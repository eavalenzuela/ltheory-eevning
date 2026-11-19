--!strict
-- Hull bonuses (Data/HullBonuses): what a hull does better than its
-- class, a level of a skill or as its role, and where each comes to
-- something.

local Attributes = require("@lt/Core/Attributes")
local Combat = require("@lt/Core/Tactical/Combat")
local Core = require("@lt/Core/Api")
local Facts = require("@lt/Core/Data/Facts")
local HullBonuses = require("@lt/Core/Data/HullBonuses")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")
local Space = require("@lt/Core/Tactical/Space")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("HullBonuses")

suite:Case("every bonus is on a hull there is, of a skill there is, and says what it does", function(t)
  local count = 0
  for id, bonuses in HullBonuses.byHull do
    local hull = assert(Ships.byId[id], id)
    t.eq(hull.bonuses, bonuses, id)
    for _, bonus in bonuses do
      count += 1
      t.ok(bonus.skill == nil or Skills.byId[bonus.skill] ~= nil, `{id}: no skill {tostring(bonus.skill)}`)
      t.ok(#bonus.note > 5 and bonus.per ~= 0, id)
    end
    -- (and the info window lists them)
    local sheet = assert(Facts.Of(id))
    local listed = 0
    for _, section in sheet.sections do
      if section.title == "Bonuses" then
        listed += #section.rows
      end
    end
    t.eq(listed, #bonuses + (if Ships.Immune(hull) then 1 else 0), id)
  end
  t.ok(count >= 30, `{count} bonuses`)
end)

suite:Case("a bonus is so much a level of its skill, and a role bonus is the hull's whatever the pilot knows", function(t)
  local kabuto = Ships.byId["frigate.kabuto"]
  t.eq(Ships.Bonus(kabuto, "repair", "armor", nil), 1)
  t.near(Ships.Bonus(kabuto, "repair", "armor", { frigates = 5 }), 1.5, 1e-9)
  t.near(Ships.Bonus(kabuto, "weapons", "duration", { frigates = 5 }, "missile"), 0.75, 1e-9)
  t.eq(Ships.Bonus(kabuto, "weapons", "duration", { frigates = 5 }, "projectile"), 1)
  local nozomi = Ships.byId["destroyer.nozomi"]
  t.near(Ships.Bonus(nozomi, "weapons", "flight", nil, "missile"), 1.5, 1e-9)
  -- On the ship's figures: armour resists a fifth more at Destroyers 5 (every kind), and the Kanau's armour a quarter more.
  local plain = Attributes.Ship(nozomi, {}, nil)
  local trained = Attributes.Ship(nozomi, {}, { destroyers = 5 })
  for kind = 1, 4 do
    t.near(trained[`armorResonance.{kind}`], plain[`armorResonance.{kind}`] * 0.8, 1e-9)
  end
  local kanau = Ships.byId["destroyer.kanau"]
  t.near(Attributes.Ship(kanau, {}, nil).armor, kanau.armor * 1.25, 1e-6)
  -- On its weapons: the Manazashi's torpedoes twice as hard, and its other launchers not.
  local manazashi = Ships.byId["attackbattlecruiser.manazashi"]
  local torpedo = Attributes.Weapon({}, "launcher.torpedo", nil, manazashi)
  t.near(torpedo.damageMultiplier, Attributes.Weapon({}, "launcher.torpedo", nil, nil).damageMultiplier * 2, 1e-9)
  t.eq(Attributes.Weapon({}, "launcher.cruise", nil, manazashi).damageMultiplier, Attributes.Weapon({}, "launcher.cruise", nil, nil).damageMultiplier)
  -- (the Naishou's turrets track a quarter better, whatever their family)
  local naishou = Ships.byId["battlecruiser.naishou"]
  t.near(Attributes.Weapon({}, "autocannon.medium", nil, naishou).tracking, Attributes.Weapon({}, "autocannon.medium", nil, nil).tracking * 1.25, 1e-9)
  t.eq(Attributes.Weapon({}, "launcher.heavy", nil, naishou).tracking, 0)
  -- On what regenerates a shield: the Undulation's relay takes half as much again off its recharge time at Frigates 5.
  local undulation = Ships.byId["frigate.undulation"]
  local relayed = { { type = "relay.shield", running = false } }
  t.near(Attributes.Ship(undulation, relayed, { frigates = 5 }).shieldRecharge, undulation.shieldRecharge * (1 - 0.2 * 1.5), 1e-6)
  t.near(Attributes.Ship(undulation, relayed, nil).shieldRecharge, undulation.shieldRecharge * 0.8, 1e-6)
  -- On an afterburner: the Akashi's gives a quarter more of its speed at Afterburners 5.
  local akashi = Ships.byId["frigate.akashi"]
  local running = { { type = "afterburner.1mn", running = true } }
  local bare = Attributes.Ship(akashi, {}, { propulsion = 5 }).maxVelocity
  local burning = Attributes.Ship(akashi, running, { propulsion = 5 }).maxVelocity
  local plainBurn = Attributes.Ship(akashi, running, nil).maxVelocity
  t.near(burning / bare, 1 + (plainBurn / Attributes.Ship(akashi, {}, nil).maxVelocity - 1) * 1.25, 1e-9)
end)

suite:Case("a supercarrier and an ultracapital are touched by no electronic warfare but a capital's disruptor; a web reaches as its hull has it", function(t)
  for _, hull in Ships.list do
    t.eq(Ships.Immune(hull), hull.class == "supercarrier" or hull.class == "ultracapital", hull.id)
  end
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local station = assert(Space.Object(state, state.player.home))
  local function launch(type: string, x: number): any
    local ship = Space.NewShip(state, type, type, "pirate", 0)
    return Space.Launch(state, ship, 1, station.x + x, station.y, station.z)
  end
  local web = launch("cruiser.ouyou", 60000)
  local item = Items.Equip(state, web.id, "projector.entanglement", nil)
  for _, case in { { "supercarrier.nullo", 1 }, { "carrier.azayake", 0.5 } } :: { { any } } do
    local target = launch(case[1], 63000)
    local speed = target.maxVelocity
    web.vitals.locks = { { target = target.id, done = 0, locked = true } }
    web.vitals.running = { { item = item.id, target = target.id, next = 0, stopping = false, cycles = 0 } }
    Core.Step(game)
    t.near(target.maxVelocity, speed * case[2], 1e-6, case[1])
    web.vitals.running = {}
    Core.Step(game)
  end
  -- (and a short-range hybrid hull's web reaches half as far again: the Orun's Knife's, and not the Ouyou's)
  local knife = launch("frigate.knife", 70000)
  local module = Modules.byId["projector.entanglement"]
  t.near(assert(Combat.Hex(state, knife.id, module)).range, assert(module.hex).range * 1.5, 1e-6)
  t.eq(assert(Combat.Hex(state, web.id, module)).range, assert(module.hex).range)
end)

return suite
