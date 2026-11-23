--!strict
-- The ships a pilot keeps at a station: assembling a bought hull into a
-- ship, packing a ship up again into a hull for the market, naming one,
-- and changing which ship is being flown.
--
-- And stepping out of a ship into a capsule (the owner, 2026-11-23: "You
-- should also be able to exit your ship into your capsule"): docked, the
-- ship stays in the hangar; in space ("Ejecting anywhere"), it floats
-- where it was, nobody's flying it, to be boarded again from a capsule
-- close by. Left on grid with a station or citadel somebody else keeps,
-- it may be taken ("NPCs might steal if it's on grid with an NPC
-- station/citadel").
--
-- And the station that is the pilot's home: where they wake, in a
-- starter ship, when their capsule is destroyed (Tactical/Aftermath).
-- It is the station a new game begins at until the pilot takes a berth
-- at another: docked there, for a fee.

local Constants = require("@lt/Core/Data/Constants")
local Corporation = require("@lt/Core/Assets/Corporation")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")
local Starbases = require("@lt/Core/Assets/Starbases")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Vitals = require("@lt/Core/Tactical/Vitals")
local Wallet = require("@lt/Core/Assets/Wallet")

local Hangar = {}

export type Event = { [string]: any }

-- What a station charges to keep a berth for a pilot to wake in.
Hangar.HOME_FEE = 10000
-- How near a ship left in space a capsule must be to board it, m; how
-- long such a ship is let be on grid with a station or citadel somebody
-- else keeps, ticks; and the chance each hour after that it is taken.
-- (Mine.)
Hangar.BOARD_RANGE = 2500
Hangar.HOUR = math.ceil(3600 / Constants.TICK)
Hangar.THEFT = 0.25
-- The longest a ship's name may be.
Hangar.NAME = 32

local function isCapsule(ship: State.Ship): boolean
  return Ships.byId[ship.type].class == "capsule"
end

-- A ship of the pilot's left in space, nobody aboard, and its ball.
local function adrift(state: State.State, ship: State.Ship?): State.Ball?
  if ship == nil or ship.owner ~= "player" or ship.left == nil or ship.pilot ~= 0 then
    return nil
  end
  return state.balls[ship.id]
end
Hangar.Adrift = function(state: State.State, ship: State.Ship?): boolean
  return adrift(state, ship) ~= nil
end

-- The player's ships docked at a station, in id order.
function Hangar.Ships(state: State.State, station: number): { State.Ship }
  local found = {}
  for _, id in state.shipIds do
    local ship = state.ships[id]
    if ship.owner == "player" and State.At(ship) == station then
      table.insert(found, ship)
    end
  end
  return found
end

function Hangar.Validate(state: State.State, command: State.Command): (boolean, string?)
  local ship = state.ships[command.actor]
  if ship == nil then
    return false, "no such ship"
  end
  if command.kind == "LeaveShip" then
    local ball = state.balls[ship.id]
    if isCapsule(ship) then
      return false, "you are in your capsule already"
    elseif ship.docked == 0 and ball == nil then
      return false, "no such ship"
    elseif ball and (ball.warp ~= nil or ball.transit ~= nil) then
      return false, "not while it is under way"
    end
    return true
  elseif command.kind == "RenameShip" then
    local other = state.ships[command.target or 0]
    local name = string.match(command.name or "", "^%s*(.-)%s*$") or ""
    if other == nil or other.owner ~= "player" or (other.id ~= ship.id and (State.At(ship) == 0 or State.At(other) ~= State.At(ship))) then
      return false, "that ship is not here"
    elseif other.pilot ~= 0 then
      return false, "somebody else flies that ship"
    elseif name == "" then
      return false, "give it a name"
    elseif #name > Hangar.NAME then
      return false, `a name is {Hangar.NAME} letters at most`
    elseif string.find(name, "[%c=]") then
      return false, "a name cannot have that in it"
    end
    return true
  elseif command.kind == "BoardShip" and State.At(ship) == 0 then
    -- (in space: a ship of the pilot's left there, from the capsule, close by)
    local other = state.ships[command.target or 0]
    local there = adrift(state, other)
    local me = state.balls[ship.id]
    if other == nil or there == nil or me == nil or there.system ~= me.system then
      return false, "that ship is not here"
    elseif not isCapsule(ship) then
      return false, "a ship in space is boarded from a capsule: leave yours first"
    elseif Space.Gap(me :: any, there :: any) > Hangar.BOARD_RANGE then
      return false, `get within {Hangar.BOARD_RANGE} m of it`
    end
    local missing = Skills.Missing(Skills.Needs(other.type), state.skills)
    if missing then
      return false, Skills.Describe(missing)
    end
    return true
  elseif State.At(ship) == 0 then
    return false, "not docked"
  end
  if command.kind == "Assemble" then
    local item = state.items[command.item or 0]
    -- (in the pilot's hangar, or the corporation's: a ship of its, then)
    if item == nil or item.holder ~= State.At(ship) or (item.place ~= "hangar" and item.place ~= "corporate") then
      return false, "that is not in the hangar here"
    elseif Ships.byId[item.type] == nil then
      return false, "that is not a hull"
    end
    return true
  elseif command.kind == "BoardShip" then
    local other = state.ships[command.target or 0]
    if other == nil or other.owner ~= "player" or other.docked == 0 or other.docked ~= State.At(ship) then
      return false, "that ship is not here"
    elseif other.id == ship.id then
      return false, "already aboard"
    elseif other.pilot ~= 0 then
      return false, "a member of your fleet flies that ship"
    elseif other.member then
      return false, "that ship is assigned to a member: take it off them first"
    end
    local missing = Skills.Missing(Skills.Needs(other.type), state.skills)
    if missing then
      return false, Skills.Describe(missing)
    end
    return true
  elseif command.kind == "Repackage" then
    -- (the owner, 2026-11-16: "can't repackage ships to sell?")
    local other = state.ships[command.target or 0]
    if other == nil or other.owner ~= "player" or other.docked ~= State.At(ship) then
      return false, "that ship is not here"
    elseif other.id == state.player.ship or other.id == ship.id then
      return false, "you are aboard it: board another first"
    elseif other.pilot ~= 0 then
      return false, "a member of your fleet flies that ship"
    elseif other.member then
      return false, "that ship is assigned to a member: take it off them first"
    elseif Ships.byId[other.type] == nil or Ships.byId[other.type].class == "capsule" then
      return false, "that cannot be packaged"
    elseif other.given then
      -- (a ship a station gave for nothing is not to be sold, nor packed
      -- and put together again as one bought: that was money from nothing)
      return false, "a ship you were given cannot be packaged"
    elseif (other.armorDamage or 0) > 0 or (other.hullDamage or 0) > 0 then
      return false, "it is damaged: repair it first"
    end
    return true
  elseif command.kind == "MoveShip" then
    -- (from the pilot's hangar here to the corporation's, or back: 2026-11-23)
    local other = state.ships[command.target or 0]
    local to = command.to
    if other == nil or other.owner ~= "player" or other.docked == 0 or other.docked ~= State.At(ship) then
      return false, "that ship is not here"
    elseif other.id == ship.id then
      return false, "you are aboard it: board another first"
    elseif other.pilot ~= 0 then
      return false, "a member of your fleet flies that ship"
    elseif other.member then
      return false, "that ship is assigned to a member: take it off them first"
    elseif Ships.byId[other.type].class == "capsule" then
      return false, "a capsule is nobody's to keep"
    elseif to ~= "corporate" and to ~= "hangar" then
      return false, "a ship goes into your hangar or the corporation's"
    elseif to == "corporate" and not Corporation.Founded(state) then
      return false, "there is no corporation: found one first"
    elseif (other.corporate == true) == (to == "corporate") then
      return false, if to == "corporate" then "it is in the corporation's hangar already" else "it is in your hangar already"
    end
    return true
  elseif command.kind == "SetHome" then
    -- Home is made of the station docked at: any that somebody keeps,
    -- a colony ship among them (the pilot then wakes wherever it has
    -- got to). Not a tower of the pilot's own, which has no berths.
    local object = Space.Object(state, State.At(ship))
    if object == nil or object.kind ~= "station" then
      return false, "this is no station"
    elseif State.At(ship) == state.player.home then
      return false, "this is your home already"
    elseif state.starbases[State.At(ship)] and not Starbases.Citadel(state.starbases[State.At(ship)]) then
      return false, "a tower has no berth to wake in"
    elseif state.starbases[State.At(ship)] and not Starbases.Has(state, state.starbases[State.At(ship)], "quarters") then
      -- (a citadel is woken in where it has a clone bay online)
      return false, "this citadel has no clone bay online"
    elseif Hangar.HOME_FEE > state.wallet then
      return false, "not enough credits for the berth"
    end
    return true
  end
  return false, `unknown command '{command.kind}'`
end

function Hangar.Apply(state: State.State, command: State.Command, events: { Event })
  local ship = state.ships[command.actor]
  if command.kind == "Assemble" then
    local item = state.items[command.item :: number]
    local hull = Ships.byId[item.type]
    Items.Take(state, item, 1)
    local corporate = item.place == "corporate"
    local made = Space.NewShip(state, hull.id, hull.name, "player", State.At(ship))
    made.corporate = if corporate then true else nil
    table.insert(events, { kind = "ShipAssembled", ship = made.id, hull = hull.id })
  elseif command.kind == "LeaveShip" then
    -- Out of the ship, into a fresh capsule: one the pilot keeps, docked
    -- (Tactical/Aftermath puts nobody into a ship from it).
    local ball = state.balls[ship.id]
    local pod = Space.NewShip(state, "capsule", "Capsule", "player", ship.docked)
    pod.chosen = true
    if ball and ship.moored then
      -- (in the field of a tower: the ship is stowed there, and the capsule is out where it was)
      local station, system, x, y, z = ship.moored :: number, ball.system, ball.x, ball.y, ball.z
      Vitals.Store(ship, ball)
      Space.RemoveBall(state, ball)
      ship.docked = station
      table.insert(events, { kind = "BallRemoved", ball = ship.id, reason = "stowed" })
      Space.Launch(state, pod, system, x, y, z)
      pod.moored = station
      table.insert(events, { kind = "BallAdded", ball = pod.id })
    elseif ball then
      -- (in space: it stays where it is, stopped and nobody's to fly, and the capsule beside it)
      local out = Space.Launch(state, pod, ball.system, ball.x, ball.y, ball.z)
      out.vx, out.vy, out.vz = ball.vx, ball.vy, ball.vz
      ball.mode, ball.target, ball.range = "stop", 0, 0
      table.clear(ball.vitals.locks)
      table.clear(ball.vitals.running)
      Vitals.Refresh(state, ball)
      ship.left = state.tick
      table.insert(events, { kind = "BallAdded", ball = pod.id })
    end
    state.player.ship = pod.id
    table.insert(events, { kind = "ShipLeft", ship = ship.id, name = ship.name, pod = pod.id, space = ball ~= nil and ship.moored == nil })
  elseif command.kind == "RenameShip" then
    local other = state.ships[command.target :: number]
    local was = other.name
    other.name = string.match(command.name :: string, "^%s*(.-)%s*$") or other.name
    local ball = state.balls[other.id]
    if ball then
      ball.name = other.name
    end
    table.insert(events, { kind = "ShipRenamed", ship = other.id, name = other.name, was = was })
  elseif command.kind == "BoardShip" and State.At(ship) == 0 then
    -- From the capsule, into a ship of the pilot's left in space: the capsule goes.
    local other = state.ships[command.target :: number]
    local pod = state.balls[ship.id]
    if pod then
      Space.RemoveBall(state, pod)
      table.insert(events, { kind = "BallRemoved", ball = ship.id, reason = "boarded" })
    end
    for _, item in table.clone(Items.In(state, ship.id)) do
      Items.Take(state, item, item.quantity)
    end
    state.ships[ship.id] = nil
    State.RemoveId(state.shipIds, ship.id)
    other.left = nil
    state.player.ship = other.id
    table.insert(events, { kind = "ShipBoarded", ship = other.id, from = ship.id })
  elseif command.kind == "BoardShip" then
    local other = state.ships[command.target :: number]
    -- (in the field of a tower, nobody docked: the ship left is stowed at
    -- the tower, by its ship maintenance array, and the one boarded is out
    -- where it was, 2026-11-22)
    local ball = state.balls[ship.id]
    if ball then
      local station, system, x, y, z = State.At(ship), ball.system, ball.x, ball.y, ball.z
      Vitals.Store(ship, ball)
      Space.RemoveBall(state, ball)
      ship.docked, ship.moored = station, nil
      table.insert(events, { kind = "BallRemoved", ball = ship.id, reason = "stowed" })
      Space.Launch(state, other, system, x, y, z)
      other.moored = station
      table.insert(events, { kind = "BallAdded", ball = other.id })
    end
    state.player.ship = other.id
    -- A capsule is put away when its pilot steps out of it.
    if Ships.byId[ship.type].class == "capsule" then
      state.ships[ship.id] = nil
      State.RemoveId(state.shipIds, ship.id)
    end
    table.insert(events, { kind = "ShipBoarded", ship = other.id, from = ship.id })
  elseif command.kind == "Repackage" then
    -- Packed for the market: whatever is fitted or carried goes into the
    -- hangar (a weapon's load beside it, a rig destroyed, as a rig is
    -- when it is taken out), and the hull is a packaged hull again.
    local other = state.ships[command.target :: number]
    local station = State.At(ship)
    for _, item in table.clone(Items.In(state, other.id)) do
      local module = Modules.byId[item.type]
      local takes = if module then Modules.Takes(module) else nil
      if item.slot > 0 and takes and item.charge ~= "" then
        local quantity = if takes.clip == 0 then 1 else item.rounds
        if quantity > 0 then
          Items.Add(state, item.charge, quantity, station, "hangar")
        end
      end
      local quantity, type = item.quantity, item.type
      local rig = item.slot > 0 and module ~= nil and module.slot == "rig"
      Items.Take(state, item, quantity)
      if not rig then
        Items.Add(state, type, quantity, station, "hangar")
      end
    end
    state.ships[other.id] = nil
    State.RemoveId(state.shipIds, other.id)
    Items.Add(state, other.type, 1, station, "hangar")
    table.insert(events, { kind = "ShipRepackaged", ship = other.id, hull = other.type, name = other.name })
  elseif command.kind == "MoveShip" then
    local other = state.ships[command.target :: number]
    other.corporate = if command.to == "corporate" then true else nil
    table.insert(events, { kind = "ShipMoved", ship = other.id, name = other.name, corporate = other.corporate == true })
  elseif command.kind == "SetHome" then
    local was = state.player.home
    state.player.home = State.At(ship)
    Wallet.Pay(state, -Hangar.HOME_FEE, "home berth", events)
    table.insert(events, { kind = "HomeMoved", station = State.At(ship), was = was, fee = Hangar.HOME_FEE })
  end
end

-- By the hour: a ship of the pilot's left in space on grid with a station
-- or citadel somebody else keeps is taken, after it has been there an
-- hour, a chance each hour.
function Hangar.Step(state: State.State, events: { Event })
  if state.tick % Hangar.HOUR ~= 0 then
    return
  end
  for _, id in table.clone(state.shipIds) do
    local ship = state.ships[id]
    local ball = adrift(state, ship)
    if ball and state.tick - (ship.left :: number) >= Hangar.HOUR then
      local place = Space.Object(state, ball.grid)
      local starbase = if place then state.starbases[place.id] else nil
      local theirs = place ~= nil and place.kind == "station" and (starbase == nil or starbase.owner ~= "player")
      if theirs and Rng.Chance(Rng.For(state.historySeed, ship.id, state.tick, 211), Hangar.THEFT) then
        Space.RemoveBall(state, ball)
        table.insert(events, { kind = "BallRemoved", ball = ship.id, reason = "left" })
        for _, item in table.clone(Items.In(state, ship.id)) do
          Items.Take(state, item, item.quantity)
        end
        state.ships[ship.id] = nil
        State.RemoveId(state.shipIds, ship.id)
        table.insert(events, { kind = "ShipStolen", ship = ship.id, name = ship.name, hull = ship.type,
          where = if place then place.name else "" })
      end
    end
  end
end

return Hangar
