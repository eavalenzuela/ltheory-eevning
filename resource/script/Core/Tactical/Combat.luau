--!strict
-- Fighting: locking targets, running modules, shots, missiles, damage
-- and destruction. The formulas are in Tactical/Gunnery; this is the
-- bookkeeping around them.
--
-- A pilot locks a target (it takes a few seconds), then switches on
-- modules. A module cycles: a weapon fires once per cycle at its target,
-- a repairer mends once per cycle, an afterburner or hardener draws
-- capacitor once per cycle and has its effect for as long as it runs.
-- Each keeps cycling until told to stop, until it lacks capacitor or
-- ammunition, or until its target is lost.
--
-- Shots are resolved by the dice, not by flying objects: the view shows
-- what the Shot events say happened. All of one tick's shots are worked
-- out first and their damage applied together, so two ships that kill
-- each other on the same tick both get their shot off.

local Constants = require("@lt/Core/Data/Constants")
local Attributes = require("@lt/Core/Attributes")
local Fields = require("@lt/Core/Tactical/Fields")
local Gunnery = require("@lt/Core/Tactical/Gunnery")
local Items = require("@lt/Core/Assets/Items")
local Mining = require("@lt/Core/Tactical/Mining")
local Modules = require("@lt/Core/Data/Modules")
local Ores = require("@lt/Core/Data/Ores")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")
local Space = require("@lt/Core/Tactical/Space")
local Standings = require("@lt/Core/Assets/Standings")
local State = require("@lt/Core/Kernel/State")
local Starbases = require("@lt/Core/Assets/Starbases")
local Vapour = require("@lt/Core/Tactical/Vapour")
local Vitals = require("@lt/Core/Tactical/Vitals")

local Combat = {}

-- What three of a pilot's crafts come to, a level (Data/Skills): a
-- missile's flight longer by this share (Long Burn), its blast tighter
-- by this (Proximity Fusing), and a drone's gun doing this much more
-- (Swarm Tactics).
Combat.LONG_BURN, Combat.FUSING, Combat.SWARM = 0.05, 0.04, 0.04

-- What a salvager brings off a wreck (Data/Types).
local SALVAGE = { "salvage.plates", "salvage.circuits", "salvage.conduits" }
Combat.SALVAGE_PIECES = 5

-- Ticks a pilot stays marked after firing on somebody who is no pirate
-- (Tactical/Traffic.MARKED: a quarter of an hour).
local MARKED = 900

export type Event = { [string]: any }

-- Damage waiting to be applied at the end of the tick.
type Hit = { target: number, by: number, damage: { number } }

local function now(state: State.State): number
  return state.tick * Constants.TICK
end

-- How big a target a body is to a scanner or a gun: a ship's signature,
-- or for anything else its own size.
local function signature(state: State.State, body: Space.Body): number
  local ball = state.balls[body.id]
  return if ball then ball.vitals.signature else math.max(25, body.radius)
end

local function findLock(ball: State.Ball, target: number): State.Lock?
  for _, lock in ball.vitals.locks do
    if lock.target == target then
      return lock
    end
  end
  return nil
end

local function findRunning(ball: State.Ball, item: number): (State.Running?, number)
  for index, r in ball.vitals.running do
    if r.item == item then
      return r, index
    end
  end
  return nil, 0
end

-- Whether 'target' can be locked or kept locked by 'ball': there, in the
-- same place, and within range.
-- The cloak a ship has running, if it has one: the fitted module's item.
local function cloakOf(state: State.State, ball: State.Ball): State.Item?
  for _, running in ball.vitals.running do
    local item = state.items[running.item]
    if item and Modules.byId[item.type].cloak then
      return item
    end
  end
  return nil
end

-- How near something has to come to a ship to break its cloak: the
-- cloak's reach, and half of that for a hull built to go unseen (which
-- its cloak does not slow either: Core/Attributes).
Combat.STEALTH = 0.5
local function reachOf(state: State.State, ball: State.Ball, cloak: Modules.ModuleType): number
  local ship = state.ships[ball.id]
  local hull = if ship then Ships.byId[ship.type] else nil
  return (cloak.cloak :: any).reach * (if hull and hull.stealth then Combat.STEALTH else 1)
end

-- A hull's own cloak (Data/Ships 'cloak': the hull has one built in).
-- There is nothing to fit and nothing in a slot: the pilot switches it
-- on with "Cloak" and off with "Uncloak", and it is on for as long as
-- 'vitals.cloaked' says. It is the cloaking device in every way but
-- these: it does not slow the ship, and it goes off the moment it is
-- told to. (First figures, those: the project owner's word is that the
-- hull "has a built-in cloak".) And it draws on the capacitor while it
-- is on (the owner's, 2026-11-15, of the Drowned's: it "does not eat
-- into their CPU/PG for fitting (but obviously does use power when
-- running)"): each second, Combat.OWN_CLOAK_DRAW times what the hull's
-- capacitor gets back in a second on the average of a full recharge.
-- So a hull under its own cloak settles at some four fifths of its
-- capacitor, whatever its size, and one with next to none cannot stay
-- under it. (How much it draws is a first figure.)
Combat.OWN_CLOAK = "cloak.device"   -- the device a hull's own cloak is, for how near breaks it
Combat.OWN_CLOAK_DRAW = 1
-- What a ship's own cloak draws in a tick, GJ.
local function ownCloakDraw(ball: State.Ball): number
  local v = ball.vitals
  return Combat.OWN_CLOAK_DRAW * v.capacitorMax / math.max(1, v.capacitorRecharge) * Constants.TICK
end
local function ownCloak(state: State.State, ball: State.Ball): boolean
  local ship = state.ships[ball.id]
  local hull = if ship then Ships.byId[ship.type] else nil
  return hull ~= nil and hull.cloak == true
end

-- How near something has to come to break the cloak a ship is under,
-- its own or a fitted one's: nil for a ship that is under none.
local function hiddenWithin(state: State.State, ball: State.Ball): number?
  if ball.vitals.cloaked then
    return reachOf(state, ball, Modules.byId[Combat.OWN_CLOAK])
  end
  local cloak = cloakOf(state, ball)
  return if cloak then reachOf(state, ball, Modules.byId[cloak.type]) else nil
end

-- Whether a ship is cloaked: nobody can target it.
function Combat.Cloaked(state: State.State, id: number): boolean
  local ball = state.balls[id]
  return ball ~= nil and (ball.vitals.cloaked == true or cloakOf(state, ball) ~= nil)
end

-- Whether a hull has a cloak of its own: its pilot can "Cloak".
function Combat.HasCloak(state: State.State, id: number): boolean
  local ball = state.balls[id]
  return ball ~= nil and ownCloak(state, ball)
end

-- What is within 'reach' of a ship on its grid, if anything: another
-- ship, a wreck, a station, a gate or a rock. (A cloak does not work
-- that near anything.) Its name.
local function crowding(state: State.State, ball: State.Ball, reach: number): string?
  for _, id in state.ballIds do
    local other = state.balls[id]
    if id ~= ball.id and other.system == ball.system and other.grid == ball.grid and Space.Gap(ball :: any, other :: any) <= reach then
      return other.name
    end
  end
  for _, id in state.wreckIds do
    local wreck = state.wrecks[id]
    if wreck.system == ball.system and wreck.grid == ball.grid and Space.Gap(ball :: any, wreck :: any) <= reach then
      return wreck.name
    end
  end
  if ball.grid ~= 0 then
    for _, object in Space.Describe(state, ball.system).objects do
      local kind: string = object.kind
      if (object.site == ball.grid or object.id == ball.grid) and (kind == "station" or kind == "gate" or kind == "asteroid")
        and Space.Gap(ball :: any, object :: any) <= reach then
        return object.name
      end
    end
  end
  return nil
end

-- Whether a ship can go under a cloak now, one that anything within
-- 'reach' breaks: not while anybody has it targeted, nor that near
-- anything.
local function mayCloak(state: State.State, ball: State.Ball, reach: number): (boolean, string?)
  for _, id in state.ballIds do
    local other = state.balls[id]
    if id ~= ball.id and other.system == ball.system and other.grid == ball.grid and findLock(other, ball.id) then
      return false, "somebody has you targeted"
    end
  end
  local near = crowding(state, ball, reach)
  if near then
    return false, `too near {near} to cloak`
  end
  return true
end

local function lockable(state: State.State, ball: State.Ball, target: number): (boolean, string?)
  local body = Space.Body(state, target)
  if body == nil or target == ball.id or Combat.Cloaked(state, target) then
    return false, "no such target"
  elseif Space.SystemOf(state, target) ~= ball.system then
    return false, "target is in another system"
  end
  local other = state.balls[target]
  if other and other.grid ~= ball.grid then
    return false, "target is not on grid"
  elseif Fields.Between(state, ball, body) then
    -- (nothing is locked across a station's field, in or out: Tactical/Fields)
    return false, Fields.REFUSED
  elseif Fields.Gap(state, ball, body) > ball.vitals.lockRange then
    return false, "out of targeting range"
  elseif other and Space.Gap(ball :: any, body) > Vapour.Sight(state, ball, other) then
    -- (a ship in a cloud of gas is locked, and locks, only from close in: Tactical/Vapour)
    return false, "lost in the vapour"
  end
  -- (a tower that has sealed itself is nobody's to shoot at: Tactical/Raids)
  local tower = if other then Starbases.OfCore(state, target) else nil
  if tower and Starbases.Sealed(state, tower) then
    return false, "the tower has sealed itself"
  end
  -- (nor is one of the pirates' own: Tactical/Keeps, seen here by the state alone)
  for _, keepId in state.keepIds do
    local keep = state.keeps[keepId]
    if keep.core == target and keep.sealed ~= 0 and state.tick < keep.sealed then
      return false, "the tower has sealed itself"
    end
  end
  return true
end

-- ---------------------------------------------------------------------
-- Orders

-- The gun a ship's hull has of its own, fixed along its bow, if it has
-- one (Data/Ships' 'spinal': the Drowned's The End has a railgun).
--
-- It is fired by pointing the ship (the project owner's, 2026-11-15:
-- "It would likely operate via align-to -> fire, to keep it simple,
-- with the same logic for a correct alignment as the trigger to enter
-- warp"). "FireSpinal" at a locked target turns the ship for it, as
-- "AlignTo" does; and once the ship is moving that way, as fast and as
-- true as it would have to be to warp there (Space.AlignedTo), the gun
-- fires one round, if it has cycled and the capacitor will pay. It
-- goes on turning after a target that moves. Any other order to the
-- helm calls the shot off, and so does losing the lock.
--
-- A round is resolved as a turret's is, on the gun's own figures: it
-- follows nothing, so what is small and crossing is missed.
function Combat.Spinal(state: State.State, id: number): Ships.Spinal?
  local ship = state.ships[id]
  local hull = if ship then Ships.byId[ship.type] else nil
  return if hull then hull.spinal else nil
end

-- Whether a thing in space is a ship of a capital class: what a plain
-- warp disruptor does not hold, and a capital's does (Data/Modules).
function Combat.Capital(state: State.State, id: number): boolean
  local ship = state.ships[id]
  local hull = if ship then Ships.byId[ship.type] else nil
  return hull ~= nil and Ships.Capital(hull.class)
end

function Combat.Validate(state: State.State, command: State.Command): (boolean, string?)
  local ship = state.ships[command.actor]
  if ship == nil then
    return false, "no such ship"
  end
  local ball = state.balls[ship.id]
  if ball == nil then
    return false, "docked"
  elseif ball.warp and ball.warp.stage == "warp" then
    return false, "in warp"
  end
  local kind = command.kind
  -- (a cloaked ship does nothing but fly, and switch its cloak off)
  if (kind == "LockTarget" or kind == "ActivateModule") and Combat.Cloaked(state, ball.id) then
    return false, "cloaked"
  end

  -- A hull's own gun, fixed along its bow (Data/Ships' 'spinal').
  if kind == "FireSpinal" then
    local gun = Combat.Spinal(state, ball.id)
    local lock = findLock(ball, command.target or 0)
    if gun == nil then
      return false, "this hull has no gun of its own"
    elseif Combat.Cloaked(state, ball.id) then
      return false, "cloaked"
    elseif lock == nil or not lock.locked then
      return false, "no locked target"
    elseif Space.Body(state, command.target or 0) == nil then
      return false, "no such target"
    end
    local cycling = (ball.vitals.spinalReady or 0) - state.tick
    if cycling > 0 then
      return false, `the {string.lower(gun.name)} is cycling: {math.ceil(cycling * Constants.TICK)} s`
    elseif ball.vitals.capacitor < gun.capacitor then
      return false, `needs {gun.capacitor} GJ of capacitor`
    end
    return true
  end

  -- A hull's own cloak, on and off.
  if kind == "Cloak" then
    if not ownCloak(state, ball) then
      return false, "this hull has no cloak of its own"
    elseif Combat.Cloaked(state, ball.id) then
      return false, "cloaked already"
    elseif ball.vitals.capacitor < ownCloakDraw(ball) then
      return false, "not enough capacitor to cloak"
    end
    return mayCloak(state, ball, reachOf(state, ball, Modules.byId[Combat.OWN_CLOAK]))
  elseif kind == "Uncloak" then
    return ball.vitals.cloaked == true, "not under the hull's own cloak"
  end

  if kind == "LockTarget" then
    local target = command.target or 0
    if findLock(ball, target) then
      return false, "already targeted"
    elseif #ball.vitals.locks >= ball.vitals.maxTargets then
      return false, "no more targets can be locked"
    end
    return lockable(state, ball, target)

  elseif kind == "UnlockTarget" then
    return findLock(ball, command.target or 0) ~= nil, "not targeted"

  elseif kind == "ActivateModule" then
    local item = state.items[command.item or 0]
    if item == nil or item.holder ~= ship.id or item.slot == 0 then
      return false, "not a fitted module"
    end
    local module = Modules.byId[item.type]
    if findRunning(ball, item.id) then
      return false, "already running"
    end
    if module.cloak then
      return mayCloak(state, ball, reachOf(state, ball, module))
    end
    if module.weapon then
      local lock = findLock(ball, command.target or 0)
      if lock == nil or not lock.locked then
        return false, "no locked target"
      elseif item.charge == "" then
        return false, "nothing loaded"
      end
      return true
    elseif module.miner then
      local lock = findLock(ball, command.target or 0)
      local rock = Space.Object(state, command.target or 0)
      if lock == nil or not lock.locked then
        return false, "no locked target"
      elseif module.miner.gas and not Mining.Cloud(rock) then
        return false, "not a cloud of gas"
      elseif rock == nil or not module.miner.gas and not Mining.Rock(rock) then
        return false, if Mining.Cloud(rock) then "a cloud of gas wants a harvester" else "not an asteroid"
      elseif Mining.Left(state, rock) <= 0 then
        return false, if module.miner.gas then "that cloud is drawn off" else "that asteroid is mined out"
      elseif Space.Gap(ball :: any, rock :: any) > module.miner.range then
        return false, if module.miner.gas then "too far from the cloud" else "out of mining range"
      end
      return true
    elseif module.salvager then
      -- (a wreck needs no lock: it is not going anywhere)
      local wreck = state.wrecks[command.target or 0]
      if wreck == nil or wreck.system ~= ball.system then
        return false, "that is not a wreck"
      elseif wreck.salvaged then
        return false, "that wreck has been salvaged"
      elseif Space.Gap(ball :: any, wreck :: any) > module.salvager.range then
        return false, "out of range"
      end
      return true
    elseif module.hex then
      local lock = findLock(ball, command.target or 0)
      local target = state.balls[command.target or 0]
      if lock == nil or not lock.locked then
        return false, "no locked target"
      elseif target == nil then
        return false, "that is not a ship"
      elseif Space.Gap(ball :: any, target :: any) > module.hex.range then
        return false, "out of range"
      elseif module.hex.kind == "scramble" and not module.capital and Combat.Capital(state, target.id) then
        return false, "a capital is held only by a capital warp disruptor"
      end
      return true
    elseif module.repair or module.boost or module.injector or module.smartbomb then
      return true
    end
    return false, "that module cannot be switched on"

  elseif kind == "DeactivateModule" then
    local running = findRunning(ball, command.item or 0)
    if running == nil then
      return false, "not running"
    end
    return true
  end
  return false, `unknown command '{kind}'`
end

function Combat.Apply(state: State.State, command: State.Command, events: { Event })
  local ball = state.balls[command.actor]
  local kind = command.kind

  if kind == "LockTarget" then
    local target = Space.Body(state, command.target :: number) :: Space.Body
    local time = Gunnery.LockTime(ball.vitals.scanResolution, signature(state, target))
    table.insert(ball.vitals.locks, { target = target.id, done = now(state) + time, locked = false })
    table.insert(events, { kind = "LockStarted", ball = ball.id, target = target.id, time = time })

  elseif kind == "UnlockTarget" then
    Combat.DropLock(state, ball, command.target :: number, "unlocked", events)

  elseif kind == "ActivateModule" then
    local item = state.items[command.item :: number]
    local module = Modules.byId[item.type]
    if module.cloak then
      -- Everything else goes off, and every lock is let go.
      ball.vitals.running, ball.vitals.locks = {}, {}
      table.insert(events, { kind = "Cloaked", ball = ball.id })
    end
    table.insert(ball.vitals.running, {
      item = item.id,
      target = if module.weapon or module.miner or module.hex or module.salvager then command.target :: number else 0,
      -- A weapon fires at once; a mining laser delivers at the end of its cycle.
      next = now(state) + (if module.miner then module.miner.duration elseif module.salvager then module.salvager.duration else 0),
      stopping = false, cycles = 0,
    })
    -- (an adaptive hardener starts even again each time it is switched on)
    if module.adaptive then
      item.adapt = nil
    end
    if module.boost then
      Vitals.Refresh(state, ball)
    end
    table.insert(events, { kind = "ModuleStarted", ball = ball.id, item = item.id, target = command.target or 0 })
    -- A pilot who opens fire on anybody but a pirate is marked for it:
    -- the factions' patrols fight a marked pilot (Tactical/Traffic).
    local shooter = state.ships[ball.id]
    -- (a drone's fire is its owner's, and a hired pilot's their employer's)
    local mine = shooter ~= nil and shooter.owner == "player"
    local victim = if module.weapon and mine then state.ships[command.target or 0] else nil
    if victim and shooter and victim.owner ~= "pirates" and victim.owner ~= shooter.owner then
      if state.tick >= state.player.marked then
        table.insert(events, { kind = "Marked", owner = victim.owner })
        -- (and whoever minds remembers it: Assets/Standings)
        Standings.Change(state, Standings.Minds(state, victim.owner, ball.system), Standings.MARKED, events)
      end
      state.player.marked = state.tick + MARKED
    end

  elseif kind == "DeactivateModule" then
    local running = findRunning(ball, command.item :: number) :: State.Running
    running.stopping = true

  elseif kind == "FireSpinal" then
    -- The ship is turned for its target, as for a warp, and the gun
    -- fires when it is pointed at it (Combat.Step). Any other order to
    -- the helm calls it off.
    local target = Space.Body(state, command.target :: number) :: Space.Body
    ball.vitals.spinalTarget = target.id
    local turn: State.Command = { kind = "AlignTo", actor = ball.id, target = target.id }
    if Space.Validate(state, turn) then
      Space.Apply(state, turn, events)
    end
    table.insert(events, { kind = "SpinalAiming", ball = ball.id, target = target.id })
    -- (fire on anybody but a pirate marks a pilot, from this as from any gun)
    local shooter = state.ships[ball.id]
    local victim = if shooter and shooter.owner == "player" then state.ships[target.id] else nil
    if victim and shooter and victim.owner ~= "pirates" and victim.owner ~= shooter.owner then
      if state.tick >= state.player.marked then
        table.insert(events, { kind = "Marked", owner = victim.owner })
        Standings.Change(state, Standings.Minds(state, victim.owner, ball.system), Standings.MARKED, events)
      end
      state.player.marked = state.tick + MARKED
    end

  elseif kind == "Cloak" then
    -- Everything goes off, and every lock is let go.
    ball.vitals.running, ball.vitals.locks = {}, {}
    ball.vitals.cloaked = true
    Vitals.Refresh(state, ball)
    table.insert(events, { kind = "Cloaked", ball = ball.id })

  elseif kind == "Uncloak" then
    ball.vitals.cloaked = nil
    table.insert(events, { kind = "Decloaked", ball = ball.id, by = "" })
  end
end

-- ---------------------------------------------------------------------
-- The tick

local function stop(state: State.State, ball: State.Ball, index: number, reason: string, events: { Event })
  local running = table.remove(ball.vitals.running, index) :: State.Running
  local item = state.items[running.item]
  if item and Modules.byId[item.type].boost then
    Vitals.Refresh(state, ball)
  end
  table.insert(events, { kind = "ModuleStopped", ball = ball.id, item = running.item, reason = reason })
end

-- Lose a lock, and stop whatever was shooting at that target.
function Combat.DropLock(state: State.State, ball: State.Ball, target: number, reason: string, events: { Event })
  for index, lock in ball.vitals.locks do
    if lock.target == target then
      table.remove(ball.vitals.locks, index)
      break
    end
  end
  for index = #ball.vitals.running, 1, -1 do
    if ball.vitals.running[index].target == target then
      stop(state, ball, index, "target lost", events)
    end
  end
  table.insert(events, { kind = "LockLost", ball = ball.id, target = target, reason = reason })
end

-- Refill a weapon from the hold. Returns false if there is nothing to
-- refill it with.
local function reload(state: State.State, ball: State.Ball, item: State.Item, clip: number): boolean
  for _, stack in Items.In(state, ball.id, "cargo") do
    if stack.type == item.charge then
      local rounds = math.min(clip, stack.quantity)
      Items.Take(state, stack, rounds)
      item.rounds = rounds
      return true
    end
  end
  return false
end

-- The chance that a turret on 'ball' would hit 'target' right now.
local function turretChance(state: State.State, ball: State.Ball, item: State.Item, weapon: Modules.Weapon,
  target: Space.Body): number
  local charge = Modules.chargeById[item.charge]
  local other = state.balls[target.id]
  -- How fast the target crosses the line of fire: the part of the
  -- relative velocity at right angles to it, over the distance.
  local rx, ry, rz = target.x - ball.x, target.y - ball.y, target.z - ball.z
  local distance = math.sqrt(rx * rx + ry * ry + rz * rz)
  local vx, vy, vz = -ball.vx, -ball.vy, -ball.vz
  if other then
    vx, vy, vz = other.vx - ball.vx, other.vy - ball.vy, other.vz - ball.vz
  end
  local angular = 0
  if distance > 0 then
    local along = (vx * rx + vy * ry + vz * rz) / distance
    local across = math.sqrt(math.max(0, vx * vx + vy * vy + vz * vz - along * along))
    angular = across / distance
  end
  -- (a charge may make the gun track better or worse: Data/Modules)
  return Gunnery.HitChance(angular, weapon.tracking * (charge.tracking or 1), signature(state, target),
    Fields.Gap(state, ball, target), weapon.optimal * charge.rangeMultiplier, weapon.falloff)
end

-- The chance a fitted, loaded turret would hit a target now, or nil if
-- the item is not one. For the interface, and for anyone wondering why
-- they keep missing.
function Combat.HitChance(state: State.State, ship: number, item: number, target: number): number?
  local ball = state.balls[ship]
  local fitted = state.items[item]
  local body = Space.Body(state, target)
  if ball == nil or fitted == nil or body == nil or fitted.holder ~= ship or fitted.charge == "" then
    return nil
  end
  local module = Modules.byId[fitted.type]
  if module == nil or module.weapon == nil or module.weapon.family == "missile" then
    return nil
  end
  return turretChance(state, ball, fitted, Attributes.Weapon(Vitals.Fit(state, ball), fitted.type, Items.Levels(state, ball.id)), body)
end

-- One shot from a turret: the dice, and the damage if it lands.
local function fireTurret(state: State.State, ball: State.Ball, running: State.Running, item: State.Item,
  weapon: Modules.Weapon, target: Space.Body, hits: { Hit }, events: { Event })
  local charge = Modules.chargeById[item.charge]
  local chance = turretChance(state, ball, item, weapon, target)
  local roll = Rng.Next(Rng.For(state.historySeed, state.tick, ball.id, item.id, running.cycles))
  local quality = Gunnery.Quality(roll, chance)
  local total = 0
  if quality > 0 then
    -- (more of the kind its hull leans to: Data/Ships' affinity)
    local hull = Ships.byId[state.ships[ball.id].type]
    local damage = {}
    for index = 1, 4 do
      damage[index] = charge.damage[index] * weapon.damageMultiplier * quality * Ships.Dealt(hull, index)
      total += damage[index]
    end
    table.insert(hits, { target = target.id, by = ball.id, damage = damage })
  end
  table.insert(events, { kind = "Shot", from = ball.id, item = item.id, to = target.id, family = weapon.family,
    outcome = if quality == 0 then "miss" elseif quality == 3 then "wreck" else "hit", damage = total })
end

-- Launch a missile: it does its damage when it arrives.
local function fireMissile(state: State.State, ball: State.Ball, item: State.Item, weapon: Modules.Weapon,
  target: Space.Body, events: { Event })
  local charge = Modules.chargeById[item.charge]
  -- (as far as its target's surface is, and for a tower in its field that is the field: Tactical/Fields)
  local flight = math.min(Space.Distance(ball :: any, target), Fields.Gap(state, ball, target) + ball.radius + target.radius)
    / charge.velocity
  local outcome = "launched"
  -- (how long it flies: as its launcher throws it, a short-range one a
  -- third as far, and longer for a pilot who has learned Long Burn. And
  -- how wide its blast will be: as its launcher and whatever is helping
  -- it make it, and tighter for one who has learned Proximity Fusing.)
  local levels = Items.Levels(state, ball.id)
  local flies = charge.flightTime * (weapon.flight or 1) * (1 + Combat.LONG_BURN * Skills.Level(levels, "long.burn"))
  if flight > flies then
    outcome = "out of range"
  else
    local hull = Ships.byId[state.ships[ball.id].type]
    local damage = {}
    for index = 1, 4 do
      damage[index] = charge.damage[index] * weapon.damageMultiplier * Ships.Dealt(hull, index)
    end
    table.insert(state.missiles, { from = ball.id, to = target.id, item = item.id, charge = charge.id,
      damage = damage, impact = now(state) + flight,
      blast = (weapon.blast or 1) * (1 - Combat.FUSING * Skills.Level(levels, "proximity.fusing")) })
  end
  table.insert(events, { kind = "Shot", from = ball.id, item = item.id, to = target.id, family = "missile",
    outcome = outcome, damage = 0, flight = math.min(flight, flies) })
end

-- Run every cycle of one module that has come due. Returns false if the
-- module stopped (the caller's index then points at the next one).
local function cycle(state: State.State, ball: State.Ball, index: number, hits: { Hit }, events: { Event }): boolean
  local running = ball.vitals.running[index]
  local item = state.items[running.item]
  local module = Modules.byId[item.type]
  local v = ball.vitals
  local time = now(state)
  while running.next <= time do
    if running.stopping then
      stop(state, ball, index, "switched off", events)
      return false
    end

    if module.weapon then
      local weapon = Attributes.Weapon(Vitals.Fit(state, ball), item.type, Items.Levels(state, ball.id))
      -- (a drone's gun does more for an owner who has learned Swarm Tactics)
      local drone = state.drones[ball.id]
      if drone and state.ships[drone.owner] then
        weapon.damageMultiplier *= 1 + Combat.SWARM * Skills.Level(Items.Levels(state, drone.owner), "swarm.tactics")
        -- (and for what its owner has fitted for its drones: each amplifier
        -- and link the less for those before it, as stacked modules are)
        local damages, trackings = {}, {}
        for _, fitted in Items.Fitted(state, drone.owner) do
          local helps = Modules.byId[fitted.type].drones
          if helps and helps.damage then
            table.insert(damages, helps.damage)
          end
          if helps and helps.tracking then
            table.insert(trackings, helps.tracking)
          end
        end
        table.sort(damages, function(a: number, b: number): boolean return a > b end)
        table.sort(trackings, function(a: number, b: number): boolean return a > b end)
        for n, by in damages do
          weapon.damageMultiplier *= 1 + (by - 1) * Attributes.Penalty(n - 1)
        end
        for n, by in trackings do
          local more = 1 + (by - 1) * Attributes.Penalty(n - 1)
          weapon.tracking *= more
          weapon.optimal *= more
          weapon.falloff *= more
        end
      end
      -- (a tracking disruptor on it: its turrets track and reach the worse;
      -- a guidance disruptor: its missiles fly the shorter, their blasts the wider)
      if v.track and weapon.family ~= "missile" then
        weapon.tracking *= v.track
        weapon.optimal *= v.track
        weapon.falloff *= v.track
      end
      if v.guide and weapon.family == "missile" then
        weapon.flight = (weapon.flight or 1) * v.guide
        weapon.blast = (weapon.blast or 1) / v.guide
      end
      local lock = findLock(ball, running.target)
      local target = Space.Body(state, running.target)
      if lock == nil or not lock.locked or target == nil then
        stop(state, ball, index, "target lost", events)
        return false
      elseif v.capacitor < weapon.capacitor then
        stop(state, ball, index, "capacitor empty", events)
        return false
      end
      if weapon.clip > 0 and item.rounds == 0 then
        -- Empty: load a fresh clip from the hold, which takes a while.
        if not reload(state, ball, item, weapon.clip) then
          stop(state, ball, index, "out of ammunition", events)
          return false
        end
        running.next = time + weapon.reload
        table.insert(events, { kind = "Reloading", ball = ball.id, item = item.id, time = weapon.reload })
        break
      end
      v.capacitor -= weapon.capacitor
      if weapon.clip > 0 then
        item.rounds -= 1
      end
      if weapon.family == "missile" then
        fireMissile(state, ball, item, weapon, target, events)
      else
        fireTurret(state, ball, running, item, weapon, target, hits, events)
      end
      running.next += weapon.duration

    elseif module.miner then
      local miner = module.miner
      local lock = findLock(ball, running.target)
      local rock = Space.Object(state, running.target)
      if lock == nil or not lock.locked or rock == nil then
        stop(state, ball, index, "target lost", events)
        return false
      elseif Space.Gap(ball :: any, rock :: any) > miner.range then
        stop(state, ball, index, "out of mining range", events)
        return false
      elseif v.capacitor < miner.capacitor then
        stop(state, ball, index, "capacitor empty", events)
        return false
      end
      -- As much as the cycle yields, the rock has left and the hold takes.
      -- (an ore, off a rock; or a gas, off a cloud)
      local ore: { id: string, volume: number } = Ores.byId[rock.variety] or Ores.gasById[rock.variety]
      -- (the hold, and before it the ore hold of a hull that has one)
      local free = Vitals.Stats(state, state.ships[ball.id], v).cargo - Items.CargoUsed(state, ball.id)
      local oreSize, oreUsed = Items.OreHold(state, ball.id)
      -- A practised miner gets 5% more for each level after the first.
      local levels = Items.Levels(state, ball.id)
      local skilled = 1 + 0.05 * math.max(0, (if levels then levels.mining or 0 else 0) - 1)
      -- (a hair over, so that 1,000 units and a fifth more is 1,150 and not 1,149)
      local units = math.min(math.floor(miner.volume * skilled / ore.volume + 1e-6),
        math.floor((free + 1e-9) / ore.volume) + math.floor((oreSize - oreUsed + 1e-9) / ore.volume))
      if units <= 0 then
        stop(state, ball, index, "the hold is full", events)
        return false
      end
      units = Mining.Take(state, rock, units)
      v.capacitor -= miner.capacitor
      if units > 0 then
        Items.StowOre(state, ball.id, ore.id, units, free)
        table.insert(events, { kind = "Mined", ball = ball.id, item = item.id, rock = rock.id, ore = ore.id, units = units })
      end
      if Mining.Left(state, rock) <= 0 then
        table.insert(events, { kind = "RockDepleted", rock = rock.id })
        stop(state, ball, index, if miner.gas then "the cloud is drawn off" else "the asteroid is mined out", events)
        return false
      end
      running.next += miner.duration

    elseif module.salvager then
      local salvager = module.salvager
      local wreck = state.wrecks[running.target]
      if wreck == nil or wreck.salvaged then
        stop(state, ball, index, "nothing left to salvage", events)
        return false
      elseif Space.Gap(ball :: any, wreck :: any) > salvager.range then
        stop(state, ball, index, "out of range", events)
        return false
      elseif v.capacitor < salvager.capacitor then
        stop(state, ball, index, "capacitor empty", events)
        return false
      end
      v.capacitor -= salvager.capacitor
      running.next += salvager.duration
      -- Each cycle may be the one: likelier with skill at it.
      local levels = Items.Levels(state, ball.id)
      local chance = salvager.chance + 0.1 * (if levels then math.max(0, levels.salvaging or 0) else 0)
      local rng = Rng.For(state.historySeed, state.tick, ball.id, item.id, 61)
      if Rng.Chance(rng, chance) then
        -- The bigger the hull, the more of it there is to bring off.
        -- (Five times as many since 2026-11-16, when income came up: more
        -- of it, not dearer, so a rig is built of what it was. Mine.)
        local pieces = Combat.SALVAGE_PIECES * (1 + math.floor(wreck.radius / 40))
        local got: { [string]: number } = {}
        for _ = 1, pieces do
          local type = SALVAGE[Rng.Int(rng, #SALVAGE) + 1]
          got[type] = (got[type] or 0) + 1
        end
        for _, type in SALVAGE do
          if got[type] then
            Items.Add(state, type, got[type], ball.id, "cargo")
          end
        end
        wreck.salvaged = true
        -- (a wreck with nothing aboard is gone once it has been stripped;
        -- one with something aboard waits for it to be taken)
        if #Items.In(state, wreck.id, "cargo") == 0 then
          wreck.expires = state.tick
        end
        table.insert(events, { kind = "Salvaged", ball = ball.id, wreck = wreck.id, pieces = pieces })
        stop(state, ball, index, "salvaged", events)
        return false
      end

    elseif module.hex then
      -- (what it does to its target is worked out for everybody at once,
      -- at the end of the tick: here it only has to keep running)
      local hex = module.hex
      local lock = findLock(ball, running.target)
      local target = state.balls[running.target]
      if lock == nil or not lock.locked or target == nil then
        stop(state, ball, index, "target lost", events)
        return false
      elseif Space.Gap(ball :: any, target :: any) > hex.range then
        stop(state, ball, index, "out of range", events)
        return false
      elseif v.capacitor < hex.capacitor then
        stop(state, ball, index, "capacitor empty", events)
        return false
      end
      v.capacitor -= hex.capacitor
      running.next += hex.duration
      -- A neutraliser, a jammer and a remote repairer do their work a
      -- cycle at a time.
      if hex.kind == "shield" or hex.kind == "armor" then
        local t = target.vitals
        local before = if hex.kind == "shield" then t.shield else t.armor
        if hex.kind == "shield" then
          t.shield = math.min(t.shieldMax, t.shield + hex.strength)
        else
          t.armor = math.min(t.armorMax, t.armor + hex.strength)
        end
        table.insert(events, { kind = "Mended", ball = ball.id, target = target.id, layer = hex.kind,
          amount = (if hex.kind == "shield" then t.shield else t.armor) - before })
      elseif hex.kind == "capacitor" then
        -- (what was taken from this ship's capacitor, into the other's: as much of it as there is room for)
        local t = target.vitals
        local before = t.capacitor
        t.capacitor = math.min(t.capacitorMax, t.capacitor + hex.strength)
        table.insert(events, { kind = "Fed", ball = ball.id, target = target.id, amount = t.capacitor - before })
      elseif hex.kind == "neut" then
        target.vitals.capacitor = math.max(0, target.vitals.capacitor - hex.strength)
      elseif hex.kind == "nos" then
        -- (an energy drain: what it takes goes into the ship's own capacitor,
        -- while the target's is the fuller of the two)
        local t = target.vitals
        local theirs = t.capacitor / math.max(1, t.capacitorMax)
        local ours = v.capacitor / math.max(1, v.capacitorMax)
        if theirs >= ours then
          local taken = math.min(hex.strength, t.capacitor, v.capacitorMax - v.capacitor)
          t.capacitor -= taken
          v.capacitor += taken
          table.insert(events, { kind = "Drained", ball = ball.id, target = target.id, amount = taken })
        end
      elseif hex.kind == "jam" then
        if Rng.Chance(Rng.For(state.historySeed, state.tick, ball.id, item.id, 67), hex.strength) then
          for at = #target.vitals.locks, 1, -1 do
            Combat.DropLock(state, target, target.vitals.locks[at].target, "jammed", events)
          end
          table.insert(events, { kind = "Jammed", ball = target.id, by = ball.id })
        end
      end

    elseif module.smartbomb then
      -- A smartbomb: so much damage to every ship within its reach but the
      -- owner's own (their ships and their drones), a cycle at a time.
      local bomb = module.smartbomb
      if v.capacitor < bomb.capacitor then
        stop(state, ball, index, "capacitor empty", events)
        return false
      end
      v.capacitor -= bomb.capacitor
      local owner = state.ships[ball.id].owner
      local struck = 0
      for _, other in state.ballIds do
        local them = state.balls[other]
        local ship = state.ships[other]
        local drone = state.drones[other]
        local ours = (ship ~= nil and ship.owner == owner) or (drone ~= nil and state.ships[drone.owner] ~= nil
          and state.ships[drone.owner].owner == owner)
        if other ~= ball.id and them and (ship or drone) and not ours and them.system == ball.system and them.grid == ball.grid
          and Space.Gap(ball :: any, them :: any) <= bomb.range then
          table.insert(hits, { target = other, by = ball.id, damage = table.clone(bomb.damage) })
          struck += 1
        end
      end
      table.insert(events, { kind = "Smartbombed", ball = ball.id, item = item.id, struck = struck })
      running.next += bomb.duration

    elseif module.repair then
      local repair = module.repair
      -- (an ancillary repairer with a charge loaded spends the charge: an
      -- armour one does so much more for it, a shield one draws no
      -- capacitor for it; out of charges it reloads from the hold when
      -- there are more, and works on as a plain one meanwhile)
      local ancillary, takes = module.ancillary, Modules.Takes(module)
      local charged = ancillary ~= nil and item.charge ~= "" and item.rounds > 0
      if ancillary and takes and item.charge ~= "" and item.rounds == 0 and reload(state, ball, item, takes.clip) then
        running.next = time + takes.reload
        table.insert(events, { kind = "Reloading", ball = ball.id, item = item.id, time = takes.reload })
        break
      end
      local cost = if charged and ancillary and ancillary.factor == 1 then 0 else repair.capacitor
      if v.capacitor < cost then
        stop(state, ball, index, "capacitor empty", events)
        return false
      end
      v.capacitor -= cost
      local amount = repair.amount * (if charged and ancillary then ancillary.factor else 1)
      if charged then
        item.rounds -= 1
      end
      if repair.layer == "shield" then
        v.shield = math.min(v.shieldMax, v.shield + amount)
      else
        v.armor = math.min(v.armorMax, v.armor + amount)
      end
      table.insert(events, { kind = "Repaired", ball = ball.id, item = item.id, layer = repair.layer, amount = amount })
      running.next += repair.duration

    elseif module.injector then
      -- A capacitor booster: a charge's worth into the capacitor each
      -- cycle; out of charges, a reload from the hold, or it stops.
      local takes = Modules.Takes(module) :: { family: string, size: number, clip: number, reload: number }
      if item.rounds == 0 or item.charge == "" then
        if item.charge == "" or not reload(state, ball, item, takes.clip) then
          stop(state, ball, index, "out of charges", events)
          return false
        end
        running.next = time + takes.reload
        table.insert(events, { kind = "Reloading", ball = ball.id, item = item.id, time = takes.reload })
        break
      end
      local charge = Modules.chargeById[item.charge]
      local gives = if charge then charge.injects or 0 else 0
      v.capacitor = math.min(v.capacitorMax, v.capacitor + gives)
      item.rounds -= 1
      table.insert(events, { kind = "CapacitorBoosted", ball = ball.id, item = item.id, amount = gives })
      running.next += module.injector.duration

    else
      local cost = module.boostCapacitor or 0
      if v.capacitor < cost then
        stop(state, ball, index, "capacitor empty", events)
        return false
      end
      v.capacitor -= cost
      -- (an adaptive hardener, after its first cycle: a step of its
      -- resistance from the kind the ship took least of to the kind it
      -- took most of, since it last looked)
      local adaptive = module.adaptive
      if adaptive and running.cycles > 0 then
        local taken = v.taken
        local split = item.adapt or table.create(4, adaptive.total / 4)
        if taken and (taken[1] + taken[2] + taken[3] + taken[4]) > 0 then
          local most, least = 1, 0
          for kind = 1, 4 do
            if taken[kind] > taken[most] then
              most = kind
            end
          end
          for kind = 1, 4 do
            if kind ~= most and split[kind] > 0 and (least == 0 or taken[kind] < taken[least]) then
              least = kind
            end
          end
          if least ~= 0 then
            local moved = math.min(adaptive.step, split[least])
            split[least] -= moved
            split[most] += moved
            item.adapt = split
            Vitals.Refresh(state, ball)
          end
        end
        v.taken = nil
      end
      running.next += module.boostDuration or 1
    end
    running.cycles += 1
  end
  return true
end

local function applyHit(state: State.State, hit: Hit, killers: { [number]: number }, events: { Event })
  local ball = state.balls[hit.target]
  if ball == nil then
    return -- an asteroid, or a ship already gone
  end
  local v = ball.vitals
  local layers = { shield = v.shield, armor = v.armor, hull = v.hull }
  local shield, armor, hull = Gunnery.Apply(layers, v.shieldResonance, v.armorResonance, v.hullResonance, hit.damage)
  -- (what it has taken of each kind, for an adaptive hardener of its)
  local taken = v.taken or { 0, 0, 0, 0 }
  for kind = 1, 4 do
    taken[kind] += hit.damage[kind] or 0
  end
  v.taken = taken
  v.shield, v.armor, v.hull = layers.shield, layers.armor, layers.hull
  table.insert(events, { kind = "DamageApplied", ball = ball.id, by = hit.by, shield = shield, armor = armor, hull = hull })
  if v.hull <= 0 and killers[ball.id] == nil then
    killers[ball.id] = hit.by
  end
end

-- Recharge, check locks, run modules, land missiles, apply damage. Ships
-- destroyed this tick are returned (id to killer) for the caller to deal
-- with: what becomes of a wreck and its pilot is not combat's business.
--
-- 'landed' is hits from elsewhere to apply with the rest (a station's
-- batteries: Tactical/Batteries).
function Combat.Step(state: State.State, events: { Event }, landed: { Hit }?): { [number]: number }
  local time = now(state)
  local hits: { Hit } = landed or {}

  -- The guns fixed along a bow (Combat.Spinal): each that has been told
  -- to fire goes on turning for its target, and fires when the ship is
  -- pointed at it.
  for _, id in state.ballIds do
    local ball = state.balls[id]
    local v = ball.vitals
    local aim = v.spinalTarget
    if aim then
      local gun = Combat.Spinal(state, id)
      local target = Space.Body(state, aim)
      local lock = findLock(ball, aim)
      if gun == nil or target == nil or lock == nil or not lock.locked or ball.mode ~= "align" or ball.warp ~= nil
        or Combat.Cloaked(state, id) then
        -- (called off: the lock is gone, or the helm has other orders)
        v.spinalTarget = nil
        table.insert(events, { kind = "SpinalOff", ball = id })
      else
        -- (after a target that moves)
        local far = math.max(1e-6, Space.Distance(ball :: any, target))
        ball.dx, ball.dy, ball.dz = (target.x - ball.x) / far, (target.y - ball.y) / far, (target.z - ball.z) / far
        if Space.AlignedTo(ball, target.x, target.y, target.z) and state.tick >= (v.spinalReady or 0) and v.capacitor >= gun.capacitor then
          v.capacitor -= gun.capacitor
          v.spinalReady = state.tick + math.ceil(gun.duration / Constants.TICK)
          v.spinalTarget = nil
          -- (how fast the target crosses the line of fire, as for a turret)
          local other = state.balls[target.id]
          local rx, ry, rz = target.x - ball.x, target.y - ball.y, target.z - ball.z
          local vx, vy, vz = -ball.vx, -ball.vy, -ball.vz
          if other then
            vx, vy, vz = other.vx - ball.vx, other.vy - ball.vy, other.vz - ball.vz
          end
          local along = (vx * rx + vy * ry + vz * rz) / far
          local across = math.sqrt(math.max(0, vx * vx + vy * vy + vz * vz - along * along))
          local chance = Gunnery.HitChance(across / far, gun.tracking, signature(state, target), Fields.Gap(state, ball, target),
            gun.optimal, gun.falloff)
          local quality = Gunnery.Quality(Rng.Next(Rng.For(state.historySeed, state.tick, id, 211)), chance)
          local total = 0
          if quality > 0 then
            local hull = Ships.byId[state.ships[id].type]
            local damage = {}
            for index = 1, 4 do
              damage[index] = gun.damage[index] * quality * Ships.Dealt(hull, index)
              total += damage[index]
            end
            table.insert(hits, { target = target.id, by = id, damage = damage })
          end
          table.insert(events, { kind = "Shot", from = id, item = 0, to = target.id, family = gun.family, look = gun.look, spinal = true,
            outcome = if quality == 0 then "miss" elseif quality == 3 then "wreck" else "hit", damage = total })
        end
      end
    end
  end

  for _, id in table.clone(state.ballIds) do
    local ball = state.balls[id]
    local v = ball.vitals
    v.shield = Gunnery.Recharge(v.shield, v.shieldMax, v.shieldRecharge, Constants.TICK)
    v.capacitor = Gunnery.Recharge(v.capacitor, v.capacitorMax, v.capacitorRecharge, Constants.TICK)
    -- (A hull that mends by itself, the Nimia's: so much of its armour
    -- and of its hull comes back each second, evenly, whatever it is
    -- doing and whatever is being done to it.)
    local armorMend, hullMend = v.armorMend or 0, v.hullMend or 0
    if armorMend > 0 and v.armor < v.armorMax then
      v.armor = math.min(v.armorMax, v.armor + v.armorMax * armorMend * Constants.TICK)
    end
    if hullMend > 0 and v.hull < v.hullMax then
      v.hull = math.min(v.hullMax, v.hull + v.hullMax * hullMend * Constants.TICK)
    end

    for index = #v.locks, 1, -1 do
      local lock = v.locks[index]
      local ok, reason = lockable(state, ball, lock.target)
      if not ok then
        Combat.DropLock(state, ball, lock.target, reason :: string, events)
      elseif not lock.locked and lock.done <= time then
        lock.locked = true
        table.insert(events, { kind = "LockCompleted", ball = ball.id, target = lock.target })
      end
    end

    local index = 1
    while index <= #v.running do
      if cycle(state, ball, index, hits, events) then
        index += 1
      end
    end
  end

  -- Missiles that arrive this tick.
  local flying: { State.Missile } = {}
  for _, missile in state.missiles do
    if missile.impact > time then
      table.insert(flying, missile)
    else
      local target = state.balls[missile.to]
      local charge = Modules.chargeById[missile.charge]
      -- (one whose target has gone into a station's field since it was
      -- launched, or come out of the one it was launched in, comes to
      -- nothing against the field: Tactical/Fields. With nobody left
      -- where it came from, it is the target being inside that stops it.)
      local from = state.balls[missile.from]
      local stopped = false
      if target and from then
        stopped = Fields.Between(state, from, target :: any)
      elseif target then
        local field = Fields.Around(state, target)
        local starbase = if field then state.starbases[field.id] else nil
        stopped = field ~= nil and not (starbase ~= nil and starbase.core == target.id)
      end
      if target and not stopped then
        local speed = math.sqrt(target.vx ^ 2 + target.vy ^ 2 + target.vz ^ 2)
        -- (its blast as wide as it was made when it was fired)
        local factor = Gunnery.MissileFactor(target.vitals.signature, speed, charge.explosionRadius * (missile.blast or 1),
          charge.explosionVelocity)
        local damage, total = {}, 0
        for i = 1, 4 do
          damage[i] = missile.damage[i] * factor
          total += damage[i]
        end
        table.insert(hits, { target = missile.to, by = missile.from, damage = damage })
        table.insert(events, { kind = "MissileHit", from = missile.from, to = missile.to, damage = total })
      end
    end
  end
  state.missiles = flying

  -- Who is held: the strongest entanglement projector running on each ship, and
  -- whether a disruptor is. A ship whose lot has changed is told, has
  -- its speed set to match, and if it was getting ready to warp, is not.
  -- (and the strongest painter and the strongest dampener, likewise)
  local entangles: { [number]: number } = {}
  local scrambles: { [number]: boolean } = {}
  local paints: { [number]: number } = {}
  local damps: { [number]: number } = {}
  -- (and the strongest tracking and guidance disruptors, and remote sensor booster)
  local tracks: { [number]: number } = {}
  local guides: { [number]: number } = {}
  local sensors: { [number]: number } = {}
  for _, id in state.ballIds do
    for _, running in state.balls[id].vitals.running do
      local item = state.items[running.item]
      local hex = if item then Modules.byId[item.type].hex else nil
      if hex and state.balls[running.target] then
        local target = running.target
        if hex.kind == "entangle" then
          entangles[target] = math.min(entangles[target] or 1, hex.strength)
        elseif hex.kind == "scramble" then
          -- (a capital is held by a capital's disruptor and by no other)
          if Modules.byId[item.type].capital or not Combat.Capital(state, target) then
            scrambles[target] = true
          end
        elseif hex.kind == "paint" then
          paints[target] = math.max(paints[target] or 1, hex.strength)
        elseif hex.kind == "damp" then
          damps[target] = math.min(damps[target] or 1, hex.strength)
        elseif hex.kind == "track" then
          tracks[target] = math.min(tracks[target] or 1, hex.strength)
        elseif hex.kind == "guide" then
          guides[target] = math.min(guides[target] or 1, hex.strength)
        elseif hex.kind == "sensor" then
          sensors[target] = math.max(sensors[target] or 1, hex.strength)
        end
      end
    end
  end
  for _, id in state.ballIds do
    local ball = state.balls[id]
    local v = ball.vitals
    local entangle, scrambled, paint, damp = entangles[id] or 1, scrambles[id] == true, paints[id] or 1, damps[id] or 1
    v.track, v.guide = tracks[id], guides[id]
    local sensor = sensors[id]
    if v.sensor ~= sensor then
      v.sensor = sensor
      Vitals.Refresh(state, ball)
    end
    if v.entangle ~= entangle or v.scrambled ~= scrambled or v.paint ~= paint or v.damp ~= damp then
      local held = v.entangle ~= entangle or v.scrambled ~= scrambled
      v.entangle, v.scrambled, v.paint, v.damp = entangle, scrambled, paint, damp
      Vitals.Refresh(state, ball)
      if scrambled and ball.warp and ball.warp.stage ~= "warp" then
        ball.warp = nil
        ball.intent = nil
      end
      if held then
        table.insert(events, { kind = "Held", ball = id, entangle = entangle, scrambled = scrambled })
      end
    end
  end

  -- The cloaked: one that something has come too near is cloaked no
  -- longer, and nobody keeps a lock on one that still is.
  local hidden: { [number]: boolean } = {}
  local any = false
  for _, id in state.ballIds do
    local ball = state.balls[id]
    -- (a hull's own cloak draws on its capacitor, and is off when that will not pay)
    if ball.vitals.cloaked then
      local draw = ownCloakDraw(ball)
      if ball.vitals.capacitor < draw then
        ball.vitals.cloaked = nil
        table.insert(events, { kind = "Decloaked", ball = id, by = "", spent = true })
      else
        ball.vitals.capacitor -= draw
      end
    end
    local reach = hiddenWithin(state, ball)
    if reach then
      local near = crowding(state, ball, reach)
      if near then
        local cloak = cloakOf(state, ball)
        if cloak then
          local _, index = findRunning(ball, cloak.id)
          stop(state, ball, index, `too near {near}`, events)
        end
        ball.vitals.cloaked = nil
        table.insert(events, { kind = "Decloaked", ball = id, by = near })
      else
        hidden[id] = true
        any = true
      end
    end
  end
  if any then
    for _, id in state.ballIds do
      local ball = state.balls[id]
      for at = #ball.vitals.locks, 1, -1 do
        local target = ball.vitals.locks[at].target
        if hidden[target] then
          Combat.DropLock(state, ball, target, "cloaked", events)
        end
      end
    end
  end

  local killers: { [number]: number } = {}
  for _, hit in hits do
    applyHit(state, hit, killers, events)
  end
  return killers
end

return Combat
