#include "../Warps.h"

#include "LTE/AutoClass.h"
#include "LTE/Script.h"
#include "LTE/V3.h"
#include "Luau/Luau.h"

namespace {
  AutoClassDerived(WarpCustom, WarpT,
    Data, instance,
    ScriptFunction, getDelta)
    DERIVED_TYPE_EX(WarpCustom)

    WarpCustom() {}

    V3 GetDelta(V3 const& p) const {
      V3 result;
      getDelta->VoidCall(&result, instance, p);
      return result;
    }
  };
}

namespace {
  /* A Luau object with GetDelta(point) -> vector. */
  AutoClassDerived(WarpLuau, WarpT,
    Data, instance)
    DERIVED_TYPE_EX(WarpLuau)

    WarpLuau() {}

    V3 GetDelta(V3 const& p) const {
      V3 result(0);
      Luau_CallMethodV3(instance, "GetDelta", p, result);
      return result;
    }
  };
}

DefineFunction(Warp_Custom) {
  if (Luau_IsValue(args.data)) {
    Reference<WarpLuau> self = new WarpLuau;
    self->instance = args.data;
    return self;
  }

  ScriptType type = args.data.type->GetAux().Convert<ScriptType>();
  Reference<WarpCustom> self = new WarpCustom;
  self->instance = args.data;
  self->getDelta = type->GetFunction("GetDelta");
  return self;
}
