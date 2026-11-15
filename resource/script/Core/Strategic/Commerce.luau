--!strict
-- Commerce: the galaxy's economy, in the real bulk goods.
--
-- The project owner's rulings (2026-11-14): the economy is wired in
-- under the markets first; it is made of the real materials (not of
-- abstract classes of goods: what is stocked and flows is the ore, the
-- minerals, the components, the moon and planetary materials a pilot
-- carries), and what is built of them is priced from what its blueprint
-- takes where it is; and it is kept moving by pirates on the lanes, by
-- what happens in a region now and then, and by haulers that carry it
-- for real (Tactical/Traffic).
--
-- This is the first of those: one economy for the map (Strategic/
-- Economy: stocks, prices, production and flows along the gates), a
-- node a system and a class a real type of goods. What each system is
-- in it follows from what the system is described with:
--
--   - People live where the stations are, more of them at a homeworld
--     and where order is kept. They use up ships, modules and charges,
--     and so the materials those are built of: what a unit of people
--     uses in an hour is worked out from the blueprints.
--   - Ore is dug where the belts are, of the ores the belts have (the
--     rare ones only where nobody keeps order). Refineries make minerals
--     of it, by the yields a pilot gets; yards and hubs make components
--     of the minerals, by the blueprints; moons give what is under them,
--     planets what they have; vapour and salvage come from where it is
--     not safe.
--   - Industry is sized and not rolled: what the galaxy's people use of
--     everything is added up, with what every stage before it takes,
--     and that much capacity and some slack is handed out among the
--     systems that have the place for it. So the galaxy can feed itself
--     and no system can: the difference is the trade.
--   - Goods go along the gates toward where they are dear, once the
--     difference is more than the carrying costs: which is more where
--     order is thin, and a great deal more into a system where pirates
--     are massing (Tactical/Surges), where some of it is lost too.
--   - A homeworld is a deep market: it buys and sells everything near
--     the normal price at a limited rate, which is what keeps the level
--     of prices where it is.
--
-- Uncharted space is not part of it: nobody lives there and no gate
-- goes there.
--
-- Every figure here is a first figure.

local Blueprints = require("@lt/Core/Data/Blueprints")
local Constants = require("@lt/Core/Data/Constants")
local Economy = require("@lt/Core/Strategic/Economy")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Moons = require("@lt/Core/Data/Moons")
local Ores = require("@lt/Core/Data/Ores")
local Planets = require("@lt/Core/Data/Planets")
local Reactions = require("@lt/Core/Data/Reactions")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")
local Types = require("@lt/Core/Data/Types")

local Commerce = {}

-- Ticks between the economy's steps: ten game minutes. And in a day.
Commerce.STEP = math.ceil(600 / Constants.TICK)
Commerce.DAY = math.ceil(86400 / Constants.TICK)
-- Credits' worth of built things a unit of people uses up in an hour.
Commerce.SCALE = 400000
-- How those are shared among what is built: hulls, modules, charges and
-- the rest.
-- (the last is boosters, which are what vapour is drawn off for)
Commerce.BASKET = { ship = 0.4, module = 0.3, charge = 0.19, drone = 0.04, structure = 0.04, goods = 0.03 } :: { [string]: number }
-- Fuel blocks a unit of people burns in an hour (their stations are
-- towers, and burn it).
Commerce.FUEL = 40
-- How much more capacity there is of every stage than the galaxy needs.
Commerce.SLACK = 1.3
-- Hours of what it uses, makes or passes on that a system aims to hold.
Commerce.COVER = 24
-- And no less of any goods than so many credits' worth: a system that
-- neither makes nor uses a thing still has a market in it, deeper than
-- any one station's.
Commerce.DEPTH = 30000000
-- What a refinery gets of an ore's perfect yield.
Commerce.YIELD = 0.75
-- The lanes: credits an hour that go along a gate for each part of the
-- price difference beyond the cost, for a pair of systems with nobody
-- in them (and as much again for each unit of people at the two ends);
-- what a jump costs, as a share of the price; what it costs more where
-- order is thin; and the share lost to pirates on a lane into lawless
-- space.
Commerce.HAUL = 6000000
Commerce.COST_JUMP = 0.02
Commerce.COST_RISK = 0.06
Commerce.LOSS = 0.03
-- A lane into a system where pirates are massing costs so much more,
-- and loses so much.
Commerce.SURGE_COST, Commerce.SURGE_LOSS = 0.5, 0.15
-- And a lane into a system that is blockaded (Strategic/Wars) all but
-- shut: a thing has to be twice the price there before any of it is
-- run in, and a fifth of that is lost.
Commerce.BLOCKADE_COST, Commerce.BLOCKADE_LOSS = 1, 0.2
-- How fast a homeworld deals with the world beyond: so many times what
-- it turns over itself.
Commerce.ANCHOR = 1.5
-- A new game's galaxy has been going for so many days when the pilot
-- comes to it (Core.New's 'settled'): long enough for the prices of
-- things to have come apart across the map. Worked out in steps of so
-- many hours, which leaves it where the game's own short steps would.
Commerce.SETTLED, Commerce.SETTLE_HOURS = 20, 2
-- What happens to a part of the map now and then: the chance on any
-- day that a glut or a shortage begins somewhere; how many there are at
-- once, at most; how many days one lasts, at the least and the most;
-- and how many times what it did a system there wants of the thing,
-- in a shortage and in a glut.
Commerce.SHOCK_CHANCE, Commerce.SHOCKS = 0.6, 4
Commerce.SHOCK_DAYS = { 3, 6 }
Commerce.SHORTAGE, Commerce.GLUT = 2.5, 0.4
-- What is left, after a step, of what was put down as having gone
-- along a watched lane and nobody was seen carrying; and how full a
-- hauler's hold is of what it carries.
Commerce.FORGET, Commerce.FILL = 0.5, 0.9
-- The share of what a built thing costs that is its materials: what a
-- local price of them moves (Data/Blueprints prices one so).
Commerce.MATERIALS = 0.6

-- ---------------------------------------------------------------------
-- The goods

-- Whether a type is one of the bulk goods the economy stocks.
local function bulk(info: Types.Info): boolean
  local id = info.id
  return info.category == "ore" or info.category == "mineral" or info.category == "component" or info.category == "moon"
    or (info.category == "planetary" and info.basePrice > 1)
    or (info.category == "goods" and (string.sub(id, 1, 4) == "gas." or string.sub(id, 1, 8) == "salvage." or id == "scrap.metal"))
    or id == "fuel.block"
end

local goods: { string } = {}
local indexOf: { [string]: number } = {}
do
  local ids = table.clone(Types.Ids())
  table.sort(ids)
  for _, id in ids do
    if bulk(Types.Info(id)) then
      table.insert(goods, id)
      indexOf[id] = #goods
    end
  end
end
-- The goods, in the order of their classes in the economy.
Commerce.goods = goods

-- The class of a type in the economy, if it is one of the goods.
function Commerce.Index(type: string): number?
  return indexOf[type]
end

-- What a unit of a type is built of, in the goods: by its blueprint,
-- and through whatever of that is itself built. Nothing for a thing
-- with no blueprint, and for one of the goods (which is itself).
-- ('share': how much of what all of it is worth, at normal prices, this
-- part is.)
export type Part = { class: number, amount: number, share: number }
local bills: { [string]: { Part } } = {}
local function billOf(type: string, depth: number): { [number]: number }
  local found: { [number]: number } = {}
  local blueprint = Blueprints.byProduct[type]
  if blueprint == nil or depth > 4 then
    return found
  end
  for _, material in blueprint.materials do
    local each = material.quantity / blueprint.perRun
    local class = indexOf[material.type]
    if class then
      found[class] = (found[class] or 0) + each
    else
      for index, amount in billOf(material.type, depth + 1) do
        found[index] = (found[index] or 0) + each * amount
      end
    end
  end
  return found
end
function Commerce.Bill(type: string): { Part }
  local kept = bills[type]
  if kept == nil then
    kept = {}
    if indexOf[type] == nil then
      local found = billOf(type, 1)
      local worth = 0
      for class = 1, #goods do
        if found[class] then
          table.insert(kept, { class = class, amount = found[class], share = found[class] * Types.Info(goods[class]).basePrice })
          worth += found[class] * Types.Info(goods[class]).basePrice
        end
      end
      for _, part in kept do
        part.share /= worth
      end
    end
    bills[type] = kept
  end
  return kept
end

-- ---------------------------------------------------------------------
-- What a system is

-- A system as the economy sees it: how many people, and what there is
-- to make things of and with.
export type Census = {
  population: number,
  stations: { [string]: number },   -- how many of each kind
  ore: { [string]: number },        -- units in its belts, by ore
  moons: { [string]: number },      -- richness under its moons, by material
  planets: { [string]: number },    -- planets that have each raw material
  security: number,
  home: boolean,
}

local PEOPLE: { [string]: number } = { ["trade hub"] = 1.2, habitat = 1.5, shipyard = 1, refinery = 0.8, outpost = 0.5 }

function Commerce.Census(galaxy: Galaxy.Galaxy, id: number): Census
  local node = galaxy.systems[id]
  local band = Galaxy.Band(node.security)
  local census: Census = { population = 0, stations = {}, ore = {}, moons = {}, planets = {}, security = node.security, home = node.home }
  local people = 0
  for _, object in System.Describe(galaxy, id).objects do
    if object.kind == "station" then
      census.stations[object.variety] = (census.stations[object.variety] or 0) + 1
      people += PEOPLE[object.variety] or 0.5
    elseif object.kind == "asteroid" and Ores.byId[object.variety] then
      census.ore[object.variety] = (census.ore[object.variety] or 0) + Ores.RockUnits(object.radius)
    elseif object.kind == "moon" then
      local deposit = Moons.Deposit(object.seed, band)
      if deposit then
        census.moons[deposit.material.id] = (census.moons[deposit.material.id] or 0) + deposit.richness
      end
    elseif object.kind == "planet" then
      local has: { string } = Planets.DEPOSITS[object.variety] or {}
      for _, raw in has do
        census.planets[raw] = (census.planets[raw] or 0) + 1
      end
    end
  end
  -- (where nobody has a station somebody still passes through: the
  -- nomads' space, whose stations roam, more than nobody's)
  census.population = if people > 0 then people * (0.6 + 0.8 * node.security) * (if node.home then 3 else 1)
    elseif node.owner ~= "" then 0.15
    else 0.03
  return census
end

-- ---------------------------------------------------------------------
-- The economy

-- What a unit of people uses up in an hour, by class: what the built
-- things in their basket are made of.
local function basket(): { number }
  local need: { number } = table.create(#goods, 0)
  local sums: { [string]: { number } } = {}
  local counts: { [string]: number } = {}
  for _, id in Types.Ids() do
    local info = Types.Info(id)
    local share = Commerce.BASKET[info.category]
    -- (a capital is not what people lose by the hour)
    local hull = Ships.byId[id]
    if share and info.basePrice > 0 and not (hull and Ships.Capital(hull.class)) then
      local bill = Commerce.Bill(id)
      if #bill > 0 then
        local sum = sums[info.category]
        if sum == nil then
          sum = table.create(#goods, 0)
          sums[info.category] = sum
        end
        counts[info.category] = (counts[info.category] or 0) + 1
        for _, part in bill do
          sum[part.class] += part.amount / info.basePrice
        end
      end
    end
  end
  for category, sum in sums do
    for class = 1, #goods do
      need[class] += Commerce.SCALE * Commerce.BASKET[category] * sum[class] / counts[category]
    end
  end
  local fuel = indexOf["fuel.block"]
  if fuel then
    need[fuel] += Commerce.FUEL
  end
  return need
end

-- A recipe, and what says how much of its capacity a system has.
type Stage = { recipe: Economy.Recipe, weight: (Census) -> number }

local function stationed(weights: { [string]: number }): (Census) -> number
  return function(census: Census): number
    local sum = 0
    for kind, weight in weights do
      sum += (census.stations[kind] or 0) * weight
    end
    return sum
  end
end

-- The stages of industry, the later ones first (so that what each takes
-- of the ones before it is known by the time they are sized).
local function stages(): { Stage }
  local list: { Stage } = {}
  local function made(type: string, by: (Census) -> number)
    -- (by its blueprint: a unit of it from what the blueprint takes)
    local blueprint = Blueprints.byProduct[type]
    local class = indexOf[type]
    if blueprint == nil or class == nil then
      return
    end
    local inputs: { Economy.Amount } = {}
    local cost = 0
    for _, material in blueprint.materials do
      local index = indexOf[material.type]
      if index then
        table.insert(inputs, { class = index, amount = material.quantity / blueprint.perRun })
        cost += Types.Info(material.type).basePrice * material.quantity / blueprint.perRun
      end
    end
    local worth = Types.Info(type).basePrice
    table.insert(list, { recipe = { id = "make " .. type, inputs = inputs, outputs = { { class = class, amount = 1 } },
      margin = math.clamp(worth / math.max(1, cost) - 1.02, 0.02, 0.15) }, weight = by })
  end
  local function source(type: string, by: (Census) -> number)
    local class = indexOf[type]
    if class then
      table.insert(list, { recipe = { id = "get " .. type, inputs = {}, outputs = { { class = class, amount = 1 } }, margin = 0.5 },
        weight = by })
    end
  end
  made("fuel.block", stationed({ ["trade hub"] = 1, habitat = 1 }))
  for _, id in goods do
    if Types.Info(id).category == "component" then
      made(id, stationed({ shipyard = 1, ["trade hub"] = 0.5 }))
    end
  end
  for _, composite in Reactions.composites do
    local class = indexOf[composite.id]
    local inputs: { Economy.Amount } = {}
    for _, material in composite.from do
      if indexOf[material] then
        table.insert(inputs, { class = indexOf[material], amount = 1 })
      end
    end
    if class and #inputs == #composite.from then
      table.insert(list, { recipe = { id = "react " .. composite.id, inputs = inputs, outputs = { { class = class, amount = 1 } },
        margin = 0.15 }, weight = stationed({ refinery = 1, outpost = 0.5 }) })
    end
  end
  for _, id in goods do
    local info = Types.Info(id)
    if Moons.byId[id] then
      source(id, function(census: Census): number
        return census.moons[id] or 0
      end)
    elseif Planets.productById[id] then
      local raw = Planets.productById[id].from
      source(id, function(census: Census): number
        return census.planets[raw] or 0
      end)
    elseif string.sub(id, 1, 4) == "gas." then
      source(id, function(census: Census): number
        return math.max(0, 0.8 - census.security)
      end)
    elseif info.category == "goods" then
      -- (salvage: where ships are lost)
      source(id, function(census: Census): number
        return census.population * (1.2 - census.security)
      end)
    end
  end
  for _, ore in Ores.list do
    local class = indexOf[ore.id]
    local outputs: { Economy.Amount } = {}
    for _, yield in ore.yields do
      if indexOf[yield.mineral] then
        table.insert(outputs, { class = indexOf[yield.mineral], amount = yield.amount * Commerce.YIELD })
      end
    end
    if class then
      table.insert(list, { recipe = { id = "refine " .. ore.id, inputs = { { class = class, amount = 100 } }, outputs = outputs,
        margin = 0.15 }, weight = stationed({ refinery = 1, outpost = 0.3 }) })
    end
  end
  for _, ore in Ores.list do
    source(ore.id, function(census: Census): number
      return census.ore[ore.id] or 0
    end)
  end
  return list
end

-- A galaxy's economy: a node for every system of its map, by the
-- system's id, an edge for every gate, and industry enough for what its
-- people use. It follows from the galaxy alone.
function Commerce.New(galaxy: Galaxy.Galaxy): Economy.Economy
  local need = basket()
  local classes: { Economy.Class } = {}
  for class, id in goods do
    local info = Types.Info(id)
    table.insert(classes, { id = id, par = info.basePrice, cover = Commerce.COVER, need = need[class],
      -- (what is bulky for what it is worth does not travel far: ore, most of all)
      bulk = math.clamp(60 * info.volume / info.basePrice, 0.3, 3) })
  end
  local list = stages()
  local recipes: { Economy.Recipe } = {}
  for index, stage in list do
    recipes[index] = stage.recipe
  end
  local charted = Galaxy.Charted(galaxy)
  local census: { Census } = table.create(charted)
  local people = 0
  for id = 1, charted do
    census[id] = Commerce.Census(galaxy, id)
    people += census[id].population
  end
  -- How much of each class the galaxy uses in an hour: its people's
  -- needs, and then, stage by stage, what the stages after take. A
  -- stage is sized by the class it is the first to make most of.
  local wanted: { number } = table.create(#goods, 0)
  for class = 1, #goods do
    wanted[class] = people * need[class]
  end
  local runs: { number } = table.create(#list, 0)
  for index, stage in list do
    local recipe = stage.recipe
    local most = 0
    for _, output in recipe.outputs do
      most = math.max(most, wanted[output.class] / output.amount)
    end
    -- (a class two stages make, as a mineral two ores yield, is wanted
    -- of the first of them only: what the others yield of it is over)
    runs[index] = most * Commerce.SLACK
    for _, output in recipe.outputs do
      wanted[output.class] = math.max(0, wanted[output.class] - most * output.amount)
    end
    for _, input in recipe.inputs do
      wanted[input.class] += most * input.amount
    end
  end
  local shares: { number } = table.create(#list, 0)
  for index, stage in list do
    for id = 1, charted do
      shares[index] += stage.weight(census[id])
    end
  end
  local econ = Economy.New(classes, recipes)
  for id = 1, charted do
    local facilities: { { recipe: number, capacity: number } } = {}
    for index, stage in list do
      local weight = stage.weight(census[id])
      if weight > 0 and runs[index] > 0 then
        table.insert(facilities, { recipe = index, capacity = runs[index] * weight / shares[index] })
      end
    end
    local node = Economy.AddNode(econ, galaxy.systems[id].name, census[id].population, facilities)
    for class = 1, #goods do
      local floor = Commerce.DEPTH / classes[class].par
      if econ.nodes[node].target[class] < floor then
        Economy.SetTarget(econ, node, class, floor)
        Economy.SetStock(econ, node, class, floor)
      end
    end
    if census[id].home then
      for class = 1, #goods do
        econ.nodes[node].anchor[class] = Commerce.ANCHOR * econ.nodes[node].target[class] / Commerce.COVER
      end
    end
  end
  for id = 1, charted do
    for _, neighbor in galaxy.systems[id].neighbors do
      if neighbor > id and neighbor <= charted then
        Economy.AddEdge(econ, id, neighbor, Commerce.HAUL * (1 + census[id].population + census[neighbor].population), 0)
      end
    end
  end
  Commerce.Lanes(econ, galaxy, 0)
  return econ
end

-- Set every lane's cost, and what it loses, from how safe its two ends
-- are now: 'surge' is where pirates are massing (the systems they are
-- massing in, Strategic/Happenings; or one system's number, 0 for
-- none), and 'blocked' the systems that are blockaded (Strategic/Wars),
-- whose lanes are all but shut.
function Commerce.Lanes(econ: Economy.Economy, galaxy: Galaxy.Galaxy, surge: number | { [number]: boolean },
  blocked: { [number]: boolean }?)
  local many: { [number]: boolean }? = if type(surge) == "table" then surge else nil
  local one: number = if type(surge) == "number" then surge else 0
  for _, edge in econ.edges do
    local a, b = galaxy.systems[edge.a], galaxy.systems[edge.b]
    local least = math.min(a.security, b.security)
    edge.cost = Commerce.COST_JUMP + Commerce.COST_RISK * (1 - least)
    edge.loss = if Galaxy.Band(least) == "lawless" then Commerce.LOSS else 0
    if (many and (many[edge.a] or many[edge.b])) or (one ~= 0 and (edge.a == one or edge.b == one)) then
      edge.cost += Commerce.SURGE_COST
      edge.loss = Commerce.SURGE_LOSS
    end
    if blocked and (blocked[edge.a] or blocked[edge.b]) then
      edge.cost += Commerce.BLOCKADE_COST
      edge.loss = math.max(edge.loss, Commerce.BLOCKADE_LOSS)
    end
  end
end

-- How much trade each system's lanes can carry, by the system's number:
-- what its open lanes would move at a given difference in price. It is
-- what pirates come for (Strategic/Happenings).
function Commerce.Carries(econ: Economy.Economy, systems: number): { number }
  local carries: { number } = table.create(systems, 0)
  for _, edge in econ.edges do
    if edge.open then
      if edge.a <= systems then
        carries[edge.a] += edge.conductance
      end
      if edge.b <= systems then
        carries[edge.b] += edge.conductance
      end
    end
  end
  return carries
end

-- What a type goes for in a system, as a share of its normal price: for
-- one of the goods, what the system's stock of it says; for a thing
-- built of them, what its materials come to there, for the part of its
-- price that is materials. 1 for anything else, and for a system that
-- is not of the economy (uncharted space).
function Commerce.Level(econ: Economy.Economy?, system: number, type: string): number
  local node = if econ then econ.nodes[system] else nil
  if econ == nil or node == nil then
    return 1
  end
  local class = indexOf[type]
  if class then
    return Economy.Price(econ, system, class) / econ.classes[class].par
  end
  local bill = Commerce.Bill(type)
  if #bill == 0 then
    return 1
  end
  local here = 0
  for _, part in bill do
    here += part.share * Economy.Price(econ, system, part.class) / econ.classes[part.class].par
  end
  return 1 + Commerce.MATERIALS * (here - 1)
end

-- A shock begins or ends: every system of its constellation wants so
-- many times what it did of the thing (or, ending, what it did again).
local function want(econ: Economy.Economy, galaxy: Galaxy.Galaxy, shock: State.Shock, factor: number)
  for id = 1, #econ.nodes do
    if galaxy.systems[id].constellation == shock.constellation then
      econ.nodes[id].target[shock.class] *= factor
    end
  end
end

-- What happens to the trade of a part of the map. The shocks that are
-- over end; and on the first step of a game day, more days than not,
-- one begins: a constellation of the map, one of the goods, a glut or
-- a shortage, for some days. A shortage is a part of the map wanting
-- more of a thing than it has: it is dear there at once, and goes there
-- along the gates from all round until there is enough, and when it is
-- over there is too much. A glut is the other way about. Returns
-- nothing: what began and ended is said in 'events'.
function Commerce.Stir(econ: Economy.Economy, galaxy: Galaxy.Galaxy, shocks: { State.Shock }, seed: number, tick: number, ticks: number,
  events: { { [string]: any } })
  for index = #shocks, 1, -1 do
    local shock = shocks[index]
    if tick >= shock.ends then
      want(econ, galaxy, shock, 1 / shock.factor)
      table.remove(shocks, index)
      table.insert(events, { kind = "TradeShockOver", constellation = shock.constellation, type = goods[shock.class],
        shortage = shock.factor > 1 })
    end
  end
  local day = Commerce.DAY
  if tick // day == (tick - ticks) // day or #shocks >= Commerce.SHOCKS then
    return
  end
  local rng = Rng.For(seed, tick // day, 707)
  -- (the constellations of the map: the last is uncharted space's, in a galaxy that has any)
  local constellations = #galaxy.constellations - (if galaxy.charted then 1 else 0)
  if constellations < 1 or not Rng.Chance(rng, Commerce.SHOCK_CHANCE) then
    return
  end
  local where = 1 + Rng.Int(rng, constellations)
  local class = 1 + Rng.Int(rng, #goods)
  for _, shock in shocks do
    -- (one thing at a time to a place)
    if shock.constellation == where then
      return
    end
  end
  local days = Commerce.SHOCK_DAYS[1] + Rng.Int(rng, Commerce.SHOCK_DAYS[2] - Commerce.SHOCK_DAYS[1] + 1)
  local shock: State.Shock = { id = tick, constellation = where, class = class,
    factor = if Rng.Chance(rng, 0.5) then Commerce.SHORTAGE else Commerce.GLUT, began = tick, ends = tick + days * day }
  table.insert(shocks, shock)
  want(econ, galaxy, shock, shock.factor)
  table.insert(events, { kind = "TradeShock", constellation = where, type = goods[class], shortage = shock.factor > 1, days = days })
end

-- Let so many days go by in an economy all at once, with nothing
-- happening to it: for a galaxy that has been going a while when a
-- game begins in it.
function Commerce.Settle(econ: Economy.Economy, galaxy: Galaxy.Galaxy, days: number)
  Commerce.Lanes(econ, galaxy, 0)
  for _ = 1, math.ceil(days * 24 / Commerce.SETTLE_HOURS) do
    Economy.Step(econ, Commerce.SETTLE_HOURS)
  end
end

-- Let the economy's time go by: 'ticks' of it, with the lanes as they
-- are now ('surge': the system pirates are massing in, 0 for none).
function Commerce.Advance(econ: Economy.Economy, galaxy: Galaxy.Galaxy, surge: number | { [number]: boolean }, ticks: number, blocked: { [number]: boolean }?)
  Commerce.Lanes(econ, galaxy, surge, blocked)
  -- (what went along the watched lanes a while ago has long arrived:
  -- half of what nobody has been seen carrying is forgotten each step)
  if econ.passed then
    for _, row in econ.passed do
      for class = 1, #row do
        row[class] *= Commerce.FORGET
      end
    end
  end
  Economy.Step(econ, ticks * Constants.TICK / 3600)
end

-- The haulers a pilot sees carry it for real (the project owner's
-- ruling; Tactical/Traffic). The economy moves goods along a gate as a
-- quantity, with nobody to be seen: in the system the pilot is in, what
-- goes along each lane is put down as it goes (Economy's 'passed'), and
-- a hauler that comes in by a gate, or leaves by one, has a hold of
-- what lately came or went that way. While it is on its way those goods
-- are in its hold and not in the stock of the system they are for: they
-- are put there when it gets where it is going (Commerce.Deliver), and
-- if it is destroyed they are in its wreck and the system goes without.

-- Watch the lanes of a system (the one the pilot is in): what was put
-- down for another is dropped.
function Commerce.Watch(econ: Economy.Economy, system: number)
  local watch: number? = if econ.nodes[system] then system else nil
  if econ.watch == watch then
    return
  end
  local passed: { [number]: { number } } = {}
  econ.watch, econ.passed = watch, passed
  if watch == nil then
    return
  end
  -- (and what is on its lanes as the pilot comes: about what the next
  -- step will send along each, by the prices at their two ends now)
  local hours = Commerce.STEP * Constants.TICK / 3600
  for _, edge in econ.edges do
    if edge.open and (edge.a == watch or edge.b == watch) then
      local other = if edge.a == watch then edge.b else edge.a
      local row: { number } = table.create(#econ.classes, 0)
      for class, info in econ.classes do
        local here, there = Economy.Price(econ, watch, class) / info.par, Economy.Price(econ, other, class) / info.par
        local gap = math.abs(here - there) - edge.cost * (info.bulk or 1)
        if gap > 0 then
          local amount = edge.conductance * hours * gap / info.par
          row[class] = if here > there then amount else -amount
        end
      end
      passed[other] = row
    end
  end
end

-- A lane of the watched system that something has lately gone along,
-- among the systems named (those its gates lead to), and which way: the
-- system at the other end, and whether the goods went out to it (or
-- came in from it). Picked by a roll in [0, 1): a lane and a way more
-- has gone by is likelier, by the root of what that was worth, so that
-- the busiest lane has most of the haulers and not all of them. Nil if
-- nothing has gone along any of them.
function Commerce.Lane(econ: Economy.Economy, among: { number }, roll: number): (number?, boolean)
  local passed = econ.passed
  if passed == nil then
    return nil, false
  end
  local lanes: { { other: number, out: boolean, weight: number } } = {}
  local sum = 0
  for _, other in among do
    local row = passed[other]
    if row then
      local came, went = 0, 0
      for class = 1, #row do
        local worth = row[class] * econ.classes[class].par
        came = math.max(came, worth)
        went = math.max(went, -worth)
      end
      for _, way in { { came, false }, { went, true } } :: { { any } } do
        if way[1] > 0 then
          table.insert(lanes, { other = other, out = way[2], weight = math.sqrt(way[1]) })
          sum += math.sqrt(way[1])
        end
      end
    end
  end
  local at = roll * sum
  for _, lane in lanes do
    at -= lane.weight
    if at < 0 then
      return lane.other, lane.out
    end
  end
  local last = lanes[#lanes]
  return if last then last.other else nil, last ~= nil and last.out
end

-- A hold of what has lately gone along a lane of the watched system,
-- for a hauler with so many m3 of room: the goods of which most went
-- that way ('out' to the system at the other end, or in from it), as
-- many units as there is room for and no more than went. They are taken
-- out of the stock of the system they were for, and off the record of
-- the lane. Returns the type, the whole units, and the system (the
-- node) they are owed to; nothing if nothing went that way, or the
-- hold has not room for one.
function Commerce.Load(econ: Economy.Economy, other: number, out: boolean, room: number): (string?, number, number)
  local watch, passed = econ.watch, econ.passed
  local row = if passed then passed[other] else nil
  if watch == nil or row == nil then
    return nil, 0, 0
  end
  local best, most = 0, 0
  for class = 1, #row do
    local worth = (if out then -row[class] else row[class]) * econ.classes[class].par
    if worth > most then
      best, most = class, worth
    end
  end
  if best == 0 then
    return nil, 0, 0
  end
  local owed = if out then other else watch
  local type = goods[best]
  local units = math.floor(math.min(math.abs(row[best]), room * Commerce.FILL / Types.Info(type).volume, econ.nodes[owed].stock[best]))
  if units < 1 then
    return nil, 0, 0
  end
  Economy.Draw(econ, owed, best, units)
  row[best] += if out then units else -units
  return type, units, owed
end

-- A hauler got where it was going: what it carried is in the stock of
-- the system it was for.
function Commerce.Deliver(econ: Economy.Economy, node: number, class: number, amount: number)
  if econ.nodes[node] then
    Economy.Give(econ, node, class, amount)
  end
end

return Commerce
