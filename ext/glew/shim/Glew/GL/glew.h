/* The engine asks for "Glew/GL/glew.h" (its own old copy, in include/).
   A build that compiles GLEW from ext/glew (Windows, with MinGW) is
   given this one first, so that the header is the library's own. */
#include "../../../include/GL/glew.h"
