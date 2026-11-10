--!strict
-- The strategic world as a whole: how it starts, where the money goes,
-- order and piracy, and a small galaxy lived through.

local Codec = require("@lt/Core/Persist/Codec")
local Economy = require("@lt/Core/Strategic/Economy")
local Fiscal = require("@lt/Core/Strategic/Fiscal")
local Goods = require("@lt/Core/Data/Goods")
local Ledger = require("@lt/Core/Kernel/Ledger")
local Mind = require("@lt/Core/Strategic/Mind")
local Order = require("@lt/Core/Strategic/Order")
local Powers = require("@lt/Core/Data/Powers")
local Routes = require("@lt/Core/Strategic/Routes")
local Sim = require("@lt/Core/Strategic/Sim")
local Test = require("@lt/Tool/Test")
local World = require("@lt/Core/Strategic/World")

local suite = Test.Suite("Sim")

local function balanced(t: Test.Context, world: World.World)
  t.eq(#Ledger.Reconcile(world.ledger, "credits", World.Wallets(world), 1e-3), 0, "a wallet is off the ledger")
  local econ = world.econ
  for g, residual in Economy.Residual(econ) do
    local through = econ.initial[g] + econ.produced[g] + econ.anchorIn[g] + econ.moved[g]
    t.ok(math.abs(residual) <= 1e-9 * math.max(1, through), `{econ.classes[g].id} leaks`)
  end
end

suite:Case("a new world: each power on its homeworld, dens in the wilds, the books open", function(t)
  local world = Sim.New(7, 60, 1)
  t.eq(#world.factions, 6, "five powers and the pirates")
  t.eq(world.pirates, 6)
  local owned = 0
  for id, s in world.systems do
    if s.owner > 0 then
      owned += 1
      t.eq(world.factions[s.owner].capital, id)
      t.ok(world.atlas.systems[id].home)
      t.eq(s.control, 1)
      t.eq(s.security, 1)
    else
      t.ok(s.security <= Powers.LOCAL_ORDER)
    end
  end
  t.eq(owned, 5)
  local dens = 0
  for id, s in world.systems do
    if s.den then
      dens += 1
      t.eq(world.atlas.systems[id].owner, 0, "beyond every power's natural reach")
      t.eq(World.Holder(world, id), world.pirates)
      t.near(World.StrengthAt(world, id, world.pirates), Powers.BAND, 1e-9)
    end
  end
  t.ok(dens >= 1 and dens <= Powers.DENS)
  for id, faction in world.factions do
    if not faction.pirate then
      t.eq(faction.credits, Powers.STARTING_CREDITS)
      t.eq(World.Navy(world, id), 60)
      t.eq(faction.hops[faction.capital], 0)
      t.eq(faction.relations[world.pirates], -100)
      t.ok(World.Hostile(world, id, world.pirates))
      t.ok(not World.Hostile(world, id, id % 5 + 1), "the powers start at peace")
    end
  end
  -- the founding grants are the only money so far, and are on the books
  t.near(world.ledger.source.credits.founding, 5 * Powers.STARTING_CREDITS + Powers.PIRATE_CREDITS, 1e-9)
  balanced(t, world)
  -- routes: a jump is a jump, both ways
  local routes = Routes.For(world.galaxy)
  for a = 1, 60 do
    for _, b in world.galaxy.systems[a].neighbors do
      t.eq(routes.hops[a][b], 1)
      t.eq(routes.next[a][b], b)
    end
    t.eq(routes.hops[a][1], routes.hops[1][a])
  end
end)

suite:Case("income is the levy on a power's people; holding systems costs as the square of their number", function(t)
  local world = Sim.New(7, 60, 1)
  local faction = world.factions[1]
  local hours = Powers.PERIOD_HOURS
  local people = world.atlas.systems[faction.capital].population
  local levy = Powers.LEVY * Goods.SCALE * people * hours
  local sov = Powers.SOV_BASE * (1 + (1 / Powers.SOV_SCALE) ^ 2) * hours
  local police = Powers.POLICE * (1 + people) * hours
  local crews = 60 * Powers.PAY * hours
  Fiscal.Step(world)
  local flow = world.ledger.flow.credits
  t.near(flow.levy, 5 * levy, 1e-6)
  t.near(flow.sovereignty, 5 * sov, 1e-6)
  t.near(flow.policing, 5 * police, 1e-6)
  t.near(flow.crews, 5 * crews + Powers.BAND * Powers.PAY * hours * world.counters["dens at start"], 1e-6)
  -- supplies were bought at the homeworld's market: fuel and ammunition for an hour's sixth
  t.ok(flow.supply > 0)
  -- (twenty frigates and five cruisers use 55 units an hour)
  t.near(world.econ.bought[Goods.Index("fuel")], 5 * 55 * hours * Powers.SUPPLY_FUEL, 1e-6)
  t.near(faction.credits, Powers.STARTING_CREDITS + levy - sov - police - crews - flow.supply / 5, 1)
  t.near(faction.income, levy / hours, 1e-6)
  t.eq(faction.arrears, 0)
  balanced(t, world)

  t.near(World.SovCost(world, faction, faction.capital, Powers.SOV_SCALE), 2 * Powers.SOV_BASE, 1e-9)
  t.near(World.SovCost(world, faction, faction.capital, 3 * Powers.SOV_SCALE), 10 * Powers.SOV_BASE, 1e-9)
  local far = 0
  for id, hops in faction.hops do
    if hops == 5 then
      far = id
    end
  end
  t.near(World.SovCost(world, faction, far, 0), Powers.SOV_BASE * (1 + 5 * Powers.SOV_DISTANCE), 1e-9)
  -- a system held loosely, or badly supplied, brings in less
  t.near(World.Yield(world, far, 0.5), 0.5 * World.Yield(world, far, 1), 1e-9)
end)

suite:Case("a power that cannot pay lays ships up, scraps nothing, and loses its loosest systems", function(t)
  local world = Sim.New(7, 60, 1)
  local faction = world.factions[1]
  for _, n in world.galaxy.systems[faction.capital].neighbors do
    World.Transfer(world, n, 1)
  end
  local held = faction.systems
  t.ok(held >= 2)
  World.Pay(world, 1, 0, faction.credits + 2000000, "a disaster")
  for _ = 1, Powers.ARREARS_GRACE + 4 do
    world.tick += Powers.PERIOD_TICKS
    Fiscal.Step(world)
    Mind.Budget(world, faction)
  end
  t.ok(faction.arrears > Powers.ARREARS_GRACE)
  t.eq(faction.periodsInArrears, faction.periods)
  local laidUp = 0
  for class, count in faction.reserve do
    laidUp += count * Powers.ships[class].strength
  end
  t.ok(laidUp >= 30, `{laidUp} laid up`)
  t.eq(World.Navy(world, 1) + laidUp, 60, "not a ship scrapped")
  t.ok(faction.systems < held, "and systems were lost")
  t.eq(world.systems[faction.capital].owner, 1, "never the capital")
  t.ok((world.counters["systems lost to arrears"] or 0) + (world.counters["systems given up"] or 0) >= 1)
  balanced(t, world)
end)

suite:Case("piracy gathers round a den and is pushed down by policing; safety and the lanes follow", function(t)
  local world = Sim.New(7, 60, 1)
  local faction = world.factions[1]
  local den = 0
  for id, s in world.systems do
    if s.den then
      den = id
    end
  end
  for _ = 1, 60 do
    world.tick += Powers.PERIOD_TICKS
    Order.Step(world)
  end
  Order.Lanes(world)
  local home = world.systems[faction.capital]
  local beside = world.systems[world.galaxy.systems[den].neighbors[1]]
  t.ok(world.systems[den].pressure > 0.9)
  t.ok(beside.pressure > 0.3, "it spreads to the den's neighbours")
  t.ok(home.pressure < 0.1 and home.security > 0.9, "a policed homeworld is safe")
  t.ok(world.systems[den].security < 0.5 * Powers.LOCAL_ORDER + 0.01)
  -- the lanes: dearer and leakier at the den than at home
  local atDen, atHome
  for at, lane in world.atlas.lanes do
    if lane.a == den or lane.b == den then
      atDen = world.econ.edges[at]
    elseif lane.a == faction.capital or lane.b == faction.capital then
      atHome = world.econ.edges[at]
    end
  end
  t.ok(atDen.cost > atHome.cost)
  t.ok(atDen.loss > 0.9 * Powers.THEFT and atHome.loss < 0.5 * Powers.THEFT)
  t.ok(atDen.conductance < atHome.conductance or atDen.conductance < world.atlas.lanes[1].conductance * 10)

  -- without policing, piracy creeps in even at home
  faction.policing = 0
  local before = home.pressure
  for _ = 1, 60 do
    Order.Step(world)
  end
  t.ok(home.pressure > before)
end)

suite:Case("war, an embargo and a siege each close the lanes they should", function(t)
  local world = Sim.New(7, 60, 1)
  local a = world.factions[1]
  -- give the second power the system next to the first's capital
  local beside = world.galaxy.systems[a.capital].neighbors[1]
  World.Transfer(world, beside, 2)
  local border = 0
  for at, lane in world.atlas.lanes do
    if (lane.a == a.capital and lane.b == beside) or (lane.b == a.capital and lane.a == beside) then
      border = at
    end
  end
  local edge = world.econ.edges[border]
  Order.Lanes(world)
  t.ok(edge.open)
  t.ok(edge.cost >= 0.02 + 0.04, "a border costs more to cross")
  a.stance[2] = 1
  Order.Lanes(world)
  t.ok(not edge.open, "embargo")
  a.stance[2] = 0
  table.insert(world.wars, { a = 1, b = 2, since = 0, startA = 1, startB = 1, lostA = 0, lostB = 0, takenA = 0, takenB = 0,
    coalition = false })
  Order.Lanes(world)
  t.ok(not edge.open, "war")
  table.remove(world.wars)
  Order.Lanes(world)
  t.ok(edge.open)
  -- a siege cuts every lane of the system
  world.systems[beside].siege = { by = 1, kind = "siege", since = 0, planned = 0, progress = 0, stage = "blockade" }
  Order.Lanes(world)
  for at, lane in world.atlas.lanes do
    if lane.a == beside or lane.b == beside then
      t.ok(not world.econ.edges[at].open)
    end
  end
end)

suite:Case("a small galaxy lives three days: the powers grow, pay their way, and the books balance", function(t)
  local world = Sim.New(5, 60, 2)
  for _ = 1, 3 * 24 * 360 do
    Sim.Tick(world)
  end
  balanced(t, world)
  local owned = 0
  for _, s in world.systems do
    if s.owner > 0 then
      owned += 1
      t.ok(s.control > 0 and s.control <= 1)
    end
    t.ok(s.pressure >= 0 and s.pressure <= 1 and s.security >= 0 and s.security <= 1)
  end
  t.ok(owned >= 15, `{owned} systems claimed`)
  t.ok(world.counters["claims"] >= 10)
  for id, faction in world.factions do
    if not faction.pirate then
      t.ok(faction.alive)
      t.ok(faction.credits == faction.credits and faction.credits > 0, `{faction.name} has {faction.credits}`)
      t.eq(faction.periodsInArrears, 0)
      t.ok(World.Navy(world, id) > 60, "the fleet has grown")
      t.ok(faction.income > faction.costs * 0.8)
    end
  end
  -- every fleet is somewhere, and every system knows who is in it
  local present = 0
  for id, s in world.systems do
    for _, fid in s.fleets do
      t.eq(world.fleets[fid].system, id)
      present += 1
    end
  end
  local inSystems = 0
  for _, fid in world.fleetIds do
    if world.fleets[fid].system > 0 then
      inSystems += 1
    end
  end
  t.eq(present, inSystems)
end)

suite:Case("saving and loading in mid-history changes nothing", function(t)
  local memory = Sim.New(5, 60, 3)
  local reloaded = Sim.New(5, 60, 3)
  t.eq(Codec.HashOf(memory), Codec.HashOf(reloaded))
  for _ = 1, 6000 do
    Sim.Tick(memory)
    Sim.Tick(reloaded)
    if memory.tick % 97 == 0 then
      local data, length = Codec.Encode(reloaded)
      reloaded = Codec.Decode(data, length)
    end
  end
  t.eq(Codec.HashOf(memory), Codec.HashOf(reloaded))
  -- and another history really is another
  local other = Sim.New(5, 60, 4)
  for _ = 1, 6000 do
    Sim.Tick(other)
  end
  t.ok(Codec.HashOf(other) ~= Codec.HashOf(memory))
end)

return suite
