#ifndef Launch_Harness_h__
#define Launch_Harness_h__

/* A scripted driver for automated runs: waits, synthetic mouse and keyboard
   input, and screenshots, so an app can be exercised and inspected without
   anyone at the controls. While a harness runs, real input is ignored.

   Commands are separated by newlines or ';', and '#' starts a comment:

     wait S              wait S seconds of real time
     frames N            wait N frames
     shot NAME           save NAME.png once this frame is drawn
     move X Y            put the cursor at pixel (X, Y)
     click [BUTTON] [X Y]  press and release a mouse button (default Left)
     mousedown [BUTTON]  hold a mouse button
     mouseup [BUTTON]    release a mouse button
     scroll D            scroll the wheel by D notches
     key NAME            press and release a key (names as in Key_*: A, N1,
                         Space, Escape, Return, LShift, F5, ...)
     keydown NAME        hold a key
     keyup NAME          release a key
     type TEXT           enter TEXT as typed characters
     echo TEXT           print TEXT
     quit                exit the app */

#include "LTE/Keyboard.h"
#include "LTE/Mouse.h"
#include "LTE/Screenshot.h"
#include "LTE/String.h"
#include "LTE/Timer.h"
#include "LTE/Vector.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>
#include <strings.h>

struct Harness {
  Vector<Vector<String> > commands;
  size_t next;
  float waitUntil;
  uint waitFrames;
  float timeout;
  Timer clock;
  Vector<Key> keysToRelease;
  Vector<MouseButton> buttonsToRelease;
  bool active;
  bool quit;

  Harness() :
    next(0),
    waitUntil(0),
    waitFrames(0),
    timeout(300),
    active(false),
    quit(false)
    {}

  void Load(String const& text) {
    std::istringstream lines(text);
    String line;
    while (std::getline(lines, line, '\n')) {
      std::istringstream statements(line);
      String statement;
      while (std::getline(statements, statement, ';')) {
        size_t comment = statement.find('#');
        if (comment != String::npos)
          statement = statement.substr(0, comment);
        Vector<String> words;
        std::istringstream tokens(statement);
        String word;
        while (tokens >> word)
          words.push(word);
        if (words.size())
          commands.push(words);
      }
    }
    active = true;
  }

  bool LoadFile(String const& path) {
    std::ifstream file(path.c_str());
    if (!file)
      return false;
    std::stringstream text;
    text << file.rdbuf();
    Load(text.str());
    return true;
  }

  void Start() {
    if (!active)
      return;
    Mouse_SetSynthetic(true);
    Keyboard_SetSynthetic(true);
    clock.Reset();
  }

  static bool ParseKey(String const& name, Key& key) {
    for (Key i = 0; i < Key_SIZE; ++i) {
      if (strcasecmp(name.c_str(), Key_String[i]) == 0) {
        key = i;
        return true;
      }
    }
    return false;
  }

  static bool ParseButton(String const& name, MouseButton& button) {
    for (MouseButton i = 0; i < MouseButton_SIZE; ++i) {
      if (strcasecmp(name.c_str(), MouseButton_String[i]) == 0) {
        button = i;
        return true;
      }
    }
    return false;
  }

  static String Rest(Vector<String> const& words, size_t from) {
    String result;
    for (size_t i = from; i < words.size(); ++i)
      result += (i > from ? " " : "") + words[i];
    return result;
  }

  void Fail(Vector<String> const& words, char const* why) {
    printf("HARNESS ERROR: '%s': %s\n", Rest(words, 0).c_str(), why);
  }

  /* Called at the start of each frame's update, after real input has been
     polled; returns false once the run is over. */
  bool Update() {
    if (!active)
      return true;

    /* Releases queued last frame, so a click or key press lasts one frame. */
    for (size_t i = 0; i < keysToRelease.size(); ++i)
      Keyboard_SetDown(keysToRelease[i], false);
    keysToRelease.clear();
    for (size_t i = 0; i < buttonsToRelease.size(); ++i)
      Mouse_SetPressed(buttonsToRelease[i], false);
    buttonsToRelease.clear();

    float now = clock.GetElapsed();
    if (now > timeout) {
      printf("HARNESS timeout after %.0f s\n", timeout);
      return false;
    }

    if (waitFrames) {
      waitFrames--;
      return true;
    }
    if (now < waitUntil)
      return true;

    while (next < commands.size()) {
      Vector<String> const& c = commands[next++];
      String const& op = c[0];

      if (op == "wait" && c.size() == 2) {
        waitUntil = now + (float)atof(c[1].c_str());
        return true;
      }

      else if (op == "frames" && c.size() == 2) {
        waitFrames = (uint)atoi(c[1].c_str());
        return true;
      }

      else if (op == "shot" && c.size() == 2)
        Screenshot_Request(c[1]);

      else if (op == "move" && c.size() == 3) {
        Mouse_UpdatePos(V2I(atoi(c[1].c_str()), atoi(c[2].c_str())));
      }

      else if (op == "click" || op == "mousedown" || op == "mouseup") {
        MouseButton button = MouseButton_Left;
        size_t arg = 1;
        if (c.size() > 1 && ParseButton(c[1], button))
          arg = 2;
        if (op == "click" && c.size() == arg + 2)
          Mouse_UpdatePos(V2I(atoi(c[arg].c_str()), atoi(c[arg + 1].c_str())));
        else if (c.size() != arg) {
          Fail(c, "expected [BUTTON] [X Y]");
          continue;
        }

        Mouse_SetPressed(button, op != "mouseup");
        if (op == "click") {
          buttonsToRelease.push(button);
          /* A press and release in the same command spans two frames. */
          return true;
        }
      }

      else if (op == "scroll" && c.size() == 2)
        Mouse_SetScrollDelta((float)atof(c[1].c_str()));

      else if ((op == "key" || op == "keydown" || op == "keyup") && c.size() == 2) {
        Key key;
        if (!ParseKey(c[1], key)) {
          Fail(c, "unknown key");
          continue;
        }
        Keyboard_SetDown(key, op != "keyup");
        if (op == "key") {
          keysToRelease.push(key);
          return true;
        }
      }

      else if (op == "type" && c.size() >= 2) {
        String text = Rest(c, 1);
        for (size_t i = 0; i < text.size(); ++i)
          Keyboard_AddText((uchar)text[i]);
      }

      else if (op == "echo") {
        printf("HARNESS %s\n", Rest(c, 1).c_str());
        fflush(stdout);
      }

      else if (op == "quit") {
        quit = true;
        return true;
      }

      else
        Fail(c, "unknown command or wrong number of arguments");
    }

    /* Out of commands without a quit: hand the controls back. */
    printf("HARNESS done, real input restored\n");
    fflush(stdout);
    Mouse_SetSynthetic(false);
    Keyboard_SetSynthetic(false);
    active = false;
    return true;
  }
};

#endif
