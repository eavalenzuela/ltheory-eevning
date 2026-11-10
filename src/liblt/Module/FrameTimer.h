#ifndef Module_FrameTimer_h__
#define Module_FrameTimer_h__

#include "Common.h"
#include "LTE/DeclareFunction.h"

DeclareFunctionNoParams(FrameTimer_Get, float)
DeclareFunctionNoParams(FrameTimer_GetEMA01, float)
DeclareFunctionNoParams(FrameTimer_GetEMA1, float)
DeclareFunctionNoParams(FrameTimer_GetEMA10, float)

/* Make every frame report exactly 'dt' seconds, whatever the wall clock
   says (0 restores real time). A run under a fixed step advances the same
   way every time, which is what screenshot comparison needs. */
LT_API void FrameTimer_SetFixedStep(float dt);

#endif
