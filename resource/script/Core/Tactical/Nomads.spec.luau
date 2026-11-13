--!strict
-- The nomads' colony fleets (Tactical/Nomads), and the ships of one
-- where the pilot is (Tactical/Traffic).

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Core = require("@lt/Core/Api")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Nomads = require("@lt/Core/Tactical/Nomads")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")
local Traffic = require("@lt/Core/Tactical/Traffic")

local suite = Test.Suite("Nomads")

local function steps(game: Core.Game, count: number)
  for _ = 1, count do
    Core.Step(game)
  end
end

-- Put the pilot's ship in space in a system, far from everything (the
-- flight is Space's to test).
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

-- The ships of the traffic that are a colony fleet's: its colony ships,
-- and its escorts.
local function fleetOf(state: State.State): ({ number }, { number })
  local colony: { number }, escorts: { number } = {}, {}
  for _, id in state.trafficIds do
    local kind = state.traffic[id].kind
    if kind == "colony" then
      table.insert(colony, id)
    elseif kind == "escort" then
      table.insert(escorts, id)
    end
  end
  return colony, escorts
end

suite:Case("a colony fleet goes round its people's space a gate at a time, a quarter of an hour to a system; and there is a fleet for every thirty systems", function(t)
  for _, count in { 40, 400, 2000 } do
    for seed = 1, 3 do
      local galaxy = Galaxy.Describe(seed, count)
      local systems = galaxy.systems
      local fleets = Nomads.Fleets(galaxy)
      local held, home = 0, 0
      for id, system in systems do
        held += if system.owner == "kethri" then 1 else 0
        home = if system.home and system.owner == "kethri" then id else home
      end
      t.eq(#fleets, math.max(1, held // Nomads.SPAN), `seed {seed}, {count} systems, where the Kethri hold {held}`)
      for index, fleet in fleets do
        t.eq({ fleet.index, fleet.faction, fleet.hull } :: { any }, { index, "kethri", "ultracapital.leslarmesdenova" } :: { any })
        t.eq(fleet.name, if index == 1 then "Les Larmes de Nova" else `Les Larmes de Nova {if index == 2 then "II" else "III"}`)
        -- The walk: from the homeworld, through their own space and no other, each step a gate, and back
        -- round to where it began.
        local walk = fleet.walk
        t.eq(walk[1], home)
        local seen: { [number]: boolean } = {}
        for step, id in walk do
          seen[id] = true
          t.eq(systems[id].owner, "kethri")
          local before = walk[(step - 2) % #walk + 1]
          t.ok(#walk == 1 or table.find(systems[before].neighbors, id) ~= nil, `seed {seed}: a step of the walk with no gate, {before} to {id}`)
        end
        -- (every system of theirs that their own space reaches from home is on it)
        local reached, queue = { [home] = true }, { home }
        local at = 1
        while at <= #queue do
          for _, neighbor in systems[queue[at]].neighbors do
            if systems[neighbor].owner == "kethri" and not reached[neighbor] then
              reached[neighbor] = true
              table.insert(queue, neighbor)
            end
          end
          at += 1
        end
        for _, id in queue do
          t.ok(seen[id], `seed {seed}: system {id} is theirs and the fleet never comes`)
        end
        -- Where it is: a stay in each, then the next; and the system it goes to is where it then is.
        local system, from, to, came, goes = Nomads.At(fleet, 5 * Nomads.STAY + 7)
        t.eq({ came, goes }, { 5 * Nomads.STAY, 6 * Nomads.STAY })
        t.eq({ (Nomads.At(fleet, goes - 1)), (Nomads.At(fleet, goes)) }, { system, to })
        t.eq((Nomads.At(fleet, came - 1)), from)
        t.eq((Nomads.At(fleet, 5 * Nomads.STAY + 7 + #walk * Nomads.STAY)), system)
      end
      -- (fleets of the same people are apart on the walk)
      if #fleets > 1 then
        t.ok((Nomads.At(fleets[1], 0)) ~= (Nomads.At(fleets[2], 0)), `seed {seed}: two fleets in one system`)
      end
    end
  end
  -- A galaxy with no Kethri in it has no fleet.
  t.eq(#Nomads.Fleets(Galaxy.Describe(1, 12)), 0)
  t.eq(Nomads.STAY, 900)
end)

suite:Case("where the pilot is, a colony fleet is there to be seen: the colony ship with a weapon on every hardpoint, and its support fleet round it; it goes by its gate when its time is up, and comes in by the gate it came by", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true, traffic = true, systems = 40 })
  local state = game.state
  local fleet = Nomads.Fleets(state.galaxy)[1]
  -- (well into a stay, so that there is time to look)
  state.tick = 4 * Nomads.STAY + 100
  local system, _, to = Nomads.At(fleet, state.tick)
  t.eq(#Core.Query.Nomads(game), 1)
  t.eq({ Core.Query.Nomads(game)[1].system, Core.Query.Nomads(game)[1].name } :: { any }, { system, "Les Larmes de Nova" } :: { any })
  move(game, system)
  steps(game, 3)
  local colony, escorts = fleetOf(state)
  t.eq({ #colony, #escorts }, { 1, 14 })
  local ship = state.ships[colony[1]]
  t.eq({ ship.type, ship.name, ship.owner }, { "ultracapital.leslarmesdenova", "Les Larmes de Nova", "kethri" })
  -- A weapon on every hardpoint, each of its hardpoint's size.
  local turrets, launchers = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }
  for _, item in Items.Fitted(state, ship.id) do
    local module = Modules.byId[item.type]
    if module.hardpoint == "turret" then
      turrets[Modules.SizeOf(module)] += 1
    elseif module.hardpoint == "launcher" then
      launchers[Modules.SizeOf(module)] += 1
    end
  end
  t.eq({ turrets, launchers }, { { 40, 32, 24, 16 }, { 10, 8, 6, 4 } })
  -- It lies off the gate it will go out by, and its support fleet keeps by it: a carrier, battleships,
  -- battlecruisers, destroyers, frigates and hauliers, all the Kethri's own.
  local gate = assert(Space.Object(state, state.traffic[ship.id].goal))
  t.eq({ gate.kind, gate.to } :: { any }, { "gate", to } :: { any })
  local classes: { [string]: number } = {}
  for _, id in escorts do
    local hull = Ships.byId[state.ships[id].type]
    t.eq({ hull.lineage, state.ships[id].owner, state.traffic[id].goal } :: { any }, { "kethri", "kethri", ship.id } :: { any })
    classes[hull.class] = (classes[hull.class] or 0) + 1
  end
  t.eq(classes, { carrier = 1, battleship = 2, battlecruiser = 2, destroyer = 3, frigate = 4, industrial = 2 })
  steps(game, 60)
  local ball = state.balls[ship.id]
  local far = math.sqrt((ball.x - gate.x) ^ 2 + (ball.y - gate.y) ^ 2 + (ball.z - gate.z) ^ 2)
  t.ok(far > 20000 and far < 60000, `the colony ship is {far} m from its gate`)
  for _, id in escorts do
    local beside = state.balls[id]
    local off = math.sqrt((beside.x - ball.x) ^ 2 + (beside.y - ball.y) ^ 2 + (beside.z - ball.z) ^ 2)
    t.ok(off < 30000, `an escort is {off} m from the colony ship`)
  end
  -- They are in the save, and the game goes on the same from it.
  local data, length = Core.Save(game)
  t.eq(Core.Hash(Core.Load(data, length)), Core.Hash(game))

  -- Its time up, it is gone by that gate: and the pilot, who was not by the gate, sees it go.
  local theirs: { [number]: boolean } = { [ship.id] = true }
  for _, id in escorts do
    theirs[id] = true
  end
  Core.TakeEvents(game)
  steps(game, Nomads.STAY - state.tick % Nomads.STAY + 1)
  t.eq({ fleetOf(state) }, { {}, {} })
  local jumped = 0
  for _, event in Core.TakeEvents(game) do
    jumped += if event.kind == "BallRemoved" and theirs[event.ball] and event.reason == "jumped" and event.gate == gate.id then 1 else 0
  end
  t.eq(jumped, 15)
  -- In the next system, a pilot who is there as it comes sees it come in by the gate from here, and cross.
  local next, from = Nomads.At(fleet, state.tick)
  t.eq({ next, from }, { to, system })
  steps(game, Nomads.STAY - state.tick % Nomads.STAY - 2)
  move(game, (Nomads.At(fleet, state.tick + 5)))
  Core.TakeEvents(game)
  steps(game, 4)
  colony, escorts = fleetOf(state)
  t.eq({ #colony, #escorts }, { 1, 14 })
  local arrived = false
  for _, event in Core.TakeEvents(game) do
    arrived = arrived or (event.kind == "ColonyFleetArrived" and event.name == "Les Larmes de Nova" and event.ships == 15)
  end
  t.ok(arrived, "nobody said it had come")
  -- Where the way on is not the way it came, it crosses the system: in by the one gate, a warp, and at rest
  -- off the other. (The first such system on its walk.)
  local stay = 0
  for step = 1, #fleet.walk do
    local _, before, after = Nomads.At(fleet, step * Nomads.STAY)
    if stay == 0 and before ~= after then
      stay = step
    end
  end
  t.ok(stay > 0, "its walk never crosses a system")
  state.tick = stay * Nomads.STAY - 2
  local across, cameFrom, goesTo = Nomads.At(fleet, state.tick + 5)
  move(game, across)
  steps(game, 6)
  colony, escorts = fleetOf(state)
  t.eq({ #colony, #escorts }, { 1, 14 })
  local out = assert(Space.Object(state, state.traffic[colony[1]].goal))
  t.eq(out.to, goesTo)
  local came = state.balls[colony[1]]
  t.ok(came.warp ~= nil or came.intent ~= nil, "it is not on its way across")
  local way: number? = nil
  for _, object in Space.Describe(state, across).objects do
    if object.kind == "gate" and object.to == cameFrom then
      way = math.sqrt((came.x - object.x) ^ 2 + (came.y - object.y) ^ 2 + (came.z - object.z) ^ 2)
    end
  end
  t.ok(way ~= nil and way < 80000, `it came in {way} m from the gate it came by`)
  steps(game, 400)
  came = state.balls[colony[1]]
  local off = math.sqrt((came.x - out.x) ^ 2 + (came.y - out.y) ^ 2 + (came.z - out.z) ^ 2)
  t.ok(came.warp == nil and off < 80000, `it came to rest {off} m from the gate it goes out by`)
  t.eq(came.mode, "orbit")
  for _, id in escorts do
    local beside = state.balls[id]
    local by = math.sqrt((beside.x - came.x) ^ 2 + (beside.y - came.y) ^ 2 + (beside.z - came.z) ^ 2)
    t.ok(beside.warp == nil and by < 60000, `an escort is {by} m from the colony ship after the crossing`)
  end
end)

suite:Case("a colony ship destroyed is gone for a day, and its support fleet with it when its time in the system is up; then another is on the walk", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true, traffic = true, systems = 40 })
  local state = game.state
  local fleet = Nomads.Fleets(state.galaxy)[1]
  state.tick = 2 * Nomads.STAY + 50
  move(game, (Nomads.At(fleet, state.tick)))
  steps(game, 3)
  local colony, escorts = fleetOf(state)
  t.eq({ #colony, #escorts }, { 1, 14 })
  Aftermath.Destroy(state, colony[1], 0, {})
  steps(game, 5)
  colony, escorts = fleetOf(state)
  t.eq({ #colony, #escorts }, { 0, 14 })
  t.eq({ Nomads.Gone(state, fleet), #Core.Query.Nomads(game) } :: { any }, { true, 0 } :: { any })
  steps(game, Nomads.STAY)
  t.eq({ fleetOf(state) }, { {}, {} })
  -- (nor is it in the next system, for a pilot who goes there)
  move(game, (Nomads.At(fleet, state.tick)))
  steps(game, 5)
  t.eq({ fleetOf(state) }, { {}, {} })
  -- A day on, there is one again.
  state.tick += Nomads.GONE
  t.eq({ Nomads.Gone(state, fleet), #Core.Query.Nomads(game) } :: { any }, { false, 1 } :: { any })
  move(game, (Nomads.At(fleet, state.tick)))
  steps(game, 3)
  colony, escorts = fleetOf(state)
  t.eq({ #colony, #escorts }, { 1, 14 })
end)

suite:Case("a pilot the Kethri would fight is fought by the colony fleet, and one they would not is left alone", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true, traffic = true, systems = 40 })
  local state = game.state
  local fleet = Nomads.Fleets(state.galaxy)[1]
  state.tick = 6 * Nomads.STAY + 20
  local system = (Nomads.At(fleet, state.tick))
  move(game, system)
  steps(game, 3)
  local colony = fleetOf(state)
  -- (beside it: on its grid)
  local ball, mine = state.balls[colony[1]], state.balls[state.player.ship]
  mine.x, mine.y, mine.z = ball.x + 20000, ball.y, ball.z
  Space.AssignGrid(state, mine)
  steps(game, 5)
  local fighting = 0
  for _, id in state.trafficIds do
    fighting += if state.pilots[id] then 1 else 0
  end
  t.eq(fighting, 0)
  -- Marked: every one of them turns on the pilot.
  state.player.marked = state.tick + Traffic.MARKED
  steps(game, 2)
  for _, id in state.trafficIds do
    local kind = state.traffic[id].kind
    if kind == "colony" or kind == "escort" then
      fighting += if state.pilots[id] then 1 else 0
    end
  end
  t.eq(fighting, 15)
  -- And the mark lapsed, they go back to their stations.
  state.player.marked = 0
  steps(game, 3)
  for _, id in state.trafficIds do
    t.eq(state.pilots[id], nil)
  end
  t.eq(state.balls[colony[1]].mode, "orbit")
end)

return suite
