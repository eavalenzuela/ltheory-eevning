/* Luau's header first: the engine defines an 'error' macro. */
#include "lua.h"

/* (the console and the hidden re-run are for whoever works on the game,
   on Linux: a Windows build is the game alone, and has neither) */
#ifndef _WIN32
#include <poll.h>
#include <unistd.h>
#endif
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

#include <SFML/Graphics/Image.hpp>
#include <SFML/Graphics/RenderWindow.hpp>
#include <SFML/Window/VideoMode.hpp>
#ifdef _WIN32
#include <io.h>
/* (declared here and not by way of windows.h, whose names get in the engine's way) */
extern "C" __declspec(dllimport) int __stdcall SetProcessDPIAware(void);
#endif

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
#ifndef _WIN32
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
#endif
  }

  Launcher(String const& appName, V2U const& size, bool border, Harness& harness) :
    appName(appName),
    harness(harness),
    luauApp(0),
    failed(false),
    console(false)
  {
    if (!OS_IsDir("resource"))
      OS_ChangeDir("../");
    /* (the game goes by its name: the rest are tools, and go by theirs) */
    window = Window_Create(appName == "game" ? "Limitless Space" : "App Launcher", size, border, false);
    /* (one with no border is the screen's own size, and goes where the screen begins) */
    if (!border)
      window->SetPosition(V2I(0, 0));
    /* (and the game's window has the game's icon: script/icon) */
    if (appName == "game") {
      sf::Image icon;
      if (OS_IsFile("resource/icon/limitless-space.png") && icon.loadFromFile("resource/icon/limitless-space.png"))
        ((sf::RenderWindow*)window->GetImplData())->setIcon(icon.getSize().x, icon.getSize().y, icon.getPixelsPtr());
    }
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
    /* Tell the app whether a harness is driving it (Host.scripted): an
       app that opens on a menu for a person goes straight to work for a
       script. */
    lua_getglobal(L, "Host");
    if (lua_istable(L, -1)) {
      lua_pushboolean(L, harness.commands.size() > 0);
      lua_setfield(L, -2, "scripted");
    }
    lua_pop(L, 1);
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
    "  --on-desktop     open the window on the desktop even for a run that is\n"
    "                   nobody's to watch (one with --do, --script,\n"
    "                   --no-present, --fixed-step or --selftest): such a run\n"
    "                   is otherwise made where it is not seen\n"
    "                   (script/offscreen)\n"
    "  --selftest KIND  fail on purpose once the engine is up, to prove that\n"
    "                   failures reach the exit status: segv or assert\n");
}

/* Whether this program is an install's (docs/distribution.md): it has
   been given another name than its own, LimitlessSpace.exe or
   limitless-space. Started with nothing said, such a one is the game. */
static bool Installed(char const* program) {
  String name = program ? program : "";
  size_t slash = name.find_last_of("/\\");
  if (slash != String::npos)
    name = name.substr(slash + 1);
  return name.size() && name != "launch" && name != "launch.exe";
}

/* How the game's window opens when somebody plays it: as the options
   have it (save/settings.txt, "window=": "borderless", at the screen's
   own size with no border, or "WxH", a window of that size), and with
   nothing set, 1920 by 1080 where the screen is bigger than that and
   borderless where it is not, since a window that does not fit its
   screen is no use. (A run that is a script's, or is given --size, is
   the size it always was.) */
static void WindowAsSet(V2U& size, bool& border) {
  std::string choice;
  std::ifstream file("save/settings.txt");
  for (std::string line; std::getline(file, line); ) {
    if (line.rfind("window=", 0) == 0)
      choice = line.substr(7);
  }
  while (choice.size() && (choice.back() == '\r' || choice.back() == ' '))
    choice.pop_back();
  sf::VideoMode screen = sf::VideoMode::getDesktopMode();
  unsigned w = 0, h = 0;
  if (choice == "borderless" || (choice.empty() && (screen.width <= size.x || screen.height <= size.y))) {
    if (screen.width >= 640 && screen.height >= 480) {
      size = V2U(screen.width, screen.height);
      border = false;
    }
  }
  else if (sscanf(choice.c_str(), "%ux%u", &w, &h) == 2 && w >= 640 && h >= 480)
    size = V2U(w, h);
}

int main(int argc, char const* argv[]) {
#ifdef _WIN32
  /* The screen's own pixels, whatever Windows has its text scaled to:
     without this a screen of 1920 by 1080 at 125% is given out as 1536
     by 864, the window is made that size and stretched, and an
     interface laid out for 1920 by 1080 does not fit it. */
  SetProcessDPIAware();
#endif
  char const* played[] = { argc > 0 ? argv[0] : "launch", "game" };
  if (argc < 2 && Installed(argc > 0 ? argv[0] : nullptr)) {
    argc = 2;
    argv = played;
    /* Nobody is listening to an installed game (on Windows it has no
       console at all): what it says is kept beside it, in log.txt, as
       it is said, for whoever is asked what went wrong. */
    if (freopen("log.txt", "w", stdout)) {
      setvbuf(stdout, nullptr, _IONBF, 0);
      dup2(fileno(stdout), fileno(stderr));
      setvbuf(stderr, nullptr, _IONBF, 0);
    }
  }
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
  bool scripted = false;
  bool onDesktop = false;
  bool sized = false;
  bool border = true;
  for (int i = 2; i < argc; ++i) {
    String opt = argv[i];
    if (opt == "--no-present") {
      present = false;
      continue;
    }
    if (opt == "--on-desktop") {
      onDesktop = true;
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
    if (opt == "--do") {
      harness.Load(value);
      scripted = true;
    }
    else if (opt == "--script") {
      if (!harness.LoadFile(value)) {
        printf("ERROR: Cannot read harness script %s\n", value.c_str());
        return 1;
      }
      scripted = true;
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
      sized = true;
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

  /* A run that is nobody's to watch (a script's, a hidden one, a timed
     one, a planted failure) opens no window on the desktop: somebody is
     working there, and a check is fifty such windows one after another.
     It is run again where it is not seen (script/offscreen: a desktop of
     its own with no screen, on the same graphics card), unless it is
     there already or the window has been asked for. It never falls back
     on the desktop by itself. */
#ifndef LIBLT_WINDOWS
  if ((scripted || !present || fixedHz > 0 || selftest.size()) && !onDesktop && !getenv("LT_OFFSCREEN")) {
    std::vector<char*> args;
    args.push_back((char*)"script/offscreen");
    for (int i = 0; i < argc; ++i)
      args.push_back((char*)argv[i]);
    args.push_back(nullptr);
    fflush(stdout);
    execv("script/offscreen", args.data());
    printf("ERROR: this run opens no window on the desktop, and script/offscreen could not be run from here (%s).\n"
           "       Run it from the top of the repository, or give --on-desktop to open the window.\n", strerror(errno));
    return 1;
  }
#endif

  /* (the game, with somebody at it: its window is as they set it) */
  if (String(argv[1]) == "game" && !sized && !(scripted || !present || fixedHz > 0 || selftest.size())) {
    WindowAsSet(size, border);
    printf("window: %u by %u, %s\n", (unsigned)size.x, (unsigned)size.y, border ? "with a border" : "no border");
    fflush(stdout);
  }

  Launcher launcher(argv[1], size, border, harness);

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
