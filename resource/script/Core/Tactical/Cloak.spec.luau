--!strict
-- The cloaking device (Data/Modules' 'cloak', Tactical/Combat).

local Core = require("@lt/Core/Api")
local Items = require("@lt/Core/Assets/Items")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Cloak")

local function submit(game: Core.Game, command: State.Command): (boolean, string?)
  command.actor = game.state.player.ship
  local ok, why = Core.Submit(game, command)
  Core.Step(game)
  return ok, why
end

local function refused(game: Core.Game, command: State.Command): string?
  command.actor = game.state.player.ship
  local ok, why = Core.Validate(game, command)
  return if ok then "(accepted)" else why
end

local function steps(game: Core.Game, count: number)
  for _ = 1, count do
    Core.Step(game)
  end
end

-- The pilot in open space, a long way from anything, with a cloaking
-- device in place of one of the Courier's guns.
local function adrift(): (Core.Game, State.Ball, State.Item)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local gun = Items.Fitted(state, state.player.ship)[1]
  Items.Take(state, gun, 1)
  local cloak = Items.Equip(state, state.player.ship, "cloak.device", nil)
  assert(submit(game, { kind = "Undock", actor = 0 }))
  local me = state.balls[state.player.ship]
  me.x += 5e7
  me.vx, me.vy, me.vz = 0, 0, 0
  Space.AssignGrid(state, me)
  assert(submit(game, { kind = "Stop", actor = 0 }))
  return game, me, cloak
end

suite:Case("a cloaking device wants its skill, and a cloaked ship is slow, locks nothing and fires nothing", function(t)
  local docked = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local item = Items.Add(docked.state, "cloak.device", 1, docked.state.player.home, "hangar")
  Items.Take(docked.state, Items.Fitted(docked.state, docked.state.player.ship)[1], 1)
  t.eq(refused(docked, { kind = "Fit", actor = 0, item = item.id }), "needs Cloaking 1")

  local game, me, cloak = adrift()
  local state = game.state
  local fast = me.maxVelocity
  t.eq(Core.Query.Cloaked(game, me.id), false)
  t.ok((submit(game, { kind = "ActivateModule", actor = 0, item = cloak.id })))
  t.eq(Core.Query.Cloaked(game, me.id), true)
  t.near(me.maxVelocity, fast * 0.25, 1e-6)
  -- Somebody to look at: it cannot be locked from under the cloak, nor a gun switched on.
  local trader = Space.NewShip(state, "industrial.hauler", "Trader", "civilian", 0)
  local other = Space.Launch(state, trader, me.system, me.x + 9000, me.y, me.z)
  t.eq(refused(game, { kind = "LockTarget", actor = 0, target = other.id }), "cloaked")
  local gun = Items.Fitted(state, me.id)[1]
  t.eq(refused(game, { kind = "ActivateModule", actor = 0, item = gun.id, target = other.id }), "cloaked")
  -- It costs a little capacitor all the while.
  local before = me.vitals.capacitor
  me.vitals.capacitor = before - 100
  steps(game, 20)
  t.ok(Core.Query.Cloaked(game, me.id))
  -- Switched off, the ship is itself again.
  t.ok((submit(game, { kind = "DeactivateModule", actor = 0, item = cloak.id })))
  steps(game, 6)
  t.eq(Core.Query.Cloaked(game, me.id), false)
  t.near(me.maxVelocity, fast, 1e-6)
  t.eq(refused(game, { kind = "LockTarget", actor = 0, target = other.id }), "(accepted)")
end)

suite:Case("nobody keeps a lock on a cloaked ship or goes for it, and it cannot cloak while anybody has it targeted", function(t)
  local game, me, cloak = adrift()
  local state = game.state
  local scout = Pirates.Spawn(state, Pirates.SCOUT, me.system, me.x + 12000, me.y, me.z, me.grid)
  -- The scout goes for the pilot and starts a lock: too late to cloak.
  steps(game, 3)
  t.eq(state.pilots[scout.id].prey, me.id)
  t.ok(#scout.vitals.locks == 1)
  t.eq(refused(game, { kind = "ActivateModule", actor = 0, item = cloak.id }), "somebody has you targeted")
  -- (its lock is broken for it, to see the rest)
  scout.vitals.locks, scout.vitals.running = {}, {}
  state.pilots[scout.id].prey = 0
  t.ok((submit(game, { kind = "ActivateModule", actor = 0, item = cloak.id })))
  steps(game, 30)
  t.ok(Core.Query.Cloaked(game, me.id))
  t.eq({ state.pilots[scout.id].prey, #scout.vitals.locks, scout.mode } :: { any }, { 0, 0, "stop" } :: { any })
  local ok, why = Core.Validate(game, { kind = "LockTarget", actor = scout.id, target = me.id })
  t.eq({ ok, why } :: { any }, { false, "no such target" } :: { any })
  local whole = me.vitals.shield
  steps(game, 60)
  t.ok(me.vitals.shield >= whole - 1, "a cloaked ship was shot at")
  -- Uncloaked, it is fair game again.
  t.ok((submit(game, { kind = "DeactivateModule", actor = 0, item = cloak.id })))
  steps(game, 8)
  t.eq(state.pilots[scout.id].prey, me.id)
end)

suite:Case("anything that comes within two kilometres switches a cloak off, and it cannot be switched on that near anything", function(t)
  local game, me, cloak = adrift()
  local state = game.state
  local trader = Space.NewShip(state, "industrial.hauler", "Trader", "civilian", 0)
  local other = Space.Launch(state, trader, me.system, me.x + 1500, me.y, me.z)
  t.eq(refused(game, { kind = "ActivateModule", actor = 0, item = cloak.id }), "too near Trader to cloak")
  other.x = me.x + 8000
  t.ok((submit(game, { kind = "ActivateModule", actor = 0, item = cloak.id })))
  steps(game, 5)
  t.ok(Core.Query.Cloaked(game, me.id))
  Core.TakeEvents(game)
  other.x = me.x + 1200
  steps(game, 2)
  t.eq(Core.Query.Cloaked(game, me.id), false)
  local told = false
  for _, event in Core.TakeEvents(game) do
    told = told or (event.kind == "Decloaked" and event.ball == me.id and event.by == "Trader")
  end
  t.ok(told, "nobody said the cloak was off")
  -- (a station does it too: nobody undocks cloaked)
  local home = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  Items.Take(home.state, Items.Fitted(home.state, home.state.player.ship)[1], 1)
  local fitted = Items.Equip(home.state, home.state.player.ship, "cloak.device", nil)
  t.ok((submit(home, { kind = "Undock", actor = 0 })))
  local why = refused(home, { kind = "ActivateModule", actor = 0, item = fitted.id })
  t.ok(why ~= "(accepted)" and string.sub(why or "", 1, 8) == "too near", `at the station's door: {tostring(why)}`)
end)

suite:Case("a cloaked ship can warp, and comes out of warp still cloaked", function(t)
  local game, me, cloak = adrift()
  t.ok((submit(game, { kind = "ActivateModule", actor = 0, item = cloak.id })))
  -- (to open space a long way off: a marked place)
  t.ok((submit(game, { kind = "Bookmark", actor = 0 })))
  local mark = Core.Query.Bookmarks(game)[1]
  mark.x += 3e7
  t.ok((submit(game, { kind = "WarpTo", actor = 0, target = mark.id })))
  local warped = false
  for _ = 1, 600 do
    Core.Step(game)
    warped = warped or (me.warp ~= nil and me.warp.stage == "warp")
    if warped and me.warp == nil then
      break
    end
  end
  t.ok(warped and me.warp == nil, "the cloaked ship did not make its warp")
  t.ok(Core.Query.Cloaked(game, me.id), "the cloak did not last the warp")
  -- It is in the save as it is.
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.ok(Core.Query.Cloaked(loaded, loaded.state.player.ship))
end)

return suite
