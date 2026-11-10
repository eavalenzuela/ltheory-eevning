--!strict
-- Windowless run of the galaxy's economy (Strategic/Atlas on the
-- Strategic/Economy kernel), measured and judged by Tool/EconProbe:
--
--   bin/ltcore Tool/econrun [--galaxy N] [--systems N] [--days N] [--step SECONDS]
--                           [--warm DAYS] [--out DIR] [--goods 1] [--atlas 1]
--                           [--slack X] [--haul X] [--jump X] [--border X] [--risk X] [--anchor X] [--source X]
--                           [--dig X] [--floor X] [--all 1]
--                           [--detail 1]
--
-- Defaults: galaxy seed 1, 400 systems, 30 game days, a step a game
-- minute (the economy steps once every six ten-second ticks), the first
-- 10 days not judged. Prints the verdicts and exits 1 if any failed.
-- With --out DIR, writes DIR/series.csv (a row a game hour) and
-- DIR/result.txt (the verdicts, as script/econsweep reads them).
-- --goods 1 prints the classes of goods and their prices and stops;
-- --atlas 1 prints who has what and stops; --detail 1 adds, after a run,
-- every class's price level and every step's use. The tuning options
-- override the atlas's settings (Atlas.SLACK and the rest) for one run:
-- for finding out what a setting does, not for passing a check.

local Atlas = require("@lt/Core/Strategic/Atlas")
local EconProbe = require("@lt/Tool/EconProbe")
local Economy = require("@lt/Core/Strategic/Economy")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Goods = require("@lt/Core/Data/Goods")

local function printGoods()
  local used: { number } = {}
  for g, class in Goods.list do
    used[g] = class.need
  end
  local required = Goods.Required(used)
  print(string.format("%-18s %-12s %12s %14s %14s", "class", "tier", "price", "used cr/h", "made cr/h"))
  for g, class in Goods.list do
    print(string.format("%-18s %-12s %12.1f %14.0f %14.0f", class.id, class.tier, class.par, class.need * class.par,
      required[g] * class.par))
  end
end

local function printAtlas(galaxy: Galaxy.Galaxy, atlas: Atlas.Atlas)
  print(string.format("%d systems, %d lanes, population %.0f", #atlas.systems, #atlas.lanes, atlas.population))
  for _, faction in atlas.factions do
    local systems, people = 0, 0
    for _, info in atlas.systems do
      if info.owner == faction.id then
        systems += 1
        people += info.population
      end
    end
    print(string.format("  %-18s home %-12s %3d systems, population %6.1f", faction.name, galaxy.systems[faction.home].name,
      systems, people))
  end
  local unclaimed, borders = 0, 0
  for _, info in atlas.systems do
    if info.owner == 0 then
      unclaimed += 1
    end
  end
  for _, lane in atlas.lanes do
    if lane.border then
      borders += 1
    end
  end
  print(string.format("  unclaimed %d systems; %d lanes cross a border", unclaimed, borders))
  for at, step in Goods.steps do
    local hosts, capacity = 0, 0
    for _, info in atlas.systems do
      for _, facility in info.facilities do
        if facility.recipe == at then
          hosts += 1
          capacity += facility.capacity
        end
      end
    end
    print(string.format("  %-18s %3d systems, capacity %12.1f an hour", step.id, hosts, capacity))
  end
end

-- Where the economy stands now: each class's price against normal, by
-- value held, in the best and worst supplied tenth of systems, and how
-- much of each step's capacity is running.
local function printDetail(econ: Economy.Economy, atlas: Atlas.Atlas)
  print(string.format("%-18s %8s %8s %8s %8s   %s", "class", "price", "low 10%", "high 10%", "anchor", "(prices as multiples of normal)"))
  for g, class in econ.classes do
    local ratios: { number } = {}
    local sum, weight = 0, 0
    for id, node in econ.nodes do
      local ratio = Economy.Price(econ, id, g) / class.par
      table.insert(ratios, ratio)
      sum += ratio * node.target[g]
      weight += node.target[g]
    end
    table.sort(ratios)
    local through = econ.anchorIn[g] + econ.produced[g]
    print(string.format("%-18s %8.3f %8.3f %8.3f %8.3f", class.id, sum / weight, ratios[math.ceil(#ratios * 0.1)],
      ratios[math.ceil(#ratios * 0.9)], if through > 0 then econ.anchorIn[g] / through else 0))
  end
  print(string.format("\n%-18s %8s %8s", "step", "in use", "hosts"))
  for at, recipe in econ.recipes do
    local could, does, hosts = 0, 0, 0
    for _, node in econ.nodes do
      for _, facility in node.facilities do
        if facility.recipe == at then
          could += facility.capacity
          does += facility.activity
          hosts += 1
        end
      end
    end
    print(string.format("%-18s %8.3f %8d", recipe.id, if could > 0 then does / could else 0, hosts))
  end
  -- How people fare by how safe their system is.
  print(string.format("\n%-18s %8s %8s", "security", "met", "systems"))
  for band = 0, 4 do
    local people, fed, count = 0, 0, 0
    for id, info in atlas.systems do
      if math.min(4, math.floor(info.security * 5)) == band then
        people += info.population
        fed += info.population * econ.nodes[id].met
        count += 1
      end
    end
    print(string.format("%.1f to %.1f         %8.3f %8d", band / 5, (band + 1) / 5, if people > 0 then fed / people else 0, count))
  end
end

return {
  Main = function(args: { string }): number
    local options: { [string]: number } = { galaxy = 1, systems = 400, days = 30, step = 60, warm = 10, goods = 0, atlas = 0,
      slack = Atlas.SLACK, haul = Atlas.HAUL, jump = Atlas.COST_JUMP, border = Atlas.COST_BORDER, risk = Atlas.COST_RISK,
      anchor = Atlas.ANCHOR, source = Atlas.AT_SOURCE, dig = Atlas.DIG, floor = Atlas.SECURITY_FLOOR,
      all = 0, detail = 0 }
    local out: string? = nil
    local i = 1
    while i <= #args do
      local name = string.match(args[i], "^%-%-(.+)$")
      local value = tonumber(args[i + 1])
      if name == "out" and args[i + 1] then
        out = args[i + 1]
      elseif name == nil or options[name] == nil or value == nil then
        print(`econrun: bad argument '{args[i]}'; see the comment at the top of Tool/econrun.luau`)
        return 2
      else
        options[name :: string] = value :: number
      end
      i += 2
    end
    if options.goods ~= 0 then
      printGoods()
      return 0
    end

    Atlas.SLACK, Atlas.HAUL, Atlas.ANCHOR, Atlas.AT_SOURCE = options.slack, options.haul, options.anchor, options.source
    Atlas.SECURITY_FLOOR = options.floor
    Atlas.COST_JUMP, Atlas.COST_BORDER, Atlas.COST_RISK = options.jump, options.border, options.risk
    Atlas.DIG, Atlas.ANCHOR_ALL = options.dig, options.all ~= 0
    local galaxy = Galaxy.Describe(options.galaxy, options.systems)
    local atlas = Atlas.Describe(galaxy, options.galaxy)
    if options.atlas ~= 0 then
      printAtlas(galaxy, atlas)
      return 0
    end
    local econ = Atlas.Economy(galaxy, atlas)
    local probe = EconProbe.New()

    local dt = options.step / 3600
    local stepsPerHour = math.max(1, math.floor(3600 / options.step + 0.5))
    local stepping = 0
    for _ = 1, options.days * 24 do
      local started = Host.Clock()
      for _ = 1, stepsPerHour do
        Economy.Step(econ, dt)
      end
      stepping += Host.Clock() - started
      EconProbe.Sample(probe, econ)
    end
    local stepMs = stepping * 1000 / econ.steps
    -- A simulation tick is ten game seconds.
    local checks = EconProbe.Checks(probe, econ, options.warm, stepMs, 10 / options.step)

    local failed = 0
    local lines: { string } = {}
    for _, check in checks do
      if not check.ok then
        failed += 1
      end
      print(string.format("  %-4s %-36s %12.5f   (%s)", if check.ok then "ok" else "FAIL", check.name, check.value, check.limit))
      table.insert(lines, `check={check.name}|{check.value}|{check.limit}|{if check.ok then "ok" else "FAIL"}`)
    end
    print(string.format("econrun: galaxy %d, %d systems, %d days, %d steps of %.0f s, %.2f ms a step; %s",
      options.galaxy, options.systems, options.days, econ.steps, options.step, stepMs,
      if failed == 0 then "all checks passed" else `{failed} check(s) FAILED`))

    if options.detail ~= 0 then
      printDetail(econ, atlas)
    end

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
