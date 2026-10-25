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
  resource: string?,           -- system resource that scales output
  tax: number?,
  demand: { [string]: number }?,
  defense: number,
  weight: number,              -- how often it is generated
}

Data.Stations = {
  { id = "mine", name = "Mining Outpost", extractor = true, defense = 2, weight = 3,
    recipes = { { inputs = { food = 2, fuel = 1 }, outputs = { ferrite = 30, silicate = 20 } } } },
  { id = "harvester", name = "Ice Harvester", extractor = true, resource = "ice", defense = 2, weight = 1.5,
    recipes = { { inputs = { food = 2 }, outputs = { ice = 40 } } } },
  { id = "refinery", name = "Refinery", defense = 3, weight = 2,
    recipes = {
      { inputs = { ferrite = 40 }, outputs = { alloy = 12 } },
      { inputs = { ice = 30 }, outputs = { fuel = 12 } },
    } },
  { id = "agri", name = "Agricultural World", extractor = true, defense = 3, weight = 1.5,
    recipes = { { inputs = { fuel = 1 }, outputs = { food = 40 } } } },
  { id = "plating", name = "Plating Works", defense = 3, weight = 1,
    recipes = { { inputs = { alloy = 10 }, outputs = { plating = 5 } } } },
  { id = "fab", name = "Electronics Fab", defense = 3, weight = 1,
    recipes = { { inputs = { silicate = 20, alloy = 4 }, outputs = { electronics = 4 } } } },
  { id = "armory", name = "Munitions Plant", defense = 4, weight = 0.8,
    recipes = { { inputs = { alloy = 6, fuel = 4 }, outputs = { munitions = 10 } } } },
  { id = "habitat", name = "Habitat", tax = 40, defense = 5, weight = 1.5,
    recipes = { { inputs = { food = 10, electronics = 1 }, outputs = {} } } },
  { id = "shipyard", name = "Shipyard", defense = 8, weight = 0,
    recipes = {}, demand = { plating = 60, electronics = 40, fuel = 60, munitions = 60 } },
  { id = "den", name = "Pirate Den", defense = 6, weight = 0, recipes = {} },
} :: { StationKind }

Data.StationById = {} :: { [string]: StationKind }
for _, kind in Data.Stations do
  Data.StationById[kind.id] = kind
end

Data.TARGET_CYCLES = 8       -- input stock a station wants, in cycles
Data.KEEP_CYCLES = 2         -- output stock a station holds back from sale
Data.CAP_CYCLES = 20         -- output storage, in cycles
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
  upkeep: number,              -- credits per period
}

Data.Ships = {
  { id = "frigate", name = "Frigate", quality = 1, cargo = 0, buildTicks = 30, upkeep = 4, credits = 300,
    cost = { plating = 4, electronics = 2, fuel = 3 } },
  { id = "cruiser", name = "Cruiser", quality = 4, cargo = 0, buildTicks = 90, upkeep = 12, credits = 1200,
    cost = { plating = 14, electronics = 8, fuel = 8 } },
  { id = "hauler", name = "Hauler", quality = 0.1, cargo = 120, buildTicks = 45, upkeep = 2, credits = 300,
    cost = { plating = 6, electronics = 2, fuel = 4 } },
} :: { ShipClass }

Data.ShipById = {} :: { [string]: ShipClass }
for _, class in Data.Ships do
  Data.ShipById[class.id] = class
end

Data.PIRATE_FRIGATE_CREDITS = 250

--------------------------------------------------------------- Combat

Data.COMBAT_SPREAD = 0.25    -- each side's strength is rolled within +-25%
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
  { name = "Pirates", pirate = true, traits = { aggressive = 1, greedy = 1, sociable = 0, lawless = 1 } },
} :: { FactionDef }

Data.TERRITORY = 40          -- systems each faction starts with
Data.PIRATE_DENS = 6
Data.STARTING_CREDITS = 100000
Data.WAR_BELOW = -50         -- relations below this are war
Data.DRIFT = 0.5             -- per period, back toward the pair's baseline
Data.FRICTION = 1.5          -- per period and shared border link, scaled by aggression
Data.LAND_HUNGER = 2         -- friction multiplier for a faction with nowhere left to expand
Data.EXHAUSTION = 0.6        -- per period at war, toward peace
Data.PEACE_ABOVE = -20       -- wars end when relations recover past this

return Data
