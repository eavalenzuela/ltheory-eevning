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

local Factions = require("@lt/Core/Data/Factions")
local HullBonuses = require("@lt/Core/Data/HullBonuses")
local Structures = require("@lt/Core/Data/Structures")

-- A gun that is part of a hull, fixed along its bow (ShipType's
-- 'spinal'): what it is called, the family its fire is drawn and heard
-- as and the gun it looks like firing, what a round of it does of each
-- kind of damage, how far it reaches and how well it follows (as a
-- turret's figures are), the seconds between rounds, and the capacitor
-- a round takes.
export type Spinal = {
  name: string, family: string, look: string,
  damage: { number }, optimal: number, falloff: number, tracking: number,
  duration: number, capacitor: number,
}

export type ShipType = {
  id: string,
  name: string,
  class: string,
  lineage: string,        -- the faction whose design it is (Data/Factions); "" for none
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
  -- How many drones it can control at once (Tactical/Drones): by its
  -- class, given below, unless it says.
  drones: number?,
  -- And the room it has for them, m3: its drone bay, apart from its
  -- hold. By its class too.
  bay: number?,
  -- An ore hold, m3: a second hold, for ore and gas and nothing else,
  -- which what the ship mines goes into, and what the barges of its
  -- pilot's fleet mine beside it (Tactical/Fleet). A capital
  -- industrial's, by its class; nil or 0 for none.
  ore: number?,
  -- A ship bay, m3: a second hold for packed hulls and nothing else. A
  -- logistics capital's, which carries ships where another capital
  -- industrial carries ore (its faction's line says: 'role'
  -- "transport"); nil or 0 for none.
  shipbay: number?,
  -- Rig slots, and the calibration the rigs in them share (Data/Modules).
  -- Every hull but the capsule has three and 400: given below, to all.
  rigs: number?,
  calibration: number?,
  turrets: number,        -- hardpoints
  launchers: number,
  capacitor: number,      -- GJ
  capacitorRecharge: number, -- s
  -- A hull that mends by itself (the Nimia's: Data/Factions' 'mends'):
  -- the share of its armour, and of its hull, that comes back each
  -- second, whatever it is doing (Tactical/Combat). Nil or 0 for a hull
  -- that does not, which is every other.
  armorMend: number?,
  hullMend: number?,
  -- targeting
  scanResolution: number, -- mm; higher locks faster
  lockRange: number,      -- m
  maxTargets: number,
  cargo: number,          -- m3
  -- Skills a pilot needs to board it. (Where absent, Data/Skills says.)
  requires: { { skill: string, level: number } }?,
  -- Nobody's to own: what stands for a tower or a battery, a drone, a
  -- tender. Not an item, and with no blueprint.
  restricted: boolean?,
  -- An alien people's hull, or the pirates': an item, with a blueprint,
  -- that no human market sells and nobody sells the blueprint of. Where
  -- the blueprints are to be found is the owner's to say (2026-11-16:
  -- "Once there are BPs for everything, we can decide where to seed
  -- them"). Until 2026-11-16 these were 'restricted', and had neither.
  foreign: boolean?,
  -- A pirate hull: the hull it was made out of.
  donor: string?,
  -- 2 for a tech 2 hull: the improved make of the hull 'base', which it
  -- is built from (below).
  tech: number?,
  base: string?,
  -- What it is beside the plain hull of its class, where a faction's
  -- line says (Data/Factions): "combat" for a combat hauler; that it has
  -- a jump drive (Tactical/Jumping); that it is built to go unseen, and
  -- a cloak neither slows it nor is broken from as far; that it has a
  -- cloak of its own, built in (Tactical/Combat: nothing is fitted for
  -- it, and it takes no slot and no capacitor); that it is built for
  -- exploration (Ships.EXPLORER, below). A hull built to go unseen or
  -- to explore fits a cloaking device for a tenth of what it asks of
  -- another (Ships.CLOAK_FITTING).
  role: string?,
  jump: boolean?,
  stealth: boolean?,
  cloak: boolean?,
  explorer: boolean?,
  -- A refinery aboard (the Drowned's Griever: the project owner's
  -- "mobile refinery"): ore in the hull's own hold, or its ore hold, is
  -- refined where it lies, in space or docked, and the minerals go in
  -- the hold (Assets/Industry). Nil for every other hull, whose ore is
  -- refined at a station.
  refinery: boolean?,
  -- Built to hold ships where they are (an interdictor): an interdiction
  -- field it drops is wider and lasts longer (Ships.INTERDICTOR,
  -- Tactical/Combat). Nil for every other hull.
  interdictor: boolean?,
  -- Built for electronic warfare: what it does to another ship with a
  -- web, a disruptor, a painter, a dampener, a jammer, a neutraliser and
  -- the like it does from farther and more strongly (Ships.EWAR,
  -- Tactical/Combat). Nil for every other hull.
  ewar: boolean?,
  -- A gun of the hull's own, fixed along its bow (the Drowned's The End:
  -- the project owner's "special, fixed bow railgun"): nothing is
  -- fitted for it and it takes no slot. It fires where the ship points,
  -- so the ship is aligned to its target to fire it, as for a warp
  -- (Tactical/Combat). Nil for every other hull.
  spinal: Spinal?,
  -- A jump drive with a field, m: when the hull jumps, every friendly
  -- ship within so far of it goes where it goes (Tactical/Jumping). Nil
  -- for a drive that takes its own hull and no more, which is every
  -- other.
  jumpField: number?,
  -- The kind of damage it leans to, as its faction's ships do (Data/
  -- Factions): 1 EM, 2 thermal, 3 kinetic, 4 explosive. Its weapons do
  -- AFFINITY more of that kind, and its shield, armour and hull let
  -- that much less of it through (which is in its resonances already).
  -- Nil for a hull that leans to none.
  affinity: number?,
  -- Its turret hardpoints by the size of gun each is for, where they are
  -- not all alike: so many for small guns, for medium, for large and for
  -- XL; and its launcher hardpoints likewise. A weapon goes on a
  -- hardpoint of its own size, or on a bigger one (Attributes.Check).
  -- Nil for a hull whose hardpoints take any.
  guns: { number }?,
  racks: { number }?,
  -- Nobody sells it, nor the blueprint for it (Data/Types).
  rare: boolean?,
  -- What it does better than its class, a level of a skill or as its
  -- role (Data/HullBonuses). Nil for a hull that has no such bonus.
  bonuses: { HullBonuses.HullBonus }?,
}

-- The bow railgun of the Drowned's ultracapital: one round where a
-- siege dreadnought's largest gun fires a hundred, at a target the
-- whole ship has been pointed at. It follows nothing: what is small and
-- crossing is missed, and what is a capital or stands still is hit
-- squarely. (Every figure is a first one: the owner's word is that it
-- is a railgun, fixed in the bow, and special.)
local BOW_RAILGUN: Spinal = {
  name = "Bow Railgun", family = "hybrid", look = "railgun.xl",
  damage = { 0, 10000, 30000, 0 }, optimal = 150000, falloff = 60000, tracking = 2,
  duration = 30, capacitor = 15000,
}
-- And the Vessari's Raiden's: a cruiser's, which fires what a
-- battleship's largest railgun does in a dozen rounds, once every
-- twenty seconds, out to sixty kilometres, and follows little more
-- than the other does. (First figures, and mine: the owner's word is
-- "t2 cruiser (special, bow railgun)".)
local CRUISER_RAILGUN: Spinal = {
  name = "Bow Railgun", family = "hybrid", look = "railgun.large",
  damage = { 0, 600, 1800, 0 }, optimal = 60000, falloff = 20000, tracking = 20,
  duration = 20, capacitor = 300,
}
-- (a hull's bow railgun, by its class: a cruiser's, or the ultracapital's)
local function bowRailgun(class: string): Spinal
  return if class == "cruiser" then CRUISER_RAILGUN else BOW_RAILGUN
end

local SHIELD = { 1.0, 0.8, 0.6, 0.5 }
local ARMOR = { 0.5, 0.65, 0.75, 0.9 }
local HULL = { 0.67, 0.67, 0.67, 0.67 }
-- How much more of its own kind of damage a hull with an affinity
-- deals, and how much less of it each of its layers lets through (the
-- project owner's figure, 2026-11-14).
local AFFINITY = 0.15

-- A layer's resonances for a hull that leans to a kind of damage: what
-- every hull's are, with that much less of its own kind let through.
local function leaning(resonance: { number }, kind: number?): { number }
  if kind == nil then
    return resonance
  end
  local out = table.clone(resonance)
  out[kind] *= 1 - AFFINITY
  return out
end

local types: { ShipType } = {
  -- The ship every pilot starts with, and gets again for nothing after
  -- losing one.
  {
    id = "frigate.courier", name = "Courier", class = "frigate", lineage = "", basePrice = 30000, volume = 2500,
    mass = 1030000, inertia = 3.4, maxVelocity = 355, warpSpeed = 5, radius = 40,
    shield = 280, armor = 240, hull = 290, shieldRecharge = 625,
    shieldResonance = SHIELD, armorResonance = ARMOR, hullResonance = HULL, signature = 37,
    -- (two guns, and a third high slot for what needs no hardpoint: the
    -- salvager a new pilot is taught with goes beside the guns, not in
    -- place of one. Character/Proof.spec flies that.)
    cpu = 155, powergrid = 44, highs = 3, mids = 2, lows = 1, turrets = 2, launchers = 0,
    capacitor = 250, capacitorRecharge = 165,
    scanResolution = 590, lockRange = 31000, maxTargets = 3, cargo = 250,
  },
  -- Lasers and armour.
  {
    id = "frigate.battleaxe", name = "Kethri Battleaxe", class = "frigate", lineage = "kethri", basePrice = 420000, volume = 2500,
    mass = 1120000, inertia = 3.2, maxVelocity = 340, warpSpeed = 5, radius = 42,
    shield = 310, armor = 415, hull = 350, shieldRecharge = 625,
    shieldResonance = SHIELD, armorResonance = ARMOR, hullResonance = HULL, signature = 36,
    cpu = 175, powergrid = 65, highs = 3, mids = 2, lows = 4, turrets = 3, launchers = 0,
    capacitor = 390, capacitorRecharge = 162,
    scanResolution = 610, lockRange = 37000, maxTargets = 4, cargo = 190,
  },
  {
    id = "industrial.hauler", name = "Mule Hauler", class = "industrial", lineage = "", basePrice = 600000, volume = 20000,
    mass = 12800000, inertia = 0.9, maxVelocity = 125, warpSpeed = 3.5, radius = 180,
    shield = 715, armor = 795, hull = 1000, shieldRecharge = 625,
    shieldResonance = SHIELD, armorResonance = ARMOR, hullResonance = HULL, signature = 195,
    cpu = 200, powergrid = 60, highs = 2, mids = 3, lows = 3, turrets = 1, launchers = 0,
    capacitor = 575, capacitorRecharge = 345,
    scanResolution = 85, lockRange = 45000, maxTargets = 2, cargo = 2250,
  },
  -- A freighter: the biggest hold there is, ten times a hauler's and
  -- more, and nothing else. No guns and nowhere to put one, no rigs, a
  -- few low slots, a great deal of hull, slow to turn, slow to warp and
  -- slow in it. Anybody's, as the Mule is. (The first of its class:
  -- the factions' own are not drawn yet.)
  {
    id = "freighter.dray", name = "Dray Freighter", class = "freighter", lineage = "", basePrice = 1200000000, volume = 1000000,
    mass = 920000000, inertia = 0.0625, maxVelocity = 65, warpSpeed = 1.5, radius = 1000,
    shield = 28000, armor = 28000, hull = 86500, shieldRecharge = 6000,
    shieldResonance = SHIELD, armorResonance = ARMOR, hullResonance = HULL, signature = 10500,
    cpu = 90, powergrid = 60, highs = 0, mids = 0, lows = 3, turrets = 0, launchers = 0,
    capacitor = 3500, capacitorRecharge = 215,
    scanResolution = 60, lockRange = 40000, maxTargets = 2, cargo = 435000,
    rigs = 0,
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

-- ---------------------------------------------------------------------
-- The factions' lines
--
-- Every faction has a hull of each class. A class has a standard hull
-- (below); a faction's is that, times the faction's character
-- (Data/Factions): so a Vessari hull has more armour than its class and
-- a Talmar one is faster, from frigate to battleship. The two frigates
-- written out above are their factions' own; the rest are made here.
--
-- What a class's standard hull is in space (the owner, 2026-11-18: "ship
-- stats need a LOT of adjustment", against the reference figures they
-- supplied): the middle hull of the reference's plain hulls of that
-- class, in its layers, speed, agility, mass, warp, signature, targeting,
-- capacitor, recharge and hold. Its shield and its armour are both the
-- mean of the reference's two, since the factions here do the leaning;
-- its hull is the reference's. A class the reference has two of here
-- (the two dreadnoughts) is the one it has; a class it has nothing like
-- (the ultracapital) stays the multiple of the supercarrier it was. A
-- freighter keeps its targeting and a supercarrier its lock range, a
-- barge its hold (the reference's keeps its ore elsewhere), and an
-- ultracapital its hold. Price, size, slots, hardpoints and fitting are
-- this game's own.

type Standard = {
  price: number, volume: number, mass: number, inertia: number, velocity: number, warp: number, radius: number,
  shield: number, armor: number, hull: number, recharge: number, signature: number,
  cpu: number, powergrid: number, highs: number, mids: number, lows: number, hardpoints: number,
  capacitor: number, capacitorRecharge: number, scan: number, lock: number, targets: number, cargo: number,
  skill: string, level: number,
  -- Its hardpoints are as many as it says, whoever builds it (a
  -- faction's yard gives or takes one on the classes that do not say).
  exact: boolean?,
}

local CLASS: { [string]: Standard } = {
  frigate = { price = 400000, volume = 2500, mass = 1080000, inertia = 3.3, velocity = 350, warp = 5, radius = 42,
    shield = 350, armor = 350, hull = 340, recharge = 625, signature = 36, cpu = 190, powergrid = 60,
    highs = 3, mids = 3, lows = 3, hardpoints = 3, capacitor = 330, capacitorRecharge = 160,
    scan = 630, lock = 35500, targets = 4, cargo = 190, skill = "frigates", level = 2 },
  destroyer = { price = 1500000, volume = 5000, mass = 1600000, inertia = 2.85, velocity = 250, warp = 4.5, radius = 75,
    shield = 800, armor = 800, hull = 800, recharge = 625, signature = 65, cpu = 300, powergrid = 115,
    highs = 7, mids = 3, lows = 3, hardpoints = 6, capacitor = 575, capacitorRecharge = 320,
    scan = 525, lock = 36000, targets = 6, cargo = 400, skill = "destroyers", level = 1 },
  cruiser = { price = 9000000, volume = 10000, mass = 11550000, inertia = 0.51, velocity = 230, warp = 4, radius = 150,
    shield = 1300, armor = 1300, hull = 1500, recharge = 1250, signature = 120, cpu = 450, powergrid = 1400,
    highs = 5, mids = 4, lows = 5, hardpoints = 4, capacitor = 1500, capacitorRecharge = 445,
    scan = 290, lock = 55000, targets = 7, cargo = 450, skill = "cruisers", level = 1 },
  battleship = { price = 150000000, volume = 50000, mass = 100250000, inertia = 0.119, velocity = 115, warp = 3, radius = 400,
    shield = 7700, armor = 7700, hull = 7700, recharge = 2500, signature = 440, cpu = 760, powergrid = 26000,
    highs = 8, mids = 5, lows = 6, hardpoints = 7, capacitor = 6000, capacitorRecharge = 1150,
    scan = 130, lock = 87000, targets = 7, cargo = 820, skill = "battleships", level = 1 },
  industrial = { price = 750000, volume = 20000, mass = 12800000, inertia = 0.9, velocity = 125, warp = 3.5, radius = 180,
    shield = 795, armor = 795, hull = 1000, recharge = 625, signature = 195, cpu = 210, powergrid = 65,
    highs = 2, mids = 3, lows = 3, hardpoints = 1, capacitor = 600, capacitorRecharge = 345,
    scan = 85, lock = 45000, targets = 2, cargo = 2700, skill = "industrials", level = 1 },

  -- The project owner's ladder above the battleship and beside it
  -- (2026-11-12): how big each is, how many hardpoints it has and what
  -- size of weapon they are for are the owner's. Every other figure is
  -- a first draft, set along the line the first five make. A size of
  -- weapon is not a rule of its own: a hull mounts what its powergrid
  -- will carry, and these are given the powergrid for what they are
  -- meant to mount and no more.
  --
  -- The two battlecruisers. The attack one is a cruiser's size and a
  -- little over with four of a battleship's guns: quick, far-reaching
  -- and thin-skinned. The other is twice a cruiser with eight of a
  -- cruiser's guns, and takes a beating.
  attackbattlecruiser = { price = 60000000, volume = 15000, mass = 15000000, inertia = 0.495, velocity = 225, warp = 3.5, radius = 200,
    shield = 1850, armor = 1850, hull = 1800, recharge = 1400, signature = 215, cpu = 550, powergrid = 15500,
    highs = 5, mids = 4, lows = 5, hardpoints = 4, capacitor = 2900, capacitorRecharge = 725,
    scan = 210, lock = 70000, targets = 7, cargo = 575, skill = "battlecruisers", level = 1, exact = true },
  battlecruiser = { price = 50000000, volume = 15000, mass = 12750000, inertia = 0.665, velocity = 160, warp = 3.5, radius = 300,
    shield = 4100, armor = 4100, hull = 4000, recharge = 1400, signature = 270, cpu = 670, powergrid = 2700,
    highs = 8, mids = 4, lows = 6, hardpoints = 8, capacitor = 2900, capacitorRecharge = 725,
    scan = 210, lock = 60000, targets = 7, cargo = 450, skill = "battlecruisers", level = 1, exact = true },
  -- The capitals. A carrier has no hardpoint: its high slots are for
  -- what needs none, and it fights with what it launches. A dreadnought
  -- is twenty hardpoints, with the powergrid for ten of a battleship's
  -- guns and ten of a cruiser's (and not for one of a siege
  -- dreadnought's). A siege dreadnought is four of the largest guns
  -- there are and the hull to carry them. A supercarrier is a carrier
  -- and more.
  carrier = { price = 1200000000, volume = 1000000, mass = 1235000000, inertia = 0.04, velocity = 80, warp = 1.5, radius = 1000,
    shield = 64500, armor = 64500, hull = 73000, recharge = 15000, signature = 9950, cpu = 1000, powergrid = 60000,
    highs = 6, mids = 6, lows = 6, hardpoints = 0, capacitor = 52500, capacitorRecharge = 4000,
    scan = 68, lock = 310000, targets = 14, cargo = 2700, skill = "carriers", level = 1, exact = true },
  dreadnought = { price = 2200000000, volume = 1300000, mass = 1260000000, inertia = 0.045, velocity = 75, warp = 1.5, radius = 1300,
    shield = 95500, armor = 95500, hull = 110000, recharge = 15000, signature = 11000, cpu = 1810, powergrid = 40500,
    highs = 20, mids = 7, lows = 8, hardpoints = 20, capacitor = 54500, capacitorRecharge = 4000,
    scan = 78, lock = 100000, targets = 7, cargo = 2550, skill = "dreadnoughts", level = 1, exact = true },
  siegedreadnought = { price = 1900000000, volume = 1000000, mass = 1260000000, inertia = 0.045, velocity = 75, warp = 1.5, radius = 950,
    shield = 95500, armor = 95500, hull = 110000, recharge = 15000, signature = 11000, cpu = 1200, powergrid = 650000,
    highs = 5, mids = 6, lows = 7, hardpoints = 4, capacitor = 54500, capacitorRecharge = 4000,
    scan = 78, lock = 100000, targets = 7, cargo = 2550, skill = "dreadnoughts", level = 1, exact = true },
  -- (what a fleet's barges bring it goes in its ore hold: Ships.ORE)
  capitalindustrial = { price = 900000000, volume = 800000, mass = 800000000, inertia = 0.07, velocity = 60, warp = 1.5, radius = 700,
    shield = 75000, armor = 75000, hull = 300000, recharge = 14400, signature = 11500, cpu = 800, powergrid = 20000,
    highs = 3, mids = 5, lows = 4, hardpoints = 0, capacitor = 67500, capacitorRecharge = 4500,
    scan = 75, lock = 200000, targets = 7, cargo = 40000, skill = "capital.industrials", level = 1, exact = true },
  supercarrier = { price = 6000000000, volume = 1500000, mass = 1675000000, inertia = 0.0355, velocity = 80, warp = 1.5, radius = 1300,
    shield = 380000, armor = 380000, hull = 260000, recharge = 20000, signature = 19000, cpu = 1400, powergrid = 90000,
    highs = 7, mids = 7, lows = 7, hardpoints = 0, capacitor = 80500, capacitorRecharge = 5050,
    scan = 62, lock = 200000, targets = 14, cargo = 1750, skill = "supercarriers", level = 1, exact = true },
}

-- A faction's own mining barge and freighter are the Quarry and the
-- Dray (below) as that faction builds them.
CLASS.barge = { price = 6000000, volume = 15000, mass = 17500000, inertia = 0.64, velocity = 125, warp = 3.5, radius = 160,
  shield = 3500, armor = 3500, hull = 4000, recharge = 1500, signature = 200, cpu = 320, powergrid = 160,
  highs = 3, mids = 2, lows = 2, hardpoints = 3, capacitor = 350, capacitorRecharge = 190,
  scan = 550, lock = 40000, targets = 6, cargo = 3500, skill = "mining", level = 4, exact = true }
-- (A carrier's size and about its price: the owner, 2026-11-16,
-- "Normally freighters should be carrier-sized and roughly the same
-- cost, with t2 jump freighters being 6-10 billion" (eight times this,
-- as every tech 2 hull is: 9.6 billion). They were 650 m and 60
-- million. Mine: as heavy as a carrier and as slow to align as before.)
CLASS.freighter = { price = 1200000000, volume = 1000000, mass = 920000000, inertia = 0.0625, velocity = 65, warp = 1.5, radius = 1000,
  shield = 28000, armor = 28000, hull = 86500, recharge = 6000, signature = 10500, cpu = 90, powergrid = 60,
  highs = 0, mids = 0, lows = 3, hardpoints = 0, capacitor = 3500, capacitorRecharge = 215,
  scan = 60, lock = 40000, targets = 2, cargo = 435000, skill = "freighters", level = 1, exact = true }
-- An ultracapital has no size of its own (each is the size its faction's
-- line says: the radius here is only what one is if nothing is said),
-- no hardpoint, and a bay for what it launches that is many times a
-- supercarrier's. (Every figure a first draft: the project owner's are
-- that it has no turrets and a huge fighter bay.)
CLASS.ultracapital = { price = 40000000000, volume = 12000000, mass = 8400000000, inertia = 0.012, velocity = 40, warp = 1.0, radius = 2000,
  shield = 1460000, armor = 1460000, hull = 990000, recharge = 20000, signature = 47500, cpu = 2400, powergrid = 300000,
  highs = 8, mids = 8, lows = 8, hardpoints = 0, capacitor = 250000, capacitorRecharge = 9000,
  scan = 30, lock = 250000, targets = 14, cargo = 40000, skill = "ultracapitals", level = 1, exact = true }
-- A mass-miner, beside a capital industrial: mining turrets where that
-- has no hardpoint (as many as its faction's line says), and the fitting
-- for them. (First figures.)
local MASS_MINER = { fitting = 1.6 }
-- The classes that work and do not fight: what hardpoints they have are
-- for tools and not for launchers, and their holds are as roomy as
-- their builders make holds.
local WORKING: { [string]: boolean } = { industrial = true, barge = true, freighter = true, capitalindustrial = true }
-- A combat hauler, beside a hauler: half the hold, twice and more the
-- hull under it, three hardpoints for guns and the fitting for them,
-- and dearer. (First figures.)
local COMBAT_HAULER = { cargo = 0.45, layers = 2.2, hardpoints = 3, fitting = 1.6, price = 2.5, slots = 1 }

-- The classes that are capitals: nobody has a tech 2 make of one, but
-- where a faction's line names one.
-- (a freighter among them: the owner, 2026-11-17, "freighters are caps
-- everywhere")
local CAPITAL: { [string]: boolean } = { carrier = true, dreadnought = true, siegedreadnought = true, capitalindustrial = true,
  supercarrier = true, ultracapital = true, freighter = true }

-- To two figures or so: nobody quotes a hull's armour to the hit point.
local function round(x: number): number
  local step = if x >= 100000 then 10000 elseif x >= 10000 then 500 elseif x >= 1000 then 50 elseif x >= 100 then 5 else 1
  return math.floor(x / step + 0.5) * step
end

-- What a gun of each size wants of a hull (small, medium, large, XL: a
-- beam laser's, the hungriest of the guns a faction's hulls are shown
-- with, and a little over), and what a launcher of each size does. A
-- hull whose line says how many hardpoints of each size it has is given
-- the fitting for a gun or a launcher on every one of them, over what
-- its class has. (Content.spec fits the Kethri's colony ship so.)
local GUN_GRID = { 13, 230, 3000, 155000 }
local GUN_CPU = { 19, 36, 56, 92 }
local RACK_GRID = { 7, 110, 1500, 100000 }
local RACK_CPU = { 22, 52, 62, 155 }

-- The room in an ultracapital's bay, m3 (Ships.BAY, below, has it by
-- class: here for the yards, which give a small one less).
local ULTRA_BAY = 40000

-- The room a logistics capital has for ships, m3 of packed hulls: one
-- carrier or siege dreadnought, or a score of battleships, or a fleet
-- of anything smaller. (A first figure.)
local SHIPBAY = 1200000

-- A hull of a class as a yard builds it: 'named' is what it is called,
-- and 'role' what it is beside the plain hull ("combat": a combat
-- hauler).
-- ('own' is how many hardpoints it has, where its faction's line says:
-- a mass-miner's mining turrets.)
-- ('sized' is its hardpoints by the size of weapon each is for, where
-- its faction's line says: so many small, medium, large and XL. Of each
-- size its builders make their share launchers, as of any hull.)
-- ('radius' is how big it is, where its faction's line says. An
-- ultracapital has no size of its own, and what the class is written
-- for is one of two kilometres: one that is smaller is that much less
-- of one in bulk, as the cube of its size. Its mass, its price, what it
-- takes to destroy, its capacitor, its hold and its bay are so much
-- less. The Vail's Archangel, a little over a kilometre, is a seventh
-- of the class: half as heavy again as the capital industrial it comes
-- of. A bigger one is as the class is: the Vessari's, the Kethri's.
-- A first rule, and not the owner's.)
local function yardHull(yard: Factions.Faction, class: string, named: string, role: string?, own: number?, sized: { number }?,
  radius: number?): ShipType
  local s = CLASS[class]
  local bulk = if class == "ultracapital" and radius and radius < s.radius then (radius / s.radius) ^ 3 else 1
  local gunGrid, gunCpu, racked = 0, 0, 0
  local guns: { number }?, racks: { number }? = nil, nil
  if sized then
    local turrets: { number }, launchers: { number } = {}, {}
    for size, count in sized do
      launchers[size] = if WORKING[class] then 0 else math.floor(count * yard.launchers + 0.5)
      turrets[size] = count - launchers[size]
      racked += launchers[size]
      gunGrid += turrets[size] * GUN_GRID[size] + launchers[size] * RACK_GRID[size]
      gunCpu += turrets[size] * GUN_CPU[size] + launchers[size] * RACK_CPU[size]
    end
    guns, racks = turrets, launchers
  end
  local combat = role == "combat"
  local working = WORKING[class] and not combat
  local hardpoints = own or (if combat then COMBAT_HAULER.hardpoints
    else s.hardpoints + (if class == "industrial" or s.exact then 0 else yard.hardpoints))
  local launchers = if working then 0 elseif sized then racked else math.floor(hardpoints * yard.launchers + 0.5)
  local layers = if combat then COMBAT_HAULER.layers else 1
  local fitting = if combat then COMBAT_HAULER.fitting elseif role == "miner" then MASS_MINER.fitting else 1
  -- (a pirate hull: the human hull of this class it was made out of,
  -- which is in the list already, the human factions coming first: the
  -- first plain one of its class they build)
  -- (or, where they say so, of a bigger class: cut down)
  local donor: string? = nil
  if yard.donors then
    local of = if yard.cut and yard.cut[class] then yard.cut[class] else class
    for _, t in types do
      if donor == nil and t.lineage == yard.donors[class] and t.class == of and t.tech ~= 2 and t.role == nil then
        donor = t.id
      end
    end
  end
  return {
    -- (a hull whose name begins "The" goes by that alone: "The Reaper")
    id = `{class}.{string.lower((string.gsub(named, "[^%a]", "")))}`,
    name = if string.sub(named, 1, 4) == "The " then named else `{yard.name} {named}`, class = class, lineage = yard.id,
    basePrice = round(s.price * yard.price * bulk * (if combat then COMBAT_HAULER.price else 1)), volume = s.volume,
    mass = round(s.mass * yard.mass * bulk), inertia = s.inertia, maxVelocity = round(s.velocity * yard.velocity),
    warpSpeed = s.warp, radius = radius or s.radius,
    shield = round(s.shield * yard.shield * layers * bulk), armor = round(s.armor * yard.armor * layers * bulk),
    hull = round(s.hull * yard.hull * layers * bulk),
    shieldRecharge = s.recharge, shieldResonance = leaning(SHIELD, yard.affinity), armorResonance = leaning(ARMOR, yard.affinity),
    hullResonance = leaning(HULL, yard.affinity), affinity = yard.affinity,
    signature = s.signature,
    cpu = round(s.cpu * yard.cpu * fitting + gunCpu), powergrid = round(s.powergrid * yard.powergrid * fitting + gunGrid),
    highs = math.max(s.highs, hardpoints) + (if sized then s.highs else 0),
    mids = math.max(if s.mids == 0 then 0 else 1, s.mids + (if s.mids == 0 then 0 else yard.mids) + (if combat then COMBAT_HAULER.slots else 0)),
    lows = math.max(1, s.lows + yard.lows + (if combat then COMBAT_HAULER.slots else 0)),
    turrets = hardpoints - launchers, launchers = launchers,
    capacitor = round(s.capacitor * yard.capacitor * bulk), capacitorRecharge = s.capacitorRecharge,
    scanResolution = s.scan, lockRange = round(s.lock * yard.lockRange), maxTargets = s.targets,
    cargo = round(s.cargo * bulk * (if WORKING[class] then yard.cargo else 1) * (if combat then COMBAT_HAULER.cargo else 1)),
    bay = if bulk < 1 then round(ULTRA_BAY * bulk) else nil,
    requires = if class == "barge" then { { skill = "mining", level = 4 }, { skill = "industrials", level = 1 } }
      else { { skill = s.skill, level = s.level } },
    foreign = if yard.kind ~= "human" then true else nil,
    -- (and so not to be bought: its drawings are to be found, Data/Blueprints)
    rare = if yard.kind ~= "human" then true else nil,
    donor = donor,
    role = role,
    rigs = if class == "freighter" then 0 else nil,
    guns = guns, racks = racks,
    armorMend = if yard.mends then yard.mends.armor else nil, hullMend = if yard.mends then yard.mends.hull else nil,
    -- (a logistics capital: a bay for hulls, and no ore hold)
    shipbay = if role == "transport" then SHIPBAY else nil, ore = if role == "transport" then 0 else nil,
  }
end

for _, yard in Factions.list do
  local line = yard.line
  if line then
    -- (hull by hull, as the faction's line names them: the tech 2 makes
    -- among them are made further down, of the hulls they are makes of)
    for _, named in line do
      if named.tech ~= 2 then
        local own = named.hardpoints
        local bySize: { number } = named.guns or {}
        for _, count in bySize do
          own = (own or 0) + count
        end
        local hull = yardHull(yard, named.class, named.name, named.role, own, named.guns, named.radius)
        hull.jump, hull.stealth, hull.rare = named.jump, named.stealth, named.rare or hull.rare
        -- (every plain hull of a people whose hulls all have a cloak of their own: the Drowned's)
        hull.cloak, hull.explorer = named.cloak or yard.cloaks, named.explorer
        hull.jumpField = named.jumpField
        hull.spinal = if named.spinal then bowRailgun(hull.class) else nil
        hull.refinery = named.refinery
        hull.interdictor, hull.ewar = named.interdictor, named.ewar
        -- (a hull written out by hand above, under the name the line has
        -- for it, is that hull: the Kethri's frigate)
        local written = false
        for _, t in types do
          written = written or t.id == hull.id
        end
        if not written then
          table.insert(types, hull)
        end
      end
    end
    continue
  end
  for _, class in Factions.CLASSES do
    local written = false
    for _, t in types do
      if t.lineage == yard.id and t.class == class then
        written = true
      end
    end
    if not written then
      table.insert(types, yardHull(yard, class, yard.hulls[class]))
    end
  end
end

-- What a pirate camp is built of (Tactical/Assault): things that stand
-- where they are put and do not fly, of the kind a ship is to everything
-- that locks, shoots and loots. Stores, small and large, which only
-- stand there; and gun emplacements, small and large, which fight.
-- Nobody sells them or has a blueprint for them. (Each takes about as
-- much destroying as a ship of the pirates' that is met beside it: a
-- cache a scout and a half, a battery a raider, a depot a destroyer and
-- a half, a redoubt a cruiser.)
for _, works in {
  { id = "works.cache", name = "Cache", radius = 70, shield = 250, armor = 600, hull = 700, signature = 250, launchers = 0, bulk = 1 },
  { id = "works.depot", name = "Depot", radius = 150, shield = 700, armor = 1800, hull = 2200, signature = 600, launchers = 0, bulk = 4 },
  { id = "works.battery", name = "Battery", radius = 60, shield = 350, armor = 500, hull = 600, signature = 180, launchers = 3, bulk = 1 },
  { id = "works.redoubt", name = "Redoubt", radius = 110, shield = 1000, armor = 1800, hull = 1800, signature = 420, launchers = 4, bulk = 3 },
  -- A station's batteries (Tactical/Batteries): they stand outside its
  -- field, where they are shot at as anything is. Each takes about as
  -- much destroying as a cruiser of the pirates' (mine: a pack has to
  -- mean it, and a lone frigate is a long time about it).
  { id = "works.battery.gun", name = "Gun Battery", radius = 60, shield = 1500, armor = 2500, hull = 2500, signature = 300, launchers = 0,
    turrets = 3, bulk = 2 },
  { id = "works.battery.missile", name = "Missile Battery", radius = 60, shield = 1500, armor = 2500, hull = 2500, signature = 300,
    launchers = 3, bulk = 2 },
} :: { { id: string, name: string, radius: number, shield: number, armor: number, hull: number, signature: number, launchers: number,
  turrets: number?, bulk: number } } do
  local turrets = works.turrets or 0
  table.insert(types, {
    id = works.id, name = works.name, class = "works", lineage = "", basePrice = 250000 * works.bulk, volume = 100000 * works.bulk,
    mass = 40000000 * works.bulk, inertia = 1, maxVelocity = 0, warpSpeed = 1, radius = works.radius,
    shield = works.shield, armor = works.armor, hull = works.hull, shieldRecharge = 900,
    shieldResonance = SHIELD, armorResonance = ARMOR, hullResonance = HULL, signature = works.signature,
    cpu = 600, powergrid = 2000, highs = works.launchers + turrets, mids = 2, lows = 3, turrets = turrets, launchers = works.launchers,
    capacitor = 2500, capacitorRecharge = 240,
    scanResolution = 320, lockRange = 60000, maxTargets = 3, cargo = 600 * works.bulk,
    restricted = true,
  })
end

-- What a defence job is to hold (Tactical/Assault): a survey rig, which
-- stands where it was put as a camp's works do, and is somebody's who
-- is nobody's enemy. A size for each level of the job: it has to stand
-- while the waves that level brings are seen off, and no longer (with
-- every one of them on it and nobody in their way, about six minutes).
-- (And it is bigger than the ships that level is flown in: it is what
-- the place is about.) Nobody sells one or has a blueprint for it.
for level, rig in {
  { name = "Small Survey Rig", radius = 120, shield = 900, armor = 1400, hull = 1700 },
  { name = "Survey Rig", radius = 180, shield = 2700, armor = 4300, hull = 5500 },
  { name = "Large Survey Rig", radius = 280, shield = 5000, armor = 8000, hull = 11000 },
  { name = "Great Survey Rig", radius = 420, shield = 10000, armor = 15000, hull = 20000 },
} do
  table.insert(types, {
    id = `works.rig.{level}`, name = rig.name, class = "works", lineage = "", basePrice = 500000 * level, volume = 100000 * level,
    mass = 40000000 * level, inertia = 1, maxVelocity = 0, warpSpeed = 1, radius = rig.radius,
    shield = rig.shield, armor = rig.armor, hull = rig.hull, shieldRecharge = 1800,
    shieldResonance = SHIELD, armorResonance = ARMOR, hullResonance = HULL, signature = 300 + 100 * level,
    cpu = 600, powergrid = 2000, highs = 0, mids = 2, lows = 3, turrets = 0, launchers = 0,
    capacitor = 2500, capacitorRecharge = 240,
    scanResolution = 320, lockRange = 60000, maxTargets = 3, cargo = 600,
    restricted = true,
  })
end

-- A tower of the pirates' own, holding a moon (Tactical/Keeps): about
-- half of a pilot's small one to bring down, and nobody's to build.
table.insert(types, {
  id = "works.keep", name = "Pirate Tower", class = "works", lineage = "", basePrice = 2000000, volume = 1000000,
  mass = 400000000, inertia = 1, maxVelocity = 0, warpSpeed = 1, radius = 300,
  shield = 60000, armor = 20000, hull = 20000, shieldRecharge = 10800,
  shieldResonance = SHIELD, armorResonance = ARMOR, hullResonance = HULL, signature = 2000,
  cpu = 600, powergrid = 2000, highs = 0, mids = 0, lows = 0, turrets = 0, launchers = 0,
  capacitor = 2500, capacitorRecharge = 240,
  scanResolution = 100, lockRange = 60000, maxTargets = 1, cargo = 0,
  restricted = true,
})

-- What stands for a pilot's control tower where it is shot at
-- (Assets/Starbases, Tactical/Raids): a thing at the tower's heart with
-- the tower's shield, armour and structure (Data/Structures), which
-- nobody flies, sells or builds. Its shield comes back in three hours.
for size, supply in Structures.SUPPLY do
  table.insert(types, {
    id = `works.tower.{size}`, name = `{({ "Small", "Medium", "Large" })[size]} Control Tower`, class = "works", lineage = "", basePrice = supply.basePrice, volume = 1000000,
    mass = 400000000 * size, inertia = 1, maxVelocity = 0, warpSpeed = 1, radius = 150 + 100 * size,
    shield = supply.shield, armor = supply.armor, hull = supply.hull, shieldRecharge = 10800,
    shieldResonance = SHIELD, armorResonance = ARMOR, hullResonance = HULL, signature = 2000 * size,
    cpu = 600, powergrid = 2000, highs = 0, mids = 0, lows = 0, turrets = 0, launchers = 0,
    capacitor = 2500, capacitorRecharge = 240,
    scanResolution = 100, lockRange = 60000, maxTargets = 1, cargo = 0,
    restricted = true,
  })
end

-- And the core of each people's tower: the baseline's of its size, with
-- every resistance of its people's layer so many points higher
-- (Structures.TOWER_RESIST, the owner's "+15 points").
for _, tower in Structures.towers do
  local function harder(resonance: { number }, layer: string): { number }
    if tower.tank ~= layer then
      return resonance
    end
    local out: { number } = {}
    for index, through in resonance do
      out[index] = math.max(0, through - tower.resist)
    end
    return out
  end
  local size = tower.size
  table.insert(types, {
    id = Structures.Core(tower), name = tower.name, class = "works", lineage = "", basePrice = tower.basePrice, volume = 1000000,
    mass = 400000000 * size, inertia = 1, maxVelocity = 0, warpSpeed = 1, radius = 150 + 100 * size,
    shield = tower.shield, armor = tower.armor, hull = tower.hull, shieldRecharge = 10800,
    shieldResonance = harder(SHIELD, "shield"), armorResonance = harder(ARMOR, "armor"), hullResonance = harder(HULL, "hull"),
    signature = 2000 * size,
    cpu = 600, powergrid = 2000, highs = 0, mids = 0, lows = 0, turrets = 0, launchers = 0,
    capacitor = 2500, capacitorRecharge = 240,
    scanResolution = 100, lockRange = 60000, maxTargets = 1, cargo = 0,
    restricted = true,
  })
end

-- And what an escort is to see through (Tactical/Assault): a tender,
-- which flies, slowly, and is rather less to shoot at than the rig of
-- its level: left to itself with those who come for it, it is lost more
-- often than not before it has flown the five and a half minutes it
-- has to. Nobody sells one or has a blueprint for it either.
for level, tender in {
  { name = "Light Tender", radius = 110, shield = 600, armor = 850, hull = 1050 },
  { name = "Tender", radius = 170, shield = 2100, armor = 3300, hull = 4100 },
  { name = "Heavy Tender", radius = 260, shield = 4400, armor = 7000, hull = 9600 },
  { name = "Great Tender", radius = 380, shield = 7200, armor = 10800, hull = 14000 },
} do
  table.insert(types, {
    id = `convoy.tender.{level}`, name = tender.name, class = "industrial", lineage = "", basePrice = 400000 * level,
    volume = 60000 * level, mass = 12000000, inertia = 1, maxVelocity = 90, warpSpeed = 3, radius = tender.radius,
    shield = tender.shield, armor = tender.armor, hull = tender.hull, shieldRecharge = 1800,
    shieldResonance = SHIELD, armorResonance = ARMOR, hullResonance = HULL, signature = 250 + 100 * level,
    cpu = 400, powergrid = 800, highs = 0, mids = 2, lows = 3, turrets = 0, launchers = 0,
    capacitor = 1500, capacitorRecharge = 240,
    scanResolution = 300, lockRange = 50000, maxTargets = 3, cargo = 4000 * level,
    restricted = true,
  })
end

-- Hulls no faction owns: anyone builds them.
table.insert(types, {
  id = "frigate.prospector", name = "Prospector", class = "frigate", lineage = "", basePrice = 180000, volume = 2500,
  mass = 1300000, inertia = 3.4, maxVelocity = 300, warpSpeed = 5, radius = 44,
  shield = 380, armor = 320, hull = 420, shieldRecharge = 625,
  shieldResonance = SHIELD, armorResonance = ARMOR, hullResonance = HULL, signature = 42,
  cpu = 160, powergrid = 30, highs = 2, mids = 2, lows = 2, turrets = 2, launchers = 0,
  capacitor = 380, capacitorRecharge = 180,
  scanResolution = 500, lockRange = 20000, maxTargets = 3, cargo = 480,
  requires = { { skill = "mining", level = 2 } },
})
table.insert(types, {
  id = "barge.quarry", name = "Quarry Barge", class = "barge", lineage = "", basePrice = 6000000, volume = 15000,
  mass = 9000000, inertia = 0.9, maxVelocity = 110, warpSpeed = 3.5, radius = 160,
  shield = 1800, armor = 1500, hull = 2600, shieldRecharge = 1100,
  shieldResonance = SHIELD, armorResonance = ARMOR, hullResonance = HULL, signature = 160,
  cpu = 320, powergrid = 160, highs = 3, mids = 2, lows = 2, turrets = 3, launchers = 0,
  capacitor = 1400, capacitorRecharge = 420,
  scanResolution = 200, lockRange = 25000, maxTargets = 3, cargo = 3500,
  requires = { { skill = "mining", level = 4 }, { skill = "industrials", level = 1 } },
})

-- What a drone flies as (Data/Drones): nobody boards one, and nobody
-- sells the hull apart from the drone.
table.insert(types, {
  id = "drone.hull.light", name = "Light Combat Drone", class = "drone", lineage = "", basePrice = 12000, volume = 5,
  mass = 300000, inertia = 3.0, maxVelocity = 520, warpSpeed = 5, radius = 5,
  shield = 40, armor = 60, hull = 80, shieldRecharge = 200,
  shieldResonance = SHIELD, armorResonance = ARMOR, hullResonance = HULL, signature = 15,
  cpu = 40, powergrid = 15, highs = 1, mids = 0, lows = 0, turrets = 1, launchers = 0,
  capacitor = 100, capacitorRecharge = 60,
  scanResolution = 800, lockRange = 30000, maxTargets = 1, cargo = 200,
  requires = { { skill = "drones", level = 1 } }, restricted = true, rigs = 0, drones = 0,
})
table.insert(types, {
  id = "drone.hull.medium", name = "Medium Combat Drone", class = "drone", lineage = "", basePrice = 45000, volume = 10,
  mass = 900000, inertia = 3.0, maxVelocity = 380, warpSpeed = 5, radius = 9,
  shield = 110, armor = 160, hull = 200, shieldRecharge = 300,
  shieldResonance = SHIELD, armorResonance = ARMOR, hullResonance = HULL, signature = 28,
  cpu = 80, powergrid = 260, highs = 1, mids = 0, lows = 0, turrets = 1, launchers = 0,
  capacitor = 300, capacitorRecharge = 120,
  scanResolution = 500, lockRange = 40000, maxTargets = 1, cargo = 400,
  requires = { { skill = "drones", level = 2 } }, restricted = true, rigs = 0, drones = 0,
})

-- What a mining drone and a repair drone fly as.
table.insert(types, {
  id = "drone.hull.mining", name = "Mining Drone", class = "drone", lineage = "", basePrice = 30000, volume = 10,
  mass = 600000, inertia = 3.0, maxVelocity = 420, warpSpeed = 5, radius = 8,
  shield = 60, armor = 80, hull = 120, shieldRecharge = 250,
  shieldResonance = SHIELD, armorResonance = ARMOR, hullResonance = HULL, signature = 22,
  cpu = 40, powergrid = 15, highs = 1, mids = 0, lows = 0, turrets = 1, launchers = 0,
  capacitor = 200, capacitorRecharge = 90,
  scanResolution = 600, lockRange = 20000, maxTargets = 1, cargo = 30,
  requires = { { skill = "drones", level = 1 } }, restricted = true, rigs = 0, drones = 0,
})
table.insert(types, {
  id = "drone.hull.repair", name = "Armor Repair Drone", class = "drone", lineage = "", basePrice = 60000, volume = 10,
  mass = 600000, inertia = 3.0, maxVelocity = 450, warpSpeed = 5, radius = 8,
  shield = 80, armor = 110, hull = 140, shieldRecharge = 250,
  shieldResonance = SHIELD, armorResonance = ARMOR, hullResonance = HULL, signature = 22,
  cpu = 40, powergrid = 15, highs = 1, mids = 0, lows = 0, turrets = 0, launchers = 0,
  capacitor = 260, capacitorRecharge = 80,
  scanResolution = 600, lockRange = 20000, maxTargets = 1, cargo = 5,
  requires = { { skill = "drones", level = 2 } }, restricted = true, rigs = 0, drones = 0,
})

-- ---------------------------------------------------------------------
-- Tech 2
--
-- The improved make of every hull of a human faction's line, and of
-- the two mining hulls: the same hull, rebuilt. It takes more of a
-- beating (three tenths more shield, armour and hull, and a quarter
-- less of every kind of damage gets through its shield and armour), has
-- a fifth more CPU, powergrid and capacitor to fit with, one slot more
-- (a low slot on a hull that is more armour than shield, else a mid),
-- sees farther and locks faster; and a hull that is for carrying
-- carries half as much again. It wants a good deal more skill
-- (Data/Skills). Nobody sells one: its blueprint is invented from the
-- plain hull's, and it is built of the plain hull and of what lawless
-- space has (Data/Blueprints, Assets/Industry).
-- What a tech 2 make is for beside that, where its faction's line says
-- (Data/Factions): to go unseen, with a cloak of its own or with one
-- fitted, or to explore. (Which hull is for what is the project owner's
-- word, 2026-11-13; one that is for nothing in particular is this
-- plain make and no more.)
--
-- A hull built for a cloak, which is one built to go unseen and one
-- built to explore: a cloaking device asks a tenth of the CPU and the
-- powergrid of it that it asks of another hull (Attributes.Needs; the
-- device is very dear to fit otherwise, Data/Modules). (The owner's
-- word, of the black ops haulers: "they just get fitting bonuses (e.g.
-- -90% cpu/pg) to make cloaks not prohibitively expensive to fit", and
-- of the exploration cruiser "cheaper to fit cloaks": that it is the
-- same tenth for both is a first figure.)
local CLOAK_FITTING = 0.1
-- An exploration hull beside: its scanner makes every scan of a signal
-- worth half as much again (Tactical/Sites); and its pilot has two more
-- codes in the buffer of a hack begun from it (Tactical/Hacking). (The
-- owner's word is "bonuses to probe scanning and hacking": the figures
-- are first ones.)
local EXPLORER = { scan = 1.5, hack = 2 }
-- And a probe launcher asks it for half the CPU and powergrid it asks of
-- another hull (Attributes.Needs; the owner, 2026-11-18: "Exploration
-- hulls get a fitting bonus for it". The half is mine).
local PROBE_FITTING = 0.5
-- An interdictor's field: so many times as wide, and as long, as
-- another hull's from the same launcher. And an electronic warfare
-- hull's work on another ship: from so many times as far, and so many
-- times as strong (a web that takes half of a ship's speed takes five
-- eighths of it from one; a painter that makes it a third bigger, five
-- twelfths; a jammer with a chance of a third, five twelfths). (The
-- owner named the two, 2026-11-17: these figures are first ones, and
-- mine.)
local INTERDICTOR = { radius = 1.5, lasts = 1.5 }
local EWAR = { range = 1.5, strength = 1.25 }
local TECH2 = { price = 8, layers = 1.3, resonance = 0.75, fitting = 1.2, velocity = 1.05, lock = 1.2, scan = 1.15, cargo = 1.5 }

local function tougher(resonance: { number }): { number }
  local out: { number } = {}
  for index, share in resonance do
    out[index] = share * TECH2.resonance
  end
  return out
end

-- The tech 2 make of a hull: 'id' and 'name' are its own.
local function rebuiltHull(base: ShipType, id: string, name: string): ShipType
  local mining = base.id == "frigate.prospector" or base.class == "barge"
  local hauler = WORKING[base.class] or mining
  local armoured = base.armor >= base.shield
  return {
    id = id, name = name, class = base.class, lineage = base.lineage,
    basePrice = base.basePrice * TECH2.price, volume = base.volume,
    mass = base.mass, inertia = base.inertia, maxVelocity = round(base.maxVelocity * TECH2.velocity),
    warpSpeed = base.warpSpeed, radius = base.radius,
    shield = round(base.shield * TECH2.layers), armor = round(base.armor * TECH2.layers), hull = round(base.hull * TECH2.layers),
    shieldRecharge = base.shieldRecharge, shieldResonance = tougher(base.shieldResonance),
    armorResonance = tougher(base.armorResonance), hullResonance = base.hullResonance,
    signature = base.signature,
    cpu = round(base.cpu * TECH2.fitting), powergrid = round(base.powergrid * TECH2.fitting),
    highs = base.highs, mids = base.mids + (if armoured then 0 else 1), lows = base.lows + (if armoured then 1 else 0),
    turrets = base.turrets, launchers = base.launchers,
    capacitor = round(base.capacitor * TECH2.fitting), capacitorRecharge = base.capacitorRecharge,
    scanResolution = round(base.scanResolution * TECH2.scan), lockRange = round(base.lockRange * TECH2.lock),
    maxTargets = base.maxTargets,
    cargo = if hauler then round(base.cargo * TECH2.cargo) else base.cargo,
    drones = base.drones, bay = base.bay, rigs = base.rigs, calibration = base.calibration,
    tech = 2, base = base.id, role = base.role,
    -- (and it is whose its base is: an alien hull's tech 2 make is no
    -- more to be had on a human market than the hull is; and it mends as
    -- that does)
    restricted = base.restricted, foreign = base.foreign, armorMend = base.armorMend, hullMend = base.hullMend,
    -- (and an alien people's is no more to be bought than its base is)
    rare = if base.foreign then true else nil,
    -- (and it leans as its base does: the resonances it was made from have that in them)
    affinity = base.affinity,
  }
end

-- The tech 2 makes a faction's line names: each a hull of its own, with
-- its own name, of the hull of the line it says.
for _, yard in Factions.list do
  local line: { Factions.Hull } = yard.line or {}
  for _, entry in line do
    if entry.tech == 2 then
      local base: ShipType? = nil
      for _, t in types do
        if t.lineage == yard.id and t.name == `{yard.name} {entry.of}` then
          base = t
        end
      end
      local from = assert(base, `{yard.name}'s {entry.name} is the tech 2 make of a hull they do not build`)
      local hull = rebuiltHull(from, `{entry.class}.{string.lower((string.gsub(entry.name, "[^%a]", "")))}`, `{yard.name} {entry.name}`)
      hull.jump, hull.stealth = entry.jump or from.jump, entry.stealth or from.stealth
      -- (the tech 2 make of a hull of a people whose plain hulls all
      -- have a cloak of their own has none, unless it is said to: the
      -- owner's, of the Drowned's two, "no builtin cloak")
      hull.cloak, hull.explorer = entry.cloak or (if yard.cloaks then nil else from.cloak), entry.explorer or from.explorer
      hull.jumpField = entry.jumpField or from.jumpField
      hull.spinal = if entry.spinal then bowRailgun(hull.class) else from.spinal
      hull.interdictor, hull.ewar = entry.interdictor or from.interdictor, entry.ewar or from.ewar
      -- (where the line gives it more hardpoints than its base has: as
      -- many more high slots, its builders' share of them launchers, and
      -- the powergrid and CPU for them as its base has for its own)
      local was = from.turrets + from.launchers
      if entry.hardpoints and entry.hardpoints ~= was and was > 0 then
        local now = entry.hardpoints
        local racks = math.floor(now * yard.launchers + 0.5)
        hull.turrets, hull.launchers = now - racks, racks
        hull.highs += now - was
        hull.powergrid = round(hull.powergrid * now / was)
        hull.cpu = round(hull.cpu * now / was)
      end
      table.insert(types, hull)
    end
  end
end
-- (No other hull has a tech 2 make. A module has its "II", and a ship
-- has not: a tech 2 ship is a hull of its own, made for something, that
-- comes of a plain one. The project owner's ruling, 2026-11-13.)

-- What a tech 2 drone flies as (Data/Drones) is another matter: a drone
-- has its "II" as a module has, and its hull is that drone's hull made
-- over in the same way, a tenth quicker. (Nobody boards it, sells it or
-- builds it apart, and it is not one of the tech 2 hulls above.)
for _, base in table.clone(types) do
  if base.class == "drone" then
    table.insert(types, {
      id = base.id .. ".ii", name = base.name .. " II", class = base.class :: string, lineage = base.lineage,
      basePrice = base.basePrice * 5, volume = base.volume,
      mass = base.mass, inertia = base.inertia, maxVelocity = round(base.maxVelocity * 1.1),
      warpSpeed = base.warpSpeed, radius = base.radius,
      shield = round(base.shield * TECH2.layers), armor = round(base.armor * TECH2.layers), hull = round(base.hull * TECH2.layers),
      shieldRecharge = base.shieldRecharge, shieldResonance = tougher(base.shieldResonance),
      armorResonance = tougher(base.armorResonance), hullResonance = base.hullResonance,
      signature = base.signature,
      cpu = round(base.cpu * TECH2.fitting), powergrid = round(base.powergrid * TECH2.fitting),
      highs = base.highs, mids = base.mids, lows = base.lows, turrets = base.turrets, launchers = base.launchers,
      capacitor = round(base.capacitor * TECH2.fitting), capacitorRecharge = base.capacitorRecharge,
      scanResolution = base.scanResolution, lockRange = base.lockRange, maxTargets = base.maxTargets, cargo = base.cargo,
      requires = base.requires, restricted = true, rigs = base.rigs, drones = base.drones,
    })
  end
end

-- What a fighter and a bomber fly as (Data/Drones): bigger, tougher and
-- quicker than any drone, and nobody's to board, sell or build apart.
-- (They have no tech 2 make. First figures.)
table.insert(types, {
  id = "drone.hull.fighter", name = "Fighter", class = "drone", lineage = "", basePrice = 4000000, volume = 150,
  mass = 2500000, inertia = 2.0, maxVelocity = 700, warpSpeed = 5, radius = 14,
  shield = 500, armor = 450, hull = 550, shieldRecharge = 400,
  shieldResonance = SHIELD, armorResonance = ARMOR, hullResonance = HULL, signature = 45,
  cpu = 100, powergrid = 100, highs = 1, mids = 0, lows = 0, turrets = 1, launchers = 0,
  capacitor = 600, capacitorRecharge = 150,
  scanResolution = 450, lockRange = 60000, maxTargets = 1, cargo = 4000,
  restricted = true, rigs = 0, drones = 0,
})
table.insert(types, {
  id = "drone.hull.bomber", name = "Bomber", class = "drone", lineage = "", basePrice = 12000000, volume = 300,
  mass = 6000000, inertia = 2.0, maxVelocity = 420, warpSpeed = 5, radius = 22,
  shield = 900, armor = 900, hull = 1100, shieldRecharge = 600,
  shieldResonance = SHIELD, armorResonance = ARMOR, hullResonance = HULL, signature = 80,
  cpu = 100, powergrid = 100, highs = 1, mids = 0, lows = 0, turrets = 0, launchers = 1,
  capacitor = 900, capacitorRecharge = 200,
  scanResolution = 300, lockRange = 90000, maxTargets = 1, cargo = 4000,
  restricted = true, rigs = 0, drones = 0,
})

-- A human faction's hull that was written out by hand, and not built
-- from its faction's figures, leans as its faction does all the same
-- (and so does the tech 2 make of one).
for _, hull in types do
  local faction = Factions.byId[hull.lineage]
  if faction and faction.affinity and hull.affinity == nil then
    hull.affinity = faction.affinity
    hull.shieldResonance = leaning(hull.shieldResonance, faction.affinity)
    hull.armorResonance = leaning(hull.armorResonance, faction.affinity)
    hull.hullResonance = leaning(hull.hullResonance, faction.affinity)
  end
end

-- What a drone, a fighter and a bomber take to destroy is half as much
-- again as it was (2026-11-18): a ship's weapons hit half as hard again
-- since then (Data/Modules' WEAPON_DAMAGE), and a drone, which carries
-- what it did, lasts as long as it did under them.
for _, t in types do
  if t.class == "drone" then
    t.shield, t.armor, t.hull = round(t.shield * 1.5), round(t.armor * 1.5), round(t.hull * 1.5)
  end
end

-- Each hull's own bonuses (Data/HullBonuses), and every hull they are
-- written for is one there is.
do
  local known: { [string]: boolean } = {}
  for _, t in types do
    t.bonuses = HullBonuses.byHull[t.id]
    known[t.id] = true
  end
  for id in HullBonuses.byHull do
    assert(known[id], `bonuses for a hull there is not: {id}`)
  end
end

local Ships = { list = types, byId = {} :: { [string]: ShipType } }
-- What an exploration hull has over another, and what share of a
-- cloaking device's fitting a hull built for a cloak asks (above, at
-- the tech 2 makes).
Ships.EXPLORER = EXPLORER
Ships.INTERDICTOR = INTERDICTOR
Ships.EWAR = EWAR
Ships.CLOAK_FITTING = CLOAK_FITTING
Ships.PROBE_FITTING = PROBE_FITTING

-- The classes with a bay for fighters, and what each launches from it
-- (the project owner's ladder: a carrier fighters, a supercarrier and
-- an ultracapital fighters and bombers).
Ships.CRAFT = {
  carrier = { fighter = true },
  supercarrier = { fighter = true, bomber = true },
  ultracapital = { fighter = true, bomber = true },
} :: { [string]: { [string]: boolean } }

Ships.RIGS = 3
Ships.CALIBRATION = 400
-- Drones a hull controls, by its class.
-- (A carrier's are what it fights with, and a capital industrial's what
-- it works with: they control twice a battleship's, a supercarrier
-- three times, and have the bays for many times as many. A fighter or
-- a bomber is one of what a hull controls, as a drone is: Ships.CRAFT,
-- Tactical/Drones.)
Ships.DRONES = { frigate = 1, destroyer = 2, cruiser = 4, battleship = 5, industrial = 2, barge = 3,
  attackbattlecruiser = 2, battlecruiser = 5, carrier = 10, dreadnought = 5, siegedreadnought = 5, capitalindustrial = 10,
  supercarrier = 15, ultracapital = 25 } :: { [string]: number }
-- And the room in its drone bay, m3: what it controls, and spares.
Ships.BAY = { frigate = 10, destroyer = 25, cruiser = 50, battleship = 125, industrial = 25, barge = 50,
  attackbattlecruiser = 25, battlecruiser = 75, carrier = 2500, dreadnought = 250, siegedreadnought = 250, capitalindustrial = 1000,
  supercarrier = 6000, ultracapital = ULTRA_BAY } :: { [string]: number }
-- And the room in its ore hold, m3, for the classes that have one: a
-- capital industrial's is seventy of a mining barge's holds. (The
-- reference's, 2026-11-18.)
Ships.ORE = { capitalindustrial = 250000 } :: { [string]: number }
-- (And a logistics capital's bay for ships: above, at the yards.)
Ships.SHIPBAY = SHIPBAY
-- Whether a class is a capital.
Ships.AFFINITY = AFFINITY

-- How much of a kind of damage (1 EM, 2 thermal, 3 kinetic, 4
-- explosive) a hull's weapons deal, as a share of what they would on a
-- hull that leans to nothing: more of the kind it leans to.
function Ships.Dealt(hull: ShipType, kind: number): number
  return if hull.affinity == kind then 1 + AFFINITY else 1
end

-- What a class's standard hull takes to destroy, layer by layer, before
-- any faction's yard has had it: what its own hulls' leanings are seen
-- against.
function Ships.Standard(class: string): { shield: number, armor: number, hull: number }?
  local s = CLASS[class]
  return if s then { shield = s.shield, armor = s.armor, hull = s.hull } else nil
end

-- What a hull's bonuses come to on something (Data/HullBonuses: 'on',
-- 'attribute', and a weapon's family or module where it matters), for a
-- pilot with these skill levels (nil: none, and only the role bonuses).
-- 1 where it has none.
function Ships.Bonus(hull: ShipType?, on: string, attribute: string, levels: { [string]: number }?, family: string?, module: string?): number
  local bonuses = if hull then hull.bonuses else nil
  if bonuses == nil then
    return 1
  end
  local out = 1
  for _, b in bonuses do
    if b.on == on and b.attribute == attribute and (b.module == nil or b.module == module)
      and (b.family == nil or b.family == family or (b.family == "turret" and family ~= nil and family ~= "missile")) then
      local level = if b.skill then (if levels then levels[b.skill] or 0 else 0) else 1
      out *= 1 + b.per * level
    end
  end
  return out
end

-- Whether no electronic warfare touches a hull of a class (Data/HullBonuses).
function Ships.Immune(hull: ShipType?): boolean
  return hull ~= nil and HullBonuses.IMMUNE[hull.class] == true
end

function Ships.Capital(class: string): boolean
  return CAPITAL[class] == true
end
-- What a class is called, one of them and several: for a list of hulls,
-- or a sheet of one.
Ships.CLASS_NAMES = {
  frigate = { "Frigate", "Frigates" }, destroyer = { "Destroyer", "Destroyers" }, cruiser = { "Cruiser", "Cruisers" },
  attackbattlecruiser = { "Attack Battlecruiser", "Attack Battlecruisers" }, battlecruiser = { "Battlecruiser", "Battlecruisers" },
  battleship = { "Battleship", "Battleships" }, carrier = { "Carrier", "Carriers" }, dreadnought = { "Dreadnought", "Dreadnoughts" },
  siegedreadnought = { "Siege Dreadnought", "Siege Dreadnoughts" }, supercarrier = { "Supercarrier", "Supercarriers" },
  ultracapital = { "Ultracapital", "Ultracapitals" },
  industrial = { "Industrial", "Industrials" }, capitalindustrial = { "Capital Industrial", "Capital Industrials" },
  freighter = { "Freighter", "Freighters" }, barge = { "Mining Barge", "Mining Barges" }, capsule = { "Capsule", "Capsules" },
} :: { [string]: { string } }

for _, t in types do
  Ships.byId[t.id] = t
  t.rigs = t.rigs or (if t.class == "capsule" then 0 else Ships.RIGS)
  t.drones = t.drones or Ships.DRONES[t.class] or 0
  t.bay = t.bay or Ships.BAY[t.class] or 0
  t.ore = t.ore or Ships.ORE[t.class] or 0
  t.calibration = t.calibration or Ships.CALIBRATION
end

-- The size of rig a hull takes (Data/Modules): 1 for a frigate or a
-- destroyer, 2 for a cruiser, a hauler or a barge, 3 for a battleship;
-- 0 for what takes none.
-- (a battlecruiser of either kind takes a cruiser's, and a capital a
-- battleship's: there is no size of rig above that yet)
local RIG_SIZE: { [string]: number } = { frigate = 1, destroyer = 1, cruiser = 2, industrial = 2, barge = 2, battleship = 3,
  attackbattlecruiser = 2, battlecruiser = 2, carrier = 3, dreadnought = 3, siegedreadnought = 3, capitalindustrial = 3,
  supercarrier = 3, ultracapital = 3 }
function Ships.RigSize(t: ShipType): number
  return RIG_SIZE[t.class] or 0
end

-- The frigate a pilot begins in, where a people's space is where they
-- begin: that people's own frigate, the first of its plain ones. (The
-- owner's, 2026-11-14: a pilot begins in a cheaply fitted frigate of the
-- people about them, and not in the Courier, which nobody's yards
-- build.) The Courier, where nobody builds one, or they keep theirs to
-- themselves.
function Ships.Starter(faction: string): string
  for _, hull in Ships.list do
    if hull.class == "frigate" and hull.lineage == faction and faction ~= "" and hull.tech ~= 2 and not hull.restricted then
      return hull.id
    end
  end
  return "frigate.courier"
end

-- The tech 2 make of a hull, if it has one.
function Ships.Improved(id: string): ShipType?
  -- (the one its faction's line names, which is called what it is called;
  -- the first, where it names more than one)
  return Ships.ImprovedAll(id)[1]
end

-- Every tech 2 make of a hull, in the order its faction's line names
-- them: the Vessari's Ouyou has two, the Hoshizora and the Raiden.
function Ships.ImprovedAll(id: string): { ShipType }
  local out: { ShipType } = {}
  for _, hull in Ships.list do
    if hull.tech == 2 and hull.base == id then
      table.insert(out, hull)
    end
  end
  return out
end

-- Seconds; see the note on agility above.
function Ships.TimeConstant(t: ShipType): number
  return t.inertia * t.mass / 1e6
end

return Ships
