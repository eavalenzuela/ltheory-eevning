--!strict
-- The item database as a whole: that the yards' lines are complete and
-- make sense, and that everything in them can be flown and built.

local Blueprints = require("@lt/Core/Data/Blueprints")
local Components = require("@lt/Core/Data/Components")
local Modules = require("@lt/Core/Data/Modules")
local Moons = require("@lt/Core/Data/Moons")
local Ores = require("@lt/Core/Data/Ores")
local Drones = require("@lt/Core/Data/Drones")
local Attributes = require("@lt/Core/Attributes")
local Reactions = require("@lt/Core/Data/Reactions")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")
local Test = require("@lt/Tool/Test")
local Types = require("@lt/Core/Data/Types")
local Factions = require("@lt/Core/Data/Factions")
local Facts = require("@lt/Core/Data/Facts")

local suite = Test.Suite("Content")

-- Can this be had from ore: a mineral some ore yields, or a component
-- whose own blueprint takes only such things?
local function fromOre(type: string): boolean
  for _, ore in Ores.list do
    for _, yield in ore.yields do
      if yield.mineral == type then
        return true
      end
    end
  end
  if Components.byId[type] == nil then
    return false
  end
  local blueprint = Blueprints.byProduct[type]
  if blueprint == nil then
    return false
  end
  for _, material in blueprint.materials do
    if Components.byId[material.type] or not fromOre(material.type) then
      return false
    end
  end
  return true
end

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
        -- (the plain hulls: the tech 2 makes of them are their own case)
        if hull.lineage == faction.id and hull.class == class and hull.tech ~= 2 then
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

suite:Case("every hull of a human line, and each mining hull, has a tech 2 make: tougher, roomier, built of the plain hull, and nobody's to buy", function(t)
  local improved = 0
  for _, hull in Ships.list do
    local faction = Factions.byId[hull.lineage]
    if hull.tech == 2 then
      improved += 1
      local base = Ships.byId[hull.base :: string]
      t.eq({ hull.id, hull.name, hull.class, hull.lineage } :: { any }, { base.id .. ".ii", base.name .. " II", base.class, base.lineage } :: { any })
      t.eq(Ships.Improved(base.id), hull)
      t.ok(base.tech == nil and Ships.Improved(hull.id) == nil, "a tech 2 hull has no tech 2 make of its own")
      -- The same hull to look at and to arm: its hardpoints, its size, its drones.
      t.eq({ hull.turrets, hull.launchers, hull.highs, hull.radius, hull.mass, hull.drones, hull.bay } :: { any },
        { base.turrets, base.launchers, base.highs, base.radius, base.mass, base.drones, base.bay } :: { any })
      -- More of it to shoot through, and less of every shot gets through.
      t.ok(hull.shield > 1.25 * base.shield and hull.armor > 1.25 * base.armor and hull.hull > 1.25 * base.hull, hull.id)
      for index = 1, 4 do
        t.near(hull.shieldResonance[index], base.shieldResonance[index] * 0.75, 1e-9)
        t.near(hull.armorResonance[index], base.armorResonance[index] * 0.75, 1e-9)
        t.eq(hull.hullResonance[index], base.hullResonance[index])
      end
      -- More to fit with, and one slot more: low on a hull that is more armour than shield, else mid.
      t.ok(hull.cpu > 1.15 * base.cpu and hull.powergrid > 1.15 * base.powergrid and hull.capacitor > 1.15 * base.capacitor, hull.id)
      t.eq({ hull.mids - base.mids, hull.lows - base.lows }, if base.armor >= base.shield then { 0, 1 } else { 1, 0 }, hull.id)
      t.ok(hull.maxVelocity >= base.maxVelocity and hull.lockRange > base.lockRange and hull.scanResolution > base.scanResolution)
      -- What carries, carries half as much again; a warship's hold is as it was.
      local carrier = base.class == "industrial" or base.id == "frigate.prospector" or base.id == "barge.quarry"
      t.near(hull.cargo / base.cargo, if carrier then 1.5 else 1, 0.03, hull.id)
      t.eq(hull.basePrice, base.basePrice * 8)
      -- More skill than the plain one, and never less than four of it.
      local needs, plain = Skills.Needs(hull.id), Skills.Needs(base.id)
      t.ok(#needs >= 1 and #needs == #plain, hull.id)
      for index, need in needs do
        t.ok(need.level >= 4 and need.level <= 5 and need.skill == plain[index].skill and need.level > plain[index].level, hull.id)
      end
      -- No station has one to sell, nor its blueprint; it is built of the plain hull, components and what lawless space has.
      local blueprint = assert(Blueprints.byProduct[hull.id], `no blueprint for {hull.id}`)
      t.eq({ Types.Info(hull.id).scarce, Types.Info(blueprint.id).scarce, blueprint.invented } :: { any }, { true, true, true } :: { any })
      t.eq({ blueprint.materials[1].type, blueprint.materials[1].quantity } :: { any }, { base.id, 1 } :: { any })
      local rare, components, moon = 0, 0, 0
      -- (and of what a reactor makes of what is drilled out of moons: one composite, of the grade for a hull its size)
      local grade = if hull.class == "battleship" or hull.class == "freighter" then 3
        elseif hull.class == "frigate" or hull.class == "destroyer" then 1 else 2
      for index, material in blueprint.materials do
        local reacted = Reactions.byId[material.type]
        t.eq(Moons.byId[material.type], nil, `{blueprint.id} should be built of nothing as it comes out of a moon`)
        if reacted then
          moon += 1
          t.eq(reacted.grade, grade, `{material.type} in {blueprint.id}`)
        elseif index > 1 then
          t.ok(fromOre(material.type), `{material.type} in {blueprint.id} comes from no ore`)
          components += if Components.byId[material.type] then 1 else 0
          rare += if material.type == "mineral.iridium" or material.type == "mineral.cobalt" then 1 else 0
        end
      end
      t.ok(components >= 5 and rare == 2, `{hull.id} is built of {components} components and {rare} rare minerals`)
      t.eq(moon, 1, `{hull.id} should call for one composite`)
    else
      -- (and every hull that should have one, has)
      local should = hull.id == "frigate.prospector" or hull.id == "barge.quarry"
        or (faction ~= nil and faction.kind == "human" and not hull.restricted)
      t.eq(Ships.Improved(hull.id) ~= nil, should, hull.id)
      t.eq(Types.Get(hull.id) == nil or Types.Info(hull.id).scarce == nil, true, hull.id)
    end
  end
  -- Four lines of five hulls, and the two that mine.
  t.eq(improved, 4 * 5 + 2)
  t.ok(Ships.Improved("frigate.courier") == nil and Ships.Improved("industrial.hauler") == nil and Ships.Improved("capsule") == nil)
end)

suite:Case("every hull for sale can be built from ore, and has skills a pilot can train", function(t)
  for _, hull in Ships.list do
    if hull.class ~= "capsule" and not hull.restricted and hull.tech ~= 2 then
      t.ok(Types.Get(hull.id) ~= nil, hull.id)
      local blueprint = assert(Blueprints.byProduct[hull.id], `no blueprint for {hull.id}`)
      t.ok(#blueprint.materials >= 2, hull.id)
      -- A hull is components and minerals together, and every one of
      -- them comes, in the end, out of a rock.
      local components, minerals = 0, 0
      for _, material in blueprint.materials do
        t.ok(material.quantity >= 1)
        if Components.byId[material.type] then
          components += 1
        else
          minerals += 1
        end
        t.ok(fromOre(material.type), `{material.type} in {blueprint.id} comes from no ore`)
      end
      t.ok(components >= 5 and minerals >= 3, `{hull.id} is built of {components} components and {minerals} minerals`)
      local function takes(mineral: string): boolean
        for _, material in blueprint.materials do
          if material.type == mineral then
            return true
          end
        end
        return false
      end
      -- (a freighter is as much metal as a battleship, and of the same kinds)
      local great = hull.class == "battleship" or hull.class == "freighter"
      t.eq(takes("mineral.cobalt"), hull.class == "cruiser" or hull.class == "barge" or great, hull.id)
      t.eq(takes("mineral.iridium"), great, hull.id)
      for _, need in Skills.Needs(hull.id) do
        t.ok(Skills.byId[need.skill] ~= nil, `{hull.id} needs an unknown skill {need.skill}`)
        t.ok(need.level >= 1 and need.level <= Skills.MAX_LEVEL)
      end
      t.ok(hull.class == "frigate" and hull.lineage == "" and hull.id == "frigate.courier" or #Skills.Needs(hull.id) >= 1,
        `{hull.id} needs no skill at all`)
    end
  end
  -- the ladder of hull skills can be climbed from a new pilot's own
  for _, id in { "destroyers", "cruisers", "battleships", "industrials", "freighters" } do
    for _, need in Skills.byId[id].requires do
      t.ok(Skills.byId[need.skill] ~= nil)
    end
  end
end)

suite:Case("a freighter is a hold and nothing else: ten times a hauler's, nothing to fight with, slow, and a skill of its own", function(t)
  local dray, mule, bastion = Ships.byId["freighter.dray"], Ships.byId["industrial.hauler"], Ships.byId["battleship.bastion"]
  t.eq({ dray.class, dray.lineage, dray.restricted, dray.tech } :: { any }, { "freighter", "", nil, nil } :: { any })
  t.ok(dray.cargo >= 10 * mule.cargo, `a freighter holds {dray.cargo} m3 and a hauler {mule.cargo}`)
  -- Nothing to fight with, nowhere to put it, and no rigs: a few low slots are all there is to fit.
  t.eq({ dray.highs, dray.mids, dray.turrets, dray.launchers, dray.rigs, dray.drones, dray.bay } :: { any }, { 0, 0, 0, 0, 0, 0, 0 } :: { any })
  t.ok(dray.lows >= 1)
  t.eq({ Attributes.Check(dray, { "autocannon.small" }) } :: { any }, { false, "no free high slot" } :: { any })
  t.eq({ Attributes.Check(dray, { "rig.cargo.large" }) } :: { any }, { false, "no free rig slot" } :: { any })
  t.ok((Attributes.Check(dray, { "cargo.expander" })))
  -- Slower than anything else there is to fly: to turn, to go, and in warp. And mostly hull.
  t.ok(Ships.TimeConstant(dray) > 2 * Ships.TimeConstant(bastion) and Ships.TimeConstant(dray) > 2 * Ships.TimeConstant(mule))
  t.ok(dray.maxVelocity < bastion.maxVelocity and dray.warpSpeed < bastion.warpSpeed and dray.warpSpeed < mule.warpSpeed)
  t.ok(dray.hull > dray.shield + dray.armor)
  -- Bought and built like any hull, of what a battleship is built of, by a pilot with the skill for it,
  -- which is at the far end of the haulers'.
  local info = Types.Info(dray.id)
  t.eq({ info.category, info.scarce } :: { any }, { "ship", nil } :: { any })
  t.ok(dray.basePrice > 50 * mule.basePrice and dray.basePrice < bastion.basePrice)
  t.ok(Blueprints.byProduct[dray.id] ~= nil)
  t.eq(Skills.Needs(dray.id), { { skill = "freighters", level = 1 } })
  t.eq(Skills.byId["freighters"].requires, { { skill = "industrials", level = 4 } })
end)

suite:Case("every weapon takes ammunition of its own size and no other; larger reaches further and tracks worse", function(t)
  local weapons = 0
  for _, module in Modules.list do
    local weapon = module.weapon
    -- (the plain ones: each has a custom and a tech 2 make, which are their own cases)
    if weapon and module.tech ~= 2 and module.meta == nil then
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
          -- and the same rack a size up is beyond it (the whole rack: on a
          -- hull that is mostly launchers, the one gun alone proves nothing)
          if size < 3 then
            local bigger = assert(Modules.byId[`{SHORT[faction.weapon]}.{NAME[size + 1]}`])
            local biggerLauncher = assert(Modules.byId[LAUNCHER[size + 1]])
            local cpuUp = turrets * bigger.cpu + launchers * biggerLauncher.cpu
            local powergridUp = turrets * bigger.powergrid + launchers * biggerLauncher.powergrid
            t.ok(cpuUp > hull.cpu or powergridUp > hull.powergrid, `{hull.id} could carry its rack a size up`)
          end
        end
      end
    end
  end
end)

suite:Case("components are made from minerals, and modules from components and minerals", function(t)
  t.eq(#Components.list, 8)
  for _, component in Components.list do
    t.ok(Types.Info(component.id).category == "component")
    t.ok(fromOre(component.id), `{component.id} cannot be made from ore`)
    local share = 0
    for _, part in component.mix do
      share += part
    end
    t.near(share, 1, 1e-9, component.id)
  end
  local hullShare = 0
  for _, part in Components.HULL do
    t.ok(Components.byId[part[1]] ~= nil)
    hullShare += part[2]
  end
  t.near(hullShare, 1, 1e-9)
  for _, module in Modules.list do
    -- (a custom make is found and not built: its own case)
    if module.meta then
      continue
    end
    local blueprint = assert(Blueprints.byProduct[module.id], module.id)
    if module.slot == "rig" then
      -- (a rig is made of what is salvaged, and nothing else: three kinds, twenty pieces for a small one,
      -- three times as many for a medium, and three times that for a large)
      local pieces = 0
      for _, material in blueprint.materials do
        t.ok(string.sub(material.type, 1, 8) == "salvage.", `{material.type} in {blueprint.id}`)
        pieces += material.quantity
      end
      t.eq({ #blueprint.materials, pieces }, { 3, 20 * ({ 1, 3, 9 })[Modules.SizeOf(module)] }, module.id)
      -- (and a sized one is the small one of its kind, of more of the same)
      local small = Modules.byId[(string.gsub((string.gsub(module.id, "%.medium$", "")), "%.large$", ""))]
      t.eq({ module.passive, module.calibration, blueprint.materials[1].type } :: { any },
        { small.passive, small.calibration, Blueprints.byProduct[small.id].materials[1].type } :: { any })
      t.eq(module.basePrice, small.basePrice * ({ 1, 3, 9 })[Modules.SizeOf(module)])
    else
      local components, minerals, moon = 0, 0, 0
      for index, material in blueprint.materials do
        if module.tech == 2 and index == 1 then
          -- (a tech 2 module is built of the plain one, which is built of ore)
          t.eq({ material.type, material.quantity } :: { any }, { module.base, 1 } :: { any })
          continue
        end
        -- (and of one thing a reactor makes of what is drilled out of
        -- moons, which nothing plain is; and of nothing as it comes up)
        t.eq(Moons.byId[material.type], nil, `{material.type} in {blueprint.id}`)
        if Reactions.byId[material.type] then
          moon += 1
          continue
        end
        if Components.byId[material.type] then
          components += 1
        else
          minerals += 1
        end
        t.ok(fromOre(material.type), `{material.type} in {blueprint.id}`)
      end
      t.ok(components >= 1 and minerals >= 2, module.id)
      t.eq(moon, if module.tech == 2 then 1 else 0, `{module.id} and what is made of what is drilled out of moons`)
    end
  end
  -- what is fired is still made straight from minerals
  for _, charge in Modules.charges do
    for _, material in assert(Blueprints.byProduct[charge.id]).materials do
      t.ok(Components.byId[material.type] == nil, charge.id)
    end
  end
  -- the rare ores are found only in lawless space
  local safe, wild = 0, 0
  for step = 0, 999 do
    local roll = (step + 0.5) / 1000
    if Ores.Pick(roll).share == 0 then
      safe += 1
    end
    if Ores.Pick(roll, true).share == 0 then
      wild += 1
    end
  end
  t.eq(safe, 0)
  t.ok(wild >= 130 and wild <= 150, `{wild} rocks in a thousand`)
end)

suite:Case("every weapon, repairer, extender, plate and mining laser has a tech 2 make: better, dearer to fit, and nobody's to buy", function(t)
  local improved = 0
  for _, module in Modules.list do
    if module.tech == 2 then
      improved += 1
      local base = Modules.byId[module.base :: string]
      t.eq({ module.id, module.name, module.slot, module.hardpoint } :: { any },
        { base.id .. ".ii", base.name .. " II", base.slot, base.hardpoint } :: { any })
      t.eq(Modules.Improved(base.id), module)
      t.ok(module.cpu >= base.cpu and module.powergrid >= base.powergrid and module.basePrice == base.basePrice * 8)
      if module.weapon and base.weapon then
        t.near(module.weapon.damageMultiplier, base.weapon.damageMultiplier * 1.2, 1e-9)
        t.eq({ module.weapon.family, module.weapon.size } :: { any }, { base.weapon.family, base.weapon.size } :: { any })
      elseif module.repair and base.repair then
        t.near(module.repair.amount, base.repair.amount * 1.25, 1e-9)
      elseif module.miner and base.miner then
        t.near(module.miner.volume, base.miner.volume * 1.25, 1e-9)
      elseif module.hex and base.hex then
        -- (a repairer for another ship: more put back, from as far)
        t.near(module.hex.strength, base.hex.strength * 1.25, 1e-9)
        t.eq({ module.hex.kind, module.hex.range } :: { any }, { base.hex.kind, base.hex.range } :: { any })
      end
      -- (what only a drone carries is what only a tech 2 drone carries)
      t.eq(module.internal, base.internal)
      -- More skill than the plain one, and never less than four of it.
      local needs, plain = Skills.Needs(module.id), Skills.Needs(base.id)
      t.ok(#needs >= 1 and #needs >= #plain)
      for index, need in needs do
        t.ok(need.level >= 4 and need.level <= 5 and Skills.byId[need.skill] ~= nil)
        if plain[index] then
          t.ok(need.skill == plain[index].skill and need.level > plain[index].level, module.id)
        end
      end
      -- No station has one to sell, nor its blueprint.
      t.eq({ Types.Info(module.id).scarce, Types.Info("blueprint." .. module.id).scarce, Blueprints.byProduct[module.id].invented } :: { any },
        { true, true, true } :: { any })
    elseif module.meta == nil then
      -- (what only a drone carries is nobody's to buy either)
      t.eq({ module.base, Types.Info(module.id).scarce } :: { any }, { nil, if module.internal then true else nil } :: { any })
      -- (and has a tech 2 make, for a tech 2 drone, and no custom one)
      t.ok(not module.internal or (Modules.Improved(module.id) ~= nil and Modules.Custom(module.id) == nil), module.id)
    end
  end
  -- 21 weapons, 2 repairers, an extender and a plate in three sizes each, two mining lasers and a gas harvester,
  -- the repairers for another ship (shield and armour, in three sizes), and the two things only a drone carries.
  t.eq(improved, 21 + 4 * 3 + 3 + 2 * 3 + 2)
  t.ok(Modules.Improved("projector.entanglement") == nil and Modules.Improved("rig.shield") == nil)
  t.eq({ Modules.SizeOf(Modules.byId["autocannon.medium.ii"]), Modules.SizeOf(Modules.byId["shield.extender.large"]),
    Modules.SizeOf(Modules.byId["miner.small"]) }, { 2, 3, 1 })
end)

suite:Case("the same modules have a custom make, between the plain one and tech 2, and a masterwork past it: easier to fit, and only ever found", function(t)
  local customs, masterworks = 0, 0
  for _, module in Modules.list do
    if module.meta then
      local master = module.meta == 2
      customs += if master then 0 else 1
      masterworks += if master then 1 else 0
      local base = Modules.byId[module.base :: string]
      local better = assert(Modules.Improved(base.id), `{base.id} has a custom make and no tech 2 make`)
      t.eq({ module.id, module.name, module.slot, module.hardpoint, module.tech } :: { any },
        { base.id .. (if master then ".master" else ".custom"), base.name .. (if master then " Masterwork" else " Custom"), base.slot,
          base.hardpoint, nil } :: { any })
      t.eq(if master then Modules.Masterwork(base.id) else Modules.Custom(base.id), module)
      t.ok(Modules.Custom(module.id) == nil and Modules.Improved(module.id) == nil and Modules.Masterwork(module.id) == nil,
        "a custom make has no better make of its own")
      -- What a pirate of a grade fits of it: the custom make a veteran, the masterwork a captain.
      t.eq({ Modules.Graded(base.id, 0), Modules.Graded(base.id, 1), Modules.Graded(base.id, 2) },
        { base.id, base.id .. ".custom", base.id .. ".master" })
      -- Easier to fit than the plain one, and worth more; a custom make does less than tech 2, and a masterwork more.
      t.ok(module.cpu <= base.cpu and module.powergrid <= base.powergrid and module.cpu >= 1 and module.powergrid >= 1, module.id)
      t.ok(module.cpu < base.cpu or module.powergrid < base.powergrid or base.cpu + base.powergrid <= 2, module.id)
      t.eq(module.basePrice, base.basePrice * (if master then 20 else 3))
      local damage, amount = if master then 1.25 else 1.1, if master then 1.35 else 1.125
      local function placed(mine: number, theirs: number)
        t.ok(if master then mine > theirs else mine < theirs, `{module.id} against the tech 2 make`)
      end
      if module.weapon and base.weapon and better.weapon then
        t.near(module.weapon.damageMultiplier, base.weapon.damageMultiplier * damage, 1e-9)
        placed(module.weapon.damageMultiplier, better.weapon.damageMultiplier)
        t.eq({ module.weapon.family, module.weapon.size } :: { any }, { base.weapon.family, base.weapon.size } :: { any })
      elseif module.repair and base.repair and better.repair then
        t.near(module.repair.amount, base.repair.amount * amount, 1e-9)
        placed(module.repair.amount, better.repair.amount)
      elseif module.miner and base.miner and better.miner then
        t.near(module.miner.volume, base.miner.volume * amount, 1e-9)
        placed(module.miner.volume, better.miner.volume)
      elseif module.hex and base.hex and better.hex then
        t.near(module.hex.strength, base.hex.strength * amount, 1e-9)
        placed(module.hex.strength, better.hex.strength)
      end
      t.ok(not base.internal, "what only a drone carries has a custom make")
      -- No more skill than the plain one.
      t.eq(Skills.Needs(module.id), Skills.Needs(base.id))
      -- Nobody sells one, and there are no drawings for it.
      t.eq({ Types.Info(module.id).scarce, Blueprints.byProduct[module.id], Types.Get("blueprint." .. module.id) } :: { any },
        { true, nil, nil } :: { any })
    end
  end
  -- One of each for every module that has a tech 2 make and is not a drone's own.
  t.eq({ customs, masterworks }, { 21 + 4 * 3 + 3 + 2 * 3, 21 + 4 * 3 + 3 + 2 * 3 })
  t.ok(Modules.Custom("projector.entanglement") == nil and Modules.Custom("autocannon.small.ii") == nil)
  t.ok(Modules.Masterwork("projector.entanglement") == nil and Modules.Masterwork("autocannon.small.custom") == nil)
  t.eq({ Modules.Graded("projector.entanglement", 2), Modules.Graded("autocannon.small", 3) }, { "projector.entanglement", "autocannon.small" })
  t.eq(Modules.SizeOf(Modules.byId["autocannon.medium.custom"]), 2)
end)

suite:Case("every charge has a tech 2 make: better at what the plain one is for and worse at something else, for a tech 2 weapon only, and nobody's to buy", function(t)
  local improved, plain = 0, 0
  local trades: { [string]: number } = {}
  for _, charge in Modules.charges do
    if charge.tech == 2 then
      improved += 1
      local base = Modules.chargeById[charge.base :: string]
      t.eq({ charge.id, charge.name, charge.family, charge.size, charge.volume } :: { any },
        { base.id .. ".ii", base.name .. " II", base.family, base.size, base.volume } :: { any })
      t.eq(Modules.ImprovedCharge(base.id), charge)
      t.ok(base.tech == nil and Modules.ImprovedCharge(charge.id) == nil)
      -- What it gives, and what it takes, by what the plain one is for: more damage, range, tracking or blast.
      local more: { number }, kind
      if base.family == "missile" then
        -- (a quarter harder, with a wider blast: less of it lands on what is small)
        more, kind = { 1.25, 1, 1, 1.3 }, "missile"
      elseif base.rangeMultiplier < 0.8 then
        more, kind = { 1.25, 1, 0.75, 1 }, "short"
      elseif base.rangeMultiplier > 1.3 then
        more, kind = { 1.10, 1.25, 0.8, 1 }, "long"
      else
        more, kind = { 1.05, 0.85, 1.3, 1 }, "middle"
      end
      trades[kind] = (trades[kind] or 0) + 1
      for index = 1, 4 do
        t.near(charge.damage[index], base.damage[index] * more[1], 1e-9)
      end
      t.near(charge.rangeMultiplier, base.rangeMultiplier * more[2], 1e-9, charge.id)
      t.eq(charge.tracking, if base.family == "missile" then nil else more[3], charge.id)
      t.near(charge.explosionRadius, base.explosionRadius * more[4], 1e-9)
      -- (every one is better at something and worse at something)
      local better = more[1] > 1 or more[2] > 1 or more[3] > 1
      local worse = more[2] < 1 or more[3] < 1 or more[4] > 1
      t.ok(better and worse, charge.id)
      -- (a missile flies as the plain one does)
      t.eq({ charge.velocity, charge.flightTime, charge.explosionVelocity }, { base.velocity, base.flightTime, base.explosionVelocity })
      t.ok(string.find(assert(Facts.Of(charge.id)).note, "Only a tech 2 weapon takes it", 1, true) ~= nil)
      t.eq(charge.basePrice, base.basePrice * 5)
      -- Nobody sells it or its blueprint; it is built of the plain charge, as many as are made, and the rare minerals.
      local blueprint = assert(Blueprints.byProduct[charge.id], charge.id)
      t.eq({ Types.Info(charge.id).scarce, Types.Info(blueprint.id).scarce, blueprint.invented } :: { any }, { true, true, true } :: { any })
      t.eq({ blueprint.materials[1].type, blueprint.materials[1].quantity, blueprint.perRun } :: { any },
        { base.id, blueprint.perRun, if charge.family == "laser" then 1 else 100 } :: { any })
      local rare = 0
      for index, material in blueprint.materials do
        rare += if index > 1 and (material.type == "mineral.cobalt" or material.type == "mineral.iridium") then 1 else 0
      end
      t.eq(rare, 2, charge.id)
    else
      plain += 1
      t.eq({ charge.base, charge.tracking, Types.Info(charge.id).scarce } :: { any }, { nil, nil, nil } :: { any })
      t.ok(Modules.ImprovedCharge(charge.id) ~= nil, `{charge.id} has no tech 2 make`)
    end
  end
  t.ok(improved == plain and plain >= 30, `{plain} plain charges and {improved} tech 2`)
  -- (there is every kind of trade to be had)
  t.ok((trades.short or 0) > 0 and (trades.middle or 0) > 0 and (trades.long or 0) > 0 and (trades.missile or 0) > 0)
end)

suite:Case("every drone has a tech 2 make: a tougher, quicker hull with the tech 2 make of what it carries, for a pilot with Drones 4", function(t)
  local improved = 0
  for _, drone in Drones.list do
    if drone.tech == 2 then
      improved += 1
      local base = Drones.byId[drone.base :: string]
      t.eq({ drone.id, drone.name, drone.role, drone.volume, drone.charge, drone.level, base.level } :: { any },
        { base.id .. ".ii", base.name .. " II", base.role, base.volume, base.charge, 4, 1 } :: { any })
      t.eq(Drones.Improved(base.id), drone)
      t.ok(Drones.Improved(drone.id) == nil)
      t.eq(drone.basePrice, base.basePrice * 5)
      -- What it carries is the tech 2 make of what the plain one carries.
      local gun, was = Modules.byId[drone.gun], Modules.byId[base.gun]
      t.eq({ gun.tech, gun.base } :: { any }, { 2, was.id } :: { any })
      -- What it flies as: more of it, a quarter less getting through, a tenth quicker; a drone's hull still.
      local hull, plain = Ships.byId[drone.hull], Ships.byId[base.hull]
      t.eq({ hull.class, hull.restricted, hull.tech, hull.turrets, hull.radius } :: { any }, { "drone", true, nil, plain.turrets, plain.radius } :: { any })
      t.ok(hull.shield > 1.2 * plain.shield and hull.armor > 1.2 * plain.armor and hull.hull > 1.2 * plain.hull, hull.id)
      t.near(hull.armorResonance[1], plain.armorResonance[1] * 0.75, 1e-9)
      t.ok(hull.maxVelocity > 1.05 * plain.maxVelocity and hull.cpu > plain.cpu and hull.powergrid > plain.powergrid)
      t.ok(Types.Get(hull.id) == nil, "a drone's hull is not a thing to hold")
      -- (and what it carries fits it)
      t.ok(Attributes.Check(hull, { gun.id }), `{gun.id} does not fit {hull.id}`)
      -- Nobody sells it or its blueprint; it is built of the plain drone.
      local blueprint = assert(Blueprints.byProduct[drone.id], drone.id)
      t.eq({ Types.Info(drone.id).scarce, Types.Info(blueprint.id).scarce, blueprint.invented } :: { any }, { true, true, true } :: { any })
      t.eq({ blueprint.materials[1].type, blueprint.materials[1].quantity } :: { any }, { base.id, 1 } :: { any })
    else
      t.eq({ drone.base, drone.level, Types.Info(drone.id).scarce } :: { any }, { nil, 1, nil } :: { any })
    end
  end
  t.eq(improved, 4)
end)

suite:Case("fittings come in three sizes, each for a larger ship than the last", function(t)
  for _, family in { "shield.extender", "shield.booster", "armor.plate", "armor.repairer", "afterburner", "capacitor.battery" } do
    local medium = assert(Modules.byId[family .. ".medium"])
    local large = assert(Modules.byId[family .. ".large"])
    t.ok(large.powergrid > 5 * medium.powergrid and large.basePrice > medium.basePrice, family)
    t.ok(string.find(medium.name, "Medium") ~= nil and string.find(large.name, "Large") ~= nil, medium.name)
    t.ok(#Skills.Needs(large.id) == 1 and Skills.byId[Skills.Needs(large.id)[1].skill] ~= nil, family)
    -- a cruiser can power a medium one and not a large; a battleship can power a large
    t.ok(medium.powergrid < 0.3 * Ships.byId["cruiser.cuirass"].powergrid, family)
    t.ok(large.powergrid > Ships.byId["cruiser.cuirass"].powergrid or family == "capacitor.battery" or family == "shield.extender"
      or family == "shield.booster", family)
    t.ok(large.powergrid < 0.3 * Ships.byId["battleship.bastion"].powergrid, family)
  end
  t.ok(assert(Modules.byId["armor.plate.large"]).passive[1].value > 8 * 520 - 1)
  t.ok(assert(assert(Modules.byId["shield.booster.large"]).repair).amount > 8 * 26)
  -- the barge carries three strip miners, each worth several mining lasers
  local barge, strip = Ships.byId["barge.quarry"], Modules.byId["miner.strip"]
  t.ok(3 * strip.cpu <= barge.cpu and 3 * strip.powergrid <= barge.powergrid and barge.turrets == 3)
  local small = assert(Modules.byId["miner.small"].miner)
  local big = assert(strip.miner)
  t.ok(big.volume / big.duration > 2 * small.volume / small.duration)
  t.ok(strip.powergrid > Ships.byId["frigate.prospector"].powergrid, "a frigate cannot power one")
end)

return suite
