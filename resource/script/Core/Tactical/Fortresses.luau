--!strict
-- Fortresses: the pirates' strongholds of a capital's size, one to a
-- region of lawless space (the owner's, 2026-11-22: capital-scale
-- fights, "pirate fortresses" among them, with the pirates' own
-- capitals at the heart of it).
--
-- Every region of the map that has lawless systems in it has one, in
-- one of them, once the pilot has come into the region: a citadel of
-- theirs, whose name the pilot hears. It is fought in stages:
--   - It stands behind a ring of batteries and redoubts, and cannot be
--     locked while any of them does.
--   - With the last of them down its guard comes: a Tyrant, a Despoiler
--     and a Warren with battlecruisers, led by one of the region's named
--     pirates (Tactical/Captains) in a Matriarch. It cannot be locked
--     while any of them is about either.
--   - Then it is open; and with its shield down to a quarter it seals
--     itself for hours (Fortresses.HOURS), and comes out of it with its
--     shield where it was: whoever is back then can bring it down. A day
--     after it opens (Fortresses.RESTOCK) it is resupplied, whole again,
--     its batteries with it, and its guard comes again when they are
--     down.
--   - Destroyed, it leaves what its commander kept (their own modules,
--     mutators, the best of the pirate site tier) and the drawings of one
--     of the pirates' capitals, which are found nowhere else; its
--     place is gone, and a day after (Fortresses.RESPAWN) another is put
--     up somewhere else in the region.
-- A Hoard lies by it, refining (Tactical/Pirates). Its guard's capitals
-- pay what capitals do (Pirates.CAPITAL_SHARE).
--
-- Nothing is in space until the pilot comes to the fortress's system:
-- until then it is a name on a list. (Every figure is mine.)

local Blueprints = require("@lt/Core/Data/Blueprints")
local Captains = require("@lt/Core/Tactical/Captains")
local Constants = require("@lt/Core/Data/Constants")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local Sites = require("@lt/Core/Tactical/Sites")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")

local Fortresses = {}

export type Event = { [string]: any }

local HOUR = math.floor(3600 / Constants.TICK + 0.5)

-- What its ring is, and how far out; who its guard is and who leads
-- them; how far off its Hoard lies.
Fortresses.RING_KINDS = { "redoubt", "battery", "redoubt", "battery", "redoubt", "battery" }
Fortresses.RING = { 9000, 14000 }
Fortresses.GUARD = { "tyrant", "despoiler", "warren", "brigand", "reaver", "brigand" }
Fortresses.LEADER = "matriarch"
Fortresses.OUT = 25000
Fortresses.HOARD = 6000
-- The share of its shield at which it seals, the hours it seals for, the
-- hours after it opens until it is whole again, and the hours after it
-- falls until another stands in the region.
Fortresses.QUARTER = 0.25
Fortresses.HOURS = 6
Fortresses.RESTOCK = 24
Fortresses.RESPAWN = 24
-- What its commander leaves: so many modules of their own, so many
-- mutators, so many of the pirate site tier's makes of the highest
-- grade, and pirate tags.
Fortresses.THEIRS = 3
Fortresses.MUTATORS = 4
Fortresses.SEIZED = 3
Fortresses.TAGS = 60

-- The lawless systems of the map in each region, worked out once for a
-- galaxy.
local lawless = { galaxy = nil :: any, regions = {} :: { [number]: { number } } }
local function regionOf(state: State.State, region: number): { number }
  if lawless.galaxy ~= state.galaxy then
    lawless.galaxy, lawless.regions = state.galaxy, {}
    for id = 1, Galaxy.Charted(state.galaxy) do
      local node = state.galaxy.systems[id]
      if Galaxy.Band(node.security) == "lawless" and not node.home then
        lawless.regions[node.region] = lawless.regions[node.region] or {}
        table.insert(lawless.regions[node.region], id)
      end
    end
  end
  return lawless.regions[region] or {}
end

-- The fortress a system holds, if one does.
function Fortresses.In(state: State.State, system: number): State.Fortress?
  for _, fortress in state.fortresses.list do
    if fortress.system == system then
      return fortress
    end
  end
  return nil
end

-- The fortress whose place, or whose core, an id is.
function Fortresses.Of(state: State.State, id: number): State.Fortress?
  for _, fortress in state.fortresses.list do
    if fortress.place == id or (fortress.core ~= 0 and fortress.core == id) then
      return fortress
    end
  end
  return nil
end

function Fortresses.Sealed(state: State.State, fortress: State.Fortress): boolean
  return fortress.sealed ~= 0 and state.tick < fortress.sealed
end

-- Who of a fortress's place stands round it: its ring (what does not
-- move), and its guard (what flies), but the core and the Hoard.
function Fortresses.Count(state: State.State, fortress: State.Fortress): (number, number)
  local ring, guard = 0, 0
  for _, id in state.pilotIds do
    local ball = state.balls[id]
    if ball and state.pilots[id].home == fortress.place and id ~= fortress.core and id ~= fortress.hoard then
      if ball.maxVelocity == 0 then
        ring += 1
      else
        guard += 1
      end
    end
  end
  return ring, guard
end

-- Why a fortress's core cannot be locked now, if it cannot.
function Fortresses.Covered(state: State.State, fortress: State.Fortress): string?
  if Fortresses.Sealed(state, fortress) then
    return "the fortress has sealed itself"
  end
  local ring, guard = Fortresses.Count(state, fortress)
  if ring > 0 then
    return "its batteries cover it: bring them down first"
  elseif guard > 0 or not fortress.guarded then
    return "its guard covers it: bring them down first"
  end
  return nil
end

local function ringed(state: State.State, fortress: State.Fortress, place: System.Object, rng: Rng.Rng)
  for index, kind in Fortresses.RING_KINDS do
    local turn = (index + Rng.Float(rng, -0.2, 0.2)) * 2 * math.pi / #Fortresses.RING_KINDS
    local out = Rng.Float(rng, Fortresses.RING[1], Fortresses.RING[2])
    Pirates.Spawn(state, Pirates.kindById[kind], fortress.system, place.x + out * math.cos(turn), place.y + Rng.Float(rng, -1500, 1500),
      place.z + out * math.sin(turn), place.id)
  end
end

local function hoarded(state: State.State, fortress: State.Fortress, place: System.Object, rng: Rng.Rng)
  local turn = Rng.Float(rng, 0, 2 * math.pi)
  local ball = Pirates.Spawn(state, Pirates.kindById.hoard, fortress.system, place.x + Fortresses.HOARD * math.cos(turn), place.y,
    place.z + Fortresses.HOARD * math.sin(turn), place.id)
  fortress.hoard = ball.id
end

-- Its place, its core, its ring and its Hoard, the first time the pilot
-- is in its system.
local function raise(state: State.State, fortress: State.Fortress, events: { Event })
  local system = fortress.system
  local objects = Space.Describe(state, system).objects
  if #objects + 12 >= Constants.STRUCTURE_ID_SPAN then
    return
  end
  local rng = Rng.For(state.historySeed, fortress.region, fortress.made, 2311)
  local planets: { System.Object } = {}
  for _, object in objects do
    if object.kind == "planet" then
      table.insert(planets, object)
    end
  end
  local near = if #planets > 0 then planets[Rng.Int(rng, #planets) + 1] else objects[1]
  local angle, out = Rng.Float(rng, 0, 2 * math.pi), math.max(near.radius * 10, 2e6)
  local place: System.Object = {
    id = system * Constants.STRUCTURE_ID_SPAN + #objects + 1, kind = "belt", name = `{state.galaxy.systems[system].name} - Pirate Fortress`,
    x = near.x + out * math.cos(angle), y = near.y, z = near.z + out * math.sin(angle), radius = 0, seed = Rng.Int(rng, 2 ^ 31),
    parent = near.id, site = 0, variety = "site.fortress", to = 0,
  }
  place.site = place.id
  table.insert(objects, place)
  state.sites[place.id] = { id = place.id, system = system, kind = "fortress", code = "", strength = 1, expires = 2 ^ 52, gone = false,
    depth = 0, led = false }
  table.insert(state.siteIds, place.id)
  fortress.place = place.id
  local core = Pirates.Spawn(state, Pirates.kindById.fortress, system, place.x, place.y, place.z, place.id)
  fortress.core = core.id
  ringed(state, fortress, place, rng)
  hoarded(state, fortress, place, rng)
  table.insert(events, { kind = "FortressRaised", site = place.id, system = system })
end

-- Its guard comes: the capitals and their escort, led by name.
local function guard(state: State.State, fortress: State.Fortress, place: System.Object, events: { Event })
  local rng = Rng.For(state.historySeed, fortress.place, state.tick, 2313)
  for index, kind in Fortresses.GUARD do
    local turn = index * 2 * math.pi / #Fortresses.GUARD + Rng.Float(rng, -0.1, 0.1)
    local ball = Pirates.Spawn(state, Pirates.kindById[kind], fortress.system, place.x + Fortresses.OUT * math.cos(turn),
      place.y + Rng.Float(rng, -2000, 2000), place.z + Fortresses.OUT * math.sin(turn), place.id)
    table.insert(events, { kind = "BallAdded", ball = ball.id })
  end
  local was = Captains.Get(state, fortress.captain)
  local leader: State.Captain = if was and was.alive then was else Captains.Pick(state, fortress.system, fortress.place + state.tick)
  fortress.captain = leader.id
  local ball = Pirates.Spawn(state, Pirates.kindById[Fortresses.LEADER], fortress.system, place.x + Fortresses.OUT, place.y,
    place.z, place.id)
  local called = Captains.Called(leader, 2, "")
  ball.name = called
  state.ships[ball.id].name = called
  state.ships[ball.id].skill = Pirates.OFFICER
  state.pilots[ball.id].captain = leader.id
  state.pilots[ball.id].bounty = math.floor(state.pilots[ball.id].bounty * Captains.Price(leader))
  table.insert(events, { kind = "BallAdded", ball = ball.id })
  fortress.guarded = true
  table.insert(events, { kind = "FortressGuard", site = fortress.place, system = fortress.system, name = called })
end

-- A pirate has been destroyed ('ship', of the place 'home': Tactical/
-- Aftermath asks of every one): if it was a fortress, it is fallen, and
-- what it had is in its wreck.
function Fortresses.Fell(state: State.State, ship: number, home: number, events: { Event })
  local fortress = Fortresses.Of(state, home)
  if fortress == nil or fortress.core ~= ship then
    return
  end
  local wreck = state.wrecks[state.wreckIds[#state.wreckIds] or 0]
  local leader = Captains.Get(state, fortress.captain)
  local name = if leader then leader.name else "their commander"
  if wreck and wreck.system == fortress.system then
    local rng = Rng.For(state.historySeed, fortress.place, 2317)
    Pirates.Officer(state, wreck.id, name, Pirates.kindById[Fortresses.LEADER], rng, Fortresses.THEIRS, Fortresses.MUTATORS)
    Sites.Seized(state, Rng.For(state.historySeed, wreck.id, 2319), wreck.id, 3, Fortresses.SEIZED)
    Items.Add(state, "tag.pirate", Fortresses.TAGS, wreck.id, "cargo")
    -- (the drawings of one of the pirates' capitals: found here, and nowhere else)
    local prints: { string } = {}
    for _, print in Blueprints.OfPeople("unbound").hulls do
      local hull = Ships.byId[print.product]
      if hull and Ships.Capital(hull.class) and hull.class ~= "capitalindustrial" then
        table.insert(prints, print.id)
      end
    end
    if #prints > 0 then
      Items.Add(state, prints[Rng.Int(rng, #prints) + 1], 1, wreck.id, "cargo")
    end
  end
  state.fortresses.list[fortress.region] = nil
  state.fortresses.fell[fortress.region] = state.tick
  table.insert(events, { kind = "FortressLost", site = fortress.place, system = fortress.system,
    name = `{state.galaxy.systems[fortress.system].name} - Pirate Fortress` })
  Sites.Release(state, fortress.place, events)
end

-- Once a tick: the region the pilot is in has its fortress (made known
-- when it is first put on the list, or again after one fell); the
-- fortress of the system the pilot is in is put in space if it is not;
-- and each that stands brings its guard when its ring is down, seals,
-- opens and is resupplied.
function Fortresses.Step(state: State.State, events: { Event })
  local me = state.balls[state.player.ship]
  if me and not state.peaceful then
    local node = state.galaxy.systems[me.system]
    local region = node.region
    local all = state.fortresses
    if not node.uncharted and all.list[region] == nil and state.tick - (all.fell[region] or -1e12) >= Fortresses.RESPAWN * HOUR then
      local where = regionOf(state, region)
      if #where > 0 then
        all.made += 1
        local rng = Rng.For(state.historySeed, region, all.made, 2309)
        local system = where[Rng.Int(rng, #where) + 1]
        all.list[region] = { region = region, system = system, made = all.made, place = 0, core = 0, hoard = 0, captain = 0,
          guarded = false, sealed = 0, charges = Fortresses.HOURS, restock = 0, cover = "" }
        table.insert(events, { kind = "FortressKnown", system = system })
      end
    end
    local here = all.list[region]
    if here and here.system == me.system and here.place == 0 then
      raise(state, here, events)
    end
  end
  for _, fortress in state.fortresses.list do
    local core = state.balls[fortress.core]
    local place = Space.Object(state, fortress.place)
    if core == nil or place == nil then
      continue
    end
    if fortress.sealed ~= 0 and state.tick >= fortress.sealed then
      fortress.sealed = 0
      core.vitals.shield = Fortresses.QUARTER * core.vitals.shieldMax
      table.insert(events, { kind = "FortressOpened", site = fortress.place, system = fortress.system })
    end
    local sealed = Fortresses.Sealed(state, fortress)
    local ring = Fortresses.Count(state, fortress)
    if not sealed and fortress.charges == 0 and fortress.restock ~= 0 and state.tick >= fortress.restock then
      -- (resupplied: whole again, its ring with it, and a guard to come when that is down)
      fortress.charges, fortress.restock, fortress.guarded = Fortresses.HOURS, 0, false
      core.vitals.shield, core.vitals.armor, core.vitals.hull = core.vitals.shieldMax, core.vitals.armorMax, core.vitals.hullMax
      if ring == 0 then
        ringed(state, fortress, place, Rng.For(state.historySeed, fortress.place, state.tick, 2321))
      end
      if state.balls[fortress.hoard] == nil then
        hoarded(state, fortress, place, Rng.For(state.historySeed, fortress.place, state.tick, 2323))
      end
      table.insert(events, { kind = "FortressRestocked", site = fortress.place, system = fortress.system })
    elseif ring == 0 and not fortress.guarded and me and me.system == fortress.system and me.grid == fortress.place then
      guard(state, fortress, place, events)
    end
    local share = core.vitals.shield / math.max(1, core.vitals.shieldMax)
    if not sealed and share <= Fortresses.QUARTER and fortress.charges > 0 then
      local hours = fortress.charges
      fortress.sealed = state.tick + hours * HOUR
      fortress.charges = 0
      fortress.restock = fortress.sealed + Fortresses.RESTOCK * HOUR
      core.vitals.shield = math.max(core.vitals.shield, Fortresses.QUARTER * core.vitals.shieldMax)
      table.insert(events, { kind = "FortressSealed", site = fortress.place, system = fortress.system, hours = hours,
        opens = fortress.sealed })
    end
    -- (why it cannot be locked, for Tactical/Combat, which asks the state)
    fortress.cover = Fortresses.Covered(state, fortress) or ""
  end
end

return Fortresses
