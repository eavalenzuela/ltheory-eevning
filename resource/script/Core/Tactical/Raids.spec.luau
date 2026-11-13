--!strict
-- Pirates raiding a pilot's tower (Tactical/Raids).

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
  local station, starbase = tower(game, "lawless")
  table.insert(starbase.modules, { type = Structures.DRILL, ready = state.tick })
  Items.Add(state, "moon.promethite", 2000, station, "hangar")
  Items.Add(state, "moon.cadmite", 10, station, "hangar")
  Items.Add(state, "ore.ferrite", 500, station, "hangar")
  Core.Step(game)
  t.eq({ Raids.Defence(state, starbase) }, { 0, 0, 0 })
  local raid = raided(game, starbase)
  t.eq({ raid.outcome, raid.defence } :: { any }, { "robbed", 0 } :: { any })
  t.ok(raid.strength >= 4 and raid.strength <= 9, `a lawless raid {raid.strength} strong`)
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
  local station, starbase = tower(game, "lawless")
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
  local station, starbase = tower(game, "lawless")
  local status = assert(Core.Query.Starbase(game, station))
  t.eq({ status.defence, status.raidLeast, status.raidMost }, { 0, 4, 9 })
  -- One battery: a raid still gets in, for a smaller share.
  table.insert(starbase.modules, { type = "battery.gun", ready = state.tick })
  Items.Add(state, "moon.dysprite", 1000, station, "hangar")
  Core.Step(game)
  t.eq({ Raids.Defence(state, starbase) }, { Raids.BATTERY, 1, 0 })
  local raid = raided(game, starbase)
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
      want = "", need = 0, limit = 0, keep = 0, retry = 0 }
    table.insert(state.fleetIds, id)
  end
  guard(901, "destroyer.halberd", "patrol", station)
  t.eq({ Raids.Defence(state, starbase) }, { Raids.PATROL.destroyer, 0, 1 })
  -- (one who is only following, or holds somewhere else, is not holding this place)
  guard(902, "destroyer.halberd", "follow", station)
  guard(903, "destroyer.halberd", "patrol", station + 1)
  t.eq({ Raids.Defence(state, starbase) }, { Raids.PATROL.destroyer, 0, 1 })
  -- A destroyer is worth a battery; with a battery beside it, a raid in low security at its weakest is met.
  table.insert(starbase.modules, { type = "battery.gun", ready = state.tick })
  t.eq((Raids.Defence(state, starbase)), Raids.PATROL.destroyer + Raids.BATTERY)
  t.eq(assert(Core.Query.Starbase(game, station)).patrol, 1)
end)

suite:Case("with the pilot there a raid is a pack that arrives, to be fought, and nothing is carried off", function(t)
  local game = galaxy()
  local state = game.state
  local station, starbase = tower(game, "lawless")
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

return suite
