--!strict
-- A module put through a mutator (Assets/Mutators), a people's own makes
-- at their markets (Assets/Market), and what a job now and then pays
-- with (Assets/Missions).

local Core = require("@lt/Core/Api")
local Items = require("@lt/Core/Assets/Items")
local Market = require("@lt/Core/Assets/Market")
local Missions = require("@lt/Core/Assets/Missions")
local Modules = require("@lt/Core/Data/Modules")
local State = require("@lt/Core/Kernel/State")
local Stations = require("@lt/Core/Assets/Stations")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Mutators")

local function refused(game: Core.Game, command: State.Command): string?
  command.actor = game.state.player.ship
  local ok, reason = Core.Validate(game, command)
  return if ok then "(accepted)" else reason
end

local function has(state: State.State, holder: number, type: string): State.Item?
  for _, item in Items.In(state, holder, "hangar") do
    if item.type == type then
      return item
    end
  end
  return nil
end

suite:Case("docked, with a mutator in the hangar, a module there comes out another module: once, and it cannot be undone", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local home = state.player.home
  local laser = assert(has(state, home, "laser.pulse.small"), "the starter kit has no laser")
  t.eq(refused(game, { kind = "Mutate", actor = 0, item = laser.id }), "there is no mutator in the hangar here")
  t.eq(refused(game, { kind = "Mutate", actor = 0, item = 424242 }), "that is not in the hangar here")
  local mutators = Items.Add(state, "mutator", 2, home, "hangar")
  t.eq(refused(game, { kind = "Mutate", actor = 0, item = assert(has(state, home, "ammo.emp")).id }), "that is not a module")
  t.eq(refused(game, { kind = "Mutate", actor = 0, item = laser.id }), "(accepted)")
  t.ok(Core.Submit(game, { kind = "Mutate", actor = state.player.ship, item = laser.id }))
  Core.Step(game)
  local told: { [string]: any }? = nil
  for _, event in Core.TakeEvents(game) do
    told = if event.kind == "Mutated" then event else told
  end
  local event = assert(told, "nothing was said of the mutation")
  t.eq({ event.from, mutators.quantity } :: { any }, { "laser.pulse.small", 1 } :: { any })
  t.eq(has(state, home, "laser.pulse.small"), nil, "the plain module should be gone")
  local out = assert(has(state, home, event.to), "what came out is not in the hangar")
  local module = Modules.byId[out.type]
  t.eq({ module.mutated, #assert(module.rolls) } :: { any }, { true, Modules.ROLLS } :: { any })
  t.eq(module.rolls, event.rolls)
  for _, roll in assert(module.rolls) do
    t.ok(roll >= Modules.WORST and roll <= Modules.BEST and roll % 1 == 0, `a roll of {roll}`)
  end
  -- It will not go through again, though there is a mutator left.
  t.eq(refused(game, { kind = "Mutate", actor = 0, item = out.id }), "it has been through a mutator already")
  -- It is fitted as any module is (the skill for a laser given), and it is its own figures that count.
  state.skills.lasers = 1
  t.ok(Core.Submit(game, { kind = "Unfit", actor = state.player.ship, item = Items.Fitted(state, state.player.ship)[1].id }))
  Core.Step(game)
  local before = Core.Query.FittingUse(game, state.player.ship)
  t.ok(Core.Submit(game, { kind = "Fit", actor = state.player.ship, item = out.id }))
  Core.Step(game)
  local after = Core.Query.FittingUse(game, state.player.ship)
  t.eq(after - before, module.cpu)
  -- Out in space there is no doing it.
  t.ok(Core.Submit(game, { kind = "Undock", actor = state.player.ship }))
  Core.Step(game)
  t.eq(refused(game, { kind = "Mutate", actor = 0, item = out.id }), "not docked")
  -- And the same seed, the same second and the same module give the same module.
  local again = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  Items.Add(again.state, "mutator", 1, again.state.player.home, "hangar")
  t.ok(Core.Submit(again, { kind = "Mutate", actor = again.state.player.ship,
    item = assert(has(again.state, again.state.player.home, "laser.pulse.small")).id }))
  Core.Step(again)
  t.ok(has(again.state, again.state.player.home, event.to) ~= nil, "the same game should give the same mutation")
end)

suite:Case("a people's stations have their own makes, and sell them to anybody", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local home = state.player.home
  local people = Stations.People(state, home)
  local theirs, others = "", ""
  for _, module in Modules.list do
    if module.meta == 3 and module.lineage == people and theirs == "" and module.basePrice < 200000 then
      theirs = module.id
    elseif module.meta == 3 and module.lineage ~= people and others == "" then
      others = module.id
    end
  end
  t.ok(theirs ~= "" and others ~= "", `no make of {people}'s to buy`)
  state.wallet = 10000000
  -- Theirs are there to be had, a few of each; somebody else's are not.
  t.ok(Market.BuyCost(state, home, theirs, Market.OWN_STOCK) ~= nil, `{theirs} is not in stock at one of its people's stations`)
  t.eq(Market.BuyCost(state, home, theirs, Market.OWN_STOCK + 1), nil)
  t.eq(Market.BuyCost(state, home, others, 1), nil, `{others} is in stock at a station of {people}'s`)
  -- (to anybody, whatever they think of the pilot: a market is not
  -- gated by standing, only the loyalty stores are)
  state.standings[people] = -4
  t.eq(refused(game, { kind = "BuyNow", actor = 0, type = theirs, quantity = 1 }), "(accepted)")
  t.ok(Core.Submit(game, { kind = "BuyNow", actor = state.player.ship, type = theirs, quantity = 1 }))
  Core.Step(game)
  t.ok(has(state, home, theirs) ~= nil, "what was bought is not in the hangar")
end)

suite:Case("now and then a job pays with one of the people's own makes in place of credits", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local home = state.player.home
  local people = Stations.People(state, home)
  local jobs, prizes = 0, 0
  for day = 0, 59 do
    state.tick = day * 86400 + 60
    for _, offer in Missions.Offers(state, home) do
      jobs += 1
      if offer.prize then
        prizes += 1
        local module = assert(Modules.byId[offer.prize], offer.prize)
        t.eq({ module.meta, module.lineage, offer.reward } :: { any }, { 3, people, 0 } :: { any })
      else
        t.ok(offer.reward > 0)
      end
    end
  end
  t.ok(prizes > 0, `none of {jobs} jobs paid with a module`)
  t.ok(prizes <= jobs * Missions.PRIZE * 1.6, `{prizes} of {jobs} jobs paid with a module`)
  -- (the same day's jobs are the same jobs, asked twice)
  local first, second = Missions.Offers(state, home), Missions.Offers(state, home)
  for index, offer in first do
    t.eq(second[index].prize, offer.prize)
  end
end)

return suite
