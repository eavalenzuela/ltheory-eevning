#ifndef Luau_ScriptCall_h__
#define Luau_ScriptCall_h__

#include "Luau/Luau.h"
#include "LTE/Type.h"

/* Calling script functions from the engine by name ("Object/System:Init").
   If resource/script/Object/System.luau exists the Luau module's function
   is called, otherwise the LTSL one, so scripts can move to Luau one at a
   time. Arguments are passed by type through the bindings' marshalling. */

LT_API bool Script_Invoke(
  String const& path,
  TypeT* returnType,
  void* returnValue,
  uint argc,
  TypeT* const* argTypes,
  void* const* args);

template <class R, class... A>
R Script_Call(String const& path, A const&... args) {
  R result = R();
  TypeT* types[] = { Type_Get<A>().t..., nullptr };
  void* values[] = { (void*)&args..., nullptr };
  Script_Invoke(path, Type_Get<R>().t, &result, sizeof...(A), types, values);
  return result;
}

template <class... A>
void Script_CallVoid(String const& path, A const&... args) {
  TypeT* types[] = { Type_Get<A>().t..., nullptr };
  void* values[] = { (void*)&args..., nullptr };
  Script_Invoke(path, nullptr, nullptr, sizeof...(A), types, values);
}

#endif
