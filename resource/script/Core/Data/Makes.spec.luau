--!strict
-- The better makes of a module that came with the owner's word of
-- 2026-11-15 (Data/Modules): a people's own, an officer's, and one that
-- has been through a mutator.

local Modules = require("@lt/Core/Data/Modules")
local Skills = require("@lt/Core/Data/Skills")
local Test = require("@lt/Tool/Test")
local Types = require("@lt/Core/Data/Types")

local suite = Test.Suite("Makes")

local function weapon(id: string): Modules.Weapon
  return assert(assert(Modules.byId[id], id).weapon, id)
end

suite:Case("each of the four peoples has its own make of what it is known for, and a shaded line of utility modules, and of nothing else", function(t)
  local counts: { [string]: number } = {}
  for _, module in Modules.list do
    if module.meta == 3 then
      local people = assert(module.lineage, module.id)
      counts[people] = (counts[people] or 0) + 1
      local base = assert(Modules.byId[assert(module.base)], module.id)
      t.ok(not base.tech and not base.meta and base.slot ~= "rig", `{module.id} is a make of something that is no plain module`)
      t.eq(module.id, `{base.id}.{people}`)
      -- (what it is known for: as easy to fit as the plain one; the rest of
      -- its line, since 2026-11-16, shaded to its style, and cheaper)
      if module.shaded then
        t.eq(module.basePrice, base.basePrice * 5, module.id)
        t.ok(Modules.Shade(people) ~= nil, people)
      else
        t.eq({ module.cpu, module.powergrid, module.basePrice } :: { any }, { base.cpu, base.powergrid, base.basePrice * 6 } :: { any }, module.id)
      end
      t.eq(Skills.Needs(module.id), Skills.Needs(base.id), `{module.id} wants more skill than the plain one`)
      t.eq(Types.Info(module.id).scarce, true)
      t.eq(Modules.Own(base.id, people), module)
    end
  end
  t.eq(#Modules.Peoples(), 4)
  for _, people in Modules.Peoples() do
    t.ok((counts[people] or 0) >= 15, `{people} has only {counts[people] or 0} makes of its own`)
  end
  -- What each is known for: its weapons, what keeps it whole, and one other thing.
  t.ok(Modules.Own("launcher.light", "vessari") and Modules.Own("armor.plate.200mm", "vessari") and Modules.Own("cargo.expander", "vessari"))
  t.ok(Modules.Own("autocannon.small", "talmar") and Modules.Own("shield.extender.small", "talmar") and Modules.Own("computer.tracking", "talmar"))
  t.ok(Modules.Own("blaster.small", "orun") and Modules.Own("armor.repairer.small", "orun") and Modules.Own("afterburner.1mn", "orun"))
  t.ok(Modules.Own("laser.pulse.small", "kethri") and Modules.Own("armor.plate.200mm", "kethri") and Modules.Own("capacitor.recharger", "kethri"))
  t.eq({ Modules.Own("laser.pulse.small", "vessari"), Modules.Own("launcher.light", "kethri"), Modules.Own("miner.small", "orun") } :: { any }, {})
  -- The line: every people makes its own of the utility modules, shaded.
  local vessari, talmar = assert(Modules.Own("shield.extender.small", "vessari")), assert(Modules.Own("disruptor.warp", "talmar"))
  t.eq({ vessari.shaded, talmar.shaded } :: { any }, { true, true } :: { any })
  t.ok(vessari.cpu < Modules.byId["shield.extender.small"].cpu, "the Vessari's are easier to fit")
  t.ok(assert(talmar.hex).range > assert(Modules.byId["disruptor.warp"].hex).range, "the Talmar's reach further")
  -- (since 2026-11-20 every module but those that do one thing, another people's guns and a mining laser)
  t.eq({ Modules.Own("cloak.device", "orun"), Modules.Own("miner.small", "vessari") } :: { any }, {})
  -- Fifteen parts in a hundred more of what it gives: between the custom make and tech 2.
  t.near(weapon("laser.pulse.small.kethri").damageMultiplier, weapon("laser.pulse.small").damageMultiplier * 1.15, 1e-9)
  t.ok(weapon("laser.pulse.small.kethri").damageMultiplier > weapon("laser.pulse.small.custom").damageMultiplier)
  t.ok(weapon("laser.pulse.small.kethri").damageMultiplier < weapon("laser.pulse.small.ii").damageMultiplier)
  t.near(Modules.byId["armor.plate.200mm.vessari"].passive[1].value, Modules.byId["armor.plate.200mm"].passive[1].value * 1.15, 1e-9)
  -- (of a thing that helps and costs, the help is more and the cost is what it was)
  local plain, own = Modules.byId["cargo.expander"], Modules.byId["cargo.expander.vessari"]
  t.near(own.passive[1].value - 1, (plain.passive[1].value - 1) * 1.15, 1e-9)
  t.eq(own.passive[2].value, plain.passive[2].value)
  -- (and of what lets less through, less: a hardener's)
  local hard, theirs = assert(Modules.byId["shield.hardener"].boost)[1], assert(Modules.byId["shield.hardener.talmar"].boost)[1]
  t.near(1 - theirs.value, (1 - hard.value) * 1.15, 1e-9)
end)

suite:Case("an officer's module is called by their name, is better than a masterwork, and is only of what a captain carries", function(t)
  local id = assert(Modules.Officer("autocannon.small", "Mara Venn"))
  t.eq(id, "autocannon.small.officer@Mara_Venn")
  local module = Modules.byId[id]
  t.eq({ module.name, module.officer, module.meta, module.base } :: { any }, { "Mara Venn's Small Autocannon", "Mara Venn", 4, "autocannon.small" } :: { any })
  t.ok(weapon(id).damageMultiplier > weapon("autocannon.small.master").damageMultiplier)
  t.ok(module.cpu <= Modules.byId["autocannon.small.master"].cpu)
  -- (and of what is no gun: what it mends, what it holds)
  local mends = Modules.byId[assert(Modules.Officer("armor.repairer.small", "Mara Venn"))]
  t.ok(assert(mends.repair).amount > assert(Modules.byId["armor.repairer.small.master"].repair).amount, "an officer's repairer against a masterwork")
  local plate = Modules.byId[assert(Modules.Officer("armor.plate.200mm", "Mara Venn"))]
  t.ok(plate.passive[1].value > Modules.byId["armor.plate.200mm.master"].passive[1].value, "an officer's plate against a masterwork")
  t.eq(Skills.Needs(id), Skills.Needs("autocannon.small"))
  local info = Types.Info(id)
  t.eq({ info.name, info.category, info.unlisted, info.basePrice } :: { any },
    { module.name, "module", true, Modules.byId["autocannon.small"].basePrice * 40 } :: { any })
  -- (the same id is the same module, whoever asks and when)
  t.eq(Modules.byId[id], module)
  t.eq(table.find(Types.Ids(), id), nil, "no market lists a module that is one of a kind")
  -- Not of a thing no captain carries, nor of a make of anything.
  -- (since 2026-11-20 every module has a masterwork but those that do one thing or do not: a cloaking device)
  t.eq({ Modules.Officer("cloak.device", "Mara Venn"), Modules.Officer("autocannon.small.ii", "Mara Venn"),
    Modules.Officer("no.such.thing", "Mara Venn") } :: { any }, {})
end)

suite:Case("a module comes out of a mutator with each figure moved its own way, once and no more", function(t)
  local plain = Modules.byId["laser.pulse.small"]
  local id = assert(Modules.Mutated("laser.pulse.small", { 30, -25, 10, 0 }))
  t.eq(id, "laser.pulse.small~55003525")
  local module = Modules.byId[id]
  t.eq({ module.name, module.mutated, module.base } :: { any }, { "Mutated Small Pulse Laser", true, "laser.pulse.small" } :: { any })
  t.eq(module.rolls, { 30, -25, 10, 0 })
  local was, now = assert(plain.weapon), assert(module.weapon)
  t.near(now.damageMultiplier, was.damageMultiplier * 1.30, 1e-9)
  t.ok(module.cpu > plain.cpu and module.powergrid > plain.powergrid, "a quarter worse to fit should take more to fit")
  t.near(now.capacitor, was.capacitor * 0.90, 1e-9)
  t.eq({ now.optimal, now.falloff, now.duration }, { was.optimal, was.falloff, was.duration })
  -- The best and the worst there is; and what is asked for past them is them.
  local best = Modules.byId[assert(Modules.Mutated("laser.pulse.small", { 30, 30, 30, 30 }))]
  local worst = Modules.byId[assert(Modules.Mutated("laser.pulse.small", { -25, -25, -25, -25 }))]
  t.near(assert(best.weapon).damageMultiplier / assert(worst.weapon).damageMultiplier, 1.30 / 0.75, 1e-9)
  t.ok(best.cpu < plain.cpu and worst.cpu > plain.cpu)
  t.eq(Modules.Mutated("laser.pulse.small", { 99, -99, 0, 0 }), Modules.Mutated("laser.pulse.small", { 30, -25, 0, 0 }))
  -- Any module, of any make, an officer's too: but not one that has been through already.
  t.ok(Modules.Mutated("laser.pulse.small.ii", { 0, 0, 0, 0 }) ~= nil and Modules.Mutated("armor.plate.200mm.vessari", { 1, 2, 3, 4 }) ~= nil)
  local theirs = assert(Modules.Mutated(assert(Modules.Officer("autocannon.small", "Mara Venn")), { 5, 5, 5, 5 }))
  t.eq(Modules.byId[theirs].name, "Mutated Mara Venn's Small Autocannon")
  t.eq(Modules.Mutated(id, { 1, 1, 1, 1 }), nil, "a mutated module should not be mutated again")
  -- A tech 2 module that has been through wants what the tech 2 one wants.
  t.eq(Skills.Needs(assert(Modules.Mutated("laser.pulse.small.ii", { 0, 0, 0, 0 }))), Skills.Needs("laser.pulse.small.ii"))
  -- And what is no such module is none.
  t.eq({ Modules.byId["nothing~12345678"], Modules.byId["laser.pulse.small~99999999"], Modules.byId["laser.pulse.small~1"],
    Modules.byId["laser.pulse.small~abcdefgh"] } :: { any }, {})
  t.eq(Types.Get("laser.pulse.small~99999999"), nil)
end)

return suite
