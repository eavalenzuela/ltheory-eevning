cmake_minimum_required (VERSION 3.5)
project(LTheory)

find_package(OpenGL REQUIRED)

# force SFML to build as a static lib to minimize pain
set(BUILD_SHARED_LIBS FALSE CACHE BOOL "" FORCE)
# static SFML gets linked into the shared liblt, so it must be PIC
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
# audio goes through miniaudio, so skip SFML's (and its openal/flac/vorbis deps)
set(SFML_BUILD_AUDIO FALSE CACHE BOOL "" FORCE)
# (nor the network module: nothing uses it, and a program that opens
# sockets for nothing is one more thing a virus scanner weighs, 2026-11-23)
set(SFML_BUILD_NETWORK FALSE CACHE BOOL "" FORCE)
# SFML 2.5 declares an old cmake minimum that CMake 4 rejects
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)
# Source paths as the repository has them, not as this machine does: the
# developer's home folder was in the strings of every shipped binary.
add_compile_options("-ffile-prefix-map=${CMAKE_SOURCE_DIR}/=")
add_subdirectory(ext/SFML)
# The picture decoder SFML carries (stb_image) knows a dozen formats and
# picks one by what is in the file; a player's own portrait is the only
# picture from outside, and the game's own are PNG, JPEG, BMP and TGA. The
# rest (PSD, GIF, HDR, PIC, PNM) had flaws a crafted file could reach, so
# they are left out.
target_compile_definitions(sfml-graphics PRIVATE STBI_ONLY_PNG STBI_ONLY_JPEG STBI_ONLY_BMP STBI_ONLY_TGA)
unset(CMAKE_POLICY_VERSION_MINIMUM)

# Luau scripting (static, PIC like SFML). The CLI gives luau-analyze, the
# type checker that scripts are checked with.
set(LUAU_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LUAU_BUILD_CLI ON CACHE BOOL "" FORCE)
add_subdirectory(ext/luau)

# Where the programs go: bin/, beside the source, unless a build says
# otherwise (the Windows build, which must not put its own over the
# Linux ones: script/build-windows).
set(LT_OUTPUT_DIR "${CMAKE_SOURCE_DIR}/bin" CACHE PATH "Where the built programs are put")

function (configure_output_dir target)
  set_target_properties (${target} PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${LT_OUTPUT_DIR}"
    LIBRARY_OUTPUT_DIRECTORY "${LT_OUTPUT_DIR}"
    ARCHIVE_OUTPUT_DIRECTORY "${LT_OUTPUT_DIR}")

  foreach (config ${CMAKE_CONFIGURATION_TYPES})
    string (TOUPPER ${config} config)
    set_target_properties (${target} PROPERTIES
      RUNTIME_OUTPUT_DIRECTORY_${config} "${LT_OUTPUT_DIR}"
      LIBRARY_OUTPUT_DIRECTORY_${config} "${LT_OUTPUT_DIR}"
      ARCHIVE_OUTPUT_DIRECTORY_${config} "${LT_OUTPUT_DIR}")
  endforeach (config)
endfunction ()

# Set build path
set(BUILD_DIR ${CMAKE_BINARY_DIR})
set(EXECUTABLE_OUTPUT_PATH ${BUILD_DIR} CACHE PATH "Build directory" FORCE)
set(LIBRARY_OUTPUT_PATH ${BUILD_DIR} CACHE PATH "Build directory" FORCE)

# Detect OS
if(${CMAKE_SYSTEM_NAME} MATCHES "Windows")
  set(WINDOWS 1)
elseif(${CMAKE_SYSTEM_NAME} MATCHES "Linux")
  set(LINUX 1)
elseif(${CMAKE_SYSTEM_NAME} MATCHES "FreeBSD")
  set(LINUX 1)
elseif(${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
  set(MAC 1)
else()
  message(FATAL_ERROR "Unsupported operating system")
  return()
endif()

# Detect Architecture
include(CheckTypeSize)
check_type_size(void* SIZEOF_VOID_PTR)
if("${SIZEOF_VOID_PTR}" STREQUAL "4")
  set(ARCH_32 1)
elseif("${SIZEOF_VOID_PTR}" STREQUAL "8")
  set(ARCH_64 1)
else()
  message(FATAL_ERROR "Unsupported architecture")
  return()
endif()

# Get ext includes
include_directories(src/liblt
  include
  include/FreeType
  ext/SFML/include
  ext/miniaudio
  ext/luau/VM/include
  ext/luau/Compiler/include)

# Get ext libraries
if(MINGW)

  # Windows, cross-compiled with MinGW-w64 (cmake/mingw-w64.cmake). GLEW is
  # compiled from ext/glew, with its own header in place of the old one in
  # include/; FreeType is the copy SFML carries for MinGW; and the engine
  # is one static library, linked into the program (a DLL of it would have
  # more names to export than a DLL can).
  include_directories(BEFORE ext/glew/shim)
  add_library(glew STATIC ext/glew/src/glew.c)
  target_include_directories(glew PUBLIC ext/glew/include)
  target_compile_definitions(glew PUBLIC GLEW_STATIC GLEW_NO_GLU)
  add_compile_definitions(GLEW_STATIC GLEW_NO_GLU LIBLT_STATIC)

  set(LINK_LIBRARIES
      glew
      ${PROJECT_SOURCE_DIR}/ext/SFML/extlibs/libs-mingw/x64/libfreetype.a
      sfml-graphics
      sfml-system
      sfml-window
      winmm
      gdi32
      ws2_32
      ole32
      dbghelp)

elseif(WINDOWS)

  file(GLOB_RECURSE EXTLIB extlib/win32/*.lib)
  set(LINK_LIBRARIES
      ${GLEW_GLEW_LIBRARY}
      sfml-graphics
      sfml-system
      sfml-window)

elseif(MAC)

  set(LINK_LIBRARIES
    # enet
      freetype
      GLEW
      sfml-graphics
      sfml-system
      sfml-window
      )

  link_directories(${PROJECT_SOURCE_DIR}/extbin/osx)

elseif(LINUX)

  # use the system freetype (same one SFML links) rather than extbin's copy
  find_package(Freetype REQUIRED)

  set(LINK_LIBRARIES
      dl
      # enet
      ${FREETYPE_LIBRARIES}
      sfml-graphics
      sfml-system
      sfml-window
      GLEW
      # miniaudio (it dlopens the audio backends itself)
      pthread
      m)

  # launch finds liblt.so next to it (and only there: the build folder's
  # own path, the developer's home in it, was in the RUNPATH of what ships)
  set(CMAKE_INSTALL_RPATH "$ORIGIN")
  set(CMAKE_BUILD_WITH_INSTALL_RPATH ON)

endif()

set(LINK_LIBRARIES ${LINK_LIBRARIES} ${OPENGL_LIBRARIES})

# Build shared libary
file(GLOB_RECURSE LIBLT_SRC src/liblt/*.cpp)
if(MINGW)
  add_library(lt STATIC ${LIBLT_SRC} ext/miniaudio/miniaudio.c)
else()
  add_library(lt SHARED ${LIBLT_SRC} ext/miniaudio/miniaudio.c)
endif()
target_link_libraries(lt ${LINK_LIBRARIES} ${EXTLIB} Luau.VM Luau.Compiler Luau.CodeGen)
configure_output_dir(lt)

# Luau reports script errors by throwing; the binding layer is built with
# exceptions so they unwind through it properly (the rest of liblt isn't)
file(GLOB LIBLT_LUAU_SRC src/liblt/Luau/*.cpp)
set_source_files_properties(${LIBLT_LUAU_SRC} PROPERTIES COMPILE_FLAGS "-fexceptions")

# Post-build step to copy DLLs to bin folder
if (MSVC)
  file(GLOB_RECURSE RUNTIME_BINARIES extbin/win32/*.dll)
  foreach(X ${RUNTIME_BINARIES})
    add_custom_command (TARGET lt POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_different
      ${X} $<TARGET_FILE_DIR:lt>)
  endforeach(X)
endif()

# Build binaries
set(TARGETS
    launch)

foreach(TARGET ${TARGETS})
  
  # (the resource script is Visual Studio's own, in its own encoding: MinGW's
  # tool cannot read it, and a program built with it goes without)
  if(MINGW)
    # (its own, with the game's icon: script/icon makes that. And no console
    # of its own: what it says is kept in a file, src/launch)
    enable_language(RC)
    file(WRITE ${CMAKE_BINARY_DIR}/icon.rc "1 ICON \"${PROJECT_SOURCE_DIR}/resource/icon/limitless-space.ico\"\n")
    add_executable(${TARGET} WIN32 ${PROJECT_SOURCE_DIR}/src/${TARGET}/${TARGET}.cpp ${CMAKE_BINARY_DIR}/icon.rc)
  else()
    add_executable(${TARGET} ${PROJECT_SOURCE_DIR}/src/${TARGET}/${TARGET}.cpp src/resources.rc)
  endif()
  target_link_libraries(${TARGET} ${LINK_LIBRARIES})
  configure_output_dir(${TARGET})

endforeach(TARGET)

# (the tools below are for whoever works on the game, on Linux: a Windows
# build is the game alone)
if(NOT MINGW)

# luaucheck: type-checks Luau scripts against definitions generated from the
# engine's reflection (C++17, with exceptions, like Luau's analysis library)
add_executable(luaucheck src/luaucheck/luaucheck.cpp)
target_link_libraries(luaucheck lt Luau.Analysis)
set_source_files_properties(src/luaucheck/luaucheck.cpp PROPERTIES COMPILE_FLAGS "-std=c++17 -fexceptions")
configure_output_dir(luaucheck)

# ltcore: runs engine-free Luau modules (the game core, its tests and tools)
# with no window and no engine. Links only the Luau VM, compiler and native
# code generator.
add_executable(ltcore src/ltcore/ltcore.cpp)
target_include_directories(ltcore PRIVATE ${PROJECT_SOURCE_DIR}/src/liblt)
target_link_libraries(ltcore Luau.VM Luau.Compiler Luau.CodeGen)
set_source_files_properties(src/ltcore/ltcore.cpp PROPERTIES COMPILE_FLAGS "-std=c++17 -fexceptions")
configure_output_dir(ltcore)

endif()

# Link dynamic targets to the shared lib
foreach(TARGET ${TARGETS})

  if(MINGW)
    # (all of the static library, and not only what the program names:
    # most of the engine is known to it by what registers itself when the
    # program starts, which nothing names)
    target_link_libraries(${TARGET} -Wl,--whole-archive lt -Wl,--no-whole-archive)
  else()
    target_link_libraries(${TARGET} lt)
  endif()

endforeach(TARGET)

# Set target properties
if(MSVC)

  # No exception handling
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /EHs")
  
  # Multi-threaded compilation
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /MP")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /fp:fast")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /arch:SSE2")

  # No libcmt warnings
  set_target_properties(lt PROPERTIES LINK_FLAGS "/NODEFAULTLIB:libcmt")
  foreach(TARGET ${EXECUTABLES})
    set_target_properties(${TARGET} PROPERTIES LINK_FLAGS "/NODEFAULTLIB:libcmt")
  endforeach(TARGET)

  # The updater requires administrator privileges to run
  # set_target_properties(updater PROPERTIES LINK_FLAGS "/level='requireAdministrator' /uiAccess='false'")

else()

  # No exception handling 
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fno-exceptions")

  # C++17 (was C++0x until the LTSL runtime was retired)
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++17")

  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O2 -g")

  # Enable lots of warnings
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -pedantic -Wall -Wextra")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-invalid-offsetof")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-unused-const-variable")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-unused-parameter")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-unused-function")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-unused-variable")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-tautological-compare")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-deprecated-copy")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-ignored-qualifiers")

  # Stop on errors
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wfatal-errors")

  # set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wconversion")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-sign-conversion")

  # Enable SSE / SSE2
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -msse -msse2")

  # A Windows program that needs nothing beside it but its own files: the
  # compiler's runtime is linked in, and it opens no console of its own.
  if(MINGW)
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -static -static-libgcc -static-libstdc++")
  endif()

endif()
