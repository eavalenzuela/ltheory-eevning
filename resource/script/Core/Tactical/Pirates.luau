--!strict
-- Pirates: where they turn up, what they fly and how they fight.
--
-- They haunt asteroid belts, and in lawless space they wait at gates.
-- When the player's ship comes to a place that has seen none for a
-- while, a pack arrives some way off, closes in, and attacks. What
-- comes follows from how safe the system is (Describe/Galaxy): a scout
-- or two where order is kept, raiders and a destroyer where it is
-- thin, and cruisers, now and then a battleship, where there is none.
--
-- They fly their own hulls, the Unbound's (Data/Ships): other people's
-- ships cut down and bolted back together. A kind of pirate is a hull,
-- what it would like fitted (it takes as much of that as the hull has
-- room, power and hardpoints for), how far off it likes to fight, and
-- what killing it pays. The bounty is on the pilot, not the hull.
--
-- Not all of them are alike. Away from where order is kept, now and
-- then one of a pack is a veteran, and in lawless space now and then
-- its captain: the same kind in the same hull, with the better makes
-- of whatever it fits that has one (Data/Modules: the custom make for
-- a veteran, the masterwork for a captain), by another name, and with
-- more on its head. A stronghold is always a captain's. What such a
-- ship had fitted is found in its wreck as it was more often than a
-- plain pirate's is found better than it looked (Tactical/Aftermath),
-- and a captain's wreck is the only place a masterwork is to be had.
--
-- Each flies with the same orders a player gives (orbit, lock,
-- activate), so anything a pirate can do, a pilot can. They ignore
-- capsules, but where no law is kept, with nothing better there, they
-- shoot those too (the owner, 2026-11-22). A pack left alone for a few minutes goes away. One that
-- carries an afterburner burns it to get to its prey, and whenever its
-- prey gets away from it: it is there sooner, and is not to be walked
-- away from. Where it likes to fight it lets the afterburner go and
-- circles at its own speed. (Burning all the while was tried, and
-- measured: circling at twice the speed, the small ones are not to be
-- hit by anything big, and a battleship that came through every camp
-- meant for it came through seven in twenty-four. And those of a job's
-- camp, or of a tower of their own, do not burn at all: with them
-- arriving in half the time the same battleship came through thirteen,
-- and the jobs are laid out level by level for the ship each is for.)
--
-- A pack fights as one. Of the ships of the pilot's side in front of
-- it, it goes for whoever is mending the others, and failing that for
-- whoever has least left to lose; and every one of the pack makes the
-- same choice, so what it shoots is shot by all of it. (Each circles
-- its prey from as far off as its kind likes to fight, which is where
-- its guns are best: six kilometres for a cruiser and fifteen for a
-- battleship. Standing farther off than that was tried, and holding
-- still at that range: either way it did worse, for want of anything
-- that reaches so far and still hits.) And one that is badly hurt breaks off, turns
-- for somewhere far away and warps: gone, with what was on its head,
-- unless it is held or finished first. (Not a scout, who is too green
-- to know when, nor a captain, who would sooner go down with the ship;
-- and nobody who is defending their own camp or tower.)
--
-- (When the strategic layer arrives, how many come and where will follow
-- from pirate pressure in the system instead of these fixed rules.)

local Battles = require("@lt/Core/Tactical/Battles")
local Blueprints = require("@lt/Core/Data/Blueprints")
local Combat = require("@lt/Core/Tactical/Combat")
local Fields = require("@lt/Core/Tactical/Fields")
local Attributes = require("@lt/Core/Attributes")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Mend = require("@lt/Core/Tactical/Mend")
local Modules = require("@lt/Core/Data/Modules")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Vapour = require("@lt/Core/Tactical/Vapour")
local Surges = require("@lt/Core/Tactical/Surges")
local System = require("@lt/Core/Describe/System")
local Types = require("@lt/Core/Data/Types")

local Pirates = {}

export type Event = { [string]: any }

-- A pirate breaks off when it has this share of itself left (shield,
-- armour and hull together).
Pirates.NERVE = 0.25
-- One with an afterburner burns it when its prey is this much farther
-- off than it likes to fight from, and lets it go when it is within
-- this much of that.
Pirates.BURN, Pirates.COAST = 3000, 1000

-- Whether a module that runs on its own ship is one that drives it
-- harder: an afterburner, or a microwarpdrive.
function Pirates.Drives(module: Modules.ModuleType): boolean
  local boost: { Modules.Modifier } = module.boost or {}
  for _, modifier in boost do
    if modifier.attribute == "maxVelocity" and modifier.value > 1 then
      return true
    end
  end
  return false
end

-- Ticks before a place that had pirates gets more.
local RESPAWN = 1200
-- Ticks a pack waits on an empty grid before leaving.
local PATIENCE = 300
-- How often a gate in lawless space has a pack waiting at it.
local CAMPED = 0.4

-- 'fit' is what it would like, in order: a module, and the charge for
-- it if it matters which (else the first there is of its kind and size).
export type Kind = {
  id: string, hull: string, name: string,
  range: number,      -- m: how far from its prey it likes to fight
  bounty: number,
  tags: number,       -- pirate tags in its wreck
  fit: { { string } },
  grade: number?,     -- 1 for a veteran of its kind, 2 for a captain
  -- The share of itself it breaks off at, where that is not the usual
  -- (Pirates.NERVE): a hauler runs at the first hit.
  nerve: number?,
  -- What it carries in its hold, beside what it fires: so many credits'
  -- worth (at base prices) of a few of these, one stack of each.
  haul: { worth: number, stacks: number, from: { string } }?,
}

local function times(count: number, module: string, charge: string?): { { string } }
  local entries: { { string } } = {}
  for _ = 1, count do
    table.insert(entries, if charge then { module, charge } else { module })
  end
  return entries
end

local function all(...: { { string } }): { { string } }
  local entries: { { string } } = {}
  for _, list in { ... } do
    for _, entry in list do
      table.insert(entries, entry)
    end
  end
  return entries
end

-- A scout is a raider's hull with one gun on it and nothing else: what
-- a new pilot in a Courier can beat. Between them the kinds fire every
-- kind of damage there is (a scout and a jackal explosive, a raider
-- kinetic, a marauder thermal, a ravager EM): they are nobody's hulls
-- and nobody's guns, and no faction's ships are proof against a pack. A raider carries a warp disruptor
-- and a destroyer an entanglement projector (and each the other's, if it has the room):
-- away from where order is kept, a pack holds what it catches.
-- (Bounties since 2026-11-16, the owner, 2026-11-16: "Income is definitely insanely low"; asked how long a pilot should work for the next hull up, "About 5 hours": a pilot in a hull of a pirate's
-- class, killing it about half the time they are out, earns the next
-- hull up in about five hours: a frigate's about a million an hour, a
-- battleship's some thirty. The figures are mine, from what the balance
-- report says the classes do and take; they were 6k, 15k, 40k, 120k,
-- 400k, and 8k, 30k, 12k, 45k, 500k for what a camp is built of.)
local KINDS: { Kind } = {
  { id = "scout", hull = "frigate.cutthroat", name = "Pirate Scout", range = 1500, bounty = 12000, tags = 1,
    fit = { { "autocannon.small", "ammo.fusion" } } },
  { id = "raider", hull = "frigate.cutthroat", name = "Pirate Raider", range = 2000, bounty = 30000, tags = 1,
    fit = all(times(3, "autocannon.small", "ammo.kinetic.short"), times(1, "launcher.light"),
      { { "disruptor.warp" }, { "afterburner.1mn" }, { "armor.plate.200mm" }, { "damage.control" }, { "gyrostabilizer" },
        { "projector.entanglement" } }) },
  { id = "jackal", hull = "destroyer.jackal", name = "Pirate Jackal", range = 3000, bounty = 100000, tags = 2,
    -- (point defence from the level 3 camps up, the owner's 2026-11-19: first, in a turret hardpoint)
    fit = all({ { "pds.small", "ammo.emp" } }, times(6, "autocannon.small", "ammo.fusion"), times(3, "launcher.light"),
      { { "projector.entanglement" }, { "afterburner.1mn" }, { "armor.plate.200mm" }, { "damage.control" }, { "gyrostabilizer" },
        { "disruptor.warp" }, { "armor.plate.200mm" } }) },
  { id = "marauder", hull = "cruiser.marauder", name = "Pirate Marauder", range = 6000, bounty = 500000, tags = 4,
    -- (short launchers since 2026-11-18, when the missiles were set from the
    -- reference: it fights from six kilometres, where they reach)
    fit = all({ { "pds.small", "ammo.emp" } }, times(5, "autocannon.medium", "ammo.thermal.short.medium"), times(3, "launcher.assault"),
      { { "gyrostabilizer" }, { "damage.control" }, { "gyrostabilizer" }, { "gyrostabilizer" }, { "ballistic.control" },
        { "disruptor.warp" }, { "painter.target" }, { "shield.extender.medium" }, { "shield.extender.medium" } }) },
  -- Between the cruiser and the battleship, where no order is kept (the
  -- owner's, 2026-11-22: the pirates' own hulls nobody flew come into
  -- the packs): the Brigand, a battlecruiser that takes a deal of
  -- killing and fires kinetic like a raider; and the Reaver, a
  -- battleship's guns on a battlecruiser's hull: explosive, from farther
  -- off than anything short of a battleship reaches, and not able to
  -- take hitting like a battleship.
  -- (Fits, ranges and bounties: mine.)
  { id = "brigand", hull = "battlecruiser.brigand", name = "Pirate Brigand", range = 8000, bounty = 1200000, tags = 6,
    fit = all({ { "pds.small", "ammo.emp" } }, times(5, "autocannon.medium", "ammo.kinetic.short.medium"),
      times(2, "launcher.heavy", "missile.heavy.kinetic"),
      { { "disruptor.warp" }, { "shield.extender.medium" }, { "shield.extender.medium" }, { "armor.plate.medium" }, { "damage.control" },
        { "gyrostabilizer" }, { "gyrostabilizer" }, { "armor.plate.medium" } }) },
  { id = "reaver", hull = "attackbattlecruiser.reaver", name = "Pirate Reaver", range = 22000, bounty = 1500000, tags = 6,
    fit = all(times(3, "artillery.large", "ammo.explosive.long.large"), times(1, "launcher.heavy", "missile.heavy.explosive"),
      { { "disruptor.warp" }, { "painter.target" }, { "shield.extender.medium" }, { "gyrostabilizer" }, { "gyrostabilizer" },
        { "damage.control" }, { "gyrostabilizer" } }) },
  { id = "ravager", hull = "battleship.ravager", name = "Pirate Ravager", range = 15000, bounty = 2500000, tags = 10,
    fit = all({ { "pds.small", "ammo.emp" } }, times(6, "artillery.large", "ammo.emp.large"), times(4, "launcher.cruise"),
      { { "armor.plate.large" }, { "damage.control" }, { "gyrostabilizer" }, { "armor.plate.large" }, { "shield.extender.large" } }) },
  -- And their haulers. A Fence flies with a pack now and then, hangs
  -- back, and runs at the first hit: held, it is what the pack had
  -- taken, in its hold. A Hoard lies at a tower of theirs, refining
  -- what the moon gives, and does not move or fire: its hold is
  -- minerals by the million, for whoever can cut through it. (Mine.)
  { id = "fence", hull = "industrial.fence", name = "Pirate Fence", range = 30000, bounty = 150000, tags = 2, nerve = 0.95,
    fit = { { "autocannon.small", "ammo.fusion" }, { "shield.extender.small" }, { "cargo.expander" }, { "cargo.expander" },
      { "damage.control" } },
    haul = { worth = 3000000, stacks = 3,
      from = { "composite.prodyne", "component.reactor", "moon.dysprite", "moon.promethite", "component.emitter", "composite.cadvan" } } },
  { id = "hoard", hull = "capitalindustrial.hoard", name = "Pirate Hoard", range = 0, bounty = 3000000, tags = 8, fit = {},
    haul = { worth = 40000000, stacks = 4, from = { "mineral.iridium", "mineral.cobalt", "mineral.titanium", "mineral.copper" } } },
  -- Not of the ladder either: what a camp is built of (Tactical/Assault).
  -- They stand where they are. The stores do nothing; the emplacements
  -- throw missiles at whatever of the pilot's side comes in reach.
  { id = "cache", hull = "works.cache", name = "Pirate Cache", range = 0, bounty = 20000, tags = 2, fit = {} },
  { id = "depot", hull = "works.depot", name = "Pirate Depot", range = 0, bounty = 100000, tags = 6, fit = {} },
  { id = "battery", hull = "works.battery", name = "Pirate Battery", range = 0, bounty = 30000, tags = 2,
    fit = all(times(3, "launcher.light"), { { "armor.plate.200mm" }, { "damage.control" } }) },
  { id = "redoubt", hull = "works.redoubt", name = "Pirate Redoubt", range = 0, bounty = 180000, tags = 5,
    fit = all(times(4, "launcher.heavy"), { { "armor.plate.medium" }, { "damage.control" }, { "ballistic.control" } }) },
  -- And a tower of their own, holding a moon (Tactical/Keeps): it does
  -- nothing itself, and is what the place is about.
  { id = "keep", hull = "works.keep", name = "Pirate Tower", range = 0, bounty = 5000000, tags = 12, fit = {} },
  -- Not one of the ladder: a mender has little to shoot with. It keeps
  -- the rest of its pack whole, and is the one to shoot first.
  { id = "mender", hull = "frigate.cutthroat", name = "Pirate Mender", range = 4500, bounty = 50000, tags = 1,
    fit = { { "remote.armor.small" }, { "remote.armor.small" }, { "autocannon.small", "ammo.fusion" }, { "afterburner.1mn" },
      { "armor.plate.200mm" }, { "damage.control" } } },
  -- And no pirates at all: the Drowned (Data/Factions), who are what is
  -- met past where pirates live, in the deepest of uncharted space.
  -- They are flown by a pirate's rules, hunt what a pirate hunts, and
  -- are as much anybody's friend ("pirates" is what the state calls
  -- whoever comes for the pilot). Their own hulls, the best make of
  -- railgun there is on every hardpoint with the round that hits
  -- hardest in it and coils behind it: hull for hull they hit harder
  -- than a pirate and take half as much killing again, which is what
  -- the owner's "dangerous" is taken for. Each kind holds what it
  -- catches in its own way.
  -- Nobody pays a bounty on one and it carries no tags: what it is
  -- worth is in what its hull is made of (Tactical/Aftermath). Every
  -- one comes under the cloak its hull has, and is not seen until it is
  -- in reach (Pirates.AMBUSH). (Which hulls, their fits and their reach
  -- are first figures.)
  { id = "drowned.cairn", hull = "frigate.cairn", name = "Drowned Cairn", range = 5000, bounty = 0, tags = 0,
    fit = all(times(3, "railgun.small.master", "charge.kinetic.short"),
      { { "disruptor.warp" }, { "afterburner.1mn" }, { "flux.coil" }, { "flux.coil" }, { "damage.control" } }) },
  { id = "drowned.gravestone", hull = "destroyer.gravestone", name = "Drowned Gravestone", range = 7000, bounty = 0, tags = 0,
    fit = all(times(6, "railgun.small.master", "charge.kinetic.short"),
      { { "projector.entanglement" }, { "afterburner.1mn" }, { "flux.coil" }, { "flux.coil" }, { "damage.control" } }) },
  { id = "drowned.casket", hull = "cruiser.casket", name = "Drowned Casket", range = 12000, bounty = 0, tags = 0,
    -- (a Fighter Pylon and its Trident on every one from a cruiser up, the owner's 2026-11-19: they have no
    -- station to replace one in, so what is shot down stays shot down)
    fit = all({ { "pylon.fighter", "drone.trident" } }, times(4, "railgun.medium.master", "charge.kinetic.short.medium"),
      { { "disruptor.warp" }, { "flux.coil" }, { "flux.coil" }, { "flux.coil" }, { "armor.plate.medium" }, { "damage.control" },
        { "shield.extender.medium" } }) },
  { id = "drowned.keeper", hull = "battlecruiser.graveyardkeeper", name = "Drowned Graveyard Keeper", range = 14000, bounty = 0, tags = 0,
    fit = all({ { "pylon.fighter", "drone.trident" } }, times(8, "railgun.medium.master", "charge.kinetic.short.medium"),
      { { "flux.coil" }, { "flux.coil" }, { "flux.coil" }, { "armor.plate.medium" }, { "damage.control" }, { "shield.extender.medium" } }) },
  { id = "drowned.coffin", hull = "battleship.coffin", name = "Drowned Coffin", range = 22000, bounty = 0, tags = 0,
    fit = all({ { "pylon.fighter", "drone.trident" } }, times(7, "railgun.large.master", "charge.kinetic.short.large"),
      { { "flux.coil" }, { "flux.coil" }, { "flux.coil" }, { "armor.plate.large" }, { "damage.control" }, { "shield.extender.large" },
        { "disruptor.warp" } }) },
}

Pirates.kinds = KINDS
Pirates.kindById = {} :: { [string]: Kind }
for _, kind in KINDS do
  Pirates.kindById[kind.id] = kind
end
Pirates.SCOUT = Pirates.kindById["scout"]

-- The grades above a plain pirate: what one is called, how many times
-- over the bounty on it is, and how many more tags it carries.
-- The level a pirate of each grade knows every skill at: a veteran's,
-- a captain's; and an officer's by name (Tactical/Sightings,
-- Tactical/Invasions). (Mine.)
Pirates.SKILL = { [1] = 3, [2] = 4 } :: { [number]: number }
Pirates.OFFICER = 5
Pirates.GRADES = {
  { id = "veteran", bounty = 2, tags = 1 },
  { id = "captain", bounty = 5, tags = 3 },
}
-- How often a pirate that comes is of each grade, by how safe the
-- system is: none where order is kept.
Pirates.GRADED = {
  secure = { 0, 0 },
  low = { 0.12, 0.02 },
  lawless = { 0.25, 0.06 },
} :: { [string]: { number } }

-- What comes, by how safe the system is: each a pack, and its share of
-- the times one comes. (Where order is kept it is a scout, or two.)
local PACKS: { [string]: { { any } } } = {
  secure = { { 0.3, { "scout", "scout" } }, { 0.7, { "scout" } } },
  -- (and now and then, where order is thin, a Brigand on its own)
  low = { { 0.47, { "raider", "raider" } }, { 0.3, { "jackal", "raider" } }, { 0.2, { "jackal", "raider", "raider" } },
    { 0.03, { "brigand" } } },
  lawless = { { 0.34, { "jackal", "jackal", "raider" } }, { 0.3, { "marauder", "mender", "raider" } },
    { 0.17, { "marauder", "jackal", "raider" } }, { 0.09, { "brigand", "marauder", "raider" } },
    { 0.05, { "reaver", "jackal", "raider" } }, { 0.05, { "ravager", "mender", "jackal" } } },
}
-- How often a pack where order is thin or none has a Fence with it.
Pirates.FENCED = { low = 0.08, lawless = 0.15 } :: { [string]: number }
Pirates.PACKS = PACKS
-- And what comes in uncharted space (Tactical/Wormholes), by how deep
-- in the system lies: at the edge what lawless space brings, and
-- further in nothing smaller than a cruiser leads a pack. With how
-- many times as likely each of them is to be a veteran or a captain.
-- (First figures.) As far in as pirates live, which is the third depth
-- (Galaxy.PIRATE_DEPTH): past it nobody comes to anything, yet.
local DEEP: { { { any } } } = {
  PACKS.lawless,
  { { 0.35, { "marauder", "mender", "jackal", "raider" } }, { 0.3, { "marauder", "marauder", "mender" } },
    { 0.15, { "marauder", "brigand", "mender" } }, { 0.2, { "ravager", "mender", "jackal" } } },
  { { 0.35, { "ravager", "mender", "marauder", "jackal" } }, { 0.3, { "ravager", "marauder", "marauder", "mender" } },
    { 0.15, { "ravager", "reaver", "brigand", "mender" } }, { 0.2, { "ravager", "ravager", "mender", "mender" } } },
}
Pirates.DEEP = DEEP
Pirates.DEEP_KEEN = { 2, 2.5, 3 }
-- And past that, in the fourth depth and the fifth, what the Drowned
-- send (the project owner's: "They are found in the 'deep' wormhole
-- systems, and their ships are both dangerous and lucrative"): nothing
-- smaller than a destroyer leads at the fourth, and a battleship or a
-- battlecruiser at the fifth. (First figures.)
local DROWNED: { { { any } } } = {
  { { 0.4, { "drowned.gravestone", "drowned.cairn", "drowned.cairn" } },
    { 0.35, { "drowned.casket", "drowned.gravestone", "drowned.cairn" } },
    { 0.25, { "drowned.keeper", "drowned.casket", "drowned.cairn" } } },
  { { 0.4, { "drowned.coffin", "drowned.casket", "drowned.gravestone", "drowned.cairn" } },
    { 0.35, { "drowned.keeper", "drowned.casket", "drowned.casket", "drowned.gravestone" } },
    { 0.25, { "drowned.coffin", "drowned.coffin", "drowned.keeper", "drowned.cairn" } } },
}
Pirates.DROWNED = DROWNED
-- How near its prey, in its own fighting ranges, a ship that came under
-- its hull's cloak comes out of it.
Pirates.AMBUSH = 1.2

-- The charge a weapon is loaded with when nobody says: the first there
-- is of its family and size.
local function chargeFor(module: Modules.ModuleType): string?
  local weapon = module.weapon
  if weapon then
    for _, candidate in Modules.charges do
      if Modules.Fits(module, candidate) then
        return candidate.id
      end
    end
  end
  return nil
end

-- What a kind of pirate ends up fitted with: as much of what it would
-- like, in order, as its hull takes. Each entry is a module and its
-- charge ("" for none). And, of what it would like, what it got and
-- what it has no room for.
local function fitOf(kind: Kind): ({ { string } }, { { string } }, { { string } })
  local hull = Ships.byId[kind.hull]
  local types: { string } = {}
  local fitted: { { string } } = {}
  local got: { { string } } = {}
  local left: { { string } } = {}
  for _, entry in kind.fit do
    local module = Modules.byId[entry[1]]
    if module then
      table.insert(types, module.id)
      if Attributes.Check(hull, types) then
        table.insert(fitted, { module.id, entry[2] or chargeFor(module) or "" })
        table.insert(got, entry)
      else
        table.remove(types)
        table.insert(left, entry)
      end
    end
  end
  return fitted, got, left
end

function Pirates.Fit(kind: Kind): { { string } }
  return (fitOf(kind))
end

-- A kind as one of a grade flies it: the same hull, and what the plain
-- kind has fitted, each thing the make of it that the grade fits
-- (Modules.Graded). A better make is easier to fit, so then, if there
-- is room, what the plain kind would have liked and could not have.
-- The kind itself, for no grade, and for what does not fly: nobody
-- commands a store.
local graded: { [string]: Kind } = {}
for _, kind in KINDS do
  -- (nor has what the Drowned send a grade: each is what it is)
  -- (nor a hauler: nobody is a veteran of running away)
  local class = Ships.byId[kind.hull].class
  if class ~= "works" and class ~= "industrial" and class ~= "capitalindustrial" and string.sub(kind.id, 1, 8) ~= "drowned." then
    local _, got, left = fitOf(kind)
    for grade, rank in Pirates.GRADES do
      local fit: { { string } } = {}
      for _, entries in { got, left } do
        for _, entry in entries do
          table.insert(fit, { Modules.Graded(entry[1], grade), entry[2] })
        end
      end
      local short = (string.gsub(kind.name, "^Pirate ", ""))
      local made: Kind = {
        id = `{kind.id}.{rank.id}`, hull = kind.hull, name = if grade == 1 then `Veteran {short}` else `{short} Captain`,
        range = kind.range, bounty = kind.bounty * rank.bounty, tags = kind.tags + rank.tags, fit = fit, grade = grade,
      }
      graded[made.id] = made
      Pirates.kindById[made.id] = made
    end
  end
end

-- What a pirate is by the name it flies under: 1 for a veteran, 2 for a
-- captain, 0 for anybody else. (The name is all that is kept of it: for
-- whoever draws the ship. One who leads by name is "Captain <name>" or
-- "<name>, Veteran <kind>": Tactical/Captains.)
function Pirates.Rank(name: string): number
  return if string.find(name, "^Veteran ") or string.find(name, ", Veteran ") then 1
    elseif string.find(name, " Captain$") or string.find(name, "^Captain ") then 2 else 0
end

function Pirates.Graded(kind: Kind, grade: number): Kind
  local rank = Pirates.GRADES[grade]
  return if rank then graded[`{kind.id}.{rank.id}`] or kind else kind
end

-- Fit a ship as a kind is fitted, loaded, with more of what it fires in
-- its hold. (For anybody's ship that is fitted from a list: the
-- factions' patrols are, Tactical/Traffic.)
function Pirates.Equip(state: State.State, ship: State.Ship, kind: Kind)
  local carried: { [string]: boolean } = {}
  for _, entry in Pirates.Fit(kind) do
    local charge: string? = if entry[2] ~= "" then entry[2] else nil
    Items.Equip(state, ship.id, entry[1], charge)
    -- (and more of what it fires in the hold, a crystal aside, which lasts)
    local loaded = if charge then Modules.chargeById[charge] else nil
    if charge and loaded and loaded.family ~= "laser" and not carried[charge] then
      carried[charge] = true
      Items.Add(state, charge, if loaded.family == "missile" then 200 else 2000, ship.id, "cargo")
    end
  end
end

-- What a named officer of the pirates leaves, beside what any captain
-- does (the owner's, 2026-11-15: officer modules "dropped by
-- high-ranking npcs/enemies", a tier above the masterwork, each by its
-- officer's name): so many of the modules they carried, as theirs
-- (Data/Modules), and so many mutators (Assets/Mutators), into their
-- wreck. 'kind' is what they flew, for what they carried: without one
-- (the commander of a tower, who flew nothing), what such a one would.
local COMMANDED = { "launcher.heavy", "autocannon.medium", "armor.repairer.medium", "armor.plate.medium", "shield.extender.medium" }
-- ('people': whose towers' drawings a copy may be of; the Unbound's,
-- the pirates', unless said. A people with no towers leaves none.)
function Pirates.Officer(state: State.State, wreck: number, name: string, kind: Kind?, rng: Rng.Rng, count: number, mutators: number,
  people: string?)
  local roots: { string } = {}
  local carried: { string } = {}
  if kind then
    for _, entry in Pirates.Fit(kind) do
      table.insert(carried, entry[1])
    end
  else
    carried = COMMANDED
  end
  for _, id in carried do
    local module = Modules.byId[id]
    local root = if module then module.base or module.id else nil
    if root and Modules.Officer(root, name) and not table.find(roots, root) then
      table.insert(roots, root)
    end
  end
  for _ = 1, count do
    if #roots == 0 then
      break
    end
    local root = table.remove(roots, Rng.Int(rng, #roots) + 1) :: string
    Items.Add(state, Modules.Officer(root, name) :: string, 1, wreck, "cargo")
  end
  if mutators > 0 then
    Items.Add(state, "mutator", mutators, wreck, "cargo")
  end
  -- And a copy of the drawings of one of the pirates' towers, good for a
  -- run or a few (the owner, 2026-11-16: "Unbound station BPCs (no BP
  -- originals), they drop as named pirate boss loot, similar to named
  -- ship modules"). The small one most often (Pirates.TOWER_COPIES), and
  -- from dice of its own, so that the rest of what they leave is what it
  -- was. (Which size how often, and how many runs: mine.)
  local towers = Blueprints.OfPeople(people or "unbound").towers
  if #towers > 0 then
    local drawn = Rng.For(state.historySeed, wreck, 977)
    local roll, size = Rng.Float(drawn, 0, 1), 1
    for index, share in Pirates.TOWER_COPIES do
      roll -= share
      if roll < 0 then
        size = index
        break
      end
    end
    local print = towers[math.min(size, #towers)]
    Items.Add(state, Blueprints.Copy(print), 1 + Rng.Int(drawn, Pirates.TOWER_RUNS), wreck, "cargo")
  end
end

-- How often a named officer's copy is of the small, the medium and the
-- large pirate tower; and the most runs it is good for.
Pirates.TOWER_COPIES = { 0.6, 0.3, 0.1 }
Pirates.TOWER_RUNS = 3

-- A pirate ship of a kind, in space at a point.
function Pirates.Spawn(state: State.State, kind: Kind, system: number, x: number, y: number, z: number, home: number): State.Ball
  local ship = Space.NewShip(state, kind.hull, kind.name, "pirates", 0)
  -- (how well its pilot knows their trade: a veteran's and a captain's
  -- better than any pirate's, the Drowned's as the Drowned's: Assets/Items)
  ship.skill = if string.sub(kind.id, 1, 8) == "drowned." then Items.NPC_LEVEL.drowned
    else Pirates.SKILL[kind.grade or 0]
  Pirates.Equip(state, ship, kind)
  -- (and what a hauler carries: so much worth of a few things, drawn by
  -- the ship, at what each is worth)
  local haul = kind.haul
  if haul then
    local drawn = Rng.For(state.historySeed, ship.id, 1709)
    local from = table.clone(haul.from)
    for _ = 1, math.min(haul.stacks, #from) do
      local type = table.remove(from, Rng.Int(drawn, #from) + 1) :: string
      local price = math.max(1, Types.Info(type).basePrice)
      Items.Add(state, type, math.max(1, math.floor(haul.worth / haul.stacks / price)), ship.id, "cargo")
    end
  end
  local ball = Space.Launch(state, ship, system, x, y, z)
  state.pilots[ship.id] = { ship = ship.id, range = kind.range, prey = 0, home = home, alone = 0, bounty = kind.bounty, tags = kind.tags,
    -- (what stands where it was put has nowhere to go, a scout does not
    -- know when to, and a captain will not)
    nerve = if kind.nerve then kind.nerve elseif kind.range > 0 and kind.id ~= "scout" and kind.grade ~= 2 then Pirates.NERVE else nil }
  table.insert(state.pilotIds, ship.id)
  return ball
end

local function pirateOnGrid(state: State.State, system: number, grid: number): boolean
  for _, id in state.pilotIds do
    local ball = state.balls[id]
    if ball and ball.system == system and ball.grid == grid then
      return true
    end
  end
  return false
end

-- How many times as long a place is left alone where it is a hired
-- pilot who is there and not the player.
Pirates.AWAY = 2

-- Put a pack at a place: each of its ships somewhere 25 to 35 km out
-- from the middle of it, of the grade the space brings (and a
-- stronghold's first a captain), and say that they have come.
-- ('keen': how many times as likely each is to be a veteran or a captain.)
local function bring(state: State.State, system: number, site: System.Object, band: string, pack: { string }, stronghold: boolean,
  rng: Rng.Rng, away: boolean, events: { Event }, keen: number?)
  local captains, unseen = 0, 0
  for index, id in pack do
    local angle = Rng.Float(rng, 0, 2 * math.pi)
    local out = Rng.Float(rng, 25000, 35000)
    -- (what grade it is, rolled apart, so that nothing else about the pack follows from it)
    local luck = Rng.Next(Rng.For(state.historySeed, state.tick, site.id, index, 73))
    local odds = Pirates.GRADED[band] or Pirates.GRADED.low
    local captain, veteran = odds[2] * (keen or 1), odds[1] * (keen or 1)
    local grade = if (stronghold and index == 1) or luck < captain then 2 elseif luck < captain + veteran then 1 else 0
    -- (what is not graded is what it is: a Fence is nobody's captain)
    local kind = Pirates.Graded(Pirates.kindById[id], grade)
    captains += if kind.grade == 2 then 1 else 0
    local ball = Pirates.Spawn(state, kind, system,
      site.x + out * math.cos(angle), site.y + Rng.Float(rng, -3000, 3000), site.z + out * math.sin(angle), site.id)
    -- (a hull with a cloak of its own comes under it: the Drowned's)
    if Combat.HasCloak(state, ball.id) then
      ball.vitals.cloaked = true
      unseen += 1
    end
    table.insert(events, { kind = "BallAdded", ball = ball.id })
  end
  -- (nobody is told of a pack that nobody can see)
  if unseen < #pack then
    table.insert(events, { kind = "PiratesArrived", grid = site.id, count = #pack, away = away, captains = captains })
  end
end

-- Bring pirates to where a ship of the pilot's side is, if the place is
-- due some: a belt anywhere, or a gate in lawless space. 'away': the
-- ship is a hired pilot's, with the player somewhere else.
local function populate(state: State.State, me: State.Ball, away: boolean, events: { Event })
  local site = Space.Object(state, me.grid)
  if site == nil then
    return
  end
  -- (past the depth pirates live at there are none, and what comes is
  -- the Drowned's: Describe/Galaxy)
  local depth = state.galaxy.systems[me.system].depth or 0
  local theirs = math.min(#DROWNED, depth - Galaxy.PIRATE_DEPTH)
  -- (where pirates are massing, the system is a kind of space worse
  -- than it is: Tactical/Surges)
  local surging = Surges.On(state, me.system)
  local band: string = Surges.Band(state, me.system, Galaxy.Band(state.galaxy.systems[me.system].security))
  local camp = site.kind == "gate" and band == "lawless"
  if site.kind ~= "belt" and not camp then
    return
  end
  -- A site (Tactical/Sites) is a belt to everything else. A den has a
  -- pack a kind of space tougher than the belts here bring, and nobody
  -- troubles a derelict where order is kept.
  local hidden = state.sites[site.id]
  -- (a stronghold is a captain's: the first of whoever keeps it)
  local stronghold = hidden ~= nil and hidden.kind == "combat" and hidden.depth > 0
  if hidden and (hidden.kind == "mission" or hidden.kind == "keep") then
    -- (who is at a place made for a job is the job's business:
    -- Tactical/Assault. And who is at a tower of the pirates' own is the
    -- tower's: Tactical/Keeps.)
    return
  elseif hidden and hidden.kind == "combat" then
    -- (and a stronghold has the worst there is, wherever it is)
    band = if band == "secure" and hidden.depth == 0 then "low" else "lawless"
  elseif hidden and (hidden.kind == "relic" or hidden.kind == "data") and band == "secure" then
    -- (nor a listening post)
    return
  end
  local last = state.spawned[site.id]
  local wait = (if away then RESPAWN * Pirates.AWAY else RESPAWN) / (if surging then Surges.SOONER else 1)
  -- (a place is left alone longer where members of the pilot's
  -- corporation hunt: half as long again for each who fights and is
  -- working in the system. Assets/Members)
  for _, id in state.membership.memberIds do
    local member = state.membership.members[id]
    if member.trade == "fighter" and member.system == me.system and state.tick >= member.refit and member.fleet == 0 then
      wait *= 1.5
    end
  end
  if (last and state.tick - last < wait) or pirateOnGrid(state, me.system, site.id) then
    return
  end
  local rng = Rng.For(state.historySeed, state.tick, site.id, 41)
  state.spawned[site.id] = state.tick
  -- (a gate is not always watched: ask again when it would be due more)
  if camp and not Rng.Chance(rng, CAMPED) then
    return
  end
  local roll = Rng.Next(rng)
  -- (in uncharted space, what its depth brings)
  local deep = math.min(#DEEP, depth)
  local packs: { { any } } = if theirs > 0 then DROWNED[theirs] elseif deep > 0 then DEEP[deep] else PACKS[band]
  local pack: { string } = packs[#packs][2]
  for _, entry in packs do
    roll -= entry[1]
    if roll < 0 then
      pack = entry[2]
      break
    end
  end
  -- (at a homeworld's own belts order is kept best of all: one comes,
  -- never a pack. A new pilot's first belt is one of these, and the ship
  -- a new game gives is no match for two: Character/Proof.spec.)
  if hidden == nil and site.kind == "belt" and state.galaxy.systems[me.system].home and #pack > 1 then
    pack = { pack[1] }
  end
  -- (and now and then, where order is thin or none, a Fence comes with
  -- them, with what they have taken: not with the Drowned, nor to a
  -- stronghold, which has its own)
  local fenced = Pirates.FENCED[band]
  if fenced and theirs <= 0 and not stronghold and Rng.Chance(Rng.For(state.historySeed, state.tick, site.id, 1711), fenced) then
    pack = table.clone(pack)
    table.insert(pack, "fence")
  end
  -- (the Drowned have no veterans and no captains: each is what it is)
  bring(state, me.system, site, band, pack, stronghold and theirs <= 0, rng, away, events,
    if theirs > 0 then 0 elseif deep > 0 then Pirates.DEEP_KEEN[deep] elseif surging then Surges.GRADED else 1)
end

-- Bring a pack to a place for a reason that is somebody else's (a raid
-- on a pilot's tower: Tactical/Raids): the kind of pack the space it is
-- in brings ('band': "secure", "low" or "lawless"), arriving as any
-- does. 'away': the pilot is somewhere else.
function Pirates.Arrive(state: State.State, system: number, site: System.Object, band: string, away: boolean, events: { Event })
  local rng = Rng.For(state.historySeed, state.tick, site.id, 43)
  state.spawned[site.id] = state.tick
  local roll = Rng.Next(rng)
  -- (in uncharted space, what its depth brings, as at a belt there: and
  -- past the pirates' depth the Drowned)
  local depth = state.galaxy.systems[system].depth or 0
  local theirs = math.min(#DROWNED, depth - Galaxy.PIRATE_DEPTH)
  local deep = math.min(#DEEP, depth)
  local packs: { { any } } = if theirs > 0 then DROWNED[theirs] elseif deep > 0 then DEEP[deep] else PACKS[band] or PACKS.low
  local pack: { string } = packs[#packs][2]
  for _, entry in packs do
    roll -= entry[1]
    if roll < 0 then
      pack = entry[2]
      break
    end
  end
  bring(state, system, site, band, pack, false, rng, away, events, if theirs > 0 then 0 elseif deep > 0 then Pirates.DEEP_KEEN[deep] else 1)
end

-- Once a tick: pirates come to where the player is, and to where a
-- hired pilot of theirs is out without them (half as often: nobody
-- hunts a hired hand as they hunt the one who pays). The fight there is
-- fought as any is, whoever is watching.
function Pirates.Populate(state: State.State, events: { Event })
  if state.peaceful then
    return
  end
  local me = state.balls[state.player.ship]
  if me and me.grid ~= 0 and Ships.byId[state.ships[me.id].type].class ~= "capsule" then
    populate(state, me, false, events)
  end
  for _, id in state.fleetIds do
    local ball = state.balls[state.fleet[id].ship]
    if ball and ball.grid ~= 0 and not (ball.warp and ball.warp.stage == "warp")
      and (me == nil or me.system ~= ball.system or me.grid ~= ball.grid) then
      populate(state, ball, true, events)
    end
  end
end

local function give(state: State.State, command: State.Command, events: { Event }): boolean
  local combat = command.kind == "LockTarget" or command.kind == "ActivateModule" or command.kind == "DeactivateModule"
    or command.kind == "Cloak" or command.kind == "Uncloak"
  if combat then
    if Combat.Validate(state, command) then
      Combat.Apply(state, command, events)
      return true
    end
  elseif Space.Validate(state, command) then
    Space.Apply(state, command, events)
    return true
  end
  return false
end

-- The rig a job is to hold at a place, or the tender it is to see
-- through there, or in to its station (Tactical/Assault's defence job,
-- seen here by the state alone), if it is there: its ball.
local function ward(state: State.State, system: number, grid: number): State.Ball?
  for _, id in state.missionIds do
    local mission = state.missions[id]
    local here = mission.site == grid or (mission.aim == "convoy" and mission.to == grid)
    if mission.kind == "assault" and (mission.aim == "hold" or mission.aim == "escort" or mission.aim == "convoy") and here then
      local rig = state.balls[mission.mark]
      if rig and rig.system == system and rig.grid == grid then
        return rig
      end
    end
  end
  -- (and a pilot's tower that somebody has come to bring down: what
  -- stands for it there, unless it has sealed itself. Tactical/Raids)
  local tower = state.starbases[grid]
  if tower and tower.siege > 0 and not (tower.sealed ~= 0 and state.tick < tower.sealed) then
    local core = state.balls[tower.core]
    if core and core.system == system and core.grid == grid then
      return core
    end
  end
  return nil
end

-- Whether a ship is mending another: it has something running on
-- somebody that is for a friend's shield or armour.
local function mending(state: State.State, ball: State.Ball): boolean
  for _, running in ball.vitals.running do
    local item = state.items[running.item]
    local module = if item then Modules.byId[item.type] else nil
    if module and running.target ~= 0 and Modules.Mends(module) then
      return true
    end
  end
  return false
end

-- What a ship has left to lose: its shield, armour and hull together.
local function left(ball: State.Ball): number
  return ball.vitals.shield + ball.vitals.armor + ball.vitals.hull
end

-- What a pirate here would go for, of the ships of the pilot's side
-- (their own, or a hired pilot's) that are worth shooting: whoever is
-- mending the others, and failing that whoever has least left to lose.
-- It is the same answer for every pirate of a pack, so a pack shoots at
-- one thing. One pirate in three goes for a drone instead when any are
-- out (the nearest to it), and any of them does when there is nothing
-- else.
local function pickPrey(state: State.State, ball: State.Ball): State.Ball?
  -- A ship of a faction's force at a front (Tactical/Fronts) goes for
  -- the ships of the other force there: whichever has least left to
  -- lose. The pilot's side is nothing to it, unless they have fired on
  -- its side there: then one such ship in two goes for them instead.
  -- (And a ship that fights for the pilot's side, a member of their
  -- corporation in their own ship, goes for the pirates there too:
  -- Tactical/Fellows.)
  local own = state.pilots[ball.id]
  if own and own.side then
    local foe: State.Ball?, has = nil, math.huge
    for _, id in state.pilotIds do
      local other, theirs = state.pilots[id], state.balls[id]
      local against = if other.side then other.side ~= own.side
        else own.side == "player" and state.ships[id] ~= nil and state.ships[id].owner == "pirates"
      if against and theirs and theirs.system == ball.system and theirs.grid == ball.grid
        and left(theirs) < has then
        foe, has = theirs, left(theirs)
      end
    end
    if not (own.foe and (foe == nil or ball.id % 2 == 0)) then
      return foe
    end
  end
  local best: State.Ball?, least, mends = nil, math.huge, false
  local drone: State.Ball?, droneLeast = nil, math.huge
  local pod: State.Ball? = nil
  local lawless = state.ships[ball.id].owner == "pirates"
    and Galaxy.Band(state.galaxy.systems[ball.system].security) == "lawless"
  local function consider(other: State.Ball?, small: boolean)
    -- (what is cloaked is not there to be gone for, nor what a station's
    -- field stands in front of: Tactical/Fields)
    if other == nil or other.system ~= ball.system or other.grid ~= ball.grid or Combat.Cloaked(state, other.id)
      or Fields.Between(state, ball, other :: any) then
      return
    end
    if small then
      local far = Space.Distance(other :: any, ball :: any)
      if far < droneLeast then
        drone, droneLeast = other, far
      end
    elseif Ships.byId[state.ships[other.id].type].class == "capsule" then
      -- (a capsule, where no law is kept, is a pirate's when there is
      -- nothing better there: the owner, 2026-11-22)
      if lawless and pod == nil then
        pod = other
      end
    else
      local has, tends = left(other), mending(state, other)
      if best == nil or (tends and not mends) or (tends == mends and (has < least or (has == least and other.id < best.id))) then
        best, least, mends = other, has, tends
      end
    end
  end
  consider(state.balls[state.player.ship], false)
  for _, id in state.fleetIds do
    consider(state.balls[state.fleet[id].ship], false)
  end
  -- (and, to a pirate, the corporation's members, each in their own
  -- ship: Tactical/Fellows. Not to a patrol or the police, who are after
  -- a pilot for what the pilot did: a member answers for themselves.)
  if state.ships[ball.id].owner == "pirates" then
    for _, id in state.membership.memberIds do
      consider(state.balls[state.membership.members[id].ship], false)
    end
  end
  for _, id in state.droneIds do
    if state.ships[id] and state.ships[id].owner == "player" then
      consider(state.balls[id], true)
    end
  end
  -- Where a job is to hold a rig, two pirates in three go for the rig,
  -- and any of them does with nobody else to go for.
  -- (by a roll of its own for each: a pack's ids go in step, and would all choose alike)
  local rig = ward(state, ball.system, ball.grid)
  if rig and (best == nil or Rng.Chance(Rng.For(state.historySeed, ball.id, 61), 2 / 3)) then
    return rig
  end
  if drone and (best == nil or Rng.Chance(Rng.For(state.historySeed, ball.id, 53), 1 / 3)) then
    return drone
  end
  -- A station's batteries stand outside its field and fire on a pirate
  -- (Tactical/Batteries, seen here by the state alone): one pirate in
  -- three goes for the nearest of them, and any does with nobody else
  -- to go for.
  if state.ships[ball.id].owner == "pirates" and state.batteries.station == ball.grid
    and (best == nil or Rng.Chance(Rng.For(state.historySeed, ball.id, 71), 1 / 3)) then
    local gun: State.Ball?, near = nil, math.huge
    for _, standing in state.batteries.balls do
      local other = state.balls[standing]
      if other and Space.Distance(other :: any, ball :: any) < near then
        gun, near = other, Space.Distance(other :: any, ball :: any)
      end
    end
    if gun then
      return gun
    end
  end
  -- Pirates rob the trade (Strategic/Commerce: the haulers a pilot sees
  -- carry what the economy sends along the lanes). A pirate with nobody
  -- of the pilot's to go for goes for a hauler on its grid, the nearest;
  -- and one in three does while there is somebody. What it destroys is
  -- in the wreck, and the system it was for goes without.
  if best == nil or Rng.Chance(Rng.For(state.historySeed, ball.id, 67), 1 / 3) then
    local hauler: State.Ball?, near = nil, math.huge
    for _, id in state.trafficIds do
      local record, other = state.traffic[id], state.balls[id]
      if (record.kind == "in" or record.kind == "out") and other and other.system == ball.system and other.grid == ball.grid
        and not (other.warp and other.warp.stage == "warp") and not Fields.Between(state, ball, other :: any) then
        local far = Space.Distance(other :: any, ball :: any)
        if far < near then
          hauler, near = other, far
        end
      end
    end
    if hauler then
      return hauler
    end
  end
  return best or pod
end

-- Whoever on a ship's grid is after anybody of the pilot's side (or
-- after the rig a job of the pilot's is to hold there), the nearest to
-- that ship first: what its drones and its fleet go for when nothing
-- has been pointed out to them. 0 for nobody.
function Pirates.Hunting(state: State.State, near: State.Ball): number
  local best, least = 0, math.huge
  -- (and whoever is after the rig a job of the pilot's is to hold here)
  local rig = ward(state, near.system, near.grid)
  for _, id in state.pilotIds do
    local other = state.balls[id]
    local prey = state.ships[state.pilots[id].prey]
    -- (or after a member of the pilot's corporation: Tactical/Fellows)
    if other and prey and (prey.owner == "player" or prey.owner == "member" or (rig ~= nil and prey.id == rig.id))
      and other.system == near.system
      and other.grid == near.grid then
      local far = Space.Distance(other :: any, near :: any)
      if far < least then
        best, least = id, far
      end
    end
  end
  return best
end

-- Whether a place is part of a job's camp, or where a job has pirates
-- come (Tactical/Assault, seen here by the state alone): those who are
-- there are there for the job, and see it through.
local function camped(state: State.State, home: number): boolean
  for _, id in state.missionIds do
    local mission = state.missions[id]
    if mission.kind == "assault" and (mission.site == home or mission.to == home or table.find(mission.rooms, home) ~= nil) then
      return true
    end
  end
  return false
end

-- A pirate is gone from the game, ship and all: it went away, or got
-- away.
local function gone(state: State.State, id: number, ball: State.Ball, reason: string, events: { Event })
  Space.RemoveBall(state, ball)
  for _, item in Items.In(state, id, nil) do
    Items.Take(state, item, item.quantity)
  end
  state.ships[id] = nil
  State.RemoveId(state.shipIds, id)
  state.pilots[id] = nil
  State.RemoveId(state.pilotIds, id)
  table.insert(events, { kind = "BallRemoved", ball = id, reason = reason })
end

-- Where a pirate that breaks off makes for: whatever of the system's
-- planets and its sun is farthest from where it is.
local function refuge(state: State.State, ball: State.Ball): number
  local best, most = 0, 0
  for _, object in Space.Describe(state, ball.system).objects do
    if object.kind == "planet" or object.kind == "sun" then
      local far = Space.Distance(object :: any, ball :: any)
      if far > most then
        best, most = object.id, far
      end
    end
  end
  return best
end

-- The station on a pirate's grid whose field somebody it would go for
-- is inside (the pilot, their hired pilots, the members of their
-- corporation), with the pirate outside it: nil if there is none.
local function sheltering(state: State.State, ball: State.Ball): System.Object?
  local field = Fields.Of(state, ball.grid)
  if field == nil or Fields.Within(field, ball :: any) then
    return nil
  end
  local function inside(other: State.Ball?): boolean
    return other ~= nil and other.system == ball.system and other.grid == ball.grid and Fields.Within(field, other :: any)
      and Ships.byId[state.ships[other.id].type].class ~= "capsule"
  end
  if inside(state.balls[state.player.ship]) then
    return field
  end
  for _, id in state.fleetIds do
    if inside(state.balls[state.fleet[id].ship]) then
      return field
    end
  end
  for _, id in state.membership.memberIds do
    if inside(state.balls[state.membership.members[id].ship]) then
      return field
    end
  end
  return nil
end

-- Each pirate decides what to do this tick.
function Pirates.Think(state: State.State, events: { Event })
  local player = state.balls[state.player.ship]
  for _, id in table.clone(state.pilotIds) do
    local pilot = state.pilots[id]
    local ball = state.balls[id]
    if ball == nil then
      continue
    elseif ball.warp and ball.warp.stage == "warp" then
      -- (one that broke off is in warp, and away: nobody sees it again)
      if pilot.fleeing then
        local name = state.ships[id].name
        -- (in the log of the fight it left, if that is one the pilot was not at)
        Battles.Fled(state, ball.system, pilot.home)
        gone(state, id, ball, "fled", events)
        table.insert(events, { kind = "PirateFled", ball = id, name = name, system = ball.system, grid = pilot.home })
      end
      continue
    end

    -- Prey: a ship of the pilot's side, if one is here and worth shooting.
    local prey: State.Ball? = state.balls[pilot.prey]
    if prey == nil or prey.system ~= ball.system or prey.grid ~= ball.grid or Combat.Cloaked(state, prey.id)
      or Fields.Between(state, ball, prey :: any) then
      prey = pickPrey(state, ball)
      pilot.prey = if prey then prey.id else 0
    elseif state.ships[prey.id] and state.ships[prey.id].owner == "player" and state.drones[prey.id] == nil
      and not mending(state, prey) then
      -- (and whoever begins to mend the others is gone for, by whoever
      -- is on a ship that is not mending anybody)
      local call = pickPrey(state, ball)
      if call and call.id ~= prey.id and mending(state, call) then
        prey = call
        pilot.prey = call.id
      end
    end

    -- Leave if nobody has been here for a while. (Those a job is to
    -- clear out of their camp stay in it: Tactical/Assault.)
    local kept = state.sites[pilot.home]
    -- (a pilot inside a station's field is nobody to those it keeps
    -- out: with nothing there they can shoot at, they go. Tactical/Fields)
    local company = prey ~= nil
      or (player ~= nil and player.system == ball.system and player.grid == ball.grid and not Fields.Between(state, ball, player :: any))
      or (kept ~= nil and (kept.kind == "mission" or kept.kind == "keep") and not kept.gone)
    pilot.alone = if company then 0 else pilot.alone + 1
    if pilot.alone > PATIENCE then
      gone(state, id, ball, "left", events)
      continue
    end

    -- One that came under its hull's own cloak (the Drowned's) closes
    -- on its prey unseen, and comes out of it when it is near enough to
    -- fight. With nobody to go for it lies where it is, under it.
    if ball.vitals.cloaked then
      if prey and Space.Gap(ball :: any, prey :: any) <= pilot.range * Pirates.AMBUSH then
        give(state, { kind = "Uncloak", actor = id }, events)
      else
        if prey and not (ball.mode == "approach" and ball.target == prey.id) then
          give(state, { kind = "Approach", actor = id, target = prey.id, range = pilot.range }, events)
        end
        continue
      end
    end

    -- Breaking off. One on its way out goes on with it, unless it has
    -- been held: then it is in the fight again, and tries again when it
    -- can. One with the nerve for it, badly hurt, turns for somewhere
    -- far off and warps (which is refused while its warp is disrupted).
    -- Nobody leaves a camp or a tower they are there to defend.
    if pilot.fleeing then
      if ball.warp then
        continue
      end
      pilot.fleeing = nil
    end
    local v = ball.vitals
    local defending = (kept ~= nil and (kept.kind == "mission" or kept.kind == "keep")) or camped(state, pilot.home)
    if pilot.nerve and not defending and left(ball) < pilot.nerve * (v.shieldMax + v.armorMax + v.hullMax) then
      local to = refuge(state, ball)
      if to ~= 0 and give(state, { kind = "WarpTo", actor = id, target = to, range = 0 }, events) then
        pilot.fleeing = true
        -- (and whatever was driving it harder is switched off: a ship
        -- is in warp the sooner for not having so far to get up to)
        for _, running in table.clone(ball.vitals.running) do
          local item = state.items[running.item]
          if item and Modules.byId[item.type].boost and not running.stopping then
            give(state, { kind = "DeactivateModule", actor = id, item = item.id }, events)
          end
        end
        table.insert(events, { kind = "PirateFleeing", ball = id, name = state.ships[id].name, system = ball.system, grid = ball.grid })
        continue
      end
    end

    if prey == nil then
      -- Somebody a pirate would go for has gone into the field of the
      -- station here, where it cannot follow and cannot lock them: it
      -- turns on the tower (the owner's ruling, 2026-11-14), circling
      -- the field and firing on what it is hung on. Nobody's tower but
      -- a pilot's own takes any harm from it (that one is gone for as
      -- 'ward' says, above), so it is a show of temper: with nothing
      -- else there to shoot at, it has gone by the time its patience has.
      local tower = if state.ships[id].owner == "pirates" then sheltering(state, ball) else nil
      if tower then
        if ball.maxVelocity > 0 and pilot.range > 0 and not (ball.mode == "orbit" and ball.target == tower.id and ball.range == pilot.range) then
          give(state, { kind = "Orbit", actor = id, target = tower.id, range = pilot.range }, events)
        end
        local locked, targeted = false, false
        for _, lock in ball.vitals.locks do
          if lock.target == tower.id then
            targeted, locked = true, lock.locked
          end
        end
        if not targeted then
          give(state, { kind = "LockTarget", actor = id, target = tower.id }, events)
        elseif locked then
          for _, item in Items.Fitted(state, id) do
            if Modules.byId[item.type].weapon then
              give(state, { kind = "ActivateModule", actor = id, item = item.id, target = tower.id }, events)
            end
          end
        end
        continue
      end
      if ball.mode ~= "stop" then
        give(state, { kind = "Stop", actor = id }, events)
      end
      continue
    end

    -- (what a camp is built of stands where it was put; and with the
    -- vapour between them, whoever fights from far off comes in close:
    -- Tactical/Vapour)
    local range = if Vapour.Between(state, ball, prey) then math.min(pilot.range, Vapour.CLOSE) else pilot.range
    -- (a pilot's tower stands in the middle of its field, which keeps a
    -- pirate out: it is circled at the field, and shot at from there.
    -- Tactical/Fields)
    local circle = prey.id
    local field = Fields.Of(state, ball.grid)
    local stood = if field then state.starbases[field.id] else nil
    if field and stood and stood.core == prey.id then
      circle = field.id
    end
    -- (and one that lies where it was put, a Hoard at its tower, stays there)
    if ball.maxVelocity > 0 and pilot.range > 0 and not (ball.mode == "orbit" and ball.target == circle and ball.range == range) then
      give(state, { kind = "Orbit", actor = id, target = circle, range = range }, events)
    end
    local locked = false
    local targeted = false
    for _, lock in ball.vitals.locks do
      if lock.target == prey.id then
        targeted = true
        locked = lock.locked
      end
    end
    if not targeted then
      give(state, { kind = "LockTarget", actor = id, target = prey.id }, events)
    end
    -- Everything it has for another ship: its guns, and what holds the
    -- prey where it is (each is refused until it is in reach). What it
    -- has for itself, from the moment it has somebody to fight: an
    -- afterburner, or anything else that runs on its own ship. And what
    -- it has for its own side: a remote repairer goes on whoever of the
    -- pack is worst hurt (Tactical/Mend).
    local mends = false
    local on: { [number]: boolean } = {}
    for _, running in ball.vitals.running do
      on[running.item] = true
    end
    for _, item in Items.Fitted(state, id) do
      local module = Modules.byId[item.type]
      if module.hex and Modules.Mends(module) then
        mends = true
      elseif locked and (module.weapon or module.hex or module.pylon) then
        give(state, { kind = "ActivateModule", actor = id, item = item.id, target = prey.id }, events)
      elseif module.boost and Pirates.Drives(module) then
        -- (burnt to get there, and let go once it is there. Not by
        -- those of a job's camp or a tower, who come on at their own
        -- speed: the jobs are measured against that, level by level.)
        local far = if circle ~= prey.id then Fields.Gap(state, ball, prey :: any) else Space.Distance(prey :: any, ball :: any)
        if defending then
          continue
        elseif far > range + Pirates.BURN and not on[item.id] then
          give(state, { kind = "ActivateModule", actor = id, item = item.id }, events)
        elseif far < range + Pirates.COAST and on[item.id] then
          give(state, { kind = "DeactivateModule", actor = id, item = item.id }, events)
        end
      elseif (module.boost or module.repair or module.pds) and not on[item.id] then
        give(state, { kind = "ActivateModule", actor = id, item = item.id }, events)
      end
    end
    if mends then
      local pack: { number } = {}
      for _, other in state.pilotIds do
        if state.ships[other] and state.ships[other].owner == state.ships[id].owner then
          table.insert(pack, other)
        end
      end
      Mend.Tend(state, ball, pack, events)
    end
  end
end

return Pirates
