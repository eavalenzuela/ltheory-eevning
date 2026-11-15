#ifndef RenderPasses_h__
#define RenderPasses_h__

#include "Game/Common.h"
#include "LTE/DeclareFunction.h"
#include "LTE/RenderPass.h"
#include "LTE/V3.h"
#include "LTE/V4.h"

DeclareFunctionNoParams(RenderPass_Blended, RenderPass)

DeclareFunction(RenderPass_Camera, RenderPass,
  Camera, camera)

DeclareFunction(RenderPass_Clear, RenderPass,
  V4, value)

DeclareFunctionNoParams(RenderPass_ClearDepth, RenderPass)

DeclareFunctionNoParams(RenderPass_DepthPrepass, RenderPass)

DeclareFunctionNoParams(RenderPass_DustClouds, RenderPass)

DeclareFunctionNoParams(RenderPass_GBuffer, RenderPass)

DeclareFunctionNoParams(RenderPass_GlobalLighting, RenderPass)

DeclareFunctionNoParams(RenderPass_LocalLighting, RenderPass)

DeclareFunctionNoParams(RenderPass_LensFlares, RenderPass)

DeclareFunctionNoParams(RenderPass_Particles, RenderPass)

DeclareFunctionNoParams(RenderPass_SMAA, RenderPass)

/* What every SMAA pass shows, and how it blends: for running a fault in
 * the picture down to one of the pass's three steps on a machine that
 * cannot be seen from where the fault is looked for. 'view' 0 is the
 * picture, 1 the edges the first step found (red: an edge to the left
 * of the pixel; green: one above it), 2 the weights the second step
 * made of them. 'plainBlend' has the third step blend as the method's
 * authors wrote it, in place of this program's own way. Nothing of it
 * is kept between runs: the picture, and this program's blend. */
DeclareFunction(RenderPass_SMAASet, void,
  int, view,
  bool, plainBlend)

DeclareFunctionNoParams(RenderPass_SSAO, RenderPass)

DeclareFunctionNoParams(RenderPass_Visibility, RenderPass)

#endif
