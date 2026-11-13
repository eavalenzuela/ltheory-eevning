--!strict
-- The whole of the one-system game, played by a script through the
-- Core's front door with nothing handed to it: a new pilot mines,
-- refines, builds ammunition from a blueprint, sells it through standing
-- orders, trains, upgrades the ship, and trades up to a combat frigate.
-- This is the test that the parts add up to a game, and that the
-- numbers do: it fails if the climb takes an unreasonable time.

local Core = require("@lt/Core/Api")
local Items = require("@lt/Core/Assets/Items")
local Mining = require("@lt/Core/Tactical/Mining")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")
local Test = require("@lt/Tool/Test")
local Types = require("@lt/Core/Data/Types")

local suite = Test.Suite("Loop")

export type Log = {
  ticks: number,
  trips: number,
  rounds: number,       -- built
  events: { [string]: number },
  hash: string,
}

-- Play until the pilot is aboard a Akashi, or 'limit' ticks have passed.
local function play(t: Test.Context, historySeed: number, limit: number): (Core.Game, Log)
  local game = Core.New({ galaxySeed = 1, historySeed = historySeed, peaceful = true })
  local state = game.state
  local home = state.player.home
  local log: Log = { ticks = 0, trips = 0, rounds = 0, events = {}, hash = "" }

  local function step()
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      log.events[event.kind] = (log.events[event.kind] or 0) + 1
      if event.kind == "JobDone" then
        log.rounds += event.quantity
      elseif event.kind == "CommandRejected" then
        error(`{event.command} was rejected: {event.reason}`)
      end
    end
  end

  local function try(command: State.Command): boolean
    command.actor = state.player.ship
    return (Core.Submit(game, command))
  end

  local function must(command: State.Command)
    command.actor = state.player.ship
    local ok, reason = Core.Submit(game, command)
    if not ok then
      error(`{command.kind} was refused at tick {state.tick}: {tostring(reason)}`, 2)
    end
    step()
  end

  local function waitFor(what: string, ticks: number, done: () -> boolean)
    for _ = 1, ticks do
      if done() then
        return
      end
      step()
    end
    if not done() then
      error(`still waiting for {what} after {ticks} ticks, at tick {state.tick}`, 2)
    end
  end

  local function stack(type: string): State.Item?
    for _, item in Items.In(state, home, "hangar") do
      if item.type == type then
        return item
      end
    end
    return nil
  end

  local function have(type: string): number
    local item = stack(type)
    return if item then item.quantity else 0
  end

  local function miners(): { State.Item }
    local found = {}
    for _, item in Items.Fitted(state, state.player.ship) do
      if item.type == "miner.small" then
        table.insert(found, item)
      end
    end
    return found
  end

  local function free(): number
    return Items.ShipStats(state, state.player.ship).cargo - Items.CargoUsed(state, state.player.ship)
  end

  -- The belt with the most ferrite left, and that ferrite's rocks.
  local function bestBelt(): number
    local byBelt: { [number]: number } = {}
    local best, most = 0, 0
    for _, object in Core.Query.Objects(game, 1) do
      if object.kind == "asteroid" and object.variety == "ore.ferrite" then
        local left = (byBelt[object.parent] or 0) + Mining.Left(state, object)
        byBelt[object.parent] = left
        if left > most or (left == most and object.parent < best) then
          best, most = object.parent, left
        end
      end
    end
    assert(best ~= 0, "no ferrite anywhere")
    return best
  end

  local function nearestRock(belt: number): System.Object?
    local ball = assert(Core.Query.Ball(game, state.player.ship))
    local best: System.Object? = nil
    local bestGap = math.huge
    for _, object in Core.Query.Objects(game, 1) do
      if object.kind == "asteroid" and object.parent == belt and object.variety == "ore.ferrite"
        and Mining.Left(state, object) > 0 then
        local gap = Space.Gap(ball :: any, object :: any)
        if gap < bestGap then
          best, bestGap = object, gap
        end
      end
    end
    return best
  end

  local function mineAHold()
    must({ kind = "Undock", actor = 0 })
    local belt = bestBelt()
    must({ kind = "WarpTo", actor = 0, target = belt })
    waitFor("the warp to the belt", 600, function()
      local ball = Core.Query.Ball(game, state.player.ship)
      return ball ~= nil and ball.warp == nil and ball.grid == belt
    end)
    local rock: System.Object? = nil
    waitFor("a full hold", 3000, function()
      if free() < 0.1 then
        return true
      end
      local ball = assert(Core.Query.Ball(game, state.player.ship))
      if rock == nil or Mining.Left(state, rock) <= 0 then
        rock = nearestRock(belt)
        if rock == nil then
          return true   -- the belt is mined out: go home with what there is
        end
        try({ kind = "Approach", actor = 0, target = rock.id, range = 4000 })
      end
      local target = (rock :: System.Object).id
      if Space.Gap(ball :: any, rock :: any) < 9000 then
        try({ kind = "LockTarget", actor = 0, target = target })
        for _, laser in miners() do
          try({ kind = "ActivateModule", actor = 0, item = laser.id, target = target })
        end
      end
      return false
    end)
    must({ kind = "WarpTo", actor = 0, target = home })
    waitFor("the warp home", 600, function()
      local ball = Core.Query.Ball(game, state.player.ship)
      return ball ~= nil and ball.warp == nil
    end)
    must({ kind = "Dock", actor = 0, target = home })
    waitFor("docking", 600, function()
      return Core.Query.Player(game).docked ~= 0
    end)
    log.trips += 1
  end

  local function wantAkashi(): boolean
    local cost = Core.Query.BuyCost(game, home, "frigate.akashi", 1)
    return cost ~= nil and state.wallet >= cost and state.skills.frigates >= 2
  end

  local function atTheStation()
    for _, item in Items.In(state, state.player.ship, "cargo") do
      must({ kind = "MoveItems", actor = 0, item = item.id, to = "hangar" })
    end
    local blueprint = stack("blueprint.ammo.emp")
    local ore = stack("ore.ferrite")
    if ore and blueprint then
      -- Refine, buy what silicon the iron needs, and build.
      must({ kind = "Reprocess", actor = 0, item = ore.id })
      local runs = math.min(20, have("mineral.iron") // 210)
      if runs >= 1 then
        local short = runs * 45 - have("mineral.silicon")
        if short > 0 then
          must({ kind = "BuyNow", actor = 0, type = "mineral.silicon", quantity = short })
        end
        must({ kind = "StartJob", actor = 0, item = blueprint.id, quantity = runs })
      end
    elseif ore then
      -- The blueprint is busy: sell the ore as it is.
      must({ kind = "SellNow", actor = 0, item = ore.id })
    end
    -- Sell what has been built (and keep the starter rounds for the guns),
    -- asking as much as will still fill.
    local rounds = have("ammo.emp") - 600
    if rounds >= 100 then
      local quote = Core.Query.Quote(game, home, "ammo.emp")
      must({ kind = "PlaceOrder", actor = 0, to = "sell", item = (stack("ammo.emp") :: State.Item).id, quantity = rounds,
        price = math.floor(quote.sellAt) })
    end
    -- A second mining laser, once CPU Management 2 makes room for it.
    if #miners() == 1 and state.skills.electronics >= 2 then
      local cost = Core.Query.BuyCost(game, home, "miner.small", 1)
      if cost and state.wallet >= cost + 2000 then
        must({ kind = "BuyNow", actor = 0, type = "miner.small", quantity = 1 })
        for _, item in Items.Fitted(state, state.player.ship) do
          if item.type == "autocannon.small" then
            must({ kind = "Unfit", actor = 0, item = item.id })
          end
        end
        must({ kind = "Fit", actor = 0, item = (stack("miner.small") :: State.Item).id })
      end
    end
  end

  -- Before the first trip: a mining laser in place of one gun, and the
  -- training that the rest needs.
  must({ kind = "Unfit", actor = 0, item = Items.Fitted(state, state.player.ship)[1].id })
  must({ kind = "Fit", actor = 0, item = (stack("miner.small") :: State.Item).id })
  must({ kind = "TrainSkill", actor = 0, type = "electronics" })
  must({ kind = "TrainSkill", actor = 0, type = "electronics" })
  must({ kind = "TrainSkill", actor = 0, type = "frigates" })

  while state.tick < limit and not wantAkashi() do
    mineAHold()
    atTheStation()
  end
  if wantAkashi() then
    must({ kind = "BuyNow", actor = 0, type = "frigate.akashi", quantity = 1 })
    must({ kind = "Assemble", actor = 0, item = (stack("frigate.akashi") :: State.Item).id })
    local ships = Core.Query.Ships(game, home)
    must({ kind = "BoardShip", actor = 0, target = ships[#ships].id })
  end
  log.ticks = state.tick
  log.hash = Core.Hash(game)
  t.ok(Types.Get("frigate.akashi") ~= nil)
  return game, log
end

suite:Case("a new pilot mines, refines, builds, sells and trains their way into a combat frigate", function(t)
  local game, log = play(t, 1, 40000)
  local state = game.state
  local hours = log.ticks / 3600
  print(string.format("     loop: aboard a Akashi after %.1f game hours, %d trips, %d rounds built, wallet %d",
    hours, log.trips, log.rounds, state.wallet))
  t.eq(Core.Query.Player(game).hull.id, "frigate.akashi")
  t.ok(hours > 1 and hours < 6, `it took {hours} game hours`)
  -- every part of the loop was used
  for _, kind in { "Mined", "Reprocessed", "JobStarted", "JobDone", "OrderPlaced", "OrderFilled", "Sold", "Bought",
    "SkillTrained", "ShipAssembled", "ShipBoarded" } do
    t.ok((log.events[kind] or 0) > 0, `no {kind} happened`)
  end
  t.eq({ state.skills.frigates, state.skills.electronics }, { 2, 2 })
  t.ok(log.rounds >= 1000, `only {log.rounds} rounds were built`)
  -- and the books balance: the wallet is the sum of its journal
  local sum = 5000
  for _, entry in state.journal do
    sum += entry.amount
  end
  t.eq(sum, state.wallet)
end)

suite:Case("played twice, it comes out the same to the last bit", function(t)
  local _, first = play(t, 7, 6000)
  local _, second = play(t, 7, 6000)
  t.eq(first.hash, second.hash)
  t.eq(first.ticks, second.ticks)
end)

return suite
