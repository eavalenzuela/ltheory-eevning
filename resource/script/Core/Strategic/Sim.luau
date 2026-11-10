--!strict
-- The strategic simulation's tick: ten game seconds of the whole
-- galaxy. (docs/roadmap.md §6.)
--
--   every tick     timers that have run out: fleets arrive, ships are
--                  launched; then each power's government takes its turn
--                  to think (once a minute each, staggered)
--   every minute   lanes are reset from who holds what; the economy
--                  steps; a round is fought wherever enemies meet; sieges
--                  advance
--   every ten      order (pirate pressure, control, security), money
--   minutes        (levy, upkeep, arrears), the pirates, diplomacy
--                  (relations, wars, coalitions, peace), budgets
--
-- The same world and the same number of ticks always give the same
-- result: every roll comes from the history seed, the tick and what is
-- being rolled for.

local Atlas = require("@lt/Core/Strategic/Atlas")
local Battle = require("@lt/Core/Strategic/Battle")
local Diplomacy = require("@lt/Core/Strategic/Diplomacy")
local Economy = require("@lt/Core/Strategic/Economy")
local Fiscal = require("@lt/Core/Strategic/Fiscal")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Mind = require("@lt/Core/Strategic/Mind")
local Order = require("@lt/Core/Strategic/Order")
local Orders = require("@lt/Core/Strategic/Orders")
local Powers = require("@lt/Core/Data/Powers")
local Raiders = require("@lt/Core/Strategic/Raiders")
local World = require("@lt/Core/Strategic/World")

local Sim = {}

-- A new world: a galaxy of 'systems' systems from 'galaxySeed', at the
-- founding. 'historySeed' drives every roll made from then on.
function Sim.New(galaxySeed: number, systems: number, historySeed: number): World.World
  local galaxy = Galaxy.Describe(galaxySeed, systems)
  local world = World.New(galaxy, Atlas.Describe(galaxy, galaxySeed), historySeed)
  for id, s in world.systems do
    s.security = Order.Security(world, id)
  end
  Order.Lanes(world)
  return world
end

-- A fleet has reached the end of a move.
local function arrived(world: World.World, fleet: World.Fleet)
  local at = fleet.system
  local task = fleet.task
  if at ~= fleet.target then
    -- Stopped short. A retreat is over; anything else waits for its
    -- government to send it on.
    if task == "retreat" or task == "home" then
      fleet.task = ""
    end
    return
  end
  if task == "attack" then
    local faction = world.factions[fleet.owner]
    local plan = faction.plan
    local planned = if plan and plan.target == at then plan.since else world.tick
    if Battle.Besiege(world, fleet, "siege", planned) then
      if plan and plan.target == at then
        faction.plan = nil
      end
    else
      fleet.task = ""
    end
  elseif task == "claim" or task == "clear" then
    if not Battle.Besiege(world, fleet, task) then
      fleet.task = ""
    end
  elseif task == "raid" then
    Raiders.Arrived(world, fleet)
  elseif task == "found" then
    Raiders.Found(world, fleet)
  elseif task == "relief" then
    fleet.task = "hold"
  elseif task == "retreat" or task == "home" then
    fleet.task = ""
  end
end

function Sim.Tick(world: World.World)
  world.tick += 1
  local tick = world.tick

  for _, id in World.PopDue(world, tick) do
    local action = world.actions[id]
    if action then
      if action.kind == "move" then
        local fleet = world.fleets[action.fleet]
        if Orders.Jumped(world, action) and fleet then
          arrived(world, fleet)
        end
      elseif action.kind == "den" then
        Raiders.Founded(world, action)
      else
        Orders.Launched(world, action)
      end
    end
  end

  if tick % Powers.ROUND_TICKS == 0 then
    Order.Lanes(world)
    Economy.Step(world.econ, Powers.ROUND_TICKS / 360)
    Battle.Round(world)
    Battle.Sieges(world)
  end

  if tick % Powers.PERIOD_TICKS == 0 then
    Order.Step(world)
    Fiscal.Step(world)
    Raiders.Step(world)
    Diplomacy.Step(world, Mind.WantsWar)
    for _, faction in world.factions do
      if faction.alive and not faction.pirate then
        Mind.Budget(world, faction)
      end
    end
  end

  Mind.Think(world)
end

return Sim
