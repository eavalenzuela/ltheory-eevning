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

local Constants = require("@lt/Core/Data/Constants")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Types = require("@lt/Core/Data/Types")
local Wallet = require("@lt/Core/Assets/Wallet")

local Aftermath = {}

export type Event = { [string]: any }

local WRECK_LIFETIME = 7200  -- ticks: two hours
local LOOT_RANGE = 2500
local DROP_CHANCE = 0.5
local INSURANCE = 0.4        -- of the hull's base price, paid without asking
local STARTER = "frigate.courier"

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
  table.insert(events, { kind = "BallDestroyed", ball = id, by = by, name = ball.name, system = ball.system,
    x = ball.x, y = ball.y, z = ball.z })

  if hull.class ~= "capsule" then
    local wreck: State.Wreck = {
      id = State.NewId(state), kind = "wreck", name = ball.name .. " Wreck", system = ball.system, grid = ball.grid,
      x = ball.x, y = ball.y, z = ball.z, radius = ball.radius, expires = state.tick + WRECK_LIFETIME,
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
        Items.Add(state, item.type, item.quantity, wreck.id, "cargo")
      end
    end
    if ship.owner == "pirates" then
      Items.Add(state, "tag.pirate", 1, wreck.id, "cargo")
      Items.Add(state, "scrap.metal", 1 + Rng.Int(Rng.For(state.historySeed, state.tick, id, 77), 5), wreck.id, "cargo")
    end
    table.insert(events, { kind = "WreckAdded", wreck = wreck.id, of = id })
  end

  local wasPlayer = id == state.player.ship
  local velocity = { ball.vx, ball.vy, ball.vz }
  Space.RemoveBall(state, ball)
  forget(state, id)

  if ship.owner == "pirates" and by == state.player.ship then
    pay(state, math.floor(hull.basePrice * 0.2), "bounty", events)
  end
  if wasPlayer and hull.class ~= "capsule" then
    pay(state, math.floor(hull.basePrice * INSURANCE), "insurance", events)
    local pod = Space.NewShip(state, "capsule", "Capsule", "player", 0)
    local out = Space.Launch(state, pod, ball.system, ball.x, ball.y, ball.z)
    out.vx, out.vy, out.vz = velocity[1], velocity[2], velocity[3]
    state.player.ship = pod.id
    table.insert(events, { kind = "Ejected", pod = pod.id })
    table.insert(events, { kind = "BallAdded", ball = pod.id })
  elseif wasPlayer then
    local fresh = Space.NewShip(state, STARTER, "Courier", "player", state.player.home)
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
      if other.owner == "player" and other.docked == station
        and Skills.Missing(Skills.Needs(other.type), state.skills) == nil then
        own = other
        break
      end
    end
    if own then
      state.player.ship = own.id
      table.insert(events, { kind = "ShipBoarded", ship = own.id, from = ship.id })
    else
      local fresh = Space.NewShip(state, STARTER, "Courier", "player", station)
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
    end
    return true
  end
  return false, `unknown command '{command.kind}'`
end

function Aftermath.Apply(state: State.State, command: State.Command, events: { Event })
  local ship = state.ships[command.actor]
  if command.kind == "Repair" then
    pay(state, -Aftermath.RepairCost(state, ship), "repairs", events)
    ship.armorDamage, ship.hullDamage = 0, 0
    table.insert(events, { kind = "ShipRepaired", ship = ship.id })
    return
  end
  -- Loot: take what fits, biggest value first is the pilot's problem; in
  -- the wreck's order here.
  local wreck = state.wrecks[command.target :: number]
  local free = Items.ShipStats(state, ship.id).cargo - Items.CargoUsed(state, ship.id)
  local taken, left = 0, 0
  for _, item in Items.In(state, wreck.id, nil) do
    local volume = Types.Info(item.type).volume
    local fits = math.min(item.quantity, math.floor((free + 1e-9) / volume))
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
    Aftermath.RemoveWreck(state, wreck)
    table.insert(events, { kind = "WreckRemoved", wreck = wreck.id })
  end
end

-- Unused here, but part of the rules: how long a wreck lasts, in seconds.
Aftermath.WRECK_SECONDS = WRECK_LIFETIME * Constants.TICK

return Aftermath
