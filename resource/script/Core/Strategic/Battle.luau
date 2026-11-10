--!strict
-- Fighting where the player is not: battles between fleets, and sieges.
--
-- A battle is not one roll. Every round (a minute) each side in a
-- system loses a share of the strength facing it, so the larger side's
-- advantage compounds (the square law), and a side that falls under
-- half of what faces it pulls out. A fight between equals lasts a
-- quarter of an hour and costs both dearly; a one-sided one is over in
-- a round or two. Because a battle is only the ships present and what
-- they did to each other this minute, it can be handed over, mid-fight,
-- to the tactical game when the player arrives, and taken back.
--
-- A system's own defences fight for whoever holds it: beside its fleets
-- when they are attacked there, and alone when it is assaulted.
--
-- A siege runs in stages, about an hour in all: the system is cut off
-- from trade; its defences are fought down; it is occupied. It stops
-- while an enemy fleet contests the system and ends if the besiegers
-- leave. Claiming an independent system is the same thing, shorter, and
-- needs construction kits to set up an administration.

local Economy = require("@lt/Core/Strategic/Economy")
local Goods = require("@lt/Core/Data/Goods")
local Orders = require("@lt/Core/Strategic/Orders")
local Powers = require("@lt/Core/Data/Powers")
local Rng = require("@lt/Core/Kernel/Rng")
local World = require("@lt/Core/Strategic/World")

local Battle = {}

-- ---------------------------------------------------------------------
-- Sieges

-- Begin a siege where a fleet is. 'planned' is the tick the plan could
-- first be seen (now, if it was not planned in the open).
function Battle.Besiege(world: World.World, fleet: World.Fleet, kind: "siege" | "claim" | "clear" | "raid",
  planned: number?): boolean
  local system = fleet.system
  if system == 0 then
    return false
  end
  local s = world.systems[system]
  local holder = World.Holder(world, system)
  if s.siege ~= nil then
    return s.siege.by == fleet.owner
  end
  local valid = if kind == "siege" then s.owner > 0 and World.Hostile(world, fleet.owner, s.owner)
    elseif kind == "claim" then s.owner == 0 and not s.den
    elseif kind == "clear" then s.den and s.owner == 0
    else holder ~= fleet.owner
  if not valid then
    return false
  end
  s.siege = {
    by = fleet.owner, kind = kind, since = world.tick, planned = planned or world.tick, progress = 0,
    stage = if kind == "siege" then "blockade" else "assault",
  }
  World.Count(world, `began: {kind}`)
  if kind == "siege" then
    World.Log(world, "siege", `{World.Name(world, fleet.owner)} lays siege to {World.SystemName(world, system)} `
      .. `({World.Name(world, s.owner)})`, system, fleet.owner, s.owner)
  end
  return true
end

local function release(world: World.World, system: number, owner: number, task: string)
  for _, id in world.systems[system].fleets do
    local fleet = world.fleets[id]
    if fleet.owner == owner then
      fleet.task = task
      fleet.since = world.tick
    end
  end
end

local function captured(world: World.World, system: number, siege: World.Siege)
  local s = world.systems[system]
  local old = s.owner
  local worth = world.atlas.systems[system].population
  local war = World.WarBetween(world, siege.by, old)
  if war then
    if war.a == siege.by then
      war.takenA += worth
    else
      war.takenB += worth
    end
  end
  World.Sour(world, siege.by, old, Powers.GRUDGE)
  World.Transfer(world, system, siege.by)
  s.defence = 0
  table.insert(world.warnings, (world.tick - siege.planned) / 6)
  World.Count(world, "captures")
  World.Log(world, "capture", `{World.Name(world, siege.by)} takes {World.SystemName(world, system)} from `
    .. `{World.Name(world, old)}`, system, siege.by, old)
  release(world, system, siege.by, "hold")
end

local function claimed(world: World.World, system: number, siege: World.Siege): boolean
  -- The kits come out of the besiegers' holds.
  local need = Orders.ClaimKits(world, system)
  local have = 0
  local s = world.systems[system]
  for _, id in s.fleets do
    local fleet = world.fleets[id]
    if fleet.owner == siege.by then
      have += fleet.kits
    end
  end
  if have < need - 1e-6 then
    return false
  end
  for _, id in s.fleets do
    local fleet = world.fleets[id]
    if fleet.owner == siege.by and need > 0 then
      local used = math.min(need, fleet.kits)
      fleet.kits -= used
      need -= used
    end
  end
  World.Transfer(world, system, siege.by)
  World.Count(world, "claims")
  World.Log(world, "claim", `{World.Name(world, siege.by)} claims {World.SystemName(world, system)}`, system, siege.by)
  release(world, system, siege.by, "hold")
  return true
end

local function cleared(world: World.World, system: number, siege: World.Siege)
  local s = world.systems[system]
  -- The den's share of the pirates' hoard goes to whoever took it.
  local dens = 0
  for _, other in world.systems do
    if other.den then
      dens += 1
    end
  end
  World.Pay(world, world.pirates, siege.by, math.max(0, world.factions[world.pirates].credits) / math.max(1, dens), "den plunder")
  s.den = false
  s.siege = nil
  s.pressure = math.max(0, s.pressure - 0.5)
  World.Count(world, "dens destroyed")
  World.Log(world, "den", `{World.Name(world, siege.by)} destroys the pirate den at {World.SystemName(world, system)}`,
    system, siege.by)
  release(world, system, siege.by, "")
end

-- Pirates take a share of whatever is worth carrying, and what they can
-- sell it for.
local function raided(world: World.World, system: number, siege: World.Siege)
  local s = world.systems[system]
  local econ = world.econ
  -- What is there worth taking, and how much of it the band can carry.
  local there = 0
  for g, class in Goods.list do
    if class.tier == "consumer" or class.tier == "military" or class.tier == "part" then
      there += econ.nodes[system].stock[g] * class.par
    end
  end
  local haul = math.min(Powers.RAID_SHARE * there, Powers.RAID_HAUL * World.StrengthAt(world, system, siege.by))
  local share = if there > 0 then haul / there else 0
  local value = 0
  for g, class in Goods.list do
    if class.tier == "consumer" or class.tier == "military" or class.tier == "part" then
      value += Economy.Take(econ, system, g, econ.nodes[system].stock[g] * share) * class.par
    end
  end
  -- The loot is sold at once. (It also counts among the goods lost, so
  -- the tally the lanes' cut is taken from is moved on past it.)
  World.Pay(world, 0, siege.by, Powers.FENCE * value, "raid loot")
  world.loot += value
  s.siege = nil
  s.raided = world.tick
  s.pressure = math.min(1, s.pressure + Powers.RAID_PRESSURE)
  s.control = math.max(0, s.control - Powers.RAID_CONTROL)
  World.Count(world, "raids")
  World.Count(world, "raided value", value)
  World.Log(world, "raid", `Pirates raid {World.SystemName(world, system)} ({World.Name(world, s.owner)}): goods worth `
    .. `{math.floor(value)} taken`, system, siege.by, s.owner)
  release(world, system, siege.by, "home")
end

-- How long a siege that cannot finish may hang on in its last stage.
local STALLED = 360

local function lift(world: World.World, system: number, siege: World.Siege, why: string?)
  world.systems[system].siege = nil
  if siege.kind == "siege" and why then
    World.Log(world, "lifted", `The siege of {World.SystemName(world, system)} is lifted: {why}`, system, siege.by)
  end
  World.Count(world, `failed: {siege.kind}`)
  release(world, system, siege.by, "")
end

-- Advance every siege by a round.
function Battle.Sieges(world: World.World)
  for system, s in world.systems do
    local siege = s.siege
    if siege then
      local by = siege.by
      local besiegers = World.StrengthAt(world, system, by)
      local valid = if siege.kind == "siege" then s.owner > 0 and World.Hostile(world, by, s.owner)
        elseif siege.kind == "claim" then s.owner == 0
        elseif siege.kind == "clear" then s.den
        else true
      if besiegers <= 0 then
        lift(world, system, siege, "the besiegers are gone")
      elseif not valid then
        lift(world, system, siege, nil)
      else
        local contested = false
        for _, id in s.fleets do
          if World.Hostile(world, by, world.fleets[id].owner) then
            contested = true
          end
        end
        if not contested then
          local beaten = s.defence <= Powers.DEFENCE_BEATEN
          siege.progress += Powers.ROUND_TICKS
          if siege.kind == "siege" then
            local assault = Powers.SIEGE_BLOCKADE + Powers.SIEGE_ASSAULT
            if siege.stage == "blockade" and siege.progress >= Powers.SIEGE_BLOCKADE then
              siege.stage = "assault"
            elseif siege.stage == "assault" then
              if siege.progress >= assault and beaten then
                siege.stage = "occupy"
                World.Log(world, "siege", `{World.SystemName(world, system)}'s defences have fallen to `
                  .. `{World.Name(world, by)}`, system, by, s.owner)
              else
                siege.progress = math.min(siege.progress, assault)
              end
            elseif siege.stage == "occupy" and siege.progress >= assault + Powers.SIEGE_OCCUPY then
              captured(world, system, siege)
            end
          elseif siege.kind == "raid" then
            if s.defence <= Powers.RAID_BEATEN and siege.progress >= 30 then
              raided(world, system, siege)
            end
          else
            if siege.stage == "assault" then
              if siege.progress >= Powers.CLAIM_ASSAULT and beaten then
                siege.stage = "occupy"
              else
                siege.progress = math.min(siege.progress, Powers.CLAIM_ASSAULT)
              end
            elseif siege.progress >= Powers.CLAIM_ASSAULT + Powers.CLAIM_OCCUPY then
              if siege.kind == "clear" then
                cleared(world, system, siege)
              elseif not claimed(world, system, siege) and siege.progress > Powers.CLAIM_ASSAULT + Powers.CLAIM_OCCUPY + STALLED then
                lift(world, system, siege, nil)
              end
            end
          end
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------
-- Rounds

-- Take 'share' of a fleet's ships, rounding by chance so that small
-- fleets lose ships too. Returns the strength lost.
local function lose(rng: Rng.Rng, fleet: World.Fleet, share: number): number
  local lost = 0
  for class, count in fleet.ships do
    if count > 0 then
      local k = math.min(count, Rng.Round(rng, count * share))
      fleet.ships[class] = count - k
      lost += k * Powers.ships[class].strength
    end
  end
  return lost
end

-- Fight a round in every system where enemies meet.
function Battle.Round(world: World.World)
  -- The systems with fleets in them, in id order.
  local seen: { [number]: boolean } = {}
  local places: { number } = {}
  for _, id in world.fleetIds do
    local system = world.fleets[id].system
    if system > 0 and not seen[system] then
      seen[system] = true
      table.insert(places, system)
    end
  end
  table.sort(places)

  local factionCount = #world.factions
  for _, system in places do
    local s = world.systems[system]
    -- Each faction's strength here.
    local strength: { number } = table.create(factionCount, 0)
    local present: { number } = {}
    for _, id in s.fleets do
      local fleet = world.fleets[id]
      if strength[fleet.owner] == 0 then
        table.insert(present, fleet.owner)
      end
      strength[fleet.owner] += math.max(1e-9, World.Strength(fleet))
    end
    table.sort(present)
    local holder = World.Holder(world, system)
    local defence = World.Defence(world, system)
    local siege = s.siege
    local full = World.FullDefence(world, system)

    -- Whom the defences engage: a faction assaulting the system, and any
    -- enemy of the holder while the holder's own fleet is here to fight.
    local function engaged(o: number): boolean
      if defence <= 0 or o == holder then
        return false
      end
      if siege and siege.by == o and siege.stage == "assault" then
        return true
      end
      return holder > 0 and strength[holder] > 0 and World.Hostile(world, holder, o)
    end

    local facing: { number } = table.create(factionCount, 0)
    local facingDefence = 0
    local fleetsFight = false
    for _, o in present do
      for _, p in present do
        if p ~= o and World.Hostile(world, o, p) then
          facing[o] += strength[p]
          fleetsFight = true
        end
      end
      if engaged(o) then
        facing[o] += defence
        facingDefence += strength[o]
      end
    end

    local any = facingDefence > 0 or fleetsFight
    if not any then
      s.fighting = 0
      continue
    end
    if fleetsFight and s.fighting == 0 then
      s.fighting = world.tick
      World.Count(world, "battles")
    end

    -- Losses, all worked out before any is applied.
    local spread = Powers.COMBAT_SPREAD
    local losses: { number } = table.create(factionCount, 0)
    for _, o in present do
      if facing[o] > 0 then
        local rng = Rng.For(world.history, world.tick, system, o)
        losses[o] = Powers.ROUND_LOSS * facing[o] * Rng.Float(rng, 1 - spread, 1 + spread)
      end
    end
    if facingDefence > 0 and full > 0 then
      local rng = Rng.For(world.history, world.tick, system, 0)
      local lost = Powers.ROUND_LOSS * facingDefence * Rng.Float(rng, 1 - spread, 1 + spread)
      s.defence = math.max(0, (defence - lost) / full)
    end
    for _, o in present do
      if losses[o] > 0 then
        local share = math.min(1, losses[o] / strength[o])
        local rng = Rng.For(world.history, world.tick, system, o, 1)
        local lost = 0
        for _, id in table.clone(s.fleets) do
          local fleet = world.fleets[id]
          if fleet.owner == o then
            lost += lose(rng, fleet, share)
            if World.Ships(fleet) == 0 then
              World.Disband(world, fleet)
            end
          end
        end
        World.Count(world, "strength lost", lost)
        -- Put down to each war it was lost in, by how much of what it
        -- faced was that enemy's.
        for _, war in world.wars do
          local enemy = if war.a == o then war.b elseif war.b == o then war.a else 0
          if enemy > 0 then
            local theirs = strength[enemy] + (if enemy == holder and engaged(o) then defence else 0)
            if theirs > 0 then
              local part = lost * theirs / facing[o]
              if war.a == o then
                war.lostA += part
              else
                war.lostB += part
              end
            end
          end
        end
      end
    end

    -- Who pulls out: a side now under half of what it faces. The holder
    -- counts its defences as its own, and never leaves its capital.
    local after: { number } = table.create(factionCount, 0)
    for _, id in s.fleets do
      local fleet = world.fleets[id]
      after[fleet.owner] += World.Strength(fleet)
    end
    local left = World.Defence(world, system)
    for _, o in present do
      if after[o] > 0 then
        local own, against = after[o], 0
        for _, p in present do
          if p ~= o and World.Hostile(world, o, p) then
            against += after[p]
          end
        end
        if o == holder and against > 0 then
          own += left
        elseif engaged(o) then
          against += left
        end
        local stands = o == holder and holder > 0 and world.factions[o].capital == system
        if against > 0 and own < Powers.RETREAT_BELOW * against and not stands then
          local gone = false
          for _, id in table.clone(s.fleets) do
            local fleet = world.fleets[id]
            if fleet and fleet.owner == o and fleet.action == 0 then
              gone = Orders.Retreat(world, fleet) or gone
            end
          end
          if gone then
            World.Count(world, "retreats")
            if after[o] + against >= 40 then
              World.Log(world, "battle", `{World.Name(world, o)} is driven from {World.SystemName(world, system)}`,
                system, o)
            end
          end
        end
      end
    end
  end
end

return Battle
