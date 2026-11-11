--!strict
-- Pirates (Tactical/Pirates): what they fly, and what comes where.

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Dogma = require("@lt/Core/Dogma")
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

suite:Case("every kind of pirate flies an Unbound hull with a fit the hull takes, its weapons loaded", function(t)
  for _, kind in Pirates.kinds do
    local hull = Ships.byId[kind.hull]
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
    t.ok((Dogma.Check(hull, types)), `{kind.name}'s fit does not go on its hull`)
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
    -- (a mender is not one of the ladder: it is there for the others)
    if kind.id == "mender" then
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
    for _, name in low do
      t.ok(name == "Pirate Raider" or name == "Pirate Jackal", `{name} in low security`)
    end
    for _, name in lawless do
      t.ok(name ~= "Pirate Scout", "a scout in lawless space")
      seen[name] = true
    end
  end
  t.ok(seen["Pirate Marauder"], "twelve packs in lawless space and no cruiser among them")
  t.ok(seen["Pirate Jackal"] and seen["Pirate Raider"])
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
