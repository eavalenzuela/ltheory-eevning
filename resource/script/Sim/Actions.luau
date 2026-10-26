--!strict
-- Submitting actions. Each reserves what it uses straight away (the fleet,
-- the goods for a ship) and schedules its timer. Moves run as a chain of
-- one-jump timers; a convoy is a move to its pickup station, then to its
-- delivery station. Cancelling is itself an action and unlocks what the
-- cancelled action held.

local Data = require("@lt/Sim/Data")
local Galaxy = require("@lt/Sim/Galaxy")
local Market = require("@lt/Sim/Market")
local State = require("@lt/Sim/State")

local Actions = {}

local function newAction(state: State.State, owner: number, kind: "move" | "convoy" | "build" | "siege" | "construct"): State.Action
  local action: State.Action = {
    id = State.NewId(state),
    owner = owner,
    kind = kind,
    submitted = state.tick,
    phase = state.phase,
    due = state.tick,
    done = false,
  }
  state.actions[action.id] = action
  State.Count(state, `submitted {kind}`)
  return action
end

local function releasePickup(state: State.State, action: State.Action)
  if action.claimed then
    action.claimed = false
    State.AddPending(state, "out", action.from :: number, action.good :: string, -(action.quantity :: number))
  end
end

-- Ends an action and frees its fleet (and a convoy's reservations)
function Actions.Finish(state: State.State, action: State.Action)
  if action.kind == "convoy" then
    releasePickup(state, action)
    if action.expected then
      action.expected = false
      State.AddPending(state, "in", action.to :: number, action.good :: string, -(action.quantity :: number))
    end
  end
  action.done = true
  state.actions[action.id] = nil
  -- Reactions to it no longer need remembering
  state.reacted[`ambush:{action.id}`] = nil
  for _, f in state.factions do
    state.reacted[`defend:{f.id}:{action.id}`] = nil
  end
  local fleet = if action.fleet then state.fleets[action.fleet] else nil
  if fleet and fleet.action == action.id then
    fleet.action = nil
    fleet.idleSince = state.tick
  end
end

-- Moves credits; nil is an independent party (credits enter or leave the economy)
function Actions.Pay(state: State.State, payer: number?, payee: number?, amount: number)
  if payer == payee then
    return
  end
  if payer then
    state.factions[payer].credits -= amount
  end
  if payee then
    state.factions[payee].credits += amount
  end
end

-- Takes up to 'amount' of 'good' from the owner's stations in the fleet's system
local function draw(state: State.State, fleet: State.Fleet, good: string, amount: number): number
  local system = fleet.system
  if not system or state.systems[system].owner ~= fleet.owner or amount <= 0 then
    return 0
  end
  local taken = 0
  for _, id in state.galaxy.systems[system].stations do
    local station = state.stations[id]
    local have = station.stock[good] or 0
    local k = math.min(have, amount - taken)
    if k > 0 then
      station.stock[good] = have - k
      taken += k
    end
    if taken >= amount then
      break
    end
  end
  return taken
end

-- Tops up fuel for 'hops' jumps (plus a margin) and munitions from the
-- owner's stations in the fleet's system
function Actions.Supply(state: State.State, fleet: State.Fleet, hops: number)
  local ships = State.ShipCount(fleet)
  fleet.fuel += draw(state, fleet, "fuel", ships * (hops + 2) - fleet.fuel)
  if fleet.role == "war" then
    fleet.munitions += draw(state, fleet, "munitions", 2 * ships - fleet.munitions)
  end
end

-- Starts the jump to the next system on the action's path
function Actions.Depart(state: State.State, action: State.Action, fleet: State.Fleet)
  State.Leave(state, fleet)
  local ships = State.ShipCount(fleet)
  local ticks = Data.JUMP_TICKS
  if fleet.fuel >= ships then
    fleet.fuel -= ships
  else
    ticks *= 2 -- out of fuel: slow
  end
  action.due = state.tick + ticks
  State.Schedule(state, action)
end

local function startPath(state: State.State, action: State.Action, fleet: State.Fleet, dest: number)
  action.path = Galaxy.Path(state.galaxy, fleet.system :: number, dest)
  action.step = 1
  Actions.Supply(state, fleet, #(action.path :: { number }))
  Actions.Depart(state, action, fleet)
end

-- Sends an idle fleet to 'dest'. 'intent' says what happens on arrival:
-- attack, claim, raid, hunt, intercept, reinforce, ambush, retreat, home
function Actions.Move(state: State.State, fleet: State.Fleet, dest: number, intent: string): State.Action?
  local at = fleet.system
  if at == nil or fleet.action ~= nil or at == dest then
    return nil
  end
  local action = newAction(state, fleet.owner, "move")
  action.fleet = fleet.id
  action.intent = intent
  action.target = dest
  fleet.action = action.id
  startPath(state, action, fleet, dest)
  return action
end

-- Starts a siege of the system the fleet is in; it falls to the fleet's
-- owner if the fleet still holds it when the timer completes
function Actions.Siege(state: State.State, fleet: State.Fleet): State.Action?
  local system = fleet.system
  if system == nil or fleet.action ~= nil then
    return nil
  end
  local action = newAction(state, fleet.owner, "siege")
  action.fleet = fleet.id
  action.intent = "siege"
  action.target = system
  action.due = state.tick + Data.SIEGE_TICKS
  fleet.action = action.id
  State.Schedule(state, action)
  return action
end

-- Pays to have a station of 'kind' constructed where the fleet is; it is
-- built if the fleet still holds the site when the timer completes
function Actions.Construct(state: State.State, fleet: State.Fleet, kind: string, credits: number): State.Action?
  local system = fleet.system
  local faction = state.factions[fleet.owner]
  if system == nil or fleet.action ~= nil or faction.credits < credits then
    return nil
  end
  faction.credits -= credits
  local action = newAction(state, fleet.owner, "construct")
  action.fleet = fleet.id
  action.intent = "construct"
  action.target = system
  action.structure = kind
  action.credits = credits
  action.due = state.tick + Data.CONSTRUCT_TICKS
  fleet.action = action.id
  State.Schedule(state, action)
  return action
end

---------------------------------------------------------------- Convoys

local function capacity(fleet: State.Fleet): number
  local total = 0
  for _, class in Data.Ships do
    total += (fleet.ships[class.id] or 0) * class.cargo
  end
  return total
end
Actions.Capacity = capacity

-- Unloads at the delivery station and ends the convoy
local function unload(state: State.State, action: State.Action, fleet: State.Fleet)
  local good = action.good :: string
  local station = state.stations[action.to :: number]
  local amount = fleet.cargo[good] or 0
  local price = Market.BuyPrice(station, good) or Data.GoodById[good].base * 0.5
  local system = state.systems[station.system]
  local buyer = system.owner
  local value = amount * price
  if buyer and buyer ~= fleet.owner then
    value = math.min(value, math.max(0, state.factions[buyer].credits))
  elseif buyer == nil then
    -- Independents pay from their treasury
    value = math.min(value, math.max(0, system.credits))
    system.credits -= value
    State.Count(state, "sales to independents", value)
  end
  Actions.Pay(state, buyer, fleet.owner, value)
  station.stock[good] = (station.stock[good] or 0) + amount
  fleet.cargo[good] = nil
  State.Count(state, "convoys delivered")
  State.Count(state, "goods delivered", amount)
  Actions.Finish(state, action)
end

-- Buys at the pickup station, then heads for the delivery station
local function load(state: State.State, action: State.Action, fleet: State.Fleet)
  releasePickup(state, action)
  local good = action.good :: string
  local station = state.stations[action.from :: number]
  local price = Market.SellPrice(station, good) or Data.GoodById[good].base
  local seller = state.systems[station.system].owner
  local amount = math.min(action.quantity :: number, Market.Surplus(station, good), capacity(fleet))
  if seller ~= fleet.owner then
    amount = math.min(amount, math.max(0, state.factions[fleet.owner].credits) / price)
  end
  if amount < 1 then
    State.Count(state, "convoys empty")
    Actions.Finish(state, action)
    return
  end
  Actions.Pay(state, fleet.owner, seller, amount * price)
  if seller == nil then
    state.systems[station.system].credits += amount * price
    State.Count(state, "purchases from independents", amount * price)
  end
  station.stock[good] -= amount
  fleet.cargo[good] = (fleet.cargo[good] or 0) + amount
  action.stage = "deliver"
  local dest = state.stations[action.to :: number].system
  if dest == fleet.system then
    unload(state, action, fleet)
  else
    startPath(state, action, fleet, dest)
  end
end

-- Called when a convoy reaches the end of its current leg
function Actions.ConvoyArrived(state: State.State, action: State.Action, fleet: State.Fleet)
  if action.stage == "pickup" then
    load(state, action, fleet)
  else
    unload(state, action, fleet)
  end
end

-- Sends idle haulers to buy 'quantity' of 'good' at station 'from' and sell it at station 'to'
function Actions.Convoy(state: State.State, fleet: State.Fleet, from: number, to: number, good: string,
  quantity: number): State.Action?
  if fleet.system == nil or fleet.action ~= nil then
    return nil
  end
  local action = newAction(state, fleet.owner, "convoy")
  action.fleet = fleet.id
  action.stage = "pickup"
  action.from, action.to, action.good, action.quantity = from, to, good, quantity
  action.intent = "convoy"
  action.claimed, action.expected = true, true
  State.AddPending(state, "out", from, good, quantity)
  State.AddPending(state, "in", to, good, quantity)
  fleet.action = action.id
  local pickup = state.stations[from].system
  if pickup == fleet.system then
    load(state, action, fleet)
  else
    action.target = pickup
    startPath(state, action, fleet, pickup)
  end
  return action
end

------------------------------------------------------------- Shipbuilding

-- Builds a ship at a shipyard (or pirate den, paid in credits). The
-- goods are taken from the station's stock now.
function Actions.Build(state: State.State, station: State.Station, ship: string, credits: number?): State.Action?
  local owner = state.systems[station.system].owner
  if owner == nil or station.building ~= nil or station.destroyed then
    return nil
  end
  local class = Data.ShipById[ship]
  local reserved: State.Stock = {}
  if credits then
    if state.factions[owner].credits < credits then
      return nil
    end
    state.factions[owner].credits -= credits
  else
    if state.factions[owner].credits < class.credits then
      return nil
    end
    for good, n in class.cost do
      if (station.stock[good] or 0) < n then
        return nil
      end
    end
    for good, n in class.cost do
      station.stock[good] -= n
      reserved[good] = n
    end
    state.factions[owner].credits -= class.credits
    credits = class.credits
  end
  local action = newAction(state, owner, "build")
  action.station = station.id
  action.ship = ship
  action.reserved = reserved
  action.credits = credits
  action.due = state.tick + class.buildTicks
  station.building = action.id
  State.Schedule(state, action)
  return action
end

----------------------------------------------------------------- Cancel

-- Cancels one of the owner's actions. A build is refunded and a siege
-- lifted now; a moving fleet stops at the next system it reaches.
function Actions.Cancel(state: State.State, owner: number, id: number): boolean
  local action = state.actions[id]
  if not action or action.done or action.owner ~= owner then
    return false
  end
  State.Count(state, "cancelled")
  if action.kind == "build" then
    local station = state.stations[action.station :: number]
    if state.systems[station.system].owner == owner then
      local reserved: State.Stock = action.reserved or {}
      for good, n in reserved do
        station.stock[good] = (station.stock[good] or 0) + n
      end
      if action.credits then
        state.factions[owner].credits += action.credits
      end
    end
    station.building = nil
    Actions.Finish(state, action)
  elseif action.kind == "siege" or action.kind == "construct" then
    Actions.Finish(state, action)
  else
    action.cancelled = true
  end
  return true
end

return Actions
