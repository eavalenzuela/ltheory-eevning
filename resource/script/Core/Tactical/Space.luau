--!strict
-- Ships in space: the commands that steer them and the tick that moves
-- them. Flight is by command only (approach, orbit, keep at range, align,
-- warp, dock, jump); nobody steers by hand.
--
-- Things in space come in two kinds. Bodies described by the galaxy
-- generator (the sun, planets, moons, belts, asteroids, stations, gates)
-- never move and live in the system's description. Ships are Balls in
-- state.balls. Space.Body finds either by id.
--
-- Distances in commands and ranges are between surfaces, as a pilot
-- thinks of them: 0 means touching.

local Constants = require("@lt/Core/Data/Constants")
local Items = require("@lt/Core/Assets/Items")
local Motion = require("@lt/Core/Tactical/Motion")
local Nomads = require("@lt/Core/Tactical/Nomads")
local Rng = require("@lt/Core/Kernel/Rng")
local Modules = require("@lt/Core/Data/Modules")
local Ships = require("@lt/Core/Data/Ships")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")
local Vitals = require("@lt/Core/Tactical/Vitals")

local Space = {}

-- What a Ball and a described Object have in common.
export type Body = {
  id: number,
  kind: string,
  name: string,
  x: number,
  y: number,
  z: number,
  radius: number,
}

export type Event = { [string]: any }

local SPAN = Constants.STRUCTURE_ID_SPAN

-- How long the name of a place the pilot has marked may be.
Space.PLACE_NAME = 32

-- A name for a marked place as it would be kept (the spaces at its ends
-- gone, and runs of them inside it made one), or nil and why it will
-- not do.
function Space.PlaceName(text: string): (string?, string?)
  local name = string.gsub(string.gsub(string.gsub(text, "^%s+", ""), "%s+$", ""), "%s+", " ")
  if #name < 1 then
    return nil, "a place has a name"
  elseif #name > Space.PLACE_NAME then
    return nil, `a name has {Space.PLACE_NAME} letters at most`
  elseif string.find(name, "[^%w '&%.%-]") then
    return nil, "a name is of letters, figures and spaces"
  end
  return name
end

-- ---------------------------------------------------------------------
-- Looking things up

-- The description of a system, made (and kept in the state) on first use.
function Space.Describe(state: State.State, system: number): System.Description
  local description = state.systems[system]
  if description == nil then
    description = System.Describe(state.galaxy, system)
    state.systems[system] = description
  end
  return description
end

-- (A colony ship of the nomads as the station it is: below, after Space.Glance.)
local colonyStation: (state: State.State, fleet: Nomads.Fleet) -> System.Object

-- The fleet whose colony ship a station is, if it is one: by its id.
function Space.Colony(state: State.State, id: number): Nomads.Fleet?
  return Nomads.FleetOf(state.galaxy, id)
end

-- The described object with this id, if its system has been described.
-- (And a colony ship of the nomads, which is a station of no system's
-- description, wherever it is now.)
function Space.Object(state: State.State, id: number): System.Object?
  if id <= 0 or id >= Constants.FIRST_DYNAMIC_ID then
    return nil
  end
  local fleet = Nomads.FleetOf(state.galaxy, id)
  if fleet then
    return colonyStation(state, fleet)
  end
  local description = state.systems[id // SPAN]
  return if description then description.objects[id % SPAN] else nil
end

-- A system's description for a look at it, which is not kept: the
-- state's own if the system has been described, and otherwise what it
-- would be (it follows from the galaxy alone), remembered here beside
-- the galaxy and not in the state. For asking what is where a pilot has
-- never been (what the markets some jumps off sell, say) without
-- putting every system asked about into the save.
type Glances = { [number]: System.Description }
local glances: { [any]: Glances } = setmetatable({} :: any, { __mode = "k" })

function Space.Glance(state: State.State, system: number): System.Description
  local kept = state.systems[system]
  if kept then
    return kept
  end
  local seen = glances[state.galaxy]
  if seen == nil then
    seen = {}
    glances[state.galaxy] = seen
  end
  local description = seen[system]
  if description == nil then
    description = System.Describe(state.galaxy, system)
    seen[system] = description
  end
  return description
end

-- A colony ship of the nomads, as the station it is (Tactical/Nomads):
-- an object like a described one, but of no system's description. It
-- is in the system its fleet is in at this tick, where its ship is if
-- that is in space to be seen, and otherwise off the gate it will leave
-- by, on the side away from the sun. It is made each time it is asked
-- for (nothing of it is kept: it follows from the galaxy, the tick and
-- where its ship is).
function colonyStation(state: State.State, fleet: Nomads.Fleet): System.Object
  local system, _, to = Nomads.At(fleet, state.tick)
  local hull = Ships.byId[fleet.hull]
  -- (a system nobody has been to has its gates too)
  local description = Space.Glance(state, system)
  local gate: System.Object? = nil
  for _, object in description.objects do
    if object.kind == "gate" and object.variety ~= "passage" and (gate == nil or object.to == to) then
      gate = object
      if object.to == to then
        break
      end
    end
  end
  local x, y, z, site = 0, 0, 0, 0
  local ball = Nomads.Ball(state, fleet)
  if ball and ball.system == system then
    x, y, z, site = ball.x, ball.y, ball.z, ball.grid
  elseif gate then
    local far = math.sqrt(gate.x ^ 2 + gate.y ^ 2 + gate.z ^ 2)
    local out = gate.radius + Nomads.OFF + hull.radius
    local ux, uy, uz = 1, 0, 0
    if far > 0 then
      ux, uy, uz = gate.x / far, gate.y / far, gate.z / far
    end
    x, y, z, site = gate.x + ux * out, gate.y + uy * out, gate.z + uz * out, gate.site
  end
  return {
    id = Nomads.StationId(fleet.index), kind = "station", name = fleet.name, x = x, y = y, z = z, radius = hull.radius,
    seed = 0, parent = if gate then gate.id else 0, site = site, variety = System.COLONY_SHIP, to = 0,
  }
end

-- The described object with this id, whether or not its system has
-- been described yet (Space.Glance).
function Space.Peek(state: State.State, id: number): System.Object?
  local fleet = Nomads.FleetOf(state.galaxy, id)
  if fleet then
    return colonyStation(state, fleet)
  end
  if id <= 0 or id >= Constants.FIRST_DYNAMIC_ID or state.galaxy.systems[id // SPAN] == nil then
    return nil
  end
  return Space.Glance(state, id // SPAN).objects[id % SPAN]
end

-- Anything in space by id: a ship's ball, a wreck or a described object.
function Space.Body(state: State.State, id: number): Body?
  local ball = state.balls[id]
  if ball then
    return ball :: any
  end
  local wreck = state.wrecks[id]
  if wreck then
    return wreck :: any
  end
  return Space.Object(state, id) :: any
end

-- A place the pilot has marked, as something to warp or align to: a
-- point, with no size. (It is not a Body to anything else: nothing is
-- there to approach, orbit or lock.)
function Space.Marked(state: State.State, id: number): Body?
  local mark = state.bookmarks[id]
  if mark == nil then
    return nil
  end
  return { id = mark.id, kind = "bookmark", name = mark.name, x = mark.x, y = mark.y, z = mark.z, radius = 0 }
end

-- How many places a pilot can have marked at once.
Space.BOOKMARKS = 40

-- The system a body is in.
function Space.SystemOf(state: State.State, id: number): number
  local ball = state.balls[id]
  if ball then
    return ball.system
  end
  local mark = state.bookmarks[id]
  if mark then
    return mark.system
  end
  local wreck = state.wrecks[id]
  if wreck then
    return wreck.system
  end
  -- (a colony ship of the nomads is in the system its fleet is in now)
  local fleet = Nomads.FleetOf(state.galaxy, id)
  if fleet then
    return (Nomads.At(fleet, state.tick))
  end
  return if id < Constants.FIRST_DYNAMIC_ID then id // SPAN else 0
end

-- The grid a body is on: a ball's or a wreck's own, a described object's
-- site, or 0.
function Space.GridOf(state: State.State, id: number): number
  local ball = state.balls[id]
  if ball then
    return ball.grid
  end
  local wreck = state.wrecks[id]
  if wreck then
    return wreck.grid
  end
  local object = Space.Object(state, id)
  return if object then object.site else 0
end

function Space.Distance(a: Body, b: Body): number
  return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end

-- Metres between two surfaces; 0 if they touch or overlap.
function Space.Gap(a: Body, b: Body): number
  return math.max(0, Space.Distance(a, b) - a.radius - b.radius)
end

-- ---------------------------------------------------------------------
-- Grids

-- Put 'ball' on the grid its position belongs to: the nearest station,
-- gate or belt within GRID_RADIUS, else the nearest open-space grid, else
-- a new open-space grid made where it is.
function Space.AssignGrid(state: State.State, ball: State.Ball)
  local best, bestDistance = 0, Constants.GRID_RADIUS
  for _, object in Space.Describe(state, ball.system).objects do
    if object.site == object.id then
      local d = Space.Distance(ball :: any, object :: any)
      if d < bestDistance then
        best, bestDistance = object.id, d
      end
    end
  end
  if best == 0 then
    for _, id in state.gridIds do
      local grid = state.grids[id]
      if grid.system == ball.system then
        local d = math.sqrt((grid.x - ball.x) ^ 2 + (grid.y - ball.y) ^ 2 + (grid.z - ball.z) ^ 2)
        if d < bestDistance then
          best, bestDistance = id, d
        end
      end
    end
  end
  if best == 0 then
    best = State.NewId(state)
    state.grids[best] = { id = best, system = ball.system, x = ball.x, y = ball.y, z = ball.z }
    table.insert(state.gridIds, best)
  end
  ball.grid = best
end

-- Where a grid is anchored.
local function gridAnchor(state: State.State, grid: number): (number, number, number)
  local open = state.grids[grid]
  if open then
    return open.x, open.y, open.z
  end
  local object = Space.Object(state, grid) :: System.Object
  return object.x, object.y, object.z
end

-- Drop open-space grids that no ball is on.
local function pruneGrids(state: State.State)
  if #state.gridIds == 0 then
    return
  end
  local used: { [number]: boolean } = {}
  for _, id in state.ballIds do
    used[state.balls[id].grid] = true
  end
  for _, id in state.wreckIds do
    used[state.wrecks[id].grid] = true
  end
  for i = #state.gridIds, 1, -1 do
    local id = state.gridIds[i]
    if not used[id] then
      state.grids[id] = nil
      table.remove(state.gridIds, i)
    end
  end
end

-- ---------------------------------------------------------------------
-- Ships entering and leaving space

local function addBall(state: State.State, ship: State.Ship, system: number, x: number, y: number, z: number): State.Ball
  -- What it flies like comes from its hull and its fit.
  local stats = Items.ShipStats(state, ship.id)
  local ball: State.Ball = {
    id = ship.id, kind = "ship", name = ship.name, system = system, grid = 0,
    x = x, y = y, z = z, vx = 0, vy = 0, vz = 0, tvx = 0, tvy = 0, tvz = 0,
    radius = stats.radius, maxVelocity = stats.maxVelocity, tau = stats.tau, warpSpeed = stats.warpSpeed,
    mode = "stop", target = 0, range = 0, dx = 0, dy = 0, dz = 0,
    vitals = Vitals.New(state, ship),
  }
  state.balls[ball.id] = ball
  -- Ships are made and launched in any order, so keep the list sorted.
  local at = #state.ballIds + 1
  while at > 1 and state.ballIds[at - 1] > ball.id do
    at -= 1
  end
  table.insert(state.ballIds, at, ball.id)
  Space.AssignGrid(state, ball)
  return ball
end

local function removeBall(state: State.State, ball: State.Ball)
  state.balls[ball.id] = nil
  State.RemoveId(state.ballIds, ball.id)
end

Space.RemoveBall = removeBall

-- Put a ship into space at a point, at rest (an NPC arriving, a test).
function Space.Launch(state: State.State, ship: State.Ship, system: number, x: number, y: number, z: number): State.Ball
  ship.docked = 0
  return addBall(state, ship, system, x, y, z)
end

local function unit(x: number, y: number, z: number): (number, number, number, number)
  local length = math.sqrt(x * x + y * y + z * z)
  if length == 0 then
    return 1, 0, 0, 0
  end
  return x / length, y / length, z / length, length
end

local function setMode(ball: State.Ball, mode: State.Mode, target: number, range: number)
  ball.mode = mode
  ball.target = target
  ball.range = range
  ball.dx, ball.dy, ball.dz = 0, 0, 0
end

local function undock(state: State.State, ship: State.Ship, events: { Event })
  local station = Space.Object(state, ship.docked) :: System.Object
  -- (a colony ship lies by a gate, or in a system with none by nothing)
  local host = Space.Object(state, station.parent)
  -- Leave on the side facing away from the body the station sits by.
  local ux, uy, uz = 1, 0, 0
  if host then
    ux, uy, uz = unit(station.x - host.x, station.y - host.y, station.z - host.z)
  end
  local hull = Ships.byId[ship.type]
  local out = station.radius + Constants.UNDOCK_DISTANCE + hull.radius
  local system = Space.SystemOf(state, station.id)
  ship.docked = 0
  local ball = addBall(state, ship, system, station.x + ux * out, station.y + uy * out, station.z + uz * out)
  -- Ships leave a station at full speed and keep going until told otherwise.
  ball.vx, ball.vy, ball.vz = ux * ball.maxVelocity, uy * ball.maxVelocity, uz * ball.maxVelocity
  setMode(ball, "goto", 0, 0)
  ball.dx, ball.dy, ball.dz = ux, uy, uz
  table.insert(events, { kind = "Undocked", ship = ship.id, station = station.id })
  table.insert(events, { kind = "BallAdded", ball = ball.id })
end

local function dock(state: State.State, ball: State.Ball, station: number, events: { Event })
  Vitals.Store(state.ships[ball.id], ball)
  removeBall(state, ball)
  state.ships[ball.id].docked = station
  table.insert(events, { kind = "BallRemoved", ball = ball.id, reason = "docked" })
  table.insert(events, { kind = "Docked", ship = ball.id, station = station })
end

local beginWarp: (ball: State.Ball, target: Body, range: number) -> ()

local function jump(state: State.State, ball: State.Ball, gate: System.Object, events: { Event })
  -- A gate that leads to a place and not to a system (a room of a camp:
  -- Tactical/Assault) sends the ship on to that place, in warp, and the
  -- place is on the charts from then on.
  if gate.variety == "passage" then
    local beyond = Space.Object(state, gate.to)
    local site = state.sites[gate.to]
    ball.intent = nil
    if beyond and site then
      site.strength = 1
      beginWarp(ball, beyond :: any, 0)
      table.insert(events, { kind = "PassageTaken", ship = ball.id, gate = gate.id, site = gate.to, name = beyond.name })
    end
    return
  end
  local from = ball.system
  local arrival = System.GateTo(Space.Describe(state, gate.to), from) :: System.Object
  -- A point a fixed distance from the far gate, in a direction rolled for
  -- this jump.
  local rng = Rng.For(state.historySeed, state.tick, ball.id, 31)
  local ux, uy, uz = unit(Rng.Float(rng, -1, 1), Rng.Float(rng, -0.3, 0.3), Rng.Float(rng, -1, 1))
  local out = arrival.radius + Constants.JUMP_ARRIVAL_DISTANCE + ball.radius
  ball.system = gate.to
  ball.x, ball.y, ball.z = arrival.x + ux * out, arrival.y + uy * out, arrival.z + uz * out
  ball.vx, ball.vy, ball.vz = 0, 0, 0
  setMode(ball, "stop", 0, 0)
  ball.warp = nil
  ball.intent = nil
  Space.AssignGrid(state, ball)
  table.insert(events, { kind = "Jumped", ship = ball.id, from = from, to = gate.to, gate = gate.id, arrival = arrival.id })
end

-- ---------------------------------------------------------------------
-- Warp

-- The point a ship arrives at when it warps to 'target' at 'range': on
-- the line from the target back toward the ship, 'range' off its surface.
local function warpPoint(ball: State.Ball, target: Body, range: number): (number, number, number, number)
  local ux, uy, uz = unit(ball.x - target.x, ball.y - target.y, ball.z - target.z)
  local out = target.radius + range + ball.radius
  local x, y, z = target.x + ux * out, target.y + uy * out, target.z + uz * out
  return x, y, z, math.sqrt((x - ball.x) ^ 2 + (y - ball.y) ^ 2 + (z - ball.z) ^ 2)
end

function beginWarp(ball: State.Ball, target: Body, range: number)
  local x, y, z = warpPoint(ball, target, range)
  setMode(ball, "align", 0, 0)
  ball.dx, ball.dy, ball.dz = unit(x - ball.x, y - ball.y, z - ball.z)
  ball.warp = {
    stage = "align", target = target.id, tx = x, ty = y, tz = z,
    startTick = 0, fx = 0, fy = 0, fz = 0, ux = 0, uy = 0, uz = 0,
  }
end

-- ---------------------------------------------------------------------
-- Commands

-- Whether 'command' can be carried out now; if not, why not.
function Space.Validate(state: State.State, command: State.Command): (boolean, string?)
  local ship = state.ships[command.actor]
  if ship == nil then
    return false, "no such ship"
  end
  local kind = command.kind
  if kind == "Undock" then
    if ship.docked == 0 then
      return false, "not docked"
    end
    -- (out of a colony ship that is in warp there is no going: it is
    -- between two places)
    local fleet = Nomads.FleetOf(state.galaxy, ship.docked)
    local carrier = if fleet then Nomads.Ball(state, fleet) else nil
    if carrier and carrier.warp and carrier.warp.stage == "warp" then
      return false, "the colony ship is in warp"
    end
    return true
  elseif kind == "ForgetBookmark" then
    return state.bookmarks[command.target or 0] ~= nil, "no such place is marked"
  elseif kind == "RenameBookmark" then
    if state.bookmarks[command.target or 0] == nil then
      return false, "no such place is marked"
    end
    local name, why = Space.PlaceName(command.what or "")
    return name ~= nil, why
  end
  local ball = state.balls[ship.id]
  if ball == nil then
    return false, "docked"
  end
  if ball.warp and ball.warp.stage == "warp" then
    return false, "in warp"
  end
  if kind == "Stop" then
    return true
  elseif kind == "Bookmark" then
    if ship.id ~= state.player.ship then
      return false, "no such ship"
    elseif #state.bookmarkIds >= Space.BOOKMARKS then
      return false, `{Space.BOOKMARKS} places are marked already: forget one first`
    end
    return true
  elseif kind == "Goto" then
    local x, y, z = command.x or 0, command.y or 0, command.z or 0
    if x == 0 and y == 0 and z == 0 then
      return false, "no direction"
    end
    return true
  elseif kind == "Approach" or kind == "Orbit" or kind == "KeepAtRange" or kind == "AlignTo"
    or kind == "WarpTo" or kind == "Dock" or kind == "Jump" then
    local target = Space.Body(state, command.target or 0)
    -- (a marked place can be warped to and aligned to, and nothing else)
    if target == nil and (kind == "WarpTo" or kind == "AlignTo") then
      target = Space.Marked(state, command.target or 0)
    end
    if target == nil or target.id == ball.id then
      return false, "no such target"
    end
    -- (a colony ship of the nomads is a ship and a station: to dock at
    -- the ship is to dock at the station it is)
    if kind == "Dock" then
      local berth = Nomads.Berth(state, target.id)
      if berth then
        target = Space.Object(state, berth) :: any
      end
      local fleet = Nomads.FleetOf(state.galaxy, (target :: Body).id)
      if fleet and Nomads.Gone(state, fleet) then
        return false, "that colony ship is gone"
      end
    end
    target = target :: Body
    if Space.SystemOf(state, target.id) ~= ball.system then
      return false, "target is in another system"
    end
    if (command.range or 0) < 0 then
      return false, "range cannot be negative"
    end
    local what: string = target.kind
    if kind == "Dock" then
      if what ~= "station" then
        return false, "not a station"
      end
    elseif kind == "Jump" then
      if what ~= "gate" then
        return false, "not a stargate"
      end
    elseif kind == "WarpTo" then
      local _, _, _, distance = warpPoint(ball, target, command.range or 0)
      if distance < Constants.WARP_MIN_DISTANCE then
        return false, "too close to warp"
      elseif ball.vitals.scrambled then
        return false, "warp scrambled"
      end
    end
    return true
  end
  return false, `unknown command '{kind}'`
end

-- Carry out a command that Validate accepted.
function Space.Apply(state: State.State, command: State.Command, events: { Event })
  local ship = state.ships[command.actor]
  local kind = command.kind
  if kind == "Undock" then
    undock(state, ship, events)
    return
  elseif kind == "ForgetBookmark" then
    local id = command.target :: number
    state.bookmarks[id] = nil
    State.RemoveId(state.bookmarkIds, id)
    table.insert(events, { kind = "BookmarkForgotten", bookmark = id })
    return
  elseif kind == "RenameBookmark" then
    local mark = state.bookmarks[command.target :: number]
    mark.name = Space.PlaceName(command.what :: string) :: string
    table.insert(events, { kind = "BookmarkRenamed", bookmark = mark.id, name = mark.name })
    return
  elseif kind == "Bookmark" then
    -- Where the ship is now, by a name given or made up ("Merear spot 3").
    local here = state.balls[ship.id]
    local name: string = command.what or ""
    if name == "" then
      local count = 1
      for _, id in state.bookmarkIds do
        count += if state.bookmarks[id].system == here.system then 1 else 0
      end
      name = `{state.galaxy.systems[here.system].name} spot {count}`
    end
    local mark: State.Bookmark = { id = State.NewId(state), name = name, system = here.system, x = here.x, y = here.y, z = here.z }
    state.bookmarks[mark.id] = mark
    table.insert(state.bookmarkIds, mark.id)
    table.insert(events, { kind = "Bookmarked", bookmark = mark.id, name = mark.name })
    return
  end
  local ball = state.balls[ship.id]
  -- A new order replaces whatever the ship was doing or meant to do.
  ball.warp = nil
  ball.intent = nil
  local range = command.range or 0
  if kind == "Stop" then
    setMode(ball, "stop", 0, 0)
    return
  elseif kind == "Goto" then
    setMode(ball, "goto", 0, 0)
    ball.dx, ball.dy, ball.dz = unit(command.x or 0, command.y or 0, command.z or 0)
    return
  end
  local target = (Space.Body(state, command.target :: number) or Space.Marked(state, command.target :: number)) :: Body
  -- (docking at a colony ship is docking at the station it is: Validate)
  if kind == "Dock" then
    local berth = Nomads.Berth(state, target.id)
    if berth then
      target = Space.Object(state, berth) :: any
    end
  end
  if kind == "Approach" then
    setMode(ball, "approach", target.id, range)
  elseif kind == "KeepAtRange" then
    setMode(ball, "keep", target.id, range)
  elseif kind == "Orbit" then
    setMode(ball, "orbit", target.id, range)
    -- The orbit's plane: it contains the line to the target and is as
    -- level as that allows.
    local ux, uy, uz = unit(ball.x - target.x, ball.y - target.y, ball.z - target.z)
    local nx, ny, nz
    if math.abs(uy) < 0.99 then
      -- normal = u x (up x u), which reduces to up minus its part along u
      nx, ny, nz = unit(-uy * ux, 1 - uy * uy, -uy * uz)
    else
      nx, ny, nz = unit(1 - ux * ux, -ux * uy, -ux * uz)
    end
    ball.dx, ball.dy, ball.dz = nx, ny, nz
  elseif kind == "AlignTo" then
    setMode(ball, "align", 0, 0)
    ball.dx, ball.dy, ball.dz = unit(target.x - ball.x, target.y - ball.y, target.z - ball.z)
  elseif kind == "WarpTo" then
    beginWarp(ball, target, range)
  elseif kind == "Dock" or kind == "Jump" then
    ball.intent = { kind = if kind == "Dock" then "dock" else "jump", target = target.id }
    local _, _, _, distance = warpPoint(ball, target, 0)
    -- (a ship held out of warp sets off the slow way)
    if distance >= Constants.WARP_MIN_DISTANCE and not ball.vitals.scrambled then
      beginWarp(ball, target, 0)
    else
      setMode(ball, "approach", target.id, 0)
    end
  end
end

-- ---------------------------------------------------------------------
-- The tick

-- The velocity a ball is trying to reach, from its mode.
local function targetVelocity(state: State.State, ball: State.Ball): (number, number, number)
  local mode = ball.mode
  local top = ball.maxVelocity
  if mode == "goto" or mode == "align" then
    return ball.dx * top, ball.dy * top, ball.dz * top
  elseif mode == "stop" then
    return 0, 0, 0
  end

  local target = Space.Body(state, ball.target)
  if target == nil or Space.SystemOf(state, target.id) ~= ball.system then
    setMode(ball, "stop", 0, 0)
    return 0, 0, 0
  end
  -- From the ball toward the target.
  local ux, uy, uz, distance = unit(target.x - ball.x, target.y - ball.y, target.z - ball.z)
  local excess = distance - target.radius - ball.radius - ball.range
  -- Closing speed proportional to what is left gives an approach with no
  -- overshoot; 1 / (4 tau) is the critically damped gain for a ship whose
  -- velocity lags its target by tau.
  local gain = 1 / (4 * ball.tau)

  if mode == "approach" then
    local speed = math.clamp(excess * gain, 0, top)
    return ux * speed, uy * speed, uz * speed
  elseif mode == "keep" then
    local slack = math.max(50, ball.range * 0.05)
    if math.abs(excess) <= slack then
      return 0, 0, 0
    end
    local speed = math.clamp(excess * gain, -top, top)
    return ux * speed, uy * speed, uz * speed
  end

  -- Orbit: fly along the circle, leaning in or out to hold the range.
  local nx, ny, nz = ball.dx, ball.dy, ball.dz
  local tx, ty, tz = unit(ny * uz - nz * uy, nz * ux - nx * uz, nx * uy - ny * ux)
  local lean = math.clamp(excess / math.max(1, 0.25 * (ball.range + target.radius)), -2, 2)
  local wx, wy, wz = unit(tx + ux * lean, ty + uy * lean, tz + uz * lean)
  return wx * top, wy * top, wz * top
end

local function stepWarp(state: State.State, ball: State.Ball, warp: State.Warp, events: { Event })
  local plan = warp.plan :: Motion.WarpPlan
  local elapsed = (state.tick - warp.startTick) * Constants.TICK
  if elapsed >= plan.total then
    ball.x, ball.y, ball.z = warp.tx, warp.ty, warp.tz
    ball.vx, ball.vy, ball.vz = warp.ux * plan.dropout, warp.uy * plan.dropout, warp.uz * plan.dropout
    ball.warp = nil
    setMode(ball, "stop", 0, 0)
    Space.AssignGrid(state, ball)
    table.insert(events, { kind = "WarpEnded", ball = ball.id, target = warp.target })
    return
  end
  local distance, speed = Motion.WarpAt(plan, elapsed)
  ball.x, ball.y, ball.z = warp.fx + warp.ux * distance, warp.fy + warp.uy * distance, warp.fz + warp.uz * distance
  ball.vx, ball.vy, ball.vz = warp.ux * speed, warp.uy * speed, warp.uz * speed
end

-- A tick has two halves, with the commands applied between them
-- (Core.Step):
--
--   Integrate  finish the second that just passed: every ship flies it
--              toward the target velocity it was given a tick ago.
--   Decide     act on where ships now are (dock, jump, enter warp) and
--              give each its target velocity for the second to come.
--
-- So a command takes effect at a tick boundary, and the state after a
-- tick fixes the next second of every ship's flight.

-- Fly every ship through the second that has just passed.
function Space.Integrate(state: State.State, events: { Event })
  local landed = false
  for _, id in state.ballIds do
    local ball = state.balls[id]
    local warp = ball.warp
    if warp and warp.stage == "warp" then
      stepWarp(state, ball, warp, events)
      landed = landed or ball.warp == nil
    else
      ball.x, ball.y, ball.z, ball.vx, ball.vy, ball.vz = Motion.Step(
        ball.x, ball.y, ball.z, ball.vx, ball.vy, ball.vz, ball.tvx, ball.tvy, ball.tvz, ball.tau, Constants.TICK)
    end
  end
  if landed then
    pruneGrids(state)
  end
end

-- Act on where ships are, and steer them for the coming second.
function Space.Decide(state: State.State, events: { Event })
  local regrid = false
  for _, id in table.clone(state.ballIds) do
    local ball = state.balls[id]
    local warp = ball.warp
    if warp and warp.stage == "warp" then
      continue
    end

    -- A ship that means to dock or jump does so once it is close enough,
    -- and otherwise makes sure it is on its way.
    local intent = ball.intent
    if intent then
      local target = Space.Object(state, intent.target) :: System.Object
      local limit = if intent.kind == "dock" then Constants.DOCK_RANGE else Constants.JUMP_RANGE
      -- (a colony ship that has gone on to its next system is not docked
      -- at from this one: the ship that meant to stops where it is)
      if Space.SystemOf(state, target.id) ~= ball.system then
        ball.intent = nil
        ball.warp = nil
        setMode(ball, "stop", 0, 0)
      elseif Space.Gap(ball :: any, target :: any) <= limit then
        if intent.kind == "dock" then
          dock(state, ball, target.id, events)
          regrid = true
          continue
        end
        jump(state, ball, target, events)
        regrid = true
      elseif warp == nil and (ball.mode ~= "approach" or ball.target ~= target.id) then
        setMode(ball, "approach", target.id, 0)
      end
    end

    if warp and ball.warp == warp then
      -- Aligning: enter warp once moving the right way fast enough.
      local speed = math.sqrt(ball.vx ^ 2 + ball.vy ^ 2 + ball.vz ^ 2)
      local along = ball.vx * ball.dx + ball.vy * ball.dy + ball.vz * ball.dz
      if speed >= Constants.WARP_ALIGN_SPEED * ball.maxVelocity and along >= Constants.WARP_ALIGN_COS * speed then
        local ux, uy, uz, distance = unit(warp.tx - ball.x, warp.ty - ball.y, warp.tz - ball.z)
        warp.stage = "warp"
        warp.startTick = state.tick
        warp.fx, warp.fy, warp.fz = ball.x, ball.y, ball.z
        warp.ux, warp.uy, warp.uz = ux, uy, uz
        warp.plan = Motion.PlanWarp(distance, ball.warpSpeed, ball.maxVelocity)
        ball.grid = 0
        ball.tvx, ball.tvy, ball.tvz = 0, 0, 0
        -- Locks and running modules do not survive entering warp (a
        -- cloak does: a ship can warp unseen).
        ball.vitals.locks = {}
        if #ball.vitals.running > 0 then
          local kept: { State.Running } = {}
          for _, running in ball.vitals.running do
            local item = state.items[running.item]
            if item and Modules.byId[item.type].cloak then
              table.insert(kept, running)
            end
          end
          ball.vitals.running = kept
          Vitals.Refresh(state, ball)
        end
        regrid = true
        table.insert(events, { kind = "WarpStarted", ball = ball.id, target = warp.target,
          duration = (warp.plan :: Motion.WarpPlan).total })
        continue
      end
    elseif ball.grid ~= 0 then
      -- Flown off the edge of its grid?
      local gx, gy, gz = gridAnchor(state, ball.grid)
      if (ball.x - gx) ^ 2 + (ball.y - gy) ^ 2 + (ball.z - gz) ^ 2 > Constants.GRID_RADIUS ^ 2 then
        Space.AssignGrid(state, ball)
        regrid = true
      end
    end

    ball.tvx, ball.tvy, ball.tvz = targetVelocity(state, ball)
  end
  if regrid then
    pruneGrids(state)
  end
end

-- ---------------------------------------------------------------------
-- Making ships

-- A new ship docked at 'station'.
function Space.NewShip(state: State.State, type: string, name: string, owner: string, station: number): State.Ship
  assert(Ships.byId[type], `no ship type '{type}'`)
  local ship: State.Ship = { id = State.NewId(state), type = type, name = name, owner = owner, docked = station,
    armorDamage = 0, hullDamage = 0, pilot = 0 }
  state.ships[ship.id] = ship
  table.insert(state.shipIds, ship.id)
  return ship
end

return Space
