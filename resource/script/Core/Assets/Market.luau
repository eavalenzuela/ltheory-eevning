--!strict
-- Station markets: buying and selling at once, standing orders, and the
-- record of what traded.
--
-- Each station sells and buys every kind of item at a price that depends
-- on how much of it the station holds (Strategic/Economy: one node, a
-- class per item type). Buying takes from that stock and raises the
-- price; selling adds to it and lowers the price; left alone, stock and
-- price drift back toward normal as the wider world, which is not
-- simulated yet, buys and sells in turn. Different kinds of station
-- value things a little differently, so there is a reason to carry ore
-- to a refinery.
--
-- A trade at once takes the station's price for each unit in turn, so a
-- large one costs more per unit than a small one. A standing order names
-- its own price and waits: a sell order fills, a few units at a time,
-- while the station would pay at least that; a buy order while the
-- station would sell for no more. A sell order's goods and a buy order's
-- credits sit in escrow until it fills or is cancelled.
--
-- Selling pays a sales tax; placing an order pays a broker's fee.
--
-- (When the strategic layer arrives these markets will be derived from
-- the stocks of the system they are in, not from a fixed normal level.)

local Economy = require("@lt/Core/Strategic/Economy")
local Items = require("@lt/Core/Assets/Items")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Types = require("@lt/Core/Data/Types")
local Wallet = require("@lt/Core/Assets/Wallet")

local Market = {}

export type Event = { [string]: any }

Market.SALES_TAX = 0.02
Market.BROKER_FEE = 0.03
-- Ticks between the markets' own steps: one game minute.
Market.STEP_TICKS = 60
-- Days of trade history kept per type.
local HISTORY_DAYS = 30
local TICKS_PER_DAY = 86400

-- How much a station normally holds of a type, in units.
local function normalStock(info: Types.Info): number
  if info.category == "ore" or info.category == "mineral" then
    return math.max(100, math.floor(300000 / info.basePrice))
  elseif info.category == "charge" then
    return math.max(100, math.floor(60000 / info.basePrice))
  elseif info.category == "ship" then
    return 4
  elseif info.category == "goods" then
    return 40
  end
  return 12
end

-- How a kind of station values a category of goods, relative to normal.
local TASTES: { [string]: { [string]: number } } = {
  refinery = { ore = 1.12, mineral = 0.94 },
  shipyard = { ship = 0.95, mineral = 1.06, module = 0.97 },
  habitat = { goods = 1.10, charge = 1.05 },
  outpost = { charge = 1.10, module = 1.08, ore = 0.90 },
}

local indexOf: { [string]: number } = {}

-- The class index of a type in every market.
function Market.Index(type: string): number?
  if next(indexOf) == nil then
    for index, id in Types.Ids() do
      indexOf[id] = index
    end
  end
  return indexOf[type]
end

-- A station's market, made on first use.
function Market.For(state: State.State, station: number): Economy.Economy
  local existing = state.markets[station]
  if existing then
    return existing
  end
  local object = assert(Space.Object(state, station), "no such station")
  local tastes = TASTES[object.variety] or {}
  local classes: { Economy.Class } = {}
  for _, id in Types.Ids() do
    local info = Types.Info(id)
    table.insert(classes, { id = id, par = info.basePrice * (tastes[info.category] or 1), cover = 0, need = 0 })
  end
  local econ = Economy.New(classes, {})
  local node = Economy.AddNode(econ, object.name, 0)
  for index, id in Types.Ids() do
    local normal = normalStock(Types.Info(id))
    Economy.SetTarget(econ, node, index, normal)
    Economy.SetStock(econ, node, index, normal)
    -- The wider world restores a quarter of a shortfall an hour.
    econ.nodes[node].anchor[index] = normal * 0.25
  end
  state.markets[station] = econ
  local at = #state.marketIds + 1
  while at > 1 and state.marketIds[at - 1] > station do
    at -= 1
  end
  table.insert(state.marketIds, at, station)
  return econ
end

export type Quote = {
  ask: number?,     -- what one unit costs to buy now; nil if there is none
  bid: number,      -- what one unit fetches now, before tax
  stock: number,    -- whole units the station has to sell
}

function Market.Quote(state: State.State, station: number, type: string): Quote
  local econ = Market.For(state, station)
  local index = assert(Market.Index(type), `no item type '{type}'`)
  return {
    ask = Economy.BuyCost(econ, 1, index, 1),
    bid = Economy.SellRevenue(econ, 1, index, 1),
    stock = math.floor(econ.nodes[1].stock[index]),
  }
end

-- What buying 'quantity' at once would cost in all, or nil if the station
-- has not that many.
function Market.BuyCost(state: State.State, station: number, type: string, quantity: number): number?
  local cost = Economy.BuyCost(Market.For(state, station), 1, assert(Market.Index(type)), quantity)
  return if cost then math.ceil(cost) else nil
end

-- What selling 'quantity' at once would bring in all, after tax.
function Market.SellValue(state: State.State, station: number, type: string, quantity: number): number
  local revenue = Economy.SellRevenue(Market.For(state, station), 1, assert(Market.Index(type)), quantity)
  return math.floor(revenue * (1 - Market.SALES_TAX))
end

local function record(state: State.State, station: number, type: string, units: number, value: number)
  local byType = state.trades[station]
  if byType == nil then
    byType = {}
    state.trades[station] = byType
  end
  local days = byType[type]
  if days == nil then
    days = {}
    byType[type] = days
  end
  local day = state.tick // TICKS_PER_DAY
  local last = days[#days]
  if last and last.day == day then
    last.volume += units
    last.value += value
  else
    table.insert(days, { day = day, volume = units, value = value })
    if #days > HISTORY_DAYS then
      table.remove(days, 1)
    end
  end
end

-- The recent days of trade in a type at a station, oldest first.
function Market.History(state: State.State, station: number, type: string): { State.TradeDay }
  local byType = state.trades[station]
  return if byType and byType[type] then byType[type] else {}
end

-- The player's standing orders, optionally at one station, in the order
-- they were placed.
function Market.Orders(state: State.State, station: number?): { State.Order }
  local found = {}
  for _, id in state.orderIds do
    local order = state.orders[id]
    if station == nil or order.station == station then
      table.insert(found, order)
    end
  end
  return found
end

-- ---------------------------------------------------------------------
-- Orders

local function dockedAt(state: State.State, command: State.Command): (number?, string?)
  local ship = state.ships[command.actor]
  if ship == nil then
    return nil, "no such ship"
  elseif ship.docked == 0 then
    return nil, "not docked"
  end
  return ship.docked, nil
end

local function wholeQuantity(q: number?): boolean
  return q ~= nil and q > 0 and q % 1 == 0
end

function Market.Validate(state: State.State, command: State.Command): (boolean, string?)
  local station, why = dockedAt(state, command)
  if station == nil then
    return false, why
  end
  local kind = command.kind

  if kind == "BuyNow" or (kind == "PlaceOrder" and command.to == "buy") then
    local type = command.type or ""
    if Market.Index(type) == nil then
      return false, "no such item type"
    elseif not wholeQuantity(command.quantity) then
      return false, "no such quantity"
    end
    local quantity = command.quantity :: number
    if kind == "BuyNow" then
      local cost = Market.BuyCost(state, station, type, quantity)
      if cost == nil then
        return false, "the station has not that many"
      elseif cost > state.wallet then
        return false, "not enough credits"
      end
      return true
    end
    local price = command.price or 0
    if price <= 0 or price % 1 ~= 0 then
      return false, "no such price"
    elseif math.ceil(price * quantity * (1 + Market.BROKER_FEE)) > state.wallet then
      return false, "not enough credits"
    end
    return true

  elseif kind == "SellNow" or (kind == "PlaceOrder" and command.to == "sell") then
    local item = state.items[command.item or 0]
    if item == nil or item.holder ~= station or item.place ~= "hangar" then
      return false, "that is not in the hangar here"
    end
    local quantity = command.quantity or item.quantity
    if not wholeQuantity(quantity) or quantity > item.quantity then
      return false, "no such quantity"
    end
    if kind == "PlaceOrder" then
      local price = command.price or 0
      if price <= 0 or price % 1 ~= 0 then
        return false, "no such price"
      elseif math.ceil(price * quantity * Market.BROKER_FEE) > state.wallet then
        return false, "not enough credits for the broker"
      end
    end
    return true

  elseif kind == "PlaceOrder" then
    return false, "buy or sell?"

  elseif kind == "CancelOrder" then
    local order = state.orders[command.order or 0]
    if order == nil then
      return false, "no such order"
    elseif order.station ~= station then
      return false, "that order is at another station"
    end
    return true
  end
  return false, `unknown command '{kind}'`
end

local function removeOrder(state: State.State, order: State.Order)
  state.orders[order.id] = nil
  State.RemoveId(state.orderIds, order.id)
end

function Market.Apply(state: State.State, command: State.Command, events: { Event })
  local station = state.ships[command.actor].docked
  local econ = Market.For(state, station)
  local kind = command.kind

  if kind == "BuyNow" then
    local type, quantity = command.type :: string, command.quantity :: number
    local cost = math.ceil(Economy.Buy(econ, 1, Market.Index(type) :: number, quantity) :: number)
    Wallet.Pay(state, -cost, "market purchase", events)
    Items.Add(state, type, quantity, station, "hangar")
    record(state, station, type, quantity, cost)
    table.insert(events, { kind = "Bought", type = type, quantity = quantity, cost = cost })

  elseif kind == "SellNow" then
    local item = state.items[command.item :: number]
    local type = item.type
    local quantity = command.quantity or item.quantity
    local gross = Economy.Sell(econ, 1, Market.Index(type) :: number, quantity)
    local net = math.floor(gross * (1 - Market.SALES_TAX))
    Items.Take(state, item, quantity)
    Wallet.Pay(state, net, "market sale", events)
    record(state, station, type, quantity, math.floor(gross))
    table.insert(events, { kind = "Sold", type = type, quantity = quantity, revenue = net })

  elseif kind == "PlaceOrder" then
    local price = command.price :: number
    local order: State.Order
    if command.to == "sell" then
      local item = state.items[command.item :: number]
      local quantity = command.quantity or item.quantity
      order = { id = State.NewId(state), station = station, side = "sell", type = item.type, quantity = quantity,
        price = price, placed = state.tick }
      Items.Take(state, item, quantity)
      Wallet.Pay(state, -math.ceil(price * quantity * Market.BROKER_FEE), "broker's fee", events)
    else
      local quantity = command.quantity :: number
      order = { id = State.NewId(state), station = station, side = "buy", type = command.type :: string,
        quantity = quantity, price = price, placed = state.tick }
      Wallet.Pay(state, -math.ceil(price * quantity * Market.BROKER_FEE), "broker's fee", events)
      Wallet.Pay(state, -price * quantity, "buy order escrow", events)
    end
    state.orders[order.id] = order
    table.insert(state.orderIds, order.id)
    table.insert(events, { kind = "OrderPlaced", order = order.id })

  elseif kind == "CancelOrder" then
    local order = state.orders[command.order :: number]
    if order.side == "sell" then
      Items.Add(state, order.type, order.quantity, order.station, "hangar")
    else
      Wallet.Pay(state, order.price * order.quantity, "buy order cancelled", events)
    end
    removeOrder(state, order)
    table.insert(events, { kind = "OrderCancelled", order = order.id })
  end
end

-- ---------------------------------------------------------------------
-- The markets' own minute

-- Fill what can be filled of one order. The station takes or gives a few
-- units a minute at most: a tenth of its normal stock an hour, and at
-- least one.
local function fill(state: State.State, order: State.Order, econ: Economy.Economy, events: { Event })
  local index = Market.Index(order.type) :: number
  local normal = econ.nodes[1].target[index]
  local limit = math.max(1, math.floor(normal * 0.1 * Market.STEP_TICKS / 3600))
  local units, value = 0, 0
  while units < limit and order.quantity > 0 do
    if order.side == "sell" then
      if Economy.SellRevenue(econ, 1, index, 1) < order.price then
        break
      end
      Economy.Sell(econ, 1, index, 1)
    else
      local ask = Economy.BuyCost(econ, 1, index, 1)
      if ask == nil or ask > order.price then
        break
      end
      Economy.Buy(econ, 1, index, 1)
    end
    units += 1
    value += order.price
    order.quantity -= 1
  end
  if units == 0 then
    return
  end
  if order.side == "sell" then
    Wallet.Pay(state, math.floor(value * (1 - Market.SALES_TAX)), "sell order filled", events)
  else
    Items.Add(state, order.type, units, order.station, "hangar")
  end
  record(state, order.station, order.type, units, value)
  table.insert(events, { kind = "OrderFilled", order = order.id, type = order.type, side = order.side,
    units = units, left = order.quantity })
  if order.quantity == 0 then
    removeOrder(state, order)
  end
end

-- Once a game minute: every market drifts back toward normal, and
-- standing orders fill where the price allows.
function Market.Step(state: State.State, events: { Event })
  if state.tick % Market.STEP_TICKS ~= 0 then
    return
  end
  for _, station in state.marketIds do
    Economy.Step(state.markets[station], Market.STEP_TICKS / 3600)
  end
  for _, id in table.clone(state.orderIds) do
    local order = state.orders[id]
    fill(state, order, Market.For(state, order.station), events)
  end
end

return Market
