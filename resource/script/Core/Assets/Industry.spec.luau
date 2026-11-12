--!strict
-- Building from blueprints, through the Core's front door.

local Blueprints = require("@lt/Core/Data/Blueprints")
local Core = require("@lt/Core/Api")
local Industry = require("@lt/Core/Assets/Industry")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Ships = require("@lt/Core/Data/Ships")
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
      or info.category == "structure" or info.category == "drone" then
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
  t.eq({ first.level, first.fee }, { 1, math.ceil(blueprint.basePrice * 0.02) })
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

suite:Case("invention works out a tech 2 blueprint from a plain one, for datacores, and may come to nothing", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local home = state.player.home
  state.wallet = 10000000
  -- What has no tech 2 make cannot be invented from. (An entanglement projector has none.)
  local projector = Items.Add(state, "blueprint.projector.entanglement", 1, home, "hangar")
  t.eq(Industry.InventionPlan(state, Blueprints.byId["blueprint.projector.entanglement"]), nil)
  t.eq(refused(game, { kind = "StartResearch", actor = 0, item = projector.id, what = "invent" }), "there is no tech 2 make of that to invent")
  -- Rounds have one, and so has a drone: as a small module is to work out, and a medium one for the bigger drones.
  local rounds = assert(Industry.InventionPlan(state, Blueprints.byId["blueprint.ammo.emp"]))
  t.eq({ rounds.product, rounds.blueprint, rounds.datacores } :: { any }, { "ammo.emp.ii", "blueprint.ammo.emp.ii", 2 } :: { any })
  t.eq(assert(Industry.InventionPlan(state, Blueprints.byId["blueprint.missile.cruise.kinetic"])).datacores, 8)
  local light = assert(Industry.InventionPlan(state, Blueprints.byId["blueprint.drone.light"]))
  t.eq({ light.product, light.datacores } :: { any }, { "drone.light.ii", 2 } :: { any })
  t.eq(assert(Industry.InventionPlan(state, Blueprints.byId["blueprint.drone.mining"])).datacores, 4)
  -- A small autocannon has: two datacores, half an hour, three chances in ten.
  local plain = Items.Add(state, "blueprint.autocannon.small", 1, home, "hangar")
  local invent: State.Command = { kind = "StartResearch", actor = 0, item = plain.id, what = "invent" }
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
  -- Try it until one comes off and one does not: each takes its datacores and fee, and gives the plain blueprint back.
  Items.Add(state, Industry.DATACORE, 99, home, "hangar")
  local won, lost = 0, 0
  for attempt = 1, 30 do
    local wallet, cores = state.wallet, hangar(game, Industry.DATACORE)
    order(t, game, { kind = "StartResearch", actor = 0, item = stack(game, "blueprint.autocannon.small").id, what = "invent" })
    t.eq({ wallet - state.wallet, cores - hangar(game, Industry.DATACORE), hangar(game, "blueprint.autocannon.small") },
      { plan.fee, 2, 0 })
    local had = hangar(game, "blueprint.autocannon.small.ii")
    local event, ticks = stepUntil(game, "InventionDone", 2000)
    t.ok(ticks >= 1790 and ticks <= 1800, `an invention took {ticks} ticks`)
    t.eq({ event.blueprint, event.product } :: { any }, { "blueprint.autocannon.small", "blueprint.autocannon.small.ii" } :: { any })
    t.eq(hangar(game, "blueprint.autocannon.small"), 1)
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

suite:Case("a tech 2 hull is invented from the plain hull's blueprint, built of the plain hull, and wants more skill to board", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local home = state.player.home
  state.wallet = 1000000000
  state.skills.invention = 5
  -- A hull is a bigger thing to work out than a module: eight datacores for a frigate, and on up.
  local plan = assert(Industry.InventionPlan(state, Blueprints.byId["blueprint.frigate.javelin"]))
  local better = Ships.byId["frigate.javelin.ii"]
  t.eq({ plan.product, plan.blueprint, plan.datacores, plan.seconds, plan.fee } :: { any },
    { "frigate.javelin.ii", "blueprint.frigate.javelin.ii", 8, 5400, math.ceil(better.basePrice * 0.05) } :: { any })
  t.near(plan.chance, 0.55, 1e-9)
  t.eq({ assert(Industry.InventionPlan(state, Blueprints.byId["blueprint.destroyer.halberd"])).datacores,
    assert(Industry.InventionPlan(state, Blueprints.byId["blueprint.cruiser.cuirass"])).datacores,
    assert(Industry.InventionPlan(state, Blueprints.byId["blueprint.battleship.bastion"])).datacores,
    assert(Industry.InventionPlan(state, Blueprints.byId["blueprint.barge.quarry"])).datacores }, { 16, 32, 64, 16 })
  -- (the starter hull has no tech 2 make, nor has a tech 2 hull one of its own)
  t.eq(Industry.InventionPlan(state, Blueprints.byId["blueprint.frigate.courier"]), nil)
  t.eq(Industry.InventionPlan(state, Blueprints.byId["blueprint.frigate.javelin.ii"]), nil)

  Items.Add(state, "blueprint.frigate.javelin", 1, home, "hangar")
  Items.Add(state, Industry.DATACORE, 200, home, "hangar")
  local tries = 0
  while hangar(game, "blueprint.frigate.javelin.ii") == 0 and tries < 20 do
    tries += 1
    order(t, game, { kind = "StartResearch", actor = 0, item = stack(game, "blueprint.frigate.javelin").id, what = "invent" })
    local event, ticks = stepUntil(game, "InventionDone", 6000)
    t.ok(ticks >= 5390 and ticks <= 5400, `inventing a frigate took {ticks} ticks`)
    t.eq(event.product, "blueprint.frigate.javelin.ii")
  end
  t.eq(hangar(game, "blueprint.frigate.javelin.ii"), 1, `nothing came of {tries} tries`)
  t.eq(hangar(game, Industry.DATACORE), 200 - 8 * tries)

  -- Built of the plain hull and of what makes the difference. Without the plain hull, nothing.
  local made = Blueprints.byId["blueprint.frigate.javelin.ii"]
  for index, material in made.materials do
    if index > 1 then
      Items.Add(state, material.type, material.quantity, home, "hangar")
    end
  end
  local build: State.Command = { kind = "StartJob", actor = 0, item = stack(game, made.id).id, quantity = 1 }
  t.eq(refused(game, build), "needs 1 more Vessari Javelin")
  Items.Add(state, "frigate.javelin", 1, home, "hangar")
  order(t, game, build)
  local built = stepUntil(game, "JobDone", 80000)
  t.eq({ built.product, hangar(game, "frigate.javelin.ii"), hangar(game, "frigate.javelin") } :: { any }, { "frigate.javelin.ii", 1, 0 } :: { any })

  -- Assembled, it is a ship; boarding it wants the frigate skill at five.
  order(t, game, { kind = "Assemble", actor = 0, item = stack(game, "frigate.javelin.ii").id })
  local ships = Core.Query.Ships(game, home)
  local ship = ships[#ships]
  t.eq(ship.type, "frigate.javelin.ii")
  state.skills.frigates = 4
  t.eq(refused(game, { kind = "BoardShip", actor = 0, target = ship.id }), "needs Frigates 5")
  state.skills.frigates = 5
  order(t, game, { kind = "BoardShip", actor = 0, target = ship.id })
  t.eq(Core.Query.Player(game).hull.id, "frigate.javelin.ii")
  -- More of it than the plain hull, bare.
  local plain = Ships.byId["frigate.javelin"]
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

return suite
