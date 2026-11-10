#include "LTE/Function.h"
#include "LTE/Mesh.h"

TypeAlias(Reference<MeshT>, Mesh);

DefineConversion(mesh_to_geometry, Mesh, Geometry) {
  dest = (Geometry)src;
}

VoidFreeFunction(Mesh_Center,
  "Translate 'mesh' such that it is centered about the origin",
  Mesh, mesh)
{
  mesh->TranslateToCenter();
} FunctionAlias(Mesh_Center, Center);

FreeFunctionNoParams(Mesh, Mesh_Create, "Create a new, empty Mesh") {
  return Mesh_Create();
}

VoidFreeFunction(Mesh_SetOcclusion,
  "Set the occlusion factor of 'mesh' to a constant of 'occlusion'",
  Mesh, mesh,
  float, occlusion)
{
  mesh->SetU(occlusion);
} FunctionAlias(Mesh_SetOcclusion, SetOcclusion);

FreeFunction(Mesh, Mesh_Scale,
  "Scale 'mesh' by 'scale' along each axis, and return it",
  Mesh, mesh,
  V3, scale)
{
  return mesh->Scale(scale);
} FunctionAlias(Mesh_Scale, Scale);

FreeFunction(Mesh, Mesh_ReverseWinding,
  "Turn 'mesh' inside out (so that its inner faces are the ones drawn), and return it",
  Mesh, mesh)
{
  return mesh->ReverseWinding();
} FunctionAlias(Mesh_ReverseWinding, ReverseWinding);

FreeFunction(Mesh, Mesh_SetU,
  "Set the u coordinate of every vertex of 'mesh' to 'u', and return it",
  Mesh, mesh,
  float, u)
{
  return mesh->SetU(u);
} FunctionAlias(Mesh_SetU, SetU);
