--!strict
-- What moons are made of that is worth drilling for.
--
-- A moon may have a deposit of one material: which, and how rich, is
-- the moon's own and never changes (it follows from the moon). A tower
-- anchored at the moon gets at it with a drill (Assets/Starbases, the
-- "Moon Drill" of Data/Structures), a silo's worth at a time.
--
-- There are six materials, in three grades. The common two are under
-- moons anywhere. The middle two are not found where order is kept,
-- and the rare two only where nobody keeps it: the better the deposit,
-- the further from help the tower that works it.
--
-- What they are for: a tower's reactor makes a composite of the two of
-- a grade (Data/Reactions), and the tech 2 make of anything is built
-- with some of that (Data/Blueprints): small things of the common
-- grade's, cruiser-sized things of the middle one's, and the largest of
-- the rare. Stations trade in them, thinly.
--
-- (Every figure here is a first proposal, to be played and judged.)

local Rng = require("@lt/Core/Kernel/Rng")

local Moons = {}

export type Material = {
  id: string,           -- "moon.salts"
  name: string,
  grade: number,        -- 1 common, 2 middle, 3 rare
  volume: number,       -- m3 a unit
  basePrice: number,    -- credits a unit
}

Moons.materials = {
  { id = "moon.salts", name = "Regolith Salts", grade = 1, volume = 1, basePrice = 200 },
  { id = "moon.volatiles", name = "Frozen Volatiles", grade = 1, volume = 1, basePrice = 260 },
  { id = "moon.cadmite", name = "Cadmite", grade = 2, volume = 1, basePrice = 600 },
  { id = "moon.vanadine", name = "Vanadine", grade = 2, volume = 1, basePrice = 800 },
  { id = "moon.promethite", name = "Promethite", grade = 3, volume = 1, basePrice = 1600 },
  { id = "moon.dysprite", name = "Dysprite", grade = 3, volume = 1, basePrice = 2200 },
} :: { Material }

Moons.byId = {} :: { [string]: Material }
for _, material in Moons.materials do
  Moons.byId[material.id] = material
end

-- Units a drill brings up in an hour from a deposit of middling
-- richness, and how rich a deposit can be, as a share of that.
Moons.YIELD = 200
Moons.POOREST, Moons.RICHEST = 0.6, 1.4

-- The chance that a moon has a deposit of each grade (and, with what is
-- left, none at all), by how safe its system is.
Moons.ODDS = {
  secure = { 0.45, 0, 0 },
  low = { 0.40, 0.30, 0 },
  lawless = { 0.30, 0.30, 0.20 },
} :: { [string]: { number } }

-- How much of what its drill brings up a tower holds before the drill
-- stops (units of the material in the tower's hangar): this much with
-- no storage array online, and this much more for each one that is.
Moons.SILO = 2400
Moons.STORAGE = 4800

export type Deposit = { material: Material, richness: number }

-- What a moon has: its material and how rich it is (a share of
-- Moons.YIELD), or nil for a moon with nothing worth a drill. 'seed' is
-- the moon's own, and 'band' how safe its system is ("secure", "low",
-- "lawless").
function Moons.Deposit(seed: number, band: string): Deposit?
  local rng = Rng.For(seed, 613)
  local roll = Rng.Next(rng)
  local which = Rng.Next(rng)
  local richness = Moons.POOREST + (Moons.RICHEST - Moons.POOREST) * Rng.Next(rng)
  local odds = Moons.ODDS[band] or Moons.ODDS.secure
  local grade = 0
  local under = 0
  for at, chance in odds do
    under += chance
    if grade == 0 and roll < under then
      grade = at
    end
  end
  if grade == 0 then
    return nil
  end
  local of: { Material } = {}
  for _, material in Moons.materials do
    if material.grade == grade then
      table.insert(of, material)
    end
  end
  return { material = of[math.min(#of, math.floor(which * #of) + 1)], richness = math.floor(richness * 100 + 0.5) / 100 }
end

-- A deposit's richness in a word.
function Moons.Word(richness: number): string
  return if richness >= 1.2 then "rich" elseif richness >= 0.9 then "fair" else "poor"
end

-- Units an hour a drill brings up from a deposit.
function Moons.PerHour(deposit: Deposit): number
  return math.floor(Moons.YIELD * deposit.richness + 0.5)
end

return Moons
