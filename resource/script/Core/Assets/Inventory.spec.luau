--!strict
-- Moving things about, as the inventory window does it: between the
-- holds of a ship in space, to and from another ship of the pilot's
-- that lies in the same station, out of a wreck a thing at a time, and
-- over the side into a container (Assets/Items, Tactical/Aftermath).

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Core = require("@lt/Core/Api")
local Items = require("@lt/Core/Assets/Items")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Inventory")

local function begun(): Core.Game
  return Core.New({ galaxySeed = 1, historySeed = 1, systems = 40, peaceful = true })
end

local function refused(game: Core.Game, command: State.Command): string?
  command.actor = game.state.player.ship
  local ok, why = Core.Validate(game, command)
  return if ok then nil else why
end

local function order(game: Core.Game, command: State.Command)
  command.actor = game.state.player.ship
  assert(Core.Submit(game, command))
  Core.Step(game)
end

local function count(state: State.State, holder: number, place: string?, type: string): number
  local total = 0
  for _, item in Items.In(state, holder, place) do
    total += if item.type == type then item.quantity else 0
  end
  return total
end

local function keys(game: Core.Game): { string }
  local found: { string } = {}
  for _, place in Core.Query.Places(game) do
    table.insert(found, `{place.kind}:{place.indent}`)
  end
  return found
end

suite:Case("docked, what is in reach is the ship's holds, the hangar, and the holds of the pilot's other ships there", function(t)
  local game = begun()
  local state = game.state
  local station = state.player.home
  -- (the ship a new pilot has carries drones: its bay is a place under its hold)
  t.eq(keys(game), { "cargo:0", "dronebay:1", "hangar:0" })
  local mule = Space.NewShip(state, "industrial.hauler", "Mule", "player", station)
  t.eq(keys(game), { "cargo:0", "dronebay:1", "hangar:0", "cargo:1", "dronebay:2" })
  local places = Core.Query.Places(game)
  t.eq({ places[4].holder, places[4].place, places[4].name } :: { any }, { mule.id, "cargo", "Mule (hold)" } :: { any })
  t.ok(places[1].capacity > 0 and places[3].capacity == 0)
  -- From the hangar into the other ship's hold, and from there into this ship's.
  local ore = Items.Add(state, "ore.ferrite", 100, station, "hangar")
  order(game, { kind = "MoveItems", actor = 0, item = ore.id, to = "cargo", target = mule.id, quantity = 60 })
  t.eq({ count(state, mule.id, "cargo", "ore.ferrite"), count(state, station, "hangar", "ore.ferrite") }, { 60, 40 })
  local aboard = Items.In(state, mule.id, "cargo")[1]
  t.eq(refused(game, { kind = "MoveItems", actor = 0, item = aboard.id, to = "cargo", target = mule.id }), "already in the hold")
  order(game, { kind = "MoveItems", actor = 0, item = aboard.id, to = "cargo", quantity = 10 })
  t.eq({ count(state, mule.id, "cargo", "ore.ferrite"), count(state, state.player.ship, "cargo", "ore.ferrite") }, { 50, 10 })
  -- (not into a ship that is somewhere else, or is not the pilot's)
  local far = Space.NewShip(state, "industrial.hauler", "Far", "player", station + 1)
  local theirs = Space.NewShip(state, "industrial.hauler", "Theirs", "civilian", station)
  for _, other in { far, theirs } do
    t.eq(refused(game, { kind = "MoveItems", actor = 0, item = aboard.id, to = "cargo", target = other.id }),
      "no ship of yours lies here by that name")
  end
  -- (and a hold is as big as it is)
  local much = Items.Add(state, "ore.ferrite", 10000000, station, "hangar")
  t.eq(refused(game, { kind = "MoveItems", actor = 0, item = much.id, to = "cargo", target = mule.id }), "not enough room in the hold")
end)

suite:Case("in space a thing goes over the side into a container, and comes out of one, or a wreck, a thing at a time", function(t)
  local game = begun()
  local state = game.state
  local me = state.player.ship
  Items.Add(state, "ore.ferrite", 50, me, "cargo")
  Items.Add(state, "scrap.metal", 4, me, "cargo")
  local ore = Items.In(state, me, "cargo")[1]
  t.eq(refused(game, { kind = "Jettison", actor = 0, item = ore.id }), "docked")
  order(game, { kind = "Undock", actor = 0 })
  -- (aboard, in space: there is no hangar to move a thing to)
  t.eq(refused(game, { kind = "MoveItems", actor = 0, item = ore.id, to = "hangar" }), "not docked")
  t.eq(keys(game), { "cargo:0", "dronebay:1" })
  -- Over the side: a container is put out for it, and it is in reach.
  order(game, { kind = "Jettison", actor = 0, item = ore.id, quantity = 30 })
  t.eq(#state.wreckIds, 1)
  local can = state.wrecks[state.wreckIds[1]]
  t.eq({ can.can, can.name, can.locked, can.salvaged } :: { any }, { true, "Cargo Container", false, true } :: { any })
  t.eq({ count(state, can.id, nil, "ore.ferrite"), count(state, me, "cargo", "ore.ferrite") }, { 30, 20 })
  t.eq(keys(game), { "cargo:0", "dronebay:1", "can:0" })
  -- The next thing goes into the same one.
  local scrap = Items.In(state, me, "cargo")[2]
  order(game, { kind = "Jettison", actor = 0, item = scrap.id })
  t.eq({ #state.wreckIds, count(state, can.id, nil, "scrap.metal") }, { 1, 4 })
  -- One thing out of it, and so many: the rest stays.
  local inCan = Items.In(state, can.id, nil)[1]
  t.eq(refused(game, { kind = "Loot", actor = 0, target = can.id, item = inCan.id, quantity = 31 }), "no such quantity")
  order(game, { kind = "Loot", actor = 0, target = can.id, item = inCan.id, quantity = 5 })
  t.eq({ count(state, can.id, nil, "ore.ferrite"), count(state, me, "cargo", "ore.ferrite"), count(state, can.id, nil, "scrap.metal") },
    { 25, 25, 4 })
  -- And all of it: the container, empty, is gone.
  order(game, { kind = "Loot", actor = 0, target = can.id })
  t.eq({ #state.wreckIds, count(state, me, "cargo", "ore.ferrite"), count(state, me, "cargo", "scrap.metal") }, { 0, 50, 4 })
  -- A wreck is in reach while it is near, and gives up one thing at a time too.
  local ball = state.balls[me]
  local pirate = Pirates.Spawn(state, Pirates.kindById["raider"], ball.system, ball.x + 800, ball.y, ball.z, ball.grid)
  Aftermath.Destroy(state, pirate.id, me, game.events)
  local wreck = state.wrecks[state.wreckIds[1]]
  t.eq(keys(game), { "cargo:0", "dronebay:1", "wreck:0" })
  local tags = count(state, wreck.id, nil, "tag.pirate")
  t.ok(tags >= 1)
  local tag: State.Item? = nil
  for _, item in Items.In(state, wreck.id, nil) do
    tag = if item.type == "tag.pirate" then item else tag
  end
  order(game, { kind = "Loot", actor = 0, target = wreck.id, item = (tag :: State.Item).id, quantity = 1 })
  t.eq({ count(state, me, "cargo", "tag.pirate"), count(state, wreck.id, nil, "tag.pirate") }, { 1, tags - 1 })
  -- (nothing goes into a wreck: it is no container)
  t.eq(refused(game, { kind = "Jettison", actor = 0, item = Items.In(state, me, "cargo")[1].id, target = wreck.id }), "not a container")
  -- (a save with a container in it is the same game loaded)
  order(game, { kind = "Jettison", actor = 0, item = Items.In(state, me, "cargo")[1].id })
  local data, length = Core.Save(game)
  t.eq(Core.Hash(Core.Load(data, length)), Core.Hash(game))
end)

return suite
