--!strict
-- Drones: small ships a pilot launches to work beside their own.
--
-- A drone is an item in its ship's drone bay until it is launched, and
-- then a ship of its own (a hull of class "drone", Data/Ships) that
-- belongs to the ship that launched it and flies with the orders
-- anybody's ship does. A hull can control so many at once, and a pilot
-- one for each level of the Drones skill, whichever is fewer; the bay
-- holds those and some spare. Drones go into the bay at a station.
--
-- What a drone does out of the bay follows from what it is for
-- (Data/Drones):
--   - a combat drone orbits what its owner pointed it at and fires on
--     it; with nothing pointed out, it goes for whatever is attacking
--     its owner's side; otherwise it keeps station on its owner;
--   - a mining drone cuts the rock it was pointed at, or the rock its
--     owner is cutting, and when its little hold is full flies back,
--     puts the ore in its owner's hold, and goes out again;
--   - a repair drone goes to whoever of its owner's side has lost most
--     of their armour and mends it, and otherwise keeps station.
-- Recalled, a drone comes back and is taken aboard, an item in the bay
-- again. When its owner docks or warps, a drone near enough is taken
-- aboard and one that is not is lost.
--
-- What a drone destroys is its owner's doing (the bounty, and the
-- blame). A drone can be shot: some of the pirates on a grid go for the
-- drones rather than the ships (Tactical/Pirates), and one that is
-- destroyed leaves nothing behind.
--
-- A hired pilot's ship has its own, and its pilot sees to them
-- (Tactical/Fleet): everything here goes by the ship that launched a
-- drone, whoever flies it.
--
-- (Cut down to this. Not yet: bandwidth, drones that jam.)

local Combat = require("@lt/Core/Tactical/Combat")
local Kinds = require("@lt/Core/Data/Drones")
local Items = require("@lt/Core/Assets/Items")
local Mend = require("@lt/Core/Tactical/Mend")
local Mining = require("@lt/Core/Tactical/Mining")
local Modules = require("@lt/Core/Data/Modules")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")
local Types = require("@lt/Core/Data/Types")

local Drones = {}

export type Event = { [string]: any }

-- How near its owner a drone has to be to be taken aboard when the
-- owner docks or warps, m. Farther off, it is lost.
Drones.SCOOP = 2500
-- How far off a drone orbits what it is fighting, and its owner.
local FIGHT, STATION = 800, 600

-- How many more a pilot has in hand for each level of the Fighters
-- skill, on a hull with a bay for them.
Drones.WING = 4

-- How many drones a ship can have out at once: what its hull controls,
-- or the pilot's Drones skill if that is less (a ship that is not the
-- pilot's is held only by its hull). On a hull with a bay for fighters
-- each level of the Fighters skill is four more in hand, fighters,
-- bombers or drones: a carrier controls more than Drones alone allows.
function Drones.Max(state: State.State, ship: number): number
  local record = state.ships[ship]
  local hull = if record then Ships.byId[record.type] else nil
  if record == nil or hull == nil then
    return 0
  end
  local levels = Items.Levels(state, ship)
  if levels == nil then
    return hull.drones or 0
  end
  local hand = math.max(0, levels.drones or 0)
  if Ships.CRAFT[hull.class] then
    hand += Drones.WING * math.max(0, levels.fighters or 0)
  end
  return math.min(hull.drones or 0, hand)
end

-- Why a ship cannot launch one of a kind, if it cannot: its hull has no
-- bay for it, or whoever flies it has not the skill.
function Drones.Cannot(state: State.State, ship: number, type: Kinds.DroneType): string?
  local record = state.ships[ship]
  local hull = Ships.byId[record.type]
  local craft = type.craft
  if craft and not (Ships.CRAFT[hull.class] and Ships.CRAFT[hull.class][craft]) then
    return `this hull has no bay for a {string.lower(type.name)}`
  end
  local levels = Items.Levels(state, ship)
  local skill = type.skill or "drones"
  if levels and math.max(0, levels[skill] or 0) < type.level then
    return `needs {if skill == "fighters" then "Fighters" else "Drones"} {type.level} for what is in the bay`
  end
  return nil
end

-- The Drones skill of whoever flies a ship: the pilot's own, or a hired
-- pilot's grade.
function Drones.Skill(state: State.State, ship: number): number
  local levels = Items.Levels(state, ship)
  return if levels then math.max(0, levels.drones or 0) else 5
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

-- The drones in a ship's drone bay, as stacks.
local function carried(state: State.State, ship: number): { State.Item }
  local found: { State.Item } = {}
  for _, item in Items.In(state, ship, "dronebay") do
    if Kinds.byId[item.type] then
      table.insert(found, item)
    end
  end
  return found
end

-- Put what a drone has in its hold into its owner's, as much as fits.
-- Returns the units moved.
-- (Ore goes into its owner's ore hold first, where the owner has one.)
local function unload(state: State.State, drone: State.Drone): number
  local moved = 0
  for _, item in Items.In(state, drone.ship, "cargo") do
    local free = Items.ShipStats(state, drone.owner).cargo - Items.CargoUsed(state, drone.owner)
    local type = item.type
    local fits: number
    if Items.IsOre(type) then
      -- (taken out of the drone only as it is known to fit: what does
      -- not stays aboard the drone)
      local volume = Types.Info(type).volume
      local size, used = Items.OreHold(state, drone.owner)
      fits = math.min(item.quantity, math.floor((free + 1e-9) / volume) + math.floor((size - used + 1e-9) / volume))
      if fits > 0 then
        Items.Take(state, item, fits)
        Items.StowOre(state, drone.owner, type, fits, free)
      end
    else
      fits = math.min(item.quantity, math.floor((free + 1e-9) / Types.Info(type).volume))
      if fits > 0 then
        Items.Take(state, item, fits)
        Items.Add(state, type, fits, drone.owner, "cargo")
      end
    end
    moved += fits
  end
  return moved
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
  -- (and what a mining drone was carrying comes aboard with it, if it fits)
  if Kinds.byId[drone.type].role == "mining" then
    unload(state, drone)
  end
  Items.Add(state, drone.type, 1, drone.owner, "dronebay")
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
      return false, "no drones in the drone bay"
    elseif (Ships.byId[ship.type].drones or 0) == 0 then
      return false, "this hull controls no drones"
    elseif #out >= Drones.Max(state, ship.id) then
      return false, if Drones.Max(state, ship.id) == 0 then "needs Drones 1" else "as many drones are out as can be controlled"
    end
    -- (a tech 2 drone takes more of the skill than a plain one, and a
    -- fighter or a bomber a bay for it and a skill of its own: something
    -- in the bay has to be what this ship and its pilot can launch)
    local why: string? = nil
    for _, stack in carried(state, ship.id) do
      local cannot = Drones.Cannot(state, ship.id, Kinds.byId[stack.type])
      if cannot == nil then
        return true
      end
      why = why or cannot
    end
    return false, why
  elseif kind == "RecallDrones" then
    return #out > 0, if #out > 0 then nil else "no drones are out"
  elseif kind == "EngageDrones" then
    if #out == 0 then
      return false, "no drones are out"
    end
    -- (a rock, for the mining drones to cut)
    local rock = Space.Object(state, command.target or 0)
    if rock and Mining.Rock(rock) then
      if Space.SystemOf(state, rock.id) ~= ball.system or rock.site ~= ball.grid then
        return false, "target is not on grid"
      end
      return true
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
      -- (what the pilot has not the skill for, or the hull the bay for,
      -- stays where it is)
      while room > 0 and state.items[stack.id] and Drones.Cannot(state, ship.id, Kinds.byId[stack.type]) == nil do
        local type = Kinds.byId[stack.type]
        Items.Take(state, stack, 1)
        local drone = Space.NewShip(state, type.hull, type.name, ship.owner, 0)
        Items.Equip(state, drone.id, type.gun, if type.charge ~= "" then type.charge else nil)
        if type.charge ~= "" then
          Items.Add(state, type.charge, 4000, drone.id, "cargo")
        end
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
    -- (a rock is for the mining drones, and a ship for those that fight:
    -- the others carry on as they were)
    local rock = Space.Object(state, command.target :: number) ~= nil
    for _, drone in Drones.Out(state, ship.id) do
      local role = Kinds.byId[drone.type].role
      if (rock and role == "mining") or (not rock and role == "combat") then
        drone.returning = false
        drone.target = command.target :: number
      end
    end
  end
end

-- The rock a ship is cutting, or has locked: what its mining drones go
-- for when no rock has been pointed out to them.
local function working(state: State.State, owner: State.Ball): System.Object?
  for _, running in owner.vitals.running do
    local item = state.items[running.item]
    local rock = if item and Modules.byId[item.type].miner then Space.Object(state, running.target) else nil
    -- (a cloud is nothing to a drone: it cuts rock)
    if rock and Mining.Rock(rock) and Mining.Left(state, rock) > 0 then
      return rock
    end
  end
  for _, lock in owner.vitals.locks do
    local rock = Space.Object(state, lock.target)
    if rock and Mining.Rock(rock) and Mining.Left(state, rock) > 0 then
      return rock
    end
  end
  return nil
end

-- The ships of a drone's owner's side: for a repair drone to look over.
local function side(state: State.State): { number }
  local ids: { number } = { state.player.ship }
  for _, id in state.fleetIds do
    table.insert(ids, state.fleet[id].ship)
  end
  for _, id in state.droneIds do
    table.insert(ids, id)
  end
  return ids
end

-- Keep station on the owner, with nothing locked.
local function station(state: State.State, ball: State.Ball, owner: State.Ball, events: { Event })
  if #ball.vitals.locks > 0 then
    ball.vitals.locks, ball.vitals.running = {}, {}
  end
  if not (ball.mode == "orbit" and ball.target == owner.id) then
    give(state, { kind = "Orbit", actor = ball.id, target = owner.id, range = 600 }, events)
  end
end

-- A mining drone's tick: out to the rock and cutting, or back with a
-- full hold.
local function mine(state: State.State, drone: State.Drone, ball: State.Ball, owner: State.Ball, events: { Event })
  local rock = Space.Object(state, drone.target)
  if rock == nil or not Mining.Rock(rock) or rock.site ~= owner.grid or Mining.Left(state, rock) <= 0 then
    rock = working(state, owner)
    drone.target = if rock then rock.id else 0
  end
  local capacity = Items.ShipStats(state, ball.id).cargo
  local used = Items.CargoUsed(state, ball.id)
  if used > 0 and (used >= 0.7 * capacity or rock == nil) then
    -- Back with it. (If the owner's hold is full it waits beside them.)
    ball.vitals.locks, ball.vitals.running = {}, {}
    if Space.Gap(ball :: any, owner :: any) < 400 then
      local moved = unload(state, drone)
      if moved > 0 then
        table.insert(events, { kind = "DroneDelivered", owner = owner.id, drone = ball.id, units = moved })
      end
    elseif not (ball.mode == "approach" and ball.target == owner.id) then
      give(state, { kind = "Approach", actor = ball.id, target = owner.id, range = 0 }, events)
    end
    return
  elseif rock == nil then
    station(state, ball, owner, events)
    return
  end
  if not (ball.mode == "orbit" and ball.target == rock.id) then
    ball.vitals.locks, ball.vitals.running = {}, {}
    give(state, { kind = "Orbit", actor = ball.id, target = rock.id, range = 500 }, events)
  end
  local locked, targeted = false, false
  for _, lock in ball.vitals.locks do
    if lock.target == rock.id then
      targeted, locked = true, lock.locked
    end
  end
  if not targeted then
    give(state, { kind = "LockTarget", actor = ball.id, target = rock.id }, events)
  elseif locked then
    for _, item in Items.Fitted(state, ball.id) do
      give(state, { kind = "ActivateModule", actor = ball.id, item = item.id, target = rock.id }, events)
    end
  end
end

-- A repair drone's tick: to whoever of its side has lost most armour,
-- and mending.
local function repair(state: State.State, ball: State.Ball, owner: State.Ball, events: { Event })
  local friends = side(state)
  local worst = Mend.Hurt(state, ball, friends, "armor", math.huge)
  if worst == nil then
    Mend.Tend(state, ball, friends, events)
    if #ball.vitals.running == 0 then
      station(state, ball, owner, events)
    end
    return
  end
  if not (ball.mode == "orbit" and ball.target == worst.id) then
    give(state, { kind = "Orbit", actor = ball.id, target = worst.id, range = 700 }, events)
  end
  Mend.Tend(state, ball, friends, events)
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
      elseif Kinds.byId[drone.type].role == "mining" then
        mine(state, drone, ball, owner, events)
      elseif Kinds.byId[drone.type].role == "repair" then
        repair(state, ball, owner, events)
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
