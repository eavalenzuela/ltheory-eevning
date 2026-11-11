--!strict
-- The M1 flight loop, played through the Core's front door with no
-- engine: undock, warp, approach, orbit, keep at range, jump, dock, and a
-- save taken in the middle of a warp.

local Codec = require("@lt/Core/Persist/Codec")
local Constants = require("@lt/Core/Data/Constants")
local Core = require("@lt/Core/Api")
local Items = require("@lt/Core/Assets/Items")
local Ships = require("@lt/Core/Data/Ships")
local Types = require("@lt/Core/Data/Types")
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

suite:Case("a fit's offence is what its loaded guns come to", function(t)
  local game = newGame()
  local ship = Core.Query.Player(game).ship
  local offence = Core.Query.Offence(game, ship)
  -- the starter ship: two small autocannons, loaded
  t.ok(offence.volley > 0 and offence.dps > 0, "loaded guns do damage")
  t.ok(offence.dps < offence.volley, "an autocannon takes more than a second a shot")
  t.near(offence.kinds[1] + offence.kinds[2] + offence.kinds[3] + offence.kinds[4], offence.dps, 1e-9)
  t.ok(offence.range > 500, "they reach somewhere")
  -- with nothing loaded they do none
  for _, item in Core.Query.Fitted(game, ship) do
    item.charge = ""
  end
  t.eq(Core.Query.Offence(game, ship).dps, 0)
end)

suite:Case("a save from the version before still opens", function(t)
  -- Version 8 had no count of goods lost to piracy in its markets. Make
  -- such a save from a new one and load it.
  local game = newGame()
  -- (a station's market exists once somebody has looked at it)
  Core.Query.Quote(game, Core.Query.Player(game).docked, "ore.ferrite")
  local data, length = Core.Save(game)
  local file = Codec.Decode(data, length)
  t.eq(file.saveVersion, Core.SAVE_VERSION)
  file.saveVersion = 8
  local markets = 0
  for _, market in file.state.markets do
    market.lost = nil
    markets += 1
  end
  t.ok(markets > 0)
  local old, oldLength = Codec.Encode(file)
  t.eq(Core.Hash(Core.Load(old, oldLength)), Core.Hash(game))
  -- Version 9 had the Kethri's missile frigate, the Spindle, which is now
  -- the Vessari Javelin: whatever was one comes through as the other.
  local renamed = Codec.Decode(data, length)
  renamed.saveVersion = 9
  local item = 0
  for id, held in renamed.state.items do
    if held.type == "ammo.emp" then
      item = id
    end
  end
  t.ok(item ~= 0, "the starting hangar has rounds in it to turn into a hull")
  renamed.state.items[item].type = "frigate.spindle"
  old, oldLength = Codec.Encode(renamed)
  t.eq(Core.Load(old, oldLength).state.items[item].type, "frigate.javelin")
  -- one from before any migration is still refused
  file.saveVersion = 3
  old, oldLength = Codec.Encode(file)
  t.fails(function()
    Core.Load(old, oldLength)
  end)
end)

suite:Case("a save from before item types were added keeps each type's own market figures", function(t)
  -- A market keeps its figures by a type's place among all the types.
  -- Make a save as it would have been before the structures were items:
  -- its markets without them, and so with every later type a place up.
  local game = newGame()
  local station = Core.Query.Player(game).docked
  t.ok(Core.Submit(game, { kind = "BuyNow", actor = game.state.player.ship, type = "ore.titanite", quantity = 50 }))
  Core.Step(game)
  local data, length = Core.Save(game)
  local file = Codec.Decode(data, length)
  local removed = 0
  for _, market in file.state.markets do
    for index = #market.classes, 1, -1 do
      local id: string = market.classes[index].id
      if string.sub(id, 1, 6) == "tower." or string.sub(id, 1, 6) == "array." or string.sub(id, 1, 5) == "fuel." then
        removed += 1
        table.remove(market.classes, index)
        for _, name in { "initial", "produced", "consumed", "used", "anchorIn", "anchorOut", "bought", "sold", "moved", "lost" } do
          table.remove(market[name], index)
        end
        for _, name in { "stock", "target", "anchor", "taste" } do
          table.remove(market.nodes[1][name], index)
        end
      end
    end
  end
  t.ok(removed > 10, "the save had no structures in its market to take out")
  local old, oldLength = Codec.Encode(file)
  local loaded = Core.Load(old, oldLength)
  -- Every type that was there has the figures it had, the ore that was
  -- bought among them, and the types that were not there start as new.
  for _, type in { "ore.titanite", "ore.ferrite", "mineral.iron", "ammo.emp", "frigate.courier", "shield.extender.small",
    "tag.pirate", "blueprint.ammo.emp" } do
    local now, was = Core.Query.Quote(loaded, station, type), Core.Query.Quote(game, station, type)
    t.eq({ now.stock, now.bid, now.ask } :: { any }, { was.stock, was.bid, was.ask } :: { any })
  end
  local fresh = Core.Query.Quote(Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true }), station, "fuel.block")
  local fuel = Core.Query.Quote(loaded, station, "fuel.block")
  t.eq({ fuel.stock, fuel.ask } :: { any }, { fresh.stock, fresh.ask } :: { any })
  t.ok(fuel.stock > 0)
  -- (and a save of today's is not touched by loading it)
  t.eq(Core.Hash(Core.Load(data, length)), Core.Hash(game))
  -- (and the game goes on from the old one)
  t.ok(Core.Submit(loaded, { kind = "BuyNow", actor = loaded.state.player.ship, type = "fuel.block", quantity = 10 }))
  for _ = 1, 20 do
    Core.Step(loaded)
  end
end)

suite:Case("what the pilot owns is listed place by place, the hold and where they are first", function(t)
  local game = newGame()
  local state = game.state
  local home = state.player.home
  local assets = Core.Query.Assets(game)
  t.eq(#assets, 1)
  local here = assets[1]
  t.eq({ here.station, here.here, here.system, #here.ships, here.ships[1].id } :: { any },
    { home, true, 1, 1, state.player.ship } :: { any })
  t.eq(#here.items, #Core.Query.Items(game, home, "hangar"))
  local worth = Ships.byId["frigate.courier"].basePrice
  for _, item in here.items do
    worth += item.quantity * Types.Info(item.type).basePrice
  end
  t.eq(here.worth, worth)
  t.ok(here.volume > 0)

  -- Something in the hold, something left at another station, and away.
  local rounds = Items.Add(state, "ammo.emp", 50, state.player.ship, "cargo")
  local other = 0
  for _, object in Core.Query.Objects(game, 1) do
    if object.kind == "station" and object.id ~= home and other == 0 then
      other = object.id
    end
  end
  t.ok(other ~= 0, "the first system has only one station")
  Items.Add(state, "ore.ferrite", 300, other, "hangar")
  assets = Core.Query.Assets(game)
  t.eq({ #assets, assets[1].station, assets[2].station, assets[3].station }, { 3, 0, home, other })
  t.eq({ assets[1].here, assets[2].here, assets[3].here }, { true, true, false })
  t.eq({ assets[1].items[1].id, assets[1].volume } :: { any }, { rounds.id, 50 * Types.Info("ammo.emp").volume } :: { any })
  t.eq({ #assets[3].ships, #assets[3].items, assets[3].worth }, { 0, 1, 300 * Types.Info("ore.ferrite").basePrice })
  -- (fitted modules are the ship's, not a stack somewhere)
  for _, place in assets do
    for _, item in place.items do
      t.eq(item.slot, 0)
    end
  end
  order(t, game, "Undock")
  Core.Step(game)
  assets = Core.Query.Assets(game)
  t.eq({ assets[1].station, assets[2].station, assets[2].here } :: { any }, { 0, home, false } :: { any })
  t.eq(#assets[2].ships, 0)
end)

return suite
