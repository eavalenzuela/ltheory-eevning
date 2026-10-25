# miniaudio (vendored)

- `miniaudio.h`: miniaudio 0.11.21 (https://github.com/mackron/miniaudio, tag `0.11.21`),
  sha256 `6b2029714f8634c4d7c70cc042f45074e0565766113fc064f20cd27c986be9c9`
- `stb_vorbis.c`: stb_vorbis v1.22, from miniaudio's `extras/` at the same tag,
  sha256 `4c7cb2ff1f7011e9d67950446b7eb9ca044f2e464d76bfbb0b84dd2e23e65636`
- `miniaudio.c`: the translation unit that compiles both

Both are public domain (Unlicense) or MIT-0 / MIT; see `LICENSE` and the end of
`stb_vorbis.c`. The engine's backend is `src/liblt/Module/SoundEngine/Miniaudio.cpp`.
