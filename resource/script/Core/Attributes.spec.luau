--!strict
local Attributes = require("@lt/Core/Attributes")
local Modules = require("@lt/Core/Data/Modules")
local Ships = require("@lt/Core/Data/Ships")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Attributes")

local lancer = Ships.byId["frigate.battleaxe"]
local courier = Ships.byId["frigate.courier"]

local function fit(...: string): { Attributes.Fitted }
  local list = {}
  for _, id in { ... } do
    table.insert(list, { type = id, running = false })
  end
  return list
end

suite:Case("an empty hull has its own numbers", function(t)
  local stats = Attributes.Ship(lancer, {})
  t.eq(stats.armor, 415)
  t.eq(stats.maxVelocity, 340)
  t.eq(stats["armorResonance.2"], 0.65)
  -- (it is a Kethri hull, and leans to EM as theirs do: 15% less of that let through by every layer)
  t.near(stats["armorResonance.1"], 0.5 * 0.85, 1e-12)
  t.near(stats["shieldResonance.1"], 1 * 0.85, 1e-12)
  t.near(stats.tau, 3.2 * 1.12, 1e-12)
end)

suite:Case("the stacking penalty is 100%, 87%, 57%, 28%", function(t)
  t.eq(Attributes.Penalty(0), 1)
  t.near(Attributes.Penalty(1), 0.869120, 1e-6)
  t.near(Attributes.Penalty(2), 0.570583, 1e-6)
  t.near(Attributes.Penalty(3), 0.282955, 1e-6)
end)

suite:Case("a plate adds armour and mass, and the mass slows the ship's turning", function(t)
  local stats = Attributes.Ship(lancer, fit("armor.plate.200mm"))
  t.eq(stats.armor, 865)
  t.eq(stats.mass, 1260000)
  t.near(stats.tau, 3.2 * 1.26, 1e-12)
end)

suite:Case("two membranes resist less than twice one", function(t)
  local one = Attributes.Ship(lancer, fit("armor.membrane"))
  t.near(one["armorResonance.2"], 0.65 * 0.85, 1e-12)
  local two = Attributes.Ship(lancer, fit("armor.membrane", "armor.membrane"))
  -- the second is worth 87% of itself: 1 - 0.15 * 0.86912
  t.near(two["armorResonance.2"], 0.65 * 0.85 * (1 - 0.15 * 0.869120), 1e-6)
  t.near(two["armorResonance.4"], 0.9 * 0.85 * (1 - 0.15 * 0.869120), 1e-6)
  t.eq(two["shieldResonance.2"], 0.8, "armour modules leave the shield alone")
end)

suite:Case("damage control is not penalised against a membrane", function(t)
  local stats = Attributes.Ship(lancer, fit("damage.control", "armor.membrane"))
  t.near(stats["armorResonance.2"], 0.65 * 0.9 * 0.85, 1e-12)
  t.near(stats["hullResonance.3"], 0.67 * 0.7, 1e-12)
  t.near(stats["shieldResonance.2"], 0.8 * 0.925, 1e-12)
end)

suite:Case("speed modules stack with a penalty", function(t)
  local stats = Attributes.Ship(lancer, fit("overdrive", "nanofiber"))
  -- overdrive is the stronger (10.5%), so the nanofiber's 7.75% is penalised
  t.near(stats.maxVelocity, 340 * 1.105 * (1 + 0.0775 * 0.869120), 1e-4)
  t.near(stats.inertia, 3.2 * 0.87, 1e-12)
  t.near(stats.hull, 350 * 0.85, 1e-12)
  t.near(stats.cargo, 190 * 0.85, 1e-12)
end)

suite:Case("a hardener only helps while it is running", function(t)
  local off = Attributes.Ship(courier, { { type = "shield.hardener", running = false } })
  local on = Attributes.Ship(courier, { { type = "shield.hardener", running = true } })
  t.eq(off["shieldResonance.2"], 0.8)
  t.near(on["shieldResonance.2"], 0.8 * 0.75, 1e-12)
end)

suite:Case("a hull takes three rigs within its calibration, and each does one thing well and another worse", function(t)
  local bare = Attributes.Ship(courier, {})
  t.eq({ courier.rigs, courier.calibration } :: { any }, { 3, 400 } :: { any })
  t.eq(Ships.byId["capsule"].rigs, 0)
  local shielded = Attributes.Ship(courier, { { type = "rig.shield", running = false } })
  t.near(shielded.shield, bare.shield * 1.15, 1e-6)
  t.near(shielded.signature, bare.signature * 1.10, 1e-6)
  local quick = Attributes.Ship(courier, { { type = "rig.engine", running = false } })
  t.near(quick.maxVelocity, bare.maxVelocity * 1.10, 1e-6)
  t.near(quick.armor, bare.armor * 0.90, 1e-6)
  -- Three go in, within calibration; a fourth does not, nor do three that ask for too much.
  t.ok((Attributes.Check(courier, { "rig.hull", "rig.engine", "rig.cargo" })))
  t.eq({ Attributes.Check(courier, { "rig.hull", "rig.engine", "rig.cargo", "rig.capacitor" }) } :: { any },
    { false, "no free rig slot" } :: { any })
  t.eq({ Attributes.Check(courier, { "rig.projectile", "rig.laser", "rig.shield" }) } :: { any },
    { false, "not enough calibration (550 of 400)" } :: { any })
  t.ok((Attributes.Check(courier, { "rig.projectile", "rig.shield" })))
  t.eq({ Attributes.Check(Ships.byId["capsule"], { "rig.hull" }) } :: { any }, { false, "no free rig slot" } :: { any })
  -- (a rig takes no slot of another kind)
  t.ok((Attributes.Check(courier, { "autocannon.small", "autocannon.small", "rig.hull" })))
  -- A rig is made for a size of hull: a small one for a frigate or a destroyer, a medium for a cruiser, a hauler
  -- or a barge, a large for a battleship. It goes into no other.
  local sizes = { frigate = 1, destroyer = 1, cruiser = 2, industrial = 2, barge = 2, battleship = 3 }
  local made = { "rig.hull", "rig.hull.medium", "rig.hull.large" }
  local called = { "small", "medium", "large" }
  local seen: { [string]: boolean } = {}
  for _, hull in Ships.list do
    local takes = sizes[hull.class]
    if takes and not seen[hull.class] and (hull.rigs or 0) > 0 then
      seen[hull.class] = true
      t.eq(Ships.RigSize(hull), takes, hull.id)
      for size, rig in made do
        t.eq({ Attributes.Check(hull, { rig }) } :: { any },
          if size == takes then { true } :: { any }
          else { false, `a {called[size]} rig does not go into this hull: it takes {called[takes]} ones` } :: { any }, `{rig} in a {hull.class}`)
      end
    end
  end
  t.ok(seen.frigate and seen.cruiser and seen.battleship and seen.industrial)
  -- (the three sizes of a rig do the same thing)
  t.eq(Modules.byId["rig.hull.large"].passive, Modules.byId["rig.hull"].passive)
  t.eq({ Modules.byId["rig.hull"].name, Modules.byId["rig.hull.medium"].name, Modules.byId["rig.hull.large"].name },
    { "Small Bulkhead Rig", "Medium Bulkhead Rig", "Large Bulkhead Rig" })
end)

suite:Case("a microwarpdrive, running, is six times the speed and six times the signature, and costs capacitor to carry", function(t)
  local off = Attributes.Ship(courier, { { type = "mwd.5mn", running = false } })
  local on = Attributes.Ship(courier, { { type = "mwd.5mn", running = true } })
  local bare = Attributes.Ship(courier, {})
  t.near(on.maxVelocity, bare.maxVelocity * 6, 1e-6)
  t.near(on.signature, bare.signature * 6, 1e-6)
  t.near(off.maxVelocity, bare.maxVelocity, 1e-6)
  t.near(off.signature, bare.signature, 1e-6)
  t.near(off.capacitor, bare.capacitor * 0.75, 1e-6)
  -- (it is the faster of the two, and the dearer to run)
  local burner = Attributes.Ship(courier, { { type = "afterburner.1mn", running = true } })
  t.ok(on.maxVelocity > burner.maxVelocity * 2)
  local mwd, afterburner = Modules.byId["mwd.5mn"], Modules.byId["afterburner.1mn"]
  t.ok((mwd.boostCapacitor or 0) > 2 * (afterburner.boostCapacitor or 0))
  -- A courier's capacitor runs one for under a minute and a half.
  t.ok(off.capacitor / (mwd.boostCapacitor or 1) * (mwd.boostDuration or 1) < 90)
  t.ok(Modules.byId["mwd.medium"] ~= nil and Modules.byId["mwd.large"] ~= nil, "a microwarpdrive comes in three sizes")
end)

suite:Case("an afterburner, running, more than doubles speed and adds mass", function(t)
  local on = Attributes.Ship(courier, { { type = "afterburner.1mn", running = true } })
  t.near(on.maxVelocity, 355 * 2.1, 1e-9)
  t.eq(on.mass, 1530000)
  t.near(on.tau, 3.4 * 1.53, 1e-12)
end)

suite:Case("heat sinks raise a laser's damage and rate of fire, and nothing else's", function(t)
  local fitted = fit("laser.pulse.small", "heat.sink", "heat.sink")
  local laser = Attributes.Weapon(fitted, "laser.pulse.small")
  t.near(laser.damageMultiplier, 4.5 * 1.07 * (1 + 0.07 * 0.869120), 1e-6)
  t.near(laser.duration, 3.5 * 0.92 * (1 - 0.08 * 0.869120), 1e-6)
  t.eq(laser.optimal, 5250)
  local cannon = Attributes.Weapon(fit("autocannon.small", "heat.sink"), "autocannon.small")
  t.near(cannon.damageMultiplier, 2.89 * 1.5, 1e-9)
  -- and the module table itself is untouched
  t.eq((Modules.byId["laser.pulse.small"].weapon :: Modules.Weapon).damageMultiplier, 4.5)
end)

suite:Case("a fit must respect slots, hardpoints, CPU and powergrid", function(t)
  t.eq({ Attributes.Check(lancer, { "laser.pulse.small", "laser.pulse.small", "laser.pulse.small" }) }, { true } :: { any })
  -- (the Courier's third high slot is for what needs no hardpoint: a salvager goes beside its two guns, a third gun does not)
  t.eq({ Attributes.Check(courier, { "laser.pulse.small", "laser.pulse.small", "laser.pulse.small" }) },
    { false, "no free turret hardpoint" } :: { any })
  t.eq({ Attributes.Check(courier, { "autocannon.small", "autocannon.small", "salvager.small" }) }, { true } :: { any })
  t.eq({ Attributes.Check(courier, { "autocannon.small", "autocannon.small", "salvager.small", "cloak.device" }) },
    { false, "no free high slot" } :: { any })
  t.eq({ Attributes.Check(lancer, { "launcher.light" }) }, { false, "no free launcher hardpoint" } :: { any })
  t.eq({ Attributes.Check(courier, { "shield.extender.small", "shield.booster.small", "armor.repairer.small" }) },
    { true } :: { any })
  t.eq({ Attributes.Check(courier, { "armor.plate.200mm", "laser.pulse.small", "laser.pulse.small", "mwd.5mn",
    "shield.extender.small" }) }, { false, "not enough powergrid (47 of 44 MW)" } :: { any })
  t.eq({ Attributes.Check(lancer, { "laser.pulse.small", "laser.pulse.small", "laser.pulse.small", "shield.hardener",
    "shield.hardener", "heat.sink", "heat.sink", "heat.sink", "damage.control" }) },
    { false, "not enough CPU (231 of 175 tf)" } :: { any })
  t.eq({ Attributes.Check(lancer, { "bogus" }) }, { false, "'bogus' is not a module" } :: { any })
end)

suite:Case("every module and charge in the data is well formed", function(t)
  for _, module in Modules.list do
    t.ok(module.slot == "high" or module.slot == "mid" or module.slot == "low" or module.slot == "rig", module.id)
    -- (a rig takes calibration and nothing else, and is always on)
    t.ok((module.slot == "rig") == (module.calibration ~= nil), `{module.id}: calibration is a rig's`)
    if module.slot == "rig" then
      t.eq({ module.cpu, module.powergrid, #module.passive } :: { any }, { 0, 0, 2 } :: { any })
    end
    local roles = (if module.weapon then 1 else 0) + (if module.repair then 1 else 0) + (if module.boost then 1 else 0)
    t.ok(roles <= 1, `{module.id} does more than one thing`)
    t.ok((module.boost == nil) == (module.boostDuration == nil), `{module.id}: boost needs a duration`)
    if module.weapon then
      local family = module.weapon.family
      local loadable = false
      for _, charge in Modules.charges do
        loadable = loadable or charge.family == family
      end
      t.ok(loadable, `{module.id} has nothing to load`)
    end
    -- any fit of just this module on a big enough hull is accepted
    t.ok(Modules.byId[module.id] == module)
  end
  for _, charge in Modules.charges do
    t.eq(#charge.damage, 4, charge.id)
  end
  for _, hull in Ships.list do
    t.eq({ #hull.shieldResonance, #hull.armorResonance, #hull.hullResonance }, { 4, 4, 4 }, hull.id)
    t.ok(hull.turrets + hull.launchers <= hull.highs + 2, hull.id)
  end
end)

return suite
