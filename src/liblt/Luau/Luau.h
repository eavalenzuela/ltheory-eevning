#ifndef Luau_Luau_h__
#define Luau_Luau_h__

#include "LTE/Common.h"
#include "LTE/String.h"

/* Luau scripting. Every engine function registered through the reflection
   system (FreeFunction, DefineFunction, member functions) is callable from
   Luau without hand-written bindings:

   - Free functions and their aliases are globals: Object_Universe(39, 0).
   - Engine values are methods-and-fields userdata: ship:GetPos(),
     data.bids, a + b (through the engine's operator functions).
   - bool, numbers and strings map to Luau's; V2 and V3 (float or double)
     to Luau vectors (z = 0 for V2); a null reference to nil.
   - Integer parameters accept only whole numbers in range, and 64-bit
     results beyond 2^53 raise an error instead of rounding.

   Scripts live in resource/script as .luau files and load each other with
   require("@lt/Path/Module"). */

struct lua_State;

/* The shared state, created and bound on first use. */
LT_API lua_State* Luau_GetState();

/* Discard the state (and every loaded module), e.g. to reload scripts. */
LT_API void Luau_Reset();

/* Whether resource/script/<module>.luau exists. */
LT_API bool Luau_HasModule(String const& module);

/* Run a module (cached) and push its result; on failure print the error
   with a traceback, push nothing and return false. */
LT_API bool Luau_Require(String const& module);

/* lua_pcall with a traceback; on failure print it, pop it and return
   false. */
LT_API bool Luau_Call(int nargs, int nresults);

/* Object scripts (Object_AddScript) written in Luau: a table whose
   Update(object) runs every frame (returning false removes it) and whose
   Receive(object, message) gets the object's messages. */
LT_API bool Luau_IsValue(Data const& value);
LT_API bool Luau_ObjectScriptUpdate(Data const& script, Data const& object);
LT_API void Luau_ObjectScriptReceive(Data const& script, Data const& object, Data const& message);

/* Luau type definitions for every bound function and engine type, for the
   checker (tools: luaucheck). */
LT_API String Luau_GenerateDefinitions();
LT_API bool Luau_WriteDefinitions(char const* path);

#endif
