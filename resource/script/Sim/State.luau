--!strict
-- The universe state: everything that changes. With the galaxy seed it is
-- the save file; the galaxy description is regenerated from that seed.
-- The history seed (stored here) drives every roll made during play, so
-- each new game in the same galaxy unfolds differently, while any run can
-- be replayed exactly from its two seeds. State.New sets up a new universe: faction territories, pirate
-- dens, starting stocks, fleets and relations.

local Data = require("@lt/Sim/Data")
local Galaxy = require("@lt/Sim/Galaxy")
local Rng = require("@lt/Sim/Rng")

local State = {}

export type Stock = { [string]: number }

export type Station = {
  id: number,
  system: number,
  kind: string,
  stock: Stock,
  nextCycle: number,
  building: number?,           -- action id of a ship under construction
  destroyed: boolean?,
  maintained: number,          -- share of its maintenance goods it got last cycle
}

export type System = {
  id: number,
  owner: number?,              -- faction id; nil for independent systems
  fleets: { number },          -- fleets present (not in transit)
  credits: number,             -- an independent system's treasury
}

export type Fleet = {
  id: number,
  owner: number,
  role: "war" | "trade",
  ships: { [string]: number },
  system: number?,             -- nil while jumping
  last: number,                -- the system it was last in
  cargo: Stock,
  fuel: number,
  munitions: number,
  action: number?,             -- the action using it
  idleSince: number,
  alive: boolean,
}

export type Faction = {
  id: number,
  name: string,
  traits: Data.Traits,
  pirate: boolean,
  credits: number,
  relations: { [number]: number },
  war: { [number]: boolean },
  baseline: { [number]: number },
  losses: number,              -- ships lost this period
  alive: boolean,
  capital: number?,
  arrears: number,             -- periods in a row it couldn't pay its costs
  costs: number,               -- running costs last period
  income: number,              -- average net income per period, before running costs
  lastCredits: number,         -- credits after paying the last period's costs
  truce: { [number]: number }, -- no war with this faction before this tick
  warStart: { [number]: number }, -- own war strength when each war began
  plan: Plan?,                 -- the attack being prepared
}

-- An attack or claim being prepared: fleets muster at 'staging', next to 'target'
export type Plan = { kind: "attack" | "claim", target: number, staging: number, since: number }

-- Fields beyond the common ones depend on the kind
export type Action = {
  id: number,
  owner: number,
  kind: "move" | "convoy" | "build" | "siege" | "construct",
  submitted: number,
  phase: "action" | "reaction" | "resolve",
  due: number,
  done: boolean,
  cancelled: boolean?,
  -- move / convoy
  fleet: number?,
  path: { number }?,
  step: number?,
  intent: string?,
  target: number?,
  -- convoy
  stage: ("pickup" | "deliver")?,
  from: number?,
  to: number?,
  good: string?,
  quantity: number?,
  claimed: boolean?,           -- still holds a pickup reservation
  expected: boolean?,          -- still holds a delivery reservation
  -- build / construct
  station: number?,
  ship: string?,
  structure: string?,          -- station kind being constructed
  reserved: Stock?,
  credits: number?,
}

export type Event = { tick: number, kind: string, text: string }

export type State = {
  seed: number,                -- galaxy seed: layout, stations and starting setup
  history: number,             -- history seed: every roll made during play
  tick: number,
  phase: "resolve" | "action" | "reaction",
  galaxy: Galaxy.Galaxy,
  factions: { Faction },
  pirates: number,
  systems: { System },
  stations: { Station },
  fleets: { [number]: Fleet },
  actions: { [number]: Action },
  timers: { { due: number, id: number } },   -- min-heap on (due, id)
  nextId: number,
  news: { Event },
  counters: { [string]: number },
  reacted: { [string]: boolean },
  pending: { [string]: number? },            -- goods claimed by convoys under way, by station and good
  built: { { system: number, kind: string } }, -- stations constructed after generation (part of the save)
}

function State.NewId(state: State): number
  state.nextId += 1
  return state.nextId
end

function State.Log(state: State, kind: string, text: string)
  table.insert(state.news, { tick = state.tick, kind = kind, text = text })
end

-- Goods that convoys under way will pick up from ('out') or deliver to ('in') a station
function State.PendingKey(direction: "out" | "in", station: number, good: string): string
  return `{direction}:{station}:{good}`
end

function State.Pending(state: State, direction: "out" | "in", station: number, good: string): number
  return state.pending[State.PendingKey(direction, station, good)] or 0
end

function State.AddPending(state: State, direction: "out" | "in", station: number, good: string, amount: number)
  local key = State.PendingKey(direction, station, good)
  local value = (state.pending[key] or 0) + amount
  state.pending[key] = if value > 0.001 then value else nil
end

function State.Count(state: State, counter: string, amount: number?)
  state.counters[counter] = (state.counters[counter] or 0) + (amount or 1)
end

------------------------------------------------------------- Timer heap

local function less(a: { due: number, id: number }, b: { due: number, id: number }): boolean
  return a.due < b.due or (a.due == b.due and a.id < b.id)
end

function State.Schedule(state: State, action: Action)
  local heap = state.timers
  table.insert(heap, { due = action.due, id = action.id })
  local i = #heap
  while i > 1 do
    local parent = i // 2
    if less(heap[i], heap[parent]) then
      heap[i], heap[parent] = heap[parent], heap[i]
      i = parent
    else
      break
    end
  end
end

-- The ids of the actions due at or before 'tick', in (due, id) order
function State.PopDue(state: State, tick: number): { number }
  local heap = state.timers
  local due = {}
  while #heap > 0 and heap[1].due <= tick do
    table.insert(due, heap[1].id)
    heap[1] = heap[#heap]
    heap[#heap] = nil
    local i = 1
    while true do
      local l, r, m = 2 * i, 2 * i + 1, i
      if l <= #heap and less(heap[l], heap[m]) then m = l end
      if r <= #heap and less(heap[r], heap[m]) then m = r end
      if m == i then break end
      heap[i], heap[m] = heap[m], heap[i]
      i = m
    end
  end
  return due
end

---------------------------------------------------------------- Fleets

function State.ShipCount(fleet: Fleet): number
  local n = 0
  for _, class in Data.Ships do
    n += fleet.ships[class.id] or 0
  end
  return n
end

function State.NewFleet(state: State, owner: number, system: number, role: "war" | "trade",
  ships: { [string]: number }): Fleet
  local fleet: Fleet = {
    id = State.NewId(state),
    owner = owner,
    role = role,
    ships = ships,
    system = system,
    last = system,
    cargo = {},
    fuel = 0,
    munitions = 0,
    action = nil,
    idleSince = state.tick,
    alive = true,
  }
  local n = State.ShipCount(fleet)
  fleet.fuel = 10 * n
  fleet.munitions = 2 * n
  state.fleets[fleet.id] = fleet
  table.insert(state.systems[system].fleets, fleet.id)
  return fleet
end

function State.Leave(state: State, fleet: Fleet)
  local system = fleet.system
  if system then
    local list = state.systems[system].fleets
    local i = table.find(list, fleet.id)
    if i then
      table.remove(list, i)
    end
    fleet.last = system
    fleet.system = nil
  end
end

function State.Arrive(state: State, fleet: Fleet, system: number)
  fleet.system = system
  table.insert(state.systems[system].fleets, fleet.id)
end

function State.Disband(state: State, fleet: Fleet)
  State.Leave(state, fleet)
  fleet.alive = false
  state.fleets[fleet.id] = nil
end

-- Moves 'ships' out of 'fleet' into a new fleet at the same system
function State.Split(state: State, fleet: Fleet, ships: { [string]: number }): Fleet
  local system = assert(fleet.system, "can only split a fleet in a system")
  local taken: { [string]: number } = {}
  for class, n in ships do
    local k = math.min(n, fleet.ships[class] or 0)
    if k > 0 then
      fleet.ships[class] -= k
      taken[class] = k
    end
  end
  local part = State.NewFleet(state, fleet.owner, system, fleet.role, taken)
  -- Share supplies by ship count
  local total = State.ShipCount(fleet) + State.ShipCount(part)
  local share = if total > 0 then State.ShipCount(part) / total else 0
  part.fuel, fleet.fuel = fleet.fuel * share, fleet.fuel * (1 - share)
  part.munitions, fleet.munitions = fleet.munitions * share, fleet.munitions * (1 - share)
  return part
end

---------------------------------------------------------------- Setup

local function stationProfile(kind: string): ({ [string]: number }, { [string]: number })
  local wants: { [string]: number } = {}
  local makes: { [string]: number } = {}
  local def = Data.StationById[kind]
  for _, recipe in def.recipes do
    for good, n in recipe.inputs do
      wants[good] = (wants[good] or 0) + n * Data.TARGET_CYCLES
    end
    for good, n in recipe.outputs do
      makes[good] = (makes[good] or 0) + n
    end
  end
  local demand: { [string]: number } = def.demand or {}
  for good, n in demand do
    wants[good] = (wants[good] or 0) + n
  end
  for good, n in Data.MAINTENANCE do
    wants[good] = (wants[good] or 0) + n * Data.MAINTENANCE_CYCLES
  end
  return wants, makes
end
State.StationProfile = stationProfile

local function addStationState(state: State, desc: Galaxy.StationDesc, rng: Rng.Rng)
  local wants, makes = stationProfile(desc.kind)
  local stock: Stock = {}
  for good, target in wants do
    stock[good] = target * Rng.Float(rng, 0.4, 0.8)
  end
  for good, perCycle in makes do
    stock[good] = (stock[good] or 0) + perCycle * Data.CAP_CYCLES * Rng.Float(rng, 0.1, 0.4)
  end
  state.stations[desc.id] = {
    id = desc.id,
    system = desc.system,
    kind = desc.kind,
    stock = stock,
    nextCycle = Rng.Int(rng, Data.CYCLE_TICKS),
    maintained = 1,
  }
end

-- Capitals far apart, among systems with at least two stations
local function pickCapitals(galaxy: Galaxy.Galaxy, rng: Rng.Rng, count: number): { number }
  local candidates = {}
  for _, system in galaxy.systems do
    if #system.stations >= 2 then
      table.insert(candidates, system.id)
    end
  end
  local capitals = { candidates[Rng.Int(rng, #candidates) + 1] }
  while #capitals < count do
    local best, bestD = candidates[1], -1
    for _, c in candidates do
      local d = math.huge
      for _, cap in capitals do
        d = math.min(d, galaxy.hops[c][cap])
      end
      if d > bestD then
        best, bestD = c, d
      end
    end
    table.insert(capitals, best)
  end
  return capitals
end

function State.New(galaxy: Galaxy.Galaxy, seed: number, history: number): State
  local rng = Rng.For(seed, 2)
  local state: State = {
    seed = seed,
    history = history,
    tick = 0,
    phase = "resolve",
    galaxy = galaxy,
    factions = {},
    pirates = 0,
    systems = {},
    stations = {},
    fleets = {},
    actions = {},
    timers = {},
    nextId = 0,
    news = {},
    counters = {},
    reacted = {},
    pending = {},
    built = {},
  }
  for _, desc in galaxy.systems do
    state.systems[desc.id] = { id = desc.id, owner = nil, fleets = {}, credits = Data.INDEPENDENT_CREDITS }
  end

  for i, def in Data.Factions do
    table.insert(state.factions, {
      id = i,
      name = def.name,
      traits = def.traits,
      pirate = def.pirate == true,
      credits = if def.pirate then Data.PIRATE_CREDITS else Data.STARTING_CREDITS,
      relations = {},
      war = {},
      baseline = {},
      losses = 0,
      alive = true,
      capital = nil,
      arrears = 0,
      costs = 0,
      income = 0,
      lastCredits = if def.pirate then Data.PIRATE_CREDITS else Data.STARTING_CREDITS,
      truce = {},
      warStart = {},
      plan = nil,
    })
    if def.pirate then
      state.pirates = i
    end
  end

  -- Relations: sociable pairs like each other, aggressive pairs don't
  for _, a in state.factions do
    for _, b in state.factions do
      if a.id < b.id then
        local value, baseline
        if a.pirate or b.pirate then
          value, baseline = -100, -100
        else
          local sociable = (a.traits.sociable + b.traits.sociable) / 2
          local aggressive = (a.traits.aggressive + b.traits.aggressive) / 2
          baseline = 10 + 40 * sociable - 50 * aggressive
          value = baseline + Rng.Float(rng, -15, 15)
        end
        a.relations[b.id], b.relations[a.id] = value, value
        a.baseline[b.id], b.baseline[a.id] = baseline, baseline
        local atWar = value < Data.WAR_BELOW
        a.war[b.id], b.war[a.id] = atWar, atWar
      end
    end
  end

  -- Territories grow outward from the capitals, one system per faction per round
  local empires = {}
  for _, f in state.factions do
    if not f.pirate then
      table.insert(empires, f)
    end
  end
  local capitals = pickCapitals(galaxy, rng, #empires)
  local frontiers: { { number } } = {}
  local owned: { number } = {}
  for i, f in empires do
    local cap = capitals[i]
    state.systems[cap].owner = f.id
    f.capital = cap
    for _, kind in { "shipyard", "habitat", "refinery" } do
      if not Galaxy.HasStation(galaxy, cap, kind) then
        Galaxy.AddStation(galaxy, cap, kind)
      end
    end
    frontiers[i] = { cap }
    owned[i] = 1
  end
  local growing = true
  while growing do
    growing = false
    for i, f in empires do
      if owned[i] < Data.TERRITORY then
        -- The frontier system with the fewest hops to the capital
        local pick: number? = nil
        for _, s in frontiers[i] do
          for _, n in galaxy.systems[s].neighbors do
            if state.systems[n].owner == nil and (pick == nil or galaxy.hops[capitals[i]][n] < galaxy.hops[capitals[i]][pick :: number]
              or (galaxy.hops[capitals[i]][n] == galaxy.hops[capitals[i]][pick :: number] and n < (pick :: number))) then
              pick = n
            end
          end
        end
        if pick then
          state.systems[pick].owner = f.id
          table.insert(frontiers[i], pick)
          owned[i] += 1
          growing = true
        end
      end
    end
  end

  -- Pirate dens in the unclaimed systems farthest from any capital
  local remote = {}
  for _, s in state.systems do
    if s.owner == nil then
      local d = math.huge
      for _, cap in capitals do
        d = math.min(d, galaxy.hops[s.id][cap])
      end
      table.insert(remote, { id = s.id, d = d })
    end
  end
  table.sort(remote, function(p, q)
    if p.d ~= q.d then
      return p.d > q.d
    end
    return p.id < q.id
  end)
  local dens: { number } = {}
  for _, r in remote do
    if #dens >= Data.PIRATE_DENS then
      break
    end
    local spaced = true
    for _, d in dens do
      if galaxy.hops[r.id][d] < 4 then
        spaced = false
      end
    end
    if spaced then
      table.insert(dens, r.id)
      state.systems[r.id].owner = state.pirates
      state.factions[state.pirates].capital = state.factions[state.pirates].capital or r.id
      Galaxy.AddStation(galaxy, r.id, "den")
    end
  end

  for _, desc in galaxy.stations do
    addStationState(state, desc, rng)
  end

  -- Starting fleets: a home fleet at the capital, garrisons, haulers
  for i, f in empires do
    State.NewFleet(state, f.id, capitals[i], "war", { frigate = 12, cruiser = 3 })
    for k, s in frontiers[i] do
      if k > 1 and k % 4 == 0 then
        State.NewFleet(state, f.id, s, "war", { frigate = 3 })
      end
    end
    for k = 1, 10 do
      State.NewFleet(state, f.id, frontiers[i][(k * 3) % #frontiers[i] + 1], "trade", { hauler = 1 })
    end
  end
  for _, den in dens do
    State.NewFleet(state, state.pirates, den, "war", { frigate = 4 })
  end
  return state
end

-- Adds a station constructed during play. It goes into the galaxy
-- description and is recorded in state.built, since the description is
-- regenerated from the seed on load.
function State.BuildStation(state: State, system: number, kind: string): Station
  local id = Galaxy.AddStation(state.galaxy, system, kind)
  local station: Station = {
    id = id,
    system = system,
    kind = kind,
    stock = {},
    nextCycle = state.tick + Data.CYCLE_TICKS,
    maintained = 1,
  }
  -- A new station starts with a little maintenance stock
  for good, n in Data.MAINTENANCE do
    station.stock[good] = n * 10
  end
  state.stations[id] = station
  table.insert(state.built, { system = system, kind = kind })
  return station
end

------------------------------------------------------------- Queries

function State.Owner(state: State, system: number): number?
  return state.systems[system].owner
end

function State.Hostile(state: State, a: number?, b: number?): boolean
  if a == nil or b == nil or a == b then
    return false
  end
  return state.factions[a].war[b] == true
end

-- Idle fleets of 'owner' (or anyone) in 'system'
function State.IdleFleets(state: State, system: number, owner: number?, role: ("war" | "trade")?): { Fleet }
  local list = {}
  for _, id in state.systems[system].fleets do
    local fleet = state.fleets[id]
    if fleet and fleet.action == nil and (owner == nil or fleet.owner == owner) and (role == nil or fleet.role == role) then
      table.insert(list, fleet)
    end
  end
  return list
end

function State.StationDefense(state: State, system: number): number
  local total = 0
  for _, id in state.galaxy.systems[system].stations do
    local station = state.stations[id]
    if not station.destroyed then
      local readiness = Data.UNMAINTAINED + (1 - Data.UNMAINTAINED) * station.maintained
      total += Data.StationById[station.kind].defense * readiness
    end
  end
  return total
end

return State
