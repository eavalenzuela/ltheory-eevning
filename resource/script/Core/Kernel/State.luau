--!strict
-- The game state: one tree of plain data (docs/design/core.md). Everything
-- the rules know is in here, and nothing else is consulted, so the state
-- is the save and its hash identifies it.

local Economy = require("@lt/Core/Strategic/Economy")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Motion = require("@lt/Core/Tactical/Motion")
local System = require("@lt/Core/Describe/System")

local State = {}

-- A ship as a thing that exists: docked or in space. While it is in space
-- it also has a Ball with the same id.
export type Ship = {
  id: number,
  type: string,     -- Data/Ships id
  name: string,
  owner: string,    -- "player", or the faction that flies it
  docked: number,   -- station id, or 0 in space
  -- The citadel it is tethered to, too big to dock there (Assets/
  -- Starbases): nil when it is not.
  tether: number?,
  -- Armour and hull points missing. Damage stays with a ship until it is
  -- repaired; shields and capacitor refill by themselves.
  armorDamage: number,
  hullDamage: number,
  -- The hired pilot who flies it (Tactical/Fleet), by their id; 0 for
  -- a ship the player flies themselves, or that nobody does.
  pilot: number,
  -- The tick its jump drive last fired, if it has one and it has
  -- (Tactical/Jumping): the drive cools from then.
  jumped: number?,
  -- True for a ship a station gave for nothing: the one a pilot begins
  -- in, and the one a pilot with none wakes in. Lost, it pays no more
  -- than the plainest hull would (Tactical/Aftermath), or losing what
  -- cost nothing would be a living.
  given: boolean?,
  -- What it is painted in, and the design laid on that (Data/Paints,
  -- Assets/Paintwork): nothing, for a ship as it left the yard.
  paint: string?,
  design: string?,
}

-- A target being locked, or locked. Times are game seconds (tick * TICK).
export type Lock = { target: number, done: number, locked: boolean }

-- A module that is switched on. It cycles at 'next', again and again
-- until told to stop, it runs out of what it needs, or loses its target.
export type Running = {
  item: number,       -- the fitted module
  target: number,     -- 0 for modules that act on their own ship
  next: number,       -- game seconds of its next cycle
  stopping: boolean,  -- stop at the next cycle
  cycles: number,     -- how many it has run, for the dice
}

-- A ship's condition and what bears on a fight. The maxima and
-- resonances come from hull and fit (Core/Attributes) and are refreshed when a
-- module that changes them starts or stops.
export type Vitals = {
  shield: number,
  armor: number,
  hull: number,
  -- What a tracking disruptor, a guidance disruptor and a remote sensor
  -- booster on it make of its turrets' tracking and reach, its
  -- missiles' flight, and its sensors (Tactical/Combat): nil for 1.
  track: number?,
  guide: number?,
  sensor: number?,
  -- The command bursts of others its owner's that reach it (their module
  -- ids, Tactical/Combat), and whether a module of its own roots it to
  -- the spot (Tactical/Vitals): module expansion, 2026-11-16.
  bursts: { string }?,
  rooted: boolean?,
  -- What it has taken of each kind of damage since an adaptive hardener
  -- of its last looked (Tactical/Combat); nil until it has taken any.
  taken: { number }?,
  capacitor: number,
  shieldMax: number,
  armorMax: number,
  hullMax: number,
  capacitorMax: number,
  shieldRecharge: number,
  capacitorRecharge: number,
  -- The share of its armour, and of its hull, a hull that mends by
  -- itself gets back each second (the Nimia's: Tactical/Combat). Nil or
  -- 0 for a hull that does not.
  armorMend: number?,
  hullMend: number?,
  signature: number,
  scanResolution: number,
  lockRange: number,
  maxTargets: number,
  shieldResonance: { number },
  armorResonance: { number },
  hullResonance: { number },
  -- What other ships are doing to it (Tactical/Combat): its top speed
  -- is 'entangle' of what it would be (1: nobody has an entanglement
  -- projector on it), and 'scrambled' keeps it out of warp.
  entangle: number,
  scrambled: boolean,
  -- (and its signature is 'paint' times what it would be, and its lock
  -- range and scan resolution 'damp' of what they would be: 1 for nobody)
  paint: number,
  damp: number,
  locks: { Lock },          -- in the order they were asked for
  running: { Running },     -- in the order they were switched on
  -- Its hull's own cloak is on: a hull with one built in
  -- (Tactical/Combat). Nil for off, and for every other hull.
  cloaked: boolean?,
  -- Its hull's own gun (a gun fixed along the bow: Tactical/Combat):
  -- what it has been told to fire at, and is aligning to (nil: nothing),
  -- and the tick it will next be ready to fire at (nil: it is).
  spinalTarget: number?,
  spinalReady: number?,
}

-- A missile in flight: it lands at 'impact' and does its damage then.
export type Missile = {
  from: number,
  to: number,
  item: number,
  charge: string,
  damage: { number },
  impact: number,
  -- How wide its blast is, as a share of the missile's own: what its
  -- launcher, a flight computer and its pilot's fusing made of it when
  -- it was fired. (Nil: as the missile is.)
  blast: number?,
}

-- A stack of items of one type in one place. A fitted module is a stack
-- of one, in a rack ("high", "mid" or "low") at a slot.
export type Item = {
  id: number,
  type: string,       -- Data/Types id
  quantity: number,
  holder: number,     -- the ship it is in or on, or the station whose hangar it is in
  -- ("dronebay" is a ship's drone bay: Tactical/Drones. "corporate" is
  -- the hangar the pilot's corporation has at a station, beside the
  -- pilot's own: Assets/Corporation)
  -- ("shipbay" is the bay for packed hulls of a hull that carries ships:
  -- a logistics capital's, Data/Ships)
  place: "hangar" | "corporate" | "cargo" | "dronebay" | "orehold" | "shipbay" | "high" | "mid" | "low" | "rig",
  slot: number,       -- within its rack, from 1; 0 unless fitted
  -- An adaptive armour hardener's share of resistance for each kind, as
  -- it has shifted (Data/Modules' 'adaptive'); nil: evenly.
  adapt: { number }?,
  charge: string,     -- for a fitted weapon: the charge type loaded, or ""
  rounds: number,     -- and the shots left in the clip
}

-- What a ship means to do when it gets within range of 'target'.
export type Intent = { kind: "dock" | "jump", target: number }

export type Warp = {
  stage: "align" | "warp",
  target: number,     -- the body warped to, for the record
  tx: number,         -- the point it will arrive at
  ty: number,
  tz: number,
  -- set on entering warp:
  startTick: number,
  fx: number,         -- where it entered warp
  fy: number,
  fz: number,
  ux: number,         -- unit direction of travel
  uy: number,
  uz: number,
  plan: Motion.WarpPlan?,
  -- A fleet's warp (Tactical/Fleet): 'gang' is the ship that called it
  -- (its own id, on that ship), and those who go with it wait for one
  -- another before they go, and go at one speed. On the ship that called
  -- it: 'called' is the tick it did, and 'expect' how many are to go
  -- with it.
  gang: number?,
  called: number?,
  expect: number?,
}

export type Mode = "stop" | "goto" | "approach" | "orbit" | "keep" | "align"

-- A ship in space. Positions are metres in system space, star at the
-- origin; velocities m/s.
export type Ball = {
  id: number,
  kind: "ship",
  name: string,
  system: number,
  grid: number,       -- the grid it is on; 0 while in warp
  x: number,
  y: number,
  z: number,
  vx: number,
  vy: number,
  vz: number,
  -- The velocity it steers toward until the next tick, decided at this
  -- one. With position and velocity it fixes the coming second of flight
  -- exactly (Motion.Step), which is what lets the view draw between ticks.
  tvx: number,
  tvy: number,
  tvz: number,
  radius: number,
  maxVelocity: number,
  tau: number,        -- seconds; see Tactical/Motion
  warpSpeed: number,  -- AU/s
  mode: Mode,
  target: number,     -- for approach, orbit, keep; else 0
  range: number,      -- metres between surfaces, for the same
  dx: number,         -- goto, align: unit direction. orbit: unit normal of
  dy: number,         -- the orbit's plane
  dz: number,
  warp: Warp?,
  intent: Intent?,
  vitals: Vitals,
}

-- An interdiction field: where it is, how wide, whose, and the tick it goes.
export type Bubble = { id: number, system: number, grid: number, x: number, y: number, z: number, radius: number, owner: string,
  expires: number }

-- What is left of a destroyed ship: it stays where the ship died, holds
-- whatever survived (as items whose holder is the wreck), and fades.
export type Wreck = {
  id: number,
  kind: "wreck",
  name: string,
  system: number,
  grid: number,
  x: number,
  y: number,
  z: number,
  radius: number,
  hull: string,       -- the Data/Ships id of the ship it was ("" in a save from before this was kept)
  expires: number,    -- the tick it disappears
  salvaged: boolean,  -- a salvager has had what the hull itself was worth
  can: boolean?,      -- a container a pilot put out, and no wreck of anything (Tactical/Aftermath)
  locked: boolean,    -- its hold is sealed: nothing is looted until it has been hacked (Tactical/Hacking)
  lock: string,       -- the kind of lock that seals it ("": a hold's; "vault": Tactical/Hacking)
}

-- A hack under way (Tactical/Hacking): the hull whose hold it is for;
-- the lock's matrix, 'size' by 'size' (its codes row by row, and which
-- of its cells have been picked); the buffer (the codes picked, in
-- order) and the room it has; the keys (each a run of codes, and
-- whether it is in the buffer yet); and where the next pick has to be:
-- 'along' a "row" or a "column", and which 'line' of those.
export type HackKey = { name: string, codes: { string }, done: boolean }
-- Something going on in the galaxy that a pilot could go to
-- (Strategic/Happenings): pirates massing in a system, a force come out
-- of a wormhole to take one, something rare seen for an hour or two, a
-- place struck by luck good or bad. 'kind' is which of those ("surge",
-- "invasion", "sighting", "disaster", "windfall") and 'what' which of
-- its kind. 'system' is where, and 'place' the station, gate or site of
-- it that it is at (0 for the whole system, or for a place that is not
-- made until the pilot comes). 'began' and 'ends' are ticks. 'strength'
-- is how much of it there is left, 'stage' how far it has got, 'kills'
-- what has been destroyed of it where the pilot was, and 'name' what it
-- is called, if it has a name of its own. 'ref' is another thing it
-- turns on, by its number, where it has one: the ship a sighted captain
-- flies, the system a closed gate leads to.
export type Happening = {
  id: number,
  kind: string,
  what: string,
  system: number,
  place: number,
  began: number,
  ends: number,
  strength: number,
  stage: number,
  kills: number,
  name: string,
  ref: number?,
}

-- What a happening has left behind it for a few days: a system's order
-- thinner or firmer than it was. 'was' is the security it had, 'now'
-- what it was made (if it is anything else when the time comes,
-- somebody else has changed it since, and it is left alone), 'ends' the
-- tick it is put back, and 'why' the kind of happening that left it.
export type Aftermath = { system: number, was: number, now: number, ends: number, why: string }

-- Everything that is going on (Strategic/Happenings): those on now, the
-- oldest first; how many there have ever been; how near each charted
-- system is to a surge, 0 to 1, by the system's number; what has been
-- left behind; how many times the pressure has been worked out; and
-- the tick each of the kinds that come by the clock is next due.
export type Happenings = {
  list: { Happening },
  count: number,
  pressure: { number },
  marks: { Aftermath },
  steps: number,
  version: number,
  sightingDue: number,
  placeDue: number,
  invasionDue: number,
}

-- A booster at work on the pilot (Data/Boosters), the tick it wears
-- off at, and whether it sat badly: its ill effect is at work too.
export type Boosted = { type: string, ends: number, wrong: boolean }

-- ('ends': the tick a lock on a clock runs out at; 0 for one that is
-- not on a clock, or not begun)
export type Hack = { wreck: number, size: number, cells: { string }, used: { boolean }, buffer: { string }, room: number,
  keys: { HackKey }, along: string, line: number, ends: number }

-- A ship flown by the game rather than the player: what it is doing.
export type Pilot = {
  ship: number,
  range: number,      -- how far from its prey it likes to fight
  prey: number,       -- the ship it is after, or 0
  home: number,       -- the grid it was spawned on
  alone: number,      -- ticks since the player was last on its grid
  bounty: number,     -- credits paid to whoever kills it
  tags: number,       -- pirate tags its wreck holds
  -- How it fights (Tactical/Pirates): the share of itself it has to be
  -- down to before it breaks off and warps away (nil: it never does),
  -- and whether it is on its way out now.
  nerve: number?,
  fleeing: boolean?,
  -- A ship of a faction's force at a front (Tactical/Fronts): the
  -- faction it fights for, what it is worth of the force's strength,
  -- and whether the pilot's side is its enemy too (they fired on its
  -- side there).
  side: string?,
  worth: number?,
  foe: boolean?,
}

-- A front: an operation of the factions' (Strategic/Wars) as a place in
-- the system the pilot is in, and, while the pilot is at it ('shown'),
-- as ships. 'ships' are those there now, by id: whose side each is on,
-- what it is worth, and whether it is of the force that came (or of the
-- defence). 'reserve' and 'held' are what each force has beyond its
-- ships; 'away' counts the ticks since the pilot left the place; and
-- 'crossed' are the sides the pilot has fired on there.
export type Front = { operation: number, system: number, site: number, shown: boolean,
  ships: { [number]: { side: string, worth: number, attacking: boolean } }, reserve: number, held: number, away: number,
  crossed: { [string]: boolean },
  -- (what the defence was worth when it was last reckoned: what it is
  -- worth more than that since has been sent to its relief, and is its)
  last: number? }

-- A ship of the traffic: a hauler coming "in" to dock at 'goal' or going
-- "out" to the gate 'goal', a "patrol" on station at 'goal', a "miner"
-- at the belt 'goal' (going "home" to the station 'goal' when it has
-- done), or one of the "police" come for a marked pilot. It
-- belongs to the system it was made in, and 'wait' counts its last
-- moments at a gate.
-- A hauler that carries part of what the economy has sent along a
-- lane (Strategic/Commerce) has it in its hold, and 'carries' says
-- whose it is: the system it is owed to (the node, in the economy), the
-- class of the goods and how many. It is put back in that system's
-- stock when the hauler gets where it is going, and never if it does
-- not.
export type Traffic = { ship: number, kind: string, goal: number, system: number, born: number, wait: number,
  carries: { node: number, class: number, amount: number }? }

-- A grid that is not anchored to a station, gate or belt: made where a
-- ship arrived in open space (those anchored to a site use the site's id).
export type Grid = { id: number, system: number, x: number, y: number, z: number }

export type Command = {
  kind: string,
  actor: number,
  target: number?,
  range: number?,
  x: number?,
  y: number?,
  z: number?,
  item: number?,      -- the item acted on
  other: number?,     -- a second item (the charge, when loading a weapon)
  quantity: number?,
  to: string?,        -- "cargo", "hangar", "corporate", "dronebay", "orehold" or "shipbay"; for an order, "buy" or "sell"
  type: string?,      -- an item type, when there is no item yet (buying)
  price: number?,     -- credits per unit, for a limit order
  order: number?,     -- an order's id
  what: string?,      -- what a colony's facility is set on or set to make
  pin: number?,       -- a colony's facility, by its number there
  hours: number?,     -- the length of an extractor's programme
  pilot: number?,     -- a hired pilot, by their id
  stops: { number }?, -- for a haul: the further stations to collect at, in order
  drops: { number }?, -- and the further stations to carry to, a load to each in turn
  station: number?,   -- the station a thing is done at from afar (a contract's)
  -- (SetAccess: whether a citadel is open to others, and its tax)
  open: boolean?,
  tax: number?,
}

-- A standing offer at a station's market. A sell order's goods and a buy
-- order's credits are held in escrow until it fills or is cancelled.
export type Order = {
  id: number,
  station: number,
  side: "buy" | "sell",
  type: string,
  quantity: number,   -- still to fill
  price: number,      -- credits per unit
  placed: number,     -- tick
}

-- A fight the pilot was not at (Tactical/Battles): a hired pilot of
-- theirs attacked at a place, with them somewhere else. Where and when
-- ('ended' is 0 while it goes on), who of the pilot's was there, who
-- came for them (each kind and how many; 'seen' is their ships, so that
-- nobody is counted twice), what of theirs was destroyed, what of the
-- pilot's was lost, how many got away, what it paid, and whether the
-- pilot came to it before it was over.
export type Tally = { name: string, count: number }
export type Fight = {
  id: number,
  system: number,
  grid: number,
  where: string,
  began: number,
  ended: number,
  pilots: { string },
  seen: { number },
  attackers: { Tally },
  destroyed: { Tally },
  lost: { string },
  fled: number,
  bounty: number,
  joined: boolean,
}

-- A lot the pilot has put up on a station's board (Assets/Contracts):
-- so many of a type, for a price in all. The board holds the goods
-- until somebody takes the lot or its time is up.
export type Listing = {
  id: number,
  station: number,
  type: string,
  quantity: number,
  price: number,      -- credits for the lot
  placed: number,     -- tick
  ends: number,       -- tick
}

-- One day of a type at a station: what was traded in it (units, and
-- what they went for in all), and the station's going price when the
-- day ended ('close': nil for the day that is not over yet, and for a
-- day put down before closes were kept). A day is put down when
-- something traded in it or its close is not the close before, so a
-- type nobody has touched has none.
export type TradeDay = { day: number, volume: number, value: number, close: number? }

-- A manufacturing job: it ends at a tick and its product then appears in
-- the hangar of the station it runs at.
export type Job = {
  id: number,
  station: number,
  -- The item the job holds: a blueprint, which its end gives back, or a
  -- copy of one ("copy.<product>": Data/Blueprints), whose runs it has
  -- used.
  blueprint: string,
  runs: number,
  product: string,
  quantity: number,   -- units it will make
  -- "" for a job that builds. For research into its blueprint, what is
  -- being learned: "material" or "time" (it makes nothing). "invent"
  -- for an invention (its product is the blueprint it hopes for), and
  -- "copy" for copying (its product is the copy, a unit a run).
  research: string,
  started: number,
  ends: number,
}

-- A drone that is out of its owner's hold (Tactical/Drones): its own
-- ship, the ship it belongs to, the kind of drone it is (Data/Drones),
-- what it has been pointed at (0: nothing), whether it has been called
-- back, and whether it was near enough its owner, last tick, to be
-- taken aboard if the owner left.
export type Drone = { ship: number, owner: number, type: string, target: number, returning: boolean, near: boolean }

-- A scan probe a pilot has put out (Tactical/Sites): where it is, and
-- the tick it runs down at.
export type Probe = { id: number, system: number, x: number, y: number, z: number, expires: number }

-- A place in space a pilot has marked, to warp back to (Tactical/Space).
export type Bookmark = { id: number, name: string, system: number, x: number, y: number, z: number }

-- How far a pilot has got with a career agent (Character/Careers): the
-- lessons done, whether the next is in hand, and how much of what it
-- wants has been done since it was taken. 'again': what the lesson in
-- hand handed over has been handed over a second time (once is all).
export type Career = { done: number, taken: boolean, count: number, again: boolean }

-- A pilot hired to fly one of the player's ships beside their own
-- (Tactical/Fleet). Every skill counts as 'skill' for a ship they fly.
-- Their wages are paid up to the tick 'paid'. 'ship' is the ship they
-- have been given (0: none). Their 'order' is to "follow" the player,
-- to "stay" docked, or to "mine" the belt 'post' and take the ore to
-- the station 'base' ('hauled' is the units brought in so far); and
-- 'target' is what they have been pointed at. 'experience' is what
-- they have learned toward their next grade.
-- One set to "haul" carries what is of the kind 'cargo' in the pilot's
-- hangar at the station 'post' to the station 'base', a hold at a time
-- ('hauled' counts those units too). One who 'sell's sells what they
-- bring in, mined or carried, where the station has a market, and
-- 'earned' is what that has made.
-- One set to "patrol" holds the place 'post', and goes in to the
-- nearest station to mend when badly hurt. One set to "guard" goes
-- where the hired pilot 'ward' goes (by their id), as the rest go where
-- the player goes. 'alarm' is set while somebody is after them with the
-- player elsewhere: it is what has been said of already.
export type Wingman = {
  id: number, name: string, skill: number, wage: number, paid: number,
  ship: number, order: string, target: number,
  post: number, base: number, hauled: number,
  experience: number,
  cargo: string, sell: boolean, earned: number,
  ward: number, alarm: boolean,
  -- For one set to haul: the stations collected at, in order ('post' is
  -- the first), and how far round them this round has got (the place
  -- in that list of the last one loaded at; 0 before the first).
  stops: { number }, leg: number,
  -- And the further stations carried to, beside 'base': a load goes to
  -- each in turn, 'base' first. 'turn' is whose turn it is (0 for
  -- 'base', then the place in 'drops').
  drops: { number }, turn: number,
  -- For one sent to "buy": the type of thing ('want'), how many of it
  -- are still to be bought ('need'), and the most to pay for one, on
  -- the average of a purchase ('limit'). It is bought at the station
  -- 'post' and brought to the station 'base'.
  want: string, need: number, limit: number,
  -- For one set to keep a thing in "stock" (the same, as a standing
  -- order): how many of it are to be kept in the hangar at 'base'
  -- ('keep'), and the tick before which they do not go again, after a
  -- market that had none for them ('retry').
  keep: number, retry: number,
  -- How they stand toward the pilot, 0 to 100 (Fleet.LOYALTY): it grows
  -- with every day's wage paid, and falls with one that is not and
  -- with a ship lost under them. At nothing, they go.
  loyalty: number,
}

-- A place that is on nobody's chart (Tactical/Sites): 'id' is the place
-- it is in its system's description. 'strength' is how far a scanner
-- has got with it, from 0 to 1 (found); 'gone' is a site that is over.
-- 'depth' is how far along a trail it is (0 for a site that was simply
-- there; 1 for a stronghold a den's records led to), and 'led' whether
-- it has itself been asked where it leads.
export type Site = { id: number, system: number, kind: string, code: string, strength: number, expires: number, gone: boolean,
  depth: number, led: boolean }

-- A glut or a shortage of something in a part of the map (Strategic/
-- Commerce): every system of a constellation wants so many times what
-- it did of one of the goods (more than once: a shortage, and it is
-- dear there; less: a glut, and it is cheap) until the tick it ends.
export type Shock = { id: number, constellation: number, class: number, factor: number, began: number, ends: number }

-- The factions at war (Strategic/Wars). An operation is a force sent
-- to a system: to claim an open one nobody holds, or to besiege a claim
-- of an enemy's ('against': whose, "" for nobody's). 'force' is what is
-- left of what was 'sent', 'defence' what is left of what 'defended'
-- (the garrison, and what was sent to its relief: 'relieved' once that
-- has been). A feud is a war between two: its score is the claims 'a'
-- has taken of 'b', less those 'b' has of 'a'.
export type Operation = { id: number, by: string, system: number, kind: string, began: number, force: number, sent: number,
  against: string, defence: number, defended: number, stage: string, relieved: boolean,
  -- (its forces are ships where the pilot is: Tactical/Fronts. What they
  -- are worth is what is left of each, and no round is reckoned.)
  shown: boolean? }
export type Feud = { a: string, b: string, since: number, score: number }
-- What is between each two factions (by the pair, "a|b" in the order of
-- the letters), the wars there are, the truces (by the pair: the tick
-- each runs out), the open systems that are claimed (by system: whose),
-- the operations going on, what each faction has to send and how weary
-- it is, the tick each last declared a war, and a count of the times a
-- system has changed hands (for whoever draws the map).
-- ('on': whether any of it goes on. In the game it does; a test that is
-- about something else has a galaxy where nobody stirs.)
export type Wars = {
  on: boolean,
  relations: { [string]: number }, feuds: { Feud }, truces: { [string]: number }, claims: { [number]: string },
  operations: { Operation }, strength: { [string]: number }, weary: { [string]: number }, declared: { [string]: number },
  version: number,
  -- (the open systems the pilot is claiming, with a beacon that has not
  -- stood long enough yet: no faction begins a claim of one. Assets/
  -- Sovereignty says which.)
  spoken: { [number]: boolean }?,
}

-- The corporation's members (Assets/Members): pilots who have joined
-- it and do as they see fit. A member has a trade ("miner", "fighter",
-- "hauler" or "scout"), a people (whose hulls they fly), a hull of
-- their own, the tax they will bear, credits of their own, what they
-- have earned and paid in tax in all, the system they are working in
-- and at what, the call they are answering (0: none), the days running
-- their earnings have been thin, and what they have kept today.
export type Member = { id: number, name: string, trade: string, people: string, hull: string, bears: number, wealth: number,
  earned: number, paid: number, joined: number, system: number, doing: string, call: number, lean: number, day: number,
  -- Their ship, where the pilot is to see it (Tactical/Fellows): the
  -- ship (0: none is out), what it is at ("work", "out" on its way to
  -- it, "home" on its way in, "front" at a siege's lines; and with no
  -- ship "rest" in a station, "away" beyond a gate, or ""), the place
  -- that is for, the tick it began, a count of ticks it has waited
  -- there, and the tick before which they do not come out again.
  ship: number, task: string, goal: number, since: number, wait: number, back: number,
  -- What they have lost: the tick until which they are out of work,
  -- finding another ship, and how many ships have gone.
  refit: number, lost: number,
  -- What a hauler's ship has aboard of the economy's, and the system it
  -- is for (as a hauler of the traffic: Tactical/Traffic).
  carries: { node: number, class: number, amount: number }?,
  -- One of the player's own characters, asked in (Character/Characters,
  -- 2026-11-17): its id, and the skills it has, kept up to date when a
  -- game is opened. Nil for anybody else.
  alt: string?, skills: { [string]: number }? }
-- Somebody who would join: who has applied (and waits until a tick), or
-- is open to it at a station today.
export type Applicant = { key: string, name: string, trade: string, people: string, hull: string, bears: number, until_: number }
-- A call the pilot has posted: what for ("defend", "mine", "haul" or
-- "scout"), which system, and the credits a day it pays each member who
-- answers it.
export type Call = { id: number, kind: string, system: number, reward: number, posted: number }
export type Membership = { tax: number, members: { [number]: Member }, memberIds: { number }, applicants: { Applicant },
  calls: { Call }, invited: { string }, invitedDay: number }

-- A wormhole that is open (Tactical/Wormholes): a way between two
-- systems that no gate joins, there for a day or so. 'a' is the place
-- of the end it opened at (a place of its system's description, and a
-- site: a scanner finds it), and 'from' that system; 'to' is the system
-- it leads to, and 'b' the place of the end there, which is 0 until
-- somebody has gone through (the far end is nowhere until then).
-- 'size' is how big a hull it lets through, 1 to 3 (Wormholes.RANK).
-- ('mass': the kilograms of hull that have gone through it, either way:
-- it closes when its size's share is spent (Tactical/Wormholes). Nil
-- for none yet. 'station': the wormhole station that holds it open, if
-- one does.)
export type Wormhole = { id: number, a: number, from: number, b: number, to: number, opened: number, closes: number, size: number,
  code: string, mass: number?, station: number? }

-- A job a station has for a pilot (Assets/Missions): a "bounty" (destroy
-- 'need' pirates in 'system'; 'done' so far), a "courier" run (carry
-- 'need' of 'type' to the station 'to'), or a "supply" order (bring
-- 'need' of 'type' to 'station'). 'key' is the offer it was (station,
-- day and place in the list), and 'id' is 0 until a pilot has taken it.
-- 'agent' is who at the station gives it, and 'loyalty' the points it
-- is worth with their faction beside the pay.
-- An "assault" is on a camp made for it (Tactical/Assault): 'level'
-- is how hard it is, 1 to 4; 'waves' the packs that keep the camp, each
-- a list of the kinds of pirate in it, one coming when the last is
-- destroyed; 'wave' how many have come; and 'site' the place, once the
-- job is taken (0 before, and for any other kind of job).
--
-- A camp is of one room or more: 'ends' says, for each room, which
-- wave is the last that is in it (so { 1, 3 } is a camp of two rooms,
-- the first wave in the first), and 'rooms' are the places, once the
-- job is taken ('site' is the first).
--
-- 'aim' is what the job is to do there: "clear" it ('need' ships, of
-- which 'done' are destroyed), destroy its "chief" ('need' is 1; 'mark'
-- is the chief's ship, once it is out), "fetch" what it took ('need'
-- of 'type', which is in a container that 'mark' is, in the last room),
-- or "raze" it ('need' things it is built of, which stand in the last
-- room once the pilot has been there: 'mark' is the first of them).
--
-- A defence job (the seventh agent's) is an assault to the rules, with
-- the aim "hold": the place is where a rig of the faction's stands
-- ('mark' is the rig's ship, once the pilot has been there), and the
-- waves are those who come for it ('need' ships, of which 'done' are
-- destroyed). Every third such job is an escort, with the aim
-- "escort": 'mark' is a tender, which flies out from the middle of
-- the place, 'need' is 1, and 'done' is 1 when it has got clear. The aim is
-- "lost" from when the rig or the tender is destroyed until the job is
-- ended for it, which is within the tick, and 'type' then says which
-- of the two it was.
--
-- A "mining" contract has a place made for it too: a pocket of rocks of
-- the ore 'type', of which 'need' units are to be brought in ('aim' is
-- "dig"). Its 'waves' are whoever turns up there to dispute it: none,
-- or one pack.
export type Mission = {
  id: number, key: string, kind: string, station: number, faction: string, system: number, need: number, done: number,
  type: string, to: number, reward: number, standing: number, taken: number,
  agent: string, loyalty: number,
  -- (which of its station's agents gives it: 1 to 5; 0 in a save from
  -- before agents had a regard of their own)
  slot: number,
  level: number, waves: { { string } }, wave: number, site: number,
  rooms: { number }, ends: { number }, aim: string, mark: number,
  -- What it pays with in place of credits, where it does: a module of
  -- the people's own make (Data/Modules), put in the hangar of the
  -- station it is handed in at.
  prize: string?,
}

-- What a pilot has researched of a blueprint: levels of each kind.
export type Research = { material: number, time: number }

-- A line in the wallet's journal.
export type Entry = { tick: number, amount: number, reason: string, balance: number }

-- The pilot's corporation (Assets/Corporation): its name ("" until one
-- is founded) and when it was founded, its own credits and their recent
-- history, and all it has earned and spent since (what its founder has
-- paid in and taken out aside).
-- 'books': what has come in (more than nothing) and gone out (less) under
-- each head, by the reason it was posted for: the same credits as
-- 'earned' and 'spent', told apart (Assets/Corporation.HEADS).
export type Corporation = { name: string, founded: number, wallet: number, journal: { Entry }, earned: number, spent: number,
  books: { [string]: number } }

-- A facility of a colony (Assets/Colonies): its number there, what kind
-- it is ("extractor", "processor" or "storage"), and what it is set on
-- (an extractor's raw material) or set to make (a processor's product).
-- An extractor's programme ends at tick 'ends' (0: it has none) and its
-- next cycle is at 'next', 'cycle' cycles in. A processor with a batch
-- in hand delivers it at 'next' (0: it has none).
export type Pin = { id: number, kind: string, what: string, ends: number, next: number, cycle: number }

export type Stored = { type: string, quantity: number }

-- A colony on a planet: whose it is, its facilities, and what its
-- store holds (in the order of the types' ids).
export type Colony = { planet: number, owner: string, pins: { Pin }, pinSeq: number, store: { Stored } }

-- A module anchored at a pilot's starbase: its Data/Structures id, and
-- the tick it is online from.
export type Anchored = { type: string, ready: number }

-- A starbase a pilot has put up (Assets/Starbases). Its tower is a
-- station in its system's description, with this id; here is what a
-- described station has not.
export type Starbase = {
  id: number,
  tower: string,      -- Data/Structures tower id
  owner: string,      -- "player"
  ready: number,      -- the tick its anchoring is done
  fuel: number,       -- fuel blocks aboard
  burnt: number,      -- the tick it last burnt one (or was lit)
  modules: { Anchored },
  -- The tick its drill last brought an hour's worth up out of the moon
  -- (or was last not drilling: it counts from when it can).
  drilled: number,
  -- The tick pirates next come for it (Tactical/Raids; 0: they do not,
  -- where order is kept), and how many times they have.
  raid: number, raids: number,
  -- Its running, since it was anchored: the fuel blocks it has burnt,
  -- the units its drill has brought up, and the units raiders have
  -- carried off.
  used: number, raised: number, robbed: number,
  -- Under fire (Tactical/Raids). 'core' is the ship that stands for it
  -- where it is shot at (0 until it is anchored); 'charges' the
  -- sealing charges aboard; 'sealed' the tick it comes out of being
  -- sealed (0 when it is not); and 'siege' how strong those are who
  -- have come to bring it down, and will be back when it opens (0
  -- when nobody has).
  core: number, charges: number, sealed: number, siege: number,
  -- Its reactor (Data/Reactions): the composite it is set to make (""
  -- for nothing), the tick it last made a batch (or was last not
  -- making one: it counts from when it can), the units it has made
  -- since the tower was anchored, and whether it stood idle last for
  -- want of what the composite is made of.
  reaction: string, reacted: number, composed: number, starved: boolean,
  -- A citadel's (Assets/Starbases): whether ships not its owner's may
  -- dock there (any that are not hostile), and the tax its owner takes
  -- of what is traded and done there, 0 to Starbases.TAX_MOST. Nil for
  -- a tower, and for a citadel closed to others.
  open: boolean?, tax: number?,
  -- A wormhole station's (Tactical/Wormholes): the wormhole it holds open
  -- now. Nil for every other, and for one that has none yet.
  hole: number?,
}

-- A station's batteries, where the pilot is (Tactical/Batteries): they
-- stand outside its field as ships do, while the pilot is there.
-- 'at' is the place last looked at (a station whose batteries do not
-- change is not gone through again each tick), 'station' is whose
-- stand now (0 for nobody's), 'kinds' what each is in
-- the station's own order ("battery.gun", "battery.missile"), and
-- 'balls' the ship that is each (0 for one that is down). 'down' is
-- every battery anywhere that has been destroyed and not yet built
-- again: whose, which of them, and the tick it is back.
export type Batteries = {
  at: number,
  station: number,
  kinds: { string },
  balls: { number },
  down: { { station: number, index: number, back: number } },
}

-- A tower of the pirates' own, holding a moon (Tactical/Keeps): 'id' is
-- its place (a site), 'moon' the moon it holds, 'core' the ship that is
-- the tower. 'sealed' is the tick it comes out of being sealed (0 when
-- it is not), 'charges' the hours it can seal for, 'restock' the tick
-- it is resupplied (0 when it need not be), and 'called' and 'calls'
-- when it last called for help and how many times since it last opened.
export type Keep = { id: number, system: number, moon: number, core: number, sealed: number, charges: number, restock: number,
  called: number, calls: number }

export type State = {
  galaxySeed: number,     -- layout; a galaxy can be shared by its seed
  historySeed: number,    -- every roll made during play
  tick: number,
  nextId: number,
  galaxy: Galaxy.Galaxy,
  systems: { [number]: System.Description },  -- the systems described so far
  ships: { [number]: Ship },
  shipIds: { number },    -- ascending, like every id list here
  items: { [number]: Item },
  itemIds: { number },
  -- The skills the pilot knows, with their levels, and the levels queued
  -- to train: the first is in training since 'trainingStarted'.
  skills: { [string]: number },
  training: { { skill: string, level: number } },
  trainingStarted: number,
  -- The pilot's character, whose skills these are (Character/Characters),
  -- and whether the queue is trained by the time the player gives it
  -- (Core.Credit) and not by the game's ticks (2026-11-17: training goes
  -- by real time only). Nil in a game with no character (a test's, or
  -- one saved before there were characters).
  character: string?,
  trainingByClock: boolean?,
  -- The paints and designs that are the pilot's for good, by their ids
  -- (Assets/Paintwork): any ship of theirs is painted in any of them.
  paints: { [string]: boolean },
  jobs: { [number]: Job },
  jobIds: { number },
  wallet: number,         -- the player's credits
  journal: { Entry },     -- the wallet's recent history, oldest first
  -- Each station's market, made the first time it is needed: what the
  -- station itself will sell and buy, as a one-node economy.
  markets: { [number]: Economy.Economy },
  marketIds: { number },
  -- The galaxy's economy, in the real bulk goods (Strategic/Commerce):
  -- a node a system of the map, by the system's id. And, for each
  -- station's market, how much of each of those goods it has had of
  -- its system so far, less what it has given it (by the goods' class
  -- in the economy): what is new of that is settled with the system.
  commerce: Economy.Economy,
  marketDrawn: { [number]: { number } },
  -- What is happening to the trade of a part of the map (Strategic/
  -- Commerce): the gluts and the shortages there are now, in the order
  -- they began.
  shocks: { Shock },
  -- The factions at war (Strategic/Wars); and their operations in the
  -- system the pilot is in, as places and ships (Tactical/Fronts), by
  -- the operation's id.
  wars: Wars,
  fronts: { [number]: Front },
  frontIds: { number },
  -- The pilot's claims on open space (Assets/Sovereignty), by system:
  -- the hours a claim beacon of theirs has stood in one that is not
  -- theirs yet, and the hours one that is theirs has been without one.
  sovereignty: { progress: { [number]: number }, dark: { [number]: number } },
  -- The corporation's members, those who would join, the calls posted
  -- for them, and the tax they pay (Assets/Members).
  membership: Membership,
  orders: { [number]: Order },
  orderIds: { number },
  -- The pilot's listings on stations' boards (Assets/Contracts); the
  -- keys of the lots of the boards taken today; and, by station and by
  -- type, how many of a blueprint's copies its builders have had of the
  -- pilot ('units' as they stood at 'tick': they are forgotten by half
  -- every few days).
  -- The fights the pilot was not at, oldest first (Tactical/Battles).
  fleetLog: { Fight },
  contracts: { [number]: Listing },
  contractIds: { number },
  contractsTaken: { string },
  contractsHad: { [number]: { [string]: { units: number, tick: number } } },
  -- trades[station][type]: recent days of trade, oldest first
  trades: { [number]: { [string]: { TradeDay } } },
  starbases: { [number]: Starbase },  -- by the id of the station the tower is
  starbaseIds: { number },
  -- The pirates' own towers (Tactical/Keeps), by the id of their place;
  -- and the systems whose keeps have been put up.
  keeps: { [number]: Keep },
  keepIds: { number },
  keepsSeen: { [number]: boolean },
  colonies: { [number]: Colony },     -- by the id of the planet
  colonyIds: { number },
  balls: { [number]: Ball },
  ballIds: { number },
  missiles: { Missile },  -- in flight, oldest first
  wrecks: { [number]: Wreck },
  wreckIds: { number },
  pilots: { [number]: Pilot },  -- by ship id
  pilotIds: { number },
  spawned: { [number]: number },  -- by grid: the tick pirates last appeared there
  happenings: Happenings, -- what is going on in the galaxy (Strategic/Happenings)
  peaceful: boolean,      -- no pirates come (for tests, and for sightseeing)
  -- Asteroids that have been mined, by id: the units left, and the tick
  -- mining began (they grow back some hours later). A rock not listed is whole.
  rocks: { [number]: { left: number, since: number } },
  rockIds: { number },
  grids: { [number]: Grid },
  gridIds: { number },
  -- 'marked' is the tick until which the factions' patrols take the
  -- pilot for a criminal (Tactical/Traffic); 0 if they never have.
  -- 'field' is the station whose field the pilot's ship is inside
  -- (Tactical/Fields), while it is inside one.
  player: { ship: number, home: number, marked: number, field: number? },
  -- The batteries of the station the pilot is at (Tactical/Batteries).
  batteries: Batteries,
  -- The other ships about (Tactical/Traffic), by ship id, and the tick
  -- at which somebody new is next looked for.
  traffic: { [number]: Traffic },
  trafficIds: { number },
  trafficDue: number,
  trafficOn: boolean,     -- whether there is any: a game has, a test of one ship has not
  -- The colony fleets of the nomads (Tactical/Nomads): where each is
  -- follows from the tick, and all that is kept is, by a fleet's number,
  -- the tick until which its colony ship is gone, for one that has been
  -- destroyed.
  nomads: { [number]: number },
  -- The mining fleets (Tactical/Traffic): by a system's number, the
  -- tick until which the fleet that works it is away, for one that has
  -- jumped out or been lost.
  miningFleets: { [number]: number },
  research: { [string]: Research },   -- by blueprint id (Assets/Industry)
  -- Jobs in hand (Assets/Missions), which of today's offers have been
  -- taken, how many jobs have been finished, and the pilot's standing
  -- with each faction (-10 to 10; a faction not here is at 0).
  missions: { [number]: Mission },
  missionIds: { number },
  missionsTaken: { string },
  missionsDone: number,
  -- By station: how many assaults its agent has given the pilot (which
  -- is what the next one follows from: Assets/Missions).
  assaults: { [number]: number },
  -- And how many mining contracts its fifth agent has.
  digs: { [number]: number },
  -- And how many courier contracts its sixth.
  couriers: { [number]: number },
  -- And how many defence jobs its seventh.
  holds: { [number]: number },
  standings: { [string]: number },
  -- The sides the pilot has fought or done war work for, and the tick
  -- they last did (Tactical/Sides): the other side of a war counts them
  -- its enemy. (Nil in a game saved before 2026-11-16.)
  served: { [string]: number }?,
  -- Interdiction fields dropped and not yet gone (Tactical/Combat; module
  -- expansion, 2026-11-16): nobody but their owner's ships warps out of
  -- one. (Nil when there are none, and in a game saved before.)
  bubbles: { Bubble }?,
  -- Loyalty points with each faction, earned by its jobs and spent at
  -- its stations (a faction not here has none).
  loyalty: { [string]: number },
  -- What each agent thinks of the pilot (Assets/Missions), by the
  -- agent: "<station>:<which of its agents>". Nothing, for one the
  -- pilot has done nothing for.
  regard: { [string]: number },
  -- Sites (Tactical/Sites) by the id of their place, in the order they
  -- came; when each system's are next looked at, and which systems have
  -- had any (by system id); and the tick the ship's scanner is free.
  sites: { [number]: Site },
  siteIds: { number },
  sitesDue: { [number]: number },
  sitesSeen: { [number]: boolean },
  scanReady: number,
  -- The wormholes that are open (Tactical/Wormholes), in the order they
  -- opened; and the last day each system was asked whether one opens
  -- in it (by system id).
  wormholes: { [number]: Wormhole },
  wormholeIds: { number },
  wormholesRolled: { [number]: number },
  -- The hack the pilot has under way, if any.
  hack: Hack?,
  -- The scan probes the pilot has out, in the order they were put out.
  probes: { [number]: Probe },
  probeIds: { number },
  drones: { [number]: Drone },      -- by the drone's own ship id
  droneIds: { number },
  -- The pilots the player has hired (Tactical/Fleet), in the order they
  -- were, and which of the day 'hiredDay''s candidates have been taken.
  fleet: { [number]: Wingman },
  fleetIds: { number },
  hired: { string },
  hiredDay: number,
  -- The implants the pilot has plugged in (Character/Implants), by the
  -- places they are in.
  implants: { string },
  -- The boosters at work on the pilot (Character/Boosters), in the
  -- order they were taken.
  boosters: { Boosted },
  -- The steps of the guide the pilot has done (Character/Guide), in the
  -- order they did them.
  guide: { string },
  -- How far the pilot has got with each of the career agents
  -- (Character/Careers), by the career's id: one not here is not begun.
  careers: { [string]: Career },
  corporation: Corporation,
  -- The places the pilot has marked, in the order they were.
  bookmarks: { [number]: Bookmark },
  bookmarkIds: { number },
  queue: { Command },     -- submitted, to be applied at the next tick
}

function State.NewId(state: State): number
  local id = state.nextId
  state.nextId += 1
  return id
end

-- Remove 'id' from an ascending list of ids.
-- Put an id into an ascending list of ids, in its place.
function State.InsertId(ids: { number }, id: number)
  local at = #ids + 1
  while at > 1 and ids[at - 1] > id do
    at -= 1
  end
  table.insert(ids, at, id)
end

function State.RemoveId(ids: { number }, id: number)
  local lo, hi = 1, #ids
  while lo <= hi do
    local mid = (lo + hi) // 2
    local v = ids[mid]
    if v == id then
      table.remove(ids, mid)
      return
    elseif v < id then
      lo = mid + 1
    else
      hi = mid - 1
    end
  end
end

return State
