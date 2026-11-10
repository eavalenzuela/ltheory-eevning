--!strict
-- The pirates as an organisation: its money, its dens, and the bands it
-- sends out.
--
-- Day to day, piracy is the pressure field in Strategic/Order: it takes
-- a share of what crosses every lane, and what it takes is sold here
-- (at well under its price) for the pirates' only income. That money
-- keeps a band of frigates at each den and builds new dens in the empty
-- systems beyond the powers' reach. A band that is strong enough raids a
-- poorly defended system nearby: it fights the defences down, carries
-- off a share of the valuables, and goes home.
--
-- The powers answer with policing and garrisons (which push the
-- pressure down), with fleets sent to relieve a raided system, and by
-- destroying dens (Strategic/Mind).

local Battle = require("@lt/Core/Strategic/Battle")
local Orders = require("@lt/Core/Strategic/Orders")
local Powers = require("@lt/Core/Data/Powers")
local Routes = require("@lt/Core/Strategic/Routes")
local World = require("@lt/Core/Strategic/World")

local Raiders = {}

local function dens(world: World.World): { number }
  local list: { number } = {}
  for id, s in world.systems do
    if s.den then
      table.insert(list, id)
    end
  end
  return list
end

local function nearest(world: World.World, from: number, places: { number }): number
  local routes = Routes.For(world.galaxy)
  local best, bestHops = 0, math.huge
  for _, place in places do
    local hops = routes.hops[from][place]
    if hops < bestHops then
      best, bestHops = place, hops
    end
  end
  return best
end

-- Jumps from a system to the nearest one any power owns.
local function remoteness(world: World.World, system: number): number
  local routes = Routes.For(world.galaxy)
  local least = math.huge
  for id, s in world.systems do
    if s.owner > 0 then
      least = math.min(least, routes.hops[system][id])
    end
  end
  return least
end

-- A fleet sent to found a den has arrived: pay for it and hold the site
-- while it is built.
function Raiders.Found(world: World.World, fleet: World.Fleet)
  local s = world.systems[fleet.system]
  local pirates = world.factions[world.pirates]
  if s.owner ~= 0 or s.den or pirates.credits < Powers.DEN_COST then
    fleet.task = "home"
    return
  end
  World.Pay(world, pirates.id, 0, Powers.DEN_COST, "den")
  local action = World.NewAction(world, pirates.id, "den", world.tick + Powers.DEN_TICKS)
  action.fleet, action.system, action.paid = fleet.id, fleet.system, Powers.DEN_COST
  fleet.task = "build"
end

-- The den's timer has run out: it stands if its escort still holds the
-- site.
function Raiders.Founded(world: World.World, action: World.Action)
  local fleet = world.fleets[action.fleet]
  local s = world.systems[action.system]
  World.EndAction(world, action)
  if fleet and fleet.system == action.system and s.owner == 0 and not s.den then
    s.den = true
    fleet.task = ""
    World.Count(world, "dens built")
    World.Log(world, "den", `Pirates have built a den at {World.SystemName(world, action.system)}`, action.system,
      world.pirates)
  elseif fleet then
    fleet.task = "home"
  end
end

function Raiders.Step(world: World.World)
  local pirates = world.factions[world.pirates]
  local routes = Routes.For(world.galaxy)
  local econ = world.econ

  -- The organisation's cut of what was taken on the lanes since the last
  -- period. (A raid's loot is paid for when it is taken: Battle.)
  local taken = 0
  for g, class in econ.classes do
    taken += econ.lost[g] * class.par
  end
  World.Pay(world, 0, pirates.id, Powers.TITHE * (taken - world.loot), "piracy on the lanes")
  world.loot = taken
  -- A hoard past any use is squandered.
  World.Pay(world, pirates.id, 0, Powers.SQUANDER * (pirates.credits - Powers.HOARD), "squandered")

  local homes = dens(world)
  -- The richer the pirates, the larger the bands they keep.
  local bandSize = math.min(Powers.BAND_MOST, Powers.BAND + pirates.credits // Powers.BAND_WEALTH)

  -- No den left: the pirates regroup wherever lawlessness is deepest.
  if #homes == 0 then
    if pirates.credits >= Powers.DEN_COST then
      local best, bestPressure = 0, -1
      for id, s in world.systems do
        if s.owner == 0 and s.pressure > bestPressure and remoteness(world, id) >= 2 then
          best, bestPressure = id, s.pressure
        end
      end
      if best > 0 then
        World.Pay(world, pirates.id, 0, Powers.DEN_COST, "den")
        world.systems[best].den = true
        World.Count(world, "dens built")
        World.Log(world, "den", `Pirates regroup at {World.SystemName(world, best)}`, best, pirates.id)
      end
    end
    return
  end

  -- What each den has at home, and its idle band.
  local founding = false
  local ships = 0
  for _, id in world.actionIds do
    if world.actions[id].kind == "den" then
      founding = true
    end
  end
  for _, id in World.FleetIds(world) do
    local fleet = world.fleets[id]
    if fleet and fleet.owner == pirates.id then
      ships += World.Ships(fleet)
      if fleet.task == "found" or fleet.task == "build" then
        founding = true
      end
      -- Anyone at a loose end goes back to the nearest den.
      if fleet.system > 0 and fleet.action == 0 and (fleet.task == "" or fleet.task == "home")
        and not world.systems[fleet.system].den then
        Orders.Move(world, fleet, nearest(world, fleet.system, homes), "home")
      elseif fleet.system > 0 and fleet.action == 0 and fleet.task == "raid" and world.systems[fleet.system].siege == nil then
        -- (a raid that never started, or was beaten off)
        fleet.task = "home"
      end
    end
  end

  for _, den in homes do
    -- The band at home: every idle pirate fleet there, as one.
    local band: World.Fleet? = nil
    for _, id in table.clone(world.systems[den].fleets) do
      local fleet = world.fleets[id]
      if fleet.owner == pirates.id and fleet.action == 0 and (fleet.task == "" or fleet.task == "home") then
        fleet.task = ""
        if band then
          World.Merge(world, band, fleet)
        else
          band = fleet
        end
      end
    end
    -- Recruit, a frigate a period, while there is money.
    if pirates.credits >= Powers.PIRATE_FRIGATE and (band == nil or band.ships[1] < bandSize)
      and ships < bandSize * #homes then
      ships += 1
      World.Pay(world, pirates.id, 0, Powers.PIRATE_FRIGATE, "recruits")
      if band then
        band.ships[1] += 1
      else
        local one: { number } = table.create(#Powers.ships, 0)
        one[1] = 1
        band = World.NewFleet(world, pirates.id, den, one)
      end
    end
    if band == nil then
      continue
    end
    local strength = World.Strength(band)

    -- Found a new den: an empty system nobody owns, far from the powers
    -- and from other dens.
    if not founding and #homes < Powers.DENS_MOST and band.ships[1] >= 10
      and pirates.credits >= Powers.DEN_COST + 4 * Powers.PIRATE_FRIGATE then
      local site, siteScore = 0, 0
      for id, s in world.systems do
        if s.owner == 0 and not s.den and routes.hops[den][id] <= 8 and #s.fleets == 0 then
          local spaced = true
          for _, other in homes do
            if routes.hops[id][other] < Powers.DEN_SPACING then
              spaced = false
            end
          end
          local remote = if spaced then remoteness(world, id) else 0
          if remote >= 2 and remote > siteScore then
            site, siteScore = id, remote
          end
        end
      end
      if site > 0 then
        local escort: { number } = table.create(#Powers.ships, 0)
        escort[1] = 6
        Orders.Move(world, World.Split(world, band, escort), site, "found")
        founding = true
        continue
      end
    end

    -- Raid: the richest system in reach whose defenders the band
    -- clearly outmatches, and which has not just been raided.
    if strength >= 8 and world.tick - band.since >= Powers.RAID_EVERY then
      local best, bestScore = 0, 0
      for id, s in world.systems do
        local hops = routes.hops[den][id]
        if hops >= 1 and hops <= Powers.RAID_RANGE and not s.den and s.siege == nil
          and (s.raided == 0 or world.tick - s.raided > Powers.RAID_SPARED) then
          local guard = World.Defence(world, id) * (1 - Powers.RAID_BEATEN)
          for _, fid in s.fleets do
            if world.fleets[fid].owner ~= pirates.id then
              guard += World.Strength(world.fleets[fid])
            end
          end
          if guard < 0.5 * strength then
            local score = world.atlas.systems[id].population / (hops + 1)
            if score > bestScore then
              best, bestScore = id, score
            end
          end
        end
      end
      if best > 0 then
        Orders.Move(world, band, best, "raid")
      else
        band.since = world.tick
      end
    end
  end
end

-- A band has reached the system it set out to raid.
function Raiders.Arrived(world: World.World, fleet: World.Fleet)
  if not Battle.Besiege(world, fleet, "raid") then
    fleet.task = "home"
  end
end

return Raiders
