--!strict
-- The galaxy's economy in the real bulk goods (Strategic/Commerce), and
-- the station markets that deal with it (Assets/Market).

local Codec = require("@lt/Core/Persist/Codec")
local Commerce = require("@lt/Core/Strategic/Commerce")
local Core = require("@lt/Core/Api")
local Economy = require("@lt/Core/Strategic/Economy")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Market = require("@lt/Core/Assets/Market")
local Space = require("@lt/Core/Tactical/Space")
local Test = require("@lt/Tool/Test")
local Types = require("@lt/Core/Data/Types")

local suite = Test.Suite("Commerce")

local SYSTEMS = 40

suite:Case("the goods are the real bulk materials, and what is built is known by what it is built of", function(t)
  t.ok(#Commerce.goods >= 40 and #Commerce.goods <= 60, `{#Commerce.goods} goods`)
  local kinds: { [string]: number } = {}
  for class, id in Commerce.goods do
    local info = Types.Info(id)
    kinds[info.category] = (kinds[info.category] or 0) + 1
    t.eq(Commerce.Index(id), class)
    t.eq(#Commerce.Bill(id), 0, `{id} is one of the goods, and is built of itself`)
  end
  t.eq({ kinds.ore, kinds.mineral, kinds.component, kinds.moon } :: { any }, { 6, 6, 8, 9 } :: { any })
  t.ok(Commerce.Index("fuel.block") ~= nil and Commerce.Index("gas.amber") ~= nil and Commerce.Index("planet.alloys") ~= nil)
  -- (not what is built, nor what nobody hauls)
  for _, id in { "frigate.courier", "autocannon.small", "ammo.emp", "raw.metals", "datacore", "skillbook.mining" } do
    t.eq(Commerce.Index(id), nil, id)
  end
  -- A hull is built of minerals and components, through its blueprint: so much of each, and the shares come to all of it.
  local bill = Commerce.Bill("frigate.courier")
  t.ok(#bill >= 3, `a frigate is built of {#bill} goods`)
  local shares, minerals, components = 0, 0, 0
  for _, part in bill do
    shares += part.share
    t.ok(part.amount > 0 and part.share > 0)
    local category = Types.Info(Commerce.goods[part.class]).category
    minerals += if category == "mineral" then 1 else 0
    components += if category == "component" then 1 else 0
  end
  t.near(shares, 1, 1e-9)
  t.ok(minerals >= 1 and components >= 1, "a hull should take minerals and components")
  t.eq(#Commerce.Bill("skillbook.mining"), 0)
end)

suite:Case("a galaxy's economy: a system a node, a gate a lane, industry enough, and prices that differ across the map", function(t)
  local galaxy = Galaxy.Describe(1, SYSTEMS)
  Galaxy.Deepen(galaxy)
  local econ = Commerce.New(galaxy)
  -- (the map's systems, and not uncharted space)
  t.eq({ #econ.nodes, #econ.classes }, { SYSTEMS, #Commerce.goods })
  local gates = 0
  for id = 1, SYSTEMS do
    gates += #galaxy.systems[id].neighbors
    t.eq(econ.nodes[id].name, galaxy.systems[id].name)
  end
  t.eq(#econ.edges, gates / 2)
  -- On the day it is made every price is the normal one, everywhere.
  for id = 1, SYSTEMS do
    for class = 1, #econ.classes do
      t.near(Economy.Price(econ, id, class) / econ.classes[class].par, 1, 1e-9)
    end
    t.eq(Commerce.Level(econ, id, "frigate.courier"), 1)
  end
  -- A homeworld has more people than anywhere, and deals with the world beyond; nowhere else does.
  local most = 0
  for id = 1, SYSTEMS do
    most = math.max(most, econ.nodes[id].population)
    local anchored = 0
    for class = 1, #econ.classes do
      anchored += if econ.nodes[id].anchor[class] > 0 then 1 else 0
    end
    t.eq(anchored, if galaxy.systems[id].home then #econ.classes else 0, `system {id}`)
  end
  t.eq(econ.nodes[1].population, most)
  -- Twenty days of it.
  for _ = 1, 20 * 144 do
    Commerce.Advance(econ, galaxy, 0, Commerce.STEP)
  end
  for class, residual in Economy.Residual(econ) do
    t.ok(math.abs(residual) * econ.classes[class].par < 1, `the books are out by {residual} of {econ.classes[class].id}`)
  end
  t.ok(Economy.AnchorShare(econ) < 0.15, `{math.floor(100 * Economy.AnchorShare(econ))}% of everything came from beyond`)
  local met, pinned, apart = 0, 0, 0
  for id = 1, SYSTEMS do
    met += econ.nodes[id].met / SYSTEMS
  end
  for class = 1, #econ.classes do
    local low, high = math.huge, 0
    for id = 1, SYSTEMS do
      local ratio = Economy.Price(econ, id, class) / econ.classes[class].par
      low, high = math.min(low, ratio), math.max(high, ratio)
      pinned += if ratio <= 0.2501 or ratio >= 3.999 then 1 else 0
    end
    apart += if high / low > 1.15 then 1 else 0
  end
  t.ok(met > 0.9, `people's needs were {math.floor(100 * met)}% met`)
  t.eq(pinned, 0, "a price is pinned at the floor or the ceiling")
  t.ok(apart >= 6, `only {apart} goods are 15% dearer somewhere than somewhere else`)
  -- (and it is the same economy every time)
  local again = Commerce.New(galaxy)
  for _ = 1, 20 * 144 do
    Commerce.Advance(again, galaxy, 0, Commerce.STEP)
  end
  t.eq(Codec.HashOf(again), Codec.HashOf(econ))
end)

suite:Case("carrying costs more where order is thin, and a great deal more into a system where pirates are massing", function(t)
  local galaxy = Galaxy.Describe(1, SYSTEMS)
  local econ = Commerce.New(galaxy)
  local safest, wildest = math.huge, 0
  for _, edge in econ.edges do
    local least = math.min(galaxy.systems[edge.a].security, galaxy.systems[edge.b].security)
    t.near(edge.cost, Commerce.COST_JUMP + Commerce.COST_RISK * (1 - least), 1e-9)
    t.eq(edge.loss, if Galaxy.Band(least) == "lawless" then Commerce.LOSS else 0)
    safest, wildest = math.min(safest, edge.cost), math.max(wildest, edge.cost)
  end
  t.ok(wildest > 2 * safest, "a lane through lawless space should cost a good deal more")
  local edge = econ.edges[1]
  local before = edge.cost
  Commerce.Lanes(econ, galaxy, edge.a)
  t.near(edge.cost, before + Commerce.SURGE_COST, 1e-9)
  t.eq(edge.loss, Commerce.SURGE_LOSS)
  for _, other in econ.edges do
    if other.a ~= edge.a and other.b ~= edge.a then
      t.ok(other.cost < Commerce.SURGE_COST, "a lane nowhere near the surge costs more")
    end
  end
  Commerce.Lanes(econ, galaxy, 0)
  t.near(edge.cost, before, 1e-9)
end)

suite:Case("a thing goes for what its system makes of it: the goods by their stock, and what is built by its materials", function(t)
  local galaxy = Galaxy.Describe(1, SYSTEMS)
  Galaxy.Deepen(galaxy)
  local econ = Commerce.New(galaxy)
  local iron = assert(Commerce.Index("mineral.iron"))
  local node = econ.nodes[2]
  Economy.SetStock(econ, 2, iron, node.target[iron] / 2)
  t.near(Commerce.Level(econ, 2, "mineral.iron"), 2, 1e-9)
  t.eq(Commerce.Level(econ, 3, "mineral.iron"), 1)
  -- (a hull that takes iron is dearer there, by the part of it that is iron and no more)
  local share = 0
  for _, part in Commerce.Bill("frigate.courier") do
    share += if part.class == iron then part.share else 0
  end
  t.ok(share > 0, "a Courier takes no iron")
  t.near(Commerce.Level(econ, 2, "frigate.courier"), 1 + Commerce.MATERIALS * share, 1e-9)
  -- (what is built of nothing the economy stocks is unmoved, and so is anything in uncharted space)
  t.eq(Commerce.Level(econ, 2, "skillbook.mining"), 1)
  t.eq(Commerce.Level(econ, SYSTEMS + 1, "mineral.iron"), 1)
  t.eq(Commerce.Level(nil, 2, "mineral.iron"), 1)
end)

suite:Case("a station's market deals with its system: its prices follow the system's, and what it is sold ends up there", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, systems = SYSTEMS, peaceful = true })
  local state = game.state
  local home = state.player.home
  local system = Space.SystemOf(state, home)
  local ferrite = assert(Commerce.Index("ore.ferrite"))
  local normal = Core.Query.Quote(game, home, "ore.ferrite").bid
  local hull = Core.Query.Quote(game, home, "frigate.courier").bid
  -- The system runs short of ferrite: the station pays more for it at the next reckoning, and nothing more for a hull (which takes none).
  local node = state.commerce.nodes[system]
  Economy.SetStock(state.commerce, system, ferrite, node.target[ferrite] / 1.5)
  Market.Peg(state)
  t.near(Core.Query.Quote(game, home, "ore.ferrite").bid / normal, 1.5, 0.01)
  t.near(Core.Query.Quote(game, home, "frigate.courier").bid / hull, 1, 1e-6)
  Economy.SetStock(state.commerce, system, ferrite, node.target[ferrite])
  Market.Peg(state)
  t.near(Core.Query.Quote(game, home, "ore.ferrite").bid / normal, 1, 1e-6)
  -- A great deal of ore sold at the station: the station has it at
  -- first, and over a day and more it is the system's.
  local before = node.stock[ferrite]
  local lot = 400000
  local ore = Items.Add(state, "ore.ferrite", lot, home, "hangar")
  assert(Core.Submit(game, { kind = "SellNow", actor = state.player.ship, item = ore.id, quantity = lot }))
  Core.Step(game)
  t.eq(node.stock[ferrite], before)
  t.ok(Core.Query.Quote(game, home, "ore.ferrite").bid < 0.8 * normal, "so much ore should have brought the station's price down")
  for _ = 1, 36 * 3600 do
    Core.Step(game)
  end
  -- (what the system makes and uses of ferrite in a day and a half has gone on too: so against a game in which nothing was sold)
  local idle = Core.New({ galaxySeed = 1, historySeed = 1, systems = SYSTEMS, peaceful = true })
  Core.Query.Quote(idle, home, "ore.ferrite")
  for _ = 1, 36 * 3600 do
    Core.Step(idle)
  end
  -- (by the economy's books: what the markets have given it, less what
  -- they have had of it. It does not stay in the one system: it is used
  -- there and goes on along the gates.)
  local function given(econ: Economy.Economy): number
    return econ.sold[ferrite] - econ.bought[ferrite]
  end
  local moved = given(state.commerce) - given(idle.state.commerce)
  t.ok(moved > 0.8 * lot and moved <= lot + 1, `{math.floor(moved)} of {lot} units reached the system`)
  t.ok(node.stock[ferrite] > idle.state.commerce.nodes[system].stock[ferrite], "the system should have more ferrite for it")
  t.ok(Core.Query.Quote(game, home, "ore.ferrite").bid > 0.9 * Core.Query.Quote(idle, home, "ore.ferrite").bid,
    "the station's price should be most of the way back")
  for class, residual in Economy.Residual(state.commerce) do
    t.ok(math.abs(residual) * state.commerce.classes[class].par < 1, `the books are out by {residual}`)
  end
end)

suite:Case("the economy is in the save, and a save from before is given its galaxy's", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, systems = SYSTEMS, peaceful = true })
  Core.Query.Quote(game, game.state.player.home, "ore.ferrite")
  for _ = 1, 3 * Commerce.STEP do
    Core.Step(game)
  end
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  for _ = 1, 2 * Commerce.STEP do
    Core.Step(game)
    Core.Step(loaded)
  end
  t.eq(Core.Hash(loaded), Core.Hash(game))
  -- A save of the version before: no economy, and markets that know nothing of what their par was.
  local fresh = Core.New({ galaxySeed = 1, historySeed = 1, systems = SYSTEMS, peaceful = true })
  Core.Query.Quote(fresh, fresh.state.player.home, "ore.ferrite")
  local saved, savedLength = Core.Save(fresh)
  local file = Codec.Decode(saved, savedLength)
  file.saveVersion = 74
  file.state.commerce, file.state.marketDrawn = nil, nil
  for _, econ in file.state.markets do
    for _, class in econ.classes do
      class.base = nil
    end
  end
  local old, oldLength = Codec.Encode(file)
  local opened = Core.Load(old, oldLength)
  t.eq(#opened.state.commerce.nodes, SYSTEMS)
  for _ = 1, 2 * Commerce.STEP do
    Core.Step(opened)
    Core.Step(fresh)
  end
  t.eq(Codec.HashOf(opened.state.commerce), Codec.HashOf(fresh.state.commerce))
  t.eq(Core.Query.Quote(opened, opened.state.player.home, "ore.ferrite").bid, Core.Query.Quote(fresh, fresh.state.player.home, "ore.ferrite").bid)
end)

suite:Case("a new game's galaxy has been going a while: prices are apart across the map, and the pilot can ask where", function(t)
  local fresh = Core.New({ galaxySeed = 1, historySeed = 1, systems = SYSTEMS, peaceful = true })
  local here, list = Core.Query.Prices(fresh, "mineral.iron")
  t.eq(here, 1)
  t.ok(#list >= 10, `{#list} systems within reach have a market`)
  for _, at in list do
    t.eq(at.level, 1)
  end
  local game = Core.New({ galaxySeed = 1, historySeed = 1, systems = SYSTEMS, peaceful = true, settled = Commerce.SETTLED })
  local state = game.state
  here, list = Core.Query.Prices(game, "mineral.iron")
  t.eq(here, Commerce.Level(state.commerce, 1, "mineral.iron"))
  t.ok(list[#list].level / list[1].level > 1.08, `iron is {list[1].level} at the cheapest and {list[#list].level} at the dearest`)
  local seen: { [number]: boolean } = {}
  for index, at in list do
    t.ok(at.system ~= 1 and not seen[at.system] and at.jumps >= 1 and at.jumps <= Core.PRICE_REACH)
    seen[at.system] = true
    t.eq({ at.name, at.level } :: { any }, { state.galaxy.systems[at.system].name, Commerce.Level(state.commerce, at.system, "mineral.iron") } :: { any })
    t.ok(index == 1 or at.level >= list[index - 1].level, "the cheapest first")
    -- (somewhere with a station to trade at)
    local station = false
    for _, object in Space.Glance(state, at.system).objects do
      station = station or object.kind == "station"
    end
    t.ok(station, `{at.name} has no station`)
  end
  -- (what is built of the goods has its own, by less; what is built of none of them goes for the same everywhere)
  local _, hulls = Core.Query.Prices(game, "frigate.courier")
  t.ok(#hulls == #list and hulls[#hulls].level / hulls[1].level < list[#list].level / list[1].level)
  t.eq(select(2, Core.Query.Prices(game, "skillbook.mining")), {})
  -- A station nobody has looked at quotes what it will charge when
  -- somebody does: its system's price, not the normal one.
  local far = list[1].system
  local station = 0
  for _, object in Space.Glance(state, far).objects do
    if object.kind == "station" and station == 0 then
      station = object.id
    end
  end
  t.eq(state.markets[station], nil)
  local units, cost = Market.Asks(state, station, "mineral.iron", 1000)
  t.eq(units, 1000)
  t.eq(state.markets[station], nil)
  -- (the pilot comes to the system, and the market is opened)
  Space.Describe(state, far)
  t.eq(cost, Market.BuyCost(state, station, "mineral.iron", 1000))
  t.ok(state.markets[station] ~= nil)
end)

return suite
