--!strict
-- Fights, played through the Core's front door. The player's ship is put
-- in space with a chosen fit, an opponent is placed at a chosen distance,
-- and what happens is compared with what the formulas say should.

local Combat = require("@lt/Core/Tactical/Combat")
local Vitals = require("@lt/Core/Tactical/Vitals")
local Ships = require("@lt/Core/Data/Ships")
local Attributes = require("@lt/Core/Attributes")
local Core = require("@lt/Core/Api")
local Gunnery = require("@lt/Core/Tactical/Gunnery")
local Items = require("@lt/Core/Assets/Items")
local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Modules = require("@lt/Core/Data/Modules")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Combat")

type Arena = { game: Core.Game, me: State.Ball, foe: State.Ball }

-- The player in a hull with a fit, at rest in space, and an opponent
-- 'distance' metres away (between surfaces), also at rest.
local function arena(hull: string, fit: { { string } }, foeHull: string, foeFit: { { string } }, distance: number,
  historySeed: number?): Arena
  local game = Core.New({ galaxySeed = 1, historySeed = historySeed or 1, peaceful = true })
  local state = game.state
  -- Swap the starter ship for the one under test.
  local old = state.player.ship
  for _, item in Items.In(state, old, nil) do
    Items.Take(state, item, item.quantity)
  end
  state.ships[old] = nil
  State.RemoveId(state.shipIds, old)
  local mine = Space.NewShip(state, hull, "Tester", "player", state.player.home)
  state.player.ship = mine.id
  for _, entry in fit do
    Items.Equip(state, mine.id, entry[1], entry[2])
  end
  local station = assert(Space.Object(state, state.player.home))
  local me = Space.Launch(state, mine, 1, station.x + 50000, station.y, station.z)

  local theirs = Space.NewShip(state, foeHull, "Target", "pirate", 0)
  for _, entry in foeFit do
    Items.Equip(state, theirs.id, entry[1], entry[2])
  end
  local foe = Space.Launch(state, theirs, 1, me.x + distance + me.radius + 100, me.y, me.z)
  foe.x = me.x + distance + me.radius + foe.radius
  return { game = game, me = me, foe = foe }
end

local function order(t: Test.Context, a: Arena, command: State.Command)
  command.actor = a.game.state.player.ship
  local ok, reason = Core.Submit(a.game, command)
  t.ok(ok, `{command.kind} was refused: {tostring(reason)}`)
end

local function refused(a: Arena, command: State.Command): string?
  command.actor = a.game.state.player.ship
  local ok, reason = Core.Validate(a.game, command)
  return if ok then "(accepted)" else reason
end

-- Step until an event of 'kind'; returns it and the ticks taken.
local function stepUntil(a: Arena, kind: string, limit: number): (Space.Event, number)
  for n = 1, limit do
    Core.Step(a.game)
    for _, event in Core.TakeEvents(a.game) do
      if event.kind == kind then
        return event, n
      end
    end
  end
  error(`no {kind} within {limit} ticks`, 2)
end

-- Step n ticks, gathering the events of the kinds asked for.
local function gather(a: Arena, ticks: number, kind: string): { Space.Event }
  local found = {}
  for _ = 1, ticks do
    Core.Step(a.game)
    for _, event in Core.TakeEvents(a.game) do
      if event.kind == kind then
        table.insert(found, event)
      end
    end
  end
  return found
end

local function lockFoe(t: Test.Context, a: Arena)
  order(t, a, { kind = "LockTarget", actor = 0, target = a.foe.id })
  stepUntil(a, "LockCompleted", 30)
end

local function modules(a: Arena): { State.Item }
  return Items.Fitted(a.game.state, a.game.state.player.ship)
end

local CANNONS = { { "autocannon.small", "ammo.emp" }, { "autocannon.small", "ammo.emp" } }

suite:Case("a lock takes the time the formula gives, and no shot before it", function(t)
  local a = arena("frigate.courier", CANNONS, "frigate.courier", {}, 2000)
  local cannon = modules(a)[1]
  t.eq(refused(a, { kind = "ActivateModule", actor = 0, item = cannon.id, target = a.foe.id }), "no locked target")
  order(t, a, { kind = "LockTarget", actor = 0, target = a.foe.id })
  local started = stepUntil(a, "LockStarted", 2)
  t.near(started.time, Gunnery.LockTime(580, 38), 1e-9)
  t.eq(refused(a, { kind = "LockTarget", actor = 0, target = a.foe.id }), "already targeted")
  t.eq(refused(a, { kind = "ActivateModule", actor = 0, item = cannon.id, target = a.foe.id }), "no locked target")
  local _, ticks = stepUntil(a, "LockCompleted", 30)
  t.eq(ticks, math.ceil(started.time), "it completes on the first tick past its time")
  t.eq(refused(a, { kind = "ActivateModule", actor = 0, item = cannon.id, target = a.foe.id }), "(accepted)")
end)

suite:Case("locks have a range and a limit", function(t)
  local a = arena("frigate.courier", CANNONS, "frigate.courier", {}, 30000)
  t.eq(refused(a, { kind = "LockTarget", actor = 0, target = a.foe.id }), "out of targeting range")
  t.eq(refused(a, { kind = "LockTarget", actor = 0, target = a.me.id }), "no such target")
  t.eq(refused(a, { kind = "UnlockTarget", actor = 0, target = a.foe.id }), "not targeted")
  -- a courier can hold three
  a.foe.x = a.me.x + 3000
  local state = a.game.state
  local extras = {}
  for i = 1, 3 do
    local ship = Space.NewShip(state, "frigate.courier", `Extra {i}`, "pirate", 0)
    extras[i] = Space.Launch(state, ship, 1, a.me.x, a.me.y + 2000 * i, a.me.z)
  end
  order(t, a, { kind = "LockTarget", actor = 0, target = a.foe.id })
  order(t, a, { kind = "LockTarget", actor = 0, target = extras[1].id })
  order(t, a, { kind = "LockTarget", actor = 0, target = extras[2].id })
  Core.Step(a.game)
  t.eq(refused(a, { kind = "LockTarget", actor = 0, target = extras[3].id }), "no more targets can be locked")
  -- How many is the hull's to say, and its pilot's skill's: a fifth more a level of Target Management, of
  -- what the hull allows, in whole targets. (A Courier's three are three at one level and four at two.)
  local courier = Ships.byId["frigate.courier"]
  for level, most in { 3, 4, 4, 5, 6 } do
    local stats = Attributes.Ship(courier, {}, { ["target.management"] = level })
    t.eq(math.floor(stats.maxTargets + 1e-6), most, `a Courier at Target Management {level}`)
  end
  t.eq(math.floor(Attributes.Ship(Ships.byId["battleship.owari"], {}, { ["target.management"] = 5 }).maxTargets + 1e-6), 14)
  -- Trained, and the ship's count brought into line with it (as it is on leaving a station): a fourth lock.
  state.skills["target.management"] = 2
  Vitals.Refresh(state, a.me)
  t.eq(a.me.vitals.maxTargets, 4)
  t.eq(refused(a, { kind = "LockTarget", actor = 0, target = extras[3].id }), "(accepted)")
  order(t, a, { kind = "LockTarget", actor = 0, target = extras[3].id })
  Core.Step(a.game)
  t.eq(#a.me.vitals.locks, 4)
end)

suite:Case("autocannons at rest hit as often and as hard as the formula says", function(t)
  -- EMP halves the 1100 m optimal; at 2000 m the target is 1450 m into a
  -- 5200 m falloff.
  local a = arena("frigate.courier", CANNONS, "industrial.hauler", {}, 2000)
  local chance = Gunnery.HitChance(0, 470, 180, 2000, 550, 5200)
  t.near(chance, 0.5 ^ ((1450 / 5200) ^ 2), 1e-12)
  lockFoe(t, a)
  for _, cannon in modules(a) do
    order(t, a, { kind = "ActivateModule", actor = 0, item = cannon.id, target = a.foe.id })
  end
  -- Count shots until the target dies (or four minutes pass).
  local shots, hits, wrecks, damage = 0, 0, 0, 0
  for _ = 1, 240 do
    Core.Step(a.game)
    for _, event in Core.TakeEvents(a.game) do
      if event.kind == "Shot" then
        shots += 1
        damage += event.damage
        if event.outcome ~= "miss" then
          hits += 1
        end
        if event.outcome == "wreck" then
          wrecks += 1
        end
      end
    end
  end
  t.ok(shots > 150, `only {shots} shots in four minutes`)
  -- two guns, one shot each per 2.8 s
  t.near(shots, 2 * 240 / 2.8, 4)
  t.near(hits / shots, chance, 0.06, "share of shots that hit")
  -- 24 raw damage a shot (EMP 12 x multiplier 2), times the average
  -- quality: 1% wrecking at 3x, the rest of the hits at roll + 0.49.
  local quality = 0.03 + (chance ^ 2 - 0.0001) / 2 + 0.49 * (chance - 0.01)
  t.near(damage / shots, 24 * quality, 24 * 0.08, "raw damage per shot")
  t.ok(wrecks <= 8, `{wrecks} wrecking hits in {shots} shots`)
end)

suite:Case("a target crossing the line of fire is harder to hit than one flying along it", function(t)
  local a = arena("frigate.courier", CANNONS, "frigate.courier", {}, 420)
  local state = a.game.state
  local cannon = modules(a)[1]
  local function chance(): number
    return assert(Combat.HitChance(state, a.me.id, cannon.id, a.foe.id))
  end
  -- 420 m between surfaces, 500 m between centres, inside optimal: certain.
  t.eq(chance(), 1)
  -- Flying straight away at 300 m/s: still no crossing.
  a.foe.vx = 300
  t.eq(chance(), 1)
  -- Crossing at 300 m/s: 0.6 rad/s. Against tracking 470 and a 38 m
  -- signature that is 0.6 * 40000 / (470 * 38) = 1.344 times what the gun
  -- can follow.
  a.foe.vx, a.foe.vz = 0, 300
  t.near(chance(), 0.5 ^ ((0.6 * 40000 / (470 * 38)) ^ 2), 1e-12)
  -- It is relative motion that counts: matching its velocity cancels it.
  a.me.vz = 300
  t.eq(chance(), 1)
  -- The same crossing speed from five times as far is a fifth of the turn
  -- rate, though now 1930 m into falloff.
  a.me.vz = 0
  a.foe.x += 2000
  local far = Gunnery.HitChance(300 / 2500, 470, 38, 2420, 550, 5200)
  t.near(chance(), far, 1e-12)
  t.ok(far > 0.8, "which is much the easier shot")
  -- A hauler crossing at the first distance is a big enough target to follow.
  t.eq(Combat.HitChance(state, a.me.id, 12345, a.foe.id), nil)
end)

suite:Case("a tech 2 charge's trade is in the shot: a short one's gun tracks worse, a middle one's better and nearer, a long one's reaches further", function(t)
  local a = arena("frigate.courier", CANNONS, "frigate.courier", {}, 420)
  local state = a.game.state
  local cannon = modules(a)[1]
  local function chance(charge: string): number
    cannon.charge = charge
    return assert(Combat.HitChance(state, a.me.id, cannon.id, a.foe.id))
  end
  -- Crossing at 300 m/s from 500 m: 0.6 rad/s, against tracking 470 and a 38 m signature.
  a.foe.vx, a.foe.vz = 0, 300
  local function tracked(share: number): number
    return 0.5 ^ ((0.6 * 40000 / (470 * share * 38)) ^ 2)
  end
  -- (the short rounds, at half the gun's range: in reach here, so it is all tracking)
  t.near(chance("ammo.fusion"), tracked(1), 1e-12)
  t.near(chance("ammo.fusion.ii"), tracked(0.75), 1e-12)
  -- (the middle rounds: the gun follows three tenths better with the tech 2 make)
  t.near(chance("ammo.sabot"), tracked(1), 1e-12)
  t.near(chance("ammo.sabot.ii"), tracked(1.3), 1e-12)
  t.ok(chance("ammo.sabot.ii") > chance("ammo.sabot") and chance("ammo.fusion.ii") < chance("ammo.fusion"))
  -- Not crossing, from far off: range is all of it. The middle rounds' tech 2 make reaches a seventh less.
  a.foe.vz = 0
  a.foe.x += 4000
  local gap = 4420
  t.near(chance("ammo.sabot"), Gunnery.HitChance(0, 470, 38, gap, 1100, 5200), 1e-12)
  t.near(chance("ammo.sabot.ii"), Gunnery.HitChance(0, 470 * 1.3, 38, gap, 1100 * 0.85, 5200), 1e-12)
  t.ok(chance("ammo.sabot.ii") < chance("ammo.sabot"), "the middle rounds' tech 2 make should give up some range")
end)

suite:Case("damage goes through shield, armour and hull, and the ship dies", function(t)
  local a = arena("frigate.battleaxe", { { "laser.pulse.small", "crystal.multifrequency" },
    { "laser.pulse.small", "crystal.multifrequency" }, { "laser.pulse.small", "crystal.multifrequency" } },
    "frigate.courier", {}, 1500)
  local foe = a.foe.id
  lockFoe(t, a)
  for _, laser in modules(a) do
    order(t, a, { kind = "ActivateModule", actor = 0, item = laser.id, target = foe })
  end
  local sawShield, sawArmor, sawHull = false, false, false
  local died: Space.Event? = nil
  local stopped = 0
  for _ = 1, 300 do
    Core.Step(a.game)
    for _, event in Core.TakeEvents(a.game) do
      if event.kind == "DamageApplied" then
        -- never a deeper layer before the one above it is gone
        t.ok(event.armor == 0 or a.foe.vitals.shield == 0, "armour was hit while shield stood")
        t.ok(event.hull == 0 or a.foe.vitals.armor == 0, "hull was hit while armour stood")
        sawShield = sawShield or event.shield > 0
        sawArmor = sawArmor or event.armor > 0
        sawHull = sawHull or event.hull > 0
      elseif event.kind == "BallDestroyed" then
        died = event
      elseif event.kind == "ModuleStopped" then
        stopped += 1
        t.eq(event.reason, "target lost")
      end
    end
    if died then
      break
    end
  end
  t.ok(sawShield and sawArmor and sawHull, "all three layers took damage")
  local death = assert(died, "the target survived five minutes of three lasers")
  t.eq({ death.ball, death.by }, { foe, a.me.id })
  t.eq(Core.Query.Ball(a.game, foe), nil, "it is gone from space")
  t.eq(a.game.state.ships[foe], nil, "and from the world")
  Core.Step(a.game)
  for _, event in Core.TakeEvents(a.game) do
    if event.kind == "ModuleStopped" then
      stopped += 1
    end
  end
  t.eq(stopped, 3, "the lasers stop when there is nothing to shoot")
  t.eq(#a.me.vitals.locks, 0)
end)

suite:Case("a missile lands after its flight and does less to a small target", function(t)
  local a = arena("frigate.carvarro", { { "launcher.light", "missile.light.kinetic" } }, "frigate.courier", {}, 10000)
  lockFoe(t, a)
  local launcher = modules(a)[1]
  order(t, a, { kind = "ActivateModule", actor = 0, item = launcher.id, target = a.foe.id })
  local shot = stepUntil(a, "Shot", 3)
  t.eq(shot.outcome, "launched")
  local flight = Space.Distance(a.me :: any, a.foe :: any) / 3750
  t.near(shot.flight, flight, 1e-9)
  local hit, ticks = stepUntil(a, "MissileHit", 10)
  t.eq(ticks, math.ceil(flight))
  -- 83 kinetic, and 15% more from a Talmar hull, which leans to kinetic; times 38/40 for a courier's signature
  -- against a 40 m blast
  t.near(hit.damage, 83 * 1.15 * 38 / 40, 1e-9)
  -- and the shield lets 60% of kinetic through
  t.near(a.foe.vitals.shieldMax - a.foe.vitals.shield, 83 * 1.15 * 38 / 40 * 0.6, 1.5)
  t.eq(launcher.rounds, 29)
end)

suite:Case("a missile fired from beyond its reach does nothing", function(t)
  local a = arena("frigate.carvarro", { { "launcher.light", "missile.light.kinetic" } }, "frigate.courier", {}, 20000)
  lockFoe(t, a)
  order(t, a, { kind = "ActivateModule", actor = 0, item = modules(a)[1].id, target = a.foe.id })
  t.eq(stepUntil(a, "Shot", 3).outcome, "out of range")
  t.eq(#gather(a, 10, "MissileHit"), 0)
  t.eq(a.foe.vitals.shield, a.foe.vitals.shieldMax)
end)

suite:Case("a shield booster mends per cycle until the capacitor gives out", function(t)
  local a = arena("frigate.courier", { { "shield.booster.small" } }, "frigate.courier", {}, 5000)
  local v = a.me.vitals
  v.shield = 50
  local booster = modules(a)[1]
  order(t, a, { kind = "ActivateModule", actor = 0, item = booster.id })
  Core.Step(a.game)
  Core.Step(a.game)
  -- one cycle so far (they are 2 s apart): 26 points, less the trickle of
  -- passive recharge either side
  t.ok(v.shield > 50 + 26 and v.shield < 50 + 26 + 4, `shield is {v.shield}`)
  t.ok(v.capacitor < v.capacitorMax - 15)
  local stoppedBy = stepUntil(a, "ModuleStopped", 120)
  t.eq(stoppedBy.reason, "capacitor empty")
  t.ok(v.capacitor < 18, "it ran until it could not pay for a cycle")
  t.eq(#v.running, 0)
end)

suite:Case("an afterburner changes how the ship flies while it runs", function(t)
  local a = arena("frigate.courier", { { "afterburner.1mn" } }, "frigate.courier", {}, 5000)
  local burner = modules(a)[1]
  order(t, a, { kind = "ActivateModule", actor = 0, item = burner.id })
  Core.Step(a.game)
  t.near(a.me.maxVelocity, 360 * 2.1, 1e-9)
  t.near(a.me.tau, 3.2 * 1.6, 1e-9)
  t.eq(refused(a, { kind = "ActivateModule", actor = 0, item = burner.id }), "already running")
  order(t, a, { kind = "DeactivateModule", actor = 0, item = burner.id })
  Core.Step(a.game)
  t.near(a.me.maxVelocity, 360 * 2.1, 1e-9, "it finishes the cycle it is in")
  local stopped = stepUntil(a, "ModuleStopped", 12)
  t.eq(stopped.reason, "switched off")
  t.near(a.me.maxVelocity, 360, 1e-9)
  t.near(a.me.tau, 3.52, 1e-9)
end)

suite:Case("guns reload from the hold, and stop when it is empty", function(t)
  local a = arena("frigate.courier", { { "autocannon.small", "ammo.emp" } }, "industrial.hauler", {}, 1500)
  local cannon = modules(a)[1]
  cannon.rounds = 2
  Items.Add(a.game.state, "ammo.emp", 3, a.me.id, "cargo")
  lockFoe(t, a)
  order(t, a, { kind = "ActivateModule", actor = 0, item = cannon.id, target = a.foe.id })
  local kinds: { string } = {}
  for _ = 1, 40 do
    Core.Step(a.game)
    for _, event in Core.TakeEvents(a.game) do
      if event.kind == "Shot" or event.kind == "Reloading" or event.kind == "ModuleStopped" then
        table.insert(kinds, if event.kind == "ModuleStopped" then event.reason else event.kind)
      end
    end
  end
  t.eq(kinds, { "Shot", "Shot", "Reloading", "Shot", "Shot", "Shot", "out of ammunition" })
  t.eq(#Items.In(a.game.state, a.me.id, "cargo"), 0)
end)

suite:Case("warping away drops locks and stops modules", function(t)
  local a = arena("frigate.courier", CANNONS, "frigate.courier", {}, 2000)
  lockFoe(t, a)
  order(t, a, { kind = "ActivateModule", actor = 0, item = modules(a)[1].id, target = a.foe.id })
  Core.Step(a.game)
  t.eq({ #a.me.vitals.locks, #a.me.vitals.running }, { 1, 1 })
  local far: number? = nil
  for _, entry in Core.Query.Overview(a.game) do
    if entry.kind == "planet" and entry.distance > 1e9 then
      far = entry.id
      break
    end
  end
  order(t, a, { kind = "WarpTo", actor = 0, target = assert(far) })
  stepUntil(a, "WarpStarted", 30)
  t.eq({ #a.me.vitals.locks, #a.me.vitals.running }, { 0, 0 })
  t.eq(refused(a, { kind = "LockTarget", actor = 0, target = a.foe.id }), "in warp")
end)

suite:Case("docking keeps the damage; the shield comes back", function(t)
  local a = arena("frigate.courier", CANNONS, "frigate.courier", {}, 2000)
  a.me.vitals.armor -= 120
  a.me.vitals.shield = 10
  order(t, a, { kind = "Dock", actor = 0, target = a.game.state.player.home })
  stepUntil(a, "Docked", 600)
  local ship = a.game.state.ships[a.game.state.player.ship]
  t.near(ship.armorDamage, 120, 1e-9)
  Core.Submit(a.game, { kind = "Undock", actor = ship.id })
  Core.Step(a.game)
  local again = assert(Core.Query.Ball(a.game, ship.id))
  t.near(again.vitals.armor, again.vitals.armorMax - 120, 1e-9, "the armour is still damaged")
  t.eq(again.vitals.shield, again.vitals.shieldMax, "the shield is full again")
end)

suite:Case("a ship destroyed takes its locks and everything aboard with it", function(t)
  local a = arena("frigate.courier", CANNONS, "frigate.courier", {}, 1500)
  local foe = a.foe.id
  Items.Add(a.game.state, "ammo.emp", 50, foe, "cargo")
  lockFoe(t, a)
  for _, cannon in modules(a) do
    order(t, a, { kind = "ActivateModule", actor = 0, item = cannon.id, target = foe })
  end
  stepUntil(a, "BallDestroyed", 300)
  t.eq(#Items.In(a.game.state, foe, nil), 0)
  t.eq(a.game.state.ships[foe], nil)
end)

suite:Case("the same seeds give the same fight, and a save in mid-fight carries on unchanged", function(t)
  local function fight(historySeed: number, reloadAt: number?): string
    local a = arena("frigate.battleaxe", { { "laser.pulse.small", "crystal.multifrequency" },
      { "laser.pulse.small", "crystal.multifrequency" } }, "industrial.hauler", {}, 3000, historySeed)
    lockFoe(t, a)
    for _, laser in modules(a) do
      order(t, a, { kind = "ActivateModule", actor = 0, item = laser.id, target = a.foe.id })
    end
    local game = a.game
    for tick = 1, 60 do
      Core.Step(game)
      if tick == reloadAt then
        local data, length = Core.Save(game)
        game = Core.Load(data, length)
      end
    end
    return Core.Hash(game)
  end
  local straight = fight(1, nil)
  t.eq(fight(1, nil), straight)
  t.eq(fight(1, 25), straight, "reloaded at tick 25")
  t.ok(fight(2, nil) ~= straight, "a different history seed rolls different dice")
end)

-- ---------------------------------------------------------------------
-- Holding another ship: the entanglement projector and the warp disruptor

local TACKLE = { { "projector.entanglement" }, { "disruptor.warp" } }

suite:Case("an entanglement projector cuts its target's speed while it runs, and only the strongest one counts", function(t)
  local a = arena("frigate.courier", TACKLE, "frigate.courier", {}, 3000)
  local state = a.game.state
  local projector = modules(a)[1]
  local was = a.foe.maxVelocity
  t.eq(refused(a, { kind = "ActivateModule", actor = 0, item = projector.id, target = a.foe.id }), "no locked target")
  lockFoe(t, a)
  order(t, a, { kind = "ActivateModule", actor = 0, item = projector.id, target = a.foe.id })
  local held = stepUntil(a, "Held", 3)
  t.eq({ held.ball, held.entangle, held.scrambled } :: { any }, { a.foe.id, 0.45, false } :: { any })
  t.near(a.foe.maxVelocity, was * 0.45, 1e-6)
  t.eq(a.foe.vitals.entangle, 0.45)
  -- A second projector on it, from somebody else, makes it no slower.
  local other = Space.NewShip(state, "frigate.courier", "Second", "player", 0)
  local second = Items.Equip(state, other.id, "projector.entanglement", nil)
  local ball = Space.Launch(state, other, 1, a.me.x, a.me.y + 500, a.me.z)
  table.insert(ball.vitals.locks, { target = a.foe.id, done = 0, locked = true })
  table.insert(ball.vitals.running, { item = second.id, target = a.foe.id, next = 0, stopping = false, cycles = 0 })
  Core.Step(a.game)
  t.near(a.foe.maxVelocity, was * 0.45, 1e-6)
  ball.vitals.running = {}
  -- It costs capacitor every cycle, and switched off, the target is free.
  local capacitor = a.me.vitals.capacitor
  gather(a, 11, "none")
  t.ok(a.me.vitals.capacitor < capacitor - 4, "an entanglement projector should cost capacitor to keep running")
  order(t, a, { kind = "DeactivateModule", actor = 0, item = projector.id })
  gather(a, 7, "none")
  t.near(a.foe.maxVelocity, was, 1e-6)
  t.eq(a.foe.vitals.entangle, 1)
end)

suite:Case("a warp disruptor keeps its target out of warp, and reaches twice as far as an entanglement projector", function(t)
  local a = arena("frigate.courier", TACKLE, "frigate.courier", {}, 15000)
  local state = a.game.state
  local projector, disruptor = modules(a)[1], modules(a)[2]
  lockFoe(t, a)
  t.eq(refused(a, { kind = "ActivateModule", actor = 0, item = projector.id, target = a.foe.id }), "out of range")
  -- The target is getting ready to warp when it is caught.
  local far = 0
  for _, object in Core.Query.Objects(a.game, 1) do
    if object.kind == "planet" and far == 0 then
      far = object.id
    end
  end
  local warp: State.Command = { kind = "WarpTo", actor = a.foe.id, target = far }
  t.ok((Space.Validate(state, warp)))
  Space.Apply(state, warp, a.game.events)
  t.ok(a.foe.warp ~= nil)
  order(t, a, { kind = "ActivateModule", actor = 0, item = disruptor.id, target = a.foe.id })
  local held = stepUntil(a, "Held", 3)
  t.eq({ held.ball, held.entangle, held.scrambled } :: { any }, { a.foe.id, 1, true } :: { any })
  t.eq(a.foe.warp, nil)
  t.eq({ Space.Validate(state, warp) } :: { any }, { false, "warp scrambled" } :: { any })
  -- (an order to dock far off is still taken: it sets off the slow way)
  local dock: State.Command = { kind = "Dock", actor = a.foe.id, target = state.player.home }
  t.ok((Space.Validate(state, dock)))
  Space.Apply(state, dock, a.game.events)
  t.eq({ a.foe.warp, a.foe.mode } :: { any }, { nil, "approach" } :: { any })
  -- Out of its reach, the hold is broken.
  a.foe.x += 30000
  stepUntil(a, "Held", 8)
  t.ok(not a.foe.vitals.scrambled)
  t.ok((Space.Validate(state, warp)))
  -- It is for ships: a rock cannot be held.
  t.eq(refused(a, { kind = "ActivateModule", actor = 0, item = disruptor.id, target = far }), "no locked target")
end)

suite:Case("a capital is held only by a capital warp disruptor, which only a capital fits", function(t)
  local plain, capital = Modules.byId["disruptor.warp"], Modules.byId["disruptor.warp.capital"]
  t.eq({ plain.capital, capital.capital, assert(capital.hex).kind } :: { any }, { nil, true, "scramble" } :: { any })
  t.ok(assert(capital.hex).range > assert(plain.hex).range and assert(capital.hex).capacitor > assert(plain.hex).capacitor)
  -- Only a capital fits one: a battleship does not, and a carrier does.
  t.eq({ Attributes.Check(Ships.byId["battleship.owari"], { "disruptor.warp.capital" }) } :: { any },
    { false, "only a capital fits that" } :: { any })
  t.eq((Attributes.Check(Ships.byId["carrier.azayake"], { "disruptor.warp.capital" })), true)
  t.eq((Attributes.Check(Ships.byId["battleship.owari"], { "disruptor.warp" })), true)
  -- A plain disruptor does nothing to a capital: it is refused, and one that is running on it all the same
  -- holds nothing.
  local a = arena("frigate.courier", { { "disruptor.warp" } }, "carrier.azayake", {}, 15000)
  t.eq({ Combat.Capital(a.game.state, a.foe.id), Combat.Capital(a.game.state, a.me.id) }, { true, false })
  lockFoe(t, a)
  local disruptor = modules(a)[1]
  t.eq(refused(a, { kind = "ActivateModule", actor = 0, item = disruptor.id, target = a.foe.id }),
    "a capital is held only by a capital warp disruptor")
  table.insert(a.me.vitals.running, { item = disruptor.id, target = a.foe.id, next = 0, stopping = false, cycles = 0 })
  gather(a, 3, "none")
  t.eq(a.foe.vitals.scrambled, false)
  -- A capital's holds a capital, from half as far again.
  local b = arena("carrier.azayake", { { "disruptor.warp.capital" } }, "carrier.scoppo", {}, 25000)
  lockFoe(t, b)
  order(t, b, { kind = "ActivateModule", actor = 0, item = modules(b)[1].id, target = b.foe.id })
  local held = stepUntil(b, "Held", 3)
  t.eq({ held.ball, held.scrambled } :: { any }, { b.foe.id, true } :: { any })
  t.eq(b.foe.vitals.scrambled, true)
  -- And anything smaller.
  local c = arena("carrier.azayake", { { "disruptor.warp.capital" } }, "battleship.owari", {}, 25000)
  lockFoe(t, c)
  order(t, c, { kind = "ActivateModule", actor = 0, item = modules(c)[1].id, target = c.foe.id })
  t.eq(stepUntil(c, "Held", 3).scrambled, true)
end)

suite:Case("a gun fixed along a bow is fired by pointing the ship: aligned to its target as for a warp, one round, and then it cycles", function(t)
  -- The Drowned's ultracapital has one (the project owner's: "special, fixed bow railgun"), and nothing else has.
  local gun = assert(Ships.byId["ultracapital.theend"].spinal, "The End has no bow gun")
  for _, hull in Ships.list do
    t.eq(hull.spinal ~= nil, hull.id == "ultracapital.theend", hull.id)
  end
  t.eq({ gun.name, gun.family } :: { any }, { "Bow Railgun", "hybrid" } :: { any })
  -- A round is a hundred of a siege dreadnought's, and it follows nothing: a capital lying still is hit
  -- squarely, and a frigate crossing is as good as never hit.
  local round = gun.damage[1] + gun.damage[2] + gun.damage[3] + gun.damage[4]
  t.ok(round >= 30000 and gun.duration >= 20, `a round of {round} every {gun.duration} s`)
  t.eq(Gunnery.HitChance(0, gun.tracking, 3200, 50000, gun.optimal, gun.falloff), 1)
  t.ok(Gunnery.HitChance(0.02, gun.tracking, 35, 50000, gun.optimal, gun.falloff) < 0.001)

  local plain = arena("carrier.azayake", {}, "carrier.scoppo", {}, 50000)
  t.eq(Core.Query.Spinal(plain.game, plain.me.id), nil)
  t.eq(refused(plain, { kind = "FireSpinal", actor = 0, target = plain.foe.id }), "this hull has no gun of its own")

  local a = arena("ultracapital.theend", {}, "carrier.scoppo", {}, 50000)
  local status = assert(Core.Query.Spinal(a.game, a.me.id))
  t.eq({ status.name, status.aiming, status.cycling, status.capacitor } :: { any }, { "Bow Railgun", false, 0, gun.capacitor } :: { any })
  t.eq(refused(a, { kind = "FireSpinal", actor = 0, target = a.foe.id }), "no locked target")
  lockFoe(t, a)
  -- Told to fire, the ship turns for its target, and nothing is fired while it is not yet pointed at it.
  local whole = a.foe.vitals.shield + a.foe.vitals.armor + a.foe.vitals.hull
  local capacitor = a.me.vitals.capacitor
  order(t, a, { kind = "FireSpinal", actor = 0, target = a.foe.id })
  Core.Step(a.game)
  Core.TakeEvents(a.game)
  t.eq({ a.me.mode, a.me.vitals.spinalTarget, assert(Core.Query.Spinal(a.game, a.me.id)).aiming } :: { any },
    { "align", a.foe.id, true } :: { any })
  t.eq(a.foe.vitals.shield + a.foe.vitals.armor + a.foe.vitals.hull, whole)
  -- Pointed at it, and moving as it would have to be to warp there, it fires: one round.
  local shot: any = nil
  local ticks = 0
  while shot == nil and ticks < 2400 do
    ticks += 1
    Core.Step(a.game)
    for _, event in Core.TakeEvents(a.game) do
      if event.kind == "Shot" and event.spinal then
        shot = event
        -- (it was aligned when it fired)
        t.ok(Space.AlignedTo(a.me, a.foe.x, a.foe.y, a.foe.z), "the bow gun fired from a ship that was not pointed at its target")
      end
    end
  end
  t.ok(shot ~= nil, "the bow gun never fired")
  t.ok(ticks > 5, `a ship at rest was pointed at its target in {ticks} ticks`)
  t.eq({ shot.from, shot.to, shot.item, shot.look } :: { any }, { a.me.id, a.foe.id, 0, "railgun.xl" } :: { any })
  t.ok(shot.outcome ~= "miss" and shot.damage >= 0.49 * round, `a carrier lying still was not hit squarely: {shot.outcome}, {shot.damage}`)
  local left = a.foe.vitals.shield + a.foe.vitals.armor + a.foe.vitals.hull
  t.ok(left < whole - 5000, `the round took {whole - left} off a carrier`)
  -- It took its capacitor, the shot is done with, and the gun is cycling.
  t.ok(a.me.vitals.capacitor < capacitor - gun.capacitor * 0.5)
  t.eq(a.me.vitals.spinalTarget, nil)
  local cycling = assert(Core.Query.Spinal(a.game, a.me.id)).cycling
  t.ok(cycling > gun.duration - 2 and cycling <= gun.duration, `cycling for {cycling} s`)
  t.ok(string.find(tostring(refused(a, { kind = "FireSpinal", actor = 0, target = a.foe.id })), "cycling", 1, true) ~= nil)
  -- Cycled, it can be told again; and any other order to the helm calls the shot off.
  a.me.vitals.spinalReady = nil
  a.me.vx, a.me.vy, a.me.vz = 0, 0, 0
  order(t, a, { kind = "FireSpinal", actor = 0, target = a.foe.id })
  Core.Step(a.game)
  t.eq(a.me.vitals.spinalTarget, a.foe.id)
  order(t, a, { kind = "Stop", actor = 0 })
  Core.Step(a.game)
  Core.Step(a.game)
  t.eq(a.me.vitals.spinalTarget, nil)
  -- With the capacitor short of a round it is refused.
  a.me.vitals.capacitor = gun.capacitor - 1
  t.eq(refused(a, { kind = "FireSpinal", actor = 0, target = a.foe.id }), `needs {gun.capacitor} GJ of capacitor`)
end)

suite:Case("a raider carries a warp disruptor, and a pilot it catches cannot warp away", function(t)
  local raider = Pirates.kindById["raider"]
  local fitted: { [string]: boolean } = {}
  for _, entry in Pirates.Fit(raider) do
    fitted[entry[1]] = true
  end
  t.ok(fitted["disruptor.warp"], "a raider has no warp disruptor")
  local jackal: { [string]: boolean } = {}
  for _, entry in Pirates.Fit(Pirates.kindById["jackal"]) do
    jackal[entry[1]] = true
  end
  t.ok(jackal["projector.entanglement"], "a jackal has no entanglement projector")
  for _, entry in Pirates.Fit(Pirates.SCOUT) do
    t.ok(Modules.byId[entry[1]].hex == nil, "a scout should hold nobody")
  end

  local a = arena("battleship.owari", {}, "frigate.courier", {}, 60000)
  local state = a.game.state
  local pirate = Pirates.Spawn(state, raider, 1, a.me.x + 6000, a.me.y, a.me.z, a.me.grid)
  local planet = 0
  for _, object in Core.Query.Objects(a.game, 1) do
    if object.kind == "planet" and planet == 0 then
      planet = object.id
    end
  end
  t.eq(refused(a, { kind = "WarpTo", actor = 0, target = planet }), "(accepted)")
  local caught = false
  for _ = 1, 60 do
    Core.Step(a.game)
    caught = caught or a.me.vitals.scrambled
  end
  t.ok(caught, "a raider six kilometres off did not catch a battleship in a minute")
  t.eq(refused(a, { kind = "WarpTo", actor = 0, target = planet }), "warp scrambled")
  -- With the raider gone, it can.
  Aftermath.Destroy(state, pirate.id, 0, a.game.events)
  Core.Step(a.game)
  t.eq(refused(a, { kind = "WarpTo", actor = 0, target = planet }), "(accepted)")
end)

suite:Case("a painter swells its target's signature, and a dampener cuts how far it can see", function(t)
  local a = arena("frigate.courier", { { "painter.target" }, { "damper.sensor" } }, "frigate.courier", CANNONS, 12000)
  local state = a.game.state
  local painter, damper = modules(a)[1], modules(a)[2]
  local signature, range, resolution = a.foe.vitals.signature, a.foe.vitals.lockRange, a.foe.vitals.scanResolution
  lockFoe(t, a)
  -- (the other ship has a lock of its own, on the player)
  table.insert(a.foe.vitals.locks, { target = a.me.id, done = 0, locked = true })
  order(t, a, { kind = "ActivateModule", actor = 0, item = painter.id, target = a.foe.id })
  gather(a, 2, "none")
  t.near(a.foe.vitals.signature, signature * 1.3, 1e-6)
  t.eq({ a.foe.vitals.paint, a.foe.vitals.damp }, { 1.3, 1 })
  t.eq(#a.foe.vitals.locks, 1)
  -- Dampened to half its range, it cannot keep a lock from twelve kilometres.
  order(t, a, { kind = "ActivateModule", actor = 0, item = damper.id, target = a.foe.id })
  local lost = stepUntil(a, "LockLost", 4)
  t.eq({ lost.ball, lost.target } :: { any }, { a.foe.id, a.me.id } :: { any })
  t.near(a.foe.vitals.lockRange, range * 0.5, 1e-6)
  t.near(a.foe.vitals.scanResolution, resolution * 0.5, 1e-6)
  t.eq(#a.foe.vitals.locks, 0)
  -- Switched off, it is as it was.
  order(t, a, { kind = "DeactivateModule", actor = 0, item = painter.id })
  order(t, a, { kind = "DeactivateModule", actor = 0, item = damper.id })
  gather(a, 7, "none")
  t.near(a.foe.vitals.signature, signature, 1e-6)
  t.near(a.foe.vitals.lockRange, range, 1e-6)
  t.ok(state.balls[a.foe.id] ~= nil)
end)

suite:Case("a neutraliser empties its target's capacitor, and a jammer breaks its locks sooner or later", function(t)
  local a = arena("frigate.courier", { { "neutraliser.small" }, { "jammer.ecm" } }, "frigate.courier", CANNONS, 3000)
  local neutraliser, jammer = modules(a)[1], modules(a)[2]
  lockFoe(t, a)
  local theirs, mine = a.foe.vitals.capacitor, a.me.vitals.capacitor
  order(t, a, { kind = "ActivateModule", actor = 0, item = neutraliser.id, target = a.foe.id })
  gather(a, 2, "none")
  -- (less what a capacitor gets back in a second or two)
  t.ok(a.foe.vitals.capacitor <= theirs - 35, "a neutraliser's first cycle should take most of its 45 GJ")
  t.ok(a.me.vitals.capacitor < mine - 20, "and cost its owner capacitor too")
  gather(a, 40, "none")
  t.ok(a.foe.vitals.capacitor < theirs * 0.35 or a.me.vitals.capacitor < 30, "forty seconds of neutralising left the target its capacitor")
  order(t, a, { kind = "DeactivateModule", actor = 0, item = neutraliser.id })
  -- The jammer: the target has a lock, and loses it within a few cycles.
  local broken = 0
  for seed = 1, 6 do
    local b = arena("frigate.courier", { { "jammer.ecm" } }, "frigate.courier", CANNONS, 3000, seed)
    lockFoe(t, b)
    table.insert(b.foe.vitals.locks, { target = b.me.id, done = 0, locked = true })
    order(t, b, { kind = "ActivateModule", actor = 0, item = modules(b)[1].id, target = b.foe.id })
    for _ = 1, 60 do
      Core.Step(b.game)
      if #b.foe.vitals.locks == 0 then
        broken += 1
        break
      end
    end
  end
  t.ok(broken >= 4, `a jammer broke a lock in a minute on only {broken} of 6 tries`)
  t.ok(jammer ~= nil)
end)

-- ---------------------------------------------------------------------
-- Salvaging

suite:Case("a salvager strips a wreck, once, in as many cycles as luck and skill allow", function(t)
  local a = arena("frigate.courier", { { "salvager.small" } }, "frigate.courier", {}, 2000)
  local state = a.game.state
  local salvager = modules(a)[1]
  -- A ship is not a wreck. Destroy it (nobody's kill) and it is.
  t.eq(refused(a, { kind = "ActivateModule", actor = 0, item = salvager.id, target = a.foe.id }), "that is not a wreck")
  Aftermath.Destroy(state, a.foe.id, 0, a.game.events)
  local wreck = state.wrecks[state.wreckIds[#state.wreckIds]]
  for _, item in Items.In(state, wreck.id, "cargo") do
    Items.Take(state, item, item.quantity)
  end
  order(t, a, { kind = "ActivateModule", actor = 0, item = salvager.id, target = wreck.id })
  local capacitor = a.me.vitals.capacitor
  local done, cycles = stepUntil(a, "Salvaged", 400)
  t.eq({ done.ball, done.wreck } :: { any }, { a.me.id, wreck.id } :: { any })
  t.ok(cycles >= 10, "a salvager should take a cycle at the least")
  t.ok(a.me.vitals.capacitor < capacitor or cycles > 60, "salvaging should cost capacitor")
  -- What came off is in the hold, as much as the hull was big.
  local pieces = 0
  for _, item in Items.In(state, a.me.id, "cargo") do
    t.ok(string.sub(item.type, 1, 8) == "salvage.", `{item.type} came off a wreck`)
    pieces += item.quantity
  end
  t.eq(pieces, Combat.SALVAGE_PIECES * (1 + math.floor(wreck.radius / 40)))
  t.eq(pieces, done.pieces)
  -- It has stopped, the wreck (which had nothing aboard) is gone, and there is no second helping.
  t.eq(#a.me.vitals.running, 0)
  Core.Step(a.game)
  t.eq(state.wrecks[wreck.id], nil)
end)

suite:Case("a wreck with something aboard stays to be looted after it is salvaged, and skill makes salvaging quicker", function(t)
  local function cyclesFor(skill: number, seeds: number): number
    local total = 0
    for seed = 1, seeds do
      local a = arena("frigate.courier", { { "salvager.small" } }, "frigate.courier", {}, 2000, seed)
      local state = a.game.state
      state.skills.salvaging = skill
      Aftermath.Destroy(state, a.foe.id, 0, a.game.events)
      local wreck = state.wrecks[state.wreckIds[#state.wreckIds]]
      Items.Add(state, "scrap.metal", 5, wreck.id, "cargo")
      order(t, a, { kind = "ActivateModule", actor = 0, item = modules(a)[1].id, target = wreck.id })
      local _, ticks = stepUntil(a, "Salvaged", 600)
      total += ticks
      -- (still there, and marked)
      Core.Step(a.game)
      t.ok(state.wrecks[wreck.id] ~= nil and wreck.salvaged, "a wreck with cargo should outlast its salvaging")
      t.eq(refused(a, { kind = "ActivateModule", actor = 0, item = modules(a)[1].id, target = wreck.id }), "that wreck has been salvaged")
    end
    return total
  end
  local green, practised = cyclesFor(1, 12), cyclesFor(5, 12)
  t.ok(practised < green, `{practised} ticks with Salvaging 5 against {green} with Salvaging 1`)
  -- Out of reach it is refused.
  local a = arena("frigate.courier", { { "salvager.small" } }, "frigate.courier", {}, 9000)
  Aftermath.Destroy(a.game.state, a.foe.id, 0, a.game.events)
  local far = a.game.state.wreckIds[#a.game.state.wreckIds]
  t.eq(refused(a, { kind = "ActivateModule", actor = 0, item = modules(a)[1].id, target = far }), "out of range")
end)

-- ---------------------------------------------------------------------
-- Module expansion, the first group (2026-11-16): fitting and tank.

suite:Case("what the hull has to fit with and holds together by: a co-processor, a reactor unit, the relays and the bulkheads", function(t)
  local hull = Ships.byId["frigate.akashi"]
  local bare = Attributes.Ship(hull, {}, nil)
  local function with(type: string): Attributes.Stats
    return Attributes.Ship(hull, { { type = type, running = false } }, nil)
  end
  t.near(with("fitting.coprocessor").cpu, bare.cpu * 1.1, 1e-6)
  t.near(with("fitting.reactor").powergrid, bare.powergrid * 1.1, 1e-6)
  t.near(with("relay.shield").shieldRecharge, bare.shieldRecharge * 0.8, 1e-6)
  t.near(with("relay.shield").capacitorRecharge, bare.capacitorRecharge * 1.1, 1e-6)
  t.near(with("relay.capacitor").capacitorRecharge, bare.capacitorRecharge * 0.8, 1e-6)
  t.near(with("hull.bulkhead").hull, bare.hull * 1.25, 1e-6)
  t.ok(with("hull.bulkhead").cargo < bare.cargo, "bulkheads take room from the hold")
end)

suite:Case("a capacitor booster puts a charge into the capacitor each cycle, and reloads from the hold", function(t)
  local a = arena("frigate.akashi", { { "capacitor.booster.small", "booster.charge.small" } }, "frigate.courier", {}, 20000)
  local state = a.game.state
  local booster = Items.Fitted(state, a.me.id)[1]
  Items.Add(state, "booster.charge.small", 5, a.me.id, "cargo")
  t.eq({ booster.charge, booster.rounds } :: { any }, { "booster.charge.small", 3 } :: { any })
  a.me.vitals.capacitor = 10
  order(t, a, { kind = "ActivateModule", actor = 0, item = booster.id })
  local boosted = stepUntil(a, "CapacitorBoosted", 5)
  t.eq(boosted.amount, 100)
  t.ok(a.me.vitals.capacitor >= 100, `capacitor {a.me.vitals.capacitor}`)
  t.eq(booster.rounds, 2)
  -- (three charges, and then a reload of three more from the hold)
  stepUntil(a, "Reloading", 40)
  stepUntil(a, "CapacitorBoosted", 30)
  t.eq(booster.rounds, 2)
  local left = 0
  for _, item in Items.In(state, a.me.id, "cargo") do
    left += if item.type == "booster.charge.small" then item.quantity else 0
  end
  t.eq(left, 2)
end)

suite:Case("an ancillary armour repairer does three times as much with paste, and works on without it", function(t)
  local a = arena("frigate.akashi", { { "armor.repairer.ancillary.small", "paste.nanite" } }, "frigate.courier", {}, 20000)
  local state = a.game.state
  local repairer = Items.Fitted(state, a.me.id)[1]
  a.me.vitals.armor = 1
  order(t, a, { kind = "ActivateModule", actor = 0, item = repairer.id })
  local first = stepUntil(a, "Repaired", 5)
  t.eq(first.amount, 180)
  t.eq(repairer.rounds, 7)
  repairer.rounds = 0
  local plain = stepUntil(a, "Repaired", 20)
  t.eq(plain.amount, 60, "with no paste in the hold, it works as a plain one")
end)

suite:Case("an ancillary shield booster spends a charge in place of the capacitor", function(t)
  local a = arena("frigate.akashi", { { "shield.booster.ancillary.small", "booster.charge.small" } }, "frigate.courier", {}, 20000)
  local state = a.game.state
  local booster = Items.Fitted(state, a.me.id)[1]
  a.me.vitals.shield = 1
  local before = a.me.vitals.capacitor
  order(t, a, { kind = "ActivateModule", actor = 0, item = booster.id })
  stepUntil(a, "Repaired", 5)
  t.ok(a.me.vitals.capacitor >= before - 1, "a charged cycle draws no capacitor")
  t.eq(booster.rounds, 8)
end)

suite:Case("an adaptive armour hardener shifts its resistance toward what the ship is hit with", function(t)
  local a = arena("frigate.akashi", { { "armor.hardener.adaptive" } }, "frigate.courier", {}, 20000)
  local state = a.game.state
  local hardener = Items.Fitted(state, a.me.id)[1]
  order(t, a, { kind = "ActivateModule", actor = 0, item = hardener.id })
  Core.Step(a.game)
  local even = a.me.vitals.armorResonance[3]
  -- (kinetic damage, cycle after cycle)
  for _ = 1, 4 do
    a.me.vitals.taken = { 0, 0, 100, 0 }
    for _ = 1, 11 do
      Core.Step(a.game)
    end
  end
  t.ok(hardener.adapt ~= nil, "nothing shifted")
  local split = hardener.adapt :: { number }
  t.ok(split[3] > 0.15, `kinetic {split[3]}`)
  t.near(split[1] + split[2] + split[3] + split[4], 0.6, 1e-9)
  t.ok(a.me.vitals.armorResonance[3] < even, "the ship lets less kinetic through")
end)

-- ---------------------------------------------------------------------
-- Module expansion, the second group (2026-11-16): combat support.

suite:Case("a smartbomb strikes every other ship within its reach, and not the ship that set it off", function(t)
  local a = arena("frigate.akashi", { { "smartbomb.em.small" } }, "frigate.courier", {}, 2000)
  local bomb = Items.Fitted(a.game.state, a.me.id)[1]
  local shield, mine = a.foe.vitals.shield, a.me.vitals.shield
  order(t, a, { kind = "ActivateModule", actor = 0, item = bomb.id })
  local went = stepUntil(a, "Smartbombed", 5)
  t.eq(went.struck, 1)
  Core.Step(a.game)
  t.ok(a.foe.vitals.shield < shield, "the other ship was struck")
  t.ok(a.me.vitals.shield >= mine, "its own ship was not")
  -- (and out of its reach, nothing)
  local far = arena("frigate.akashi", { { "smartbomb.em.small" } }, "frigate.courier", {}, 9000)
  order(t, far, { kind = "ActivateModule", actor = 0, item = Items.Fitted(far.game.state, far.me.id)[1].id })
  t.eq(stepUntil(far, "Smartbombed", 5).struck, 0)
end)

suite:Case("an energy drain takes the target's capacitor into its own ship, while the target's is the fuller", function(t)
  local a = arena("frigate.akashi", { { "drain.small" } }, "frigate.courier", {}, 3000)
  lockFoe(t, a)
  local drain = Items.Fitted(a.game.state, a.me.id)[1]
  a.me.vitals.capacitor = 10
  local theirs = a.foe.vitals.capacitor
  order(t, a, { kind = "ActivateModule", actor = 0, item = drain.id, target = a.foe.id })
  local drained = stepUntil(a, "Drained", 5)
  t.eq(drained.amount, 20)
  t.ok(a.foe.vitals.capacitor < theirs, "taken from the target")
  t.ok(a.me.vitals.capacitor >= 29, `into its own: {a.me.vitals.capacitor}`)
end)

suite:Case("a tracking disruptor and a guidance disruptor are set on their target; a remote sensor booster lengthens its reach", function(t)
  local a = arena("cruiser.ouyou", { { "ewar.tracking" }, { "ewar.guidance" }, { "remote.sensor" } }, "frigate.courier", {}, 3000)
  lockFoe(t, a)
  local reach = a.foe.vitals.lockRange
  for _, item in Items.Fitted(a.game.state, a.me.id) do
    order(t, a, { kind = "ActivateModule", actor = 0, item = item.id, target = a.foe.id })
  end
  Core.Step(a.game)
  Core.Step(a.game)
  t.eq({ a.foe.vitals.track, a.foe.vitals.guide } :: { any }, { 0.7, 0.7 } :: { any })
  t.near(a.foe.vitals.lockRange, reach * 1.3, 1e-6)
  t.eq(a.me.vitals.track, nil, "nothing on the ship that runs them")
end)

return suite
