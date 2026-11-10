--!strict
-- Windowless run of the universe simulation:
--
--   bin/ltcore Tool/simrun [--galaxy N] [--history N] [--systems N]
--                          [--ticks N] [--reload-every N] [--report-every N]
--                          [--sample-every N] [--out DIR]
--
-- Prints one result line with the final state hash and the time per tick.
-- --reload-every N saves the state to bytes and loads it back every N
-- ticks; the final hash must not depend on it (that is the determinism
-- check, at whatever scale the arguments give). --report-every N prints
-- faction standings as the run goes. Defaults: galaxy 1, history 1, 400
-- systems, 10000 ticks, no reloads, no reports.
--
-- With --out DIR the run is measured (Tool/SimProbe): the state is
-- sampled every --sample-every ticks (default 60, ten game minutes) into
-- DIR/series.csv, the run is judged against the thresholds, and the
-- verdict goes to DIR/result.txt and the news feed to DIR/news.txt. The
-- exit status is then 1 if any check failed. script/simsweep runs this
-- across seeds.

local Codec = require("@lt/Core/Persist/Codec")
local Sim = require("@lt/Sim/Sim")
local SimProbe = require("@lt/Tool/SimProbe")

local function gameTime(tick: number): string
  local minutes = tick * 10 // 60
  return string.format("day %d %02d:%02d", minutes // 1440 + 1, minutes // 60 % 24, minutes % 60)
end

return {
  Main = function(args: { string }): number
    local options: { [string]: number } = {
      galaxy = 1, history = 1, systems = 400, ticks = 10000, ["reload-every"] = 0, ["report-every"] = 0,
      ["sample-every"] = 60,
    }
    local out: string? = nil
    local i = 1
    while i <= #args do
      local name = string.match(args[i], "^%-%-(.+)$")
      local value = tonumber(args[i + 1])
      if name == "out" and args[i + 1] then
        out = args[i + 1]
      elseif name == nil or options[name] == nil or value == nil then
        print(`simrun: bad argument '{args[i]}'; see the comment at the top of Tool/simrun.luau`)
        return 2
      else
        options[name :: string] = value :: number
      end
      i += 2
    end

    local started = Host.Clock()
    local state = Sim.New(options.galaxy, options.systems, options.history)
    local probe = SimProbe.New()
    local reloads, reloadTime = 0, 0
    for _ = 1, options.ticks do
      Sim.Tick(state)
      if out and state.tick % options["sample-every"] == 0 then
        SimProbe.Sample(probe, state)
      end
      if options["reload-every"] > 0 and state.tick % options["reload-every"] == 0 then
        local before = Host.Clock()
        local data, length = Codec.Encode(state)
        state = Codec.Decode(data, length)
        reloads += 1
        reloadTime += Host.Clock() - before
      end
      if options["report-every"] > 0 and state.tick % options["report-every"] == 0 then
        print(`==== tick {state.tick} ({gameTime(state.tick)})`)
        for _, s in Sim.Stats(state) do
          print(string.format("  %-22s %3d systems  %3d frig %3d cru %3d haul  %9.0f cr%s",
            s.name, s.systems, s.frigates, s.cruisers, s.haulers, s.credits,
            if s.alive then "" else " (eliminated)"))
        end
      end
    end

    local data, length = Codec.Encode(state)
    local elapsed = Host.Clock() - started - reloadTime
    print(string.format("hash %s  galaxy %d history %d systems %d ticks %d  %.2f ms/tick  state %d bytes%s",
      Codec.Hash(data, length), options.galaxy, options.history, options.systems, state.tick,
      elapsed * 1000 / options.ticks, length,
      if reloads > 0 then string.format("  %d reloads at %.0f ms each", reloads, reloadTime * 1000 / reloads) else ""))
    if out == nil then
      return 0
    end

    local dir: string = out
    if not Host.MakeDir(dir) then
      print(`simrun: cannot create {dir}`)
      return 2
    end
    local failed = 0
    local result = {
      `hash={Codec.Hash(data, length)}`,
      `galaxy={options.galaxy}`, `history={options.history}`, `systems={options.systems}`, `ticks={state.tick}`,
      string.format("ms_per_tick=%.3f", elapsed * 1000 / options.ticks),
    }
    for _, c in SimProbe.Checks(probe, state) do
      if not c.pass then
        failed += 1
      end
      print(string.format("  %-4s %-36s %10.3f   (%s)", if c.pass then "ok" else "FAIL", c.name, c.value, c.limit))
      table.insert(result, string.format("check=%s|%.6g|%s|%s", c.name, c.value, c.limit, if c.pass then "ok" else "FAIL"))
    end
    local news = table.create(#state.news)
    for n, event in state.news do
      news[n] = `[{gameTime(event.tick)}] {event.kind}: {event.text}`
    end
    Host.WriteFile(dir .. "/series.csv", SimProbe.Csv(probe))
    Host.WriteFile(dir .. "/news.txt", table.concat(news, "\n") .. "\n")
    Host.WriteFile(dir .. "/result.txt", table.concat(result, "\n") .. "\n")
    return if failed > 0 then 1 else 0
  end,
}
