--!strict
-- Mishaps: luck, good and bad, that happens to places (the owner's
-- ruling, 2026-11-14: "disasters and windfalls", one of the four kinds
-- of thing going on, Strategic/Happenings). They move prices and
-- routes, not fleets.
--
-- Now and then, within some jumps of the pilot, one of three:
--
--   A station's works out of use: its refinery, its yards or its
--   laboratory, for half a day to a day. What it does there cannot be
--   done until it is mended (Assets/Stations, which asks the list).
--
--   A gate closed for repairs, for a few hours: nothing jumps through
--   it either way, a route is planned round it, and the economy's lane
--   along it carries nothing meanwhile. Only a gate there is a way
--   round is ever closed.
--
--   A rich belt found: a place on the overview of its system, with
--   rocks of a rare ore, for about a day.
--
-- Every figure is a first proposal, and mine.

local Constants = require("@lt/Core/Data/Constants")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Happenings = require("@lt/Core/Strategic/Happenings")
local Ores = require("@lt/Core/Data/Ores")
local Rng = require("@lt/Core/Kernel/Rng")
local Sites = require("@lt/Core/Tactical/Sites")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")

local Mishaps = {}

export type Event = { [string]: any }

local HOUR = math.floor(3600 / Constants.TICK + 0.5)

-- Hours from one to the next, at least and at most; how many are on at
-- once at most; how many jumps from the pilot one can be; the hours
-- each kind lasts; and the share of them that are each kind.
Mishaps.EVERY = { 3, 5 }
Mishaps.MOST = 3
Mishaps.REACH = 10
Mishaps.LASTS = { outage = { 12, 24 }, gate = { 2, 4 }, belt = { 20, 30 } }
Mishaps.ODDS = { outage = 0.4, gate = 0.25, belt = 0.35 }
-- What of a station's can go out of use (never its market, its hangars
-- or its berths: nobody is to be stranded by one).
Mishaps.SERVICES = { "refining", "industry", "research" } :: { Structures.Service }
-- A rich belt: how many rocks of each of its two ores, and the units in each.
Mishaps.ROCKS = 5
Mishaps.UNITS = 30000

local function count(state: State.State): number
  local on = 0
  for _, one in state.happenings.list do
    on += if one.kind == Happenings.DISASTER or one.kind == Happenings.WINDFALL then 1 else 0
  end
  return on
end

-- Whether the gate between two systems is closed.
function Mishaps.Shut(state: State.State, a: number, b: number): boolean
  for _, one in state.happenings.list do
    if one.kind == Happenings.DISASTER and one.what == "gate" and ((one.system == a and one.ref == b) or (one.system == b and one.ref == a)) then
      return true
    end
  end
  return false
end

-- Every closed gate, for whoever plans a way (Galaxy.Route): by the
-- number its two systems make, both ways round.
function Mishaps.Closed(state: State.State): { [number]: boolean }?
  local closed: { [number]: boolean }? = nil
  local span = #state.galaxy.systems + 1
  for _, one in state.happenings.list do
    if one.kind == Happenings.DISASTER and one.what == "gate" and one.ref then
      local found: { [number]: boolean } = closed or {}
      found[one.system * span + one.ref] = true
      found[one.ref * span + one.system] = true
      closed = found
    end
  end
  return closed
end

-- Open or shut the economy's lane between two systems.
local function lane(state: State.State, a: number, b: number, open: boolean)
  for _, edge in state.commerce.edges do
    if (edge.a == a and edge.b == b) or (edge.a == b and edge.b == a) then
      edge.open = open
    end
  end
end

-- Whether there is a way from one system to another that does not use
-- the gate between them (nor any that is closed already).
local function round(state: State.State, a: number, b: number): boolean
  local systems = state.galaxy.systems
  local seen: { [number]: boolean } = { [a] = true }
  local queue = { a }
  local at = 1
  while at <= #queue and at < 6000 do
    local system = queue[at]
    at += 1
    for _, neighbor in systems[system].neighbors do
      if not seen[neighbor] and not (system == a and neighbor == b) and not Mishaps.Shut(state, system, neighbor) then
        if neighbor == b then
          return true
        end
        seen[neighbor] = true
        table.insert(queue, neighbor)
      end
    end
  end
  return false
end

-- Begin one, somewhere within reach of 'here'.
local function begin(state: State.State, here: number, rng: Rng.Rng, events: { Event })
  local galaxy = state.galaxy
  local far = Happenings.Reach(state, here, Mishaps.REACH)
  local heard = Happenings.Reach(state, here, Happenings.HEARD)
  local where: { number } = {}
  for id = 1, Galaxy.Charted(galaxy) do
    if far[id] then
      table.insert(where, id)
    end
  end
  if #where == 0 then
    return
  end
  local roll = Rng.Next(rng)
  local what = if roll < Mishaps.ODDS.outage then "outage" elseif roll < Mishaps.ODDS.outage + Mishaps.ODDS.gate then "gate" else "belt"
  local function hours(kind: string): number
    local lasts = Mishaps.LASTS[kind]
    return math.floor(Rng.Float(rng, lasts[1], lasts[2]) * HOUR)
  end
  if what == "outage" then
    -- (a few tries at a system with a station that has something to lose)
    for _ = 1, 6 do
      local system = where[Rng.Int(rng, #where) + 1]
      for _, object in Space.Glance(state, system).objects do
        if object.kind == "station" and state.starbases[object.id] == nil then
          local service = Mishaps.SERVICES[Rng.Int(rng, #Mishaps.SERVICES) + 1]
          local makeup = Structures.Makeup(object.variety, object.radius, galaxy.systems[system].nearest, false)
          local has, down = false, false
          for _, module in makeup.modules do
            has = has or Structures.moduleById[module].service == service
          end
          for _, one in state.happenings.list do
            down = down or (one.kind == Happenings.DISASTER and one.place == object.id)
          end
          if has and not down then
            Happenings.Begin(state, Happenings.DISASTER, service, system, object.id, hours("outage"), 1,
              `The {Structures.Provider(service)} at {object.name}`, events, heard)
            return
          end
        end
      end
    end
    what = "belt"
  end
  if what == "gate" then
    for _ = 1, 6 do
      local a = where[Rng.Int(rng, #where) + 1]
      local neighbors = galaxy.systems[a].neighbors
      if #neighbors >= 2 then
        local b = neighbors[Rng.Int(rng, #neighbors) + 1]
        if #galaxy.systems[b].neighbors >= 2 and not Mishaps.Shut(state, a, b) and round(state, a, b) then
          local one = Happenings.Begin(state, Happenings.DISASTER, "gate", a, 0, hours("gate"), 1, galaxy.systems[b].name, events, heard)
          one.ref = b
          lane(state, a, b, false)
          return
        end
      end
    end
    what = "belt"
  end
  local system = where[Rng.Int(rng, #where) + 1]
  if Happenings.In(state, system, Happenings.WINDFALL) == nil then
    Happenings.Begin(state, Happenings.WINDFALL, "belt", system, 0, hours("belt"), 1, "", events, heard)
  end
end

-- A rich belt, with the pilot in its system: staked, with its rocks.
local function belt(state: State.State, one: State.Happening): boolean
  if one.place ~= 0 then
    return true
  end
  local rng = Rng.For(state.historySeed, one.id, 1311)
  local site = Sites.Stake(state, one.system, rng, "Rich Belt")
  if site == nil then
    return false
  end
  one.place = site.id
  for _ = 1, 2 do
    -- (of the ores that are rare: the first shares of the wild ones)
    local ore = Ores.Pick(Rng.Next(rng) * 0.04, true)
    Sites.Rocks(state, site, rng, ore.id, Mishaps.ROCKS, Mishaps.UNITS)
  end
  return true
end

-- Once a tick: one that is due begins, a rich belt the pilot is in the
-- system of is put there, and those whose time is up end: a gate opens
-- and its lane with it, a belt is let go. 'here' is the system the
-- pilot is in.
function Mishaps.Step(state: State.State, here: number, events: { Event })
  local all = state.happenings
  if state.tick >= all.placeDue then
    local rng = Rng.For(state.historySeed, all.count, state.tick, 1309)
    all.placeDue = state.tick + math.floor(Rng.Float(rng, Mishaps.EVERY[1], Mishaps.EVERY[2]) * HOUR)
    if count(state) < Mishaps.MOST and not state.galaxy.systems[here].uncharted then
      begin(state, here, rng, events)
    end
  end
  for index = #all.list, 1, -1 do
    local one = all.list[index]
    if one.kind ~= Happenings.DISASTER and one.kind ~= Happenings.WINDFALL then
      continue
    end
    local over = state.tick >= one.ends
    if not over and one.kind == Happenings.WINDFALL and one.system == here then
      over = not belt(state, one)
    end
    if over then
      if one.what == "gate" and one.ref then
        lane(state, one.system, one.ref, true)
      elseif one.kind == Happenings.WINDFALL and one.place ~= 0 and state.sites[one.place] then
        Sites.Release(state, one.place, events)
      end
      Happenings.End(state, one, "over", events)
    end
  end
end

return Mishaps
