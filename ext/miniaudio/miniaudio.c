/* The single translation unit that compiles miniaudio, with stb_vorbis for
   Ogg Vorbis decoding, following miniaudio's documented integration. */

#define STB_VORBIS_HEADER_ONLY
#include "stb_vorbis.c"

#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#undef STB_VORBIS_HEADER_ONLY
#include "stb_vorbis.c"
