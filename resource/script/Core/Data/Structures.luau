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
  -- A citadel (the owner's B2, 2026-11-17): a station docked inside, of
  -- nobody's people, with slots for service modules and for batteries
  -- in place of a tower's powergrid and CPU (Structures.CITADEL_SIZES).
  -- Nil for a control tower.
  citadel: boolean?,
  slots: number?,       -- service modules it can have fitted
  defences: number?,    -- batteries it can have fitted
  reach: number?,       -- the radius of the citadel itself, m (its field is wider)
  kind: string?,        -- a citadel's kind (Structures.CITADEL_KINDS)
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
  -- A citadel's service module (fitted, not anchored round a tower), and
  -- the fuel blocks it burns in an hour while it is online. Nil for a
  -- tower's module.
  citadel: boolean?,
  fuel: number?,
  -- Of a citadel's service modules, one that only some kinds of citadel
  -- can fit ('kinds', Structures.CITADEL_KINDS), and those only from a
  -- size up ('least'); and what it opens there that nothing else of a
  -- citadel does ('opens': "capital" capital ships built, "advanced"
  -- tech 2 hulls built, "invention" tech 2 hulls invented, "bridge" a
  -- jump bridge to another gravity station).
  kinds: { string }?,
  least: number?,
  opens: string?,
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

-- Citadels (B2 on the roadmap; the owner's answers of 2026-11-17): "A
-- big station you dock in", beside the towers, which stay. Five sizes,
-- "small through XXL", built from a blueprint at a station, hauled to a
-- site and anchored as a tower is. What it gives is what is fitted in
-- it: service modules, each burning fuel while it is online, and
-- batteries of its own. It is fought as a tower is, and leaves a
-- derelict hulk when it is brought down (Assets/Citadels). Of no
-- people: its guns are the baseline's and so is its tank. Every figure
-- below is mine. Packed, a small one goes in an industrial's hold, the
-- extra-large in a capital industrial's and the largest in a
-- freighter's.
Structures.CITADEL_SIZES = { "small", "medium", "large", "extralarge", "huge" }
-- How big each is, its radius, and what docks or tethers there (the
-- owner, 2026-11-17: "Small = 0.5km | Only subcaps below battleships can
-- dock. Battleships will tether only. Caps+ cannot tether. Medium = 1km
-- | all subcaps can dock. Caps tether. Supercaps+ cannot tether. Large =
-- 5km | everything up to caps can dock. Supers+ tether. XLarge = 10km |
-- everything through supers can dock. Ultras tether. XXLarge = 40km |
-- everything can dock"; and "freighters are capitals"). By the tier of
-- a hull (Structures.HullTier): the highest that docks, and the highest
-- that tethers. Its field reaches half as far again and two kilometres
-- more (mine).
Structures.CITADEL_REACH = { 500, 1000, 5000, 10000, 40000 }
Structures.CITADEL_BERTH = { { 1, 2 }, { 2, 3 }, { 3, 5 }, { 4, 5 }, { 5, 5 } }
Structures.CITADEL_NAMES = { "Small Citadel", "Medium Citadel", "Large Citadel", "Extra-Large Citadel", "Huge Citadel" }
Structures.CITADEL_SIZE_NAMES = { "Small", "Medium", "Large", "Extra-Large", "Huge" }
-- The kinds of citadel (the owner, 2026-11-17: "These are each their own
-- citadel, with their own BP. Their type determines bonuses, and in some
-- cases special [modules] they can fit that other types cannot"): each
-- kind at each size is a citadel of its own, "Small Shipyard". What a
-- kind does better (Structures.CITADEL_BONUS) and what only it can fit
-- (the modules with 'kinds') are below. Any kind fits the plain service
-- modules, and does no better with them than a citadel of another kind.
-- (and the sixth, the owner's of the same day: a gravity station, a jump
-- hub: "Jump hub", of a beacon lit and a bridge to another)
-- (and the seventh, the owner's of the same day: a wormhole station, which
-- holds a wormhole open from where it stands, one after another, each
-- closing by time and by mass as any does: Tactical/Wormholes)
Structures.CITADEL_KINDS = { "habitation", "tradehub", "refinery", "research", "shipyard", "gravity", "wormhole" }
Structures.CITADEL_KIND_NAMES = { habitation = "Habitation", tradehub = "Trade Hub", refinery = "Refinery",
  research = "Research Station", shipyard = "Shipyard", gravity = "Gravity Station", wormhole = "Wormhole Station" } :: { [string]: string }
-- What each kind does better, where it is (its services online): mine,
-- every figure, but the kinds' exclusive modules, which are the owner's.
--   shipyard     a job builds in three quarters of the time, of nine
--                tenths of the materials
--   refinery     a tenth more of what ore and ice give
--   research     research, copying and invention in three quarters of
--                the time; and invention a tenth more likely to come off
--   tradehub     half the sales tax and broker's fee on what is traded there
--   habitation   a clone bay and room for storage without a module for
--                them, and a fifth less fuel
--   gravity      a jump beacon lit without a module for it (the
--                owner's: it counts as a lit beacon for jump drives)
--   wormhole     a wormhole held open just outside it while it is lit,
--                and another as soon as that one closes (the owner's)
export type CitadelBonus = { jobTime: number?, materials: number?, refine: number?, researchTime: number?, invent: number?,
  fees: number?, fuel: number?, gives: { Service }?, holds: boolean? }
Structures.CITADEL_BONUS = {
  shipyard = { jobTime = 0.75, materials = 0.9 },
  refinery = { refine = 1.1 },
  research = { researchTime = 0.75, invent = 0.1 },
  tradehub = { fees = 0.5 },
  habitation = { fuel = 0.8, gives = { "quarters", "storage" } },
  gravity = { gives = { "beacon" } },
  wormhole = { holds = true },
} :: { [string]: CitadelBonus }
Structures.CITADEL = {
  { field = 2750, fuel = 8, anchor = 2 * 3600, volume = 4000, basePrice = 80000000, shield = 300000, armor = 150000, hull = 150000,
    bay = 12, slots = 2, defences = 2 },
  { field = 3500, fuel = 15, anchor = 4 * 3600, volume = 12000, basePrice = 250000000, shield = 600000, armor = 300000, hull = 300000,
    bay = 18, slots = 3, defences = 4 },
  { field = 9500, fuel = 30, anchor = 8 * 3600, volume = 25000, basePrice = 900000000, shield = 1200000, armor = 600000, hull = 600000,
    bay = 24, slots = 5, defences = 6 },
  { field = 17000, fuel = 60, anchor = 12 * 3600, volume = 30000, basePrice = 3000000000, shield = 2500000, armor = 1200000,
    hull = 1200000, bay = 36, slots = 6, defences = 8 },
  { field = 62000, fuel = 120, anchor = 24 * 3600, volume = 40000, basePrice = 10000000000, shield = 5000000, armor = 2500000,
    hull = 2500000, bay = 48, slots = 8, defences = 10 },
}
for _, kind in Structures.CITADEL_KINDS do
  for size, word in Structures.CITADEL_SIZES do
    local c = Structures.CITADEL[size]
    table.insert(towers, {
      id = `citadel.{kind}.{word}`, name = `{Structures.CITADEL_SIZE_NAMES[size]} {Structures.CITADEL_KIND_NAMES[kind]}`, faction = "",
      size = size,
      powergrid = 0, cpu = 0, field = c.field, fuel = c.fuel, anchor = c.anchor, volume = c.volume, basePrice = c.basePrice,
      shield = c.shield, armor = c.armor, hull = c.hull, bay = c.bay,
      gun = "projectile", gunBonus = 1, missileBonus = 1, tank = "shield", resist = 0,
      citadel = true, slots = c.slots, defences = c.defences, reach = Structures.CITADEL_REACH[size], kind = kind,
    })
  end
end
-- (the citadels of before there were kinds, "citadel.small" and so on:
-- what a save has of them, or of their blueprints, is a habitation of
-- its size, Core.Load. Nil for an id that names none.)
function Structures.CitadelNow(id: string): string?
  local changed = false
  local now = string.gsub(id, "citadel%.(%a+)", function(word: string): string
    if table.find(Structures.CITADEL_SIZES, word) then
      changed = true
      return `citadel.habitation.{word}`
    end
    return `citadel.{word}`
  end)
  return if changed then now else nil
end

-- How big a hull is, for where it docks: 1 for anything smaller than a
-- battleship, 2 a battleship, 3 a capital (a freighter among them: the
-- owner's word), 4 a supercarrier, 5 an ultracapital. (By the names of
-- the classes: Data/Ships' classes are not to be had here.)
local TIERS: { [string]: number } = { battleship = 2, freighter = 3, carrier = 3, dreadnought = 3, siegedreadnought = 3,
  capitalindustrial = 3, supercarrier = 4, ultracapital = 5 }
function Structures.HullTier(class: string): number
  return TIERS[class] or 1
end

-- What a hull of a class can do at a citadel: "dock", "tether" or
-- "none". At a tower, or any station that is not a citadel, "dock".
function Structures.Berth(tower: Tower?, class: string): string
  if tower == nil or not tower.citadel then
    return "dock"
  end
  local tier = Structures.HullTier(class)
  local berth = Structures.CITADEL_BERTH[tower.size]
  return if tier <= berth[1] then "dock" elseif tier <= berth[2] then "tether" else "none"
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
  -- A citadel's service modules: fitted in it, a slot each, burning fuel
  -- while online. (A citadel open to others has traders come to it: so
  -- a pilot's citadel may have a market, where a pilot's tower may not.)
  { id = "service.market", name = "Market Hub", service = "market", radius = 0, powergrid = 0, cpu = 0, anchor = 600, pilot = true,
    volume = 3500, basePrice = 30000000, citadel = true, fuel = 10 },
  { id = "service.repair", name = "Repair and Fitting Bay", service = "fitting", radius = 0, powergrid = 0, cpu = 0, anchor = 300,
    pilot = true, volume = 2000, basePrice = 8000000, citadel = true, fuel = 4 },
  { id = "service.refinery", name = "Refinery", service = "refining", radius = 0, powergrid = 0, cpu = 0, anchor = 600, pilot = true,
    volume = 3000, basePrice = 15000000, citadel = true, fuel = 8 },
  { id = "service.manufacturing", name = "Manufacturing Plant", service = "industry", radius = 0, powergrid = 0, cpu = 0, anchor = 600,
    pilot = true, volume = 3500, basePrice = 20000000, citadel = true, fuel = 10 },
  { id = "service.research", name = "Research Laboratory", service = "research", radius = 0, powergrid = 0, cpu = 0, anchor = 600,
    pilot = true, volume = 3000, basePrice = 18000000, citadel = true, fuel = 8 },
  { id = "service.clone", name = "Clone Bay", service = "quarters", radius = 0, powergrid = 0, cpu = 0, anchor = 300, pilot = true,
    volume = 2000, basePrice = 12000000, citadel = true, fuel = 5 },
  { id = "service.storage", name = "Hangar Expansion", service = "storage", radius = 0, powergrid = 0, cpu = 0, anchor = 300,
    pilot = true, volume = 2000, basePrice = 5000000, citadel = true, fuel = 2 },
  -- What only some kinds of citadel fit (the owner's, 2026-11-17: "only
  -- shipyards can fit capital ship assembly module, no matter the size"
  -- and "the capital ship assembly module cannot be fitted in small or
  -- medium shipyard citadels, only large+"; "Shipyards -> Advanced Ship
  -- Assembly Module (T2 ship manufacturing)"; "Research Station ->
  -- Advanced research hub (invention for t2 ship hulls)"; and the
  -- refinery's reactor, which was my proposal). In a citadel, a capital
  -- is built only with the first, a tech 2 hull only with the second,
  -- and a tech 2 hull invented only with the third (Assets/Industry).
  -- Each is a manufacturing plant, a laboratory or a reactor array of
  -- its own beside that. Prices and fuel are mine.
  { id = "service.assembly.capital", name = "Capital Ship Assembly", service = "industry", radius = 0, powergrid = 0, cpu = 0,
    anchor = 1200, pilot = true, volume = 3500, basePrice = 250000000, citadel = true, fuel = 25, kinds = { "shipyard" }, least = 3,
    opens = "capital" },
  { id = "service.assembly.advanced", name = "Advanced Ship Assembly", service = "industry", radius = 0, powergrid = 0, cpu = 0,
    anchor = 900, pilot = true, volume = 3500, basePrice = 120000000, citadel = true, fuel = 15, kinds = { "shipyard" },
    opens = "advanced" },
  { id = "service.research.advanced", name = "Advanced Research Hub", service = "research", radius = 0, powergrid = 0, cpu = 0,
    anchor = 900, pilot = true, volume = 3500, basePrice = 90000000, citadel = true, fuel = 12, kinds = { "research" },
    opens = "invention" },
  { id = "service.reactor", name = "Reactor", service = "reaction", radius = 0, powergrid = 0, cpu = 0, anchor = 900, pilot = true,
    volume = 3500, basePrice = 60000000, citadel = true, fuel = 12, kinds = { "refinery" } },
  -- (the gravity station's: "only it fits a Jump Bridge to another
  -- gravity station", the owner's. A ship in the field of one goes to
  -- another, of its owner's or open to it, on the station's fuel:
  -- Tactical/Jumping. Price, fuel and how far it reaches are mine.)
  { id = "service.bridge", name = "Jump Bridge", service = "beacon", radius = 0, powergrid = 0, cpu = 0, anchor = 1200, pilot = true,
    volume = 3500, basePrice = 150000000, citadel = true, fuel = 20, kinds = { "gravity" }, opens = "bridge" },
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
-- A station has a ship maintenance array, what its kind is for, more of
-- it the bigger its tower, and batteries; the starter has, before all
-- that, everything the round of play needs. It is never given more than
-- its tower can power.
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
  -- (every station has a ship maintenance array, first so that nothing
  -- crowds it out: a ship bought or held at any station can be boarded
  -- and fitted there. The owner, 2026-11-18: "place ship maintenance
  -- arrays at all stations, otherwise contract ships purchased there
  -- can't be easily retrieved")
  local chosen: { string } = if starter then table.clone(ROUND) else { "array.hangar" }
  local kind = KIND[variety] or KIND["outpost"]
  for index = 1, size + 2 do
    if kind[index] ~= "array.hangar" then
      table.insert(chosen, kind[index])
    end
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
