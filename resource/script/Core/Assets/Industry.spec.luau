--!strict
-- Building from blueprints, through the Core's front door.

local Blueprints = require("@lt/Core/Data/Blueprints")
local Core = require("@lt/Core/Api")
local Industry = require("@lt/Core/Assets/Industry")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")
local Types = require("@lt/Core/Data/Types")

local suite = Test.Suite("Industry")

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

local function hangar(game: Core.Game, type: string): number
  return Industry.Have(game.state, game.state.player.home, type)
end

local function stack(game: Core.Game, type: string): State.Item
  for _, item in Items.In(game.state, game.state.player.home, "hangar") do
    if item.type == type then
      return item
    end
  end
  error(`no {type} in the hangar`, 2)
end

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

suite:Case("everything fitted, fired, flown or built into it has a blueprint, and its materials cost about 60% of it", function(t)
  local count = 0
  for _, id in Types.Ids() do
    local info = Types.Info(id)
    if info.category == "module" or info.category == "charge" or info.category == "ship" or info.category == "component" then
      local blueprint = assert(Blueprints.byProduct[id], `no blueprint for {id}`)
      count += 1
      t.eq(Types.Info(blueprint.id).category, "blueprint")
      local cost = 0
      for _, m in blueprint.materials do
        t.ok(m.quantity >= 1 and m.quantity % 1 == 0)
        -- (a mineral or a component, at its own price)
        cost += m.quantity * Types.Info(m.type).basePrice
      end
      local share = cost / (info.basePrice * blueprint.perRun)
      -- (whole components make a cheap thing's bill a little lumpy)
      t.ok(share > 0.5 and share < 0.7, `{id}: materials are {share} of the product's price`)
      t.eq(blueprint.basePrice, info.basePrice * blueprint.perRun * 10)
    end
  end
  t.eq(count, #Blueprints.list)
  t.eq(Blueprints.byProduct["ammo.emp"].perRun, 100)
  t.eq(Blueprints.byProduct["crystal.multifrequency"].perRun, 1)
  t.eq(Blueprints.byProduct["capsule"], nil)
end)

suite:Case("a job takes the minerals, a fee and the blueprint, and delivers when its time is up", function(t)
  local game, home = newGame()
  local state = game.state
  local blueprint = Blueprints.byId["blueprint.ammo.emp"]
  -- a run of a hundred rounds: 210 iron and 45 silicon
  t.eq(blueprint.materials, { { type = "mineral.iron", quantity = 210 }, { type = "mineral.silicon", quantity = 45 } })
  local item = stack(game, "blueprint.ammo.emp")
  t.eq(refused(game, { kind = "StartJob", actor = 0, item = item.id, quantity = 5 }), "needs 1050 more Iron")
  Items.Add(state, "mineral.iron", 1100, home, "hangar")
  t.eq(refused(game, { kind = "StartJob", actor = 0, item = item.id, quantity = 5 }), "needs 225 more Silicon")
  Items.Add(state, "mineral.silicon", 225, home, "hangar")

  local plan = assert(Core.Query.JobPlan(game, home, "blueprint.ammo.emp", 5))
  -- 60 s a run, 4% quicker for Industry 1; the fee is 2% of 500 rounds
  t.eq({ plan.quantity, plan.seconds, plan.fee }, { 500, 288, 200 })
  t.eq(plan.materials, { { type = "mineral.iron", need = 1050, have = 1100 }, { type = "mineral.silicon", need = 225, have = 225 } })

  local rounds = hangar(game, "ammo.emp")
  order(t, game, { kind = "StartJob", actor = 0, item = item.id, quantity = 5 })
  t.eq({ hangar(game, "mineral.iron"), hangar(game, "mineral.silicon"), hangar(game, "blueprint.ammo.emp") }, { 50, 0, 0 })
  t.eq(state.wallet, 5000 - 200)
  t.eq(state.journal[#state.journal].reason, "manufacturing fee")
  local jobs = Core.Query.Jobs(game, home)
  t.eq({ #jobs, jobs[1].product, jobs[1].quantity, jobs[1].ends - jobs[1].started } :: { any },
    { 1, "ammo.emp", 500, 288 } :: { any })

  Core.TakeEvents(game)
  local done, ticks = stepUntil(game, "JobDone", 400)
  t.eq({ done.product, done.quantity, done.station, ticks } :: { any }, { "ammo.emp", 500, home, 288 } :: { any })
  t.eq(hangar(game, "ammo.emp"), rounds + 500)
  t.eq(hangar(game, "blueprint.ammo.emp"), 1, "the blueprint comes back")
  t.eq(#Core.Query.Jobs(game), 0)
end)

suite:Case("a job that cannot be run is refused, with the reason", function(t)
  local game, home = newGame()
  local state = game.state
  local item = stack(game, "blueprint.ammo.emp")
  Items.Add(state, "mineral.iron", 100000, home, "hangar")
  Items.Add(state, "mineral.silicon", 100000, home, "hangar")
  t.eq(refused(game, { kind = "StartJob", actor = 0, item = stack(game, "ammo.emp").id }), "that is not a blueprint")
  t.eq(refused(game, { kind = "StartJob", actor = 0, item = item.id, quantity = 0 }), "a job is for 1 to 100 runs")
  t.eq(refused(game, { kind = "StartJob", actor = 0, item = item.id, quantity = 2.5 }), "a job is for 1 to 100 runs")
  t.eq(refused(game, { kind = "StartJob", actor = 0, item = item.id, quantity = 101 }), "a job is for 1 to 100 runs")
  t.eq(refused(game, { kind = "StartJob", actor = 0, item = 4242 }), "no such item")
  state.wallet = 39
  t.eq(refused(game, { kind = "StartJob", actor = 0, item = item.id }), "not enough credits for the fee")
  state.wallet = 40
  t.eq(refused(game, { kind = "StartJob", actor = 0, item = item.id }), "(accepted)")

  -- Two jobs at once, until Mass Production adds a slot.
  state.wallet = 10000
  local more = Items.Add(state, "blueprint.ammo.fusion", 2, home, "hangar")
  order(t, game, { kind = "StartJob", actor = 0, item = item.id })
  order(t, game, { kind = "StartJob", actor = 0, item = more.id })
  t.eq(refused(game, { kind = "StartJob", actor = 0, item = more.id }), "every job slot is in use")
  t.eq(Core.Query.JobSlots(game), 2)
  state.skills["mass.production"] = 1
  order(t, game, { kind = "StartJob", actor = 0, item = more.id })
  t.eq(#Core.Query.Jobs(game), 3)

  order(t, game, { kind = "Undock", actor = 0 })
  t.eq(refused(game, { kind = "StartJob", actor = 0, item = item.id }), "not docked")
end)

suite:Case("a job finishes whether or not the pilot is there, and Industry makes it quicker", function(t)
  local game, home = newGame()
  local state = game.state
  state.skills.industry = 5
  Items.Add(state, "mineral.iron", 1000, home, "hangar")
  Items.Add(state, "mineral.silicon", 1000, home, "hangar")
  local rounds = hangar(game, "ammo.emp")
  order(t, game, { kind = "StartJob", actor = 0, item = stack(game, "blueprint.ammo.emp").id, quantity = 2 })
  -- 120 s, a fifth quicker
  local job = Core.Query.Jobs(game)[1]
  t.eq(job.ends - job.started, 96)
  order(t, game, { kind = "Undock", actor = 0 })
  for _ = 1, 100 do
    Core.Step(game)
  end
  t.eq(Core.Query.Player(game).docked, 0)
  t.eq(hangar(game, "ammo.emp"), rounds + 200)
end)

suite:Case("a hull built from its blueprint is a hull like any bought one", function(t)
  local game, home = newGame()
  local state = game.state
  state.wallet = 100000
  local blueprint = Blueprints.byId["blueprint.frigate.lancer"]
  for _, m in blueprint.materials do
    Items.Add(state, m.type, m.quantity, home, "hangar")
  end
  local item = Items.Add(state, blueprint.id, 1, home, "hangar")
  order(t, game, { kind = "StartJob", actor = 0, item = item.id })
  for _, m in blueprint.materials do
    t.eq(hangar(game, m.type), 0)
  end
  stepUntil(game, "JobDone", 5000)
  t.eq(hangar(game, "frigate.lancer"), 1)
  order(t, game, { kind = "Assemble", actor = 0, item = stack(game, "frigate.lancer").id })
  t.eq(#Core.Query.Ships(game, home), 2)
end)

suite:Case("a module's blueprint makes one module a run", function(t)
  local game, home = newGame()
  local state = game.state
  local module = Modules.byId["shield.extender.small"]
  local blueprint = Blueprints.byProduct[module.id]
  for _, m in blueprint.materials do
    Items.Add(state, m.type, m.quantity * 3, home, "hangar")
  end
  local had = hangar(game, module.id)
  order(t, game, { kind = "StartJob", actor = 0, item = Items.Add(state, blueprint.id, 1, home, "hangar").id, quantity = 3 })
  stepUntil(game, "JobDone", 2000)
  t.eq(hangar(game, module.id), had + 3)
end)

suite:Case("Reprocessing recovers 3% more of the ore a level", function(t)
  local game, home = newGame()
  local state = game.state
  t.eq(Industry.RefineYield(state), 0.5)
  state.skills.refining = 4
  t.near(Industry.RefineYield(state), 0.62, 1e-12)
  local ore = Items.Add(state, "ore.ferrite", 1000, home, "hangar")
  order(t, game, { kind = "Reprocess", actor = 0, item = ore.id })
  -- 250 iron and 30 silicon a hundred at perfect yield
  t.eq({ hangar(game, "mineral.iron"), hangar(game, "mineral.silicon") }, { 1550, 186 })
end)

suite:Case("jobs are plain data and survive a save, to the same state", function(t)
  local game, home = newGame()
  Items.Add(game.state, "mineral.iron", 1000, home, "hangar")
  Items.Add(game.state, "mineral.silicon", 1000, home, "hangar")
  order(t, game, { kind = "StartJob", actor = 0, item = stack(game, "blueprint.ammo.emp").id, quantity = 3 })
  for _ = 1, 50 do
    Core.Step(game)
  end
  local copy = Core.Load(Core.Save(game))
  t.eq(Core.Hash(copy), Core.Hash(game))
  for _ = 1, 200 do
    Core.Step(game)
    Core.Step(copy)
  end
  t.eq(#Core.Query.Jobs(copy), 0)
  t.eq(Industry.Have(copy.state, home, "ammo.emp"), hangar(game, "ammo.emp"))
  t.eq(Core.Hash(copy), Core.Hash(game))
end)

return suite
