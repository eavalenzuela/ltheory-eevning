--!strict
-- Making things out of other things, at a station: for now, refining ore
-- into minerals.

local Items = require("@lt/Core/Assets/Items")
local Ores = require("@lt/Core/Data/Ores")
local State = require("@lt/Core/Kernel/State")

local Industry = {}

export type Event = { [string]: any }

-- The item, if it is a stack in the hangar of the station the ship is
-- docked at; otherwise nil and why not.
local function inHangar(state: State.State, command: State.Command): (State.Item?, string?)
  local ship = state.ships[command.actor]
  if ship == nil then
    return nil, "no such ship"
  elseif ship.docked == 0 then
    return nil, "not docked"
  end
  local item = state.items[command.item or 0]
  if item == nil then
    return nil, "no such item"
  elseif item.holder ~= ship.docked or item.place ~= "hangar" then
    return nil, "that is not in the hangar here"
  end
  return item, nil
end

-- What refining a stack of ore gives: the units used, and the minerals.
function Industry.RefineOutput(type: string, quantity: number): (number, { { mineral: string, amount: number } })
  local ore = Ores.byId[type]
  local batches = quantity // Ores.BATCH
  local out = {}
  for _, yield in ore.yields do
    local amount = math.floor(batches * yield.amount * Ores.REFINE_YIELD)
    if amount > 0 then
      table.insert(out, { mineral = yield.mineral, amount = amount })
    end
  end
  return batches * Ores.BATCH, out
end

function Industry.Validate(state: State.State, command: State.Command): (boolean, string?)
  local item, why = inHangar(state, command)
  if item == nil then
    return false, why
  end
  if command.kind == "Reprocess" then
    if Ores.byId[item.type] == nil then
      return false, "that is not ore"
    elseif item.quantity < Ores.BATCH then
      return false, `refining takes at least {Ores.BATCH} units`
    end
    return true
  end
  return false, `unknown command '{command.kind}'`
end

function Industry.Apply(state: State.State, command: State.Command, events: { Event })
  local ship = state.ships[command.actor]
  local item = state.items[command.item :: number]
  if command.kind == "Reprocess" then
    local type = item.type
    local used, minerals = Industry.RefineOutput(type, item.quantity)
    Items.Take(state, item, used)
    for _, m in minerals do
      Items.Add(state, m.mineral, m.amount, ship.docked, "hangar")
    end
    table.insert(events, { kind = "Reprocessed", ship = ship.id, ore = type, units = used, minerals = minerals })
  end
end

return Industry
