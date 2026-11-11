--!strict
-- The fleet: pilots hired to fly the player's other ships beside their
-- own.
--
-- A station has a few pilots looking for work each day. One is hired
-- for a fee, is paid a wage every day after, and brings one thing: how
-- good they are, a grade from 1 to 4, which is the level every skill
-- counts as for a ship they fly and decides how big a hull they can be
-- given (a frigate at 1, a battleship at 4). The player commands as
-- many as their Leadership.
--
-- A hired pilot does nothing until given a ship: one of the player's
-- own, docked where the player is, fitted as the player fitted it,
-- which they have to be good enough to fly. From then on they stay
-- with the player. They undock when the player does and dock when the
-- player does, warp where the player warps and jump where the player
-- jumps, and one left behind makes their own way after, gate by gate.
-- On the player's grid they fight whatever they have been pointed at;
-- with nothing pointed out, whoever is attacking anybody of the fleet;
-- and otherwise they keep station. One with a remote repairer fitted
-- mends whoever of the fleet is worst hurt. Told to stay, a pilot docks
-- at the nearest station and waits there.
--
-- A pilot whose ship has a mining laser can be set to mine the belt
-- the player is at: they cut rock after rock until the hold is full,
-- take the ore in to the nearest station, where it goes into the
-- player's hangar, and come back, for as long as they are left to it
-- and wherever the player goes. Somebody after them at the belt sends
-- them in early.
--
-- They fly with the orders anybody's ship does, so everything that
-- holds for a ship holds for theirs. What they destroy is the
-- player's doing (the bounty, and the blame). A ship of theirs that is
-- destroyed is lost with what was aboard, less the insurance. The
-- pilot is not: they are back on the list, without a ship.
--
-- A pilot whose wage cannot be paid leaves, and the ship they flew is
-- found at the player's home station.
--
-- (The beginning of M7. Not yet: pilots who haul or patrol by standing
-- order, pilots who get better, loyalty, a ship's own drones.)

local Combat = require("@lt/Core/Tactical/Combat")
local Constants = require("@lt/Core/Data/Constants")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Mend = require("@lt/Core/Tactical/Mend")
local Mining = require("@lt/Core/Tactical/Mining")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Names = require("@lt/Core/Describe/Names")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")
local Types = require("@lt/Core/Data/Types")
local Vitals = require("@lt/Core/Tactical/Vitals")
local Wallet = require("@lt/Core/Assets/Wallet")

local Fleet = {}

export type Event = { [string]: any }

-- Somebody looking for work at a station today.
export type Candidate = { key: string, name: string, skill: number, fee: number, wage: number }

-- How many a station has looking for work each day.
Fleet.CANDIDATES = 3
-- Ticks in a day: what a wage is for, and how long a station's
-- candidates are the same.
local DAY = math.ceil(86400 / Constants.TICK)
Fleet.DAY = DAY

-- What a pilot of a skill is paid a day, and what it costs to sign them.
function Fleet.Wage(skill: number): number
  return 6000 * skill * skill
end

function Fleet.Fee(skill: number): number
  return 5 * Fleet.Wage(skill)
end

-- How many pilots the player can command: their Leadership.
function Fleet.Max(state: State.State): number
  return math.max(0, state.skills.leadership or 0)
end

-- The pilots looking for work at a station today, less those hired.
function Fleet.Candidates(state: State.State, station: number): { Candidate }
  local object = Space.Object(state, station)
  if object == nil or object.kind ~= "station" or state.starbases[station] then
    return {}
  end
  local day = state.tick // DAY
  local found: { Candidate } = {}
  for slot = 1, Fleet.CANDIDATES do
    local key = `{station}:{day}:{slot}`
    if not (state.hiredDay == day and table.find(state.hired, key)) then
      local rng = Rng.For(state.historySeed, station, day, slot, 97)
      local roll = Rng.Next(rng)
      local skill = if roll < 0.4 then 1 elseif roll < 0.75 then 2 elseif roll < 0.95 then 3 else 4
      table.insert(found, { key = key, name = Names.Person(rng), skill = skill, fee = Fleet.Fee(skill), wage = Fleet.Wage(skill) })
    end
  end
  return found
end

local function candidate(state: State.State, station: number, key: string): Candidate?
  for _, found in Fleet.Candidates(state, station) do
    if found.key == key then
      return found
    end
  end
  return nil
end

-- How good a pilot has to be to be given a hull of a class.
Fleet.GRADE = { frigate = 1, industrial = 1, destroyer = 2, barge = 2, cruiser = 3, battleship = 4 } :: { [string]: number }

-- Why a hired pilot cannot fly a ship as it is fitted, if they cannot:
-- they are not good enough for a hull of its class, or it or something
-- fitted to it wants a skill at a level above theirs.
function Fleet.Cannot(state: State.State, wing: State.Wingman, ship: State.Ship): string?
  local hull = Ships.byId[ship.type]
  local grade = Fleet.GRADE[hull.class] or 1
  if wing.skill < grade then
    return `is grade {wing.skill}: a {hull.class} wants a pilot of grade {grade}`
  end
  local levels = Items.HIRED[wing.skill]
  local missing = Skills.Missing(Skills.Needs(ship.type), levels)
  for _, item in Items.Fitted(state, ship.id) do
    missing = missing or Skills.Missing(Skills.Needs(item.type), levels)
  end
  return if missing then Skills.Describe(missing) else nil
end

local function nearestStation(state: State.State, me: State.Ball): System.Object?
  local best: System.Object?, least = nil, math.huge
  for _, object in Space.Describe(state, me.system).objects do
    local starbase = state.starbases[object.id]
    if object.kind == "station" and (starbase == nil or starbase.ready <= state.tick) then
      local far = Space.Distance(object :: any, me :: any)
      if far < least then
        best, least = object, far
      end
    end
  end
  return best
end

-- The mining lasers a ship has fitted.
local function miners(state: State.State, ship: number): { State.Item }
  local found: { State.Item } = {}
  if state.ships[ship] then
    for _, item in Items.Fitted(state, ship) do
      if Modules.byId[item.type].miner then
        table.insert(found, item)
      end
    end
  end
  return found
end

-- The hired pilots a "mine here" would set to work: those (or the one
-- named) on the player's grid whose ship has a mining laser.
local function diggers(state: State.State, only: State.Wingman?): { State.Wingman }
  local lead = state.balls[state.player.ship]
  local found: { State.Wingman } = {}
  for _, id in state.fleetIds do
    local wing = state.fleet[id]
    local ball = state.balls[wing.ship]
    if (only == nil or only == wing) and lead and ball and ball.system == lead.system and ball.grid == lead.grid
      and #miners(state, wing.ship) > 0 then
      table.insert(found, wing)
    end
  end
  return found
end

function Fleet.Validate(state: State.State, command: State.Command): (boolean, string?)
  local ship = state.ships[command.actor]
  if ship == nil or ship.id ~= state.player.ship then
    return false, "no such ship"
  end
  local kind = command.kind
  if kind == "HirePilot" then
    if ship.docked == 0 then
      return false, "not docked"
    end
    local found = candidate(state, ship.docked, command.what or "")
    if found == nil then
      return false, "nobody of that name is looking for work here"
    elseif #state.fleetIds >= Fleet.Max(state) then
      return false, if Fleet.Max(state) == 0 then "needs Leadership 1" else `Leadership {Fleet.Max(state)} commands no more pilots`
    elseif state.wallet < found.fee then
      return false, "not enough credits"
    end
    return true
  end
  local wing: State.Wingman? = state.fleet[command.pilot or 0]
  if kind == "AssignShip" then
    if wing == nil then
      return false, "no such pilot"
    elseif ship.docked == 0 then
      return false, "not docked"
    end
    local old = state.ships[wing.ship]
    if old and old.docked == 0 then
      return false, `{wing.name} is out flying`
    end
    local target = command.target or 0
    if target == 0 then
      return old ~= nil, if old then nil else `{wing.name} has no ship`
    end
    local other = state.ships[target]
    if other == nil or other.owner ~= "player" or other.docked ~= ship.docked then
      return false, "that ship is not here"
    elseif other.id == ship.id then
      return false, "that is the ship you are flying"
    elseif other.pilot == wing.id then
      return false, `{wing.name} flies it already`
    elseif other.pilot ~= 0 then
      return false, "somebody flies that ship already"
    elseif Ships.byId[other.type].class == "capsule" then
      return false, "nobody is hired to fly a capsule"
    end
    local cannot = Fleet.Cannot(state, wing, other)
    if cannot then
      return false, `{wing.name} {cannot}`
    end
    return true
  elseif kind == "DismissPilot" then
    if wing == nil then
      return false, "no such pilot"
    end
    local old = state.ships[wing.ship]
    if old and old.docked == 0 then
      return false, `{wing.name} is out flying`
    end
    return true
  elseif kind == "FleetOrder" then
    if #state.fleetIds == 0 then
      return false, "no pilots are hired"
    elseif command.pilot ~= nil and command.pilot ~= 0 and wing == nil then
      return false, "no such pilot"
    end
    local what = command.what
    if what == "follow" or what == "stay" then
      return true
    elseif what == "mine" then
      local me = state.balls[ship.id]
      if me == nil then
        return false, "docked"
      end
      local post = Space.Object(state, me.grid)
      if post == nil or post.kind ~= "belt" then
        return false, "this is not an asteroid belt"
      elseif nearestStation(state, me) == nil then
        return false, "there is no station in this system to take the ore to"
      elseif #diggers(state, wing) == 0 then
        return false, "no hired pilot here has a mining laser fitted"
      end
      return true
    elseif what == "engage" then
      local me = state.balls[ship.id]
      local target = state.balls[command.target or 0]
      if me == nil then
        return false, "docked"
      elseif target == nil or state.ships[target.id].owner == "player" then
        return false, "no such target"
      elseif target.system ~= me.system or target.grid ~= me.grid or me.grid == 0 then
        return false, "target is not on grid"
      end
      return true
    end
    return false, "no such order"
  end
  return false, `unknown command '{kind}'`
end

-- Take a pilot off whatever ship they have.
local function release(state: State.State, wing: State.Wingman)
  local old = state.ships[wing.ship]
  if old then
    old.pilot = 0
  end
  wing.ship, wing.target = 0, 0
end

local function forget(state: State.State, wing: State.Wingman)
  release(state, wing)
  state.fleet[wing.id] = nil
  State.RemoveId(state.fleetIds, wing.id)
end

function Fleet.Apply(state: State.State, command: State.Command, events: { Event })
  local ship = state.ships[command.actor]
  local kind = command.kind
  if kind == "HirePilot" then
    local found = candidate(state, ship.docked, command.what :: string) :: Candidate
    local day = state.tick // DAY
    if state.hiredDay ~= day then
      state.hired, state.hiredDay = {}, day
    end
    table.insert(state.hired, found.key)
    Wallet.Pay(state, -found.fee, "hiring", events)
    local wing: State.Wingman = { id = State.NewId(state), name = found.name, skill = found.skill, wage = found.wage,
      paid = state.tick, ship = 0, order = "follow", target = 0, post = 0, base = 0, hauled = 0 }
    state.fleet[wing.id] = wing
    table.insert(state.fleetIds, wing.id)
    table.insert(events, { kind = "PilotHired", pilot = wing.id, name = wing.name })
    return
  end
  local wing = state.fleet[command.pilot or 0]
  if kind == "AssignShip" then
    release(state, wing)
    local other = state.ships[command.target or 0]
    if other then
      other.pilot = wing.id
      wing.ship = other.id
    end
    table.insert(events, { kind = "ShipAssigned", pilot = wing.id, name = wing.name, ship = wing.ship })
  elseif kind == "DismissPilot" then
    table.insert(events, { kind = "PilotLeft", pilot = wing.id, name = wing.name, reason = "dismissed" })
    forget(state, wing)
  elseif kind == "FleetOrder" and command.what == "mine" then
    -- The belt the player is at, and the station nearest it.
    local me = state.balls[ship.id]
    local base = nearestStation(state, me) :: System.Object
    for _, each in diggers(state, wing) do
      each.order, each.target = "mine", 0
      each.post, each.base = me.grid, base.id
    end
    table.insert(events, { kind = "FleetOrdered", what = "mine", target = me.grid })
  elseif kind == "FleetOrder" then
    for _, id in state.fleetIds do
      local each = state.fleet[id]
      if wing == nil or each == wing then
        if command.what == "engage" then
          each.target = command.target :: number
        else
          each.order = command.what :: string
          each.target = 0
        end
      end
    end
    table.insert(events, { kind = "FleetOrdered", what = command.what, target = command.target or 0 })
  end
end

local function give(state: State.State, command: State.Command, events: { Event }): boolean
  local kind = command.kind
  if kind == "LockTarget" or kind == "ActivateModule" or kind == "DeactivateModule" then
    if Combat.Validate(state, command) then
      Combat.Apply(state, command, events)
      return true
    end
  elseif Space.Validate(state, command) then
    Space.Apply(state, command, events)
    return true
  end
  return false
end

-- A pilot whose wage cannot be paid goes. The ship they flew is found
-- at the player's home station, as it was.
local function quit(state: State.State, wing: State.Wingman, events: { Event })
  local ship = state.ships[wing.ship]
  local ball = if ship then state.balls[ship.id] else nil
  if ship and ball then
    Vitals.Store(ship, ball)
    Space.RemoveBall(state, ball)
    ship.docked = state.player.home
    table.insert(events, { kind = "BallRemoved", ball = ship.id, reason = "left" })
  end
  table.insert(events, { kind = "PilotLeft", pilot = wing.id, name = wing.name, reason = "unpaid" })
  forget(state, wing)
end

-- Whether a module that runs on its own ship is one to switch on for a
-- fight: a hardener or an afterburner, but nothing that makes the ship
-- a bigger target (a microwarpdrive).
local function forFights(module: Modules.ModuleType): boolean
  if module.boost == nil then
    return false
  end
  for _, modifier in module.boost do
    if modifier.attribute == "signature" then
      return false
    end
  end
  return true
end

local function running(ball: State.Ball, item: number): boolean
  for _, each in ball.vitals.running do
    if each.item == item then
      return true
    end
  end
  return false
end

-- Fight 'prey': orbit it at a range the ship's weapons like, lock it,
-- and switch on everything there is for another ship and for a fight.
local function fight(state: State.State, me: State.Ball, prey: State.Ball, events: { Event })
  if not (me.mode == "orbit" and me.target == prey.id) then
    local reach = Items.Offence(state, me.id).range
    give(state, { kind = "Orbit", actor = me.id, target = prey.id, range = math.clamp(reach * 0.6, 1000, 15000) }, events)
  end
  local locked, targeted = false, false
  for _, lock in me.vitals.locks do
    if lock.target == prey.id then
      targeted, locked = true, lock.locked
    end
  end
  if not targeted then
    give(state, { kind = "LockTarget", actor = me.id, target = prey.id }, events)
  end
  for _, item in Items.Fitted(state, me.id) do
    local module = Modules.byId[item.type]
    if module.weapon or (module.hex and not Modules.Mends(module)) then
      if locked then
        give(state, { kind = "ActivateModule", actor = me.id, item = item.id, target = prey.id }, events)
      end
    elseif forFights(module) then
      give(state, { kind = "ActivateModule", actor = me.id, item = item.id }, events)
    end
  end
end

-- Look after the ship: a repairer runs while there is something to
-- mend and capacitor to mend it with.
local function mend(state: State.State, me: State.Ball, fighting: boolean, events: { Event })
  local vitals = me.vitals
  for _, item in Items.Fitted(state, me.id) do
    local module = Modules.byId[item.type]
    local repair = module.repair
    if repair then
      local have, most = vitals.armor, vitals.armorMax
      if repair.layer == "shield" then
        have, most = vitals.shield, vitals.shieldMax
      end
      local on = running(me, item.id)
      if not on and have < 0.8 * most and vitals.capacitor > 0.25 * vitals.capacitorMax then
        give(state, { kind = "ActivateModule", actor = me.id, item = item.id }, events)
      elseif on and (have >= 0.98 * most or vitals.capacitor < 0.1 * vitals.capacitorMax) then
        give(state, { kind = "DeactivateModule", actor = me.id, item = item.id }, events)
      end
    elseif not fighting and forFights(module) and running(me, item.id) then
      give(state, { kind = "DeactivateModule", actor = me.id, item = item.id }, events)
    end
  end
end

-- The ships of the player's side: their own, the hired pilots', and
-- the drones.
local function side(state: State.State): { number }
  local ids: { number } = { state.player.ship }
  for _, id in state.fleetIds do
    table.insert(ids, state.fleet[id].ship)
  end
  for _, id in state.droneIds do
    table.insert(ids, id)
  end
  return ids
end

-- The next gate on the way to a system.
local function travel(state: State.State, me: State.Ball, system: number, events: { Event })
  if not (me.intent and me.intent.kind == "jump") then
    local route = Galaxy.Route(state.galaxy, me.system, system)
    local gate = System.GateTo(Space.Describe(state, me.system), route[2])
    if gate then
      give(state, { kind = "Jump", actor = me.id, target = gate.id }, events)
    end
  end
end

-- What a pilot set to mine does: to the belt, a rock after another
-- until the hold is full, in to the station with it, and out again.
-- Somebody after the fleet at the belt sends them in early.
local function work(state: State.State, wing: State.Wingman, ship: State.Ship, events: { Event })
  local post, base = Space.Object(state, wing.post), Space.Object(state, wing.base)
  if post == nil or base == nil or #miners(state, ship.id) == 0 then
    wing.order = "stay"
    return
  end
  local me = state.balls[ship.id]
  if me == nil then
    -- Docked: what was mined goes into the hangar, and out again.
    local units = 0
    if ship.docked == base.id then
      for _, item in Items.In(state, ship.id, "cargo") do
        if Types.Info(item.type).category == "ore" then
          units += item.quantity
          Items.Add(state, item.type, item.quantity, base.id, "hangar")
          Items.Take(state, item, item.quantity)
        end
      end
    end
    if units > 0 then
      wing.hauled += units
      table.insert(events, { kind = "OreDelivered", pilot = wing.id, name = wing.name, units = units, station = base.id })
    end
    give(state, { kind = "Undock", actor = ship.id }, events)
    return
  end
  mend(state, me, false, events)
  if me.intent and me.intent.kind == "dock" then
    return
  end
  local system = Space.SystemOf(state, post.id)
  if me.system ~= system then
    travel(state, me, system, events)
    return
  elseif me.grid ~= post.id then
    if me.warp == nil and not give(state, { kind = "WarpTo", actor = ship.id, target = post.id, range = 0 }, events)
      and not (me.mode == "approach" and me.target == post.id) then
      give(state, { kind = "Approach", actor = ship.id, target = post.id, range = 0 }, events)
    end
    return
  end

  -- At the belt.
  local lasers = miners(state, ship.id)
  local function goIn()
    me.vitals.locks = {}
    give(state, { kind = "Dock", actor = ship.id, target = base.id }, events)
  end
  if Pirates.Hunting(state, me) ~= 0 then
    goIn()
    return
  end
  for _, item in lasers do
    if running(me, item.id) then
      return
    end
  end
  -- Nothing is cutting: the hold is full, the rock is gone, or it is time to begin.
  local capacity = Items.ShipStats(state, ship.id).cargo
  local used = Items.CargoUsed(state, ship.id)
  if capacity - used < math.max(2, 0.03 * capacity) then
    goIn()
    return
  end
  local reach = math.huge
  for _, item in lasers do
    reach = math.min(reach, (Modules.byId[item.type].miner :: Modules.Miner).range)
  end
  local rock: System.Object?, least = nil, math.huge
  for _, object in Space.Describe(state, system).objects do
    if object.kind == "asteroid" and object.site == post.id and Mining.Left(state, object) > 0 then
      local far = Space.Distance(object :: any, me :: any)
      if far < least then
        rock, least = object, far
      end
    end
  end
  if rock == nil then
    -- The belt is mined out: in with what there is, or wait for it to grow back.
    if used > 0.03 * capacity then
      goIn()
    elseif me.mode ~= "stop" then
      give(state, { kind = "Stop", actor = ship.id }, events)
    end
    return
  end
  if Space.Gap(me :: any, rock :: any) > reach * 0.8 then
    if not (me.mode == "approach" and me.target == rock.id) then
      give(state, { kind = "Approach", actor = ship.id, target = rock.id, range = reach * 0.5 }, events)
    end
    return
  end
  local locked, targeted = false, false
  for _, lock in me.vitals.locks do
    if lock.target == rock.id then
      targeted, locked = true, lock.locked
    end
  end
  if not targeted then
    me.vitals.locks = {}
    give(state, { kind = "LockTarget", actor = ship.id, target = rock.id }, events)
  elseif locked then
    for _, item in lasers do
      give(state, { kind = "ActivateModule", actor = ship.id, item = item.id, target = rock.id }, events)
    end
  end
end

-- What a hired pilot does with their ship this tick. 'place' is theirs
-- in the list, which is where they keep station.
local function fly(state: State.State, wing: State.Wingman, ship: State.Ship, place: number, events: { Event })
  local mine = state.ships[state.player.ship]
  local lead = state.balls[mine.id]
  local me = state.balls[ship.id]
  if me and me.warp and me.warp.stage == "warp" then
    return
  end

  if wing.order == "mine" then
    work(state, wing, ship, events)
    return
  elseif wing.order == "stay" then
    -- Dock at the nearest station, and wait.
    if me and not (me.intent and me.intent.kind == "dock") then
      local station = nearestStation(state, me)
      if station then
        give(state, { kind = "Dock", actor = ship.id, target = station.id }, events)
      elseif me.mode ~= "stop" then
        give(state, { kind = "Stop", actor = ship.id }, events)
      end
    end
    return
  end

  if me == nil then
    -- Docked: out when the player is out, or is somewhere else.
    if lead ~= nil or mine.docked ~= ship.docked then
      give(state, { kind = "Undock", actor = ship.id }, events)
    end
    return
  end
  mend(state, me, me.vitals.scrambled or wing.target ~= 0, events)

  -- A pilot who is held where they are fights whoever is doing it.
  local held = me.vitals.scrambled
  local leadSystem = if lead then lead.system else Space.SystemOf(state, mine.docked)
  local together = lead ~= nil and lead.system == me.system and lead.grid ~= 0 and lead.grid == me.grid
  if not held then
    if me.system ~= leadSystem then
      -- The next gate on the way to the player.
      travel(state, me, leadSystem, events)
      return
    elseif lead == nil then
      -- The player is docked here: dock too.
      if not (me.intent and me.intent.kind == "dock" and me.intent.target == mine.docked) then
        give(state, { kind = "Dock", actor = ship.id, target = mine.docked }, events)
      end
      return
    end
    -- Where the player is going, go too.
    local intent = lead.intent
    if intent then
      if not (me.intent and me.intent.kind == intent.kind and me.intent.target == intent.target) then
        give(state, { kind = if intent.kind == "dock" then "Dock" else "Jump", actor = ship.id, target = intent.target }, events)
      end
      return
    end
    local going = lead.warp
    if going then
      if me.warp and me.warp.target == going.target then
        return
      end
      -- (as far off it as the player means to arrive)
      local body = Space.Body(state, going.target)
      if body then
        local off = math.sqrt((going.tx - body.x) ^ 2 + (going.ty - body.y) ^ 2 + (going.tz - body.z) ^ 2)
        if give(state, { kind = "WarpTo", actor = ship.id, target = body.id, range = math.max(0, off - body.radius - lead.radius) }, events) then
          return
        end
      end
    end
    if not together then
      -- Left behind in the system: to where the player is, once they
      -- have got there.
      if me.warp == nil and lead.grid ~= 0 then
        if not give(state, { kind = "WarpTo", actor = ship.id, target = lead.id, range = 1000 }, events)
          and not (me.mode == "approach" and me.target == lead.id) then
          give(state, { kind = "Approach", actor = ship.id, target = lead.id, range = 1000 }, events)
        end
      end
      return
    end
  end

  -- On the player's grid, or held on another: fight what has been
  -- pointed out, or whoever is after the fleet, or keep station.
  -- (one with a remote repairer mends whoever of the fleet is worst hurt)
  local mending = Mend.Tend(state, me, side(state), events)
  local prey = state.balls[wing.target]
  if prey == nil or prey.system ~= me.system or prey.grid ~= me.grid then
    wing.target = 0
    prey = state.balls[Pirates.Hunting(state, me)]
  end
  if prey then
    fight(state, me, prey, events)
  else
    -- (nobody to fight: let go of everybody but those being mended)
    for at = #me.vitals.locks, 1, -1 do
      if not mending[me.vitals.locks[at].target] then
        table.remove(me.vitals.locks, at)
      end
    end
    if together and lead and not (me.mode == "keep" and me.target == lead.id) then
      give(state, { kind = "KeepAtRange", actor = ship.id, target = lead.id, range = 500 + 400 * place }, events)
    end
  end
end

-- Once a tick: wages, and what every hired pilot does.
function Fleet.Step(state: State.State, events: { Event })
  for place, id in table.clone(state.fleetIds) do
    local wing = state.fleet[id]
    if state.tick - wing.paid >= DAY then
      if state.wallet < wing.wage then
        quit(state, wing, events)
        continue
      end
      Wallet.Pay(state, -wing.wage, "wages", events)
      wing.paid += DAY
    end
    local ship = state.ships[wing.ship]
    if wing.ship ~= 0 and ship == nil then
      -- Their ship has been destroyed: they are back on the list.
      table.insert(events, { kind = "WingmanLost", pilot = wing.id, name = wing.name })
      wing.ship, wing.target = 0, 0
    elseif ship then
      fly(state, wing, ship, place, events)
    end
  end
end

return Fleet
