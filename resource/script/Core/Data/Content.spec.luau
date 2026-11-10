--!strict
-- The item database as a whole: that the yards' lines are complete and
-- make sense, and that everything in them can be flown and built.

local Blueprints = require("@lt/Core/Data/Blueprints")
local Modules = require("@lt/Core/Data/Modules")
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

suite:Case("every weapon takes ammunition of its own size and no other; larger reaches further and tracks worse", function(t)
  local weapons = 0
  for _, module in Modules.list do
    local weapon = module.weapon
    if weapon then
      weapons += 1
      local fits = 0
      for _, charge in Modules.charges do
        if charge.family == weapon.family and charge.size == weapon.size then
          fits += 1
        end
      end
      t.ok(fits >= 3, `{module.id} has {fits} kinds of ammunition`)
      t.ok(#Skills.Needs(module.id) >= 1, `{module.id} needs no skill`)
      for _, need in Skills.Needs(module.id) do
        t.ok(Skills.byId[need.skill] ~= nil, `{module.id} needs an unknown skill {need.skill}`)
      end
    end
  end
  t.eq(weapons, 6 * 3 + 3, "six forms of turret and a launcher, in three sizes")
  for _, form in { "laser.pulse", "laser.beam", "autocannon", "artillery", "blaster", "railgun" } do
    local small, medium, large = Modules.byId[form .. ".small"], Modules.byId[form .. ".medium"], Modules.byId[form .. ".large"]
    for _, pair in { { small, medium }, { medium, large } } do
      local a, b = assert(pair[1].weapon), assert(pair[2].weapon)
      t.ok(b.optimal > a.optimal and b.tracking < a.tracking, pair[2].id)
      t.ok(pair[2].powergrid > 5 * pair[1].powergrid and pair[2].basePrice > pair[1].basePrice, pair[2].id)
    end
  end
  -- a charge a size up carries more, of the same kind
  for _, charge in Modules.charges do
    local bigger = Modules.chargeById[charge.id .. ".medium"]
    if bigger then
      local largest = assert(Modules.chargeById[charge.id .. ".large"])
      t.eq(bigger.size, 2)
      t.eq(largest.size, 3)
      for index, amount in charge.damage do
        t.ok(bigger.damage[index] >= amount and largest.damage[index] >= bigger.damage[index], bigger.id)
      end
      t.ok(Blueprints.byProduct[bigger.id] ~= nil and Blueprints.byProduct[largest.id] ~= nil)
    end
  end
  for _, size in { "light", "heavy", "cruise" } do
    for _, kind in { "em", "thermal", "kinetic", "explosive" } do
      t.ok(Modules.chargeById[`missile.{size}.{kind}`] ~= nil, `no {kind} {size} missile`)
    end
  end
end)

suite:Case("every human warship can carry a full rack of its own faction's weapons, at its own size", function(t)
  local SHORT = { laser = "laser.pulse", projectile = "autocannon", hybrid = "blaster" }
  local SIZE = { frigate = 1, destroyer = 1, cruiser = 2, battleship = 3 }
  local NAME = { "small", "medium", "large" }
  local LAUNCHER = { "launcher.light", "launcher.heavy", "launcher.cruise" }
  for _, faction in Factions.list do
    if faction.kind == "human" then
      for _, hull in Ships.list do
        local size = SIZE[hull.class]
        if hull.lineage == faction.id and size then
          local turret = assert(Modules.byId[`{SHORT[faction.weapon]}.{NAME[size]}`])
          local launcher = assert(Modules.byId[LAUNCHER[size]])
          -- as many of each as it has hardpoints and high slots for, launchers first
          local launchers = math.min(hull.launchers, hull.highs)
          local turrets = math.min(hull.turrets, hull.highs - launchers)
          local cpu = turrets * turret.cpu + launchers * launcher.cpu
          local powergrid = turrets * turret.powergrid + launchers * launcher.powergrid
          t.ok(cpu <= 0.8 * hull.cpu, `{hull.id}: its weapons take {cpu} of {hull.cpu} cpu`)
          t.ok(powergrid <= 0.8 * hull.powergrid, `{hull.id}: its weapons take {powergrid} of {hull.powergrid} MW`)
          -- and the next size up is beyond it
          if size < 3 then
            local bigger = assert(Modules.byId[`{SHORT[faction.weapon]}.{NAME[size + 1]}`])
            t.ok(hull.turrets == 0 or hull.turrets * bigger.powergrid > hull.powergrid, `{hull.id} could carry {bigger.id}`)
          end
        end
      end
    end
  end
end)

return suite
