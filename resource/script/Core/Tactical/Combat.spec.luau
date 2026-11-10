--!strict
-- Fights, played through the Core's front door. The player's ship is put
-- in space with a chosen fit, an opponent is placed at a chosen distance,
-- and what happens is compared with what the formulas say should.

local Combat = require("@lt/Core/Tactical/Combat")
local Core = require("@lt/Core/Api")
local Gunnery = require("@lt/Core/Tactical/Gunnery")
local Items = require("@lt/Core/Assets/Items")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Combat")

type Arena = { game: Core.Game, me: State.Ball, foe: State.Ball }

-- The player in a hull with a fit, at rest in space, and an opponent
-- 'distance' metres away (between surfaces), also at rest.
local function arena(hull: string, fit: { { string } }, foeHull: string, foeFit: { { string } }, distance: number,
  historySeed: number?): Arena
  local game = Core.New({ galaxySeed = 1, historySeed = historySeed or 1 })
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

suite:Case("damage goes through shield, armour and hull, and the ship dies", function(t)
  local a = arena("frigate.lancer", { { "laser.pulse.small", "crystal.multifrequency" },
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
  local a = arena("frigate.harrier", { { "launcher.light", "missile.light.kinetic" } }, "frigate.courier", {}, 10000)
  lockFoe(t, a)
  local launcher = modules(a)[1]
  order(t, a, { kind = "ActivateModule", actor = 0, item = launcher.id, target = a.foe.id })
  local shot = stepUntil(a, "Shot", 3)
  t.eq(shot.outcome, "launched")
  local flight = Space.Distance(a.me :: any, a.foe :: any) / 3750
  t.near(shot.flight, flight, 1e-9)
  local hit, ticks = stepUntil(a, "MissileHit", 10)
  t.eq(ticks, math.ceil(flight))
  -- 83 kinetic, times 38/40 for a courier's signature against a 40 m blast
  t.near(hit.damage, 83 * 38 / 40, 1e-9)
  -- and the shield lets 60% of kinetic through
  t.near(a.foe.vitals.shieldMax - a.foe.vitals.shield, 83 * 38 / 40 * 0.6, 1.5)
  t.eq(launcher.rounds, 29)
end)

suite:Case("a missile fired from beyond its reach does nothing", function(t)
  local a = arena("frigate.harrier", { { "launcher.light", "missile.light.kinetic" } }, "frigate.courier", {}, 20000)
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

suite:Case("when the player's ship is destroyed they wake at home in a new one", function(t)
  local a = arena("frigate.courier", {}, "frigate.lancer", { { "laser.pulse.small", "crystal.multifrequency" },
    { "laser.pulse.small", "crystal.multifrequency" }, { "laser.pulse.small", "crystal.multifrequency" } }, 1500)
  local old = a.me.id
  Core.Submit(a.game, { kind = "LockTarget", actor = a.foe.id, target = old })
  stepUntil(a, "LockCompleted", 30)
  for _, laser in Items.Fitted(a.game.state, a.foe.id) do
    Core.Submit(a.game, { kind = "ActivateModule", actor = a.foe.id, item = laser.id, target = old })
  end
  local respawned = stepUntil(a, "Respawned", 400)
  local player = Core.Query.Player(a.game)
  t.ok(player.ship ~= old)
  t.eq(player.ship, respawned.ship)
  t.eq(player.docked, a.game.state.player.home)
  t.eq(player.hull.id, "frigate.courier")
  t.eq(a.game.state.ships[old], nil)
end)

suite:Case("the same seeds give the same fight, and a save in mid-fight carries on unchanged", function(t)
  local function fight(historySeed: number, reloadAt: number?): string
    local a = arena("frigate.lancer", { { "laser.pulse.small", "crystal.multifrequency" },
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

return suite
