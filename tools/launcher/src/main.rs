//! The launcher (docs/distribution.md): installs and updates the game from the NAS's distribution
//! (`script/publish`), then starts it. Its source began as the launcher of another of the owner's projects, with
//! this game's names put in and what a game with a server needs taken out.
//!
//! - The install is the launcher's own folder: put `LimitlessSpaceLauncher.exe` (or `limitless-space-launcher`) in
//!   an empty folder and run it. It asks the distribution for `manifest.json` (every file of the release: path, size,
//!   SHA-256), fetches what's missing or changed (several at once, resuming a broken download), removes what a
//!   release dropped, and starts the game: `LimitlessSpace.exe` on Windows, `limitless-space` on Linux, both in every
//!   install.
//! - What it has checked is kept in `.limitless-install.json` (each file's size, time and hash), so a run after the
//!   first only reads the files that changed.
//! - Where the distribution is: `launcher.txt` beside it (`url = http://…/`), else the address it was built with.
//! - `limitless-launcher manifest <dir> --release R [--title T]`: the publishing side: `<dir>/manifest.json` for the
//!   tree `<dir>/files` (following links), hashes kept in `<dir>/../hashes.json` between publishes.

use std::collections::BTreeMap;
use std::io::{BufRead, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

const RELEASE: &str = match option_env!("LT_RELEASE") {
    Some(r) => r,
    None => "dev",
};
/// The distribution's address, as `script/publish` built it in.
const BUILT_URL: Option<&str> = option_env!("LT_DIST_URL");
const STATE: &str = ".limitless-install.json";
/// What the game is called, and the programs of an install: the game for each system.
const NAME: &str = "Limitless Space";
const GAME_WINDOWS: &str = "LimitlessSpace.exe";
const GAME_LINUX: &str = "limitless-space";
const CONFIG: &str = "launcher.txt";
/// Downloads at once.
const LANES: usize = 6;
// The most a manifest may be (bytes): a quarter of a million files is a few tens of megabytes.
const MANIFEST_MOST: u64 = 64 << 20;

/// A release: its files.
#[derive(Debug, Clone, Serialize, Deserialize)]
struct Manifest {
    release: String,
    /// The release's title ("Limitless Space 0.1"), if it has one.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    title: String,
    files: Vec<Entry>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Entry {
    /// Its path in the install (`/`-separated), size and SHA-256.
    p: String,
    s: u64,
    h: String,
    /// A program to mark executable (Linux).
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    x: bool,
}

/// A file already checked: its size and modification time then, and its hash.
#[derive(Debug, Clone, Serialize, Deserialize)]
struct Known {
    s: u64,
    m: u64,
    h: String,
}

/// What the install holds (the launcher's record).
#[derive(Debug, Default, Serialize, Deserialize)]
struct State {
    release: String,
    files: BTreeMap<String, Known>,
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let r = if args.first().is_some_and(|a| a == "manifest") { manifest(&args[1..]) } else { launch(&args) };
    if let Err(e) = r {
        eprintln!("\nerror: {e}");
        // (Started by a double-click on Windows: keep its window open to be read.)
        if cfg!(windows) {
            eprintln!("Press Enter to close.");
            let _ = std::io::stdin().lock().read_line(&mut String::new());
        }
        std::process::exit(1);
    }
}

fn mtime(meta: &std::fs::Metadata) -> u64 {
    meta.modified().ok().and_then(|t| t.duration_since(UNIX_EPOCH).ok()).map_or(0, |d| d.as_nanos() as u64)
}

/// A file's SHA-256 (hex), from `known` if its size and time haven't changed since.
fn hash(path: &Path, rel: &str, known: &Mutex<BTreeMap<String, Known>>) -> std::io::Result<String> {
    let meta = std::fs::metadata(path)?;
    let (s, m) = (meta.len(), mtime(&meta));
    if let Some(k) = known.lock().unwrap().get(rel).filter(|k| k.s == s && k.m == m) {
        return Ok(k.h.clone());
    }
    let h = hash_file(path)?;
    known.lock().unwrap().insert(rel.to_string(), Known { s, m, h: h.clone() });
    Ok(h)
}

/// Whether a manifest path is one that stays inside the install folder: relative, `/`-separated, with no empty, `.`
/// or `..` part, no drive, backslash, colon or NUL. (A path such as `../x` or `/home/x` would be written, made
/// executable or removed outside it.)
fn safe_rel(p: &str) -> bool {
    !p.is_empty()
        && !p.starts_with('/')
        && !p.contains(['\\', ':', '\0'])
        && p.split('/').all(|part| !part.is_empty() && part != "." && part != "..")
}

fn hash_file(path: &Path) -> std::io::Result<String> {
    let mut f = std::fs::File::open(path)?;
    let mut sha = Sha256::new();
    let mut buf = vec![0u8; 1 << 20];
    loop {
        let n = f.read(&mut buf)?;
        if n == 0 {
            break;
        }
        sha.update(&buf[..n]);
    }
    Ok(sha.finalize().iter().map(|b| format!("{b:02x}")).collect())
}

fn gb(n: u64) -> String {
    format!("{:.2} GB", n as f64 / 1e9)
}

// --- Publishing: the manifest. ---

fn manifest(args: &[String]) -> Result<(), String> {
    let dir = PathBuf::from(args.first().ok_or("manifest <dir> --release R [--title T]")?);
    let opt = |k: &str| args.iter().position(|a| a == k).and_then(|i| args.get(i + 1)).cloned();
    let release = opt("--release").ok_or("--release")?;
    let title = opt("--title").unwrap_or_default();
    let root = dir.join("files");
    let cache_file = dir.parent().unwrap_or(&dir).join("hashes.json");
    let known: Mutex<BTreeMap<String, Known>> = Mutex::new(std::fs::read_to_string(&cache_file).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_default());
    let mut paths = Vec::new();
    walk(&root, &root, &mut paths).map_err(|e| format!("{}: {e}", root.display()))?;
    paths.sort();
    let total = paths.len();
    let started = Instant::now();
    let mut files = Vec::with_capacity(total);
    for (i, rel) in paths.iter().enumerate() {
        let p = root.join(rel);
        let h = hash(&p, rel, &known).map_err(|e| format!("{}: {e}", p.display()))?;
        let s = std::fs::metadata(&p).map_err(|e| e.to_string())?.len();
        // (The programs at the top without an extension: the Linux game and launcher.)
        let x = !rel.contains('/') && !rel.contains('.');
        files.push(Entry { p: rel.clone(), s, h, x });
        if i % 2000 == 0 {
            eprint!("\rhashing {i}/{total}…");
        }
    }
    let size: u64 = files.iter().map(|f| f.s).sum();
    let m = Manifest { release, title, files };
    let text = serde_json::to_string(&m).map_err(|e| e.to_string())?;
    std::fs::write(dir.join("manifest.json"), text).map_err(|e| e.to_string())?;
    let kept = known.into_inner().unwrap();
    std::fs::write(&cache_file, serde_json::to_string(&kept).map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
    eprintln!("\rmanifest: {total} files, {} ({:.0} s)", gb(size), started.elapsed().as_secs_f32());
    Ok(())
}

/// Every file under `dir` (links followed), as `/`-separated paths from `root`.
fn walk(root: &Path, dir: &Path, out: &mut Vec<String>) -> std::io::Result<()> {
    for e in std::fs::read_dir(dir)? {
        let p = e?.path();
        let meta = std::fs::metadata(&p)?;
        if meta.is_dir() {
            walk(root, &p, out)?;
        } else if meta.is_file() {
            let rel = p.strip_prefix(root).map_err(std::io::Error::other)?;
            out.push(rel.components().map(|c| c.as_os_str().to_string_lossy()).collect::<Vec<_>>().join("/"));
        }
    }
    Ok(())
}

// --- Installing, updating and starting. ---

fn install_dir() -> Result<PathBuf, String> {
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    Ok(exe.parent().ok_or("no folder")?.to_path_buf())
}

/// The distribution's address: `--url` (kept), `launcher.txt`, else the built-in one.
fn dist_url(dir: &Path, args: &[String]) -> Result<String, String> {
    let given = args.iter().position(|a| a == "--url").and_then(|i| args.get(i + 1)).cloned();
    let saved = std::fs::read_to_string(dir.join(CONFIG)).ok().and_then(|t| t.lines().find_map(|l| l.trim().strip_prefix("url").map(|v| v.trim().trim_start_matches('=').trim().trim_matches('"').to_string())));
    let url = given.clone().or(saved).or(BUILT_URL.map(str::to_string)).ok_or("Where's the distribution? Run with --url http://<nas>:<port>/")?;
    let url = if url.ends_with('/') { url } else { format!("{url}/") };
    if given.is_some() || !dir.join(CONFIG).exists() {
        let _ = std::fs::write(dir.join(CONFIG), format!("url = {url}\n"));
    }
    Ok(url)
}

/// The HTTP client, one for the whole run: its connections are kept and reused (a new one for each of a quarter of a
/// million files ran out of ports). A slow or vanished NAS gives up rather than hangs.
fn agent() -> ureq::Agent {
    // (no redirects: what is fetched comes from the server named, and nowhere else)
    ureq::AgentBuilder::new()
        .timeout_connect(Duration::from_secs(15))
        .timeout_read(Duration::from_secs(60))
        .max_idle_connections_per_host(LANES * 2)
        .redirects(0)
        .build()
}

fn fetch_manifest(http: &ureq::Agent, url: &str) -> Result<Manifest, String> {
    let r = http.get(&format!("{url}manifest.json")).call().map_err(|e| e.to_string())?;
    // (no bigger than any manifest could be: a server can't fill the disk or the memory with one)
    let mut text = String::new();
    r.into_reader().take(MANIFEST_MOST).read_to_string(&mut text).map_err(|e| e.to_string())?;
    let m: Manifest = serde_json::from_str(&text).map_err(|e| format!("manifest.json: {e}"))?;
    // (every path inside the install folder, and only a program at its top made executable)
    for e in &m.files {
        if !safe_rel(&e.p) || (e.x && e.p.contains('/')) {
            return Err(format!("manifest.json: refusing the path {:?}", e.p));
        }
    }
    Ok(m)
}

fn launch(args: &[String]) -> Result<(), String> {
    let dir = install_dir()?;
    println!("{NAME} launcher {RELEASE} — {}", dir.display());
    let own = std::env::current_exe().ok().and_then(|p| p.file_name().map(|n| n.to_string_lossy().to_string())).unwrap_or_default();
    let _ = std::fs::remove_file(dir.join(format!("{own}.old")));
    let url = dist_url(&dir, args)?;
    let state_file = dir.join(STATE);
    let mut state: State = std::fs::read_to_string(&state_file).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_default();
    let http = agent();
    let m = match fetch_manifest(&http, &url) {
        Ok(m) => m,
        Err(e) if !state.release.is_empty() => {
            println!("Couldn't reach {url} ({e}); starting what's installed ({}).", state.release);
            return play(&dir, args);
        }
        Err(e) => return Err(format!("Couldn't reach {url}: {e}")),
    };
    let named = if m.title.is_empty() { String::new() } else { format!("{}, ", m.title) };
    println!("Release {named}{} (installed: {}).", m.release, if state.release.is_empty() { "nothing yet" } else { &state.release });
    let known = Mutex::new(std::mem::take(&mut state.files));
    // What to fetch: missing, or not as the manifest has it.
    let mut want = Vec::new();
    let n = m.files.len();
    for (i, e) in m.files.iter().enumerate() {
        let p = dir.join(&e.p);
        // (a file the last release didn't put here is hashed but not taken on: only what this launcher fetched, or
        // fetched before, is ever its to remove)
        let ours = known.lock().unwrap().contains_key(&e.p);
        let ok = std::fs::metadata(&p).is_ok_and(|meta| meta.len() == e.s)
            && if ours { hash(&p, &e.p, &known) } else { hash_file(&p) }.is_ok_and(|h| h == e.h);
        if !ok {
            want.push(e.clone());
        }
        if i % 2000 == 0 {
            print!("\rChecking {i}/{n}…");
            let _ = std::io::stdout().flush();
        }
    }
    println!("\rChecked {n} files.        ");
    let save = |files: BTreeMap<String, Known>, release: &str| {
        let s = State { release: release.to_string(), files };
        let _ = std::fs::write(&state_file, serde_json::to_string(&s).unwrap_or_default());
    };
    if !want.is_empty() {
        let total: u64 = want.iter().map(|e| e.s).sum();
        println!("Fetching {} files, {}.", want.len(), gb(total));
        let failed = download(&http, &url, &dir, &own, want, &known, total);
        if !failed.is_empty() {
            save(known.into_inner().unwrap(), &state.release);
            return Err(format!("{} files didn't come ({}…); run it again to carry on.", failed.len(), failed.iter().take(3).cloned().collect::<Vec<_>>().join(", ")));
        }
    }
    // What the release dropped (only what we put here: the rest of the folder is left alone).
    let mut files = known.into_inner().unwrap();
    let keep: std::collections::HashSet<&str> = m.files.iter().map(|e| e.p.as_str()).collect();
    let gone: Vec<String> = files.keys().filter(|p| !keep.contains(p.as_str())).cloned().collect();
    for p in &gone {
        // (an old record's entry that would reach outside the folder is forgotten, not acted on)
        if safe_rel(p) {
            let _ = std::fs::remove_file(dir.join(p));
        }
        files.remove(p);
    }
    if !gone.is_empty() {
        println!("Removed {} files the release dropped.", gone.len());
    }
    save(files, &m.release);
    println!("Up to date: {}.", m.release);
    play(&dir, args)
}

/// Fetch `want` into `dir`, several at once; the paths that failed.
fn download(http: &ureq::Agent, url: &str, dir: &Path, own: &str, want: Vec<Entry>, known: &Mutex<BTreeMap<String, Known>>, total: u64) -> Vec<String> {
    let queue = Mutex::new(want);
    let failed = Mutex::new(Vec::new());
    let (got, done, finished) = (AtomicU64::new(0), AtomicUsize::new(0), AtomicBool::new(false));
    let count = queue.lock().unwrap().len();
    std::thread::scope(|s| {
        s.spawn(|| {
            let start = Instant::now();
            while !finished.load(Ordering::Relaxed) {
                std::thread::sleep(Duration::from_millis(500));
                let g = got.load(Ordering::Relaxed);
                let rate = g as f64 / start.elapsed().as_secs_f64().max(0.1) / 1e6;
                print!("\r  {} / {}  ({}/{} files, {rate:.0} MB/s)   ", gb(g), gb(total), done.load(Ordering::Relaxed), count);
                let _ = std::io::stdout().flush();
            }
        });
        let lanes: Vec<_> = (0..LANES)
            .map(|_| {
                s.spawn(|| {
                    loop {
                        let Some(e) = queue.lock().unwrap().pop() else { break };
                        let mut last = String::new();
                        let ok = (0..3).any(|_| match fetch(http, url, dir, own, &e, &got) {
                            Ok(()) => true,
                            Err(err) => {
                                last = err;
                                false
                            }
                        });
                        if ok {
                            let p = dir.join(&e.p);
                            if let Ok(meta) = std::fs::metadata(&p) {
                                known.lock().unwrap().insert(e.p.clone(), Known { s: meta.len(), m: mtime(&meta), h: e.h.clone() });
                            }
                        } else {
                            failed.lock().unwrap().push(format!("{} ({last})", e.p));
                        }
                        done.fetch_add(1, Ordering::Relaxed);
                    }
                })
            })
            .collect();
        for l in lanes {
            let _ = l.join();
        }
        finished.store(true, Ordering::Relaxed);
    });
    println!();
    failed.into_inner().unwrap()
}

/// One file: into `<path>.part` (carried on from where a broken one stopped, if the server can), checked, then put in
/// place. The launcher itself is swapped in beside the running one (renamed `.old`: Windows lets a running program be
/// renamed, not replaced).
fn fetch(http: &ureq::Agent, url: &str, dir: &Path, own: &str, e: &Entry, got: &AtomicU64) -> Result<(), String> {
    let dest = dir.join(&e.p);
    if let Some(parent) = dest.parent() {
        std::fs::create_dir_all(parent).map_err(|x| x.to_string())?;
    }
    let part = PathBuf::from(format!("{}.part", dest.display()));
    let have = std::fs::metadata(&part).map_or(0, |m| m.len()).min(e.s);
    let encoded: String = e.p.split('/').map(encode).collect::<Vec<_>>().join("/");
    let mut req = http.get(&format!("{url}files/{encoded}"));
    if have > 0 && have < e.s {
        req = req.set("Range", &format!("bytes={have}-"));
    }
    let r = req.call().map_err(|x| x.to_string())?;
    // (A server that ignores the range sends it all: start over.)
    let resumed = r.status() == 206 && have > 0;
    let mut f = std::fs::OpenOptions::new().create(true).write(true).append(resumed).truncate(!resumed).open(&part).map_err(|x| x.to_string())?;
    if resumed {
        got.fetch_add(have, Ordering::Relaxed);
    }
    // (no more than the file is: a server can't fill the disk with one)
    let mut body = r.into_reader().take(e.s.saturating_sub(if resumed { have } else { 0 }) + 1);
    let mut buf = vec![0u8; 1 << 18];
    loop {
        let n = body.read(&mut buf).map_err(|x| x.to_string())?;
        if n == 0 {
            break;
        }
        f.write_all(&buf[..n]).map_err(|x| x.to_string())?;
        got.fetch_add(n as u64, Ordering::Relaxed);
    }
    drop(f);
    if std::fs::metadata(&part).map_or(0, |m| m.len()) > e.s {
        let _ = std::fs::remove_file(&part);
        return Err("it was bigger than the manifest said".into());
    }
    let h = hash_file(&part).map_err(|x| x.to_string())?;
    if h != e.h {
        let _ = std::fs::remove_file(&part);
        return Err("its hash didn't match".into());
    }
    if e.p == own {
        let _ = std::fs::rename(&dest, dir.join(format!("{own}.old")));
    }
    std::fs::rename(&part, &dest).map_err(|x| x.to_string())?;
    #[cfg(unix)]
    if e.x {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(&dest, std::fs::Permissions::from_mode(0o755));
    }
    Ok(())
}

/// A path part for a URL.
fn encode(s: &str) -> String {
    s.bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => (b as char).to_string(),
            _ => format!("%{b:02X}"),
        })
        .collect()
}

/// On Linux, `~/.local/share/applications/limitless-space.desktop`: the game in the desktop's app list, this
/// launcher behind it, and the install's icon (`resource/icon/limitless-space.png`) its icon. Rewritten when it
/// differs (the install moved); nothing elsewhere.
fn desktop_entry(dir: &Path) {
    if !cfg!(target_os = "linux") {
        return;
    }
    let (Some(home), Ok(exe)) = (std::env::var_os("HOME"), std::env::current_exe()) else { return };
    let apps = PathBuf::from(home).join(".local/share/applications");
    let icon = dir.join("resource/icon/limitless-space.png");
    let text = format!(
        "[Desktop Entry]\nType=Application\nName={NAME}\nExec=\"{}\"\nPath={}\nIcon={}\nTerminal=false\nCategories=Game;\n",
        exe.display(),
        dir.display(),
        if icon.exists() { icon.display().to_string() } else { "applications-games".into() },
    );
    let file = apps.join("limitless-space.desktop");
    if std::fs::read_to_string(&file).ok().as_deref() != Some(text.as_str())
        && std::fs::create_dir_all(&apps).and_then(|_| std::fs::write(&file, &text)).is_ok()
    {
        println!("Added \"{NAME}\" to your applications.");
    }
    // And the save editor (App/saveedit), where the install has it: its own program, run in the install.
    let editor = dir.join("limitless-space-saveedit");
    if !editor.exists() {
        return;
    }
    let text = format!(
        "[Desktop Entry]\nType=Application\nName={NAME} Save Editor\nExec=\"{}\"\nPath={}\nIcon={}\nTerminal=false\nCategories=Game;\n",
        editor.display(),
        dir.display(),
        if icon.exists() { icon.display().to_string() } else { "applications-games".into() },
    );
    let file = apps.join("limitless-space-saveedit.desktop");
    if std::fs::read_to_string(&file).ok().as_deref() != Some(text.as_str())
        && std::fs::create_dir_all(&apps).and_then(|_| std::fs::write(&file, &text)).is_ok()
    {
        println!("Added \"{NAME} Save Editor\" to your applications.");
    }
}

/// Start the game (`--no-play`: don't), from its own folder: its files, and what it saves, are beside it.
fn play(dir: &Path, args: &[String]) -> Result<(), String> {
    desktop_entry(dir);
    if args.iter().any(|a| a == "--no-play") {
        return Ok(());
    }
    let exe = dir.join(if cfg!(windows) { GAME_WINDOWS } else { GAME_LINUX });
    let mut cmd = std::process::Command::new(&exe);
    cmd.current_dir(dir);
    cmd.spawn().map_err(|e| format!("{}: {e}", exe.display()))?;
    println!("Starting {NAME}…");
    std::thread::sleep(Duration::from_secs(1));
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A tree published and fetched: the manifest's files come over, a changed one comes again, a dropped one goes.
    #[test]
    fn publish_and_update() {
        let base = std::env::temp_dir().join(format!("limitless-launcher-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        let dist = base.join("dist");
        std::fs::create_dir_all(dist.join("files/data/db")).unwrap();
        std::fs::write(dist.join("files/data/db/a.xml"), "alpha").unwrap();
        std::fs::write(dist.join("files/limitless-space"), "program").unwrap();
        let args = |r: &str| ["", "--release", r, "--title", "A title"].iter().map(|s| s.to_string()).collect::<Vec<_>>();
        let mut a = args("one");
        a[0] = dist.display().to_string();
        manifest(&a).unwrap();
        let m: Manifest = serde_json::from_str(&std::fs::read_to_string(dist.join("manifest.json")).unwrap()).unwrap();
        assert_eq!(m.files.len(), 2);
        assert_eq!(m.title, "A title");
        assert!(m.files.iter().any(|e| e.p == "limitless-space" && e.x) && m.files.iter().any(|e| e.p == "data/db/a.xml" && !e.x));
        assert_eq!(m.files.iter().find(|e| e.p == "data/db/a.xml").unwrap().h, hash_file(&dist.join("files/data/db/a.xml")).unwrap());
        assert_eq!(encode("a b+c"), "a%20b%2Bc");
        let _ = std::fs::remove_dir_all(&base);
    }
}
