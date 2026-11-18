--!strict
-- Learning skills and training them (Data/Skills says what they are).
--
-- A pilot knows a skill once it has been learned from its book, and then
-- trains it a level at a time. Levels wait in a queue; the first is in
-- training, and takes its time whatever the pilot is doing. Taking the
-- level in training out of the queue loses the time spent on it.
--
-- Training goes on while the game is not being played: when a save is
-- opened, the time since it was made is given to the queue
-- (Training.Credit, by way of Core.Away: the view says how long it
-- was). Nothing else in the game moves in that time. What is left of it
-- when the queue runs out is lost.
--
-- And a training injector (Data/Injectors) is banked time: used, from
-- the hangar here or the hold, it gives the queue its seconds at once, by
-- the same way. (Not while the queue has less than that left in it:
-- what is left over would be lost.)

local Constants = require("@lt/Core/Data/Constants")
local Injectors = require("@lt/Core/Data/Injectors")
local Items = require("@lt/Core/Assets/Items")
local Skills = require("@lt/Core/Data/Skills")
local State = require("@lt/Core/Kernel/State")
local Vitals = require("@lt/Core/Tactical/Vitals")

local Training = {}

export type Event = { [string]: any }

local BOOK = "book."

-- The skill a book teaches, if the item type is a skill book.
function Training.BookSkill(type: string): Skills.Skill?
  if string.sub(type, 1, #BOOK) ~= BOOK then
    return nil
  end
  return Skills.byId[string.sub(type, #BOOK + 1)]
end

-- The level a skill will be at once everything queued for it is trained;
-- -1 if the pilot does not know it.
function Training.QueuedLevel(state: State.State, skill: string): number
  local level = state.skills[skill] or -1
  for _, entry in state.training do
    if entry.skill == skill then
      level = math.max(level, entry.level)
    end
  end
  return level
end

local function ticksFor(entry: { skill: string, level: number }): number
  return math.ceil(Skills.TrainingSeconds(Skills.byId[entry.skill], entry.level) / Constants.TICK)
end

export type Queued = {
  skill: string,
  level: number,
  seconds: number,    -- the whole of this level
  left: number,       -- until it is trained, counting what is queued before it
}

-- The queue with its times, first in training first.
function Training.Queue(state: State.State): { Queued }
  local queue: { Queued } = {}
  local done = (state.tick - state.trainingStarted) * Constants.TICK
  local before = 0
  for _, entry in state.training do
    local seconds = ticksFor(entry) * Constants.TICK
    before += seconds
    table.insert(queue, { skill = entry.skill, level = entry.level, seconds = seconds, left = before - done })
  end
  return queue
end

function Training.Validate(state: State.State, command: State.Command): (boolean, string?)
  local ship = state.ships[command.actor]
  if ship == nil or ship.owner ~= "player" then
    return false, "no such ship"
  end
  local kind = command.kind

  if kind == "LearnSkill" then
    -- (a book is read where it is: in the hangar of the station the
    -- pilot is docked at, or in the hold of the ship they fly, docked or
    -- not. The owner, 2026-11-15, was given one and found no way to use it.)
    local item = state.items[command.item or 0]
    local inHangar = item ~= nil and ship.docked ~= 0 and item.holder == ship.docked and item.place == "hangar"
    local inHold = item ~= nil and item.holder == ship.id and item.place == "cargo"
    if item == nil or not (inHangar or inHold) then
      return false, "that is not in the hangar here, nor in the hold"
    end
    local skill = Training.BookSkill(item.type)
    if skill == nil then
      return false, "that is not a skill book"
    elseif state.skills[skill.id] ~= nil then
      return false, "already known"
    end
    local missing = Skills.Missing(skill.requires, state.skills)
    if missing then
      return false, Skills.Describe(missing)
    end
    return true

  elseif kind == "TrainSkill" then
    local skill = Skills.byId[command.type or ""]
    if skill == nil then
      return false, "no such skill"
    elseif state.skills[skill.id] == nil then
      return false, "learn it from its book first"
    elseif Training.QueuedLevel(state, skill.id) >= Skills.MAX_LEVEL then
      return false, "nothing more to train"
    elseif #state.training >= Skills.QUEUE_LENGTH then
      return false, "the training queue is full"
    end
    return true

  elseif kind == "CancelTraining" then
    if state.training[command.quantity or 0] == nil then
      return false, "no such entry in the queue"
    end
    return true

  elseif kind == "Inject" then
    local item = state.items[command.item or 0]
    local inHangar = item ~= nil and ship.docked ~= 0 and item.holder == ship.docked and item.place == "hangar"
    local inHold = item ~= nil and item.holder == ship.id and item.place == "cargo"
    if item == nil or not (inHangar or inHold) then
      return false, "that is not in the hangar here, nor in the hold"
    end
    local injector = Injectors.byId[item.type]
    if injector == nil then
      return false, "that is not a training injector"
    elseif #state.training == 0 then
      return false, "nothing is in training: queue a skill first"
    end
    local queue = Training.Queue(state)
    local left = queue[#queue].left
    if left < injector.seconds then
      return false, "the queue has less than that left to train: queue more first"
    end
    return true
  end
  return false, `unknown command '{kind}'`
end

function Training.Apply(state: State.State, command: State.Command, events: { Event })
  local kind = command.kind
  if kind == "LearnSkill" then
    local item = state.items[command.item :: number]
    local skill = Training.BookSkill(item.type) :: Skills.Skill
    Items.Take(state, item, 1)
    state.skills[skill.id] = 0
    table.insert(events, { kind = "SkillLearned", skill = skill.id })

  elseif kind == "TrainSkill" then
    local skill = command.type :: string
    if #state.training == 0 then
      state.trainingStarted = state.tick
    end
    local level = Training.QueuedLevel(state, skill) + 1
    table.insert(state.training, { skill = skill, level = level })
    table.insert(events, { kind = "TrainingQueued", skill = skill, level = level })

  elseif kind == "CancelTraining" then
    local index = command.quantity :: number
    local skill = state.training[index].skill
    -- The later levels of the same skill cannot be trained without it.
    for at = #state.training, index, -1 do
      if state.training[at].skill == skill then
        table.remove(state.training, at)
      end
    end
    if index == 1 then
      state.trainingStarted = state.tick
    end
    table.insert(events, { kind = "TrainingCancelled", skill = skill })

  elseif kind == "Inject" then
    local item = state.items[command.item :: number]
    local injector = Injectors.byId[item.type]
    Items.Take(state, item, 1)
    local trained = Training.Credit(state, injector.seconds, events)
    table.insert(events, { kind = "Injected", type = injector.id, seconds = injector.seconds, trained = trained })
  end
end

-- Each tick: the level in training is finished if its time is up, and the
-- next begins where it ended.
-- Give the queue so many seconds that nothing else has had: the levels
-- they finish are trained. Returns how many were.
function Training.Credit(state: State.State, seconds: number, events: { Event }): number
  local queued = #state.training
  if queued == 0 or seconds <= 0 then
    return 0
  end
  state.trainingStarted -= math.floor(seconds / Constants.TICK)
  Training.Step(state, events)
  -- (with nothing left in training there is nothing for the rest of it to go to)
  if #state.training == 0 then
    state.trainingStarted = state.tick
  end
  return queued - #state.training
end

-- Once a tick. (A character's queue is trained by the time the player
-- gives it, not by ticks: the time it has had stands still with the
-- game's, and only Training.Credit moves it on.)
function Training.Tick(state: State.State, events: { Event })
  if state.trainingByClock and #state.training > 0 then
    state.trainingStarted += 1
  end
  Training.Step(state, events)
end

function Training.Step(state: State.State, events: { Event })
  while true do
    local first = state.training[1]
    if first == nil then
      return
    end
    local ticks = ticksFor(first)
    if state.tick - state.trainingStarted < ticks then
      return
    end
    state.skills[first.skill] = first.level
    table.remove(state.training, 1)
    state.trainingStarted += ticks
    table.insert(events, { kind = "SkillTrained", skill = first.skill, level = first.level })
    -- A skill that makes the ship better does so at once, in space too.
    local ball = state.balls[state.player.ship]
    if ball then
      Vitals.Refresh(state, ball)
    end
  end
end

return Training
