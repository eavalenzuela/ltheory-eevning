--!strict
-- A station's guns (Tactical/Batteries).

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Batteries = require("@lt/Core/Tactical/Batteries")
local Core = require("@lt/Core/Api")
local Items = require("@lt/Core/Assets/Items")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Ships = require("@lt/Core/Data/Ships")
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

suite:Case("a station's batteries stand outside its field, to be shot at: one destroyed fires no more, and is built again", function(t)
  local game, me = outside(t)
  local state = game.state
  local station = assert(Space.Object(state, state.player.home))
  local standing = Batteries.Standing(state)
  local kinds = 0
  for _, module in assert(Stations.Makeup(state, station.id)).modules do
    kinds += if module == "battery.gun" or module == "battery.missile" then 1 else 0
  end
  t.ok(kinds > 0)
  t.eq(#standing, kinds)
  for index, id in standing do
    local ball, ship = state.balls[id], state.ships[id]
    t.ok(ball ~= nil and ship ~= nil, `battery {index} is not standing`)
    t.eq(Ships.byId[ship.type].class, "works")
    t.ok(Space.Distance(station :: any, ball :: any) > station.radius + ball.radius, `battery {index} stands inside the field`)
    t.eq(ball.grid, station.id)
    t.eq(ship.owner, Stations.People(state, station.id))
    -- (and can be locked by whoever is outside with it)
    t.ok((Core.Validate(game, { kind = "LockTarget", actor = me.id, target = id })))
  end
  t.eq({ Core.Query.Batteries(game, station.id) } :: { any }, { true, {} } :: { any })

  -- A pirate comes: every volley is from one of them.
  local scout = Pirates.Spawn(state, Pirates.SCOUT, me.system, me.x + (me.x - station.x), me.y + (me.y - station.y),
    me.z + (me.z - station.z), me.grid)
  state.pilots[scout.id] = nil
  State.RemoveId(state.pilotIds, scout.id)
  scout.mode = "stop"
  -- One of them is destroyed: it is down, the rest fire on, and it does not.
  local lost = standing[1]
  Aftermath.Destroy(state, lost, 0, game.events)
  local from: { [number]: number } = {}
  for _ = 1, 12 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      if event.kind == "BatteryFired" then
        from[event.from] = (from[event.from] or 0) + 1
      end
    end
  end
  t.eq(Batteries.Standing(state)[1], 0)
  t.eq({ Core.Query.Batteries(game, station.id) } :: { any }, { true, { 1 } } :: { any })
  t.eq(from[lost], nil, "a destroyed battery fired")
  for index = 2, kinds do
    t.ok((from[Batteries.Standing(state)[index]] or 0) > 0, `battery {index} did not fire`)
  end
  t.eq(from[station.id], nil, "a volley came from the station and not from a battery")

  -- When the pilot goes they are taken away, and when the pilot comes
  -- back they stand again, all but the one that is down: until its time.
  local ships = #state.shipIds
  me.x += 4e6
  Space.AssignGrid(state, me)
  steps(game, 2)
  t.eq(#Batteries.Standing(state), 0)
  t.ok(#state.shipIds <= ships - (kinds - 1), "the batteries were left standing with nobody there")
  me.x -= 4e6
  Space.AssignGrid(state, me)
  steps(game, 2)
  t.eq(Batteries.Standing(state)[1], 0, "a battery that is down should be down still")
  t.ok(Batteries.Standing(state)[2] ~= 0)
  -- Docked there, the pilot has not gone: the batteries are there still,
  -- and fire on a pirate that comes while the pilot is inside.
  t.ok(Core.Submit(game, { kind = "Dock", actor = me.id, target = station.id }))
  for _ = 1, 200 do
    Core.Step(game)
    if state.ships[state.player.ship].docked ~= 0 then
      break
    end
  end
  t.ok(state.ships[state.player.ship].docked ~= 0)
  steps(game, 2)
  t.ok(state.balls[Batteries.Standing(state)[2]] ~= nil, "the batteries should be there while the pilot is docked")
  local second = Pirates.Spawn(state, Pirates.SCOUT, scout.system, scout.x + 500, scout.y, scout.z, station.id)
  state.pilots[second.id] = nil
  State.RemoveId(state.pilotIds, second.id)
  second.mode = "stop"
  t.ok(steps(game, 12) >= 3, "the batteries did not fire on a pirate while the pilot was docked")
  t.ok(Core.Submit(game, { kind = "Undock", actor = state.player.ship }))
  steps(game, 3)
  state.batteries.down[1].back = state.tick + 2
  steps(game, 4)
  t.ok(Batteries.Standing(state)[1] ~= 0 and state.balls[Batteries.Standing(state)[1]] ~= nil, "a battery whose time has come was not built again")
  t.eq({ Core.Query.Batteries(game, station.id) } :: { any }, { true, {} } :: { any })
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
  -- (just outside its field, where its batteries stand: since 2026-11-20 a tower's field is the reference's, 15 km for a small)
  local field = assert(Space.Object(state, station))
  local scout = Pirates.Spawn(state, Pirates.SCOUT, me.system, field.x + field.radius + 2000, field.y, field.z, me.grid)
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
