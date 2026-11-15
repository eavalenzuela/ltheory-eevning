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

## Not yet

- An interface that fits a screen smaller than 1920 by 1080: it is laid out in pixels for that size and more, and on a smaller screen its panels lie over one another. (It wants drawing at a scale, which is not built.)
- An icon for the programs, and for the Linux desktop's entry.
- A list of what changed for players (the portal lists the commits since the last release).
- The Linux build is the laptop's own: it wants the same libraries the laptop has.
