--!strict
-- Fleets on the move, battles and sieges, on a small galaxy.

local Battle = require("@lt/Core/Strategic/Battle")
local Diplomacy = require("@lt/Core/Strategic/Diplomacy")
local Ledger = require("@lt/Core/Kernel/Ledger")
local Economy = require("@lt/Core/Strategic/Economy")
local Orders = require("@lt/Core/Strategic/Orders")
local Powers = require("@lt/Core/Data/Powers")
local Routes = require("@lt/Core/Strategic/Routes")
local Sim = require("@lt/Core/Strategic/Sim")
local Test = require("@lt/Tool/Test")
local World = require("@lt/Core/Strategic/World")

local suite = Test.Suite("Battle")

local function ships(frigates: number, cruisers: number?, battleships: number?): { number }
  return { frigates, cruisers or 0, battleships or 0 }
end

-- A minute of fighting and siege, with nothing else going on.
local function minutes(world: World.World, n: number)
  for _ = 1, n do
    world.tick += Powers.ROUND_TICKS
    Battle.Round(world)
    Battle.Sieges(world)
  end
end

-- Run the timers only (fleets in flight), a tick at a time.
local function fly(world: World.World, ticks: number)
  for _ = 1, ticks do
    world.tick += 1
    for _, id in World.PopDue(world, world.tick) do
      local action = world.actions[id]
      if action and action.kind == "move" then
        Orders.Jumped(world, action)
      end
    end
  end
end

-- A system some way from a power's capital, and the route's length.
local function farFrom(world: World.World, capital: number, least: number): number
  local routes = Routes.For(world.galaxy)
  for id in world.systems do
    if routes.hops[capital][id] == least then
      return id
    end
  end
  error("no system that far")
end

suite:Case("a fleet takes a minute a jump and stops where it was sent", function(t)
  local world = Sim.New(7, 60, 1)
  local faction = world.factions[1]
  local dest = farFrom(world, faction.capital, 3)
  local fleet = World.NewFleet(world, 1, faction.capital, ships(5))
  t.ok(Orders.Move(world, fleet, dest, "home"))
  t.eq(fleet.system, 0)
  t.ok(not Orders.Move(world, fleet, faction.capital, "home"), "it is under way")
  fly(world, 3 * Powers.JUMP_TICKS - 1)
  t.eq(fleet.system, 0)
  fly(world, 1)
  t.eq(fleet.system, dest)
  t.eq(fleet.action, 0)
  t.eq(#world.actionIds, 0)
end)

suite:Case("nobody slips past an enemy fleet, and a halted fleet stops at the next system", function(t)
  local world = Sim.New(7, 60, 1)
  local a, b = world.factions[1], world.factions[2]
  local routes = Routes.For(world.galaxy)
  local dest = farFrom(world, a.capital, 4)
  local second = routes.next[routes.next[a.capital][dest]][dest]
  t.ok(Diplomacy.Declare(world, a, b, false))
  World.NewFleet(world, 2, second, ships(10))
  local fleet = World.NewFleet(world, 1, a.capital, ships(20))
  Orders.Move(world, fleet, dest, "home")
  fly(world, 60)
  t.eq(fleet.system, second, "stopped by the enemy")
  t.eq(fleet.target, dest, "and still means to go on")

  local free = World.NewFleet(world, 1, a.capital, ships(3))
  Orders.Move(world, free, dest, "home")
  fly(world, 2)
  t.ok(Orders.Halt(world, free))
  fly(world, 60)
  t.eq(free.system, routes.next[a.capital][dest])
end)

suite:Case("the larger fleet wins by more than its numbers, and the loser pulls out under half", function(t)
  local world = Sim.New(7, 60, 1)
  local a, b = world.factions[1], world.factions[2]
  Diplomacy.Declare(world, a, b, false)
  -- on neutral ground, so that nobody's defences join in
  local ground = farFrom(world, a.capital, 3)
  t.eq(world.systems[ground].owner, 0)
  local big = World.NewFleet(world, 1, ground, ships(120))
  local small = World.NewFleet(world, 2, ground, ships(100))
  local rounds = 0
  while small.system == ground and world.fleets[small.id] and rounds < 100 do
    minutes(world, 1)
    rounds += 1
  end
  t.ok(rounds >= 5 and rounds < 40, `it took {rounds} rounds`)
  local left, leftSmall = World.Strength(big), if world.fleets[small.id] then World.Strength(small) else 0
  -- 120 against 100 by the square law ends near 77 against 38
  t.ok(left > 60 and left < 95, `the winner has {left}`)
  t.ok(leftSmall < 0.5 * left + 6, `the loser has {leftSmall}`)
  t.ok(120 - left < 100 - leftSmall, "the winner lost fewer")
  local war = assert(World.WarBetween(world, 1, 2))
  t.near(war.lostA, 120 - left, 1e-6)
  t.ok(world.systems[ground].fighting > 0)
  minutes(world, 2)
  t.eq(world.systems[ground].fighting, 0, "quiet once one side has gone")
end)

suite:Case("a siege takes an hour, in stages, and the system changes hands", function(t)
  local world = Sim.New(7, 60, 1)
  local a, b = world.factions[1], world.factions[2]
  local target = world.galaxy.systems[b.capital].neighbors[1]
  World.Transfer(world, target, 2)
  world.systems[target].control = 1
  Diplomacy.Declare(world, a, b, false)
  local fleet = World.NewFleet(world, 1, target, ships(120))
  local planned = world.tick
  world.tick += 120
  t.ok(Battle.Besiege(world, fleet, "siege", planned))
  local siege = assert(world.systems[target].siege)
  t.eq(siege.stage, "blockade")
  local before = World.Strength(fleet)
  minutes(world, 9)
  t.eq(siege.stage, "blockade")
  t.eq(world.systems[target].defence, 1, "nothing is fired during the blockade")
  minutes(world, 2)
  t.eq(siege.stage, "assault")
  minutes(world, 28)
  t.ok(world.systems[target].defence <= Powers.DEFENCE_BEATEN)
  t.ok(World.Strength(fleet) < before, "the defences cost the besiegers ships")
  minutes(world, 2)
  t.eq(siege.stage, "occupy")
  minutes(world, 18)
  t.eq(world.systems[target].owner, 2)
  minutes(world, 3)
  t.eq(world.systems[target].owner, 1)
  t.eq(world.systems[target].siege, nil)
  t.near(world.systems[target].control, Powers.CONTROL_NEW, 1e-9)
  t.eq(fleet.task, "hold")
  -- the warning: from the plan to the fall, in minutes
  t.eq(#world.warnings, 1)
  t.ok(world.warnings[1] >= 80 and world.warnings[1] <= 84, `{world.warnings[1]} minutes`)
  local war = assert(World.WarBetween(world, 1, 2))
  t.near(war.takenA, world.atlas.systems[target].population, 1e-9)
  t.ok(Diplomacy.Score(world, war) > 0)
end)

suite:Case("a siege waits while it is contested and ends when the besiegers go", function(t)
  local world = Sim.New(7, 60, 1)
  local a, b = world.factions[1], world.factions[2]
  local target = world.galaxy.systems[b.capital].neighbors[1]
  World.Transfer(world, target, 2)
  Diplomacy.Declare(world, a, b, false)
  local fleet = World.NewFleet(world, 1, target, ships(0, 30))
  Battle.Besiege(world, fleet, "siege")
  minutes(world, 5)
  local siege = assert(world.systems[target].siege)
  t.eq(siege.progress, 30)
  -- a relief force too small to win still stops the clock while it lasts
  local relief = World.NewFleet(world, 2, target, ships(0, 20))
  minutes(world, 1)
  t.eq(siege.progress, 30)
  t.ok(world.systems[target].defence < 1, "the defences fight beside their fleet")
  -- beaten off, the siege goes on, then the besiegers leave
  while world.fleets[relief.id] and relief.system == target do
    minutes(world, 1)
  end
  minutes(world, 2)
  t.ok(siege.progress > 30)
  World.Disband(world, fleet)
  minutes(world, 1)
  t.eq(world.systems[target].siege, nil)
  t.eq(world.systems[target].owner, 2)
end)

suite:Case("an independent system is claimed with kits, and not without", function(t)
  local world = Sim.New(7, 60, 1)
  local a = world.factions[1]
  local target = world.galaxy.systems[a.capital].neighbors[1]
  t.eq(world.systems[target].owner, 0)
  local need = Orders.ClaimKits(world, target)
  local fleet = World.NewFleet(world, 1, a.capital, ships(0, 12))
  t.near(Orders.BuyKits(world, fleet, need), need, 1e-9)
  t.ok(a.credits < Powers.STARTING_CREDITS, "the kits were paid for")
  fleet.kits = need - 1
  World.Leave(world, fleet)
  World.Arrive(world, fleet, target)
  t.ok(Battle.Besiege(world, fleet, "claim"))
  minutes(world, 30)
  t.eq(world.systems[target].owner, 0, "one kit short")
  fleet.kits = need
  minutes(world, 1)
  t.eq(world.systems[target].owner, 1)
  t.near(fleet.kits, 0, 1e-9)
  t.eq(a.systems, 2)
  t.eq(#world.warnings, 0, "a claim is not a capture")
end)

suite:Case("a raid takes what the band can carry, and the books show it", function(t)
  local world = Sim.New(7, 60, 1)
  local pirates = world.factions[world.pirates]
  local target = world.galaxy.systems[world.factions[1].capital].neighbors[1]
  local band = World.NewFleet(world, pirates.id, target, ships(20))
  local before = pirates.credits
  t.ok(Battle.Besiege(world, band, "raid"))
  minutes(world, 12)
  t.eq(world.systems[target].siege, nil)
  t.eq(world.counters["raids"], 1)
  local value = world.counters["raided value"]
  t.ok(value > 0 and value <= Powers.RAID_HAUL * 20 + 1e-6, `took {value}`)
  t.near(pirates.credits - before, Powers.FENCE * value, 1e-6)
  t.near(world.loot, value, 1e-6)
  t.eq(band.task, "home")
  t.ok(world.systems[target].pressure >= Powers.RAID_PRESSURE)
  -- nothing appeared or vanished outside the books
  t.eq(#Ledger.Reconcile(world.ledger, "credits", World.Wallets(world), 1e-6), 0)
  for _, residual in Economy.Residual(world.econ) do
    t.near(residual, 0, 1e-6)
  end
end)

suite:Case("ships are bought on the capital's market, laid up and brought back", function(t)
  local world = Sim.New(7, 60, 1)
  local a = world.factions[1]
  local price = assert(Orders.ShipPrice(world, a.capital, 2))
  t.ok(price > 60000, "a cruiser is its hull and its fittings")
  local before = a.credits
  t.ok(Orders.Build(world, a, 2))
  t.ok(before - a.credits >= price - 1e-6, "paid at the market's price")
  t.eq(Orders.Building(world, 1), 1)
  local navy = World.Navy(world, 1)
  for _ = 1, Powers.ships[2].buildTicks do
    world.tick += 1
    for _, id in World.PopDue(world, world.tick) do
      Orders.Launched(world, world.actions[id])
    end
  end
  t.eq(World.Navy(world, 1), navy + 8)
  a.credits = 100
  local ok, why = Orders.Build(world, a, 3)
  t.ok(not ok and why == "not enough credits")

  local fleet = world.fleets[world.systems[a.capital].fleets[1]]
  t.ok(Orders.Mothball(world, fleet, ships(10, 2)))
  t.eq(a.reserve, ships(10, 2))
  t.eq(World.Navy(world, 1), navy + 8 - 26)
  a.credits = 50000
  t.ok(Orders.Reactivate(world, a, 2, 2))
  t.eq(a.reserve, ships(10, 0))
  t.ok(a.credits < 50000, "bringing ships back costs a share of their price")
end)

return suite
