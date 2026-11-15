--!strict
-- Paintwork: a ship painted, and stripped. (The owner's list of
-- 2026-11-15: "paint system in-game (apply different designs + paint
-- sets to ships, that you buy on market)".)
--
-- Docked, with a paint or a design (Data/Paints) in the hangar there,
-- the ship the pilot is in is painted with it. The thing is used up.
-- The ship keeps its paint and its design until it is painted again
-- (the new takes the place of the old, which is gone) or stripped back
-- to how it left the yard (nothing is given back for that). A design
-- needs a paint under it.
--
-- A ship's paint goes with the ship: sold, lost, or handed to a hired
-- pilot, it is still painted. It changes nothing but how the ship
-- looks.

local Items = require("@lt/Core/Assets/Items")
local Paints = require("@lt/Core/Data/Paints")
local State = require("@lt/Core/Kernel/State")

local Paintwork = {}

export type Event = { [string]: any }

Paintwork.COMMANDS = { Paint = true, StripPaint = true }

-- Why a ship cannot be painted with an item, or nil if it can.
local function refused(state: State.State, ship: State.Ship, item: State.Item?): string?
  if item == nil or item.holder ~= ship.docked or item.place ~= "hangar" then
    return "that is not in the hangar here"
  end
  local paint, design = Paints.paintById[item.type], Paints.designById[item.type]
  if paint == nil and design == nil then
    return "that is neither a paint nor a design"
  elseif paint and ship.paint == paint.id then
    return "the ship is in that paint already"
  elseif design and ship.paint == nil then
    return "a design needs a paint under it: paint the ship first"
  elseif design and ship.design == design.id then
    return "the ship has that design already"
  end
  return nil
end

function Paintwork.Validate(state: State.State, command: State.Command): (boolean, string?)
  local ship = state.ships[command.actor]
  if ship == nil then
    return false, "no such ship"
  elseif ship.docked == 0 then
    return false, "not docked"
  end
  if command.kind == "StripPaint" then
    if ship.paint == nil and ship.design == nil then
      return false, "the ship is as it left the yard"
    end
    return true
  end
  local why = refused(state, ship, state.items[command.item or 0])
  if why then
    return false, why
  end
  return true
end

function Paintwork.Apply(state: State.State, command: State.Command, events: { Event })
  local ship = state.ships[command.actor]
  if command.kind == "StripPaint" then
    ship.paint, ship.design = nil, nil
    table.insert(events, { kind = "Painted", ship = ship.id, stripped = true })
    return
  end
  local item = state.items[command.item :: number]
  local type = item.type
  Items.Take(state, item, 1)
  if Paints.paintById[type] then
    ship.paint = type
  else
    ship.design = type
  end
  table.insert(events, { kind = "Painted", ship = ship.id, with = type, paint = ship.paint, design = ship.design })
end

return Paintwork
