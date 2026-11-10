#include "LTE/Function.h"
#include "LTE/CubeMap.h"
#include "LTE/Screenshot.h"
#include "LTE/ShaderInstance.h"

/* Cube maps for scripts: a picture of every direction from a point, which
   is how a globe's surface is kept (it has no poles to pinch at). A script
   draws one with a shader and hands it to another shader to read. */

TypeAlias(Reference<CubeMapT>, CubeMap);

FreeFunction(CubeMap, CubeMap_Create,
  "Create a cube map whose faces are 'resolution' pixels square, 8 bits a channel",
  int, resolution)
{
  return CubeMap_Create((uint)resolution);
}

FreeFunction(CubeMap, CubeMap_CreateHDR,
  "Create a cube map whose faces are 'resolution' pixels square, 16-bit float a channel (for heights and normals)",
  int, resolution)
{
  return CubeMap_Create((uint)resolution, GL_TextureFormat::RGBA16F);
}

VoidFreeFunction(CubeMap_GenerateFromShaderInstance,
  "Fill 'cubeMap' by executing 'shaderInstance' once for every direction",
  CubeMap, cubeMap,
  ShaderInstance, shaderInstance)
{
  shaderInstance->Begin();
  cubeMap->GenerateFromShader(shaderInstance->GetShader());
  shaderInstance->End();
} FunctionAlias(CubeMap_GenerateFromShaderInstance, GenerateFromShader);

VoidFreeFunction(ShaderInstance_SetCubeMap,
  "Set the cube map variable 'name' in 'instance' to 'value'",
  ShaderInstance, instance,
  String, name,
  CubeMap, value)
{
  instance->SetCubeMap(name, value);
} FunctionAlias(ShaderInstance_SetCubeMap, SetCubeMap);

/* (Here because it is for the same scripts: an app that takes its own
   pictures, such as a viewer that goes through a list of views.) */
VoidFreeFunction(Screenshot_Save,
  "Save the frame being drawn as 'name'.png in the screenshot directory, once it is complete",
  String, name)
{
  Screenshot_Request(name);
}
