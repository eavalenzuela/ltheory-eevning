--!strict
-- Planets worked: what a colony takes out of a planet, and what it
-- makes of it.
--
-- Planetary industry, as the owner set it out: a command centre is put
-- down on a planet from
-- orbit, and facilities are raised round it within the power and CPU
-- the centre supplies. Extractors bring up a raw material the planet
-- has, on a programme of some hours whose yield falls off as it runs;
-- processors turn a raw material into something worth carrying; what
-- comes out waits in storage for a ship to fetch it from orbit.
--
-- What a planet has follows from its kind, and how rich it is in each
-- from the planet itself. What is made there goes into fuel blocks and
-- into towers and their modules (Data/Blueprints), so a starbase is fed
-- and built from planets.
--
-- This is the data. The rules are Assets/Colonies.

local Rng = require("@lt/Core/Kernel/Rng")

local Planets = {}

-- What comes out of the ground: bulky and worth little.
export type Raw = { id: string, name: string, volume: number, basePrice: number }

-- What a processor makes of a raw material: 'input' units of 'from' go
-- in each cycle and 'output' of this come out.
export type Product = {
  id: string, name: string, volume: number, basePrice: number,
  from: string, input: number, output: number,
}

-- A kind of facility: what it draws of the command centre's supply,
-- what it costs to raise, and (for storage) the room it adds, m3.
export type Facility = { id: string, name: string, powergrid: number, cpu: number, cost: number, room: number }

Planets.raws = {
  { id = "raw.aqueous", name = "Aqueous Liquids", volume = 0.01, basePrice = 1 },
  { id = "raw.biomass", name = "Biomass", volume = 0.01, basePrice = 1 },
  { id = "raw.metals", name = "Base Metals", volume = 0.01, basePrice = 1 },
  { id = "raw.heavy", name = "Heavy Metals", volume = 0.01, basePrice = 1 },
  { id = "raw.gas", name = "Noble Gas", volume = 0.01, basePrice = 1 },
  { id = "raw.silicates", name = "Silicates", volume = 0.01, basePrice = 1 },
} :: { Raw }

-- A thousand units of raw material make ten of the product, which is
-- worth about twice what went in: processing is where the worth is.
Planets.products = {
  { id = "planet.water", name = "Water", volume = 0.4, basePrice = 150, from = "raw.aqueous", input = 1000, output = 10 },
  { id = "planet.polymers", name = "Biopolymers", volume = 0.4, basePrice = 190, from = "raw.biomass", input = 1000, output = 10 },
  { id = "planet.alloys", name = "Construction Alloys", volume = 0.4, basePrice = 210, from = "raw.metals", input = 1000, output = 10 },
  { id = "planet.catalysts", name = "Catalysts", volume = 0.4, basePrice = 260, from = "raw.heavy", input = 1000, output = 10 },
  { id = "planet.isotopes", name = "Fuel Isotopes", volume = 0.4, basePrice = 240, from = "raw.gas", input = 1000, output = 10 },
  { id = "planet.ceramics", name = "Ceramics", volume = 0.4, basePrice = 200, from = "raw.silicates", input = 1000, output = 10 },
} :: { Product }

-- What each kind of planet (Describe/System's 'variety') has to take.
Planets.DEPOSITS = {
  temperate = { "raw.aqueous", "raw.biomass", "raw.silicates" },
  ocean = { "raw.aqueous", "raw.biomass", "raw.gas" },
  barren = { "raw.metals", "raw.heavy", "raw.silicates" },
  lava = { "raw.metals", "raw.heavy", "raw.silicates" },
  ice = { "raw.aqueous", "raw.gas", "raw.heavy" },
  gas = { "raw.gas", "raw.aqueous", "raw.metals" },
} :: { [string]: { string } }

-- The command centre: an item, carried to the planet and put down from
-- orbit. It supplies the colony's power and CPU, and has a little room
-- of its own (m3). Small enough for a frigate's hold: a colony is how a
-- pilot with one ship starts to earn while doing something else.
Planets.CENTRE = {
  id = "colony.command", name = "Planetary Command Centre", volume = 100, basePrice = 90000,
  powergrid = 6000, cpu = 1600, room = 500,
}

-- (The CPU is what runs out: three
-- extractors and three processors leave none for storage.)
Planets.facilities = {
  { id = "extractor", name = "Extractor", powergrid = 800, cpu = 200, cost = 45000, room = 0 },
  { id = "processor", name = "Processor", powergrid = 800, cpu = 200, cost = 75000, room = 0 },
  { id = "storage", name = "Storage Facility", powergrid = 700, cpu = 500, cost = 250000, room = 5000 },
} :: { Facility }

-- An extractor's and a processor's cycle, in seconds of game time.
Planets.CYCLE = 900
-- What an extractor brings up in its first cycle on a deposit of
-- richness 1, in units. Later cycles of a programme bring up less:
-- cycle k (from 0) yields this over 1 + FALLOFF * k, so a short
-- programme takes more in an hour and a long one needs less minding.
Planets.YIELD = 1000
Planets.FALLOFF = 0.03
-- The lengths a programme can be given, hours.
Planets.PROGRAMMES = { 1, 4, 12, 24 }
-- What it costs to bring goods up to a ship, as a share of their worth.
Planets.EXPORT_TAX = 0.10
-- How near a planet (in its own radii, from its middle) a ship has to
-- be to put a command centre down or to fetch what a colony has made:
-- where a ship that has warped to the planet arrives.
Planets.REACH = 5

Planets.rawById = {} :: { [string]: Raw }
Planets.productById = {} :: { [string]: Product }
Planets.productOf = {} :: { [string]: Product }    -- by the raw it is made from
Planets.facilityById = {} :: { [string]: Facility }
local rawIndex: { [string]: number } = {}
for index, raw in Planets.raws do
  Planets.rawById[raw.id] = raw
  rawIndex[raw.id] = index
end
for _, product in Planets.products do
  Planets.productById[product.id] = product
  Planets.productOf[product.from] = product
end
for _, facility in Planets.facilities do
  Planets.facilityById[facility.id] = facility
end

export type Deposit = { raw: string, richness: number }

-- How rich a planet is in a raw material, from 0.6 to 1.4: it follows
-- from the planet's seed, so it need not be kept.
function Planets.Richness(seed: number, raw: string): number
  return Rng.Float(Rng.For(seed, rawIndex[raw] or 0, 4001), 0.6, 1.4)
end

-- What a planet of a kind has, and how rich it is in each. None for a
-- kind nobody can work.
function Planets.Deposits(variety: string, seed: number): { Deposit }
  local found: { Deposit } = {}
  local has: { string }? = Planets.DEPOSITS[variety]
  if has then
    for _, raw in has do
      table.insert(found, { raw = raw, richness = Planets.Richness(seed, raw) })
    end
  end
  return found
end

-- What an extractor brings up in cycle 'k' (from 0) of its programme.
function Planets.Yield(richness: number, k: number): number
  return math.floor(Planets.YIELD * richness / (1 + Planets.FALLOFF * k))
end

return Planets
