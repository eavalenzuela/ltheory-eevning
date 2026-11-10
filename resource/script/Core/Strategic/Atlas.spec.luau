--!strict
-- The galaxy's economy: the goods table, who has what, and whether a
-- small galaxy built from them runs. (The full-size judgement, 16 seeds
-- of 400 systems over 30 game days, is script/econsweep.)

local Atlas = require("@lt/Core/Strategic/Atlas")
local Codec = require("@lt/Core/Persist/Codec")
local EconProbe = require("@lt/Tool/EconProbe")
local Economy = require("@lt/Core/Strategic/Economy")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Goods = require("@lt/Core/Data/Goods")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Atlas")

suite:Case("every class of goods is priced from what it is made of, at the standard margin", function(t)
  local classes = Goods.Classes()
  local recipes = Goods.Recipes()
  t.eq(#classes, 27)
  t.eq(#recipes, #Goods.steps)
  local makers: { [number]: number } = {}
  for at, recipe in recipes do
    t.eq(recipe.id, Goods.steps[at].id)
    t.eq(#recipe.outputs, 1)
    local out = recipe.outputs[1].class
    makers[out] = (makers[out] or 0) + 1
    -- every way of making something pays the same at normal prices, and
    -- its labour comes out positive
    t.near(recipe.margin, Goods.MARGIN, 1e-9, recipe.id)
    local cost = 0
    for _, input in recipe.inputs do
      t.ok(input.class < out or classes[input.class].par < classes[out].par * 100, recipe.id)
      cost += input.amount * classes[input.class].par
    end
    t.ok(classes[out].par / (1 + recipe.margin) - cost >= 0, `{recipe.id} has no room for labour`)
  end
  for g, class in classes do
    t.ok(class.par > 0 and class.cover > 0, class.id)
    t.ok((makers[g] or 0) >= 1, `nothing makes {class.id}`)
  end
  -- a later stage is worth more than what goes into it
  local par = function(id: string): number
    return classes[Goods.Index(id)].par
  end
  t.ok(par("metals") > 2 * par("ore.common"))
  t.ok(par("components") > par("alloys") + 0.5 * par("electronics"))
  t.ok(par("hulls.battleship") > 5 * par("hulls.cruiser"))
end)

suite:Case("what a unit of population uses is worth what the table says, and making it takes more", function(t)
  local used: { number } = {}
  local value = 0
  for g, class in Goods.list do
    used[g] = class.need
    value += class.need * class.par
  end
  t.near(value, Goods.SCALE, 1e-6)
  local required, runs = Goods.Required(used)
  for g, class in Goods.list do
    t.ok(required[g] >= used[g], class.id)
    -- everything is either used by people or goes into something that is
    t.ok(required[g] > 0, `nobody needs {class.id}`)
  end
  -- metals are made two ways, in fixed shares
  local smelt, recycle = 0, 0
  for at, step in Goods.steps do
    if step.id == "smelt" then
      smelt = runs[at]
    elseif step.id == "recycle" then
      recycle = runs[at]
    end
  end
  t.near(smelt / (smelt + recycle), 0.85, 1e-9)
  t.near(smelt + recycle, required[Goods.Index("metals")], 1e-6)
end)

suite:Case("the atlas claims most systems for eight powers and sizes industry to what people use", function(t)
  local galaxy = Galaxy.Describe(3, 200)
  local atlas = Atlas.Describe(galaxy, 3)
  t.eq(#atlas.factions, 8)
  t.eq(#atlas.systems, 200)
  local homes, claimed, people = 0, 0, 0
  for id, info in atlas.systems do
    t.eq(info.id, id)
    people += info.population
    if info.home then
      homes += 1
      t.eq({ info.hops, info.security, info.population } :: { any }, { 0, 1, 40 } :: { any })
      t.eq(atlas.factions[info.owner].home, id)
    end
    if info.owner ~= 0 then
      claimed += 1
      t.ok(info.security >= Atlas.SECURITY_FLOOR and info.security <= 1)
    else
      t.eq(info.security, 0)
      t.ok(info.population <= 1)
    end
  end
  t.eq(homes, 8)
  t.near(people, atlas.population, 1e-9)
  t.ok(claimed / 200 > 0.7 and claimed / 200 < 0.95, `{claimed} of 200 systems are claimed`)

  -- Capacity for every step is what the galaxy needs, plus the slack.
  local used: { number } = table.create(#Goods.list, 0)
  for _, info in atlas.systems do
    for g, class in Goods.list do
      used[g] += info.population * class.need * info.taste[g]
    end
  end
  local _, runs = Goods.Required(used)
  for at, step in Goods.steps do
    local capacity, hosts = 0, 0
    for _, info in atlas.systems do
      for _, facility in info.facilities do
        if facility.recipe == at then
          capacity += facility.capacity
          hosts += 1
        end
      end
    end
    t.near(capacity / runs[at], Atlas.SLACK, 1e-6, step.id)
    t.ok(hosts >= 2, `{step.id} has {hosts} host(s)`)
  end
  -- a lane a gate, dearer across a border and in lawless space
  local gates = 0
  for _, system in galaxy.systems do
    gates += #system.neighbors
  end
  t.eq(#atlas.lanes, gates / 2)
  for _, lane in atlas.lanes do
    local a, b = atlas.systems[lane.a], atlas.systems[lane.b]
    t.eq(lane.border, a.owner ~= b.owner)
    t.near(lane.cost, Atlas.COST_JUMP + (if lane.border then Atlas.COST_BORDER else 0)
      + Atlas.COST_RISK * (1 - math.min(a.security, b.security)), 1e-12)
  end
end)

suite:Case("raw materials are only dug where they are, and battleships only built at homes and hubs", function(t)
  local galaxy = Galaxy.Describe(5, 150)
  local atlas = Atlas.Describe(galaxy, 5)
  for _, info in atlas.systems do
    for _, facility in info.facilities do
      local step = Goods.steps[facility.recipe]
      local made = Goods.list[Goods.Index(step.makes)]
      if made.tier == "raw" then
        t.ok((info.resources[made.resource] or 0) > 0, `{step.id} at a system without {made.resource}`)
      elseif step.makes == "hulls.battleship" then
        t.ok(info.home or info.hub)
      end
    end
  end
end)

suite:Case("describing a galaxy twice gives the same atlas, and another seed a different one", function(t)
  local galaxy = Galaxy.Describe(2, 120)
  local a, b = Atlas.Describe(galaxy, 2), Atlas.Describe(galaxy, 2)
  t.eq(Codec.HashOf(a), Codec.HashOf(b))
  t.ok(Codec.HashOf(a) ~= Codec.HashOf(Atlas.Describe(galaxy, 3)))
end)

suite:Case("a small galaxy's economy runs: books balance, people are supplied, nothing starves, it settles", function(t)
  local galaxy = Galaxy.Describe(4, 80)
  local atlas = Atlas.Describe(galaxy, 4)
  local econ = Atlas.Economy(galaxy, atlas)
  t.eq(#econ.nodes, 80)
  t.eq(#econ.edges, #atlas.lanes)
  local probe = EconProbe.New()
  -- twelve game days in ten-minute steps
  for _ = 1, 12 * 24 do
    for _ = 1, 6 do
      Economy.Step(econ, 1 / 6)
    end
    EconProbe.Sample(probe, econ)
  end
  local verdicts: { [string]: EconProbe.Check } = {}
  for _, check in EconProbe.Checks(probe, econ, 4, 0, 0) do
    verdicts[check.name] = check
  end
  for _, name in { "books: worst leak (share)", "needs met, by head", "needs met, worst tenth of systems",
    "stocks at the price ceiling", "stocks at the price floor", "price level", "share through anchors",
    "industry in use", "stock still drifting (share)", "lanes short of haulage" } do
    local check = assert(verdicts[name], `no check called '{name}'`)
    t.ok(check.ok, `{name}: {check.value} (wanted {check.limit})`)
  end
  -- and the state is plain data: it saves, loads and carries on the same
  local copy = Codec.Decode(Codec.Encode(econ))
  t.eq(Codec.HashOf(copy), Codec.HashOf(econ))
  for _ = 1, 24 do
    Economy.Step(econ, 1 / 6)
    Economy.Step(copy, 1 / 6)
  end
  t.eq(Codec.HashOf(copy), Codec.HashOf(econ))
end)

suite:Case("a blockaded region goes short and recovers when the lanes reopen", function(t)
  local galaxy = Galaxy.Describe(4, 48)
  local atlas = Atlas.Describe(galaxy, 4)
  local econ = Atlas.Economy(galaxy, atlas)
  local function settle(hours: number)
    for _ = 1, hours * 6 do
      Economy.Step(econ, 1 / 6)
    end
  end
  -- How well the people of one power are supplied.
  local function met(faction: number): number
    local people, fed = 0, 0
    for id, info in atlas.systems do
      if info.owner == faction then
        people += info.population
        fed += info.population * econ.nodes[id].met
      end
    end
    return fed / people
  end
  settle(6 * 24)
  local before = met(1)
  -- Close every lane across the first power's border.
  local closed = 0
  for index, lane in atlas.lanes do
    if lane.border and (atlas.systems[lane.a].owner == 1 or atlas.systems[lane.b].owner == 1) then
      econ.edges[index].open = false
      closed += 1
    end
  end
  t.ok(closed > 0)
  settle(6 * 24)
  local during = met(1)
  t.ok(during < before - 0.005, `cut off, its people went from {before} to {during}`)
  t.ok(during > 0.5, "but a power has industry of its own, and its homeworld")
  for _, edge in econ.edges do
    edge.open = true
  end
  settle(8 * 24)
  t.near(met(1), before, 0.01, "and with the lanes open it comes back")
end)

return suite
