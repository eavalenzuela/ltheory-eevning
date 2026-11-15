--!strict
-- What can be done at a station: only what it has a module for.
--
-- A station is a control tower and the modules anchored round it
-- (Data/Structures), and a service is there because its module is: no
-- trade hub, no market; no ship maintenance array, no fitting, repairs
-- or changing ships; no refining array, no refining; no ship assembly
-- array, nothing built. This holds at every station (the project
-- owner's decision). So that a new pilot is not stranded, the station a
-- pilot starts at is given every module that the whole round of
-- mining, refining, building, selling and fitting needs, whatever kind
-- of station it is.
--
-- What a station is made of follows from what it is (its kind, its
-- size, and whether it is the starter), so nothing is kept in the state
-- for it. Mooring, keeping things in the hangar, the wallet and
-- training are not any module's: they can be done at any station.

local Constants = require("@lt/Core/Data/Constants")
local Space = require("@lt/Core/Tactical/Space")
local Starbases = require("@lt/Core/Assets/Starbases")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")

local Stations = {}

-- The station a new pilot starts at: the first station of system 1.
function Stations.Starter(state: State.State): number
  for _, object in Space.Describe(state, 1).objects do
    if object.kind == "station" then
      return object.id
    end
  end
  error("the first system has no station")
end

-- What a station is made of: its tower and its modules. Nil if 'id' is
-- not a station.
function Stations.Makeup(state: State.State, id: number): Structures.Makeup?
  -- (a station of a system nobody has been to yet has its makeup too)
  local object = Space.Peek(state, id)
  if object == nil or object.kind ~= "station" then
    return nil
  end
  -- (a pilot's own: what has been anchored there, online or not)
  local starbase = state.starbases[id]
  if starbase then
    return Starbases.Makeup(starbase)
  end
  -- (a colony ship of the nomads is its people's, wherever it is)
  local fleet = Space.Colony(state, id)
  if fleet then
    return Structures.Makeup(object.variety, object.radius, fleet.faction, false)
  end
  -- (its tower is of the faction whose homeworld is nearest: a station in
  -- space nobody holds was still built by somebody)
  local faction = state.galaxy.systems[Space.SystemOf(state, id)].nearest
  return Structures.Makeup(object.variety, object.radius, faction, id == Stations.Starter(state))
end

-- Whose a station is: the nomads' whose colony ship it is, and else the
-- people who built its tower (those whose homeworld is nearest, in held
-- space and in open space alike). "" for what is no station.
function Stations.People(state: State.State, id: number): string
  local object = Space.Peek(state, id)
  if object == nil or object.kind ~= "station" then
    return ""
  end
  local fleet = Space.Colony(state, id)
  if fleet then
    return fleet.faction
  end
  return state.galaxy.systems[Space.SystemOf(state, id)].nearest
end

-- Whether a station has a module that gives a service.
-- Whether something going on has put a station's service out of use
-- (Strategic/Happenings, seen here by the state alone): its works are
-- being mended (Tactical/Mishaps), or invaders are at the stations of
-- its system (Tactical/Invasions), which stops every works there. The
-- seconds until it is mended, if that is known; nil if it is in use.
local WORKS: { [string]: boolean } = { refining = true, industry = true, research = true }
function Stations.Out(state: State.State, id: number, service: Structures.Service): number?
  for _, one in state.happenings.list do
    if one.kind == "disaster" and one.place == id and one.what == service then
      return math.max(0, one.ends - state.tick) * Constants.TICK
    elseif one.kind == "invasion" and one.stage >= 3 and WORKS[service] and state.starbases[id] == nil
      and one.system == Space.SystemOf(state, id) then
      return math.max(0, one.ends - state.tick) * Constants.TICK
    end
  end
  return nil
end

function Stations.Has(state: State.State, id: number, service: Structures.Service): boolean
  if Stations.Out(state, id, service) then
    return false
  end
  -- (a pilot's own gives only what is online, and nothing when it is dark)
  local starbase = state.starbases[id]
  if starbase then
    return Starbases.Has(state, starbase, service)
  end
  local makeup = Stations.Makeup(state, id)
  if makeup then
    for _, module in makeup.modules do
      if Structures.moduleById[module].service == service then
        return true
      end
    end
  end
  return false
end

-- The services a station gives, in the order of Structures.SERVICES.
function Stations.Services(state: State.State, id: number): { Structures.Service }
  local found: { Structures.Service } = {}
  for _, service in Structures.SERVICES do
    if Stations.Has(state, id, service) then
      table.insert(found, service)
    end
  end
  return found
end

-- The service each kind of command is done by. (A command not here is
-- nobody's: it can be given anywhere it makes sense.)
local FITTING: Structures.Service, REFINING: Structures.Service = "fitting", "refining"
local INDUSTRY: Structures.Service, MARKET: Structures.Service = "industry", "market"
local RESEARCH: Structures.Service = "research"
local NEEDS: { [string]: Structures.Service } = {
  Fit = FITTING, Unfit = FITTING, LoadCharge = FITTING, Repair = FITTING, Assemble = FITTING, BoardShip = FITTING,
  Reprocess = REFINING,
  StartJob = INDUSTRY,
  StartResearch = RESEARCH,
  BuyNow = MARKET, SellNow = MARKET, PlaceOrder = MARKET, ModifyOrder = MARKET,
  AcceptContract = MARKET, FillContract = MARKET, ListContract = MARKET,
}

-- Whether the station a command is given at can carry it out. (A
-- command given by a ship that is not docked is not this module's to
-- refuse: whoever carries it out says whether it can be done in space.)
function Stations.Validate(state: State.State, command: State.Command): (boolean, string?)
  if command.kind == "Dock" then
    -- (nobody moors at a tower that is still being anchored)
    local starbase = state.starbases[command.target or 0]
    if starbase and not Starbases.Anchored(state, starbase) then
      return false, "the tower is not anchored yet"
    end
    return true
  end
  local service = NEEDS[command.kind]
  local ship = state.ships[command.actor]
  if service == nil or ship == nil or ship.docked == 0 then
    return true
  end
  if Stations.Makeup(state, ship.docked) == nil or Stations.Has(state, ship.docked, service) then
    return true
  end
  local out = Stations.Out(state, ship.docked, service)
  if out then
    return false, `the {Structures.Provider(service)} here is out of use, for {math.ceil(out / 3600)} h more`
  end
  return false, `this station has no {Structures.Provider(service)}`
end

return Stations
