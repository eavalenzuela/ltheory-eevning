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
-- large one costs more per unit than a small one, and pays the station's
-- spread: it sells a little above the going price and buys a little
-- below.
--
-- A standing order names its own price and waits for the station's
-- customers. A sell order fills while it asks no more than the station
-- would for the same unit: the customers take the cheaper offer. A buy
-- order fills while it bids no less than the station would. So an order
-- earns the spread a trade at once gives away, but slowly: a station's
-- customers move a tenth of its normal stock an hour, shared between the
-- orders for a type. What an order sells still lands in the local market
-- and what it buys leaves it, so the price moves against a large order
-- until the wider world has absorbed it. A sell order's goods and a buy
-- order's credits sit in escrow until it fills or is cancelled.
--
-- Selling pays a sales tax; placing an order pays a broker's fee. The
-- two together are more than the spread, so buying and selling the same
-- thing at one station never pays. (Why it cannot: every unit an order
-- moves is priced off the stretch of the price curve that unit covers,
-- so whatever path the stock takes, coming back to where it started
-- gains at most the two spreads.)
--
-- (When the strategic layer arrives these markets will be derived from
-- the stocks of the system they are in, not from a fixed normal level.)

local Economy = require("@lt/Core/Strategic/Economy")
local Factions = require("@lt/Core/Data/Factions")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local Standings = require("@lt/Core/Assets/Standings")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local Types = require("@lt/Core/Data/Types")
local Corporation = require("@lt/Core/Assets/Corporation")
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

-- The player's sales tax and broker's fee, each a tenth lower for every
-- level of the skill for it.
-- (At a station, both also follow from what its faction thinks of the
-- pilot: Assets/Standings.)
function Market.Tax(state: State.State, station: number?): number
  return Market.SALES_TAX * (1 - 0.1 * math.max(0, state.skills.accounting or 0))
    * (if station then Standings.Fees(state, station) else 1)
end

function Market.Fee(state: State.State, station: number?): number
  return Market.BROKER_FEE * (1 - 0.1 * math.max(0, state.skills["broker.relations"] or 0))
    * (if station then Standings.Fees(state, station) else 1)
end

-- How much a station normally holds of a type, in units. Raw materials
-- and ammunition are deep markets: the pilot is one of many who mine and
-- shoot, and a hold of ore should not move the price much.
local function normalStock(info: Types.Info): number
  if info.category == "planetary" then
    -- (raw materials are worth too little for anyone to keep a mountain of)
    return math.max(100, math.min(200000, math.floor(3000000 / info.basePrice)))
  elseif info.category == "moon" then
    -- (thinly traded: a tower's output is more than one station takes at its price)
    return math.max(100, math.floor(1200000 / info.basePrice))
  elseif info.category == "ore" or info.category == "mineral" or info.category == "component" then
    return math.max(100, math.floor(6000000 / info.basePrice))
  elseif info.category == "charge" then
    return math.max(100, math.floor(3000000 / info.basePrice))
  elseif info.category == "structure" then
    -- Fuel is burnt by the hour and bought by the hold; a tower is a rare sale.
    return if info.id == "fuel.block" then math.max(100, math.floor(3000000 / info.basePrice))
      elseif info.id == "colony.command" then 20
      else 6
  elseif info.category == "ship" then
    return 10
  elseif info.category == "implant" then
    return 12
  elseif info.category == "goods" then
    return 40
  elseif info.category == "blueprint" or info.category == "skillbook" then
    -- Printed to order: buying one hardly moves the price.
    return 1000
  end
  return 40
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

-- Whose a station is shows in its market. A faction's stations have
-- its own hulls and its own kinds of weapon, and what they fire, at
-- the price anybody would ask. Another faction's are imports: dearer
-- by this much, and of another faction's hulls a station keeps only a
-- few (which is why they have to be dearer by so much: a market of
-- four moves a long way for one hull). So a hull or a rack of guns
-- bought where it is made sells for more where it is not, by more than
-- the spread and the tax, and rounds by the hold do too.
Market.FOREIGN_HULL = 1.4
Market.FOREIGN_ARMS = 1.25
Market.FOREIGN_STOCK = 4

-- The kinds of weapon a faction's own ships carry: its turrets, and
-- missiles if a fair share of its hardpoints are launchers.
local function families(faction: string): { [string]: boolean }
  local own = Factions.byId[faction]
  if own == nil then
    return {}
  end
  return { [own.weapon] = true, missile = own.launchers >= 0.3 }
end

-- What a faction's station makes of a type: how much dearer than
-- anybody's it is there (1: no dearer), and whether it has only a few.
function Market.Leaning(faction: string, id: string): (number, boolean)
  if Factions.byId[faction] == nil then
    return 1, false
  end
  local hull = Ships.byId[id]
  if hull then
    local builder = Factions.byId[hull.lineage]
    if builder and builder.kind == "human" and builder.id ~= faction then
      return Market.FOREIGN_HULL, true
    end
    return 1, false
  end
  local module, charge = Modules.byId[id], Modules.chargeById[id]
  local family = if module and module.weapon then module.weapon.family elseif charge then charge.family else nil
  if family and not families(faction)[family] then
    return Market.FOREIGN_ARMS, false
  end
  return 1, false
end

-- A market as it is on the day it opens: every type there is, at its
-- normal stock, valued as a station of that kind, and of that faction,
-- values it.
local function open(name: string, variety: string, faction: string): Economy.Economy
  local tastes = TASTES[variety] or {}
  local classes: { Economy.Class } = {}
  for _, id in Types.Ids() do
    local info = Types.Info(id)
    table.insert(classes, { id = id, par = info.basePrice * (tastes[info.category] or 1) * (Market.Leaning(faction, id)), cover = 0,
      need = 0 })
  end
  local econ = Economy.New(classes, {})
  local node = Economy.AddNode(econ, name, 0)
  for index, id in Types.Ids() do
    local info = Types.Info(id)
    local normal = normalStock(info)
    local _, few = Market.Leaning(faction, id)
    if few then
      normal = math.min(normal, Market.FOREIGN_STOCK)
    end
    if info.scarce then
      -- Nobody brings these: a station has what pilots have sold it,
      -- would like a few, and pays well while it has none.
      Economy.SetTarget(econ, node, index, 4)
      Economy.SetStock(econ, node, index, 0)
      econ.nodes[node].anchor[index] = 0
    else
      Economy.SetTarget(econ, node, index, normal)
      Economy.SetStock(econ, node, index, normal)
      -- The wider world restores a quarter of a shortfall an hour.
      econ.nodes[node].anchor[index] = normal * 0.25
    end
  end
  return econ
end

-- What a market keeps for each type, by the type's place among them all.
local BY_TYPE = { "initial", "produced", "consumed", "used", "anchorIn", "anchorOut", "bought", "sold", "moved", "lost" }
local OF_NODE = { "stock", "target", "anchor", "taste" }

-- Set the markets of a save out by the types there are now.
--
-- A market keeps its figures by a type's place among all the types, and
-- the game grows: a save from before a type was added (or from after one
-- was dropped) has its markets set out by a list that is no longer the
-- list. Each such market is opened afresh and given back every figure
-- it had for a type that is still there, so a type keeps its own stock
-- and a new type starts at its normal one. A market already set out by
-- today's list is not touched. (Core.Load does this for every save.)
function Market.Reconcile(state: State.State)
  local ids = Types.Ids()
  for _, station in state.marketIds do
    local old = state.markets[station]
    local same = #old.classes == #ids
    for index, class in old.classes do
      same = same and class.id == ids[index]
    end
    if not same then
      local object = Space.Object(state, station)
      local fresh = open(old.nodes[1].name, if object then object.variety else "",
        if object then state.galaxy.systems[Space.SystemOf(state, station)].nearest else "")
      local was: { [string]: number } = {}
      for index, class in old.classes do
        was[class.id] = index
      end
      local from, to = old :: any, fresh :: any
      for index, id in ids do
        local before = was[id]
        if before then
          fresh.classes[index] = old.classes[before]
          for _, name in BY_TYPE do
            to[name][index] = from[name][before]
          end
          for _, name in OF_NODE do
            to.nodes[1][name][index] = from.nodes[1][name][before]
          end
        end
      end
      fresh.hours, fresh.steps = old.hours, old.steps
      fresh.nodes[1].met = old.nodes[1].met
      state.markets[station] = fresh
    end
  end
end

-- A station's market, made on first use.
function Market.For(state: State.State, station: number): Economy.Economy
  local existing = state.markets[station]
  if existing then
    return existing
  end
  local object = assert(Space.Object(state, station), "no such station")
  -- (it is the market of the faction whose tower the station is: the
  -- one whose homeworld is nearest)
  local econ = open(object.name, object.variety, state.galaxy.systems[Space.SystemOf(state, station)].nearest)
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
  -- The most a sell order can ask, and the least a buy order can bid
  -- (nil if the station has none), and still fill now.
  sellAt: number,
  buyAt: number?,
}

local OVER = (1 + Economy.SPREAD) / (1 - Economy.SPREAD)

function Market.Quote(state: State.State, station: number, type: string): Quote
  local econ = Market.For(state, station)
  local index = assert(Market.Index(type), `no item type '{type}'`)
  local ask = Economy.BuyCost(econ, 1, index, 1)
  local bid = Economy.SellRevenue(econ, 1, index, 1)
  return {
    ask = ask, bid = bid, stock = math.floor(econ.nodes[1].stock[index]),
    sellAt = bid * OVER, buyAt = if ask then ask / OVER else nil,
  }
end

-- A station's market for a look at it: the market itself where it has
-- been opened, and otherwise one as any station of its kind and faction
-- has on the day it opens, which is not kept (and is never to be traded
-- with). Nil if that is no station. So what a market some jumps off
-- asks can be said without opening it.
local unopened: { [string]: Economy.Economy } = {}

function Market.Glance(state: State.State, station: number): Economy.Economy?
  local existing = state.markets[station]
  if existing then
    return existing
  end
  local object = Space.Peek(state, station)
  if object == nil or object.kind ~= "station" then
    return nil
  end
  local faction = state.galaxy.systems[Space.SystemOf(state, station)].nearest
  local key = `{object.variety}:{faction}`
  local econ = unopened[key]
  if econ == nil then
    econ = open(key, object.variety, faction)
    unopened[key] = econ
  end
  return econ
end

-- What a station some way off has of a type, and what 'quantity' of it
-- (or all it has, if that is fewer) would cost there now: the units
-- that is, and the cost. Nothing is opened or changed. (0, 0: it has
-- none, or is no station.)
function Market.Asks(state: State.State, station: number, type: string, quantity: number): (number, number)
  local econ = Market.Glance(state, station)
  local index = Market.Index(type)
  if econ == nil or index == nil then
    return 0, 0
  end
  local units = math.min(quantity, math.floor(econ.nodes[1].stock[index]))
  if units < 1 then
    return 0, 0
  end
  return units, math.ceil(Economy.BuyCost(econ, 1, index, units) :: number)
end

-- How many of a type, 'most' at most, a station's market will sell now
-- to somebody who pays no more than 'limit' credits for one on the
-- average of the purchase, and no more than 'purse' credits in all. (A
-- market asks more for each unit than for the one before: so it is the
-- first so many, and a search finds how many.)
function Market.Within(state: State.State, station: number, type: string, most: number, limit: number, purse: number): number
  local econ = Market.For(state, station)
  local index = assert(Market.Index(type), `no item type '{type}'`)
  local function fine(units: number): boolean
    local cost = Economy.BuyCost(econ, 1, index, units)
    return cost ~= nil and math.ceil(cost) <= limit * units and math.ceil(cost) <= purse
  end
  local low, high = 0, math.min(most, math.floor(econ.nodes[1].stock[index]))
  while low < high do
    local middle = (low + high + 1) // 2
    if fine(middle) then
      low = middle
    else
      high = middle - 1
    end
  end
  return low
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
  return math.floor(revenue * (1 - Market.Tax(state, station)))
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
    elseif math.ceil(price * quantity * (1 + Market.Fee(state, station))) > state.wallet then
      return false, "not enough credits"
    end
    return true

  elseif kind == "SellNow" or (kind == "PlaceOrder" and command.to == "sell") then
    local item = state.items[command.item or 0]
    if item == nil or item.holder ~= station or not Items.IsStore(item.place) then
      return false, "that is not in the hangar here"
    elseif kind == "PlaceOrder" and item.place ~= "hangar" then
      -- (an order is the pilot's own: what it fetches is paid to them)
      return false, "an order is placed from your own hangar"
    end
    local quantity = command.quantity or item.quantity
    if not wholeQuantity(quantity) or quantity > item.quantity then
      return false, "no such quantity"
    end
    if kind == "PlaceOrder" then
      local price = command.price or 0
      if price <= 0 or price % 1 ~= 0 then
        return false, "no such price"
      elseif math.ceil(price * quantity * Market.Fee(state, station)) > state.wallet then
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

  elseif kind == "ModifyOrder" then
    -- An order's price changed, where the order is.
    local order = state.orders[command.order or 0]
    local price = command.price or 0
    if order == nil then
      return false, "no such order"
    elseif order.station ~= station then
      return false, "that order is at another station"
    elseif price <= 0 or price % 1 ~= 0 then
      return false, "no such price"
    elseif price == order.price then
      return false, "that is its price already"
    end
    local fee, held = Market.Reprice(state, order, price)
    if fee + math.max(0, held) > state.wallet then
      return false, "not enough credits"
    end
    return true
  end
  return false, `unknown command '{kind}'`
end

-- What changing an order's price costs: the broker's fee, on what the
-- order has gained in worth (nothing, for a price brought down); and,
-- for a buy order, how much more it has to hold (less than nothing: it
-- gives some back).
function Market.Reprice(state: State.State, order: State.Order, price: number): (number, number)
  local more = (price - order.price) * order.quantity
  local fee = if more > 0 then math.ceil(more * Market.Fee(state, order.station)) else 0
  return fee, if order.side == "buy" then more else 0
end

-- Sell so many of an item to a station's market, at once: the item
-- goes, the wallet is paid what it fetched less the tax, and the trade
-- is on the station's books. Returns what was paid. (The item is the
-- pilot's own, wherever it is: in the hangar there, or in the hold of a
-- ship of theirs docked there.) 'business': it is a hired pilot who
-- sells, or it is sold out of the corporation's hangar, and what it
-- fetches is the corporation's, if there is one (Assets/Corporation).
function Market.Sell(state: State.State, station: number, item: State.Item, quantity: number, events: { Event },
  business: boolean?): number
  local type = item.type
  local gross = Economy.Sell(Market.For(state, station), 1, Market.Index(type) :: number, quantity)
  local net = math.floor(gross * (1 - Market.Tax(state, station)))
  Items.Take(state, item, quantity)
  if business then
    -- (what a drill brought up is a head of its own on the books)
    Corporation.Earn(state, net, if Types.Info(type).category == "moon" then "moon sale" else "market sale", events)
  else
    Wallet.Pay(state, net, "market sale", events)
  end
  record(state, station, type, quantity, math.floor(gross))
  table.insert(events, { kind = "Sold", type = type, quantity = quantity, revenue = net })
  return net
end

-- Buy so many of a type from a station's market, at once: they are put
-- in 'place' of 'holder' (the pilot's hangar at the station, or the
-- hold of a ship of theirs docked there), what they cost is paid, and
-- the trade is on the station's books. Returns what was paid.
-- 'business': it is a hired pilot who buys, and the corporation that
-- pays, if there is one (Assets/Corporation).
function Market.Buy(state: State.State, station: number, type: string, quantity: number, holder: number,
  place: "hangar" | "cargo", events: { Event }, business: boolean?): number
  local cost = math.ceil(Economy.Buy(Market.For(state, station), 1, Market.Index(type) :: number, quantity) :: number)
  if business then
    -- (and so is what the towers burn)
    Corporation.Spend(state, cost, if type == Structures.FUEL.id then "fuel" else "market purchase", events)
  else
    Wallet.Pay(state, -cost, "market purchase", events)
  end
  Items.Add(state, type, quantity, holder, place)
  record(state, station, type, quantity, cost)
  -- (a hired pilot's buying is said by whoever sent them: Tactical/Fleet)
  if not business then
    table.insert(events, { kind = "Bought", type = type, quantity = quantity, cost = cost })
  end
  return cost
end

local function removeOrder(state: State.State, order: State.Order)
  state.orders[order.id] = nil
  State.RemoveId(state.orderIds, order.id)
end

function Market.Apply(state: State.State, command: State.Command, events: { Event })
  local station = state.ships[command.actor].docked
  local kind = command.kind

  if kind == "BuyNow" then
    Market.Buy(state, station, command.type :: string, command.quantity :: number, station, "hangar", events)

  elseif kind == "SellNow" then
    local item = state.items[command.item :: number]
    -- (what is sold out of the corporation's hangar is paid to the corporation)
    Market.Sell(state, station, item, command.quantity or item.quantity, events, item.place == "corporate")

  elseif kind == "PlaceOrder" then
    local price = command.price :: number
    local order: State.Order
    if command.to == "sell" then
      local item = state.items[command.item :: number]
      local quantity = command.quantity or item.quantity
      order = { id = State.NewId(state), station = station, side = "sell", type = item.type, quantity = quantity,
        price = price, placed = state.tick }
      Items.Take(state, item, quantity)
      Wallet.Pay(state, -math.ceil(price * quantity * Market.Fee(state, station)), "broker's fee", events)
    else
      local quantity = command.quantity :: number
      order = { id = State.NewId(state), station = station, side = "buy", type = command.type :: string,
        quantity = quantity, price = price, placed = state.tick }
      Wallet.Pay(state, -math.ceil(price * quantity * Market.Fee(state, station)), "broker's fee", events)
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

  elseif kind == "ModifyOrder" then
    local order = state.orders[command.order :: number]
    local price = command.price :: number
    local fee, held = Market.Reprice(state, order, price)
    if fee > 0 then
      Wallet.Pay(state, -fee, "broker's fee", events)
    end
    if held ~= 0 then
      Wallet.Pay(state, -held, if held > 0 then "buy order escrow" else "buy order repriced", events)
    end
    local was = order.price
    order.price = price
    table.insert(events, { kind = "OrderChanged", order = order.id, type = order.type, was = was, price = price, fee = fee })
  end
end

-- ---------------------------------------------------------------------
-- The markets' own minute

-- The share of a station's normal stock of a type its customers move in
-- an hour.
Market.CUSTOMERS = 0.1

-- How many units of a type a station's customers will take or bring in
-- the market minute that ends now. A whole number each minute that adds
-- up to the hourly rate, so something traded once an hour is.
local function customers(state: State.State, econ: Economy.Economy, index: number): number
  local perStep = econ.nodes[1].target[index] * Market.CUSTOMERS * Market.STEP_TICKS / 3600
  local step = state.tick // Market.STEP_TICKS
  return math.floor(perStep * step + 1e-9) - math.floor(perStep * (step - 1) + 1e-9)
end

-- Fill what can be filled of one order with at most 'limit' units;
-- returns the units filled.
local function fill(state: State.State, order: State.Order, econ: Economy.Economy, limit: number, events: { Event }): number
  local index = Market.Index(order.type) :: number
  local units, value = 0, 0
  while units < limit and order.quantity > 0 do
    if order.side == "sell" then
      -- The unit this would add to the local market: what the station
      -- would pay for it, and so what it would then ask for it.
      if order.price > Economy.SellRevenue(econ, 1, index, 1) * OVER then
        break
      end
      Economy.Sell(econ, 1, index, 1)
    else
      -- The unit this would take: what the station asks for it, and so
      -- what it would have paid for it.
      local ask = Economy.BuyCost(econ, 1, index, 1)
      if ask == nil or order.price < ask / OVER then
        break
      end
      Economy.Buy(econ, 1, index, 1)
    end
    units += 1
    value += order.price
    order.quantity -= 1
  end
  if units == 0 then
    return 0
  end
  if order.side == "sell" then
    Wallet.Pay(state, math.floor(value * (1 - Market.Tax(state, order.station))), "sell order filled", events)
  else
    Items.Add(state, order.type, units, order.station, "hangar")
  end
  record(state, order.station, order.type, units, value)
  table.insert(events, { kind = "OrderFilled", order = order.id, type = order.type, side = order.side,
    units = units, left = order.quantity })
  if order.quantity == 0 then
    removeOrder(state, order)
  end
  return units
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
  -- Orders in the order they were placed; those for the same thing on the
  -- same side share the minute's customers, first come first served.
  local taken: { [string]: number } = {}
  for _, id in table.clone(state.orderIds) do
    local order = state.orders[id]
    local econ = Market.For(state, order.station)
    local key = `{order.station} {order.side} {order.type}`
    local left = customers(state, econ, Market.Index(order.type) :: number) - (taken[key] or 0)
    if left > 0 then
      taken[key] = (taken[key] or 0) + fill(state, order, econ, left, events)
    end
  end
end

return Market
