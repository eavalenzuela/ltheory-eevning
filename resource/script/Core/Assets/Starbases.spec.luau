--!strict
-- Starbases a pilot puts up (Assets/Starbases), through the Core's
-- front door.

local Blueprints = require("@lt/Core/Data/Blueprints")
local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Items = require("@lt/Core/Assets/Items")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Stations = require("@lt/Core/Assets/Stations")
local Structures = require("@lt/Core/Data/Structures")
local System = require("@lt/Core/Describe/System")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Starbases")

local SMALL = Structures.towerById["tower.vessari.small"]
local FUEL = Structures.FUEL.id

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

local function steps(game: Core.Game, count: number)
  for _ = 1, count do
    Core.Step(game)
  end
end

local function stepUntil(game: Core.Game, kind: string, limit: number): Space.Event
  for _ = 1, limit do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      if event.kind == kind then
        return event
      end
    end
  end
  error(`no {kind} within {limit} ticks`, 2)
end

local function hold(game: Core.Game, type: string): State.Item?
  for _, item in Items.In(game.state, game.state.player.ship, "cargo") do
    if item.type == type then
      return item
    end
  end
  return nil
end

local function carry(game: Core.Game, type: string, quantity: number): State.Item
  return Items.Add(game.state, type, quantity, game.state.player.ship, "cargo")
end

-- A moon of the first system the ship can warp to from where it is.
local function aMoon(game: Core.Game): System.Object
  for _, object in Core.Query.Objects(game, 1) do
    if object.kind == "moon" and Core.Validate(game, { kind = "WarpTo", actor = game.state.player.ship, target = object.id }) then
      return object
    end
  end
  error("no moon to warp to")
end

-- A peaceful game with the pilot's ship in space beside a moon, a small
-- tower in its hold: the game, the moon and the tower.
local function atMoon(t: Test.Context): (Core.Game, System.Object, State.Item)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local tower = carry(game, SMALL.id, 1)
  order(t, game, { kind = "Undock", actor = 0 })
  Core.Step(game)
  local moon = aMoon(game)
  order(t, game, { kind = "WarpTo", actor = 0, target = moon.id })
  stepUntil(game, "WarpEnded", 600)
  return game, moon, tower
end

-- The same with the tower anchored and the ship moored at it: the game
-- and the station the tower is.
local function moored(t: Test.Context, fuel: number?): (Core.Game, number)
  local game, moon, tower = atMoon(t)
  order(t, game, { kind = "AnchorTower", actor = 0, item = tower.id, target = moon.id })
  local station = stepUntil(game, "StarbaseAnchored", 3).station :: number
  steps(game, SMALL.anchor)
  order(t, game, { kind = "Dock", actor = 0, target = station })
  stepUntil(game, "Docked", 120)
  if fuel then
    order(t, game, { kind = "Fuel", actor = 0, item = carry(game, FUEL, fuel).id })
    Core.Step(game)
  end
  return game, station
end

-- Anchor a module from the hold and wait for it to come online.
local function anchor(t: Test.Context, game: Core.Game, type: string)
  order(t, game, { kind = "AnchorModule", actor = 0, item = carry(game, type, 1).id })
  steps(game, Structures.moduleById[type].anchor + 1)
end

suite:Case("a tower is anchored from the hold, beside a moon, and nowhere else", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local tower = carry(game, SMALL.id, 1)
  local ore = carry(game, "ore.ferrite", 10)
  local far: System.Object? = nil
  for _, object in Core.Query.Objects(game, 1) do
    if object.kind == "moon" then
      far = far or object
    end
  end
  local moon = assert(far)
  t.eq(refused(game, { kind = "AnchorTower", actor = 0, item = tower.id, target = moon.id }), "docked")
  order(t, game, { kind = "Undock", actor = 0 })
  Core.Step(game)
  local here = aMoon(game)
  t.eq(refused(game, { kind = "AnchorTower", actor = 0, item = tower.id, target = here.id }), "too far from the moon")
  t.eq(refused(game, { kind = "AnchorTower", actor = 0, item = ore.id, target = here.id }), "no control tower in the hold")
  t.eq(refused(game, { kind = "AnchorTower", actor = 0, item = tower.id, target = game.state.player.home }), "a tower is anchored at a moon")
  order(t, game, { kind = "WarpTo", actor = 0, target = here.id })
  Core.Step(game)
  stepUntil(game, "WarpEnded", 600)
  t.eq(refused(game, { kind = "AnchorTower", actor = 0, item = tower.id, target = here.id }), "(accepted)")
end)

suite:Case("an anchored tower is a station of its system from then on, and the ship that put it up is on its grid", function(t)
  local game, moon, tower = atMoon(t)
  local before = #Core.Query.Objects(game, 1)
  order(t, game, { kind = "AnchorTower", actor = 0, item = tower.id, target = moon.id })
  local station = stepUntil(game, "StarbaseAnchored", 3).station :: number
  t.eq(hold(game, SMALL.id), nil)
  local objects = Core.Query.Objects(game, 1)
  t.eq(#objects, before + 1)
  local object = assert(Space.Object(game.state, station))
  t.eq({ object.kind, object.variety, object.parent, object.site, object.radius } :: { any },
    { "station", "starbase", moon.id, station, SMALL.field } :: { any })
  t.eq(objects[#objects].id, station)
  local ball = assert(Core.Query.Ball(game, game.state.player.ship))
  t.eq(ball.grid, station)
  t.ok(Space.Distance(ball :: any, object :: any) < SMALL.field, "the ship is outside the field of the tower it anchored")
  -- (it is on the overview, by name)
  local listed = false
  for _, entry in Core.Query.Overview(game) do
    listed = listed or entry.id == station
  end
  t.ok(listed, "the tower is not on the overview")
  local status = assert(Core.Query.Starbase(game, station))
  t.eq({ status.tower.id, status.anchored, status.lit, status.fuel, #status.modules } :: { any }, { SMALL.id, false, false, 0, 0 } :: { any })
  t.eq(assert(Stations.Makeup(game.state, station)).tower, SMALL.id)
end)

suite:Case("nobody moors at a tower until it is anchored, and a moon takes one tower", function(t)
  local game, moon, tower = atMoon(t)
  order(t, game, { kind = "AnchorTower", actor = 0, item = tower.id, target = moon.id })
  local station = stepUntil(game, "StarbaseAnchored", 3).station :: number
  t.eq(refused(game, { kind = "Dock", actor = 0, target = station }), "the tower is not anchored yet")
  local second = carry(game, SMALL.id, 1)
  t.eq(refused(game, { kind = "AnchorTower", actor = 0, item = second.id, target = moon.id }), "that moon has a tower already")
  steps(game, SMALL.anchor)
  t.ok(assert(Core.Query.Starbase(game, station)).anchored)
  order(t, game, { kind = "Dock", actor = 0, target = station })
  stepUntil(game, "Docked", 120)
  t.eq(Core.Query.Player(game).docked, station)
  -- (and the pilot can put things down there, and leave again)
  order(t, game, { kind = "MoveItems", actor = 0, item = second.id, to = "hangar" })
  Core.Step(game)
  t.eq(#Core.Query.Items(game, station, "hangar"), 1)
  order(t, game, { kind = "Undock", actor = 0 })
  stepUntil(game, "Undocked", 3)
end)

suite:Case("fuel lights a tower, and it burns by the hour", function(t)
  local game, station = moored(t)
  local status = assert(Core.Query.Starbase(game, station))
  t.eq({ status.anchored, status.lit } :: { any }, { true, false } :: { any })
  local ore = carry(game, "ore.ferrite", 10)
  t.eq(refused(game, { kind = "Fuel", actor = 0, item = ore.id }), "no fuel to hand")
  local blocks = carry(game, FUEL, 100)
  t.eq(refused(game, { kind = "Fuel", actor = 0, item = blocks.id, quantity = 101 }), "not that many")
  order(t, game, { kind = "Fuel", actor = 0, item = blocks.id, quantity = 60 })
  Core.Step(game)
  t.eq(assert(hold(game, FUEL)).quantity, 40)
  status = assert(Core.Query.Starbase(game, station))
  t.eq({ status.lit, status.fuel, status.hours } :: { any }, { true, 60, 60 / SMALL.fuel } :: { any })
  -- (fuel in the tower's own hangar will do as well as fuel in the hold)
  order(t, game, { kind = "MoveItems", actor = 0, item = blocks.id, to = "hangar" })
  Core.Step(game)
  order(t, game, { kind = "Fuel", actor = 0, item = Core.Query.Items(game, station, "hangar")[1].id })
  Core.Step(game)
  t.eq(assert(Core.Query.Starbase(game, station)).fuel, 100)
  local was = game.state.starbases[station].fuel
  steps(game, 3600)
  t.eq(was - game.state.starbases[station].fuel, SMALL.fuel)
end)

suite:Case("a module is anchored at a lit tower that can power it, and gives its service once it is online", function(t)
  local game, station = moored(t)
  local array = carry(game, "array.refining", 1)
  t.eq(refused(game, { kind = "AnchorModule", actor = 0, item = array.id }), "the tower is dark")
  order(t, game, { kind = "Fuel", actor = 0, item = carry(game, FUEL, 500).id })
  Core.Step(game)
  local ore = Items.Add(game.state, "ore.ferrite", 300, station, "hangar")
  t.eq(refused(game, { kind = "Reprocess", actor = 0, item = ore.id }), "this station has no Refining Array")
  t.eq(refused(game, { kind = "AnchorModule", actor = 0, item = carry(game, "array.trade", 1).id }), "a pilot cannot anchor a Trade Hub")
  t.eq(refused(game, { kind = "AnchorModule", actor = 0, item = ore.id }), "no structure module to hand")
  order(t, game, { kind = "AnchorModule", actor = 0, item = array.id })
  Core.Step(game)
  t.eq(hold(game, "array.refining"), nil)
  -- (there, and not yet working)
  t.eq(assert(Stations.Makeup(game.state, station)).modules, { "array.refining" })
  local status = assert(Core.Query.Starbase(game, station))
  t.eq({ status.modules[1].type, status.modules[1].online, status.powergrid, status.cpu } :: { any },
    { "array.refining", false, 350, 150 } :: { any })
  t.ok(not Stations.Has(game.state, station, "refining"))
  steps(game, Structures.moduleById["array.refining"].anchor)
  t.ok(Stations.Has(game.state, station, "refining"))
  t.ok(assert(Core.Query.Starbase(game, station)).modules[1].online)
  order(t, game, { kind = "Reprocess", actor = 0, item = ore.id })
  Core.Step(game)
  local iron = 0
  for _, item in Core.Query.Items(game, station, "hangar") do
    iron += if item.type == "mineral.iron" then item.quantity else 0
  end
  t.ok(iron > 0, "nothing was refined at the pilot's own array")
end)

suite:Case("a tower carries no more than it has the powergrid and the CPU for", function(t)
  -- A small tower supplies 1500 MW and 2000 tf.
  local game, station = moored(t, 2000)
  for _, type in { "array.assembly", "array.refining", "array.hangar", "array.laboratory", "array.habitat" } do
    anchor(t, game, type)
  end
  local carried = assert(Core.Query.Starbase(game, station))
  t.eq({ carried.powergrid, carried.cpu }, { 1350, 1250 })
  t.eq(refused(game, { kind = "AnchorModule", actor = 0, item = carry(game, "battery.gun", 1).id }), "the tower has not the powergrid")
  t.eq(refused(game, { kind = "AnchorModule", actor = 0, item = carry(game, "array.storage", 1).id }), "(accepted)")
  for _, service in { "industry", "refining", "fitting", "research", "quarters" } do
    t.ok(Stations.Has(game.state, station, service), `the pilot's tower has nothing for {service}`)
  end
  t.ok(not Stations.Has(game.state, station, "market"))

  local other, second = moored(t, 2000)
  for _ = 1, 4 do
    anchor(t, other, "array.laboratory")
  end
  local full = assert(Core.Query.Starbase(other, second))
  t.eq({ full.powergrid, full.cpu }, { 800, 2000 })
  t.eq(refused(other, { kind = "AnchorModule", actor = 0, item = carry(other, "array.storage", 1).id }), "the tower has not the CPU")
end)

suite:Case("a tower out of fuel is dark and gives nothing, and fuel lights it again at once", function(t)
  local game, station = moored(t, 2)
  anchor(t, game, "array.refining")
  local ore = Items.Add(game.state, "ore.ferrite", 300, station, "hangar")
  t.eq(refused(game, { kind = "Reprocess", actor = 0, item = ore.id }), "(accepted)")
  local dark = stepUntil(game, "StarbaseDark", 3600 // SMALL.fuel * 2 + 2)
  t.eq(dark.station, station)
  local status = assert(Core.Query.Starbase(game, station))
  t.eq({ status.lit, status.fuel, status.modules[1].online } :: { any }, { false, 0, false } :: { any })
  t.ok(not Stations.Has(game.state, station, "refining"))
  t.eq(refused(game, { kind = "Reprocess", actor = 0, item = ore.id }), "this station has no Refining Array")
  -- (it says so once, not every tick it stays dark)
  for _ = 1, 50 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      t.ok(event.kind ~= "StarbaseDark", "a dark tower went dark again")
    end
  end
  order(t, game, { kind = "Fuel", actor = 0, item = carry(game, FUEL, 5).id })
  Core.Step(game)
  t.ok(Stations.Has(game.state, station, "refining"))
  -- (and the hour starts from when it was lit, not from when it went out)
  steps(game, 3600 // SMALL.fuel - 2)
  t.eq(game.state.starbases[station].fuel, 5)
  steps(game, 2)
  t.eq(game.state.starbases[station].fuel, 4)
end)

suite:Case("a module can be unanchored again, into the tower's hangar", function(t)
  local game, station = moored(t, 100)
  anchor(t, game, "array.refining")
  anchor(t, game, "array.storage")
  t.eq(refused(game, { kind = "UnanchorModule", actor = 0, type = "array.hangar" }), "no such module is anchored here")
  order(t, game, { kind = "UnanchorModule", actor = 0, type = "array.refining" })
  Core.Step(game)
  t.eq(assert(Stations.Makeup(game.state, station)).modules, { "array.storage" })
  t.ok(not Stations.Has(game.state, station, "refining"))
  local found = 0
  for _, item in Core.Query.Items(game, station, "hangar") do
    found += if item.type == "array.refining" then item.quantity else 0
  end
  t.eq(found, 1)
end)

suite:Case("a starbase is only its owner's to run, and only from its own moorings", function(t)
  local game = moored(t, 100)
  local blocks = carry(game, FUEL, 10)
  order(t, game, { kind = "Undock", actor = 0 })
  stepUntil(game, "Undocked", 3)
  t.eq(refused(game, { kind = "Fuel", actor = 0, item = blocks.id }), "not moored at a starbase of your own")
  t.eq(refused(game, { kind = "UnanchorModule", actor = 0, type = "array.refining" }), "not moored at a starbase of your own")

  local home = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  t.eq(refused(home, { kind = "Fuel", actor = 0, item = carry(home, FUEL, 10).id }), "not moored at a starbase of your own")
end)

suite:Case("a starbase is in the save, and the game goes on the same from it", function(t)
  local game, station = moored(t, 30)
  anchor(t, game, "array.refining")
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  local object = assert(Space.Object(loaded.state, station))
  t.eq(object.variety, "starbase")
  t.eq(assert(Core.Query.Starbase(loaded, station)).fuel, assert(Core.Query.Starbase(game, station)).fuel)
  t.ok(Stations.Has(loaded.state, station, "refining"))
  steps(game, 800)
  steps(loaded, 800)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.ok(game.state.starbases[station].fuel < 30)
end)

suite:Case("a save from before there were starbases opens with none", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local data, length = Core.Save(game)
  local file = Codec.Decode(data, length)
  file.saveVersion = 11
  file.state.starbases = nil
  file.state.starbaseIds = nil
  local old, oldLength = Codec.Encode(file)
  local loaded = Core.Load(old, oldLength)
  t.eq(#loaded.state.starbaseIds, 0)
  t.eq(Core.Query.Starbase(loaded, loaded.state.player.home), nil)
  t.eq(Core.Hash(loaded), Core.Hash(game))
end)

suite:Case("towers, modules and fuel are bought, and built from blueprints", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local home = game.state.player.home
  for _, type in { SMALL.id, "array.refining", FUEL } do
    local quote = Core.Query.Quote(game, home, type)
    t.ok(quote.ask ~= nil and quote.ask > 0, `nobody sells {type} at the starter station`)
    t.ok(Blueprints.byProduct[type] ~= nil, `there is no blueprint for {type}`)
  end
end)

return suite
