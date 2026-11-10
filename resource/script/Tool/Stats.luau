--!strict
-- Small statistics for judging a simulation run from its time series.

local Stats = {}

function Stats.Mean(values: { number }): number
  if #values == 0 then
    return 0
  end
  local sum = 0
  for _, v in values do
    sum += v
  end
  return sum / #values
end

-- The p-th percentile (0..100), interpolating between neighbours.
function Stats.Percentile(values: { number }, p: number): number
  if #values == 0 then
    return 0
  end
  local sorted = table.clone(values)
  table.sort(sorted)
  local at = 1 + (#sorted - 1) * p / 100
  local lo = math.floor(at)
  local hi = math.min(#sorted, lo + 1)
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (at - lo)
end

function Stats.Median(values: { number }): number
  return Stats.Percentile(values, 50)
end

-- Least-squares slope of ys against xs.
function Stats.Slope(xs: { number }, ys: { number }): number
  local n = #xs
  if n < 2 then
    return 0
  end
  local mx, my = Stats.Mean(xs), Stats.Mean(ys)
  local num, den = 0, 0
  for i = 1, n do
    num += (xs[i] - mx) * (ys[i] - my)
    den += (xs[i] - mx) * (xs[i] - mx)
  end
  return if den == 0 then 0 else num / den
end

-- How fast a series is drifting over its last two thirds, as a fraction
-- of its own typical size per unit of x. Near 0 means it has settled;
-- -0.2 means it is losing a fifth of its level per unit. 'floor' keeps a
-- series that sits near zero from looking volatile.
function Stats.Trend(xs: { number }, ys: { number }, floor: number?): number
  local from = math.max(1, #xs - (#xs * 2) // 3 + 1)
  local wx, wy, level = {}, {}, 0
  for i = from, #xs do
    table.insert(wx, xs[i])
    table.insert(wy, ys[i])
    level += math.abs(ys[i])
  end
  if #wx < 2 then
    return 0
  end
  level = math.max(level / #wx, floor or 1e-9)
  return Stats.Slope(wx, wy) / level
end

return Stats
