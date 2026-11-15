--!strict
-- Luck, good and bad, that happens to places (Tactical/Mishaps).

local Constants = require("@lt/Core/Data/Constants")
local Core = require("@lt/Core/Api")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Happenings = require("@lt/Core/Strategic/Happenings")
local Mishaps = require("@lt/Core/Tactical/Mishaps")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Stations = require("@lt/Core/Assets/Stations")
local Structures = require("@lt/Core/Data/Structures")
local System = require("@lt/Core/Describe/System")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Mishaps")

type Event = { [string]: any }

local HOUR = math.floor(3600 / Constants.TICK + 0.5)

local function game40(): (Core.Game, State.State)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, systems = 40, peaceful = true })
  return game, game.state
end

suite:Case("now and then something happens to a place within reach: works out of use, a gate closed that there is a way round, a rich belt", function(t)
  local _, state = game40()
  local all = state.happenings
  local events: { Event } = {}
  local kinds: { [string]: number } = {}
  local most = 0
  -- (by the ten minutes, for twelve days, with nobody going anywhere)
  for _ = 1, 12 * 24 * 6 do
    state.tick += 600
    Mishaps.Step(state, 1, events)
    local on = 0
    for _, one in all.list do
      on += if one.kind == Happenings.DISASTER or one.kind == Happenings.WINDFALL then 1 else 0
      if one.kind == Happenings.DISASTER and one.what == "gate" then
        local b = assert(one.ref)
        t.ok(#state.galaxy.systems[one.system].neighbors >= 2 and #state.galaxy.systems[b].neighbors >= 2,
          "a gate closed at a system with no other")
        -- (there is a way round it, which a route takes)
        local way = Galaxy.Route(state.galaxy, one.system, b, false, Mishaps.Closed(state))
        t.ok(#way > 2, "no way round a closed gate")
        -- (and the economy's lane along it carries nothing meanwhile)
        for _, edge in state.commerce.edges do
          if (edge.a == one.system and edge.b == b) or (edge.a == b and edge.b == one.system) then
            t.ok(not edge.open, "the lane of a closed gate is open")
          end
        end
      end
    end
    most = math.max(most, on)
  end
  local far = Happenings.Reach(state, 1, Mishaps.REACH)
  for _, event in events do
    if event.kind == "HappeningBegan" then
      local kind = if event.happening == Happenings.WINDFALL then "belt" elseif event.what == "gate" then "gate" else "outage"
      kinds[kind] = (kinds[kind] or 0) + 1
      t.ok(far[event.system] ~= nil, "something out of reach of the pilot")
    end
  end
  t.ok((kinds.outage or 0) > 0 and (kinds.gate or 0) > 0 and (kinds.belt or 0) > 0,
    `outages {kinds.outage or 0}, gates {kinds.gate or 0}, belts {kinds.belt or 0}`)
  t.ok(most <= Mishaps.MOST and most >= 2, `{most} on at once at the most`)
end)

suite:Case("works out of use: what the station does there cannot be done until it is mended, and the rest of it can", function(t)
  local game, state = game40()
  local home = state.player.home
  local station = assert(Space.Object(state, home))
  t.ok(Stations.Has(state, home, "refining") and Stations.Has(state, home, "industry"))
  local refuse: State.Command = { kind = "Reprocess", actor = state.player.ship, item = 0, quantity = 1 }
  t.ok((Stations.Validate(state, refuse)))
  local one = Happenings.Begin(state, Happenings.DISASTER, "refining", 1, home, 12 * HOUR, 1,
    `The {Structures.Provider("refining")} at {station.name}`, game.events)
  t.ok(not Stations.Has(state, home, "refining"), "a refinery that is out of use should refuse")
  t.ok(Stations.Has(state, home, "industry") and Stations.Has(state, home, "market") and Stations.Has(state, home, "fitting"))
  t.near(assert(Stations.Out(state, home, "refining")), 12 * 3600, 1)
  local ok, why = Stations.Validate(state, refuse)
  t.ok(not ok and string.find(why or "", "out of use", 1, true) ~= nil, tostring(why))
  local services = Stations.Services(state, home)
  t.eq(table.find(services, "refining"), nil)
  -- Mended when its time is up.
  state.tick = one.ends
  Mishaps.Step(state, 1, game.events)
  t.eq(Happenings.Get(state, one.id), nil)
  t.ok(Stations.Has(state, home, "refining"))
end)

suite:Case("a closed gate: nothing jumps through it either way, a route goes round, its lane carries nothing, and it opens in its time", function(t)
  local game, state = game40()
  -- (a gate of the pilot's own system that there is a way round)
  local a, b = 1, 0
  for _, neighbor in state.galaxy.systems[a].neighbors do
    if b == 0 and #state.galaxy.systems[neighbor].neighbors >= 2 and #Galaxy.Route(state.galaxy, a, neighbor, false,
      { [a * (#state.galaxy.systems + 1) + neighbor] = true, [neighbor * (#state.galaxy.systems + 1) + a] = true }) > 2 then
      b = neighbor
    end
  end
  assert(b ~= 0, "the first system has no gate there is a way round")
  t.ok(Core.Submit(game, { kind = "Undock", actor = state.player.ship }))
  Core.Step(game)
  local gate: System.Object? = nil
  for _, object in Space.Describe(state, a).objects do
    if object.kind == "gate" and object.to == b then
      gate = object
    end
  end
  local through: State.Command = { kind = "Jump", actor = state.player.ship, target = assert(gate).id }
  t.ok((Core.Validate(game, through)))
  local function open(): boolean
    for _, edge in state.commerce.edges do
      if (edge.a == a and edge.b == b) or (edge.a == b and edge.b == a) then
        return edge.open
      end
    end
    error("the two systems have no lane")
  end
  t.ok(open())
  -- Closed, by the module's own doing: asked for until one comes of this gate is too long, so it is begun as it would be.
  local one = Happenings.Begin(state, Happenings.DISASTER, "gate", a, 0, 3 * HOUR, 1, state.galaxy.systems[b].name, game.events)
  one.ref = b
  t.ok(Mishaps.Shut(state, a, b) and Mishaps.Shut(state, b, a) and not Mishaps.Shut(state, a, a))
  t.eq({ Core.Validate(game, through) } :: { any }, { false, "the gate is closed for repairs" } :: { any })
  local way = Galaxy.Route(state.galaxy, a, b, false, Core.Query.Closed(game))
  t.ok(#way > 2, "a route should go round a closed gate")
  t.eq(#Galaxy.Route(state.galaxy, a, b), 2)
  -- It opens in its time.
  state.tick = one.ends
  Mishaps.Step(state, a, game.events)
  t.ok(not Mishaps.Shut(state, a, b))
  t.ok((Core.Validate(game, through)))
  t.eq(Core.Query.Closed(game), nil)
  t.ok(open())
end)

suite:Case("a rich belt: a place with rocks of a rare ore when the pilot is in its system, and gone when its time is", function(t)
  local game, state = game40()
  local one = Happenings.Begin(state, Happenings.WINDFALL, "belt", 1, 0, 20 * HOUR, 1, "", game.events)
  -- Somewhere else, nothing is put anywhere.
  Mishaps.Step(state, 2, game.events)
  t.eq(one.place, 0)
  Mishaps.Step(state, 1, game.events)
  t.ok(one.place ~= 0, "the belt was not put there")
  local place = assert(Space.Object(state, one.place))
  t.ok(string.find(place.name, "Rich Belt", 1, true) ~= nil, place.name)
  local rocks = 0
  for _, object in Space.Describe(state, 1).objects do
    if object.kind == "asteroid" and object.site == one.place then
      rocks += 1
      t.ok(Space.Distance(object :: any, place :: any) < 9000)
    end
  end
  t.eq(rocks, 2 * Mishaps.ROCKS)
  -- (it is not put there twice)
  Mishaps.Step(state, 1, game.events)
  local again = 0
  for _, object in Space.Describe(state, 1).objects do
    again += if object.kind == "asteroid" and object.site == one.place then 1 else 0
  end
  t.eq(again, rocks)
  state.tick = one.ends
  Mishaps.Step(state, 1, game.events)
  t.eq(Happenings.Get(state, one.id), nil)
  t.ok(state.sites[one.place].gone)
end)

return suite
