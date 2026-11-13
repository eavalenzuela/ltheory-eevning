--!strict
-- What a cloud of gas does to the ship in it (Tactical/Vapour).

local Combat = require("@lt/Core/Tactical/Combat")
local Core = require("@lt/Core/Api")
local Mining = require("@lt/Core/Tactical/Mining")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Rng = require("@lt/Core/Kernel/Rng")
local Sites = require("@lt/Core/Tactical/Sites")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")
local Test = require("@lt/Tool/Test")
local Vapour = require("@lt/Core/Tactical/Vapour")

local suite = Test.Suite("Vapour")

local function steps(game: Core.Game, count: number)
  for _ = 1, count do
    Core.Step(game)
  end
end

-- Put a ship somewhere, at rest, and on whatever grid that is.
local function put(game: Core.Game, ball: State.Ball, x: number, y: number, z: number)
  ball.x, ball.y, ball.z = x, y, z
  ball.vx, ball.vy, ball.vz = 0, 0, 0
  ball.mode, ball.target = "stop", 0
  Space.AssignGrid(game.state, ball)
end

-- A game with a vapour field in the home system and the pilot's ship in
-- the middle of one of its clouds: the game, the pilot's ball, the
-- cloud, and the field's other clouds.
local function inCloud(): (Core.Game, State.Ball, System.Object, { System.Object })
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local site = assert(Sites.Plant(state, 1, "gas", Rng.For(1, 2, 3), game.events), "no room for a vapour field")
  local clouds: { System.Object } = {}
  for _, object in Space.Describe(state, 1).objects do
    if object.site == site.id and Mining.Cloud(object) then
      table.insert(clouds, object)
    end
  end
  assert(#clouds >= 4, "a vapour field has four clouds at least")
  local command: State.Command = { kind = "Undock", actor = state.player.ship }
  assert(Core.Submit(game, command))
  Core.Step(game)
  local me = state.balls[state.player.ship]
  local cloud = table.remove(clouds, 1) :: System.Object
  put(game, me, cloud.x, cloud.y, cloud.z)
  assert(me.grid == site.id, "a vapour field should be a grid of its own")
  return game, me, cloud, clouds
end

-- A ship that is nobody's enemy and does nothing, so far straight up
-- from a point: its ball.
local function drifter(game: Core.Game, from: { x: number, y: number, z: number }, up: number): State.Ball
  local state = game.state
  local me = state.balls[state.player.ship]
  local ship = Space.NewShip(state, "frigate.courier", "Drifter", "vessari", 0)
  local ball = Space.Launch(state, ship, me.system, from.x, from.y + up, from.z)
  Space.AssignGrid(state, ball)
  assert(ball.grid == me.grid, "the drifter should be on the pilot's grid")
  return ball
end

local function lock(game: Core.Game, by: State.Ball, target: number): string
  local ok, why = Combat.Validate(game.state, { kind = "LockTarget", actor = by.id, target = target })
  return if ok then "yes" else why or "?"
end

suite:Case("a ship in a cloud, or within a little of its edge, is in the vapour; a cloud drawn off is no cover, and nowhere else is anybody in any", function(t)
  local game, me, cloud = inCloud()
  local state = game.state
  t.eq(Vapour.In(state, me), true)
  -- At its edge, a little outside it, and beyond that.
  local out = cloud.radius + me.radius
  put(game, me, cloud.x, cloud.y + out + Vapour.EDGE - 20, cloud.z)
  t.eq(Vapour.In(state, me), true)
  put(game, me, cloud.x, cloud.y + out + Vapour.EDGE + 20, cloud.z)
  t.eq(Vapour.In(state, me), false)
  t.eq({ Core.Query.Veiled(game, me.id) } :: { any }, { false, Vapour.SIGHT } :: { any })
  -- Back in it; and with the cloud drawn off there is nothing to be in.
  put(game, me, cloud.x, cloud.y, cloud.z)
  t.eq(Core.Query.Veiled(game, me.id), true)
  t.ok(Mining.Take(state, cloud, Mining.Left(state, cloud)) > 0)
  t.eq(Vapour.In(state, me), false)
  -- At a belt nobody is in any.
  for _, object in Space.Describe(state, 1).objects do
    if object.kind == "belt" then
      put(game, me, object.x, object.y, object.z)
      break
    end
  end
  t.ok(state.sites[me.grid] == nil)
  t.eq(Vapour.In(state, me), false)
end)

suite:Case("a ship in a cloud is locked only from close in, and locks no farther; rocks, wrecks and the clouds are locked from as far as ever", function(t)
  local game, me, cloud, others = inCloud()
  local state = game.state
  -- Eight kilometres off, in the clear: neither locks the other.
  local far = drifter(game, cloud, 8000)
  t.eq({ Vapour.In(state, me), Vapour.In(state, far) }, { true, false })
  t.eq({ lock(game, me, far.id), lock(game, far, me.id) }, { "lost in the vapour", "lost in the vapour" })
  -- Four kilometres off: each locks the other.
  local near = drifter(game, cloud, 4000)
  t.eq(Vapour.In(state, near), false)
  t.eq({ lock(game, me, near.id), lock(game, near, me.id) }, { "yes", "yes" })
  -- A cloud across the field is locked from where the pilot is, vapour or no.
  local across: System.Object? = nil
  for _, other in others do
    if Space.Gap(me :: any, other :: any) > Vapour.SIGHT and Space.Gap(me :: any, other :: any) < me.vitals.lockRange then
      across = other
    end
  end
  t.eq(lock(game, me, assert(across, "no cloud across the field in reach").id), "yes")
  -- Out of the cloud, in the clear, eight kilometres is nothing: the two in the clear lock each other.
  t.ok(Space.Gap(far :: any, near :: any) < Vapour.SIGHT)
  put(game, me, cloud.x, cloud.y - 8000, cloud.z)
  t.eq({ Vapour.In(state, me), Space.Gap(me :: any, far :: any) > 15000 }, { false, true })
  t.eq({ lock(game, me, far.id), lock(game, far, me.id) }, { "yes", "yes" })
  -- And it is whoever is in it, not who looks: with the other ship in the cloud and the pilot out, neither locks.
  put(game, near, cloud.x, cloud.y, cloud.z)
  t.eq({ Vapour.In(state, near), lock(game, me, near.id), lock(game, near, me.id) } :: { any },
    { true, "lost in the vapour", "lost in the vapour" } :: { any })
end)

suite:Case("a lock held is lost when its target goes into the vapour out of reach, and the overview says who is in it", function(t)
  local game, me, cloud = inCloud()
  put(game, me, cloud.x, cloud.y - 8000, cloud.z)
  local other = drifter(game, cloud, 8000)
  assert(Core.Submit(game, { kind = "LockTarget", actor = me.id, target = other.id }))
  steps(game, 30)
  t.ok(#me.vitals.locks == 1 and me.vitals.locks[1].locked, "the lock should be made, in the clear")
  local veiled: boolean? = nil
  for _, entry in Core.Query.Overview(game) do
    veiled = if entry.id == other.id then entry.veiled else veiled
  end
  t.eq(veiled, false)
  -- Into the cloud it goes: sixteen kilometres off still, and the lock is gone.
  Core.TakeEvents(game)
  put(game, other, cloud.x, cloud.y, cloud.z)
  steps(game, 2)
  local lost = ""
  for _, event in Core.TakeEvents(game) do
    lost = if event.kind == "LockLost" and event.ball == me.id then event.reason else lost
  end
  t.eq({ #me.vitals.locks, lost } :: { any }, { 0, "lost in the vapour" } :: { any })
  for _, entry in Core.Query.Overview(game) do
    veiled = if entry.id == other.id then entry.veiled else veiled
  end
  t.eq(veiled, true)
  -- It is in the save as it stands: nothing of it is kept but where the ships are.
  local data, length = Core.Save(game)
  t.eq(Core.Hash(Core.Load(data, length)), Core.Hash(game))
end)

suite:Case("whoever fights from far off comes in close with the vapour between, and stands off again in the clear", function(t)
  local game, me, cloud = inCloud()
  local state = game.state
  -- A battleship of the pirates', which likes fifteen kilometres.
  local kind = Pirates.kindById["ravager"]
  t.ok(kind.range > Vapour.SIGHT)
  local ball = Pirates.Spawn(state, kind, me.system, cloud.x, cloud.y + 20000, cloud.z, me.grid)
  steps(game, 3)
  t.eq({ state.pilots[ball.id].prey, ball.mode, ball.range } :: { any }, { me.id, "orbit", Vapour.CLOSE } :: { any })
  -- The pilot out in the clear, a long way from any cloud: it stands off at its own range.
  put(game, me, cloud.x, cloud.y - 12000, cloud.z)
  t.eq(Vapour.In(state, me), false)
  steps(game, 3)
  t.eq({ ball.mode, ball.range } :: { any }, { "orbit", kind.range } :: { any })
end)

return suite
