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
  if Rng.Chance(rng, 0.5) then
    local module = Modules.list[Rng.Int(rng, #Modules.list) + 1]
    Items.Add(state, if Rng.Chance(rng, 0.15) then "blueprint." .. module.id else module.id, 1, wreck, "cargo")
  end
end

local function addWreck(state: State.State, name: string, system: number, grid: number, x: number, y: number, z: number, radius: number,
  expires: number): number
  local wreck: State.Wreck = {
    id = State.NewId(state), kind = "wreck", name = name, system = system, grid = grid, x = x, y = y, z = z, radius = radius,
    hull = "", expires = expires, salvaged = false,
  }
  state.wrecks[wreck.id] = wreck
  table.insert(state.wreckIds, wreck.id)
  return wreck.id
end

-- Make a site in a system: a place in its description, and what is
-- there. Nothing is made if the description is nearly full.
local function make(state: State.State, system: number, rng: Rng.Rng, events: { Event })
  local description = Space.Describe(state, system)
  local objects = description.objects
  if #objects + 40 >= Constants.STRUCTURE_ID_SPAN then
    return
  end
  local planets: { System.Object } = {}
  for _, object in objects do
    if object.kind == "planet" then
      table.insert(planets, object)
    end
  end
  if #planets == 0 then
    return
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
  local place = add("belt", `{NAMES[kind]} {code}`, x, y, z, 0, planet.id, "site." .. kind)
  place.site = place.id
  local expires = state.tick + Sites.LIFE
  state.sites[place.id] = {
    id = place.id, system = system, kind = kind, code = code, strength = if Sites.SCANS[kind] <= 0 then 1 else 0,
    expires = expires, gone = false,
  }
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
    local rich = if band == "secure" then 1 elseif band == "low" then 2 else 4
    local hulls = if kind == "combat" then 1 else 2 + Rng.Int(rng, 2)
    for h = 1, hulls do
      local wreck = addWreck(state, if kind == "combat" then "Pirate Stores" else "Derelict Hull", system, place.id,
        x + Rng.Float(rng, -6000, 6000), y + Rng.Float(rng, -1500, 1500), z + Rng.Float(rng, -6000, 6000),
        Rng.Float(rng, 50, 140), expires)
      loot(state, rng, wreck, rich)
      if kind == "combat" then
        loot(state, rng, wreck, rich)
        Items.Add(state, "tag.pirate", 2 * rich, wreck, "cargo")
        Items.Add(state, "ammo.fusion", 500 * rich, wreck, "cargo")
      end
    end
  end
  table.insert(events, { kind = "SiteAppeared", site = place.id, system = system, what = kind })
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
  elseif command.kind ~= "Scan" then
    return false, `unknown command '{command.kind}'`
  elseif state.tick < state.scanReady then
    return false, "the scanner is still cycling"
  end
  return true
end

function Sites.Apply(state: State.State, command: State.Command, events: { Event })
  local ball = state.balls[command.actor]
  state.scanReady = state.tick + Sites.SCAN
  local found, signals = 0, 0
  for _, site in Sites.In(state, ball.system) do
    if site.strength < 1 then
      site.strength = math.min(1, site.strength + Sites.Gain(state, site.kind))
      if site.strength >= 1 then
        found += 1
      else
        signals += 1
      end
    end
  end
  table.insert(events, { kind = "Scanned", ball = ball.id, system = ball.system, found = found, signals = signals })
end

return Sites
