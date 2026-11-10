--!strict
-- What a government can order: fleets moved, ships built, laid up and
-- brought back, supplies and kits bought, a system let go.
--
-- These are the only ways a power acts on the world, whoever decides
-- for it (Strategic/Mind today; a player who rules a power later). Each
-- checks that the order can be carried out and says so if not; each
-- takes what it uses straight away. What a navy needs it buys on the
-- market of the system it is in, at that market's prices.

local Economy = require("@lt/Core/Strategic/Economy")
local Goods = require("@lt/Core/Data/Goods")
local Powers = require("@lt/Core/Data/Powers")
local Routes = require("@lt/Core/Strategic/Routes")
local World = require("@lt/Core/Strategic/World")

local Orders = {}

local FUEL = Goods.Index("fuel")
local AMMUNITION = Goods.Index("ammunition")
local MODULES = Goods.Index("modules")
local KITS = Goods.Index("construction.kits")

-- ---------------------------------------------------------------------
-- Buying

-- What 'quantity' of a class would cost a buyer at a system now, or nil
-- if it does not hold that many.
function Orders.Price(world: World.World, system: number, class: number, quantity: number): number?
  return Economy.BuyCost(world.econ, system, class, quantity)
end

-- Buy up to 'quantity' of a class at a system for a faction: as much as
-- is there and it can pay for. Returns how many it got.
function Orders.Buy(world: World.World, faction: World.Faction, system: number, class: number, quantity: number,
  reason: string): number
  local econ = world.econ
  -- (never the last of a stock: someone else lives here too)
  local wanted = math.min(quantity, econ.nodes[system].stock[class] * 0.8)
  if wanted <= 0 then
    return 0
  end
  local cost = Economy.BuyCost(econ, system, class, wanted)
  if cost and cost > math.max(0, faction.credits) then
    -- roughly what it can afford; prices rise as it buys, so a little under
    wanted *= math.max(0, faction.credits) / cost * 0.95
    cost = if wanted > 0 then Economy.BuyCost(econ, system, class, wanted) else nil
  end
  if not cost or wanted <= 0 or cost > math.max(0, faction.credits) then
    return 0
  end
  Economy.Buy(econ, system, class, wanted)
  World.Pay(world, faction.id, 0, cost, reason)
  return wanted
end

-- What a fleet holds when full.
function Orders.SupplyRoom(fleet: World.Fleet): number
  return World.SupplyRate(fleet) * Powers.SUPPLY_HOURS
end

-- Fill a fleet's supplies from the market where it is. Only in its own
-- space: nobody sells fuel to a foreign navy. Returns what it took on.
function Orders.Provision(world: World.World, fleet: World.Fleet): number
  local system = fleet.system
  if system == 0 or world.systems[system].owner ~= fleet.owner then
    return 0
  end
  local faction = world.factions[fleet.owner]
  local short = Orders.SupplyRoom(fleet) - fleet.supply
  if short <= 0 then
    return 0
  end
  -- A unit of supply is so much fuel and so much ammunition: it gets
  -- whichever fraction both can be had for.
  local fuel = Orders.Buy(world, faction, system, FUEL, short * Powers.SUPPLY_FUEL, "supply")
  local got = fuel / Powers.SUPPLY_FUEL
  local ammunition = Orders.Buy(world, faction, system, AMMUNITION, got * Powers.SUPPLY_AMMUNITION, "supply")
  got = math.min(got, ammunition / Powers.SUPPLY_AMMUNITION)
  fleet.supply += got
  return got
end

-- Buy construction kits for a fleet, where it is, in its own space.
function Orders.BuyKits(world: World.World, fleet: World.Fleet, kits: number): number
  local system = fleet.system
  if system == 0 or world.systems[system].owner ~= fleet.owner or kits <= 0 then
    return 0
  end
  local got = Orders.Buy(world, world.factions[fleet.owner], system, KITS, kits, "construction kits")
  fleet.kits += got
  return got
end

-- The kits it takes to bring a system in.
function Orders.ClaimKits(world: World.World, system: number): number
  return Powers.CLAIM_KITS + Powers.CLAIM_KITS_PER_HEAD * world.atlas.systems[system].population
end

-- ---------------------------------------------------------------------
-- Moving

local function depart(world: World.World, action: World.Action, fleet: World.Fleet)
  World.Leave(world, fleet)
  action.due = world.tick + Powers.JUMP_TICKS
  World.Schedule(world, action)
end

-- Send a fleet to a system, to do 'task' about 'target' when it gets
-- there (the destination itself unless given). The fleet must be in a
-- system and not already under way. It fills its supplies first.
function Orders.Move(world: World.World, fleet: World.Fleet, dest: number, task: string, target: number?): boolean
  if fleet.system == 0 or fleet.action ~= 0 then
    return false
  end
  fleet.task = task
  fleet.target = target or dest
  fleet.since = world.tick
  if fleet.system == dest then
    return true
  end
  Orders.Provision(world, fleet)
  local action: World.Action = {
    id = World.NewId(world), owner = fleet.owner, kind = "move", due = world.tick,
    fleet = fleet.id, dest = dest, cancelled = false, ship = 0, count = 0, system = 0, paid = 0,
  }
  world.actions[action.id] = action
  table.insert(world.actionIds, action.id)
  fleet.action = action.id
  World.Count(world, "moves")
  depart(world, action, fleet)
  return true
end

-- A move's timer has run out: the fleet arrives in the next system on
-- its way. Returns true if that is the end of its journey (because it
-- is where it was going, was told to stop, or met an enemy fleet).
function Orders.Jumped(world: World.World, action: World.Action): boolean
  local fleet = world.fleets[action.fleet]
  if fleet == nil then
    World.EndAction(world, action)
    return false
  end
  local routes = Routes.For(world.galaxy)
  local at = routes.next[fleet.last][action.dest]
  World.Arrive(world, fleet, at)
  local stopped = at == action.dest or action.cancelled
  if not stopped and fleet.task ~= "retreat" then
    -- Nobody slips past an enemy fleet of any size.
    local own, facing = World.Strength(fleet), 0
    for _, id in world.systems[at].fleets do
      local other = world.fleets[id]
      if World.Hostile(world, fleet.owner, other.owner) then
        facing += World.Strength(other)
      end
    end
    stopped = facing >= 0.25 * own
  end
  if stopped then
    World.EndAction(world, action)
    return true
  end
  depart(world, action, fleet)
  return false
end

-- Stop a fleet at the next system it reaches. (An order like any other:
-- the fleet is not free until it gets there.)
function Orders.Halt(world: World.World, fleet: World.Fleet): boolean
  local action = if fleet.action > 0 then world.actions[fleet.action] else nil
  if action == nil or action.cancelled then
    return false
  end
  action.cancelled = true
  World.Count(world, "moves cancelled")
  return true
end

-- Pull a beaten fleet out: one jump, to its own space if it can, else
-- back the way it came, else anywhere no enemy fleet waits. False if
-- there is nowhere to go.
function Orders.Retreat(world: World.World, fleet: World.Fleet): boolean
  local at = fleet.system
  if at == 0 or fleet.action ~= 0 then
    return false
  end
  local function clear(system: number): boolean
    for _, id in world.systems[system].fleets do
      if World.Hostile(world, fleet.owner, world.fleets[id].owner) then
        return false
      end
    end
    return true
  end
  local neighbors = world.galaxy.systems[at].neighbors
  local pick = 0
  for _, n in neighbors do
    if pick == 0 and world.systems[n].owner == fleet.owner and clear(n) then
      pick = n
    end
  end
  if pick == 0 and fleet.last ~= at and fleet.last > 0 and table.find(neighbors, fleet.last) and clear(fleet.last) then
    pick = fleet.last
  end
  for _, n in neighbors do
    if pick == 0 and clear(n) then
      pick = n
    end
  end
  if pick == 0 then
    return false
  end
  return Orders.Move(world, fleet, pick, "retreat")
end

-- ---------------------------------------------------------------------
-- Ships

-- What building one ship of a class at a system would cost now, or nil
-- if its market cannot supply one.
function Orders.ShipPrice(world: World.World, system: number, class: number): number?
  local ship = Powers.ships[class]
  local hull = Economy.BuyCost(world.econ, system, Goods.Index(ship.hull), 1)
  local modules = Economy.BuyCost(world.econ, system, MODULES, ship.modules)
  return if hull and modules then hull + modules else nil
end

-- How many ships a faction has on the slips.
function Orders.Building(world: World.World, faction: number): number
  local n = 0
  for _, id in world.actionIds do
    local action = world.actions[id]
    if action.owner == faction and action.kind == "build" then
      n += 1
    end
  end
  return n
end

-- Lay a ship down at the capital's yard: the hull and its fittings are
-- bought there now, and it joins the fleet when it is done.
function Orders.Build(world: World.World, faction: World.Faction, class: number): (boolean, string?)
  local system = faction.capital
  if system == 0 or world.systems[system].owner ~= faction.id then
    return false, "no yard"
  end
  if world.systems[system].siege ~= nil then
    return false, "the yard is under siege"
  end
  if Orders.Building(world, faction.id) >= Powers.YARD_SLOTS then
    return false, "every slip is in use"
  end
  local price = Orders.ShipPrice(world, system, class)
  if price == nil then
    return false, "the market cannot supply one"
  end
  if price > faction.credits then
    return false, "not enough credits"
  end
  local ship = Powers.ships[class]
  local econ = world.econ
  local cost = (Economy.Buy(econ, system, Goods.Index(ship.hull), 1) :: number)
    + (Economy.Buy(econ, system, MODULES, ship.modules) :: number)
  World.Pay(world, faction.id, 0, cost, "shipbuilding")
  local action = World.NewAction(world, faction.id, "build", world.tick + ship.buildTicks)
  action.ship, action.count, action.system, action.paid = class, 1, system, cost
  World.Count(world, `laid down: {ship.id}`)
  return true, nil
end

-- A build or a reactivation is done: the ships join the fleet waiting at
-- the capital, or make a new one.
function Orders.Launched(world: World.World, action: World.Action)
  World.EndAction(world, action)
  local faction = world.factions[action.owner]
  local system = faction.capital
  if not faction.alive or system == 0 then
    return
  end
  local ships: { number } = table.create(#Powers.ships, 0)
  ships[action.ship] = action.count
  local fleet = World.NewFleet(world, faction.id, system, ships)
  for _, id in world.systems[system].fleets do
    local other = world.fleets[id]
    if other.id ~= fleet.id and other.owner == faction.id and other.action == 0 and other.task == "" then
      World.Merge(world, other, fleet)
      break
    end
  end
  World.Count(world, `launched: {Powers.ships[action.ship].id}`, action.count)
end

-- Lay ships up: they leave the fleet and cost little until brought
-- back. The fleet must be idle in its own space.
function Orders.Mothball(world: World.World, fleet: World.Fleet, ships: { number }): boolean
  if fleet.system == 0 or fleet.action ~= 0 or world.systems[fleet.system].owner ~= fleet.owner then
    return false
  end
  local faction = world.factions[fleet.owner]
  local before = World.SupplyRate(fleet)
  local moved = 0
  for class in Powers.ships do
    local k = math.min(ships[class] or 0, fleet.ships[class])
    fleet.ships[class] -= k
    faction.reserve[class] += k
    moved += k
  end
  if moved == 0 then
    return false
  end
  World.Count(world, "ships laid up", moved)
  if World.Ships(fleet) == 0 then
    World.Disband(world, fleet)
  elseif before > 0 then
    fleet.supply *= World.SupplyRate(fleet) / before
  end
  return true
end

-- Bring laid-up ships of a class back: a share of their price now, and
-- they are at the capital after a while.
function Orders.Reactivate(world: World.World, faction: World.Faction, class: number, count: number): boolean
  local n = math.min(count, faction.reserve[class])
  if n <= 0 or faction.capital == 0 then
    return false
  end
  local ship = Powers.ships[class]
  local econ = world.econ
  local par = econ.classes[Goods.Index(ship.hull)].par + ship.modules * econ.classes[MODULES].par
  local fee = n * par * Powers.REACTIVATE_SHARE
  if fee > faction.credits then
    return false
  end
  World.Pay(world, faction.id, 0, fee, "reactivation")
  faction.reserve[class] -= n
  local action = World.NewAction(world, faction.id, "reactivate", world.tick + Powers.REACTIVATE_TICKS)
  action.ship, action.count, action.system, action.paid = class, n, faction.capital, fee
  World.Count(world, "ships brought back", n)
  return true
end

-- ---------------------------------------------------------------------
-- Territory

function Orders.SetPolicing(world: World.World, faction: World.Faction, level: number)
  faction.policing = math.clamp(level, 0, 1)
end

-- Give a system up. Not the capital.
function Orders.Release(world: World.World, faction: World.Faction, system: number): boolean
  if world.systems[system].owner ~= faction.id or system == faction.capital then
    return false
  end
  World.Transfer(world, system, 0)
  World.Count(world, "systems given up")
  World.Log(world, "release", `{faction.name} withdraws from {World.SystemName(world, system)}`, system, faction.id)
  return true
end

return Orders
