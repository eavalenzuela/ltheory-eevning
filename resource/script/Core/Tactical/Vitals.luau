--!strict
-- A ship's condition in space: hit points, capacitor, and the numbers a
-- fight turns on, worked out from its hull and fit.

local Attributes = require("@lt/Core/Attributes")
local Constants = require("@lt/Core/Data/Constants")
local Modules = require("@lt/Core/Data/Modules")
local Items = require("@lt/Core/Assets/Items")
local Ships = require("@lt/Core/Data/Ships")
local State = require("@lt/Core/Kernel/State")

local Vitals = {}

local function resonance(stats: Attributes.Stats, layer: string): { number }
  return { stats[layer .. ".1"], stats[layer .. ".2"], stats[layer .. ".3"], stats[layer .. ".4"] }
end

-- A ship's attributes with the modules now running on its ball.
function Vitals.Stats(state: State.State, ship: State.Ship, vitals: State.Vitals?): Attributes.Stats
  local running: { [number]: boolean } = {}
  if vitals then
    for _, r in vitals.running do
      running[r.item] = true
    end
  end
  local fit = Items.Fit(state, ship.id, running)
  -- (and the command bursts of others that reach it, as if they ran on it:
  -- one of each, and none that it runs itself)
  if vitals and vitals.bursts then
    for _, burst in vitals.bursts do
      local own = false
      for _, each in fit do
        own = own or (each.type == burst and each.running)
      end
      if not own then
        table.insert(fit, { type = burst, running = true })
      end
    end
  end
  local stats = Attributes.Ship(Ships.byId[ship.type], fit, Items.Levels(state, ship.id))
  -- (a Trident takes more to bring down for its pylon's hull's bonus to it: Data/HullBonuses)
  local drone = state.drones[ship.id]
  local owner = if drone and drone.pylon then state.ships[drone.owner] else nil
  if owner then
    local by = Ships.Bonus(Ships.byId[owner.type], "trident", "toughness", Items.Levels(state, owner.id))
    if by ~= 1 then
      stats.shield, stats.armor, stats.hull = stats.shield * by, stats.armor * by, stats.hull * by
    end
  end
  return stats
end

-- The fit as the attribute engine wants it, with what is running.
function Vitals.Fit(state: State.State, ball: State.Ball): { Attributes.Fitted }
  local running: { [number]: boolean } = {}
  for _, r in ball.vitals.running do
    running[r.item] = true
  end
  return Items.Fit(state, ball.id, running)
end

-- The vitals of a ship as it leaves a station: shields and capacitor
-- full, armour and hull carrying whatever damage it has.
function Vitals.New(state: State.State, ship: State.Ship): State.Vitals
  local stats = Vitals.Stats(state, ship, nil)
  return {
    shield = stats.shield,
    armor = math.max(1, stats.armor - ship.armorDamage),
    hull = math.max(1, stats.hull - ship.hullDamage),
    capacitor = stats.capacitor,
    shieldMax = stats.shield, armorMax = stats.armor, hullMax = stats.hull, capacitorMax = stats.capacitor,
    shieldRecharge = stats.shieldRecharge, capacitorRecharge = stats.capacitorRecharge,
    armorMend = if stats.armorMend > 0 then stats.armorMend else nil, hullMend = if stats.hullMend > 0 then stats.hullMend else nil,
    signature = stats.signature, scanResolution = stats.scanResolution,
    -- (whole targets: a skill's share of one more is not one more)
    lockRange = stats.lockRange, maxTargets = math.floor(stats.maxTargets + 1e-6),
    shieldResonance = resonance(stats, "shieldResonance"),
    armorResonance = resonance(stats, "armorResonance"),
    hullResonance = resonance(stats, "hullResonance"),
    entangle = 1, scrambled = false, paint = 1, damp = 1,
    locks = {}, running = {},
  }
end

-- Bring a ball's maxima, resonances and flight into line with its fit
-- and what is running now. Called when a module that changes them (an
-- afterburner, a hardener) starts or stops.
function Vitals.Refresh(state: State.State, ball: State.Ball)
  local v = ball.vitals
  local stats = Vitals.Stats(state, state.ships[ball.id], v)
  v.shieldMax, v.armorMax, v.hullMax, v.capacitorMax = stats.shield, stats.armor, stats.hull, stats.capacitor
  v.shield, v.armor = math.min(v.shield, v.shieldMax), math.min(v.armor, v.armorMax)
  v.hull, v.capacitor = math.min(v.hull, v.hullMax), math.min(v.capacitor, v.capacitorMax)
  v.shieldRecharge, v.capacitorRecharge = stats.shieldRecharge, stats.capacitorRecharge
  v.armorMend = if stats.armorMend > 0 then stats.armorMend else nil
  v.hullMend = if stats.hullMend > 0 then stats.hullMend else nil
  -- (a painter on it swells what it shows, and a dampener cuts what it sees)
  -- (and a remote sensor booster on it, the other way)
  local sensor = v.sensor or 1
  v.signature, v.scanResolution = stats.signature * v.paint, stats.scanResolution * v.damp * sensor
  v.lockRange, v.maxTargets = stats.lockRange * v.damp * sensor, math.floor(stats.maxTargets + 1e-6)
  v.shieldResonance = resonance(stats, "shieldResonance")
  v.armorResonance = resonance(stats, "armorResonance")
  v.hullResonance = resonance(stats, "hullResonance")
  -- (an entanglement projector on it takes its share of the speed, whatever the fit)
  ball.maxVelocity, ball.tau = stats.maxVelocity * v.entangle, stats.tau
  -- (and a siege, triage or industrial core module running roots it)
  local rooted = false
  for _, r in v.running do
    local item = state.items[r.item]
    rooted = rooted or (item ~= nil and Modules.byId[item.type] ~= nil and Modules.byId[item.type].immobile == true)
  end
  v.rooted = if rooted then true else nil
  if rooted then
    ball.maxVelocity = 0
  end
end

-- A hull that mends by itself goes on mending in a hangar: once a tick,
-- every docked ship of such a hull that carries damage has that much
-- less of it. (In space it is its ball that mends: Tactical/Combat.)
function Vitals.Mend(state: State.State)
  for _, id in state.shipIds do
    local ship = state.ships[id]
    if ship.docked ~= 0 and (ship.armorDamage > 0 or ship.hullDamage > 0) then
      local hull = Ships.byId[ship.type]
      if (hull.armorMend or 0) > 0 or (hull.hullMend or 0) > 0 then
        local stats = Vitals.Stats(state, ship, nil)
        ship.armorDamage = math.max(0, ship.armorDamage - stats.armor * stats.armorMend * Constants.TICK)
        ship.hullDamage = math.max(0, ship.hullDamage - stats.hull * stats.hullMend * Constants.TICK)
      end
    end
  end
end

-- Remember a ball's damage on its ship, as it docks.
function Vitals.Store(ship: State.Ship, ball: State.Ball)
  ship.armorDamage = math.max(0, ball.vitals.armorMax - ball.vitals.armor)
  ship.hullDamage = math.max(0, ball.vitals.hullMax - ball.vitals.hull)
end

return Vitals
