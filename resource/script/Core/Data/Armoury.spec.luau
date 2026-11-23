--!strict
-- The armoury as the project owner laid it out (2026-11-14): what a
-- weapon fires in every kind of damage and three reaches, a short and a
-- long make of every launcher, the modules that help the weapons and
-- harden a ship against one kind of damage, and the kind each human
-- faction's ships lean to.

local Attributes = require("@lt/Core/Attributes")
local Blueprints = require("@lt/Core/Data/Blueprints")
local Core = require("@lt/Core/Api")
local Factions = require("@lt/Core/Data/Factions")
local Fits = require("@lt/Core/Fits")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")
local Types = require("@lt/Core/Data/Types")

local suite = Test.Suite("Armoury")

-- The one kind of damage a charge does (1 EM, 2 thermal, 3 kinetic, 4
-- explosive) and how much, or 0 and all of it for one that does several.
local function pure(charge: Modules.ChargeType): (number, number)
  local kind, total, kinds = 0, 0, 0
  for index, amount in charge.damage do
    if amount > 0 then
      kind, kinds = index, kinds + 1
      total += amount
    end
  end
  return if kinds == 1 then kind else 0, total
end

-- The plain charges of a family and a size.
local function plain(family: string, size: number): { Modules.ChargeType }
  local found: { Modules.ChargeType } = {}
  for _, charge in Modules.charges do
    -- (a vertical-launch missile or a plasma torpedo is its launcher's own, and not one of the twelve: Data/Modules)
    if charge.family == family and charge.size == size and charge.tech ~= 2 and charge.line == nil then
      table.insert(found, charge)
    end
  end
  return found
end

suite:Case("a round, a hybrid charge and a missile come in every kind of damage and three reaches: twelve a size; a crystal is EM and thermal", function(t)
  local names: { [string]: boolean } = {}
  for _, family in { "projectile", "hybrid" } do
    for size = 1, 4 do
      local charges = plain(family, size)
      t.eq(#charges, 12, `{family} {size}`)
      -- one of each kind at each reach, each doing the one kind of damage, and as much as the others of its reach
      local seen: { [string]: number } = {}
      for _, charge in charges do
        local kind, total = pure(charge)
        t.ok(kind >= 1, `{charge.id} does more than one kind of damage`)
        local reach = if charge.rangeMultiplier == 0.5 then "short" elseif charge.rangeMultiplier == 1 then "standard"
          elseif charge.rangeMultiplier == 1.6 then "long" else "?"
        t.ok(reach ~= "?", `{charge.id} reaches {charge.rangeMultiplier}`)
        local cell = `{kind} {reach}`
        t.eq(seen[cell], nil, `two {family} charges of size {size} are {cell}`)
        seen[cell] = total
        t.ok(not names[charge.name], `two charges are called {charge.name}`)
        names[charge.name] = true
        -- (and each has a tech 2 make, which nobody sells, and a blueprint)
        t.ok(Modules.chargeById[charge.id .. ".ii"] ~= nil and Blueprints.byProduct[charge.id] ~= nil, charge.id)
        t.eq(Types.Info(charge.id).scarce, nil, charge.id)
      end
      for kind = 1, 4 do
        t.ok(seen[`{kind} short`] > seen[`{kind} standard`] and seen[`{kind} standard`] > seen[`{kind} long`], `{family} {size} kind {kind}`)
        t.eq({ seen[`{kind} short`], seen[`{kind} standard`], seen[`{kind} long`] },
          { seen["1 short"], seen["1 standard"], seen["1 long"] }, `{family} {size}: a kind is as good as another`)
      end
    end
  end
  -- The rounds there were before there were twelve are the rounds they were: by id, kind, reach, and how hard they hit.
  local function is(id: string, name: string, kind: number, total: number, range: number)
    local charge = assert(Modules.chargeById[id], id)
    local does, much = pure(charge)
    t.eq({ charge.name, does, much, charge.rangeMultiplier } :: { any }, { name, kind, total, range } :: { any }, id)
  end
  is("ammo.emp", "Small Shock Canister", 1, 12, 0.5)
  is("ammo.fusion", "Small Burst Canister", 4, 12, 0.5)
  is("ammo.sabot", "Small Penetrator Rounds", 3, 8, 1)
  is("charge.plasma", "Small Plasma Charge", 2, 11, 0.5)
  is("charge.slug", "Small Iron Slug", 3, 9, 1)
  is("charge.needle", "Small Iron Needle", 3, 7, 1.6)
  is("ammo.thermal.long", "Small Incendiary Sabot", 2, 6, 1.6)
  is("charge.em.standard", "Small Ion Slug", 1, 9, 1)
  is("charge.explosive.long.large", "Large Blast Needle", 4, 7 * 4, 1.6)

  -- Missiles: each kind as a missile, a rocket (half the flight, three tenths more) and a javelin (six tenths
  -- more flight, a quarter less).
  for size = 1, 4 do
    local charges = plain("missile", size)
    t.eq(#charges, 12, `missiles of size {size}`)
    t.eq(string.find(charges[1].id, "%.short") or string.find(charges[1].id, "%.long"), nil, "the missile itself comes first")
    for _, charge in charges do
      local kind = pure(charge)
      t.ok(kind >= 1 and not names[charge.name], charge.id)
      names[charge.name] = true
      if not string.find(charge.id, "%.short$") and not string.find(charge.id, "%.long$") then
        local rocket, javelin = assert(Modules.chargeById[charge.id .. ".short"]), assert(Modules.chargeById[charge.id .. ".long"])
        t.near(rocket.damage[kind], charge.damage[kind] * 1.3, 1e-9, rocket.id)
        t.near(rocket.flightTime, charge.flightTime * 0.5, 1e-9, rocket.id)
        t.near(javelin.damage[kind], charge.damage[kind] * 0.75, 1e-9, javelin.id)
        t.near(javelin.flightTime, charge.flightTime * 1.6, 1e-9, javelin.id)
        t.eq({ rocket.velocity, javelin.explosionRadius }, { charge.velocity, charge.explosionRadius })
        t.ok(string.find(rocket.name, "Rocket", 1, true) ~= nil and string.find(javelin.name, "Javelin", 1, true) ~= nil)
      end
    end
  end
  t.eq(Modules.chargeById["missile.light.kinetic"].name, "Lance Light Missile")
  t.eq(Modules.chargeById["missile.cruise.em.short"].name, "Arc Cruise Rocket")
  -- A laser's crystals are as they were: three a size, EM and thermal and nothing else.
  for size = 1, 4 do
    local crystals = plain("laser", size)
    t.eq(#crystals, 3)
    for _, crystal in crystals do
      t.eq({ crystal.damage[3], crystal.damage[4] }, { 0, 0 }, crystal.id)
      t.ok(crystal.damage[1] > 0)
    end
  end
end)

suite:Case("every launcher has a short make of its size: the same missiles, thrown a third as far and faster", function(t)
  local pairs = { { "launcher.light", "launcher.rocket" }, { "launcher.heavy", "launcher.assault" }, { "launcher.cruise", "launcher.torpedo" },
    { "launcher.siege", "launcher.bombard" } }
  for size, pair in pairs do
    local long, short = assert(Modules.byId[pair[1]]), assert(Modules.byId[pair[2]])
    local far, near = assert(long.weapon), assert(short.weapon)
    t.eq({ far.family, far.size, near.family, near.size } :: { any }, { "missile", size, "missile", size } :: { any })
    t.eq({ short.slot, short.hardpoint } :: { any }, { "high", "launcher" } :: { any })
    t.eq({ far.flight, near.flight } :: { any }, { nil, 0.35 } :: { any })
    -- (how much faster, how much harder each missile lands, and what each takes to fit, are the reference's short and
    -- long launcher of that size, 2026-11-18)
    t.ok(near.duration < far.duration, short.id)
    t.ok(short.basePrice < long.basePrice and near.clip > far.clip, short.id)
    -- (as it is fitted: a launcher throws its missiles as far as they fly, and a short one a third of that)
    t.eq({ Attributes.Weapon({}, long.id, nil).flight, Attributes.Weapon({}, short.id, nil).flight }, { 1, 0.35 })
    -- (the same skills, a blueprint, a tech 2 make and the makes that are found, which throw no farther)
    t.eq(Skills.Needs(short.id), Skills.Needs(long.id))
    t.ok(Blueprints.byProduct[short.id] ~= nil)
    for _, make in { ".ii", ".custom", ".master" } do
      t.eq(assert(assert(Modules.byId[short.id .. make], short.id .. make).weapon).flight, 0.35)
    end
  end

  -- In a fight: a light missile flies 18.75 km from a launcher, and 6.56 km from a rocket launcher.
  local function shot(launcher: string, distance: number): (string, number)
    local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
    local state = game.state
    local old = state.player.ship
    for _, item in Items.In(state, old, nil) do
      Items.Take(state, item, item.quantity)
    end
    state.ships[old] = nil
    State.RemoveId(state.shipIds, old)
    local mine = Space.NewShip(state, "frigate.carvarro", "Tester", "player", state.player.home)
    state.player.ship = mine.id
    Items.Equip(state, mine.id, launcher, "missile.light.thermal")
    local station = assert(Space.Object(state, state.player.home))
    local me = Space.Launch(state, mine, 1, station.x + 4e6, station.y, station.z)
    local theirs = Space.NewShip(state, "frigate.courier", "Target", "pirate", 0)
    local foe = Space.Launch(state, theirs, 1, me.x + distance + me.radius + 100, me.y, me.z)
    foe.x = me.x + distance + me.radius + foe.radius
    assert(Core.Submit(game, { kind = "LockTarget", actor = me.id, target = foe.id }))
    for _ = 1, 60 do
      Core.Step(game)
      if me.vitals.locks[1] and me.vitals.locks[1].locked then
        break
      end
    end
    Core.TakeEvents(game)
    assert(Core.Submit(game, { kind = "ActivateModule", actor = me.id, item = Items.Fitted(state, me.id)[1].id, target = foe.id }))
    for _ = 1, 3 do
      Core.Step(game)
      for _, event in Core.TakeEvents(game) do
        if event.kind == "Shot" then
          return event.outcome, Items.Offence(state, me.id).range
        end
      end
    end
    error("nothing was fired")
  end
  local outcome, reach = shot("launcher.light", 8000)
  t.eq({ outcome, reach } :: { any }, { "launched", 18750 } :: { any })
  outcome, reach = shot("launcher.rocket", 8000)
  t.eq(outcome, "out of range")
  t.near(reach, 18750 * 0.35, 1e-6)
  t.eq((shot("launcher.rocket", 6000)), "launched")
end)

suite:Case("what helps the weapons: a damage upgrade for hybrids, an enhancer for every turret, and three computers to switch on", function(t)
  local function weapon(gun: string, fitted: { Attributes.Fitted }): Modules.Weapon
    return Attributes.Weapon(fitted, gun, nil)
  end
  local function on(type: string): { Attributes.Fitted }
    return { { type = type, running = true } }
  end
  local function off(type: string): { Attributes.Fitted }
    return { { type = type, running = false } }
  end
  -- The Flux Coil is to hybrids what the Heat Sink is to lasers, and does nothing for anybody else's guns.
  local blaster, plain = weapon("blaster.small", off("flux.coil")), weapon("blaster.small", {})
  t.near(blaster.damageMultiplier, plain.damageMultiplier * 1.07, 1e-9)
  t.near(blaster.duration, plain.duration * 0.92, 1e-9)
  t.eq(weapon("autocannon.small", off("flux.coil")), weapon("autocannon.small", {}))
  t.eq(weapon("laser.pulse.small", off("flux.coil")), weapon("laser.pulse.small", {}))
  t.eq(Modules.byId["flux.coil"].slot, "low")
  -- A Tracking Enhancer is for every turret, hybrids too, and no launcher.
  for _, gun in { "autocannon.small", "laser.beam.medium", "railgun.large", "blaster.small" } do
    local bare, helped = weapon(gun, {}), weapon(gun, off("tracking.enhancer"))
    t.near(helped.tracking, bare.tracking * 1.07, 1e-9, gun)
    t.near(helped.optimal, bare.optimal * 1.0725, 1e-6, gun)
    t.near(helped.falloff, bare.falloff * 1.145, 1e-6, gun)
  end
  t.eq(weapon("launcher.light", off("tracking.enhancer")), weapon("launcher.light", {}))
  -- The computers do nothing until they are switched on, and take a mid slot and capacitor while they run.
  for _, id in { "computer.tracking", "computer.range", "computer.flight" } do
    local module = Modules.byId[id]
    t.eq({ module.slot, #module.passive, module.boostDuration ~= nil, (module.boostCapacitor or 0) > 0 } :: { any },
      { "mid", 0, true, true } :: { any }, id)
    for _, gun in { "autocannon.small", "launcher.light" } do
      t.eq(weapon(gun, off(id)), weapon(gun, {}), `{id} off on {gun}`)
    end
    t.ok(Blueprints.byProduct[id] ~= nil and Types.Info(id).scarce == nil, id)
  end
  for _, gun in { "autocannon.medium", "laser.pulse.small", "railgun.large" } do
    local bare = weapon(gun, {})
    t.near(weapon(gun, on("computer.tracking")).tracking, bare.tracking * 1.2, 1e-9, gun)
    t.eq(weapon(gun, on("computer.tracking")).optimal, bare.optimal, gun)
    t.near(weapon(gun, on("computer.range")).optimal, bare.optimal * 1.1, 1e-6, gun)
    t.near(weapon(gun, on("computer.range")).falloff, bare.falloff * 1.2, 1e-6, gun)
    t.eq(weapon(gun, on("computer.flight")), bare, gun)
  end
  local launcher = weapon("launcher.heavy", {})
  t.eq(weapon("launcher.heavy", on("computer.tracking")), launcher)
  t.eq(weapon("launcher.heavy", on("computer.range")), launcher)
  local guided = weapon("launcher.heavy", on("computer.flight"))
  t.near(guided.flight :: number, 1.08, 1e-9)
  t.near(guided.blast :: number, 0.945, 1e-9)
  -- (and on a short launcher it is as much more of the third it throws)
  t.near(weapon("launcher.assault", on("computer.flight")).flight :: number, 0.35 * 1.08, 1e-9)
end)

suite:Case("a hardener against one kind of damage halves what its layer lets through of that kind, switched on, and of no other", function(t)
  local hull = Ships.byId["cruiser.ouyou"]
  local bare = Attributes.Ship(hull, {}, nil)
  local count = 0
  for kind, word in { "em", "thermal", "kinetic", "explosive" } do
    for _, layer in { "shield", "armor" } do
      local id = `{layer}.hardener.{word}`
      local module = assert(Modules.byId[id], id)
      count += 1
      t.eq({ module.slot, #module.passive } :: { any }, { if layer == "shield" then "mid" else "low", 0 } :: { any }, id)
      t.ok(Blueprints.byProduct[id] ~= nil and Types.Info(id).scarce == nil, id)
      local running = Attributes.Ship(hull, { { type = id, running = true } }, nil)
      local idle = Attributes.Ship(hull, { { type = id, running = false } }, nil)
      for _, other in { "shield", "armor", "hull" } do
        for index = 1, 4 do
          local name = `{other}Resonance.{index}`
          t.eq(idle[name], bare[name], `{id} off`)
          t.near(running[name], bare[name] * (if other == layer and index == kind then 0.5 else 1), 1e-12, `{id} on {name}`)
        end
      end
    end
  end
  t.eq(count, 8)
  -- Two of the same are worth less than twice one (they stack as everything does), and the plain hardener is still there.
  local two = Attributes.Ship(hull, { { type = "shield.hardener.em", running = true }, { type = "shield.hardener.em", running = true } }, nil)
  t.ok(two["shieldResonance.1"] < bare["shieldResonance.1"] * 0.5 and two["shieldResonance.1"] > bare["shieldResonance.1"] * 0.25)
  t.ok(Modules.byId["shield.hardener"] ~= nil and Modules.byId["armor.membrane"] ~= nil)
end)

suite:Case("each human faction's ships lean to a kind of damage: they do 15% more of it and let 15% less of it through; nobody else's lean", function(t)
  -- (the project owner's mapping, 2026-11-14)
  local leans: { [string]: number } = { kethri = 1, orun = 2, talmar = 3, vessari = 4 }
  for _, faction in Factions.list do
    t.eq(faction.affinity, if faction.kind == "human" then leans[faction.id] else nil, faction.id)
    if faction.kind == "human" then
      t.ok(leans[faction.id] ~= nil, `{faction.id} is a human faction with no kind of its own`)
    end
  end
  t.eq(Ships.AFFINITY, 0.15)
  local plainShield, plainArmor, plainHull = { 1.0, 0.8, 0.6, 0.5 }, { 0.5, 0.65, 0.75, 0.9 }, { 0.67, 0.67, 0.67, 0.67 }
  local leaning = 0
  for _, hull in Ships.list do
    local faction = Factions.byId[hull.lineage]
    local kind = if faction and faction.kind == "human" then leans[faction.id] else nil
    t.eq(hull.affinity, kind, hull.id)
    for index = 1, 4 do
      t.eq(Ships.Dealt(hull, index), if kind == index then 1.15 else 1, hull.id)
    end
    if kind then
      leaning += 1
      -- (a tech 2 hull's shield and armour are tougher all round: what it leans to is tougher by the same again)
      local tough = if hull.tech == 2 then 0.75 else 1
      for index = 1, 4 do
        local less = if index == kind then 0.85 else 1
        t.near(hull.shieldResonance[index], plainShield[index] * tough * less, 1e-12, hull.id)
        t.near(hull.armorResonance[index], plainArmor[index] * tough * less, 1e-12, hull.id)
        t.near(hull.hullResonance[index], plainHull[index] * less, 1e-12, hull.id)
      end
    elseif hull.class ~= "drone" and hull.tech ~= 2 and not (hull.class == "works" and string.sub(hull.id, 1, 12) == "works.tower." and #hull.id > 13)
      and not (hull.class == "works" and string.match(hull.id, "^works%.citadel%.%a+%.%a+%.%a+$") ~= nil) then
      -- (a people's tower core is better on its people's layer: Data/Structures' spec says so; and an alien
      -- people's citadel's, as their towers')
      t.eq({ hull.shieldResonance, hull.armorResonance, hull.hullResonance }, { plainShield, plainArmor, plainHull }, hull.id)
    end
  end
  t.ok(leaning >= 50, `{leaning} hulls lean to a kind of damage`)
  t.eq({ Ships.byId["frigate.courier"].affinity, Ships.byId["frigate.cutthroat"].affinity } :: { any }, { nil, nil } :: { any })

  -- On paper: a Vessari hull's guns do 15% more with explosive rounds than with kinetic ones that hit as hard.
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local function paper(hullId: string, gun: string, charge: string): Items.Offence
    local ship = Space.NewShip(state, hullId, "T", "player", state.player.home)
    Items.Equip(state, ship.id, gun, charge)
    return Items.Offence(state, ship.id)
  end
  local burst, solid = paper("frigate.akashi", "autocannon.small", "ammo.fusion"), paper("frigate.akashi", "autocannon.small", "ammo.kinetic.short")
  t.near(burst.volley, solid.volley * 1.15, 1e-9)
  t.near(burst.kinds[4], burst.dps, 1e-9)
  t.eq(paper("frigate.courier", "autocannon.small", "ammo.fusion").volley, solid.volley)
  -- And a standard fit loads what its hull leans to, where its guns fire it.
  local function loaded(hullId: string): number
    local hull = Ships.byId[hullId]
    local charge = Modules.chargeById[assert(Fits.Charge(Fits.Weapons(hull)[1], hull), hullId)]
    return (pure(charge))
  end
  t.eq(loaded("frigate.akashi"), 4, "a Vessari hull loads explosive")
  t.eq(loaded("frigate.carvarro"), 3, "a Talmar hull loads kinetic")
  local orun: Ships.ShipType? = nil
  local kethri: Ships.ShipType? = nil
  for _, hull in Ships.list do
    if hull.lineage == "orun" and hull.turrets > 0 and orun == nil then
      orun = hull
    elseif hull.lineage == "kethri" and hull.turrets > 0 and kethri == nil then
      kethri = hull
    end
  end
  t.eq(loaded(assert(orun).id), 2, "an Orun hull loads thermal")
  -- (a crystal is EM and thermal both: the Kethri's first is one with EM in it)
  local crystal = Modules.chargeById[assert(Fits.Charge(Fits.Weapons(assert(kethri))[1], kethri))]
  t.ok(crystal.family == "laser" and crystal.damage[1] > 0)
  -- (nobody's hull: the first there is, as before)
  t.eq(Fits.Charge("autocannon.small"), "ammo.emp")
  t.eq(Fits.Charge("launcher.light"), "missile.light.kinetic")
end)

suite:Case("the pirates fire every kind of damage between them, and their hulls lean to none", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local fired: { [string]: number } = {}
  local kinds: { [number]: boolean } = {}
  for _, id in { "scout", "raider", "jackal", "marauder", "ravager" } do
    local ball = Pirates.Spawn(state, Pirates.kindById[id], 1, 1e9, 0, 0, 0)
    t.eq(Ships.byId[state.ships[ball.id].type].affinity, nil, id)
    for _, item in Items.Fitted(state, ball.id) do
      local module = Modules.byId[item.type]
      if module.weapon and module.weapon.family == "projectile" and fired[id] == nil then
        local kind = pure(Modules.chargeById[item.charge])
        t.ok(kind >= 1, `{id} fires {item.charge}`)
        fired[id] = kind
        kinds[kind] = true
      end
    end
  end
  t.eq(fired, { scout = 4, raider = 3, jackal = 4, marauder = 2, ravager = 1 })
  t.eq({ kinds[1], kinds[2], kinds[3], kinds[4] }, { true, true, true, true })
end)

return suite
