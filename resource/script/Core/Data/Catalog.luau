--!strict
-- How the types of item are set out for a pilot to look through: in
-- groups, each under a heading, and in a sensible order within a group.
-- Hulls go by the faction whose design they are, frigate to battleship;
-- modules by what they are (lasers, shields, propulsion), small to
-- large; charges by what fires them; blueprints by what they make.
--
--   for _, entry in Catalog.Listing("ship") do
--     entry.header ("Vessari") or entry.info (a Types.Info)

local Factions = require("@lt/Core/Data/Factions")
local Modules = require("@lt/Core/Data/Modules")
local Ships = require("@lt/Core/Data/Ships")
local Planets = require("@lt/Core/Data/Planets")
local Structures = require("@lt/Core/Data/Structures")
local Types = require("@lt/Core/Data/Types")

local Catalog = {}

-- A row of a listing: a heading, or a type.
export type Entry = { header: string?, info: Types.Info? }

-- The order the categories come in where they are mixed (a hangar).
Catalog.CATEGORIES = { "module", "charge", "ship", "structure", "ore", "mineral", "planetary", "component", "blueprint", "skillbook",
  "goods" }

local categoryOrder: { [string]: number } = {}
for index, category in Catalog.CATEGORIES do
  categoryOrder[category] = index
end

local factionOrder: { [string]: number } = {}
for index, faction in Factions.list do
  factionOrder[faction.id] = index
end

local CLASSES: { [string]: number } = { frigate = 1, destroyer = 2, cruiser = 3, battleship = 4, industrial = 5, barge = 6, capsule = 7 }

-- Kinds of module, by the start of the type's id.
local MODULES: { { any } } = {
  { "laser.", "Lasers", 1 }, { "autocannon", "Projectile guns", 2 }, { "artillery", "Projectile guns", 2 },
  { "blaster", "Hybrid guns", 3 }, { "railgun", "Hybrid guns", 3 }, { "launcher.", "Launchers", 4 },
  { "shield.", "Shields", 5 }, { "armor.", "Armour", 6 }, { "afterburner", "Propulsion", 7 }, { "mwd.", "Propulsion", 7 },
  { "capacitor.", "Capacitor", 8 }, { "miner.", "Mining", 9 }, { "salvager", "Mining", 9 },
  { "web.", "Electronic warfare", 10 },
  { "disruptor.", "Electronic warfare", 10 },
}
local MISSILES = { "Light missiles", "Heavy missiles", "Cruise missiles" }
local MAKES: { [string]: { any } } = {
  ship = { "Hulls", 1 }, module = { "Modules", 2 }, charge = { "Charges", 3 }, component = { "Components", 4 },
  structure = { "Structures", 5 },
}

-- 1 small, 2 medium, 3 large, from a type's id.
local function sizeOf(id: string): number
  return if string.find(id, "large", 1, true) or string.find(id, "cruise", 1, true) then 3
    elseif string.find(id, "medium", 1, true) or string.find(id, "heavy", 1, true) then 2
    else 1
end

-- The group a type belongs to within its category: its heading ("" for
-- none), where that group comes among the groups, and where the type
-- comes within it (before its name is looked at).
function Catalog.Group(id: string): (string, number, number)
  local hull = Ships.byId[id]
  if hull then
    local faction = Factions.byId[hull.lineage]
    return if faction then faction.name else "Civilian", if faction then factionOrder[faction.id] else 99, CLASSES[hull.class] or 9
  end
  local info = Types.Get(id)
  local category = if info then info.category else ""
  if category == "module" then
    for _, kind in MODULES do
      if string.sub(id, 1, #kind[1]) == kind[1] then
        return kind[2], kind[3], sizeOf(id)
      end
    end
    return "Other", 20, sizeOf(id)
  elseif category == "charge" then
    local charge = Modules.chargeById[id]
    if charge.family == "missile" then
      return MISSILES[charge.size] or "Missiles", 3 + charge.size, charge.size
    end
    local order = if charge.family == "laser" then 1 elseif charge.family == "projectile" then 2 else 3
    return if order == 1 then "Laser crystals" elseif order == 2 then "Projectile rounds" else "Hybrid charges", order, charge.size
  elseif category == "structure" then
    local tower = Structures.towerById[id]
    if tower then
      return "Control towers", 1, tower.size
    elseif Structures.moduleById[id] then
      return "Structure modules", 2, 0
    elseif id == Planets.CENTRE.id then
      return "Colonies", 4, 0
    end
    return "Fuel", 3, 0
  elseif category == "planetary" then
    return if Planets.rawById[id] then "Raw materials" else "Processed materials", if Planets.rawById[id] then 1 else 2, 0
  elseif category == "blueprint" then
    local product = string.sub(id, #"blueprint." + 1)
    local made = Types.Get(product)
    local kind = MAKES[if made then made.category else ""]
    if kind then
      -- (within a group, as what they make would be set out)
      local _, group, rank = Catalog.Group(product)
      return kind[1], kind[2], group * 10 + rank
    end
    return "Other", 9, 0
  end
  return "", 0, 0
end

-- Whether type 'a' comes before type 'b' where types are listed
-- together: by category, then group, then place in the group, then name.
function Catalog.Before(a: string, b: string): boolean
  local ia, ib = Types.Get(a), Types.Get(b)
  local ca = categoryOrder[if ia then ia.category else ""] or 99
  local cb = categoryOrder[if ib then ib.category else ""] or 99
  if ca ~= cb then
    return ca < cb
  end
  local _, groupA, rankA = Catalog.Group(a)
  local _, groupB, rankB = Catalog.Group(b)
  if groupA ~= groupB then
    return groupA < groupB
  end
  if rankA ~= rankB then
    return rankA < rankB
  end
  local na, nb = if ia then ia.name else a, if ib then ib.name else b
  if na ~= nb then
    return na < nb
  end
  return a < b
end

local listings: { [string]: { Entry } } = {}

-- The types of a category set out for reading: every one once, each
-- group under its heading.
function Catalog.Listing(category: string): { Entry }
  local made = listings[category]
  if made then
    return made
  end
  local ids: { string } = {}
  for _, id in Types.Ids() do
    if Types.Info(id).category == category then
      table.insert(ids, id)
    end
  end
  table.sort(ids, Catalog.Before)
  local out: { Entry } = {}
  local heading = ""
  for _, id in ids do
    local group = Catalog.Group(id)
    if group ~= heading then
      heading = group
      table.insert(out, { header = group })
    end
    table.insert(out, { info = Types.Info(id) })
  end
  listings[category] = out
  return out
end

return Catalog
