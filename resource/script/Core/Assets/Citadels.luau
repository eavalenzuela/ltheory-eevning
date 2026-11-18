--!strict
-- The factions' citadels (the owner's B2, 2026-11-17: "Pirates and
-- factions both" build citadels; and 2026-11-18, in this order: "the
-- hulk work + loot, then the BPs, then actually having NPC factions own
-- citadels, then having the generator start placing them in universe
-- generation").
--
-- Where: put down in a system when it is first described or looked at
-- from afar (Tactical/Space's CitadelObjects; how many and of what,
-- Describe/CitadelSites): in held space more the higher its security
-- (the owner, 2026-11-18: "A 1.0 system should probably have a citadel
-- or station at every other planet"), of the kinds and sizes that
-- people builds (the human peoples' the standard ones, the Vail's and
-- the Nimia's their own: Data/Structures' CITADEL_ALIEN); and in some
-- of open space, the hulk of one that fell long ago. Each stands at a
-- moon or a planet of its own.
--
-- What: a station like any of the faction's, docked at and traded in,
-- with the services of its kind (Citadels.Modules), drawn as its
-- people's design in their colours. Big hulls dock where the citadel's
-- size lets them; a faction's citadel has no tether for the rest.
--
-- How they fall (the owner, 2026-11-18: players attack them "later";
-- for now only the world brings them down): every one in a system that
-- passes out of its people's hands, and one where an invasion is let be
-- (Tactical/Invasions). It leaves its hulk (Assets/Hulks), with some of
-- its fittings in it, and an alien people's drawing of it.

local Constants = require("@lt/Core/Data/Constants")
local Hulks = require("@lt/Core/Assets/Hulks")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")

local Citadels = {}

export type Event = { [string]: any }

-- A save from before there were any: the systems it has seen have
-- theirs put down now, at the end of what is in their descriptions.
-- (The rest have theirs when they are first looked at.)
function Citadels.Place(state: State.State)
  state.citadels = state.citadels or {}
  state.citadelIds = state.citadelIds or {}
  state.citadelsSeen = state.citadelsSeen or {}
  local seen: { number } = {}
  for system in state.systems do
    table.insert(seen, system)
  end
  table.sort(seen)
  for _, system in seen do
    local description = state.systems[system]
    for _, object in Space.CitadelObjects(state, description) do
      table.insert(description.objects, object)
    end
  end
end

-- What a faction's citadel has fitted, by its kind and as its slots let
-- it: a market and repairs everywhere, and its kind's own work.
local FITTED: { [string]: { string } } = {
  habitation = { "service.market", "service.repair", "service.clone", "service.storage", "service.manufacturing" },
  tradehub = { "service.market", "service.repair", "service.storage", "service.refinery", "service.research" },
  refinery = { "service.refinery", "service.market", "service.repair", "service.reactor", "service.storage" },
  research = { "service.research", "service.market", "service.repair", "service.research.advanced", "service.storage" },
  shipyard = { "service.manufacturing", "service.repair", "service.market", "service.assembly.advanced", "service.assembly.capital" },
  generator = { "service.generator.gravity", "service.market", "service.repair", "service.storage" },
}
function Citadels.Modules(tower: Structures.Tower): { string }
  local out: { string } = {}
  for _, id in FITTED[tower.kind or ""] or FITTED.habitation do
    local module = Structures.moduleById[id]
    if module and #out < (tower.slots or 2) and (module.least or 1) <= tower.size
      and (module.kinds == nil or table.find(module.kinds, tower.kind or "") ~= nil) then
      table.insert(out, id)
    end
  end
  return out
end

-- The faction's citadel a station is, if it is one that stands.
function Citadels.At(state: State.State, station: number): State.Citadel?
  return Space.FactionCitadel(state, station)
end

-- A system's citadels, in order.
function Citadels.Of(state: State.State, system: number): { State.Citadel }
  local out: { State.Citadel } = {}
  if state.citadels == nil then
    return out
  end
  local slot = 1
  local record = state.citadels[Space.CitadelKey(system, slot)]
  while record do
    table.insert(out, record)
    slot += 1
    record = state.citadels[Space.CitadelKey(system, slot)]
  end
  return out
end

-- Its hulk, where the pilot can see it: a fallen citadel of a system
-- that has been described, whose hulk is not there yet.
local function settle(state: State.State, record: State.Citadel, events: { Event })
  if not record.fallen or record.wreck ~= 0 or record.station == 0 or state.systems[record.system] == nil then
    return
  end
  local tower = Structures.towerById[record.tower]
  local object = Space.Object(state, record.station)
  if tower == nil or object == nil then
    return
  end
  local wreck = Hulks.Make(state, record.system, object, tower, Citadels.Modules(tower), events)
  record.wreck = wreck.id
end

-- Where the pilot is: the hulks of the citadels that have fallen there.
function Citadels.Settle(state: State.State, system: number, events: { Event })
  if state.citadels == nil then
    return
  end
  Space.Describe(state, system)
  for _, record in Citadels.Of(state, system) do
    settle(state, record, events)
  end
end

-- One of them falls. Its place is its hulk's from now on, and the hulk
-- is there now if the system has been described (else when the pilot
-- first comes: Citadels.Settle).
local function fall(state: State.State, record: State.Citadel, events: { Event })
  if record.fallen then
    return
  end
  -- (whoever is docked there is put out, as from a pilot's that falls)
  local object = if record.station ~= 0 and state.systems[record.system] then Space.Object(state, record.station) else nil
  if object then
    for _, shipId in state.shipIds do
      local ship = state.ships[shipId]
      if ship.docked == object.id then
        if shipId == state.player.ship then
          Space.Apply(state, { kind = "Undock", actor = shipId }, events)
        else
          ship.docked = state.player.home
        end
      end
    end
  end
  record.fallen = true
  Space.Forget(state, record.system)
  settle(state, record, events)
  table.insert(events, { kind = "CitadelFell", system = record.system, station = record.station, tower = record.tower, owner = record.owner })
end

-- The factions' citadels in a system fall: every one, or ('one') the
-- first of them that stands.
function Citadels.Fall(state: State.State, system: number, events: { Event }, one: boolean?)
  for _, record in Citadels.Of(state, system) do
    if not record.fallen then
      fall(state, record, events)
      if one then
        return
      end
    end
  end
end

-- Once an hour: a citadel whose system is no longer its people's falls.
local HOUR = math.floor(3600 / Constants.TICK + 0.5)
function Citadels.Step(state: State.State, events: { Event })
  if state.tick % HOUR ~= 0 or state.citadelIds == nil then
    return
  end
  for _, key in table.clone(state.citadelIds) do
    local record = state.citadels[key]
    if not record.fallen and state.galaxy.systems[record.system].owner ~= record.owner then
      fall(state, record, events)
    end
  end
end

return Citadels
