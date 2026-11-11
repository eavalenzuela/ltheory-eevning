--!strict
-- An assault: a job to clear a pirate camp, at a place made for it.
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
-- ship of theirs destroyed counts toward the job, whoever of the
-- pilot's side does it, and pays its own bounty as any pirate does.
-- With the last wave down the job is done, and is paid at the station
-- that gave it (Assets/Missions). Finished, given up or lapsed, the
-- camp goes, and whoever is left of it.
--
-- (EVE's security missions, cut down. Not yet: rooms with gates between
-- them, things to fetch or to destroy other than ships, a camp that is
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
-- How many waves a camp of each level has.
Assault.WAVES = { 2, 3, 3, 3 }
-- Seconds between the last ship of a wave and the first of the next.
Assault.BREATHER = 20
-- What a job pays, as a share of the bounties on the camp's keepers,
-- with so much for each level beside; and the standing it is worth.
Assault.SHARE = 0.6
Assault.BASE = 5000
Assault.CREDIT = 0.15

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

-- What a job to clear a camp pays (before what the pilot's standing
-- adds), and the standing it is worth.
function Assault.Pay(level: number, waves: { { string } }): (number, number)
  local _, bounty = Assault.Count(waves)
  return math.floor(Assault.SHARE * bounty) + Assault.BASE * level, Assault.CREDIT * level
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

-- The job is taken: its camp is on the charts.
function Assault.Open(state: State.State, mission: State.Mission, events: { Event })
  local site = Sites.Stake(state, mission.system, Rng.For(state.historySeed, mission.id, 59), "Pirate Camp")
  if site then
    mission.site = site.id
    table.insert(events, { kind = "SiteAppeared", site = site.id, system = site.system, what = "mission" })
  end
end

-- Whoever of a camp is still in it.
local function keepers(state: State.State, site: number): { number }
  local found: { number } = {}
  for _, id in state.pilotIds do
    if state.pilots[id].home == site and state.balls[id] then
      table.insert(found, id)
    end
  end
  return found
end

-- The job is over, however it ended: the camp goes, and whoever is
-- left of it. (What they left in wrecks stays until it fades.)
function Assault.Close(state: State.State, mission: State.Mission, events: { Event })
  if mission.site == 0 then
    return
  end
  for _, id in keepers(state, mission.site) do
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
  Sites.Release(state, mission.site, events)
  state.spawned[mission.site] = nil
end

-- A ship that kept a place has been destroyed (Tactical/Aftermath, once
-- it is gone): if the place is a camp a job is to clear, it counts, and
-- with the last of a wave the next is due, or the job is done.
function Assault.Fell(state: State.State, home: number, events: { Event })
  for _, id in state.missionIds do
    local mission = state.missions[id]
    if mission.kind == "assault" and mission.site ~= 0 and mission.site == home and mission.done < mission.need then
      mission.done += 1
      if #keepers(state, home) == 0 then
        state.spawned[home] = state.tick
        local cleared = mission.wave >= #mission.waves
        table.insert(events, { kind = if cleared then "AssaultCleared" else "WaveDown", mission = id, station = mission.station,
          wave = mission.wave, of = #mission.waves })
      end
    end
  end
end

-- Once a tick: at a camp the pilot is at, with nobody of it left and a
-- wave still to come, it comes (the first at once, the others after a
-- breather).
function Assault.Step(state: State.State, events: { Event })
  local me = state.balls[state.player.ship]
  if me == nil or me.grid == 0 or Ships.byId[state.ships[me.id].type].class == "capsule" then
    return
  end
  for _, id in state.missionIds do
    local mission = state.missions[id]
    if mission.kind == "assault" and mission.site == me.grid and mission.wave < #mission.waves and #keepers(state, mission.site) == 0 then
      local last = state.spawned[mission.site]
      local place = Space.Object(state, mission.site)
      if place and (last == nil or (state.tick - last) * Constants.TICK >= Assault.BREATHER) then
        mission.wave += 1
        local wave = mission.waves[mission.wave]
        local rng = Rng.For(state.historySeed, mission.id, mission.wave, 43)
        for _, kind in wave do
          -- Somewhere 25 to 35 km out from the middle of the place.
          local angle = Rng.Float(rng, 0, 2 * math.pi)
          local out = Rng.Float(rng, 25000, 35000)
          local ball = Pirates.Spawn(state, Pirates.kindById[kind], me.system,
            place.x + out * math.cos(angle), place.y + Rng.Float(rng, -3000, 3000), place.z + out * math.sin(angle), place.id)
          table.insert(events, { kind = "BallAdded", ball = ball.id })
        end
        table.insert(events, { kind = "PiratesArrived", grid = place.id, count = #wave, wave = mission.wave, of = #mission.waves })
      end
    end
  end
end

return Assault
