--!strict
-- An assault: a job at a pirate camp, at a place made for it.
--
-- A station's fourth agent has this work, for a pilot the faction does
-- not think ill of, as hard as they are thought fit for: four levels,
-- the second at a standing of 1, the third at 3, the fourth at 5. A
-- pilot takes whichever of the levels open to them they like, one job
-- from a station at a time, and the agent has another as soon as the
-- last is done with.
--
-- Taking the job puts the camp on the charts: a place in the station's
-- system or a neighbour's (Tactical/Sites), found already. Nobody is
-- there until the pilot is. Then the camp's keepers come out in waves,
-- two at the first level and three at the others: a wave when the pilot
-- arrives, and the next a little after the last ship of one is
-- destroyed. They do not leave, and nothing else comes there. Every
-- ship of theirs destroyed pays its own bounty as any pirate does.
--
-- A camp is of one room or more (one at the first level, as many as
-- three at the fourth): each a place of its own, some tens of thousands
-- of kilometres from the last, with some of the camp's waves in it. Only
-- the first is on the charts. The way on from a room is its gate, which
-- stands in the room and is shut while anybody of the room is left: with
-- the room cleared it opens, and a ship that goes through it (the order
-- that takes a ship through a stargate) is sent on to the next room,
-- which is on the overview from then on.
--
-- What the job is to do there is one of four things:
--   - clear the camp: every ship of every wave;
--   - raze it: destroy what it is built of, which stands in the last
--     room from when the pilot gets there (Assault.WORKS: stores, and
--     at the two harder levels an emplacement that fires on whoever
--     comes).
--     They are ships to everything that locks and shoots, and do not
--     move. Whoever of the camp's keepers is left can be left;
--   - destroy its chief, who comes out with the last wave of the last
--     room (and has twice the bounty on them): whoever else is left can
--     be left;
--   - fetch what the camp took: a container in the last room, with the
--     stolen cargo in it, to be looted and brought back to the station.
--     Nobody has to be destroyed in that room to do it.
-- Done, the job is paid at the station that gave it (Assets/Missions).
-- Finished, given up or lapsed, the camp goes, and whoever and whatever
-- is left of it.
--
-- A mining contract (a station's fifth agent's work) has a place made
-- for it in the same way: a pocket of rocks of one ore, half as much
-- again as the contract wants, which nobody else knows of. The job is
-- to bring so much of that ore in. At the first two levels nobody
-- disputes it; at the third and the fourth a pack turns up when the
-- pilot does, once. (Ore of the kind from anywhere else does as well:
-- the pocket is where it is to be had.)
--
-- (Security and mining missions, cut down. Not yet: a camp that is not
-- pirates'.)

local Constants = require("@lt/Core/Data/Constants")
local Items = require("@lt/Core/Assets/Items")
local Ores = require("@lt/Core/Data/Ores")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local Sites = require("@lt/Core/Tactical/Sites")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")

local Assault = {}

export type Event = { [string]: any }

-- The standing with the faction that each level wants.
Assault.STANDING = { -2, 1, 3, 5 }
-- How many waves a camp of each level has, and how many rooms it has at
-- most (and at least: one, but two at the third level and the fourth).
Assault.WAVES = { 2, 3, 3, 3 }
Assault.ROOMS = { 1, 2, 2, 3 }
local LEAST = { 1, 1, 2, 2 }
Assault.LEAST = LEAST
-- Seconds between the last ship of a wave and the first of the next.
Assault.BREATHER = 20
-- What a job pays, as a share of the bounties on the camp's keepers,
-- with so much for each level beside; and the standing it is worth.
Assault.SHARE = 0.6
Assault.BASE = 5000
Assault.CREDIT = 0.15
-- What a job may be to do, and how likely each is.
Assault.AIMS = { "clear", "raze", "chief", "fetch" }
local ODDS = { 0.3, 0.2, 0.25, 0.25 }
-- What a camp of each level is built of (kinds of Tactical/Pirates, of
-- hulls of the class "works"): there to be destroyed where the job is
-- to raze the camp, and not there at all where it is anything else.
-- And how far from the middle of the last room they stand. (An
-- emplacement fires for as long as it stands, beside whoever keeps the
-- room: the levels have as much of that as the ship a level is for
-- comes through, which the spec holds them to, and no more.)
Assault.WORKS = {
  { "cache" },
  { "cache", "cache" },
  { "depot", "battery" },
  { "depot", "redoubt" },
}
Assault.WORKS_OUT = { 7000, 10000 }
-- What a camp took, and how much of it there is to bring back, a level.
Assault.LOOT = "cargo.stolen"
Assault.CRATES = 10
-- How many times over the bounty on a camp's chief is.
Assault.CHIEF = 2
-- A room's gate on to the next: what kind of gate it is (a thing of the
-- system's description, of the kind a stargate is, that leads to a place
-- and not to a system), how far from the middle of its room it stands,
-- and how big it is.
Assault.GATE = "passage"
Assault.GATE_OUT = 9000
Assault.GATE_RADIUS = 260

-- The packs a camp of each level may be kept by: a camp has some of
-- them, no two alike, the order they come in being part of the luck.
-- (A pirate's ship is as good as a pilot's of its class, so a level is
-- not a pack of the class it is for: the first is scouts, which a
-- frigate can take two and three at a time; the second raiders, for a
-- destroyer; the third the pirates' destroyers, for a cruiser; the
-- fourth their cruisers, for a battleship. The spec flies a plain ship
-- of each class at every camp its level can be, and holds the levels to
-- that.)
local PACKS: { { { string } } } = {
  { { "scout" }, { "scout", "scout" }, { "scout", "scout", "scout" } },
  { { "raider" }, { "raider", "scout" }, { "raider", "scout", "scout" }, { "scout", "scout", "scout" } },
  { { "jackal" }, { "jackal", "scout", "scout" }, { "raider", "raider" }, { "jackal", "raider" } },
  { { "marauder" }, { "marauder", "jackal" }, { "jackal", "jackal" }, { "marauder", "raider" } },
}
Assault.PACKS = PACKS

-- A mining contract of each level: the ores it may be for, how much of
-- the ore it wants (cubic metres: most of a mining frigate's hold at
-- the first, two holds of a barge at the fourth), and who turns up to
-- dispute the pocket.
local DIGS: { { ores: { string }, volume: number, pack: { string } } } = {
  { ores = { "ore.ferrite", "ore.silicate" }, volume = 300, pack = {} },
  { ores = { "ore.silicate", "ore.cuprite" }, volume = 900, pack = {} },
  { ores = { "ore.titanite", "ore.cobaltite" }, volume = 2500, pack = { "scout", "scout" } },
  { ores = { "ore.cobaltite", "ore.iridite" }, volume = 7000, pack = { "raider", "scout" } },
}
-- What a contract pays over what the ore is worth, with so much a
-- level beside; the standing it is worth a level; how many rocks its
-- pocket has; and how much more ore is in them than the contract wants.
Assault.DIG_PAY = 1.3
Assault.DIG_BASE = 3000
Assault.DIG_CREDIT = 0.1
Assault.DIG_ROCKS = 4
Assault.DIG_SPARE = 1.5

-- The terms of a mining contract of a level: the ore, how many units
-- of it (a round number of hundreds), and the pack that disputes it
-- (empty for none).
function Assault.Dig(rng: Rng.Rng, level: number): (string, number, { string })
  local dig = DIGS[level]
  local ore = dig.ores[Rng.Int(rng, #dig.ores) + 1]
  local units = math.max(100, math.floor(dig.volume / Ores.byId[ore].volume / 100 + 0.5) * 100)
  return ore, units, table.clone(dig.pack)
end

-- What a mining contract for so much of an ore pays (before what the
-- pilot's standing adds), and the standing it is worth.
function Assault.DigPay(level: number, ore: string, units: number): (number, number)
  return math.floor(Assault.DIG_PAY * units * Ores.byId[ore].basePrice) + Assault.DIG_BASE * level, Assault.DIG_CREDIT * level
end

-- The hardest level a pilot of a standing is given; 0 for one the
-- faction thinks too ill of to give any.
function Assault.Top(standing: number): number
  local top = 0
  for level, wanted in Assault.STANDING do
    if standing >= wanted then
      top = level
    end
  end
  return top
end

-- The waves of a camp of a level: so many of its packs, drawn without
-- putting any back.
function Assault.Plan(rng: Rng.Rng, level: number): { { string } }
  local left = table.clone(PACKS[level])
  local waves: { { string } } = {}
  for _ = 1, Assault.WAVES[level] do
    table.insert(waves, table.clone(table.remove(left, Rng.Int(rng, #left) + 1) :: { string }))
  end
  return waves
end

-- How a camp of a level is laid out, and what the job there is to do:
-- for each room the last wave that is in it (every room has one at
-- least), and the aim.
function Assault.Shape(rng: Rng.Rng, level: number): ({ number }, string)
  local waves = Assault.WAVES[level]
  local rooms = math.min(waves, LEAST[level] + Rng.Int(rng, Assault.ROOMS[level] - LEAST[level] + 1))
  -- (which of the waves begin a room: the first, and so many of the rest)
  local begins: { boolean } = { true }
  local wanted = rooms - 1
  for wave = 2, waves do
    local left = waves - wave + 1
    begins[wave] = wanted > 0 and Rng.Next(rng) < wanted / left
    wanted -= if begins[wave] then 1 else 0
  end
  local ends: { number } = {}
  for wave = 2, waves do
    if begins[wave] then
      table.insert(ends, wave - 1)
    end
  end
  table.insert(ends, waves)
  local roll, aim = Rng.Next(rng), Assault.AIMS[1]
  for index, share in ODDS do
    roll -= share
    if roll < 0 then
      aim = Assault.AIMS[index]
      break
    end
  end
  return ends, aim
end

-- How many ships there are in some waves, and the bounties on them all.
function Assault.Count(waves: { { string } }): (number, number)
  local ships, bounty = 0, 0
  for _, wave in waves do
    for _, kind in wave do
      ships += 1
      bounty += Pirates.kindById[kind].bounty
    end
  end
  return ships, bounty
end

-- What a job at a camp pays (before what the pilot's standing adds),
-- and the standing it is worth. (A camp that is to be razed has what
-- it is built of to pay for beside its keepers.)
function Assault.Pay(level: number, waves: { { string } }, aim: string?): (number, number)
  local _, bounty = Assault.Count(waves)
  if aim == "raze" then
    bounty += select(2, Assault.Count({ Assault.WORKS[level] }))
  end
  return math.floor(Assault.SHARE * bounty) + Assault.BASE * level, Assault.CREDIT * level
end

-- What a job of an aim counts: the ships of the camp, what it is built
-- of, the one chief, or the crates to bring back.
function Assault.Need(aim: string, level: number, waves: { { string } }): number
  if aim == "chief" then
    return 1
  elseif aim == "fetch" then
    return Assault.CRATES * level
  elseif aim == "raze" then
    return #Assault.WORKS[level]
  end
  return (Assault.Count(waves))
end

-- Whether a camp can be put in a system: it has a planet to be out
-- from, and its description has room.
function Assault.Room(state: State.State, system: number): boolean
  local objects = Space.Describe(state, system).objects
  if #objects + 40 >= Constants.STRUCTURE_ID_SPAN then
    return false
  end
  for _, object in objects do
    if object.kind == "planet" then
      return true
    end
  end
  return false
end

local NUMERALS = { "", " II", " III", " IV" }

-- The job is taken: its camp is on the charts, the first room of it,
-- and what it took is in the last.
function Assault.Open(state: State.State, mission: State.Mission, events: { Event })
  local rng = Rng.For(state.historySeed, mission.id, 59)
  local last: State.Site? = nil
  for room = 1, #mission.ends do
    local site = Sites.Stake(state, mission.system, rng, if mission.kind == "mining" then "Ore Pocket" else "Pirate Camp", last,
      NUMERALS[room])
    if site == nil then
      break
    end
    table.insert(mission.rooms, site.id)
    last = site
  end
  -- (the gate on from each room but the last: rolled apart from the
  -- rest, so that nothing else about the camp follows from it)
  if mission.kind == "assault" then
    for room = 1, #mission.rooms - 1 do
      local here, beyond = state.sites[mission.rooms[room]], Space.Object(state, mission.rooms[room + 1])
      if here and beyond then
        local roll = Rng.For(state.historySeed, mission.id, room, 61)
        local angle = Rng.Float(roll, 0, 2 * math.pi)
        Sites.Fixture(state, here, "gate", `Gate to {beyond.name}`, Assault.GATE_OUT * math.cos(angle), Rng.Float(roll, -1500, 1500),
          Assault.GATE_OUT * math.sin(angle), Assault.GATE_RADIUS, Assault.GATE, beyond.id)
      end
    end
  end
  mission.site = mission.rooms[1] or 0
  if mission.site ~= 0 then
    table.insert(events, { kind = "SiteAppeared", site = mission.site, system = mission.system, what = "mission" })
  end
  -- (a mining contract's pocket has its rocks: half as much ore again as is wanted)
  if mission.kind == "mining" and last then
    Sites.Rocks(state, last, rng, mission.type, Assault.DIG_ROCKS,
      math.ceil(Assault.DIG_SPARE * mission.need / Assault.DIG_ROCKS))
  end
  if mission.aim == "fetch" and last then
    local place = Space.Object(state, last.id)
    if place then
      local wreck: State.Wreck = {
        id = State.NewId(state), kind = "wreck", name = "Stolen Cargo", system = mission.system, grid = place.id,
        x = place.x + Rng.Float(rng, -4000, 4000), y = place.y + Rng.Float(rng, -1000, 1000), z = place.z + Rng.Float(rng, -4000, 4000),
        radius = 30, hull = "", expires = 2 ^ 52, salvaged = true, locked = false,
      }
      state.wrecks[wreck.id] = wreck
      table.insert(state.wreckIds, wreck.id)
      Items.Add(state, mission.type, mission.need, wreck.id, "cargo")
      mission.mark = wreck.id
    end
  end
end

-- Whether a ship is a thing a camp is built of, and not one that flies.
local function isWorks(state: State.State, id: number): boolean
  local ship = state.ships[id]
  return ship ~= nil and Ships.byId[ship.type].class == "works"
end

-- Whoever of a room of a camp is still in it: its keepers, who come in
-- waves; or with them, if 'all', what the camp is built of.
local function keepers(state: State.State, room: number, all: boolean?): { number }
  local found: { number } = {}
  for _, id in state.pilotIds do
    if state.pilots[id].home == room and state.balls[id] and (all or not isWorks(state, id)) then
      table.insert(found, id)
    end
  end
  return found
end

-- The job is over, however it ended: the camp goes, every room of it,
-- and whoever is left there, and the container if it is still about.
-- (What they left in wrecks stays until it fades.)
function Assault.Close(state: State.State, mission: State.Mission, events: { Event })
  for _, room in mission.rooms do
    for _, id in keepers(state, room, true) do
      Space.RemoveBall(state, state.balls[id])
      for _, item in Items.In(state, id, nil) do
        Items.Take(state, item, item.quantity)
      end
      state.ships[id] = nil
      State.RemoveId(state.shipIds, id)
      state.pilots[id] = nil
      State.RemoveId(state.pilotIds, id)
      table.insert(events, { kind = "BallRemoved", ball = id, reason = "left" })
    end
    Sites.Release(state, room, events)
    state.spawned[room] = nil
  end
  local container = if mission.aim == "fetch" then state.wrecks[mission.mark] else nil
  if container then
    for _, item in Items.In(state, container.id, nil) do
      Items.Take(state, item, item.quantity)
    end
    state.wrecks[container.id] = nil
    State.RemoveId(state.wreckIds, container.id)
    table.insert(events, { kind = "WreckRemoved", wreck = container.id })
  end
end

-- The room of a camp a place is, and the job whose camp it is.
local function roomOf(state: State.State, place: number): (State.Mission?, number)
  for _, id in state.missionIds do
    local mission = state.missions[id]
    local room = if mission.kind == "assault" or mission.kind == "mining" then table.find(mission.rooms, place) else nil
    if room then
      return mission, room
    end
  end
  return nil, 0
end

-- The gate that stands in a room of a camp, if it has one (the last
-- room has none; nor has a camp of a save from before there were gates).
function Assault.Gate(state: State.State, room: number): System.Object?
  local site = state.sites[room]
  if site == nil then
    return nil
  end
  for _, object in Space.Describe(state, site.system).objects do
    if object.kind == "gate" and object.variety == Assault.GATE and object.site == room then
      return object
    end
  end
  return nil
end

-- Whether a camp's gate will take a ship through: it is shut while any
-- wave of its room is still to come, or anybody of the room is left.
function Assault.Passable(state: State.State, gate: System.Object): (boolean, string?)
  local mission, room = roomOf(state, gate.site)
  if mission == nil or state.sites[gate.to] == nil then
    return false, "the gate leads nowhere now"
  elseif mission.wave < mission.ends[room] or #keepers(state, gate.site) > 0 then
    return false, "the gate is shut while the camp's keepers hold this room"
  end
  return true
end

-- A ship that kept a place has been destroyed (Tactical/Aftermath, once
-- it is gone; 'works' says it was a thing the place is built of): if
-- the place is a room of a camp, it counts toward the job as the job
-- counts; and with the last of a wave the next is due, or the way to
-- the next room is found, or the camp is cleared.
function Assault.Fell(state: State.State, home: number, ship: number, works: boolean, events: { Event })
  local mission, room = roomOf(state, home)
  if mission == nil then
    return
  end
  local was = mission.done
  if mission.aim == (if works then "raze" else "clear") then
    mission.done = math.min(mission.need, mission.done + 1)
  elseif mission.aim == "chief" and ship == mission.mark then
    mission.done = mission.need
  end
  if mission.aim ~= "fetch" and mission.done >= mission.need and was < mission.need then
    table.insert(events, { kind = "AssaultCleared", mission = mission.id, station = mission.station, aim = mission.aim })
  end
  -- (what a camp is built of is no part of its waves)
  if works or #keepers(state, home) > 0 then
    return
  end
  state.spawned[home] = state.tick
  if mission.wave < mission.ends[room] then
    table.insert(events, { kind = "WaveDown", mission = mission.id, wave = mission.wave, of = #mission.waves })
  elseif room < #mission.rooms then
    -- The room is cleared: its gate opens, and leads on to the next.
    -- (A camp with no gate, of a save from before there were any, has
    -- the way to the next room found, as it was then.)
    local next = state.sites[mission.rooms[room + 1]]
    local place = Space.Object(state, mission.rooms[room + 1])
    local gate = Assault.Gate(state, home)
    if next and place and next.strength < 1 then
      if gate == nil then
        next.strength = 1
      end
      table.insert(events, { kind = "RoomOpen", mission = mission.id, room = room + 1, of = #mission.rooms, site = next.id,
        name = place.name, gate = if gate then gate.id else 0 })
    end
  end
end

-- Once a tick: in a room of a camp that the pilot is in, with nobody of
-- it left and a wave of that room's still to come, it comes (the first
-- at once, the others after a breather).
function Assault.Step(state: State.State, events: { Event })
  local me = state.balls[state.player.ship]
  if me == nil or me.grid == 0 or Ships.byId[state.ships[me.id].type].class == "capsule" then
    return
  end
  local mission, room = roomOf(state, me.grid)
  local place = Space.Object(state, me.grid)
  -- (the waves of the rooms before have all to have come: a pilot who
  -- has found their own way to a room finds nobody in, and nothing)
  if mission == nil or place == nil or mission.wave < (mission.ends[room - 1] or 0) then
    return
  end
  -- A camp that is to be razed has what it is built of standing in its
  -- last room, from when the pilot first comes there: spread round the
  -- middle of it, some kilometres out. ('mark' is the first of them.)
  if mission.aim == "raze" and room == #mission.rooms and mission.mark == 0 then
    local works = Assault.WORKS[mission.level]
    local rng = Rng.For(state.historySeed, mission.id, 67)
    local turn = Rng.Float(rng, 0, 2 * math.pi)
    for index, kind in works do
      local angle = turn + (index - 1 + Rng.Float(rng, -0.2, 0.2)) * 2 * math.pi / #works
      local out = Rng.Float(rng, Assault.WORKS_OUT[1], Assault.WORKS_OUT[2])
      local ball = Pirates.Spawn(state, Pirates.kindById[kind], me.system,
        place.x + out * math.cos(angle), place.y + Rng.Float(rng, -1500, 1500), place.z + out * math.sin(angle), place.id)
      if index == 1 then
        mission.mark = ball.id
      end
      table.insert(events, { kind = "BallAdded", ball = ball.id })
    end
    table.insert(events, { kind = "WorksSighted", mission = mission.id, grid = place.id, count = #works })
  end
  if mission.wave >= mission.ends[room] or #keepers(state, me.grid) > 0 then
    return
  end
  local last = state.spawned[me.grid]
  if last ~= nil and (state.tick - last) * Constants.TICK < Assault.BREATHER then
    return
  end
  mission.wave += 1
  local wave = mission.waves[mission.wave]
  local rng = Rng.For(state.historySeed, mission.id, mission.wave, 43)
  for index, kind in wave do
    -- Somewhere 25 to 35 km out from the middle of the place.
    local angle = Rng.Float(rng, 0, 2 * math.pi)
    local out = Rng.Float(rng, 25000, 35000)
    local ball = Pirates.Spawn(state, Pirates.kindById[kind], me.system,
      place.x + out * math.cos(angle), place.y + Rng.Float(rng, -3000, 3000), place.z + out * math.sin(angle), place.id)
    -- (the camp's chief is the first of the last wave)
    if mission.aim == "chief" and mission.wave == #mission.waves and index == 1 then
      mission.mark = ball.id
      ball.name = "Pirate Chief"
      state.ships[ball.id].name = "Pirate Chief"
      state.pilots[ball.id].bounty *= Assault.CHIEF
    end
    table.insert(events, { kind = "BallAdded", ball = ball.id })
  end
  table.insert(events, { kind = "PiratesArrived", grid = place.id, count = #wave, wave = mission.wave, of = #mission.waves,
    chief = mission.aim == "chief" and mission.wave == #mission.waves })
end

return Assault
