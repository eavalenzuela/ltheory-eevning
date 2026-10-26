--!strict
-- Headless run of the universe simulation: generates a galaxy, runs it
-- far faster than real time and prints a report every so often (territory,
-- fleets, credits, wars, the economy and the main news). The full news
-- feed goes to cache/sim_news.txt. Run with `bin/launch simrun`; it exits
-- when done. Edit the constants below to change the run.

local Ai = require("@lt/Sim/Ai")
local Sim = require("@lt/Sim/Sim")

local GALAXY_SEED = 1
local HISTORY_SEED: number? = nil -- nil: a fresh history each run; set it to replay one
local SYSTEMS = 400
local TICKS = 40000          -- 10 s each: 40000 ticks is about 4.6 days of game time
local REPORT_EVERY = 5000

local function gameTime(tick: number): string
  local minutes = tick * 10 // 60
  return string.format("day %d %02d:%02d", minutes // 1440 + 1, minutes // 60 % 24, minutes % 60)
end

local function pad(s: string, n: number): string
  return s .. string.rep(" ", math.max(0, n - #s))
end

local HEADLINES = { capture = true, war = true, peace = true, eliminated = true, lapse = true, construct = true }

return {
  Initialize = function()
    local started = os.clock()
    local state = Sim.New(GALAXY_SEED, SYSTEMS, HISTORY_SEED)
    local stations = #state.galaxy.stations
    local links = 0
    for _, system in state.galaxy.systems do
      links += #system.neighbors
    end
    print(`galaxy seed {state.seed}, history seed {state.history}: {SYSTEMS} systems, {links // 2} gate links, `
      .. `{stations} stations; generated in {string.format("%.2f", os.clock() - started)} s`)

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
            .. `{string.format("%9.0f", s.credits)} cr  costs {string.format("%5.0f", s.costs)}/period`
            .. `{if s.arrears > 0 then ` ARREARS {s.arrears}` else ""}{status}{wars}`)
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
        local timing = {}
        local timingKeys = {}
        for k in Sim.Timing do
          table.insert(timingKeys, k)
        end
        table.sort(timingKeys)
        for _, k in timingKeys do
          table.insert(timing, `{k} {string.format("%.2f", Sim.Timing[k] * 1000 / REPORT_EVERY)}`)
          Sim.Timing[k] = 0
        end
        print("  ms per tick: " .. table.concat(timing, ", "))
        local decisions = {}
        local decisionKeys = {}
        for k in Ai.Timing do
          table.insert(decisionKeys, k)
        end
        table.sort(decisionKeys)
        for _, k in decisionKeys do
          table.insert(decisions, `{k} {string.format("%.2f", Ai.Timing[k] * 1000 / REPORT_EVERY)}`)
          Ai.Timing[k] = 0
        end
        print("  decisions ms per tick: " .. table.concat(decisions, ", "))
        local economy = {}
        for _, row in Sim.Economy(state) do
          table.insert(economy, `{row.good} {math.floor(row.stock)} @{math.floor(row.price)}`)
        end
        print("  economy: " .. table.concat(economy, ", "))
        -- Independent treasuries and how well stations are maintained
        local treasury, independent = 0, 0
        local maintained = { owned = 0, owned_n = 0, independent = 0, independent_n = 0 }
        for _, system in state.systems do
          if system.owner == nil then
            treasury += system.credits
            independent += 1
          end
        end
        for _, station in state.stations do
          if not station.destroyed then
            if state.systems[station.system].owner then
              maintained.owned += station.maintained
              maintained.owned_n += 1
            else
              maintained.independent += station.maintained
              maintained.independent_n += 1
            end
          end
        end
        print(`  independents: {independent} systems, treasury {math.floor(treasury)}; maintenance met: `
          .. `factions {math.floor(100 * maintained.owned / math.max(1, maintained.owned_n))}%, `
          .. `independents {math.floor(100 * maintained.independent / math.max(1, maintained.independent_n))}%`)
        local headlines = 0
        for i = newsSeen + 1, #state.news do
          local event = state.news[i]
          if HEADLINES[event.kind] and headlines < 14 then
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
