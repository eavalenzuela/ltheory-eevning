--!strict
-- One place to ask about any kind of item: a module, a charge, later a
-- commodity or a packaged hull.

local Modules = require("@lt/Core/Data/Modules")

local Types = {}

export type Info = {
  id: string,
  name: string,
  category: "module" | "charge" | "goods",
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

-- Things that are only carried and sold.
local goods: { Info } = {
  -- Proof of a pirate killed. Worth a bounty to whoever collects them.
  { id = "tag.pirate", name = "Pirate Tag", category = "goods", volume = 0.1, basePrice = 4000 },
  { id = "scrap.metal", name = "Scrap Metal", category = "goods", volume = 0.5, basePrice = 60 },
}
for _, g in goods do
  byId[g.id] = g
end

function Types.Get(id: string): Info?
  return byId[id]
end

-- For code that already knows the id is good.
function Types.Info(id: string): Info
  return assert(byId[id], `no item type '{id}'`)
end

return Types
