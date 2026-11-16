--!strict
-- Starbases: what a station is made of.
--
-- A station is not one building. It is a control tower with separate
-- modules anchored round it inside the tower's field (decided by the
-- project's owner): a service is there because its module is.
--
-- A tower is a faction's: each human faction that keeps to a place
-- builds its own, in three sizes. What is anchored round a tower is nobody's in
-- particular: a gun battery, a shipyard or a storage array is the same
-- thing at any faction's tower, as a ship's weapons are the same on any
-- hull (the owner's decision, 2026-11-10).
--
-- For scale, at full size a tower's field is 15, 21 and 30 km in radius for
-- the three sizes, the tower itself some 3 km, its modules from 400 m
-- (a battery) to nearly 2 km (a ship assembly array). Ours are smaller
-- throughout, to suit stations of 2 to 8 km (Describe/System), and keep
-- those proportions.
--
-- The Kethri keep to no place and build no towers. Where another people
-- has a station they have a colony ship: ten kilometres of ship that is
-- station and fleet dock both, with everything aboard it that a station
-- has anchored round it (the owner's draft, 2026-11-11). To the game it
-- is a station like any other, which a ship moors at; it is not yet a
-- ship that goes anywhere, or that anybody flies.
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
  -- What it takes to bring it down: its shield, its armour and its
  -- structure. And how many sealing charges it holds: an hour sealed
  -- for each (Assets/Starbases, Tactical/Raids).
  shield: number, armor: number, hull: number,
  bay: number,
  -- What its people's tower is better at than the baseline (the owner,
  -- 2026-11-16): the family its gun batteries fire ("projectile",
  -- "hybrid", "laser") and how much more they do (1.15: 15% more); how
  -- much more its missile batteries do (1 for a people that does not
  -- lean on launchers); and the layer it holds best ("shield", "armor",
  -- "hull") with how many points every resistance of it has over the
  -- baseline's (0.15). (Structures.Core is the hull that has them.)
  gun: string, gunBonus: number, missileBonus: number,
  tank: string, resist: number,
}

-- What a module is for: the service it gives the tower's guests, or how
-- it serves the tower itself.
-- (One of Structures.SERVICES: "market", "fitting", "refining",
-- "industry", "research", "storage", "quarters", "defence",
-- "extraction", "reaction", "beacon".)
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

-- A class of colony ship: a nomad faction's station. It is a ship, of
-- the class above every other (an ultracapital: Data/Ships'
-- CLASS_NAMES), which has no size of its own: each such ship is the
-- size it is (the project owner's ladder of 2026-11-12).
export type ColonyShip = {
  id: string,           -- "colonyship.larmes"
  name: string,
  faction: string,
  class: string,        -- "ultracapital"
  length: number,       -- m, bow to stern
  beam: number,         -- m, at its widest
}

Structures.SIZES = { "small", "medium", "large" }
Structures.SERVICES = { "market", "fitting", "refining", "industry", "research", "storage", "quarters", "defence",
  "extraction", "reaction", "beacon" } :: { Service }
-- The drill a pilot's tower gets at its moon with (Assets/Starbases,
-- Data/Moons), and the array that makes room for more of what it
-- brings up.
Structures.DRILL = "array.drill"
Structures.STORAGE = "array.storage"
-- And the reactor that makes a composite of what drills bring up
-- (Data/Reactions).
Structures.REACTOR = "array.reactor"
-- And the beacon a jump drive comes out at (Tactical/Jumping).
Structures.BEACON = "array.beacon"
-- And the beacon that claims an open system for whoever keeps the
-- tower it is anchored at (Assets/Sovereignty). (Its service, "claim",
-- is a pilot's tower's and no station's: it is not one of the list.)
Structures.CLAIM = "array.claim"

-- A tower by size. Its supply doubles with each size, and so does the
-- fuel it burns (ten, twenty and forty blocks an hour).
-- Packed, the largest still goes in the hold of any industrial.
-- (What it takes to bring one down doubles too, near enough: a small
-- tower's shield is a dozen battleships', and a pack that has it to
-- itself is some minutes getting it to the quarter where it seals.)
local SUPPLY = {
  { powergrid = 1500, cpu = 2000, field = 3000, fuel = 10, anchor = 60, volume = 1500, basePrice = 2000000,
    shield = 120000, armor = 40000, hull = 40000, bay = 12 },
  { powergrid = 3000, cpu = 4000, field = 5000, fuel = 20, anchor = 120, volume = 2500, basePrice = 5000000,
    shield = 250000, armor = 80000, hull = 80000, bay = 18 },
  { powergrid = 6000, cpu = 8000, field = 7000, fuel = 40, anchor = 240, volume = 3600, basePrice = 12000000,
    shield = 500000, armor = 160000, hull = 160000, bay = 24 },
}
Structures.SUPPLY = SUPPLY

-- The peoples that have towers: the human factions with stations, the
-- pirates, and the two alien peoples who hold stations (the owner,
-- 2026-11-16: "Add Unbound, Nimia, Vail"). The Kethri have colony ships
-- and the Drowned no stations at all.
Structures.TOWER_PEOPLES = { "vessari", "talmar", "orun", "unbound", "nimia", "vail" }

-- A people's tower is the baseline above with its people's bonuses (the
-- owner, 2026-11-16, "roughly 15% to their given faction bonuses
-- (increased damage for their turret types, increased resists for
-- their defenses)", and of how: the gun batteries fire the people's
-- turret family, missiles too for a people that leans on launchers, and
-- the resistances are "+15 points"). The same at every size.
Structures.TOWER_DAMAGE = 1.15
Structures.TOWER_RESIST = 0.15
-- (a people leans on launchers where a fair share of its hardpoints are
-- launchers: the same share a market of theirs stocks missiles for,
-- Assets/Market. The threshold is mine)
Structures.TOWER_LAUNCHERS = 0.3

local towers: { Tower } = {}
for _, people in Structures.TOWER_PEOPLES do
  local faction = Factions.byId[people]
  for size, word in Structures.SIZES do
    table.insert(towers, {
      id = `tower.{faction.id}.{word}`,
      name = `{faction.name} {string.upper(string.sub(word, 1, 1))}{string.sub(word, 2)} Control Tower`,
      faction = faction.id, size = size, powergrid = SUPPLY[size].powergrid, cpu = SUPPLY[size].cpu,
      field = SUPPLY[size].field, fuel = SUPPLY[size].fuel, anchor = SUPPLY[size].anchor, volume = SUPPLY[size].volume,
      basePrice = SUPPLY[size].basePrice,
      shield = SUPPLY[size].shield, armor = SUPPLY[size].armor, hull = SUPPLY[size].hull, bay = SUPPLY[size].bay,
      gun = faction.weapon, gunBonus = Structures.TOWER_DAMAGE,
      missileBonus = if faction.launchers >= Structures.TOWER_LAUNCHERS then Structures.TOWER_DAMAGE else 1,
      tank = faction.tank :: string, resist = Structures.TOWER_RESIST,
    })
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
  -- (what a pilot's tower is at a moon for: Data/Moons)
  { id = "array.drill", name = "Moon Drill", service = "extraction", radius = 320, powergrid = 600, cpu = 300, anchor = 60,
    pilot = true, volume = 2500, basePrice = 4000000 },
  -- (and what makes something to build with of what a drill brings up:
  -- Data/Reactions)
  { id = "array.reactor", name = "Reactor Array", service = "reaction", radius = 300, powergrid = 500, cpu = 400, anchor = 60,
    pilot = true, volume = 2500, basePrice = 3500000 },
  -- (what a ship with a jump drive comes out at: Tactical/Jumping)
  { id = "array.beacon", name = "Jump Beacon", service = "beacon", radius = 220, powergrid = 300, cpu = 250, anchor = 60,
    pilot = true, volume = 2000, basePrice = 2500000 },
  -- (what makes an open system a pilot's own: Assets/Sovereignty)
  { id = "array.claim", name = "Claim Beacon", service = "claim", radius = 260, powergrid = 400, cpu = 300, anchor = 120,
    pilot = true, volume = 2500, basePrice = 12000000 },
  { id = "battery.gun", name = "Gun Battery", service = "defence", radius = 150, powergrid = 200, cpu = 60, anchor = 20,
    pilot = true, volume = 500, basePrice = 600000 },
  { id = "battery.missile", name = "Missile Battery", service = "defence", radius = 150, powergrid = 120, cpu = 120, anchor = 20,
    pilot = true, volume = 500, basePrice = 600000 },
}

-- The colony ships, by class. (The first of a size of ship above
-- capitals. There is the one class so far.)
local colonyShips: { ColonyShip } = {
  { id = "colonyship.larmes", name = "Les Larmes de Nova", faction = "kethri", class = "ultracapital", length = 10000, beam = 1000 },
}

-- What a tower burns. A block is a block, whoever's tower it is for.
Structures.FUEL = { id = "fuel.block", name = "Fuel Block", volume = 2, basePrice = 300 }
-- And what seals one: a charge is burnt for each hour a tower holds
-- out sealed, when its shield is failing.
Structures.SEAL = { id = "fuel.seal", name = "Sealing Charge", volume = 5, basePrice = 15000 }
-- The hull that stands for a tower where it is shot at: its own, with
-- its people's resistances (Data/Ships). (Until 2026-11-16 it was one
-- of three, by size, whoever's the tower was: a save from then keeps
-- the core it had, and the next tower anchored has its own.)
function Structures.Core(tower: Tower): string
  return `works.{tower.id}`
end

Structures.towers = towers
Structures.modules = modules
Structures.colonyShips = colonyShips
Structures.towerById = {} :: { [string]: Tower }
Structures.moduleById = {} :: { [string]: ModuleType }
Structures.colonyShipById = {} :: { [string]: ColonyShip }
for _, tower in towers do
  Structures.towerById[tower.id] = tower
end
for _, ship in colonyShips do
  Structures.colonyShipById[ship.id] = ship
end

-- The class of colony ship a faction has for a station, if it is one
-- that has them.
function Structures.ColonyShip(faction: string): ColonyShip?
  local whose = Factions.byId[faction]
  if whose == nil or not whose.nomad then
    return nil
  end
  for _, ship in colonyShips do
    if ship.faction == faction then
      return ship
    end
  end
  return nil
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
-- repairs, refining, building, research, and somewhere to keep things.
-- The station a pilot starts at has all of it.
local ROUND = { "array.trade", "array.hangar", "array.refining", "array.assembly", "array.laboratory", "array.storage" }

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

-- How far beyond a station's field its batteries stand, m.
Structures.POST_OUT = 750

-- Where a battery of a station stands, from the station's middle: the
-- 'index'th of them (1, 2, ...) of a station of this radius and seed.
-- Outside the field (Tactical/Fields: nothing fires across it, so what
-- fires for a station cannot be inside it), round it by turns of the
-- golden angle, above and below by turns. The game stands them there
-- (Tactical/Batteries) and the view draws them there (Game/View/Starbase).
function Structures.Post(radius: number, seed: number, index: number): (number, number, number)
  local turn = (seed % 6283) / 1000 + 1.1 + index * 2.399963
  local lift = if index % 2 == 0 then 0.36 else -0.32
  local out = radius + Structures.POST_OUT
  return out * math.cos(lift) * math.cos(turn), out * math.sin(lift), out * math.cos(lift) * math.sin(turn)
end

-- What a station is made of. A tower ('tower', its type) and the
-- modules anchored round it; or a colony ship ('ship', its class), and
-- then 'modules' are what it has aboard, which give what they would
-- give anchored at a tower but stand nowhere.
export type Makeup = { tower: string?, ship: string?, modules: { string } }

-- What a colony ship has aboard: everything the round of play needs,
-- room to live, and as many batteries as a large tower.
local ABOARD = { "array.assembly", "array.trade", "array.habitat", "array.hangar", "array.storage", "array.laboratory", "array.refining",
  "battery.gun", "battery.gun", "battery.gun", "battery.missile", "battery.missile", "battery.missile" }

-- What a station is made of: its tower, and the modules anchored round
-- it, the larger ones first. It follows from what the station is and
-- nothing else, so it need not be kept: 'variety' and 'radius' are the
-- station's (Describe/System), 'faction' is whose tower it is, and
-- 'starter' says it is the station a pilot starts at.
--
-- A station has what its kind is for, more of it the bigger its tower,
-- and batteries; the starter has, before all that, everything the round
-- of play needs. It is never given more than its tower can power.
--
-- A nomad faction's is a colony ship, whatever kind or size the station
-- would have been, and has the same aboard every time.
function Structures.Makeup(variety: string, radius: number, faction: string, starter: boolean?): Makeup
  local ship = Structures.ColonyShip(faction)
  if ship then
    return { ship = ship.id, modules = table.clone(ABOARD) }
  end
  -- (a small tower cannot power everything the round of play needs: the
  -- station a pilot starts at has a medium one at the least)
  local size = if starter then math.max(2, Structures.SizeFor(radius)) else Structures.SizeFor(radius)
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
