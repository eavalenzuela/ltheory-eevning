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
  -- Skills a pilot needs to fit it. (Where absent, Data/Skills says.)
  requires: { { skill: string, level: number } }?,
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

  -- Speed, capacitor, cargo
  {
    id = "afterburner.1mn", name = "Small Afterburner", slot = "mid", hardpoint = "",
    cpu = 13, powergrid = 9, volume = 5, basePrice = 9000, passive = {},
    boost = { ship("maxVelocity", "mul", 2.1), ship("mass", "add", 500000) },
    boostDuration = 10, boostCapacitor = 11,
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
-- long-range form, each of those in three sizes; launchers in three
-- sizes. A larger weapon reaches further, follows a crossing target
-- worse, and needs a larger ship to power it. What it does to a target
-- is its ammunition's doing: every size of weapon takes its own size of
-- charge, and a larger charge carries more.

local SIZE_NAME = { "small", "medium", "large" }
local SIZE_TITLE = { "Small", "Medium", "Large" }
-- Charge damage, by size.
local SIZE_DAMAGE = { 1, 2.3, 5.5 }

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
local SIZE_RANGE = { 1, 2.2, 4.4 }
local SIZE_TRACKING = { 1, 0.33, 0.12 }
local SIZE_CAPACITOR = { 1, 3, 9 }
local SIZE_DURATION = { 1, 1.25, 1.6 }
local SIZE_CPU = { 1, 2.4, 5 }
local SIZE_POWERGRID = { 1, 18, 230 }
local SIZE_PRICE = { 1, 10, 100 }
local SIZE_VOLUME = { 5, 10, 20 }
local SIZE_SKILL: { string? } = { nil, "medium.weapons", "large.weapons" }

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
  for size = 1, 3 do
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

-- Fittings by size: the small ones are written out above, and a medium
-- and a large are each of those, scaled for a cruiser and a battleship.
local FITTINGS: { { any } } = {
  { "shield.extender.small", "shield.extender", "shield.operation" },
  { "shield.booster.small", "shield.booster", "shield.operation" },
  { "armor.plate.200mm", "armor.plate", "hull.upgrades" },
  { "armor.repairer.small", "armor.repairer", "repair.systems" },
  { "afterburner.1mn", "afterburner", "propulsion" },
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

-- What a mining barge carries.
table.insert(modules, {
  id = "miner.strip", name = "Strip Miner", slot = "high", hardpoint = "turret",
  cpu = 80, powergrid = 40, volume = 25, basePrice = 400000, passive = {},
  miner = { volume = 200, duration = 120, capacitor = 180, range = 12000 },
  requires = { { skill = "mining", level = 4 } },
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
}
local MISSILE_KINDS = { { "em", "Arc", 1 }, { "thermal", "Ember", 2 }, { "kinetic", "Lance", 3 }, { "explosive", "Breaker", 4 } } :: { { any } }

for _, small in table.clone(charges) do
  if small.family ~= "missile" then
    for size = 2, 3 do
      local damage: { number } = {}
      for index, amount in small.damage do
        damage[index] = amount * SIZE_DAMAGE[size]
      end
      table.insert(charges, {
        id = `{small.id}.{SIZE_NAME[size]}`, name = `{SIZE_TITLE[size]} {small.name}`, family = small.family, size = size,
        volume = small.volume * (size * size - size), basePrice = small.basePrice * (if size == 2 then 3 else 9),
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
