--!strict
-- How a power's government decides: what to spend, what to build, where
-- to grow, when to attack and what to defend.
--
-- Everything here is done through Strategic/Orders, Battle.Besiege and
-- Diplomacy: a government has no way to act that a player ruling a
-- power would not have. There is no fog between powers: a government
-- sees every fleet and every plan.
--
-- A power keeps its free fleets together at its capital and sends
-- detachments out for a purpose; a system can be reached from the
-- capital in minutes, and a siege takes an hour.
--
--   Budget    every period. Decide how much fleet the income can carry.
--             Short of money: lay ships up, then police less, then give
--             up the system that costs most for what it brings. Flush:
--             bring ships back and police fully.
--   Build     keep the fleet at what the budget allows, in a mix of
--             classes.
--   Expand    claim the independent neighbour that will pay best, if any
--             will pay at all: holding a system costs more the farther
--             it is and the more systems there are.
--   Attack    at war, pick an enemy border system worth having, gather a
--             force beside it in the open, and go when it is enough:
--             three to one over the defences and a margin over what the
--             enemy can bring.
--   Defend    send what is free to a system under siege or raid, if it
--             is enough to matter.
--   Hunt      destroy a pirate den near home.

local Battle = require("@lt/Core/Strategic/Battle")
local Diplomacy = require("@lt/Core/Strategic/Diplomacy")
local Fiscal = require("@lt/Core/Strategic/Fiscal")
local Goods = require("@lt/Core/Data/Goods")
local Orders = require("@lt/Core/Strategic/Orders")
local Powers = require("@lt/Core/Data/Powers")
local Routes = require("@lt/Core/Strategic/Routes")
local World = require("@lt/Core/Strategic/World")

local Mind = {}

local KITS = Goods.Index("construction.kits")

-- What a unit of strength costs an hour on active service, near enough:
-- its crew, and its supplies at normal prices.
local UPKEEP = Powers.PAY + 45
-- The mix a navy aims for, as shares of its strength by ship class.
local MIX = { 0.35, 0.40, 0.25 }
-- How long a fleet stays in a system it has just taken or relieved.
local HOLD = 360
-- The least a power keeps on active service whatever its finances.
local CADRE = 20

-- A fleet that can be given something to do.
local function free(fleet: World.Fleet): boolean
  return fleet.action == 0 and fleet.system > 0 and fleet.task == ""
end

local function laidUp(faction: World.Faction): number
  local total = 0
  for class, count in faction.reserve do
    total += count * Powers.ships[class].strength
  end
  return total
end

-- The fleet the income can carry, in strength.
function Mind.Affordable(world: World.World, faction: World.Faction): number
  local sov, police = Fiscal.Fixed(world, faction)
  local share = Powers.FLEET_SHARE + 0.15 * faction.traits.aggressive + (if World.AtWar(world, faction.id) then 0.2 else 0)
  local spare = (faction.credits - Powers.TREASURY_HOURS * faction.costs) / Powers.SPEND_HOURS
  return math.max(CADRE, ((faction.income - sov - police) * math.min(0.9, share) + spare) / UPKEEP)
end

-- The free fleet at the capital (all of them folded into one), and its
-- strength.
local function reserveFleet(world: World.World, faction: World.Faction): World.Fleet?
  if faction.capital == 0 then
    return nil
  end
  local main: World.Fleet? = nil
  for _, id in table.clone(world.systems[faction.capital].fleets) do
    local fleet = world.fleets[id]
    if fleet.owner == faction.id and free(fleet) then
      if main then
        World.Merge(world, main, fleet)
      else
        main = fleet
      end
    end
  end
  return main
end

-- What must stay at home.
local function guard(world: World.World, faction: World.Faction): number
  return Powers.HOME_GUARD * World.Navy(world, faction.id)
end

-- Ships out of 'fleet' worth at least 'needed', smallest classes first
-- for a small job, leaving at least 'keep' behind. Nil if it cannot.
local function detachment(fleet: World.Fleet, needed: number, keep: number): { number }?
  if World.Strength(fleet) - keep < needed then
    return nil
  end
  local supplied = if fleet.supply > 0 then 1 else Powers.UNSUPPLIED
  local take: { number } = table.create(#Powers.ships, 0)
  local got = 0
  for class, ship in Powers.ships do
    local each = ship.strength * supplied
    local k = math.min(fleet.ships[class], math.ceil((needed - got) / each))
    if k > 0 then
      take[class] = k
      got += k * each
    end
    if got >= needed then
      break
    end
  end
  return if got >= needed then take else nil
end

-- ---------------------------------------------------------------------
-- Budget

function Mind.Budget(world: World.World, faction: World.Faction)
  local navy = World.Navy(world, faction.id)
  local affordable = Mind.Affordable(world, faction)
  local runway = Powers.RESERVE_HOURS * faction.costs
  local short = faction.credits < 2 * faction.costs or (faction.income < faction.costs and faction.credits < runway)

  if short or navy > 1.15 * affordable then
    -- Lay up what the budget cannot carry, from the fleet at home.
    local excess = math.max(navy - affordable, if short then (faction.costs - faction.income) / UPKEEP else 0)
    local main = reserveFleet(world, faction)
    if main and excess > 0 and navy > CADRE then
      local take = detachment(main, math.min(excess, navy - CADRE, World.Strength(main)), 0)
      if take then
        Orders.Mothball(world, main, take)
      end
    end
  end
  if short then
    if faction.policing > 0.25 and faction.income < faction.costs then
      Orders.SetPolicing(world, faction, faction.policing - 0.25)
    end
    -- Still owing: let go of the system that costs most for what it
    -- brings.
    if faction.arrears > 0 or faction.credits < 0 then
      local worst, worstNet = 0, 0
      for id, s in world.systems do
        if s.owner == faction.id and id ~= faction.capital then
          local net = World.Yield(world, id, s.control) - World.SovCost(world, faction, id, faction.systems)
          if net < worstNet then
            worst, worstNet = id, net
          end
        end
      end
      if worst > 0 then
        Orders.Release(world, faction, worst)
      end
    end
  elseif not World.AtWar(world, faction.id) and faction.systems > 1 then
    -- At peace and solvent: still, a system that costs far more than it
    -- brings is let go. (Counting what the others would cost less
    -- without it.)
    local sov = Fiscal.Fixed(world, faction)
    local saved = World.SovDearer(faction, sov)
    local worst, worstNet = 0, Powers.RELEASE_BELOW
    for id, s in world.systems do
      if s.owner == faction.id and id ~= faction.capital and s.siege == nil then
        local hold = if World.Foreign(world, id, faction.id) then 0.7 * Powers.OCCUPIED else 0.7
        local net = World.Yield(world, id, math.max(s.control, hold)) - World.SovCost(world, faction, id, faction.systems) - saved
          - faction.policing * Powers.POLICE * (1 + world.atlas.systems[id].population)
        if net < worstNet then
          worst, worstNet = id, net
        end
      end
    end
    if worst > 0 then
      Orders.Release(world, faction, worst)
    end
  end
  if not short and faction.income > 1.1 * faction.costs and faction.credits > runway then
    if faction.policing < 1 then
      Orders.SetPolicing(world, faction, faction.policing + 0.25)
    end
    -- Bring ships back while the budget has room for them.
    local room = affordable - navy
    for class, ship in Powers.ships do
      local k = math.min(faction.reserve[class], math.floor(room / ship.strength))
      if k > 0 and Orders.Reactivate(world, faction, class, k) then
        room -= k * ship.strength
      end
    end
  end
end

-- ---------------------------------------------------------------------
-- Build

local function build(world: World.World, faction: World.Faction)
  local navy = World.Navy(world, faction.id)
  local have = navy + laidUp(faction)
  local byClass: { number } = table.create(#Powers.ships, 0)
  for _, id in world.fleetIds do
    local fleet = world.fleets[id]
    if fleet.owner == faction.id then
      for class, count in fleet.ships do
        byClass[class] += count * Powers.ships[class].strength
      end
    end
  end
  for _, id in world.actionIds do
    local action = world.actions[id]
    if action.owner == faction.id and (action.kind == "build" or action.kind == "reactivate") then
      local strength = action.count * Powers.ships[action.ship].strength
      byClass[action.ship] += strength
      have += strength
    end
  end
  local target = Mind.Affordable(world, faction)
  if have >= target then
    return
  end
  -- (what is being kept for a claim is not there to spend)
  local runway = Powers.RESERVE_HOURS * faction.costs + faction.earmark
  -- The class furthest under its share of the fleet that the treasury
  -- can pay for and the gap has room for.
  for _ = 1, Powers.YARD_SLOTS do
    local pick, pickLack = 0, 0
    for class, ship in Powers.ships do
      local lack = MIX[class] * target - byClass[class]
      local price = Orders.ShipPrice(world, faction.capital, class)
      if lack > pickLack and price and faction.credits - price > runway and ship.strength <= target - have + 1 then
        pick, pickLack = class, lack
      end
    end
    if pick == 0 or not Orders.Build(world, faction, pick) then
      return
    end
    byClass[pick] += Powers.ships[pick].strength
    have += Powers.ships[pick].strength
  end
end

-- ---------------------------------------------------------------------
-- Expand

-- What a system would bring a faction, less what holding and policing
-- it would cost: both an hour, with one more system on the books.
local function netWorth(world: World.World, faction: World.Faction, system: number, sov: number): number
  local people = world.atlas.systems[system].population
  local count = faction.systems + 1
  -- (the hold it can expect: less on another power's ground)
  local hold = if World.Foreign(world, system, faction.id) then 0.7 * Powers.OCCUPIED else 0.7
  -- (every system already held costs more for each one added)
  return World.Yield(world, system, hold) - World.SovCost(world, faction, system, count) - World.SovDearer(faction, sov)
    - faction.policing * Powers.POLICE * (1 + people)
end

local function expand(world: World.World, faction: World.Faction)
  local claiming = 0
  local taken: { [number]: boolean } = {}
  for _, id in world.fleetIds do
    local fleet = world.fleets[id]
    if fleet.owner == faction.id and fleet.task == "claim" then
      claiming += 1
      taken[fleet.target] = true
    end
  end
  faction.earmark = 0
  if claiming >= 1 + math.floor(2 * faction.traits.greedy + 0.5) or faction.income < faction.costs then
    return
  end
  local sov = Fiscal.Fixed(world, faction)
  local best, bestScore = 0, 0
  local seen: { [number]: boolean } = {}
  for id, s in world.systems do
    if s.owner == faction.id then
      for _, n in world.galaxy.systems[id].neighbors do
        local there = world.systems[n]
        if not seen[n] and there.owner == 0 and not there.den and not taken[n] and there.siege == nil then
          seen[n] = true
          local score = netWorth(world, faction, n, sov)
          -- A poor system is worth taking for the sake of a good one
          -- behind it.
          local beyond = 0
          for _, m in world.galaxy.systems[n].neighbors do
            if world.systems[m].owner == 0 and not world.systems[m].den then
              beyond = math.max(beyond, netWorth(world, faction, m, sov))
            end
          end
          score += 0.5 * beyond
          if score > bestScore then
            best, bestScore = n, score
          end
        end
      end
    end
  end
  if best == 0 then
    return
  end
  local main = reserveFleet(world, faction)
  if main == nil then
    return
  end
  local needed = math.max(3, Powers.ATTACK_ODDS * World.Defence(world, best))
  for _, id in world.systems[best].fleets do
    if World.Hostile(world, faction.id, world.fleets[id].owner) then
      needed += 1.5 * World.Strength(world.fleets[id])
    end
  end
  local kits = Orders.ClaimKits(world, best)
  local price = Orders.Price(world, faction.capital, KITS, kits)
  local take = detachment(main, needed, guard(world, faction))
  if take == nil or price == nil then
    return
  end
  if faction.credits - price < Powers.RESERVE_HOURS * faction.costs then
    -- Not yet: but the yards are not to spend what this is waiting for.
    faction.earmark = price
    return
  end
  local party = World.Split(world, main, take)
  if Orders.BuyKits(world, party, kits) < kits - 1e-6 then
    -- (the market ran short between the asking and the buying)
    main.kits += party.kits
    party.kits = 0
    World.Merge(world, main, party)
    return
  end
  Orders.Move(world, party, best, "claim")
end

-- ---------------------------------------------------------------------
-- Attack

-- What a faction needs at an enemy system to take it: three to one over
-- its defences at full strength, and a margin (smaller for the bold)
-- over the fleet its owner can bring.
local function needed(world: World.World, faction: World.Faction, target: number): number
  local owner = world.systems[target].owner
  local theirs = if owner > 0 then (1 - Powers.HOME_GUARD) * World.Navy(world, owner) else 0
  local margin = 1.3 - 0.4 * faction.traits.aggressive
  return Powers.ATTACK_ODDS * World.FullDefence(world, target) + margin * theirs
end

-- The enemy system most worth attacking that a faction could take with
-- 'field' strength, and the system of its own to gather beside it.
-- 'enemy' is the owner to look at; 0 for everyone it is at war with.
local function target(world: World.World, faction: World.Faction, enemy: number, field: number): (number, number)
  local routes = Routes.For(world.galaxy)
  local sov = Fiscal.Fixed(world, faction)
  local best, bestScore, bestStaging = 0, 0, 0
  for id, s in world.systems do
    local theirs = if enemy > 0 then s.owner == enemy
      else s.owner > 0 and s.owner ~= world.pirates and World.Hostile(world, faction.id, s.owner)
    if theirs then
      -- Somewhere of its own to gather: next door, or failing that two
      -- jumps off (across a system neither holds).
      local staging = 0
      local neighbors = world.galaxy.systems[id].neighbors
      for _, n in neighbors do
        if world.systems[n].owner == faction.id
          and (staging == 0 or routes.hops[faction.capital][n] < routes.hops[faction.capital][staging]) then
          staging = n
        end
      end
      if staging == 0 then
        for _, n in neighbors do
          for _, m in world.galaxy.systems[n].neighbors do
            if world.systems[m].owner == faction.id
              and (staging == 0 or routes.hops[faction.capital][m] < routes.hops[faction.capital][staging]) then
              staging = m
            end
          end
        end
      end
      -- Not a system that would be a millstone: a power too large to
      -- hold a poor system does not fight for one.
      if staging > 0 and netWorth(world, faction, id, sov) > 2 * Powers.RELEASE_BELOW
        and field >= needed(world, faction, id) then
        local info = world.atlas.systems[id]
        -- Worth more if it lies in what was always this power's part of
        -- the map.
        local score = info.population * (if info.owner == faction.id then 1.5 else 1) / (World.FullDefence(world, id) + 5)
        if score > bestScore then
          best, bestScore, bestStaging = id, score, staging
        end
      end
    end
  end
  return best, bestStaging
end

-- Would this power start a war with that one now? Only if it thinks its
-- fleet a match for the other's, and can see something it could take.
function Mind.WantsWar(world: World.World, faction: World.Faction, other: World.Faction): boolean
  if not Diplomacy.Confident(world, faction, other) then
    return false
  end
  local field = (1 - Powers.HOME_GUARD) * World.Navy(world, faction.id)
  return (target(world, faction, other.id, field)) > 0
end

local function attack(world: World.World, faction: World.Faction)
  local plan = faction.plan
  if plan then
    local owner = world.systems[plan.target].owner
    local valid = World.Hostile(world, faction.id, owner) and world.systems[plan.staging].owner == faction.id
    if not valid then
      faction.plan = nil
      return
    end
    if plan.launched then
      -- On its way or at work. The plan is done with when the siege
      -- begins (Sim), or if the force never gets there.
      for _, id in world.fleetIds do
        local fleet = world.fleets[id]
        if fleet.owner == faction.id and fleet.task == "attack" and fleet.target == plan.target then
          return
        end
      end
      faction.plan = nil
      return
    end
    local need = needed(world, faction, plan.target)
    local gathered: { World.Fleet } = {}
    local here, coming = 0, 0
    for _, id in world.fleetIds do
      local fleet = world.fleets[id]
      if fleet.owner == faction.id and fleet.task == "muster" and fleet.target == plan.staging then
        if fleet.system == plan.staging and fleet.action == 0 then
          table.insert(gathered, fleet)
          here += World.Strength(fleet)
        else
          coming += World.Strength(fleet)
        end
      end
    end
    if here >= need and coming == 0 then
      for _, fleet in gathered do
        Orders.Move(world, fleet, plan.target, "attack")
      end
      plan.launched = true
      World.Count(world, "assaults launched")
      World.Log(world, "assault", `{faction.name} moves on {World.SystemName(world, plan.target)} with `
        .. `{math.floor(here)} against {math.floor(World.FullDefence(world, plan.target))}`, plan.target, faction.id, owner)
      return
    end
    -- Everything that can be spared goes: the defender will bring all
    -- it has, and a force cut to the bare need would meet it short.
    local main = reserveFleet(world, faction)
    if main then
      local spare = World.Strength(main) - guard(world, faction)
      local take = if spare >= 1 then detachment(main, spare, guard(world, faction)) else nil
      if take then
        Orders.Move(world, World.Split(world, main, take), plan.staging, "muster")
        return
      end
    end
    if coming > 0 and here + coming >= need then
      return
    end
    if world.tick - plan.since > Powers.PLAN_PATIENCE then
      faction.plan = nil
      World.Count(world, "plans dropped")
    end
    return
  end

  -- One offensive at a time, and none while the last gain is still
  -- being secured.
  for _, id in world.fleetIds do
    local fleet = world.fleets[id]
    if fleet.owner == faction.id and (fleet.task == "attack" or fleet.task == "muster" or fleet.task == "hold") then
      return
    end
  end
  local main = reserveFleet(world, faction)
  if main == nil then
    return
  end
  local best, bestStaging = target(world, faction, 0, World.Strength(main) - guard(world, faction))
  if best > 0 then
    faction.plan = { kind = "attack", target = best, staging = bestStaging, since = world.tick, launched = false }
    World.Count(world, "plans made")
    World.Log(world, "plan", `{faction.name} gathers a force at {World.SystemName(world, bestStaging)}, beside `
      .. `{World.SystemName(world, best)}`, best, faction.id, world.systems[best].owner)
  end
end

-- ---------------------------------------------------------------------
-- Defend

local function defend(world: World.World, faction: World.Faction)
  local main: World.Fleet? = nil
  for id, s in world.systems do
    if s.owner == faction.id then
      local threat = 0
      for _, fid in s.fleets do
        local fleet = world.fleets[fid]
        if World.Hostile(world, faction.id, fleet.owner) then
          threat += World.Strength(fleet)
        end
      end
      if threat > 0 then
        -- What is there or on its way already.
        local committed = 0
        for _, fid in world.fleetIds do
          local fleet = world.fleets[fid]
          if fleet.owner == faction.id and (fleet.system == id or (fleet.task == "relief" and fleet.target == id)) then
            committed += World.Strength(fleet)
          end
        end
        local want = 1.2 * threat - committed - World.Defence(world, id)
        if want > 0 then
          main = main or reserveFleet(world, faction)
          if main then
            -- The capital is defended with everything; anywhere else,
            -- with what can be spared.
            local keep = if id == faction.capital or main.system == id then 0 else guard(world, faction)
            local spare = World.Strength(main) - keep
            -- Only if it is enough to stand: half of what is there, at
            -- the least, or it would be thrown away.
            if spare + committed + World.Defence(world, id) >= 0.9 * threat and spare > 0 then
              -- (all of it: a relief sent in pieces is beaten in pieces)
              local take = detachment(main, if threat > 30 then spare else math.min(spare, want), keep)
              if take then
                Orders.Move(world, World.Split(world, main, take), id, "relief")
                World.Count(world, "reliefs sent")
              end
            end
          end
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------
-- Hunt

local function hunt(world: World.World, faction: World.Faction)
  local routes = Routes.For(world.galaxy)
  for _, id in world.fleetIds do
    local fleet = world.fleets[id]
    if fleet.owner == faction.id and fleet.task == "clear" then
      return
    end
  end
  if faction.income < faction.costs then
    return
  end
  local main = reserveFleet(world, faction)
  if main == nil then
    return
  end
  local best, bestHops, bestNeed = 0, 6, 0
  for id, s in world.systems do
    if s.den and s.owner == 0 and s.siege == nil and routes.hops[faction.capital][id] < bestHops then
      -- only a den that troubles this power: next to something it holds
      local near = false
      for _, n in world.galaxy.systems[id].neighbors do
        if world.systems[n].owner == faction.id then
          near = true
        end
      end
      if near then
        local need = Powers.ATTACK_ODDS * World.FullDefence(world, id) + 1.5 * World.StrengthAt(world, id, world.pirates)
        if World.Strength(main) - guard(world, faction) >= need then
          best, bestHops, bestNeed = id, routes.hops[faction.capital][id], need
        end
      end
    end
  end
  if best > 0 then
    local take = detachment(main, bestNeed, guard(world, faction))
    if take then
      Orders.Move(world, World.Split(world, main, take), best, "clear")
    end
  end
end

-- ---------------------------------------------------------------------
-- Keeping the fleets in order

local function review(world: World.World, faction: World.Faction)
  for _, id in World.FleetIds(world) do
    local fleet = world.fleets[id]
    if fleet and fleet.owner == faction.id and fleet.action == 0 and fleet.system > 0 then
      local at = fleet.system
      local siege = world.systems[at].siege
      local task = fleet.task
      if task == "claim" or task == "attack" or task == "clear" then
        if at ~= fleet.target then
          -- stopped on the way (an enemy fleet): go on once the way is clear
          local blocked = false
          for _, fid in world.systems[at].fleets do
            if World.Hostile(world, faction.id, world.fleets[fid].owner) then
              blocked = true
            end
          end
          if not blocked then
            Orders.Move(world, fleet, fleet.target, task)
          end
        elseif siege == nil or siege.by ~= faction.id then
          local kind: "siege" | "claim" | "clear" = if task == "attack" then "siege" elseif task == "claim" then "claim" else "clear"
          if not Battle.Besiege(world, fleet, kind) then
            fleet.task = ""
          end
        end
      elseif task == "hold" or task == "relief" then
        local threatened = false
        for _, fid in world.systems[at].fleets do
          if World.Hostile(world, faction.id, world.fleets[fid].owner) then
            threatened = true
          end
        end
        if task == "relief" and at == fleet.target then
          fleet.task = "hold"
          fleet.since = world.tick
        elseif not threatened and world.tick - fleet.since > HOLD then
          fleet.task = ""
        end
      elseif task == "muster" then
        local plan = faction.plan
        if plan == nil or plan.staging ~= fleet.target then
          fleet.task = ""
        elseif at ~= fleet.target then
          Orders.Move(world, fleet, fleet.target, "muster")
        end
      elseif task == "retreat" or task == "home" then
        fleet.task = ""
      end
      -- Whatever is free and away from the capital comes home.
      if fleet.task == "" and at ~= faction.capital and faction.capital > 0 then
        Orders.Move(world, fleet, faction.capital, "home")
      end
    end
  end
end

-- ---------------------------------------------------------------------
-- The round of decisions

-- Each power thinks once a minute, about one thing at a time, in turn.
function Mind.Think(world: World.World)
  local tick = world.tick
  for _, faction in world.factions do
    if faction.alive and not faction.pirate and (tick + faction.id) % 6 == 0 then
      local turn = ((tick + faction.id) // 6) % 6
      review(world, faction)
      if turn == 0 or turn == 3 then
        defend(world, faction)
      elseif turn == 1 then
        build(world, faction)
      elseif turn == 2 then
        expand(world, faction)
      elseif turn == 4 then
        attack(world, faction)
      else
        hunt(world, faction)
      end
    end
  end
end

return Mind
