--!strict
-- Skills: what a pilot knows how to use, and how well.
--
-- A skill has levels 0 to 5. Some gate things: a hull or module names the
-- skills and levels its user needs. Some make the pilot better: a bonus
-- that grows with each level. A pilot starts knowing a handful; any other
-- has to be learned from its book before it can be trained.
--
-- Training takes game time: a level's base time (a minute for the first,
-- ten hours for the fifth) times the skill's rank. It carries on whatever
-- the pilot is doing.

local Modules = require("@lt/Core/Data/Modules")

export type Need = { skill: string, level: number }

export type Skill = {
  id: string,
  name: string,
  rank: number,
  start: number,          -- the level a new pilot has; -1 if it must be learned from a book
  requires: { Need },     -- to train it at all
  -- A modifier on the ship or its weapons; its 'value' is the change per
  -- level (0.05: 5% more a level; -0.03: 3% less).
  bonus: Modules.Modifier?,
  note: string,
}

-- Seconds to train each level of a rank 1 skill.
local LEVEL_SECONDS = { 60, 300, 1500, 7200, 36000 }

local function ship(attribute: string, perLevel: number): Modules.Modifier
  return { on = "ship", attribute = attribute, op = "mul", value = perLevel }
end

local function weapons(family: string, attribute: string, perLevel: number): Modules.Modifier
  return { on = "weapons", family = family, attribute = attribute, op = "mul", value = perLevel }
end

local skills: { Skill } = {
  -- Ships
  { id = "frigates", name = "Frigates", rank = 2, start = 1, requires = {}, note = "Level 2 to fly combat frigates." },
  { id = "industrials", name = "Industrials", rank = 3, start = -1, requires = { { skill = "frigates", level = 2 } },
    note = "To fly haulers." },
  { id = "navigation", name = "Navigation", rank = 1, start = 0, requires = {}, bonus = ship("maxVelocity", 0.05),
    note = "5% more speed a level." },
  { id = "evasive.maneuvering", name = "Evasive Maneuvering", rank = 2, start = -1,
    requires = { { skill = "navigation", level = 2 } }, bonus = ship("inertia", -0.04), note = "4% quicker to turn a level." },
  { id = "propulsion", name = "Afterburners", rank = 1, start = 0, requires = {}, note = "Level 1 to fit an afterburner." },
  -- Guns and missiles
  { id = "projectiles", name = "Projectile Turrets", rank = 1, start = 1, requires = {}, note = "To fit autocannons." },
  { id = "lasers", name = "Laser Turrets", rank = 1, start = 0, requires = {}, note = "Level 1 to fit lasers." },
  { id = "missiles", name = "Missile Launchers", rank = 1, start = 0, requires = {}, note = "Level 1 to fit launchers." },
  { id = "rapid.firing", name = "Rapid Firing", rank = 2, start = -1, requires = { { skill = "projectiles", level = 2 } },
    bonus = weapons("projectile", "duration", -0.04), note = "Autocannons fire 4% faster a level." },
  { id = "sharpshooter", name = "Sharpshooter", rank = 2, start = -1, requires = { { skill = "lasers", level = 2 } },
    bonus = weapons("laser", "optimal", 0.05), note = "5% more laser range a level." },
  { id = "weapon.upgrades", name = "Weapon Upgrades", rank = 2, start = 0, requires = {},
    note = "Level 1 to fit damage and tracking modules." },
  -- Defence
  { id = "shield.operation", name = "Shield Operation", rank = 1, start = 1, requires = {}, note = "To fit shield modules." },
  { id = "shield.management", name = "Shield Management", rank = 3, start = -1,
    requires = { { skill = "shield.operation", level = 2 } }, bonus = ship("shield", 0.05), note = "5% more shield a level." },
  { id = "repair.systems", name = "Repair Systems", rank = 1, start = 0, requires = {}, note = "Level 1 to fit armor repairers." },
  { id = "hull.upgrades", name = "Hull Upgrades", rank = 2, start = 0, requires = {}, bonus = ship("armor", 0.05),
    note = "Level 1 to fit plates and membranes; 5% more armor a level." },
  -- Engineering
  { id = "capacitor.management", name = "Capacitor Management", rank = 3, start = -1, requires = {},
    bonus = ship("capacitor", 0.05), note = "5% more capacitor a level." },
  { id = "electronics", name = "CPU Management", rank = 1, start = 0, requires = {}, bonus = ship("cpu", 0.05),
    note = "5% more CPU a level." },
  { id = "engineering", name = "Power Grid Management", rank = 1, start = 0, requires = {}, bonus = ship("powergrid", 0.05),
    note = "5% more powergrid a level." },
  { id = "targeting", name = "Long Range Targeting", rank = 2, start = -1, requires = {}, bonus = ship("lockRange", 0.05),
    note = "5% more targeting range a level." },
  -- Industry and trade
  { id = "mining", name = "Mining", rank = 1, start = 1, requires = {}, note = "To fit mining lasers; 5% more ore a level after the first." },
  { id = "refining", name = "Reprocessing", rank = 1, start = 0, requires = {}, note = "3% more minerals from ore a level." },
  { id = "industry", name = "Industry", rank = 1, start = 1, requires = {}, note = "To run manufacturing jobs; 4% quicker a level." },
  { id = "mass.production", name = "Mass Production", rank = 2, start = -1, requires = { { skill = "industry", level = 3 } },
    note = "One more job at a time a level." },
  { id = "accounting", name = "Accounting", rank = 3, start = -1, requires = {}, note = "Sales tax a tenth lower a level." },
  { id = "broker.relations", name = "Broker Relations", rank = 2, start = -1, requires = {}, note = "Broker's fee a tenth lower a level." },
}

local Skills = {
  list = skills,
  byId = {} :: { [string]: Skill },
  MAX_LEVEL = 5,
  QUEUE_LENGTH = 10,
}

for _, skill in skills do
  Skills.byId[skill.id] = skill
end

-- Seconds to train a skill from 'level - 1' to 'level'.
function Skills.TrainingSeconds(skill: Skill, level: number): number
  return LEVEL_SECONDS[level] * skill.rank
end

-- What a pilot needs to use a hull or module, by item type. Anything not
-- listed needs nothing.
local NEEDS: { [string]: { Need } } = {
  ["frigate.lancer"] = { { skill = "frigates", level = 2 } },
  ["frigate.harrier"] = { { skill = "frigates", level = 2 } },
  ["industrial.hauler"] = { { skill = "industrials", level = 1 } },
  ["laser.pulse.small"] = { { skill = "lasers", level = 1 } },
  ["autocannon.small"] = { { skill = "projectiles", level = 1 } },
  ["launcher.light"] = { { skill = "missiles", level = 1 } },
  ["miner.small"] = { { skill = "mining", level = 1 } },
  ["shield.extender.small"] = { { skill = "shield.operation", level = 1 } },
  ["shield.booster.small"] = { { skill = "shield.operation", level = 1 } },
  ["shield.hardener"] = { { skill = "shield.operation", level = 2 } },
  ["armor.plate.200mm"] = { { skill = "hull.upgrades", level = 1 } },
  ["armor.membrane"] = { { skill = "hull.upgrades", level = 1 } },
  ["armor.repairer.small"] = { { skill = "repair.systems", level = 1 } },
  ["damage.control"] = { { skill = "hull.upgrades", level = 2 } },
  ["heat.sink"] = { { skill = "weapon.upgrades", level = 1 } },
  ["gyrostabilizer"] = { { skill = "weapon.upgrades", level = 1 } },
  ["ballistic.control"] = { { skill = "weapon.upgrades", level = 1 } },
  ["tracking.enhancer"] = { { skill = "weapon.upgrades", level = 1 } },
  ["afterburner.1mn"] = { { skill = "propulsion", level = 1 } },
}

function Skills.Needs(type: string): { Need }
  return NEEDS[type] or {}
end

-- The first need a pilot with these skill levels does not meet, if any.
function Skills.Missing(needs: { Need }, levels: { [string]: number }): Need?
  for _, need in needs do
    if (levels[need.skill] or -1) < need.level then
      return need
    end
  end
  return nil
end

-- "needs Frigates 2"
function Skills.Describe(need: Need): string
  return `needs {Skills.byId[need.skill].name} {need.level}`
end

-- The id of the book that teaches a skill.
function Skills.Book(skill: string): string
  return "book." .. skill
end

-- The levels a new pilot starts with.
function Skills.Starting(): { [string]: number }
  local levels: { [string]: number } = {}
  for _, skill in skills do
    if skill.start >= 0 then
      levels[skill.id] = skill.start
    end
  end
  return levels
end

return Skills
