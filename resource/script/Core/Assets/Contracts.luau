--!strict
-- Contracts: things changing hands by the lot, at a station's board.
--
-- A market deals in one kind of thing at a time, at a price that moves.
-- A contract is a lot at a price: these things, all of them, for so
-- much. A station's board has three sorts.
--
-- Offers: lots somebody there will sell. Each day a station has a few:
-- a hull of its faction's with what it would be fitted with, packed; a
-- copy of some blueprint, good for so many runs; a few of some module
-- no station sells. What is asked is about what the lot is worth,
-- sometimes under and sometimes well over. Taken, the lot is in the
-- hangar there.
--
-- Wants: lots somebody there will pay for, more than a market would
-- for so many. They are of what nobody sells and a pilot builds or
-- finds: tech 2 modules, rounds, drones and hulls. Filled from the
-- hangar there, they pay at once.
--
-- Listings: a pilot's own. A stack from the hangar is put up at a
-- price, and is held by the board for a week. Now and then somebody
-- looks at it, and takes it if the price is near what it is worth
-- there: the nearer, the sooner, and well under its worth, within the
-- hour. What it is worth is what the station's market would give for so
-- many, for a thing a market deals in (so a listing is no way round a
-- market: it does as well as selling, more slowly, and what is sold by
-- it lands in the market as what is sold there does). A blueprint copy,
-- which no market deals in, is worth its base price to the builders of
-- a station until they have enough of that design, and less for each
-- one after: what they have had is forgotten by half in three days.
--
-- Putting up a listing pays the broker, and what it fetches pays the
-- sales tax, as an order does.

local Blueprints = require("@lt/Core/Data/Blueprints")
local Constants = require("@lt/Core/Data/Constants")
local Economy = require("@lt/Core/Strategic/Economy")
local Fits = require("@lt/Core/Fits")
local Items = require("@lt/Core/Assets/Items")
local Market = require("@lt/Core/Assets/Market")
local Modules = require("@lt/Core/Data/Modules")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Types = require("@lt/Core/Data/Types")
local Wallet = require("@lt/Core/Assets/Wallet")

local Contracts = {}

export type Event = { [string]: any }

-- A lot is so many of each of some types.
export type Stack = { type: string, quantity: number }
-- What a station's board has today: a lot for sale ('side' "offer",
-- and 'price' is what it costs) or a lot wanted ("want", and 'price' is
-- what it pays). 'worth' is the base price of it all.
export type Lot = { key: string, side: "offer" | "want", slot: number, title: string, stacks: { Stack }, price: number, worth: number }

local DAY = math.ceil(86400 / Constants.TICK)
local HOUR = math.ceil(3600 / Constants.TICK)

-- How many lots a station's board has for sale each day, and wants.
Contracts.OFFERS = 3
Contracts.WANTS = 2
-- How many lots a wandering trader has while they lie at a station.
Contracts.TRADER = 3
-- How long a pilot's listing stays up, and how many they can have up.
Contracts.LASTS = 7 * DAY
Contracts.LISTINGS = 10
-- (and so many more for each level of Ledger Keeping: Data/Skills)
Contracts.LEDGER = 2

-- How many listings a pilot can have up at once.
function Contracts.Limit(state: State.State): number
  return Contracts.LISTINGS + Contracts.LEDGER * math.max(0, state.skills["ledger.keeping"] or 0)
end
-- A listing asking this share of its worth or less is taken within the
-- hour; asking more than that share, never. Between the two, the chance
-- an hour runs from the one figure down to the other.
Contracts.SURE, Contracts.NEVER = 0.85, 1.05
Contracts.CHANCE = { near = 0.22, far = 0.02 }
-- What a station's builders will take of one design's copies at its
-- base price, in credits' worth, before they pay less; and how long
-- they take to forget half of what they have had.
Contracts.APPETITE = 250000
Contracts.FORGET = 3 * DAY

-- Whose a station is: the faction whose homeworld is nearest.
local function factionOf(state: State.State, station: number): string
  return state.galaxy.systems[Space.SystemOf(state, station)].nearest
end

-- Whether a station has a board: one somebody keeps, with a market.
local function hasBoard(state: State.State, station: number): boolean
  local object = Space.Object(state, station)
  return object ~= nil and object.kind == "station" and state.starbases[station] == nil
end

-- A lot's stacks, with every type once.
local function gathered(types: { string }, each: number): { Stack }
  local stacks: { Stack } = {}
  for _, type in types do
    local found = false
    for _, stack in stacks do
      if stack.type == type then
        stack.quantity += each
        found = true
      end
    end
    if not found then
      table.insert(stacks, { type = type, quantity = each })
    end
  end
  return stacks
end

-- The base price of a lot.
function Contracts.Base(stacks: { Stack }): number
  local worth = 0
  for _, stack in stacks do
    worth += Types.Info(stack.type).basePrice * stack.quantity
  end
  return worth
end

-- The hulls a station's board might have: its faction's own, of the
-- kinds anybody may buy, and nothing a yard takes a year over. (Where
-- the faction builds none to sell, anybody's.)
local hullsOf: { [string]: { Ships.ShipType } } = {}
local function hulls(faction: string): { Ships.ShipType }
  local found = hullsOf[faction]
  if found == nil then
    found = {}
    local any: { Ships.ShipType } = {}
    for _, hull in Ships.list do
      if hull.class ~= "capsule" and not hull.restricted and not hull.rare and hull.tech ~= 2 and not Ships.Capital(hull.class) then
        table.insert(any, hull)
        if hull.lineage == faction then
          table.insert(found, hull)
        end
      end
    end
    if #found == 0 then
      found = any
    end
    hullsOf[faction] = found
  end
  return found
end

-- The blueprints whose copies a board might have: the ones stations
-- sell, and the tech 2 ones nobody does (but not a people's own, nor
-- what is only built into a drone).
local plain: { Blueprints.Blueprint }, invented: { Blueprints.Blueprint } = {}, {}
-- The modules no station sells that a board might have a few of: tech 2
-- makes and custom ones.
local rare: { Modules.ModuleType } = {}
-- What a board might want: what nobody sells and a pilot builds, by the
-- category of it.
local wanted: { string } = {}
for _, blueprint in Blueprints.list do
  local module = Modules.byId[blueprint.product]
  if blueprint.rare or (module and (module.internal or module.lineage)) then
    continue
  elseif blueprint.invented then
    table.insert(invented, blueprint)
  else
    table.insert(plain, blueprint)
  end
end
for _, module in Modules.list do
  if (module.tech == 2 or module.meta) and not module.internal and not module.lineage and module.slot ~= "rig" then
    table.insert(rare, module)
  end
end
for _, id in Types.Ids() do
  local info = Types.Info(id)
  local module = Modules.byId[id]
  local hull = Ships.byId[id]
  if info.scarce and (info.category == "module" or info.category == "charge" or info.category == "drone" or info.category == "ship")
    and not (module and (module.internal or module.lineage or module.meta)) and not (hull and (hull.rare or hull.tech ~= 2)) then
    table.insert(wanted, id)
  end
end

-- The key of a lot: its station, day, side and place.
local function keyOf(station: number, day: number, side: string, slot: number): string
  return `{station}:{day}:{side}:{slot}`
end

-- What a station's board has today, less what has been taken: the lots
-- for sale, then the lots wanted.
function Contracts.Board(state: State.State, station: number): { Lot }
  if not hasBoard(state, station) then
    return {}
  end
  local day = state.tick // DAY
  local lots: { Lot } = {}
  for slot = 1, Contracts.OFFERS do
    local key = keyOf(station, day, "offer", slot)
    if table.find(state.contractsTaken, key) then
      continue
    end
    local rng = Rng.For(state.historySeed, station, day, slot, 131)
    local lot: Lot = { key = key, side = "offer", slot = slot, title = "", stacks = {}, price = 0, worth = 0 }
    if slot == 1 then
      -- A hull, with what it would be fitted with and something to fire.
      local line = hulls(factionOf(state, station))
      local hull = line[Rng.Int(rng, #line) + 1]
      local fit = Fits.Standard(hull)
      lot.stacks = gathered(fit, 1)
      table.insert(lot.stacks, 1, { type = hull.id, quantity = 1 })
      local loaded: { [string]: boolean } = {}
      for _, type in fit do
        local charge = Fits.Charge(type, hull)
        if charge and not loaded[charge] then
          loaded[charge] = true
          -- (crystals are not used up: one a gun. Rounds by the few hundred.)
          local crystal = Modules.chargeById[charge].family == "laser"
          local guns = 0
          for _, other in fit do
            guns += if Fits.Charge(other, hull) == charge then 1 else 0
          end
          table.insert(lot.stacks, { type = charge, quantity = if crystal then guns else 200 * guns })
        end
      end
      lot.title = `{hull.name}, fitted out`
      lot.worth = Contracts.Base(lot.stacks)
      lot.price = math.ceil(lot.worth * Rng.Float(rng, 0.88, 1.06))
    elseif slot == 2 then
      -- A copy of a blueprint: one a station sells, or now and then a
      -- tech 2 one, good for a few runs and dear.
      local tech2 = #invented > 0 and Rng.Chance(rng, 0.15)
      local from = if tech2 then invented else plain
      local blueprint = from[Rng.Int(rng, #from) + 1]
      local choice = if tech2 then { 1, 2, 3, 5 } else { 5, 10, 20, 50 }
      local runs = choice[Rng.Int(rng, #choice) + 1]
      lot.stacks = { { type = Blueprints.Copy(blueprint), quantity = runs } }
      lot.title = `{Types.Info(blueprint.product).name}: a copy, {runs} {if runs == 1 then "run" else "runs"}`
      lot.worth = Contracts.Base(lot.stacks)
      lot.price = math.ceil(lot.worth * (if tech2 then Rng.Float(rng, 1.5, 2.5) else Rng.Float(rng, 0.8, 1.3)))
    else
      -- A few of a module no station sells.
      local module = rare[Rng.Int(rng, #rare) + 1]
      local count = 1 + Rng.Int(rng, 3)
      lot.stacks = { { type = module.id, quantity = count } }
      lot.title = `{count} x {module.name}`
      lot.worth = Contracts.Base(lot.stacks)
      lot.price = math.ceil(lot.worth * Rng.Float(rng, 1.0, 1.5))
    end
    table.insert(lots, lot)
  end
  -- A wandering trader lying at the station (Tactical/Sightings, seen
  -- here by the state alone) has three lots of their own while they
  -- stay: modules no station sells, for less than a board asks, and a
  -- copy of a design no station has, for less than one is ever let go
  -- for. Each is theirs once: taken, it is gone until the next of them.
  for _, one in state.happenings.list do
    if one.kind == "sighting" and one.what == "trader" and one.place == station then
      for slot = 1, Contracts.TRADER do
        local key = `{station}:trader{one.id}:offer:{slot}`
        if table.find(state.contractsTaken, key) then
          continue
        end
        local rng = Rng.For(state.historySeed, station, one.id, slot, 139)
        local lot: Lot = { key = key, side = "offer", slot = Contracts.OFFERS + slot, title = "", stacks = {}, price = 0, worth = 0 }
        if slot == Contracts.TRADER and #invented > 0 then
          local blueprint = invented[Rng.Int(rng, #invented) + 1]
          local runs = 2 + Rng.Int(rng, 4)
          lot.stacks = { { type = Blueprints.Copy(blueprint), quantity = runs } }
          lot.title = `{one.name}: {Types.Info(blueprint.product).name}, a copy, {runs} runs`
          lot.worth = Contracts.Base(lot.stacks)
          lot.price = math.ceil(lot.worth * Rng.Float(rng, 0.9, 1.2))
        else
          local module = rare[Rng.Int(rng, #rare) + 1]
          local count = 1 + Rng.Int(rng, 2)
          lot.stacks = { { type = module.id, quantity = count } }
          lot.title = `{one.name}: {count} x {module.name}`
          lot.worth = Contracts.Base(lot.stacks)
          lot.price = math.ceil(lot.worth * Rng.Float(rng, 0.65, 0.9))
        end
        table.insert(lots, lot)
      end
    end
  end
  for slot = 1, Contracts.WANTS do
    local key = keyOf(station, day, "want", slot)
    if table.find(state.contractsTaken, key) or #wanted == 0 then
      continue
    end
    local rng = Rng.For(state.historySeed, station, day, slot, 137)
    local type = wanted[Rng.Int(rng, #wanted) + 1]
    local info = Types.Info(type)
    -- (so many as come to a few hundred thousand credits; of a hull, one)
    local sum = 200000 + 100000 * Rng.Int(rng, 9)
    local count = if info.category == "ship" then 1 else math.clamp(math.floor(sum / info.basePrice + 0.5), 1, 2000)
    local stacks: { Stack } = { { type = type, quantity = count } }
    local worth = Contracts.Base(stacks)
    table.insert(lots, { key = key, side = "want", slot = slot, title = `{count} x {info.name}`, stacks = stacks,
      price = math.floor(worth * Rng.Float(rng, 1.1, 1.4)), worth = worth })
  end
  return lots
end

-- A lot of a station's board today, by its side and place: nil if it is
-- taken, or was never there.
function Contracts.Lot(state: State.State, station: number, side: string, slot: number): Lot?
  for _, lot in Contracts.Board(state, station) do
    if lot.side == side and lot.slot == slot then
      return lot
    end
  end
  return nil
end

-- How much of a lot is in a station's hangar: for each stack, how many
-- are there (of as many as it wants, at most).
function Contracts.Have(state: State.State, station: number, stacks: { Stack }): { number }
  local have: { number } = {}
  for index, stack in stacks do
    have[index] = 0
    for _, item in Items.In(state, station, "hangar") do
      if item.type == stack.type then
        have[index] += item.quantity
      end
    end
    have[index] = math.min(have[index], stack.quantity)
  end
  return have
end

-- ---------------------------------------------------------------------
-- A pilot's own listings

-- How many of a design's copies a station's builders have had lately:
-- what they have been sold, less what they have forgotten.
local function had(state: State.State, station: number, type: string): number
  local byType = state.contractsHad[station]
  local entry = if byType then byType[type] else nil
  if entry == nil then
    return 0
  end
  return entry.units * 0.5 ^ ((state.tick - entry.tick) / Contracts.FORGET)
end

-- What so many of a type are worth to whoever looks at a station's
-- board: what its market would give for them, or, for what no market
-- deals in, their base price while the station's builders want them
-- and less for each one after.
function Contracts.Worth(state: State.State, station: number, type: string, quantity: number): number
  local index = Market.Index(type)
  if index then
    return math.floor(Economy.SellRevenue(Market.For(state, station), 1, index, quantity))
  end
  local base = Types.Info(type).basePrice
  local enough = math.max(1, Contracts.APPETITE / base)
  local already = had(state, station, type)
  return math.floor(base * enough * math.log((enough + already + quantity) / (enough + already)))
end

-- The pilot's listings, optionally at one station, oldest first.
function Contracts.Listings(state: State.State, station: number?): { State.Listing }
  local found = {}
  for _, id in state.contractIds do
    local listing = state.contracts[id]
    if station == nil or listing.station == station then
      table.insert(found, listing)
    end
  end
  return found
end

-- What putting a lot up at a price costs: the broker's fee.
function Contracts.Fee(state: State.State, station: number, price: number): number
  return math.ceil(price * Market.Fee(state, station))
end

-- The chance that a listing is taken in an hour, by what it asks
-- against what it is worth.
function Contracts.Chance(price: number, worth: number): number
  if worth <= 0 then
    return 0
  end
  local ratio = price / worth
  if ratio <= Contracts.SURE then
    return 1
  elseif ratio > Contracts.NEVER then
    return 0
  end
  local share = (Contracts.NEVER - ratio) / (Contracts.NEVER - Contracts.SURE)
  return Contracts.CHANCE.far + (Contracts.CHANCE.near - Contracts.CHANCE.far) * share
end

local function dockedAt(state: State.State, command: State.Command): (number?, string?)
  local ship = state.ships[command.actor]
  if ship == nil then
    return nil, "no such ship"
  elseif ship.docked == 0 then
    return nil, "not docked"
  elseif not hasBoard(state, ship.docked) then
    return nil, "there is no board here"
  end
  return ship.docked, nil
end

function Contracts.Validate(state: State.State, command: State.Command): (boolean, string?)
  local station, why = dockedAt(state, command)
  if station == nil then
    return false, why
  end
  local kind = command.kind
  if kind == "AcceptContract" then
    local lot = Contracts.Lot(state, station, "offer", command.target or 0)
    if lot == nil then
      return false, "that is not on the board"
    elseif lot.price > state.wallet then
      return false, "not enough credits"
    end
    return true

  elseif kind == "FillContract" then
    local lot = Contracts.Lot(state, station, "want", command.target or 0)
    if lot == nil then
      return false, "that is not on the board"
    end
    local have = Contracts.Have(state, station, lot.stacks)
    for index, stack in lot.stacks do
      if have[index] < stack.quantity then
        return false, `needs {stack.quantity - have[index]} more {Types.Info(stack.type).name} in the hangar here`
      end
    end
    return true

  elseif kind == "ListContract" then
    local item = state.items[command.item or 0]
    if item == nil or item.holder ~= station or item.place ~= "hangar" then
      return false, "that is not in the hangar here"
    end
    local quantity = command.quantity or item.quantity
    local price = command.price or 0
    if quantity < 1 or quantity % 1 ~= 0 or quantity > item.quantity then
      return false, "no such quantity"
    elseif price < 1 or price % 1 ~= 0 then
      return false, "no such price"
    elseif #state.contractIds >= Contracts.Limit(state) then
      return false, `{Contracts.Limit(state)} listings at a time`
    elseif Contracts.Fee(state, station, price) > state.wallet then
      return false, "not enough credits for the broker"
    end
    return true

  elseif kind == "CancelContract" then
    local listing = state.contracts[command.order or 0]
    if listing == nil then
      return false, "no such listing"
    elseif listing.station ~= station then
      return false, "that listing is at another station"
    end
    return true
  end
  return false, `unknown command '{kind}'`
end

-- A lot of the board is taken: nobody else has it today. (Yesterday's
-- are forgotten as today's are put down.)
local function take(state: State.State, key: string)
  table.insert(state.contractsTaken, key)
  local day = `:{state.tick // DAY}:`
  for index = #state.contractsTaken, 1, -1 do
    local taken = state.contractsTaken[index]
    -- (a wandering trader's lot is theirs, not a day's: it is kept as
    -- long as they are there)
    local trader = tonumber(string.match(taken, ":trader(%d+):"))
    local staying = false
    if trader then
      for _, one in state.happenings.list do
        staying = staying or one.id == trader
      end
    end
    if not staying and not string.find(taken, day, 1, true) then
      table.remove(state.contractsTaken, index)
    end
  end
end

local function close(state: State.State, listing: State.Listing)
  state.contracts[listing.id] = nil
  State.RemoveId(state.contractIds, listing.id)
end

function Contracts.Apply(state: State.State, command: State.Command, events: { Event })
  local ship = state.ships[command.actor]
  local station = ship.docked
  local kind = command.kind
  if kind == "AcceptContract" then
    local lot = Contracts.Lot(state, station, "offer", command.target :: number) :: Lot
    Wallet.Pay(state, -lot.price, "contract", events)
    for _, stack in lot.stacks do
      Items.Add(state, stack.type, stack.quantity, station, "hangar")
    end
    take(state, lot.key)
    table.insert(events, { kind = "ContractAccepted", station = station, title = lot.title, price = lot.price })

  elseif kind == "FillContract" then
    local lot = Contracts.Lot(state, station, "want", command.target :: number) :: Lot
    for _, stack in lot.stacks do
      local left = stack.quantity
      for _, item in Items.In(state, station, "hangar") do
        if left > 0 and item.type == stack.type then
          local taken = math.min(left, item.quantity)
          Items.Take(state, item, taken)
          left -= taken
        end
      end
    end
    Wallet.Pay(state, lot.price, "contract", events)
    take(state, lot.key)
    table.insert(events, { kind = "ContractFilled", station = station, title = lot.title, price = lot.price })

  elseif kind == "ListContract" then
    local item = state.items[command.item :: number]
    local quantity = command.quantity or item.quantity
    local price = command.price :: number
    local type = item.type
    Items.Take(state, item, quantity)
    Wallet.Pay(state, -Contracts.Fee(state, station, price), "broker's fee", events)
    local listing: State.Listing = { id = State.NewId(state), station = station, type = type, quantity = quantity, price = price,
      placed = state.tick, ends = state.tick + Contracts.LASTS }
    state.contracts[listing.id] = listing
    table.insert(state.contractIds, listing.id)
    table.insert(events, { kind = "ContractListed", listing = listing.id, type = type, quantity = quantity, price = price })

  elseif kind == "CancelContract" then
    local listing = state.contracts[command.order :: number]
    Items.Add(state, listing.type, listing.quantity, listing.station, "hangar")
    close(state, listing)
    table.insert(events, { kind = "ContractCancelled", listing = listing.id, type = listing.type, quantity = listing.quantity })
  end
end

-- Once a game hour: each of the pilot's listings is looked at, and taken
-- or not; and one whose week is up comes down, its lot back in the
-- hangar of the station it was put up at.
function Contracts.Step(state: State.State, events: { Event })
  if state.tick % HOUR ~= 0 or #state.contractIds == 0 then
    return
  end
  for _, id in table.clone(state.contractIds) do
    local listing = state.contracts[id]
    local worth = Contracts.Worth(state, listing.station, listing.type, listing.quantity)
    local chance = Contracts.Chance(listing.price, worth)
    if chance > 0 and Rng.Chance(Rng.For(state.historySeed, listing.id, state.tick // HOUR, 139), chance) then
      -- Taken: the pilot is paid, less the sales tax. What a market
      -- deals in lands in the station's market, as if sold there; a
      -- copy is one more the station's builders have had.
      local index = Market.Index(listing.type)
      if index then
        Economy.Sell(Market.For(state, listing.station), 1, index, listing.quantity)
      else
        local byType = state.contractsHad[listing.station]
        if byType == nil then
          byType = {}
          state.contractsHad[listing.station] = byType
        end
        byType[listing.type] = { units = had(state, listing.station, listing.type) + listing.quantity, tick = state.tick }
      end
      local paid = math.floor(listing.price * (1 - Market.Tax(state, listing.station)))
      Wallet.Pay(state, paid, "contract", events)
      close(state, listing)
      table.insert(events, { kind = "ContractSold", listing = id, station = listing.station, type = listing.type,
        quantity = listing.quantity, price = listing.price, paid = paid })
    elseif listing.ends <= state.tick then
      Items.Add(state, listing.type, listing.quantity, listing.station, "hangar")
      close(state, listing)
      table.insert(events, { kind = "ContractExpired", listing = id, station = listing.station, type = listing.type,
        quantity = listing.quantity })
    end
  end
end

return Contracts
