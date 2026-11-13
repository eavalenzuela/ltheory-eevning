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
local Structures = require("@lt/Core/Data/Structures")

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
  -- Rig slots, and the calibration the rigs in them share (Data/Modules).
  -- Every hull but the capsule has three and 400: given below, to all.
  rigs: number?,
  calibration: number?,
  turrets: number,        -- hardpoints
  launchers: number,
  capacitor: number,      -- GJ
  capacitorRecharge: number, -- s
  -- targeting
  scanResolution: number, -- mm; higher locks faster
  lockRange: number,      -- m
  maxTargets: number,
  cargo: number,          -- m3
  -- Skills a pilot needs to board it. (Where absent, Data/Skills says.)
  requires: { { skill: string, level: number } }?,
  -- Not sold on an ordinary market, and with no blueprint to be had
  -- there: a pirate's hull, or an alien one.
  restricted: boolean?,
  -- A pirate hull: the hull it was made out of.
  donor: string?,
  -- 2 for a tech 2 hull: the improved make of the hull 'base', which it
  -- is built from (below).
  tech: number?,
  base: string?,
  -- What it is beside the plain hull of its class, where a faction's
  -- line says (Data/Factions): "combat" for a combat hauler; that it has
  -- a jump drive; that it is built to go unseen. (The last two are
  -- marked and not yet made.)
  role: string?,
  jump: boolean?,
  stealth: boolean?,
}

local SHIELD = { 1.0, 0.8, 0.6, 0.5 }
local ARMOR = { 0.5, 0.65, 0.75, 0.9 }
local HULL = { 0.67, 0.67, 0.67, 0.67 }

local types: { ShipType } = {
  -- The ship every pilot starts with, and gets again for nothing after
  -- losing one.
  {
    id = "frigate.courier", name = "Courier", class = "frigate", lineage = "", basePrice = 30000, volume = 2500,
    mass = 1100000, inertia = 3.2, maxVelocity = 360, warpSpeed = 5, radius = 40,
    shield = 350, armor = 300, hull = 300, shieldRecharge = 625,
    shieldResonance = SHIELD, armorResonance = ARMOR, hullResonance = HULL, signature = 38,
    -- (two guns, and a third high slot for what needs no hardpoint: the
    -- salvager a new pilot is taught with goes beside the guns, not in
    -- place of one. Character/Proof.spec flies that.)
    cpu = 110, powergrid = 32, highs = 3, mids = 2, lows = 1, turrets = 2, launchers = 0,
    capacitor = 260, capacitorRecharge = 190,
    scanResolution = 580, lockRange = 22000, maxTargets = 3, cargo = 180,
  },
  -- Lasers and armour.
  {
    id = "frigate.lancer", name = "Kethri Lancer", class = "frigate", lineage = "kethri", basePrice = 420000, volume = 2500,
    mass = 1190000, inertia = 3.0, maxVelocity = 345, warpSpeed = 5, radius = 42,
    shield = 390, armor = 520, hull = 360, shieldRecharge = 625,
    shieldResonance = SHIELD, armorResonance = ARMOR, hullResonance = HULL, signature = 37,
    cpu = 125, powergrid = 48, highs = 3, mids = 2, lows = 4, turrets = 3, launchers = 0,
    capacitor = 400, capacitorRecharge = 187,
    scanResolution = 600, lockRange = 26000, maxTargets = 4, cargo = 135,
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
  -- A freighter: the biggest hold there is, ten times a hauler's and
  -- more, and nothing else. No guns and nowhere to put one, no rigs, a
  -- few low slots, a great deal of hull, slow to turn, slow to warp and
  -- slow in it. Anybody's, as the Mule is. (The first of its class:
  -- the factions' own are not drawn yet.)
  {
    id = "freighter.dray", name = "Dray Freighter", class = "freighter", lineage = "", basePrice = 60000000, volume = 250000,
    mass = 300000000, inertia = 0.12, maxVelocity = 75, warpSpeed = 1.5, radius = 650,
    shield = 6000, armor = 9000, hull = 38000, shieldRecharge = 3000,
    shieldResonance = SHIELD, armorResonance = ARMOR, hullResonance = HULL, signature = 900,
    cpu = 90, powergrid = 60, highs = 0, mids = 0, lows = 3, turrets = 0, launchers = 0,
    capacitor = 6000, capacitorRecharge = 1200,
    scanResolution = 60, lockRange = 40000, maxTargets = 2, cargo = 40000,
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
  frigate = { price = 400000, volume = 2500, mass = 1150000, inertia = 3.1, velocity = 355, warp = 5, radius = 42,
    shield = 440, armor = 440, hull = 350, recharge = 625, signature = 37, cpu = 135, powergrid = 44,
    highs = 3, mids = 3, lows = 3, hardpoints = 3, capacitor = 340, capacitorRecharge = 185,
    scan = 620, lock = 25000, targets = 4, cargo = 135, skill = "frigates", level = 2 },
  destroyer = { price = 1500000, volume = 5000, mass = 1700000, inertia = 2.7, velocity = 265, warp = 4.5, radius = 75,
    shield = 850, armor = 850, hull = 750, recharge = 800, signature = 72, cpu = 200, powergrid = 85,
    highs = 7, mids = 3, lows = 3, hardpoints = 6, capacitor = 700, capacitorRecharge = 270,
    scan = 480, lock = 40000, targets = 6, cargo = 380, skill = "destroyers", level = 1 },
  cruiser = { price = 9000000, volume = 10000, mass = 11500000, inertia = 0.5, velocity = 215, warp = 3, radius = 150,
    shield = 2300, armor = 2300, hull = 2100, recharge = 1250, signature = 125, cpu = 380, powergrid = 900,
    highs = 5, mids = 4, lows = 5, hardpoints = 4, capacitor = 1500, capacitorRecharge = 480,
    scan = 290, lock = 55000, targets = 6, cargo = 450, skill = "cruisers", level = 1 },
  battleship = { price = 150000000, volume = 50000, mass = 100000000, inertia = 0.13, velocity = 115, warp = 2, radius = 400,
    shield = 7200, armor = 7200, hull = 7000, recharge = 2500, signature = 400, cpu = 620, powergrid = 13000,
    highs = 8, mids = 5, lows = 6, hardpoints = 7, capacitor = 5500, capacitorRecharge = 1100,
    scan = 110, lock = 85000, targets = 7, cargo = 700, skill = "battleships", level = 1 },
  industrial = { price = 750000, volume = 20000, mass = 11000000, inertia = 1.0, velocity = 130, warp = 4.5, radius = 180,
    shield = 1000, armor = 1100, hull = 1500, recharge = 900, signature = 180, cpu = 210, powergrid = 65,
    highs = 2, mids = 3, lows = 3, hardpoints = 1, capacitor = 520, capacitorRecharge = 300,
    scan = 150, lock = 30000, targets = 2, cargo = 4600, skill = "industrials", level = 1 },

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
  attackbattlecruiser = { price = 60000000, volume = 15000, mass = 15000000, inertia = 0.45, velocity = 195, warp = 2.8, radius = 200,
    shield = 3200, armor = 3200, hull = 3000, recharge = 1500, signature = 230, cpu = 480, powergrid = 8600,
    highs = 5, mids = 4, lows = 5, hardpoints = 4, capacitor = 3600, capacitorRecharge = 800,
    scan = 240, lock = 80000, targets = 6, cargo = 500, skill = "battlecruisers", level = 1, exact = true },
  battlecruiser = { price = 50000000, volume = 15000, mass = 35000000, inertia = 0.28, velocity = 160, warp = 2.5, radius = 300,
    shield = 4800, armor = 4800, hull = 4500, recharge = 1800, signature = 270, cpu = 560, powergrid = 1900,
    highs = 8, mids = 4, lows = 6, hardpoints = 8, capacitor = 3200, capacitorRecharge = 700,
    scan = 210, lock = 65000, targets = 7, cargo = 600, skill = "battlecruisers", level = 1, exact = true },
  -- The capitals. A carrier has no hardpoint: its high slots are for
  -- what needs none, and it fights with what it launches. A dreadnought
  -- is twenty hardpoints, with the powergrid for ten of a battleship's
  -- guns and ten of a cruiser's (and not for one of a siege
  -- dreadnought's). A siege dreadnought is four of the largest guns
  -- there are and the hull to carry them. A supercarrier is a carrier
  -- and more.
  carrier = { price = 1200000000, volume = 1000000, mass = 1100000000, inertia = 0.035, velocity = 75, warp = 1.5, radius = 1000,
    shield = 70000, armor = 70000, hull = 65000, recharge = 6000, signature = 3200, cpu = 1000, powergrid = 60000,
    highs = 6, mids = 6, lows = 6, hardpoints = 0, capacitor = 45000, capacitorRecharge = 3600,
    scan = 60, lock = 180000, targets = 10, cargo = 6000, skill = "carriers", level = 1, exact = true },
  dreadnought = { price = 2200000000, volume = 1300000, mass = 1600000000, inertia = 0.03, velocity = 60, warp = 1.4, radius = 1300,
    shield = 110000, armor = 110000, hull = 100000, recharge = 7000, signature = 4200, cpu = 1500, powergrid = 23000,
    highs = 20, mids = 7, lows = 8, hardpoints = 20, capacitor = 60000, capacitorRecharge = 4200,
    scan = 55, lock = 130000, targets = 10, cargo = 5000, skill = "dreadnoughts", level = 1, exact = true },
  siegedreadnought = { price = 1900000000, volume = 1000000, mass = 1300000000, inertia = 0.035, velocity = 65, warp = 1.4, radius = 950,
    shield = 85000, armor = 85000, hull = 80000, recharge = 6500, signature = 3400, cpu = 1100, powergrid = 410000,
    highs = 5, mids = 6, lows = 7, hardpoints = 4, capacitor = 70000, capacitorRecharge = 4500,
    scan = 50, lock = 160000, targets = 8, cargo = 5000, skill = "dreadnoughts", level = 1, exact = true },
  -- (its hold is for what a fleet's barges bring it: that hold, and the
  -- bringing, are not made yet)
  capitalindustrial = { price = 900000000, volume = 800000, mass = 900000000, inertia = 0.045, velocity = 70, warp = 1.6, radius = 700,
    shield = 40000, armor = 45000, hull = 60000, recharge = 5000, signature = 2800, cpu = 800, powergrid = 20000,
    highs = 3, mids = 5, lows = 4, hardpoints = 0, capacitor = 30000, capacitorRecharge = 3200,
    scan = 70, lock = 120000, targets = 8, cargo = 30000, skill = "capital.industrials", level = 1, exact = true },
  supercarrier = { price = 6000000000, volume = 1500000, mass = 1800000000, inertia = 0.03, velocity = 55, warp = 1.3, radius = 1300,
    shield = 180000, armor = 180000, hull = 170000, recharge = 9000, signature = 4800, cpu = 1400, powergrid = 90000,
    highs = 7, mids = 7, lows = 7, hardpoints = 0, capacitor = 80000, capacitorRecharge = 5000,
    scan = 45, lock = 200000, targets = 12, cargo = 9000, skill = "supercarriers", level = 1, exact = true },
}

-- A faction's own mining barge and freighter are the Quarry and the
-- Dray (below) as that faction builds them.
CLASS.barge = { price = 6000000, volume = 15000, mass = 9000000, inertia = 0.9, velocity = 110, warp = 3.5, radius = 160,
  shield = 1800, armor = 1500, hull = 2600, recharge = 1100, signature = 160, cpu = 320, powergrid = 160,
  highs = 3, mids = 2, lows = 2, hardpoints = 3, capacitor = 1400, capacitorRecharge = 420,
  scan = 200, lock = 25000, targets = 3, cargo = 3500, skill = "mining", level = 4, exact = true }
CLASS.freighter = { price = 60000000, volume = 250000, mass = 300000000, inertia = 0.12, velocity = 75, warp = 1.5, radius = 650,
  shield = 6000, armor = 9000, hull = 38000, recharge = 3000, signature = 900, cpu = 90, powergrid = 60,
  highs = 0, mids = 0, lows = 3, hardpoints = 0, capacitor = 6000, capacitorRecharge = 1200,
  scan = 60, lock = 40000, targets = 2, cargo = 40000, skill = "freighters", level = 1, exact = true }
-- An ultracapital has no size of its own (each is the size its faction's
-- line says: the radius here is only what one is if nothing is said),
-- no hardpoint, and a bay for what it launches that is many times a
-- supercarrier's. (Every figure a first draft: the project owner's are
-- that it has no turrets and a huge fighter bay.)
CLASS.ultracapital = { price = 40000000000, volume = 12000000, mass = 9000000000, inertia = 0.012, velocity = 40, warp = 1.0, radius = 2000,
  shield = 700000, armor = 700000, hull = 650000, recharge = 20000, signature = 12000, cpu = 2400, powergrid = 300000,
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
local CAPITAL: { [string]: boolean } = { carrier = true, dreadnought = true, siegedreadnought = true, capitalindustrial = true,
  supercarrier = true, ultracapital = true }

-- To two figures or so: nobody quotes a hull's armour to the hit point.
local function round(x: number): number
  local step = if x >= 100000 then 10000 elseif x >= 10000 then 500 elseif x >= 1000 then 50 elseif x >= 100 then 5 else 1
  return math.floor(x / step + 0.5) * step
end

-- A hull of a class as a yard builds it: 'named' is what it is called,
-- and 'role' what it is beside the plain hull ("combat": a combat
-- hauler).
-- ('own' is how many hardpoints it has, where its faction's line says:
-- a mass-miner's mining turrets.)
local function yardHull(yard: Factions.Faction, class: string, named: string, role: string?, own: number?): ShipType
  local s = CLASS[class]
  local combat = role == "combat"
  local working = WORKING[class] and not combat
  local hardpoints = own or (if combat then COMBAT_HAULER.hardpoints
    else s.hardpoints + (if class == "industrial" or s.exact then 0 else yard.hardpoints))
  local launchers = if working then 0 else math.floor(hardpoints * yard.launchers + 0.5)
  local layers = if combat then COMBAT_HAULER.layers else 1
  local fitting = if combat then COMBAT_HAULER.fitting elseif role == "miner" then MASS_MINER.fitting else 1
  -- (a pirate hull: the human hull of this class it was made out of,
  -- which is in the list already, the human factions coming first: the
  -- first plain one of its class they build)
  local donor: string? = nil
  if yard.donors then
    for _, t in types do
      if donor == nil and t.lineage == yard.donors[class] and t.class == class and t.tech ~= 2 and t.role == nil then
        donor = t.id
      end
    end
  end
  return {
    id = `{class}.{string.lower((string.gsub(named, "[^%a]", "")))}`, name = `{yard.name} {named}`, class = class, lineage = yard.id,
    basePrice = round(s.price * yard.price * (if combat then COMBAT_HAULER.price else 1)), volume = s.volume,
    mass = round(s.mass * yard.mass), inertia = s.inertia, maxVelocity = round(s.velocity * yard.velocity),
    warpSpeed = s.warp, radius = s.radius,
    shield = round(s.shield * yard.shield * layers), armor = round(s.armor * yard.armor * layers),
    hull = round(s.hull * yard.hull * layers),
    shieldRecharge = s.recharge, shieldResonance = SHIELD, armorResonance = ARMOR, hullResonance = HULL,
    signature = s.signature,
    cpu = round(s.cpu * yard.cpu * fitting), powergrid = round(s.powergrid * yard.powergrid * fitting),
    highs = math.max(s.highs, hardpoints),
    mids = math.max(if s.mids == 0 then 0 else 1, s.mids + (if s.mids == 0 then 0 else yard.mids) + (if combat then COMBAT_HAULER.slots else 0)),
    lows = math.max(1, s.lows + yard.lows + (if combat then COMBAT_HAULER.slots else 0)),
    turrets = hardpoints - launchers, launchers = launchers,
    capacitor = round(s.capacitor * yard.capacitor), capacitorRecharge = s.capacitorRecharge,
    scanResolution = s.scan, lockRange = round(s.lock * yard.lockRange), maxTargets = s.targets,
    cargo = round(s.cargo * (if WORKING[class] then yard.cargo else 1) * (if combat then COMBAT_HAULER.cargo else 1)),
    requires = if class == "barge" then { { skill = "mining", level = 4 }, { skill = "industrials", level = 1 } }
      else { { skill = s.skill, level = s.level } },
    restricted = if yard.kind ~= "human" then true else nil,
    donor = donor,
    role = role,
    rigs = if class == "freighter" then 0 else nil,
  }
end

for _, yard in Factions.list do
  local line = yard.line
  if line then
    -- (hull by hull, as the faction's line names them: the tech 2 makes
    -- among them are made further down, of the hulls they are makes of)
    for _, named in line do
      if named.tech ~= 2 then
        local hull = yardHull(yard, named.class, named.name, named.role, named.hardpoints)
        hull.jump, hull.stealth = named.jump, named.stealth
        hull.radius = named.radius or hull.radius
        table.insert(types, hull)
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
} do
  table.insert(types, {
    id = works.id, name = works.name, class = "works", lineage = "", basePrice = 250000 * works.bulk, volume = 100000 * works.bulk,
    mass = 40000000 * works.bulk, inertia = 1, maxVelocity = 0, warpSpeed = 1, radius = works.radius,
    shield = works.shield, armor = works.armor, hull = works.hull, shieldRecharge = 900,
    shieldResonance = SHIELD, armorResonance = ARMOR, hullResonance = HULL, signature = works.signature,
    cpu = 600, powergrid = 2000, highs = works.launchers, mids = 2, lows = 3, turrets = 0, launchers = works.launchers,
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

local Ships = { list = types, byId = {} :: { [string]: ShipType } }

Ships.RIGS = 3
Ships.CALIBRATION = 400
-- Drones a hull controls, by its class.
-- (A carrier's are what it fights with, and a capital industrial's what
-- it works with: they control twice a battleship's, a supercarrier
-- three times, and have the bays for many times as many. Fighters and
-- bombers, which are theirs alone, are not made yet.)
Ships.DRONES = { frigate = 1, destroyer = 2, cruiser = 4, battleship = 5, industrial = 2, barge = 3,
  attackbattlecruiser = 2, battlecruiser = 5, carrier = 10, dreadnought = 5, siegedreadnought = 5, capitalindustrial = 10,
  supercarrier = 15, ultracapital = 25 } :: { [string]: number }
-- And the room in its drone bay, m3: what it controls, and spares.
Ships.BAY = { frigate = 10, destroyer = 25, cruiser = 50, battleship = 125, industrial = 25, barge = 50,
  attackbattlecruiser = 25, battlecruiser = 75, carrier = 2500, dreadnought = 250, siegedreadnought = 250, capitalindustrial = 1000,
  supercarrier = 6000, ultracapital = 40000 } :: { [string]: number }
-- Whether a class is a capital.
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

-- The tech 2 make of a hull, if it has one.
function Ships.Improved(id: string): ShipType?
  -- (the one its faction's line names, which is called what it is called)
  for _, hull in Ships.list do
    if hull.tech == 2 and hull.base == id then
      return hull
    end
  end
  return nil
end

-- Seconds; see the note on agility above.
function Ships.TimeConstant(t: ShipType): number
  return t.inertia * t.mass / 1e6
end

return Ships
