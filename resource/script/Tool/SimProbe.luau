--!strict
-- Measures a run of the simulation: samples the state into time series,
-- and at the end judges the run against thresholds. The thresholds are
-- opening proposals (docs/roadmap.md §6) to be calibrated; what matters
-- is that a run which ends broke and fleetless cannot pass by being read
-- optimistically in a log.

local Sim = require("@lt/Sim/Sim")
local State = require("@lt/Sim/State")
local Stats = require("@lt/Tool/Stats")

local SimProbe = {}

export type Row = { tick: number, series: string, key: string, value: number }
export type Check = { name: string, value: number, limit: string, pass: boolean }

export type Probe = {
  rows: { Row },
  -- the totals, kept as arrays for the checks
  days: { number },
  credits: { number },
  warships: { number },
  haulers: { number },
  maintained: { number },
  arrearsSamples: number,
  factionSamples: number,
}

local TICKS_PER_DAY = 8640

function SimProbe.New(): Probe
  return { rows = {}, days = {}, credits = {}, warships = {}, haulers = {}, maintained = {},
    arrearsSamples = 0, factionSamples = 0 }
end

-- Record one sample of 'state'.
function SimProbe.Sample(probe: Probe, state: State.State)
  local tick = state.tick
  local function row(series: string, key: string, value: number)
    table.insert(probe.rows, { tick = tick, series = series, key = key, value = value })
  end

  local credits, warships, haulers = 0, 0, 0
  for id, s in Sim.Stats(state) do
    local faction = state.factions[id]
    row("credits", s.name, s.credits)
    row("systems", s.name, s.systems)
    row("warships", s.name, s.frigates + s.cruisers)
    row("haulers", s.name, s.haulers)
    row("costs", s.name, s.costs)
    if not faction.pirate and s.alive then
      credits += s.credits
      warships += s.frigates + s.cruisers
      haulers += s.haulers
      probe.factionSamples += 1
      if s.arrears > 0 then
        probe.arrearsSamples += 1
      end
    end
  end
  for _, e in Sim.Economy(state) do
    row("stock", e.good, e.stock)
    row("price", e.good, e.price)
  end

  local owned, ownedCount, independent, independentCount, treasury = 0, 0, 0, 0, 0
  for _, station in state.stations do
    if not station.destroyed then
      if state.systems[station.system].owner then
        owned += station.maintained
        ownedCount += 1
      else
        independent += station.maintained
        independentCount += 1
      end
    end
  end
  for _, system in state.systems do
    if system.owner == nil then
      treasury += system.credits
    end
  end
  local met = owned / math.max(1, ownedCount)
  row("total", "faction credits", credits)
  row("total", "warships", warships)
  row("total", "haulers", haulers)
  row("total", "independent treasury", treasury)
  row("total", "maintenance met (factions)", met)
  row("total", "maintenance met (independents)", independent / math.max(1, independentCount))

  table.insert(probe.days, tick / TICKS_PER_DAY)
  table.insert(probe.credits, credits)
  table.insert(probe.warships, warships)
  table.insert(probe.haulers, haulers)
  table.insert(probe.maintained, met)
end

-- Judge the run. Call after the last sample.
function SimProbe.Checks(probe: Probe, state: State.State): { Check }
  local checks: { Check } = {}
  local function check(name: string, value: number, limit: string, pass: boolean)
    table.insert(checks, { name = name, value = value, limit = limit, pass = pass })
  end

  local alive, total, largest, ownedSystems = 0, 0, 0, 0
  for id, s in Sim.Stats(state) do
    if not state.factions[id].pirate then
      total += 1
      if s.alive then
        alive += 1
      end
      largest = math.max(largest, s.systems)
      ownedSystems += s.systems
    end
  end
  check("factions alive", alive, `>= {math.ceil(total * 0.75)} of {total}`, alive >= math.ceil(total * 0.75))
  local share = largest / math.max(1, ownedSystems)
  check("largest share of owned systems", share, "< 0.45", share < 0.45)

  -- Drift per game day over the last two thirds of the run. A settled
  -- economy hovers; one that is bleeding out or inflating does not.
  local creditTrend = Stats.Trend(probe.days, probe.credits, 1000)
  check("faction credits trend per day", creditTrend, "within +-0.10", math.abs(creditTrend) <= 0.10)
  local fleetTrend = Stats.Trend(probe.days, probe.warships, 10)
  check("warships trend per day", fleetTrend, "within +-0.10", math.abs(fleetTrend) <= 0.10)

  local met = Stats.Median(probe.maintained)
  check("median maintenance met (factions)", met, ">= 0.85", met >= 0.85)
  local arrears = probe.arrearsSamples / math.max(1, probe.factionSamples)
  check("share of faction-time in arrears", arrears, "< 0.05", arrears < 0.05)
  return checks
end

function SimProbe.Csv(probe: Probe): string
  local lines = table.create(#probe.rows + 1)
  lines[1] = "tick,series,key,value"
  for i, r in probe.rows do
    lines[i + 1] = string.format("%d,%s,%s,%.10g", r.tick, r.series, r.key, r.value)
  end
  return table.concat(lines, "\n") .. "\n"
end

return SimProbe
