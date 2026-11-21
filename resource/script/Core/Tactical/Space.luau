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

local CitadelDoors = require("@lt/Core/Data/CitadelDoors")
local CitadelSites = require("@lt/Core/Describe/CitadelSites")
local Constants = require("@lt/Core/Data/Constants")
local Factions = require("@lt/Core/Data/Factions")
local Items = require("@lt/Core/Assets/Items")
local Motion = require("@lt/Core/Tactical/Motion")
local Nomads = require("@lt/Core/Tactical/Nomads")
local Rng = require("@lt/Core/Kernel/Rng")
local Modules = require("@lt/Core/Data/Modules")
local Ships = require("@lt/Core/Data/Ships")
local Sides = require("@lt/Core/Tactical/Sides")
local Skills = require("@lt/Core/Data/Skills")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local System = require("@lt/Core/Describe/System")
local Vitals = require("@lt/Core/Tactical/Vitals")
local Wormholes = require("@lt/Core/Tactical/Wormholes")

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

-- A faction's citadel's key (State.Citadel): its system's, and its place
-- among that system's.
local CITADEL_KEY = 100
function Space.CitadelKey(system: number, slot: number): number
  return system * CITADEL_KEY + slot
end

-- The factions' citadels of a system nobody has described, as a glance
-- at it has them (Space.Glance): worked out, not kept in the state.
local passing: { [any]: { [number]: { State.Citadel } } } = setmetatable({} :: any, { __mode = "k" })

-- A system's citadels: those put down in the state, or, for one not
-- described yet, those it would have now (put down in the state with
-- 'keep', the first time it is described).
local function citadelRecords(state: State.State, description: System.Description, keep: boolean): { State.Citadel }
  local system = description.id
  local records: { State.Citadel } = {}
  if state.citadelsSeen and state.citadelsSeen[system] then
    local slot = 1
    local record = state.citadels[Space.CitadelKey(system, slot)]
    while record do
      table.insert(records, record)
      slot += 1
      record = state.citadels[Space.CitadelKey(system, slot)]
    end
    return records
  end
  local owner = state.galaxy.systems[system].owner
  for slot, site in CitadelSites.Of(state.galaxy, description) do
    table.insert(records, { system = system, slot = slot, tower = site.tower, owner = if site.fallen then "" else owner,
      fallen = site.fallen, body = site.body.id, station = 0, wreck = 0 })
  end
  if keep then
    local seenAll: { [number]: boolean } = state.citadelsSeen or {}
    state.citadelsSeen = seenAll
    seenAll[system] = true
    for _, record in records do
      local key = Space.CitadelKey(system, record.slot)
      state.citadels[key] = record
      State.InsertId(state.citadelIds, key)
    end
  else
    local seen = passing[state.galaxy]
    if seen == nil then
      seen = {}
      passing[state.galaxy] = seen
    end
    seen[system] = records
  end
  return records
end

-- The factions' citadels in a system's description (Assets/Citadels;
-- where, Describe/CitadelSites), as that is made: at the end of what
-- follows from the galaxy, so nothing else of it moves. The first time
-- a system is described ('keep'), they are put down in the state; a
-- glance at it from afar works them out and keeps nothing. Standing,
-- each is a station by a moon or a planet of the system, the citadel's
-- field across; fallen, its hulk's place (the hulk itself is put there
-- when the pilot comes: Assets/Citadels' Settle).
function Space.CitadelObjects(state: State.State, description: System.Description, keep: boolean?): { System.Object }
  local out: { System.Object } = {}
  if state.citadels == nil then
    return out
  end
  local system = description.id
  for _, record in citadelRecords(state, description, keep ~= false) do
    local tower = Structures.towerById[record.tower]
    local body = description.objects[record.body % SPAN]
    if tower and body and #description.objects + #out + 1 < SPAN then
      local rng = Rng.For(state.galaxy.seed, system, 7003, record.slot)
      local angle = Rng.Float(rng, 0, 2 * math.pi)
      local reach = tower.reach or 5000
      local off = body.radius * 1.5 + reach * 2 + 4000
      local id = system * SPAN + #description.objects + #out + 1
      local object: System.Object = {
        id = id, kind = "station", name = `{body.name} - {tower.name}`, x = body.x + math.cos(angle) * off, y = body.y + reach * 0.2,
        z = body.z + math.sin(angle) * off, radius = tower.field, seed = Rng.Int(rng, 100000), parent = body.id, site = id,
        variety = "citadel", to = 0,
      }
      -- (one that has fallen is its hulk's place: as Assets/Hulks' Stand has it)
      if record.fallen then
        object.kind, object.variety, object.radius, object.name = "belt", "hulk", reach, `{body.name} - {tower.name} Hulk`
      end
      record.station = id
      table.insert(out, object)
    end
  end
  return out
end

-- The description of a system, made (and kept in the state) on first use.
function Space.Describe(state: State.State, system: number): System.Description
  local description = state.systems[system]
  if description == nil then
    description = System.Describe(state.galaxy, system)
    for _, citadel in Space.CitadelObjects(state, description) do
      table.insert(description.objects, citadel)
    end
    state.systems[system] = description
  end
  return description
end

-- The faction's citadel a station is (Assets/Citadels), if it is one
-- that stands. Nil for anything else, a pilot's citadel among them.
function Space.FactionCitadel(state: State.State, id: number): State.Citadel?
  if state.citadels == nil or id <= 0 or id >= Constants.FIRST_DYNAMIC_ID then
    return nil
  end
  local system = id // SPAN
  if state.galaxy.systems[system] == nil then
    return nil
  end
  -- (a system not yet described: those a glance at it has)
  if not (state.citadelsSeen and state.citadelsSeen[system]) then
    Space.Glance(state, system)
    local seen = passing[state.galaxy]
    local glanced: { State.Citadel } = if seen and seen[system] then seen[system] else {}
    for _, record in glanced do
      if record.station == id then
        return if record.fallen then nil else record
      end
    end
    return nil
  end
  local slot = 1
  local record = state.citadels[Space.CitadelKey(system, slot)]
  while record do
    if record.station == id then
      return if record.fallen then nil else record
    end
    slot += 1
    record = state.citadels[Space.CitadelKey(system, slot)]
  end
  return nil
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
    -- (and the factions' citadels there, as Space.Describe has them: not
    -- put down in the state by a glance)
    for _, citadel in Space.CitadelObjects(state, description, false) do
      table.insert(description.objects, citadel)
    end
    seen[system] = description
  end
  return description
end

-- Forget what a glance at a system saw (what is there has changed: a
-- faction's citadel has fallen, Assets/Citadels).
function Space.Forget(state: State.State, system: number)
  local seen = glances[state.galaxy]
  if seen then
    seen[system] = nil
  end
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
  -- (the mark of a place is the place, as big as it is: a warp to it
  -- ends where a warp to the place would. Where the place is gone (a
  -- wormhole closed), the mark is where it was.)
  local object = if mark.object then Space.Object(state, mark.object) else nil
  if object then
    return { id = mark.id, kind = "bookmark", name = mark.name, x = object.x, y = object.y, z = object.z, radius = object.radius }
  end
  return { id = mark.id, kind = "bookmark", name = mark.name, x = mark.x, y = mark.y, z = mark.z, radius = 0 }
end

-- The marks a pilot has of a place (by the place's id).
function Space.MarkOf(state: State.State, object: number): State.Bookmark?
  for _, id in state.bookmarkIds do
    local mark = state.bookmarks[id]
    if mark.object == object then
      return mark
    end
  end
  return nil
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

-- How far outside a citadel's hangar door an undocking ship is first
-- seen, beyond its own size, m (mine).
Space.DOOR_CLEAR = 40

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
  -- (a citadel's guests come out just past the citadel itself, inside
  -- its field, and wait there tethered: Assets/Starbases. Out of any
  -- other station, beyond its field.)
  local starbase = state.starbases[station.id]
  -- (a faction's citadel is left as a pilot's is: Assets/Citadels)
  local theirs = if starbase == nil then Space.FactionCitadel(state, station.id) else nil
  local tower = if starbase then Structures.towerById[starbase.tower] elseif theirs then Structures.towerById[theirs.tower] else nil
  local citadel = tower ~= nil and tower.citadel == true and tower.reach ~= nil
  local out = (if citadel and tower then tower.reach :: number else station.radius) + Constants.UNDOCK_DISTANCE + hull.radius
  local system = Space.SystemOf(state, station.id)
  ship.docked = 0
  local x, y, z = station.x + ux * out, station.y + uy * out, station.z + uz * out
  -- (out of a citadel, by one of its hangar doors, as its design has them
  -- (Data/CitadelDoors: the owner, 2026-11-17, "ships undocking exit
  -- through one of the hangar doors"): just outside it, coasting out the
  -- way it faces, which door by the ship. Where its design has none, past
  -- the citadel as before.)
  -- (an alien people's citadel by its own design's: "vail.shipyard")
  local design = if tower and tower.kind and tower.faction ~= "" then `{tower.faction}.{tower.kind}` elseif tower then tower.kind else nil
  local doors = if citadel and tower and design then (CitadelDoors[design] or {})[tower.size] else nil
  local door = if doors and #doors > 0 then doors[ship.id % #doors + 1] else nil
  if door and tower then
    local reach = tower.reach :: number
    local clear = hull.radius * 1.2 + Space.DOOR_CLEAR
    x = station.x + door[1] * reach + door[4] * clear
    y = station.y + door[2] * reach + door[5] * clear
    z = station.z + door[3] * reach + door[6] * clear
    ux, uy, uz = door[4], door[5], door[6]
  end
  local ball = addBall(state, ship, system, x, y, z)
  if citadel then
    setMode(ball, "stop", 0, 0)
    if door then
      ball.vx, ball.vy, ball.vz = ux * ball.maxVelocity * 0.5, uy * ball.maxVelocity * 0.5, uz * ball.maxVelocity * 0.5
    end
  else
    -- Ships leave a station at full speed and keep going until told otherwise.
    ball.vx, ball.vy, ball.vz = ux * ball.maxVelocity, uy * ball.maxVelocity, uz * ball.maxVelocity
    setMode(ball, "goto", 0, 0)
  end
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

-- ---------------------------------------------------------------------
-- Through a stargate (State.Transit)

-- How long a passage's stages take (seconds): flying in from where it
-- jumps from; waiting beyond, at the least and at the most (the pilot's
-- view is let finish making the far side: the owner, 2026-11-21, "a
-- longer black tunnel on arrival, for loading, is fine"); and coming out.
Space.TRANSIT_IN = 6
Space.TUNNEL_LEAST = 2
Space.TUNNEL_MOST = 12
Space.TRANSIT_OUT = 5
-- How far out on the gate's axis the way in is drawn by (from its middle),
-- and how far beyond the far gate's opening a ship comes to a stop ("~5 km
-- past the gate, with a small spread", the owner), give or take.
Space.TRANSIT_LEAD = 2500
Space.EMERGE_STOP = 5000
Space.EMERGE_SPREAD = 500

-- The way a gate faces: out of its system, as it is drawn (Game/View/Scene).
function Space.GateAxis(gate: { x: number, z: number }): (number, number, number)
  local length = math.sqrt(gate.x ^ 2 + gate.z ^ 2)
  if length < 1 then
    return 0, 0, 1
  end
  return gate.x / length, 0, gate.z / length
end

-- Where a ship is 't' seconds into its passage's stage, and how fast it
-- is going.
function Space.TransitAt(transit: State.Transit, t: number): (number, number, number, number, number, number)
  local T = transit
  if T.stage == "in" then
    local tau = math.clamp(t / Space.TRANSIT_IN, 0, 1)
    -- (along a curve from where it was, by the point on the axis, to the
    -- gate's middle; and along that at a pace that begins as fast as it
    -- was going and ends at 'speed')
    local fax, fay, faz = T.ax - T.fx, T.ay - T.fy, T.az - T.fz
    local agx, agy, agz = T.gx - T.ax, T.gy - T.ay, T.gz - T.az
    local first, last = 2 * math.sqrt(fax ^ 2 + fay ^ 2 + faz ^ 2), 2 * math.sqrt(agx ^ 2 + agy ^ 2 + agz ^ 2)
    local k0 = if first > 1 then math.clamp(T.enter * Space.TRANSIT_IN / first, 0, 2) else 0
    local k1 = if last > 1 then math.min(T.speed * Space.TRANSIT_IN / last, math.sqrt(9 - k0 * k0)) else 0
    local t2, t3 = tau * tau, tau * tau * tau
    local u = (-2 * t3 + 3 * t2) + k0 * (t3 - 2 * t2 + tau) + k1 * (t3 - t2)
    local du = ((-6 * t2 + 6 * tau) + k0 * (3 * t2 - 4 * tau + 1) + k1 * (3 * t2 - 2 * tau)) / Space.TRANSIT_IN
    local a, b, c = (1 - u) ^ 2, 2 * (1 - u) * u, u * u
    local x = a * T.fx + b * T.ax + c * T.gx
    local y = a * T.fy + b * T.ay + c * T.gy
    local z = a * T.fz + b * T.az + c * T.gz
    -- (the curve's way at u: 2(1-u)(A-F) + 2u(G-A))
    local dx, dy, dz = 2 * (1 - u) * fax + 2 * u * agx, 2 * (1 - u) * fay + 2 * u * agy, 2 * (1 - u) * faz + 2 * u * agz
    return x, y, z, dx * du, dy * du, dz * du
  elseif T.stage == "out" then
    local tau = math.clamp(t / Space.TRANSIT_OUT, 0, 1)
    local d = T.reach * (1 - (1 - tau) ^ 3)
    local speed = T.reach * 3 * (1 - tau) ^ 2 / Space.TRANSIT_OUT
    return T.ox + T.ux * d, T.oy + T.uy * d, T.oz + T.uz * d, T.ux * speed, T.uy * speed, T.uz * speed
  end
  -- (waiting beyond: still, facing the way it will come out)
  return T.ox, T.oy, T.oz, T.ux * 0.01, T.uy * 0.01, T.uz * 0.01
end

-- Whether a ship is going through a stargate, and so nobody's to touch.
function Space.InTransit(state: State.State, id: number): boolean
  local ball = state.balls[id]
  return ball ~= nil and ball.transit ~= nil
end

-- Its locks are let go and what runs on it stops, as on entering warp (a
-- cloak runs on).
local function standDown(state: State.State, ball: State.Ball)
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
end

-- A passage's far side: out through the gate 'far', into its system, a
-- little aside of straight in, rolled for this passage; from behind the
-- gate, to stop a little way on. (Its way in is the caller's to fill.)
local function farSide(state: State.State, ball: State.Ball, far: System.Object): State.Transit
  local rng = Rng.For(state.historySeed, state.tick, ball.id, 31)
  local wx, wy, wz = Space.GateAxis(far)
  wx, wy, wz = -wx, -wy, -wz
  -- (two ways square to it, and a little of each)
  local px, py, pz = unit(-wz, 0, wx)
  local qx, qy, qz = py * wz - pz * wy, pz * wx - px * wz, px * wy - py * wx
  local r1, r2 = Rng.Float(rng, -0.12, 0.12), Rng.Float(rng, -0.08, 0.08)
  local ux, uy, uz = unit(wx + px * r1 + qx * r2, wy + py * r1 + qy * r2, wz + pz * r1 + qz * r2)
  local back = far.radius
  return {
    stage = "out", startTick = state.tick, gate = 0, arrival = far.id, from = ball.system, to = ball.system,
    fx = 0, fy = 0, fz = 0, ax = 0, ay = 0, az = 0, gx = 0, gy = 0, gz = 0, enter = 0, speed = 0,
    ox = far.x - ux * back, oy = far.y - uy * back, oz = far.z - uz * back, ux = ux, uy = uy, uz = uz,
    reach = back + Space.EMERGE_STOP + Rng.Float(rng, -Space.EMERGE_SPREAD, Space.EMERGE_SPREAD),
  }
end

-- A ship just come into a system by a stargate from beyond it (the
-- system's own traffic, Tactical/Traffic): it comes out of the gate, as
-- one that went through it would.
function Space.ComeThrough(state: State.State, ball: State.Ball, gate: System.Object, events: { Event })
  local transit = farSide(state, ball, gate)
  ball.transit = transit
  ball.x, ball.y, ball.z = transit.ox, transit.oy, transit.oz
  ball.vx, ball.vy, ball.vz = 0, 0, 0
  Space.AssignGrid(state, ball)
  table.insert(events, { kind = "JumpEmerged", ship = ball.id, gate = gate.id, seconds = Space.TRANSIT_OUT })
end

-- A ship close enough to a stargate to jump begins its passage: it flies
-- in along the gate's axis, from the side it is on.
local function beginTransit(state: State.State, ball: State.Ball, gate: System.Object, far: System.Object?, events: { Event })
  local nx, ny, nz = Space.GateAxis(gate)
  local side = if (ball.x - gate.x) * nx + (ball.y - gate.y) * ny + (ball.z - gate.z) * nz < 0 then -1 else 1
  local lead = Space.TRANSIT_LEAD
  local ax, ay, az = gate.x + nx * side * lead, gate.y + ny * side * lead, gate.z + nz * side * lead
  -- (how fast it was coming at the gate, and how fast it goes through:
  -- twice and a bit the pace of the whole way in)
  local length = math.sqrt((ax - ball.x) ^ 2 + (ay - ball.y) ^ 2 + (az - ball.z) ^ 2) + lead
  local ux, uy, uz = unit(gate.x - ball.x, gate.y - ball.y, gate.z - ball.z)
  local enter = math.max(0, ball.vx * ux + ball.vy * uy + ball.vz * uz)
  -- (with no far side, it goes in and is gone: Space.EnterGate)
  local transit: State.Transit = if far then farSide(state, ball, far) else {
    stage = "in", startTick = state.tick, gate = 0, arrival = 0, from = ball.system, to = 0,
    fx = 0, fy = 0, fz = 0, ax = 0, ay = 0, az = 0, gx = 0, gy = 0, gz = 0, enter = 0, speed = 0,
    ox = gate.x, oy = gate.y, oz = gate.z, ux = 0, uy = 0, uz = 1, reach = 0, ready = true,
  }
  transit.stage, transit.gate, transit.to = "in", gate.id, if far then gate.to else 0
  transit.fx, transit.fy, transit.fz = ball.x, ball.y, ball.z
  transit.ax, transit.ay, transit.az = ax, ay, az
  transit.gx, transit.gy, transit.gz = gate.x, gate.y, gate.z
  transit.enter, transit.speed = enter, 2.2 * length / Space.TRANSIT_IN
  ball.transit = transit
  ball.warp = nil
  ball.intent = nil
  setMode(ball, "stop", 0, 0)
  ball.tvx, ball.tvy, ball.tvz = 0, 0, 0
  standDown(state, ball)
  table.insert(events, { kind = "JumpBegan", ship = ball.id, gate = gate.id, to = gate.to, seconds = Space.TRANSIT_IN })
end

-- Through the gate's middle: into the system beyond, to wait behind the
-- far gate. (On the far gate's grid already, so that the pilot's view
-- makes what is there while the screen is black.)
local function crossTransit(state: State.State, ball: State.Ball, transit: State.Transit, events: { Event })
  local from = ball.system
  transit.stage = "tunnel"
  transit.startTick = state.tick
  -- (another's ship has nothing to wait for)
  transit.ready = transit.ready or state.ships[ball.id] == nil or ball.id ~= state.player.ship
  ball.system = transit.to
  ball.x, ball.y, ball.z = transit.ox, transit.oy, transit.oz
  ball.vx, ball.vy, ball.vz = 0, 0, 0
  Space.AssignGrid(state, ball)
  table.insert(events, { kind = "Jumped", ship = ball.id, from = from, to = transit.to, gate = transit.gate, arrival = transit.arrival,
    wormhole = false })
end

-- Out of the far gate.
local function emerge(state: State.State, ball: State.Ball, transit: State.Transit, events: { Event })
  transit.stage = "out"
  transit.startTick = state.tick
  table.insert(events, { kind = "JumpEmerged", ship = ball.id, gate = transit.arrival, seconds = Space.TRANSIT_OUT })
end

-- A passage's stage moved on, at a tick: through, out, or done.
local function stepTransit(state: State.State, ball: State.Ball, transit: State.Transit, events: { Event })
  local elapsed = (state.tick - transit.startTick) * Constants.TICK
  if transit.stage == "in" and elapsed >= Space.TRANSIT_IN then
    if transit.to == 0 then
      -- (gone in, and nowhere: the system's own traffic, whose way on is
      -- nobody's business: Tactical/Traffic takes it away)
      transit.stage, transit.startTick = "tunnel", state.tick
      ball.x, ball.y, ball.z, ball.vx, ball.vy, ball.vz = transit.gx, transit.gy, transit.gz, 0, 0, 0
      return
    end
    crossTransit(state, ball, transit, events)
    return
  elseif transit.stage == "tunnel" then
    if (transit.ready and elapsed >= Space.TUNNEL_LEAST) or elapsed >= Space.TUNNEL_MOST then
      emerge(state, ball, transit, events)
    end
    return
  elseif transit.stage == "out" and elapsed >= Space.TRANSIT_OUT then
    local x, y, z = Space.TransitAt(transit, Space.TRANSIT_OUT)
    ball.x, ball.y, ball.z = x, y, z
    ball.vx, ball.vy, ball.vz = 0, 0, 0
    ball.transit = nil
    setMode(ball, "stop", 0, 0)
    Space.AssignGrid(state, ball)
    table.insert(events, { kind = "JumpEnded", ship = ball.id, gate = transit.arrival })
    return
  end
  ball.x, ball.y, ball.z, ball.vx, ball.vy, ball.vz = Space.TransitAt(transit, elapsed)
end

-- A ship goes into a stargate it is close enough to and is gone (the
-- system's own traffic, leaving: Tactical/Traffic, which takes it away
-- once it is through). Nothing beyond the gate is looked at.
function Space.EnterGate(state: State.State, ball: State.Ball, gate: System.Object, events: { Event })
  beginTransit(state, ball, gate, nil, events)
end

-- The pilot's view has made the far side: its ship may come out (once
-- it has waited the least it must).
function Space.Ready(state: State.State, id: number)
  local ball = state.balls[id]
  local transit = if ball then ball.transit else nil
  if transit and transit.stage == "tunnel" then
    transit.ready = true
  end
end

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
  local to, far = gate.to, nil :: System.Object?
  if gate.kind == "wormhole" then
    -- A wormhole (Tactical/Wormholes) leads where it leads, and the ship
    -- comes out beside its far end: which is made now, if this is the
    -- first ship through. One that has closed on the way leads nowhere.
    local hole = Wormholes.At(state, gate.id)
    local site = state.sites[gate.id]
    far = if hole and site and not site.gone then Wormholes.Far(state, hole, gate.id) else nil
    if hole == nil or far == nil then
      ball.intent = nil
      table.insert(events, { kind = "JumpFailed", ship = ball.id, gate = gate.id, why = "that wormhole has closed" })
      return
    end
    to = Wormholes.Beyond(hole, gate.id)
  else
    far = System.GateTo(Space.Describe(state, to), from)
    -- A stargate: through it, a passage (State.Transit).
    if far then
      beginTransit(state, ball, gate, far, events)
      return
    end
  end
  local arrival = far :: System.Object
  -- A point a fixed distance from the far gate, in a direction rolled for
  -- this jump.
  local rng = Rng.For(state.historySeed, state.tick, ball.id, 31)
  local ux, uy, uz = unit(Rng.Float(rng, -1, 1), Rng.Float(rng, -0.3, 0.3), Rng.Float(rng, -1, 1))
  local out = arrival.radius + Constants.JUMP_ARRIVAL_DISTANCE + ball.radius
  ball.system = to
  ball.x, ball.y, ball.z = arrival.x + ux * out, arrival.y + uy * out, arrival.z + uz * out
  ball.vx, ball.vy, ball.vz = 0, 0, 0
  setMode(ball, "stop", 0, 0)
  ball.warp = nil
  ball.intent = nil
  Space.AssignGrid(state, ball)
  table.insert(events, { kind = "Jumped", ship = ball.id, from = from, to = to, gate = gate.id, arrival = arrival.id,
    wormhole = gate.kind == "wormhole" })
  -- (and its mass is spent on the wormhole, which may close behind it)
  if gate.kind == "wormhole" then
    local hole = Wormholes.At(state, gate.id)
    local record = state.ships[ball.id]
    if hole and record then
      Wormholes.Passed(state, hole, Ships.byId[record.type].mass, events)
    end
  end
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

-- A fleet's warp. The ship that calls one is turning for its warp
-- already (an ordinary order to warp: Tactical/Fleet gives it); this
-- says that so many others are to go with it. They join as they are
-- ready, each turning for a place of its own in a ring about where the
-- caller will arrive, and nobody goes until all of them are pointed the
-- right way and moving: then all go in the one tick, at the warp speed
-- of the slowest, and so arrive together. A fleet does not wait for
-- ever: after FLEET_WAIT the caller goes with whoever is ready, and
-- the rest come on by themselves. Called off (any other order to the
-- caller), those who had turned to go with it stop.
Space.FLEET_WAIT = math.ceil(60 / Constants.TICK)
-- How far out the ring is that a fleet arrives in, and how many places
-- it has before another, wider one begins.
Space.FLEET_RING, Space.FLEET_PLACES = 750, 6

-- A ship that is turning for its warp calls its fleet to go with it.
function Space.CallFleet(state: State.State, ball: State.Ball, expect: number)
  local warp = ball.warp
  if warp and warp.stage == "align" then
    warp.gang, warp.called, warp.expect = ball.id, state.tick, expect
  end
end

-- A ship joins the fleet warp another has called, in a place of the
-- ring ('place': 1 for the first to join, and on). False if there is
-- none to join, or the ship cannot warp there.
function Space.JoinWarp(state: State.State, ball: State.Ball, lead: State.Ball, place: number): boolean
  local going = lead.warp
  if going == nil or going.gang ~= lead.id or going.stage ~= "align" or ball.vitals.scrambled or ball.grid ~= lead.grid then
    return false
  end
  local body = Space.Body(state, going.target) or Space.Marked(state, going.target)
  if body == nil then
    return false
  end
  -- (the ring lies across the line from the body to where the caller arrives)
  local ux, uy, uz = unit(going.tx - body.x, going.ty - body.y, going.tz - body.z)
  if ux == 0 and uy == 0 and uz == 0 then
    ux = 1
  end
  local px, py, pz
  if math.abs(uy) < 0.99 then
    px, py, pz = unit(-uy * ux, 1 - uy * uy, -uy * uz)
  else
    px, py, pz = unit(1 - ux * ux, -ux * uy, -ux * uz)
  end
  local qx, qy, qz = uy * pz - uz * py, uz * px - ux * pz, ux * py - uy * px
  local ring = (place - 1) // Space.FLEET_PLACES
  local angle = 2 * math.pi * ((place - 1) % Space.FLEET_PLACES) / Space.FLEET_PLACES + ring * 0.5
  local out = Space.FLEET_RING * (1 + ring) + ball.radius + lead.radius
  local x = going.tx + out * (math.cos(angle) * px + math.sin(angle) * qx)
  local y = going.ty + out * (math.cos(angle) * py + math.sin(angle) * qy)
  local z = going.tz + out * (math.cos(angle) * pz + math.sin(angle) * qz)
  if (x - ball.x) ^ 2 + (y - ball.y) ^ 2 + (z - ball.z) ^ 2 < Constants.WARP_MIN_DISTANCE ^ 2 then
    return false
  end
  ball.intent = nil
  setMode(ball, "align", 0, 0)
  ball.dx, ball.dy, ball.dz = unit(x - ball.x, y - ball.y, z - ball.z)
  ball.warp = {
    stage = "align", target = going.target, tx = x, ty = y, tz = z,
    startTick = 0, fx = 0, fy = 0, fz = 0, ux = 0, uy = 0, uz = 0, gang = lead.id,
  }
  return true
end

-- Whether a ship turning for its warp is pointed the right way and
-- moving fast enough to go.
local function aligned(ball: State.Ball): boolean
  local speed = math.sqrt(ball.vx ^ 2 + ball.vy ^ 2 + ball.vz ^ 2)
  local along = ball.vx * ball.dx + ball.vy * ball.dy + ball.vz * ball.dz
  return speed >= Constants.WARP_ALIGN_SPEED * ball.maxVelocity and along >= Constants.WARP_ALIGN_COS * speed
end

-- The same of a ship and a place: whether it is pointed at that place
-- and moving fast enough, as it would have to be to warp there. (What
-- a gun fixed along a bow is fired by: Tactical/Combat.)
function Space.AlignedTo(ball: State.Ball, x: number, y: number, z: number): boolean
  local dx, dy, dz = unit(x - ball.x, y - ball.y, z - ball.z)
  local speed = math.sqrt(ball.vx ^ 2 + ball.vy ^ 2 + ball.vz ^ 2)
  local along = ball.vx * dx + ball.vy * dy + ball.vz * dz
  return speed >= Constants.WARP_ALIGN_SPEED * ball.maxVelocity and along >= Constants.WARP_ALIGN_COS * speed
end

-- How the fleet warps stand this tick, by the ship that called each:
-- whether it goes now, and the warp speed and the sublight speed of the
-- slowest of those who go (what all of them warp at). Those who had
-- turned to go with a fleet warp that has been called off stop; those
-- left behind by one that has gone are on their own.
type Gang = { go: boolean, warpSpeed: number, maxVelocity: number, ready: number }
local function gangs(state: State.State): { [number]: Gang }
  local found: { [number]: Gang } = {}
  for _, id in state.ballIds do
    local ball = state.balls[id]
    local warp = ball.warp
    if warp and warp.gang and warp.stage == "align" then
      local lead = state.balls[warp.gang]
      local theirs = if lead then lead.warp else nil
      if theirs == nil or theirs.gang ~= warp.gang or lead.grid ~= ball.grid then
        -- (called off, or the caller is gone)
        if ball.id ~= warp.gang then
          ball.warp = nil
          setMode(ball, "stop", 0, 0)
        else
          warp.gang, warp.called, warp.expect = nil, nil, nil
        end
      elseif theirs.stage == "warp" then
        -- (it went without this one)
        warp.gang = nil
      elseif aligned(ball) then
        local gang = found[warp.gang]
        if gang == nil then
          gang = { go = false, warpSpeed = math.huge, maxVelocity = math.huge, ready = 0 }
          found[warp.gang] = gang
        end
        gang.ready += 1
        gang.warpSpeed = math.min(gang.warpSpeed, ball.warpSpeed)
        gang.maxVelocity = math.min(gang.maxVelocity, ball.maxVelocity)
      end
    end
  end
  for id, gang in found do
    local lead = state.balls[id]
    local warp = lead.warp :: State.Warp
    -- (the caller itself has to be ready. then: everybody, or time is up)
    gang.go = aligned(lead) and (gang.ready >= 1 + (warp.expect or 0) or state.tick - (warp.called or 0) >= Space.FLEET_WAIT)
  end
  return found
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
    -- (not with a module fitted the pilot has not the skills for: a ship
    -- may come so, bought fitted out on a contract, Assets/Contracts;
    -- the owner, 2026-11-16: "buying a fitted ship from contracts, it should already be assembled with the modules fitted. You just shouldn't be able to undock with it if some of the modules you can't use")
    if ship.id == state.player.ship then
      for _, item in Items.Fitted(state, ship.id) do
        local missing = Skills.Missing(Skills.Needs(item.type), state.skills)
        if missing then
          return false, `{Skills.Describe(missing)} for the {Modules.byId[item.type].name} fitted`
        end
      end
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
  elseif kind == "Bookmark" then
    -- Where the ship is; or a place, by itself (one given, or the
    -- station the ship is docked at). Docked, or anywhere in space.
    if ship.id ~= state.player.ship then
      return false, "no such ship"
    elseif #state.bookmarkIds >= Space.BOOKMARKS then
      return false, `{Space.BOOKMARKS} places are marked already: forget one first`
    end
    local place = command.target or (if state.balls[ship.id] == nil then ship.docked else 0)
    if place ~= 0 then
      if Space.Object(state, place) == nil then
        return false, "only a place can be marked"
      elseif Space.MarkOf(state, place) then
        return false, "that place is marked already"
      end
    elseif state.balls[ship.id] == nil then
      return false, "docked"
    end
    if command.what and command.what ~= "" then
      local name, why = Space.PlaceName(command.what)
      return name ~= nil, why
    end
    return true
  end
  local ball = state.balls[ship.id]
  if ball == nil then
    return false, "docked"
  end
  if ball.transit then
    if kind == "Emerge" then
      return ball.transit.stage == "tunnel", "not between gates"
    end
    return false, "going through a stargate"
  elseif kind == "Emerge" then
    return false, "not between gates"
  end
  if ball.warp and ball.warp.stage == "warp" then
    return false, "in warp"
  end
  -- (rooted by a siege, triage or industrial core module: module expansion)
  if ball.vitals.rooted and (kind == "WarpTo" or kind == "Dock" or kind == "Jump") then
    return false, "rooted to the spot while its module runs"
  end
  if kind == "Stop" then
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
      -- (a side at war shuts its stations to one who has served its foe:
      -- the owner, 2026-11-16, "Stations shut"; Tactical/Sides)
      local whose = Sides.StationOf(state, target.id, ball.system)
      local foe = if ship.owner == "player" and whose ~= "" then Sides.EnemyOf(state, whose) else nil
      if foe then
        return false, `the {Factions.byId[whose].name} shut their stations to those on the {Factions.byId[foe].name}' books`
      end
    elseif kind == "Jump" then
      if what == "wormhole" then
        -- (through a wormhole: only one that is open, found, and big
        -- enough for the hull)
        local ok, why = Wormholes.Passable(state, target.id, ship)
        if not ok then
          return false, why
        end
      elseif what ~= "gate" then
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
  elseif kind == "Emerge" then
    Space.Ready(state, ship.id)
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
    -- A place by itself, named as it is; or where the ship is now, by a
    -- name given or made up ("Merear spot 3").
    local name: string = command.what or ""
    local place = command.target or (if state.balls[ship.id] == nil then ship.docked else 0)
    local mark: State.Bookmark
    if place ~= 0 then
      local object = Space.Object(state, place) :: System.Object
      mark = { id = State.NewId(state), name = if name ~= "" then name else object.name, system = Space.SystemOf(state, place),
        x = object.x, y = object.y, z = object.z, object = place, what = object.kind }
    else
      local here = state.balls[ship.id]
      if name == "" then
        local count = 1
        for _, id in state.bookmarkIds do
          count += if state.bookmarks[id].system == here.system then 1 else 0
        end
        name = `{state.galaxy.systems[here.system].name} spot {count}`
      end
      mark = { id = State.NewId(state), name = name, system = here.system, x = here.x, y = here.y, z = here.z }
    end
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
    -- (an approach to a station, right up to it, comes in to its tower:
    -- through its field, which keeps out whoever it keeps out, and
    -- inside which nothing outside can lock the ship or be locked from
    -- it. Tactical/Fields. Docking is done from the field's edge on the
    -- way, as it always was; and a colony ship is all hull.)
    if ball.range == 0 and target.kind == "station" and Nomads.FleetOf(state.galaxy, target.id) == nil then
      excess = distance - target.radius * Constants.TOWER_SHARE - ball.radius
    end
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
    local transit = ball.transit
    if transit then
      local stage = transit.stage
      stepTransit(state, ball, transit, events)
      landed = landed or ball.transit == nil or transit.stage ~= stage
    elseif warp and warp.stage == "warp" then
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
  local fleets = gangs(state)
  for _, id in table.clone(state.ballIds) do
    local ball = state.balls[id]
    local warp = ball.warp
    if warp and warp.stage == "warp" then
      continue
    end
    -- (going through a stargate: it goes where its passage takes it)
    if ball.transit then
      ball.tvx, ball.tvy, ball.tvz = ball.vx, ball.vy, ball.vz
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
      -- (one of a fleet's warp waits for the fleet, and goes at the
      -- speed of its slowest)
      local fleet = if warp.gang then fleets[warp.gang] else nil
      if aligned(ball) and (warp.gang == nil or (fleet ~= nil and fleet.go)) then
        local ux, uy, uz, distance = unit(warp.tx - ball.x, warp.ty - ball.y, warp.tz - ball.z)
        warp.stage = "warp"
        warp.startTick = state.tick
        warp.fx, warp.fy, warp.fz = ball.x, ball.y, ball.z
        warp.ux, warp.uy, warp.uz = ux, uy, uz
        warp.plan = Motion.PlanWarp(distance, if fleet then fleet.warpSpeed else ball.warpSpeed,
          if fleet then fleet.maxVelocity else ball.maxVelocity)
        ball.grid = 0
        ball.tvx, ball.tvy, ball.tvz = 0, 0, 0
        -- Locks and running modules do not survive entering warp (a
        -- cloak does: a ship can warp unseen).
        standDown(state, ball)
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
