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
-- This is the data, and the makeup of the stations there already are.
-- A service is only where its module is (Assets/Stations): a station
-- has what its kind is for and no more, but for the one a pilot starts
-- at, which has everything the whole round of play needs. A pilot can
-- put up a tower of their own, fuel it and anchor modules round it
-- (Assets/Starbases).

local Factions = require("@lt/Core/Data/Factions")

local Structures = {}

export type Tower = {
  id: string,           -- "tower.vessari.medium"
  name: string,
  faction: string,
  size: number,         -- 1 small, 2 medium, 3 large
  powergrid: number,    -- what it can supply to its modules, MW
  cpu: number,          -- tf
  field: number,        -- the radius of its field, m
  fuel: number,         -- fuel blocks it burns in a game hour while it is online
  anchor: number,       -- seconds it takes to anchor
  volume: number,       -- m3, packed
  basePrice: number,
}

-- What a module is for: the service it gives the tower's guests, or how
-- it serves the tower itself.
-- (One of Structures.SERVICES: "market", "fitting", "refining",
-- "industry", "research", "storage", "quarters", "defence".)
export type Service = string

export type ModuleType = {
  id: string,           -- "array.assembly"
  name: string,
  service: Service,
  radius: number,       -- m
  powergrid: number,    -- what it draws, MW
  cpu: number,
  anchor: number,       -- seconds it takes to anchor
  pilot: boolean,       -- whether a pilot can anchor one at a tower of their own
  volume: number,       -- m3, packed
  basePrice: number,
}

Structures.SIZES = { "small", "medium", "large" }
Structures.SERVICES = { "market", "fitting", "refining", "industry", "research", "storage", "quarters", "defence" } :: { Service }

-- A tower by size. Its supply doubles with each size, and so does the
-- fuel it burns (ten, twenty and forty blocks an hour, as EVE's do).
-- Packed, the largest still goes in the hold of any industrial.
local SUPPLY = {
  { powergrid = 1500, cpu = 2000, field = 3000, fuel = 10, anchor = 60, volume = 1500, basePrice = 2000000 },
  { powergrid = 3000, cpu = 4000, field = 5000, fuel = 20, anchor = 120, volume = 2500, basePrice = 5000000 },
  { powergrid = 6000, cpu = 8000, field = 7000, fuel = 40, anchor = 240, volume = 3600, basePrice = 12000000 },
}

local towers: { Tower } = {}
for _, faction in Factions.list do
  if faction.kind == "human" then
    for size, word in Structures.SIZES do
      table.insert(towers, {
        id = `tower.{faction.id}.{word}`,
        name = `{faction.name} {string.upper(string.sub(word, 1, 1))}{string.sub(word, 2)} Control Tower`,
        faction = faction.id, size = size, powergrid = SUPPLY[size].powergrid, cpu = SUPPLY[size].cpu,
        field = SUPPLY[size].field, fuel = SUPPLY[size].fuel, anchor = SUPPLY[size].anchor, volume = SUPPLY[size].volume,
        basePrice = SUPPLY[size].basePrice,
      })
    end
  end
end

-- (A pilot cannot anchor a trade hub: a market is the traders who come
-- to it, and nobody comes to a tower of one pilot's.)
local modules: { ModuleType } = {
  { id = "array.trade", name = "Trade Hub", service = "market", radius = 380, powergrid = 300, cpu = 450, anchor = 60, pilot = false,
    volume = 2000, basePrice = 3000000 },
  { id = "array.hangar", name = "Ship Maintenance Array", service = "fitting", radius = 300, powergrid = 250, cpu = 200, anchor = 30,
    pilot = true, volume = 2000, basePrice = 1200000 },
  { id = "array.refining", name = "Refining Array", service = "refining", radius = 260, powergrid = 350, cpu = 150, anchor = 30,
    pilot = true, volume = 1500, basePrice = 1500000 },
  { id = "array.assembly", name = "Ship Assembly Array", service = "industry", radius = 600, powergrid = 400, cpu = 300, anchor = 45,
    pilot = true, volume = 2500, basePrice = 2500000 },
  { id = "array.laboratory", name = "Laboratory", service = "research", radius = 260, powergrid = 200, cpu = 500, anchor = 30,
    pilot = true, volume = 1500, basePrice = 1800000 },
  { id = "array.storage", name = "Storage Array", service = "storage", radius = 280, powergrid = 50, cpu = 50, anchor = 20,
    pilot = true, volume = 1000, basePrice = 400000 },
  { id = "array.habitat", name = "Habitat", service = "quarters", radius = 340, powergrid = 150, cpu = 100, anchor = 30,
    pilot = true, volume = 2000, basePrice = 900000 },
  { id = "battery.gun", name = "Gun Battery", service = "defence", radius = 150, powergrid = 200, cpu = 60, anchor = 20,
    pilot = true, volume = 500, basePrice = 600000 },
  { id = "battery.missile", name = "Missile Battery", service = "defence", radius = 150, powergrid = 120, cpu = 120, anchor = 20,
    pilot = true, volume = 500, basePrice = 600000 },
}

-- What a tower burns. A block is a block, whoever's tower it is for.
Structures.FUEL = { id = "fuel.block", name = "Fuel Block", volume = 2, basePrice = 300 }

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

-- The module that gives a service, by name, for telling a pilot what a
-- station lacks.
function Structures.Provider(service: Service): string
  for _, module in modules do
    if module.service == service then
      return module.name
    end
  end
  return service
end

-- What the whole round of play needs: selling and buying, fitting and
-- repairs, refining, building, and somewhere to keep things. The
-- station a pilot starts at has all of it.
local ROUND = { "array.trade", "array.hangar", "array.refining", "array.assembly", "array.storage" }

-- What a kind of station (Describe/System's 'variety') is made of, the
-- first things first: a small one has the first three, and each size
-- above one more.
local KIND: { [string]: { string } } = {
  ["trade hub"] = { "array.trade", "array.storage", "array.hangar", "array.storage", "array.habitat" },
  ["shipyard"] = { "array.assembly", "array.hangar", "array.storage", "array.assembly", "array.laboratory" },
  ["refinery"] = { "array.refining", "array.storage", "array.refining", "array.storage", "array.hangar" },
  ["habitat"] = { "array.habitat", "array.storage", "array.habitat", "array.laboratory", "array.hangar" },
  ["outpost"] = { "array.hangar", "array.storage", "array.storage", "array.laboratory", "array.habitat" },
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
-- station's (Describe/System), 'faction' is whose tower it is, and
-- 'starter' says it is the station a pilot starts at.
--
-- A station has what its kind is for, more of it the bigger its tower,
-- and batteries; the starter has, before all that, everything the round
-- of play needs. It is never given more than its tower can power.
function Structures.Makeup(variety: string, radius: number, faction: string, starter: boolean?): Makeup
  local size = Structures.SizeFor(radius)
  local tower = Structures.towerById[`tower.{faction}.{Structures.SIZES[size]}`]
  assert(tower, `no tower of faction '{faction}'`)
  local chosen: { string } = if starter then table.clone(ROUND) else {}
  local kind = KIND[variety] or KIND["outpost"]
  for index = 1, size + 2 do
    table.insert(chosen, kind[index])
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
