--!strict
-- Nomads: where a wandering people's colony ships are.
--
-- A people that keeps no stations (Data/Factions' 'nomad': the Kethri)
-- has colony ships, each with a support fleet in tow, which roam the
-- space it holds. A colony fleet goes round and round a walk of its
-- people's systems: out from the homeworld by every gate that leads
-- into more of their space and back again, so that each step of it is
-- a jump through a gate, and every system of theirs that their own
-- space reaches sees it come by. It stays a quarter of an hour in each.
-- A people has a fleet for every ten systems it holds, and one at the
-- least, spaced out along the same walk.
--
-- Where a fleet is follows from the galaxy and the tick and from
-- nothing else. The ships themselves are only there where the pilot is
-- (Tactical/Traffic puts them there, and takes them away: they are
-- traffic, like everybody else about). One thing is remembered: a
-- colony ship that has been destroyed is gone for a day (state.nomads)
-- before another takes its place on the walk.
--
-- (First figures, all of them: how long a fleet stays, how many there
-- are, and what a support fleet is made of. The project owner's word is
-- that the colony ship roams their space with its support fleet in tow.)
--
-- A colony ship is a station too, and the only kind such a people has
-- (the project owner's, 2026-11-13: "they're all roaming colony ships,
-- no stationary ones"): a pilot docks at it, and it has its hangar, its
-- market and its agents aboard, which go where it goes. So a pilot
-- docked in one, the ships and the goods they left there, and a pilot
-- hired to wait there, all travel with it; and the same ship is at a
-- different star when the pilot comes back for what is aboard. As a
-- station it has an id like any other, which is not of any one system:
-- Nomads.StationId. (Where it is as a place, and what docking at it is:
-- Tactical/Space, which asks here whose a station is and where.)

local Constants = require("@lt/Core/Data/Constants")
local Factions = require("@lt/Core/Data/Factions")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Names = require("@lt/Core/Describe/Names")
local Ships = require("@lt/Core/Data/Ships")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")

local Nomads = {}

-- Systems to a colony fleet: a people has one for every so many of the
-- systems it holds, and one at least. (One to thirty at first, when a
-- people had a colony ship moored in every system beside: they are the
-- only places to dock in its space now, so there are three times as
-- many.)
Nomads.SPAN = 10
-- How far off the gate it lies by a colony ship keeps, metres between
-- them.
Nomads.OFF = 30000
-- The stations that colony ships are have ids of a system no galaxy
-- has: this one (ids are system * Constants.STRUCTURE_ID_SPAN + index,
-- and a galaxy is a few thousand systems). A fleet's is its index there.
Nomads.SYSTEM = 90000
-- Ticks a fleet stays in a system.
Nomads.STAY = math.floor(900 / Constants.TICK + 0.5)
-- Ticks a colony ship that was destroyed is gone for.
Nomads.GONE = math.floor(86400 / Constants.TICK + 0.5)
-- What a support fleet is: so many hulls of its people's of each class.
Nomads.SUPPORT = { { "carrier", 1 }, { "battleship", 2 }, { "battlecruiser", 2 }, { "destroyer", 3 }, { "frigate", 4 },
  { "industrial", 2 } } :: { { any } }

export type Fleet = {
  index: number,      -- which fleet of the galaxy's it is, from 1
  faction: string,
  hull: string,       -- its colony ship's hull
  name: string,       -- and what that ship is called
  -- The systems it goes through, round and round: each a gate from the
  -- one before, and the first a gate from the last.
  walk: { number },
  start: number,      -- how far along the walk it is at tick 0
}

-- A people's colony ship: the hull, if it has one.
local function colonyShip(faction: Factions.Faction): Ships.ShipType?
  if not faction.nomad then
    return nil
  end
  for _, hull in Ships.list do
    if hull.lineage == faction.id and hull.class == "ultracapital" then
      return hull
    end
  end
  return nil
end

-- The walk of a people's space from its homeworld.
local function walkFrom(galaxy: Galaxy.Galaxy, home: number): { number }
  local systems = galaxy.systems
  local whose = systems[home].owner
  local walk: { number } = { home }
  local seen: { [number]: boolean } = { [home] = true }
  local function visit(id: number)
    for _, neighbor in systems[id].neighbors do
      if not seen[neighbor] and systems[neighbor].owner == whose then
        seen[neighbor] = true
        table.insert(walk, neighbor)
        visit(neighbor)
        table.insert(walk, id)
      end
    end
  end
  visit(home)
  -- (it ends where it began: once is enough)
  if #walk > 1 then
    table.remove(walk)
  end
  return walk
end

-- The colony fleets of a galaxy. (Worked out once for a galaxy and kept
-- beside it, as Galaxy.Holders is.)
local known: { [any]: { Fleet } } = setmetatable({}, { __mode = "k" }) :: any
function Nomads.Fleets(galaxy: Galaxy.Galaxy): { Fleet }
  local kept = known[galaxy]
  if kept == nil then
    kept = {}
    for _, faction in Factions.list do
      local hull = colonyShip(faction)
      local home = 0
      for id, system in galaxy.systems do
        if system.home and system.owner == faction.id then
          home = id
        end
      end
      if hull and home ~= 0 then
        local walk = walkFrom(galaxy, home)
        local reached: { [number]: boolean } = {}
        local held = 0
        for _, id in walk do
          held += if reached[id] then 0 else 1
          reached[id] = true
        end
        local class = Structures.ColonyShip(faction.id)
        local count = math.max(1, held // Nomads.SPAN)
        for number = 1, count do
          table.insert(kept, {
            index = #kept + 1, faction = faction.id, hull = hull.id,
            name = (if class then class.name else hull.name) .. (if number > 1 then ` {Names.Roman(number)}` else ""),
            walk = walk, start = (number - 1) * #walk // count,
          })
        end
      end
    end
    known[galaxy] = kept
  end
  return kept
end

-- Where a fleet is at a tick: the system, the one it came from and the
-- one it goes to next (the same system, for a people with only the
-- one), the tick it came and the tick it goes.
function Nomads.At(fleet: Fleet, tick: number): (number, number, number, number, number)
  local walk = fleet.walk
  local stay = tick // Nomads.STAY
  local step = (stay + fleet.start) % #walk
  return walk[step + 1], walk[(step - 1) % #walk + 1], walk[(step + 1) % #walk + 1], stay * Nomads.STAY, (stay + 1) * Nomads.STAY
end

-- The id of the station a fleet's colony ship is.
function Nomads.StationId(index: number): number
  return Nomads.SYSTEM * Constants.STRUCTURE_ID_SPAN + index
end

-- The fleet whose colony ship a station is, by the station's id: nil
-- for the id of anything else.
function Nomads.FleetOf(galaxy: Galaxy.Galaxy, id: number): Fleet?
  if id // Constants.STRUCTURE_ID_SPAN ~= Nomads.SYSTEM then
    return nil
  end
  return Nomads.Fleets(galaxy)[id % Constants.STRUCTURE_ID_SPAN]
end

-- A fleet's colony ship as a ship in space, if it is there to be seen
-- (Tactical/Traffic puts it there, where the pilot is): its ball.
function Nomads.Ball(state: State.State, fleet: Fleet): State.Ball?
  for _, id in state.trafficIds do
    local record = state.traffic[id]
    if record.kind == "colony" and record.wait == fleet.index then
      return state.balls[id]
    end
  end
  return nil
end

-- The station a ship in space is, if it is a colony ship: its id. Nil
-- for any other ship. (To dock at the ship is to dock at the station.)
function Nomads.Berth(state: State.State, ball: number): number?
  local record = state.traffic[ball]
  if record == nil or record.kind ~= "colony" or state.balls[ball] == nil then
    return nil
  end
  return Nomads.StationId(record.wait)
end

-- Whether a fleet's colony ship is gone: destroyed, and not yet
-- replaced.
function Nomads.Gone(state: State.State, fleet: Fleet): boolean
  return (state.nomads[fleet.index] or 0) > state.tick
end

-- Every colony fleet there is now, and where: for the map.
export type Sighting = { faction: string, name: string, system: number, next: number, leaves: number }
function Nomads.Where(state: State.State): { Sighting }
  local found: { Sighting } = {}
  for _, fleet in Nomads.Fleets(state.galaxy) do
    if not Nomads.Gone(state, fleet) then
      local system, _, next, _, leaves = Nomads.At(fleet, state.tick)
      table.insert(found, { faction = fleet.faction, name = fleet.name, system = system, next = next, leaves = leaves })
    end
  end
  return found
end

return Nomads
