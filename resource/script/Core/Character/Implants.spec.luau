--!strict
-- Implants (Data/Implants, Character/Implants).

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Attributes = require("@lt/Core/Attributes")
local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Facts = require("@lt/Core/Data/Facts")
local Implants = require("@lt/Core/Data/Implants")
local Items = require("@lt/Core/Assets/Items")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")
local Types = require("@lt/Core/Data/Types")

local suite = Test.Suite("Implants")

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

local function give(game: Core.Game, type: string): State.Item
  return Items.Add(game.state, type, 1, game.state.player.home, "hangar")
end

suite:Case("there are two implants for each of five places and four more for the fifth, each an item with a price and a sheet", function(t)
  local places: { number } = table.create(Implants.SLOTS, 0)
  for _, implant in Implants.list do
    t.ok(implant.slot >= 1 and implant.slot <= Implants.SLOTS and implant.slot % 1 == 0)
    places[implant.slot] += 1
    local info = Types.Info(implant.id)
    t.eq({ info.category, info.basePrice } :: { any }, { "implant", Implants.Price(implant) } :: { any })
    t.eq(#implant.passive, 1)
    local sheet = assert(Facts.Of(implant.id))
    t.eq(sheet.kind, "Implant")
  end
  t.eq(places, { 2, 2, 2, 2, 6 })
  t.ok(Implants.Price(Implants.byId["implant.scan"]) > Implants.Price(Implants.byId["implant.shield"]))
end)

suite:Case("an implant for a kind of weapon makes that kind do a twentieth more damage, and no other kind any", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  state.skills.cybernetics = 5
  local ship = state.player.ship
  local function damage(type: string): number
    return Attributes.Weapon(Items.Fit(state, ship, nil), type, Items.Levels(state, ship)).damageMultiplier
  end
  local families: { [string]: string } = {
    laser = "laser.pulse.small", projectile = "autocannon.small", hybrid = "blaster.small", missile = "launcher.light",
  }
  local before: { [string]: number } = {}
  for family, type in families do
    before[family] = damage(type)
  end
  -- One for each family, all for the fifth place: so one at a time.
  for _, family in { "laser", "projectile", "hybrid", "missile" } do
    local implant = Implants.byId["implant." .. family]
    t.eq({ implant.slot, implant.passive[1].on, implant.passive[1].family } :: { any }, { 5, "weapons", family } :: { any })
  end
  t.ok((submit(game, { kind = "PlugImplant", actor = 0, item = give(game, "implant.projectile").id })))
  t.eq(refused(game, { kind = "PlugImplant", actor = 0, item = give(game, "implant.laser").id }),
    "that place has an implant in it: it has to come out first")
  for family, type in families do
    t.near(damage(type), before[family] * (if family == "projectile" then 1.05 else 1), 1e-9, family)
  end
  -- (and the ship in the fitting window says so: its guns are autocannons)
  t.ok((submit(game, { kind = "UnplugImplant", actor = 0, what = "implant.projectile" })))
  t.near(damage("autocannon.small"), before.projectile, 1e-9)
end)

suite:Case("an implant is plugged in at a station, into its own place, by a pilot with the Cybernetics for it", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local shield = give(game, "implant.shield")
  t.eq(refused(game, { kind = "PlugImplant", actor = 0, item = shield.id }), "needs Cybernetics 1")
  state.skills.cybernetics = 1
  local rounds = Items.In(state, state.player.home, "hangar")[1]
  t.eq(refused(game, { kind = "PlugImplant", actor = 0, item = rounds.id }), "that is not an implant")
  local before = Core.Query.Stats(game, state.player.ship).shield
  t.ok((submit(game, { kind = "PlugImplant", actor = 0, item = shield.id })))
  t.eq({ state.implants, state.items[shield.id] } :: { any }, { { "implant.shield" }, nil } :: { any })
  -- It counts for the ship the pilot flies, from then on.
  t.near(Core.Query.Stats(game, state.player.ship).shield, before * 1.05, 1e-6)
  -- Its place is taken, and a later place wants more of the skill.
  local armor = give(game, "implant.armor")
  t.eq(refused(game, { kind = "PlugImplant", actor = 0, item = armor.id }), "that place has an implant in it: it has to come out first")
  local speed = give(game, "implant.velocity")
  t.eq(refused(game, { kind = "PlugImplant", actor = 0, item = speed.id }), "needs Cybernetics 3")
  state.skills.cybernetics = 3
  local fast = Core.Query.Stats(game, state.player.ship).maxVelocity
  t.ok((submit(game, { kind = "PlugImplant", actor = 0, item = speed.id })))
  t.near(Core.Query.Stats(game, state.player.ship).maxVelocity, fast * 1.04, 1e-6)
  local places, open = Core.Query.Implants(game)
  t.eq(#places, Implants.SLOTS)
  t.eq({ (places[1].implant :: any).id, places[2].implant, (places[3].implant :: any).id, places[5].implant, open } :: { any },
    { "implant.shield", nil, "implant.velocity", nil, 3 } :: { any })
  -- Out in space it is the ship's: the ball has the shield and the speed.
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  local me = state.balls[state.player.ship]
  t.near(me.vitals.shieldMax, before * 1.05, 1e-6)
  t.eq(refused(game, { kind = "UnplugImplant", actor = 0, what = "implant.shield" }), "not docked")
  -- A hired pilot's ship has none of it, nor a drone.
  local second = Space.NewShip(state, "frigate.courier", "Second", "player", state.player.home)
  t.eq(#Items.Fit(state, second.id, nil), 2, "a ship the pilot could fly themselves should have their implants")
  second.pilot = 99
  state.fleet[99] = { id = 99, name = "Somebody", skill = 1, wage = 1, paid = 0, ship = second.id, order = "stay", target = 0, post = 0, base = 0, hauled = 0, experience = 0,
    cargo = "", sell = false, earned = 0, ward = 0, alarm = false, stops = {}, leg = 0 }
  t.eq(#Items.Fit(state, second.id, nil), 0, "a hired pilot's ship should have none of the player's implants")
end)

suite:Case("an implant taken out is destroyed, and a pilot whose capsule is destroyed loses them all", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  state.skills.cybernetics = 5
  for _, type in { "implant.shield", "implant.capacitor", "implant.scan" } do
    t.ok((submit(game, { kind = "PlugImplant", actor = 0, item = give(game, type).id })))
  end
  t.eq(state.implants, { "implant.shield", "implant.capacitor", "implant.scan" })
  t.eq(refused(game, { kind = "UnplugImplant", actor = 0, what = "implant.armor" }), "no such implant is plugged in")
  t.ok((submit(game, { kind = "UnplugImplant", actor = 0, what = "implant.capacitor" })))
  t.eq(state.implants, { "implant.shield", "implant.scan" })
  local left = 0
  for _, item in Items.In(state, state.player.home, "hangar") do
    left += if Types.Info(item.type).category == "implant" then 1 else 0
  end
  t.eq(left, 0, "an implant taken out came back as an item")
  -- They are in the save.
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq({ Core.Hash(loaded), loaded.state.implants } :: { any }, { Core.Hash(game), { "implant.shield", "implant.scan" } } :: { any })
  local file = Codec.Decode(data, length)
  file.saveVersion = 28
  file.state.implants = nil
  local old, oldLength = Codec.Encode(file)
  t.eq(Core.Load(old, oldLength).state.implants, {})
  -- The ship is lost: they are still there. The capsule is lost: they are not.
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  Aftermath.Destroy(state, state.player.ship, 0, game.events)
  t.eq(#state.implants, 2)
  Core.TakeEvents(game)
  Aftermath.Destroy(state, state.player.ship, 0, game.events)
  t.eq(state.implants, {})
  local told = false
  for _, event in Core.TakeEvents(game) do
    told = told or (event.kind == "ImplantsLost" and event.count == 2)
  end
  t.ok(told, "nobody said the implants were lost")
end)

return suite
