#include "../Objects.h"

#include "Component/BoundingBox.h"
#include "Component/Cullable.h"
#include "Component/Drawable.h"
#include "Component/Motion.h"
#include "Component/Nameable.h"
#include "Component/Orientation.h"
#include "Component/Scriptable.h"

#include "Luau/Luau.h"

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
  Data, instance)
  DERIVED_TYPE_EX(ObjectCustom)

  ObjectCustom() {}
};

DERIVED_IMPLEMENT(ObjectCustom)

DefineFunction(Object_Custom) {
  Reference<ObjectCustom> self = new ObjectCustom;

  /* A Luau object: its Update(object) runs as an object script. */
  self->instance = args.data;
  self->AddScript(args.data);
  return self;
}
