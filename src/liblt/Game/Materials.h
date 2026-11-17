#ifndef Materials_h__
#define Materials_h__

#include "LTE/DeclareFunction.h"
#include "LTE/ShaderInstance.h"

DeclareFunctionNoParams(Material_Debug, ShaderInstance)

DeclareFunctionNoParams(Material_Grass, ShaderInstance)

DeclareFunctionNoParams(Material_Ice, ShaderInstance)

/* Ice of an ice field (2026-11-17): deep blue, and pale blue. */
DeclareFunctionNoParams(Material_IceDeep, ShaderInstance)

DeclareFunctionNoParams(Material_IcePale, ShaderInstance)

DeclareFunctionNoParams(Material_Metal, ShaderInstance)

DeclareFunctionNoParams(Material_Rock, ShaderInstance)

DeclareFunctionNoParams(Material_RockShiny, ShaderInstance)

DeclareFunctionNoParams(Material_Water, ShaderInstance)

#endif
