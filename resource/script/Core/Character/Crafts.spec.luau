--!strict
-- The crafts of each trade (Data/Skills): the skills that make a pilot
-- better at what they can do already, and what comes of each.

local Attributes = require("@lt/Core/Attributes")
local Blueprints = require("@lt/Core/Data/Blueprints")
local Combat = require("@lt/Core/Tactical/Combat")
local Contracts = require("@lt/Core/Assets/Contracts")
local Core = require("@lt/Core/Api")
local Fleet = require("@lt/Core/Tactical/Fleet")
local Industry = require("@lt/Core/Assets/Industry")
local Items = require("@lt/Core/Assets/Items")
local Jumping = require("@lt/Core/Tactical/Jumping")
local Missions = require("@lt/Core/Assets/Missions")
local Modules = require("@lt/Core/Data/Modules")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Ships = require("@lt/Core/Data/Ships")
local Sites = require("@lt/Core/Tactical/Sites")
local Skills = require("@lt/Core/Data/Skills")
local Space = require("@lt/Core/Tactical/Space")
local Standings = require("@lt/Core/Assets/Standings")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")
local Types = require("@lt/Core/Data/Types")

local suite = Test.Suite("Crafts")

-- The crafts, in the order of the skill list: the skills the data marks as one.
local CRAFTS: { string } = {}
for _, skill in Skills.list do
  if skill.craft then
    table.insert(CRAFTS, skill.id)
  end
end

local function newGame(): (Core.Game, number)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  return game, game.state.player.home
end

suite:Case("each craft is a skill with a book, learned and not begun with, and named for what a pilot learns and not for what it raises", function(t)
  -- (the project owner's word, 2026-11-14: "don't just name them what they upgrade")
  local PLAIN = { "Range", "Speed", "Damage", "Tracking", "Recharge", "Resist", "Signature", "Cargo", "Fuel", "Wage", "Standing",
    "Loyalty", "Probe", "Copy", "Copying", "Research", "Missile", "Turret", "Drone", "Shield", "Armour", "Armor", "Hull", "Capacitor",
    "Warp", "Falloff", "Lock", "Listing", "Efficiency", "Bonus" }
  local names: { [string]: boolean } = {}
  for _, id in CRAFTS do
    local skill = assert(Skills.byId[id], id)
    t.eq({ skill.start, #skill.note > 20 } :: { any }, { -1, true } :: { any }, id)
    t.ok(not names[skill.name], `two skills are called {skill.name}`)
    names[skill.name] = true
    for _, word in PLAIN do
      t.ok(string.find(skill.name, word, 1, true) == nil, `'{skill.name}' is named for what it raises ({word})`)
    end
    -- (a book for it, which a market lists, and nothing a pilot needs it for: a craft gates nothing)
    local book = Types.Info(Skills.Book(id))
    t.eq({ book.category, book.unlisted } :: { any }, { "skillbook", nil } :: { any }, id)
    for _, need in skill.requires do
      t.ok(Skills.byId[need.skill] ~= nil and need.level >= 1 and need.level <= 4, id)
    end
  end
  for _, type in Types.Ids() do
    for _, need in Skills.Needs(type) do
      t.ok(table.find(CRAFTS, need.skill) == nil, `{type} should not need {need.skill}`)
    end
  end
  t.eq(#CRAFTS, 24)
  t.eq(Skills.Level(nil, "windage"), 0)
  t.eq(Skills.Level({ windage = 3 }, "windage"), 3)
  t.eq(Skills.Level({ windage = -1 }, "windage"), 0)
end)

suite:Case("the crafts of a ship and its weapons: what each adds, a level", function(t)
  local hull = Ships.byId["cruiser.ouyou"]
  local function stat(skill: string, attribute: string): (number, number)
    return Attributes.Ship(hull, {}, { [skill] = 5 })[attribute], Attributes.Ship(hull, {}, {})[attribute]
  end
  local function near(skill: string, attribute: string, times: number)
    local with, without = stat(skill, attribute)
    t.near(with, without * times, math.abs(without) * 1e-9, `{skill} on {attribute}`)
  end
  near("wayfinding", "warpSpeed", 1.25)
  near("running.dark", "signature", 0.9)
  near("stowage", "cargo", 1.25)
  near("snapshot", "scanResolution", 1.25)
  near("reactor.trim", "capacitorRecharge", 0.75)
  near("field.harmonics", "shieldRecharge", 0.75)
  near("compartmentation", "hull", 1.25)
  -- A layer's four resistances together: a tenth less of each kind let through at five.
  for kind = 1, 4 do
    near("dispersal", `shieldResonance.{kind}`, 0.9)
    near("glancing.angles", `armorResonance.{kind}`, 0.9)
    -- (and each minds its own layer)
    near("dispersal", `armorResonance.{kind}`, 1)
    near("glancing.angles", `shieldResonance.{kind}`, 1)
    near("glancing.angles", `hullResonance.{kind}`, 1)
  end
  -- Turrets of every family follow and reach better; launchers have nothing to follow with, and fire faster.
  for _, gun in { "autocannon.small", "laser.pulse.small", "blaster.small", "artillery.large", "railgun.medium" } do
    local plain = Attributes.Weapon({}, gun, {})
    t.near(Attributes.Weapon({}, gun, { deflection = 5 }).tracking, plain.tracking * 1.25, 1e-9, gun)
    t.near(Attributes.Weapon({}, gun, { windage = 5 }).falloff, plain.falloff * 1.25, 1e-6, gun)
    t.eq(Attributes.Weapon({}, gun, { ["salvo.drill"] = 5 }).duration, plain.duration, gun)
    t.eq(Attributes.Weapon({}, gun, { deflection = 5 }).optimal, plain.optimal, gun)
  end
  local launcher = Attributes.Weapon({}, "launcher.light", {})
  t.near(Attributes.Weapon({}, "launcher.light", { ["salvo.drill"] = 5 }).duration, launcher.duration * 0.85, 1e-9)
  t.eq(Attributes.Weapon({}, "launcher.light", { deflection = 5, windage = 5 }), launcher)
  -- Nobody's skills, nothing.
  t.eq(Attributes.Ship(hull, {}, nil).hull, hull.hull)
end)

-- The pilot in a hull with a fit, at rest in open space, and a target
-- (nobody's, doing nothing) so far off.
local function arena(hull: string, fit: { { string } }, distance: number): (Core.Game, State.Ball, State.Ball)
  local game = newGame()
  local state = game.state
  local old = state.player.ship
  for _, item in Items.In(state, old, nil) do
    Items.Take(state, item, item.quantity)
  end
  state.ships[old] = nil
  State.RemoveId(state.shipIds, old)
  local mine = Space.NewShip(state, hull, "Tester", "player", state.player.home)
  state.player.ship = mine.id
  for _, entry in fit do
    Items.Equip(state, mine.id, entry[1], entry[2])
  end
  local station = assert(Space.Object(state, state.player.home))
  local me = Space.Launch(state, mine, 1, station.x + 4e6, station.y, station.z)
  local theirs = Space.NewShip(state, "frigate.courier", "Target", "pirate", 0)
  local foe = Space.Launch(state, theirs, 1, me.x + distance + me.radius + 100, me.y, me.z)
  foe.x = me.x + distance + me.radius + foe.radius
  return game, me, foe
end

-- Lock the target and switch the first module on it; the first event of
-- a kind in so many ticks, or nil.
local function fire(game: Core.Game, me: State.Ball, foe: State.Ball, kind: string, limit: number): { [string]: any }?
  local state = game.state
  assert(Core.Submit(game, { kind = "LockTarget", actor = me.id, target = foe.id }))
  for _ = 1, 60 do
    Core.Step(game)
    if me.vitals.locks[1] and me.vitals.locks[1].locked then
      break
    end
  end
  Core.TakeEvents(game)
  local item = Items.Fitted(state, me.id)[1]
  assert(Core.Submit(game, { kind = "ActivateModule", actor = me.id, item = item.id, target = foe.id }))
  for _ = 1, limit do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      if event.kind == kind then
        return event
      end
    end
  end
  return nil
end

suite:Case("Long Burn has a missile fly farther, and Proximity Fusing has more of it land on a small ship", function(t)
  local fit = { { "launcher.light", "missile.light.kinetic" } }
  -- A light missile flies 18.75 km: at twenty a launch comes to nothing. With Long Burn at five it flies a quarter
  -- longer, and gets there.
  local game, me, foe = arena("frigate.carvarro", fit, 20000)
  t.near(Items.Offence(game.state, me.id).range, 18750, 1)
  t.eq(assert(fire(game, me, foe, "Shot", 3)).outcome, "out of range")
  game, me, foe = arena("frigate.carvarro", fit, 20000)
  game.state.skills["long.burn"] = 5
  t.near(Items.Offence(game.state, me.id).range, 18750 * (1 + 5 * Combat.LONG_BURN), 1)
  local shot = assert(fire(game, me, foe, "Shot", 3))
  t.eq(shot.outcome, "launched")
  t.ok(fire ~= nil and shot.flight > 5, `it should fly longer than five seconds, and flew {shot.flight}`)

  -- A Courier is smaller than a light missile's blast: 38/40 of it lands. With the blast a fifth tighter, all of it.
  -- (The missile is kinetic and the hull a Talmar's, which leans to kinetic: 15% more in it to begin with.)
  local warhead = 83 * (1 + Ships.AFFINITY)
  game, me, foe = arena("frigate.carvarro", fit, 10000)
  t.near(assert(fire(game, me, foe, "MissileHit", 12)).damage, warhead * 38 / 40, 1e-9)
  game, me, foe = arena("frigate.carvarro", fit, 10000)
  game.state.skills["proximity.fusing"] = 5
  t.near(assert(fire(game, me, foe, "MissileHit", 12)).damage, warhead, 1e-9)
  -- (one level: a blast of 38.4 m, and 38 m of ship)
  game, me, foe = arena("frigate.carvarro", fit, 10000)
  game.state.skills["proximity.fusing"] = 1
  t.near(assert(fire(game, me, foe, "MissileHit", 12)).damage, warhead * 38 / (40 * (1 - Combat.FUSING)), 1e-9)
end)

suite:Case("Swarm Tactics has a pilot's drones hit harder, and nobody else's guns", function(t)
  -- The same fight twice, shot for shot: what the drones do is a fifth more at five, and what the ship does is not.
  local function fought(level: number): (number, number)
    local game, me, foe = arena("cruiser.ouyou", { { "autocannon.medium", "ammo.emp.medium" } }, 3000)
    local state = game.state
    state.skills.drones = 5
    state.skills["swarm.tactics"] = level
    foe.vitals.shieldMax, foe.vitals.shield = 1e9, 1e9
    Items.Add(state, "drone.light", 2, me.id, "dronebay")
    assert(Core.Submit(game, { kind = "LaunchDrones", actor = me.id }))
    Core.Step(game)
    assert(Core.Submit(game, { kind = "EngageDrones", actor = me.id, target = foe.id }))
    assert(Core.Submit(game, { kind = "LockTarget", actor = me.id, target = foe.id }))
    local mine, theirs = 0, 0
    for _ = 1, 90 do
      Core.Step(game)
      if me.vitals.locks[1] and me.vitals.locks[1].locked and #me.vitals.running == 0 then
        Core.Submit(game, { kind = "ActivateModule", actor = me.id, item = Items.Fitted(state, me.id)[1].id, target = foe.id })
      end
      for _, event in Core.TakeEvents(game) do
        if event.kind == "Shot" and event.to == foe.id then
          if event.from == me.id then
            mine += event.damage
          else
            theirs += event.damage
          end
        end
      end
    end
    return mine, theirs
  end
  local mine, drones = fought(0)
  local mineToo, more = fought(5)
  t.ok(mine > 0 and drones > 0, `the ship did {mine} and its drones {drones}`)
  t.near(more, drones * (1 + 5 * Combat.SWARM), drones * 1e-9)
  t.eq(mineToo, mine)
end)

suite:Case("the crafts of making, trading and working for people: what each comes to", function(t)
  local game, home = newGame()
  local state = game.state
  -- Bench Science and Draughtsmanship: a quarter off the time, at five.
  local blueprint = Blueprints.byId["blueprint.ammo.emp"]
  local research = assert(Industry.ResearchPlan(state, blueprint, "time")).seconds
  local copy = Industry.CopyPlan(state, blueprint, 40)
  state.skills["bench.science"] = 5
  state.skills.draughtsmanship = 5
  t.eq(assert(Industry.ResearchPlan(state, blueprint, "time")).seconds, math.ceil(research * 0.75))
  t.eq(assert(Industry.ResearchPlan(state, blueprint, "material")).seconds, math.ceil(research * 0.75))
  local quicker = Industry.CopyPlan(state, blueprint, 40)
  t.eq({ quicker.seconds, quicker.fee, quicker.runs }, { math.ceil(copy.seconds * 0.75), copy.fee, copy.runs })
  -- (and the job itself takes what the plan says)
  local item = assert(Items.Add(state, "blueprint.ammo.emp", 1, home, "hangar"))
  state.wallet = 1000000
  assert(Core.Submit(game, { kind = "StartResearch", actor = state.player.ship, item = item.id, what = "copy", quantity = 40 }))
  Core.Step(game)
  local job = Core.Query.Jobs(game, home)[1]
  t.eq(job.ends - job.started, quicker.seconds)

  -- Ledger Keeping: two more lots up at a time, a level.
  t.eq(Contracts.Limit(state), Contracts.LISTINGS)
  state.skills["ledger.keeping"] = 3
  t.eq({ Contracts.Limit(state), Core.Query.Contracts(game, home).limit }, { Contracts.LISTINGS + 6, Contracts.LISTINGS + 6 })

  -- Hard Bargaining: the same jobs, for 15% more at five. Patronage: a quarter more loyalty points for them.
  local plain = Missions.Offers(state, home)
  state.skills["hard.bargaining"] = 5
  local dearer = Missions.Offers(state, home)
  t.eq(#dearer, #plain)
  for index, offer in plain do
    t.eq({ dearer[index].kind, dearer[index].need } :: { any }, { offer.kind, offer.need } :: { any })
    -- (where both pay in credits: one job in five pays with a module worth about its credits, Missions.PRIZE,
    -- and what is worth about 15% more is not always the same module, or any)
    if offer.prize == nil and dearer[index].prize == nil then
      t.near(dearer[index].reward, offer.reward * 1.15, 2, offer.kind)
    end
  end
  state.skills.patronage = 5
  local patron = Missions.Offers(state, home)
  for index, offer in dearer do
    t.eq(patron[index].reward, offer.reward)
    -- (a job that pays with a module in place of credits, Missions.PRIZE, pays no credits to count the points
    -- from: it earns the points of the pay the module stands for)
    if offer.prize == nil then
      t.near(patron[index].loyalty, math.floor(offer.reward / (Missions.LOYALTY * Missions.PAY) * 1.25), 1, offer.kind)
    end
    t.ok(patron[index].loyalty >= offer.loyalty)
  end

  -- Protocol: what is done for a faction counts a quarter more at five, and what is done against it as it did.
  local faction = state.galaxy.systems[1].nearest
  local was = Standings.Of(state, faction)
  Standings.Change(state, faction, 1)
  t.near(Standings.Of(state, faction) - was, 1, 1e-9)
  state.skills.protocol = 5
  Standings.Change(state, faction, 1)
  t.near(Standings.Of(state, faction) - was, 1 + 1.25, 1e-9)
  Standings.Change(state, faction, -1)
  t.near(Standings.Of(state, faction) - was, 1.25, 1e-9)

  -- Paymaster: a fifth off a hired pilot's day at five, on top of what a devoted one forgoes.
  local wing: any = { wage = 1000, loyalty = 0 }
  t.eq(Fleet.Due(state, wing), 1000)
  state.skills.paymaster = 5
  t.eq(Fleet.Due(state, wing), 800)
  wing.loyalty = Fleet.LOYALTY.devoted
  t.eq(Fleet.Due(state, wing), math.floor(800 * (1 - Fleet.LOYALTY.less)))

  -- Lean Burn: a quarter less fuel for the same jump, at five (and never less than a block).
  local carrier = Space.NewShip(state, "carrier.tennit", "Jumper", "player", home)
  local raw = 10 * Ships.byId["carrier.tennit"].mass / Jumping.FUEL_MASS
  local fuel = Jumping.Fuel(state, carrier.id, 10)
  t.eq(fuel, math.ceil(raw))
  state.skills["lean.burn"] = 5
  t.ok(fuel > 8, `a carrier's ten light years take {fuel} blocks`)
  t.eq(Jumping.Fuel(state, carrier.id, 10), math.ceil(raw * 0.75 - 1e-9))
  t.ok(Jumping.Fuel(state, carrier.id, 10) < fuel)
  t.eq(Jumping.Fuel(state, carrier.id, 0), 1)
end)

suite:Case("Triangulation makes each probe near a signal worth more", function(t)
  -- A hidden belt, a probe by it, and one scan from far away: how far the scan gets with the craft and without.
  local function scanned(level: number): number
    -- (the first history whose first system has a hidden belt: the same one both times)
    for seed = 1, 60 do
      local game = Core.New({ galaxySeed = 1, historySeed = seed, peaceful = true })
      local state = game.state
      assert(Core.Submit(game, { kind = "Undock", actor = state.player.ship }))
      Core.Step(game)
      Core.Step(game)
      local me = state.balls[state.player.ship]
      for _, site in Sites.In(state, 1) do
        if site.kind == "ore" then
          state.skills.triangulation = level
          local place = assert(Space.Object(state, site.id))
          Items.Add(state, Sites.PROBE, 1, me.id, "cargo")
          local from = { me.x, me.y, me.z }
          me.x, me.y, me.z = place.x + 5e7, place.y, place.z
          assert(Core.Submit(game, { kind = "LaunchProbe", actor = me.id }))
          Core.Step(game)
          me.x, me.y, me.z = from[1] + 30 * 149597870700, from[2], from[3]
          Space.AssignGrid(state, me)
          t.eq((Sites.Covered(state, site, me)), 1)
          t.eq(site.strength, 0)
          assert(Core.Submit(game, { kind = "Scan", actor = me.id }))
          for _ = 1, Sites.SCAN + 1 do
            Core.Step(game)
          end
          return site.strength / Sites.Gain(state, site.kind, me.id)
        end
      end
    end
    error("no history seed up to 60 gives the first system a hidden belt")
  end
  local plain, better = scanned(0), scanned(5)
  -- (a scan and a probe: twice a scan. With the probe worth half as much again: two and a half.)
  t.near(plain, 2, 1e-6)
  t.near(better, 1 + (1 + 5 * Sites.TRIANGULATION), 1e-6)
  -- (the pirates' ships have no crafts)
  t.eq(Skills.Level(nil, "triangulation"), 0)
  t.ok(Pirates.NERVE > 0 and Modules.byId["launcher.light"] ~= nil)
end)

return suite
