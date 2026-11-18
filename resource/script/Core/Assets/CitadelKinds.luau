--!strict
-- What a citadel's kind does where it stands (Data/Structures'
-- CITADEL_KINDS and CITADEL_BONUS): the bonus a station gives to the
-- work done at it, and what its kind's own modules open there. Asked of
-- by Assets/Industry, Assets/Market and Assets/Starbases. (Whether the
-- service the work wants is online is Assets/Stations' to say: a bonus
-- is had only where the work can be done at all.)

local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")

local CitadelKinds = {}

local NONE: Structures.CitadelBonus = {}

-- The kind of citadel a station is, if it is one of a kind.
function CitadelKinds.Of(state: State.State, station: number?): string?
  local starbase = if station then state.starbases[station] else nil
  local tower = if starbase then Structures.towerById[starbase.tower] else nil
  return if tower and tower.citadel then tower.kind else nil
end

-- What the station does better, by its kind: nothing, if it is no citadel.
function CitadelKinds.Bonus(state: State.State, station: number?): Structures.CitadelBonus
  local kind = CitadelKinds.Of(state, station)
  return if kind then Structures.CITADEL_BONUS[kind] or NONE else NONE
end

-- Whether a citadel has a module online that opens what is asked
-- ("capital", "advanced", "invention": Data/Structures' 'opens').
function CitadelKinds.Opens(state: State.State, station: number, what: string): boolean
  local starbase = state.starbases[station]
  if starbase == nil then
    return false
  end
  for _, module in starbase.modules do
    if state.tick >= module.ready and Structures.moduleById[module.type].opens == what then
      return true
    end
  end
  return false
end

-- Whether a station is a citadel (where those modules are wanted).
function CitadelKinds.IsCitadel(state: State.State, station: number?): boolean
  local starbase = if station then state.starbases[station] else nil
  local tower = if starbase then Structures.towerById[starbase.tower] else nil
  return tower ~= nil and tower.citadel == true
end

return CitadelKinds
