/* Luau's header first: the engine defines an 'error' macro. */
#include "lua.h"

#include <poll.h>
#include <unistd.h>

#include "Harness.h"

#include "Luau/Luau.h"

#include "Module/FrameTimer.h"
#include "Module/PhysicsEngine.h"
#include "Module/SoundEngine.h"

#include "LTE/Keyboard.h"
#include "LTE/Profiler.h"
#include "LTE/Program.h"
#include "LTE/OS.h"
#include "LTE/Renderer.h"
#include "LTE/Screenshot.h"
#include "LTE/Window.h"

struct Launcher : public Program {
  String appName;
  Module physicsEngine;
  Module soundEngine;
  Harness& harness;
  /* Registry reference to the app's table; 0 until it has started. */
  int luauApp;

  /* Set when the app could not be started. Script errors are counted
     separately (Luau_GetErrorCount); either makes the exit status 1. */
  bool failed;

  /* --console: lines typed in the terminal are run as Luau. */
  bool console;
  String consoleLine;

  /* Run whatever complete lines have arrived on stdin, without waiting. */
  void PollConsole() {
    struct pollfd fd = { 0, POLLIN, 0 };
    while (poll(&fd, 1, 0) > 0 && (fd.revents & (POLLIN | POLLHUP))) {
      char buffer[1024];
      ssize_t n = read(0, buffer, sizeof(buffer));
      if (n <= 0) {
        console = false;
        return;
      }
      for (ssize_t i = 0; i < n; ++i) {
        if (buffer[i] != '\n') {
          consoleLine += buffer[i];
          continue;
        }
        if (consoleLine.size())
          Luau_Eval(consoleLine);
        consoleLine = "";
      }
    }
  }

  Launcher(String const& appName, V2U const& size, Harness& harness) :
    appName(appName),
    harness(harness),
    luauApp(0),
    failed(false),
    console(false)
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

    if (!Luau_HasModule("App/" + appName)) {
      printf("ERROR: no app resource/script/App/%s.luau\n", appName.c_str());
      failed = true;
      deleted = true;
      return;
    }

    LaunchLuau();
  }

  /* An app is a Luau module returning a table; its Initialize runs once
     and its Update every frame, each called as a method. An app without
     Update ends after Initialize. A script error prints a traceback and
     ends the app. */
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
      failed = true;
      deleted = true;
      return;
    }
    lua_getfield(L, -1, "Update");
    bool hasUpdate = !lua_isnil(L, -1);
    lua_pop(L, 1);
    luauApp = lua_ref(L, -1);
    lua_pop(L, 1);
    if (!CallLuau("Initialize") || !hasUpdate)
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
      return;
    }

    if (Keyboard_Down(Key_Tilde))
      debugprint;

    if (Keyboard_Pressed(Key_F5))
      Launch();

    if (console)
      PollConsole();

    if (luauApp && !CallLuau("Update")) {
      deleted = true;
      return;
    }

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
    "  --timeout S      end a harness run after S seconds (default 300)\n"
    "  --fixed-step HZ  advance the app's clock by exactly 1/HZ s per frame and\n"
    "                   seed the random generator, so a run repeats exactly;\n"
    "                   'wait S' then lasts S*HZ frames\n"
    "  --console        read Luau from the terminal while the app runs: type a\n"
    "                   line and it is run in the app's VM, values printed\n"
    "  --no-present     draw every frame but never show it; screenshots still\n"
    "                   work, and the desktop cannot slow the run down\n"
    "  --selftest KIND  fail on purpose once the engine is up, to prove that\n"
    "                   failures reach the exit status: segv or assert\n");
}

int main(int argc, char const* argv[]) {
  if (argc < 2 || argv[1][0] == '-') {
    Usage();
    return argc < 2 ? 0 : 1;
  }

  V2U size(1920, 1080);
  Harness harness;
  String selftest;
  float fixedHz = 0;
  bool present = true;
  bool console = false;
  for (int i = 2; i < argc; ++i) {
    String opt = argv[i];
    if (opt == "--no-present") {
      present = false;
      continue;
    }
    if (opt == "--console") {
      console = true;
      continue;
    }
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
    else if (opt == "--fixed-step") {
      fixedHz = (float)atof(value.c_str());
      if (fixedHz <= 0) {
        printf("ERROR: --fixed-step expects a rate in Hz, such as 60\n");
        return 1;
      }
    }
    else if (opt == "--selftest") {
      if (value != "segv" && value != "assert") {
        printf("ERROR: --selftest expects segv or assert\n");
        return 1;
      }
      selftest = value;
    }
    else {
      printf("ERROR: Unknown option %s\n", opt.c_str());
      Usage();
      return 1;
    }
  }

  Launcher launcher(argv[1], size, harness);

  if (!present)
    launcher.window->SetPresent(false);
  launcher.console = console;
  if (console) {
    printf("console: type Luau and press Enter; it runs in the app's VM\n");
    fflush(stdout);
  }

  /* A repeatable run: the same time step every frame, and the same random
     numbers (Program seeds rand() from the clock). */
  if (fixedHz > 0) {
    FrameTimer_SetFixedStep(1.0f / fixedHz);
    harness.fixedStep = 1.0f / fixedHz;
    srand(1);
  }

  /* Planted failures, raised after the engine has installed its signal
     handlers, so the check script can prove a crash is not reported as
     success. */
  if (selftest == "segv") {
    volatile int* null = 0;
    *null = 1;
  }
  if (selftest == "assert")
    LTE_ASSERT(selftest.size() == 0);

  launcher.Execute();

  /* The exit status is what a test runner sees: 0 only when the app
     started, no script raised an error and every harness command worked.
     Crashes and failed assertions exit from the signal handlers in OS.cpp
     with 128 + the signal number. */
  int errors = Luau_GetErrorCount();
  if (launcher.failed || harness.failed || errors > 0) {
    printf("FAILED:%s%s", launcher.failed ? " app did not start;" : "",
      harness.failed ? " harness command failed or timed out;" : "");
    if (errors > 0)
      printf(" %d script error(s);", errors);
    printf("\n");
    fflush(stdout);
    return 1;
  }
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
