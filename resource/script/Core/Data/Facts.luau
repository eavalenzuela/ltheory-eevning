--!strict
-- What there is to say about a type of item: its attributes, as labelled
-- values under headings, for an information window to show. One place
-- knows how every kind of thing is described; nothing here is drawn.
--
--   local sheet = Facts.Of("frigate.lancer")
--   sheet.name, sheet.kind, sheet.note
--   for _, section in sheet.sections do ... section.title, section.rows

local Blueprints = require("@lt/Core/Data/Blueprints")
local Components = require("@lt/Core/Data/Components")
local Drones = require("@lt/Core/Data/Drones")
local Factions = require("@lt/Core/Data/Factions")
local Modules = require("@lt/Core/Data/Modules")
local Ores = require("@lt/Core/Data/Ores")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")
local Planets = require("@lt/Core/Data/Planets")
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
local SIZES = { "Small", "Medium", "Large" }

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
local function words(attribute: string): string
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
  sheet.kind = if faction then `{faction.name} {hull.class}` else string.upper(string.sub(hull.class, 1, 1)) .. string.sub(hull.class, 2)
  sheet.note = if hull.donor then `Made over from the {nameOf(hull.donor)}.`
    elseif faction then faction.note
    else ""

  local defence = section(sheet, "Defence")
  row(defence, "Shield", `{whole(hull.shield)} HP`)
  row(defence, "Armour", `{whole(hull.armor)} HP`)
  row(defence, "Hull", `{whole(hull.hull)} HP`)
  row(defence, "Shield resists (EM / th / kin / exp)", resists(hull.shieldResonance))
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

  needs(sheet, hull.id)
  if hull.restricted then
    local to = section(sheet, "Trade")
    row(to, "Worth", `{whole(hull.basePrice)} cr`)
    row(to, "Sold", "nowhere: not a hull the human factions sell or build")
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

  if weapon then
    local to = section(sheet, "Weapon")
    row(to, "Damage", `x{plain(weapon.damageMultiplier)} of its charge's`)
    row(to, "Fires every", seconds(weapon.duration))
    if weapon.optimal > 0 then
      row(to, "Optimal range", metres(weapon.optimal))
      row(to, "Falloff", metres(weapon.falloff))
      row(to, "Tracking", plain(weapon.tracking))
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
  end
  if module.slot == "rig" then
    local to = section(sheet, "Rig")
    row(to, "Calibration", `{plain(module.calibration or 0)} of a hull's 400`)
    row(to, "Taken out", "it is destroyed")
  end
  if module.salvager then
    local salvager = module.salvager
    local to = section(sheet, "Salvaging")
    row(to, "Chance a cycle", `{plain(salvager.chance * 100)}%, and 10% more a level of Salvaging`)
    row(to, "Range", metres(salvager.range))
    row(to, "Capacitor a cycle", `{plain(salvager.capacitor)} GJ every {seconds(salvager.duration)}`)
  end
  if module.cloak then
    local to = section(sheet, "Cloak")
    row(to, "While it runs", "the ship cannot be targeted, and can target nothing")
    row(to, "Switched off by", `anything within {metres(module.cloak.reach)}`)
    row(to, "Cannot be switched on", "while anybody has the ship targeted")
  end
  if module.hex then
    local hex = module.hex
    local titles: { [string]: string } = { web = "Stasis web", scramble = "Warp disruption", paint = "Target painting",
      damp = "Sensor dampening", neut = "Energy neutralising", jam = "Jamming", shield = "Remote shield boosting",
      armor = "Remote armour repair" }
    local does: { [string]: string } = {
      web = `top speed cut to {plain(hex.strength * 100)}%`, scramble = "cannot warp",
      paint = `signature {plain(hex.strength * 100)}% of what it was`,
      damp = `lock range and scan resolution cut to {plain(hex.strength * 100)}%`,
      neut = `{plain(hex.strength)} GJ taken from its capacitor a cycle`,
      jam = `{plain(hex.strength * 100)}% chance a cycle of breaking its locks`,
      shield = `{plain(hex.strength)} shield put back a cycle`, armor = `{plain(hex.strength)} armour put back a cycle`,
    }
    local to = section(sheet, titles[hex.kind])
    row(to, "On its target", does[hex.kind])
    row(to, "Range", metres(hex.range))
    row(to, "Capacitor a cycle", `{plain(hex.capacitor)} GJ every {seconds(hex.duration)}`)
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
  row(fitting, "CPU", `{plain(module.cpu)} tf`)
  row(fitting, "Powergrid", `{plain(module.powergrid)} MW`)
  needs(sheet, module.id)
  trade(sheet, module.id)
end

local function chargeSheet(sheet: Sheet, charge: Modules.ChargeType)
  sheet.kind = `{SIZES[charge.size] or "Small"} {charge.family} charge`
  local to = section(sheet, "Charge")
  row(to, "Damage", damage(charge.damage, 1))
  if charge.family == "missile" then
    row(to, "Speed", `{plain(charge.velocity)} m/s`)
    row(to, "Flies for", seconds(charge.flightTime))
    row(to, "Range", metres(charge.velocity * charge.flightTime))
    row(to, "Explosion radius", metres(charge.explosionRadius))
    row(to, "Explosion velocity", `{plain(charge.explosionVelocity)} m/s`)
  elseif charge.rangeMultiplier ~= 1 then
    row(to, "Optimal range", percent(charge.rangeMultiplier))
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
    sheet.kind = "Ore"
    sheet.note = if ore.wild then "Found only in lawless space." else "Found in the asteroid belts."
    local to = section(sheet, "Refines to (per 100 units, at perfect yield)")
    for _, yield in ore.yields do
      row(to, nameOf(yield.mineral), whole(yield.amount), yield.mineral)
    end
    trade(sheet, type)
  elseif category == "mineral" then
    sheet.kind = "Mineral"
    local to = section(sheet, "Refined from")
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
    local blueprint = Blueprints.byId[type]
    sheet.kind = "Blueprint"
    local to = section(sheet, "Makes")
    row(to, nameOf(blueprint.product), `{blueprint.perRun} a run`, blueprint.product)
    row(to, "A run takes", seconds(blueprint.seconds))
    local materials = section(sheet, "Materials a run")
    for _, material in blueprint.materials do
      row(materials, nameOf(material.type), whole(material.quantity), material.type)
    end
    local market = section(sheet, "Trade")
    row(market, "Base price", `{whole(blueprint.basePrice)} cr`)
  elseif category == "drone" then
    local drone = Drones.byId[type]
    sheet.kind = "Drone"
    sheet.note = "Launched from the hold to fight beside the ship: it goes for what it is pointed at, or for whatever is attacking its owner. Near enough when its owner warps or docks, it is taken aboard; left behind, it is lost."
    local gun = Modules.byId[drone.gun]
    local flies = Ships.byId[drone.hull]
    local has = section(sheet, "Drone")
    row(has, "Armed with", gun.name, gun.id)
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
    if tower then
      sheet.kind = "Control tower"
      sheet.note = "The heart of a starbase. Anchored at a moon and fed with fuel, it throws a field and powers the modules anchored round it."
      local has = section(sheet, "Tower")
      row(has, "Field", `{whole(tower.field)} m`)
      row(has, "Powergrid", `{whole(tower.powergrid)} MW`)
      row(has, "CPU", `{whole(tower.cpu)} tf`)
      row(has, "Burns", `{tower.fuel} blocks an hour`, Structures.FUEL.id)
      row(has, "Anchors in", seconds(tower.anchor))
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
      if #skill.requires > 0 then
        local required = section(sheet, "Requires")
        for _, need in skill.requires do
          row(required, Skills.byId[need.skill].name, `level {need.level}`, Skills.Book(need.skill))
        end
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
