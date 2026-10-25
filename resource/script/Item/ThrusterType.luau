--!strict
-- The model of a thruster (Luau port of Item/ThrusterType.lts), generated
-- once by the engine.

local PlateModel = require("@lt/Item/PlateModel")

return {
  Generate = function(): Model
    return PlateModel.Build(8,
      { { center = vector.create(0, 0, 0), scale = vector.create(0.25, 0.10, 0.5), bevel = 0.25 } },
      { { point = vector.create(0, 0, 0), strength = 0.25 }, { point = vector.create(0, 0, 0.5), strength = 0.25 } })
  end,
}
