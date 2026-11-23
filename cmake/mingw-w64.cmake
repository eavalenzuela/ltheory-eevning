# Cross-compiling for Windows (x86_64) from Linux with MinGW-w64:
#
#   cmake -DCMAKE_TOOLCHAIN_FILE=cmake/mingw-w64.cmake -S . -B build/windows
#
# The compilers are the system's (apt install g++-mingw-w64-x86-64-posix)
# if they are there, else a copy unpacked from Ubuntu's packages without
# root, in ~/.local/opt/mingw (script/build-windows says how to get one).
# The posix-threads flavour: the engine and Luau use std::thread.
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

set(MINGW_TRIPLE x86_64-w64-mingw32)
find_program(MINGW_GCC NAMES ${MINGW_TRIPLE}-gcc-posix PATHS $ENV{HOME}/.local/opt/mingw/usr/bin)
find_program(MINGW_GXX NAMES ${MINGW_TRIPLE}-g++-posix PATHS $ENV{HOME}/.local/opt/mingw/usr/bin)
find_program(MINGW_WINDRES NAMES ${MINGW_TRIPLE}-windres PATHS $ENV{HOME}/.local/opt/mingw/usr/bin)
if(NOT MINGW_GCC OR NOT MINGW_GXX OR NOT MINGW_WINDRES)
  message(FATAL_ERROR "no MinGW-w64 compilers (posix threads) were found: see script/build-windows")
endif()
set(CMAKE_C_COMPILER ${MINGW_GCC})
set(CMAKE_CXX_COMPILER ${MINGW_GXX})
set(CMAKE_RC_COMPILER ${MINGW_WINDRES})

# Headers and libraries are the target's, programs the host's.
get_filename_component(MINGW_BIN ${MINGW_GCC} DIRECTORY)
get_filename_component(MINGW_USR ${MINGW_BIN} DIRECTORY)
# (and what SFML carries for MinGW; FreeType is ext/freetype, CMakeLists.txt)
get_filename_component(SFML_EXTLIBS ${CMAKE_CURRENT_LIST_DIR}/../ext/SFML/extlibs ABSOLUTE)
set(CMAKE_FIND_ROOT_PATH ${MINGW_USR}/${MINGW_TRIPLE} ${MINGW_USR}/lib/gcc/${MINGW_TRIPLE} ${SFML_EXTLIBS})
# (and the compilers' own headers' paths, which code inlined from them
# carries, as the toolchain's and not this machine's: a copy unpacked in
# the home folder put that folder's path in the program's strings)
add_compile_options("-ffile-prefix-map=${MINGW_USR}=/usr")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
