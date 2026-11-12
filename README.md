# Limit Theory (old engine): an offline space sandbox

A single-player space game built on the old C++ Limit Theory engine. You fly by giving your ship orders, and make a living mining, building, trading, running missions and fighting pirates in a generated galaxy of up to 400 systems.

It is a work in progress. The systems are playable from end to end; the ships, stations and sounds are first-pass placeholders ("grey box").

## Where this comes from

This is a fork of the old C++ implementation of Limit Theory, its engine (LTE) and its scripting language, written by Josh Parnell from 2012 to 2015 and released into the public domain. What has changed in this fork:

- The scripts are [Luau](https://luau.org) (typed Lua); the engine's own scripting language is gone. See `docs/luau.md`.
- It builds and runs on 64-bit Linux.
- There is a new game on top of the engine (`bin/launch game`). All of its state and rules live in a deterministic, engine-free Luau core, and the engine draws what the core says. The old prototype is still in the tree as `ltheory`.

`docs/roadmap.md` has the plan and, at its top, what is built so far.

## What is in the game

- **Flight by orders**: approach, orbit, keep at range, align, warp, dock, jump through gates, with an autopilot and a star map.
- **Ships and fitting**: frigates to battleships and haulers for four human factions and the pirates, a freighter for anybody, with turrets, launchers, drones, electronic warfare, cloaks, rigs and tech 2 gear.
- **Combat**: target locking, tracking and range, shields, armour and hull, wrecks to loot and salvage, insurance, and a capsule to get home in.
- **Industry**: mining, refining, manufacturing from blueprints, research and invention, and planetary colonies.
- **Trade**: a market at each station with buy and sell orders, where prices differ by who owns the station.
- **Things to do**: career agents who show a new pilot the ropes, daily jobs, combat camps, mining contracts and courier contracts from agents, standings and loyalty stores, sites to scan down, derelicts and vaults to hack, gas to harvest and make into boosters.
- **A character**: skills that train in real time, including while the game is closed, and implants.
- **Company**: hired pilots who follow, mine, haul, patrol and guard, with drones of their own; a corporation of your own for them to work for, with its own account and books; starbases of your own with anchored modules.
- **A world**: security that falls away from each faction's homeworld, police and gate guns where order is kept, other ships going about their business.
- **Saves**, music, and sound.

## Requirements

64-bit Linux is what this fork is built and tested on (Ubuntu, GCC 15, CMake 4.2, Mesa). The original targeted Windows with Visual Studio; that has not been tried here.

On Debian or Ubuntu:

```sh
sudo apt install build-essential cmake python3 git-lfs libglew-dev libglu1-mesa-dev \
  libfreetype-dev libx11-dev libxrandr-dev libudev-dev libgl-dev
```

To run the checks (not needed to play): `sudo apt install sway xwayland python3-pil`. The scripted play-throughs draw on a hidden desktop that `sway` provides; without it they fall back on `xvfb-run`, which is much slower.

Audio goes through the vendored miniaudio, so no audio libraries are needed. With no audio device the game runs silently.

## Getting the source

The art, fonts and sounds are stored with Git LFS, and SFML and Luau are submodules. Install LFS before cloning, or most resources will be broken in ways that are hard to recognise.

```sh
git lfs install
git clone --recursive <this repository's URL> ltheory
cd ltheory
```

## Building

```sh
python3 configure.py          # generate the build files (CMake)
python3 configure.py build    # compile; the first time takes a while
```

This leaves three programs in `bin/`: `launch` (runs an app in a window), `ltcore` (runs engine-free scripts with no window) and `luaucheck` (the type checker). Scripts are read at start, so changing a `.luau` file needs no rebuild.

## Playing

```sh
bin/launch game
```

On a laptop with two graphics cards, `DRI_PRIME=1 bin/launch game` runs it on the faster one.

The game opens on a menu: continue, new game (pick a seed and a galaxy size), load, options (sound on or off, and the loudness of effects and music), quit. A new game starts you docked at a station with a small ship. That station has five career agents (the Careers tab), who each teach a way of making a living in a few short lessons and pay for them; the Guide button lists everything else there is to do, and shows the lessons you have in hand while you are in space.

| | |
|---|---|
| Left click | Select something in space or on the overview |
| Right click | A menu of what can be done about it, with distances for orbit, keep at range and warp |
| Double click (overview) | Approach it, or warp to it if it is far off |
| Double click (in space) | Fly the way the cursor points; on a bracket, as on its row of the overview |
| Left drag, mouse wheel | Turn the camera, zoom |
| Q, W, E, A | Approach, orbit, keep at range, align |
| S, D | Warp to, dock or jump |
| L, Tab | Lock or unlock, pick the next hostile ship |
| F1 to F12 | Switch the fitted modules on and off |
| Space | Stop |
| C, M | Camera follows what is selected, the star map |
| P, Escape | Pause, the menu |
| F9, F10 | Quick save, quick load |

Docking saves the game. Saves and settings are kept in `save/`, which git ignores.

## Other apps and tools

`bin/launch <name>` runs `resource/script/App/<name>.luau`. Besides `game` there are the old prototype (`ltheory`) and the original demos and tools, among them `war`, `dogfight`, `rails`, `observatory`, `model`, `platemesh` and `map`.

| | |
|---|---|
| `script/check` | Says whether the tree is healthy: type check, engine-free specs, about thirty-five scripted play-throughs of the game, and screenshot comparisons. It takes about a quarter of an hour. Its fifty or so windows are opened where nobody sees them (`script/offscreen`); `--on-desktop` shows them, and `--fast` skips everything that needs one. |
| `bin/luaucheck` | Type-checks every script in strict mode. |
| `bin/ltcore Tool/specs` | Runs the engine-free test suites. |
| `script/viewer` | One window for looking at hulls, stations, planets and effects, and for taking pictures of them. |
| `script/offscreen` | Runs a command that opens windows on a desktop of its own with no screen (a headless `sway`, on the same graphics card). A scripted or hidden run of `bin/launch` goes through it by itself. |
| `script/soundgen` | Makes the game's own sounds and music from the written descriptions in `resource/sound/made/sounds.txt`. |
| `script/modelgen` | Writes the hull models under `resource/model` (Wavefront OBJ, which Blender opens) from numbers. The game reads a hull from such a file, or from a binary glTF (`.glb`) made anywhere. |

`docs/tools.md` covers these and the rest, and `docs/harness.md` the scripted harness the play-throughs use.

## Where things are

| | |
|---|---|
| `resource/script/Core/` | The game: all state and rules, engine-free and deterministic (`docs/design/core.md`) |
| `resource/script/Game/` | What the player sees and hears: the scene, the interface, sound and music |
| `resource/script/App/` | The apps, `game.luau` among them |
| `resource/script/Tool/` | Engine-free tools: the spec runner, the simulation runs |
| `src/` | The engine (`liblt`), the launcher, `ltcore` and `luaucheck` |
| `resource/` | Shaders, fonts, textures, sounds, and the hull models that are read from files |
| `test/` | Scripted play-throughs (`scenario/`) and stored screenshots (`golden/`) |
| `docs/` | The roadmap, design notes, and a catalogue of the old codebase |
| `ext/`, `extbin/`, `extlib/` | Third-party code and libraries |

## Sound and music

The original engine's sounds are in `resource/sound`. The sounds and music under `resource/sound/made` were generated from text descriptions with ElevenLabs' sound-effect and music services, by `script/soundgen`; the descriptions are kept beside them in `sounds.txt`.

Nothing is needed to play them. Making new ones needs an ElevenLabs API key in the environment or in a `.env` file at the top of the repository (`ELEVENLABS_API_KEY=...`), which git ignores, and spends credits on that account.

## Licence

The code, and everything it makes, is in the public domain (see `LICENSE`). Some files came from elsewhere and keep their own terms: third-party code, the fonts, and some of the original engine's sounds. `NOTICE.md` says which.
