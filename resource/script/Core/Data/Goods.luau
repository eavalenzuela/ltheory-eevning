--!strict
-- The classes of goods the galaxy's economy runs on, and how each is made.
--
-- The background economy (Strategic/Economy) does not track every kind
-- of item: it tracks these classes, in bulk, at every system. An item a
-- pilot handles belongs to one of them and takes its price from it.
--
-- Prices are not set by hand. A raw material has a cost of extraction;
-- everything else costs its inputs plus the labour of making it, plus a
-- margin. So every step of every chain pays at normal prices, and the
-- price level has nowhere to drift.
--
-- Quantities are in units of the class (a unit of ore, a hull). Rates
-- are per hour. A unit of population stands for a great many people and
-- their pilots: what it uses in an hour is worth about 50,000 credits.

local Economy = require("@lt/Core/Strategic/Economy")

local Goods = {}

export type Tier = "raw" | "refined" | "part" | "consumer" | "military" | "hull" | "construction"

export type Good = {
  id: string,
  name: string,
  tier: Tier,
  par: number,      -- credits per unit; worked out below for everything made
  need: number,     -- units a unit of population uses per hour
  resource: string, -- for a raw material: what a system must have to yield it
}

-- The margin every recipe earns at normal prices.
Goods.MARGIN = 0.15

-- Hours of throughput a system aims to hold, by tier. Finished goods
-- are held deeper than raw ones.
local COVER: { [string]: number } = {
  raw = 24, refined = 24, part = 36, consumer = 48, military = 48, hull = 96, construction = 72,
}

-- How costly a tier is to haul for what it is worth (a lane's cost is
-- multiplied by this). Raw materials are bulky and cheap, so they are
-- refined near where they are dug; finished goods travel.
local BULK: { [string]: number } = {
  raw = 1.6, refined = 1.0, part = 0.7, consumer = 0.6, military = 0.6, hull = 0.8, construction = 0.8,
}

-- Labour as a share of the inputs' cost, by the tier of what is made.
local LABOUR: { [string]: number } = {
  refined = 0.25, part = 0.30, consumer = 0.35, military = 0.35, hull = 0.30, construction = 0.30,
}

local goods: { Good } = {}
local index: { [string]: number } = {}

local function good(id: string, name: string, tier: Tier, par: number, need: number, resource: string?)
  table.insert(goods, { id = id, name = name, tier = tier, par = par, need = need, resource = resource or "" })
  index[id] = #goods
end

-- What a unit of population uses of everything, in credits an hour at
-- normal prices, before scaling (worked out below).
local SCALE = 50000

-- Raw materials: the price is the cost of getting them.
good("ore.common", "Common Ore", "raw", 6, 0, "ore")
good("ore.rare", "Rare Ore", "raw", 30, 0, "rare")
good("ice", "Ice", "raw", 10, 0, "ice")
good("gas", "Gas", "raw", 14, 0, "gas")
good("biomass", "Biomass", "raw", 8, 0, "life")
-- What is left of ships that are lost. It turns up wherever pilots fly,
-- and is melted down for metals.
good("salvage", "Salvage", "raw", 8, 0, "wrecks")

-- Everything below is made; its price comes from its recipe. 'need' is
-- relative here and scaled once the prices are known.
good("metals", "Metals", "refined", 0, 0)
good("rare.metals", "Rare Metals", "refined", 0, 0)
good("fuel", "Fuel", "refined", 0, 6)
good("chemicals", "Chemicals", "refined", 0, 0)
good("food", "Food", "refined", 0, 12)
good("alloys", "Alloys", "part", 0, 0)
good("polymers", "Polymers", "part", 0, 0)
good("electronics", "Electronics", "part", 0, 0)
good("components", "Components", "part", 0, 0)
good("machinery", "Machinery", "part", 0, 3)
good("consumer.goods", "Consumer Goods", "consumer", 0, 10)
good("medical", "Medical Supplies", "consumer", 0, 3)
good("luxuries", "Luxuries", "consumer", 0, 3)
good("ammunition", "Ammunition", "military", 0, 5)
good("modules", "Ship Modules", "military", 0, 5)
good("drones", "Drones", "military", 0, 2)
good("hulls.frigate", "Frigate Hulls", "hull", 0, 4)
good("hulls.industrial", "Industrial Hulls", "hull", 0, 3)
good("hulls.cruiser", "Cruiser Hulls", "hull", 0, 3)
good("hulls.battleship", "Battleship Hulls", "hull", 0, 2)
good("construction.kits", "Construction Kits", "construction", 0, 3)

export type Step = {
  id: string,
  makes: string,                    -- the class this is a way to make
  inputs: { [string]: number },     -- units per unit made
  -- Where a class can be made two ways: the share of it that is made
  -- this way. The first step listed for a class sets its price.
  share: number?,
}

-- In an order where everything a step uses is made by an earlier one.
local steps: { Step } = {
  -- Extraction: nothing in, a raw material out.
  { id = "mine.common", makes = "ore.common", inputs = {} },
  { id = "mine.rare", makes = "ore.rare", inputs = {} },
  { id = "harvest.ice", makes = "ice", inputs = {} },
  { id = "harvest.gas", makes = "gas", inputs = {} },
  { id = "farm", makes = "biomass", inputs = {} },
  { id = "salvage", makes = "salvage", inputs = {} },
  -- Refining.
  { id = "smelt", makes = "metals", inputs = { ["ore.common"] = 2 }, share = 0.85 },
  -- (1.5 of salvage a unit: what makes recycling pay exactly as well as
  -- smelting at normal prices.)
  { id = "recycle", makes = "metals", inputs = { salvage = 1.5 }, share = 0.15 },
  { id = "smelt.rare", makes = "rare.metals", inputs = { ["ore.rare"] = 2 } },
  { id = "refine.fuel", makes = "fuel", inputs = { ice = 1.5 } },
  { id = "refine.chemicals", makes = "chemicals", inputs = { gas = 1.5 } },
  { id = "process.food", makes = "food", inputs = { biomass = 1.2 } },
  -- Parts.
  { id = "forge", makes = "alloys", inputs = { metals = 1.5, ["rare.metals"] = 0.2 } },
  { id = "polymerise", makes = "polymers", inputs = { chemicals = 1.5 } },
  { id = "fabricate", makes = "electronics", inputs = { ["rare.metals"] = 0.5, polymers = 0.5, metals = 0.3 } },
  { id = "assemble", makes = "components", inputs = { alloys = 1, electronics = 0.5 } },
  { id = "build.machinery", makes = "machinery", inputs = { alloys = 1.5, components = 1 } },
  -- What people buy.
  { id = "make.goods", makes = "consumer.goods", inputs = { polymers = 0.6, electronics = 0.3 } },
  { id = "make.medical", makes = "medical", inputs = { chemicals = 0.8, food = 0.3 } },
  { id = "make.luxuries", makes = "luxuries", inputs = { food = 0.5, ["rare.metals"] = 0.3, polymers = 0.3 } },
  -- What pilots use up.
  { id = "make.ammunition", makes = "ammunition", inputs = { metals = 0.8, chemicals = 0.4 } },
  { id = "make.modules", makes = "modules", inputs = { components = 1, electronics = 0.5 } },
  { id = "make.drones", makes = "drones", inputs = { components = 0.6, electronics = 0.6, alloys = 0.3 } },
  { id = "yard.frigate", makes = "hulls.frigate", inputs = { alloys = 40, components = 10 } },
  { id = "yard.industrial", makes = "hulls.industrial", inputs = { alloys = 90, components = 15, machinery = 5 } },
  { id = "yard.cruiser", makes = "hulls.cruiser", inputs = { alloys = 300, components = 80, machinery = 20 } },
  { id = "yard.battleship", makes = "hulls.battleship", inputs = { alloys = 1800, components = 500, machinery = 150 } },
  { id = "make.kits", makes = "construction.kits", inputs = { alloys = 4, machinery = 2, polymers = 1 } },
}

-- Prices: inputs plus labour, plus the margin. (The steps are in order,
-- so an input's price is known by the time it is used.)
for _, step in steps do
  local made = goods[index[step.makes]]
  if made.tier ~= "raw" and made.par == 0 then
    local cost = 0
    for id, amount in step.inputs do
      local input = goods[assert(index[id], `{step.id} uses an unknown class '{id}'`)]
      assert(input.par > 0, `{step.id} uses {id} before it is made`)
      cost += amount * input.par
    end
    made.par = cost * (1 + LABOUR[made.tier]) * (1 + Goods.MARGIN)
  end
end

-- Needs: the relative weights above become units an hour, so that a unit
-- of population uses SCALE credits' worth an hour at normal prices,
-- split between the classes in proportion to the weights.
do
  local weight = 0
  for _, g in goods do
    weight += g.need
  end
  for _, g in goods do
    g.need = g.need / weight * SCALE / g.par
  end
end

Goods.list = goods
Goods.index = index
Goods.steps = steps
Goods.SCALE = SCALE

-- The index of a class by id.
function Goods.Index(id: string): number
  return assert(index[id], `no class of goods '{id}'`)
end

-- The classes as the economy wants them.
function Goods.Classes(): { Economy.Class }
  local classes: { Economy.Class } = {}
  for _, g in goods do
    table.insert(classes, { id = g.id, par = g.par, cover = COVER[g.tier], need = g.need, bulk = BULK[g.tier] })
  end
  return classes
end

-- The recipes as the economy wants them, one per step and in the same
-- order: recipe i is steps[i].
function Goods.Recipes(): { Economy.Recipe }
  local recipes: { Economy.Recipe } = {}
  for _, step in steps do
    local inputs: { Economy.Amount } = {}
    -- in class order, so the arithmetic is the same every time
    for g, class in goods do
      local amount = step.inputs[class.id]
      if amount then
        table.insert(inputs, { class = g, amount = amount })
      end
    end
    -- The margin this way of making it earns at normal prices: the
    -- standard one for the step that set the price, and whatever the
    -- inputs leave for any other.
    local made = goods[index[step.makes]]
    local margin = Goods.MARGIN
    if #inputs > 0 then
      local cost = 0
      for _, input in inputs do
        cost += input.amount * goods[input.class].par
      end
      margin = made.par / (cost * (1 + LABOUR[made.tier])) - 1
    end
    table.insert(recipes, {
      id = step.id, inputs = inputs, outputs = { { class = index[step.makes], amount = 1 } }, margin = margin,
    })
  end
  return recipes
end

-- How much of every class must be made an hour, and how many runs an
-- hour of every step that takes, for people to have 'used' (units an
-- hour of each class, by class index): what they use, plus what goes
-- into making it, all the way down. Returns the two lists, by class
-- index and by step index.
function Goods.Required(used: { number }): ({ number }, { number })
  local required = table.clone(used)
  local runs: { number } = table.create(#steps, 0)
  for at = #steps, 1, -1 do
    local step = steps[at]
    runs[at] = required[index[step.makes]] * (step.share or 1)
    for id, amount in step.inputs do
      required[index[id]] += runs[at] * amount
    end
  end
  return required, runs
end

return Goods
