--!strict
-- What a pilot puts out into space and picks up again (Tactical/Deploy,
-- Data/Deployables).

local Core = require("@lt/Core/Api")
local Deployables = require("@lt/Core/Data/Deployables")
local Items = require("@lt/Core/Assets/Items")
local Jumping = require("@lt/Core/Tactical/Jumping")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")
local Types = require("@lt/Core/Data/Types")

local suite = Test.Suite("Deploy")

-- A pilot in space, well clear of the station they left.
local function out(t: Test.Context): (Core.Game, State.Ball)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  t.ok(Core.Submit(game, { kind = "Undock", actor = state.player.ship }))
  Core.Step(game)
  local me = state.balls[state.player.ship]
  me.x += 40000
  Space.AssignGrid(state, me)
  t.ok(Core.Submit(game, { kind = "Stop", actor = me.id }))
  Core.Step(game)
  return game, me
end

local function order(t: Test.Context, game: Core.Game, command: State.Command)
  local ok, why = Core.Submit(game, command)
  t.ok(ok, why)
  Core.Step(game)
end

local function put(game: Core.Game, type: string): State.Item
  return Items.Add(game.state, type, 1, game.state.player.ship, "cargo")
end

suite:Case("every deployable is an item to be bought, with a blueprint", function(t)
  for _, each in Deployables.list do
    local info = Types.Info(each.id)
    t.eq({ info.name, info.category } :: { any }, { each.name, "structure" } :: { any }, each.id)
  end
end)

suite:Case("a Field Depot holds what is put in it, a ship by it is refitted there, and it is picked up again once empty", function(t)
  local game, me = out(t)
  local state = game.state
  order(t, game, { kind = "Deploy", actor = me.id, item = put(game, "deploy.depot").id })
  local depot: State.Wreck? = nil
  for _, id in state.wreckIds do
    if state.wrecks[id].deploy == "deploy.depot" then
      depot = state.wrecks[id]
    end
  end
  local there = assert(depot, "no depot out")
  -- What is jettisoned into it goes in, as far as its hold lets it.
  order(t, game, { kind = "Jettison", actor = me.id, item = Items.Add(state, "mineral.iron", 100, me.id, "cargo").id, target = there.id })
  t.eq(#Items.In(state, there.id, nil), 1)
  -- A module taken off the ship by it goes into it, and goes back on from it.
  local fitted = Items.Fitted(state, me.id)[1]
  local type = fitted.type
  order(t, game, { kind = "Unfit", actor = me.id, item = fitted.id })
  local stored: State.Item? = nil
  for _, item in Items.In(state, there.id, nil) do
    if item.type == type then
      stored = item
    end
  end
  order(t, game, { kind = "Fit", actor = me.id, item = assert(stored, "the module did not go into the depot").id })
  local back = false
  for _, item in Items.Fitted(state, me.id) do
    back = back or item.type == type
  end
  t.ok(back, "the module did not go back on")
  -- Not picked up with something in it; emptied, it is.
  t.eq((Core.Validate(game, { kind = "Scoop", actor = me.id, target = there.id })), false)
  order(t, game, { kind = "Loot", actor = me.id, target = there.id })
  order(t, game, { kind = "Scoop", actor = me.id, target = there.id })
  t.eq(state.wrecks[there.id], nil)
  local again = 0
  for _, item in Items.In(state, me.id, "cargo") do
    again += if item.type == "deploy.depot" then item.quantity else 0
  end
  t.eq(again, 1)
end)

suite:Case("a Salvage Tractor Post draws in a wreck in its reach and takes what is in it; it lasts two days", function(t)
  local game, me = out(t)
  local state = game.state
  order(t, game, { kind = "Deploy", actor = me.id, item = put(game, "deploy.tractor").id })
  local post = assert(state.wrecks[state.wreckIds[#state.wreckIds]])
  t.eq(post.deploy, "deploy.tractor")
  local wreck: State.Wreck = { id = State.NewId(state), kind = "wreck", name = "Some Wreck", system = post.system, grid = post.grid,
    x = post.x + 20000, y = post.y, z = post.z, radius = 40, hull = "", expires = state.tick + 7200, salvaged = false, locked = false,
    lock = "" }
  state.wrecks[wreck.id] = wreck
  table.insert(state.wreckIds, wreck.id)
  Items.Add(state, "mineral.iron", 50, wreck.id, "cargo")
  for _ = 1, 40 do
    Core.Step(game)
  end
  t.eq(#Items.In(state, wreck.id, nil), 0)
  t.eq(Items.In(state, post.id, nil)[1].quantity, 50)
  -- (at its end, a plain container with what is in it)
  state.tick = assert(post.ends)
  Core.Step(game)
  t.ok(post.deploy == nil or state.wrecks[post.id].deploy == nil, "it lasted past its life")
  t.eq(state.wrecks[post.id].name, "Cargo Container")
end)

suite:Case("a Jump Beacon Buoy is a lit beacon for the pilot's jump drives for an hour; an interdiction buoy is not for where order is kept", function(t)
  local game, me = out(t)
  local state = game.state
  order(t, game, { kind = "Deploy", actor = me.id, item = put(game, "deploy.beacon").id })
  local lit = false
  for _, beacon in Jumping.Beacons(state, state.player.ship) do
    lit = lit or beacon.kind == "buoy"
  end
  t.ok(lit, "no beacon lit")
  -- (the pilot starts where order is kept)
  local ok, why = Core.Validate(game, { kind = "Deploy", actor = me.id, item = put(game, "deploy.bubble.small").id })
  t.eq({ ok, why } :: { any }, { false, "not where order is kept" } :: { any })
end)

return suite
