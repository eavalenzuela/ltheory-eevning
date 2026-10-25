#ifndef LTE_Keyboard_h__
#define LTE_Keyboard_h__

#include "Common.h"

namespace LTE {
  LT_API const char* Key_Name(Key key);

  LT_API void Keyboard_AddDown(Key key);

  LT_API void Keyboard_AddText(uchar c);

  LT_API void Keyboard_Block();

  LT_API bool Keyboard_Down(Key key);

  LT_API Vector<Key> const& Keyboard_GetKeysPressed();

  LT_API bool Keyboard_IsBlocked();

  LT_API void Keyboard_ModifyString(String& str, int& cursor);

  /* The characters typed this frame. */
  LT_API String Keyboard_GetText();

  LT_API bool Keyboard_Pressed(Key key);

  LT_API bool Keyboard_Released(Key key);

  LT_API void Keyboard_Update(bool hasFocus);

  /* Synthetic mode ignores the real keyboard; keys change only through
     Keyboard_SetDown (used by the launcher's test harness). */
  LT_API bool Keyboard_IsSynthetic();

  LT_API void Keyboard_SetDown(Key key, bool down);

  LT_API void Keyboard_SetSynthetic(bool synthetic);

  inline bool Keyboard_Alt() {
    return Keyboard_Down(Key_LAlt) || Keyboard_Down(Key_RAlt);
  }

  inline bool Keyboard_Control() {
    return Keyboard_Down(Key_LControl) || Keyboard_Down(Key_RControl);
  }

  inline bool Keyboard_Shift() {
    return Keyboard_Down(Key_LShift) || Keyboard_Down(Key_RShift);
  }

  inline bool Keyboard_System() {
    return Keyboard_Down(Key_LSystem) || Keyboard_Down(Key_RSystem);
  }
}

#endif
