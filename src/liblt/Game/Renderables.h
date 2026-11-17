#ifndef Graphics_Renderables_h__
#define Graphics_Renderables_h__

#include "LTE/DeclareFunction.h"
#include "LTE/Generic.h"

DeclareFunctionArgBind(Renderable_Asteroid, Renderable,
  uint, seed)

DeclareFunctionArgBind(Renderable_Ice, Renderable,
  uint, seed)

/* A chunk of an ice field (2026-11-17): soft and rounded, deep blue; and
   sharp and faceted, pale blue. */
DeclareFunctionArgBind(Renderable_IceDeep, Renderable,
  uint, seed)

DeclareFunctionArgBind(Renderable_IceShard, Renderable,
  uint, seed)

DeclareFunctionArgBind(Renderable_Imposter, Renderable,
  Renderable, source)

DeclareFunctionArgBind(Renderable_Starfield, Renderable,
  uint, seed,
  uint, starCount)

#endif
