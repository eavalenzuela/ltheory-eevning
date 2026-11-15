--!strict
-- What follows a fight: wrecks and what survives in them, bounties,
-- insurance, the pilot's escape pod, looting and repairs.
--
-- When a ship dies it leaves a wreck where it was. Each stack aboard,
-- fitted or in the hold, has an even chance of surviving into the wreck.
-- A pirate's wreck also holds its tag. Killing a pirate pays its bounty.
--
-- When the player's ship dies the hull's insurance pays out and the pilot
-- is left in a capsule, which can fly and warp but not fight. Docked in a
-- capsule, the pilot is given a starter ship. If the capsule is destroyed
-- too, the pilot wakes at home in one.

local Assault = require("@lt/Core/Tactical/Assault")
local Battles = require("@lt/Core/Tactical/Battles")
local Keeps = require("@lt/Core/Tactical/Keeps")
local Raids = require("@lt/Core/Tactical/Raids")
local Constants = require("@lt/Core/Data/Constants")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local Sites = require("@lt/Core/Tactical/Sites")
local Skills = require("@lt/Core/Data/Skills")
local Space = require("@lt/Core/Tactical/Space")
local Standings = require("@lt/Core/Assets/Standings")
local State = require("@lt/Core/Kernel/State")
local Stations = require("@lt/Core/Assets/Stations")
local Surges = require("@lt/Core/Tactical/Surges")
local Types = require("@lt/Core/Data/Types")
local Corporation = require("@lt/Core/Assets/Corporation")
local Wallet = require("@lt/Core/Assets/Wallet")

local Aftermath = {}

export type Event = { [string]: any }

local WRECK_LIFETIME = 7200  -- ticks: two hours
local LOOT_RANGE = 2500
local DROP_CHANCE = 0.5
-- The chance that what survives of a pirate's fitted module is the
-- custom make of it (Data/Modules), where there is one.
local CUSTOM_CHANCE = 0.2
Aftermath.CUSTOM_CHANCE = CUSTOM_CHANCE
-- And how often a module of a pirate's that was a better make to begin
-- with (a veteran's custom fittings, a captain's masterworks) is found
-- as it was: the rest of the time what is left of it is the plain one.
local KEPT_CHANCE = 0.4
Aftermath.KEPT_CHANCE = KEPT_CHANCE
-- The share of a bounty the pilot is paid for a pirate their hired
-- pilots destroyed with the pilot somewhere else: the rest is theirs.
Aftermath.AWAY = 0.5
local INSURANCE = 0.4        -- of the hull's base price, paid without asking
-- What a lost ship's insurance pays. A ship that was given pays as the
-- plain Courier does, whatever it is: enough to begin again with, and
-- not a price for throwing away what cost nothing. (Mine: the people's
-- frigate is worth thirteen Couriers.)
local function cover(ship: State.Ship, hull: Ships.ShipType): number
  local worth = if ship.given then math.min(hull.basePrice, Ships.byId["frigate.courier"].basePrice) else hull.basePrice
  return math.floor(worth * INSURANCE)
end

-- (the hull a pilot with no ship is given: the one a pilot begins in,
-- bare. Data/Ships says which, by whose station it is they wake at.)
-- (If the pilot has not the skill for that people's frigate, the plain
-- Courier, which anybody can fly: a ship that cannot be flown is none.)
local function starter(state: State.State, station: number): (string, string)
  local hull = Ships.byId[Ships.Starter(Stations.People(state, station))]
  if Skills.Missing(Skills.Needs(hull.id), state.skills) then
    hull = Ships.byId["frigate.courier"]
  end
  return hull.id, (string.gsub(hull.name, "^%S+ ", ""))
end

Aftermath.LOOT_RANGE = LOOT_RANGE

local function pay(state: State.State, amount: number, reason: string, events: { Event })
  Wallet.Pay(state, amount, reason, events)
end

local function forget(state: State.State, ship: number)
  for _, item in Items.In(state, ship, nil) do
    Items.Take(state, item, item.quantity)
  end
  state.ships[ship] = nil
  State.RemoveId(state.shipIds, ship)
  if state.pilots[ship] then
    state.pilots[ship] = nil
    State.RemoveId(state.pilotIds, ship)
  end
end

-- A ship has been destroyed by 'by'.
function Aftermath.Destroy(state: State.State, id: number, by: number, events: { Event })
  local ball = state.balls[id]
  local ship = state.ships[id]
  local hull = Ships.byId[ship.type]
  local pilot: State.Pilot? = state.pilots[id]
  table.insert(events, { kind = "BallDestroyed", ball = id, by = by, name = ball.name, system = ball.system,
    x = ball.x, y = ball.y, z = ball.z, radius = ball.radius })

  -- (a capsule leaves nothing, and neither does a drone)
  if hull.class ~= "capsule" and hull.class ~= "drone" then
    local wreck: State.Wreck = {
      id = State.NewId(state), kind = "wreck", name = ball.name .. " Wreck", system = ball.system, grid = ball.grid,
      x = ball.x, y = ball.y, z = ball.z, radius = ball.radius, hull = ship.type, expires = state.tick + WRECK_LIFETIME,
      salvaged = false, locked = false, lock = "",
    }
    state.wrecks[wreck.id] = wreck
    table.insert(state.wreckIds, wreck.id)
    -- What survives. Each stack, and each weapon's load, gets its own roll.
    for _, item in Items.In(state, id, nil) do
      local rng = Rng.For(state.historySeed, state.tick, id, item.id)
      if item.charge ~= "" then
        local weapon = Modules.byId[item.type].weapon :: Modules.Weapon
        local loaded = if weapon.clip == 0 then 1 else item.rounds
        if loaded > 0 and Rng.Chance(rng, DROP_CHANCE) then
          Items.Add(state, item.charge, loaded, wreck.id, "cargo")
        end
      end
      if Rng.Chance(rng, DROP_CHANCE) then
        -- (a pirate's own guns and fittings are now and then better than they look)
        local fitted = item.place == "high" or item.place == "mid" or item.place == "low"
        local made = Modules.byId[item.type]
        local found = item.type
        if ship.owner == "pirates" and fitted and made and made.meta and made.base then
          found = if Rng.Chance(rng, KEPT_CHANCE) then item.type else made.base
        elseif ship.owner == "pirates" and fitted then
          local custom = Modules.Custom(item.type)
          found = if custom and Rng.Chance(rng, CUSTOM_CHANCE) then custom.id else item.type
        end
        Items.Add(state, found, item.quantity, wreck.id, "cargo")
      end
    end
    if ship.owner == "pirates" then
      Items.Add(state, "tag.pirate", if pilot then math.max(1, pilot.tags) else 1, wreck.id, "cargo")
      Items.Add(state, "scrap.metal", 1 + Rng.Int(Rng.For(state.historySeed, state.tick, id, 77), 5), wreck.id, "cargo")
    end
    table.insert(events, { kind = "WreckAdded", wreck = wreck.id, of = id })
  end

  local wasPlayer = id == state.player.ship
  -- (a ship a hired pilot flew, lost in a fight the pilot was not at: in its log)
  local flew = if ship.owner == "player" then state.fleet[ship.pilot] else nil
  if flew then
    Battles.Lost(state, ball.system, ball.grid, flew.name, hull.name)
  end
  -- (a ship of the pilot's that somebody hired was flying is insured as
  -- their own is: Tactical/Fleet sees to the pilot)
  if ship.owner == "player" and ship.pilot ~= 0 then
    pay(state, cover(ship, hull), "insurance", events)
  end
  local velocity = { ball.vx, ball.vy, ball.vz }
  Space.RemoveBall(state, ball)
  forget(state, id)
  -- (one that kept a camp a job is to clear counts toward the job; and
  -- the rig a job was to hold is that job lost)
  if pilot then
    Assault.Fell(state, pilot.home, id, hull.class == "works", events)
    -- (and a tower the pirates held a moon with is that moon free)
    Keeps.Fell(state, id, pilot.home, events)
  else
    Assault.Lost(state, id, events)
    -- (and what stood for a pilot's tower under fire is the tower lost)
    Raids.CoreLost(state, id, events)
  end

  -- (a bounty is on the pilot, not the hull: a scout in a patched frigate
  -- is worth a scout's)
  -- What the factions make of it (Assets/Standings): a ship of theirs, or
  -- anybody's in their space, destroyed by the pilot is held against
  -- them, and a pirate destroyed in their space is to the pilot's credit.
  if by == state.player.ship and ship.owner ~= "player" then
    if ship.owner == "pirates" then
      -- (to whoever keeps order there: the pirates do not thank a pilot
      -- for it in their own space)
      Standings.Change(state, Galaxy.Keeper(state.galaxy.systems[ball.system]), Standings.PIRATE)
    elseif state.traffic[id] then
      Standings.Change(state, Standings.Minds(state, ship.owner, ball.system), Standings.KILLED, events)
    end
  end
  if ship.owner == "pirates" and by == state.player.ship then
    -- (with the pilot somewhere else it was their hired pilots' doing,
    -- and half of the bounty is theirs)
    -- (doubled where pirates are massing, and counted there: Tactical/Surges)
    local full = (if pilot then pilot.bounty else math.floor(hull.basePrice * 0.2)) * Surges.Fell(state, ball.system)
    local mine = state.balls[state.player.ship]
    local there = wasPlayer or (mine ~= nil and mine.system == ball.system and mine.grid == ball.grid)
    if there then
      pay(state, full, "bounty", events)
    else
      -- (which is their corporation's, where they have one)
      Corporation.Earn(state, math.floor(full * Aftermath.AWAY), "bounty", events)
    end
    -- (in the log of the fight, if it is one the pilot was not at when it began)
    Battles.Destroyed(state, ball.system, ball.grid, ship.name, if there then full else math.floor(full * Aftermath.AWAY))
    -- (and it counts toward any bounty job the pilot has for this system)
    for _, id in state.missionIds do
      local mission = state.missions[id]
      -- (a job against the pirates: a strike against a faction's force is counted below)
      if mission.kind == "bounty" and mission.type == "" and mission.system == ball.system and mission.done < mission.need then
        mission.done += 1
      end
    end
  end
  -- A ship of a faction's force at a front (Tactical/Fronts) counts
  -- toward a strike the pilot has taken against that faction there
  -- (Assets/Missions: war work).
  if pilot and pilot.side and by == state.player.ship then
    for _, id in state.missionIds do
      local mission = state.missions[id]
      if mission.kind == "bounty" and mission.type == pilot.side and mission.system == ball.system and mission.done < mission.need then
        mission.done += 1
      end
    end
  end
  if wasPlayer and hull.class ~= "capsule" then
    pay(state, cover(ship, hull), "insurance", events)
    local pod = Space.NewShip(state, "capsule", "Capsule", "player", 0)
    local out = Space.Launch(state, pod, ball.system, ball.x, ball.y, ball.z)
    out.vx, out.vy, out.vz = velocity[1], velocity[2], velocity[3]
    state.player.ship = pod.id
    table.insert(events, { kind = "Ejected", pod = pod.id })
    table.insert(events, { kind = "BallAdded", ball = pod.id })
  elseif wasPlayer then
    -- (the capsule was the pilot: what they had plugged in is gone with it)
    if #state.implants > 0 then
      table.insert(events, { kind = "ImplantsLost", count = #state.implants })
      state.implants = {}
    end
    -- (and whatever boosters were at work on them)
    state.boosters = {}
    local granted, called = starter(state, state.player.home)
    local fresh = Space.NewShip(state, granted, called, "player", state.player.home)
    fresh.given = true
    state.player.ship = fresh.id
    table.insert(events, { kind = "Respawned", ship = fresh.id, station = state.player.home })
  end
end

-- Things that settle by themselves each tick: a pilot docked in a capsule
-- gets a starter ship, and old wrecks fade.
function Aftermath.Step(state: State.State, events: { Event })
  local ship = state.ships[state.player.ship]
  if ship.docked ~= 0 and Ships.byId[ship.type].class == "capsule" then
    local station = ship.docked
    forget(state, ship.id)
    -- If the pilot keeps a ship here that they can fly they are put in
    -- it; otherwise the station gives them a starter.
    local own: State.Ship? = nil
    for _, id in state.shipIds do
      local other = state.ships[id]
      if other.owner == "player" and other.docked == station and other.pilot == 0
        and Skills.Missing(Skills.Needs(other.type), state.skills) == nil then
        own = other
        break
      end
    end
    if own then
      state.player.ship = own.id
      table.insert(events, { kind = "ShipBoarded", ship = own.id, from = ship.id })
    else
      local granted, called = starter(state, station)
      local fresh = Space.NewShip(state, granted, called, "player", station)
      fresh.given = true
      state.player.ship = fresh.id
      table.insert(events, { kind = "ShipGranted", ship = fresh.id, station = station })
    end
  end
  for index = #state.wreckIds, 1, -1 do
    local wreck = state.wrecks[state.wreckIds[index]]
    if wreck.expires <= state.tick then
      Aftermath.RemoveWreck(state, wreck)
      table.insert(events, { kind = "WreckRemoved", wreck = wreck.id })
    end
  end
end

function Aftermath.RemoveWreck(state: State.State, wreck: State.Wreck)
  for _, item in Items.In(state, wreck.id, nil) do
    Items.Take(state, item, item.quantity)
  end
  state.wrecks[wreck.id] = nil
  State.RemoveId(state.wreckIds, wreck.id)
end

-- What repairing a docked ship would cost: a tenth of the hull's price
-- for one wrecked from full, in proportion.
function Aftermath.RepairCost(state: State.State, ship: State.Ship): number
  local stats = Items.ShipStats(state, ship.id)
  local share = (ship.armorDamage + ship.hullDamage) / (stats.armor + stats.hull)
  return math.ceil(Ships.byId[ship.type].basePrice * 0.1 * share)
end

function Aftermath.Validate(state: State.State, command: State.Command): (boolean, string?)
  local ship = state.ships[command.actor]
  if ship == nil then
    return false, "no such ship"
  end
  if command.kind == "Repair" then
    if ship.docked == 0 then
      return false, "not docked"
    elseif ship.armorDamage + ship.hullDamage <= 0 then
      return false, "nothing to repair"
    elseif Aftermath.RepairCost(state, ship) > state.wallet then
      return false, "not enough credits"
    end
    return true
  elseif command.kind == "Loot" then
    local ball = state.balls[ship.id]
    if ball == nil then
      return false, "docked"
    elseif ball.warp and ball.warp.stage == "warp" then
      return false, "in warp"
    end
    local wreck = state.wrecks[command.target or 0]
    if wreck == nil then
      return false, "not a wreck"
    elseif wreck.system ~= ball.system or Space.Gap(ball :: any, wreck :: any) > LOOT_RANGE then
      return false, "too far away"
    elseif wreck.locked then
      return false, "its hold is sealed: it has to be hacked"
    end
    -- (one thing out of it, and so many: as much as there is room for)
    if command.item then
      local item = state.items[command.item]
      if item == nil or item.holder ~= wreck.id then
        return false, "that is not in it"
      end
      local quantity = command.quantity or item.quantity
      if quantity <= 0 or quantity % 1 ~= 0 or quantity > item.quantity then
        return false, "no such quantity"
      end
      local free = Items.ShipStats(state, ship.id).cargo - Items.CargoUsed(state, ship.id)
      if quantity * Types.Info(item.type).volume > free + 1e-9 then
        return false, "not enough room in the hold"
      end
    end
    return true
  elseif command.kind == "Jettison" then
    -- Something out of a hold of the ship's, into space: into a
    -- container, which is put out for it, or ('target') into one that
    -- is there already.
    local ball = state.balls[ship.id]
    local item = state.items[command.item or 0]
    if ball == nil then
      return false, "docked"
    elseif ball.warp and ball.warp.stage == "warp" then
      return false, "in warp"
    elseif item == nil or item.holder ~= ship.id then
      return false, "that item is not aboard"
    elseif item.slot > 0 then
      return false, "unfit it first"
    end
    local quantity = command.quantity or item.quantity
    if quantity <= 0 or quantity % 1 ~= 0 or quantity > item.quantity then
      return false, "no such quantity"
    end
    if command.target and command.target ~= 0 then
      local can = state.wrecks[command.target]
      if can == nil or not can.can then
        return false, "not a container"
      elseif can.system ~= ball.system or Space.Gap(ball :: any, can :: any) > LOOT_RANGE then
        return false, "too far away"
      end
    end
    return true
  end
  return false, `unknown command '{command.kind}'`
end

-- A container of the pilot's in reach of a ship, if there is one: the
-- nearest.
local function canNear(state: State.State, ball: State.Ball): State.Wreck?
  local best: State.Wreck?, least = nil, LOOT_RANGE
  for _, id in state.wreckIds do
    local wreck = state.wrecks[id]
    if wreck.can and wreck.system == ball.system and Space.Gap(ball :: any, wreck :: any) <= least then
      best, least = wreck, Space.Gap(ball :: any, wreck :: any)
    end
  end
  return best
end

function Aftermath.Apply(state: State.State, command: State.Command, events: { Event })
  local ship = state.ships[command.actor]
  if command.kind == "Repair" then
    pay(state, -Aftermath.RepairCost(state, ship), "repairs", events)
    ship.armorDamage, ship.hullDamage = 0, 0
    table.insert(events, { kind = "ShipRepaired", ship = ship.id })
    return
  end
  if command.kind == "Jettison" then
    local ball = state.balls[ship.id]
    local item = state.items[command.item :: number]
    local quantity = command.quantity or item.quantity
    local type = item.type
    local there = if command.target and command.target ~= 0 then state.wrecks[command.target] else canNear(state, ball)
    local can: State.Wreck
    if there then
      can = there
    else
      -- (a little way off the ship, on the side it is not going)
      local made: State.Wreck = {
        id = State.NewId(state), kind = "wreck", name = "Cargo Container", system = ball.system, grid = ball.grid,
        x = ball.x + ball.radius + 60, y = ball.y - 20, z = ball.z + 40, radius = 12, hull = "", expires = state.tick + WRECK_LIFETIME,
        -- (there is nothing of it to salvage, and nothing to hack)
        salvaged = true, locked = false, lock = "", can = true,
      }
      state.wrecks[made.id] = made
      table.insert(state.wreckIds, made.id)
      table.insert(events, { kind = "WreckAdded", wreck = made.id })
      can = made
    end
    Items.Take(state, item, quantity)
    Items.Add(state, type, quantity, can.id, "cargo")
    -- (it lasts from when something was last put in it)
    can.expires = state.tick + WRECK_LIFETIME
    table.insert(events, { kind = "Jettisoned", ship = ship.id, type = type, quantity = quantity, can = can.id })
    return
  end
  -- Loot: take what fits, biggest value first is the pilot's problem; in
  -- the wreck's order here. (Or, with a thing named, that thing and no
  -- other: so many of it.)
  local wreck = state.wrecks[command.target :: number]
  local free = Items.ShipStats(state, ship.id).cargo - Items.CargoUsed(state, ship.id)
  local taken, left = 0, 0
  for _, item in Items.In(state, wreck.id, nil) do
    local volume = Types.Info(item.type).volume
    local fits = math.min(item.quantity, math.floor((free + 1e-9) / volume))
    if command.item then
      fits = if item.id == command.item then math.min(fits, command.quantity or item.quantity) else 0
    end
    if fits > 0 then
      local type = item.type
      left += item.quantity - fits
      Items.Take(state, item, fits)
      Items.Add(state, type, fits, ship.id, "cargo")
      free -= fits * volume
      taken += fits
    else
      left += item.quantity
    end
  end
  table.insert(events, { kind = "Looted", ship = ship.id, wreck = wreck.id, taken = taken, left = left })
  if left == 0 then
    local den = state.sites[wreck.grid]
    Aftermath.RemoveWreck(state, wreck)
    table.insert(events, { kind = "WreckRemoved", wreck = wreck.id })
    -- (a den's stores, emptied, may say where the pack's stronghold is)
    if den and den.system == wreck.system then
      Sites.Lead(state, den, events)
    end
  end
end

-- Unused here, but part of the rules: how long a wreck lasts, in seconds.
Aftermath.WRECK_SECONDS = WRECK_LIFETIME * Constants.TICK

return Aftermath
