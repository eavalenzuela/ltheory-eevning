--!strict
-- Captains: the pirates who lead, by name, region by region.
--
-- The owner's rulings (2026-11-22): a job's chief is a named pirate, a
-- veteran at the first two levels and a captain at the last two; and
-- the names are a roster, not new every time. So each region of the
-- galaxy (Describe/Galaxy: a score or so of systems; uncharted space is
-- one) has a handful of pirates who lead there:
--   - Whoever leads a camp a job is against, a sighting's camp or (in
--     time) a fortress is one of the region's, by name.
--   - One the pilot fails to bring down (the job given up or let lapse,
--     the sighting over with them alive) is still about, and turns up
--     again with more on their head: half as much again for every time
--     they got away, up to three times what one of their kind is worth.
--   - One brought down is gone for good, and somebody new comes up in
--     their place: the roster is always full.
--
-- The roster is made as it is asked for, so a region nobody goes near
-- has nobody in it yet. (How many to a region and what getting away is
-- worth: mine.)

local Names = require("@lt/Core/Describe/Names")
local Rng = require("@lt/Core/Kernel/Rng")
local State = require("@lt/Core/Kernel/State")

local Captains = {}

export type Event = { [string]: any }

-- How many lead in a region at once; what each time they got away adds
-- to what is on their head (a share of it); and the most it comes to.
Captains.ROSTER = 5
Captains.GROWTH = 0.5
Captains.MOST = 3

-- The roster of a system's region, filled up to its number with new
-- names where some are gone (or none were ever made).
local function roster(state: State.State, system: number): { State.Captain }
  local region = state.galaxy.systems[system].region
  local all = state.captains
  local here: { State.Captain } = {}
  for _, id in all.ids do
    local one = all.list[id]
    if one.region == region and one.alive then
      table.insert(here, one)
    end
  end
  while #here < Captains.ROSTER do
    all.made += 1
    local rng = Rng.For(state.historySeed, region, all.made, 2251)
    local one: State.Captain = { id = all.made, name = Names.Person(rng), region = region, escapes = 0, alive = true }
    all.list[one.id] = one
    table.insert(all.ids, one.id)
    table.insert(here, one)
  end
  return here
end

-- One of the pirates who lead in a system's region, chosen by 'salt'
-- (whatever it is they are to lead: a job, a sighting), and the same
-- one for the same salt while the roster stands as it does.
function Captains.Pick(state: State.State, system: number, salt: number): State.Captain
  local here = roster(state, system)
  return here[Rng.Int(Rng.For(state.historySeed, salt, 2253), #here) + 1]
end

-- A captain by id, if there is one by it.
function Captains.Get(state: State.State, id: number?): State.Captain?
  return if id then state.captains.list[id] else nil
end

-- How many times what is on one of their kind's head is on theirs.
function Captains.Price(one: State.Captain): number
  return math.min(Captains.MOST, 1 + Captains.GROWTH * one.escapes)
end

-- What a named pirate flies under: "Captain <name>" for a captain, and
-- "<name>, Veteran <kind>" for a veteran ('short': the kind's name with
-- the "Pirate" taken off, "Raider").
function Captains.Called(one: State.Captain, grade: number, short: string): string
  return if grade >= 2 then `Captain {one.name}` else `{one.name}, Veteran {short}`
end

-- They have been brought down: gone, and the next asked for in their
-- region is somebody new.
function Captains.Killed(state: State.State, id: number, events: { Event })
  local one = state.captains.list[id]
  if one and one.alive then
    one.alive = false
    table.insert(events, { kind = "CaptainKilled", captain = id, name = one.name })
  end
end

-- What they led is over and they are not brought down: they got away,
-- and will be worth more the next time.
function Captains.Escaped(state: State.State, id: number, events: { Event })
  local one = state.captains.list[id]
  if one and one.alive then
    one.escapes += 1
    table.insert(events, { kind = "CaptainEscaped", captain = id, name = one.name, price = Captains.Price(one) })
  end
end

return Captains
