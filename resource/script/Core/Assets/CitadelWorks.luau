--!strict
-- CitadelWorks: what a citadel's observatory and miners do (the owner's
-- rulings, 2026-11-18).
--
-- A research station's Observatory finds the signals of its system for
-- its owner, one at a time, the nearest to it first: about a minute for
-- most, the hardest two and a half (Sites.SCANS says how hard each kind
-- is: a hidden belt or a vapour field is a minute, a derelict nearly two
-- and a listening post two and a half). A signal found is found as a
-- probe scan finds it: on the overview, to warp to.
--
-- A refinery's miners bring up, every hour, as much of each thing there
-- is for them to mine as a tech 2 mining laser would in that hour, as
-- many times over as the citadel's size (1 small to 5 huge), into its
-- hangar: the Asteroid Miner of each ore its system's belts hold, the
-- Moon Miner of the material of the moon it is anchored at, the Planet
-- Miner of each raw material of the planet it is anchored at. Nothing is
-- taken out of a belt (the owner's: it is what the citadel itself is
-- for, and a mining fleet does better).
--
-- Only while the citadel is lit and the module online.
local Constants = require("@lt/Core/Data/Constants")
local Corporation = require("@lt/Core/Assets/Corporation")
local Modules = require("@lt/Core/Data/Modules")
local Mining = require("@lt/Core/Tactical/Mining")
local Planets = require("@lt/Core/Data/Planets")
local Sites = require("@lt/Core/Tactical/Sites")
local Space = require("@lt/Core/Tactical/Space")
local Starbases = require("@lt/Core/Assets/Starbases")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local Items = require("@lt/Core/Assets/Items")
local Types = require("@lt/Core/Data/Types")

export type Event = { [string]: any }

local CitadelWorks = {}

local HOUR = math.floor(3600 / Constants.TICK + 0.5)

-- The seconds the observatory takes over a signal of a kind: a minute
-- for one a ship's scanner finds in three scans or fewer, and three
-- quarters of a minute more for each scan more, two and a half at most.
function CitadelWorks.Seconds(kind: string): number
  local scans = Sites.SCANS[kind] or 3
  return math.min(150, 60 + 45 * math.max(0, scans - 3))
end

-- What a tech 2 mining laser brings up in an hour, m3.
local function laserHour(): number
  local laser = Modules.byId["miner.small.ii"] or Modules.byId["miner.small"]
  local miner = assert(laser and laser.miner)
  return miner.volume * 3600 / miner.duration
end

-- The module online in a citadel that works at something, by what.
local function working(state: State.State, starbase: State.Starbase, works: string): Structures.ModuleType?
  if not Starbases.Lit(state, starbase) then
    return nil
  end
  for _, fitted in starbase.modules do
    local module = Structures.moduleById[fitted.type]
    if module.works == works and state.tick >= fitted.ready then
      return module
    end
  end
  return nil
end

-- What a citadel's miners bring up in an hour: each thing, and how many
-- units of it. (What would be, with every miner it has fitted online.)
export type Yield = { type: string, units: number, by: string }
function CitadelWorks.Mining(state: State.State, starbase: State.Starbase): { Yield }
  local tower = Structures.towerById[starbase.tower]
  local out: { Yield } = {}
  if not tower.citadel then
    return out
  end
  local m3 = laserHour() * tower.size
  local function add(type: string, by: string)
    local info = Types.Info(type)
    local volume = math.max(info.volume or 1, 1e-3)
    table.insert(out, { type = type, units = math.floor(m3 / volume), by = by })
  end
  local system = Space.SystemOf(state, starbase.id)
  local body = Space.Object(state, Starbases.Moon(state, starbase))
  for _, fitted in starbase.modules do
    local module = Structures.moduleById[fitted.type]
    if module.works == "asteroid" then
      -- (each ore that the system's belts hold, in the order they lie)
      local description = state.systems[system]
      local seen: { [string]: boolean } = {}
      if description then
        for _, object in description.objects do
          local parent = if object.kind == "asteroid" then Space.Object(state, object.parent) else nil
          -- (rock: not ice, and not a cloud of gas)
          if parent and parent.kind == "belt" and Mining.Rock(object) and not seen[object.variety] and Types.Info(object.variety) then
            seen[object.variety] = true
            add(object.variety, module.id)
          end
        end
      end
    elseif module.works == "moon" and body and body.kind == "moon" then
      local deposit = Starbases.Deposit(state, body.id)
      if deposit then
        add(deposit.material.id, module.id)
      end
    elseif module.works == "planet" and body and body.kind == "planet" then
      for _, deposit in Planets.Deposits(body.variety, body.seed) do
        add(deposit.raw, module.id)
      end
    end
  end
  return out
end

-- The signal a citadel's observatory is working at, and how far it has
-- got with it (0 to 1): nil when it is not working at one.
function CitadelWorks.Observing(state: State.State, starbase: State.Starbase): (State.Site?, number)
  local site = state.sites[starbase.observing or 0]
  if site == nil or site.gone or site.strength >= 1 or working(state, starbase, "observatory") == nil then
    return nil, 0
  end
  return site, site.strength
end

-- The next signal for an observatory: the nearest to it in its system
-- that is not found yet (and not part of a job's camp, which no scanner
-- finds before the job opens it).
local function nearest(state: State.State, starbase: State.Starbase): State.Site?
  local here = Space.Object(state, starbase.id)
  if here == nil then
    return nil
  end
  local best: State.Site? = nil
  local bestGap = math.huge
  for _, site in Sites.In(state, Space.SystemOf(state, starbase.id)) do
    local object = Space.Object(state, site.id)
    if site.strength < 1 and site.kind ~= "mission" and object then
      local gap = (object.x - here.x) ^ 2 + (object.y - here.y) ^ 2 + (object.z - here.z) ^ 2
      if gap < bestGap then
        best, bestGap = site, gap
      end
    end
  end
  return best
end

function CitadelWorks.Step(state: State.State, events: { Event })
  for _, id in state.starbaseIds do
    local starbase = state.starbases[id]
    local tower = Structures.towerById[starbase.tower]
    if tower.citadel then
      -- The observatory: a second more at the signal it is at, or the next one.
      if working(state, starbase, "observatory") then
        local site: State.Site? = state.sites[starbase.observing or 0]
        if site == nil or site.gone or site.strength >= 1 then
          site = nearest(state, starbase)
          starbase.observing = if site then site.id else 0
        end
        if site then
          site.strength = math.min(1, site.strength + Constants.TICK / CitadelWorks.Seconds(site.kind))
          if site.strength >= 1 then
            table.insert(events, { kind = "ObservatoryFound", station = id, site = site.id, system = site.system })
            starbase.observing = 0
          end
        end
      end
      -- The miners: their hour runs from when the first of them came online, and only while it is lit.
      local since = 0
      if Starbases.Lit(state, starbase) then
        for _, fitted in starbase.modules do
          if Structures.moduleById[fitted.type].works and Structures.moduleById[fitted.type].works ~= "observatory"
            and state.tick >= fitted.ready then
            since = if since == 0 then math.max(starbase.mined or 0, fitted.ready) else math.min(since, math.max(starbase.mined or 0, fitted.ready))
          end
        end
      end
      if since == 0 then
        starbase.mined = state.tick
      elseif state.tick - since >= HOUR then
        starbase.mined = since + HOUR
        for _, yield in CitadelWorks.Mining(state, starbase) do
          -- (what an online miner brings up: one fitted and not yet online brings nothing yet)
          local online = false
          for _, fitted in starbase.modules do
            online = online or (fitted.type == yield.by and state.tick >= fitted.ready)
          end
          if online and yield.units > 0 then
            Items.Add(state, yield.type, yield.units, id, Corporation.Store(state))
            table.insert(events, { kind = "CitadelMined", station = id, type = yield.type, units = yield.units })
          end
        end
      end
    end
  end
end

return CitadelWorks
