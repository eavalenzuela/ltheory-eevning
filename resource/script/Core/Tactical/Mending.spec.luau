--!strict
-- Hulls that mend by themselves (the Nimia's: Data/Factions' 'mends',
-- Data/Ships' 'armorMend' and 'hullMend'; Tactical/Combat in space and
-- Tactical/Vitals in a hangar), what makes them mend faster
-- (Data/Modules, Data/Skills), and that such a hull has no shield.

local Attributes = require("@lt/Core/Attributes")
local Constants = require("@lt/Core/Data/Constants")
local Core = require("@lt/Core/Api")
local Factions = require("@lt/Core/Data/Factions")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")
local Types = require("@lt/Core/Data/Types")

local suite = Test.Suite("Mending")

local function steps(game: Core.Game, count: number)
  for _ = 1, count do
    Core.Step(game)
  end
end

-- The pilot in open space in a hull of a type, a long way from anything.
local function flying(type: string): (Core.Game, State.Ball)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local ship = Space.NewShip(state, type, "Test", "player", state.player.home)
  state.player.ship = ship.id
  assert(Core.Submit(game, { kind = "Undock", actor = ship.id }))
  Core.Step(game)
  local me = state.balls[ship.id]
  me.x += 5e7
  me.vx, me.vy, me.vz = 0, 0, 0
  Space.AssignGrid(state, me)
  assert(Core.Submit(game, { kind = "Stop", actor = ship.id }))
  Core.Step(game)
  return game, me
end

suite:Case("a hull of the Nimia's has no shield, and its armour and its hull come back by themselves, so much a second", function(t)
  local nimia = Factions.byId.nimia
  t.eq({ nimia.shield, nimia.mends } :: { any }, { 0, { armor = 0.004, hull = 0.002 } } :: { any })
  for _, hull in Ships.list do
    if hull.lineage == "nimia" then
      t.eq({ hull.shield, hull.armorMend, hull.hullMend } :: { any }, { 0, 0.004, 0.002 } :: { any }, hull.id)
    elseif hull.class ~= "drone" and hull.class ~= "capsule" then
      t.eq({ hull.armorMend, hull.hullMend } :: { any }, { nil, nil } :: { any }, hull.id)
      t.ok(hull.shield > 0, `{hull.id} has no shield`)
    end
  end
  local game, me = flying("frigate.oon")
  local v = me.vitals
  t.eq({ v.shield, v.shieldMax, v.armorMend, v.hullMend } :: { any }, { 0, 0, 0.004, 0.002 } :: { any })
  -- Half its armour and half its hull gone: each tick puts back its share, evenly, until it is whole.
  v.armor, v.hull = v.armorMax / 2, v.hullMax / 2
  steps(game, 10)
  t.near(v.armor, v.armorMax * (0.5 + 10 * 0.004 * Constants.TICK), 1e-6)
  t.near(v.hull, v.hullMax * (0.5 + 10 * 0.002 * Constants.TICK), 1e-6)
  steps(game, math.ceil(0.5 / (0.002 * Constants.TICK)) + 5)
  t.eq({ v.armor, v.hull, v.shield } :: { any }, { v.armorMax, v.hullMax, 0 } :: { any })
  -- It is in the save, and the game goes on the same from it.
  v.armor = v.armorMax / 3
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  steps(game, 7)
  steps(loaded, 7)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  -- A hull that is anybody else's does not: what its armour has lost stays lost.
  local other, plain = flying("frigate.akashi")
  local w = plain.vitals
  t.eq({ w.armorMend, w.hullMend } :: { any }, { nil, nil } :: { any })
  w.armor, w.hull = w.armorMax / 2, w.hullMax / 2
  steps(other, 30)
  t.eq({ w.armor, w.hull } :: { any }, { w.armorMax / 2, w.hullMax / 2 } :: { any })
end)

suite:Case("with no shield, a shot is into its armour at once; and no shield module goes on it", function(t)
  local oon = Ships.byId["frigate.oon"]
  for _, module in { "shield.extender.small", "shield.booster.small", "shield.hardener", "rig.shield" } do
    t.eq({ Attributes.Check(oon, { module }) } :: { any }, { false, "this hull carries no shield" } :: { any }, module)
  end
  t.eq({ Attributes.Check(oon, { "armor.plate.200mm", "armor.repairer.small", "damage.control" }) } :: { any }, { true } :: { any })
  -- (and a hull with one takes them as ever)
  t.eq({ Attributes.Check(Ships.byId["frigate.akashi"], { "shield.extender.small" }) } :: { any }, { true } :: { any })
  -- Its people's guns are blasters, the short-range hybrid turret, which fires plasma.
  t.eq(Factions.byId.nimia.weapon, "hybrid")
  local blaster = Modules.byId["blaster.small"]
  t.eq((blaster.weapon :: Modules.Weapon).family, "hybrid")
  t.eq(Modules.chargeById["charge.plasma"].family, "hybrid")
  local railgun = Modules.byId["railgun.small"]
  t.ok((blaster.weapon :: Modules.Weapon).optimal < (railgun.weapon :: Modules.Weapon).optimal, "a blaster is the short one of the two")
end)

suite:Case("the Nimia's own gear makes it mend faster: a low-slot lattice, two rigs and two skills; and does nothing for a hull that does not mend", function(t)
  local oon = Ships.byId["frigate.oon"]
  local function mends(types: { string }, levels: { [string]: number }?): (number, number)
    local fitted: { Attributes.Fitted } = {}
    for _, type in types do
      table.insert(fitted, { type = type, running = false })
    end
    local stats = Attributes.Ship(oon, fitted, levels)
    return stats.armorMend, stats.hullMend
  end
  t.eq({ mends({}) } :: { any }, { 0.004, 0.002 } :: { any })
  -- The lattice: half as fast again, armour and hull; a second one does less than the first.
  local lattice = Modules.byId["mend.lattice"]
  t.eq({ lattice.slot, lattice.lineage } :: { any }, { "low", "nimia" } :: { any })
  local one, hullOne = mends({ "mend.lattice" })
  t.near(one, 0.004 * 1.5, 1e-12)
  t.near(hullOne, 0.002 * 1.5, 1e-12)
  local two = mends({ "mend.lattice", "mend.lattice" })
  t.ok(two > one and two < 0.004 * 1.5 * 1.5 - 1e-9, `two lattices mend {two}`)
  t.eq({ Attributes.Check(oon, { "mend.lattice", "mend.lattice" }) } :: { any }, { true } :: { any })
  -- The rigs: one for the armour, at the cost of speed, and one for the hull, at the cost of room.
  local armorRig, hullRig = mends({ "rig.mend.armor" }), select(2, mends({ "rig.mend.hull" }))
  t.near(armorRig, 0.004 * 1.3, 1e-12)
  t.near(hullRig, 0.002 * 1.3, 1e-12)
  t.eq({ mends({ "rig.mend.armor" }) } :: { any }, { armorRig, 0.002 } :: { any })
  for _, id in { "rig.mend.armor", "rig.mend.armor.medium", "rig.mend.armor.large", "rig.mend.hull", "rig.mend.hull.medium", "rig.mend.hull.large" } do
    t.eq({ Modules.byId[id].slot, Modules.byId[id].lineage } :: { any }, { "rig", "nimia" } :: { any }, id)
  end
  -- The skills: a tenth a level each, the one for armour and the other for hull.
  local armor, hull = Skills.byId["armor.mending"], Skills.byId["hull.mending"]
  t.eq({ armor.faction, hull.faction, armor.start, hull.start } :: { any }, { "nimia", "nimia", -1, -1 } :: { any })
  local skilled, skilledHull = mends({}, { ["armor.mending"] = 5, ["hull.mending"] = 3 })
  t.near(skilled, 0.004 * 1.5, 1e-12)
  t.near(skilledHull, 0.002 * 1.3, 1e-12)
  t.eq(Skills.Needs("mend.lattice"), { { skill = "armor.mending", level = 1 } })
  -- None of it is on anybody's market, nor the drawings for it, nor the books.
  for _, id in { "mend.lattice", "rig.mend.armor", "rig.mend.hull.large", "blueprint.mend.lattice", "blueprint.rig.mend.armor",
    Skills.Book("armor.mending"), Skills.Book("hull.mending") } do
    t.eq(Types.Info(id).scarce, true, id)
  end
  -- On a hull that does not mend, all of it together mends nothing.
  local akashi = Ships.byId["frigate.akashi"]
  local stats = Attributes.Ship(akashi, { { type = "mend.lattice", running = false }, { type = "rig.mend.armor", running = false } },
    { ["armor.mending"] = 5, ["hull.mending"] = 5 })
  t.eq({ stats.armorMend, stats.hullMend } :: { any }, { 0, 0 } :: { any })
  -- Fitted and flown, the ship in space mends at what the fit comes to.
  local game, me = flying("frigate.oon")
  local state = game.state
  Items.Equip(state, me.id, "mend.lattice", nil)
  state.skills["armor.mending"] = 5
  me.vitals.armor = me.vitals.armorMax / 2
  -- (its vitals are brought into line with its fit when anything about it changes: here, by hand)
  local Vitals = require("@lt/Core/Tactical/Vitals")
  Vitals.Refresh(state, me)
  t.near(me.vitals.armorMend :: number, 0.004 * 1.5 * 1.5, 1e-12)
  local was = me.vitals.armor
  steps(game, 10)
  t.near(me.vitals.armor - was, me.vitals.armorMax * 0.004 * 1.5 * 1.5 * 10 * Constants.TICK, 1e-6)
end)

suite:Case("a hull that mends goes on mending in a hangar, and costs the less to have repaired", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local theirs = Space.NewShip(state, "frigate.oon", "Mender", "player", state.player.home)
  local plain = Space.NewShip(state, "frigate.akashi", "Plain", "player", state.player.home)
  local oon, akashi = Ships.byId["frigate.oon"], Ships.byId["frigate.akashi"]
  theirs.armorDamage, theirs.hullDamage = oon.armor / 2, oon.hull / 2
  plain.armorDamage, plain.hullDamage = akashi.armor / 2, akashi.hull / 2
  steps(game, 20)
  t.near(theirs.armorDamage, oon.armor * (0.5 - 20 * 0.004 * Constants.TICK), 1e-6)
  t.near(theirs.hullDamage, oon.hull * (0.5 - 20 * 0.002 * Constants.TICK), 1e-6)
  t.eq({ plain.armorDamage, plain.hullDamage } :: { any }, { akashi.armor / 2, akashi.hull / 2 } :: { any })
  steps(game, math.ceil(0.5 / (0.002 * Constants.TICK)) + 5)
  t.eq({ theirs.armorDamage, theirs.hullDamage } :: { any }, { 0, 0 } :: { any })
  -- Aboard it, there is nothing left to pay a station for.
  state.player.ship = theirs.id
  t.eq(Core.Query.RepairCost(game), 0)
end)

suite:Case("a logistics capital has a bay for packed hulls where another capital industrial has an ore hold", function(t)
  local knuu, zzna = Ships.byId["capitalindustrial.knuu"], Ships.byId["capitalindustrial.zzna"]
  t.eq({ knuu.role, knuu.shipbay, knuu.ore } :: { any }, { "transport", Ships.SHIPBAY, 0 } :: { any })
  t.eq({ zzna.role, zzna.shipbay, zzna.ore, zzna.turrets } :: { any }, { nil, nil, Ships.ORE.capitalindustrial, 0 } :: { any })
  t.eq(Ships.SHIPBAY, 1200000)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local home = state.player.home
  local ship = Space.NewShip(state, "capitalindustrial.knuu", "Carrier of ships", "player", home)
  state.player.ship = ship.id
  t.eq({ Core.Query.ShipBay(game, ship.id) } :: { any }, { 1200000, 0 } :: { any })
  t.eq({ Core.Query.OreHold(game, ship.id) } :: { any }, { 0, 0 } :: { any })
  -- Packed hulls go into it from the hangar, as many as there is room for, and nothing else does.
  local frigates = Items.Add(state, "frigate.akashi", 4, home, "hangar")
  local battleship = Items.Add(state, "battleship.owari", 1, home, "hangar")
  local rounds = Items.Add(state, "ammo.emp", 100, home, "hangar")
  local function move(item: State.Item, to: string, quantity: number?): (boolean, string?)
    local command: State.Command = { kind = "MoveItems", actor = ship.id, item = item.id, to = to, quantity = quantity }
    local ok, why = Core.Validate(game, command)
    if ok then
      assert(Core.Submit(game, command))
      Core.Step(game)
    end
    return ok, why
  end
  t.eq({ move(rounds, "shipbay") } :: { any }, { false, "only packed hulls go in a ship bay" } :: { any })
  t.ok((move(frigates, "shipbay", 3)))
  t.ok((move(battleship, "shipbay")))
  local size, used = Core.Query.ShipBay(game, ship.id)
  t.eq({ size, used } :: { any }, { 1200000, 3 * Ships.byId["frigate.akashi"].volume + Ships.byId["battleship.owari"].volume } :: { any })
  local aboard: { [string]: number } = {}
  for _, item in Core.Query.Items(game, ship.id, "shipbay") do
    aboard[item.type] = item.quantity
  end
  t.eq(aboard, { ["frigate.akashi"] = 3, ["battleship.owari"] = 1 })
  -- (a carrier is a million cubic metres packed: one goes in, and a second does not)
  local carriers = Items.Add(state, "carrier.azayake", 2, home, "hangar")
  t.ok((move(carriers, "shipbay", 1)))
  t.eq({ move(carriers, "shipbay", 1) } :: { any }, { false, "not enough room in the ship bay" } :: { any })
  -- And out again, into the hangar.
  for _, item in Core.Query.Items(game, ship.id, "shipbay") do
    t.ok((move(item, "hangar")))
  end
  t.eq({ Core.Query.ShipBay(game, ship.id) } :: { any }, { 1200000, 0 } :: { any })
  -- A hull without one has nowhere to put them.
  local other = Space.NewShip(state, "capitalindustrial.zzna", "Miner", "player", home)
  state.player.ship = other.id
  local command: State.Command = { kind = "MoveItems", actor = other.id, item = carriers.id, to = "shipbay", quantity = 1 }
  t.eq({ Core.Validate(game, command) } :: { any }, { false, "this hull has no ship bay" } :: { any })
end)

return suite
