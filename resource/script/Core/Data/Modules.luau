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
-- (Attributes.luau).
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
  -- 1 small, 2 medium, 3 large: it takes charges of its own size only.
  size: number,
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
  -- It draws gas off a cloud, and does nothing to a rock (as a laser
  -- that cuts rock does nothing to a cloud).
  gas: boolean?,
}

-- What a module does to another ship while it runs on it. An "entangle" cuts
-- the target's top speed to 'strength' of what it was; a "scramble"
-- keeps it out of warp; a "paint" makes its signature 'strength' times
-- as big; a "damp" cuts how far it can lock and how fast to 'strength'
-- of what they were; a "neut" takes 'strength' GJ from its capacitor
-- each cycle; and a "jam" has a chance of 'strength' each cycle of
-- breaking every lock it holds. Three are for a friend: a "shield" puts
-- 'strength' points back on its target's shield each cycle, an
-- "armor" on its armour, and a "capacitor" puts 'strength' GJ into its
-- capacitor (which is what the cycle costs the ship that sends it: the
-- energy is moved, not made).
export type Hex = {
  kind: "entangle" | "scramble" | "paint" | "damp" | "neut" | "jam" | "shield" | "armor" | "capacitor",
  range: number,            -- m
  strength: number,
  duration: number,         -- s per cycle
  capacitor: number,        -- GJ per cycle
}

-- A salvager works on a wreck: each cycle may bring off what is still
-- worth having of the hull itself ('chance', before any skill).
export type Salvager = {
  range: number,            -- m
  duration: number,         -- s per cycle
  capacitor: number,        -- GJ per cycle
  chance: number,
}

export type ModuleType = {
  id: string,
  name: string,
  slot: "high" | "mid" | "low" | "rig",
  -- A rig's share of the hull's calibration (Data/Ships).
  calibration: number?,
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
  hex: Hex?,
  salvager: Salvager?,
  -- A cloak: while it runs (it is a 'boost', which is what slows the
  -- ship) nobody can target the ship, and anything that comes within
  -- 'reach' metres of it switches it off.
  cloak: { reach: number }?,
  -- A jump beacon generator: while it runs, a ship with a jump drive
  -- can jump to the system the ship is in (Tactical/Jumping).
  beacon: boolean?,
  -- A data analyzer: fitted, it lets the ship hack a sealed hold from
  -- within its range (Tactical/Hacking).
  analyzer: { range: number }?,
  -- What it is called for short, where there is not room for its name.
  short: string?,
  -- Skills a pilot needs to fit it. (Where absent, Data/Skills says.)
  requires: { { skill: string, level: number } }?,
  -- What only a drone carries (Data/Drones): nobody sells it, finds it
  -- or fits it to a ship.
  internal: boolean?,
  -- 2 for a tech 2 module: the improved make of the module 'base',
  -- which nobody sells: it is invented and built (Assets/Industry).
  tech: number?,
  base: string?,
  -- 1 for a custom make: the module 'base' as somebody has worked it
  -- over, a little better and easier to fit. Nobody sells one or builds
  -- one: they are found in wrecks (Tactical/Aftermath, Tactical/Sites).
  -- 2 for a masterwork: the same module made over by the best hands
  -- the pirates have, better than tech 2 and as easy to fit as a custom
  -- make. Only their captains fit them (Tactical/Pirates), and only a
  -- captain's wreck has one.
  meta: number?,
}

export type ChargeType = {
  id: string,
  name: string,
  family: string,           -- the weapon family it fits
  size: number,             -- and the size of weapon: 1 small, 2 medium, 3 large
  volume: number,
  basePrice: number,
  damage: { number },
  rangeMultiplier: number,  -- on a turret's optimal range
  -- on a turret's tracking, where the charge changes it (a tech 2
  -- charge's trade, below); as the gun tracks by itself, if not said
  tracking: number?,
  -- missiles
  velocity: number,         -- m/s
  flightTime: number,       -- s
  explosionRadius: number,  -- m; smaller targets take less
  explosionVelocity: number, -- m/s; faster targets take less
  -- 2 for a tech 2 charge: the improved make of the charge 'base',
  -- which only a tech 2 weapon takes (below).
  tech: number?,
  base: string?,
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
      optimal = 5200, falloff = 2500, tracking = 370, clip = 0, reload = 1, size = 1 },
  },
  {
    id = "autocannon.small", name = "Small Autocannon", slot = "high", hardpoint = "turret",
    cpu = 6, powergrid = 3, volume = 5, basePrice = 8000, passive = {},
    weapon = { family = "projectile", duration = 2.8, capacitor = 0, damageMultiplier = 2.0,
      optimal = 1100, falloff = 5200, tracking = 470, clip = 120, reload = 10, size = 1 },
  },
  {
    id = "launcher.light", name = "Light Missile Launcher", slot = "high", hardpoint = "launcher",
    cpu = 26, powergrid = 5, volume = 5, basePrice = 12000, passive = {},
    weapon = { family = "missile", duration = 9, capacitor = 0, damageMultiplier = 1.0,
      optimal = 0, falloff = 0, tracking = 0, clip = 30, reload = 30, size = 1 },
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
    id = "shield.hardener", name = "Shield Hardener", slot = "mid", hardpoint = "",
    cpu = 30, powergrid = 1, volume = 5, basePrice = 15000, passive = {},
    boost = resist("shield", 0.75), boostDuration = 10, boostCapacitor = 12,
  },

  -- Armour
  {
    id = "armor.plate.200mm", name = "Small Armor Plate", slot = "low", hardpoint = "",
    cpu = 8, powergrid = 14, volume = 10, basePrice = 6000,
    passive = { ship("armor", "add", 520), ship("mass", "add", 187500) },
  },
  {
    id = "armor.repairer.small", name = "Small Armor Repairer", slot = "low", hardpoint = "",
    cpu = 6, powergrid = 6, volume = 5, basePrice = 8000, passive = {},
    repair = { layer = "armor", amount = 60, duration = 6, capacitor = 40 },
  },
  {
    id = "armor.membrane", name = "Reactive Membrane", slot = "low", hardpoint = "",
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
    id = "ballistic.control", name = "Guidance Computer", slot = "low", hardpoint = "",
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

  -- What is left of a ship is worth something to whoever takes the
  -- trouble (Tactical/Combat; what comes off is Data/Types' salvage).
  {
    id = "salvager.small", name = "Salvager", slot = "high", hardpoint = "",
    cpu = 20, powergrid = 1, volume = 5, basePrice = 40000, passive = {},
    salvager = { range = 5000, duration = 10, capacitor = 18, chance = 0.3 },
    requires = { { skill = "salvaging", level = 1 } },
  },

  -- Holding another ship: slowing it, and keeping it out of warp. (One
  -- size of each: what they do does not go by the size of the hull.)
  {
    id = "projector.entanglement", name = "Gravitic Entanglement Projector", short = "GEP", slot = "mid", hardpoint = "",
    cpu = 22, powergrid = 1, volume = 5, basePrice = 30000, passive = {},
    hex = { kind = "entangle", range = 10000, strength = 0.45, duration = 5, capacitor = 4 },
    requires = { { skill = "propulsion.jamming", level = 1 } },
  },
  {
    id = "disruptor.warp", name = "Warp Disruptor", slot = "mid", hardpoint = "",
    cpu = 26, powergrid = 1, volume = 5, basePrice = 45000, passive = {},
    hex = { kind = "scramble", range = 20000, strength = 1, duration = 5, capacitor = 8 },
    requires = { { skill = "propulsion.jamming", level = 1 } },
  },

  -- The rest of electronic warfare: making a ship easier to hit, harder
  -- of sight, short of capacitor, or blind for a moment.
  {
    id = "painter.target", name = "Target Painter", slot = "mid", hardpoint = "",
    cpu = 20, powergrid = 1, volume = 5, basePrice = 25000, passive = {},
    hex = { kind = "paint", range = 40000, strength = 1.3, duration = 5, capacitor = 4 },
    requires = { { skill = "electronic.warfare", level = 1 } },
  },
  {
    id = "damper.sensor", name = "Sensor Dampener", slot = "mid", hardpoint = "",
    cpu = 24, powergrid = 1, volume = 5, basePrice = 30000, passive = {},
    hex = { kind = "damp", range = 30000, strength = 0.5, duration = 5, capacitor = 5 },
    requires = { { skill = "electronic.warfare", level = 1 } },
  },
  {
    id = "neutraliser.small", name = "Small Energy Neutraliser", slot = "high", hardpoint = "",
    cpu = 12, powergrid = 9, volume = 5, basePrice = 35000, passive = {},
    hex = { kind = "neut", range = 6000, strength = 45, duration = 6, capacitor = 30 },
    requires = { { skill = "electronic.warfare", level = 2 } },
  },
  {
    id = "jammer.ecm", name = "ECM Jammer", slot = "mid", hardpoint = "",
    cpu = 30, powergrid = 1, volume = 5, basePrice = 40000, passive = {},
    hex = { kind = "jam", range = 25000, strength = 0.35, duration = 10, capacitor = 14 },
    requires = { { skill = "electronic.warfare", level = 3 } },
  },

  -- Getting into a derelict's sealed hold (Tactical/Hacking): it has
  -- only to be fitted.
  {
    id = "analyzer.data", name = "Data Analyzer", slot = "mid", hardpoint = "",
    cpu = 20, powergrid = 1, volume = 5, basePrice = 60000, passive = {},
    analyzer = { range = 5000 },
    requires = { { skill = "hacking", level = 1 } },
  },

  -- Not being seen. While it runs the ship cannot be targeted, and what
  -- had it targeted loses it; it flies at a quarter of its speed, can
  -- lock nothing and switch nothing else on, and may still warp. It
  -- cannot be switched on while anybody has the ship targeted, nor
  -- within two kilometres of anything, and anything that comes that
  -- near switches it off.
  {
    id = "cloak.device", name = "Cloaking Device", slot = "high", hardpoint = "",
    cpu = 30, powergrid = 1, volume = 5, basePrice = 250000, passive = {},
    boost = { ship("maxVelocity", "mul", 0.25) }, boostDuration = 5, boostCapacitor = 2,
    cloak = { reach = 2000 },
    requires = { { skill = "cloaking", level = 1 } },
  },

  -- A beacon for a jump drive to come out at (Tactical/Jumping): while
  -- it runs on a ship of the pilot's fleet, a ship of theirs with a jump
  -- drive can jump to the system that ship is in. It goes on any hull,
  -- and a hired pilot keeps theirs running whenever they are out in
  -- space. (First figures.)
  {
    id = "beacon.jump", name = "Jump Beacon Generator", slot = "high", hardpoint = "",
    cpu = 40, powergrid = 10, volume = 20, basePrice = 1500000, passive = {},
    boost = {}, boostDuration = 10, boostCapacitor = 4,
    beacon = true,
    requires = { { skill = "jump.drives", level = 1 } },
  },

  -- Mending somebody else: shield or armour put back on another ship,
  -- for as long as it is locked, in reach, and there is capacitor.
  {
    id = "remote.shield.small", name = "Small Remote Shield Booster", slot = "high", hardpoint = "",
    cpu = 28, powergrid = 6, volume = 5, basePrice = 40000, passive = {},
    hex = { kind = "shield", range = 10000, strength = 50, duration = 5, capacitor = 30 },
    requires = { { skill = "remote.repair", level = 1 } },
  },
  {
    id = "remote.armor.small", name = "Small Remote Armor Repairer", slot = "high", hardpoint = "",
    cpu = 18, powergrid = 8, volume = 5, basePrice = 40000, passive = {},
    hex = { kind = "armor", range = 8000, strength = 55, duration = 6, capacitor = 30 },
    requires = { { skill = "remote.repair", level = 1 } },
  },

  -- And feeding somebody else: capacitor sent to another ship, for as
  -- long as it is locked and in reach. What arrives is what was sent.
  {
    id = "remote.capacitor.small", name = "Small Capacitor Relay", short = "Relay", slot = "high", hardpoint = "",
    cpu = 20, powergrid = 5, volume = 5, basePrice = 40000, passive = {},
    hex = { kind = "capacitor", range = 10000, strength = 40, duration = 5, capacitor = 40 },
    requires = { { skill = "engineering", level = 2 } },
  },

  -- What a mining drone cuts with and a repair drone mends with: small
  -- things, of no use on a ship.
  {
    id = "miner.drone", name = "Drone Mining Laser", slot = "high", hardpoint = "turret",
    cpu = 5, powergrid = 1, volume = 1, basePrice = 4000, passive = {},
    miner = { volume = 10, duration = 60, capacitor = 5, range = 2000 }, internal = true,
  },
  {
    id = "remote.armor.drone", name = "Drone Armor Repairer", slot = "high", hardpoint = "",
    cpu = 5, powergrid = 1, volume = 1, basePrice = 8000, passive = {},
    hex = { kind = "armor", range = 3000, strength = 18, duration = 5, capacitor = 6 }, internal = true,
  },
  -- What a fighter and a bomber carry (Data/Drones): of no use on a
  -- ship either. A fighter's cannon is a quick gun that follows what it
  -- fires at and takes a cruiser's rounds, for ships of any size. A
  -- bomber's rack throws a siege dreadnought's missiles, slowly: for
  -- what is big and stands still, and next to nothing to a frigate.
  -- (First figures.)
  {
    id = "fighter.cannon", name = "Fighter Cannon", slot = "high", hardpoint = "turret",
    cpu = 20, powergrid = 20, volume = 10, basePrice = 300000, passive = {},
    weapon = { family = "projectile", duration = 2.5, capacitor = 0, damageMultiplier = 5.0,
      optimal = 3000, falloff = 9000, tracking = 300, clip = 200, reload = 8, size = 2 },
    internal = true, requires = { { skill = "fighters", level = 1 } },
  },
  {
    id = "bomber.rack", name = "Bomber Torpedo Rack", slot = "high", hardpoint = "launcher",
    cpu = 20, powergrid = 20, volume = 10, basePrice = 900000, passive = {},
    weapon = { family = "missile", duration = 14, capacitor = 0, damageMultiplier = 1.5,
      optimal = 0, falloff = 0, tracking = 0, clip = 12, reload = 30, size = 4 },
    internal = true, requires = { { skill = "fighters", level = 3 } },
  },

  -- Speed, capacitor, cargo
  {
    id = "afterburner.1mn", name = "Small Afterburner", slot = "mid", hardpoint = "",
    cpu = 13, powergrid = 9, volume = 5, basePrice = 9000, passive = {},
    boost = { ship("maxVelocity", "mul", 2.1), ship("mass", "add", 500000) },
    boostDuration = 10, boostCapacitor = 11,
  },
  -- Six times the speed for as long as the capacitor lasts, which is not
  -- long, and a signature six times the size while it burns: easy to hit
  -- from far off, hard to catch. (An afterburner is the other bargain.)
  {
    id = "mwd.5mn", name = "Small Microwarpdrive", slot = "mid", hardpoint = "",
    cpu = 22, powergrid = 14, volume = 5, basePrice = 60000, passive = { ship("capacitor", "mul", 0.85) },
    boost = { ship("maxVelocity", "mul", 6.0), ship("mass", "add", 500000), ship("signature", "mul", 6.0) },
    boostDuration = 10, boostCapacitor = 42,
  },
  {
    id = "overdrive", name = "Thrust Booster", slot = "low", hardpoint = "",
    cpu = 20, powergrid = 1, volume = 5, basePrice = 9000,
    passive = { ship("maxVelocity", "mul", 1.105, true), ship("cargo", "mul", 0.9) },
  },
  {
    id = "nanofiber", name = "Lightened Frame", slot = "low", hardpoint = "",
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
    id = "cargo.expander", name = "Cargo Extension", slot = "low", hardpoint = "",
    cpu = 0, powergrid = 0, volume = 5, basePrice = 5000,
    passive = { ship("cargo", "mul", 1.175, true), ship("maxVelocity", "mul", 0.9) },
  },
}

-- A round costs 20; a crystal, which is never used up, as much as a
-- hundred and fifty of them.
local function turretCharge(id: string, name: string, family: string, damage: { number }, range: number): ChargeType
  return { id = id, name = name, family = family, size = 1, volume = if family == "laser" then 1 else 0.0025,
    basePrice = if family == "laser" then 3000 else 20,
    damage = damage, rangeMultiplier = range, velocity = 0, flightTime = 0, explosionRadius = 0, explosionVelocity = 0 }
end

local function missile(id: string, name: string, damage: { number }): ChargeType
  return { id = id, name = name, family = "missile", size = 1, volume = 0.015, basePrice = 60, damage = damage, rangeMultiplier = 1,
    velocity = 3750, flightTime = 5, explosionRadius = 40, explosionVelocity = 170 }
end

local charges: { ChargeType } = {
  -- Crystals are not used up.
  turretCharge("crystal.multifrequency", "Wide-band Crystal", "laser", { 7, 5, 0, 0 }, 0.5),
  turretCharge("crystal.standard", "Standard Crystal", "laser", { 5, 3, 0, 0 }, 1.0),
  turretCharge("crystal.radio", "Long-wave Crystal", "laser", { 5, 0, 0, 0 }, 1.6),
  turretCharge("ammo.emp", "Shock Rounds", "projectile", { 9, 0, 1, 2 }, 0.5),
  turretCharge("ammo.fusion", "Burst Rounds", "projectile", { 0, 0, 2, 10 }, 0.5),
  turretCharge("ammo.sabot", "Penetrator Rounds", "projectile", { 0, 0, 6, 2 }, 1.0),
  missile("missile.light.kinetic", "Lance Light Missile", { 0, 0, 83, 0 }),
  missile("missile.light.explosive", "Breaker Light Missile", { 0, 0, 0, 83 }),
  missile("missile.light.thermal", "Ember Light Missile", { 0, 83, 0, 0 }),
}

-- ---------------------------------------------------------------------
-- The rest of the armoury, made from tables
--
-- Turrets come in three families, each in a short-range and a
-- long-range form, each of those in four sizes; launchers in four
-- sizes. A larger weapon reaches further, follows a crossing target
-- worse, and needs a larger ship to power it. What it does to a target
-- is its ammunition's doing: every size of weapon takes its own size of
-- charge, and a larger charge carries more.
--
-- The fourth size, XL, is what a siege dreadnought mounts (the project
-- owner's ladder of 2026-11-12; its figures are first drafts): each
-- wants more powergrid than a dreadnought has in all, so nothing else
-- carries one. The other fittings stop at large.

local SIZE_NAME = { "small", "medium", "large", "xl" }
local SIZE_TITLE = { "Small", "Medium", "Large", "XL" }
-- Charge damage, by size.
local SIZE_DAMAGE = { 1, 2.3, 5.5, 14 }

type Form = {
  id: string, title: string, family: string, skill: string,
  duration: number, capacitor: number, multiplier: number, optimal: number, falloff: number, tracking: number,
  clip: number, reload: number, cpu: number, powergrid: number, price: number,
}

local FORMS: { Form } = {
  { id = "laser.pulse", title = "Pulse Laser", family = "laser", skill = "lasers", duration = 3, capacitor = 3.5,
    multiplier = 2.2, optimal = 5200, falloff = 2500, tracking = 370, clip = 0, reload = 1, cpu = 9, powergrid = 6, price = 9000 },
  { id = "laser.beam", title = "Beam Laser", family = "laser", skill = "lasers", duration = 4, capacitor = 5,
    multiplier = 2.5, optimal = 11000, falloff = 3000, tracking = 160, clip = 0, reload = 1, cpu = 11, powergrid = 8, price = 11000 },
  { id = "autocannon", title = "Autocannon", family = "projectile", skill = "projectiles", duration = 2.8, capacitor = 0,
    multiplier = 2.0, optimal = 1100, falloff = 5200, tracking = 470, clip = 120, reload = 10, cpu = 6, powergrid = 3, price = 8000 },
  { id = "artillery", title = "Artillery", family = "projectile", skill = "projectiles", duration = 7, capacitor = 0,
    multiplier = 5.2, optimal = 9000, falloff = 6500, tracking = 110, clip = 20, reload = 10, cpu = 9, powergrid = 7, price = 10000 },
  { id = "blaster", title = "Blaster", family = "hybrid", skill = "hybrids", duration = 2.5, capacitor = 1.8,
    multiplier = 2.4, optimal = 1400, falloff = 2200, tracking = 430, clip = 80, reload = 5, cpu = 8, powergrid = 6, price = 9000 },
  { id = "railgun", title = "Railgun", family = "hybrid", skill = "hybrids", duration = 3.8, capacitor = 2.4,
    multiplier = 2.4, optimal = 12000, falloff = 5000, tracking = 140, clip = 80, reload = 5, cpu = 10, powergrid = 8, price = 11000 },
}

-- How a weapon grows with its size.
local SIZE_RANGE = { 1, 2.2, 4.4, 8 }
local SIZE_TRACKING = { 1, 0.33, 0.12, 0.04 }
local SIZE_CAPACITOR = { 1, 3, 9, 30 }
local SIZE_DURATION = { 1, 1.25, 1.6, 2.1 }
local SIZE_CPU = { 1, 2.4, 5, 10 }
local SIZE_POWERGRID = { 1, 18, 230, 12000 }
local SIZE_PRICE = { 1, 10, 100, 1500 }
local SIZE_VOLUME = { 5, 10, 20, 400 }
local SIZE_SKILL: { string? } = { nil, "medium.weapons", "large.weapons", "capital.weapons" }

local known: { [string]: boolean } = {}
for _, m in modules do
  known[m.id] = true
end

local function needs(skill: string, size: number): { { skill: string, level: number } }
  local list = { { skill = skill, level = 1 } }
  local sized = SIZE_SKILL[size]
  if sized then
    table.insert(list, { skill = sized, level = 1 })
  end
  return list
end

for _, form in FORMS do
  for size = 1, #SIZE_NAME do
    local id = `{form.id}.{SIZE_NAME[size]}`
    if not known[id] then
      table.insert(modules, {
        id = id, name = `{SIZE_TITLE[size]} {form.title}`, slot = "high", hardpoint = "turret",
        cpu = math.floor(form.cpu * SIZE_CPU[size] + 0.5), powergrid = math.floor(form.powergrid * SIZE_POWERGRID[size] + 0.5),
        volume = SIZE_VOLUME[size], basePrice = form.price * SIZE_PRICE[size], passive = {},
        weapon = { family = form.family, duration = form.duration * SIZE_DURATION[size],
          capacitor = form.capacitor * SIZE_CAPACITOR[size], damageMultiplier = form.multiplier,
          optimal = form.optimal * SIZE_RANGE[size], falloff = form.falloff * SIZE_RANGE[size],
          tracking = form.tracking * SIZE_TRACKING[size], clip = form.clip, reload = form.reload, size = size },
        requires = needs(form.skill, size),
      })
    end
  end
end

local LAUNCHERS = {
  { id = "launcher.heavy", name = "Heavy Missile Launcher", cpu = 50, powergrid = 95, price = 110000, duration = 12, clip = 30,
    reload = 35 },
  { id = "launcher.cruise", name = "Cruise Missile Launcher", cpu = 80, powergrid = 1300, price = 1100000, duration = 16, clip = 24,
    reload = 40 },
  { id = "launcher.siege", name = "Siege Missile Launcher", cpu = 160, powergrid = 40000, price = 16000000, duration = 22, clip = 16,
    reload = 50 },
}
for index, launcher in LAUNCHERS do
  table.insert(modules, {
    id = launcher.id, name = launcher.name, slot = "high", hardpoint = "launcher",
    cpu = launcher.cpu, powergrid = launcher.powergrid, volume = SIZE_VOLUME[index + 1], basePrice = launcher.price, passive = {},
    weapon = { family = "missile", duration = launcher.duration, capacitor = 0, damageMultiplier = 1.0,
      optimal = 0, falloff = 0, tracking = 0, clip = launcher.clip, reload = launcher.reload, size = index + 1 },
    requires = needs("missiles", index + 1),
  })
end

-- Rigs: worked into the hull for good. A rig does one thing well and
-- another a little worse, takes no CPU or powergrid, shares the hull's
-- calibration with the other rigs, and is destroyed if it is taken out.
-- They are built of what is salvaged from wrecks (Data/Blueprints).
--
-- A rig is made for a size of hull, and goes into no other (Data/Ships:
-- RigSize): a small one into a frigate or a destroyer, a medium one
-- into a cruiser, a hauler or a barge, a large one into a battleship.
-- All three do the same; what differs is what there is to work it
-- into, and so what it takes to make: three times as much salvage for
-- a medium rig as for a small one, and three times that for a large.
local RIG_SIZES: { { any } } = { { "", "Small ", 1 }, { ".medium", "Medium ", 3 }, { ".large", "Large ", 9 } }
local function rig(id: string, name: string, calibration: number, passive: { Modifier })
  for _, size in RIG_SIZES do
    table.insert(modules, {
      id = "rig." .. id .. size[1], name = size[2] .. name, slot = "rig", hardpoint = "", cpu = 0, powergrid = 0,
      volume = 5 * size[3], basePrice = 24000 * size[3],
      calibration = calibration, passive = passive, requires = { { skill = "jury.rigging", level = 1 } },
    })
  end
end
-- How many times a small rig's salvage a rig of each size takes.
local RIG_WORK = { 1, 3, 9 }
rig("shield", "Field Extender Rig", 150, { ship("shield", "mul", 1.15, true), ship("signature", "mul", 1.10) })
rig("armor", "Armour Pump Rig", 150, { ship("armor", "mul", 1.15, true), ship("maxVelocity", "mul", 0.90) })
rig("hull", "Bulkhead Rig", 100, { ship("hull", "mul", 1.20, true), ship("cargo", "mul", 0.90) })
rig("engine", "Engine Tuning Rig", 100, { ship("maxVelocity", "mul", 1.10, true), ship("armor", "mul", 0.90) })
rig("cargo", "Cargo Bracing Rig", 100, { ship("cargo", "mul", 1.15, true), ship("armor", "mul", 0.90) })
rig("capacitor", "Capacitor Flux Rig", 100, { ship("capacitorRecharge", "mul", 0.85, true), ship("shield", "mul", 0.90) })
rig("projectile", "Projectile Burst Rig", 200, { weapons("projectile", "duration", 0.90), ship("powergrid", "mul", 0.90) })
rig("laser", "Energy Burst Rig", 200, { weapons("laser", "duration", 0.90), ship("powergrid", "mul", 0.90) })
rig("hybrid", "Hybrid Burst Rig", 200, { weapons("hybrid", "duration", 0.90), ship("powergrid", "mul", 0.90) })

-- Fittings by size: the small ones are written out above, and a medium
-- and a large are each of those, scaled for a cruiser and a battleship.
local FITTINGS: { { any } } = {
  { "shield.extender.small", "shield.extender", "shield.operation" },
  { "shield.booster.small", "shield.booster", "shield.operation" },
  { "armor.plate.200mm", "armor.plate", "hull.upgrades" },
  { "armor.repairer.small", "armor.repairer", "repair.systems" },
  { "afterburner.1mn", "afterburner", "propulsion" },
  { "mwd.5mn", "mwd", "propulsion" },
  { "capacitor.battery.small", "capacitor.battery", "engineering" },
}
local FIT_AMOUNT = { 1, 3.2, 9 }
local FIT_MASS = { 1, 10, 100 }
local FIT_CPU = { 1, 1.6, 2.4 }
local FIT_POWERGRID = { 1, 15, 180 }
local FIT_PRICE = { 1, 8, 60 }
local FIT_CYCLE = { 1, 1.5, 2.25 }
local FIT_CAPACITOR = { 1, 3, 8.5 }

local function scaled(list: { Modifier }, size: number): { Modifier }
  local out: { Modifier } = {}
  for _, m in list do
    local value = m.value
    if m.op == "add" then
      value *= if m.attribute == "mass" then FIT_MASS[size] elseif m.attribute == "signature" then size else FIT_AMOUNT[size]
    end
    table.insert(out, { on = m.on, family = m.family, attribute = m.attribute, op = m.op, value = value, stack = m.stack })
  end
  return out
end

for _, fitting in FITTINGS do
  local small: ModuleType? = nil
  for _, m in modules do
    if m.id == fitting[1] then
      small = m
    end
  end
  local base = assert(small)
  for size = 2, 3 do
    local repair = base.repair
    table.insert(modules, {
      id = `{fitting[2]}.{SIZE_NAME[size]}`, name = (string.gsub(base.name, "Small", SIZE_TITLE[size])),
      slot = base.slot, hardpoint = base.hardpoint,
      cpu = math.floor(base.cpu * FIT_CPU[size] + 0.5), powergrid = math.floor(base.powergrid * FIT_POWERGRID[size] + 0.5),
      volume = base.volume * (size * size - size), basePrice = base.basePrice * FIT_PRICE[size],
      passive = scaled(base.passive, size),
      repair = if repair then { layer = repair.layer, amount = repair.amount * FIT_AMOUNT[size],
        duration = repair.duration * FIT_CYCLE[size], capacitor = repair.capacitor * FIT_CAPACITOR[size] } else nil,
      boost = if base.boost then scaled(base.boost, size) else nil,
      boostDuration = base.boostDuration,
      boostCapacitor = if base.boostCapacitor then base.boostCapacitor * FIT_CAPACITOR[size] else nil,
      requires = { { skill = fitting[3], level = size + 1 } },
    })
  end
end

-- And the remote repairers by size, and the relays: more put back, or
-- sent, from farther off. (What a relay sends is what it costs, at
-- every size.)
local REMOTE_RANGE = { 1, 1.6, 2.5 }
for _, base in table.clone(modules) do
  local hex = base.hex
  if hex and (hex.kind == "shield" or hex.kind == "armor" or hex.kind == "capacitor") and not base.internal then
    for size = 2, 3 do
      local cost = hex.capacitor * FIT_CAPACITOR[size]
      table.insert(modules, {
        id = (string.gsub(base.id, "small", SIZE_NAME[size])), name = (string.gsub(base.name, "Small", SIZE_TITLE[size])),
        slot = base.slot, hardpoint = base.hardpoint,
        cpu = math.floor(base.cpu * FIT_CPU[size] + 0.5), powergrid = math.floor(base.powergrid * FIT_POWERGRID[size] + 0.5),
        volume = base.volume * (size * size - size), basePrice = base.basePrice * FIT_PRICE[size], passive = {},
        hex = { kind = hex.kind, range = hex.range * REMOTE_RANGE[size],
          strength = if hex.kind == "capacitor" then cost else hex.strength * FIT_AMOUNT[size],
          duration = hex.duration, capacitor = cost },
        requires = { { skill = if hex.kind == "capacitor" then "engineering" else "remote.repair", level = size + 1 } },
      })
    end
  end
end

-- What a mining barge carries.
table.insert(modules, {
  id = "miner.strip", name = "Strip Miner", slot = "high", hardpoint = "turret",
  cpu = 80, powergrid = 40, volume = 25, basePrice = 400000, passive = {},
  miner = { volume = 200, duration = 120, capacitor = 180, range = 12000 },
  requires = { { skill = "mining", level = 4 } },
})

-- What draws the gas off a cloud (Data/Ores, Tactical/Sites): it works
-- from close by, and brings in half the room a mining laser cuts.
table.insert(modules, {
  id = "miner.gas", name = "Gas Harvester", short = "Harvester", slot = "high", hardpoint = "turret",
  cpu = 50, powergrid = 2, volume = 5, basePrice = 60000, passive = {},
  miner = { volume = 20, duration = 60, capacitor = 40, range = 3000, gas = true },
  requires = { { skill = "mining", level = 2 } },
})

-- Ammunition by size. The small charges are written out above; the
-- medium and large ones are those, larger. And what the hybrids fire.
table.insert(charges, turretCharge("charge.plasma", "Plasma Charge", "hybrid", { 0, 6, 5, 0 }, 0.5))
table.insert(charges, turretCharge("charge.slug", "Slug Charge", "hybrid", { 0, 3, 6, 0 }, 1.0))
table.insert(charges, turretCharge("charge.needle", "Needle Charge", "hybrid", { 0, 2, 5, 0 }, 1.6))
table.insert(charges, missile("missile.light.em", "Arc Light Missile", { 83, 0, 0, 0 }))

local MISSILE_SIZES = {
  { id = "heavy", title = "Heavy", damage = 190, velocity = 4300, flight = 6.5, radius = 140, speed = 85, volume = 0.03, price = 180 },
  { id = "cruise", title = "Cruise", damage = 450, velocity = 4700, flight = 14, radius = 330, speed = 70, volume = 0.05, price = 550 },
  -- (what a siege launcher throws: slow, and for what is big and slow)
  { id = "siege", title = "Siege", damage = 1150, velocity = 3800, flight = 24, radius = 1400, speed = 30, volume = 0.3, price = 3000 },
}
local MISSILE_KINDS = { { "em", "Arc", 1 }, { "thermal", "Ember", 2 }, { "kinetic", "Lance", 3 }, { "explosive", "Breaker", 4 } } :: { { any } }

for _, small in table.clone(charges) do
  if small.family ~= "missile" then
    for size = 2, #SIZE_NAME do
      local damage: { number } = {}
      for index, amount in small.damage do
        damage[index] = amount * SIZE_DAMAGE[size]
      end
      table.insert(charges, {
        id = `{small.id}.{SIZE_NAME[size]}`, name = `{SIZE_TITLE[size]} {small.name}`, family = small.family, size = size,
        volume = small.volume * (size * size - size), basePrice = small.basePrice * 3 ^ (size - 1),
        damage = damage, rangeMultiplier = small.rangeMultiplier,
        velocity = 0, flightTime = 0, explosionRadius = 0, explosionVelocity = 0,
      })
    end
  end
end
for index, sized in MISSILE_SIZES do
  for _, kind in MISSILE_KINDS do
    local damage = { 0, 0, 0, 0 }
    damage[kind[3]] = sized.damage
    table.insert(charges, {
      id = `missile.{sized.id}.{kind[1]}`, name = `{kind[2]} {sized.title} Missile`, family = "missile", size = index + 1,
      volume = sized.volume, basePrice = sized.price, damage = damage, rangeMultiplier = 1,
      velocity = sized.velocity, flightTime = sized.flight, explosionRadius = sized.radius, explosionVelocity = sized.speed,
    })
  end
end

-- Tech 2 charges: the improved make of every crystal, round, charge
-- and missile, which only a tech 2 weapon takes (Assets/Items). Each is
-- better at what the plain one is for and worse at something else, so
-- that it is a choice and not only a dearer round:
--   - a turret's short charge (the one that hits hardest, at half the
--     range) hits a quarter harder still, and the gun tracks a quarter
--     worse with it: for what is big and slow;
--   - its middle charge makes the gun track three tenths better, for a
--     twentieth more damage and a seventh less range: for what is small
--     and quick;
--   - its long charge reaches a quarter further, for a tenth more
--     damage, and the gun tracks a fifth worse with it: for what is to
--     be kept at a distance;
--   - a missile hits a quarter harder, and its blast is three tenths
--     wider, so that what is small takes less of it than of the plain
--     one.
-- Nobody sells them: the blueprint is invented from the plain charge's,
-- and they are built of the plain charge and of what lawless space has
-- (Data/Blueprints).
type Trade = { damage: number, range: number, tracking: number?, blast: number }
local CHARGE2 = {
  price = 5,
  short = { damage = 1.25, range = 1, tracking = 0.75, blast = 1 } :: Trade,
  middle = { damage = 1.05, range = 0.85, tracking = 1.3, blast = 1 } :: Trade,
  long = { damage = 1.10, range = 1.25, tracking = 0.8, blast = 1 } :: Trade,
  missile = { damage = 1.25, range = 1, tracking = nil, blast = 1.3 } :: Trade,
}
for _, base in table.clone(charges) do
  local trade: Trade = if base.family == "missile" then CHARGE2.missile
    elseif base.rangeMultiplier < 0.8 then CHARGE2.short
    elseif base.rangeMultiplier > 1.3 then CHARGE2.long
    else CHARGE2.middle
  local damage: { number } = {}
  for index, amount in base.damage do
    damage[index] = amount * trade.damage
  end
  table.insert(charges, {
    id = base.id .. ".ii", name = base.name .. " II", family = base.family, size = base.size, volume = base.volume,
    basePrice = base.basePrice * CHARGE2.price, damage = damage, rangeMultiplier = base.rangeMultiplier * trade.range,
    tracking = trade.tracking,
    velocity = base.velocity, flightTime = base.flightTime, explosionRadius = base.explosionRadius * trade.blast,
    explosionVelocity = base.explosionVelocity, tech = 2, base = base.id,
  })
end

-- Tech 2: the improved make of every weapon, repairer (a ship's own, or
-- one for another ship), shield extender, armour plate and mining
-- laser. A fifth more damage, or a quarter more of what it mends, holds
-- or cuts, for a seventh more CPU and powergrid and a good deal more
-- skill (Data/Skills). Nobody sells
-- one: its blueprint is invented from the plain module's in a
-- laboratory, and it is built of the plain module and of minerals that
-- safe space does not have (Data/Blueprints, Assets/Industry).
--
-- And between the plain make and tech 2, the custom make of each of the
-- same modules: one that somebody has worked over. A tenth more damage,
-- or an eighth more of what it mends, holds or cuts, for a tenth less
-- CPU and powergrid, and no more skill than the plain one. Nobody
-- sells or builds these: a pirate's wreck now and then has the custom
-- make of what the pirate had fitted, and their stores have some.
--
-- And past tech 2, the masterwork of each of the same modules: a
-- quarter more damage, or a third more of what it mends, holds or cuts,
-- as easy to fit as the custom make, and no more skill than the plain
-- one. Nobody sells, builds or stores these: a pirate captain fits
-- them, and what is left of them is in the captain's wreck.
--
-- (What only a drone carries has a tech 2 make and no custom one: it is
-- what a tech 2 drone carries, and is no more to be had apart than the
-- plain one is.)
type Better = { id: string, name: string, damage: number, amount: number, fitting: number, price: number, tech: number?, meta: number? }
local TECH2: Better = { id = ".ii", name = " II", damage = 1.2, amount = 1.25, fitting = 1.15, price = 8, tech = 2 }
local CUSTOM: Better = { id = ".custom", name = " Custom", damage = 1.1, amount = 1.125, fitting = 0.9, price = 3, meta = 1 }
local MASTER: Better = { id = ".master", name = " Masterwork", damage = 1.25, amount = 1.35, fitting = 0.9, price = 20, meta = 2 }
for _, base in table.clone(modules) do
  local buffer = string.sub(base.id, 1, 15) == "shield.extender" or string.sub(base.id, 1, 11) == "armor.plate"
  local hex = base.hex
  local mends = hex ~= nil and (hex.kind == "shield" or hex.kind == "armor")
  if base.weapon or base.repair or base.miner or buffer or mends then
    local weapon, repair, miner = base.weapon, base.repair, base.miner
    local makes: { Better } = if base.internal then { TECH2 } else { CUSTOM, TECH2, MASTER }
    for _, make in makes do
      local passive: { Modifier } = {}
      for _, m in base.passive do
        -- (what it holds is more; what it weighs and shows is the same)
        local more = m.op == "add" and (m.attribute == "shield" or m.attribute == "armor")
        table.insert(passive, { on = m.on, family = m.family, attribute = m.attribute, op = m.op,
          value = if more then m.value * make.amount else m.value, stack = m.stack })
      end
      table.insert(modules, {
        id = base.id .. make.id, name = base.name .. make.name, slot = base.slot, hardpoint = base.hardpoint,
        -- (what takes more to fit takes a whole unit more, and what takes less, a whole unit less)
        cpu = math.max(1, if make.fitting < 1 then math.floor(base.cpu * make.fitting) else math.ceil(base.cpu * make.fitting)),
        powergrid = math.max(1, if make.fitting < 1 then math.floor(base.powergrid * make.fitting)
          else math.ceil(base.powergrid * make.fitting)),
        volume = base.volume, basePrice = base.basePrice * make.price, passive = passive,
        weapon = if weapon then { family = weapon.family, duration = weapon.duration, capacitor = weapon.capacitor,
          damageMultiplier = weapon.damageMultiplier * make.damage, optimal = weapon.optimal, falloff = weapon.falloff,
          tracking = weapon.tracking, clip = weapon.clip, reload = weapon.reload, size = weapon.size } else nil,
        repair = if repair then { layer = repair.layer, amount = repair.amount * make.amount, duration = repair.duration,
          capacitor = repair.capacitor } else nil,
        miner = if miner then { volume = miner.volume * make.amount, duration = miner.duration, capacitor = miner.capacitor,
          range = miner.range, gas = miner.gas } else nil,
        hex = if hex and mends then { kind = hex.kind, range = hex.range, strength = hex.strength * make.amount,
          duration = hex.duration, capacitor = hex.capacitor } else nil,
        internal = base.internal,
        tech = make.tech, meta = make.meta, base = base.id,
      })
    end
  end
end

local Modules = {
  list = modules,
  byId = {} :: { [string]: ModuleType },
  charges = charges,
  chargeById = {} :: { [string]: ChargeType },
}

for _, m in modules do
  Modules.byId[m.id] = m
end

-- The tech 2 make of a module, if it has one.
function Modules.Improved(id: string): ModuleType?
  local better = Modules.byId[id .. ".ii"]
  return if better and better.tech == 2 then better else nil
end

-- The tech 2 make of a charge, if it has one.
function Modules.ImprovedCharge(id: string): ChargeType?
  local better = Modules.chargeById[id .. ".ii"]
  return if better and better.tech == 2 then better else nil
end

-- The custom make of a module, if it has one.
function Modules.Custom(id: string): ModuleType?
  local better = Modules.byId[id .. ".custom"]
  return if better and better.meta then better else nil
end

-- The masterwork of a module, if it has one.
function Modules.Masterwork(id: string): ModuleType?
  local better = Modules.byId[id .. ".master"]
  return if better and better.meta then better else nil
end

-- The make of a module that a pirate of a grade fits (Tactical/Pirates):
-- the custom make for a veteran (1), the masterwork for a captain (2);
-- the module itself where there is no such make of it, or for anybody
-- else.
function Modules.Graded(id: string, grade: number): string
  local better = if grade == 1 then Modules.Custom(id) elseif grade == 2 then Modules.Masterwork(id) else nil
  return if better then better.id else id
end

-- How much more of everything a rig takes to make than a small one of
-- its kind (Data/Blueprints).
function Modules.RigWork(module: ModuleType): number
  return RIG_WORK[if string.find(module.id, ".large", 1, true) then 3 elseif string.find(module.id, ".medium", 1, true) then 2 else 1]
end

-- A module's size, 1 to 3: its weapon's, or what its name says.
function Modules.SizeOf(module: ModuleType): number
  if module.weapon then
    return module.weapon.size
  end
  return if string.find(module.id, "large", 1, true) then 3 elseif string.find(module.id, "medium", 1, true) then 2 else 1
end

-- Whether a module is one that mends another ship (a remote shield
-- booster or armour repairer).
function Modules.Mends(module: ModuleType): boolean
  return module.hex ~= nil and (module.hex.kind == "shield" or module.hex.kind == "armor")
end

-- Whether a module that runs on another ship is for a friend (one that
-- mends, or a relay that sends capacitor), where everything else that
-- runs on another ship is for an enemy.
function Modules.Friendly(module: ModuleType): boolean
  return module.hex ~= nil and (Modules.Mends(module) or module.hex.kind == "capacitor")
end
for _, c in charges do
  Modules.chargeById[c.id] = c
end

return Modules
