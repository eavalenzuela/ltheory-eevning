--!strict
-- Starbases a pilot puts up (Assets/Starbases), through the Core's
-- front door.

local Blueprints = require("@lt/Core/Data/Blueprints")
local CitadelDoors = require("@lt/Core/Data/CitadelDoors")
local CitadelKinds = require("@lt/Core/Assets/CitadelKinds")
local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Industry = require("@lt/Core/Assets/Industry")
local Items = require("@lt/Core/Assets/Items")
local Jumping = require("@lt/Core/Tactical/Jumping")
local Market = require("@lt/Core/Assets/Market")
local Moons = require("@lt/Core/Data/Moons")
local Reactions = require("@lt/Core/Data/Reactions")
local Space = require("@lt/Core/Tactical/Space")
local Starbases = require("@lt/Core/Assets/Starbases")
local State = require("@lt/Core/Kernel/State")
local Stations = require("@lt/Core/Assets/Stations")
local Structures = require("@lt/Core/Data/Structures")
local System = require("@lt/Core/Describe/System")
local Test = require("@lt/Tool/Test")
local Types = require("@lt/Core/Data/Types")

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
-- 'deposit': one with something under it (true), or with nothing (false).
local function aMoon(game: Core.Game, deposit: boolean?): System.Object
  for _, object in Core.Query.Objects(game, 1) do
    if object.kind == "moon" and Core.Validate(game, { kind = "WarpTo", actor = game.state.player.ship, target = object.id })
      and (deposit == nil or (Core.Query.Deposit(game, object.id) ~= nil) == deposit) then
      return object
    end
  end
  error("no moon to warp to")
end

-- A peaceful game with the pilot's ship in space beside a moon, a small
-- tower in its hold: the game, the moon and the tower.
local function atMoon(t: Test.Context, deposit: boolean?): (Core.Game, System.Object, State.Item)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local tower = carry(game, SMALL.id, 1)
  order(t, game, { kind = "Undock", actor = 0 })
  Core.Step(game)
  local moon = aMoon(game, deposit)
  order(t, game, { kind = "WarpTo", actor = 0, target = moon.id })
  stepUntil(game, "WarpEnded", 600)
  return game, moon, tower
end

-- The same with the tower anchored and the ship moored at it: the game
-- and the station the tower is.
local function moored(t: Test.Context, fuel: number?, deposit: boolean?): (Core.Game, number)
  local game, moon, tower = atMoon(t, deposit)
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
  t.eq(refused(game, { kind = "AnchorTower", actor = 0, item = ore.id, target = here.id }), "no control tower or citadel in the hold")
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
  t.eq(refused(game, { kind = "AnchorTower", actor = 0, item = second.id, target = moon.id }), "that moon has a tower or a citadel already")
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

suite:Case("a pilot keeps one tower, and one more for each level of Anchoring", function(t)
  local game, moon, tower = atMoon(t)
  local state = game.state
  t.eq({ Starbases.Kept(state, "player") }, { 0, 1 })
  order(t, game, { kind = "AnchorTower", actor = 0, item = tower.id, target = moon.id })
  stepUntil(game, "StarbaseAnchored", 3)
  t.eq({ Starbases.Kept(state, "player") }, { 1, 1 })
  -- At another moon, a second is one too many.
  local other: System.Object? = nil
  for _, object in Core.Query.Objects(game, 1) do
    if object.kind == "moon" and object.id ~= moon.id and other == nil
      and Core.Validate(game, { kind = "WarpTo", actor = state.player.ship, target = object.id }) then
      other = object
    end
  end
  local there = assert(other, "no second moon to warp to")
  order(t, game, { kind = "WarpTo", actor = 0, target = there.id })
  stepUntil(game, "WarpEnded", 600)
  local second = carry(game, SMALL.id, 1)
  local again: State.Command = { kind = "AnchorTower", actor = 0, item = second.id, target = there.id }
  t.eq(refused(game, again), "you keep one tower: each level of Anchoring is one more")
  -- With a level of it, the second goes up; and a third does not.
  state.skills.anchoring = 1
  order(t, game, again)
  stepUntil(game, "StarbaseAnchored", 3)
  t.eq({ Starbases.Kept(state, "player") }, { 2, 2 })
  t.eq(refused(game, { kind = "AnchorTower", actor = 0, item = carry(game, SMALL.id, 1).id, target = there.id }),
    "that moon has a tower or a citadel already")
  -- A pilot begins with the skill at nothing, and one of a save from before is given it so.
  local fresh = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  t.eq(fresh.state.skills.anchoring, 0)
  local file = Codec.Decode(Core.Save(fresh))
  file.saveVersion = 51
  file.state.skills.anchoring = nil
  local old, oldLength = Codec.Encode(file)
  t.eq(Core.Load(old, oldLength).state.skills.anchoring, 0)
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

suite:Case("a moon may have a deposit: which, and how rich, is the moon's own, and the better ones are where order is thin", function(t)
  -- By how safe the system is: what share of moons have anything, and of what grade.
  local found: { [string]: { number } } = {}
  for _, band in { "secure", "low", "lawless" } do
    local grades = { 0, 0, 0, 0 }
    for seed = 1, 600 do
      local deposit = Moons.Deposit(seed, band)
      if deposit then
        grades[deposit.material.grade] += 1
        t.ok(deposit.richness >= Moons.POOREST and deposit.richness <= Moons.RICHEST, `a deposit {deposit.richness} rich`)
        t.eq(Moons.PerHour(deposit), math.floor(Moons.YIELD * deposit.richness + 0.5))
        -- (the same moon has the same, whenever it is asked)
        local again = assert(Moons.Deposit(seed, band))
        t.eq({ again.material.id, again.richness } :: { any }, { deposit.material.id, deposit.richness } :: { any })
      else
        grades[4] += 1
      end
    end
    found[band] = grades
  end
  print(string.format("     moons: of 600, with nothing %d where order is kept, %d where it is thin, %d where there is none; rare under %d of those",
    found.secure[4], found.low[4], found.lawless[4], found.lawless[3]))
  t.ok(found.secure[1] > 200 and found.secure[2] == 0 and found.secure[3] == 0, "where order is kept there is only the common grade")
  t.ok(found.low[1] > 150 and found.low[2] > 120 and found.low[3] == 0, "where it is thin, the middle grade too")
  t.ok(found.lawless[2] > 120 and found.lawless[3] > 80, "and the rare only where there is none")
  t.ok(found.secure[4] > found.low[4] and found.low[4] > found.lawless[4], "the safer, the more moons with nothing")
  -- Each grade has two materials, and both turn up.
  local seen: { [string]: boolean } = {}
  for seed = 1, 600 do
    local deposit = Moons.Deposit(seed, "lawless")
    if deposit then
      seen[deposit.material.id] = true
    end
  end
  for _, material in Moons.materials do
    t.ok(seen[material.id], `no moon has {material.name}`)
  end
  -- A moon of the game says what it has (the first system is a homeworld's: order is kept), and nothing else has a deposit.
  -- And stations trade in what moons give, as in anything.
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  for _, material in Moons.materials do
    local quote = Core.Query.Quote(game, game.state.player.home, material.id)
    t.ok(quote.ask ~= nil and quote.stock >= 100, `the market should have {material.name}`)
  end
  for _, object in Core.Query.Objects(game, 1) do
    local deposit = Core.Query.Deposit(game, object.id)
    if object.kind == "moon" then
      local same = Moons.Deposit(object.seed, "secure")
      t.eq(if deposit then deposit.material.id else "", if same then same.material.id else "", object.name)
    else
      t.eq(deposit, nil, object.name)
    end
  end
end)

suite:Case("a tower with a drill online brings up what is under its moon by the hour, into its hangar, while it has the room", function(t)
  local game, station = moored(t, 1000, true)
  local state = game.state
  local starbase = state.starbases[station]
  local deposit = assert(Starbases.Deposit(state, Starbases.Moon(state, starbase)), "the moon should have a deposit")
  local type, hourly = deposit.material.id, Moons.PerHour(deposit)
  local function stored(): number
    local units = 0
    for _, item in Core.Query.Items(game, station, "hangar") do
      units += if item.type == type then item.quantity else 0
    end
    return units
  end
  -- With no drill nothing comes up.
  local status = assert(Core.Query.Starbase(game, station))
  t.eq({ status.drilling.anchored, status.drilling.online, status.drilling.perHour, status.drilling.room, status.next } :: { any },
    { false, false, hourly, Moons.SILO, 0 } :: { any })
  t.ok(status.moon ~= "" and assert(status.drilling.deposit).material.id == type)
  steps(game, 3700)
  t.eq(stored(), 0)
  -- A drill is anchored: one, and no second.
  anchor(t, game, "array.drill")
  Core.TakeEvents(game)
  status = assert(Core.Query.Starbase(game, station))
  t.eq({ status.drilling.anchored, status.drilling.online } :: { any }, { true, true } :: { any })
  t.ok(status.next > 3500 and status.next <= 3600, `the first hour should be nearly all to come, not {status.next} s`)
  t.eq(refused(game, { kind = "AnchorModule", actor = 0, item = carry(game, "array.drill", 1).id }), "the tower has a drill already")
  -- An hour on, an hour's worth is in the hangar; and the same the hour after.
  local first = stepUntil(game, "MoonDrilled", 3700)
  t.eq({ first.station, first.type, first.units, first.full } :: { any }, { station, type, hourly, false } :: { any })
  t.eq(stored(), hourly)
  steps(game, 3600)
  t.eq(stored(), 2 * hourly)
  -- It is in the save, part of the way through an hour.
  steps(game, 1000)
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  steps(game, 3000)
  steps(loaded, 3000)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.eq(stored(), 3 * hourly)
  -- The tower holds a silo's worth and no more: the drill stops, and says so with the last it had room for.
  state.starbases[station].fuel = 100000
  local last: Space.Event? = nil
  for _ = 1, 30 do
    if stored() >= Moons.SILO then
      break
    end
    last = stepUntil(game, "MoonDrilled", 3700)
  end
  t.eq(stored(), Moons.SILO)
  t.eq(assert(last).full, true)
  t.ok(assert(last).units <= hourly)
  steps(game, 2 * 3600)
  t.eq(stored(), Moons.SILO, "a full tower should take no more")
  -- Some is taken away, and it goes on.
  for _, item in Items.In(state, station, "hangar") do
    if item.type == type then
      Items.Take(state, item, 1000)
    end
  end
  stepUntil(game, "MoonDrilled", 3700)
  t.eq(stored(), Moons.SILO - 1000 + hourly)
  -- A storage array is room for more.
  anchor(t, game, "array.storage")
  t.eq(assert(Core.Query.Starbase(game, station)).drilling.room, Moons.SILO + Moons.STORAGE)
  -- A dark tower drills nothing, and when it is lit again the hour begins again: nothing is owed for the dark.
  local before = stored()
  state.starbases[station].fuel = 0
  steps(game, 3 * 3600)
  t.eq(stored(), before)
  t.eq(assert(Core.Query.Starbase(game, station)).next, 0)
  order(t, game, { kind = "Fuel", actor = 0, item = carry(game, FUEL, 500).id })
  steps(game, 3500)
  t.eq(stored(), before, "an hour had not gone by since the tower was lit")
  steps(game, 200)
  t.eq(stored(), before + hourly)
  -- A save from before towers drilled opens, and its tower begins from now.
  local file = Codec.Decode(Core.Save(game))
  file.saveVersion = 51
  file.state.starbases[station].drilled = nil
  local old, oldLength = Codec.Encode(file)
  local opened = Core.Load(old, oldLength)
  t.eq(opened.state.starbases[station].drilled, opened.state.tick)
end)

suite:Case("a tower keeps count of its running: the fuel it has burnt and what its drill has brought up, priced, and what a day of it costs and brings", function(t)
  local game, station = moored(t, 1000, true)
  local state = game.state
  local starbase = state.starbases[station]
  local deposit = assert(Starbases.Deposit(state, Starbases.Moon(state, starbase)))
  local hourly, price = Moons.PerHour(deposit), deposit.material.basePrice
  -- Lit, with no drill: it burns, and brings up nothing.
  local running = Starbases.Running(state, starbase)
  t.eq({ running.material, running.fuelADay, running.yieldADay } :: { any },
    { deposit.material.id, SMALL.fuel * 24 * Structures.FUEL.basePrice, 0 } :: { any })
  local used = starbase.used
  steps(game, 3600 * 3)
  t.eq({ starbase.used - used, starbase.raised, starbase.robbed }, { SMALL.fuel * 3, 0, 0 })
  -- With the drill online: a day of it is twenty-four hours' worth, and each hour is counted.
  anchor(t, game, Structures.DRILL)
  t.eq(Starbases.Running(state, starbase).yieldADay, hourly * 24 * price)
  steps(game, 3600 * 2 + 5)
  running = Starbases.Running(state, starbase)
  t.eq({ running.raised, running.raisedWorth }, { hourly * 2, hourly * 2 * price })
  t.eq({ running.used, running.usedWorth }, { starbase.used, starbase.used * Structures.FUEL.basePrice })
  t.eq(assert(Core.Query.Starbase(game, station)).running, running)
  -- Dark, a day of it is nothing either way: and the count stays.
  starbase.fuel = 0
  for _, item in Core.Query.Items(game, station, "hangar") do
    if item.type == FUEL then
      Items.Take(state, item, item.quantity)
    end
  end
  steps(game, 2)
  local dark = Starbases.Running(state, starbase)
  t.eq({ dark.fuelADay, dark.yieldADay, dark.raised }, { 0, 0, hourly * 2 })
  -- It is in the save; and a save from before towers kept count opens with the count begun.
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq({ Core.Hash(loaded), loaded.state.starbases[station].raised } :: { any }, { Core.Hash(game), hourly * 2 } :: { any })
  local file = Codec.Decode(data, length)
  file.saveVersion = 58
  file.state.corporation.books = nil
  for _, each in file.state.starbases do
    each.used, each.raised, each.robbed = nil, nil, nil
  end
  local old, oldLength = Codec.Encode(file)
  local before = Core.Load(old, oldLength).state
  t.eq({ before.starbases[station].used, before.starbases[station].raised, before.starbases[station].robbed }, { 0, 0, 0 })
  t.eq(before.corporation.books, {})
end)

suite:Case("a moon with nothing under it takes no drill", function(t)
  local game, station = moored(t, 500, false)
  t.eq(assert(Core.Query.Starbase(game, station)).drilling.deposit, nil)
  t.eq(refused(game, { kind = "AnchorModule", actor = 0, item = carry(game, "array.drill", 1).id }), "this moon has nothing worth a drill")
end)

suite:Case("a tower that has burnt its last feeds itself from the fuel in its hangar, a day's worth at a time, and is not dark for it", function(t)
  local game, station = moored(t, 3)
  local state = game.state
  local starbase = state.starbases[station]
  -- Three blocks in the tank, and five hundred in the hangar: when the three are burnt it takes a day's worth, and stays lit.
  Items.Add(state, FUEL, 500, station, "hangar")
  local dark, fed = false, 0
  for _ = 1, 3 * 360 + 10 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      dark = dark or event.kind == "StarbaseDark"
      if event.kind == "StarbaseFuelled" and event.hangar then
        fed += event.fuel
      end
    end
  end
  local day = SMALL.fuel * 24
  t.eq({ dark, fed } :: { any }, { false, day } :: { any })
  t.ok(Starbases.Lit(state, starbase), "the tower should have stayed lit")
  local left = 0
  for _, item in Items.In(state, station, "hangar") do
    left += if item.type == FUEL then item.quantity else 0
  end
  t.eq(left, 500 - day)
  t.ok(starbase.fuel > day - 3 and starbase.fuel <= day)
  -- A dark tower with fuel put in its hangar lights itself; one with none stays dark.
  starbase.fuel = 0
  for _, item in Items.In(state, station, "hangar") do
    if item.type == FUEL then
      Items.Take(state, item, item.quantity)
    end
  end
  steps(game, 5)
  t.ok(not Starbases.Lit(state, starbase))
  Items.Add(state, FUEL, 40, station, "hangar")
  steps(game, 2)
  t.ok(Starbases.Lit(state, starbase), "fuel in the hangar should light a dark tower")
  t.eq(starbase.fuel, 40)
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

suite:Case("a tower is taken down by the one ship moored at it, with nothing on it and nothing in it, into that ship's hold; and the moon is free again", function(t)
  -- A pilot with a hired hand, a tower lit at a moon with a module on it, moored there.
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local home = state.player.home
  state.skills.leadership = 1
  state.wallet = 10000000
  order(t, game, { kind = "HirePilot", actor = 0, what = Core.Query.Candidates(game, home)[1].key })
  Core.Step(game)
  local wing = state.fleet[state.fleetIds[1]]
  local tower = carry(game, SMALL.id, 1)
  order(t, game, { kind = "Undock", actor = 0 })
  Core.Step(game)
  local moon = aMoon(game, nil)
  order(t, game, { kind = "WarpTo", actor = 0, target = moon.id })
  stepUntil(game, "WarpEnded", 600)
  order(t, game, { kind = "AnchorTower", actor = 0, item = tower.id, target = moon.id })
  local station = stepUntil(game, "StarbaseAnchored", 3).station :: number
  steps(game, SMALL.anchor)
  order(t, game, { kind = "Dock", actor = 0, target = station })
  stepUntil(game, "Docked", 120)
  order(t, game, { kind = "Fuel", actor = 0, item = carry(game, FUEL, 100).id })
  Core.Step(game)
  anchor(t, game, "array.storage")
  local starbase = state.starbases[station]
  -- (the hired pilot is set to carry from the tower to the home station: by hand, they having no ship)
  wing.order, wing.base, wing.post, wing.stops = "haul", home, station, { station }
  t.eq({ Starbases.Kept(state, "player") }, { 1, 1 })

  -- Not with a module on it, nor with anything in its hangars.
  local down: State.Command = { kind = "UnanchorTower", actor = 0 }
  t.eq(refused(game, down), "unanchor its modules first")
  order(t, game, { kind = "UnanchorModule", actor = 0, type = "array.storage" })
  Core.Step(game)
  t.eq(refused(game, down), "its hangars are not empty")
  for _, item in Items.Stored(state, station) do
    Items.Take(state, item, item.quantity)
  end
  -- Not into a hold too small for it.
  t.eq(refused(game, down), string.format("the tower wants %d m3 of hold, and this ship has %d free", SMALL.volume,
    math.floor(Items.ShipStats(state, state.player.ship).cargo - Items.CargoUsed(state, state.player.ship))))
  -- A hauler has the room: but not while another ship of the pilot's is moored there.
  local courier = state.player.ship
  -- (stepped into by hand: a tower with no maintenance array lets nobody change ships at it)
  local mule = Space.NewShip(state, "industrial.hauler", "Mule", "player", station)
  state.player.ship = mule.id
  t.eq(refused(game, down), "another ship is moored here")
  state.ships[courier].docked = home
  -- Not out in space, either.
  t.eq(refused(game, down), "(accepted)")

  -- Down it comes: the tower and what fuel was in its tank are in the hold, and the ship is in space where it was.
  local fuel = starbase.fuel
  t.ok(fuel > 0)
  Core.TakeEvents(game)
  order(t, game, down)
  local said = stepUntil(game, "TowerUnanchored", 2)
  t.eq({ said.station, said.tower, said.fuel, said.left } :: { any }, { station, SMALL.id, fuel, 0 } :: { any })
  t.eq({ assert(hold(game, SMALL.id)).quantity, assert(hold(game, FUEL)).quantity }, { 1, fuel })
  local me = state.balls[mule.id]
  t.ok(me ~= nil and state.ships[mule.id].docked == 0, "the ship should be out in space")
  t.ok(me.grid ~= station, "the ship is on the grid of a tower that is not there")
  -- Nothing is left of it: no starbase, no station, nothing on the overview, and the pilot keeps none.
  t.eq({ state.starbases[station], #state.starbaseIds } :: { any }, { nil, 0 } :: { any })
  t.eq({ Starbases.Kept(state, "player") }, { 0, 1 })
  local was = assert(Space.Object(state, station))
  t.eq({ was.kind, was.site, was.parent } :: { any }, { "gone", 0, 0 } :: { any })
  t.ok(not Stations.Has(state, station, "refining"))
  for _, entry in Core.Query.Overview(game) do
    t.ok(entry.id ~= station, "the tower is still on the overview")
  end
  t.eq(refused(game, { kind = "Dock", actor = 0, target = station }), "not a station")
  -- The hired pilot who carried from it waits, with nowhere there to go.
  t.eq({ wing.order, wing.base, wing.post, #wing.stops } :: { any }, { "stay", home, 0, 0 } :: { any })
  -- It is all in the save.
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.eq(assert(Space.Object(loaded.state, station)).kind, "gone")
  steps(game, 50)
  steps(loaded, 50)
  t.eq(Core.Hash(loaded), Core.Hash(game))

  -- And the moon takes a tower again: the same one, put up anew.
  order(t, game, { kind = "Stop", actor = 0 })
  steps(game, 20)
  order(t, game, { kind = "AnchorTower", actor = 0, item = assert(hold(game, SMALL.id)).id, target = moon.id })
  local again = stepUntil(game, "StarbaseAnchored", 3).station :: number
  t.ok(again ~= station, "the new tower has the id of the one taken down")
  t.eq({ #state.starbaseIds, assert(Space.Object(state, again)).kind } :: { any }, { 1, "station" } :: { any })
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

suite:Case("a composite is made of the two moon materials of its grade, and is worth a quarter more than they are", function(t)
  t.eq(#Reactions.composites, 3)
  for grade, composite in Reactions.composites do
    t.eq({ composite.grade, #composite.from }, { grade, 2 })
    local worth = 0
    for _, from in composite.from do
      t.eq(Moons.byId[from].grade, grade, `{from} in {composite.id}`)
      t.eq(Reactions.Of(from), composite)
      worth += Moons.byId[from].basePrice
    end
    t.eq(composite.basePrice, math.floor(worth * (1 + Reactions.MARGIN) + 0.5))
    t.eq(Reactions.For(grade), composite)
    -- (kept and traded with what it is made of)
    local info = Types.Info(composite.id)
    t.eq({ info.name, info.category, info.basePrice } :: { any }, { composite.name, "moon", composite.basePrice } :: { any })
  end
  t.eq(Reactions.Of("ore.ferrite"), nil)
end)

suite:Case("a tower with a reactor online makes a composite of what it is given, a batch an hour, out of its hangars and into them", function(t)
  local game, station = moored(t, 1000)
  local state = game.state
  local starbase = state.starbases[station]
  local glass = Reactions.byId["composite.saltglass"]
  local function has(type: string): number
    local units = 0
    for _, item in Items.Stored(state, station) do
      units += if item.type == type then item.quantity else 0
    end
    return units
  end
  local function give(type: string, units: number)
    Items.Add(state, type, units, station, "hangar")
  end
  -- (so many ticks: how often it said it stood idle in them)
  local function idled(count: number): number
    local said = 0
    for _ = 1, count do
      Core.Step(game)
      for _, event in Core.TakeEvents(game) do
        said += if event.kind == "ReactorIdle" then 1 else 0
      end
    end
    return said
  end
  -- With no reactor there is nothing to set.
  t.eq(refused(game, { kind = "SetReaction", actor = 0, type = glass.id }), "no reactor is anchored here")
  local status = assert(Core.Query.Starbase(game, station))
  t.eq({ status.reacting.anchored, status.reacting.online, status.reacting.making, status.reacts } :: { any }, { false, false, nil, 0 } :: { any })
  -- One is anchored: one, and no second. It makes nothing until it is told what.
  anchor(t, game, "array.reactor")
  t.eq(refused(game, { kind = "AnchorModule", actor = 0, item = carry(game, "array.reactor", 1).id }), "the tower has a reactor already")
  t.eq(refused(game, { kind = "SetReaction", actor = 0, type = "composite.nothing" }), "a reactor makes no such thing")
  t.eq(refused(game, { kind = "SetReaction", actor = 0, type = "" }), "the reactor is making nothing")
  give(glass.from[1], 250)
  give(glass.from[2], 250)
  t.eq(idled(3700), 0)
  t.eq(has(glass.id), 0)
  -- Told, with both things to hand: a batch an hour, of a batch of each.
  for _, item in Items.Stored(state, station) do
    if item.type == glass.from[2] then
      Items.Take(state, item, item.quantity)
    end
  end
  order(t, game, { kind = "SetReaction", actor = 0, type = glass.id })
  Core.Step(game)
  t.eq(refused(game, { kind = "SetReaction", actor = 0, type = glass.id }), "the reactor is making that already")
  status = assert(Core.Query.Starbase(game, station))
  t.eq({ status.reacting.online, status.reacting.making, status.reacting.have[1], status.reacting.have[2] } :: { any },
    { true, glass, 250, 0 } :: { any })
  t.ok(status.reacts > 3500 and status.reacts <= 3600, `the first hour should be nearly all to come, not {status.reacts} s`)
  -- With only one of the two it stands idle, and says so the once.
  local idle = stepUntil(game, "ReactorIdle", 3700)
  t.eq({ idle.station, idle.type, idle.want } :: { any }, { station, glass.id, glass.from[2] } :: { any })
  t.eq(idled(2 * 3600), 0)
  t.eq({ has(glass.id), starbase.starved } :: { any }, { 0, true } :: { any })
  -- The other comes, and it goes to work at its next hour.
  give(glass.from[2], 250)
  local made = stepUntil(game, "Reacted", 3700)
  t.eq({ made.station, made.type, made.units } :: { any }, { station, glass.id, Reactions.BATCH } :: { any })
  t.eq({ has(glass.from[1]), has(glass.from[2]), has(glass.id), starbase.starved } :: { any }, { 150, 150, 100, false } :: { any })
  -- It is in the save, part of the way through an hour.
  steps(game, 1000)
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  steps(game, 2600)
  steps(loaded, 2600)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.eq({ has(glass.from[1]), has(glass.from[2]), has(glass.id), starbase.composed }, { 50, 50, 200, 200 })
  -- Too little left for a third: idle again, and said again.
  t.eq(idled(3700), 1)
  t.eq(has(glass.id), 200)
  -- A dark tower makes nothing, and lit again its hour begins again: nothing is owed for the dark.
  give(glass.from[1], 100)
  give(glass.from[2], 100)
  starbase.fuel = 0
  steps(game, 2 * 3600 + 10)
  t.eq(has(glass.id), 200)
  order(t, game, { kind = "Fuel", actor = 0, item = carry(game, FUEL, 500).id })
  steps(game, 3500)
  t.eq(has(glass.id), 200)
  steps(game, 200)
  t.eq(has(glass.id), 300)
  -- Told to make nothing, it stops; and one taken down is making nothing when it goes up again.
  give(glass.from[1], 300)
  give(glass.from[2], 300)
  order(t, game, { kind = "SetReaction", actor = 0, type = "" })
  steps(game, 3700)
  t.eq(has(glass.id), 300)
  order(t, game, { kind = "SetReaction", actor = 0, type = glass.id })
  Core.Step(game)
  order(t, game, { kind = "UnanchorModule", actor = 0, type = "array.reactor" })
  Core.Step(game)
  t.eq(starbase.reaction, "")
  steps(game, 3700)
  t.eq(has(glass.id), 300)
  -- A tower of a save from before there were reactors is making nothing.
  local file = Codec.Decode(Core.Save(game))
  file.saveVersion = 63
  for _, tower in file.state.starbases do
    tower.reaction, tower.reacted, tower.composed, tower.starved = nil, nil, nil, nil
  end
  local old, oldLength = Codec.Encode(file)
  local opened = Core.Load(old, oldLength)
  local was = opened.state.starbases[station]
  t.eq({ was.reaction, was.composed, was.starved } :: { any }, { "", 0, false } :: { any })
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

-- Citadels (the owner's B2, 2026-11-17): a station docked inside, of
-- the same machinery as a tower.
-- (a research station: the kind whose bonus none of these cases turns on)
local CITADEL = Structures.towerById["citadel.research.small"]

-- A peaceful game with a small citadel anchored at a planet (or a moon)
-- and the ship docked in it, fuelled: the game and the station.
-- ('tower': another citadel than CITADEL, by its id.)
local function inCitadel(t: Test.Context, at: string?, tower: string?): (Core.Game, number)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local citadel = carry(game, tower or CITADEL.id, 1)
  order(t, game, { kind = "Undock", actor = 0 })
  Core.Step(game)
  local body: System.Object? = nil
  for _, object in Core.Query.Objects(game, 1) do
    if object.kind == (at or "planet") and body == nil
      and Core.Validate(game, { kind = "WarpTo", actor = game.state.player.ship, target = object.id }) then
      body = object
    end
  end
  local there = assert(body, "nothing to warp to")
  order(t, game, { kind = "WarpTo", actor = 0, target = there.id })
  stepUntil(game, "WarpEnded", 600)
  order(t, game, { kind = "AnchorTower", actor = 0, item = citadel.id, target = there.id })
  local station = stepUntil(game, "StarbaseAnchored", 3).station :: number
  -- (hours of anchoring, not waited out tick by tick)
  game.state.starbases[station].ready = game.state.tick
  Core.Step(game)
  order(t, game, { kind = "Dock", actor = 0, target = station })
  stepUntil(game, "Docked", 120)
  order(t, game, { kind = "Fuel", actor = 0, item = carry(game, FUEL, 2000).id })
  Core.Step(game)
  return game, station
end

suite:Case("a citadel is anchored at a planet or a moon, is not one of the towers a pilot keeps, and is a station called so", function(t)
  local game, station = inCitadel(t)
  local object = assert(Space.Object(game.state, station))
  t.eq({ object.variety, string.sub(object.name, -9) } :: { any }, { "citadel", "- Citadel" } :: { any })
  t.eq((Starbases.Kept(game.state, "player")), 0)
  t.ok(Starbases.Citadel(game.state.starbases[station]))
  -- (a moon takes one too)
  local again = inCitadel(t, "moon")
  t.ok(again.state.starbases ~= nil)
  -- (and it is built from a print, of moon materials from the large size up)
  local small, large = assert(Blueprints.byProduct["citadel.research.small"]), assert(Blueprints.byProduct["citadel.research.large"])
  local function moon(print: Blueprints.Blueprint): boolean
    for _, material in print.materials do
      if Types.Info(material.type).category == "moon" then
        return true
      end
    end
    return false
  end
  t.eq({ moon(small), moon(large) }, { false, true })
end)

suite:Case("a citadel has services fitted by the slot, and batteries by theirs, and burns fuel for each service online", function(t)
  local game, station = inCitadel(t)
  local starbase = game.state.starbases[station]
  t.eq(refused(game, { kind = "AnchorModule", actor = 0, item = carry(game, "array.refining", 1).id }),
    "a citadel has services fitted, not a tower's modules")
  local before = Starbases.Burn(game.state, starbase)
  t.eq(before, CITADEL.fuel)
  order(t, game, { kind = "AnchorModule", actor = 0, item = carry(game, "service.refinery", 1).id })
  Core.Step(game)
  t.eq(refused(game, { kind = "AnchorModule", actor = 0, item = carry(game, "service.refinery", 1).id }), "it has a Refinery already")
  order(t, game, { kind = "AnchorModule", actor = 0, item = carry(game, "service.clone", 1).id })
  Core.Step(game)
  t.eq(refused(game, { kind = "AnchorModule", actor = 0, item = carry(game, "service.market", 1).id }), "its 2 service slots are full")
  -- (the batteries have slots of their own)
  order(t, game, { kind = "AnchorModule", actor = 0, item = carry(game, "battery.gun", 1).id })
  Core.Step(game)
  steps(game, Structures.moduleById["service.refinery"].anchor)
  t.ok(Stations.Has(game.state, station, "refining"))
  t.eq(Starbases.Burn(game.state, starbase), CITADEL.fuel + 8 + 5)
  -- (a tower takes no service of a citadel's)
  t.eq(Starbases.Slots(starbase), 2)
end)

suite:Case("a citadel with a clone bay online is a place to wake; it is closed to others until its owner opens it, with a tax", function(t)
  local game, station = inCitadel(t)
  t.eq(refused(game, { kind = "SetHome", actor = 0 }), "this citadel has no clone bay online")
  order(t, game, { kind = "AnchorModule", actor = 0, item = carry(game, "service.clone", 1).id })
  steps(game, Structures.moduleById["service.clone"].anchor + 1)
  game.state.wallet += 1000000
  order(t, game, { kind = "SetHome", actor = 0 })
  Core.Step(game)
  t.eq(game.state.player.home, station)
  -- (whoever else comes: closed, then open)
  local other = Space.NewShip(game.state, "frigate.akashi", "A trader", "vessari", 0)
  local dock: State.Command = { kind = "Dock", actor = other.id, target = station }
  t.eq({ Stations.Validate(game.state, dock) } :: { any }, { false, "this citadel is closed to you" } :: { any })
  t.eq(refused(game, { kind = "SetAccess", actor = 0, open = true, tax = 0.5 }), "the tax is from 0 to 15%")
  order(t, game, { kind = "SetAccess", actor = 0, open = true, tax = 0.05 })
  Core.Step(game)
  t.eq({ game.state.starbases[station].open, game.state.starbases[station].tax } :: { any }, { true, 0.05 } :: { any })
  t.ok((Stations.Validate(game.state, dock)))
  -- (and a save keeps it)
  local data, length = Core.Save(game)
  t.eq(Core.Hash(Core.Load(data, length)), Core.Hash(game))
end)

suite:Case("what docks at a citadel goes by its size; what is too big tethers or cannot, and a friendly ship in its field is tethered", function(t)
  -- (the owner's table: the highest of each that docks, and that tethers)
  local function berths(class: string): { string }
    local out: { string } = {}
    for size = 1, 5 do
      table.insert(out, Structures.Berth(Structures.towerById[`citadel.research.{Structures.CITADEL_SIZES[size]}`], class))
    end
    return out
  end
  t.eq(berths("cruiser"), { "dock", "dock", "dock", "dock", "dock" })
  t.eq(berths("battleship"), { "tether", "dock", "dock", "dock", "dock" })
  t.eq(berths("freighter"), { "none", "tether", "dock", "dock", "dock" })
  t.eq(berths("supercarrier"), { "none", "none", "tether", "dock", "dock" })
  t.eq(berths("ultracapital"), { "none", "none", "tether", "tether", "dock" })
  t.eq(Structures.Berth(SMALL, "ultracapital"), "dock")
  -- (in the game: a battleship is refused at a small citadel's door)
  local game, station = inCitadel(t)
  local big = Space.NewShip(game.state, "battleship.owari", "A battleship", "player", 0)
  t.eq({ Stations.Validate(game.state, { kind = "Dock", actor = big.id, target = station }) } :: { any },
    { false, "too big to dock here: it tethers, inside the field" } :: { any })
  -- (and the pilot's own ship, undocked inside the field, is tethered: nobody locks it)
  order(t, game, { kind = "Undock", actor = 0 })
  stepUntil(game, "Tethered", 30)
  local ship = game.state.ships[game.state.player.ship]
  t.eq(ship.tether, station)
  local object = assert(Space.Object(game.state, station))
  local pirate = Space.NewShip(game.state, "frigate.akashi", "A pirate", "pirates", 0)
  local ball = Space.Launch(game.state, pirate, Space.SystemOf(game.state, station), object.x + 500, object.y, object.z)
  Space.AssignGrid(game.state, ball)
  t.eq({ Core.Validate(game, { kind = "LockTarget", actor = pirate.id, target = ship.id }) } :: { any },
    { false, "it is tethered to a citadel" } :: { any })
  -- (it mends there, with a repair bay online)
  local vitals = game.state.balls[ship.id].vitals
  vitals.armor = vitals.armorMax * 0.5
  game.state.ships[ship.id].tether = nil
  order(t, game, { kind = "Dock", actor = 0, target = station })
  stepUntil(game, "Docked", 120)
  order(t, game, { kind = "AnchorModule", actor = 0, item = carry(game, "service.repair", 1).id })
  steps(game, Structures.moduleById["service.repair"].anchor + 1)
  order(t, game, { kind = "Undock", actor = 0 })
  stepUntil(game, "Tethered", 30)
  local mended = game.state.balls[ship.id].vitals
  mended.armor = mended.armorMax * 0.5
  steps(game, 10)
  t.ok(mended.armor > mended.armorMax * 0.6, "a tethered ship was not mended")
end)

suite:Case("each kind of citadel is a citadel of its own, with its own print: it does its own work better, and fits what only it may", function(t)
  -- Five kinds at five sizes, each with its name and its print.
  for _, kind in Structures.CITADEL_KINDS do
    for size, word in Structures.CITADEL_SIZES do
      local tower = assert(Structures.towerById[`citadel.{kind}.{word}`], `no {word} {kind}`)
      t.eq({ tower.kind, tower.size, tower.name } :: { any },
        { kind, size, `{Structures.CITADEL_SIZE_NAMES[size]} {Structures.CITADEL_KIND_NAMES[kind]}` } :: { any })
      t.ok(Blueprints.byProduct[tower.id] ~= nil, `no print for {tower.id}`)
    end
  end
  t.eq({ Structures.towerById["citadel.small"], Structures.CitadelNow("blueprint.citadel.large"), Structures.CitadelNow("citadel.shipyard.small") } :: { any },
    { nil, "blueprint.citadel.habitation.large", nil } :: { any })
  -- A small shipyard fits an Advanced Ship Assembly, and not a Capital Ship Assembly (large and up); nor does a
  -- research station fit either.
  local game, station = inCitadel(t, nil, "citadel.shipyard.small")
  local state = game.state
  t.eq(refused(game, { kind = "AnchorModule", actor = 0, item = carry(game, "service.assembly.capital", 1).id }),
    "a Capital Ship Assembly is fitted only in a large citadel or bigger")
  t.eq(CitadelKinds.Of(state, station), "shipyard")
  -- (with a manufacturing plant in it, a capital is still not built there; nor a tech 2 hull)
  order(t, game, { kind = "AnchorModule", actor = 0, item = carry(game, "service.manufacturing", 1).id })
  Core.Step(game)
  for _, module in state.starbases[station].modules do
    module.ready = state.tick
  end
  Core.Step(game)
  state.skills.industry = 5
  local capital = assert(Blueprints.byProduct["carrier.azayake"])
  t.eq(refused(game, { kind = "StartJob", actor = 0, item = Items.Add(state, capital.id, 1, station, "hangar").id, quantity = 1 }),
    "a capital is built here only with a Capital Ship Assembly")
  local advanced = assert(Blueprints.byProduct["destroyer.kanau"])
  t.eq(refused(game, { kind = "StartJob", actor = 0, item = Items.Add(state, advanced.id, 1, station, "hangar").id, quantity = 1 }),
    "a tech 2 hull is built here only with an Advanced Ship Assembly")
  -- What it does better: a job here takes three quarters of the time, of nine tenths of the materials.
  local frigate = assert(Blueprints.byProduct["frigate.akashi"])
  local here, there = Industry.Plan(state, station, frigate, 1), Industry.Plan(state, state.player.home, frigate, 1)
  t.ok(here.seconds < there.seconds * 0.8, `{here.seconds} s here and {there.seconds} s at home`)
  t.ok(here.materials[1].need < there.materials[1].need, "no fewer materials here")
  local other = inCitadel(t, nil, "citadel.research.medium")
  t.eq(refused(other, { kind = "AnchorModule", actor = 0, item = carry(other, "service.assembly.advanced", 1).id }),
    "only a shipyard citadel fits an Advanced Ship Assembly")
  -- A trade hub halves the tax; a habitation has a clone bay and storage with nothing fitted, and burns less.
  local hub, hubAt = inCitadel(t, nil, "citadel.tradehub.small")
  t.near(Market.Tax(hub.state, hubAt), Market.Tax(hub.state, nil) * 0.5, 1e-9)
  local home, homeAt = inCitadel(t, nil, "citadel.habitation.small")
  local citadel = home.state.starbases[homeAt]
  t.eq({ Starbases.Has(home.state, citadel, "quarters"), Starbases.Has(home.state, citadel, "storage"),
    Starbases.Has(home.state, citadel, "industry") } :: { any }, { true, true, false } :: { any })
  t.near(Starbases.Burn(home.state, citadel), Structures.towerById["citadel.habitation.small"].fuel * 0.8, 1e-6)
end)

suite:Case("a ship leaves a citadel by one of its hangar doors, just outside it and coasting out of it", function(t)
  local game, station = inCitadel(t)
  local state = game.state
  local doors = assert(CitadelDoors[CITADEL.kind :: string][CITADEL.size], "no doors for the citadel")
  t.ok(#doors >= 1, "a citadel with no door")
  order(t, game, { kind = "Undock", actor = 0 })
  stepUntil(game, "Undocked", 30)
  local ball = assert(state.balls[state.player.ship], "not in space")
  local object = assert(Space.Object(state, station))
  local door = doors[state.player.ship % #doors + 1]
  local reach = CITADEL.reach :: number
  -- (where it came out: off that door, a little way out of it; and going the way it faces)
  local ax, ay, az = object.x + door[1] * reach, object.y + door[2] * reach, object.z + door[3] * reach
  local off = vector.create(ball.x - ax, ball.y - ay, ball.z - az)
  local outward = vector.create(door[4], door[5], door[6])
  t.ok(vector.dot(off, outward) > 0 and vector.magnitude(off - outward * vector.dot(off, outward)) < 1 + ball.radius,
    `it came out {vector.magnitude(off)} m from the door, not out of it`)
  t.ok(vector.dot(vector.create(ball.vx, ball.vy, ball.vz), outward) > 0, "it is not moving out of the door")
  t.ok(Space.Distance(ball :: any, object :: any) < reach * 1.2, "it came out far from the citadel")
end)

suite:Case("a gravity station is a lit jump beacon of itself; with a Jump Bridge, a ship in its field goes to another's, on the station's fuel", function(t)
  local game, first = inCitadel(t, nil, "citadel.gravity.small")
  local state = game.state
  local ship = state.player.ship
  -- (a beacon lit with nothing fitted: a jump drive may come out at it)
  local lit = false
  for _, beacon in Jumping.Beacons(state, ship) do
    lit = lit or beacon.id == first
  end
  t.ok(lit, "a gravity station is no beacon")
  -- (only a gravity station fits a bridge)
  t.eq(Structures.moduleById["service.bridge"].kinds, { "gravity" })
  -- Fit a bridge, and leave.
  local function bridge(station: number)
    order(t, game, { kind = "AnchorModule", actor = 0, item = carry(game, "service.bridge", 1).id })
    Core.Step(game)
    for _, module in state.starbases[station].modules do
      module.ready = state.tick
    end
    Core.Step(game)
  end
  bridge(first)
  -- A second, in another system within the bridge's reach: the ship is put by a planet there to anchor it.
  local here = Space.SystemOf(state, first)
  local other: System.Object? = nil
  for id in state.galaxy.systems do
    if other == nil and id ~= here and not state.galaxy.systems[id].uncharted and Jumping.Distance(state, here, id) <= Jumping.BRIDGE_RANGE then
      for _, object in Space.Describe(state, id).objects do
        if other == nil and object.kind == "planet" then
          other = object
        end
      end
    end
  end
  local planet = assert(other, "no planet within a bridge's reach")
  local elsewhere = Space.SystemOf(state, planet.id)
  order(t, game, { kind = "Undock", actor = 0 })
  stepUntil(game, "Undocked", 30)
  t.eq(#Jumping.BridgeTo(state, ship), 0, "a bridge with no other bridge goes nowhere")
  t.eq(refused(game, { kind = "Bridge", actor = 0, target = elsewhere }), "no jump bridge there to go to")
  local ball = state.balls[ship]
  ball.system, ball.x, ball.y, ball.z = elsewhere, planet.x + planet.radius + 30000, planet.y, planet.z
  ball.vx, ball.vy, ball.vz = 0, 0, 0
  Space.AssignGrid(state, ball)
  order(t, game, { kind = "AnchorTower", actor = 0, item = carry(game, "citadel.gravity.small", 1).id, target = planet.id })
  local second = stepUntil(game, "StarbaseAnchored", 3).station :: number
  state.starbases[second].ready = state.tick
  Core.Step(game)
  order(t, game, { kind = "Dock", actor = 0, target = second })
  stepUntil(game, "Docked", 300)
  order(t, game, { kind = "Fuel", actor = 0, item = carry(game, FUEL, 2000).id })
  Core.Step(game)
  bridge(second)
  order(t, game, { kind = "Undock", actor = 0 })
  stepUntil(game, "Undocked", 30)
  -- Back to the first, by the bridge: the second pays for it.
  local ways = Jumping.BridgeTo(state, ship)
  t.eq({ #ways, ways[1] and ways[1].station } :: { any }, { 1, first } :: { any })
  local fuel, cost = state.starbases[second].fuel, Jumping.Fuel(state, ship, Jumping.Distance(state, elsewhere, here))
  order(t, game, { kind = "Bridge", actor = 0, target = here })
  Core.Step(game)
  ball = state.balls[ship]
  t.eq(ball.system, here)
  t.ok(Space.Distance(ball :: any, assert(Space.Object(state, first)) :: any) < Structures.towerById["citadel.gravity.small"].field,
    "it came out far from the bridge it went to")
  t.ok(state.starbases[second].fuel <= fuel - cost, "the bridge it left did not pay the fuel")
  -- (never into uncharted space, nor out of it: were the other system
  -- uncharted, there is nowhere to go)
  t.eq(#Jumping.BridgeTo(state, ship), 1)
  state.galaxy.systems[elsewhere].uncharted = true
  t.eq(#Jumping.BridgeTo(state, ship), 0, "a bridge reaches into uncharted space")
  t.eq(refused(game, { kind = "Bridge", actor = 0, target = elsewhere }), "no bridge finds its way in or out of uncharted space")
  state.galaxy.systems[elsewhere].uncharted = nil
  -- (nor from warp, nor out of a bridge's field)
  ball.x += 1e7
  t.eq(refused(game, { kind = "Bridge", actor = 0, target = elsewhere }), "not in the field of a jump bridge")
end)

return suite
