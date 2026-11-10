--!strict
-- Items: where everything a pilot owns is, and the orders that move it
-- (fit, unfit, load, move between hangar and cargo).
--
-- An item is a stack of one type in one place: a station's hangar, a
-- ship's cargo hold, or a slot in one of a ship's racks. Loose stacks of
-- the same type in the same place merge. A fitted module is always a
-- stack of one. A weapon's loaded charge is recorded on the weapon.
--
-- Fitting happens docked: the ship and the item must be at the same
-- station.

local Dogma = require("@lt/Core/Dogma")
local Modules = require("@lt/Core/Data/Modules")
local Ships = require("@lt/Core/Data/Ships")
local State = require("@lt/Core/Kernel/State")
local Types = require("@lt/Core/Data/Types")

local Items = {}

export type Event = { [string]: any }

local RACKS = { "high", "mid", "low" }

-- ---------------------------------------------------------------------
-- Looking

-- The items held by 'holder', optionally only those in one place, in id
-- order.
function Items.In(state: State.State, holder: number, place: string?): { State.Item }
  local found = {}
  for _, id in state.itemIds do
    local item = state.items[id]
    if item.holder == holder and (place == nil or item.place == place) then
      table.insert(found, item)
    end
  end
  return found
end

-- A ship's fitted modules, rack by rack (high, mid, low), slot by slot.
function Items.Fitted(state: State.State, ship: number): { State.Item }
  local found = {}
  for _, id in state.itemIds do
    local item = state.items[id]
    if item.holder == ship and item.slot > 0 then
      table.insert(found, item)
    end
  end
  local rank = { high = 1, mid = 2, low = 3 }
  table.sort(found, function(a: State.Item, b: State.Item): boolean
    local ra, rb = rank[a.place :: "high"], rank[b.place :: "high"]
    if ra ~= rb then
      return ra < rb
    end
    return a.slot < b.slot
  end)
  return found
end

-- The fit as the attribute engine wants it. 'running' says which module
-- items are switched on, by item id.
function Items.Fit(state: State.State, ship: number, running: { [number]: boolean }?): { Dogma.Fitted }
  local fit = {}
  for _, item in Items.Fitted(state, ship) do
    table.insert(fit, { type = item.type, running = running ~= nil and running[item.id] == true })
  end
  return fit
end

-- A ship's attributes with its present fit, nothing running.
function Items.ShipStats(state: State.State, ship: number): Dogma.Stats
  return Dogma.Ship(Ships.byId[state.ships[ship].type], Items.Fit(state, ship, nil))
end

-- Cubic metres in a ship's hold.
function Items.CargoUsed(state: State.State, ship: number): number
  local used = 0
  for _, item in Items.In(state, ship, "cargo") do
    used += item.quantity * Types.Info(item.type).volume
  end
  return used
end

-- ---------------------------------------------------------------------
-- Making and moving

-- Add 'quantity' of a type to a hangar or hold, merging with a stack that
-- is already there. Returns the stack.
function Items.Add(state: State.State, type: string, quantity: number, holder: number, place: "hangar" | "cargo"): State.Item
  assert(Types.Get(type), `no item type '{type}'`)
  assert(quantity > 0 and quantity % 1 == 0, "a quantity is a positive whole number")
  for _, item in Items.In(state, holder, place) do
    if item.type == type then
      item.quantity += quantity
      return item
    end
  end
  local item: State.Item = {
    id = State.NewId(state), type = type, quantity = quantity, holder = holder, place = place,
    slot = 0, charge = "", rounds = 0,
  }
  state.items[item.id] = item
  table.insert(state.itemIds, item.id)
  return item
end

-- Take 'quantity' out of a stack; the stack goes when it is empty.
function Items.Take(state: State.State, item: State.Item, quantity: number)
  assert(quantity > 0 and quantity <= item.quantity, "cannot take more than the stack holds")
  item.quantity -= quantity
  if item.quantity == 0 then
    state.items[item.id] = nil
    State.RemoveId(state.itemIds, item.id)
  end
end

-- ---------------------------------------------------------------------
-- Orders

-- The station a ship and an item share, or nil with the reason they do
-- not: the ship is in space, or the item is elsewhere.
local function sharedStation(state: State.State, ship: State.Ship, item: State.Item): (number?, string?)
  if ship.docked == 0 then
    return nil, "not docked"
  end
  local here = item.holder == ship.docked and item.place == "hangar"
  local aboard = item.holder == ship.id
  if not (here or aboard) then
    return nil, "that item is not here"
  end
  return ship.docked, nil
end

local function freeSlot(state: State.State, ship: number, rack: string, size: number): number
  local taken: { [number]: boolean } = {}
  for _, item in Items.In(state, ship, rack) do
    taken[item.slot] = true
  end
  for slot = 1, size do
    if not taken[slot] then
      return slot
    end
  end
  return 0
end

function Items.Validate(state: State.State, command: State.Command): (boolean, string?)
  local ship = state.ships[command.actor]
  if ship == nil then
    return false, "no such ship"
  end
  local item = state.items[command.item or 0]
  if item == nil then
    return false, "no such item"
  end
  local station, why = sharedStation(state, ship, item)
  if station == nil then
    return false, why
  end
  local hull = Ships.byId[ship.type]
  local kind = command.kind

  if kind == "Fit" then
    local module = Modules.byId[item.type]
    if module == nil then
      return false, "not a module"
    elseif item.slot > 0 then
      return false, "already fitted"
    end
    local types = {}
    for _, fitted in Items.Fitted(state, ship.id) do
      table.insert(types, fitted.type)
    end
    table.insert(types, item.type)
    return Dogma.Check(hull, types)

  elseif kind == "Unfit" then
    if item.slot == 0 or item.holder ~= ship.id then
      return false, "not fitted to this ship"
    end
    return true

  elseif kind == "LoadCharge" then
    local module = Modules.byId[item.type]
    if item.slot == 0 or item.holder ~= ship.id or module == nil or module.weapon == nil then
      return false, "not a fitted weapon"
    end
    local charge = state.items[command.other or 0]
    if charge == nil or charge.slot > 0 then
      return false, "no such charge"
    end
    local _, chargeWhy = sharedStation(state, ship, charge)
    if chargeWhy then
      return false, chargeWhy
    end
    local chargeType = Modules.chargeById[charge.type]
    if chargeType == nil or chargeType.family ~= module.weapon.family then
      return false, "that does not fit this weapon"
    end
    return true

  elseif kind == "MoveItems" then
    if item.slot > 0 then
      return false, "unfit it first"
    end
    local quantity = command.quantity or item.quantity
    if quantity <= 0 or quantity % 1 ~= 0 or quantity > item.quantity then
      return false, "no such quantity"
    end
    if command.to == "cargo" then
      if item.place == "cargo" then
        return false, "already in the hold"
      end
      local free = Items.ShipStats(state, ship.id).cargo - Items.CargoUsed(state, ship.id)
      if quantity * Types.Info(item.type).volume > free + 1e-9 then
        return false, "not enough room in the hold"
      end
      return true
    elseif command.to == "hangar" then
      if item.place == "hangar" then
        return false, "already in the hangar"
      end
      return true
    end
    return false, "move it where?"
  end
  return false, `unknown command '{kind}'`
end

-- Put a weapon's loaded charge back where loose items go (the hangar).
local function unload(state: State.State, weapon: State.Item, station: number)
  local module = Modules.byId[weapon.type]
  if weapon.charge ~= "" and module.weapon then
    -- A crystal is one item; rounds are however many are left.
    local quantity = if module.weapon.clip == 0 then 1 else weapon.rounds
    if quantity > 0 then
      Items.Add(state, weapon.charge, quantity, station, "hangar")
    end
  end
  weapon.charge = ""
  weapon.rounds = 0
end

function Items.Apply(state: State.State, command: State.Command, events: { Event })
  local ship = state.ships[command.actor]
  local item = state.items[command.item :: number]
  local station = ship.docked
  local kind = command.kind

  if kind == "Fit" then
    local module = Modules.byId[item.type]
    local hull = Ships.byId[ship.type] :: any
    local slot = freeSlot(state, ship.id, module.slot, hull[module.slot .. "s"])
    -- One leaves the stack and goes into the rack.
    local fitted: State.Item = {
      id = State.NewId(state), type = item.type, quantity = 1, holder = ship.id, place = module.slot,
      slot = slot, charge = "", rounds = 0,
    }
    Items.Take(state, item, 1)
    state.items[fitted.id] = fitted
    table.insert(state.itemIds, fitted.id)
    table.insert(events, { kind = "Fitted", ship = ship.id, item = fitted.id })

  elseif kind == "Unfit" then
    unload(state, item, station)
    local type = item.type
    Items.Take(state, item, 1)
    Items.Add(state, type, 1, station, "hangar")
    table.insert(events, { kind = "Unfitted", ship = ship.id, type = type })

  elseif kind == "LoadCharge" then
    local weapon = (Modules.byId[item.type].weapon :: Modules.Weapon)
    local charge = state.items[command.other :: number]
    local type = charge.type
    unload(state, item, station)
    -- (unloading may have merged into, but cannot have removed, the stack
    -- being loaded from)
    local stack = state.items[charge.id]
    local quantity = if weapon.clip == 0 then 1 else math.min(weapon.clip, stack.quantity)
    Items.Take(state, stack, quantity)
    item.charge = type
    item.rounds = if weapon.clip == 0 then 0 else quantity
    table.insert(events, { kind = "ChargeLoaded", ship = ship.id, item = item.id, charge = type })

  elseif kind == "MoveItems" then
    local quantity = command.quantity or item.quantity
    local type = item.type
    Items.Take(state, item, quantity)
    if command.to == "cargo" then
      Items.Add(state, type, quantity, ship.id, "cargo")
    else
      Items.Add(state, type, quantity, station, "hangar")
    end
    table.insert(events, { kind = "ItemsMoved", ship = ship.id, type = type, quantity = quantity, to = command.to })
  end
end

Items.RACKS = RACKS

return Items
