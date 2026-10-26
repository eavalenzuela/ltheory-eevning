--!strict
-- Faction decisions. In the action phase a faction reviews the state and
-- submits new actions (ships to build, convoys, expansion, attacks); in
-- the reaction phase it responds to other factions' actions in progress
-- (defending, intercepting, ambushing convoys). Choices are scored against
-- the faction's goals and weighted by its personality traits.

local Actions = require("@lt/Sim/Actions")
local Combat = require("@lt/Sim/Combat")
local Data = require("@lt/Sim/Data")
local Market = require("@lt/Sim/Market")
local State = require("@lt/Sim/State")

local Ai = {}

-- Per-faction summary, rebuilt once per tick
export type Census = {
  systems: { number },
  stations: number,
  warStrength: number,
  haulers: number,
  idleWar: { State.Fleet },
  idleTrade: { State.Fleet },
  attacks: number,             -- attack moves in progress
  claims: { [number]: boolean }, -- systems being claimed
  hunts: { [number]: boolean },  -- systems being hunted in
}

function Ai.Census(state: State.State): { Census }
  local census: { Census } = {}
  for _, f in state.factions do
    census[f.id] = {
      systems = {}, stations = 0, warStrength = 0, haulers = 0,
      idleWar = {}, idleTrade = {}, attacks = 0, claims = {}, hunts = {},
    }
  end
  for _, system in state.systems do
    local owner = system.owner
    if owner then
      table.insert(census[owner].systems, system.id)
      census[owner].stations += #state.galaxy.systems[system.id].stations
    end
  end
  local ids = {}
  for id in state.fleets do
    table.insert(ids, id)
  end
  table.sort(ids)
  for _, id in ids do
    local fleet = state.fleets[id]
    local c = census[fleet.owner]
    if fleet.role == "war" then
      c.warStrength += Combat.FleetStrength(fleet)
    else
      c.haulers += fleet.ships.hauler or 0
    end
    if fleet.action == nil and fleet.system then
      table.insert(if fleet.role == "war" then c.idleWar else c.idleTrade, fleet)
    end
  end
  local actionIds = {}
  for id in state.actions do
    table.insert(actionIds, id)
  end
  table.sort(actionIds)
  for _, id in actionIds do
    local action = state.actions[id]
    local c = census[action.owner]
    if action.intent == "attack" or action.intent == "siege" then
      c.attacks += 1
    elseif action.intent == "claim" then
      c.claims[action.target :: number] = true
    elseif action.intent == "hunt" then
      c.hunts[action.target :: number] = true
    end
  end
  return census
end

-- A fleet from the tick-start census that is still free to act
local function available(fleet: State.Fleet): boolean
  return fleet.alive and fleet.action == nil and fleet.system ~= nil
end

local function hops(state: State.State, a: number, b: number): number
  return state.galaxy.hops[a][b]
end

local function isEnemy(state: State.State, faction: State.Faction, other: number?): boolean
  return other ~= nil and other ~= faction.id and faction.war[other] == true
end

-- Keeps two frigates behind when a fleet leaves an owned system it guards
local function detach(state: State.State, fleet: State.Fleet, ships: { [string]: number }?): State.Fleet
  if ships then
    return State.Split(state, fleet, ships)
  end
  local system = fleet.system :: number
  if state.systems[system].owner == fleet.owner and (fleet.ships.frigate or 0) > 3 then
    local keep = { frigate = 2 }
    local send: { [string]: number } = {}
    for class, n in fleet.ships do
      send[class] = n - (keep[class] or 0)
    end
    return State.Split(state, fleet, send)
  end
  return fleet
end

-- Ships from 'fleet' worth at least 'needed' in strength, cruisers first,
-- keeping two frigates behind in an owned system; nil if it can't spare
-- that much
local function sparing(state: State.State, fleet: State.Fleet, needed: number): { [string]: number }?
  local system = fleet.system :: number
  local keep = if state.systems[system].owner == fleet.owner then 2 else 0
  local take: { [string]: number } = {}
  local strength = 0
  local mult = if fleet.munitions < State.ShipCount(fleet) then Data.NO_MUNITIONS else 1
  for _, id in { "cruiser", "frigate" } do
    local class = Data.ShipById[id]
    local spare = (fleet.ships[id] or 0) - (if id == "frigate" then keep else 0)
    local k = 0
    while k < spare and strength < needed do
      k += 1
      strength += class.quality * mult
    end
    if k > 0 then
      take[id] = k
    end
  end
  return if strength >= needed then take else nil
end

------------------------------------------------------------- Shipbuilding

local function buildShips(state: State.State, faction: State.Faction, c: Census)
  local wars = 0
  for _, atWar in faction.war do
    if atWar then wars += 1 end
  end
  local wantHaulers = math.max(6, c.stations // 3)
  -- Enough to garrison and keep expanding the territory, more for the aggressive and at war
  local wantStrength = 2 * #c.systems * (0.6 + 0.8 * faction.traits.aggressive) + 30 * math.max(0, wars - 1)
  -- Keep building while a prepared attack or claim lacks the strength
  if faction.plan then
    wantStrength = math.max(wantStrength, c.warStrength + 20)
  end
  for _, system in c.systems do
    for _, id in state.galaxy.systems[system].stations do
      local station = state.stations[id]
      if station.kind == "shipyard" and station.building == nil and not station.destroyed then
        local ship: string? = nil
        if c.haulers < wantHaulers then
          ship = "hauler"
        elseif c.warStrength < wantStrength and faction.credits > faction.costs * Data.BUILD_RESERVE
          and faction.income > faction.costs + Data.ShipById.cruiser.upkeep then
          ship = "cruiser"
          for good, n in Data.ShipById.cruiser.cost do
            if (station.stock[good] or 0) < n then
              ship = "frigate"
            end
          end
        end
        if ship and Actions.Build(state, station, ship) then
          if ship == "hauler" then c.haulers += 1 else c.warStrength += Data.ShipById[ship].quality end
        end
      end
    end
  end
end

------------------------------------------------------------------ Trade

local PICKUP_RANGE = 8
local DELIVERY_RANGE = 12

local SELLER_CANDIDATES = 6
local BUYER_CANDIDATES = 12

-- The best few offers within 'range' of 'at', by price (cheapest sellers
-- or best-paying buyers)
local function nearby(state: State.State, faction: State.Faction, offers: { Market.Offer }, at: number,
  range: number, cheapest: boolean, limit: number): { Market.Offer }
  local list = {}
  for _, offer in offers do
    local system = state.stations[offer.station].system
    if offer.amount > 0 and hops(state, at, system) <= range and not isEnemy(state, faction, state.systems[system].owner) then
      table.insert(list, offer)
    end
  end
  table.sort(list, function(a, b)
    if a.price ~= b.price then
      if cheapest then return a.price < b.price end
      return a.price > b.price
    end
    return a.station < b.station
  end)
  while #list > limit do
    table.remove(list)
  end
  return list
end

-- Sends idle haulers on the most profitable run per jump within reach
local function trade(state: State.State, faction: State.Faction, c: Census, index: Market.Index)
  local sent, evaluated = 0, 0
  for _, fleet in c.idleTrade do
    if sent >= 4 or evaluated >= 8 then
      break
    end
    if not available(fleet) then
      continue
    end
    evaluated += 1
    local at = fleet.system :: number
    local room = Actions.Capacity(fleet)
    local best: { from: Market.Offer, to: Market.Offer, good: string, amount: number }? = nil
    local bestRate = 10
    for _, good in Data.Goods do
      local offers = index[good.id]
      local sellers = nearby(state, faction, offers.sellers, at, PICKUP_RANGE, true, SELLER_CANDIDATES)
      if #sellers > 0 then
        local buyers = nearby(state, faction, offers.buyers, at, PICKUP_RANGE + DELIVERY_RANGE, false, BUYER_CANDIDATES)
        for _, seller in sellers do
          local sellerSystem = state.stations[seller.station].system
          local sellerOwner = state.systems[sellerSystem].owner
          local toSeller = hops(state, at, sellerSystem)
          for _, buyer in buyers do
            local buyerSystem = state.stations[buyer.station].system
            local route = hops(state, sellerSystem, buyerSystem)
            if buyer.station ~= seller.station and route <= DELIVERY_RANGE and buyer.price > seller.price then
              local amount = math.min(room, seller.amount, buyer.amount)
              local margin = buyer.price - seller.price
              -- Supplying your own stations is worth more than the margin alone
              if state.systems[buyerSystem].owner == faction.id then
                margin += 0.2 * good.base
              end
              local affordable = sellerOwner == faction.id or faction.credits >= amount * seller.price
              local rate = amount * margin / (toSeller + route + 1)
              if affordable and rate > bestRate then
                bestRate = rate
                best = { from = seller, to = buyer, good = good.id, amount = amount }
              end
            end
          end
        end
      end
    end
    if best then
      if Actions.Convoy(state, fleet, best.from.station, best.to.station, best.good, best.amount) then
        -- Other haulers this tick go after other offers
        best.from.amount -= best.amount
        best.to.amount -= best.amount
        sent += 1
      end
    end
  end
end

------------------------------------------------------------- Expansion

local function expand(state: State.State, faction: State.Faction, c: Census)
  -- Every system adds sovereignty upkeep: only expand with a reserve
  if faction.credits < faction.costs * Data.EXPAND_RESERVE then
    return
  end
  local claiming = 0
  for _ in c.claims do
    claiming += 1
  end
  local maxClaims = 2 + math.floor(2 * faction.traits.aggressive)
  if claiming >= maxClaims then
    return
  end
  -- Unclaimed neighbours, most stations first
  local targets: { number } = {}
  local seen: { [number]: boolean } = {}
  for _, system in c.systems do
    for _, n in state.galaxy.systems[system].neighbors do
      if not seen[n] and state.systems[n].owner == nil and not c.claims[n] then
        seen[n] = true
        table.insert(targets, n)
      end
    end
  end
  table.sort(targets, function(a, b)
    local sa, sb = #state.galaxy.systems[a].stations, #state.galaxy.systems[b].stations
    if sa ~= sb then return sa > sb end
    return a < b
  end)
  for _, target in targets do
    if claiming >= maxClaims then
      break
    end
    -- Independents resist: send enough to win at the attack odds
    local needed = math.max(1, Data.ATTACK_ODDS * State.StationDefense(state, target) * Data.INDEPENDENT_DEFENSE)
    local pick: State.Fleet? = nil
    local ships: { [string]: number }? = nil
    for _, fleet in c.idleWar do
      if available(fleet) and hops(state, fleet.system :: number, target) <= 20
        and (pick == nil or hops(state, fleet.system :: number, target) < hops(state, (pick :: State.Fleet).system :: number, target)) then
        local spare = sparing(state, fleet, needed)
        if spare then
          pick, ships = fleet, spare
        end
      end
    end
    if pick and ships then
      local party = State.Split(state, pick, ships)
      if Actions.Move(state, party, target, "claim") then
        c.claims[target] = true
        claiming += 1
      end
    elseif faction.plan == nil then
      -- No fleet can spare enough on its own: gather a force next to it
      for _, system in c.systems do
        if table.find(state.galaxy.systems[system].neighbors, target) then
          faction.plan = { kind = "claim", target = target, staging = system, since = state.tick }
          State.Log(state, "plan", `{faction.name} gathers a force to claim {state.galaxy.systems[target].name}`)
          break
        end
      end
    end
  end
end

------------------------------------------------------------ Hunting pirates

local function huntPirates(state: State.State, faction: State.Faction, c: Census)
  for _, system in c.systems do
    if not c.hunts[system] then
      local pirates = State.IdleFleets(state, system, state.pirates)
      if #pirates > 0 then
        local threat = Combat.Strength(pirates)
        for _, fleet in c.idleWar do
          if available(fleet) and Combat.FleetStrength(fleet) >= 1.3 * threat
            and hops(state, fleet.system :: number, system) <= 4 then
            if fleet.system == system then
              break -- already here; a fight happens on the next arrival
            end
            if Actions.Move(state, detach(state, fleet), system, "hunt") then
              c.hunts[system] = true
            end
            break
          end
        end
      end
    end
  end
end

-------------------------------------------------------------------- War

-- A system's defence against an attack: its stations plus the owner's war
-- fleets close enough to relieve a siege
local function defenseOf(state: State.State, target: number): number
  local owner = state.systems[target].owner
  local defense = State.StationDefense(state, target)
  local reach = Data.SIEGE_TICKS // Data.JUMP_TICKS + 1
  for _, fleet in state.fleets do
    if fleet.owner == owner and fleet.role == "war" and fleet.system
      and hops(state, fleet.system :: number, target) <= reach then
      defense += Combat.FleetStrength(fleet)
    end
  end
  return defense
end

local MUSTER_RANGE = 15
local PLAN_PATIENCE = 360    -- ticks to gather a force before giving up (1 hour)

-- Attacks are prepared: pick an enemy border system that can be taken at
-- the attack odds, gather fleets at a staging system next to it, and
-- launch when the gathered force is strong enough
local function attack(state: State.State, faction: State.Faction, c: Census)
  local plan = faction.plan
  if plan then
    local p = plan :: State.Plan
    local targetOwner = state.systems[p.target].owner
    local valid = if p.kind == "claim" then targetOwner == nil else isEnemy(state, faction, targetOwner)
    if not valid or state.systems[p.staging].owner ~= faction.id then
      faction.plan = nil
      return
    end
    local need = if p.kind == "claim"
      then math.max(1, Data.ATTACK_ODDS * State.StationDefense(state, p.target) * Data.INDEPENDENT_DEFENSE)
      else Data.ATTACK_ODDS * defenseOf(state, p.target)
    local here = State.IdleFleets(state, p.staging, faction.id, "war")
    local strength = Combat.Strength(here)
    if strength >= need then
      for _, fleet in here do
        Actions.Move(state, detach(state, fleet), p.target, p.kind)
      end
      faction.plan = nil
      State.Log(state, "assault", `{faction.name} launches {if p.kind == "claim" then "a claim on" else "an assault on"} `
        .. `{state.galaxy.systems[p.target].name} ({math.floor(strength)} against {math.floor(need / Data.ATTACK_ODDS)})`)
      return
    end
    -- Call in more: fleets already on the way count
    local projected = strength
    for _, action in state.actions do
      if action.owner == faction.id and action.intent == "muster" and action.target == p.staging then
        projected += Combat.FleetStrength(state.fleets[action.fleet :: number])
      end
    end
    local candidates = {}
    for _, fleet in c.idleWar do
      if available(fleet) and fleet.system ~= p.staging and hops(state, fleet.system :: number, p.staging) <= MUSTER_RANGE then
        table.insert(candidates, fleet)
      end
    end
    table.sort(candidates, function(a, b)
      local da, db = hops(state, a.system :: number, p.staging), hops(state, b.system :: number, p.staging)
      if da ~= db then return da < db end
      return a.id < b.id
    end)
    for _, fleet in candidates do
      if projected >= need then
        break
      end
      local party = detach(state, fleet)
      if Actions.Move(state, party, p.staging, "muster") then
        projected += Combat.FleetStrength(party)
      end
    end
    if projected < need and state.tick - p.since > PLAN_PATIENCE then
      faction.plan = nil
    end
    return
  end

  local limit = 1 + math.floor(2 * faction.traits.aggressive)
  if c.attacks >= limit then
    return
  end
  local available_ = 0
  for _, fleet in c.idleWar do
    if available(fleet) then
      available_ += Combat.FleetStrength(fleet)
    end
  end
  local best: State.Plan? = nil
  local bestScore = 0
  local seen: { [number]: boolean } = {}
  for _, system in c.systems do
    for _, target in state.galaxy.systems[system].neighbors do
      if not seen[target] and isEnemy(state, faction, state.systems[target].owner) then
        seen[target] = true
        local defense = defenseOf(state, target)
        if available_ >= Data.ATTACK_ODDS * defense then
          local score = (10 * #state.galaxy.systems[target].stations + 5) / (defense + 1)
          if score > bestScore then
            bestScore = score
            best = { kind = "attack", target = target, staging = system, since = state.tick }
          end
        end
      end
    end
  end
  if best then
    faction.plan = best
    State.Log(state, "plan", `{faction.name} prepares an assault on {state.galaxy.systems[best.target].name}`)
  end
end

-- Drops actions that no longer make sense: attacks on systems no longer
-- hostile, convoys whose delivery station became hostile
local function review(state: State.State, faction: State.Faction)
  local ids = {}
  for id, action in state.actions do
    if action.owner == faction.id then
      table.insert(ids, id)
    end
  end
  table.sort(ids)
  for _, id in ids do
    local action = state.actions[id]
    local owner = if action.target then state.systems[action.target :: number].owner else nil
    -- A siege of an independent system is a claim being pacified: it only
    -- lapses if someone else takes the system first
    local stale = if action.intent == "siege" and owner == nil then false
      elseif action.intent == "siege" then not isEnemy(state, faction, owner)
      elseif action.intent == "attack" then not isEnemy(state, faction, owner)
      else false
    if stale and not action.cancelled then
      Actions.Cancel(state, faction.id, id)
    elseif action.kind == "convoy" and not action.cancelled then
      local dest = state.stations[action.to :: number].system
      if isEnemy(state, faction, state.systems[dest].owner) then
        Actions.Cancel(state, faction.id, id)
      end
    end
  end
end

---------------------------------------------------------------- Pirates

local function dens(state: State.State): { number }
  local list = {}
  for _, system in state.systems do
    if system.owner == state.pirates then
      table.insert(list, system.id)
    end
  end
  return list
end

local function nearest(state: State.State, from: number, systems: { number }): number?
  local best: number? = nil
  for _, s in systems do
    if best == nil or hops(state, from, s) < hops(state, from, best :: number) then
      best = s
    end
  end
  return best
end

local function piratesAct(state: State.State, faction: State.Faction, c: Census)
  local homes = dens(state)
  local fleetShips = 0
  for _, fleet in state.fleets do
    if fleet.owner == faction.id then
      fleetShips += State.ShipCount(fleet)
    end
  end
  -- Recruit at the dens with plunder
  for _, home in homes do
    for _, id in state.galaxy.systems[home].stations do
      local station = state.stations[id]
      if station.kind == "den" and fleetShips < 8 * #homes then
        if Actions.Build(state, station, "frigate", Data.PIRATE_FRIGATE_CREDITS) then
          fleetShips += 1
        end
      end
    end
  end
  for _, fleet in c.idleWar do
    if not available(fleet) then
      continue
    end
    local at = fleet.system :: number
    local atHome = state.systems[at].owner == faction.id
    if not atHome and state.tick - fleet.idleSince > 30 then
      local home = nearest(state, at, homes)
      if home then
        Actions.Move(state, fleet, home, "home")
      end
    elseif atHome and (fleet.ships.frigate or 0) >= 3 and (state.tick + fleet.id) % 12 == 0 then
      -- Raid the richest weakly defended system within reach
      local strength = Combat.FleetStrength(fleet)
      local best, bestScore = 0, 0
      for _, system in state.systems do
        local d = hops(state, at, system.id)
        if d >= 1 and d <= 5 and system.owner ~= faction.id then
          local defense = Combat.Strength(State.IdleFleets(state, system.id, system.owner)) + State.StationDefense(state, system.id)
          if defense < 0.7 * strength then
            local loot = 0
            for _, id in state.galaxy.systems[system.id].stations do
              for good, n in state.stations[id].stock do
                loot += 0.25 * n * Data.GoodById[good].base
              end
            end
            local score = loot / (d + 1)
            if score > bestScore then
              best, bestScore = system.id, score
            end
          end
        end
      end
      if best > 0 and bestScore > 300 then
        Actions.Move(state, fleet, best, "raid")
      end
    end
  end
end

-- Ambush loaded convoys on their way
local function ambush(state: State.State, faction: State.Faction, c: Census)
  local ids = {}
  for id, action in state.actions do
    if action.kind == "convoy" and action.stage == "deliver" and action.owner ~= faction.id then
      table.insert(ids, id)
    end
  end
  table.sort(ids)
  for _, id in ids do
    local key = `ambush:{id}`
    if not state.reacted[key] then
      state.reacted[key] = true
      local convoy = state.actions[id]
      local fleet = state.fleets[convoy.fleet :: number]
      local good = convoy.good :: string
      local value = (fleet and fleet.cargo[good] or 0) * Data.GoodById[good].base
      if value >= 600 then
        local path = convoy.path :: { number }
        local step = convoy.step :: number
        local bestFleet: State.Fleet? = nil
        local bestSystem, bestHops = 0, math.huge
        for _, raider in c.idleWar do
          if available(raider) and (raider.ships.frigate or 0) >= 2 then
            for k = step, #path do
              local eta = (convoy.due - state.tick) + (k - step) * Data.JUMP_TICKS
              local d = hops(state, raider.system :: number, path[k])
              if d <= 5 and d * Data.JUMP_TICKS < eta and d < bestHops then
                bestFleet, bestSystem, bestHops = raider, path[k], d
              end
            end
          end
        end
        if bestFleet and bestHops > 0 then
          Actions.Move(state, bestFleet, bestSystem, "ambush")
        end
      end
    end
  end
end

---------------------------------------------------------------- Defence

local function defend(state: State.State, faction: State.Faction, c: Census)
  local ids = {}
  for id, action in state.actions do
    if (action.intent == "attack" or action.intent == "raid" or action.intent == "siege") and action.owner ~= faction.id
      and state.systems[action.target :: number].owner == faction.id then
      table.insert(ids, id)
    end
  end
  table.sort(ids)
  for _, id in ids do
    local key = `defend:{faction.id}:{id}`
    if not state.reacted[key] then
      state.reacted[key] = true
      local threat = state.actions[id]
      local attacker = state.fleets[threat.fleet :: number]
      if attacker then
        -- A siege has no path left: the time left is until the system falls
        local path: { number } = threat.path or {}
        local step: number = threat.step or 1
        local target = threat.target :: number
        local eta = (threat.due - state.tick) + math.max(0, #path - step) * Data.JUMP_TICKS
        local danger = Combat.FleetStrength(attacker)
        local defense = Combat.Strength(State.IdleFleets(state, target, faction.id)) + State.StationDefense(state, target)
        if defense < 1.1 * danger then
          -- Intercept on the way with one strong enough fleet, if one can get there first
          local done = false
          for _, fleet in c.idleWar do
            if not done and available(fleet) and fleet.system ~= target and Combat.FleetStrength(fleet) >= 1.2 * danger then
              for k = step, #path - 1 do
                local point = path[k]
                local theirs = (threat.due - state.tick) + (k - step) * Data.JUMP_TICKS
                local ours = hops(state, fleet.system :: number, point) * Data.JUMP_TICKS
                if ours < theirs and not isEnemy(state, faction, state.systems[point].owner) then
                  if fleet.system == point or Actions.Move(state, fleet, point, "intercept") then
                    State.Log(state, "intercept", `{faction.name} moves to intercept {state.factions[threat.owner].name} at {state.galaxy.systems[point].name}`)
                    done = true
                    break
                  end
                end
              end
            end
          end
          -- Otherwise reinforce the target, if enough can arrive in time
          if not done then
            local helpers: { State.Fleet } = {}
            local total = defense
            -- Fleets idle at the start of the tick may have left since
            local candidates = {}
            for _, fleet in c.idleWar do
              if available(fleet) then
                table.insert(candidates, fleet)
              end
            end
            table.sort(candidates, function(a, b)
              local da, db = hops(state, a.system :: number, target), hops(state, b.system :: number, target)
              if da ~= db then return da < db end
              return a.id < b.id
            end)
            for _, fleet in candidates do
              if total < 1.2 * danger and available(fleet) and fleet.system ~= target
                and hops(state, fleet.system :: number, target) * Data.JUMP_TICKS < eta then
                table.insert(helpers, fleet)
                total += Combat.FleetStrength(fleet)
              end
            end
            if total >= 1.2 * danger then
              for _, fleet in helpers do
                Actions.Move(state, fleet, target, "reinforce")
              end
              if #helpers > 0 then
                State.Log(state, "reinforce", `{faction.name} reinforces {state.galaxy.systems[target].name} against {state.factions[threat.owner].name}`)
              end
            end
          end
        end
      end
    end
  end
end

--------------------------------------------------------------- Phases

-- Seconds spent in each decision, accumulated (for profiling)
Ai.Timing = {} :: { [string]: number }

local function timed<A...>(name: string, f: (A...) -> (), ...: A...)
  local started = os.clock()
  f(...)
  Ai.Timing[name] = (Ai.Timing[name] or 0) + os.clock() - started
end

function Ai.ActionPhase(state: State.State, faction: State.Faction, c: Census, index: Market.Index)
  if not faction.alive then
    return
  end
  if faction.pirate then
    timed("pirates", piratesAct, state, faction, c)
    return
  end
  timed("build", buildShips, state, faction, c)
  local slot = (state.tick + faction.id) % 6
  if slot % 3 == 0 then
    timed("trade", trade, state, faction, c, index)
  end
  if slot == 1 then
    timed("review", review, state, faction)
    timed("expand", expand, state, faction, c)
  elseif slot == 2 then
    timed("hunt", huntPirates, state, faction, c)
  elseif slot == 4 then
    timed("attack", attack, state, faction, c)   -- also follows up prepared claims
  end
end

function Ai.ReactionPhase(state: State.State, faction: State.Faction, c: Census)
  if not faction.alive then
    return
  end
  if faction.pirate then
    ambush(state, faction, c)
  else
    defend(state, faction, c)
  end
end

return Ai
