--!strict
-- Implants: plugging one in, and taking one out (Data/Implants has what
-- they are).
--
-- An implant is plugged in at a station, from the hangar there. It goes
-- in the place it is made for, which has to be empty, and the pilot has
-- to know enough Cybernetics for that place: one level a place. From
-- then on it is part of the pilot and counts for every ship they fly
-- (Assets/Items hands it to the attribute engine with the fit). Taking
-- one out destroys it; and a pilot whose capsule is destroyed loses
-- every one they had (Tactical/Aftermath).

local Items = require("@lt/Core/Assets/Items")
local Kinds = require("@lt/Core/Data/Implants")
local State = require("@lt/Core/Kernel/State")

local Implants = {}

export type Event = { [string]: any }

-- The implant a pilot has in a place, if any.
function Implants.In(state: State.State, slot: number): Kinds.Implant?
  for _, id in state.implants do
    if Kinds.byId[id].slot == slot then
      return Kinds.byId[id]
    end
  end
  return nil
end

function Implants.Validate(state: State.State, command: State.Command): (boolean, string?)
  local ship = state.ships[command.actor]
  if ship == nil or ship.id ~= state.player.ship then
    return false, "no such ship"
  elseif State.At(ship) == 0 then
    return false, "not docked"
  end
  if command.kind == "PlugImplant" then
    local item = state.items[command.item or 0]
    if item == nil or item.holder ~= State.At(ship) or item.place ~= "hangar" then
      return false, "that is not in the hangar here"
    end
    local implant = Kinds.byId[item.type]
    if implant == nil then
      return false, "that is not an implant"
    elseif (state.skills.cybernetics or 0) < implant.slot then
      return false, `needs Cybernetics {implant.slot}`
    elseif Implants.In(state, implant.slot) then
      return false, "that place has an implant in it: it has to come out first"
    end
    return true
  elseif command.kind == "UnplugImplant" then
    if table.find(state.implants, command.what or "") == nil then
      return false, "no such implant is plugged in"
    end
    return true
  end
  return false, `unknown command '{command.kind}'`
end

function Implants.Apply(state: State.State, command: State.Command, events: { Event })
  if command.kind == "PlugImplant" then
    local item = state.items[command.item :: number]
    local implant = Kinds.byId[item.type]
    -- (one that is plugged in is no longer an item)
    Items.Take(state, item, 1)
    table.insert(state.implants, implant.id)
    table.sort(state.implants, function(a: string, b: string): boolean
      return Kinds.byId[a].slot < Kinds.byId[b].slot
    end)
    table.insert(events, { kind = "ImplantPlugged", implant = implant.id, slot = implant.slot })
  elseif command.kind == "UnplugImplant" then
    local at = table.find(state.implants, command.what :: string) :: number
    table.remove(state.implants, at)
    table.insert(events, { kind = "ImplantDestroyed", implant = command.what })
  end
end

return Implants
