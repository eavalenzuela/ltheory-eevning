--!strict
-- Drones (Data/Drones, Tactical/Drones).

local Blueprints = require("@lt/Core/Data/Blueprints")
local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Drones = require("@lt/Core/Tactical/Drones")
local Items = require("@lt/Core/Assets/Items")
local Kinds = require("@lt/Core/Data/Drones")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")
local Types = require("@lt/Core/Data/Types")

local suite = Test.Suite("Drones")

-- The pilot in a hull, at rest in open space, with so many light drones
-- in the hold and the Drones skill at a level.
local function flying(hull: string, drones: number, skill: number, traffic: boolean?): (Core.Game, State.Ball)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true, traffic = traffic })
  local state = game.state
  local old = state.player.ship
  for _, item in Items.In(state, old, nil) do
    Items.Take(state, item, item.quantity)
  end
  state.ships[old] = nil
  State.RemoveId(state.shipIds, old)
  local mine = Space.NewShip(state, hull, "Tester", "player", state.player.home)
  state.player.ship = mine.id
  state.skills.drones = skill
  if drones > 0 then
    Items.Add(state, "drone.light", drones, mine.id, "cargo")
  end
  local station = assert(Space.Object(state, state.player.home))
  local me = Space.Launch(state, mine, 1, station.x + 4e6, station.y, station.z)
  return game, me
end

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

local function carried(game: Core.Game): number
  return Core.Query.Drones(game).carried
end

suite:Case("a drone is an item with a blueprint and a hull of its own, and hulls control more of them the bigger they are", function(t)
  for _, kind in Kinds.list do
    t.eq(Types.Info(kind.id).category, "drone")
    t.ok(Blueprints.byProduct[kind.id] ~= nil, `no blueprint for {kind.name}`)
    local hull = Ships.byId[kind.hull]
    t.eq({ hull.class, hull.restricted, hull.drones } :: { any }, { "drone", true, 0 } :: { any })
    t.eq(Types.Get(kind.hull), nil)
  end
  t.eq({ Ships.byId["frigate.courier"].drones, Ships.byId["cruiser.cuirass"].drones, Ships.byId["battleship.bastion"].drones,
    Ships.byId["capsule"].drones } :: { any }, { 1, 4, 5, 0 } :: { any })
end)

suite:Case("drones are launched from the hold, as many as the hull controls and the pilot has the skill for", function(t)
  local docked = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  t.eq(refused(docked, { kind = "LaunchDrones", actor = 0 }), "docked")
  local none = flying("cruiser.cuirass", 0, 5)
  t.eq(refused(none, { kind = "LaunchDrones", actor = 0 }), "no drones in the hold")
  local green = flying("cruiser.cuirass", 3, 0)
  t.eq(refused(green, { kind = "LaunchDrones", actor = 0 }), "needs Drones 1")
  -- A cruiser controls four: a pilot with Drones 2 has two out, and with Drones 5, four.
  local game = flying("cruiser.cuirass", 6, 2)
  t.ok((submit(game, { kind = "LaunchDrones", actor = 0 })))
  local status = Core.Query.Drones(game)
  t.eq({ status.carried, status.out, status.max }, { 4, 2, 2 })
  t.eq(refused(game, { kind = "LaunchDrones", actor = 0 }), "as many drones are out as can be controlled")
  game.state.skills.drones = 5
  t.ok((submit(game, { kind = "LaunchDrones", actor = 0 })))
  status = Core.Query.Drones(game)
  t.eq({ status.carried, status.out, status.max }, { 2, 4, 4 })
  -- Each is a ship of the pilot's, armed, on the pilot's grid.
  local me = game.state.balls[game.state.player.ship]
  for _, drone in Drones.Out(game.state, me.id) do
    local ship, ball = game.state.ships[drone.ship], game.state.balls[drone.ship]
    t.eq({ ship.owner, ship.type, ball.grid } :: { any }, { "player", "drone.hull.light", me.grid } :: { any })
    t.eq(#Items.Fitted(game.state, drone.ship), 1)
  end
  -- A frigate controls one.
  local small = flying("frigate.courier", 3, 5)
  t.ok((submit(small, { kind = "LaunchDrones", actor = 0 })))
  t.eq({ Core.Query.Drones(small).out, carried(small) }, { 1, 2 })
end)

suite:Case("a drone keeps station on its owner, fights what it is pointed at, and comes back when it is called", function(t)
  local game, me = flying("cruiser.cuirass", 2, 5)
  local state = game.state
  t.ok((submit(game, { kind = "LaunchDrones", actor = 0 })))
  steps(game, 5)
  local out = Drones.Out(state, me.id)
  for _, drone in out do
    local ball = state.balls[drone.ship]
    t.eq({ ball.mode, ball.target } :: { any }, { "orbit", me.id } :: { any })
  end
  t.eq(refused(game, { kind = "EngageDrones", actor = 0, target = out[1].ship }), "no such target")
  -- Somebody to fight (who fights nobody back).
  local scout = Pirates.Spawn(state, Pirates.SCOUT, me.system, me.x + 4000, me.y, me.z, me.grid)
  state.pilots[scout.id] = nil
  State.RemoveId(state.pilotIds, scout.id)
  steps(game, 5)
  t.eq(state.balls[out[1].ship].target, me.id)
  t.ok((submit(game, { kind = "EngageDrones", actor = 0, target = scout.id })))
  t.eq(Core.Query.Drones(game).engaged, 2)
  local whole = scout.vitals.shield + scout.vitals.armor + scout.vitals.hull
  steps(game, 60)
  t.eq(state.balls[out[1].ship].target, scout.id)
  t.ok(state.balls[scout.id] == nil or scout.vitals.shield + scout.vitals.armor + scout.vitals.hull < whole, "two drones did a scout no harm in a minute")
  -- Called back, they are items in the hold again.
  t.ok((submit(game, { kind = "RecallDrones", actor = 0 })))
  t.eq(Core.Query.Drones(game).returning, 2)
  for _ = 1, 120 do
    Core.Step(game)
    if Core.Query.Drones(game).out == 0 then
      break
    end
  end
  t.eq({ Core.Query.Drones(game).out, carried(game) }, { 0, 2 })
  t.eq(#state.droneIds, 0)
  t.eq(refused(game, { kind = "RecallDrones", actor = 0 }), "no drones are out")
end)

suite:Case("a drone goes for whoever attacks its owner, and what it destroys is its owner's doing", function(t)
  local game, me = flying("battleship.bastion", 5, 5)
  local state = game.state
  t.ok((submit(game, { kind = "LaunchDrones", actor = 0 })))
  local scout = Pirates.Spawn(state, Pirates.SCOUT, me.system, me.x + 5000, me.y, me.z, me.grid)
  local wallet = state.wallet
  local dead = false
  for _ = 1, 400 do
    Core.Step(game)
    if state.balls[scout.id] == nil then
      dead = true
      break
    end
  end
  t.ok(dead, "five drones did not kill a scout that attacked their owner")
  t.eq(state.wallet - wallet, Pirates.SCOUT.bounty)
  -- (and with it gone they go back to keeping station)
  steps(game, 5)
  for _, drone in Drones.Out(state, me.id) do
    t.eq(drone.target, 0)
  end
end)

suite:Case("a pilot whose drones fire on somebody who is no pirate is marked for it", function(t)
  local game, me = flying("cruiser.cuirass", 2, 5)
  local state = game.state
  t.ok((submit(game, { kind = "LaunchDrones", actor = 0 })))
  local trader = Space.NewShip(state, "industrial.hauler", "Trader", "civilian", 0)
  local ball = Space.Launch(state, trader, me.system, me.x + 3000, me.y, me.z)
  t.ok((submit(game, { kind = "EngageDrones", actor = 0, target = ball.id })))
  t.eq(state.player.marked, 0)
  steps(game, 40)
  t.ok(state.player.marked > state.tick, "drones fired on a trader and nobody was marked")
end)

suite:Case("when its owner warps or docks, a drone that is near is taken aboard and one that is not is lost", function(t)
  local game, me = flying("cruiser.cuirass", 2, 5)
  local state = game.state
  t.ok((submit(game, { kind = "LaunchDrones", actor = 0 })))
  steps(game, 3)
  local out = Drones.Out(state, me.id)
  -- One is sent a long way off.
  local far = state.balls[out[2].ship]
  far.x += Drones.SCOOP * 4
  steps(game, 2)
  local planet = 0
  for _, object in Core.Query.Objects(game, 1) do
    if object.kind == "planet" and planet == 0 then
      planet = object.id
    end
  end
  t.ok((submit(game, { kind = "WarpTo", actor = 0, target = planet })))
  local scooped, lost = 0, 0
  for _ = 1, 60 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      scooped += if event.kind == "DroneScooped" then 1 else 0
      lost += if event.kind == "DroneLost" then 1 else 0
    end
  end
  t.eq({ scooped, lost }, { 1, 1 })
  t.eq({ Core.Query.Drones(game).out, carried(game) }, { 0, 1 })
  t.eq(#state.droneIds, 0)
  -- (and no ship or item of a drone that has gone is left behind)
  for _, id in state.shipIds do
    t.ok(Ships.byId[state.ships[id].type].class ~= "drone", "a drone's ship outlived the drone")
  end
end)

suite:Case("drones out are in the save, and an older save has none", function(t)
  local game = flying("cruiser.cuirass", 3, 5)
  t.ok((submit(game, { kind = "LaunchDrones", actor = 0 })))
  steps(game, 10)
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  steps(game, 50)
  steps(loaded, 50)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.eq(Core.Query.Drones(loaded).out, 3)
  local fresh = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local saved, savedLength = Core.Save(fresh)
  local file = Codec.Decode(saved, savedLength)
  file.saveVersion = 22
  file.state.drones, file.state.droneIds = nil, nil
  local old, oldLength = Codec.Encode(file)
  t.eq(#Core.Load(old, oldLength).state.droneIds, 0)
end)

return suite
