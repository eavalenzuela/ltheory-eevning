--!strict
-- Station markets and the hangar, through the Core's front door.

local Core = require("@lt/Core/Api")
local Items = require("@lt/Core/Assets/Items")
local Market = require("@lt/Core/Assets/Market")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Market")

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
  for _, item in Items.In(game.state, game.state.player.home, "hangar") do
    if item.type == type then
      return item.quantity
    end
  end
  return 0
end

local function stack(game: Core.Game, type: string): State.Item
  for _, item in Items.In(game.state, game.state.player.home, "hangar") do
    if item.type == type then
      return item
    end
  end
  error(`no {type} in the hangar`, 2)
end

local function minutes(game: Core.Game, n: number)
  for _ = 1, n * 60 do
    Core.Step(game)
  end
end

suite:Case("a station asks a little over the going price and bids a little under", function(t)
  local game, home = newGame()
  -- Iron: base 4 credits, with tens of thousands in stock, so one unit
  -- barely moves the price and the gap is the 2% spread each way.
  local iron = Core.Query.Quote(game, home, "mineral.iron")
  t.eq(iron.stock, 75000)
  t.near(assert(iron.ask), 4 * 1.02, 0.001)
  t.near(iron.bid, 4 * 0.98, 0.001)
  -- A module: a dozen in stock, so the first one off the shelf is dearer
  -- than normal: 12 * ln(12/11) of base, plus the spread.
  local extender = Core.Query.Quote(game, home, "shield.extender.small")
  t.eq(extender.stock, 12)
  t.near(assert(extender.ask), 7000 * 12 * math.log(12 / 11) * 1.02, 0.01)
  t.near(extender.bid, 7000 * 12 * math.log(13 / 12) * 0.98, 0.01)
  t.ok(assert(extender.ask) > extender.bid)
end)

suite:Case("different kinds of station value things differently", function(t)
  local game = newGame()
  local state = game.state
  local byVariety: { [string]: number } = {}
  for system = 1, 3 do
    Space.Describe(state, system)
    for _, object in Core.Query.Objects(game, system) do
      if object.kind == "station" then
        byVariety[object.variety] = object.id
      end
    end
  end
  local plain = byVariety["trade hub"] or byVariety["habitat"]
  local refinery = assert(byVariety["refinery"], "no refinery in the first three systems")
  local here = Core.Query.Quote(game, assert(plain), "ore.ferrite").bid
  local there = Core.Query.Quote(game, refinery, "ore.ferrite").bid
  t.near(there / here, 1.12, 1e-6, "a refinery pays 12% more for ore")
  t.ok(Core.Query.Quote(game, refinery, "mineral.iron").bid < Core.Query.Quote(game, assert(plain), "mineral.iron").bid)
end)

suite:Case("buying takes the price for each unit in turn, and the price rises behind it", function(t)
  local game, home = newGame()
  game.state.wallet = 1000000
  local before = assert(Core.Query.Quote(game, home, "shield.extender.small").ask)
  local cost = assert(Core.Query.BuyCost(game, home, "shield.extender.small", 6))
  -- half the shelf: 12 * ln(12/6) of base each way round, plus spread
  t.eq(cost, math.ceil(7000 * 12 * math.log(2) * 1.02))
  t.ok(cost > 6 * before, "six cost more than six times the first")
  order(t, game, { kind = "BuyNow", actor = 0, type = "shield.extender.small", quantity = 6 })
  t.eq(game.state.wallet, 1000000 - cost)
  t.eq(hangar(game, "shield.extender.small"), 7, "six bought and the one from the starter kit")
  t.ok(assert(Core.Query.Quote(game, home, "shield.extender.small").ask) > 1.8 * before, "and the next is dearer still")
  t.eq(refused(game, { kind = "BuyNow", actor = 0, type = "shield.extender.small", quantity = 7 }), "the station has not that many")
  game.state.wallet = 10
  t.eq(refused(game, { kind = "BuyNow", actor = 0, type = "shield.extender.small", quantity = 1 }), "not enough credits")
  t.eq(refused(game, { kind = "BuyNow", actor = 0, type = "no.such.thing", quantity = 1 }), "no such item type")
  t.eq(refused(game, { kind = "BuyNow", actor = 0, type = "mineral.iron", quantity = 1.5 }), "no such quantity")
end)

suite:Case("selling pays the going price less tax, and buying back costs more", function(t)
  local game, home = newGame()
  local ore = Items.Add(game.state, "ore.ferrite", 5000, home, "hangar")
  local value = Core.Query.SellValue(game, home, "ore.ferrite", 5000)
  -- 50,000 normally in stock; 5,000 more pushes the price down as they go
  t.eq(value, math.floor(6 * 50000 * math.log(55000 / 50000) * 0.98 * 0.98))
  local wallet = game.state.wallet
  order(t, game, { kind = "SellNow", actor = 0, item = ore.id, quantity = 5000 })
  t.eq(game.state.wallet, wallet + value)
  t.eq(hangar(game, "ore.ferrite"), 0)
  local back = assert(Core.Query.BuyCost(game, home, "ore.ferrite", 5000))
  t.ok(back > value * 1.05, `sold for {value}, would cost {back} to buy back`)
  t.eq(refused(game, { kind = "SellNow", actor = 0, item = 12345 }), "that is not in the hangar here")
end)

suite:Case("a market drifts back to normal when left alone", function(t)
  local game, home = newGame()
  game.state.wallet = 1000000
  order(t, game, { kind = "BuyNow", actor = 0, type = "mineral.titanium", quantity = 2500 })
  local dear = assert(Core.Query.Quote(game, home, "mineral.titanium").ask)
  t.ok(dear > 60 * 1.9, "half the stock gone, the price about doubles")
  minutes(game, 60)
  local later = assert(Core.Query.Quote(game, home, "mineral.titanium").ask)
  t.ok(later < dear and later > 61.5, `an hour on it has eased from {dear} to {later}`)
  minutes(game, 60 * 47)
  t.near(assert(Core.Query.Quote(game, home, "mineral.titanium").ask), 60 * 1.02, 0.6, "two days on it is back")
end)

suite:Case("a sell order waits for its price, then fills a little each minute", function(t)
  local game, home = newGame()
  local state = game.state
  local ore = Items.Add(state, "mineral.copper", 3000, home, "hangar")
  local wallet = state.wallet
  -- Copper bids just under 22. Ask 23: nobody pays that yet.
  order(t, game, { kind = "PlaceOrder", actor = 0, to = "sell", item = ore.id, quantity = 3000, price = 23 })
  t.eq(hangar(game, "mineral.copper"), 0, "the copper is in escrow")
  t.eq(state.wallet, wallet - math.ceil(23 * 3000 * 0.03), "less the broker's fee")
  local placed = Core.Query.Orders(game, home)
  t.eq(#placed, 1)
  t.eq({ placed[1].side, placed[1].type, placed[1].quantity, placed[1].price } :: { any },
    { "sell", "mineral.copper", 3000, 23 } :: { any })
  minutes(game, 10)
  t.eq(placed[1].quantity, 3000, "nothing fills while the station would pay less")

  -- A shortage: someone buys a third of the station's copper.
  state.wallet += 500000
  order(t, game, { kind = "BuyNow", actor = 0, type = "mineral.copper", quantity = 4500 })
  t.ok(Core.Query.Quote(game, home, "mineral.copper").bid > 23)
  wallet = state.wallet
  minutes(game, 1)
  local first = 3000 - placed[1].quantity
  -- a tenth of normal stock an hour: 13,636 * 0.1 / 60 = 22 a minute
  t.eq(first, 22)
  t.eq(state.wallet, wallet + math.floor(22 * 23 * 0.98), "paid at the order's price, less tax")
  minutes(game, 600)
  t.ok(#Core.Query.Orders(game, home) == 0 or placed[1].quantity < 3000 - 22, "it keeps filling")
  local history = Core.Query.History(game, home, "mineral.copper")
  t.eq(#history, 1)
  t.ok(history[1].volume >= 4500 + 22)
end)

suite:Case("a buy order holds its credits and fills when the price comes down to it", function(t)
  local game, home = newGame()
  local state = game.state
  state.wallet = 100000
  -- Iron asks about 4.08. Offer 3 for 2,000.
  order(t, game, { kind = "PlaceOrder", actor = 0, to = "buy", type = "mineral.iron", quantity = 2000, price = 3 })
  t.eq(state.wallet, 100000 - 6000 - 180, "the price in escrow, and the fee")
  minutes(game, 5)
  t.eq(hangar(game, "mineral.iron"), 0)
  -- A glut: the station is sold far more iron than it wants.
  local glut = Items.Add(state, "mineral.iron", 60000, home, "hangar")
  order(t, game, { kind = "SellNow", actor = 0, item = glut.id, quantity = 60000 })
  t.ok(assert(Core.Query.Quote(game, home, "mineral.iron").ask) < 3)
  minutes(game, 1)
  -- 75,000 * 0.1 / 60 = 125 a minute
  t.eq(hangar(game, "mineral.iron"), 125)
  minutes(game, 20)
  t.eq(hangar(game, "mineral.iron"), 2000)
  t.eq(#Core.Query.Orders(game, home), 0, "a filled order is gone")
end)

suite:Case("cancelling an order returns what it held, but not the fee", function(t)
  local game, home = newGame()
  local state = game.state
  state.wallet = 50000
  local ore = Items.Add(state, "mineral.copper", 500, home, "hangar")
  order(t, game, { kind = "PlaceOrder", actor = 0, to = "sell", item = ore.id, quantity = 500, price = 30 })
  order(t, game, { kind = "PlaceOrder", actor = 0, to = "buy", type = "mineral.iron", quantity = 1000, price = 2 })
  local afterFees = state.wallet
  t.eq(afterFees, 50000 - 450 - 60 - 2000)
  for _, placed in table.clone(Core.Query.Orders(game, home)) do
    order(t, game, { kind = "CancelOrder", actor = 0, order = placed.id })
  end
  t.eq(#Core.Query.Orders(game, home), 0)
  t.eq(hangar(game, "mineral.copper"), 500)
  t.eq(state.wallet, afterFees + 2000)
  t.eq(refused(game, { kind = "CancelOrder", actor = 0, order = 12345 }), "no such order")
end)

suite:Case("orders are refused for want of goods, credits or sense", function(t)
  local game, home = newGame()
  game.state.wallet = 100
  local ammo = stack(game, "ammo.emp")
  t.eq(refused(game, { kind = "PlaceOrder", actor = 0, to = "sell", item = ammo.id, quantity = 601, price = 20 }), "no such quantity")
  t.eq(refused(game, { kind = "PlaceOrder", actor = 0, to = "sell", item = ammo.id, quantity = 600, price = 0 }), "no such price")
  t.eq(refused(game, { kind = "PlaceOrder", actor = 0, to = "sell", item = ammo.id, quantity = 600, price = 20 }),
    "not enough credits for the broker")
  t.eq(refused(game, { kind = "PlaceOrder", actor = 0, to = "buy", type = "mineral.iron", quantity = 1000, price = 5 }),
    "not enough credits")
  t.eq(refused(game, { kind = "PlaceOrder", actor = 0, type = "mineral.iron", quantity = 10, price = 5 }), "buy or sell?")
  Core.Submit(game, { kind = "Undock", actor = game.state.player.ship })
  Core.Step(game)
  t.eq(refused(game, { kind = "BuyNow", actor = 0, type = "mineral.iron", quantity = 1 }), "not docked")
  local _ = home
end)

suite:Case("the wallet keeps a journal", function(t)
  local game, home = newGame()
  local ore = Items.Add(game.state, "ore.ferrite", 1000, home, "hangar")
  order(t, game, { kind = "SellNow", actor = 0, item = ore.id })
  order(t, game, { kind = "BuyNow", actor = 0, type = "ammo.fusion", quantity = 100 })
  local journal = game.state.journal
  t.eq(#journal, 2)
  t.eq({ journal[1].reason, journal[2].reason }, { "market sale", "market purchase" })
  t.ok(journal[1].amount > 0 and journal[2].amount < 0)
  t.eq(journal[2].balance, game.state.wallet)
end)

suite:Case("a hull can be bought, assembled, boarded and flown", function(t)
  local game, home = newGame()
  local state = game.state
  state.wallet = 600000
  local first = state.player.ship
  order(t, game, { kind = "BuyNow", actor = 0, type = "frigate.lancer", quantity = 1 })
  t.eq(hangar(game, "frigate.lancer"), 1)
  t.eq(refused(game, { kind = "Assemble", actor = 0, item = stack(game, "ammo.emp").id }), "that is not a hull")
  order(t, game, { kind = "Assemble", actor = 0, item = stack(game, "frigate.lancer").id })
  t.eq(hangar(game, "frigate.lancer"), 0)
  local ships = Core.Query.Ships(game, home)
  t.eq(#ships, 2)
  local lancer = ships[2]
  t.eq({ lancer.type, lancer.docked, lancer.owner } :: { any }, { "frigate.lancer", home, "player" } :: { any })
  t.eq(refused(game, { kind = "BoardShip", actor = 0, target = first }), "already aboard")
  order(t, game, { kind = "BoardShip", actor = 0, target = lancer.id })
  t.eq(state.player.ship, lancer.id)
  t.ok(state.ships[first] ~= nil, "the old ship stays in the hangar, guns and all")
  t.eq(#Items.Fitted(state, first), 2)
  Core.Submit(game, { kind = "Undock", actor = lancer.id })
  Core.Step(game)
  local ball = assert(Core.Query.Ball(game, lancer.id))
  t.eq(ball.maxVelocity, 345)
  t.eq(Core.Query.Player(game).hull.id, "frigate.lancer")
end)

suite:Case("a pilot who docks a capsule where they keep a ship is put in that ship", function(t)
  local game, home = newGame()
  local state = game.state
  local spare = Space.NewShip(state, "frigate.harrier", "Spare", "player", home)
  Core.Submit(game, { kind = "Undock", actor = state.player.ship })
  Core.Step(game)
  local Aftermath = require("@lt/Core/Tactical/Aftermath")
  Aftermath.Destroy(state, state.player.ship, 0, game.events)
  Core.Submit(game, { kind = "Dock", actor = state.player.ship, target = home })
  for _ = 1, 600 do
    Core.Step(game)
    if Core.Query.Player(game).docked ~= 0 then
      break
    end
  end
  Core.Step(game)
  t.eq(state.player.ship, spare.id)
  t.eq(#Core.Query.Ships(game, home), 1, "and no starter ship is handed out")
end)

suite:Case("markets are plain data and survive a save", function(t)
  local game, home = newGame()
  game.state.wallet = 100000
  order(t, game, { kind = "BuyNow", actor = 0, type = "mineral.iron", quantity = 5000 })
  order(t, game, { kind = "PlaceOrder", actor = 0, to = "buy", type = "mineral.copper", quantity = 100, price = 10 })
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  minutes(game, 30)
  minutes(loaded, 30)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.eq(Market.Quote(loaded.state, home, "mineral.iron"), Market.Quote(game.state, home, "mineral.iron"))
end)

return suite
