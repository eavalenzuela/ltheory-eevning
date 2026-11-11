--!strict
-- Drones: small ships a pilot launches to fight beside their own.
--
-- A drone is an item in the hold until it is launched, and then a ship
-- of its own (a hull of class "drone", Data/Ships) that belongs to the
-- ship that launched it and flies with the orders anybody's ship does.
-- A hull can control so many at once, and a pilot one for each level of
-- the Drones skill, whichever is fewer.
--
-- Out of the hold a drone does one of three things. Told to engage, it
-- orbits what its owner pointed it at and fires on it. With nothing
-- pointed out, it goes for whatever is attacking its owner. Otherwise
-- it keeps station on its owner. Recalled, it comes back and is taken
-- aboard, an item again. When its owner docks or warps, a drone near
-- enough is taken aboard and one that is not is lost.
--
-- What a drone destroys is its owner's doing (the bounty, and the
-- blame). A drone can be shot: some of the pirates on a grid go for the
-- drones rather than the ships (Tactical/Pirates), and one that is
-- destroyed leaves nothing behind.
--
-- (EVE's, cut down. Not yet: a drone bay apart from the hold, drones
-- that mine, repair or jam, bandwidth.)

local Combat = require("@lt/Core/Tactical/Combat")
local Kinds = require("@lt/Core/Data/Drones")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")

local Drones = {}

export type Event = { [string]: any }

-- How near its owner a drone has to be to be taken aboard when the
-- owner docks or warps, m. Farther off, it is lost.
Drones.SCOOP = 2500
-- How far off a drone orbits what it is fighting, and its owner.
local FIGHT, STATION = 800, 600

-- How many drones a ship can have out at once: what its hull controls,
-- or the pilot's Drones skill if that is less (a ship that is not the
-- pilot's is held only by its hull).
function Drones.Max(state: State.State, ship: number): number
  local record = state.ships[ship]
  local hull = if record then Ships.byId[record.type] else nil
  if record == nil or hull == nil then
    return 0
  end
  local levels = Items.Levels(state, ship)
  return math.min(hull.drones or 0, if levels then math.max(0, levels.drones or 0) else hull.drones or 0)
end

-- The drones a ship has out, in the order they were launched.
function Drones.Out(state: State.State, ship: number): { State.Drone }
  local found: { State.Drone } = {}
  for _, id in state.droneIds do
    if state.drones[id].owner == ship then
      table.insert(found, state.drones[id])
    end
  end
  return found
end

-- The drones in a ship's hold, as stacks.
local function carried(state: State.State, ship: number): { State.Item }
  local found: { State.Item } = {}
  for _, item in Items.In(state, ship, "cargo") do
    if Kinds.byId[item.type] then
      table.insert(found, item)
    end
  end
  return found
end

-- Take a drone out of the game: its ball, what it carries, every record.
local function remove(state: State.State, id: number, reason: string, events: { Event })
  local ball = state.balls[id]
  if ball then
    Space.RemoveBall(state, ball)
    table.insert(events, { kind = "BallRemoved", ball = id, reason = reason })
  end
  for _, item in Items.In(state, id, nil) do
    Items.Take(state, item, item.quantity)
  end
  if state.ships[id] then
    state.ships[id] = nil
    State.RemoveId(state.shipIds, id)
  end
  state.drones[id] = nil
  State.RemoveId(state.droneIds, id)
end

-- Take a drone back aboard its owner: it is an item in the hold again.
local function scoop(state: State.State, drone: State.Drone, events: { Event })
  Items.Add(state, drone.type, 1, drone.owner, "cargo")
  remove(state, drone.ship, "scooped", events)
  table.insert(events, { kind = "DroneScooped", owner = drone.owner, type = drone.type })
end

local function give(state: State.State, command: State.Command, events: { Event }): boolean
  local combat = command.kind == "LockTarget" or command.kind == "ActivateModule"
  if combat then
    if Combat.Validate(state, command) then
      Combat.Apply(state, command, events)
      return true
    end
  elseif Space.Validate(state, command) then
    Space.Apply(state, command, events)
    return true
  end
  return false
end

function Drones.Validate(state: State.State, command: State.Command): (boolean, string?)
  local ship = state.ships[command.actor]
  local ball = state.balls[command.actor]
  if ship == nil then
    return false, "no such ship"
  elseif ball == nil then
    return false, "docked"
  elseif ball.warp and ball.warp.stage == "warp" then
    return false, "in warp"
  end
  local out = Drones.Out(state, ship.id)
  local kind = command.kind
  if kind == "LaunchDrones" then
    if #carried(state, ship.id) == 0 then
      return false, "no drones in the hold"
    elseif (Ships.byId[ship.type].drones or 0) == 0 then
      return false, "this hull controls no drones"
    elseif #out >= Drones.Max(state, ship.id) then
      return false, if Drones.Max(state, ship.id) == 0 then "needs Drones 1" else "as many drones are out as can be controlled"
    end
    return true
  elseif kind == "RecallDrones" then
    return #out > 0, if #out > 0 then nil else "no drones are out"
  elseif kind == "EngageDrones" then
    if #out == 0 then
      return false, "no drones are out"
    end
    local target = state.balls[command.target or 0]
    if target == nil or target.id == ball.id or state.drones[target.id] then
      return false, "no such target"
    elseif target.system ~= ball.system or target.grid ~= ball.grid then
      return false, "target is not on grid"
    end
    return true
  end
  return false, `unknown command '{kind}'`
end

function Drones.Apply(state: State.State, command: State.Command, events: { Event })
  local ship = state.ships[command.actor]
  local ball = state.balls[command.actor]
  local kind = command.kind
  if kind == "LaunchDrones" then
    -- As many as there is room to control, from the stacks in the hold.
    local room = Drones.Max(state, ship.id) - #Drones.Out(state, ship.id)
    for _, stack in carried(state, ship.id) do
      while room > 0 and state.items[stack.id] do
        local type = Kinds.byId[stack.type]
        Items.Take(state, stack, 1)
        local drone = Space.NewShip(state, type.hull, type.name, ship.owner, 0)
        Items.Equip(state, drone.id, type.gun, type.charge)
        Items.Add(state, type.charge, 4000, drone.id, "cargo")
        local n = #state.droneIds
        local launched = Space.Launch(state, drone, ball.system, ball.x + 150 * math.cos(n * 2.4), ball.y + 60,
          ball.z + 150 * math.sin(n * 2.4))
        state.drones[drone.id] = { ship = drone.id, owner = ship.id, type = type.id, target = 0, returning = false, near = true }
        table.insert(state.droneIds, drone.id)
        table.insert(events, { kind = "BallAdded", ball = launched.id })
        table.insert(events, { kind = "DroneLaunched", owner = ship.id, drone = drone.id })
        room -= 1
      end
    end
  elseif kind == "RecallDrones" then
    for _, drone in Drones.Out(state, ship.id) do
      drone.returning = true
      drone.target = 0
    end
  elseif kind == "EngageDrones" then
    for _, drone in Drones.Out(state, ship.id) do
      drone.returning = false
      drone.target = command.target :: number
    end
  end
end

-- Once a tick: every drone does what it is for.
function Drones.Step(state: State.State, events: { Event })
  for _, id in table.clone(state.droneIds) do
    local drone = state.drones[id]
    local ball = state.balls[id]
    local owner = state.balls[drone.owner]
    if ball == nil or state.ships[id] == nil then
      -- (destroyed: whoever did it has seen to the rest)
      state.drones[id] = nil
      State.RemoveId(state.droneIds, id)
      table.insert(events, { kind = "DroneLost", owner = drone.owner, type = drone.type, destroyed = true })
    elseif owner == nil or state.ships[drone.owner] == nil or (owner.warp and owner.warp.stage == "warp") or owner.system ~= ball.system then
      -- Its owner has docked, warped or gone: aboard if it was near, lost if not.
      if drone.near and state.ships[drone.owner] then
        scoop(state, drone, events)
      else
        remove(state, id, "lost", events)
        table.insert(events, { kind = "DroneLost", owner = drone.owner, type = drone.type })
      end
    else
      local gap = Space.Gap(ball :: any, owner :: any)
      drone.near = gap <= Drones.SCOOP
      if drone.returning then
        if gap < 300 then
          scoop(state, drone, events)
        elseif not (ball.mode == "approach" and ball.target == owner.id) then
          ball.vitals.locks, ball.vitals.running = {}, {}
          give(state, { kind = "Approach", actor = id, target = owner.id, range = 0 }, events)
        end
      else
        local prey = state.balls[drone.target]
        if prey == nil or prey.system ~= ball.system or prey.grid ~= ball.grid then
          drone.target = Pirates.Hunting(state, owner)
          prey = state.balls[drone.target]
        end
        if prey == nil then
          if #ball.vitals.locks > 0 then
            ball.vitals.locks, ball.vitals.running = {}, {}
          end
          if not (ball.mode == "orbit" and ball.target == owner.id) then
            give(state, { kind = "Orbit", actor = id, target = owner.id, range = STATION }, events)
          end
        else
          if not (ball.mode == "orbit" and ball.target == prey.id) then
            give(state, { kind = "Orbit", actor = id, target = prey.id, range = FIGHT }, events)
          end
          local locked, targeted = false, false
          for _, lock in ball.vitals.locks do
            if lock.target == prey.id then
              targeted, locked = true, lock.locked
            end
          end
          if not targeted then
            give(state, { kind = "LockTarget", actor = id, target = prey.id }, events)
          elseif locked then
            for _, item in Items.Fitted(state, id) do
              if Modules.byId[item.type].weapon then
                give(state, { kind = "ActivateModule", actor = id, item = item.id, target = prey.id }, events)
              end
            end
          end
        end
      end
    end
  end
end

return Drones
