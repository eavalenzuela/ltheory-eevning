--!strict
-- Module and charge types: what can be fitted to a ship and loaded into
-- its weapons.
--
-- A module changes its ship in two ways. Its 'passive' modifiers apply
-- whenever it is fitted; its 'boost' modifiers apply only while it is
-- running. A modifier either adds to an attribute or multiplies it, and
-- applies either to the ship or to the ship's weapons of one family.
-- Multipliers marked 'stack' are subject to the stacking penalty: the
-- second one of a kind is worth 87% of itself, the third 57%, and so on
-- (Dogma.luau).
--
-- Damage is a list of four numbers: EM, thermal, kinetic, explosive.

export type Modifier = {
  on: "ship" | "weapons",
  family: string?,        -- for "weapons": which family ("laser", "projectile", "missile")
  attribute: string,
  op: "add" | "mul",
  value: number,
  stack: boolean?,
}

export type Weapon = {
  family: string,           -- "laser" | "projectile" | "missile"
  duration: number,         -- s between shots
  capacitor: number,        -- GJ per shot
  damageMultiplier: number,
  -- turrets
  optimal: number,          -- m
  falloff: number,          -- m
  tracking: number,         -- how well it follows a crossing target; higher is better
  -- launchers leave the three above at 0: the missile carries its own range
  clip: number,             -- shots per load; 0 if the charge is never used up
  reload: number,           -- s to load a fresh clip
}

export type Repair = {
  layer: "shield" | "armor",
  amount: number,           -- HP per cycle
  duration: number,         -- s
  capacitor: number,        -- GJ per cycle
}

export type Miner = {
  volume: number,           -- m3 of ore per cycle
  duration: number,         -- s; the ore arrives at the end of each cycle
  capacitor: number,        -- GJ per cycle
  range: number,            -- m
}

export type ModuleType = {
  id: string,
  name: string,
  slot: "high" | "mid" | "low",
  hardpoint: "turret" | "launcher" | "",
  cpu: number,
  powergrid: number,
  volume: number,           -- m3
  basePrice: number,
  passive: { Modifier },
  -- at most one of these makes it something a pilot switches on:
  weapon: Weapon?,
  repair: Repair?,
  miner: Miner?,
  boost: { Modifier }?,     -- applies while running
  boostDuration: number?,   -- s per cycle, with 'boost'
  boostCapacitor: number?,  -- GJ per cycle
}

export type ChargeType = {
  id: string,
  name: string,
  family: string,           -- the weapon family it fits
  volume: number,
  basePrice: number,
  damage: { number },
  rangeMultiplier: number,  -- on a turret's optimal range
  -- missiles
  velocity: number,         -- m/s
  flightTime: number,       -- s
  explosionRadius: number,  -- m; smaller targets take less
  explosionVelocity: number, -- m/s; faster targets take less
}

local function ship(attribute: string, op: "add" | "mul", value: number, stack: boolean?): Modifier
  return { on = "ship", attribute = attribute, op = op, value = value, stack = stack }
end

local function weapons(family: string, attribute: string, value: number): Modifier
  return { on = "weapons", family = family, attribute = attribute, op = "mul", value = value, stack = true }
end

-- All four resonances of a layer at once.
local function resist(layer: string, value: number): { Modifier }
  local list = {}
  for index = 1, 4 do
    table.insert(list, ship(`{layer}Resonance.{index}`, "mul", value, true))
  end
  return list
end

local modules: { ModuleType } = {
  -- Weapons
  {
    id = "laser.pulse.small", name = "Small Pulse Laser", slot = "high", hardpoint = "turret",
    cpu = 9, powergrid = 6, volume = 5, basePrice = 9000, passive = {},
    weapon = { family = "laser", duration = 3, capacitor = 3.5, damageMultiplier = 2.2,
      optimal = 5200, falloff = 2500, tracking = 370, clip = 0, reload = 1 },
  },
  {
    id = "autocannon.small", name = "150mm Autocannon", slot = "high", hardpoint = "turret",
    cpu = 6, powergrid = 3, volume = 5, basePrice = 8000, passive = {},
    weapon = { family = "projectile", duration = 2.8, capacitor = 0, damageMultiplier = 2.0,
      optimal = 1100, falloff = 5200, tracking = 470, clip = 120, reload = 10 },
  },
  {
    id = "launcher.light", name = "Light Missile Launcher", slot = "high", hardpoint = "launcher",
    cpu = 26, powergrid = 5, volume = 5, basePrice = 12000, passive = {},
    weapon = { family = "missile", duration = 9, capacitor = 0, damageMultiplier = 1.0,
      optimal = 0, falloff = 0, tracking = 0, clip = 30, reload = 30 },
  },

  -- Mining
  {
    id = "miner.small", name = "Mining Laser", slot = "high", hardpoint = "turret",
    cpu = 60, powergrid = 2, volume = 5, basePrice = 15000, passive = {},
    miner = { volume = 40, duration = 60, capacitor = 60, range = 10000 },
  },

  -- Shield
  {
    id = "shield.extender.small", name = "Small Shield Extender", slot = "mid", hardpoint = "",
    cpu = 20, powergrid = 2, volume = 5, basePrice = 7000,
    passive = { ship("shield", "add", 280), ship("signature", "add", 3) },
  },
  {
    id = "shield.booster.small", name = "Small Shield Booster", slot = "mid", hardpoint = "",
    cpu = 22, powergrid = 2, volume = 5, basePrice = 8000, passive = {},
    repair = { layer = "shield", amount = 26, duration = 2, capacitor = 18 },
  },
  {
    id = "shield.hardener", name = "Multispectrum Shield Hardener", slot = "mid", hardpoint = "",
    cpu = 30, powergrid = 1, volume = 5, basePrice = 15000, passive = {},
    boost = resist("shield", 0.75), boostDuration = 10, boostCapacitor = 12,
  },

  -- Armour
  {
    id = "armor.plate.200mm", name = "200mm Steel Plates", slot = "low", hardpoint = "",
    cpu = 8, powergrid = 14, volume = 10, basePrice = 6000,
    passive = { ship("armor", "add", 520), ship("mass", "add", 187500) },
  },
  {
    id = "armor.repairer.small", name = "Small Armor Repairer", slot = "low", hardpoint = "",
    cpu = 6, powergrid = 6, volume = 5, basePrice = 8000, passive = {},
    repair = { layer = "armor", amount = 60, duration = 6, capacitor = 40 },
  },
  {
    id = "armor.membrane", name = "Multispectrum Membrane", slot = "low", hardpoint = "",
    cpu = 18, powergrid = 1, volume = 5, basePrice = 12000, passive = resist("armor", 0.85),
  },
  {
    id = "damage.control", name = "Damage Control", slot = "low", hardpoint = "",
    cpu = 25, powergrid = 1, volume = 5, basePrice = 20000,
    -- Not penalised against other modules: it is in a class of its own.
    passive = {
      ship("hullResonance.1", "mul", 0.6), ship("hullResonance.2", "mul", 0.6),
      ship("hullResonance.3", "mul", 0.6), ship("hullResonance.4", "mul", 0.6),
      ship("armorResonance.1", "mul", 0.9), ship("armorResonance.2", "mul", 0.9),
      ship("armorResonance.3", "mul", 0.9), ship("armorResonance.4", "mul", 0.9),
      ship("shieldResonance.1", "mul", 0.925), ship("shieldResonance.2", "mul", 0.925),
      ship("shieldResonance.3", "mul", 0.925), ship("shieldResonance.4", "mul", 0.925),
    },
  },

  -- Damage and tracking
  {
    id = "heat.sink", name = "Heat Sink", slot = "low", hardpoint = "",
    cpu = 20, powergrid = 1, volume = 5, basePrice = 25000,
    passive = { weapons("laser", "damageMultiplier", 1.10), weapons("laser", "duration", 0.895) },
  },
  {
    id = "gyrostabilizer", name = "Gyrostabilizer", slot = "low", hardpoint = "",
    cpu = 20, powergrid = 1, volume = 5, basePrice = 25000,
    passive = { weapons("projectile", "damageMultiplier", 1.10), weapons("projectile", "duration", 0.895) },
  },
  {
    id = "ballistic.control", name = "Ballistic Control System", slot = "low", hardpoint = "",
    cpu = 30, powergrid = 1, volume = 5, basePrice = 25000,
    passive = { weapons("missile", "damageMultiplier", 1.10), weapons("missile", "duration", 0.895) },
  },
  {
    id = "tracking.enhancer", name = "Tracking Enhancer", slot = "low", hardpoint = "",
    cpu = 10, powergrid = 1, volume = 5, basePrice = 18000,
    passive = {
      weapons("laser", "tracking", 1.095), weapons("projectile", "tracking", 1.095),
      weapons("laser", "optimal", 1.10), weapons("projectile", "optimal", 1.10),
      weapons("laser", "falloff", 1.20), weapons("projectile", "falloff", 1.20),
    },
  },

  -- Speed, capacitor, cargo
  {
    id = "afterburner.1mn", name = "1MN Afterburner", slot = "mid", hardpoint = "",
    cpu = 13, powergrid = 9, volume = 5, basePrice = 9000, passive = {},
    boost = { ship("maxVelocity", "mul", 2.1), ship("mass", "add", 500000) },
    boostDuration = 10, boostCapacitor = 11,
  },
  {
    id = "overdrive", name = "Overdrive Injector", slot = "low", hardpoint = "",
    cpu = 20, powergrid = 1, volume = 5, basePrice = 9000,
    passive = { ship("maxVelocity", "mul", 1.105, true), ship("cargo", "mul", 0.9) },
  },
  {
    id = "nanofiber", name = "Nanofiber Structure", slot = "low", hardpoint = "",
    cpu = 0, powergrid = 0, volume = 5, basePrice = 9000,
    passive = { ship("maxVelocity", "mul", 1.0775, true), ship("inertia", "mul", 0.87, true), ship("hull", "mul", 0.85) },
  },
  {
    id = "capacitor.battery.small", name = "Small Capacitor Battery", slot = "mid", hardpoint = "",
    cpu = 20, powergrid = 5, volume = 5, basePrice = 7000, passive = { ship("capacitor", "add", 100) },
  },
  {
    id = "capacitor.recharger", name = "Capacitor Recharger", slot = "mid", hardpoint = "",
    cpu = 22, powergrid = 1, volume = 5, basePrice = 9000, passive = { ship("capacitorRecharge", "mul", 0.85) },
  },
  {
    id = "cargo.expander", name = "Expanded Cargohold", slot = "low", hardpoint = "",
    cpu = 0, powergrid = 0, volume = 5, basePrice = 5000,
    passive = { ship("cargo", "mul", 1.175, true), ship("maxVelocity", "mul", 0.9) },
  },
}

local function turretCharge(id: string, name: string, family: string, damage: { number }, range: number): ChargeType
  return { id = id, name = name, family = family, volume = if family == "laser" then 1 else 0.0025, basePrice = 20,
    damage = damage, rangeMultiplier = range, velocity = 0, flightTime = 0, explosionRadius = 0, explosionVelocity = 0 }
end

local function missile(id: string, name: string, damage: { number }): ChargeType
  return { id = id, name = name, family = "missile", volume = 0.015, basePrice = 60, damage = damage, rangeMultiplier = 1,
    velocity = 3750, flightTime = 5, explosionRadius = 40, explosionVelocity = 170 }
end

local charges: { ChargeType } = {
  -- Crystals are not used up.
  turretCharge("crystal.multifrequency", "Multifrequency Crystal", "laser", { 7, 5, 0, 0 }, 0.5),
  turretCharge("crystal.standard", "Standard Crystal", "laser", { 5, 3, 0, 0 }, 1.0),
  turretCharge("crystal.radio", "Radio Crystal", "laser", { 5, 0, 0, 0 }, 1.6),
  turretCharge("ammo.emp", "EMP Rounds", "projectile", { 9, 0, 1, 2 }, 0.5),
  turretCharge("ammo.fusion", "Fusion Rounds", "projectile", { 0, 0, 2, 10 }, 0.5),
  turretCharge("ammo.sabot", "Titanium Sabot Rounds", "projectile", { 0, 0, 6, 2 }, 1.0),
  missile("missile.light.kinetic", "Bloodclaw Light Missile", { 0, 0, 83, 0 }),
  missile("missile.light.explosive", "Piranha Light Missile", { 0, 0, 0, 83 }),
  missile("missile.light.thermal", "Flameburst Light Missile", { 0, 83, 0, 0 }),
}

local Modules = {
  list = modules,
  byId = {} :: { [string]: ModuleType },
  charges = charges,
  chargeById = {} :: { [string]: ChargeType },
}

for _, m in modules do
  Modules.byId[m.id] = m
end
for _, c in charges do
  Modules.chargeById[c.id] = c
end

return Modules
