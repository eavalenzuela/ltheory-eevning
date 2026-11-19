--!strict
-- Skills: what a pilot knows how to use, and how well.
--
-- A skill has levels 0 to 5. Some gate things: a hull or module names the
-- skills and levels its user needs. Some make the pilot better: a bonus
-- that grows with each level. A pilot starts knowing a handful; any other
-- has to be learned from its book before it can be trained.
--
-- Training takes game time: a level's base time (six seconds for the
-- first, twenty-four minutes for the fifth) times the skill's rank. It
-- carries on whatever the pilot is doing.

local Modules = require("@lt/Core/Data/Modules")
local Ships = require("@lt/Core/Data/Ships")

export type Need = { skill: string, level: number }

export type Skill = {
  id: string,
  name: string,
  rank: number,
  start: number,          -- the level a new pilot has; -1 if it must be learned from a book
  requires: { Need },     -- to train it at all
  -- A modifier on the ship or its weapons; its 'value' is the change per
  -- level (0.05: 5% more a level; -0.03: 3% less). For weapons, the
  -- family "turret" is every turret there is, whatever it fires.
  bonus: Modules.Modifier?,
  -- More of them, for a skill that does the same to several things at
  -- once (a layer's four resistances).
  bonuses: { Modules.Modifier }?,
  note: string,
  -- A people's own teaching (a faction's id): no market of anybody
  -- else's has the book. (The Nimia's two.)
  faction: string?,
  -- One of the crafts of a trade: it gates nothing and nothing is laid
  -- out on the footing that a pilot has it (a job's level is for a
  -- pilot with the plain skills at that level: Tactical/Assault). What
  -- it gives is over and above.
  craft: boolean?,
}

-- Seconds to train each level of a rank 1 skill. (A tenth of what they
-- were until 2026-11-18, the owner's: "training speeds need to be MUCH
-- shorter, given it's an offline game", and of how much, "10x faster":
-- every skill there is to the fifth level in about a week of play.)
local LEVEL_SECONDS = { 6, 24, 90, 360, 1440 }

local function ship(attribute: string, perLevel: number): Modules.Modifier
  return { on = "ship", attribute = attribute, op = "mul", value = perLevel }
end

local function weapons(family: string, attribute: string, perLevel: number): Modules.Modifier
  return { on = "weapons", family = family, attribute = attribute, op = "mul", value = perLevel }
end

-- The same change to what a layer lets through of each kind of damage.
local function resists(layer: string, perLevel: number): { Modules.Modifier }
  local all: { Modules.Modifier } = {}
  for kind = 1, 4 do
    table.insert(all, ship(`{layer}Resonance.{kind}`, perLevel))
  end
  return all
end

local skills: { Skill } = {
  -- Ships
  { id = "frigates", name = "Frigates", rank = 2, start = 1, requires = {}, note = "Level 2 to fly combat frigates." },
  { id = "destroyers", name = "Destroyers", rank = 3, start = -1, requires = { { skill = "frigates", level = 3 } },
    note = "Level 1 to fly destroyers." },
  { id = "cruisers", name = "Cruisers", rank = 5, start = -1, requires = { { skill = "destroyers", level = 3 } },
    note = "Level 1 to fly cruisers." },
  { id = "battleships", name = "Battleships", rank = 8, start = -1, requires = { { skill = "cruisers", level = 4 } },
    note = "Level 1 to fly battleships." },
  -- (The classes of the owner's ladder of 2026-11-12. What each asks
  -- first, and how long it is to learn, are first drafts.)
  { id = "battlecruisers", name = "Battlecruisers", rank = 6, start = -1, requires = { { skill = "cruisers", level = 3 } },
    note = "Level 1 to fly battlecruisers, of either kind." },
  { id = "carriers", name = "Carriers", rank = 12, start = -1,
    requires = { { skill = "battleships", level = 3 }, { skill = "drones", level = 4 } }, note = "Level 1 to fly carriers." },
  { id = "dreadnoughts", name = "Dreadnoughts", rank = 12, start = -1, requires = { { skill = "battleships", level = 4 } },
    note = "Level 1 to fly dreadnoughts and siege dreadnoughts." },
  { id = "supercarriers", name = "Supercarriers", rank = 16, start = -1, requires = { { skill = "carriers", level = 4 } },
    note = "Level 1 to fly supercarriers." },
  { id = "ultracapitals", name = "Ultracapitals", rank = 20, start = -1, requires = { { skill = "carriers", level = 5 } },
    note = "Level 1 to fly an ultracapital." },
  { id = "industrials", name = "Industrials", rank = 3, start = -1, requires = { { skill = "frigates", level = 2 } },
    note = "To fly haulers." },
  { id = "freighters", name = "Freighters", rank = 8, start = -1, requires = { { skill = "industrials", level = 4 } },
    note = "Level 1 to fly freighters." },
  { id = "capital.industrials", name = "Capital Industrials", rank = 10, start = -1, requires = { { skill = "freighters", level = 3 } },
    note = "Level 1 to fly capital industrials." },
  { id = "navigation", name = "Navigation", rank = 1, start = 0, requires = {}, bonus = ship("maxVelocity", 0.05),
    note = "5% more speed a level." },
  { id = "jump.drives", name = "Jump Drive Operation", rank = 6, start = -1, requires = { { skill = "navigation", level = 4 } },
    note = "Level 1 to use a jump drive, and a tenth further a level." },
  { id = "evasive.maneuvering", name = "Evasive Maneuvering", rank = 2, start = -1,
    requires = { { skill = "navigation", level = 2 } }, bonus = ship("inertia", -0.04), note = "4% quicker to turn a level." },
  { id = "propulsion", name = "Afterburners", rank = 1, start = 0, requires = {}, note = "Level 1 to fit an afterburner." },
  -- Guns and missiles
  -- (Each family's skill makes its guns hit 5% harder a level, the
  -- launchers' its missiles: the owner, 2026-11-18, of a ladder of
  -- damage skills as the reference has, so that a trained pilot hits
  -- much harder than a new one.)
  { id = "projectiles", name = "Projectile Turrets", rank = 1, start = 1, requires = {},
    bonus = weapons("projectile", "damageMultiplier", 0.05), note = "To fit autocannons; projectile turrets hit 5% harder a level." },
  { id = "lasers", name = "Laser Turrets", rank = 1, start = 0, requires = {},
    bonus = weapons("laser", "damageMultiplier", 0.05), note = "Level 1 to fit lasers; lasers hit 5% harder a level." },
  { id = "hybrids", name = "Hybrid Turrets", rank = 1, start = -1, requires = {},
    bonus = weapons("hybrid", "damageMultiplier", 0.05), note = "Level 1 to fit blasters and railguns; they hit 5% harder a level." },
  { id = "medium.weapons", name = "Medium Weapons", rank = 3, start = -1, requires = { { skill = "weapon.upgrades", level = 2 } },
    note = "Level 1 to fit medium turrets and heavy launchers." },
  { id = "large.weapons", name = "Large Weapons", rank = 5, start = -1, requires = { { skill = "medium.weapons", level = 3 } },
    note = "Level 1 to fit large turrets and cruise launchers." },
  { id = "capital.weapons", name = "Capital Weapons", rank = 9, start = -1, requires = { { skill = "large.weapons", level = 4 } },
    note = "Level 1 to fit XL turrets and siege launchers: what a siege dreadnought mounts." },
  { id = "missiles", name = "Missile Launchers", rank = 1, start = 0, requires = {},
    bonus = weapons("missile", "damageMultiplier", 0.05), note = "Level 1 to fit launchers; missiles hit 5% harder a level." },
  -- (every turret since 2026-11-18, the owner's; it was autocannons only)
  { id = "rapid.firing", name = "Rapid Firing", rank = 2, start = -1, requires = { { skill = "weapon.upgrades", level = 2 } },
    bonus = weapons("turret", "duration", -0.04), note = "Turrets fire 4% faster a level." },
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
  -- The Nimia's own (the project owner's: "skills that increase repair
  -- rate"): a hull of theirs mends by itself, and these make it mend
  -- faster. They do nothing for a hull that does not. (First figures.)
  { id = "armor.mending", name = "Armour Mending", rank = 3, start = -1, requires = { { skill = "hull.upgrades", level = 3 } },
    bonus = ship("armorMend", 0.10), faction = "nimia",
    note = "Level 1 to fit a Mending Lattice; a hull that mends by itself mends its armour 10% faster a level." },
  { id = "hull.mending", name = "Hull Mending", rank = 4, start = -1, requires = { { skill = "armor.mending", level = 3 } },
    bonus = ship("hullMend", 0.10), faction = "nimia",
    note = "A hull that mends by itself mends its hull 10% faster a level." },
  -- Engineering
  { id = "capacitor.management", name = "Capacitor Management", rank = 3, start = -1, requires = {},
    bonus = ship("capacitor", 0.05), note = "5% more capacitor a level." },
  { id = "electronics", name = "CPU Management", rank = 1, start = 0, requires = {}, bonus = ship("cpu", 0.05),
    note = "5% more CPU a level." },
  { id = "engineering", name = "Power Grid Management", rank = 1, start = 0, requires = {}, bonus = ship("powergrid", 0.05),
    note = "5% more powergrid a level." },
  -- (How many things a ship can have locked at once is its hull's to say,
  -- and this skill's: the project owner's, 2026-11-13, "ship class
  -- defines max, along with skills". A fifth more a level, of what the
  -- hull allows, and whole targets only: Tactical/Vitals. A first figure.)
  { id = "target.management", name = "Target Management", rank = 2, start = -1, requires = {}, bonus = ship("maxTargets", 0.20),
    note = "A fifth more targets locked at once a level, of what the hull allows (whole ones only)." },
  { id = "targeting", name = "Long Range Targeting", rank = 2, start = -1, requires = {}, bonus = ship("lockRange", 0.05),
    note = "5% more targeting range a level." },
  -- Industry and trade
  { id = "mining", name = "Mining", rank = 1, start = 1, requires = {}, note = "To fit mining lasers; 5% more ore a level after the first." },
  { id = "refining", name = "Reprocessing", rank = 1, start = 0, requires = {}, note = "3% more minerals from ore a level." },
  { id = "industry", name = "Industry", rank = 1, start = 1, requires = {}, note = "To run manufacturing jobs; 4% quicker a level." },
  { id = "mass.production", name = "Mass Production", rank = 2, start = -1, requires = { { skill = "industry", level = 3 } },
    note = "One more job at a time a level." },
  { id = "invention", name = "Invention", rank = 4, start = -1, requires = { { skill = "industry", level = 3 } },
    note = "Level 1 to invent a tech 2 blueprint; 5% likelier to succeed a level." },
  { id = "accounting", name = "Accounting", rank = 3, start = -1, requires = {}, note = "Sales tax a tenth lower a level." },
  { id = "broker.relations", name = "Broker Relations", rank = 2, start = -1, requires = {}, note = "Broker's fee a tenth lower a level." },
  -- (What came later comes after: a pilot's first skills are the ones above.)
  -- Working on the hull itself
  { id = "jury.rigging", name = "Jury Rigging", rank = 2, start = -1, requires = {}, note = "Level 1 to fit rigs." },
  -- Picking over what is left
  { id = "salvaging", name = "Salvaging", rank = 3, start = -1, requires = {},
    note = "Level 1 to fit a salvager. 10% likelier to bring something off each cycle a level." },
  -- Company
  { id = "fighters", name = "Fighters", rank = 8, start = -1, requires = { { skill = "drones", level = 5 } },
    note = "Level 1 to launch fighters from a carrier, level 3 for bombers; and four more of either in hand a level." },
  { id = "drones", name = "Drones", rank = 2, start = 0, requires = {},
    note = "One more drone out at once a level, as far as the hull controls. Level 4 for a tech 2 drone." },
  { id = "leadership", name = "Leadership", rank = 4, start = 1, requires = {},
    note = "One more hired pilot under your command a level." },
  -- What a pilot takes
  { id = "pharmacology", name = "Pharmacology", rank = 2, start = -1, requires = {},
    note = "A booster lasts a fifth longer a level." },
  { id = "tolerance", name = "Tolerance", rank = 3, start = -1, requires = { { skill = "pharmacology", level = 2 } },
    note = "A booster sits badly 8% less often a level, from one time in two." },
  -- Towers
  { id = "anchoring", name = "Anchoring", rank = 4, start = 0, requires = {},
    note = "One more control tower of your own a level. A pilot keeps one without it." },
  { id = "remote.repair", name = "Remote Repair", rank = 2, start = -1, requires = { { skill = "repair.systems", level = 2 } },
    note = "To fit remote shield boosters and armor repairers: small (1), medium (3), large (4)." },
  -- Getting in another ship's way
  { id = "electronic.warfare", name = "Electronic Warfare", rank = 3, start = -1, requires = { { skill = "electronics", level = 2 } },
    note = "To fit painters and dampeners (1), neutralisers (2) and jammers (3)." },
  -- What a pilot has in their head
  { id = "cybernetics", name = "Cybernetics", rank = 3, start = -1, requires = {},
    note = "One more place for an implant a level, to five." },
  -- Getting into things
  { id = "hacking", name = "Hacking", rank = 3, start = -1, requires = { { skill = "electronics", level = 2 } },
    note = "Level 1 to fit a relic or data analyzer; one more code in the buffer for each level after." },
  -- Not being seen
  { id = "cloaking", name = "Cloaking", rank = 4, start = -1, requires = { { skill = "electronics", level = 3 } },
    note = "Level 1 to fit a cloaking device." },
  -- Holding things
  { id = "propulsion.jamming", name = "Propulsion Jamming", rank = 3, start = -1, requires = { { skill = "electronics", level = 2 } },
    note = "Level 1 to fit an entanglement projector or a warp disruptor. Level 4 for a capital warp disruptor." },
  -- Finding things
  { id = "astrometrics", name = "Astrometrics", rank = 3, start = 0, requires = {},
    note = "Each scan brings a hidden site 10% nearer to found a level." },

  -- The crafts of each trade (2026-11-14: the rest of the tree, with
  -- the project owner's word on it: "don't just name them what they
  -- upgrade"). Each is named for what a pilot learns to do, and says in
  -- its note what comes of it. None gates anything: they make a pilot
  -- better at what they can do already. Every figure is a first one.
  -- Gunnery
  { id = "deflection", name = "Deflection Shooting", rank = 2, start = -1, craft = true, requires = { { skill = "weapon.upgrades", level = 2 } },
    bonus = weapons("turret", "tracking", 0.05), note = "Turrets follow a crossing target 5% better a level." },
  -- (the owner's names, 2026-11-18, for a craft of all turrets and one
  -- of all missiles)
  { id = "precision.shooting", name = "Precision Shooting", rank = 2, start = -1, craft = true,
    requires = { { skill = "weapon.upgrades", level = 2 } },
    bonus = weapons("turret", "damageMultiplier", 0.03), note = "Turrets hit 3% harder a level." },
  { id = "missile.tracking", name = "Missile Tracking", rank = 2, start = -1, craft = true, requires = { { skill = "missiles", level = 2 } },
    bonus = weapons("missile", "damageMultiplier", 0.03), note = "Missiles hit 3% harder a level." },
  { id = "windage", name = "Windage", rank = 2, start = -1, craft = true, requires = { { skill = "weapon.upgrades", level = 2 } },
    bonus = weapons("turret", "falloff", 0.05), note = "Turrets keep their aim 5% farther past their best range a level." },
  { id = "salvo.drill", name = "Salvo Drill", rank = 2, start = -1, craft = true, requires = { { skill = "missiles", level = 2 } },
    bonus = weapons("missile", "duration", -0.03), note = "Launchers fire 3% faster a level." },
  { id = "long.burn", name = "Long Burn", rank = 2, start = -1, craft = true, requires = { { skill = "missiles", level = 2 } },
    note = "A missile flies 5% longer a level, and so that much farther." },
  { id = "proximity.fusing", name = "Proximity Fusing", rank = 3, start = -1, craft = true, requires = { { skill = "missiles", level = 3 } },
    note = "A missile's blast is 4% tighter a level: more of it lands on a small ship." },
  { id = "swarm.tactics", name = "Swarm Tactics", rank = 3, start = -1, craft = true, requires = { { skill = "drones", level = 3 } },
    note = "Your drones' guns do 4% more a level." },
  -- Flying
  { id = "wayfinding", name = "Wayfinding", rank = 2, start = -1, craft = true, requires = { { skill = "navigation", level = 2 } },
    bonus = ship("warpSpeed", 0.05), note = "5% faster in warp a level." },
  { id = "running.dark", name = "Running Dark", rank = 3, start = -1, craft = true, requires = { { skill = "navigation", level = 3 } },
    bonus = ship("signature", -0.02), note = "A 2% smaller signature a level: slower to be locked, and less of a missile lands." },
  { id = "stowage", name = "Stowage", rank = 1, start = -1, craft = true, requires = {}, bonus = ship("cargo", 0.05),
    note = "A hold takes 5% more a level." },
  { id = "lean.burn", name = "Lean Burn", rank = 4, start = -1, craft = true, requires = { { skill = "jump.drives", level = 2 } },
    note = "A jump burns 5% less fuel a level." },
  { id = "snapshot", name = "Snapshot", rank = 2, start = -1, craft = true, requires = { { skill = "electronics", level = 2 } },
    bonus = ship("scanResolution", 0.05), note = "Locks 5% quicker a level." },
  -- Keeping the ship whole
  { id = "reactor.trim", name = "Reactor Trim", rank = 2, start = -1, craft = true, requires = { { skill = "engineering", level = 2 } },
    bonus = ship("capacitorRecharge", -0.05), note = "The capacitor recharges 5% quicker a level." },
  { id = "field.harmonics", name = "Field Harmonics", rank = 2, start = -1, craft = true, requires = { { skill = "shield.operation", level = 2 } },
    bonus = ship("shieldRecharge", -0.05), note = "The shield recharges 5% quicker a level." },
  { id = "dispersal", name = "Dispersal", rank = 3, start = -1, craft = true, requires = { { skill = "shield.operation", level = 3 } },
    bonuses = resists("shield", -0.02), note = "A shield lets 2% less of everything through a level." },
  { id = "glancing.angles", name = "Glancing Angles", rank = 3, start = -1, craft = true, requires = { { skill = "hull.upgrades", level = 3 } },
    bonuses = resists("armor", -0.02), note = "Armour lets 2% less of everything through a level." },
  { id = "compartmentation", name = "Compartmentation", rank = 2, start = -1, craft = true, requires = { { skill = "hull.upgrades", level = 2 } },
    bonus = ship("hull", 0.05), note = "5% more hull a level." },
  -- Making and selling
  { id = "bench.science", name = "Bench Science", rank = 3, start = -1, craft = true, requires = { { skill = "industry", level = 2 } },
    note = "Research into a blueprint takes 5% less time a level." },
  { id = "draughtsmanship", name = "Draughtsmanship", rank = 2, start = -1, craft = true, requires = { { skill = "industry", level = 2 } },
    note = "Copying a blueprint takes 5% less time a level." },
  { id = "ledger.keeping", name = "Ledger Keeping", rank = 2, start = -1, craft = true, requires = {},
    note = "Two more lots up on the stations' boards at a time a level." },
  -- Working for people
  { id = "hard.bargaining", name = "Hard Bargaining", rank = 3, start = -1, craft = true, requires = {},
    note = "A station's jobs pay 3% more a level." },
  { id = "protocol", name = "Protocol", rank = 3, start = -1, craft = true, requires = {},
    note = "What you do for a faction counts 5% more with it a level." },
  { id = "patronage", name = "Patronage", rank = 3, start = -1, craft = true, requires = { { skill = "protocol", level = 2 } },
    note = "A job done earns 5% more loyalty points a level." },
  { id = "paymaster", name = "Paymaster", rank = 3, start = -1, craft = true, requires = { { skill = "leadership", level = 2 } },
    note = "Hired pilots are paid 4% less a day a level." },
  -- Towers and colonies, and the corporation (the owner, 2026-11-16, of the skills for structures and the corporation I put to them: "Yes to all your recs"; the names, ranks,
  -- needs and figures mine).
  { id = "husbandry", name = "Husbandry", rank = 3, start = -1, craft = true, requires = { { skill = "anchoring", level = 1 } },
    note = "A tower of yours burns 5% less fuel a level." },
  { id = "raising", name = "Raising", rank = 3, start = -1, craft = true, requires = { { skill = "anchoring", level = 2 } },
    note = "Your towers and their modules anchor 10% quicker a level." },
  { id = "fire.control", name = "Fire Control", rank = 3, start = -1, craft = true, requires = { { skill = "anchoring", level = 2 } },
    note = "Your towers' batteries do 5% more damage a level." },
  { id = "deep.boring", name = "Deep Boring", rank = 3, start = -1, craft = true, requires = {},
    note = "Your colonies' extractors bring up 5% more a level." },
  { id = "hospitality", name = "Hospitality", rank = 3, start = -1, craft = true, requires = { { skill = "leadership", level = 2 } },
    note = "Room for two more members in your corporation a level." },
  { id = "renown", name = "Renown", rank = 3, start = -1, craft = true, requires = { { skill = "leadership", level = 2 } },
    note = "Pilots ask to join your corporation 10% more often a level." },
  { id = "muster", name = "Muster", rank = 4, start = -1, craft = true, requires = { { skill = "leadership", level = 3 } },
    note = "One more call on your members posted at once a level." },
  { id = "stewardship", name = "Stewardship", rank = 4, start = -1, craft = true, requires = { { skill = "anchoring", level = 3 } },
    note = "The systems you hold pay 5% more levy a level." },
  -- Finding things
  { id = "triangulation", name = "Triangulation", rank = 3, start = -1, craft = true, requires = { { skill = "astrometrics", level = 2 } },
    note = "Each scan probe near a signal is worth 10% more a level." },
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

-- The skills' groups, as the skills window lists them down its left
-- (the owner, 2026-11-16, of the groups I put to them: "Hulls ->
-- Piloting. Flight -> Navigation", and "Combine weapons and gunnery";
-- the rest as they were put; and Structures, with Anchoring moved into
-- it, on their "Yes to all your recs"). Every
-- skill is in one, and one only.
export type Group = { id: string, name: string, skills: { string } }
Skills.GROUPS = {
  { id = "piloting", name = "Piloting", skills = { "frigates", "destroyers", "cruisers", "battlecruisers", "battleships", "industrials",
    "freighters", "capital.industrials", "carriers", "dreadnoughts", "supercarriers", "ultracapitals" } },
  { id = "navigation", name = "Navigation", skills = { "navigation", "propulsion", "evasive.maneuvering", "jump.drives", "wayfinding",
    "running.dark", "lean.burn" } },
  -- (Weapons and Gunnery were two groups as put; the owner: "Combine
  -- weapons and gunnery". The one name, Weapons, is mine: the sizes in
  -- it are for launchers too.)
  { id = "weapons", name = "Weapons", skills = { "weapon.upgrades", "medium.weapons", "large.weapons", "capital.weapons",
    "projectiles", "lasers", "hybrids", "rapid.firing", "precision.shooting", "sharpshooter", "deflection", "windage" } },
  { id = "missiles", name = "Missiles", skills = { "missiles", "missile.tracking", "salvo.drill", "long.burn", "proximity.fusing" } },
  { id = "drones", name = "Drones", skills = { "drones", "fighters", "swarm.tactics" } },
  { id = "shields", name = "Shields", skills = { "shield.operation", "shield.management", "field.harmonics", "dispersal" } },
  { id = "armour", name = "Armour and Hull", skills = { "repair.systems", "hull.upgrades", "glancing.angles", "compartmentation",
    "remote.repair", "armor.mending", "hull.mending" } },
  { id = "systems", name = "Ship Systems", skills = { "electronics", "engineering", "capacitor.management", "reactor.trim", "jury.rigging" } },
  { id = "targeting", name = "Targeting", skills = { "target.management", "targeting", "snapshot" } },
  { id = "warfare", name = "Electronic Warfare", skills = { "electronic.warfare", "propulsion.jamming", "cloaking" } },
  { id = "exploration", name = "Exploration", skills = { "astrometrics", "triangulation", "hacking", "salvaging" } },
  { id = "mining", name = "Mining", skills = { "mining", "refining", "stowage" } },
  { id = "industry", name = "Industry", skills = { "industry", "mass.production", "invention", "bench.science", "draughtsmanship" } },
  { id = "trade", name = "Trade", skills = { "accounting", "broker.relations", "ledger.keeping" } },
  { id = "standing", name = "Standing", skills = { "protocol", "patronage", "hard.bargaining" } },
  { id = "structures", name = "Structures", skills = { "anchoring", "husbandry", "raising", "fire.control", "deep.boring" } },
  { id = "command", name = "Command", skills = { "leadership", "paymaster", "hospitality", "renown", "muster", "stewardship" } },
  { id = "enhancement", name = "Implants and Boosters", skills = { "cybernetics", "pharmacology", "tolerance" } },
} :: { Group }
-- A skill's group, by the skill's id.
Skills.groupOf = {} :: { [string]: Group }
for _, group in Skills.GROUPS do
  for _, id in group.skills do
    assert(Skills.byId[id], `the skill group {group.name} names a skill there is not: {id}`)
    assert(Skills.groupOf[id] == nil, `{id} is in two skill groups`)
    Skills.groupOf[id] = group
  end
end

-- A pilot's level in a skill: 0 for one they have not learned, and for
-- a ship nobody trained to fly (whose levels are nil).
function Skills.Level(levels: { [string]: number }?, id: string): number
  return if levels then math.max(0, levels[id] or 0) else 0
end

-- Seconds to train a skill from 'level - 1' to 'level'.
function Skills.TrainingSeconds(skill: Skill, level: number): number
  return LEVEL_SECONDS[level] * skill.rank
end

-- What a pilot needs to use a hull or module, by item type. Anything not
-- listed needs nothing.
local NEEDS: { [string]: { Need } } = {
  ["frigate.battleaxe"] = { { skill = "frigates", level = 2 } },
  ["industrial.hauler"] = { { skill = "industrials", level = 1 } },
  ["freighter.dray"] = { { skill = "freighters", level = 1 } },
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
  ["mwd.5mn"] = { { skill = "propulsion", level = 3 } },
}

-- The needs of the tech 2 make of each module, worked out once.
local improved: { [string]: { Need } } = {}

function Skills.Needs(type: string): { Need }
  local listed = NEEDS[type]
  if listed then
    return listed
  end
  -- A tech 2 module wants what the plain one does, three levels higher
  -- (and never less than four of anything).
  local better = Modules.byId[type]
  if better and better.tech == 2 and better.base then
    local needs = improved[type]
    if needs == nil then
      needs = {}
      for _, need in Skills.Needs(better.base) do
        table.insert(needs, { skill = need.skill, level = math.clamp(need.level + 3, 4, 5) })
      end
      if #needs == 0 then
        table.insert(needs, { skill = "engineering", level = 4 })
      end
      improved[type] = needs
    end
    return needs
  end
  -- A custom make wants no more than the plain one.
  if better and better.meta and better.base then
    return Skills.Needs(better.base)
  end
  -- A tech 2 hull wants what the plain one does, as a tech 2 module does.
  local rebuilt = Ships.byId[type]
  if rebuilt and rebuilt.tech == 2 and rebuilt.base then
    local needs = improved[type]
    if needs == nil then
      needs = {}
      for _, need in Skills.Needs(rebuilt.base) do
        table.insert(needs, { skill = need.skill, level = math.clamp(need.level + 3, 4, 5) })
      end
      improved[type] = needs
    end
    return needs
  end
  -- A hull or a module made from a table says what it needs itself.
  local hull = Ships.byId[type]
  if hull and hull.requires then
    return hull.requires
  end
  local module = Modules.byId[type]
  return if module and module.requires then module.requires else {}
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
