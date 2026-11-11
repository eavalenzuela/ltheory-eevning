--!strict
-- Sites: places that are not on anybody's chart.
--
-- A system has a few places in it worth finding, more of them the less
-- safe it is, of three kinds:
--   - a pirate den: a pack a kind of space tougher than the belts bring,
--     and the pirates' stores to be looted;
--   - a hidden belt: big rocks, some of the rare ores even where order
--     is kept;
--   - a derelict: hulls adrift with what was aboard them.
-- A den shows on a ship's scanner at once (it is not hiding). The others
-- are signals that have to be worked: every scan brings each one nearer
-- to being found, and a found site can be warped to like any other
-- place. A site lasts a day or two, or until it is cleaned out, and
-- another turns up somewhere else in the system a while after.
--
-- A site is a place added to its system's description (as a pilot's
-- starbase is), so that warping, grids, mining and pirates all know it
-- as they know a belt. What makes it a site is kept here: what kind it
-- is, how far a scanner has got with it, and when it goes. Only the
-- system the pilot is in gets new ones.
--
-- (EVE's exploration, cut down. Not yet: probes to place, a hacking
-- game, gas, sites that lead on to others, anything a pilot cannot
-- reach with the ship's own scanner.)

local Components = require("@lt/Core/Data/Components")
local Constants = require("@lt/Core/Data/Constants")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Mining = require("@lt/Core/Tactical/Mining")
local Modules = require("@lt/Core/Data/Modules")
local Ores = require("@lt/Core/Data/Ores")
local Rng = require("@lt/Core/Kernel/Rng")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")

local Sites = {}

export type Event = { [string]: any }

-- Sites a system has at once, by how safe it is.
Sites.COUNT = { secure = 2, low = 3, lawless = 4 } :: { [string]: number }
-- Ticks between one look at a system's sites and the next: what has been
-- cleaned out goes, and if there is room for another, one comes.
Sites.CHECK = 600
-- Ticks a site lasts if nobody cleans it out.
Sites.LIFE = 129600
-- Ticks a scan takes: the scanner cannot be used again until it is done.
Sites.SCAN = 8
-- Scans it takes to find a site of a kind with no skill at it (a den is
-- found before the first). Each level of Astrometrics makes every scan
-- worth a tenth more.
Sites.SCANS = { combat = 0, ore = 3, relic = 4 } :: { [string]: number }
local NAMES: { [string]: string } = { combat = "Pirate Den", ore = "Hidden Belt", relic = "Derelict" }
-- How likely each kind is, by how safe the system is: combat, ore, relic.
local ODDS: { [string]: { number } } = { secure = { 0.4, 0.35, 0.25 }, low = { 0.45, 0.25, 0.3 }, lawless = { 0.5, 0.2, 0.3 } }
local KINDS = { "combat", "ore", "relic" }

-- What a scan adds to a site's signal: all of it at once for a den.
function Sites.Gain(state: State.State, kind: string): number
  local scans = Sites.SCANS[kind] or 1
  if scans <= 0 then
    return 1
  end
  return (1 + 0.1 * math.max(0, state.skills.astrometrics or 0)) / scans + 1e-9
end

-- Probes. A scan probe is put out where the ship is and stays there
-- for an hour. A signal with a probe within an astronomical unit of it
-- is scanned that much better: each probe that near makes a scan worth
-- as much again. And a derelict cannot be pinned down without one: the
-- ship's own scanner gets it half way, and no further, unless a probe
-- (or the ship itself) is that near it. The scanner says which planet
-- a signal is by, which is where to take a probe.
Sites.PROBE = "probe.scan"
Sites.PROBES = 4              -- a pilot has so many out at once, at most
Sites.PROBE_LIFE = 3600       -- ticks
Sites.PROBE_RANGE = Constants.AU
-- How far the ship's scanner alone gets with a site of a kind (1: all the way).
Sites.ALONE = { combat = 1, ore = 1, relic = 0.5 } :: { [string]: number }

-- The probes a pilot has out in a system, in the order they were put out.
function Sites.Probes(state: State.State, system: number): { State.Probe }
  local found: { State.Probe } = {}
  for _, id in state.probeIds do
    if state.probes[id].system == system then
      table.insert(found, state.probes[id])
    end
  end
  return found
end

-- How many probes are near enough a site to help with it, and whether
-- anything of the pilot's is (a probe, or 'ball', the ship itself).
function Sites.Covered(state: State.State, site: State.Site, ball: State.Ball?): (number, boolean)
  local place = Space.Object(state, site.id)
  if place == nil then
    return 0, false
  end
  local near = 0
  for _, probe in Sites.Probes(state, site.system) do
    if (probe.x - place.x) ^ 2 + (probe.y - place.y) ^ 2 + (probe.z - place.z) ^ 2 <= Sites.PROBE_RANGE ^ 2 then
      near += 1
    end
  end
  local ship = ball ~= nil and ball.system == site.system
    and (ball.x - place.x) ^ 2 + (ball.y - place.y) ^ 2 + (ball.z - place.z) ^ 2 <= Sites.PROBE_RANGE ^ 2
  return near, near > 0 or ship
end

-- The sites of a system that are still there, in the order they came.
function Sites.In(state: State.State, system: number): { State.Site }
  local found: { State.Site } = {}
  for _, id in state.siteIds do
    local site = state.sites[id]
    if site.system == system and not site.gone then
      table.insert(found, site)
    end
  end
  return found
end

-- Whether a place of a system's description is one a pilot cannot see
-- on the overview: a site not found yet, or one that has gone.
function Sites.Hidden(state: State.State, id: number): boolean
  local site = state.sites[id]
  return site ~= nil and (site.gone or site.strength < 1)
end

local function loot(state: State.State, rng: Rng.Rng, wreck: number, rich: number)
  local parts = Components.list
  for _ = 1, 2 do
    local part = parts[Rng.Int(rng, #parts) + 1]
    Items.Add(state, part.id, math.floor((10 + Rng.Int(rng, 40)) * rich), wreck, "cargo")
  end
  Items.Add(state, "scrap.metal", math.floor((8 + Rng.Int(rng, 30)) * rich), wreck, "cargo")
  -- Now and then something that was fitted, or the drawings for it.
  -- (a plain one: the tech 2 make of anything is nobody's to find)
  if Rng.Chance(rng, 0.5) then
    local module = Modules.list[Rng.Int(rng, #Modules.list) + 1]
    if module.tech == 2 and module.base then
      module = Modules.byId[module.base]
    elseif module.internal then
      module = Modules.byId["miner.small"]
    end
    Items.Add(state, if Rng.Chance(rng, 0.15) then "blueprint." .. module.id else module.id, 1, wreck, "cargo")
  end
end

local function addWreck(state: State.State, name: string, system: number, grid: number, x: number, y: number, z: number, radius: number,
  expires: number): number
  local wreck: State.Wreck = {
    id = State.NewId(state), kind = "wreck", name = name, system = system, grid = grid, x = x, y = y, z = z, radius = radius,
    hull = "", expires = expires, salvaged = false, locked = false,
  }
  state.wrecks[wreck.id] = wreck
  table.insert(state.wreckIds, wreck.id)
  return wreck.id
end

-- Make a site in a system: a place in its description, and what is
-- there. Nothing is made if the description is nearly full. With
-- 'depth' it is a stronghold on a den's trail: a den, found already,
-- with more in its stores. Returns the site made, if one was.
local function make(state: State.State, system: number, rng: Rng.Rng, events: { Event }, depth: number?): State.Site?
  local description = Space.Describe(state, system)
  local objects = description.objects
  if #objects + 40 >= Constants.STRUCTURE_ID_SPAN then
    return nil
  end
  local planets: { System.Object } = {}
  for _, object in objects do
    if object.kind == "planet" then
      table.insert(planets, object)
    end
  end
  if #planets == 0 then
    return nil
  end
  local band = Galaxy.Band(state.galaxy.systems[system].security)
  local roll, kind = Rng.Next(rng), "relic"
  for index, share in ODDS[band] do
    roll -= share
    if roll < 0 then
      kind = KINDS[index]
      break
    end
  end
  local deep = depth or 0
  if deep > 0 then
    kind = "combat"
  end
  -- Somewhere out from a planet, well clear of it.
  local planet = planets[Rng.Int(rng, #planets) + 1]
  local angle, out = Rng.Float(rng, 0, 2 * math.pi), planet.radius * Rng.Float(rng, 6, 14)
  local x, y, z = planet.x + out * math.cos(angle), planet.y + out * Rng.Float(rng, -0.1, 0.1), planet.z + out * math.sin(angle)
  local code = string.format("%s%s-%03d", string.char(65 + Rng.Int(rng, 26)), string.char(65 + Rng.Int(rng, 26)), Rng.Int(rng, 1000))
  local function add(what: System.Kind, name: string, ox: number, oy: number, oz: number, radius: number, parent: number,
    variety: string): System.Object
    local object: System.Object = {
      id = system * Constants.STRUCTURE_ID_SPAN + #objects + 1, kind = what, name = name, x = ox, y = oy, z = oz, radius = radius,
      seed = Rng.Int(rng, 2 ^ 31), parent = parent, site = 0, variety = variety, to = 0,
    }
    table.insert(objects, object)
    return object
  end
  local place = add("belt", `{if deep > 0 then "Pirate Stronghold" else NAMES[kind]} {code}`, x, y, z, 0, planet.id, "site." .. kind)
  place.site = place.id
  local expires = state.tick + Sites.LIFE
  local site: State.Site = {
    id = place.id, system = system, kind = kind, code = code, strength = if Sites.SCANS[kind] <= 0 then 1 else 0,
    expires = expires, gone = false, depth = deep, led = false,
  }
  state.sites[place.id] = site
  table.insert(state.siteIds, place.id)

  if kind == "ore" then
    -- Big rocks along an arc, as a belt's are, and a third of them of
    -- the rare ores wherever it is.
    local start = Rng.Float(rng, 0, 2 * math.pi)
    local rocks = 10 + Rng.Int(rng, 9)
    for r = 1, rocks do
      local along = start + (r / rocks) * math.pi * Rng.Float(rng, 0.9, 1.1)
      local far = Rng.Float(rng, 10000, 20000)
      local ore = Ores.Pick(Rng.Next(rng), band == "lawless" or Rng.Chance(rng, 0.35))
      local rock = add("asteroid", ore.name, x + far * math.cos(along), y + Rng.Float(rng, -4000, 4000), z + far * math.sin(along),
        Rng.Float(rng, 500, 1200), place.id, ore.id)
      rock.site = place.id
    end
  else
    -- Hulls adrift (or, at a den, the pirates' stores) with things aboard.
    local rich = (if band == "secure" then 1 elseif band == "low" then 2 else 4) * (1 + 2 * deep)
    local hulls = if kind == "combat" then 1 else 2 + Rng.Int(rng, 2)
    for h = 1, hulls do
      local wreck = addWreck(state, if kind == "combat" then "Pirate Stores" else "Derelict Hull", system, place.id,
        x + Rng.Float(rng, -6000, 6000), y + Rng.Float(rng, -1500, 1500), z + Rng.Float(rng, -6000, 6000),
        Rng.Float(rng, 50, 140), expires)
      loot(state, rng, wreck, rich)
      -- (a derelict's hold is sealed: Tactical/Hacking. And it has what
      -- an invention is worked out from: Assets/Industry)
      if kind == "relic" then
        state.wrecks[wreck].locked = true
        Items.Add(state, "datacore", (1 + Rng.Int(rng, 2)) * rich, wreck, "cargo")
      end
      if kind == "combat" then
        loot(state, rng, wreck, rich)
        Items.Add(state, "tag.pirate", 2 * rich, wreck, "cargo")
        Items.Add(state, "ammo.fusion", 500 * rich, wreck, "cargo")
      end
    end
  end
  table.insert(events, { kind = "SiteAppeared", site = place.id, system = system, what = kind })
  return site
end

-- The chance that a den's stores, once emptied, say where another is.
Sites.TRAIL = 0.4

-- A den's stores have been emptied: now and then there is something in
-- them that says where the pack's stronghold is. It is in the least
-- safe system a jump away (the den's own, if none is less safe than
-- it), found already and on the overview there for a day and a half;
-- the pack that keeps it is the worst there is, and its stores are
-- three times a den's. A stronghold leads nowhere further.
function Sites.Lead(state: State.State, site: State.Site, events: { Event })
  if site.kind ~= "combat" or site.led or site.depth > 0 then
    return
  end
  site.led = true
  local rng = Rng.For(state.historySeed, site.id, 93)
  if not Rng.Chance(rng, Sites.TRAIL) then
    return
  end
  local to = site.system
  for _, neighbor in state.galaxy.systems[site.system].neighbors do
    if state.galaxy.systems[neighbor].security < state.galaxy.systems[to].security then
      to = neighbor
    end
  end
  local stronghold = make(state, to, rng, events, 1)
  if stronghold then
    local place = Space.Object(state, stronghold.id)
    table.insert(events, { kind = "TrailFound", from = site.id, site = stronghold.id, system = to,
      name = if place then place.name else "a stronghold" })
  end
end

-- Whether there is anything left at a site worth its being there.
local function spent(state: State.State, site: State.Site): boolean
  if site.kind == "ore" then
    for _, object in Space.Describe(state, site.system).objects do
      if object.kind == "asteroid" and object.site == site.id and Mining.Left(state, object) > 0 then
        return false
      end
    end
    return true
  end
  for _, id in state.wreckIds do
    local wreck = state.wrecks[id]
    if wreck.grid == site.id and wreck.system == site.system and #Items.In(state, id, "cargo") > 0 then
      return false
    end
  end
  return true
end

-- Once a tick: now and then, in the system the pilot is in, sites that
-- are spent or out of time go, and one comes if there is room.
function Sites.Step(state: State.State, events: { Event })
  -- (a probe that has run down is gone)
  for index = #state.probeIds, 1, -1 do
    local probe = state.probes[state.probeIds[index]]
    if state.tick >= probe.expires then
      state.probes[probe.id] = nil
      table.remove(state.probeIds, index)
      table.insert(events, { kind = "ProbeLost", probe = probe.id })
    end
  end
  local me = state.ships[state.player.ship]
  if me == nil then
    return
  end
  local ball = state.balls[me.id]
  local system = if ball then ball.system else Space.SystemOf(state, me.docked)
  if state.tick < (state.sitesDue[system] or 0) then
    return
  end
  state.sitesDue[system] = state.tick + Sites.CHECK
  local here = Sites.In(state, system)
  local left = #here
  for _, site in here do
    -- (never from under the pilot)
    local present = ball ~= nil and ball.grid == site.id
    if not present and (state.tick >= site.expires or spent(state, site)) then
      site.gone = true
      left -= 1
      table.insert(events, { kind = "SiteGone", site = site.id, system = system })
    end
  end
  local band = Galaxy.Band(state.galaxy.systems[system].security)
  -- (a system new to the pilot is found with all of its sites; after
  -- that they come one at a time)
  local wanted = if state.sitesSeen[system] == nil then Sites.COUNT[band] - left else math.min(1, Sites.COUNT[band] - left)
  state.sitesSeen[system] = true
  for index = 1, wanted do
    make(state, system, Rng.For(state.historySeed, state.tick, system, index, 91), events)
  end
end

function Sites.Validate(state: State.State, command: State.Command): (boolean, string?)
  local ball = state.balls[command.actor]
  if state.ships[command.actor] == nil then
    return false, "no such ship"
  elseif ball == nil then
    return false, "docked"
  elseif ball.warp and ball.warp.stage == "warp" then
    return false, "in warp"
  elseif command.kind == "LaunchProbe" then
    local carried = false
    for _, item in Items.In(state, ball.id, "cargo") do
      carried = carried or item.type == Sites.PROBE
    end
    if not carried then
      return false, "no scan probe in the hold"
    elseif #state.probeIds >= Sites.PROBES then
      return false, `{Sites.PROBES} probes are out already`
    end
    return true
  elseif command.kind == "RecallProbes" then
    if #Sites.Probes(state, ball.system) == 0 then
      return false, "no probes are out in this system"
    end
    return true
  elseif command.kind ~= "Scan" then
    return false, `unknown command '{command.kind}'`
  elseif state.tick < state.scanReady then
    return false, "the scanner is still cycling"
  end
  return true
end

function Sites.Apply(state: State.State, command: State.Command, events: { Event })
  local ball = state.balls[command.actor]
  if command.kind == "LaunchProbe" then
    for _, item in Items.In(state, ball.id, "cargo") do
      if item.type == Sites.PROBE then
        Items.Take(state, item, 1)
        break
      end
    end
    local probe: State.Probe = { id = State.NewId(state), system = ball.system, x = ball.x, y = ball.y, z = ball.z,
      expires = state.tick + Sites.PROBE_LIFE }
    state.probes[probe.id] = probe
    table.insert(state.probeIds, probe.id)
    table.insert(events, { kind = "ProbeLaunched", ball = ball.id, probe = probe.id, out = #state.probeIds })
    return
  elseif command.kind == "RecallProbes" then
    -- (those in this system come back to the hold, wherever they are in it)
    local back = 0
    for _, probe in Sites.Probes(state, ball.system) do
      state.probes[probe.id] = nil
      State.RemoveId(state.probeIds, probe.id)
      back += 1
    end
    Items.Add(state, Sites.PROBE, back, ball.id, "cargo")
    table.insert(events, { kind = "ProbesRecalled", ball = ball.id, count = back })
    return
  end
  state.scanReady = state.tick + Sites.SCAN
  local found, signals, faint = 0, 0, 0
  for _, site in Sites.In(state, ball.system) do
    if site.strength < 1 then
      -- (each probe near it makes the scan worth as much again; and
      -- without anything near it, a faint one is got only so far)
      local probes, near = Sites.Covered(state, site, ball)
      local reach = if near then 1 else Sites.ALONE[site.kind] or 1
      if site.strength < reach then
        site.strength = math.min(reach, site.strength + Sites.Gain(state, site.kind) * (1 + probes))
      end
      if site.strength >= 1 then
        found += 1
      else
        signals += 1
        faint += if not near and site.strength >= reach then 1 else 0
      end
    end
  end
  table.insert(events, { kind = "Scanned", ball = ball.id, system = ball.system, found = found, signals = signals, faint = faint })
end

return Sites
