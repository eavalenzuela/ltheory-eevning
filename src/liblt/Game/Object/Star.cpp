#include "../Objects.h"

#include "Component/Drawable.h"
#include "Component/Orientation.h"

#include "Game/Light.h"
#include "Game/Messages.h"

#include "LTE/Function.h"
#include "LTE/Math.h"
#include "LTE/Pool.h"
#include "LTE/RNG.h"

typedef ObjectWrapper
  < Component_Drawable
  < Component_Orientation
  < ObjectWrapperTail<ObjectType_Star>
  > > >
  StarBaseT;

AutoClassDerived(Star, StarBaseT,
  LightRef, light,
  Color, color,
  float, flareDepth)

  DERIVED_TYPE_EX(Star)
  POOLED_TYPE

  Star() :
    flareDepth(0)
    {}

  Signature GetSignature() const {
    return Signature(1e5f, Mix(12, 16, Saturate(color.z)), 0.25f, 1);
  }

  void OnMessage(Data& m) {
    BaseType::OnMessage(m);
    if (m.type == Type_Get<MessageGetColor>())
      m.Convert<MessageGetColor>().color = color;
  }

  void OnUpdate(UpdateState& state) {
    BaseType::OnUpdate(state);

    if (!light)
      light = Light_Create(this);
    light->color = 10.0f * color;
    light->radius = 3000000;
    light->flareDepth = flareDepth;
  }
};

DERIVED_IMPLEMENT(Star)

DefineFunction(Object_Star) {
  Reference<Star> self = new Star;
  self->color = args.color;
  return self;
}

VoidFreeFunction(Star_SetColor,
  "Set the colour of the star 'star', and so of its light and of the flare drawn for it",
  Object, star,
  Color, color)
{
  if (star->GetType() == ObjectType_Star)
    ((Star*)star.t)->color = color;
}

VoidFreeFunction(Star_SetFlareDepth,
  "Set how far off the flare of the star 'star' is taken to be when deciding what hides it; 0 for as far as the star is",
  Object, star,
  float, depth)
{
  if (star->GetType() == ObjectType_Star)
    ((Star*)star.t)->flareDepth = depth;
}
