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
  -- The size of hardpoint it goes on, where that is not its charges'
  -- size: a rapid launcher's, a medium one throwing light missiles.
  mount: number?,
  -- launchers: how long its missiles fly, as a share of what the
  -- missile flies by itself, and how wide their blast is, likewise (1
  -- where not said: a short-range launcher throws its missiles a third
  -- as far, and a flight computer changes both)
  -- (how much faster its missiles fly than their own speed: a hull's
  -- bonus, Data/HullBonuses; nil for 1)
  speed: number?,
  flight: number?,
  blast: number?,
  -- A beam that leaps (the Vail's Litany Beam): on a hit it goes on to
  -- the nearest other ship of its target's side within 'reach' of the
  -- one it struck, at most 'leaps' times a shot and never to a ship it
  -- has struck already, each leap doing 'share' of the hit before it and
  -- rolling its own hit; a miss ends it (Tactical/Combat). Nil for every
  -- other weapon.
  leap: { reach: number, leaps: number, share: number }?,
  -- A launcher that throws a volley (the Vessari's Swarm Launcher, the
  -- Kethri's Vertical Launch Battery): each cycle 'count' missiles at the
  -- one target, 'gap' seconds apart, each 'share' of the missile it is
  -- loaded with over 'count', flying 'speed' times as fast along a path
  -- 'stretch' times as long as the straight way ('path' says how it is
  -- drawn: "zig", jinking, or "arc", up out of the cell and down on the
  -- target). One with 'closest' will not fire at what is nearer than so
  -- much of its reach (Tactical/Combat). Each is a missile of its own, to
  -- be shot down by itself. Nil for every other weapon.
  volley: Volley?,
  -- A launcher that takes only its own line of ammunition (ChargeType's
  -- 'line': "vertical", the Kethri's vertical-launch missiles; "plasma",
  -- the Nimia's plasma torpedoes), and no other.
  line: string?,
  -- How what it fires flies, where that is not as a missile's: "plasma",
  -- the Nimia's plasma torpedoes, which point defence cannot shoot down
  -- (Tactical/PointDefence). (A volley's is its 'path'.)
  path: string?,
}

-- A point defence turret: rounds a second; how fast it swings (radians
-- a second); its tracking, optimal and falloff, as a turret's; and what a
-- round that hits a drone does, as a part of the round's damage; and
-- how much of what the gunnery odds say each round has of hitting a
-- missile (small, quick and hard to hit: most rounds go wide).
export type PointDefence = {
  accuracy: number,
  rate: number,
  traverse: number,
  tracking: number,
  optimal: number,
  falloff: number,
  damage: number,
}

export type Volley = {
  count: number,
  share: number,
  speed: number,
  gap: number,
  path: string,
  stretch: number?,
  closest: number?,
}

export type Repair = {
  layer: "shield" | "armor" | "hull",
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
  -- It cuts ice, and nothing else (2026-11-16).
  ice: boolean?,
}

-- What a module does to another ship while it runs on it. An "entangle" cuts
-- the target's top speed to 'strength' of what it was; a "scramble"
-- keeps it out of warp (a capital only if the module is a capital's:
-- ModuleType's 'capital'); a "paint" makes its signature 'strength' times
-- as big; a "damp" cuts how far it can lock and how fast to 'strength'
-- of what they were; a "neut" takes 'strength' GJ from its capacitor
-- each cycle; and a "jam" has a chance of 'strength' each cycle of
-- breaking every lock it holds. Three are for a friend: a "shield" puts
-- 'strength' points back on its target's shield each cycle, an
-- "armor" on its armour, and a "capacitor" puts 'strength' GJ into its
-- capacitor (which is what the cycle costs the ship that sends it: the
-- energy is moved, not made).
export type Hex = {
  -- (module expansion, 2026-11-16: "track" a tracking disruptor, "guide" a
  -- guidance disruptor, "nos" an energy drain, "sensor" a remote sensor booster)
  kind: "entangle" | "scramble" | "paint" | "damp" | "neut" | "jam" | "shield" | "armor" | "capacitor" | "track" | "guide" | "nos"
    | "sensor",
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
  -- (more from the ship's own repairers of a layer, "shield" or "armor",
  -- while it is fitted: so much more, the more of them the less each,
  -- Tactical/Combat)
  amplify: { layer: string, by: number }?,
  -- (so much more drone control range, m: Tactical/Drones)
  droneRange: number?,
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
  -- 'reach' metres of it switches it off. 'cpu' is what it asks to be
  -- fitted, beside the module's own figure: that share of the hull's
  -- own CPU, whatever the hull (Attributes.Needs).
  cloak: { reach: number, cpu: number }?,
  -- A jump beacon generator: while it runs, a ship with a jump drive
  -- can jump to the system the ship is in (Tactical/Jumping).
  beacon: boolean?,
  -- (a Jump Portal Generator: Tactical/Jumping)
  portal: boolean?,
  -- (so many more codes in a hacker's buffer: Tactical/Hacking)
  hackBuffer: number?,
  -- A data analyzer: fitted, it lets the ship hack a sealed hold from
  -- within its range (Tactical/Hacking).
  -- (a relic analyzer, 2026-11-16, opens a derelict's hold; a data
  -- analyzer, since, a listening post's vaults)
  analyzer: { range: number, relic: boolean? }?,
  -- A capital's module: only a hull of a capital class fits it
  -- (Attributes.Check). And of a warp disruptor, that it holds a capital
  -- too, which a plain one does not (Tactical/Combat).
  capital: boolean?,
  -- What it is called for short, where there is not room for its name.
  short: string?,
  -- Skills a pilot needs to fit it. (Where absent, Data/Skills says.)
  requires: { { skill: string, level: number } }?,
  -- What only a drone carries (Data/Drones): nobody sells it, finds it
  -- or fits it to a ship.
  internal: boolean?,
  -- A people's own make (a faction's id): no market of anybody else's
  -- has it, nor the drawings for it. (The Nimia's mending gear.)
  lineage: string?,
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
  -- 3 for a people's own make (the owner's, 2026-11-15): what one of
  -- the four peoples builds of the kinds of module it is known for,
  -- better than the custom make and short of tech 2. 'lineage' says
  -- whose: their stations sell it, to a pilot they think well of.
  -- 4 for an officer's: the module 'base' as a named officer of the
  -- pirates carried it, better than a masterwork, and called by their
  -- name. Only that officer's wreck has it.
  meta: number?,
  -- A module that has been put through a mutator: every figure of it
  -- moved, each its own way, for better or for worse. 'rolls' are how
  -- far, in hundredths (what it gives, how easy it is to fit, how little
  -- it draws, how far it reaches: more is better, of each).
  mutated: boolean?,
  rolls: { number }?,
  -- The officer whose it was, for an officer's.
  officer: string?,
  -- What a module that is no weapon is loaded with (Modules.Takes): the
  -- family and size of charge (size 0: any), how many it holds, and the
  -- seconds a reload from the hold takes. (Module expansion, 2026-11-16.)
  takes: { family: string, size: number, clip: number, reload: number, line: string? }?,
  -- A point defence turret (Tactical/PointDefence): switched on, it
  -- shoots at the enemy's missiles in reach, and at their drones.
  pds: PointDefence?,
  -- A Fighter Pylon (the Drowned's): the drone it carries on the hull,
  -- launched when it is switched on (Tactical/Drones), and the drone
  -- bandwidth it holds for that while fitted.
  pylon: { drone: string, bandwidth: number }?,
  -- A capacitor booster: each cycle (s) puts the charge it is loaded
  -- with into the capacitor, a charge a cycle.
  injector: { duration: number }?,
  -- A repairer that does 'factor' times as much a cycle while it has a
  -- charge loaded, a charge a cycle (an armour one: paste); a shield one
  -- spends a charge in place of capacitor instead (factor 1).
  ancillary: { factor: number }?,
  -- An adaptive hardener: while it runs it holds 'total' of armour
  -- resistance spread over the four kinds, at first evenly, and each
  -- cycle moves 'step' of it from the kind the ship took least of to the
  -- kind it took most of (Tactical/Combat).
  adaptive: { total: number, step: number }?,
  -- What it does for the drones of the ship it is fitted to: their guns'
  -- damage, and their tracking and reach, so many times.
  drones: { damage: number?, tracking: number?, speed: number? }?,
  -- A smartbomb: each cycle, so much damage of each kind to every ship
  -- within 'range' of it but its owner's own.
  smartbomb: { range: number, damage: { number }, duration: number, capacitor: number }?,
  -- A micro jump drive: so far ahead, after a spool of so many seconds.
  jump: { distance: number, spool: number }?,
  -- A warp stabilizer: points against warp disruption.
  stabilizer: number?,
  -- A tractor beam: pulls a wreck so fast toward the ship, from within range.
  tractor: { range: number, speed: number, duration: number, capacitor: number }?,
  -- A scanner: a ship's fit, its hold, or the rocks round about.
  scanner: { kind: "ship" | "cargo" | "survey", range: number, duration: number, capacitor: number }?,
  -- A mining upgrade: ore off a rock so many times as much.
  mining: number?,
  -- (so much more ice a cycle, as 'mining' is ore: Tactical/Combat's Yield)
  ice: number?,
  -- (so much more chance a salvager's cycle brings something off, added;
  -- and so many times the strength of the probes launched: 2026-11-20)
  salvage: number?,
  probing: number?,
  -- A Burst Jammer: a cycle at a time, every ship not its owner's within
  -- 'range' has 'strength' chance of having its locks broken
  -- (Tactical/Combat).
  burstJam: { range: number, strength: number, duration: number, capacitor: number }?,
  -- A command burst: what its 'boost' does, on the owner's ships within
  -- range; a mining burst, ore off a rock so many times as much.
  burst: { range: number, mining: number? }?,
  -- The hull classes it goes on, if only some (a siege module a dreadnought's).
  classes: { string }?,
  -- While it runs the ship cannot move, warp, jump or dock.
  immobile: boolean?,
  -- What it burns out of the hold each cycle.
  burns: { type: string, quantity: number }?,
  -- A triage module: remote repair and capacitor sent so many times as much.
  triage: number?,
  -- An industrial core: the ship's command bursts reach twice as far.
  core: boolean?,
  -- A launcher of interdiction fields: so wide, lasting so many seconds.
  bubble: { radius: number, lasts: number }?,
  -- A probe launcher (Tactical/Sites): it puts out the scan probes in
  -- the hold, and each reads 'strength' times what a plain one's does.
  probes: { strength: number }?,
  -- A people's make of a module outside its speciality: shaded to its
  -- style (Modules.Shade), not the speciality's make.
  shaded: boolean?,
  -- A pirate site's make (meta 6): its grade, 1 to 3 (Modules.SiteMake).
  site: number?,
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
  -- A capacitor charge: GJ it puts into the capacitor (a booster's).
  injects: number?,
  -- A mining crystal: so many times as much of this ore in a modulated laser.
  ore: string?,
  -- A charge of a launcher's own line ("vertical", "plasma"): for that
  -- launcher only (Weapon's 'line').
  line: string?,
  yieldBy: number?,
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
    cpu = 15, powergrid = 10, volume = 5, basePrice = 9000, passive = {},
    weapon = { family = "laser", duration = 3.5, capacitor = 4.44, damageMultiplier = 3,
      optimal = 5250, falloff = 2500, tracking = 246, clip = 0, reload = 1, size = 1 },
  },
  {
    id = "autocannon.small", name = "Small Autocannon", slot = "high", hardpoint = "turret",
    cpu = 9, powergrid = 4, volume = 5, basePrice = 8000, passive = {},
    weapon = { family = "projectile", duration = 3.75, capacitor = 0, damageMultiplier = 2.89,
      optimal = 1000, falloff = 5160, tracking = 315, clip = 120, reload = 10, size = 1 },
  },
  {
    id = "launcher.light", name = "Light Missile Launcher", slot = "high", hardpoint = "launcher",
    cpu = 21, powergrid = 6, volume = 5, basePrice = 12000, passive = {},
    weapon = { family = "missile", duration = 16, capacitor = 0, damageMultiplier = 1.0,
      optimal = 0, falloff = 0, tracking = 0, clip = 30, reload = 30, size = 1 },
  },

  -- Mining
  {
    id = "miner.small", name = "Mining Laser", slot = "high", hardpoint = "turret",
    cpu = 60, powergrid = 2, volume = 5, basePrice = 15000, passive = {},
    -- (100 m3 a minute since 2026-11-16, when income came up: it was 40. Mine.)
    miner = { volume = 100, duration = 60, capacitor = 60, range = 10000 },
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
  -- The Nimia's own: a low-slot module that makes a hull that mends by
  -- itself (theirs: Data/Ships' 'armorMend' and 'hullMend') mend half
  -- as fast again, armour and hull both. More than one, and each does
  -- less than the last. On a hull that does not mend it does nothing.
  {
    id = "mend.lattice", name = "Mending Lattice", slot = "low", hardpoint = "",
    cpu = 20, powergrid = 2, volume = 5, basePrice = 60000, lineage = "nimia",
    passive = { ship("armorMend", "mul", 1.5, true), ship("hullMend", "mul", 1.5, true) },
    requires = { { skill = "armor.mending", level = 1 } },
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
    id = "flux.coil", name = "Flux Coil", slot = "low", hardpoint = "",
    cpu = 20, powergrid = 1, volume = 5, basePrice = 25000,
    passive = { weapons("hybrid", "damageMultiplier", 1.10), weapons("hybrid", "duration", 0.895) },
  },
  {
    id = "ballistic.control", name = "Guidance Computer", slot = "low", hardpoint = "",
    cpu = 30, powergrid = 1, volume = 5, basePrice = 25000,
    passive = { weapons("missile", "damageMultiplier", 1.10), weapons("missile", "duration", 0.895) },
  },
  {
    id = "tracking.enhancer", name = "Tracking Enhancer", slot = "low", hardpoint = "",
    cpu = 10, powergrid = 1, volume = 5, basePrice = 18000,
    -- (every turret there is: "turret" is every family but missiles, Core/Attributes)
    passive = { weapons("turret", "tracking", 1.095), weapons("turret", "optimal", 1.10), weapons("turret", "falloff", 1.20) },
  },
  -- What is switched on to help the weapons (the project owner's,
  -- 2026-11-14: "tracking and range computers for turrets and guidance
  -- modules for missiles", with no scripts): each does more than what is
  -- only bolted on, for a mid slot and capacitor while it runs.
  {
    id = "computer.tracking", name = "Tracking Computer", slot = "mid", hardpoint = "",
    cpu = 30, powergrid = 1, volume = 5, basePrice = 30000, passive = {},
    boost = { weapons("turret", "tracking", 1.25) }, boostDuration = 10, boostCapacitor = 6,
  },
  {
    id = "computer.range", name = "Ranging Computer", slot = "mid", hardpoint = "",
    cpu = 30, powergrid = 1, volume = 5, basePrice = 30000, passive = {},
    boost = { weapons("turret", "optimal", 1.15), weapons("turret", "falloff", 1.25) }, boostDuration = 10, boostCapacitor = 6,
  },
  {
    id = "computer.flight", name = "Flight Computer", slot = "mid", hardpoint = "",
    cpu = 30, powergrid = 1, volume = 5, basePrice = 30000, passive = {},
    boost = { weapons("missile", "flight", 1.2), weapons("missile", "blast", 0.85) }, boostDuration = 10, boostCapacitor = 6,
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
  -- And the one that holds a capital. A plain warp disruptor does
  -- nothing to a hull of a capital class (the project owner's rule,
  -- 2026-11-15: "Warp disrupting the archangel itself only works with a
  -- capital warp disruptor, same as other capitals"); this one holds
  -- anything, and only a capital fits it. (Its figures are first ones.)
  {
    id = "disruptor.warp.capital", name = "Capital Warp Disruptor", slot = "mid", hardpoint = "",
    cpu = 60, powergrid = 1500, volume = 40, basePrice = 4000000, passive = {}, capital = true,
    hex = { kind = "scramble", range = 30000, strength = 1, duration = 5, capacitor = 80 },
    requires = { { skill = "propulsion.jamming", level = 4 } },
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
  -- It is very dear to fit to a hull that is not built for it (the
  -- project owner's word, 2026-11-13: "cloaks are usually *very*
  -- CPU-expensive, on hulls that are not designed for it"): it asks
  -- three quarters of the hull's own CPU, of a frigate as of a
  -- battleship, so that a ship with one carries little else. A hull that
  -- is built for it asks a tenth of that (Ships.CLOAK_FITTING). (That it
  -- is a share of the hull's, and three quarters, are first figures: a
  -- plain number of teraflops is nothing to a battleship or more than a
  -- frigate has.)
  {
    id = "cloak.device", name = "Cloaking Device", slot = "high", hardpoint = "",
    cpu = 0, powergrid = 1, volume = 5, basePrice = 250000, passive = {},
    boost = { ship("maxVelocity", "mul", 0.25) }, boostDuration = 5, boostCapacitor = 2,
    cloak = { reach = 2000, cpu = 0.75 },
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
    miner = { volume = 25, duration = 60, capacitor = 5, range = 2000 }, internal = true,
  },
  {
    id = "remote.armor.drone", name = "Drone Armor Repairer", slot = "high", hardpoint = "",
    cpu = 5, powergrid = 1, volume = 1, basePrice = 8000, passive = {},
    hex = { kind = "armor", range = 3000, strength = 18, duration = 5, capacitor = 6 }, internal = true,
  },
  -- And what a combat drone shoots with: what a light and a medium drone
  -- carried when they flew a ship's small and medium autocannons, before
  -- the ships' guns were set from the reference (2026-11-18), so that
  -- drones are as they were. Of no use on a ship.
  {
    id = "drone.gun.light", name = "Light Drone Autocannon", slot = "high", hardpoint = "turret",
    cpu = 6, powergrid = 3, volume = 1, basePrice = 8000, passive = {},
    weapon = { family = "projectile", duration = 2.8, capacitor = 0, damageMultiplier = 2.0,
      optimal = 1100, falloff = 5200, tracking = 470, clip = 120, reload = 10, size = 1 },
    internal = true, requires = { { skill = "drones", level = 1 } },
  },
  {
    id = "drone.gun.medium", name = "Medium Drone Autocannon", slot = "high", hardpoint = "turret",
    cpu = 14, powergrid = 54, volume = 1, basePrice = 80000, passive = {},
    weapon = { family = "projectile", duration = 3.5, capacitor = 0, damageMultiplier = 2.3,
      optimal = 2420, falloff = 11440, tracking = 155, clip = 120, reload = 10, size = 2 },
    internal = true, requires = { { skill = "drones", level = 1 } },
  },
  -- And a heavy drone's and a sentry's: a battleship's rounds, the heavy
  -- one's slow to follow, the sentry's from far off and slower still.
  -- (First figures, mine.)
  {
    id = "drone.gun.heavy", name = "Heavy Drone Autocannon", slot = "high", hardpoint = "turret",
    cpu = 24, powergrid = 200, volume = 1, basePrice = 250000, passive = {},
    weapon = { family = "projectile", duration = 4.5, capacitor = 0, damageMultiplier = 2.4,
      optimal = 4000, falloff = 16000, tracking = 45, clip = 120, reload = 10, size = 3 },
    internal = true, requires = { { skill = "drones", level = 3 } },
  },
  {
    id = "drone.gun.sentry", name = "Sentry Drone Cannon", slot = "high", hardpoint = "turret",
    cpu = 24, powergrid = 200, volume = 1, basePrice = 300000, passive = {},
    weapon = { family = "projectile", duration = 5, capacitor = 0, damageMultiplier = 2.2,
      optimal = 25000, falloff = 20000, tracking = 12, clip = 120, reload = 10, size = 3 },
    internal = true, requires = { { skill = "drones", level = 3 } },
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
    weapon = { family = "projectile", duration = 2.5, capacitor = 0, damageMultiplier = 5.75,
      optimal = 3000, falloff = 9000, tracking = 300, clip = 200, reload = 8, size = 2 },
    internal = true, requires = { { skill = "fighters", level = 1 } },
  },
  {
    id = "bomber.rack", name = "Bomber Torpedo Rack", slot = "high", hardpoint = "launcher",
    cpu = 20, powergrid = 20, volume = 10, basePrice = 900000, passive = {},
    -- (what it throws hits four times as hard and spreads four times as
    -- wide since 2026-11-18, the reference's: on a tower about what it did)
    weapon = { family = "missile", duration = 14, capacitor = 0, damageMultiplier = 0.5,
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

-- ---------------------------------------------------------------------
-- Module expansion, the first group: fitting and tank (the owner,
-- 2026-11-16, asked which groups of new kinds: all four; this is the
-- first). The figures are mine.

-- What the hull has to fit with: more CPU, or more powergrid (not
-- penalised against each other: each is the only one of its kind).
table.insert(modules, {
  id = "fitting.coprocessor", name = "Co-Processor", slot = "low", hardpoint = "",
  cpu = 0, powergrid = 1, volume = 5, basePrice = 15000, passive = { ship("cpu", "mul", 1.10) },
  requires = { { skill = "electronics", level = 2 } },
})
table.insert(modules, {
  id = "fitting.reactor", name = "Reactor Control Unit", slot = "low", hardpoint = "",
  cpu = 20, powergrid = 0, volume = 5, basePrice = 18000, passive = { ship("powergrid", "mul", 1.10) },
  requires = { { skill = "engineering", level = 2 } },
})
-- A relay: one of the ship's two recharges quicker, the other slower.
table.insert(modules, {
  id = "relay.shield", name = "Shield Power Relay", slot = "low", hardpoint = "",
  cpu = 12, powergrid = 1, volume = 5, basePrice = 12000,
  passive = { ship("shieldRecharge", "mul", 0.8, true), ship("capacitorRecharge", "mul", 1.1) },
  requires = { { skill = "shield.operation", level = 2 } },
})
-- What makes a shield come back the quicker by itself (2026-11-18, the
-- owner's "yes" to the reference's three, for a ship that tanks by its
-- shield's own recharge: the Vail's): a recharger for a mid slot, and a
-- flux coil for a low one, which does more for less shield. (And a rig,
-- below.)
table.insert(modules, {
  id = "shield.recharger", name = "Shield Recharger", slot = "mid", hardpoint = "",
  cpu = 25, powergrid = 1, volume = 5, basePrice = 10000,
  passive = { ship("shieldRecharge", "mul", 0.9, true) },
  requires = { { skill = "shield.operation", level = 1 } },
})
table.insert(modules, {
  id = "shield.fluxcoil", name = "Shield Flux Coil", slot = "low", hardpoint = "",
  cpu = 20, powergrid = 1, volume = 5, basePrice = 14000,
  passive = { ship("shieldRecharge", "mul", 0.72, true), ship("shield", "mul", 0.85, true) },
  requires = { { skill = "shield.operation", level = 2 } },
})
table.insert(modules, {
  id = "relay.capacitor", name = "Capacitor Power Relay", slot = "low", hardpoint = "",
  cpu = 12, powergrid = 1, volume = 5, basePrice = 12000,
  passive = { ship("capacitorRecharge", "mul", 0.8, true), ship("shieldRecharge", "mul", 1.1) },
  requires = { { skill = "engineering", level = 2 } },
})
-- More hull, and less room in the hold for the bracing.
table.insert(modules, {
  id = "hull.bulkhead", name = "Reinforced Bulkheads", slot = "low", hardpoint = "",
  cpu = 10, powergrid = 1, volume = 5, basePrice = 10000,
  passive = { ship("hull", "mul", 1.25, true), ship("cargo", "mul", 0.9) },
  requires = { { skill = "hull.upgrades", level = 1 } },
})
-- An armour hardener that learns: it shifts its resistance toward what
-- the ship is being hit with.
table.insert(modules, {
  id = "armor.hardener.adaptive", name = "Adaptive Armor Hardener", short = "Adaptive", slot = "low", hardpoint = "",
  cpu = 25, powergrid = 1, volume = 5, basePrice = 30000, passive = {},
  boost = {}, boostDuration = 10, boostCapacitor = 10,
  adaptive = { total = 0.6, step = 0.06 },
  requires = { { skill = "hull.upgrades", level = 3 } },
})
-- ---------------------------------------------------------------------
-- Module expansion, the second group: combat support (2026-11-16; the
-- figures mine).

-- What the drones do: hit harder, and track and reach further.
table.insert(modules, {
  id = "drone.amplifier", name = "Drone Damage Amplifier", short = "Drone Amp", slot = "low", hardpoint = "",
  cpu = 20, powergrid = 1, volume = 5, basePrice = 20000, passive = {}, drones = { damage = 1.12 },
  requires = { { skill = "drones", level = 2 } },
})
table.insert(modules, {
  id = "drone.tracking", name = "Omnidirectional Tracking Link", short = "Drone Link", slot = "mid", hardpoint = "",
  cpu = 25, powergrid = 1, volume = 5, basePrice = 18000, passive = {}, drones = { tracking = 1.25 },
  requires = { { skill = "drones", level = 2 } },
})
-- (and since 2026-11-20, of the reference review: drones that fly faster,
-- and a low-slot tracking link. Their figures are mine.)
table.insert(modules, {
  id = "drone.navigation", name = "Drone Navigation Computer", short = "Drone Nav", slot = "mid", hardpoint = "",
  cpu = 25, powergrid = 1, volume = 5, basePrice = 22000, passive = {}, drones = { speed = 1.20 },
  requires = { { skill = "drones", level = 2 } },
})
table.insert(modules, {
  id = "drone.enhancer", name = "Drone Tracking Enhancer", short = "Drone Track", slot = "low", hardpoint = "",
  cpu = 24, powergrid = 1, volume = 5, basePrice = 20000, passive = {}, drones = { tracking = 1.10 },
  requires = { { skill = "drones", level = 2 } },
})
-- Electronic warfare against weapons: turrets track and reach worse, and
-- missiles fly shorter with wider blasts.
table.insert(modules, {
  id = "ewar.tracking", name = "Tracking Disruptor", slot = "mid", hardpoint = "",
  cpu = 25, powergrid = 1, volume = 5, basePrice = 30000, passive = {},
  hex = { kind = "track", range = 30000, strength = 0.7, duration = 5, capacitor = 15 },
  requires = { { skill = "electronic.warfare", level = 2 } },
})
table.insert(modules, {
  id = "ewar.guidance", name = "Guidance Disruptor", slot = "mid", hardpoint = "",
  cpu = 25, powergrid = 1, volume = 5, basePrice = 30000, passive = {},
  hex = { kind = "guide", range = 30000, strength = 0.7, duration = 5, capacitor = 15 },
  requires = { { skill = "electronic.warfare", level = 2 } },
})
-- Seeing further and locking quicker: the ship's own, and a friend's.
table.insert(modules, {
  id = "sensor.booster", name = "Sensor Booster", slot = "mid", hardpoint = "",
  cpu = 20, powergrid = 1, volume = 5, basePrice = 16000, passive = {},
  boost = { ship("lockRange", "mul", 1.3, true), ship("scanResolution", "mul", 1.3, true) }, boostDuration = 10, boostCapacitor = 5,
  requires = { { skill = "electronics", level = 1 } },
})
table.insert(modules, {
  id = "remote.sensor", name = "Remote Sensor Booster", slot = "mid", hardpoint = "",
  cpu = 22, powergrid = 1, volume = 5, basePrice = 20000, passive = {},
  hex = { kind = "sensor", range = 30000, strength = 1.3, duration = 10, capacitor = 10 },
  requires = { { skill = "electronics", level = 2 } },
})
-- By size: energy drains (capacitor taken from the target into the ship,
-- while the target has the fuller capacitor) and smartbombs of each kind.
for _, each in { { "small", "Small", 1 }, { "medium", "Medium", 2 }, { "large", "Large", 3 } } :: { { any } } do
  local name, title, size = each[1] :: string, each[2] :: string, each[3] :: number
  local cpuBy, gridBy, priceBy = ({ 1, 1.6, 2.4 })[size], ({ 1, 15, 180 })[size], ({ 1, 8, 60 })[size]
  table.insert(modules, {
    id = `drain.{name}`, name = `{title} Energy Nosferatu`, short = "Nosferatu", slot = "high", hardpoint = "",
    cpu = math.floor(15 * cpuBy + 0.5), powergrid = math.floor(8 * gridBy + 0.5), volume = 5 * size, basePrice = 30000 * priceBy,
    passive = {}, hex = { kind = "nos", range = ({ 7500, 10000, 15000 })[size], strength = ({ 20, 60, 180 })[size], duration = 12, capacitor = 0 },
    requires = { { skill = "electronic.warfare", level = size } },
  })
  for kind, label in { "EM", "Thermal", "Kinetic", "Explosive" } do
    local damage = { 0, 0, 0, 0 }
    damage[kind] = ({ 60, 180, 500 })[size]
    table.insert(modules, {
      id = `smartbomb.{string.lower(label)}.{name}`, name = `{title} {label} Smartbomb`, short = "Smartbomb", slot = "high", hardpoint = "",
      cpu = math.floor(25 * cpuBy + 0.5), powergrid = math.floor(20 * gridBy + 0.5), volume = 5 * size, basePrice = 25000 * priceBy,
      passive = {}, smartbomb = { range = ({ 5000, 6000, 7500 })[size], damage = damage, duration = 10, capacitor = ({ 50, 150, 450 })[size] },
      requires = { { skill = "weapon.upgrades", level = size + 1 } },
    })
  end
end

-- ---------------------------------------------------------------------
-- Module expansion, the third group: utility and industry (2026-11-16;
-- the figures mine).

-- A micro jump drive: after a spool, the ship is thrown so far ahead
-- along the way it is going, and its locks are broken.
table.insert(modules, {
  id = "jump.micro", name = "Micro Jump Drive", short = "MJD", slot = "mid", hardpoint = "",
  cpu = 30, powergrid = 20, volume = 10, basePrice = 600000, passive = {},
  jump = { distance = 100000, spool = 12 },
  requires = { { skill = "navigation", level = 4 } },
})
-- A warp stabilizer: one point against warp disruption, for so much
-- worse targeting.
table.insert(modules, {
  id = "warp.stabilizer", name = "Warp Core Stabilizer", short = "Stabilizer", slot = "low", hardpoint = "",
  cpu = 20, powergrid = 1, volume = 5, basePrice = 15000, stabilizer = 1,
  passive = { ship("lockRange", "mul", 0.7, true), ship("scanResolution", "mul", 0.7, true) },
  requires = { { skill = "navigation", level = 1 } },
})
-- A tractor beam: pulls a wreck or a can to the ship.
table.insert(modules, {
  id = "tractor.beam", name = "Tractor Beam", short = "Tractor", slot = "high", hardpoint = "",
  cpu = 25, powergrid = 1, volume = 5, basePrice = 30000, passive = {},
  tractor = { range = 20000, speed = 500, duration = 5, capacitor = 5 },
  requires = { { skill = "salvaging", level = 1 } },
})
-- Scanners: what a ship has fitted, what is in its hold, and what the
-- rocks round about hold.
table.insert(modules, {
  id = "scanner.ship", name = "Ship Scanner", slot = "mid", hardpoint = "",
  cpu = 25, powergrid = 1, volume = 5, basePrice = 12000, passive = {},
  scanner = { kind = "ship", range = 30000, duration = 5, capacitor = 10 },
  requires = { { skill = "electronics", level = 1 } },
})
table.insert(modules, {
  id = "scanner.cargo", name = "Cargo Scanner", slot = "mid", hardpoint = "",
  cpu = 25, powergrid = 1, volume = 5, basePrice = 12000, passive = {},
  scanner = { kind = "cargo", range = 30000, duration = 5, capacitor = 10 },
  requires = { { skill = "electronics", level = 1 } },
})
table.insert(modules, {
  id = "scanner.survey", name = "Survey Scanner", slot = "mid", hardpoint = "",
  cpu = 20, powergrid = 1, volume = 5, basePrice = 10000, passive = {},
  scanner = { kind = "survey", range = 25000, duration = 5, capacitor = 5 },
  requires = { { skill = "mining", level = 1 } },
})
-- A probe launcher, and its tech 2 make (Tactical/Sites; the owner,
-- 2026-11-18: "Probe launcher module"). It puts out the scan probes in
-- the hold; the tech 2 one's read a quarter more. Easier to fit on a
-- hull built to explore (Attributes.Needs). (The figures are mine.)
table.insert(modules, {
  id = "scanner.probe", name = "Probe Launcher", short = "Probes", slot = "mid", hardpoint = "",
  cpu = 20, powergrid = 1, volume = 5, basePrice = 60000, passive = {}, probes = { strength = 1 },
  requires = { { skill = "astrometrics", level = 1 } },
})
table.insert(modules, {
  id = "scanner.probe.ii", name = "Probe Launcher II", short = "Probes II", slot = "mid", hardpoint = "",
  cpu = 24, powergrid = 1, volume = 5, basePrice = 480000, passive = {}, probes = { strength = 1.25 },
  tech = 2, base = "scanner.probe",
})
-- A relic analyzer: what opens a derelict's hold (a data analyzer opens
-- a listening post's vaults).
table.insert(modules, {
  id = "analyzer.relic", name = "Relic Analyzer", slot = "mid", hardpoint = "",
  cpu = 20, powergrid = 1, volume = 5, basePrice = 60000, passive = {},
  analyzer = { range = 5000, relic = true },
  requires = { { skill = "hacking", level = 1 } },
})
-- Ice harvesters: a block or so of ice a cycle off an ice field's chunks,
-- and nothing off anything else; the barge's, a dozen.
table.insert(modules, {
  id = "miner.ice", name = "Ice Harvester", short = "Ice Harv", slot = "high", hardpoint = "turret",
  cpu = 60, powergrid = 12, volume = 10, basePrice = 120000, passive = {},
  miner = { volume = 100, duration = 60, capacitor = 60, range = 10000, ice = true },
  requires = { { skill = "mining", level = 3 } },
})
table.insert(modules, {
  id = "miner.ice.strip", name = "Strip Ice Harvester", short = "Strip Ice", slot = "high", hardpoint = "turret",
  cpu = 80, powergrid = 45, volume = 25, basePrice = 900000, passive = {},
  miner = { volume = 600, duration = 120, capacitor = 180, range = 12000, ice = true },
  requires = { { skill = "mining", level = 4 } },
})
-- A mining upgrade: so much more off a rock with every laser.
table.insert(modules, {
  id = "mining.upgrade", name = "Mining Laser Upgrade", short = "Mining Upg", slot = "low", hardpoint = "",
  cpu = 35, powergrid = 1, volume = 5, basePrice = 20000, passive = {}, mining = 1.09,
  requires = { { skill = "mining", level = 2 } },
})
-- (a Burst Jammer, of the reference review: every ship not its owner's
-- within 10 km may have its locks broken, a cycle every 30 s, for the
-- reference's capacitor; the chance mine)
table.insert(modules, {
  id = "jammer.burst", name = "Burst Jammer", short = "Burst Jam", slot = "mid", hardpoint = "",
  cpu = 30, powergrid = 1, volume = 5, basePrice = 60000, passive = {},
  burstJam = { range = 10000, strength = 0.25, duration = 30, capacitor = 240 },
  requires = { { skill = "electronic.warfare", level = 3 } },
})
-- (a Scan Rangefinding Array, of the reference review: the probes it
-- launches the stronger; the figure mine)
table.insert(modules, {
  id = "scan.rangefinder", name = "Scan Rangefinding Array", short = "Scan Array", slot = "low", hardpoint = "",
  cpu = 30, powergrid = 1, volume = 5, basePrice = 30000, passive = {}, probing = 1.10,
  requires = { { skill = "astrometrics", level = 2 } },
})
-- (and for ice, which the mining upgrade does nothing for, since
-- 2026-11-20: the figure mine)
table.insert(modules, {
  id = "ice.upgrade", name = "Ice Harvester Upgrade", short = "Ice Upg", slot = "low", hardpoint = "",
  cpu = 35, powergrid = 1, volume = 5, basePrice = 25000, passive = {}, ice = 1.06,
  requires = { { skill = "mining", level = 3 } },
})
-- Modulated lasers: a little less off a rock by themselves, and much
-- more with the crystal cut for its ore (crystals below; never used up).
table.insert(modules, {
  id = "miner.modulated", name = "Modulated Mining Laser", short = "Mod Laser", slot = "high", hardpoint = "turret",
  cpu = 70, powergrid = 3, volume = 5, basePrice = 90000, passive = {},
  miner = { volume = 80, duration = 60, capacitor = 60, range = 10000 },
  takes = { family = "crystal", size = 0, clip = 0, reload = 5 },
  requires = { { skill = "mining", level = 3 } },
})
table.insert(modules, {
  id = "miner.strip.modulated", name = "Modulated Strip Miner", short = "Mod Strip", slot = "high", hardpoint = "turret",
  cpu = 90, powergrid = 45, volume = 25, basePrice = 1200000, passive = {},
  miner = { volume = 640, duration = 120, capacitor = 180, range = 12000 },
  takes = { family = "crystal", size = 0, clip = 0, reload = 5 },
  requires = { { skill = "mining", level = 4 } },
})

-- ---------------------------------------------------------------------
-- Module expansion, the fourth group: fleet and capital (2026-11-16; the
-- figures mine).

-- Command bursts: while one runs, what it boosts is boosted on every ship
-- of its owner's within its range, its own ship too (the strongest of a
-- kind counts, not several: Tactical/Combat).
local function burst(id: string, name: string, boost: { Modifier }, mining: number?)
  table.insert(modules, {
    id = id, name = name, short = "Burst", slot = "mid", hardpoint = "",
    cpu = 40, powergrid = 30, volume = 10, basePrice = 250000, passive = {},
    boost = boost, boostDuration = 30, boostCapacitor = 40,
    burst = { range = 15000, mining = mining },
    requires = { { skill = "leadership", level = 1 } },
  })
end
burst("burst.shield", "Shield Command Burst", resist("shield", 0.9))
burst("burst.armor", "Armor Command Burst", { ship("armor", "mul", 1.1, true) })
burst("burst.skirmish", "Skirmish Command Burst", { ship("maxVelocity", "mul", 1.1, true), ship("signature", "mul", 0.9, true) })
burst("burst.information", "Information Command Burst", { ship("lockRange", "mul", 1.2, true), ship("scanResolution", "mul", 1.2, true) })
burst("burst.mining", "Mining Command Burst", {}, 1.1)

-- What roots a capital to the spot for a minute at a time, burning so
-- much of what is refined from ice each cycle out of the hold.
local SIEGE: { Modifier } = {}
for _, family in { "laser", "projectile", "hybrid", "missile" } do
  table.insert(SIEGE, weapons(family, "damageMultiplier", 2))
end
table.insert(modules, {
  id = "siege.module", name = "Siege Module", short = "Siege", slot = "high", hardpoint = "",
  cpu = 60, powergrid = 1000, volume = 4000, basePrice = 40000000, passive = {}, capital = true,
  classes = { "dreadnought", "siegedreadnought" }, immobile = true,
  boost = SIEGE, boostDuration = 60, boostCapacitor = 0, burns = { type = "ice.salts", quantity = 150 },
  requires = { { skill = "dreadnoughts", level = 1 } },
})
table.insert(modules, {
  id = "triage.module", name = "Triage Module", short = "Triage", slot = "high", hardpoint = "",
  cpu = 60, powergrid = 1000, volume = 4000, basePrice = 30000000, passive = {}, capital = true,
  classes = { "carrier" }, immobile = true, triage = 2,
  boost = { ship("lockRange", "mul", 1.5, true), ship("scanResolution", "mul", 1.5, true) }, boostDuration = 60, boostCapacitor = 0,
  burns = { type = "ice.salts", quantity = 150 },
  requires = { { skill = "carriers", level = 1 } },
})
table.insert(modules, {
  id = "industrial.core", name = "Industrial Core", short = "Ind Core", slot = "high", hardpoint = "",
  cpu = 50, powergrid = 800, volume = 4000, basePrice = 25000000, passive = {}, capital = true,
  classes = { "capitalindustrial" }, immobile = true, core = true,
  boost = {}, boostDuration = 60, boostCapacitor = 0, burns = { type = "ice.heavywater", quantity = 250 },
  requires = { { skill = "capital.industrials", level = 1 } },
})
-- A launcher that drops a field where the ship is, which keeps everybody
-- but its owner's ships in it from warping off for two minutes: a
-- destroyer's, one charge a field.
table.insert(modules, {
  id = "bubble.launcher", name = "Interdiction Field Launcher", short = "Bubble", slot = "high", hardpoint = "",
  cpu = 50, powergrid = 15, volume = 10, basePrice = 2500000, passive = {}, classes = { "destroyer" },
  bubble = { radius = 20000, lasts = 120 },
  takes = { family = "bubble", size = 0, clip = 1, reload = 15 },
  requires = { { skill = "propulsion.jamming", level = 3 } },
})

-- By size: capacitor boosters (each cycle a charge's worth into the
-- capacitor), ancillary shield boosters (a charge in place of the
-- capacitor a cycle) and ancillary armour repairers (three times as much
-- a cycle while there is paste).
local ANCILLARY_SIZES: { { any } } = { { "small", "Small", 1 }, { "medium", "Medium", 2 }, { "large", "Large", 3 } }
for _, each in ANCILLARY_SIZES do
  local name, title, size = each[1] :: string, each[2] :: string, each[3] :: number
  local cpuBy, gridBy, priceBy = ({ 1, 1.6, 2.4 })[size], ({ 1, 15, 180 })[size], ({ 1, 8, 60 })[size]
  local amountBy, cycleBy, capBy = ({ 1, 3.2, 9 })[size], ({ 1, 1.5, 2.25 })[size], ({ 1, 3, 8.5 })[size]
  table.insert(modules, {
    id = `capacitor.booster.{name}`, name = `{title} Capacitor Booster`, short = "Cap Booster", slot = "mid", hardpoint = "",
    cpu = math.floor(20 * cpuBy + 0.5), powergrid = math.floor(10 * gridBy + 0.5), volume = 5 * size, basePrice = 15000 * priceBy,
    passive = {}, takes = { family = "booster", size = size, clip = 3, reload = 10 }, injector = { duration = 10 * cycleBy },
    requires = { { skill = "engineering", level = size + 1 } },
  })
  table.insert(modules, {
    id = `shield.booster.ancillary.{name}`, name = `{title} Ancillary Shield Booster`, short = "Ancillary", slot = "mid", hardpoint = "",
    cpu = math.floor(30 * cpuBy + 0.5), powergrid = math.floor(4 * gridBy + 0.5), volume = 5 * size, basePrice = 20000 * priceBy,
    passive = {}, repair = { layer = "shield", amount = 40 * amountBy, duration = 3 * cycleBy, capacitor = 30 * capBy },
    takes = { family = "booster", size = size, clip = 9, reload = 60 }, ancillary = { factor = 1 },
    requires = { { skill = "shield.operation", level = size + 1 } },
  })
  table.insert(modules, {
    id = `armor.repairer.ancillary.{name}`, name = `{title} Ancillary Armor Repairer`, short = "Ancillary", slot = "low", hardpoint = "",
    cpu = math.floor(10 * cpuBy + 0.5), powergrid = math.floor(7 * gridBy + 0.5), volume = 5 * size, basePrice = 20000 * priceBy,
    passive = {}, repair = { layer = "armor", amount = 60 * amountBy, duration = 6 * cycleBy, capacitor = 40 * capBy },
    takes = { family = "paste", size = 0, clip = 8, reload = 60 }, ancillary = { factor = 3 },
    requires = { { skill = "repair.systems", level = size + 1 } },
  })
end

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

-- What a weapon fires does one kind of damage (the project owner's
-- ruling, 2026-11-14): a projectile round, a hybrid charge and a missile
-- come in all four kinds (EM, thermal, kinetic, explosive), and each
-- kind in three reaches: a short one that hits hardest, a standard one,
-- and a long one that hits least. Twelve of each, a size. (A laser's
-- crystals are EM and thermal only, and are as they were: three, by
-- reach.) A round is named for its kind and its reach.
--
-- The kinds, in the order damage is always given in; and for each
-- family, what a round of each kind is called and what one of each
-- reach is, with the damage a small one does at each reach.
local KINDS = { "em", "thermal", "kinetic", "explosive" }
local REACHES = { { id = "short", range = 0.5 }, { id = "standard", range = 1.0 }, { id = "long", range = 1.6 } }
type Rounds = { family: string, id: string, kinds: { string }, forms: { string }, damage: { number },
  -- (the three there were before there were twelve keep the ids they had: kind and reach, and the id)
  kept: { { any } } }
local ROUNDS: { Rounds } = {
  { family = "projectile", id = "ammo", kinds = { "Shock", "Incendiary", "Penetrator", "Burst" }, forms = { "Canister", "Rounds", "Sabot" },
    damage = { 12, 8, 6 }, kept = { { 1, 1, "ammo.emp" }, { 4, 1, "ammo.fusion" }, { 3, 2, "ammo.sabot" } } },
  { family = "hybrid", id = "charge", kinds = { "Ion", "Plasma", "Iron", "Blast" }, forms = { "Charge", "Slug", "Needle" },
    damage = { 11, 9, 7 }, kept = { { 2, 1, "charge.plasma" }, { 3, 2, "charge.slug" }, { 3, 3, "charge.needle" } } },
}

-- The id of a family's round of a kind and a reach.
local function roundId(rounds: Rounds, kind: number, reach: number): string
  for _, kept in rounds.kept do
    if kept[1] == kind and kept[2] == reach then
      return kept[3]
    end
  end
  return `{rounds.id}.{KINDS[kind]}.{REACHES[reach].id}`
end

local charges: { ChargeType } = {
  -- Crystals are not used up.
  turretCharge("crystal.multifrequency", "Wide-band Crystal", "laser", { 7, 5, 0, 0 }, 0.5),
  turretCharge("crystal.standard", "Standard Crystal", "laser", { 5, 3, 0, 0 }, 1.0),
  turretCharge("crystal.radio", "Long-wave Crystal", "laser", { 5, 0, 0, 0 }, 1.6),
}
-- (projectile rounds first, as they always were; the hybrids' come
-- after the missiles, below, as theirs did)
local function addRounds(rounds: Rounds)
  for kind = 1, 4 do
    for reach = 1, 3 do
      local damage = { 0, 0, 0, 0 }
      damage[kind] = rounds.damage[reach]
      table.insert(charges, turretCharge(roundId(rounds, kind, reach), `{rounds.kinds[kind]} {rounds.forms[reach]}`, rounds.family, damage,
        REACHES[reach].range))
    end
  end
end
addRounds(ROUNDS[1])

-- A missile of a kind comes in three reaches too: the missile itself, a
-- rocket (half the flight, three tenths more in the warhead) and a
-- javelin (six tenths more flight, a quarter less in the warhead).
-- (the missile itself first: it is what a launcher is loaded with where nobody says)
local MISSILE_REACH = { { id = "", form = "Missile", damage = 1, flight = 1 }, { id = ".short", form = "Rocket", damage = 1.3, flight = 0.5 },
  { id = ".long", form = "Javelin", damage = 0.75, flight = 1.6 } }
for _, kind in { { "kinetic", "Lance", 3 }, { "explosive", "Breaker", 4 }, { "thermal", "Ember", 2 } } :: { { any } } do
  for _, reach in MISSILE_REACH do
    local damage = { 0, 0, 0, 0 }
    damage[kind[3]] = 83 * reach.damage
    local made = missile(`missile.light.{kind[1]}{reach.id}`, `{kind[2]} Light {reach.form}`, damage)
    made.flightTime *= reach.flight
    table.insert(charges, made)
  end
end

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

-- The Kethri's vertical launch (their Vertical Launch Battery and its
-- missiles, below): how much further than the long launcher of its size
-- it reaches, how much longer than the straight way its path is, the
-- least range (a part of its reach), the missiles a salvo, and the time
-- between one leaving its cell and the next (s).
local VERTICAL = { reach = 1.3, stretch = 1.3, closest = 0.1, count = 8, gap = 0.25 }
-- Charge damage, by size.
local SIZE_DAMAGE = { 1, 2, 4, 8 }

-- A gun of a size: what its rounds are multiplied by, the seconds
-- between shots, optimal range and falloff (m), tracking, capacitor a
-- shot, CPU and powergrid.
type Sized = { number }
type Form = {
  id: string, title: string, family: string, skill: string,
  clip: number, reload: number, price: number,
  -- (small, medium, large, XL)
  sizes: { Sized },
  -- (a beam that leaps, its reach by size; and whose people's make it is)
  leap: { reach: { number }, leaps: number, share: number }?,
  lineage: string?,
}

-- Each size of each gun is the reference's gun of that size and make
-- (the owner, 2026-11-18, against the reference figures they supplied):
-- a bigger gun reaches further and hits harder, and follows a crossing
-- target so much worse that a battleship's guns all but miss a frigate
-- and a dreadnought's never hit one.
local FORMS: { Form } = {
  { id = "laser.pulse", title = "Pulse Laser", family = "laser", skill = "lasers", clip = 0, reload = 1, price = 9000, sizes = {
    { 3, 3.5, 5250, 2500, 246, 4.44, 15, 10 }, { 3, 5.25, 10500, 5000, 26, 13.3, 33, 189 },
    { 3, 7.88, 21000, 10000, 3.38, 36, 50, 2500 }, { 7.65, 12, 42000, 20000, 0.0385, 240, 80, 125000 } } },
  { id = "laser.beam", title = "Beam Laser", family = "laser", skill = "lasers", clip = 0, reload = 1, price = 11000, sizes = {
    { 4.5, 5, 11000, 2500, 90, 9.03, 18, 12 }, { 3.75, 6, 22000, 8000, 9.5, 21.7, 35, 225 },
    { 3, 9, 40000, 16000, 1.53, 52, 55, 2925 }, { 6.38, 15, 100000, 42000, 0.0218, 520, 90, 152500 } } },
  { id = "autocannon", title = "Autocannon", family = "projectile", skill = "projectiles", clip = 120, reload = 10, price = 8000, sizes = {
    { 2.89, 3.75, 1000, 5160, 315, 0, 9, 4 }, { 2.89, 5.46, 2000, 10836, 33.8, 0, 24, 140 },
    { 2.69, 7.88, 4000, 20640, 4.32, 0, 39, 2000 }, { 4.12, 8, 25000, 28800, 0.0415, 0, 55, 100000 } } },
  { id = "artillery", title = "Artillery", family = "projectile", skill = "projectiles", clip = 20, reload = 10, price = 10000, sizes = {
    { 7.04, 10.7, 10000, 8750, 64, 0, 15, 10 }, { 7.97, 18, 20000, 17500, 6.69, 0, 30, 225 },
    { 10.7, 40.2, 40000, 35000, 0.9, 0, 45, 3250 }, { 10.3, 30, 94000, 90000, 0.0171, 0, 70, 125000 } } },
  { id = "blaster", title = "Blaster", family = "hybrid", skill = "hybrids", clip = 80, reload = 5, price = 9000, sizes = {
    { 3.67, 3.5, 1500, 2500, 380, 1.42, 16, 8 }, { 3.67, 5.25, 3000, 5000, 38.4, 4.25, 29, 179 },
    { 3.67, 7.88, 6000, 10000, 5.2, 12.7, 52, 1980 }, { 5.57, 10, 20000, 25000, 0.0437, 100, 105, 99000 } } },
  { id = "railgun", title = "Railgun", family = "hybrid", skill = "hybrids", clip = 80, reload = 5, price = 11000, sizes = {
    { 3.02, 4.25, 12000, 6000, 73.5, 2.34, 24, 9 }, { 3.48, 5.83, 21600, 10800, 5.9, 7, 38, 198 },
    { 3.02, 8.13, 43200, 21600, 1.05, 21, 67, 2200 }, { 7.43, 20, 120000, 32000, 0.0183, 300, 115, 110000 } } },
  -- The Vail's own (the owner, 2026-11-18: "alien-specific weapons, like
  -- lasers that *bounce* to other enemy ships within x range of the
  -- targeted ones"; fitted by any hull that can fit a laser): a pulse
  -- laser's reach and tracking for four fifths of its damage, that on a
  -- hit leaps on to another of the target's side near it, twice at most,
  -- each leap half the hit before it. A weapon for a pack. (The name and
  -- every figure are mine; "your's fit well".)
  { id = "laser.litany", title = "Litany Beam", family = "laser", skill = "lasers", clip = 0, reload = 1, price = 30000, sizes = {
    { 2.4, 3.5, 5250, 2500, 246, 4.44, 15, 10 }, { 2.4, 5.25, 10500, 5000, 26, 13.3, 33, 189 },
    { 2.4, 7.88, 21000, 10000, 3.38, 36, 50, 2500 }, { 6.12, 12, 42000, 20000, 0.0385, 240, 80, 125000 } },
    leap = { reach = { 5000, 7500, 10000, 15000 }, leaps = 2, share = 0.5 }, lineage = "vail" },
}

-- What a weapon of each size costs, how big it is packed, and the skill
-- it wants beside its family's.
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
    local f = form.sizes[size]
    if not known[id] then
      table.insert(modules, {
        id = id, name = `{SIZE_TITLE[size]} {form.title}`, slot = "high", hardpoint = "turret",
        cpu = f[7], powergrid = f[8],
        volume = SIZE_VOLUME[size], basePrice = form.price * SIZE_PRICE[size], passive = {},
        weapon = { family = form.family, duration = f[2], capacitor = f[6], damageMultiplier = f[1],
          optimal = f[3], falloff = f[4], tracking = f[5], clip = form.clip, reload = form.reload, size = size,
          leap = if form.leap then { reach = form.leap.reach[size], leaps = form.leap.leaps, share = form.leap.share } else nil },
        requires = needs(form.skill, size), lineage = form.lineage,
      })
    end
  end
end

local LAUNCHERS = {
  { id = "launcher.heavy", name = "Heavy Missile Launcher", cpu = 50, powergrid = 100, price = 110000, duration = 15, clip = 30,
    reload = 35 },
  { id = "launcher.cruise", name = "Cruise Missile Launcher", cpu = 60, powergrid = 1450, price = 1100000, duration = 20.7, clip = 24,
    reload = 40 },
  { id = "launcher.siege", name = "Siege Missile Launcher", cpu = 150, powergrid = 100000, price = 16000000, duration = 171, clip = 16,
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

-- Rapid launchers (the reference review, 2026-11-20): a launcher for a
-- medium hardpoint that throws light missiles, and one for a large that
-- throws heavy ones, more than twice as often as the plain launcher of
-- their missiles, from a smaller load that takes long to reload. Their
-- figures are the reference's (cycle, load, reload, fitting; prices mine).
for _, rapid in {
  { id = "launcher.rapid.light", name = "Rapid Light Missile Launcher", size = 1, mount = 2, duration = 7.8, clip = 19, reload = 35,
    cpu = 35, powergrid = 73, price = 40000 },
  { id = "launcher.rapid.heavy", name = "Rapid Heavy Missile Launcher", size = 2, mount = 3, duration = 6.48, clip = 24, reload = 35,
    cpu = 50, powergrid = 960, price = 300000 },
} do
  table.insert(modules, {
    id = rapid.id, name = rapid.name, slot = "high", hardpoint = "launcher",
    cpu = rapid.cpu, powergrid = rapid.powergrid, volume = SIZE_VOLUME[rapid.mount], basePrice = rapid.price, passive = {},
    weapon = { family = "missile", duration = rapid.duration, capacitor = 0, damageMultiplier = 1.0,
      optimal = 0, falloff = 0, tracking = 0, clip = rapid.clip, reload = rapid.reload, size = rapid.size, mount = rapid.mount },
    requires = needs("missiles", rapid.mount),
  })
end

-- And the short-range launcher of each size (the project owner's,
-- 2026-11-14: a long and a short make of every weapon at every size, as
-- turrets have; the names are first ones). It takes the missiles its
-- size of launcher takes, and throws them a third as far: what a blaster
-- is to a railgun. How often it fires, how hard what it throws hits, and
-- what it takes to fit are the reference's short launcher of that size
-- beside its long one (2026-11-18): the small one fires quickly and
-- lightly, the biggest slowly and harder. It holds half as many again.
local CLOSE = { flight = 0.35, price = 0.9, clip = 1.5 }
local SHORT_LAUNCHERS = {
  { id = "launcher.rocket", name = "Rocket Launcher", long = "launcher.light", duration = 5, damage = 0.4, cpu = 15, powergrid = 4 },
  { id = "launcher.assault", name = "Assault Launcher", long = "launcher.heavy", duration = 8, damage = 0.67, cpu = 45, powergrid = 108 },
  { id = "launcher.torpedo", name = "Torpedo Launcher", long = "launcher.cruise", duration = 18, damage = 1.2, cpu = 74, powergrid = 1630 },
  { id = "launcher.bombard", name = "Bombardment Launcher", long = "launcher.siege", duration = 128, damage = 1.24, cpu = 150,
    powergrid = 100000 },
}
for size, short in SHORT_LAUNCHERS do
  local long: ModuleType? = nil
  for _, module in modules do
    if module.id == short.long then
      long = module
    end
  end
  local base = (assert(long, short.long).weapon) :: Weapon
  table.insert(modules, {
    id = short.id, name = short.name, slot = "high", hardpoint = "launcher",
    cpu = short.cpu, powergrid = short.powergrid,
    volume = SIZE_VOLUME[size], basePrice = (long :: ModuleType).basePrice * CLOSE.price, passive = {},
    weapon = { family = "missile", duration = short.duration, capacitor = 0, damageMultiplier = short.damage,
      optimal = 0, falloff = 0, tracking = 0, clip = math.floor(base.clip * CLOSE.clip), reload = base.reload, size = size,
      flight = CLOSE.flight },
    requires = needs("missiles", size),
  })
end

-- The Vessari's own launcher, of every size (the owner, 2026-11-18:
-- "Gundam/Macross-style missiles", the volley "just [at] your active
-- target", and "short-range"): a missile of its size broken into a swarm
-- of small ones, 6, 12, 18 and 24 a cycle, that between them do nine
-- tenths of what the one would have, each with half its blast (the
-- better on a small ship). It is the short-range launcher of its size
-- (rocket, assault, torpedo, bombardment) in fitting, cycle and reach:
-- its missiles fly a third as fast again, for so much the shorter a
-- time. Fitted by any hull that can fit a launcher; scarce, as the
-- Vessari's gear is. (The name and every figure mine but the counts and
-- the short reach.)
local SWARM_SPEED = 1.3
for size, short in { "launcher.rocket", "launcher.assault", "launcher.torpedo", "launcher.bombard" } do
  local made: ModuleType? = nil
  for _, module in modules do
    if module.id == short then
      made = module
    end
  end
  local base = assert(made, short)
  local weapon = assert(base.weapon)
  table.insert(modules, {
    id = `launcher.swarm.{SIZE_NAME[size]}`, name = `{SIZE_TITLE[size]} Swarm Launcher`, short = "Swarm", slot = "high", hardpoint = "launcher",
    cpu = base.cpu, powergrid = base.powergrid, volume = SIZE_VOLUME[size], basePrice = base.basePrice * 3, passive = {},
    weapon = { family = "missile", duration = weapon.duration, capacitor = 0, damageMultiplier = weapon.damageMultiplier,
      optimal = 0, falloff = 0, tracking = 0, clip = weapon.clip, reload = weapon.reload, size = size,
      flight = (weapon.flight or 1) / SWARM_SPEED, blast = 0.5,
      volley = { count = ({ 6, 12, 18, 24 })[size], share = 0.9, speed = SWARM_SPEED, gap = 0.03, path = "zig" } },
    requires = needs("missiles", size), lineage = "vessari",
  })
end

-- The Kethri's own launcher, of every size (the owner, 2026-11-19): a
-- Vertical Launch Battery, a row of cells two by four that ripples its
-- eight missiles out, four along one row and four back along the other,
-- each an eighth of the one it is loaded with. They go straight up out
-- of their cells, over a third of the way to the target, and down on
-- it; it reaches 1.3 times as far as the long launcher of its size, and
-- will not fire at what is nearer than a tenth of that (Tactical/Combat).
-- It takes only vertical-launch missiles. Fitted as the long launcher of
-- its size is, by any hull that can fit a launcher, if a fifth dearer
-- in CPU and powergrid; scarce, as the Kethri's gear is. (The name,
-- reach, least range, salvo and turn the owner's; the rest mine.)
for size, long in { "launcher.light", "launcher.heavy", "launcher.cruise", "launcher.siege" } do
  local made: ModuleType? = nil
  for _, module in modules do
    if module.id == long then
      made = module
    end
  end
  local base = assert(made, long)
  local weapon = assert(base.weapon)
  local v = VERTICAL
  table.insert(modules, {
    id = `launcher.vertical.{SIZE_NAME[size]}`, name = `{SIZE_TITLE[size]} Vertical Launch Battery`, short = "VLB", slot = "high",
    hardpoint = "launcher", cpu = base.cpu * 1.2, powergrid = base.powergrid * 1.2, volume = SIZE_VOLUME[size],
    basePrice = base.basePrice * 3, passive = {},
    weapon = { family = "missile", duration = weapon.duration, capacitor = 0, damageMultiplier = weapon.damageMultiplier,
      optimal = 0, falloff = 0, tracking = 0, clip = weapon.clip, reload = weapon.reload, size = size, flight = weapon.flight,
      line = "vertical",
      volley = { count = v.count, share = 1, speed = 1, gap = v.gap, path = "arc", stretch = v.stretch, closest = v.closest } },
    requires = needs("missiles", size), lineage = "kethri",
  })
end

-- Point defence (the owner's rulings, 2026-11-19): a small projectile
-- turret in a turret hardpoint that, switched on, shoots streams of
-- tracers at the enemy's missiles within its reach, and at their drones
-- when there are none, swinging to each in turn (Tactical/PointDefence).
-- It loads small projectile rounds, 120 at a time. (Every figure mine,
-- approved: ten rounds a second, 90 degrees a second, 5 km and 5 km.)
-- (the owner, 2026-11-19, of how it fares against a steady stream:
-- "mostly misses", one turret stopping about half of a lone launcher's
-- missiles, so that what is fired one at a time is cut and not stopped)
local PDS_REACH = { 2500, 2500 }
local PDS_ACCURACY = 0.08
table.insert(modules, {
  id = "pds.small", name = "Point Defence Turret", short = "PDS", slot = "high", hardpoint = "turret",
  cpu = 12, powergrid = 6, volume = 5, basePrice = 20000, passive = {},
  takes = { family = "projectile", size = 1, clip = 120, reload = 6 },
  pds = { rate = 10, traverse = math.rad(90), tracking = 3000, optimal = PDS_REACH[1], falloff = PDS_REACH[2], damage = 0.1,
    accuracy = PDS_ACCURACY },
  requires = needs("projectiles", 1),
})

-- The Nimia's own launcher, of every size (the owner, 2026-11-19): the
-- Plasma Torpedo Launcher. It fires a ball of plasma that point defence
-- cannot shoot down, slowly, every second cycle of the short-range
-- launcher of its size with twice its hit, so as hard a second; it fits
-- as that launcher does, if a fifth dearer in CPU and powergrid, and
-- takes only plasma torpedoes. Fitted by any hull that can fit a
-- launcher; scarce, as the Nimia's gear is. (The name and the torpedoes
-- the owner's; the rest mine.)
for size, short in { "launcher.rocket", "launcher.assault", "launcher.torpedo", "launcher.bombard" } do
  local made: ModuleType? = nil
  for _, module in modules do
    if module.id == short then
      made = module
    end
  end
  local base = assert(made, short)
  local weapon = assert(base.weapon)
  table.insert(modules, {
    id = `launcher.plasma.{SIZE_NAME[size]}`, name = `{SIZE_TITLE[size]} Plasma Torpedo Launcher`, short = "Plasma", slot = "high",
    hardpoint = "launcher", cpu = base.cpu * 1.2, powergrid = base.powergrid * 1.2, volume = SIZE_VOLUME[size],
    basePrice = base.basePrice * 3, passive = {},
    weapon = { family = "missile", duration = weapon.duration * 2, capacitor = 0, damageMultiplier = weapon.damageMultiplier * 2,
      optimal = 0, falloff = 0, tracking = 0, clip = weapon.clip, reload = weapon.reload, size = size, flight = 1,
      line = "plasma", path = "plasma" },
    requires = needs("missiles", size), lineage = "nimia",
  })
end

-- The Drowned's Fighter Pylon (the owner, 2026-11-19: "a hull-mounted
-- Fighter (think how mini-subs attach to a full sized submarine)"): it
-- takes a turret hardpoint and a great deal of CPU, holds 75 Mbit/s of
-- the hull's drone bandwidth, and wants Drones 5. It carries one Trident
-- on the hull, which goes out when it is switched on, to the target, and
-- comes back to it when it is switched off; the Trident counts as one
-- of the drones the ship has out. One that is destroyed is replaced only
-- in a station. (The name, the hardpoint, the bandwidth and the skill the
-- owner's; the CPU, powergrid and price mine.)
table.insert(modules, {
  id = "pylon.fighter", name = "Fighter Pylon", short = "Pylon", slot = "high", hardpoint = "turret",
  cpu = 150, powergrid = 60, volume = 50, basePrice = 4000000, passive = {},
  takes = { family = "pylon", size = 0, clip = 1, reload = 0 },
  pylon = { drone = "drone.trident", bandwidth = 75 },
  requires = { { skill = "drones", level = 5 } }, lineage = "drowned",
})

-- Hardeners against one kind of damage (the project owner's, 2026-11-14:
-- "type-specific hardeners"): switched on, a shield's lets half as much
-- of its kind through, and an armour's likewise, where the plain Shield
-- Hardener and the Reactive Membrane take a quarter and a seventh off
-- every kind. So a ship can be made ready for who it is going to meet.
local HARDENED = 0.5
for kind, word in { "EM", "Thermal", "Kinetic", "Explosive" } do
  table.insert(modules, {
    id = `shield.hardener.{KINDS[kind]}`, name = `{word} Shield Hardener`, slot = "mid", hardpoint = "",
    cpu = 26, powergrid = 1, volume = 5, basePrice = 18000, passive = {},
    boost = { ship(`shieldResonance.{kind}`, "mul", HARDENED, true) }, boostDuration = 10, boostCapacitor = 10,
  })
  table.insert(modules, {
    id = `armor.hardener.{KINDS[kind]}`, name = `{word} Armor Hardener`, slot = "low", hardpoint = "",
    cpu = 24, powergrid = 1, volume = 5, basePrice = 18000, passive = {},
    boost = { ship(`armorResonance.{kind}`, "mul", HARDENED, true) }, boostDuration = 10, boostCapacitor = 8,
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
-- ('lineage': a rig that is a people's own make, as a module can be.)
local function rig(id: string, name: string, calibration: number, passive: { Modifier }, lineage: string?)
  for _, size in RIG_SIZES do
    table.insert(modules, {
      id = "rig." .. id .. size[1], name = size[2] .. name, slot = "rig", hardpoint = "", cpu = 0, powergrid = 0,
      volume = 5 * size[3], basePrice = 24000 * size[3],
      calibration = calibration, passive = passive, requires = { { skill = "jury.rigging", level = 1 } },
      lineage = lineage,
    })
  end
end
-- How many times a small rig's salvage a rig of each size takes.
local RIG_WORK = { 1, 3, 9 }
rig("shield", "Field Extender Rig", 150, { ship("shield", "mul", 1.15, true), ship("signature", "mul", 1.10) })
rig("regen", "Field Regeneration Rig", 150, { ship("shieldRecharge", "mul", 0.8, true), ship("signature", "mul", 1.10) })
rig("armor", "Armour Pump Rig", 150, { ship("armor", "mul", 1.15, true), ship("maxVelocity", "mul", 0.90) })
rig("hull", "Bulkhead Rig", 100, { ship("hull", "mul", 1.20, true), ship("cargo", "mul", 0.90) })
-- (and since 2026-11-20 of the reference review: a rig for salvaging and
-- one for probing, with no cost to the ship; the figures mine)
rig("salvage", "Salvage Tackle Rig", 100, {})
rig("probing", "Gravity Capacitor Rig", 100, {})
for _, m in modules do
  if string.sub(m.id, 1, 11) == "rig.salvage" then
    m.salvage = 0.10
  elseif string.sub(m.id, 1, 11) == "rig.probing" then
    m.probing = 1.10
  end
end
rig("engine", "Engine Tuning Rig", 100, { ship("maxVelocity", "mul", 1.10, true), ship("armor", "mul", 0.90) })
rig("cargo", "Cargo Bracing Rig", 100, { ship("cargo", "mul", 1.15, true), ship("armor", "mul", 0.90) })
rig("capacitor", "Capacitor Flux Rig", 100, { ship("capacitorRecharge", "mul", 0.85, true), ship("shield", "mul", 0.90) })
rig("projectile", "Projectile Burst Rig", 200, { weapons("projectile", "duration", 0.90), ship("powergrid", "mul", 0.90) })
rig("laser", "Energy Burst Rig", 200, { weapons("laser", "duration", 0.90), ship("powergrid", "mul", 0.90) })
rig("hybrid", "Hybrid Burst Rig", 200, { weapons("hybrid", "duration", 0.90), ship("powergrid", "mul", 0.90) })
-- The Nimia's own (the project owner's: "Faction-specific shipmods,
-- modules (low slots), and skills that increase repair rate"): worked
-- into a hull that mends by itself, one has its armour mend three
-- tenths faster and is the slower for the weight of it, the other its
-- hull and has less room in the hold. In a hull that does not mend
-- they do nothing but cost it that. (The figures are first ones.)
rig("mend.armor", "Living Armour Rig", 150, { ship("armorMend", "mul", 1.30, true), ship("maxVelocity", "mul", 0.95) }, "nimia")
rig("mend.hull", "Living Hull Rig", 150, { ship("hullMend", "mul", 1.30, true), ship("cargo", "mul", 0.90) }, "nimia")

-- What was missing of the modules and rigs against the reference (the
-- review of 2026-11-20; the owner, overnight: "check for missing ship
-- modules ... knock out the rest"), every figure the reference's tech 1
-- one, and the names mine:
--   - against one kind of damage, all the time: a shield amplifier (mid)
--     and an armour coating (low), and a rig of each for every kind
--     (each people deals one kind most: Data/Factions' affinity);
--   - for missiles, what turrets had: a low-slot enhancer of their
--     flight and their blast, and rigs of their blast, their speed,
--     their flight and the launchers' rate;
--   - for turrets, rigs of their reach, their tracking and their damage,
--     beside the rate rigs above;
--   - a medium and a heavy energy neutraliser beside the small.
for kind, word in { "EM", "Thermal", "Kinetic", "Explosive" } do
  table.insert(modules, {
    id = `shield.amplifier.{KINDS[kind]}`, name = `{word} Shield Amplifier`, slot = "mid", hardpoint = "",
    cpu = 25, powergrid = 1, volume = 5, basePrice = 15000, passive = { ship(`shieldResonance.{kind}`, "mul", 0.675, true) },
    requires = { { skill = "shield.operation", level = 2 } },
  })
  table.insert(modules, {
    id = `armor.coating.{KINDS[kind]}`, name = `{word} Armour Coating`, slot = "low", hardpoint = "",
    cpu = 12, powergrid = 1, volume = 5, basePrice = 15000, passive = { ship(`armorResonance.{kind}`, "mul", 0.76, true) },
    requires = { { skill = "hull.upgrades", level = 2 } },
  })
  rig(`shield.screen.{KINDS[kind]}`, `{word} Shield Screen Rig`, 150,
    { ship(`shieldResonance.{kind}`, "mul", 0.70, true), ship("signature", "mul", 1.10) })
  rig(`armor.screen.{KINDS[kind]}`, `{word} Armour Screen Rig`, 150,
    { ship(`armorResonance.{kind}`, "mul", 0.70, true), ship("maxVelocity", "mul", 0.90) })
end
table.insert(modules, {
  id = "missile.guidance", name = "Missile Guidance Enhancer", slot = "low", hardpoint = "",
  cpu = 10, powergrid = 1, volume = 5, basePrice = 20000,
  passive = { weapons("missile", "speed", 1.045), weapons("missile", "flight", 1.045), weapons("missile", "blast", 0.956) },
  requires = { { skill = "weapon.upgrades", level = 1 } },
})
rig("missile.blast", "Warhead Focus Rig", 150, { weapons("missile", "blast", 0.85), ship("powergrid", "mul", 0.90) })
rig("missile.speed", "Missile Thruster Rig", 150, { weapons("missile", "speed", 1.10), ship("powergrid", "mul", 0.90) })
rig("missile.flight", "Missile Endurance Rig", 150, { weapons("missile", "flight", 1.10), ship("powergrid", "mul", 0.90) })
rig("missile.rate", "Launcher Feed Rig", 200, { weapons("missile", "duration", 0.90), ship("powergrid", "mul", 0.90) })
rig("turret.optimal", "Turret Reach Rig", 150, { weapons("turret", "optimal", 1.15), ship("powergrid", "mul", 0.90) })
rig("turret.falloff", "Turret Spread Rig", 150, { weapons("turret", "falloff", 1.15), ship("powergrid", "mul", 0.90) })
rig("turret.tracking", "Turret Tracking Rig", 150, { weapons("turret", "tracking", 1.15), ship("powergrid", "mul", 0.90) })
rig("turret.damage", "Turret Charge Rig", 200, { weapons("turret", "damageMultiplier", 1.10), ship("powergrid", "mul", 0.90) })
-- (and amplifiers of what the ship's own repairers mend: the reference's
-- shield booster amplifier, 30%; and an armour one for the active armour
-- tankers, the same, mine)
table.insert(modules, {
  id = "amplifier.shield", name = "Shield Boost Amplifier", slot = "mid", hardpoint = "", cpu = 50, powergrid = 1, volume = 5,
  basePrice = 30000, passive = {}, amplify = { layer = "shield", by = 0.30 }, requires = { { skill = "shield.operation", level = 2 } },
})
table.insert(modules, {
  id = "amplifier.armor", name = "Armour Repair Amplifier", slot = "low", hardpoint = "", cpu = 30, powergrid = 1, volume = 5,
  basePrice = 30000, passive = {}, amplify = { layer = "armor", by = 0.30 }, requires = { { skill = "repair.systems", level = 2 } },
})
-- (a hull repairer: the reference's is weak, 25 a 30 s cycle for a small;
-- here as an armour repairer's amount over its cycle, the hull a ship's
-- last layer, mine. And a heavy web of short reach: the reference's
-- grappler, a fifth of the speed out to a kilometre)
table.insert(modules, {
  id = "hull.repairer.small", name = "Small Hull Repairer", slot = "low", hardpoint = "", cpu = 10, powergrid = 5, volume = 5,
  basePrice = 25000, passive = {}, repair = { layer = "hull", amount = 45, duration = 8, capacitor = 40 },
  requires = { { skill = "repair.systems", level = 1 } },
})
table.insert(modules, {
  id = "projector.grappler", name = "Gravitic Grappler", short = "Grappler", slot = "mid", hardpoint = "", cpu = 30, powergrid = 50,
  volume = 10, basePrice = 60000, passive = {},
  hex = { kind = "entangle", range = 1000, strength = 0.2, duration = 5, capacitor = 4 },
  requires = { { skill = "propulsion.jamming", level = 3 } },
})
-- (a Jump Portal Generator: the owner's, 2026-11-20, "only ultracaps and
-- black-ops *battleships+*": it holds a portal open for the friendly
-- ships near it to jump through, Tactical/Jumping. Black ops battleships
-- are to have it when there are any. The fitting figures are mine.)
table.insert(modules, {
  id = "jump.portal", name = "Jump Portal Generator", slot = "high", hardpoint = "", cpu = 100, powergrid = 50000, volume = 5000,
  basePrice = 900000000, passive = {}, portal = true, classes = { "ultracapital" }, capital = true,
  requires = { { skill = "jump.drives", level = 4 } },
})
-- (a Cipher Buffer: the owner's, 2026-11-20, a hacking helper of "+1
-- buffer slot", Tactical/Hacking; one counts, however many are fitted.
-- The fitting figures and the name are mine.)
table.insert(modules, {
  id = "hack.buffer", name = "Cipher Buffer", slot = "mid", hardpoint = "", cpu = 20, powergrid = 1, volume = 5,
  basePrice = 350000, passive = {}, hackBuffer = 1, requires = { { skill = "hacking", level = 2 } },
})
-- (a Drone Link Augmentor: drones worked 20 km farther from the ship, the
-- reference's, now that drones have a control range, Tactical/Drones)
table.insert(modules, {
  id = "drone.link", name = "Drone Link Augmentor", slot = "high", hardpoint = "", cpu = 27, powergrid = 53, volume = 25,
  basePrice = 40000, passive = {}, droneRange = 20000, requires = { { skill = "drones", level = 3 } },
})
-- (and the utility modules of the same review, for hauling, travel and
-- fitting: the reference's figures where it has one that means the same
-- here; the warp accelerator's, the coil's and the generator's mine)
for _, each in {
  { "inertial.damper", "Inertial Damper", "low", 18, 1, { ship("inertia", "mul", 0.8325, true), ship("signature", "mul", 1.10) },
    "navigation" },
  { "warp.accelerator", "Warp Field Accelerator", "low", 10, 1, { ship("warpSpeed", "mul", 1.10, true) }, "navigation" },
  { "targeting.amplifier", "Targeting Amplifier", "low", 20, 1,
    { ship("lockRange", "mul", 1.25, true), ship("scanResolution", "mul", 1.12, true), ship("maxTargets", "add", 1) }, "electronics" },
  { "signature.dampener", "Signature Dampener", "mid", 25, 1, { ship("signature", "mul", 0.90, true) }, "electronics" },
  { "capacitor.coil", "Capacitor Recharge Coil", "low", 20, 1, { ship("capacitorRecharge", "mul", 0.80, true), ship("capacitor", "mul", 0.90) },
    "engineering" },
  { "grid.diagnostic", "Grid Diagnostic Unit", "low", 20, 1,
    { ship("powergrid", "mul", 1.05, true), ship("capacitor", "mul", 1.04, true), ship("shield", "mul", 1.04, true),
      ship("capacitorRecharge", "mul", 0.96, true), ship("shieldRecharge", "mul", 0.96, true) }, "engineering" },
  { "auxiliary.generator", "Auxiliary Generator", "low", 30, 0, { ship("powergrid", "add", 10) }, "engineering" },
} :: { { any } } do
  table.insert(modules, {
    id = each[1], name = each[2], slot = each[3], hardpoint = "", cpu = each[4], powergrid = each[5], volume = 5, basePrice = 20000,
    passive = each[6], requires = { { skill = each[7], level = 1 } },
  })
end
for size, each in { { "medium", "Medium", 150, 12, 8000, 25, 175 }, { "heavy", "Heavy", 500, 24, 16000, 50, 2000 },
  { "xl", "Capital", 1500, 30, 30000, 120, 25000 } } :: { { any } } do
  table.insert(modules, {
    id = `neutraliser.{each[1]}`, name = `{each[2]} Energy Neutraliser`, slot = "high", hardpoint = "",
    cpu = each[6], powergrid = each[7], volume = 5 * (size + 1), basePrice = 35000 * (size + 1) ^ 2, passive = {},
    hex = { kind = "neut", range = each[5], strength = each[3], duration = each[4], capacitor = each[3] },
    requires = { { skill = "electronic.warfare", level = math.min(4, 2 + size) } }, capital = if size == 3 then true :: boolean? else nil,
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
  { "mwd.5mn", "mwd", "propulsion" },
  { "capacitor.battery.small", "capacitor.battery", "engineering" },
}
-- (and since 2026-11-20 an XL of each, for capitals only: the owner's
-- "Yes, XL sizes", the figures mine, about three times a large's and on a
-- longer cycle, as the reference's capital modules are to its large ones)
local FIT_AMOUNT = { 1, 3.2, 9, 30 }
local FIT_MASS = { 1, 10, 100, 1000 }
local FIT_CPU = { 1, 1.6, 2.4, 4 }
-- (a large one's since 2026-11-18 a little more, when a cruiser's
-- powergrid rose with its guns: still more than a cruiser has)
local FIT_POWERGRID = { 1, 15, 250, 2500 }
local FIT_PRICE = { 1, 8, 60, 400 }
local FIT_CYCLE = { 1, 1.5, 2.25, 3.4 }
local FIT_CAPACITOR = { 1, 3, 8.5, 28 }

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
  for size = 2, 4 do
    local repair = base.repair
    -- (one whose name says no size says XL in front, for a capital)
    local named, sized = string.gsub(base.name, "Small", SIZE_TITLE[size])
    table.insert(modules, {
      id = `{fitting[2]}.{SIZE_NAME[size]}`, name = if sized == 0 and size == 4 then `XL {base.name}` else named, capital = if size == 4 then true :: boolean? else nil,
      slot = base.slot, hardpoint = base.hardpoint,
      cpu = math.floor(base.cpu * FIT_CPU[size] + 0.5), powergrid = math.floor(base.powergrid * FIT_POWERGRID[size] + 0.5),
      volume = base.volume * (size * size - size), basePrice = base.basePrice * FIT_PRICE[size],
      passive = scaled(base.passive, size),
      repair = if repair then { layer = repair.layer, amount = repair.amount * FIT_AMOUNT[size],
        duration = repair.duration * FIT_CYCLE[size], capacitor = repair.capacitor * FIT_CAPACITOR[size] } else nil,
      boost = if base.boost then scaled(base.boost, size) else nil,
      boostDuration = base.boostDuration,
      boostCapacitor = if base.boostCapacitor then base.boostCapacitor * FIT_CAPACITOR[size] else nil,
      -- (an XL as much skill as a large: its tech 2 make the more)
      requires = { { skill = fitting[3], level = math.min(4, size + 1) } },
    })
  end
end

-- And the remote repairers by size, and the relays: more put back, or
-- sent, from farther off. (What a relay sends is what it costs, at
-- every size.)
local REMOTE_RANGE = { 1, 1.6, 2.5, 4 }
for _, base in table.clone(modules) do
  local hex = base.hex
  if hex and (hex.kind == "shield" or hex.kind == "armor" or hex.kind == "capacitor") and not base.internal then
    for size = 2, 4 do
      local cost = hex.capacitor * FIT_CAPACITOR[size]
      table.insert(modules, {
        id = (string.gsub(base.id, "small", SIZE_NAME[size])), name = (string.gsub(base.name, "Small", SIZE_TITLE[size])),
        slot = base.slot, hardpoint = base.hardpoint, capital = if size == 4 then true :: boolean? else nil,
        cpu = math.floor(base.cpu * FIT_CPU[size] + 0.5), powergrid = math.floor(base.powergrid * FIT_POWERGRID[size] + 0.5),
        volume = base.volume * (size * size - size), basePrice = base.basePrice * FIT_PRICE[size], passive = {},
        hex = { kind = hex.kind, range = hex.range * REMOTE_RANGE[size],
          strength = if hex.kind == "capacitor" then cost else hex.strength * FIT_AMOUNT[size],
          duration = hex.duration, capacitor = cost },
        requires = { { skill = if hex.kind == "capacitor" then "engineering" else "remote.repair", level = math.min(4, size + 1) } },
      })
    end
  end
end

-- What a mining barge carries.
table.insert(modules, {
  id = "miner.strip", name = "Strip Miner", slot = "high", hardpoint = "turret",
  cpu = 80, powergrid = 40, volume = 25, basePrice = 400000, passive = {},
  -- (800 a cycle since 2026-11-16, when income came up: it was 200. Mine.)
  miner = { volume = 800, duration = 120, capacitor = 180, range = 12000 },
  requires = { { skill = "mining", level = 4 } },
})

-- What draws the gas off a cloud (Data/Ores, Tactical/Sites): it works
-- from close by, and brings in half the room a mining laser cuts.
table.insert(modules, {
  id = "miner.gas", name = "Gas Harvester", short = "Harvester", slot = "high", hardpoint = "turret",
  cpu = 50, powergrid = 2, volume = 5, basePrice = 60000, passive = {},
  miner = { volume = 50, duration = 60, capacitor = 40, range = 3000, gas = true },
  requires = { { skill = "mining", level = 2 } },
})

-- Ammunition by size. The small charges are written out above; the
-- medium and large ones are those, larger. And what the hybrids fire.
addRounds(ROUNDS[2])

-- What the boosters and the ancillary repairers are loaded with (module
-- expansion, 2026-11-16; the figures mine): capacitor charges by size,
-- and nanite paste, which any ancillary armour repairer takes.
for size, each in { { "small", "Small", 100, 1.5, 60 }, { "medium", "Medium", 400, 6, 220 }, { "large", "Large", 1200, 18, 640 } } :: { { any } } do
  table.insert(charges, {
    id = `booster.charge.{each[1]}`, name = `{each[2]} Capacitor Charge`, family = "booster", size = size, volume = each[4],
    basePrice = each[5], damage = { 0, 0, 0, 0 }, rangeMultiplier = 1, velocity = 0, flightTime = 0, explosionRadius = 0,
    explosionVelocity = 0, injects = each[3],
  })
end
table.insert(charges, {
  id = "paste.nanite", name = "Nanite Repair Paste", family = "paste", size = 0, volume = 0.01, basePrice = 300,
  damage = { 0, 0, 0, 0 }, rangeMultiplier = 1, velocity = 0, flightTime = 0, explosionRadius = 0, explosionVelocity = 0,
})
-- What an interdiction field launcher fires (module expansion).
table.insert(charges, {
  id = "bubble.charge", name = "Interdiction Field Charge", family = "bubble", size = 0, volume = 5, basePrice = 20000,
  damage = { 0, 0, 0, 0 }, rangeMultiplier = 1, velocity = 0, flightTime = 0, explosionRadius = 0, explosionVelocity = 0,
})
-- Mining crystals, one for each ore, for a modulated laser (module
-- expansion, 2026-11-16; the figures mine).
for _, each in { { "ferrite", "Ferrite" }, { "silicate", "Silicate" }, { "cuprite", "Cuprite" }, { "titanite", "Titanite" },
  { "cobaltite", "Cobaltite" }, { "iridite", "Iridite" } } :: { { string } } do
  table.insert(charges, {
    id = `crystal.{each[1]}`, name = `{each[2]} Mining Crystal`, family = "crystal", size = 0, volume = 1,
    basePrice = 12000, damage = { 0, 0, 0, 0 }, rangeMultiplier = 1, velocity = 0, flightTime = 0, explosionRadius = 0,
    explosionVelocity = 0, ore = `ore.{each[1]}`, yieldBy = 1.6,
  })
end
for _, reach in MISSILE_REACH do
  local made = missile(`missile.light.em{reach.id}`, `Arc Light {reach.form}`, { 83 * reach.damage, 0, 0, 0 })
  made.flightTime *= reach.flight
  table.insert(charges, made)
end

local MISSILE_SIZES = {
  { id = "heavy", title = "Heavy", damage = 149, velocity = 4300, flight = 6.5, radius = 140, speed = 85, volume = 0.03, price = 180 },
  { id = "cruise", title = "Cruise", damage = 375, velocity = 4700, flight = 14, radius = 330, speed = 70, volume = 0.05, price = 550 },
  -- (what a siege launcher throws: a great deal, seldom, and for what is
  -- big and slow; the reference's, 2026-11-18)
  { id = "siege", title = "Siege", damage = 4750, velocity = 7000, flight = 15, radius = 6000, speed = 40, volume = 0.3, price = 3000 },
}
local MISSILE_KINDS = { { "em", "Arc", 1 }, { "thermal", "Ember", 2 }, { "kinetic", "Lance", 3 }, { "explosive", "Breaker", 4 } } :: { { any } }

-- (a turret's charges alone: a capacitor charge is made a size each
-- already, and paste, a field charge and a mining crystal fit whatever
-- takes them; once every charge but a missile was copied, and there was
-- a "Medium Small Capacitor Charge", 2026-11-23)
local SIZED = { laser = true, projectile = true, hybrid = true }
for _, small in table.clone(charges) do
  if SIZED[small.family] then
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
    -- (and the small one says it is, as the others do: "Small Shock
    -- Canister" beside "Medium Shock Canister", the owner, 2026-11-23)
    if small.size == 1 and string.sub(small.name, 1, 6) ~= "Small " then
      small.name = `Small {small.name}`
    end
  end
end
for index, sized in MISSILE_SIZES do
  for _, kind in MISSILE_KINDS do
    for _, reach in MISSILE_REACH do
      local damage = { 0, 0, 0, 0 }
      damage[kind[3]] = sized.damage * reach.damage
      table.insert(charges, {
        id = `missile.{sized.id}.{kind[1]}{reach.id}`, name = `{kind[2]} {sized.title} {reach.form}`, family = "missile", size = index + 1,
        volume = sized.volume, basePrice = sized.price, damage = damage, rangeMultiplier = 1,
        velocity = sized.velocity, flightTime = sized.flight * reach.flight, explosionRadius = sized.radius,
        explosionVelocity = sized.speed,
      })
    end
  end
end

-- The Kethri's vertical-launch missiles (the owner, 2026-11-19: their
-- own launcher, with its own missiles): of every size and the four
-- kinds, each the plain missile of its size and kind in damage, speed
-- and blast, but flying long enough to go up out of its cell, over and
-- down on a target 1.3 times as far as the plain one reaches (its path
-- VERTICAL's stretch times the straight way). Only a Vertical Launch
-- Battery takes them, and it takes nothing else. (Every figure but the
-- 1.3 mine.)
for _, plain in table.clone(charges) do
  if plain.family == "missile" and string.find(plain.id, "^missile%.%a+%.%a+$") and plain.tech == nil then
    local sized = string.match(plain.id, "^missile%.(%a+)%.")
    local kind = string.match(plain.id, "%.(%a+)$")
    local made = table.clone(plain)
    made.id = `missile.vertical.{sized}.{kind}`
    made.name = string.gsub(plain.name, " Missile$", " Vertical Missile")
    made.flightTime = plain.flightTime * VERTICAL.reach * VERTICAL.stretch
    made.basePrice = plain.basePrice * 1.5
    made.line = "vertical"
    table.insert(charges, made)
  end
end

-- The Nimia's plasma torpedoes (the owner, 2026-11-19: their Plasma
-- Torpedo Launcher, "slow-firing ball-plasma torpedoes" that track to
-- the target and "can't be shot down, but they are relatively
-- slow-moving, so they can be outrun"): of every size, two kinds, each
-- the plain missile of its size in damage, a blast twice as wide and
-- half as quick to spread, and slow, burning long. Only the Plasma
-- Torpedo Launcher takes them. (The names and the two mixes the owner's;
-- the speeds, the burn, the blast and the price mine: "slower" than the
-- 900 to 450 m/s first put to them.)
local PLASMA = { speed = { 550, 450, 350, 250 }, burn = 40, blast = 2, spread = 0.5, price = 2 }
for size, sized in { "light", "heavy", "cruise", "siege" } do
  local plain: ChargeType? = nil
  for _, charge in charges do
    if charge.id == `missile.{sized}.kinetic` then
      plain = charge
    end
  end
  local base = assert(plain, sized)
  local total = base.damage[3]
  for _, kind in { { "static", "Plasmostatic", { 0.9, 0, 0, 0.1 } }, { "baric", "Plasmobaric", { 0, 0.9, 0.1, 0 } } } :: { { any } } do
    local damage: { number } = {}
    for index, part in kind[3] :: { number } do
      damage[index] = total * part
    end
    table.insert(charges, {
      id = `torpedo.plasma.{SIZE_NAME[size]}.{kind[1]}`, name = `{SIZE_TITLE[size]} {kind[2]} Torpedo`, family = "missile",
      size = size, volume = base.volume, basePrice = base.basePrice * PLASMA.price, damage = damage, rangeMultiplier = 1,
      velocity = PLASMA.speed[size], flightTime = PLASMA.burn, explosionRadius = base.explosionRadius * PLASMA.blast,
      explosionVelocity = base.explosionVelocity * PLASMA.spread, line = "plasma",
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
    explosionVelocity = base.explosionVelocity, tech = 2, base = base.id, line = base.line,
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
-- ---------------------------------------------------------------------
-- The reference's figures (the owner, 2026-11-18, of the module pass:
-- "Approved"): each plain module of these families as the reference's
-- plain module of its kind and size, in what it does, what it costs to
-- run and what it takes to fit. Set here, on the plain modules, before
-- any better make is made of them, so every make has them too. Where
-- one module here does what the reference does with one module and a
-- choice of scripts, a computer that is for tracking or for range has
-- the reference's with that script, and the flight computer, which does
-- both, the reference's with none; a remote module's one range is the
-- reference's optimal range and falloff together. (Those choices mine.)
do
  local byId: { [string]: ModuleType } = {}
  for _, m in modules do
    byId[m.id] = m
  end
  local function get(id: string): ModuleType
    return assert(byId[id], `no module {id}`)
  end
  -- (a modifier's figure, where the module has one on that attribute)
  local function set(list: { Modifier }?, attribute: string, value: number)
    if list == nil then
      return
    end
    for _, m in list do
      if m.attribute == attribute then
        m.value = value
      end
    end
  end
  local function fitting(id: string, cpu: number, powergrid: number)
    local m = get(id)
    m.cpu, m.powergrid = cpu, powergrid
  end
  local SIZES = { "small", "medium", "large" }
  local function each(prefix: string, fn: (ModuleType, number) -> ())
    for size, word in SIZES do
      fn(get(`{prefix}.{word}`), size)
    end
  end

  -- Tank
  each("shield.extender", function(m, size)
    set(m.passive, "shield", ({ 400, 800, 1900 })[size])
    set(m.passive, "signature", ({ 2, 7, 25 })[size])
    m.cpu, m.powergrid = ({ 20, 28, 40 })[size], ({ 2, 28, 150 })[size]
  end)
  each("shield.booster", function(m, size)
    local r = assert(m.repair)
    r.amount, r.duration, r.capacitor = ({ 26, 78, 207 })[size], ({ 2, 3, 4 })[size], ({ 20, 60, 160 })[size]
    m.cpu, m.powergrid = ({ 25, 50, 100 })[size], ({ 2, 12, 150 })[size]
  end)
  each("shield.booster.ancillary", function(m, size)
    local r = assert(m.repair)
    r.amount, r.duration, r.capacitor = ({ 52, 146, 390 })[size], ({ 2, 3, 4 })[size], ({ 66, 198, 528 })[size]
    m.cpu, m.powergrid = ({ 25, 50, 100 })[size], ({ 2, 12, 150 })[size]
  end)
  for size, id in { "armor.plate.200mm", "armor.plate.medium", "armor.plate.large" } do
    local m = get(id)
    set(m.passive, "armor", ({ 450, 1750, 3500 })[size])
    set(m.passive, "mass", ({ 140000, 1350000, 3500000 })[size])
    m.cpu, m.powergrid = ({ 15, 25, 30 })[size], ({ 10, 200, 500 })[size]
  end
  each("armor.repairer", function(m, size)
    local r = assert(m.repair)
    r.amount, r.duration, r.capacitor = ({ 69, 276, 690 })[size], ({ 6, 12, 15 })[size], ({ 40, 160, 400 })[size]
    m.cpu, m.powergrid = ({ 5, 25, 50 })[size], ({ 5, 120, 1800 })[size]
  end)
  each("armor.repairer.ancillary", function(m, size)
    local r = assert(m.repair)
    r.amount, r.duration, r.capacitor = ({ 52, 207, 518 })[size], ({ 6, 12, 15 })[size], ({ 40, 160, 400 })[size]
    m.cpu, m.powergrid = ({ 5, 25, 50 })[size], ({ 5, 120, 1800 })[size]
  end)
  get("shield.hardener").boostCapacitor = 40
  fitting("shield.hardener", 40, 1)
  for _, kind in { "em", "thermal", "kinetic", "explosive" } do
    local shield, armor = get(`shield.hardener.{kind}`), get(`armor.hardener.{kind}`)
    shield.boostCapacitor, shield.cpu = 20, 40
    armor.boostDuration, armor.boostCapacitor, armor.cpu = 20, 30, 33
  end
  get("armor.membrane").cpu = 30
  for index = 1, 4 do
    set(get("damage.control").passive, `hullResonance.{index}`, 0.7)
  end
  local bulkhead = get("hull.bulkhead")
  set(bulkhead.passive, "hull", 1.15)
  table.insert(bulkhead.passive, ship("inertia", "mul", 1.03))
  each("capacitor.battery", function(m, size)
    set(m.passive, "capacitor", ({ 120, 500, 1300 })[size])
    m.cpu, m.powergrid = ({ 20, 35, 50 })[size], ({ 8, 75, 400 })[size]
  end)
  get("capacitor.recharger").cpu = 10
  set(get("relay.shield").passive, "capacitorRecharge", 1.3)

  -- Weapon support
  for _, id in { "heat.sink", "gyrostabilizer", "flux.coil", "ballistic.control" } do
    local m = get(id)
    set(m.passive, "damageMultiplier", 1.07)
    set(m.passive, "duration", 0.92)
    m.cpu = if id == "ballistic.control" then 35 else 27
  end
  local enhancer = get("tracking.enhancer")
  set(enhancer.passive, "tracking", 1.07)
  set(enhancer.passive, "optimal", 1.0725)
  set(enhancer.passive, "falloff", 1.145)
  local tracking, range, flight = get("computer.tracking"), get("computer.range"), get("computer.flight")
  set(tracking.boost, "tracking", 1.2)
  set(range.boost, "optimal", 1.1)
  set(range.boost, "falloff", 1.2)
  set(flight.boost, "flight", 1.08)
  set(flight.boost, "blast", 0.945)
  tracking.boostCapacitor, range.boostCapacitor, flight.boostCapacitor = 7, 7, 7
  local amplifier, link = get("drone.amplifier"), get("drone.tracking")
  if amplifier.drones then
    amplifier.drones.damage = 1.15
  end
  if link.drones then
    link.drones.tracking = 1.2
  end

  -- Electronic warfare
  local function hex(id: string, fields: { [string]: number })
    local h = assert(get(id).hex, id) :: any
    for key, value in fields do
      h[key] = value
    end
  end
  hex("projector.entanglement", { strength = 0.5, capacitor = 5 })
  fitting("projector.entanglement", 25, 1)
  hex("disruptor.warp", { capacitor = 25 })
  fitting("disruptor.warp", 40, 1)
  hex("painter.target", { strength = 1.25, range = 30000, capacitor = 10 })
  hex("damper.sensor", { strength = 0.863, range = 25000, capacitor = 30 })
  fitting("damper.sensor", 35, 1)
  for _, id in { "ewar.tracking", "ewar.guidance" } do
    hex(id, { strength = 0.847, range = 40000 })
    fitting(id, 40, 1)
  end
  hex("neutraliser.small", { range = 4000, capacitor = 45 })
  fitting("neutraliser.small", 10, 8)
  each("drain", function(m, size)
    local h = assert(m.hex)
    h.strength, h.duration, h.range = ({ 8, 30, 100 })[size], ({ 2.5, 5, 10 })[size], ({ 4000, 8000, 16000 })[size]
    m.cpu, m.powergrid = ({ 15, 25, 50 })[size], ({ 8, 175, 2000 })[size]
  end)
  local booster = get("sensor.booster")
  set(booster.boost, "lockRange", 1.25)
  set(booster.boost, "scanResolution", 1.25)
  booster.boostCapacitor, booster.cpu = 10, 12
  for _, kind in { "em", "thermal", "kinetic", "explosive" } do
    each(`smartbomb.{kind}`, function(m, size)
      local bomb = assert(m.smartbomb)
      for index, amount in bomb.damage do
        bomb.damage[index] = if amount > 0 then ({ 50, 100, 250 })[size] else 0
      end
      bomb.range, bomb.capacitor = ({ 3000, 4000, 5000 })[size], ({ 30, 75, 200 })[size]
      m.cpu, m.powergrid = ({ 30, 50, 80 })[size], ({ 8, 200, 1000 })[size]
    end)
  end

  -- Remote assistance
  each("remote.shield", function(m, size)
    local h = assert(m.hex)
    h.strength, h.duration, h.range, h.capacitor = ({ 65, 260, 520 })[size], ({ 4, 8, 8 })[size], ({ 10500, 12500, 16700 })[size],
      ({ 58, 232, 492 })[size]
    m.cpu, m.powergrid = ({ 28, 50, 112 })[size], ({ 3, 52, 208 })[size]
  end)
  each("remote.armor", function(m, size)
    local h = assert(m.hex)
    h.strength, h.duration, h.range, h.capacitor = ({ 49, 196, 392 })[size], ({ 3, 6, 6 })[size], ({ 9500, 11250, 15500 })[size],
      ({ 38, 155, 330 })[size]
    m.cpu, m.powergrid = ({ 10, 20, 40 })[size], ({ 6, 120, 600 })[size]
  end)
  each("remote.capacitor", function(m, size)
    local h = assert(m.hex)
    h.strength, h.duration, h.range, h.capacitor = ({ 30, 90, 270 })[size], 5, ({ 3500, 5000, 7500 })[size], ({ 38, 113, 338 })[size]
    m.cpu, m.powergrid = ({ 30, 40, 50 })[size], ({ 4, 80, 320 })[size]
  end)

  -- Propulsion and utility
  for size, id in { "afterburner.1mn", "afterburner.medium", "afterburner.large" } do
    local m = get(id)
    m.boostCapacitor, m.cpu, m.powergrid = ({ 20, 80, 320 })[size], ({ 15, 25, 50 })[size], ({ 10, 50, 625 })[size]
  end
  for size, id in { "mwd.5mn", "mwd.medium", "mwd.large" } do
    local m = get(id)
    m.boostCapacitor, m.cpu, m.powergrid = ({ 45, 180, 320 })[size], ({ 25, 50, 75 })[size], ({ 15, 150, 1250 })[size]
    -- (and a quarter less capacitor while it is fitted, running or not)
    set(m.passive, "capacitor", 0.75)
  end
  set(get("overdrive").passive, "cargo", 0.85)
  local expander = get("cargo.expander")
  set(expander.passive, "maxVelocity", 0.85)
  table.insert(expander.passive, ship("hull", "mul", 0.8))
  set(get("fitting.coprocessor").passive, "cpu", 1.08)
end

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
          tracking = weapon.tracking, clip = weapon.clip, reload = weapon.reload, size = weapon.size, mount = weapon.mount,
          flight = weapon.flight, blast = weapon.blast, leap = weapon.leap, volley = weapon.volley,
          line = weapon.line, path = weapon.path } else nil,
        repair = if repair then { layer = repair.layer, amount = repair.amount * make.amount, duration = repair.duration,
          capacitor = repair.capacitor } else nil,
        miner = if miner then { volume = miner.volume * make.amount, duration = miner.duration, capacitor = miner.capacitor,
          range = miner.range, gas = miner.gas, ice = miner.ice } else nil,
        hex = if hex and mends then { kind = hex.kind, range = hex.range, strength = hex.strength * make.amount,
          duration = hex.duration, capacitor = hex.capacitor } else nil,
        internal = base.internal,
        tech = make.tech, meta = make.meta, base = base.id,
        -- (and what it is loaded with, and does with it, as its plain make)
        takes = base.takes, ancillary = base.ancillary, short = base.short,
      })
    end
  end
end

-- ---------------------------------------------------------------------
-- A module made over, generally: every figure of it by a factor.
-- 'output' is on what it gives (a weapon's damage, what a repairer
-- mends, what a laser cuts, what a plate or an extender holds, and the
-- good of every other thing it does to its ship or its weapons),
-- 'fitting' on its CPU and powergrid, 'capacitor' on what it draws, and
-- 'reach' on how far it reaches. (The three makes above are older than
-- this, and are worked out their own way: they change nothing but
-- damage, amount and fitting.)

-- Attributes of which less is the better: what a module does to one of
-- these is good when it makes it smaller.
local function lessIsBetter(attribute: string): boolean
  return string.find(attribute, "Resonance", 1, true) ~= nil or attribute == "capacitorRecharge" or attribute == "shieldRecharge"
    or attribute == "signature" or attribute == "mass" or attribute == "inertia" or attribute == "blast"
    -- (a weapon's cycle: shorter is faster; till 2026-11-20 a weapon upgrade's make left its rate as the plain one's)
    or attribute == "duration"
end

-- A modifier with the good it does made 'output' times as much. What
-- it costs its ship (a cargo extension's speed, a drive's mass) is left.
local function bettered(m: Modifier, output: number): Modifier
  local value = m.value
  local less = lessIsBetter(m.attribute)
  if m.op == "mul" then
    if (value > 1 and not less) or (value < 1 and less) then
      value = 1 + (value - 1) * output
      -- (nothing is made nothing, or less: a tenth of it is always left)
      if less then
        value = math.max(0.1, value)
      end
    end
  elseif (value > 0 and not less) or (value < 0 and less) then
    value *= output
  end
  return { on = m.on, family = m.family, attribute = m.attribute, op = m.op, value = value, stack = m.stack }
end

-- ('amount', where it is given, is on everything a module gives but a
-- weapon's damage, in place of 'output': the older makes have the two
-- apart, and a make that is to be better than one of them has to be.)
type Tune = { output: number, amount: number?, fitting: number, capacitor: number, reach: number, price: number }

local function resized(n: number, by: number): number
  if n <= 0 then
    return n
  end
  return math.max(1, if by < 1 then math.floor(n * by) else math.ceil(n * by))
end

local function made(base: ModuleType, id: string, name: string, tune: Tune): ModuleType
  local amount = tune.amount or tune.output
  local passive: { Modifier } = {}
  for _, m in base.passive do
    table.insert(passive, bettered(m, amount))
  end
  local boost: { Modifier }? = nil
  if base.boost then
    local list: { Modifier } = {}
    for _, m in base.boost do
      table.insert(list, bettered(m, amount))
    end
    boost = list
  end
  local weapon, repair, miner, hex = base.weapon, base.repair, base.miner, base.hex
  local mends = hex ~= nil and (hex.kind == "shield" or hex.kind == "armor")
  local out = table.clone(base)
  out.id, out.name = id, name
  out.cpu, out.powergrid = resized(base.cpu, tune.fitting), resized(base.powergrid, tune.fitting)
  out.basePrice = math.floor(base.basePrice * tune.price)
  out.passive, out.boost = passive, boost
  out.boostCapacitor = if base.boostCapacitor then base.boostCapacitor * tune.capacitor else nil
  if weapon then
    local w = table.clone(weapon)
    w.damageMultiplier, w.capacitor = weapon.damageMultiplier * tune.output, weapon.capacitor * tune.capacitor
    w.optimal, w.falloff = weapon.optimal * tune.reach, weapon.falloff * tune.reach
    out.weapon = w
  end
  if repair then
    local r = table.clone(repair)
    r.amount, r.capacitor = repair.amount * amount, repair.capacitor * tune.capacitor
    out.repair = r
  end
  if miner then
    local m = table.clone(miner)
    m.volume, m.capacitor, m.range = miner.volume * amount, miner.capacitor * tune.capacitor, miner.range * tune.reach
    out.miner = m
  end
  if hex then
    local h = table.clone(hex)
    -- (what it does to its target, so much more: since 2026-11-16 for every
    -- kind but a disruptor's, which holds or does not)
    local kind = hex.kind
    h.strength = if mends or kind == "neut" or kind == "nos" or kind == "capacitor" then hex.strength * amount
      elseif kind == "jam" then math.min(0.95, hex.strength * amount)
      elseif kind == "paint" or kind == "sensor" then 1 + (hex.strength - 1) * amount
      elseif kind == "entangle" or kind == "damp" or kind == "track" or kind == "guide" then math.max(0.05, 1 - (1 - hex.strength) * amount)
      else hex.strength
    h.capacitor, h.range = hex.capacitor * tune.capacitor, hex.range * tune.reach
    out.hex = h
  end
  -- (what the module expansion's kinds do, so much more: 2026-11-16)
  if base.drones then
    local d = base.drones
    out.drones = { damage = if d.damage then 1 + (d.damage - 1) * amount else nil,
      tracking = if d.tracking then 1 + (d.tracking - 1) * amount else nil,
      speed = if d.speed then 1 + (d.speed - 1) * amount else nil }
  end
  if base.mining then
    out.mining = 1 + (base.mining - 1) * amount
  end
  if base.ice then
    out.ice = 1 + (base.ice - 1) * amount
  end
  if base.salvage then
    out.salvage = base.salvage * amount
  end
  if base.probing then
    out.probing = 1 + (base.probing - 1) * amount
  end
  if base.burstJam then
    local b = table.clone(base.burstJam)
    b.strength, b.range, b.capacitor = math.min(0.95, b.strength * amount), b.range * tune.reach, b.capacitor * tune.capacitor
    out.burstJam = b
  end
  if base.smartbomb then
    local b = table.clone(base.smartbomb)
    local damage = {}
    for kind, d in base.smartbomb.damage do
      damage[kind] = d * tune.output
    end
    b.damage, b.capacitor, b.range = damage, base.smartbomb.capacitor * tune.capacitor, base.smartbomb.range * tune.reach
    out.smartbomb = b
  end
  if base.adaptive then
    out.adaptive = { total = math.min(0.9, base.adaptive.total * amount), step = base.adaptive.step }
  end
  if base.ancillary then
    out.ancillary = { factor = 1 + (base.ancillary.factor - 1) * amount }
  end
  if base.tractor then
    local b = table.clone(base.tractor)
    b.range, b.speed, b.capacitor = b.range * tune.reach, b.speed * amount, b.capacitor * tune.capacitor
    out.tractor = b
  end
  if base.scanner then
    local b = table.clone(base.scanner)
    b.range, b.capacitor = b.range * tune.reach, b.capacitor * tune.capacitor
    out.scanner = b
  end
  if base.burst then
    out.burst = { range = base.burst.range * tune.reach, mining = if base.burst.mining then 1 + (base.burst.mining - 1) * amount else nil }
  end
  -- (and the kinds of 2026-11-20: a repair amplifier's share, a drone link's reach)
  if base.amplify then
    out.amplify = { layer = base.amplify.layer, by = base.amplify.by * amount }
  end
  if base.droneRange then
    out.droneRange = base.droneRange * amount
  end
  -- (and the older kinds brought up to the full line, 2026-11-20)
  if base.salvager then
    local b = table.clone(base.salvager)
    b.range, b.capacitor = b.range * tune.reach, b.capacitor * tune.capacitor
    b.chance = if b.chance > 0 then math.min(1, b.chance * amount) else b.chance
    out.salvager = b
  end
  if base.analyzer then
    local b = table.clone(base.analyzer)
    b.range = b.range * tune.reach
    out.analyzer = b
  end
  if base.pds then
    local b = table.clone(base.pds)
    b.damage, b.accuracy = b.damage * tune.output, math.min(0.95, b.accuracy * amount)
    b.tracking, b.optimal, b.falloff = b.tracking * amount, b.optimal * tune.reach, b.falloff * tune.reach
    out.pds = b
  end
  -- (it is a make of the plain module its base is a make of, and wants the skills of what it was made from)
  out.base = base.base or base.id
  return out
end

-- ---------------------------------------------------------------------
-- The full line for every module (the owner's, 2026-11-20: "Full line"
-- for the kinds new that day, then "let's bring older modules up to the
-- current standard"): beside a people's make and the pirate site tier
-- (below), a custom make, a tech 2 make and a masterwork, and so an
-- officer's, each as much better as the older three makes are, for
-- every module that had none. Not those that do one thing or do not
-- (ONE_THING), which no make would better; and a rig has a tech 2 make
-- and no other (the owner's: "We do want t2 rigs, for sure").
local ONE_THING: { [string]: boolean } = { ["jump.portal"] = true, ["hack.buffer"] = true, ["beacon.jump"] = true,
  ["jump.micro"] = true, ["cloak.device"] = true, ["bubble.launcher"] = true }
local NEW_MAKES: { { id: string, name: string, tune: Tune, tech: number?, meta: number? } } = {
  { id = CUSTOM.id, name = CUSTOM.name, tune = { output = CUSTOM.damage, amount = CUSTOM.amount, fitting = CUSTOM.fitting, capacitor = 1,
    reach = 1, price = CUSTOM.price }, meta = 1 },
  { id = TECH2.id, name = TECH2.name, tune = { output = TECH2.damage, amount = TECH2.amount, fitting = TECH2.fitting, capacitor = 1,
    reach = 1, price = TECH2.price }, tech = 2 },
  { id = MASTER.id, name = MASTER.name, tune = { output = MASTER.damage, amount = MASTER.amount, fitting = MASTER.fitting, capacitor = 1,
    reach = 1, price = MASTER.price }, meta = 2 },
}
do
  local had: { [string]: boolean } = {}
  for _, m in modules do
    had[m.id] = true
  end
  for _, base in table.clone(modules) do
    if not base.tech and not base.meta and not base.lineage and not base.internal and not ONE_THING[base.id] then
      for _, make in NEW_MAKES do
        if (base.slot ~= "rig" or make.tech == 2) and not had[base.id .. make.id] then
          local own = made(base, base.id .. make.id, base.name .. make.name, make.tune)
          own.tech, own.meta, own.base = make.tech, make.meta, base.id
          table.insert(modules, own)
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------
-- A people's own make (the owner's rulings, 2026-11-15: "Speciality,
-- plus one utility each"). Each of the four peoples builds its own make
-- of the kinds of module it is known for: the weapons its warships
-- carry, what it keeps them whole with, and one other thing. Fifteen
-- parts in a hundred more of what the module gives, as easy to fit as
-- the plain one, and no more skill: better than the custom make, short
-- of tech 2. Their stations sell them, to a pilot they think well of
-- (Assets/Market), and their agents now and then pay with one
-- (Assets/Missions). Nobody has the drawings.
--
-- (Which other thing is whose is my proposal, for the owner to correct:
-- the Vessari carry more, the Talmar aim better, the Orun go faster,
-- the Kethri have the capacitor for their lasers.)
--
-- And since 2026-11-16 (module expansion; the owner's answer, "Full line
-- per people"): every people makes its own of most utility modules too
-- (propulsion, tank, fitting, weapon upgrades, electronic warfare,
-- remote repair, drone upgrades), shaded to its style. Its speciality
-- keeps the make above; the rest of its line is shaded, the figures
-- and which shade is whose mine: the Vessari's well made and easy to
-- fit, the Talmar's reaching further, the Orun's giving the most and
-- hardest to fit, the Kethri's drawing the least capacitor.
-- (Since 2026-11-20 every module but those that do one thing or do not,
-- ONE_THING above: the owner's "bring older modules up to the current
-- standard".)
local SHADES: { [string]: Tune } = {
  vessari = { output = 1.10, fitting = 0.85, capacitor = 1, reach = 1, price = 5 },
  talmar = { output = 1.10, fitting = 1, capacitor = 1, reach = 1.15, price = 5 },
  orun = { output = 1.18, fitting = 1.1, capacitor = 1, reach = 1, price = 5 },
  kethri = { output = 1.10, fitting = 1, capacitor = 0.8, reach = 1, price = 5 },
}
-- What a people's shade is, in words (Data/Facts).
local SHADE_WORDS: { [string]: string } = {
  vessari = "a tenth better, and easier to fit", talmar = "a tenth better, and reaching further",
  orun = "nearly a fifth better, and harder to fit", kethri = "a tenth better, and drawing a fifth less capacitor",
}
local PEOPLES: { { id: string, name: string, makes: { string } } } = {
  { id = "vessari", name = "Vessari", makes = { "launcher.", "armor.plate", "armor.repairer", "armor.membrane", "armor.hardener",
    "cargo.expander" } },
  { id = "talmar", name = "Talmar", makes = { "autocannon.", "artillery.", "shield.extender", "shield.booster", "shield.hardener",
    "computer.tracking", "tracking.enhancer" } },
  { id = "orun", name = "Orun", makes = { "blaster.", "railgun.", "armor.plate", "armor.repairer", "armor.membrane", "armor.hardener",
    "afterburner.", "mwd." } },
  { id = "kethri", name = "Kethri", makes = { "laser.pulse", "laser.beam", "armor.plate", "armor.repairer", "armor.membrane",
    "armor.hardener", "capacitor.battery", "capacitor.recharger" } },
}
local PEOPLE_TUNE: Tune = { output = 1.15, fitting = 1, capacitor = 1, reach = 1, price = 6 }
local function starts(id: string, prefixes: { string }): boolean
  for _, prefix in prefixes do
    if string.sub(id, 1, #prefix) == prefix then
      return true
    end
  end
  return false
end
for _, base in table.clone(modules) do
  if not base.tech and not base.meta and not base.internal and not base.lineage and base.slot ~= "rig" then
    for _, people in PEOPLES do
      -- (since 2026-11-20 every module that is not of their speciality, and does more than one thing: ONE_THING)
      -- (and not another people's guns nor a mining laser: a people makes its own of those, or none)
      local tune = if starts(base.id, people.makes) then PEOPLE_TUNE
        elseif not ONE_THING[base.id] and not base.weapon and not base.miner then SHADES[people.id] else nil
      if tune then
        local own = made(base, `{base.id}.{people.id}`, `{people.name} {base.name}`, tune)
        own.meta, own.lineage = 3, people.id
        own.shaded = if tune ~= PEOPLE_TUNE then true else nil
        table.insert(modules, own)
      end
    end
  end
end

-- ---------------------------------------------------------------------
-- The pirate site tier (module expansion, 2026-11-16; the owner's answer
-- "Yes, pirate site tier"): what the Unbound keep for themselves at their
-- dens and camps and towers, in three grades by how deep or dangerous the
-- place is. Better than a people's make, short of an officer's. Of the
-- modules a captain fits (those with a masterwork) and of the utility
-- line the peoples make. Only found: in a den's or a stronghold's
-- stores, a camp chief's wreck, a tower commander's (Tactical/Sites).
-- The grades' names and figures are mine.
local SITE_RANKS = { "Raider", "Reaver", "Warlord" }
local SITE_TUNES: { Tune } = {
  { output = 1.20, amount = 1.25, fitting = 0.95, capacitor = 0.95, reach = 1, price = 10 },
  { output = 1.24, amount = 1.32, fitting = 0.9, capacitor = 0.95, reach = 1.02, price = 15 },
  { output = 1.28, amount = 1.40, fitting = 0.88, capacitor = 0.92, reach = 1.04, price = 25 },
}
local siteMakes: { { string } } = { {}, {}, {} }
local ids: { [string]: boolean } = {}
for _, module in modules do
  ids[module.id] = true
end
for _, base in table.clone(modules) do
  if not base.tech and not base.meta and not base.internal and not base.lineage and base.slot ~= "rig" and not base.capital
    and not base.classes then
    -- (what a captain fits: what there is a masterwork of)
    if ids[base.id .. ".master"] then
      for grade, tune in SITE_TUNES do
        local own = made(base, `{base.id}.site{grade}`, `Unbound {SITE_RANKS[grade]} {base.name}`, tune)
        own.meta, own.site = 6, grade
        table.insert(modules, own)
        table.insert(siteMakes[grade], own.id)
      end
    end
  end
end

-- Every weapon a ship fits hits half as hard again as the reference's
-- of its size and make (the owner, 2026-11-18, of fights that took far
-- longer than they should: the reference's pilots hit three to five
-- times as hard as its bare guns, through skills, hull bonuses and
-- damage modules, and this is the part of that a pilot with none of
-- those has here). Not what a drone, a fighter or a bomber carries.
local WEAPON_DAMAGE = 1.5
do
  local done: { [Weapon]: boolean } = {}
  for _, m in modules do
    local weapon = m.weapon
    if weapon and not m.internal and not done[weapon] then
      done[weapon] = true
      weapon.damageMultiplier *= WEAPON_DAMAGE
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

-- What a module is loaded with: a weapon's charges, or a booster's or
-- an ancillary repairer's (ModuleType.takes). Nil for one that takes none.
function Modules.Takes(module: ModuleType): { family: string, size: number, clip: number, reload: number, line: string? }?
  local weapon = module.weapon
  if weapon then
    return { family = weapon.family, size = weapon.size, clip = weapon.clip, reload = weapon.reload, line = weapon.line }
  end
  return module.takes
end

-- Whether a charge goes in a module (of its family and size; a size 0
-- takes any of its family; a tech 2 charge only a tech 2 weapon; a
-- charge of a launcher's own line only that launcher, which takes nothing
-- else).
function Modules.Fits(module: ModuleType, charge: ChargeType): boolean
  local takes = Modules.Takes(module)
  return takes ~= nil and charge.family == takes.family and (takes.size == 0 or charge.size == takes.size)
    and not (charge.tech == 2 and module.tech ~= 2) and charge.line == takes.line
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

-- ---------------------------------------------------------------------
-- An officer's module, and a mutated one: each is a module by itself,
-- and what it is, is in what it is called. There is no list of them:
-- a module's id says whose it was ("autocannon.small.officer@Mara_Venn")
-- or how it came out of the mutator ("autocannon.small~40253055": four
-- figures, each from 00 to 55, which is 25 parts in a hundred worse to
-- 30 better), and the module is worked out from that when it is first
-- asked for. Two with the same id are the same module, in any game.

-- An officer's: better than a masterwork in everything (the owner's:
-- "A new tier above it"). A third more damage from a weapon (a
-- masterwork's is a quarter) and 45 parts in a hundred more of what
-- anything else gives (a masterwork's is 35), easier to fit than a
-- masterwork, a little easier on the capacitor and a little longer in
-- reach. (The figures are mine.)
local OFFICER_TUNE: Tune = { output = 1.32, amount = 1.45, fitting = 0.85, capacitor = 0.9, reach = 1.05, price = 40 }
local OFFICER = ".officer@"
-- A mutation: each figure anywhere from a quarter worse to three tenths
-- better (the owner's: "A gamble, wide"), in hundredths.
Modules.WORST, Modules.BEST = -25, 30
Modules.ROLLS = 4

local function derived(id: string): ModuleType?
  local cut = string.find(id, "~", 1, true)
  if cut then
    local base = Modules.byId[string.sub(id, 1, cut - 1)]
    local code = string.sub(id, cut + 1)
    if base == nil or base.mutated or #code ~= 2 * Modules.ROLLS or string.find(code, "^%d+$") == nil then
      return nil
    end
    local rolls: { number } = {}
    for index = 1, Modules.ROLLS do
      local roll = (tonumber(string.sub(code, 2 * index - 1, 2 * index)) :: number) + Modules.WORST
      if roll > Modules.BEST then
        return nil
      end
      rolls[index] = roll
    end
    local out = made(base, id, `Mutated {base.name}`, { output = 1 + rolls[1] / 100, fitting = 1 - rolls[2] / 100,
      capacitor = 1 - rolls[3] / 100, reach = 1 + rolls[4] / 100, price = 1.5 })
    out.mutated, out.rolls = true, rolls
    out.meta = base.meta or 5
    return out
  end
  local at = string.find(id, OFFICER, 1, true)
  if at then
    local base = Modules.byId[string.sub(id, 1, at - 1)]
    local who = string.sub(id, at + #OFFICER)
    -- (of the plain modules there is a masterwork of: what a captain fits)
    if base == nil or base.tech or base.meta or who == "" or rawget(Modules.byId, base.id .. ".master") == nil then
      return nil
    end
    local name = (string.gsub(who, "_", " "))
    local out = made(base, id, `{name}'s {base.name}`, OFFICER_TUNE)
    out.meta, out.officer = 4, name
    return out
  end
  return nil
end

setmetatable(Modules.byId :: any, { __index = function(known: { [string]: ModuleType }, id: any): ModuleType?
  if type(id) ~= "string" then
    return nil
  end
  local found = derived(id)
  if found then
    rawset(known, id, found)
  end
  return found
end })

-- The id of a module as an officer of a name carried it; nil if it is
-- no module an officer carries.
function Modules.Officer(id: string, name: string): string?
  local made = `{id}{OFFICER}{(string.gsub(name, " ", "_"))}`
  return if Modules.byId[made] then made else nil
end

-- The id of a module as it comes out of a mutator with these rolls
-- (hundredths, WORST to BEST, one for each figure); nil if it cannot
-- be mutated (it has been already, or it is no module).
function Modules.Mutated(id: string, rolls: { number }): string?
  local code = ""
  for index = 1, Modules.ROLLS do
    code ..= string.format("%02d", math.clamp(math.floor((rolls[index] or 0) + 0.5), Modules.WORST, Modules.BEST) - Modules.WORST)
  end
  local made = `{id}~{code}`
  return if Modules.byId[made] then made else nil
end

-- The peoples that have makes of their own, and a people's make of a
-- module, if they have one.
function Modules.Peoples(): { string }
  local ids: { string } = {}
  for _, people in PEOPLES do
    table.insert(ids, people.id)
  end
  return ids
end

-- The pirate site tier's makes of a grade (1 to 3), by their ids.
function Modules.SiteMakes(grade: number): { string }
  return siteMakes[math.clamp(grade, 1, 3)]
end

-- What a grade of the pirate site tier is called.
function Modules.SiteRank(grade: number): string
  return SITE_RANKS[math.clamp(grade, 1, 3)]
end

-- How a people's shade of its line is, in words; nil for none.
function Modules.Shade(people: string): string?
  return SHADE_WORDS[people]
end

function Modules.Own(id: string, people: string): ModuleType?
  local better = rawget(Modules.byId, `{id}.{people}`)
  return if better and better.meta == 3 then better else nil
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
    return module.weapon.mount or module.weapon.size
  end
  return if string.find(module.id, "large", 1, true) then 3 elseif string.find(module.id, "medium", 1, true) then 2 else 1
end

-- Whether a module is one that mends another ship (a remote shield
-- booster or armour repairer).
function Modules.Mends(module: ModuleType): boolean
  return module.hex ~= nil and (module.hex.kind == "shield" or module.hex.kind == "armor")
end

-- Whether a module that runs on another ship is for a friend (one that
-- mends, a relay that sends capacitor, or a remote sensor booster), where
-- everything else that runs on another ship is for an enemy.
function Modules.Friendly(module: ModuleType): boolean
  return module.hex ~= nil and (Modules.Mends(module) or module.hex.kind == "capacitor" or module.hex.kind == "sensor")
end
for _, c in charges do
  Modules.chargeById[c.id] = c
end

return Modules
