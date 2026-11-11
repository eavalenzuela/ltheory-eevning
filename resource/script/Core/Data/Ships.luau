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
    cpu = 110, powergrid = 32, highs = 2, mids = 2, lows = 1, turrets = 2, launchers = 0,
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
  -- Projectiles, missiles and shields.
  {
    id = "frigate.harrier", name = "Talmar Rapier", class = "frigate", lineage = "talmar", basePrice = 400000, volume = 2500,
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
}

-- To two figures or so: nobody quotes a hull's armour to the hit point.
local function round(x: number): number
  local step = if x >= 100000 then 10000 elseif x >= 10000 then 500 elseif x >= 1000 then 50 elseif x >= 100 then 5 else 1
  return math.floor(x / step + 0.5) * step
end

local function hullId(faction: Factions.Faction, class: string): string
  return `{class}.{string.lower((string.gsub(faction.hulls[class], "[^%a]", "")))}`
end

for _, yard in Factions.list do
  for _, class in Factions.CLASSES do
    local id = hullId(yard, class)
    local written = false
    for _, t in types do
      if t.lineage == yard.id and t.class == class then
        written = true
      end
    end
    if not written then
      local s = CLASS[class]
      local hardpoints = s.hardpoints + (if class == "industrial" then 0 else yard.hardpoints)
      local launchers = if class == "industrial" then 0 else math.floor(hardpoints * yard.launchers + 0.5)
      -- (a pirate hull: the human hull of this class it was made out of,
      -- which is in the list already, the human factions coming first)
      local donor: string? = nil
      if yard.donors then
        for _, t in types do
          if t.lineage == yard.donors[class] and t.class == class then
            donor = t.id
          end
        end
      end
      table.insert(types, {
        id = id, name = `{yard.name} {yard.hulls[class]}`, class = class, lineage = yard.id,
        basePrice = round(s.price * yard.price), volume = s.volume,
        mass = round(s.mass * yard.mass), inertia = s.inertia, maxVelocity = round(s.velocity * yard.velocity),
        warpSpeed = s.warp, radius = s.radius,
        shield = round(s.shield * yard.shield), armor = round(s.armor * yard.armor), hull = round(s.hull * yard.hull),
        shieldRecharge = s.recharge, shieldResonance = SHIELD, armorResonance = ARMOR, hullResonance = HULL,
        signature = s.signature,
        cpu = round(s.cpu * yard.cpu), powergrid = round(s.powergrid * yard.powergrid),
        highs = math.max(s.highs, hardpoints), mids = math.max(1, s.mids + yard.mids), lows = math.max(1, s.lows + yard.lows),
        turrets = hardpoints - launchers, launchers = launchers,
        capacitor = round(s.capacitor * yard.capacitor), capacitorRecharge = s.capacitorRecharge,
        scanResolution = s.scan, lockRange = round(s.lock * yard.lockRange), maxTargets = s.targets,
        cargo = round(s.cargo * (if class == "industrial" then yard.cargo else 1)),
        requires = { { skill = s.skill, level = s.level } },
        restricted = if yard.kind ~= "human" then true else nil,
        donor = donor,
      })
    end
  end
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

for _, base in table.clone(types) do
  local yard = Factions.byId[base.lineage]
  local mining = base.id == "frigate.prospector" or base.id == "barge.quarry"
  if ((yard ~= nil and yard.kind == "human") or mining) and not base.restricted then
    local carrier = base.class == "industrial" or mining
    local armoured = base.armor >= base.shield
    table.insert(types, {
      id = base.id .. ".ii", name = base.name .. " II", class = base.class, lineage = base.lineage,
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
      cargo = if carrier then round(base.cargo * TECH2.cargo) else base.cargo,
      drones = base.drones, bay = base.bay, rigs = base.rigs, calibration = base.calibration,
      tech = 2, base = base.id,
    })
  end
end

local Ships = { list = types, byId = {} :: { [string]: ShipType } }

Ships.RIGS = 3
Ships.CALIBRATION = 400
-- Drones a hull controls, by its class.
Ships.DRONES = { frigate = 1, destroyer = 2, cruiser = 4, battleship = 5, industrial = 2, barge = 3 } :: { [string]: number }
-- And the room in its drone bay, m3: what it controls, and spares.
Ships.BAY = { frigate = 10, destroyer = 25, cruiser = 50, battleship = 125, industrial = 25, barge = 50 } :: { [string]: number }

for _, t in types do
  Ships.byId[t.id] = t
  t.rigs = t.rigs or (if t.class == "capsule" then 0 else Ships.RIGS)
  t.drones = t.drones or Ships.DRONES[t.class] or 0
  t.bay = t.bay or Ships.BAY[t.class] or 0
  t.calibration = t.calibration or Ships.CALIBRATION
end

-- The tech 2 make of a hull, if it has one.
function Ships.Improved(id: string): ShipType?
  local better = Ships.byId[id .. ".ii"]
  return if better and better.tech == 2 then better else nil
end

-- Seconds; see the note on agility above.
function Ships.TimeConstant(t: ShipType): number
  return t.inertia * t.mass / 1e6
end

return Ships
