--!strict
-- The universe simulation. Each tick has three phases:
--   1. resolve: timers due this tick complete (jumps, battles, captures,
--      convoys, ships built), stations produce, and every period upkeep,
--      taxes and relations update
--   2. action: every faction reviews the state and submits actions
--   3. reaction: every faction responds to the others' actions in progress
-- Battles outside the player's system use the abstract combat model.

local Actions = require("@lt/Sim/Actions")
local Ai = require("@lt/Sim/Ai")
local Combat = require("@lt/Sim/Combat")
local Data = require("@lt/Sim/Data")
local Galaxy = require("@lt/Sim/Galaxy")
local Market = require("@lt/Sim/Market")
local Rng = require("@lt/Sim/Rng")
local State = require("@lt/Sim/State")

local Sim = {}

-- A new universe. 'galaxySeed' fixes the galaxy and starting setup;
-- 'historySeed' drives the rolls during play and is picked fresh when
-- not given.
function Sim.New(galaxySeed: number, systemCount: number, historySeed: number?): State.State
  local history = historySeed or Rng.Int(Rng.For(os.time(), math.floor(os.clock() * 1000000)), 2147483647)
  return State.New(Galaxy.Describe(galaxySeed, systemCount), galaxySeed, history)
end

local function name(state: State.State, faction: number?): string
  return if faction then state.factions[faction].name else "independents"
end

local function systemName(state: State.State, system: number): string
  return state.galaxy.systems[system].name
end

local function shift(state: State.State, a: number, b: number, amount: number)
  local fa, fb = state.factions[a], state.factions[b]
  if fa.pirate or fb.pirate then
    return
  end
  fa.relations[b] += amount
  fb.relations[a] += amount
end

----------------------------------------------------------------- Battles

-- Sends a beaten fleet back where it came from, or to a friendly
-- neighbour; destroys it if there's nowhere to go
local function retreat(state: State.State, fleet: State.Fleet)
  local at = fleet.system :: number
  local options = { fleet.last }
  for _, n in state.galaxy.systems[at].neighbors do
    if state.systems[n].owner == fleet.owner then
      table.insert(options, n)
    end
  end
  for _, n in state.galaxy.systems[at].neighbors do
    table.insert(options, n)
  end
  for _, dest in options do
    if dest ~= at and not State.Hostile(state, fleet.owner, state.systems[dest].owner) then
      if Actions.Move(state, fleet, dest, "retreat") then
        return
      end
    end
  end
  State.Disband(state, fleet)
end

-- Ends a fleet's action because of a battle
local function interrupt(state: State.State, fleet: State.Fleet)
  local id = fleet.action
  if id then
    local action = state.actions[id]
    if action then
      Actions.Finish(state, action)
    end
    fleet.action = nil
  end
end

-- Pirates keep looted maintenance goods at their nearest den and fence
-- the rest; returns the credits the loot fetched
local function stash(state: State.State, pirate: number, near: number, good: string, amount: number): number
  if Data.MAINTENANCE[good] then
    local best: State.Station? = nil
    local bestHops = math.huge
    for _, system in state.systems do
      if system.owner == pirate then
        for _, id in state.galaxy.systems[system.id].stations do
          local station = state.stations[id]
          local d = state.galaxy.hops[near][system.id]
          if station.kind == "den" and not station.destroyed and d < bestHops then
            best, bestHops = station, d
          end
        end
      end
    end
    if best then
      best.stock[good] = (best.stock[good] or 0) + amount
      return 0
    end
  end
  return 0.5 * amount * Data.GoodById[good].base
end

local function fight(state: State.State, system: number, a: number, b: number, assault: boolean)
  local owner = state.systems[system].owner
  local sideA = State.IdleFleets(state, system, a)
  local sideB = State.IdleFleets(state, system, b)
  -- Fleets mid-action count too
  for _, id in state.systems[system].fleets do
    local fleet = state.fleets[id]
    if fleet and fleet.action ~= nil then
      if fleet.owner == a then table.insert(sideA, fleet) end
      if fleet.owner == b then table.insert(sideB, fleet) end
    end
  end
  -- Stations defend their owner against an assault
  local defA = if assault and owner == a then State.StationDefense(state, system) else 0
  local defB = if assault and owner == b then State.StationDefense(state, system) else 0
  local strengthA = Combat.Strength(sideA) + defA
  local strengthB = Combat.Strength(sideB) + defB
  if (#sideA == 0 and defA == 0) or (#sideB == 0 and defB == 0) then
    return
  end
  local rng = Rng.For(state.history, state.tick, system, a, b)
  local aWins, lossA, lossB = Combat.Fight(rng, strengthA, strengthB)
  -- Static defence soaks part of its side's losses
  local fleetShareA = if strengthA > 0 then Combat.Strength(sideA) / strengthA else 0
  local fleetShareB = if strengthB > 0 then Combat.Strength(sideB) / strengthB else 0
  local lostA = Combat.ApplyLosses(rng, sideA, lossA * (if aWins then fleetShareA else 1))
  local lostB = Combat.ApplyLosses(rng, sideB, lossB * (if aWins then 1 else fleetShareB))
  state.factions[a].losses += lostA
  state.factions[b].losses += lostB
  State.Count(state, "battles")
  State.Count(state, "ships lost", lostA + lostB)
  shift(state, a, b, -5)

  local winner, loser = if aWins then a else b, if aWins then b else a
  local losers = if aWins then sideB else sideA
  local cargo = 0
  local pirateWon = state.factions[winner].pirate
  for _, fleet in losers do
    for good, n in fleet.cargo do
      cargo += n * Data.GoodById[good].base
      if pirateWon then
        state.factions[winner].credits += stash(state, winner, system, good, n)
      end
    end
    fleet.cargo = {}
  end
  if cargo > 0 then
    State.Count(state, "convoys lost")
  end
  if lostA + lostB >= 6 or cargo > 0 then
    local what = if cargo > 0 then ` (cargo worth {math.floor(cargo)} lost)` else ""
    State.Log(state, "battle", `{name(state, winner)} beat {name(state, loser)} at {systemName(state, system)}: `
      .. `{lostA + lostB} ships lost{what}`)
  end

  -- Clear the dead; the beaten retreat
  for _, list in { sideA, sideB } do
    for _, fleet in list do
      if State.ShipCount(fleet) == 0 then
        interrupt(state, fleet)
        State.Disband(state, fleet)
      end
    end
  end
  for _, fleet in losers do
    if fleet.alive then
      interrupt(state, fleet)
      retreat(state, fleet)
    end
  end
end

-- A claim on an independent system fights its stations first
local function resist(state: State.State, system: number, faction: number)
  local defense = State.StationDefense(state, system) * Data.INDEPENDENT_DEFENSE
  local side = State.IdleFleets(state, system, faction)
  for _, id in state.systems[system].fleets do
    local fleet = state.fleets[id]
    if fleet and fleet.owner == faction and fleet.action ~= nil then
      table.insert(side, fleet)
    end
  end
  if defense <= 0 or #side == 0 then
    return
  end
  local rng = Rng.For(state.history, state.tick, system, faction, 0)
  local won, loss = Combat.Fight(rng, Combat.Strength(side), defense)
  local lost = Combat.ApplyLosses(rng, side, loss)
  state.factions[faction].losses += lost
  State.Count(state, "battles")
  State.Count(state, "ships lost", lost)
  if not won then
    State.Log(state, "battle", `{systemName(state, system)}'s independents drove off {name(state, faction)} ({lost} ships lost)`)
  end
  for _, fleet in side do
    if State.ShipCount(fleet) == 0 then
      interrupt(state, fleet)
      State.Disband(state, fleet)
    elseif not won then
      interrupt(state, fleet)
      retreat(state, fleet)
    end
  end
end

-- Fights between hostile parties in a system some fleet arrived in
local function battles(state: State.State, system: number, arrivals: { State.Action })
  local owner = state.systems[system].owner
  if owner == nil then
    for _, action in arrivals do
      if action.intent == "claim" and action.step == #(action.path :: { number }) then
        resist(state, system, action.owner)
      end
    end
  end
  local present: { number } = {}
  local seen: { [number]: boolean } = {}
  for _, id in state.systems[system].fleets do
    local fleet = state.fleets[id]
    if fleet and not seen[fleet.owner] then
      seen[fleet.owner] = true
      table.insert(present, fleet.owner)
    end
  end
  -- An attack or raid also fights the system's stations
  local assaulted: { [number]: boolean } = {}
  for _, action in arrivals do
    local final = action.step == #(action.path :: { number })
    if final and (action.intent == "attack" or action.intent == "raid") and State.Hostile(state, action.owner, owner) then
      assaulted[action.owner] = true
      if owner and not seen[owner] then
        seen[owner] = true
        table.insert(present, owner)
      end
    end
  end
  -- A siege counts as an assault too, so the stations back a relief force
  for _, id in state.systems[system].fleets do
    local fleet = state.fleets[id]
    local action = if fleet and fleet.action then state.actions[fleet.action] else nil
    if action and action.kind == "siege" then
      assaulted[action.owner] = true
    end
  end
  table.sort(present)
  for i = 1, #present do
    for j = i + 1, #present do
      local a, b = present[i], present[j]
      if State.Hostile(state, a, b) then
        local assault = (owner == a and assaulted[b] == true) or (owner == b and assaulted[a] == true)
        fight(state, system, a, b, assault)
      end
    end
  end
end

------------------------------------------------------------- Arrivals

local function hostilesPresent(state: State.State, system: number, owner: number): boolean
  for _, id in state.systems[system].fleets do
    local fleet = state.fleets[id]
    if fleet and State.Hostile(state, owner, fleet.owner) then
      return true
    end
  end
  return false
end

-- Hands a system to 'faction' (nil: it becomes independent), cancelling
-- ships under construction there
local function transfer(state: State.State, system: number, faction: number?)
  state.systems[system].owner = faction
  for _, id in state.galaxy.systems[system].stations do
    local station = state.stations[id]
    local building = station.building
    if building then
      local action = state.actions[building]
      if action then
        Actions.Finish(state, action)
      end
      station.building = nil
    end
    if station.kind == "den" and (faction == nil or not state.factions[faction].pirate) then
      station.destroyed = true
    end
  end
end

local function capture(state: State.State, system: number, faction: number)
  local old = state.systems[system].owner
  transfer(state, system, faction)
  if old then
    shift(state, faction, old, -15)
  end
  State.Count(state, "captures")
  State.Log(state, "capture", `{name(state, faction)} captured {systemName(state, system)} from {name(state, old)}`)
end

local function claim(state: State.State, system: number, faction: number)
  transfer(state, system, faction)
  State.Count(state, "claims")
  State.Log(state, "claim", `{name(state, faction)} claimed {systemName(state, system)}`)
end

local function raid(state: State.State, system: number, fleet: State.Fleet)
  local loot = 0
  for _, id in state.galaxy.systems[system].stations do
    local station = state.stations[id]
    for good, n in station.stock do
      local k = 0.25 * n
      station.stock[good] = n - k
      loot += k * Data.GoodById[good].base
      state.factions[fleet.owner].credits += stash(state, fleet.owner, system, good, k)
    end
  end
  State.Count(state, "raids")
  State.Log(state, "raid", `{name(state, fleet.owner)} raided {systemName(state, system)} `
    .. `({name(state, state.systems[system].owner)}), goods worth {math.floor(loot)}`)
end

local function arrived(state: State.State, action: State.Action, fleet: State.Fleet)
  local system = fleet.system :: number
  local owner = state.systems[system].owner
  local intent = action.intent
  if action.kind == "convoy" then
    Actions.ConvoyArrived(state, action, fleet)
    return
  end
  Actions.Finish(state, action)
  if intent == "attack" then
    if State.Hostile(state, fleet.owner, owner) and not hostilesPresent(state, system, fleet.owner) then
      if Actions.Siege(state, fleet) then
        State.Log(state, "siege", `{name(state, fleet.owner)} lays siege to {systemName(state, system)} ({name(state, owner)})`)
      end
    end
  elseif intent == "claim" then
    if owner == nil and not hostilesPresent(state, system, fleet.owner) then
      -- A defended system has to be pacified: held for a siege's length
      if State.StationDefense(state, system) > 0 then
        Actions.Siege(state, fleet)
      else
        claim(state, system, fleet.owner)
      end
    end
  elseif intent == "raid" then
    if not hostilesPresent(state, system, fleet.owner) then
      raid(state, system, fleet)
    end
  elseif intent == "construct" then
    if owner == nil and #state.galaxy.systems[system].stations == 0 and not hostilesPresent(state, system, fleet.owner)
      and Actions.Construct(state, fleet, "den", Data.DEN_CREDITS) then
      State.Log(state, "construct", `{name(state, fleet.owner)} begin building a den at {systemName(state, system)}`)
    end
  end
end

------------------------------------------------------------- Production

local function produce(state: State.State, station: State.Station)
  local kind = Data.StationById[station.kind]
  local owner = state.systems[station.system].owner
  local resources = state.galaxy.systems[station.system].resources
  local makes = Market.Profile(station.kind).makes
  -- Maintenance first, drawn from this station, then the others in its
  -- system; a station short of it works at reduced strength
  do
    local others = state.galaxy.systems[station.system].stations
    local total, count = 0, 0
    for good, n in Data.MAINTENANCE do
      local available = 0
      for _, id in others do
        available += state.stations[id].stock[good] or 0
      end
      local share = math.min(1, available / n)
      total += share
      count += 1
      -- Consume what's there, from this station first
      local need = n * share
      local own = math.min(need, station.stock[good] or 0)
      station.stock[good] = (station.stock[good] or 0) - own
      need -= own
      for _, id in others do
        if need <= 0 then
          break
        end
        local other = state.stations[id]
        local k = math.min(need, other.stock[good] or 0)
        other.stock[good] = (other.stock[good] or 0) - k
        need -= k
      end
    end
    station.maintained = total / count
  end
  local readiness = Data.UNMAINTAINED + (1 - Data.UNMAINTAINED) * station.maintained
  for _, recipe in kind.recipes do
    -- Run unless every output is already at capacity (a recipe that pays
    -- tax or makes nothing always runs)
    local function capacity(good: string): number
      return if kind.planet then math.huge else makes[good] * Data.CAP_CYCLES
    end
    local room, outputs = false, 0
    for good in recipe.outputs do
      outputs += 1
      if (station.stock[good] or 0) < capacity(good) then
        room = true
      end
    end
    if room or outputs == 0 or kind.tax then
      -- Inputs come from any station in the system, this one first
      local others = state.galaxy.systems[station.system].stations
      local fraction = 1
      for good, n in recipe.inputs do
        local available = 0
        for _, id in others do
          available += state.stations[id].stock[good] or 0
        end
        fraction = math.min(fraction, available / n)
      end
      for good, n in recipe.inputs do
        local need = n * fraction
        local own = math.min(need, station.stock[good] or 0)
        station.stock[good] = (station.stock[good] or 0) - own
        need -= own
        for _, id in others do
          if need <= 0 then
            break
          end
          local other = state.stations[id]
          local k = math.min(need, other.stock[good] or 0)
          other.stock[good] = (other.stock[good] or 0) - k
          need -= k
        end
      end
      local rate = if kind.extractor then math.max(fraction, Data.EXTRACTOR_IDLE) else fraction
      local value = 0
      for good, n in recipe.outputs do
        local cap = capacity(good)
        local have = station.stock[good] or 0
        if have < cap then
          local richness = if kind.extractor and resources[good] then resources[good] else 1
          local made = math.min(n * rate * richness * readiness, cap - have)
          station.stock[good] = have + made
          value += made * Data.GoodById[good].base
        end
      end
      -- Industry tax on what was made (only factions levy taxes)
      local levy = value * Data.INDUSTRY_TAX
      if owner and not state.factions[owner].pirate then
        state.factions[owner].credits += levy
        State.Count(state, "industry tax", levy)
      end
      local tax = (kind.tax or 0) * fraction * readiness
      if tax > 0 and owner and not state.factions[owner].pirate then
        state.factions[owner].credits += tax
        State.Count(state, "taxes", tax)
      end
    end
  end
end

------------------------------------------------------------- Periodic

-- Shared gate links between each pair of factions, and which factions
-- still have unclaimed neighbours to expand into
local function borders(state: State.State): ({ [number]: { [number]: number } }, { [number]: boolean })
  local links: { [number]: { [number]: number } } = {}
  local room: { [number]: boolean } = {}
  for _, f in state.factions do
    links[f.id] = {}
  end
  for _, system in state.systems do
    local a = system.owner
    for _, n in state.galaxy.systems[system.id].neighbors do
      local b = state.systems[n].owner
      if a and b and b ~= a then
        links[a][b] = (links[a][b] or 0) + 1
      elseif a and b == nil then
        room[a] = true
      end
    end
  end
  return links, room
end

local function warStrength(state: State.State): { [number]: number }
  local strength: { [number]: number } = {}
  for _, f in state.factions do
    strength[f.id] = 0
  end
  for _, fleet in state.fleets do
    if fleet.role == "war" then
      strength[fleet.owner] += Combat.FleetStrength(fleet)
    end
  end
  return strength
end

-- The owned system farthest from the capital (not the capital itself)
local function mostRemote(state: State.State, faction: State.Faction): number?
  local capital = faction.capital
  local pick, pickD = nil, -1
  for _, system in state.systems do
    if system.owner == faction.id and system.id ~= capital then
      local d = if capital then state.galaxy.hops[capital][system.id] else 0
      if d > pickD then
        pick, pickD = system.id, d
      end
    end
  end
  return pick
end

-- Scraps idle ships (cruisers, then frigates keeping one per fleet, then
-- haulers beyond six) until maintenance falls by 'saving' credits per period
local function decommission(state: State.State, faction: State.Faction, saving: number)
  local fleets = {}
  local haulers = 0
  for _, fleet in state.fleets do
    if fleet.owner == faction.id and fleet.action == nil then
      table.insert(fleets, fleet)
    end
    if fleet.owner == faction.id then
      haulers += fleet.ships.hauler or 0
    end
  end
  table.sort(fleets, function(a, b)
    local sa, sb = State.ShipCount(a), State.ShipCount(b)
    if sa ~= sb then return sa > sb end
    return a.id < b.id
  end)
  local saved, scrapped = 0, 0
  for _, id in { "cruiser", "frigate", "hauler" } do
    local class = Data.ShipById[id]
    for _, fleet in fleets do
      local keep = if id == "frigate" and fleet.role == "war" then 1 else 0
      while saved < saving and (fleet.ships[id] or 0) > keep and (id ~= "hauler" or haulers > 6) do
        fleet.ships[id] -= 1
        saved += class.upkeep
        scrapped += 1
        if id == "hauler" then
          haulers -= 1
        end
      end
    end
  end
  -- Fleets scrapped down to nothing are gone
  for _, fleet in fleets do
    if State.ShipCount(fleet) == 0 then
      State.Disband(state, fleet)
    end
  end
  if scrapped > 0 then
    State.Count(state, "ships decommissioned", scrapped)
    State.Log(state, "decommission", `{faction.name} decommissions {scrapped} ships to balance its budget`)
  end
end

-- Sovereignty and ship maintenance; arrears cost systems and crews
local function pay(state: State.State)
  local systems: { [number]: number } = {}
  local stations: { [number]: number } = {}
  for _, system in state.systems do
    local owner = system.owner
    if owner then
      systems[owner] = (systems[owner] or 0) + 1
      stations[owner] = (stations[owner] or 0) + #state.galaxy.systems[system.id].stations
    end
  end
  local maintenance: { [number]: number } = {}
  for _, fleet in state.fleets do
    for _, class in Data.Ships do
      maintenance[fleet.owner] = (maintenance[fleet.owner] or 0) + (fleet.ships[class.id] or 0) * class.upkeep
    end
  end
  for _, f in state.factions do
    if f.alive then
      local sov = (systems[f.id] or 0) * Data.SOV_PER_SYSTEM + (stations[f.id] or 0) * Data.SOV_PER_STATION
      local earned = f.credits - f.lastCredits
      f.income = if state.tick <= Data.PERIOD_TICKS then earned
        else f.income + Data.INCOME_SMOOTHING * (earned - f.income)
      f.costs = sov + (maintenance[f.id] or 0)
      f.credits -= f.costs
      f.lastCredits = f.credits
      State.Count(state, "sovereignty upkeep", sov)
      State.Count(state, "ship maintenance", maintenance[f.id] or 0)
      if f.credits < 0 then
        f.arrears += 1
      else
        f.arrears = 0
      end
      if f.arrears > Data.ARREARS_GRACE then
        local lost = mostRemote(state, f)
        if lost then
          transfer(state, lost, nil)
          State.Count(state, "systems lost to arrears")
          State.Log(state, "lapse", `{f.name} lost control of {systemName(state, lost)}: unpaid upkeep`)
        end
      end
      if f.income < f.costs and f.credits < f.costs * Data.DECOMMISSION_RUNWAY then
        decommission(state, f, f.costs - 0.9 * math.max(0, f.income))
      end
      if f.arrears > 0 then
        -- Unpaid crews desert
        local rng = Rng.For(state.history, state.tick, f.id, 1)
        local deserted = 0
        for _, fleet in state.fleets do
          if fleet.owner == f.id then
            deserted += Combat.ApplyLosses(rng, { fleet }, Data.DESERTION)
          end
        end
        State.Count(state, "ships deserted", deserted)
      end
    end
  end
end

-- The exhausted side cedes its border systems (those under siege first)
-- and a share of its credits
local function negotiate(state: State.State, winner: State.Faction, loser: State.Faction)
  local besieged: { [number]: boolean } = {}
  for _, action in state.actions do
    if action.kind == "siege" and action.owner == winner.id then
      besieged[action.target :: number] = true
    end
  end
  local candidates: { number } = {}
  for _, system in state.systems do
    if system.owner == loser.id and system.id ~= loser.capital then
      for _, n in state.galaxy.systems[system.id].neighbors do
        if state.systems[n].owner == winner.id then
          table.insert(candidates, system.id)
          break
        end
      end
    end
  end
  table.sort(candidates, function(a, b)
    local sa, sb = besieged[a] == true, besieged[b] == true
    if sa ~= sb then return sa end
    local na, nb = #state.galaxy.systems[a].stations, #state.galaxy.systems[b].stations
    if na ~= nb then return na > nb end
    return a < b
  end)
  local ceded = {}
  for i = 1, math.min(Data.CEDED_SYSTEMS, #candidates) do
    transfer(state, candidates[i], winner.id)
    table.insert(ceded, systemName(state, candidates[i]))
  end
  local reparations = math.max(0, loser.credits) * Data.REPARATIONS
  Actions.Pay(state, loser.id, winner.id, reparations)
  local terms = if #ceded > 0 then "cedes " .. table.concat(ceded, ", ") else "cedes nothing"
  State.Log(state, "peace", `{loser.name} sues {winner.name} for peace: {terms}, pays {math.floor(reparations)} credits`)
end

local function makePeace(state: State.State, a: State.Faction, b: State.Faction)
  a.war[b.id], b.war[a.id] = false, false
  a.declared[b.id], b.declared[a.id] = nil, nil
  a.lastWarEnded, b.lastWarEnded = state.tick, state.tick
  a.relations[b.id], b.relations[a.id] = Data.AFTER_PEACE, Data.AFTER_PEACE
  local until_ = state.tick + Data.TRUCE_PERIODS * Data.PERIOD_TICKS
  a.truce[b.id], b.truce[a.id] = until_, until_
  if a.plan and state.systems[a.plan.target].owner == b.id then a.plan = nil end
  if b.plan and state.systems[b.plan.target].owner == a.id then b.plan = nil end
  State.Count(state, "peace treaties")
end

-- A faction may declare war if it hasn't declared one, or had one end,
-- within the cooldown
local function canDeclare(state: State.State, f: State.Faction): boolean
  return state.tick - f.lastDeclared >= Data.WAR_COOLDOWN and state.tick - f.lastWarEnded >= Data.WAR_COOLDOWN
end

local function period(state: State.State)
  pay(state)
  local strength = warStrength(state)

  -- Power: war fleet plus territory
  local held: { [number]: number } = {}
  for _, system in state.systems do
    if system.owner then
      held[system.owner] = (held[system.owner] or 0) + 1
    end
  end
  local power: { [number]: number } = {}
  local total, count = 0, 0
  for _, f in state.factions do
    power[f.id] = strength[f.id] + 3 * (held[f.id] or 0)
    if f.alive and not f.pirate then
      total += power[f.id]
      count += 1
    end
  end
  local average = if count > 0 then total / count else 1

  -- An aggressor clearly stronger than the faction it attacked
  local function bully(f: State.Faction): boolean
    for other, declared in f.declared do
      if declared and f.war[other] and power[f.id] > Data.AGGRESSOR_RATIO * power[other] then
        return true
      end
    end
    return false
  end

  -- Coalitions: the others fear a strong aggressor and side with its victim
  for _, a in state.factions do
    if a.alive and not a.pirate then
      for victim, declared in a.declared do
        if declared and a.war[victim] and power[a.id] > Data.AGGRESSOR_RATIO * power[victim] then
          local fear = Data.FEAR * power[a.id] / (2 * average)
          for _, c in state.factions do
            if c.alive and not c.pirate and c.id ~= a.id and c.id ~= victim and not c.war[victim] then
              c.relations[a.id] -= fear
              a.relations[c.id] = c.relations[a.id]
              c.relations[victim] += Data.SOLIDARITY
              state.factions[victim].relations[c.id] = c.relations[victim]
            end
          end
        end
      end
    end
  end

  -- Relations: drift back toward the baseline; friction along shared
  -- borders, worse for the aggressive, eased by the sociable and doubled
  -- for a faction with nowhere left to expand
  local links, room = borders(state)
  for _, a in state.factions do
    for _, b in state.factions do
      if a.id < b.id and not a.pirate and not b.pirate and a.alive and b.alive then
        local r = a.relations[b.id]
        local drift = math.clamp(a.baseline[b.id] - r, -Data.DRIFT, Data.DRIFT)
        local aggressive = (a.traits.aggressive + b.traits.aggressive) / 2
        local sociable = (a.traits.sociable + b.traits.sociable) / 2
        local hunger = if room[a.id] and room[b.id] then 1 else Data.LAND_HUNGER
        local friction = -(links[a.id][b.id] or 0) * Data.FRICTION * aggressive * (1 - 0.7 * sociable) * hunger
        r += drift + friction
        a.relations[b.id], b.relations[a.id] = r, r

        if not a.war[b.id] then
          if r < Data.WAR_BELOW and state.tick >= (a.truce[b.id] or 0) then
            -- The declarer: a faction joining a coalition against a strong
            -- aggressor, otherwise the more aggressive of the two
            local bullyA, bullyB = bully(a), bully(b)
            local declarer = if bullyB and not bullyA then a
              elseif bullyA and not bullyB then b
              elseif a.traits.aggressive >= b.traits.aggressive then a
              else b
            local target = if declarer == a then b else a
            if canDeclare(state, declarer) then
              a.war[b.id], b.war[a.id] = true, true
              a.warStart[b.id], b.warStart[a.id] = strength[a.id], strength[b.id]
              declarer.declared[target.id] = true
              declarer.lastDeclared = state.tick
              State.Count(state, "wars declared")
              if bully(target) then
                State.Count(state, "coalition wars")
                State.Log(state, "war", `{declarer.name} joins the coalition against {target.name}`)
              else
                State.Log(state, "war", `{declarer.name} declares war on {target.name}`)
              end
            end
          end
        else
          -- Wars end when a side runs out of resources
          local function exhausted(f: State.Faction, other: number): boolean
            return f.credits < f.costs * Data.EXHAUSTED_RUNWAY
              or strength[f.id] < Data.EXHAUSTED_STRENGTH * (f.warStart[other] or 0)
          end
          local ea, eb = exhausted(a, b.id), exhausted(b, a.id)
          if ea and eb then
            makePeace(state, a, b)
            State.Log(state, "peace", `{a.name} and {b.name}, both exhausted, make a white peace`)
          elseif ea or eb then
            local winner, loser = if ea then b else a, if ea then a else b
            negotiate(state, winner, loser)
            makePeace(state, a, b)
          end
        end
      end
    end
  end

  -- Eliminations (peace terms may have moved systems since 'held')
  local remaining: { [number]: number } = {}
  for _, system in state.systems do
    if system.owner then
      remaining[system.owner] = (remaining[system.owner] or 0) + 1
    end
  end
  for _, f in state.factions do
    if f.alive and not f.pirate and (remaining[f.id] or 0) == 0 then
      f.alive = false
      State.Log(state, "eliminated", `{f.name} has been eliminated`)
      for _, fleet in state.fleets do
        if fleet.owner == f.id then
          interrupt(state, fleet)
          State.Disband(state, fleet)
        end
      end
    end
    f.losses = 0
  end
end

------------------------------------------------------------------ Tick

local function resolve(state: State.State)
  state.phase = "resolve"
  local arrivals: { State.Action } = {}
  local bySystem: { [number]: { State.Action } } = {}
  local touched: { number } = {}
  local builds: { State.Action } = {}
  local sieges: { State.Action } = {}
  for _, id in State.PopDue(state, state.tick) do
    local action = state.actions[id]
    if action and not action.done then
      if action.kind == "build" then
        table.insert(builds, action)
      elseif action.kind == "siege" or action.kind == "construct" then
        table.insert(sieges, action)
      else
        local fleet = state.fleets[action.fleet :: number]
        if fleet and fleet.alive then
          local dest = (action.path :: { number })[action.step :: number]
          State.Arrive(state, fleet, dest)
          table.insert(arrivals, action)
          if not bySystem[dest] then
            bySystem[dest] = {}
            table.insert(touched, dest)
          end
          table.insert(bySystem[dest], action)
        else
          Actions.Finish(state, action)
        end
      end
    end
  end

  -- 1. Battles where fleets arrived
  table.sort(touched)
  for _, system in touched do
    battles(state, system, bySystem[system])
  end

  -- 2. Moves continue, or complete what they set out to do
  for _, action in arrivals do
    if not action.done then
      local fleet = state.fleets[action.fleet :: number]
      if not fleet or not fleet.alive then
        Actions.Finish(state, action)
      elseif action.cancelled then
        Actions.Finish(state, action)
      elseif (action.step :: number) < #(action.path :: { number }) then
        action.step = (action.step :: number) + 1
        Actions.Depart(state, action, fleet)
      else
        arrived(state, action, fleet)
      end
    end
  end

  -- 3. Sieges and constructions complete if the fleet still holds the system
  for _, action in sieges do
    if not action.done then
      local fleet = state.fleets[action.fleet :: number]
      local system = action.target :: number
      Actions.Finish(state, action)
      local owner = state.systems[system].owner
      if action.kind == "construct" then
        if fleet and fleet.alive and fleet.system == system and owner == nil
          and not hostilesPresent(state, system, fleet.owner) then
          State.BuildStation(state, system, action.structure :: string)
          transfer(state, system, fleet.owner)
          State.Count(state, "stations constructed")
          State.Log(state, "construct", `{name(state, fleet.owner)} completed a {Data.StationById[action.structure :: string].name} `
            .. `at {systemName(state, system)}`)
        end
      elseif fleet and fleet.alive and fleet.system == system and not hostilesPresent(state, system, fleet.owner) then
        if owner == nil then
          claim(state, system, fleet.owner)
        elseif State.Hostile(state, fleet.owner, owner) then
          capture(state, system, fleet.owner)
        end
      end
    end
  end

  -- 4. Ships finished
  for _, action in builds do
    local station = state.stations[action.station :: number]
    station.building = nil
    Actions.Finish(state, action)
    if state.systems[station.system].owner == action.owner and not station.destroyed then
      local ship = action.ship :: string
      local role: "war" | "trade" = if ship == "hauler" then "trade" else "war"
      local fleet = if role == "war" then State.IdleFleets(state, station.system, action.owner, role)[1] else nil
      if fleet then
        fleet.ships[ship] = (fleet.ships[ship] or 0) + 1
        fleet.fuel += 10
        fleet.munitions += 2
      else
        State.NewFleet(state, action.owner, station.system, role, { [ship] = 1 })
      end
      State.Count(state, `built {ship}`)
    end
  end

  -- 5. Production
  for _, station in state.stations do
    if not station.destroyed and state.tick >= station.nextCycle then
      station.nextCycle += Data.CYCLE_TICKS
      produce(state, station)
    end
  end

  -- 6. Upkeep, taxes, relations
  if state.tick > 0 and state.tick % Data.PERIOD_TICKS == 0 then
    period(state)
  end
end

-- Merges idle war fleets of the same owner in each system
local function consolidate(state: State.State)
  for _, system in state.systems do
    if #system.fleets > 1 then
      local keep: { [string]: State.Fleet } = {}
      for _, id in table.clone(system.fleets) do
        local fleet = state.fleets[id]
        -- Haulers stay separate, so each can run its own convoy
        if fleet and fleet.action == nil and fleet.role == "war" then
          local key = `{fleet.owner}:{fleet.role}`
          local into = keep[key]
          if into then
            for class, n in fleet.ships do
              into.ships[class] = (into.ships[class] or 0) + n
            end
            into.fuel += fleet.fuel
            into.munitions += fleet.munitions
            for good, n in fleet.cargo do
              into.cargo[good] = (into.cargo[good] or 0) + n
            end
            State.Disband(state, fleet)
          else
            keep[key] = fleet
          end
        end
      end
    end
  end
end

-- Seconds spent in each part of the tick, accumulated (for profiling)
Sim.Timing = {} :: { [string]: number }

local function timed(part: string, started: number): number
  local now = os.clock()
  Sim.Timing[part] = (Sim.Timing[part] or 0) + (now - started)
  return now
end

function Sim.Tick(state: State.State)
  local t = os.clock()
  resolve(state)
  t = timed("resolve", t)
  consolidate(state)
  local census = Ai.Census(state)
  t = timed("census", t)
  local index = Market.Index(state)
  t = timed("market index", t)
  state.phase = "action"
  for _, faction in state.factions do
    Ai.ActionPhase(state, faction, census[faction.id], index)
    t = timed(if faction.pirate then "action: pirates" else "action: factions", t)
  end
  state.phase = "reaction"
  for _, faction in state.factions do
    Ai.ReactionPhase(state, faction, census[faction.id])
  end
  timed("reaction", t)
  state.tick += 1
end

------------------------------------------------------------------ Stats

export type FactionStats = {
  name: string,
  systems: number,
  frigates: number,
  cruisers: number,
  haulers: number,
  credits: number,
  costs: number,
  arrears: number,
  wars: { string },
  alive: boolean,
}

function Sim.Stats(state: State.State): { FactionStats }
  local stats: { FactionStats } = {}
  for _, f in state.factions do
    local wars = {}
    for other, atWar in f.war do
      if atWar and not state.factions[other].pirate and state.factions[other].alive then
        -- '*' marks a war this faction declared
        table.insert(wars, state.factions[other].name .. (if f.declared[other] then "*" else ""))
      end
    end
    table.sort(wars)
    stats[f.id] = { name = f.name, systems = 0, frigates = 0, cruisers = 0, haulers = 0,
      credits = f.credits, costs = f.costs, arrears = f.arrears, wars = wars, alive = f.alive }
  end
  for _, system in state.systems do
    if system.owner then
      stats[system.owner].systems += 1
    end
  end
  for _, fleet in state.fleets do
    local s = stats[fleet.owner]
    s.frigates += fleet.ships.frigate or 0
    s.cruisers += fleet.ships.cruiser or 0
    s.haulers += fleet.ships.hauler or 0
  end
  return stats
end

-- Total stock of each good, and its average price where it is traded
function Sim.Economy(state: State.State): { { good: string, stock: number, price: number } }
  local rows = {}
  for _, good in Data.Goods do
    local stock, priceSum, priceCount = 0, 0, 0
    for _, station in state.stations do
      stock += station.stock[good.id] or 0
      local p = Market.BuyPrice(station, good.id) or Market.SellPrice(station, good.id)
      if p then
        priceSum += p
        priceCount += 1
      end
    end
    for _, fleet in state.fleets do
      stock += fleet.cargo[good.id] or 0
    end
    table.insert(rows, { good = good.name, stock = stock, price = if priceCount > 0 then priceSum / priceCount else 0 })
  end
  return rows
end

return Sim
