--!strict
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
--             once the gap exceeds the edge's cost: conductance * excess
--             gap per hour in value, never more than half of what would
--             close the gap (so prices approach each other and cannot
--             overshoot)
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
  met: number,          -- share of its population's needs met last step
}

export type Edge = {
  a: number,
  b: number,
  conductance: number,  -- credits per hour of goods moved per unit of
                        -- relative price gap beyond the cost
  cost: number,         -- the gap, as a fraction of par, that trade must beat
  open: boolean,
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
}

local PRICE_MIN, PRICE_MAX = 0.25, 4
local CONSUMPTION_ELASTICITY = 0.5
-- A facility needs this many hours of inputs in stock to run flat out.
local INPUT_HOURS = 2
-- The share of the gap-closing quantity a flow may move in one step.
local ALPHA = 0.5
-- No node aims to hold less than this many credits' worth of a class.
local TARGET_FLOOR_VALUE = 200
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
  }
end

-- The stock a node aims to hold of each class: 'cover' hours of the most
-- it consumes, makes or uses in an hour.
local function targets(econ: Economy, node: Node): { number }
  local rate = zeros(#econ.classes)
  for g, class in econ.classes do
    rate[g] = node.population * class.need
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

-- Add a node; its stocks start on target. Returns its id.
function Economy.AddNode(econ: Economy, name: string, population: number,
  facilities: { { recipe: number, capacity: number } }?): number
  local node: Node = {
    id = #econ.nodes + 1, name = name, population = population, facilities = {},
    stock = {}, target = {}, anchor = zeros(#econ.classes), met = 1,
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
  table.insert(econ.edges, { a = a, b = b, conductance = conductance, cost = cost, open = true })
  return #econ.edges
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

local function price(econ: Economy, n: Node, g: number): number
  local stock = n.stock[g]
  local ratio = if stock <= 0 then PRICE_MAX else math.clamp(n.target[g] / stock, PRICE_MIN, PRICE_MAX)
  return econ.classes[g].par * ratio
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

-- Put goods into a node's stock; returns what they fetched.
function Economy.Sell(econ: Economy, node: number, class: number, quantity: number): number
  local revenue = Economy.SellRevenue(econ, node, class, quantity)
  econ.nodes[node].stock[class] += quantity
  econ.sold[class] += quantity
  return revenue
end

-- ---------------------------------------------------------------------
-- The step

local function ramp(x: number): number
  return math.clamp(x, 0, 1)
end

local function produce(econ: Economy, node: Node, dt: number)
  for _, facility in node.facilities do
    local recipe = econ.recipes[facility.recipe]
    -- How well stocked the inputs are, and what a run costs and earns at
    -- this node's prices. Labour is whatever makes the margin come out at
    -- the recipe's own when every price is at par.
    local supplied = 1
    local inputValue, inputPar, outputValue, outputPar = 0, 0, 0, 0
    for _, input in recipe.inputs do
      local class = econ.classes[input.class]
      supplied = math.min(supplied, ramp(node.stock[input.class] / (facility.capacity * input.amount * INPUT_HOURS)))
      inputValue += input.amount * price(econ, node, input.class)
      inputPar += input.amount * class.par
    end
    for _, output in recipe.outputs do
      outputValue += output.amount * price(econ, node, output.class)
      outputPar += output.amount * econ.classes[output.class].par
    end
    local labour = outputPar / (1 + recipe.margin) - inputPar
    local profit = outputValue / (inputValue + labour) - 1
    local activity = facility.capacity * supplied * ramp(profit / recipe.margin)
    -- Never use more of an input than is there.
    for _, input in recipe.inputs do
      activity = math.min(activity, node.stock[input.class] / (input.amount * dt))
    end
    facility.activity = activity
    for _, input in recipe.inputs do
      local amount = activity * input.amount * dt
      node.stock[input.class] -= amount
      econ.used[input.class] += amount
    end
    for _, output in recipe.outputs do
      local amount = activity * output.amount * dt
      node.stock[output.class] += amount
      econ.produced[output.class] += amount
    end
  end
end

local function consume(econ: Economy, node: Node, dt: number)
  if node.population <= 0 then
    node.met = 1
    return
  end
  local wanted, got = 0, 0
  for g, class in econ.classes do
    if class.need > 0 then
      local base = node.population * class.need * dt
      local want = base * (price(econ, node, g) / class.par) ^ -CONSUMPTION_ELASTICITY
      local amount = math.min(want, node.stock[g])
      node.stock[g] -= amount
      econ.consumed[g] += amount
      wanted += base * class.par
      got += math.min(amount, base) * class.par
    end
  end
  node.met = if wanted > 0 then got / wanted else 1
end

local function anchor(econ: Economy, node: Node, dt: number)
  for g, rate in node.anchor do
    if rate > 0 then
      local class = econ.classes[g]
      local gap = price(econ, node, g) / class.par - 1
      -- Dear here: the anchor sells in. Cheap here: it buys out. Never
      -- past the point where the price would cross par.
      local amount = rate * gap * dt
      local limit = node.target[g] - node.stock[g]
      if amount > 0 then
        amount = math.min(amount, math.max(0, limit) * ALPHA)
        node.stock[g] += amount
        econ.anchorIn[g] += amount
      else
        amount = math.min(-amount, math.max(0, -limit) * ALPHA)
        node.stock[g] -= amount
        econ.anchorOut[g] += amount
      end
    end
  end
end

local function flow(econ: Economy, edge: Edge, dt: number)
  if not edge.open then
    return
  end
  local a, b = econ.nodes[edge.a], econ.nodes[edge.b]
  for g, class in econ.classes do
    local pa, pb = price(econ, a, g), price(econ, b, g)
    local from, to, low, high = a, b, pa, pb
    if pa > pb then
      from, to, low, high = b, a, pb, pa
    end
    local gap = (high - low) / class.par - edge.cost
    if gap > 0 and from.stock[g] > 0 then
      -- How much would close the gap to the edge's cost, from how fast
      -- each end's price moves with its stock (dp/dS = -p/S).
      local closing = gap * class.par / (low / from.stock[g] + high / math.max(to.stock[g], 1e-9))
      local amount = math.min(edge.conductance * gap * dt / class.par, ALPHA * closing, from.stock[g])
      from.stock[g] -= amount
      to.stock[g] += amount
      econ.moved[g] += amount
    end
  end
end

-- Advance the economy by 'hours' of game time.
function Economy.Step(econ: Economy, hours: number)
  for _, node in econ.nodes do
    produce(econ, node, hours)
    consume(econ, node, hours)
    anchor(econ, node, hours)
  end
  -- Edges are settled one after another, each seeing the last one's
  -- effect, in an order that reverses every step so that neither end of
  -- the list is favoured.
  local count = #econ.edges
  if econ.steps % 2 == 0 then
    for i = 1, count do
      flow(econ, econ.edges[i], hours)
    end
  else
    for i = count, 1, -1 do
      flow(econ, econ.edges[i], hours)
    end
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
      - econ.consumed[g] - econ.used[g] - econ.anchorOut[g] - econ.bought[g])
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
