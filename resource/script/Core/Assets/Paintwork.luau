--!strict
-- Paintwork: a paint made the pilot's own, a ship painted, and stripped.
-- (The owner's list of 2026-11-15: "paint system in-game (apply
-- different designs + paint sets to ships, that you buy on market)";
-- and their ruling of the same day, asked whether a paint should be
-- used up by a painting: "Unlocked for good, switch via a list in
-- fitting screen".)
--
-- A paint or a design (Data/Paints) is a thing a market sells. Made the
-- pilot's own (UnlockPaint), the thing is used up and the paint is
-- theirs for good: state.paints. That is done where the thing is: in
-- the hangar of the station they are docked at, or in the hold of the
-- ship they fly. A faction's livery brings with it the design that
-- faction's ships wear on it.
--
-- Docked, the ship the pilot is in is painted in any paint that is
-- theirs, and has any design that is theirs laid on it, as often as
-- they like and for nothing (Paint); and either comes off again
-- (StripPaint: the design alone, or all of it back to how the ship left
-- the yard). A design needs a paint under it. One that is not theirs
-- yet and lies in the hangar there is made theirs by the painting.
--
-- A ship's paint goes with the ship: sold, lost, or handed to a hired
-- pilot, it is still painted. It changes nothing but how the ship
-- looks.

local Items = require("@lt/Core/Assets/Items")
local Paints = require("@lt/Core/Data/Paints")
local State = require("@lt/Core/Kernel/State")

local Paintwork = {}

export type Event = { [string]: any }

Paintwork.COMMANDS = { UnlockPaint = true, Paint = true, StripPaint = true }

-- Whether a paint or a design is the pilot's.
function Paintwork.Has(state: State.State, type: string): boolean
  return state.paints[type] == true
end

-- The thing in the hangar where a ship is docked that would make a
-- paint or a design the pilot's, if one lies there.
local function lying(state: State.State, ship: State.Ship, type: string): State.Item?
  if ship.docked ~= 0 then
    for _, item in Items.In(state, ship.docked, "hangar") do
      if item.type == type then
        return item
      end
    end
  end
  return nil
end

-- A paint or a design becomes the pilot's: and with a livery, the
-- design that faction's ships wear on it.
local function give(state: State.State, type: string, events: { Event })
  state.paints[type] = true
  local paint = Paints.paintById[type]
  if paint and paint.wears then
    state.paints[paint.wears] = true
  end
  table.insert(events, { kind = "PaintUnlocked", type = type, with = if paint then paint.wears else nil })
end

function Paintwork.Validate(state: State.State, command: State.Command): (boolean, string?)
  local ship = state.ships[command.actor]
  if ship == nil then
    return false, "no such ship"
  end
  local kind = command.kind
  if kind == "UnlockPaint" then
    local item = state.items[command.item or 0]
    local inHangar = item ~= nil and ship.docked ~= 0 and item.holder == ship.docked and item.place == "hangar"
    local inHold = item ~= nil and item.holder == ship.id and item.place == "cargo"
    if item == nil or not (inHangar or inHold) then
      return false, "that is not in the hangar here, nor in the hold"
    elseif Paints.paintById[item.type] == nil and Paints.designById[item.type] == nil then
      return false, "that is neither a paint nor a design"
    elseif state.paints[item.type] then
      return false, "it is yours already"
    end
    return true
  elseif ship.docked == 0 then
    return false, "not docked"
  elseif kind == "StripPaint" then
    if command.what == "design" then
      if ship.design == nil then
        return false, "the ship has no design on it"
      end
    elseif ship.paint == nil and ship.design == nil then
      return false, "the ship is as it left the yard"
    end
    return true
  end
  local type = command.type or ""
  local paint, design = Paints.paintById[type], Paints.designById[type]
  if paint == nil and design == nil then
    return false, "that is neither a paint nor a design"
  elseif not state.paints[type] and lying(state, ship, type) == nil then
    return false, "that is not one of yours: a market sells it"
  elseif paint and ship.paint == paint.id then
    return false, "the ship is in that paint already"
  elseif design and ship.paint == nil then
    return false, "a design needs a paint under it: paint the ship first"
  elseif design and ship.design == design.id then
    return false, "the ship has that design already"
  end
  return true
end

function Paintwork.Apply(state: State.State, command: State.Command, events: { Event })
  local ship = state.ships[command.actor]
  local kind = command.kind
  if kind == "UnlockPaint" then
    local item = state.items[command.item :: number]
    local type = item.type
    Items.Take(state, item, 1)
    give(state, type, events)
  elseif kind == "StripPaint" then
    if command.what == "design" then
      ship.design = nil
      table.insert(events, { kind = "Painted", ship = ship.id, paint = ship.paint })
    else
      ship.paint, ship.design = nil, nil
      table.insert(events, { kind = "Painted", ship = ship.id, stripped = true })
    end
  else
    local type = command.type :: string
    if not state.paints[type] then
      Items.Take(state, lying(state, ship, type) :: State.Item, 1)
      give(state, type, events)
    end
    if Paints.paintById[type] then
      ship.paint = type
    else
      ship.design = type
    end
    table.insert(events, { kind = "Painted", ship = ship.id, with = type, paint = ship.paint, design = ship.design })
  end
end

return Paintwork
