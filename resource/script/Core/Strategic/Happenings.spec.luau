--!strict
-- What is going on in the galaxy (Strategic/Happenings): where pirates
-- mass and when, what is left behind, and what a pilot is told of it.

local Codec = require("@lt/Core/Persist/Codec")
local Commerce = require("@lt/Core/Strategic/Commerce")
local Constants = require("@lt/Core/Data/Constants")
local Core = require("@lt/Core/Api")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Happenings = require("@lt/Core/Strategic/Happenings")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Happenings")

type Event = { [string]: any }

local HOUR = math.floor(3600 / Constants.TICK + 0.5)
local DAY = 24 * HOUR

local function game40(peaceful: boolean?): (Core.Game, State.State)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, systems = 40, peaceful = peaceful })
  return game, game.state
end

-- Let 'hours' go by for the pressure alone (the clock, the pressure's
-- step, and what ends by the clock), without flying the rest of the game
-- through them: what began and what ended.
local function pass(state: State.State, hours: number): ({ Event }, { Event })
  local events: { Event } = {}
  local trade = Commerce.Carries(state.commerce, Galaxy.Charted(state.galaxy))
  for _ = 1, math.floor(hours * HOUR / Happenings.STEP) do
    state.tick += Happenings.STEP
    Happenings.Press(state, events, 1, trade)
    Happenings.Step(state, events)
  end
  local began, ended = {}, {}
  for _, event in events do
    if event.kind == "HappeningBegan" then
      table.insert(began, event)
    elseif event.kind == "HappeningEnded" then
      table.insert(ended, event)
    end
  end
  return began, ended
end

local function thin(state: State.State, band: string): number
  for id = 1, Galaxy.Charted(state.galaxy) do
    if Galaxy.Band(state.galaxy.systems[id].security) == band then
      return id
    end
  end
  error(`no system of {band} security`)
end

suite:Case("every system of thin order has a pressure, which comes to a surge sooner the thinner and the richer; several are on at once", function(t)
  local _, state = game40()
  local all = state.happenings
  local charted = Galaxy.Charted(state.galaxy)
  t.eq(#all.pressure, charted)
  for id = 1, charted do
    local secure = Galaxy.Band(state.galaxy.systems[id].security) == "secure"
    t.ok(all.pressure[id] >= 0 and all.pressure[id] < 1)
    t.ok(not secure or all.pressure[id] == 0, "where order is kept there is no pressure")
  end
  t.eq(#all.list, 0)
  -- Four days: surges begin, each where order is thin, and at some time more than one is on.
  local most, count = 0, 0
  local seen: { [number]: boolean } = {}
  for _ = 1, 4 * 24 do
    local began = pass(state, 1)
    for _, event in began do
      count += 1
      seen[event.system] = true
      t.eq(event.happening, Happenings.SURGE)
      t.ok(Galaxy.Band(state.galaxy.systems[event.system].security) ~= "secure", "a surge where order is kept")
      -- (a pilot hears of it from within a few jumps, and is told how many; from farther, not)
      local route = #Galaxy.Route(state.galaxy, 1, event.system) - 1
      t.eq(event.jumps, if route <= Happenings.HEARD then route else -1)
    end
    most = math.max(most, #all.list)
    for _, one in all.list do
      t.eq(all.pressure[one.system], 1, "a system pirates are massing in is at the top of its pressure")
    end
  end
  t.ok(count >= 6, `only {count} surges in four days in a galaxy of forty`)
  t.ok(most >= 2, "never more than one surge on at once")
  -- No two of them in the same system at once, and none where the last has only just been.
  for _, one in all.list do
    for _, other in all.list do
      t.ok(one.id == other.id or one.system ~= other.system)
    end
  end

  -- Thinner and richer, sooner: from nothing, a lawless system with twice the trade comes to one before a low one with half.
  local low, lawless = thin(state, "low"), thin(state, "lawless")
  local trade: { number } = table.create(charted, 1)
  trade[lawless], trade[low] = 2, 0.5
  all.pressure[low], all.pressure[lawless] = 0, 0
  local events: { Event } = {}
  for _ = 1, 60 do
    state.tick += Happenings.STEP
    Happenings.Press(state, events, 1, trade)
  end
  t.ok(all.pressure[lawless] > all.pressure[low] * 1.5, `lawless {all.pressure[lawless]}, low {all.pressure[low]}`)
end)

suite:Case("a surge that runs its time leaves order thinner for three days, and one that is broken leaves it firmer; then it is as it was", function(t)
  local game, state = game40()
  local all = state.happenings
  local system = thin(state, "low")
  local node = state.galaxy.systems[system]
  local was = Galaxy.Order(node)
  -- It runs its time.
  local surge = Happenings.Begin(state, Happenings.SURGE, "pirates", system, 0, 2 * HOUR, 1, "", game.events)
  all.pressure[system] = 1
  state.tick += 2 * HOUR
  local events: { Event } = {}
  Happenings.Step(state, events)
  t.eq({ events[1].kind, events[1].outcome, events[1].system } :: { any }, { "HappeningEnded", "over", system } :: { any })
  t.eq(Happenings.Get(state, surge.id), nil)
  t.eq(all.pressure[system], Happenings.SPENT)
  t.near(Galaxy.Order(node), was + Happenings.MARKS.surge, 1e-9)
  local left = Core.Query.Aftermath(game)
  t.eq({ #left, left[1].system, left[1].why } :: { any }, { 1, system, "a surge" } :: { any })
  t.near(left[1].delta, Happenings.MARKS.surge, 1e-9)
  t.near(left[1].left, Happenings.MARK_DAYS * 86400, 1)
  -- (a second mark does not go on top of the first)
  Happenings.Mark(state, system, -0.2, "another")
  t.eq(#all.marks, 1)
  -- Three days on it is put back, exactly.
  state.tick += Happenings.MARK_DAYS * DAY
  Happenings.Step(state, events)
  t.eq({ Galaxy.Order(node), #all.marks } :: { any }, { was, 0 } :: { any })

  -- Broken: enough pirates destroyed there ends it early, and the place is the better for it.
  surge = Happenings.Begin(state, Happenings.SURGE, "pirates", system, 0, 2 * HOUR, 1, "", game.events)
  all.pressure[system] = 1
  for _ = 1, Happenings.SURGE_BREAK do
    t.ok(Happenings.Fell(state, system))
  end
  events = {}
  Happenings.Step(state, events)
  t.eq({ events[1].outcome, events[1].kills } :: { any }, { "broken", Happenings.SURGE_BREAK } :: { any })
  t.eq(all.pressure[system], 0)
  t.near(Galaxy.Order(node), was + Happenings.MARKS.surgeBroken, 1e-9)
  -- (and if somebody else changes its order meanwhile, theirs stands)
  node.order = 0.4
  state.tick += Happenings.MARK_DAYS * DAY
  Happenings.Step(state, events)
  t.eq({ Galaxy.Order(node), #all.marks } :: { any }, { 0.4, 0 } :: { any })

  -- A pirate destroyed where no surge is lets the pressure down a little, and that is all.
  all.pressure[system] = 0.5
  t.ok(not Happenings.Fell(state, system))
  t.near(all.pressure[system], 0.5 - Happenings.RELIEF, 1e-9)
  -- And a system the pilot's corporation keeps order in is left as it is.
  node.owner = "player"
  Happenings.Mark(state, system, -0.1, "a surge")
  t.eq(#all.marks, 0)
end)

suite:Case("what is going on is told nearest first, with how far and how long; the nearest surge is the surge a pilot is told of", function(t)
  local game, state = game40()
  t.eq(#Core.Query.Happenings(game), 0)
  t.eq(Core.Query.Surge(game), nil)
  -- Three, at three distances: one where the pilot is, one a way off, one out of all reach (uncharted).
  local far, most = 1, 0
  for id = 1, Galaxy.Charted(state.galaxy) do
    local jumps = #Galaxy.Route(state.galaxy, 1, id) - 1
    if jumps > most then
      far, most = id, jumps
    end
  end
  local nowhere = Galaxy.Charted(state.galaxy) + 1
  Happenings.Begin(state, Happenings.SURGE, "pirates", far, 0, 2 * HOUR, 1, "", game.events)
  Happenings.Begin(state, Happenings.SIGHTING, "captain", nowhere, 0, HOUR, 1, "Somebody", game.events)
  Happenings.Begin(state, Happenings.WINDFALL, "belt", 1, 0, 3 * HOUR, 1, "", game.events)
  local told = Core.Query.Happenings(game)
  t.eq(#told, 3)
  t.eq({ told[1].kind, told[1].jumps, told[1].here, told[1].where } :: { any },
    { Happenings.WINDFALL, 0, true, state.galaxy.systems[1].name } :: { any })
  t.eq({ told[2].kind, told[2].jumps, told[2].here } :: { any }, { Happenings.SURGE, most, false } :: { any })
  t.near(told[2].left, 2 * 3600, 1)
  t.eq({ told[3].kind, told[3].jumps, told[3].name } :: { any }, { Happenings.SIGHTING, -1, "Somebody" } :: { any })
  local surge = assert(Core.Query.Surge(game))
  t.eq({ surge.system, surge.jumps } :: { any }, { far, most } :: { any })
end)

suite:Case("a game with no pirates has no surges; what is going on is in the save; and a save from before opens with its one surge on the list", function(t)
  local _, quiet = game40(true)
  local began = pass(quiet, 5 * 24)
  t.eq({ #began, #quiet.happenings.list }, { 0, 0 })

  local game, state = game40()
  pass(state, 3 * 24)
  t.ok(#state.happenings.list + #state.happenings.marks > 0, "nothing had happened in three days")
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.eq(#loaded.state.happenings.list, #state.happenings.list)
  -- A save of the last version, with one surge the old way.
  local file = Codec.Decode(data, length)
  file.saveVersion = 81
  file.state.happenings = nil
  file.state.surge = { system = 7, ends = file.state.tick + 500, next = 0, kills = 3, count = 4 }
  local old, oldLength = Codec.Encode(file)
  local opened = Core.Load(old, oldLength).state
  local list = opened.happenings.list
  t.eq({ #list, list[1].kind, list[1].system, list[1].kills, list[1].ends - opened.tick } :: { any },
    { 1, Happenings.SURGE, 7, 3, 500 } :: { any })
  t.eq(#opened.happenings.pressure, Galaxy.Charted(opened.galaxy))
  t.eq((opened :: any).surge, nil)
end)

suite:Case("a ship sent somewhere goes round a surge or an invasion where there is a way round, and through it where there is none", function(t)
  -- (the world events' rulings left the ships the pilot sends ignoring
  -- them; on the owner's list, 2026-11-16)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true, systems = 40 })
  local state = game.state
  local galaxy = state.galaxy
  local round, through = 0, 0
  for from = 1, math.min(30, Galaxy.Charted(galaxy)) do
    for to = from + 1, math.min(30, Galaxy.Charted(galaxy)) do
      local plain = Galaxy.Route(galaxy, from, to)
      if #plain >= 3 then
        local middle = plain[2]
        local way = Galaxy.Route(galaxy, from, to, false, nil, { [middle] = true })
        t.eq({ way[1], way[#way] }, { from, to }, "the ends are never gone round")
        if table.find(way, middle) then
          through += 1
        else
          round += 1
          t.ok(#way - #plain <= Galaxy.AVOID, "a way round no longer than the danger is dear")
        end
      end
    end
  end
  t.ok(round > 0, "no way round anything")
  -- (and Happenings.Way reads the surges and invasions going on)
  local plain = Galaxy.Route(galaxy, 1, 2)
  if #plain >= 3 then
    Happenings.Begin(state, Happenings.SURGE, "pirates", plain[2], 0, 3600, 10, "", {})
    local way = Happenings.Way(state, 1, 2)
    t.ok(#way > 0)
    t.eq(Happenings.Danger(state)[plain[2]], true)
  end
  local _ = through
end)

return suite
