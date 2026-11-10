--!strict
-- The strategic world: the galaxy's powers, their fleets and their wars,
-- on top of the galaxy's economy. (docs/roadmap.md §6.)
--
-- Everything that changes is here, as plain data: with the two seeds it
-- is the save. The galaxy and the atlas are descriptions made once and
-- kept (who lives where, what is made where); the economy holds every
-- stock; the rest is who owns what, how firmly, and what the fleets are
-- doing.
--
-- A new world starts at the founding: each power holds its homeworld
-- and nothing else, and every other system is independent. The powers
-- grow by claiming.
--
-- Money lives only with the powers and the pirates. Every credit that
-- moves is posted to the ledger with a reason, and credits enter or
-- leave the world only through it, so the sources and sinks can be read
-- off and a leak shows up as a residual.

local Atlas = require("@lt/Core/Strategic/Atlas")
local Economy = require("@lt/Core/Strategic/Economy")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Goods = require("@lt/Core/Data/Goods")
local Ledger = require("@lt/Core/Kernel/Ledger")
local Powers = require("@lt/Core/Data/Powers")
local Rng = require("@lt/Core/Kernel/Rng")
local Routes = require("@lt/Core/Strategic/Routes")

local World = {}

export type Siege = {
  by: number,           -- the faction laying it
  -- siege: of an enemy's system. claim: of an independent one. clear:
  -- of a pirate den. raid: by pirates, for loot.
  kind: "siege" | "claim" | "clear" | "raid",
  since: number,        -- the tick it began
  planned: number,      -- the tick the plan behind it could first be seen
  progress: number,     -- ticks it has gone on unopposed
  stage: "blockade" | "assault" | "occupy",
}

export type System = {
  id: number,
  owner: number,        -- faction id; 0 if independent
  control: number,      -- how firmly the owner holds it, 0 to 1
  pressure: number,     -- pirate pressure, 0 to 1
  security: number,     -- how safe it is, 0 to 1: follows from the two above
  den: boolean,         -- a pirate den stands here
  defence: number,      -- how much of its own defences is left, 0 to 1
  fleets: { number },   -- fleets present (not those jumping), in id order
  siege: Siege?,
  fighting: number,     -- the tick fleets began fighting here; 0 when quiet
  raided: number,       -- the tick pirates last raided it
}

export type Fleet = {
  id: number,
  owner: number,
  ships: { number },    -- how many of each ship class (Powers.ships)
  system: number,       -- where it is; 0 while jumping
  last: number,         -- the system it was last in
  supply: number,       -- units of supply aboard
  kits: number,         -- construction kits aboard
  action: number,       -- the action moving it; 0 if none
  -- What it is for. "" when it is free to be given something to do.
  task: string,
  target: number,       -- the system its task concerns
  since: number,        -- the tick it last arrived or was given its task
}

export type Action = {
  id: number,
  owner: number,
  kind: "move" | "build" | "reactivate" | "den",
  due: number,
  -- move
  fleet: number,
  dest: number,
  cancelled: boolean,
  -- build, reactivate
  ship: number,         -- ship class
  count: number,
  system: number,       -- where
  paid: number,         -- what it cost
}

export type War = {
  a: number,            -- who declared it
  b: number,
  since: number,
  startA: number,       -- each side's strength at the outset
  startB: number,
  lostA: number,        -- strength each has lost in it
  lostB: number,
  takenA: number,       -- the worth of what each has taken from the other
  takenB: number,
  coalition: boolean,   -- declared to stop an aggressor
}

-- An attack being prepared in the open: a force gathers at 'staging',
-- next to 'target', and is launched when it is enough.
export type Plan = { kind: "attack", target: number, staging: number, since: number, launched: boolean }

export type Faction = {
  id: number,
  name: string,
  traits: Powers.Traits,
  pirate: boolean,
  alive: boolean,
  capital: number,          -- system id; 0 for the pirates
  credits: number,
  systems: number,          -- how many it owns
  relations: { number },    -- by faction id
  baseline: { number },     -- where each relation settles, left alone
  truce: { number },        -- no war with that faction before this tick
  -- Toward each faction: 0 nothing, 1 borders closed to it, 2 and its
  -- enemy subsidised.
  stance: { number },
  lastDeclared: number,
  lastWarEnded: number,
  policing: number,         -- effort, 0 to 1
  reserve: { number },      -- laid-up ships, by ship class
  income: number,           -- credits an hour, smoothed
  costs: number,
  arrears: number,          -- periods in a row it could not pay
  periods: number,          -- periods it has existed
  periodsInArrears: number,
  plan: Plan?,
  -- Credits its government is keeping back for something it has decided
  -- on but cannot pay for yet (the kits for a claim).
  earmark: number,
  hops: { number },         -- jumps from its capital to every system
}

export type News = { tick: number, kind: string, text: string, system: number, a: number, b: number }

export type World = {
  seed: number,             -- the galaxy's
  history: number,          -- every roll made during play comes from this
  tick: number,
  galaxy: Galaxy.Galaxy,
  atlas: Atlas.Atlas,
  econ: Economy.Economy,
  factions: { Faction },
  pirates: number,          -- the pirates' faction id
  systems: { System },
  fleets: { [number]: Fleet },
  actions: { [number]: Action },
  -- The ids in 'fleets' and 'actions', ascending. Rules loop over these,
  -- never over the maps: a map's order changes when a save is loaded.
  fleetIds: { number },
  actionIds: { number },
  timers: { { due: number, id: number } },   -- a heap on (due, id)
  wars: { War },
  nextId: number,
  ledger: Ledger.Ledger,
  news: { News },           -- the latest; older items are dropped
  counters: { [string]: number },
  -- Minutes from an attack's plan being visible to the system falling,
  -- one entry a capture.
  warnings: { number },
  loot: number,             -- the worth of goods lost to piracy, as of the last period
}

local NEWS_KEPT = 400

-- ---------------------------------------------------------------------
-- Small things

function World.NewId(world: World): number
  world.nextId += 1
  return world.nextId
end

function World.Count(world: World, counter: string, amount: number?)
  world.counters[counter] = (world.counters[counter] or 0) + (amount or 1)
end

function World.Log(world: World, kind: string, text: string, system: number?, a: number?, b: number?)
  local news = world.news
  table.insert(news, { tick = world.tick, kind = kind, text = text, system = system or 0, a = a or 0, b = b or 0 })
  World.Count(world, "news: " .. kind)
  if #news > NEWS_KEPT + 100 then
    table.move(news, 101, #news, 1)
    for _ = 1, 100 do
      table.remove(news)
    end
  end
end

function World.Name(world: World, faction: number): string
  return if faction > 0 then world.factions[faction].name else "the independents"
end

function World.SystemName(world: World, system: number): string
  return world.galaxy.systems[system].name
end

local function account(faction: number): string
  return if faction > 0 then `actor:{faction}` else Ledger.WORLD
end

-- Move credits between two factions, or between a faction and the world
-- (0): the only way credits change hands.
function World.Pay(world: World, from: number, to: number, amount: number, reason: string)
  if amount <= 0 or from == to then
    return
  end
  if from > 0 then
    world.factions[from].credits -= amount
  end
  if to > 0 then
    world.factions[to].credits += amount
  end
  Ledger.Post(world.ledger, "credits", account(from), account(to), amount, reason)
end

-- The accounts that hold credits, as the ledger's Reconcile wants them.
function World.Wallets(world: World): { [string]: number }
  local wallets: { [string]: number } = {}
  for _, faction in world.factions do
    wallets[account(faction.id)] = faction.credits
  end
  return wallets
end

-- Remove 'id' from an ascending list of ids.
function World.RemoveId(ids: { number }, id: number)
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

-- ---------------------------------------------------------------------
-- Timers: a heap of (due, id), so the actions due at a tick come out in
-- an order that does not depend on when they were put in.

local function less(a: { due: number, id: number }, b: { due: number, id: number }): boolean
  return a.due < b.due or (a.due == b.due and a.id < b.id)
end

function World.Schedule(world: World, action: Action)
  local heap = world.timers
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

-- The ids of the actions due at or before 'tick', in (due, id) order.
function World.PopDue(world: World, tick: number): { number }
  local heap = world.timers
  local due: { number } = {}
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

function World.NewAction(world: World, owner: number, kind: "move" | "build" | "reactivate" | "den", due: number): Action
  local action: Action = {
    id = World.NewId(world), owner = owner, kind = kind, due = due,
    fleet = 0, dest = 0, cancelled = false, ship = 0, count = 0, system = 0, paid = 0,
  }
  world.actions[action.id] = action
  table.insert(world.actionIds, action.id)
  World.Schedule(world, action)
  return action
end

function World.EndAction(world: World, action: Action)
  world.actions[action.id] = nil
  World.RemoveId(world.actionIds, action.id)
  local fleet = if action.fleet > 0 then world.fleets[action.fleet] else nil
  if fleet and fleet.action == action.id then
    fleet.action = 0
  end
end

-- ---------------------------------------------------------------------
-- Who is whose enemy

function World.WarBetween(world: World, a: number, b: number): War?
  for _, war in world.wars do
    if (war.a == a and war.b == b) or (war.a == b and war.b == a) then
      return war
    end
  end
  return nil
end

-- Two factions that fight on sight: at war, or one of them the pirates.
-- (0, the independents, is nobody's enemy as such.)
function World.Hostile(world: World, a: number, b: number): boolean
  if a == b or a == 0 or b == 0 then
    return false
  end
  if a == world.pirates or b == world.pirates then
    return true
  end
  return World.WarBetween(world, a, b) ~= nil
end

function World.AtWar(world: World, faction: number): boolean
  for _, war in world.wars do
    if war.a == faction or war.b == faction then
      return true
    end
  end
  return false
end

-- Bad blood: lower the level two powers' relations settle at, and
-- their relations now.
function World.Sour(world: World, a: number, b: number, amount: number)
  local fa, fb = world.factions[a], world.factions[b]
  if a == b or fa.pirate or fb.pirate then
    return
  end
  local baseline = math.max(-80, fa.baseline[b] - amount)
  local relation = math.max(-100, fa.relations[b] - amount)
  fa.baseline[b], fb.baseline[a] = baseline, baseline
  fa.relations[b], fb.relations[a] = relation, relation
end

-- ---------------------------------------------------------------------
-- Fleets

function World.Ships(fleet: Fleet): number
  local n = 0
  for _, count in fleet.ships do
    n += count
  end
  return n
end

-- What a fleet is worth in a fight when it has its supplies.
function World.FullStrength(fleet: Fleet): number
  local total = 0
  for class, count in fleet.ships do
    total += count * Powers.ships[class].strength
  end
  return total
end

-- What it is worth now.
function World.Strength(fleet: Fleet): number
  local total = World.FullStrength(fleet)
  return if fleet.supply > 0 then total else total * Powers.UNSUPPLIED
end

-- Units of supply a fleet uses in an hour.
function World.SupplyRate(fleet: Fleet): number
  local total = 0
  for class, count in fleet.ships do
    total += count * Powers.ships[class].supply
  end
  return total
end

function World.NewFleet(world: World, owner: number, system: number, ships: { number }): Fleet
  local fleet: Fleet = {
    id = World.NewId(world), owner = owner, ships = ships, system = system, last = system,
    supply = 0, kits = 0, action = 0, task = "", target = 0, since = world.tick,
  }
  fleet.supply = World.SupplyRate(fleet) * Powers.SUPPLY_HOURS
  world.fleets[fleet.id] = fleet
  table.insert(world.fleetIds, fleet.id)
  table.insert(world.systems[system].fleets, fleet.id)
  return fleet
end

function World.Leave(world: World, fleet: Fleet)
  if fleet.system > 0 then
    World.RemoveId(world.systems[fleet.system].fleets, fleet.id)
    fleet.last = fleet.system
    fleet.system = 0
  end
end

function World.Arrive(world: World, fleet: Fleet, system: number)
  fleet.system = system
  fleet.since = world.tick
  -- kept in id order
  local list = world.systems[system].fleets
  local at = #list + 1
  while at > 1 and list[at - 1] > fleet.id do
    at -= 1
  end
  table.insert(list, at, fleet.id)
end

function World.Disband(world: World, fleet: Fleet)
  if fleet.action > 0 then
    local action = world.actions[fleet.action]
    if action then
      World.EndAction(world, action)
    end
  end
  World.Leave(world, fleet)
  world.fleets[fleet.id] = nil
  World.RemoveId(world.fleetIds, fleet.id)
end

-- The fleets in id order. The list is a copy, so the loop's body may
-- make and disband fleets; check that each still exists.
function World.FleetIds(world: World): { number }
  return table.clone(world.fleetIds)
end

-- Move 'ships' (by class) out of a fleet into a new one beside it, with
-- its share of the supplies. Kits stay with the old fleet.
function World.Split(world: World, fleet: Fleet, ships: { number }): Fleet
  assert(fleet.system > 0, "only a fleet in a system can be split")
  local before = World.SupplyRate(fleet)
  local taken: { number } = table.create(#Powers.ships, 0)
  for class in Powers.ships do
    local k = math.min(ships[class] or 0, fleet.ships[class])
    fleet.ships[class] -= k
    taken[class] = k
  end
  local part = World.NewFleet(world, fleet.owner, fleet.system, taken)
  local share = if before > 0 then World.SupplyRate(part) / before else 0
  part.supply = fleet.supply * share
  fleet.supply -= part.supply
  return part
end

-- Fold one fleet into another in the same system.
function World.Merge(world: World, into: Fleet, fleet: Fleet)
  for class, count in fleet.ships do
    into.ships[class] += count
  end
  into.supply += fleet.supply
  into.kits += fleet.kits
  World.Disband(world, fleet)
end

-- The strength of one faction's fleets in a system.
function World.StrengthAt(world: World, system: number, owner: number): number
  local total = 0
  for _, id in world.systems[system].fleets do
    local fleet = world.fleets[id]
    if fleet.owner == owner then
      total += World.Strength(fleet)
    end
  end
  return total
end

-- A faction's whole active strength, wherever it is.
function World.Navy(world: World, owner: number): number
  local total = 0
  for _, id in world.fleetIds do
    local fleet = world.fleets[id]
    if fleet.owner == owner then
      total += World.FullStrength(fleet)
    end
  end
  return total
end

-- ---------------------------------------------------------------------
-- Systems

-- What a system's own defences are worth at full strength: its people's,
-- and a den's if one stands there.
function World.FullDefence(world: World, system: number): number
  local info = world.atlas.systems[system]
  local s = world.systems[system]
  local own = Powers.DEFENCE * math.sqrt(info.population) * (if info.home then Powers.DEFENCE_HOME else 1)
  if s.owner > 0 then
    own *= 0.5 + 0.5 * s.control
  end
  return own + (if s.den then Powers.DEN_DEFENCE else 0)
end

function World.Defence(world: World, system: number): number
  return World.FullDefence(world, system) * world.systems[system].defence
end

-- Who a system's defences fight for: its owner, the pirates if it is a
-- den nobody owns, or else nobody but themselves (0).
function World.Holder(world: World, system: number): number
  local s = world.systems[system]
  return if s.owner > 0 then s.owner elseif s.den then world.pirates else 0
end

-- What holding a system costs its owner an hour, were it to hold
-- 'count' systems in all.
function World.SovCost(world: World, faction: Faction, system: number, count: number): number
  local hops = math.max(0, faction.hops[system])
  return Powers.SOV_BASE * (1 + Powers.SOV_DISTANCE * hops) * (1 + (count / Powers.SOV_SCALE) ^ 2)
end

-- What one more system would add to the cost of those a faction already
-- holds, an hour. 'sov' is what they cost now.
function World.SovDearer(faction: Faction, sov: number): number
  local n = faction.systems
  return sov / (1 + (n / Powers.SOV_SCALE) ^ 2) * (2 * n + 1) / Powers.SOV_SCALE ^ 2
end

-- Is this system in the natural part of the map of some other power
-- that still lives?
function World.Foreign(world: World, system: number, faction: number): boolean
  local sphere = world.atlas.systems[system].owner
  return sphere > 0 and sphere ~= faction and world.factions[sphere].alive
end

-- What a system brings its owner an hour at a given hold on it.
function World.Yield(world: World, system: number, control: number): number
  local info = world.atlas.systems[system]
  return Powers.LEVY * Goods.SCALE * info.population * world.econ.nodes[system].met * control
end

local function hopsFrom(world: World, source: number): { number }
  return table.clone(Routes.For(world.galaxy).hops[source])
end

-- Hand a system to a faction (0: it becomes independent). The caller
-- reports it. A power that loses its capital moves it to the largest
-- system it has left; one with nothing left is finished.
function World.Transfer(world: World, system: number, to: number)
  local s = world.systems[system]
  local old = s.owner
  if old == to then
    return
  end
  s.owner = to
  s.control = if to > 0 then Powers.CONTROL_NEW else 0
  s.siege = nil
  if to > 0 then
    world.factions[to].systems += 1
  end
  if old > 0 then
    local faction = world.factions[old]
    faction.systems -= 1
    if faction.capital == system then
      local best, bestPeople = 0, -1
      for id, other in world.systems do
        if other.owner == old and world.atlas.systems[id].population > bestPeople then
          best, bestPeople = id, world.atlas.systems[id].population
        end
      end
      faction.capital = best
      if best > 0 then
        faction.hops = hopsFrom(world, best)
        -- Half of what was laid up at the old capital is lost with it.
        for class, count in faction.reserve do
          faction.reserve[class] = count // 2
        end
        World.Log(world, "capital", `{faction.name} moves its capital to {World.SystemName(world, best)}`, best, old)
      end
    end
    if faction.systems <= 0 and faction.alive then
      World.Eliminate(world, faction)
    end
  end
end

function World.Eliminate(world: World, faction: Faction)
  faction.alive = false
  faction.plan = nil
  for _, id in World.FleetIds(world) do
    local fleet = world.fleets[id]
    if fleet and fleet.owner == faction.id then
      World.Disband(world, fleet)
    end
  end
  for _, id in table.clone(world.actionIds) do
    local action = world.actions[id]
    if action and action.owner == faction.id then
      World.EndAction(world, action)
    end
  end
  for at = #world.wars, 1, -1 do
    local war = world.wars[at]
    if war.a == faction.id or war.b == faction.id then
      local other = world.factions[if war.a == faction.id then war.b else war.a]
      other.lastWarEnded = world.tick
      table.remove(world.wars, at)
    end
  end
  for _, s in world.systems do
    if s.siege and s.siege.by == faction.id then
      s.siege = nil
    end
  end
  for class in faction.reserve do
    faction.reserve[class] = 0
  end
  World.Count(world, "powers eliminated")
  World.Log(world, "eliminated", `{faction.name} is no more`, 0, faction.id)
end

-- ---------------------------------------------------------------------
-- A new world

function World.New(galaxy: Galaxy.Galaxy, atlas: Atlas.Atlas, history: number): World
  local rng = Rng.For(galaxy.seed, 3001)
  local routes = Routes.For(galaxy)
  local world: World = {
    seed = galaxy.seed, history = history, tick = 0,
    galaxy = galaxy, atlas = atlas, econ = Atlas.Economy(galaxy, atlas),
    factions = {}, pirates = 0, systems = {},
    fleets = {}, actions = {}, fleetIds = {}, actionIds = {}, timers = {}, wars = {},
    nextId = 0, ledger = Ledger.New(), news = {}, counters = {}, warnings = {}, loot = 0,
  }
  local count = #galaxy.systems
  local factionCount = #atlas.factions + 1

  for id = 1, count do
    world.systems[id] = {
      id = id, owner = 0, control = 0, pressure = 0, security = Powers.LOCAL_ORDER, den = false, defence = 1,
      fleets = {}, siege = nil, fighting = 0, raided = 0,
    }
  end

  local function newFaction(name: string, traits: Powers.Traits, pirate: boolean, capital: number)
    local id = #world.factions + 1
    table.insert(world.factions, {
      id = id, name = name, traits = traits, pirate = pirate, alive = true, capital = capital,
      credits = 0, systems = 0,
      relations = table.create(factionCount, 0), baseline = table.create(factionCount, 0),
      truce = table.create(factionCount, 0), stance = table.create(factionCount, 0),
      lastDeclared = -Powers.WAR_COOLDOWN, lastWarEnded = -Powers.WAR_COOLDOWN,
      policing = 1, reserve = table.create(#Powers.ships, 0),
      income = 0, costs = 0, arrears = 0, periods = 0, periodsInArrears = 0, plan = nil, earmark = 0,
      hops = if capital > 0 then hopsFrom(world, capital) else table.create(count, 0),
    })
  end
  for _, described in atlas.factions do
    local def = Powers.list[described.id]
    newFaction(def.name, def.traits, false, described.home)
  end
  newFaction(Powers.PIRATES, { aggressive = 1, greedy = 1, sociable = 0 }, true, 0)
  world.pirates = #world.factions

  -- Each power: its homeworld, its first fleet and its first money (a
  -- grant from the world, like everything it will later raise in taxes).
  for _, faction in world.factions do
    if faction.pirate then
      World.Pay(world, 0, faction.id, Powers.PIRATE_CREDITS, "founding")
    else
      local home = world.systems[faction.capital]
      home.owner = faction.id
      home.control = 1
      home.security = 1
      faction.systems = 1
      World.Pay(world, 0, faction.id, Powers.STARTING_CREDITS, "founding")
      World.NewFleet(world, faction.id, faction.capital, table.clone(Powers.HOME_FLEET))
    end
  end

  -- Relations: sociable pairs get on, aggressive pairs do not.
  for _, a in world.factions do
    for _, b in world.factions do
      if a.id < b.id then
        local baseline, value = -100, -100
        if not a.pirate and not b.pirate then
          baseline = Powers.Natural(a.traits, b.traits)
          value = baseline + Rng.Float(rng, -10, 10)
        end
        a.relations[b.id], b.relations[a.id] = value, value
        a.baseline[b.id], b.baseline[a.id] = baseline, baseline
      end
    end
  end

  -- Pirate dens: in systems outside every power's natural reach, the
  -- remotest first, spaced apart. Each has its band.
  local remote: { { id: number, hops: number } } = {}
  for id, info in atlas.systems do
    if info.owner == 0 then
      table.insert(remote, { id = id, hops = info.hops })
    end
  end
  table.sort(remote, function(p, q)
    if p.hops ~= q.hops then
      return p.hops > q.hops
    end
    return p.id < q.id
  end)
  local dens: { number } = {}
  for _, candidate in remote do
    if #dens >= Powers.DENS then
      break
    end
    local spaced = true
    for _, den in dens do
      if routes.hops[candidate.id][den] < Powers.DEN_SPACING then
        spaced = false
      end
    end
    if spaced then
      table.insert(dens, candidate.id)
      world.systems[candidate.id].den = true
      world.systems[candidate.id].pressure = 1
      local ships: { number } = table.create(#Powers.ships, 0)
      ships[1] = Powers.BAND
      World.NewFleet(world, world.pirates, candidate.id, ships)
    end
  end
  World.Count(world, "dens at start", #dens)
  return world
end

return World
