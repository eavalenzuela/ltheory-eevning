--!strict
-- A look at the factions at war (Core/Strategic/Wars), run by
-- themselves: bin/ltcore Tool/wars [systems] [days] [seed]
--
-- It builds a galaxy, lets so many game days go by with nobody flying
-- in it, and prints what happened: how many systems each faction holds
-- at the end (its home, and its claims), the wars and the truces, the
-- claims made, taken, held against a siege and let go, and how long the
-- whole of it took to work out.

local Galaxy = require("@lt/Core/Describe/Galaxy")
local Wars = require("@lt/Core/Strategic/Wars")

return { Main = function(args: { string }): number
  local systems, days, seed = tonumber(args[1]) or 400, tonumber(args[2]) or 30, tonumber(args[3]) or 1
  local galaxy = Galaxy.Describe(seed, systems)
  Galaxy.Deepen(galaxy)
  local wars = Wars.New(galaxy)
  local home: { [string]: number } = {}
  local open = 0
  for id = 1, Galaxy.Charted(galaxy) do
    local owner = galaxy.systems[id].owner
    if owner ~= "" then
      home[owner] = (home[owner] or 0) + 1
    else
      open += 1
    end
  end
  local counts: { [string]: number } = {}
  local started = os.clock()
  local log = 0
  for tick = 1, days * Wars.DAY do
    local events: { any } = {}
    Wars.Step(galaxy, wars, seed, tick, events)
    for _, event in events do
      local key = if event.kind == "OperationOver" then `OperationOver ({event.how})`
        elseif event.kind == "OperationBegan" then `OperationBegan ({event.what})` else event.kind
      counts[key] = (counts[key] or 0) + 1
      if (event.kind == "WarDeclared" or event.kind == "PeaceMade") and log < 24 then
        log += 1
        print(string.format("  day %5.1f  %s", tick / Wars.DAY, if event.kind == "WarDeclared" then `{event.by} declares war on {event.on}`
          else `{event.a} and {event.b} make a truce after {event.hours} hours, {event.score} claims to the first`))
      end
    end
  end
  print(string.format("%d systems (%d open), %d days in %.2f s", Galaxy.Charted(galaxy), open, days, os.clock() - started))
  local keys: { string } = {}
  for key in counts do
    table.insert(keys, key)
  end
  table.sort(keys)
  for _, key in keys do
    print(string.format("  %-28s %d", key, counts[key]))
  end
  local left = 0
  for id = 1, Galaxy.Charted(galaxy) do
    left += if galaxy.systems[id].owner == "" then 1 else 0
  end
  print(`  open systems left: {left}`)
  for _, faction in Galaxy.Holders(galaxy) do
    local claims = 0
    for _, owner in wars.claims do
      claims += if owner == faction then 1 else 0
    end
    print(string.format("  %-12s home %3d  claims %3d  strength %6.0f  weary %.2f", faction, home[faction] or 0, claims,
      wars.strength[faction] or 0, wars.weary[faction] or 0))
  end
  return 0
end }
