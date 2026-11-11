--!strict
-- The Core's front door. The view, the UI and the tests go through this
-- and nothing else:
--
--   local game = Core.New({ galaxySeed = 1, historySeed = 1 })
--   Core.Submit(game, { kind = "Undock", actor = game.state.player.ship })
--   Core.Step(game)                      -- one tick
--   for _, event in Core.TakeEvents(game) do ... end
--   local data, length = Core.Save(game)
--
-- A Game is the state plus what is not state: the events of the ticks
-- since they were last taken. Commands are queued in the state and take
-- effect at the start of the next tick.

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Batteries = require("@lt/Core/Tactical/Batteries")
local Blueprints = require("@lt/Core/Data/Blueprints")
local Codec = require("@lt/Core/Persist/Codec")
local Combat = require("@lt/Core/Tactical/Combat")
local Constants = require("@lt/Core/Data/Constants")
local Dogma = require("@lt/Core/Dogma")
local Factions = require("@lt/Core/Data/Factions")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Hangar = require("@lt/Core/Assets/Hangar")
local Industry = require("@lt/Core/Assets/Industry")
local Items = require("@lt/Core/Assets/Items")
local Market = require("@lt/Core/Assets/Market")
local Mining = require("@lt/Core/Tactical/Mining")
local Missions = require("@lt/Core/Assets/Missions")
local Modules = require("@lt/Core/Data/Modules")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")
local Space = require("@lt/Core/Tactical/Space")
local Colonies = require("@lt/Core/Assets/Colonies")
local Planets = require("@lt/Core/Data/Planets")
local Starbases = require("@lt/Core/Assets/Starbases")
local State = require("@lt/Core/Kernel/State")
local Stations = require("@lt/Core/Assets/Stations")
local Structures = require("@lt/Core/Data/Structures")
local System = require("@lt/Core/Describe/System")
local Traffic = require("@lt/Core/Tactical/Traffic")
local Training = require("@lt/Core/Character/Training")
local Types = require("@lt/Core/Data/Types")

local Core = {}

export type Game = {
  state: State.State,
  events: { Space.Event },
}

export type Options = {
  galaxySeed: number,
  historySeed: number,
  systems: number?,   -- default 3
  peaceful: boolean?, -- no pirates; default false
  -- Other ships about (Tactical/Traffic); default false. The game turns
  -- it on. A test that is about one ship has the galaxy to itself.
  traffic: boolean?,
}

-- The shape of the state. Raise it, and add a migration, whenever a
-- change would make an old save unreadable.
Core.SAVE_VERSION = 18

-- MIGRATIONS[n] turns the state of a version n save into version n + 1.
-- Load applies them in turn, so a save from any version listed here
-- still opens.
local MIGRATIONS: { [number]: (state: any) -> () } = {
  -- 9: a market keeps count of goods lost to piracy (none, in a station).
  [8] = function(state: any)
    for _, market in state.markets do
      market.lost = table.create(#market.classes, 0)
      for _, edge in market.edges do
        edge.loss = 0
      end
    end
  end,
  -- 10: the Kethri took lasers and armour and the Vessari missiles, so
  -- the Kethri's frigate is the Lancer (the same hull as before under
  -- another flag) and the missile frigate, which was the Kethri Spindle,
  -- is the Vessari Javelin. A Spindle in a save becomes a Javelin, and
  -- its blueprint likewise. (The Javelin has a mid slot fewer and a low
  -- slot more: a Spindle with every mid slot filled comes through with a
  -- module the fitting screen has no row for.)
  [9] = function(state: any)
    local renamed = { ["frigate.spindle"] = "frigate.javelin", ["blueprint.frigate.spindle"] = "blueprint.frigate.javelin" }
    local function walk(t: any)
      local moved: { any } = {}
      for key, value in t do
        if type(value) == "table" then
          walk(value)
        elseif type(value) == "string" and renamed[value] then
          t[key] = renamed[value]
        end
        if type(key) == "string" and renamed[key] then
          table.insert(moved, key)
        end
      end
      for _, key in moved do
        t[renamed[key]], t[key] = t[key], nil
      end
    end
    walk(state)
  end,
  -- 11: a wreck remembers what hull it was, for the view to draw it as
  -- that hull broken. One from before is drawn as plain wreckage.
  [10] = function(state: any)
    for _, wreck in state.wrecks do
      wreck.hull = wreck.hull or ""
    end
  end,
  -- 12: pilots can put up starbases. A save from before has none.
  [11] = function(state: any)
    state.starbases = state.starbases or {}
    state.starbaseIds = state.starbaseIds or {}
  end,
  -- 13: planets can be worked. A save from before has no colonies.
  [12] = function(state: any)
    state.colonies = state.colonies or {}
    state.colonyIds = state.colonyIds or {}
  end,
  -- 14: a system has a security, and a pirate's bounty is its own. The
  -- galaxy of an older save is given its securities, and its pirates
  -- the bounty they had by the old rule (a fifth of the hull's price).
  -- (Its belts are as they were described: the rare ores are in the
  -- lawless belts of a new game.)
  [13] = function(state: any)
    Galaxy.Claim(state.galaxy)
    for _, pilot in state.pilots do
      local ship = state.ships[pilot.ship]
      local hull = if ship then Ships.byId[ship.type] else nil
      pilot.bounty = pilot.bounty or (if hull then math.floor(hull.basePrice * 0.2) else 0)
      pilot.tags = pilot.tags or 1
    end
  end,
  -- 15: a system is somebody's, or nobody's, and its security follows
  -- from that. The galaxy of an older save is shared out as a new one's
  -- is. (The stations of a system far from the first homeworld become
  -- its own faction's.)
  [14] = function(state: any)
    Galaxy.Claim(state.galaxy)
  end,
  -- 16: there are other ships about, and a pilot can be marked for
  -- firing on them. A save from before has none, and nobody is marked.
  [15] = function(state: any)
    state.traffic = state.traffic or {}
    state.trafficIds = state.trafficIds or {}
    state.trafficDue = state.trafficDue or 0
    -- (a save from before was somebody's game, and a game has traffic)
    if state.trafficOn == nil then
      state.trafficOn = true
    end
    state.player.marked = state.player.marked or 0
  end,
  -- 17: blueprints can be researched. A save from before has learned
  -- nothing, and its jobs all build.
  [16] = function(state: any)
    state.research = state.research or {}
    for _, job in state.jobs do
      job.research = job.research or ""
    end
  end,
  -- 18: stations have jobs for a pilot, and a pilot has a standing with
  -- each faction. A save from before has none in hand and stands at 0.
  [17] = function(state: any)
    state.missions = state.missions or {}
    state.missionIds = state.missionIds or {}
    state.missionsTaken = state.missionsTaken or {}
    state.missionsDone = state.missionsDone or 0
    state.standings = state.standings or {}
  end,
}

-- A new game: a galaxy, and the player's first ship docked at a station
-- in system 1.
function Core.New(options: Options): Game
  local galaxy = Galaxy.Describe(options.galaxySeed, options.systems or 3)
  local state: State.State = {
    galaxySeed = options.galaxySeed,
    historySeed = options.historySeed,
    tick = 0,
    nextId = Constants.FIRST_DYNAMIC_ID,
    galaxy = galaxy,
    systems = {},
    ships = {},
    shipIds = {},
    items = {},
    itemIds = {},
    skills = Skills.Starting(),
    training = {},
    trainingStarted = 0,
    jobs = {},
    research = {},
    missions = {},
    missionIds = {},
    missionsTaken = {},
    missionsDone = 0,
    standings = {},
    jobIds = {},
    wallet = 0,
    journal = {},
    markets = {},
    marketIds = {},
    orders = {},
    orderIds = {},
    trades = {},
    starbases = {},
    starbaseIds = {},
    colonies = {},
    colonyIds = {},
    balls = {},
    ballIds = {},
    missiles = {},
    wrecks = {},
    wreckIds = {},
    pilots = {},
    pilotIds = {},
    spawned = {},
    peaceful = options.peaceful == true,
    rocks = {},
    rockIds = {},
    grids = {},
    gridIds = {},
    player = { ship = 0, home = 0, marked = 0 },
    traffic = {},
    trafficIds = {},
    trafficDue = 0,
    trafficOn = options.traffic == true,
    queue = {},
  }
  -- (the starter station: the one that has a module for everything)
  local home = Space.Object(state, Stations.Starter(state))
  assert(home, "the first system has no station")
  local ship = Space.NewShip(state, "frigate.courier", "Courier", "player", home.id)
  state.player.ship = ship.id
  state.player.home = home.id
  state.wallet = 5000

  -- A starter fit and a few things to try in the hangar: some of them
  -- need a skill trained first, and the blueprint needs minerals.
  Items.Equip(state, ship.id, "autocannon.small", "ammo.emp")
  Items.Equip(state, ship.id, "autocannon.small", "ammo.emp")
  for _, kit in { { "ammo.emp", 600 }, { "ammo.fusion", 400 }, { "shield.extender.small", 1 }, { "afterburner.1mn", 1 },
    { "armor.repairer.small", 1 }, { "laser.pulse.small", 1 }, { "crystal.multifrequency", 1 },
    { "miner.small", 1 }, { "blueprint.ammo.emp", 1 } } :: { { any } } do
    Items.Add(state, kit[1], kit[2], home.id, "hangar")
  end
  return { state = state, events = {} }
end

-- Which module carries out a kind of command.
local ASSET_COMMANDS = { Fit = true, Unfit = true, LoadCharge = true, MoveItems = true }
local COMBAT_COMMANDS = { LockTarget = true, UnlockTarget = true, ActivateModule = true, DeactivateModule = true }
local AFTERMATH_COMMANDS = { Loot = true, Repair = true }
local INDUSTRY_COMMANDS = { Reprocess = true, StartJob = true, StartResearch = true }
local TRAINING_COMMANDS = { LearnSkill = true, TrainSkill = true, CancelTraining = true }
local MARKET_COMMANDS = { BuyNow = true, SellNow = true, PlaceOrder = true, CancelOrder = true }
local HANGAR_COMMANDS = { Assemble = true, BoardShip = true }
local STARBASE_COMMANDS = { AnchorTower = true, Fuel = true, AnchorModule = true, UnanchorModule = true }
local MISSION_COMMANDS = { AcceptMission = true, CompleteMission = true, AbandonMission = true }
local COLONY_COMMANDS = { DeployColony = true, BuildFacility = true, RemoveFacility = true, StartExtraction = true, Export = true }

local function validate(state: State.State, command: State.Command): (boolean, string?)
  -- (first, whether the station it is given at has the module for it)
  local served, lacking = Stations.Validate(state, command)
  if not served then
    return false, lacking
  end
  if ASSET_COMMANDS[command.kind] then
    return Items.Validate(state, command)
  elseif COMBAT_COMMANDS[command.kind] then
    return Combat.Validate(state, command)
  elseif AFTERMATH_COMMANDS[command.kind] then
    return Aftermath.Validate(state, command)
  elseif INDUSTRY_COMMANDS[command.kind] then
    return Industry.Validate(state, command)
  elseif MARKET_COMMANDS[command.kind] then
    return Market.Validate(state, command)
  elseif HANGAR_COMMANDS[command.kind] then
    return Hangar.Validate(state, command)
  elseif STARBASE_COMMANDS[command.kind] then
    return Starbases.Validate(state, command)
  elseif COLONY_COMMANDS[command.kind] then
    return Colonies.Validate(state, command)
  elseif MISSION_COMMANDS[command.kind] then
    return Missions.Validate(state, command)
  elseif TRAINING_COMMANDS[command.kind] then
    return Training.Validate(state, command)
  end
  return Space.Validate(state, command)
end

-- Whether a command could be carried out now, and if not, why not. Does
-- not change anything; the UI uses it to grey out actions.
function Core.Validate(game: Game, command: State.Command): (boolean, string?)
  return validate(game.state, command)
end

-- Queue a command for the next tick. Returns false and a reason if it
-- cannot be carried out now (it is then not queued).
function Core.Submit(game: Game, command: State.Command): (boolean, string?)
  local ok, reason = validate(game.state, command)
  if ok then
    table.insert(game.state.queue, command)
  end
  return ok, reason
end

-- Advance one tick: fly every ship through the second that just passed,
-- resolve the fighting of that second (Tactical/Combat) and what follows
-- from it (Tactical/Aftermath), apply the queued commands in order, let
-- the pirates give theirs, then steer every ship for the second to come
-- (Tactical/Space). A queued command that has stopped
-- being valid (an earlier one docked the ship, say) is dropped with a
-- CommandRejected event.
function Core.Step(game: Game)
  local state = game.state
  state.tick += 1
  Space.Integrate(state, game.events)
  local killers = Combat.Step(state, game.events, Batteries.Fire(state, game.events))
  for _, id in table.clone(state.ballIds) do
    local by = killers[id]
    if by then
      Aftermath.Destroy(state, id, by, game.events)
    end
  end
  local queue = state.queue
  state.queue = {}
  for _, command in queue do
    local ok, reason = validate(state, command)
    if ok and ASSET_COMMANDS[command.kind] then
      Items.Apply(state, command, game.events)
    elseif ok and COMBAT_COMMANDS[command.kind] then
      Combat.Apply(state, command, game.events)
    elseif ok and AFTERMATH_COMMANDS[command.kind] then
      Aftermath.Apply(state, command, game.events)
    elseif ok and INDUSTRY_COMMANDS[command.kind] then
      Industry.Apply(state, command, game.events)
    elseif ok and MARKET_COMMANDS[command.kind] then
      Market.Apply(state, command, game.events)
    elseif ok and HANGAR_COMMANDS[command.kind] then
      Hangar.Apply(state, command, game.events)
    elseif ok and STARBASE_COMMANDS[command.kind] then
      Starbases.Apply(state, command, game.events)
    elseif ok and COLONY_COMMANDS[command.kind] then
      Colonies.Apply(state, command, game.events)
    elseif ok and MISSION_COMMANDS[command.kind] then
      Missions.Apply(state, command, game.events)
    elseif ok and TRAINING_COMMANDS[command.kind] then
      Training.Apply(state, command, game.events)
    elseif ok then
      Space.Apply(state, command, game.events)
    else
      table.insert(game.events, { kind = "CommandRejected", command = command.kind, actor = command.actor, reason = reason })
    end
  end
  Pirates.Populate(state, game.events)
  Traffic.Step(state, game.events)
  Pirates.Think(state, game.events)
  Space.Decide(state, game.events)
  Aftermath.Step(state, game.events)
  Mining.Step(state)
  Market.Step(state, game.events)
  Starbases.Step(state, game.events)
  Colonies.Step(state, game.events)
  Industry.Step(state, game.events)
  Training.Step(state, game.events)
end

-- The events since the last call, oldest first.
function Core.TakeEvents(game: Game): { Space.Event }
  local events = game.events
  game.events = {}
  return events
end

-- ---------------------------------------------------------------------
-- Saving

-- The game as bytes: a buffer and how much of it is used.
function Core.Save(game: Game): (buffer, number)
  return Codec.Encode({ format = "ltheory-eevning save", saveVersion = Core.SAVE_VERSION, state = game.state })
end

-- A game from bytes written by Save. Raises if they are not a save this
-- version can read.
function Core.Load(data: buffer, length: number?): Game
  local file = Codec.Decode(data, length)
  if type(file) ~= "table" or file.format ~= "ltheory-eevning save" then
    error("Core.Load: this is not a save file", 0)
  end
  local version = file.saveVersion
  while type(version) == "number" and version < Core.SAVE_VERSION and MIGRATIONS[version] do
    MIGRATIONS[version](file.state)
    version += 1
  end
  if version ~= Core.SAVE_VERSION then
    error(`Core.Load: the save is version {tostring(file.saveVersion)}; this build reads version {Core.SAVE_VERSION}`, 0)
  end
  -- (whatever its version, it may be from before an item type was added)
  Market.Reconcile(file.state)
  return { state = file.state, events = {} }
end

-- The fingerprint of the state. Two games with the same hash are in the
-- same state.
function Core.Hash(game: Game): string
  return Codec.HashOf(game.state)
end

-- ---------------------------------------------------------------------
-- Questions the view asks. These read the state and never change it.

local Query = {}
Core.Query = Query

export type PlayerInfo = {
  ship: number,
  shipName: string,
  hull: Ships.ShipType,
  docked: number,     -- station id, or 0
  system: number,
  systemName: string,
  security: number,   -- of the system: 1 at a homeworld, 0 where nobody keeps order
  owner: string,      -- the name of the faction whose system it is; "" if nobody's
}

function Query.Player(game: Game): PlayerInfo
  local state = game.state
  local ship = state.ships[state.player.ship]
  local system = if ship.docked ~= 0 then Space.SystemOf(state, ship.docked) else state.balls[ship.id].system
  return {
    ship = ship.id, shipName = ship.name, hull = Ships.byId[ship.type], docked = ship.docked,
    system = system, systemName = state.galaxy.systems[system].name, security = state.galaxy.systems[system].security,
    owner = if Factions.byId[state.galaxy.systems[system].owner] then Factions.byId[state.galaxy.systems[system].owner].name else "",
  }
end

-- How safe a system is, and which of the three kinds of space that
-- makes it ("secure", "low" or "lawless"). Nothing for no such system.
function Query.Security(game: Game, system: number): (number?, Galaxy.Band?)
  local node = game.state.galaxy.systems[system]
  if node == nil then
    return nil, nil
  end
  return node.security, Galaxy.Band(node.security)
end

export type Entry = {
  id: number,
  kind: string,
  name: string,
  distance: number,   -- metres between surfaces, from the player's ship
  onGrid: boolean,
  variety: string,
  hostile: boolean,   -- a ship that will fire on the pilot: a pirate, or a patrol that has taken them for a criminal
}

-- What the player's ship can see: everything on its grid, and every
-- place in the system it could warp to. Nearest first. Empty while docked.
function Query.Overview(game: Game): { Entry }
  local state = game.state
  local me = state.balls[state.player.ship]
  if me == nil then
    return {}
  end
  local entries: { Entry } = {}
  for _, object in Space.Describe(state, me.system).objects do
    local onGrid = me.grid ~= 0 and object.site == me.grid
    local gone = object.kind == "asteroid" and Mining.Left(state, object) <= 0
    if (onGrid or object.kind ~= "asteroid") and not gone then
      local entry: Entry = { id = object.id, kind = object.kind :: string, name = object.name,
        distance = Space.Gap(me :: any, object :: any), onGrid = onGrid, variety = object.variety, hostile = false }
      table.insert(entries, entry)
    end
  end
  for _, id in state.ballIds do
    local ball = state.balls[id]
    if id ~= me.id and ball.system == me.system and ball.grid == me.grid and me.grid ~= 0 then
      local entry: Entry = { id = id, kind = ball.kind :: string, name = ball.name,
        distance = Space.Gap(me :: any, ball :: any), onGrid = true, variety = state.ships[id].type,
        hostile = state.ships[id].owner == "pirates" or state.pilots[id] ~= nil }
      table.insert(entries, entry)
    end
  end
  for _, id in state.wreckIds do
    local wreck = state.wrecks[id]
    if wreck.system == me.system and wreck.grid == me.grid and me.grid ~= 0 then
      local entry: Entry = { id = id, kind = "wreck", name = wreck.name,
        distance = Space.Gap(me :: any, wreck :: any), onGrid = true, variety = "", hostile = false }
      table.insert(entries, entry)
    end
  end
  table.sort(entries, function(a: Entry, b: Entry): boolean
    if a.distance ~= b.distance then
      return a.distance < b.distance
    end
    return a.id < b.id
  end)
  return entries
end

-- What a holder (a ship, a station's hangar, a wreck) has, optionally in
-- one place only.
function Query.Items(game: Game, holder: number, place: string?): { State.Item }
  return Items.In(game.state, holder, place)
end

-- A ship's fitted modules, rack by rack.
function Query.Fitted(game: Game, ship: number): { State.Item }
  return Items.Fitted(game.state, ship)
end

-- A ship's attributes with its present fit (nothing running).
function Query.Stats(game: Game, ship: number): Dogma.Stats
  return Items.ShipStats(game.state, ship)
end

-- What a ship's weapons come to with what is loaded in them.
function Query.Offence(game: Game, ship: number): Items.Offence
  return Items.Offence(game.state, ship)
end

-- CPU and powergrid a ship's fit uses.
function Query.FittingUse(game: Game, ship: number): (number, number)
  local cpu, powergrid = 0, 0
  for _, item in Items.Fitted(game.state, ship) do
    local module = Modules.byId[item.type]
    cpu += module.cpu
    powergrid += module.powergrid
  end
  return cpu, powergrid
end

function Query.CargoUsed(game: Game, ship: number): number
  return Items.CargoUsed(game.state, ship)
end

-- What repairing the player's docked ship would cost.
function Query.RepairCost(game: Game): number
  return Aftermath.RepairCost(game.state, game.state.ships[game.state.player.ship])
end

-- The chance a fitted turret would hit a target now, or nil.
function Query.HitChance(game: Game, ship: number, item: number, target: number): number?
  return Combat.HitChance(game.state, ship, item, target)
end

-- What a station's market asks and bids for a type, and how many it has.
function Query.Quote(game: Game, station: number, type: string): Market.Quote
  return Market.Quote(game.state, station, type)
end

-- What buying a quantity at once would cost (nil if the station has not
-- that many), and what selling it at once would bring after tax.
function Query.BuyCost(game: Game, station: number, type: string, quantity: number): number?
  return Market.BuyCost(game.state, station, type, quantity)
end

function Query.SellValue(game: Game, station: number, type: string, quantity: number): number
  return Market.SellValue(game.state, station, type, quantity)
end

-- The sales tax and broker's fee the pilot pays, as shares.
function Query.Fees(game: Game): (number, number)
  return Market.Tax(game.state), Market.Fee(game.state)
end

-- The wallet's journal, oldest first.
function Query.Journal(game: Game): { State.Entry }
  return game.state.journal
end

function Query.Orders(game: Game, station: number?): { State.Order }
  return Market.Orders(game.state, station)
end

function Query.History(game: Game, station: number, type: string): { State.TradeDay }
  return Market.History(game.state, station, type)
end

-- The player's ships docked at a station.
function Query.Ships(game: Game, station: number): { State.Ship }
  return Hangar.Ships(game.state, station)
end

-- What the player owns, place by place: the hold of the ship flown
-- (station 0), then every station with something of the pilot's in its
-- hangar, the one docked at first and the rest by system and station.
export type AssetsAt = {
  station: number,      -- 0 for the hold
  name: string,
  system: number,
  systemName: string,
  here: boolean,        -- the pilot is docked there (or it is the hold)
  ships: { State.Ship },
  items: { State.Item },
  volume: number,       -- of the items, m3
  worth: number,        -- of items and hulls, at base prices
}
function Query.Assets(game: Game): { AssetsAt }
  local state = game.state
  local me = state.ships[state.player.ship]
  local places: { [number]: AssetsAt } = {}
  local order: { number } = {}
  local function at(station: number): AssetsAt
    local place = places[station]
    if place == nil then
      local object = Space.Object(state, station)
      local system = if object then Space.SystemOf(state, station) else Query.Player(game).system
      place = {
        station = station, name = if object then object.name else `{me.name}: hold`, system = system,
        systemName = state.galaxy.systems[system].name, here = station == 0 or station == me.docked,
        ships = {}, items = {}, volume = 0, worth = 0,
      }
      places[station] = place
      table.insert(order, station)
    end
    return place
  end
  for _, id in state.itemIds do
    local item = state.items[id]
    local hold = item.holder == me.id and item.place == "cargo"
    if hold or (item.place == "hangar" and Space.Object(state, item.holder) ~= nil) then
      local place = at(if hold then 0 else item.holder)
      local info = Types.Info(item.type)
      table.insert(place.items, item)
      place.volume += item.quantity * info.volume
      place.worth += item.quantity * info.basePrice
    end
  end
  for _, id in state.shipIds do
    local ship = state.ships[id]
    if ship.owner == me.owner and ship.docked ~= 0 then
      local place = at(ship.docked)
      table.insert(place.ships, ship)
      place.worth += Ships.byId[ship.type].basePrice
    end
  end
  table.sort(order, function(a: number, b: number): boolean
    local pa, pb = places[a], places[b]
    if pa.here ~= pb.here then
      return pa.here
    elseif (a == 0) ~= (b == 0) then
      return a == 0
    end
    return a < b
  end)
  local found: { AssetsAt } = {}
  for _, station in order do
    table.insert(found, places[station])
  end
  return found
end

export type SkillInfo = {
  skill: Skills.Skill,
  level: number,      -- -1 if the pilot has not learned it
  queued: number,     -- the level it will reach when the queue is done
}

-- Every skill, in the order the data lists them, with what the pilot
-- knows of it.
function Query.Skills(game: Game): { SkillInfo }
  local found: { SkillInfo } = {}
  for _, skill in Skills.list do
    table.insert(found, { skill = skill, level = game.state.skills[skill.id] or -1,
      queued = Training.QueuedLevel(game.state, skill.id) })
  end
  return found
end

-- The training queue with its times; the first entry is in training.
function Query.Training(game: Game): { Training.Queued }
  return Training.Queue(game.state)
end

-- Why the pilot cannot use a hull or module yet ("needs Frigates 2"), or
-- nil if they can.
function Query.Untrained(game: Game, type: string): string?
  local missing = Skills.Missing(Skills.Needs(type), game.state.skills)
  return if missing then Skills.Describe(missing) else nil
end

-- The manufacturing jobs running, optionally at one station.
function Query.Jobs(game: Game, station: number?): { State.Job }
  return Industry.Jobs(game.state, station)
end

function Query.JobSlots(game: Game): number
  return Industry.JobSlots(game.state)
end

-- What running a blueprint so many times at a station would take, or nil
-- if the type is not a blueprint.
function Query.JobPlan(game: Game, station: number, type: string, runs: number): Industry.Plan?
  local blueprint = Blueprints.byId[type]
  return if blueprint then Industry.Plan(game.state, station, blueprint, runs) else nil
end

-- A body by id (a ship in space or a described object), or nil.
function Query.Body(game: Game, id: number): Space.Body?
  return Space.Body(game.state, id)
end

-- A pilot's starbase, by the id of its station: how it stands. Nil if
-- the station is not one.
export type StarbaseStatus = {
  tower: Structures.Tower,
  mine: boolean,          -- it is the player's
  anchored: boolean,      -- its anchoring is done
  wait: number,           -- seconds until it is, if it is not
  lit: boolean,           -- and it has fuel
  fuel: number,           -- blocks aboard
  hours: number,          -- that they will last
  powergrid: number,      -- drawn by its modules
  cpu: number,
  -- (a module is online when its own anchoring is done and the tower is lit)
  modules: { { type: string, online: boolean, wait: number } },
}
function Query.Starbase(game: Game, id: number): StarbaseStatus?
  local state = game.state
  local starbase = state.starbases[id]
  if starbase == nil then
    return nil
  end
  local powergrid, cpu = Starbases.Draw(starbase)
  local lit = Starbases.Lit(state, starbase)
  local modules = {}
  for _, module in starbase.modules do
    table.insert(modules, { type = module.type, online = lit and state.tick >= module.ready,
      wait = math.max(0, module.ready - state.tick) * Constants.TICK })
  end
  local ship = state.ships[state.player.ship]
  return {
    tower = Structures.towerById[starbase.tower], mine = ship ~= nil and ship.owner == starbase.owner,
    anchored = Starbases.Anchored(state, starbase), wait = math.max(0, starbase.ready - state.tick) * Constants.TICK, lit = lit,
    fuel = starbase.fuel, hours = Starbases.Hours(starbase), powergrid = powergrid, cpu = cpu, modules = modules,
  }
end

-- The jobs to be had and in hand: what the station the pilot is docked
-- at offers (none in space), the jobs the pilot has taken, each with
-- whether it can be finished where they are now (and if not, why not),
-- and their standing with the faction whose station it is.
export type MissionStatus = { mission: State.Mission, title: string, ready: boolean, why: string }
export type MissionsStatus = { offers: { MissionStatus }, inHand: { MissionStatus }, faction: string, standing: number, done: number }
function Query.Missions(game: Game): MissionsStatus
  local state = game.state
  local ship = state.ships[state.player.ship]
  local offers: { MissionStatus } = {}
  local faction, standing = "", 0
  if ship.docked ~= 0 then
    for _, offer in Missions.Offers(state, ship.docked) do
      table.insert(offers, { mission = offer, title = Missions.Title(offer), ready = false, why = "" })
    end
    local node = state.galaxy.systems[Space.SystemOf(state, ship.docked)]
    faction = if Factions.byId[node.nearest] then Factions.byId[node.nearest].name else ""
    standing = Missions.Standing(state, node.nearest)
  end
  local inHand: { MissionStatus } = {}
  for _, mission in Missions.InHand(state) do
    local ready, why = Missions.Ready(state, ship, mission)
    table.insert(inHand, { mission = mission, title = Missions.Title(mission), ready = ready, why = why or "" })
  end
  return { offers = offers, inHand = inHand, faction = faction, standing = standing, done = state.missionsDone }
end

-- What the pilot has researched of a blueprint (levels of material and
-- of time saving), and what the next level of each would take (nil when
-- there is none). Nothing for no such blueprint.
export type ResearchStatus = { material: number, time: number, nextMaterial: Industry.ResearchPlan?, nextTime: Industry.ResearchPlan? }
function Query.Research(game: Game, type: string): ResearchStatus?
  local blueprint = Blueprints.byId[type]
  if blueprint == nil then
    return nil
  end
  local material, time = Industry.Researched(game.state, type)
  return {
    material = material, time = time,
    nextMaterial = Industry.ResearchPlan(game.state, blueprint, "material"),
    nextTime = Industry.ResearchPlan(game.state, blueprint, "time"),
  }
end

-- What a planet has to take, and how rich it is in each: for any planet
-- of a described system, colony or none. None for anything else.
function Query.Deposits(game: Game, planet: number): { Planets.Deposit }
  local object = Space.Object(game.state, planet)
  return if object and object.kind == "planet" then Planets.Deposits(object.variety, object.seed) else {}
end

-- The planets the player has a colony on, in the order of their ids.
function Query.Colonies(game: Game): { number }
  local state = game.state
  local ship = state.ships[state.player.ship]
  local found: { number } = {}
  for _, id in state.colonyIds do
    if ship and state.colonies[id].owner == ship.owner then
      table.insert(found, id)
    end
  end
  return found
end

-- A colony, by the id of its planet: how it stands. Nil if the planet
-- has none.
export type FacilityStatus = {
  id: number,
  kind: string,
  what: string,
  working: boolean,   -- an extractor on a programme, a processor with a batch in hand
  left: number,       -- seconds its programme has to run, or its batch
  rate: number,       -- units an extractor's next cycle brings up
}
export type ColonyStatus = {
  planet: number,
  name: string,
  variety: string,
  mine: boolean,
  powergrid: number,  -- drawn by its facilities
  cpu: number,
  room: number,       -- of its store, m3
  used: number,
  near: boolean,      -- the player's ship is near enough to take goods up
  deposits: { Planets.Deposit },
  facilities: { FacilityStatus },
  -- (what the player's ship could take of each now: Colonies.Fits)
  store: { { type: string, quantity: number, fits: number } },
}
function Query.Colony(game: Game, planet: number): ColonyStatus?
  local state = game.state
  local colony = state.colonies[planet]
  local object = Space.Object(state, planet)
  if colony == nil or object == nil then
    return nil
  end
  local ship = state.ships[state.player.ship]
  local powergrid, cpu = Colonies.Draw(colony)
  local room, used = Colonies.Room(colony)
  local near = ship ~= nil and Colonies.Near(state, ship.id, planet)
  local facilities: { FacilityStatus } = {}
  for _, pin in colony.pins do
    local extractor = pin.kind == "extractor"
    local working = if extractor then pin.ends > 0 else pin.next > 0
    table.insert(facilities, {
      id = pin.id, kind = pin.kind, what = pin.what, working = working,
      left = if working then math.max(0, (if extractor then pin.ends else pin.next) - state.tick) * Constants.TICK else 0,
      rate = if extractor and working then Planets.Yield(Planets.Richness(object.seed, pin.what), pin.cycle) else 0,
    })
  end
  local store = {}
  for _, stored in colony.store do
    table.insert(store, { type = stored.type, quantity = stored.quantity,
      fits = if near and ship then Colonies.Fits(state, ship.id, colony, stored.type) else 0 })
  end
  return {
    planet = planet, name = object.name, variety = object.variety, mine = ship ~= nil and ship.owner == colony.owner,
    powergrid = powergrid, cpu = cpu, room = room, used = used, near = near,
    deposits = Planets.Deposits(object.variety, object.seed), facilities = facilities, store = store,
  }
end

-- The station a new pilot starts at: the one that has everything.
function Query.Starter(game: Game): number
  return Stations.Starter(game.state)
end

-- What a station is made of (its tower and modules), and the services
-- its modules give. Nil and none if 'id' is not a station.
function Query.Station(game: Game, id: number): (Structures.Makeup?, { Structures.Service })
  return Stations.Makeup(game.state, id), Stations.Services(game.state, id)
end

-- A ship's ball, or nil if it is docked.
function Query.Ball(game: Game, ship: number): State.Ball?
  return game.state.balls[ship]
end

-- The described objects of a system, or nothing if the game has not been
-- there yet.
function Query.Objects(game: Game, system: number): { System.Object }
  local description = game.state.systems[system]
  return if description then description.objects else {}
end

return Core
