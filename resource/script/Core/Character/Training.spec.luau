--!strict
-- Skills: learning, the training queue, and what a trained skill changes.

local Core = require("@lt/Core/Api")
local Items = require("@lt/Core/Assets/Items")
local Market = require("@lt/Core/Assets/Market")
local Skills = require("@lt/Core/Data/Skills")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")
local Types = require("@lt/Core/Data/Types")

local suite = Test.Suite("Training")

local function newGame(): (Core.Game, number)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  return game, game.state.player.home
end

local function order(t: Test.Context, game: Core.Game, command: State.Command)
  command.actor = game.state.player.ship
  local ok, reason = Core.Submit(game, command)
  t.ok(ok, `{command.kind} was refused: {tostring(reason)}`)
  Core.Step(game)
end

local function refused(game: Core.Game, command: State.Command): string?
  command.actor = game.state.player.ship
  local ok, reason = Core.Validate(game, command)
  return if ok then "(accepted)" else reason
end

local function stack(game: Core.Game, type: string): State.Item
  for _, item in Items.In(game.state, game.state.player.home, "hangar") do
    if item.type == type then
      return item
    end
  end
  error(`no {type} in the hangar`, 2)
end

-- Step until an event of a kind; the ticks it took.
local function stepUntil(game: Core.Game, kind: string, limit: number): ({ [string]: any }, number)
  for n = 1, limit do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      if event.kind == kind then
        return event, n
      end
    end
  end
  error(`no {kind} within {limit} ticks`, 2)
end

suite:Case("the skill data is sound", function(t)
  for _, skill in Skills.list do
    t.ok(skill.rank >= 1 and skill.start >= -1 and skill.start <= Skills.MAX_LEVEL, skill.id)
    for _, need in skill.requires do
      t.ok(Skills.byId[need.skill] ~= nil, `{skill.id} requires an unknown skill '{need.skill}'`)
      t.ok(skill.start < 0, `{skill.id} has a prerequisite, so it has to come from a book`)
    end
    -- a book for every skill a pilot does not start with, and only those
    t.eq(Types.Get(Skills.Book(skill.id)) ~= nil, skill.start < 0, skill.id)
  end
  for _, id in Types.Ids() do
    for _, need in Skills.Needs(id) do
      t.ok(Skills.byId[need.skill] ~= nil, `{id} needs an unknown skill '{need.skill}'`)
    end
  end
  -- a minute for the first level of a rank 1 skill; eight hours for the
  -- fifth level of a rank 2; a day and more for the fifth of battleships
  t.eq(Skills.TrainingSeconds(Skills.byId.lasers, 1), 60)
  t.eq(Skills.TrainingSeconds(Skills.byId.frigates, 5), 28800)
  t.eq(Skills.TrainingSeconds(Skills.byId.battleships, 5), 115200)
end)

suite:Case("a new pilot cannot fit a laser until Laser Turrets is trained, which takes a minute", function(t)
  local game = newGame()
  local state = game.state
  t.eq({ state.skills.frigates, state.skills.lasers, state.skills["rapid.firing"] } :: { any }, { 1, 0, nil } :: { any })
  local cannon = Items.Fitted(state, state.player.ship)[1]
  order(t, game, { kind = "Unfit", actor = 0, item = cannon.id })
  local laser = stack(game, "laser.pulse.small")
  t.eq(refused(game, { kind = "Fit", actor = 0, item = laser.id }), "needs Laser Turrets 1")
  t.eq(Core.Query.Untrained(game, "laser.pulse.small"), "needs Laser Turrets 1")
  t.eq(Core.Query.Untrained(game, "autocannon.small"), nil)

  order(t, game, { kind = "TrainSkill", actor = 0, type = "lasers" })
  local queue = Core.Query.Training(game)
  t.eq({ #queue, queue[1].skill, queue[1].level, queue[1].seconds, queue[1].left } :: { any },
    { 1, "lasers", 1, 60, 60 } :: { any })
  Core.TakeEvents(game)
  local trained, ticks = stepUntil(game, "SkillTrained", 100)
  t.eq({ trained.skill, trained.level, ticks } :: { any }, { "lasers", 1, 60 } :: { any })
  t.eq(state.skills.lasers, 1)
  t.eq(#Core.Query.Training(game), 0)
  order(t, game, { kind = "Fit", actor = 0, item = laser.id })
  t.eq(#Items.Fitted(state, state.player.ship), 2)
end)

suite:Case("levels queue, each takes its base time times the skill's rank, and one starts where the last ended", function(t)
  local game = newGame()
  local state = game.state
  order(t, game, { kind = "TrainSkill", actor = 0, type = "lasers" })      -- 60 s
  order(t, game, { kind = "TrainSkill", actor = 0, type = "frigates" })    -- level 2 of a rank 2: 480 s
  order(t, game, { kind = "TrainSkill", actor = 0, type = "lasers" })      -- level 2: 240 s
  local queue = Core.Query.Training(game)
  t.eq({ queue[1].level, queue[2].level, queue[3].level }, { 1, 2, 2 })
  -- two ticks have passed since the first was queued
  t.eq({ queue[1].left, queue[2].left, queue[3].left }, { 58, 538, 778 })
  local started = state.tick - 2
  Core.TakeEvents(game)
  local finished: { { any } } = {}
  for _ = 1, 1000 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      if event.kind == "SkillTrained" then
        table.insert(finished, { event.skill, event.level, state.tick - started })
      end
    end
  end
  t.eq(finished, { { "lasers", 1, 60 }, { "frigates", 2, 540 }, { "lasers", 2, 780 } } :: { { any } })
  local known: { [string]: number } = {}
  for _, info in Core.Query.Skills(game) do
    known[info.skill.id] = info.level
  end
  t.eq({ known.lasers, known.frigates, known.missiles, known["rapid.firing"] }, { 2, 2, 0, -1 })
end)

suite:Case("time the pilot was away goes to their training, and to nothing else; what is left when the queue runs out is lost", function(t)
  local game = newGame()
  local state = game.state
  -- With nothing in training, time away is nothing.
  t.eq(Core.Away(game, 3600), 0)
  order(t, game, { kind = "TrainSkill", actor = 0, type = "lasers" })      -- 60 s
  order(t, game, { kind = "TrainSkill", actor = 0, type = "frigates" })    -- 480 s
  order(t, game, { kind = "TrainSkill", actor = 0, type = "lasers" })      -- 240 s
  local tick, wallet = state.tick, state.wallet
  Core.TakeEvents(game)
  -- A hundred seconds away: the first level is trained, and the second is forty-two seconds in (two had gone by).
  t.eq(Core.Away(game, 100), 1)
  t.eq({ state.skills.lasers, #state.training, state.tick, state.wallet }, { 1, 2, tick, wallet })
  local queue = Core.Query.Training(game)
  t.eq({ queue[1].skill, queue[1].left, queue[2].left } :: { any }, { "frigates", 480 - 42, 480 - 42 + 240 } :: { any })
  local trained, credited = 0, false
  for _, event in Core.TakeEvents(game) do
    trained += if event.kind == "SkillTrained" then 1 else 0
    credited = credited or (event.kind == "TrainingCredited" and event.seconds == 100 and event.trained == 1 and event.queued == 2)
  end
  t.eq({ trained, credited } :: { any }, { 1, true } :: { any })
  -- No time, or less than none: nothing.
  t.eq({ Core.Away(game, 0), Core.Away(game, -50) }, { 0, 0 })
  t.eq(Core.Query.Training(game)[1].left, 480 - 42)
  -- A day away: everything queued is trained, and the rest of the day is gone.
  t.eq(Core.Away(game, 86400), 2)
  t.eq({ state.skills.frigates, state.skills.lasers, #state.training, state.tick }, { 2, 2, 0, tick })
  -- What is queued after that starts from now, not from then.
  order(t, game, { kind = "TrainSkill", actor = 0, type = "missiles" })
  t.eq(Core.Query.Training(game)[1].left, Skills.TrainingSeconds(Skills.byId.missiles, 1))
  -- It is in the save as anything else is.
  local data, length = Core.Save(game)
  t.eq(Core.Hash(Core.Load(data, length)), Core.Hash(game))
end)

suite:Case("a skill a pilot does not start with is learned from its book, once its own needs are met", function(t)
  local game, home = newGame()
  local state = game.state
  t.eq(refused(game, { kind = "TrainSkill", actor = 0, type = "rapid.firing" }), "learn it from its book first")
  t.eq(refused(game, { kind = "TrainSkill", actor = 0, type = "juggling" }), "no such skill")
  local books = Items.Add(state, "book.rapid.firing", 2, home, "hangar")
  t.eq(refused(game, { kind = "LearnSkill", actor = 0, item = books.id }), "needs Projectile Turrets 2")
  t.eq(refused(game, { kind = "LearnSkill", actor = 0, item = stack(game, "ammo.emp").id }), "that is not a skill book")
  state.skills.projectiles = 2
  order(t, game, { kind = "LearnSkill", actor = 0, item = books.id })
  t.eq({ state.skills["rapid.firing"], books.quantity }, { 0, 1 }, "known at level 0, and the book is used up")
  t.eq(refused(game, { kind = "LearnSkill", actor = 0, item = books.id }), "already known")
  order(t, game, { kind = "TrainSkill", actor = 0, type = "rapid.firing" })
  t.eq(Core.Query.Training(game)[1].seconds, 120)
end)

suite:Case("the queue holds ten levels, stops at level five, and cancelling drops a skill's later levels too", function(t)
  local game = newGame()
  local state = game.state
  for _ = 1, 5 do
    order(t, game, { kind = "TrainSkill", actor = 0, type = "lasers" })
  end
  t.eq(refused(game, { kind = "TrainSkill", actor = 0, type = "lasers" }), "nothing more to train")
  for _ = 1, 5 do
    order(t, game, { kind = "TrainSkill", actor = 0, type = "missiles" })
  end
  t.eq(refused(game, { kind = "TrainSkill", actor = 0, type = "navigation" }), "the training queue is full")
  t.eq(refused(game, { kind = "CancelTraining", actor = 0, quantity = 11 }), "no such entry in the queue")

  -- Cancel Missile Launchers 3: levels 4 and 5 go with it.
  order(t, game, { kind = "CancelTraining", actor = 0, quantity = 8 })
  local queue = Core.Query.Training(game)
  t.eq(#queue, 7)
  t.eq({ queue[6].skill, queue[6].level, queue[7].skill, queue[7].level } :: { any },
    { "missiles", 1, "missiles", 2 } :: { any })
  -- Cancelling the level in training loses the time spent on it: what
  -- is next starts from nothing.
  -- (ten ticks have passed since the first level was queued)
  t.eq(queue[1].left, 60 - 10)
  order(t, game, { kind = "CancelTraining", actor = 0, quantity = 1 })
  queue = Core.Query.Training(game)
  t.eq({ #queue, queue[1].skill, queue[1].level, queue[1].left } :: { any }, { 2, "missiles", 1, 60 } :: { any })
  t.eq(state.skills.lasers, 0)
end)

suite:Case("a skill with a bonus makes the ship better the moment it is trained, in space too", function(t)
  local game = newGame()
  local state = game.state
  local ship = state.player.ship
  local before = Items.ShipStats(state, ship)
  order(t, game, { kind = "Undock", actor = 0 })
  local ball = assert(Core.Query.Ball(game, ship))
  t.eq(ball.maxVelocity, before.maxVelocity)
  order(t, game, { kind = "TrainSkill", actor = 0, type = "navigation" })
  for _ = 1, 59 do
    Core.Step(game)
  end
  t.eq(ball.maxVelocity, before.maxVelocity)
  Core.Step(game)
  t.near(ball.maxVelocity, before.maxVelocity * 1.05, 1e-9)
  -- 5% more powergrid and CPU a level, which lets more be fitted
  state.skills.engineering, state.skills.electronics = 4, 2
  local after = Items.ShipStats(state, ship)
  t.near(after.powergrid, before.powergrid * 1.2, 1e-9)
  t.near(after.cpu, before.cpu * 1.1, 1e-9)
  -- and a pirate in the same hull gets none of it
  local Attributes = require("@lt/Core/Attributes")
  local Ships = require("@lt/Core/Data/Ships")
  t.eq(Attributes.Ship(Ships.byId[state.ships[ship].type], Items.Fit(state, ship, nil), nil).powergrid, before.powergrid)
end)

suite:Case("weapon skills change the weapons of their family only", function(t)
  local Attributes = require("@lt/Core/Attributes")
  local fitted = { { type = "autocannon.small", running = false }, { type = "laser.pulse.small", running = false } }
  local plain = Attributes.Weapon(fitted, "autocannon.small", {})
  local quick = Attributes.Weapon(fitted, "autocannon.small", { ["rapid.firing"] = 5, sharpshooter = 5 })
  t.near(quick.duration, plain.duration * 0.8, 1e-9)
  t.eq(quick.optimal, plain.optimal)
  local laser = Attributes.Weapon(fitted, "laser.pulse.small", {})
  local far = Attributes.Weapon(fitted, "laser.pulse.small", { ["rapid.firing"] = 5, sharpshooter = 5 })
  t.near(far.optimal, laser.optimal * 1.25, 1e-9)
  t.eq(far.duration, laser.duration)
end)

suite:Case("trade skills lower the tax and the broker's fee by a tenth a level", function(t)
  local game = newGame()
  local state = game.state
  t.eq({ Market.Tax(state), Market.Fee(state) }, { 0.02, 0.03 })
  state.skills.accounting = 5
  state.skills["broker.relations"] = 2
  t.near(Market.Tax(state), 0.01, 1e-12)
  t.near(Market.Fee(state), 0.024, 1e-12)
end)

suite:Case("training goes on through a save and load, to the same state", function(t)
  local game = newGame()
  order(t, game, { kind = "TrainSkill", actor = 0, type = "lasers" })
  order(t, game, { kind = "TrainSkill", actor = 0, type = "lasers" })
  for _ = 1, 30 do
    Core.Step(game)
  end
  local copy = Core.Load(Core.Save(game))
  t.eq(Core.Hash(copy), Core.Hash(game))
  for _ = 1, 400 do
    Core.Step(game)
    Core.Step(copy)
  end
  t.eq(copy.state.skills.lasers, 2)
  t.eq(Core.Hash(copy), Core.Hash(game))
end)

return suite
