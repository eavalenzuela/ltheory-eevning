--!strict
-- The item database as a whole: that the yards' lines are complete and
-- make sense, and that everything in them can be flown and built.

local Blueprints = require("@lt/Core/Data/Blueprints")
local Ores = require("@lt/Core/Data/Ores")
local Powers = require("@lt/Core/Data/Powers")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")
local Test = require("@lt/Tool/Test")
local Types = require("@lt/Core/Data/Types")
local Yards = require("@lt/Core/Data/Yards")

local suite = Test.Suite("Content")

suite:Case("every power builds in a yard, two to a yard, each with its own paint", function(t)
  t.eq(#Yards.list, 4)
  local seen = 0
  for _, power in Powers.list do
    local yard = assert(Yards.Of(power.name), `{power.name} has no yard`)
    t.ok(yard.paint[power.name] ~= nil, `{power.name} has no paint`)
    seen += 1
  end
  t.eq(seen, 8)
  for _, yard in Yards.list do
    t.eq(#yard.powers, 2, yard.id)
    t.ok(Yards.byId[yard.id] == yard)
  end
end)

suite:Case("every yard has a hull of every class, and a bigger class is more of everything but nimble", function(t)
  local names: { [string]: boolean } = {}
  for _, hull in Ships.list do
    t.ok(not names[hull.name], `two hulls called {hull.name}`)
    names[hull.name] = true
  end
  for _, yard in Yards.list do
    local line: { Ships.ShipType } = {}
    for _, class in Yards.CLASSES do
      local found: Ships.ShipType? = nil
      for _, hull in Ships.list do
        if hull.lineage == yard.id and hull.class == class then
          t.ok(found == nil, `{yard.id} has two {class}s`)
          found = hull
        end
      end
      local hull = assert(found, `{yard.id} builds no {class}`)
      table.insert(line, hull)
    end
    -- the warships, smallest to largest
    for i = 2, 4 do
      local small, big = line[i - 1], line[i]
      t.ok(big.basePrice > small.basePrice and big.mass > small.mass, big.id)
      t.ok(big.shield + big.armor + big.hull > 1.5 * (small.shield + small.armor + small.hull), big.id)
      t.ok(big.maxVelocity < small.maxVelocity and big.scanResolution < small.scanResolution, big.id)
      t.ok(Ships.TimeConstant(big) > Ships.TimeConstant(small), `{big.id} turns no slower`)
      t.ok(big.signature > small.signature and big.lockRange > small.lockRange, big.id)
    end
    for _, hull in line do
      -- (a hull may have more hardpoints than high slots: the pilot chooses the mix)
      t.ok(hull.turrets <= hull.highs and hull.launchers <= hull.highs and hull.turrets + hull.launchers >= 1, hull.id)
      t.ok(hull.mids >= 1 and hull.lows >= 1, hull.id)
      -- a yard's character shows: armour yards carry more armour than shield
      if hull.class ~= "industrial" then
        if yard.tank == "armor" then
          t.ok(hull.armor > hull.shield, hull.id)
        else
          t.ok(hull.shield > hull.armor, hull.id)
        end
      end
    end
    t.ok(line[5].cargo > 20 * line[1].cargo, "an industrial carries far more than a frigate")
  end
end)

suite:Case("every hull can be bought, built from ore, and has skills a pilot can train", function(t)
  for _, hull in Ships.list do
    if hull.class ~= "capsule" then
      t.ok(Types.Get(hull.id) ~= nil, hull.id)
      local blueprint = assert(Blueprints.byProduct[hull.id], `no blueprint for {hull.id}`)
      t.ok(#blueprint.materials >= 2, hull.id)
      for _, material in blueprint.materials do
        local mined = false
        for _, ore in Ores.list do
          for _, yield in ore.yields do
            mined = mined or yield.mineral == material.type
          end
        end
        t.ok(mined, `{material.type} in {blueprint.id} comes from no ore`)
        t.ok(material.quantity >= 1)
      end
      for _, need in Skills.Needs(hull.id) do
        t.ok(Skills.byId[need.skill] ~= nil, `{hull.id} needs an unknown skill {need.skill}`)
        t.ok(need.level >= 1 and need.level <= Skills.MAX_LEVEL)
      end
      t.ok(hull.class == "frigate" and hull.lineage == "" and hull.id == "frigate.courier" or #Skills.Needs(hull.id) >= 1,
        `{hull.id} needs no skill at all`)
    end
  end
  -- the ladder of hull skills can be climbed from a new pilot's own
  for _, id in { "destroyers", "cruisers", "battleships" } do
    for _, need in Skills.byId[id].requires do
      t.ok(Skills.byId[need.skill] ~= nil)
    end
  end
end)

return suite
