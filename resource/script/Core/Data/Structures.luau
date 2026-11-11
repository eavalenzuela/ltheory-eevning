--!strict
-- Starbases: what a station is made of.
--
-- A station is not one building. It is a control tower with separate
-- modules anchored round it inside the tower's field, in the manner of
-- EVE's old player-owned starbases (decided by the project's owner): a
-- service is there because its module is.
--
-- A tower is a faction's: each of the four human factions builds its
-- own, in three sizes. What is anchored round a tower is nobody's in
-- particular: a gun battery, a shipyard or a storage array is the same
-- thing at any faction's tower, as a ship's weapons are the same on any
-- hull (the owner's decision, 2026-11-10).
--
-- For scale, EVE's: a tower's field is 15, 21 and 30 km in radius for
-- the three sizes, the tower itself some 3 km, its modules from 400 m
-- (a battery) to nearly 2 km (a ship assembly array). Ours are smaller
-- throughout, to suit stations of 2 to 8 km (Describe/System), and keep
-- those proportions.
--
-- This is the data and the makeup of the stations there already are.
-- The rules that go with it (anchoring, bringing online, fuel, a
-- service only where its module is online) are not written yet: for
-- now every station offers everything, and so is given every module
-- that a service needs.

local Factions = require("@lt/Core/Data/Factions")

local Structures = {}

export type Tower = {
  id: string,           -- "tower.vessari.medium"
  name: string,
  faction: string,
  size: number,         -- 1 small, 2 medium, 3 large
  powergrid: number,    -- what it can supply to its modules, MW
  cpu: number,          -- tf
}

-- What a module is for: the service it gives the tower's guests, or how
-- it serves the tower itself.
export type Service = "market" | "fitting" | "refining" | "industry" | "research" | "storage" | "quarters" | "defence"

export type ModuleType = {
  id: string,           -- "array.assembly"
  name: string,
  service: Service,
  radius: number,       -- m
  powergrid: number,    -- what it draws, MW
  cpu: number,
}

Structures.SIZES = { "small", "medium", "large" }

-- A tower's supply by size. (EVE's doubles with each size; so does this.)
local SUPPLY = { { powergrid = 1500, cpu = 2000 }, { powergrid = 3000, cpu = 4000 }, { powergrid = 6000, cpu = 8000 } }

local towers: { Tower } = {}
for _, faction in Factions.list do
  if faction.kind == "human" then
    for size, word in Structures.SIZES do
      table.insert(towers, {
        id = `tower.{faction.id}.{word}`,
        name = `{faction.name} {string.upper(string.sub(word, 1, 1))}{string.sub(word, 2)} Control Tower`,
        faction = faction.id, size = size, powergrid = SUPPLY[size].powergrid, cpu = SUPPLY[size].cpu,
      })
    end
  end
end

local modules: { ModuleType } = {
  { id = "array.trade", name = "Trade Hub", service = "market", radius = 380, powergrid = 300, cpu = 450 },
  { id = "array.hangar", name = "Ship Maintenance Array", service = "fitting", radius = 300, powergrid = 250, cpu = 200 },
  { id = "array.refining", name = "Refining Array", service = "refining", radius = 260, powergrid = 350, cpu = 150 },
  { id = "array.assembly", name = "Ship Assembly Array", service = "industry", radius = 600, powergrid = 400, cpu = 300 },
  { id = "array.laboratory", name = "Laboratory", service = "research", radius = 260, powergrid = 200, cpu = 500 },
  { id = "array.storage", name = "Storage Array", service = "storage", radius = 280, powergrid = 50, cpu = 50 },
  { id = "array.habitat", name = "Habitat", service = "quarters", radius = 340, powergrid = 150, cpu = 100 },
  { id = "battery.gun", name = "Gun Battery", service = "defence", radius = 150, powergrid = 200, cpu = 60 },
  { id = "battery.missile", name = "Missile Battery", service = "defence", radius = 150, powergrid = 120, cpu = 120 },
}

Structures.towers = towers
Structures.modules = modules
Structures.towerById = {} :: { [string]: Tower }
Structures.moduleById = {} :: { [string]: ModuleType }
for _, tower in towers do
  Structures.towerById[tower.id] = tower
end
for _, module in modules do
  Structures.moduleById[module.id] = module
end

-- The services a docked pilot has screens for. Until modules are things
-- that can be offline or absent, every station has one of each.
local BASICS = { "array.trade", "array.hangar", "array.refining", "array.assembly" }

-- What a kind of station (Describe/System's 'variety') has more of.
local LEANING: { [string]: { string } } = {
  ["trade hub"] = { "array.storage", "array.trade", "array.storage", "array.habitat" },
  ["shipyard"] = { "array.assembly", "array.storage", "array.assembly", "array.laboratory" },
  ["refinery"] = { "array.refining", "array.storage", "array.storage", "array.refining" },
  ["habitat"] = { "array.habitat", "array.habitat", "array.laboratory", "array.storage" },
  ["outpost"] = { "array.storage", "battery.gun", "battery.missile", "array.hangar" },
}

-- The size of tower for a station of a radius (Describe/System makes
-- them from 2 to 8 km): 1, 2 or 3.
function Structures.SizeFor(radius: number): number
  return if radius < 4000 then 1 elseif radius < 6000 then 2 else 3
end

export type Makeup = { tower: string, modules: { string } }

-- What a station is made of: its tower, and the modules anchored round
-- it, the larger ones first. It follows from what the station is and
-- nothing else, so it need not be kept: 'variety' and 'radius' are the
-- station's (Describe/System), 'faction' is whose tower it is.
--
-- Every station has the basics. A bigger tower carries more of what its
-- kind of station leans to, and more batteries; it is never given more
-- than it can power.
function Structures.Makeup(variety: string, radius: number, faction: string): Makeup
  local size = Structures.SizeFor(radius)
  local tower = Structures.towerById[`tower.{faction}.{Structures.SIZES[size]}`]
  assert(tower, `no tower of faction '{faction}'`)
  local chosen = table.clone(BASICS)
  local leaning = LEANING[variety] or LEANING["outpost"]
  for index = 1, size + 1 do
    table.insert(chosen, leaning[index])
  end
  for _ = 1, size do
    table.insert(chosen, "battery.gun")
    table.insert(chosen, "battery.missile")
  end
  -- (what it cannot power is left off, from the end: its batteries first)
  local powergrid, cpu = 0, 0
  local kept: { string } = {}
  for _, id in chosen do
    local module = Structures.moduleById[id]
    if powergrid + module.powergrid <= tower.powergrid and cpu + module.cpu <= tower.cpu then
      powergrid += module.powergrid
      cpu += module.cpu
      table.insert(kept, id)
    end
  end
  table.sort(kept, function(a: string, b: string): boolean
    local ra, rb = Structures.moduleById[a].radius, Structures.moduleById[b].radius
    if ra ~= rb then
      return ra > rb
    end
    return a < b
  end)
  return { tower = tower.id, modules = kept }
end

return Structures
