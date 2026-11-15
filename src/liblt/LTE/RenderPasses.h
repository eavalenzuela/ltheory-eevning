#ifndef LTE_RenderPasses_h__
#define LTE_RenderPasses_h__

#include "DeclareFunction.h"
#include "RenderPass.h"
#include "String.h"

DeclareFunction(RenderPass_Aberration, RenderPass,
  float, strength)

DeclareFunction(RenderPass_Composite, RenderPass,
  Vector<RenderPass>, passes)

DeclareFunction(RenderPass_Bloom, RenderPass,
  int, radius,
  float, variance)

DeclareFunction(RenderPass_BloomLight, RenderPass,
  int, radius)

DeclareFunctionNoParams(RenderPass_MotionBlur, RenderPass)

DeclareFunction(RenderPass_PostFilter, RenderPass,
  String, shaderPath)

DeclareFunction(RenderPass_RadialBlur, RenderPass,
  V2, center,
  float, radius,
  float, strength,
  float, falloff)

DeclareFunctionNoParams(RenderPass_Tonemap, RenderPass)

/* Switch a pass off, or on again, by its name (RenderPassT::GetName):
 * one that is off is not rendered, wherever it stands in whatever list.
 * Every pass is on when the program starts, and nothing of this is kept
 * between one run and the next: whoever wants a pass off says so at
 * each start. (The settings' own "Graphics/<type>" switches are kept in
 * cache/settings.bin, where every app that runs from this folder would
 * get them.) */
DeclareFunction(RenderPass_SetEnabled, void,
  String, name,
  bool, enabled)

/* Whether a name is switched on (RenderPass_SetEnabled): for a pass
 * that has a part of what it does under a name of its own, where
 * leaving the whole pass out would leave out something the rest of the
 * frame needs. The global lighting's sun and sky light is "Global
 * Light" (off, the light buffer is still cleared); the local
 * lighting's lights are "Local Lights" (off, what is lit is still put
 * together). */
LT_API bool RenderPass_IsEnabled(char const* name);

#endif
