--!strict
-- Characters: the pilots a player has, kept outside any one game (the
-- owner's rulings of 2026-11-17, Character/Characters).

local Characters = require("@lt/Core/Character/Characters")
local Constants = require("@lt/Core/Data/Constants")
local Core = require("@lt/Core/Api")
local Skills = require("@lt/Core/Data/Skills")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Characters")

-- The seconds a level takes, as the game counts them.
local function takes(skill: string, level: number): number
  return math.ceil(Skills.TrainingSeconds(Skills.byId[skill], level) / Constants.TICK) * Constants.TICK
end

suite:Case("a character trains its queue by real time, a level after another, and time with nothing queued goes to nothing", function(t)
  local character = Characters.New("ada", "Ada", "badge:3", 1000)
  t.eq(character.skills.frigates, Skills.Starting().frigates)
  character.training = { { skill = "frigates", level = 2 }, { skill = "frigates", level = 3 } }
  local first, second = takes("frigates", 2), takes("frigates", 3)
  -- (part of the first)
  t.eq(#Characters.CatchUp(character, 1000 + first - 10), 0)
  t.eq({ character.done, #character.training } :: { any }, { first - 10, 2 } :: { any })
  t.eq(Characters.Left(character), 10 + second)
  -- (the first done, and into the second)
  local trained = Characters.CatchUp(character, 1000 + first + 5)
  t.eq(trained, { { skill = "frigates", level = 2 } })
  t.eq({ character.skills.frigates, character.done, #character.training } :: { any }, { 2, 5, 1 } :: { any })
  -- (all of it, and long after)
  Characters.CatchUp(character, 1000 + first + second + 99999)
  t.eq({ character.skills.frigates, character.done, #character.training } :: { any }, { 3, 0, 0 } :: { any })
  -- (a clock that goes back gives nothing, and takes nothing)
  t.eq(#Characters.CatchUp(character, 5), 0)
  t.eq(character.skills.frigates, 3)
end)

suite:Case("a character is written as lines of text and read back the same; anything else is not one", function(t)
  local character = Characters.New("bo-tan", "Bo Tan", "file:bo-tan.png", 42)
  character.skills.mining = 4
  character.training = { { skill = "mining", level = 5 } }
  character.done, character.at = 120, 99
  local back = assert(Characters.Decode(Characters.Encode(character)))
  t.eq(back, character)
  t.eq({ Characters.Decode("name=nobody\n") } :: { any }, { nil, "not a character" } :: { any })
  -- (a skill the game no longer has is let go)
  local old = assert(Characters.Decode(Characters.Encode(character) .. "skill.gone.skill=3\ntrain=gone.skill:4\n"))
  t.eq({ old.skills["gone.skill"], #old.training } :: { any }, { nil, 1 } :: { any })
  t.eq({ Characters.Slug("  Bo Tan the 2nd! "), Characters.Slug("!!!") }, { "bo-tan-the-2nd", "pilot" })
  t.eq({ Characters.NameOk("") } :: { any }, { false, "a character needs a name" } :: { any })
  t.eq({ Characters.NameOk("Bo Tan") } :: { any }, { true } :: { any })
end)

suite:Case("in a game the pilot is their character: its skills and queue, trained by the time given and not by ticks", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local character = Characters.New("ada", "Ada", "badge:1", 0)
  character.skills.mining = 3
  character.training = { { skill = "mining", level = 4 } }
  character.done = 100
  Characters.Into(state, character)
  t.eq({ state.skills.mining, state.character, state.trainingByClock } :: { any }, { 3, "ada", true } :: { any })
  -- (the game's own skills for its starter ship are kept: the most of each)
  t.ok((state.skills.frigates or 0) >= 1)
  -- (ticks go by, and the queue is no further on)
  for _ = 1, 50 do
    Core.Step(game)
  end
  local done = (state.tick - state.trainingStarted) * Constants.TICK
  t.eq(done, 100)
  -- (time given: it is)
  Core.Credit(game, 60)
  t.eq((state.tick - state.trainingStarted) * Constants.TICK, 160)
  Core.Credit(game, takes("mining", 4))
  t.eq({ state.skills.mining, #state.training } :: { any }, { 4, 0 } :: { any })
  -- (and back into the character, as of a time)
  state.training = { { skill = "mining", level = 5 } }
  state.trainingStarted = state.tick - 30
  Characters.From(state, character, 777)
  t.eq({ character.skills.mining, character.done, character.at, #character.training } :: { any }, { 4, 30, 777, 1 } :: { any })
  -- (and one with nothing queued leaves when the game's last training
  -- began as it was: a save loaded plays out as the game did)
  local idle = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  idle.state.trainingStarted = 7
  for _ = 1, 20 do
    Core.Step(idle)
  end
  Characters.Into(idle.state, Characters.New("cy", "Cy", "badge:1", 0))
  t.eq(idle.state.trainingStarted, 7)
  -- A game with no character trains by its ticks, as it always did.
  local plain = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  plain.state.training = { { skill = "mining", level = 1 } }
  plain.state.trainingStarted = 0
  for _ = 1, 5 do
    Core.Step(plain)
  end
  t.eq((plain.state.tick - plain.state.trainingStarted) * Constants.TICK, 5)
end)

suite:Case("a game saved before there were characters gives its pilot to a new one, as of when it was saved", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  state.skills.mining = 2
  state.training = { { skill = "mining", level = 3 } }
  state.trainingStarted = state.tick
  for _ = 1, 40 do
    Core.Step(game)
  end
  local character = Characters.Adopt(state, "pilot", "Pilot", 5000)
  t.eq({ character.skills.mining, character.done, character.at, #character.training } :: { any }, { 2, 40, 5000, 1 } :: { any })
  t.ok(string.match(character.portrait, "^portrait:%d+$") ~= nil)
end)

suite:Case("another of the player's characters is asked into the corporation: a member at a trade, with the skills it has", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  t.eq({ Core.CanJoinAlt(game, "bo", "miner") } :: { any }, { false, "there is no corporation to be a member of: found one first" } :: { any })
  state.wallet = 10000000
  assert(Core.Submit(game, { kind = "FoundCorporation", actor = state.player.ship, what = "Bo and Ada" }))
  Core.Step(game)
  state.character = "ada"
  t.eq({ Core.CanJoinAlt(game, "ada", "miner") } :: { any }, { false, "that is who you are" } :: { any })
  t.eq({ Core.CanJoinAlt(game, "bo", "pirate") } :: { any }, { false, "a member is a miner, a fighter, a hauler or a scout" } :: { any })
  local skills = Skills.Starting()
  skills.mining = 4
  t.ok(Core.JoinAlt(game, "bo", "Bo Tan", "miner", skills))
  local member = state.membership.members[state.membership.memberIds[#state.membership.memberIds]]
  t.eq({ member.name, member.trade, member.alt, (member.skills :: any).mining, member.bears } :: { any }, { "Bo Tan", "miner", "bo", 4, 1 } :: { any })
  t.eq({ Core.CanJoinAlt(game, "bo", "miner") } :: { any }, { false, "they are a member already" } :: { any })
  -- (and their skills kept up to date)
  skills.mining = 5
  Core.AltSkills(game, "bo", skills)
  t.eq((member.skills :: any).mining, 5)
end)

return suite
