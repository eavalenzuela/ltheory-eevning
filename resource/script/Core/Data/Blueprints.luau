--!strict
-- What can be built, and from what.
--
-- Every module, charge and hull has a blueprint. A run of a blueprint
-- turns minerals into the product: one module or hull, or a hundred
-- rounds. The minerals are worked out from the product's base price, so
-- that at normal prices the materials cost about 60% of what the product
-- sells for: building is worth it, and the gap pays for the blueprint
-- and the builder's time.
--
-- A blueprint is not used up; it costs ten times its product. A copy of
-- one is: a laboratory makes copies of a blueprint, good for so many
-- runs each, and a run built from a copy is a run the copy has no more
-- (Assets/Industry).
--
-- The tech 2 make of a module, a hull or a drone is built of the plain
-- one, of the parts and the rare minerals that make the difference,
-- and of what is drilled out of moons (Data/Moons): the common grade
-- for small things, the middle one for cruiser-sized, the rare for the
-- largest.

local Factions = require("@lt/Core/Data/Factions")
local Boosters = require("@lt/Core/Data/Boosters")
local Components = require("@lt/Core/Data/Components")
local Drones = require("@lt/Core/Data/Drones")
local Modules = require("@lt/Core/Data/Modules")
local Ores = require("@lt/Core/Data/Ores")
local Planets = require("@lt/Core/Data/Planets")
local Reactions = require("@lt/Core/Data/Reactions")
local Ships = require("@lt/Core/Data/Ships")
local Structures = require("@lt/Core/Data/Structures")

export type Blueprint = {
  id: string,               -- "blueprint.<product>"
  product: string,
  name: string,
  perRun: number,           -- units made by one run
  seconds: number,          -- per run
  materials: { { type: string, quantity: number } },  -- per run
  basePrice: number,        -- of the blueprint itself
  -- Nobody sells it: it is invented from another (Assets/Industry).
  invented: boolean?,
  -- Nobody sells it, and nobody invents it: a hull's that is not to be
  -- bought (Data/Ships' 'rare'). It is to be found, if at all.
  rare: boolean?,
}

local MATERIAL_SHARE = 0.6
-- A module or a hull is built from components and from minerals: this
-- share of its material cost is components.
local COMPONENT_SHARE = 0.5

-- How a product's material cost is split between minerals.
local MIX: { [string]: { [string]: number } } = {
  charge = { ["mineral.iron"] = 0.7, ["mineral.silicon"] = 0.3 },
  module = { ["mineral.iron"] = 0.5, ["mineral.silicon"] = 0.2, ["mineral.copper"] = 0.3 },
  ship = { ["mineral.iron"] = 0.45, ["mineral.silicon"] = 0.15, ["mineral.copper"] = 0.2, ["mineral.titanium"] = 0.2 },
  -- Larger hulls need what safe space does not have.
  cruiser = { ["mineral.iron"] = 0.4, ["mineral.silicon"] = 0.1, ["mineral.copper"] = 0.15, ["mineral.titanium"] = 0.2,
    ["mineral.cobalt"] = 0.15 },
  battleship = { ["mineral.iron"] = 0.35, ["mineral.silicon"] = 0.1, ["mineral.copper"] = 0.15, ["mineral.titanium"] = 0.15,
    ["mineral.cobalt"] = 0.15, ["mineral.iridium"] = 0.1 },
  -- What a tech 2 module has over the plain one is made of what only
  -- lawless space has.
  tech2 = { ["mineral.titanium"] = 0.4, ["mineral.cobalt"] = 0.4, ["mineral.iridium"] = 0.2 },
}

-- The components a module is built around, by what it is, as shares of
-- the component part of its cost.
local function moduleParts(module: Modules.ModuleType): { { any } }
  local id = module.id
  if module.weapon then
    return { { "component.weapon", 0.7 }, { "component.electronics", 0.3 } }
  elseif module.miner then
    return { { "component.weapon", 0.5 }, { "component.electronics", 0.5 } }
  elseif string.sub(id, 1, 7) == "shield." then
    return { { "component.emitter", 0.7 }, { "component.electronics", 0.3 } }
  elseif string.sub(id, 1, 6) == "armor." or id == "damage.control" then
    return { { "component.plating", 1 } }
  elseif string.sub(id, 1, 11) == "afterburner" or string.sub(id, 1, 4) == "mwd." or id == "overdrive" or id == "nanofiber" then
    return { { "component.thruster", 1 } }
  elseif string.sub(id, 1, 10) == "capacitor." then
    return { { "component.capacitor", 1 } }
  end
  return { { "component.electronics", 1 } }
end

local Blueprints = { list = {} :: { Blueprint }, byId = {} :: { [string]: Blueprint }, byProduct = {} :: { [string]: Blueprint } }

-- What a part costs: a component, something made on a planet, or what
-- a reactor makes of what is drilled out of moons.
local function priceOf(part: string): number
  local component = Components.byId[part]
  local composite = Reactions.byId[part]
  return if component then component.basePrice elseif composite then composite.basePrice else Planets.productById[part].basePrice
end

-- The parts of the tech 2 make of something that calls for what moons
-- give: the parts of the plain one, and the composite its size calls
-- for (1 small, 2 medium, 3 large: Data/Reactions), which takes 'share'
-- of what the parts cost between them (so the whole costs what it did).
-- A composite is made of both moon materials of its grade, so both are
-- wanted.
--
-- Which do (the project owner's ruling, 2026-11-12): every tech 2 hull,
-- and the tech 2 modules that are large or larger. The small and the
-- medium tech 2 modules do not, and so neither does a drone, which is a
-- small gun on a small engine.
--
-- A large module is a fifth composite by cost of parts. A hull is a
-- twenty-fifth: it costs so much more than what is fitted to it that a
-- fifth of a battleship would be more than a tower brings up in a week.
local MOON_SHARE, MOON_HULL = 0.2, 0.04
local function advanced(parts: { { any } }, size: number, share: number): { { any } }
  local all: { { any } } = {}
  for _, part in parts do
    table.insert(all, { part[1], part[2] * (1 - share) })
  end
  table.insert(all, { Reactions.For(size).id :: any, share })
  return all
end

-- How big a module is, for that: by its weapon's size, or by its name.
local function moduleSize(module: Modules.ModuleType): number
  if string.find(module.id, ".large", 1, true) then
    return 3
  elseif string.find(module.id, ".medium", 1, true) then
    return 2
  end
  return if module.weapon then module.weapon.size else 1
end
-- (the size from which a tech 2 module calls for a composite)
local LARGE = 3
local HULL_SIZE: { [string]: number } = { frigate = 1, destroyer = 1, cruiser = 2, industrial = 2, barge = 2, attackbattlecruiser = 2,
  battlecruiser = 2, battleship = 3, freighter = 3, carrier = 3, dreadnought = 3, siegedreadnought = 3, capitalindustrial = 3,
  supercarrier = 3, ultracapital = 3 }

-- 'mix' is how the mineral part of the cost is split; 'parts', if
-- given, the components (and what is made on planets) that take
-- COMPONENT_SHARE of it first.
local function add(product: string, name: string, mix: { [string]: number }, basePrice: number, perRun: number, seconds: number,
  parts: { { any } }?)
  local materials = {}
  local budget = MATERIAL_SHARE * basePrice * perRun
  if parts then
    for _, part in parts do
      local quantity = math.max(1, math.floor(COMPONENT_SHARE * budget * part[2] / priceOf(part[1]) + 0.5))
      table.insert(materials, { type = part[1], quantity = quantity })
    end
    budget *= 1 - COMPONENT_SHARE
  end
  -- In mineral order, so every blueprint lists them the same way.
  for _, mineral in Ores.minerals do
    local share = mix[mineral.id]
    if share then
      local quantity = math.max(1, math.floor(budget * share / mineral.basePrice + 0.5))
      table.insert(materials, { type = mineral.id, quantity = quantity })
    end
  end
  local blueprint: Blueprint = {
    id = "blueprint." .. product, product = product, name = name .. " Blueprint", perRun = perRun,
    seconds = seconds, materials = materials, basePrice = basePrice * perRun * 10,
  }
  table.insert(Blueprints.list, blueprint)
  Blueprints.byId[blueprint.id] = blueprint
  Blueprints.byProduct[product] = blueprint
end

-- Components first: everything else is built from them. They are made
-- ten to a run.
for _, component in Components.list do
  add(component.id, component.name, component.mix, component.basePrice, 10, 60 + component.basePrice // 5)
end

-- A rig is built of what is salvaged from wrecks (Tactical/Combat), and
-- nothing else: ten of the kind of salvage it is mostly made of, six of
-- the next and four of the third, which is which going round with the
-- rigs so that all three kinds are wanted.
local SALVAGE = { "salvage.plates", "salvage.circuits", "salvage.conduits" }
local rigs = 0
for _, module in Modules.list do
  if module.slot == "rig" then
    -- (a medium or a large rig is the small one of its kind, of more of the same)
    local work = Modules.RigWork(module)
    rigs += if work == 1 then 1 else 0
    local materials = {}
    for index, count in { 10, 6, 4 } do
      table.insert(materials, { type = SALVAGE[(rigs + index - 2) % 3 + 1], quantity = count * work })
    end
    local blueprint: Blueprint = {
      id = "blueprint." .. module.id, product = module.id, name = module.name .. " Blueprint", perRun = 1, seconds = 600,
      materials = materials, basePrice = module.basePrice * 10,
      -- (a people's own make is built from drawings nobody sells)
      rare = if module.lineage then true else nil,
    }
    table.insert(Blueprints.list, blueprint)
    Blueprints.byId[blueprint.id] = blueprint
    Blueprints.byProduct[module.id] = blueprint
  elseif module.meta then
    -- (a custom make is nobody's to build: there are no drawings for it)
    continue
  elseif module.tech == 2 and module.base then
    -- A tech 2 module is built of the plain one, and of what makes the
    -- difference: components and the rare minerals, and for a large
    -- one a composite. Its blueprint is not for sale.
    local base = Modules.byId[module.base]
    local size = moduleSize(module)
    add(module.id, module.name, MIX.tech2, module.basePrice - base.basePrice, 1, 600 + module.basePrice // 100,
      if size >= LARGE then advanced(moduleParts(module), size, MOON_SHARE) else moduleParts(module))
    local blueprint = Blueprints.byProduct[module.id]
    table.insert(blueprint.materials, 1, { type = base.id, quantity = 1 })
    blueprint.basePrice = module.basePrice * 10
    blueprint.invented = true
  else
    add(module.id, module.name, MIX.module, module.basePrice, 1, 120 + module.basePrice // 100, moduleParts(module))
    -- (what only a drone carries is built into the drone: nobody sells
    -- the drawings for it apart)
    if module.internal then
      Blueprints.byProduct[module.id].invented = true
    end
    -- (and a people's own make is built from drawings nobody sells)
    if module.lineage then
      Blueprints.byProduct[module.id].rare = true
    end
  end
end
for _, charge in Modules.charges do
  -- Crystals are made one at a time; rounds and missiles by the hundred.
  local perRun = if charge.family == "laser" then 1 else 100
  local plain = if charge.tech == 2 and charge.base then Modules.chargeById[charge.base] else nil
  if plain then
    -- A tech 2 charge is built of the plain one, as many as are made,
    -- and of the rare minerals. Its blueprint is not for sale.
    add(charge.id, charge.name, MIX.tech2, charge.basePrice - plain.basePrice, perRun, 120)
    local blueprint = Blueprints.byProduct[charge.id]
    table.insert(blueprint.materials, 1, { type = plain.id, quantity = perRun })
    blueprint.basePrice = charge.basePrice * perRun * 10
    blueprint.invented = true
  else
    add(charge.id, charge.name, MIX.charge, charge.basePrice, perRun, 60)
  end
end
for _, hull in Ships.list do
  local plain = if hull.tech == 2 and hull.base then Ships.byId[hull.base] else nil
  if hull.restricted then
    -- (a pirate's hull, or an alien one, tech 2 or plain: nobody has
    -- the drawings)
    continue
  elseif plain then
    -- A tech 2 hull is built of the plain one, and of what makes the
    -- difference: hull components and the rare minerals. Its blueprint
    -- is not for sale.
    add(hull.id, hull.name, MIX.tech2, hull.basePrice - plain.basePrice, 1, math.min(72000, 600 + hull.basePrice // 200),
      advanced(Components.HULL, HULL_SIZE[hull.class] or 1, MOON_HULL))
    local blueprint = Blueprints.byProduct[hull.id]
    table.insert(blueprint.materials, 1, { type = plain.id, quantity = 1 })
    blueprint.basePrice = hull.basePrice * 10
    blueprint.invented = true
  elseif hull.class ~= "capsule" and not hull.restricted then
    -- (a freighter is as much metal as a battleship, and of the same kinds)
    local mix = if hull.class == "battleship" or hull.class == "freighter" or Ships.Capital(hull.class) then MIX.battleship
      elseif hull.class == "cruiser" or hull.class == "barge" or hull.class == "attackbattlecruiser" or hull.class == "battlecruiser"
        then MIX.cruiser
      else MIX.ship
    -- (the largest hulls take most of a day, not a week)
    add(hull.id, hull.name, mix, hull.basePrice, 1, math.min(72000, 600 + hull.basePrice // 200), Components.HULL)
    -- (a hull nobody sells has a blueprint nobody sells either: it can
    -- be built by whoever comes by one, and by nobody else)
    Blueprints.byProduct[hull.id].rare = hull.rare
  end
end

-- A drone is built as a small gun on a small engine is.
for _, drone in Drones.list do
  local parts: { { any } } = { { "component.weapon", 0.4 }, { "component.thruster", 0.3 }, { "component.electronics", 0.3 } }
  local plain = if drone.tech == 2 and drone.base then Drones.byId[drone.base] else nil
  if plain then
    -- (a tech 2 drone is built of the plain one, the same parts over
    -- again and the rare minerals; and its blueprint is not for sale)
    add(drone.id, drone.name, MIX.tech2, drone.basePrice - plain.basePrice, 1, 600, parts)
    local blueprint = Blueprints.byProduct[drone.id]
    table.insert(blueprint.materials, 1, { type = plain.id, quantity = 1 })
    blueprint.basePrice = drone.basePrice * 10
    blueprint.invented = true
  else
    add(drone.id, drone.name, MIX.module, drone.basePrice, 1, 300, parts)
  end
end

-- Structures: a tower as a big hull is built, its modules as lesser
-- ones, and fuel by the forty. What stays in space for years is built
-- of what planets give as well as of what hulls are: a third of a
-- structure's parts are alloys, ceramics and polymers, and half of what
-- goes into fuel is isotopes, water and catalysts (Data/Planets).
local STRUCTURE: { { any } } = { { "planet.alloys", 0.17 }, { "planet.ceramics", 0.09 }, { "planet.polymers", 0.07 } }
for _, part in Components.HULL do
  table.insert(STRUCTURE, { part[1], part[2] * 0.67 })
end
local FUEL: { { any } } = { { "planet.isotopes", 0.5 }, { "planet.water", 0.3 }, { "planet.catalysts", 0.2 } }
for _, tower in Structures.towers do
  -- (an alien people's tower and the pirates' are not built from a
  -- print, as their hulls are not: they are got where they are sold)
  local people = Factions.byId[tower.faction]
  if people and people.kind == "human" then
    add(tower.id, tower.name, MIX.cruiser, tower.basePrice, 1, math.min(72000, 600 + tower.basePrice // 200), STRUCTURE)
  end
end
for _, module in Structures.modules do
  add(module.id, module.name, MIX.ship, module.basePrice, 1, math.min(72000, 600 + module.basePrice // 200), STRUCTURE)
end
add(Structures.FUEL.id, Structures.FUEL.name, MIX.charge, Structures.FUEL.basePrice, 40, 120, FUEL)
add(Structures.SEAL.id, Structures.SEAL.name, MIX.charge, Structures.SEAL.basePrice, 1, 300, FUEL)
-- (a command centre is built as a small hull is, of nothing a colony
-- makes: the first one has to come from somewhere)
add(Planets.CENTRE.id, Planets.CENTRE.name, MIX.ship, Planets.CENTRE.basePrice, 1, 600, Components.HULL)

-- A booster is made of its gas, and of silicon to hold it: nothing a
-- station sells is the gas, so it is made by whoever went and got it.
-- A mild one takes half of both, and a strong one is made of two of
-- the plain one and as much of both again.
for _, booster in Boosters.list do
  local share = if booster.strength == Boosters.MILD then 2 else 1
  local materials: { { type: string, quantity: number } } = { { type = booster.gas, quantity = Boosters.GAS // share },
    { type = "mineral.silicon", quantity = Boosters.SILICON // share } }
  if booster.strength == Boosters.STRONG then
    table.insert(materials, 1, { type = Boosters.Plain(booster).id, quantity = Boosters.DOSES })
  end
  local blueprint: Blueprint = {
    id = "blueprint." .. booster.id, product = booster.id, name = booster.name .. " Booster Blueprint", perRun = 1, seconds = 300,
    materials = materials,
    basePrice = booster.price * 10,
  }
  table.insert(Blueprints.list, blueprint)
  Blueprints.byId[blueprint.id] = blueprint
  Blueprints.byProduct[booster.id] = blueprint
end

-- A copy of a blueprint is kept as its runs: one unit of "copy.<product>"
-- is one run, and a stack of twenty is a copy good for twenty.
Blueprints.COPY = "copy."

-- The item type a copy of a blueprint is.
function Blueprints.Copy(blueprint: Blueprint): string
  return Blueprints.COPY .. blueprint.product
end

-- The blueprint an item type is, and whether it is a copy of it and not
-- the blueprint itself. Nil for anything else.
function Blueprints.Of(type: string): (Blueprint?, boolean)
  local blueprint = Blueprints.byId[type]
  if blueprint then
    return blueprint, false
  elseif string.sub(type, 1, #Blueprints.COPY) == Blueprints.COPY then
    local copied = Blueprints.byProduct[string.sub(type, #Blueprints.COPY + 1)]
    return copied, copied ~= nil
  end
  return nil, false
end

-- Jobs a pilot can run at once before any skill adds more.
Blueprints.JOB_SLOTS = 2
-- The fee to install a job, as a share of what it will make.
Blueprints.JOB_FEE = 0.02

return Blueprints
