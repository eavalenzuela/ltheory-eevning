--!strict
-- Work a station has for a pilot (Assets/Missions).

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Items = require("@lt/Core/Assets/Items")
local Missions = require("@lt/Core/Assets/Missions")
local Ships = require("@lt/Core/Data/Ships")
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
  -- (the Vessari's are projectile guns and missiles: six kinds of gun and three launchers; and their five hulls)
  t.eq({ faction, blueprints, foreign, hulls } :: { any }, { "vessari", 9, 0, 5 } :: { any })
  state.standings[faction] = 2.5
  t.eq(refused(game, { kind = "RedeemLoyalty", actor = 0, type = "blueprint.frigate.javelin.ii" }), "needs a standing of 3 with them")
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

return suite
