--!strict
-- Missions: work a station has for a pilot.
--
-- Every station that is not a pilot's own offers three jobs a day, each
-- one of three kinds:
--   - a bounty: destroy so many pirates in a system (the station's own
--     or a neighbour's), and come back to be paid;
--   - a courier run: carry sealed cargo to another station, in this
--     system or the next, and be paid there;
--   - a supply order: bring so much of an ore or a mineral to the
--     station, for half as much again as it is worth.
-- What is offered follows from the station and the day, so it is the
-- same however often it is asked for, and is not kept: only what a
-- pilot has taken on is. A pilot has at most five jobs in hand.
--
-- A pirate the pilot destroys in a bounty job's system counts toward it
-- (Tactical/Aftermath does the counting).
--
-- Finishing a job pays its reward and a little standing with the
-- faction whose station it was; abandoning one costs standing. Standing
-- runs from -10 to 10, and each point adds 3% to what that faction's
-- stations pay for a job.
--
-- Each job comes from somebody: a station has three agents, by name,
-- and each has one job a day. A job in hand has to be finished within
-- three days of being taken; one that is not lapses, at the cost in
-- standing of having given it up.
--
-- A finished job also earns loyalty points with the faction, a point
-- for every four hundred credits of its pay, and a faction's stations
-- have a store where they are spent (with some credits beside): on
-- datacores, on implants, and on the blueprints of the tech 2 makes of
-- the faction's own kinds of weapon, which are otherwise only to be
-- invented. What a store will let a pilot have follows from their
-- standing: datacores for anybody it does not think ill of, implants
-- at a standing of 1, blueprints at 2.
--
-- And a station has a fourth agent, whose work is of another kind: an
-- assault on a pirate camp, at a place made for the job (the rules of
-- it are Tactical/Assault's). It comes in levels, as many of them open
-- as the pilot's standing with the faction allows, each offered beside
-- the day's three; a pilot has one from a station at a time, and the
-- agent has another as soon as that is done with. The job there is to
-- clear the camp, to destroy its chief, or to bring back what it took.
--
-- A fifth agent has mining contracts, in the same levels and on the
-- same terms: so much of an ore to bring in, from a pocket of it made
-- for the contract and put on the charts when it is taken.
--
-- A sixth has courier contracts, in levels of their own: sealed cargo
-- to a station some jumps off, more of it and farther the higher the
-- level (Missions.RUNS). The first is a frigate's hold over one to
-- three jumps. The second is a hauler's over five to ten. Where it
-- goes is a station that can be got to without going through lawless
-- space, that many jumps off by such a way (the farthest there is, in
-- a galaxy too small to have one in reach), and it pays by the volume
-- and the jumps. The crates are handed over at the station the
-- contract is taken at, and can be carried in as many trips as it
-- takes. (Two levels so far. The harder ones are for holds nobody has
-- yet, or for runs through lawless space.)
--
-- And each agent has a regard of their own for the pilot, beside what
-- their faction thinks: nothing to begin with, more with every job of
-- theirs that is finished (half a point for one of the day's; a
-- quarter and a quarter a level for an assault or a contract), a point
-- less for one given up or let lapse, from -5 to 10. An agent pays a
-- pilot they think well of more (2% a point, over what the faction's
-- standing adds); and the fourth and the fifth open their harder
-- levels to a pilot they know, whatever the faction makes of them: the
-- second at a regard of 2, the third at 5, the fourth at 8. So the
-- levels can be had by going from station to station doing a little
-- for everybody, or by staying with one agent and doing a lot.
--
-- (A first version of the roadmap's agents. Not yet: jobs made from
-- what the simulation needs.)

local Assault = require("@lt/Core/Tactical/Assault")
local Constants = require("@lt/Core/Data/Constants")
local Factions = require("@lt/Core/Data/Factions")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Blueprints = require("@lt/Core/Data/Blueprints")
local Implants = require("@lt/Core/Data/Implants")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Names = require("@lt/Core/Describe/Names")
local Rng = require("@lt/Core/Kernel/Rng")
local Space = require("@lt/Core/Tactical/Space")
local Standings = require("@lt/Core/Assets/Standings")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")
local Ships = require("@lt/Core/Data/Ships")
local Types = require("@lt/Core/Data/Types")
local Wallet = require("@lt/Core/Assets/Wallet")

local Missions = {}

export type Event = { [string]: any }

Missions.OFFERS = 3
-- The levels of the sixth agent's courier contracts: cubic metres of
-- sealed cargo (from 'least' to 'most', by 'step'), the jumps it is to
-- be carried ('near' to 'far'), and what it pays: so much, and so much
-- for each cubic metre carried a jump.
Missions.RUNS = {
  { least = 30, most = 150, step = 10, near = 1, far = 3, base = 3000, rate = 25 },
  { least = 1000, most = 3000, step = 100, near = 5, far = 10, base = 10000, rate = 3 },
}
-- The standing a courier contract is worth, a level.
Missions.RUN_CREDIT = 0.1
Missions.IN_HAND = 5
Missions.CRATE = "cargo.sealed"
-- Credits of a job's pay to a loyalty point.
Missions.LOYALTY = 400
-- Ticks a job in hand may be kept before it lapses: three days.
Missions.LIMIT = 3 * math.ceil(86400 / Constants.TICK)
-- Ticks in the day a station's offers last.
local DAY = math.ceil(86400 / Constants.TICK)
-- What a pirate killed for a bounty job is worth, by how safe the
-- system is where it has to be done.
local HEAD: { [string]: number } = { secure = 9000, low = 30000, lawless = 90000 }
local SUPPLIES = { "ore.ferrite", "ore.cuprite", "ore.silicate", "mineral.iron", "mineral.silicon", "mineral.copper" }

-- What an offer is called, for the lists.
function Missions.Title(mission: State.Mission): string
  if mission.kind == "bounty" then
    return `Bounty: {mission.need} {if mission.need == 1 then "pirate" else "pirates"}`
  elseif mission.kind == "assault" then
    local ships = Assault.Count(mission.waves)
    return `Assault, level {mission.level}: ` .. (if mission.aim == "chief" then "the chief of a camp"
      elseif mission.aim == "fetch" then `{mission.need} crates a camp took`
      elseif mission.aim == "raze" then (if mission.need == 1 then "a camp's store" else `a camp's {mission.need} works`)
      else `a camp of {ships}`)
  elseif mission.kind == "mining" then
    return `Mining, level {mission.level}: {mission.need} {Types.Info(mission.type).name}`
  elseif mission.kind == "courier" and mission.level > 0 then
    return `Courier, level {mission.level}: {mission.need} m3`
  elseif mission.kind == "courier" then
    return `Courier: {mission.need} m3 of sealed cargo`
  end
  return `Supply: {mission.need} {Types.Info(mission.type).name}`
end

-- A pilot's standing with a faction, from -10 to 10 (Assets/Standings).
function Missions.Standing(state: State.State, faction: string): number
  return Standings.Of(state, faction)
end

local function stations(state: State.State, system: number): { System.Object }
  local found: { System.Object } = {}
  for _, object in Space.Describe(state, system).objects do
    if object.kind == "station" and state.starbases[object.id] == nil then
      table.insert(found, object)
    end
  end
  return found
end

-- How many jumps every system is from one, by ways that keep out of
-- lawless space (a system not in the list cannot be got to so). Worked
-- out once for each system of a galaxy and kept: a galaxy does not
-- change.
type Reached = { [number]: number }
local reaches: { [Galaxy.Galaxy]: { [number]: Reached } } = setmetatable({}, { __mode = "k" }) :: any
function Missions.Reach(galaxy: Galaxy.Galaxy, from: number): Reached
  local known: { [number]: Reached }? = reaches[galaxy]
  if known == nil then
    local fresh: { [number]: Reached } = {}
    reaches[galaxy] = fresh
    known = fresh
  end
  local kept: Reached? = (known :: { [number]: Reached })[from]
  if kept then
    return kept
  end
  local far: Reached = { [from] = 0 }
  local queue = { from }
  local at = 1
  while at <= #queue do
    local id = queue[at]
    at += 1
    for _, next in galaxy.systems[id].neighbors do
      if far[next] == nil and Galaxy.Band(galaxy.systems[next].security) ~= "lawless" then
        far[next] = far[id] + 1
        table.insert(queue, next)
      end
    end
  end
  (known :: { [number]: Reached })[from] = far
  return far
end

-- How many jumps a courier job's cargo is carried: by the way that
-- keeps out of lawless space, or by the shortest if there is no such.
function Missions.Jumps(state: State.State, mission: State.Mission): number
  local from, to = Space.SystemOf(state, mission.station), Space.SystemOf(state, mission.to)
  return Missions.Reach(state.galaxy, from)[to] or math.max(0, #Galaxy.Route(state.galaxy, from, to) - 1)
end

-- Where a courier contract of a level from a station goes: a station
-- so many jumps off as the level says, by a way that keeps out of
-- lawless space, and how many jumps that is. With no such station in
-- the galaxy, the farthest there is short of it, if that is farther
-- than the level below goes; and for the first level, with nowhere
-- else, another station of the same system. Nil if there is nowhere.
local TRIES = 4
local function destination(state: State.State, station: number, system: number, level: number, rng: Rng.Rng): (System.Object?, number)
  local run = Missions.RUNS[level]
  local far = Missions.Reach(state.galaxy, system)
  local within: { number } = {}
  local short: { number } = {}
  local least = if level > 1 then Missions.RUNS[level - 1].far + 1 else 1
  for id = 1, #state.galaxy.systems do
    local jumps = far[id]
    if jumps and jumps >= run.near and jumps <= run.far then
      table.insert(within, id)
    elseif jumps and jumps >= least and jumps < run.near then
      table.insert(short, id)
    end
  end
  -- (the farthest first, and of those as far the lower-numbered)
  table.sort(short, function(a: number, b: number): boolean
    if far[a] ~= far[b] then
      return far[a] > far[b]
    end
    return a < b
  end)
  -- Some of those the right way off, from wherever the roll says, until one has a station.
  local first = Rng.Int(rng, math.max(1, #within))
  for try = 1, math.min(TRIES, #within) do
    local id = within[(first + try - 1) % #within + 1]
    local there = stations(state, id)
    if #there > 0 then
      return there[Rng.Int(rng, #there) + 1], far[id]
    end
  end
  for try = 1, math.min(TRIES, #short) do
    local there = stations(state, short[try])
    if #there > 0 then
      return there[Rng.Int(rng, #there) + 1], far[short[try]]
    end
  end
  if level == 1 then
    local here: { System.Object } = {}
    for _, object in stations(state, system) do
      if object.id ~= station then
        table.insert(here, object)
      end
    end
    if #here > 0 then
      return here[Rng.Int(rng, #here) + 1], 0
    end
  end
  return nil, 0
end

-- Who at a station gives its nth job of the day: the same person every
-- day, for as long as the galaxy lasts.
function Missions.Agent(state: State.State, station: number, slot: number): string
  return Names.Person(Rng.For(state.galaxySeed, station, slot, 71))
end

-- An agent's own regard for the pilot: what a finished job of the day's
-- adds to it, what one with levels adds (and that again for each
-- level), what one given up or let lapse takes, how far it goes either
-- way, the share more an agent pays for each point of it, and the
-- regard at which each level of an assault or a contract is opened.
Missions.REGARD = { daily = 0.5, levelled = 0.25, lost = 1, least = -5, most = 10, pay = 0.02 }
Missions.OPENS = { 0, 2, 5, 8 }

-- What an agent thinks of the pilot ('slot': which of the station's
-- agents; 0, of a job from before they had a regard, is nobody).
function Missions.Regard(state: State.State, station: number, slot: number): number
  return state.regard[`{station}:{slot}`] or 0
end

local function regarded(state: State.State, mission: State.Mission, change: number)
  if mission.slot > 0 then
    local key = `{mission.station}:{mission.slot}`
    state.regard[key] = math.clamp((state.regard[key] or 0) + change, Missions.REGARD.least, Missions.REGARD.most)
  end
end

-- The hardest level an agent's regard opens by itself.
local function known(regard: number): number
  local top = 0
  for level, wanted in Missions.OPENS do
    if regard >= wanted then
      top = level
    end
  end
  return top
end

-- The key of an offer: its station, day and place in the list.
local function keyOf(station: number, day: number, slot: number): string
  return `{station}:{day}:{slot}`
end

-- What a station offers today, less what has been taken. Each is a
-- mission as it would be if taken (its id is 0 until it is).
function Missions.Offers(state: State.State, station: number): { State.Mission }
  local object = Space.Object(state, station)
  if object == nil or object.kind ~= "station" or state.starbases[station] then
    return {}
  end
  local system = Space.SystemOf(state, station)
  local node = state.galaxy.systems[system]
  local day = state.tick // DAY
  local factions = 1 + 0.03 * Missions.Standing(state, node.nearest)
  -- (what an agent pays: for the faction's standing, and for their own regard)
  local function paying(slot: number): number
    return factions * (1 + Missions.REGARD.pay * math.max(0, Missions.Regard(state, station, slot)))
  end
  local offers: { State.Mission } = {}
  for slot = 1, Missions.OFFERS do
    local bonus = paying(slot)
    local key = keyOf(station, day, slot)
    if not table.find(state.missionsTaken, key) then
      local rng = Rng.For(state.historySeed, station, day, slot, 83)
      local mission: State.Mission = {
        id = 0, key = key, kind = "bounty", station = station, faction = node.nearest, system = system, need = 1, done = 0,
        type = "", to = station, reward = 0, standing = 0.1, taken = 0,
        agent = Missions.Agent(state, station, slot), loyalty = 0, slot = slot,
        level = 0, waves = {}, wave = 0, site = 0, rooms = {}, ends = {}, aim = "", mark = 0,
      }
      local roll = Rng.Int(rng, 3)
      -- (a neighbour's station, for a courier run that is a jump)
      local next = node.neighbors[Rng.Int(rng, #node.neighbors) + 1]
      local here, there = stations(state, system), if next then stations(state, next) else {}
      if roll == 0 or (roll == 1 and #here < 2 and #there == 0) then
        -- Where order is thinner next door, the bounty may be for there.
        local wilder = next ~= nil and state.galaxy.systems[next].security < node.security and Rng.Chance(rng, 0.5)
        mission.system = if wilder then next else system
        mission.need = 1 + Rng.Int(rng, 3)
        local band = Galaxy.Band(state.galaxy.systems[mission.system].security)
        mission.reward = math.floor(mission.need * HEAD[band] * bonus)
        mission.standing = if band == "secure" then 0.1 elseif band == "low" then 0.2 else 0.4
      elseif roll == 1 then
        mission.kind = "courier"
        local far = #there > 0 and (#here < 2 or Rng.Chance(rng, 0.5))
        local choices = if far then there else here
        local to = choices[Rng.Int(rng, #choices) + 1]
        if to.id == station then
          to = choices[(table.find(choices, to) :: number) % #choices + 1]
        end
        mission.to = to.id
        mission.type = Missions.CRATE
        mission.need = 40 + 10 * Rng.Int(rng, 8)
        mission.reward = math.floor((if far then 9000 else 4000) * (0.8 + mission.need / 200) * bonus)
        mission.standing = if far then 0.15 else 0.1
      else
        mission.kind = "supply"
        mission.type = SUPPLIES[Rng.Int(rng, #SUPPLIES) + 1]
        mission.need = 200 + 100 * Rng.Int(rng, 9)
        mission.reward = math.floor(mission.need * Types.Info(mission.type).basePrice * 1.5 * bonus)
        mission.standing = 0.1
      end
      mission.loyalty = math.max(1, mission.reward // Missions.LOYALTY)
      table.insert(offers, mission)
    end
  end
  -- The fourth agent's, and the fifth's: an assault and a mining
  -- contract at each level the pilot's standing opens, unless one of
  -- this station's of the kind is in hand already.
  local assaulting, digging, running = false, false, false
  for _, id in state.missionIds do
    local held = state.missions[id]
    assaulting = assaulting or (held.kind == "assault" and held.station == station)
    digging = digging or (held.kind == "mining" and held.station == station)
    running = running or (held.kind == "courier" and held.level > 0 and held.station == station)
  end
  -- (as many levels as the faction's standing opens, or as the agent's
  -- own regard does, whichever is more; none from an agent whose
  -- faction thinks too ill of the pilot to give any)
  local standingTop = Assault.Top(Missions.Standing(state, node.nearest))
  local function topOf(slot: number): number
    return if standingTop == 0 then 0 else math.max(standingTop, known(Missions.Regard(state, station, slot)))
  end
  local given = state.assaults[station] or 0
  for level = 1, if assaulting then 0 else topOf(Missions.OFFERS + 1) do
    local bonus = paying(Missions.OFFERS + 1)
    local rng = Rng.For(state.historySeed, station, given, level, 89)
    -- (two times in five the camp is in a neighbour's system)
    local next = node.neighbors[Rng.Int(rng, math.max(1, #node.neighbors)) + 1]
    local where = if next ~= nil and Rng.Chance(rng, 0.4) then next else system
    if not Assault.Room(state, where) then
      where = system
    end
    local waves = Assault.Plan(rng, level)
    local ends, aim = Assault.Shape(rng, level)
    local pay, credit = Assault.Pay(level, waves, aim)
    local reward = math.floor(pay * bonus)
    if Assault.Room(state, where) then
      table.insert(offers, {
        id = 0, key = `{station}:a{given}:{level}`, kind = "assault", station = station, faction = node.nearest, system = where,
        need = Assault.Need(aim, level, waves), done = 0, type = if aim == "fetch" then Assault.LOOT else "", to = station,
        reward = reward, standing = credit, taken = 0,
        agent = Missions.Agent(state, station, Missions.OFFERS + 1), loyalty = math.max(1, reward // Missions.LOYALTY),
        slot = Missions.OFFERS + 1, level = level, waves = waves, wave = 0, site = 0, rooms = {}, ends = ends, aim = aim, mark = 0,
      })
    end
  end
  local dug = state.digs[station] or 0
  for level = 1, if digging then 0 else topOf(Missions.OFFERS + 2) do
    local bonus = paying(Missions.OFFERS + 2)
    local rng = Rng.For(state.historySeed, station, dug, level, 101)
    -- (one time in three the pocket is in a neighbour's system)
    local next = node.neighbors[Rng.Int(rng, math.max(1, #node.neighbors)) + 1]
    local where = if next ~= nil and Rng.Chance(rng, 1 / 3) and Assault.Room(state, next) then next else system
    local ore, units, pack = Assault.Dig(rng, level)
    local pay, credit = Assault.DigPay(level, ore, units)
    local reward = math.floor(pay * bonus)
    if Assault.Room(state, where) then
      table.insert(offers, {
        id = 0, key = `{station}:d{dug}:{level}`, kind = "mining", station = station, faction = node.nearest, system = where,
        need = units, done = 0, type = ore, to = station, reward = reward, standing = credit, taken = 0,
        agent = Missions.Agent(state, station, Missions.OFFERS + 2), loyalty = math.max(1, reward // Missions.LOYALTY),
        slot = Missions.OFFERS + 2, level = level, waves = if #pack > 0 then { pack } else {}, wave = 0, site = 0, rooms = {},
        ends = { if #pack > 0 then 1 else 0 }, aim = "dig", mark = 0,
      })
    end
  end
  -- The sixth agent's: a courier contract at each level there is that
  -- the pilot's standing opens, unless one of this station's is in hand.
  local run = state.couriers[station] or 0
  for level = 1, if running then 0 else math.min(#Missions.RUNS, topOf(Missions.OFFERS + 3)) do
    local bonus = paying(Missions.OFFERS + 3)
    local rng = Rng.For(state.historySeed, station, run, level, 107)
    local to, jumps = destination(state, station, system, level, rng)
    if to then
      local spec = Missions.RUNS[level]
      local need = spec.least + spec.step * Rng.Int(rng, (spec.most - spec.least) // spec.step + 1)
      local reward = math.floor((spec.base + spec.rate * need * math.max(1, jumps)) * bonus)
      table.insert(offers, {
        id = 0, key = `{station}:c{run}:{level}`, kind = "courier", station = station, faction = node.nearest,
        system = Space.SystemOf(state, to.id), need = need, done = 0, type = Missions.CRATE, to = to.id, reward = reward,
        standing = Missions.RUN_CREDIT * level, taken = 0,
        agent = Missions.Agent(state, station, Missions.OFFERS + 3), loyalty = math.max(1, reward // Missions.LOYALTY),
        slot = Missions.OFFERS + 3, level = level, waves = {}, wave = 0, site = 0, rooms = {}, ends = {}, aim = "run", mark = 0,
      })
    end
  end
  return offers
end

-- The jobs in hand, oldest first.
function Missions.InHand(state: State.State): { State.Mission }
  local found: { State.Mission } = {}
  for _, id in state.missionIds do
    table.insert(found, state.missions[id])
  end
  return found
end

-- How many of a type a docked ship has to hand: in its hold and in the
-- hangar of the station it is at.
function Missions.ToHand(state: State.State, ship: State.Ship, type: string): number
  local have = 0
  for _, item in Items.In(state, ship.id, "cargo") do
    have += if item.type == type then item.quantity else 0
  end
  for _, item in Items.In(state, ship.docked, "hangar") do
    have += if item.type == type and item.slot == 0 then item.quantity else 0
  end
  return have
end

-- Take 'quantity' of a type from what a docked ship has to hand.
function Missions.Hand(state: State.State, ship: State.Ship, type: string, quantity: number)
  for _, place in { { ship.id, "cargo" }, { ship.docked, "hangar" } } :: { { any } } do
    for _, item in Items.In(state, place[1], place[2]) do
      if quantity > 0 and item.type == type and item.slot == 0 then
        local take = math.min(quantity, item.quantity)
        Items.Take(state, item, take)
        quantity -= take
      end
    end
  end
end

-- Where a job is finished, and whether it can be finished now by a ship
-- docked there; if not, why not.
function Missions.Ready(state: State.State, ship: State.Ship, mission: State.Mission): (boolean, string?)
  local where = if mission.kind == "courier" then mission.to else mission.station
  if ship.docked ~= where then
    local object = Space.Object(state, where)
    return false, `finish it at {if object then object.name else "its station"}`
  elseif mission.kind == "assault" and mission.aim == "chief" then
    if mission.done < mission.need then
      return false, "the camp's chief is still to destroy"
    end
  elseif mission.kind == "bounty" or (mission.kind == "assault" and mission.aim ~= "fetch") then
    if mission.done < mission.need then
      return false, `{mission.need - mission.done} still to destroy`
    end
  elseif Missions.ToHand(state, ship, mission.type) < mission.need then
    return false, `{mission.need - Missions.ToHand(state, ship, mission.type)} more to bring`
  end
  return true
end

function Missions.Validate(state: State.State, command: State.Command): (boolean, string?)
  local ship = state.ships[command.actor]
  if ship == nil then
    return false, "no such ship"
  elseif ship.docked == 0 then
    return false, "not docked"
  end
  local kind = command.kind
  if kind == "RedeemLoyalty" then
    local offer, faction = Missions.Stocked(state, ship.docked, command.type or "")
    local quantity = command.quantity or 1
    if offer == nil then
      return false, "this station's store has no such thing"
    elseif quantity < 1 or quantity % 1 ~= 0 then
      return false, "how many?"
    elseif Standings.Of(state, faction) < offer.standing then
      return false, `needs a standing of {offer.standing} with them`
    elseif (state.loyalty[faction] or 0) < offer.points * quantity then
      return false, `needs {offer.points * quantity} loyalty points`
    elseif state.wallet < offer.credits * quantity then
      return false, "not enough credits"
    end
    return true
  elseif kind == "AcceptMission" then
    for _, offer in Missions.Offers(state, ship.docked) do
      if offer.key == command.what then
        if #state.missionIds >= Missions.IN_HAND then
          return false, `a pilot has {Missions.IN_HAND} jobs in hand at most`
        end
        return true
      end
    end
    return false, "no such job is offered here"
  end
  local mission = state.missions[command.target or 0]
  if mission == nil then
    return false, "no such job in hand"
  elseif kind == "CompleteMission" then
    return Missions.Ready(state, ship, mission)
  elseif kind == "AbandonMission" then
    return true
  end
  return false, `unknown command '{kind}'`
end

local function close(state: State.State, mission: State.Mission)
  state.missions[mission.id] = nil
  State.RemoveId(state.missionIds, mission.id)
end

local function standing(state: State.State, faction: string, change: number)
  Standings.Change(state, faction, change)
end

function Missions.Apply(state: State.State, command: State.Command, events: { Event })
  local ship = state.ships[command.actor]
  local kind = command.kind
  if kind == "RedeemLoyalty" then
    local offer, faction = Missions.Stocked(state, ship.docked, command.type :: string)
    local quantity = command.quantity or 1
    if offer then
      state.loyalty[faction] = (state.loyalty[faction] or 0) - offer.points * quantity
      Wallet.Pay(state, -offer.credits * quantity, "loyalty store", events)
      Items.Add(state, offer.type, quantity, ship.docked, "hangar")
      table.insert(events, { kind = "LoyaltyRedeemed", type = offer.type, quantity = quantity, faction = faction,
        points = offer.points * quantity, left = state.loyalty[faction] })
    end
    return
  elseif kind == "AcceptMission" then
    for _, offer in Missions.Offers(state, ship.docked) do
      if offer.key == command.what then
        offer.id = State.NewId(state)
        offer.taken = state.tick
        state.missions[offer.id] = offer
        table.insert(state.missionIds, offer.id)
        table.insert(state.missionsTaken, offer.key)
        -- (yesterday's offers are gone: so is the list of which were taken)
        local day = `:{state.tick // DAY}:`
        for index = #state.missionsTaken, 1, -1 do
          if not string.find(state.missionsTaken[index], day, 1, true) then
            table.remove(state.missionsTaken, index)
          end
        end
        if offer.kind == "courier" then
          Items.Add(state, Missions.CRATE, offer.need, ship.docked, "hangar")
          -- (the sixth agent's next is another contract)
          if offer.level > 0 then
            state.couriers[offer.station] = (state.couriers[offer.station] or 0) + 1
          end
        elseif offer.kind == "assault" then
          -- (the agent's next is another job; and the camp is on the charts)
          state.assaults[offer.station] = (state.assaults[offer.station] or 0) + 1
          Assault.Open(state, offer, events)
        elseif offer.kind == "mining" then
          state.digs[offer.station] = (state.digs[offer.station] or 0) + 1
          Assault.Open(state, offer, events)
        end
        table.insert(events, { kind = "MissionAccepted", mission = offer.id, title = Missions.Title(offer) })
      end
    end
    return
  end
  local mission = state.missions[command.target :: number]
  if kind == "CompleteMission" then
    if mission.kind == "assault" then
      -- (what the camp took is handed over, where that was the job)
      if mission.aim == "fetch" then
        Missions.Hand(state, ship, mission.type, mission.need)
      end
    elseif mission.kind ~= "bounty" then
      Missions.Hand(state, ship, mission.type, mission.need)
    end
    -- (a place made for the job goes with it)
    Assault.Close(state, mission, events)
    Wallet.Pay(state, mission.reward, "mission reward", events)
    standing(state, mission.faction, mission.standing)
    -- (and whoever gave it thinks the better of the pilot)
    regarded(state, mission, if mission.level > 0 then Missions.REGARD.levelled * (1 + mission.level) else Missions.REGARD.daily)
    state.loyalty[mission.faction] = (state.loyalty[mission.faction] or 0) + mission.loyalty
    close(state, mission)
    state.missionsDone += 1
    table.insert(events, { kind = "MissionCompleted", mission = mission.id, title = Missions.Title(mission), reward = mission.reward,
      faction = mission.faction, standing = Missions.Standing(state, mission.faction), loyalty = mission.loyalty,
      agent = mission.agent, regard = Missions.Regard(state, mission.station, mission.slot) })
  elseif kind == "AbandonMission" then
    -- (a courier's cargo goes back, as much of it as is to hand; and so
    -- does what was fetched from a camp)
    if mission.kind == "courier" or (mission.kind == "assault" and mission.aim == "fetch") then
      Missions.Hand(state, ship, mission.type, math.min(mission.need, Missions.ToHand(state, ship, mission.type)))
    end
    Assault.Close(state, mission, events)
    standing(state, mission.faction, -2 * mission.standing)
    regarded(state, mission, -Missions.REGARD.lost)
    close(state, mission)
    table.insert(events, { kind = "MissionAbandoned", mission = mission.id, title = Missions.Title(mission) })
  end
end

-- Once a minute: a job kept past its time lapses, as if it had been
-- given up.
function Missions.Step(state: State.State, events: { Event })
  if state.tick % 60 ~= 0 then
    return
  end
  for _, id in table.clone(state.missionIds) do
    local mission = state.missions[id]
    if state.tick - mission.taken > Missions.LIMIT then
      Assault.Close(state, mission, events)
      standing(state, mission.faction, -2 * mission.standing)
      regarded(state, mission, -Missions.REGARD.lost)
      close(state, mission)
      table.insert(events, { kind = "MissionExpired", mission = mission.id, title = Missions.Title(mission) })
    end
  end
end

-- The seconds a job in hand has left before it lapses.
function Missions.Left(state: State.State, mission: State.Mission): number
  return math.max(0, Missions.LIMIT - (state.tick - mission.taken)) * Constants.TICK
end

-- What a faction's store lets a pilot have, for so many loyalty points
-- and so many credits, at a standing of at least so much.
export type Stock = { type: string, points: number, credits: number, standing: number }

local stores: { [string]: { Stock } } = {}

-- A faction's store: a datacore, the implants, the blueprints of the
-- tech 2 makes of its own kinds of weapon, and, for a pilot it thinks
-- well of, those of the tech 2 makes of its own hulls.
Missions.HULL_POINTS = { frigate = 600, destroyer = 900, industrial = 900, cruiser = 1800, battleship = 3600 } :: { [string]: number }
function Missions.Store(faction: string): { Stock }
  local made = stores[faction]
  if made then
    return made
  end
  local own = Factions.byId[faction]
  local stock: { Stock } = {}
  if own and own.kind == "human" then
    table.insert(stock, { type = "datacore", points = 50, credits = 5000, standing = 0 })
    for _, implant in Implants.list do
      table.insert(stock, { type = implant.id, points = 120 * implant.slot, credits = Implants.Price(implant) // 2, standing = 1 })
    end
    local families: { [string]: boolean } = { [own.weapon] = true, missile = own.launchers >= 0.3 }
    for _, module in Modules.list do
      local blueprint = Blueprints.byProduct[module.id]
      if module.tech == 2 and module.weapon and families[module.weapon.family] and blueprint then
        table.insert(stock, { type = blueprint.id, points = math.ceil(module.basePrice / 400), credits = 0, standing = 2 })
      end
    end
    for _, hull in Ships.list do
      local blueprint = Blueprints.byProduct[hull.id]
      local points = Missions.HULL_POINTS[hull.class]
      if hull.tech == 2 and hull.lineage == faction and blueprint and points then
        table.insert(stock, { type = blueprint.id, points = points, credits = hull.basePrice // 20, standing = 3 })
      end
    end
  end
  stores[faction] = stock
  return stock
end

-- What a station's store has of a type, and whose store it is. Nothing
-- at a pilot's own starbase, or for a type it does not keep.
function Missions.Stocked(state: State.State, station: number, type: string): (Stock?, string)
  local object = Space.Object(state, station)
  if object == nil or object.kind ~= "station" or state.starbases[station] then
    return nil, ""
  end
  local faction = state.galaxy.systems[Space.SystemOf(state, station)].nearest
  for _, stock in Missions.Store(faction) do
    if stock.type == type then
      return stock, faction
    end
  end
  return nil, faction
end

-- The name of the faction a job is for.
function Missions.For(mission: State.Mission): string
  local faction = Factions.byId[mission.faction]
  return if faction then faction.name else "nobody"
end

return Missions
