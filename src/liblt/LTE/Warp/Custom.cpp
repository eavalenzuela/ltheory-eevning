#include "../Warps.h"

#include "LTE/AutoClass.h"
#include "LTE/Data.h"
#include "LTE/V3.h"
#include "Luau/Luau.h"

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
  if (!Luau_IsValue(args.data))
    error("Warp_Custom expects a Luau table");

  Reference<WarpLuau> self = new WarpLuau;
  self->instance = args.data;
  return self;
}
