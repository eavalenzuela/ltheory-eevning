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
  -- Armour and hull points missing. Damage stays with a ship until it is
  -- repaired; shields and capacitor refill by themselves.
  armorDamage: number,
  hullDamage: number,
  -- The hired pilot who flies it (Tactical/Fleet), by their id; 0 for
  -- a ship the player flies themselves, or that nobody does.
  pilot: number,
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
  capacitor: number,
  shieldMax: number,
  armorMax: number,
  hullMax: number,
  capacitorMax: number,
  shieldRecharge: number,
  capacitorRecharge: number,
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
}

-- A missile in flight: it lands at 'impact' and does its damage then.
export type Missile = {
  from: number,
  to: number,
  item: number,
  charge: string,
  damage: { number },
  impact: number,
}

-- A stack of items of one type in one place. A fitted module is a stack
-- of one, in a rack ("high", "mid" or "low") at a slot.
export type Item = {
  id: number,
  type: string,       -- Data/Types id
  quantity: number,
  holder: number,     -- the ship it is in or on, or the station whose hangar it is in
  -- ("dronebay" is a ship's drone bay: Tactical/Drones)
  place: "hangar" | "cargo" | "dronebay" | "high" | "mid" | "low" | "rig",
  slot: number,       -- within its rack, from 1; 0 unless fitted
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
}

-- A ship of the traffic: a hauler coming "in" to dock at 'goal' or going
-- "out" to the gate 'goal', a "patrol" on station at 'goal', a "miner"
-- at the belt 'goal' (going "home" to the station 'goal' when it has
-- done), or one of the "police" come for a marked pilot. It
-- belongs to the system it was made in, and 'wait' counts its last
-- moments at a gate.
export type Traffic = { ship: number, kind: string, goal: number, system: number, born: number, wait: number }

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
  to: string?,        -- "cargo" or "hangar"; for an order, "buy" or "sell"
  type: string?,      -- an item type, when there is no item yet (buying)
  price: number?,     -- credits per unit, for a limit order
  order: number?,     -- an order's id
  what: string?,      -- what a colony's facility is set on or set to make
  pin: number?,       -- a colony's facility, by its number there
  hours: number?,     -- the length of an extractor's programme
  pilot: number?,     -- a hired pilot, by their id
  stops: { number }?, -- for a haul: the further stations to collect at, in order
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

-- One day's trade in a type at a station.
export type TradeDay = { day: number, volume: number, value: number }

-- A manufacturing job: it ends at a tick and its product then appears in
-- the hangar of the station it runs at.
export type Job = {
  id: number,
  station: number,
  blueprint: string,
  runs: number,
  product: string,
  quantity: number,   -- units it will make
  -- "" for a job that builds. For research into its blueprint, what is
  -- being learned: "material" or "time" (it makes nothing).
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
-- wants has been done since it was taken.
export type Career = { done: number, taken: boolean, count: number }

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
  -- For one sent to "buy": the type of thing ('want'), how many of it
  -- are still to be bought ('need'), and the most to pay for one, on
  -- the average of a purchase ('limit'). It is bought at the station
  -- 'post' and brought to the station 'base'.
  want: string, need: number, limit: number,
}

-- A place that is on nobody's chart (Tactical/Sites): 'id' is the place
-- it is in its system's description. 'strength' is how far a scanner
-- has got with it, from 0 to 1 (found); 'gone' is a site that is over.
-- 'depth' is how far along a trail it is (0 for a site that was simply
-- there; 1 for a stronghold a den's records led to), and 'led' whether
-- it has itself been asked where it leads.
export type Site = { id: number, system: number, kind: string, code: string, strength: number, expires: number, gone: boolean,
  depth: number, led: boolean }

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
}

-- What a pilot has researched of a blueprint: levels of each kind.
export type Research = { material: number, time: number }

-- A line in the wallet's journal.
export type Entry = { tick: number, amount: number, reason: string, balance: number }

-- The pilot's corporation (Assets/Corporation): its name ("" until one
-- is founded) and when it was founded, its own credits and their recent
-- history, and all it has earned and spent since (what its founder has
-- paid in and taken out aside).
export type Corporation = { name: string, founded: number, wallet: number, journal: { Entry }, earned: number, spent: number }

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
}

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
  jobs: { [number]: Job },
  jobIds: { number },
  wallet: number,         -- the player's credits
  journal: { Entry },     -- the wallet's recent history, oldest first
  -- Each station's market, made the first time it is needed: what the
  -- station itself will sell and buy, as a one-node economy.
  markets: { [number]: Economy.Economy },
  marketIds: { number },
  orders: { [number]: Order },
  orderIds: { number },
  -- trades[station][type]: recent days of trade, oldest first
  trades: { [number]: { [string]: { TradeDay } } },
  starbases: { [number]: Starbase },  -- by the id of the station the tower is
  starbaseIds: { number },
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
  peaceful: boolean,      -- no pirates come (for tests, and for sightseeing)
  -- Asteroids that have been mined, by id: the units left, and the tick
  -- mining began (they grow back some hours later). A rock not listed is whole.
  rocks: { [number]: { left: number, since: number } },
  rockIds: { number },
  grids: { [number]: Grid },
  gridIds: { number },
  -- 'marked' is the tick until which the factions' patrols take the
  -- pilot for a criminal (Tactical/Traffic); 0 if they never have.
  player: { ship: number, home: number, marked: number },
  -- The other ships about (Tactical/Traffic), by ship id, and the tick
  -- at which somebody new is next looked for.
  traffic: { [number]: Traffic },
  trafficIds: { number },
  trafficDue: number,
  trafficOn: boolean,     -- whether there is any: a game has, a test of one ship has not
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
  standings: { [string]: number },
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
