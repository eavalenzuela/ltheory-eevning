--!strict
-- The galaxy's own tick as Core.Step steps it, with nobody flying in it:
-- the pirates' pressure (Strategic/Happenings), the factions at war
-- (Strategic/Wars), and every ten game minutes the economy (Strategic/
-- Commerce: its gluts and shortages, then its flows). For the windowless
-- tools that run a galaxy for days (Tool/galaxyrun, Tool/galaxydiverge),
-- so that what they judge is what a game runs. (Core.Step does the same
-- things in the same order among everything else; a change there is to
-- be made here too.)
local Commerce = require("@lt/Core/Strategic/Commerce")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Happenings = require("@lt/Core/Strategic/Happenings")
local Standings = require("@lt/Core/Assets/Standings")
local State = require("@lt/Core/Kernel/State")
local Wars = require("@lt/Core/Strategic/Wars")

local GalaxyStep = {}

-- Time spent, in seconds: on the economy, and on the rest.
GalaxyStep.econ, GalaxyStep.rest = 0, 0

-- Step 'state' to its next tick, with what happens in 'events'. 'here' is
-- the system the pilot would be in (the pirates' pressure is let down
-- where the pilot is).
function GalaxyStep.Step(state: State.State, events: { any }, here: number)
  local tick = state.tick + 1
  state.tick = tick
  local galaxy = state.galaxy
  local started = Host.Clock()
  Happenings.Step(state, events)
  local hostile: { [string]: boolean }? = nil
  if state.wars.on and tick % Wars.HOUR == 0 then
    local those: { [string]: boolean } = {}
    for _, faction in Galaxy.Holders(galaxy) do
      those[faction] = Standings.Hostile(state, faction)
    end
    hostile = those
  end
  Wars.Step(galaxy, state.wars, state.historySeed, tick, events, hostile, state.commerce)
  GalaxyStep.rest += Host.Clock() - started
  if tick % Commerce.STEP == 0 then
    started = Host.Clock()
    Commerce.Stir(state.commerce, galaxy, state.shocks, state.historySeed, tick, Commerce.STEP, events)
    Happenings.Press(state, events, here, Commerce.Carries(state.commerce, Galaxy.Charted(galaxy)))
    Commerce.Advance(state.commerce, galaxy, Happenings.Surging(state), Commerce.STEP, Wars.Blocked(state.wars))
    GalaxyStep.econ += Host.Clock() - started
  end
end

return GalaxyStep
