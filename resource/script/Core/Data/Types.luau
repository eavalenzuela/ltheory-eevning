--!strict
-- One place to ask about any kind of item: a module, a charge, later a
-- commodity or a packaged hull.

local Blueprints = require("@lt/Core/Data/Blueprints")
local Modules = require("@lt/Core/Data/Modules")
local Ores = require("@lt/Core/Data/Ores")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")

local Types = {}

export type Info = {
  id: string,
  name: string,
  category: "module" | "charge" | "goods" | "ore" | "mineral" | "ship" | "blueprint" | "skillbook",
  volume: number,     -- m3 per unit
  basePrice: number,  -- credits per unit
}

local byId: { [string]: Info } = {}

for _, m in Modules.list do
  byId[m.id] = { id = m.id, name = m.name, category = "module", volume = m.volume, basePrice = m.basePrice }
end
for _, c in Modules.charges do
  byId[c.id] = { id = c.id, name = c.name, category = "charge", volume = c.volume, basePrice = c.basePrice }
end

for _, ore in Ores.list do
  byId[ore.id] = { id = ore.id, name = ore.name, category = "ore", volume = ore.volume, basePrice = ore.basePrice }
end
for _, mineral in Ores.minerals do
  byId[mineral.id] = { id = mineral.id, name = mineral.name, category = "mineral", volume = mineral.volume, basePrice = mineral.basePrice }
end

-- A hull, packaged: bought and sold like anything else, and assembled
-- into a ship at a station. (Nobody sells capsules.)
for _, hull in Ships.list do
  if hull.class ~= "capsule" and not hull.restricted then
    byId[hull.id] = { id = hull.id, name = hull.name, category = "ship", volume = hull.volume, basePrice = hull.basePrice }
  end
end

for _, blueprint in Blueprints.list do
  byId[blueprint.id] = { id = blueprint.id, name = blueprint.name, category = "blueprint", volume = 0.01,
    basePrice = blueprint.basePrice }
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
}
for _, g in goods do
  byId[g.id] = g
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
