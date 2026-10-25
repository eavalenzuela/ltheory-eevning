--!strict
-- The model of a TransferUnit module (Luau port of Item/TransferUnitType.lts),
-- generated once by the engine.

local PlateModel = require("@lt/Item/PlateModel")

return {
  Generate = function(): Model
    return PlateModel.Build(8, {
      { center = vector.create(0, 0.25, 2.0), scale = vector.create(0.2, 0.4, 1.8), bevel = 0.05 },
      { center = vector.create(0, 0.25, 1.2), scale = vector.create(0.8, 0.2, 1.2), bevel = 0.05 },
    })
  end,
}
