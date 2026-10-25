#include "Resources.h"

#include "Game/Item.h"
#include "Game/Object.h"

#include "LTE/Function.h"

VoidFreeFunction(Object_AddResource,
  "Add 'item' to 'objects' list of natural resources with weight 'w'",
  Object, object,
  Item, item,
  float, weight)
{
  ComponentResources* resources = object->GetResources();
  LTE_ASSERT(resources != nullptr);
  resources->elements[item] = weight;
} FunctionAlias(Object_AddResource, AddResource);

FreeFunction(int, Object_GetResourceCount,
  "Return the number of resource types in 'object'",
  Object, object)
{
  ComponentResources* resources = object->GetResources();
  return resources ? (int)resources->elements.size() : 0;
} FunctionAlias(Object_GetResourceCount, GetResourceCount);

FreeFunction(Item, Object_GetResource,
  "Return the resource type at 'index' in 'object'",
  Object, object,
  int, index)
{
  ComponentResources* resources = object->GetResources();
  if (!resources || index < 0 || index >= (int)resources->elements.size())
    return nullptr;
  return resources->elements.entries[index].key;
} FunctionAlias(Object_GetResource, GetResource);
