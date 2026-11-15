--!strict
-- The corporation's members (Assets/Members).

local Commerce = require("@lt/Core/Strategic/Commerce")
local Core = require("@lt/Core/Api")
local Economy = require("@lt/Core/Strategic/Economy")
local Members = require("@lt/Core/Assets/Members")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local Starbases = require("@lt/Core/Assets/Starbases")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local Test = require("@lt/Tool/Test")

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
  local hull = { miner = "frigate.courier", fighter = "frigate.akashi", hauler = "industrial.hauler", scout = "frigate.courier" }
  local one: State.Member = { id = State.NewId(state), name = "Test " .. trade, trade = trade, people = "vessari", hull = hull[trade],
    bears = bears or 0.3, wealth = 0, earned = 0, paid = 0, joined = state.tick, system = 1, doing = "idle", call = 0, lean = 0, day = 0,
    ship = 0, task = "", goal = 0, since = 0, wait = 0, back = 0, refit = 0, lost = 0 }
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
    hull = "industrial.hauler", bears = 0.2, until_ = state.tick + Members.DAY })
  t.eq(refused(game, { kind = "AcceptMember", actor = 0, what = "apply:late" }), `the corporation has room for {Members.ROOM} members`)
  local out = Members.List(state)[1]
  order(game, { kind = "ExpelMember", actor = 0, target = out.id })
  t.eq(state.membership.members[out.id], nil)
  local data, length = Core.Save(game)
  t.eq(Core.Hash(Core.Load(data, length)), Core.Hash(game))
end)

suite:Case("a member works at their own trade by the hour, keeps what they earn, and pays the corporation its tax", function(t)
  local game = founded()
  local state = game.state
  local commerce = state.commerce
  state.membership.tax = 0.2
  local account = state.corporation.wallet
  -- A miner: what they dig is in the system's stock, and they are paid what it goes for there.
  local miner = member(game, "miner")
  local ore = 0
  for _, id in { "ore.ferrite", "ore.silicate", "ore.cuprite", "ore.titanite" } do
    ore += commerce.nodes[1].stock[Commerce.Index(id) :: number]
  end
  hours(game, 1)
  local after = 0
  for _, id in { "ore.ferrite", "ore.silicate", "ore.cuprite", "ore.titanite" } do
    after += commerce.nodes[1].stock[Commerce.Index(id) :: number]
  end
  t.ok(after > ore, "a miner's hour put no ore in the system's stock")
  t.eq({ miner.doing, miner.earned, miner.paid, miner.wealth } :: { any },
    { "mining", Members.EARNS.miner.frigate, Members.EARNS.miner.frigate * 0.2, Members.EARNS.miner.frigate * 0.8 } :: { any })
  t.eq(state.corporation.wallet - account, Members.EARNS.miner.frigate * 0.2)
  -- A fighter hunts, for more where it is less safe; and is counted where a system is watched.
  local fighter = member(game, "fighter")
  hours(game, 1)
  t.eq({ fighter.doing, fighter.earned } :: { any }, { "hunting", Members.EARNS.fighter.frigate * 0.5 } :: { any })
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
  local fighter = member(game, "fighter")
  local price = Ships.byId["destroyer.nozomi"].basePrice
  fighter.wealth = price * 1.2
  fighter.day = 1e9
  local said = hours(game, 24)
  t.eq(fighter.hull, "destroyer.nozomi")
  t.eq(said.MemberUpgraded[1].name, fighter.name)
  t.ok(fighter.wealth < price and Members.Prospect(state, fighter, 1) > Members.EARNS.fighter.frigate * 0.5)
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
  -- (three days running with next to nothing: gone)
  state.membership.tax = 0.1
  local hauler = member(game, "hauler")
  said = hours(game, 24 * 2)
  t.ok(state.membership.members[hauler.id] ~= nil and hauler.lean == 2, "a hauler with nothing to carry should be counting the lean days")
  said = hours(game, 24)
  t.eq(state.membership.members[hauler.id], nil)
  t.eq(said.MemberLeft[#said.MemberLeft].why, "thin pickings")
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
