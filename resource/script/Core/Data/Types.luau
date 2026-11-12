--!strict
-- One place to ask about any kind of item: a module, a charge, later a
-- commodity or a packaged hull.

local Blueprints = require("@lt/Core/Data/Blueprints")
local Boosters = require("@lt/Core/Data/Boosters")
local Components = require("@lt/Core/Data/Components")
local Drones = require("@lt/Core/Data/Drones")
local Implants = require("@lt/Core/Data/Implants")
local Modules = require("@lt/Core/Data/Modules")
local Ores = require("@lt/Core/Data/Ores")
local Planets = require("@lt/Core/Data/Planets")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")
local Structures = require("@lt/Core/Data/Structures")

local Types = {}

export type Info = {
  id: string,
  name: string,
  category: "module" | "charge" | "goods" | "ore" | "mineral" | "component" | "ship" | "blueprint" | "skillbook" | "structure"
    | "planetary" | "drone" | "implant",
  volume: number,     -- m3 per unit
  basePrice: number,  -- credits per unit
  -- No station has it to sell unless a pilot sold it there: a tech 2
  -- module, an invented blueprint, a datacore.
  scarce: boolean?,
}

local byId: { [string]: Info } = {}

for _, m in Modules.list do
  byId[m.id] = { id = m.id, name = m.name, category = "module", volume = m.volume, basePrice = m.basePrice,
    scarce = if m.tech == 2 or m.internal or m.meta then true else nil }
end
for _, c in Modules.charges do
  byId[c.id] = { id = c.id, name = c.name, category = "charge", volume = c.volume, basePrice = c.basePrice,
    scarce = if c.tech == 2 then true else nil }
end

for _, ore in Ores.list do
  byId[ore.id] = { id = ore.id, name = ore.name, category = "ore", volume = ore.volume, basePrice = ore.basePrice }
end
for _, mineral in Ores.minerals do
  byId[mineral.id] = { id = mineral.id, name = mineral.name, category = "mineral", volume = mineral.volume, basePrice = mineral.basePrice }
end

for _, component in Components.list do
  byId[component.id] = { id = component.id, name = component.name, category = "component", volume = component.volume,
    basePrice = component.basePrice }
end

-- A hull, packaged: bought and sold like anything else, and assembled
-- into a ship at a station. (Nobody sells capsules.)
for _, hull in Ships.list do
  if hull.class ~= "capsule" and not hull.restricted then
    byId[hull.id] = { id = hull.id, name = hull.name, category = "ship", volume = hull.volume, basePrice = hull.basePrice,
      scarce = if hull.tech == 2 then true else nil }
  end
end

-- What a starbase is made of, packed for carrying: towers, the modules
-- anchored round them, and the fuel they burn.
for _, tower in Structures.towers do
  byId[tower.id] = { id = tower.id, name = tower.name, category = "structure", volume = tower.volume, basePrice = tower.basePrice }
end
for _, module in Structures.modules do
  byId[module.id] = { id = module.id, name = module.name, category = "structure", volume = module.volume, basePrice = module.basePrice }
end
byId[Structures.FUEL.id] = { id = Structures.FUEL.id, name = Structures.FUEL.name, category = "structure",
  volume = Structures.FUEL.volume, basePrice = Structures.FUEL.basePrice }

-- What a colony takes out of a planet and makes of it, and the command
-- centre a colony starts from.
for _, raw in Planets.raws do
  byId[raw.id] = { id = raw.id, name = raw.name, category = "planetary", volume = raw.volume, basePrice = raw.basePrice }
end
for _, product in Planets.products do
  byId[product.id] = { id = product.id, name = product.name, category = "planetary", volume = product.volume,
    basePrice = product.basePrice }
end
byId[Planets.CENTRE.id] = { id = Planets.CENTRE.id, name = Planets.CENTRE.name, category = "structure",
  volume = Planets.CENTRE.volume, basePrice = Planets.CENTRE.basePrice }

-- Drones, as they are in a hold.
for _, drone in Drones.list do
  byId[drone.id] = { id = drone.id, name = drone.name, category = "drone", volume = drone.volume, basePrice = drone.basePrice,
    scarce = if drone.tech == 2 then true else nil }
end

-- Implants, before anybody has plugged them in.
for _, implant in Implants.list do
  byId[implant.id] = { id = implant.id, name = implant.name, category = "implant", volume = Implants.VOLUME,
    basePrice = Implants.Price(implant) }
end

for _, blueprint in Blueprints.list do
  byId[blueprint.id] = { id = blueprint.id, name = blueprint.name, category = "blueprint", volume = 0.01,
    basePrice = blueprint.basePrice, scarce = blueprint.invented }
end
-- A book for every skill a pilot does not start with.
for _, skill in Skills.list do
  if skill.start < 0 then
    byId[Skills.Book(skill.id)] = { id = Skills.Book(skill.id), name = skill.name .. " (skill book)", category = "skillbook",
      volume = 0.01, basePrice = 25000 * skill.rank }
  end
end

-- Things that are only carried and sold.
local goods: { Info } = {
  -- Proof of a pirate killed. Worth a bounty to whoever collects them.
  { id = "tag.pirate", name = "Pirate Tag", category = "goods", volume = 0.1, basePrice = 4000 },
  { id = "scrap.metal", name = "Scrap Metal", category = "goods", volume = 0.5, basePrice = 60 },
  -- What a salvager brings off a wreck (Tactical/Combat): the makings of
  -- rigs, and worth selling meanwhile.
  { id = "salvage.plates", name = "Salvaged Plating", category = "goods", volume = 0.05, basePrice = 600 },
  { id = "salvage.circuits", name = "Salvaged Circuits", category = "goods", volume = 0.02, basePrice = 900 },
  { id = "salvage.conduits", name = "Salvaged Conduits", category = "goods", volume = 0.03, basePrice = 750 },
  -- What a courier job gives a pilot to carry (Assets/Missions): a cubic
  -- metre a unit, and worth nothing to anybody but who it is for.
  { id = "cargo.sealed", name = "Sealed Cargo", category = "goods", volume = 1, basePrice = 1 },
  -- (what a pirate camp took, to be brought back for a job: Tactical/Assault)
  { id = "cargo.stolen", name = "Stolen Cargo", category = "goods", volume = 5, basePrice = 1 },
  -- A scan probe (Tactical/Sites): put out near where a signal is, it
  -- makes every scan of it worth more.
  { id = "probe.scan", name = "Scan Probe", category = "goods", volume = 1, basePrice = 15000 },
  -- What an invention is worked out from (Assets/Industry): found in
  -- derelicts (Tactical/Sites), and nowhere to be bought.
  { id = "datacore", name = "Datacore", category = "goods", volume = 0.1, basePrice = 30000, scarce = true },
}
for _, g in goods do
  byId[g.id] = g
end
-- Gas, drawn off a cloud (Data/Ores), and the boosters made from it
-- (Data/Boosters): no station has either unless a pilot sold it there.
for _, gas in Ores.gases do
  byId[gas.id] = { id = gas.id, name = gas.name, category = "goods", volume = gas.volume, basePrice = gas.basePrice, scarce = true }
end
for _, booster in Boosters.list do
  byId[booster.id] = { id = booster.id, name = booster.name .. " Booster", category = "goods", volume = Boosters.VOLUME,
    basePrice = Boosters.PRICE, scarce = true }
end

-- Every type id, in order: the order markets list them in.
local ids: { string } = {}

function Types.Ids(): { string }
  if #ids == 0 then
    for id in byId do
      table.insert(ids, id)
    end
    table.sort(ids)
  end
  return ids
end

function Types.Get(id: string): Info?
  return byId[id]
end

-- For code that already knows the id is good.
function Types.Info(id: string): Info
  return assert(byId[id], `no item type '{id}'`)
end

return Types
