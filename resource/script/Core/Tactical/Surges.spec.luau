--!strict
-- What pirates massing in a system does to it (Tactical/Surges). Where and when they mass: Strategic/Happenings.spec.

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Constants = require("@lt/Core/Data/Constants")
local Core = require("@lt/Core/Api")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Happenings = require("@lt/Core/Strategic/Happenings")
local Surges = require("@lt/Core/Tactical/Surges")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Surges")

local HOUR = math.floor(3600 / Constants.TICK + 0.5)

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
  t.eq({ Surges.Band(state, thin, "low"), Surges.Fell(state, thin), Surges.On(state, thin) } :: { any }, { "low", 1, false } :: { any })
  local surge = Happenings.Begin(state, Happenings.SURGE, "pirates", thin, 0, HOUR, 1, "", game.events)
  t.ok(Surges.On(state, thin) and not Surges.On(state, 1))
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
  t.eq(surge.kills, 0)
  t.eq(fell(thin), math.floor(Pirates.SCOUT.bounty * Surges.BOUNTY * Aftermath.AWAY))
  t.eq(surge.kills, 1)
  -- When it is over, a head there is worth what it was.
  Happenings.End(state, surge, "over", game.events)
  t.eq(fell(thin), plain)
end)

return suite
