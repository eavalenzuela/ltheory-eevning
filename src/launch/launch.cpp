/* Luau's header first: the engine defines an 'error' macro. */
#include "lua.h"

#include "Harness.h"

#include "Luau/Luau.h"

#include "Module/PhysicsEngine.h"
#include "Module/SoundEngine.h"

#include "LTE/Keyboard.h"
#include "LTE/Profiler.h"
#include "LTE/Program.h"
#include "LTE/OS.h"
#include "LTE/Renderer.h"
#include "LTE/Screenshot.h"
#include "LTE/Script.h"
#include "LTE/Window.h"

// #define TIME_LTSL_COMPILE

#ifdef TIME_LTSL_COMPILE
#include "LTE/Debug.h"
#include "LTE/Timer.h"
#endif

struct Launcher : public Program {
  String appName;
  ScriptFunction initialize;
  ScriptFunction update;
  Data instance;
  Module physicsEngine;
  Module soundEngine;
  Harness& harness;
  /* Registry reference to a Luau app's table; 0 for LTSL apps. */
  int luauApp;

  Launcher(String const& appName, V2U const& size, Harness& harness) :
    appName(appName),
    harness(harness),
    luauApp(0)
  {
    if (!OS_IsDir("resource"))
      OS_ChangeDir("../");
    window = Window_Create("App Launcher", size, true, false);
    window->SetSync(false);
    Renderer_Initialize();
  }

  void OnInitialize() {
    Launch();
    harness.Start();
  }

  void Launch() {
    physicsEngine = nullptr;
    soundEngine = nullptr;
    physicsEngine = CreatePhysicsEngine();
    soundEngine = SoundEngine_Miniaudio();
    if (!soundEngine) {
      printf("WARNING: Audio unavailable, continuing without sound\n");
      soundEngine = SoundEngine_Null();
    }

    if (Luau_HasModule("App/" + appName)) {
      LaunchLuau();
      return;
    }

    Script_ClearCache();

#ifdef TIME_LTSL_COMPILE
    Timer timer;
#endif
    ScriptFunction main = ScriptFunction_Load("App/" + appName + ":Main");
#ifdef TIME_LTSL_COMPILE
    dbg | "LTSL Compile Time: " | timer.GetElapsed() | endl;
#endif

    if (!main) {
      printf("ERROR: Launcher failed to load script %s\n", appName.c_str());
      deleted = true;
      return;
    }

    /* Only script-defined types carry a ScriptType in their aux data. */
    if (!main->returnType->GetAux().data) {
      printf("ERROR: Launcher expects %s:Main to return a script type (got %s)\n",
        appName.c_str(), main->returnType->name.c_str());
      deleted = true;
      return;
    }

    /* NOTE : We have to raw cast here due to issues with the usual
              .Convert<ScriptType>. Due to a major design flaw in the Type
              system, Type_Get<T> returns different static storage in the exe
              vs the dll, so type equality comparisons fail when they shouldn't.
              I am not going to fix this right now. */
    ScriptType app = *(ScriptType*)main->returnType->GetAux().data;
    initialize = app->GetFunction("Initialize");
    update = app->GetFunction("Update");
    instance.Construct(app->type);
    main->VoidCall(instance.data);

    if (initialize)
      initialize->VoidCall(0, instance);
    if (!update)
      deleted = true;
  }

  /* A Luau app is a module returning a table; its Initialize runs once and
     its Update every frame, each called as a method. A script error prints
     a traceback and ends the app. */
  void LaunchLuau() {
    luauApp = 0;
    Luau_Reset();
    lua_State* L = Luau_GetState();
    if (!Luau_Require("App/" + appName)) {
      deleted = true;
      return;
    }
    if (!lua_istable(L, -1)) {
      printf("ERROR: App/%s.luau must return a table\n", appName.c_str());
      lua_pop(L, 1);
      deleted = true;
      return;
    }
    luauApp = lua_ref(L, -1);
    lua_pop(L, 1);
    if (!CallLuau("Initialize"))
      deleted = true;
  }

  bool CallLuau(char const* method) {
    lua_State* L = Luau_GetState();
    lua_getref(L, luauApp);
    lua_getfield(L, -1, method);
    if (lua_isnil(L, -1)) {
      lua_pop(L, 2);
      return true;
    }
    lua_insert(L, -2);
    return Luau_Call(1, 0);
  }

  void OnUpdate() {
    if (!harness.Update())
      harness.quit = true;

    if (Keyboard_Pressed(Key_F1))
      Screenshot_Request("");
    if (Keyboard_Pressed(Key_F2))
      Profiler_Auto(1.0f);

    if (Keyboard_Pressed(Key_W) && Keyboard_Control()) {
      deleted = true;
      instance.Clear();
      return;
    }

    if (Keyboard_Down(Key_Tilde))
      debugprint;

    if (Keyboard_Pressed(Key_F5))
      Launch();

    if (luauApp && !CallLuau("Update")) {
      deleted = true;
      return;
    }

    if (update)
      update->VoidCall(0, instance);

    if (physicsEngine)
      physicsEngine->Update();
    if (soundEngine)
      soundEngine->Update();
  }

  void OnPreDisplay() {
    Screenshot_Flush();
    if (harness.quit)
      deleted = true;
  }
};

void Usage() {
  printf(
    "Usage: launch APP [options]\n"
    "  --do COMMANDS    run harness commands (see src/launch/Harness.h),\n"
    "                   separated by ';'\n"
    "  --script FILE    run harness commands from FILE\n"
    "  --out DIR        write screenshots to DIR (default cache/screenshot)\n"
    "  --scale N        shrink screenshots by an integer factor\n"
    "  --size WxH       window size (default 1920x1080)\n"
    "  --timeout S      end a harness run after S seconds (default 300)\n");
}

int main(int argc, char const* argv[]) {
  if (argc < 2 || argv[1][0] == '-') {
    Usage();
    return argc < 2 ? 0 : 1;
  }

  V2U size(1920, 1080);
  Harness harness;
  for (int i = 2; i < argc; ++i) {
    String opt = argv[i];
    if (i + 1 >= argc) {
      printf("ERROR: %s needs a value\n", opt.c_str());
      Usage();
      return 1;
    }
    String value = argv[++i];
    if (opt == "--do")
      harness.Load(value);
    else if (opt == "--script") {
      if (!harness.LoadFile(value)) {
        printf("ERROR: Cannot read harness script %s\n", value.c_str());
        return 1;
      }
    }
    else if (opt == "--out")
      Screenshot_SetDirectory(value);
    else if (opt == "--scale")
      Screenshot_SetDownscale((uint)Max(1, atoi(value.c_str())));
    else if (opt == "--size") {
      uint w, h;
      if (sscanf(value.c_str(), "%ux%u", &w, &h) != 2) {
        printf("ERROR: --size expects WxH\n");
        return 1;
      }
      size = V2U(w, h);
    }
    else if (opt == "--timeout")
      harness.timeout = (float)atof(value.c_str());
    else {
      printf("ERROR: Unknown option %s\n", opt.c_str());
      Usage();
      return 1;
    }
  }

  Launcher(argv[1], size, harness).Execute();
  return 0;
}

#if 0
#ifdef LIBLT_WINDOWS
  #pragma comment(linker, "/SUBSYSTEM:windows")
  #include <windows.h>
  int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrev, PSTR cmd, int show) {
    char const* argv[] = { "program" };
    return main(0, argv);
  }
#endif
#endif
