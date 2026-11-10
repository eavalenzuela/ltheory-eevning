--!strict
-- The M1 flight loop, played through the Core's front door with no
-- engine: undock, warp, approach, orbit, keep at range, jump, dock, and a
-- save taken in the middle of a warp.

local Constants = require("@lt/Core/Data/Constants")
local Core = require("@lt/Core/Api")
local Motion = require("@lt/Core/Tactical/Motion")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Flight")

-- Flight is the subject here, so no pirates.
local function newGame(): Core.Game
  return Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
end

local function me(game: Core.Game): State.Ball
  return assert(Core.Query.Ball(game, game.state.player.ship), "the player's ship is not in space")
end

local function order(t: Test.Context, game: Core.Game, kind: string, target: number?, range: number?)
  local ok, reason = Core.Submit(game, { kind = kind, actor = game.state.player.ship, target = target, range = range })
  t.ok(ok, `{kind} was refused: {tostring(reason)}`)
end

-- Step until an event of 'kind' happens; returns it and the ticks taken.
local function stepUntil(t: Test.Context, game: Core.Game, kind: string, limit: number): (Space.Event, number)
  for n = 1, limit do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      if event.kind == kind then
        return event, n
      end
    end
  end
  error(`no {kind} event within {limit} ticks`, 2)
end

local function steps(game: Core.Game, n: number)
  for _ = 1, n do
    Core.Step(game)
  end
  Core.TakeEvents(game)
end

-- The nearest overview entry of a kind.
local function nearest(t: Test.Context, game: Core.Game, kind: string): Core.Entry
  for _, entry in Core.Query.Overview(game) do
    if entry.kind == kind then
      return entry
    end
  end
  error(`nothing of kind {kind} on the overview`, 2)
end

local function gap(game: Core.Game, id: number): number
  return Space.Gap(me(game) :: any, assert(Core.Query.Body(game, id)))
end

local function speed(ball: State.Ball): number
  return math.sqrt(ball.vx ^ 2 + ball.vy ^ 2 + ball.vz ^ 2)
end

-- Bring the ship to rest in open space near the station.
local function undockAndStop(t: Test.Context, game: Core.Game)
  order(t, game, "Undock")
  steps(game, 1)
  order(t, game, "Stop")
  steps(game, 60)
  t.ok(speed(me(game)) < 0.01, "the ship did not come to rest")
end

suite:Case("a new game starts docked, and space commands are refused there", function(t)
  local game = newGame()
  local player = Core.Query.Player(game)
  t.ok(player.docked ~= 0)
  t.eq(player.system, 1)
  t.eq(Core.Query.Overview(game), {})
  t.eq({ Core.Validate(game, { kind = "Stop", actor = player.ship }) }, { false, "docked" } :: { any })
  t.eq({ Core.Validate(game, { kind = "Stop", actor = 12345 }) }, { false, "no such ship" } :: { any })
end)

suite:Case("undocking leaves the station at full speed, clear of its surface", function(t)
  local game = newGame()
  local station = Core.Query.Player(game).docked
  order(t, game, "Undock")
  local event = stepUntil(t, game, "Undocked", 1)
  t.eq(event.station, station)
  local ball = me(game)
  t.near(speed(ball), ball.maxVelocity, 1e-6)
  t.near(gap(game, station), Constants.UNDOCK_DISTANCE, 1e-3, "it appears the undock distance off the surface")
  t.eq(ball.grid, station, "it is on the station's grid")
  t.eq({ Core.Validate(game, { kind = "Undock", actor = ball.id }) }, { false, "not docked" } :: { any })
end)

suite:Case("from rest a ship enters warp after its align time and arrives on schedule", function(t)
  local game = newGame()
  undockAndStop(t, game)
  local ball = me(game)
  local belt = nearest(t, game, "belt")
  order(t, game, "WarpTo", belt.id, 0)
  local started, alignTicks = stepUntil(t, game, "WarpStarted", 20)
  -- The order takes effect at the next tick. From then, 75% of top speed
  -- takes 1.386 time constants: 4.88 s, so 5 whole ticks.
  t.eq(alignTicks, 1 + math.ceil(Motion.TimeToSpeed(ball.tau, Constants.WARP_ALIGN_SPEED) / Constants.TICK))
  t.eq(ball.grid, 0, "in warp a ship is on no grid")
  t.eq({ Core.Validate(game, { kind = "Stop", actor = ball.id }) }, { false, "in warp" } :: { any })
  local _, warpTicks = stepUntil(t, game, "WarpEnded", 200)
  t.eq(warpTicks, math.ceil(started.duration / Constants.TICK), "the warp took as long as planned")
  t.near(gap(game, belt.id), 0, 1e-3, "warping to 0 arrives at the belt")
  t.eq(ball.grid, belt.id)
  t.near(speed(ball), Constants.WARP_DROPOUT_SPEED, 1e-6, "it drops out at the dropout speed")
  -- the rocks are now on grid
  t.ok(nearest(t, game, "asteroid").onGrid)
end)

suite:Case("warping to 100 km stops 100 km short", function(t)
  local game = newGame()
  undockAndStop(t, game)
  local planet = nearest(t, game, "planet")
  order(t, game, "WarpTo", planet.id, 100000)
  stepUntil(t, game, "WarpEnded", 300)
  t.near(gap(game, planet.id), 100000, 1e-3)
end)

suite:Case("approach closes to the target without overshooting", function(t)
  local game = newGame()
  undockAndStop(t, game)
  order(t, game, "WarpTo", nearest(t, game, "belt").id, 0)
  stepUntil(t, game, "WarpEnded", 200)
  local rock = nearest(t, game, "asteroid")
  order(t, game, "Approach", rock.id, 500)
  local last = math.huge
  local closest = math.huge
  for _ = 1, 900 do
    Core.Step(game)
    local g = gap(game, rock.id)
    closest = math.min(closest, g)
    last = g
  end
  t.near(last, 500, 5, "it settles at the range asked for")
  t.ok(closest > 495, `it overshot to {closest} m`)
  t.ok(speed(me(game)) < 1, "and stops there")
end)

suite:Case("orbit holds its range at close to full speed", function(t)
  local game = newGame()
  undockAndStop(t, game)
  order(t, game, "WarpTo", nearest(t, game, "belt").id, 0)
  stepUntil(t, game, "WarpEnded", 200)
  local rock = nearest(t, game, "asteroid")
  order(t, game, "Orbit", rock.id, 5000)
  steps(game, 600)
  local ball = me(game)
  local low, high, slowest = math.huge, 0, math.huge
  local sx, sy, sz = ball.x, ball.y, ball.z
  local travelled = 0
  for _ = 1, 300 do
    Core.Step(game)
    local g = gap(game, rock.id)
    low, high = math.min(low, g), math.max(high, g)
    slowest = math.min(slowest, speed(ball))
    travelled = math.max(travelled, math.sqrt((ball.x - sx) ^ 2 + (ball.y - sy) ^ 2 + (ball.z - sz) ^ 2))
  end
  t.ok(low > 4500 and high < 5500, `the range wandered between {low} and {high} m`)
  t.ok(slowest > 0.9 * ball.maxVelocity, `it slowed to {slowest} m/s`)
  t.ok(travelled > 5000, "it is going round, not hovering")
end)

suite:Case("keep at range backs off as well as closes in", function(t)
  local game = newGame()
  undockAndStop(t, game)
  order(t, game, "WarpTo", nearest(t, game, "belt").id, 0)
  stepUntil(t, game, "WarpEnded", 200)
  local rock = nearest(t, game, "asteroid")
  order(t, game, "Approach", rock.id, 1000)
  steps(game, 900)
  order(t, game, "KeepAtRange", rock.id, 8000)
  steps(game, 900)
  t.near(gap(game, rock.id), 8000, 400, "it backed off to the range")
  t.ok(speed(me(game)) < 1)
end)

suite:Case("commands that make no sense are refused with a reason", function(t)
  local game = newGame()
  undockAndStop(t, game)
  local ship = game.state.player.ship
  local station = Core.Query.Player(game).docked
  local function refused(command: State.Command): string?
    local ok, reason = Core.Validate(game, command)
    t.ok(not ok, `{command.kind} was accepted`)
    return reason
  end
  local home = game.state.player.home
  t.eq(station, 0)
  t.eq(refused({ kind = "WarpTo", actor = ship, target = home }), "too close to warp")
  t.eq(refused({ kind = "Dock", actor = ship, target = nearest(t, game, "planet").id }), "not a station")
  t.eq(refused({ kind = "Jump", actor = ship, target = home }), "not a stargate")
  t.eq(refused({ kind = "Approach", actor = ship, target = ship }), "no such target")
  t.eq(refused({ kind = "Approach", actor = ship, target = 2 * Constants.STRUCTURE_ID_SPAN + 1 }), "no such target")
  t.eq(refused({ kind = "Orbit", actor = ship, target = home, range = -1 }), "range cannot be negative")
  t.eq(refused({ kind = "Goto", actor = ship }), "no direction")
  t.eq(refused({ kind = "Dance", actor = ship }), "unknown command 'Dance'")
  -- a queued command that stops being valid is dropped, not obeyed
  order(t, game, "Dock", home)
  steps(game, 1)
  order(t, game, "Stop")
  order(t, game, "Dock", home)
  local docked = false
  for _ = 1, 400 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      docked = docked or event.kind == "Docked"
    end
  end
  t.ok(docked, "the last order given wins")
end)

-- Jump to the next system and dock there. Calls 'midWarp' once, on the
-- tick after the ship enters warp toward the gate.
local function jumpAndDock(t: Test.Context, game: Core.Game, midWarp: ((Core.Game) -> ())?): number
  undockAndStop(t, game)
  local ticks = 0
  local gate = nearest(t, game, "gate")
  order(t, game, "Jump", gate.id)
  local _, n = stepUntil(t, game, "WarpStarted", 30)
  ticks += n
  steps(game, 3)
  ticks += 3
  if midWarp then
    midWarp(game)
  end
  local jumped, m = stepUntil(t, game, "Jumped", 2000)
  ticks += m
  t.eq(jumped.from, 1)
  local player = Core.Query.Player(game)
  t.eq(player.system, jumped.to)
  t.near(gap(game, jumped.arrival), Constants.JUMP_ARRIVAL_DISTANCE, 1e-3, "it appears a fixed distance from the far gate")
  t.eq(me(game).grid, jumped.arrival)
  local station = nearest(t, game, "station")
  order(t, game, "Dock", station.id)
  local docked, k = stepUntil(t, game, "Docked", 4000)
  ticks += k
  t.eq(docked.station, station.id)
  t.eq(Core.Query.Player(game).docked, station.id)
  t.eq(Core.Query.Ball(game, player.ship), nil, "a docked ship is not in space")
  t.eq(#game.state.gridIds, 0, "no open-space grid is left behind")
  return ticks
end

suite:Case("jump to the next system and dock there", function(t)
  jumpAndDock(t, newGame(), nil)
end)

suite:Case("the same orders give the same game", function(t)
  local a, b = newGame(), newGame()
  jumpAndDock(t, a, nil)
  jumpAndDock(t, b, nil)
  t.eq(Core.Hash(a), Core.Hash(b))
  local other = Core.New({ galaxySeed = 1, historySeed = 2, peaceful = true })
  jumpAndDock(t, other, nil)
  t.ok(Core.Hash(other) ~= Core.Hash(a), "a different history seed changes where the jump arrives")
end)

suite:Case("a save taken in mid-warp reloads and finishes identically", function(t)
  local straight = newGame()
  jumpAndDock(t, straight, nil)

  -- Same orders, but the game is replaced by its own save in mid-warp.
  local resumed = newGame()
  local saved: buffer? = nil
  local savedLength = 0
  undockAndStop(t, resumed)
  order(t, resumed, "Jump", nearest(t, resumed, "gate").id)
  stepUntil(t, resumed, "WarpStarted", 30)
  steps(resumed, 3)
  t.ok(me(resumed).warp ~= nil, "the save is taken in warp")
  saved, savedLength = Core.Save(resumed)
  local loaded = Core.Load(saved :: buffer, savedLength)
  t.eq(Core.Hash(loaded), Core.Hash(resumed), "loading gives back the saved state")
  stepUntil(t, loaded, "Jumped", 2000)
  order(t, loaded, "Dock", nearest(t, loaded, "station").id)
  stepUntil(t, loaded, "Docked", 4000)
  t.eq(Core.Hash(loaded), Core.Hash(straight))
end)

suite:Case("the state at a tick fixes the next second of flight", function(t)
  -- What the view relies on to draw between ticks: from a ball's position,
  -- velocity and target velocity (or its warp plan) the next tick's
  -- position follows exactly, whatever the ship is doing.
  local game = newGame()
  undockAndStop(t, game)
  order(t, game, "WarpTo", nearest(t, game, "belt").id, 0)
  local checked, warping = 0, 0
  local function checkTicks(n: number)
    for _ = 1, n do
      local ball = me(game)
      local x, y, z
      local warp = ball.warp
      if warp and warp.stage == "warp" then
        local plan = assert(warp.plan)
        local d = Motion.WarpAt(plan, (game.state.tick + 1 - warp.startTick) * Constants.TICK)
        x, y, z = warp.fx + warp.ux * d, warp.fy + warp.uy * d, warp.fz + warp.uz * d
        warping += 1
      else
        x, y, z = Motion.Step(ball.x, ball.y, ball.z, ball.vx, ball.vy, ball.vz,
          ball.tvx, ball.tvy, ball.tvz, ball.tau, Constants.TICK)
      end
      Core.Step(game)
      t.eq({ ball.x, ball.y, ball.z }, { x, y, z }, `tick {game.state.tick}`)
      checked += 1
    end
  end
  checkTicks(40)
  order(t, game, "Orbit", nearest(t, game, "asteroid").id, 3000)
  checkTicks(200)
  t.ok(warping > 5 and checked == 240, "the run covered warp and sub-warp flight")
end)

suite:Case("a file that is not a save is refused", function(t)
  t.fails(function()
    Core.Load(buffer.fromstring("LTV1 nonsense"))
  end)
  local game = newGame()
  local data, length = Core.Save(game)
  t.eq(Core.Hash(Core.Load(data, length)), Core.Hash(game))
end)

return suite
