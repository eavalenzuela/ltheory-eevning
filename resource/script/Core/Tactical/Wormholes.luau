--!strict
-- Wormholes: the ways into uncharted space, and out of it.
--
-- Half of the galaxy is on no map (Galaxy.Deepen): as many systems
-- again as the gates join, with no gate to any of them, nobody living
-- there but pirates, and more to find the deeper in they lie. The way
-- to one is a wormhole: a hole that opens somewhere in a system, stays
-- for most of a day, and closes. Nobody says where one is. It is a
-- signal on the scanner, to be worked like any other (Tactical/Sites),
-- and when it is found it can be warped to and gone through like a
-- gate.
--
-- The project owner's rulings (2026-11-14): as many systems of
-- uncharted space as there are of the map; pirates live there, for
-- now; there is always a way out; and none of it is ever on the star
-- map. The rest is first figures:
--
--   - A system of the map has a wormhole open in it on one day in so
--     many, more often the less order is kept there. It leads into
--     uncharted space. (A homeworld never has one: order is kept best
--     there, and a new pilot's first system is as it was.)
--   - A system of uncharted space has one of its own every day, which
--     leads back to the map or on to another uncharted system: back
--     more often than not near the edge, and seldom from far in.
--   - Depth is a ladder. A wormhole from the map comes out at the first
--     depth, or now and then the second; one that leads on from a
--     system leads to its own depth, a step deeper or a step back, and
--     never further. So the fifth depth is four wormholes from the map
--     at the least, and the way straight back (below) is one.
--   - A wormhole is one of four sizes, and nothing bigger than its
--     size gets through: a frigate or a destroyer through any, a
--     cruiser or a battlecruiser through a broad one or bigger, a
--     battleship through a great or a massive one, and a capital below
--     the supercarriers (a carrier, a dreadnought, a capital industrial,
--     a freighter) through a massive one only. A supercarrier or an
--     ultracapital goes through none. (The massive size is the owner's,
--     2026-11-17: "there should be wormholes that capitals can fit
--     through (otherwise, most citadels couldn't ever be brought in)
--     ... that can fit anything below supers". A citadel of medium size
--     or more goes only in a freighter's hold.)
--   - No jump drive or bridge finds its way in or out (the owner,
--     2026-11-17: "nothing should ever be able to jumpdrive jump to
--     j-space"; Tactical/Jumping): wormholes are the only way.
--   - Always a way out: a system of uncharted space the pilot is in is
--     never left with no wormhole open. If the last one closes, another
--     opens at once: a massive one, which anything that got in can
--     leave by, and it leads back to the map.
--
-- A wormhole's end is a place of its system's description (as a site
-- is, and a pilot's tower), with a site's record so that the scanner
-- and the overview know it as they know any signal. The far end is
-- nowhere until somebody goes through: the system it leads to is fixed
-- when the wormhole opens, and the place there is made by the first
-- ship that comes out of it (which then knows where it is). Only the
-- system the pilot is in gets new ones.
--
-- And mass (2026-11-17, with the owner's wormhole stations): a wormhole
-- takes so much hull through it and no more, either way, by its size
-- (Wormholes.MASS: mine), and closes when that is spent, whatever time
-- it has left. The ship that spends it gets through.
--
-- A wormhole station (Data/Structures' kinds of citadel: the owner's,
-- "the wormhole will cycle according to the regular time and mass
-- rules") holds one open at its heart while it is lit (the owner,
-- 2026-11-21: in the sphere at its middle, which ships go into through
-- its turning rings): one that leads into uncharted space as any from
-- its system would, found from the first (its owner knows where it is),
-- and when that one closes, by time or by mass, another at once.
--
-- (Not yet: anything living in uncharted space but pirates, a hired
-- pilot finding their own way out of it.)

local Constants = require("@lt/Core/Data/Constants")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local System = require("@lt/Core/Describe/System")

local Wormholes = {}

export type Event = { [string]: any }

local SPAN = Constants.STRUCTURE_ID_SPAN

-- The kind of place a wormhole's end is, what a site's record calls it,
-- and its variety (a site's is "site." and its kind).
Wormholes.KIND = "wormhole"
Wormholes.VARIETY = "site.wormhole"
-- Ticks in a day: a system is asked once a day whether one opens.
Wormholes.DAY = math.ceil(86400 / Constants.TICK)
-- How long one stays open: so long at least, so long at most.
Wormholes.LIFE = { math.ceil(57600 / Constants.TICK), math.ceil(86400 / Constants.TICK) }
-- The chance that a system of the map has one open in it on a day, by
-- how safe it is.
Wormholes.CHANCE = { secure = 0.1, low = 0.2, lawless = 0.3 } :: { [string]: number }
-- The chance that the one an uncharted system has each day leads back
-- to the map, by the system's depth.
Wormholes.OUT = { 0.6, 0.45, 0.3, 0.2, 0.1 }
-- The depth a wormhole from the map comes out at: how often the first,
-- how often the second.
Wormholes.ENTRY = { 0.8, 0.2 }
-- Where one that leads on from an uncharted system leads: how often a
-- step deeper, and how often to the same depth (the rest, a step back).
Wormholes.DEEPER, Wormholes.LEVEL = 0.5, 0.3
-- The sizes: how often a wormhole is of each, and what each is called.
-- (Mine, the massive the rarest.)
Wormholes.SIZES = { 0.3, 0.4, 0.22, 0.08 }
Wormholes.SIZE_NAMES = { "narrow", "broad", "great", "massive" }
-- The smallest size a hull of each class gets through. (A class not
-- here gets through none: a supercarrier, an ultracapital.)
Wormholes.RANK = { capsule = 1, frigate = 1, destroyer = 1, cruiser = 2, industrial = 2, barge = 2, attackbattlecruiser = 2,
  battlecruiser = 2, battleship = 3, carrier = 4, dreadnought = 4, siegedreadnought = 4, capitalindustrial = 4,
  freighter = 4 } :: { [string]: number }
-- The biggest class that gets through each size, as it is said.
Wormholes.LETS = { "a destroyer", "a battlecruiser", "a battleship", "a dreadnought" }
-- How big the hole is, metres.
Wormholes.RADIUS = 1200
-- The kilograms of hull each size takes through it before it closes.
-- Mine: about 175 of the biggest each of the first three lets through
-- (destroyers, battlecruisers, battleships: the owner, 2026-11-17,
-- found a dozen and a half "too small"), and for the massive about 37
-- dreadnoughts or 54 freighters, so that capitals stay what spends one.
Wormholes.MASS = { 300000000, 6000000000, 18000000000, 60000000000 }
-- How big the wormhole a wormhole station holds at its heart is: so much
-- of the station's own radius (the sphere at the middle of the citadel,
-- as Game/View/Citadel grows it, is about so big: 0.174 of the large one).
Wormholes.HELD_SHARE = 0.17

-- The description of a system, made (and kept in the state) on first
-- use. (Space.Describe, which is above this module.)
local function describe(state: State.State, system: number): System.Description
  local description = state.systems[system]
  if description == nil then
    description = System.Describe(state.galaxy, system)
    state.systems[system] = description
  end
  return description
end

-- How far out a station is: a citadel's own radius (Data/Structures'
-- 'reach'), or its place's.
function Wormholes.StationReach(state: State.State, station: System.Object): number
  local starbase = state.starbases[station.id]
  local tower = if starbase then Structures.towerById[starbase.tower] else nil
  return if tower and tower.reach then tower.reach else station.radius
end

-- The station a wormhole's end is held open at the heart of, if it is
-- (a wormhole station's: the end it opened at).
function Wormholes.HeldAt(state: State.State, place: System.Object): System.Object?
  local hole = Wormholes.At(state, place.id)
  if hole == nil or hole.station == nil or hole.a ~= place.id then
    return nil
  end
  local station = describe(state, place.id // SPAN).objects[hole.station % SPAN]
  return if station and station.id == hole.station then station else nil
end

-- The wormhole one of whose ends a place is, if it is open.
function Wormholes.At(state: State.State, place: number): State.Wormhole?
  for _, id in state.wormholeIds do
    local hole = state.wormholes[id]
    if hole.a == place or (hole.b ~= 0 and hole.b == place) then
      return hole
    end
  end
  return nil
end

-- The wormholes open in a system, in the order they opened: those
-- that opened there, and those somebody has come out of there.
function Wormholes.In(state: State.State, system: number): { State.Wormhole }
  local found: { State.Wormhole } = {}
  for _, id in state.wormholeIds do
    local hole = state.wormholes[id]
    if hole.from == system or (hole.b ~= 0 and hole.to == system) then
      table.insert(found, hole)
    end
  end
  return found
end

-- The system a wormhole leads to from a place that is one of its ends.
function Wormholes.Beyond(hole: State.Wormhole, place: number): number
  return if place == hole.a then hole.to else hole.from
end

-- What is said of where a wormhole leads, from one of its ends: the
-- system by name once somebody has been through, and until then only
-- what kind of space it is.
function Wormholes.Leads(state: State.State, hole: State.Wormhole, place: number): string
  local node = state.galaxy.systems[Wormholes.Beyond(hole, place)]
  if hole.b ~= 0 then
    return if node.uncharted then `{node.name} (uncharted)` else node.name
  end
  return if node.uncharted then "uncharted space" else "charted space"
end

-- Whether a hull gets through a wormhole of a size.
function Wormholes.Fits(hull: Ships.ShipType, size: number): boolean
  local rank = Wormholes.RANK[hull.class]
  return rank ~= nil and rank <= size
end

-- Whether a ship can go through the wormhole whose end a place is, and
-- if not, why not.
function Wormholes.Passable(state: State.State, place: number, ship: State.Ship): (boolean, string?)
  local hole = Wormholes.At(state, place)
  local site = state.sites[place]
  if hole == nil or site == nil or site.gone then
    return false, "that wormhole has closed"
  elseif site.strength < 1 then
    return false, "no such target"
  end
  local hull = Ships.byId[ship.type]
  if Wormholes.RANK[hull.class] == nil then
    return false, "no supercarrier or anything bigger goes through a wormhole"
  elseif not Wormholes.Fits(hull, hole.size) then
    return false, `too big for this wormhole: nothing over {Wormholes.LETS[hole.size]} gets through`
  end
  return true
end

-- An end of a wormhole in a system: a place of its description, some
-- way out from a planet (or, where there is none, from the star), and
-- a site's record for it. Nil if the description has no room.
-- ('near': a place to open it by, in place of a planet: a wormhole
-- station's own.)
local function place(state: State.State, system: number, rng: Rng.Rng, code: string, closes: number, found: boolean,
  near: System.Object?): System.Object?
  local objects = describe(state, system).objects
  if #objects + 2 >= SPAN then
    return nil
  end
  local planets: { System.Object } = {}
  for _, object in objects do
    if object.kind == "planet" then
      table.insert(planets, object)
    end
  end
  local x, y, z, parent
  local radius = Wormholes.RADIUS
  if near then
    x, y, z = near.x, near.y, near.z
    parent = near.id
    radius = Wormholes.HELD_SHARE * Wormholes.StationReach(state, near)
  elseif #planets > 0 then
    local planet = planets[Rng.Int(rng, #planets) + 1]
    local angle, out = Rng.Float(rng, 0, 2 * math.pi), planet.radius * Rng.Float(rng, 8, 18)
    x, y, z = planet.x + out * math.cos(angle), planet.y + out * Rng.Float(rng, -0.1, 0.1), planet.z + out * math.sin(angle)
    parent = planet.id
  else
    local angle, out = Rng.Float(rng, 0, 2 * math.pi), Constants.AU * Rng.Float(rng, 0.5, 3)
    x, y, z = out * math.cos(angle), out * Rng.Float(rng, -0.02, 0.02), out * math.sin(angle)
    parent = objects[1].id
  end
  local id = system * SPAN + #objects + 1
  local object: System.Object = {
    id = id, kind = Wormholes.KIND :: any, name = `Wormhole {code}`, x = x, y = y, z = z, radius = radius,
    seed = Rng.Int(rng, 2 ^ 31), parent = parent, site = id, variety = Wormholes.VARIETY, to = 0,
  }
  table.insert(objects, object)
  local site: State.Site = { id = id, system = system, kind = Wormholes.KIND, code = code, strength = if found then 1 else 0,
    expires = closes, gone = false, depth = 0, led = false }
  state.sites[id] = site
  table.insert(state.siteIds, id)
  return object
end

-- Open a wormhole in a system, leading to another: of a size, or of
-- whatever size it turns out to be. Returns it, or nil if the system's
-- description has no room for the place.
function Wormholes.Open(state: State.State, from: number, to: number, rng: Rng.Rng, events: { Event }, size: number?,
  found: boolean?, near: System.Object?): State.Wormhole?
  local roll, turned = Rng.Next(rng), #Wormholes.SIZES
  for at, share in Wormholes.SIZES do
    roll -= share
    if roll < 0 then
      turned = at
      break
    end
  end
  local code = string.format("%s%s-%03d", string.char(65 + Rng.Int(rng, 26)), string.char(65 + Rng.Int(rng, 26)), Rng.Int(rng, 1000))
  local closes = state.tick + Wormholes.LIFE[1] + Rng.Int(rng, Wormholes.LIFE[2] - Wormholes.LIFE[1] + 1)
  local wide = size or turned
  local made = place(state, from, rng, code, closes, found == true, near)
  if made == nil then
    return nil
  end
  local hole: State.Wormhole = { id = State.NewId(state), a = made.id, from = from, b = 0, to = to, opened = state.tick, closes = closes,
    size = wide, code = code }
  state.wormholes[hole.id] = hole
  table.insert(state.wormholeIds, hole.id)
  table.insert(events, { kind = "WormholeOpened", wormhole = hole.id, system = from, site = made.id })
  table.insert(events, { kind = "SiteAppeared", site = made.id, system = from, what = Wormholes.KIND })
  return hole
end

-- The end of a wormhole that a ship going in at 'entered' comes out
-- of: made now, if nobody has been through yet, and found from then on
-- (whoever came out of it knows where it is). Nil if the far system's
-- description has no room for it, which is as good as never.
function Wormholes.Far(state: State.State, hole: State.Wormhole, entered: number): System.Object?
  if entered ~= hole.a then
    return describe(state, hole.from).objects[hole.a % SPAN]
  end
  if hole.b == 0 then
    local made = place(state, hole.to, Rng.For(state.historySeed, hole.id, 53), hole.code, hole.closes, true)
    if made == nil then
      return nil
    end
    hole.b = made.id
    return made
  end
  local far = describe(state, hole.to).objects[hole.b % SPAN]
  local site = state.sites[hole.b]
  if site then
    site.strength = 1
  end
  return far
end

-- Close a wormhole: both of its ends are gone from every chart.
local function close(state: State.State, hole: State.Wormhole, events: { Event })
  state.wormholes[hole.id] = nil
  State.RemoveId(state.wormholeIds, hole.id)
  for _, id in { hole.a, hole.b } do
    local site = state.sites[id]
    if site and not site.gone then
      site.gone = true
      table.insert(events, { kind = "WormholeClosed", wormhole = hole.id, site = id, system = site.system, found = site.strength >= 1,
        name = `Wormhole {hole.code}` })
      table.insert(events, { kind = "SiteGone", site = id, system = site.system })
    end
  end
end

-- Close a wormhole now (for whoever has a reason to: a test, a cheat).
function Wormholes.Close(state: State.State, hole: State.Wormhole, events: { Event })
  close(state, hole, events)
end

-- The kilograms of hull a wormhole will take through it yet.
function Wormholes.Left(hole: State.Wormhole): number
  return math.max(0, Wormholes.MASS[hole.size] - (hole.mass or 0))
end

-- How much of what it takes a wormhole has left, as it is said: "stable"
-- (more than half), "reduced" (half or less), "critical" (a tenth or less).
function Wormholes.Strain(hole: State.Wormhole): string
  local share = Wormholes.Left(hole) / Wormholes.MASS[hole.size]
  return if share > 0.5 then "stable" elseif share > 0.1 then "reduced" else "critical"
end

-- A ship of so many kilograms has gone through: it is spent on the
-- wormhole, which closes if that is the last of what it takes.
function Wormholes.Passed(state: State.State, hole: State.Wormhole, mass: number, events: { Event })
  hole.mass = (hole.mass or 0) + mass
  if Wormholes.Left(hole) <= 0 and state.wormholes[hole.id] then
    close(state, hole, events)
  end
end

-- A system of uncharted space of a depth, picked by a roll: any but
-- 'but'. With none of that depth (a small galaxy has not every depth),
-- one of the nearest depth there is. Nil if the galaxy has none (or
-- only that one).
local function deep(state: State.State, rng: Rng.Rng, but: number, depth: number): number?
  local systems = state.galaxy.systems
  local found: { number } = {}
  local least = math.huge
  for id = Galaxy.Charted(state.galaxy) + 1, #systems do
    if id ~= but then
      local off = math.abs((systems[id].depth or 1) - depth)
      if off < least then
        found, least = { id }, off
      elseif off == least then
        table.insert(found, id)
      end
    end
  end
  return if #found > 0 then found[Rng.Int(rng, #found) + 1] else nil
end

-- The system of uncharted space a wormhole opening in a system leads
-- to (Wormholes.Open is given it): for one of the map, one at the edge;
-- for one of uncharted space, one a step deeper, level or a step back.
-- Nil if there is nowhere.
function Wormholes.Onward(state: State.State, from: number, rng: Rng.Rng): number?
  local node = state.galaxy.systems[from]
  if not node.uncharted then
    return deep(state, rng, from, if Rng.Chance(rng, Wormholes.ENTRY[1]) then 1 else 2)
  end
  local depth = node.depth or 1
  local roll = Rng.Next(rng)
  local step = if roll < Wormholes.DEEPER then 1 elseif roll < Wormholes.DEEPER + Wormholes.LEVEL then 0 else -1
  return deep(state, rng, from, math.clamp(depth + step, 1, #Galaxy.DEPTHS))
end

-- Once a tick. Wormholes out of time close. Then, in the system the
-- pilot is flying in: if it is uncharted space and no wormhole is open
-- there, one opens that leads to the map (always a way out); and, once
-- a day, the system is asked whether one of its own opens.
function Wormholes.Step(state: State.State, events: { Event })
  for index = #state.wormholeIds, 1, -1 do
    local hole = state.wormholes[state.wormholeIds[index]]
    if state.tick >= hole.closes then
      close(state, hole, events)
    end
  end
  -- Every wormhole station that is lit holds one open: another, if the
  -- last has closed. (Lit as Assets/Starbases says, which is above this
  -- module: anchored, fuelled and not sealed.)
  for _, id in state.starbaseIds do
    local starbase = state.starbases[id]
    local tower = Structures.towerById[starbase.tower]
    local lit = state.tick >= starbase.ready and starbase.fuel > 0 and (starbase.sealed or 0) <= state.tick
    -- (a generator station with its Wormhole Generator online: the owner,
    -- 2026-11-18, the station "fueled AND the module installed")
    local generating: { string } = {}
    for _, module in starbase.modules do
      if state.tick >= module.ready then
        table.insert(generating, module.type)
      end
    end
    if tower and lit and Structures.Generating(generating) == "wormhole" and (starbase.hole == nil or state.wormholes[starbase.hole] == nil) then
      starbase.hole = nil
      local system = id // SPAN
      local station = describe(state, system).objects[id % SPAN]
      local rng = Rng.For(state.historySeed, id, state.tick, 99)
      local to = if station then Wormholes.Onward(state, system, rng) else nil
      local hole = if to and station then Wormholes.Open(state, system, to, rng, events, nil, true, station) else nil
      if hole then
        hole.station = id
        starbase.hole = hole.id
      end
    end
  end
  local ball = state.balls[state.player.ship]
  if ball == nil then
    return
  end
  local system = ball.system
  local node = state.galaxy.systems[system]
  local charted = Galaxy.Charted(state.galaxy)
  if charted >= #state.galaxy.systems then
    -- (a galaxy with no uncharted space has no wormholes)
    return
  end
  local day = state.tick // Wormholes.DAY
  if (state.wormholesRolled[system] or -1) < day then
    state.wormholesRolled[system] = day
    local rng = Rng.For(state.historySeed, system, day, 97)
    if node.uncharted then
      local depth = math.clamp(node.depth or 1, 1, #Wormholes.OUT)
      local out = Rng.Chance(rng, Wormholes.OUT[depth])
      local to = if out then nil else Wormholes.Onward(state, system, rng)
      Wormholes.Open(state, system, to or (1 + Rng.Int(rng, charted)), rng, events)
    elseif not node.home and Rng.Chance(rng, Wormholes.CHANCE[Galaxy.Band(node.security)] or 0) then
      local to = Wormholes.Onward(state, system, rng)
      if to then
        Wormholes.Open(state, system, to, rng, events)
      end
    end
  end
  if node.uncharted and #Wormholes.In(state, system) == 0 then
    local rng = Rng.For(state.historySeed, system, state.tick, 98)
    Wormholes.Open(state, system, 1 + Rng.Int(rng, charted), rng, events, #Wormholes.SIZES)
  end
end

return Wormholes
