--!strict
-- Hull types: what a ship is before anything is fitted to it.
--
-- agility: the time constant of a ship's exponential approach to a new
-- velocity is inertia * mass / 1e6 seconds. Time to align for warp (reach
-- 75% of top speed from rest) is 1.386 times that.
--
-- Resistances are stored as resonances: the fraction of damage of a type
-- that gets through (0.6 means 40% resisted), per layer in the order EM,
-- thermal, kinetic, explosive. Everything that improves a resistance
-- multiplies the resonance, which is why two 25% hardeners give less
-- than 50%.

export type ShipType = {
  id: string,
  name: string,
  class: string,
  lineage: string,        -- whose yards build it; "" for none
  basePrice: number,      -- credits; what insurance and loot values start from
  volume: number,         -- m3, assembled
  -- movement
  mass: number,           -- kg
  inertia: number,        -- inertia modifier
  maxVelocity: number,    -- m/s
  warpSpeed: number,      -- AU/s
  radius: number,         -- m
  -- defence
  shield: number,         -- HP
  armor: number,
  hull: number,
  shieldRecharge: number, -- s for the passive recharge curve
  shieldResonance: { number },
  armorResonance: { number },
  hullResonance: { number },
  signature: number,      -- m; how big a target it is
  -- fitting
  cpu: number,            -- tf
  powergrid: number,      -- MW
  highs: number,
  mids: number,
  lows: number,
  turrets: number,        -- hardpoints
  launchers: number,
  capacitor: number,      -- GJ
  capacitorRecharge: number, -- s
  -- targeting
  scanResolution: number, -- mm; higher locks faster
  lockRange: number,      -- m
  maxTargets: number,
  cargo: number,          -- m3
}

local SHIELD = { 1.0, 0.8, 0.6, 0.5 }
local ARMOR = { 0.5, 0.65, 0.75, 0.9 }
local HULL = { 0.67, 0.67, 0.67, 0.67 }

local types: { ShipType } = {
  -- The ship every pilot starts with, and gets again for nothing after
  -- losing one.
  {
    id = "frigate.courier", name = "Kestrel Courier", class = "frigate", lineage = "", basePrice = 30000, volume = 2500,
    mass = 1100000, inertia = 3.2, maxVelocity = 360, warpSpeed = 5, radius = 40,
    shield = 350, armor = 300, hull = 300, shieldRecharge = 625,
    shieldResonance = SHIELD, armorResonance = ARMOR, hullResonance = HULL, signature = 38,
    cpu = 110, powergrid = 32, highs = 2, mids = 2, lows = 1, turrets = 2, launchers = 0,
    capacitor = 260, capacitorRecharge = 190,
    scanResolution = 580, lockRange = 22000, maxTargets = 3, cargo = 180,
  },
  -- Lasers and armour.
  {
    id = "frigate.lancer", name = "Vessari Lancer", class = "frigate", lineage = "vessari", basePrice = 420000, volume = 2500,
    mass = 1190000, inertia = 3.0, maxVelocity = 345, warpSpeed = 5, radius = 42,
    shield = 390, armor = 520, hull = 360, shieldRecharge = 625,
    shieldResonance = SHIELD, armorResonance = ARMOR, hullResonance = HULL, signature = 37,
    cpu = 125, powergrid = 48, highs = 3, mids = 2, lows = 4, turrets = 3, launchers = 0,
    capacitor = 400, capacitorRecharge = 187,
    scanResolution = 600, lockRange = 26000, maxTargets = 4, cargo = 135,
  },
  -- Projectiles, missiles and shields.
  {
    id = "frigate.harrier", name = "Talmar Harrier", class = "frigate", lineage = "talmar", basePrice = 400000, volume = 2500,
    mass = 1067000, inertia = 3.22, maxVelocity = 375, warpSpeed = 5, radius = 40,
    shield = 500, armor = 380, hull = 330, shieldRecharge = 625,
    shieldResonance = SHIELD, armorResonance = ARMOR, hullResonance = HULL, signature = 35,
    cpu = 150, powergrid = 40, highs = 3, mids = 4, lows = 2, turrets = 2, launchers = 2,
    capacitor = 300, capacitorRecharge = 175,
    scanResolution = 660, lockRange = 24000, maxTargets = 4, cargo = 130,
  },
  {
    id = "industrial.hauler", name = "Mule Hauler", class = "industrial", lineage = "", basePrice = 600000, volume = 20000,
    mass = 11000000, inertia = 1.0, maxVelocity = 130, warpSpeed = 4.5, radius = 180,
    shield = 900, armor = 1100, hull = 1500, shieldRecharge = 900,
    shieldResonance = SHIELD, armorResonance = ARMOR, hullResonance = HULL, signature = 180,
    cpu = 200, powergrid = 60, highs = 2, mids = 3, lows = 3, turrets = 1, launchers = 0,
    capacitor = 500, capacitorRecharge = 300,
    scanResolution = 150, lockRange = 30000, maxTargets = 2, cargo = 3800,
  },
  -- What a pilot is left in when the ship is gone.
  {
    id = "capsule", name = "Capsule", class = "capsule", lineage = "", basePrice = 0, volume = 500,
    mass = 32000, inertia = 6, maxVelocity = 150, warpSpeed = 5, radius = 6,
    shield = 180, armor = 100, hull = 200, shieldRecharge = 300,
    shieldResonance = SHIELD, armorResonance = ARMOR, hullResonance = HULL, signature = 25,
    cpu = 0, powergrid = 0, highs = 0, mids = 0, lows = 0, turrets = 0, launchers = 0,
    capacitor = 150, capacitorRecharge = 100,
    scanResolution = 100, lockRange = 20000, maxTargets = 2, cargo = 0,
  },
}

local Ships = { list = types, byId = {} :: { [string]: ShipType } }

for _, t in types do
  Ships.byId[t.id] = t
end

-- Seconds; see the note on agility above.
function Ships.TimeConstant(t: ShipType): number
  return t.inertia * t.mass / 1e6
end

return Ships
