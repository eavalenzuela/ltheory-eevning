--!strict
-- Boosters (Data/Boosters, Character/Boosters).

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Attributes = require("@lt/Core/Attributes")
local Blueprints = require("@lt/Core/Data/Blueprints")
local Boosters = require("@lt/Core/Data/Boosters")
local Boosting = require("@lt/Core/Character/Boosters")
local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Facts = require("@lt/Core/Data/Facts")
local Items = require("@lt/Core/Assets/Items")
local Ores = require("@lt/Core/Data/Ores")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")
local Types = require("@lt/Core/Data/Types")

local suite = Test.Suite("Boosters")

local function submit(game: Core.Game, command: State.Command): (boolean, string?)
  command.actor = game.state.player.ship
  local ok, why = Core.Submit(game, command)
  Core.Step(game)
  return ok, why
end

local function refused(game: Core.Game, command: State.Command): string?
  command.actor = game.state.player.ship
  local ok, why = Core.Validate(game, command)
  return if ok then "(accepted)" else why
end

-- A weapon of the pilot's ship as it is now, with whatever is at work on the pilot.
local function weapon(game: Core.Game, type: string): { [string]: any }
  local state = game.state
  return Attributes.Weapon(Items.Fit(state, state.player.ship, nil), type, Items.Levels(state, state.player.ship)) :: any
end

local function give(game: Core.Game, type: string, quantity: number?): State.Item
  return Items.Add(game.state, type, quantity or 1, game.state.player.home, "hangar")
end

suite:Case("there are two boosters of each of three kinds, each made of its kind's gas and of nothing a station sells", function(t)
  local kinds = { 0, 0, 0 }
  local gases: { [number]: string } = {}
  for _, booster in Boosters.list do
    kinds[booster.kind] += 1
    -- (the boosters of a kind are of the one gas, and each kind's is its own)
    t.eq(gases[booster.kind] or booster.gas, booster.gas)
    gases[booster.kind] = booster.gas
    t.ok(Ores.gasById[booster.gas] ~= nil, booster.gas)
    -- Something given, and something taken.
    local better, worse = 0, 0
    for _, modifier in booster.passive do
      t.eq(modifier.op, "mul")
      -- (a time is better shorter, and inertia better less; everything else better more)
      local time = modifier.attribute == "shieldRecharge" or modifier.attribute == "capacitorRecharge" or modifier.attribute == "inertia"
      local good = if time then modifier.value < 1 else modifier.value > 1
      better += if good then 1 else 0
      worse += if good then 0 else 1
    end
    t.ok(better >= 1 and worse == 1, `{booster.id} gives {better} and takes {worse}`)
    -- An item nobody sells, with a sheet, and drawings that anybody does.
    local info = Types.Info(booster.id)
    t.eq({ info.category, info.scarce, info.basePrice } :: { any }, { "goods", true, Boosters.PRICE } :: { any })
    t.eq(assert(Facts.Of(booster.id)).kind, "Booster")
    local blueprint = assert(Blueprints.byProduct[booster.id])
    t.eq({ blueprint.materials[1].type, blueprint.materials[1].quantity, blueprint.invented } :: { any },
      { booster.gas, Boosters.GAS, nil } :: { any })
    t.eq(Types.Info(blueprint.id).scarce, nil)
  end
  t.eq(kinds, { 2, 2, 2 })
  t.ok(gases[1] ~= gases[2] and gases[2] ~= gases[3] and gases[1] ~= gases[3])
  for _, gas in Ores.gases do
    local info = Types.Info(gas.id)
    t.eq({ info.category, info.scarce } :: { any }, { "goods", true } :: { any })
    t.eq(assert(Facts.Of(gas.id)).kind, "Gas")
  end
end)

suite:Case("a booster is taken from the hold or the hangar, is used up, and makes the ship better at one thing and worse at another", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local ship = state.player.ship
  local before = Items.ShipStats(state, ship)
  local gun = Items.Fitted(state, ship)[1]
  local was = weapon(game, gun.type)
  local skin = give(game, "booster.thickskin", 2)
  t.eq(refused(game, { kind = "TakeBooster", actor = 0, item = give(game, "datacore").id }), "that is not a booster")
  t.eq(refused(game, { kind = "TakeBooster", actor = 0, item = 999999 }), "that is not in the hold, nor in the hangar here")
  t.ok((submit(game, { kind = "TakeBooster", actor = 0, item = skin.id })))
  t.eq({ #state.boosters, state.boosters[1].type, skin.quantity } :: { any }, { 1, "booster.thickskin", 1 } :: { any })
  local after = Items.ShipStats(state, ship)
  t.near(after.armor, before.armor * 1.15, 1e-6)
  t.near(after.maxVelocity, before.maxVelocity * 0.92, 1e-6)
  t.eq(after.shield, before.shield)
  -- One of a kind at a time; one of another kind beside it.
  t.eq(refused(game, { kind = "TakeBooster", actor = 0, item = skin.id }), "Thickskin is still at work: one of a kind at a time")
  t.eq(refused(game, { kind = "TakeBooster", actor = 0, item = give(game, "booster.halo").id }),
    "Thickskin is still at work: one of a kind at a time")
  t.ok((submit(game, { kind = "TakeBooster", actor = 0, item = give(game, "booster.redline").id })))
  local now = weapon(game, gun.type)
  t.near(now.damageMultiplier, was.damageMultiplier * 1.10, 1e-6)
  t.near(Items.ShipStats(state, ship).shield, before.shield * 0.90, 1e-6)
  -- The pilot sees which are at work and for how long, and which are to hand.
  local working, hand = Core.Query.Boosters(game)
  t.eq({ #working, working[1].booster.id, working[2].booster.id } :: { any }, { 2, "booster.thickskin", "booster.redline" } :: { any })
  t.ok(working[1].left > Boosters.SECONDS - 5 and working[1].left <= Boosters.SECONDS)
  t.eq(#hand, 2)
  for _, row in hand do
    t.ok(row.refused ~= nil, "a booster of a kind that is at work should say why it cannot be taken")
  end

  -- In space too, out of the hold: and the ship in space is what it has become at once.
  local third = Items.Add(state, "booster.slipstream", 1, ship, "cargo")
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  local ball = state.balls[ship]
  local speed, armor = ball.maxVelocity, ball.vitals.armorMax
  t.ok((submit(game, { kind = "TakeBooster", actor = 0, item = third.id })))
  t.near(ball.maxVelocity, speed * 1.15, 1e-6)
  t.near(ball.vitals.armorMax, armor * 0.92, 1e-6)
  t.ok(ball.vitals.armor <= ball.vitals.armorMax)
  -- (and what is in the hangar of a station is not to hand out here)
  t.eq(refused(game, { kind = "TakeBooster", actor = 0, item = skin.id }), "that is not in the hold, nor in the hangar here")
end)

suite:Case("a booster wears off in half an hour, is in the save, and is gone with the pilot's capsule", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local ship = state.player.ship
  local before = Items.ShipStats(state, ship)
  t.ok((submit(game, { kind = "TakeBooster", actor = 0, item = give(game, "booster.halo").id })))
  t.near(Items.ShipStats(state, ship).shield, before.shield * 1.15, 1e-6)
  -- In the save, and a save from before has none.
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq({ Core.Hash(loaded), loaded.state.boosters[1].type } :: { any }, { Core.Hash(game), "booster.halo" } :: { any })
  local file = Codec.Decode(data, length)
  file.saveVersion = 45
  file.state.boosters = nil
  local old, oldLength = Codec.Encode(file)
  t.eq(Core.Load(old, oldLength).state.boosters, {})
  -- It wears off, and says so.
  local spent = false
  for _ = 1, Boosting.TICKS + 2 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      spent = spent or (event.kind == "BoosterSpent" and event.booster == "booster.halo")
    end
    t.ok(spent == (#state.boosters == 0))
  end
  t.ok(spent)
  t.near(Items.ShipStats(state, ship).shield, before.shield, 1e-6)
  -- And another can be taken then.
  t.ok((submit(game, { kind = "TakeBooster", actor = 0, item = give(game, "booster.thickskin").id })))
  -- The ship is lost: it is still at work. The capsule is lost: it is not.
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  Aftermath.Destroy(state, state.player.ship, 0, game.events)
  t.eq(#state.boosters, 1)
  Aftermath.Destroy(state, state.player.ship, 0, game.events)
  t.eq(state.boosters, {})
end)

return suite
