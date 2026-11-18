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
    -- (a hull of every class by name; or, where the owner has gone through the faction's ships, its line of them)
    local line = faction.line
    if line then
      local named: { [string]: boolean } = {}
      for _, hull in line do
        t.ok(not named[hull.name], `{faction.id} has two hulls called {hull.name}`)
        named[hull.name] = true
      end
      t.ok(#line >= 5, faction.id)
    else
      for _, class in Factions.CLASSES do
        t.ok(faction.hulls[class] ~= nil, `{faction.id} has no {class}`)
      end
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
    -- (a faction whose ships the owner has gone through has its own line of them: the case after this one)
    if faction.line then
      continue
    end
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
    -- The owner's ladder beside the battleship and above it (2026-11-12): how big each is, how many hardpoints
    -- it has whoever builds it, and what they are for.
    local LADDER: { [string]: { number } } = { attackbattlecruiser = { 200, 4 }, battlecruiser = { 300, 8 }, carrier = { 1000, 0 },
      dreadnought = { 1300, 20 }, siegedreadnought = { 950, 4 }, capitalindustrial = { 700, 0 }, supercarrier = { 1300, 0 } }
    for _, hull in line do
      local rung = LADDER[hull.class]
      if rung then
        t.eq({ hull.radius, hull.turrets + hull.launchers }, rung, hull.id)
        t.eq(Ships.Capital(hull.class), hull.radius >= 700, hull.id)
      end
      -- (a hull may have more hardpoints than high slots: the pilot chooses the mix; and what fights with what
      -- it launches, or does not fight, has no hardpoint at all)
      t.ok(hull.turrets <= hull.highs and hull.launchers <= hull.highs, hull.id)
      t.eq(hull.turrets + hull.launchers >= 1, rung == nil or rung[2] > 0, hull.id)
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
      -- every people's hull is an item with drawings; only human designs are for sale (an alien one, or a pirate's, is rare)
      t.ok(Types.Get(hull.id) ~= nil and Blueprints.byProduct[hull.id] ~= nil, hull.id)
      t.eq(hull.foreign == true, faction.kind ~= "human", hull.id)
      if faction.kind ~= "human" then
        t.ok(hull.rare and Blueprints.byProduct[hull.id].rare, hull.id)
      end
    end
    t.ok(line[5].cargo > 10 * line[1].cargo, "an industrial carries far more than a frigate")
  end
end)

suite:Case("the Talmar's ships are the owner's rework of them: each by name, of its class and that class's size, with the tech 2 makes that are hulls of their own", function(t)
  local talmar = Factions.byId.talmar
  local RADIUS = { frigate = 42, destroyer = 75, cruiser = 150, battlecruiser = 300, battleship = 400, carrier = 1000, dreadnought = 1300,
    supercarrier = 1300, industrial = 180, barge = 160, freighter = 1000, capitalindustrial = 700 }
  -- (name, class, the hull it is the tech 2 make of, a jump drive, built to go unseen)
  local LINE: { { any } } = {
    { "Carvarro", "frigate" }, { "Creavo", "frigate" }, { "Nephelo", "frigate", "Carvarro", nil, true }, { "Meseolo", "destroyer" },
    { "Osso", "destroyer", "Meseolo" }, { "Paestro", "cruiser" }, { "Stenanno", "cruiser" },
    { "Sopholto", "battlecruiser" }, { "Phaeto", "battleship" }, { "Losiano", "battleship" }, { "Scoppo", "carrier", nil, true },
    { "Concorso", "dreadnought" }, { "Nullo", "supercarrier" },
    { "Sunfish", "industrial" }, { "Tarantula", "industrial", "Sunfish", nil, true }, { "Armadillo", "industrial" },
    { "Anteater", "barge" }, { "Rhino", "freighter" }, { "Sugarglider", "freighter", "Rhino", true },
    { "Jaguar", "capitalindustrial" }, { "Rapa", "capitalindustrial", "Jaguar", true },
  }
  t.eq(#assert(talmar.line), #LINE)
  local theirs = 0
  for _, hull in Ships.list do
    theirs += if hull.lineage == "talmar" then 1 else 0
  end
  -- (the twenty-one, and no other: a ship has no "II")
  t.eq(theirs, #LINE)
  for _, entry in LINE do
    local name: string, class: string, of: string?, jump: boolean?, stealth: boolean? = entry[1], entry[2], entry[3], entry[4], entry[5]
    local hull = assert(Ships.byId[`{class}.{string.lower(name)}`], `the Talmar have no {name}`)
    t.eq({ hull.name, hull.class, hull.lineage, hull.radius, hull.jump, hull.stealth } :: { any },
      { `Talmar {name}`, class, "talmar", RADIUS[class], jump, stealth } :: { any }, name)
    if of then
      local base = assert(Ships.byId[`{class}.{string.lower(of)}`])
      t.eq({ hull.tech, hull.base, Ships.Improved(base.id), Ships.byId[base.id .. ".ii"] } :: { any }, { 2, base.id, hull, nil } :: { any }, name)
      -- (and a hauler carries more: a warship's hold is as it was)
      t.ok(hull.shield + hull.armor + hull.hull > base.shield + base.armor + base.hull and hull.cargo >= base.cargo, name)
      t.ok(hull.cargo > base.cargo or not (class == "industrial" or class == "freighter" or class == "capitalindustrial"), name)
      t.eq({ Types.Info(hull.id).scarce, assert(Blueprints.byProduct[hull.id]).invented } :: { any }, { true, true } :: { any }, name)
    else
      t.eq({ hull.tech, Types.Get(hull.id) ~= nil, Blueprints.byProduct[hull.id] ~= nil } :: { any }, { nil, true, true } :: { any }, name)
      t.ok(#Skills.Needs(hull.id) >= 1, name)
    end
  end
  -- A shield people, in every warship; two hulls of a class are the same to the rules, for now.
  for _, pair in { { "frigate.carvarro", "frigate.creavo" }, { "cruiser.paestro", "cruiser.stenanno" }, { "battleship.phaeto", "battleship.losiano" } } do
    local a, b = Ships.byId[pair[1]], Ships.byId[pair[2]]
    t.ok(a.shield > a.armor, a.id)
    t.eq({ a.shield, a.armor, a.hull, a.turrets, a.launchers, a.basePrice }, { b.shield, b.armor, b.hull, b.turrets, b.launchers, b.basePrice })
  end
  -- The combat hauler: half a hauler's hold, twice and more its hull, and guns.
  local hauler, fighter = Ships.byId["industrial.sunfish"], Ships.byId["industrial.armadillo"]
  t.ok(fighter.cargo < 0.5 * hauler.cargo and fighter.armor > 2 * hauler.armor and fighter.turrets + fighter.launchers == 3 and hauler.launchers == 0)
  t.eq(fighter.role, "combat")
  -- A barge of their own mines as the Quarry does, and a freighter of theirs carries as the Dray does.
  local barge, freighter = Ships.byId["barge.anteater"], Ships.byId["freighter.rhino"]
  t.eq({ barge.turrets, barge.launchers, freighter.turrets + freighter.launchers, freighter.rigs } :: { any }, { 3, 0, 0, 0 } :: { any })
  t.ok(freighter.cargo > 30000 and #Skills.Needs(barge.id) == 2)
  -- What they had is gone, and so are the classes their line does not name.
  -- (A Falchion and a Claymore there are again: the Orun's, by the owner's list of theirs, and nothing of the
  -- Talmar's.)
  for _, gone in { "frigate.harrier", "destroyer.sabre", "cruiser.falchion", "battleship.claymore", "industrial.packet" } do
    t.ok(Ships.byId[gone] == nil or Ships.byId[gone].lineage ~= "talmar", gone)
  end
  for _, hull in Ships.list do
    t.ok(hull.lineage ~= "talmar" or (hull.class ~= "attackbattlecruiser" and hull.class ~= "siegedreadnought"), hull.id)
  end
  -- A patrol of theirs flies the first plain hull of a class, and the pirates' frigate is made of it.
  t.eq(Ships.byId["frigate.cutthroat"].donor, "frigate.carvarro")
end)

suite:Case("the Nimia's ships are the owner's list of them: fourteen hulls of living metal, with no shield, that mend; a black ops cruiser, and two capital industrials, one for ore and one for ships", function(t)
  local nimia = Factions.byId.nimia
  t.eq(Factions.byId.skarn, nil, "the Skarn were a stand-in for the Nimia, and are gone")
  t.eq({ nimia.name, nimia.kind, nimia.weapon, nimia.launchers } :: { any }, { "Nimia", "alien", "hybrid", 0 } :: { any })
  local RADIUS = { frigate = 42, destroyer = 75, cruiser = 150, battlecruiser = 300, battleship = 400, carrier = 1000,
    siegedreadnought = 950, supercarrier = 1300, industrial = 180, freighter = 1000, capitalindustrial = 700 }
  -- (name, class, the hull it is the tech 2 make of)
  local LINE: { { any } } = {
    { "O'on", "frigate" }, { "Kri", "destroyer" }, { "Ka'va", "cruiser" }, { "Hon", "cruiser" }, { "Hano", "cruiser", "Hon" },
    { "Hoku", "battlecruiser" }, { "R'ru", "battleship" }, { "Zzk", "siegedreadnought" }, { "Takk", "carrier" },
    { "Yuln", "supercarrier" }, { "Rikn", "industrial" }, { "Joj'k", "freighter" }, { "Zzna", "capitalindustrial" },
    { "Knuu", "capitalindustrial" },
  }
  t.eq(#assert(nimia.line), #LINE)
  local theirs = 0
  for _, hull in Ships.list do
    theirs += if hull.lineage == "nimia" then 1 else 0
  end
  t.eq(theirs, #LINE)
  for _, entry in LINE do
    local name: string, class: string, of: string? = entry[1], entry[2], entry[3]
    -- (a hull's id is its class and the letters of its name: an apostrophe is not one)
    local id = `{class}.{string.lower((string.gsub(name, "[^%a]", "")))}`
    local hull = assert(Ships.byId[id], `the Nimia have no {name}`)
    t.eq({ hull.name, hull.class, hull.lineage, hull.radius } :: { any }, { `Nimia {name}`, class, "nimia", RADIUS[class] } :: { any }, name)
    -- An alien people's: nothing of theirs is on a human market, and its drawings are to be found.
    -- (since 2026-11-16 an item with drawings, which nobody sells: the owner's "create blueprints for the alien towers and ships")
    t.ok(hull.foreign and not hull.restricted and hull.rare and Types.Get(hull.id) ~= nil, name)
    t.ok(Blueprints.byProduct[hull.id] ~= nil and Blueprints.byProduct[hull.id].rare, name)
    -- No shield, and armour and hull that mend; more of both than a hull of its class has, to stand in for the shield.
    t.eq({ hull.shield, hull.armorMend, hull.hullMend } :: { any }, { 0, 0.004, 0.002 } :: { any }, name)
    t.eq(hull.launchers, 0, name)
    if of then
      local base = assert(Ships.byId[`{class}.{string.lower(of)}`])
      t.eq({ hull.tech, hull.base, Ships.Improved(base.id) } :: { any }, { 2, base.id, hull } :: { any }, name)
    else
      t.eq(hull.tech, nil, name)
      t.ok(#Skills.Needs(hull.id) >= 1, name)
    end
    -- Every one has a seed to be drawn from.
    t.ok(Facts.Of(hull.id) ~= nil, name)
  end
  -- The Hano is the black ops make of the Hon, and of no other cruiser of theirs.
  local hano = Ships.byId["cruiser.hano"]
  t.eq({ hano.stealth, hano.cloak, hano.base } :: { any }, { true, nil, "cruiser.hon" } :: { any })
  t.eq(Ships.Improved("cruiser.kava"), nil)
  -- Their warships carry blasters: a frigate of theirs has a hardpoint more than the plain one, and they are all turrets.
  local oon = Ships.byId["frigate.oon"]
  t.eq({ oon.turrets, oon.launchers } :: { any }, { 4, 0 } :: { any })
  t.ok(oon.lows > oon.mids, "their repair gear goes in low slots, and they have the more of those")
  -- The Zzna is a mining capital: an ore hold, and no turret. The Knuu carries ships.
  local zzna, knuu = Ships.byId["capitalindustrial.zzna"], Ships.byId["capitalindustrial.knuu"]
  t.eq({ zzna.turrets + zzna.launchers, zzna.role, zzna.ore, zzna.shipbay } :: { any }, { 0, nil, Ships.ORE.capitalindustrial, nil } :: { any })
  t.eq({ knuu.turrets + knuu.launchers, knuu.role, knuu.ore, knuu.shipbay } :: { any }, { 0, "transport", 0, Ships.SHIPBAY } :: { any })
  -- What a sheet says of one.
  local sheet = assert(Facts.Of("frigate.oon"))
  local said: { [string]: string } = {}
  for _, section in sheet.sections do
    for _, row in section.rows do
      said[row.label] = row.value
    end
  end
  t.eq(sheet.kind, "Nimia frigate")
  t.ok(string.find(said["Shield"], "none", 1, true) ~= nil and said["Mends by itself"] ~= nil, "the sheet does not say it has no shield and mends")
  t.eq(assert(Facts.Of("capitalindustrial.knuu")).kind, "Nimia logistics capital")
  t.eq(assert(Facts.Of("cruiser.hano")).kind, "Nimia tech 2 black ops cruiser")
end)

suite:Case("the Vail's ships are the owner's list of them: seventeen hulls, two of them tech 2 hulls of their own (one black ops), an ultracapital whose jump drive has a field, and no hauler, siege dreadnought or supercarrier", function(t)
  local vail = Factions.byId.vail
  t.eq({ vail.name, vail.kind } :: { any }, { "Vail", "alien" } :: { any })
  local RADIUS = { frigate = 42, destroyer = 75, cruiser = 150, attackbattlecruiser = 200, battlecruiser = 300, battleship = 400,
    carrier = 1000, dreadnought = 1300, barge = 160, freighter = 1000, capitalindustrial = 700, ultracapital = 1050 }
  -- (name, class, the hull it is the tech 2 make of)
  local LINE: { { any } } = {
    { "Prostration", "frigate" }, { "Undulation", "frigate" }, { "Exaltation", "destroyer" }, { "Adoration", "destroyer" },
    { "Aberration", "destroyer", "Adoration" }, { "Enervation", "cruiser" }, { "Interstition", "cruiser", "Enervation" },
    { "Intervention", "attackbattlecruiser" }, { "Innocence", "battlecruiser" }, { "Penance", "battleship" },
    { "Extravagance", "battleship" }, { "Accordance", "carrier" }, { "Awe", "dreadnought" }, { "Panacea", "barge" },
    { "Indulgence", "freighter" }, { "Embrace", "capitalindustrial" }, { "Archangel", "ultracapital" },
  }
  t.eq(#assert(vail.line), #LINE)
  local theirs = 0
  for _, hull in Ships.list do
    theirs += if hull.lineage == "vail" then 1 else 0
    -- The hulls they had before the list are gone, and the classes the list has none of are not built.
    t.ok(hull.lineage ~= "vail" or (hull.class ~= "industrial" and hull.class ~= "siegedreadnought" and hull.class ~= "supercarrier"), hull.id)
  end
  t.eq(theirs, #LINE)
  t.eq({ Ships.byId["frigate.thorn"], Ships.byId["battleship.harpoon"], Ships.byId["industrial.drover"] } :: { any }, {})
  for _, entry in LINE do
    local name: string, class: string, of: string? = entry[1], entry[2], entry[3]
    local id = `{class}.{string.lower(name)}`
    local hull = assert(Ships.byId[id], `the Vail have no {name}`)
    t.eq({ hull.name, hull.class, hull.lineage, hull.radius } :: { any }, { `Vail {name}`, class, "vail", RADIUS[class] } :: { any }, name)
    -- An alien people's: nothing of theirs is on a human market, and its drawings are to be found.
    -- (since 2026-11-16 an item with drawings, which nobody sells: the owner's "create blueprints for the alien towers and ships")
    t.ok(hull.foreign and not hull.restricted and hull.rare and Types.Get(hull.id) ~= nil, name)
    t.ok(Blueprints.byProduct[hull.id] ~= nil and Blueprints.byProduct[hull.id].rare, name)
    -- Their guns are all turrets, and their hulls have a shield (they are not the Nimia).
    t.eq(hull.launchers, 0, name)
    t.ok(hull.shield > 0 and hull.armorMend == nil, name)
    if of then
      local base = assert(Ships.byId[`{class}.{string.lower(of)}`])
      t.eq({ hull.tech, hull.base, Ships.Improved(base.id) } :: { any }, { 2, base.id, hull } :: { any }, name)
    else
      t.eq(hull.tech, nil, name)
      t.ok(#Skills.Needs(hull.id) >= 1, name)
    end
    t.ok(Facts.Of(hull.id) ~= nil, name)
  end
  -- The owner's ladder holds for them: four of a battleship's guns on the attack battlecruiser, eight on the
  -- battlecruiser, twenty on the dreadnought, none on the carrier; a barge's three are for mining.
  local function guns(id: string): number
    return Ships.byId[id].turrets + Ships.byId[id].launchers
  end
  t.eq({ guns("attackbattlecruiser.intervention"), guns("battlecruiser.innocence"), guns("dreadnought.awe"), guns("carrier.accordance"),
    guns("barge.panacea"), guns("freighter.indulgence"), guns("capitalindustrial.embrace") }, { 4, 8, 20, 0, 3, 0, 0 })
  -- A patrol of theirs flies the first plain hull of a class.
  t.eq({ Ships.Improved("frigate.prostration"), Ships.Improved("destroyer.exaltation"), Ships.Improved("battleship.penance") } :: { any }, {})
  -- What each tech 2 hull is for: the Interstition goes unseen, and the Aberration is the plain make (the
  -- owner's word for both).
  local aberration, interstition = Ships.byId["destroyer.aberration"], Ships.byId["cruiser.interstition"]
  t.eq({ aberration.stealth, aberration.cloak, aberration.jump, aberration.explorer } :: { any }, {})
  t.eq({ interstition.stealth, interstition.cloak, interstition.jump } :: { any }, { true, nil, nil } :: { any })
  -- The Archangel is their ultracapital (the owner's: "roughly 1.5x as large as the plain Embrace", with a
  -- jump drive whose field takes every friendly ship within 5 km): half as big again as the Embrace, a jump
  -- drive with a field, and no hardpoint. It was the tech 2 make of the Embrace for a day, and is not.
  local archangel, embrace, awe = Ships.byId["ultracapital.archangel"], Ships.byId["capitalindustrial.embrace"], Ships.byId["dreadnought.awe"]
  t.eq(Ships.byId["capitalindustrial.archangel"], nil)
  t.eq({ archangel.radius / embrace.radius, archangel.jump, archangel.jumpField, archangel.tech, archangel.turrets + archangel.launchers } :: { any },
    { 1.5, true, 5000, nil, 0 } :: { any })
  t.eq({ embrace.jump, embrace.jumpField, Ships.Improved(embrace.id) } :: { any }, {})
  -- So much smaller than the class is written for, it is that much less of one in bulk: heavier than the
  -- capital industrial it comes of and lighter than their dreadnought, which is bigger; where the Vessari's
  -- ultracapital, which is as big as the class, is as the class is.
  t.ok(archangel.mass > embrace.mass and archangel.mass < 2 * embrace.mass and archangel.mass < awe.mass, `it masses {archangel.mass}`)
  t.ok(archangel.shield > embrace.shield and archangel.shield < 1.2 * awe.shield, `its shield is {archangel.shield}`)
  local daiichi = Ships.byId["ultracapital.daiichi"]
  t.ok(daiichi.mass > 5 * archangel.mass and (daiichi.bay or 0) == Ships.BAY.ultracapital and (archangel.bay or 0) < Ships.BAY.ultracapital)
  local sheet = assert(Facts.Of("ultracapital.archangel"))
  local built: { [string]: boolean } = {}
  for _, section in sheet.sections do
    for _, row in section.rows do
      built[row.label] = true
    end
  end
  t.eq({ sheet.kind, built["Jump drive"], built["Jump field"] } :: { any }, { "Vail ultracapital", true, true } :: { any })
  t.eq(assert(Facts.Of("cruiser.interstition")).kind, "Vail tech 2 black ops cruiser")
  t.eq(assert(Facts.Of("frigate.undulation")).kind, "Vail frigate")
end)

suite:Case("the Drowned's ships are the owner's list of them: fifteen hulls, every plain one with a cloak of its own, two tech 2 hulls with a jump drive and no cloak; and they are a people of the deep", function(t)
  local drowned = Factions.byId.drowned
  t.eq(Factions.byId.tessellate, nil, "the Tessellate were a stand-in for the Drowned, and are gone")
  -- A people of the deep: they hold nothing on the map. Every plain hull of theirs has a cloak of its own,
  -- their guns are railguns, and a wreck of theirs has what its hull is made of in it.
  t.eq({ drowned.name, drowned.kind, drowned.deep, drowned.cloaks, drowned.weapon, drowned.gun, drowned.launchers, drowned.wreck } :: { any },
    { "Drowned", "alien", true, true, "hybrid", "railgun", 0, "alloy.benthic" } :: { any })
  t.ok(Types.Get("alloy.benthic") ~= nil and Types.Info("alloy.benthic").basePrice > 10 * Types.Info("tag.pirate").basePrice)
  for _, faction in Factions.list do
    t.eq(faction.deep, if faction.id == "drowned" then true else nil, faction.id)
  end
  local RADIUS = { frigate = 42, destroyer = 75, cruiser = 150, battlecruiser = 300, battleship = 400, carrier = 1000,
    dreadnought = 1300, siegedreadnought = 950, ultracapital = 2000, industrial = 180, freighter = 1000, capitalindustrial = 700 }
  -- (name, class, the hull it is the tech 2 make of)
  local LINE: { { any } } = {
    { "Cairn", "frigate" }, { "Charon", "frigate" }, { "Gravestone", "destroyer" }, { "Casket", "cruiser" },
    { "Rebirth", "cruiser", "Casket" }, { "Graveyard Keeper", "battlecruiser" }, { "Coffin", "battleship" },
    { "Funeral Procession", "carrier" }, { "The Reaper", "dreadnought" }, { "The Mercy", "siegedreadnought" },
    { "The End", "ultracapital" }, { "Hearse", "industrial" }, { "Griever", "capitalindustrial" }, { "Cemetery", "freighter" },
    { "Resurrection", "freighter", "Cemetery" },
  }
  t.eq(#assert(drowned.line), #LINE)
  local theirs = 0
  for _, hull in Ships.list do
    theirs += if hull.lineage == "drowned" then 1 else 0
  end
  t.eq(theirs, #LINE)
  for _, entry in LINE do
    local name: string, class: string, of: string? = entry[1], entry[2], entry[3]
    -- (a hull's id is its class and the letters of its name; and one whose name begins "The" goes by that alone)
    local id = `{class}.{string.lower((string.gsub(name, "[^%a]", "")))}`
    local hull = assert(Ships.byId[id], `the Drowned have no {name}`)
    t.eq({ hull.name, hull.class, hull.lineage, hull.radius } :: { any },
      { if string.sub(name, 1, 4) == "The " then name else `Drowned {name}`, class, "drowned", RADIUS[class] } :: { any }, name)
    -- (since 2026-11-16 an item with drawings, which nobody sells: the owner's "create blueprints for the alien towers and ships")
    t.ok(hull.foreign and not hull.restricted and hull.rare and Types.Get(hull.id) ~= nil, name)
    t.ok(Blueprints.byProduct[hull.id] ~= nil and Blueprints.byProduct[hull.id].rare, name)
    t.eq(hull.launchers, 0, name)
    if of then
      -- A tech 2 hull of theirs: "no builtin cloak. can fit jumpdrive".
      local base = assert(Ships.byId[`{class}.{string.lower(of)}`])
      t.eq({ hull.tech, hull.base, Ships.Improved(base.id), hull.cloak, hull.jump } :: { any }, { 2, base.id, hull, nil, true } :: { any }, name)
    else
      t.eq({ hull.tech, hull.cloak, hull.jump } :: { any }, { nil, true, nil } :: { any }, name)
      t.ok(#Skills.Needs(hull.id) >= 1, name)
    end
    t.ok(Facts.Of(hull.id) ~= nil, name)
  end
  -- The cloak a hull has of its own takes nothing to fit: a Cairn with every slot it has to fit with.
  local cairn = Ships.byId["frigate.cairn"]
  t.eq({ cairn.turrets, cairn.launchers } :: { any }, { 3, 0 } :: { any })
  -- The Griever mines for itself: ten mining turrets, and an ore hold. The End is their ultracapital.
  local griever, last = Ships.byId["capitalindustrial.griever"], Ships.byId["ultracapital.theend"]
  t.eq({ griever.role, griever.turrets, griever.launchers, griever.ore } :: { any }, { "miner", 10, 0, Ships.ORE.capitalindustrial } :: { any })
  t.eq({ last.name, last.class, last.cloak } :: { any }, { "The End", "ultracapital", true } :: { any })
  t.eq(assert(Facts.Of("frigate.cairn")).kind, "Drowned frigate")
end)

suite:Case("the Orun's ships are the owner's list of them: nineteen hulls, six of them tech 2 hulls of their own, with a barge, a freighter and a capital industrial that leads a mining fleet", function(t)
  local orun = Factions.byId.orun
  local RADIUS = { frigate = 42, destroyer = 75, cruiser = 150, battlecruiser = 300, battleship = 400, carrier = 1000,
    siegedreadnought = 950, barge = 160, industrial = 180, freighter = 1000, capitalindustrial = 700 }
  -- (name, class, the hull it is the tech 2 make of)
  local LINE: { { any } } = {
    { "Skinner", "frigate" }, { "Skiver", "frigate", "Skinner" }, { "Knife", "frigate" },
    { "Scythe", "destroyer" }, { "Kama", "destroyer", "Scythe" },
    { "Armer", "cruiser" }, { "Gladius", "cruiser" }, { "Falchion", "cruiser", "Gladius" },
    { "Zweihander", "battlecruiser" }, { "Claymore", "battleship" }, { "Katana", "carrier" }, { "Excalibur", "carrier", "Katana" },
    { "Sword", "siegedreadnought" }, { "Guthook", "siegedreadnought", "Sword" },
    { "Scarab", "barge" }, { "Pill", "industrial" }, { "Longhorn", "industrial", "Pill" }, { "Tiger", "freighter" },
    { "Stag", "capitalindustrial" },
  }
  t.eq(#assert(orun.line), #LINE)
  local theirs = 0
  for _, hull in Ships.list do
    theirs += if hull.lineage == "orun" then 1 else 0
  end
  t.eq(theirs, #LINE)
  for _, entry in LINE do
    local name: string, class: string, of: string? = entry[1], entry[2], entry[3]
    local hull = assert(Ships.byId[`{class}.{string.lower(name)}`], `the Orun have no {name}`)
    t.eq({ hull.name, hull.class, hull.lineage, hull.radius } :: { any }, { `Orun {name}`, class, "orun", RADIUS[class] } :: { any }, name)
    if of then
      local base = assert(Ships.byId[`{class}.{string.lower(of)}`])
      t.eq({ hull.tech, hull.base, Ships.Improved(base.id) } :: { any }, { 2, base.id, hull } :: { any }, name)
      t.eq(Types.Info(hull.id).scarce, true, name)
    else
      t.eq({ hull.tech, Types.Get(hull.id) ~= nil, Blueprints.byProduct[hull.id] ~= nil } :: { any }, { nil, true, true } :: { any }, name)
      t.ok(#Skills.Needs(hull.id) >= 1, name)
    end
    -- An armour people, in every hull that has a turret; and no launcher on any.
    if hull.turrets > 0 and class ~= "barge" then
      t.ok(hull.armor > hull.shield, name)
    end
    t.eq(hull.launchers, 0, name)
  end
  -- (a frigate with two hulls beside it and a cruiser with one: each tech 2 hull comes of the one it says)
  t.eq(Ships.Improved("frigate.knife"), nil)
  t.eq(Ships.Improved("cruiser.armer"), nil)
  -- The Stag leads a mining fleet and does not mine: no hardpoint, and the ore hold the fleet's barges fill.
  local stag = Ships.byId["capitalindustrial.stag"]
  t.eq({ stag.turrets + stag.launchers, stag.role, stag.ore } :: { any }, { 0, nil, Ships.ORE.capitalindustrial } :: { any })
  -- A barge of their own mines as the Quarry does, and a freighter of theirs carries as the Dray does.
  local barge, freighter = Ships.byId["barge.scarab"], Ships.byId["freighter.tiger"]
  t.eq({ barge.turrets, barge.launchers, freighter.turrets + freighter.launchers, freighter.rigs } :: { any }, { 3, 0, 0, 0 } :: { any })
  t.ok(freighter.cargo > 30000 and #Skills.Needs(barge.id) == 2)
  -- The siege dreadnought: four hardpoints, for the largest guns there are; and its tech 2 make eight ("t2
  -- siege dreadnought (8x guns)"), with the high slots and the powergrid for them.
  local sword, guthook = Ships.byId["siegedreadnought.sword"], Ships.byId["siegedreadnought.guthook"]
  t.eq({ sword.turrets, guthook.turrets, guthook.launchers, guthook.highs - sword.highs } :: { any }, { 4, 8, 0, 4 } :: { any })
  t.ok(guthook.powergrid > 2 * sword.powergrid and guthook.cpu > 2 * sword.cpu)
  -- What they had is gone, and so are the classes their line does not name.
  for _, gone in { "frigate.mastiff", "destroyer.boar", "cruiser.aurochs", "battleship.mammoth", "industrial.ox" } do
    t.eq(Ships.byId[gone], nil, gone)
  end
  for _, hull in Ships.list do
    t.ok(hull.lineage ~= "orun" or (hull.class ~= "attackbattlecruiser" and hull.class ~= "dreadnought" and hull.class ~= "supercarrier"),
      hull.id)
  end
  -- The pirates' destroyer, hauler, carrier and siege dreadnought are made over from theirs. (Their attack
  -- battlecruiser was: nobody builds one now, and it is the Kethri's battlecruiser cut down.)
  t.eq({ Ships.byId["destroyer.jackal"].donor, Ships.byId["industrial.fence"].donor, Ships.byId["carrier.warren"].donor,
    Ships.byId["siegedreadnought.despoiler"].donor, Ships.byId["attackbattlecruiser.reaver"].donor } :: { any },
    { "destroyer.scythe", "industrial.pill", "carrier.katana", "siegedreadnought.sword", "battlecruiser.extremis" } :: { any })
end)

suite:Case("the Kethri's ships are the owner's list of them: fifteen hulls, two of them tech 2, two hardpoints in ten of them launchers, and a colony ship ten kilometres long with 140 hardpoints that nobody sells", function(t)
  local kethri = Factions.byId.kethri
  local RADIUS = { frigate = 42, destroyer = 75, cruiser = 150, battlecruiser = 300, battleship = 400, carrier = 1000, dreadnought = 1300,
    ultracapital = 5000, barge = 160, industrial = 180, freighter = 1000, capitalindustrial = 700 }
  -- (name, class, the hull's own name in its id, the hull it is the tech 2 make of)
  local LINE: { { any } } = {
    { "Battleaxe", "frigate" }, { "Gauntlet", "frigate" }, { "Sentry", "destroyer" }, { "Noxious", "destroyer", nil, "Sentry" },
    { "Perfexis", "cruiser" }, { "Extremis", "battlecruiser" }, { "Deluge", "battlecruiser", nil, "Extremis" },
    { "Teardrop", "battleship" }, { "Tennit", "carrier" }, { "Pox", "dreadnought" }, { "Porter", "industrial" }, { "Hiven", "freighter" }, { "Pulley", "barge" },
    { "Piton", "capitalindustrial" }, { "Les Larmes de Nova", "ultracapital", "leslarmesdenova" },
  }
  t.eq(#assert(kethri.line), #LINE)
  local theirs = 0
  for _, hull in Ships.list do
    theirs += if hull.lineage == "kethri" then 1 else 0
  end
  t.eq(theirs, #LINE)
  for _, entry in LINE do
    local name: string, class: string, of: string? = entry[1], entry[2], entry[4]
    local hull = assert(Ships.byId[`{class}.{entry[3] or string.lower(name)}`], `the Kethri have no {name}`)
    t.eq({ hull.name, hull.class, hull.lineage, hull.radius, hull.tech, hull.base } :: { any },
      { `Kethri {name}`, class, "kethri", RADIUS[class], if of then 2 else nil, if of then `{class}.{string.lower(of)}` else nil } :: { any },
      name)
    t.ok(Types.Get(hull.id) ~= nil and Blueprints.byProduct[hull.id] ~= nil and #Skills.Needs(hull.id) >= 1, name)
    -- An armour people; and of a warship's hardpoints about two in ten are launchers (a frigate has three
    -- hardpoints: the Battleaxe, written out by hand, is all lasers, and the Gauntlet has one launcher).
    if hull.turrets + hull.launchers > 0 and class ~= "barge" and class ~= "industrial" then
      t.ok(hull.armor > hull.shield, name)
      local share = hull.launchers / (hull.turrets + hull.launchers)
      t.ok(class == "frigate" and hull.launchers <= 1 or share >= 0.12 and share <= 0.26, `{name}: {hull.launchers} launchers of {hull.turrets + hull.launchers}`)
    end
  end
  -- The colony ship: fifty hardpoints for small weapons, forty for medium, thirty for large and twenty for XL,
  -- and of each size two in ten are launchers.
  local ship = Ships.byId["ultracapital.leslarmesdenova"]
  t.eq({ ship.guns, ship.racks } :: { any }, { { 40, 32, 24, 16 }, { 10, 8, 6, 4 } } :: { any })
  t.eq({ ship.turrets, ship.launchers, Ships.Capital(ship.class), Skills.Needs(ship.id)[1].skill } :: { any },
    { 112, 28, true, "ultracapitals" } :: { any })
  t.ok(ship.highs >= 140 and assert(ship.bay) >= Ships.BAY.ultracapital)
  -- It has the fitting for a beam laser on every turret hardpoint and a launcher on every other, each of its
  -- hardpoint's size.
  local SIZES = { "small", "medium", "large", "xl" }
  local RACKS = { "launcher.light", "launcher.heavy", "launcher.cruise", "launcher.siege" }
  local all: { string } = {}
  for size = 1, 4 do
    for _ = 1, assert(ship.guns)[size] do
      table.insert(all, `laser.beam.{SIZES[size]}`)
    end
    for _ = 1, assert(ship.racks)[size] do
      table.insert(all, RACKS[size])
    end
  end
  t.eq(#all, 140)
  t.eq({ Attributes.Check(ship, all) } :: { any }, { true } :: { any })
  -- A weapon goes on a hardpoint of its own size or a bigger: not one XL gun more than it has the hardpoints
  -- for, though a small gun will go where a large one would.
  local over = table.clone(all)
  table.remove(over, 1)
  table.insert(over, "laser.beam.xl")
  t.eq({ Attributes.Check(ship, over) } :: { any }, { false, "no free hardpoint for a XL turret" } :: { any })
  local under: { string } = {}
  for _ = 1, 112 do
    table.insert(under, "laser.pulse.small")
  end
  t.eq({ Attributes.Check(ship, under) } :: { any }, { true } :: { any })
  table.insert(under, "launcher.siege")
  table.insert(under, "launcher.siege")
  table.insert(under, "launcher.siege")
  table.insert(under, "launcher.siege")
  t.eq({ Attributes.Check(ship, under) } :: { any }, { true } :: { any })
  table.insert(under, "launcher.siege")
  t.eq({ Attributes.Check(ship, under) } :: { any }, { false, "no free hardpoint for a XL launcher" } :: { any })
  -- Nobody sells it, nor the blueprint for it; and nobody invents it. It can be built by whoever comes by one.
  t.eq({ ship.rare, Types.Info(ship.id).scarce, Types.Info(`blueprint.{ship.id}`).scarce, Blueprints.byProduct[ship.id].rare,
    Blueprints.byProduct[ship.id].invented } :: { any }, { true, true, true, true, nil } :: { any })
  -- (the Vessari's ultracapital, which anybody can buy, has no hardpoint at all)
  t.eq({ Ships.byId["ultracapital.daiichi"].rare, Ships.byId["ultracapital.daiichi"].guns } :: { any }, {})
  -- The Piton leads a mining fleet, as the Orun's Stag does; and the barge mines.
  local piton, pulley = Ships.byId["capitalindustrial.piton"], Ships.byId["barge.pulley"]
  t.eq({ piton.turrets + piton.launchers, piton.ore, pulley.turrets, pulley.launchers } :: { any },
    { 0, Ships.ORE.capitalindustrial, 3, 0 } :: { any })
  -- What they had is gone, and so are the classes their line does not name.
  for _, gone in { "frigate.lancer", "destroyer.gantry", "cruiser.trellis", "battleship.spire", "industrial.lighter" } do
    t.eq(Ships.byId[gone], nil, gone)
  end
  for _, hull in Ships.list do
    t.ok(hull.lineage ~= "kethri" or (hull.class ~= "attackbattlecruiser" and hull.class ~= "siegedreadnought"
      and hull.class ~= "supercarrier"), hull.id)
  end
  -- The pirates' battleship is made over from theirs, and their attack battlecruiser from the Extremis, cut down.
  t.eq({ Ships.byId["battleship.ravager"].donor, Ships.byId["attackbattlecruiser.reaver"].donor } :: { any },
    { "battleship.teardrop", "battlecruiser.extremis" } :: { any })
end)

suite:Case("the Vessari's ships are the owner's list of them: an ultracapital four kilometres wide, a mass-miner with ten mining turrets, an attack battlecruiser, and four tech 2 hulls of their own, two of one cruiser", function(t)
  local vessari = Factions.byId.vessari
  local RADIUS = { frigate = 42, destroyer = 75, cruiser = 150, attackbattlecruiser = 200, battlecruiser = 300, battleship = 400,
    carrier = 1000, ultracapital = 2060, industrial = 180, freighter = 1000, capitalindustrial = 700 }
  -- (name, class, the hull it is the tech 2 make of)
  local LINE: { { any } } = {
    { "Akashi", "frigate" }, { "Kabuto", "frigate" }, { "Nozomi", "destroyer" }, { "Kanau", "destroyer", "Nozomi" }, { "Ouyou", "cruiser" },
    { "Hoshizora", "cruiser", "Ouyou" }, { "Raiden", "cruiser", "Ouyou" }, { "Manazashi", "attackbattlecruiser" }, { "Naishou", "battlecruiser" }, { "Owari", "battleship" }, { "Yoake", "battleship" }, { "Azayake", "carrier" },
    { "Daiichi", "ultracapital" }, { "Mizumushi", "industrial" }, { "Akaboshi", "industrial", "Mizumushi" },
    { "Yoruzake", "freighter" }, { "Okami", "capitalindustrial" },
  }
  t.eq(#assert(vessari.line), #LINE)
  local theirs = 0
  for _, hull in Ships.list do
    theirs += if hull.lineage == "vessari" then 1 else 0
  end
  t.eq(theirs, #LINE)
  for _, entry in LINE do
    local name: string, class: string, of: string? = entry[1], entry[2], entry[3]
    local hull = assert(Ships.byId[`{class}.{string.lower(name)}`], `the Vessari have no {name}`)
    t.eq({ hull.name, hull.class, hull.lineage, hull.radius } :: { any }, { `Vessari {name}`, class, "vessari", RADIUS[class] } :: { any }, name)
    if of then
      local base = assert(Ships.byId[`{class}.{string.lower(of)}`])
      t.eq({ hull.tech, hull.base, table.find(Ships.ImprovedAll(base.id), hull) ~= nil } :: { any }, { 2, base.id, true } :: { any }, name)
      t.eq(Types.Info(hull.id).scarce, true, name)
    else
      t.eq({ hull.tech, Types.Get(hull.id) ~= nil, Blueprints.byProduct[hull.id] ~= nil } :: { any }, { nil, true, true } :: { any }, name)
      t.ok(#Skills.Needs(hull.id) >= 1, name)
    end
    -- An armour people, in every warship; and mostly launchers.
    if class ~= "industrial" and class ~= "freighter" and class ~= "capitalindustrial" then
      t.ok(hull.armor > hull.shield, name)
      t.ok(hull.launchers >= hull.turrets, name)
    end
  end
  -- The ultracapital: no hardpoint, and a bay for what it launches many times a supercarrier's.
  local great = Ships.byId["ultracapital.daiichi"]
  t.eq({ great.turrets + great.launchers, Ships.Capital(great.class) } :: { any }, { 0, true } :: { any })
  t.ok(assert(great.bay) > 5 * Ships.BAY.supercarrier and assert(great.drones) > Ships.DRONES.supercarrier)
  t.eq(Skills.Needs(great.id)[1].skill, "ultracapitals")
  -- The mass-miner: a capital industrial with ten mining turrets, and the fitting for ten strip miners.
  local miner, strip = Ships.byId["capitalindustrial.okami"], Modules.byId["miner.strip"]
  t.eq({ miner.turrets, miner.launchers, miner.role } :: { any }, { 10, 0, "miner" } :: { any })
  t.ok(miner.highs >= 10 and 10 * strip.cpu <= miner.cpu and 10 * strip.powergrid <= miner.powergrid)
  -- (the Talmar's capital industrial, which commands and does not mine, has none)
  t.eq(Ships.byId["capitalindustrial.jaguar"].turrets, 0)
  -- What they had is gone, and so are the classes their line does not name.
  for _, gone in { "frigate.javelin", "destroyer.halberd", "cruiser.cuirass", "battleship.bastion", "industrial.caravan" } do
    t.eq(Ships.byId[gone], nil, gone)
  end
  for _, hull in Ships.list do
    t.ok(hull.lineage ~= "vessari" or (hull.class ~= "dreadnought"
      and hull.class ~= "siegedreadnought" and hull.class ~= "supercarrier" and hull.class ~= "barge"), hull.id)
  end
  -- The pirates' cruiser is made over from theirs.
  t.eq(Ships.byId["cruiser.marauder"].donor, "cruiser.ouyou")
  -- The Ouyou has two tech 2 makes: the Hoshizora, for electronic warfare, and the Raiden, their special
  -- ship, with a bow railgun of a cruiser's.
  local hoshi, raiden = Ships.byId["cruiser.hoshizora"], Ships.byId["cruiser.raiden"]
  t.eq({ hoshi.ewar, hoshi.spinal, raiden.ewar, raiden.spinal ~= nil } :: { any }, { true, nil, nil, true } :: { any })
  t.ok(assert(raiden.spinal).capacitor < raiden.capacitor, "a cruiser can pay for a round of its own bow railgun")
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
    -- (of its own class, or where they say so of a bigger, cut down: nobody builds an attack battlecruiser)
    t.eq(original.class, (Factions.byId.unbound.cut or {})[class] or class)
    t.eq(original.lineage, donors[class])
    t.eq(Factions.byId[original.lineage].kind, "human")
    t.ok(hull.basePrice < original.basePrice, hull.id)
    if class ~= "industrial" then
      t.ok(hull.maxVelocity > 0.98 * original.maxVelocity, hull.id)
      -- (more guns than it was built for; but for the classes whose hardpoints are the same whoever builds them,
      -- and for a hull cut down from a bigger class, which has fewer and larger)
      t.ok(hull.turrets + hull.launchers > original.turrets + original.launchers or original.id == "frigate.carvarro"
        or original.class ~= class
        or (Factions.CLASSES[5] ~= class and table.find(Factions.CLASSES, class) :: number > 5
          and hull.turrets + hull.launchers == original.turrets + original.launchers), hull.id)
    end
  end
end)

suite:Case("a ship has no \"II\": a tech 2 ship is a hull of its own, named in its faction's line, that comes of a plain one: tougher, roomier, built of the plain hull, and nobody's to buy", function(t)
  local improved = 0
  for _, hull in Ships.list do
    local faction = Factions.byId[hull.lineage]
    if hull.tech == 2 then
      improved += 1
      local base = Ships.byId[hull.base :: string]
      -- (a hull with a name of its own, which its faction's line gives it: no hull is another's "II")
      t.eq({ hull.class, hull.lineage } :: { any }, { base.class, base.lineage } :: { any })
      t.ok(hull.class ~= "drone" and string.sub(hull.id, -3) ~= ".ii" and string.sub(hull.name, -3) ~= " II", hull.id)
      t.ok(faction ~= nil and faction.line ~= nil, hull.id)
      t.ok(table.find(Ships.ImprovedAll(base.id), hull) ~= nil, hull.id)
      t.ok(base.tech == nil and Ships.Improved(hull.id) == nil, "a tech 2 hull has no tech 2 make of its own")
      -- The same hull to look at and to arm: its hardpoints, its size, its drones. (But the Orun's Guthook, with
      -- twice the Sword's hardpoints, by its line.)
      t.eq({ hull.radius, hull.mass, hull.drones, hull.bay } :: { any }, { base.radius, base.mass, base.drones, base.bay } :: { any })
      if hull.id ~= "siegedreadnought.guthook" then
        t.eq({ hull.turrets, hull.launchers, hull.highs } :: { any }, { base.turrets, base.launchers, base.highs } :: { any }, hull.id)
      end
      -- More of it to shoot through, and less of every shot gets through.
      -- (of what it has: a hull of the Nimia's has no shield, tech 2 or plain)
      -- (by more than a fifth, after a capital's figures are rounded to two places: the Orun's Excalibur)
      t.ok((hull.shield > 1.2 * base.shield or base.shield == 0) and hull.armor > 1.2 * base.armor and hull.hull > 1.2 * base.hull,
        hull.id)
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
      local carrier = base.class == "industrial" or base.class == "barge" or base.class == "freighter" or base.class == "capitalindustrial"
        or base.id == "frigate.prospector"
      t.near(hull.cargo / base.cargo, if carrier then 1.5 else 1, 0.03, hull.id)
      t.eq(hull.basePrice, base.basePrice * 8)
      -- More skill than the plain one, and never less than four of it.
      local needs, plain = Skills.Needs(hull.id), Skills.Needs(base.id)
      t.ok(#needs >= 1 and #needs == #plain, hull.id)
      for index, need in needs do
        t.ok(need.level >= 4 and need.level <= 5 and need.skill == plain[index].skill and need.level > plain[index].level, hull.id)
      end
      -- (An alien people's is no more a human's to buy or to build than the hull it comes of: the Nimia's Hano.)
      if hull.foreign then
        local found = assert(Blueprints.byProduct[hull.id], `no blueprint for {hull.id}`)
        t.ok(base.foreign and found.rare and not found.invented and Types.Get(hull.id) ~= nil, hull.id)
        continue
      end
      -- No station has one to sell, nor its blueprint; it is built of the plain hull, components and what lawless space has.
      local blueprint = assert(Blueprints.byProduct[hull.id], `no blueprint for {hull.id}`)
      t.eq({ Types.Info(hull.id).scarce, Types.Info(blueprint.id).scarce, blueprint.invented } :: { any }, { true, true, true } :: { any })
      t.eq({ blueprint.materials[1].type, blueprint.materials[1].quantity } :: { any }, { base.id, 1 } :: { any })
      local rare, components, moon = 0, 0, 0
      -- (and of what a reactor makes of what is drilled out of moons: one composite, of the grade for a hull its size)
      local grade = if hull.class == "battleship" or hull.class == "freighter" or Ships.Capital(hull.class) then 3
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
      -- (a hull has one where its faction's line names one, and nowhere else)
      local should = false
      for _, entry in (if faction then faction.line else nil) or {} :: { Factions.Hull } do
        should = should or (entry.tech == 2 and hull.name == `{(faction :: Factions.Faction).name} {entry.of}`)
      end
      t.ok(hull.class == "drone" or Ships.byId[hull.id .. ".ii"] == nil, `{hull.id} has a "II"`)
      t.eq(Ships.Improved(hull.id) ~= nil, should, hull.id)
      -- (and it is to be bought, unless it is a hull nobody sells: the Kethri's colony ship)
      t.eq(Types.Get(hull.id) == nil or Types.Info(hull.id).scarce == (if hull.rare then true else nil), true, hull.id)
    end
  end
  -- The Talmar's five (the Nephelo, the Osso, the Tarantula, the Sugarglider and the Rapa), the Vessari's four
  -- (the Kanau, the Hoshizora, the Raiden and the Akaboshi), the Orun's six (the Skiver, the Kama, the
  -- Falchion, the Excalibur, the Guthook and the Longhorn), the Kethri's two (the Noxious and the Deluge), the
  -- Nimia's one (the Hano), the Vail's two (the Aberration and the Interstition) and the Drowned's two (the
  -- Rebirth and the Resurrection).
  t.eq(improved, 22)
  t.ok(Ships.Improved("frigate.courier") == nil and Ships.Improved("industrial.hauler") == nil and Ships.Improved("capsule") == nil)
end)

suite:Case("what each tech 2 hull is for is the owner's word: to jump, to go unseen, to explore, or nothing beside being tech 2", function(t)
  -- (hull, jump drive, built to go unseen, a cloak of its own, built for exploration)
  local FOR: { { any } } = {
    { "industrial.tarantula", nil, true, nil, nil }, { "freighter.sugarglider", true, nil, nil, nil },
    { "capitalindustrial.rapa", true, nil, nil, nil },
    { "destroyer.kanau", nil, nil, nil, nil }, { "industrial.akaboshi", nil, true, nil, nil },
    { "frigate.skiver", nil, true, true, nil }, { "destroyer.kama", nil, nil, nil, nil },
    { "cruiser.falchion", nil, nil, nil, true }, { "industrial.longhorn", nil, true, nil, nil },
    -- (and the Nimia's one, "blackops" on the owner's list of their ships)
    { "cruiser.hano", nil, true, nil, nil },
    -- (and the Vail's two, by the owner's list of their ships: "t2 destroyer", of which the owner said
    -- "plain t2 package"; and "t2 cruiser (black ops)")
    { "destroyer.aberration", nil, nil, nil, nil }, { "cruiser.interstition", nil, true, nil, nil },
    -- (and the Drowned's two: each "no builtin cloak. can fit jumpdrive")
    { "cruiser.rebirth", true, nil, nil, nil }, { "freighter.resurrection", true, nil, nil, nil },
    -- (and the owner's of 2026-11-17: the Talmar's "t2 frigate (black ops)" and "t2 destroyer (interdictor)";
    -- the Vessari's "t2 cruiser (ewar)" and "t2 cruiser (special, bow railgun)"; the Orun's "t2 carrier" and
    -- "t2 siege dreadnought (8x guns)"; the Kethri's "t2 destroyer (interdictor)" and "t2 battlecruiser
    -- (black ops)". The interdictors and the electronic warfare hull are seen to below.)
    { "frigate.nephelo", nil, true, nil, nil }, { "destroyer.osso", nil, nil, nil, nil },
    { "cruiser.hoshizora", nil, nil, nil, nil }, { "cruiser.raiden", nil, nil, nil, nil },
    { "carrier.excalibur", nil, nil, nil, nil }, { "siegedreadnought.guthook", nil, nil, nil, nil },
    { "destroyer.noxious", nil, nil, nil, nil }, { "battlecruiser.deluge", nil, true, nil, nil },
  }
  local said: { [string]: boolean } = {}
  for _, entry in FOR do
    local hull = assert(Ships.byId[entry[1]], `no {entry[1]}`)
    said[hull.id] = true
    t.eq({ hull.tech, hull.jump, hull.stealth, hull.cloak, hull.explorer } :: { any }, { 2, entry[2], entry[3], entry[4], entry[5] } :: { any }, hull.id)
    -- What it is for is on its sheet, where it is for anything.
    local sheet = assert(Facts.Of(hull.id))
    local built: { [string]: boolean } = {}
    for _, section in sheet.sections do
      if section.title == "Built with" then
        for _, row in section.rows do
          built[row.label] = true
        end
      end
    end
    t.eq({ built["Jump drive"], built["Stealth"], built["Cloak"], built["Scanner"] } :: { any }, { entry[2], entry[3], entry[4], entry[5] } :: { any }, hull.id)
    -- (a hull built to go unseen or to explore fits a cloaking device cheaply, and says so)
    t.eq(built["Cloaking device"], if entry[3] or entry[5] then true else nil, hull.id)
    t.eq(string.find(sheet.kind, "black ops", 1, true) ~= nil, entry[3] == true, sheet.kind)
    t.eq(string.find(sheet.kind, "exploration", 1, true) ~= nil, entry[5] == true, sheet.kind)
    -- (a hull that is to cloak with a device has the room for one, and one that explores for its analyzer too)
    if entry[3] and not entry[4] then
      t.eq({ Attributes.Check(hull, { "cloak.device" }) } :: { any }, { true } :: { any }, hull.id)
    elseif entry[5] then
      t.eq({ Attributes.Check(hull, { "cloak.device", "analyzer.data" }) } :: { any }, { true } :: { any }, hull.id)
    end
  end
  -- Those are all the tech 2 hulls there are, and no plain hull is built for any of it but to jump.
  for _, hull in Ships.list do
    if hull.tech == 2 then
      t.ok(said[hull.id], `{hull.id} is a tech 2 hull nobody has said the purpose of`)
    else
      -- (but a plain hull of the Drowned's, every one of which has a cloak of its own)
      local built = Factions.byId[hull.lineage]
      t.eq({ hull.stealth, hull.cloak, hull.explorer } :: { any }, { nil, if built and built.cloaks then true else nil, nil } :: { any },
        hull.id)
    end
  end
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
      -- (a freighter is as much metal as a battleship, and of the same kinds; so is a capital, and a
      -- battlecruiser of either kind is built of what a cruiser is)
      local great = hull.class == "battleship" or hull.class == "freighter" or Ships.Capital(hull.class)
      t.eq(takes("mineral.cobalt"), hull.class == "cruiser" or hull.class == "barge" or hull.class == "attackbattlecruiser"
        or hull.class == "battlecruiser" or great, hull.id)
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
  local dray, mule, bastion = Ships.byId["freighter.dray"], Ships.byId["industrial.hauler"], Ships.byId["battleship.owari"]
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
  -- Bought and built like any hull, by a pilot with the skill for it, which is at the far end of the
  -- haulers'; a carrier's size and about its price (the owner, 2026-11-16: "Normally freighters should
  -- be carrier-sized and roughly the same cost").
  local info = Types.Info(dray.id)
  t.eq({ info.category, info.scarce } :: { any }, { "ship", nil } :: { any })
  local carrier = Ships.byId["carrier.katana"]
  t.ok(dray.basePrice > bastion.basePrice and dray.basePrice <= carrier.basePrice)
  t.eq(dray.radius, carrier.radius)
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
  -- (and a fighter's cannon and a bomber's rack, which only they carry)
  t.eq(weapons, 6 * 4 + 2 * 4 + 2, "six forms of turret and two of launcher, in four sizes, and what a fighter and a bomber carry")
  for _, form in { "laser.pulse", "laser.beam", "autocannon", "artillery", "blaster", "railgun" } do
    local small, medium, large = Modules.byId[form .. ".small"], Modules.byId[form .. ".medium"], Modules.byId[form .. ".large"]
    -- (and the fourth size, which only a siege dreadnought has the powergrid for)
    local xl = Modules.byId[form .. ".xl"]
    t.eq({ assert(xl.weapon).size, xl.powergrid > 23000 } :: { any }, { 4, true } :: { any }, xl.id)
    for _, pair in { { small, medium }, { medium, large }, { large, xl } } do
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
      local greatest = assert(Modules.chargeById[charge.id .. ".xl"])
      t.eq(bigger.size, 2)
      t.eq(largest.size, 3)
      t.eq(greatest.size, 4)
      for index, amount in charge.damage do
        t.ok(bigger.damage[index] >= amount and largest.damage[index] >= bigger.damage[index]
          and greatest.damage[index] >= largest.damage[index], bigger.id)
      end
      t.ok(Blueprints.byProduct[bigger.id] ~= nil and Blueprints.byProduct[largest.id] ~= nil and Blueprints.byProduct[greatest.id] ~= nil)
    end
  end
  for _, size in { "light", "heavy", "cruise", "siege" } do
    for _, kind in { "em", "thermal", "kinetic", "explosive" } do
      t.ok(Modules.chargeById[`missile.{size}.{kind}`] ~= nil, `no {kind} {size} missile`)
    end
  end
end)

suite:Case("every human warship can carry a full rack of its own faction's weapons, at its own size", function(t)
  local SHORT = { laser = "laser.pulse", projectile = "autocannon", hybrid = "blaster" }
  -- (by the owner's ladder: an attack battlecruiser carries a battleship's guns, a battlecruiser a cruiser's,
  -- and a siege dreadnought the largest there are)
  local SIZE = { frigate = 1, destroyer = 1, cruiser = 2, battleship = 3, attackbattlecruiser = 3, battlecruiser = 2, siegedreadnought = 4 }
  local NAME = { "small", "medium", "large", "xl" }
  local LAUNCHER = { "launcher.light", "launcher.heavy", "launcher.cruise", "launcher.siege" }
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
          if size < 4 then
            local bigger = assert(Modules.byId[`{SHORT[faction.weapon]}.{NAME[size + 1]}`])
            local biggerLauncher = assert(Modules.byId[LAUNCHER[size + 1]])
            local cpuUp = turrets * bigger.cpu + launchers * biggerLauncher.cpu
            local powergridUp = turrets * bigger.powergrid + launchers * biggerLauncher.powergrid
            t.ok(cpuUp > hull.cpu or powergridUp > hull.powergrid, `{hull.id} could carry its rack a size up`)
          end
        end
        -- A dreadnought is ten of a battleship's and ten of a cruiser's, on twenty hardpoints: it has the
        -- fitting for that, in its faction's guns of the long reach too, and not for one of the largest.
        if hull.lineage == faction.id and hull.class == "dreadnought" then
          local LONG = { laser = "laser.beam", projectile = "artillery", hybrid = "railgun" }
          for _, form in { SHORT[faction.weapon], LONG[faction.weapon] } do
            local cpu, powergrid = 0, 0
            for index = 1, 20 do
              local at = if index % 2 == 1 then 3 else 2
              local module = assert(Modules.byId[if index <= hull.launchers then LAUNCHER[at] else `{form}.{NAME[at]}`])
              cpu += module.cpu
              powergrid += module.powergrid
            end
            t.ok(cpu <= hull.cpu and powergrid <= hull.powergrid,
              `{hull.id}: ten large and ten medium ({form}) take {cpu} of {hull.cpu} cpu and {powergrid} of {hull.powergrid} MW`)
          end
          for _, module in Modules.list do
            -- (but for what only a bomber carries, which is nothing a ship fits)
            t.ok(module.weapon == nil or module.weapon.size < 4 or module.internal or module.powergrid > hull.powergrid,
              `{hull.id} could carry a {module.id}`)
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
  local composites = 0
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
      -- (by the owner's ruling only the large tech 2 modules call for it: the small and the medium do not)
      local large = string.find(module.id, ".large", 1, true) ~= nil
        or (string.find(module.id, ".medium", 1, true) == nil and module.weapon ~= nil and module.weapon.size >= 3)
      t.eq(moon, if module.tech == 2 and large then 1 else 0, `{module.id} and what is made of what is drilled out of moons`)
      composites += moon
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
  t.ok(composites > 0, "some large tech 2 module should call for a composite")
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
      -- (nor a people's own make, on anybody else's market: the Nimia's mending gear)
      t.eq({ module.base, Types.Info(module.id).scarce } :: { any },
        { nil, if module.internal or module.lineage then true else nil } :: { any })
      -- (and has a tech 2 make, for a tech 2 drone, and no custom one)
      t.ok(not module.internal or (Modules.Improved(module.id) ~= nil and Modules.Custom(module.id) == nil), module.id)
    end
  end
  -- 32 weapons, 2 repairers, an extender and a plate in three sizes each, two mining lasers and a gas harvester,
  -- the repairers for another ship (shield and armour, in three sizes), and the four things only a drone, a
  -- fighter or a bomber carries; and since 2026-11-16 the ancillary shield boosters and armour repairers,
  -- three sizes each, the two modulated lasers and the two ice harvesters.
  t.eq(improved, 32 + 4 * 3 + 3 + 2 * 3 + 4 + 2 * 3 + 2 + 2)
  t.ok(Modules.Improved("projector.entanglement") == nil and Modules.Improved("rig.shield") == nil)
  t.eq({ Modules.SizeOf(Modules.byId["autocannon.medium.ii"]), Modules.SizeOf(Modules.byId["shield.extender.large"]),
    Modules.SizeOf(Modules.byId["miner.small"]) }, { 2, 3, 1 })
end)

suite:Case("the same modules have a custom make, between the plain one and tech 2, and a masterwork past it: easier to fit, and only ever found", function(t)
  local customs, masterworks = 0, 0
  for _, module in Modules.list do
    -- (a people's own make is meta 3, and has a spec of its own: Data/Makes.spec)
    if module.meta and module.meta <= 2 then
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
  t.eq({ customs, masterworks }, { 32 + 4 * 3 + 3 + 2 * 3 + 2 * 3 + 4, 32 + 4 * 3 + 3 + 2 * 3 + 2 * 3 + 4 })
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
    elseif drone.craft then
      -- (a fighter and a bomber have no tech 2 make: their own case)
      t.eq({ drone.base, Drones.Improved(drone.id) } :: { any }, { nil, nil } :: { any })
    else
      t.eq({ drone.base, drone.level, Types.Info(drone.id).scarce } :: { any }, { nil, 1, nil } :: { any })
    end
  end
  t.eq(improved, 4)
end)

suite:Case("a fighter and a bomber are craft a carrier launches: bigger, tougher and harder-hitting than a drone, with a bay only on the hulls for them", function(t)
  local fighter, bomber, drone = Drones.byId["drone.fighter"], Drones.byId["drone.bomber"], Drones.byId["drone.medium"]
  t.eq({ fighter.craft, fighter.skill, fighter.level, bomber.craft, bomber.skill, bomber.level } :: { any },
    { "fighter", "fighters", 1, "bomber", "fighters", 3 } :: { any })
  for _, craft in { fighter, bomber } do
    local hull, gun = Ships.byId[craft.hull], Modules.byId[craft.gun]
    t.eq({ hull.class, hull.restricted, Types.Get(hull.id), gun.internal } :: { any }, { "drone", true, nil, true } :: { any }, craft.id)
    t.ok(Attributes.Check(hull, { gun.id }), `{gun.id} does not fit {hull.id}`)
    -- (what it is loaded with is of the size its weapon takes)
    t.eq(assert(Modules.chargeById[craft.charge]).size, assert(gun.weapon).size, craft.id)
    local plain = Ships.byId[drone.hull]
    t.ok(hull.shield + hull.armor + hull.hull > 3 * (plain.shield + plain.armor + plain.hull) and craft.volume > 10 * drone.volume, craft.id)
    -- A thing to buy and to build, as a drone is.
    t.eq({ Types.Info(craft.id).category, Blueprints.byProduct[craft.id] ~= nil } :: { any }, { "drone", true } :: { any }, craft.id)
  end
  -- A fighter's gun does several medium drones' work; a bomber's missile is the heaviest there is.
  local cannon, light = assert(Modules.byId["fighter.cannon"].weapon), assert(Modules.byId[drone.gun].weapon)
  t.ok(cannon.damageMultiplier / cannon.duration > 3 * light.damageMultiplier / light.duration and cannon.tracking > light.tracking)
  t.eq(assert(Modules.byId["bomber.rack"].weapon).size, 4)
  -- The bays: a carrier's is for fighters, a supercarrier's and an ultracapital's for bombers too, and nothing else has one.
  for _, hull in Ships.list do
    local bay = Ships.CRAFT[hull.class]
    t.eq(bay ~= nil, hull.class == "carrier" or hull.class == "supercarrier" or hull.class == "ultracapital", hull.id)
    if bay then
      t.eq({ bay.fighter, bay.bomber } :: { any }, { true, if hull.class == "carrier" then nil else true } :: { any }, hull.id)
      -- (and room in it for more of them than it has out at once)
      t.ok(assert(hull.bay) >= assert(hull.drones) * fighter.volume, `{hull.id} has not the bay for the fighters it controls`)
    end
  end
  t.ok(Skills.byId.fighters ~= nil)
end)

suite:Case("fittings come in three sizes, each for a larger ship than the last", function(t)
  for _, family in { "shield.extender", "shield.booster", "armor.plate", "armor.repairer", "afterburner", "capacitor.battery" } do
    local medium = assert(Modules.byId[family .. ".medium"])
    local large = assert(Modules.byId[family .. ".large"])
    t.ok(large.powergrid > 5 * medium.powergrid and large.basePrice > medium.basePrice, family)
    t.ok(string.find(medium.name, "Medium") ~= nil and string.find(large.name, "Large") ~= nil, medium.name)
    t.ok(#Skills.Needs(large.id) == 1 and Skills.byId[Skills.Needs(large.id)[1].skill] ~= nil, family)
    -- a cruiser can power a medium one and not a large; a battleship can power a large
    t.ok(medium.powergrid < 0.3 * Ships.byId["cruiser.ouyou"].powergrid, family)
    t.ok(large.powergrid > Ships.byId["cruiser.ouyou"].powergrid or family == "capacitor.battery" or family == "shield.extender"
      or family == "shield.booster", family)
    t.ok(large.powergrid < 0.3 * Ships.byId["battleship.owari"].powergrid, family)
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

suite:Case("every skill is in one of the owner's groups, and the groups are theirs", function(t)
  -- (2026-11-16: the groups put to them, with "Hulls -> Piloting. Flight -> Navigation" and "Combine weapons and gunnery")
  local names = {}
  for _, group in Skills.GROUPS do
    table.insert(names, group.name)
  end
  t.eq(names, { "Piloting", "Navigation", "Weapons", "Missiles", "Drones", "Shields", "Armour and Hull", "Ship Systems",
    "Targeting", "Electronic Warfare", "Exploration", "Mining", "Industry", "Trade", "Standing", "Structures", "Command", "Implants and Boosters" })
  for _, skill in Skills.list do
    t.ok(Skills.groupOf[skill.id] ~= nil, `{skill.name} is in no group`)
  end
end)

return suite
