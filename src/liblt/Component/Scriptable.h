#ifndef Component_Scriptable_h__
#define Component_Scriptable_h__

#include "Common.h"
#include "LTE/AutoClass.h"
#include "LTE/Script.h"
#include "Luau/Luau.h"

AutoClass(ComponentScriptElement,
  Data, object,
  ScriptFunction, receive,
  ScriptFunction, update)

  ComponentScriptElement() {}
};

AutoClass(ComponentScriptable,
  Vector<ComponentScriptElement>, elements)

  ComponentScriptable() {}

  void OnUpdate(ObjectT* self) {
    Object selfRef = self;
    for (int i = 0; i < (int)elements.size(); ++i) {
      ComponentScriptElement& element = elements[i];
      bool alive = true;
      if (element.update)
        element.update->VoidCall(&alive, element.object, selfRef);
      else
        alive = Luau_ObjectScriptUpdate(element.object, Data(selfRef));
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
    /* A Luau script has no LTSL functions; it is called through Luau. */
    if (Luau_IsValue(object)) {
      Scriptable.elements.push(ComponentScriptElement(object, nullptr, nullptr));
      return;
    }

    ScriptType type = object.type->GetAux().Convert<ScriptType>();
    ScriptFunction receive = type->GetFunction("Receive");
    ScriptFunction update = type->GetFunction("Update");
    if (!update)
      error("Script object must have 'Update' function");

    Scriptable.elements.push(ComponentScriptElement(object, receive, update));
  }

  void OnMessage(Data& message) {
    for (size_t i = 0; i < Scriptable.elements.size(); ++i) {
      ComponentScriptElement& element = Scriptable.elements[i];
      if (element.receive)
        element.receive->VoidCall(
          0, element.object, (Object)this,
          DataRef(Type_Get<Data>(), (void*)&message));
      else if (!element.update)
        Luau_ObjectScriptReceive(element.object, Data((Object)this), message);
    }

    BaseT::OnMessage(message);
  }
};

#endif
