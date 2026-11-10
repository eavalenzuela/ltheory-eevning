--!strict
local Stats = require("@lt/Tool/Stats")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Stats")

suite:Case("mean, median and percentiles", function(t)
  t.eq(Stats.Mean({ 1, 2, 3, 6 }), 3)
  t.eq(Stats.Median({ 5, 1, 3 }), 3)
  t.eq(Stats.Median({ 1, 2, 3, 4 }), 2.5)
  t.eq(Stats.Percentile({ 10, 20, 30, 40, 50 }, 0), 10)
  t.eq(Stats.Percentile({ 10, 20, 30, 40, 50 }, 100), 50)
  t.eq(Stats.Percentile({ 10, 20, 30, 40, 50 }, 10), 14)
  t.eq(Stats.Mean({}), 0)
end)

suite:Case("slope of a line is its gradient", function(t)
  t.near(Stats.Slope({ 0, 1, 2, 3 }, { 1, 3, 5, 7 }), 2, 1e-12)
  t.eq(Stats.Slope({ 1, 1, 1 }, { 1, 2, 3 }), 0, "no spread in x")
end)

suite:Case("trend is relative drift over the last two thirds", function(t)
  local xs, flat, falling, settled = {}, {}, {}, {}
  for i = 0, 29 do
    xs[i + 1] = i
    flat[i + 1] = 100
    falling[i + 1] = 1000 - 30 * i
    -- drops for the first third, then holds
    settled[i + 1] = if i < 10 then 1000 - 90 * i else 100
  end
  t.eq(Stats.Trend(xs, flat), 0)
  t.ok(Stats.Trend(xs, falling) < -0.05, "a steady fall is a trend")
  t.eq(Stats.Trend(xs, settled), 0, "an early transient is ignored")
  t.near(Stats.Trend({ 0, 1, 2 }, { 0, 0.001, 0.002 }, 100), 0, 1e-4)
end)

return suite
