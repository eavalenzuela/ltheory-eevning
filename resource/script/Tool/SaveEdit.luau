--!strict
-- The save editor's work (the owner, 2026-11-17: "let's build a save
-- editor, so I can tweak and test stuff"): what App/saveedit does to a
-- game, with no engine in it, so that its specs run in bin/ltcore.
--
-- A save is a game (Core.Load) and goes back as one (Core.Save). Every
-- change here is made the way the game itself makes it where it can be
-- (Items.Add, Space.NewShip, Wars.Take, Wormholes.Close), so that what
-- is written is a state the game could have come to. Before anything is
-- written, Check loads a copy of the bytes and runs a step of the game
-- on it: a save the game could not go on from is never written.
--
-- A pilot's skills and queue are their character's as well as the
-- game's (Core/Character/Characters: on load the game takes the higher
-- of the two levels of each skill, and the character's queue). So what
-- is changed of them here is written to the character too (CharacterOf),
-- or a skill taken down would come back up.

local Characters = require("@lt/Core/Character/Characters")
local Core = require("@lt/Core/Api")
local Factions = require("@lt/Core/Data/Factions")
local Items = require("@lt/Core/Assets/Items")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local Types = require("@lt/Core/Data/Types")
local Wars = require("@lt/Core/Strategic/Wars")
local Wormholes = require("@lt/Core/Tactical/Wormholes")

local SaveEdit = {}

type Game = Core.Game

-- ---------------------------------------------------------------------
-- Opening, checking, writing

-- A game from a save's bytes, or nil and why not.
function SaveEdit.Open(data: buffer, length: number?): (Game?, string?)
  local ok, loaded = pcall(Core.Load, data, length)
  if not ok then
    return nil, tostring(loaded)
  end
  return loaded, nil
end

-- Whether the game can be written: it saves, the bytes load again, and
-- the game goes on a step from them. (The step is the copy's: the game
-- being edited is not moved on.)
function SaveEdit.Check(game: Game): (boolean, string?)
  local ok, data, length = pcall(Core.Save, game)
  if not ok then
    return false, `it cannot be saved: {data}`
  end
  local copy, why = SaveEdit.Open(data, length)
  if copy == nil then
    return false, `it does not load again: {why}`
  end
  local stepped, err = pcall(function(): boolean
    Core.Step(copy)
    return true
  end)
  if not stepped then
    return false, `the game cannot go on from it: {err}`
  end
  return true, nil
end

-- ---------------------------------------------------------------------
-- The pilot

function SaveEdit.SetWallet(game: Game, credits: number)
  game.state.wallet = math.max(0, math.floor(credits))
end

-- A skill to a level, 0 to 5; below 0, not known at all.
function SaveEdit.SetSkill(game: Game, skill: string, level: number)
  assert(Skills.byId[skill], `no skill '{skill}'`)
  level = math.clamp(math.floor(level), -1, Skills.MAX_LEVEL)
  if level >= 0 then
    game.state.skills[skill] = level
  else
    (game.state.skills :: { [string]: any })[skill] = nil
  end
  -- (a queue that would train it to where it is already, or below, is
  -- shortened by what it no longer needs)
  local training = game.state.training
  for index = #training, 1, -1 do
    if training[index].skill == skill and training[index].level <= level then
      table.remove(training, index)
    end
  end
end

-- Every skill to a level (or, below 0, every skill a pilot begins
-- without forgotten).
function SaveEdit.AllSkills(game: Game, level: number)
  for _, skill in Skills.list do
    SaveEdit.SetSkill(game, skill.id, if level < 0 then (if skill.start >= 0 then skill.start else -1) else level)
  end
end

function SaveEdit.ClearTraining(game: Game)
  table.clear(game.state.training)
  game.state.trainingStarted = game.state.tick
end

-- Standing with a faction, -10 to 10.
function SaveEdit.SetStanding(game: Game, faction: string, standing: number)
  assert(Factions.byId[faction], `no faction '{faction}'`)
  game.state.standings[faction] = math.clamp(standing, -10, 10)
end

-- Loyalty points with a faction.
function SaveEdit.SetLoyalty(game: Game, faction: string, points: number)
  assert(Factions.byId[faction], `no faction '{faction}'`)
  points = math.max(0, math.floor(points))
  if points > 0 then
    game.state.loyalty[faction] = points
  else
    (game.state.loyalty :: { [string]: any })[faction] = nil
  end
end

-- The pilot's character as the game now has them: what was read of
-- their file, with the game's skills and queue put in its place (taken
-- down too, which the game's own load would not do).
function SaveEdit.CharacterOf(game: Game, character: Characters.Character): Characters.Character
  local state = game.state
  local out = table.clone(character)
  out.skills = table.clone(state.skills)
  out.training = table.clone(state.training)
  if #state.training == 0 then
    out.done = 0
  end
  return out
end

-- ---------------------------------------------------------------------
-- Ships and items

export type Place = { holder: number, place: string, label: string, ship: number? }

-- The name of a place in space (a station, a planet), or its id.
function SaveEdit.PlaceName(game: Game, id: number): string
  local object = Space.Object(game.state, id)
  return if object then object.name else `#{id}`
end

-- Everywhere the pilot has something: the hangar of each station with
-- something of theirs in it, and each of their ships' holds and racks.
function SaveEdit.Places(game: Game): { Place }
  local state = game.state
  local places: { Place } = {}
  local stations: { [number]: boolean } = {}
  local mine: { [number]: boolean } = {}
  for _, id in state.shipIds do
    local ship = state.ships[id]
    if ship.owner == "player" then
      mine[id] = true
      if ship.docked ~= 0 then
        stations[ship.docked] = true
      end
    end
  end
  for _, id in state.itemIds do
    local item = state.items[id]
    if item.place == "hangar" and not mine[item.holder] then
      stations[item.holder] = true
    end
  end
  local list: { number } = {}
  for station in stations do
    table.insert(list, station)
  end
  table.sort(list)
  for _, station in list do
    table.insert(places, { holder = station, place = "hangar", label = `Hangar: {SaveEdit.PlaceName(game, station)}` })
  end
  for _, id in state.shipIds do
    local ship = state.ships[id]
    if mine[id] then
      local hull = Ships.byId[ship.type]
      local where = if ship.docked ~= 0 then SaveEdit.PlaceName(game, ship.docked) else "in space"
      local active = if id == state.player.ship then " (flying)" else ""
      table.insert(places, { holder = id, place = "ship", label = `{ship.name}: {hull and hull.name or ship.type}, {where}{active}`,
        ship = id })
    end
  end
  return places
end

-- What is in a place: a hangar's stacks, or everything in and on a ship.
function SaveEdit.Contents(game: Game, place: Place): { State.Item }
  local state = game.state
  local out: { State.Item } = {}
  for _, id in state.itemIds do
    local item = state.items[id]
    if item.holder == place.holder and (place.place == "ship" or item.place == place.place) then
      table.insert(out, item)
    end
  end
  return out
end

-- How many of a stack there are; none, and it goes. A fitted item is one.
function SaveEdit.SetQuantity(game: Game, item: number, quantity: number)
  local state = game.state
  local stack = assert(state.items[item], "no such item")
  quantity = math.max(0, math.floor(quantity))
  if quantity == 0 then
    state.items[item] = nil
    State.RemoveId(state.itemIds, item)
  elseif stack.slot == 0 then
    stack.quantity = quantity
  end
end

-- Something put in a hangar or a ship's hold.
function SaveEdit.Give(game: Game, type: string, quantity: number, holder: number, place: string): State.Item
  assert(Types.Get(type), `no item type '{type}'`)
  return Items.Add(game.state, type, math.max(1, math.floor(quantity)), holder, place :: any)
end

-- A new ship of a hull, assembled, docked at a station.
function SaveEdit.GiveShip(game: Game, hull: string, station: number): State.Ship
  local type = assert(Ships.byId[hull], `no hull '{hull}'`)
  return Space.NewShip(game.state, hull, type.name, "player", station)
end

-- A ship made good: no damage to its armour or hull.
function SaveEdit.Repair(game: Game, ship: number)
  local record = assert(game.state.ships[ship], "no such ship")
  record.armorDamage, record.hullDamage = 0, 0
end

-- A ship gone, and all that was in or on it. Not the one being flown,
-- nor one out in space.
function SaveEdit.RemoveShip(game: Game, ship: number): (boolean, string?)
  local state = game.state
  local record = state.ships[ship]
  if record == nil then
    return false, "no such ship"
  elseif ship == state.player.ship then
    return false, "that is the ship being flown"
  elseif record.docked == 0 or state.balls[ship] ~= nil then
    return false, "it is out in space"
  end
  for index = #state.itemIds, 1, -1 do
    local id = state.itemIds[index]
    if state.items[id].holder == ship then
      state.items[id] = nil
      table.remove(state.itemIds, index)
    end
  end
  state.ships[ship] = nil
  State.RemoveId(state.shipIds, ship)
  return true, nil
end

-- ---------------------------------------------------------------------
-- The world

-- A structure's fuel.
function SaveEdit.SetFuel(game: Game, station: number, fuel: number)
  local starbase = assert(game.state.starbases[station], "no such structure")
  starbase.fuel = math.max(0, math.floor(fuel))
end

-- A structure anchored now, and every module on it online.
function SaveEdit.FinishBuilding(game: Game, station: number)
  local state = game.state
  local starbase = assert(state.starbases[station], "no such structure")
  starbase.ready = math.min(starbase.ready, state.tick)
  for _, module in starbase.modules do
    module.ready = math.min(module.ready, state.tick)
  end
end

-- The name of a structure: its kind, and where it is.
function SaveEdit.StructureName(game: Game, station: number): string
  local starbase = game.state.starbases[station]
  local tower = if starbase then Structures.towerById[starbase.tower] else nil
  return `{if tower then tower.name else "structure"} at {SaveEdit.PlaceName(game, station)}`
end

-- A wormhole's size (1 to Wormholes.SIZES).
function SaveEdit.SetWormholeSize(game: Game, hole: number, size: number)
  local record = assert(game.state.wormholes[hole], "no such wormhole")
  record.size = math.clamp(math.floor(size), 1, #Wormholes.SIZES)
end

-- A wormhole with its whole life before it, and no mass gone through.
function SaveEdit.FreshenWormhole(game: Game, hole: number)
  local state = game.state
  local record = assert(state.wormholes[hole], "no such wormhole")
  record.closes = state.tick + Wormholes.LIFE[2]
  record.mass = nil
end

function SaveEdit.CloseWormhole(game: Game, hole: number)
  local record = assert(game.state.wormholes[hole], "no such wormhole")
  Wormholes.Close(game.state, record, game.events)
end

-- A system to a faction, or ("") to nobody, as a war would hand it over.
function SaveEdit.SetOwner(game: Game, system: number, owner: string)
  local state = game.state
  local node = assert(state.galaxy.systems[system], "no such system")
  assert(not node.uncharted, "uncharted space is nobody's")
  assert(owner == "" or owner == Wars.PILOT or Factions.byId[owner], `no faction '{owner}'`)
  Wars.Take(state.galaxy, state.wars, system, owner)
end

-- Pirate pressure in a system, 0 to 1.
function SaveEdit.SetPressure(game: Game, system: number, pressure: number)
  local all = game.state.happenings.pressure
  assert(game.state.galaxy.systems[system], "no such system")
  all[system] = math.clamp(pressure, 0, 1)
end

-- What a station's market holds of each thing: the type, how much, and
-- how much it would hold left alone. Empty for one nobody has traded at.
export type Stock = { index: number, type: string, stock: number, target: number }
function SaveEdit.Stock(game: Game, station: number): { Stock }
  local out: { Stock } = {}
  local econ = game.state.markets[station]
  local node = if econ then econ.nodes[1] else nil
  if econ and node then
    for index, class in econ.classes do
      table.insert(out, { index = index, type = class.id, stock = node.stock[index] or 0, target = node.target[index] or 0 })
    end
  end
  return out
end

function SaveEdit.SetStock(game: Game, station: number, index: number, units: number)
  local econ = assert(game.state.markets[station], "no market there")
  local node = assert(econ.nodes[1], "no market there")
  assert(econ.classes[index], "no such good")
  node.stock[index] = math.max(0, units)
end

-- ---------------------------------------------------------------------
-- Raw: anything in the state, by its path of keys

export type Key = string | number

-- The keys of a table, numbers first and ascending, then strings.
function SaveEdit.Keys(t: { [any]: any }): { Key }
  local keys: { Key } = {}
  for key in t do
    table.insert(keys, key)
  end
  table.sort(keys, function(a: any, b: any): boolean
    local ta, tb = type(a), type(b)
    if ta ~= tb then
      return ta == "number"
    end
    return a < b
  end)
  return keys
end

-- What is at a path in a table (nil if nothing).
function SaveEdit.At(root: any, path: { Key }): any
  local at = root
  for _, key in path do
    if type(at) ~= "table" then
      return nil
    end
    at = at[key]
  end
  return at
end

-- A value at a path set from what was typed, as the kind of value it
-- was: a number stays a number, a string a string, a flag a flag. A
-- table is not set this way.
function SaveEdit.SetRaw(root: any, path: { Key }, text: string): (boolean, string?)
  if #path == 0 then
    return false, "that is the whole state"
  end
  local parent = SaveEdit.At(root, table.move(path, 1, #path - 1, 1, {}))
  if type(parent) ~= "table" then
    return false, "nothing there"
  end
  local key = path[#path]
  local was = parent[key]
  local kind = type(was)
  if kind == "number" then
    local value = tonumber(text)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
      return false, "not a number"
    end
    parent[key] = value
  elseif kind == "string" then
    parent[key] = text
  elseif kind == "boolean" then
    local lower = string.lower(text)
    if lower == "true" or lower == "1" or lower == "yes" then
      parent[key] = true
    elseif lower == "false" or lower == "0" or lower == "no" then
      parent[key] = false
    else
      return false, "true or false"
    end
  else
    return false, "only a number, a string or a flag is set here"
  end
  return true, nil
end

return SaveEdit
