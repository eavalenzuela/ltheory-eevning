--!strict
-- Mending one's friends: what a ship flown by the game does with the
-- remote repairers it has fitted (Data/Modules' "shield" and "armor"),
-- and with a relay that sends capacitor ("capacitor"). A hired pilot
-- does it for the player's side (Tactical/Fleet) and a pirate for the
-- pack (Tactical/Pirates).
--
-- A layer is mended for whoever has least of it left, under nine
-- tenths, until they are whole. Capacitor is sent to whoever has least
-- of theirs left, under half, until they have nine tenths: and only by
-- a ship that has more than half of its own, which stops when it is
-- down to a third.

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

-- How much a ship has left of what a module for a friend gives: its
-- shield, its armour or its capacitor, as a share of the whole.
local function left(ball: State.Ball, kind: string): number
  local v = ball.vitals
  return if kind == "shield" then v.shield / math.max(1, v.shieldMax)
    elseif kind == "capacitor" then v.capacitor / math.max(1, v.capacitorMax)
    else v.armor / math.max(1, v.armorMax)
end

-- What a ship has to be under to be given some, and at to be given no more.
local WANTS: { [string]: number } = { shield = 0.9, armor = 0.9, capacitor = 0.5 }
local ENOUGH: { [string]: number } = { shield = 0.99, armor = 0.99, capacitor = 0.9 }
-- What the ship that gives has to have of its own capacitor to begin,
-- and (for a relay, which gives its own away) to go on.
local BEGIN: { [string]: number } = { shield = 0.3, armor = 0.3, capacitor = 0.5 }
local SPARE = 1 / 3

-- Of 'friends' (ships, by id), the one on a ship's grid and within
-- reach that most wants a layer mended (or capacitor sent): the one
-- with the least of it left, if that is under what one has to be under.
local function hurt(state: State.State, me: State.Ball, friends: { number }, layer: string, reach: number): State.Ball?
  local worst: State.Ball?, least = nil, WANTS[layer] or 0.9
  for _, id in friends do
    local ball = state.balls[id]
    if ball and ball.id ~= me.id and ball.system == me.system and ball.grid == me.grid
      and Space.Gap(me :: any, ball :: any) <= reach then
      local share = left(ball, layer)
      if share < least then
        worst, least = ball, share
      end
    end
  end
  return worst
end

-- (For whoever has to fly to the one that wants mending before it can
-- be mended: a repair drone.)
Mend.Hurt = hurt

-- Every remote repairer a ship has goes on whoever of its friends wants
-- it most, and comes off when they are whole; and every relay likewise,
-- on whoever is shortest of capacitor. Returns the ships it is locked
-- on for that (by id), which are not to be let go of with the enemies'
-- locks.
function Mend.Tend(state: State.State, me: State.Ball, friends: { number }, events: { Event }): { [number]: boolean }
  local keep: { [number]: boolean } = {}
  for _, item in Items.Fitted(state, me.id) do
    local module = Modules.byId[item.type]
    local hex = module.hex
    if hex and Modules.Friendly(module) then
      local on: State.Running? = nil
      for _, each in me.vitals.running do
        if each.item == item.id then
          on = each
        end
      end
      if on then
        local target = state.balls[on.target]
        local whole = target == nil or left(target, hex.kind) >= (ENOUGH[hex.kind] or 0.99)
        -- (a relay gives its own away: it stops while there is still some to fly on)
        local short = hex.kind == "capacitor" and left(me, "capacitor") < SPARE
        if (whole or short) and not on.stopping then
          give(state, { kind = "DeactivateModule", actor = me.id, item = item.id }, events)
        end
        keep[on.target] = true
      elseif left(me, "capacitor") > (BEGIN[hex.kind] or 0.3) then
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
