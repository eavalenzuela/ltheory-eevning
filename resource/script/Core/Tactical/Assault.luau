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
-- A defence job (a station's seventh agent's work) is the other way
-- about: the place is not the pirates' but a survey rig of the
-- faction's, which stands there from when the pilot first comes
-- (Assault.RIGS: a bigger one a level), and the pirates come for it,
-- in the waves a camp of the level would have, one room's worth. Most
-- of them go for the rig and not for the pilot (Tactical/Pirates). The
-- job is to see every one of them off with the rig still standing: a
-- rig destroyed is the job lost, at once, as a job given up is. And
-- they set the pace: a wave that is not down two minutes after it came
-- has the next one come anyway (Assault.PRESS).
--
-- Every third job of that agent's is an escort (the aim "escort"): what
-- stands in for the rig is a tender, which flies. It is waiting by the
-- middle of the place when the pilot comes, and sets off at once,
-- slowly, straight out: so far out (Assault.TENDER_OUT) it is clear,
-- and gone. The same waves come for it on the way, at the same pace.
-- The job is to see it out: whoever is still about when it goes is no
-- part of the job (though their bounties are the pilot's), and no wave
-- comes after. A tender destroyed is the job lost. (At the first level,
-- since 2026-11-20, a wave waits for the one before to be down, as at a
-- camp: the owner's, when a tech 1 destroyer lost the job or won it by
-- a hair as the dice fell. And at the third and fourth, since
-- 2026-11-22, the owner's again. Assault.Pressed.)
--
-- And every sixth is a convoy (the aim "convoy"): the same tender, but
-- where it gets clear of the place it warps on to where it is going
-- ('to'): the station the job is from, if the place is in that
-- station's system, and if it is in a neighbour's, the gate that leads
-- back there. It lands some way off (Assault.CONVOY_IN) and flies in,
-- to dock or to go through. All the waves but the last come for it at
-- the place; the last is waiting where it lands. The job is to see it
-- in: it is done when the tender docks, or is through the gate, and
-- not before. It pays more than an escort does (Assault.CONVOY_PAY).
--
-- (Security and mining missions, cut down. Not yet: a camp that is not
-- pirates', a convoy to follow through its gate and on.)

local Captains = require("@lt/Core/Tactical/Captains")
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
-- (25,000 a level since 2026-11-16, when income came up: it was 5,000. Mine.)
Assault.BASE = 25000
Assault.CREDIT = 0.15
-- What a defence job is to hold, by its level (Data/Ships), how far
-- from the middle of the place it stands, and what such a job pays
-- beside what a camp of the same keepers would: holding is harder than
-- clearing.
Assault.RIGS = { "works.rig.1", "works.rig.2", "works.rig.3", "works.rig.4" }
Assault.RIG_OUT = { 2000, 4000 }
Assault.HOLD_PAY = 1.25
-- How long after a wave has come for a rig the next one does, whether
-- or not the first is destroyed (seconds): at a camp its keepers wait
-- their turn, and those who come for a rig do not.
Assault.PRESS = 120
-- What an escort is to see through, by its level (Data/Ships); how far
-- from the middle of the place it waits, and how far out it has to get
-- to be clear (metres); and that every so-manyth job of the agent's is
-- an escort.
Assault.TENDERS = { "convoy.tender.1", "convoy.tender.2", "convoy.tender.3", "convoy.tender.4" }
Assault.TENDER_FROM = 1500
Assault.TENDER_OUT = 28000
Assault.ESCORTS = 3
-- What a job may be to do, and how likely each is. (A defence job is
-- always to "hold", and is not one of these: it is another agent's.)
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
-- What a camp's chief is, by the job's level: one of the pirates who
-- lead in the region, by name (Tactical/Captains), a veteran of their
-- kind at the first two levels and a captain at the last two (the
-- owner's, 2026-11-22). The grade is what puts more on their head
-- (Pirates.GRADES), and getting away from the pilot before more again.
Assault.CHIEF = { 1, 1, 2, 2 }
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
-- destroyer; the third the pirates' destroyers, one to a wave, for a
-- cruiser, with a frigate or two beside one (two destroyers at once are
-- more than a cruiser of the level comes through, and a wave of
-- frigates alone it cannot hit); the fourth their cruisers, two of them
-- at most, or two of their destroyers, for a
-- battleship. The owner, 2026-11-18: a mission's pirates are "weaker
-- than the ship class assigned to the mission, by level", and two
-- frigates are what a cruiser's guns cannot hit, since they were set
-- from the reference.) The spec flies a plain ship
-- of each class at every camp its level can be, and holds the levels to
-- that. Since 2026-11-19 a Jackal has point defence, which shoots down
-- a pilot's drones as well as missiles: the third level's hardest pack
-- lost a scout for it, the owner's choice, and had it back once point
-- defence mostly missed and missiles flew after their targets; and as it
-- takes a gun's hardpoint, the fourth level's lone Marauder gained one.)
local PACKS: { { { string } } } = {
  { { "scout" }, { "scout", "scout" }, { "scout", "scout", "scout" } },
  { { "raider" }, { "raider", "scout" }, { "raider", "scout", "scout" }, { "scout", "scout", "scout" } },
  { { "jackal" }, { "jackal", "scout" }, { "jackal", "scout", "scout" }, { "jackal", "raider" } },
  { { "marauder", "scout" }, { "marauder", "jackal" }, { "jackal", "jackal" }, { "marauder", "marauder" } },
}
Assault.PACKS = PACKS

-- A mining contract of each level: the ores it may be for, how much of
-- the ore it wants (cubic metres: most of a mining frigate's hold at
-- the first, two holds of a barge at the fourth), and who turns up to
-- dispute the pocket.
local DIGS: { { ores: { string }, volume: number, pack: { string } } } = {
  -- (200 since 2026-11-18: most of a frigate's hold, now that the
  -- Prospector, the 480 m3 mining frigate, is gone. Mine.)
  { ores = { "ore.ferrite", "ore.silicate" }, volume = 200, pack = {} },
  { ores = { "ore.silicate", "ore.cuprite" }, volume = 900, pack = {} },
  { ores = { "ore.titanite", "ore.cobaltite" }, volume = 2500, pack = { "scout", "scout" } },
  { ores = { "ore.cobaltite", "ore.iridite" }, volume = 7000, pack = { "raider", "scout" } },
}
-- What a contract pays over what the ore is worth, with so much a
-- level beside; the standing it is worth a level; how many rocks its
-- pocket has; and how much more ore is in them than the contract wants.
Assault.DIG_PAY = 1.3
-- (12,000 a level since 2026-11-16: it was 3,000. Mine.)
Assault.DIG_BASE = 12000
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
  local pay = math.floor(Assault.DIG_PAY * units * Ores.byId[ore].basePrice) + Assault.DIG_BASE * level
  return math.floor(pay * (Assault.LEVEL_PAY.mining[level] or 1)), Assault.DIG_CREDIT * level
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

-- Whether an aim is a tender's: one to see through ("escort"), or in to
-- the station the job is from ("convoy").
function Assault.Tender(aim: string?): boolean
  return aim == "escort" or aim == "convoy"
end

-- A convoy: how far off the station its tender lands, what the job pays
-- beside a camp of its level cleared, how far from the tender the last
-- wave is waiting, and which of the agent's jobs it is (every sixth).
Assault.CONVOY_IN = 20000
Assault.CONVOY_PAY = 1.5
Assault.CONVOY_WAIT = { 12000, 18000 }
Assault.CONVOYS = 6

-- What a job at a camp pays (before what the pilot's standing adds),
-- and the standing it is worth. (A camp that is to be razed has what
-- it is built of to pay for beside its keepers.)
-- What each level of a line of work is paid beyond what its figures
-- come to: so that each earns in an hour about what a courier contract
-- of its level does (the owner, 2026-11-22: "Level with courier", from
-- the earnings report, script/earnings, which measured courier
-- contracts at 2.6, 8.7, 9.4 and 94 million an hour by level; assaults
-- at 2.4, 5.3, 9.8 and 23; rigs held at 2.8, 6.5, 12 and 51; mining
-- contracts at 0.7, 2.5, 7.3 and 14). Nothing is paid less than it was.
Assault.LEVEL_PAY = {
  assault = { 1.1, 1.65, 1, 4.1 },
  defence = { 1, 1.35, 1, 1.85 },
  mining = { 3.7, 3.5, 1.3, 6.7 },
}

function Assault.Pay(level: number, waves: { { string } }, aim: string?): (number, number)
  local _, bounty = Assault.Count(waves)
  if aim == "raze" then
    bounty += select(2, Assault.Count({ Assault.WORKS[level] }))
  end
  local pay = math.floor(Assault.SHARE * bounty) + Assault.BASE * level
  local defence = aim == "hold" or Assault.Tender(aim)
  local more = if aim == "convoy" then Assault.CONVOY_PAY elseif aim == "hold" or aim == "escort" then Assault.HOLD_PAY else 1
  local line = Assault.LEVEL_PAY[if defence then "defence" else "assault"]
  return math.floor(pay * more * (line[level] or 1)), Assault.CREDIT * level
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
  -- (whoever leads the camp, by name, for a job that is to bring them down)
  if mission.aim == "chief" and mission.captain == nil then
    mission.captain = Captains.Pick(state, mission.system, mission.id).id
  end
  local rng = Rng.For(state.historySeed, mission.id, 59)
  local last: State.Site? = nil
  for room = 1, #mission.ends do
    local site = Sites.Stake(state, mission.system, rng, if mission.kind == "mining" then "Ore Pocket"
      elseif mission.aim == "hold" then "Survey Rig" elseif Assault.Tender(mission.aim) then "Convoy Route" else "Pirate Camp", last,
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
  -- (where a convoy's tender is going: the job's station, or from a
  -- neighbour's system the gate that leads to it)
  if mission.aim == "convoy" then
    local home = Space.SystemOf(state, mission.station)
    local gate = if mission.system ~= home then System.GateTo(Space.Describe(state, mission.system), home) else nil
    mission.to = if mission.system == home then mission.station elseif gate then gate.id else 0
    if mission.to == 0 then
      -- (nowhere to go: it is a plain escort, to see clear of its place)
      mission.aim, mission.need, mission.ends = "escort", 1, { #mission.waves }
    end
  end
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
        radius = 30, hull = "", expires = 2 ^ 52, salvaged = true, locked = false, lock = "",
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
  -- (a chief who was not brought down got away, and is worth more next time)
  if mission.captain then
    Captains.Escaped(state, mission.captain, events)
  end
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
  -- (and the rig a defence job was to hold, or the tender it was to see through, if it is still there)
  local rig = if Assault.Warded(mission) or mission.aim == "lost" then state.ships[mission.mark] else nil
  if rig then
    local ball = state.balls[rig.id]
    if ball then
      Space.RemoveBall(state, ball)
      table.insert(events, { kind = "BallRemoved", ball = rig.id, reason = "left" })
    end
    for _, item in Items.In(state, rig.id, nil) do
      Items.Take(state, item, item.quantity)
    end
    state.ships[rig.id] = nil
    State.RemoveId(state.shipIds, rig.id)
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

-- Ore has been mined (Tactical/Combat): if it was off a rock of a
-- mining contract's pocket, of the ore the contract is for, by a ship of
-- the pilot's, it is what the contract counts (up to what it wants).
-- Only ore so mined is taken for it: ore bought, or mined elsewhere, is
-- not. (The owner, 2026-11-22: "Only pocket ore counts", when the
-- earnings report found a contract could be filled at a profit of four
-- fifths from the station's own market, and the next taken at once.)
function Assault.Dug(state: State.State, ball: number, rock: number, ore: string, units: number)
  local object = Space.Object(state, rock)
  local ship = state.ships[ball]
  if object == nil or object.site == nil or ship == nil or ship.owner ~= "player" then
    return
  end
  local mission = roomOf(state, object.site)
  if mission and mission.kind == "mining" and mission.type == ore then
    mission.done = math.min(mission.need, mission.done + units)
  end
end

-- Whether a ship is the chief a camp job is to destroy.
function Assault.Chief(state: State.State, home: number, ship: number): boolean
  local mission = roomOf(state, home)
  return mission ~= nil and mission.aim == "chief" and mission.mark == ship
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
  -- (a camp to clear, and a rig to hold, count the ships that come; a camp to raze, what it is built of)
  local counts = if works then mission.aim == "raze" else mission.aim == "clear" or mission.aim == "hold"
  if counts then
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

-- Whether a job is a defence job with its ward still to keep: a rig to
-- hold, or a tender to see through, or in.
function Assault.Warded(mission: State.Mission): boolean
  return mission.kind == "assault" and (mission.aim == "hold" or Assault.Tender(mission.aim))
end

-- Whether a job's waves come on their own time (Assault.PRESS), whether
-- or not the one before is down: a rig to hold, and a tender to see
-- through past the first level; but an escort's past the second wait
-- again. (The owner, 2026-11-22: "Waves wait above L2", when the
-- earnings report's plain cruiser and battleship were swamped or pinned
-- at every escort of theirs, and held every rig.)
Assault.ESCORT_PRESSED = { [2] = true }
function Assault.Pressed(mission: State.Mission): boolean
  if mission.aim == "escort" then
    return Assault.ESCORT_PRESSED[mission.level] == true
  end
  return Assault.Warded(mission) and not (Assault.Tender(mission.aim) and mission.level <= 1)
end

-- A ship has been destroyed: if it was the rig a defence job was to
-- hold, or the tender it was to see through, the job is lost.
-- (Assets/Missions ends it: it is marked here. What it was to do is
-- kept in 'type', which such a job has no other use for.)
function Assault.Lost(state: State.State, ship: number, events: { Event })
  for _, id in state.missionIds do
    local mission = state.missions[id]
    if Assault.Warded(mission) and mission.mark ~= 0 and mission.mark == ship and mission.done < mission.need then
      table.insert(events, { kind = "WardLost", mission = mission.id, station = mission.station, escort = Assault.Tender(mission.aim) })
      mission.type = mission.aim
      mission.aim = "lost"
    end
  end
end

-- The way a job's tender flies: straight out from the middle of the
-- place, level, the way it was put down from it.
local function heading(state: State.State, mission: State.Mission): (number, number)
  local angle = Rng.Float(Rng.For(state.historySeed, mission.id, 71), 0, 2 * math.pi)
  return math.cos(angle), math.sin(angle)
end

-- A wave of a job's comes: its ships, so far out from a point of a
-- grid, all round it. They are of the job's place ('home') wherever
-- they come: they stay while the job is in hand, and go when it ends.
local function comes(state: State.State, mission: State.Mission, system: number, home: number, grid: number, x: number, y: number,
  z: number, least: number, most: number, events: { Event })
  mission.wave += 1
  local wave = mission.waves[mission.wave]
  local rng = Rng.For(state.historySeed, mission.id, mission.wave, 43)
  for index, kind in wave do
    local angle = Rng.Float(rng, 0, 2 * math.pi)
    local out = Rng.Float(rng, least, most)
    -- (the camp's chief is the first of the last wave: by name, of the grade the level says)
    local chief = mission.aim == "chief" and mission.wave == #mission.waves and index == 1
    local grade = if chief then Assault.CHIEF[mission.level] or 1 else 0
    local ball = Pirates.Spawn(state, Pirates.Graded(Pirates.kindById[kind], grade), system, x + out * math.cos(angle),
      y + Rng.Float(rng, -3000, 3000), z + out * math.sin(angle), home)
    if chief then
      mission.mark = ball.id
      local leader = Captains.Get(state, mission.captain)
      if leader then
        local name = Captains.Called(leader, grade, (string.gsub(Pirates.kindById[kind].name, "^Pirate ", "")))
        ball.name = name
        state.ships[ball.id].name = name
        state.pilots[ball.id].bounty = math.floor(state.pilots[ball.id].bounty * Captains.Price(leader))
        state.pilots[ball.id].captain = leader.id
      end
    end
    table.insert(events, { kind = "BallAdded", ball = ball.id })
  end
  table.insert(events, { kind = "PiratesArrived", grid = grid, count = #wave, wave = mission.wave, of = #mission.waves,
    chief = mission.aim == "chief" and mission.wave == #mission.waves, hold = mission.aim == "hold",
    escort = Assault.Tender(mission.aim), convoy = mission.aim == "convoy" and grid == mission.to })
end

-- A tender is out of the game: it has got clear, or got in.
local function gone(state: State.State, id: number)
  for _, item in Items.In(state, id, nil) do
    Items.Take(state, item, item.quantity)
  end
  state.ships[id] = nil
  State.RemoveId(state.shipIds, id)
end

-- Once a tick, wherever the pilot is: a tender that has got far enough
-- out from the middle of its place is clear, and gone, and the job is
-- done; or, for a convoy, it warps on to where it is going (the job's
-- station, or the gate that leads to it), where the last wave is
-- waiting for it, flies in, and docks or goes through, and the job is
-- done then.
local function arrive(state: State.State, events: { Event })
  for _, id in state.missionIds do
    local mission = state.missions[id]
    local tender = mission.kind == "assault" and Assault.Tender(mission.aim) and mission.done < mission.need and mission.mark ~= 0
    local ball = if tender then state.balls[mission.mark] else nil
    local ship = if tender then state.ships[mission.mark] else nil
    local place = if tender then Space.Object(state, mission.site) else nil
    if tender and mission.aim == "convoy" and mission.done >= 1 then
      -- On its way in, or there.
      local dest = Space.Object(state, mission.to)
      if (ship and ship.docked == mission.to) or (ball and ball.system ~= mission.system) then
        -- (docked, or through the gate: either way it is no part of the game any more)
        if ball then
          Space.RemoveBall(state, ball)
          table.insert(events, { kind = "BallRemoved", ball = ball.id, reason = "left" })
        end
        gone(state, mission.mark)
        mission.done = mission.need
        table.insert(events, { kind = "AssaultCleared", mission = mission.id, station = mission.station, aim = mission.aim,
          through = dest ~= nil and dest.kind == "gate" })
      elseif ball and dest and ball.warp == nil then
        if ball.grid == mission.to then
          if mission.wave < #mission.waves then
            comes(state, mission, ball.system, mission.site, ball.grid, ball.x, ball.y, ball.z, Assault.CONVOY_WAIT[1],
              Assault.CONVOY_WAIT[2], events)
            state.spawned[ball.grid] = state.tick
          end
          if ball.intent == nil then
            Space.Apply(state, { kind = if dest.kind == "gate" then "Jump" else "Dock", actor = ball.id, target = mission.to }, events)
          end
        else
          -- (it fell short, or was held: on again as soon as it can be)
          local on: State.Command = { kind = "WarpTo", actor = ball.id, target = mission.to, range = Assault.CONVOY_IN }
          if Space.Validate(state, on) then
            Space.Apply(state, on, events)
          end
        end
      end
    elseif ball and place then
      local far = math.sqrt((ball.x - place.x) ^ 2 + (ball.y - place.y) ^ 2 + (ball.z - place.z) ^ 2)
      local away: State.Command = { kind = "WarpTo", actor = ball.id, target = mission.to, range = Assault.CONVOY_IN }
      if far >= Assault.TENDER_OUT and mission.aim == "convoy" and Space.Validate(state, away) then
        Space.Apply(state, away, events)
        mission.done = 1
        table.insert(events, { kind = "WardAway", mission = mission.id, station = mission.station, ward = ball.id, to = mission.to })
      elseif far >= Assault.TENDER_OUT and mission.aim == "escort" then
        Space.RemoveBall(state, ball)
        gone(state, ball.id)
        mission.done = mission.need
        table.insert(events, { kind = "BallRemoved", ball = ball.id, reason = "warped" })
        table.insert(events, { kind = "AssaultCleared", mission = mission.id, station = mission.station, aim = mission.aim })
      elseif ball.mode ~= "goto" then
        -- (it keeps on its way out, whatever has happened to it: and a
        -- convoy's tender that is held out of warp keeps on too, until
        -- it is let go)
        local x, z = heading(state, mission)
        Space.Apply(state, { kind = "Goto", actor = ball.id, x = x, y = 0, z = z }, events)
      end
    end
  end
end

-- Once a tick: in a room of a camp that the pilot is in, with nobody of
-- it left and a wave of that room's still to come, it comes (the first
-- at once, the others after a breather). Where the job is to hold a
-- rig, the next comes anyway once the last has been there long enough.
function Assault.Step(state: State.State, events: { Event })
  arrive(state, events)
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
  -- What a defence job is to hold stands there from when the pilot
  -- first comes: a few kilometres from the middle of the place. And a
  -- tender to be seen through is waiting nearer the middle, and sets
  -- off straight out from it. ('mark' is it.) It is the faction's, and
  -- nobody's enemy.
  if Assault.Warded(mission) and mission.mark == 0 then
    local escort = Assault.Tender(mission.aim)
    local rng = Rng.For(state.historySeed, mission.id, 71)
    local angle = Rng.Float(rng, 0, 2 * math.pi)
    local out = if escort then Assault.TENDER_FROM else Rng.Float(rng, Assault.RIG_OUT[1], Assault.RIG_OUT[2])
    local hulls = if escort then Assault.TENDERS else Assault.RIGS
    local hull = Ships.byId[hulls[math.clamp(mission.level, 1, #hulls)]]
    local rig = Space.NewShip(state, hull.id, hull.name, mission.faction, 0)
    local ball = Space.Launch(state, rig, me.system, place.x + out * math.cos(angle), place.y + Rng.Float(rng, -500, 500),
      place.z + out * math.sin(angle))
    mission.mark = rig.id
    table.insert(events, { kind = "BallAdded", ball = ball.id })
    table.insert(events, { kind = "WardSighted", mission = mission.id, grid = place.id, ward = rig.id, escort = escort })
    if escort then
      Space.Apply(state, { kind = "Goto", actor = rig.id, x = math.cos(angle), y = 0, z = math.sin(angle) }, events)
    end
  end
  -- (nobody comes for a tender that has got clear, nor to the place a
  -- convoy's has left)
  if Assault.Tender(mission.aim) and mission.done >= 1 then
    return
  end
  if mission.wave >= mission.ends[room] then
    return
  end
  local last = state.spawned[me.grid]
  local since = if last ~= nil then (state.tick - last) * Constants.TICK else math.huge
  if #keepers(state, me.grid) > 0 then
    -- (whoever comes for a rig does not wait for those before them to
    -- be destroyed: so long after one wave came, the next does)
    if not Assault.Pressed(mission) or since < Assault.PRESS then
      return
    end
  elseif since < Assault.BREATHER then
    return
  end
  if Assault.Pressed(mission) then
    state.spawned[me.grid] = state.tick
  end
  -- Somewhere 25 to 35 km out from the middle of the place.
  comes(state, mission, me.system, place.id, place.id, place.x, place.y, place.z, 25000, 35000, events)
end

return Assault
