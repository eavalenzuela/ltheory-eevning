--!strict
-- Measures a run of the galaxy's economy and judges it.
--
-- Sample once a game hour. At the end, Checks gives a verdict on each
-- thing a working economy has to do, measured over the run after its
-- first 'warm' days (stocks start at their normal levels, which no real
-- economy sits at, so the opening days are a settling-in).
--
-- The thresholds are the definition of "working" that the stocks-and-
-- flows design is held to (docs/roadmap.md §6, stage S2):
--
--   books balance        nothing is created or lost outside the ledger
--   people are supplied  on average, and in the worst-served tenth
--   nothing is starved   few stocks sit at the price ceiling, or the floor
--   prices hold level    the average price stays near normal
--   it feeds itself      little enters through the homeworld anchors
--   industry is used     neither idle nor flat out everywhere
--   it has settled       total stock is not still drifting at the end
--   places differ        prices vary between systems, but not wildly
--   there is trade       some lanes would pay a trader, and few are so
--                        short of haulage that prices stay far apart

local Economy = require("@lt/Core/Strategic/Economy")

local EconProbe = {}

export type Sample = { [string]: number }

export type Probe = {
  samples: { Sample },
  lastIn: number,       -- value through anchors, produced and moved, at the last sample
  lastMade: number,
  lastMoved: number,
  lastHours: number,
}

export type Check = { name: string, value: number, limit: string, ok: boolean }

EconProbe.COLUMNS = { "hours", "met", "metLow", "starved", "glut", "priceIndex", "anchorShare", "utilisation",
  "stockValue", "spread", "movedPerHour", "payingLanes", "bestMargin", "anchorWorst", "strained" }

-- What a jump has to clear, after both ends' spreads, to be worth a
-- trader's while.
EconProbe.TRADER_MARGIN = 0.05
-- How far beyond a lane's cost a price gap may stand before the lane
-- counts as short of haulage, in multiples of the normal price.
EconProbe.STRAIN = 0.1

function EconProbe.New(): Probe
  return { samples = {}, lastIn = 0, lastMade = 0, lastMoved = 0, lastHours = 0 }
end

local function percentile(values: { number }, share: number): number
  local sorted = table.clone(values)
  table.sort(sorted)
  return sorted[math.clamp(math.ceil(#sorted * share), 1, #sorted)]
end

function EconProbe.Sample(probe: Probe, econ: Economy.Economy)
  local classes, nodes = econ.classes, econ.nodes
  local sample: Sample = { hours = econ.hours }

  -- How well people are supplied: the average, by head, and the level
  -- the worst-served tenth of systems are at or below.
  local people, fed = 0, 0
  local mets: { number } = {}
  for _, node in nodes do
    people += node.population
    fed += node.population * node.met
    table.insert(mets, node.met)
  end
  sample.met = fed / people
  sample.metLow = percentile(mets, 0.1)

  -- Prices: how many stocks are at the ceiling or the floor, the average
  -- level, and how much each class's price differs between systems.
  local pairs, starved, glut = 0, 0, 0
  local levelSum, valueSum = 0, 0
  local stockValue = 0
  local spreads: { number } = {}
  local ratios: { { number } } = {}
  for g, class in classes do
    local sum, squares = 0, 0
    local row: { number } = table.create(#nodes, 0)
    for id, node in nodes do
      local ratio = Economy.Price(econ, id, g) / class.par
      row[id] = ratio
      pairs += 1
      if ratio >= 3.999 then
        starved += 1
      elseif ratio <= 0.2501 then
        glut += 1
      end
      sum += ratio
      squares += ratio * ratio
      -- the price level, weighted by what each stock is normally worth
      local weight = node.target[g] * class.par
      levelSum += ratio * weight
      valueSum += weight
      stockValue += node.stock[g] * class.par
    end
    local mean = sum / #nodes
    table.insert(spreads, math.sqrt(math.max(0, squares / #nodes - mean * mean)) / mean)
    ratios[g] = row
  end
  sample.starved = starved / pairs
  sample.glut = glut / pairs
  sample.priceIndex = levelSum / valueSum
  sample.spread = percentile(spreads, 0.5)
  sample.stockValue = stockValue

  -- Since the last sample: what came through anchors against what was
  -- made, and what moved along the lanes. And over the whole run so far,
  -- the class that leans on anchors most.
  local anchored, made, moved = 0, 0, 0
  local worst = 0
  for g, class in classes do
    anchored += econ.anchorIn[g] * class.par
    made += econ.produced[g] * class.par
    moved += econ.moved[g] * class.par
    local through = econ.anchorIn[g] + econ.produced[g]
    if through > 0 then
      worst = math.max(worst, econ.anchorIn[g] / through)
    end
  end
  sample.anchorWorst = worst
  local hours = math.max(1e-9, econ.hours - probe.lastHours)
  local newIn, newMade = anchored - probe.lastIn, made - probe.lastMade
  sample.anchorShare = if newIn + newMade > 0 then newIn / (newIn + newMade) else 0
  sample.movedPerHour = (moved - probe.lastMoved) / hours
  probe.lastIn, probe.lastMade, probe.lastMoved, probe.lastHours = anchored, made, moved, econ.hours

  -- How hard industry is working, by the value of what it could make.
  local could, does = 0, 0
  for _, node in nodes do
    for _, facility in node.facilities do
      local recipe = econ.recipes[facility.recipe]
      local value = 0
      for _, output in recipe.outputs do
        value += output.amount * classes[output.class].par
      end
      could += facility.capacity * value
      does += facility.activity * value
    end
  end
  sample.utilisation = if could > 0 then does / could else 0

  -- Lanes a trader could work: buying something at one end's asking
  -- price and selling it at the other's bid clears TRADER_MARGIN. And
  -- lanes that cannot keep up: a class whose prices at the two ends
  -- stand further apart than the lane's cost by more than STRAIN, which
  -- haulage should have closed.
  local paying, best, strained, laneClasses = 0, 0, 0, 0
  for _, edge in econ.edges do
    local pays = false
    for g, class in classes do
      local low, high = ratios[g][edge.a], ratios[g][edge.b]
      if low > high then
        low, high = high, low
      end
      local margin = high * (1 - Economy.SPREAD) / (low * (1 + Economy.SPREAD)) - 1
      if margin >= EconProbe.TRADER_MARGIN then
        pays = true
      end
      best = math.max(best, margin)
      laneClasses += 1
      if edge.open and high - low > edge.cost * (class.bulk or 1) + EconProbe.STRAIN then
        strained += 1
      end
    end
    if pays then
      paying += 1
    end
  end
  sample.payingLanes = paying / math.max(1, #econ.edges)
  sample.bestMargin = best
  sample.strained = strained / math.max(1, laneClasses)

  table.insert(probe.samples, sample)
end

-- The average of a column over the samples after 'warmHours'.
local function average(probe: Probe, column: string, warmHours: number): number
  local sum, count = 0, 0
  for _, sample in probe.samples do
    if sample.hours > warmHours then
      sum += sample[column]
      count += 1
    end
  end
  return if count > 0 then sum / count else 0
end

-- The verdicts. 'stepMs' is the measured time of one economy step, and
-- 'stepsPerTick' how many of them a simulation tick takes on average
-- (one every six ticks is 1/6).
function EconProbe.Checks(probe: Probe, econ: Economy.Economy, warmDays: number, stepMs: number, stepsPerTick: number): { Check }
  local warm = warmDays * 24
  local checks: { Check } = {}
  local function check(name: string, value: number, low: number?, high: number?)
    local ok = (low == nil or value >= low) and (high == nil or value <= high)
    local limit = if low and high then `{low} to {high}` elseif low then `>= {low}` else `<= {high}`
    table.insert(checks, { name = name, value = value, limit = limit, ok = ok })
  end

  -- The books: the worst class's leak, as a share of what passed
  -- through it.
  local leak = 0
  for g, residual in Economy.Residual(econ) do
    local through = econ.initial[g] + econ.produced[g] + econ.anchorIn[g] + econ.moved[g]
    leak = math.max(leak, math.abs(residual) / math.max(1, through))
  end
  check("books: worst leak (share)", leak, nil, 1e-9)
  check("needs met, by head", average(probe, "met", warm), 0.92, nil)
  check("needs met, worst tenth of systems", average(probe, "metLow", warm), 0.75, nil)
  check("stocks at the price ceiling", average(probe, "starved", warm), nil, 0.02)
  check("stocks at the price floor", average(probe, "glut", warm), nil, 0.05)
  check("price level", average(probe, "priceIndex", warm), 0.85, 1.2)
  check("share through anchors", average(probe, "anchorShare", warm), nil, 0.10)
  local final = probe.samples[#probe.samples]
  check("the class anchors supply most", if final then final.anchorWorst else 1, nil, 0.25)
  check("industry in use", average(probe, "utilisation", warm), 0.5, 0.95)
  -- Settled: total stock over the last third of the run against the
  -- third before it.
  local last = probe.samples[#probe.samples]
  local span = if last then last.hours - warm else 0
  local early, late, earlyCount, lateCount = 0, 0, 0, 0
  for _, sample in probe.samples do
    if sample.hours > warm + span * 2 / 3 then
      late += sample.stockValue
      lateCount += 1
    elseif sample.hours > warm + span / 3 then
      early += sample.stockValue
      earlyCount += 1
    end
  end
  local drift = if earlyCount > 0 and lateCount > 0 then math.abs(late / lateCount / (early / earlyCount) - 1) else 1
  check("stock still drifting (share)", drift, nil, 0.03)
  check("price spread between systems", average(probe, "spread", warm), 0.03, 0.35)
  check("lanes that would pay a trader", average(probe, "payingLanes", warm), 0.10, nil)
  check("best margin on a lane", average(probe, "bestMargin", warm), 0.05, 2.5)
  check("lanes short of haulage", average(probe, "strained", warm), nil, 0.03)
  check("ms a simulation tick", stepMs * stepsPerTick, nil, 1)
  return checks
end

return EconProbe
