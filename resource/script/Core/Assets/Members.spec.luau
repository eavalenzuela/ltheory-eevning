--!strict
-- The corporation's members (Assets/Members).

local Commerce = require("@lt/Core/Strategic/Commerce")
local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Economy = require("@lt/Core/Strategic/Economy")
local Items = require("@lt/Core/Assets/Items")
local Market = require("@lt/Core/Assets/Market")
local Members = require("@lt/Core/Assets/Members")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")
local Space = require("@lt/Core/Tactical/Space")
local Starbases = require("@lt/Core/Assets/Starbases")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local Test = require("@lt/Tool/Test")
local Types = require("@lt/Core/Data/Types")

local suite = Test.Suite("Members")

-- A game with a corporation founded and money in its account, the pilot
-- docked at home.
local function founded(): Core.Game
  local game = Core.New({ galaxySeed = 1, historySeed = 1, systems = 40, peaceful = true })
  local state = game.state
  state.wallet = 80000000
  assert(Core.Submit(game, { kind = "FoundCorporation", actor = state.player.ship, what = "Haven Holdings" }))
  Core.Step(game)
  assert(Core.Submit(game, { kind = "CorporationDeposit", actor = state.player.ship, quantity = 20000000 }))
  Core.Step(game)
  Core.TakeEvents(game)
  return game
end

local function refused(game: Core.Game, command: State.Command): string?
  command.actor = game.state.player.ship
  local ok, why = Core.Validate(game, command)
  return if ok then "(accepted)" else why
end

local function order(game: Core.Game, command: State.Command)
  command.actor = game.state.player.ship
  assert(Core.Submit(game, command))
  Core.Step(game)
end

-- Let so many hours go by for the members, and nothing else: what was said, by kind.
local function hours(game: Core.Game, count: number): { [string]: { any } }
  local state = game.state
  local said: { [string]: { any } } = {}
  for _ = 1, count do
    state.tick = (state.tick // Members.HOUR + 1) * Members.HOUR
    local events: { any } = {}
    Members.Step(state, events)
    for _, event in events do
      said[event.kind] = said[event.kind] or {}
      table.insert(said[event.kind], event)
    end
  end
  return said
end

-- A member of a trade, joined by hand: in the hull a member of that trade comes in.
local function member(game: Core.Game, trade: string, bears: number?): State.Member
  local state = game.state
  local hull = { miner = "frigate.courier", fighter = "frigate.akashi", hauler = "industrial.mizumushi", scout = "frigate.courier" }
  local one: State.Member = Members.Fill(state, { id = State.NewId(state), name = "Test " .. trade, trade = trade, people = "vessari", hull = hull[trade],
    bears = bears or 0.3, wealth = 0, earned = 0, paid = 0, joined = state.tick, system = 1, doing = "idle", call = 0, lean = 0, day = 0,
    ship = 0, task = "", goal = 0, since = 0, wait = 0, back = 0, refit = 0, lost = 0 })
  state.membership.members[one.id] = one
  table.insert(state.membership.memberIds, one.id)
  return one
end

suite:Case("pilots join a corporation both ways: some apply, and one open to it at a station can be asked", function(t)
  local plain = Core.New({ galaxySeed = 1, historySeed = 1, systems = 40, peaceful = true })
  t.eq({ Members.Room(plain.state), #Members.Open(plain.state, plain.state.player.home) }, { 0, 0 })
  t.eq(refused(plain, { kind = "SetTax", actor = 0, quantity = 10 }), "there is no corporation to be a member of: found one first")
  t.eq(next(hours(plain, 24 * 10)), nil, "somebody applied to a pilot with no corporation")
  local game = founded()
  local state = game.state
  t.eq({ Members.Room(state), state.membership.tax } :: { any }, { Members.ROOM, Members.TAX } :: { any })
  -- At a station: two who are open to it today, each with a trade, a hull of their own and a tax they will bear.
  local open = Members.Open(state, state.player.home)
  t.eq(#open, Members.OPEN)
  for _, one in open do
    t.ok(table.find(Members.TRADES, one.trade) ~= nil and Ships.byId[one.hull] ~= nil and #one.name > 2)
    t.ok(one.bears >= Members.BEARS[1] and one.bears <= Members.BEARS[2])
  end
  -- (asked at more tax than they will bear, no; at what they will, yes: and not twice in a day)
  state.membership.tax = open[1].bears + 0.05
  t.eq(string.sub(refused(game, { kind = "InviteMember", actor = 0, what = open[1].key }) or "", 1, 30), "they will not join at a tax of")
  state.membership.tax = Members.BEARS[1]
  t.eq(refused(game, { kind = "InviteMember", actor = 0, what = "nobody" }), "nobody here of that name is open to joining")
  order(game, { kind = "InviteMember", actor = 0, what = open[1].key })
  local joined = Members.List(state)
  t.eq(#joined, 1)
  t.eq({ joined[1].name, joined[1].trade, joined[1].hull, joined[1].system } :: { any }, { open[1].name, open[1].trade, open[1].hull, 1 } :: { any })
  t.eq(#Members.Open(state, state.player.home), Members.OPEN - 1)
  -- Others apply, over the days, and wait three: accepted or turned away, or gone when they have waited long enough.
  local said = hours(game, 24 * 30)
  local applied = #(said.MemberApplied or {} :: { any })
  t.ok(applied >= 3 and applied <= 20, `{applied} pilots applied in thirty days`)
  t.ok(#state.membership.applicants <= Members.WAITING)
  state.membership.applicants = { { key = "apply:test", name = "Ada Brook", trade = "miner", people = "vessari", hull = "frigate.courier",
    bears = 0.2, until_ = state.tick + Members.DAY }, { key = "apply:other", name = "Cal Dane", trade = "scout", people = "vessari",
    hull = "frigate.courier", bears = 0.2, until_ = state.tick + Members.DAY } }
  order(game, { kind = "AcceptMember", actor = 0, what = "apply:test" })
  order(game, { kind = "DeclineMember", actor = 0, what = "apply:other" })
  t.eq(#state.membership.applicants, 0)
  local found = false
  for _, one in Members.List(state) do
    found = found or (one.name == "Ada Brook" and one.trade == "miner")
  end
  t.ok(found, "the one accepted is not a member")
  -- (no more than there is room for; and one can be put out)
  for _ = #Members.List(state) + 1, Members.Room(state) do
    member(game, "miner")
  end
  table.insert(state.membership.applicants, { key = "apply:late", name = "Ena Finch", trade = "hauler", people = "vessari",
    hull = "industrial.mizumushi", bears = 0.2, until_ = state.tick + Members.DAY })
  t.eq(refused(game, { kind = "AcceptMember", actor = 0, what = "apply:late" }), `the corporation has room for {Members.ROOM} members`)
  local out = Members.List(state)[1]
  order(game, { kind = "ExpelMember", actor = 0, target = out.id })
  t.eq(state.membership.members[out.id], nil)
  local data, length = Core.Save(game)
  t.eq(Core.Hash(Core.Load(data, length)), Core.Hash(game))
end)

suite:Case("a member works at their own trade by the hour: what a miner digs and a fighter salvages goes in the corporation's hangar for a share, and money earned pays the tax", function(t)
  local game = founded()
  local state = game.state
  local commerce = state.commerce
  state.membership.tax = 0.2
  local account = state.corporation.wallet
  -- A miner: what they dig is in the corporation's hangar at its station
  -- there, and they are paid their share of what it goes for (2026-11-21).
  local miner = member(game, "miner")
  local station = Members.DepositAt(state, 1)
  local function held(prefix: string): number
    local count = 0
    for _, item in Items.In(state, station, "corporate") do
      count += if string.sub(item.type, 1, #prefix) == prefix then item.quantity else 0
    end
    return count
  end
  t.eq(station, state.player.home)
  hours(game, 1)
  t.ok(held("ore.") > 0, "a miner's hour put no ore in the corporation's hangar")
  t.eq({ miner.doing, miner.earned, miner.paid, miner.shares, miner.wealth } :: { any },
    { "mining", 0, 0, math.floor(miner.delivered * Members.SHARE), miner.shares } :: { any })
  t.ok(math.abs(miner.delivered - Members.EARNS.miner.frigate * (1 + Members.GRADE_EARNS * (miner.grade - 1)))
    < Types.Info("ore.titanite").basePrice * 2, "what was put in the hangar is not worth an hour's mining")
  t.eq(account - state.corporation.wallet, miner.shares)
  -- A fighter hunts, for more where it is less safe, half of it heads (money, taxed) and half salvage for the hangar;
  -- and is counted where a system is watched.
  local fighter = member(game, "fighter")
  hours(game, 1)
  t.eq({ fighter.doing, fighter.earned } :: { any }, { "hunting", Members.EARNS.fighter.frigate * 0.5 * Members.BOUNTY } :: { any })
  t.ok(held("salvage.") > 0 and fighter.delivered > 0, "a fighter's hour put no salvage in the corporation's hangar")
  t.eq({ Members.Watching(state, 1) }, { 1, Members.STANDS })
  t.eq((Members.Watching(state, 2)), 0)
  -- A hauler with nothing dearer anywhere near earns nothing: with iron short next door, they carry it there.
  local hauler = member(game, "hauler")
  hours(game, 1)
  t.eq({ hauler.doing, hauler.earned } :: { any }, { "idle", 0 } :: { any })
  local next = state.galaxy.systems[1].neighbors[1]
  local iron = Commerce.Index("mineral.iron") :: number
  Economy.SetStock(commerce, next, iron, commerce.nodes[next].target[iron] / 2)
  local there, here = commerce.nodes[next].stock[iron], commerce.nodes[1].stock[iron]
  hours(game, 1)
  t.eq(hauler.doing, "hauling")
  t.ok(hauler.earned > 0 and commerce.nodes[next].stock[iron] > there and commerce.nodes[1].stock[iron] < here, "no iron was carried to where it was short")
  -- A scout finds what is to be found where they are: a signal an hour.
  local scout = member(game, "scout")
  assert(Core.Submit(game, { kind = "Undock", actor = state.player.ship }))
  for _ = 1, 3 do
    Core.Step(game)
  end
  local unfound = 0
  for _, id in state.siteIds do
    unfound += if state.sites[id].system == 1 and state.sites[id].strength < 1 and not state.sites[id].gone then 1 else 0
  end
  t.ok(unfound >= 1, "the home system has nothing to find")
  local said = hours(game, 1)
  t.eq({ scout.doing, #said.MemberFound, said.MemberFound[1].name } :: { any }, { "scouting", 1, scout.name } :: { any })
  local left = 0
  for _, id in state.siteIds do
    left += if state.sites[id].system == 1 and state.sites[id].strength < 1 and not state.sites[id].gone then 1 else 0
  end
  t.eq(left, unfound - 1)
  for class, residual in Economy.Residual(commerce) do
    t.ok(math.abs(residual) * commerce.classes[class].par < 1, `the economy's books are out by {residual}`)
  end
end)

suite:Case("a member buys a better hull as they earn, and leaves when the tax is over what they will bear or the pickings stay thin", function(t)
  local game = founded()
  local state = game.state
  state.membership.tax = 0.1
  -- (the next hull of their trade, with a fifth over)
  -- (bought at their market, at what it asks: 2026-11-21)
  local fighter = member(game, "fighter")
  local market = Members.MarketOf(state, fighter)
  local asks = assert(Market.BuyCost(state, market, "destroyer.nozomi", 1), "the market has no Nozomi")
  local stock = Market.Quote(state, market, "destroyer.nozomi").stock
  fighter.wealth = asks * 1.2 + 10000000
  fighter.day = 1e9
  local said = hours(game, 24)
  t.eq(fighter.hull, "destroyer.nozomi")
  t.eq(said.MemberUpgraded[1].name, fighter.name)
  t.eq(Market.Quote(state, market, "destroyer.nozomi").stock, stock - 1)
  t.ok(fighter.wealth <= asks * 0.2 + 10000000 and Members.Prospect(state, fighter, 1) > Members.EARNS.fighter.frigate * 0.5)
  -- (and fitted it out from the same market, as their trade wants)
  t.eq({ fighter.fitFor, #fighter.fit } :: { any }, { "destroyer.nozomi", #Members.WantedFit("fighter", "destroyer.nozomi") } :: { any })
  -- (taxed over what they will bear: gone at the day's end)
  local miner = member(game, "miner", 0.15)
  state.membership.tax = 0.2
  said = hours(game, 24)
  t.eq(state.membership.members[miner.id], nil)
  local why = ""
  for _, event in said.MemberLeft do
    why = if event.name == miner.name then event.why else why
  end
  t.eq(why, "the tax")
  t.ok(state.membership.members[fighter.id] ~= nil, "one who bears the tax left too")
  -- (three days running with next to nothing: gone; for one not yet attached to the corporation)
  state.membership.tax = 0.1
  local hauler = member(game, "hauler")
  hauler.loyalty = 0
  said = hours(game, 24 * 2)
  t.ok(state.membership.members[hauler.id] ~= nil and hauler.lean == 2, "a hauler with nothing to carry should be counting the lean days")
  said = hours(game, 24)
  t.eq(state.membership.members[hauler.id], nil)
  t.eq(said.MemberLeft[#said.MemberLeft].why, "thin pickings")
end)

suite:Case("a member is a person: a grade that rises with work, a home, the hulls they own, what they want, a share the pilot sets, and a log of it all", function(t)
  local game = founded()
  local state = game.state
  -- One who joins: as good as the hull they come in needs, at home at the corporation's station, owning that hull, wanting something.
  for _ = 1, 40 do
    if #state.membership.applicants == 0 then
      hours(game, 24)
    end
  end
  local applicant = assert(state.membership.applicants[1], "nobody applied in forty days")
  order(game, { kind = "AcceptMember", actor = 0, what = applicant.key })
  local one = state.membership.members[state.membership.memberIds[#state.membership.memberIds]]
  local class = Ships.byId[one.hull].class
  t.ok(one.grade >= Members.CLASS_GRADE[class] and one.grade <= 5, "a grade too low for the hull they fly")
  t.eq({ one.home, one.clone, one.ships, one.loyalty, one.title, one.owed } :: { any },
    { state.player.home, state.player.home, { one.hull }, Members.LOYALTY_START, "", 0 } :: { any })
  t.ok(one.aim ~= nil and Members.AimProgress(state, one) < 1, "a new member wants nothing, or has it already")
  t.ok(string.find(state.membership.log[#state.membership.log].text, "joined", 1, true) ~= nil, "joining is not in the log")
  -- A grade rises with the hours worked at their trade.
  local miner = member(game, "miner")
  t.eq(miner.grade, 1)
  miner.practice = Members.GRADE_HOURS[2] - 1
  local said = hours(game, 1)
  t.eq({ miner.grade, said.MemberGraded and said.MemberGraded[1].name } :: { any }, { 2, miner.name } :: { any })
  -- (and an NPC member flies no hull above their grade)
  t.ok(not Members.CanFly(miner, assert(Members.HullFor("fighter", "vessari", "battleship"))), "a grade 2 flies a battleship")
  t.ok(Members.CanFly(miner, assert(Members.HullFor("fighter", "vessari", "cruiser"))), "a grade 2 cannot fly a cruiser")
  -- The share is the pilot's to set, and what they are paid is that share.
  order(game, { kind = "SetShare", actor = 0, quantity = 40 })
  t.eq(state.membership.share, 0.4)
  t.eq(refused(game, { kind = "SetShare", actor = 0, quantity = 120 }), "a share is a whole number of per cent, 100 at most")
  local before = miner.shares
  local delivered = miner.delivered
  hours(game, 1)
  t.eq(miner.shares - before, math.floor((miner.delivered - delivered) * 0.4))
  -- A corporation that cannot pay (nor the pilot for it: Corporation.Spend) owes; one it still owes at the day's end leaves.
  state.corporation.wallet, state.wallet = 0, 0
  said = hours(game, 24)
  t.eq(state.membership.members[miner.id], nil)
  local why = ""
  for _, event in (said.MemberLeft or {}) :: { any } do
    why = if event.name == miner.name then event.why else why
  end
  t.eq(why, "pay owed")
  -- The room: twenty, and twenty more a level of Hospitality.
  t.eq(Members.Room(state), Members.ROOM)
  state.skills.hospitality = 5
  t.eq(Members.Room(state), 120)
end)

suite:Case("members buy what they fly with at a real market: their trade's fit a module at a time, a fighter's charges as they run low; and less is brought in without it", function(t)
  local game = founded()
  local state = game.state
  local fighter = member(game, "fighter")
  local market = Members.MarketOf(state, fighter)
  t.eq(market, state.player.home)
  -- (come in fitted out: Members.Fill, as one who joins)
  local wanted = Members.WantedFit("fighter", fighter.hull)
  t.ok(#wanted >= 2 and #fighter.fit == #wanted and fighter.ammo == Members.AMMO_FULL and fighter.charge ~= "", "a fighter came in unfitted")
  local fitted = Members.Prospect(state, fighter, 1)
  -- With nothing on it, half as much, and with nothing to fire half that; they buy it back, as their money goes.
  fighter.fit = {}
  t.near(Members.Prospect(state, fighter, 1), fitted * Members.UNFITTED, 1)
  fighter.ammo = 0
  t.near(Members.Prospect(state, fighter, 1), fitted * Members.UNFITTED * 0.5, 1)
  fighter.wealth, fighter.day = 50000000, 1e9
  local said = hours(game, 24)
  -- (with that much they may have bought a better hull too, and fitted that)
  t.eq({ fighter.fitFor, #fighter.fit, fighter.ammo } :: { any },
    { fighter.hull, #Members.WantedFit("fighter", fighter.hull), Members.AMMO_FULL } :: { any })
  t.ok(fighter.wealth < 50000000, "nothing was paid for it")
  local fittedNote = false
  for _, note in state.membership.log do
    fittedNote = fittedNote or (note.member == fighter.id and string.find(note.text, "fitted", 1, true) ~= nil)
  end
  t.ok(fittedNote, "the fitting is not in the log")
  -- (charges are used by the hour)
  hours(game, 1)
  t.ok(fighter.ammo < Members.AMMO_FULL, "a fighter's hour fired nothing")
  local _ = said
end)

suite:Case("one of the player's own characters is set a hull and a budget: they buy the books it wants, then the hull once they can fly it, from the corporation's account", function(t)
  local game = founded()
  local state = game.state
  local events = {}
  local alt = assert(Members.JoinAlt(state, "alt-one", "Alt One", "fighter", { gunnery = 1 }, events))
  t.eq(refused(game, { kind = "SetBudget", actor = 0, target = alt.id, quantity = 50000000 }), "(accepted)")
  local npc = member(game, "fighter")
  t.eq(refused(game, { kind = "SetTarget", actor = 0, target = npc.id, what = "destroyer.nozomi" }),
    "only your own characters are set what to spend and fly: other members decide for themselves")
  order(game, { kind = "SetBudget", actor = 0, target = alt.id, quantity = 50000000 })
  order(game, { kind = "SetTarget", actor = 0, target = alt.id, what = "destroyer.nozomi" })
  local needs = Skills.Needs("destroyer.nozomi")
  t.ok(#needs > 0, "a Nozomi needs no skills")
  local account = state.corporation.wallet
  local said = hours(game, 24)
  -- (the books first: known now, at nothing yet)
  for _, need in needs do
    t.ok((alt.skills :: any)[need.skill] ~= nil, `{need.skill} was not learned`)
  end
  t.ok(said.MemberLearned ~= nil and said.MemberLearned[1].alt == "alt-one", "nobody was told what they learned")
  t.eq(alt.hull ~= "destroyer.nozomi", true)
  t.ok(alt.budget < 50000000 and state.corporation.wallet < account, "the books were not paid for out of the corporation's")
  -- (trained, they buy it, and fit it)
  for _, need in needs do
    (alt.skills :: any)[need.skill] = need.level
  end
  hours(game, 24)
  t.eq({ alt.hull, alt.fitFor } :: { any }, { "destroyer.nozomi", "destroyer.nozomi" } :: { any })
  t.ok(table.find(alt.ships, "destroyer.nozomi") ~= nil, "the Nozomi is not theirs")
  -- (nothing over the budget)
  order(game, { kind = "SetBudget", actor = 0, target = alt.id, quantity = 0 })
  alt.fit = {}
  hours(game, 24)
  t.eq(#alt.fit, 0)
end)

suite:Case("a save from before members were people loads with each made one: a grade, a home, their hull theirs, the share and the log", function(t)
  local game = founded()
  local state = game.state
  local one = member(game, "fighter")
  local data, length = Core.Save(game)
  local file = Codec.Decode(data, length)
  -- (as a save of version 91 had it)
  file.saveVersion = 91
  file.state.membership.share, file.state.membership.log = nil, nil
  for _, each in file.state.membership.members do
    for _, field in { "home", "clone", "grade", "practice", "ships", "implants", "aim", "loyalty", "title", "owed", "budget", "delivered",
      "shares", "dayGoods", "dayShare" } do
      each[field] = nil
    end
  end
  local old, oldLength = Codec.Encode(file)
  local loaded = Core.Load(old, oldLength).state
  local was = loaded.membership.members[one.id]
  t.eq({ loaded.membership.share, #loaded.membership.log, was.home, was.ships, was.grade, was.title, was.owed } :: { any },
    { Members.SHARE, 0, state.player.home, { one.hull }, Members.CLASS_GRADE[Ships.byId[one.hull].class], "", 0 } :: { any })
end)

suite:Case("a call is not an order: members of its trade go where it pays them to, and nobody else does", function(t)
  local game = founded()
  local state = game.state
  -- A second place: a tower of the pilot's in another system.
  local other = 0
  for id = 2, 40 do
    if other == 0 then
      for _, object in Space.Describe(state, id).objects do
        if object.kind == "moon" and other == 0 then
          Starbases.Raise(state, id, object, Structures.towerById["tower.vessari.small"], "player", object.x + object.radius * 3, object.y, object.z)
          other = id
        end
      end
    end
  end
  t.eq(Members.Places(state), { 1, other })
  t.eq(Members.Room(state), Members.ROOM + Members.ROOM_TOWER)
  local miner, fighter = member(game, "miner"), member(game, "fighter")
  miner.day, fighter.day = 1e9, 1e9
  -- (what a call can be, and where)
  t.eq(refused(game, { kind = "PostCall", actor = 0, what = "dance", target = other, quantity = 0 }), "a call is to defend, mine, haul or scout")
  t.eq(refused(game, { kind = "PostCall", actor = 0, what = "mine", target = 7, quantity = 0 }), "a call is for a system the corporation has a place in")
  order(game, { kind = "PostCall", actor = 0, what = "mine", target = other, quantity = 2000000 })
  t.eq(refused(game, { kind = "PostCall", actor = 0, what = "mine", target = other, quantity = 5 }), "that call is posted already")
  local call = state.membership.calls[1]
  local account = state.corporation.wallet
  local said = hours(game, 24)
  -- The miner has gone where the call pays; the fighter has no reason to.
  t.eq({ miner.system, miner.call }, { other, call.id })
  t.eq(said.CallAnswered[1].name, miner.name)
  t.ok(fighter.call == 0, "a fighter answered a call for miners")
  -- (and is paid what it promised, a day, out of the corporation's account)
  miner.day = 1e9
  local before = state.corporation.wallet
  local wealth = miner.wealth
  hours(game, 24)
  t.ok(before - state.corporation.wallet > 1000000 and miner.wealth - wealth >= 2000000, "the call's reward was not paid")
  t.ok(account > 0)
  -- Called off, nobody is answering it.
  order(game, { kind = "CancelCall", actor = 0, target = call.id })
  t.eq({ #state.membership.calls, miner.call }, { 0, 0 })
end)

return suite
