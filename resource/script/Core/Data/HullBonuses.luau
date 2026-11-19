--!strict
-- What each hull does better than its class (the owner, 2026-11-18: hull
-- bonuses "hull by hull", which give each hull tactics of its own: an
-- active-repair brawler, a kiter, a ship that holds its target at range).
--
-- A bonus is so much a level of a skill, the hull's class skill as a
-- rule ("+5% missile damage a level of Frigates"), or a role bonus,
-- which is the hull's whatever its pilot knows ("+50% missile flight
-- time"). Each is a multiplier, 1 + so much a level: what is better
-- smaller (a rate of fire's time between shots, what a resistance lets
-- through) has its so much below nought.
--
-- What a bonus is on ('on'), and what of it ('attribute'):
--   ship        a ship's attribute (Core/Attributes): "armor", "cargo",
--               "maxVelocity"..., or "armorResonance" for all four of a
--               layer's
--   weapons     its weapons of a family ("missile", "projectile",
--               "laser", "hybrid", or "turret" for every family of
--               turret): "damageMultiplier", "duration", "flight",
--               "tracking"...
--   launcher    one launcher's weapons ('module': "launcher.torpedo")
--   repair      what a local repairer of a layer mends ("armor",
--               "shield")
--   afterburner how much more speed an afterburner gives ("speed")
--   hex         how strongly its electronic warfare of a kind works on
--               another ship ("damp", "paint"...)
--   drones      what its drones, fighters and bombers do ("damage")
--   mining      what its mining yields ("yield")
--   ore         its ore hold ("hold")
--   spinal      its bow gun ("damage")
-- Where Core/Attributes, Tactical/Combat and Assets/Items read them.

export type HullBonus = {
  skill: string?, -- nil for a role bonus
  per: number,
  on: string,
  attribute: string,
  family: string?,
  module: string?,
  note: string,   -- what the info window says of it
}

local HullBonuses = {}

local function level(skill: string, per: number, on: string, attribute: string, note: string, family: string?, module: string?): HullBonus
  return { skill = skill, per = per, on = on, attribute = attribute, family = family, module = module, note = note }
end

local function role(per: number, on: string, attribute: string, note: string, family: string?, module: string?): HullBonus
  return { skill = nil, per = per, on = on, attribute = attribute, family = family, module = module, note = note }
end

-- (the bonuses, by skill: so much a level)
local function missileDamage(skill: string): HullBonus
  return level(skill, 0.05, "weapons", "damageMultiplier", "5% more missile damage", "missile")
end
local function missileRate(skill: string): HullBonus
  return level(skill, -0.05, "weapons", "duration", "launchers fire 5% faster", "missile")
end
local function missileFlight(skill: string, per: number): HullBonus
  return level(skill, per, "weapons", "flight", `missiles fly {string.format("%g", per * 100)}% longer`, "missile")
end
local function armorRepair(skill: string, per: number): HullBonus
  return level(skill, per, "repair", "armor", `armour repairers mend {string.format("%g", per * 100)}% more`)
end
local function armorResists(skill: string): HullBonus
  return level(skill, -0.04, "ship", "armorResonance", "armour resists 4% more of every kind of damage")
end
local function armorHP(skill: string): HullBonus
  return level(skill, 0.05, "ship", "armor", "5% more armour")
end
local function projectile(skill: string, per: number, attribute: string, what: string): HullBonus
  return level(skill, per, "weapons", attribute, what, "projectile")
end
local function shieldBoost(skill: string): HullBonus
  return level(skill, 0.075, "repair", "shield", "shield boosters mend 7.5% more")
end
local function shieldResists(skill: string): HullBonus
  return level(skill, -0.04, "ship", "shieldResonance", "the shield resists 4% more of every kind of damage")
end
local function shieldHP(skill: string): HullBonus
  return level(skill, 0.05, "ship", "shield", "5% more shield")
end
local function cargo(skill: string): HullBonus
  return level(skill, 0.05, "ship", "cargo", "5% more hold")
end
local function speed(skill: string): HullBonus
  return level(skill, 0.05, "ship", "maxVelocity", "5% faster")
end
-- (the Vessari's frigates: an afterburner the faster for the pilot's Afterburners)
local AFTERBURNER = level("propulsion", 0.05, "afterburner", "speed", "an afterburner's speed bonus 5% greater")

HullBonuses.byHull = {
  -- The Vessari (the owner, 2026-11-18): missiles and armour, so kiters
  -- and active-repair tankers.
  ["frigate.akashi"] = { missileDamage("frigates"), missileFlight("frigates", 0.10), AFTERBURNER },
  ["frigate.kabuto"] = { missileRate("frigates"), armorRepair("frigates", 0.10), AFTERBURNER },
  ["destroyer.nozomi"] = { missileDamage("destroyers"), armorResists("destroyers"),
    role(0.5, "weapons", "flight", "missiles fly 50% longer", "missile") },
  ["destroyer.kanau"] = { missileDamage("destroyers"), armorResists("destroyers"),
    role(0.5, "weapons", "flight", "missiles fly 50% longer", "missile"), role(0.25, "ship", "armor", "25% more armour") },
  ["cruiser.ouyou"] = { missileDamage("cruisers"), armorRepair("cruisers", 0.05) },
  ["cruiser.hoshizora"] = { missileDamage("cruisers"), armorRepair("cruisers", 0.05),
    role(0.5, "hex", "damp", "sensor dampeners 50% stronger") },
  ["cruiser.raiden"] = { armorHP("cruisers"), level("cruisers", 0.05, "spinal", "damage", "5% more damage from the bow railgun") },
  ["attackbattlecruiser.manazashi"] = { missileDamage("battlecruisers"), missileFlight("battlecruisers", 0.10),
    role(1.0, "launcher", "damageMultiplier", "torpedoes do twice the damage", nil, "launcher.torpedo") },
  ["battlecruiser.naishou"] = { missileRate("battlecruisers"), armorResists("battlecruisers"),
    role(0.25, "weapons", "tracking", "turrets track 25% better", "turret") },
  ["battleship.owari"] = { missileRate("battleships"), armorHP("battleships") },
  ["battleship.yoake"] = { level("battleships", 0.05, "weapons", "damageMultiplier", "5% more projectile damage", "projectile"),
    armorRepair("battleships", 0.075) },
  ["industrial.mizumushi"] = { level("industrials", 0.05, "ship", "cargo", "5% more hold"),
    level("industrials", 0.05, "ship", "maxVelocity", "5% faster") },
  ["industrial.akaboshi"] = { level("industrials", 0.05, "ship", "cargo", "5% more hold"),
    level("industrials", 0.05, "ship", "maxVelocity", "5% faster") },
  ["carrier.azayake"] = { level("carriers", 0.05, "drones", "damage", "fighters do 5% more damage"), armorResists("carriers") },
  ["capitalindustrial.okami"] = { level("capital.industrials", 0.05, "mining", "yield", "5% more from mining"),
    level("capital.industrials", 0.05, "ore", "hold", "5% more ore hold") },
  ["ultracapital.daiichi"] = { level("ultracapitals", 0.05, "drones", "damage", "fighters and bombers do 5% more damage"),
    armorHP("ultracapitals") },
  ["freighter.yoruzake"] = { level("freighters", 0.05, "ship", "cargo", "5% more hold"), armorHP("freighters") },

  -- The Talmar (2026-11-18, the owner: "looks good for now"): projectiles
  -- and shields, fast; active-shield brawlers and falloff kiters.
  ["frigate.carvarro"] = { projectile("frigates", 0.05, "damageMultiplier", "5% more projectile damage"), shieldBoost("frigates") },
  ["frigate.creavo"] = { projectile("frigates", -0.05, "duration", "projectile turrets fire 5% faster"),
    projectile("frigates", 0.10, "falloff", "projectile turrets keep their aim 10% farther past their best range") },
  ["frigate.nephelo"] = { projectile("frigates", -0.05, "duration", "projectile turrets fire 5% faster"),
    projectile("frigates", 0.10, "falloff", "projectile turrets keep their aim 10% farther past their best range") },
  ["destroyer.meseolo"] = { projectile("destroyers", -0.05, "duration", "projectile turrets fire 5% faster"),
    projectile("destroyers", 0.10, "optimal", "projectile turrets reach 10% farther"),
    role(0.5, "weapons", "falloff", "projectile turrets keep their aim half as far again past their best range", "projectile") },
  ["destroyer.osso"] = { projectile("destroyers", -0.05, "duration", "projectile turrets fire 5% faster"),
    projectile("destroyers", 0.10, "optimal", "projectile turrets reach 10% farther"),
    role(0.5, "weapons", "falloff", "projectile turrets keep their aim half as far again past their best range", "projectile") },
  ["cruiser.paestro"] = { projectile("cruisers", 0.05, "damageMultiplier", "5% more projectile damage"), shieldBoost("cruisers") },
  ["cruiser.stenanno"] = { projectile("cruisers", -0.05, "duration", "projectile turrets fire 5% faster"), shieldResists("cruisers") },
  ["battlecruiser.sopholto"] = { projectile("battlecruisers", 0.05, "damageMultiplier", "5% more projectile damage"),
    shieldResists("battlecruisers") },
  ["battleship.losiano"] = { projectile("battleships", 0.05, "damageMultiplier", "5% more projectile damage"), shieldHP("battleships") },
  ["battleship.phaeto"] = { projectile("battleships", -0.05, "duration", "projectile turrets fire 5% faster"), shieldBoost("battleships") },
  ["industrial.armadillo"] = { cargo("industrials"), shieldHP("industrials") },
  ["industrial.sunfish"] = { cargo("industrials"), speed("industrials") },
  ["industrial.tarantula"] = { cargo("industrials"), speed("industrials") },
  ["carrier.scoppo"] = { level("carriers", 0.05, "drones", "damage", "fighters do 5% more damage"), shieldResists("carriers") },
  ["dreadnought.concorso"] = { projectile("dreadnoughts", 0.05, "damageMultiplier", "5% more projectile damage"), shieldHP("dreadnoughts") },
  ["capitalindustrial.jaguar"] = { level("capital.industrials", 0.05, "ore", "hold", "5% more ore hold"), shieldHP("capital.industrials") },
  ["capitalindustrial.rapa"] = { level("capital.industrials", 0.05, "ore", "hold", "5% more ore hold"), shieldHP("capital.industrials") },
  ["supercarrier.nullo"] = { level("supercarriers", 0.05, "drones", "damage", "fighters and bombers do 5% more damage"),
    shieldHP("supercarriers") },
  ["barge.anteater"] = { level("mining", 0.05, "mining", "yield", "5% more from mining"), shieldHP("mining") },
  ["freighter.rhino"] = { cargo("freighters"), speed("freighters") },
  ["freighter.sugarglider"] = { cargo("freighters"), speed("freighters") },
} :: { [string]: { HullBonus } }

-- The classes that no electronic warfare touches (the owner, 2026-11-18:
-- "all supercaps+ are immune to ewar"): webs, painters, dampeners,
-- disruptors of tracking and guidance, jammers, neutralisers and drains
-- do nothing to them. A warp disruptor still holds one as a capital is
-- held (a capital's disruptor), and an interdiction field does.
HullBonuses.IMMUNE = { supercarrier = true, ultracapital = true } :: { [string]: boolean }

return HullBonuses
