--!strict
-- Runs the engine-free test suites:
--
--   bin/ltcore Tool/specs [FILTER] [--file MODULE] [--list]
--
-- With no arguments it finds every *.spec.luau under resource/script/Core
-- and Tool and runs all of their cases. FILTER keeps the cases whose
-- "suite: case" name contains it. --file runs one module by name instead
-- of searching (it need not end in .spec). --list prints the case names
-- without running them. The exit status is 1 if any case failed or no
-- case ran, so a typo in a filter cannot pass silently.

local Test = require("@lt/Tool/Test")

local ROOT = "resource/script/"
local SEARCH = { "Core", "Tool" }

local function find(dir: string, out: { string })
  for _, name in Host.ListDir(ROOT .. dir) do
    if string.sub(name, -1) == "/" then
      find(dir .. "/" .. string.sub(name, 1, -2), out)
    elseif string.sub(name, -10) == ".spec.luau" then
      table.insert(out, dir .. "/" .. string.sub(name, 1, -6))
    end
  end
end

return {
  Main = function(args: { string }): number
    local filter: string? = nil
    local modules: { string } = {}
    local list = false
    local i = 1
    while i <= #args do
      local arg = args[i]
      if arg == "--file" then
        i += 1
        table.insert(modules, args[i])
      elseif arg == "--list" then
        list = true
      else
        filter = arg
      end
      i += 1
    end
    if #modules == 0 then
      for _, dir in SEARCH do
        find(dir, modules)
      end
    end

    local started = Host.Clock()
    local passed, failed = 0, 0
    for _, module in modules do
      local suite = (require :: any)("@lt/" .. module) :: Test.Suite
      if type(suite) ~= "table" or type(suite.cases) ~= "table" then
        print(`FAIL {module}: the module does not return a Test.Suite`)
        failed += 1
      elseif list then
        for _, case in suite.cases do
          print(`{suite.name}: {case.name}`)
          passed += 1
        end
      else
        local result = Test.Run(suite, filter)
        passed += result.passed
        failed += result.failed
      end
    end

    if list then
      return 0
    end
    print(`specs: {passed} passed, {failed} failed, {#modules} file(s), `
      .. `{string.format("%.2f", Host.Clock() - started)} s`)
    if passed + failed == 0 then
      print("specs: no case ran")
      return 1
    end
    return if failed > 0 then 1 else 0
  end,
}
