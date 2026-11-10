--!strict
-- The ships a pilot keeps at a station: assembling a bought hull into a
-- ship, and changing which ship is being flown.

local Items = require("@lt/Core/Assets/Items")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")

local Hangar = {}

export type Event = { [string]: any }

-- The player's ships docked at a station, in id order.
function Hangar.Ships(state: State.State, station: number): { State.Ship }
  local found = {}
  for _, id in state.shipIds do
    local ship = state.ships[id]
    if ship.owner == "player" and ship.docked == station then
      table.insert(found, ship)
    end
  end
  return found
end

function Hangar.Validate(state: State.State, command: State.Command): (boolean, string?)
  local ship = state.ships[command.actor]
  if ship == nil then
    return false, "no such ship"
  elseif ship.docked == 0 then
    return false, "not docked"
  end
  if command.kind == "Assemble" then
    local item = state.items[command.item or 0]
    if item == nil or item.holder ~= ship.docked or item.place ~= "hangar" then
      return false, "that is not in the hangar here"
    elseif Ships.byId[item.type] == nil then
      return false, "that is not a hull"
    end
    return true
  elseif command.kind == "BoardShip" then
    local other = state.ships[command.target or 0]
    if other == nil or other.owner ~= "player" or other.docked ~= ship.docked then
      return false, "that ship is not here"
    elseif other.id == ship.id then
      return false, "already aboard"
    end
    return true
  end
  return false, `unknown command '{command.kind}'`
end

function Hangar.Apply(state: State.State, command: State.Command, events: { Event })
  local ship = state.ships[command.actor]
  if command.kind == "Assemble" then
    local item = state.items[command.item :: number]
    local hull = Ships.byId[item.type]
    Items.Take(state, item, 1)
    local made = Space.NewShip(state, hull.id, hull.name, "player", ship.docked)
    table.insert(events, { kind = "ShipAssembled", ship = made.id, hull = hull.id })
  elseif command.kind == "BoardShip" then
    local other = state.ships[command.target :: number]
    state.player.ship = other.id
    -- A capsule is put away when its pilot steps out of it.
    if Ships.byId[ship.type].class == "capsule" then
      state.ships[ship.id] = nil
      State.RemoveId(state.shipIds, ship.id)
    end
    table.insert(events, { kind = "ShipBoarded", ship = other.id, from = ship.id })
  end
end

return Hangar
