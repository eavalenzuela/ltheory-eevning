--!strict
-- What there is to say about a type of item: its attributes, as labelled
-- values under headings, for an information window to show. One place
-- knows how every kind of thing is described; nothing here is drawn.
--
--   local sheet = Facts.Of("frigate.battleaxe")
--   sheet.name, sheet.kind, sheet.note
--   for _, section in sheet.sections do ... section.title, section.rows

local Blueprints = require("@lt/Core/Data/Blueprints")
local Boosters = require("@lt/Core/Data/Boosters")
local Components = require("@lt/Core/Data/Components")
local Drones = require("@lt/Core/Data/Drones")
local Implants = require("@lt/Core/Data/Implants")
local Injectors = require("@lt/Core/Data/Injectors")
local Factions = require("@lt/Core/Data/Factions")
local Modules = require("@lt/Core/Data/Modules")
local Ores = require("@lt/Core/Data/Ores")
local Paints = require("@lt/Core/Data/Paints")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")
local Moons = require("@lt/Core/Data/Moons")
local Planets = require("@lt/Core/Data/Planets")
local Reactions = require("@lt/Core/Data/Reactions")
local Structures = require("@lt/Core/Data/Structures")
local Types = require("@lt/Core/Data/Types")

local Facts = {}

-- (a row about another type of item gives its id as 'link', so that a
-- window can open that one's sheet from it)
export type Row = { label: string, value: string, link: string? }
export type Section = { title: string, rows: { Row } }
export type Sheet = {
  id: string,
  name: string,
  kind: string,           -- what sort of thing it is, in a few words ("Vessari frigate", "Small turret")
  note: string,           -- a sentence about it, or ""
  sections: { Section },
}

-- ---------------------------------------------------------------------
-- Numbers as text

-- 1,250,000
local function whole(n: number): string
  local text = string.format("%d", math.floor(math.abs(n) + 0.5))
  local grouped = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
  if string.sub(grouped, 1, 1) == "," then
    grouped = string.sub(grouped, 2)
  end
  return if n < 0 then "-" .. grouped else grouped
end

-- 12, 3.5, 0.25: no more decimals than the number needs, two at most.
local function plain(n: number): string
  if math.abs(n) >= 1000 then
    return whole(n)
  end
  local text = string.format("%.2f", n)
  text = string.gsub(text, "0+$", "")
  text = string.gsub(text, "%.$", "")
  return text
end

local function metres(n: number): string
  return if n >= 1000 then `{plain(n / 1000)} km` else `{plain(n)} m`
end

local function seconds(n: number): string
  if n >= 3600 then
    return `{plain(n / 3600)} h`
  elseif n >= 120 then
    return `{plain(n / 60)} min`
  end
  return `{plain(n)} s`
end

-- A multiplier as a change: 1.25 is "+25%", 0.9 is "-10%".
local function percent(multiplier: number): string
  local change = (multiplier - 1) * 100
  return `{if change >= 0 then "+" else ""}{plain(change)}%`
end

local DAMAGE = { "EM", "thermal", "kinetic", "explosive" }
local SIZES = { "Small", "Medium", "Large", "XL" }

-- 12 EM, 8 kinetic
local function damage(amounts: { number }, multiplier: number): string
  local parts: { string } = {}
  for index, amount in amounts do
    if amount > 0 then
      table.insert(parts, `{plain(amount * multiplier)} {DAMAGE[index]}`)
    end
  end
  return if #parts > 0 then table.concat(parts, ", ") else "none"
end

-- What a layer lets through of each kind of damage, as what it stops:
-- 0% / 20% / 40% / 50%
local function resists(resonance: { number }): string
  local parts: { string } = {}
  for _, r in resonance do
    table.insert(parts, `{plain((1 - r) * 100)}%`)
  end
  return table.concat(parts, " / ")
end

-- "maxVelocity" as "max velocity".
-- (what a hull that mends by itself gets back each second: said as it is)
local WORDED: { [string]: string } = { armorMend = "armour's mending", hullMend = "hull's mending" }
local function words(attribute: string): string
  if WORDED[attribute] then
    return WORDED[attribute]
  end
  local spaced = string.gsub(attribute, "(%u)", " %1")
  return string.lower(spaced)
end

local function nameOf(type: string): string
  local info = Types.Get(type)
  return if info then info.name else type
end

-- ---------------------------------------------------------------------
-- Pieces of a sheet

local function section(sheet: Sheet, title: string): Section
  local made: Section = { title = title, rows = {} }
  table.insert(sheet.sections, made)
  return made
end

local function row(to: Section, label: string, value: string, link: string?)
  table.insert(to.rows, { label = label, value = value, link = if link and Types.Get(link) then link else nil })
end

-- What a modifier does, as a row.
local function modifier(to: Section, m: Modules.Modifier, perLevel: boolean)
  local what = if m.on == "weapons" then `{m.family or "all"} weapons: {words(m.attribute)}` else words(m.attribute)
  local value: string
  if perLevel then
    value = `{if m.value >= 0 then "+" else ""}{plain(m.value * 100)}% a level`
  elseif m.op == "mul" then
    value = percent(m.value)
  else
    value = `{if m.value >= 0 then "+" else ""}{plain(m.value)}`
  end
  row(to, string.upper(string.sub(what, 1, 1)) .. string.sub(what, 2), value)
end

-- The skills a pilot needs for it, if any.
local function needs(sheet: Sheet, type: string)
  local list = Skills.Needs(type)
  if #list > 0 then
    local to = section(sheet, "Requires")
    for _, need in list do
      row(to, Skills.byId[need.skill].name, `level {need.level}`, Skills.Book(need.skill))
    end
  end
end

-- What it costs, how much room it takes, and what it is built from.
local function trade(sheet: Sheet, type: string)
  local info = Types.Get(type)
  local to = section(sheet, "Trade")
  if info then
    row(to, "Base price", `{whole(info.basePrice)} cr`)
    row(to, "Volume", `{plain(info.volume)} m3`)
  end
  local blueprint = Blueprints.byId["blueprint." .. type]
  if blueprint then
    local built = section(sheet, `Built from (makes {blueprint.perRun}, {seconds(blueprint.seconds)})`)
    for _, material in blueprint.materials do
      row(built, nameOf(material.type), whole(material.quantity), material.type)
    end
  end
end

-- How many blueprints call for it.
local function usedIn(type: string): number
  local count = 0
  for _, blueprint in Blueprints.list do
    for _, material in blueprint.materials do
      if material.type == type then
        count += 1
        break
      end
    end
  end
  return count
end

-- ---------------------------------------------------------------------
-- Each kind of thing

local function hullSheet(sheet: Sheet, hull: Ships.ShipType)
  local faction = Factions.byId[hull.lineage]
  local called = Ships.CLASS_NAMES[hull.class]
  local class = if called then called[1] else string.upper(string.sub(hull.class, 1, 1)) .. string.sub(hull.class, 2)
  -- (a hauler built to be shot at is called what it is)
  -- (and so is one built to go unseen, and one built to explore)
  local what = if hull.role == "combat" then "combat hauler"
    elseif hull.role == "transport" then "logistics capital"
    elseif hull.stealth then `black ops {string.lower(class)}`
    elseif hull.explorer then `exploration {string.lower(class)}`
    elseif hull.interdictor then "interdictor"
    elseif hull.ewar then `electronic warfare {string.lower(class)}`
    else string.lower(class)
  sheet.kind = if faction then `{faction.name} {if hull.tech == 2 then "tech 2 " else ""}{what}` else class
  sheet.note = if hull.donor then `Made over from the {nameOf(hull.donor)}.`
    elseif hull.tech == 2 and hull.base then
      `The tech 2 make of the {nameOf(hull.base)}: rebuilt to take more and fit more. Nobody sells one. Its blueprint is invented from the plain hull's, and it is built of the plain hull.`
    elseif faction then faction.note
    else ""
  -- What it is built with that others of its class are not: a jump
  -- drive (Tactical/Jumping), to go unseen or a cloak of its own
  -- (Tactical/Combat), or to explore (Ships.EXPLORER).
  if hull.jump or hull.stealth or hull.cloak or hull.explorer or hull.affinity or hull.spinal or hull.refinery or hull.interdictor
    or hull.ewar then
    local built = section(sheet, "Built with")
    -- (the kind of damage its faction's ships lean to: Data/Ships' affinity)
    if hull.affinity then
      local kind = ({ "EM", "thermal", "kinetic", "explosive" })[hull.affinity]
      row(built, "Affinity", `{kind}: its weapons do {whole(Ships.AFFINITY * 100)}% more {kind} damage, and it lets {whole(Ships.AFFINITY * 100)}% less of it through`)
    end
    if hull.jump then
      row(built, "Jump drive", "reaches 20 light years without a gate, to a beacon, on fuel blocks")
    end
    if hull.jump and hull.jumpField then
      row(built, "Jump field", `takes with it every friendly ship within {whole(hull.jumpField / 1000)} km that is not in warp or scrambled`)
    end
    if hull.refinery then
      row(built, "Refinery", "aboard: ore in its hold or its ore hold is refined where it lies, in space or docked")
    end
    if hull.spinal then
      local gun = hull.spinal
      row(built, gun.name, `fixed along the bow: the ship is aligned to its target to fire it. {whole(gun.damage[1] + gun.damage[2] + gun.damage[3] + gun.damage[4])} a round, every {whole(gun.duration)} s, for {whole(gun.capacitor)} GJ`)
    end
    if hull.cloak then
      row(built, "Cloak", "its own, built in: nothing to fit and no slot, and it draws on the capacitor while it is on")
    end
    if hull.stealth then
      row(built, "Stealth", "a cloak does not slow it, and is broken only from half as far")
    end
    if hull.stealth or hull.explorer then
      row(built, "Cloaking device", `fits for {whole(Ships.CLOAK_FITTING * 100)}% of the CPU and powergrid it asks of another hull`)
    end
    if hull.interdictor then
      local wide = Ships.INTERDICTOR
      row(built, "Interdiction", `an interdiction field it drops is {whole((wide.radius - 1) * 100)}% wider and lasts {whole((wide.lasts - 1) * 100)}% longer`)
    end
    if hull.ewar then
      local more = Ships.EWAR
      row(built, "Electronic warfare", `its webs, disruptors, painters, dampeners, jammers and neutralisers reach {whole((more.range - 1) * 100)}% farther and work {whole((more.strength - 1) * 100)}% more strongly`)
    end
    if hull.explorer then
      local has = Ships.EXPLORER
      row(built, "Scanner", `every scan of a signal is worth {whole((has.scan - 1) * 100)}% more`)
      row(built, "Hacking", `{has.hack} more codes in the buffer`)
    end
  end
  -- (and what it launches, if it has a bay for more than drones)
  if hull.class == "carrier" or hull.class == "supercarrier" or hull.class == "ultracapital" then
    row(section(sheet, "Launches"), "From its bay", if hull.class == "carrier" then "drones and fighters" else "drones, fighters and bombers")
  end

  local defence = section(sheet, "Defence")
  -- (a hull of the Nimia's has no shield, and mends: Tactical/Combat)
  local shielded = hull.shield > 0 or hull.class == "capsule"
  row(defence, "Shield", if shielded then `{whole(hull.shield)} HP` else "none: it carries no shield, and takes no shield module")
  row(defence, "Armour", `{whole(hull.armor)} HP`)
  row(defence, "Hull", `{whole(hull.hull)} HP`)
  local armorMend, hullMend = hull.armorMend or 0, hull.hullMend or 0
  if armorMend > 0 or hullMend > 0 then
    row(defence, "Mends by itself", `armour {plain(armorMend * 100)}% a second ({seconds(1 / armorMend)} from nothing), hull {plain(hullMend * 100)}% ({seconds(1 / hullMend)})`)
  end
  if shielded then
    row(defence, "Shield resists (EM / th / kin / exp)", resists(hull.shieldResonance))
  end
  row(defence, "Armour resists", resists(hull.armorResonance))
  row(defence, "Signature", metres(hull.signature))

  local fitting = section(sheet, "Fitting")
  row(fitting, "Slots (high / mid / low)", `{hull.highs} / {hull.mids} / {hull.lows}`)
  row(fitting, "Hardpoints (turret / launcher)", `{hull.turrets} / {hull.launchers}`)
  row(fitting, "CPU", `{plain(hull.cpu)} tf`)
  row(fitting, "Powergrid", `{plain(hull.powergrid)} MW`)
  row(fitting, "Capacitor", `{plain(hull.capacitor)} GJ, {seconds(hull.capacitorRecharge)} to recharge`)

  local movement = section(sheet, "Movement")
  row(movement, "Top speed", `{plain(hull.maxVelocity)} m/s`)
  -- (three quarters of top speed, which is what a warp needs, takes 1.386 time constants)
  row(movement, "Time to align", seconds(Ships.TimeConstant(hull) * 1.386))
  row(movement, "Warp speed", `{plain(hull.warpSpeed)} AU/s`)
  row(movement, "Mass", `{whole(hull.mass / 1000)} t`)

  local targeting = section(sheet, "Targeting")
  row(targeting, "Lock range", metres(hull.lockRange))
  row(targeting, "Scan resolution", `{plain(hull.scanResolution)} mm`)
  row(targeting, "Targets", tostring(hull.maxTargets))

  local hold = section(sheet, "Hold")
  row(hold, "Cargo", `{plain(hull.cargo)} m3`)
  if (hull.shipbay or 0) > 0 then
    row(hold, "Ship bay", `{whole(hull.shipbay or 0)} m3, for packed hulls`)
  end

  needs(sheet, hull.id)
  if hull.restricted then
    local to = section(sheet, "Trade")
    row(to, "Worth", `{whole(hull.basePrice)} cr`)
    row(to, "Sold", "nowhere: nobody's to own")
  elseif hull.foreign then
    local to = section(sheet, "Trade")
    row(to, "Worth", `{whole(hull.basePrice)} cr`)
    row(to, "Sold", "by no human market: built from drawings that have to be found")
  elseif hull.class ~= "capsule" then
    trade(sheet, hull.id)
  end
end

local function moduleSheet(sheet: Sheet, module: Modules.ModuleType)
  local weapon, repair, miner = module.weapon, module.repair, module.miner
  local slot = string.upper(string.sub(module.slot, 1, 1)) .. string.sub(module.slot, 2) .. " slot"
  sheet.kind = if weapon then `{SIZES[weapon.size]} {if module.hardpoint == "launcher" then "launcher" else "turret"}`
    elseif module.hardpoint ~= "" then `{slot} {module.hardpoint}`
    else `{slot} module`
  -- (a make of another module: what it is the make of, and how it is come by)
  local cut = string.find(module.id, "~", 1, true)
  local people = if module.lineage then Factions.byId[module.lineage] else nil
  if module.mutated and cut then
    sheet.note = `The {nameOf(string.sub(module.id, 1, cut - 1))} as it came out of a mutator: what it gives, how it fits, what it draws and how far it reaches were each thrown again, once. It cannot go through another, and no market deals in one.`
    -- (how each figure came out: a quarter worse to three tenths better)
    local to = section(sheet, "Mutation")
    for index, label in { "What it gives", "Fitting", "Capacitor draw", "Reach" } do
      local roll = (module.rolls or {})[index] or 0
      row(to, label, if roll == 0 then "as it was" else `{whole(math.abs(roll))}% {if roll > 0 then "better" else "worse"}`)
    end
  elseif module.officer and module.base then
    sheet.note = `{module.officer}'s own {nameOf(module.base)}: better than a masterwork, easier to fit, and no harder to use than the plain one. It was in their wreck and nowhere else, and no market deals in one.`
  elseif module.site and module.base then
    sheet.note = `The {nameOf(module.base)} as the Unbound keep it for themselves, of the {Modules.SiteRank(module.site)} grade ({module.site} of 3): better than any people's make, short of an officer's, and no harder to use. Nobody sells or builds one. It is found in pirate dens' and strongholds' stores, in camp chiefs' wrecks, and with the commanders of pirate towers.`
  elseif module.meta == 3 and people and module.base and module.shaded then
    sheet.note = `The {people.name}' own make of the {nameOf(module.base)}: {Modules.Shade(people.id) or "better than the plain one"}, and no harder to use. Their stations sell it to anybody, and their agents now and then pay with one. Nobody has the drawings.`
  elseif module.meta == 3 and people and module.base then
    sheet.note = `The {people.name}' own make of the {nameOf(module.base)}: better than the plain one, and no harder to fit or to use. Their stations sell it to anybody, and their agents now and then pay a job with one.`
  elseif module.meta == 2 and module.base then
    sheet.note = `The {nameOf(module.base)} made over by the best hands the pirates have: better than any that is built to a drawing, easy to fit, and no harder to use than the plain one. Nobody sells or builds one. Only a pirate captain fits them, and now and then one outlives the captain's ship.`
  elseif module.meta and module.base then
    sheet.note = `The {nameOf(module.base)} as somebody has worked it over: a little better, easier to fit, and no harder to use. Nobody sells or builds one. They are found in pirates' wrecks and in their stores.`
  elseif module.tech == 2 and module.base then
    sheet.note = `The tech 2 make of the {nameOf(module.base)}: better, and harder to fit and to use. Nobody sells one. Its blueprint is invented from the plain one's.`
  end

  if weapon then
    local to = section(sheet, "Weapon")
    row(to, "Damage", `x{plain(weapon.damageMultiplier)} of its charge's`)
    row(to, "Fires every", seconds(weapon.duration))
    if weapon.optimal > 0 then
      row(to, "Optimal range", metres(weapon.optimal))
      row(to, "Falloff", metres(weapon.falloff))
      row(to, "Tracking", plain(weapon.tracking))
    elseif (weapon.flight or 1) ~= 1 then
      row(to, "Range", `{whole((weapon.flight or 1) * 100)}% of its missile's`)
    else
      row(to, "Range", "its missile's")
    end
    if weapon.capacitor > 0 then
      row(to, "Capacitor a shot", `{plain(weapon.capacitor)} GJ`)
    end
    row(to, "Takes", `{string.lower(SIZES[weapon.size])} {weapon.family} charges`)
    if weapon.clip > 0 then
      row(to, "Clip", `{weapon.clip} shots, {seconds(weapon.reload)} to reload`)
    end
  end
  if repair then
    local to = section(sheet, "Repair")
    row(to, if repair.layer == "shield" then "Shield restored" else "Armour repaired", `{plain(repair.amount)} HP every {seconds(repair.duration)}`)
    row(to, "Capacitor a cycle", `{plain(repair.capacitor)} GJ`)
    -- (an ancillary one: what a charge does for it)
    local ancillary, takes = module.ancillary, module.takes
    if ancillary and takes then
      row(to, "Loaded", if ancillary.factor > 1 then `{plain(ancillary.factor)} times as much a cycle, a charge a cycle`
        else "draws no capacitor, a charge a cycle")
      row(to, "Takes", `{if takes.family == "paste" then "repair paste" else "capacitor charges"}, {takes.clip} at a time, {seconds(takes.reload)} to reload`)
    end
  end
  -- A capacitor booster: what it is loaded with, and how often it gives it.
  if module.injector and module.takes then
    local to = section(sheet, "Capacitor booster")
    row(to, "Puts in", `a charge's worth every {seconds(module.injector.duration)}`)
    row(to, "Takes", `{string.lower(SIZES[module.takes.size] or "")} capacitor charges, {module.takes.clip} at a time, {seconds(module.takes.reload)} to reload`)
  end
  -- An adaptive hardener: how much it holds, and how it shifts.
  if module.adaptive then
    local to = section(sheet, "Adaptive hardener")
    row(to, "Armour resistance", `{plain(module.adaptive.total * 100)}% in all, evenly at first`)
    row(to, "Each cycle", `{plain(module.adaptive.step * 100)}% moves to the kind of damage taken most`)
  end
  if module.slot == "rig" then
    local to = section(sheet, "Rig")
    row(to, "Calibration", `{plain(module.calibration or 0)} of a hull's 400`)
    row(to, "Goes into", ({ "a frigate or a destroyer", "a cruiser, a hauler or a barge", "a battleship" })[Modules.SizeOf(module)])
    row(to, "Taken out", "it is destroyed")
  end
  if module.salvager then
    local salvager = module.salvager
    local to = section(sheet, "Salvaging")
    row(to, "Chance a cycle", `{plain(salvager.chance * 100)}%, and 10% more a level of Salvaging`)
    row(to, "Range", metres(salvager.range))
    row(to, "Capacitor a cycle", `{plain(salvager.capacitor)} GJ every {seconds(salvager.duration)}`)
  end
  if module.analyzer then
    local to = section(sheet, "Hacking")
    row(to, "Opens", if module.analyzer.relic then "a derelict's sealed hold, by finding the keys of its lock"
      else "a listening post's vault, by finding the keys of its lock")
    row(to, "Range", metres(module.analyzer.range))
    row(to, "A level of Hacking", "one more code in the buffer")
  end
  -- (module expansion, 2026-11-16: the third group's)
  if module.jump then
    local to = section(sheet, "Micro jump drive")
    row(to, "Throws the ship", `{metres(module.jump.distance)} ahead, the way it is going`)
    row(to, "Spools up for", seconds(module.jump.spool))
    row(to, "Then", "every lock is broken; not while warp scrambled")
  end
  if module.stabilizer then
    local to = section(sheet, "Warp stability")
    row(to, "Against disruption", `{plain(module.stabilizer)} disruptor's worth`)
  end
  if module.tractor then
    local to = section(sheet, "Tractor beam")
    row(to, "Pulls a wreck", `{plain(module.tractor.speed)} m/s, to a kilometre off`)
    row(to, "Range", metres(module.tractor.range))
    row(to, "Capacitor a cycle", `{plain(module.tractor.capacitor)} GJ every {seconds(module.tractor.duration)}`)
  end
  if module.scanner then
    local scan = module.scanner
    local to = section(sheet, "Scanner")
    row(to, "Reads", if scan.kind == "ship" then "what a locked ship has fitted" elseif scan.kind == "cargo" then "what a locked ship has in its hold"
      else "what every rock in reach still holds")
    row(to, "Range", metres(scan.range))
    row(to, "Takes", `{seconds(scan.duration)} and {plain(scan.capacitor)} GJ`)
  end
  if module.mining then
    local to = section(sheet, "Mining upgrade")
    row(to, "Ore off a rock", `{plain(module.mining * 100)}% of what it was, with every laser`)
  end
  -- (module expansion, 2026-11-16: the fourth group's)
  if module.burst then
    local to = section(sheet, "Command burst")
    row(to, "Reaches", `every ship of its owner's within {metres(module.burst.range)}, its own too; twice as far from a running industrial core`)
    if module.burst.mining then
      row(to, "Ore off a rock", `{plain(module.burst.mining * 100)}% of what it was`)
    end
    row(to, "Of each kind", "only the strongest counts")
  end
  if module.classes then
    local names = {}
    for _, class in module.classes do
      table.insert(names, if Ships.CLASS_NAMES[class] then Ships.CLASS_NAMES[class][2] else class)
    end
    row(section(sheet, "Fitted to"), "Only", table.concat(names, " and "))
  end
  if module.immobile then
    local to = section(sheet, "While it runs")
    row(to, "The ship", "cannot move, warp, jump or dock")
    if module.triage then
      row(to, "Remote repair and capacitor sent", `{plain(module.triage)} times as much`)
    end
    if module.core then
      row(to, "Command bursts", "reach twice as far")
    end
  end
  if module.burns then
    row(section(sheet, "Burns"), "Each cycle", `{plain(module.burns.quantity)} {nameOf(module.burns.type)} from the hold`)
  end
  if module.bubble then
    local to = section(sheet, "Interdiction field")
    row(to, "Dropped", `where the ship is, {metres(module.bubble.radius)} wide`)
    row(to, "Lasts", seconds(module.bubble.lasts))
    row(to, "In it", "nobody but its owner's ships can warp, stabilizers or none")
  end
  if module.probes then
    local to = section(sheet, "Probes")
    row(to, "Puts out", "the scan probes in the hold, up to eight at once, each to a corner of a box round the ship")
    row(to, "Reads", `{whole(module.probes.strength * 100)}% of what a plain launcher's probes do`)
    row(to, "On a hull built to explore", `{whole(Ships.PROBE_FITTING * 100)}% of the CPU and powergrid`)
  end
  if module.takes and module.takes.family == "crystal" then
    row(section(sheet, "Crystals"), "Takes", "a mining crystal: far more of the crystal's ore, never used up")
  end
  if module.cloak then
    local to = section(sheet, "Cloak")
    row(to, "While it runs", "the ship cannot be targeted, and can target nothing")
    row(to, "Switched off by", `anything within {metres(module.cloak.reach)}`)
    row(to, "Cannot be switched on", "while anybody has the ship targeted")
  end
  if module.hex then
    local hex = module.hex
    local titles: { [string]: string } = { entangle = "Gravitic entanglement", scramble = "Warp disruption", paint = "Target painting",
      damp = "Sensor dampening", neut = "Energy neutralising", jam = "Jamming", shield = "Remote shield boosting",
      armor = "Remote armour repair", capacitor = "Capacitor relay", track = "Tracking disruption", guide = "Guidance disruption",
      nos = "Energy draining", sensor = "Remote sensor boosting" }
    local does: { [string]: string } = {
      entangle = `top speed cut to {plain(hex.strength * 100)}%`, scramble = "cannot warp",
      paint = `signature {plain(hex.strength * 100)}% of what it was`,
      damp = `lock range and scan resolution cut to {plain(hex.strength * 100)}%`,
      neut = `{plain(hex.strength)} GJ taken from its capacitor a cycle`,
      jam = `{plain(hex.strength * 100)}% chance a cycle of breaking its locks`,
      shield = `{plain(hex.strength)} shield put back a cycle`, armor = `{plain(hex.strength)} armour put back a cycle`,
      capacitor = `{plain(hex.strength)} GJ put into its capacitor a cycle`,
      track = `its turrets' tracking and range cut to {plain(hex.strength * 100)}%`,
      guide = `its missiles' flight cut to {plain(hex.strength * 100)}%, their blast that much wider`,
      nos = `up to {plain(hex.strength)} GJ a cycle taken into this ship's capacitor, while the target's is the fuller`,
      sensor = `lock range and scan resolution {plain(hex.strength * 100)}% of what they were`,
    }
    local to = section(sheet, titles[hex.kind])
    row(to, "On its target", does[hex.kind])
    row(to, "Range", metres(hex.range))
    row(to, "Capacitor a cycle", `{plain(hex.capacitor)} GJ every {seconds(hex.duration)}`)
  end
  -- (module expansion, 2026-11-16: what is done for the drones, and a smartbomb)
  if module.drones then
    local to = section(sheet, "Drones")
    if module.drones.damage then
      row(to, "Drone damage", `{plain(module.drones.damage * 100)}% of what it was`)
    end
    if module.drones.tracking then
      row(to, "Drone tracking and range", `{plain(module.drones.tracking * 100)}% of what they were`)
    end
  end
  if module.smartbomb then
    local bomb = module.smartbomb
    local to = section(sheet, "Smartbomb")
    row(to, "Damage", damage(bomb.damage, 1))
    row(to, "Strikes", `every ship and drone within {metres(bomb.range)} that is not its owner's`)
    row(to, "Capacitor a cycle", `{plain(bomb.capacitor)} GJ every {seconds(bomb.duration)}`)
  end
  if miner then
    local to = section(sheet, "Mining")
    row(to, "Ore a cycle", `{plain(miner.volume)} m3 every {seconds(miner.duration)}`)
    row(to, "Range", metres(miner.range))
    row(to, "Capacitor a cycle", `{plain(miner.capacitor)} GJ`)
  end
  if #module.passive > 0 then
    local to = section(sheet, "While fitted")
    for _, m in module.passive do
      modifier(to, m, false)
    end
  end
  if module.boost then
    local to = section(sheet, "While running")
    for _, m in module.boost do
      modifier(to, m, false)
    end
    if module.boostCapacitor then
      row(to, "Capacitor a cycle", `{plain(module.boostCapacitor)} GJ every {seconds(module.boostDuration or 0)}`)
    end
  end

  local fitting = section(sheet, "Fitting")
  -- (a cloaking device asks a share of the hull's own: Attributes.Needs)
  if module.cloak then
    row(fitting, "CPU", `{whole(module.cloak.cpu * 100)}% of the hull's own`)
  else
    row(fitting, "CPU", `{plain(module.cpu)} tf`)
  end
  row(fitting, "Powergrid", `{plain(module.powergrid)} MW`)
  if module.cloak then
    row(fitting, "On a hull built for it", `{whole(Ships.CLOAK_FITTING * 100)}% of both`)
  end
  needs(sheet, module.id)
  trade(sheet, module.id)
end

local function chargeSheet(sheet: Sheet, charge: Modules.ChargeType)
  sheet.kind = `{SIZES[charge.size] or "Small"} {charge.family} charge`
  if charge.tech == 2 and charge.base then
    -- (what it is better at than the plain one, and what worse)
    local plain = Modules.chargeById[charge.base]
    local how = if charge.family == "missile" then "it hits a quarter harder, and its blast is wider, so that small ships take less of it"
      elseif plain.rangeMultiplier < 0.8 then "it hits a quarter harder, and the gun tracks a quarter worse with it"
      elseif plain.rangeMultiplier > 1.3 then "it reaches a quarter further and hits a little harder, and the gun tracks a fifth worse with it"
      else "the gun tracks three tenths better with it and it hits a little harder, at a seventh less range"
    sheet.note = `The tech 2 make of {nameOf(charge.base)}: {how}. Only a tech 2 weapon takes it. Nobody sells it: its blueprint is invented from the plain one's.`
  end
  -- (a capacitor charge, and repair paste: what they do, not damage)
  if charge.family == "booster" then
    sheet.kind = `{SIZES[charge.size] or "Small"} capacitor charge`
    row(section(sheet, "Charge"), "Puts into the capacitor", `{plain(charge.injects or 0)} GJ, in a capacitor booster; or a cycle's capacitor, in an ancillary shield booster`)
    trade(sheet, charge.id)
    return
  elseif charge.family == "bubble" then
    sheet.kind = "Interdiction charge"
    row(section(sheet, "Charge"), "In an interdiction field launcher", "one field")
    trade(sheet, charge.id)
    return
  elseif charge.family == "crystal" then
    sheet.kind = "Mining crystal"
    row(section(sheet, "Charge"), "In a modulated laser", `{plain((charge.yieldBy or 1) * 100)}% as much {nameOf(charge.ore or "")} a cycle`)
    trade(sheet, charge.id)
    return
  elseif charge.family == "paste" then
    sheet.kind = "Repair paste"
    row(section(sheet, "Charge"), "In an ancillary armour repairer", "three times as much repaired a cycle, a unit a cycle")
    trade(sheet, charge.id)
    return
  end
  local to = section(sheet, "Charge")
  row(to, "Damage", damage(charge.damage, 1))
  if charge.family == "missile" then
    row(to, "Speed", `{plain(charge.velocity)} m/s`)
    row(to, "Flies for", seconds(charge.flightTime))
    row(to, "Range", metres(charge.velocity * charge.flightTime))
    row(to, "Explosion radius", metres(charge.explosionRadius))
    row(to, "Explosion velocity", `{plain(charge.explosionVelocity)} m/s`)
  else
    if charge.rangeMultiplier ~= 1 then
      row(to, "Optimal range", percent(charge.rangeMultiplier))
    end
    if charge.tracking then
      row(to, "Tracking", percent(charge.tracking))
    end
  end
  trade(sheet, charge.id)
end

-- ---------------------------------------------------------------------

-- Everything there is to say about a type, or nil if there is no such
-- type.
function Facts.Of(type: string): Sheet?
  local info = Types.Get(type)
  local hull = Ships.byId[type]
  if info == nil and hull == nil then
    return nil
  end
  local sheet: Sheet = { id = type, name = if info then info.name elseif hull then hull.name else type, kind = "", note = "", sections = {} }

  if hull then
    hullSheet(sheet, hull)
    return sheet
  end
  local module = Modules.byId[type]
  if module then
    moduleSheet(sheet, module)
    return sheet
  end
  local charge = Modules.chargeById[type]
  if charge then
    chargeSheet(sheet, charge)
    return sheet
  end
  local category = if info then info.category else ""

  if category == "ore" then
    local ore = Ores.byId[type]
    sheet.kind = if ore.ice then "Ice" else "Ore"
    sheet.note = if ore.ice then (if ore.share == 0 then "Found only in the ice fields of lawless space; cut with an ice harvester."
        else "Found in ice fields; cut with an ice harvester.")
      elseif ore.wild then "Found only in lawless space." else "Found in the asteroid belts."
    local to = section(sheet, if ore.ice then "Refines to (per block, at perfect yield)" else "Refines to (per 100 units, at perfect yield)")
    for _, yield in ore.yields do
      row(to, nameOf(yield.mineral), whole(yield.amount), yield.mineral)
    end
    trade(sheet, type)
  elseif category == "mineral" then
    sheet.kind = if Ores.mineralById[type] and string.sub(type, 1, 4) == "ice." then "Ice product" else "Mineral"
    local to = section(sheet, "Refined from")
    for _, ice in Ores.ices do
      for _, yield in ice.yields do
        if yield.mineral == type then
          row(to, ice.name, `{whole(yield.amount)} per block`, ice.id)
        end
      end
    end
    for _, ore in Ores.list do
      for _, yield in ore.yields do
        if yield.mineral == type then
          row(to, ore.name, `{whole(yield.amount)} per 100`, ore.id)
        end
      end
    end
    row(section(sheet, "Use"), "Called for by", `{usedIn(type)} blueprints`)
    trade(sheet, type)
  elseif category == "component" then
    local component = Components.byId[type]
    sheet.kind = "Component"
    sheet.note = "A part that modules and hulls are built from."
    row(section(sheet, "Use"), "Called for by", `{usedIn(type)} blueprints`)
    if component then
      trade(sheet, type)
    end
  elseif category == "blueprint" then
    local blueprint, copy = Blueprints.Of(type)
    assert(blueprint)
    sheet.kind = if copy then "Blueprint copy" else "Blueprint"
    if copy then
      sheet.note = "A copy of a blueprint, made in a laboratory from the blueprint itself. Each one is a run: a job built from a copy uses up the runs it is for, and an invention uses up one. What its owner has researched of the design counts for it. No market deals in copies."
    end
    local to = section(sheet, "Makes")
    row(to, nameOf(blueprint.product), `{blueprint.perRun} a run`, blueprint.product)
    row(to, "A run takes", seconds(blueprint.seconds))
    local materials = section(sheet, "Materials a run")
    for _, material in blueprint.materials do
      row(materials, nameOf(material.type), whole(material.quantity), material.type)
    end
    local market = section(sheet, "Trade")
    row(market, "Base price", if copy then `{whole(Types.Info(type).basePrice)} cr a run` else `{whole(blueprint.basePrice)} cr`)
  elseif category == "paint" then
    local paint, design = Paints.paintById[type], Paints.designById[type]
    if paint then
      sheet.kind = "Paint for a ship"
      sheet.note = paint.note .. " Made yours from its menu in the inventory, it is used up and the paint is yours for good: any ship you fly is painted in it, and in any other of yours, from the list on the fitting screen, as often as you like. It changes nothing but how the ship looks."
    elseif design then
      sheet.kind = "Design for a ship"
      sheet.note = design.note .. " Laid over a ship's paint, in the colour that paint has for designs: it needs a paint under it. Made yours from its menu in the inventory, it is used up and the design is yours for good, on the fitting screen's list."
    end
    trade(sheet, type)
  elseif category == "implant" then
    local implant = Implants.byId[type]
    sheet.kind = "Implant"
    sheet.note = "Plugged in at a station, it is part of the pilot and counts for every ship they fly. Taken out, it is destroyed; and a pilot whose capsule is destroyed loses every implant they had."
    local does = section(sheet, "Implant")
    row(does, "Does", implant.note)
    row(does, "Place", `{implant.slot} of {Implants.SLOTS}`)
    row(does, "To plug in", `Cybernetics {implant.slot}`)
    trade(sheet, type)
  elseif category == "drone" then
    local drone = Drones.byId[type]
    sheet.kind = "Drone"
    local gun = Modules.byId[drone.gun]
    local flies = Ships.byId[drone.hull]
    sheet.note = if drone.role == "mining" then "Launched from the drone bay to cut the rock its owner is working, or the one it is pointed at: when its little hold is full it flies back, puts the ore in its owner's hold and goes out again."
      elseif drone.role == "repair" then "Launched from the drone bay to mend whoever of its owner's side has lost most armour: it goes to them and sets to, and otherwise keeps station on its owner."
      else "Launched from the drone bay to fight beside the ship: it goes for what it is pointed at, or for whatever is attacking its owner's side."
    sheet.note ..= " Near enough when its owner warps or docks, it is taken aboard; left behind, it is lost."
    if drone.tech == 2 and drone.base then
      sheet.note ..= ` The tech 2 make of the {nameOf(drone.base)}: tougher and quicker, with the tech 2 make of what that carries. It takes Drones {drone.level} to have one out. Nobody sells one: its blueprint is invented from the plain drone's.`
    end
    local has = section(sheet, "Drone")
    if gun.miner then
      row(has, "Cuts", `{whole(gun.miner.volume)} m3 a minute, into a hold of {whole(flies.cargo)} m3`)
    elseif gun.hex then
      row(has, "Mends", `{whole(gun.hex.strength)} armour every {seconds(gun.hex.duration)}`)
    else
      row(has, "Armed with", gun.name, gun.id)
    end
    row(has, "Speed", `{whole(flies.maxVelocity)} m/s`)
    row(has, "Shield, armour, hull", `{whole(flies.shield)}, {whole(flies.armor)}, {whole(flies.hull)} HP`)
    row(has, "To launch", `Drones {flies.requires and flies.requires[1].level or 1}`)
    trade(sheet, type)
  elseif category == "planetary" then
    local raw, product = Planets.rawById[type], Planets.productById[type]
    if raw then
      sheet.kind = "Raw material"
      sheet.note = "Brought up out of a planet by a colony's extractors. Bulky and worth little until it is processed."
      local on = section(sheet, "Found on")
      for _, variety in { "temperate", "ocean", "barren", "lava", "ice", "gas" } do
        for _, has in Planets.DEPOSITS[variety] do
          if has == type then
            row(on, `{string.upper(string.sub(variety, 1, 1))}{string.sub(variety, 2)} planets`, "by extractor")
          end
        end
      end
      local made = Planets.productOf[type]
      if made then
        row(section(sheet, "Processed into"), made.name, `{whole(made.output)} from {whole(made.input)}`, made.id)
      end
    elseif product then
      sheet.kind = "Processed material"
      sheet.note = "Made on a planet by a colony's processors, and fetched from orbit."
      row(section(sheet, "Processed from"), nameOf(product.from), `{whole(product.input)} make {whole(product.output)}`, product.from)
      row(section(sheet, "Use"), "Called for by", `{usedIn(type)} blueprints`)
    end
    trade(sheet, type)
  elseif category == "moon" and Reactions.byId[type] then
    local composite = Reactions.byId[type]
    sheet.kind = "Composite"
    sheet.note = "Made in the reactor of a tower, of the two moon materials of its grade. What tech 2 hulls and the large tech 2 modules are built with."
    local made = section(sheet, "Reacted from")
    for _, from in composite.from do
      row(made, nameOf(from), `{whole(Reactions.BATCH)} an hour`, from)
    end
    row(made, "Makes", `{whole(Reactions.BATCH)} an hour`)
    row(section(sheet, "Use"), "Called for by", `{usedIn(type)} blueprints`)
    trade(sheet, type)
  elseif category == "moon" then
    local material = Moons.byId[type]
    sheet.kind = "Moon material"
    sheet.note = "Brought up out of a moon by the drill of a tower anchored there. "
      .. (if material.grade == 1 then "Found under moons anywhere."
        elseif material.grade == 2 then "Not found where order is kept."
        else "Found only where nobody keeps order.")
    local has = section(sheet, "Deposit")
    row(has, "Grade", if material.grade == 1 then "common" elseif material.grade == 2 then "uncommon" else "rare")
    row(has, "A drill brings up", `{whole(Moons.YIELD * Moons.POOREST)} to {whole(Moons.YIELD * Moons.RICHEST)} an hour`)
    local into = Reactions.Of(type)
    if into then
      row(section(sheet, "Use"), "A reactor makes of it", into.name, into.id)
    end
    trade(sheet, type)
  elseif category == "structure" and type == Planets.CENTRE.id then
    sheet.kind = "Command centre"
    sheet.note = "The start of a colony. Put down on a planet from orbit, it powers the extractors, processors and storage raised round it."
    local has = section(sheet, "Supplies")
    row(has, "Powergrid", `{whole(Planets.CENTRE.powergrid)} MW`)
    row(has, "CPU", `{whole(Planets.CENTRE.cpu)} tf`)
    row(has, "Room", `{whole(Planets.CENTRE.room)} m3`)
    local raise = section(sheet, "Facilities")
    for _, facility in Planets.facilities do
      row(raise, facility.name, `{whole(facility.powergrid)} MW, {whole(facility.cpu)} tf, {whole(facility.cost)} cr`)
    end
    trade(sheet, type)
  elseif category == "structure" then
    local tower, anchored = Structures.towerById[type], Structures.moduleById[type]
    if tower and tower.citadel then
      sheet.kind = "Citadel"
      sheet.note = "A station of your own that ships dock inside. Built at a station, hauled to a moon or planet and anchored; what it offers is what is fitted in it. Brought down, it leaves a derelict hulk."
      local has = section(sheet, "Citadel")
      row(has, "Field", `{whole(tower.field)} m`)
      row(has, "Service slots", whole(tower.slots or 0))
      row(has, "Battery slots", whole(tower.defences or 0))
      row(has, "Burns", `{tower.fuel} blocks an hour, and more for each service online`, Structures.FUEL.id)
      row(has, "Anchors in", seconds(tower.anchor))
      -- (what its kind does better, and what only its kind fits)
      local kind = tower.kind
      if kind then
        local bonus: Structures.CitadelBonus = Structures.CITADEL_BONUS[kind] or {}
        local better = section(sheet, Structures.CITADEL_KIND_NAMES[kind])
        local function less(share: number?): string?
          return if share then `{whole((1 - share) * 100)}% less` else nil
        end
        if bonus.jobTime then
          row(better, "Manufacturing", `{less(bonus.jobTime)} time, {less(bonus.materials)} materials`)
        end
        if bonus.refine then
          row(better, "Refining", `{whole((bonus.refine - 1) * 100)}% more of what ore and ice give`)
        end
        if bonus.researchTime then
          row(better, "Research", `{less(bonus.researchTime)} time for research, copying and invention; invention {whole((bonus.invent or 0) * 100)} in 100 likelier`)
        end
        if bonus.fees then
          row(better, "Trade", `{less(bonus.fees)} sales tax and broker's fee here`)
        end
        if bonus.gives then
          row(better, "Without a module", table.concat(bonus.gives, " and "))
        end
        if bonus.fuel then
          row(better, "Fuel", less(bonus.fuel) :: string)
        end
        for _, only in Structures.modules do
          if only.kinds and table.find(only.kinds, kind) and (only.least or 1) <= tower.size then
            row(better, "Only this kind fits", only.name, only.id)
          end
        end
      end
      local stands = section(sheet, "Under fire")
      row(stands, "Shield", whole(tower.shield))
      row(stands, "Armour", whole(tower.armor))
      row(stands, "Structure", whole(tower.hull))
      row(stands, "Seals for", `{tower.bay} hours at most: a charge an hour`, Structures.SEAL.id)
    elseif anchored and anchored.citadel then
      sheet.kind = "Citadel service"
      sheet.note = "Fitted in a citadel, a slot each. It gives its service there while it is online, and burns fuel for it."
      local does = section(sheet, "Service")
      row(does, "Gives", anchored.service)
      if anchored.kinds then
        local names: { string } = {}
        for _, each in anchored.kinds do
          table.insert(names, Structures.CITADEL_KIND_NAMES[each])
        end
        row(does, "Fitted only in", table.concat(names, ", ") .. (if anchored.least then ` of {string.lower(Structures.CITADEL_SIZE_NAMES[anchored.least])} size or bigger` else ""))
      end
      local opens = ({ capital = "capital ships to be built here", advanced = "tech 2 hulls to be built here",
        invention = "tech 2 hulls to be invented here", bridge = "ships in its field go to another gravity station's bridge" } :: { [string]: string })[anchored.opens or ""]
      if opens then
        row(does, "Lets", opens)
      end
      local makes = ({ gravity = "a gravity station: a lit jump beacon, and a Jump Bridge may be fitted beside it",
        wormhole = "a wormhole station: holds a wormhole open just outside it, into uncharted space; when it closes, by time or by the mass gone through it, another opens" } :: { [string]: string })[anchored.generator or ""]
      if makes then
        row(does, "Makes it", makes)
      end
      if anchored.needs then
        for _, each in Structures.modules do
          if each.generator == anchored.needs then
            row(does, "Needs beside it", each.name, each.id)
          end
        end
      end
      row(does, "Burns", `{anchored.fuel or 0} blocks an hour`, Structures.FUEL.id)
      row(does, "Comes online in", seconds(anchored.anchor))
    elseif tower then
      sheet.kind = "Control tower"
      sheet.note = "The heart of a starbase. Anchored at a moon and fed with fuel, it throws a field and powers the modules anchored round it."
      local has = section(sheet, "Tower")
      row(has, "Field", `{whole(tower.field)} m`)
      row(has, "Powergrid", `{whole(tower.powergrid)} MW`)
      row(has, "CPU", `{whole(tower.cpu)} tf`)
      row(has, "Burns", `{tower.fuel} blocks an hour`, Structures.FUEL.id)
      row(has, "Anchors in", seconds(tower.anchor))
      local stands = section(sheet, "Under fire")
      row(stands, "Shield", whole(tower.shield))
      row(stands, "Armour", whole(tower.armor))
      row(stands, "Structure", whole(tower.hull))
      row(stands, "Seals for", `{tower.bay} hours at most: a charge an hour`, Structures.SEAL.id)
      -- (what its people's tower is better at)
      local better = section(sheet, `{Factions.byId[tower.faction].name} make`)
      local percent = function(times: number): string
        return `{math.floor((times - 1) * 100 + 0.5)}% more damage`
      end
      row(better, "Gun batteries", `fire {tower.gun} weapons, {percent(tower.gunBonus)}`)
      if tower.missileBonus > 1 then
        row(better, "Missile batteries", percent(tower.missileBonus))
      end
      row(better, if tower.tank == "armor" then "Armour" elseif tower.tank == "shield" then "Shield" else "Structure",
        `every resistance +{math.floor(tower.resist * 100 + 0.5)} points`)
    elseif anchored then
      sheet.kind = "Structure module"
      sheet.note = "Anchored inside a tower's field and run from the tower's power. Whoever built the tower, the module is the same."
      local does = section(sheet, "Module")
      row(does, "Gives", anchored.service)
      row(does, "Powergrid", `{whole(anchored.powergrid)} MW`)
      row(does, "CPU", `{whole(anchored.cpu)} tf`)
      row(does, "Anchors in", seconds(anchored.anchor))
      row(does, "A pilot can anchor one", if anchored.pilot then "yes" else "no")
    else
      sheet.kind = "Fuel"
      sheet.note = "What a control tower burns. A tower that runs out goes dark, and its modules with it."
    end
    local market = section(sheet, "Trade")
    row(market, "Volume", `{whole(if info then info.volume else 0)} m3`)
    row(market, "Base price", `{whole(if info then info.basePrice else 0)} cr`)
  elseif category == "skillbook" then
    local skill: Skills.Skill? = nil
    for _, candidate in Skills.list do
      if Skills.Book(candidate.id) == type then
        skill = candidate
      end
    end
    sheet.kind = "Skill book"
    if skill then
      sheet.note = skill.note
      local to = section(sheet, "Skill")
      row(to, "Teaches", skill.name)
      row(to, "Rank", `{skill.rank} (level 1 takes {seconds(Skills.TrainingSeconds(skill, 1))})`)
      if skill.bonus then
        modifier(to, skill.bonus, true)
      end
      for _, bonus in skill.bonuses or {} :: { Modules.Modifier } do
        modifier(to, bonus, true)
      end
      if #skill.requires > 0 then
        local required = section(sheet, "Requires")
        for _, need in skill.requires do
          row(required, Skills.byId[need.skill].name, `level {need.level}`, Skills.Book(need.skill))
        end
      end
    end
    trade(sheet, type)
  elseif Boosters.byId[type] then
    local booster = Boosters.byId[type]
    sheet.kind = "Booster"
    sheet.note = "Taken out of the hold, or out of the hangar where the pilot is docked, it is used up and is at work for half an hour on every ship they fly. One of a kind at a time, whatever its strength. "
      .. (if booster.wrong > 0 then "Some of the time it sits badly, and takes something for as long as it gives."
        else "A mild one does half what the plain one does, and never sits badly.")
    local does = section(sheet, "Booster")
    row(does, "Gives", booster.note)
    if booster.wrong > 0 then
      row(does, "May take", booster.cost)
      row(does, "Sits badly", `{whole(booster.wrong * 100)} times in 100; {whole(Boosters.TOLERANCE * 100)} fewer a level of Tolerance`)
    else
      row(does, "Sits badly", "never")
    end
    row(does, "Strength", ({ "mild", "plain", "strong" })[booster.strength])
    row(does, "Kind", Boosters.KINDS[booster.kind])
    row(does, "Lasts", `{seconds(Boosters.SECONDS)}; a fifth longer a level of Pharmacology`)
    row(does, "Made from", nameOf(booster.gas), booster.gas)
    trade(sheet, type)
  elseif Injectors.byId[type] then
    local injector = Injectors.byId[type]
    sheet.kind = "Training injector"
    sheet.note = "Banked training time. Used from the hold, or from the hangar where the pilot is docked, it gives the training queue its time at once, as if that much had gone by. Not while the queue has less than that left to train."
    local does = section(sheet, "Training injector")
    row(does, "Gives", `{seconds(injector.seconds)} of training`)
    row(does, "Found", "on station markets, in loyalty stores, in pirates' wrecks, and in data and relic sites")
    trade(sheet, type)
  elseif Ores.gasById[type] then
    sheet.kind = "Gas"
    sheet.note = "Drawn off the clouds of a vapour field with a gas harvester. Nothing refines it, and no station has it to sell: it is what boosters are made from."
    local made = section(sheet, "Made into")
    for _, booster in Boosters.list do
      if booster.gas == type then
        row(made, booster.name .. " Booster", booster.note, booster.id)
      end
    end
    trade(sheet, type)
  else
    sheet.kind = "Goods"
    trade(sheet, type)
  end
  return sheet
end

return Facts
