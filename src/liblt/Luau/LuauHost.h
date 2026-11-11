#ifndef Luau_LuauHost_h__
#define Luau_LuauHost_h__

/* The Host table: the small set of services an engine-free script needs
   from whatever is running it (binary files, directories, a clock, the
   command line, an exit status).

   Two hosts register it: the engine (src/liblt/Luau/Luau.cpp) and the
   windowless runner (src/ltcore/ltcore.cpp). Scripts under
   resource/script/Core, Sim and Tool may use Host and nothing else from
   the engine, so the same code runs in both. The definitions that the
   type checker reads are in resource/script/host.d.luau; keep the two in
   step.

   Header-only and limited to the Luau C API and POSIX, so the runner does
   not have to link the engine. Linux only, like the rest of the project.

   Functions report failure by returning false or nil, never by raising:
   a missing save file is an ordinary case for the caller to handle. */

#include "lua.h"
#include "lualib.h"

#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <algorithm>
#include <string>
#include <vector>

#include <dirent.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

namespace LuauHost {
  /* Host.ReadFile(path) -> buffer?  The whole file as bytes, or nil. */
  inline int ReadFile(lua_State* L) {
    char const* path = luaL_checkstring(L, 1);
    FILE* file = fopen(path, "rb");
    if (!file) {
      lua_pushnil(L);
      return 1;
    }
    std::string data;
    char chunk[65536];
    size_t n;
    while ((n = fread(chunk, 1, sizeof(chunk), file)) > 0)
      data.append(chunk, n);
    bool failed = ferror(file) != 0;
    fclose(file);
    if (failed) {
      lua_pushnil(L);
      return 1;
    }
    void* buffer = lua_newbuffer(L, data.size());
    if (!data.empty())
      memcpy(buffer, data.data(), data.size());
    return 1;
  }

  /* The bytes of argument 'index' (a buffer or a string), limited to the
     optional length in argument 'index + 1'. */
  inline char const* Bytes(lua_State* L, int index, size_t& size) {
    char const* data;
    if (lua_isbuffer(L, index))
      data = (char const*)lua_tobuffer(L, index, &size);
    else
      data = luaL_checklstring(L, index, &size);
    if (!lua_isnoneornil(L, index + 1)) {
      double length = luaL_checknumber(L, index + 1);
      if (length < 0 || length > (double)size)
        luaL_error(L, "length %f is outside the data (%d bytes)", length, (int)size);
      size = (size_t)length;
    }
    return data;
  }

  inline int Write(lua_State* L, char const* mode) {
    char const* path = luaL_checkstring(L, 1);
    size_t size = 0;
    char const* data = Bytes(L, 2, size);
    FILE* file = fopen(path, mode);
    if (!file) {
      lua_pushboolean(L, false);
      return 1;
    }
    bool ok = size == 0 || fwrite(data, 1, size, file) == size;
    ok = fclose(file) == 0 && ok;
    lua_pushboolean(L, ok);
    return 1;
  }

  /* Host.WriteFile(path, data, length?) -> boolean.  'data' is a buffer
     or a string; 'length' writes only its first bytes. To replace a file
     safely, write a temporary file and Host.Rename it over the old one. */
  inline int WriteFile(lua_State* L) {
    return Write(L, "wb");
  }

  /* Host.AppendFile(path, data, length?) -> boolean */
  inline int AppendFile(lua_State* L) {
    return Write(L, "ab");
  }

  /* Host.Rename(from, to) -> boolean.  Atomic within one filesystem. */
  inline int Rename(lua_State* L) {
    lua_pushboolean(L, rename(luaL_checkstring(L, 1), luaL_checkstring(L, 2)) == 0);
    return 1;
  }

  /* Host.Remove(path) -> boolean.  A file or an empty directory. */
  inline int Remove(lua_State* L) {
    lua_pushboolean(L, remove(luaL_checkstring(L, 1)) == 0);
    return 1;
  }

  /* Host.Exists(path) -> boolean */
  inline int Exists(lua_State* L) {
    struct stat info;
    lua_pushboolean(L, stat(luaL_checkstring(L, 1), &info) == 0);
    return 1;
  }

  /* Host.MakeDir(path) -> boolean.  Creates missing parents too; true if
     the directory exists afterwards. */
  inline int MakeDir(lua_State* L) {
    std::string path = luaL_checkstring(L, 1);
    for (size_t i = 1; i <= path.size(); ++i) {
      if (i == path.size() || path[i] == '/') {
        std::string part = path.substr(0, i);
        if (mkdir(part.c_str(), 0777) != 0 && errno != EEXIST) {
          lua_pushboolean(L, false);
          return 1;
        }
      }
    }
    struct stat info;
    lua_pushboolean(L, stat(path.c_str(), &info) == 0 && S_ISDIR(info.st_mode));
    return 1;
  }

  /* Host.ListDir(path) -> { string }.  Entry names in byte order (so runs
     do not depend on directory order), directories with a trailing '/'.
     Empty if the directory cannot be read. */
  inline int ListDir(lua_State* L) {
    std::string path = luaL_checkstring(L, 1);
    std::vector<std::string> names;
    if (DIR* dir = opendir(path.c_str())) {
      while (struct dirent* entry = readdir(dir)) {
        std::string name = entry->d_name;
        if (name == "." || name == "..")
          continue;
        struct stat info;
        if (stat((path + "/" + name).c_str(), &info) == 0 && S_ISDIR(info.st_mode))
          name += "/";
        names.push_back(name);
      }
      closedir(dir);
    }
    std::sort(names.begin(), names.end());
    lua_createtable(L, (int)names.size(), 0);
    for (size_t i = 0; i < names.size(); ++i) {
      lua_pushlstring(L, names[i].data(), names[i].size());
      lua_rawseti(L, -2, (int)i + 1);
    }
    return 1;
  }

  /* Host.Clock() -> number.  Seconds on a monotonic clock, for timing
     tools and frame pacing. Game rules must not read it. */
  inline int Clock(lua_State* L) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    lua_pushnumber(L, (double)now.tv_sec + (double)now.tv_nsec * 1e-9);
    return 1;
  }

  /* Host.Time() -> number.  Seconds since 1970, for naming files and
     picking a fresh seed. Game rules must not read it. */
  inline int Time(lua_State* L) {
    lua_pushnumber(L, (double)time(0));
    return 1;
  }

  /* Host.Exit(code) never returns.  Ends the process with that status
     without running destructors, which is what a test wants: the status
     is the result. */
  inline int Exit(lua_State* L) {
    int code = (int)luaL_optnumber(L, 1, 0);
    fflush(0);
    _exit(code);
    return 0;
  }

  /* Create the global Host table. 'args' become Host.args; 'headless' is
     true when no engine is present. */
  inline void Register(
    lua_State* L,
    int argc,
    char const* const* argv,
    bool headless)
  {
    static const luaL_Reg functions[] = {
      { "ReadFile", ReadFile },
      { "WriteFile", WriteFile },
      { "AppendFile", AppendFile },
      { "Rename", Rename },
      { "Remove", Remove },
      { "Exists", Exists },
      { "MakeDir", MakeDir },
      { "ListDir", ListDir },
      { "Clock", Clock },
      { "Time", Time },
      { "Exit", Exit },
      { 0, 0 }
    };

    lua_newtable(L);
    for (luaL_Reg const* f = functions; f->name; ++f) {
      lua_pushcfunction(L, f->func, f->name);
      lua_setfield(L, -2, f->name);
    }
    lua_createtable(L, argc, 0);
    for (int i = 0; i < argc; ++i) {
      lua_pushstring(L, argv[i]);
      lua_rawseti(L, -2, i + 1);
    }
    lua_setfield(L, -2, "args");
    lua_pushboolean(L, headless);
    lua_setfield(L, -2, "headless");
    /* (the launcher sets this when a harness is driving the app) */
    lua_pushboolean(L, false);
    lua_setfield(L, -2, "scripted");
    lua_setglobal(L, "Host");
  }
}

#endif
