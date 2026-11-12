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
--
-- Pirates come for a tower where order is thin (Tactical/Raids), and
-- its batteries fire on them (Tactical/Batteries).
--
-- Not yet: taking a tower down, more than one owner.

local Constants = require("@lt/Core/Data/Constants")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Moons = require("@lt/Core/Data/Moons")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local System = require("@lt/Core/Describe/System")

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

-- Whether a starbase is lit: anchored, and with fuel aboard.
function Starbases.Lit(state: State.State, starbase: State.Starbase): boolean
  return state.tick >= starbase.ready and starbase.fuel > 0
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
    for _, item in Items.In(state, starbase.id, "hangar") do
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
-- the station it is moored at.
local function toHand(state: State.State, command: State.Command): State.Item?
  local ship = state.ships[command.actor]
  local item = state.items[command.item or 0]
  if ship == nil or item == nil or item.slot ~= 0 then
    return nil
  end
  if (item.holder == ship.id and item.place == "cargo") or (ship.docked ~= 0 and item.holder == ship.docked and item.place == "hangar") then
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
    if item == nil or item.type ~= Structures.FUEL.id then
      return false, "no fuel to hand"
    end
    local quantity = command.quantity or item.quantity
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
    end
    return true
  elseif kind == "UnanchorModule" then
    for _, module in starbase.modules do
      if module.type == command.type then
        return true
      end
    end
    return false, "no such module is anchored here"
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
    burnt = state.tick, modules = {}, drilled = state.tick, raid = 0, raids = 0 }
  State.InsertId(state.starbaseIds, id)
  return id
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
  elseif kind == "UnanchorModule" then
    for index = #starbase.modules, 1, -1 do
      if starbase.modules[index].type == command.type then
        table.remove(starbase.modules, index)
        Items.Add(state, command.type :: string, 1, starbase.id, "hangar")
        table.insert(events, { kind = "ModuleUnanchored", station = starbase.id, module = command.type })
        break
      end
    end
  end
end

-- Once a tick: every lit tower burns its fuel, a block at a time, and
-- one that burns its last goes dark. And a lit tower with a drill
-- online brings up an hour's worth of its moon, every hour, while it
-- has the room.
local HOUR = math.floor(3600 / Constants.TICK + 0.5)

-- A tower with nothing in its tank takes what fuel is in its own
-- hangar, a day's worth at a time.
local function feed(state: State.State, starbase: State.Starbase, events: { Event })
  if starbase.fuel > 0 or not Starbases.Anchored(state, starbase) then
    return
  end
  for _, item in Items.In(state, starbase.id, "hangar") do
    if item.type == Structures.FUEL.id and starbase.fuel == 0 then
      local take = math.min(item.quantity, Structures.towerById[starbase.tower].fuel * 24)
      Items.Take(state, item, take)
      starbase.fuel, starbase.burnt = take, state.tick
      table.insert(events, { kind = "StarbaseFuelled", station = starbase.id, fuel = take, hangar = true })
    end
  end
end

function Starbases.Step(state: State.State, events: { Event })
  for _, id in state.starbaseIds do
    local starbase = state.starbases[id]
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
          Items.Add(state, deposit.material.id, units, id, "hangar")
          -- ('full': that was the last it has room for)
          table.insert(events, { kind = "MoonDrilled", station = id, type = deposit.material.id, units = units,
            full = drilling.stored + units >= drilling.room })
        end
      end
    end
    if Starbases.Lit(state, starbase) then
      local every = interval(Structures.towerById[starbase.tower])
      -- (anchoring does not burn: the clock starts when it is done)
      starbase.burnt = math.max(starbase.burnt, starbase.ready)
      while starbase.fuel > 0 and state.tick - starbase.burnt >= every do
        starbase.fuel -= 1
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
