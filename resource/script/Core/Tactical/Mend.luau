--!strict
-- Mending one's friends: what a ship flown by the game does with the
-- remote repairers it has fitted (Data/Modules' "shield" and "armor").
-- A hired pilot does it for the player's side (Tactical/Fleet) and a
-- pirate for the pack (Tactical/Pirates).

local Combat = require("@lt/Core/Tactical/Combat")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")

local Mend = {}

export type Event = { [string]: any }

local function give(state: State.State, command: State.Command, events: { Event })
  if Combat.Validate(state, command) then
    Combat.Apply(state, command, events)
  end
end

-- Of 'friends' (ships, by id), the one on a ship's grid and within
-- reach that most wants a layer mended: the one with the least of it
-- left, if that is under nine tenths.
local function hurt(state: State.State, me: State.Ball, friends: { number }, layer: string, reach: number): State.Ball?
  local worst: State.Ball?, least = nil, 0.9
  for _, id in friends do
    local ball = state.balls[id]
    if ball and ball.id ~= me.id and ball.system == me.system and ball.grid == me.grid
      and Space.Gap(me :: any, ball :: any) <= reach then
      local v = ball.vitals
      local share = if layer == "shield" then v.shield / math.max(1, v.shieldMax) else v.armor / math.max(1, v.armorMax)
      if share < least then
        worst, least = ball, share
      end
    end
  end
  return worst
end

-- Every remote repairer a ship has goes on whoever of its friends wants
-- it most, and comes off when they are whole. Returns the ships it is
-- locked on for that (by id), which are not to be let go of with the
-- enemies' locks.
function Mend.Tend(state: State.State, me: State.Ball, friends: { number }, events: { Event }): { [number]: boolean }
  local keep: { [number]: boolean } = {}
  for _, item in Items.Fitted(state, me.id) do
    local module = Modules.byId[item.type]
    local hex = module.hex
    if hex and Modules.Mends(module) then
      local on: State.Running? = nil
      for _, each in me.vitals.running do
        if each.item == item.id then
          on = each
        end
      end
      if on then
        local target = state.balls[on.target]
        local whole = target == nil
          or (if hex.kind == "shield" then target.vitals.shield >= 0.99 * target.vitals.shieldMax
            else target.vitals.armor >= 0.99 * target.vitals.armorMax)
        if whole and not on.stopping then
          give(state, { kind = "DeactivateModule", actor = me.id, item = item.id }, events)
        end
        keep[on.target] = true
      elseif me.vitals.capacitor > 0.3 * me.vitals.capacitorMax then
        local friend = hurt(state, me, friends, hex.kind, hex.range)
        if friend then
          keep[friend.id] = true
          local held: State.Lock? = nil
          for _, lock in me.vitals.locks do
            if lock.target == friend.id then
              held = lock
            end
          end
          if held == nil then
            give(state, { kind = "LockTarget", actor = me.id, target = friend.id }, events)
          elseif held.locked then
            give(state, { kind = "ActivateModule", actor = me.id, item = item.id, target = friend.id }, events)
          end
        end
      end
    end
  end
  return keep
end

return Mend
