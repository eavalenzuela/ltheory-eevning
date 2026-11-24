--!strict
-- Windowless run of the galaxy as a game runs it with nobody flying in
-- it: the economy in the real bulk goods (Strategic/Commerce, with its
-- regional gluts and shortages), the pirates' pressure and surges
-- (Strategic/Happenings) and the factions at war (Strategic/Wars), each
-- stepped as Core.Step steps it, on a new game's own state. Judged by
-- Tool/EconProbe for the economy and by the checks below for the wars.
--
--   bin/ltcore Tool/galaxyrun [--galaxy N] [--systems N] [--days N] [--warm DAYS] [--settled DAYS] [--out DIR]
--
-- Defaults: galaxy seed 1, 400 systems, 30 game days, the first 5 not
-- judged, the economy settled for Commerce.SETTLED days first as a new
-- game's is. Prints the verdicts and exits 1 if any failed. With --out
-- DIR, writes DIR/series.csv (a row a game hour, the economy's) and
-- DIR/result.txt (the verdicts, as script/sweep reads them).
--
-- (This replaced Tool/econrun and Tool/factionrun on 2026-11-24, when the
-- headless faction model they ran was retired: the owner's "Yes, retire
-- the headless faction model". What they judged was a model the game did
-- not run.)
local Commerce = require("@lt/Core/Strategic/Commerce")
local Core = require("@lt/Core/Api")
local EconProbe = require("@lt/Tool/EconProbe")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local GalaxyStep = require("@lt/Tool/GalaxyStep")
local Wars = require("@lt/Core/Strategic/Wars")

return {
  Main = function(args: { string }): number
    local options: { [string]: number } = { galaxy = 1, systems = 400, days = 30, warm = 5, settled = Commerce.SETTLED }
    local out: string? = nil
    local i = 1
    while i <= #args do
      local name = string.match(args[i], "^%-%-(.+)$")
      local value = tonumber(args[i + 1])
      if name == "out" and args[i + 1] then
        out = args[i + 1]
      elseif name == nil or options[name] == nil or value == nil then
        print(`galaxyrun: bad argument '{args[i]}'; see the comment at the top of Tool/galaxyrun.luau`)
        return 2
      else
        options[name :: string] = value :: number
      end
      i += 2
    end

    local made = Host.Clock()
    local game = Core.New({ galaxySeed = options.galaxy, historySeed = options.galaxy, systems = options.systems, peaceful = true,
      wars = true, settled = options.settled })
    local state = game.state
    local galaxy = state.galaxy
    local setup = Host.Clock() - made
    local econ = state.commerce
    local probe = EconProbe.New()
    local here = 1

    -- What happened, counted.
    local counts: { [string]: number } = {}
    local open0 = 0
    for id = 1, Galaxy.Charted(galaxy) do
      open0 += if galaxy.systems[id].owner == "" then 1 else 0
    end
    local ticks = options.days * Wars.DAY
    for tick = 1, ticks do
      local events: { any } = {}
      GalaxyStep.Step(state, events, here)
      if tick % Wars.HOUR == 0 then
        EconProbe.Sample(probe, econ)
      end
      for _, event in events do
        local key = if event.kind == "OperationOver" then `OperationOver ({event.how})`
          elseif event.kind == "OperationBegan" then `OperationBegan ({event.what})` else event.kind
        counts[key] = (counts[key] or 0) + 1
      end
    end

    -- The economy's verdicts (Tool/EconProbe), then the wars'.
    local steps = math.max(1, ticks // Commerce.STEP)
    local stepMs = GalaxyStep.econ * 1000 / steps
    local restTime = GalaxyStep.rest
    local checks = EconProbe.Checks(probe, econ, options.warm, stepMs, 1 / Commerce.STEP)
    local function check(name: string, value: number, low: number?, high: number?)
      local ok = (low == nil or value >= low) and (high == nil or value <= high)
      local limit = if low and high then `{low} to {high}` elseif low then `>= {low}` else `<= {high}`
      table.insert(checks, { name = name, value = value, limit = limit, ok = ok })
    end
    local holders = Galaxy.Holders(galaxy)
    local claims: { [string]: number } = {}
    local claimed = 0
    for _, owner in state.wars.claims do
      claims[owner] = (claims[owner] or 0) + 1
      claimed += 1
    end
    local most, spent = 0, 0
    for _, faction in holders do
      most = math.max(most, claims[faction] or 0)
      spent += if (state.wars.strength[faction] or 0) <= 0 then 1 else 0
    end
    -- (the first figures for what a lively, unrigged map looks like: mine)
    -- (of what the factions may claim between them: in a big galaxy most
    -- of the open space stays open, as the owner ruled)
    local claimable = math.min(open0, #holders * Wars.CLAIMS)
    check("wars: what may be claimed, claimed (share)", if claimable > 0 then claimed / claimable else 1, 0.5, nil)
    check("wars: the largest holder's share of claims", if claimed > 0 then most / claimed else 0, nil, 0.45)
    check("wars: factions with nothing left to send", spent, nil, 0)
    check("wars: declared", counts.WarDeclared or 0, 1, nil)
    check("wars: truces made", counts.PeaceMade or 0, 1, nil)
    check("wars: ms a simulation tick, all but the economy", restTime * 1000 / ticks, nil, 1)

    local failed = 0
    local lines: { string } = {}
    for _, each in checks do
      if not each.ok then
        failed += 1
      end
      print(string.format("  %-4s %-44s %12.5f   (%s)", if each.ok then "ok" else "FAIL", each.name, each.value, each.limit))
      table.insert(lines, `check={each.name}|{each.value}|{each.limit}|{if each.ok then "ok" else "FAIL"}`)
    end
    local keys: { string } = {}
    for key in counts do
      table.insert(keys, key)
    end
    table.sort(keys)
    for _, key in keys do
      print(string.format("  %-36s %d", key, counts[key]))
    end
    -- (and any goods that lean on the homeworlds' dealings with the world
    -- beyond for more than a quarter of what passes: what nothing makes)
    for g, class in econ.classes do
      local through = econ.anchorIn[g] + econ.produced[g]
      if through > 0 and econ.anchorIn[g] / through > 0.25 then
        print(string.format("  leans on the homeworlds: %-20s %.0f%% of %.0f", class.id, 100 * econ.anchorIn[g] / through, through))
      end
    end
    for _, faction in holders do
      print(string.format("  %-12s claims %3d  strength %6.0f  weary %.2f", faction, claims[faction] or 0,
        state.wars.strength[faction] or 0, state.wars.weary[faction] or 0))
    end
    print(string.format("galaxyrun: galaxy %d, %d systems, %d days; set up in %.2f s, %.2f ms an economy step, %.4f ms a tick for the rest; %s",
      options.galaxy, Galaxy.Charted(galaxy), options.days, setup, stepMs, restTime * 1000 / ticks,
      if failed == 0 then "all checks passed" else `{failed} check(s) FAILED`))

    if out then
      Host.MakeDir(out)
      local rows = { table.concat(EconProbe.COLUMNS, ",") }
      for _, sample in probe.samples do
        local cells: { string } = {}
        for _, column in EconProbe.COLUMNS do
          table.insert(cells, string.format("%.6g", sample[column]))
        end
        table.insert(rows, table.concat(cells, ","))
      end
      local series = buffer.fromstring(table.concat(rows, "\n") .. "\n")
      Host.WriteFile(out .. "/series.csv", series, buffer.len(series))
      local result = buffer.fromstring(table.concat(lines, "\n") .. "\n")
      Host.WriteFile(out .. "/result.txt", result, buffer.len(result))
    end
    return if failed == 0 then 0 else 1
  end,
}
