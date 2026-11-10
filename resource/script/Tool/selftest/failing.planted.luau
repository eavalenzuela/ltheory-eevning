--!strict
-- Planted failure for script/check: the spec runner must exit non-zero on
-- this suite. It is not named *.spec.luau, so a normal run skips it.
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("planted")

suite:Case("this assertion fails on purpose", function(t)
  t.eq(1 + 1, 3)
end)

return suite
