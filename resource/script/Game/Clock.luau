--!strict
-- Turns frame time into Core ticks. Pause and acceleration change how
-- fast ticks are taken, never what a tick does.

local Constants = require("@lt/Core/Data/Constants")

local Clock = {}

export type Clock = {
  scale: number,    -- game seconds per real second
  paused: boolean,
  pending: number,  -- game seconds accumulated toward the next tick
}

-- No more than this many ticks in one frame, so a stall cannot snowball.
local MAX_TICKS_PER_FRAME = 40

function Clock.New(): Clock
  return { scale = 1, paused = false, pending = 0 }
end

-- Add a frame's worth of time; returns how many ticks are now due.
function Clock.Advance(clock: Clock, frameSeconds: number): number
  if clock.paused then
    return 0
  end
  clock.pending += math.min(frameSeconds, 0.25) * clock.scale
  local due = math.min(MAX_TICKS_PER_FRAME, clock.pending // Constants.TICK)
  clock.pending -= due * Constants.TICK
  if due == MAX_TICKS_PER_FRAME then
    clock.pending = math.min(clock.pending, Constants.TICK)
  end
  return due
end

-- Seconds of game time since the last tick, for drawing between ticks.
function Clock.SinceTick(clock: Clock): number
  return math.min(clock.pending, Constants.TICK)
end

return Clock
