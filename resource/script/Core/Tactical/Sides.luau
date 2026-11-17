--!strict
-- Sides: whose side the pilot is on in the factions' wars, and who
-- treats them as an enemy for it. The owner's rulings, 2026-11-16, of
-- being caught in a war (all four of what was put to them):
--
--   - "Enemy of your side": once the pilot has fought or done war work
--     for one side, the other side's fleets and navy attack them on
--     sight in their space and at the front, until the war ends or
--     their standing with that side recovers.
--   - "Blockades stop you": a side's blockade fleets at the gates of a
--     contested system stop and fight anyone on the other side's books
--     (Tactical/Traffic's pickets).
--   - "Stations shut": that side's stations refuse them docking
--     (Tactical/Space).
--   - "Neutral is safe": one who has worked for neither side is left
--     alone, even at the front.
--
-- What counts as serving a side: firing on the other side's ships at a
-- front (Tactical/Fronts), or a war job done for it (Assets/Missions),
-- which costs standing with the other side too. Recovered: standing with
-- the other side back to Sides.FORGIVEN. (The figures are mine.) Read
-- by the rules of space itself (docking), so this asks nothing of them:
-- a standing is read straight from the state, as Assets/Standings has
-- it.

local Factions = require("@lt/Core/Data/Factions")
local Nomads = require("@lt/Core/Tactical/Nomads")
local State = require("@lt/Core/Kernel/State")
local Wars = require("@lt/Core/Strategic/Wars")

export type Event = { [string]: any }

local Sides = {}

-- The standing with the other side at which the pilot is no longer its
-- enemy for having served its foe; and what a war job done costs with
-- the other side.
Sides.FORGIVEN = 0
Sides.GRUDGE = 0.5

-- The pilot has served a side: fought for it, or done its war work.
function Sides.Serve(state: State.State, faction: string, events: { Event }?)
  if Factions.byId[faction] == nil then
    return
  end
  local served = state.served or {}
  state.served = served
  if served[faction] == nil and events then
    table.insert(events, { kind = "SideTaken", faction = faction })
  end
  served[faction] = state.tick
end

-- The side the pilot has served that a faction is at war with, if that
-- faction counts them its enemy for it now; nil if it does not.
function Sides.EnemyOf(state: State.State, faction: string): string?
  local served = state.served
  if served == nil or Factions.byId[faction] == nil or (state.standings[faction] or 0) >= Sides.FORGIVEN then
    return nil
  end
  -- (in the order of their names: what is found does not hang on how a table is walked)
  local sides: { string } = {}
  for side in served do
    table.insert(sides, side)
  end
  table.sort(sides)
  for _, side in sides do
    if side ~= faction and Wars.AtWar(state.wars, side, faction) then
      return side
    end
  end
  return nil
end

-- Whose a station is, for whom it shuts its doors: a colony ship's
-- people, or the faction that holds the system.
function Sides.StationOf(state: State.State, station: number, system: number): string
  local fleet = Nomads.FleetOf(state.galaxy, station)
  if fleet then
    return fleet.faction
  end
  local node = state.galaxy.systems[system]
  return if node and Factions.byId[node.owner] then node.owner else ""
end

return Sides
