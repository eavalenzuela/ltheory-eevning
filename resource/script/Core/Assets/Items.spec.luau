--!strict
local Core = require("@lt/Core/Api")
local Items = require("@lt/Core/Assets/Items")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Items")

-- A new game whose pilot has trained what the starter kit needs.
local function newGame(): Core.Game
  local game = Core.New({ galaxySeed = 1, historySeed = 1 })
  for _, skill in { "propulsion", "lasers", "repair.systems" } do
    game.state.skills[skill] = 1
  end
  return game
end

-- The first stack of a type in the player's home hangar.
local function inHangar(game: Core.Game, type: string): State.Item
  for _, item in Items.In(game.state, game.state.player.home, "hangar") do
    if item.type == type then
      return item
    end
  end
  error(`no {type} in the hangar`, 2)
end

local function hangarCount(game: Core.Game, type: string): number
  for _, item in Items.In(game.state, game.state.player.home, "hangar") do
    if item.type == type then
      return item.quantity
    end
  end
  return 0
end

-- Give an order and take the tick that carries it out.
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

suite:Case("a new game has a fitted, loaded ship and a kit in the hangar", function(t)
  local game = newGame()
  local ship = game.state.player.ship
  local fitted = Items.Fitted(game.state, ship)
  t.eq(#fitted, 2)
  for slot, item in fitted do
    t.eq({ item.type, item.place, item.slot, item.charge, item.rounds } :: { any },
      { "autocannon.small", "high", slot, "ammo.emp", 120 } :: { any })
  end
  t.eq(hangarCount(game, "ammo.emp"), 600)
  t.eq(game.state.wallet, 5000)
  t.eq(#Core.TakeEvents(game), 0, "setting up is not news")
end)

suite:Case("fitting takes one from the stack and fills the next free slot", function(t)
  local game = newGame()
  local ship = game.state.player.ship
  order(t, game, { kind = "Fit", actor = 0, item = inHangar(game, "shield.extender.small").id })
  order(t, game, { kind = "Fit", actor = 0, item = inHangar(game, "afterburner.1mn").id })
  local mids = Items.In(game.state, ship, "mid")
  t.eq({ mids[1].type, mids[1].slot, mids[2].type, mids[2].slot } :: { any },
    { "shield.extender.small", 1, "afterburner.1mn", 2 } :: { any })
  t.eq(hangarCount(game, "shield.extender.small"), 0)
  t.eq(Items.ShipStats(game.state, ship).shield, 350 + 280, "and the ship has the extender's shield")
end)

suite:Case("a fit that breaks the rules is refused, with the reason", function(t)
  local game = newGame()
  -- both high slots hold autocannons already
  t.eq(refused(game, { kind = "Fit", actor = 0, item = inHangar(game, "laser.pulse.small").id }), "no free high slot")
  t.eq(refused(game, { kind = "Fit", actor = 0, item = inHangar(game, "ammo.emp").id }), "not a module")
  t.eq(refused(game, { kind = "Fit", actor = 0, item = 12345 }), "no such item")
  local fitted = Items.Fitted(game.state, game.state.player.ship)[1]
  t.eq(refused(game, { kind = "Fit", actor = 0, item = fitted.id }), "already fitted")
  t.eq(refused(game, { kind = "MoveItems", actor = 0, item = fitted.id, to = "hangar" }), "unfit it first")
end)

suite:Case("unfitting returns the module and what was loaded in it", function(t)
  local game = newGame()
  local ship = game.state.player.ship
  local cannon = Items.Fitted(game.state, ship)[1]
  order(t, game, { kind = "Unfit", actor = 0, item = cannon.id })
  t.eq(#Items.Fitted(game.state, ship), 1)
  t.eq(hangarCount(game, "autocannon.small"), 1)
  t.eq(hangarCount(game, "ammo.emp"), 720, "its 120 rounds are back with the other 600")
  -- the freed slot is the one a new module takes
  order(t, game, { kind = "Fit", actor = 0, item = inHangar(game, "laser.pulse.small").id })
  local highs = Items.In(game.state, ship, "high")
  table.sort(highs, function(a: State.Item, b: State.Item): boolean
    return a.slot < b.slot
  end)
  t.eq({ highs[1].type, highs[1].slot, highs[2].type, highs[2].slot } :: { any },
    { "laser.pulse.small", 1, "autocannon.small", 2 } :: { any })
end)

suite:Case("loading swaps the charge; a crystal is one item and is not counted in rounds", function(t)
  local game = newGame()
  local ship = game.state.player.ship
  local cannon = Items.Fitted(game.state, ship)[1]
  order(t, game, { kind = "LoadCharge", actor = 0, item = cannon.id, other = inHangar(game, "ammo.fusion").id })
  t.eq({ cannon.charge, cannon.rounds } :: { any }, { "ammo.fusion", 120 } :: { any })
  t.eq(hangarCount(game, "ammo.fusion"), 280)
  t.eq(hangarCount(game, "ammo.emp"), 720, "the EMP it held went back")

  t.eq(refused(game, { kind = "LoadCharge", actor = 0, item = cannon.id, other = inHangar(game, "crystal.multifrequency").id }),
    "that does not fit this weapon")
  order(t, game, { kind = "Unfit", actor = 0, item = cannon.id })
  order(t, game, { kind = "Fit", actor = 0, item = inHangar(game, "laser.pulse.small").id })
  local laser = Items.In(game.state, ship, "high")[2]
  if laser.type ~= "laser.pulse.small" then
    laser = Items.In(game.state, ship, "high")[1]
  end
  order(t, game, { kind = "LoadCharge", actor = 0, item = laser.id, other = inHangar(game, "crystal.multifrequency").id })
  t.eq({ laser.charge, laser.rounds } :: { any }, { "crystal.multifrequency", 0 } :: { any })
  t.eq(hangarCount(game, "crystal.multifrequency"), 0)
  order(t, game, { kind = "Unfit", actor = 0, item = laser.id })
  t.eq(hangarCount(game, "crystal.multifrequency"), 1, "and comes back whole")
end)

suite:Case("the hold has a size", function(t)
  local game = newGame()
  local ship = game.state.player.ship
  -- 600 rounds at 0.0025 m3 is 1.5 m3: fits easily in 180
  order(t, game, { kind = "MoveItems", actor = 0, item = inHangar(game, "ammo.emp").id, quantity = 400, to = "cargo" })
  t.eq(hangarCount(game, "ammo.emp"), 200)
  t.near(Items.CargoUsed(game.state, ship), 1, 1e-9)
  local hold = Items.In(game.state, ship, "cargo")[1]
  t.eq(refused(game, { kind = "MoveItems", actor = 0, item = hold.id, to = "cargo" }), "already in the hold")
  t.eq(refused(game, { kind = "MoveItems", actor = 0, item = hold.id, quantity = 401, to = "hangar" }), "no such quantity")
  -- A stack too big for the hold: 40 extenders at 5 m3 is 200 m3.
  local bulky = Items.Add(game.state, "shield.extender.small", 40, game.state.player.home, "hangar")
  t.eq(refused(game, { kind = "MoveItems", actor = 0, item = bulky.id, to = "cargo" }), "not enough room in the hold")
  t.eq(refused(game, { kind = "MoveItems", actor = 0, item = bulky.id, quantity = 35, to = "cargo" }), "(accepted)")
  order(t, game, { kind = "MoveItems", actor = 0, item = hold.id, quantity = 400, to = "hangar" })
  t.eq(hangarCount(game, "ammo.emp"), 600, "moved back, the stacks merge")
  t.eq(#Items.In(game.state, ship, "cargo"), 0)
end)

suite:Case("fitting is done docked", function(t)
  local game = newGame()
  local extender = inHangar(game, "shield.extender.small")
  Core.Submit(game, { kind = "Undock", actor = game.state.player.ship })
  Core.Step(game)
  t.eq(refused(game, { kind = "Fit", actor = 0, item = extender.id }), "not docked")
  local cannon = Items.Fitted(game.state, game.state.player.ship)[1]
  t.eq(refused(game, { kind = "Unfit", actor = 0, item = cannon.id }), "not docked")
end)

suite:Case("a fit changes how the ship flies once it undocks", function(t)
  local game = newGame()
  local ship = game.state.player.ship
  local plate = Items.Add(game.state, "nanofiber", 1, game.state.player.home, "hangar")
  order(t, game, { kind = "Fit", actor = 0, item = plate.id })
  Core.Submit(game, { kind = "Undock", actor = ship })
  Core.Step(game)
  local ball = assert(Core.Query.Ball(game, ship))
  t.near(ball.maxVelocity, 360 * 1.0775, 1e-9)
  t.near(ball.tau, 3.2 * 0.87 * 1.1, 1e-9)
end)

return suite
