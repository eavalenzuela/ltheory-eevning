--!strict
-- Pirates (Tactical/Pirates): what they fly, and what comes where.

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Attributes = require("@lt/Core/Attributes")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Pirates")

-- A game with the player's ship in space at the first thing of a kind
-- in the first system of a band (the ship is put there: the flight is
-- Space's to test), and that thing.
local function at(t: Test.Context, historySeed: number, band: Galaxy.Band, kind: string): (Core.Game, System.Object)
  local game = Core.New({ galaxySeed = 1, historySeed = historySeed })
  local state = game.state
  t.ok(Core.Submit(game, { kind = "Undock", actor = state.player.ship }))
  Core.Step(game)
  local found: System.Object? = nil
  for system = 1, #state.galaxy.systems do
    if found == nil and Galaxy.Band(state.galaxy.systems[system].security) == band then
      -- (a system nobody has been to is described when it is first asked about)
      for _, object in Space.Describe(state, system).objects do
        if object.kind == kind and found == nil then
          found = object
        end
      end
    end
  end
  local site = assert(found, `no {kind} in {band} space`)
  local ball = assert(Core.Query.Ball(game, state.player.ship))
  ball.system = site.id // 10000
  ball.x, ball.y, ball.z = site.x + 2000, site.y, site.z
  Space.AssignGrid(state, ball)
  t.eq(ball.grid, site.id)
  Core.TakeEvents(game)
  return game, site
end

-- The pirates that come within a few ticks, by name.
local function arrivals(game: Core.Game): { string }
  local names: { string } = {}
  for _ = 1, 3 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      if event.kind == "BallAdded" then
        local ship = game.state.ships[event.ball]
        if ship and ship.owner == "pirates" then
          table.insert(names, ship.name)
        end
      end
    end
  end
  table.sort(names)
  return names
end

-- What a pirate is called without its grade ("Veteran Raider" and
-- "Raider Captain" are a "Pirate Raider"), and the grade.
local function ungraded(name: string): (string, number)
  local veteran = string.match(name, "^Veteran (.+)$")
  local captain = string.match(name, "^(.+) Captain$")
  if veteran then
    return "Pirate " .. veteran, 1
  elseif captain then
    return "Pirate " .. captain, 2
  end
  return name, 0
end

suite:Case("every kind of pirate flies an Unbound hull with a fit the hull takes, its weapons loaded", function(t)
  for _, kind in Pirates.kinds do
    local hull = Ships.byId[kind.hull]
    -- (what a camp is built of is nobody's hull, and is not flown: below)
    if hull ~= nil and hull.class == "works" then
      continue
    end
    t.ok(hull ~= nil and hull.lineage == "unbound", `{kind.name} flies '{kind.hull}', which is not the pirates' own`)
    local fit = Pirates.Fit(kind)
    local types: { string } = {}
    local weapons = 0
    for _, entry in fit do
      table.insert(types, entry[1])
      local module = Modules.byId[entry[1]]
      if module.weapon then
        weapons += 1
        local charge = Modules.chargeById[entry[2]]
        t.ok(charge ~= nil, `{kind.name}'s {module.name} has nothing loaded`)
        t.eq({ charge.family, charge.size } :: { any }, { module.weapon.family, module.weapon.size } :: { any })
      end
    end
    t.ok((Attributes.Check(hull, types)), `{kind.name}'s fit does not go on its hull`)
    t.ok(weapons >= 1, `{kind.name} has no weapon`)
    -- (all but the scout and the mender use every hardpoint the hull has)
    if kind.id ~= "scout" and kind.id ~= "mender" then
      t.eq(weapons, hull.turrets + hull.launchers)
    end
  end
  t.eq(#Pirates.Fit(Pirates.SCOUT), 1)
end)

suite:Case("a bigger pirate hits harder, takes more killing and pays more", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local last = { dps = 0, hp = 0, bounty = 0, tags = 0 }
  for _, kind in Pirates.kinds do
    -- (a mender is not one of the ladder: it is there for the others;
    -- nor is what a camp is built of)
    if kind.id == "mender" or Ships.byId[kind.hull].class == "works" then
      continue
    end
    local ball = Pirates.Spawn(game.state, kind, 1, 1e9, 0, 0, 0)
    local offence = Items.Offence(game.state, ball.id)
    local v = ball.vitals
    local hp = v.shieldMax + v.armorMax + v.hullMax
    t.ok(offence.dps > last.dps * 1.3, `{kind.name} does {offence.dps} a second and the kind below {last.dps}`)
    t.ok(hp > last.hp * 1.4, `{kind.name} has {hp} hit points and the kind below {last.hp}`)
    t.ok(kind.bounty > last.bounty * 2 and kind.tags >= last.tags)
    -- (and it fights from inside the reach of its guns)
    t.ok(kind.range < offence.range, `{kind.name} keeps {kind.range} m off and reaches {offence.range}`)
    local pilot = game.state.pilots[ball.id]
    t.eq({ pilot.bounty, pilot.tags }, { kind.bounty, kind.tags })
    last = { dps = offence.dps, hp = hp, bounty = kind.bounty, tags = kind.tags }
  end
  -- A scout is what it was when it flew a Courier: one small gun, worth 6,000.
  t.eq(Pirates.SCOUT.bounty, 6000)
end)

suite:Case("what a camp is built of stands where it is put: a store does nothing, and an emplacement fires on what comes in reach", function(t)
  local stores, emplacements = 0, 0
  for _, kind in Pirates.kinds do
    local hull = Ships.byId[kind.hull]
    if hull.class ~= "works" then
      continue
    end
    -- Nobody sells one or builds one, and it does not move.
    t.eq({ hull.restricted, hull.maxVelocity, hull.turrets } :: { any }, { true, 0, 0 } :: { any })
    local fit = Pirates.Fit(kind)
    local weapons = 0
    for _, entry in fit do
      weapons += if Modules.byId[entry[1]].weapon then 1 else 0
    end
    t.eq({ #fit, weapons }, { #kind.fit, hull.launchers }, `{kind.name}'s fit`)
    stores += if weapons == 0 then 1 else 0
    emplacements += if weapons > 0 then 1 else 0

    local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
    local state = game.state
    local id = state.player.ship
    t.ok((Core.Submit(game, { kind = "Undock", actor = id })))
    Core.Step(game)
    local me = state.balls[id]
    me.x += 5e7
    me.vx, me.vy, me.vz = 0, 0, 0
    Space.AssignGrid(state, me)
    t.ok((Core.Submit(game, { kind = "Stop", actor = id })))
    local ball = Pirates.Spawn(state, kind, me.system, me.x + 6000, me.y, me.z, me.grid)
    local x, y, z = ball.x, ball.y, ball.z
    local was = me.vitals.shield
    local shots = 0
    for _ = 1, 40 do
      Core.Step(game)
      for _, event in Core.TakeEvents(game) do
        shots += if event.kind == "Shot" and event.from == ball.id then 1 else 0
      end
    end
    t.eq({ ball.x, ball.y, ball.z }, { x, y, z }, `{kind.name} moved`)
    if weapons > 0 then
      t.ok(shots > 0 and me.vitals.shield < was, `{kind.name} did not fire on a ship six kilometres off`)
    else
      t.eq({ shots, me.vitals.shield }, { 0, was }, `{kind.name} is a store`)
    end
  end
  t.ok(stores >= 2 and emplacements >= 2)
end)

suite:Case("a mender keeps its pack whole: its repairers go on whichever pirate is worst hurt", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local fit = Pirates.Fit(Pirates.kindById["mender"])
  local remote = 0
  for _, entry in fit do
    remote += if Modules.Mends(Modules.byId[entry[1]]) then 1 else 0
  end
  t.eq(remote, 2)
  -- The player out in open space, a raider on them, and a mender with it.
  t.ok((Core.Submit(game, { kind = "Undock", actor = state.player.ship })))
  Core.Step(game)
  local me = state.balls[state.player.ship]
  me.x += 4e6
  Space.AssignGrid(state, me)
  local raider = Pirates.Spawn(state, Pirates.kindById["raider"], me.system, me.x + 3000, me.y, me.z, me.grid)
  local mender = Pirates.Spawn(state, Pirates.kindById["mender"], me.system, me.x + 5000, me.y, me.z, me.grid)
  for _ = 1, 30 do
    Core.Step(game)
  end
  -- (it does not mend the ship it is hunting, hurt as it may be)
  for _, running in mender.vitals.running do
    t.ok(running.target ~= me.id or not Modules.Mends(Modules.byId[state.items[running.item].type]), "the mender is mending its prey")
  end
  raider.vitals.armor = raider.vitals.armorMax * 0.2
  local mending = false
  for _ = 1, 40 do
    Core.Step(game)
    for _, running in mender.vitals.running do
      mending = mending or running.target == raider.id
    end
  end
  t.ok(mending, "the mender did nothing for a raider with a fifth of its armour")
  t.ok(raider.vitals.armor > raider.vitals.armorMax * 0.2 + 100 or state.balls[raider.id] == nil, "the raider's armour was not put back")
end)

suite:Case("what comes follows from how safe the system is", function(t)
  for band, packs in Pirates.PACKS do
    local share = 0
    for _, pack in packs do
      share += pack[1]
      for _, id in pack[2] do
        t.ok(Pirates.kindById[id] ~= nil, `a pack in {band} space has a '{id}'`)
        if band == "secure" then
          t.eq(id, "scout")
        else
          t.ok(id ~= "scout", "a scout is for where order is kept")
        end
      end
    end
    t.near(share, 1, 1e-9)
  end
  local seen: { [string]: boolean } = {}
  for seed = 1, 12 do
    local secure = arrivals((at(t, seed, "secure", "belt")))
    t.ok(#secure >= 1 and #secure <= 2, `history seed {seed}: {#secure} pirates at a belt in secure space`)
    for _, name in secure do
      t.eq(name, "Pirate Scout")
    end
    local low = arrivals((at(t, seed, "low", "belt")))
    t.ok(#low >= 2 and #low <= 3, `history seed {seed}: {#low} pirates at a belt in low security`)
    local lawless = arrivals((at(t, seed, "lawless", "belt")))
    t.eq(#lawless, 3)
    -- (whatever grade each is of: below)
    for _, name in low do
      local kind = ungraded(name)
      t.ok(kind == "Pirate Raider" or kind == "Pirate Jackal", `{name} in low security`)
    end
    for _, name in lawless do
      local kind = ungraded(name)
      t.ok(kind ~= "Pirate Scout", "a scout in lawless space")
      seen[kind] = true
    end
  end
  t.ok(seen["Pirate Marauder"], "twelve packs in lawless space and no cruiser among them")
  t.ok(seen["Pirate Jackal"] and seen["Pirate Raider"])
end)

suite:Case("a veteran of a kind fits the custom make of whatever it has one of, and a captain the masterwork: the same hull, more to it, and more on its head", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local function whole(ball: State.Ball): number
    return ball.vitals.shieldMax + ball.vitals.armorMax + ball.vitals.hullMax
  end
  local graded = 0
  for _, kind in Pirates.kinds do
    t.eq(Pirates.Graded(kind, 0), kind)
    -- (what one is, is told by the name it flies under: whoever draws it asks)
    t.eq({ Pirates.Rank(kind.name), Pirates.Rank(Pirates.Graded(kind, 1).name), Pirates.Rank(Pirates.Graded(kind, 2).name) },
      if Ships.byId[kind.hull].class == "works" then { 0, 0, 0 } else { 0, 1, 2 }, kind.name)
    -- (nobody commands a store)
    if Ships.byId[kind.hull].class == "works" then
      t.eq({ Pirates.Graded(kind, 1), Pirates.Graded(kind, 2) }, { kind, kind })
      continue
    end
    local plain = Pirates.Spawn(state, kind, 1, 1e9, 0, 0, 0)
    local last = { dps = Items.Offence(state, plain.id).dps, hp = whole(plain) }
    local short = (string.gsub(kind.name, "^Pirate ", ""))
    for grade, rank in Pirates.GRADES do
      graded += 1
      local better = Pirates.Graded(kind, grade)
      t.eq({ better.id, better.hull, better.grade, better.range, better.bounty, better.tags } :: { any },
        { `{kind.id}.{rank.id}`, kind.hull, grade, kind.range, kind.bounty * rank.bounty, kind.tags + rank.tags } :: { any })
      t.eq(Pirates.kindById[better.id], better)
      t.eq({ better.name, (ungraded(better.name)), select(2, ungraded(better.name)) } :: { any },
        { if grade == 1 then `Veteran {short}` else `{short} Captain`, kind.name, grade } :: { any })
      -- It has what the plain kind has, each thing the make its grade fits, loaded alike; and then
      -- whatever else of what the plain kind would like that there is room for now.
      t.eq(#better.fit, #kind.fit)
      local was, fit = Pirates.Fit(kind), Pirates.Fit(better)
      for index, entry in was do
        t.eq(fit[index], { Modules.Graded(entry[1], grade), entry[2] }, `{better.name}'s fit, place {index}`)
      end
      local made = 0
      for _, entry in fit do
        local module = Modules.byId[entry[1]]
        made += if module.meta == grade then 1 else 0
        t.ok(module.meta == nil or module.meta == grade, `{better.name} has a {module.name}`)
        t.ok(module.meta == grade or Modules.Graded(entry[1], grade) == entry[1], `{better.name} has a plain {module.name}`)
      end
      t.ok(#fit >= #was and made >= 1, `{better.name}'s fit`)
      -- It hits harder than the grade below, takes as much killing at least, and is worth what its grade is.
      local ball = Pirates.Spawn(state, better, 1, 1e9 + 1e6 * graded, 0, 0, 0)
      local dps, hp = Items.Offence(state, ball.id).dps, whole(ball)
      t.ok(dps > last.dps * 1.03, `{better.name} does {dps} a second and the grade below {last.dps}`)
      t.ok(hp >= last.hp, `{better.name} has {hp} hit points and the grade below {last.hp}`)
      local pilot = state.pilots[ball.id]
      t.eq({ ball.name, state.ships[ball.id].type, pilot.bounty, pilot.tags } :: { any },
        { better.name, kind.hull, better.bounty, better.tags } :: { any })
      last = { dps = dps, hp = hp }
    end
  end
  -- (the five of the ladder and the mender, in two grades)
  t.eq(graded, 12)
  -- A captain's marauder against a plain one: a quarter more to its guns, and a good deal more plate and shield.
  local plain = Pirates.Spawn(state, Pirates.kindById["marauder"], 1, 3e9, 0, 0, 0)
  local captain = Pirates.Spawn(state, Pirates.kindById["marauder.captain"], 1, 4e9, 0, 0, 0)
  t.near(Items.Offence(state, captain.id).dps / Items.Offence(state, plain.id).dps, 1.25, 0.03)
  t.ok(whole(captain) > whole(plain) * 1.1, `{whole(captain)} against {whole(plain)}`)
end)

suite:Case("veterans and captains come where order is thin: none where it is kept, more of them the wilder it is, and a stronghold is a captain's", function(t)
  local counts: { [string]: { number } } = {}
  local bands: { Galaxy.Band } = {}
  table.insert(bands, "secure")
  table.insert(bands, "low")
  table.insert(bands, "lawless")
  for _, band: Galaxy.Band in bands do
    local all, veterans, captains = 0, 0, 0
    for seed = 1, 80 do
      local game = at(t, seed, band, "belt")
      local said = 0
      for _ = 1, 3 do
        Core.Step(game)
        for _, event in Core.TakeEvents(game) do
          local ship = if event.kind == "BallAdded" then game.state.ships[event.ball] else nil
          if ship and ship.owner == "pirates" then
            local _, grade = ungraded(ship.name)
            all += 1
            veterans += if grade == 1 then 1 else 0
            captains += if grade == 2 then 1 else 0
            said -= if grade == 2 then 1 else 0
          elseif event.kind == "PiratesArrived" then
            said += event.captains
          end
        end
      end
      -- (the word that they have come says how many captains are among them)
      t.eq(said, 0)
    end
    counts[band] = { all, veterans, captains }
    local odds = Pirates.GRADED[band]
    t.near(veterans / all, odds[1], 0.07, `{veterans} veterans of {all} in {band} space`)
    t.near(captains / all, odds[2], 0.04, `{captains} captains of {all} in {band} space`)
  end
  t.eq({ counts.secure[2], counts.secure[3] }, { 0, 0 })
  t.ok(counts.low[2] > 0 and counts.lawless[2] > counts.low[2] and counts.lawless[3] > 0,
    `{counts.low[2]} veterans in low security, {counts.lawless[2]} and {counts.lawless[3]} captains in lawless space`)
  -- A stronghold (a den that another den's stores gave away): the first of whoever keeps it is a captain.
  local kept = 0
  for seed = 1, 40 do
    local game = Core.New({ galaxySeed = 1, historySeed = seed })
    local state = game.state
    t.ok(Core.Submit(game, { kind = "Undock", actor = state.player.ship }))
    Core.Step(game)
    local den: State.Site? = nil
    for _, id in state.siteIds do
      local site = state.sites[id]
      den = den or (if site.kind == "combat" and site.system == 1 and not site.gone then site else nil)
    end
    if den == nil then
      continue
    end
    kept += 1
    den.depth = 1
    local place = assert(Space.Object(state, den.id))
    local ball = state.balls[state.player.ship]
    ball.x, ball.y, ball.z = place.x + 500, place.y, place.z
    Space.AssignGrid(state, ball)
    Core.TakeEvents(game)
    local first: string? = nil
    local others = 0
    for _ = 1, 3 do
      Core.Step(game)
      for _, event in Core.TakeEvents(game) do
        local ship = if event.kind == "BallAdded" then state.ships[event.ball] else nil
        if ship and ship.owner == "pirates" then
          others += if first then 1 else 0
          first = first or ship.name
        end
      end
    end
    t.eq(select(2, ungraded(first or "")), 2, `a stronghold's first keeper is a {first or "nobody"}`)
    t.ok(others >= 1, "a captain with nobody to command")
  end
  t.ok(kept >= 5, `{kept} dens in forty games`)
end)

suite:Case("a gate is watched only in lawless space, and not every time", function(t)
  local camps = 0
  for seed = 1, 30 do
    t.eq(#arrivals((at(t, seed, "secure", "gate"))), 0)
    t.eq(#arrivals((at(t, seed, "low", "gate"))), 0)
    local game = at(t, seed, "lawless", "gate")
    local waiting = arrivals(game)
    camps += if #waiting > 0 then 1 else 0
    t.ok(#waiting == 0 or #waiting == 3)
    -- (and an unwatched gate stays unwatched for a while)
    if #waiting == 0 then
      for _ = 1, 100 do
        Core.Step(game)
      end
      t.eq(#game.state.pilotIds, 0)
    end
  end
  t.ok(camps >= 5 and camps <= 20, `{camps} of 30 lawless gates were watched`)
end)

suite:Case("no pirates come in a peaceful game, to a capsule, or to a station", function(t)
  local game = at(t, 1, "lawless", "belt")
  game.state.peaceful = true
  t.eq(#arrivals(game), 0)
  local docked = at(t, 1, "lawless", "station")
  t.eq(#arrivals(docked), 0)
end)

suite:Case("a pirate's bounty and tags are its own, whatever it flies", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  t.ok(Core.Submit(game, { kind = "Undock", actor = state.player.ship }))
  Core.Step(game)
  local me = assert(Core.Query.Ball(game, state.player.ship))
  for _, kind in Pirates.kinds do
    local ball = Pirates.Spawn(state, kind, me.system, me.x + 5000, me.y, me.z, me.grid)
    local wallet = state.wallet
    Aftermath.Destroy(state, ball.id, state.player.ship, game.events)
    t.eq(state.wallet - wallet, kind.bounty)
    local wreck = state.wrecks[state.wreckIds[#state.wreckIds]]
    t.eq(wreck.hull, kind.hull)
    local tags = 0
    for _, item in Items.In(state, wreck.id, "cargo") do
      tags += if item.type == "tag.pirate" then item.quantity else 0
    end
    t.eq(tags, kind.tags)
  end
end)

suite:Case("a save from before pirates had bounties of their own keeps what they were worth", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local scout = Pirates.Spawn(state, Pirates.SCOUT, 1, 1e9, 0, 0, 0)
  local data, length = Core.Save(game)
  local file = Codec.Decode(data, length)
  file.saveVersion = 13
  for _, pilot in file.state.pilots do
    pilot.bounty, pilot.tags = nil, nil
  end
  for _, system in file.state.galaxy.systems do
    system.security = nil
  end
  local old, oldLength = Codec.Encode(file)
  local loaded = Core.Load(old, oldLength)
  local pilot: State.Pilot = loaded.state.pilots[scout.id]
  t.eq({ pilot.bounty, pilot.tags }, { math.floor(Ships.byId[Pirates.SCOUT.hull].basePrice * 0.2), 1 })
  for id, system in loaded.state.galaxy.systems do
    t.eq(system.security, state.galaxy.systems[id].security)
  end
  t.eq(loaded.state.galaxy.systems[1].security, 1)
end)

return suite
