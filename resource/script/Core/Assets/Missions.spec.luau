--!strict
-- Work a station has for a pilot (Assets/Missions).

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Items = require("@lt/Core/Assets/Items")
local Missions = require("@lt/Core/Assets/Missions")
local Pirates = require("@lt/Core/Tactical/Pirates")
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
    local offers = Missions.Offers(state, state.player.home)
    t.eq(#offers, Missions.OFFERS)
    t.eq(Missions.Offers(state, state.player.home), offers)
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
  t.eq(#Core.Query.Missions(newGame()).offers, 3)
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
  t.eq(#Missions.Offers(state, state.player.home), Missions.OFFERS - 1)
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
  t.eq(#Core.Query.Missions(before).offers, 3)
end)

return suite
