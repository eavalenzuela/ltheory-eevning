# Releases, the launcher and the LAN's distribution

The owner's ruling (2026-11-14): the game is packaged for Windows and handed out on the LAN from the NAS, the way another of their projects is. Their answers: the Windows version is cross-built on the laptop with MinGW; the launcher is that project's, adapted; a release is published to the NAS only when they ask for one; and the game is called **Limitless Space**.

## The Windows build

`script/build-windows [SOURCE [OUT]]` cross-compiles the game for Windows (x86_64) with MinGW-w64 (`cmake/mingw-w64.cmake`), into `build/windows/bin/launch.exe`. The Linux programs in `bin/` are not touched.

- The compilers are the system's if they are there, else a copy unpacked from Ubuntu's packages without root in `~/.local/opt/mingw` (the script's header says how).
- The engine is one static library there, linked into the program, with the compiler's own runtime linked in too: the `.exe` needs nothing beside it but `resource/`.
- GLEW is compiled from `ext/glew` (2.2.0, with its own header in place of the old one in `include/`), and FreeType is the copy SFML carries for MinGW.
- Only the game is built: `luaucheck` and `ltcore` are for whoever works on it, on Linux.
- A program started with nothing said, under any name but `launch`, is the game: an install's `LimitlessSpace.exe` and `limitless-space` are `launch` under another name.

## A release

`script/publish [--local]` builds the last commit, clean (a git worktree in `build/publish/src`: what is not committed is not released), for Linux and for Windows as one version, `<date>-<commit>`. The title is the committed `RELEASE_TITLE` at the top of the repository.

It stages the distribution in `build/publish/dist`:

```
index.html                  the portal: the release, its changes since the last, the launchers, three steps
manifest.json               {release, title, files: [{p, s, h (SHA-256), x (a Linux program)}]}
LimitlessSpaceLauncher.exe  limitless-space-launcher      (to download)
files/                      an install's tree:
  LimitlessSpace.exe  limitless-space  liblt.so  LimitlessSpaceLauncher.exe  limitless-space-launcher
  resource/  LICENSE  NOTICE.md
```

With `--local` that is all, and nothing leaves the machine: `python3 -m http.server -d build/publish/dist 5008` serves it to try the launcher against.

Without it, the release is tagged here (`release/<release>`, not pushed: the repository goes to its remote when its owner says) and synced to the NAS over SSH, the manifest last, so that a launcher never sees a release whose files are not there yet. Where the NAS is is not in the repository: `LT_NAS_HOST` and `LT_NAS_USER`, from the environment or from `.env`.

## The launcher (`tools/launcher`)

A small program of its own (Rust; it cross-builds for Windows in seconds). The install is its own folder:

- It asks the distribution for `manifest.json`, checks each file (size and hash; what it has checked before is in `.limitless-install.json`, so a later run reads only the files whose size or time changed), fetches what is missing or different six at a time into `<file>.part` (carried on with a range after a break; checked against the hash before it is put in place), removes files a release dropped (only those it installed), and starts the game for its system from that folder. The NAS unreachable but something installed: it starts that.
- Its own update: the new one downloaded beside it, the running one renamed `.old` (Windows lets a running program be renamed, not replaced), removed next time.
- Where the distribution is: `launcher.txt` beside it (`url = …`, written on the first run, or by `--url`), else the address it was built with (`LT_DIST_URL`). `--no-play`: update only.
- What the game saves (`save/`: saved games, settings) is in the same folder, and is nothing the launcher installed: an update leaves it alone.

## The game's window

How the window opens is a setting (the options' Window; `window=` in `save/settings.txt`, which the program reads as it starts, so a change is for the next start): **Automatic** (a window of 1920 by 1080 where the screen is bigger than that, and otherwise the screen's own size with no border), **Fits the screen** (always that), or a window of **1920 by 1080** or **2560 by 1440**. A run that is a script's, or is given `--size`, is 1920 by 1080 as it always was. `LT_OFFSCREEN_SIZE=WxH script/offscreen ... --size WxH` shows the interface at another size where nobody sees it.

## The NAS

`deploy/compose.yml` is the drop-in for the NAS's own repository (`services/ltheory/compose.yml`): one static file server (`caddy file-server`, ranges, no listing) over `/tank/ltheory/dist` on port 5008. The game has no server: it is played on the machine it is installed on.

The first time: the folder made on the NAS, the service added to its repository and started (`make ltheory`), then `script/publish`. After that a publish only syncs files.

## What a real Windows machine showed

The first release was checked under Wine, which draws with this machine's own driver. On the owner's Windows machine (an AMD driver) the star's shader was refused: it used `active` as a name, which later versions of GLSL keep for themselves, and that driver holds a GLSL 1.20 shader to it. Wine could not have shown it. Since then:

- `script/shaderlint` checks every shader for such names and compiles each with the Khronos reference compiler, strictly as GLSL 1.20 and as a current GLSL. What it found and is mended: `active` and `sample` used as names (the star, the lighting every lit thing uses, the font and irradiance bakes), a texture lookup that wants an extension asked for, macros carried over several lines, a stray semicolon and a missing one.
- A shader that fails no longer stops the game to wait for a key: it says what the driver's compiler said, prints the shader once, and goes on, so that one run shows every shader that fails.
- The Windows game asks for the screen's own pixels (a guess at the next thing: with Windows' text scaled to 125%, a program that does not ask is told the screen is smaller than it is).

With that it ran there, and showed the next thing: ships and station modules in large dark rectangles, square to the screen. A pixel worked out as no number at all (a division of nothing by nothing, an angle asked of no direction) is one black dot; but the bloom blurs the bright picture at a low size, and blurs such a pixel into a rectangle. This machine's driver turns such a thing into a number wherever a shader takes a minimum, a maximum or a clamp; that one's lets it through. It was reproduced here by putting such pixels in on purpose, behind those accidents. Since then:

- `asNumber` and `asLight` (`common/global.jsl`) say what min, max and clamp do not: what is no number is nothing. They are written as comparisons, which such a thing fails every one of. Every fragment shader's result goes through the first; albedo, the lighting passes' results, what the bloom takes in, blurs and puts back, and what the tonemap takes in go through the second.
- The places such things came from: the normal a surface is stored by took an angle with `atan(0, 0)` for a face square to the world (every flat face of a station module that is not turned); a root of a number that may be a hair under nothing; light bent into ice that cannot get in.
- Checked here: with such pixels put in ahead of the guards, the rectangles are gone and only the pixels themselves are dark; and all ten goldens match, so nothing that was right has changed.

## The icon, the log and the notes

- `script/icon` draws the game's icon (a stand-in mark until the owner has one of their own: `script/icon PICTURE.png` makes the files from a picture) and writes `resource/icon/limitless-space.png` and `.ico`, both committed. The Windows programs have it compiled in (the game by CMake, the launcher by its `build.rs`), the game's window sets it as it opens, and the Linux desktop's entry points at the install's copy.
- The Windows game is a program with no console of its own. An installed game, started with nothing said (on either system), keeps what it says in `log.txt` in its folder, as it is said: the first thing to ask for when something goes wrong.
- `RELEASE_NOTES.md`, at the top of the repository, says what each release brings in words for whoever plays it, the newest first. The portal page shows its first section as the release's own and the next three under it; a publish whose notes still begin with the last release's section says so. With no notes the commits since the last release stand in.

## Not yet

- An interface that fits a screen smaller than 1920 by 1080: it is laid out in pixels for that size and more, and on a smaller screen its panels lie over one another. (It wants drawing at a scale, which is not built.)
- The Linux build is the laptop's own: it wants the same libraries the laptop has.
