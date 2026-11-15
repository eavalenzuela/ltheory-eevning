--!strict
-- The field round a station (Tactical/Fields): nothing is locked or
-- shot across it, whoever the station fires on is kept out of it, and
-- what goes for somebody inside it turns on what it can reach.

local Combat = require("@lt/Core/Tactical/Combat")
local Core = require("@lt/Core/Api")
local Fields = require("@lt/Core/Tactical/Fields")
local Items = require("@lt/Core/Assets/Items")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local System = require("@lt/Core/Describe/System")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Fields")

type Event = { [string]: any }

-- A game with the pilot's ship at rest outside the station they began
-- at. 'quiet': with every battery of that station down, so that what a
-- case puts there to be looked at is not shot to pieces meanwhile.
local function outside(quiet: boolean?): (Core.Game, State.Ball, System.Object)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  if quiet then
    for index = 1, 12 do
      table.insert(state.batteries.down, { station = state.player.home, index = index, back = state.tick + 1000000 })
    end
  end
  assert(Core.Submit(game, { kind = "Undock", actor = state.player.ship }))
  Core.Step(game)
  assert(Core.Submit(game, { kind = "Stop", actor = state.player.ship }))
  for _ = 1, 30 do
    Core.Step(game)
  end
  Core.TakeEvents(game)
  local me = state.balls[state.player.ship]
  local station = assert(Space.Object(state, state.player.home))
  assert(me.grid == station.id, "the pilot is not at the station they began at")
  return game, me, station
end

-- The way from a station's middle out through a ship.
local function outward(station: System.Object, ball: State.Ball): (number, number, number)
  local far = Space.Distance(station :: any, ball :: any)
  return (ball.x - station.x) / far, (ball.y - station.y) / far, (ball.z - station.z) / far
end

-- Put a ship at rest 'share' of a station's radius from its middle, on
-- the side the pilot left it by.
local function put(ball: State.Ball, station: System.Object, ux: number, uy: number, uz: number, share: number)
  local out = station.radius * share
  ball.x, ball.y, ball.z = station.x + ux * out, station.y + uy * out, station.z + uz * out
  ball.vx, ball.vy, ball.vz, ball.tvx, ball.tvy, ball.tvz = 0, 0, 0, 0, 0, 0
  ball.mode = "stop"
end

-- A ship of nobody's, at rest there.
local function drifter(state: State.State, system: number, x: number, y: number, z: number): State.Ball
  local ship = Space.NewShip(state, "frigate.courier", "Drifter", "civilian", 0)
  local ball = Space.Launch(state, ship, system, x, y, z)
  ball.mode = "stop"
  return ball
end

local function steps(game: Core.Game, count: number): { Event }
  local seen: { Event } = {}
  for _ = 1, count do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      table.insert(seen, event)
    end
  end
  return seen
end

local function has(events: { Event }, kind: string): Event?
  for _, event in events do
    if event.kind == kind then
      return event
    end
  end
  return nil
end

local function lock(game: Core.Game, actor: number, target: number): (boolean, string?)
  return Combat.Validate(game.state, { kind = "LockTarget", actor = actor, target = target })
end

suite:Case("nothing is locked across a station's field, in or out, and the station itself always is", function(t)
  local game, me, station = outside(true)
  local state = game.state
  local ux, uy, uz = outward(station, me)
  t.ok(Fields.Of(state, me.grid) == station, "the station a pilot begins at has no field")
  t.ok(not Fields.Within(station, me :: any), "a ship that has just left a station is outside its field")
  local out = drifter(state, me.system, me.x + ux * 2000, me.y + uy * 2000, me.z + uz * 2000)
  local inner = drifter(state, me.system, station.x + ux * station.radius * 0.5, station.y + uy * station.radius * 0.5,
    station.z + uz * station.radius * 0.5)
  t.ok(Fields.Within(station, inner :: any))

  -- From outside: what is outside, and the station, and not what is inside.
  t.ok((lock(game, me.id, out.id)))
  t.ok((lock(game, me.id, station.id)), "the tower can be locked from outside its field")
  t.eq({ lock(game, me.id, inner.id) } :: { any }, { false, Fields.REFUSED } :: { any })
  t.eq({ lock(game, inner.id, me.id) } :: { any }, { false, Fields.REFUSED } :: { any })
  t.ok(Core.Submit(game, { kind = "LockTarget", actor = me.id, target = out.id }))
  steps(game, 12)
  t.eq(#me.vitals.locks, 1)
  t.eq(Core.Query.Field(game), 0)

  -- The pilot goes in: the lock is lost, they are told where they are,
  -- and it is the other way about.
  put(me, station, ux, uy, uz, 0.4)
  local seen = steps(game, 2)
  local lost = has(seen, "LockLost")
  t.ok(lost ~= nil and lost.reason == Fields.REFUSED, "a lock across the field should be lost to it")
  t.eq(#me.vitals.locks, 0)
  t.ok(has(seen, "FieldEntered") ~= nil, "the pilot was not told they were inside")
  t.eq(Core.Query.Field(game), station.id)
  t.ok((lock(game, me.id, inner.id)), "two ships inside the same field can lock each other")
  t.eq({ lock(game, me.id, out.id) } :: { any }, { false, Fields.REFUSED } :: { any })
  t.eq({ lock(game, out.id, me.id) } :: { any }, { false, Fields.REFUSED } :: { any })

  -- And out again.
  put(me, station, ux, uy, uz, 1.3)
  seen = steps(game, 2)
  t.ok(has(seen, "FieldLeft") ~= nil)
  t.eq(Core.Query.Field(game), 0)
  t.ok((lock(game, me.id, out.id)))
end)

suite:Case("an approach to a station comes in to its tower, and whoever its guns fire on is kept out and put out", function(t)
  local game, me, station = outside(true)
  local state = game.state
  local ux, uy, uz = outward(station, me)
  -- A pirate told to come right in gets to the edge and no farther.
  local scout = Pirates.Spawn(state, Pirates.SCOUT, me.system, me.x + ux * 3000, me.y + uy * 3000, me.z + uz * 3000, me.grid)
  state.pilots[scout.id] = nil
  State.RemoveId(state.pilotIds, scout.id)
  scout.mode, scout.target, scout.range = "approach", station.id, 0
  local nearest = math.huge
  for _ = 1, 120 do
    Core.Step(game)
    nearest = math.min(nearest, Space.Distance(station :: any, scout :: any))
  end
  t.ok(nearest >= station.radius, `a pirate got {math.floor(station.radius - nearest)} m inside the field`)
  t.ok(nearest < station.radius + 500, "and it should have come up to the field's edge")
  t.ok(Fields.Barred(state, station, scout.id))

  -- The pilot, told the same, goes in to the tower.
  t.ok(not Fields.Barred(state, station, me.id))
  t.ok(Core.Submit(game, { kind = "Approach", actor = me.id, target = station.id, range = 0 }))
  steps(game, 240)
  t.ok(Fields.Within(station, me :: any), "an approach to a station should take a ship inside its field")
  t.ok(Space.Distance(station :: any, me :: any) < station.radius * 0.5, "and well inside it")

  -- Marked by the patrols, they are the station's to fire on: out they go.
  state.player.marked = state.tick + 500
  t.ok(Fields.Barred(state, station, me.id))
  steps(game, 12)
  t.ok(not Fields.Within(station, me :: any), "a marked pilot was left inside the field")
  t.eq(Core.Query.Field(game), 0)
end)

suite:Case("a missile on its way is stopped by the field its target goes into, and whoever was after them turns on the tower and then goes", function(t)
  local game, me, station = outside(true)
  local state = game.state
  local ux, uy, uz = outward(station, me)
  -- An emplacement of the pirates', launchers and all, six kilometres off.
  local guns = Pirates.Spawn(state, Pirates.kindById.battery, me.system, me.x + ux * 6000, me.y + uy * 6000, me.z + uz * 6000, me.grid)
  local launched = false
  for _ = 1, 60 do
    Core.Step(game)
    launched = launched or #state.missiles > 0
    if launched then
      break
    end
  end
  t.ok(launched, "the emplacement never fired")
  t.eq(state.pilots[guns.id].prey, me.id)
  -- Inside, with missiles in the air: none of them lands.
  put(me, station, ux, uy, uz, 0.4)
  local shield, armor = me.vitals.shield, me.vitals.armor
  local seen = steps(game, 30)
  local mine = 0
  for _, missile in state.missiles do
    mine += if missile.to == me.id then 1 else 0
  end
  t.eq(mine, 0, "missiles for the pilot are still in the air after thirty seconds")
  t.ok(me.vitals.shield >= shield and me.vitals.armor >= armor, "a missile came through the field")
  -- It cannot go for the pilot any more, and turns on the tower.
  t.eq(state.pilots[guns.id].prey, 0)
  local onTower = false
  for _, event in seen do
    onTower = onTower or (event.kind == "Shot" and event.from == guns.id and event.to == station.id)
  end
  t.ok(onTower, "with its prey inside the field, a pirate should fire on the tower")
  -- And when that has got it nowhere for long enough, it is gone.
  steps(game, 320)
  t.eq(state.balls[guns.id], nil, "it should have given the tower up")
end)

suite:Case("with a pilot inside the field, pirates go for the batteries that stand outside it", function(t)
  local game, me, station = outside()
  local state = game.state
  local ux, uy, uz = outward(station, me)
  t.ok(#state.batteries.balls > 0, "the station's batteries are not standing")
  put(me, station, ux, uy, uz, 0.4)
  local pack: { State.Ball } = {}
  for index = 1, 3 do
    table.insert(pack, Pirates.Spawn(state, Pirates.SCOUT, me.system, station.x + ux * (station.radius + 4000 + 300 * index),
      station.y + uy * (station.radius + 4000 + 300 * index), station.z + uz * (station.radius + 4000 + 300 * index), me.grid))
  end
  steps(game, 3)
  for _, pirate in pack do
    local prey = state.pilots[pirate.id].prey
    t.ok(table.find(state.batteries.balls, prey) ~= nil, "a pirate with nobody else to go for should go for a battery")
  end
end)

suite:Case("which stations have a field: all but a dark tower of the pilot's own, and a colony ship", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local ship = state.player.ship
  t.ok(Fields.Of(state, state.player.home) ~= nil)
  t.eq(Fields.Of(state, 0), nil)
  -- A tower of the pilot's own: none while it is dark, one when it has
  -- fuel, and it keeps it when it seals itself.
  local tower = Structures.towerById["tower.vessari.small"]
  local item = Items.Add(state, tower.id, 1, ship, "cargo")
  t.ok(Core.Submit(game, { kind = "Undock", actor = ship }))
  Core.Step(game)
  local moon = 0
  for _, object in Core.Query.Objects(game, 1) do
    if object.kind == "moon" and moon == 0 then
      moon = object.id
    end
  end
  local body = assert(Space.Object(state, moon))
  local me = state.balls[ship]
  me.x, me.y, me.z = body.x + body.radius * 2, body.y, body.z
  Space.AssignGrid(state, me)
  t.ok(Core.Submit(game, { kind = "Stop", actor = ship }))
  t.ok(Core.Submit(game, { kind = "AnchorTower", actor = ship, item = item.id, target = moon }))
  steps(game, tower.anchor + 3)
  local station = state.starbaseIds[1]
  local starbase = state.starbases[station]
  t.eq(Fields.Of(state, station), nil, "a tower with no fuel has no field")
  t.eq(assert(Core.Query.Starbase(game, station)).field, false)
  starbase.fuel = 100
  t.ok(Fields.Of(state, station) ~= nil)
  starbase.sealed = state.tick + 100
  t.ok(Fields.Of(state, station) ~= nil, "a sealed tower keeps its field")
  t.eq(assert(Core.Query.Starbase(game, station)).field, true)
  -- (and its owner is never kept out of it, whatever the patrols think of them)
  state.player.marked = state.tick + 500
  t.ok(not Fields.Barred(state, assert(Space.Object(state, station)), ship))
end)

return suite
