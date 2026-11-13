--!strict
-- Work a station has for a pilot (Assets/Missions).

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Assault = require("@lt/Core/Tactical/Assault")
local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Mining = require("@lt/Core/Tactical/Mining")
local Missions = require("@lt/Core/Assets/Missions")
local Ores = require("@lt/Core/Data/Ores")
local Ships = require("@lt/Core/Data/Ships")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Sites = require("@lt/Core/Tactical/Sites")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")
local Types = require("@lt/Core/Data/Types")

local suite = Test.Suite("Missions")

local function newGame(historySeed: number?): Core.Game
  return Core.New({ galaxySeed = 1, historySeed = historySeed or 1, peaceful = true })
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

-- A game whose starter station offers a job of a kind today, that job
-- taken: the game and the mission. (Which seed offers what is looked for.)
local function taken(t: Test.Context, kind: string): (Core.Game, State.Mission)
  for seed = 1, 40 do
    local game = newGame(seed)
    for _, offer in Missions.Offers(game.state, game.state.player.home) do
      if offer.kind == kind then
        t.ok((submit(game, { kind = "AcceptMission", actor = 0, what = offer.key })))
        return game, game.state.missions[game.state.missionIds[1]]
      end
    end
  end
  error(`no history seed up to 40 offers a {kind} job at the starter station`)
end

suite:Case("a station offers three jobs a day, the same however often it is asked, and a pilot's own offers none", function(t)
  local kinds: { [string]: number } = {}
  for seed = 1, 12 do
    local game = newGame(seed)
    local state = game.state
    local every = Missions.Offers(state, state.player.home)
    t.eq(Missions.Offers(state, state.player.home), every)
    -- (the day's three: the fourth agent's assaults, the fifth's mining contracts and the sixth's courier contracts
    -- are their own cases)
    local offers: { State.Mission } = {}
    for _, offer in every do
      if offer.level == 0 then
        table.insert(offers, offer)
      end
    end
    -- (and the seventh's defence jobs)
    t.eq({ #offers, #every }, { Missions.OFFERS, Missions.OFFERS + 4 })
    for _, offer in offers do
      kinds[offer.kind] = (kinds[offer.kind] or 0) + 1
      t.ok(offer.reward > 0 and offer.need > 0 and offer.standing > 0, `{Missions.Title(offer)} pays {offer.reward}`)
      t.eq({ offer.id, offer.done, offer.station, offer.faction } :: { any }, { 0, 0, state.player.home, "vessari" } :: { any })
      if offer.kind == "courier" then
        local to = assert(Space.Object(state, offer.to))
        t.ok(to.kind == "station" and to.id ~= offer.station, "a courier run goes to another station")
        t.ok(offer.need <= 130, "a courier's cargo should go in a frigate's hold")
      elseif offer.kind == "supply" then
        t.ok(offer.reward > offer.need * Types.Info(offer.type).basePrice, "a supply order should pay more than the goods are worth")
      else
        t.ok(table.find(state.galaxy.systems[1].neighbors, offer.system) ~= nil or offer.system == 1)
      end
    end
    -- Tomorrow's are others.
    state.tick += 86400
    local tomorrow = Missions.Offers(state, state.player.home)
    t.ok(tomorrow[1].key ~= offers[1].key)
  end
  t.ok((kinds.bounty or 0) > 3 and (kinds.courier or 0) > 3 and (kinds.supply or 0) > 3, "a kind of job is hardly ever offered")
  t.eq(#Missions.Offers(newGame().state, 99999), 0)
  t.eq(#Core.Query.Missions(newGame()).offers, 7)
end)

suite:Case("a job is taken at its station, once, and a pilot has five in hand at most", function(t)
  local game = newGame()
  local state = game.state
  local offers = Missions.Offers(state, state.player.home)
  t.eq(refused(game, { kind = "AcceptMission", actor = 0, what = "nothing" }), "no such job is offered here")
  t.ok((submit(game, { kind = "AcceptMission", actor = 0, what = offers[1].key })))
  t.eq(#state.missionIds, 1)
  local mine = state.missions[state.missionIds[1]]
  t.ok(mine.id ~= 0)
  t.eq(mine.key, offers[1].key)
  t.eq(#Missions.Offers(state, state.player.home), #offers - 1)
  t.eq(refused(game, { kind = "AcceptMission", actor = 0, what = offers[1].key }), "no such job is offered here")
  -- Five in hand, and no more.
  for extra = 1, 4 do
    state.missions[1000 + extra] = table.clone(mine)
    state.missions[1000 + extra].id = 1000 + extra
    table.insert(state.missionIds, 1000 + extra)
  end
  t.eq(refused(game, { kind = "AcceptMission", actor = 0, what = offers[2].key }), "a pilot has 5 jobs in hand at most")
  -- Not from space.
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  t.eq(refused(game, { kind = "AcceptMission", actor = 0, what = offers[2].key }), "not docked")
end)

suite:Case("a bounty job counts the pirates the pilot destroys in its system, and pays at its station", function(t)
  local game, mission = taken(t, "bounty")
  local state = game.state
  t.eq(refused(game, { kind = "CompleteMission", actor = 0, target = mission.id }), `{mission.need} still to destroy`)
  -- Kills elsewhere, and by somebody else, do not count.
  local elsewhere = Pirates.Spawn(state, Pirates.SCOUT, mission.system % 3 + 1, 1e9, 0, 0, 0)
  Aftermath.Destroy(state, elsewhere.id, state.player.ship, game.events)
  local another = Pirates.Spawn(state, Pirates.SCOUT, mission.system, 1e9, 0, 0, 0)
  Aftermath.Destroy(state, another.id, 0, game.events)
  t.eq(mission.done, 0)
  for _ = 1, mission.need + 1 do
    local scout = Pirates.Spawn(state, Pirates.SCOUT, mission.system, 1e9, 0, 0, 0)
    Aftermath.Destroy(state, scout.id, state.player.ship, game.events)
  end
  t.eq(mission.done, mission.need)
  local wallet = state.wallet
  -- (the pirates destroyed have earned a little standing already)
  local thought = Missions.Standing(state, "vessari")
  t.ok((submit(game, { kind = "CompleteMission", actor = 0, target = mission.id })))
  t.eq(state.wallet - wallet, mission.reward)
  t.eq(#state.missionIds, 0)
  t.near(Missions.Standing(state, "vessari") - thought, mission.standing, 1e-9)
  t.eq(state.missionsDone, 1)
  -- (standing makes the next job pay better)
  state.tick += 86400
  local plain = newGame(state.historySeed)
  plain.state.tick = state.tick
  local now, before = Missions.Offers(state, state.player.home), Missions.Offers(plain.state, plain.state.player.home)
  t.ok(now[1].reward >= before[1].reward)
  state.standings.vessari = 10
  t.ok(Missions.Offers(state, state.player.home)[1].reward > before[1].reward * 1.25)
end)

suite:Case("a courier job gives sealed cargo to carry, and pays where it is delivered", function(t)
  local game, mission = taken(t, "courier")
  local state = game.state
  local ship = state.ships[state.player.ship]
  local crate = nil
  for _, item in Items.In(state, state.player.home, "hangar") do
    if item.type == Missions.CRATE then
      crate = item
    end
  end
  t.eq(assert(crate, "the cargo was not put in the hangar").quantity, mission.need)
  t.eq(mission.type, Missions.CRATE)
  local to = assert(Space.Object(state, mission.to))
  t.eq(refused(game, { kind = "CompleteMission", actor = 0, target = mission.id }), `finish it at {to.name}`)
  -- Into the hold, and (the flight is Space's to test) to where it is going.
  t.ok((submit(game, { kind = "MoveItems", actor = 0, item = (crate :: State.Item).id, to = "cargo" })))
  ship.docked = mission.to
  -- With some of it missing it is not done.
  local held = Items.In(state, ship.id, "cargo")[1]
  Items.Take(state, held, 5)
  t.eq(refused(game, { kind = "CompleteMission", actor = 0, target = mission.id }), "5 more to bring")
  Items.Add(state, Missions.CRATE, 5, mission.to, "hangar")
  local wallet = state.wallet
  t.ok((submit(game, { kind = "CompleteMission", actor = 0, target = mission.id })))
  t.eq(state.wallet - wallet, mission.reward)
  t.eq(#Items.In(state, ship.id, "cargo"), 0)
  for _, item in Items.In(state, mission.to, "hangar") do
    t.ok(item.type ~= Missions.CRATE, "the cargo was not taken")
  end
end)

suite:Case("a supply order takes what it asked for from the hangar, and no more", function(t)
  local game, mission = taken(t, "supply")
  local state = game.state
  t.eq(refused(game, { kind = "CompleteMission", actor = 0, target = mission.id }), `{mission.need} more to bring`)
  Items.Add(state, mission.type, mission.need + 70, state.player.home, "hangar")
  local wallet = state.wallet
  t.ok((submit(game, { kind = "CompleteMission", actor = 0, target = mission.id })))
  t.eq(state.wallet - wallet, mission.reward)
  local left = 0
  for _, item in Items.In(state, state.player.home, "hangar") do
    left += if item.type == mission.type then item.quantity else 0
  end
  t.eq(left, 70)
end)

suite:Case("a job abandoned costs standing, and jobs are in the save", function(t)
  local game, mission = taken(t, "bounty")
  local state = game.state
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.eq(Core.Query.Missions(loaded).inHand[1].title, Missions.Title(mission))
  t.ok((submit(game, { kind = "AbandonMission", actor = 0, target = mission.id })))
  t.eq(#state.missionIds, 0)
  t.near(Missions.Standing(state, "vessari"), -2 * mission.standing, 1e-9)
  t.eq(refused(game, { kind = "AbandonMission", actor = 0, target = mission.id }), "no such job in hand")
  -- A save from before there were jobs opens with none, at no standing.
  local file = Codec.Decode(data, length)
  file.saveVersion = 17
  for _, name in { "missions", "missionIds", "missionsTaken", "missionsDone", "standings" } do
    file.state[name] = nil
  end
  local old, oldLength = Codec.Encode(file)
  local before = Core.Load(old, oldLength)
  t.eq({ #before.state.missionIds, before.state.missionsDone, Missions.Standing(before.state, "vessari") }, { 0, 0, 0 })
  t.eq(#Core.Query.Missions(before).offers, 7)
end)

-- The assaults a station offers, by level.
local function assaults(game: Core.Game, station: number): { State.Mission }
  local found: { State.Mission } = {}
  for _, offer in Missions.Offers(game.state, station) do
    -- (the fourth agent's: a defence job, the seventh's, is an assault only to the rules)
    if Missions.Line(offer) == "assault" then
      table.insert(found, offer)
    end
  end
  return found
end

-- A game in which the home station's assault of a level is on a camp in
-- its own system, to do a thing there ("clear" it, if not said), of so
-- many rooms (any number, if not said), that job taken: the game and
-- the job.
local function camp(level: number, aim: string?, rooms: number?): (Core.Game, State.Mission)
  for seed = 1, 200 do
    local game = newGame(seed)
    local state = game.state
    state.standings.vessari = Assault.STANDING[level]
    local offer = assaults(game, state.player.home)[level]
    if offer and offer.system == 1 and offer.aim == (aim or "clear") and (rooms == nil or #offer.ends == rooms) then
      assert(submit(game, { kind = "AcceptMission", actor = 0, what = offer.key }))
      return game, state.missions[state.missionIds[1]]
    end
  end
  error(`no history seed up to 200 has a level {level} camp like that in the home system`)
end

-- The ships that keep a place, in the order they came.
local function keepers(game: Core.Game, site: number): { number }
  local found: { number } = {}
  for _, id in game.state.pilotIds do
    if game.state.pilots[id].home == site and game.state.balls[id] then
      table.insert(found, id)
    end
  end
  return found
end

-- Put the pilot's ship at a place, at rest.
local function at(game: Core.Game, id: number)
  local state = game.state
  local place = assert(Space.Object(state, id))
  local ball = state.balls[state.player.ship]
  ball.x, ball.y, ball.z = place.x + 500, place.y, place.z
  ball.vx, ball.vy, ball.vz = 0, 0, 0
  Space.AssignGrid(state, ball)
  assert(ball.grid == id, "a camp should be a grid of its own")
end

local function steps(game: Core.Game, count: number)
  for _ = 1, count do
    Core.Step(game)
  end
end

suite:Case("the fourth agent has an assault on a pirate camp, at each level the pilot's standing opens", function(t)
  local game = newGame()
  local state = game.state
  local home = state.player.home
  -- One level for a pilot nobody knows, and another at a standing of 1, of 3 and of 5. None for one they think ill of.
  for _, case in { { -3, 0 }, { -2, 1 }, { 0, 1 }, { 0.9, 1 }, { 1, 2 }, { 3, 3 }, { 5, 4 }, { 10, 4 } } do
    state.standings.vessari = case[1]
    t.eq(#assaults(game, home), case[2], `at a standing of {case[1]}`)
    t.eq(Assault.Top(case[1]), case[2])
  end
  state.standings.vessari = 5
  local offers = assaults(game, home)
  t.eq(assaults(game, home), offers, "the same however often it is asked")
  local last = 0
  for level, offer in offers do
    t.eq({ offer.kind, offer.level, offer.id, offer.done, offer.wave, offer.site, offer.station, offer.faction } :: { any },
      { "assault", level, 0, 0, 0, 0, home, "vessari" } :: { any })
    t.eq(offer.agent, Missions.Agent(state, home, 4), "an assault is the fourth agent's")
    t.ok(offer.system == 1 or table.find(state.galaxy.systems[1].neighbors, offer.system) ~= nil)
    -- Its waves: as many as its level has, no two alike, of that level's packs; and it counts their ships.
    t.eq(#offer.waves, Assault.WAVES[level])
    local ships, bounty = 0, 0
    for index, wave in offer.waves do
      local known = false
      for _, pack in Assault.PACKS[level] do
        known = known or table.concat(pack, ",") == table.concat(wave, ",")
      end
      t.ok(known, `a wave of level {level} is {table.concat(wave, ",")}`)
      for other = 1, index - 1 do
        t.ok(table.concat(offer.waves[other], ",") ~= table.concat(wave, ","), "a camp has the same wave twice")
      end
      for _, kind in wave do
        ships += 1
        bounty += Pirates.kindById[kind].bounty
      end
    end
    -- What it counts is what it is to do: the camp's ships, what it is built of, its one chief, or the crates to bring back.
    t.ok(table.find(Assault.AIMS, offer.aim) ~= nil, `an assault to "{offer.aim}"`)
    t.eq({ offer.need, offer.type } :: { any },
      if offer.aim == "chief" then { 1, "" } :: { any } elseif offer.aim == "fetch" then { 10 * level, "cargo.stolen" } :: { any }
        elseif offer.aim == "raze" then { #Assault.WORKS[level], "" } :: { any } else { ships, "" } :: { any })
    -- Its rooms: as many as its level may have, each with a wave at least, the last wave in the last.
    t.ok(#offer.ends >= 1 and #offer.ends <= Assault.ROOMS[level] and offer.ends[#offer.ends] == #offer.waves)
    for index = 2, #offer.ends do
      t.ok(offer.ends[index] > offer.ends[index - 1])
    end
    t.eq({ #offer.rooms, offer.mark }, { 0, 0 })
    -- It pays six tenths of the bounties on them (and on what the camp is built of, where that is the job)
    -- and five thousand a level, and what the pilot's standing adds.
    if offer.aim == "raze" then
      for _, kind in Assault.WORKS[level] do
        bounty += Pirates.kindById[kind].bounty
      end
    end
    t.eq(offer.reward, math.floor((math.floor(0.6 * bounty) + 5000 * level) * (1 + 0.03 * 5)))
    t.near(offer.standing, 0.15 * level, 1e-9)
    t.eq(offer.loyalty, offer.reward // Missions.LOYALTY)
    t.ok(offer.reward > last, "a harder camp should pay more")
    last = offer.reward
    t.eq(Missions.Title(offer), `Assault, level {level}: ` .. (if offer.aim == "chief" then "the chief of a camp"
      elseif offer.aim == "fetch" then `{offer.need} crates a camp took`
      elseif offer.aim == "raze" then (if offer.need == 1 then "a camp's store" else `a camp's {offer.need} works`)
      else `a camp of {ships}`))
  end
  -- One from a station at a time: taking one takes the others off the list, and the agent's next is another job.
  t.ok((submit(game, { kind = "AcceptMission", actor = 0, what = offers[2].key })))
  t.eq({ #assaults(game, home), state.assaults[home] }, { 0, 1 })
  -- (and the one courier contract a galaxy of three systems has room for, and the four defence jobs)
  t.eq(#Missions.Offers(state, home), Missions.OFFERS + 4 + 1 + 4, "the day's three are still offered, and the mining contracts")
  local mine = state.missions[state.missionIds[1]]
  t.ok((submit(game, { kind = "AbandonMission", actor = 0, target = mine.id })))
  -- (giving it up cost standing: put that back, to see all four again)
  state.standings.vessari = 5
  local again = assaults(game, home)
  t.eq(#again, 4)
  t.ok(again[2].key ~= offers[2].key)
end)

suite:Case("taking an assault puts its camp on the charts: a place of its own, found already, that is not one of the system's sites", function(t)
  local game, mission = camp(1, "clear", 1)
  local state = game.state
  local site = assert(state.sites[mission.site], "the job has no camp")
  local place = assert(Space.Object(state, site.id))
  t.eq({ site.kind, site.system, site.strength, site.gone, place.kind, place.variety, string.sub(place.name, 1, 11) } :: { any },
    { "mission", 1, 1, false, "belt", "site.mission", "Pirate Camp" } :: { any })
  t.eq(Sites.Hidden(state, site.id), false)
  -- Nobody is there until the pilot is.
  t.eq(#keepers(game, site.id), 0)
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  local shown = false
  for _, entry in Core.Query.Overview(game) do
    shown = shown or (entry.id == site.id and entry.kind == "site" and entry.variety == "site.mission")
  end
  t.ok(shown, "the camp is not on the overview")
  -- The system's own sites come and go as they did, and the camp is not counted among them or taken away.
  steps(game, 2 * Sites.CHECK + 5)
  local own = 0
  for _, other in Sites.In(state, 1) do
    own += if other.kind == "mission" then 0 else 1
  end
  t.eq({ own, site.gone } :: { any }, { Sites.COUNT.secure, false } :: { any })
  t.eq(#keepers(game, site.id), 0, "somebody came to a camp nobody is at")
end)

suite:Case("at the camp its keepers come in waves, each a little after the last is destroyed, and the last one down finishes the job", function(t)
  local game, mission = camp(1, "clear", 1)
  local state = game.state
  local home = state.player.home
  local wallet, credit = state.wallet, Missions.Standing(state, "vessari")
  t.eq(refused(game, { kind = "CompleteMission", actor = 0, target = mission.id }), `{mission.need} still to destroy`)
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  at(game, mission.site)
  Core.TakeEvents(game)
  steps(game, 2)
  -- The first wave is there at once, and is the camp's own: nothing else comes.
  local first = keepers(game, mission.site)
  t.eq({ #first, mission.wave, mission.done }, { #mission.waves[1], 1, 0 })
  local told = false
  for _, event in Core.TakeEvents(game) do
    told = told or (event.kind == "PiratesArrived" and event.wave == 1 and event.of == #mission.waves and event.count == #first)
  end
  t.ok(told, "nobody said the first wave had come")
  for index, id in first do
    t.eq(state.ships[id].type, Pirates.kindById[mission.waves[1][index]].hull)
  end
  steps(game, 60)
  t.eq(#keepers(game, mission.site), #first, "a second pack came while the first was there")
  -- They stay, however long the pilot is away.
  local me = state.balls[state.player.ship]
  me.x += 5e7
  Space.AssignGrid(state, me)
  steps(game, 400)
  t.eq(#keepers(game, mission.site), #first, "the camp's keepers left it")
  at(game, mission.site)
  -- One down, and the rest: each counts; with the last the next wave is due, after a breather.
  local bounties = 0
  for index, id in first do
    bounties += state.pilots[id].bounty
    Aftermath.Destroy(state, id, state.player.ship, game.events)
    t.eq(mission.done, index)
  end
  t.eq(state.wallet - wallet, bounties, "each of them pays its own bounty")
  local down = false
  for _, event in Core.TakeEvents(game) do
    down = down or (event.kind == "WaveDown" and event.wave == 1)
    t.ok(event.kind ~= "AssaultCleared", "the camp was called cleared with a wave to come")
  end
  t.ok(down, "nobody said the wave was down")
  steps(game, Assault.BREATHER - 5)
  t.eq({ #keepers(game, mission.site), mission.wave }, { 0, 1 })
  steps(game, 10)
  local second = keepers(game, mission.site)
  t.eq({ #second, mission.wave }, { #mission.waves[2], 2 })
  -- The last of the last wave: the job is done, and nobody else comes.
  for _, id in second do
    Aftermath.Destroy(state, id, state.player.ship, game.events)
  end
  t.eq(mission.done, mission.need)
  local cleared = false
  for _, event in Core.TakeEvents(game) do
    cleared = cleared or (event.kind == "AssaultCleared" and event.mission == mission.id and event.station == home)
  end
  t.ok(cleared, "nobody said the camp was cleared")
  steps(game, 80)
  t.eq(#keepers(game, mission.site), 0)
  -- Paid at the station that gave it: the reward, the standing, the loyalty points; and the camp is off the charts.
  t.eq(refused(game, { kind = "CompleteMission", actor = 0, target = mission.id }), "not docked")
  t.ok((submit(game, { kind = "Dock", actor = 0, target = home })))
  for _ = 1, 1500 do
    if state.ships[state.player.ship].docked == home then
      break
    end
    Core.Step(game)
  end
  local before = state.wallet
  -- (the pirates destroyed were to the pilot's credit already: what the job adds is its own)
  t.ok(Missions.Standing(state, "vessari") > credit)
  credit = Missions.Standing(state, "vessari")
  t.ok((submit(game, { kind = "CompleteMission", actor = 0, target = mission.id })))
  t.eq(state.wallet - before, mission.reward)
  t.near(Missions.Standing(state, "vessari") - credit, 0.15, 1e-6)
  t.eq(state.loyalty.vessari, mission.loyalty)
  t.eq({ state.sites[mission.site].gone, Sites.Hidden(state, mission.site), #state.missionIds } :: { any }, { true, true, 0 } :: { any })
  -- And the agent has another.
  t.eq(#assaults(game, home), 1)
end)

suite:Case("an assault given up takes its camp and whoever is in it; it is in the save, and an older save has none", function(t)
  local game, mission = camp(2, "clear", 1)
  local state = game.state
  local home = state.player.home
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  at(game, mission.site)
  steps(game, 2)
  t.eq(#keepers(game, mission.site), #mission.waves[1])
  -- In the save, with the wave out.
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  steps(game, 30)
  steps(loaded, 30)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  -- (a pilot in a capsule is not sent a wave)
  -- Given up, from the station: the camp goes, and its keepers, and it costs twice what it was worth.
  local ball = state.balls[state.player.ship]
  local station = assert(Space.Object(state, home))
  ball.x, ball.y, ball.z = station.x + station.radius + 500, station.y, station.z
  Space.AssignGrid(state, ball)
  t.ok((submit(game, { kind = "Dock", actor = 0, target = home })))
  for _ = 1, 600 do
    if state.ships[state.player.ship].docked == home then
      break
    end
    Core.Step(game)
  end
  local credit = Missions.Standing(state, "vessari")
  t.ok((submit(game, { kind = "AbandonMission", actor = 0, target = mission.id })))
  t.eq({ #keepers(game, mission.site), state.sites[mission.site].gone } :: { any }, { 0, true } :: { any })
  t.near(credit - Missions.Standing(state, "vessari"), 0.6, 1e-6)
  for _, id in state.pilotIds do
    t.ok(state.pilots[id].home ~= mission.site, "one of the camp's keepers is still about")
  end
  -- A save from before there were assaults: its jobs are none of them one, and no agent has given any.
  local plain = newGame()
  local offer = Missions.Offers(plain.state, plain.state.player.home)[1]
  t.ok((submit(plain, { kind = "AcceptMission", actor = 0, what = offer.key })))
  local now, nowLength = Core.Save(plain)
  local file = Codec.Decode(now, nowLength)
  file.saveVersion = 36
  file.state.assaults = nil
  for _, each in file.state.missions do
    each.level, each.waves, each.wave, each.site = nil, nil, nil, nil
  end
  local old, oldLength = Codec.Encode(file)
  t.eq(Core.Hash(Core.Load(old, oldLength)), Core.Hash(plain))
end)

-- Destroy every keeper of a room, as the pilot's doing. Returns how many there were.
local function sweep(game: Core.Game, room: number): number
  local there = keepers(game, room)
  for _, id in there do
    Aftermath.Destroy(game.state, id, game.state.player.ship, game.events)
  end
  return #there
end

-- The events of a kind since they were last taken.
local function said(game: Core.Game, kind: string): { [string]: any }?
  local found: { [string]: any }? = nil
  for _, event in Core.TakeEvents(game) do
    found = if event.kind == kind then event else found
  end
  return found
end

suite:Case("a camp of two rooms: only the first is on the charts, and the way to the second is the first's gate, shut until it is cleared", function(t)
  local game, mission = camp(3, "clear", 2)
  local state = game.state
  t.eq({ #mission.rooms, mission.site } :: { any }, { 2, mission.rooms[1] } :: { any })
  local first, second = mission.rooms[1], mission.rooms[2]
  local outer, inner = assert(Space.Object(state, first)), assert(Space.Object(state, second))
  -- The second room: a place of its own, far enough off to be another grid, by the camp's name; and not found.
  t.eq({ state.sites[first].strength, state.sites[second].strength, state.sites[second].code } :: { any },
    { 1, 0, state.sites[first].code } :: { any })
  t.eq(inner.name, outer.name .. " II")
  local apart = Space.Distance(outer :: any, inner :: any)
  t.ok(apart >= 2e7 and apart <= 6.1e7, `the rooms are {apart} m apart`)
  t.eq(Sites.Hidden(state, second), true)
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  -- No scanner finds it, and it is not a signal.
  for _ = 1, 6 do
    submit(game, { kind = "Scan", actor = 0 })
    steps(game, Sites.SCAN + 1)
  end
  t.eq(state.sites[second].strength, 0, "a scan found a room of a camp")
  for _, row in Core.Query.Sites(game) do
    t.ok(row.id ~= second, "the room that is not open is on the scanner")
  end
  -- The first room has a gate that leads on to the second (the last room
  -- has none), a little way from its middle: a gate as a stargate is,
  -- that leads to a place.
  local gate = assert(Assault.Gate(state, first), "the first room has no gate")
  t.eq({ gate.kind, gate.variety, gate.to, gate.site, gate.name } :: { any },
    { "gate", Assault.GATE, second, first, `Gate to {inner.name}` } :: { any })
  t.eq(Assault.Gate(state, second), nil, "the last room has a gate")
  t.near(Space.Distance(outer :: any, gate :: any), Assault.GATE_OUT, 1600)
  -- The first room has its own waves and no more: with the last of them down, nobody else comes there.
  at(game, first)
  -- (and its gate is shut while they are to come, or there)
  t.eq(refused(game, { kind = "Jump", actor = 0, target = gate.id }), "the gate is shut while the camp's keepers hold this room")
  local inFirst = mission.ends[1]
  local destroyed = 0
  for wave = 1, inFirst do
    steps(game, Assault.BREATHER + 3)
    t.eq({ mission.wave, #keepers(game, first) }, { wave, #mission.waves[wave] })
    t.eq(refused(game, { kind = "Jump", actor = 0, target = gate.id }), "the gate is shut while the camp's keepers hold this room")
    Core.TakeEvents(game)
    destroyed += sweep(game, first)
  end
  local open = assert(said(game, "RoomOpen"), "nobody said the gate was open")
  t.eq({ open.room, open.of, open.site, open.name, open.gate } :: { any }, { 2, 2, second, inner.name, gate.id } :: { any })
  -- The second room is on no chart yet: the gate is the way to it.
  t.eq({ state.sites[second].strength, Sites.Hidden(state, second), mission.done } :: { any }, { 0, true, destroyed } :: { any })
  steps(game, Assault.BREATHER + 20)
  t.eq({ mission.wave, #keepers(game, first) }, { inFirst, 0 })
  -- Through it: the ship makes for the gate, and at it is sent on to the
  -- second room, in warp; and that room is on the overview from then on.
  t.eq(refused(game, { kind = "Jump", actor = 0, target = gate.id }), "(accepted)")
  t.ok((submit(game, { kind = "Jump", actor = 0, target = gate.id })))
  local through: { [string]: any }? = nil
  for _ = 1, 900 do
    Core.Step(game)
    through = through or said(game, "PassageTaken")
    if through then
      break
    end
  end
  t.ok(through ~= nil, "the ship never went through the gate")
  local sent = through :: { [string]: any }
  t.eq({ sent.ship, sent.gate, sent.site, sent.name } :: { any }, { state.player.ship, gate.id, second, inner.name } :: { any })
  local sentOn = state.balls[state.player.ship]
  t.eq({ state.sites[second].strength, Sites.Hidden(state, second), sentOn.warp and sentOn.warp.target } :: { any },
    { 1, false, second } :: { any })
  local shown = false
  for _, entry in Core.Query.Overview(game) do
    shown = shown or (entry.id == second and entry.kind == "site")
  end
  t.ok(shown, "the second room is not on the overview")
  -- The rest are in the second room, and come when the pilot does.
  at(game, second)
  for wave = inFirst + 1, #mission.waves do
    steps(game, Assault.BREATHER + 3)
    t.eq({ mission.wave, #keepers(game, second), #keepers(game, first) }, { wave, #mission.waves[wave], 0 })
    Core.TakeEvents(game)
    sweep(game, second)
  end
  t.eq(mission.done, mission.need)
  -- Done with, both rooms go.
  local home = state.player.home
  local ball = state.balls[state.player.ship]
  local station = assert(Space.Object(state, home))
  ball.x, ball.y, ball.z = station.x + station.radius + 500, station.y, station.z
  Space.AssignGrid(state, ball)
  t.ok((submit(game, { kind = "Dock", actor = 0, target = home })))
  for _ = 1, 600 do
    if state.ships[state.player.ship].docked == home then
      break
    end
    Core.Step(game)
  end
  t.ok((submit(game, { kind = "CompleteMission", actor = 0, target = mission.id })))
  t.eq({ state.sites[first].gone, state.sites[second].gone }, { true, true })
end)

suite:Case("a pilot who finds their own way to a room that is not open finds nobody in", function(t)
  local game, mission = camp(3, "clear", 2)
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  at(game, mission.rooms[2])
  steps(game, Assault.BREATHER + 20)
  t.eq({ mission.wave, #keepers(game, mission.rooms[2]) }, { 0, 0 })
end)

suite:Case("an assault on a camp's chief is done when the chief is destroyed, whoever else is left", function(t)
  -- (a camp whose last wave is more than the chief)
  local game: Core.Game, mission: State.Mission
  for level = 2, 4 do
    game, mission = camp(level, "chief", 1)
    if #mission.waves[#mission.waves] > 1 then
      break
    end
  end
  local state = game.state
  t.ok(#mission.waves[#mission.waves] > 1, "no camp with company for its chief")
  t.eq({ mission.need, mission.done, mission.mark }, { 1, 0, 0 })
  t.eq(refused(game, { kind = "CompleteMission", actor = 0, target = mission.id }), "the camp's chief is still to destroy")
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  at(game, mission.site)
  -- The waves before the last: nobody of them is the chief, and destroying them is not the job.
  for wave = 1, #mission.waves - 1 do
    steps(game, Assault.BREATHER + 3)
    t.eq({ mission.wave, mission.mark }, { wave, 0 })
    sweep(game, mission.site)
    t.eq(mission.done, 0)
  end
  -- The chief is the first of the last wave, by that name, with twice the bounty on them.
  Core.TakeEvents(game)
  steps(game, Assault.BREATHER + 3)
  local last = keepers(game, mission.site)
  t.eq({ #last, mission.mark }, { #mission.waves[#mission.waves], last[1] })
  local arrived = assert(said(game, "PiratesArrived"))
  t.eq(arrived.chief, true)
  local kind = Pirates.kindById[mission.waves[#mission.waves][1]]
  t.eq({ state.balls[last[1]].name, state.ships[last[1]].name, state.pilots[last[1]].bounty } :: { any },
    { "Pirate Chief", "Pirate Chief", 2 * kind.bounty } :: { any })
  t.eq(state.balls[last[2]].name, Pirates.kindById[mission.waves[#mission.waves][2]].name)
  -- One of the others down: not the job. The chief down: the job, with the rest still there.
  Aftermath.Destroy(state, last[2], state.player.ship, game.events)
  t.eq(mission.done, 0)
  Core.TakeEvents(game)
  local wallet = state.wallet
  Aftermath.Destroy(state, last[1], state.player.ship, game.events)
  t.eq({ mission.done, state.wallet - wallet }, { 1, 2 * kind.bounty })
  local cleared = assert(said(game, "AssaultCleared"), "nobody said the chief was down")
  t.eq(cleared.aim, "chief")
  -- Paid at the station; and whoever was left goes with the camp.
  local left = #keepers(game, mission.site)
  local home = state.player.home
  local ball = state.balls[state.player.ship]
  local station = assert(Space.Object(state, home))
  ball.x, ball.y, ball.z = station.x + station.radius + 500, station.y, station.z
  Space.AssignGrid(state, ball)
  t.ok((submit(game, { kind = "Dock", actor = 0, target = home })))
  for _ = 1, 600 do
    if state.ships[state.player.ship].docked == home then
      break
    end
    Core.Step(game)
  end
  t.ok((submit(game, { kind = "CompleteMission", actor = 0, target = mission.id })))
  t.eq({ #keepers(game, mission.site), #state.missionIds }, { 0, 0 })
  t.ok(left == #last - 2)
end)

suite:Case("an assault to raze a camp: what it is built of stands in the last room, and is the job, whoever else is left", function(t)
  local game, mission = camp(3, "raze", 2)
  local state = game.state
  local works = Assault.WORKS[3]
  t.eq({ mission.need, mission.done, mission.mark }, { #works, 0, 0 })
  t.eq(Missions.Title(mission), `Assault, level 3: a camp's {#works} works`)
  -- (it pays for what the camp is built of beside its keepers)
  t.ok(Assault.Pay(3, mission.waves, "raze") > Assault.Pay(3, mission.waves))
  t.eq(refused(game, { kind = "CompleteMission", actor = 0, target = mission.id }), `{#works} still to destroy`)
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  -- The first room: its keepers, and nothing built. Destroying them is not the job.
  at(game, mission.rooms[1])
  steps(game, 3)
  local first = keepers(game, mission.rooms[1])
  t.ok(#first > 0)
  for _, id in first do
    t.ok(Ships.byId[state.ships[id].type].class ~= "works")
  end
  while mission.wave < mission.ends[1] or #keepers(game, mission.rooms[1]) > 0 do
    sweep(game, mission.rooms[1])
    steps(game, Assault.BREATHER + 3)
  end
  t.eq({ mission.done, mission.mark }, { 0, 0 })
  -- A pilot who gets to the last room before its time finds nothing there.
  -- (here the first is cleared, so it is the last room's time)
  Core.TakeEvents(game)
  at(game, mission.rooms[2])
  steps(game, 2)
  local sighted = assert(said(game, "WorksSighted"), "nobody said what stands there")
  t.eq(sighted.count, #works)
  -- What it is built of stands there, each some kilometres from the middle, with the room's first wave.
  local there = keepers(game, mission.rooms[2])
  local built: { number } = {}
  local place = assert(Space.Object(state, mission.rooms[2]))
  for _, id in there do
    if Ships.byId[state.ships[id].type].class == "works" then
      table.insert(built, id)
      local ball = state.balls[id]
      local out = math.sqrt((ball.x - place.x) ^ 2 + (ball.z - place.z) ^ 2)
      t.ok(out >= Assault.WORKS_OUT[1] and out <= Assault.WORKS_OUT[2], `one stands {out} m out`)
      t.eq({ state.ships[id].owner, state.pilots[id].bounty } :: { any },
        { "pirates", Pirates.kindById[works[#built]].bounty } :: { any })
    end
  end
  t.eq({ #built, mission.mark, #there - #built }, { #works, built[1], #mission.waves[mission.ends[1] + 1] })
  -- They are put up once.
  steps(game, 5)
  t.eq(#keepers(game, mission.rooms[2]), #there)
  -- A keeper destroyed is not the job; nor do the works hold the next wave back.
  for _, id in there do
    if not table.find(built, id) then
      Aftermath.Destroy(state, id, state.player.ship, game.events)
    end
  end
  t.eq(mission.done, 0)
  if mission.ends[1] + 1 < #mission.waves then
    steps(game, Assault.BREATHER + 3)
    t.eq(mission.wave, mission.ends[1] + 2)
  end
  -- Each of the works destroyed counts, pays its own bounty, and the last finishes the job.
  Core.TakeEvents(game)
  for index, id in built do
    local wallet = state.wallet
    Aftermath.Destroy(state, id, state.player.ship, game.events)
    t.eq({ mission.done, state.wallet - wallet }, { index, Pirates.kindById[works[index]].bounty })
  end
  local cleared = assert(said(game, "AssaultCleared"), "nobody said the camp was razed")
  t.eq(cleared.aim, "raze")
  -- It is in the save as it stands.
  local file, length = Core.Save(game)
  t.eq(Core.Hash(Core.Load(file, length)), Core.Hash(game))
  -- Paid at the station; and whoever was left goes with the camp.
  local home = state.player.home
  local ball = state.balls[state.player.ship]
  local station = assert(Space.Object(state, home))
  ball.x, ball.y, ball.z = station.x + station.radius + 500, station.y, station.z
  Space.AssignGrid(state, ball)
  t.ok((submit(game, { kind = "Dock", actor = 0, target = home })))
  for _ = 1, 600 do
    if state.ships[state.player.ship].docked == home then
      break
    end
    Core.Step(game)
  end
  t.ok((submit(game, { kind = "CompleteMission", actor = 0, target = mission.id })))
  t.eq({ #keepers(game, mission.rooms[2]), #state.missionIds }, { 0, 0 })
end)

suite:Case("an assault given up takes what its camp is built of with it", function(t)
  local game, mission = camp(2, "raze", 1)
  local state = game.state
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  at(game, mission.site)
  steps(game, 3)
  local there = keepers(game, mission.site)
  t.eq(#there, #Assault.WORKS[2] + #mission.waves[1])
  -- (a job is given up where it was taken)
  local home = state.player.home
  local ball = state.balls[state.player.ship]
  local station = assert(Space.Object(state, home))
  ball.x, ball.y, ball.z = station.x + station.radius + 500, station.y, station.z
  Space.AssignGrid(state, ball)
  t.ok((submit(game, { kind = "Dock", actor = 0, target = home })))
  for _ = 1, 600 do
    if state.ships[state.player.ship].docked == home then
      break
    end
    Core.Step(game)
  end
  t.ok((submit(game, { kind = "AbandonMission", actor = 0, target = mission.id })))
  for _, id in there do
    t.eq({ state.balls[id], state.ships[id], state.pilots[id] } :: { any }, {})
  end
end)

suite:Case("an assault to fetch what a camp took: a container in the last room, looted and brought back to the station", function(t)
  local game, mission = camp(1, "fetch")
  local state = game.state
  local home = state.player.home
  t.eq({ mission.need, mission.type } :: { any }, { 10, "cargo.stolen" } :: { any })
  -- The container is in the last room, with the crates in it.
  local container = assert(state.wrecks[mission.mark], "the camp has no container")
  local last = mission.rooms[#mission.rooms]
  t.eq({ container.name, container.grid, container.system, container.locked } :: { any }, { "Stolen Cargo", last, 1, false } :: { any })
  local crates = 0
  for _, item in Items.In(state, container.id, "cargo") do
    crates += if item.type == "cargo.stolen" then item.quantity else 0
  end
  t.eq(crates, 10)
  t.eq(refused(game, { kind = "CompleteMission", actor = 0, target = mission.id }), "10 more to bring")
  -- It does not fade while the job is in hand.
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  steps(game, 200)
  t.ok(state.wrecks[container.id] ~= nil)
  -- Destroying the camp's keepers is not the job: it counts nothing.
  at(game, mission.site)
  steps(game, 3)
  sweep(game, mission.site)
  t.eq(mission.done, 0)
  -- Looted (from beside it), the crates are in the hold. Nobody in that room has to be destroyed first.
  local ball = state.balls[state.player.ship]
  ball.x, ball.y, ball.z = container.x + 500, container.y, container.z
  Space.AssignGrid(state, ball)
  t.ok((submit(game, { kind = "Loot", actor = 0, target = container.id })))
  local held = 0
  for _, item in Items.In(state, state.player.ship, "cargo") do
    held += if item.type == "cargo.stolen" then item.quantity else 0
  end
  t.eq(held, 10)
  -- Brought back: handed over, and paid.
  local station = assert(Space.Object(state, home))
  ball.x, ball.y, ball.z = station.x + station.radius + 500, station.y, station.z
  Space.AssignGrid(state, ball)
  t.ok((submit(game, { kind = "Dock", actor = 0, target = home })))
  for _ = 1, 600 do
    if state.ships[state.player.ship].docked == home then
      break
    end
    Core.Step(game)
  end
  local wallet = state.wallet
  t.ok((submit(game, { kind = "CompleteMission", actor = 0, target = mission.id })))
  t.eq(state.wallet - wallet, mission.reward)
  local kept = 0
  for _, place in { { state.player.ship, "cargo" }, { home, "hangar" } } :: { { any } } do
    for _, item in Items.In(state, place[1], place[2]) do
      kept += if item.type == "cargo.stolen" then item.quantity else 0
    end
  end
  t.eq(kept, 0, "the crates should have been handed over")

  -- Given up with the container untouched: it goes with the camp.
  local other, job = camp(1, "fetch")
  local box = job.mark
  t.ok(other.state.wrecks[box] ~= nil)
  t.ok((submit(other, { kind = "AbandonMission", actor = 0, target = job.id })))
  t.eq(other.state.wrecks[box], nil)
end)

suite:Case("an assault of a save from before camps had rooms is on a camp of one room, to be cleared", function(t)
  local game, mission = camp(1, "clear", 1)
  local data, length = Core.Save(game)
  local file = Codec.Decode(data, length)
  file.saveVersion = 37
  for _, each in file.state.missions do
    each.rooms, each.ends, each.aim, each.mark = nil, nil, nil, nil
  end
  local old, oldLength = Codec.Encode(file)
  local loaded = Core.Load(old, oldLength)
  local theirs = loaded.state.missions[mission.id]
  t.eq({ theirs.rooms, theirs.ends, theirs.aim, theirs.mark } :: { any }, { { mission.site }, { #mission.waves }, "clear", 0 } :: { any })
  t.eq(Core.Hash(loaded), Core.Hash(game))
end)

-- The mining contracts a station offers, by level.
local function contracts(game: Core.Game, station: number): { State.Mission }
  local found: { State.Mission } = {}
  for _, offer in Missions.Offers(game.state, station) do
    if offer.kind == "mining" then
      table.insert(found, offer)
    end
  end
  return found
end

-- A game in which the home station's mining contract of a level is for
-- a pocket in its own system, that contract taken: the game and the job.
local function pocket(level: number): (Core.Game, State.Mission)
  for seed = 1, 60 do
    local game = newGame(seed)
    local state = game.state
    state.standings.vessari = Assault.STANDING[level]
    local offer = contracts(game, state.player.home)[level]
    if offer and offer.system == 1 then
      assert(submit(game, { kind = "AcceptMission", actor = 0, what = offer.key }))
      return game, state.missions[state.missionIds[1]]
    end
  end
  error("no history seed up to 60 has the pocket in the home system")
end

suite:Case("the fifth agent has a mining contract at each level the pilot's standing opens: so much of an ore, for more than it is worth", function(t)
  local game = newGame()
  local state = game.state
  local home = state.player.home
  for _, case in { { -3, 0 }, { 0, 1 }, { 1, 2 }, { 3, 3 }, { 5, 4 } } do
    state.standings.vessari = case[1]
    t.eq(#contracts(game, home), case[2], `at a standing of {case[1]}`)
  end
  local offers = contracts(game, home)
  t.eq(contracts(game, home), offers, "the same however often it is asked")
  local last = 0
  for level, offer in offers do
    t.eq({ offer.kind, offer.aim, offer.level, offer.id, offer.site, offer.station } :: { any },
      { "mining", "dig", level, 0, 0, home } :: { any })
    t.eq(offer.agent, Missions.Agent(state, home, 5), "a mining contract is the fifth agent's")
    t.ok(offer.agent ~= Missions.Agent(state, home, 4))
    t.ok(offer.system == 1 or table.find(state.galaxy.systems[1].neighbors, offer.system) ~= nil)
    -- An ore, and a round number of hundreds of it: more by the cubic metre a level.
    local ore = assert(Ores.byId[offer.type], `a contract for {offer.type}`)
    t.eq(offer.need % 100, 0)
    local volume = offer.need * ore.volume
    t.near(volume, ({ 300, 900, 2500, 7000 })[level], 61, `level {level} wants {volume} m3`)
    -- It pays three tenths over what the ore is worth, and three thousand a level, and what the pilot's standing adds.
    t.eq(offer.reward, math.floor((math.floor(1.3 * offer.need * ore.basePrice) + 3000 * level) * (1 + 0.03 * 5)))
    t.near(offer.standing, 0.1 * level, 1e-9)
    t.ok(offer.reward > last, "a bigger contract should pay more")
    last = offer.reward
    t.eq(Missions.Title(offer), `Mining, level {level}: {offer.need} {ore.name}`)
    -- Nobody disputes the first two; a pack turns up at the others.
    t.eq({ #offer.waves, #offer.ends, offer.ends[1] }, if level <= 2 then { 0, 1, 0 } else { 1, 1, 1 })
  end
  -- The rare ores are the higher levels'.
  t.ok(Ores.byId[offers[1].type].share > 0.2 and Ores.byId[offers[4].type].share == 0)
  -- One from a station at a time, beside whatever else is in hand; and the agent's next is another.
  t.ok((submit(game, { kind = "AcceptMission", actor = 0, what = offers[1].key })))
  t.eq({ #contracts(game, home), state.digs[home], #assaults(game, home) }, { 0, 1, 4 })
  t.ok((submit(game, { kind = "AbandonMission", actor = 0, target = state.missionIds[1] })))
  state.standings.vessari = 5
  t.ok(contracts(game, home)[1].key ~= offers[1].key)
end)

suite:Case("taking a mining contract puts its pocket on the charts: rocks of the ore, half as much again as is wanted; the ore brought in, it is paid", function(t)
  local game, mission = pocket(1)
  local state = game.state
  local home = state.player.home
  local site = assert(state.sites[mission.site], "the contract has no pocket")
  local place = assert(Space.Object(state, site.id))
  t.eq({ site.kind, site.strength, string.sub(place.name, 1, 10), #mission.rooms } :: { any }, { "mission", 1, "Ore Pocket", 1 } :: { any })
  -- Its rocks: four of them, of the ore, a few kilometres from the middle, with what is wanted and half as much again.
  local rocks, units = 0, 0
  for _, object in Space.Describe(state, 1).objects do
    if object.kind == "asteroid" and object.site == site.id then
      rocks += 1
      units += Mining.Left(state, object)
      t.eq(object.variety, mission.type)
      local far = Space.Distance(object :: any, place :: any)
      t.ok(far >= 2500 and far <= 7500, `a rock {far} m from the middle of the pocket`)
    end
  end
  t.eq(rocks, 4)
  t.ok(units >= 1.5 * mission.need and units <= 1.6 * mission.need + 200, `{units} units in the pocket for a contract of {mission.need}`)
  -- Nobody is there, and nobody comes: pirates leave a pocket alone as they do a camp.
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  state.peaceful = false
  at(game, site.id)
  steps(game, 90)
  t.eq(#keepers(game, site.id), 0)
  for _, id in state.pilotIds do
    local ball = state.balls[id]
    t.ok(ball == nil or ball.grid ~= site.id, "somebody came to a pocket nobody disputes")
  end
  state.peaceful = true
  -- Not done until the ore is to hand at the station. (Ore of the kind from anywhere does.)
  t.eq(refused(game, { kind = "CompleteMission", actor = 0, target = mission.id }), "not docked")
  Items.Add(state, mission.type, mission.need - 100, state.player.ship, "cargo")
  local ball = state.balls[state.player.ship]
  local station = assert(Space.Object(state, home))
  ball.x, ball.y, ball.z = station.x + station.radius + 500, station.y, station.z
  Space.AssignGrid(state, ball)
  t.ok((submit(game, { kind = "Dock", actor = 0, target = home })))
  for _ = 1, 600 do
    if state.ships[state.player.ship].docked == home then
      break
    end
    Core.Step(game)
  end
  t.eq(refused(game, { kind = "CompleteMission", actor = 0, target = mission.id }), "100 more to bring")
  Items.Add(state, mission.type, 150, home, "hangar")
  local wallet = state.wallet
  t.ok((submit(game, { kind = "CompleteMission", actor = 0, target = mission.id })))
  t.eq(state.wallet - wallet, mission.reward)
  local left = 0
  for _, holder in { { state.player.ship, "cargo" }, { home, "hangar" } } :: { { any } } do
    for _, item in Items.In(state, holder[1], holder[2]) do
      left += if item.type == mission.type then item.quantity else 0
    end
  end
  t.eq(left, 50, "what was wanted should be taken, and no more")
  -- The pocket goes with the contract.
  t.eq({ state.sites[site.id].gone, #state.missionIds } :: { any }, { true, 0 } :: { any })
end)

suite:Case("at the harder contracts a pack turns up at the pocket when the pilot does, once; and a save from before has no contracts given", function(t)
  local game, mission = pocket(3)
  local state = game.state
  t.eq(#mission.waves, 1)
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  at(game, mission.site)
  steps(game, 2)
  local pack = keepers(game, mission.site)
  t.eq({ #pack, mission.wave }, { #mission.waves[1], 1 })
  -- Destroyed, they are not replaced, and they count for nothing toward the contract.
  for _, id in pack do
    Aftermath.Destroy(state, id, state.player.ship, game.events)
  end
  steps(game, Assault.BREATHER + 30)
  t.eq({ #keepers(game, mission.site), mission.done, mission.wave }, { 0, 0, 1 })
  -- In the save; and a save from before the fifth agent had any.
  local data, length = Core.Save(game)
  t.eq(Core.Hash(Core.Load(data, length)), Core.Hash(game))
  local plain = newGame()
  local now, nowLength = Core.Save(plain)
  local file = Codec.Decode(now, nowLength)
  file.saveVersion = 40
  file.state.digs = nil
  local old, oldLength = Codec.Encode(file)
  t.eq(Core.Hash(Core.Load(old, oldLength)), Core.Hash(plain))
end)

suite:Case("a job comes from an agent, the same people at a station every day, and is worth loyalty points beside its pay", function(t)
  local game = newGame()
  local state = game.state
  local home = state.player.home
  local today = Missions.Offers(state, home)
  local names: { string } = {}
  for slot, offer in today do
    t.ok(#offer.agent > 4, "a job from nobody")
    t.eq(offer.agent, Missions.Agent(state, home, slot))
    t.eq(offer.loyalty, math.max(1, offer.reward // Missions.LOYALTY))
    table.insert(names, offer.agent)
  end
  t.ok(names[1] ~= names[2] and names[2] ~= names[3])
  for _ = 1, 86400 do
    Core.Step(game)
  end
  for slot, offer in Missions.Offers(state, home) do
    t.eq(offer.agent, names[slot], "tomorrow's job should come from the same agent")
  end
end)

suite:Case("a finished job earns loyalty points, and a faction's store sells for them what its standing allows", function(t)
  local game, mission = taken(t, "supply")
  local state = game.state
  local home = state.player.home
  local faction = mission.faction
  state.wallet = 100000000
  -- Nothing to spend yet.
  t.eq(refused(game, { kind = "RedeemLoyalty", actor = 0, type = "datacore" }), "needs 50 loyalty points")
  t.eq(refused(game, { kind = "RedeemLoyalty", actor = 0, type = "mineral.iron" }), "this station's store has no such thing")
  Items.Add(state, mission.type, mission.need, home, "hangar")
  t.ok((submit(game, { kind = "CompleteMission", actor = 0, target = mission.id })))
  t.eq(state.loyalty[faction], mission.loyalty)
  local status = Core.Query.Missions(game)
  t.eq({ status.loyalty, #status.store > 10 } :: { any }, { mission.loyalty, true } :: { any })
  -- A datacore for fifty points and five thousand credits, to anybody in good standing.
  state.loyalty[faction] = 400
  local wallet = state.wallet
  t.ok((submit(game, { kind = "RedeemLoyalty", actor = 0, type = "datacore", quantity = 2 })))
  t.eq({ state.loyalty[faction], wallet - state.wallet }, { 300, 10000 })
  local cores = 0
  for _, item in Items.In(state, home, "hangar") do
    cores += if item.type == "datacore" then item.quantity else 0
  end
  t.eq(cores, 2)
  -- An implant wants a standing of 1, and a blueprint of 2 (and only of the faction's own kinds of weapon).
  state.standings[faction] = 0.5
  t.eq(refused(game, { kind = "RedeemLoyalty", actor = 0, type = "implant.shield" }), "needs a standing of 1 with them")
  state.standings[faction] = 1
  t.ok((submit(game, { kind = "RedeemLoyalty", actor = 0, type = "implant.shield" })))
  t.eq(state.loyalty[faction], 300 - 120)
  local store = Missions.Store(faction)
  local blueprints, foreign, hulls = 0, 0, 0
  for _, stock in store do
    local made = string.sub(stock.type, #"blueprint." + 1)
    if string.sub(stock.type, 1, 10) == "blueprint." and Ships.byId[made] then
      -- (a tech 2 hull of the faction's own line: for a pilot it thinks well of, and not for points alone)
      hulls += 1
      local hull = Ships.byId[made]
      t.eq({ hull.tech, hull.lineage, stock.standing, stock.points, stock.credits } :: { any },
        { 2, faction, 3, Missions.HULL_POINTS[hull.class], hull.basePrice // 20 } :: { any })
    elseif string.sub(stock.type, 1, 10) == "blueprint." then
      blueprints += 1
      t.eq({ stock.standing, stock.credits }, { 2, 0 })
      foreign += if string.find(stock.type, "laser", 1, true) or string.find(stock.type, "blaster", 1, true) then 1 else 0
    end
  end
  -- (the Vessari's are projectile guns and missiles: eight kinds of gun and four launchers; and the two tech 2
  -- ships their line names, the Kanau and the Akaboshi: a ship has no "II")
  t.eq({ faction, blueprints, foreign, hulls } :: { any }, { "vessari", 12, 0, 2 } :: { any })
  -- (the Talmar's store has the one tech 2 hull of theirs that a store sells: their hauler's, for a pilot they
  -- think well of)
  local theirs = 0
  for _, stock in Missions.Store("talmar") do
    if stock.type == "blueprint.industrial.tarantula" then
      theirs += 1
      t.eq({ stock.standing, stock.points } :: { any }, { 3, Missions.HULL_POINTS.industrial } :: { any })
    end
    t.ok(string.sub(stock.type, -3) ~= ".ii" or Ships.byId[string.sub(stock.type, #"blueprint." + 1)] == nil, stock.type)
  end
  t.eq(theirs, 1)
  state.standings[faction] = 1
  t.eq(refused(game, { kind = "RedeemLoyalty", actor = 0, type = "blueprint.autocannon.small.ii" }), "needs a standing of 2 with them")
  state.standings[faction] = 2
  state.loyalty[faction] = 100000
  t.ok((submit(game, { kind = "RedeemLoyalty", actor = 0, type = "blueprint.autocannon.small.ii" })))
  t.ok(state.loyalty[faction] < 100000)
  -- With somebody who thinks ill of the pilot there is nothing to be had.
  state.standings[faction] = -1
  t.eq(refused(game, { kind = "RedeemLoyalty", actor = 0, type = "datacore" }), "needs a standing of 0 with them")
end)

suite:Case("a job kept more than three days lapses, at the cost of having given it up", function(t)
  local game, mission = taken(t, "bounty")
  local state = game.state
  local faction = mission.faction
  t.near(Missions.Left(state, mission), 3 * 86400, 2)
  for _ = 1, Missions.LIMIT - 120 do
    Core.Step(game)
  end
  t.eq(#state.missionIds, 1)
  t.ok(Core.Query.Missions(game).inHand[1].left <= 180)
  local before = Missions.Standing(state, faction)
  local lapsed = false
  for _ = 1, 400 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      lapsed = lapsed or (event.kind == "MissionExpired" and event.mission == mission.id)
    end
  end
  t.ok(lapsed, "nobody said the job had lapsed")
  t.eq(#state.missionIds, 0)
  t.ok(Missions.Standing(state, faction) < before - mission.standing, "a lapsed job should cost standing")
  -- An older save's jobs have no agent and earn no points, and their three days begin when it is opened.
  local other, held = taken(t, "bounty")
  for _ = 1, 5000 do
    Core.Step(other)
  end
  local data, length = Core.Save(other)
  local file = Codec.Decode(data, length)
  file.saveVersion = 29
  file.state.loyalty = nil
  for _, each in file.state.missions do
    each.agent, each.loyalty = nil, nil
  end
  local old, oldLength = Codec.Encode(file)
  local loaded = Core.Load(old, oldLength)
  local kept = loaded.state.missions[held.id]
  t.eq({ kept.agent, kept.loyalty, kept.taken, loaded.state.loyalty } :: { any }, { "", 0, loaded.state.tick, {} } :: { any })
end)

suite:Case("an agent has a regard of their own for the pilot: more with every job of theirs finished, less with one given up, and they pay for it", function(t)
  local game, mission = taken(t, "supply")
  local state = game.state
  local home = state.player.home
  t.ok(mission.slot >= 1 and mission.slot <= Missions.OFFERS)
  t.eq(mission.agent, Missions.Agent(state, home, mission.slot))
  t.eq(Missions.Regard(state, home, mission.slot), 0)
  -- What the same agent would pay for the same job by a pilot they think well of: 2% a point.
  local function paid(regard: number): number
    local other = newGame(state.historySeed)
    other.state.regard[`{home}:{mission.slot}`] = regard
    for _, offer in Missions.Offers(other.state, home) do
      if offer.key == mission.key then
        return offer.reward
      end
    end
    error("the offer is gone")
  end
  t.eq(paid(0), mission.reward)
  t.near(paid(5) / mission.reward, 1 + 5 * Missions.REGARD.pay, 0.001)
  -- (one who thinks ill of the pilot pays what they pay anybody)
  t.eq(paid(-3), mission.reward)
  -- Finished: half a point with whoever gave it, and with nobody else.
  Items.Add(state, mission.type, mission.need, home, "hangar")
  t.ok((submit(game, { kind = "CompleteMission", actor = 0, target = mission.id })))
  local done: { [string]: any }? = nil
  for _, event in Core.TakeEvents(game) do
    done = if event.kind == "MissionCompleted" then event else done
  end
  t.eq({ assert(done).agent, assert(done).regard } :: { any }, { mission.agent, Missions.REGARD.daily } :: { any })
  for slot = 1, Missions.OFFERS + 2 do
    t.eq(Missions.Regard(state, home, slot), if slot == mission.slot then Missions.REGARD.daily else 0, `agent {slot}`)
  end
  -- The pilot sees it against each job offered.
  for _, row in Core.Query.Missions(game).offers do
    t.eq(row.regard, Missions.Regard(state, home, row.mission.slot))
  end
  -- Given up: a point less, and it can go below nothing; let lapse, the same.
  local other, held = taken(t, "bounty")
  t.ok((submit(other, { kind = "AbandonMission", actor = 0, target = held.id })))
  t.eq(Missions.Regard(other.state, held.station, held.slot), -Missions.REGARD.lost)
  local third, kept = taken(t, "bounty")
  for _ = 1, Missions.LIMIT + 200 do
    Core.Step(third)
  end
  t.eq({ #third.state.missionIds, Missions.Regard(third.state, kept.station, kept.slot) } :: { any }, { 0, -Missions.REGARD.lost } :: { any })
  -- It is in the save, and an older save has nobody's.
  state.regard[`{home}:1`] = 9.8
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq({ Core.Hash(loaded), Missions.Regard(loaded.state, home, 1) } :: { any }, { Core.Hash(game), 9.8 } :: { any })
  local busy, job = taken(t, "bounty")
  local busyData, busyLength = Core.Save(busy)
  local busyFile = Codec.Decode(busyData, busyLength)
  busyFile.saveVersion = 46
  busyFile.state.regard = nil
  for _, each in busyFile.state.missions do
    each.slot = nil
  end
  local old, oldLength = Codec.Encode(busyFile)
  local opened = Core.Load(old, oldLength)
  t.eq({ opened.state.regard, opened.state.missions[job.id].slot } :: { any }, { {}, 0 } :: { any })
  -- (a job from before agents had a regard is from nobody in particular: finishing it moves nobody's)
  t.ok((submit(opened, { kind = "AbandonMission", actor = 0, target = job.id })))
  t.eq(opened.state.regard, {})
end)

suite:Case("the fourth and the fifth agent open their harder levels to a pilot they know, whatever the faction makes of them", function(t)
  local game = newGame()
  local state = game.state
  local home = state.player.home
  local function levels(kind: string): number
    local top = 0
    for _, offer in Missions.Offers(state, home) do
      top = if offer.kind == kind then math.max(top, offer.level) else top
    end
    return top
  end
  -- A pilot the faction has no opinion of has the first level from each.
  t.eq({ levels("assault"), levels("mining") }, { 1, 1 })
  -- Known to the fourth agent, and not to the fifth: the fourth's levels open, and theirs only.
  for level, wanted in Missions.OPENS do
    state.regard[`{home}:{Missions.OFFERS + 1}`] = wanted
    t.eq({ levels("assault"), levels("mining") }, { level, 1 }, `at a regard of {wanted}`)
    state.regard[`{home}:{Missions.OFFERS + 1}`] = wanted - 0.01
    t.eq(levels("assault"), math.max(1, level - 1), `just short of a regard of {wanted}`)
  end
  -- The faction's standing still opens them for everybody's agents, as it did.
  state.regard = {}
  state.standings.vessari = Assault.STANDING[3]
  t.eq({ levels("assault"), levels("mining") }, { 3, 3 })
  -- (whichever is more)
  state.regard[`{home}:{Missions.OFFERS + 2}`] = Missions.OPENS[4]
  t.eq({ levels("assault"), levels("mining") }, { 3, 4 })
  -- And no regard gets work out of an agent whose faction will give the pilot none.
  state.standings.vessari = Assault.STANDING[1] - 1
  t.eq({ levels("assault"), levels("mining") }, { 0, 0 })
  -- An assault finished is worth a quarter of a point and a quarter a level with its agent.
  state.standings.vessari = 0
  state.regard = {}
  local offer: State.Mission? = nil
  for _, each in Missions.Offers(state, home) do
    offer = if each.kind == "mining" then each else offer
  end
  local contract = assert(offer)
  t.ok((submit(game, { kind = "AcceptMission", actor = 0, what = contract.key })))
  Items.Add(state, contract.type, contract.need, home, "hangar")
  t.ok((submit(game, { kind = "CompleteMission", actor = 0, target = state.missionIds[1] })))
  t.near(Missions.Regard(state, home, Missions.OFFERS + 2), Missions.REGARD.levelled * 2, 1e-9)
  -- (so four first-level jobs for one agent open that agent's second level)
  t.ok(4 * Missions.REGARD.levelled * 2 >= Missions.OPENS[2])
end)

-- The sixth agent's courier contracts among what a station offers, by level.
local function runs(game: Core.Game, station: number): { State.Mission }
  local found: { State.Mission } = {}
  for _, offer in Missions.Offers(game.state, station) do
    if offer.kind == "courier" and offer.level > 0 then
      table.insert(found, offer)
    end
  end
  return found
end

suite:Case("the sixth agent has courier contracts in levels: a frigate's hold over a few jumps, a hauler's over many, then more than a hauler holds, then a freighter's", function(t)
  local seen = { 0, 0, 0, 0 }
  local wild, bulk = 0, 0
  for seed = 1, 12 do
    local game = Core.New({ galaxySeed = 1, historySeed = seed, peaceful = true, systems = 40 })
    local state = game.state
    local home = state.player.home
    -- One level for a pilot nobody knows; the second at a standing of 1, or for a pilot the agent knows.
    t.eq(#runs(game, home), 1)
    state.regard[`{home}:{Missions.OFFERS + 3}`] = Missions.OPENS[2]
    t.eq(#runs(game, home), 2)
    state.regard = {}
    state.standings.vessari = 10
    local offers = runs(game, home)
    t.eq(#offers, #Missions.RUNS, "every level should be offered where the galaxy has room for it")
    t.eq(runs(game, home), offers, "the same however often it is asked")
    local reach = Missions.Reach(state.galaxy, 1)
    for level, offer in offers do
      local run = if offer.aim == "wild" then Missions.WILD else Missions.RUNS[level]
      seen[level] += 1
      t.eq({ offer.level, offer.id, offer.station, offer.type, offer.slot } :: { any },
        { level, 0, home, Missions.CRATE, Missions.OFFERS + 3 } :: { any })
      t.eq(offer.agent, Missions.Agent(state, home, Missions.OFFERS + 3), "a courier contract is the sixth agent's")
      t.ok(offer.need >= run.least and offer.need <= run.most and offer.need % run.step == 0, `level {level}: {offer.need} m3`)
      local to = assert(Space.Object(state, offer.to))
      t.eq({ to.kind, offer.system } :: { any }, { "station", Space.SystemOf(state, to.id) } :: { any })
      local jumps = Missions.Jumps(state, offer)
      if offer.aim == "wild" then
        -- The fourth level's other kind: to a station that only lawless space leads to, and it says so.
        wild += 1
        t.eq(level, #Missions.RUNS)
        t.eq(reach[offer.system], nil, "a run through lawless space went where there was a safe way")
        t.eq(jumps, #Galaxy.Route(state.galaxy, 1, offer.system) - 1)
        t.ok(jumps >= run.near and jumps <= run.far, `a lawless run of {jumps} jumps`)
        t.eq(Missions.Title(offer), `Courier, level {level}: {offer.need} m3, lawless`)
      else
        -- Any other: so many jumps off by a way that keeps out of lawless space (in a galaxy of forty, the
        -- farthest there is, for the levels that would go farther than it has room for).
        bulk += if level == #Missions.RUNS then 1 else 0
        t.eq(offer.aim, "run")
        t.eq(jumps, assert(reach[offer.system], "a courier contract goes where only lawless space leads"))
        local least = if level > 1 then math.min(run.near, Missions.RUNS[level - 1].near + 1) else 1
        t.ok(jumps >= least and jumps <= run.far, `level {level}: {jumps} jumps`)
        t.eq(Missions.Title(offer), `Courier, level {level}: {offer.need} m3`)
      end
      -- It pays for the volume and the way, and standing by its level.
      t.eq(offer.reward, math.floor((run.base + run.rate * offer.need * jumps) * (1 + 0.03 * 10)))
      t.near(offer.standing, Missions.RUN_CREDIT * level, 1e-9)
    end
  end
  t.eq(seen, { 12, 12, 12, 12 })
  t.ok(wild >= 2 and bulk >= 2, `of twelve fourth-level contracts, {wild} lawless runs and {bulk} freighter loads`)
  -- What carries each: the starter ship the first, a hauler the second, more than a hauler the third, and only
  -- a freighter the fourth (or, for the run through lawless space, a hauler).
  local courier, mule, dray = Ships.byId["frigate.courier"].cargo, Ships.byId["industrial.hauler"].cargo, Ships.byId["freighter.dray"].cargo
  t.ok(Missions.RUNS[1].most <= courier and Missions.RUNS[2].least > courier and Missions.RUNS[2].most <= mule)
  t.ok(Missions.RUNS[3].least > mule and Missions.RUNS[3].most <= dray)
  t.ok(Missions.RUNS[4].least > 3 * mule and Missions.RUNS[4].most <= dray and Missions.WILD.most <= mule)
  -- The way there: every system on it is one the pilot can cross without entering lawless space.
  local galaxy = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true, systems = 40 }).state.galaxy
  for id, jumps in Missions.Reach(galaxy, 1) do
    t.ok(id == 1 or Galaxy.Band(galaxy.systems[id].security) ~= "lawless", `system {id}, {jumps} jumps off, is lawless`)
  end
  -- A galaxy too small for it: the first level goes as far as there is to go, and nothing harder has anywhere to.
  local small = newGame()
  small.state.standings.vessari = 10
  local few = runs(small, small.state.player.home)
  t.ok(#few >= 1 and few[1].level == 1 and Missions.Jumps(small.state, few[1]) <= 1)
  for _, offer in few do
    t.ok(offer.level == 1 or offer.aim == "wild", `a galaxy of three systems offered level {offer.level}`)
  end
end)

suite:Case("a courier contract hands its crates over, is carried in as many trips as it takes, and is paid where it is delivered; then the agent has another", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true, systems = 40 })
  local state = game.state
  local home = state.player.home
  local ship = state.ships[state.player.ship]
  state.standings.vessari = 1
  local offers = runs(game, home)
  local big = offers[2]
  t.eq(big.level, 2)
  t.ok((submit(game, { kind = "AcceptMission", actor = 0, what = big.key })))
  local mission = state.missions[state.missionIds[1]]
  -- The crates are in the hangar here, the agent has nothing more while it is in hand, and it is one more job in hand.
  local crates = 0
  for _, item in Items.In(state, home, "hangar") do
    crates += if item.type == Missions.CRATE then item.quantity else 0
  end
  t.eq({ crates, #runs(game, home), state.couriers[home] } :: { any }, { mission.need, 0, 1 } :: { any })
  t.eq(refused(game, { kind = "CompleteMission", actor = 0, target = mission.id }),
    `finish it at {(assert(Space.Object(state, mission.to))).name}`)
  -- A first trip with what a Courier holds, left in the hangar there; and the rest brought after.
  local function there(units: number)
    for _, item in Items.In(state, home, "hangar") do
      if item.type == Missions.CRATE and units > 0 then
        Items.Add(state, Missions.CRATE, units, ship.id, "cargo")
        Items.Take(state, item, units)
      end
    end
    ship.docked = mission.to
  end
  there(150)
  t.eq(refused(game, { kind = "CompleteMission", actor = 0, target = mission.id }), `{mission.need - 150} more to bring`)
  t.ok((submit(game, { kind = "MoveItems", actor = 0, item = Items.In(state, ship.id, "cargo")[1].id, to = "hangar" })))
  ship.docked = home
  there(mission.need - 150)
  local wallet, standing = state.wallet, Missions.Standing(state, "vessari")
  t.ok((submit(game, { kind = "CompleteMission", actor = 0, target = mission.id })))
  t.eq(state.wallet - wallet, mission.reward)
  t.near(Missions.Standing(state, "vessari") - standing, Missions.RUN_CREDIT * 2, 1e-9)
  -- (with whoever gave it, a quarter of a point and a quarter a level)
  t.near(Missions.Regard(state, home, Missions.OFFERS + 3), Missions.REGARD.levelled * 3, 1e-9)
  local left = 0
  for _, holder in { ship.id, mission.to, home } do
    for _, item in Items.In(state, holder, nil) do
      left += if item.type == Missions.CRATE then item.quantity else 0
    end
  end
  t.eq(left, 0, "the crates should all have been handed over")
  -- The agent's next is another contract, and not the same one.
  ship.docked = home
  local next = runs(game, home)
  t.eq(#next, 2)
  t.ok(next[2].key ~= big.key)
  -- Contracts given are in the save, and an older save has given none.
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq({ Core.Hash(loaded), loaded.state.couriers[home] } :: { any }, { Core.Hash(game), 1 } :: { any })
  local file = Codec.Decode(data, length)
  file.saveVersion = 49
  file.state.couriers = nil
  local old, oldLength = Codec.Encode(file)
  t.eq(Core.Load(old, oldLength).state.couriers, {})
end)

-- The defence jobs a station offers, by level.
local function defences(game: Core.Game, station: number): { State.Mission }
  local found: { State.Mission } = {}
  for _, offer in Missions.Offers(game.state, station) do
    if Missions.Line(offer) == "defence" then
      table.insert(found, offer)
    end
  end
  return found
end

-- A game in which the home station's defence job of a level is in its
-- own system, that job taken, and the pilot at the place with the rig
-- sighted: the game and the job.
local function rig(level: number): (Core.Game, State.Mission)
  for seed = 1, 200 do
    local game = newGame(seed)
    local state = game.state
    state.standings.vessari = Assault.STANDING[level]
    local offer = defences(game, state.player.home)[level]
    if offer and offer.system == 1 then
      assert(submit(game, { kind = "AcceptMission", actor = 0, what = offer.key }))
      local mission = state.missions[state.missionIds[1]]
      assert(submit(game, { kind = "Undock", actor = 0 }))
      at(game, mission.site)
      Core.TakeEvents(game)
      steps(game, 2)
      return game, mission
    end
  end
  error(`no history seed up to 200 has a level {level} defence job in the home system`)
end

-- Take the pilot home: put by the home station, and docked there.
local function goHome(game: Core.Game)
  local state = game.state
  local home = state.player.home
  local me = state.balls[state.player.ship]
  local station = assert(Space.Object(state, home))
  me.x, me.y, me.z = station.x + station.radius + 500, station.y, station.z
  Space.AssignGrid(state, me)
  assert(submit(game, { kind = "Dock", actor = 0, target = home }))
  for _ = 1, 600 do
    if state.ships[state.player.ship].docked == home then
      return
    end
    Core.Step(game)
  end
  error("the pilot did not get home")
end

suite:Case("the seventh agent has a defence job at each level the pilot's standing opens: a rig to hold against a camp's worth of waves", function(t)
  local game = newGame()
  local state = game.state
  local home = state.player.home
  for _, case in { { -3, 0 }, { 0, 1 }, { 1, 2 }, { 3, 3 }, { 5, 4 } } do
    state.standings.vessari = case[1]
    t.eq(#defences(game, home), case[2], `at a standing of {case[1]}`)
  end
  for level, offer in defences(game, home) do
    -- An assault to the rules, to hold; one place; as many to destroy as its waves bring.
    t.eq({ offer.kind, offer.aim, offer.level, #offer.ends, offer.ends[1], offer.slot } :: { any },
      { "assault", "hold", level, 1, #offer.waves, Missions.OFFERS + 4 } :: { any })
    t.eq(offer.need, (Assault.Count(offer.waves)))
    t.eq(Missions.Title(offer), `Defence, level {level}: a rig against {offer.need}`)
    -- It pays a quarter more than clearing a camp of the same keepers would.
    -- (before what the agent adds for a pilot they think well of)
    local clear = Assault.Pay(level, offer.waves, "clear")
    local hold = Assault.Pay(level, offer.waves, "hold")
    t.eq(hold, math.floor(clear * Assault.HOLD_PAY))
    t.ok(offer.reward >= hold)
    t.ok(offer.agent ~= "", "nobody gives it")
  end
  -- It is not the fourth agent's: each has their own, and taking the one leaves the other.
  t.eq(#assaults(game, home), 4)
  t.ok(defences(game, home)[1].agent ~= assaults(game, home)[1].agent)
  t.ok((submit(game, { kind = "AcceptMission", actor = 0, what = defences(game, home)[2].key })))
  t.eq({ #defences(game, home), #assaults(game, home), state.holds[home] }, { 0, 4, 1 })
  t.eq(Missions.Line(state.missions[state.missionIds[1]]), "defence")
end)

suite:Case("at the place the rig stands from when the pilot comes, most of those who come go for it, and with all of them down and the rig standing the job is done", function(t)
  local game, mission = rig(2)
  local state = game.state
  local home = state.player.home
  -- The place is on the charts under its own name, and the rig is there: the faction's, a works, a few kilometres out.
  local place = assert(Space.Object(state, mission.site))
  t.ok(string.find(place.name, "Survey Rig", 1, true) ~= nil, `the place is called {place.name}`)
  local ward = assert(state.ships[mission.mark], "no rig")
  local ball = assert(state.balls[ward.id], "the rig is not in space")
  t.eq({ ward.type, ward.owner, Ships.byId[ward.type].class, ball.grid } :: { any }, { Assault.RIGS[2], "vessari", "works", mission.site } :: { any })
  local out = math.sqrt((ball.x - place.x) ^ 2 + (ball.z - place.z) ^ 2)
  t.ok(out >= Assault.RIG_OUT[1] and out <= Assault.RIG_OUT[2], `the rig is {out} m out`)
  t.eq(state.pilots[ward.id], nil, "the rig is nobody's to fly")
  -- The first wave came with the pilot; nobody waits for anybody.
  local first = keepers(game, mission.site)
  t.eq({ #first, mission.wave, mission.done }, { #mission.waves[1], 1, 0 })
  -- Two in three of them are after the rig, the rest after the pilot: over the three waves, by what they have picked.
  steps(game, Assault.PRESS - 5)
  t.eq(mission.wave, 1, "the second wave came early")
  steps(game, 10)
  t.eq({ mission.wave, #keepers(game, mission.site) }, { 2, #mission.waves[1] + #mission.waves[2] }, "the second wave waits for nobody")
  steps(game, Assault.PRESS + 5)
  t.eq({ mission.wave, #keepers(game, mission.site) }, { 3, mission.need })
  local onRig, onPilot = 0, 0
  for _, id in keepers(game, mission.site) do
    local prey = state.pilots[id].prey
    onRig += if prey == ward.id then 1 else 0
    onPilot += if prey == state.player.ship then 1 else 0
  end
  t.eq(onRig + onPilot, mission.need)
  t.ok(onRig >= onPilot and onRig > 0, `{onRig} are on the rig and {onPilot} on the pilot`)
  -- Whoever is after the rig is who the pilot's drones and hired pilots go for.
  t.ok(Pirates.Hunting(state, state.balls[state.player.ship]) ~= 0)
  -- The rig has taken hurt by now, and stands.
  t.ok(ball.vitals.shield < ball.vitals.shieldMax, "nobody has fired on the rig")
  t.ok(state.missions[mission.id] ~= nil and state.balls[ward.id] ~= nil)
  -- All of them down: done, said so, and nobody else comes.
  Core.TakeEvents(game)
  for index, id in keepers(game, mission.site) do
    Aftermath.Destroy(state, id, state.player.ship, game.events)
    t.eq(mission.done, index)
  end
  local held = said(game, "AssaultCleared")
  t.ok(held ~= nil and (held :: any).aim == "hold", "nobody said the rig was held")
  steps(game, Assault.PRESS + Assault.BREATHER + 5)
  t.eq({ #keepers(game, mission.site), mission.wave }, { 0, 3 })
  -- In the save, with the rig out.
  local data, length = Core.Save(game)
  t.eq(Core.Hash(Core.Load(data, length)), Core.Hash(game))
  -- Paid at the station; and the rig goes when the job does.
  goHome(game)
  local wallet, credit = state.wallet, Missions.Standing(state, "vessari")
  t.ok((submit(game, { kind = "CompleteMission", actor = 0, target = mission.id })))
  t.eq(state.wallet - wallet, mission.reward)
  t.ok(Missions.Standing(state, "vessari") > credit)
  t.eq({ state.ships[ward.id], state.balls[ward.id], state.sites[mission.site].gone } :: { any }, { nil, nil, true } :: { any })
  -- The agent's next is another.
  local next = defences(game, home)
  t.ok(#next > 0 and next[1].key ~= mission.key, "the agent has the same job again")
end)

suite:Case("a rig destroyed is the job lost, at once, at the cost of having given it up; and one given up takes its rig with it", function(t)
  local game, mission = rig(1)
  local state = game.state
  local ward = mission.mark
  local first = keepers(game, mission.site)
  t.ok(#first > 0)
  local credit = Missions.Standing(state, "vessari")
  local agent = Missions.Regard(state, mission.station, mission.slot)
  Core.TakeEvents(game)
  -- Whoever destroys it.
  Aftermath.Destroy(state, ward, first[1], game.events)
  steps(game, 1)
  local lost, failed = false, false
  for _, event in Core.TakeEvents(game) do
    lost = lost or (event.kind == "WardLost" and event.mission == mission.id)
    failed = failed or (event.kind == "MissionFailed" and event.mission == mission.id)
  end
  t.ok(lost and failed, "nobody said the rig was destroyed and the job lost")
  t.eq({ state.missions[mission.id], #state.missionIds, state.sites[mission.site].gone } :: { any }, { nil, 0, true } :: { any })
  t.near(credit - Missions.Standing(state, "vessari"), 2 * mission.standing, 1e-9)
  t.near(agent - Missions.Regard(state, mission.station, mission.slot), Missions.REGARD.lost, 1e-9)
  t.eq(#keepers(game, mission.site), 0, "those who came for it are still about")
  t.eq(state.missionsDone, 0)
  -- The agent has another, when the pilot is back (to one the faction still gives work to: the least it
  -- does at was where this pilot stood).
  goHome(game)
  t.eq(#defences(game, state.player.home), 0)
  state.standings.vessari = 0
  local again = defences(game, state.player.home)
  t.ok(#again == 1 and again[1].key ~= mission.key, "the agent should have another job, and not the one that was lost")

  -- Given up with the rig standing: the rig goes with the place.
  local other, job = rig(1)
  local standing = other.state.ships[job.mark]
  t.ok(standing ~= nil)
  goHome(other)
  t.ok((submit(other, { kind = "AbandonMission", actor = 0, target = job.id })))
  t.eq({ other.state.ships[job.mark], other.state.balls[job.mark], #keepers(other, job.site) } :: { any }, { nil, nil, 0 } :: { any })

  -- A save from before there were defence jobs: no agent has given any.
  local plain = newGame()
  local now, nowLength = Core.Save(plain)
  local file = Codec.Decode(now, nowLength)
  file.saveVersion = 57
  file.state.holds = nil
  local old, oldLength = Codec.Encode(file)
  local loaded = Core.Load(old, oldLength)
  t.eq(loaded.state.holds, {})
  t.eq(Core.Hash(loaded), Core.Hash(plain))
end)

-- A game in which the home station's seventh agent has given two jobs
-- already, so that the next is an escort; that one, of a level, in the
-- home system, taken, and the pilot at the place with the tender
-- sighted: the game and the job.
local function convoy(level: number): (Core.Game, State.Mission)
  for seed = 1, 200 do
    local game = newGame(seed)
    local state = game.state
    state.standings.vessari = math.max(0, Assault.STANDING[level])
    state.holds[state.player.home] = Assault.ESCORTS - 1
    local offer = defences(game, state.player.home)[level]
    if offer and offer.system == 1 then
      assert(Missions.Escort(offer), "the agent's third job should be an escort")
      assert(submit(game, { kind = "AcceptMission", actor = 0, what = offer.key }))
      local mission = state.missions[state.missionIds[1]]
      assert(submit(game, { kind = "Undock", actor = 0 }))
      at(game, mission.site)
      Core.TakeEvents(game)
      steps(game, 2)
      return game, mission
    end
  end
  error(`no history seed up to 200 has a level {level} escort in the home system`)
end

suite:Case("every third job of the seventh agent's is an escort: a tender to see through, on the terms of the rig", function(t)
  local game = newGame()
  local state = game.state
  local home = state.player.home
  state.standings.vessari = 5
  -- (and every other one of those a convoy, which is an escort that goes somewhere)
  for given, aim in { [0] = "hold", "hold", "escort", "hold", "hold", "convoy", "hold", "hold", "escort" } do
    state.holds[home] = given
    for level, offer in defences(game, home) do
      t.eq({ Missions.Escort(offer), Missions.Convoy(offer), offer.aim, Missions.Line(offer) } :: { any },
        { aim ~= "hold", aim == "convoy", aim, "defence" } :: { any }, `job {given + 1}, level {level}`)
    end
  end
  state.holds[home] = 2
  for level, offer in defences(game, home) do
    -- One thing to do, which is the tender getting there; the same waves, and the pay of holding against them.
    local ships = Assault.Count(offer.waves)
    t.eq({ offer.kind, offer.need, #offer.ends, offer.ends[1] } :: { any }, { "assault", 1, 1, #offer.waves } :: { any })
    t.eq(Missions.Title(offer), `Escort, level {level}: a tender past {ships}`)
    t.eq((Assault.Pay(level, offer.waves, "escort")), (Assault.Pay(level, offer.waves, "hold")))
  end
  t.eq(#assaults(game, home), 4)
end)

suite:Case("the tender waits by the middle of its place and flies out; those who come do not wait, and with the tender clear the job is done, whoever is left", function(t)
  local game, mission = convoy(2)
  local state = game.state
  local home = state.player.home
  local place = assert(Space.Object(state, mission.site))
  t.ok(string.find(place.name, "Convoy Route", 1, true) ~= nil, `the place is called {place.name}`)
  -- The tender: the faction's, nobody's to fly, by the middle of the place, and on its way out.
  local ward = assert(state.ships[mission.mark], "no tender")
  local ball = assert(state.balls[ward.id], "the tender is not in space")
  t.eq({ ward.type, ward.owner, ball.grid, ball.mode } :: { any }, { Assault.TENDERS[2], "vessari", mission.site, "goto" } :: { any })
  t.eq(state.pilots[ward.id], nil)
  local function out(): number
    return math.sqrt((ball.x - place.x) ^ 2 + (ball.y - place.y) ^ 2 + (ball.z - place.z) ^ 2)
  end
  t.ok(out() < Assault.TENDER_FROM + 500, `the tender is {out()} m out`)
  -- The first wave came with the pilot, and the next does not wait for it.
  t.eq({ #keepers(game, mission.site), mission.wave, mission.done }, { #mission.waves[1], 1, 0 })
  steps(game, Assault.PRESS + 5)
  t.eq(mission.wave, 2, "the second wave waits for nobody")
  t.ok(out() > Assault.TENDER_FROM + 5000, "the tender has not moved")
  -- Most of them are after the tender, and the pilot's drones and hired pilots would go for those.
  local onTender = 0
  for _, id in keepers(game, mission.site) do
    onTender += if state.pilots[id].prey == ward.id then 1 else 0
  end
  t.ok(onTender > 0, "nobody is after the tender")
  t.ok(Pirates.Hunting(state, state.balls[state.player.ship]) ~= 0)
  -- One of them destroyed is a bounty, and no part of the job.
  local wallet = state.wallet
  local first = keepers(game, mission.site)[1]
  local bounty = state.pilots[first].bounty
  Aftermath.Destroy(state, first, state.player.ship, game.events)
  t.eq({ state.wallet - wallet, mission.done }, { bounty, 0 })
  -- In the save, on its way.
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  -- Through: put as far out as it has to get, it is clear at once, and gone.
  Core.TakeEvents(game)
  local scale = (Assault.TENDER_OUT + 100) / out()
  ball.x, ball.y, ball.z = place.x + (ball.x - place.x) * scale, place.y + (ball.y - place.y) * scale, place.z + (ball.z - place.z) * scale
  steps(game, 1)
  local through = said(game, "AssaultCleared")
  t.ok(through ~= nil and (through :: any).aim == "escort", "nobody said the tender was through")
  t.eq({ mission.done, state.ships[ward.id], state.balls[ward.id] } :: { any }, { 1, nil, nil } :: { any })
  -- Whoever is left is still there, and nobody else comes.
  local left, wave = #keepers(game, mission.site), mission.wave
  t.ok(left > 0)
  steps(game, Assault.PRESS + Assault.BREATHER + 5)
  t.eq({ mission.wave, #keepers(game, mission.site) }, { wave, left })
  -- Paid at the station; the place goes, and they with it; and the agent's next is a rig again.
  goHome(game)
  local had = state.wallet
  t.ok((submit(game, { kind = "CompleteMission", actor = 0, target = mission.id })))
  t.eq(state.wallet - had, mission.reward)
  t.eq({ #keepers(game, mission.site), state.sites[mission.site].gone } :: { any }, { 0, true } :: { any })
  local next = defences(game, home)
  t.ok(#next > 0 and not Missions.Escort(next[1]), "the agent's fourth job should be a rig to hold")
end)

suite:Case("a tender destroyed is the job lost, and is said to be a tender; one left alone flies out by itself", function(t)
  local game, mission = convoy(1)
  local state = game.state
  local ward = mission.mark
  local credit = Missions.Standing(state, "vessari")
  Core.TakeEvents(game)
  Aftermath.Destroy(state, ward, keepers(game, mission.site)[1], game.events)
  steps(game, 1)
  local lost, failed = false, ""
  for _, event in Core.TakeEvents(game) do
    lost = lost or (event.kind == "WardLost" and event.mission == mission.id and event.escort == true)
    failed = if event.kind == "MissionFailed" and event.mission == mission.id then event.title else failed
  end
  t.ok(lost, "nobody said the tender was destroyed")
  t.eq(failed, `Escort, level 1: a tender past {(Assault.Count(mission.waves))}`)
  t.eq({ state.missions[mission.id], #state.missionIds } :: { any }, { nil, 0 } :: { any })
  t.near(credit - Missions.Standing(state, "vessari"), 2 * mission.standing, 1e-9)

  -- Nobody about (the pilot gone, and those who came with them): it gets there by itself, and the job is done.
  local other, job = convoy(1)
  local tender = other.state.balls[job.mark]
  for _, id in keepers(other, job.site) do
    Aftermath.Destroy(other.state, id, other.state.player.ship, other.events)
  end
  goHome(other)
  -- (asked for the pay before it is in)
  t.eq(refused(other, { kind = "CompleteMission", actor = 0, target = job.id }), "the tender is still to see through")
  local arrived = false
  for _ = 1, 600 do
    Core.Step(other)
    if job.done >= job.need then
      arrived = true
      break
    end
  end
  t.ok(arrived, "the tender did not get clear by itself")
  t.eq({ other.state.balls[tender.id], job.wave } :: { any }, { nil, 1 } :: { any })
  t.ok((submit(other, { kind = "CompleteMission", actor = 0, target = job.id })))
end)

-- A game in which the home station's seventh agent has given five jobs
-- already, so that the next is a convoy; that one, of a level, taken,
-- and the pilot at the place with the tender sighted: the game and the
-- job.
-- ('abroad': one whose place is in a neighbour's system, the pilot put
-- there by hand; else one in the station's own.)
local function inbound(level: number, abroad: boolean?): (Core.Game, State.Mission)
  for seed = 1, 200 do
    local game = newGame(seed)
    local state = game.state
    state.standings.vessari = math.max(0, Assault.STANDING[level])
    state.holds[state.player.home] = Assault.CONVOYS - 1
    local offer = defences(game, state.player.home)[level]
    if offer and (offer.system ~= 1) == (abroad == true) then
      assert(Missions.Convoy(offer), "the agent's sixth job should be a convoy")
      assert(submit(game, { kind = "AcceptMission", actor = 0, what = offer.key }))
      local mission = state.missions[state.missionIds[1]]
      assert(submit(game, { kind = "Undock", actor = 0 }))
      state.balls[state.player.ship].system = mission.system
      at(game, mission.site)
      Core.TakeEvents(game)
      steps(game, 2)
      return game, mission
    end
  end
  error(`no history seed up to 200 has a level {level} convoy {if abroad then "in a neighbour's system" else "in the home system"}`)
end

suite:Case("every sixth job of the seventh agent's is a convoy: a tender to see in to the station, or to the gate that leads to it, for more pay", function(t)
  local game = newGame()
  local state = game.state
  local home = state.player.home
  state.standings.vessari = 5
  state.holds[home] = Assault.CONVOYS - 1
  local offers = defences(game, home)
  t.eq(#offers, 4)
  for level, offer in offers do
    local ships = Assault.Count(offer.waves)
    -- Two things to count: the tender getting away from the place, and getting in. The last wave is kept for the station.
    t.eq({ offer.aim, offer.need, #offer.ends, offer.ends[1] } :: { any }, { "convoy", 2, 1, #offer.waves - 1 } :: { any })
    -- (in the station's system, or a neighbour's)
    t.ok(offer.system == 1 or table.find(state.galaxy.systems[1].neighbors, offer.system) ~= nil, `a convoy in system {offer.system}`)
    t.ok(#offer.waves >= 2, "a convoy wants a wave for the place and one for the station")
    t.eq(Missions.Title(offer), `Convoy, level {level}: a tender in past {ships}`)
    local escort, convoy = Assault.Pay(level, offer.waves, "escort"), Assault.Pay(level, offer.waves, "convoy")
    t.ok(convoy > escort, `a convoy pays {convoy} and an escort {escort}`)
    t.eq(convoy, math.floor((Assault.Pay(level, offer.waves, "clear")) * Assault.CONVOY_PAY))
  end
end)

suite:Case("a convoy's tender gets clear of its place and warps on to the station, where the last wave is waiting; the job is done when it docks", function(t)
  local game, mission = inbound(1)
  local state = game.state
  local home = state.player.home
  local place = assert(Space.Object(state, mission.site))
  local station = assert(Space.Object(state, home))
  t.ok(string.find(place.name, "Convoy Route", 1, true) ~= nil, `the place is called {place.name}`)
  local ward = assert(state.ships[mission.mark], "no tender")
  local ball = assert(state.balls[ward.id], "the tender is not in space")
  t.eq({ ward.type, ball.grid, ball.mode, mission.wave, mission.done } :: { any }, { Assault.TENDERS[1], mission.site, "goto", 1, 0 } :: { any })
  -- Not paid for yet, whatever is asked.
  -- Far enough out, it is away to the station: and that is half the job.
  Core.TakeEvents(game)
  local function out(): number
    return math.sqrt((ball.x - place.x) ^ 2 + (ball.y - place.y) ^ 2 + (ball.z - place.z) ^ 2)
  end
  local scale = (Assault.TENDER_OUT + 100) / out()
  ball.x, ball.y, ball.z = place.x + (ball.x - place.x) * scale, place.y + (ball.y - place.y) * scale, place.z + (ball.z - place.z) * scale
  steps(game, 1)
  local away = said(game, "WardAway")
  t.ok(away ~= nil and (away :: any).station == home and (away :: any).ward == ward.id, "nobody said the tender was away")
  t.eq({ mission.done, mission.need, ball.warp ~= nil } :: { any }, { 1, 2, true } :: { any })
  -- In the save, on its way.
  local data, length = Core.Save(game)
  t.eq(Core.Hash(Core.Load(data, length)), Core.Hash(game))
  -- Nobody else comes to the place it has left.
  sweep(game, mission.site)
  steps(game, Assault.BREATHER + 5)
  t.eq({ mission.wave, #keepers(game, mission.site) }, { 1, 0 })
  -- It lands off the station, the last wave comes for it there, and it makes for the dock.
  local landed = false
  for _ = 1, 900 do
    Core.Step(game)
    if state.balls[ward.id] and ball.warp == nil and ball.grid == home then
      landed = true
      break
    end
  end
  t.ok(landed, "the tender did not get to the station")
  steps(game, 2)
  local waiting = keepers(game, mission.site)
  t.eq({ mission.wave, #waiting, mission.done }, { #mission.waves, #mission.waves[#mission.waves], 1 })
  t.ok(ball.intent ~= nil and (ball.intent :: any).kind == "dock" and (ball.intent :: any).target == home, "the tender is not making for the dock")
  local off = Space.Gap(ball :: any, station :: any)
  t.ok(off > Assault.CONVOY_IN - 6000 and off < Assault.CONVOY_IN + 6000, `the tender landed {off} m off the station`)
  local after = 0
  for _, id in waiting do
    after += if state.pilots[id].prey == ward.id then 1 else 0
    local theirs = state.balls[id]
    local far = math.sqrt((theirs.x - ball.x) ^ 2 + (theirs.y - ball.y) ^ 2 + (theirs.z - ball.z) ^ 2)
    t.ok(far < Assault.CONVOY_WAIT[2] + 6000, `one of the last wave is {far} m from the tender`)
  end
  steps(game, 5)
  for _, id in keepers(game, mission.site) do
    after += if state.pilots[id].prey == ward.id then 1 else 0
  end
  t.ok(after > 0, "nobody of the last wave is after the tender")
  -- Seen off, it gets in: and the job is done, and the tender no part of the game.
  goHome(game)
  t.eq(refused(game, { kind = "CompleteMission", actor = 0, target = mission.id }), "the tender is still to see in")
  for _, id in keepers(game, mission.site) do
    Aftermath.Destroy(state, id, state.player.ship, game.events)
  end
  Core.TakeEvents(game)
  local inAt = 0
  for tick = 1, 900 do
    Core.Step(game)
    if mission.done >= mission.need then
      inAt = tick
      break
    end
  end
  t.ok(inAt > 0, "the tender did not get in")
  local cleared = said(game, "AssaultCleared")
  t.ok(cleared ~= nil and (cleared :: any).aim == "convoy", "nobody said the tender was in")
  t.eq({ mission.done, state.ships[ward.id], state.balls[ward.id] } :: { any }, { 2, nil, nil } :: { any })
  print(`     convoy: the tender landed {math.floor(off)} m off the station and was in {inAt} s after the last of them was down`)
  local had = state.wallet
  t.ok((submit(game, { kind = "CompleteMission", actor = 0, target = mission.id })))
  t.eq(state.wallet - had, mission.reward)
  -- And the agent's next is a rig again.
  local next = defences(game, home)
  t.ok(#next > 0 and not Missions.Escort(next[1]), "the agent's seventh job should be a rig to hold")
end)

suite:Case("a convoy's tender destroyed off the station is the job lost, as one destroyed at its place is", function(t)
  local game, mission = inbound(1)
  local state = game.state
  local home = state.player.home
  local place = assert(Space.Object(state, mission.site))
  local ball = assert(state.balls[mission.mark])
  local scale = (Assault.TENDER_OUT + 100) / math.sqrt((ball.x - place.x) ^ 2 + (ball.y - place.y) ^ 2 + (ball.z - place.z) ^ 2)
  ball.x, ball.y, ball.z = place.x + (ball.x - place.x) * scale, place.y + (ball.y - place.y) * scale, place.z + (ball.z - place.z) * scale
  local landed = false
  for _ = 1, 900 do
    Core.Step(game)
    if state.balls[mission.mark] and ball.warp == nil and ball.grid == home then
      landed = true
      break
    end
  end
  t.ok(landed, "the tender did not get to the station")
  steps(game, 2)
  local credit = Missions.Standing(state, "vessari")
  Core.TakeEvents(game)
  Aftermath.Destroy(state, mission.mark, keepers(game, mission.site)[1], game.events)
  steps(game, 1)
  local lost, failed = false, ""
  for _, event in Core.TakeEvents(game) do
    lost = lost or (event.kind == "WardLost" and event.mission == mission.id and event.escort == true)
    failed = if event.kind == "MissionFailed" and event.mission == mission.id then event.title else failed
  end
  t.ok(lost, "nobody said the tender was destroyed")
  t.eq(failed, `Convoy, level 1: a tender in past {(Assault.Count(mission.waves))}`)
  t.eq({ state.missions[mission.id], #state.missionIds } :: { any }, { nil, 0 } :: { any })
  t.near(credit - Missions.Standing(state, "vessari"), 2 * mission.standing, 1e-9)
  -- (and those who were waiting for it are gone with the job)
  t.eq(#keepers(game, mission.site), 0)
end)

suite:Case("a convoy in a neighbour's system is seen to the gate that leads home, and through it", function(t)
  local game, mission = inbound(1, true)
  local state = game.state
  local home = state.player.home
  t.ok(mission.system ~= 1)
  local gate = assert(Space.Object(state, mission.to), "the convoy is going nowhere")
  t.eq({ gate.kind, gate.to, Space.SystemOf(state, gate.id) } :: { any }, { "gate", 1, mission.system } :: { any })
  local place = assert(Space.Object(state, mission.site))
  local ward = assert(state.ships[mission.mark], "no tender")
  local ball = assert(state.balls[ward.id], "the tender is not in space")
  -- Clear of its place, it is away to the gate.
  Core.TakeEvents(game)
  local scale = (Assault.TENDER_OUT + 100) / math.sqrt((ball.x - place.x) ^ 2 + (ball.y - place.y) ^ 2 + (ball.z - place.z) ^ 2)
  ball.x, ball.y, ball.z = place.x + (ball.x - place.x) * scale, place.y + (ball.y - place.y) * scale, place.z + (ball.z - place.z) * scale
  steps(game, 1)
  local away = said(game, "WardAway")
  t.ok(away ~= nil and (away :: any).to == gate.id, "nobody said the tender was away to the gate")
  t.eq(mission.done, 1)
  sweep(game, mission.site)
  -- It lands off the gate, the last wave is there, and it makes for the gate.
  local landed = false
  for _ = 1, 900 do
    Core.Step(game)
    if state.balls[ward.id] and ball.warp == nil and ball.grid == gate.id then
      landed = true
      break
    end
  end
  t.ok(landed, "the tender did not get to the gate")
  steps(game, 2)
  t.eq({ mission.wave, #keepers(game, mission.site) }, { #mission.waves, #mission.waves[#mission.waves] })
  t.ok(ball.intent ~= nil and (ball.intent :: any).kind == "jump" and (ball.intent :: any).target == gate.id, "the tender is not making for the gate")
  -- Seen off, it goes through: and the job is done, and the tender no part of the game.
  sweep(game, mission.site)
  Core.TakeEvents(game)
  local through = 0
  for tick = 1, 900 do
    Core.Step(game)
    if mission.done >= mission.need then
      through = tick
      break
    end
  end
  t.ok(through > 0, "the tender did not get through")
  local cleared = said(game, "AssaultCleared")
  t.ok(cleared ~= nil and (cleared :: any).aim == "convoy" and (cleared :: any).through == true, "nobody said the tender was through the gate")
  t.eq({ mission.done, state.ships[ward.id], state.balls[ward.id] } :: { any }, { 2, nil, nil } :: { any })
  -- In the save, and paid at the station.
  local data, length = Core.Save(game)
  t.eq(Core.Hash(Core.Load(data, length)), Core.Hash(game))
  state.balls[state.player.ship].system = 1
  goHome(game)
  local had = state.wallet
  t.ok((submit(game, { kind = "CompleteMission", actor = 0, target = mission.id })))
  t.eq(state.wallet - had, mission.reward)
  t.eq(state.sites[mission.site].gone, true)
  t.ok(home == mission.station)
end)

return suite
