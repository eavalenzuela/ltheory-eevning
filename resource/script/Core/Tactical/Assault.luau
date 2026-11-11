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
-- the first is on the charts. The way to the next is found when a room
-- is cleared: it is on the overview from then on.
--
-- What the job is to do there is one of three things:
--   - clear the camp: every ship of every wave;
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
-- (EVE's security missions, cut down. Not yet: a gate to fly through
-- from room to room, things to destroy other than ships, a camp that is
-- not pirates'.)

local Constants = require("@lt/Core/Data/Constants")
local Items = require("@lt/Core/Assets/Items")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local Sites = require("@lt/Core/Tactical/Sites")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")

local Assault = {}

export type Event = { [string]: any }

-- The standing with the faction that each level wants.
Assault.STANDING = { -2, 1, 3, 5 }
-- How many waves a camp of each level has, and how many rooms it has at
-- most (and at least: one, but two at the third level and the fourth).
Assault.WAVES = { 2, 3, 3, 3 }
Assault.ROOMS = { 1, 2, 2, 3 }
local LEAST = { 1, 1, 2, 2 }
-- Seconds between the last ship of a wave and the first of the next.
Assault.BREATHER = 20
-- What a job pays, as a share of the bounties on the camp's keepers,
-- with so much for each level beside; and the standing it is worth.
Assault.SHARE = 0.6
Assault.BASE = 5000
Assault.CREDIT = 0.15
-- What a job may be to do, and how likely each is.
Assault.AIMS = { "clear", "chief", "fetch" }
local ODDS = { 0.5, 0.25, 0.25 }
-- What a camp took, and how much of it there is to bring back, a level.
Assault.LOOT = "cargo.stolen"
Assault.CRATES = 10
-- How many times over the bounty on a camp's chief is.
Assault.CHIEF = 2

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
-- and the standing it is worth.
function Assault.Pay(level: number, waves: { { string } }): (number, number)
  local _, bounty = Assault.Count(waves)
  return math.floor(Assault.SHARE * bounty) + Assault.BASE * level, Assault.CREDIT * level
end

-- What a job of an aim counts: the ships of the camp, the one chief, or
-- the crates to bring back.
function Assault.Need(aim: string, level: number, waves: { { string } }): number
  if aim == "chief" then
    return 1
  elseif aim == "fetch" then
    return Assault.CRATES * level
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
    local site = Sites.Stake(state, mission.system, rng, "Pirate Camp", last, NUMERALS[room])
    if site == nil then
      break
    end
    table.insert(mission.rooms, site.id)
    last = site
  end
  mission.site = mission.rooms[1] or 0
  if mission.site ~= 0 then
    table.insert(events, { kind = "SiteAppeared", site = mission.site, system = mission.system, what = "mission" })
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

-- Whoever of a room of a camp is still in it.
local function keepers(state: State.State, room: number): { number }
  local found: { number } = {}
  for _, id in state.pilotIds do
    if state.pilots[id].home == room and state.balls[id] then
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
    for _, id in keepers(state, room) do
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
    local room = if mission.kind == "assault" then table.find(mission.rooms, place) else nil
    if room then
      return mission, room
    end
  end
  return nil, 0
end

-- A ship that kept a place has been destroyed (Tactical/Aftermath, once
-- it is gone): if the place is a room of a camp, it counts toward the
-- job as the job counts; and with the last of a wave the next is due,
-- or the way to the next room is found, or the camp is cleared.
function Assault.Fell(state: State.State, home: number, ship: number, events: { Event })
  local mission, room = roomOf(state, home)
  if mission == nil then
    return
  end
  local was = mission.done
  if mission.aim == "clear" then
    mission.done = math.min(mission.need, mission.done + 1)
  elseif mission.aim == "chief" and ship == mission.mark then
    mission.done = mission.need
  end
  if mission.aim ~= "fetch" and mission.done >= mission.need and was < mission.need then
    table.insert(events, { kind = "AssaultCleared", mission = mission.id, station = mission.station, aim = mission.aim })
  end
  if #keepers(state, home) > 0 then
    return
  end
  state.spawned[home] = state.tick
  if mission.wave < mission.ends[room] then
    table.insert(events, { kind = "WaveDown", mission = mission.id, wave = mission.wave, of = #mission.waves })
  elseif room < #mission.rooms then
    -- The room is cleared: the way to the next is found.
    local next = state.sites[mission.rooms[room + 1]]
    local place = Space.Object(state, mission.rooms[room + 1])
    if next and place and next.strength < 1 then
      next.strength = 1
      table.insert(events, { kind = "RoomOpen", mission = mission.id, room = room + 1, of = #mission.rooms, site = next.id,
        name = place.name })
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
  -- (the waves of the rooms before have all to have come: a pilot who
  -- has found their own way to a room finds nobody in)
  if mission == nil or mission.wave >= mission.ends[room] or mission.wave < (mission.ends[room - 1] or 0)
    or #keepers(state, me.grid) > 0 then
    return
  end
  local last = state.spawned[me.grid]
  local place = Space.Object(state, me.grid)
  if place == nil or (last ~= nil and (state.tick - last) * Constants.TICK < Assault.BREATHER) then
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
