--!strict
-- Station markets and the hangar, through the Core's front door.

local Core = require("@lt/Core/Api")
local Items = require("@lt/Core/Assets/Items")
local Market = require("@lt/Core/Assets/Market")
local Nomads = require("@lt/Core/Tactical/Nomads")
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
  -- Iron: base 4 credits, with a million and a half in stock, so one
  -- unit barely moves the price and the gap is the 2% spread each way.
  local iron = Core.Query.Quote(game, home, "mineral.iron")
  t.eq(iron.stock, 1500000)
  t.near(assert(iron.ask), 4 * 1.02, 0.001)
  t.near(iron.bid, 4 * 0.98, 0.001)
  -- A hull: ten in stock, so the first one off the shelf is dearer than
  -- normal: 10 * ln(10/9) of base, plus the spread.
  local javelin = Core.Query.Quote(game, home, "frigate.akashi")
  t.eq(javelin.stock, 10)
  t.near(assert(javelin.ask), 400000 * 10 * math.log(10 / 9) * 1.02, 0.01)
  t.near(javelin.bid, 400000 * 10 * math.log(11 / 10) * 0.98, 0.01)
  t.ok(assert(javelin.ask) > javelin.bid)
  t.eq(Core.Query.Quote(game, home, "shield.extender.small").stock, 40)
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
  game.state.wallet = 10000000
  local before = assert(Core.Query.Quote(game, home, "frigate.akashi").ask)
  local cost = assert(Core.Query.BuyCost(game, home, "frigate.akashi", 5))
  -- half the shelf: 10 * ln(10/5) of base each way round, plus spread
  t.eq(cost, math.ceil(400000 * 10 * math.log(2) * 1.02))
  t.ok(cost > 5 * before, "five cost more than five times the first")
  order(t, game, { kind = "BuyNow", actor = 0, type = "frigate.akashi", quantity = 5 })
  t.eq(game.state.wallet, 10000000 - cost)
  t.eq(hangar(game, "frigate.akashi"), 5)
  t.ok(assert(Core.Query.Quote(game, home, "frigate.akashi").ask) > 1.8 * before, "and the next is dearer still")
  t.eq(refused(game, { kind = "BuyNow", actor = 0, type = "frigate.akashi", quantity = 6 }), "the station has not that many")
  game.state.wallet = 10
  t.eq(refused(game, { kind = "BuyNow", actor = 0, type = "shield.extender.small", quantity = 1 }), "not enough credits")
  t.eq(refused(game, { kind = "BuyNow", actor = 0, type = "no.such.thing", quantity = 1 }), "no such item type")
  t.eq(refused(game, { kind = "BuyNow", actor = 0, type = "mineral.iron", quantity = 1.5 }), "no such quantity")
end)

suite:Case("selling pays the going price less tax, and buying back costs more", function(t)
  local game, home = newGame()
  local ore = Items.Add(game.state, "ore.ferrite", 100000, home, "hangar")
  local value = Core.Query.SellValue(game, home, "ore.ferrite", 100000)
  -- a million normally in stock; a tenth more pushes the price down as
  -- they go
  t.eq(value, math.floor(6 * 1000000 * math.log(1.1) * 0.98 * 0.98))
  -- a hold of 1,800 hardly moves it: within half a percent of the bid
  t.ok(Core.Query.SellValue(game, home, "ore.ferrite", 1800) > 1800 * 6 * 0.98 * 0.98 * 0.995)
  local wallet = game.state.wallet
  order(t, game, { kind = "SellNow", actor = 0, item = ore.id, quantity = 100000 })
  t.eq(game.state.wallet, wallet + value)
  t.eq(hangar(game, "ore.ferrite"), 0)
  local back = assert(Core.Query.BuyCost(game, home, "ore.ferrite", 100000))
  t.ok(back > value * 1.05, `sold for {value}, would cost {back} to buy back`)
  t.eq(refused(game, { kind = "SellNow", actor = 0, item = 12345 }), "that is not in the hangar here")
end)

suite:Case("a market drifts back to normal when left alone", function(t)
  local game, home = newGame()
  game.state.wallet = 10000000
  order(t, game, { kind = "BuyNow", actor = 0, type = "mineral.titanium", quantity = 50000 })
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
  -- The station asks 22.44 for copper. Ask 23: its customers buy from
  -- the station instead.
  order(t, game, { kind = "PlaceOrder", actor = 0, to = "sell", item = ore.id, quantity = 3000, price = 23 })
  t.eq(hangar(game, "mineral.copper"), 0, "the copper is in escrow")
  t.eq(state.wallet, wallet - math.ceil(23 * 3000 * 0.03), "less the broker's fee")
  local placed = Core.Query.Orders(game, home)
  t.eq(#placed, 1)
  t.eq({ placed[1].side, placed[1].type, placed[1].quantity, placed[1].price } :: { any },
    { "sell", "mineral.copper", 3000, 23 } :: { any })
  minutes(game, 10)
  t.eq(placed[1].quantity, 3000, "nothing fills while the station asks less")

  -- A shortage: someone buys a third of the station's copper.
  state.wallet += 5000000
  order(t, game, { kind = "BuyNow", actor = 0, type = "mineral.copper", quantity = 90000 })
  t.ok(assert(Core.Query.Quote(game, home, "mineral.copper").ask) > 23)
  wallet = state.wallet
  minutes(game, 1)
  local first = 3000 - placed[1].quantity
  -- a tenth of normal stock an hour: 272,727 * 0.1 / 60 = 454.5 a minute
  t.ok(first == 454 or first == 455, `{first} filled in the first minute`)
  t.eq(state.wallet, wallet + math.floor(first * 23 * 0.98), "paid at the order's price, less tax")
  minutes(game, 10)
  t.eq(#Core.Query.Orders(game, home), 0, "it keeps filling until it is gone")
  local history = Core.Query.History(game, home, "mineral.copper")
  t.eq(#history, 1)
  t.eq(history[1].volume, 90000 + 3000)
end)

suite:Case("a buy order holds its credits and fills when the price comes down to it", function(t)
  local game, home = newGame()
  local state = game.state
  state.wallet = 100000
  -- The station bids 3.92 for iron. Offer 3 for 6,000: nobody sells for
  -- that while the station pays more.
  order(t, game, { kind = "PlaceOrder", actor = 0, to = "buy", type = "mineral.iron", quantity = 6000, price = 3 })
  t.eq(state.wallet, 100000 - 18000 - 540, "the price in escrow, and the fee")
  minutes(game, 5)
  t.eq(hangar(game, "mineral.iron"), 0)
  -- A glut: the station is sold far more iron than it wants.
  local glut = Items.Add(state, "mineral.iron", 600000, home, "hangar")
  order(t, game, { kind = "SellNow", actor = 0, item = glut.id, quantity = 600000 })
  t.ok(Core.Query.Quote(game, home, "mineral.iron").bid < 3)
  minutes(game, 1)
  -- 1,500,000 * 0.1 / 60 = 2,500 a minute
  t.eq(hangar(game, "mineral.iron"), 2500)
  minutes(game, 20)
  t.eq(hangar(game, "mineral.iron"), 6000)
  t.eq(#Core.Query.Orders(game, home), 0, "a filled order is gone")
end)

suite:Case("an order earns the spread a trade at once gives away, at the pace of the station's customers", function(t)
  local game, home = newGame()
  local state = game.state
  local quote = Core.Query.Quote(game, home, "ammo.emp")
  t.near(assert(quote.ask), 20.4, 1e-3)
  t.near(quote.bid, 19.6, 1e-3)
  t.near(quote.sellAt, 20.4, 1e-3)
  t.near(assert(quote.buyAt), 19.6, 1e-3)
  local ammo = stack(game, "ammo.emp")
  local atOnce = Core.Query.SellValue(game, home, "ammo.emp", 500)
  t.ok(atOnce < 500 * 19.6 * 0.98, "selling 500 at once takes the bid, less tax, and pushes it down")
  -- Asking 20 undercuts the station's 20.40.
  order(t, game, { kind = "PlaceOrder", actor = 0, to = "sell", item = ammo.id, quantity = 500, price = 20 })
  local wallet = state.wallet
  local placed = Core.Query.Orders(game, home)[1]
  minutes(game, 1)
  -- the station normally holds 150,000 rounds: 15,000 an hour, 250 a
  -- minute
  t.eq(placed.quantity, 250)
  minutes(game, 1)
  t.eq(#Core.Query.Orders(game, home), 0)
  t.eq(state.wallet, wallet + 2 * math.floor(250 * 20 * 0.98))
  t.ok(state.wallet - wallet > atOnce)
end)

suite:Case("orders for the same thing share the customers, first placed first; rare things sell rarely", function(t)
  local game, home = newGame()
  local state = game.state
  state.wallet = 100000
  local ammo = stack(game, "ammo.emp")
  order(t, game, { kind = "PlaceOrder", actor = 0, to = "sell", item = ammo.id, quantity = 30, price = 20 })
  order(t, game, { kind = "PlaceOrder", actor = 0, to = "sell", item = ammo.id, quantity = 300, price = 19 })
  local orders = Core.Query.Orders(game, home)
  local second = orders[2]
  minutes(game, 1)
  t.eq(#Core.Query.Orders(game, home), 1, "the first, of 30, is filled")
  t.eq(second.quantity, 80, "and the second got the other 220 of the minute's 250")

  -- A station normally holds 40 of a module: its customers take four an
  -- hour, not one a minute. (Priced low, so only the customers limit it.)
  local extenders = Items.Add(state, "shield.extender.small", 5, home, "hangar")
  order(t, game, { kind = "PlaceOrder", actor = 0, to = "sell", item = extenders.id, quantity = 6, price = 4000 })
  local slow = Core.Query.Orders(game, home)[2]
  minutes(game, 45)
  t.eq(slow.quantity, 3, "three in three quarters of an hour")
  minutes(game, 45)
  t.eq(slow.quantity, 0, "six in an hour and a half")
  t.eq(#Core.Query.Orders(game, home), 0)
end)

suite:Case("a thin market moves against an order: one hull more than a station wants is a lot", function(t)
  local game, home = newGame()
  local state = game.state
  state.wallet = 1000000
  local quote = Core.Query.Quote(game, home, "frigate.akashi")
  -- ten on the shelves at 400,000: the eleventh is worth less, and the
  -- tenth, to someone who wants it gone from them, more
  t.near(quote.sellAt, 400000 * 10 * math.log(11 / 10) * 1.02, 0.01)
  t.near(assert(quote.buyAt), 400000 * 10 * math.log(10 / 9) * 0.98, 0.01)
  t.ok(quote.sellAt < 390000 and assert(quote.buyAt) > 410000)
  local hulls = Items.Add(state, "frigate.akashi", 3, home, "hangar")
  order(t, game, { kind = "PlaceOrder", actor = 0, to = "sell", item = hulls.id, quantity = 3,
    price = math.floor(quote.sellAt) - 500 })
  local placed = Core.Query.Orders(game, home)[1]
  minutes(game, 300)
  t.eq(placed.quantity, 2, "one sells; the next waits for the wider world to take up the first")
  minutes(game, 3000)
  -- (what is normal here has moved a little in two days, with what the
  -- system has of what a hull is built of: Strategic/Commerce. An order
  -- left over what the station now asks for the eleventh is brought
  -- down to it, as its owner would.)
  local now = Core.Query.Quote(game, home, "frigate.akashi")
  if placed.quantity == 2 and now.sellAt < placed.price + 500 then
    t.near(now.stock, 10, 0.5, "the wider world has not taken up the first")
    order(t, game, { kind = "ModifyOrder", actor = 0, order = placed.id, price = math.floor(now.sellAt) - 500 })
    minutes(game, 60)
  end
  t.ok(placed.quantity < 2, "which it does, in time")
end)

-- Cancel every order and trade at once back to holding 'want' of a type:
-- what a trader is left with is then all in the wallet.
local function settle(t: Test.Context, game: Core.Game, type: string, want: number)
  for _, placed in Core.Query.Orders(game, game.state.player.home) do
    order(t, game, { kind = "CancelOrder", actor = 0, order = placed.id })
  end
  local over = hangar(game, type) - want
  if over > 0 then
    order(t, game, { kind = "SellNow", actor = 0, item = stack(game, type).id, quantity = over })
  elseif over < 0 then
    order(t, game, { kind = "BuyNow", actor = 0, type = type, quantity = -over })
  end
end

suite:Case("buying and selling the same thing at one station never pays, however skilled the trader", function(t)
  local lots: { { any } } = { { "mineral.copper", 100 }, { "shield.extender.small", 1 }, { "ammo.emp", 200 }, { "frigate.akashi", 1 } }
  local START = 10000000
  local boughtByOrder, soldByOrder = 0, 0
  for _, skilled in { false, true } do
    for _, lot in lots do
      local type: string, quantity: number = lot[1], lot[2]
      local game, home = newGame()
      local state = game.state
      if skilled then
        state.skills.accounting, state.skills["broker.relations"] = 5, 5
      end
      state.wallet = START
      local had = hangar(game, type)

      -- At once: buy, then sell back.
      order(t, game, { kind = "BuyNow", actor = 0, type = type, quantity = quantity })
      order(t, game, { kind = "SellNow", actor = 0, item = stack(game, type).id, quantity = quantity })
      t.ok(state.wallet < START, `{type}: a round trip at once made {state.wallet - START}`)
      minutes(game, 1200)

      -- With orders, at the best prices that fill. Three ways: sell back
      -- straight away into the price the buying pushed up; sell back
      -- once the wider world has restocked the station; and buy and
      -- sell at the same time. Whatever has not traded by the end is
      -- cancelled and settled at once, so the wallet tells the whole
      -- story. (The skilled trader only: the other pays more in fees
      -- for the same trades.)
      local waits: { number } = if skilled then { 0, 1200, -1 } else {}
      for _, wait in waits do
        state.wallet = START
        local quote = Core.Query.Quote(game, home, type)
        order(t, game, { kind = "PlaceOrder", actor = 0, to = "buy", type = type, quantity = quantity,
          price = math.ceil(assert(quote.buyAt)) })
        local bought = Core.Query.Orders(game, home)[1]
        local sold: State.Order
        if wait < 0 then
          local spare = Items.Add(state, type, quantity, home, "hangar")
          order(t, game, { kind = "PlaceOrder", actor = 0, to = "sell", item = spare.id, quantity = quantity,
            price = math.floor(quote.sellAt) })
          sold = Core.Query.Orders(game, home)[2]
          minutes(game, 1200)
          boughtByOrder += quantity - bought.quantity
          soldByOrder += quantity - sold.quantity
          settle(t, game, type, had + quantity)
          Items.Take(state, stack(game, type), quantity)
        else
          minutes(game, 600)
          if wait == 0 then
            t.eq(bought.quantity, 0, `{type}: the buy order filled`)
          end
          boughtByOrder += quantity - bought.quantity
          minutes(game, wait)
          if hangar(game, type) > had then
            quote = Core.Query.Quote(game, home, type)
            order(t, game, { kind = "PlaceOrder", actor = 0, to = "sell", item = stack(game, type).id,
              quantity = hangar(game, type) - had, price = math.floor(quote.sellAt) })
            local orders = Core.Query.Orders(game, home)
            sold = orders[#orders]
            local asked = sold.quantity
            minutes(game, 1200)
            soldByOrder += asked - sold.quantity
          end
          settle(t, game, type, had)
        end
        t.ok(state.wallet < START, `{type}, skilled {tostring(skilled)}, wait {wait}: orders made {state.wallet - START}`)
        minutes(game, 1200)
      end
    end
  end
  t.ok(boughtByOrder > 500 and soldByOrder > 500, `orders bought {boughtByOrder} and sold {soldByOrder}`)
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

suite:Case("an order's price can be changed where the order is: the broker is paid on what it gains, and a buy order holds the difference", function(t)
  local game, home = newGame()
  local state = game.state
  state.wallet = 50000
  local ore = Items.Add(state, "mineral.copper", 500, home, "hangar")
  order(t, game, { kind = "PlaceOrder", actor = 0, to = "sell", item = ore.id, quantity = 500, price = 30 })
  order(t, game, { kind = "PlaceOrder", actor = 0, to = "buy", type = "mineral.iron", quantity = 1000, price = 2 })
  local sell: State.Order?, buy: State.Order? = nil, nil
  for _, placed in Core.Query.Orders(game, home) do
    if placed.side == "sell" then
      sell = placed
    else
      buy = placed
    end
  end
  local selling, buying = assert(sell), assert(buy)
  t.eq(refused(game, { kind = "ModifyOrder", actor = 0, order = 12345, price = 31 }), "no such order")
  t.eq(refused(game, { kind = "ModifyOrder", actor = 0, order = selling.id, price = 30 }), "that is its price already")
  t.eq(refused(game, { kind = "ModifyOrder", actor = 0, order = selling.id, price = 0 }), "no such price")
  t.eq(refused(game, { kind = "ModifyOrder", actor = 0, order = selling.id, price = 30.5 }), "no such price")
  -- A sell order put up from 30 to 40: the broker's 3% of the 5,000 it has gained. Brought down, nothing.
  local before = state.wallet
  order(t, game, { kind = "ModifyOrder", actor = 0, order = selling.id, price = 40 })
  t.eq({ selling.price, selling.quantity, before - state.wallet }, { 40, 500, 150 })
  order(t, game, { kind = "ModifyOrder", actor = 0, order = selling.id, price = 25 })
  t.eq({ selling.price, before - state.wallet }, { 25, 150 })
  -- A buy order put up from 2 to 3: the thousand credits more it holds, and the broker's 30. Brought down to 1, it gives 2,000 back.
  before = state.wallet
  order(t, game, { kind = "ModifyOrder", actor = 0, order = buying.id, price = 3 })
  t.eq({ buying.price, before - state.wallet }, { 3, 1000 + 30 })
  order(t, game, { kind = "ModifyOrder", actor = 0, order = buying.id, price = 1 })
  t.eq({ buying.price, before - state.wallet }, { 1, 1030 - 2000 })
  -- Not for more than there is to pay with; and cancelled, it gives back what it holds now.
  state.wallet = 100
  t.eq(refused(game, { kind = "ModifyOrder", actor = 0, order = buying.id, price = 2 }), "not enough credits")
  order(t, game, { kind = "CancelOrder", actor = 0, order = buying.id })
  t.eq(state.wallet, 100 + 1000)
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
  order(t, game, { kind = "BuyNow", actor = 0, type = "frigate.akashi", quantity = 1 })
  t.eq(hangar(game, "frigate.akashi"), 1)
  t.eq(refused(game, { kind = "Assemble", actor = 0, item = stack(game, "ammo.emp").id }), "that is not a hull")
  order(t, game, { kind = "Assemble", actor = 0, item = stack(game, "frigate.akashi").id })
  t.eq(hangar(game, "frigate.akashi"), 0)
  local ships = Core.Query.Ships(game, home)
  t.eq(#ships, 2)
  local javelin = ships[2]
  t.eq({ javelin.type, javelin.docked, javelin.owner } :: { any }, { "frigate.akashi", home, "player" } :: { any })
  t.eq(refused(game, { kind = "BoardShip", actor = 0, target = first }), "already aboard")
  t.eq(refused(game, { kind = "BoardShip", actor = 0, target = javelin.id }), "needs Frigates 2",
    "a new pilot has not trained for a combat frigate")
  state.skills.frigates = 2
  order(t, game, { kind = "BoardShip", actor = 0, target = javelin.id })
  t.eq(state.player.ship, javelin.id)
  t.ok(state.ships[first] ~= nil, "the old ship stays in the hangar, guns and all")
  t.eq(#Items.Fitted(state, first), 2)
  Core.Submit(game, { kind = "Undock", actor = javelin.id })
  Core.Step(game)
  local ball = assert(Core.Query.Ball(game, javelin.id))
  -- (a Akashi's top speed, with the pilot's Navigation as it is)
  t.eq(ball.maxVelocity, 325)
  t.eq(Core.Query.Player(game).hull.id, "frigate.akashi")
end)

suite:Case("a pilot who docks a capsule where they keep a ship is put in that ship", function(t)
  local game, home = newGame()
  local state = game.state
  state.skills.frigates = 2
  local spare = Space.NewShip(state, "frigate.carvarro", "Spare", "player", home)
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

suite:Case("but not in a ship they have not trained to fly: then the station gives a starter", function(t)
  local game, home = newGame()
  local state = game.state
  local spare = Space.NewShip(state, "frigate.carvarro", "Spare", "player", home)
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
  t.ok(state.player.ship ~= spare.id)
  t.eq(Core.Query.Player(game).hull.id, "frigate.courier")
  t.eq(#Core.Query.Ships(game, home), 2, "the Carvarro waits in the hangar")
end)

-- A game day at the markets alone, a minute at a time: what Core.Step
-- does for them, without the rest of the game (which has nothing going
-- on in it here), so that a spec can let weeks go by.
local DAY = 86400
local function upTo(game: Core.Game, tick: number)
  local state = game.state
  -- (the markets step on the minute)
  state.tick -= state.tick % Market.STEP_TICKS
  while state.tick < tick do
    state.tick += Market.STEP_TICKS
    Market.Step(state, {})
  end
end
local function days(game: Core.Game, n: number)
  upTo(game, game.state.tick - game.state.tick % Market.STEP_TICKS + n * DAY)
end

suite:Case("a price nobody moves has no history to keep, and its chart is level", function(t)
  local game, home = newGame()
  local state = game.state
  local going = Market.Going(state, home, "mineral.titanium")
  t.near(going, 60, 1e-9)
  -- On the first day there is the one day to show: today, at what the price is now.
  t.eq(Core.Query.PriceHistory(game, home, "mineral.titanium"), { { day = 0, price = going, volume = 0, value = 0 } })
  days(game, 32)
  t.eq(state.tick // DAY, 32)
  t.eq(next(state.trades), nil, "a month of nothing should have put nothing down")
  -- Thirty days, today the last of them, by default: every one at the price it has always had.
  local chart = Core.Query.PriceHistory(game, home, "mineral.titanium")
  t.eq({ #chart, chart[1].day, chart[#chart].day }, { 30, 3, 32 })
  for _, day in chart do
    t.eq({ day.price, day.volume, day.value }, { going, 0, 0 })
  end
  t.eq(#Core.Query.PriceHistory(game, home, "mineral.titanium", 7), 7)
  -- What no market deals in has no chart, nor has what is no station.
  t.eq(Core.Query.PriceHistory(game, home, "copy.ammo.emp"), {})
  t.eq(Core.Query.PriceHistory(game, 4242, "mineral.titanium"), {})
end)

suite:Case("a day something traded in is put down with what the price closed at, and a price drifting home each day until it is home", function(t)
  local game, home = newGame()
  local state = game.state
  state.wallet = 10000000
  local rest = Market.Going(state, home, "mineral.titanium")
  -- Day 3, four hours before it ends: half the stock is bought, and the price about doubles.
  upTo(game, 3 * DAY + 20 * 3600)
  order(t, game, { kind = "BuyNow", actor = 0, type = "mineral.titanium", quantity = 50000 })
  local spent = 10000000 - state.wallet
  local moved = Market.Going(state, home, "mineral.titanium")
  t.ok(moved > rest * 1.9, `the price should about double, and went from {rest} to {moved}`)
  -- The day is not over: it is put down with its trade and no close, and the chart has today at the price now.
  local history = Core.Query.History(game, home, "mineral.titanium")
  t.eq(history, { { day = 3, volume = 50000, value = spent } })
  local chart = Core.Query.PriceHistory(game, home, "mineral.titanium")
  t.eq({ #chart, chart[3].price, chart[4].price, chart[4].volume, chart[4].value }, { 4, rest, moved, 50000, spent })

  -- The day ends: it closes at what the price has eased to in those four hours. The day after, in which
  -- nothing traded, is put down too, at its own close: the price was still on its way home.
  upTo(game, 4 * DAY)
  history = Core.Query.History(game, home, "mineral.titanium")
  local third = assert(history[1].close)
  t.eq({ #history, history[1].day, history[1].volume }, { 1, 3, 50000 })
  t.ok(third < moved * 0.8 and third > rest * 1.1, `day 3 should close well between {rest} and {moved}, and closed at {third}`)
  upTo(game, 5 * DAY)
  history = Core.Query.History(game, home, "mineral.titanium")
  t.eq({ #history, history[2].day, history[2].volume, history[2].value }, { 2, 4, 0, 0 })
  t.ok(assert(history[2].close) < third, "the day after should close nearer home")
  -- Home, the price is put down no more: weeks on, the history is what it was, and nothing else has any.
  days(game, 5)
  history = Core.Query.History(game, home, "mineral.titanium")
  local put = #history
  t.ok(put >= 2 and put <= 4, `a price that came home should stop being put down, and has {put} days`)
  t.near(assert(history[put].close), rest, rest * 0.001)
  days(game, 5)
  t.eq(#Core.Query.History(game, home, "mineral.titanium"), put)
  local others = 0
  for _, id in { "mineral.iron", "mineral.copper", "ammo.emp", "frigate.akashi" } do
    others += #Core.Query.History(game, home, id)
  end
  t.eq(others, 0)

  -- The chart of those days: level, the jump on day 3, and down again; today is the price now.
  t.eq(state.tick, 15 * DAY)
  state.tick = 12 * DAY + 5
  chart = Market.Chart(state, home, "mineral.titanium", 30)
  t.eq({ #chart, chart[1].day, chart[13].day }, { 13, 0, 12 })
  t.eq({ chart[1].price, chart[3].price, chart[4].price, chart[4].volume, chart[5].volume }, { rest, rest, third, 50000, 0 })
  t.eq(chart[5].price, assert(history[2].close))
  for index = 5, 12 do
    t.ok(chart[index].price <= chart[index - 1].price and chart[index].price >= rest * 0.999, `day {chart[index].day} is out of line`)
  end
  t.eq(chart[13].price, Market.Going(state, home, "mineral.titanium"))
  -- A chart that begins after the price last moved begins at what it closed at then.
  state.tick = 200 * DAY
  chart = Market.Chart(state, home, "mineral.titanium", 30)
  t.eq({ #chart, chart[1].price }, { 30, assert(history[put].close) })
end)

suite:Case("what nobody brings is put down once when a pilot sells some, and stays where that left it", function(t)
  local game, home = newGame()
  local state = game.state
  local type = "autocannon.small.ii"
  local rest = Market.Going(state, home, type)
  Items.Add(state, type, 2, home, "hangar")
  order(t, game, { kind = "SellNow", actor = 0, item = stack(game, type).id, quantity = 2 })
  local after = Market.Going(state, home, type)
  t.near(after, rest / 2, 1e-6, "a station that wanted four and has two pays half of what it did with none")
  days(game, 3)
  -- One day: the day of the sale. Nothing brings the price back, so nothing more is put down.
  local history = Core.Query.History(game, home, type)
  t.eq({ #history, history[1].day, history[1].volume, history[1].close } :: { any }, { 1, 0, 2, after } :: { any })
  local chart = Core.Query.PriceHistory(game, home, type)
  t.eq({ #chart, chart[1].price, chart[2].price, chart[4].price }, { 4, after, after, after })
end)

suite:Case("a history from before closes were kept is read as it is, and thirty days of one are kept", function(t)
  local game, home = newGame()
  local state = game.state
  local rest = Market.Going(state, home, "mineral.iron")
  -- (as an older save has it: the days something traded in, and no closes)
  state.trades[home] = { ["mineral.iron"] = { { day = 0, volume = 10, value = 100 }, { day = 2, volume = 5, value = 60 } } }
  days(game, 4)
  local chart = Core.Query.PriceHistory(game, home, "mineral.iron")
  t.eq({ #chart, chart[1].volume, chart[3].volume, chart[3].value }, { 5, 10, 5, 60 })
  for _, day in chart do
    t.eq(day.price, rest)
  end
  t.eq(#Core.Query.History(game, home, "mineral.iron"), 2, "a price that did not move puts nothing down")
  -- A trade a day for forty days (the days between gone by in a moment): the last thirty are kept.
  state.wallet = 10000000
  for day = 5, 44 do
    state.tick = day * DAY + 100
    order(t, game, { kind = "BuyNow", actor = 0, type = "mineral.iron", quantity = 100 })
  end
  local history = Core.Query.History(game, home, "mineral.iron")
  t.eq({ #history, history[1].day, history[30].day, history[30].volume }, { 30, 15, 44, 100 })
end)

suite:Case("closing prices are in the save", function(t)
  local game, home = newGame()
  game.state.wallet = 10000000
  upTo(game, 20 * 3600)
  order(t, game, { kind = "BuyNow", actor = 0, type = "mineral.titanium", quantity = 50000 })
  upTo(game, DAY)
  local loaded = Core.Load(Core.Save(game))
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.eq(Core.Query.History(loaded, home, "mineral.titanium"), Core.Query.History(game, home, "mineral.titanium"))
  days(game, 2)
  days(loaded, 2)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.eq(Core.Query.PriceHistory(loaded, home, "mineral.titanium"), Core.Query.PriceHistory(game, home, "mineral.titanium"))
  t.eq(#Core.Query.History(loaded, home, "mineral.titanium"), 2)
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

suite:Case("a faction's stations have its own hulls and weapons at anybody's price, and another's dearer and scarcer", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true, systems = 40 })
  local state = game.state
  -- A station in the space of each of the four.
  local stations: { [string]: number } = {}
  for id, node in state.galaxy.systems do
    if node.home then
      for _, object in Space.Describe(state, id).objects do
        if object.kind == "station" and stations[node.nearest] == nil then
          stations[node.nearest] = object.id
        end
      end
    end
  end
  -- (the Kethri have none there, or anywhere: the place to trade among them is a colony ship of theirs)
  t.eq(stations.kethri, nil)
  local vessari, kethri, orun = assert(stations.vessari), Nomads.StationId(1), assert(stations.orun)
  t.eq(Nomads.Fleets(state.galaxy)[1].faction, "kethri")
  t.eq({ Market.Leaning("vessari", "frigate.akashi") } :: { any }, { 1, false } :: { any })
  t.eq({ Market.Leaning("kethri", "frigate.akashi") } :: { any }, { Market.FOREIGN_HULL, true } :: { any })
  t.eq({ Market.Leaning("kethri", "frigate.courier") } :: { any }, { 1, false } :: { any })
  t.eq({ Market.Leaning("kethri", "laser.pulse.small") } :: { any }, { 1, false } :: { any })
  -- (another faction's guns and what they fire: a few, dearer. The owner, 2026-11-16)
  t.eq({ Market.Leaning("vessari", "laser.pulse.small") } :: { any }, { Market.FOREIGN_ARMS, true } :: { any })
  t.eq({ Market.Leaning("vessari", "launcher.light") } :: { any }, { 1, false } :: { any })
  t.eq({ Market.Leaning("orun", "missile.light.em") } :: { any }, { Market.FOREIGN_ARMS, true } :: { any })
  t.eq({ Market.Leaning("orun", "blaster.small") } :: { any }, { 1, false } :: { any })
  t.eq({ Market.Leaning("orun", "mineral.iron") } :: { any }, { 1, false } :: { any })
  -- A Akashi is the Vessari's: ten on their shelves, four on the Kethri's, and dearer there.
  local here, there = Core.Query.Quote(game, vessari, "frigate.akashi"), Core.Query.Quote(game, kethri, "frigate.akashi")
  t.eq({ here.stock, there.stock }, { 10, Market.FOREIGN_STOCK })
  t.ok(there.bid > here.bid * 1.2, `a Akashi fetches {there.bid} among the Kethri and {here.bid} at home`)
  t.ok(assert(there.ask) > assert(here.ask) * 1.5, "a hull bought where it is not made should cost half as much again, and more")
  -- So carrying one from where it is made to where it is not pays, tax and all.
  state.wallet = 10000000
  local cost = assert(Core.Query.BuyCost(game, vessari, "frigate.akashi", 1))
  Items.Add(state, "frigate.akashi", 1, kethri, "hangar")
  t.ok(Core.Query.SellValue(game, kethri, "frigate.akashi", 1) > cost * 1.03, "a hull carried to another faction's space should sell at a profit")
  -- And so does a Kethri laser among the Orun. (One: another faction's
  -- guns are a few on a shelf since 2026-11-16, so a hold of them is
  -- more than its market wants, as a hold of hulls is.)
  local lasers = assert(Core.Query.BuyCost(game, kethri, "laser.pulse.small", 1))
  t.ok(Core.Query.SellValue(game, orun, "laser.pulse.small", 1) > lasers * 1.03, "a laser carried to the Orun should sell at a profit")
  t.ok(Core.Query.SellValue(game, kethri, "laser.pulse.small", 1) < lasers, "nothing sells at a profit where it was bought")
  t.eq(Core.Query.Quote(game, orun, "laser.pulse.small").stock, Market.FOREIGN_STOCK)
  -- (and what they fire: as many as a quarter of the few the Kethri keep,
  -- which is a tenth of what is normal: Market.FOREIGN_CHARGES)
  local shelf = Core.Query.Quote(game, kethri, "ammo.emp").stock
  t.ok(shelf >= Market.FOREIGN_STOCK and shelf < Core.Query.Quote(game, vessari, "ammo.emp").stock, `{shelf} rounds on a Kethri shelf`)
  local some = math.max(1, shelf // 4)
  local rounds = assert(Core.Query.BuyCost(game, vessari, "ammo.emp", some))
  t.ok(Core.Query.SellValue(game, kethri, "ammo.emp", some) > rounds * 1.03, `{some} rounds carried to the Kethri should sell at a profit`)
end)

suite:Case("a station keeps its people's goods, a few of another's, what its kind trades in, and its people's prints", function(t)
  -- (the owner, 2026-11-16: another faction's goods "A few, dearer";
  -- prints "Own faction, by station kind"; goods nobody owns "By station kind")
  local game = Core.New({ galaxySeed = 1, historySeed = 1 })
  local state = game.state
  local home = state.player.home
  local object = assert(Space.Object(state, home))
  t.eq(object.variety, "trade hub")
  local function stock(id: string): number
    return Core.Query.Quote(game, home, id).stock
  end
  -- Its people's tower and hull, and another's few.
  t.ok(stock("tower.vessari.small") > Market.FOREIGN_STOCK and stock("frigate.akashi") > Market.FOREIGN_STOCK)
  t.eq({ stock("tower.orun.small"), stock("blaster.small") } :: { any }, { Market.FOREIGN_STOCK, Market.FOREIGN_STOCK } :: { any })
  -- Its people's prints, and nobody else's: a trade hub has every kind of them.
  t.ok(stock("blueprint.frigate.akashi") > 0 and stock("blueprint.autocannon.small") > 0 and stock("blueprint.shield.extender.small") > 0)
  t.eq({ stock("blueprint.tower.orun.small"), stock("blueprint.blaster.small") } :: { any }, { 0, 0 } :: { any })
  -- (and a print it does not sell, it buys for little)
  local quote = Core.Query.Quote(game, home, "blueprint.blaster.small")
  t.eq(quote.ask, nil)
  -- What goes where, by kind.
  t.eq({ Market.PRINTS.ship, Market.PRINTS.module, Market.PRINTS.structure } :: { any }, { "shipyard", "outpost", "refinery" } :: { any })
  t.ok(Market.KINDS.refinery.ore and not Market.KINDS.refinery.ship and Market.KINDS.shipyard.ship and Market.KINDS["trade hub"] == nil)
end)

return suite
