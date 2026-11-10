--!strict
-- Ores and the minerals they refine into.
--
-- An asteroid is made of one ore. Mining fills the hold with it; a
-- station refines it, 100 units at a time, into minerals, which are what
-- everything is built from. A station's base refinery recovers half of
-- what is in the ore (REFINE_YIELD); skill and better equipment raise
-- that later. Ore is priced at about what it yields at that base rate,
-- so refining is worth doing but selling ore raw is not foolish.

export type Mineral = { id: string, name: string, volume: number, basePrice: number }

export type Ore = {
  id: string,
  name: string,
  volume: number,       -- m3 per unit
  basePrice: number,    -- credits per unit
  share: number,        -- how common its rocks are in an ordinary belt
  -- minerals per 100 units at perfect yield
  wild: number?,          -- its share of the rocks in lawless space, if it is found only there
  yields: { { mineral: string, amount: number } },
}

local minerals: { Mineral } = {
  { id = "mineral.iron", name = "Iron", volume = 0.01, basePrice = 4 },
  { id = "mineral.silicon", name = "Silicon", volume = 0.01, basePrice = 8 },
  { id = "mineral.copper", name = "Copper", volume = 0.01, basePrice = 22 },
  { id = "mineral.titanium", name = "Titanium", volume = 0.01, basePrice = 60 },
  -- Found only where space is not safe. Cruisers need the first;
  -- battleships both.
  { id = "mineral.cobalt", name = "Cobalt", volume = 0.01, basePrice = 140 },
  { id = "mineral.iridium", name = "Iridium", volume = 0.01, basePrice = 420 },
}

local ores: { Ore } = {
  { id = "ore.ferrite", name = "Ferrite", volume = 0.1, basePrice = 6, share = 0.60,
    yields = { { mineral = "mineral.iron", amount = 250 }, { mineral = "mineral.silicon", amount = 30 } } },
  { id = "ore.silicate", name = "Silicate", volume = 0.15, basePrice = 8, share = 0.25,
    yields = { { mineral = "mineral.silicon", amount = 180 }, { mineral = "mineral.iron", amount = 60 } } },
  { id = "ore.cuprite", name = "Cuprite", volume = 0.3, basePrice = 15, share = 0.12,
    yields = { { mineral = "mineral.copper", amount = 120 }, { mineral = "mineral.iron", amount = 80 } } },
  { id = "ore.titanite", name = "Titanite", volume = 0.6, basePrice = 34, share = 0.03,
    yields = { { mineral = "mineral.titanium", amount = 90 }, { mineral = "mineral.copper", amount = 60 } } },
  -- No belt in safe space has these (their share there is nothing).
  { id = "ore.cobaltite", name = "Cobaltite", volume = 0.8, basePrice = 70, share = 0, wild = 0.10,
    yields = { { mineral = "mineral.cobalt", amount = 80 }, { mineral = "mineral.titanium", amount = 40 } } },
  { id = "ore.iridite", name = "Iridite", volume = 1.2, basePrice = 160, share = 0, wild = 0.04,
    yields = { { mineral = "mineral.iridium", amount = 60 }, { mineral = "mineral.cobalt", amount = 40 } } },
}

local Ores = {
  list = ores,
  byId = {} :: { [string]: Ore },
  minerals = minerals,
  mineralById = {} :: { [string]: Mineral },
  -- The share of an ore's minerals a station's refinery recovers.
  REFINE_YIELD = 0.5,
  -- Units refined at a time.
  BATCH = 100,
}

for _, ore in ores do
  Ores.byId[ore.id] = ore
end
for _, mineral in minerals do
  Ores.mineralById[mineral.id] = mineral
end

-- How many units of ore a rock of a given radius (m) holds when whole.
function Ores.RockUnits(radius: number): number
  return math.floor(radius * 40)
end

-- The ore of a rock, from a roll in [0, 1). In lawless space ('wild')
-- the rare ores take their share, out of the commonest's.
function Ores.Pick(roll: number, wild: boolean?): Ore
  local sum = 0
  if wild then
    for _, ore in ores do
      sum += ore.wild or 0
      if roll < sum then
        return ore
      end
    end
  end
  local rare = sum
  for index, ore in ores do
    sum += if index == 1 then ore.share - rare else ore.share
    if roll < sum then
      return ore
    end
  end
  return ores[1]
end

return Ores
