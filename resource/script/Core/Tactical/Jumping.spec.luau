--!strict
-- Jump drives (Tactical/Jumping).

local Constants = require("@lt/Core/Data/Constants")
local Core = require("@lt/Core/Api")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Jumping = require("@lt/Core/Tactical/Jumping")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
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

-- The system farthest from another that is within so many light years
-- of it, and the nearest that is not.
local function reach(game: Core.Game, from: number, range: number): (number, number)
  local state = game.state
  local inside, outside = 0, 0
  local most, least = -1, math.huge
  for id in state.galaxy.systems do
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
  local beacon = assert(Jumping.Beacon(state, to))
  t.eq({ me.system, assert(jumped).from, assert(jumped).to, assert(jumped).drive, assert(jumped).arrival } :: { any },
    { to, home, to, true, beacon.id } :: { any })
  t.ok(Space.Gap(me :: any, beacon :: any) <= Jumping.LAND * 1.2 and me.grid == beacon.id, "it should come out beside the station")
  t.eq({ Jumping.Held(state, me.id), me.mode } :: { any }, { 25, "stop" } :: { any })
  t.ok(me.vitals.capacitor < 0.1 * me.vitals.capacitorMax)
  t.eq(Core.Query.Player(game).system, to)
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
  t.ok((submit(game, { kind = "Dock", actor = 0, target = beacon.id })))
  for _ = 1, 600 do
    Core.Step(game)
    if state.ships[me.id].docked ~= 0 then
      break
    end
  end
  t.eq(refused(game, { kind = "JumpDrive", actor = 0, target = home }), "docked")
end)

return suite
