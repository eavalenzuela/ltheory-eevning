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
local Factions = require("@lt/Core/Data/Factions")
local Hulks = require("@lt/Core/Assets/Hulks")
local Items = require("@lt/Core/Assets/Items")
local Rng = require("@lt/Core/Kernel/Rng")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local Types = require("@lt/Core/Data/Types")
local Wallet = require("@lt/Core/Assets/Wallet")

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

-- The defence module a faction's citadel has (the owner's, 2026-11-20:
-- fought as a pilot's citadel is): of its people's weapons, a missile
-- people's launchers. (Which family is each people's is mine.)
function Citadels.Defence(record: State.Citadel): string
  local tower = Structures.towerById[record.tower]
  local people = Factions.byId[record.owner]
  local family = if people == nil then "projectile" elseif people.launchers >= 0.5 then "missile" else people.weapon
  return `citadel.defence.{family}.{Structures.CITADEL_SIZES[tower.size]}`
end

-- The faction's citadel a ship stands for under fire, if it does.
-- (by the core's id: what is destroyed is forgotten before its citadel hears of it)
function Citadels.OfCore(state: State.State, ship: number): State.Citadel?
  for _, key in state.citadelIds or {} :: { number } do
    local record = state.citadels[key]
    if record.core == ship then
      return record
    end
  end
  return nil
end

-- What stands for each faction's citadel of the pilot's system under
-- fire (the owner's, 2026-11-20: fought as a pilot's is): a ship of its
-- faction's at its heart, nobody's to fly, with all its shield (its
-- shield modules full) and fought layer by layer, reinforced between
-- (Tactical/Combat). Put there when the pilot is first in its system,
-- and kept, with what has been done to it.
function Citadels.Cores(state: State.State, system: number, events: { Event })
  if state.citadels == nil then
    return
  end
  for _, record in Citadels.Of(state, system) do
    if not record.fallen and record.station ~= 0 and (record.core == nil or state.balls[record.core] == nil) then
      local tower = Structures.towerById[record.tower]
      local object = Space.Object(state, record.station)
      if tower and object then
        local core = Space.NewShip(state, Structures.Core(tower), tower.name, record.owner, 0)
        core.stands = record.station
        local ball = Space.Launch(state, core, record.system, object.x, object.y, object.z)
        ball.vitals.shieldMax, ball.vitals.shield = tower.shield, tower.shield
        ball.vitals.phase = "shield"
        ball.vitals.cap = tower.cap
        record.core = core.id
        table.insert(events, { kind = "BallAdded", ball = ball.id })
      end
    end
  end
end

-- A ship has been destroyed: if it stood for a faction's citadel, the
-- citadel falls (and leaves its hulk, as one does to the world: fall).
local fall: (state: State.State, record: State.Citadel, events: { Event }) -> ()
function Citadels.CoreLost(state: State.State, ship: number, events: { Event })
  local record = Citadels.OfCore(state, ship)
  if record then
    record.core = nil
    fall(state, record, events)
  end
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

-- What a finder asks of the pilot for what was saved at a fallen
-- citadel: a share of what it is worth (the owner, 2026-11-22: "half is
-- kept and moved to a nearby station, but the player must pay 5% of the
-- total value to recover it").
Citadels.FINDERS_FEE = 0.05
Citadels.SAVED = 0.5
-- How many jumps off a station is looked for to take it to.
local NEAR = 12

-- The station nearest a system by the gates (its own first), not a
-- tower or a citadel of anybody's, nor the one that fell: where what was
-- saved of it is taken. The pilot's home, if there is none so near.
local function nearest(state: State.State, system: number, gone: number): number
  local seen: { [number]: boolean } = { [system] = true }
  local ring = { system }
  for _ = 0, NEAR do
    local after: { number } = {}
    for _, id in ring do
      for _, object in Space.Describe(state, id).objects do
        if object.kind == "station" and object.id ~= gone and state.starbases[object.id] == nil
          and Space.FactionCitadel(state, object.id) == nil and Citadels.At(state, object.id) == nil then
          return object.id
        end
      end
      for _, next in state.galaxy.systems[id].neighbors do
        if not seen[next] then
          seen[next] = true
          table.insert(after, next)
        end
      end
    end
    ring = after
  end
  return state.player.home
end

-- What the pilot kept at a citadel that has fallen: half of each stack
-- is saved and taken to the nearest station, to be had back there for
-- the finder's fee; the rest is lost with it. (A stack of one is saved
-- or not by a toss.)
local function save(state: State.State, record: State.Citadel, station: number, events: { Event })
  local stored = Items.Stored(state, station)
  if #stored == 0 then
    return
  end
  local held = state.held or {}
  state.held = held
  local id = State.NewId(state)
  local worth = 0
  for _, item in stored do
    local kept = math.floor(item.quantity * Citadels.SAVED)
    if item.quantity == 1 then
      kept = if Rng.Chance(Rng.For(state.historySeed, item.id, 911), Citadels.SAVED) then 1 else 0
    end
    if kept <= 0 then
      Items.Take(state, item, item.quantity)
    else
      if kept < item.quantity then
        Items.Take(state, item, item.quantity - kept)
      end
      item.holder = id
      worth += kept * Types.Info(item.type).basePrice
    end
  end
  if worth <= 0 then
    return
  end
  local to = nearest(state, record.system, station)
  local object = Space.Object(state, station)
  held[id] = { id = id, station = to, from = if object then object.name else "a citadel",
    fee = math.ceil(worth * Citadels.FINDERS_FEE), worth = worth }
  local there = Space.Object(state, to)
  table.insert(events, { kind = "HangarSaved", from = held[id].from, station = to, name = if there then there.name else "a station",
    fee = held[id].fee, worth = worth })
end

-- Having what was saved back: at the station it was taken to, for its fee.
Citadels.COMMANDS = { Recover = true }

function Citadels.Validate(state: State.State, command: State.Command): (boolean, string?)
  local held = if state.held then state.held[command.target or 0] else nil
  local ship = state.ships[command.actor]
  if held == nil then
    return false, "nothing is held for you"
  elseif ship == nil or ship.docked ~= held.station then
    return false, "it is held at another station"
  elseif state.wallet < held.fee then
    return false, "not enough credits for the finder's fee"
  end
  return true
end

function Citadels.Apply(state: State.State, command: State.Command, events: { Event })
  local all = assert(state.held)
  local held = all[command.target :: number]
  Wallet.Pay(state, -held.fee, "finder's fee", events)
  for _, item in Items.Stored(state, held.id) do
    item.holder = held.station
  end
  all[held.id] = nil
  table.insert(events, { kind = "HangarRecovered", station = held.station, from = held.from, fee = held.fee })
end

-- What is held for the pilot, at a station or anywhere ('station' nil).
function Citadels.Held(state: State.State, station: number?): { State.Held }
  local found: { State.Held } = {}
  local all: { [number]: State.Held } = state.held or {}
  for _, held in all do
    if station == nil or held.station == station then
      table.insert(found, held)
    end
  end
  table.sort(found, function(a, b)
    return a.id < b.id
  end)
  return found
end

-- One of them falls. Its place is its hulk's from now on, and the hulk
-- is there now if the system has been described (else when the pilot
-- first comes: Citadels.Settle).
function fall(state: State.State, record: State.Citadel, events: { Event })
  if record.fallen then
    return
  end
  if record.station ~= 0 then
    Space.Rehome(state, record.station)
    -- (what the pilot kept there: half saved, at a station near)
    save(state, record, record.station, events)
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
  -- (and what stood for it under fire goes with it)
  local core = if record.core then state.balls[record.core] else nil
  if core then
    Space.RemoveBall(state, core)
  end
  record.core = nil
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
  local me = state.balls[state.player.ship]
  if me then
    Citadels.Cores(state, me.system, events)
  end
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
