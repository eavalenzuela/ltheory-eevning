--!strict
-- Standings: what each faction thinks of the pilot, from -10 to 10.
--
-- It is earned by doing a faction's jobs (Assets/Missions) and, a little
-- at a time, by killing pirates in its space. It is lost by firing on
-- its ships, or on anybody's in its space (half a point each time the
-- pilot is marked for it, Tactical/Combat), and by destroying them (a
-- point more). It is remembered after the mark has lapsed.
--
-- What it does:
--   - a faction's stations charge a pilot they think well of less to
--     trade, and one they think ill of more: 3% of the broker's fee and
--     the sales tax for each point, to half as much or half as much
--     again;
--   - its jobs pay 3% more a point (Assets/Missions);
--   - at -5 its patrols fight the pilot on sight (Tactical/Traffic).
-- A grudge fades: a standing below nothing rises a twentieth of a point
-- an hour, so nobody is shut out for good.
--
-- (Not yet: anything a high standing opens, standing with the pirates,
-- factions minding what a pilot does to each other's ships.)

local Constants = require("@lt/Core/Data/Constants")
local Factions = require("@lt/Core/Data/Factions")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")

local Standings = {}

export type Event = { [string]: any }

Standings.HOSTILE = -5
Standings.MARKED = -0.5       -- for being marked: firing on somebody who is no pirate
Standings.KILLED = -1         -- and for destroying them
Standings.PIRATE = 0.02       -- for a pirate destroyed in a faction's space
Standings.FORGOTTEN = 0.05    -- what a grudge fades by in an hour
local HOUR = math.ceil(3600 / Constants.TICK)

function Standings.Of(state: State.State, faction: string): number
  return state.standings[faction] or 0
end

-- Whether a faction's patrols fight the pilot on sight.
function Standings.Hostile(state: State.State, faction: string): boolean
  return Standings.Of(state, faction) <= Standings.HOSTILE
end

-- Change the pilot's standing with a faction (nothing happens for
-- anybody who is not one of the factions).
function Standings.Change(state: State.State, faction: string, by: number, events: { Event }?)
  if Factions.byId[faction] == nil or by == 0 then
    return
  end
  local now = math.clamp(Standings.Of(state, faction) + by, -10, 10)
  state.standings[faction] = now
  if events then
    table.insert(events, { kind = "StandingChanged", faction = faction, by = by, standing = now })
  end
end

-- The faction that minds what is done to a ship of an owner in a
-- system: the ship's own, if it is a faction's, else whoever holds the
-- system. "" for nobody.
function Standings.Minds(state: State.State, owner: string, system: number): string
  if Factions.byId[owner] and Factions.byId[owner].kind == "human" then
    return owner
  end
  local node = state.galaxy.systems[system]
  return if node then node.owner else ""
end

-- What a station's fees and taxes are multiplied by for this pilot.
function Standings.Fees(state: State.State, station: number): number
  local node = state.galaxy.systems[Space.SystemOf(state, station)]
  if node == nil then
    return 1
  end
  return math.clamp(1 - 0.03 * Standings.Of(state, node.nearest), 0.5, 1.5)
end

-- Once a tick: on the hour, every grudge fades a little.
function Standings.Step(state: State.State)
  if state.tick % HOUR ~= 0 then
    return
  end
  for _, faction in Factions.list do
    local now = state.standings[faction.id]
    if now and now < 0 then
      state.standings[faction.id] = math.min(0, now + Standings.FORGOTTEN)
    end
  end
end

return Standings
