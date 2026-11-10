--!strict
-- Windowless run of the strategic simulation (Core/Strategic/Sim: the
-- powers, their wars and the pirates on the galaxy's economy), measured
-- and judged by Tool/FactionProbe:
--
--   bin/ltcore Tool/factionrun [--galaxy N] [--history N] [--systems N] [--days N] [--warm DAYS]
--                              [--out DIR] [--news 1] [--every HOURS] [--detail 1]
--
-- Defaults: galaxy seed 1, history seed the same as the galaxy's, 400
-- systems, 30 game days, the first 10 days not judged where a check
-- says so. Prints the verdicts and exits 1 if any failed. With --out
-- DIR, writes DIR/series.csv (a row a game hour), DIR/news.txt (the
-- last few hundred events) and DIR/result.txt (the verdicts, as
-- script/factionsweep reads them). --news 1 prints events as they
-- happen (--news 2: plans, claims and raids too); --every H prints a
-- line on the state of the galaxy every H hours; --detail 1 adds a
-- table of the powers, where the money went, and the counters.

local FactionProbe = require("@lt/Tool/FactionProbe")
local Ledger = require("@lt/Core/Kernel/Ledger")
local Powers = require("@lt/Core/Data/Powers")
local Sim = require("@lt/Core/Strategic/Sim")
local World = require("@lt/Core/Strategic/World")

local QUIET: { [string]: boolean } = { plan = true, claim = true, raid = true, assault = true, release = true, siege = true,
  battle = true, lifted = true, capture = true, embargo = true }

local function clock(tick: number): string
  local minutes = tick // 6
  return string.format("d%02d %02d:%02d", minutes // 1440, minutes // 60 % 24, minutes % 60)
end

local function printPowers(world: World.World)
  print(string.format("\n%-18s %5s %7s %9s %8s %8s %6s %6s %5s %5s  %s", "power", "sys", "people", "credits", "income", "costs",
    "navy", "laid", "pol", "arr%", "at war with"))
  for _, faction in world.factions do
    local people = 0
    for id, s in world.systems do
      if s.owner == faction.id then
        people += world.atlas.systems[id].population
      end
    end
    local laidUp = 0
    for class, count in faction.reserve do
      laidUp += count * Powers.ships[class].strength
    end
    local wars: { string } = {}
    for _, war in world.wars do
      if war.a == faction.id then
        table.insert(wars, world.factions[war.b].name .. "*")
      elseif war.b == faction.id then
        table.insert(wars, world.factions[war.a].name)
      end
    end
    print(string.format("%-18s %5d %7.1f %9.0f %8.0f %8.0f %6.0f %6.0f %5.2f %5.1f  %s%s", faction.name, faction.systems, people,
      faction.credits, faction.income, faction.costs, World.Navy(world, faction.id), laidUp, faction.policing,
      if faction.periods > 0 then 100 * faction.periodsInArrears / faction.periods else 0,
      if faction.alive then "" else "(gone) ", table.concat(wars, ", ")))
  end
end

-- How each pair of powers stands, and how many lanes join their space.
local function printRelations(world: World.World)
  print("\nrelations (lanes across the border):")
  for _, a in world.factions do
    if not a.pirate then
      local cells: { string } = {}
      for _, b in world.factions do
        if not b.pirate then
          local links = 0
          for _, lane in world.atlas.lanes do
            local oa, ob = world.systems[lane.a].owner, world.systems[lane.b].owner
            if (oa == a.id and ob == b.id) or (oa == b.id and ob == a.id) then
              links += 1
            end
          end
          table.insert(cells, if a.id == b.id then "     --  " else string.format("%5.0f(%2d)", a.relations[b.id], links))
        end
      end
      print(string.format("  %-18s %s", a.name, table.concat(cells, " ")))
    end
  end
end

local function printMoney(world: World.World)
  print("\ncredits in, by reason:")
  for _, line in Ledger.Sources(world.ledger, "credits") do
    print(string.format("  %-20s %14.0f", line.reason, line.amount))
  end
  print("credits out, by reason:")
  for _, line in Ledger.Sinks(world.ledger, "credits") do
    print(string.format("  %-20s %14.0f", line.reason, line.amount))
  end
  local names: { string } = {}
  for name in world.counters do
    table.insert(names, name)
  end
  table.sort(names)
  print("counted:")
  for _, name in names do
    print(string.format("  %-28s %12.0f", name, world.counters[name]))
  end
end

return {
  Main = function(args: { string }): number
    local options: { [string]: number } = { galaxy = 1, history = -1, systems = 400, days = 30, warm = 10, news = 0, every = 0,
      detail = 0 }
    local out: string? = nil
    local i = 1
    while i <= #args do
      local name = string.match(args[i], "^%-%-(.+)$")
      local value = tonumber(args[i + 1])
      if name == "out" and args[i + 1] then
        out = args[i + 1]
      elseif name == nil or options[name] == nil or value == nil then
        print(`factionrun: bad argument '{args[i]}'; see the comment at the top of Tool/factionrun.luau`)
        return 2
      else
        options[name :: string] = value :: number
      end
      i += 2
    end
    local history = if options.history < 0 then options.galaxy else options.history

    local world = Sim.New(options.galaxy, options.systems, history)
    local probe = FactionProbe.New(world)
    local seen = 0     -- news items printed so far, by the count of all news ever
    local total = 0
    local kept: { string } = {}
    local ticking = 0
    for hour = 1, options.days * 24 do
      local started = Host.Clock()
      for _ = 1, 360 do
        Sim.Tick(world)
      end
      ticking += Host.Clock() - started
      FactionProbe.Sample(probe, world)
      -- The news since the last look. (The world keeps only the latest
      -- few hundred, so count from the newest back.)
      local all = 0
      for name, n in world.counters do
        if string.sub(name, 1, 6) == "news: " then
          all += n
        end
      end
      local fresh = math.min(all - total, #world.news)
      for at = #world.news - fresh + 1, #world.news do
        local item = world.news[at]
        local line = `{clock(item.tick)}  {item.text}`
        table.insert(kept, line)
        if options.news >= 2 or (options.news >= 1 and not QUIET[item.kind]) then
          print(line)
        end
      end
      total = all
      seen += fresh
      if options.every > 0 and hour % options.every == 0 then
        local s = probe.samples[#probe.samples]
        print(string.format("%s  alive %d  claimed %.2f  largest %.2f  wars %d  navy %5.0f (+%4.0f laid up)  income %7.0f  "
          .. "costs %7.0f  sec %.2f  dens %d  met %.3f  price %.3f", clock(world.tick), s.alive, s.claimed, s.largest, s.wars,
          s.navy, s.laidUp, s.income, s.costs, s.security, s.dens, s.met, s.priceIndex))
      end
    end
    local tickMs = ticking * 1000 / world.tick
    local checks = FactionProbe.Checks(probe, world, options.warm, tickMs)

    local failed = 0
    local lines: { string } = {}
    for _, check in checks do
      if not check.ok then
        failed += 1
      end
      print(string.format("  %-4s %-40s %12.5f   (%s)", if check.ok then "ok" else "FAIL", check.name, check.value, check.limit))
      table.insert(lines, `check={check.name}|{check.value}|{check.limit}|{if check.ok then "ok" else "FAIL"}`)
    end
    print(string.format("factionrun: galaxy %d, history %d, %d systems, %d days, %.3f ms a tick; %s",
      options.galaxy, history, options.systems, options.days, tickMs,
      if failed == 0 then "all checks passed" else `{failed} check(s) FAILED`))

    if options.detail ~= 0 then
      printPowers(world)
      printRelations(world)
      printMoney(world)
    end

    if out then
      Host.MakeDir(out)
      local rows = { table.concat(FactionProbe.COLUMNS, ",") }
      for _, sample in probe.samples do
        local cells: { string } = {}
        for _, column in FactionProbe.COLUMNS do
          table.insert(cells, string.format("%.6g", sample[column] or 0))
        end
        table.insert(rows, table.concat(cells, ","))
      end
      local function write(name: string, text: string)
        local data = buffer.fromstring(text)
        Host.WriteFile(out .. "/" .. name, data, buffer.len(data))
      end
      write("series.csv", table.concat(rows, "\n") .. "\n")
      write("news.txt", table.concat(kept, "\n") .. "\n")
      write("result.txt", table.concat(lines, "\n") .. "\n")
    end
    return if failed == 0 then 0 else 1
  end,
}
