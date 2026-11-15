--!strict
-- Happenings: what is going on in the galaxy that a pilot could go to.
--
-- The owner's rulings (2026-11-14): four kinds, a mark left behind for
-- a few days by those nobody answers, and all of it told in one place.
--
--   Pirate surges. Pirates mass where the galaxy's own state says they
--   would: where order is thin and trade is rich. Every charted system
--   that is not secure has a pressure, 0 to 1, which grows with how thin
--   its order is and how much trade its lanes can carry, and is let
--   down by every pirate destroyed there. At 1 a surge begins: several
--   are on at once across the galaxy, not one near the pilot. While one
--   is on, the system is worse than its space (Tactical/Surges says how,
--   to the pirates and to what is paid for them), and its lanes cost
--   the economy more (Strategic/Commerce). Enough pirates destroyed
--   there breaks it early.
--
--   Invasions, sightings, and what happens to places, are other
--   modules' (Tactical/Invasions, Tactical/Sightings, Assets/Mishaps):
--   they come by the clock, within reach of the pilot, and are kept
--   here with the surges, in one list.
--
-- What is left behind. A surge that runs its time leaves the system's
-- order a little thinner for a few days, and one that is broken leaves
-- it a little firmer: its security is changed, and put back when the
-- time is up. Nothing changes hands. (A system the pilot's corporation
-- keeps order in is left as it is: its order is theirs.)
--
-- This module is the list, the pressure and what is left behind. What
-- any of it puts in space where the pilot is, is for the modules of
-- the tactical layer, each of which asks here.
--
-- Every figure is a first proposal, and mine.

local Constants = require("@lt/Core/Data/Constants")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Rng = require("@lt/Core/Kernel/Rng")
local State = require("@lt/Core/Kernel/State")

local Happenings = {}

export type Event = { [string]: any }

local HOUR = math.floor(3600 / Constants.TICK + 0.5)
local DAY = 24 * HOUR

Happenings.SURGE = "surge"
Happenings.INVASION = "invasion"
Happenings.SIGHTING = "sighting"
Happenings.DISASTER = "disaster"
Happenings.WINDFALL = "windfall"

-- Hours an ordinary system of thin order (security 0.5, with the lanes
-- an ordinary system has) takes to come to a surge from nothing; the
-- hours one lasts; how many pirates destroyed there break it; how much
-- pressure each pirate destroyed lets down; and the pressure a system
-- is left with after one that ran its time, and after one that was
-- broken.
Happenings.SURGE_EVERY = 96
Happenings.SURGE_LASTS = 2
Happenings.SURGE_BREAK = 10
Happenings.RELIEF = 0.02
Happenings.SPENT = 0.25
-- How often the pressure is worked out, ticks (with the economy's step).
Happenings.STEP = 600
-- What is left behind, in security, and for how many days: by a surge
-- that ran its time, and by one that was broken; by an invasion that
-- was let be, and one that was beaten.
Happenings.MARK_DAYS = 3
Happenings.MARKS = { surge = -0.05, surgeBroken = 0.03, invasion = -0.15, invasionBeaten = 0.05 }
-- How many jumps off a pilot hears of something beginning.
Happenings.HEARD = 6
-- How far off anything is looked for when how far it is is asked.
Happenings.FAR = 40

-- Nothing going on, and the pressure every system begins a game with:
-- somewhere on its way, so that they do not all come due together.
function Happenings.None(state: State.State): State.Happenings
  local pressure: { number } = {}
  local galaxy = state.galaxy
  for id = 1, Galaxy.Charted(galaxy) do
    local node = galaxy.systems[id]
    pressure[id] = if Galaxy.Band(node.security) == "secure" then 0
      else Rng.Float(Rng.For(state.historySeed, id, 1201), 0, 0.85)
  end
  local rng = Rng.For(state.historySeed, 0, 1203)
  return { list = {}, count = 0, pressure = pressure, marks = {}, steps = 0, version = 0,
    sightingDue = state.tick + math.floor(Rng.Float(rng, 0.5, 1.0) * HOUR),
    placeDue = state.tick + math.floor(Rng.Float(rng, 1.0, 2.0) * HOUR),
    invasionDue = state.tick + math.floor(Rng.Float(rng, 3.0, 5.0) * HOUR) }
end

-- How many jumps every system within 'reach' of one is from it, by the
-- gates: the system itself is 0. (Uncharted space has no gates: from
-- there, nothing is in reach.)
function Happenings.Reach(state: State.State, from: number, reach: number): { [number]: number }
  local systems = state.galaxy.systems
  local jumps: { [number]: number } = { [from] = 0 }
  local queue = { from }
  local at = 1
  while at <= #queue do
    local system = queue[at]
    at += 1
    if jumps[system] < reach then
      for _, neighbor in systems[system].neighbors do
        if jumps[neighbor] == nil then
          jumps[neighbor] = jumps[system] + 1
          table.insert(queue, neighbor)
        end
      end
    end
  end
  return jumps
end

-- The happening of a kind that is on in a system, if one is.
function Happenings.In(state: State.State, system: number, kind: string): State.Happening?
  for _, one in state.happenings.list do
    if one.system == system and one.kind == kind then
      return one
    end
  end
  return nil
end

-- The happening with an id, if it is still on.
function Happenings.Get(state: State.State, id: number): State.Happening?
  for _, one in state.happenings.list do
    if one.id == id then
      return one
    end
  end
  return nil
end

-- The systems pirates are massing in now: for the economy, whose lanes
-- there cost more (Strategic/Commerce).
function Happenings.Surging(state: State.State): { [number]: boolean }
  local found: { [number]: boolean } = {}
  for _, one in state.happenings.list do
    if one.kind == Happenings.SURGE then
      found[one.system] = true
    end
  end
  return found
end

-- Something begins: it is put on the list and said. 'lasts' is in
-- ticks. Returns it.
function Happenings.Begin(state: State.State, kind: string, what: string, system: number, place: number, lasts: number,
  strength: number, name: string, events: { Event }, far: { [number]: number }?): State.Happening
  local all = state.happenings
  all.count += 1
  all.version += 1
  local one: State.Happening = { id = all.count, kind = kind, what = what, system = system, place = place, began = state.tick,
    ends = state.tick + lasts, strength = strength, stage = 1, kills = 0, name = name }
  table.insert(all.list, one)
  -- ('far': how many jumps each system the pilot would hear from is from them. -1 for one too far to hear of.)
  table.insert(events, { kind = "HappeningBegan", id = one.id, happening = kind, what = what, system = system, name = name,
    jumps = if far then far[system] or -1 else -1, ends = one.ends })
  return one
end

-- Leave a mark on a system's order for a few days. One at a time: a
-- system that has one already keeps it.
function Happenings.Mark(state: State.State, system: number, delta: number, why: string)
  local node = state.galaxy.systems[system]
  -- (never where the pilot's corporation keeps order, which is theirs
  -- to keep; nor in uncharted space, which has none)
  if node == nil or node.uncharted or node.owner == "player" or delta == 0 then
    return
  end
  for _, mark in state.happenings.marks do
    if mark.system == system then
      return
    end
  end
  local was = node.security
  local now = math.clamp(was + delta, 0, 1)
  if now == was then
    return
  end
  node.security = now
  table.insert(state.happenings.marks, { system = system, was = was, now = now, ends = state.tick + Happenings.MARK_DAYS * DAY,
    why = why })
  state.happenings.version += 1
end

-- Something is over: it comes off the list, and is said, with how it
-- went ('outcome': "over" for what ran its time, "broken" or "beaten"
-- for what was seen off, or whatever its own module says).
function Happenings.End(state: State.State, one: State.Happening, outcome: string, events: { Event })
  local all = state.happenings
  for index, other in all.list do
    if other.id == one.id then
      table.remove(all.list, index)
      break
    end
  end
  all.version += 1
  table.insert(events, { kind = "HappeningEnded", id = one.id, happening = one.kind, what = one.what, system = one.system,
    name = one.name, outcome = outcome, kills = one.kills })
end

-- A pirate has been destroyed in a system, with the pilot there or by
-- their own people: the pressure there is let down, and a surge that is
-- on there counts it (and is broken by enough of them). Returns whether
-- a surge was on.
function Happenings.Fell(state: State.State, system: number, events: { Event }?): boolean
  local all = state.happenings
  if all.pressure[system] then
    all.pressure[system] = math.max(0, all.pressure[system] - Happenings.RELIEF)
  end
  local surge = Happenings.In(state, system, Happenings.SURGE)
  if surge == nil then
    return false
  end
  surge.kills += 1
  if surge.kills >= Happenings.SURGE_BREAK then
    -- (it is ended by the next step, which has somewhere to say so)
    surge.ends = math.min(surge.ends, state.tick)
  end
  return true
end

-- Work out the pressure, each STEP ticks: every system of thin order is
-- a step nearer a surge, by how thin and how rich in trade it is, and
-- one that has come to it begins one. 'here' is the system the pilot is
-- in (who hears of what begins within a few jumps), and 'trade' how
-- much each system's lanes can carry (Strategic/Commerce's, by system),
-- if the caller has it: without, every system counts alike.
function Happenings.Press(state: State.State, events: { Event }, here: number, trade: { number }?)
  local all = state.happenings
  all.steps += 1
  if state.peaceful then
    return
  end
  local galaxy = state.galaxy
  local charted = Galaxy.Charted(galaxy)
  local mean = 0
  if trade then
    for id = 1, charted do
      mean += trade[id] or 0
    end
    mean /= math.max(1, charted)
  end
  local surging = Happenings.Surging(state)
  local share = (Happenings.STEP / HOUR) / Happenings.SURGE_EVERY
  local far: { [number]: number }? = nil
  for id = 1, charted do
    local node = galaxy.systems[id]
    if Galaxy.Band(node.security) == "secure" then
      -- (where order is kept there is none to speak of)
      all.pressure[id] = 0
    elseif not surging[id] then
      local rich = if trade and mean > 0 then math.min(3, (trade[id] or 0) / mean) else 1
      local roll = Rng.Float(Rng.For(state.historySeed, all.steps, id, 1207), 0.5, 1.5)
      local pressure = (all.pressure[id] or 0) + share * ((1 - node.security) / 0.5) * (0.5 + 0.5 * rich) * roll
      if pressure >= 1 then
        pressure = 1
        far = far or Happenings.Reach(state, here, Happenings.HEARD)
        Happenings.Begin(state, Happenings.SURGE, "pirates", id, 0, Happenings.SURGE_LASTS * HOUR, 1, "", events, far)
      end
      all.pressure[id] = pressure
    end
  end
end

-- Once a tick: a surge whose time is up, or that has been broken, ends,
-- and leaves its mark; and a mark whose days are up is taken off.
-- (The other kinds are ended by their own modules.)
function Happenings.Step(state: State.State, events: { Event })
  local all = state.happenings
  for index = #all.list, 1, -1 do
    local one = all.list[index]
    if one.kind == Happenings.SURGE and state.tick >= one.ends then
      local broken = one.kills >= Happenings.SURGE_BREAK
      all.pressure[one.system] = if broken then 0 else Happenings.SPENT
      Happenings.End(state, one, if broken then "broken" else "over", events)
      Happenings.Mark(state, one.system, if broken then Happenings.MARKS.surgeBroken else Happenings.MARKS.surge,
        if broken then "a surge broken" else "a surge")
    end
  end
  for index = #all.marks, 1, -1 do
    local mark = all.marks[index]
    if state.tick >= mark.ends then
      local node = state.galaxy.systems[mark.system]
      -- (put back as it was, unless somebody else has changed it since)
      if node and node.security == mark.now then
        node.security = mark.was
      end
      table.remove(all.marks, index)
      all.version += 1
    end
  end
end

return Happenings
