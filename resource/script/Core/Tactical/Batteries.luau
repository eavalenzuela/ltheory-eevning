--!strict
-- Batteries: the guns of a station.
--
-- A station's gun and missile batteries (Data/Structures) fire on what
-- has no business on its grid: any pirate, and a pilot the patrols have
-- marked (Tactical/Traffic). A pilot's own starbase fires on pirates
-- and never on its owner, and only while it is lit. A battery does not
-- miss: it is a big gun on a still platform with nothing else to do.
--
-- Only the station whose grid the pilot is on is looked at, as with
-- everything else that happens where the pilot is not.
--
-- A gate in space somebody holds is guarded the same way, by sentry
-- guns: they fire on pirates and on a marked pilot at the gate.
--
-- (Not yet: batteries and sentries as things that can be shot at, a
-- battery's own range and tracking, a starbase's batteries waiting to
-- come online.)

local Galaxy = require("@lt/Core/Describe/Galaxy")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Stations = require("@lt/Core/Assets/Stations")

local Batteries = {}

export type Event = { [string]: any }
export type Hit = { target: number, by: number, damage: { number } }

-- How far from the tower a battery reaches, m.
Batteries.RANGE = 45000
-- A battery's volley (EM, thermal, kinetic, explosive) and the ticks
-- between volleys: twenty points a second from a gun battery, fifteen
-- from a missile battery.
local GUN = { every = 3, damage = { 0, 15, 30, 15 } }
local MISSILE = { every = 6, damage = { 0, 0, 45, 45 } }

-- What the batteries of the station the pilot is at do this tick: the
-- hits they land, for Combat to apply with everybody else's.
function Batteries.Fire(state: State.State, events: { Event }): { Hit }
  local hits: { Hit } = {}
  local me = state.balls[state.player.ship]
  local station = if me and me.grid ~= 0 then Space.Object(state, me.grid) else nil
  if me == nil or station == nil then
    return hits
  end
  -- A gate in space somebody holds has sentry guns: three where order
  -- is kept, two where it is thin. (Nobody guards a gate that is nobody's.)
  local sentries = 0
  if station.kind == "gate" then
    local node = state.galaxy.systems[me.system]
    sentries = if node.owner == "" then 0 elseif Galaxy.Band(node.security) == "secure" then 3 else 2
    if sentries == 0 then
      return hits
    end
  elseif station.kind ~= "station" or not Stations.Has(state, station.id, "defence") then
    return hits
  end
  local own = state.starbases[station.id] ~= nil
  local marked = not own and state.tick < state.player.marked
  local targets: { number } = {}
  for _, id in state.ballIds do
    local ball = state.balls[id]
    local ship = state.ships[id]
    if ball.system == me.system and ball.grid == me.grid and ship and Ships.byId[ship.type].class ~= "capsule"
      and (ship.owner == "pirates" or (marked and id == me.id))
      and not (ball.warp and ball.warp.stage == "warp")
      and Space.Distance(ball :: any, station :: any) <= Batteries.RANGE then
      table.insert(targets, id)
    end
  end
  if #targets == 0 then
    return hits
  end
  local modules: { string } = if sentries > 0 then table.create(sentries, "battery.gun") else (Stations.Makeup(state, station.id) :: any).modules
  local index = 0
  for _, module in modules do
    local battery = if module == "battery.gun" then GUN elseif module == "battery.missile" then MISSILE else nil
    if battery then
      index += 1
      -- (each on its own beat, and each at its own one of them, in turn)
      if (state.tick + index * 2) % battery.every == 0 then
        local target = targets[(index - 1) % #targets + 1]
        table.insert(hits, { target = target, by = station.id, damage = table.clone(battery.damage) })
        table.insert(events, { kind = "BatteryFired", station = station.id, battery = index, to = target, missile = battery == MISSILE })
      end
    end
  end
  return hits
end

return Batteries
