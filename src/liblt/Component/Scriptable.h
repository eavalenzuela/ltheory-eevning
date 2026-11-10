#ifndef Component_Scriptable_h__
#define Component_Scriptable_h__

#include "Common.h"
#include "LTE/AutoClass.h"
#include "LTE/Data.h"
#include "LTE/Vector.h"
#include "Luau/Luau.h"

AutoClass(ComponentScriptElement,
  Data, object)

  ComponentScriptElement() {}
};

AutoClass(ComponentScriptable,
  Vector<ComponentScriptElement>, elements)

  ComponentScriptable() {}

  void OnUpdate(ObjectT* self) {
    Object selfRef = self;
    for (int i = 0; i < (int)elements.size(); ++i) {
      ComponentScriptElement& element = elements[i];
      bool alive = Luau_ObjectScriptUpdate(element.object, Data(selfRef));
      if (!alive) {
        elements.removeIndex(i);
        i--;
        continue;
      }
    }
  }
};

AutoComponent(Scriptable)
  void OnUpdate(UpdateState& s) {
    Scriptable.OnUpdate(this);
    BaseT::OnUpdate(s);
  }

  void AddScript(Data const& object) {
    /* An object script is a Luau table; it is called through Luau. */
    if (!Luau_IsValue(object))
      error("Script object must be a Luau table");

    Scriptable.elements.push(ComponentScriptElement(object));
  }

  void OnMessage(Data& message) {
    for (size_t i = 0; i < Scriptable.elements.size(); ++i) {
      ComponentScriptElement& element = Scriptable.elements[i];
      Luau_ObjectScriptReceive(element.object, Data((Object)this), message);
    }

    BaseT::OnMessage(message);
  }
};

#endif
