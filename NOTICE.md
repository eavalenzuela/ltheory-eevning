# What is whose

`LICENSE` places this repository's code in the public domain. That covers what its authors wrote and what that code makes. Some files here came from elsewhere and keep the terms they came with. This file says which, as far as it is known.

## Covered by `LICENSE`

- The engine and tools in `src/`, and everything in `resource/script/` and `resource/shader/`.
- Everything the game shows that those make when it runs: hulls, stations, planets, stars, effects, icons and the interface. Nearly all of it is made as the game runs and is stored nowhere.
- `docs/`, `script/` and `test/`.
- The hull models in `resource/model`, which `script/modelgen` writes: from numbers, and for the Vail's battleship on a base shape (`resource/model/vail/base/battleship.glb`) that the project's owner modelled with other tools and in Blender, and publishes with the rest.

## Sounds and music made for this game

`resource/sound/made/` holds sound effects and music generated from the text descriptions in `sounds.txt`, with ElevenLabs' sound-effect and music services, by the project's owner on their own account, which carries a commercial licence (`script/soundgen`). One of them, `gate/jump.ogg`, is a generated sound joined to one of the original engine's.

`resource/sound/atmosphere/` holds sounds that the project's owner made themselves, by their own means, and put there for the game to play: radio chatter, the creaking of wrecks, a missile's impact, a small explosion. They publish them with the rest.

Under ElevenLabs' terms the account holder keeps all rights in what they generate, except as those terms expressly say otherwise. The owner puts no restriction of their own on these files and publishes them with the rest. Anyone reusing the files elsewhere should read ElevenLabs' terms, which also say how such output may be used.

## Pictures made for this game

`resource/texture/portraits/` holds the character portraits, which the project's owner made and put there for the game. They publish them with the rest.

`resource/texture/splash-art.jpg`, the picture behind the opening splash, is a picture of the game's own ships, posed and drawn by the game, redrawn by OpenAI's image service (`script/artgen`) on the project's owner's account, with one of the portraits given as the manner to draw in. Anyone reusing it elsewhere should read OpenAI's terms on generated output.

`resource/texture/icons/`, the inventory's icons (one for each kind of item), were drawn by the same service from words alone (`script/artgen kinds`, the kinds listed in `script/iconkinds.txt`), on the project's owner's account. The same terms apply.

`resource/texture/glyphs/`, the overview's and the fitting window's signs (white glyphs the game tints), and `resource/texture/factions/`, the factions' logos and their emblems (`script/artgen emblems`, from pictures in `cache/artgen/logos`), were drawn by the same service (`script/artgen glyphsheet`, from `script/overviewglyphs.txt`), on the project's owner's account. The same terms apply.

## Third-party code

| | Licence |
|---|---|
| `ext/SFML` | zlib/png (`ext/SFML/license.md`); it bundles further libraries with their own licences (`ext/SFML/extlibs`: OpenAL Soft, FLAC, Ogg, Vorbis, FreeType, stb_image). Its stb_image and FreeType are not used: `ext/stb` and `ext/freetype` are, below |
| `ext/stb` | `stb_image.h` 2.34 and `stb_image_write.h` 1.19, from github.com/nothings/stb: public domain or MIT, at your choice (in each file) |
| `ext/freetype` | FreeType 2.15.0, the release signed by its maintainer, without its `docs/`: the FreeType License or GPL 2, at your choice (`ext/freetype/LICENSE.TXT`). The Windows build compiles it |
| `ext/luau` | MIT (`ext/luau/LICENSE.txt`) |
| `ext/miniaudio` | Public domain or MIT No Attribution, at your choice (`ext/miniaudio/LICENSE`) |
| FreeType (`include/FreeType`, binaries in `extbin/`, `extlib/`) | FreeType License |
| GLEW (`include/Glew`, binaries; and its source, version 2.2.0, in `ext/glew`, which the Windows build compiles) | Modified BSD and MIT (`ext/glew/LICENSE.txt`) |
| ENet (`include/enet`, binaries) | MIT |
| zlib (`extbin/win32/zlib1.dll`) | zlib |
| libsndfile (`extbin/osx/sndfile.framework`) | LGPL 2.1 or later |
| UTF8-CPP (`include/UTF8`) | Boost Software License |
| `include/windirent.h` | MIT |
| SMAA lookup textures (`resource/texture/SMAA_*.bin`) | MIT |

## Fonts

`resource/font/` holds 38 families. All but four carry the SIL Open Font License (`OFL.txt` in each folder). Droid Sans is under the Apache License 2.0 (`LICENSE.txt`), Ubuntu Mono under the Ubuntu Font Licence (`UFL.txt`), and Noto Sans and Noto Sans CJK SC came without a licence file; Noto fonts are published under the SIL Open Font License.

## From the original repository, origin not established

These came with the original Limit Theory repository. The public-domain dedication cannot be assumed to reach them. (The original soundtrack's sound banks and a copy of the Oculus SDK's headers were of this kind too, were used by nothing, and have been removed.)

- **Sounds in `resource/sound/`** other than `made/`. Most appear to have been made for the original game. Twenty-five more carried embedded keyword tags of the kind a stock sound library adds, and were probably licensed from one. All of those have been removed, and what the game played of them is replaced by sounds made for it.
- **`include/GL/`**: old OpenGL headers for the Windows build: Microsoft's (`GL.H`, `GLU.H`, `GLAux.h`), GLUT and GLUI, each under its own terms.
- **Textures** `ice.jpg`, `rock.jpg`, `water_normals.jpg`, `lensdirt.jpg`, `tree.png`, `splash.png` and the icons in `resource/texture/`.
