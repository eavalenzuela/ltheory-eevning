--!strict
-- Pirates raiding a pilot's tower (Tactical/Raids).

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Codec = require("@lt/Core/Persist/Codec")
local Constants = require("@lt/Core/Data/Constants")
local Core = require("@lt/Core/Api")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Raids = require("@lt/Core/Tactical/Raids")
local Space = require("@lt/Core/Tactical/Space")
local Starbases = require("@lt/Core/Assets/Starbases")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Raids")

local SMALL = Structures.towerById["tower.vessari.small"]
local HOUR = math.floor(3600 / Constants.TICK + 0.5)

local function steps(game: Core.Game, count: number)
  for _ = 1, count do
    Core.Step(game)
  end
end

-- A galaxy of forty systems, with pirates in it, and the pilot docked at home.
local function galaxy(peaceful: boolean?): Core.Game
  return Core.New({ galaxySeed = 1, historySeed = 1, systems = 40, peaceful = peaceful == true })
end

-- A lit small tower of the pilot's at a moon of the first system of a
-- kind of space ("secure", "low", "lawless"), put there from nowhere:
-- its station's id, and the tower.
local function tower(game: Core.Game, band: string): (number, State.Starbase)
  local state = game.state
  for id, node in state.galaxy.systems do
    if Galaxy.Band(node.security) == band then
      for _, object in Space.Describe(state, id).objects do
        if object.kind == "moon" then
          local station = Starbases.Raise(state, id, object, SMALL, "player", object.x + 5 * object.radius, object.y, object.z)
          local starbase = state.starbases[station]
          starbase.ready, starbase.fuel = state.tick, 1000000
          return station, starbase
        end
      end
    end
  end
  error(`no moon in {band} space`)
end

-- The raid on a tower that the next few ticks bring, made due now.
local function raided(game: Core.Game, starbase: State.Starbase): Space.Event
  starbase.raid = game.state.tick + 1
  for _ = 1, 3 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      if event.kind == "TowerRaided" and event.station == starbase.id then
        return event
      end
    end
  end
  error("no raid came", 2)
end

local function stored(game: Core.Game, station: number, type: string): number
  local units = 0
  for _, item in Items.In(game.state, station, "hangar") do
    units += if item.type == type then item.quantity else 0
  end
  return units
end

suite:Case("a tower where order is kept is left alone, and where it is thin a raid comes in its time: sooner where there is no order at all", function(t)
  local game = galaxy()
  local state = game.state
  local _, safe = tower(game, "secure")
  local _, thin = tower(game, "low")
  local _, wild = tower(game, "lawless")
  -- (with batteries enough to see anybody off: this is about when they come)
  for _ = 1, 5 do
    table.insert(wild.modules, { type = "battery.gun", ready = state.tick })
  end
  t.eq({ Raids.Band(state, safe), Raids.Band(state, thin), Raids.Band(state, wild) }, { "secure", "low", "lawless" })
  Core.Step(game)
  local now = state.tick
  t.eq(safe.raid, 0)
  t.ok(thin.raid - now >= 8 * HOUR - 1 and thin.raid - now <= 14 * HOUR, `a raid in low security in {(thin.raid - now) / HOUR} hours`)
  t.ok(wild.raid - now >= 3 * HOUR - 1 and wild.raid - now <= 6 * HOUR, `a raid in lawless space in {(wild.raid - now) / HOUR} hours`)
  -- It comes when it is due, and the next is set for its own time after.
  local due = wild.raid
  local came = 0
  for _ = 1, due - now + 2 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      if event.kind == "TowerRaided" then
        came += 1
        t.eq({ event.station, state.tick } :: { any }, { wild.id, due } :: { any })
      end
    end
  end
  t.eq({ came, wild.raids, safe.raids }, { 1, 1, 0 })
  t.ok(wild.raid - due >= 3 * HOUR and wild.raid - due <= 6 * HOUR)
  t.eq(safe.raid, 0)
  -- A tower still anchoring has nothing to come for.
  local _, fresh = tower(game, "lawless")
  fresh.ready = state.tick + 100000
  Core.Step(game)
  t.eq(fresh.raid, 0)
end)

suite:Case("with nothing against it a raid carries off most of what the drill brought up and puts the drill out; nothing else is touched", function(t)
  local game = galaxy()
  local state = game.state
  local station, starbase = tower(game, "low")
  table.insert(starbase.modules, { type = Structures.DRILL, ready = state.tick })
  Items.Add(state, "moon.promethite", 2000, station, "hangar")
  Items.Add(state, "moon.cadmite", 10, station, "hangar")
  Items.Add(state, "ore.ferrite", 500, station, "hangar")
  Core.Step(game)
  t.eq({ Raids.Defence(state, starbase) }, { 0, 0, 0 })
  local raid = raided(game, starbase)
  t.eq({ raid.outcome, raid.defence } :: { any }, { "robbed", 0 } :: { any })
  t.ok(raid.strength >= 2 and raid.strength <= 4, `a raid in low security {raid.strength} strong`)
  -- (four fifths of each moon material, in whole units, and none of the ore)
  t.eq({ stored(game, station, "moon.promethite"), stored(game, station, "moon.cadmite"), stored(game, station, "ore.ferrite") },
    { 400, 2, 500 })
  t.eq(raid.taken, 1600 + 8)
  -- (and it is on the tower's count of what raiders have had)
  t.eq(starbase.robbed, 1608)
  -- The drill is out for an hour, and then at work again.
  local status = assert(Core.Query.Starbase(game, station))
  t.eq({ status.drilling.anchored, status.drilling.online } :: { any }, { true, false } :: { any })
  steps(game, HOUR + 2)
  t.ok(assert(Core.Query.Starbase(game, station)).drilling.online, "the drill should be back after its hour")
  -- The tower stands, and has what it had.
  t.ok(state.starbases[station] ~= nil and Starbases.Lit(state, starbase))
end)

suite:Case("a raid robs the corporation's hangar at a tower as it does the pilot's own", function(t)
  local game = galaxy()
  local state = game.state
  local station, starbase = tower(game, "low")
  Items.Add(state, "moon.promethite", 1000, station, "hangar")
  Items.Add(state, "moon.promethite", 500, station, "corporate")
  Core.Step(game)
  local raid = raided(game, starbase)
  t.eq(raid.outcome, "robbed")
  local theirs = 0
  for _, item in Items.In(state, station, "corporate") do
    theirs += if item.type == "moon.promethite" then item.quantity else 0
  end
  t.eq({ stored(game, station, "moon.promethite"), theirs, raid.taken }, { 200, 100, 1200 })
end)

suite:Case("batteries online stand against a raid: enough of them beat it off, and too few lose less", function(t)
  local game = galaxy()
  local state = game.state
  local wild = assert(Core.Query.Starbase(game, (tower(game, "lawless"))))
  t.eq({ wild.defence, wild.raidLeast, wild.raidMost }, { 0, 4, 9 })
  -- (where order is thin: a raid there is after what can be carried, whatever it is met with)
  local station, starbase = tower(game, "low")
  local status = assert(Core.Query.Starbase(game, station))
  t.eq({ status.defence, status.raidLeast, status.raidMost }, { 0, 2, 4 })
  -- One battery: a raid stronger than it still gets in, for a smaller share.
  table.insert(starbase.modules, { type = "battery.gun", ready = state.tick })
  Items.Add(state, "moon.dysprite", 1000, station, "hangar")
  Core.Step(game)
  t.eq({ Raids.Defence(state, starbase) }, { Raids.BATTERY, 1, 0 })
  local raid = raided(game, starbase)
  for _ = 1, 20 do
    if raid.outcome ~= "beaten" then
      break
    end
    -- (one no stronger than the battery is seen off, and nothing taken)
    t.ok(raid.strength <= Raids.BATTERY and raid.taken == 0)
    raid = raided(game, starbase)
  end
  t.eq({ raid.outcome, raid.defence } :: { any }, { "robbed", Raids.BATTERY } :: { any })
  local share = math.min(Raids.MOST, (raid.strength - raid.defence) / raid.strength)
  t.eq(raid.taken, math.floor(1000 * share))
  t.ok(share < Raids.MOST, "a battery should be worth something")
  local left = stored(game, station, "moon.dysprite")
  t.eq(left, 1000 - raid.taken)
  -- A battery still coming online counts for nothing, nor do any at a dark tower.
  table.insert(starbase.modules, { type = "battery.missile", ready = state.tick + 100000 })
  t.eq({ Raids.Defence(state, starbase) }, { Raids.BATTERY, 1, 0 })
  starbase.fuel = 0
  t.eq({ Raids.Defence(state, starbase) }, { 0, 0, 0 })
  starbase.fuel = 1000000
  -- Five of them are more than any raid here: beaten off, and nothing taken, every time.
  for _ = 1, 4 do
    table.insert(starbase.modules, { type = "battery.gun", ready = state.tick })
  end
  t.eq((Raids.Defence(state, starbase)), 5 * Raids.BATTERY)
  for _ = 1, 6 do
    local again = raided(game, starbase)
    t.eq({ again.outcome, again.taken } :: { any }, { "beaten", 0 } :: { any })
  end
  t.eq(stored(game, station, "moon.dysprite"), left)
  t.eq(assert(Core.Query.Starbase(game, station)).batteries, 5)
end)

suite:Case("a hired pilot set to hold the place counts for the ship they fly", function(t)
  local game = galaxy()
  local state = game.state
  local station, starbase = tower(game, "low")
  local object = assert(Space.Object(state, station))
  local system = Space.SystemOf(state, station)
  local function guard(id: number, hull: string, order: string, post: number)
    local ship = Space.NewShip(state, hull, "Guard", "player", 0)
    Space.Launch(state, ship, system, object.x + 500 * id, object.y, object.z)
    ship.pilot = id
    state.fleet[id] = { id = id, name = "Somebody", skill = 3, wage = 1, paid = state.tick, ship = ship.id, order = order, target = 0, post = post,
      base = 0, hauled = 0, experience = 0, cargo = "", sell = false, earned = 0, ward = 0, alarm = false, stops = {}, leg = 0,
      want = "", need = 0, limit = 0, keep = 0, retry = 0, loyalty = 40, drops = {}, turn = 0 }
    table.insert(state.fleetIds, id)
  end
  guard(901, "destroyer.nozomi", "patrol", station)
  t.eq({ Raids.Defence(state, starbase) }, { Raids.PATROL.destroyer, 0, 1 })
  -- (one who is only following, or holds somewhere else, is not holding this place)
  guard(902, "destroyer.nozomi", "follow", station)
  guard(903, "destroyer.nozomi", "patrol", station + 1)
  t.eq({ Raids.Defence(state, starbase) }, { Raids.PATROL.destroyer, 0, 1 })
  -- A destroyer is worth a battery; with a battery beside it, a raid in low security at its weakest is met.
  table.insert(starbase.modules, { type = "battery.gun", ready = state.tick })
  t.eq((Raids.Defence(state, starbase)), Raids.PATROL.destroyer + Raids.BATTERY)
  t.eq(assert(Core.Query.Starbase(game, station)).patrol, 1)
end)

suite:Case("with the pilot there a raid is a pack that arrives, to be fought, and nothing is carried off", function(t)
  local game = galaxy()
  local state = game.state
  local station, starbase = tower(game, "low")
  Items.Add(state, "moon.dysprite", 1000, station, "hangar")
  -- (moored there)
  state.ships[state.player.ship].docked = station
  starbase.raid = state.tick + 1
  local arrived, fought = 0, false
  for _ = 1, 3 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      if event.kind == "PiratesArrived" and event.grid == station then
        arrived = event.count
      elseif event.kind == "TowerRaided" then
        fought = event.outcome == "fought" and event.taken == 0
      end
    end
  end
  t.ok(arrived >= 2 and fought, `{arrived} pirates came, and the raid was {if fought then "fought" else "not fought"}`)
  t.eq(stored(game, station, "moon.dysprite"), 1000)
  local there = 0
  for _, id in state.ballIds do
    local ball = state.balls[id]
    there += if state.ships[id].owner == "pirates" and ball.grid == station then 1 else 0
  end
  t.eq(there, arrived)
end)

suite:Case("a game with no pirates has no raids, a raid to come is in the save, and a save from before opens with none begun", function(t)
  local quiet = galaxy(true)
  local station, starbase = tower(quiet, "lawless")
  Items.Add(quiet.state, "moon.dysprite", 1000, station, "hangar")
  Core.Step(quiet)
  starbase.raid = quiet.state.tick + 1
  steps(quiet, 3)
  for _, event in Core.TakeEvents(quiet) do
    t.ok(event.kind ~= "TowerRaided", "a raid came in a game with no pirates")
  end
  t.eq(stored(quiet, station, "moon.dysprite"), 1000)

  local game = galaxy()
  local _, wild = tower(game, "lawless")
  steps(game, 10)
  t.ok(wild.raid > 0)
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.eq(loaded.state.starbases[wild.id].raid, wild.raid)
  local file = Codec.Decode(data, length)
  file.saveVersion = 52
  file.state.starbases[wild.id].raid = nil
  file.state.starbases[wild.id].raids = nil
  local old, oldLength = Codec.Encode(file)
  local opened = Core.Load(old, oldLength)
  t.eq({ opened.state.starbases[wild.id].raid, opened.state.starbases[wild.id].raids }, { 0, 0 })
  Core.Step(opened)
  t.ok(opened.state.starbases[wild.id].raid > opened.state.tick, "its first raid should be set for its time")
end)

-- Every event of a kind that the next few ticks bring, with a raid on a tower made due now.
local function besieged(game: Core.Game, starbase: State.Starbase, ticks: number?): { [string]: { Space.Event } }
  starbase.raid = game.state.tick + 1
  local found: { [string]: { Space.Event } } = {}
  for _ = 1, ticks or 3 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      found[event.kind] = found[event.kind] or {}
      table.insert(found[event.kind], event)
    end
  end
  return found
end

-- The pirates who have come for a tower and are there.
local function raiders(game: Core.Game, station: number): { number }
  local found: { number } = {}
  for _, id in game.state.pilotIds do
    if game.state.pilots[id].home == station and game.state.balls[id] then
      table.insert(found, id)
    end
  end
  return found
end

suite:Case("a tower has a shield, armour and a structure, and a thing at its heart that stands for it where it is shot at", function(t)
  local game = galaxy()
  local state = game.state
  local station, starbase = tower(game, "low")
  t.eq(starbase.core, 0)
  Core.Step(game)
  local core = assert(state.balls[starbase.core], "an anchored tower should have its core out")
  local ship = state.ships[starbase.core]
  local object = assert(Space.Object(state, station))
  t.eq({ ship.type, ship.owner, core.grid, core.x, core.y, core.z, core.maxVelocity } :: { any },
    { Structures.Core(Structures.towerById[starbase.tower]), "starbase", station, object.x, object.y, object.z, 0 } :: { any })
  t.eq({ core.vitals.shieldMax, core.vitals.armorMax, core.vitals.hullMax }, { SMALL.shield, SMALL.armor, SMALL.hull })
  t.eq({ Starbases.Health(state, starbase) }, { 1, 1, 1 })
  t.eq(Starbases.OfCore(state, starbase.core), starbase)
  -- (it is nobody's ship: not the pilot's to board, and not one that keeps the tower from being taken down)
  t.eq(state.pilots[starbase.core], nil)
  -- Sealing charges go in its bay as fuel goes in its tank: as many as it holds.
  local ship0 = state.player.ship
  state.ships[ship0].docked = station
  local charges = Items.Add(state, Structures.SEAL.id, 20, ship0, "cargo")
  local function refused(command: State.Command): string?
    command.actor = ship0
    local ok, why = Core.Validate(game, command)
    return if ok then "(accepted)" else why
  end
  t.eq(refused({ kind = "Fuel", actor = 0, item = charges.id, quantity = SMALL.bay + 1 }), `its bay has room for {SMALL.bay} more`)
  t.ok((Core.Submit(game, { kind = "Fuel", actor = ship0, item = charges.id })))
  Core.Step(game)
  t.eq({ starbase.charges, charges.quantity }, { SMALL.bay, 20 - SMALL.bay })
  t.eq(refused({ kind = "Fuel", actor = 0, item = charges.id }), `its bay holds {SMALL.bay} sealing charges, and is full`)
  local status = assert(Core.Query.Starbase(game, station))
  t.eq({ status.charges, status.bay, status.sealed, status.shield, status.armor, status.hull } :: { any },
    { SMALL.bay, SMALL.bay, 0, 1, 1, 1 } :: { any })
end)

suite:Case("where nobody keeps order a raid the defence does not match is a siege: with nobody there the tower seals, an hour a charge, and they are back when it opens", function(t)
  local game = galaxy()
  local state = game.state
  local station, starbase = tower(game, "lawless")
  Items.Add(state, "moon.dysprite", 1000, station, "hangar")
  Core.Step(game)
  starbase.charges = 6
  local core = assert(state.balls[starbase.core])
  local said = besieged(game, starbase)
  local raid = assert(said.TowerRaided)[1]
  t.eq({ #said.TowerRaided, raid.outcome, raid.back, raid.taken } :: { any }, { 1, "siege", false, 0 } :: { any })
  t.ok(raid.strength >= 4 and raid.strength <= 9)
  -- Sealed: for six hours, its charges burnt, its shield at the quarter; it does nothing, and nothing is taken.
  local sealed = assert(said.TowerSealed, "the tower did not seal")[1]
  t.eq({ sealed.station, sealed.hours, sealed.opens - state.tick > 6 * HOUR - 5, starbase.charges, starbase.siege } :: { any },
    { station, 6, true, 0, raid.strength } :: { any })
  t.eq({ Starbases.Sealed(state, starbase), Starbases.Lit(state, starbase), (Raids.Defence(state, starbase)) } :: { any },
    { true, false, 0 } :: { any })
  t.near(core.vitals.shield / core.vitals.shieldMax, Raids.QUARTER, 0.01)
  t.eq(stored(game, station, "moon.dysprite"), 1000)
  local status = assert(Core.Query.Starbase(game, station))
  t.ok(status.sealed > 6 * 3600 - 10 and status.sealed <= 6 * 3600 and status.siege == raid.strength)
  -- Nobody comes while it is sealed, and it is in the save.
  local fuel = starbase.fuel
  steps(game, 3 * HOUR)
  t.eq({ state.starbases[station] ~= nil, starbase.fuel } :: { any }, { true, fuel } :: { any })
  for _, event in Core.TakeEvents(game) do
    t.ok(event.kind ~= "TowerRaided", "a raid came for a sealed tower")
  end
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  -- Batteries put up while it holds out are there when they come back: enough of them, and they are seen off.
  local other = Core.Load(data, length)
  for _ = 1, 5 do
    table.insert(other.state.starbases[station].modules, { type = "battery.gun", ready = other.state.tick })
  end
  local outcome = ""
  for _ = 1, 3 * HOUR + 10 do
    Core.Step(other)
    for _, event in Core.TakeEvents(other) do
      outcome = if event.kind == "TowerRaided" then event.outcome else outcome
    end
  end
  t.eq({ outcome, other.state.starbases[station] ~= nil, other.state.starbases[station].siege } :: { any }, { "beaten", true, 0 } :: { any })
  -- With nothing against them, they bring it down: the tower, and what was in it.
  local opened, lost = false, nil :: Space.Event?
  for _ = 1, 3 * HOUR + 10 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      opened = opened or event.kind == "TowerOpened"
      lost = if event.kind == "TowerLost" then event else lost
    end
  end
  t.ok(opened, "the tower did not open")
  t.ok(lost ~= nil and (lost :: any).station == station, "the tower was not lost")
  t.eq({ state.starbases[station], #state.starbaseIds, assert(Space.Object(state, station)).kind, state.ships[core.id] } :: { any },
    { nil, 0, "gone", nil } :: { any })
  t.eq(stored(game, station, "moon.dysprite"), 0)
end)

suite:Case("a tower with no charge to burn does not seal: a siege nobody meets brings it down at once, and what was moored there is found at home", function(t)
  local game = galaxy()
  local state = game.state
  local station, starbase = tower(game, "lawless")
  Core.Step(game)
  local moored = Space.NewShip(state, "frigate.courier", "Left there", "player", station)
  local said = besieged(game, starbase)
  local outcomes: { string } = {}
  local came: { Space.Event } = said.TowerRaided or {}
  for _, event in came do
    table.insert(outcomes, event.outcome)
  end
  t.eq(outcomes, { "siege", "lost" })
  t.ok(said.TowerLost ~= nil and said.TowerSealed == nil)
  t.eq({ state.starbases[station], moored.docked } :: { any }, { nil, state.player.home } :: { any })
  -- (a dark tower with charges aboard is no better off: sealing wants power)
  local dark, tank = tower(game, "lawless")
  Core.Step(game)
  tank.charges, tank.fuel = 6, 0
  t.ok(besieged(game, tank).TowerLost ~= nil, "a dark tower sealed itself")
  t.eq(state.starbases[dark], nil)
end)

suite:Case("with the pilot there a siege is a pack that goes for the tower: its shield at the quarter it seals and they go, and it cannot be shot at", function(t)
  local game = galaxy()
  local state = game.state
  local station, starbase = tower(game, "lawless")
  Core.Step(game)
  starbase.charges = 4
  local core = assert(state.balls[starbase.core])
  -- (the pilot out in space beside it)
  local object = assert(Space.Object(state, station))
  local me = state.balls[state.player.ship]
  if me == nil then
    local mine = state.ships[state.player.ship]
    me = Space.Launch(state, mine, Space.SystemOf(state, station), object.x + object.radius + 2000, object.y, object.z)
  end
  me.system = Space.SystemOf(state, station)
  me.x, me.y, me.z = object.x + object.radius + 2000, object.y, object.z
  Space.AssignGrid(state, me)
  t.eq(me.grid, station)
  local said = besieged(game, starbase, 6)
  local raid = assert(said.TowerRaided)[1]
  t.eq({ raid.outcome, starbase.siege } :: { any }, { "siege", raid.strength } :: { any })
  local pack = raiders(game, station)
  t.ok(#pack >= 2, `{#pack} came`)
  -- Most of them are after the tower.
  steps(game, 5)
  local onTower = 0
  for _, id in raiders(game, station) do
    onTower += if state.pilots[id].prey == core.id then 1 else 0
  end
  t.ok(onTower >= 1, "nobody is after the tower")
  -- It can be locked, as anything can: by them, and by the pilot.
  t.ok((Core.Validate(game, { kind = "LockTarget", actor = me.id, target = core.id })))
  -- Its shield at the quarter: it seals, for an hour a charge, and those who came go.
  core.vitals.shield = 0.2 * core.vitals.shieldMax
  Core.TakeEvents(game)
  steps(game, 2)
  local sealed = false
  for _, event in Core.TakeEvents(game) do
    sealed = sealed or (event.kind == "TowerSealed" and event.hours == 4)
  end
  t.ok(sealed, "the tower did not seal")
  t.eq({ #raiders(game, station), Starbases.Sealed(state, starbase), starbase.siege } :: { any }, { 0, true, raid.strength } :: { any })
  local ok, why = Core.Validate(game, { kind = "LockTarget", actor = me.id, target = core.id })
  t.eq({ ok, why } :: { any }, { false, "the tower has sealed itself" } :: { any })
  -- When it opens they are back, and with the pilot there it is a fight again.
  local back = false
  for _ = 1, 4 * HOUR + 10 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      back = back or (event.kind == "TowerRaided" and event.outcome == "siege" and event.back == true)
    end
    if back then
      break
    end
  end
  t.ok(back, "they did not come back when it opened")
  t.near(core.vitals.shield / core.vitals.shieldMax, Raids.QUARTER, 0.01)
  -- Seen off, every one of them: the siege is broken, and the tower stands.
  steps(game, 3)
  for _, id in raiders(game, station) do
    Aftermath.Destroy(state, id, me.id, game.events)
  end
  Core.TakeEvents(game)
  steps(game, 5)
  local broken = false
  for _, event in Core.TakeEvents(game) do
    broken = broken or event.kind == "SiegeBroken"
  end
  t.ok(broken, "nobody said the siege was broken")
  t.eq({ starbase.siege, state.starbases[station] ~= nil } :: { any }, { 0, true } :: { any })
end)

suite:Case("a tower whose core is destroyed is lost: the pilot moored there is put out into space, and a hired pilot posted there waits", function(t)
  local game = galaxy()
  local state = game.state
  local station, starbase = tower(game, "lawless")
  Core.Step(game)
  local core = assert(state.balls[starbase.core])
  state.ships[state.player.ship].docked = station
  Items.Add(state, "ore.ferrite", 500, station, "corporate")
  table.insert(starbase.modules, { type = "array.storage", ready = state.tick })
  state.fleet[77] = { id = 77, name = "Somebody", skill = 1, wage = 1, paid = state.tick, ship = 0, order = "haul", target = 0, post = station,
    base = state.player.home, hauled = 0, experience = 0, cargo = "ore", sell = false, earned = 0, ward = 0, alarm = false,
    stops = { station }, leg = 0, want = "", need = 0, limit = 0, keep = 0, retry = 0, loyalty = 40, drops = {}, turn = 0 }
  table.insert(state.fleetIds, 77)
  Core.TakeEvents(game)
  Aftermath.Destroy(state, core.id, 0, game.events)
  local lost: Space.Event? = nil
  for _, event in Core.TakeEvents(game) do
    lost = if event.kind == "TowerLost" then event else lost
  end
  t.ok(lost ~= nil and (lost :: any).modules == 1 and (lost :: any).stacks == 1, "the tower was not said to be lost with what was on it and in it")
  t.eq({ state.starbases[station], #Items.Stored(state, station), assert(Space.Object(state, station)).kind } :: { any }, { nil, 0, "gone" } :: { any })
  local me = state.balls[state.player.ship]
  t.ok(me ~= nil and state.ships[state.player.ship].docked == 0, "the pilot should be out in space")
  t.eq({ state.fleet[77].order, state.fleet[77].post, #state.fleet[77].stops } :: { any }, { "stay", 0, 0 } :: { any })
  -- (what is left of it lies where it was, on the grid the pilot is on)
  local wrecks = 0
  for _, id in state.wreckIds do
    wrecks += if state.wrecks[id].grid == me.grid then 1 else 0
  end
  t.eq(wrecks, 1)
  steps(game, 20)
end)

suite:Case("a lit tower mends, a save from before there were sieges opens with nothing to seal with, and nobody after it", function(t)
  local game = galaxy()
  local state = game.state
  local station, starbase = tower(game, "low")
  Core.Step(game)
  local core = assert(state.balls[starbase.core])
  core.vitals.armor, core.vitals.hull = 0.5 * core.vitals.armorMax, 0.5 * core.vitals.hullMax
  steps(game, 2 * HOUR)
  t.near(core.vitals.armor / core.vitals.armorMax, 0.5 + 2 * Raids.MEND, 1e-6)
  t.near(core.vitals.hull / core.vitals.hullMax, 0.5 + 2 * Raids.MEND, 1e-6)
  local data, length = Core.Save(game)
  local file = Codec.Decode(data, length)
  file.saveVersion = 61
  local record = file.state.starbases[station]
  record.core, record.charges, record.sealed, record.siege = nil, nil, nil, nil
  file.state.balls[starbase.core] = nil
  file.state.ships[starbase.core] = nil
  for at, id in file.state.ballIds do
    if id == starbase.core then
      table.remove(file.state.ballIds, at)
      break
    end
  end
  for at, id in file.state.shipIds do
    if id == starbase.core then
      table.remove(file.state.shipIds, at)
      break
    end
  end
  local old, oldLength = Codec.Encode(file)
  local opened = Core.Load(old, oldLength)
  local was = opened.state.starbases[station]
  t.eq({ was.core, was.charges, was.sealed, was.siege }, { 0, 0, 0, 0 })
  Core.Step(opened)
  t.ok(was.core ~= 0 and opened.state.balls[was.core] ~= nil, "it should be given what stands for it as the game goes on")
end)

return suite
