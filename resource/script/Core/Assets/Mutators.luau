--!strict
-- Mutators: a module put through one comes out changed (the owner's,
-- 2026-11-15: "mods which have been mutated, i.e. had their stats
-- somewhat randomized, by use of a mutator item", and how far: "A
-- gamble, wide").
--
-- A mutator is a thing found, not bought: in what a named officer of
-- the pirates leaves, in a derelict now and then, and with whoever
-- comes out of the deep (Tactical/Sightings, Tactical/Invasions,
-- Tactical/Keeps). Docked, with one in the hangar, a module in the same
-- hangar is put through it. The mutator is used up, and the module
-- comes back another module (Data/Modules): each of its four figures
-- (what it gives, how easy it is to fit, how little it draws, how far it
-- reaches) moved on its own, anywhere from a quarter worse to three
-- tenths better. It cannot be undone, and a module that has been
-- through one will not go through another.
--
-- What it comes out as follows from the game's seed, the tick and the
-- module: asking twice in the same second gives the same answer.

local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Rng = require("@lt/Core/Kernel/Rng")
local State = require("@lt/Core/Kernel/State")

local Mutators = {}

export type Event = { [string]: any }

Mutators.ITEM = "mutator"
Mutators.COMMANDS = { Mutate = true }

-- A mutator in a station's hangar, if there is one.
local function mutator(state: State.State, station: number): State.Item?
  for _, item in Items.In(state, station, "hangar") do
    if item.type == Mutators.ITEM then
      return item
    end
  end
  return nil
end

-- Whether a module could be put through a mutator at all.
function Mutators.Takes(type: string): boolean
  local module = Modules.byId[type]
  return module ~= nil and not module.mutated and not module.internal
end

function Mutators.Validate(state: State.State, command: State.Command): (boolean, string?)
  local ship = state.ships[command.actor]
  if ship == nil then
    return false, "no such ship"
  elseif State.At(ship) == 0 then
    return false, "not docked"
  end
  local item = state.items[command.item or 0]
  if item == nil or item.holder ~= State.At(ship) or item.place ~= "hangar" then
    return false, "that is not in the hangar here"
  end
  local module = Modules.byId[item.type]
  if module == nil or module.internal then
    return false, "that is not a module"
  elseif module.mutated then
    return false, "it has been through a mutator already"
  elseif mutator(state, State.At(ship)) == nil then
    return false, "there is no mutator in the hangar here"
  end
  return true
end

function Mutators.Apply(state: State.State, command: State.Command, events: { Event })
  local ship = state.ships[command.actor]
  local station = State.At(ship)
  local item = state.items[command.item :: number]
  local used = mutator(state, station) :: State.Item
  local rng = Rng.For(state.historySeed, state.tick, item.id, 163)
  local rolls: { number } = {}
  for index = 1, Modules.ROLLS do
    rolls[index] = Modules.WORST + Rng.Int(rng, Modules.BEST - Modules.WORST + 1)
  end
  local was = item.type
  local now = Modules.Mutated(was, rolls) :: string
  Items.Take(state, used, 1)
  Items.Take(state, item, 1)
  Items.Add(state, now, 1, station, "hangar")
  table.insert(events, { kind = "Mutated", from = was, to = now, rolls = rolls })
end

return Mutators
