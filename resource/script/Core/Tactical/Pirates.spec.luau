--!strict
-- Pirates (Tactical/Pirates): what they fly, and what comes where.

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Attributes = require("@lt/Core/Attributes")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Pirates")

-- A game with the player's ship in space at the first thing of a kind
-- in the first system of a band (the ship is put there: the flight is
-- Space's to test), and that thing.
local function at(t: Test.Context, historySeed: number, band: Galaxy.Band, kind: string): (Core.Game, System.Object)
  local game = Core.New({ galaxySeed = 1, historySeed = historySeed })
  local state = game.state
  t.ok(Core.Submit(game, { kind = "Undock", actor = state.player.ship }))
  Core.Step(game)
  local found: System.Object? = nil
  for system = 1, #state.galaxy.systems do
    if found == nil and Galaxy.Band(state.galaxy.systems[system].security) == band then
      -- (a system nobody has been to is described when it is first asked about)
      for _, object in Space.Describe(state, system).objects do
        if object.kind == kind and found == nil then
          found = object
        end
      end
    end
  end
  local site = assert(found, `no {kind} in {band} space`)
  local ball = assert(Core.Query.Ball(game, state.player.ship))
  ball.system = site.id // 10000
  ball.x, ball.y, ball.z = site.x + 2000, site.y, site.z
  Space.AssignGrid(state, ball)
  t.eq(ball.grid, site.id)
  Core.TakeEvents(game)
  return game, site
end

-- The pirates that come within a few ticks, by name.
local function arrivals(game: Core.Game): { string }
  local names: { string } = {}
  for _ = 1, 3 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      if event.kind == "BallAdded" then
        local ship = game.state.ships[event.ball]
        if ship and ship.owner == "pirates" then
          table.insert(names, ship.name)
        end
      end
    end
  end
  table.sort(names)
  return names
end

-- What a pirate is called without its grade ("Veteran Raider" and
-- "Raider Captain" are a "Pirate Raider"), and the grade.
local function ungraded(name: string): (string, number)
  local veteran = string.match(name, "^Veteran (.+)$")
  local captain = string.match(name, "^(.+) Captain$")
  if veteran then
    return "Pirate " .. veteran, 1
  elseif captain then
    return "Pirate " .. captain, 2
  end
  return name, 0
end

suite:Case("every kind of pirate flies an Unbound hull with a fit the hull takes, its weapons loaded", function(t)
  for _, kind in Pirates.kinds do
    local hull = Ships.byId[kind.hull]
    -- (what a camp is built of is nobody's hull, and is not flown: below)
    if hull ~= nil and hull.class == "works" then
      continue
    end
    -- (what is met in the deep is no pirate, and flies its own people's hulls: the Drowned)
    local own = if string.sub(kind.id, 1, 8) == "drowned." then "drowned" else "unbound"
    t.ok(hull ~= nil and hull.lineage == own, `{kind.name} flies '{kind.hull}', which is not the pirates' own`)
    local fit = Pirates.Fit(kind)
    local types: { string } = {}
    local weapons = 0
    for _, entry in fit do
      table.insert(types, entry[1])
      local module = Modules.byId[entry[1]]
      if module.weapon then
        weapons += 1
        local charge = Modules.chargeById[entry[2]]
        t.ok(charge ~= nil, `{kind.name}'s {module.name} has nothing loaded`)
        t.eq({ charge.family, charge.size } :: { any }, { module.weapon.family, module.weapon.size } :: { any })
      end
    end
    t.ok((Attributes.Check(hull, types)), `{kind.name}'s fit does not go on its hull`)
    t.ok(weapons >= 1, `{kind.name} has no weapon`)
    -- (all but the scout and the mender use every hardpoint the hull has)
    if kind.id ~= "scout" and kind.id ~= "mender" then
      t.eq(weapons, hull.turrets + hull.launchers)
    end
  end
  t.eq(#Pirates.Fit(Pirates.SCOUT), 1)
end)

suite:Case("what the Drowned send is no pirate: their own hulls with railguns on every hardpoint, no bounty and no tags, and a wreck with what its hull is made of in it", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local sent = 0
  local last = { dps = 0, hp = 0 }
  for _, kind in Pirates.kinds do
    if string.sub(kind.id, 1, 8) ~= "drowned." then
      continue
    end
    sent += 1
    local hull = Ships.byId[kind.hull]
    t.eq({ hull.lineage, hull.cloak, kind.bounty, kind.tags, kind.name } :: { any }, { "drowned", true, 0, 0, hull.name } :: { any })
    local ball = Pirates.Spawn(state, kind, 1, 1e9 + sent * 1e6, 0, 0, 0)
    -- Railguns on every hardpoint, loaded.
    local guns = 0
    for _, item in Items.Fitted(state, ball.id) do
      if string.sub(item.type, 1, 8) == "railgun." then
        guns += 1
        t.ok(item.charge ~= "", `{kind.name}'s railgun is not loaded`)
      end
    end
    t.eq(guns, hull.turrets, kind.name)
    -- Each is more than the one before.
    local offence = Items.Offence(state, ball.id)
    local hp = ball.vitals.shieldMax + ball.vitals.armorMax + ball.vitals.hullMax
    t.ok(offence.dps > last.dps and hp > last.hp, `{kind.name} does {offence.dps} a second with {hp} hit points`)
    last = { dps = offence.dps, hp = hp }
    -- Its wreck: so much of what its hull is made of for its size, and no pirate's tags.
    local wrecks = #state.wreckIds
    Aftermath.Destroy(state, ball.id, 0, game.events)
    t.eq(#state.wreckIds, wrecks + 1)
    local wreck = state.wrecks[state.wreckIds[#state.wreckIds]]
    local alloy, tags = 0, 0
    for _, item in Items.In(state, wreck.id, nil) do
      alloy += if item.type == "alloy.benthic" then item.quantity else 0
      tags += if item.type == "tag.pirate" then item.quantity else 0
    end
    t.eq({ alloy, tags }, { hull.radius // Aftermath.STUFF, 0 }, kind.name)
  end
  t.eq(sent, 5)
  -- The packs, as they are written: every one of the Drowned's own kinds.
  for _, packs in Pirates.DROWNED do
    for _, entry in packs do
      for _, id in entry[2] do
        t.ok(string.sub(id, 1, 8) == "drowned." and Pirates.kindById[id] ~= nil, id)
      end
    end
  end
end)

suite:Case("a bigger pirate hits harder, takes more killing and pays more", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local last = { dps = 0, hp = 0, bounty = 0, tags = 0 }
  for _, kind in Pirates.kinds do
    -- (a mender is not one of the ladder: it is there for the others;
    -- nor is what a camp is built of, nor what the Drowned send)
    if kind.id == "mender" or Ships.byId[kind.hull].class == "works" or string.sub(kind.id, 1, 8) == "drowned." then
      continue
    end
    local ball = Pirates.Spawn(game.state, kind, 1, 1e9, 0, 0, 0)
    local offence = Items.Offence(game.state, ball.id)
    local v = ball.vitals
    local hp = v.shieldMax + v.armorMax + v.hullMax
    t.ok(offence.dps > last.dps * 1.3, `{kind.name} does {offence.dps} a second and the kind below {last.dps}`)
    t.ok(hp > last.hp * 1.4, `{kind.name} has {hp} hit points and the kind below {last.hp}`)
    t.ok(kind.bounty > last.bounty * 2 and kind.tags >= last.tags)
    -- (and it fights from inside the reach of its guns)
    t.ok(kind.range < offence.range, `{kind.name} keeps {kind.range} m off and reaches {offence.range}`)
    local pilot = game.state.pilots[ball.id]
    t.eq({ pilot.bounty, pilot.tags }, { kind.bounty, kind.tags })
    last = { dps = offence.dps, hp = hp, bounty = kind.bounty, tags = kind.tags }
  end
  -- A scout is what it was when it flew a Courier: one small gun, worth 12,000 (6,000 until 2026-11-16).
  t.eq(Pirates.SCOUT.bounty, 12000)
end)

suite:Case("what a camp is built of stands where it is put: a store does nothing, and an emplacement fires on what comes in reach", function(t)
  local stores, emplacements = 0, 0
  for _, kind in Pirates.kinds do
    local hull = Ships.byId[kind.hull]
    if hull.class ~= "works" then
      continue
    end
    -- Nobody sells one or builds one, and it does not move.
    t.eq({ hull.restricted, hull.maxVelocity, hull.turrets } :: { any }, { true, 0, 0 } :: { any })
    local fit = Pirates.Fit(kind)
    local weapons = 0
    for _, entry in fit do
      weapons += if Modules.byId[entry[1]].weapon then 1 else 0
    end
    t.eq({ #fit, weapons }, { #kind.fit, hull.launchers }, `{kind.name}'s fit`)
    stores += if weapons == 0 then 1 else 0
    emplacements += if weapons > 0 then 1 else 0

    local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
    local state = game.state
    local id = state.player.ship
    t.ok((Core.Submit(game, { kind = "Undock", actor = id })))
    Core.Step(game)
    local me = state.balls[id]
    me.x += 5e7
    me.vx, me.vy, me.vz = 0, 0, 0
    Space.AssignGrid(state, me)
    t.ok((Core.Submit(game, { kind = "Stop", actor = id })))
    local ball = Pirates.Spawn(state, kind, me.system, me.x + 6000, me.y, me.z, me.grid)
    local x, y, z = ball.x, ball.y, ball.z
    local was = me.vitals.shield
    local shots = 0
    for _ = 1, 40 do
      Core.Step(game)
      for _, event in Core.TakeEvents(game) do
        shots += if event.kind == "Shot" and event.from == ball.id then 1 else 0
      end
    end
    t.eq({ ball.x, ball.y, ball.z }, { x, y, z }, `{kind.name} moved`)
    if weapons > 0 then
      t.ok(shots > 0 and me.vitals.shield < was, `{kind.name} did not fire on a ship six kilometres off`)
    else
      t.eq({ shots, me.vitals.shield }, { 0, was }, `{kind.name} is a store`)
    end
  end
  t.ok(stores >= 2 and emplacements >= 2)
end)

suite:Case("a mender keeps its pack whole: its repairers go on whichever pirate is worst hurt", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local fit = Pirates.Fit(Pirates.kindById["mender"])
  local remote = 0
  for _, entry in fit do
    remote += if Modules.Mends(Modules.byId[entry[1]]) then 1 else 0
  end
  t.eq(remote, 2)
  -- The player out in open space (in a battleship, which lives through it), a raider on them, and a mender with it.
  state.ships[state.player.ship].type = "battleship.owari"
  t.ok((Core.Submit(game, { kind = "Undock", actor = state.player.ship })))
  Core.Step(game)
  local me = state.balls[state.player.ship]
  me.x += 4e6
  Space.AssignGrid(state, me)
  local raider = Pirates.Spawn(state, Pirates.kindById["raider"], me.system, me.x + 3000, me.y, me.z, me.grid)
  local mender = Pirates.Spawn(state, Pirates.kindById["mender"], me.system, me.x + 5000, me.y, me.z, me.grid)
  for _ = 1, 30 do
    Core.Step(game)
  end
  -- (it does not mend the ship it is hunting, hurt as it may be)
  for _, running in mender.vitals.running do
    t.ok(running.target ~= me.id or not Modules.Mends(Modules.byId[state.items[running.item].type]), "the mender is mending its prey")
  end
  raider.vitals.armor = raider.vitals.armorMax * 0.2
  local mending = false
  for _ = 1, 40 do
    Core.Step(game)
    for _, running in mender.vitals.running do
      mending = mending or running.target == raider.id
    end
  end
  t.ok(mending, "the mender did nothing for a raider with a fifth of its armour")
  t.ok(raider.vitals.armor > raider.vitals.armorMax * 0.2 + 100 or state.balls[raider.id] == nil, "the raider's armour was not put back")
end)

-- A game with the player's ship at rest in open space, a long way from
-- anything.
-- ('hull' is what it flies instead, where the case is about what its
-- attackers do and not about whether it lives through it.)
local function inOpenSpace(hull: string?): (Core.Game, State.Ball)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  if hull then
    state.ships[state.player.ship].type = hull
  end
  assert(Core.Submit(game, { kind = "Undock", actor = state.player.ship }))
  Core.Step(game)
  local me = state.balls[state.player.ship]
  me.x += 4e6
  me.vx, me.vy, me.vz = 0, 0, 0
  Space.AssignGrid(state, me)
  Core.TakeEvents(game)
  return game, me
end

-- Bring a ship down to a share of all it has: its shield gone first,
-- then its armour, then its hull.
local function hurt(ball: State.Ball, share: number)
  local v = ball.vitals
  local keep = share * (v.shieldMax + v.armorMax + v.hullMax)
  v.hull = math.min(v.hullMax, keep)
  v.armor = math.min(v.armorMax, keep - v.hull)
  v.shield = math.min(v.shieldMax, keep - v.hull - v.armor)
end

suite:Case("a pirate badly hurt breaks off and warps away, with what was on its head; held, it cannot, and fights on", function(t)
  local game, me = inOpenSpace("battleship.owari")
  local state = game.state
  local raider = Pirates.Spawn(state, Pirates.kindById["raider"], me.system, me.x + 3000, me.y, me.z, me.grid)
  local pilot = state.pilots[raider.id]
  t.eq({ pilot.nerve, pilot.fleeing } :: { any }, { Pirates.NERVE, nil } :: { any })
  for _ = 1, 10 do
    Core.Step(game)
  end
  t.eq({ pilot.prey, raider.mode } :: { any }, { me.id, "orbit" } :: { any })
  -- Hurt, but not badly: it stays.
  hurt(raider, Pirates.NERVE + 0.1)
  Core.TakeEvents(game)
  for _ = 1, 5 do
    Core.Step(game)
  end
  t.eq({ pilot.fleeing, raider.warp } :: { any }, { nil, nil } :: { any })
  -- Badly: it turns for somewhere far off, and says so to whoever is watching.
  hurt(raider, Pirates.NERVE - 0.05)
  local wallet = state.wallet
  local fleeing, fled, removed = nil :: any, nil :: any, nil :: any
  for _ = 1, 120 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      fleeing = if event.kind == "PirateFleeing" then event else fleeing
      fled = if event.kind == "PirateFled" then event else fled
      removed = if event.kind == "BallRemoved" and event.ball == raider.id then event else removed
    end
    if fled then
      break
    end
  end
  t.eq({ fleeing.ball, fleeing.name } :: { any }, { raider.id, "Pirate Raider" } :: { any })
  t.eq({ fled.ball, fled.name, removed.reason } :: { any }, { raider.id, "Pirate Raider", "fled" } :: { any })
  -- It is gone, ship and all: no wreck, no bounty, and nothing of it left in the state.
  t.eq({ state.balls[raider.id], state.ships[raider.id], state.pilots[raider.id], #state.wreckIds, state.wallet } :: { any },
    { nil, nil, nil, 0, wallet } :: { any })

  -- Another, with a warp disruptor on it: it cannot warp, and so it fights on. Let go, it is off.
  local second = Pirates.Spawn(state, Pirates.kindById["raider"], me.system, me.x + 3000, me.y, me.z, me.grid)
  local disruptor = Items.Equip(state, me.id, "disruptor.warp", nil)
  state.skills["propulsion.jamming"] = 5
  t.ok((Core.Submit(game, { kind = "LockTarget", actor = me.id, target = second.id })))
  local held = false
  for _ = 1, 60 do
    Core.Step(game)
    if not held then
      held = (Core.Submit(game, { kind = "ActivateModule", actor = me.id, item = disruptor.id, target = second.id }))
    end
    if second.vitals.scrambled then
      break
    end
  end
  t.ok(second.vitals.scrambled, "the raider should be held")
  hurt(second, 0.1)
  Core.TakeEvents(game)
  -- (both kept as they are: who would win is not what this is about)
  local function hold()
    if state.balls[second.id] then
      hurt(second, 0.1)
    end
    me.vitals.shield, me.vitals.armor, me.vitals.hull = me.vitals.shieldMax, me.vitals.armorMax, me.vitals.hullMax
    me.vitals.capacitor = me.vitals.capacitorMax
  end
  for _ = 1, 30 do
    Core.Step(game)
    hold()
  end
  t.ok(state.balls[second.id] ~= nil and second.warp == nil and state.pilots[second.id].fleeing == nil, "a pirate that is held cannot leave")
  t.eq({ state.pilots[second.id].prey, second.mode } :: { any }, { me.id, "orbit" } :: { any })
  t.ok((Core.Submit(game, { kind = "DeactivateModule", actor = me.id, item = disruptor.id })))
  local away = false
  for _ = 1, 120 do
    Core.Step(game)
    hold()
    for _, event in Core.TakeEvents(game) do
      away = away or (event.kind == "PirateFled" and event.ball == second.id)
    end
  end
  t.ok(away, "let go, it should have got away")
end)

suite:Case("not everybody breaks off: a scout does not know when to, a captain will not, and nobody leaves what they are there to defend", function(t)
  local game, me = inOpenSpace()
  local state = game.state
  local function nerveOf(kind: Pirates.Kind): number?
    local ball = Pirates.Spawn(state, kind, me.system, me.x + 4e5, me.y, me.z, 0)
    local nerve = state.pilots[ball.id].nerve
    Aftermath.Destroy(state, ball.id, 0, game.events)
    return nerve
  end
  local raider = Pirates.kindById["raider"]
  t.eq(nerveOf(Pirates.SCOUT), nil)
  t.eq(nerveOf(raider), Pirates.NERVE)
  t.eq(nerveOf(Pirates.kindById["mender"]), Pirates.NERVE)
  t.eq(nerveOf(Pirates.kindById["ravager"]), Pirates.NERVE)
  t.eq(nerveOf(Pirates.Graded(raider, 1)), Pirates.NERVE, "a veteran knows when to go")
  t.eq(nerveOf(Pirates.Graded(raider, 2)), nil, "a captain goes down with the ship")
  t.eq(nerveOf(Pirates.kindById["battery"]), nil, "what stands where it was put has nowhere to go")
  -- A scout, cut to pieces, is still there.
  local scout = Pirates.Spawn(state, Pirates.SCOUT, me.system, me.x + 3000, me.y, me.z, me.grid)
  for _ = 1, 40 do
    Core.Step(game)
    hurt(scout, 0.05)
  end
  t.ok(state.balls[scout.id] ~= nil and scout.warp == nil, "a scout should see it through")
  Aftermath.Destroy(state, scout.id, 0, game.events)
  -- A raider whose place is a job's camp: the job is to clear them out of it, and they stay to be cleared.
  local camp = Pirates.Spawn(state, raider, me.system, me.x + 3000, me.y, me.z, me.grid)
  local mission: any = { id = 4242, kind = "assault", site = me.grid, to = 0, rooms = { me.grid }, taken = state.tick, standing = 0,
    faction = "", aim = "clear", need = 9, done = 0, mark = 0, waves = {}, wave = 0, ends = {}, level = 1, station = state.player.home,
    system = me.system, type = "", reward = 0, agent = "", loyalty = 0, slot = 0, key = "" }
  state.missions[4242] = mission
  table.insert(state.missionIds, 4242)
  for _ = 1, 40 do
    Core.Step(game)
    hurt(camp, 0.05)
  end
  t.ok(state.balls[camp.id] ~= nil and camp.warp == nil and state.pilots[camp.id].fleeing == nil, "a camp's pirate should stay in it")
end)

suite:Case("a pirate with an afterburner burns it to get to its prey and lets it go where it likes to fight; one of a job's camp does not burn", function(t)
  local game, me = inOpenSpace()
  local state = game.state
  local kind = Pirates.kindById["raider"]
  t.ok(Pirates.Drives(Modules.byId["afterburner.1mn"]) and not Pirates.Drives(Modules.byId["damage.control"]))
  local function burning(ball: State.Ball): boolean
    for _, running in ball.vitals.running do
      local item = state.items[running.item]
      if item and Pirates.Drives(Modules.byId[item.type]) and not running.stopping then
        return true
      end
    end
    return false
  end
  -- (the pilot's ship kept whole: who would win is not what this is about)
  local function steps(count: number, done: (() -> boolean)?): boolean
    for _ = 1, count do
      Core.Step(game)
      me.vitals.shield, me.vitals.armor, me.vitals.hull = me.vitals.shieldMax, me.vitals.armorMax, me.vitals.hullMax
      if done and done() then
        return true
      end
    end
    return false
  end
  -- Twenty kilometres off: it burns, and comes on at twice its speed.
  local raider = Pirates.Spawn(state, kind, me.system, me.x + 20000, me.y, me.z, me.grid)
  state.pilots[raider.id].nerve = nil
  local plain = raider.maxVelocity
  steps(4)
  t.ok(burning(raider), "far from its prey, a raider should burn its afterburner")
  t.ok(raider.maxVelocity > plain * 1.8, `it does {raider.maxVelocity} m/s burning, and {plain} without`)
  -- Where it likes to fight, it lets the afterburner go, and circles at its own speed.
  t.ok(steps(120, function()
    return Space.Distance(raider :: any, me :: any) < kind.range + Pirates.COAST
  end), "it did not get there")
  t.ok(steps(30, function()
    return not burning(raider) and math.abs(raider.maxVelocity - plain) < 1
  end), "in its orbit, it should have let the afterburner go")
  -- Its prey gets away from it: it burns again.
  me.x += 15000
  t.ok(steps(15, function()
    return burning(raider)
  end), "after a prey that has got away, it should burn again")
  -- One that breaks off switches it off, to be in warp the sooner.
  state.pilots[raider.id].nerve = Pirates.NERVE
  hurt(raider, 0.1)
  steps(2)
  t.eq({ state.pilots[raider.id].fleeing, burning(raider) } :: { any }, { true, false } :: { any })
  steps(120, function()
    return state.balls[raider.id] == nil
  end)
  t.eq(state.balls[raider.id], nil)
  -- And one that is there to defend a job's camp comes on at its own speed, however far it has to come.
  state.sites[me.grid] = { id = me.grid, system = me.system, kind = "mission", gone = false } :: any
  local camp = Pirates.Spawn(state, kind, me.system, me.x + 20000, me.y, me.z, me.grid)
  for _ = 1, 20 do
    steps(1)
    t.ok(not burning(camp), "a camp's raider should not burn")
  end
  t.eq({ state.pilots[camp.id].prey, camp.maxVelocity } :: { any }, { me.id, plain } :: { any })
end)

suite:Case("what comes follows from how safe the system is", function(t)
  for band, packs in Pirates.PACKS do
    local share = 0
    for _, pack in packs do
      share += pack[1]
      for _, id in pack[2] do
        t.ok(Pirates.kindById[id] ~= nil, `a pack in {band} space has a '{id}'`)
        if band == "secure" then
          t.eq(id, "scout")
        else
          t.ok(id ~= "scout", "a scout is for where order is kept")
        end
      end
    end
    t.near(share, 1, 1e-9)
  end
  local seen: { [string]: boolean } = {}
  for seed = 1, 12 do
    local secure = arrivals((at(t, seed, "secure", "belt")))
    t.ok(#secure >= 1 and #secure <= 2, `history seed {seed}: {#secure} pirates at a belt in secure space`)
    for _, name in secure do
      t.eq(name, "Pirate Scout")
    end
    local low = arrivals((at(t, seed, "low", "belt")))
    t.ok(#low >= 2 and #low <= 3, `history seed {seed}: {#low} pirates at a belt in low security`)
    local lawless = arrivals((at(t, seed, "lawless", "belt")))
    t.eq(#lawless, 3)
    -- (whatever grade each is of: below)
    for _, name in low do
      local kind = ungraded(name)
      t.ok(kind == "Pirate Raider" or kind == "Pirate Jackal", `{name} in low security`)
    end
    for _, name in lawless do
      local kind = ungraded(name)
      t.ok(kind ~= "Pirate Scout", "a scout in lawless space")
      seen[kind] = true
    end
  end
  t.ok(seen["Pirate Marauder"], "twelve packs in lawless space and no cruiser among them")
  t.ok(seen["Pirate Jackal"] and seen["Pirate Raider"])
end)

suite:Case("a veteran of a kind fits the custom make of whatever it has one of, and a captain the masterwork: the same hull, more to it, and more on its head", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local function whole(ball: State.Ball): number
    return ball.vitals.shieldMax + ball.vitals.armorMax + ball.vitals.hullMax
  end
  local graded = 0
  for _, kind in Pirates.kinds do
    t.eq(Pirates.Graded(kind, 0), kind)
    -- (what one is, is told by the name it flies under: whoever draws it asks)
    t.eq({ Pirates.Rank(kind.name), Pirates.Rank(Pirates.Graded(kind, 1).name), Pirates.Rank(Pirates.Graded(kind, 2).name) },
      if Ships.byId[kind.hull].class == "works" or string.sub(kind.id, 1, 8) == "drowned." then { 0, 0, 0 } else { 0, 1, 2 }, kind.name)
    -- (nobody commands a store, and the Drowned have no veterans and no captains)
    if Ships.byId[kind.hull].class == "works" or string.sub(kind.id, 1, 8) == "drowned." then
      t.eq({ Pirates.Graded(kind, 1), Pirates.Graded(kind, 2) }, { kind, kind })
      continue
    end
    local plain = Pirates.Spawn(state, kind, 1, 1e9, 0, 0, 0)
    local last = { dps = Items.Offence(state, plain.id).dps, hp = whole(plain) }
    local short = (string.gsub(kind.name, "^Pirate ", ""))
    for grade, rank in Pirates.GRADES do
      graded += 1
      local better = Pirates.Graded(kind, grade)
      t.eq({ better.id, better.hull, better.grade, better.range, better.bounty, better.tags } :: { any },
        { `{kind.id}.{rank.id}`, kind.hull, grade, kind.range, kind.bounty * rank.bounty, kind.tags + rank.tags } :: { any })
      t.eq(Pirates.kindById[better.id], better)
      t.eq({ better.name, (ungraded(better.name)), select(2, ungraded(better.name)) } :: { any },
        { if grade == 1 then `Veteran {short}` else `{short} Captain`, kind.name, grade } :: { any })
      -- It has what the plain kind has, each thing the make its grade fits, loaded alike; and then
      -- whatever else of what the plain kind would like that there is room for now.
      t.eq(#better.fit, #kind.fit)
      local was, fit = Pirates.Fit(kind), Pirates.Fit(better)
      for index, entry in was do
        t.eq(fit[index], { Modules.Graded(entry[1], grade), entry[2] }, `{better.name}'s fit, place {index}`)
      end
      local made = 0
      for _, entry in fit do
        local module = Modules.byId[entry[1]]
        made += if module.meta == grade then 1 else 0
        t.ok(module.meta == nil or module.meta == grade, `{better.name} has a {module.name}`)
        t.ok(module.meta == grade or Modules.Graded(entry[1], grade) == entry[1], `{better.name} has a plain {module.name}`)
      end
      t.ok(#fit >= #was and made >= 1, `{better.name}'s fit`)
      -- It hits harder than the grade below, takes as much killing at least, and is worth what its grade is.
      local ball = Pirates.Spawn(state, better, 1, 1e9 + 1e6 * graded, 0, 0, 0)
      local dps, hp = Items.Offence(state, ball.id).dps, whole(ball)
      t.ok(dps > last.dps * 1.03, `{better.name} does {dps} a second and the grade below {last.dps}`)
      t.ok(hp >= last.hp, `{better.name} has {hp} hit points and the grade below {last.hp}`)
      local pilot = state.pilots[ball.id]
      t.eq({ ball.name, state.ships[ball.id].type, pilot.bounty, pilot.tags } :: { any },
        { better.name, kind.hull, better.bounty, better.tags } :: { any })
      last = { dps = dps, hp = hp }
    end
  end
  -- (the five of the ladder and the mender, in two grades)
  t.eq(graded, 12)
  -- A captain's marauder against a plain one: a quarter more to its guns, and a good deal more plate and shield.
  local plain = Pirates.Spawn(state, Pirates.kindById["marauder"], 1, 3e9, 0, 0, 0)
  local captain = Pirates.Spawn(state, Pirates.kindById["marauder.captain"], 1, 4e9, 0, 0, 0)
  -- (its pilot knows their trade better than a plain pirate, too: Pirates.SKILL. As well as each other, the quarter
  -- is the guns'; as they are, more again.)
  local skilled = Items.Offence(state, captain.id).dps
  state.ships[captain.id].skill = state.ships[plain.id].skill
  t.near(Items.Offence(state, captain.id).dps / Items.Offence(state, plain.id).dps, 1.25, 0.03)
  t.ok(skilled > Items.Offence(state, captain.id).dps * 1.2, "a captain's skills make no difference")
  t.ok(whole(captain) > whole(plain) * 1.1, `{whole(captain)} against {whole(plain)}`)
end)

suite:Case("veterans and captains come where order is thin: none where it is kept, more of them the wilder it is, and a stronghold is a captain's", function(t)
  local counts: { [string]: { number } } = {}
  local bands: { Galaxy.Band } = {}
  table.insert(bands, "secure")
  table.insert(bands, "low")
  table.insert(bands, "lawless")
  for _, band: Galaxy.Band in bands do
    local all, veterans, captains = 0, 0, 0
    for seed = 1, 80 do
      local game = at(t, seed, band, "belt")
      local said = 0
      for _ = 1, 3 do
        Core.Step(game)
        for _, event in Core.TakeEvents(game) do
          local ship = if event.kind == "BallAdded" then game.state.ships[event.ball] else nil
          if ship and ship.owner == "pirates" then
            local _, grade = ungraded(ship.name)
            all += 1
            veterans += if grade == 1 then 1 else 0
            captains += if grade == 2 then 1 else 0
            said -= if grade == 2 then 1 else 0
          elseif event.kind == "PiratesArrived" then
            said += event.captains
          end
        end
      end
      -- (the word that they have come says how many captains are among them)
      t.eq(said, 0)
    end
    counts[band] = { all, veterans, captains }
    local odds = Pirates.GRADED[band]
    t.near(veterans / all, odds[1], 0.07, `{veterans} veterans of {all} in {band} space`)
    t.near(captains / all, odds[2], 0.04, `{captains} captains of {all} in {band} space`)
  end
  t.eq({ counts.secure[2], counts.secure[3] }, { 0, 0 })
  t.ok(counts.low[2] > 0 and counts.lawless[2] > counts.low[2] and counts.lawless[3] > 0,
    `{counts.low[2]} veterans in low security, {counts.lawless[2]} and {counts.lawless[3]} captains in lawless space`)
  -- A stronghold (a den that another den's stores gave away): the first of whoever keeps it is a captain.
  local kept = 0
  for seed = 1, 40 do
    local game = Core.New({ galaxySeed = 1, historySeed = seed })
    local state = game.state
    t.ok(Core.Submit(game, { kind = "Undock", actor = state.player.ship }))
    Core.Step(game)
    local den: State.Site? = nil
    for _, id in state.siteIds do
      local site = state.sites[id]
      den = den or (if site.kind == "combat" and site.system == 1 and not site.gone then site else nil)
    end
    if den == nil then
      continue
    end
    kept += 1
    den.depth = 1
    local place = assert(Space.Object(state, den.id))
    local ball = state.balls[state.player.ship]
    ball.x, ball.y, ball.z = place.x + 500, place.y, place.z
    Space.AssignGrid(state, ball)
    Core.TakeEvents(game)
    local first: string? = nil
    local others = 0
    for _ = 1, 3 do
      Core.Step(game)
      for _, event in Core.TakeEvents(game) do
        local ship = if event.kind == "BallAdded" then state.ships[event.ball] else nil
        if ship and ship.owner == "pirates" then
          others += if first then 1 else 0
          first = first or ship.name
        end
      end
    end
    t.eq(select(2, ungraded(first or "")), 2, `a stronghold's first keeper is a {first or "nobody"}`)
    t.ok(others >= 1, "a captain with nobody to command")
  end
  t.ok(kept >= 5, `{kept} dens in forty games`)
end)

suite:Case("a gate is watched only in lawless space, and not every time", function(t)
  local camps = 0
  for seed = 1, 30 do
    t.eq(#arrivals((at(t, seed, "secure", "gate"))), 0)
    t.eq(#arrivals((at(t, seed, "low", "gate"))), 0)
    local game = at(t, seed, "lawless", "gate")
    local waiting = arrivals(game)
    camps += if #waiting > 0 then 1 else 0
    t.ok(#waiting == 0 or #waiting == 3)
    -- (and an unwatched gate stays unwatched for a while)
    if #waiting == 0 then
      for _ = 1, 100 do
        Core.Step(game)
      end
      -- (nobody who flies: a tower the pirates hold a moon with, and its batteries, are no watch on a gate)
      local flying = 0
      for _, id in game.state.pilotIds do
        local ball = game.state.balls[id]
        flying += if ball and ball.maxVelocity > 0 then 1 else 0
      end
      t.eq(flying, 0)
    end
  end
  t.ok(camps >= 5 and camps <= 20, `{camps} of 30 lawless gates were watched`)
end)

suite:Case("no pirates come in a peaceful game, to a capsule, or to a station", function(t)
  local game = at(t, 1, "lawless", "belt")
  game.state.peaceful = true
  t.eq(#arrivals(game), 0)
  local docked = at(t, 1, "lawless", "station")
  t.eq(#arrivals(docked), 0)
end)

suite:Case("a pirate's bounty and tags are its own, whatever it flies", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  t.ok(Core.Submit(game, { kind = "Undock", actor = state.player.ship }))
  Core.Step(game)
  local me = assert(Core.Query.Ball(game, state.player.ship))
  for _, kind in Pirates.kinds do
    local ball = Pirates.Spawn(state, kind, me.system, me.x + 5000, me.y, me.z, me.grid)
    local wallet = state.wallet
    Aftermath.Destroy(state, ball.id, state.player.ship, game.events)
    t.eq(state.wallet - wallet, kind.bounty)
    local wreck = state.wrecks[state.wreckIds[#state.wreckIds]]
    t.eq(wreck.hull, kind.hull)
    local tags = 0
    for _, item in Items.In(state, wreck.id, "cargo") do
      tags += if item.type == "tag.pirate" then item.quantity else 0
    end
    t.eq(tags, kind.tags)
  end
end)

suite:Case("a save from before pirates had bounties of their own keeps what they were worth", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local scout = Pirates.Spawn(state, Pirates.SCOUT, 1, 1e9, 0, 0, 0)
  local data, length = Core.Save(game)
  local file = Codec.Decode(data, length)
  file.saveVersion = 13
  for _, pilot in file.state.pilots do
    pilot.bounty, pilot.tags = nil, nil
  end
  -- (the systems of the map: uncharted space came later, and nobody keeps order there)
  for id = 1, file.state.galaxy.charted do
    file.state.galaxy.systems[id].security = nil
  end
  local old, oldLength = Codec.Encode(file)
  local loaded = Core.Load(old, oldLength)
  local pilot: State.Pilot = loaded.state.pilots[scout.id]
  t.eq({ pilot.bounty, pilot.tags }, { math.floor(Ships.byId[Pirates.SCOUT.hull].basePrice * 0.2), 1 })
  for id, system in loaded.state.galaxy.systems do
    t.eq(system.security, state.galaxy.systems[id].security)
  end
  t.eq(loaded.state.galaxy.systems[1].security, 1)
end)

return suite
