--!strict
-- Sovereignty: an open system as the pilot's own.
--
-- The project owner's rulings (2026-11-14). A system is claimed with a
-- tower: a Claim Beacon anchored at one of the pilot's lit towers, in
-- an open system that nobody holds. After some hours unchallenged the
-- system is theirs, and stays so while a tower of theirs stands there,
-- lit, with a beacon. Holding it gives their name on it (it is on the
-- star map as theirs, and they can give it a name of their own), order
-- kept there (it is lawless no longer: Strategic/Wars), and a place in
-- the diplomacy: a faction that thinks badly of the pilot and holds
-- space next to it may declare on them and besiege it, as it would an
-- enemy's claim, and the siege is a front to fight at (Tactical/
-- Fronts). What a system's trade would pay its holder is for later.
--
-- A beacon speaks for the system it stands in from the first hour: no
-- faction begins a claim of its own there while it stands. (A faction
-- that has claimed a system already keeps it: taking a faction's claim
-- for the pilot is not built.)
--
-- First figures: six hours to claim, and twelve dark before a claim is
-- let go.

local Constants = require("@lt/Core/Data/Constants")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Space = require("@lt/Core/Tactical/Space")
local Starbases = require("@lt/Core/Assets/Starbases")
local State = require("@lt/Core/Kernel/State")
local Wars = require("@lt/Core/Strategic/Wars")

local Sovereignty = {}

export type Event = { [string]: any }

-- Ticks in an hour; the hours a beacon has to stand before the system
-- is its keeper's; and the hours a system of the pilot's can be without
-- one before it is let go.
Sovereignty.HOUR = math.ceil(3600 / Constants.TICK)
Sovereignty.CLAIM, Sovereignty.LAPSE = 6, 12

-- The systems in which the pilot has a lit tower with a claim beacon
-- online.
local function beacons(state: State.State): { [number]: boolean }
  local lit: { [number]: boolean } = {}
  for _, id in state.starbaseIds do
    local starbase = state.starbases[id]
    if starbase.owner == Wars.PILOT and Starbases.Has(state, starbase, "claim") then
      lit[Space.SystemOf(state, id)] = true
    end
  end
  return lit
end

-- How a system stands for the pilot: "held" (theirs), "claiming" (a
-- beacon of theirs is up, with the hours it has stood and the hours it
-- takes), "contested" (a beacon is up, and something is being done to
-- the system by somebody else, or it is somebody's already), or "none".
function Sovereignty.Status(state: State.State, system: number): (string, number, number)
  local node = state.galaxy.systems[system]
  if node == nil then
    return "none", 0, Sovereignty.CLAIM
  elseif node.owner == Wars.PILOT then
    return "held", state.sovereignty.dark[system] or 0, Sovereignty.LAPSE
  elseif not beacons(state)[system] then
    return "none", 0, Sovereignty.CLAIM
  elseif node.owner ~= "" or node.uncharted then
    return "contested", 0, Sovereignty.CLAIM
  end
  return "claiming", state.sovereignty.progress[system] or 0, Sovereignty.CLAIM
end

-- Once a tick; it does something once an hour. A beacon in an open
-- system that nobody holds, and that nobody is doing anything to, has
-- stood an hour more, and when it has stood long enough the system is
-- the pilot's. A system of the pilot's with no beacon lit in it has
-- been dark an hour more, and is let go when it has been dark too long.
function Sovereignty.Step(state: State.State, events: { Event })
  local sovereignty = state.sovereignty
  local lit = beacons(state)
  -- (what the pilot's beacon stands in is spoken for, from the tick it
  -- is lit: no faction begins a claim of it, and one that was only
  -- mustering for it calls that off. Strategic/Wars)
  local spoken: { [number]: boolean } = {}
  for system in lit do
    if state.galaxy.systems[system].owner == "" then
      spoken[system] = true
    end
  end
  state.wars.spoken = spoken
  if state.tick % Sovereignty.HOUR ~= 0 or state.tick == 0 then
    return
  end
  local busy = Wars.Blocked(state.wars)
  for system in lit do
    local node = state.galaxy.systems[system]
    if node.owner == "" and not node.uncharted and not node.home and not busy[system] then
      local stood = (sovereignty.progress[system] or 0) + 1
      if stood >= Sovereignty.CLAIM then
        sovereignty.progress[system] = nil
        Wars.Take(state.galaxy, state.wars, system, Wars.PILOT)
        table.insert(events, { kind = "SystemTaken", system = system, by = Wars.PILOT, from = "" })
      else
        sovereignty.progress[system] = stood
      end
    end
  end
  for system in sovereignty.progress do
    if not lit[system] then
      sovereignty.progress[system] = nil
    end
  end
  for id = 1, Galaxy.Charted(state.galaxy) do
    if state.galaxy.systems[id].owner == Wars.PILOT then
      if lit[id] then
        sovereignty.dark[id] = nil
      else
        local dark = (sovereignty.dark[id] or 0) + 1
        if dark >= Sovereignty.LAPSE then
          sovereignty.dark[id] = nil
          Wars.Take(state.galaxy, state.wars, id, "")
          table.insert(events, { kind = "ClaimLapsed", system = id, by = Wars.PILOT })
        else
          sovereignty.dark[id] = dark
        end
      end
    elseif sovereignty.dark[id] then
      sovereignty.dark[id] = nil
    end
  end
end

function Sovereignty.Validate(state: State.State, command: State.Command): (boolean, string?)
  if command.kind ~= "RenameSystem" then
    return false, `unknown command '{command.kind}'`
  end
  local node = state.galaxy.systems[command.target or 0]
  if node == nil or node.owner ~= Wars.PILOT then
    return false, "that system is not yours to name"
  end
  -- (a name as a marked place's is: letters, figures and spaces, and not too long)
  local name, why = Space.PlaceName(command.what or "")
  if name == nil then
    return false, why
  end
  for id = 1, #state.galaxy.systems do
    if state.galaxy.systems[id].name == name and id ~= node.id then
      return false, "another system has that name"
    end
  end
  return true
end

function Sovereignty.Apply(state: State.State, command: State.Command, events: { Event })
  local node = state.galaxy.systems[command.target :: number]
  local was = node.name
  node.name = Space.PlaceName(command.what or "") :: string
  -- (what has been described of it goes by the new name too)
  local described = state.systems[node.id]
  if described then
    described.name = node.name
  end
  table.insert(events, { kind = "SystemRenamed", system = node.id, name = node.name, was = was })
end

return Sovereignty
