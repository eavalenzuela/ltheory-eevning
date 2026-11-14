--!strict
-- Contracts: a station's board, through the Core's front door.

local Blueprints = require("@lt/Core/Data/Blueprints")
local Codec = require("@lt/Core/Persist/Codec")
local Contracts = require("@lt/Core/Assets/Contracts")
local Core = require("@lt/Core/Api")
local Items = require("@lt/Core/Assets/Items")
local Market = require("@lt/Core/Assets/Market")
local Modules = require("@lt/Core/Data/Modules")
local Ships = require("@lt/Core/Data/Ships")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")
local Types = require("@lt/Core/Data/Types")

local suite = Test.Suite("Contracts")

local DAY, HOUR = 86400, 3600

local function newGame(): (Core.Game, number)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  return game, game.state.player.home
end

local function order(t: Test.Context, game: Core.Game, command: State.Command)
  command.actor = game.state.player.ship
  local ok, reason = Core.Submit(game, command)
  t.ok(ok, `{command.kind} was refused: {tostring(reason)}`)
  Core.Step(game)
end

local function refused(game: Core.Game, command: State.Command): string?
  command.actor = game.state.player.ship
  local ok, reason = Core.Validate(game, command)
  return if ok then "(accepted)" else reason
end

local function hangar(game: Core.Game, type: string): number
  local count = 0
  for _, item in Items.In(game.state, game.state.player.home, "hangar") do
    if item.type == type then
      count += item.quantity
    end
  end
  return count
end

local function stack(game: Core.Game, type: string): State.Item
  for _, item in Items.In(game.state, game.state.player.home, "hangar") do
    if item.type == type then
      return item
    end
  end
  error(`no {type} in the hangar`, 2)
end

-- So many hours at the boards alone: what Core.Step does for them, an
-- hour at a time, and what came of the listings in them (not the
-- wallet's own events).
local function hours(game: Core.Game, n: number): { Contracts.Event }
  local state = game.state
  local events: { Contracts.Event } = {}
  state.tick -= state.tick % HOUR
  for _ = 1, n do
    state.tick += HOUR
    Contracts.Step(state, events)
  end
  local came: { Contracts.Event } = {}
  for _, event in events do
    if string.sub(event.kind, 1, 8) == "Contract" then
      table.insert(came, event)
    end
  end
  return came
end

local function lot(game: Core.Game, station: number, side: string, slot: number): Contracts.Lot
  return assert(Contracts.Lot(game.state, station, side, slot), `no {side} {slot} on the board`)
end

suite:Case("a station's board has lots for sale and lots wanted: the same all day, and others tomorrow", function(t)
  local game, home = newGame()
  local state = game.state
  local board = Contracts.Board(state, home)
  t.eq(#board, Contracts.OFFERS + Contracts.WANTS)
  t.eq(Contracts.Board(state, home), board, "asked again, it is the same board")
  -- A hull with what it would be fitted with, and something to fire.
  local ship = board[1]
  local hull = assert(Ships.byId[ship.stacks[1].type], "the first lot should be a hull's")
  t.eq({ ship.side, ship.slot, ship.stacks[1].quantity, ship.title } :: { any }, { "offer", 1, 1, `{hull.name}, fitted out` } :: { any })
  t.ok(#ship.stacks >= 3, "a hull, its fit and its rounds")
  t.ok(not hull.restricted and not hull.rare and hull.tech ~= 2 and not Ships.Capital(hull.class), hull.id)
  -- A copy of a blueprint.
  local copy = board[2]
  local blueprint, isCopy = Blueprints.Of(copy.stacks[1].type)
  t.ok(blueprint ~= nil and isCopy and #copy.stacks == 1, "the second lot should be a copy")
  -- A few of a module no station sells.
  local few = board[3]
  local module = assert(Modules.byId[few.stacks[1].type], "the third lot should be modules")
  t.ok(Types.Info(module.id).scarce and few.stacks[1].quantity >= 1 and few.stacks[1].quantity <= 3)
  -- And two lots wanted, of what nobody sells: paid for at more than its base price.
  for index = Contracts.OFFERS + 1, #board do
    local want = board[index]
    local info = Types.Info(want.stacks[1].type)
    t.eq({ want.side, want.slot, #want.stacks } :: { any }, { "want", index - Contracts.OFFERS, 1 } :: { any })
    t.ok(info.scarce and Market.Index(info.id) ~= nil, info.id)
    t.ok(want.price >= want.worth * 1.1 - 1 and want.price <= want.worth * 1.4, `{want.title} pays {want.price} for {want.worth}`)
  end

  -- Every lot, over a month and at every station of the first system: well made, and priced by what it is.
  local stations: { number } = {}
  for _, object in Core.Query.Objects(game, 1) do
    if object.kind == "station" then
      table.insert(stations, object.id)
    end
  end
  t.ok(#stations >= 2)
  local titles: { [string]: boolean } = {}
  local kinds = 0
  for day = 0, 29 do
    state.tick = day * DAY + 5
    for _, station in stations do
      local lots = Contracts.Board(state, station)
      t.eq(#lots, Contracts.OFFERS + Contracts.WANTS)
      for _, each in lots do
        t.ok(each.title ~= "" and #each.stacks > 0 and each.price > 0, each.key)
        t.eq(each.worth, Contracts.Base(each.stacks), each.key)
        for _, stack in each.stacks do
          t.ok(Types.Get(stack.type) ~= nil and stack.quantity >= 1 and stack.quantity % 1 == 0, `{each.key}: {stack.type}`)
        end
        local share = each.price / each.worth
        if each.side == "offer" and each.slot == 1 then
          t.ok(share >= 0.88 and share <= 1.07, `{each.title} at {share} of its worth`)
        elseif each.side == "offer" and each.slot == 2 then
          t.ok(share >= 0.8 and share <= 2.6, `{each.title} at {share} of its worth`)
        elseif each.side == "offer" then
          t.ok(share >= 1.0 and share <= 1.51, `{each.title} at {share} of its worth`)
        end
        if not titles[each.title] then
          titles[each.title] = true
          kinds += 1
        end
      end
    end
  end
  t.ok(kinds > 60, `a month of boards should have many different lots, and has {kinds}`)
  -- Tomorrow's board is not today's, and what is no station has none.
  state.tick = 5
  local today = Contracts.Board(state, home)
  state.tick = DAY + 5
  local tomorrow = Contracts.Board(state, home)
  t.ok(today[1].key ~= tomorrow[1].key)
  t.eq(Contracts.Board(state, 4242), {})
end)

suite:Case("a lot for sale is paid for and is in the hangar, and nobody else has it that day", function(t)
  local game, home = newGame()
  local state = game.state
  local ship = lot(game, home, "offer", 1)
  t.eq(refused(game, { kind = "AcceptContract", actor = 0, target = 1 }), if ship.price > state.wallet then "not enough credits" else "(accepted)")
  state.wallet = ship.price + 1000
  t.eq(refused(game, { kind = "AcceptContract", actor = 0, target = 9 }), "that is not on the board")
  local before: { number } = {}
  for index, stack in ship.stacks do
    before[index] = hangar(game, stack.type)
  end
  Core.TakeEvents(game)
  order(t, game, { kind = "AcceptContract", actor = 0, target = 1 })
  t.eq({ state.wallet, state.journal[#state.journal].reason } :: { any }, { 1000, "contract" } :: { any })
  for index, stack in ship.stacks do
    t.eq(hangar(game, stack.type) - before[index], stack.quantity, stack.type)
  end
  local accepted: any = nil
  for _, event in Core.TakeEvents(game) do
    accepted = if event.kind == "ContractAccepted" then event else accepted
  end
  t.eq({ accepted.title, accepted.price, accepted.station } :: { any }, { ship.title, ship.price, home } :: { any })
  -- It is off the board for the day, and the rest of the board is as it was.
  t.eq(Contracts.Lot(state, home, "offer", 1), nil)
  t.eq(#Contracts.Board(state, home), Contracts.OFFERS + Contracts.WANTS - 1)
  t.eq(refused(game, { kind = "AcceptContract", actor = 0, target = 1 }), "that is not on the board")
  -- The hull is a hull like any bought one: assembled, it is a ship.
  order(t, game, { kind = "Assemble", actor = 0, item = stack(game, ship.stacks[1].type).id })
  local ships = Core.Query.Ships(game, home)
  t.eq(ships[#ships].type, ship.stacks[1].type)
  -- Tomorrow there is another in its place, and yesterday's taking is forgotten when the next is taken.
  state.tick = DAY + 10
  local next = lot(game, home, "offer", 1)
  state.wallet = next.price
  order(t, game, { kind = "AcceptContract", actor = 0, target = 1 })
  t.eq({ #state.contractsTaken, state.wallet }, { 1, 0 })
  -- Not from space.
  order(t, game, { kind = "Undock", actor = 0 })
  for _ = 1, 20 do
    Core.Step(game)
  end
  t.eq(refused(game, { kind = "AcceptContract", actor = 0, target = 2 }), "not docked")
end)

suite:Case("a lot wanted is filled from the hangar, and pays more than a market would for so many", function(t)
  local game, home = newGame()
  local state = game.state
  local want = lot(game, home, "want", 1)
  local type, count = want.stacks[1].type, want.stacks[1].quantity
  local name = Types.Info(type).name
  t.eq(refused(game, { kind = "FillContract", actor = 0, target = 1 }), `needs {count} more {name} in the hangar here`)
  Items.Add(state, type, count + 3, home, "hangar")
  if count > 1 then
    Items.Take(state, stack(game, type), 4)
    t.eq(refused(game, { kind = "FillContract", actor = 0, target = 1 }), `needs 1 more {name} in the hangar here`)
    Items.Add(state, type, 4, home, "hangar")
  end
  -- (what the market here would give for the same lot, sold at once)
  local market = Core.Query.SellValue(game, home, type, count)
  local wallet = state.wallet
  Core.TakeEvents(game)
  order(t, game, { kind = "FillContract", actor = 0, target = 1 })
  t.eq({ state.wallet - wallet, hangar(game, type), state.journal[#state.journal].reason } :: { any }, { want.price, 3, "contract" } :: { any })
  local filled: any = nil
  for _, event in Core.TakeEvents(game) do
    filled = if event.kind == "ContractFilled" then event else filled
  end
  t.eq({ filled.title, filled.price } :: { any }, { want.title, want.price } :: { any })
  t.eq(Contracts.Lot(state, home, "want", 1), nil)
  t.eq(refused(game, { kind = "FillContract", actor = 0, target = 1 }), "that is not on the board")
  if count >= 8 then
    t.ok(want.price > market, `a want for {count} pays {want.price}, and the market would give {market}`)
  end
  -- The other want is still there.
  t.ok(Contracts.Lot(state, home, "want", 2) ~= nil)
end)

suite:Case("a pilot's listing is held by the board, and taken when its price is near what it is worth", function(t)
  local game, home = newGame()
  local state = game.state
  state.wallet = 1000000
  -- The chance an hour, by what is asked against the worth: sure well under it, never well over.
  t.eq({ Contracts.Chance(85, 100), Contracts.Chance(50, 100), Contracts.Chance(106, 100), Contracts.Chance(10, 0) }, { 1, 1, 0, 0 })
  t.near(Contracts.Chance(100, 100), 0.07, 1e-9)
  t.near(Contracts.Chance(105, 100), 0.02, 1e-9)
  t.ok(Contracts.Chance(90, 100) > Contracts.Chance(95, 100) and Contracts.Chance(95, 100) > Contracts.Chance(100, 100))

  -- A copy good for a hundred runs. No market deals in it: to the builders here it is worth near its base price.
  Items.Add(state, "copy.ammo.emp", 300, home, "hangar")
  local base = Types.Info("copy.ammo.emp").basePrice
  local worth = Contracts.Worth(state, home, "copy.ammo.emp", 100)
  t.ok(worth > base * 100 * 0.9 and worth < base * 100, `a hundred runs worth {base * 100} at base are worth {worth} here`)
  local copies = stack(game, "copy.ammo.emp")
  t.eq(refused(game, { kind = "ListContract", actor = 0, item = copies.id, quantity = 301, price = 100 }), "no such quantity")
  t.eq(refused(game, { kind = "ListContract", actor = 0, item = copies.id, quantity = 2.5, price = 100 }), "no such quantity")
  t.eq(refused(game, { kind = "ListContract", actor = 0, item = copies.id, quantity = 100, price = 0 }), "no such price")
  t.eq(refused(game, { kind = "ListContract", actor = 0, item = 4242, quantity = 1, price = 100 }), "that is not in the hangar here")
  local price = math.floor(worth * 0.8)
  local queried, fee, chance = Core.Query.ContractWorth(game, home, "copy.ammo.emp", 100, price)
  t.eq({ queried, fee, chance }, { worth, math.ceil(price * 0.03), 1 })
  Core.TakeEvents(game)
  order(t, game, { kind = "ListContract", actor = 0, item = copies.id, quantity = 100, price = price })
  t.eq({ state.wallet, hangar(game, "copy.ammo.emp"), state.journal[#state.journal].reason } :: { any },
    { 1000000 - fee, 200, "broker's fee" } :: { any })
  local listings = Contracts.Listings(state, home)
  t.eq({ #listings, listings[1].type, listings[1].quantity, listings[1].price, listings[1].ends - listings[1].placed } :: { any },
    { 1, "copy.ammo.emp", 100, price, 7 * DAY } :: { any })
  local seen = Core.Query.Contracts(game, home)
  t.eq({ #seen.listings, seen.listings[1].worth, seen.listings[1].chance, seen.listings[1].here, seen.limit } :: { any },
    { 1, worth, 1, true, Contracts.LISTINGS } :: { any })

  -- Within the hour somebody takes it: the pilot is paid, less the sales tax, wherever they are.
  local wallet = state.wallet
  local sold: any = nil
  for _ = 1, HOUR do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      sold = if event.kind == "ContractSold" then event else sold
    end
  end
  local paid = math.floor(price * 0.98)
  t.eq({ sold.type, sold.quantity, sold.price, sold.paid, sold.station } :: { any }, { "copy.ammo.emp", 100, price, paid, home } :: { any })
  t.eq({ state.wallet - wallet, #Contracts.Listings(state), hangar(game, "copy.ammo.emp") }, { paid, 0, 200 })

  -- The builders here have had a hundred: the next hundred are worth less to them, until they have forgotten.
  local second = Contracts.Worth(state, home, "copy.ammo.emp", 100)
  t.ok(second < worth * 0.97, `the next hundred should be worth less than {worth}, and are worth {second}`)
  state.tick += Contracts.FORGET
  local later = Contracts.Worth(state, home, "copy.ammo.emp", 100)
  t.ok(later > second and later < worth, `three days on, {later} should be between {second} and {worth}`)
  state.tick += 20 * Contracts.FORGET
  t.near(Contracts.Worth(state, home, "copy.ammo.emp", 100), worth, 2)
  -- However many are put up, they are never worth more than a few times what a station's builders want of them.
  Items.Add(state, "copy.ammo.emp", 1000000, home, "hangar")
  t.ok(Contracts.Worth(state, home, "copy.ammo.emp", 1000000) < Contracts.APPETITE * 8)

  -- Asked too much for, a listing is never taken: its week up, the lot is back in the hangar.
  local dear = math.floor(Contracts.Worth(state, home, "copy.ammo.emp", 50) * 1.2)
  order(t, game, { kind = "ListContract", actor = 0, item = stack(game, "copy.ammo.emp").id, quantity = 50, price = dear })
  local had = hangar(game, "copy.ammo.emp")
  local events = hours(game, 7 * 24 - 1)
  t.eq({ #events, #Contracts.Listings(state) }, { 0, 1 })
  events = hours(game, 2)
  t.eq({ #events, events[1].kind, events[1].quantity, #Contracts.Listings(state), hangar(game, "copy.ammo.emp") - had } :: { any },
    { 1, "ContractExpired", 50, 0, 50 } :: { any })

  -- Called off where it is up: the lot is back, and the broker keeps the fee.
  order(t, game, { kind = "ListContract", actor = 0, item = stack(game, "copy.ammo.emp").id, quantity = 10, price = 100000 })
  t.eq(state.journal[#state.journal].amount, -3000)
  local up = Contracts.Listings(state)[1]
  wallet = state.wallet
  had = hangar(game, "copy.ammo.emp")
  t.eq(refused(game, { kind = "CancelContract", actor = 0, order = 4242 }), "no such listing")
  state.ships[state.player.ship].docked = 4242
  t.eq(refused(game, { kind = "CancelContract", actor = 0, order = up.id }), "there is no board here")
  state.ships[state.player.ship].docked = home
  order(t, game, { kind = "CancelContract", actor = 0, order = up.id })
  t.eq({ state.wallet, hangar(game, "copy.ammo.emp") - had, #Contracts.Listings(state) }, { wallet, 10, 0 })

  -- Ten at a time.
  for _ = 1, Contracts.LISTINGS do
    order(t, game, { kind = "ListContract", actor = 0, item = stack(game, "copy.ammo.emp").id, quantity = 1, price = 100000 })
  end
  t.eq(refused(game, { kind = "ListContract", actor = 0, item = stack(game, "copy.ammo.emp").id, quantity = 1, price = 100000 }),
    `{Contracts.LISTINGS} listings at a time`)
  -- And the broker is paid first.
  order(t, game, { kind = "CancelContract", actor = 0, order = Contracts.Listings(state)[1].id })
  state.wallet = 2999
  t.eq(refused(game, { kind = "ListContract", actor = 0, item = stack(game, "copy.ammo.emp").id, quantity = 1, price = 100000 }),
    "not enough credits for the broker")
end)

suite:Case("a listing of what a market deals in is worth what the market would give, lands in the market, and is no way round it", function(t)
  local game, home = newGame()
  local state = game.state
  state.wallet = 10000000
  Items.Add(state, "mineral.iron", 20000, home, "hangar")
  local worth = Contracts.Worth(state, home, "mineral.iron", 20000)
  -- (what selling them at once would bring, before the tax)
  t.near(worth, Core.Query.SellValue(game, home, "mineral.iron", 20000) / 0.98, 2)
  local before = Core.Query.Quote(game, home, "mineral.iron")
  local price = math.floor(worth * 0.85)
  order(t, game, { kind = "ListContract", actor = 0, item = stack(game, "mineral.iron").id, quantity = 20000, price = price })
  t.eq(Core.Query.Quote(game, home, "mineral.iron").stock, before.stock, "up on the board, it is in nobody's market yet")
  local events = hours(game, 1)
  t.eq({ #events, events[1].kind, events[1].paid } :: { any }, { 1, "ContractSold", math.floor(price * 0.98) } :: { any })
  local after = Core.Query.Quote(game, home, "mineral.iron")
  t.eq(after.stock, before.stock + 20000)
  t.ok(after.bid < before.bid, "what is sold by contract moves the market as what is sold there does")

  -- Bought at a market and put up on its board at the most anybody would ever pay, a lot loses money: the
  -- broker and the tax are more than the board can add.
  for _, count in { 100, 5000, 40000 } do
    local fresh = newGame()
    fresh.state.wallet = 100000000
    local cost = assert(Core.Query.BuyCost(fresh, home, "mineral.titanium", count))
    order(t, fresh, { kind = "BuyNow", actor = 0, type = "mineral.titanium", quantity = count })
    local most = math.floor(Contracts.Worth(fresh.state, home, "mineral.titanium", count) * Contracts.NEVER)
    local back = math.floor(most * 0.98) - Contracts.Fee(fresh.state, home, most)
    t.ok(back < cost, `{count} bought for {cost} would come back as {back}`)
    t.ok(Contracts.Chance(most + 1, Contracts.Worth(fresh.state, home, "mineral.titanium", count)) == 0)
  end
end)

suite:Case("boards are in the save, and a save from before there were any opens with nothing up", function(t)
  local game, home = newGame()
  local state = game.state
  state.wallet = 10000000
  Items.Add(state, "copy.ammo.emp", 500, home, "hangar")
  order(t, game, { kind = "ListContract", actor = 0, item = stack(game, "copy.ammo.emp").id, quantity = 100, price = 1000 })
  hours(game, 1)
  order(t, game, { kind = "ListContract", actor = 0, item = stack(game, "copy.ammo.emp").id, quantity = 100, price = 19000 })
  order(t, game, { kind = "AcceptContract", actor = 0, target = 3 })
  t.eq({ #state.contractIds, #state.contractsTaken, state.contractsHad[home]["copy.ammo.emp"].units } :: { any }, { 1, 1, 100 } :: { any })
  local loaded = Core.Load(Core.Save(game))
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.eq(Contracts.Board(loaded.state, home), Contracts.Board(state, home))
  local mine, theirs = hours(game, 200), hours(loaded, 200)
  t.eq(#mine, 1, "in a week the listing is taken or its time is up")
  t.eq(theirs, mine)
  t.eq(Core.Hash(loaded), Core.Hash(game))

  -- An older save: no boards in it.
  local plain = newGame()
  local file = Codec.Decode(Core.Save(plain))
  file.saveVersion = 71
  file.state.contracts, file.state.contractIds, file.state.contractsTaken, file.state.contractsHad = nil, nil, nil, nil
  local old, length = Codec.Encode(file)
  local opened = Core.Load(old, length)
  t.eq(Core.Hash(opened), Core.Hash(plain))
  t.eq({ #opened.state.contractIds, #opened.state.contractsTaken, #Contracts.Board(opened.state, home) }, { 0, 0, 5 })
end)

return suite
