--!strict
-- Pirates: where they turn up and how they fight.
--
-- For now they haunt asteroid belts. When the player's ship is at a belt
-- that has seen none for a while, a small pack arrives some way off,
-- closes in, and attacks. Each flies with the same orders a player gives
-- (orbit, lock, activate), so anything a pirate can do, a pilot can.
-- They ignore capsules. A pack left alone for a few minutes goes away.
--
-- (When the strategic layer arrives, how many come and where will follow
-- from pirate pressure in the system instead of this fixed rule.)

local Combat = require("@lt/Core/Tactical/Combat")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")

local Pirates = {}

export type Event = { [string]: any }

-- Ticks before a belt that had pirates gets more.
local RESPAWN = 1200
-- Ticks a pack waits on an empty grid before leaving.
local PATIENCE = 300

type Kind = { hull: string, name: string, range: number, fit: { { string } }, ammo: string? }

local SCOUT: Kind = {
  hull = "frigate.courier", name = "Pirate Scout", range = 1500,
  fit = { { "autocannon.small", "ammo.fusion" } }, ammo = "ammo.fusion",
}

-- A pirate ship of a kind, in space at a point.
function Pirates.Spawn(state: State.State, kind: Kind, system: number, x: number, y: number, z: number, home: number): State.Ball
  local ship = Space.NewShip(state, kind.hull, kind.name, "pirates", 0)
  for _, entry in kind.fit do
    Items.Equip(state, ship.id, entry[1], entry[2])
  end
  if kind.ammo then
    Items.Add(state, kind.ammo, 2000, ship.id, "cargo")
  end
  local ball = Space.Launch(state, ship, system, x, y, z)
  state.pilots[ship.id] = { ship = ship.id, range = kind.range, prey = 0, home = home, alone = 0 }
  table.insert(state.pilotIds, ship.id)
  return ball
end

Pirates.SCOUT = SCOUT

local function pirateOnGrid(state: State.State, system: number, grid: number): boolean
  for _, id in state.pilotIds do
    local ball = state.balls[id]
    if ball and ball.system == system and ball.grid == grid then
      return true
    end
  end
  return false
end

-- Bring pirates to the belt the player is at, if it is due some.
function Pirates.Populate(state: State.State, events: { Event })
  local me = state.balls[state.player.ship]
  if state.peaceful or me == nil or me.grid == 0 or Ships.byId[state.ships[me.id].type].class == "capsule" then
    return
  end
  local belt = Space.Object(state, me.grid)
  if belt == nil or belt.kind ~= "belt" then
    return
  end
  local last = state.spawned[belt.id]
  if (last and state.tick - last < RESPAWN) or pirateOnGrid(state, me.system, belt.id) then
    return
  end
  local rng = Rng.For(state.historySeed, state.tick, belt.id, 41)
  local count = if Rng.Chance(rng, 0.3) then 2 else 1
  for _ = 1, count do
    -- Somewhere 25 to 35 km out from the belt's centre.
    local angle = Rng.Float(rng, 0, 2 * math.pi)
    local out = Rng.Float(rng, 25000, 35000)
    local ball = Pirates.Spawn(state, SCOUT, me.system,
      belt.x + out * math.cos(angle), belt.y + Rng.Float(rng, -3000, 3000), belt.z + out * math.sin(angle), belt.id)
    table.insert(events, { kind = "BallAdded", ball = ball.id })
  end
  state.spawned[belt.id] = state.tick
  table.insert(events, { kind = "PiratesArrived", grid = belt.id, count = count })
end

local function give(state: State.State, command: State.Command, events: { Event }): boolean
  local combat = command.kind == "LockTarget" or command.kind == "ActivateModule"
  if combat then
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

-- Each pirate decides what to do this tick.
function Pirates.Think(state: State.State, events: { Event })
  local player = state.balls[state.player.ship]
  for _, id in table.clone(state.pilotIds) do
    local pilot = state.pilots[id]
    local ball = state.balls[id]
    if ball == nil or (ball.warp and ball.warp.stage == "warp") then
      continue
    end

    -- Leave if nobody has been here for a while.
    local company = player ~= nil and player.system == ball.system and player.grid == ball.grid
    pilot.alone = if company then 0 else pilot.alone + 1
    if pilot.alone > PATIENCE then
      Space.RemoveBall(state, ball)
      for _, item in Items.In(state, id, nil) do
        Items.Take(state, item, item.quantity)
      end
      state.ships[id] = nil
      State.RemoveId(state.shipIds, id)
      state.pilots[id] = nil
      State.RemoveId(state.pilotIds, id)
      table.insert(events, { kind = "BallRemoved", ball = id, reason = "left" })
      continue
    end

    -- Prey: the player's ship, if it is here and worth shooting.
    local prey: State.Ball? = state.balls[pilot.prey]
    if prey == nil or prey.system ~= ball.system or prey.grid ~= ball.grid then
      pilot.prey = 0
      prey = nil
      if company and player and Ships.byId[state.ships[player.id].type].class ~= "capsule" then
        pilot.prey = player.id
        prey = player
      end
    end
    if prey == nil then
      if ball.mode ~= "stop" then
        give(state, { kind = "Stop", actor = id }, events)
      end
      continue
    end

    if not (ball.mode == "orbit" and ball.target == prey.id) then
      give(state, { kind = "Orbit", actor = id, target = prey.id, range = pilot.range }, events)
    end
    local locked = false
    local targeted = false
    for _, lock in ball.vitals.locks do
      if lock.target == prey.id then
        targeted = true
        locked = lock.locked
      end
    end
    if not targeted then
      give(state, { kind = "LockTarget", actor = id, target = prey.id }, events)
    elseif locked then
      for _, item in Items.Fitted(state, id) do
        if Modules.byId[item.type].weapon then
          give(state, { kind = "ActivateModule", actor = id, item = item.id, target = prey.id }, events)
        end
      end
    end
  end
end

return Pirates
