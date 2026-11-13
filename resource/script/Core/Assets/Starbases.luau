--!strict
-- Starbases a pilot puts up: a control tower anchored at a moon, fed
-- with fuel, with modules anchored round it (Data/Structures).
--
-- A pilot's tower is a station like any other. Anchoring one adds a
-- station to its system's description, so it is on the overview, can be
-- warped to and moored at, keeps a hangar, and gives the services its
-- modules give (Assets/Stations), by all the code that already knows
-- stations. What it has that a described station has not is kept here:
-- whose it is, its fuel, and its modules one by one.
--
-- The rules:
--   - A tower is anchored from a ship's hold, beside a moon that has no
--     tower yet. It takes a while (longer the bigger), and until it is
--     done nobody can moor there. A pilot keeps one tower, and one
--     more for each level of Anchoring.
--   - It burns fuel blocks by the hour while it has any. With none it
--     is dark: its field is down and none of its modules gives
--     anything. Fuel is put in by a ship moored there, and it lights
--     again at once. And a tower that has burnt its last feeds itself
--     from whatever fuel is in its own hangar, a day's worth at a time:
--     so fuel brought there by anybody keeps it lit.
--   - A module is anchored by a ship moored there, from its hold or the
--     tower's hangar, if the tower is lit and has the powergrid and CPU
--     for it besides what it already carries. It takes a while to come
--     online. It can be unanchored again, into the hangar.
--   - A moon may have a deposit (Data/Moons), and a tower with a drill
--     online works it: every hour the tower is lit, an hour's worth of
--     the moon's material is put in the tower's hangar. The tower holds
--     only so much of it (a silo's worth, and more for each storage
--     array online); with no room for more the drill stands idle until
--     some is taken away. One drill to a tower, and none at a moon with
--     nothing under it.
--   - A tower with a reactor online makes a composite of the two moon
--     materials of a grade (Data/Reactions): every hour the tower is
--     lit, a batch of each out of the tower's hangars and a batch of
--     the composite into them. Which composite is the owner's to set
--     (SetReaction), moored there. With too little of either material
--     the reactor stands idle until there is more. One reactor to a
--     tower.
--
-- Pirates come for a tower where order is thin (Tactical/Raids), and
-- its batteries fire on them (Tactical/Batteries).
--
-- A tower keeps count of its running since it was anchored: the fuel
-- it has burnt, what its drill has brought up, and what raiders have
-- carried off. Starbases.Running puts a price on each, and says what a
-- day of it costs and brings: what the pilot's books show of it
-- (Assets/Corporation).
--
-- Not yet: taking a tower down, more than one owner.

local Constants = require("@lt/Core/Data/Constants")
local Corporation = require("@lt/Core/Assets/Corporation")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Moons = require("@lt/Core/Data/Moons")
local Reactions = require("@lt/Core/Data/Reactions")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local System = require("@lt/Core/Describe/System")
local Types = require("@lt/Core/Data/Types")

local Starbases = {}

export type Event = { [string]: any }

-- How near a moon (in its own radii, from its middle) a tower has to be
-- anchored: where a ship that has warped to the moon arrives.
Starbases.REACH = 5

-- How many towers a pilot keeps with no Anchoring at all; each level of
-- it is one more.
Starbases.FIRST = 1

-- How many towers an owner has, and how many the pilot can keep.
function Starbases.Kept(state: State.State, owner: string): (number, number)
  local have = 0
  for _, id in state.starbaseIds do
    have += if state.starbases[id].owner == owner then 1 else 0
  end
  return have, Starbases.FIRST + math.max(0, state.skills.anchoring or 0)
end

-- Ticks between one fuel block and the next, for a tower.
local function interval(tower: Structures.Tower): number
  return math.floor(3600 / Constants.TICK / tower.fuel + 0.5)
end

-- The ticks a number of seconds takes.
local function ticks(seconds: number): number
  return math.ceil(seconds / Constants.TICK)
end

-- Whether a starbase's tower has finished anchoring.
function Starbases.Anchored(state: State.State, starbase: State.Starbase): boolean
  return state.tick >= starbase.ready
end

-- Whether a starbase has sealed itself (Tactical/Raids): nothing can
-- touch it, and it does nothing, until the tick it opens.
function Starbases.Sealed(state: State.State, starbase: State.Starbase): boolean
  return starbase.sealed ~= 0 and state.tick < starbase.sealed
end

-- Whether a starbase is lit: anchored, with fuel aboard, and not sealed
-- (a sealed tower gives nothing, drills nothing, fires at nobody, and
-- burns nothing).
function Starbases.Lit(state: State.State, starbase: State.Starbase): boolean
  return state.tick >= starbase.ready and starbase.fuel > 0 and not Starbases.Sealed(state, starbase)
end

-- The starbase a ship stands for where it is shot at, if it is one's core.
function Starbases.OfCore(state: State.State, ship: number): State.Starbase?
  for _, id in state.starbaseIds do
    if state.starbases[id].core == ship then
      return state.starbases[id]
    end
  end
  return nil
end

-- How much of a tower's shield, armour and structure is left, each 0 to
-- 1 (1, 1, 1 for one not yet anchored, which has nothing to shoot at).
function Starbases.Health(state: State.State, starbase: State.Starbase): (number, number, number)
  local ball = state.balls[starbase.core]
  if ball == nil then
    return 1, 1, 1
  end
  local vitals = ball.vitals
  return vitals.shield / math.max(1, vitals.shieldMax), vitals.armor / math.max(1, vitals.armorMax), vitals.hull / math.max(1, vitals.hullMax)
end

-- The powergrid and CPU a starbase's modules draw between them.
function Starbases.Draw(starbase: State.Starbase): (number, number)
  local powergrid, cpu = 0, 0
  for _, module in starbase.modules do
    local type = Structures.moduleById[module.type]
    powergrid += type.powergrid
    cpu += type.cpu
  end
  return powergrid, cpu
end

-- What a moon has under it (Data/Moons), by the moon's id: nil for one
-- with nothing, and for what is no moon.
function Starbases.Deposit(state: State.State, moon: number): Moons.Deposit?
  local object = Space.Object(state, moon)
  if object == nil or object.kind ~= "moon" then
    return nil
  end
  return Moons.Deposit(object.seed, Galaxy.Band(state.galaxy.systems[Space.SystemOf(state, moon)].security))
end

-- The moon a starbase is anchored at, by its id (0 if it is not said).
function Starbases.Moon(state: State.State, starbase: State.Starbase): number
  local object = Space.Object(state, starbase.id)
  return if object then object.parent else 0
end

-- How many of a kind of module a starbase has online.
local function online(state: State.State, starbase: State.Starbase, type: string): number
  local count = 0
  if Starbases.Lit(state, starbase) then
    for _, module in starbase.modules do
      if module.type == type and state.tick >= module.ready then
        count += 1
      end
    end
  end
  return count
end

-- How a starbase's drilling stands: what is under its moon (nil: no
-- deposit), whether a drill is anchored and whether it is online, the
-- units an hour it brings up, how many units of the material are in
-- the tower's hangar, and how many the tower holds before the drill
-- stops.
export type Drilling = { deposit: Moons.Deposit?, anchored: boolean, online: boolean, perHour: number, stored: number, room: number }
function Starbases.Drilling(state: State.State, starbase: State.Starbase): Drilling
  local deposit = Starbases.Deposit(state, Starbases.Moon(state, starbase))
  local anchored = false
  for _, module in starbase.modules do
    anchored = anchored or module.type == Structures.DRILL
  end
  local stored = 0
  if deposit then
    -- (in the pilot's hangar there or the corporation's: the one silo)
    for _, item in Items.Stored(state, starbase.id) do
      if item.type == deposit.material.id then
        stored += item.quantity
      end
    end
  end
  return {
    deposit = deposit, anchored = anchored, online = online(state, starbase, Structures.DRILL) > 0,
    perHour = if deposit then Moons.PerHour(deposit) else 0, stored = stored,
    room = Moons.SILO + Moons.STORAGE * online(state, starbase, Structures.STORAGE),
  }
end

-- How a starbase's reactor stands: whether one is anchored and whether
-- it is online, what it is set to make (nil: nothing), how many units
-- of each thing that is made of are in the tower's hangars (in the
-- order of the composite's 'from'), and whether it stood idle last for
-- want of them.
export type Reacting = { anchored: boolean, online: boolean, making: Reactions.Composite?, have: { number }, starved: boolean }
function Starbases.Reacting(state: State.State, starbase: State.Starbase): Reacting
  local anchored = false
  for _, module in starbase.modules do
    anchored = anchored or module.type == Structures.REACTOR
  end
  local making = Reactions.byId[starbase.reaction]
  local have: { number } = {}
  if making then
    for index, from in making.from do
      have[index] = 0
      -- (in the pilot's hangar there or the corporation's)
      for _, item in Items.Stored(state, starbase.id) do
        if item.type == from then
          have[index] += item.quantity
        end
      end
    end
  end
  return { anchored = anchored, online = online(state, starbase, Structures.REACTOR) > 0, making = making, have = have,
    starved = starbase.starved }
end

-- Whether a starbase has a module online that gives a service.
function Starbases.Has(state: State.State, starbase: State.Starbase, service: Structures.Service): boolean
  if not Starbases.Lit(state, starbase) then
    return false
  end
  for _, module in starbase.modules do
    if state.tick >= module.ready and Structures.moduleById[module.type].service == service then
      return true
    end
  end
  return false
end

-- What stands there: the tower and every module anchored round it,
-- online or not, the larger first.
function Starbases.Makeup(starbase: State.Starbase): Structures.Makeup
  local modules: { string } = {}
  for _, module in starbase.modules do
    table.insert(modules, module.type)
  end
  table.sort(modules, function(a: string, b: string): boolean
    local ra, rb = Structures.moduleById[a].radius, Structures.moduleById[b].radius
    if ra ~= rb then
      return ra > rb
    end
    return a < b
  end)
  return { tower = starbase.tower, modules = modules }
end

-- The hours of fuel a starbase has left.
function Starbases.Hours(starbase: State.Starbase): number
  return starbase.fuel / Structures.towerById[starbase.tower].fuel
end

-- The moon a command names, if it is one.
local function moonOf(state: State.State, command: State.Command): System.Object?
  local object = Space.Object(state, command.target or 0)
  return if object and object.kind == "moon" then object else nil
end

-- The starbase the ship giving a command is moored at, if it is its
-- owner's.
local function mooredAt(state: State.State, command: State.Command): State.Starbase?
  local ship = state.ships[command.actor]
  local starbase = if ship and ship.docked ~= 0 then state.starbases[ship.docked] else nil
  return if starbase and ship and starbase.owner == ship.owner then starbase else nil
end

-- An item a moored ship may use: in its own hold, or in the hangar of
-- the station it is moored at (the pilot's own, or their corporation's).
local function toHand(state: State.State, command: State.Command): State.Item?
  local ship = state.ships[command.actor]
  local item = state.items[command.item or 0]
  if ship == nil or item == nil or item.slot ~= 0 then
    return nil
  end
  if (item.holder == ship.id and item.place == "cargo")
    or (ship.docked ~= 0 and item.holder == ship.docked and Items.IsStore(item.place)) then
    return item
  end
  return nil
end

function Starbases.Validate(state: State.State, command: State.Command): (boolean, string?)
  local ship = state.ships[command.actor]
  if ship == nil then
    return false, "no such ship"
  end
  local kind = command.kind
  if kind == "AnchorTower" then
    local ball = state.balls[ship.id]
    if ball == nil then
      return false, "docked"
    elseif ball.warp and ball.warp.stage == "warp" then
      return false, "in warp"
    end
    local item = state.items[command.item or 0]
    if item == nil or item.holder ~= ship.id or item.place ~= "cargo" or Structures.towerById[item.type] == nil then
      return false, "no control tower in the hold"
    end
    local moon = moonOf(state, command)
    if moon == nil or Space.SystemOf(state, moon.id) ~= ball.system then
      return false, "a tower is anchored at a moon"
    end
    -- (not at one the pirates hold with a tower of their own, from
    -- however near: Tactical/Keeps)
    for _, keepId in state.keepIds do
      if state.keeps[keepId].moon == moon.id then
        return false, "pirates hold that moon: bring their tower down first"
      end
    end
    if Space.Distance(ball :: any, moon :: any) > moon.radius * Starbases.REACH then
      return false, "too far from the moon"
    end
    for _, object in Space.Describe(state, ball.system).objects do
      if object.kind == "station" and object.parent == moon.id and state.starbases[object.id] then
        return false, "that moon has a tower already"
      end
    end
    local have, most = Starbases.Kept(state, ship.owner)
    if have >= most then
      return false, if most == 1 then "you keep one tower: each level of Anchoring is one more"
        else `you keep {most} towers: each level of Anchoring is one more`
    end
    return true
  end

  local starbase = mooredAt(state, command)
  if starbase == nil then
    return false, "not moored at a starbase of your own"
  end
  local tower = Structures.towerById[starbase.tower]
  if kind == "Fuel" then
    local item = toHand(state, command)
    if item == nil or (item.type ~= Structures.FUEL.id and item.type ~= Structures.SEAL.id) then
      return false, "no fuel to hand"
    end
    local quantity = command.quantity or item.quantity
    if item.type == Structures.SEAL.id then
      -- (sealing charges: as many as its bay has room for, if no number is said)
      local room = tower.bay - starbase.charges
      quantity = command.quantity or math.min(item.quantity, room)
      if room <= 0 then
        return false, `its bay holds {tower.bay} sealing charges, and is full`
      elseif quantity > room then
        return false, `its bay has room for {room} more`
      end
    end
    if quantity < 1 or quantity > item.quantity or quantity % 1 ~= 0 then
      return false, "not that many"
    end
    return true
  elseif kind == "AnchorModule" then
    local item = toHand(state, command)
    local module = if item then Structures.moduleById[item.type] else nil
    if module == nil then
      return false, "no structure module to hand"
    elseif not module.pilot then
      return false, `a pilot cannot anchor a {module.name}`
    elseif not Starbases.Lit(state, starbase) then
      return false, "the tower is dark"
    end
    local powergrid, cpu = Starbases.Draw(starbase)
    if powergrid + module.powergrid > tower.powergrid then
      return false, "the tower has not the powergrid"
    elseif cpu + module.cpu > tower.cpu then
      return false, "the tower has not the CPU"
    end
    if module.id == Structures.DRILL then
      -- (one drill to a moon, and none where there is nothing to drill for)
      local drilling = Starbases.Drilling(state, starbase)
      if drilling.anchored then
        return false, "the tower has a drill already"
      elseif drilling.deposit == nil then
        return false, "this moon has nothing worth a drill"
      end
    elseif module.id == Structures.REACTOR and Starbases.Reacting(state, starbase).anchored then
      -- (and one reactor to a tower)
      return false, "the tower has a reactor already"
    end
    return true
  elseif kind == "SetReaction" then
    -- What the tower's reactor makes: a composite ('type'), or nothing ("").
    local what = command.type or ""
    if not Starbases.Reacting(state, starbase).anchored then
      return false, "no reactor is anchored here"
    elseif what ~= "" and Reactions.byId[what] == nil then
      return false, "a reactor makes no such thing"
    elseif what == starbase.reaction then
      return false, if what == "" then "the reactor is making nothing" else "the reactor is making that already"
    end
    return true
  elseif kind == "UnanchorModule" then
    for _, module in starbase.modules do
      if module.type == command.type then
        return true
      end
    end
    return false, "no such module is anchored here"
  elseif kind == "UnanchorTower" then
    -- Taken down with nothing on it and nothing in it, by the one ship
    -- moored there, into that ship's hold.
    if #starbase.modules > 0 then
      return false, "unanchor its modules first"
    elseif #Items.Stored(state, starbase.id) > 0 then
      return false, "its hangars are not empty"
    end
    for _, id in state.shipIds do
      local other = state.ships[id]
      if other.id ~= ship.id and other.docked == starbase.id then
        return false, "another ship is moored here"
      end
    end
    for _, id in state.jobIds do
      if state.jobs[id].station == starbase.id then
        return false, "a job is running here"
      end
    end
    local free = Items.ShipStats(state, ship.id).cargo - Items.CargoUsed(state, ship.id)
    if tower.volume > free + 1e-9 then
      return false, string.format("the tower wants %d m3 of hold, and this ship has %d free", tower.volume, math.floor(free))
    end
    return true
  end
  return false, `unknown command '{kind}'`
end

-- Put a tower up at a moon, at a place: it is a station in the
-- system's description from now on, and anchoring. Its station's id.
function Starbases.Raise(state: State.State, system: number, moon: System.Object, tower: Structures.Tower, owner: string,
  x: number, y: number, z: number): number
  local description = Space.Describe(state, system)
  local id = system * Constants.STRUCTURE_ID_SPAN + #description.objects + 1
  assert(#description.objects + 1 < Constants.STRUCTURE_ID_SPAN, "a system has outgrown its id range")
  table.insert(description.objects, {
    id = id, kind = "station", name = `{moon.name} - Starbase`, x = x, y = y, z = z,
    radius = tower.field, seed = (state.tick * 7919 + id) % 100000, parent = moon.id, site = id, variety = "starbase", to = 0,
  })
  state.starbases[id] = { id = id, tower = tower.id, owner = owner, ready = state.tick + ticks(tower.anchor), fuel = 0,
    burnt = state.tick, modules = {}, drilled = state.tick, raid = 0, raids = 0, used = 0, raised = 0, robbed = 0,
    core = 0, charges = 0, sealed = 0, siege = 0, reaction = "", reacted = state.tick, composed = 0, starved = false }
  State.InsertId(state.starbaseIds, id)
  return id
end

-- A starbase is no more: taken down, or brought down. Whoever of the
-- hired pilots was posted there, or based there, or collected there or
-- carried there, is not any more: they wait where they are, and are
-- the home station's from now on. The thing that stood for it under
-- fire goes with it. Its place in the system's list is kept (an
-- object's place there is its id), and is nothing: no station, no
-- body, no grid's middle; whoever was on its grid is in open space,
-- and whatever wrecks lay there lie there still.
function Starbases.Remove(state: State.State, id: number, events: { Event })
  local starbase = state.starbases[id]
  if starbase == nil then
    return
  end
  for _, wingId in state.fleetIds do
    local wing = state.fleet[wingId]
    local at = table.find(wing.stops, id)
    if wing.base == id or wing.post == id or at or table.find(wing.drops, id) then
      wing.order = "stay"
      wing.base = if wing.base == id then state.player.home else wing.base
      wing.post = if wing.post == id then 0 else wing.post
      while at do
        table.remove(wing.stops, at)
        at = table.find(wing.stops, id)
      end
      wing.leg = 0
      wing.drops, wing.turn = {}, 0
      table.insert(events, { kind = "FleetUnposted", pilot = wing.id, name = wing.name, station = id })
    end
  end
  local core = state.ships[starbase.core]
  if core then
    local ball = state.balls[core.id]
    if ball then
      Space.RemoveBall(state, ball)
      table.insert(events, { kind = "BallRemoved", ball = core.id, reason = "left" })
    end
    state.ships[core.id] = nil
    State.RemoveId(state.shipIds, core.id)
  end
  state.starbases[id] = nil
  State.RemoveId(state.starbaseIds, id)
  state.spawned[id] = nil
  local object = Space.Object(state, id)
  if object then
    object.kind, object.site, object.parent, object.variety, object.radius, object.to = "gone", 0, 0, "", 0, 0
    local open = 0
    for _, ballId in state.ballIds do
      local ball = state.balls[ballId]
      if ball.grid == id then
        Space.AssignGrid(state, ball)
        open = ball.grid
      end
    end
    for _, wreckId in state.wreckIds do
      local wreck = state.wrecks[wreckId]
      if wreck.grid == id then
        wreck.grid = open
      end
    end
  end
end

function Starbases.Apply(state: State.State, command: State.Command, events: { Event })
  local ship = state.ships[command.actor]
  local kind = command.kind
  if kind == "AnchorTower" then
    local ball = state.balls[ship.id]
    local item = state.items[command.item :: number]
    local tower = Structures.towerById[item.type]
    local moon = moonOf(state, command) :: System.Object
    Items.Take(state, item, 1)
    -- (a kilometre or so off the ship that put it there, which is then
    -- inside its field)
    local id = Starbases.Raise(state, ball.system, moon, tower, ship.owner, ball.x + 1200, ball.y, ball.z)
    -- (the ships about are on its grid now, not out in open space)
    for _, other in state.ballIds do
      local near = state.balls[other]
      if near.system == ball.system and not (near.warp and near.warp.stage == "warp") then
        Space.AssignGrid(state, near)
      end
    end
    table.insert(events, { kind = "StarbaseAnchored", station = id, system = ball.system, by = ship.id })
    return
  end

  local starbase = mooredAt(state, command) :: State.Starbase
  if kind == "Fuel" then
    local item = toHand(state, command) :: State.Item
    if item.type == Structures.SEAL.id then
      local quantity = command.quantity or math.min(item.quantity, Structures.towerById[starbase.tower].bay - starbase.charges)
      Items.Take(state, item, quantity)
      starbase.charges += quantity
      table.insert(events, { kind = "StarbaseCharged", station = starbase.id, charges = starbase.charges })
      return
    end
    local quantity = command.quantity or item.quantity
    Items.Take(state, item, quantity)
    if starbase.fuel == 0 then
      starbase.burnt = state.tick
    end
    starbase.fuel += quantity
    table.insert(events, { kind = "StarbaseFuelled", station = starbase.id, fuel = starbase.fuel })
  elseif kind == "AnchorModule" then
    local item = toHand(state, command) :: State.Item
    local module = Structures.moduleById[item.type]
    Items.Take(state, item, 1)
    table.insert(starbase.modules, { type = module.id, ready = state.tick + ticks(module.anchor) })
    table.insert(events, { kind = "ModuleAnchored", station = starbase.id, module = module.id })
  elseif kind == "SetReaction" then
    starbase.reaction, starbase.reacted, starbase.starved = command.type or "", state.tick, false
    table.insert(events, { kind = "ReactionSet", station = starbase.id, type = starbase.reaction })
  elseif kind == "UnanchorModule" then
    for index = #starbase.modules, 1, -1 do
      if starbase.modules[index].type == command.type then
        table.remove(starbase.modules, index)
        if command.type == Structures.REACTOR then
          -- (a reactor taken down is making nothing when it goes up again)
          starbase.reaction, starbase.starved = "", false
        end
        Items.Add(state, command.type :: string, 1, starbase.id, "hangar")
        table.insert(events, { kind = "ModuleUnanchored", station = starbase.id, module = command.type })
        break
      end
    end
  elseif kind == "UnanchorTower" then
    local tower = Structures.towerById[starbase.tower]
    local id = starbase.id
    -- Out of its moorings first, while there are moorings to leave.
    Space.Apply(state, { kind = "Undock", actor = ship.id }, events)
    Items.Add(state, tower.id, 1, ship.id, "cargo")
    -- (what fuel is in its tank comes too, as far as there is room for it)
    local free = Items.ShipStats(state, ship.id).cargo - Items.CargoUsed(state, ship.id)
    local each = Types.Info(Structures.FUEL.id).volume
    local kept = math.min(starbase.fuel, if each > 0 then math.max(0, math.floor((free + 1e-9) / each)) else starbase.fuel)
    if kept > 0 then
      Items.Add(state, Structures.FUEL.id, kept, ship.id, "cargo")
    end
    local object = Space.Object(state, id)
    local name = if object then object.name else "the tower"
    local left = starbase.fuel - kept
    -- (what sealing charges are aboard come too, as the fuel does)
    local room = Items.ShipStats(state, ship.id).cargo - Items.CargoUsed(state, ship.id)
    local charges = math.min(starbase.charges, math.max(0, math.floor((room + 1e-9) / Structures.SEAL.volume)))
    if charges > 0 then
      Items.Add(state, Structures.SEAL.id, charges, ship.id, "cargo")
    end
    Starbases.Remove(state, id, events)
    table.insert(events, { kind = "TowerUnanchored", station = id, name = name, tower = tower.id, fuel = kept, left = left })
  end
end

-- Once a tick: every lit tower burns its fuel, a block at a time, and
-- one that burns its last goes dark. And a lit tower with a drill
-- online brings up an hour's worth of its moon, every hour, while it
-- has the room.
local HOUR = math.floor(3600 / Constants.TICK + 0.5)

-- How a tower's running stands, in units and in what they are worth at
-- the price such things are listed at (no market's: a tower is far from
-- one): the fuel burnt since it was anchored, what the drill has
-- brought up and what raiders have carried off; and what a day of it
-- costs in fuel and brings up, as it is fitted now (nothing, dark).
export type Running = {
  used: number, usedWorth: number, raised: number, raisedWorth: number, robbed: number, robbedWorth: number,
  material: string,       -- what is under its moon ("" for nothing)
  fuelADay: number,       -- credits' worth of fuel burnt in a day
  yieldADay: number,      -- credits' worth brought up in a day
}
function Starbases.Running(state: State.State, starbase: State.Starbase): Running
  local fuel = Structures.FUEL.basePrice
  local drilling = Starbases.Drilling(state, starbase)
  local deposit = drilling.deposit
  local price = if deposit then deposit.material.basePrice else 0
  local lit = Starbases.Lit(state, starbase)
  return {
    used = starbase.used, usedWorth = starbase.used * fuel,
    raised = starbase.raised, raisedWorth = starbase.raised * price,
    robbed = starbase.robbed, robbedWorth = starbase.robbed * price,
    material = if deposit then deposit.material.id else "",
    fuelADay = if lit then Structures.towerById[starbase.tower].fuel * 24 * fuel else 0,
    yieldADay = if lit and drilling.online then drilling.perHour * 24 * price else 0,
  }
end

-- A tower with nothing in its tank takes what fuel is in its own
-- hangar, a day's worth at a time (the corporation's fuel before the
-- pilot's own).
local function feed(state: State.State, starbase: State.Starbase, events: { Event })
  if starbase.fuel > 0 or not Starbases.Anchored(state, starbase) then
    return
  end
  local fuel = Items.In(state, starbase.id, "corporate")
  for _, item in Items.In(state, starbase.id, "hangar") do
    table.insert(fuel, item)
  end
  for _, item in fuel do
    if item.type == Structures.FUEL.id and starbase.fuel == 0 then
      local take = math.min(item.quantity, Structures.towerById[starbase.tower].fuel * 24)
      Items.Take(state, item, take)
      starbase.fuel, starbase.burnt = take, state.tick
      table.insert(events, { kind = "StarbaseFuelled", station = starbase.id, fuel = take, hangar = true })
    end
  end
end

-- A reactor's hour is up: a batch of the composite it is set to make,
-- of a batch of each thing that is made of, out of the tower's hangars
-- (the corporation's before the pilot's own) and into them. With too
-- little of either it stands idle, and says so the first time.
local function react(state: State.State, starbase: State.Starbase, events: { Event })
  local making = Reactions.byId[starbase.reaction]
  if making == nil then
    return
  end
  local stored = Items.In(state, starbase.id, "corporate")
  for _, item in Items.In(state, starbase.id, "hangar") do
    table.insert(stored, item)
  end
  for _, from in making.from do
    local have = 0
    for _, item in stored do
      have += if item.type == from then item.quantity else 0
    end
    if have < Reactions.BATCH then
      if not starbase.starved then
        starbase.starved = true
        table.insert(events, { kind = "ReactorIdle", station = starbase.id, type = making.id, want = from })
      end
      return
    end
  end
  for _, from in making.from do
    local left = Reactions.BATCH
    for _, item in stored do
      if item.type == from and left > 0 then
        local take = math.min(left, item.quantity)
        left -= take
        Items.Take(state, item, take)
      end
    end
  end
  -- (what a reactor makes is the business's, as what a drill brings up is)
  Items.Add(state, making.id, Reactions.BATCH, starbase.id, Corporation.Store(state))
  starbase.composed += Reactions.BATCH
  starbase.starved = false
  table.insert(events, { kind = "Reacted", station = starbase.id, type = making.id, units = Reactions.BATCH })
end

function Starbases.Step(state: State.State, events: { Event })
  for _, id in state.starbaseIds do
    local starbase = state.starbases[id]
    -- (anchored, it has what stands for it under fire: at its heart,
    -- with its shield, its armour and its structure, and nobody's to fly)
    if starbase.core == 0 and Starbases.Anchored(state, starbase) then
      local tower = Structures.towerById[starbase.tower]
      local object = Space.Object(state, id)
      if object then
        local core = Space.NewShip(state, Structures.Core(tower), tower.name, "starbase", 0)
        local ball = Space.Launch(state, core, Space.SystemOf(state, id), object.x, object.y, object.z)
        starbase.core = core.id
        table.insert(events, { kind = "BallAdded", ball = ball.id })
      end
    end
    feed(state, starbase, events)
    -- (the drill: its hour runs from when it came online, and only
    -- while the tower is lit)
    local since = 0
    if Starbases.Lit(state, starbase) then
      for _, module in starbase.modules do
        if module.type == Structures.DRILL and state.tick >= module.ready then
          since = math.max(starbase.drilled, module.ready)
        end
      end
    end
    if since == 0 then
      starbase.drilled = state.tick
    elseif state.tick - since >= HOUR then
      starbase.drilled = since + HOUR
      local drilling = Starbases.Drilling(state, starbase)
      local deposit = drilling.deposit
      if deposit then
        local units = math.min(drilling.perHour, drilling.room - drilling.stored)
        if units > 0 then
          -- (what a drill brings up is the business's: Corporation.Store)
          Items.Add(state, deposit.material.id, units, id, Corporation.Store(state))
          starbase.raised += units
          -- ('full': that was the last it has room for)
          table.insert(events, { kind = "MoonDrilled", station = id, type = deposit.material.id, units = units,
            full = drilling.stored + units >= drilling.room })
        end
      end
    end
    -- (the reactor: its hour runs from when it came online and was set
    -- to make something, and only while the tower is lit)
    local began = 0
    if starbase.reaction ~= "" and Starbases.Lit(state, starbase) then
      for _, module in starbase.modules do
        if module.type == Structures.REACTOR and state.tick >= module.ready then
          began = math.max(starbase.reacted, module.ready)
        end
      end
    end
    if began == 0 then
      starbase.reacted = state.tick
    elseif state.tick - began >= HOUR then
      starbase.reacted = began + HOUR
      react(state, starbase, events)
    end
    if Starbases.Lit(state, starbase) then
      local every = interval(Structures.towerById[starbase.tower])
      -- (anchoring does not burn: the clock starts when it is done)
      starbase.burnt = math.max(starbase.burnt, starbase.ready)
      while starbase.fuel > 0 and state.tick - starbase.burnt >= every do
        starbase.fuel -= 1
        starbase.used += 1
        starbase.burnt += every
      end
      -- (its last block burnt: what is in the hangar, before it goes dark)
      feed(state, starbase, events)
      if starbase.fuel == 0 then
        table.insert(events, { kind = "StarbaseDark", station = id })
      end
    end
  end
end

return Starbases
