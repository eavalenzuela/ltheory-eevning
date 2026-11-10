--!strict
-- War and peace between the powers, on a small galaxy.

local Diplomacy = require("@lt/Core/Strategic/Diplomacy")
local Ledger = require("@lt/Core/Kernel/Ledger")
local Powers = require("@lt/Core/Data/Powers")
local Sim = require("@lt/Core/Strategic/Sim")
local Test = require("@lt/Tool/Test")
local World = require("@lt/Core/Strategic/World")

local suite = Test.Suite("Diplomacy")

local WHITE: Diplomacy.Terms = { loser = 0, winner = 0, pays = 0, cedes = {} }

-- Give 'owner' the systems next to another power's capital, so that the
-- two share a border. Returns them.
local function settleBeside(world: World.World, owner: number, capital: number): { number }
  local taken: { number } = {}
  for _, n in world.galaxy.systems[capital].neighbors do
    if world.systems[n].owner == 0 then
      World.Transfer(world, n, owner)
      table.insert(taken, n)
    end
  end
  return taken
end

suite:Case("a power may declare one war a day, and none during a truce", function(t)
  local world = Sim.New(7, 60, 1)
  local a, b, c = world.factions[1], world.factions[2], world.factions[3]
  t.ok(Diplomacy.CanDeclare(world, a, b))
  local ok, why = Diplomacy.CanDeclare(world, a, world.factions[world.pirates])
  t.ok(not ok and why == "no such war")
  t.ok(Diplomacy.Declare(world, a, b, false))
  t.ok(World.Hostile(world, 1, 2) and World.Hostile(world, 2, 1))
  t.ok(a.relations[2] <= Powers.WAR_BELOW and b.relations[1] == a.relations[2])
  ok, why = Diplomacy.CanDeclare(world, a, b)
  t.ok(not ok and why == "already at war")
  ok, why = Diplomacy.CanDeclare(world, a, c)
  t.ok(not ok and why == "it declared a war within the day")
  t.ok(Diplomacy.CanDeclare(world, c, a), "the cooldown is the declarer's own")
  world.tick += Powers.WAR_COOLDOWN
  t.ok(Diplomacy.CanDeclare(world, a, c))

  Diplomacy.MakePeace(world, assert(World.WarBetween(world, 1, 2)), WHITE)
  t.ok(not World.Hostile(world, 1, 2))
  t.eq(a.relations[2], Powers.AFTER_PEACE)
  ok, why = Diplomacy.CanDeclare(world, a, b)
  t.ok(not ok and why == "a truce holds")
  ok, why = Diplomacy.CanDeclare(world, a, c)
  t.ok(not ok and why == "one of its wars ended within the day")
  world.tick += Powers.TRUCE
  t.ok(Diplomacy.CanDeclare(world, b, a))
  t.eq(world.counters["peace treaties"], 1)
end)

suite:Case("the score follows what is taken and lost, and the terms follow the score", function(t)
  local world = Sim.New(7, 60, 1)
  local a, b = world.factions[1], world.factions[2]
  local border = settleBeside(world, 2, a.capital)
  t.ok(#border >= 1)
  Diplomacy.Declare(world, a, b, false)
  local war = assert(World.WarBetween(world, 1, 2))
  t.eq(Diplomacy.Score(world, war), 0)
  t.eq(Diplomacy.Terms(world, war).loser, 0, "level: no terms")

  -- The declarer destroys half the other's fleet for a tenth of its own.
  war.lostB, war.lostA = 0.5 * war.startB, 0.1 * war.startA
  t.near(Diplomacy.Score(world, war), 0.5 * 0.4, 1e-9)
  -- And takes territory worth most of what the war is measured against.
  local reference = 0.5 * math.min(Diplomacy.Worth(world, 1), Diplomacy.Worth(world, 2))
  war.takenA = 0.6 * reference
  local score = Diplomacy.Score(world, war)
  t.ok(score > 0.6 and score <= 1, `score {score}`)
  local terms = Diplomacy.Terms(world, war)
  t.eq(terms.loser, 2)
  t.eq(terms.winner, 1)
  t.near(terms.pays, Powers.REPARATIONS * score * b.credits, 1e-6)
  t.ok(#terms.cedes >= 1 and #terms.cedes <= Powers.CEDED_MOST)
  for _, id in terms.cedes do
    t.eq(world.systems[id].owner, 2)
    t.ok(id ~= b.capital, "never the capital")
  end
  -- What the winner gains the loser loses.
  t.ok(Diplomacy.Value(world, war, 1, terms) > 0)
  t.near(Diplomacy.Value(world, war, 1, terms), -Diplomacy.Value(world, war, 2, terms), 1e-9)
  t.eq(Diplomacy.Value(world, war, 3, terms), 0)
end)

suite:Case("a side signs when the terms beat fighting on: sooner the wearier it is", function(t)
  local world = Sim.New(7, 60, 1)
  local a, b = world.factions[1], world.factions[2]
  settleBeside(world, 2, a.capital)
  Diplomacy.Declare(world, a, b, false)
  local war = assert(World.WarBetween(world, 1, 2))
  -- Fresh and level: neither will sign a peace with no terms.
  t.ok(not Diplomacy.Accepts(world, war, a, WHITE))
  t.ok(not Diplomacy.Accepts(world, war, b, WHITE))
  t.near(Diplomacy.Weariness(world, war, a), 0, 1e-9)
  -- Half the longest war later, both will.
  world.tick += Powers.WAR_LONGEST / 2
  t.near(Diplomacy.Weariness(world, war, a), 0.5, 1e-9)
  t.ok(Diplomacy.Accepts(world, war, a, WHITE) and Diplomacy.Accepts(world, war, b, WHITE))
  world.tick -= Powers.WAR_LONGEST / 2

  -- The declarer well ahead and fresh: it will not take a peace with no
  -- terms, which the loser would be glad of.
  war.lostB = 0.8 * war.startB
  t.ok(Diplomacy.Score(world, war) > 0.3)
  t.ok(not Diplomacy.Accepts(world, war, a, WHITE))
  t.ok(Diplomacy.Accepts(world, war, b, WHITE))
  -- An empty treasury makes anyone readier.
  local before = Diplomacy.Weariness(world, war, a)
  a.arrears = 1
  t.near(Diplomacy.Weariness(world, war, a), before + 0.5, 1e-9)
end)

suite:Case("peace hands over what the terms say, and leaves a grudge and a truce", function(t)
  local world = Sim.New(7, 60, 1)
  local a, b = world.factions[1], world.factions[2]
  local border = settleBeside(world, 2, a.capital)
  Diplomacy.Declare(world, a, b, false)
  local war = assert(World.WarBetween(world, 1, 2))
  local usual = a.baseline[2]
  local credits = a.credits
  local terms: Diplomacy.Terms = { loser = 2, winner = 1, pays = 40000, cedes = { border[1] } }
  Diplomacy.MakePeace(world, war, terms)
  t.eq(world.systems[border[1]].owner, 1)
  t.near(a.credits, credits + 40000, 1e-9)
  t.near(world.ledger.flow.credits.reparations, 40000, 1e-9)
  t.eq(#Ledger.Reconcile(world.ledger, "credits", World.Wallets(world), 1e-6), 0)
  t.eq(#world.wars, 0)
  t.near(a.baseline[2], usual - Powers.GRUDGE, 1e-9)
  t.eq(a.relations[2], Powers.AFTER_PEACE)
  -- the side that gained must leave the other alone for longer
  t.eq(b.truce[1], world.tick + Powers.TRUCE)
  t.eq(a.truce[2], world.tick + Powers.TRUCE_WON)
  -- and the grudge fades
  for _ = 1, 6 * 24 * 10 do
    world.tick += Powers.PERIOD_TICKS
    Diplomacy.Step(world)
  end
  t.ok(a.baseline[2] > usual - 0.5 * Powers.GRUDGE)
end)

suite:Case("an oversized aggressor is embargoed, its victim subsidised, and a coalition forms", function(t)
  local world = Sim.New(7, 60, 1)
  local a, b = world.factions[1], world.factions[2]
  -- A fleet far beyond anyone's, and a war against a neighbour.
  World.NewFleet(world, 1, a.capital, { 0, 0, 60 })
  for _, faction in world.factions do
    faction.income = 20000
  end
  Diplomacy.Declare(world, a, b, false)
  local sawEmbargo, sawSubsidy = false, false
  for _ = 1, 6 * 12 do
    world.tick += Powers.PERIOD_TICKS
    Diplomacy.Step(world)
    for id = 3, world.pirates - 1 do
      sawEmbargo = sawEmbargo or world.factions[id].stance[1] >= 1
      sawSubsidy = sawSubsidy or world.factions[id].stance[1] >= 2
    end
    if (world.counters["coalition wars"] or 0) > 0 then
      break
    end
  end
  t.ok(sawEmbargo, "borders were closed to it")
  t.ok(sawSubsidy and (world.counters["subsidy periods"] or 0) > 0, "its victim was paid")
  t.ok((world.counters["coalition wars"] or 0) >= 1, "someone joined the war")
  t.ok(world.ledger.flow.credits.subsidy > 0)
  t.eq(#Ledger.Reconcile(world.ledger, "credits", World.Wallets(world), 1e-6), 0)
  -- a war between equals frightens nobody
  local calm = Sim.New(7, 60, 1)
  Diplomacy.Declare(calm, calm.factions[1], calm.factions[2], false)
  local before = calm.factions[3].relations[1]
  for _ = 1, 12 do
    calm.tick += Powers.PERIOD_TICKS
    Diplomacy.Step(calm)
  end
  t.ok(math.abs(calm.factions[3].relations[1] - before) < 5)
  t.eq(calm.counters["embargoes"], nil)
end)

suite:Case("neighbours quarrel at random: the same in the same history, different in another", function(t)
  local function relationAfter(history: number): number
    local world = Sim.New(7, 60, history)
    settleBeside(world, 2, world.factions[1].capital)
    for _ = 1, 60 do
      world.tick += Powers.PERIOD_TICKS
      Diplomacy.Step(world)
    end
    return world.factions[1].relations[2]
  end
  local first = relationAfter(1)
  t.eq(relationAfter(1), first)
  t.ok(relationAfter(2) ~= first)
  -- powers that do not touch have no incidents
  local apart = Sim.New(7, 60, 1)
  local other = Sim.New(7, 60, 2)
  for _ = 1, 30 do
    apart.tick += Powers.PERIOD_TICKS
    other.tick += Powers.PERIOD_TICKS
    Diplomacy.Step(apart)
    Diplomacy.Step(other)
  end
  t.eq(apart.factions[1].relations[2], other.factions[1].relations[2])
end)

return suite
