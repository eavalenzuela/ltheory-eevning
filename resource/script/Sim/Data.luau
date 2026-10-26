--!strict
-- The universe simulation's content: goods, station kinds, ship classes,
-- factions and tuning constants. This is the file to edit to change the
-- economy; the rest of Sim/ reads it.

local Data = {}

---------------------------------------------------------------- Timing

Data.JUMP_TICKS = 6          -- one gate jump (1 minute at 10 s per tick)
Data.CYCLE_TICKS = 30        -- one production cycle at a station
Data.PERIOD_TICKS = 60       -- upkeep, taxes and relation drift
Data.SIEGE_TICKS = 20        -- attackers must hold a system this long to capture it

----------------------------------------------------------------- Goods

export type Good = { id: string, name: string, base: number }

Data.Goods = {
  { id = "ferrite", name = "Ferrite Ore", base = 10 },
  { id = "silicate", name = "Silicate Ore", base = 12 },
  { id = "ice", name = "Volatile Ice", base = 8 },
  { id = "alloy", name = "Alloy", base = 40 },
  { id = "fuel", name = "Fuel", base = 30 },
  { id = "food", name = "Food", base = 20 },
  { id = "plating", name = "Hull Plating", base = 120 },
  { id = "electronics", name = "Electronics", base = 150 },
  { id = "munitions", name = "Munitions", base = 60 },
  { id = "domestic", name = "Domestic Goods", base = 50 },
} :: { Good }

Data.GoodById = {} :: { [string]: Good }
for _, good in Data.Goods do
  Data.GoodById[good.id] = good
end

--------------------------------------------------------- Station kinds

-- A recipe turns inputs into outputs once per production cycle. Outputs
-- marked 'resource' scale with the system's richness in that resource.
-- 'tax' pays the owner that many credits per fully supplied cycle.
-- 'demand' lists goods the station stocks without a recipe (shipyards).
export type Recipe = { inputs: { [string]: number }, outputs: { [string]: number } }
export type StationKind = {
  id: string,
  name: string,
  recipes: { Recipe },
  extractor: boolean?,         -- produces at a reduced rate without inputs
  planet: boolean?,            -- a planet: unlimited storage
  resource: string?,           -- system resource that scales output
  tax: number?,
  demand: { [string]: number }?,
  defense: number,
  weight: number,              -- how often it is generated
}

Data.Stations = {
  { id = "mine", name = "Mining Outpost", extractor = true, defense = 10, weight = 3,
    recipes = { { inputs = { food = 2, fuel = 1 }, outputs = { ferrite = 30, silicate = 20 } } } },
  { id = "harvester", name = "Ice Harvester", extractor = true, resource = "ice", defense = 10, weight = 1.5,
    recipes = { { inputs = { food = 2 }, outputs = { ice = 40 } } } },
  { id = "refinery", name = "Refinery", defense = 15, weight = 2,
    recipes = {
      { inputs = { ferrite = 40 }, outputs = { alloy = 12 } },
      { inputs = { ice = 30 }, outputs = { fuel = 12 } },
    } },
  { id = "agri", name = "Agricultural World", extractor = true, planet = true, defense = 20, weight = 1.5,
    recipes = { { inputs = { fuel = 1 }, outputs = { food = 40 } } } },
  { id = "plating", name = "Plating Works", defense = 15, weight = 1,
    recipes = { { inputs = { alloy = 10 }, outputs = { plating = 5 } } } },
  { id = "fab", name = "Electronics Fab", defense = 15, weight = 1,
    recipes = { { inputs = { silicate = 20, alloy = 4 }, outputs = { electronics = 4 } } } },
  { id = "armory", name = "Munitions Plant", defense = 20, weight = 0.8,
    recipes = { { inputs = { alloy = 6, fuel = 4 }, outputs = { munitions = 10 } } } },
  { id = "goods", name = "Goods Factory", defense = 15, weight = 1.5,
    recipes = { { inputs = { alloy = 2, silicate = 6, food = 2 }, outputs = { domestic = 12 } } } },
  { id = "habitat", name = "Habitat", planet = true, tax = 80, defense = 25, weight = 1.5,
    recipes = { { inputs = { food = 10, electronics = 1, domestic = 2 }, outputs = {} } } },
  { id = "shipyard", name = "Shipyard", defense = 40, weight = 0,
    recipes = {}, demand = { plating = 60, electronics = 40, fuel = 60, munitions = 60 } },
  { id = "den", name = "Pirate Den", defense = 30, weight = 0, recipes = {} },
  -- A faction's capital planet: a little of every key good with no
  -- inputs, a large population tax and strong defences
  { id = "homeworld", name = "Homeworld", extractor = true, planet = true, tax = 300, defense = 60, weight = 0,
    recipes = { { inputs = {}, outputs = { food = 30, fuel = 12, domestic = 12, alloy = 8, plating = 3,
      electronics = 2, munitions = 4 } } } },
} :: { StationKind }

Data.StationById = {} :: { [string]: StationKind }
for _, kind in Data.Stations do
  Data.StationById[kind.id] = kind
end

-- Every station consumes these each cycle to run (crew, power, upkeep),
-- drawing on any station in its system. A station short of them works and
-- defends at reduced strength.
Data.MAINTENANCE = { food = 0.5, fuel = 0.3, domestic = 0.3 } :: { [string]: number }
Data.UNMAINTAINED = 0.5      -- output and defence of a station with no maintenance
Data.MAINTENANCE_CYCLES = 40 -- maintenance stock a station keeps, in cycles
Data.INDUSTRY_TAX = 0.03     -- share of each cycle's output value paid to the owner

Data.TARGET_CYCLES = 8       -- input stock a station wants, in cycles
Data.KEEP_CYCLES = 2         -- output stock a station holds back from sale
Data.CAP_CYCLES = 20         -- output storage of orbital stations, in cycles (planets have no limit;
                             -- for them it is only the reference for pricing)
Data.EXTRACTOR_IDLE = 0.25   -- extractor output without inputs

----------------------------------------------------------- Ship classes

export type ShipClass = {
  id: string,
  name: string,
  quality: number,             -- combat value per ship
  cargo: number,
  cost: { [string]: number },
  credits: number,             -- labour and fittings, on top of the goods
  buildTicks: number,
  upkeep: number,              -- maintenance (repairs, crew) in credits per period
}

Data.Ships = {
  { id = "frigate", name = "Frigate", quality = 1, cargo = 0, buildTicks = 30, upkeep = 6, credits = 300,
    cost = { plating = 4, electronics = 2, fuel = 3 } },
  { id = "cruiser", name = "Cruiser", quality = 4, cargo = 0, buildTicks = 90, upkeep = 18, credits = 1200,
    cost = { plating = 14, electronics = 8, fuel = 8 } },
  { id = "hauler", name = "Hauler", quality = 0.1, cargo = 120, buildTicks = 45, upkeep = 3, credits = 300,
    cost = { plating = 6, electronics = 2, fuel = 4 } },
} :: { ShipClass }

Data.ShipById = {} :: { [string]: ShipClass }
for _, class in Data.Ships do
  Data.ShipById[class.id] = class
end

Data.PIRATE_FRIGATE_CREDITS = 250
Data.EMERGENCY_HAULER_CREDITS = 1500 -- a hauler bought outright by a faction with too few to supply its shipyards
Data.PIRATE_CREDITS = 40000  -- pirates' starting war chest (raids pay irregularly)
Data.DEN_CREDITS = 15000     -- what pirates pay to have a den constructed
Data.CONSTRUCT_TICKS = 60    -- construction time; the escort must hold the site
Data.MAX_DENS = 9
Data.PIRATES_PER_DEN = 6     -- frigates pirates keep per den

--------------------------------------------------------------- Combat

Data.COMBAT_SPREAD = 0.25    -- each side's strength is rolled within +-25%
Data.ATTACK_ODDS = 3         -- attack (or claim) only with this much strength over the defence
Data.RETREAT_AT = 0.6        -- the loser retreats after losing this share
Data.ROUT_RATIO = 3          -- a loser this much weaker is destroyed
Data.NO_MUNITIONS = 0.5      -- strength multiplier without munitions

------------------------------------------------------------- Factions

-- Personality: values in [0, 1]
export type Traits = { aggressive: number, greedy: number, sociable: number, lawless: number }
export type FactionDef = { name: string, traits: Traits, pirate: boolean? }

Data.Factions = {
  { name = "Vessari Combine", traits = { aggressive = 0.3, greedy = 0.9, sociable = 0.6, lawless = 0.2 } },
  { name = "Iron Kestrel Union", traits = { aggressive = 0.9, greedy = 0.4, sociable = 0.2, lawless = 0.3 } },
  { name = "Halcyon Accord", traits = { aggressive = 0.2, greedy = 0.4, sociable = 0.9, lawless = 0.1 } },
  { name = "Drovan Syndicate", traits = { aggressive = 0.6, greedy = 0.8, sociable = 0.3, lawless = 0.7 } },
  { name = "Meridian Directorate", traits = { aggressive = 0.5, greedy = 0.5, sociable = 0.4, lawless = 0.1 } },
  { name = "Ashen Covenant", traits = { aggressive = 0.7, greedy = 0.3, sociable = 0.4, lawless = 0.4 } },
  { name = "Talmar Free Cities", traits = { aggressive = 0.2, greedy = 0.7, sociable = 0.8, lawless = 0.2 } },
  { name = "Corvane Hegemony", traits = { aggressive = 0.8, greedy = 0.6, sociable = 0.2, lawless = 0.2 } },
  { name = "Pirates", pirate = true, traits = { aggressive = 1, greedy = 1, sociable = 0, lawless = 1 } },
} :: { FactionDef }

Data.TERRITORY = 1           -- systems each faction starts with: its home system
Data.PIRATE_DENS = 6
Data.STARTING_CREDITS = 50000
Data.HOME_FLEET = { frigate = 8, cruiser = 2 } :: { [string]: number }
Data.STARTING_HAULERS = 4
Data.INCOME_SMOOTHING = 0.2  -- weight of the latest period in a faction's income average
Data.WAR_BELOW = -50         -- relations below this lead to war
Data.DRIFT = 0.5             -- per period, back toward the pair's baseline
Data.FRICTION = 1.5          -- per period and shared border link, scaled by aggression
Data.LAND_HUNGER = 2         -- friction multiplier for a faction with nowhere left to expand

-- Sovereignty: every owned system and station costs credits per period.
-- A faction that can't pay builds up arrears; past the grace period it
-- loses its most remote system each period, and its crews desert.
Data.SOV_PER_SYSTEM = 6
Data.SOV_PER_STATION = 2
Data.ARREARS_GRACE = 6       -- periods in arrears before systems are lost
Data.DESERTION = 0.05        -- share of ships lost per period in arrears
Data.INDEPENDENT_DEFENSE = 1 -- multiplier on an independent system's station defence
Data.INDEPENDENT_CREDITS = 20000 -- an independent system's starting treasury; independents
                                 -- earn only by selling goods (they collect no taxes)
Data.EXPAND_RESERVE = 20     -- periods of running costs a faction keeps before expanding
Data.BUILD_RESERVE = 30      -- periods of running costs a faction keeps (working capital for trade) before building warships or stations
Data.DECOMMISSION_RUNWAY = 15 -- a faction running a deficit scraps ships once it has fewer periods of costs left than this
Data.BUDGET_MARGIN = 1.1     -- income must cover running costs by this much before new ships are built

-- Peace: a side at war is exhausted when it has less than RUNWAY periods
-- of running costs left, or its war fleet is below STRENGTH of what it was
-- when the war began. The exhausted side sues for peace and cedes up to
-- CEDED border systems plus a share of its credits; if both are
-- exhausted the peace is white. A truce follows.
Data.EXHAUSTED_RUNWAY = 2
Data.EXHAUSTED_STRENGTH = 0.5
Data.CEDED_SYSTEMS = 2
Data.REPARATIONS = 0.3
Data.TRUCE_PERIODS = 60      -- 10 hours
Data.AFTER_PEACE = -20       -- relations right after a peace

-- War cooldowns, in ticks of 10 real seconds: a faction can't declare war
-- within this long of declaring another, or of one of its wars ending
Data.WAR_COOLDOWN = 8640     -- 24 hours

-- Coalitions: while an aggressor is this much more powerful than the
-- faction it attacked, the others' relations with it fall (fear, scaled by
-- its dominance) and rise with its victim (solidarity), until they join
-- the war against it
Data.AGGRESSOR_RATIO = 1.2
Data.FEAR = 3                -- per period, at twice the average power
Data.SOLIDARITY = 1          -- per period

return Data
