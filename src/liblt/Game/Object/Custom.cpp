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
  Data, instance,
  bool, scenery)
  DERIVED_TYPE_EX(ObjectCustom)

  ObjectCustom() :
    scenery(false)
    {}

  bool IsMovable() const {
    return !scenery;
  }
};

DERIVED_IMPLEMENT(ObjectCustom)

DefineFunction(Object_Custom) {
  Reference<ObjectCustom> self = new ObjectCustom;

  /* A Luau object: its Update(object) runs as an object script. */
  self->instance = args.data;
  self->AddScript(args.data);
  return self;
}

/* Scenery: something a script puts where it should be drawn each frame,
 * that is no part of the physical world (a planet in the far distance,
 * drawn near and small). It is not movable and never enters the spatial
 * partition, so nothing can query or hit it.
 *
 * This matters for more than tidiness. The partition is a grid of cells
 * about a kilometre across, into which a movable object is put afresh
 * every frame, cell by cell: for something the size of a planet that is
 * millions of cells, and sixteen such bodies took the game from 150
 * frames a second to 7. */
DefineFunction(Object_Scenery) {
  Reference<ObjectCustom> self = new ObjectCustom;
  self->instance = args.data;
  self->AddScript(args.data);
  self->scenery = true;
  self->BoundingBox.inSpatialGrid = kOutOfSpatialGrid;
  return self;
}
