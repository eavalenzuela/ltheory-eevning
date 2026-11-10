--!strict
-- Finds where a save and load changes the course of the strategic
-- simulation (Core/Strategic/Sim):
--
--   bin/ltcore Tool/simdiverge [--galaxy N] [--history N] [--systems N]
--                              [--ticks N] [--reload-every N]
--
-- Runs two copies of the same history side by side. One stays in memory;
-- the other is saved to bytes and loaded back every N ticks, which
-- rebuilds all of its tables. They must stay identical. If they do not,
-- the run is repeated up to the last point where they still agreed and
-- then compared after every tick, and the first fields that differ are
-- printed. The usual cause is a loop over a map whose result depends on
-- the order the keys come out in. Exits 0 if the copies never differ.

local Codec = require("@lt/Core/Persist/Codec")
local Sim = require("@lt/Core/Strategic/Sim")
local World = require("@lt/Core/Strategic/World")

local function reload(state: World.World): (World.World, string)
  local data, length = Codec.Encode(state)
  return Codec.Decode(data, length), Codec.Hash(data, length)
end

local function show(v: any): string
  if type(v) == "string" then
    return string.format("%q", v)
  elseif type(v) == "table" then
    return "a table"
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
    local options: { [string]: number } = {
      galaxy = 1, history = 1, systems = 400, ticks = 6000, ["reload-every"] = 97,
    }
    local i = 1
    while i <= #args do
      local name = string.match(args[i], "^%-%-(.+)$")
      local value = tonumber(args[i + 1])
      if name == nil or options[name] == nil or value == nil then
        print(`simdiverge: bad argument '{args[i]}'; see the comment at the top of Tool/simdiverge.luau`)
        return 2
      end
      options[name] = value
      i += 2
    end
    local every = options["reload-every"]

    -- Pass 1: find the interval in which the two copies part ways.
    local memory = Sim.New(options.galaxy, options.systems, options.history)
    local reloaded = Sim.New(options.galaxy, options.systems, options.history)
    local agreedAt = 0
    local differAt: number? = nil
    for _ = 1, options.ticks do
      Sim.Tick(memory)
      Sim.Tick(reloaded)
      if memory.tick % every == 0 then
        local hash
        reloaded, hash = reload(reloaded)
        if Codec.HashOf(memory) ~= hash then
          differAt = memory.tick
          break
        end
        agreedAt = memory.tick
      end
    end
    if differAt == nil then
      print(`simdiverge: no difference in {options.ticks} ticks `
        .. `(galaxy {options.galaxy}, history {options.history}, {options.systems} systems, reload every {every})`)
      return 0
    end
    print(`simdiverge: the copies agree at tick {agreedAt} and differ by tick {differAt}; replaying`)

    -- Pass 2: replay to the last agreement, then compare after every tick.
    memory = Sim.New(options.galaxy, options.systems, options.history)
    reloaded = Sim.New(options.galaxy, options.systems, options.history)
    for _ = 1, agreedAt do
      Sim.Tick(memory)
      Sim.Tick(reloaded)
      if memory.tick % every == 0 then
        reloaded = reload(reloaded)
      end
    end
    for _ = agreedAt + 1, differAt do
      Sim.Tick(memory)
      Sim.Tick(reloaded)
      local found: { string } = {}
      differences(memory, reloaded, "state", found, 40)
      if #found > 0 then
        table.sort(found)
        print(`first difference after tick {memory.tick} ({#found}{if #found >= 40 then "+" else ""} fields):`)
        for _, line in found do
          print("  " .. line)
        end
        return 1
      end
    end
    print("simdiverge: the hashes differ but no field does; this should not happen")
    return 1
  end,
}
