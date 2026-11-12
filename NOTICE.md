# What is whose

`LICENSE` places this repository's code in the public domain. That covers what its authors wrote and what that code makes. Some files here came from elsewhere and keep the terms they came with. This file says which, as far as it is known.

## Covered by `LICENSE`

- The engine and tools in `src/`, and everything in `resource/script/` and `resource/shader/`.
- Everything the game shows that those make when it runs: hulls, stations, planets, stars, effects, icons and the interface. None of it is stored as an art file.
- `docs/`, `script/` and `test/`.

## Sounds and music made for this game

`resource/sound/made/` holds sound effects and music generated from the text descriptions in `sounds.txt`, with ElevenLabs' sound-effect and music services, by the project's owner on their own account, which carries a commercial licence (`script/soundgen`). One of them, `gate/jump.ogg`, is a generated sound joined to one of the original engine's.

The owner puts no restriction of their own on these files and publishes them with the rest. How such output may be used is also governed by ElevenLabs' terms for the plan it was made on; anyone reusing the files elsewhere should read those.

## Third-party code

| | Licence |
|---|---|
| `ext/SFML` | zlib/png (`ext/SFML/license.md`); it bundles further libraries with their own licences (`ext/SFML/extlibs`: OpenAL Soft, FLAC, Ogg, Vorbis, FreeType, stb_image) |
| `ext/luau` | MIT (`ext/luau/LICENSE.txt`) |
| `ext/miniaudio` | Public domain or MIT No Attribution, at your choice (`ext/miniaudio/LICENSE`) |
| FreeType (`include/FreeType`, binaries in `extbin/`, `extlib/`) | FreeType License |
| GLEW (`include/Glew`, binaries) | Modified BSD and MIT |
| ENet (`include/enet`, binaries) | MIT |
| zlib (`extbin/win32/zlib1.dll`) | zlib |
| libsndfile (`extbin/osx/sndfile.framework`) | LGPL 2.1 or later |
| UTF8-CPP (`include/UTF8`) | Boost Software License |
| `include/windirent.h` | MIT |
| SMAA lookup textures (`resource/texture/SMAA_*.bin`) | MIT |

## Fonts

`resource/font/` holds 38 families. All but four carry the SIL Open Font License (`OFL.txt` in each folder). Droid Sans is under the Apache License 2.0 (`LICENSE.txt`), Ubuntu Mono under the Ubuntu Font Licence (`UFL.txt`), and Noto Sans and Noto Sans CJK SC came without a licence file; Noto fonts are published under the SIL Open Font License.

## From the original repository, origin not established

These came with the original Limit Theory repository. The public-domain dedication cannot be assumed to reach them.

- **Sounds in `resource/sound/`** other than `made/`. Most appear to have been made for the original game. Twenty-five carry embedded keyword tags of the kind a stock sound library adds, and were probably licensed from one:
  `scanner/loop.wav`, `ship/ambiance/interior/1.wav`, `station/ambiance_ship_loops_14.wav`, `_15.wav`, `_16.wav`, `system/ambiance/006.wav`, `weapon/pulse5.wav`, and in `ui/`: `dragbegin.wav`, `dragend.wav`, `elementselect.wav`, `entertext.wav`, `hover.wav`, `misc/1.wav`, `misc/2.wav`, `objectmenuclose.wav`, `objectmenuopen.wav`, `open/1.wav`, `scannerclose.wav`, `scanneropen.wav`, `select/1.wav`, `select/4.wav`, `tabselect.wav`, `windowopen.wav`, `workspace_next.wav`, `workspace_prev.wav`.
- **`resource/music/`**: the original game's soundtrack as FMOD sound banks. Nothing here can play them.
- **`include/OVR/`**: headers from the Oculus SDK, under that SDK's own licence. Nothing in the build uses them.
- **`include/GL/`**: old OpenGL headers for the Windows build: Microsoft's (`GL.H`, `GLU.H`, `GLAux.h`), GLUT and GLUI, each under its own terms.
- **Textures** `ice.jpg`, `rock.jpg`, `water_normals.jpg`, `lensdirt.jpg`, `tree.png`, `splash.png` and the icons in `resource/texture/`.
