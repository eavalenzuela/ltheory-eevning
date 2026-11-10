/* ltcore: run engine-free Luau modules with no window, no GL context and
   no engine.

     ltcore MODULE [ARG ...]

   MODULE names a file under resource/script as require does ("Tool/test",
   or "@lt/Tool/test"). The module is loaded, then:
     - if it returns a table with a Main function, Main(args) is called;
     - otherwise, if the table has an Initialize function, it is called as
       a method, so a run-once app written for bin/launch also works here.
   A number returned by either becomes the exit status. A script error
   prints a traceback and exits 1.

   Only the Luau VM and compiler are linked. The engine's ~740 bound
   functions are absent by construction: a module that runs here cannot
   depend on the engine, the GPU or a display. The one extra global is
   Host (src/liblt/Luau/LuauHost.h): files, directories, a clock, the
   arguments and Exit.

   Modules are compiled exactly as the engine compiles them
   (src/liblt/Luau/Luau.cpp, Require), so a deterministic module gives the
   same results in both. */

#include "lua.h"
#include "Luau/CodeGen.h"
#include "lualib.h"
#include "luacode.h"

#include "Luau/LuauHost.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>

#include <sys/stat.h>
#include <unistd.h>

namespace {
  std::string ModulePath(std::string const& module) {
    std::string path = module.compare(0, 4, "@lt/") == 0 ? module.substr(4) : module;
    return "resource/script/" + path + ".luau";
  }

  bool ReadSource(std::string const& path, std::string& out) {
    std::ifstream file(path.c_str(), std::ios::binary);
    if (!file)
      return false;
    std::ostringstream s;
    s << file.rdbuf();
    out = s.str();
    return true;
  }

  int Require(lua_State* L) {
    std::string module = luaL_checkstring(L, 1);

    lua_getfield(L, LUA_REGISTRYINDEX, "_LT_MODULES");
    int cache = lua_gettop(L);
    lua_getfield(L, cache, module.c_str());
    if (!lua_isnil(L, -1))
      return 1;
    lua_pop(L, 1);

    std::string path = ModulePath(module);
    std::string source;
    if (!ReadSource(path, source))
      luaL_error(L, "module '%s' not found (%s)", module.c_str(), path.c_str());

    lua_CompileOptions options;
    memset(&options, 0, sizeof(options));
    /* Level 2 inlines small local functions, which the rules are full of. */
    options.optimizationLevel = 2;
    options.debugLevel = 1;
    size_t size = 0;
    char* bytecode = luau_compile(source.data(), source.size(), &options, &size);
    std::string chunk = "@" + path;
    int status = luau_load(L, chunk.c_str(), bytecode, size, 0);
    free(bytecode);
    if (status != 0)
      lua_error(L);
    /* A module that starts with --!native is compiled to machine code
       (the hot loops of the economy; everything else is interpreted).
       LT_NATIVE_REPORT=1 says what became of each. */
    if (Luau::CodeGen::isSupported()) {
      Luau::CodeGen::CompilationResult result =
        Luau::CodeGen::compile(L, -1, Luau::CodeGen::CodeGen_OnlyNativeModules);
      if (getenv("LT_NATIVE_REPORT") && result.result != Luau::CodeGen::CodeGenCompilationResult::NotNativeModule)
        printf("native: %s: %s\n", path.c_str(), Luau::CodeGen::toString(result.result).c_str());
    }

    lua_call(L, 0, 1);
    if (lua_isnil(L, -1)) {
      lua_pop(L, 1);
      lua_pushboolean(L, true);
    }
    lua_pushvalue(L, -1);
    lua_setfield(L, cache, module.c_str());
    return 1;
  }

  int Traceback(lua_State* L) {
    char const* message = lua_tostring(L, 1);
    luaL_traceback(L, L, message ? message : "(non-string error)", 1);
    return 1;
  }

  /* Call the function below its 'nargs' arguments; on error print a
     traceback and return false. */
  bool Call(lua_State* L, int nargs, int nresults) {
    int base = lua_gettop(L) - nargs;
    lua_pushcfunction(L, Traceback, "traceback");
    lua_insert(L, base);
    int status = lua_pcall(L, nargs, nresults, base);
    lua_remove(L, base);
    if (status != LUA_OK) {
      printf("LUAU ERROR: %s\n", lua_tostring(L, -1));
      fflush(stdout);
      lua_pop(L, 1);
      return false;
    }
    return true;
  }

  int StatusFrom(lua_State* L) {
    int status = lua_isnumber(L, -1) ? (int)lua_tonumber(L, -1) : 0;
    lua_pop(L, 1);
    return status;
  }
}

int main(int argc, char const* argv[]) {
  if (argc < 2 || argv[1][0] == '-') {
    printf(
      "Usage: ltcore MODULE [ARG ...]\n"
      "  Runs resource/script/MODULE.luau with no window and no engine.\n"
      "  The module's Main(args) (or Initialize) is called; a number it\n"
      "  returns is the exit status. See src/ltcore/ltcore.cpp.\n");
    return argc < 2 ? 0 : 1;
  }

  /* Like bin/launch: run from the repository root, or from bin/. */
  struct stat info;
  if (stat("resource", &info) != 0 && chdir("..") != 0)
    return 1;

  /* Line-buffer stdout even when piped, so progress from a long run
     shows up as it happens. */
  setvbuf(stdout, 0, _IOLBF, 0);

  lua_State* L = luaL_newstate();
  if (Luau::CodeGen::isSupported())
    Luau::CodeGen::create(L);
  luaL_openlibs(L);
  lua_newtable(L);
  lua_setfield(L, LUA_REGISTRYINDEX, "_LT_MODULES");
  lua_pushcfunction(L, Require, "require");
  lua_setglobal(L, "require");
  LuauHost::Register(L, argc - 2, argv + 2, true);
  /* A promise that nothing replaces the built-in globals from here on:
     with it the VM resolves math.sqrt and the like when a module loads
     and calls them directly, which is several times faster. (Modules may
     still add globals of their own.) */
  lua_setsafeenv(L, LUA_GLOBALSINDEX, true);

  lua_getglobal(L, "require");
  lua_pushstring(L, argv[1]);
  if (!Call(L, 1, 1))
    return 1;

  int status = 0;
  if (lua_istable(L, -1)) {
    lua_getfield(L, -1, "Main");
    if (lua_isfunction(L, -1)) {
      lua_getglobal(L, "Host");
      lua_getfield(L, -1, "args");
      lua_remove(L, -2);
      if (!Call(L, 1, 1))
        return 1;
      status = StatusFrom(L);
    } else {
      lua_pop(L, 1);
      lua_getfield(L, -1, "Initialize");
      if (lua_isfunction(L, -1)) {
        lua_pushvalue(L, -2);
        if (!Call(L, 1, 1))
          return 1;
        status = StatusFrom(L);
      } else
        lua_pop(L, 1);
    }
  }

  fflush(stdout);
  lua_close(L);
  return status;
}
