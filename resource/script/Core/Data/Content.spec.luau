--!strict
-- The item database as a whole: that the yards' lines are complete and
-- make sense, and that everything in them can be flown and built.

local Blueprints = require("@lt/Core/Data/Blueprints")
local Ores = require("@lt/Core/Data/Ores")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")
local Test = require("@lt/Tool/Test")
local Types = require("@lt/Core/Data/Types")
local Factions = require("@lt/Core/Data/Factions")

local suite = Test.Suite("Content")

suite:Case("four human factions, the pirates and three alien ones, each with a look of its own", function(t)
  local kinds: { [string]: number } = {}
  local styles: { [string]: boolean } = {}
  for _, faction in Factions.list do
    kinds[faction.kind] = (kinds[faction.kind] or 0) + 1
    t.ok(not styles[faction.style], `two factions build in the {faction.style} style`)
    styles[faction.style] = true
    t.ok(Factions.byId[faction.id] == faction)
    t.ok(#faction.note > 20, faction.id)
    for _, class in Factions.CLASSES do
      t.ok(faction.hulls[class] ~= nil, `{faction.id} has no {class}`)
    end
  end
  t.eq(kinds, { human = 4, pirate = 1, alien = 3 })
end)

suite:Case("every faction has a hull of every class, and a bigger class is more of everything but nimble", function(t)
  local names: { [string]: boolean } = {}
  for _, hull in Ships.list do
    t.ok(not names[hull.name], `two hulls called {hull.name}`)
    t.ok(Ships.byId[hull.id] == hull, `two hulls with the id {hull.id}`)
    names[hull.name] = true
  end
  for _, faction in Factions.list do
    local line: { Ships.ShipType } = {}
    for _, class in Factions.CLASSES do
      local found: Ships.ShipType? = nil
      for _, hull in Ships.list do
        if hull.lineage == faction.id and hull.class == class then
          t.ok(found == nil, `{faction.id} has two {class}s`)
          found = hull
        end
      end
      local hull = assert(found, `{faction.id} builds no {class}`)
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
      -- a faction's character shows in how its warships take a hit
      if hull.class ~= "industrial" then
        if faction.tank == "armor" then
          t.ok(hull.armor > hull.shield, hull.id)
        elseif faction.tank == "shield" then
          t.ok(hull.shield > hull.armor, hull.id)
        else
          t.ok(hull.hull > hull.shield, hull.id)
        end
      end
      -- only human designs are for sale
      t.eq(Types.Get(hull.id) ~= nil, faction.kind == "human", hull.id)
      t.eq(Blueprints.byProduct[hull.id] ~= nil, faction.kind == "human", hull.id)
    end
    t.ok(line[5].cargo > 10 * line[1].cargo, "an industrial carries far more than a frigate")
  end
end)

suite:Case("every pirate hull is somebody else's, cheaper, quicker and thinner-skinned", function(t)
  local pirates = Factions.byId.unbound
  local donors = assert(pirates.donors)
  for _, class in Factions.CLASSES do
    local theirs: Ships.ShipType? = nil
    for _, hull in Ships.list do
      if hull.lineage == "unbound" and hull.class == class then
        theirs = hull
      end
    end
    local hull = assert(theirs)
    local original = assert(Ships.byId[assert(hull.donor, hull.id)], `{hull.id} was made from nothing`)
    t.eq(original.class, class)
    t.eq(original.lineage, donors[class])
    t.eq(Factions.byId[original.lineage].kind, "human")
    t.ok(hull.basePrice < original.basePrice, hull.id)
    if class ~= "industrial" then
      t.ok(hull.maxVelocity > 0.98 * original.maxVelocity, hull.id)
      t.ok(hull.turrets + hull.launchers > original.turrets + original.launchers or original.id == "frigate.harrier", hull.id)
    end
  end
end)

suite:Case("every hull for sale can be built from ore, and has skills a pilot can train", function(t)
  for _, hull in Ships.list do
    if hull.class ~= "capsule" and not hull.restricted then
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
