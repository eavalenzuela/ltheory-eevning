#include "../Objects.h"

#include "Component/BoundingBox.h"
#include "Component/Cullable.h"
#include "Component/Drawable.h"
#include "Component/Motion.h"
#include "Component/Nameable.h"
#include "Component/Orientation.h"
#include "Component/Scriptable.h"

#include "Game/Player.h"

#include "LTE/Script.h"

#include "Luau/Luau.h"

#include "UI/Widget.h"

typedef ObjectWrapper
  < Component_BoundingBox
  < Component_Drawable
  < Component_Cullable
  < Component_Motion
  < Component_Nameable
  < Component_Orientation
  < Component_Scriptable
  < ObjectWrapperTail<ObjectType_Custom>
  > > > > > > > >
  CustomBaseT;

AutoClassDerived(ObjectCustom, CustomBaseT,
  Data, instance,
  ScriptFunction, getWidget,
  ScriptFunction, onCreate,
  ScriptFunction, onDestroy,
  ScriptFunction, onUpdate)
  DERIVED_TYPE_EX(ObjectCustom)

  ObjectCustom() {}

  Widget GetWidget(Player const& self) {
    if (getWidget) {
      Widget widget;
      getWidget->VoidCall(&widget, instance, (Object)this, self);
      return widget;
    }

    return BaseType::GetWidget(self);
  }

  void OnCreate() {
    BaseType::OnCreate();
    if (onCreate)
      onCreate->VoidCall(0, instance, (Object)this);
  }

  void OnDestroy() {
    BaseType::OnDestroy();
    if (onDestroy)
      onDestroy->VoidCall(0, instance, (Object)this);
  }

  void OnUpdate(UpdateState& state) {
    BaseType::OnUpdate(state);
    if (onUpdate)
      onUpdate->VoidCall(0, instance, (Object)this);
  }
};

DERIVED_IMPLEMENT(ObjectCustom)

DefineFunction(Object_Custom) {
  Reference<ObjectCustom> self = new ObjectCustom;

  /* A Luau object: its Update(object) runs as an object script. */
  if (Luau_IsValue(args.data)) {
    self->instance = args.data;
    self->AddScript(args.data);
    return self;
  }

  ScriptType const& type = args.data.type->GetAux().Convert<ScriptType>();
  self->instance = args.data;
  self->getWidget = type->GetFunction("GetWidget");
  self->onCreate = type->GetFunction("Create");
  self->onDestroy = type->GetFunction("Destroy");
  self->onUpdate = type->GetFunction("Update");
  return self;
}
