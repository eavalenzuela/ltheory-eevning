--!strict
-- Where the pilot is next to go: the places of the system they are in
-- that lie on the way to something they have set out to do, for the
-- overview and the brackets to pick out.
--
--   - With somewhere to go (a destination set on the map), the gate that
--     leads the next jump of the way there.
--   - For each job in hand (Assets/Missions): where it is to be done, or,
--     once it is done, where it is paid. A bounty has no one place (its
--     pirates are at the belts of its system). An assault's is the room
--     of its camp the pilot has got to, or, once that room is cleared,
--     the gate in it that leads on. A mining contract's is its
--     pocket, until the ore is aboard. A courier run's is where the
--     cargo goes, or, while the cargo is not aboard, where it is.
--   - For a lesson of a career agent's that is done and not yet reported
--     (Character/Careers), the agents' station.
-- Each is a place in this system, or, when it lies in another, the gate
-- that leads the way to that one.
--
-- Worked out once a tick, and again when the pilot changes where they
-- mean to go.

local Core = require("@lt/Core/Api")
local Session = require("@lt/Game/Session")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")

local Waypoints = {}

-- By the id of the place: why it is one ("route", "job", "lesson").
export type Marks = { [number]: string }

local cached: Marks = {}
local stamp = ""

-- How many of a type are in the hold of the pilot's ship.
local function aboard(game: Core.Game, ship: number, type: string): number
  local have = 0
  for _, item in Core.Query.Items(game, ship, "cargo") do
    have += if item.type == type then item.quantity else 0
  end
  return have
end

-- Where a job in hand takes the pilot next: a place, and the system it
-- is in (0 and the system, for a job with no one place there).
local function stop(game: Core.Game, ship: number, mission: State.Mission): (number, number)
  local state = game.state
  local home = Space.SystemOf(state, mission.station)
  if mission.kind == "bounty" then
    if mission.done >= mission.need then
      return mission.station, home
    end
    return 0, mission.system
  elseif mission.kind == "courier" then
    if aboard(game, ship, mission.type) >= mission.need then
      return mission.to, Space.SystemOf(state, mission.to)
    end
    return mission.station, home
  elseif mission.kind == "mining" then
    if aboard(game, ship, mission.type) >= mission.need or mission.site == 0 then
      return mission.station, home
    end
    return mission.site, mission.system
  elseif mission.kind == "assault" then
    local done = if mission.aim == "fetch" then aboard(game, ship, mission.type) >= mission.need else mission.done >= mission.need
    if done or mission.site == 0 then
      return mission.station, home
    elseif mission.aim == "convoy" and mission.done >= 1 then
      -- (a convoy's tender that has left its place is to be followed to where it is going)
      return mission.to, mission.system
    end
    -- (the room the pilot has got to: the last whose way is found; or,
    -- with that room cleared, its gate, which leads on)
    local room = mission.site
    for _, id in mission.rooms do
      if Core.Query.Found(game, id) then
        room = id
      end
    end
    for _, object in Core.Query.Objects(game, mission.system) do
      if object.kind == "gate" and object.variety == "passage" and object.site == room
        and Core.Validate(game, { kind = "Jump", actor = ship, target = object.id }) then
        return object.id, mission.system
      end
    end
    return room, mission.system
  end
  -- (a supply order: what it wants is brought to its station)
  return mission.station, home
end

-- The systems, other than the one the pilot is in, that what they have
-- set out to do lies in: for each job in hand, where it is next to be
-- done or paid, and for a lesson to report, the agents' system. By the
-- system's id: why ("job", "lesson"). For the map.
function Waypoints.Systems(session: Session.Session): { [number]: string }
  local game = session.game
  local player = Core.Query.Player(game)
  local found: { [number]: string } = {}
  for _, held in Core.Query.Missions(game).inHand do
    local _, system = stop(game, player.ship, held.mission)
    if system ~= player.system then
      found[system] = "job"
    end
  end
  local careers = Core.Query.Careers(game)
  for _, row in careers.rows do
    if row.taken and row.lesson and row.lesson.bring == nil and row.have >= row.need then
      local system = Space.SystemOf(game.state, careers.station)
      if system ~= player.system and found[system] == nil then
        found[system] = "lesson"
      end
    end
  end
  return found
end

function Waypoints.Of(session: Session.Session): Marks
  local game = session.game
  local state = game.state
  local player = Core.Query.Player(game)
  local key = `{session.epoch}:{state.tick}:{player.system}:{session.destination}:{session.safest}`
  if key == stamp then
    return cached
  end
  stamp = key
  local marks: Marks = {}
  cached = marks
  local objects = Core.Query.Objects(game, player.system)
  -- The gate of this system that leads the way to another.
  local function toward(system: number): number
    local route = Session.Way(session, player.system, system, session.safest)
    for _, object in objects do
      if object.kind == "gate" and object.to == route[2] then
        return object.id
      end
    end
    return 0
  end
  local function mark(place: number, system: number, why: string)
    local id = if system == player.system then place else toward(system)
    if id ~= 0 and marks[id] == nil then
      marks[id] = why
    end
  end

  if session.destination ~= 0 and session.destination ~= player.system and state.galaxy.systems[session.destination] then
    mark(0, session.destination, "route")
  end
  for _, held in Core.Query.Missions(game).inHand do
    local place, system = stop(game, player.ship, held.mission)
    mark(place, system, "job")
  end
  local careers = Core.Query.Careers(game)
  for _, row in careers.rows do
    if row.taken and row.lesson and row.lesson.bring == nil and row.have >= row.need then
      mark(careers.station, Space.SystemOf(state, careers.station), "lesson")
    end
  end
  return marks
end

return Waypoints
