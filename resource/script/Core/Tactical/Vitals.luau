--!strict
-- A ship's condition in space: hit points, capacitor, and the numbers a
-- fight turns on, worked out from its hull and fit.

local Dogma = require("@lt/Core/Dogma")
local Items = require("@lt/Core/Assets/Items")
local Ships = require("@lt/Core/Data/Ships")
local State = require("@lt/Core/Kernel/State")

local Vitals = {}

local function resonance(stats: Dogma.Stats, layer: string): { number }
  return { stats[layer .. ".1"], stats[layer .. ".2"], stats[layer .. ".3"], stats[layer .. ".4"] }
end

-- A ship's attributes with the modules now running on its ball.
function Vitals.Stats(state: State.State, ship: State.Ship, vitals: State.Vitals?): Dogma.Stats
  local running: { [number]: boolean } = {}
  if vitals then
    for _, r in vitals.running do
      running[r.item] = true
    end
  end
  return Dogma.Ship(Ships.byId[ship.type], Items.Fit(state, ship.id, running))
end

-- The fit as the attribute engine wants it, with what is running.
function Vitals.Fit(state: State.State, ball: State.Ball): { Dogma.Fitted }
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
    signature = stats.signature, scanResolution = stats.scanResolution,
    lockRange = stats.lockRange, maxTargets = stats.maxTargets,
    shieldResonance = resonance(stats, "shieldResonance"),
    armorResonance = resonance(stats, "armorResonance"),
    hullResonance = resonance(stats, "hullResonance"),
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
  v.signature, v.scanResolution = stats.signature, stats.scanResolution
  v.lockRange, v.maxTargets = stats.lockRange, stats.maxTargets
  v.shieldResonance = resonance(stats, "shieldResonance")
  v.armorResonance = resonance(stats, "armorResonance")
  v.hullResonance = resonance(stats, "hullResonance")
  ball.maxVelocity, ball.tau = stats.maxVelocity, stats.tau
end

-- Remember a ball's damage on its ship, as it docks.
function Vitals.Store(ship: State.Ship, ball: State.Ball)
  ship.armorDamage = math.max(0, ball.vitals.armorMax - ball.vitals.armor)
  ship.hullDamage = math.max(0, ball.vitals.hullMax - ball.vitals.hull)
end

return Vitals
