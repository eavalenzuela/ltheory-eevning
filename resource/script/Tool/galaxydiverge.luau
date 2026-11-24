--!strict
-- Finds whether a save and load changes the course of the galaxy as a
-- game runs it (Tool/GalaxyStep: the economy, the pirates' pressure and
-- the factions at war, with nobody flying):
--
--   bin/ltcore Tool/galaxydiverge [--galaxy N] [--history N] [--systems N] [--ticks N] [--reload-every N]
--
-- Runs two copies of the same new game side by side. One stays in
-- memory; the other is saved (Core.Save) and loaded back (Core.Load)
-- every N ticks, which rebuilds all of its tables. Their state hashes
-- (Core.Hash) must agree after every reload. If they do not, the tick
-- of the first difference is printed with the first fields that differ.
-- The usual cause is a loop over a map whose result depends on the
-- order the keys come out in. Exits 0 if the copies never differ.
--
-- (This replaced Tool/simdiverge on 2026-11-24, which ran the retired
-- headless faction model, not the game.)
local Core = require("@lt/Core/Api")
local GalaxyStep = require("@lt/Tool/GalaxyStep")

local function show(v: any): string
  if type(v) == "number" then
    return string.format("%.17g", v)
  end
  return tostring(v)
end

-- Every place two values differ, up to 'limit', as "path: a vs b".
local function differences(a: any, b: any, path: string, out: { string }, limit: number)
  if #out >= limit or a == b then
    return
  end
  if type(a) ~= "table" or type(b) ~= "table" then
    if not (a ~= a and b ~= b) then
      table.insert(out, `{path}: in memory {show(a)}, reloaded {show(b)}`)
    end
    return
  end
  for k, v in a do
    local where = if type(k) == "number" then `{path}[{k}]` else `{path}.{tostring(k)}`
    differences(v, b[k], where, out, limit)
  end
  for k, v in b do
    if a[k] == nil then
      local where = if type(k) == "number" then `{path}[{k}]` else `{path}.{tostring(k)}`
      differences(nil, v, where, out, limit)
    end
  end
end

return {
  Main = function(args: { string }): number
    local options: { [string]: number } = { galaxy = 1, history = 1, systems = 400, ticks = 6000, ["reload-every"] = 97 }
    local i = 1
    while i <= #args do
      local name = string.match(args[i], "^%-%-(.+)$")
      local value = tonumber(args[i + 1])
      if name == nil or options[name] == nil or value == nil then
        print(`galaxydiverge: bad argument '{args[i]}'; see the comment at the top of Tool/galaxydiverge.luau`)
        return 2
      end
      options[name] = value
      i += 2
    end
    local every = options["reload-every"]
    local function new(): Core.Game
      return Core.New({ galaxySeed = options.galaxy, historySeed = options.history, systems = options.systems, peaceful = true,
        wars = true })
    end
    local memory, reloaded = new(), new()
    for tick = 1, options.ticks do
      GalaxyStep.Step(memory.state, {}, 1)
      GalaxyStep.Step(reloaded.state, {}, 1)
      if tick % every == 0 or tick == options.ticks then
        local data, length = Core.Save(reloaded)
        reloaded = Core.Load(data, length)
        if Core.Hash(reloaded) ~= Core.Hash(memory) then
          local found: { string } = {}
          differences(memory.state, reloaded.state, "state", found, 12)
          print(`galaxydiverge: the copies differ after tick {tick} (reloaded every {every})`)
          for _, line in found do
            print(`  {line}`)
          end
          return 1
        end
      end
    end
    print(`galaxydiverge: no difference over {options.ticks} ticks (galaxy {options.galaxy}, history {options.history}, {options.systems} systems, reloaded every {every})`)
    return 0
  end,
}
