--!strict
-- Surges: now and then pirates mass in one system.
--
-- Every few hours a surge begins somewhere order is thin, within a few
-- jumps of where the pilot is, and lasts a couple of hours. While it is
-- on, that system is worse than its space: where a pilot of the
-- player's side is, pirates come sooner and in the packs of space a
-- kind less safe, more of them veterans and captains; and what is on
-- the head of every pirate destroyed there is doubled. It is said when
-- one begins and where, and when it ends how many were destroyed.
--
-- One at a time. A game with no pirates in it has none.
--
-- This module is only the surge itself: when, where, and whether one is
-- on. Who comes is Tactical/Pirates' business and what is paid is
-- Tactical/Aftermath's; each asks here.
--
-- (A stand-in, like the pirates' own rules: when the strategic layer
-- joins the game, where pirates mass is where its pressure is. Every
-- figure is a first proposal.)

local Constants = require("@lt/Core/Data/Constants")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Rng = require("@lt/Core/Kernel/Rng")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")

local Surges = {}

export type Event = { [string]: any }

local HOUR = math.floor(3600 / Constants.TICK + 0.5)

-- Hours from the end of one surge to the start of the next, at least
-- and at most; how long one lasts; and how soon the first of a new game
-- comes.
Surges.EVERY = { 2, 4 }
Surges.LASTS = 2
Surges.FIRST = { 0.5, 1.5 }
-- How many jumps from the pilot one can begin.
Surges.REACH = 6
-- How many times what is on a pirate's head is paid there, how many
-- times as soon pirates come back to a place, and how many times as
-- likely one is a veteran or a captain.
Surges.BOUNTY = 2
Surges.SOONER = 2
Surges.GRADED = 2

-- No surge, and the first due in its time.
function Surges.None(state: State.State): State.Surge
  local rng = Rng.For(state.historySeed, 0, 977)
  return { system = 0, ends = 0, next = state.tick + math.floor(Rng.Float(rng, Surges.FIRST[1], Surges.FIRST[2]) * HOUR), kills = 0,
    count = 0 }
end

-- Whether a surge is on in a system.
function Surges.On(state: State.State, system: number): boolean
  return state.surge.system ~= 0 and state.surge.system == system
end

-- The kind of space a system is to the pirates who come there: a kind
-- less safe than it is, while a surge is on.
function Surges.Band(state: State.State, system: number, band: string): string
  if Surges.On(state, system) then
    return if band == "secure" then "low" else "lawless"
  end
  return band
end

-- A pirate has been destroyed in a system: it is counted, where a surge
-- is on. Returns how many times its bounty is paid.
function Surges.Fell(state: State.State, system: number): number
  if Surges.On(state, system) then
    state.surge.kills += 1
    return Surges.BOUNTY
  end
  return 1
end

-- The systems a surge could begin in: those where order is thin, within
-- reach of the pilot's, each with how many jumps off it is; in the order
-- of their ids.
local function candidates(state: State.State): { { number } }
  local systems = state.galaxy.systems
  -- (where the pilot is: in space, or docked)
  local ship = state.ships[state.player.ship]
  local here = if ship == nil then 1 elseif state.balls[ship.id] then state.balls[ship.id].system else Space.SystemOf(state, ship.docked)
  local jumps: { [number]: number } = { [here] = 0 }
  local queue = { here }
  local at = 1
  while at <= #queue do
    local system = queue[at]
    at += 1
    if jumps[system] < Surges.REACH then
      for _, neighbor in systems[system].neighbors do
        if jumps[neighbor] == nil then
          jumps[neighbor] = jumps[system] + 1
          table.insert(queue, neighbor)
        end
      end
    end
  end
  local found: { { number } } = {}
  for id = 1, #systems do
    if jumps[id] and Galaxy.Band(systems[id].security) ~= "secure" then
      table.insert(found, { id, jumps[id] })
    end
  end
  return found
end

-- Once a tick: a surge that is over ends, and one that is due begins.
function Surges.Step(state: State.State, events: { Event })
  local surge = state.surge
  if surge.system ~= 0 then
    if state.tick >= surge.ends then
      table.insert(events, { kind = "SurgeEnded", system = surge.system, kills = surge.kills })
      local rng = Rng.For(state.historySeed, surge.count, 983)
      surge.system, surge.kills = 0, 0
      surge.next = state.tick + math.floor(Rng.Float(rng, Surges.EVERY[1], Surges.EVERY[2]) * HOUR)
    end
  elseif state.tick >= surge.next then
    local rng = Rng.For(state.historySeed, surge.count, 991)
    local where = if state.peaceful then {} else candidates(state)
    if #where == 0 then
      -- (nowhere for one: asked again in an hour)
      surge.next = state.tick + HOUR
      return
    end
    local picked = where[Rng.Int(rng, #where) + 1]
    surge.system, surge.ends, surge.kills = picked[1], state.tick + Surges.LASTS * HOUR, 0
    surge.count += 1
    table.insert(events, { kind = "SurgeBegan", system = picked[1], jumps = picked[2], ends = surge.ends })
  end
end

return Surges
