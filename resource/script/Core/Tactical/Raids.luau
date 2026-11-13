--!strict
-- Raids: pirates come for a pilot's tower.
--
-- A tower where order is kept is left alone. One in low security or in
-- lawless space is raided now and then: the less safe the space, the
-- oftener and the harder. What stands against a raid is what the tower
-- has to shoot with (each gun or missile battery that is online) and
-- whoever of the pilot's hired pilots is holding the place (set to
-- patrol there, and in space on its grid).
--
-- With the pilot there (in space on the tower's grid, or moored at it)
-- a raid is a pack that arrives, and is fought as any fight is: the
-- batteries fire (Tactical/Batteries), the patrol fights, the pilot
-- may. With the pilot somewhere else it is settled at once, strength
-- against strength:
--   - beaten off, if the defence is as strong as the raid;
--   - and if it is not, the raiders get at what the drill has brought
--     up. They carry off a share of the moon material in the tower's
--     hangar, the bigger the more they outmatch the defence (never all
--     of it), and the drill is out for an hour.
-- Nothing else of the pilot's is touched, and the tower stands: a raid
-- is after what can be carried, and what a drill brings up is lying in
-- the open.
--
-- (Every figure is a first proposal. Not yet: a raid that takes a
-- tower down, or a tower that holds out on a timer.)

local Constants = require("@lt/Core/Data/Constants")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Moons = require("@lt/Core/Data/Moons")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local Starbases = require("@lt/Core/Assets/Starbases")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")

local Raids = {}

export type Event = { [string]: any }

local HOUR = math.floor(3600 / Constants.TICK + 0.5)

-- Hours from one raid to the next, at least and at most, by how safe
-- the tower's system is. (None where order is kept.)
Raids.EVERY = { low = { 8, 14 }, lawless = { 3, 6 } } :: { [string]: { number } }
-- How strong a raid is, at least and at most.
Raids.STRENGTH = { low = { 2, 4 }, lawless = { 4, 9 } } :: { [string]: { number } }
-- What a battery online is worth against one, and a hired pilot's ship
-- holding the place, by its class.
Raids.BATTERY = 2
Raids.PATROL = { frigate = 1, destroyer = 2, cruiser = 4, battleship = 8 } :: { [string]: number }
-- The most of what is there that raiders carry off, and how long the
-- drill is out after they have been (seconds).
Raids.MOST = 0.8
Raids.DOWN = 3600

-- How safe a starbase's system is: "secure", "low" or "lawless".
function Raids.Band(state: State.State, starbase: State.Starbase): string
  return Galaxy.Band(state.galaxy.systems[Space.SystemOf(state, starbase.id)].security)
end

-- What a starbase has against a raid: its strength in all, how many
-- batteries of it are online, and how many hired pilots hold the place.
function Raids.Defence(state: State.State, starbase: State.Starbase): (number, number, number)
  local batteries, patrol, strength = 0, 0, 0
  if Starbases.Lit(state, starbase) then
    for _, module in starbase.modules do
      if state.tick >= module.ready and Structures.moduleById[module.type].service == "defence" then
        batteries += 1
        strength += Raids.BATTERY
      end
    end
  end
  for _, id in state.fleetIds do
    local wing = state.fleet[id]
    local ship = state.ships[wing.ship]
    local ball = if ship then state.balls[ship.id] else nil
    if wing.order == "patrol" and wing.post == starbase.id and ship and ball and ball.grid == starbase.id
      and ball.system == Space.SystemOf(state, starbase.id) then
      local worth = Raids.PATROL[Ships.byId[ship.type].class] or 0
      if worth > 0 then
        patrol += 1
        strength += worth
      end
    end
  end
  return strength, batteries, patrol
end

-- When the next raid on a starbase is due, from now: the tick. (0 for
-- one that is left alone.)
local function due(state: State.State, starbase: State.Starbase): number
  local every = Raids.EVERY[Raids.Band(state, starbase)]
  if every == nil then
    return 0
  end
  local rng = Rng.For(state.historySeed, starbase.id, starbase.raids, 811)
  return state.tick + math.floor(Rng.Float(rng, every[1], every[2]) * HOUR)
end

-- Whether the pilot is at a starbase: moored there, or in space on its grid.
local function present(state: State.State, starbase: State.Starbase): boolean
  local ship = state.ships[state.player.ship]
  local ball = state.balls[state.player.ship]
  if ship and ship.docked == starbase.id then
    return true
  end
  return ball ~= nil and ball.grid == starbase.id and ball.system == Space.SystemOf(state, starbase.id)
end

-- Once a tick: a raid that is due comes.
function Raids.Step(state: State.State, events: { Event })
  for _, id in state.starbaseIds do
    local starbase = state.starbases[id]
    local band = Raids.Band(state, starbase)
    local ranges = Raids.STRENGTH[band]
    if ranges == nil or not Starbases.Anchored(state, starbase) then
      starbase.raid = 0
    elseif starbase.raid == 0 then
      starbase.raid = due(state, starbase)
    elseif state.tick >= starbase.raid and not state.peaceful then
      local rng = Rng.For(state.historySeed, starbase.id, starbase.raids, 823)
      local strength = ranges[1] + Rng.Int(rng, ranges[2] - ranges[1] + 1)
      local defence = Raids.Defence(state, starbase)
      local station = Space.Object(state, id)
      if present(state, starbase) and station then
        -- The pilot is there: they come, and it is fought.
        Pirates.Arrive(state, Space.SystemOf(state, id), station, band, false, events)
        table.insert(events, { kind = "TowerRaided", station = id, outcome = "fought", strength = strength, defence = defence, taken = 0 })
      elseif defence >= strength then
        table.insert(events, { kind = "TowerRaided", station = id, outcome = "beaten", strength = strength, defence = defence, taken = 0 })
      else
        -- They get in at what the drill has brought up, and the drill.
        local share = math.min(Raids.MOST, (strength - defence) / strength)
        local taken, type = 0, ""
        -- (out of the pilot's hangar there and the corporation's alike)
        for _, item in Items.Stored(state, id) do
          if Moons.byId[item.type] then
            local units = math.floor(item.quantity * share)
            if units > 0 then
              taken += units
              type = item.type
              Items.Take(state, item, units)
            end
          end
        end
        for _, module in starbase.modules do
          if module.type == Structures.DRILL then
            module.ready = math.max(module.ready, state.tick + math.ceil(Raids.DOWN / Constants.TICK))
          end
        end
        starbase.robbed += taken
        table.insert(events, { kind = "TowerRaided", station = id, outcome = "robbed", strength = strength, defence = defence,
          taken = taken, type = type })
      end
      starbase.raids += 1
      starbase.raid = due(state, starbase)
    elseif state.tick >= starbase.raid then
      -- (a game with no pirates in it has no raids: ask again later)
      starbase.raids += 1
      starbase.raid = due(state, starbase)
    end
  end
end

return Raids
