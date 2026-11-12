--!strict
-- Pirates massing in a system (Tactical/Surges).

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Codec = require("@lt/Core/Persist/Codec")
local Constants = require("@lt/Core/Data/Constants")
local Core = require("@lt/Core/Api")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Space = require("@lt/Core/Tactical/Space")
local Surges = require("@lt/Core/Tactical/Surges")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Surges")

local HOUR = math.floor(3600 / Constants.TICK + 0.5)

-- Step until an event of a kind, as many as 'limit' ticks: the event, or nil.
local function stepUntil(game: Core.Game, kind: string, limit: number): Space.Event?
  for _ = 1, limit do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      if event.kind == kind then
        return event
      end
    end
  end
  return nil
end

suite:Case("a surge begins in its time somewhere order is thin and within reach, lasts two hours, and the next comes in its own time", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, systems = 40 })
  local state = game.state
  t.eq(Core.Query.Surge(game), nil)
  t.ok(state.surge.next >= Surges.FIRST[1] * HOUR and state.surge.next <= Surges.FIRST[2] * HOUR + 1,
    `the first surge of a new game in {state.surge.next / HOUR} hours`)
  local began = assert(stepUntil(game, "SurgeBegan", 2 * HOUR), "no surge began")
  local system = began.system :: number
  t.ok(Galaxy.Band(state.galaxy.systems[system].security) ~= "secure", "a surge should be where order is thin")
  t.eq(began.jumps, #Galaxy.Route(state.galaxy, 1, system) - 1)
  t.ok(began.jumps <= Surges.REACH, `a surge {began.jumps} jumps off`)
  t.eq({ state.surge.system, state.surge.ends, state.surge.count }, { system, state.tick + Surges.LASTS * HOUR, 1 })
  t.ok(Surges.On(state, system) and not Surges.On(state, 1))
  local told = assert(Core.Query.Surge(game))
  t.eq({ told.system, told.name, told.jumps, told.kills } :: { any },
    { system, state.galaxy.systems[system].name, began.jumps, 0 } :: { any })
  t.near(told.left, Surges.LASTS * 3600, 2)
  -- It ends when its time is up, and says how many were destroyed there.
  state.surge.kills = 7
  local started = state.tick
  local ended = assert(stepUntil(game, "SurgeEnded", Surges.LASTS * HOUR + 2), "the surge did not end")
  t.eq({ ended.system, ended.kills, state.tick - started }, { system, 7, Surges.LASTS * HOUR })
  t.eq({ state.surge.system, state.surge.kills }, { 0, 0 })
  t.eq(Core.Query.Surge(game), nil)
  local gap = state.surge.next - state.tick
  t.ok(gap >= Surges.EVERY[1] * HOUR and gap <= Surges.EVERY[2] * HOUR, `the next surge in {gap / HOUR} hours`)
  -- And the next is one more.
  assert(stepUntil(game, "SurgeBegan", Surges.EVERY[2] * HOUR + 2), "no second surge began")
  t.eq(state.surge.count, 2)
end)

suite:Case("where a surge is on the space is a kind worse and a pirate's head is worth double, and is counted; elsewhere it is as it was", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, systems = 40 })
  local state = game.state
  local thin = 0
  for id, node in state.galaxy.systems do
    if thin == 0 and Galaxy.Band(node.security) == "low" then
      thin = id
    end
  end
  assert(thin ~= 0, "no system of low security")
  t.eq({ Surges.Band(state, thin, "low"), Surges.Fell(state, thin), state.surge.kills } :: { any }, { "low", 1, 0 } :: { any })
  state.surge.system, state.surge.ends = thin, state.tick + HOUR
  t.eq({ Surges.Band(state, thin, "low"), Surges.Band(state, thin, "lawless"), Surges.Band(state, 1, "secure") }, { "lawless", "lawless", "secure" })
  -- A scout destroyed there, by a pilot who is somewhere else: half of twice what is on its head, where it was half of once.
  local function fell(system: number): number
    local before = state.wallet
    local ball = Pirates.Spawn(state, Pirates.SCOUT, system, 1e9, 0, 0, 0)
    Aftermath.Destroy(state, ball.id, state.player.ship, game.events)
    return state.wallet - before
  end
  local plain = math.floor(Pirates.SCOUT.bounty * Aftermath.AWAY)
  t.eq(fell(1), plain)
  t.eq(state.surge.kills, 0)
  t.eq(fell(thin), math.floor(Pirates.SCOUT.bounty * Surges.BOUNTY * Aftermath.AWAY))
  t.eq(state.surge.kills, 1)
  -- When it is over, a head there is worth what it was.
  state.surge.system = 0
  t.eq(fell(thin), plain)
end)

suite:Case("a game with no pirates has no surges; one that is on is in the save; and a save from before opens with none", function(t)
  local quiet = Core.New({ galaxySeed = 1, historySeed = 1, systems = 40, peaceful = true })
  t.eq(stepUntil(quiet, "SurgeBegan", 5 * HOUR), nil)
  t.eq(quiet.state.surge.system, 0)

  local game = Core.New({ galaxySeed = 1, historySeed = 1, systems = 40 })
  assert(stepUntil(game, "SurgeBegan", 2 * HOUR), "no surge began")
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq({ Core.Hash(loaded), loaded.state.surge.system } :: { any }, { Core.Hash(game), game.state.surge.system } :: { any })
  local file = Codec.Decode(data, length)
  file.saveVersion = 54
  file.state.surge = nil
  local old, oldLength = Codec.Encode(file)
  local opened = Core.Load(old, oldLength)
  t.eq({ opened.state.surge.system, opened.state.surge.next - opened.state.tick }, { 0, 3600 })
end)

return suite
