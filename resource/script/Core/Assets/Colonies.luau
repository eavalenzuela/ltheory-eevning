--!strict
-- Colonies: planets worked (Data/Planets has what there is to take and
-- to make, and the figures).
--
-- The rules:
--   - A command centre is put down from a ship's hold, from near the
--     planet, on a planet that can be worked and has no colony yet.
--   - Facilities are raised round it for credits, from anywhere (a
--     colony is run from a distance, as EVE's are), within the power
--     and CPU the centre supplies: extractors, each set on one raw
--     material the planet has; processors, each making one product of
--     a raw material the planet has; storage.
--   - An extractor works on a programme of a set length. Each cycle it
--     brings up a little less than the last, so a programme that has
--     run a while is worth starting again, and when it ends the
--     extractor stops until it is given another.
--   - A processor takes a batch of its raw material whenever the store
--     has one and delivers the product a cycle later.
--   - Everything goes through the colony's one store. Raw material that
--     finds no room is lost; what is made always finds room.
--   - A ship near the planet takes what it wants from the store into
--     its hold, and pays a tax on its worth to have it brought up.
--
-- Not yet: sending anything down to a colony, a centre that can be
-- upgraded or taken up again, the facilities as places on the planet
-- with links between them, a customs office to shoot at.

local Constants = require("@lt/Core/Data/Constants")
local Items = require("@lt/Core/Assets/Items")
local Planets = require("@lt/Core/Data/Planets")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")
local Types = require("@lt/Core/Data/Types")
local Wallet = require("@lt/Core/Assets/Wallet")

local Colonies = {}

export type Event = { [string]: any }

local CYCLE = math.ceil(Planets.CYCLE / Constants.TICK)

-- The planet a command names, if it is one.
local function planetOf(state: State.State, command: State.Command): System.Object?
  local object = Space.Object(state, command.target or 0)
  return if object and object.kind == "planet" then object else nil
end

-- The colony a command names, if it is the commanding ship's owner's.
local function colonyOf(state: State.State, command: State.Command): State.Colony?
  local ship = state.ships[command.actor]
  local colony = state.colonies[command.target or 0]
  return if colony and ship and colony.owner == ship.owner then colony else nil
end

local function pinOf(colony: State.Colony, id: number?): State.Pin?
  for _, pin in colony.pins do
    if pin.id == id then
      return pin
    end
  end
  return nil
end

-- Whether a planet has a raw material.
local function has(planet: System.Object, raw: string): boolean
  local deposits: { string }? = Planets.DEPOSITS[planet.variety]
  return deposits ~= nil and table.find(deposits, raw) ~= nil
end

-- The powergrid and CPU a colony's facilities draw between them.
function Colonies.Draw(colony: State.Colony): (number, number)
  local powergrid, cpu = 0, 0
  for _, pin in colony.pins do
    local facility = Planets.facilityById[pin.kind]
    powergrid += facility.powergrid
    cpu += facility.cpu
  end
  return powergrid, cpu
end

-- The room a colony's store has, and how much of it is taken, m3.
function Colonies.Room(colony: State.Colony): (number, number)
  local room = Planets.CENTRE.room
  for _, pin in colony.pins do
    room += Planets.facilityById[pin.kind].room
  end
  local used = 0
  for _, stored in colony.store do
    used += stored.quantity * Types.Info(stored.type).volume
  end
  return room, used
end

-- How many of a type a colony's store holds.
function Colonies.Stored(colony: State.Colony, type: string): number
  for _, stored in colony.store do
    if stored.type == type then
      return stored.quantity
    end
  end
  return 0
end

-- Put 'quantity' of a type into the store (kept in the order of the
-- types' ids, so it is the same store however it was filled).
local function put(colony: State.Colony, type: string, quantity: number)
  if quantity <= 0 then
    return
  end
  local at = #colony.store + 1
  for index, stored in colony.store do
    if stored.type == type then
      stored.quantity += quantity
      return
    elseif stored.type > type then
      at = index
      break
    end
  end
  table.insert(colony.store, at, { type = type, quantity = quantity })
end

local function take(colony: State.Colony, type: string, quantity: number)
  for index, stored in colony.store do
    if stored.type == type then
      assert(stored.quantity >= quantity, "a colony has not that many")
      stored.quantity -= quantity
      if stored.quantity == 0 then
        table.remove(colony.store, index)
      end
      return
    end
  end
  error("a colony has none of that")
end

-- Whether a ship is near enough a planet to put a centre down on it or
-- to have goods brought up; if not, why not.
local function near(state: State.State, ship: State.Ship, planet: System.Object): (boolean, string?)
  local ball = state.balls[ship.id]
  if ball == nil then
    return false, "docked"
  elseif ball.warp and ball.warp.stage == "warp" then
    return false, "in warp"
  elseif Space.SystemOf(state, planet.id) ~= ball.system or Space.Distance(ball :: any, planet :: any) > planet.radius * Planets.REACH then
    return false, "too far from the planet"
  end
  return true
end

-- Whether the ship of a pilot is near enough a planet to trade with a
-- colony on it.
function Colonies.Near(state: State.State, ship: number, planet: number): boolean
  local object = Space.Object(state, planet)
  local record = state.ships[ship]
  return object ~= nil and record ~= nil and (near(state, record, object))
end

-- How many of a type a ship could take up from a colony now: what is
-- there, what the hold has room for, and what the pilot can pay the tax
-- on.
function Colonies.Fits(state: State.State, ship: number, colony: State.Colony, type: string): number
  local info = Types.Info(type)
  local free = Items.ShipStats(state, ship).cargo - Items.CargoUsed(state, ship)
  local count = math.min(Colonies.Stored(colony, type), math.floor(free / info.volume + 1e-6))
  local each = info.basePrice * Planets.EXPORT_TAX
  if each > 0 then
    count = math.min(count, math.floor(state.wallet / each))
  end
  return math.max(0, count)
end

-- The tax on bringing 'quantity' of a type up to a ship.
function Colonies.Tax(type: string, quantity: number): number
  return math.ceil(Types.Info(type).basePrice * quantity * Planets.EXPORT_TAX)
end

function Colonies.Validate(state: State.State, command: State.Command): (boolean, string?)
  local ship = state.ships[command.actor]
  if ship == nil then
    return false, "no such ship"
  end
  local kind = command.kind
  if kind == "DeployColony" then
    local item = state.items[command.item or 0]
    if item == nil or item.holder ~= ship.id or item.place ~= "cargo" or item.type ~= Planets.CENTRE.id then
      return false, "no command centre in the hold"
    end
    local planet = planetOf(state, command)
    if planet == nil then
      return false, "a colony is put down on a planet"
    elseif Planets.DEPOSITS[planet.variety] == nil then
      return false, "nothing can be worked there"
    end
    local ok, why = near(state, ship, planet)
    if not ok then
      return false, why
    elseif state.colonies[planet.id] then
      return false, "that planet has a colony already"
    end
    return true
  end

  local colony = colonyOf(state, command)
  local planet = planetOf(state, command)
  if colony == nil or planet == nil then
    return false, "no colony of yours there"
  end
  if kind == "BuildFacility" then
    local facility = Planets.facilityById[command.type or ""]
    if facility == nil then
      return false, "no such facility"
    end
    local what = command.what or ""
    if facility.id == "extractor" then
      if Planets.rawById[what] == nil or not has(planet, what) then
        return false, "an extractor is set on something the planet has"
      end
    elseif facility.id == "processor" then
      local product = Planets.productById[what]
      if product == nil then
        return false, "a processor is set to make something"
      elseif not has(planet, product.from) then
        return false, `nothing here to make {product.name} from`
      end
    end
    local powergrid, cpu = Colonies.Draw(colony)
    if powergrid + facility.powergrid > Planets.CENTRE.powergrid then
      return false, "the command centre has not the powergrid"
    elseif cpu + facility.cpu > Planets.CENTRE.cpu then
      return false, "the command centre has not the CPU"
    elseif state.wallet < facility.cost then
      return false, "not enough credits"
    end
    return true
  elseif kind == "RemoveFacility" then
    local pin = pinOf(colony, command.pin)
    if pin == nil then
      return false, "no such facility"
    end
    local room, used = Colonies.Room(colony)
    if used > room - Planets.facilityById[pin.kind].room then
      return false, "it holds more than there would be room for"
    end
    return true
  elseif kind == "StartExtraction" then
    local pin = pinOf(colony, command.pin)
    if pin == nil or pin.kind ~= "extractor" then
      return false, "no such extractor"
    elseif table.find(Planets.PROGRAMMES, command.hours or 0) == nil then
      return false, `a programme runs {table.concat(Planets.PROGRAMMES, ", ")} hours`
    end
    return true
  elseif kind == "Export" then
    local ok, why = near(state, ship, planet)
    if not ok then
      return false, why
    end
    local type = command.type or ""
    local stored = Colonies.Stored(colony, type)
    if stored == 0 then
      return false, "the colony has none of that"
    end
    local quantity = command.quantity or stored
    if quantity < 1 or quantity > stored or quantity % 1 ~= 0 then
      return false, "not that many"
    end
    local free = Items.ShipStats(state, ship.id).cargo - Items.CargoUsed(state, ship.id)
    if quantity * Types.Info(type).volume > free + 1e-6 then
      return false, "not enough room in the hold"
    elseif Colonies.Tax(type, quantity) > state.wallet then
      return false, "not enough credits for the export tax"
    end
    return true
  end
  return false, `unknown command '{kind}'`
end

function Colonies.Apply(state: State.State, command: State.Command, events: { Event })
  local ship = state.ships[command.actor]
  local kind = command.kind
  if kind == "DeployColony" then
    local planet = planetOf(state, command) :: System.Object
    Items.Take(state, state.items[command.item :: number], 1)
    state.colonies[planet.id] = { planet = planet.id, owner = ship.owner, pins = {}, pinSeq = 0, store = {} }
    State.InsertId(state.colonyIds, planet.id)
    table.insert(events, { kind = "ColonyDeployed", planet = planet.id, by = ship.id })
    return
  end

  local colony = colonyOf(state, command) :: State.Colony
  if kind == "BuildFacility" then
    local facility = Planets.facilityById[command.type :: string]
    Wallet.Pay(state, -facility.cost, `colony: {string.lower(facility.name)}`, events)
    colony.pinSeq += 1
    table.insert(colony.pins, { id = colony.pinSeq, kind = facility.id, what = if facility.id == "storage" then "" else command.what :: string,
      ends = 0, next = 0, cycle = 0 })
    table.insert(events, { kind = "FacilityBuilt", planet = colony.planet, pin = colony.pinSeq, type = facility.id })
  elseif kind == "RemoveFacility" then
    for index, pin in colony.pins do
      if pin.id == command.pin then
        table.remove(colony.pins, index)
        table.insert(events, { kind = "FacilityRemoved", planet = colony.planet, pin = pin.id, type = pin.kind })
        break
      end
    end
  elseif kind == "StartExtraction" then
    local pin = pinOf(colony, command.pin) :: State.Pin
    pin.cycle = 0
    pin.next = state.tick + CYCLE
    pin.ends = state.tick + math.ceil((command.hours :: number) * 3600 / Constants.TICK)
    table.insert(events, { kind = "ExtractionStarted", planet = colony.planet, pin = pin.id, hours = command.hours })
  elseif kind == "Export" then
    local type = command.type :: string
    local quantity = command.quantity or Colonies.Stored(colony, type)
    take(colony, type, quantity)
    Items.Add(state, type, quantity, ship.id, "cargo")
    local tax = Colonies.Tax(type, quantity)
    Wallet.Pay(state, -tax, "export tax", events)
    table.insert(events, { kind = "Exported", planet = colony.planet, ship = ship.id, type = type, quantity = quantity, tax = tax })
  end
end

-- Once a tick: every extractor whose cycle has come round brings up
-- what it brings, and every processor takes a batch or delivers one.
function Colonies.Step(state: State.State, events: { Event })
  for _, id in state.colonyIds do
    local colony = state.colonies[id]
    local planet = Space.Object(state, id) :: System.Object
    for _, pin in colony.pins do
      if pin.kind == "extractor" and pin.ends > 0 then
        while pin.next <= pin.ends and state.tick >= pin.next do
          local raw = Planets.rawById[pin.what]
          local room, used = Colonies.Room(colony)
          local fits = math.floor((room - used) / raw.volume + 1e-6)
          put(colony, raw.id, math.min(Planets.Yield(Planets.Richness(planet.seed, raw.id), pin.cycle), fits))
          pin.cycle += 1
          pin.next += CYCLE
        end
        if pin.next > pin.ends then
          pin.ends, pin.next = 0, 0
          table.insert(events, { kind = "ExtractionEnded", planet = id, pin = pin.id, raw = pin.what })
        end
      elseif pin.kind == "processor" then
        local product = Planets.productById[pin.what]
        if pin.next > 0 and state.tick >= pin.next then
          put(colony, product.id, product.output)
          pin.next = 0
        end
        if pin.next == 0 and Colonies.Stored(colony, product.from) >= product.input then
          take(colony, product.from, product.input)
          pin.next = state.tick + CYCLE
        end
      end
    end
  end
end

return Colonies
