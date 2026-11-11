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
local Dogma = require("@lt/Core/Dogma")
local Gunnery = require("@lt/Core/Tactical/Gunnery")
local Items = require("@lt/Core/Assets/Items")
local Mining = require("@lt/Core/Tactical/Mining")
local Modules = require("@lt/Core/Data/Modules")
local Ores = require("@lt/Core/Data/Ores")
local Rng = require("@lt/Core/Kernel/Rng")
local Space = require("@lt/Core/Tactical/Space")
local Standings = require("@lt/Core/Assets/Standings")
local State = require("@lt/Core/Kernel/State")
local Vitals = require("@lt/Core/Tactical/Vitals")

local Combat = {}

-- What a salvager brings off a wreck (Data/Types).
local SALVAGE = { "salvage.plates", "salvage.circuits", "salvage.conduits" }

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
local function lockable(state: State.State, ball: State.Ball, target: number): (boolean, string?)
  local body = Space.Body(state, target)
  if body == nil or target == ball.id then
    return false, "no such target"
  elseif Space.SystemOf(state, target) ~= ball.system then
    return false, "target is in another system"
  end
  local other = state.balls[target]
  if other and other.grid ~= ball.grid then
    return false, "target is not on grid"
  elseif Space.Gap(ball :: any, body) > ball.vitals.lockRange then
    return false, "out of targeting range"
  end
  return true
end

-- ---------------------------------------------------------------------
-- Orders

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
      elseif rock == nil or rock.kind ~= "asteroid" then
        return false, "not an asteroid"
      elseif Mining.Left(state, rock) <= 0 then
        return false, "that asteroid is mined out"
      elseif Space.Gap(ball :: any, rock :: any) > module.miner.range then
        return false, "out of mining range"
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
      end
      return true
    elseif module.repair or module.boost then
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
    table.insert(ball.vitals.running, {
      item = item.id,
      target = if module.weapon or module.miner or module.hex or module.salvager then command.target :: number else 0,
      -- A weapon fires at once; a mining laser delivers at the end of its cycle.
      next = now(state) + (if module.miner then module.miner.duration elseif module.salvager then module.salvager.duration else 0),
      stopping = false, cycles = 0,
    })
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
  return Gunnery.HitChance(angular, weapon.tracking, signature(state, target),
    Space.Gap(ball :: any, target), weapon.optimal * charge.rangeMultiplier, weapon.falloff)
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
  return turretChance(state, ball, fitted, Dogma.Weapon(Vitals.Fit(state, ball), fitted.type, Items.Levels(state, ball.id)), body)
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
    local damage = {}
    for index = 1, 4 do
      damage[index] = charge.damage[index] * weapon.damageMultiplier * quality
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
  local flight = Space.Distance(ball :: any, target) / charge.velocity
  local outcome = "launched"
  if flight > charge.flightTime then
    outcome = "out of range"
  else
    local damage = {}
    for index = 1, 4 do
      damage[index] = charge.damage[index] * weapon.damageMultiplier
    end
    table.insert(state.missiles, { from = ball.id, to = target.id, item = item.id, charge = charge.id,
      damage = damage, impact = now(state) + flight })
  end
  table.insert(events, { kind = "Shot", from = ball.id, item = item.id, to = target.id, family = "missile",
    outcome = outcome, damage = 0, flight = math.min(flight, charge.flightTime) })
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
      local weapon = Dogma.Weapon(Vitals.Fit(state, ball), item.type, Items.Levels(state, ball.id))
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
      local ore = Ores.byId[rock.variety]
      local free = Vitals.Stats(state, state.ships[ball.id], v).cargo - Items.CargoUsed(state, ball.id)
      -- A practised miner gets 5% more for each level after the first.
      local levels = Items.Levels(state, ball.id)
      local skilled = 1 + 0.05 * math.max(0, (if levels then levels.mining or 0 else 0) - 1)
      local units = math.min(math.floor(miner.volume * skilled / ore.volume), math.floor((free + 1e-9) / ore.volume))
      if units <= 0 then
        stop(state, ball, index, "the hold is full", events)
        return false
      end
      units = Mining.Take(state, rock, units)
      v.capacitor -= miner.capacitor
      if units > 0 then
        Items.Add(state, ore.id, units, ball.id, "cargo")
        table.insert(events, { kind = "Mined", ball = ball.id, item = item.id, rock = rock.id, ore = ore.id, units = units })
      end
      if Mining.Left(state, rock) <= 0 then
        table.insert(events, { kind = "RockDepleted", rock = rock.id })
        stop(state, ball, index, "the asteroid is mined out", events)
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
        local pieces = 1 + math.floor(wreck.radius / 40)
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
      -- A neutraliser and a jammer do their work a cycle at a time.
      if hex.kind == "neut" then
        target.vitals.capacitor = math.max(0, target.vitals.capacitor - hex.strength)
      elseif hex.kind == "jam" then
        if Rng.Chance(Rng.For(state.historySeed, state.tick, ball.id, item.id, 67), hex.strength) then
          for at = #target.vitals.locks, 1, -1 do
            Combat.DropLock(state, target, target.vitals.locks[at].target, "jammed", events)
          end
          table.insert(events, { kind = "Jammed", ball = target.id, by = ball.id })
        end
      end

    elseif module.repair then
      local repair = module.repair
      if v.capacitor < repair.capacitor then
        stop(state, ball, index, "capacitor empty", events)
        return false
      end
      v.capacitor -= repair.capacitor
      if repair.layer == "shield" then
        v.shield = math.min(v.shieldMax, v.shield + repair.amount)
      else
        v.armor = math.min(v.armorMax, v.armor + repair.amount)
      end
      table.insert(events, { kind = "Repaired", ball = ball.id, item = item.id, layer = repair.layer, amount = repair.amount })
      running.next += repair.duration

    else
      local cost = module.boostCapacitor or 0
      if v.capacitor < cost then
        stop(state, ball, index, "capacitor empty", events)
        return false
      end
      v.capacitor -= cost
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

  for _, id in table.clone(state.ballIds) do
    local ball = state.balls[id]
    local v = ball.vitals
    v.shield = Gunnery.Recharge(v.shield, v.shieldMax, v.shieldRecharge, Constants.TICK)
    v.capacitor = Gunnery.Recharge(v.capacitor, v.capacitorMax, v.capacitorRecharge, Constants.TICK)

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
      if target then
        local speed = math.sqrt(target.vx ^ 2 + target.vy ^ 2 + target.vz ^ 2)
        local factor = Gunnery.MissileFactor(target.vitals.signature, speed, charge.explosionRadius, charge.explosionVelocity)
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

  -- Who is held: the strongest webifier running on each ship, and
  -- whether a disruptor is. A ship whose lot has changed is told, has
  -- its speed set to match, and if it was getting ready to warp, is not.
  -- (and the strongest painter and the strongest dampener, likewise)
  local webs: { [number]: number } = {}
  local scrambles: { [number]: boolean } = {}
  local paints: { [number]: number } = {}
  local damps: { [number]: number } = {}
  for _, id in state.ballIds do
    for _, running in state.balls[id].vitals.running do
      local item = state.items[running.item]
      local hex = if item then Modules.byId[item.type].hex else nil
      if hex and state.balls[running.target] then
        local target = running.target
        if hex.kind == "web" then
          webs[target] = math.min(webs[target] or 1, hex.strength)
        elseif hex.kind == "scramble" then
          scrambles[target] = true
        elseif hex.kind == "paint" then
          paints[target] = math.max(paints[target] or 1, hex.strength)
        elseif hex.kind == "damp" then
          damps[target] = math.min(damps[target] or 1, hex.strength)
        end
      end
    end
  end
  for _, id in state.ballIds do
    local ball = state.balls[id]
    local v = ball.vitals
    local web, scrambled, paint, damp = webs[id] or 1, scrambles[id] == true, paints[id] or 1, damps[id] or 1
    if v.web ~= web or v.scrambled ~= scrambled or v.paint ~= paint or v.damp ~= damp then
      local held = v.web ~= web or v.scrambled ~= scrambled
      v.web, v.scrambled, v.paint, v.damp = web, scrambled, paint, damp
      Vitals.Refresh(state, ball)
      if scrambled and ball.warp and ball.warp.stage ~= "warp" then
        ball.warp = nil
        ball.intent = nil
      end
      if held then
        table.insert(events, { kind = "Held", ball = id, web = web, scrambled = scrambled })
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
