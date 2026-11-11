--!strict
-- A station's guns (Tactical/Batteries).

local Batteries = require("@lt/Core/Tactical/Batteries")
local Core = require("@lt/Core/Api")
local Items = require("@lt/Core/Assets/Items")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Stations = require("@lt/Core/Assets/Stations")
local Structures = require("@lt/Core/Data/Structures")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Batteries")

-- A game with the pilot's ship at rest outside the station they began at.
local function outside(t: Test.Context): (Core.Game, State.Ball)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  t.ok(Stations.Has(game.state, game.state.player.home, "defence"), "the starter station has no battery")
  t.ok(Core.Submit(game, { kind = "Undock", actor = game.state.player.ship }))
  Core.Step(game)
  t.ok(Core.Submit(game, { kind = "Stop", actor = game.state.player.ship }))
  Core.Step(game)
  local me = game.state.balls[game.state.player.ship]
  t.eq(me.grid, game.state.player.home)
  return game, me
end

local function steps(game: Core.Game, count: number): number
  local volleys = 0
  for _ = 1, count do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      volleys += if event.kind == "BatteryFired" then 1 else 0
    end
  end
  return volleys
end

suite:Case("a station leaves a pilot alone, and fires on one the patrols have marked until the mark lapses", function(t)
  local game, me = outside(t)
  t.eq(steps(game, 30), 0)
  t.near(me.vitals.shield, me.vitals.shieldMax, 1)
  game.state.player.marked = game.state.tick + 20
  local volleys = steps(game, 12)
  t.ok(volleys >= 4, `only {volleys} volleys in twelve seconds`)
  t.ok(me.vitals.shield < me.vitals.shieldMax * 0.8, "the batteries did the pilot no harm")
  steps(game, 10)
  t.eq(steps(game, 20), 0)
  -- A capsule is not worth a shell, marked or not.
  local pod = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local ship = pod.state.ships[pod.state.player.ship]
  ship.type = "capsule"
  t.ok(Core.Submit(pod, { kind = "Undock", actor = ship.id }))
  Core.Step(pod)
  pod.state.player.marked = pod.state.tick + 100
  t.eq(steps(pod, 20), 0)
end)

suite:Case("a station's batteries kill a pirate that comes to it, and nobody is paid for it", function(t)
  local game, me = outside(t)
  local wallet = game.state.wallet
  local scout = Pirates.Spawn(game.state, Pirates.SCOUT, me.system, me.x + 4000, me.y, me.z, me.grid)
  t.eq(scout.grid, me.grid)
  local volleys = steps(game, 90)
  t.ok(volleys > 0)
  t.eq(game.state.balls[scout.id], nil)
  t.eq(game.state.wallet, wallet)
  -- (and with nothing left to fire on, they stop)
  t.eq(steps(game, 20), 0)
  -- Out of reach, a pirate is safe from them.
  local far = Pirates.Spawn(game.state, Pirates.SCOUT, me.system, me.x + Batteries.RANGE + 20000, me.y, me.z, me.grid)
  far.mode = "stop"
  game.state.pilots[far.id] = nil
  State.RemoveId(game.state.pilotIds, far.id)
  t.eq(steps(game, 20), 0)
  t.ok(game.state.balls[far.id] ~= nil)
end)

suite:Case("a pilot's own starbase fires on pirates while it is lit, and never on its owner", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local ship = state.player.ship
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
  t.eq(me.grid, station)
  local starbase = state.starbases[station]
  table.insert(starbase.modules, { type = "battery.gun", ready = 0 })
  local scout = Pirates.Spawn(state, Pirates.SCOUT, me.system, me.x + 5000, me.y, me.z, me.grid)
  state.pilots[scout.id] = nil
  State.RemoveId(state.pilotIds, scout.id)
  -- Dark, it does nothing. Lit, it fires on the pirate.
  t.eq(steps(game, 12), 0)
  starbase.fuel = 100
  state.player.marked = state.tick + 500
  local shield = me.vitals.shield
  t.ok(steps(game, 12) >= 3, "a lit starbase's battery did not fire on a pirate")
  t.ok(scout.vitals.shield < scout.vitals.shieldMax)
  t.ok(me.vitals.shield >= shield, "a starbase fired on its owner")
end)

return suite
