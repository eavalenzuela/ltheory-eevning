--!strict
local Dogma = require("@lt/Core/Dogma")
local Modules = require("@lt/Core/Data/Modules")
local Ships = require("@lt/Core/Data/Ships")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Dogma")

local lancer = Ships.byId["frigate.lancer"]
local courier = Ships.byId["frigate.courier"]

local function fit(...: string): { Dogma.Fitted }
  local list = {}
  for _, id in { ... } do
    table.insert(list, { type = id, running = false })
  end
  return list
end

suite:Case("an empty hull has its own numbers", function(t)
  local stats = Dogma.Ship(lancer, {})
  t.eq(stats.armor, 520)
  t.eq(stats.maxVelocity, 345)
  t.eq(stats["armorResonance.1"], 0.5)
  t.near(stats.tau, 3.0 * 1.19, 1e-12)
end)

suite:Case("the stacking penalty is 100%, 87%, 57%, 28%", function(t)
  t.eq(Dogma.Penalty(0), 1)
  t.near(Dogma.Penalty(1), 0.869120, 1e-6)
  t.near(Dogma.Penalty(2), 0.570583, 1e-6)
  t.near(Dogma.Penalty(3), 0.282955, 1e-6)
end)

suite:Case("a plate adds armour and mass, and the mass slows the ship's turning", function(t)
  local stats = Dogma.Ship(lancer, fit("armor.plate.200mm"))
  t.eq(stats.armor, 1040)
  t.eq(stats.mass, 1377500)
  t.near(stats.tau, 3.0 * 1.3775, 1e-12)
end)

suite:Case("two membranes resist less than twice one", function(t)
  local one = Dogma.Ship(lancer, fit("armor.membrane"))
  t.near(one["armorResonance.1"], 0.5 * 0.85, 1e-12)
  local two = Dogma.Ship(lancer, fit("armor.membrane", "armor.membrane"))
  -- the second is worth 87% of itself: 1 - 0.15 * 0.86912
  t.near(two["armorResonance.1"], 0.5 * 0.85 * (1 - 0.15 * 0.869120), 1e-6)
  t.near(two["armorResonance.4"], 0.9 * 0.85 * (1 - 0.15 * 0.869120), 1e-6)
  t.eq(two["shieldResonance.1"], 1, "armour modules leave the shield alone")
end)

suite:Case("damage control is not penalised against a membrane", function(t)
  local stats = Dogma.Ship(lancer, fit("damage.control", "armor.membrane"))
  t.near(stats["armorResonance.1"], 0.5 * 0.9 * 0.85, 1e-12)
  t.near(stats["hullResonance.3"], 0.67 * 0.6, 1e-12)
  t.near(stats["shieldResonance.2"], 0.8 * 0.925, 1e-12)
end)

suite:Case("speed modules stack with a penalty", function(t)
  local stats = Dogma.Ship(lancer, fit("overdrive", "nanofiber"))
  -- overdrive is the stronger (10.5%), so the nanofiber's 7.75% is penalised
  t.near(stats.maxVelocity, 345 * 1.105 * (1 + 0.0775 * 0.869120), 1e-4)
  t.near(stats.inertia, 3.0 * 0.87, 1e-12)
  t.near(stats.hull, 360 * 0.85, 1e-12)
  t.near(stats.cargo, 135 * 0.9, 1e-12)
end)

suite:Case("a hardener only helps while it is running", function(t)
  local off = Dogma.Ship(courier, { { type = "shield.hardener", running = false } })
  local on = Dogma.Ship(courier, { { type = "shield.hardener", running = true } })
  t.eq(off["shieldResonance.2"], 0.8)
  t.near(on["shieldResonance.2"], 0.8 * 0.75, 1e-12)
end)

suite:Case("a microwarpdrive, running, is six times the speed and six times the signature, and costs capacitor to carry", function(t)
  local off = Dogma.Ship(courier, { { type = "mwd.5mn", running = false } })
  local on = Dogma.Ship(courier, { { type = "mwd.5mn", running = true } })
  local bare = Dogma.Ship(courier, {})
  t.near(on.maxVelocity, bare.maxVelocity * 6, 1e-6)
  t.near(on.signature, bare.signature * 6, 1e-6)
  t.near(off.maxVelocity, bare.maxVelocity, 1e-6)
  t.near(off.signature, bare.signature, 1e-6)
  t.near(off.capacitor, bare.capacitor * 0.85, 1e-6)
  -- (it is the faster of the two, and the dearer to run)
  local burner = Dogma.Ship(courier, { { type = "afterburner.1mn", running = true } })
  t.ok(on.maxVelocity > burner.maxVelocity * 2)
  local mwd, afterburner = Modules.byId["mwd.5mn"], Modules.byId["afterburner.1mn"]
  t.ok((mwd.boostCapacitor or 0) > 3 * (afterburner.boostCapacitor or 0))
  -- A courier's capacitor runs one for under a minute and a half.
  t.ok(off.capacitor / (mwd.boostCapacitor or 1) * (mwd.boostDuration or 1) < 90)
  t.ok(Modules.byId["mwd.medium"] ~= nil and Modules.byId["mwd.large"] ~= nil, "a microwarpdrive comes in three sizes")
end)

suite:Case("an afterburner, running, more than doubles speed and adds mass", function(t)
  local on = Dogma.Ship(courier, { { type = "afterburner.1mn", running = true } })
  t.near(on.maxVelocity, 360 * 2.1, 1e-9)
  t.eq(on.mass, 1600000)
  t.near(on.tau, 3.2 * 1.6, 1e-12)
end)

suite:Case("heat sinks raise a laser's damage and rate of fire, and nothing else's", function(t)
  local fitted = fit("laser.pulse.small", "heat.sink", "heat.sink")
  local laser = Dogma.Weapon(fitted, "laser.pulse.small")
  t.near(laser.damageMultiplier, 2.2 * 1.10 * (1 + 0.10 * 0.869120), 1e-6)
  t.near(laser.duration, 3 * 0.895 * (1 - 0.105 * 0.869120), 1e-6)
  t.eq(laser.optimal, 5200)
  local cannon = Dogma.Weapon(fit("autocannon.small", "heat.sink"), "autocannon.small")
  t.eq(cannon.damageMultiplier, 2.0)
  -- and the module table itself is untouched
  t.eq((Modules.byId["laser.pulse.small"].weapon :: Modules.Weapon).damageMultiplier, 2.2)
end)

suite:Case("a fit must respect slots, hardpoints, CPU and powergrid", function(t)
  t.eq({ Dogma.Check(lancer, { "laser.pulse.small", "laser.pulse.small", "laser.pulse.small" }) }, { true } :: { any })
  t.eq({ Dogma.Check(courier, { "laser.pulse.small", "laser.pulse.small", "laser.pulse.small" }) },
    { false, "no free high slot" } :: { any })
  t.eq({ Dogma.Check(lancer, { "launcher.light" }) }, { false, "no free launcher hardpoint" } :: { any })
  t.eq({ Dogma.Check(courier, { "shield.extender.small", "shield.booster.small", "armor.repairer.small" }) },
    { true } :: { any })
  t.eq({ Dogma.Check(courier, { "armor.plate.200mm", "laser.pulse.small", "laser.pulse.small", "afterburner.1mn" }) },
    { false, "not enough powergrid (35 of 32 MW)" } :: { any })
  t.eq({ Dogma.Check(lancer, { "shield.hardener", "shield.hardener", "heat.sink", "heat.sink", "heat.sink", "damage.control" }) },
    { false, "not enough CPU (145 of 125 tf)" } :: { any })
  t.eq({ Dogma.Check(lancer, { "bogus" }) }, { false, "'bogus' is not a module" } :: { any })
end)

suite:Case("every module and charge in the data is well formed", function(t)
  for _, module in Modules.list do
    t.ok(module.slot == "high" or module.slot == "mid" or module.slot == "low", module.id)
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
