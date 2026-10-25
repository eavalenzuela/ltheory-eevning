--!strict
-- The model of a turret (Luau port of Item/TurretType.lts), generated once
-- by the engine.

local PlateModel = require("@lt/Item/PlateModel")

return {
  Generate = function(): Model
    return PlateModel.Build(8,
      { { center = vector.create(0, 0, 0), scale = 0.75 * vector.create(1.0, 0.5, 1.0), bevel = 0.5 } },
      { { point = vector.create(-1, 0, 0), strength = 0.25 }, { point = vector.create(1, 0, 0), strength = 0.25 } })
  end,
}
