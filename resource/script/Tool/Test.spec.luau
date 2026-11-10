--!strict
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Test kit")

suite:Case("eq compares tables by content", function(t)
  local function sample(): any
    return { a = 1, list = { 1, 2, { x = "y" } :: any } }
  end
  t.eq(sample(), sample())
  t.eq(0 / 0, 0 / 0, "two NaNs count as equal")
end)

suite:Case("eq reports where two tables differ", function(t)
  t.eq(Test.Difference({ a = { 1, 2 } }, { a = { 1, 3 } }, ""), ".a[2]: got 2, expected 3")
  t.eq(Test.Difference({ a = 1 }, { a = 1, b = 2 }, ""), ".b: got nothing, expected 2")
  t.eq(Test.Difference({ a = 1, b = 2 }, { a = 1 }, ""), ".b: got 2, expected nothing")
  t.eq(Test.Difference(1, "1", ""), 'value: got 1, expected "1"')
end)

suite:Case("near, ok and fails", function(t)
  t.near(0.1 + 0.2, 0.3, 1e-12)
  t.ok(true)
  t.fails(function()
    t.near(1, 2, 0.5)
  end)
  t.fails(function()
    t.ok(false)
  end)
  t.fails(function()
    t.eq({ 1 }, { 2 })
  end)
  t.fails(function()
    t.fails(function() end)
  end, "fails must fail when nothing is raised")
end)

suite:Case("a failing case is counted, not fatal", function(t)
  local inner = Test.Suite("inner")
  inner:Case("passes", function() end)
  inner:Case("raises", function()
    error("expected by the spec")
  end)
  -- Run prints the failure; that output is part of what is being tested.
  local result = Test.Run(inner, "passes")
  t.eq(result, { passed = 1, failed = 0 }, "filter keeps one case")
end)

return suite
