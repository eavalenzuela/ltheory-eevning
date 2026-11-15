--!strict
-- Pirates, wrecks, loot, bounties, the capsule, and repairs.

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Core = require("@lt/Core/Api")
local Hangar = require("@lt/Core/Assets/Hangar")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Nomads = require("@lt/Core/Tactical/Nomads")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Stations = require("@lt/Core/Assets/Stations")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Aftermath")

local function me(game: Core.Game): State.Ball
  return assert(Core.Query.Ball(game, game.state.player.ship), "the player's ship is not in space")
end

local function order(t: Test.Context, game: Core.Game, command: State.Command)
  command.actor = game.state.player.ship
  local ok, reason = Core.Submit(game, command)
  t.ok(ok, `{command.kind} was refused: {tostring(reason)}`)
end

local function refused(game: Core.Game, command: State.Command): string?
  command.actor = game.state.player.ship
  local ok, reason = Core.Validate(game, command)
  return if ok then "(accepted)" else reason
end

local function stepUntil(game: Core.Game, kind: string, limit: number): (Space.Event, number)
  for n = 1, limit do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      if event.kind == kind then
        return event, n
      end
    end
  end
  error(`no {kind} within {limit} ticks`, 2)
end

local function nearest(game: Core.Game, kind: string): Core.Entry
  for _, entry in Core.Query.Overview(game) do
    if entry.kind == kind then
      return entry
    end
  end
  error(`nothing of kind {kind} on the overview`, 2)
end

-- A game with the player's starter ship at rest in open space near home.
local function inSpace(peaceful: boolean, historySeed: number?): Core.Game
  local game = Core.New({ galaxySeed = 1, historySeed = historySeed or 1, peaceful = peaceful })
  Core.Submit(game, { kind = "Undock", actor = game.state.player.ship })
  Core.Step(game)
  Core.Submit(game, { kind = "Stop", actor = game.state.player.ship })
  for _ = 1, 40 do
    Core.Step(game)
  end
  Core.TakeEvents(game)
  return game
end

-- Lock a ship and open fire with everything.
local function attack(t: Test.Context, game: Core.Game, target: number)
  order(t, game, { kind = "LockTarget", actor = 0, target = target })
  stepUntil(game, "LockCompleted", 40)
  for _, item in Items.Fitted(game.state, game.state.player.ship) do
    order(t, game, { kind = "ActivateModule", actor = 0, item = item.id, target = target })
  end
end

-- A pirate scout at rest 'distance' metres from the player.
local function scoutAt(game: Core.Game, distance: number): State.Ball
  local ball = me(game)
  return Pirates.Spawn(game.state, Pirates.SCOUT, ball.system, ball.x + distance, ball.y, ball.z, ball.grid)
end

suite:Case("killing a pirate leaves a wreck with its tag, and pays the bounty", function(t)
  local game = inSpace(true)
  local scout = scoutAt(game, 1500)
  -- (peaceful only stops pirates arriving; this one still fights back)
  attack(t, game, scout.id)
  local wallet = game.state.wallet
  local added = stepUntil(game, "WreckAdded", 400)
  local wreck = game.state.wrecks[added.wreck]
  t.eq(wreck.name, "Pirate Scout Wreck")
  t.eq({ wreck.x, wreck.y, wreck.z }, { scout.x, scout.y, scout.z }, "the wreck is where it died")
  local loot: { [string]: number } = {}
  for _, item in Items.In(game.state, wreck.id, nil) do
    loot[item.type] = item.quantity
  end
  t.eq(loot["tag.pirate"], 1)
  t.ok((loot["scrap.metal"] or 0) >= 1)
  -- a courier hull is 30,000; a fifth of that
  t.eq(game.state.wallet, wallet + 6000)
  t.eq(game.state.pilots[scout.id], nil)
  t.eq(#game.state.pilotIds, 0)
  t.eq(nearest(game, "wreck").id, wreck.id, "and it shows on the overview")
end)

suite:Case("looting needs to be close, takes what fits, and clears an emptied wreck", function(t)
  local game = inSpace(true)
  local scout = scoutAt(game, 6000)
  Aftermath.Destroy(game.state, scout.id, 0, game.events)
  Core.TakeEvents(game)
  local wreck = nearest(game, "wreck")
  t.eq(refused(game, { kind = "Loot", actor = 0, target = wreck.id }), "too far away")
  t.eq(refused(game, { kind = "Loot", actor = 0, target = game.state.player.home }), "not a wreck")
  order(t, game, { kind = "Approach", actor = 0, target = wreck.id, range = 1000 })
  for _ = 1, 200 do
    Core.Step(game)
  end
  Core.TakeEvents(game)

  -- Something too bulky to take all of: 50 extenders at 5 m3 into a 180 m3 hold.
  Items.Add(game.state, "shield.extender.small", 50, wreck.id, "cargo")
  order(t, game, { kind = "Loot", actor = 0, target = wreck.id })
  local looted = stepUntil(game, "Looted", 2)
  t.ok(looted.left > 0 and looted.taken > 0)
  local hold: { [string]: number } = {}
  for _, item in Items.In(game.state, game.state.player.ship, "cargo") do
    hold[item.type] = item.quantity
  end
  t.eq(hold["tag.pirate"], 1)
  t.ok(Items.CargoUsed(game.state, game.state.player.ship) <= 180)
  t.ok(hold["shield.extender.small"] >= 30 and hold["shield.extender.small"] < 50)
  t.ok(game.state.wrecks[wreck.id] ~= nil, "the wreck stays while something is left")

  -- Make room and take the rest.
  for _, item in Items.In(game.state, game.state.player.ship, "cargo") do
    Items.Take(game.state, item, item.quantity)
  end
  order(t, game, { kind = "Loot", actor = 0, target = wreck.id })
  stepUntil(game, "WreckRemoved", 2)
  t.eq(game.state.wrecks[wreck.id], nil)
  t.eq(#Items.In(game.state, wreck.id, nil), 0)
end)

suite:Case("about half of what a ship carried survives it", function(t)
  local game = inSpace(true)
  local state = game.state
  local ball = me(game)
  local survived = 0
  local ships = 300
  for i = 1, ships do
    local ship = Space.NewShip(state, "frigate.courier", "Dummy", "nobody", 0)
    Items.Add(state, "armor.plate.200mm", 1, ship.id, "cargo")
    Space.Launch(state, ship, ball.system, ball.x + 1000 * i, ball.y, ball.z)
    Aftermath.Destroy(state, ship.id, 0, game.events)
  end
  for _, id in state.wreckIds do
    if #Items.In(state, id, nil) > 0 then
      survived += 1
    end
  end
  t.near(survived / ships, 0.5, 0.09)
  t.eq(#state.wreckIds, ships)
  -- and none of it is left attached to ships that no longer exist
  for _, id in state.itemIds do
    t.ok(state.wrecks[state.items[id].holder] ~= nil or state.items[id].holder < 2e9 and state.ships[state.items[id].holder] ~= nil
      or state.items[id].holder == state.player.home, "an item with no holder")
  end
end)

suite:Case("what survives of a pirate's fitted module is now and then the custom make of it, and nobody else's ever is", function(t)
  local game = inSpace(true)
  local state = game.state
  local ball = me(game)
  -- Three hundred scouts, destroyed by nobody: each has small autocannons fitted, which have a custom make.
  local plain, custom, others = 0, 0, 0
  for i = 1, 300 do
    local scout = Pirates.Spawn(state, Pirates.SCOUT, ball.system, ball.x + 1000 * i, ball.y, ball.z, ball.grid)
    local fitted = 0
    for _, item in Items.Fitted(state, scout.id) do
      fitted += if Modules.Custom(item.type) then 1 else 0
    end
    assert(fitted > 0, "a scout has nothing fitted that has a custom make")
    Aftermath.Destroy(state, scout.id, 0, game.events)
    local wreck = state.wreckIds[#state.wreckIds]
    for _, item in Items.In(state, wreck, "cargo") do
      local module = Modules.byId[item.type]
      if module and module.meta then
        custom += item.quantity
        t.ok(Modules.byId[module.base :: string] ~= nil)
      elseif module and Modules.Custom(item.type) then
        plain += item.quantity
      elseif module then
        others += item.quantity
      end
      t.ok(module == nil or module.tech ~= 2, "a pirate's wreck had a tech 2 module")
    end
  end
  -- A fifth of what survives that could be.
  t.ok(custom > 0 and plain > 0, `{custom} custom and {plain} plain modules in three hundred wrecks`)
  t.near(custom / (custom + plain), Aftermath.CUSTOM_CHANCE, 0.07)
  -- A ship that is not a pirate's leaves what it had, as it was: fitted, or carried.
  for i = 1, 200 do
    local ship = Space.NewShip(state, "frigate.courier", "Dummy", "nobody", 0)
    Items.Equip(state, ship.id, "autocannon.small", "ammo.emp")
    Space.Launch(state, ship, ball.system, ball.x - 1000 * i, ball.y, ball.z)
    Aftermath.Destroy(state, ship.id, 0, game.events)
    for _, item in Items.In(state, state.wreckIds[#state.wreckIds], "cargo") do
      t.ok(item.type ~= "autocannon.small.custom", "a ship that was nobody's left a custom module")
    end
  end
  -- And what a pirate only carried is not worked over either.
  for i = 1, 200 do
    local scout = Pirates.Spawn(state, Pirates.SCOUT, ball.system, ball.x, ball.y + 1000 * i, ball.z, ball.grid)
    for _, item in Items.Fitted(state, scout.id) do
      Items.Take(state, item, item.quantity)
    end
    Items.Add(state, "armor.repairer.small", 1, scout.id, "cargo")
    Aftermath.Destroy(state, scout.id, 0, game.events)
    for _, item in Items.In(state, state.wreckIds[#state.wreckIds], "cargo") do
      t.ok(item.type ~= "armor.repairer.small.custom", "a module in a pirate's hold came out custom")
    end
  end
end)

suite:Case("a veteran's custom fittings and a captain's masterworks outlive the ship two times in five; the rest are found plain", function(t)
  local game = inSpace(true)
  local state = game.state
  local ball = me(game)
  for grade, id in { "raider.veteran", "raider.captain" } do
    local kept, plain = 0, 0
    for i = 1, 150 do
      local raider = Pirates.Spawn(state, Pirates.kindById[id], ball.system, ball.x + 1000 * i, ball.y + 1e6 * grade, ball.z, ball.grid)
      local better = 0
      for _, item in Items.Fitted(state, raider.id) do
        better += if Modules.byId[item.type].meta == grade then 1 else 0
      end
      assert(better >= 4, `a {id} has {better} of its grade's make fitted`)
      Aftermath.Destroy(state, raider.id, 0, game.events)
      for _, item in Items.In(state, state.wreckIds[#state.wreckIds], "cargo") do
        local module = Modules.byId[item.type]
        if module and module.meta then
          -- (never a better make than it had, nor the other grade's)
          t.eq(module.meta, grade, `a {id}'s wreck had a {module.name}`)
          kept += item.quantity
        elseif module and Modules.Graded(item.type, grade) ~= item.type then
          plain += item.quantity
        end
        t.ok(module == nil or module.tech ~= 2, "a pirate's wreck had a tech 2 module")
      end
    end
    t.ok(kept > 0 and plain > 0, `{kept} kept and {plain} plain in a hundred and fifty wrecks of a {id}`)
    t.near(kept / (kept + plain), Aftermath.KEPT_CHANCE, 0.07)
  end
end)

suite:Case("wrecks fade after two hours", function(t)
  local game = inSpace(true)
  local scout = scoutAt(game, 3000)
  Aftermath.Destroy(game.state, scout.id, 0, game.events)
  local wreck = nearest(game, "wreck")
  t.eq(game.state.wrecks[wreck.id].expires, game.state.tick + 7200)
  game.state.wrecks[wreck.id].expires = game.state.tick + 3
  stepUntil(game, "WreckRemoved", 4)
  t.eq(#game.state.wreckIds, 0)
  t.eq(#game.state.gridIds, 0, "and the patch of space it kept alive goes too")
end)

suite:Case("losing a ship: insurance, a wreck, and the pilot in a capsule that can get home", function(t)
  local game = inSpace(true)
  local old = me(game)
  local oldId, x, y, z = old.id, old.x, old.y, old.z
  local wallet = game.state.wallet
  Aftermath.Destroy(game.state, oldId, 0, game.events)
  local pod = me(game)
  local player = Core.Query.Player(game)
  t.eq(player.hull.id, "capsule")
  t.ok(pod.id ~= oldId)
  t.eq({ pod.x, pod.y, pod.z }, { x, y, z })
  t.eq(game.state.wallet, wallet + 12000, "40% of a 30,000 hull")
  t.eq(nearest(game, "wreck").name, "Courier Wreck")
  t.eq(#Items.Fitted(game.state, pod.id), 0)

  order(t, game, { kind = "Dock", actor = 0, target = game.state.player.home })
  local granted = stepUntil(game, "ShipGranted", 600)
  player = Core.Query.Player(game)
  t.eq(player.ship, granted.ship)
  t.eq(player.hull.id, "frigate.courier")
  t.eq(player.docked, game.state.player.home)
  t.eq(game.state.ships[pod.id], nil, "the capsule is put away")
  t.eq(game.state.wallet, wallet + 12000, "the starter ship is free and uninsured")
end)

suite:Case("losing the capsule too: the pilot wakes at home", function(t)
  local game = inSpace(true)
  Aftermath.Destroy(game.state, me(game).id, 0, game.events)
  local wallet = game.state.wallet
  Aftermath.Destroy(game.state, me(game).id, 0, game.events)
  local player = Core.Query.Player(game)
  t.eq({ player.docked, player.hull.id } :: { any }, { game.state.player.home, "frigate.courier" } :: { any })
  t.eq(game.state.wallet, wallet, "a capsule is not insured")
  t.eq(#game.state.wreckIds, 1, "and leaves no wreck")
end)

suite:Case("the frigate a pilot of the game begins in: a people's own, fitted with what they can fit, insured as the plainest hull", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true, starter = true })
  local state = game.state
  local ship = state.ships[state.player.ship]
  local hull = Ships.byId[ship.type]
  t.eq(hull.class, "frigate")
  t.ok(hull.lineage ~= "", "a frigate some people build, and not the plain Courier")
  t.eq(hull.lineage, Stations.People(state, state.player.home), "of the people whose station the pilot begins at")
  t.eq(Skills.Missing(Skills.Needs(hull.id), state.skills), nil, "which the pilot can fly")
  local highs = 0
  for _, item in Items.Fitted(state, ship.id) do
    t.eq(Skills.Missing(Skills.Needs(item.type), state.skills), nil, `and can fit {item.type} to again`)
    highs += if item.place == "high" then 1 else 0
  end
  t.ok(highs >= 1 and highs < hull.highs, "armed, with a high slot left free")

  -- Lost: it pays what a Courier would, not two fifths of what such a
  -- frigate costs, and the one the pilot wakes in is no better insured.
  Core.Submit(game, { kind = "Undock", actor = ship.id })
  Core.Step(game)
  local wallet = state.wallet
  Aftermath.Destroy(state, ship.id, 0, game.events)
  t.eq(state.wallet, wallet + 12000, "a ship that was given pays as the plainest hull does")
  Aftermath.Destroy(state, me(game).id, 0, game.events)
  local woke = state.ships[state.player.ship]
  t.eq({ woke.type, woke.docked, woke.given } :: { any }, { hull.id, state.player.home, true } :: { any })
  t.eq(#Items.Fitted(state, woke.id), 0, "the one a pilot wakes in is bare")
  -- (and a ship that was paid for is insured for what it is)
  local bought = Space.NewShip(state, hull.id, "Bought", "player", state.player.home)
  order(t, game, { kind = "BoardShip", actor = 0, target = bought.id })
  Core.Step(game)
  Core.Submit(game, { kind = "Undock", actor = bought.id })
  Core.Step(game)
  wallet = state.wallet
  Aftermath.Destroy(state, bought.id, 0, game.events)
  t.eq(state.wallet, wallet + math.floor(hull.basePrice * 0.4))
end)

suite:Case("home is the station a pilot takes a berth at, for a fee: it is where they wake", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local ship = state.ships[state.player.ship]
  local first = state.player.home
  -- A new game's home is where it begins.
  local home = Core.Query.Home(game)
  t.eq({ home.station, home.here, home.jumps, home.fee } :: { any }, { first, true, 0, Hangar.HOME_FEE } :: { any })
  t.eq(home.name, assert(Space.Object(state, first)).name)
  t.eq(refused(game, { kind = "SetHome", actor = 0 }), "this is your home already")
  -- Another station of the same system: docked there, it can be made home by whoever has the fee.
  local second: any = nil
  for _, object in Core.Query.Objects(game, 1) do
    if object.kind == "station" and object.id ~= first then
      second = object
    end
  end
  assert(second, "the first system should have a second station")
  ship.docked = second.id
  home = Core.Query.Home(game)
  t.eq({ home.station, home.here, home.jumps } :: { any }, { first, false, 0 } :: { any })
  t.eq(state.wallet, 5000)
  t.eq(refused(game, { kind = "SetHome", actor = 0 }), "not enough credits for the berth")
  state.wallet = 50000
  -- (a tower of the pilot's own has no berths: this one is forged for the asking)
  state.starbases[second.id] = {} :: any
  t.eq(refused(game, { kind = "SetHome", actor = 0 }), "a tower has no berth to wake in")
  state.starbases[second.id] = nil
  Core.TakeEvents(game)
  order(t, game, { kind = "SetHome", actor = 0 })
  local moved = stepUntil(game, "HomeMoved", 3)
  t.eq({ moved.station, moved.was, moved.fee }, { second.id, first, Hangar.HOME_FEE })
  t.eq({ state.player.home, state.wallet, state.journal[#state.journal].reason } :: { any }, { second.id, 40000, "home berth" } :: { any })
  home = Core.Query.Home(game)
  t.eq({ home.station, home.here, home.name } :: { any }, { second.id, true, second.name } :: { any })
  t.eq(refused(game, { kind = "SetHome", actor = 0 }), "this is your home already")
  -- In space there is no making a home of anything.
  order(t, game, { kind = "Undock", actor = 0 })
  for _ = 1, 20 do
    Core.Step(game)
  end
  t.eq(refused(game, { kind = "SetHome", actor = 0 }), "not docked")
  -- The ship lost, and the capsule: the pilot wakes at the new home, and not where the game began.
  Aftermath.Destroy(state, me(game).id, 0, game.events)
  Core.TakeEvents(game)
  Aftermath.Destroy(state, me(game).id, 0, game.events)
  local woke: any = nil
  for _, event in Core.TakeEvents(game) do
    woke = if event.kind == "Respawned" then event else woke
  end
  local player = Core.Query.Player(game)
  t.eq({ woke.station, player.docked, player.hull.id } :: { any }, { second.id, second.id, "frigate.courier" } :: { any })
  -- It is in the save.
  local loaded = Core.Load(Core.Save(game))
  t.eq({ loaded.state.player.home, Core.Hash(loaded) } :: { any }, { second.id, Core.Hash(game) } :: { any })
end)

suite:Case("a colony ship can be home: the pilot wakes aboard it, wherever it has got to", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true, traffic = true, systems = 40 })
  local state = game.state
  local ship = state.ships[state.player.ship]
  local station = Nomads.StationId(1)
  ship.docked = station
  Space.Describe(state, Space.SystemOf(state, station))
  state.wallet = 50000
  order(t, game, { kind = "SetHome", actor = 0 })
  stepUntil(game, "HomeMoved", 3)
  local home = Core.Query.Home(game)
  t.eq({ home.station, home.here } :: { any }, { station, true } :: { any })
  t.eq(home.name, assert(Space.Object(state, station)).name)
  -- Back where the game began, a long way off: home is so many jumps away, and the capsule lost there wakes aboard.
  local first = Stations.Starter(state)
  ship.docked = first
  home = Core.Query.Home(game)
  t.ok(home.jumps >= 1 and not home.here, `the colony ship should be some jumps off, and is {home.jumps}`)
  order(t, game, { kind = "Undock", actor = 0 })
  for _ = 1, 20 do
    Core.Step(game)
  end
  Aftermath.Destroy(state, me(game).id, 0, game.events)
  Aftermath.Destroy(state, me(game).id, 0, game.events)
  local player = Core.Query.Player(game)
  t.eq({ player.docked, player.hull.id } :: { any }, { station, "frigate.courier" } :: { any })
  for _ = 1, 120 do
    Core.Step(game)
  end
  t.eq(Core.Query.Player(game).docked, station)
  t.eq(Core.Query.Player(game).system, Space.SystemOf(state, station), "the pilot is where the colony ship is")
end)

suite:Case("repairs cost in proportion to the damage and need the money", function(t)
  local game = inSpace(true)
  local ball = me(game)
  local ship = game.state.ships[ball.id]
  t.eq(refused(game, { kind = "Repair", actor = 0 }), "not docked")
  ball.vitals.armor -= 150   -- of 300
  ball.vitals.hull -= 150    -- of 300
  order(t, game, { kind = "Dock", actor = 0, target = game.state.player.home })
  stepUntil(game, "Docked", 600)
  -- half of armour plus hull gone: half of a tenth of 30,000
  t.eq(Aftermath.RepairCost(game.state, ship), 1500)
  game.state.wallet = 1000
  t.eq(refused(game, { kind = "Repair", actor = 0 }), "not enough credits")
  game.state.wallet = 5000
  order(t, game, { kind = "Repair", actor = 0 })
  stepUntil(game, "ShipRepaired", 2)
  t.eq({ ship.armorDamage, ship.hullDamage, game.state.wallet }, { 0, 0, 3500 })
  t.eq(refused(game, { kind = "Repair", actor = 0 }), "nothing to repair")
end)

-- Fly the starter ship to the nearest belt. Pirates, if any are due,
-- arrive on the tick the ship does; their event is returned.
local function toBelt(game: Core.Game): (Core.Entry, Space.Event?)
  local belt = nearest(game, "belt")
  Core.Submit(game, { kind = "WarpTo", actor = game.state.player.ship, target = belt.id })
  for _ = 1, 300 do
    Core.Step(game)
    local landed = false
    local arrived: Space.Event? = nil
    for _, event in Core.TakeEvents(game) do
      landed = landed or event.kind == "WarpEnded"
      if event.kind == "PiratesArrived" then
        arrived = event
      end
    end
    if landed then
      return belt, arrived
    end
  end
  error("the warp to the belt never ended", 2)
end

suite:Case("pirates turn up at a belt, close in and open fire", function(t)
  local game = inSpace(false)
  t.eq(#game.state.pilotIds, 0, "there are none in open space")
  local belt, came = toBelt(game)
  local arrived = assert(came, "no pirates came")
  t.eq(arrived.grid, belt.id)
  t.ok(arrived.count >= 1 and arrived.count <= 2)
  t.eq(#game.state.pilotIds, arrived.count)
  local pirate = nearest(game, "ship")
  t.ok(pirate.distance > 5000, `they start some way off, not on top of the player ({pirate.distance} m)`)
  -- within four minutes they have locked the player and hit it
  local hit = false
  for _ = 1, 240 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      hit = hit or (event.kind == "DamageApplied" and event.ball == game.state.player.ship)
    end
  end
  t.ok(hit, "the pirates never landed a shot")
  t.ok(nearest(game, "ship").distance < 5000, "they closed in")
end)

suite:Case("a starter ship that fights back beats a lone scout", function(t)
  for seed = 1, 3 do
    local game = inSpace(true, seed)
    local scout = scoutAt(game, 8000)
    attack(t, game, scout.id)
    stepUntil(game, "WreckAdded", 600)
    local player = Core.Query.Player(game)
    t.eq(player.hull.id, "frigate.courier", `history seed {seed}: the player lost`)
    t.ok(me(game).vitals.hull > 0)
  end
end)

suite:Case("pirates ignore a capsule, and leave a place nobody is in", function(t)
  local game = inSpace(false)
  toBelt(game)
  local count = #game.state.pilotIds
  t.ok(count > 0, "no pirates came")
  -- The player's ship is lost; the pirates lose interest.
  Aftermath.Destroy(game.state, me(game).id, 0, game.events)
  for _ = 1, 30 do
    Core.Step(game)
  end
  for _, id in game.state.pilotIds do
    t.eq(game.state.pilots[id].prey, 0)
    t.eq(#game.state.balls[id].vitals.locks, 0)
  end
  -- The capsule warps home; after five minutes alone they are gone.
  Core.Submit(game, { kind = "Dock", actor = game.state.player.ship, target = game.state.player.home })
  for _ = 1, 400 do
    Core.Step(game)
  end
  t.eq(#game.state.pilotIds, 0)
  for _, id in game.state.shipIds do
    t.eq(game.state.ships[id].owner, "player", `{count} pirates should have left`)
  end
end)

suite:Case("a cleared belt stays quiet for twenty minutes, and a peaceful game always", function(t)
  local game = inSpace(false)
  toBelt(game)
  t.ok(#game.state.pilotIds > 0, "no pirates came")
  for _, id in table.clone(game.state.pilotIds) do
    Aftermath.Destroy(game.state, id, 0, game.events)
  end
  Core.TakeEvents(game)
  local arrivals = 0
  for _ = 1, 1190 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      if event.kind == "PiratesArrived" then
        arrivals += 1
      end
    end
  end
  t.eq(arrivals, 0)
  stepUntil(game, "PiratesArrived", 20)

  local quiet = inSpace(true)
  toBelt(quiet)
  for _ = 1, 100 do
    Core.Step(quiet)
  end
  t.eq(#quiet.state.pilotIds, 0)
end)

return suite
