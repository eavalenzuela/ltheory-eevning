#ifndef Light_h__
#define Light_h__

#include "Object.h"
#include "ObjectWrapper.h"

#include "Component/Attachable.h"
#include "Component/Orientation.h"
#include "LTE/Color.h"

typedef ObjectWrapper
  < Component_Attachable
  < Component_Orientation
  < ObjectWrapperTail<ObjectType_Light>
  > > >
  LightBaseT;

struct Light : public LightBaseT {
  typedef Light SelfType;
  Color color;
  float radius;
  float visibility;
  bool flare;

  /* How far off the light's flare is taken to be, when deciding whether
   * something is in front of it and hides it; 0 for as far as the light
   * is. (A star's light stands far beyond the disc that is drawn for the
   * star, and its flare is not to be hidden by that disc.) */
  float flareDepth;

  Light() :
    color(1),
    radius(1),
    visibility(1),
    flare(true),
    flareDepth(0)
    {}

  FIELDS {
    MAPFIELD(color)
    MAPFIELD(radius)
    LightBaseT::MapFields(type, addr, m, aux);
  }
};

LT_API LightRef Light_Create(ObjectT* parent);

#endif
