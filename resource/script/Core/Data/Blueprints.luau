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

local Components = require("@lt/Core/Data/Components")
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
-- A module or a hull is built from components and from minerals: this
-- share of its material cost is components.
local COMPONENT_SHARE = 0.5

-- How a product's material cost is split between minerals.
local MIX: { [string]: { [string]: number } } = {
  charge = { ["mineral.iron"] = 0.7, ["mineral.silicon"] = 0.3 },
  module = { ["mineral.iron"] = 0.5, ["mineral.silicon"] = 0.2, ["mineral.copper"] = 0.3 },
  ship = { ["mineral.iron"] = 0.45, ["mineral.silicon"] = 0.15, ["mineral.copper"] = 0.2, ["mineral.titanium"] = 0.2 },
  -- Larger hulls need what safe space does not have.
  cruiser = { ["mineral.iron"] = 0.4, ["mineral.silicon"] = 0.1, ["mineral.copper"] = 0.15, ["mineral.titanium"] = 0.2,
    ["mineral.cobalt"] = 0.15 },
  battleship = { ["mineral.iron"] = 0.35, ["mineral.silicon"] = 0.1, ["mineral.copper"] = 0.15, ["mineral.titanium"] = 0.15,
    ["mineral.cobalt"] = 0.15, ["mineral.iridium"] = 0.1 },
}

-- The components a module is built around, by what it is, as shares of
-- the component part of its cost.
local function moduleParts(module: Modules.ModuleType): { { any } }
  local id = module.id
  if module.weapon then
    return { { "component.weapon", 0.7 }, { "component.electronics", 0.3 } }
  elseif module.miner then
    return { { "component.weapon", 0.5 }, { "component.electronics", 0.5 } }
  elseif string.sub(id, 1, 7) == "shield." then
    return { { "component.emitter", 0.7 }, { "component.electronics", 0.3 } }
  elseif string.sub(id, 1, 6) == "armor." or id == "damage.control" then
    return { { "component.plating", 1 } }
  elseif string.sub(id, 1, 11) == "afterburner" or id == "overdrive" or id == "nanofiber" then
    return { { "component.thruster", 1 } }
  elseif string.sub(id, 1, 10) == "capacitor." then
    return { { "component.capacitor", 1 } }
  end
  return { { "component.electronics", 1 } }
end

local Blueprints = { list = {} :: { Blueprint }, byId = {} :: { [string]: Blueprint }, byProduct = {} :: { [string]: Blueprint } }

-- 'mix' is how the mineral part of the cost is split; 'parts', if
-- given, the components that take COMPONENT_SHARE of it first.
local function add(product: string, name: string, mix: { [string]: number }, basePrice: number, perRun: number, seconds: number,
  parts: { { any } }?)
  local materials = {}
  local budget = MATERIAL_SHARE * basePrice * perRun
  if parts then
    for _, part in parts do
      local component = Components.byId[part[1]]
      local quantity = math.max(1, math.floor(COMPONENT_SHARE * budget * part[2] / component.basePrice + 0.5))
      table.insert(materials, { type = component.id, quantity = quantity })
    end
    budget *= 1 - COMPONENT_SHARE
  end
  -- In mineral order, so every blueprint lists them the same way.
  for _, mineral in Ores.minerals do
    local share = mix[mineral.id]
    if share then
      local quantity = math.max(1, math.floor(budget * share / mineral.basePrice + 0.5))
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

-- Components first: everything else is built from them. They are made
-- ten to a run.
for _, component in Components.list do
  add(component.id, component.name, component.mix, component.basePrice, 10, 60 + component.basePrice // 5)
end

for _, module in Modules.list do
  add(module.id, module.name, MIX.module, module.basePrice, 1, 120 + module.basePrice // 100, moduleParts(module))
end
for _, charge in Modules.charges do
  -- Crystals are made one at a time; rounds and missiles by the hundred.
  local perRun = if charge.family == "laser" then 1 else 100
  add(charge.id, charge.name, MIX.charge, charge.basePrice, perRun, 60)
end
for _, hull in Ships.list do
  if hull.class ~= "capsule" and not hull.restricted then
    local mix = if hull.class == "battleship" then MIX.battleship
      elseif hull.class == "cruiser" or hull.class == "barge" then MIX.cruiser
      else MIX.ship
    -- (the largest hulls take most of a day, not a week)
    add(hull.id, hull.name, mix, hull.basePrice, 1, math.min(72000, 600 + hull.basePrice // 200), Components.HULL)
  end
end

-- Jobs a pilot can run at once before any skill adds more.
Blueprints.JOB_SLOTS = 2
-- The fee to install a job, as a share of what it will make.
Blueprints.JOB_FEE = 0.02

return Blueprints
