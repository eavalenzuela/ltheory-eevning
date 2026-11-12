--!strict
-- The fleet: pilots hired to fly the player's other ships beside their
-- own.
--
-- A station has a few pilots looking for work each day. One is hired
-- for a fee, is paid a wage every day after, and brings one thing: how
-- good they are, a grade from 1 to 4, which is the level every skill
-- counts as for a ship they fly and decides how big a hull they can be
-- given (a frigate at 1, a battleship at 4). The player commands as
-- many as their Leadership, and a corporation of theirs has places for
-- a few more (Assets/Corporation). What the pilots cost and what they
-- bring in is the corporation's business, where there is one, and the
-- player's own where there is not.
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
-- A pilot whose ship is docked can be set to haul: what there is of a
-- kind (ore, minerals, what colonies make, components, or all of
-- these) in the player's hangar at that station is carried, a hold at
-- a time, to another station, in the system or systems away, and put
-- in the player's hangar there. With nothing left to carry they wait
-- where the goods were, and go again when there are more.
--
-- A haul can be a round of several stations: the one the ship is
-- docked at and as many as four more to collect at, in the order
-- given, and one to deliver to. The pilot goes round the stops that
-- have something for them, in that order, taking at each what fits,
-- and then delivers: at once when the hold is full, and otherwise when
-- there is nothing more further round. They know what is in the
-- player's hangars (it is on the books), so they fly to no stop for
-- nothing; and with nothing anywhere they wait at the first.
--
-- And a pilot can be told to sell what they bring in, mined or
-- carried: it goes to the market of the station they bring it to, if
-- that has one, at what the market gives, and into the hangar if not.
--
-- A pilot whose ship is docked can be sent to buy: so many of a thing,
-- at the market of another station, for no more than so much each.
-- They go there, buy what the hold takes, bring it back to the station
-- they were sent from and put it in the player's hangar, and go again
-- until it is all brought. The corporation pays, where there is one.
-- What a market asks rises with every unit it sells, so "no more than
-- so much each" is on the average of a purchase; and with nothing more
-- to be had under that price, or nothing left to pay with, they bring
-- what they have and say so. Done, they wait where they brought it.
--
-- Where the player is not, a hired pilot is on their own. Pirates come
-- for them as they come for the player (Tactical/Pirates), half as
-- often, and the fight is fought as any is; a pilot who is gone for
-- says so. A pirate they destroy with the player elsewhere pays half
-- its bounty (Tactical/Aftermath). Two orders are for that:
--   - patrol: the armed pilots with the player (or the one named) hold
--     the place the player is at. They fight whatever pirates come
--     there, and one badly hurt goes in to the nearest station, is
--     mended for what mending costs, and comes out again.
--   - guard: one pilot goes where another hired pilot goes, as the rest
--     go where the player goes: beside a miner at their belt, or a
--     hauler on their run, and fights whoever comes for either.
--
-- A pilot whose wage cannot be paid leaves, and the ship they flew is
-- found at the player's home station.
--
-- A hired pilot uses the drones in their ship's bay (Tactical/Drones)
-- by themselves: as many as their hull controls and their grade allows
-- go out when there is something for them to do (somebody to fight, or
-- a rock being cut), the fighting ones at whoever the pilot is
-- fighting, and are called in again when there is not. And a pilot
-- does not leave them behind: before going anywhere of their own
-- accord they call them in, and wait for any that is too far off to be
-- taken aboard. (One who is running for a station with a ship that is
-- going to pieces does not wait.)
--
-- (The beginning of M7. Not yet: loyalty.)

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Combat = require("@lt/Core/Tactical/Combat")
local Constants = require("@lt/Core/Data/Constants")
local Corporation = require("@lt/Core/Assets/Corporation")
local Digger = require("@lt/Core/Tactical/Digger")
local DroneKinds = require("@lt/Core/Data/Drones")
local Drones = require("@lt/Core/Tactical/Drones")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Mend = require("@lt/Core/Tactical/Mend")
local Items = require("@lt/Core/Assets/Items")
local Market = require("@lt/Core/Assets/Market")
local Modules = require("@lt/Core/Data/Modules")
local Names = require("@lt/Core/Describe/Names")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Stations = require("@lt/Core/Assets/Stations")
local System = require("@lt/Core/Describe/System")
local Types = require("@lt/Core/Data/Types")
local Vitals = require("@lt/Core/Tactical/Vitals")

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

-- A hired pilot learns by doing: a point of experience for every
-- thousand credits of bounty on a pirate destroyed on a grid they are
-- flying on (whoever of the fleet fired the shot), and one for every
-- fifty units of ore they bring in. Enough of it and they go up a
-- grade, to 5 at most (a grade nobody is hired at), and are paid as
-- that grade is.
Fleet.BEST = 5

-- The experience it takes to go up from a grade.
function Fleet.Needed(skill: number): number
  return 200 * skill * skill
end

-- Give a pilot experience, and promote them if it is enough.
local function learn(state: State.State, wing: State.Wingman, points: number, events: { Event })
  if wing.skill >= Fleet.BEST or points <= 0 then
    return
  end
  wing.experience += points
  while wing.skill < Fleet.BEST and wing.experience >= Fleet.Needed(wing.skill) do
    wing.experience -= Fleet.Needed(wing.skill)
    wing.skill += 1
    wing.wage = Fleet.Wage(wing.skill)
    table.insert(events, { kind = "PilotPromoted", pilot = wing.id, name = wing.name, skill = wing.skill })
  end
  if wing.skill >= Fleet.BEST then
    wing.experience = 0
  end
end

-- A pirate with so much bounty on it has been destroyed on a grid by
-- the player's side: every hired pilot flying there learns from it.
function Fleet.Credit(state: State.State, system: number, grid: number, bounty: number, events: { Event })
  local points = bounty // 1000
  for _, id in state.fleetIds do
    local wing = state.fleet[id]
    local ball = state.balls[wing.ship]
    if ball and ball.system == system and ball.grid == grid and grid ~= 0 then
      learn(state, wing, points, events)
    end
  end
end

-- What a pilot set to haul can be told to carry: the things of one
-- category, or of all of these.
Fleet.CARGO = { "ore", "mineral", "moon", "planetary", "component", "all" }
-- The stations a haul can collect at, the one the ship is docked at among them.
Fleet.STOPS = 5
-- How many jumps off a market can be, to be offered as a place to send
-- a pilot to buy at. (They will go further, sent.)
Fleet.SHOPS = 5

-- Whether a type is of a kind a hauler carries.
function Fleet.Carries(kind: string, type: string): boolean
  local category = Types.Info(type).category
  if kind == "all" then
    return category == "ore" or category == "mineral" or category == "moon" or category == "planetary" or category == "component"
  end
  return category == kind and table.find(Fleet.CARGO, kind) ~= nil
end

-- How many pilots the player can have hired: as many as their
-- Leadership, and with that what places a corporation of theirs has.
-- (Leadership comes first: a corporation of nobody who can lead has
-- nobody.)
function Fleet.Max(state: State.State): number
  local lead = math.max(0, state.skills.leadership or 0)
  return if lead > 0 then lead + Corporation.Staff(state) else 0
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
      -- (the first at the station a new pilot starts at is always
      -- somebody new: there is always one a new pilot can afford)
      if slot == 1 and station == Stations.Starter(state) then
        skill = 1
      end
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
Fleet.GRADE = { frigate = 1, industrial = 1, destroyer = 2, barge = 2, cruiser = 3, battleship = 4, freighter = 4 } :: { [string]: number }

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

-- The hired pilots a "mine here" would set to work: those (or the one
-- named) on the player's grid whose ship has a mining laser.
local function diggers(state: State.State, only: State.Wingman?): { State.Wingman }
  local lead = state.balls[state.player.ship]
  local found: { State.Wingman } = {}
  for _, id in state.fleetIds do
    local wing = state.fleet[id]
    local ball = state.balls[wing.ship]
    if (only == nil or only == wing) and lead and ball and ball.system == lead.system and ball.grid == lead.grid
      and #Digger.Lasers(state, wing.ship) > 0 then
      table.insert(found, wing)
    end
  end
  return found
end

-- The hired pilots a "patrol here" would set to it: those (or the one
-- named) on the player's grid whose ship has a weapon.
local function guards(state: State.State, only: State.Wingman?): { State.Wingman }
  local lead = state.balls[state.player.ship]
  local found: { State.Wingman } = {}
  for _, id in state.fleetIds do
    local wing = state.fleet[id]
    local ball = state.balls[wing.ship]
    if (only == nil or only == wing) and lead and ball and ball.system == lead.system and ball.grid == lead.grid then
      for _, item in Items.Fitted(state, wing.ship) do
        if Modules.byId[item.type].weapon then
          table.insert(found, wing)
          break
        end
      end
    end
  end
  return found
end

-- The hired pilot who flies a ship, if one does.
function Fleet.Flying(state: State.State, ship: number): State.Wingman?
  for _, id in state.fleetIds do
    if ship ~= 0 and state.fleet[id].ship == ship then
      return state.fleet[id]
    end
  end
  return nil
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
      return false, if Fleet.Max(state) == 0 then "needs Leadership 1"
        elseif Corporation.Founded(state) then `{state.corporation.name} has places for {Fleet.Max(state)} pilots and no more`
        else `Leadership {Fleet.Max(state)} commands no more pilots`
    elseif not Corporation.Afford(state, found.fee) then
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
    elseif what == "sell" or what == "keep" then
      -- (what they bring in is sold, or kept: said to one pilot)
      if wing == nil then
        return false, "that is said to one pilot"
      end
      return true
    elseif what == "guard" then
      -- (one pilot, and another's ship for them to go with)
      if wing == nil then
        return false, "that is said to one pilot"
      elseif state.ships[wing.ship] == nil then
        return false, `{wing.name} has no ship`
      end
      local ward = Fleet.Flying(state, command.target or 0)
      if ward == nil then
        return false, "pick the ship of another of your pilots for them to guard"
      elseif ward == wing then
        return false, "nobody guards themselves"
      elseif ward.order == "guard" and ward.ward == wing.id then
        return false, `{ward.name} is guarding {wing.name}`
      end
      return true
    elseif what == "patrol" then
      local me = state.balls[ship.id]
      if me == nil then
        return false, "docked"
      elseif Space.Object(state, me.grid) == nil then
        return false, "there is nothing here to hold: go to a belt, a gate or a station"
      elseif #guards(state, wing) == 0 then
        return false, "no hired pilot here has a weapon fitted"
      end
      return true
    elseif what == "haul" then
      if wing == nil then
        return false, "that is said to one pilot"
      end
      local theirs = state.ships[wing.ship]
      if theirs == nil then
        return false, `{wing.name} has no ship`
      elseif theirs.docked == 0 then
        return false, `{wing.name} has to be docked where the goods are`
      elseif table.find(Fleet.CARGO, command.type or "") == nil then
        return false, "no such cargo"
      end
      local to = Space.Object(state, command.target or 0)
      local starbase = if to then state.starbases[to.id] else nil
      if to == nil or to.kind ~= "station" or (starbase ~= nil and starbase.ready > state.tick) then
        return false, "that is not a station to carry to"
      elseif to.id == theirs.docked then
        return false, "that is where the goods are"
      elseif #Galaxy.Route(state.galaxy, Space.SystemOf(state, theirs.docked), Space.SystemOf(state, to.id)) == 0 then
        return false, "there is no way there"
      end
      -- (and the further stations to collect at, if it is a round of several)
      local stops: { number } = command.stops or {}
      if #stops + 1 > Fleet.STOPS then
        return false, `a round has {Fleet.STOPS} stations to collect at, at most`
      end
      for index, id in stops do
        local stop = Space.Object(state, id)
        local built = state.starbases[id]
        if stop == nil or stop.kind ~= "station" or (built ~= nil and built.ready > state.tick) then
          return false, "that is not a station to collect at"
        elseif id == to.id then
          return false, "what is collected at the station it is carried to is there already"
        elseif id == theirs.docked or table.find(stops, id) ~= index then
          return false, "a station is collected at once a round"
        elseif #Galaxy.Route(state.galaxy, Space.SystemOf(state, theirs.docked), Space.SystemOf(state, id)) == 0 then
          return false, "there is no way there"
        end
      end
      return true
    elseif what == "buy" then
      if wing == nil then
        return false, "that is said to one pilot"
      end
      local theirs = state.ships[wing.ship]
      if theirs == nil then
        return false, `{wing.name} has no ship`
      elseif theirs.docked == 0 then
        return false, `{wing.name} has to be docked where it is to be brought`
      end
      local info = Types.Get(command.type or "")
      local quantity, price = command.quantity or 0, command.price or 0
      if info == nil or Market.Index(info.id) == nil then
        return false, "no such thing to buy"
      elseif quantity < 1 or quantity % 1 ~= 0 then
        return false, "how many?"
      elseif price <= 0 then
        return false, "for how much each, at most?"
      end
      -- (the market may be in a system nobody has been to yet)
      local at = Space.Peek(state, command.target or 0)
      if at == nil or at.kind ~= "station" or not Stations.Has(state, at.id, "market") then
        return false, "that is not a station with a market"
      elseif at.id == theirs.docked then
        return false, "that is this station: buy it here yourself"
      elseif #Galaxy.Route(state.galaxy, Space.SystemOf(state, theirs.docked), Space.SystemOf(state, at.id)) == 0 then
        return false, "there is no way there"
      elseif info.volume > Items.ShipStats(state, theirs.id).cargo then
        return false, `one does not fit in {wing.name}'s hold`
      end
      -- (and one, at least, is to be had there now for what was said, and can be paid for)
      local units, cost = Market.Asks(state, at.id, info.id, 1)
      if units < 1 then
        return false, "that market has none"
      elseif cost > price then
        return false, `one is {cost} credits there now`
      elseif not Corporation.Afford(state, cost) then
        return false, "not enough credits"
      end
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
    Corporation.Spend(state, found.fee, "hiring", events)
    local wing: State.Wingman = { id = State.NewId(state), name = found.name, skill = found.skill, wage = found.wage,
      paid = state.tick, ship = 0, order = "follow", target = 0, post = 0, base = 0, hauled = 0, experience = 0,
      stops = {}, leg = 0, want = "", need = 0, limit = 0,
      cargo = "", sell = false, earned = 0, ward = 0, alarm = false }
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
  elseif kind == "FleetOrder" and (command.what == "sell" or command.what == "keep") then
    wing.sell = command.what == "sell"
    table.insert(events, { kind = "FleetOrdered", what = command.what, target = 0 })
  elseif kind == "FleetOrder" and command.what == "guard" then
    local ward = Fleet.Flying(state, command.target :: number) :: State.Wingman
    wing.order, wing.target, wing.ward = "guard", 0, ward.id
    table.insert(events, { kind = "FleetOrdered", what = "guard", target = ward.ship })
  elseif kind == "FleetOrder" and command.what == "patrol" then
    -- The place the player is at, and the station nearest it to mend at.
    local me = state.balls[ship.id]
    local base = nearestStation(state, me)
    for _, each in guards(state, wing) do
      each.order, each.target = "patrol", 0
      each.post, each.base = me.grid, if base then base.id else 0
    end
    table.insert(events, { kind = "FleetOrdered", what = "patrol", target = me.grid })
  elseif kind == "FleetOrder" and command.what == "haul" then
    -- From the station their ship is docked at, to the one named.
    wing.order, wing.target = "haul", 0
    wing.post, wing.base = state.ships[wing.ship].docked, command.target :: number
    wing.cargo = command.type :: string
    -- (the round: here first, and then the further stations, in the order given)
    wing.stops, wing.leg = { wing.post }, 0
    local further: { number } = command.stops or {}
    for _, id in further do
      table.insert(wing.stops, id)
    end
    table.insert(events, { kind = "FleetOrdered", what = "haul", target = wing.base })
  elseif kind == "FleetOrder" and command.what == "buy" then
    -- To the market named, and back to the station their ship is docked
    -- at. (The market's system is described now, if it never was.)
    local market = command.target :: number
    Space.Describe(state, Space.SystemOf(state, market))
    wing.order, wing.target = "buy", 0
    wing.post, wing.base = market, state.ships[wing.ship].docked
    wing.want, wing.need, wing.limit = command.type :: string, command.quantity :: number, command.price :: number
    wing.stops, wing.leg = {}, 0
    table.insert(events, { kind = "FleetOrdered", what = "buy", target = market, pilot = wing.id, name = wing.name,
      type = wing.want, quantity = wing.need, price = wing.limit })
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
    if module.weapon or (module.hex and not Modules.Friendly(module)) then
      if locked then
        give(state, { kind = "ActivateModule", actor = me.id, item = item.id, target = prey.id }, events)
      end
    elseif forFights(module) then
      give(state, { kind = "ActivateModule", actor = me.id, item = item.id }, events)
    end
  end
end

-- A pilot's own drones, out: whatever is in the bay that can be
-- controlled, any that were on their way in turned round, and those
-- that fight pointed at 'prey' (with none, they do what drones do with
-- nothing pointed out: Tactical/Drones).
local function loose(state: State.State, me: State.Ball, prey: State.Ball?, events: { Event })
  local launch: State.Command = { kind = "LaunchDrones", actor = me.id }
  if Drones.Validate(state, launch) then
    Drones.Apply(state, launch, events)
  end
  local astray = false
  for _, drone in Drones.Out(state, me.id) do
    drone.returning = false
    -- (only those that fight are pointed at anybody)
    astray = astray or (prey ~= nil and drone.target ~= prey.id and DroneKinds.byId[drone.type].role == "combat")
  end
  if prey and astray then
    local engage: State.Command = { kind = "EngageDrones", actor = me.id, target = prey.id }
    if Drones.Validate(state, engage) then
      Drones.Apply(state, engage, events)
    end
  end
end

-- And called in. True while any of them is still too far off to be
-- taken aboard if the ship left now.
local function callIn(state: State.State, me: State.Ball): boolean
  local waiting = false
  for _, drone in Drones.Out(state, me.id) do
    drone.returning, drone.target = true, 0
    waiting = waiting or not drone.near
  end
  return waiting
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

-- Unload what a docked ship holds of a kind at the station it is docked
-- at: into the player's hangar there, or to the market, for a pilot who
-- sells, if the station has one and trades in the thing. Returns the
-- units unloaded, what selling made, and the volume of it all.
local function unload(state: State.State, wing: State.Wingman, ship: State.Ship, kind: string, events: { Event }): (number, number, number)
  local station = ship.docked
  local sells = wing.sell and Stations.Has(state, station, "market")
  local units, revenue, volume = 0, 0, 0
  for _, item in Items.In(state, ship.id, "cargo") do
    if Fleet.Carries(kind, item.type) then
      units += item.quantity
      volume += item.quantity * Types.Info(item.type).volume
      if sells and Market.Index(item.type) then
        revenue += Market.Sell(state, station, item, item.quantity, events, true)
      else
        Items.Add(state, item.type, item.quantity, station, "hangar")
        Items.Take(state, item, item.quantity)
      end
    end
  end
  wing.hauled += units
  wing.earned += revenue
  return units, revenue, volume
end

-- Whether the player's hangar at a station has anything of a kind.
local function stocked(state: State.State, station: number, kind: string): boolean
  for _, item in Items.In(state, station, "hangar") do
    if Fleet.Carries(kind, item.type) and item.quantity > 0 then
      return true
    end
  end
  return false
end

-- Where a pilot set to haul goes next, and why: the next station of
-- their round, after the last one loaded at, that has something for
-- them ("collect"), unless the hold is full; with none, the station it
-- is all carried to, if they carry anything ("deliver"); and with
-- nothing aboard and nothing anywhere, the first station of the round,
-- to wait at ("wait").
function Fleet.HaulGoal(state: State.State, wing: State.Wingman, ship: State.Ship): (number, string)
  local carrying = false
  for _, item in Items.In(state, ship.id, "cargo") do
    carrying = carrying or Fleet.Carries(wing.cargo, item.type)
  end
  local capacity = Items.ShipStats(state, ship.id).cargo
  local full = carrying and capacity - Items.CargoUsed(state, ship.id) < math.max(2, 0.03 * capacity)
  if not full then
    for index, stop in wing.stops do
      -- (a round that has not begun has every stop before it; one that
      -- has, only those further on)
      if index > wing.leg and Space.Object(state, stop) and stocked(state, stop, wing.cargo) then
        return stop, "collect"
      end
    end
  end
  if carrying then
    return wing.base, "deliver"
  end
  return wing.stops[1] or wing.post, "wait"
end

-- What a pilot set to haul does: round the stations they collect at
-- that have something for them, a hold's worth, to the station it is
-- carried to with it, and round again; and with nothing to carry
-- anywhere, they wait at the first.
local function carry(state: State.State, wing: State.Wingman, ship: State.Ship, events: { Event })
  local to = Space.Object(state, wing.base)
  if to == nil or #wing.stops == 0 or Space.Object(state, wing.stops[1]) == nil then
    wing.order = "stay"
    return
  end
  local me = state.balls[ship.id]
  if me == nil then
    local at = table.find(wing.stops, ship.docked)
    if ship.docked == to.id then
      local units, revenue, volume = unload(state, wing, ship, wing.cargo, events)
      if units > 0 then
        table.insert(events, { kind = "HaulDelivered", pilot = wing.id, name = wing.name, units = units, station = to.id, revenue = revenue })
        -- (a point of experience for every hundred cubic metres brought)
        learn(state, wing, volume // 100, events)
      end
      -- (and the round begins again)
      wing.leg = 0
    elseif at and at > wing.leg then
      -- (the hangar is looked over now and then, not every second)
      if (state.tick + wing.id) % 5 ~= 0 then
        return
      end
      local free = Items.ShipStats(state, ship.id).cargo - Items.CargoUsed(state, ship.id)
      local loaded = false
      for _, item in Items.In(state, ship.docked, "hangar") do
        if Fleet.Carries(wing.cargo, item.type) then
          local each = Types.Info(item.type).volume
          local take = if each > 0 then math.min(item.quantity, math.floor(free / each)) else item.quantity
          if take > 0 then
            Items.Add(state, item.type, take, ship.id, "cargo")
            Items.Take(state, item, take)
            free -= take * each
            loaded = true
          end
        end
      end
      if loaded then
        wing.leg = at
      end
    end
    -- (out, unless where they are is where they are to be: waiting for
    -- cargo at the first station, with nothing aboard and nothing anywhere)
    local goal, why = Fleet.HaulGoal(state, wing, ship)
    if goal == ship.docked and why ~= "deliver" then
      return
    end
    give(state, { kind = "Undock", actor = ship.id }, events)
    return
  end
  mend(state, me, false, events)
  -- (on the way in somewhere, they go on: where to is looked at again
  -- when they have got there, or come out of a gate)
  if me.intent and (me.intent.kind == "dock" or me.intent.kind == "jump") then
    return
  end
  local goal = Space.Object(state, (Fleet.HaulGoal(state, wing, ship)))
  if goal == nil then
    return
  end
  local system = Space.SystemOf(state, goal.id)
  if me.system ~= system then
    travel(state, me, system, events)
  else
    give(state, { kind = "Dock", actor = ship.id, target = goal.id }, events)
  end
end

-- How many of what a pilot was sent to buy are in their hold.
function Fleet.Bought(state: State.State, wing: State.Wingman, ship: State.Ship): number
  local aboard = 0
  for _, item in Items.In(state, ship.id, "cargo") do
    if item.type == wing.want then
      aboard += item.quantity
    end
  end
  return aboard
end

-- What a pilot sent to buy does: to the market, where they buy what the
-- hold takes of what is still wanted, for no more than they were told
-- to pay and with what there is to pay with; back with it to where they
-- were sent from; and again, until it is all brought. With nothing more
-- to be had they say why, bring what they have, and the errand is over.
local function shop(state: State.State, wing: State.Wingman, ship: State.Ship, events: { Event })
  local market, home = Space.Object(state, wing.post), Space.Object(state, wing.base)
  local info = Types.Get(wing.want)
  if market == nil or home == nil or info == nil then
    wing.order = "stay"
    return
  end
  local me = state.balls[ship.id]
  if me == nil then
    if ship.docked == home.id then
      -- (what is aboard of it, into the hangar)
      local units = 0
      for _, item in Items.In(state, ship.id, "cargo") do
        if item.type == wing.want then
          units += item.quantity
          Items.Add(state, item.type, item.quantity, home.id, "hangar")
          Items.Take(state, item, item.quantity)
        end
      end
      if units > 0 then
        wing.hauled += units
        table.insert(events, { kind = "BuyDelivered", pilot = wing.id, name = wing.name, type = wing.want, units = units,
          station = home.id, left = wing.need })
        -- (a point of experience for every hundred cubic metres brought)
        learn(state, wing, (units * info.volume) // 100, events)
      end
      -- (no room for one more, with the hold as it is: that is the end of it)
      local room = Items.ShipStats(state, ship.id).cargo - Items.CargoUsed(state, ship.id)
      if wing.need > 0 and room < info.volume then
        table.insert(events, { kind = "BuyEnded", pilot = wing.id, name = wing.name, type = wing.want, short = wing.need,
          station = home.id, reason = "there is no room in their hold" })
        wing.need = 0
      end
      if wing.need <= 0 then
        -- (all brought, or all there was to bring: they wait here)
        wing.order, wing.want, wing.need = "stay", "", 0
        return
      end
    elseif ship.docked == market.id and wing.need > 0 then
      -- (the market is looked over now and then, not every second)
      if (state.tick + wing.id) % 5 ~= 0 then
        return
      end
      local free = Items.ShipStats(state, ship.id).cargo - Items.CargoUsed(state, ship.id)
      local fits = if info.volume > 0 then math.floor(free / info.volume) else wing.need
      local purse = state.wallet + (if Corporation.Founded(state) then math.max(0, state.corporation.wallet) else 0)
      local most = math.min(wing.need, fits)
      local sells = Stations.Has(state, market.id, "market")
      local units = if sells then Market.Within(state, market.id, wing.want, most, wing.limit, purse) else 0
      if units > 0 then
        local cost = Market.Buy(state, market.id, wing.want, units, ship.id, "cargo", events, true)
        wing.need -= units
        table.insert(events, { kind = "BuyMade", pilot = wing.id, name = wing.name, type = wing.want, units = units, cost = cost,
          station = market.id })
      end
      if units < most then
        -- (fewer than the hold would take: there is no more for them here,
        -- and they bring what they have)
        local quote = if sells then Market.Quote(state, market.id, wing.want) else nil
        local reason = if quote == nil or quote.ask == nil or quote.stock < 1 then "there is no more to be had there"
          elseif quote.ask > wing.limit then `it is {math.ceil(quote.ask)} credits each there now`
          else "there is not the money for more"
        table.insert(events, { kind = "BuyEnded", pilot = wing.id, name = wing.name, type = wing.want, short = wing.need,
          station = market.id, reason = reason })
        wing.need = 0
      end
    end
    give(state, { kind = "Undock", actor = ship.id }, events)
    return
  end
  mend(state, me, false, events)
  if me.intent and (me.intent.kind == "dock" or me.intent.kind == "jump") then
    return
  end
  -- (to the market for more, with room for it; and home with what there is)
  local free = Items.ShipStats(state, ship.id).cargo - Items.CargoUsed(state, ship.id)
  local goal = if wing.need > 0 and free >= info.volume and Fleet.Bought(state, wing, ship) == 0 then market else home
  local system = Space.SystemOf(state, goal.id)
  if me.system ~= system then
    travel(state, me, system, events)
  else
    give(state, { kind = "Dock", actor = ship.id, target = goal.id }, events)
  end
end

-- Whether a pilot has a guard with them: another hired pilot set to
-- guard them, whose ship is on the grid theirs is on.
local function guarded(state: State.State, wing: State.Wingman, me: State.Ball): boolean
  for _, id in state.fleetIds do
    local other = state.fleet[id]
    local ball = state.balls[other.ship]
    if other.order == "guard" and other.ward == wing.id and ball and ball.system == me.system and ball.grid == me.grid
      and me.grid ~= 0 then
      return true
    end
  end
  return false
end

-- What a pilot set to mine does: to the belt, a rock after another
-- until the hold is full, in to the station with it, and out again.
-- Somebody after the fleet at the belt sends them in early.
local function work(state: State.State, wing: State.Wingman, ship: State.Ship, events: { Event })
  local post, base = Space.Object(state, wing.post), Space.Object(state, wing.base)
  if post == nil or base == nil or #Digger.Lasers(state, ship.id) == 0 then
    wing.order = "stay"
    return
  end
  local me = state.balls[ship.id]
  if me == nil then
    -- Docked: what was mined goes into the hangar (or is sold), and out again.
    local units, revenue = 0, 0
    if ship.docked == base.id then
      units, revenue = unload(state, wing, ship, "ore", events)
    end
    if units > 0 then
      table.insert(events, { kind = "OreDelivered", pilot = wing.id, name = wing.name, units = units, station = base.id, revenue = revenue })
      learn(state, wing, units // 50, events)
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

  -- At the belt: somebody after the fleet sends them in (unless they
  -- have a guard there to see to it), and so does a full hold or a belt
  -- with nothing left (Tactical/Digger).
  local hunted = Pirates.Hunting(state, me) ~= 0 and not guarded(state, wing, me)
  if hunted or not Digger.Work(state, me, post, events) then
    -- (the drones in first, unless there is no time for it)
    if callIn(state, me) and not hunted then
      return
    end
    me.vitals.locks = {}
    give(state, { kind = "Dock", actor = ship.id, target = base.id }, events)
  else
    -- (at work: what is in the drone bay works too)
    loose(state, me, nil, events)
  end
end

-- How much of its armour and hull a patrol's ship can lose before its
-- pilot takes it in to be mended.
Fleet.RETIRE = 0.4

-- What a pilot set to patrol does: to their post, and there whatever
-- pirates come are fought, the nearest first. Badly hurt, in to the
-- nearest station; mended there, for what it costs, and out again.
local function patrol(state: State.State, wing: State.Wingman, ship: State.Ship, events: { Event })
  local post = Space.Object(state, wing.post)
  local site = state.sites[wing.post]
  if post == nil or (site ~= nil and site.gone) then
    -- (the place is no more: back to the player)
    wing.order = "follow"
    return
  end
  local me = state.balls[ship.id]
  if me == nil then
    -- Docked: mended, if it can be paid for (if not, they wait until it can), and out.
    if ship.armorDamage + ship.hullDamage > 0 then
      local cost = Aftermath.RepairCost(state, ship)
      if not Corporation.Afford(state, cost) then
        return
      end
      Corporation.Spend(state, cost, "repairs", events)
      ship.armorDamage, ship.hullDamage = 0, 0
      table.insert(events, { kind = "ShipRepaired", ship = ship.id })
    end
    give(state, { kind = "Undock", actor = ship.id }, events)
    return
  end
  if me.intent and me.intent.kind == "dock" then
    return
  end
  local vitals = me.vitals
  if vitals.armor + vitals.hull < Fleet.RETIRE * (vitals.armorMax + vitals.hullMax) and not vitals.scrambled then
    local station = nearestStation(state, me)
    if station then
      -- (the drones are called, and not waited for)
      callIn(state, me)
      me.vitals.locks = {}
      give(state, { kind = "Dock", actor = ship.id, target = station.id }, events)
      table.insert(events, { kind = "PatrolRetired", pilot = wing.id, name = wing.name, station = station.id })
      return
    end
  end
  local system = Space.SystemOf(state, post.id)
  if me.system ~= system then
    travel(state, me, system, events)
    return
  elseif me.grid ~= post.id and not vitals.scrambled then
    if me.warp == nil and not give(state, { kind = "WarpTo", actor = ship.id, target = post.id, range = 0 }, events)
      and not (me.mode == "approach" and me.target == post.id) then
      give(state, { kind = "Approach", actor = ship.id, target = post.id, range = 0 }, events)
    end
    return
  end
  -- At the post: the nearest pirate there is, if there is one.
  local prey: State.Ball?, least = nil, math.huge
  for _, id in state.pilotIds do
    local other = state.balls[id]
    if other and state.ships[id].owner == "pirates" and other.system == me.system and other.grid == me.grid then
      local far = Space.Distance(other :: any, me :: any)
      if far < least then
        prey, least = other, far
      end
    end
  end
  mend(state, me, prey ~= nil, events)
  local mending = Mend.Tend(state, me, side(state), events)
  if prey then
    fight(state, me, prey, events)
    loose(state, me, prey, events)
  else
    callIn(state, me)
    for at = #me.vitals.locks, 1, -1 do
      if not mending[me.vitals.locks[at].target] then
        table.remove(me.vitals.locks, at)
      end
    end
    if not (me.mode == "orbit" and me.target == post.id) then
      give(state, { kind = "Orbit", actor = ship.id, target = post.id, range = 5000 }, events)
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
  elseif wing.order == "haul" then
    carry(state, wing, ship, events)
    return
  elseif wing.order == "buy" then
    shop(state, wing, ship, events)
    return
  elseif wing.order == "patrol" then
    patrol(state, wing, ship, events)
    return
  elseif wing.order == "stay" then
    -- Dock at the nearest station, and wait. (The drones in first.)
    if me and callIn(state, me) then
      return
    end
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

  -- One set to guard another pilot goes where that one goes, as the
  -- rest go where the player goes: from here on 'mine' and 'lead' are
  -- that pilot's ship. (If that pilot or their ship is no more, it is
  -- the player again.)
  if wing.order == "guard" then
    local ward = state.fleet[wing.ward]
    local theirs = if ward then state.ships[ward.ship] else nil
    if theirs then
      mine, lead = theirs, state.balls[theirs.id]
    else
      wing.order, wing.ward = "follow", 0
    end
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
  -- (and one set to guard stands and fights whoever is after anybody
  -- of the pilot's where they are, and catches their charge up after)
  local held = me.vitals.scrambled or (wing.order == "guard" and me.grid ~= 0 and Pirates.Hunting(state, me) ~= 0)
  local leadSystem = if lead then lead.system else Space.SystemOf(state, mine.docked)
  local together = lead ~= nil and lead.system == me.system and lead.grid ~= 0 and lead.grid == me.grid
  if not held then
    -- (about to go somewhere: the drones in first, and waited for)
    local leaving = me.system ~= leadSystem or lead == nil or lead.intent ~= nil or lead.warp ~= nil or not together
    if leaving and callIn(state, me) then
      return
    end
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
    loose(state, me, prey, events)
  else
    callIn(state, me)
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
      if not Corporation.Afford(state, wing.wage) then
        quit(state, wing, events)
        continue
      end
      Corporation.Spend(state, wing.wage, "wages", events)
      wing.paid += DAY
    end
    local ship = state.ships[wing.ship]
    if wing.ship ~= 0 and ship == nil then
      -- Their ship has been destroyed: they are back on the list.
      table.insert(events, { kind = "WingmanLost", pilot = wing.id, name = wing.name })
      wing.ship, wing.target = 0, 0
    elseif ship then
      fly(state, wing, ship, place, events)
      -- Somebody after them, with the player somewhere else: they say
      -- so, once for as long as it goes on.
      local ball = state.balls[ship.id]
      local lead = state.balls[state.player.ship]
      local alone = ball ~= nil and not (lead ~= nil and lead.system == ball.system and lead.grid == ball.grid)
      local hunted = ball ~= nil and alone and ball.grid ~= 0 and Pirates.Hunting(state, ball) ~= 0
      if ball and hunted and not wing.alarm then
        local at = Space.Object(state, ball.grid)
        table.insert(events, { kind = "FleetAttacked", pilot = wing.id, name = wing.name, grid = ball.grid,
          where = if at then at.name else state.galaxy.systems[ball.system].name })
      end
      wing.alarm = hunted
    end
  end
end

return Fleet
