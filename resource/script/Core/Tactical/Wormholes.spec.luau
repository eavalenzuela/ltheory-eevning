--!strict
-- Uncharted space and the wormholes into it (Describe/Galaxy,
-- Tactical/Wormholes).

local Codec = require("@lt/Core/Persist/Codec")
local Constants = require("@lt/Core/Data/Constants")
local Structures = require("@lt/Core/Data/Structures")
local Core = require("@lt/Core/Api")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Jumping = require("@lt/Core/Tactical/Jumping")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local Sites = require("@lt/Core/Tactical/Sites")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")
local Test = require("@lt/Tool/Test")
local Wormholes = require("@lt/Core/Tactical/Wormholes")

local suite = Test.Suite("Wormholes")

local SYSTEMS = 40

-- A game of forty systems (and forty more that are on no map), with the
-- pilot's ship in space at home, at rest. 'peaceful' unless said.
local function inSpace(historySeed: number?, pirates: boolean?): Core.Game
  local game = Core.New({ galaxySeed = 1, historySeed = historySeed or 1, systems = SYSTEMS, peaceful = not pirates })
  assert(Core.Submit(game, { kind = "Undock", actor = game.state.player.ship }))
  Core.Step(game)
  assert(Core.Submit(game, { kind = "Stop", actor = game.state.player.ship }))
  Core.Step(game)
  Core.TakeEvents(game)
  return game
end

local function steps(game: Core.Game, count: number)
  for _ = 1, count do
    Core.Step(game)
  end
end

-- Put the pilot's ship somewhere in a system, at rest.
local function put(game: Core.Game, system: number, x: number, y: number, z: number)
  local state = game.state
  local ball = state.balls[state.player.ship]
  ball.system = system
  ball.x, ball.y, ball.z = x, y, z
  ball.vx, ball.vy, ball.vz = 0, 0, 0
  ball.warp, ball.intent = nil, nil
  Space.AssignGrid(state, ball)
end

-- Put the pilot's ship a few kilometres off a place.
local function beside(game: Core.Game, id: number)
  local place = assert(Space.Object(game.state, id))
  put(game, id // Constants.STRUCTURE_ID_SPAN, place.x + place.radius + 4000, place.y, place.z)
end

-- The first event of a kind in the next so many ticks.
local function till(game: Core.Game, kind: string, limit: number): { [string]: any }?
  for _ = 1, limit do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      if event.kind == kind then
        return event
      end
    end
  end
  return nil
end

local function refused(game: Core.Game, command: State.Command): string?
  local ok, why = Core.Validate(game, command)
  return if ok then "(accepted)" else why
end

-- A system of the map of a kind of space (and no homeworld), and one
-- of uncharted space of a depth: the lowest-numbered.
local function ofBand(game: Core.Game, band: string): number
  for id = 1, Galaxy.Charted(game.state.galaxy) do
    if Galaxy.Band(game.state.galaxy.systems[id].security) == band and not game.state.galaxy.systems[id].home then
      return id
    end
  end
  error(`no {band} system`)
end
local function ofDepth(game: Core.Game, depth: number): number
  for id = Galaxy.Charted(game.state.galaxy) + 1, #game.state.galaxy.systems do
    if game.state.galaxy.systems[id].depth == depth then
      return id
    end
  end
  error(`no uncharted system of depth {depth}`)
end

-- A wormhole opened by hand, found already: from a system to another.
local function opened(game: Core.Game, from: number, to: number, size: number?): State.Wormhole
  return assert(Wormholes.Open(game.state, from, to, Rng.For(7, from, to), game.events, size or 3, true))
end

-- Send the pilot's ship through the wormhole whose end a place is.
local function through(t: any, game: Core.Game, place: number): { [string]: any }
  beside(game, place)
  local ok, why = Core.Submit(game, { kind = "Jump", actor = game.state.player.ship, target = place })
  t.ok(ok, `the jump was refused: {why}`)
  return assert(till(game, "Jumped", 900), "the ship never went through")
end

suite:Case("a galaxy has as many systems again that are on no map, and its map is what it would have been", function(t)
  local plain = Galaxy.Describe(1, SYSTEMS)
  local galaxy = Galaxy.Describe(1, SYSTEMS)
  Galaxy.Deepen(galaxy)
  t.eq({ #galaxy.systems, Galaxy.Charted(galaxy), Galaxy.Charted(plain) }, { 2 * SYSTEMS, SYSTEMS, SYSTEMS })
  -- (the map: every system of it as it was, but for nothing)
  for id = 1, SYSTEMS do
    t.eq(galaxy.systems[id], plain.systems[id], `system {id}`)
  end
  for id = 1, #plain.regions do
    t.eq(galaxy.regions[id], plain.regions[id])
  end
  local depths = { 0, 0, 0, 0, 0 }
  local names: { [string]: boolean } = {}
  for id = 1, SYSTEMS do
    names[galaxy.systems[id].name] = true
  end
  local region = galaxy.regions[#galaxy.regions]
  t.eq({ region.name, #galaxy.regions } :: { any }, { "Uncharted space", #plain.regions + 1 } :: { any })
  for id = SYSTEMS + 1, 2 * SYSTEMS do
    local system = galaxy.systems[id]
    t.eq({ system.id, system.uncharted, #system.neighbors, system.owner, system.home, system.security, system.region } :: { any },
      { id, true, 0, "", false, 0, region.id } :: { any })
    t.ok(not names[system.name], `{system.name} is the name of two systems`)
    names[system.name] = true
    local depth = system.depth :: number
    t.ok(depth >= 1 and depth <= #Galaxy.DEPTHS and depth % 1 == 0)
    depths[depth] += 1
    -- (no gate leads there, from anywhere)
    t.eq(#Galaxy.Route(galaxy, 1, id), 0)
  end
  -- (five depths, every one of them somewhere, and the edge the commonest)
  t.eq({ #Galaxy.DEPTHS, Galaxy.PIRATE_DEPTH }, { 5, 3 })
  for depth = 1, 5 do
    t.ok(depths[depth] >= 1 and depths[depth] <= depths[1], `depths: {table.concat(depths, ", ")}`)
  end
  -- (it follows from the seed, and is done once)
  local again = Galaxy.Describe(1, SYSTEMS)
  Galaxy.Deepen(again)
  Galaxy.Deepen(again)
  t.eq(again, galaxy)
  -- (and nobody holds any of it: the holders are who they were)
  t.eq(Galaxy.Holders(galaxy), Galaxy.Holders(plain))
  -- A system of it has planets and belts, and nothing anybody built.
  local belts, planets = 0, 0
  for id = SYSTEMS + 1, 2 * SYSTEMS do
    for _, object in System.Describe(galaxy, id).objects do
      t.ok(object.kind ~= "station" and object.kind ~= "gate", `{object.name} is in uncharted space`)
      belts += if object.kind == "belt" then 1 else 0
      planets += if object.kind == "planet" then 1 else 0
    end
  end
  t.ok(planets >= SYSTEMS and belts >= SYSTEMS, `{planets} planets and {belts} belts in forty systems`)
end)

suite:Case("a system of the map has a wormhole on some days, more often where order is thin: a signal, found by scanning", function(t)
  local game = inSpace()
  local state = game.state
  local entries = { 0, 0 }
  local function days(system: number): number
    local ball = state.balls[state.player.ship]
    put(game, system, ball.x, ball.y, ball.z)
    local count = 0
    for day = 100, 399 do
      state.tick = day * Wormholes.DAY + 7
      local events: { any } = {}
      Wormholes.Step(state, events)
      -- (asked again the same day, it says the same)
      Wormholes.Step(state, events)
      for _, event in events do
        if event.kind == "WormholeOpened" then
          count += 1
          local hole = state.wormholes[event.wormhole]
          t.eq({ hole.from, hole.a, hole.b } :: { any }, { system, event.site, 0 } :: { any })
          t.ok(state.galaxy.systems[hole.to].uncharted, "a wormhole of the map leads off it")
          -- (to the edge of it: the first depth, or now and then the second)
          local into = state.galaxy.systems[hole.to].depth :: number
          t.ok(into <= 2, `a wormhole of the map led to depth {into}`)
          entries[into] += 1
          t.ok(hole.closes - hole.opened >= Wormholes.LIFE[1] and hole.closes - hole.opened <= Wormholes.LIFE[2])
          t.ok(hole.size >= 1 and hole.size <= 3)
        end
      end
      -- (one at a time: yesterday's has closed)
      t.ok(#Wormholes.In(state, system) <= 1)
    end
    return count
  end
  local safe, wild = days(ofBand(game, "secure")), days(ofBand(game, "lawless"))
  t.ok(safe >= 15 and safe <= 50, `{safe} days of 300 with a wormhole where order is kept`)
  t.ok(wild >= 65 and wild <= 120, `{wild} days of 300 with a wormhole in lawless space`)
  print(`     wormholes: on {safe} days of 300 where order is kept, and {wild} where it is not`)
  -- (and never at a homeworld)
  t.eq({ state.galaxy.systems[1].home, days(1) } :: { any }, { true, 0 } :: { any })
  t.ok(entries[1] > 2 * entries[2] and entries[2] >= 5, `{entries[1]} came out at the first depth and {entries[2]} at the second`)

  -- One that is there: not on the overview, a signal on the scanner,
  -- found in a scan or two, and then a place to warp to.
  game = inSpace()
  state = game.state
  local hole = assert(Wormholes.Open(state, 1, ofDepth(game, 1), Rng.For(3), game.events))
  local site = state.sites[hole.a]
  local place = assert(Space.Object(state, hole.a))
  t.eq({ site.kind, site.strength, site.gone, place.kind, place.variety, place.site } :: { any },
    { "wormhole", 0, false, "wormhole", "site.wormhole", hole.a } :: { any })
  t.eq(place.name, `Wormhole {hole.code}`)
  local function listed(): boolean
    for _, entry in Core.Query.Overview(game) do
      if entry.id == hole.a then
        t.eq({ entry.kind, entry.variety }, { "site", "site.wormhole" })
        return true
      end
    end
    return false
  end
  t.eq(listed(), false)
  t.eq(refused(game, { kind = "Jump", actor = state.player.ship, target = hole.a }), "no such target")
  local signal = false
  for _, row in Core.Query.Sites(game) do
    if row.id == hole.a then
      signal = true
      t.eq({ row.found, row.kind, row.name } :: { any }, { false, "", `Signal {hole.code}` } :: { any })
    end
  end
  t.ok(signal, "the wormhole is not a signal on the scanner")
  local scans = 0
  while site.strength < 1 and scans < 5 do
    assert(Core.Submit(game, { kind = "Scan", actor = state.player.ship }))
    steps(game, Sites.SCAN + 1)
    scans += 1
  end
  t.ok(scans >= 1 and scans <= Sites.SCANS.wormhole, `found in {scans} scans`)
  t.eq(listed(), true)
  t.eq(refused(game, { kind = "WarpTo", actor = state.player.ship, target = hole.a }), "(accepted)")
  t.eq(refused(game, { kind = "Jump", actor = state.player.ship, target = hole.a }), "(accepted)")
  -- (and it is not one of the system's count of sites: they are as many as they were)
  local own = 0
  for _, other in Sites.In(state, 1) do
    own += if other.kind == "wormhole" then 0 else 1
  end
  t.eq(own, Sites.COUNT.secure)
end)

suite:Case("a ship goes through a wormhole and comes out beside its far end, which is there from then on, and back", function(t)
  local game = inSpace()
  local state = game.state
  local deep = ofDepth(game, 2)
  local hole = opened(game, 1, deep)
  t.eq({ hole.b, Wormholes.Leads(state, hole, hole.a) } :: { any }, { 0, "uncharted space" } :: { any })
  -- (the far system is nobody's business until somebody goes)
  t.eq(state.systems[deep], nil)
  local out = through(t, game, hole.a)
  local me = state.balls[state.player.ship]
  t.eq({ out.from, out.to, out.gate, out.arrival, out.wormhole } :: { any }, { 1, deep, hole.a, hole.b, true } :: { any })
  t.ok(hole.b ~= 0 and hole.b // Constants.STRUCTURE_ID_SPAN == deep, "the far end is not a place of the far system")
  local far = assert(Space.Object(state, hole.b))
  t.eq({ me.system, me.grid, far.kind, far.name } :: { any }, { deep, hole.b, "wormhole", `Wormhole {hole.code}` } :: { any })
  t.near(Space.Gap(me :: any, far :: any), Constants.JUMP_ARRIVAL_DISTANCE, 1)
  -- (whoever came out of it knows where it is)
  t.eq({ state.sites[hole.b].strength, state.sites[hole.b].gone, state.sites[hole.b].kind } :: { any }, { 1, false, "wormhole" } :: { any })
  local shown = false
  for _, entry in Core.Query.Overview(game) do
    shown = shown or (entry.id == hole.b and entry.onGrid)
  end
  t.ok(shown, "the far end is not on the overview")
  -- (and where each end leads is known by name now)
  local name = state.galaxy.systems[deep].name
  t.eq(Wormholes.Leads(state, hole, hole.a), `{name} (uncharted)`)
  t.eq(Wormholes.Leads(state, hole, hole.b), state.galaxy.systems[1].name)
  t.eq({ table.find(Wormholes.In(state, 1), hole) ~= nil, table.find(Wormholes.In(state, deep), hole) ~= nil,
    Wormholes.At(state, hole.b) == hole, Wormholes.Beyond(hole, hole.b) } :: { any }, { true, true, true, 1 } :: { any })
  -- Uncharted space: no station, no gate, nobody's, and the pilot is in it.
  local player = Core.Query.Player(game)
  t.eq({ player.system, player.uncharted, player.depth, player.depths } :: { any }, { deep, true, 2, 5 } :: { any })
  for _, entry in Core.Query.Overview(game) do
    t.ok(entry.kind ~= "station" and entry.kind ~= "gate", `{entry.name} is in uncharted space`)
  end
  -- And back, by the same hole: out beside the end it went in at.
  local back = through(t, game, hole.b)
  local near = assert(Space.Object(state, hole.a))
  t.eq({ back.from, back.to, back.arrival, me.system, me.grid } :: { any }, { deep, 1, hole.a, 1, hole.a } :: { any })
  t.near(Space.Gap(me :: any, near :: any), Constants.JUMP_ARRIVAL_DISTANCE, 1)
  -- (a second trip makes no second far end)
  local objects = #Space.Describe(state, deep).objects
  through(t, game, hole.a)
  t.eq(#Space.Describe(state, deep).objects, objects)
end)

suite:Case("a wormhole lets through what its size lets through, and nothing bigger than a battleship goes through any", function(t)
  local game = inSpace()
  local state = game.state
  local deep = ofDepth(game, 1)
  local holes = { opened(game, 1, deep, 1), opened(game, 1, deep, 2), opened(game, 1, deep, 3) }
  local function hull(class: string): State.Ship
    for _, type in Ships.list do
      if type.class == class then
        return Space.NewShip(state, type.id, "Tester", "player", state.player.home)
      end
    end
    error(`no hull of class {class}`)
  end
  local fits: { [string]: number } = { capsule = 1, frigate = 1, destroyer = 1, cruiser = 2, industrial = 2, barge = 2,
    attackbattlecruiser = 2, battlecruiser = 2, battleship = 3 }
  local seen: { [string]: boolean } = {}
  for _, type in Ships.list do
    if not seen[type.class] then
      seen[type.class] = true
      local ship = hull(type.class)
      for size, hole in holes do
        local ok, why = Wormholes.Passable(state, hole.a, ship)
        local least = fits[type.class]
        t.eq(ok, least ~= nil and least <= size, `a {type.class} through a {Wormholes.SIZE_NAMES[size]} wormhole`)
        if least == nil then
          t.eq(why, "nothing bigger than a battleship goes through a wormhole")
        elseif not ok then
          t.eq(why, `too big for this wormhole: nothing over {Wormholes.LETS[size]} gets through`)
        end
      end
    end
  end
  t.ok(seen.carrier and seen.freighter and seen.battleship and seen.cruiser, "a class of hull is missing")
  -- (as the order to jump says, for the ship that is asked about)
  local cruiser = hull("cruiser")
  local station = assert(Space.Object(state, state.player.home))
  Space.Launch(state, cruiser, 1, station.x + 4e6, station.y, station.z)
  t.eq(refused(game, { kind = "Jump", actor = cruiser.id, target = holes[1].a }),
    "too big for this wormhole: nothing over a destroyer gets through")
  t.eq(refused(game, { kind = "Jump", actor = cruiser.id, target = holes[2].a }), "(accepted)")
  t.eq(refused(game, { kind = "Jump", actor = state.player.ship, target = holes[1].a }), "(accepted)")
  -- (a size is rolled when nobody says: all three turn up)
  local sizes = { 0, 0, 0 }
  for index = 1, 200 do
    local hole = assert(Wormholes.Open(state, 2, deep, Rng.For(11, index), game.events))
    sizes[hole.size] += 1
    Wormholes.Close(state, hole, game.events)
  end
  t.ok(sizes[1] >= 35 and sizes[2] >= 60 and sizes[3] >= 25, `sizes of 200: {sizes[1]}, {sizes[2]}, {sizes[3]}`)
end)

suite:Case("a wormhole closes when its time is up: both ends go, and nobody goes through", function(t)
  local game = inSpace()
  local state = game.state
  local deep = ofDepth(game, 1)
  local hole = opened(game, 1, deep)
  through(t, game, hole.a)
  through(t, game, hole.b)
  -- (on the way to it when it goes: the ship is told, and stays where it is)
  local place = assert(Space.Object(state, hole.a))
  put(game, 1, place.x + 60000, place.y, place.z)
  assert(Core.Submit(game, { kind = "Jump", actor = state.player.ship, target = hole.a }))
  steps(game, 3)
  Core.TakeEvents(game)
  state.tick = hole.closes - 1
  local closed: { any } = {}
  local failed = false
  for _ = 1, 400 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      -- (this one: the day's own, if there is one, goes in its own time)
      if event.kind == "WormholeClosed" and event.wormhole == hole.id then
        table.insert(closed, event)
      end
      failed = failed or event.kind == "JumpFailed" or event.kind == "CommandRejected"
      t.ok(event.kind ~= "Jumped", "a ship went through a wormhole that had closed")
    end
  end
  t.eq(#closed, 2)
  t.eq({ closed[1].site, closed[1].system, closed[1].found, closed[1].name } :: { any }, { hole.a, 1, true, `Wormhole {hole.code}` } :: { any })
  t.eq({ closed[2].site, closed[2].system } :: { any }, { hole.b, deep } :: { any })
  t.eq({ state.wormholes[hole.id], table.find(state.wormholeIds, hole.id), state.sites[hole.a].gone, state.sites[hole.b].gone } :: { any },
    { nil, nil, true, true } :: { any })
  t.eq(state.balls[state.player.ship].system, 1)
  t.eq(Wormholes.At(state, hole.a), nil)
  t.eq(refused(game, { kind = "Jump", actor = state.player.ship, target = hole.a }), "that wormhole has closed")
  -- (and it is on no overview, though the pilot is beside where it was)
  beside(game, hole.a)
  for _, entry in Core.Query.Overview(game) do
    t.ok(entry.id ~= hole.a, "a closed wormhole is on the overview")
  end
  for _, row in Core.Query.Sites(game) do
    t.ok(row.id ~= hole.a, "a closed wormhole is a signal still")
  end
end)

suite:Case("always a way out: uncharted space the pilot is in is never left with no wormhole open", function(t)
  local game = inSpace()
  local state = game.state
  local charted = Galaxy.Charted(state.galaxy)
  local taken: { [number]: number } = {}
  local led = 0
  for depth = 1, 5 do
    local deep = ofDepth(game, depth)
    local hole = opened(game, 1, deep, 1)
    through(t, game, hole.a)
    Core.Step(game)
    Core.TakeEvents(game)
    -- (the system has one of its own each day, beside the one come by)
    t.eq(#Wormholes.In(state, deep), 2)
    -- Ten days there, looked at every ten minutes: never none.
    local out, deeper, least = 0, 0, 99
    local start = state.tick
    for tick = start, start + 10 * Wormholes.DAY, 600 do
      state.tick = tick
      local events: { any } = {}
      Wormholes.Step(state, events)
      local open = Wormholes.In(state, deep)
      least = math.min(least, #open)
      for _, event in events do
        if event.kind == "WormholeOpened" then
          local opened = state.wormholes[event.wormhole]
          out += if opened.to <= charted then 1 else 0
          deeper += if opened.to > charted then 1 else 0
          t.ok(opened.to ~= deep, "a wormhole leads to where it is")
          -- (a ladder: one that leads on goes a step deeper, level or a step back, and no further)
          local onward = state.galaxy.systems[opened.to].depth
          if onward then
            t.ok(math.abs(onward - depth) <= 1, `a wormhole at depth {depth} led to depth {onward}`)
            taken[onward - depth] = (taken[onward - depth] or 0) + 1
          end
        end
      end
    end
    t.ok(least >= 1, `uncharted space was left with {least} wormholes open`)
    t.ok(out + deeper >= 9, `{out} led out and {deeper} on in ten days at depth {depth}`)
    led += out
    -- With every one of them closed under the pilot, another opens at
    -- once: a great one, that leads back to the map.
    for _, open in Wormholes.In(state, deep) do
      Wormholes.Close(state, open, game.events)
    end
    t.eq(#Wormholes.In(state, deep), 0)
    Core.TakeEvents(game)
    Core.Step(game)
    local open = Wormholes.In(state, deep)
    t.eq(#open, 1)
    t.eq({ open[1].size, open[1].from, open[1].to <= charted } :: { any }, { 3, deep, true } :: { any })
    -- (to be found as any is: and then the way home)
    local site = state.sites[open[1].a]
    t.eq(site.strength, 0)
    site.strength = 1
    local home = through(t, game, open[1].a)
    t.ok(home.to <= charted and not state.galaxy.systems[home.to].uncharted, "the way out led further in")
    put(game, 1, 4e9, 0, 0)
  end
  -- (over fifty days at the five depths: some led straight out, and of
  -- those that led on, every kind of step was taken)
  t.ok(led >= 10 and (taken[1] or 0) >= 5 and (taken[0] or 0) >= 3 and (taken[-1] or 0) >= 2,
    `{led} out, {taken[1] or 0} deeper, {taken[0] or 0} level, {taken[-1] or 0} back`)
  -- (and a system of the map is not owed one: with whatever it had
  -- today closed, it has none)
  steps(game, 3)
  for _, open in Wormholes.In(state, 1) do
    Wormholes.Close(state, open, game.events)
  end
  steps(game, 3)
  t.eq(#Wormholes.In(state, 1), 0)
end)

suite:Case("no jump drive finds its way in or out of uncharted space", function(t)
  local game = inSpace()
  local state = game.state
  local deep = ofDepth(game, 1)
  local jumper: Ships.ShipType? = nil
  for _, type in Ships.list do
    if type.jump and not jumper then
      jumper = type
    end
  end
  local hull = assert(jumper, "no hull has a jump drive")
  local mine = Space.NewShip(state, hull.id, "Tester", "player", state.player.home)
  local station = assert(Space.Object(state, state.player.home))
  local me = Space.Launch(state, mine, 1, station.x + 4e6, station.y, station.z)
  t.ok(Jumping.Fitted(state, mine.id))
  t.eq(refused(game, { kind = "JumpDrive", actor = mine.id, target = deep }), "no drive finds its way in or out of uncharted space")
  t.eq(Jumping.Soon(state, mine.id, deep), false)
  me.system = deep
  Space.AssignGrid(state, me)
  t.eq(refused(game, { kind = "JumpDrive", actor = mine.id, target = 2 }), "no drive finds its way in or out of uncharted space")
  t.eq(Jumping.Soon(state, mine.id, 2), false)
end)

suite:Case("what lives in uncharted space is worse the deeper in, and there is more to find", function(t)
  for depth = 1, 3 do
    local game = inSpace(depth, true)
    local state = game.state
    local deep = ofDepth(game, depth)
    local belt: System.Object? = nil
    for _, object in Space.Describe(state, deep).objects do
      if object.kind == "belt" and belt == nil then
        belt = object
      end
    end
    local at = assert(belt, "the system has no belt")
    put(game, deep, at.x + 500, at.y, at.z)
    Core.Step(game)
    -- (more sites than lawless space has, by its depth: its own, with
    -- no wormhole counted, nor a moon the pirates hold with a tower)
    local own = 0
    for _, site in Sites.In(state, deep) do
      own += if site.kind == "wormhole" or site.kind == "keep" then 0 else 1
    end
    t.eq(own, Sites.COUNT.lawless + depth)
    -- (the pack that comes to the belt)
    local worst, count = 0, 0
    local order: { [string]: number } = { scout = 1, raider = 2, jackal = 3, mender = 3, marauder = 4, ravager = 5 }
    for _, id in state.pilotIds do
      local ball = state.balls[id]
      if ball and ball.system == deep and ball.grid == at.id then
        count += 1
        for kind, rank in order do
          if string.find(string.lower(state.ships[id].name), kind, 1, true) then
            worst = math.max(worst, rank)
          end
        end
      end
    end
    t.ok(count >= 3, `{count} pirates came to a belt at depth {depth}`)
    t.ok(worst >= (if depth == 1 then 3 else 4), `the worst of a pack at depth {depth} was of rank {worst}`)
  end
  -- Past the third depth not even pirates live: what comes to a belt
  -- there is the Drowned's (Data/Factions), in their own hulls, under
  -- the cloak each has until it is in reach. There is no den and no
  -- tower of the pirates', and there is no more to find than at the
  -- third.
  for depth = 4, 5 do
    local game = inSpace(depth, true)
    local state = game.state
    local deep = ofDepth(game, depth)
    local belt: System.Object? = nil
    for _, object in Space.Describe(state, deep).objects do
      if object.kind == "belt" and belt == nil then
        belt = object
      end
    end
    local at = assert(belt, "the system has no belt")
    put(game, deep, at.x + 500, at.y, at.z)
    Core.TakeEvents(game)
    steps(game, 5)
    -- A pack has come, and nobody is told: every one of it is under its cloak, and cannot be targeted.
    t.ok(#state.pilotIds >= 3, `{#state.pilotIds} of the Drowned came to a belt at depth {depth}`)
    local biggest = 0
    for _, id in state.pilotIds do
      local hull = Ships.byId[state.ships[id].type]
      t.eq({ hull.lineage, hull.cloak, Core.Query.Cloaked(game, id) } :: { any }, { "drowned", true, true } :: { any })
      t.eq({ Core.Validate(game, { kind = "LockTarget", actor = state.player.ship, target = id }) } :: { any },
        { false, "no such target" } :: { any })
      biggest = math.max(biggest, hull.radius)
    end
    -- (nothing smaller than a destroyer leads at the fourth depth, and a battlecruiser or a battleship at the fifth)
    t.ok(biggest >= (if depth == 4 then 75 else 300), `the biggest hull of a pack at depth {depth} is {biggest} m`)
    for _, event in Core.TakeEvents(game) do
      t.ok(event.kind ~= "PiratesArrived", "a pack that came unseen was announced")
    end
    -- Before long they are in reach, and out from under their cloaks.
    local out = false
    for _ = 1, 600 do
      Core.Step(game)
      for _, event in Core.TakeEvents(game) do
        out = out or (event.kind == "Decloaked" and state.pilots[event.ball] ~= nil)
      end
    end
    t.ok(out, `nobody of the Drowned came out from under a cloak at depth {depth}`)
    t.eq(#state.keepIds, 0)
    local own = 0
    for _, site in Sites.In(state, deep) do
      t.ok(site.kind ~= "combat" and site.kind ~= "keep", `a {site.kind} site at depth {depth}`)
      own += if site.kind == "wormhole" then 0 else 1
    end
    t.eq(own, Sites.COUNT.lawless + Galaxy.PIRATE_DEPTH)
  end
  -- (the packs of each depth, as they are written: nothing below a
  -- cruiser leads one past the edge, and the deepest are led by a
  -- battleship)
  for _, entry in Pirates.DEEP[2] do
    t.ok(entry[2][1] == "marauder" or entry[2][1] == "ravager")
  end
  for _, entry in Pirates.DEEP[3] do
    t.eq(entry[2][1], "ravager")
  end
  for depth = 1, 3 do
    local share = 0
    for _, entry in Pirates.DEEP[depth] do
      share += entry[1]
      for _, kind in entry[2] do
        t.ok(Pirates.kindById[kind] ~= nil, `no pirate is a {kind}`)
      end
    end
    t.near(share, 1, 1e-9)
  end
  -- A wormhole is nobody's camp: nothing comes to one.
  local game = inSpace(1, true)
  local state = game.state
  local hole = opened(game, ofBand(game, "lawless"), ofDepth(game, 3))
  beside(game, hole.a)
  steps(game, 400)
  for _, id in state.pilotIds do
    local ball = state.balls[id]
    t.ok(ball == nil or ball.grid ~= hole.a, "pirates came to a wormhole")
  end
end)

suite:Case("wormholes are in the save, and a save from before has its galaxy deepened and none open", function(t)
  local game = inSpace()
  local hole = opened(game, 1, ofDepth(game, 3))
  through(t, game, hole.a)
  steps(game, 5)
  Core.TakeEvents(game)
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.eq(loaded.state.wormholes[hole.id], hole)
  for _ = 1, 50 do
    Core.Step(game)
    Core.Step(loaded)
  end
  t.eq(Core.Hash(loaded), Core.Hash(game))

  -- A save of the version before: a galaxy of the map alone, and
  -- nothing of wormholes. It opens as a new game of the same seeds is.
  local fresh = Core.New({ galaxySeed = 1, historySeed = 1, systems = SYSTEMS, peaceful = true })
  local saved, savedLength = Core.Save(fresh)
  local file = Codec.Decode(saved, savedLength)
  file.saveVersion = 73
  local galaxy = file.state.galaxy
  for id = #galaxy.systems, galaxy.charted + 1, -1 do
    galaxy.systems[id] = nil
  end
  galaxy.regions[#galaxy.regions], galaxy.constellations[#galaxy.constellations] = nil, nil
  galaxy.charted = nil
  file.state.wormholes, file.state.wormholeIds, file.state.wormholesRolled = nil, nil, nil
  local old, oldLength = Codec.Encode(file)
  local older = Core.Load(old, oldLength)
  t.eq({ #older.state.galaxy.systems, older.state.galaxy.charted } :: { any }, { 2 * SYSTEMS, SYSTEMS } :: { any })
  t.eq(older.state.galaxy, fresh.state.galaxy)
  t.eq(Core.Hash(older), Core.Hash(fresh))
  for _ = 1, 20 do
    Core.Step(older)
  end
end)

suite:Case("a pilot whose ship is lost in uncharted space is in a capsule there, which gets through any wormhole", function(t)
  local game = inSpace(1, true)
  local state = game.state
  local deep = ofDepth(game, 3)
  local hole = opened(game, 1, deep)
  through(t, game, hole.a)
  -- (to a belt, where what lives there is)
  local belt: System.Object? = nil
  for _, object in Space.Describe(state, deep).objects do
    if object.kind == "belt" and belt == nil then
      belt = object
    end
  end
  local at = assert(belt, "the system has no belt")
  put(game, deep, at.x + 500, at.y, at.z)
  local first = state.player.ship
  local lost = false
  for _ = 1, 3000 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      lost = lost or (event.kind == "BallDestroyed" and event.ball == first)
    end
    if lost then
      break
    end
  end
  t.ok(lost, "a frigate lasted an hour at a belt in the deepest of uncharted space")
  steps(game, 5)
  local ship = state.ships[state.player.ship]
  local me = state.balls[state.player.ship]
  t.ok(ship ~= nil and me ~= nil and ship.id ~= first, "the pilot is nowhere")
  t.eq({ Ships.byId[ship.type].class, me.system } :: { any }, { "capsule", deep } :: { any })
  -- (the way it came is open still, and a capsule fits through the narrowest)
  t.eq(Wormholes.Passable(state, hole.b, ship), true)
  t.eq(Wormholes.Fits(Ships.byId[ship.type], 1), true)
  local home = through(t, game, hole.b)
  t.eq({ home.to, state.balls[state.player.ship].system }, { 1, 1 })
  steps(game, 50)
end)

suite:Case("a hired pilot goes through a wormhole after the pilot, if their ship fits", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, systems = SYSTEMS, peaceful = true })
  local state = game.state
  state.wallet = 10000000
  local function order(command: State.Command)
    command.actor = state.player.ship
    local ok, why = Core.Submit(game, command)
    t.ok(ok, `{command.kind} was refused: {why}`)
    Core.Step(game)
  end
  local second = Space.NewShip(state, "frigate.courier", "Second", "player", state.player.home)
  local candidates = Core.Query.Candidates(game, state.player.home)
  order({ kind = "HirePilot", actor = 0, what = candidates[1].key })
  local wing = state.fleet[state.fleetIds[#state.fleetIds]]
  order({ kind = "AssignShip", actor = 0, pilot = wing.id, target = second.id })
  order({ kind = "Undock", actor = 0 })
  steps(game, 5)
  local theirs = assert(state.balls[second.id], "the hired pilot did not come out")
  local deep = ofDepth(game, 1)
  local hole = opened(game, 1, deep, 1)
  local place = assert(Space.Object(state, hole.a))
  theirs.x, theirs.y, theirs.z = place.x + place.radius + 6000, place.y + 800, place.z
  theirs.vx, theirs.vy, theirs.vz = 0, 0, 0
  Space.AssignGrid(state, theirs)
  through(t, game, hole.a)
  -- (the pilot is through: the hired one comes after, by the same hole)
  local followed = false
  for _ = 1, 900 do
    Core.Step(game)
    if theirs.system == deep then
      followed = true
      break
    end
  end
  t.ok(followed, "the hired pilot was left behind")
  t.eq(theirs.grid, hole.b)
  -- And back: the pilot first, and the hired one after.
  Core.TakeEvents(game)
  through(t, game, hole.b)
  local back = false
  for _ = 1, 900 do
    Core.Step(game)
    if theirs.system == 1 then
      back = true
      break
    end
  end
  t.ok(back, "the hired pilot did not come back")
end)

suite:Case("a tower is anchored anywhere in uncharted space, but no claim beacon: nobody holds a system there", function(t)
  -- (the owner, 2026-11-16: "all of j-space (wormhole space) should be
  -- able to have towers anchored in it, just no sovereignty")
  local game = Core.New({ galaxySeed = 1, historySeed = 1, systems = SYSTEMS, peaceful = true })
  local state = game.state
  local function order(command: State.Command)
    command.actor = state.player.ship
    local ok, why = Core.Submit(game, command)
    t.ok(ok, `{command.kind} was refused: {why}`)
    Core.Step(game)
  end
  -- (room for a tower at every depth)
  state.skills.anchoring = 5
  order({ kind = "Undock", actor = 0 })
  steps(game, 5)
  for depth = 1, #Galaxy.DEPTHS do
    local deep = ofDepth(game, depth)
    local moon: System.Object? = nil
    for _, object in Space.Describe(state, deep).objects do
      if object.kind == "moon" and moon == nil then
        moon = object
      end
    end
    if moon then
      local tower = Items.Add(state, "tower.vessari.small", 1, state.player.ship, "cargo")
      put(game, deep, moon.x + moon.radius * 1.5, moon.y, moon.z)
      t.eq(refused(game, { kind = "AnchorTower", actor = state.player.ship, item = tower.id, target = moon.id }), "(accepted)",
        `a tower at depth {depth}`)
      if depth == 1 then
        order({ kind = "AnchorTower", actor = 0, item = tower.id, target = moon.id })
        local station = state.starbaseIds[#state.starbaseIds]
        steps(game, Structures.towerById["tower.vessari.small"].anchor + 2)
        order({ kind = "Dock", actor = 0, target = station })
        for _ = 1, 120 do
          if state.ships[state.player.ship].docked == station then
            break
          end
          Core.Step(game)
        end
        t.eq(state.ships[state.player.ship].docked, station, "the pilot did not dock at their tower out here")
        local fuel = Items.Add(state, Structures.FUEL.id, 50, state.player.ship, "cargo")
        order({ kind = "Fuel", actor = 0, item = fuel.id })
        local beacon = Items.Add(state, Structures.CLAIM, 1, state.player.ship, "cargo")
        t.eq(refused(game, { kind = "AnchorModule", actor = state.player.ship, item = beacon.id }), "nobody can hold uncharted space")
        order({ kind = "Undock", actor = 0 })
        steps(game, 5)
      end
    end
  end
end)

suite:Case("a wormhole takes so much mass through it and no more: each ship spends its hull's, and the one that spends the last gets through and it closes", function(t)
  local game = inSpace()
  local state = game.state
  local deepest = #state.galaxy.systems
  local events = {}
  local hole = assert(Wormholes.Open(state, 1, deepest, Rng.For(1, 2, 3), events, 3, true))
  t.eq({ Wormholes.Left(hole), Wormholes.Strain(hole) } :: { any }, { Wormholes.MASS[3], "stable" } :: { any })
  -- A ship through it spends its own hull's mass.
  beside(game, hole.a)
  assert(Core.Submit(game, { kind = "Jump", actor = state.player.ship, target = hole.a }))
  for _ = 1, 120 do
    if state.balls[state.player.ship].system ~= 1 then
      break
    end
    Core.Step(game)
  end
  local hull = Ships.byId[state.ships[state.player.ship].type]
  t.eq({ state.balls[state.player.ship].system, hole.mass } :: { any }, { deepest, hull.mass } :: { any })
  -- Worn down, it says so; and the last of it closes it.
  Wormholes.Passed(state, hole, Wormholes.MASS[3] * 0.6 - hull.mass, events)
  t.eq(Wormholes.Strain(hole), "reduced")
  Wormholes.Passed(state, hole, Wormholes.MASS[3] * 0.35, events)
  t.eq(Wormholes.Strain(hole), "critical")
  Wormholes.Passed(state, hole, Wormholes.MASS[3], events)
  t.eq(state.wormholes[hole.id], nil, "it should have closed")
end)

suite:Case("a wormhole station holds a wormhole open just outside it while it is lit, and opens another when that one closes", function(t)
  local game = inSpace()
  local state = game.state
  -- (a station of the kind, stood for here by a planet of the home system's: the rule asks only where it is)
  local planet: System.Object? = nil
  for _, object in Space.Describe(state, 1).objects do
    if planet == nil and object.kind == "planet" then
      planet = object
    end
  end
  local at = assert(planet)
  local starbase: State.Starbase = { id = at.id, tower = "citadel.wormhole.small", owner = "player", ready = 0, fuel = 0, burnt = 0,
    modules = {}, drilled = 0, raid = 0, raids = 0, used = 0, raised = 0, robbed = 0, core = 0, charges = 0, sealed = 0, siege = 0,
    reaction = "", reacted = 0, composed = 0, starved = false }
  state.starbases[at.id] = starbase
  table.insert(state.starbaseIds, at.id)
  steps(game, 2)
  t.eq(starbase.hole, nil, "a dark station holds nothing open")
  starbase.fuel = 100
  steps(game, 2)
  local hole = assert(state.wormholes[starbase.hole or 0], "a lit station should hold a wormhole open")
  local near = assert(Space.Object(state, hole.a))
  t.eq({ hole.station, hole.from, state.galaxy.systems[hole.to].uncharted, state.sites[hole.a].strength } :: { any },
    { at.id, 1, true, 1 } :: { any })
  t.ok(Space.Distance(near :: any, at :: any) < at.radius + Wormholes.HELD_OUT + 2 * Wormholes.RADIUS, "it is not just outside the station")
  -- Closed (by time, by mass, by anything), another opens at once.
  Wormholes.Close(state, hole, {})
  steps(game, 2)
  local again = assert(state.wormholes[starbase.hole or 0], "no second wormhole")
  t.ok(again.id ~= hole.id and again.station == at.id)
  state.starbases[at.id] = nil
  State.RemoveId(state.starbaseIds, at.id)
end)

return suite
