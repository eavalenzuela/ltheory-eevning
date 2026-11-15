--!strict
-- Surges: what pirates massing in a system does to it.
--
-- Where pirates mass, and when, is the galaxy's own state now
-- (Strategic/Happenings: the pressure in every system of thin order,
-- which the owner ruled on 2026-11-14 in place of one surge at a time
-- within a few jumps of the pilot). This module is what a surge is to
-- the place it is in: while one is on, that system is worse than its
-- space. Where a pilot of the player's side is, pirates come sooner and
-- in the packs of space a kind less safe, more of them veterans and
-- captains; and what is on the head of every pirate destroyed there is
-- doubled. Enough of them destroyed there breaks it.
--
-- Who comes is Tactical/Pirates' business and what is paid is
-- Tactical/Aftermath's; each asks here.
--
-- (Every figure is a first proposal.)

local Happenings = require("@lt/Core/Strategic/Happenings")
local State = require("@lt/Core/Kernel/State")

local Surges = {}

export type Event = { [string]: any }

-- How many times what is on a pirate's head is paid there, how many
-- times as soon pirates come back to a place, and how many times as
-- likely one is a veteran or a captain.
Surges.BOUNTY = 2
Surges.SOONER = 2
Surges.GRADED = 2

-- Whether a surge is on in a system.
function Surges.On(state: State.State, system: number): boolean
  return Happenings.In(state, system, Happenings.SURGE) ~= nil
end

-- The kind of space a system is to the pirates who come there: a kind
-- less safe than it is, while a surge is on.
function Surges.Band(state: State.State, system: number, band: string): string
  if Surges.On(state, system) then
    return if band == "secure" then "low" else "lawless"
  end
  return band
end

-- A pirate has been destroyed in a system: the pressure there is let
-- down, and where a surge is on it is counted. Returns how many times
-- its bounty is paid.
function Surges.Fell(state: State.State, system: number): number
  return if Happenings.Fell(state, system) then Surges.BOUNTY else 1
end

return Surges
