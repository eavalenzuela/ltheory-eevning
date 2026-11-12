--!strict
-- Working a belt: what a ship flown by the game does with the mining
-- lasers it has fitted, once it is at the belt. A hired pilot set to
-- mine does it (Tactical/Fleet), and so do the miners of the traffic
-- (Tactical/Traffic).

local Combat = require("@lt/Core/Tactical/Combat")
local Items = require("@lt/Core/Assets/Items")
local Mining = require("@lt/Core/Tactical/Mining")
local Modules = require("@lt/Core/Data/Modules")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")

local Digger = {}

export type Event = { [string]: any }

local function give(state: State.State, command: State.Command, events: { Event }): boolean
  local kind = command.kind
  if kind == "LockTarget" or kind == "ActivateModule" then
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

-- The mining lasers a ship has fitted.
function Digger.Lasers(state: State.State, ship: number): { State.Item }
  local found: { State.Item } = {}
  if state.ships[ship] then
    for _, item in Items.Fitted(state, ship) do
      -- (a hired pilot cuts rock: what draws gas off a cloud is not one of these)
      local miner = Modules.byId[item.type].miner
      if miner and not miner.gas then
        table.insert(found, item)
      end
    end
  end
  return found
end

-- One tick's work for a ship that is at the belt 'post': to the nearest
-- rock with ore in it, a lock, and every laser on it, rock after rock.
-- Returns false when there is no more to do here: the hold is full, or
-- the belt is mined out ('waits', if nothing has been mined yet: the
-- ship then stays, for the belt to grow back).
function Digger.Work(state: State.State, me: State.Ball, post: System.Object, events: { Event }): boolean
  local lasers = Digger.Lasers(state, me.id)
  if #lasers == 0 then
    return false
  end
  for _, item in lasers do
    for _, running in me.vitals.running do
      if running.item == item.id then
        return true
      end
    end
  end
  -- Nothing is cutting: the hold is full, the rock is gone, or it is time to begin.
  local capacity = Items.ShipStats(state, me.id).cargo
  local used = Items.CargoUsed(state, me.id)
  if capacity - used < math.max(2, 0.03 * capacity) then
    return false
  end
  local reach = math.huge
  for _, item in lasers do
    reach = math.min(reach, (Modules.byId[item.type].miner :: Modules.Miner).range)
  end
  local rock: System.Object?, least = nil, math.huge
  for _, object in Space.Describe(state, me.system).objects do
    if Mining.Rock(object) and object.site == post.id and Mining.Left(state, object) > 0 then
      local far = Space.Distance(object :: any, me :: any)
      if far < least then
        rock, least = object, far
      end
    end
  end
  if rock == nil then
    -- The belt is mined out: done, with anything aboard. Otherwise wait.
    if used > 0.03 * capacity then
      return false
    elseif me.mode ~= "stop" then
      give(state, { kind = "Stop", actor = me.id }, events)
    end
    return true
  end
  if Space.Gap(me :: any, rock :: any) > reach * 0.8 then
    if not (me.mode == "approach" and me.target == rock.id) then
      give(state, { kind = "Approach", actor = me.id, target = rock.id, range = reach * 0.5 }, events)
    end
    return true
  end
  local locked, targeted = false, false
  for _, lock in me.vitals.locks do
    if lock.target == rock.id then
      targeted, locked = true, lock.locked
    end
  end
  if not targeted then
    me.vitals.locks = {}
    give(state, { kind = "LockTarget", actor = me.id, target = rock.id }, events)
  elseif locked then
    for _, item in lasers do
      give(state, { kind = "ActivateModule", actor = me.id, item = item.id, target = rock.id }, events)
    end
  end
  return true
end

return Digger
