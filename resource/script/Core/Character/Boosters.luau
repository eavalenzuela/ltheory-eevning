--!strict
-- Boosters: taking one, and its wearing off (Data/Boosters has what
-- they are).
--
-- A booster is taken out of the hold of the ship the pilot is flying,
-- anywhere, or out of the hangar of the station they are docked at. It
-- is used up, and is at work from then for half an hour
-- (Boosters.SECONDS), wherever the pilot goes and whatever they fly:
-- Assets/Items hands it to the attribute engine with the fit, as it
-- does an implant. One of each kind can be at work at once; another of
-- a kind is refused until the one at work has worn off. A pilot whose
-- capsule is destroyed wakes with none at work (Tactical/Aftermath).

local Constants = require("@lt/Core/Data/Constants")
local Items = require("@lt/Core/Assets/Items")
local Kinds = require("@lt/Core/Data/Boosters")
local State = require("@lt/Core/Kernel/State")
local Vitals = require("@lt/Core/Tactical/Vitals")

local Boosters = {}

export type Event = { [string]: any }

-- Ticks a booster is at work for.
Boosters.TICKS = math.ceil(Kinds.SECONDS / Constants.TICK)

-- The booster of a kind that is at work, if one is.
function Boosters.Working(state: State.State, kind: number): State.Boosted?
  for _, boosted in state.boosters do
    if Kinds.byId[boosted.type].kind == kind then
      return boosted
    end
  end
  return nil
end

-- What the pilot flies is not what it was: a booster has begun, or worn off.
local function refresh(state: State.State)
  local ball = state.balls[state.player.ship]
  if ball then
    Vitals.Refresh(state, ball)
  end
end

function Boosters.Validate(state: State.State, command: State.Command): (boolean, string?)
  local ship = state.ships[command.actor]
  if ship == nil or ship.id ~= state.player.ship then
    return false, "no such ship"
  elseif command.kind ~= "TakeBooster" then
    return false, `unknown command '{command.kind}'`
  end
  local item = state.items[command.item or 0]
  local aboard = item ~= nil and item.holder == ship.id and item.place == "cargo"
  local here = item ~= nil and ship.docked ~= 0 and item.holder == ship.docked and item.place == "hangar"
  if item == nil or not (aboard or here) then
    return false, "that is not in the hold, nor in the hangar here"
  end
  local booster = Kinds.byId[item.type]
  if booster == nil then
    return false, "that is not a booster"
  end
  local working = Boosters.Working(state, booster.kind)
  if working then
    return false, `{Kinds.byId[working.type].name} is still at work: one of a kind at a time`
  end
  return true
end

function Boosters.Apply(state: State.State, command: State.Command, events: { Event })
  local item = state.items[command.item :: number]
  local booster = Kinds.byId[item.type]
  Items.Take(state, item, 1)
  local ends = state.tick + Boosters.TICKS
  table.insert(state.boosters, { type = booster.id, ends = ends })
  refresh(state)
  table.insert(events, { kind = "BoosterTaken", booster = booster.id, ends = ends })
end

-- Once a tick: a booster whose time is up has worn off.
function Boosters.Step(state: State.State, events: { Event })
  local worn = false
  for index = #state.boosters, 1, -1 do
    local boosted = state.boosters[index]
    if state.tick >= boosted.ends then
      table.remove(state.boosters, index)
      worn = true
      table.insert(events, { kind = "BoosterSpent", booster = boosted.type })
    end
  end
  if worn then
    refresh(state)
  end
end

return Boosters
