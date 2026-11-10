--!strict
-- The economy kernel on toy graphs. Each case is a property the
-- prototype's hauler economy did not have, or a way a flow economy is
-- known to go wrong.

local Codec = require("@lt/Core/Persist/Codec")
local Economy = require("@lt/Core/Strategic/Economy")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Economy")

local DT = 1 / 60 -- one game minute

-- One class with no consumers: goods that only move.
local function transitOnly(): Economy.Economy
  return Economy.New({ { id = "goods", par = 10, cover = 24, need = 0 } }, {})
end

local function run(econ: Economy.Economy, hours: number, dt: number?)
  local step = dt or DT
  for _ = 1, math.floor(hours / step + 0.5) do
    Economy.Step(econ, step)
  end
end

local function leak(t: Test.Context, econ: Economy.Economy)
  for g, residual in Economy.Residual(econ) do
    local scale = math.max(1, econ.initial[g] + econ.produced[g] + econ.sold[g] + econ.anchorIn[g])
    t.ok(math.abs(residual) < 1e-7 * scale, `{econ.classes[g].id} leaked {residual}`)
  end
end

suite:Case("two nodes share out their stock until the price gap is the cost of trade", function(t)
  local econ = transitOnly()
  local a = Economy.AddNode(econ, "A", 0)
  local b = Economy.AddNode(econ, "B", 0)
  -- With nothing made or used here each node aims to hold 200.
  Economy.SetStock(econ, a, 1, 400) -- cheap: half par
  Economy.SetStock(econ, b, 1, 100) -- dear: twice par
  Economy.AddEdge(econ, a, b, 400, 0.05)
  local lastGap = math.huge
  for _ = 1, 60 * 600 do
    Economy.Step(econ, DT)
    local gap = (Economy.Price(econ, b, 1) - Economy.Price(econ, a, 1)) / 10
    t.ok(gap >= 0.05 - 1e-9, `the flow overshot: the gap fell to {gap}`)
    t.ok(gap <= lastGap + 1e-12, "the gap widened")
    lastGap = gap
  end
  t.near(lastGap, 0.05, 1e-3, "it settles at the cost of trade")
  t.near(econ.nodes[a].stock[1] + econ.nodes[b].stock[1], 500, 1e-9, "nothing was made or lost on the way")
  leak(t, econ)
end)

suite:Case("a closed edge carries nothing", function(t)
  local econ = transitOnly()
  local a = Economy.AddNode(econ, "A", 0)
  local b = Economy.AddNode(econ, "B", 0)
  Economy.SetStock(econ, a, 1, 400)
  Economy.SetStock(econ, b, 1, 100)
  local edge = Economy.AddEdge(econ, a, b, 400, 0.05)
  econ.edges[edge].open = false
  run(econ, 50)
  t.eq({ econ.nodes[a].stock[1], econ.nodes[b].stock[1] }, { 400, 100 })
end)

-- A mine at one end of a chain, a city at the other, 'links' edges between.
local function chain(links: number, conductance: number, cost: number): (Economy.Economy, number, number)
  local econ = Economy.New(
    { { id = "food", par = 20, cover = 24, need = 1 } },
    { { id = "farm", inputs = {}, outputs = { { class = 1, amount = 1 } }, margin = 0.25 } })
  local farm = Economy.AddNode(econ, "Farm", 0, { { recipe = 1, capacity = 12 } })
  local last = farm
  for i = 1, links - 1 do
    local node = Economy.AddNode(econ, `Waypoint {i}`, 0)
    Economy.AddEdge(econ, last, node, conductance, cost)
    last = node
  end
  local city = Economy.AddNode(econ, "City", 6)
  Economy.AddEdge(econ, last, city, conductance, cost)
  return econ, farm, city
end

suite:Case("along a chain each edge's price gap is its cost plus flow over conductance", function(t)
  local conductance, cost = 600, 0.04
  local econ, _, city = chain(4, conductance, cost)
  run(econ, 2000)
  -- The steady flow: what the city eats per hour, measured over 100 hours.
  local before = econ.consumed[1]
  run(econ, 100)
  local flow = (econ.consumed[1] - before) / 100
  t.ok(flow > 3 and flow < 7, `the city eats {flow} an hour; it wants 6 at par`)
  for i, edge in econ.edges do
    local gap = (Economy.Price(econ, edge.b, 1) - Economy.Price(econ, edge.a, 1)) / 20
    local expected = cost + flow * 20 / conductance
    t.ok(math.abs(gap - expected) < 0.05 * expected, `edge {i}: gap {gap}, expected {expected}`)
  end
  t.ok(Economy.Price(econ, city, 1) > 20, "so food is dearer in the city than at par")
  t.ok(econ.nodes[city].met > 0.6, `the city gets {econ.nodes[city].met} of what it needs`)
  leak(t, econ)
end)

-- Add a glut at one node of a settled graph and watch every price: none
-- may zigzag.
local function impulse(t: Test.Context, econ: Economy.Economy, at: number, what: string)
  run(econ, 300)
  Economy.SetStock(econ, at, 1, econ.nodes[at].stock[1] + 600)
  local last: { number } = {}
  local direction: { number } = {}
  local turns: { number } = {}
  for n in econ.nodes do
    last[n], direction[n], turns[n] = Economy.Price(econ, n, 1), 0, 0
  end
  for _ = 1, 60 * 400 do
    Economy.Step(econ, DT)
    for n in econ.nodes do
      local p = Economy.Price(econ, n, 1)
      local d = p - last[n]
      if math.abs(d) > 1e-9 then
        local sign = if d > 0 then 1 else -1
        if direction[n] ~= 0 and sign ~= direction[n] then
          turns[n] += 1
        end
        direction[n] = sign
      end
      last[n] = p
    end
  end
  for n, count in turns do
    -- A node may see the glut arrive and then drain: one turn. More is a
    -- price bouncing.
    t.ok(count <= 1, `{what}: the price at node {n} changed direction {count} times`)
  end
  leak(t, econ)
end

suite:Case("a glut spreads round a ring without any price bouncing", function(t)
  local econ = transitOnly()
  for i = 1, 6 do
    Economy.AddNode(econ, `N{i}`, 0)
  end
  for i = 1, 6 do
    Economy.AddEdge(econ, i, i % 6 + 1, 300, 0.03)
  end
  impulse(t, econ, 1, "ring")
end)

suite:Case("a glut spreads out from the hub of a star without any price bouncing", function(t)
  local econ = transitOnly()
  local hub = Economy.AddNode(econ, "Hub", 0)
  for i = 1, 5 do
    Economy.AddEdge(econ, hub, Economy.AddNode(econ, `Leaf {i}`, 0), 300, 0.03)
  end
  impulse(t, econ, hub, "star")
end)

-- Mine -> factory -> city: ore becomes goods, which the city consumes.
local function industry(): (Economy.Economy, { mine: number, factory: number, city: number, toCity: number })
  local econ = Economy.New(
    { { id = "ore", par = 8, cover = 24, need = 0 }, { id = "goods", par = 30, cover = 24, need = 1 } },
    {
      { id = "mine", inputs = {}, outputs = { { class = 1, amount = 1 } }, margin = 0.25 },
      { id = "factory", inputs = { { class = 1, amount = 2 } }, outputs = { { class = 2, amount = 1 } }, margin = 0.25 },
    })
  local mine = Economy.AddNode(econ, "Mine", 0, { { recipe = 1, capacity = 20 } })
  local factory = Economy.AddNode(econ, "Factory", 0, { { recipe = 2, capacity = 8 } })
  local city = Economy.AddNode(econ, "City", 5)
  Economy.AddEdge(econ, mine, factory, 1500, 0.03)
  local toCity = Economy.AddEdge(econ, factory, city, 1500, 0.03)
  return econ, { mine = mine, factory = factory, city = city, toCity = toCity }
end

local function prices(econ: Economy.Economy): { number }
  local list = {}
  for n in econ.nodes do
    for g in econ.classes do
      table.insert(list, Economy.Price(econ, n, g))
    end
  end
  return list
end

local function close(t: Test.Context, a: { number }, b: { number }, tolerance: number, what: string)
  for i, value in a do
    t.ok(math.abs(value - b[i]) <= tolerance * math.max(value, b[i]), `{what}: price {i} is {value} against {b[i]}`)
  end
end

suite:Case("a supply chain settles, with no help from anchors", function(t)
  local econ, at = industry()
  run(econ, 1500)
  local settled = prices(econ)
  local made, eaten, mined, used = econ.produced[2], econ.consumed[2], econ.produced[1], econ.used[1]
  run(econ, 200)
  close(t, prices(econ), settled, 0.01, "after 200 more hours")
  made, eaten = econ.produced[2] - made, econ.consumed[2] - eaten
  mined, used = econ.produced[1] - mined, econ.used[1] - used
  t.ok(math.abs(made - eaten) < 0.02 * eaten, `{made} goods made against {eaten} eaten`)
  t.ok(math.abs(mined - used) < 0.02 * used, `{mined} ore mined against {used} used`)
  t.ok(eaten / 200 > 3, `the city eats {eaten / 200} an hour of the 5 it wants`)
  t.ok(econ.nodes[at.city].met > 0.7)
  t.eq(Economy.AnchorShare(econ), 0)
  leak(t, econ)
end)

suite:Case("a blockade starves the city, and lifting it brings back the same economy", function(t)
  local econ, at = industry()
  run(econ, 1500)
  local settled = prices(econ)
  local cityPrice = Economy.Price(econ, at.city, 2)

  econ.edges[at.toCity].open = false
  run(econ, 300)
  t.ok(Economy.Price(econ, at.city, 2) > 1.5 * cityPrice, "goods grow dear in the cut-off city")
  t.ok(econ.nodes[at.city].met < 0.5, `the city still gets {econ.nodes[at.city].met} of its needs`)
  t.ok(econ.nodes[at.factory].facilities[1].activity < 2, "the factory, with nowhere to sell, winds down")

  econ.edges[at.toCity].open = true
  run(econ, 1500)
  -- Nothing about the slump is remembered. Every market that makes, uses
  -- or eats something is back where it was: ore at the mine and the
  -- factory, goods at the factory and the city.
  local after = prices(econ)
  for _, index in { 1, 3, 4, 6 } do
    t.ok(math.abs(after[index] - settled[index]) <= 0.02 * settled[index],
      `price {index} is {after[index]}, was {settled[index]}`)
  end
  -- The city's ore, which nobody there wants, is the exception: some
  -- drifted in while it was cheap and stays, because carrying it back is
  -- not worth the cost of the trip. It sits within that cost of where it was.
  t.ok(math.abs(after[5] - settled[5]) <= 0.08 * settled[5], `idle ore in the city is {after[5]}, was {settled[5]}`)
  t.ok(econ.nodes[at.city].met > 0.7, "the city is fed again")
  t.ok(econ.nodes[at.factory].facilities[1].activity > 3, "the factory is running again")
  leak(t, econ)
end)

suite:Case("the step size does not change the outcome", function(t)
  local outcomes: { { number } } = {}
  local eaten: { number } = {}
  for i, dt in { 1 / 120, 1 / 60, 1 / 30 } do
    local econ = industry()
    run(econ, 800, dt)
    outcomes[i] = prices(econ)
    eaten[i] = econ.consumed[2]
  end
  close(t, outcomes[1], outcomes[2], 0.03, "30 s against 60 s steps")
  close(t, outcomes[3], outcomes[2], 0.03, "120 s against 60 s steps")
  t.ok(math.abs(eaten[1] - eaten[2]) < 0.03 * eaten[2] and math.abs(eaten[3] - eaten[2]) < 0.03 * eaten[2],
    `goods eaten: {eaten[1]}, {eaten[2]}, {eaten[3]}`)
end)

suite:Case("an anchor holds a lone city near par, and its share is measured", function(t)
  local econ = Economy.New({ { id = "food", par = 20, cover = 24, need = 1 } }, {})
  local city = Economy.AddNode(econ, "City", 4)
  econ.nodes[city].anchor[1] = 40
  run(econ, 500)
  local p = Economy.Price(econ, city, 1)
  t.ok(p > 20 and p < 24, `the price is {p}`)
  t.ok(econ.nodes[city].met > 0.9)
  t.eq(Economy.AnchorShare(econ), 1, "everything here came through the anchor")
  leak(t, econ)
end)

suite:Case("a trade walks the price curve, and buying then selling never pays", function(t)
  local econ = transitOnly()
  local a = Economy.AddNode(econ, "A", 0)
  Economy.SetStock(econ, a, 1, 400)
  t.eq(Economy.BuyCost(econ, a, 1, 401), nil, "more than the node holds cannot be bought")

  -- 300 units in one go costs what 3 lots of 100 cost.
  local whole = Economy.BuyCost(econ, a, 1, 300) :: number
  local parts = 0
  for _ = 1, 3 do
    parts += Economy.Buy(econ, a, 1, 100) :: number
  end
  t.near(parts, whole, 1e-9 * whole)
  -- par 10, target 200: from 400 down to 100 the price is 2000/S, so the
  -- value is 2000 * ln(400/100), plus the spread.
  t.near(whole, 2000 * math.log(4) * (1 + Economy.SPREAD), 1e-6)

  -- Selling them straight back returns less than was paid, by the spread
  -- on both legs.
  local back = Economy.Sell(econ, a, 1, 300)
  t.near(back, 2000 * math.log(4) * (1 - Economy.SPREAD), 1e-6)
  t.ok(back < whole)
  t.near(econ.nodes[a].stock[1], 400, 1e-9)
  leak(t, econ)
end)

suite:Case("the price curve is capped at four times par and floored at a quarter", function(t)
  local econ = transitOnly()
  local a = Economy.AddNode(econ, "A", 0) -- target 200
  Economy.SetStock(econ, a, 1, 20)
  t.eq(Economy.Price(econ, a, 1), 40)
  Economy.SetStock(econ, a, 1, 0)
  t.eq(Economy.Price(econ, a, 1), 40)
  Economy.SetStock(econ, a, 1, 5000)
  t.eq(Economy.Price(econ, a, 1), 2.5)
  -- Selling into a glut fetches the floor price for every unit.
  t.near(Economy.SellRevenue(econ, a, 1, 100), 2.5 * 100 * (1 - Economy.SPREAD), 1e-9)
end)

suite:Case("the economy is plain data and carries on unchanged after a save", function(t)
  local straight = industry()
  run(straight, 400)

  local resumed = industry()
  run(resumed, 150)
  local data, length = Codec.Encode(resumed)
  resumed = Codec.Decode(data, length)
  run(resumed, 250)
  t.eq(Codec.HashOf(resumed), Codec.HashOf(straight))
end)

-- A trader with one hold: it goes wherever the best profit per hour is,
-- buying and selling against the nodes like anyone else.
suite:Case("a lone trader makes a steady, modest living from the gaps the flows leave", function(t)
  local econ = Economy.New(
    { { id = "food", par = 20, cover = 24, need = 1 } },
    { { id = "farm", inputs = {}, outputs = { { class = 1, amount = 1 } }, margin = 0.25 } })
  -- A farm at the hub; cities one, two and three jumps out along thin lanes.
  local farm = Economy.AddNode(econ, "Farm", 0, { { recipe = 1, capacity = 30 } })
  local hops: { number } = { 0 }
  for arm = 1, 3 do
    local last = farm
    for step = 1, arm do
      local node = Economy.AddNode(econ, `Arm {arm} step {step}`, if step == arm then 5 else 0)
      Economy.AddEdge(econ, last, node, 250, 0.04)
      hops[node] = step
      last = node
    end
  end
  run(econ, 500)

  local HOLD = 12
  local HOURS_PER_HOP = 0.5
  local wallet = 0
  local traded = 0
  local days: { number } = {}
  for day = 1, 30 do
    local start = wallet
    local hoursLeft = 24
    while hoursLeft > 0 do
      -- Every run starts at the farm: buy there, sell at the best city.
      local best, bestRate = 0, 0
      local cost = Economy.BuyCost(econ, farm, 1, HOLD)
      if cost then
        for node, distance in hops do
          if distance > 0 and econ.nodes[node].population > 0 then
            local rate = (Economy.SellRevenue(econ, node, 1, HOLD) - cost) / (2 * distance * HOURS_PER_HOP)
            if rate > bestRate then
              best, bestRate = node, rate
            end
          end
        end
      end
      if best == 0 then
        -- Nothing worth carrying: wait an hour.
        run(econ, 1)
        hoursLeft -= 1
      else
        local trip = hops[best] * HOURS_PER_HOP
        wallet -= Economy.Buy(econ, farm, 1, HOLD) :: number
        run(econ, trip)
        local revenue = Economy.Sell(econ, best, 1, HOLD)
        wallet += revenue
        traded += revenue
        run(econ, trip)
        hoursLeft -= 2 * trip
      end
    end
    days[day] = wallet - start
  end

  local good = 0
  for _, profit in days do
    if profit > 0 then
      good += 1
    end
  end
  t.ok(good >= 27, `the trader made money on only {good} of 30 days`)
  -- A living, not a fortune: its margin on what it carried is a fraction
  -- of the goods' worth, and nowhere near the 4x the price cap allows.
  local margin = wallet / traded
  print(string.format("     trader: profit on %d of 30 days, %.0f credits on %.0f turnover (%.0f%%); far city fed %.0f%%",
    good, wallet, traded, 100 * margin, 100 * econ.nodes[#econ.nodes].met))
  t.ok(margin > 0.02 and margin < 0.5, `it kept {margin} of its turnover`)
  t.ok(econ.nodes[#econ.nodes].met > 0.5, `the far city gets {econ.nodes[#econ.nodes].met} of its needs`)
  leak(t, econ)
end)

suite:Case("what pirates take on a lane, or from a stock, is lost to both ends and kept in the books", function(t)
  local econ = transitOnly()
  local a = Economy.AddNode(econ, "A", 0)
  local b = Economy.AddNode(econ, "B", 0)
  Economy.SetStock(econ, a, 1, 400)
  Economy.SetStock(econ, b, 1, 100)
  local edge = Economy.AddEdge(econ, a, b, 400, 0.05)
  t.eq(econ.edges[edge].loss, 0, "a lane loses nothing unless told to")
  econ.edges[edge].loss = 0.1
  run(econ, 50)
  local held = econ.nodes[a].stock[1] + econ.nodes[b].stock[1]
  t.ok(econ.moved[1] > 50)
  t.near(econ.lost[1], 0.1 * econ.moved[1], 1e-9, "a tenth of what was carried")
  t.near(held, 500 - econ.lost[1], 1e-9)
  -- the gap still closes to the cost of trade, and never past it
  local gap = (Economy.Price(econ, b, 1) - Economy.Price(econ, a, 1)) / 10
  t.ok(gap >= 0.05 - 1e-9 and gap < 0.06, `the gap is {gap}`)
  -- a raid: taken by force, nobody paid, no more than is there
  local before = econ.lost[1]
  t.near(Economy.Take(econ, a, 1, 30), 30, 1e-12)
  t.near(Economy.Take(econ, a, 1, 1e9), econ.lost[1] - before - 30, 1e-9)
  t.eq(econ.nodes[a].stock[1], 0)
  leak(t, econ)
end)

return suite
