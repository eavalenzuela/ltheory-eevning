--!strict
-- Headless run of the universe simulation: generates a galaxy, runs it
-- far faster than real time and prints a report every so often (territory,
-- fleets, credits, wars, the economy and the main news). The full news
-- feed goes to cache/sim_news.txt. Run with `bin/launch simrun`; it exits
-- when done. Edit the constants below to change the run.

local Sim = require("@lt/Sim/Sim")

local SEED = 1
local SYSTEMS = 400
local TICKS = 20000          -- 10 s each: 20000 ticks is about 55 hours of game time
local REPORT_EVERY = 2500

local function gameTime(tick: number): string
  local minutes = tick * 10 // 60
  return string.format("day %d %02d:%02d", minutes // 1440 + 1, minutes // 60 % 24, minutes % 60)
end

local function pad(s: string, n: number): string
  return s .. string.rep(" ", math.max(0, n - #s))
end

local HEADLINES = { capture = true, war = true, peace = true, eliminated = true }

return {
  Initialize = function()
    local started = os.clock()
    local state = Sim.New(SEED, SYSTEMS)
    local stations = #state.galaxy.stations
    local links = 0
    for _, system in state.galaxy.systems do
      links += #system.neighbors
    end
    print(`galaxy: {SYSTEMS} systems, {links // 2} gate links, {stations} stations; generated in `
      .. `{string.format("%.2f", os.clock() - started)} s`)

    local lastCounters: { [string]: number } = {}
    local newsSeen = 0
    local tickStart = os.clock()
    for _ = 1, TICKS do
      Sim.Tick(state)
      if state.tick % REPORT_EVERY == 0 then
        local elapsed = os.clock() - tickStart
        print("")
        print(`==== tick {state.tick} ({gameTime(state.tick)}), {string.format("%.2f", elapsed * 1000 / state.tick)} ms per tick`)
        for _, s in Sim.Stats(state) do
          local status = if s.alive then "" else " (eliminated)"
          local wars = if #s.wars > 0 then "  war: " .. table.concat(s.wars, ", ") else ""
          print(`  {pad(s.name, 22)} {string.format("%3d", s.systems)} systems  {string.format("%3d", s.frigates)} frig `
            .. `{string.format("%3d", s.cruisers)} cru {string.format("%3d", s.haulers)} haul  `
            .. `{string.format("%9.0f", s.credits)} cr{status}{wars}`)
        end
        local parts = {}
        local keys = {}
        for k in state.counters do
          table.insert(keys, k)
        end
        table.sort(keys)
        for _, k in keys do
          local delta = state.counters[k] - (lastCounters[k] or 0)
          lastCounters[k] = state.counters[k]
          if delta > 0 then
            table.insert(parts, `{k} {math.floor(delta)}`)
          end
        end
        print("  since last: " .. table.concat(parts, ", "))
        local economy = {}
        for _, row in Sim.Economy(state) do
          table.insert(economy, `{row.good} {math.floor(row.stock)} @{math.floor(row.price)}`)
        end
        print("  economy: " .. table.concat(economy, ", "))
        local headlines = 0
        for i = newsSeen + 1, #state.news do
          local event = state.news[i]
          if HEADLINES[event.kind] and headlines < 12 then
            print(`    [{gameTime(event.tick)}] {event.text}`)
            headlines += 1
          end
        end
        newsSeen = #state.news
      end
    end

    local lines = {}
    for _, event in state.news do
      table.insert(lines, `[{gameTime(event.tick)}] {event.kind}: {event.text}`)
    end
    File_Write("cache/sim_news.txt", table.concat(lines, "\n") .. "\n")
    print("")
    print(`done: {TICKS} ticks in {string.format("%.1f", os.clock() - started)} s; {#state.news} news events in cache/sim_news.txt`)
  end,
}
