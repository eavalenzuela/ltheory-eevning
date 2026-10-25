#ifndef Universe_h__
#define Universe_h__

#include "Object.h"
#include "ObjectWrapper.h"
#include "Item.h"

#include "Component/Interior.h"
#include "Component/Nameable.h"
#include "Component/Resources.h"
#include "Component/Seeded.h"

#include "LTE/Distribution.h"

typedef ObjectWrapper
  < Component_Interior
  < Component_Nameable
  < Component_Resources
  < Component_Seeded
  < ObjectWrapperTail<ObjectType_Universe>
  > > > > >
  UniverseBaseT;

struct Universe : public UniverseBaseT {
  uint depth;
  Time age;
  /* Sub-tick remainder carried between Universe_Advance calls. */
  double ageRemainder;
  Distribution<Item> colonyTypes;
  Vector<Object> loadedRegions;
  Item currencyBasis;

  Universe() :
    age(0),
    ageRemainder(0)
    {}
};

LT_API Universe* Universe_Get();

/* Advance the active universe's clock by 'dt' seconds. */
LT_API void Universe_Advance(float dt);

#endif
