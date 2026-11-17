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
  -- Ice (module expansion, 2026-11-16): refined a unit at a time, not a
  -- hundred, and found in ice fields, not belts.
  batch: number?,
  ice: boolean?,
  -- How a chunk of it looks (Game/View/Scene): "shard", sharp and pale
  -- blue; "deep", soft and dark blue. (2026-11-17, the owner's two looks;
  -- which ice has which is mine.)
  look: string?,
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

-- Gas: what a cloud is made of (Tactical/Sites has the places where
-- there are clouds). It is drawn off with a harvester as ore is cut
-- with a laser, into the hold; nothing refines it, and it is what a
-- booster is made from (Data/Boosters), each kind of gas the boosters of
-- one kind.
export type Gas = { id: string, name: string, volume: number, basePrice: number }

local gases: { Gas } = {
  { id = "gas.amber", name = "Amber Vapour", volume = 1, basePrice = 240 },
  { id = "gas.verdant", name = "Verdant Vapour", volume = 1, basePrice = 240 },
  { id = "gas.azure", name = "Azure Vapour", volume = 1, basePrice = 240 },
}

-- Ice (module expansion, 2026-11-16; the names and figures mine): cut
-- from the chunks of an ice field with an ice harvester, a block at a
-- time, and refined a block at a time into the ice products, which fuel
-- blocks are made of (Data/Blueprints). Not in 'list', which is the
-- belts' ores and the economy's: ice is found only in ice fields, and the
-- simulation does not trade it yet. Priced, as ore is, at about what it
-- yields at the base rate.
local iceProducts: { Mineral } = {
  { id = "ice.heavywater", name = "Heavy Water", volume = 0.1, basePrice = 40 },
  { id = "ice.oxygen", name = "Liquid Oxygen", volume = 0.1, basePrice = 50 },
  { id = "ice.salts", name = "Cryo Salts", volume = 0.1, basePrice = 200 },
}
local ices: { Ore } = {
  { id = "ice.rime", name = "Rime Ice", volume = 50, basePrice = 2600, share = 0.7, batch = 1, ice = true, look = "shard",
    yields = { { mineral = "ice.heavywater", amount = 40 }, { mineral = "ice.oxygen", amount = 30 }, { mineral = "ice.salts", amount = 10 } } },
  { id = "ice.glacial", name = "Glacial Ice", volume = 50, basePrice = 4400, share = 0.3, batch = 1, ice = true, look = "deep",
    yields = { { mineral = "ice.heavywater", amount = 30 }, { mineral = "ice.oxygen", amount = 50 }, { mineral = "ice.salts", amount = 25 } } },
  -- (only where nobody keeps order)
  { id = "ice.dark", name = "Dark Ice", volume = 50, basePrice = 7400, share = 0, wild = 0.4, batch = 1, ice = true, look = "deep",
    yields = { { mineral = "ice.heavywater", amount = 20 }, { mineral = "ice.oxygen", amount = 40 }, { mineral = "ice.salts", amount = 60 } } },
}

local Ores = {
  list = ores,
  ices = ices,
  iceProducts = iceProducts,
  byId = {} :: { [string]: Ore },
  minerals = minerals,
  mineralById = {} :: { [string]: Mineral },
  gases = gases,
  gasById = {} :: { [string]: Gas },
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
for _, gas in gases do
  Ores.gasById[gas.id] = gas
end
-- (ice is ore to refine: byId has it; and its products are minerals)
for _, ice in ices do
  Ores.byId[ice.id] = ice
end
for _, product in iceProducts do
  Ores.mineralById[product.id] = product
end

-- Whether a thing to be mined is ice.
function Ores.Ice(variety: string): boolean
  local ore = Ores.byId[variety]
  return ore ~= nil and ore.ice == true
end

-- How many units of an ore are refined at a time.
function Ores.BatchOf(type: string): number
  local ore = Ores.byId[type]
  return if ore and ore.batch then ore.batch else Ores.BATCH
end

-- How many blocks an ice chunk of a given radius (m) holds when whole.
function Ores.IceUnits(radius: number): number
  return math.floor(radius / 4)
end

-- The ice of a chunk, from a roll in [0, 1): the dark only in lawless space.
function Ores.PickIce(roll: number, wild: boolean?): Ore
  local sum = 0
  for _, ice in ices do
    sum += if wild then (ice.wild or ice.share * 0.6) else ice.share
    if roll < sum then
      return ice
    end
  end
  return ices[1]
end

-- How many units of ore a rock of a given radius (m) holds when whole.
function Ores.RockUnits(radius: number): number
  return math.floor(radius * 40)
end

-- How many units of gas a cloud of a given radius (m) holds when whole:
-- a cloud is a great deal of room with very little in it.
function Ores.CloudUnits(radius: number): number
  return math.floor(radius / 2)
end

-- What a thing to be mined holds when whole: 'variety' is what it is of
-- (an ore, for a rock; a gas, for a cloud).
function Ores.Units(variety: string, radius: number): number
  return if Ores.gasById[variety] then Ores.CloudUnits(radius) elseif Ores.Ice(variety) then Ores.IceUnits(radius)
    else Ores.RockUnits(radius)
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
