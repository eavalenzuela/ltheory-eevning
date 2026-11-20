--!strict
-- Building from blueprints, through the Core's front door.

local Blueprints = require("@lt/Core/Data/Blueprints")
local Boosters = require("@lt/Core/Data/Boosters")
local Core = require("@lt/Core/Api")
local Industry = require("@lt/Core/Assets/Industry")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Ores = require("@lt/Core/Data/Ores")
local Ships = require("@lt/Core/Data/Ships")
local Structures = require("@lt/Core/Data/Structures")
local Factions = require("@lt/Core/Data/Factions")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Stations = require("@lt/Core/Assets/Stations")
local Test = require("@lt/Tool/Test")
local Types = require("@lt/Core/Data/Types")

local suite = Test.Suite("Industry")

local function newGame(): (Core.Game, number)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  return game, game.state.player.home
end

-- A type's stack in the hangar of the pilot's home station, if there is one.
local function inHangar(game: Core.Game, type: string): State.Item?
  for _, item in Items.In(game.state, game.state.player.home, "hangar") do
    if item.type == type then
      return item
    end
  end
  return nil
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
    local custom = Modules.byId[id] ~= nil and Modules.byId[id].meta ~= nil
    if custom then
      -- (a custom make is found, never built: there are no drawings for it)
      t.eq(Blueprints.byProduct[id], nil, id)
    elseif info.category == "module" or info.category == "charge" or info.category == "ship" or info.category == "component"
      or info.category == "structure" or info.category == "drone" or Boosters.byId[id] ~= nil then
      -- (an alien people's tower and the pirates' are built from a print nobody sells: Data/Blueprints)
      local tower = Structures.towerById[id]
      if tower and not tower.citadel then
        t.eq(Blueprints.byProduct[id].rare == true, Factions.byId[tower.faction].kind ~= "human", id)
      end
      -- (and a booster, which is made of its gas)
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
      t.eq(blueprint.basePrice, info.basePrice * blueprint.perRun * Blueprints.ORIGINAL)
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

suite:Case("a job is called off where it runs: the blueprint comes back with what the finished runs made, and the rest is lost", function(t)
  local game, home = newGame()
  local state = game.state
  local item = stack(game, "blueprint.ammo.emp")
  Items.Add(state, "mineral.iron", 1050, home, "hangar")
  Items.Add(state, "mineral.silicon", 225, home, "hangar")
  local rounds = hangar(game, "ammo.emp")
  t.eq(refused(game, { kind = "CancelJob", actor = 0, target = 4242 }), "no such job")
  -- Five runs of a hundred rounds, 288 seconds in all. Called off after 120: two runs are done.
  order(t, game, { kind = "StartJob", actor = 0, item = item.id, quantity = 5 })
  local job = Core.Query.Jobs(game, home)[1]
  local wallet = state.wallet
  for _ = 1, 119 do
    Core.Step(game)
  end
  Core.TakeEvents(game)
  order(t, game, { kind = "CancelJob", actor = 0, target = job.id })
  local called: any = nil
  for _, event in Core.TakeEvents(game) do
    if event.kind == "JobCancelled" then
      called = event
    end
    t.ok(event.kind ~= "JobDone", "a job called off is not done")
  end
  t.eq({ called.job, called.product, called.made, called.quantity, called.research } :: { any },
    { job.id, "ammo.emp", 200, 500, "" } :: { any })
  t.eq({ hangar(game, "ammo.emp"), hangar(game, "blueprint.ammo.emp"), hangar(game, "mineral.iron"), hangar(game, "mineral.silicon") },
    { rounds + 200, 1, 0, 0 })
  t.eq({ #Core.Query.Jobs(game), state.wallet }, { 0, wallet }, "its place is free, and the fee is not given back")
  for _ = 1, 400 do
    Core.Step(game)
  end
  t.eq(hangar(game, "ammo.emp"), rounds + 200, "nothing more should come of a job called off")
  -- At once, nothing has been made; and a job is called off only where it runs.
  Items.Add(state, "mineral.iron", 210, home, "hangar")
  Items.Add(state, "mineral.silicon", 45, home, "hangar")
  order(t, game, { kind = "StartJob", actor = 0, item = stack(game, "blueprint.ammo.emp").id, quantity = 1 })
  local second = Core.Query.Jobs(game, home)[1]
  state.ships[state.player.ship].docked = home + 1
  t.eq(refused(game, { kind = "CancelJob", actor = 0, target = second.id }), "that job is running at another station")
  state.ships[state.player.ship].docked = home
  order(t, game, { kind = "CancelJob", actor = 0, target = second.id })
  t.eq({ hangar(game, "ammo.emp"), hangar(game, "blueprint.ammo.emp") }, { rounds + 200, 1 })
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
  local blueprint = Blueprints.byId["blueprint.frigate.battleaxe"]
  for _, m in blueprint.materials do
    Items.Add(state, m.type, m.quantity, home, "hangar")
  end
  local item = Items.Add(state, blueprint.id, 1, home, "hangar")
  order(t, game, { kind = "StartJob", actor = 0, item = item.id })
  for _, m in blueprint.materials do
    t.eq(hangar(game, m.type), 0)
  end
  stepUntil(game, "JobDone", 5000)
  t.eq(hangar(game, "frigate.battleaxe"), 1)
  order(t, game, { kind = "Assemble", actor = 0, item = stack(game, "frigate.battleaxe").id })
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

suite:Case("research in a laboratory takes a level at a time off what a blueprint uses, or off how long it takes", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local home = state.player.home
  state.wallet = 10000000
  local blueprint = Blueprints.byId["blueprint.ammo.emp"]
  local item = assert(inHangar(game, blueprint.id))
  for _, mineral in { "mineral.iron", "mineral.silicon" } do
    Items.Add(state, mineral, 1000000, home, "hangar")
  end
  local function submit(command: State.Command): (boolean, string?)
    command.actor = state.player.ship
    local ok, why = Core.Submit(game, command)
    Core.Step(game)
    return ok, why
  end
  local before = Industry.Plan(state, home, blueprint, 10)
  t.eq({ Industry.Researched(state, blueprint.id) }, { 0, 0 })
  local first = assert(Industry.ResearchPlan(state, blueprint, "material"))
  t.eq({ first.level, first.fee }, { 1, math.ceil(blueprint.basePrice * 0.02 * 10 / Blueprints.ORIGINAL) })
  t.eq({ Core.Validate(game, { kind = "StartResearch", actor = state.player.ship, item = item.id, what = "speed" }) } :: { any },
    { false, "research is into materials or into time" } :: { any })

  -- A level of each. The blueprint is in the laboratory meanwhile, and research takes a job slot.
  local wallet = state.wallet
  t.ok(submit({ kind = "StartResearch", actor = 0, item = item.id, what = "material" }))
  t.eq(wallet - state.wallet, first.fee)
  t.eq(inHangar(game, blueprint.id), nil)
  t.eq(#Core.Query.Jobs(game, home), 1)
  t.eq(Core.Query.Jobs(game, home)[1].research, "material")
  for _ = 1, first.seconds + 2 do
    Core.Step(game)
  end
  t.eq({ Industry.Researched(state, blueprint.id) }, { 1, 0 })
  item = assert(inHangar(game, blueprint.id))
  t.eq(#Core.Query.Jobs(game, home), 0)
  local second = assert(Industry.ResearchPlan(state, blueprint, "material"))
  t.ok(second.seconds > first.seconds and second.fee > first.fee, "a second level should take longer and cost more than the first")
  t.ok(submit({ kind = "StartResearch", actor = 0, item = item.id, what = "time" }))
  for _ = 1, first.seconds + 2 do
    Core.Step(game)
  end
  t.eq({ Industry.Researched(state, blueprint.id) }, { 1, 1 })

  -- What was learned comes off a job: a hundredth of the materials, a fiftieth of the time.
  local after = Industry.Plan(state, home, blueprint, 10)
  for index, material in after.materials do
    t.eq(material.need, math.max(10, math.ceil(before.materials[index].need * 0.99 - 1e-9)))
    t.ok(material.need <= before.materials[index].need)
  end
  t.ok(after.seconds < before.seconds)
  t.near(after.seconds, before.seconds * 0.98, 1)
  t.eq(after.quantity, before.quantity)

  -- Ten levels is all there is.
  state.research[blueprint.id] = { material = 10, time = 3 }
  t.eq(Industry.ResearchPlan(state, blueprint, "material"), nil)
  item = assert(inHangar(game, blueprint.id))
  t.eq({ Core.Validate(game, { kind = "StartResearch", actor = state.player.ship, item = item.id, what = "material" }) } :: { any },
    { false, "there is no more to learn of it" } :: { any })
  local status = assert(Core.Query.Research(game, blueprint.id))
  t.eq({ status.material, status.time, status.nextMaterial == nil, status.nextTime ~= nil } :: { any }, { 10, 3, true, true } :: { any })
  local tenth = Industry.Plan(state, home, blueprint, 10)
  t.near(tenth.materials[1].need, before.materials[1].need * 0.9, 1)
end)

suite:Case("research wants a laboratory, and is in the save", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  state.wallet = 10000000
  local item = assert(inHangar(game, "blueprint.ammo.emp"))
  local study: State.Command = { kind = "StartResearch", actor = state.player.ship, item = item.id, what = "time" }
  t.ok((Core.Validate(game, study)), "the starter station should have a laboratory")
  -- Moor the ship, and the blueprint, at a station without one.
  local home = state.player.home
  for system = 1, 3 do
    for _, object in Core.Query.Objects(game, system) do
      if object.kind == "station" and not Stations.Has(state, object.id, "research") then
        state.ships[state.player.ship].docked = object.id
        item.holder = object.id
        t.eq({ Core.Validate(game, study) } :: { any }, { false, "this station has no Laboratory" } :: { any })
      end
    end
  end
  state.ships[state.player.ship].docked = home
  item.holder = home
  t.ok(Core.Submit(game, study))
  for _ = 1, 50 do
    Core.Step(game)
  end
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  for _ = 1, 600 do
    Core.Step(game)
    Core.Step(loaded)
  end
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.eq({ Industry.Researched(loaded.state, "blueprint.ammo.emp") }, { 0, 1 })
end)

suite:Case("a laboratory copies a blueprint: a copy good for so many runs, for a fee and half the time of building them", function(t)
  local game, home = newGame()
  local state = game.state
  local blueprint = Blueprints.byId["blueprint.ammo.emp"]
  -- A copy is an item of its own, by the run: named for its blueprint, among the types and in no market.
  t.eq({ Blueprints.Copy(blueprint), Blueprints.Of("copy.ammo.emp"), select(2, Blueprints.Of("copy.ammo.emp")) } :: { any },
    { "copy.ammo.emp", blueprint, true } :: { any })
  t.eq({ Blueprints.Of("blueprint.ammo.emp") } :: { any }, { blueprint, false } :: { any })
  t.eq({ Blueprints.Of("ammo.emp") } :: { any }, { nil, false } :: { any })
  t.eq({ Blueprints.Of("copy.nothing") } :: { any }, { nil, false } :: { any })
  local info = Types.Info("copy.ammo.emp")
  t.eq({ info.name, info.category, info.unlisted, info.basePrice } :: { any },
    { "Shock Canister Blueprint Copy", "blueprint", true, blueprint.basePrice // 500 } :: { any })
  t.eq(table.find(Types.Ids(), "copy.ammo.emp"), nil, "no market lists a copy")
  for _, each in Blueprints.list do
    local copy = assert(Types.Get(Blueprints.Copy(each)), each.id)
    t.ok(copy.unlisted and copy.basePrice >= 1 and copy.basePrice * 100 <= each.basePrice + 99, each.id)
  end

  -- Five runs: 60 s a run to build, so 150 s to copy; and the fee of building them.
  local item = stack(game, "blueprint.ammo.emp")
  local plan = assert(Core.Query.CopyPlan(game, "blueprint.ammo.emp", 5))
  t.eq(plan, { copy = "copy.ammo.emp", runs = 5, seconds = 150, fee = 200 })
  t.eq(Core.Query.CopyPlan(game, "copy.ammo.emp", 5), nil)
  t.eq(refused(game, { kind = "StartResearch", actor = 0, item = item.id, what = "copy", quantity = 0 }), "a copy is of 1 to 100 runs")
  t.eq(refused(game, { kind = "StartResearch", actor = 0, item = item.id, what = "copy", quantity = 101 }), "a copy is of 1 to 100 runs")
  t.eq(refused(game, { kind = "StartResearch", actor = 0, item = item.id, what = "copy", quantity = 2.5 }), "a copy is of 1 to 100 runs")
  state.wallet = 199
  t.eq(refused(game, { kind = "StartResearch", actor = 0, item = item.id, what = "copy", quantity = 5 }), "not enough credits for the fee")
  state.wallet = 5000
  Core.TakeEvents(game)
  order(t, game, { kind = "StartResearch", actor = 0, item = item.id, what = "copy", quantity = 5 })
  t.eq({ state.wallet, state.journal[#state.journal].reason, hangar(game, "blueprint.ammo.emp") } :: { any },
    { 4800, "copying fee", 0 } :: { any })
  local jobs = Core.Query.Jobs(game, home)
  t.eq({ #jobs, jobs[1].research, jobs[1].blueprint, jobs[1].product, jobs[1].runs, jobs[1].quantity, jobs[1].ends - jobs[1].started } :: { any },
    { 1, "copy", "blueprint.ammo.emp", "copy.ammo.emp", 5, 5, 150 } :: { any })
  local done, ticks = stepUntil(game, "CopyDone", 200)
  t.eq({ done.blueprint, done.copy, done.runs, done.station, ticks } :: { any },
    { "blueprint.ammo.emp", "copy.ammo.emp", 5, home, 150 } :: { any })
  t.eq({ hangar(game, "blueprint.ammo.emp"), hangar(game, "copy.ammo.emp"), #Core.Query.Jobs(game) }, { 1, 5, 0 })

  -- A copy is not copied, nor researched: both take the blueprint itself. And no market deals in one.
  local copy = stack(game, "copy.ammo.emp")
  for _, what in { "copy", "material", "time" } do
    t.eq(refused(game, { kind = "StartResearch", actor = 0, item = copy.id, what = what, quantity = 1 }),
      "that takes the blueprint itself, not a copy", what)
  end
  t.eq(refused(game, { kind = "SellNow", actor = 0, item = copy.id, quantity = 1 }), "no market deals in that")
  t.eq(refused(game, { kind = "PlaceOrder", actor = 0, to = "sell", item = copy.id, quantity = 1, price = 100 }), "no market deals in that")
  t.eq(refused(game, { kind = "BuyNow", actor = 0, type = "copy.ammo.emp", quantity = 1 }), "no such item type")

  -- Copying takes a place among the jobs, and a laboratory.
  state.wallet = 100000
  order(t, game, { kind = "StartResearch", actor = 0, item = stack(game, "blueprint.ammo.emp").id, what = "copy", quantity = 100 })
  local second = Items.Add(state, "blueprint.autocannon.small", 2, home, "hangar")
  order(t, game, { kind = "StartResearch", actor = 0, item = second.id, what = "copy", quantity = 1 })
  t.eq(refused(game, { kind = "StartResearch", actor = 0, item = second.id, what = "copy", quantity = 1 }), "every job slot is in use")
end)

suite:Case("a job built from a copy uses up the runs it is for, and what its owner has researched counts for it", function(t)
  local game, home = newGame()
  local state = game.state
  Items.Add(state, "copy.ammo.emp", 5, home, "hangar")
  Items.Add(state, "mineral.iron", 2000, home, "hangar")
  Items.Add(state, "mineral.silicon", 500, home, "hangar")
  local copy = stack(game, "copy.ammo.emp")
  -- A copy has the runs it has: no more are to be had of it.
  t.eq(refused(game, { kind = "StartJob", actor = 0, item = copy.id, quantity = 6 }), "that copy has 5 runs left")
  -- It plans as the blueprint does, and what has been researched of the design comes off it too.
  local plain = assert(Core.Query.JobPlan(game, home, "blueprint.ammo.emp", 3))
  local plan = assert(Core.Query.JobPlan(game, home, "copy.ammo.emp", 3))
  t.eq({ plan.quantity, plan.seconds, plan.fee, plan.materials[1].need }, { plain.quantity, plain.seconds, plain.fee, 630 })
  state.research["blueprint.ammo.emp"] = { material = 10, time = 0 }
  t.eq(assert(Core.Query.JobPlan(game, home, "copy.ammo.emp", 3)).materials[1].need, 567)
  state.research["blueprint.ammo.emp"] = nil

  local rounds = hangar(game, "ammo.emp")
  Core.TakeEvents(game)
  order(t, game, { kind = "StartJob", actor = 0, item = copy.id, quantity = 3 })
  t.eq({ hangar(game, "copy.ammo.emp"), hangar(game, "blueprint.ammo.emp"), hangar(game, "mineral.iron") }, { 2, 1, 2000 - 630 })
  t.eq(Core.Query.Jobs(game, home)[1].blueprint, "copy.ammo.emp")
  local done = stepUntil(game, "JobDone", 400)
  t.eq({ done.product, done.quantity } :: { any }, { "ammo.emp", 300 } :: { any })
  -- The rounds, and nothing else: the three runs are gone, and the blueprint in the hangar is the one that was there.
  t.eq({ hangar(game, "ammo.emp"), hangar(game, "copy.ammo.emp"), hangar(game, "blueprint.ammo.emp") }, { rounds + 300, 2, 1 })
  -- The last of it: one run is left, which is said as one.
  order(t, game, { kind = "StartJob", actor = 0, item = stack(game, "copy.ammo.emp").id, quantity = 1 })
  t.eq(refused(game, { kind = "StartJob", actor = 0, item = stack(game, "copy.ammo.emp").id, quantity = 2 }), "that copy has 1 run left")
  -- (the blueprint builds beside it meanwhile: a copy is how one design is at work twice)
  order(t, game, { kind = "StartJob", actor = 0, item = stack(game, "blueprint.ammo.emp").id, quantity = 1 })
  stepUntil(game, "JobDone", 400)
  for _ = 1, 5 do
    Core.Step(game)
  end
  t.eq({ hangar(game, "ammo.emp"), hangar(game, "copy.ammo.emp"), hangar(game, "blueprint.ammo.emp"), #Core.Query.Jobs(game) },
    { rounds + 500, 1, 1, 0 })
  order(t, game, { kind = "StartJob", actor = 0, item = stack(game, "copy.ammo.emp").id, quantity = 1 })
  t.eq(inHangar(game, "copy.ammo.emp"), nil, "a copy with no runs left is no more")
end)

suite:Case("called off, a job from a copy gives back the runs not used, and a copying the runs copied", function(t)
  local game, home = newGame()
  local state = game.state
  Items.Add(state, "copy.ammo.emp", 5, home, "hangar")
  Items.Add(state, "mineral.iron", 1050, home, "hangar")
  Items.Add(state, "mineral.silicon", 225, home, "hangar")
  local rounds = hangar(game, "ammo.emp")
  -- Five runs, 288 seconds in all. Called off after 120: two runs are done, and three are the copy's still.
  order(t, game, { kind = "StartJob", actor = 0, item = stack(game, "copy.ammo.emp").id, quantity = 5 })
  t.eq(inHangar(game, "copy.ammo.emp"), nil)
  for _ = 1, 119 do
    Core.Step(game)
  end
  Core.TakeEvents(game)
  order(t, game, { kind = "CancelJob", actor = 0, target = Core.Query.Jobs(game, home)[1].id })
  local called: any = nil
  for _, event in Core.TakeEvents(game) do
    called = if event.kind == "JobCancelled" then event else called
  end
  t.eq({ called.blueprint, called.made, called.quantity, called.back } :: { any }, { "copy.ammo.emp", 200, 500, 3 } :: { any })
  t.eq({ hangar(game, "ammo.emp"), hangar(game, "copy.ammo.emp"), hangar(game, "blueprint.ammo.emp"), hangar(game, "mineral.iron") },
    { rounds + 200, 3, 1, 0 })

  -- A copying of ten runs, 300 seconds. Called off after 100: three runs are copied, and the blueprint is back.
  order(t, game, { kind = "StartResearch", actor = 0, item = stack(game, "blueprint.ammo.emp").id, what = "copy", quantity = 10 })
  for _ = 1, 99 do
    Core.Step(game)
  end
  Core.TakeEvents(game)
  order(t, game, { kind = "CancelJob", actor = 0, target = Core.Query.Jobs(game, home)[1].id })
  for _, event in Core.TakeEvents(game) do
    called = if event.kind == "JobCancelled" then event else called
    t.ok(event.kind ~= "CopyDone", "a copying called off is not done")
  end
  t.eq({ called.research, called.made, called.quantity, called.back } :: { any }, { "copy", 3, 10, 0 } :: { any })
  t.eq({ hangar(game, "copy.ammo.emp"), hangar(game, "blueprint.ammo.emp"), #Core.Query.Jobs(game) }, { 6, 1, 0 })

  -- An invention called off gives back the run it was working from, and not its datacores.
  state.skills.invention = 1
  state.wallet = 1000000
  Items.Add(state, Industry.DATACORE, 2, home, "hangar")
  order(t, game, { kind = "StartResearch", actor = 0, item = stack(game, "copy.ammo.emp").id, what = "invent" })
  t.eq({ hangar(game, "copy.ammo.emp"), hangar(game, Industry.DATACORE) }, { 5, 0 })
  order(t, game, { kind = "CancelJob", actor = 0, target = Core.Query.Jobs(game, home)[1].id })
  t.eq({ hangar(game, "copy.ammo.emp"), hangar(game, Industry.DATACORE), hangar(game, "blueprint.ammo.emp") }, { 6, 0, 1 })
end)

suite:Case("copying, and a job from a copy, are in the save", function(t)
  local game, home = newGame()
  local state = game.state
  Items.Add(state, "copy.ammo.emp", 4, home, "hangar")
  Items.Add(state, "mineral.iron", 1000, home, "hangar")
  Items.Add(state, "mineral.silicon", 1000, home, "hangar")
  order(t, game, { kind = "StartJob", actor = 0, item = stack(game, "copy.ammo.emp").id, quantity = 3 })
  order(t, game, { kind = "StartResearch", actor = 0, item = stack(game, "blueprint.ammo.emp").id, what = "copy", quantity = 7 })
  for _ = 1, 50 do
    Core.Step(game)
  end
  local loaded = Core.Load(Core.Save(game))
  t.eq(Core.Hash(loaded), Core.Hash(game))
  for _ = 1, 400 do
    Core.Step(game)
    Core.Step(loaded)
  end
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.eq({ #Core.Query.Jobs(loaded), Industry.Have(loaded.state, home, "copy.ammo.emp"), Industry.Have(loaded.state, home, "blueprint.ammo.emp") },
    { 0, 8, 1 })
end)

suite:Case("invention works out a tech 2 blueprint from a copy of a plain one, for datacores, and may come to nothing", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local home = state.player.home
  state.wallet = 10000000
  -- What has no tech 2 make cannot be invented from. (A cloaking device has none, since 2026-11-20 one of the few.)
  local projector = Items.Add(state, "blueprint.cloak.device", 1, home, "hangar")
  t.eq(Industry.InventionPlan(state, Blueprints.byId["blueprint.cloak.device"]), nil)
  t.eq(refused(game, { kind = "StartResearch", actor = 0, item = projector.id, what = "invent" }), "there is no tech 2 make of that to invent")
  -- Rounds have one, and so has a drone: as a small module is to work out, and a medium one for the bigger drones.
  local rounds = assert(Industry.InventionPlan(state, Blueprints.byId["blueprint.ammo.emp"]))
  t.eq({ rounds.product, rounds.blueprint, rounds.datacores } :: { any }, { "ammo.emp.ii", "blueprint.ammo.emp.ii", 2 } :: { any })
  t.eq(assert(Industry.InventionPlan(state, Blueprints.byId["blueprint.missile.cruise.kinetic"])).datacores, 8)
  local light = assert(Industry.InventionPlan(state, Blueprints.byId["blueprint.drone.light"]))
  t.eq({ light.product, light.datacores } :: { any }, { "drone.light.ii", 2 } :: { any })
  t.eq(assert(Industry.InventionPlan(state, Blueprints.byId["blueprint.drone.mining"])).datacores, 4)
  -- A small autocannon has: two datacores, half an hour, three chances in ten.
  -- It is worked out from a copy, never from the blueprint itself.
  local plain = Items.Add(state, "blueprint.autocannon.small", 1, home, "hangar")
  t.eq(refused(game, { kind = "StartResearch", actor = 0, item = plain.id, what = "invent" }), "inventing uses up a copy: copy this first")
  local copies = Items.Add(state, "copy.autocannon.small", 40, home, "hangar")
  local invent: State.Command = { kind = "StartResearch", actor = 0, item = copies.id, what = "invent" }
  local plan = assert(Industry.InventionPlan(state, Blueprints.byId["blueprint.autocannon.small"]))
  t.eq({ plan.product, plan.blueprint, plan.datacores, plan.seconds } :: { any },
    { "autocannon.small.ii", "blueprint.autocannon.small.ii", 2, 1800 } :: { any })
  t.near(plan.chance, 0.3, 1e-9)
  t.eq(assert(Industry.InventionPlan(state, Blueprints.byId["blueprint.artillery.large"])).datacores, 8)
  t.eq(refused(game, invent), "needs Invention 1")
  state.skills.invention = 2
  t.near(assert(Industry.InventionPlan(state, Blueprints.byId["blueprint.autocannon.small"])).chance, 0.4, 1e-9)
  t.eq(refused(game, invent), "needs 2 more Datacore")
  Items.Add(state, Industry.DATACORE, 1, home, "hangar")
  t.eq(refused(game, invent), "needs 1 more Datacore")
  -- Try it until one comes off and one does not: each takes its datacores, its fee and a run of the copy, and
  -- gives none of them back. The blueprint itself stays where it is.
  Items.Add(state, Industry.DATACORE, 99, home, "hangar")
  local won, lost = 0, 0
  for attempt = 1, 30 do
    local wallet, cores, runs = state.wallet, hangar(game, Industry.DATACORE), hangar(game, "copy.autocannon.small")
    order(t, game, { kind = "StartResearch", actor = 0, item = stack(game, "copy.autocannon.small").id, what = "invent" })
    t.eq({ wallet - state.wallet, cores - hangar(game, Industry.DATACORE), runs - hangar(game, "copy.autocannon.small"),
      hangar(game, "blueprint.autocannon.small") }, { plan.fee, 2, 1, 1 })
    local had = hangar(game, "blueprint.autocannon.small.ii")
    local event, ticks = stepUntil(game, "InventionDone", 2000)
    t.ok(ticks >= 1790 and ticks <= 1800, `an invention took {ticks} ticks`)
    t.eq({ event.blueprint, event.product, event.used } :: { any },
      { "copy.autocannon.small", "blueprint.autocannon.small.ii", true } :: { any })
    t.eq({ hangar(game, "blueprint.autocannon.small"), runs - hangar(game, "copy.autocannon.small") }, { 1, 1 })
    t.eq(hangar(game, "blueprint.autocannon.small.ii") - had, if event.success then 1 else 0)
    won += if event.success then 1 else 0
    lost += if event.success then 0 else 1
    if won > 0 and lost > 0 and attempt >= 12 then
      break
    end
  end
  t.ok(won >= 1 and lost >= 1, `{won} inventions came off and {lost} did not`)
  t.ok(won <= lost + 3, `at four chances in ten, {won} of {won + lost} came off`)

  -- What was invented builds the tech 2 module: of the plain one, components and the rare minerals.
  local made = Blueprints.byId["blueprint.autocannon.small.ii"]
  t.eq({ made.materials[1].type, made.materials[1].quantity } :: { any }, { "autocannon.small", 1 } :: { any })
  local rare = 0
  for _, material in made.materials do
    Items.Add(state, material.type, material.quantity, home, "hangar")
    rare += if material.type == "mineral.cobalt" or material.type == "mineral.iridium" or material.type == "mineral.titanium" then 1 else 0
  end
  t.eq(rare, 3)
  order(t, game, { kind = "StartJob", actor = 0, item = stack(game, made.id).id, quantity = 1 })
  local built = stepUntil(game, "JobDone", 5000)
  t.eq({ built.product, hangar(game, "autocannon.small.ii"), hangar(game, "autocannon.small") } :: { any },
    { "autocannon.small.ii", 1, 0 } :: { any })
  -- It wants more of the skill than the plain one to fit.
  local item = stack(game, "autocannon.small.ii")
  t.eq(refused(game, { kind = "Fit", actor = 0, item = item.id }), "needs Projectile Turrets 4")
end)

suite:Case("a hull with two tech 2 makes is invented toward the one asked for (the Vessari's Ouyou: the Hoshizora and the Raiden)", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local print = Blueprints.byId["blueprint.cruiser.ouyou"]
  local each = Industry.Inventions(state, print)
  t.eq({ #each, each[1].product, each[2].product } :: { any }, { 2, "cruiser.hoshizora", "cruiser.raiden" } :: { any })
  t.eq(assert(Industry.InventionPlan(state, print, "cruiser.raiden")).blueprint, "blueprint.cruiser.raiden")
  -- (the first, where none is asked for; and a hull with one make has one invention)
  t.eq(assert(Industry.InventionPlan(state, print)).product, "cruiser.hoshizora")
  t.eq(#Industry.Inventions(state, Blueprints.byId["blueprint.destroyer.nozomi"]), 1)
end)

suite:Case("a tech 2 hull is invented from a copy of the plain hull's blueprint, built of the plain hull, and wants more skill to board", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local home = state.player.home
  state.wallet = 1000000000
  state.skills.invention = 5
  -- (A ship has no "II": a tech 2 ship is a hull of its own that comes of a plain one, where a faction's line
  -- names one. The Talmar's hauler, the Sunfish, has the Tarantula.)
  -- A hull is a bigger thing to work out than a module: sixteen datacores for a hauler, and on up.
  local plan = assert(Industry.InventionPlan(state, Blueprints.byId["blueprint.industrial.sunfish"]))
  local better = Ships.byId["industrial.tarantula"]
  t.eq({ plan.product, plan.blueprint, plan.datacores, plan.seconds, plan.fee } :: { any },
    { "industrial.tarantula", "blueprint.industrial.tarantula", 16, 7200, math.ceil(better.basePrice * 0.05) } :: { any })
  t.near(plan.chance, 0.55, 1e-9)
  t.eq({ assert(Industry.InventionPlan(state, Blueprints.byId["blueprint.freighter.rhino"])).datacores,
    assert(Industry.InventionPlan(state, Blueprints.byId["blueprint.capitalindustrial.jaguar"])).datacores }, { 64, 128 })
  -- (a hull whose faction names no tech 2 make of it has none, nor has a tech 2 hull one of its own)
  for _, plain in { "frigate.courier", "frigate.akashi", "battleship.owari", "barge.anteater", "frigate.creavo", "industrial.armadillo" } do
    t.eq(Industry.InventionPlan(state, Blueprints.byId["blueprint." .. plain]), nil, plain)
    t.eq(Ships.byId[plain .. ".ii"], nil, plain)
  end
  t.eq(Industry.InventionPlan(state, Blueprints.byId["blueprint.industrial.tarantula"]), nil)

  Items.Add(state, "copy.industrial.sunfish", 20, home, "hangar")
  Items.Add(state, Industry.DATACORE, 400, home, "hangar")
  local tries = 0
  while hangar(game, "blueprint.industrial.tarantula") == 0 and tries < 20 do
    tries += 1
    order(t, game, { kind = "StartResearch", actor = 0, item = stack(game, "copy.industrial.sunfish").id, what = "invent" })
    local event, ticks = stepUntil(game, "InventionDone", 8000)
    t.ok(ticks >= 7190 and ticks <= 7200, `inventing a hauler took {ticks} ticks`)
    t.eq(event.product, "blueprint.industrial.tarantula")
  end
  t.eq(hangar(game, "blueprint.industrial.tarantula"), 1, `nothing came of {tries} tries`)
  t.eq({ hangar(game, Industry.DATACORE), hangar(game, "copy.industrial.sunfish") }, { 400 - 16 * tries, 20 - tries })

  -- Built of the plain hull and of what makes the difference. Without the plain hull, nothing.
  local made = Blueprints.byId["blueprint.industrial.tarantula"]
  for index, material in made.materials do
    if index > 1 then
      Items.Add(state, material.type, material.quantity, home, "hangar")
    end
  end
  local build: State.Command = { kind = "StartJob", actor = 0, item = stack(game, made.id).id, quantity = 1 }
  t.eq(refused(game, build), "needs 1 more Talmar Sunfish")
  Items.Add(state, "industrial.sunfish", 1, home, "hangar")
  order(t, game, build)
  local built = stepUntil(game, "JobDone", 80000)
  t.eq({ built.product, hangar(game, "industrial.tarantula"), hangar(game, "industrial.sunfish") } :: { any },
    { "industrial.tarantula", 1, 0 } :: { any })

  -- Assembled, it is a ship; boarding it wants the hauler's skill at four.
  order(t, game, { kind = "Assemble", actor = 0, item = stack(game, "industrial.tarantula").id })
  local ships = Core.Query.Ships(game, home)
  local ship = ships[#ships]
  t.eq(ship.type, "industrial.tarantula")
  state.skills.industrials = 3
  t.eq(refused(game, { kind = "BoardShip", actor = 0, target = ship.id }), "needs Industrials 4")
  state.skills.industrials = 4
  order(t, game, { kind = "BoardShip", actor = 0, target = ship.id })
  t.eq(Core.Query.Player(game).hull.id, "industrial.tarantula")
  -- More of it than the plain hull, bare.
  local plain = Ships.byId["industrial.sunfish"]
  local stats = Items.ShipStats(state, ship.id)
  t.ok(stats.cpu > 1.15 * Items.ShipStats(state, ships[1].id).cpu or stats.cpu > plain.cpu, "a tech 2 hull should have more to fit with")
  t.eq({ better.lows - plain.lows + better.mids - plain.mids, better.turrets, better.launchers }, { 1, plain.turrets, plain.launchers })
  -- Insured for what it is worth, which is eight of the plain hull.
  t.eq(better.basePrice, 8 * plain.basePrice)
end)

suite:Case("nobody sells a tech 2 module, its blueprint or a datacore, and a station that has none buys them dear", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local home = state.player.home
  state.wallet = 100000000
  for _, type in { "autocannon.small.ii", "blueprint.autocannon.small.ii", "datacore" } do
    local quote = Core.Query.Quote(game, home, type)
    t.eq(quote.stock, 0, type)
    t.eq(refused(game, { kind = "BuyNow", actor = 0, type = type, quantity = 1 }) ~= "(accepted)", true, type)
    -- (what a pilot brings is bought for more than its base price, there being none)
    Items.Add(state, type, 1, home, "hangar")
    t.ok(Core.Query.SellValue(game, home, type, 1) > Types.Info(type).basePrice, type)
  end
  -- The plain module is for sale as it always was.
  t.ok(Core.Query.Quote(game, home, "autocannon.small").stock > 0)
end)

suite:Case("a hull that is a refinery too refines the ore in its own holds where it lies, in space or docked, and puts the minerals in its hold", function(t)
  -- The Drowned's Griever is such a hull (the project owner's: "mass-miner, mobile refinery"), and since 2026-11-20 every
  -- capital industrial but a transport (the owner's: in place of compressing ore); nothing else is.
  for _, hull in Ships.list do
    t.eq(hull.refinery, if hull.class == "capitalindustrial" and hull.role ~= "transport" then true else nil, hull.id)
  end
  local function flying(hull: string): (Core.Game, State.Ship)
    local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
    local state = game.state
    local mine = Space.NewShip(state, hull, "Tester", "player", state.player.home)
    state.player.ship = mine.id
    return game, mine
  end
  local function count(state: State.State, holder: number, place: string, type: string): number
    local found = 0
    for _, item in Items.In(state, holder, place) do
      found += if item.type == type then item.quantity else 0
    end
    return found
  end
  -- Any other hull's ore is refined at a station, out of the hangar: not out of its hold.
  local plain, other = flying("industrial.porter")
  local kept = Items.Add(plain.state, "ore.ferrite", 1000, other.id, "cargo")
  t.eq(refused(plain, { kind = "Reprocess", actor = 0, item = kept.id }), "this hull has no refinery aboard")

  local game, ship = flying("capitalindustrial.griever")
  local state = game.state
  local ore = Items.Add(state, "ore.ferrite", 1050, ship.id, "orehold")
  local few = Items.Add(state, "ore.cuprite", 5, ship.id, "cargo")
  t.ok(5 < Ores.BATCH)
  t.eq(refused(game, { kind = "Reprocess", actor = 0, item = few.id }), `refining takes at least {Ores.BATCH} units`)
  -- Docked, at a station whatever it has for a refinery: the ore out of its ore hold, the minerals into its hold.
  local used, minerals = Industry.RefineOutput("ore.ferrite", 1050, Industry.RefineYield(state))
  t.ok(used > 0 and used <= 1050 and #minerals >= 1)
  order(t, game, { kind = "Reprocess", actor = 0, item = ore.id })
  t.eq(count(state, ship.id, "orehold", "ore.ferrite"), 1050 - used)
  for _, m in minerals do
    t.eq({ count(state, ship.id, "cargo", m.mineral), count(state, state.player.home, "hangar", m.mineral) }, { m.amount, 0 }, m.mineral)
  end
  -- In space: the same, out of its hold this time.
  local more = Items.Add(state, "ore.ferrite", 2 * Ores.BATCH, ship.id, "cargo")
  order(t, game, { kind = "Undock", actor = 0 })
  t.ok(state.balls[ship.id] ~= nil, "the Griever should be in space")
  local had = count(state, ship.id, "cargo", minerals[1].mineral)
  order(t, game, { kind = "Reprocess", actor = 0, item = more.id })
  t.eq(count(state, ship.id, "cargo", "ore.ferrite"), 0)
  t.ok(count(state, ship.id, "cargo", minerals[1].mineral) > had, "nothing came of refining in space")
  -- With no room in the hold for what would come of it, it is refused.
  local big = Items.Add(state, "ore.ferrite", 4 * Ores.BATCH, ship.id, "orehold")
  local hold = Items.ShipStats(state, ship.id).cargo - Items.CargoUsed(state, ship.id)
  Items.Add(state, "scrap.metal", math.max(1, math.floor(hold / Types.Info("scrap.metal").volume)), ship.id, "cargo")
  t.eq(refused(game, { kind = "Reprocess", actor = 0, item = big.id }), "no room in the hold for the minerals")
end)

return suite
