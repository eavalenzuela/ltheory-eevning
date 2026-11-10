--!strict
-- Measures a run of the strategic simulation (the powers, their wars,
-- the pirates, on the galaxy's economy) and judges it.
--
-- Sample once a game hour. At the end, Checks gives a verdict on each
-- thing a working faction layer has to do (docs/roadmap.md §6, stage
-- S3). Some are counted over the whole run, some over the run after its
-- first 'warm' days: a world starts at the founding, with every power on
-- one system, and the first days are a land rush that says little about
-- how the settled galaxy behaves.
--
--   books balance         no credit and no goods outside the ledgers
--   powers survive        most are alive at the end, none has swallowed
--                         the map, few are ever unable to pay their way
--   they grow             most people come under a power, a frontier is
--                         left, and what is claimed stays policed
--   they fight            wars are declared, cost ships, and end
--   the player can keep   from a plan being visible to a system falling
--   up                    is long enough to get there
--   people are supplied   war and piracy disturb the economy without
--                         breaking it
--   pirates persist       dens survive, without pirates owning the lanes
--   it is cheap           a tick costs little

local Economy = require("@lt/Core/Strategic/Economy")
local EconProbe = require("@lt/Tool/EconProbe")
local Ledger = require("@lt/Core/Kernel/Ledger")
local Powers = require("@lt/Core/Data/Powers")
local World = require("@lt/Core/Strategic/World")

local FactionProbe = {}

export type Sample = { [string]: number }

export type Probe = {
  samples: { Sample },
  econ: EconProbe.Probe,
  powers: number,           -- how many there were at the start
}

export type Check = { name: string, value: number, limit: string, ok: boolean }

FactionProbe.COLUMNS = { "hours", "alive", "claimed", "governed", "largest", "smallest", "atWar", "wars", "arrears", "navy", "laidUp",
  "credits", "income", "costs", "security", "pressure", "dens", "pirateCredits", "pirateFleet", "met", "priceIndex",
  "anchorShare", "closedLanes" }

function FactionProbe.New(world: World.World): Probe
  local powers = 0
  for _, faction in world.factions do
    if not faction.pirate then
      powers += 1
    end
  end
  return { samples = {}, econ = EconProbe.New(), powers = powers }
end

function FactionProbe.Sample(probe: Probe, world: World.World)
  EconProbe.Sample(probe.econ, world.econ)
  local econ = probe.econ.samples[#probe.econ.samples]
  local sample: Sample = { hours = world.tick / 360, met = econ.met, priceIndex = econ.priceIndex, anchorShare = econ.anchorShare }

  local alive, atWar, arrears, largest, smallest = 0, 0, 0, 0, math.huge
  local navy, laidUp, credits, income, costs = 0, 0, 0, 0, 0
  for _, faction in world.factions do
    if faction.pirate then
      sample.pirateCredits = faction.credits
      sample.pirateFleet = World.Navy(world, faction.id)
    elseif faction.alive then
      alive += 1
      largest = math.max(largest, faction.systems)
      smallest = math.min(smallest, faction.systems)
      if World.AtWar(world, faction.id) then
        atWar += 1
      end
      if faction.credits < 0 then
        arrears += 1
      end
      navy += World.Navy(world, faction.id)
      for class, count in faction.reserve do
        laidUp += count * Powers.ships[class].strength
      end
      credits += faction.credits
      income += faction.income
      costs += faction.costs
    end
  end
  local count = #world.systems
  local claimed, security, pressure, dens = 0, 0, 0, 0
  local people, governed = 0, 0
  for id, s in world.systems do
    people += world.atlas.systems[id].population
    if s.owner > 0 then
      claimed += 1
      security += s.security
      governed += world.atlas.systems[id].population
    end
    pressure += s.pressure
    if s.den then
      dens += 1
    end
  end
  local closed = 0
  for _, edge in world.econ.edges do
    if not edge.open then
      closed += 1
    end
  end
  sample.alive = alive
  sample.claimed = claimed / count
  sample.governed = governed / people
  sample.largest = largest / count
  sample.smallest = if alive > 0 then smallest / count else 0
  sample.atWar = if alive > 0 then atWar / alive else 0
  sample.wars = #world.wars
  sample.arrears = if alive > 0 then arrears / alive else 0
  sample.navy = navy
  sample.laidUp = laidUp
  sample.credits = credits
  sample.income = income
  sample.costs = costs
  sample.security = if claimed > 0 then security / claimed else 0
  sample.pressure = pressure / count
  sample.dens = dens
  sample.closedLanes = closed / math.max(1, #world.econ.edges)
  table.insert(probe.samples, sample)
end

local function average(samples: { Sample }, column: string, warmHours: number): number
  local sum, count = 0, 0
  for _, sample in samples do
    if sample.hours > warmHours then
      sum += sample[column]
      count += 1
    end
  end
  return if count > 0 then sum / count else 0
end

local function median(values: { number }): number
  if #values == 0 then
    return 0
  end
  local sorted = table.clone(values)
  table.sort(sorted)
  return sorted[(#sorted + 1) // 2]
end

-- The verdicts. 'tickMs' is the measured time of a tick.
function FactionProbe.Checks(probe: Probe, world: World.World, warmDays: number, tickMs: number): { Check }
  local warm = warmDays * 24
  local checks: { Check } = {}
  local function check(name: string, value: number, low: number?, high: number?)
    local ok = (low == nil or value >= low) and (high == nil or value <= high)
    local limit = if low and high then `{low} to {high}` elseif low then `>= {low}` else `<= {high}`
    table.insert(checks, { name = name, value = value, limit = limit, ok = ok })
  end
  local counters = world.counters
  local function counted(name: string): number
    return counters[name] or 0
  end
  local last = probe.samples[#probe.samples]

  -- The books. Credits: every wallet against the ledger, to within
  -- rounding on the largest sum that moved. Goods: the economy's own.
  local moved = 1
  for _, line in Ledger.Sources(world.ledger, "credits") do
    moved += line.amount
  end
  check("books: wallets off the ledger", #Ledger.Reconcile(world.ledger, "credits", World.Wallets(world), moved * 1e-9), nil, 0)
  local leak = 0
  local econ = world.econ
  for g, residual in Economy.Residual(econ) do
    local through = econ.initial[g] + econ.produced[g] + econ.anchorIn[g] + econ.moved[g]
    leak = math.max(leak, math.abs(residual) / math.max(1, through))
  end
  check("books: worst leak of goods (share)", leak, nil, 1e-9)

  -- The powers.
  check("powers alive at the end (share)", last.alive / probe.powers, 0.75, nil)
  check("largest power's share of systems", last.largest, nil, 0.45)
  local periods, owing = 0, 0
  for _, faction in world.factions do
    if not faction.pirate then
      periods += faction.periods
      owing += faction.periodsInArrears
    end
  end
  check("power-time in arrears (share)", if periods > 0 then owing / periods else 0, nil, 0.05)
  -- Most people live under some power; a good part of the map (the
  -- poor, far systems, which cost more to hold than they bring) does not
  -- belong to any.
  check("people living under a power (share)", last.governed, 0.7, nil)
  check("systems claimed at the end (share)", last.claimed, 0.35, 0.9)
  check("security of claimed systems", average(probe.samples, "security", warm), 0.5, nil)

  -- War.
  local declared = counted("wars declared")
  check("wars declared", declared, 2, nil)
  check("power-time at war (share)", average(probe.samples, "atWar", warm), 0.01, 0.6)
  -- Wars cost ships: what was lost in them, in average navies. (Systems
  -- need not change hands: between equals an invasion is often beaten
  -- off. How many did is shown, and not judged.)
  local navies = average(probe.samples, "navy", 0) / math.max(1, probe.powers)
  check("strength lost in wars (navies)", counted("strength lost in wars") / math.max(1, navies), 0.1, nil)
  check("systems taken or ceded in war", counted("captures") + counted("systems ceded"), 0, nil)
  local over = declared - #world.wars
  check("wars that ended in a peace (share)", if over > 0 then counted("peace treaties") / over else 1, 0.7, nil)
  check("warning of a capture, median minutes", if #world.warnings > 0 then median(world.warnings) else 45, 45, nil)

  -- The economy under them.
  check("needs met, by head", average(probe.samples, "met", warm), 0.88, nil)
  check("price level", average(probe.samples, "priceIndex", warm), 0.85, 1.3)
  check("share through anchors", average(probe.samples, "anchorShare", warm), nil, 0.10)

  -- Pirates.
  check("pirate dens, on average", average(probe.samples, "dens", warm), 1, Powers.DENS_MOST)
  local carried, lost = 0, 0
  for g, class in econ.classes do
    carried += econ.moved[g] * class.par
    lost += econ.lost[g] * class.par
  end
  check("goods lost to pirates (share of trade)", if carried > 0 then lost / carried else 0, 0.0005, 0.02)

  check("ms a tick", tickMs, nil, 5)
  return checks
end

return FactionProbe
