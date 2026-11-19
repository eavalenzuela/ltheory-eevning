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
--   regen       how much more what makes its shield come back by itself
--               does: a recharger, a flux coil, a power relay, a rig
--               ("shield")
--   hex         how strongly its electronic warfare of a kind works on
--               another ship ("damp", "paint"...)
--   reach       how far its electronic warfare of a kind reaches
--               ("entangle": a web)
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
local function hybrid(skill: string, per: number, attribute: string, what: string): HullBonus
  return level(skill, per, "weapons", attribute, what, "hybrid")
end
-- (a short-range hybrid hull's: the owner, 2026-11-18, "for hybrid-heavy faction, any short-range ships should get a
-- bonus to webifier range or strength". Range, as a role, is mine.)
local WEB = role(0.5, "reach", "entangle", "stasis webs reach half as far again")
local function laser(skill: string, per: number, attribute: string, what: string): HullBonus
  return level(skill, per, "weapons", attribute, what, "laser")
end
local function laserCap(skill: string): HullBonus
  return laser(skill, -0.10, "capacitor", "lasers use 10% less capacitor")
end
local function regen(skill: string): HullBonus
  return level(skill, 0.10, "regen", "shield", "shield rechargers, flux coils, power relays and regeneration rigs work 10% better")
end
local function armorMend(skill: string): HullBonus
  return level(skill, 0.10, "ship", "armorMend", "its armour mends 10% faster")
end
local PIRATE_LOCK = role(0.5, "ship", "scanResolution", "locks on half as fast again (scan resolution)")
local function hullHP(skill: string): HullBonus
  return level(skill, 0.05, "ship", "hull", "5% more hull")
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

  -- The Orun (2026-11-18): hybrids and armour on hulls with more hull to
  -- them; blaster brawlers that web what they close on, and railgun
  -- snipers.
  ["frigate.knife"] = { hybrid("frigates", 0.05, "damageMultiplier", "5% more hybrid damage"), speed("frigates"), WEB },
  ["frigate.skinner"] = { hybrid("frigates", -0.05, "duration", "hybrid turrets fire 5% faster"),
    hybrid("frigates", 0.10, "optimal", "hybrid turrets reach 10% farther") },
  ["frigate.skiver"] = { hybrid("frigates", 0.05, "damageMultiplier", "5% more hybrid damage"), speed("frigates"), WEB },
  ["destroyer.scythe"] = { hybrid("destroyers", 0.05, "damageMultiplier", "5% more hybrid damage"), armorHP("destroyers"),
    role(0.25, "weapons", "tracking", "turrets track 25% better", "turret"), WEB },
  ["destroyer.kama"] = { hybrid("destroyers", 0.05, "damageMultiplier", "5% more hybrid damage"), armorHP("destroyers"),
    role(0.25, "weapons", "tracking", "turrets track 25% better", "turret"), role(0.25, "ship", "hull", "25% more hull"), WEB },
  ["cruiser.armer"] = { hybrid("cruisers", 0.05, "damageMultiplier", "5% more hybrid damage"), armorRepair("cruisers", 0.075), WEB },
  ["cruiser.gladius"] = { hybrid("cruisers", -0.05, "duration", "hybrid turrets fire 5% faster"),
    hybrid("cruisers", 0.10, "optimal", "hybrid turrets reach 10% farther") },
  ["cruiser.falchion"] = { hybrid("cruisers", -0.05, "duration", "hybrid turrets fire 5% faster"),
    hybrid("cruisers", 0.10, "optimal", "hybrid turrets reach 10% farther") },
  ["battlecruiser.zweihander"] = { hybrid("battlecruisers", 0.05, "damageMultiplier", "5% more hybrid damage"),
    armorResists("battlecruisers"), WEB },
  ["battleship.claymore"] = { hybrid("battleships", 0.05, "damageMultiplier", "5% more hybrid damage"),
    hybrid("battleships", 0.10, "optimal", "hybrid turrets reach 10% farther") },
  ["industrial.pill"] = { cargo("industrials"), hullHP("industrials") },
  ["industrial.longhorn"] = { cargo("industrials"), hullHP("industrials") },
  ["carrier.katana"] = { level("carriers", 0.05, "drones", "damage", "fighters do 5% more damage"), armorResists("carriers") },
  ["carrier.excalibur"] = { level("carriers", 0.05, "drones", "damage", "fighters do 5% more damage"), armorResists("carriers") },
  ["siegedreadnought.sword"] = { hybrid("dreadnoughts", 0.05, "damageMultiplier", "5% more hybrid damage"), hullHP("dreadnoughts") },
  ["siegedreadnought.guthook"] = { hybrid("dreadnoughts", 0.05, "damageMultiplier", "5% more hybrid damage"), hullHP("dreadnoughts") },
  ["capitalindustrial.stag"] = { level("capital.industrials", 0.05, "ore", "hold", "5% more ore hold"), hullHP("capital.industrials") },
  ["barge.scarab"] = { level("mining", 0.05, "mining", "yield", "5% more from mining"), hullHP("mining") },
  ["freighter.tiger"] = { cargo("freighters"), hullHP("freighters") },

  -- The Kethri (2026-11-18, the owner: "looks good"): lasers, which live
  -- on the capacitor, and armour; brawlers and beam snipers.
  ["frigate.battleaxe"] = { laser("frigates", 0.05, "damageMultiplier", "5% more laser damage"), laserCap("frigates") },
  ["frigate.gauntlet"] = { laser("frigates", -0.05, "duration", "lasers fire 5% faster"),
    laser("frigates", 0.10, "optimal", "lasers reach 10% farther") },
  ["destroyer.sentry"] = { laser("destroyers", 0.05, "damageMultiplier", "5% more laser damage"), laserCap("destroyers"),
    role(0.5, "weapons", "optimal", "lasers reach half as far again", "laser") },
  ["destroyer.noxious"] = { laser("destroyers", 0.05, "damageMultiplier", "5% more laser damage"), laserCap("destroyers"),
    role(0.5, "weapons", "optimal", "lasers reach half as far again", "laser") },
  ["cruiser.perfexis"] = { laser("cruisers", 0.05, "damageMultiplier", "5% more laser damage"), armorResists("cruisers") },
  ["battlecruiser.extremis"] = { laser("battlecruisers", -0.05, "duration", "lasers fire 5% faster"), laserCap("battlecruisers") },
  ["battlecruiser.deluge"] = { laser("battlecruisers", -0.05, "duration", "lasers fire 5% faster"), laserCap("battlecruisers") },
  ["battleship.teardrop"] = { laser("battleships", 0.05, "damageMultiplier", "5% more laser damage"), armorHP("battleships") },
  ["industrial.porter"] = { cargo("industrials"), armorHP("industrials") },
  ["carrier.tennit"] = { level("carriers", 0.05, "drones", "damage", "fighters do 5% more damage"), armorResists("carriers") },
  ["dreadnought.pox"] = { laser("dreadnoughts", 0.05, "damageMultiplier", "5% more laser damage"), laserCap("dreadnoughts") },
  ["capitalindustrial.piton"] = { level("capital.industrials", 0.05, "ore", "hold", "5% more ore hold"), armorHP("capital.industrials") },
  ["ultracapital.leslarmesdenova"] = { laser("ultracapitals", 0.05, "damageMultiplier", "5% more laser damage"),
    armorHP("ultracapitals") },
  ["barge.pulley"] = { level("mining", 0.05, "mining", "yield", "5% more from mining"), armorHP("mining") },
  ["freighter.hiven"] = { cargo("freighters"), armorHP("freighters") },

  -- The Unbound, the pirates' hulls made over from others (2026-11-18):
  -- projectiles, some launchers, and hull. Every one of them locks on
  -- the quicker (the owner: "I would give them a role bonus to target
  -- lock speed / scan resolution. That leans into the 'pirate' side";
  -- the half again is mine), and what catches ships holds them from
  -- farther.
  ["frigate.cutthroat"] = { projectile("frigates", 0.05, "damageMultiplier", "5% more projectile damage"), speed("frigates"),
    PIRATE_LOCK, role(0.25, "reach", "scramble", "warp disruptors reach a quarter farther") },
  ["destroyer.jackal"] = { projectile("destroyers", -0.05, "duration", "projectile turrets fire 5% faster"), hullHP("destroyers"),
    PIRATE_LOCK, role(0.25, "reach", "scramble", "warp disruptors reach a quarter farther") },
  ["cruiser.marauder"] = { projectile("cruisers", 0.05, "damageMultiplier", "5% more projectile damage"), missileDamage("cruisers"),
    PIRATE_LOCK },
  ["attackbattlecruiser.reaver"] = { projectile("battlecruisers", 0.05, "damageMultiplier", "5% more projectile damage"),
    projectile("battlecruisers", 0.10, "falloff", "projectile turrets keep their aim 10% farther past their best range"), PIRATE_LOCK },
  ["battlecruiser.brigand"] = { projectile("battlecruisers", -0.05, "duration", "projectile turrets fire 5% faster"),
    hullHP("battlecruisers"), PIRATE_LOCK },
  ["battleship.ravager"] = { projectile("battleships", 0.05, "damageMultiplier", "5% more projectile damage"), hullHP("battleships"),
    PIRATE_LOCK },
  ["industrial.fence"] = { cargo("industrials"), speed("industrials"), PIRATE_LOCK },
  ["carrier.warren"] = { level("carriers", 0.05, "drones", "damage", "fighters do 5% more damage"), hullHP("carriers"), PIRATE_LOCK },
  ["dreadnought.tyrant"] = { projectile("dreadnoughts", 0.05, "damageMultiplier", "5% more projectile damage"), hullHP("dreadnoughts"),
    PIRATE_LOCK },
  ["siegedreadnought.despoiler"] = { projectile("dreadnoughts", 0.05, "damageMultiplier", "5% more projectile damage"),
    hullHP("dreadnoughts"), PIRATE_LOCK },
  ["capitalindustrial.hoard"] = { level("capital.industrials", 0.05, "ore", "hold", "5% more ore hold"),
    hullHP("capital.industrials"), PIRATE_LOCK },
  ["supercarrier.matriarch"] = { level("supercarriers", 0.05, "drones", "damage", "fighters and bombers do 5% more damage"),
    hullHP("supercarriers"), PIRATE_LOCK },

  -- The Vail (2026-11-18): lasers, and a heavy shield that tanks by its
  -- own recharge (the owner: "given they have a heavy shield, they should
  -- actually not be active-rep ships, they should be shield-regen module
  -- bonuses"); beam snipers and regenerating brawlers.
  ["frigate.prostration"] = { laser("frigates", 0.05, "damageMultiplier", "5% more laser damage"),
    laser("frigates", 0.10, "optimal", "lasers reach 10% farther") },
  ["frigate.undulation"] = { laser("frigates", -0.05, "duration", "lasers fire 5% faster"), regen("frigates") },
  ["destroyer.adoration"] = { laser("destroyers", 0.05, "damageMultiplier", "5% more laser damage"), laserCap("destroyers"),
    role(0.5, "weapons", "optimal", "lasers reach half as far again", "laser") },
  ["destroyer.exaltation"] = { laser("destroyers", -0.05, "duration", "lasers fire 5% faster"), regen("destroyers"),
    role(0.25, "weapons", "tracking", "turrets track 25% better", "turret") },
  ["destroyer.aberration"] = { laser("destroyers", 0.05, "damageMultiplier", "5% more laser damage"), laserCap("destroyers"),
    role(0.5, "weapons", "optimal", "lasers reach half as far again", "laser"), role(0.25, "ship", "shield", "25% more shield") },
  ["cruiser.enervation"] = { laser("cruisers", 0.05, "damageMultiplier", "5% more laser damage"),
    laser("cruisers", 0.10, "optimal", "lasers reach 10% farther") },
  ["cruiser.interstition"] = { laser("cruisers", 0.05, "damageMultiplier", "5% more laser damage"),
    laser("cruisers", 0.10, "optimal", "lasers reach 10% farther") },
  ["attackbattlecruiser.intervention"] = { laser("battlecruisers", 0.05, "damageMultiplier", "5% more laser damage"),
    laser("battlecruisers", 0.10, "optimal", "lasers reach 10% farther") },
  ["battlecruiser.innocence"] = { laser("battlecruisers", -0.05, "duration", "lasers fire 5% faster"), shieldResists("battlecruisers") },
  ["battleship.extravagance"] = { laser("battleships", 0.05, "damageMultiplier", "5% more laser damage"), shieldHP("battleships") },
  ["battleship.penance"] = { laser("battleships", -0.05, "duration", "lasers fire 5% faster"), regen("battleships") },
  ["carrier.accordance"] = { level("carriers", 0.05, "drones", "damage", "fighters do 5% more damage"), shieldResists("carriers") },
  ["dreadnought.awe"] = { laser("dreadnoughts", 0.05, "damageMultiplier", "5% more laser damage"), shieldHP("dreadnoughts") },
  ["capitalindustrial.embrace"] = { level("capital.industrials", 0.05, "ore", "hold", "5% more ore hold"), shieldHP("capital.industrials") },
  ["ultracapital.archangel"] = { level("ultracapitals", 0.05, "drones", "damage", "fighters and bombers do 5% more damage"),
    shieldHP("ultracapitals") },
  ["barge.panacea"] = { level("mining", 0.05, "mining", "yield", "5% more from mining"), shieldHP("mining") },
  ["freighter.indulgence"] = { cargo("freighters"), shieldHP("freighters") },

  -- The Nimia (2026-11-18, the owner: "this looks good"): blasters, and
  -- no shield but an armour and a hull that mend by themselves; the
  -- short-range hulls web what they close on.
  ["frigate.oon"] = { hybrid("frigates", 0.05, "damageMultiplier", "5% more hybrid damage"), armorMend("frigates"), WEB },
  ["destroyer.kri"] = { hybrid("destroyers", -0.05, "duration", "hybrid turrets fire 5% faster"), armorMend("destroyers"), WEB,
    role(0.25, "weapons", "tracking", "turrets track 25% better", "turret") },
  ["cruiser.hon"] = { hybrid("cruisers", 0.05, "damageMultiplier", "5% more hybrid damage"), speed("cruisers"), WEB },
  ["cruiser.kava"] = { hybrid("cruisers", -0.05, "duration", "hybrid turrets fire 5% faster"),
    level("cruisers", 0.10, "ship", "hullMend", "its hull mends 10% faster"), WEB },
  ["cruiser.hano"] = { hybrid("cruisers", 0.05, "damageMultiplier", "5% more hybrid damage"), speed("cruisers"), WEB },
  ["battlecruiser.hoku"] = { hybrid("battlecruisers", 0.05, "damageMultiplier", "5% more hybrid damage"), armorMend("battlecruisers"),
    WEB },
  ["battleship.rru"] = { hybrid("battleships", 0.05, "damageMultiplier", "5% more hybrid damage"), armorHP("battleships"), WEB },
  ["industrial.rikn"] = { cargo("industrials"), armorMend("industrials") },
  ["carrier.takk"] = { level("carriers", 0.05, "drones", "damage", "fighters do 5% more damage"), armorMend("carriers") },
  ["siegedreadnought.zzk"] = { hybrid("dreadnoughts", 0.05, "damageMultiplier", "5% more hybrid damage"), armorHP("dreadnoughts") },
  ["capitalindustrial.knuu"] = { armorHP("capital.industrials"), armorMend("capital.industrials") },
  ["capitalindustrial.zzna"] = { level("capital.industrials", 0.05, "ore", "hold", "5% more ore hold"), armorMend("capital.industrials") },
  ["supercarrier.yuln"] = { level("supercarriers", 0.05, "drones", "damage", "fighters and bombers do 5% more damage"),
    armorHP("supercarriers") },
  ["freighter.jojk"] = { cargo("freighters"), armorMend("freighters") },
} :: { [string]: { HullBonus } }

-- The classes that no electronic warfare touches (the owner, 2026-11-18:
-- "all supercaps+ are immune to ewar"): webs, painters, dampeners,
-- disruptors of tracking and guidance, jammers, neutralisers and drains
-- do nothing to them. A warp disruptor still holds one as a capital is
-- held (a capital's disruptor), and an interdiction field does.
HullBonuses.IMMUNE = { supercarrier = true, ultracapital = true } :: { [string]: boolean }

return HullBonuses
