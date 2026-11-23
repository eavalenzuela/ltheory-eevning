--!strict
-- A force out of wormhole space that means to stay (Tactical/Invasions).

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Constants = require("@lt/Core/Data/Constants")
local Core = require("@lt/Core/Api")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Happenings = require("@lt/Core/Strategic/Happenings")
local Invasions = require("@lt/Core/Tactical/Invasions")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Space = require("@lt/Core/Tactical/Space")
local Standings = require("@lt/Core/Assets/Standings")
local State = require("@lt/Core/Kernel/State")
local Stations = require("@lt/Core/Assets/Stations")
local Test = require("@lt/Tool/Test")
local Wormholes = require("@lt/Core/Tactical/Wormholes")

local suite = Test.Suite("Invasions")

type Event = { [string]: any }

local HOUR = math.floor(3600 / Constants.TICK + 0.5)

local function of(events: { Event }, kind: string): { Event }
  local found: { Event } = {}
  for _, event in events do
    if event.kind == kind then
      table.insert(found, event)
    end
  end
  return found
end

local function invasion(state: State.State): State.Happening?
  for _, one in state.happenings.list do
    if one.kind == Happenings.INVASION then
      return one
    end
  end
  return nil
end

-- A game with the pilot's ship in space, at rest, a long way from the station they began at.
local function away(): (Core.Game, State.State, State.Ball)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, systems = 40 })
  local state = game.state
  assert(Core.Submit(game, { kind = "Undock", actor = state.player.ship }))
  Core.Step(game)
  local me = state.balls[state.player.ship]
  me.x += 5e7
  me.vx, me.vy, me.vz, me.tvx, me.tvy, me.tvz = 0, 0, 0, 0, 0, 0
  me.mode = "stop"
  Space.AssignGrid(state, me)
  Core.TakeEvents(game)
  return game, state, me
end

suite:Case("one comes in its time, within reach and never at a homeworld; one at a time; and goes from stage to stage by the clock", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, systems = 40 })
  local state = game.state
  local all = state.happenings
  t.ok(all.invasionDue >= Invasions.FIRST[1] * HOUR and all.invasionDue <= Invasions.FIRST[2] * HOUR + 1)
  local events: { Event } = {}
  state.tick = all.invasionDue - 1
  Invasions.Step(state, 1, events)
  t.eq(invasion(state), nil)
  state.tick += 1
  Invasions.Step(state, 1, events)
  local one = assert(invasion(state), "no invasion came when it was due")
  local node = state.galaxy.systems[one.system]
  local far = Happenings.Reach(state, 1, Invasions.REACH)
  t.ok(far[one.system] ~= nil and far[one.system] >= Invasions.NEAR, "an invasion out of reach, or where the pilot is")
  t.ok(not node.home and not node.uncharted, "an invasion of a homeworld")
  local grade = Invasions.Grade(one)
  t.eq({ one.strength, one.stage, one.ends - one.began } :: { any }, { grade.force, 1, Invasions.LASTS * grade.long * HOUR } :: { any })
  -- No second while it is on, and its stages come by the clock.
  local station = 0
  for _, object in Space.Glance(state, one.system).objects do
    station = if station == 0 and object.kind == "station" then object.id else station
  end
  events = {}
  state.tick = one.began + math.floor(Invasions.STAGES[2] * HOUR)
  Invasions.Step(state, 1, events)
  t.eq({ one.stage, #of(events, "HappeningStage"), #of(events, "HappeningBegan") }, { 2, 1, 0 })
  if station ~= 0 and Stations.Makeup(state, station) then
    t.eq(Stations.Out(state, station, "refining"), nil, "their stations work until the invaders are at them")
  end
  state.tick = one.began + math.floor(Invasions.STAGES[3] * HOUR)
  Invasions.Step(state, 1, events)
  t.eq(one.stage, 3)
  if station ~= 0 then
    t.ok(Stations.Out(state, station, "refining") ~= nil and Stations.Out(state, station, "industry") ~= nil,
      "with the invaders at the stations every works there should have stopped")
    t.eq(Stations.Out(state, station, "market"), nil, "and nothing else of them")
  end
  t.eq(Stations.Out(state, state.player.home, "refining"), nil, "and no works anywhere else")

  -- Let be, it goes in its time: order there is thinner, a station's works are out for a day, and the next is hours off.
  local was = node.security
  events = {}
  state.tick = one.ends
  Invasions.Step(state, 1, events)
  t.eq(invasion(state), nil)
  local over = of(events, "HappeningEnded")
  t.eq({ #over, over[1].outcome } :: { any }, { 1, "over" } :: { any })
  if was > 0 then
    t.ok(node.security < was, "an invasion nobody answered should leave order thinner")
  end
  if station ~= 0 then
    local ruin = Happenings.In(state, one.system, Happenings.DISASTER)
    t.ok(ruin ~= nil and ruin.ends - state.tick == Invasions.RUIN * HOUR, "no works were left out of use after it")
  end
  local gap = all.invasionDue - state.tick
  t.ok(gap >= Invasions.EVERY[1] * HOUR and gap <= Invasions.EVERY[2] * HOUR, `the next invasion in {gap / HOUR} hours`)

  -- A game with no pirates has none.
  local quiet = Core.New({ galaxySeed = 1, historySeed = 1, systems = 40, peaceful = true }).state
  local none: { Event } = {}
  for _ = 1, 24 do
    quiet.tick += HOUR
    Invasions.Step(quiet, 1, none)
  end
  t.eq(#none, 0)
end)

suite:Case("where the pilot is: their lines and the way they came, a few of them at a time, and beaten when none is left", function(t)
  local game, state, me = away()
  local node = state.galaxy.systems[me.system]
  local one = Happenings.Begin(state, Happenings.INVASION, "deep", me.system, 0, Invasions.LASTS * HOUR, Invasions.FORCE, "", game.events)
  local holes = #state.wormholeIds
  Invasions.Step(state, me.system, game.events)
  t.ok(one.place ~= 0, "their lines were not staked")
  local place = assert(Space.Object(state, one.place))
  t.ok(string.find(place.name, "Invaders' Lines", 1, true) ~= nil, place.name)
  -- (the way they came: a great wormhole, open as long as they are)
  t.eq(#state.wormholeIds, holes + 1)
  local hole = state.wormholes[state.wormholeIds[#state.wormholeIds]]
  t.eq({ hole.from, hole.size, hole.closes } :: { any }, { me.system, 3, one.ends } :: { any })
  -- (from one of the Drowned's depths, past the pirates')
  t.ok((state.galaxy.systems[hole.to].depth or 0) > Galaxy.PIRATE_DEPTH, "the way they came is not from the Drowned's depths")
  t.ok(Wormholes.At(state, hole.a) ~= nil)
  -- Away from their lines nobody comes up.
  for _ = 1, 3 do
    state.tick += Invasions.REINFORCE
    Invasions.Step(state, me.system, game.events)
  end
  t.eq(#state.pilotIds, 0)
  -- At them, they come up one at a time, to no more than a few.
  me.x, me.y, me.z = place.x, place.y, place.z
  Space.AssignGrid(state, me)
  local most, sent = 0, 0
  local wallet, standing = state.wallet, Standings.Of(state, if Galaxy.Keeper(node) ~= "" then Galaxy.Keeper(node) else node.nearest)
  local was = node.security
  Core.TakeEvents(game)
  for _ = 1, 3000 do
    state.tick += 1
    local before = #state.pilotIds
    Invasions.Step(state, me.system, game.events)
    sent += #state.pilotIds - before
    most = math.max(most, #state.pilotIds)
    if Happenings.Get(state, one.id) == nil then
      break
    end
    -- (and once a few are up, one of them is destroyed)
    if #state.pilotIds >= 2 or one.strength <= 2 then
      local victim = state.pilotIds[1]
      if victim then
        Aftermath.Destroy(state, victim, state.player.ship, game.events)
      end
    end
  end
  t.eq(Happenings.Get(state, one.id), nil, "the invasion was never beaten")
  t.eq(sent, Invasions.FORCE, "as many came up as the force was")
  t.ok(most <= Invasions.WAVE and most >= 2, `{most} in space at once at the most`)
  local over = of(Core.TakeEvents(game), "HappeningEnded")
  t.eq({ over[1].outcome, over[1].kills } :: { any }, { "beaten", Invasions.FORCE } :: { any })
  -- The keeper pays and thinks the better of the pilot, order there is firmer, and their lines are let go.
  t.ok(state.wallet >= wallet + Invasions.REWARD, "beating an invasion was not paid for")
  t.ok(Standings.Of(state, if Galaxy.Keeper(node) ~= "" then Galaxy.Keeper(node) else node.nearest) > standing)
  if was < 1 then
    t.ok(node.security > was, "an invasion beaten should leave order firmer")
  end
  t.ok(state.sites[one.place].gone)
  t.eq(Happenings.In(state, me.system, Happenings.DISASTER), nil, "no works are left out of use after one that was beaten")
  -- The last of them was their leader, an officer by name: what was theirs is in the wreck.
  t.ok(over[1].name ~= "", "the leader of an invasion has a name")
  local theirs, mutators = 0, 0
  for _, id in state.wreckIds do
    if state.wrecks[id].name == over[1].name .. " Wreck" then
      for _, item in Items.In(state, id, nil) do
        local module = Modules.byId[item.type]
        theirs += if module and module.officer == over[1].name then item.quantity else 0
        mutators += if item.type == "mutator" then item.quantity else 0
      end
    end
  end
  t.eq({ theirs, mutators }, { Invasions.THEIRS, Invasions.MUTATORS })
end)

suite:Case("by depth: out of the fifth a bigger force than out of the fourth, now and then one in great force on the map, led by a capital", function(t)
  local seen: { [string]: number } = {}
  for seed = 1, 60 do
    local game = Core.New({ galaxySeed = 1, historySeed = seed, systems = 40 })
    local state = game.state
    state.tick = state.happenings.invasionDue
    Invasions.Step(state, 1, {})
    local one = invasion(state)
    if one then
      seen[one.what] = (seen[one.what] or 0) + 1
      local grade = Invasions.Grade(one)
      t.eq({ one.strength, one.ends - one.began } :: { any }, { grade.force, Invasions.LASTS * grade.long * HOUR } :: { any })
      if one.what == "great" then
        t.ok(not state.galaxy.systems[one.system].uncharted)
        local leader = Invasions.Leader(state, one)
        t.ok(leader == "drowned.reaper" or leader == Invasions.LEADER_END, leader)
      end
    end
  end
  t.ok((seen.deep or 0) > 0 and (seen.deep5 or 0) > 0 and (seen.great or 0) > 0, `of 60: {seen.deep} {seen.deep5} {seen.great}`)
  local deep, fifth, great = Invasions.GRADES.deep, Invasions.GRADES.deep5, Invasions.GRADES.great
  t.ok(fifth.force > deep.force and fifth.reward > deep.reward and fifth.theirs > deep.theirs)
  t.ok(great.force > fifth.force and great.long == 2 and great.reward > fifth.reward)
  -- (their capitals come in great force)
  local capitals = 0
  for _, id in great.turn do
    capitals += if id == "drowned.funeral" or id == "drowned.reaper" or id == "drowned.mercy" then 1 else 0
  end
  t.ok(capitals >= 3)
end)

suite:Case("they come into the shallow depths of uncharted space where the pilot is, and let be they fall on the pilot's towers there", function(t)
  local game, state, me = away()
  -- (the pilot in a system of the second depth, with a tower there)
  local shallow = 0
  for id = Galaxy.Charted(state.galaxy) + 1, #state.galaxy.systems do
    if shallow == 0 and state.galaxy.systems[id].depth == 2 then
      shallow = id
    end
  end
  t.ok(shallow ~= 0, "no system of the second depth")
  me.system = shallow
  Space.AssignGrid(state, me)
  local planet = 0
  for _, object in Space.Describe(state, shallow).objects do
    if planet == 0 and object.kind == "planet" then
      planet = object.id
    end
  end
  local starbase: State.Starbase = { id = planet, tower = "citadel.generator.large", owner = "player", ready = 0, fuel = 100, burnt = 0,
    modules = {}, drilled = 0, raid = 0, raids = 0, used = 0, raised = 0, robbed = 0, core = 0, charges = 0, sealed = 0, siege = 0,
    reaction = "", reacted = 0, composed = 0, starved = false }
  state.starbases[planet] = starbase
  table.insert(state.starbaseIds, planet)
  state.tick = math.max(state.tick, state.happenings.invasionDue)
  local events: { Event } = {}
  Invasions.Step(state, shallow, events)
  local one = assert(invasion(state), "no invasion in uncharted space")
  t.eq(one.system, shallow)
  t.ok(one.what ~= "great", "one in great force in uncharted space")
  -- Let be till its end: the tower's next raid is now.
  state.tick = one.ends
  Invasions.Step(state, 1, events)
  t.eq(invasion(state), nil)
  t.eq(starbase.raid, state.tick)
  state.starbases[planet] = nil
  State.RemoveId(state.starbaseIds, planet)
end)

suite:Case("at its worst one in great force stops the works of the stations in the next systems too", function(t)
  local _, state = away()
  -- (a system of the map with a neighbour that has a station with works)
  local events: { Event } = {}
  local at, next, station = 0, 0, 0
  for id = 1, Galaxy.Charted(state.galaxy) do
    if at ~= 0 then
      break
    end
    for _, other in state.galaxy.systems[id].neighbors do
      for _, object in Space.Describe(state, other).objects do
        if at == 0 and object.kind == "station" and state.starbases[object.id] == nil and Stations.Has(state, object.id, "industry") then
          at, next, station = id, other, object.id
        end
      end
    end
  end
  t.ok(station ~= 0, "no station next door to anywhere")
  local one = Happenings.Begin(state, Happenings.INVASION, "great", at, 0, Invasions.LASTS * 2 * HOUR, Invasions.GRADES.great.force, "",
    events)
  one.stage = 3
  t.ok(Stations.Out(state, station, "industry") ~= nil, "the next system's works are in use")
  -- (one of the fourth depth's stops its own system's alone)
  one.what = "deep"
  t.ok(next ~= at and Stations.Out(state, station, "industry") == nil)
end)

return suite
