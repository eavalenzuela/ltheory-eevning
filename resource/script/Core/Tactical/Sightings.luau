--!strict
-- Sightings: something rare, seen for an hour or two, that a pilot
-- could go to (the owner's ruling, 2026-11-14: one of the four kinds of
-- thing going on, Strategic/Happenings).
--
-- Now and then, within a few jumps of the pilot, one of three:
--
--   A pirate captain, by name, with a small escort. Their camp is a
--   place on the overview of the system they are in. They are a
--   captain of what that space brings (Tactical/Pirates), with three
--   times the price on their head, and what they carry is in the
--   wreck: custom makes, and tags.
--
--   A derelict hull, adrift: a derelict as any other (Tactical/Sites),
--   but found already, and gone when the sighting is.
--
--   A wandering trader, by name, lying at a station: while they stay
--   the station's board has three lots of theirs (Assets/Contracts).
--
-- Nothing is put in space until the pilot is in the system: until then
-- a sighting is a line on a list. A sighting that is taken (the captain
-- destroyed, the derelict emptied) is over; the rest are over when
-- their time is.
--
-- Every figure is a first proposal, and mine.

local Constants = require("@lt/Core/Data/Constants")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Happenings = require("@lt/Core/Strategic/Happenings")
local Items = require("@lt/Core/Assets/Items")
local Names = require("@lt/Core/Describe/Names")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Rng = require("@lt/Core/Kernel/Rng")
local Sites = require("@lt/Core/Tactical/Sites")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")

local Sightings = {}

export type Event = { [string]: any }

local HOUR = math.floor(3600 / Constants.TICK + 0.5)

-- Hours from one to the next, at least and at most; how many are on at
-- once at most; how many jumps from the pilot one can be; and the hours
-- each kind lasts.
Sightings.EVERY = { 1, 2 }
Sightings.MOST = 3
Sightings.REACH = 8
Sightings.LASTS = { captain = { 1, 2 }, derelict = { 1.5, 3 }, trader = { 2, 4 } }
-- The share of them that are each kind (a captain only where order is
-- thin and pirates come at all, a trader only where there is a station).
Sightings.ODDS = { captain = 0.4, derelict = 0.35, trader = 0.25 }
-- What a captain is, by the space they are in, and who is with them;
-- how many times a captain's price is on their head; and what is in
-- the wreck beside what any captain's has: custom makes, and tags.
Sightings.CAPTAIN = { low = "jackal", lawless = "marauder" }
Sightings.ESCORT = { low = { "raider", "raider" }, lawless = { "jackal", "raider", "raider" } }
Sightings.BOUNTY = 3
Sightings.PRIZES = 3
Sightings.TAGS = 8
-- How far from the middle of their camp they lie, m.
Sightings.OUT = 9000

local function count(state: State.State): number
  local on = 0
  for _, one in state.happenings.list do
    on += if one.kind == Happenings.SIGHTING then 1 else 0
  end
  return on
end

-- A station of a system that has a board, if it has one: the first.
local function station(state: State.State, system: number): number
  for _, object in Space.Glance(state, system).objects do
    if object.kind == "station" and state.starbases[object.id] == nil then
      return object.id
    end
  end
  return 0
end

-- Begin one, somewhere within reach of 'here'.
local function begin(state: State.State, here: number, rng: Rng.Rng, events: { Event })
  local galaxy = state.galaxy
  local far = Happenings.Reach(state, here, Sightings.REACH)
  local where: { number } = {}
  for id = 1, Galaxy.Charted(galaxy) do
    if far[id] and Happenings.In(state, id, Happenings.SIGHTING) == nil then
      table.insert(where, id)
    end
  end
  if #where == 0 then
    return
  end
  local system = where[Rng.Int(rng, #where) + 1]
  local band = Galaxy.Band(galaxy.systems[system].security)
  local roll = Rng.Next(rng)
  local what = if roll < Sightings.ODDS.captain then "captain"
    elseif roll < Sightings.ODDS.captain + Sightings.ODDS.derelict then "derelict" else "trader"
  local place = 0
  if what == "captain" and (state.peaceful or band == "secure") then
    what = "derelict"
  elseif what == "trader" then
    place = station(state, system)
    what = if place == 0 then "derelict" else what
  end
  local lasts = Sightings.LASTS[what]
  Happenings.Begin(state, Happenings.SIGHTING, what, system, place, math.floor(Rng.Float(rng, lasts[1], lasts[2]) * HOUR), 1,
    if what == "derelict" then "" else Names.Person(rng), events, Happenings.Reach(state, here, Happenings.HEARD))
end

-- A captain's sighting, with the pilot in the system: their camp is
-- staked, they and theirs are there when the pilot comes to it, and
-- when the captain is destroyed what they carried is in the wreck.
-- Returns how it has ended, if it has.
local function captain(state: State.State, one: State.Happening, me: State.Ball?, events: { Event }): string?
  local rng = Rng.For(state.historySeed, one.id, 1303)
  if one.place == 0 then
    local site = Sites.Stake(state, one.system, rng, `{one.name}'s Camp`)
    if site == nil then
      return "gone"
    end
    one.place = site.id
  end
  local place = Space.Object(state, one.place)
  if place == nil then
    return "gone"
  end
  if one.stage == 1 and me and me.grid == one.place then
    local band = if Galaxy.Band(state.galaxy.systems[one.system].security) == "lawless" then "lawless" else "low"
    local kind = Pirates.Graded(Pirates.kindById[Sightings.CAPTAIN[band]], 2)
    local turn = Rng.Float(rng, 0, 2 * math.pi)
    local ball = Pirates.Spawn(state, kind, one.system, place.x + Sightings.OUT * math.cos(turn), place.y,
      place.z + Sightings.OUT * math.sin(turn), one.place)
    -- (by their own name, with more on their head than a captain has)
    ball.name = one.name
    state.ships[ball.id].name = one.name
    state.pilots[ball.id].bounty *= Sightings.BOUNTY
    table.insert(events, { kind = "BallAdded", ball = ball.id })
    for index, with in Sightings.ESCORT[band] do
      local beside = turn + 0.12 * index
      local escort = Pirates.Spawn(state, Pirates.kindById[with], one.system, place.x + (Sightings.OUT + 600 * index) * math.cos(beside),
        place.y, place.z + (Sightings.OUT + 600 * index) * math.sin(beside), one.place)
      table.insert(events, { kind = "BallAdded", ball = escort.id })
    end
    one.ref, one.stage = ball.id, 2
  elseif one.stage == 2 and state.ships[one.ref or 0] == nil then
    -- (destroyed: what they carried is in what is left of them)
    for index = #state.wreckIds, 1, -1 do
      local wreck = state.wrecks[state.wreckIds[index]]
      if wreck.system == one.system and wreck.name == one.name .. " Wreck" then
        Sites.Prizes(state, rng, wreck.id, Sightings.PRIZES)
        Items.Add(state, "tag.pirate", Sightings.TAGS, wreck.id, "cargo")
        break
      end
    end
    one.kills += 1
    return "taken"
  end
  return nil
end

-- A derelict's sighting, with the pilot in the system: it is there,
-- found, and when it has been emptied the sighting is over.
local function derelict(state: State.State, one: State.Happening, events: { Event }): string?
  if one.place == 0 then
    local site = Sites.Plant(state, one.system, "relic", Rng.For(state.historySeed, one.id, 1307), events)
    if site == nil then
      return "gone"
    end
    -- (found already, and there as long as the sighting is)
    site.strength, site.expires = 1, one.ends
    one.place = site.id
  end
  local site = state.sites[one.place]
  return if site == nil or site.gone then "taken" else nil
end

-- Let go of what a sighting put in space.
local function release(state: State.State, one: State.Happening, events: { Event })
  if one.place ~= 0 and one.what ~= "trader" and state.sites[one.place] then
    Sites.Release(state, one.place, events)
  end
end

-- Once a tick: a sighting that is due begins, those the pilot is in the
-- system of are put in space and looked after, and those that are over
-- end. 'here' is the system the pilot is in.
function Sightings.Step(state: State.State, here: number, events: { Event })
  local all = state.happenings
  if state.tick >= all.sightingDue then
    local rng = Rng.For(state.historySeed, all.count, state.tick, 1301)
    all.sightingDue = state.tick + math.floor(Rng.Float(rng, Sightings.EVERY[1], Sightings.EVERY[2]) * HOUR)
    if count(state) < Sightings.MOST and not state.galaxy.systems[here].uncharted then
      begin(state, here, rng, events)
    end
  end
  local me = state.balls[state.player.ship]
  for index = #all.list, 1, -1 do
    local one = all.list[index]
    if one.kind ~= Happenings.SIGHTING then
      continue
    end
    local outcome: string? = nil
    if state.tick >= one.ends then
      outcome = "gone"
    elseif one.system == here then
      if one.what == "captain" then
        outcome = captain(state, one, me, events)
      elseif one.what == "derelict" then
        outcome = derelict(state, one, events)
      end
    end
    if outcome then
      release(state, one, events)
      Happenings.End(state, one, outcome, events)
    end
  end
end

return Sightings
