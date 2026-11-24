--!strict
-- An icon for every type of item. The owner, 2026-11-23: one drawn
-- icon for each kind of item, "by category, of course" (a shield booster
-- of every size and make has the one), abstract, on no background, in
-- the cel manner they picked; drawn by script/artgen from
-- script/iconkinds.txt and put in resource/texture/icons (Game/UI/IconSet
-- lists them). Over it the game marks what the picture does not say: a
-- bracket in the top left corner for a better make (custom, a people's own,
-- tech 2, masterwork, officer's), a letter in the bottom left for its
-- size, and a twist in the bottom right for one mutated. A blueprint is
-- its product's icon on a blueprint's tile. A kind with no picture yet
-- has the old sign: a tile in its category's colour with a pictogram.
--
--   ItemIcon.Draw("laser.pulse.medium", x, y, 28)

local Blueprints = require("@lt/Core/Data/Blueprints")
local Fonts = require("@lt/Fonts")
local IconSet = require("@lt/Game/UI/IconSet")
local Modules = require("@lt/Core/Data/Modules")
local Paints = require("@lt/Core/Data/Paints")
local Theme = require("@lt/Game/UI/Theme")
local Types = require("@lt/Core/Data/Types")
local Ships = require("@lt/Core/Data/Ships")

local ItemIcon = {}

local function v(x: number, y: number): vector
  return vector.create(x, y)
end

local TILE: { [string]: vector } = {
  module = vector.create(0.20, 0.42, 0.62),
  charge = vector.create(0.62, 0.44, 0.16),
  ship = vector.create(0.24, 0.50, 0.36),
  ore = vector.create(0.46, 0.36, 0.28),
  mineral = vector.create(0.42, 0.44, 0.50),
  component = vector.create(0.36, 0.46, 0.30),
  blueprint = vector.create(0.16, 0.32, 0.62),
  skillbook = vector.create(0.50, 0.30, 0.52),
  goods = vector.create(0.42, 0.42, 0.36),
  structure = vector.create(0.34, 0.40, 0.48),
  planetary = vector.create(0.30, 0.46, 0.44),
  moon = vector.create(0.46, 0.44, 0.56),
  drone = vector.create(0.46, 0.34, 0.50),
  implant = vector.create(0.50, 0.26, 0.40),
}

-- A closed outline through some points.
local function outline(points: { vector }): { Glyph }
  local out: { Glyph } = {}
  for index, point in points do
    table.insert(out, Glyph_Line(point, points[index % #points + 1], 1, 1))
  end
  return out
end

local function add(to: { Glyph }, more: { Glyph }): { Glyph }
  for _, glyph in more do
    table.insert(to, glyph)
  end
  return to
end

-- The parts of each pictogram, in a square from -1 to 1.
local PICTOGRAMS: { [string]: () -> { Glyph } } = {
  laser = function()
    return { Glyph_Box(v(-0.72, 0), v(0.2, 0.34), 1, 1), Glyph_Line(v(-0.5, 0), v(0.95, 0), 1, 1),
      Glyph_Line(v(0.55, -0.32), v(0.9, -0.12), 1, 0.7), Glyph_Line(v(0.55, 0.32), v(0.9, 0.12), 1, 0.7) }
  end,
  gun = function()
    return { Glyph_Box(v(-0.6, 0), v(0.3, 0.36), 1, 1), Glyph_Box(v(0.25, -0.14), v(0.6, 0.07), 1, 1),
      Glyph_Box(v(0.25, 0.14), v(0.6, 0.07), 1, 1) }
  end,
  hybrid = function()
    return { Glyph_Line(v(-0.9, -0.3), v(0.6, -0.3), 1, 1), Glyph_Line(v(-0.9, 0.3), v(0.6, 0.3), 1, 1),
      Glyph_Circle(v(0.15, 0), 0.2, 1, 1), Glyph_Line(v(0.45, 0), v(0.95, 0), 1, 0.7) }
  end,
  launcher = function()
    return add({ Glyph_Triangle(v(0.35, -0.3), v(0.35, 0.3), v(0.95, 0), 1, 1), Glyph_Box(v(-0.1, 0), v(0.45, 0.2), 1, 1) },
      { Glyph_Line(v(-0.55, -0.2), v(-0.9, -0.5), 1, 1), Glyph_Line(v(-0.55, 0.2), v(-0.9, 0.5), 1, 1) })
  end,
  shield = function()
    return { Glyph_Ring(0, 0.85, 1, 1, 0), Glyph_Ring(0, 0.5, 1, 0.6, 0), Glyph_Circle(0, 0.16, 1, 1) }
  end,
  armor = function()
    return { Glyph_Box(v(0, -0.55), v(0.8, 0.14), 1, 1), Glyph_Box(v(0, 0), v(0.8, 0.14), 1, 0.8), Glyph_Box(v(0, 0.55), v(0.8, 0.14), 1, 0.6) }
  end,
  engine = function()
    return { Glyph_Triangle(v(0.7, -0.55), v(0.7, 0.55), v(-0.1, 0), 1, 1), Glyph_Line(v(-0.3, 0), v(-0.95, 0), 1, 1),
      Glyph_Line(v(-0.3, -0.3), v(-0.8, -0.45), 1, 0.7), Glyph_Line(v(-0.3, 0.3), v(-0.8, 0.45), 1, 0.7) }
  end,
  battery = function()
    return add(outline({ v(-0.8, -0.45), v(0.65, -0.45), v(0.65, 0.45), v(-0.8, 0.45) }),
      { Glyph_Box(v(0.8, 0), v(0.1, 0.2), 1, 1), Glyph_Box(v(-0.45, 0), v(0.18, 0.28), 1, 1), Glyph_Box(v(0.0, 0), v(0.18, 0.28), 1, 0.6) })
  end,
  miner = function()
    return { Glyph_Line(v(-0.9, 0.6), v(0.15, -0.1), 1, 1), Glyph_Circle(v(0.45, -0.3), 0.42, 1, 1), Glyph_Box(v(-0.8, 0.55), v(0.16, 0.16), 1, 1) }
  end,
  crystal = function()
    return add(outline({ v(0, -0.9), v(0.55, 0), v(0, 0.9), v(-0.55, 0) }), { Glyph_Line(v(-0.55, 0), v(0.55, 0), 1, 0.6) })
  end,
  rounds = function()
    -- a round standing on its base
    return add(outline({ v(-0.32, 0.8), v(-0.32, -0.15), v(0, -0.85), v(0.32, -0.15), v(0.32, 0.8) }),
      { Glyph_Line(v(-0.32, 0.35), v(0.32, 0.35), 1, 0.7) })
  end,
  slug = function()
    return { Glyph_Circle(v(0.2, 0), 0.42, 1, 1), Glyph_Line(v(-0.95, -0.25), v(-0.3, -0.25), 1, 0.7), Glyph_Line(v(-0.95, 0), v(-0.4, 0), 1, 1),
      Glyph_Line(v(-0.95, 0.25), v(-0.3, 0.25), 1, 0.7) }
  end,
  missile = function()
    return { Glyph_Triangle(v(0.4, -0.22), v(0.4, 0.22), v(0.95, 0), 1, 1), Glyph_Box(v(-0.1, 0), v(0.5, 0.2), 1, 1),
      Glyph_Triangle(v(-0.6, -0.2), v(-0.95, -0.55), v(-0.95, -0.2), 1, 1), Glyph_Triangle(v(-0.6, 0.2), v(-0.95, 0.55), v(-0.95, 0.2), 1, 1) }
  end,
  ship = function()
    return { Glyph_Triangle(v(-0.8, -0.6), v(-0.8, 0.6), v(0.95, 0), 1, 1), Glyph_Triangle(v(-0.95, -0.25), v(-0.95, 0.25), v(-0.5, 0), 1, 0.4) }
  end,
  hauler = function()
    return add(outline({ v(-0.9, -0.5), v(0.5, -0.5), v(0.9, 0), v(0.5, 0.5), v(-0.9, 0.5) }),
      { Glyph_Line(v(-0.4, -0.5), v(-0.4, 0.5), 1, 0.7), Glyph_Line(v(0.1, -0.5), v(0.1, 0.5), 1, 0.7) })
  end,
  rock = function()
    return outline({ v(-0.8, -0.2), v(-0.35, -0.75), v(0.4, -0.7), v(0.85, -0.1), v(0.55, 0.65), v(-0.3, 0.8), v(-0.85, 0.35) })
  end,
  ingot = function()
    return add(outline({ v(-0.55, -0.4), v(0.55, -0.4), v(0.9, 0.45), v(-0.9, 0.45) }), { Glyph_Line(v(-0.35, 0), v(0.35, 0), 1, 0.6) })
  end,
  gear = function()
    local out: { Glyph } = { Glyph_Ring(0, 0.55, 1, 1, 0), Glyph_Circle(0, 0.18, 1, 1) }
    for tooth = 0, 7 do
      local a = tooth * math.pi / 4
      table.insert(out, Glyph_Line(v(0.6 * math.cos(a), 0.6 * math.sin(a)), v(0.92 * math.cos(a), 0.92 * math.sin(a)), 1, 1))
    end
    return out
  end,
  blueprint = function()
    return add(outline({ v(-0.8, -0.8), v(0.8, -0.8), v(0.8, 0.8), v(-0.8, 0.8) }),
      { Glyph_Line(v(-0.8, -0.25), v(0.8, -0.25), 1, 0.5), Glyph_Line(v(-0.8, 0.3), v(0.8, 0.3), 1, 0.5), Glyph_Line(v(-0.25, -0.8), v(-0.25, 0.8), 1, 0.5),
        Glyph_Line(v(0.3, -0.8), v(0.3, 0.8), 1, 0.5) })
  end,
  book = function()
    return add(outline({ v(-0.7, -0.85), v(0.7, -0.85), v(0.7, 0.85), v(-0.7, 0.85) }),
      { Glyph_Line(v(-0.4, -0.85), v(-0.4, 0.85), 1, 1), Glyph_Line(v(-0.15, -0.35), v(0.45, -0.35), 1, 0.7), Glyph_Line(v(-0.15, 0), v(0.45, 0), 1, 0.7) })
  end,
  crate = function()
    return add(outline({ v(-0.8, -0.7), v(0.8, -0.7), v(0.8, 0.7), v(-0.8, 0.7) }),
      { Glyph_Line(v(-0.8, -0.7), v(0.8, 0.7), 1, 0.6), Glyph_Line(v(-0.8, 0.7), v(0.8, -0.7), 1, 0.6) })
  end,
}

-- Which pictogram a type has, by the start of its id.
local BY_PREFIX: { { string } } = {
  { "laser.", "laser" }, { "autocannon", "gun" }, { "artillery", "gun" }, { "blaster", "hybrid" }, { "railgun", "hybrid" },
  { "launcher.", "launcher" }, { "shield.", "shield" }, { "armor.", "armor" }, { "afterburner", "engine" }, { "mwd.", "engine" }, { "capacitor.", "battery" },
  { "miner.", "miner" }, { "missile.", "missile" }, { "crystal.", "crystal" }, { "charge.", "slug" }, { "ammo.", "rounds" },
}
local BY_CATEGORY: { [string]: string } = {
  module = "gear", charge = "rounds", ore = "rock", mineral = "ingot", component = "gear", blueprint = "blueprint",
  skillbook = "book", goods = "crate", structure = "crate", planetary = "crate", moon = "rock", drone = "gear", implant = "gear",
}
local CLASS_PIPS: { [string]: number } = { frigate = 1, destroyer = 1, cruiser = 2, battleship = 3, industrial = 2, barge = 2, freighter = 3,
  attackbattlecruiser = 3, battlecruiser = 2, carrier = 3, dreadnought = 3, siegedreadnought = 3, capitalindustrial = 3, supercarrier = 3,
  ultracapital = 3 }

-- The pictogram, the size (0 for none, else 1 to 3) and the category of
-- a type.
function ItemIcon.Parts(type: string): (string, number, string)
  local hull = Ships.byId[type]
  if hull then
    return if hull.class == "industrial" or hull.class == "barge" or hull.class == "freighter" or hull.class == "capitalindustrial"
      then "hauler" else "ship",
      CLASS_PIPS[hull.class] or 0, "ship"
  end
  local info = Types.Get(type)
  local category = if info then info.category else "goods"
  local size = if string.find(type, "large", 1, true) or string.find(type, "cruise", 1, true) or string.find(type, ".xl", 1, true)
      or string.find(type, "siege", 1, true) then 3
    elseif string.find(type, "medium", 1, true) or string.find(type, "heavy", 1, true) then 2
    elseif category == "module" or category == "charge" then 1
    else 0
  if category == "blueprint" then
    return "blueprint", 0, category
  end
  for _, pair in BY_PREFIX do
    if string.sub(type, 1, #pair[1]) == pair[1] then
      return pair[2], size, category
    end
  end
  return BY_CATEGORY[category] or "crate", size, category
end

-- The kind of icon a type has, by the start of its id (the longest that
-- fits), in each category. (Hulls by their class.)
local KIND_BY_PREFIX: { [string]: { { string } } } = {
  module = {
    { "laser.", "laser" }, { "autocannon", "projectile" }, { "artillery", "projectile" }, { "blaster", "hybrid" },
    { "railgun", "hybrid" }, { "launcher.", "launcher" }, { "smartbomb", "smartbomb" }, { "pds", "pds" },
    { "neutraliser", "neutraliser" }, { "drain", "nosferatu" }, { "heat.sink", "weaponupgrade" },
    { "gyrostabilizer", "weaponupgrade" }, { "flux.coil", "weaponupgrade" }, { "ballistic", "weaponupgrade" },
    { "computer.", "tracking" }, { "tracking.enhancer", "tracking" }, { "missile.guidance", "tracking" },
    { "drone.gun", "projectile" }, { "fighter.cannon", "projectile" }, { "drone.", "droneupgrade" },
    { "pylon.fighter", "fighterbay" }, { "bomber.rack", "fighterbay" }, { "burst.", "burst" }, { "siege", "siege" },
    { "triage", "triage" }, { "industrial.core", "industrialcore" },
    { "shield.booster", "shieldbooster" }, { "shield.extender", "shieldextender" }, { "shield.hardener", "shieldhardener" },
    { "shield.amplifier", "shieldhardener" }, { "shield.recharger", "shieldregen" }, { "shield.fluxcoil", "shieldregen" },
    { "relay.shield", "shieldregen" }, { "amplifier.shield", "shieldamp" }, { "armor.repairer", "armorrepairer" },
    { "mend.lattice", "armorrepairer" }, { "armor.plate", "armorplate" }, { "armor.", "armorhardener" },
    { "amplifier.armor", "armoramp" }, { "damage.control", "damagecontrol" }, { "hull.repairer", "hullrepairer" },
    { "hull.bulkhead", "bulkhead" }, { "remote.shield", "remoteshield" }, { "remote.armor", "remotearmor" },
    { "remote.capacitor", "remotecap" }, { "remote.sensor", "remotesensor" },
    { "capacitor.battery", "capbattery" }, { "capacitor.booster", "capbooster" }, { "capacitor.", "capregen" },
    { "relay.capacitor", "capregen" }, { "fitting.coprocessor", "cpu" }, { "fitting.reactor", "powergrid" },
    { "auxiliary.generator", "powergrid" }, { "grid.diagnostic", "powergrid" }, { "afterburner", "afterburner" },
    { "mwd", "mwd" }, { "nanofiber", "speed" }, { "overdrive", "speed" }, { "inertial", "speed" },
    { "warp.stabilizer", "warpstab" }, { "warp.accelerator", "warpaccel" }, { "jump.micro", "microjump" },
    { "jump.portal", "jumpportal" }, { "beacon.jump", "jumpportal" }, { "cloak", "cloak" },
    { "sensor.booster", "sensorbooster" }, { "targeting.amplifier", "targetamp" }, { "scan.rangefinder", "targetamp" },
    { "signature.dampener", "sigdamp" },
    { "disruptor", "disruptor" }, { "projector.grappler", "grappler" }, { "projector.entanglement", "entangle" },
    { "jammer.ecm", "jammer" }, { "jammer.burst", "burstjammer" }, { "damper", "damper" },
    { "ewar.tracking", "trackdisrupt" }, { "ewar.guidance", "guidedisrupt" }, { "painter", "painter" },
    { "bubble", "bubble" }, { "miner.strip", "stripminer" }, { "miner.ice", "iceminer" }, { "miner.gas", "gasminer" },
    { "miner.", "miner" }, { "mining.upgrade", "miningupgrade" }, { "ice.upgrade", "miningupgrade" },
    { "tractor", "tractor" }, { "salvager", "salvager" }, { "scanner.survey", "survey" }, { "scanner.ship", "shipscan" },
    { "scanner.cargo", "cargoscan" }, { "scanner.probe", "probelauncher" }, { "analyzer.data", "dataanalyzer" },
    { "analyzer.relic", "relicanalyzer" }, { "hack.buffer", "cipher" }, { "cargo.", "cargoext" }, { "rig.", "rig" },
  },
  charge = {
    { "crystal.standard", "crystal" }, { "crystal.radio", "crystal" }, { "crystal.multifrequency", "crystal" },
    { "crystal.", "miningcrystal" }, { "ammo.", "ammo" }, { "charge.", "slug" }, { "missile.", "missile" },
    { "torpedo.", "missile" }, { "booster.charge", "capcharge" }, { "bubble.charge", "bubblecharge" },
    { "paste.nanite", "nanite" },
  },
  goods = {
    { "alloy.benthic", "benthic" }, { "booster.", "booster" }, { "cargo.sealed", "sealedcargo" },
    { "cargo.stolen", "stolencargo" }, { "datacore", "datacore" }, { "gas.", "vapour" }, { "injector.", "injector" },
    { "mutator", "mutator" }, { "probe.", "probe" }, { "salvage.", "salvage" }, { "scrap.", "scrap" }, { "tag.", "tag" },
  },
  drone = {
    { "drone.mining", "miningdrone" }, { "drone.repair", "repairdrone" }, { "drone.fighter", "fighter" },
    { "drone.trident", "fighter" }, { "drone.bomber", "bomber" }, { "drone.", "combatdrone" },
  },
  ore = { { "ice.", "ice" }, { "", "ore" } },
  moon = { { "composite.", "moonmaterial" }, { "", "moonore" } },
  mineral = { { "ice.", "iceproduct" }, { "", "mineral" } },
  planetary = { { "raw.", "planetraw" }, { "", "planetproduct" } },
  implant = { { "", "implant" } },
  skillbook = { { "", "skillbook" } },
  component = {
    { "component.capacitor", "capcell" }, { "component.electronics", "electronics" },
    { "component.emitter", "shieldemitter" }, { "component.frame", "frame" }, { "component.plating", "plating" },
    { "component.reactor", "reactor" }, { "component.thruster", "thruster" }, { "component.weapon", "weaponassembly" },
  },
  structure = {
    { "array.assembly", "assembly" }, { "array.beacon", "beacon" }, { "array.claim", "claim" },
    { "array.drill", "stationminer" }, { "array.habitat", "habitat" }, { "array.hangar", "storage" },
    { "array.laboratory", "research" }, { "array.reactor", "reactorarray" }, { "array.refining", "refinery" },
    { "array.storage", "storage" }, { "array.trade", "market" }, { "battery.", "defence" },
    { "citadel.defence", "defence" }, { "citadel.generator", "generator" }, { "citadel.habitation", "citadel" },
    { "citadel.nimia.habitation", "citadel" }, { "citadel.vail.habitation", "citadel" },
    { "citadel.hardener", "stationshield" }, { "citadel.shield", "stationshield" }, { "citadel.miner", "stationminer" },
    { "citadel.observatory", "observatory" }, { "citadel.refinery", "refinery" }, { "citadel.nimia.refinery", "refinery" },
    { "citadel.vail.refinery", "refinery" }, { "citadel.research", "research" }, { "citadel.nimia.research", "research" },
    { "citadel.vail.research", "research" }, { "citadel.shipyard", "shipyard" }, { "citadel.nimia.shipyard", "shipyard" },
    { "citadel.vail.shipyard", "shipyard" }, { "citadel.tradehub", "market" }, { "colony.", "command" },
    { "deploy.beacon", "beacon" }, { "deploy.bubble", "buoy" }, { "deploy.tractor", "depot" }, { "deploy.", "depot" },
    { "fuel.block", "fuel" }, { "fuel.seal", "sealing" }, { "service.assembly", "assembly" }, { "service.bridge", "bridge" },
    { "service.clone", "habitat" }, { "service.generator", "gravity" }, { "service.manufacturing", "assembly" },
    { "service.market", "market" }, { "service.reactor", "reactorarray" }, { "service.refinery", "refinery" },
    { "service.repair", "repairbay" }, { "service.research", "research" }, { "service.storage", "storage" },
    { "tower.", "tower" },
  },
}
-- (the longest start first, so that "miner.strip" is found before "miner.")
for _, list in KIND_BY_PREFIX do
  table.sort(list, function(a: { string }, b: { string }): boolean
    return #a[1] > #b[1]
  end)
end

local kindOf: { [string]: string } = {}

-- The kind of icon a type has ("shieldbooster", "frigate", ...), and
-- whether it is a blueprint of it; "" for a kind with none.
function ItemIcon.Kind(type: string): (string, boolean)
  local blueprint = Types.Get(type) and (Types.Get(type) :: Types.Info).category == "blueprint"
  if blueprint then
    local of = Blueprints.Of(type)
    return if of then (ItemIcon.Kind(of.product)) else "", true
  end
  local known = kindOf[type]
  if known then
    return known, false
  end
  local found = ""
  local hull = Ships.byId[type]
  if hull then
    found = hull.class
  else
    local info = Types.Get(type)
    local list: { { string } } = KIND_BY_PREFIX[if info then info.category else "goods"] or {}
    for _, pair in list do
      if string.sub(type, 1, #pair[1]) == pair[1] then
        found = pair[2]
        break
      end
    end
    if found == "" and info and info.category == "goods" then
      found = "crate"
    end
  end
  kindOf[type] = found
  return found, false
end

-- What a type's tab says: the colour of its make, nil for a plain one.
local TIER = {
  custom = vector.create(0.72, 0.78, 0.86),  -- a make worked over: steel
  tech2 = vector.create(1.0, 0.78, 0.25),    -- tech 2: gold
  master = vector.create(0.95, 0.32, 0.28),  -- a masterwork: red
  officer = vector.create(0.72, 0.42, 1.0),  -- an officer's: violet
}
local function tierOf(type: string): vector?
  local module = Modules.byId[type]
  if module then
    if module.meta == 3 then
      return Theme.WHOSE[module.lineage or ""] or Theme.GOOD
    end
    return if module.meta == 4 then TIER.officer elseif module.meta == 2 then TIER.master elseif module.tech == 2
      then TIER.tech2 elseif module.meta == 1 then TIER.custom else nil
  end
  local charge = Modules.chargeById[type]
  if charge then
    return if charge.tech == 2 then TIER.tech2 else nil
  end
  local hull = Ships.byId[type]
  if hull then
    return if hull.tech == 2 then TIER.tech2 elseif hull.navy then Theme.WHOSE[hull.lineage] or Theme.GOOD else nil
  end
  return nil
end

-- What size a type is, as a letter; "" for none said.
local function sizeOf(type: string): string
  local module = Modules.byId[type]
  if module then
    if string.find(type, ".xl", 1, true) or string.find(type, "capital", 1, true) then
      return "XL"
    end
    return ({ "S", "M", "L", "XL" })[Modules.SizeOf(module)] or ""
  end
  local charge = Modules.chargeById[type]
  if charge then
    return ({ "S", "M", "L", "XL" })[charge.size] or ""
  end
  return ""
end

-- A picture of a kind, the smallest of its sizes that is as big as it
-- is drawn (they are not filtered down: one twice as big shimmers).
local pictures: { [string]: Texture } = {}
local function picture(kind: string, size: number): Texture?
  if kind == "" or not IconSet.kinds[kind] then
    return nil
  end
  local px = IconSet.sizes[#IconSet.sizes]
  for _, each in IconSet.sizes do
    if each >= size then
      px = each
      break
    end
  end
  local path = `texture/icons/{px}/{kind}.png`
  local made: Texture? = pictures[path]
  if made == nil then
    local ok, texture = pcall(Texture_LoadFrom, Location_Resource(path))
    if ok and texture then
      pictures[path] = texture
      made = texture
    end
  end
  return made
end

-- The marks over a picture: its make, its size, a mutated one's twist.
-- (A twist: a ring broken by a stroke.)
local function shape(glyphs: { Glyph }): Icon
  local icon = Icon_Create()
  for _, glyph in glyphs do
    Icon_AddGlyph(icon, glyph)
  end
  return icon
end
local TWIST = shape({ Glyph_Ring(0, 0.85, 1, 1, 0), Glyph_Line(v(-0.6, 0.6), v(0.6, -0.6), 1, 1) })
local DARK = vector.create(0.02, 0.03, 0.05)
local function marks(type: string, x: number, y: number, size: number)
  local tier = tierOf(type)
  if tier then
    -- a corner bracket, solid: along the top and down the left
    local long, thick = math.max(6, math.floor(size * 0.34)), math.max(2, math.floor(size * 0.09 + 0.5))
    WidgetRenderer_DrawPanel(vector.create(x, y), vector.create(long, thick), tier, 1, 1, 0)
    WidgetRenderer_DrawPanel(vector.create(x, y), vector.create(thick, long), tier, 1, 1, 0)
  end
  -- (the letter only where there is room for it to be read)
  local letter = if size >= 28 then sizeOf(type) else ""
  if letter ~= "" then
    local px = math.max(9, math.floor(size * 0.26 + 0.5))
    local at = vector.create(x + 1, y + size - 2)
    WidgetRenderer_DrawText(Fonts.Heading(), letter, at + vector.create(1, 1), px, DARK, 0.9, false)
    WidgetRenderer_DrawText(Fonts.Heading(), letter, at, px, vector.create(0.92, 0.95, 1.0), 0.95, false)
  end
  local module = Modules.byId[type]
  if module and module.mutated then
    local m = math.max(3, size * 0.12)
    Icon_Draw(TWIST, vector.create(x + size - m - 1, y + size - m - 1), m, vector.create(1.0, 0.4, 0.85), 1)
  end
end

local built: { [string]: Icon } = {}

local function pictogram(name: string): Icon
  local made: Icon? = built[name]
  if made then
    return made
  end
  local icon = Icon_Create()
  for _, glyph in (PICTOGRAMS[name] or PICTOGRAMS.crate)() do
    Icon_AddGlyph(icon, glyph)
  end
  built[name] = icon
  return icon
end

-- Draw the icon of a type with its top-left corner at (x, y), 'size'
-- pixels square.
function ItemIcon.Draw(type: string, x: number, y: number, size: number)
  -- (drawn by the engine, in pixels: where it is and how big, by the interface's scale)
  if Theme.scale ~= 1 then
    x, y, size = Theme.Px(x), Theme.Px(y), Theme.Px(size)
  end
  -- A paint is a swatch of itself: its plating's colour, with the colour
  -- of what it marks and of its designs in a band along the foot. A
  -- design is a tile with bars across.
  local paint, design = Paints.paintById[type], Paints.designById[type]
  if paint or design then
    local round = math.max(2, size / 8)
    local function colour(c: { number }): vector
      -- (as bright on a tile as on a hull in the sun)
      return vector.create(c[1], c[2], c[3]) * 1.5
    end
    if paint then
      WidgetRenderer_DrawPanel(vector.create(x, y), vector.create(size, size), colour(paint.plating), 1, 1, round)
      WidgetRenderer_DrawPanel(vector.create(x, y + size * 0.62), vector.create(size / 2, size * 0.38), colour(paint.patch), 1, 1, 0)
      WidgetRenderer_DrawPanel(vector.create(x + size / 2, y + size * 0.62), vector.create(size / 2, size * 0.38), colour(paint.accent), 1, 1, 0)
      WidgetRenderer_DrawPanel(vector.create(x, y + size * 0.56), vector.create(size, size * 0.07), colour(paint.trim), 1, 1, 0)
    else
      WidgetRenderer_DrawPanel(vector.create(x, y), vector.create(size, size), vector.create(0.30, 0.33, 0.38), 0.8, 0.9, round)
      for bar = 0, 2 do
        WidgetRenderer_DrawPanel(vector.create(x + size * 0.16, y + size * (0.2 + 0.24 * bar)), vector.create(size * 0.68, size * 0.11),
          vector.create(0.92, 0.95, 1.0), 0.9, 0.9, 0)
      end
    end
    return
  end
  local kind, blueprint = ItemIcon.Kind(type)
  local texture = picture(kind, size)
  if texture then
    if blueprint then
      -- (a blueprint: its product on a blueprint's tile, paler for a copy)
      local copy = string.find(type, Blueprints.COPY, 1, true) ~= nil
      WidgetRenderer_DrawPanel(vector.create(x, y), vector.create(size, size),
        if copy then vector.create(0.22, 0.42, 0.62) else vector.create(0.12, 0.26, 0.56), 0.6, 0.9, math.max(2, size / 8))
      WidgetRenderer_DrawTexture(texture, vector.create(x + size * 0.1, y + size * 0.1), vector.create(size * 0.8, size * 0.8), 1)
      return
    end
    WidgetRenderer_DrawTexture(texture, vector.create(x, y), vector.create(size, size), 1)
    marks(type, x, y, size)
    return
  end
  local name, pips, category = ItemIcon.Parts(type)
  local tile = TILE[category] or TILE.goods
  WidgetRenderer_DrawPanel(vector.create(x, y), vector.create(size, size), tile, 0.55, 0.9, math.max(2, size / 8))
  Icon_Draw(pictogram(name), vector.create(x + size / 2, y + size / 2 - (if pips > 0 then size * 0.06 else 0)), size * 0.30,
    vector.create(0.92, 0.95, 1.0), 1)
  -- size: one to three pips along the bottom
  local pip = math.max(2, size / 11)
  for index = 1, pips do
    WidgetRenderer_DrawPanel(vector.create(x + size / 2 + (index - (pips + 1) / 2) * pip * 2 - pip / 2, y + size - pip * 1.6),
      vector.create(pip, pip), vector.create(1, 1, 1), 0.9, 0.9, 0)
  end
end

return ItemIcon
