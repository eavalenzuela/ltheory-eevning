--!strict
-- Vapour: what a cloud of gas does to the ship in it.
--
-- A ship in a cloud (inside it, or within a little of its edge) is
-- hard to see, and sees no better: nobody locks it from farther off
-- than Vapour.SIGHT, and it locks nobody from farther off than that. A
-- lock held from farther is lost when its target goes in, or when its
-- holder does. So a cloud is cover, both ways, for whoever is in it: a
-- harvester's ship is safe from what shoots from far off, and whoever
-- wants it has to come in close, where a big ship's guns follow a
-- small one badly.
--
-- Only ships and drones are hidden. A rock, a wreck or the cloud
-- itself is locked from as far as ever, in the vapour or out of it.
-- A cloud that has been drawn off is no cover.
--
-- (Tactical/Combat asks here whenever it asks whether a thing can be
-- locked, which is when a lock is begun and every tick it is held.
-- Those who fight by themselves ask too, and close in: Tactical/Pirates
-- and Tactical/Fleet. The figures are first ones.)

local Mining = require("@lt/Core/Tactical/Mining")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")

local Vapour = {}

-- How far off a ship in a cloud can be locked from, and can lock
-- (metres, between surfaces); and how far outside a cloud's edge its
-- vapour still hides a ship.
Vapour.SIGHT = 5000
Vapour.EDGE = 500
-- How near whoever fights by themselves comes to something in the
-- vapour, or from in it: well inside what can be locked.
Vapour.CLOSE = 3500

-- Whether a ship is in a cloud. (Clouds are at vapour fields, and a
-- vapour field is a place of its own: so anywhere else this is asked
-- and answered at once.)
function Vapour.In(state: State.State, ball: State.Ball): boolean
  local site = state.sites[ball.grid]
  if site == nil or site.kind ~= "gas" or site.system ~= ball.system then
    return false
  end
  for _, object in Space.Describe(state, ball.system).objects do
    if object.site == ball.grid and Mining.Cloud(object) and Mining.Left(state, object) > 0
      and Space.Gap(ball :: any, object :: any) <= Vapour.EDGE then
      return true
    end
  end
  return false
end

-- Whether the vapour is between two ships: either of them is in a cloud.
function Vapour.Between(state: State.State, one: State.Ball, other: State.Ball): boolean
  return Vapour.In(state, one) or Vapour.In(state, other)
end

-- How far apart two ships can be for one to lock the other, as far as
-- the vapour goes: Vapour.SIGHT with either of them in a cloud, and any
-- distance otherwise.
function Vapour.Sight(state: State.State, one: State.Ball, other: State.Ball): number
  return if Vapour.Between(state, one, other) then Vapour.SIGHT else math.huge
end

return Vapour
