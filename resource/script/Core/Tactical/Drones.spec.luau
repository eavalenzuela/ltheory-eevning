--!strict
-- Drones (Data/Drones, Tactical/Drones).

local Blueprints = require("@lt/Core/Data/Blueprints")
local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Drones = require("@lt/Core/Tactical/Drones")
local Items = require("@lt/Core/Assets/Items")
local Kinds = require("@lt/Core/Data/Drones")
local Modules = require("@lt/Core/Data/Modules")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")
local Vitals = require("@lt/Core/Tactical/Vitals")
local Types = require("@lt/Core/Data/Types")

local suite = Test.Suite("Drones")

-- The pilot in a hull, at rest in open space, with so many light drones
-- in the drone bay and the Drones skill at a level.
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
    Items.Add(state, "drone.light", drones, mine.id, "dronebay")
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
  t.eq({ Ships.byId["frigate.courier"].drones, Ships.byId["cruiser.ouyou"].drones, Ships.byId["battleship.owari"].drones,
    Ships.byId["capsule"].drones } :: { any }, { 1, 4, 5, 0 } :: { any })
end)

suite:Case("drones are launched from the hold, as many as the hull controls and the pilot has the skill for", function(t)
  local docked = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  t.eq(refused(docked, { kind = "LaunchDrones", actor = 0 }), "docked")
  local none = flying("cruiser.ouyou", 0, 5)
  t.eq(refused(none, { kind = "LaunchDrones", actor = 0 }), "no drones in the drone bay")
  local green = flying("cruiser.ouyou", 3, 0)
  t.eq(refused(green, { kind = "LaunchDrones", actor = 0 }), "needs Drones 1")
  -- A cruiser controls four: a pilot with Drones 2 has two out, and with Drones 5, four.
  local game = flying("cruiser.ouyou", 6, 2)
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

suite:Case("a tech 2 drone takes Drones 4 to have out, and flies a tougher hull with the tech 2 make of what it carries", function(t)
  -- With only tech 2 drones in the bay, a pilot short of the skill launches none.
  local game, me = flying("cruiser.ouyou", 0, 3)
  local state = game.state
  Items.Add(state, "drone.light.ii", 2, me.id, "dronebay")
  t.eq(refused(game, { kind = "LaunchDrones", actor = 0 }), "needs Drones 4 for what is in the bay")
  -- With plain ones beside them, the plain ones go and the others stay.
  Items.Add(state, "drone.light", 1, me.id, "dronebay")
  t.ok((submit(game, { kind = "LaunchDrones", actor = 0 })))
  local out = Drones.Out(state, me.id)
  t.eq({ #out, out[1].type, carried(game) } :: { any }, { 1, "drone.light", 2 } :: { any })
  -- With the skill, they go: each a tougher hull, with a tech 2 gun on it.
  state.skills.drones = 4
  t.ok((submit(game, { kind = "LaunchDrones", actor = 0 })))
  out = Drones.Out(state, me.id)
  t.eq({ #out, carried(game) }, { 3, 0 })
  local seen = 0
  for _, drone in out do
    if drone.type == "drone.light.ii" then
      seen += 1
      local ship, ball = state.ships[drone.ship], state.balls[drone.ship]
      t.eq({ ship.type, ball.name } :: { any }, { "drone.hull.light.ii", "Light Combat Drone II" } :: { any })
      local guns = Items.Fitted(state, drone.ship)
      t.eq({ #guns, guns[1].type, guns[1].charge } :: { any }, { 1, "drone.gun.light.ii", "ammo.fusion" } :: { any })
      t.ok(ball.vitals.armorMax > state.balls[out[1].ship].vitals.armorMax, "a tech 2 drone should have more armour")
    end
  end
  t.eq(seen, 2)
  -- The others of them: a mining drone and a repair drone of the tech 2 make carry the tech 2 make of their tools.
  local other, ship = flying("cruiser.ouyou", 0, 5)
  Items.Add(other.state, "drone.mining.ii", 1, ship.id, "dronebay")
  Items.Add(other.state, "drone.repair.ii", 1, ship.id, "dronebay")
  t.ok((submit(other, { kind = "LaunchDrones", actor = 0 })))
  local tools: { string } = {}
  for _, drone in Drones.Out(other.state, ship.id) do
    table.insert(tools, Items.Fitted(other.state, drone.ship)[1].type)
  end
  table.sort(tools)
  t.eq(tools, { "miner.drone.ii", "remote.armor.drone.ii" })
end)

suite:Case("a drone keeps station on its owner, fights what it is pointed at, and comes back when it is called", function(t)
  local game, me = flying("cruiser.ouyou", 2, 5)
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
  local game, me = flying("battleship.owari", 5, 5)
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
  local game, me = flying("cruiser.ouyou", 2, 5)
  local state = game.state
  t.ok((submit(game, { kind = "LaunchDrones", actor = 0 })))
  local trader = Space.NewShip(state, "industrial.mizumushi", "Trader", "civilian", 0)
  local ball = Space.Launch(state, trader, me.system, me.x + 3000, me.y, me.z)
  t.ok((submit(game, { kind = "EngageDrones", actor = 0, target = ball.id })))
  t.eq(state.player.marked, 0)
  steps(game, 40)
  t.ok(state.player.marked > state.tick, "drones fired on a trader and nobody was marked")
end)

suite:Case("when its owner warps or docks, a drone that is near is taken aboard and one that is not is lost", function(t)
  local game, me = flying("cruiser.ouyou", 2, 5)
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
  local game = flying("cruiser.ouyou", 3, 5)
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

suite:Case("drones go into a ship's drone bay at a station, as many as it has room for, and are launched from there", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local home = state.player.home
  state.skills.drones = 5
  -- A Courier's bay is ten cubic metres: two light drones, or one of the bigger kinds.
  t.eq({ Ships.byId["frigate.courier"].bay, Ships.byId["cruiser.ouyou"].bay, Ships.byId["capsule"].bay }, { 10, 50, 0 })
  local lights = Items.Add(state, "drone.light", 3, home, "hangar")
  local rounds = Items.In(state, home, "hangar")[1]
  t.eq(refused(game, { kind = "MoveItems", actor = 0, item = rounds.id, to = "dronebay", quantity = 1 }), "only drones go in a drone bay")
  t.eq(refused(game, { kind = "MoveItems", actor = 0, item = lights.id, to = "dronebay" }), "not enough room in the drone bay")
  t.ok((submit(game, { kind = "MoveItems", actor = 0, item = lights.id, to = "dronebay", quantity = 2 })))
  local status = Core.Query.Drones(game)
  t.eq({ status.carried, status.bayUsed, status.bay }, { 2, 10, 10 })
  -- (they are not in the hold: the hold is as empty as it was)
  t.eq(Core.Query.CargoUsed(game, state.player.ship), 0)
  -- Out of the bay again, into the hangar.
  local stack = Items.In(state, state.player.ship, "dronebay")[1]
  t.ok((submit(game, { kind = "MoveItems", actor = 0, item = stack.id, to = "hangar", quantity = 1 })))
  t.eq(Core.Query.Drones(game).carried, 1)
  -- Drones in the hold are cargo, and nothing is launched from there.
  local held = Items.Add(state, "drone.light", 1, state.player.ship, "cargo")
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  local me = state.balls[state.player.ship]
  me.x += 4e6
  me.vx, me.vy, me.vz = 0, 0, 0
  Space.AssignGrid(state, me)
  t.ok((submit(game, { kind = "Stop", actor = 0 })))
  t.ok((submit(game, { kind = "LaunchDrones", actor = 0 })))
  t.eq({ Core.Query.Drones(game).out, Core.Query.Drones(game).carried, state.items[held.id] ~= nil } :: { any }, { 1, 0, true } :: { any })
  t.eq(refused(game, { kind = "LaunchDrones", actor = 0 }), "no drones in the drone bay")
  -- Called back, it is in the bay again.
  t.ok((submit(game, { kind = "RecallDrones", actor = 0 })))
  for _ = 1, 120 do
    Core.Step(game)
    if Core.Query.Drones(game).out == 0 then
      break
    end
  end
  t.eq({ Core.Query.Drones(game).out, Core.Query.Drones(game).carried }, { 0, 1 })
  -- A save from before there was a bay: the drones in a hold go into the bay, as far as they fit.
  local old = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  Items.Add(old.state, "drone.light", 2, old.state.player.ship, "cargo")
  local data, length = Core.Save(old)
  local file = Codec.Decode(data, length)
  file.saveVersion = 32
  local before, beforeLength = Codec.Encode(file)
  local loaded = Core.Load(before, beforeLength)
  t.eq({ Core.Query.Drones(loaded).carried, Core.Query.CargoUsed(loaded, loaded.state.player.ship) }, { 2, 0 })
end)

suite:Case("a mining drone cuts the rock its owner is working, brings the ore back, and goes out again", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  state.skills.drones = 5
  local kind = Kinds.byId["drone.mining"]
  t.eq({ kind.role, Modules.byId[kind.gun].internal, Types.Info(kind.gun).scarce } :: { any }, { "mining", true, true } :: { any })
  Items.Add(state, "drone.mining", 1, state.player.ship, "dronebay")
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  -- Beside a rock of the first belt.
  local rock: any = nil
  for _, object in Core.Query.Objects(game, 1) do
    rock = rock or (if object.kind == "asteroid" then object else nil)
  end
  local me = state.balls[state.player.ship]
  me.x, me.y, me.z = rock.x + rock.radius + 3000, rock.y, rock.z
  me.vx, me.vy, me.vz = 0, 0, 0
  Space.AssignGrid(state, me)
  t.ok((submit(game, { kind = "Stop", actor = 0 })))
  t.ok((submit(game, { kind = "LaunchDrones", actor = 0 })))
  local drone = state.drones[state.droneIds[1]]
  local ball = state.balls[drone.ship]
  -- With no rock to go for it keeps station.
  steps(game, 5)
  t.eq({ ball.mode, ball.target } :: { any }, { "orbit", me.id } :: { any })
  -- Pointed at the rock (a ship is no target for it, and a rock none for a drone that fights).
  t.ok((submit(game, { kind = "EngageDrones", actor = 0, target = rock.id })))
  t.eq(drone.target, rock.id)
  local delivered = 0
  local seen = false
  for _ = 1, 600 do
    Core.Step(game)
    seen = seen or (ball.mode == "orbit" and ball.target == rock.id and #ball.vitals.running == 1)
    for _, event in Core.TakeEvents(game) do
      if event.kind == "DroneDelivered" and event.owner == me.id then
        delivered += event.units
      end
    end
    if delivered > 0 then
      break
    end
  end
  t.ok(seen, "the mining drone never cut the rock")
  t.ok(delivered > 0, "the mining drone brought nothing back")
  local ore = 0
  for _, item in Items.In(state, me.id, "cargo") do
    ore += if Types.Info(item.type).category == "ore" then item.quantity else 0
  end
  t.eq(ore, delivered)
  -- And out again for more.
  local again = false
  for _ = 1, 120 do
    Core.Step(game)
    again = again or (ball.mode == "orbit" and ball.target == rock.id)
  end
  t.ok(again, "the mining drone did not go back to the rock")
  -- Called back with ore aboard, the ore comes aboard with it.
  t.ok((submit(game, { kind = "RecallDrones", actor = 0 })))
  for _ = 1, 200 do
    Core.Step(game)
    if #state.droneIds == 0 then
      break
    end
  end
  t.eq({ #state.droneIds, Core.Query.Drones(game).carried }, { 0, 1 })
end)

suite:Case("a repair drone goes to whoever of its side has lost most armour and mends them", function(t)
  local game, me = flying("cruiser.ouyou", 1, 5)
  local state = game.state
  Items.Add(state, "drone.repair", 1, me.id, "dronebay")
  t.ok((submit(game, { kind = "LaunchDrones", actor = 0 })))
  t.eq(#state.droneIds, 2)
  local mender: State.Ball? = nil
  for _, id in state.droneIds do
    if state.drones[id].type == "drone.repair" then
      mender = state.balls[id]
    end
  end
  local drone = assert(mender)
  steps(game, 5)
  t.eq({ drone.mode, drone.target, #drone.vitals.running } :: { any }, { "orbit", me.id, 0 } :: { any })
  -- The owner's armour is knocked about.
  me.vitals.armor = me.vitals.armorMax * 0.5
  local started = false
  for _ = 1, 40 do
    Core.Step(game)
    started = started or (#drone.vitals.running == 1 and drone.vitals.running[1].target == me.id)
  end
  t.ok(started, "the repair drone did not set to")
  local before = me.vitals.armor
  steps(game, 60)
  t.ok(me.vitals.armor > before + 100, `the armour went from {before} to {me.vitals.armor} in a minute`)
  -- An engage order at a ship is not for it: it goes on mending.
  local scout = Pirates.Spawn(state, Pirates.SCOUT, me.system, me.x + 5000, me.y, me.z, me.grid)
  state.pilots[scout.id] = nil
  State.RemoveId(state.pilotIds, scout.id)
  t.ok((submit(game, { kind = "EngageDrones", actor = 0, target = scout.id })))
  t.eq(state.drones[drone.id].target, 0)
end)

suite:Case("a carrier launches fighters, a supercarrier bombers too, and the Fighters skill is how many a pilot has in hand", function(t)
  -- A battleship has no bay for one, whatever is in its drone bay.
  local other = (flying("battleship.owari", 0, 5))
  other.state.skills.fighters = 5
  Items.Add(other.state, "drone.fighter", 2, other.state.player.ship, "dronebay")
  t.eq(refused(other, { kind = "LaunchDrones", actor = 0 }), "this hull has no bay for a fighter")
  -- (with a drone beside them the drone goes out, and the fighters stay)
  Items.Add(other.state, "drone.light", 1, other.state.player.ship, "dronebay")
  t.ok((submit(other, { kind = "LaunchDrones", actor = 0 })))
  t.eq({ Core.Query.Drones(other).out, carried(other) }, { 1, 2 })

  -- A carrier: fighters want the Fighters skill, and bombers a bay it has not.
  local game, me = flying("carrier.azayake", 0, 5)
  local state = game.state
  Items.Add(state, "drone.fighter", 12, me.id, "dronebay")
  t.eq(refused(game, { kind = "LaunchDrones", actor = 0 }), "needs Fighters 1 for what is in the bay")
  -- Each level is four more in hand beside what Drones gives: at one, nine of the carrier's ten.
  state.skills.fighters = 1
  t.eq({ Drones.Max(state, me.id), Ships.byId["carrier.azayake"].drones } :: { any }, { 9, 10 } :: { any })
  state.skills.fighters = 2
  t.eq(Drones.Max(state, me.id), 10)
  t.ok((submit(game, { kind = "LaunchDrones", actor = 0 })))
  t.eq({ Core.Query.Drones(game).out, carried(game) }, { 10, 2 })
  local out = Drones.Out(state, me.id)
  for _, craft in out do
    t.eq({ craft.type, state.ships[craft.ship].type } :: { any }, { "drone.fighter", "drone.hull.fighter" } :: { any })
  end
  -- They fight what they are pointed at: a pirate destroyer does not last a minute against ten.
  local prey = Pirates.Spawn(state, Pirates.kindById.jackal, me.system, me.x + 5000, me.y, me.z, me.grid)
  state.pilots[prey.id] = nil
  State.RemoveId(state.pilotIds, prey.id)
  t.ok((submit(game, { kind = "EngageDrones", actor = 0, target = prey.id })))
  steps(game, 60)
  t.eq(state.balls[prey.id], nil, "ten fighters should have destroyed it")
  -- Called back, they are in the bay again.
  t.ok((submit(game, { kind = "RecallDrones", actor = 0 })))
  for _ = 1, 200 do
    Core.Step(game)
    if Core.Query.Drones(game).out == 0 then
      break
    end
  end
  t.eq({ Core.Query.Drones(game).out, carried(game) }, { 0, 12 })
  -- A bomber is not a carrier's to launch.
  for _, item in Items.In(state, me.id, "dronebay") do
    Items.Take(state, item, item.quantity)
  end
  Items.Add(state, "drone.bomber", 2, me.id, "dronebay")
  state.skills.fighters = 5
  t.eq(refused(game, { kind = "LaunchDrones", actor = 0 }), "this hull has no bay for a bomber")

  -- A supercarrier's: at Fighters 2 bombers want more skill, and at 3 they go out.
  local great, flagship = flying("supercarrier.nullo", 0, 5)
  Items.Add(great.state, "drone.bomber", 4, flagship.id, "dronebay")
  great.state.skills.fighters = 2
  t.eq(refused(great, { kind = "LaunchDrones", actor = 0 }), "needs Fighters 3 for what is in the bay")
  great.state.skills.fighters = 3
  t.ok((submit(great, { kind = "LaunchDrones", actor = 0 })))
  t.eq({ Core.Query.Drones(great).out, great.state.ships[Drones.Out(great.state, flagship.id)[1].ship].type } :: { any },
    { 4, "drone.hull.bomber" } :: { any })
  -- What a bomber throws is for what is big: it takes a pirates' tower apart, and hardly marks a frigate.
  local tower = Pirates.Spawn(great.state, Pirates.kindById.keep, flagship.system, flagship.x + 9000, flagship.y, flagship.z, flagship.grid)
  local whole = tower.vitals.shield
  t.ok((submit(great, { kind = "EngageDrones", actor = 0, target = tower.id })))
  steps(great, 120)
  local harm = whole - tower.vitals.shield
  t.ok(harm > 10000, `four bombers took {harm} off a tower's shield in two minutes`)
  -- Out, they are in the save.
  local data, length = Core.Save(great)
  t.eq(Core.Hash(Core.Load(data, length)), Core.Hash(great))
end)

-- (module expansion, 2026-11-16)
suite:Case("drone damage amplifiers fitted to the owner make its drones hit harder", function(t)
  local function harm(amplifiers: number): number
    local game, me = flying("cruiser.ouyou", 2, 5)
    local state = game.state
    -- (two low slots filled each time, so the items' ids, and the rolls hung on them, are the same)
    for n = 1, 2 do
      Items.Equip(state, me.id, if n <= amplifiers then "drone.amplifier" else "fitting.coprocessor")
    end
    t.ok((submit(game, { kind = "LaunchDrones", actor = 0 })))
    steps(game, 5)
    local scout = Pirates.Spawn(state, Pirates.SCOUT, me.system, me.x + 4000, me.y, me.z, me.grid)
    state.pilots[scout.id] = nil
    State.RemoveId(state.pilotIds, scout.id)
    -- (too tough to die in the time)
    scout.vitals.shield, scout.vitals.shieldMax = 1e7, 1e7
    t.ok((submit(game, { kind = "EngageDrones", actor = 0, target = scout.id })))
    steps(game, 60)
    return 1e7 - scout.vitals.shield
  end
  local plain, one, two = harm(0), harm(1), harm(2)
  t.ok(plain > 0, "the drones did no harm")
  t.near(one / plain, 1.15, 0.005)
  -- (a second one does less than the first: stacked like any other)
  t.ok(two / one > 1 and two / one < 1.15, `{two / one}`)
end)

suite:Case("drones are worked only so far from their ship: farther with the Drones skill and with a Drone Link Augmentor", function(t)
  local game, me = flying("cruiser.ouyou", 2, 5)
  local state = game.state
  t.ok((submit(game, { kind = "LaunchDrones", actor = 0 })))
  steps(game, 5)
  local reach = Drones.Reach(state, me.id)
  t.eq(reach, Drones.RANGE + 5 * Drones.RANGE_SKILL)
  -- Somebody out of reach is not to be engaged; somebody in it is.
  local far = Pirates.Spawn(state, Pirates.SCOUT, me.system, me.x + reach + 5000, me.y, me.z, me.grid)
  local near = Pirates.Spawn(state, Pirates.SCOUT, me.system, me.x + 4000, me.y, me.z, me.grid)
  for _, ball in { far, near } do
    state.pilots[ball.id] = nil
    State.RemoveId(state.pilotIds, ball.id)
  end
  t.eq(refused(game, { kind = "EngageDrones", actor = 0, target = far.id }), `beyond drone control range ({math.floor(reach / 1000)} km)`)
  t.ok((submit(game, { kind = "EngageDrones", actor = 0, target = near.id })))
  -- An augmentor fitted reaches farther.
  local link = Items.Add(state, "drone.link", 1, me.id, "cargo")
  link.slot = 99
  t.eq(Drones.Reach(state, me.id), reach + 20000)
  Items.Take(state, link, 1)
  t.eq(Drones.Reach(state, me.id), reach)
end)

suite:Case("a Drone Navigation Computer fitted makes its owner's drones fly faster, a second the less for the first", function(t)
  local game, me = flying("cruiser.ouyou", 2, 5)
  local state = game.state
  t.ok((submit(game, { kind = "LaunchDrones", actor = 0 })))
  steps(game, 2)
  local drone = state.ships[Drones.Out(state, me.id)[1].ship]
  local plain = Vitals.Stats(state, drone, nil).maxVelocity
  Items.Add(state, "drone.navigation", 1, me.id, "cargo").slot = 98
  local one = Vitals.Stats(state, drone, nil).maxVelocity
  t.near(one, plain * 1.2, 1e-6)
  Items.Add(state, "drone.navigation", 1, me.id, "cargo").slot = 99
  local two = Vitals.Stats(state, drone, nil).maxVelocity
  t.ok(two > one and two < plain * 1.2 * 1.2, "a second computer should add less")
end)

return suite
