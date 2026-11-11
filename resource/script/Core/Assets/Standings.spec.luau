--!strict
-- What the factions think of the pilot (Assets/Standings), and what
-- follows from it.

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Batteries = require("@lt/Core/Tactical/Batteries")
local Core = require("@lt/Core/Api")
local Items = require("@lt/Core/Assets/Items")
local Market = require("@lt/Core/Assets/Market")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Space = require("@lt/Core/Tactical/Space")
local Standings = require("@lt/Core/Assets/Standings")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Standings")

local function steps(game: Core.Game, count: number): number
  local volleys = 0
  for _ = 1, count do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      volleys += if event.kind == "BatteryFired" then 1 else 0
    end
  end
  return volleys
end

-- A busy game with the pilot's ship at rest beside the first patrol
-- that comes: the game, the pilot's ball and the patrol's.
local function besidePatrol(t: Test.Context): (Core.Game, State.Ball, State.Ball)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true, traffic = true })
  local state = game.state
  t.ok(Core.Submit(game, { kind = "Undock", actor = state.player.ship }))
  steps(game, 400)
  local patrol: State.Ball? = nil
  for _, id in state.trafficIds do
    if state.traffic[id].kind == "patrol" and patrol == nil then
      patrol = state.balls[id]
    end
  end
  local target = assert(patrol, "no patrol came")
  local me = state.balls[state.player.ship]
  me.x, me.y, me.z = target.x + 1500, target.y, target.z
  Space.AssignGrid(state, me)
  t.ok(Core.Submit(game, { kind = "Stop", actor = me.id }))
  Core.Step(game)
  return game, me, target
end

suite:Case("a faction's stations charge less to a pilot they think well of, and more to one they do not", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local home = state.player.home
  local tax, fee = Market.Tax(state, home), Market.Fee(state, home)
  t.eq({ tax, fee }, { Market.Tax(state), Market.Fee(state) })
  t.eq(Standings.Fees(state, home), 1)
  state.standings.vessari = 5
  t.near(Market.Fee(state, home), fee * 0.85, 1e-9)
  t.near(Market.Tax(state, home), tax * 0.85, 1e-9)
  local _, shown = Core.Query.Fees(game)
  t.near(shown, fee * 0.85, 1e-9)
  state.standings.vessari = 10
  t.near(Standings.Fees(state, home), 0.7, 1e-9)
  state.standings.vessari = -10
  t.near(Standings.Fees(state, home), 1.3, 1e-9)
  -- (and another faction's opinion is nothing to this station)
  state.standings = { talmar = 10 }
  t.eq(Standings.Fees(state, home), 1)
  -- A sale pays what the station's tax leaves.
  state.standings = { vessari = 5 }
  local item = Items.Add(state, "ore.ferrite", 1000, home, "hangar")
  local well = Market.SellValue(state, home, "ore.ferrite", 1000)
  state.standings = {}
  t.ok(well > Market.SellValue(state, home, "ore.ferrite", 1000), "standing made no difference to what a sale pays")
  t.ok(item.quantity == 1000)
end)

suite:Case("standing keeps within -10 and 10, is only a faction's to give, and a grudge fades by the hour", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  Standings.Change(state, "vessari", 25)
  t.eq(Standings.Of(state, "vessari"), 10)
  Standings.Change(state, "vessari", -40)
  t.eq(Standings.Of(state, "vessari"), -10)
  Standings.Change(state, "civilian", -1)
  Standings.Change(state, "", -1)
  Standings.Change(state, "unbound", -1)
  t.eq(Standings.Of(state, "civilian"), 0)
  t.eq(state.standings.civilian, nil)
  t.ok(Standings.Hostile(state, "vessari") and not Standings.Hostile(state, "talmar"))
  -- Who minds: a faction for its own, and whoever holds the system for anybody else's.
  t.eq(Standings.Minds(state, "talmar", 1), "talmar")
  t.eq(Standings.Minds(state, "civilian", 1), "vessari")
  t.eq(Standings.Minds(state, "civilian", 3), "")
  -- A grudge fades; goodwill does not.
  state.standings = { vessari = -0.12, talmar = 2 }
  steps(game, 3600)
  t.near(Standings.Of(state, "vessari"), -0.07, 1e-9)
  steps(game, 7200)
  t.eq(Standings.Of(state, "vessari"), 0)
  t.eq(Standings.Of(state, "talmar"), 2)
end)

suite:Case("firing on a patrol costs standing once a marking, destroying it costs more, and a pirate killed earns a little", function(t)
  local game, me, target = besidePatrol(t)
  local state = game.state
  t.ok(Core.Submit(game, { kind = "LockTarget", actor = me.id, target = target.id }))
  steps(game, 15)
  local guns = Items.Fitted(state, me.id)
  t.ok(Core.Submit(game, { kind = "ActivateModule", actor = me.id, item = guns[1].id, target = target.id }))
  steps(game, 2)
  t.near(Standings.Of(state, "vessari"), Standings.MARKED, 1e-9)
  -- (a second gun in the same marking is not a second offence)
  t.ok(Core.Submit(game, { kind = "ActivateModule", actor = me.id, item = guns[2].id, target = target.id }))
  steps(game, 2)
  t.near(Standings.Of(state, "vessari"), Standings.MARKED, 1e-9)
  Aftermath.Destroy(state, target.id, me.id, game.events)
  t.near(Standings.Of(state, "vessari"), Standings.MARKED + Standings.KILLED, 1e-9)
  local scout = Pirates.Spawn(state, Pirates.SCOUT, me.system, me.x + 4e7, me.y, me.z, 0)
  Aftermath.Destroy(state, scout.id, me.id, game.events)
  t.near(Standings.Of(state, "vessari"), Standings.MARKED + Standings.KILLED + Standings.PIRATE, 1e-9)
end)

suite:Case("a faction that thinks ill enough of a pilot fights them on sight in its space", function(t)
  local game, me, target = besidePatrol(t)
  local state = game.state
  steps(game, 20)
  t.eq(state.pilots[target.id], nil)
  state.standings.vessari = Standings.HOSTILE
  steps(game, 3)
  t.ok(state.pilots[target.id] ~= nil, "a patrol left a pilot its faction is at odds with alone")
  t.eq(state.player.marked, 0)
  local shield = me.vitals.shield
  steps(game, 40)
  t.ok(me.vitals.shield < shield or state.balls[me.id] == nil)
end)

suite:Case("a held system's gates have sentry guns, which fire on a marked pilot and on pirates, and a lawless one's have none", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  t.ok(Core.Submit(game, { kind = "Undock", actor = state.player.ship }))
  Core.Step(game)
  local me = state.balls[state.player.ship]
  local function toGate(system: number)
    for _, object in Space.Describe(state, system).objects do
      if object.kind == "gate" then
        me.system = system
        me.x, me.y, me.z = object.x + 3000, object.y, object.z
        Space.AssignGrid(state, me)
        t.eq(me.grid, object.id)
        return
      end
    end
    error("no gate")
  end
  toGate(1)
  t.ok(Core.Submit(game, { kind = "Stop", actor = me.id }))
  t.eq(steps(game, 20), 0)
  state.player.marked = state.tick + 12
  local secure = steps(game, 12)
  t.ok(secure >= 6, `only {secure} volleys from a secure gate's sentries in twelve seconds`)
  t.eq(steps(game, 20), 0)
  -- A pirate at a guarded gate is fired on too.
  local scout = Pirates.Spawn(state, Pirates.SCOUT, 1, me.x + 3000, me.y, me.z, me.grid)
  state.pilots[scout.id] = nil
  State.RemoveId(state.pilotIds, scout.id)
  t.ok(steps(game, 9) > 0)
  t.ok(scout.vitals.shield < scout.vitals.shieldMax)
  Aftermath.Destroy(state, scout.id, 0, game.events)
  -- Low security has fewer guns; lawless space has none.
  toGate(2)
  state.player.marked = state.tick + 12
  local low = steps(game, 12)
  t.ok(low > 0 and low < secure, `{low} volleys in low security against {secure} in secure space`)
  toGate(3)
  state.player.marked = state.tick + 100
  t.eq(steps(game, 20), 0)
  t.ok(Batteries.RANGE > 3000)
end)

return suite
