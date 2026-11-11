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
-- resonances come from hull and fit (Core/Dogma) and are refreshed when a
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
  place: "hangar" | "cargo" | "high" | "mid" | "low",
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
}

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
-- "out" to the gate 'goal', or a "patrol" on station at 'goal'. It
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

-- A job a station has for a pilot (Assets/Missions): a "bounty" (destroy
-- 'need' pirates in 'system'; 'done' so far), a "courier" run (carry
-- 'need' of 'type' to the station 'to'), or a "supply" order (bring
-- 'need' of 'type' to 'station'). 'key' is the offer it was (station,
-- day and place in the list), and 'id' is 0 until a pilot has taken it.
export type Mission = {
  id: number, key: string, kind: string, station: number, faction: string, system: number, need: number, done: number,
  type: string, to: number, reward: number, standing: number, taken: number,
}

-- What a pilot has researched of a blueprint: levels of each kind.
export type Research = { material: number, time: number }

-- A line in the wallet's journal.
export type Entry = { tick: number, amount: number, reason: string, balance: number }

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
  standings: { [string]: number },
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
