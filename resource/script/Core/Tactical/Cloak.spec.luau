--!strict
-- The cloaking device (Data/Modules' 'cloak', Tactical/Combat), and the
-- cloak a hull has of its own (Data/Ships' 'cloak').

local Attributes = require("@lt/Core/Attributes")
local Core = require("@lt/Core/Api")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Ships = require("@lt/Core/Data/Ships")
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

suite:Case("a hull built to go unseen keeps its speed under a cloak, and only what comes within a kilometre switches it off", function(t)
  -- The Talmar's tech 2 hauler, the Tarantula, is such a hull; their plain hauler is not.
  t.eq({ Ships.byId["industrial.tarantula"].stealth, Ships.byId["industrial.sunfish"].stealth } :: { any }, { true, nil } :: { any })
  local function aboard(type: string): (Core.Game, State.Ball, State.Item)
    local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
    local state = game.state
    local ship = Space.NewShip(state, type, "Runner", "player", state.player.home)
    state.player.ship = ship.id
    state.skills.cloaking = 1
    local cloak = Items.Equip(state, ship.id, "cloak.device", nil)
    assert(submit(game, { kind = "Undock", actor = 0 }))
    local me = state.balls[ship.id]
    me.x += 5e7
    me.vx, me.vy, me.vz = 0, 0, 0
    Space.AssignGrid(state, me)
    assert(submit(game, { kind = "Stop", actor = 0 }))
    return game, me, cloak
  end
  -- The plain hauler under a cloak flies at a quarter of its speed; the Tarantula at all of it.
  local plain, slow, device = aboard("industrial.sunfish")
  local was = slow.maxVelocity
  t.ok((submit(plain, { kind = "ActivateModule", actor = 0, item = device.id })))
  t.near(slow.maxVelocity, was * 0.25, 1)
  local game, me, cloak = aboard("industrial.tarantula")
  local state = game.state
  local fast = me.maxVelocity
  t.ok((submit(game, { kind = "ActivateModule", actor = 0, item = cloak.id })))
  t.eq({ Core.Query.Cloaked(game, me.id), me.maxVelocity } :: { any }, { true, fast } :: { any })
  -- Something a kilometre and a half off does not switch it off, as it would a plain hull's; inside a kilometre, it does.
  local trader = Space.NewShip(state, "industrial.hauler", "Trader", "civilian", 0)
  local other = Space.Launch(state, trader, me.system, me.x + 1500 + me.radius + 200, me.y, me.z)
  steps(game, 3)
  t.eq(Core.Query.Cloaked(game, me.id), true)
  other.x = me.x + 600 + me.radius + other.radius
  steps(game, 2)
  t.eq(Core.Query.Cloaked(game, me.id), false)
  -- And it cannot be switched on again that near, though it could at a kilometre and a half.
  local why = tostring(refused(game, { kind = "ActivateModule", actor = 0, item = cloak.id }))
  t.ok(string.find(why, "too near", 1, true) ~= nil, `within a kilometre: {why}`)
end)

-- The pilot in open space in a hull of a given type, with nothing fitted.
local function flying(type: string): (Core.Game, State.Ball)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local ship = Space.NewShip(state, type, "Runner", "player", state.player.home)
  state.player.ship = ship.id
  assert(submit(game, { kind = "Undock", actor = 0 }))
  local me = state.balls[ship.id]
  me.x += 5e7
  me.vx, me.vy, me.vz = 0, 0, 0
  Space.AssignGrid(state, me)
  assert(submit(game, { kind = "Stop", actor = 0 }))
  return game, me
end

suite:Case("a hull with a cloak of its own cloaks with nothing fitted: at its full speed and for no capacitor, until it is told to stop", function(t)
  -- The Orun's tech 2 frigate, the Skiver, is such a hull (the project owner's word); the Skinner it is made of is not.
  t.eq({ Ships.byId["frigate.skiver"].cloak, Ships.byId["frigate.skiver"].stealth } :: { any }, { true, true } :: { any })
  t.eq({ Ships.byId["frigate.skinner"].cloak, Ships.byId["frigate.skinner"].stealth } :: { any }, { nil, nil } :: { any })
  local plain = flying("frigate.skinner")
  t.eq({ Core.Query.OwnCloak(plain, plain.state.player.ship) } :: { any }, { false, false } :: { any })
  t.eq(refused(plain, { kind = "Cloak", actor = 0 }), "this hull has no cloak of its own")

  local game, me = flying("frigate.skiver")
  local state = game.state
  t.eq(#Items.Fitted(state, me.id), 0)
  t.eq({ Core.Query.OwnCloak(game, me.id) } :: { any }, { true, false } :: { any })
  t.eq(refused(game, { kind = "Uncloak", actor = 0 }), "not under the hull's own cloak")
  local fast = me.maxVelocity
  Core.TakeEvents(game)
  t.ok((submit(game, { kind = "Cloak", actor = 0 })))
  t.eq({ Core.Query.Cloaked(game, me.id), me.maxVelocity } :: { any }, { true, fast } :: { any })
  t.eq({ Core.Query.OwnCloak(game, me.id) } :: { any }, { true, true } :: { any })
  local told = false
  for _, event in Core.TakeEvents(game) do
    told = told or (event.kind == "Cloaked" and event.ball == me.id)
  end
  t.ok(told, "nobody said the cloak was on")
  t.eq(refused(game, { kind = "Cloak", actor = 0 }), "cloaked already")
  -- Nothing is locked from under it, as from under any cloak.
  local trader = Space.NewShip(state, "industrial.hauler", "Trader", "civilian", 0)
  local other = Space.Launch(state, trader, me.system, me.x + 9000, me.y, me.z)
  t.eq(refused(game, { kind = "LockTarget", actor = 0, target = other.id }), "cloaked")
  t.eq({ Core.Validate(game, { kind = "LockTarget", actor = other.id, target = me.id }) } :: { any }, { false, "no such target" } :: { any })
  -- It asks no capacitor: with none at all it stays on.
  me.vitals.capacitor = 0
  steps(game, 30)
  t.ok(Core.Query.Cloaked(game, me.id), "the hull's own cloak went off for want of capacitor")
  -- Told to stop, it is off at once, and says so.
  t.ok((submit(game, { kind = "Uncloak", actor = 0 })))
  t.eq(Core.Query.Cloaked(game, me.id), false)
  local off = false
  for _, event in Core.TakeEvents(game) do
    off = off or (event.kind == "Decloaked" and event.ball == me.id and event.by == "")
  end
  t.ok(off, "nobody said the cloak was off")
  t.eq(refused(game, { kind = "LockTarget", actor = 0, target = other.id }), "(accepted)")
end)

suite:Case("a hull's own cloak is a cloak like another: not while targeted nor near anything, broken by what comes near, kept through a warp and a save", function(t)
  local game, me = flying("frigate.skiver")
  local state = game.state
  local trader = Space.NewShip(state, "industrial.hauler", "Trader", "civilian", 0)
  local other = Space.Launch(state, trader, me.system, me.x + 9000, me.y, me.z)
  -- Not while anybody has it targeted.
  table.insert(other.vitals.locks, { target = me.id, done = 0, locked = true })
  t.eq(refused(game, { kind = "Cloak", actor = 0 }), "somebody has you targeted")
  other.vitals.locks = {}
  -- Not within a kilometre of anything (it is built to go unseen: half the two kilometres of a plain hull).
  other.x = me.x + 600 + me.radius + other.radius
  t.eq(refused(game, { kind = "Cloak", actor = 0 }), "too near Trader to cloak")
  other.x = me.x + 1500 + me.radius + other.radius
  t.ok((submit(game, { kind = "Cloak", actor = 0 })))
  steps(game, 3)
  t.eq(Core.Query.Cloaked(game, me.id), true)
  -- What comes within the kilometre switches it off.
  Core.TakeEvents(game)
  other.x = me.x + 600 + me.radius + other.radius
  steps(game, 2)
  t.eq({ Core.Query.Cloaked(game, me.id), me.vitals.cloaked } :: { any }, { false, nil } :: { any })
  local told = false
  for _, event in Core.TakeEvents(game) do
    told = told or (event.kind == "Decloaked" and event.ball == me.id and event.by == "Trader")
  end
  t.ok(told, "nobody said what switched the cloak off")
  -- It lasts a warp, and is in the save as it is.
  other.x = me.x + 9000
  t.ok((submit(game, { kind = "Cloak", actor = 0 })))
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
  t.ok(Core.Query.Cloaked(game, me.id), "the hull's own cloak did not last the warp")
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.eq({ Core.Query.OwnCloak(loaded, loaded.state.player.ship) } :: { any }, { true, true } :: { any })
end)

suite:Case("a cloaking device asks a quarter as much of a hull built for exploration", function(t)
  -- The Orun's tech 2 cruiser, the Falchion, is such a hull (the project owner's word); the Gladius it is made of is not.
  local falchion, gladius = Ships.byId["cruiser.falchion"], Ships.byId["cruiser.gladius"]
  t.eq({ falchion.explorer, gladius.explorer } :: { any }, { true, nil } :: { any })
  local device = Modules.byId["cloak.device"]
  t.eq({ Attributes.Needs(gladius, device) } :: { any }, { device.cpu, device.powergrid } :: { any })
  t.eq({ Attributes.Needs(falchion, device) } :: { any }, { device.cpu * 0.25, device.powergrid * 0.25 } :: { any })
  -- (and nothing else asks less of it)
  local analyzer = Modules.byId["analyzer.data"]
  t.eq({ Attributes.Needs(falchion, analyzer) } :: { any }, { analyzer.cpu, analyzer.powergrid } :: { any })
  -- What the fitting screen counts is the same.
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local ship = Space.NewShip(state, "cruiser.falchion", "Seeker", "player", state.player.home)
  Items.Equip(state, ship.id, "cloak.device", nil)
  t.eq({ Core.Query.FittingUse(game, ship.id) } :: { any }, { device.cpu * 0.25, device.powergrid * 0.25 } :: { any })
  -- It is a cloak like any other there: it slows the ship, which is not built to go unseen.
  t.eq(falchion.stealth, nil)
end)

return suite
