--!strict
-- The ships a pilot keeps at a station: assembling a bought hull into a
-- ship, packing a ship up again into a hull for the market, and
-- changing which ship is being flown.
--
-- And the station that is the pilot's home: where they wake, in a
-- starter ship, when their capsule is destroyed (Tactical/Aftermath).
-- It is the station a new game begins at until the pilot takes a berth
-- at another: docked there, for a fee.

local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Wallet = require("@lt/Core/Assets/Wallet")

local Hangar = {}

export type Event = { [string]: any }

-- What a station charges to keep a berth for a pilot to wake in.
Hangar.HOME_FEE = 10000

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
    elseif other.pilot ~= 0 then
      return false, "a hired pilot flies that ship"
    end
    local missing = Skills.Missing(Skills.Needs(other.type), state.skills)
    if missing then
      return false, Skills.Describe(missing)
    end
    return true
  elseif command.kind == "Repackage" then
    -- (the owner, 2026-11-16: "can't repackage ships to sell?")
    local other = state.ships[command.target or 0]
    if other == nil or other.owner ~= "player" or other.docked ~= ship.docked then
      return false, "that ship is not here"
    elseif other.id == state.player.ship or other.id == ship.id then
      return false, "you are aboard it: board another first"
    elseif other.pilot ~= 0 then
      return false, "a hired pilot flies that ship"
    elseif Ships.byId[other.type] == nil or Ships.byId[other.type].class == "capsule" then
      return false, "that cannot be packaged"
    elseif (other.armorDamage or 0) > 0 or (other.hullDamage or 0) > 0 then
      return false, "it is damaged: repair it first"
    end
    return true
  elseif command.kind == "SetHome" then
    -- Home is made of the station docked at: any that somebody keeps,
    -- a colony ship among them (the pilot then wakes wherever it has
    -- got to). Not a tower of the pilot's own, which has no berths.
    local object = Space.Object(state, ship.docked)
    if object == nil or object.kind ~= "station" then
      return false, "this is no station"
    elseif ship.docked == state.player.home then
      return false, "this is your home already"
    elseif state.starbases[ship.docked] then
      return false, "a tower has no berth to wake in"
    elseif Hangar.HOME_FEE > state.wallet then
      return false, "not enough credits for the berth"
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
  elseif command.kind == "Repackage" then
    -- Packed for the market: whatever is fitted or carried goes into the
    -- hangar (a weapon's load beside it, a rig destroyed, as a rig is
    -- when it is taken out), and the hull is a packaged hull again.
    local other = state.ships[command.target :: number]
    local station = ship.docked
    for _, item in table.clone(Items.In(state, other.id)) do
      local module = Modules.byId[item.type]
      local takes = if module then Modules.Takes(module) else nil
      if item.slot > 0 and takes and item.charge ~= "" then
        local quantity = if takes.clip == 0 then 1 else item.rounds
        if quantity > 0 then
          Items.Add(state, item.charge, quantity, station, "hangar")
        end
      end
      local quantity, type = item.quantity, item.type
      local rig = item.slot > 0 and module ~= nil and module.slot == "rig"
      Items.Take(state, item, quantity)
      if not rig then
        Items.Add(state, type, quantity, station, "hangar")
      end
    end
    state.ships[other.id] = nil
    State.RemoveId(state.shipIds, other.id)
    Items.Add(state, other.type, 1, station, "hangar")
    table.insert(events, { kind = "ShipRepackaged", ship = other.id, hull = other.type, name = other.name })
  elseif command.kind == "SetHome" then
    local was = state.player.home
    state.player.home = ship.docked
    Wallet.Pay(state, -Hangar.HOME_FEE, "home berth", events)
    table.insert(events, { kind = "HomeMoved", station = ship.docked, was = was, fee = Hangar.HOME_FEE })
  end
end

return Hangar
