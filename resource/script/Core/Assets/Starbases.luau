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
--     done nobody can moor there.
--   - It burns fuel blocks by the hour while it has any. With none it
--     is dark: its field is down and none of its modules gives
--     anything. Fuel is put in by a ship moored there, and it lights
--     again at once.
--   - A module is anchored by a ship moored there, from its hold or the
--     tower's hangar, if the tower is lit and has the powergrid and CPU
--     for it besides what it already carries. It takes a while to come
--     online. It can be unanchored again, into the hangar.
--
-- Not yet: taking a tower down, anybody attacking one, batteries that
-- shoot, more than one owner.

local Constants = require("@lt/Core/Data/Constants")
local Items = require("@lt/Core/Assets/Items")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local System = require("@lt/Core/Describe/System")

local Starbases = {}

export type Event = { [string]: any }

-- How near a moon (in its own radii, from its middle) a tower has to be
-- anchored: where a ship that has warped to the moon arrives.
Starbases.REACH = 5

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

function Starbases.Apply(state: State.State, command: State.Command, events: { Event })
  local ship = state.ships[command.actor]
  local kind = command.kind
  if kind == "AnchorTower" then
    local ball = state.balls[ship.id]
    local item = state.items[command.item :: number]
    local tower = Structures.towerById[item.type]
    local moon = moonOf(state, command) :: System.Object
    Items.Take(state, item, 1)
    -- The tower is a station in the system's description from now on:
    -- a kilometre or so off the ship that put it there, which is then
    -- inside its field.
    local description = Space.Describe(state, ball.system)
    local id = ball.system * Constants.STRUCTURE_ID_SPAN + #description.objects + 1
    assert(#description.objects + 1 < Constants.STRUCTURE_ID_SPAN, "a system has outgrown its id range")
    table.insert(description.objects, {
      id = id, kind = "station", name = `{moon.name} - Starbase`, x = ball.x + 1200, y = ball.y, z = ball.z,
      radius = tower.field, seed = (state.tick * 7919 + id) % 100000, parent = moon.id, site = id, variety = "starbase", to = 0,
    })
    state.starbases[id] = { id = id, tower = tower.id, owner = ship.owner, ready = state.tick + ticks(tower.anchor), fuel = 0,
      burnt = state.tick, modules = {} }
    State.InsertId(state.starbaseIds, id)
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
-- one that burns its last goes dark.
function Starbases.Step(state: State.State, events: { Event })
  for _, id in state.starbaseIds do
    local starbase = state.starbases[id]
    if Starbases.Lit(state, starbase) then
      local every = interval(Structures.towerById[starbase.tower])
      -- (anchoring does not burn: the clock starts when it is done)
      starbase.burnt = math.max(starbase.burnt, starbase.ready)
      while starbase.fuel > 0 and state.tick - starbase.burnt >= every do
        starbase.fuel -= 1
        starbase.burnt += every
      end
      if starbase.fuel == 0 then
        table.insert(events, { kind = "StarbaseDark", station = id })
      end
    end
  end
end

return Starbases
