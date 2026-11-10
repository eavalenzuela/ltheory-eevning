--!strict
-- Mining and refining, through the Core's front door.

local Core = require("@lt/Core/Api")
local Industry = require("@lt/Core/Assets/Industry")
local Items = require("@lt/Core/Assets/Items")
local Mining = require("@lt/Core/Tactical/Mining")
local Ores = require("@lt/Core/Data/Ores")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Mining")

local function me(game: Core.Game): State.Ball
  return assert(Core.Query.Ball(game, game.state.player.ship))
end

local function order(t: Test.Context, game: Core.Game, command: State.Command)
  command.actor = game.state.player.ship
  local ok, reason = Core.Submit(game, command)
  t.ok(ok, `{command.kind} was refused: {tostring(reason)}`)
end

local function refused(game: Core.Game, command: State.Command): string?
  command.actor = game.state.player.ship
  local ok, reason = Core.Validate(game, command)
  return if ok then "(accepted)" else reason
end

local function stepUntil(game: Core.Game, kind: string, limit: number): (Space.Event, number)
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

local function hold(game: Core.Game, type: string): number
  for _, item in Items.In(game.state, game.state.player.ship, "cargo") do
    if item.type == type then
      return item.quantity
    end
  end
  return 0
end

-- A peaceful game with a mining laser in place of one gun, the ship at a
-- belt within mining range of a locked rock of the ore asked for.
local function atRock(t: Test.Context, oreId: string): (Core.Game, State.Ball, number, State.Item)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local ship = state.player.ship
  local cannon = Items.Fitted(state, ship)[1]
  Items.Take(state, cannon, 1)
  local laser = Items.Equip(state, ship, "miner.small", nil)
  Core.Submit(game, { kind = "Undock", actor = ship })
  Core.Step(game)
  -- Find a belt with a rock of that ore, and go to the rock.
  local rock: number? = nil
  for _, object in Core.Query.Objects(game, 1) do
    if object.kind == "asteroid" and object.variety == oreId then
      rock = object.id
      break
    end
  end
  local target = assert(rock, `no {oreId} in the first system`)
  local belt = assert(Space.Object(state, target)).parent
  order(t, game, { kind = "WarpTo", actor = 0, target = belt })
  stepUntil(game, "WarpEnded", 300)
  order(t, game, { kind = "Approach", actor = 0, target = target, range = 3000 })
  for _ = 1, 400 do
    Core.Step(game)
  end
  order(t, game, { kind = "LockTarget", actor = 0, target = target })
  stepUntil(game, "LockCompleted", 30)
  Core.TakeEvents(game)
  return game, me(game), target, laser
end

suite:Case("every belt rock is an ore, and common ores are common", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local counts: { [string]: number } = {}
  local total = 0
  for system = 1, 3 do
    Space.Describe(game.state, system)
    for _, object in Core.Query.Objects(game, system) do
      if object.kind == "asteroid" then
        local ore = assert(Ores.byId[object.variety], `{object.name} is made of '{object.variety}'`)
        t.eq(object.name, ore.name)
        counts[ore.id] = (counts[ore.id] or 0) + 1
        total += 1
      end
    end
  end
  t.ok(total > 100, `only {total} rocks in three systems`)
  t.near((counts["ore.ferrite"] or 0) / total, 0.6, 0.12)
  t.ok((counts["ore.titanite"] or 0) / total < 0.1)
  t.near(Ores.list[1].share + Ores.list[2].share + Ores.list[3].share + Ores.list[4].share, 1, 1e-12)
end)

suite:Case("a mining laser delivers a cycle's ore when the cycle ends", function(t)
  local game, ball, rock, laser = atRock(t, "ore.ferrite")
  local whole = Mining.Left(game.state, assert(Space.Object(game.state, rock)))
  order(t, game, { kind = "ActivateModule", actor = 0, item = laser.id, target = rock })
  local capacitor = ball.vitals.capacitor
  local mined, ticks = stepUntil(game, "Mined", 70)
  -- the order takes effect on the next tick, then a 60 s cycle
  t.eq(ticks, 61)
  -- 40 m3 of ferrite at 0.1 m3 a unit
  t.eq({ mined.ore, mined.units }, { "ore.ferrite", 400 } :: { any })
  t.eq(hold(game, "ore.ferrite"), 400)
  t.eq(Mining.Left(game.state, assert(Space.Object(game.state, rock))), whole - 400)
  t.ok(ball.vitals.capacitor < capacitor, "and it drew capacitor")
  -- and again a minute later
  local _, again = stepUntil(game, "Mined", 70)
  t.eq(again, 60)
  t.eq(hold(game, "ore.ferrite"), 800)
end)

suite:Case("a practised miner brings in 5% more a level after the first", function(t)
  local game, _, rock, laser = atRock(t, "ore.ferrite")
  game.state.skills.mining = 4
  order(t, game, { kind = "ActivateModule", actor = 0, item = laser.id, target = rock })
  local mined = stepUntil(game, "Mined", 70)
  t.eq(mined.units, 460)
end)

suite:Case("mining stops when the hold is full, and takes only what fits", function(t)
  local game, _, rock, laser = atRock(t, "ore.ferrite")
  -- 180 m3 hold: leave room for 25 m3, less than a cycle's 40.
  Items.Add(game.state, "ore.ferrite", 1550, game.state.player.ship, "cargo")
  order(t, game, { kind = "ActivateModule", actor = 0, item = laser.id, target = rock })
  local mined = stepUntil(game, "Mined", 70)
  t.eq(mined.units, 250, "the 25 m3 that fits")
  t.near(Items.CargoUsed(game.state, game.state.player.ship), 180, 1e-9)
  local stopped = stepUntil(game, "ModuleStopped", 70)
  t.eq(stopped.reason, "the hold is full")
end)

suite:Case("a rock runs out, drops off the overview, and grows back", function(t)
  local game, ball, rock, laser = atRock(t, "ore.ferrite")
  local object = assert(Space.Object(game.state, rock))
  -- Leave it one short cycle from empty.
  Mining.Take(game.state, object, Mining.Left(game.state, object) - 150)
  local since = game.state.tick
  order(t, game, { kind = "ActivateModule", actor = 0, item = laser.id, target = rock })
  local mined = stepUntil(game, "Mined", 70)
  t.eq(mined.units, 150, "only what was left")
  t.eq(Mining.Left(game.state, object), 0)
  t.eq(#ball.vitals.running, 0, "the laser stops")
  for _, entry in Core.Query.Overview(game) do
    t.ok(entry.id ~= rock, "a mined-out rock is still listed")
  end
  t.eq(refused(game, { kind = "ActivateModule", actor = 0, item = laser.id, target = rock }), "that asteroid is mined out")
  -- Six hours after mining began it is whole again.
  game.state.tick = since + Mining.REGROW - 2
  Core.Step(game)
  t.eq(Mining.Left(game.state, object), 0)
  Core.Step(game)
  Core.Step(game)
  t.eq(Mining.Left(game.state, object), Ores.RockUnits(object.radius))
  t.eq(#game.state.rockIds, 0)
end)

suite:Case("a mining laser needs a locked rock in range", function(t)
  local game, _, rock, laser = atRock(t, "ore.ferrite")
  t.eq(refused(game, { kind = "ActivateModule", actor = 0, item = laser.id }), "no locked target")
  -- a rock that is locked but too far
  local far: number? = nil
  for _, entry in Core.Query.Overview(game) do
    if entry.kind == "asteroid" and entry.distance > 12000 and entry.distance < 20000 then
      far = entry.id
      break
    end
  end
  order(t, game, { kind = "LockTarget", actor = 0, target = assert(far, "no rock 12 to 20 km away") })
  stepUntil(game, "LockCompleted", 30)
  t.eq(refused(game, { kind = "ActivateModule", actor = 0, item = laser.id, target = far }), "out of mining range")
  -- flying out of range of a rock being mined stops the laser
  order(t, game, { kind = "ActivateModule", actor = 0, item = laser.id, target = rock })
  Core.Step(game)
  order(t, game, { kind = "Approach", actor = 0, target = far, range = 500 })
  local stopped = stepUntil(game, "ModuleStopped", 200)
  t.eq(stopped.reason, "out of mining range")
end)

suite:Case("refining turns ore into minerals, a hundred units at a time, at half yield", function(t)
  -- 250 iron and 30 silicon per hundred ferrite at perfect yield
  t.eq({ Industry.RefineOutput("ore.ferrite", 1234) }, { 1200,
    { { mineral = "mineral.iron", amount = 1500 }, { mineral = "mineral.silicon", amount = 180 } } } :: { any })
  t.eq({ Industry.RefineOutput("ore.titanite", 100) }, { 100,
    { { mineral = "mineral.titanium", amount = 45 }, { mineral = "mineral.copper", amount = 30 } } } :: { any })

  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local home = game.state.player.home
  local ore = Items.Add(game.state, "ore.ferrite", 1234, home, "hangar")
  local small = Items.Add(game.state, "ore.cuprite", 99, home, "hangar")
  t.eq(refused(game, { kind = "Reprocess", actor = 0, item = small.id }), "refining takes at least 100 units")
  local ammo = Items.In(game.state, home, "hangar")[1]
  t.eq(refused(game, { kind = "Reprocess", actor = 0, item = ammo.id }), "that is not ore")
  order(t, game, { kind = "Reprocess", actor = 0, item = ore.id })
  Core.Step(game)
  local have: { [string]: number } = {}
  for _, item in Items.In(game.state, home, "hangar") do
    have[item.type] = item.quantity
  end
  t.eq({ have["ore.ferrite"], have["mineral.iron"], have["mineral.silicon"] }, { 34, 1500, 180 })
end)

suite:Case("ore is priced at about what it refines to", function(t)
  for _, ore in Ores.list do
    local worth = 0
    local _, minerals = Industry.RefineOutput(ore.id, 100)
    for _, m in minerals do
      worth += m.amount * Ores.mineralById[m.mineral].basePrice
    end
    local ratio = worth / (100 * ore.basePrice)
    t.ok(ratio > 0.9 and ratio < 1.15, `{ore.name}: refining returns {ratio} of the ore's price`)
  end
end)

return suite
