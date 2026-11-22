--!strict
-- Jump drives (Tactical/Jumping).

local Constants = require("@lt/Core/Data/Constants")
local Attributes = require("@lt/Core/Attributes")
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
  -- (every carrier has one since 2026-11-20, the owner's "Capitals+ yes"; a plain freighter has not)
  t.eq({ Ships.byId["carrier.scoppo"].jump, Ships.byId["carrier.azayake"].jump, Ships.byId["freighter.yoruzake"].jump } :: { any },
    { true, true, nil } :: { any })
  local other = (flying("freighter.yoruzake"))
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
  -- (nobody docks at a tower, 2026-11-22: in its field the ship is in space, and jumps from there)
  t.ok((submit(game, { kind = "Dock", actor = 0, target = lit })))
  for _ = 1, 900 do
    Core.Step(game)
    if state.ships[me.id].moored ~= nil then
      break
    end
  end
  t.eq({ state.ships[me.id].docked, state.ships[me.id].moored } :: { any }, { 0, lit } :: { any })
  t.eq(refused(game, { kind = "JumpDrive", actor = 0, target = home }), "(accepted)")
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

suite:Case("a drive with a field takes every friendly ship within five kilometres with it: not one too far off, in warp, scrambled or somebody else's", function(t)
  -- (the Vail's Archangel has one; the Talmar's jump carrier has a drive and no field)
  local hull = Ships.byId["ultracapital.archangel"]
  t.eq({ hull.jump, hull.jumpField, Ships.byId["carrier.scoppo"].jumpField } :: { any }, { true, 5000, nil } :: { any })
  local plain = (flying("carrier.scoppo"))
  t.eq({ Jumping.Field(plain.state, plain.state.player.ship), assert(Core.Query.JumpDrive(plain)).field }, { 0, 0 })

  local game, me = flying("ultracapital.archangel")
  local state = game.state
  state.skills[Jumping.SKILL] = 1
  local home = me.system
  local to = reach(game, home, Jumping.RANGE * (1 + Jumping.FURTHER))
  local lit = tower(game, to)
  -- A ship beside it: whose it is, how far off between the two hulls, and which way (1 along x, 2 up, 3 along z).
  local function beside(name: string, owner: string, gap: number, way: number): State.Ball
    local ship = Space.NewShip(state, "barge.panacea", name, owner, 0)
    local off = me.radius + Ships.byId[ship.type].radius + gap
    local ball = Space.Launch(state, ship, home, me.x + (if way == 1 then off else 0), me.y + (if way == 2 then off else 0),
      me.z + (if way == 3 then off else 0))
    t.eq(ball.radius, Ships.byId[ship.type].radius)
    return ball
  end
  local near = beside("Near", "player", 1000, 1)
  local member = beside("Member", "member", 4990, 2)
  local far = beside("Far", "player", 5010, 3)
  local stranger = beside("Stranger", "civilian", 500, 1)
  local held = beside("Held", "player", 2000, 3)
  local away = beside("Away", "player", 3000, 2)
  held.vitals.scrambled = true;
  (away :: any).warp = {}
  -- Who a jump would take, in the order of their ids; and what the pilot is told of the drive.
  t.eq(Jumping.Along(state, me.id), { near.id, member.id })
  local status = assert(Core.Query.JumpDrive(game, to))
  t.eq({ status.field, status.along }, { 5000, 2 })
  -- (one that was held is taken once it is let go)
  held.vitals.scrambled = false
  t.eq(Jumping.Along(state, me.id), { near.id, member.id, held.id })
  held.vitals.scrambled = true

  local distance = Jumping.Distance(state, home, to)
  local fuel = Jumping.Fuel(state, me.id, distance)
  Items.Add(state, Structures.FUEL.id, fuel + 10, me.id, "cargo")
  me.vitals.capacitor = me.vitals.capacitorMax
  near.vx, near.mode = 30, "goto"
  local wasNear = { near.x - me.x, near.y - me.y, near.z - me.z }
  local wasMember = { member.x - me.x, member.y - me.y, member.z - me.z }
  local command: State.Command = { kind = "JumpDrive", actor = me.id, target = to }
  t.eq({ Jumping.Validate(state, command) } :: { any }, { true } :: { any })
  local events: { Jumping.Event } = {}
  Jumping.Apply(state, command, events)
  -- The hull went, and the two within its field with it: each as far from it, and the same way off, as it was, at rest.
  t.eq({ me.system, near.system, member.system }, { to, to, to })
  t.near(near.x - me.x, wasNear[1], 1e-6)
  t.near(member.y - me.y, wasMember[2], 1e-6)
  t.eq({ near.vx, near.mode, #near.vitals.running, #near.vitals.locks } :: { any }, { 0, "stop", 0, 0 } :: { any })
  t.ok(near.grid == me.grid and me.grid ~= 0, "what it took is not on its grid")
  -- The others are where they were.
  t.eq({ far.system, stranger.system, held.system, away.system }, { home, home, home, home })
  -- It burned what its own mass takes and no more, and only its own drive is cooling.
  t.eq(Jumping.Held(state, me.id), 10)
  t.eq({ state.ships[me.id].jumped, state.ships[near.id].jumped } :: { any }, { state.tick, nil } :: { any })
  -- What is said of it: a jump for each, the taken ones' saying whose field it was.
  local said: { [number]: any } = {}
  for _, event in events do
    t.eq({ event.kind, event.from, event.to, event.drive, event.arrival } :: { any }, { "Jumped", home, to, true, lit } :: { any })
    said[event.ship] = event
  end
  t.eq(#events, 3)
  t.eq({ said[me.id].took, said[me.id].along, said[near.id].along, said[member.id].along } :: { any }, { 2, nil, me.id, me.id } :: { any })
  for _ = 1, 10 do
    Core.Step(game)
  end
end)

suite:Case("a jump portal is opened by an ultracapital's generator to a lit beacon; friendly ships near it go through on its fuel, but no capital", function(t)
  local game, me = flying("ultracapital.daiichi")
  local state = game.state
  state.skills[Jumping.SKILL] = 4
  local home = me.system
  local to = reach(game, home, Jumping.Range(game.state, me.id))
  tower(game, to)
  Items.Add(state, Structures.FUEL.id, 100000, me.id, "cargo")
  me.vitals.capacitor = me.vitals.capacitorMax
  t.eq(refused(game, { kind = "OpenPortal", actor = 0, target = to }), "no Jump Portal Generator fitted")
  -- (nothing smaller than an ultracapital fits one)
  t.eq((Attributes.Check(Ships.byId["carrier.scoppo"], { "jump.portal" })), false)
  Items.Add(state, "jump.portal", 1, me.id, "cargo").slot = 99
  t.ok((submit(game, { kind = "OpenPortal", actor = 0, target = to })))
  t.eq(me.system, home)
  t.ok(math.abs(Jumping.PortalLeft(state, me.id) - (Jumping.PORTAL_LIFE - 1)) <= 1)
  t.eq(refused(game, { kind = "OpenPortal", actor = 0, target = to }), "a portal is open already")
  -- Ships of the pilot's: one near, one too far off, and a capital near.
  local function ship(hull: string, gap: number): State.Ball
    local made = Space.NewShip(state, hull, "Other", "player", state.player.home)
    local other = Space.Launch(state, made, home, me.x + me.radius + gap, me.y, me.z)
    other.vitals.capacitor = 0
    return other
  end
  local near, far, big = ship("cruiser.ouyou", 1000), ship("cruiser.ouyou", 20000), ship("carrier.scoppo", 2000)
  local function through(ball: State.Ball): string?
    local ok, why = Core.Validate(game, { kind = "JumpPortal", actor = ball.id, target = me.id })
    return if ok then "(accepted)" else why
  end
  t.eq(through(far), "no jump portal open within 5 km")
  t.eq(through(big), "no capital goes through a jump portal")
  local fuel = Jumping.Held(state, me.id)
  t.ok((Core.Submit(game, { kind = "JumpPortal", actor = near.id, target = me.id })))
  Core.Step(game)
  t.eq(near.system, to)
  t.eq(Jumping.Held(state, me.id), fuel - Jumping.Fuel(state, near.id, Jumping.Distance(state, home, to)))
  -- Its life over, it is shut.
  for _ = 1, Jumping.PORTAL_LIFE do
    Core.Step(game)
  end
  t.eq(Jumping.PortalLeft(state, me.id), 0)
  t.eq(through(ship("cruiser.ouyou", 1000)), "no jump portal open within 5 km")
end)

return suite
