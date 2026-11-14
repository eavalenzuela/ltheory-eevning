--!strict
-- Making things out of other things, at a station: refining ore into
-- minerals, and building from blueprints.
--
-- A manufacturing job takes a blueprint, the minerals for its runs and a
-- fee, and some time. When the time is up the product and the blueprint
-- appear in the hangar of the station the job ran at, whether or not the
-- pilot is there. A pilot runs a couple of jobs at once.
--
-- A blueprint builds for ever, and is in one place at a time. A copy of
-- it is good for so many runs and no more: a laboratory makes copies
-- from the blueprint, a job built from a copy uses up the runs it is
-- for, and an invention uses one up whether it comes off or not. So
-- the blueprint can stay at home, building, while its copies go where
-- the work is.

local Blueprints = require("@lt/Core/Data/Blueprints")
local Constants = require("@lt/Core/Data/Constants")
local Items = require("@lt/Core/Assets/Items")
local Drones = require("@lt/Core/Data/Drones")
local Modules = require("@lt/Core/Data/Modules")
local Ores = require("@lt/Core/Data/Ores")
local Rng = require("@lt/Core/Kernel/Rng")
local State = require("@lt/Core/Kernel/State")
local Ships = require("@lt/Core/Data/Ships")
local Types = require("@lt/Core/Data/Types")
local Wallet = require("@lt/Core/Assets/Wallet")

local Industry = {}

-- The most runs one job can be for.
Industry.MAX_RUNS = 100

export type Event = { [string]: any }

-- The item, if it is a stack in the hangar of the station the ship is
-- docked at; otherwise nil and why not.
local function inHangar(state: State.State, command: State.Command): (State.Item?, string?)
  local ship = state.ships[command.actor]
  if ship == nil then
    return nil, "no such ship"
  elseif ship.docked == 0 then
    return nil, "not docked"
  end
  local item = state.items[command.item or 0]
  if item == nil then
    return nil, "no such item"
  elseif item.holder ~= ship.docked or item.place ~= "hangar" then
    return nil, "that is not in the hangar here"
  end
  return item, nil
end

-- The share of an ore's minerals the pilot recovers: 3% more for each
-- level of Reprocessing.
function Industry.RefineYield(state: State.State): number
  return Ores.REFINE_YIELD + 0.03 * math.max(0, state.skills.refining or 0)
end

-- What refining a stack of ore gives: the units used, and the minerals.
function Industry.RefineOutput(type: string, quantity: number, yield: number?): (number, { { mineral: string, amount: number } })
  local ore = Ores.byId[type]
  local batches = quantity // Ores.BATCH
  local share = yield or Ores.REFINE_YIELD
  local out = {}
  for _, yield in ore.yields do
    local amount = math.floor(batches * yield.amount * share + 1e-9)
    if amount > 0 then
      table.insert(out, { mineral = yield.mineral, amount = amount })
    end
  end
  return batches * Ores.BATCH, out
end

-- ---------------------------------------------------------------------
-- Manufacturing

-- How many of a type are in a station's hangar.
function Industry.Have(state: State.State, station: number, type: string): number
  local have = 0
  for _, item in Items.In(state, station, "hangar") do
    if item.type == type then
      have += item.quantity
    end
  end
  return have
end

-- Jobs the pilot can run at once: one more for each level of Mass
-- Production.
function Industry.JobSlots(state: State.State): number
  return Blueprints.JOB_SLOTS + math.max(0, state.skills["mass.production"] or 0)
end

-- Research: what a pilot has learned of a blueprint in a laboratory.
-- Each level of the one kind takes 1% off what a run uses, and each of
-- the other 2% off how long it takes, to ten levels of each (material
-- and time efficiency). It is the pilot's knowledge of the
-- design, not a mark on one copy: it holds for every copy they have.
Industry.RESEARCH_LEVELS = 10
Industry.MATERIAL_SAVED = 0.01
Industry.TIME_SAVED = 0.02
-- What a level of two of a pilot's crafts takes off the time (Data/
-- Skills): Bench Science off research, Draughtsmanship off copying.
Industry.BENCH, Industry.DRAUGHT = 0.05, 0.05

-- The levels a pilot has researched of a blueprint: materials, time.
function Industry.Researched(state: State.State, blueprint: string): (number, number)
  local known = state.research[blueprint]
  if known then
    return known.material, known.time
  end
  return 0, 0
end

export type ResearchPlan = { what: string, level: number, seconds: number, fee: number }

-- What the next level of research into a blueprint would take: "material"
-- or "time". Nil when there is no next level. Each level takes half as
-- long again as the last, and costs more.
function Industry.ResearchPlan(state: State.State, blueprint: Blueprints.Blueprint, what: string): ResearchPlan?
  local material, time = Industry.Researched(state, blueprint.id)
  local level = if what == "material" then material elseif what == "time" then time else Industry.RESEARCH_LEVELS
  if level >= Industry.RESEARCH_LEVELS then
    return nil
  end
  return {
    what = what, level = level + 1,
    -- (5% quicker for each level of Bench Science)
    seconds = math.ceil((300 + 0.5 * math.min(7200, blueprint.seconds)) * 1.5 ^ level
      * (1 - Industry.BENCH * math.max(0, state.skills["bench.science"] or 0))),
    fee = math.ceil(blueprint.basePrice * 0.02 * (level + 1)),
  }
end

-- Invention: working out, in a laboratory, the tech 2 make of what a
-- blueprint builds. It takes datacores (found in derelicts), a fee and
-- a while, more of each the bigger the module, and may come to nothing:
-- three chances in ten, and one in twenty more for each level of the
-- Invention skill. The blueprint it starts from is given back either
-- way, and a success leaves a blueprint for the tech 2 module beside it,
-- for good.
--
-- It is worked out from a copy of the blueprint, and one run of the
-- copy is used up by it, whether it comes off or not: the blueprint
-- itself is never put to it.
Industry.DATACORE = "datacore"
-- How big a thing a hull of a class is to invent, where a small module
-- is 1 and a large one 3: it sets the datacores (two, doubled for each
-- step) and the time.
Industry.HULL_SIZE = { frigate = 3, destroyer = 4, industrial = 4, barge = 4, cruiser = 5, attackbattlecruiser = 6,
  battlecruiser = 6, battleship = 6, freighter = 6, capitalindustrial = 7 } :: { [string]: number }
Industry.INVENT_CHANCE = 0.3
Industry.INVENT_SKILL = 0.05

export type InventionPlan = { product: string, blueprint: string, datacores: number, seconds: number, fee: number, chance: number }

-- What inventing from a blueprint would take and make, or nil if what
-- it builds has no tech 2 make.
function Industry.InventionPlan(state: State.State, blueprint: Blueprints.Blueprint): InventionPlan?
  local module = Modules.Improved(blueprint.product)
  local hull = Ships.Improved(blueprint.product)
  local charge = Modules.ImprovedCharge(blueprint.product)
  local drone = Drones.Improved(blueprint.product)
  local id = if module then module.id elseif hull then hull.id elseif charge then charge.id elseif drone then drone.id else ""
  local made = Blueprints.byProduct[id]
  if made == nil then
    return nil
  end
  -- (a hull is a bigger thing to work out than any module; a charge is
  -- as its weapon is, and a drone as a small module or a medium one)
  local size = if module then Modules.SizeOf(module) elseif hull then Industry.HULL_SIZE[hull.class] or 3
    elseif charge then charge.size elseif drone then (if drone.volume > 5 then 2 else 1) else 1
  return {
    product = id, blueprint = made.id, datacores = 2 ^ size, seconds = 1800 * size,
    fee = math.ceil(Types.Info(id).basePrice * 0.05),
    chance = math.min(1, Industry.INVENT_CHANCE + Industry.INVENT_SKILL * math.max(0, state.skills.invention or 0)),
  }
end

-- How long a job of so many runs takes: 4% less for each level of
-- Industry, and less again for what has been researched of it.
function Industry.JobSeconds(state: State.State, blueprint: Blueprints.Blueprint, runs: number): number
  local _, time = Industry.Researched(state, blueprint.id)
  return math.ceil(blueprint.seconds * runs * (1 - 0.04 * math.max(0, state.skills.industry or 0)) * (1 - Industry.TIME_SAVED * time))
end

-- What the station charges to run it.
function Industry.JobFee(blueprint: Blueprints.Blueprint, runs: number): number
  return math.ceil(Blueprints.JOB_FEE * Types.Info(blueprint.product).basePrice * blueprint.perRun * runs)
end

-- Copying: a laboratory makes of a blueprint a copy good for so many
-- runs. A run takes half as long to copy as to build, and the station
-- charges for it what it would to build it. The blueprint is in the
-- laboratory meanwhile, and comes back with the copy.
Industry.COPY_TIME = 0.5

export type CopyPlan = { copy: string, runs: number, seconds: number, fee: number }

-- What copying so many runs of a blueprint would take, and the item
-- type the copy is. (5% quicker for each level of Draughtsmanship.)
function Industry.CopyPlan(state: State.State, blueprint: Blueprints.Blueprint, runs: number): CopyPlan
  local quicker = 1 - Industry.DRAUGHT * math.max(0, state.skills.draughtsmanship or 0)
  return { copy = Blueprints.Copy(blueprint), runs = runs, seconds = math.ceil(blueprint.seconds * runs * Industry.COPY_TIME * quicker),
    fee = Industry.JobFee(blueprint, runs) }
end

export type Plan = {
  blueprint: Blueprints.Blueprint,
  runs: number,
  quantity: number,     -- units it would make
  seconds: number,
  fee: number,
  materials: { { type: string, need: number, have: number } },
}

-- What a job of so many runs at a station would take, and what of it is
-- in the hangar there.
function Industry.Plan(state: State.State, station: number, blueprint: Blueprints.Blueprint, runs: number): Plan
  local materials = {}
  -- (what has been researched comes off the whole job, though never to
  -- less than one of a thing a run)
  local saved = 1 - Industry.MATERIAL_SAVED * (Industry.Researched(state, blueprint.id))
  for _, m in blueprint.materials do
    table.insert(materials, { type = m.type, need = math.max(runs, math.ceil(m.quantity * runs * saved - 1e-9)),
      have = Industry.Have(state, station, m.type) })
  end
  return {
    blueprint = blueprint, runs = runs, quantity = blueprint.perRun * runs,
    seconds = Industry.JobSeconds(state, blueprint, runs), fee = Industry.JobFee(blueprint, runs),
    materials = materials,
  }
end

-- The jobs running, optionally at one station, oldest first.
function Industry.Jobs(state: State.State, station: number?): { State.Job }
  local found = {}
  for _, id in state.jobIds do
    local job = state.jobs[id]
    if station == nil or job.station == station then
      table.insert(found, job)
    end
  end
  return found
end

function Industry.Validate(state: State.State, command: State.Command): (boolean, string?)
  if command.kind == "CancelJob" then
    -- A job is called off where it runs, by whoever is docked there.
    local ship = state.ships[command.actor]
    local job = state.jobs[command.target or 0]
    if ship == nil then
      return false, "no such ship"
    elseif job == nil then
      return false, "no such job"
    elseif ship.docked ~= job.station then
      return false, "that job is running at another station"
    end
    return true
  end
  local item, why = inHangar(state, command)
  if item == nil then
    return false, why
  end
  if command.kind == "Reprocess" then
    if Ores.byId[item.type] == nil then
      return false, "that is not ore"
    elseif item.quantity < Ores.BATCH then
      return false, `refining takes at least {Ores.BATCH} units`
    end
    return true

  elseif command.kind == "StartJob" then
    local blueprint, copy = Blueprints.Of(item.type)
    if blueprint == nil then
      return false, "that is not a blueprint"
    end
    local runs = command.quantity or 1
    if runs < 1 or runs % 1 ~= 0 or runs > Industry.MAX_RUNS then
      return false, `a job is for 1 to {Industry.MAX_RUNS} runs`
    elseif copy and runs > item.quantity then
      return false, if item.quantity == 1 then "that copy has 1 run left" else `that copy has {item.quantity} runs left`
    elseif (state.skills.industry or 0) < 1 then
      return false, "needs Industry 1"
    elseif #state.jobIds >= Industry.JobSlots(state) then
      return false, "every job slot is in use"
    end
    local plan = Industry.Plan(state, item.holder, blueprint, runs)
    for _, m in plan.materials do
      if m.have < m.need then
        return false, `needs {m.need - m.have} more {Types.Info(m.type).name}`
      end
    end
    if plan.fee > state.wallet then
      return false, "not enough credits for the fee"
    end
    return true

  elseif command.kind == "StartResearch" then
    local blueprint, copy = Blueprints.Of(item.type)
    if blueprint == nil then
      return false, "that is not a blueprint"
    elseif command.what == "invent" then
      local plan = Industry.InventionPlan(state, blueprint)
      if plan == nil then
        return false, "there is no tech 2 make of that to invent"
      elseif not copy then
        return false, "inventing uses up a copy: copy this first"
      elseif (state.skills.invention or 0) < 1 then
        return false, "needs Invention 1"
      elseif #state.jobIds >= Industry.JobSlots(state) then
        return false, "every job slot is in use"
      end
      local have = 0
      for _, stack in Items.In(state, item.holder, "hangar") do
        if stack.type == Industry.DATACORE then
          have += stack.quantity
        end
      end
      if have < plan.datacores then
        return false, `needs {plan.datacores - have} more Datacore`
      elseif plan.fee > state.wallet then
        return false, "not enough credits for the fee"
      end
      return true
    elseif copy then
      -- (what is learned is learned of the design, and a copy is made
      -- of the design: neither is to be had from a copy)
      return false, "that takes the blueprint itself, not a copy"
    elseif command.what == "copy" then
      local runs = command.quantity or 1
      if runs < 1 or runs % 1 ~= 0 or runs > Industry.MAX_RUNS then
        return false, `a copy is of 1 to {Industry.MAX_RUNS} runs`
      elseif (state.skills.industry or 0) < 1 then
        return false, "needs Industry 1"
      elseif #state.jobIds >= Industry.JobSlots(state) then
        return false, "every job slot is in use"
      elseif Industry.CopyPlan(state, blueprint, runs).fee > state.wallet then
        return false, "not enough credits for the fee"
      end
      return true
    elseif command.what ~= "material" and command.what ~= "time" then
      return false, "research is into materials or into time"
    end
    local plan = Industry.ResearchPlan(state, blueprint, command.what :: string)
    if plan == nil then
      return false, "there is no more to learn of it"
    elseif (state.skills.industry or 0) < 1 then
      return false, "needs Industry 1"
    elseif #state.jobIds >= Industry.JobSlots(state) then
      return false, "every job slot is in use"
    elseif plan.fee > state.wallet then
      return false, "not enough credits for the fee"
    end
    return true
  end
  return false, `unknown command '{command.kind}'`
end

-- How many units a job that builds has finished so far: whole runs of
-- it, by how far through its time it is. (And of a job that copies, the
-- runs copied so far. Research and invention have no runs, and have
-- made nothing until they are done.)
function Industry.Made(state: State.State, job: State.Job): number
  if job.runs < 1 then
    return 0
  end
  local span = math.max(1, job.ends - job.started)
  local runs = math.floor(job.runs * math.clamp((state.tick - job.started) / span, 0, 1))
  return runs * (job.quantity // job.runs)
end

function Industry.Apply(state: State.State, command: State.Command, events: { Event })
  if command.kind == "CancelJob" then
    -- Called off: the blueprint comes back, and what the runs already
    -- finished have made. What went into the rest is lost, and the fee.
    -- (Of a copy, what comes back is the runs not yet used: those the
    -- job had not got to, or the one an invention was working from.)
    local job = state.jobs[command.target :: number]
    local made = Industry.Made(state, job)
    local _, copy = Blueprints.Of(job.blueprint)
    local back = 1
    if copy then
      back = if job.runs < 1 then 1 else job.runs - made // math.max(1, job.quantity // job.runs)
    end
    if back > 0 then
      Items.Add(state, job.blueprint, back, job.station, "hangar")
    end
    if made > 0 then
      Items.Add(state, job.product, made, job.station, "hangar")
    end
    state.jobs[job.id] = nil
    State.RemoveId(state.jobIds, job.id)
    table.insert(events, { kind = "JobCancelled", job = job.id, blueprint = job.blueprint, product = job.product, made = made,
      quantity = job.quantity, research = job.research, station = job.station, back = if copy then back else 0 })
    return
  end
  local ship = state.ships[command.actor]
  local item = state.items[command.item :: number]
  if command.kind == "Reprocess" then
    local type = item.type
    local used, minerals = Industry.RefineOutput(type, item.quantity, Industry.RefineYield(state))
    Items.Take(state, item, used)
    for _, m in minerals do
      Items.Add(state, m.mineral, m.amount, ship.docked, "hangar")
    end
    table.insert(events, { kind = "Reprocessed", ship = ship.id, ore = type, units = used, minerals = minerals })

  elseif command.kind == "StartJob" then
    local station = ship.docked
    local blueprint, copy = Blueprints.Of(item.type)
    local plan = Industry.Plan(state, station, blueprint :: Blueprints.Blueprint, command.quantity or 1)
    for _, m in plan.materials do
      local left = m.need
      for _, stack in Items.In(state, station, "hangar") do
        if left > 0 and stack.type == m.type then
          local take = math.min(left, stack.quantity)
          Items.Take(state, stack, take)
          left -= take
        end
      end
    end
    -- The blueprint is in the job until it is done. The runs of a copy
    -- are in it for good: the job carries the copy's type as its
    -- blueprint, which is how its end knows there is nothing to give
    -- back.
    local held = item.type
    Items.Take(state, item, if copy then plan.runs else 1)
    Wallet.Pay(state, -plan.fee, "manufacturing fee", events)
    local job: State.Job = {
      id = State.NewId(state), station = station, blueprint = held, runs = plan.runs,
      product = plan.blueprint.product, quantity = plan.quantity, research = "",
      started = state.tick, ends = state.tick + math.ceil(plan.seconds / Constants.TICK),
    }
    state.jobs[job.id] = job
    table.insert(state.jobIds, job.id)
    table.insert(events, { kind = "JobStarted", job = job.id, product = job.product, quantity = job.quantity, ends = job.ends })

  elseif command.kind == "StartResearch" and command.what == "invent" then
    local blueprint = Blueprints.Of(item.type) :: Blueprints.Blueprint
    local plan = Industry.InventionPlan(state, blueprint) :: InventionPlan
    local station = ship.docked
    local left = plan.datacores
    for _, stack in Items.In(state, station, "hangar") do
      if left > 0 and stack.type == Industry.DATACORE then
        local take = math.min(left, stack.quantity)
        Items.Take(state, stack, take)
        left -= take
      end
    end
    -- One run of the copy goes into the laboratory, and does not come
    -- out of it.
    local held = item.type
    Items.Take(state, item, 1)
    Wallet.Pay(state, -plan.fee, "invention fee", events)
    -- (the job carries the blueprint it hopes to make as its product)
    local job: State.Job = {
      id = State.NewId(state), station = station, blueprint = held, runs = 0, product = plan.blueprint, quantity = 1,
      research = "invent", started = state.tick, ends = state.tick + math.ceil(plan.seconds / Constants.TICK),
    }
    state.jobs[job.id] = job
    table.insert(state.jobIds, job.id)
    table.insert(events, { kind = "ResearchStarted", job = job.id, blueprint = held, what = "invent", ends = job.ends })

  elseif command.kind == "StartResearch" and command.what == "copy" then
    local blueprint = Blueprints.byId[item.type]
    local plan = Industry.CopyPlan(state, blueprint, command.quantity or 1)
    -- The blueprint is in the laboratory until it is done.
    Items.Take(state, item, 1)
    Wallet.Pay(state, -plan.fee, "copying fee", events)
    -- (the job carries the copy it is making as its product, a unit a run)
    local job: State.Job = {
      id = State.NewId(state), station = ship.docked, blueprint = blueprint.id, runs = plan.runs, product = plan.copy,
      quantity = plan.runs, research = "copy", started = state.tick, ends = state.tick + math.ceil(plan.seconds / Constants.TICK),
    }
    state.jobs[job.id] = job
    table.insert(state.jobIds, job.id)
    table.insert(events, { kind = "ResearchStarted", job = job.id, blueprint = blueprint.id, what = "copy", ends = job.ends })

  elseif command.kind == "StartResearch" then
    local blueprint = Blueprints.byId[item.type]
    local plan = Industry.ResearchPlan(state, blueprint, command.what :: string) :: ResearchPlan
    -- The blueprint is in the laboratory until it is done.
    Items.Take(state, item, 1)
    Wallet.Pay(state, -plan.fee, "research fee", events)
    local job: State.Job = {
      id = State.NewId(state), station = ship.docked, blueprint = blueprint.id, runs = 0, product = "", quantity = 0,
      research = plan.what, started = state.tick, ends = state.tick + math.ceil(plan.seconds / Constants.TICK),
    }
    state.jobs[job.id] = job
    table.insert(state.jobIds, job.id)
    table.insert(events, { kind = "ResearchStarted", job = job.id, blueprint = blueprint.id, what = plan.what, ends = job.ends })
  end
end

-- Each tick: a job whose time is up delivers its product, and its
-- blueprint, to the hangar it ran at. (Not a copy: the runs of a copy
-- that went into a job are used.)
function Industry.Step(state: State.State, events: { Event })
  for _, id in table.clone(state.jobIds) do
    local job = state.jobs[id]
    if job.ends <= state.tick then
      local blueprint, copy = Blueprints.Of(job.blueprint)
      if not copy then
        Items.Add(state, job.blueprint, 1, job.station, "hangar")
      end
      state.jobs[id] = nil
      State.RemoveId(state.jobIds, id)
      if job.research == "invent" then
        -- It comes off, or it does not: the roll is the job's own, and
        -- the chance is what the pilot's skill makes it when it ends.
        local plan = if blueprint then Industry.InventionPlan(state, blueprint) else nil
        local chance = if plan then plan.chance else 0
        local success = Rng.Chance(Rng.For(state.historySeed, job.id, 91), chance)
        if success then
          Items.Add(state, job.product, 1, job.station, "hangar")
        end
        table.insert(events, { kind = "InventionDone", job = id, blueprint = job.blueprint, product = job.product,
          success = success, station = job.station, used = copy })
      elseif job.research == "copy" then
        -- The copy, by the run, beside the blueprint it was made from.
        Items.Add(state, job.product, job.quantity, job.station, "hangar")
        table.insert(events, { kind = "CopyDone", job = id, blueprint = job.blueprint, copy = job.product, runs = job.quantity,
          station = job.station })
      elseif job.research ~= "" then
        -- What was learned is the pilot's from now on.
        local known = state.research[job.blueprint] or { material = 0, time = 0 }
        if job.research == "material" then
          known.material += 1
        else
          known.time += 1
        end
        state.research[job.blueprint] = known
        table.insert(events, { kind = "ResearchDone", job = id, blueprint = job.blueprint, what = job.research,
          level = if job.research == "material" then known.material else known.time, station = job.station })
      else
        Items.Add(state, job.product, job.quantity, job.station, "hangar")
        table.insert(events, { kind = "JobDone", job = id, product = job.product, quantity = job.quantity, station = job.station })
      end
    end
  end
end

return Industry
