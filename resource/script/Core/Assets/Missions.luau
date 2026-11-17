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
-- for every two thousand credits of its pay (Missions.LOYALTY, times
-- Missions.PAY), and a faction's stations
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
-- A seventh has defence jobs, in the assaults' levels and on their
-- terms: a survey rig of the faction's to hold against the waves a
-- camp of the level would have, who come for it and do not wait their
-- turn. The rig standing when the last of them is destroyed, it is
-- paid, a quarter more than clearing a camp of them would be; the rig
-- destroyed, the job is lost at once, at the cost of having given it
-- up (Tactical/Assault, which it is an assault to: the aim "hold").
-- Every third job of theirs is an escort instead: a tender that flies
-- out from the middle of the place while the same waves come for it,
-- and is clear when it has got far enough out (the aim "escort").
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
-- takes. The third is more than a hauler holds, over six to twelve
-- jumps: several trips, or a freighter's one. The fourth is one of two
-- things, turn about by the roll: a freighter's hold over eight to
-- sixteen jumps; or a hauler's to a station that cannot be got to
-- without going through lawless space, which pays for the danger of
-- it.
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
local Sides = require("@lt/Core/Tactical/Sides")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")
local Ships = require("@lt/Core/Data/Ships")
local Types = require("@lt/Core/Data/Types")
local Wallet = require("@lt/Core/Assets/Wallet")

local Missions = {}

export type Event = { [string]: any }

Missions.OFFERS = 3
-- War work: how many jumps off a force of the station's faction may be
-- for its agent to have work at it; what a ship of the other force is
-- paid for, what a run through the blockade pays (for a hold of the
-- middle size), and what either does for the pilot's standing.
Missions.WAR_REACH = 6
-- (Five times what they were, 2026-11-16, when income came up. Mine.)
Missions.WAR_HEAD, Missions.WAR_RUN, Missions.WAR_STANDING = 400000, 150000, 0.4
-- (And how many times an escort's pay an escort to the front is paid.)
Missions.WAR_ESCORT = 1.5
-- The levels of the sixth agent's courier contracts: cubic metres of
-- sealed cargo (from 'least' to 'most', by 'step'), the jumps it is to
-- be carried ('near' to 'far'), and what it pays: so much, and so much
-- for each cubic metre carried a jump.
-- (Since 2026-11-16, when income came up, 3, 5, 10 and 20 times what they
-- were by level, so a freighter's run pays some ten to fifteen million.
-- Mine.)
Missions.RUNS = {
  { least = 30, most = 150, step = 10, near = 1, far = 3, base = 9000, rate = 75 },
  { least = 1000, most = 3000, step = 100, near = 5, far = 10, base = 50000, rate = 15 },
  { least = 6000, most = 12000, step = 500, near = 6, far = 12, base = 300000, rate = 15 },
  { least = 25000, most = 40000, step = 2500, near = 8, far = 16, base = 2000000, rate = 20 },
}
-- And the fourth level's other kind: a hauler's hold to a station that
-- only lawless space leads to, so many jumps off by the shortest way.
-- How often the fourth is that, where there is such a station.
Missions.WILD = { least = 500, most = 3000, step = 100, near = 3, far = 10, base = 3000000, rate = 240 }
Missions.WILD_CHANCE = 0.5
-- The standing a courier contract is worth, a level.
Missions.RUN_CREDIT = 0.1
Missions.IN_HAND = 5
Missions.CRATE = "cargo.sealed"
-- What every job's credits are multiplied by, whatever the job and
-- whoever gives it. (The owner, of a playtest, 2026-11-15: "jobs pay
-- far too little in credits. We could easily 5x the credit payouts and
-- still be under-powered. Frigates cost 400k+, so at 20k for starter
-- combat missions you'd be running 80 combat missions just to replace
-- one lost frigate (or buy a new one)." The figures below are what a
-- job paid before that, and are kept as they were: this is the one
-- number to change to pay more, or less.)
Missions.PAY = 5
-- Credits of a job's pay to a loyalty point, as its pay was before
-- Missions.PAY: what a job earns in points is not changed by it.
Missions.LOYALTY = 400
-- What a level of two of a pilot's crafts adds (Data/Skills): Hard
-- Bargaining to what a job pays, Patronage to the loyalty points it earns.
Missions.BARGAIN, Missions.PATRON = 0.03, 0.05
-- Ticks a job in hand may be kept before it lapses: three days.
Missions.LIMIT = 3 * math.ceil(86400 / Constants.TICK)
-- Ticks in the day a station's offers last.
local DAY = math.ceil(86400 / Constants.TICK)
-- What a pirate killed for a bounty job is worth, by how safe the
-- system is where it has to be done.
-- (Four times what they were, 2026-11-16, when income came up. Mine.)
local HEAD: { [string]: number } = { secure = 36000, low = 120000, lawless = 360000 }
local SUPPLIES = { "ore.ferrite", "ore.cuprite", "ore.silicate", "mineral.iron", "mineral.silicon", "mineral.copper" }

-- Whose line of work a job is: "assault", "defence", "mining" or
-- "courier" for the four agents whose work has levels (the fourth to
-- the seventh), and "" for one of the day's three. (A defence job is an
-- assault to the rules, with the aim "hold": Tactical/Assault.)
function Missions.Line(mission: State.Mission): string
  if mission.level <= 0 then
    return ""
  elseif mission.kind == "assault" and (mission.aim == "hold" or Assault.Tender(mission.aim) or mission.aim == "lost") then
    return "defence"
  end
  return mission.kind
end

-- Whether a defence job is an escort (a tender to see through, or in to
-- the station) and not a rig to hold: by what it is to do, or was, if it
-- is lost.
function Missions.Escort(mission: State.Mission): boolean
  return mission.kind == "assault" and (Assault.Tender(mission.aim) or (mission.aim == "lost" and Assault.Tender(mission.type)))
end

-- And whether it is a convoy: the tender is to be seen in to the
-- station the job is from.
function Missions.Convoy(mission: State.Mission): boolean
  return mission.kind == "assault" and (mission.aim == "convoy" or (mission.aim == "lost" and mission.type == "convoy"))
end

-- What an offer is called, for the lists.
function Missions.Title(mission: State.Mission): string
  if mission.kind == "bounty" and mission.type ~= "" then
    -- (war work: a strike against a faction's force at a front)
    local enemy = Factions.byId[mission.type]
    return `Strike: {mission.need} ships of the {if enemy then enemy.name else mission.type} force`
  elseif mission.kind == "courier" and mission.aim == "blockade" then
    return `Blockade run: {mission.need} m3 of sealed cargo`
  elseif mission.kind == "bounty" then
    return `Bounty: {mission.need} {if mission.need == 1 then "pirate" else "pirates"}`
  elseif Missions.Convoy(mission) then
    return `Convoy, level {mission.level}: a tender in past {(Assault.Count(mission.waves))}`
  elseif Missions.Escort(mission) and string.find(mission.key, ":war:", 1, true) then
    -- (war work: the escort is at the system the faction's force is at)
    return `Escort to the front, level {mission.level}: a tender past {(Assault.Count(mission.waves))}`
  elseif Missions.Escort(mission) then
    return `Escort, level {mission.level}: a tender past {(Assault.Count(mission.waves))}`
  elseif Missions.Line(mission) == "defence" then
    return `Defence, level {mission.level}: a rig against {mission.need}`
  elseif mission.kind == "assault" then
    local ships = Assault.Count(mission.waves)
    return `Assault, level {mission.level}: ` .. (if mission.aim == "chief" then "the chief of a camp"
      elseif mission.aim == "fetch" then `{mission.need} crates a camp took`
      elseif mission.aim == "raze" then (if mission.need == 1 then "a camp's store" else `a camp's {mission.need} works`)
      else `a camp of {ships}`)
  elseif mission.kind == "mining" then
    return `Mining, level {mission.level}: {mission.need} {Types.Info(mission.type).name}`
  elseif mission.kind == "courier" and mission.level > 0 then
    -- (a run through lawless space says so)
    return `Courier, level {mission.level}: {mission.need} m3` .. (if mission.aim == "wild" then ", lawless" else "")
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

-- How many jumps every system is from one by the shortest way,
-- whatever space it goes through. Kept as Missions.Reach is.
local anyway: { [Galaxy.Galaxy]: { [number]: Reached } } = setmetatable({}, { __mode = "k" }) :: any
local function shortest(galaxy: Galaxy.Galaxy, from: number): Reached
  local known: { [number]: Reached }? = anyway[galaxy]
  if known == nil then
    local fresh: { [number]: Reached } = {}
    anyway[galaxy] = fresh
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
      if far[next] == nil then
        far[next] = far[id] + 1
        table.insert(queue, next)
      end
    end
  end
  (known :: { [number]: Reached })[from] = far
  return far
end

local TRIES = 4

-- Where a run through lawless space from a system goes: a station that
-- cannot be got to without it, so many jumps off by the shortest way as
-- Missions.WILD says, and how many that is. Nil if there is none.
local function beyond(state: State.State, system: number, rng: Rng.Rng): (System.Object?, number)
  local held = Missions.Reach(state.galaxy, system)
  local far = shortest(state.galaxy, system)
  local within: { number } = {}
  for id = 1, #state.galaxy.systems do
    local jumps = far[id]
    if jumps and held[id] == nil and jumps >= Missions.WILD.near and jumps <= Missions.WILD.far then
      table.insert(within, id)
    end
  end
  local first = Rng.Int(rng, math.max(1, #within))
  for try = 1, math.min(TRIES, #within) do
    local id = within[(first + try - 1) % #within + 1]
    local there = stations(state, id)
    if #there > 0 then
      return there[Rng.Int(rng, #there) + 1], far[id]
    end
  end
  return nil, 0
end

-- Where a courier contract of a level from a station goes: a station
-- so many jumps off as the level says, by a way that keeps out of
-- lawless space, and how many jumps that is. With no such station in
-- the galaxy, the farthest there is short of it, if that is farther
-- than the level below begins; and for the first level, with nowhere
-- else, another station of the same system. Nil if there is nowhere.
local function destination(state: State.State, station: number, system: number, level: number, rng: Rng.Rng): (System.Object?, number)
  local run = Missions.RUNS[level]
  local far = Missions.Reach(state.galaxy, system)
  local within: { number } = {}
  local short: { number } = {}
  -- (short of it, but farther than the level below begins)
  local least = if level > 1 then math.min(run.near, Missions.RUNS[level - 1].near + 1) else 1
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
-- A people's own makes of module (Data/Modules), by the people: what
-- their agents now and then pay with. And how often.
local OWN: { [string]: { Modules.ModuleType } } = {}
for _, module in Modules.list do
  if module.meta == 3 and module.lineage then
    OWN[module.lineage] = OWN[module.lineage] or {}
    table.insert(OWN[module.lineage], module)
  end
end
Missions.PRIZE = 0.2

function Missions.Offers(state: State.State, station: number): { State.Mission }
  local object = Space.Object(state, station)
  if object == nil or object.kind ~= "station" or state.starbases[station] then
    return {}
  end
  local system = Space.SystemOf(state, station)
  local node = state.galaxy.systems[system]
  local day = state.tick // DAY
  -- (and what a pilot who has learned Hard Bargaining gets out of anybody)
  local factions = (1 + 0.03 * Missions.Standing(state, node.nearest)) * (1 + Missions.BARGAIN * math.max(0, state.skills["hard.bargaining"] or 0))
  -- (the loyalty points a job's pay earns: more for one who has learned Patronage)
  local function points(reward: number): number
    return math.max(1, math.floor(reward / (Missions.LOYALTY * Missions.PAY) * (1 + Missions.PATRON * math.max(0, state.skills.patronage or 0))))
  end
  -- (what an agent pays: Missions.PAY times what the job's figures come
  -- to, and more for the faction's standing and for their own regard)
  local function paying(slot: number): number
    return Missions.PAY * factions * (1 + Missions.REGARD.pay * math.max(0, Missions.Regard(state, station, slot)))
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
        mission.reward = math.floor((if far then 36000 else 16000) * (0.8 + mission.need / 200) * bonus)
        mission.standing = if far then 0.15 else 0.1
      else
        mission.kind = "supply"
        mission.type = SUPPLIES[Rng.Int(rng, #SUPPLIES) + 1]
        mission.need = 200 + 100 * Rng.Int(rng, 9)
        mission.reward = math.floor(mission.need * Types.Info(mission.type).basePrice * 1.5 * bonus)
        mission.standing = 0.1
      end
      mission.loyalty = points(mission.reward)
      table.insert(offers, mission)
    end
  end
  -- War work (Strategic/Wars; the project owner's ruling, 2026-11-14):
  -- where the faction whose station this is has a force at a system
  -- within a few jumps, besieging it or holding it against a siege, the
  -- first agent has a strike for the pilot (so many ships of the other
  -- force destroyed, at its lines: Tactical/Fronts) and, if there is a
  -- station there to carry to, a run through the blockade with sealed
  -- cargo. Of the nearest such system. They pay well, and the faction
  -- thinks the better of whoever does them.
  local front: State.Operation? = nil
  do
    local far = shortest(state.galaxy, system)
    local nearest: State.Operation? = nil
    for _, operation in state.wars.operations do
      local jumps = far[operation.system]
      if operation.stage ~= "muster" and jumps and jumps <= Missions.WAR_REACH and operation.against ~= ""
        and (operation.by == node.nearest or operation.against == node.nearest)
        and (nearest == nil or jumps < far[nearest.system]) then
        nearest = operation
      end
    end
    front = nearest
    if nearest then
      local enemy = if nearest.by == node.nearest then nearest.against else nearest.by
      local rng = Rng.For(state.historySeed, station, nearest.id, 89)
      local bonus = paying(1)
      local function work(what: string): State.Mission?
        local key = `{station}:war:{nearest.id}:{what}`
        if table.find(state.missionsTaken, key) then
          return nil
        end
        return {
          id = 0, key = key, kind = "bounty", station = station, faction = node.nearest, system = nearest.system, need = 1, done = 0,
          type = enemy, to = station, reward = 0, standing = Missions.WAR_STANDING, taken = 0,
          agent = Missions.Agent(state, station, 1), loyalty = 0, slot = 1,
          level = 0, waves = {}, wave = 0, site = 0, rooms = {}, ends = {}, aim = "", mark = 0,
        }
      end
      local strike = work("strike")
      if strike then
        strike.need = 2 + Rng.Int(rng, 3)
        strike.reward = math.floor(strike.need * Missions.WAR_HEAD * bonus)
        strike.loyalty = points(strike.reward)
        table.insert(offers, strike)
      end
      local there = stations(state, nearest.system)
      local run = if #there > 0 and nearest.system ~= system then work("run") else nil
      if run then
        run.kind, run.type, run.aim = "courier", Missions.CRATE, "blockade"
        run.to = there[Rng.Int(rng, #there) + 1].id
        run.need = 60 + 10 * Rng.Int(rng, 7)
        run.reward = math.floor(Missions.WAR_RUN * (0.8 + run.need / 200) * bonus)
        run.loyalty = points(run.reward)
        table.insert(offers, run)
      end
    end
  end
  -- The fourth agent's, and the fifth's: an assault and a mining
  -- contract at each level the pilot's standing opens, unless one of
  -- this station's of the kind is in hand already.
  local assaulting, digging, running, holding = false, false, false, false
  for _, id in state.missionIds do
    local held = state.missions[id]
    local line = Missions.Line(held)
    assaulting = assaulting or (line == "assault" and held.station == station)
    digging = digging or (line == "mining" and held.station == station)
    running = running or (line == "courier" and held.station == station)
    holding = holding or (line == "defence" and held.station == station)
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
        agent = Missions.Agent(state, station, Missions.OFFERS + 1), loyalty = points(reward),
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
        agent = Missions.Agent(state, station, Missions.OFFERS + 2), loyalty = points(reward),
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
    local spec = Missions.RUNS[level]
    local aim = "run"
    local to: System.Object?, jumps = nil, 0
    -- (the fourth level is now and then a run through lawless space, where there is anywhere it leads)
    if level == #Missions.RUNS and Rng.Chance(Rng.For(state.historySeed, station, run, 109), Missions.WILD_CHANCE) then
      to, jumps = beyond(state, system, rng)
      if to then
        spec, aim = Missions.WILD, "wild"
      end
    end
    if to == nil then
      to, jumps = destination(state, station, system, level, rng)
    end
    if to then
      local need = spec.least + spec.step * Rng.Int(rng, (spec.most - spec.least) // spec.step + 1)
      local reward = math.floor((spec.base + spec.rate * need * math.max(1, jumps)) * bonus)
      table.insert(offers, {
        id = 0, key = `{station}:c{run}:{level}`, kind = "courier", station = station, faction = node.nearest,
        system = Space.SystemOf(state, to.id), need = need, done = 0, type = Missions.CRATE, to = to.id, reward = reward,
        standing = Missions.RUN_CREDIT * level, taken = 0,
        agent = Missions.Agent(state, station, Missions.OFFERS + 3), loyalty = points(reward),
        slot = Missions.OFFERS + 3, level = level, waves = {}, wave = 0, site = 0, rooms = {}, ends = {}, aim = aim, mark = 0,
      })
    end
  end
  -- The seventh agent's: a defence job at each level the pilot's
  -- standing opens, unless one of this station's is in hand. A survey
  -- rig of the faction's, in this system or a neighbour's, and the
  -- waves a camp of the level would have coming for it, in the one place.
  local held = state.holds[station] or 0
  for level = 1, if holding then 0 else topOf(Missions.OFFERS + 4) do
    local bonus = paying(Missions.OFFERS + 4)
    local rng = Rng.For(state.historySeed, station, held, level, 127)
    -- (one time in three the rig is in a neighbour's system)
    local next = node.neighbors[Rng.Int(rng, math.max(1, #node.neighbors)) + 1]
    local where = if next ~= nil and Rng.Chance(rng, 1 / 3) and Assault.Room(state, next) then next else system
    local waves = Assault.Plan(rng, level)
    -- (every third job of theirs is an escort: a tender to see through,
    -- which is the one thing it counts; and every other one of those a
    -- convoy, whose tender is to be seen in to this station, or, from a
    -- neighbour's system, to the gate that leads here and through it:
    -- it counts getting away and getting in)
    local aim = if held % Assault.CONVOYS == Assault.CONVOYS - 1 and #waves >= 2 then "convoy"
      elseif held % Assault.ESCORTS == Assault.ESCORTS - 1 then "escort" else "hold"
    local pay, credit = Assault.Pay(level, waves, aim)
    local reward = math.floor(pay * bonus)
    if Assault.Room(state, where) then
      table.insert(offers, {
        id = 0, key = `{station}:h{held}:{level}`, kind = "assault", station = station, faction = node.nearest, system = where,
        need = if aim == "convoy" then 2 elseif aim == "escort" then 1 else (Assault.Count(waves)), done = 0, type = "", to = station,
        reward = reward,
        standing = credit, taken = 0,
        agent = Missions.Agent(state, station, Missions.OFFERS + 4), loyalty = points(reward),
        -- (a convoy's last wave is not for the place: it waits at the station)
        slot = Missions.OFFERS + 4, level = level, waves = waves, wave = 0, site = 0, rooms = {},
        ends = { if aim == "convoy" then #waves - 1 else #waves }, aim = aim,
        mark = 0,
      })
    end
  end
  -- War work, the third kind: an escort to the front. The seventh agent
  -- has a tender to be seen through at the system the faction's force
  -- is at: the job is their escort (Tactical/Assault), of the first or
  -- second level as the pilot's standing opens, and is paid more for
  -- where it is. (Who comes for the tender is who comes for any: the
  -- pirates a war draws. Not yet the other force's own ships.)
  if front and not holding and topOf(Missions.OFFERS + 4) >= 1 and Assault.Room(state, front.system) then
    local key = `{station}:war:{front.id}:escort`
    if not table.find(state.missionsTaken, key) then
      local level = math.min(2, topOf(Missions.OFFERS + 4))
      local waves = Assault.Plan(Rng.For(state.historySeed, station, front.id, 131), level)
      local pay, credit = Assault.Pay(level, waves, "escort")
      local reward = math.floor(pay * Missions.WAR_ESCORT * paying(Missions.OFFERS + 4))
      table.insert(offers, {
        id = 0, key = key, kind = "assault", station = station, faction = node.nearest, system = front.system, need = 1, done = 0,
        type = "", to = station, reward = reward, standing = math.max(credit, Missions.WAR_STANDING), taken = 0,
        agent = Missions.Agent(state, station, Missions.OFFERS + 4), loyalty = points(reward),
        slot = Missions.OFFERS + 4, level = level, waves = waves, wave = 0, site = 0, rooms = {}, ends = { #waves }, aim = "escort",
        mark = 0,
      })
    end
  end
  -- Now and then a job pays with one of the people's own makes of
  -- module in place of credits (the owner's, 2026-11-15): one job in
  -- five, where the people have a make worth about what the job pays,
  -- or somewhat more. (By a roll of its own, so that nothing else about
  -- the day's jobs is changed by it.)
  for _, offer in offers do
    local makes = OWN[offer.faction]
    if makes and offer.reward > 0 and Rng.Chance(Rng.For(state.historySeed, station, day, offer.slot, 151), Missions.PRIZE) then
      local fitting: { string } = {}
      for _, module in makes do
        if module.basePrice >= offer.reward * 0.8 and module.basePrice <= offer.reward * 2 then
          table.insert(fitting, module.id)
        end
      end
      if #fitting > 0 then
        offer.prize = fitting[Rng.Int(Rng.For(state.historySeed, station, day, offer.slot, 157), #fitting) + 1]
        offer.reward = 0
      end
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
  elseif mission.kind == "assault" and mission.aim == "lost" then
    return false, if Missions.Escort(mission) then "the tender is destroyed" else "the rig is destroyed"
  elseif mission.kind == "assault" and Assault.Tender(mission.aim) then
    if mission.done < mission.need then
      return false, if mission.aim == "convoy" then "the tender is still to see in" else "the tender is still to see through"
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
        elseif Assault.Warded(offer) then
          -- (the seventh agent's next is another; and where the rig is, is on the charts)
          state.holds[offer.station] = (state.holds[offer.station] or 0) + 1
          Assault.Open(state, offer, events)
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
    -- (or what it pays with: into the hangar there)
    if mission.prize and Types.Get(mission.prize) then
      Items.Add(state, mission.prize, 1, ship.docked, "hangar")
    end
    standing(state, mission.faction, mission.standing)
    -- (war work is serving a side: the other side of the war it was for
    -- thinks the worse of the pilot, and counts them its enemy while the
    -- war lasts: Tactical/Sides)
    local operation = tonumber(string.match(mission.key, ":war:(%d+):") or "")
    if operation then
      for _, each in state.wars.operations do
        if each.id == operation then
          local other = if each.by == mission.faction then each.against else each.by
          Sides.Serve(state, mission.faction, events)
          standing(state, other, -Sides.GRUDGE)
        end
      end
    end
    -- (and whoever gave it thinks the better of the pilot)
    regarded(state, mission, if mission.level > 0 then Missions.REGARD.levelled * (1 + mission.level) else Missions.REGARD.daily)
    state.loyalty[mission.faction] = (state.loyalty[mission.faction] or 0) + mission.loyalty
    close(state, mission)
    state.missionsDone += 1
    table.insert(events, { kind = "MissionCompleted", mission = mission.id, title = Missions.Title(mission), reward = mission.reward,
      prize = mission.prize,
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
-- given up. And at once: a defence job whose rig has been destroyed is
-- lost (Tactical/Assault marks it), as one given up is.
function Missions.Step(state: State.State, events: { Event })
  for _, id in table.clone(state.missionIds) do
    local mission = state.missions[id]
    if mission.kind == "assault" and mission.aim == "lost" then
      local title = Missions.Title(mission)
      Assault.Close(state, mission, events)
      standing(state, mission.faction, -2 * mission.standing)
      regarded(state, mission, -Missions.REGARD.lost)
      close(state, mission)
      table.insert(events, { kind = "MissionFailed", mission = mission.id, title = title })
    end
  end
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
Missions.HULL_POINTS = { frigate = 600, destroyer = 900, industrial = 900, cruiser = 1800, attackbattlecruiser = 2700,
  battlecruiser = 2700, battleship = 3600 } :: { [string]: number }
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
      -- (what only a drone or a fighter carries is not a thing a store sells drawings of)
      if module.tech == 2 and module.weapon and families[module.weapon.family] and blueprint and not module.internal then
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
