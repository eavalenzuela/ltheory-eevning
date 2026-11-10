--!strict
-- A small test kit for engine-free code. A spec file is a module named
-- Something.spec.luau under Core, Sim or Tool that returns a suite:
--
--   local Test = require("@lt/Tool/Test")
--   local suite = Test.Suite("Rng")
--   suite:Case("the same key gives the same stream", function(t)
--     t.eq(a, b)
--   end)
--   return suite
--
-- Run every spec with `bin/ltcore Tool/specs` (see Tool/specs.luau). A
-- check that fails raises an error, which ends that case; the runner
-- reports it with a traceback and carries on with the next case.

local Test = {}

export type Context = {
  -- Deep equality: tables are compared by content, numbers exactly.
  eq: (actual: any, expected: any, what: string?) -> (),
  -- |actual - expected| <= tolerance
  near: (actual: number, expected: number, tolerance: number, what: string?) -> (),
  ok: (condition: any, what: string?) -> (),
  -- Passes when fn raises an error.
  fails: (fn: () -> (), what: string?) -> (),
}

export type Case = { name: string, run: (t: Context) -> () }

export type Suite = {
  name: string,
  cases: { Case },
  Case: (self: Suite, name: string, run: (t: Context) -> ()) -> (),
}

local function show(v: any): string
  if type(v) == "string" then
    return string.format("%q", v)
  end
  return tostring(v)
end

-- Where two values first differ, as a path like ".fleets[3].ships", or nil
-- if they are equal.
local function difference(a: any, b: any, path: string): string?
  if a == b then
    return nil
  end
  if type(a) ~= "table" or type(b) ~= "table" then
    -- NaN is the one value not equal to itself; two NaNs count as equal.
    if a ~= a and b ~= b then
      return nil
    end
    return `{if path == "" then "value" else path}: got {show(a)}, expected {show(b)}`
  end
  for k, v in a do
    local where = if type(k) == "number" then `{path}[{k}]` else `{path}.{tostring(k)}`
    if b[k] == nil then
      return `{where}: got {show(v)}, expected nothing`
    end
    local d = difference(v, b[k], where)
    if d then
      return d
    end
  end
  for k, v in b do
    if a[k] == nil then
      local where = if type(k) == "number" then `{path}[{k}]` else `{path}.{tostring(k)}`
      return `{where}: got nothing, expected {show(v)}`
    end
  end
  return nil
end

Test.Difference = difference

local context: Context = {
  eq = function(actual: any, expected: any, what: string?)
    local d = difference(actual, expected, "")
    if d then
      error((if what then what .. ": " else "") .. d, 2)
    end
  end,
  near = function(actual: number, expected: number, tolerance: number, what: string?)
    if not (math.abs(actual - expected) <= tolerance) then
      error(`{if what then what .. ": " else ""}got {actual}, expected {expected} within {tolerance}`, 2)
    end
  end,
  ok = function(condition: any, what: string?)
    if not condition then
      error(what or "condition is false", 2)
    end
  end,
  fails = function(fn: () -> (), what: string?)
    local ok = pcall(fn)
    if ok then
      error((if what then what .. ": " else "") .. "expected an error, but none was raised", 2)
    end
  end,
}

function Test.Suite(name: string): Suite
  local suite = { name = name, cases = {} } :: any
  function suite.Case(self: Suite, caseName: string, run: (t: Context) -> ())
    table.insert(self.cases, { name = caseName, run = run })
  end
  return suite
end

export type Result = { passed: number, failed: number }

-- Run one suite, printing a line per failure. 'filter', if given, keeps
-- only the cases whose "suite: case" name contains it.
function Test.Run(suite: Suite, filter: string?): Result
  local result = { passed = 0, failed = 0 }
  for _, case in suite.cases do
    local full = `{suite.name}: {case.name}`
    if filter == nil or string.find(full, filter, 1, true) then
      local ok, message = xpcall(function()
        case.run(context)
      end, function(e: any): string
        return debug.traceback(tostring(e), 2)
      end)
      if ok then
        result.passed += 1
      else
        result.failed += 1
        print(`FAIL {full}`)
        for line in string.gmatch(tostring(message), "[^\n]+") do
          print("     " .. line)
        end
      end
    end
  end
  return result
end

return Test
