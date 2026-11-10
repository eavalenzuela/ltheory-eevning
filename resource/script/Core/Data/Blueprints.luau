--!strict
-- What can be built, and from what.
--
-- Every module, charge and hull has a blueprint. A run of a blueprint
-- turns minerals into the product: one module or hull, or a hundred
-- rounds. The minerals are worked out from the product's base price, so
-- that at normal prices the materials cost about 60% of what the product
-- sells for: building is worth it, and the gap pays for the blueprint
-- and the builder's time.
--
-- A blueprint is not used up; it costs ten times its product.

local Modules = require("@lt/Core/Data/Modules")
local Ores = require("@lt/Core/Data/Ores")
local Ships = require("@lt/Core/Data/Ships")

export type Blueprint = {
  id: string,               -- "blueprint.<product>"
  product: string,
  name: string,
  perRun: number,           -- units made by one run
  seconds: number,          -- per run
  materials: { { type: string, quantity: number } },  -- per run
  basePrice: number,        -- of the blueprint itself
}

local MATERIAL_SHARE = 0.6

-- How a product's material cost is split between minerals.
local MIX: { [string]: { [string]: number } } = {
  charge = { ["mineral.iron"] = 0.7, ["mineral.silicon"] = 0.3 },
  module = { ["mineral.iron"] = 0.5, ["mineral.silicon"] = 0.2, ["mineral.copper"] = 0.3 },
  ship = { ["mineral.iron"] = 0.45, ["mineral.silicon"] = 0.15, ["mineral.copper"] = 0.2, ["mineral.titanium"] = 0.2 },
}

local Blueprints = { list = {} :: { Blueprint }, byId = {} :: { [string]: Blueprint }, byProduct = {} :: { [string]: Blueprint } }

local function add(product: string, name: string, category: string, basePrice: number, perRun: number, seconds: number)
  local materials = {}
  -- In mineral order, so every blueprint lists them the same way.
  for _, mineral in Ores.minerals do
    local share = MIX[category][mineral.id]
    if share then
      local quantity = math.max(1, math.floor(MATERIAL_SHARE * basePrice * perRun * share / mineral.basePrice + 0.5))
      table.insert(materials, { type = mineral.id, quantity = quantity })
    end
  end
  local blueprint: Blueprint = {
    id = "blueprint." .. product, product = product, name = name .. " Blueprint", perRun = perRun,
    seconds = seconds, materials = materials, basePrice = basePrice * perRun * 10,
  }
  table.insert(Blueprints.list, blueprint)
  Blueprints.byId[blueprint.id] = blueprint
  Blueprints.byProduct[product] = blueprint
end

for _, module in Modules.list do
  add(module.id, module.name, "module", module.basePrice, 1, 120 + module.basePrice // 100)
end
for _, charge in Modules.charges do
  -- Crystals are made one at a time; rounds and missiles by the hundred.
  local perRun = if charge.family == "laser" then 1 else 100
  add(charge.id, charge.name, "charge", charge.basePrice, perRun, 60)
end
for _, hull in Ships.list do
  if hull.class ~= "capsule" then
    add(hull.id, hull.name, "ship", hull.basePrice, 1, 600 + hull.basePrice // 200)
  end
end

-- Jobs a pilot can run at once before any skill adds more.
Blueprints.JOB_SLOTS = 2
-- The fee to install a job, as a share of what it will make.
Blueprints.JOB_FEE = 0.02

return Blueprints
