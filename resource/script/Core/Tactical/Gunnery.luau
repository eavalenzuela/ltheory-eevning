--!strict
-- The mathematics of a fight, with no state: how long a lock takes,
-- whether a turret hits and how hard, how much of a missile's blast a
-- target takes, how damage passes through shield, armour and hull, and
-- how shields and capacitors recharge. All of it follows EVE's formulas.

local Gunnery = {}

-- Seconds to lock a target: quicker with a sharper scanner (scan
-- resolution, mm) and a bigger target (signature radius, m).
function Gunnery.LockTime(scanResolution: number, signature: number): number
  local asinh = math.log(signature + math.sqrt(signature * signature + 1))
  return 40000 / (scanResolution * asinh * asinh)
end

-- The chance a turret hits. 'angular' is how fast the target crosses the
-- gun's view, in radians per second (transversal speed over distance);
-- tracking is the gun's, signature the target's. Inside optimal range
-- distance costs nothing; each falloff beyond it halves the chance, then
-- quarters it, and so on. A target crossing at exactly the rate the gun
-- can follow is hit half the time.
function Gunnery.HitChance(angular: number, tracking: number, signature: number,
  distance: number, optimal: number, falloff: number): number
  local track = angular * 40000 / (tracking * signature)
  local range = if falloff > 0 then math.max(0, distance - optimal) / falloff
    else (if distance > optimal then math.huge else 0)
  return 0.5 ^ (track * track + range * range)
end

-- How good a shot was, from one roll in [0, 1): 0 is a miss; a roll under
-- 1% is a wrecking hit for three times the damage; otherwise the damage
-- multiplier is the roll plus 0.49, so better odds also mean better hits.
function Gunnery.Quality(roll: number, chance: number): number
  if roll < 0.01 and chance > 0 then
    return 3
  elseif roll < chance then
    return roll + 0.49
  end
  return 0
end

-- The share of a missile's damage a target takes: less if it is smaller
-- than the explosion, less again if it outruns it.
function Gunnery.MissileFactor(signature: number, speed: number, explosionRadius: number, explosionVelocity: number): number
  local size = signature / explosionRadius
  local outrun = if speed > 0 then (size * explosionVelocity / speed) ^ 0.68 else math.huge
  return math.min(1, size, outrun)
end

export type Layers = { shield: number, armor: number, hull: number }

-- Apply damage (EM, thermal, kinetic, explosive) to a ship's layers in
-- place, shield first. Each layer lets through its resonance of each
-- type; what a layer cannot absorb carries on to the next in the same
-- proportions. Returns the hit points removed from each layer.
function Gunnery.Apply(layers: Layers, shieldResonance: { number }, armorResonance: { number },
  hullResonance: { number }, damage: { number }): (number, number, number)
  local remaining = 1 -- the share of the raw damage still to be absorbed
  local function hit(points: number, resonance: { number }): (number, number)
    if remaining <= 0 then
      return points, 0
    end
    local effective = 0
    for index = 1, 4 do
      effective += damage[index] * resonance[index]
    end
    effective *= remaining
    if effective <= 0 then
      return points, 0
    elseif effective <= points then
      remaining = 0
      return points - effective, effective
    end
    remaining *= 1 - points / effective
    return 0, points
  end
  local shieldLost, armorLost, hullLost
  layers.shield, shieldLost = hit(layers.shield, shieldResonance)
  layers.armor, armorLost = hit(layers.armor, armorResonance)
  layers.hull, hullLost = hit(layers.hull, hullResonance)
  return shieldLost, armorLost, hullLost
end

-- A shield or capacitor 'dt' seconds later, recharging on its own. The
-- rate peaks at a quarter full and falls away toward empty and toward
-- full; 'time' is the module's recharge time.
function Gunnery.Recharge(current: number, max: number, time: number, dt: number): number
  if max <= 0 then
    return 0
  end
  local root = math.sqrt(math.clamp(current / max, 0, 1))
  local next = 1 + (root - 1) * math.exp(-5 * dt / time)
  return max * next * next
end

return Gunnery
