--!strict
-- Jump drives (Tactical/Jumping).

local Constants = require("@lt/Core/Data/Constants")
local Core = require("@lt/Core/Api")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Jumping = require("@lt/Core/Tactical/Jumping")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local Starbases = require("@lt/Core/Assets/Starbases")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Jumping")

-- The pilot in a hull, at rest in open space at home, in a galaxy of
-- forty systems.
local function flying(hull: string): (Core.Game, State.Ball)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, systems = 40, peaceful = true })
  local state = game.state
  local mine = Space.NewShip(state, hull, "Tester", "player", state.player.home)
  state.player.ship = mine.id
  local station = assert(Space.Object(state, state.player.home))
  local me = Space.Launch(state, mine, Space.SystemOf(state, state.player.home), station.x + 4e6, station.y, station.z)
  return game, me
end

local function submit(game: Core.Game, command: State.Command): (boolean, string?)
  command.actor = game.state.player.ship
  local ok, why = Core.Submit(game, command)
  Core.Step(game)
  return ok, why
end

local function refused(game: Core.Game, command: State.Command): string?
  command.actor = game.state.player.ship
  local ok, why = Core.Validate(game, command)
  return if ok then "(accepted)" else why
end

-- A tower of the pilot's in a system, lit, with a Jump Beacon anchored
-- and online: the station it is.
local function tower(game: Core.Game, system: number): number
  local state = game.state
  for _, object in Space.Describe(state, system).objects do
    if object.kind == "moon" then
      local id = Starbases.Raise(state, system, object, Structures.towerById["tower.vessari.small"], "player",
        object.x + object.radius * 3, object.y, object.z)
      local starbase = state.starbases[id]
      starbase.ready, starbase.fuel, starbase.burnt = state.tick, 100000, state.tick
      table.insert(starbase.modules, { type = Structures.BEACON, ready = state.tick })
      return id
    end
  end
  error(`system {system} has no moon to put a tower at`)
end

-- The system farthest from another that is within so many light years
-- of it, and the nearest that is not.
local function reach(game: Core.Game, from: number, range: number): (number, number)
  local state = game.state
  local inside, outside = 0, 0
  local most, least = -1, math.huge
  -- (the systems of the map: no drive goes to the others, Tactical/Wormholes)
  for id = 1, Galaxy.Charted(state.galaxy) do
    local far = Jumping.Distance(state, from, id)
    if id ~= from and far <= range and far > most then
      inside, most = id, far
    elseif far > range and far < least then
      outside, least = id, far
    end
  end
  return inside, outside
end

suite:Case("a hull built with a jump drive goes to a system within its reach without a gate, for fuel and most of its capacitor", function(t)
  -- (the Talmar's carrier has one; the Vessari's has not)
  t.eq({ Ships.byId["carrier.scoppo"].jump, Ships.byId["carrier.azayake"].jump } :: { any }, { true, nil } :: { any })
  local other = (flying("carrier.azayake"))
  other.state.skills[Jumping.SKILL] = 5
  t.eq(refused(other, { kind = "JumpDrive", actor = 0, target = 2 }), "this hull has no jump drive")
  t.eq(Core.Query.JumpDrive(other), nil)

  local game, me = flying("carrier.scoppo")
  local state = game.state
  local home = me.system
  local to, beyond = reach(game, home, Jumping.RANGE * (1 + Jumping.FURTHER))
  t.ok(to ~= 0 and beyond ~= 0, "the galaxy should have a system in reach and one out of it")
  -- It takes the skill, and reaches a tenth further for each level of it.
  -- There has to be a beacon lit there: a Jump Beacon online at a lit tower of the pilot's.
  t.eq(refused(game, { kind = "JumpDrive", actor = 0, target = to }), "no beacon is lit there")
  t.eq(#assert(Core.Query.JumpDrive(game, to)).beacons, 0)
  local lit = tower(game, to)
  tower(game, beyond)
  t.eq(refused(game, { kind = "JumpDrive", actor = 0, target = to }), "needs Jump Drive Operation 1")
  state.skills[Jumping.SKILL] = 1
  t.near(Jumping.Range(state, me.id), Jumping.RANGE * 1.1, 1e-9)
  t.ok(string.find(tostring(refused(game, { kind = "JumpDrive", actor = 0, target = beyond })), "out of reach", 1, true) ~= nil)
  t.eq(refused(game, { kind = "JumpDrive", actor = 0, target = home }), "that is the system you are in")
  t.eq(refused(game, { kind = "JumpDrive", actor = 0, target = 99999 }), "no such system")
  -- Fuel blocks out of the hold, so many a light year for the mass of the hull; and most of a full capacitor.
  local distance = Jumping.Distance(state, home, to)
  local fuel = Jumping.Fuel(state, me.id, distance)
  t.eq(fuel, math.ceil(distance * Ships.byId["carrier.scoppo"].mass / Jumping.FUEL_MASS))
  t.eq(refused(game, { kind = "JumpDrive", actor = 0, target = to }), `needs {fuel} fuel blocks in the hold, and there are 0`)
  Items.Add(state, Structures.FUEL.id, fuel + 25, me.id, "cargo")
  me.vitals.capacitor = 0.5 * me.vitals.capacitorMax
  t.eq(refused(game, { kind = "JumpDrive", actor = 0, target = to }), "needs 70% of the capacitor")
  me.vitals.capacitor = me.vitals.capacitorMax
  local status = assert(Core.Query.JumpDrive(game, to))
  t.eq({ status.ready, status.fuel, status.held, status.cooling } :: { any }, { true, fuel, fuel + 25, 0 } :: { any })
  t.near(status.distance, distance, 1e-9)
  -- (and the map says how many gates that saves)
  local gates = #Galaxy.Route(state.galaxy, home, to) - 1
  print(string.format("     jump: %.1f light years, %d gates by the map, %d fuel blocks", distance, gates, fuel))

  -- It jumps: there at once, at rest, a little way off a station, with the fuel burnt and little capacitor left.
  Core.TakeEvents(game)
  t.ok((submit(game, { kind = "JumpDrive", actor = 0, target = to })))
  local jumped: { [string]: any }? = nil
  for _, event in Core.TakeEvents(game) do
    jumped = if event.kind == "Jumped" then event else jumped
  end
  local beacon = assert(Jumping.Beacon(state, me.id, to))
  t.eq({ me.system, assert(jumped).from, assert(jumped).to, assert(jumped).drive, assert(jumped).arrival, beacon.kind, beacon.id } :: { any },
    { to, home, to, true, lit, "tower", lit } :: { any })
  t.ok(Space.Gap(me :: any, beacon :: any) <= Jumping.LAND * 1.2 and me.grid == beacon.id, "it should come out beside the tower")
  t.eq({ Jumping.Held(state, me.id), me.mode } :: { any }, { 25, "stop" } :: { any })
  t.ok(me.vitals.capacitor < 0.1 * me.vitals.capacitorMax)
  t.eq(Core.Query.Player(game).system, to)
  -- (the way home has no beacon: the drive goes nowhere there is none)
  t.eq(refused(game, { kind = "JumpDrive", actor = 0, target = home }), "no beacon is lit there")
  local back = tower(game, home)
  -- The drive cools before it fires again; and it is in the save, cooling.
  me.vitals.capacitor = me.vitals.capacitorMax
  Items.Add(state, Structures.FUEL.id, fuel, me.id, "cargo")
  local cooling = tostring(refused(game, { kind = "JumpDrive", actor = 0, target = home }))
  t.ok(string.find(cooling, "the drive is cooling", 1, true) ~= nil, cooling)
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.ok(Jumping.Cooling(loaded.state, me.id) > 0)
  for _ = 1, math.ceil(Jumping.COOLDOWN / Constants.TICK) + 1 do
    Core.Step(game)
  end
  me.vitals.capacitor = me.vitals.capacitorMax
  t.eq(refused(game, { kind = "JumpDrive", actor = 0, target = home }), "(accepted)")
  -- Not from a warp, with a scrambler on it, or docked.
  me.vitals.scrambled = true
  t.eq(refused(game, { kind = "JumpDrive", actor = 0, target = home }), "warp scrambled")
  me.vitals.scrambled = false
  -- A tower that goes dark, or whose beacon is taken down, lights nobody's way.
  t.eq(refused(game, { kind = "JumpDrive", actor = 0, target = home }), "(accepted)")
  state.starbases[back].fuel = 0
  t.eq(refused(game, { kind = "JumpDrive", actor = 0, target = home }), "no beacon is lit there")
  state.starbases[back].fuel = 1000
  table.clear(state.starbases[back].modules)
  t.eq(refused(game, { kind = "JumpDrive", actor = 0, target = home }), "no beacon is lit there")
  table.insert(state.starbases[back].modules, { type = Structures.BEACON, ready = state.tick })
  t.ok((submit(game, { kind = "Dock", actor = 0, target = lit })))
  for _ = 1, 900 do
    Core.Step(game)
    if state.ships[me.id].docked ~= 0 then
      break
    end
  end
  t.eq(refused(game, { kind = "JumpDrive", actor = 0, target = home }), "docked")
end)

suite:Case("a ship of the pilot's fleet with a beacon generator running lights the way to where it is, and the jump comes out beside it", function(t)
  local game, me = flying("carrier.scoppo")
  local state = game.state
  local home = me.system
  state.skills[Jumping.SKILL] = 1
  local to = (reach(game, home, Jumping.RANGE))
  Items.Add(state, Structures.FUEL.id, 2000, me.id, "cargo")
  -- A ship of the pilot's out in space there, with a generator fitted and not running: no beacon.
  local scout = Space.NewShip(state, "frigate.akashi", "Scout", "player", 0)
  local generator = Items.Equip(state, scout.id, "beacon.jump", nil)
  local far = assert(Space.Describe(state, to).objects[1])
  local there = Space.Launch(state, scout, to, far.x + far.radius + 5e6, far.y, far.z)
  t.eq(refused(game, { kind = "JumpDrive", actor = 0, target = to }), "no beacon is lit there")
  -- Running, it is one: the map has it, a ship's, within the drive's reach.
  t.ok((Core.Submit(game, { kind = "ActivateModule", actor = scout.id, item = generator.id })))
  Core.Step(game)
  local status = assert(Core.Query.JumpDrive(game, to))
  t.eq({ #status.beacons, status.beacons[1].system, status.beacons[1].kind, status.beacons[1].reached, status.ready } :: { any },
    { 1, to, "ship", true, true } :: { any })
  t.ok((submit(game, { kind = "JumpDrive", actor = 0, target = to })))
  t.eq({ me.system, me.grid == there.grid } :: { any }, { to, true } :: { any })
  t.ok(Space.Gap(me :: any, there :: any) <= Jumping.LAND * 1.2, "it should come out beside the ship that lit the way")
  -- Its own beacon is nobody's way to itself, and one switched off is none.
  t.eq(#Jumping.Beacons(state, scout.id), 0)
  t.ok((Core.Submit(game, { kind = "DeactivateModule", actor = scout.id, item = generator.id })))
  for _ = 1, 15 do
    Core.Step(game)
  end
  t.eq(#Jumping.Beacons(state, me.id), 0)
end)

return suite
