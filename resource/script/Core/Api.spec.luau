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
  -- the Vessari Akashi: whatever was one comes through as the other.
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
  t.eq(Core.Load(old, oldLength).state.items[item].type, "frigate.akashi")
  -- one from before any migration is still refused
  file.saveVersion = 3
  old, oldLength = Codec.Encode(file)
  t.fails(function()
    Core.Load(old, oldLength)
  end)
end)

suite:Case("a save from before the entanglement projector had its name keeps the module and what it was doing", function(t)
  local game = newGame()
  local data, length = Core.Save(game)
  local file = Codec.Decode(data, length)
  file.saveVersion = 42
  local old = file.state
  -- As it was: the module under its old id, and a ship's share of its
  -- speed under the old name of that.
  local item = 0
  for id, held in old.items do
    if held.type == "ammo.emp" then
      item = id
    end
  end
  t.ok(item ~= 0, "the starting hangar has rounds in it to turn into a module")
  old.items[item].type = "web.stasis"
  old.balls[901] = { id = 901, vitals = { web = 0.45, scrambled = true } }
  local was, wasLength = Codec.Encode(file)
  local loaded = Core.Load(was, wasLength).state
  t.eq(loaded.items[item].type, "projector.entanglement")
  t.eq(loaded.balls[901].vitals.entangle, 0.45)
  t.eq((loaded.balls[901].vitals :: any).web, nil)
end)

suite:Case("a save from before the Kethri were nomads has their stations as colony ships and their towers as Vessari ones", function(t)
  local game = Core.New({ galaxySeed = 3, historySeed = 1, systems = 40, peaceful = true })
  local state = game.state
  -- A system of the Kethri's that has been seen. (There is no station
  -- in it now: among the Kethri there are none but the colony ships
  -- that roam. In a save from then there was one, which is put back
  -- here as it was, after everything else of the system, with the
  -- market it had: that of a station that has been looked at.)
  local theirs = 0
  for system = 1, 40 do
    if theirs == 0 and state.galaxy.systems[system].nearest == "kethri" then
      theirs = system
    end
  end
  t.ok(theirs ~= 0, "no system of the Kethri's in a galaxy of forty")
  local host = 0
  for _, object in Space.Describe(state, theirs).objects do
    t.ok(object.kind ~= "station", "a station among the Kethri")
    host = if object.kind == "moon" or (host == 0 and object.kind == "planet") then object.id else host
  end
  Core.Query.Quote(game, state.player.home, "ore.ferrite")
  local data, length = Core.Save(game)
  -- As it was: a station there of a kind and size, and a Kethri tower in
  -- the pilot's hangar, one anchored, and one in a market's list.
  local file = Codec.Decode(data, length)
  file.saveVersion = 41
  local old = file.state
  local station = theirs * 10000 + #old.systems[theirs].objects + 1
  table.insert(old.systems[theirs].objects, { id = station, kind = "station", name = "Somewhere IV - Moon 2 - Trade hub 1",
    x = 1e9, y = 0, z = 1e9, radius = 6400, seed = 7, parent = host, site = station, variety = "trade hub", to = 0 })
  old.markets[station] = Codec.Decode(Codec.Encode(old.markets[state.player.home]))
  table.insert(old.marketIds, station)
  table.sort(old.marketIds)
  local item = 0
  for id, held in old.items do
    if held.type == "ammo.emp" then
      item = id
    end
  end
  t.ok(item ~= 0, "the starting hangar has rounds in it to turn into a tower")
  old.items[item].type = "tower.kethri.medium"
  old.starbases[7] = { id = 7, tower = "tower.kethri.small", owner = "player", ready = 0, fuel = 0, burnt = 0, modules = {} }
  table.insert(old.starbaseIds, 7)
  local market = old.markets[station]
  table.insert(market.classes, { id = "tower.kethri.small", par = 1, cover = 0, need = 0 })
  for _, name in { "initial", "produced", "consumed", "used", "anchorIn", "anchorOut", "bought", "sold", "moved", "lost" } do
    table.insert(market[name], 0)
  end
  for _, name in { "stock", "target", "anchor", "taste" } do
    table.insert(market.nodes[1][name], 0)
  end
  local was, wasLength = Codec.Encode(file)
  local loaded = Core.Load(was, wasLength).state
  t.eq(loaded.items[item].type, "tower.vessari.medium")
  t.eq(loaded.starbases[7].tower, "tower.vessari.small")
  local object = assert(Space.Object(loaded, station))
  t.eq(object.name, "Somewhere IV - Moon 2 - Colony ship 1")
  t.eq(object.variety, "colony ship")
  t.eq(object.radius, 5000)
  t.eq(#loaded.markets[station].classes, #Types.Ids())
  for _, class in loaded.markets[station].classes do
    t.ok(string.find(class.id, "tower.kethri.", 1, true) == nil, "a market still lists a Kethri tower")
  end
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

suite:Case("an older save's galaxy is given the regions it would have had", function(t)
  local game = Core.New({ galaxySeed = 5, historySeed = 1, systems = 40, peaceful = true })
  local data, length = Core.Save(game)
  local file = Codec.Decode(data, length)
  file.saveVersion = 27
  file.state.galaxy.regions, file.state.galaxy.constellations = nil, nil
  for _, system in file.state.galaxy.systems do
    system.region, system.constellation = nil, nil
  end
  local old, oldLength = Codec.Encode(file)
  local loaded = Core.Load(old, oldLength)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  local player = Core.Query.Player(loaded)
  t.ok(#player.region > 4 and #player.constellation > 2)
  t.eq(player.region, loaded.state.galaxy.regions[loaded.state.galaxy.systems[1].region].name)
end)

suite:Case("a save with the hulls the Talmar had opens with the hulls they have: every one of them, wherever it is in the save", function(t)
  local game = newGame()
  local state = game.state
  local home = Core.Query.Player(game).docked
  -- A ship of theirs, a packed hull and its blueprint, a tech 2 make with a name of its own, and their market.
  Space.NewShip(state, "frigate.carvarro", "Spare", "player", home)
  Items.Add(state, "cruiser.paestro", 1, home, "hangar")
  Items.Add(state, "blueprint.battleship.phaeto", 1, home, "hangar")
  Items.Add(state, "industrial.tarantula", 1, home, "hangar")
  Core.Query.Quote(game, home, "destroyer.meseolo")
  Core.Step(game)
  local data, length = Core.Save(game)
  -- The same save as it was before their ships were gone through: every name of a new hull is the old one's.
  local WAS: { [string]: string } = {
    ["frigate.carvarro"] = "frigate.harrier", ["destroyer.meseolo"] = "destroyer.sabre", ["cruiser.paestro"] = "cruiser.falchion",
    ["battleship.phaeto"] = "battleship.claymore", ["industrial.sunfish"] = "industrial.packet",
    ["frigate.carvarro.ii"] = "frigate.harrier.ii", ["destroyer.meseolo.ii"] = "destroyer.sabre.ii",
    ["cruiser.paestro.ii"] = "cruiser.falchion.ii", ["battleship.phaeto.ii"] = "battleship.claymore.ii",
    ["industrial.tarantula"] = "industrial.packet.ii",
  }
  local changed = 0
  local function was(value: any): any
    if type(value) ~= "string" then
      return value
    elseif WAS[value] then
      return WAS[value]
    elseif string.sub(value, 1, 10) == "blueprint." and WAS[string.sub(value, 11)] then
      return "blueprint." .. WAS[string.sub(value, 11)]
    end
    return value
  end
  local function walk(node: any)
    local moved: { [any]: any } = {}
    for key, value in node do
      if type(value) == "table" then
        walk(value)
      elseif was(value) ~= value then
        node[key] = was(value)
        changed += 1
      end
      if was(key) ~= key then
        moved[key] = was(key)
      end
    end
    for key, old in moved do
      node[old] = node[key]
      node[key] = nil
      changed += 1
    end
  end
  local file = Codec.Decode(data, length)
  file.saveVersion = 64
  walk(file.state)
  t.ok(changed >= 4, `the save should have had the hulls in it: {changed} places`)
  local old, oldLength = Codec.Encode(file)
  local opened = Core.Load(old, oldLength)
  t.eq(Core.Hash(opened), Core.Hash(game))
  local hulls = 0
  for _, id in opened.state.shipIds do
    local ship = opened.state.ships[id]
    t.ok(Ships.byId[ship.type] ~= nil, `a ship of a hull there is not: {ship.type}`)
    hulls += if ship.type == "frigate.carvarro" then 1 else 0
  end
  t.eq(hulls, 1)
  for _, id in opened.state.itemIds do
    t.ok(Types.Get(opened.state.items[id].type) ~= nil, `an item of a type there is not: {opened.state.items[id].type}`)
  end
  -- And it goes on as the other does.
  for _ = 1, 20 do
    Core.Step(game)
    Core.Step(opened)
  end
  t.eq(Core.Hash(opened), Core.Hash(game))
end)

suite:Case("a save with the tech 2 make of a hull that every hull had opens with the plain hull, and what was fitted to it in its hold; and a hull the Vessari had is the one they have", function(t)
  local game = newGame()
  local state = game.state
  local home = Core.Query.Player(game).docked
  local spare = Space.NewShip(state, "frigate.akashi", "Spare", "player", home)
  -- (a gun fitted to it: put there by hand, the ship being nobody's to fit just now)
  local gun = Items.Add(state, "autocannon.small", 1, spare.id, "cargo")
  gun.place, gun.slot = "high", 1
  Items.Add(state, "blueprint.frigate.akashi", 1, home, "hangar")
  Items.Add(state, "drone.light.ii", 2, home, "hangar")
  local data, length = Core.Save(game)
  -- (as it was when the Vessari's frigate was the Javelin and there was a Javelin II: that ship is one, and
  -- the blueprint is its)
  local file = Codec.Decode(data, length)
  file.saveVersion = 65
  file.state.ships[spare.id].type = "frigate.javelin.ii"
  for _, item in file.state.items do
    if item.type == "blueprint.frigate.akashi" then
      item.type = "blueprint.frigate.javelin.ii"
    end
  end
  local old, oldLength = Codec.Encode(file)
  local opened = Core.Load(old, oldLength)
  t.eq(opened.state.ships[spare.id].type, "frigate.akashi")
  local fitted, held, blueprints, drones = 0, 0, 0, 0
  for _, id in opened.state.itemIds do
    local item = opened.state.items[id]
    t.ok(Types.Get(item.type) ~= nil, `an item of a type there is not: {item.type}`)
    fitted += if item.holder == spare.id and item.place == "high" then 1 else 0
    held += if item.holder == spare.id and item.place == "cargo" and item.type == "autocannon.small" then 1 else 0
    blueprints += if item.type == "blueprint.frigate.akashi" then item.quantity else 0
    -- (a drone has its "II" still, as a module has)
    drones += if item.type == "drone.light.ii" then item.quantity else 0
  end
  t.eq({ fitted, held, blueprints, drones }, { 0, 1, 1, 2 })
  for _ = 1, 10 do
    Core.Step(opened)
  end
end)

suite:Case("a save with a hull the Orun had opens with the hull of theirs that stands where it stood", function(t)
  local game = newGame()
  local state = game.state
  local home = Core.Query.Player(game).docked
  -- (name then, name now: a hull of the class they still build, and two of classes they do not)
  local WAS: { { string } } = { { "frigate.mastiff", "frigate.skinner" }, { "industrial.ox", "industrial.pill" },
    { "attackbattlecruiser.wolverine", "battlecruiser.zweihander" }, { "supercarrier.rookery", "carrier.katana" } }
  local ships: { number } = {}
  for index, pair in WAS do
    ships[index] = Space.NewShip(state, pair[2], `Spare {index}`, "player", home).id
    Items.Add(state, `blueprint.{pair[2]}`, index, home, "hangar")
  end
  local data, length = Core.Save(game)
  local file = Codec.Decode(data, length)
  file.saveVersion = 68
  for index, pair in WAS do
    file.state.ships[ships[index]].type = pair[1]
    for _, item in file.state.items do
      if item.type == `blueprint.{pair[2]}` then
        item.type = `blueprint.{pair[1]}`
      end
    end
  end
  local old, oldLength = Codec.Encode(file)
  local opened = Core.Load(old, oldLength)
  for index, pair in WAS do
    t.eq(opened.state.ships[ships[index]].type, pair[2])
    local blueprints = 0
    for _, id in opened.state.itemIds do
      local item = opened.state.items[id]
      t.ok(Types.Get(item.type) ~= nil, `an item of a type there is not: {item.type}`)
      blueprints += if item.type == `blueprint.{pair[2]}` then item.quantity else 0
    end
    t.eq(blueprints, index, pair[2])
  end
  t.eq(Core.Hash(opened), Core.Hash(game))
  for _ = 1, 10 do
    Core.Step(opened)
  end
end)

suite:Case("a save from when the Nimia were the Skarn opens with them the Nimia: their space, what they think of the pilot, and their hulls", function(t)
  -- A galaxy with all eight factions in it, and so with the Nimia holding space.
  local game = Core.New({ galaxySeed = 2, historySeed = 1, systems = 80, peaceful = true })
  local state = game.state
  local theirs = 0
  for _, system in state.galaxy.systems do
    theirs += if system.owner == "nimia" then 1 else 0
  end
  t.ok(theirs >= 1, "the Nimia hold nothing in a galaxy of eighty")
  state.standings.nimia = -3
  -- (name then, name now: hulls of classes they still build, and of two they do not)
  local WAS: { { string } } = { { "frigate.stinger", "frigate.oon" }, { "cruiser.broodguard", "cruiser.hon" },
    { "attackbattlecruiser.mauler", "battlecruiser.hoku" }, { "dreadnought.kraken", "siegedreadnought.zzk" },
    { "capitalindustrial.glutton", "capitalindustrial.zzna" } }
  local ships: { number } = {}
  for index, pair in WAS do
    ships[index] = Space.NewShip(state, pair[2], `Theirs {index}`, "nimia", 0).id
  end
  local data, length = Core.Save(game)
  -- As it was: the Skarn's systems, the Skarn's opinion, the Skarn's ships of the Skarn's hulls.
  local file = Codec.Decode(data, length)
  file.saveVersion = 70
  local old = file.state
  for _, system in old.galaxy.systems do
    if system.owner == "nimia" then
      system.owner = "skarn"
    end
  end
  old.standings.skarn, old.standings.nimia = old.standings.nimia, nil
  for index, pair in WAS do
    old.ships[ships[index]].type, old.ships[ships[index]].owner = pair[1], "skarn"
  end
  local was, wasLength = Codec.Encode(file)
  local opened = Core.Load(was, wasLength)
  local held = 0
  for _, system in opened.state.galaxy.systems do
    t.ok(system.owner ~= "skarn", `{system.name} is still the Skarn's`)
    held += if system.owner == "nimia" then 1 else 0
  end
  t.eq(held, theirs)
  t.eq({ opened.state.standings.nimia, opened.state.standings.skarn } :: { any }, { -3, nil } :: { any })
  for index, pair in WAS do
    local ship = opened.state.ships[ships[index]]
    t.eq({ ship.type, ship.owner } :: { any }, { pair[2], "nimia" } :: { any })
  end
  t.eq(Core.Hash(opened), Core.Hash(game))
  for _ = 1, 10 do
    Core.Step(opened)
  end
end)

suite:Case("a save with a hull the Kethri had opens with the hull of theirs that stands where it stood, and with nothing known of any colony ship lost", function(t)
  local game = newGame()
  local state = game.state
  local home = Core.Query.Player(game).docked
  -- (name then, name now: the frigate, which is the same hull; a cruiser, which they build no more; a supercarrier)
  local WAS: { { string } } = { { "frigate.lancer", "frigate.battleaxe" }, { "cruiser.trellis", "battlecruiser.extremis" },
    { "supercarrier.arcade", "carrier.tennit" }, { "industrial.lighter", "industrial.porter" } }
  local ships: { number } = {}
  for index, pair in WAS do
    ships[index] = Space.NewShip(state, pair[2], `Spare {index}`, "player", home).id
    Items.Add(state, `blueprint.{pair[2]}`, index, home, "hangar")
  end
  local data, length = Core.Save(game)
  local file = Codec.Decode(data, length)
  file.saveVersion = 69
  file.state.nomads = nil
  for index, pair in WAS do
    file.state.ships[ships[index]].type = pair[1]
    for _, item in file.state.items do
      if item.type == `blueprint.{pair[2]}` then
        item.type = `blueprint.{pair[1]}`
      end
    end
  end
  local old, oldLength = Codec.Encode(file)
  local opened = Core.Load(old, oldLength)
  for index, pair in WAS do
    t.eq(opened.state.ships[ships[index]].type, pair[2])
    local blueprints = 0
    for _, id in opened.state.itemIds do
      local item = opened.state.items[id]
      t.ok(Types.Get(item.type) ~= nil, `an item of a type there is not: {item.type}`)
      blueprints += if item.type == `blueprint.{pair[2]}` then item.quantity else 0
    end
    t.eq(blueprints, index, pair[2])
  end
  t.eq(opened.state.nomads, {})
  t.eq(Core.Hash(opened), Core.Hash(game))
  for _ = 1, 10 do
    Core.Step(opened)
  end
end)

suite:Case("a save from before the map had a height opens with the heights its galaxy would have had", function(t)
  local game = Core.New({ galaxySeed = 3, historySeed = 1, systems = 40 })
  local heights: { number } = {}
  local most = 0
  for id, system in game.state.galaxy.systems do
    heights[id] = system.z
    most = math.max(most, math.abs(system.z))
  end
  -- (a relief: some of it well out of the plane, none of it far, and neighbours at much the same height)
  t.ok(most > 2 and most <= 1.2 * 25, `the highest system is {most} light years out of the plane`)
  local data, length = Core.Save(game)
  local file = Codec.Decode(data, length)
  file.saveVersion = 67
  -- (the systems of the map: uncharted space came later, and has no height)
  for id = 1, file.state.galaxy.charted do
    file.state.galaxy.systems[id].z = nil
  end
  local old, oldLength = Codec.Encode(file)
  local opened = Core.Load(old, oldLength)
  for id, system in opened.state.galaxy.systems do
    t.eq(system.z, heights[id], `system {id}`)
  end
  t.eq(Core.Hash(opened), Core.Hash(game))
end)

return suite
