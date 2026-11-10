--!strict
-- The mathematics of ship movement, with no state: sub-warp flight and
-- the warp profile. Both are closed-form, so the view can evaluate the
-- same formulas between ticks and meet the Core's state exactly at each
-- tick (the engine's kinematic mode mirrors this file).
--
-- Sub-warp flight is a first-order lag: a ship has a target velocity, and
-- its velocity closes the gap exponentially with time constant tau
-- (Ships.TimeConstant). From rest toward top speed:
--     v(t) = vmax * (1 - e^(-t/tau))
-- so the time to reach a fraction f of top speed is -tau * ln(1 - f);
-- for warp's 75% that is 1.386 tau.
--
-- Warp follows a straight line in three stages:
--     accelerate   distance d(t) = e^(k t) - 1, speed k e^(k t)
--     cruise       at the peak speed
--     decelerate   speed peak * e^(-j t), until it falls to the dropout
--                  speed
-- with k the hull's warp speed in AU/s and j = min(k / 3, 2). The peak is
-- k AU/s when the trip is long enough to reach it. A frigate at 5 AU/s
-- covers 20 AU in about 22 s, most of it accelerating and braking.

local Constants = require("@lt/Core/Data/Constants")

local Motion = {}

-- One step of sub-warp flight: position and velocity after 'dt' seconds
-- with a constant target velocity. Exact, not an approximation.
function Motion.Step(
  x: number, y: number, z: number,
  vx: number, vy: number, vz: number,
  tx: number, ty: number, tz: number,
  tau: number, dt: number
): (number, number, number, number, number, number)
  local decay = math.exp(-dt / tau)
  local reach = tau * (1 - decay)
  return x + tx * dt + (vx - tx) * reach,
    y + ty * dt + (vy - ty) * reach,
    z + tz * dt + (vz - tz) * reach,
    tx + (vx - tx) * decay,
    ty + (vy - ty) * decay,
    tz + (vz - tz) * decay
end

-- Seconds to reach 'fraction' of top speed from rest.
function Motion.TimeToSpeed(tau: number, fraction: number): number
  return -tau * math.log(1 - fraction)
end

export type WarpPlan = {
  distance: number,   -- m, along the line
  k: number,          -- acceleration rate, per second
  j: number,          -- deceleration rate, per second
  peak: number,       -- m/s
  dropout: number,    -- m/s on leaving warp
  tAccel: number,     -- s
  tCruise: number,
  tDecel: number,
  total: number,
  dAccel: number,     -- m covered while accelerating
  dCruise: number,
}

-- Plan a warp of 'distance' metres for a hull with the given warp speed
-- (AU/s) and sub-warp top speed (m/s).
function Motion.PlanWarp(distance: number, warpSpeed: number, maxVelocity: number): WarpPlan
  local k = warpSpeed
  local j = math.min(k / 3, Constants.WARP_MAX_DECELERATION)
  local dropout = math.min(maxVelocity / 2, Constants.WARP_DROPOUT_SPEED)
  local peak = k * Constants.AU
  -- Distance spent accelerating to the peak and braking from it.
  local dAccel = peak / k - 1
  local dDecel = (peak - dropout) / j
  local dCruise = distance - dAccel - dDecel
  if dCruise < 0 then
    -- Too short to reach full warp speed: accelerate straight into the
    -- brake. Solve distance = peak/k - 1 + (peak - dropout)/j for the peak.
    peak = (distance + 1 + dropout / j) * k * j / (k + j)
    dAccel = peak / k - 1
    dCruise = 0
  end
  local tAccel = math.log(peak / k) / k
  local tCruise = dCruise / peak
  local tDecel = math.log(peak / dropout) / j
  return {
    distance = distance, k = k, j = j, peak = peak, dropout = dropout,
    tAccel = tAccel, tCruise = tCruise, tDecel = tDecel, total = tAccel + tCruise + tDecel,
    dAccel = dAccel, dCruise = dCruise,
  }
end

-- Distance along the line and speed, 't' seconds into the warp.
function Motion.WarpAt(plan: WarpPlan, t: number): (number, number)
  if t <= 0 then
    return 0, plan.k
  elseif t < plan.tAccel then
    local e = math.exp(plan.k * t)
    return e - 1, plan.k * e
  elseif t < plan.tAccel + plan.tCruise then
    return plan.dAccel + plan.peak * (t - plan.tAccel), plan.peak
  elseif t < plan.total then
    local e = math.exp(-plan.j * (t - plan.tAccel - plan.tCruise))
    return plan.dAccel + plan.dCruise + plan.peak / plan.j * (1 - e), plan.peak * e
  end
  return plan.distance, plan.dropout
end

return Motion
