--!strict
--!native
-- The background economy: stocks and prices of commodity classes at each
-- system, production and consumption there, and goods flowing along the
-- gates toward where they are dear. (docs/roadmap.md §6.)
--
-- This replaces the prototype's haulers. Nothing here is an agent that
-- can die, run out of money or wait for another: every quantity changes
-- continuously, so the economy cannot deadlock. Discrete things (a
-- player's hold of ore, a faction's supply convoy) take part through Buy
-- and Sell, against the same prices.
--
-- The rules, per class of goods at a node:
--
--   target    T = cover * max(what the node consumes, makes or uses per
--                 hour at full rate, a floor)
--   price     p = par * clamp(T / S, 1/4, 4)          S = stock
--   consume   need * (p / par)^-1/2 per hour, as far as stock allows
--   produce   each facility runs at capacity * (how well stocked its
--             inputs are) * (how profitable it is here: full speed at
--             its par margin, stopped at no margin)
--   flow      along an open edge, from the cheaper end to the dearer,
--             once the gap exceeds the edge's cost (times the class's
--             bulk: cheap heavy goods do not travel far): conductance * excess
--             gap per hour in value, and never more than would close the
--             gap (so prices approach each other and cannot overshoot)
--             (An edge may also lose a share of what it carries: piracy.)
--   anchor    a few nodes sell and buy near par at a limited rate; they
--             are the economy's boundary, and how much passes through
--             them is watched (a healthy economy barely uses them)
--
-- Targets depend only on what a node is, never on how it has fared, so
-- a node that was starved wants exactly what it wanted before: there is
-- no state for a slump to hide in. par prices are fixed, so the price
-- level cannot drift.
--
-- Rates are per game hour and every step takes its length in hours, so
-- the step size can change without retuning. Stocks are real numbers
-- (these are bulk aggregates, not items). The state is plain data.

local Economy = {}

export type Class = {
  id: string,
  par: number,      -- credits per unit when stock is on target
  cover: number,    -- hours of throughput a node aims to hold
  need: number,     -- units a unit of population consumes per hour at par
  -- How costly it is to haul for what it is worth: an edge's cost is
  -- multiplied by this. Ore is bulky for its price and electronics are
  -- not. 1 if absent.
  bulk: number?,
  -- A station's market only (Assets/Market): what its par is where
  -- every price is normal. Its par follows what the system it is in
  -- makes of that (Strategic/Commerce).
  base: number?,
}

export type Amount = { class: number, amount: number }

-- What a facility does per hour at capacity 1. 'margin' is the profit
-- over cost it earns when every price is at par.
export type Recipe = { id: string, inputs: { Amount }, outputs: { Amount }, margin: number }

export type Facility = { recipe: number, capacity: number, activity: number }

export type Node = {
  id: number,
  name: string,
  population: number,
  facilities: { Facility },
  stock: { number },    -- by class index
  target: { number },   -- by class index; fixed by what the node is
  anchor: { number },   -- by class index: units per hour it trades per unit of
                        -- relative price gap from par; 0 for none
  taste: { number },    -- by class index: how much of a class its people use,
                        -- relative to the class's 'need' (1 for most)
  met: number,          -- share of its population's needs met last step
}

export type Edge = {
  a: number,
  b: number,
  conductance: number,  -- credits per hour of goods moved per unit of
                        -- relative price gap beyond the cost
  cost: number,         -- the gap, as a fraction of par, that trade must beat
  open: boolean,
  loss: number,         -- the share of what is carried that never arrives (piracy)
}

export type Economy = {
  classes: { Class },
  recipes: { Recipe },
  nodes: { Node },
  edges: { Edge },
  hours: number,
  steps: number,
  -- Running totals by class index, for the conservation check and the
  -- reports: everything that entered or left any stock.
  initial: { number },
  produced: { number },
  consumed: { number },   -- by population
  used: { number },       -- as recipe inputs
  anchorIn: { number },
  anchorOut: { number },
  bought: { number },     -- taken out through Buy
  sold: { number },       -- put in through Sell
  moved: { number },      -- carried along edges (not a source or sink)
  lost: { number },       -- lost on the way, or taken from a stock by force
}

local PRICE_MIN, PRICE_MAX = 0.25, 4
-- (Consumption falls with the square root of the price: an elasticity of
-- a half, written into 'consume' as a square root.)
-- A facility needs this many hours of inputs in stock to run flat out.
local INPUT_HOURS = 2
-- The share of its remaining gap an anchor may close in one step.
local ALPHA = 0.5
-- No node aims to hold less than this many credits' worth of a class: a
-- system that neither makes nor uses something still has some on sale.
-- (A thin stock makes a twitchy price: a hold or two would swing it.)
local TARGET_FLOOR_VALUE = 2000
-- What a trader pays over, or gets under, the curve.
Economy.SPREAD = 0.02

-- ---------------------------------------------------------------------
-- Building one

local function zeros(n: number): { number }
  return table.create(n, 0)
end

function Economy.New(classes: { Class }, recipes: { Recipe }): Economy
  local n = #classes
  return {
    classes = classes, recipes = recipes, nodes = {}, edges = {}, hours = 0, steps = 0,
    initial = zeros(n), produced = zeros(n), consumed = zeros(n), used = zeros(n),
    anchorIn = zeros(n), anchorOut = zeros(n), bought = zeros(n), sold = zeros(n), moved = zeros(n),
    lost = zeros(n),
  }
end

-- The stock a node aims to hold of each class: 'cover' hours of the most
-- it consumes, makes or uses in an hour.
local function targets(econ: Economy, node: Node): { number }
  local rate = zeros(#econ.classes)
  for g, class in econ.classes do
    rate[g] = node.population * class.need * node.taste[g]
  end
  for _, facility in node.facilities do
    local recipe = econ.recipes[facility.recipe]
    for _, input in recipe.inputs do
      rate[input.class] = math.max(rate[input.class], facility.capacity * input.amount)
    end
    for _, output in recipe.outputs do
      rate[output.class] = math.max(rate[output.class], facility.capacity * output.amount)
    end
  end
  local target = zeros(#econ.classes)
  for g, class in econ.classes do
    target[g] = math.max(class.cover * rate[g], TARGET_FLOOR_VALUE / class.par)
  end
  return target
end

-- Add a node; its stocks start on target. Returns its id. 'taste', if
-- given, scales what its people use of each class.
function Economy.AddNode(econ: Economy, name: string, population: number,
  facilities: { { recipe: number, capacity: number } }?, taste: { number }?): number
  local node: Node = {
    id = #econ.nodes + 1, name = name, population = population, facilities = {},
    stock = {}, target = {}, anchor = zeros(#econ.classes), taste = taste or table.create(#econ.classes, 1), met = 1,
  }
  local given: { { recipe: number, capacity: number } } = facilities or {}
  for _, f in given do
    table.insert(node.facilities, { recipe = f.recipe, capacity = f.capacity, activity = 0 })
  end
  node.target = targets(econ, node)
  node.stock = table.clone(node.target)
  for g, amount in node.stock do
    econ.initial[g] += amount
  end
  table.insert(econ.nodes, node)
  return node.id
end

function Economy.AddEdge(econ: Economy, a: number, b: number, conductance: number, cost: number): number
  table.insert(econ.edges, { a = a, b = b, conductance = conductance, cost = cost, open = true, loss = 0 })
  return #econ.edges
end

-- Set the stock a node aims to hold of a class, overriding what its
-- population and facilities imply (a station's market has neither).
function Economy.SetTarget(econ: Economy, node: number, class: number, target: number)
  econ.nodes[node].target[class] = target
end

-- Set a node's stock of a class, as part of setting a scene up (it
-- counts as starting stock, not as goods created).
function Economy.SetStock(econ: Economy, node: number, class: number, amount: number)
  local n = econ.nodes[node]
  econ.initial[class] += amount - n.stock[class]
  n.stock[class] = amount
end

-- ---------------------------------------------------------------------
-- Prices

function Economy.Price(econ: Economy, node: number, class: number): number
  local n = econ.nodes[node]
  local stock = n.stock[class]
  local ratio = if stock <= 0 then PRICE_MAX else math.clamp(n.target[class] / stock, PRICE_MIN, PRICE_MAX)
  return econ.classes[class].par * ratio
end

-- Price as a multiple of par, for a target and a stock.
local function ratioAt(target: number, stock: number): number
  return if stock <= 0 then PRICE_MAX else math.clamp(target / stock, PRICE_MIN, PRICE_MAX)
end

-- The price a class would have at a node with so much of it in stock.
function Economy.PriceAt(econ: Economy, node: number, class: number, stock: number): number
  return econ.classes[class].par * ratioAt(econ.nodes[node].target[class], stock)
end

-- The value of the goods between two stock levels, low to high, along
-- the price curve: par at 4x below a quarter of target, par * T / S in
-- the middle, par / 4 above four times target.
local function curveValue(par: number, target: number, low: number, high: number): number
  local knee1, knee2 = target / PRICE_MAX, target / PRICE_MIN
  local value = 0
  if low < knee1 then
    value += par * PRICE_MAX * (math.min(high, knee1) - low)
  end
  local a, b = math.max(low, knee1), math.min(high, knee2)
  if b > a then
    value += par * target * math.log(b / a)
  end
  if high > knee2 then
    value += par * PRICE_MIN * (high - math.max(low, knee2))
  end
  return value
end

-- ---------------------------------------------------------------------
-- Trading against a node (the player, a convoy, a bot)

-- What 'quantity' units would cost here now, walking up the curve. More
-- than the node holds cannot be bought: returns nil.
function Economy.BuyCost(econ: Economy, node: number, class: number, quantity: number): number?
  local n = econ.nodes[node]
  local stock = n.stock[class]
  if quantity > stock then
    return nil
  end
  return curveValue(econ.classes[class].par, n.target[class], stock - quantity, stock) * (1 + Economy.SPREAD)
end

-- What 'quantity' units would fetch here now, walking down the curve.
function Economy.SellRevenue(econ: Economy, node: number, class: number, quantity: number): number
  local n = econ.nodes[node]
  local stock = n.stock[class]
  return curveValue(econ.classes[class].par, n.target[class], stock, stock + quantity) * (1 - Economy.SPREAD)
end

-- Take goods out of a node's stock; returns what they cost, or nil if it
-- does not hold that many. The caller pays: the market itself has no
-- wallet.
function Economy.Buy(econ: Economy, node: number, class: number, quantity: number): number?
  local cost = Economy.BuyCost(econ, node, class, quantity)
  if cost then
    econ.nodes[node].stock[class] -= quantity
    econ.bought[class] += quantity
  end
  return cost
end

-- Take up to 'quantity' out of a node's stock by force (a raid): nobody
-- is paid. Returns how much was there to take.
function Economy.Take(econ: Economy, node: number, class: number, quantity: number): number
  local stock = econ.nodes[node].stock
  local taken = math.clamp(quantity, 0, stock[class])
  stock[class] -= taken
  econ.lost[class] += taken
  return taken
end

-- Goods that leave a node's stock for a market that deals with it (a
-- station's, with the system it is in: Assets/Market), and goods that
-- come to it from one: no price is worked out, the market having paid
-- its own. Draw returns how much was there to take.
function Economy.Draw(econ: Economy, node: number, class: number, quantity: number): number
  local stock = econ.nodes[node].stock
  local taken = math.clamp(quantity, 0, stock[class])
  stock[class] -= taken
  econ.bought[class] += taken
  return taken
end

function Economy.Give(econ: Economy, node: number, class: number, quantity: number)
  econ.nodes[node].stock[class] += quantity
  econ.sold[class] += quantity
end

-- Put goods into a node's stock; returns what they fetched.
function Economy.Sell(econ: Economy, node: number, class: number, quantity: number): number
  local revenue = Economy.SellRevenue(econ, node, class, quantity)
  econ.nodes[node].stock[class] += quantity
  econ.sold[class] += quantity
  return revenue
end

-- ---------------------------------------------------------------------
-- The step
--
-- A node's prices are worked out once, as multiples of par, when its
-- turn comes: its facilities, its people and its anchor all act on the
-- prices the step began with. They are worked out again once the node
-- is done, for the flows, which keep them current as goods move.

-- Fill 'row' with a node's prices as multiples of par.
local function ratios(node: Node, row: { number })
  local target, stock = node.target, node.stock
  for g = 1, #target do
    local held = stock[g]
    row[g] = if held <= 0 then PRICE_MAX else math.clamp(target[g] / held, PRICE_MIN, PRICE_MAX)
  end
end

-- A recipe laid out for the inner loop: its inputs' and outputs' classes
-- and amounts as flat lists, and what a run pays in labour (whatever
-- makes its margin come out at the recipe's own when every price is at
-- par).
type Flat = {
  inClass: { number }, inAmount: { number }, outClass: { number }, outAmount: { number },
  labour: number, margin: number,
}

local function flatten(econ: Economy): { Flat }
  local flats: { Flat } = table.create(#econ.recipes)
  for at, recipe in econ.recipes do
    local flat: Flat = { inClass = {}, inAmount = {}, outClass = {}, outAmount = {}, labour = 0, margin = recipe.margin }
    local inputPar, outputPar = 0, 0
    for index, input in recipe.inputs do
      flat.inClass[index], flat.inAmount[index] = input.class, input.amount
      inputPar += input.amount * econ.classes[input.class].par
    end
    for index, output in recipe.outputs do
      flat.outClass[index], flat.outAmount[index] = output.class, output.amount
      outputPar += output.amount * econ.classes[output.class].par
    end
    flat.labour = outputPar / (1 + recipe.margin) - inputPar
    flats[at] = flat
  end
  return flats
end

-- 'worth' is the node's price of each class in credits (par times the
-- row), worked out once for all its facilities.
local function produce(econ: Economy, node: Node, worth: { number }, flats: { Flat }, dt: number)
  local stock, used, produced = node.stock, econ.used, econ.produced
  local facilities = node.facilities
  for f = 1, #facilities do
    local facility = facilities[f]
    local flat = flats[facility.recipe]
    local inClass, inAmount, outClass, outAmount = flat.inClass, flat.inAmount, flat.outClass, flat.outAmount
    local capacity = facility.capacity
    -- How well stocked the inputs are, and what a run costs and earns at
    -- this node's prices.
    local supplied = 1
    local inputValue, outputValue = 0, 0
    for i = 1, #inClass do
      local g, amount = inClass[i], inAmount[i]
      supplied = math.min(supplied, stock[g] / (capacity * amount * INPUT_HOURS))
      inputValue += amount * worth[g]
    end
    for i = 1, #outClass do
      outputValue += outAmount[i] * worth[outClass[i]]
    end
    local profit = outputValue / (inputValue + flat.labour) - 1
    local activity = capacity * math.clamp(supplied, 0, 1) * math.clamp(profit / flat.margin, 0, 1)
    -- Never use more of an input than is there.
    for i = 1, #inClass do
      activity = math.min(activity, stock[inClass[i]] / (inAmount[i] * dt))
    end
    facility.activity = activity
    if activity > 0 then
      local scale = activity * dt
      for i = 1, #inClass do
        local g, amount = inClass[i], scale * inAmount[i]
        stock[g] -= amount
        used[g] += amount
      end
      for i = 1, #outClass do
        local g, amount = outClass[i], scale * outAmount[i]
        stock[g] += amount
        produced[g] += amount
      end
    end
  end
end

local function consume(econ: Economy, node: Node, row: { number }, dt: number)
  local population = node.population
  if population <= 0 then
    node.met = 1
    return
  end
  local classes, stock, taste, consumed = econ.classes, node.stock, node.taste, econ.consumed
  local wanted, got = 0, 0
  for g = 1, #classes do
    local class = classes[g]
    local need = class.need * taste[g]
    if need > 0 then
      local base = population * need * dt
      -- (the price to the power of minus the elasticity, which is a half)
      local want = base / math.sqrt(row[g])
      local amount = math.min(want, stock[g])
      stock[g] -= amount
      consumed[g] += amount
      wanted += base * class.par
      got += math.min(amount, base) * class.par
    end
  end
  node.met = if wanted > 0 then got / wanted else 1
end

local function anchor(econ: Economy, node: Node, row: { number }, dt: number)
  local stock, target = node.stock, node.target
  for g, rate in node.anchor do
    if rate > 0 then
      local gap = row[g] - 1
      -- Dear here: the anchor sells in. Cheap here: it buys out. Never
      -- past the point where the price would cross par.
      local amount = rate * gap * dt
      local limit = target[g] - stock[g]
      if amount > 0 then
        amount = math.min(amount, math.max(0, limit) * ALPHA)
        stock[g] += amount
        econ.anchorIn[g] += amount
      else
        amount = math.min(-amount, math.max(0, -limit) * ALPHA)
        stock[g] -= amount
        econ.anchorOut[g] += amount
      end
    end
  end
end

-- The gap between two ends of an edge, in multiples of par, left after
-- 'amount' has moved from one to the other.
local function gapAfter(toTarget: number, toStock: number, fromTarget: number, fromStock: number, cost: number,
  amount: number): number
  return ratioAt(toTarget, toStock + amount) - ratioAt(fromTarget, fromStock - amount) - cost
end

-- The amount, no more than 'most', that moved from one end to the other
-- leaves their prices exactly the edge's cost apart. Where both prices
-- stay on the sloping part of the curve that is the root of a quadratic:
--
--   Tt / (St + x) - Tf / (Sf - x) = k
--   k x^2 + (k (St - Sf) - Tt - Tf) x + (Tt Sf - Tf St - k St Sf) = 0
--
-- Otherwise (a price pinned at the ceiling or the floor) it is found by
-- halving.
local function closing(toTarget: number, toStock: number, fromTarget: number, fromStock: number, cost: number,
  most: number): number
  local a = cost
  local b = cost * (toStock - fromStock) - toTarget - fromTarget
  local c = toTarget * fromStock - fromTarget * toStock - cost * toStock * fromStock
  local root = b * b - 4 * a * c
  if root >= 0 and toStock > 0 then
    local x = 2 * c / (-b + math.sqrt(root))
    if x > 0 and x <= most then
      local toRatio, fromRatio = toTarget / (toStock + x), fromTarget / (fromStock - x)
      if toRatio > PRICE_MIN and toRatio < PRICE_MAX and fromRatio > PRICE_MIN and fromRatio < PRICE_MAX then
        return x
      end
    end
  end
  local low, high = 0, most
  for _ = 1, 30 do
    local middle = (low + high) / 2
    if gapAfter(toTarget, toStock, fromTarget, fromStock, cost, middle) > 0 then
      low = middle
    else
      high = middle
    end
  end
  return low
end

local function flow(econ: Economy, edge: Edge, rows: { { number } }, bulks: { number }, dt: number)
  if not edge.open then
    return
  end
  local a, b = econ.nodes[edge.a], econ.nodes[edge.b]
  local aRow, bRow = rows[edge.a], rows[edge.b]
  local reach = edge.conductance * dt
  local kept = 1 - edge.loss
  for g = 1, #aRow do
    local ra, rb = aRow[g], bRow[g]
    local cost = edge.cost * bulks[g]
    -- Most classes on most edges are within the cost of each other, and
    -- nothing moves.
    local gap = math.abs(ra - rb) - cost
    if gap > 0 then
      local from, to = a, b
      if ra > rb then
        from, to = b, a
      end
      local fromStock, toStock, fromTarget, toTarget = from.stock[g], to.stock[g], from.target[g], to.target[g]
      if fromStock > 0 then
        local amount = math.min(reach * gap / econ.classes[g].par, fromStock)
        if gapAfter(toTarget, toStock, fromTarget, fromStock, cost, amount) < 0 then
          -- That much would carry the prices past each other (a thin
          -- stock, or a long step). Move what just closes the gap.
          amount = closing(toTarget, toStock, fromTarget, fromStock, cost, amount)
        end
        -- (What pirates take on the way is lost to both ends. The gap
        -- then closes a little less than was worked out, never more.)
        local arrived = amount * kept
        from.stock[g] = fromStock - amount
        to.stock[g] = toStock + arrived
        econ.moved[g] += amount
        econ.lost[g] += amount - arrived
        local fromRatio, toRatio = ratioAt(fromTarget, fromStock - amount), ratioAt(toTarget, toStock + arrived)
        if ra > rb then
          bRow[g], aRow[g] = fromRatio, toRatio
        else
          aRow[g], bRow[g] = fromRatio, toRatio
        end
      end
    end
  end
end

-- Each node's prices during a step. Not state: every row is filled in
-- afresh before it is read. Kept between steps only to spare the memory
-- of making four hundred lists a step.
local scratch: { { number } } = {}

-- Advance the economy by 'hours' of game time.
function Economy.Step(econ: Economy, hours: number)
  local classes = econ.classes
  local flats = flatten(econ)
  local worth: { number } = table.create(#classes, 0)
  local bulks: { number } = table.create(#classes, 1)
  for g, class in classes do
    bulks[g] = class.bulk or 1
  end
  local rows = scratch
  for id, node in econ.nodes do
    local row = rows[id]
    -- (another economy, with other classes, may have used it last)
    if row == nil or #row ~= #classes then
      row = table.create(#classes, 1)
      rows[id] = row
    end
    ratios(node, row)
    for g = 1, #classes do
      worth[g] = classes[g].par * row[g]
    end
    produce(econ, node, worth, flats, hours)
    consume(econ, node, row, hours)
    anchor(econ, node, row, hours)
    ratios(node, row)
    rows[id] = row
  end
  -- Edges are settled one after another, each seeing the last one's
  -- effect, so that several flows into one node cannot jointly overshoot.
  -- Always in the same order: reversing it on alternate steps was tried
  -- and makes prices jitter with a period of two steps.
  for _, edge in econ.edges do
    flow(econ, edge, rows, bulks, hours)
  end
  econ.hours += hours
  econ.steps += 1
end

-- ---------------------------------------------------------------------
-- Looking at one

-- For each class, how far the stocks are from what the books say they
-- should be: starting stock plus everything that came in, less
-- everything that went out. Anything but rounding error is a leak.
function Economy.Residual(econ: Economy): { number }
  local residual = zeros(#econ.classes)
  for g in econ.classes do
    local held = 0
    for _, node in econ.nodes do
      held += node.stock[g]
    end
    residual[g] = held - (econ.initial[g] + econ.produced[g] + econ.anchorIn[g] + econ.sold[g]
      - econ.consumed[g] - econ.used[g] - econ.anchorOut[g] - econ.bought[g] - econ.lost[g])
  end
  return residual
end

-- The share of everything that entered stocks which came from anchors,
-- by value. Near 0 in a healthy economy; near 1 means the anchors are
-- doing the economy's job for it.
function Economy.AnchorShare(econ: Economy): number
  local fromAnchors, total = 0, 0
  for g, class in econ.classes do
    fromAnchors += econ.anchorIn[g] * class.par
    total += (econ.anchorIn[g] + econ.produced[g]) * class.par
  end
  return if total > 0 then fromAnchors / total else 0
end

return Economy
