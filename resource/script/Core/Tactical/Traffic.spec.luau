--!strict
-- The other ships about (Tactical/Traffic).

local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")
local Traffic = require("@lt/Core/Tactical/Traffic")

local suite = Test.Suite("Traffic")

local function busy(historySeed: number?): Core.Game
  return Core.New({ galaxySeed = 1, historySeed = historySeed or 1, peaceful = true, traffic = true })
end

local function steps(game: Core.Game, count: number)
  for _ = 1, count do
    Core.Step(game)
  end
end

-- How many of the traffic are haulers, and how many patrol.
local function count(state: State.State): (number, number)
  local haulers, patrols = 0, 0
  for _, id in state.trafficIds do
    if state.traffic[id].kind == "patrol" then
      patrols += 1
    else
      haulers += 1
    end
  end
  return haulers, patrols
end

-- Put the pilot's ship in space in a system (the flight is Space's to test).
local function move(game: Core.Game, system: number)
  local state = game.state
  if state.balls[state.player.ship] == nil then
    assert(Core.Submit(game, { kind = "Undock", actor = state.player.ship }))
    Core.Step(game)
  end
  local ball = state.balls[state.player.ship]
  local sun = Space.Describe(state, system).objects[1]
  ball.system = system
  ball.x, ball.y, ball.z = sun.x + 5e10, sun.y, sun.z
  Space.AssignGrid(state, ball)
end

suite:Case("a game with no traffic has none, and a secure system fills up to what it should have and no more", function(t)
  local quiet = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  steps(quiet, 600)
  t.eq({ #quiet.state.trafficIds, #quiet.state.shipIds }, { 0, 1 })

  local game = busy()
  local state = game.state
  local most = 0
  for _ = 1, 40 do
    steps(game, 60)
    local haulers, patrols = count(state)
    t.ok(haulers <= Traffic.HAULERS.secure and patrols <= Traffic.PATROLS.secure, `{haulers} haulers and {patrols} patrols about`)
    most = math.max(most, haulers)
  end
  local haulers, patrols = count(state)
  t.ok(most >= 3, `never more than {most} haulers about in a homeworld's system`)
  t.eq(patrols, Traffic.PATROLS.secure)
  t.ok(haulers >= 1)
  -- Every one is a real ship of the first system, in a hauler's hull or
  -- a patrol's, of the faction whose space it is or anybody's.
  for _, id in state.trafficIds do
    local record, ship = state.traffic[id], state.ships[id]
    local hull = Ships.byId[ship.type]
    t.eq(record.system, 1)
    if record.kind == "patrol" then
      t.eq({ ship.owner, hull.lineage } :: { any }, { "vessari", "vessari" } :: { any })
      t.ok(hull.class == "frigate" or hull.class == "destroyer")
      t.ok(#Items.Fitted(state, id) >= 3, "a patrol ship should be armed")
    else
      t.eq(hull.class, "industrial")
      t.ok(ship.owner == "vessari" or ship.owner == "civilian")
    end
  end
  -- Nothing but the traffic and the pilot's own, and nothing of a ship that has gone.
  t.eq(#state.shipIds, 1 + #state.trafficIds)
  for _, id in state.itemIds do
    local item = state.items[id]
    t.ok(item.holder == state.player.home or state.ships[item.holder] ~= nil, `an item is held by {item.holder}, which is gone`)
  end
  -- (and nobody was sent on into a system nobody has seen)
  local described = 0
  for _ in state.systems do
    described += 1
  end
  t.eq(described, 1)
end)

suite:Case("haulers come in by a gate to dock, and go out from a station to a gate, and are gone", function(t)
  local game = busy()
  local state = game.state
  local docked, jumped = 0, 0
  local seen: { [number]: string } = {}
  for _ = 1, 3000 do
    Core.Step(game)
    for _, id in state.trafficIds do
      seen[id] = state.traffic[id].kind
    end
    for _, event in Core.TakeEvents(game) do
      if event.kind == "BallRemoved" and seen[event.ball] then
        docked += if event.reason == "docked" and seen[event.ball] == "in" then 1 else 0
        jumped += if event.reason == "jumped" and seen[event.ball] == "out" then 1 else 0
        t.ok(state.ships[event.ball] == nil or event.reason == "docked", "a hauler that has gone is still a ship")
      end
    end
  end
  t.ok(docked >= 3, `only {docked} haulers docked in fifty minutes`)
  t.ok(jumped >= 3, `only {jumped} haulers left by a gate in fifty minutes`)
  t.ok(#state.shipIds <= 1 + Traffic.HAULERS.secure + Traffic.PATROLS.secure)
end)

suite:Case("how many are about follows from how safe the system is, and they do not outlast the pilot's leaving", function(t)
  local game = busy()
  local state = game.state
  steps(game, 600)
  t.ok(#state.trafficIds >= 3)
  for system, node in state.galaxy.systems do
    if system ~= 1 then
      move(game, system)
      Core.Step(game)
      for _, id in state.trafficIds do
        t.eq(state.traffic[id].system, system)
      end
      steps(game, 900)
      local band = Galaxy.Band(node.security)
      local haulers, patrols = count(state)
      t.ok(haulers <= Traffic.HAULERS[band], `{haulers} haulers in {band} space`)
      t.eq(patrols, Traffic.PATROLS[band])
      for _, id in state.trafficIds do
        local ship = state.ships[id]
        if band == "lawless" then
          t.eq(ship.owner, "civilian")
        end
      end
    end
  end
end)

suite:Case("firing on a ship that is no pirate's marks the pilot, and the patrol there fights them until it lapses", function(t)
  local game = busy()
  local state = game.state
  assert(Core.Submit(game, { kind = "Undock", actor = state.player.ship }))
  steps(game, 400)
  local patrol: State.Ball? = nil
  for _, id in state.trafficIds do
    if state.traffic[id].kind == "patrol" and patrol == nil then
      patrol = state.balls[id]
    end
  end
  local target = assert(patrol, "no patrol came to a homeworld's system")
  -- Beside it, and a lock.
  local me = state.balls[state.player.ship]
  me.x, me.y, me.z = target.x + 1500, target.y, target.z
  Space.AssignGrid(state, me)
  t.eq(me.grid, target.grid)
  t.ok(Core.Submit(game, { kind = "Stop", actor = me.id }))
  t.ok(Core.Submit(game, { kind = "LockTarget", actor = me.id, target = target.id }))
  steps(game, 15)
  t.eq(state.player.marked, 0)
  t.eq(state.pilots[target.id], nil)
  local hostile = false
  for _, entry in Core.Query.Overview(game) do
    hostile = hostile or entry.hostile
  end
  t.ok(not hostile, "a patrol is nobody's enemy until they make it one")
  -- Open fire.
  local gun = Items.Fitted(state, me.id)[1]
  t.ok(Core.Submit(game, { kind = "ActivateModule", actor = me.id, item = gun.id, target = target.id }))
  local marked = false
  for _ = 1, 3 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      marked = marked or event.kind == "Marked"
    end
  end
  t.ok(marked, "nothing said the pilot was marked")
  t.eq(state.player.marked > state.tick + Traffic.MARKED - 10, true)
  t.ok(state.pilots[target.id] ~= nil, "the patrol took no notice")
  local shield = me.vitals.shield
  steps(game, 40)
  t.ok(me.vitals.shield < shield or state.balls[me.id] == nil, "the patrol did not fire back")
  for _, entry in Core.Query.Overview(game) do
    if entry.id == target.id then
      t.ok(entry.hostile)
    end
  end
  -- It lapses, and the patrol stands down (if both are still there).
  state.player.marked = state.tick + 2
  steps(game, 5)
  if state.ships[target.id] then
    t.eq(state.pilots[target.id], nil)
    t.eq(#target.vitals.running, 0)
  end
end)

suite:Case("traffic is in the save, and the game goes on the same from it", function(t)
  local game = busy(3)
  steps(game, 700)
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  steps(game, 700)
  steps(loaded, 700)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.ok(#loaded.state.trafficIds >= 2)
end)

suite:Case("a save from before there was traffic opens as a game that has it", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local data, length = Core.Save(game)
  local file = Codec.Decode(data, length)
  file.saveVersion = 15
  file.state.traffic, file.state.trafficIds, file.state.trafficDue, file.state.trafficOn = nil, nil, nil, nil
  file.state.player.marked = nil
  local old, oldLength = Codec.Encode(file)
  local loaded = Core.Load(old, oldLength)
  t.eq({ loaded.state.trafficOn, loaded.state.player.marked, #loaded.state.trafficIds } :: { any }, { true, 0, 0 } :: { any })
  steps(loaded, 300)
  t.ok(#loaded.state.trafficIds >= 1)
end)

return suite
