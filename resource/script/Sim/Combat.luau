--!strict
-- Abstract combat for battles outside the player's system: a Lanchester
-- square-law exchange with a random spread, where the loser retreats
-- after heavy losses (or is destroyed if hopelessly outmatched). In the
-- player's system battles are fought physically instead.

local Data = require("@lt/Sim/Data")
local Rng = require("@lt/Sim/Rng")
local State = require("@lt/Sim/State")

local Combat = {}

-- Combat value of a fleet; halved without munitions
function Combat.FleetStrength(fleet: State.Fleet): number
  local total = 0
  for _, class in Data.Ships do
    total += (fleet.ships[class.id] or 0) * class.quality
  end
  if fleet.munitions < State.ShipCount(fleet) then
    total *= Data.NO_MUNITIONS
  end
  return total
end

function Combat.Strength(fleets: { State.Fleet }): number
  local total = 0
  for _, fleet in fleets do
    total += Combat.FleetStrength(fleet)
  end
  return total
end

-- Rolls a battle between strengths a and b. Returns whether a won and the
-- share of its strength each side lost.
function Combat.Fight(rng: Rng.Rng, a: number, b: number): (boolean, number, number)
  local spread = Data.COMBAT_SPREAD
  local va = a * Rng.Float(rng, 1 - spread, 1 + spread)
  local vb = b * Rng.Float(rng, 1 - spread, 1 + spread)
  local aWins = va >= vb
  local winner, loser = if aWins then va else vb, if aWins then vb else va
  if winner <= 0 then
    return aWins, 0, 0
  end
  local loserLoss = if winner >= Data.ROUT_RATIO * loser then 1 else Data.RETREAT_AT
  -- Square law: the winner pays for the strength it destroyed
  local destroyed = loser ^ 2 - (loser * (1 - loserLoss)) ^ 2
  local winnerLoss = 1 - math.sqrt(math.max(0, winner ^ 2 - destroyed)) / winner
  if aWins then
    return true, winnerLoss, loserLoss
  end
  return false, loserLoss, winnerLoss
end

-- Removes a share of each fleet's ships and spends munitions; returns the
-- number of ships lost
function Combat.ApplyLosses(rng: Rng.Rng, fleets: { State.Fleet }, share: number): number
  local lost = 0
  for _, fleet in fleets do
    fleet.munitions = math.max(0, fleet.munitions - State.ShipCount(fleet))
    for _, class in Data.Ships do
      local n = fleet.ships[class.id] or 0
      if n > 0 then
        local k = math.min(n, Rng.Round(rng, n * share))
        fleet.ships[class.id] = n - k
        lost += k
      end
    end
  end
  return lost
end

return Combat
