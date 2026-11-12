--!strict
local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Items = require("@lt/Core/Assets/Items")
local Space = require("@lt/Core/Tactical/Space")
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
  -- both turret hardpoints hold autocannons already (the third high slot is for what needs none)
  t.eq(refused(game, { kind = "Fit", actor = 0, item = inHangar(game, "laser.pulse.small").id }), "no free turret hardpoint")
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

suite:Case("a tech 2 charge goes into a tech 2 weapon and no other, and hits harder", function(t)
  local game = newGame()
  local state = game.state
  local ship = state.player.ship
  local home = state.player.home
  local cannon = Items.Fitted(state, ship)[1]
  local better = Items.Add(state, "ammo.fusion.ii", 500, home, "hangar")
  t.eq(refused(game, { kind = "LoadCharge", actor = 0, item = cannon.id, other = better.id }), "a tech 2 charge wants a tech 2 weapon")
  -- A tech 2 autocannon in its place takes it, and plain rounds too.
  order(t, game, { kind = "Unfit", actor = 0, item = cannon.id })
  state.skills["projectiles"] = 5
  local gun = Items.Add(state, "autocannon.small.ii", 1, home, "hangar")
  order(t, game, { kind = "Fit", actor = 0, item = gun.id })
  local fitted: State.Item? = nil
  for _, item in Items.Fitted(state, ship) do
    fitted = if item.type == "autocannon.small.ii" then item else fitted
  end
  local weapon = assert(fitted, "the tech 2 autocannon is not fitted")
  order(t, game, { kind = "LoadCharge", actor = 0, item = weapon.id, other = inHangar(game, "ammo.fusion").id })
  local plain = Items.Offence(state, ship).volley
  order(t, game, { kind = "LoadCharge", actor = 0, item = weapon.id, other = inHangar(game, "ammo.fusion.ii").id })
  t.eq({ weapon.charge, weapon.rounds } :: { any }, { "ammo.fusion.ii", 120 } :: { any })
  t.eq(hangarCount(game, "ammo.fusion.ii"), 380)
  -- (the other gun fires what it did: the difference is this one's)
  t.ok(Items.Offence(state, ship).volley > plain, "tech 2 rounds should hit harder")
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

suite:Case("a rig is fitted like a module, wants its skill, and is destroyed when it is taken out", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local ship = state.player.ship
  local home = state.player.home
  local rig = Items.Add(state, "rig.hull", 2, home, "hangar")
  local fit: State.Command = { kind = "Fit", actor = ship, item = rig.id }
  t.eq({ Core.Validate(game, fit) } :: { any }, { false, "needs Jury Rigging 1" } :: { any })
  state.skills["jury.rigging"] = 1
  local before = Core.Query.Stats(game, ship)
  t.ok(Core.Submit(game, fit))
  Core.Step(game)
  local fitted: State.Item? = nil
  for _, item in Core.Query.Fitted(game, ship) do
    if item.type == "rig.hull" then
      fitted = item
    end
  end
  local there = assert(fitted, "the rig was not fitted")
  t.eq({ there.place, there.slot } :: { any }, { "rig", 1 } :: { any })
  t.eq(rig.quantity, 1)
  local after = Core.Query.Stats(game, ship)
  t.near(after.hull, before.hull * 1.2, 1e-6)
  t.near(after.cargo, before.cargo * 0.9, 1e-6)
  -- (it takes none of the CPU or powergrid, and none of the other slots)
  t.eq({ Core.Query.FittingUse(game, ship) }, { Core.Query.FittingUse(game, ship) })
  -- Taken out, it is gone: the hangar has the one that was never fitted, and no more.
  t.ok(Core.Submit(game, { kind = "Unfit", actor = ship, item = there.id }))
  local destroyed = false
  Core.Step(game)
  for _, event in Core.TakeEvents(game) do
    destroyed = destroyed or (event.kind == "RigDestroyed" and event.type == "rig.hull")
  end
  t.ok(destroyed, "nothing said the rig was destroyed")
  local left = 0
  for _, item in Core.Query.Items(game, home, "hangar") do
    left += if item.type == "rig.hull" then item.quantity else 0
  end
  t.eq(left, 1)
  t.near(Core.Query.Stats(game, ship).hull, before.hull, 1e-6)
end)

suite:Case("a rig goes into a hull of its size and no other, and one in a bigger hull in an older save is that hull's size from then on", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local home = state.player.home
  state.skills["jury.rigging"] = 1
  -- The Courier is a frigate: a small rig goes in, a medium one does not, and says why.
  local medium = Items.Add(state, "rig.hull.medium", 1, home, "hangar")
  t.eq({ Core.Validate(game, { kind = "Fit", actor = state.player.ship, item = medium.id }) } :: { any },
    { false, "a medium rig does not go into this hull: it takes small ones" } :: { any })
  local small = Items.Add(state, "rig.hull", 1, home, "hangar")
  t.ok(Core.Submit(game, { kind = "Fit", actor = state.player.ship, item = small.id }))
  Core.Step(game)
  -- A cruiser of the pilot's, with a medium rig in it; and another, in the hangar, with a large one that is its own size.
  local cruiser = Space.NewShip(state, "cruiser.cuirass", "Cruiser", "player", home)
  local inCruiser = Items.Equip(state, cruiser.id, "rig.engine.medium", nil)
  local battleship = Space.NewShip(state, "battleship.bastion", "Battleship", "player", home)
  local inBattleship = Items.Equip(state, battleship.id, "rig.shield.large", nil)
  -- As a save from before rigs had sizes would have them: every one the rig there was, whatever it is in.
  local data, length = Core.Save(game)
  local file = Codec.Decode(data, length)
  file.saveVersion = 47
  file.state.items[inCruiser.id].type = "rig.engine"
  file.state.items[inBattleship.id].type = "rig.shield"
  file.state.items[medium.id].type = "rig.hull"
  local old, oldLength = Codec.Encode(file)
  local loaded = Core.Load(old, oldLength).state
  -- What is worked into a hull is that hull's size; what lies loose in a hangar is the small one it always was.
  t.eq({ loaded.items[inCruiser.id].type, loaded.items[inBattleship.id].type, loaded.items[medium.id].type } :: { any },
    { "rig.engine.medium", "rig.shield.large", "rig.hull" } :: { any })
  local frigates = 0
  for _, item in loaded.items do
    frigates += if item.place == "rig" and item.holder == loaded.player.ship and item.type == "rig.hull" then 1 else 0
  end
  t.eq(frigates, 1, "the frigate's small rig should be as it was")
end)

return suite
