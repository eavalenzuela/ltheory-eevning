--!strict
-- Places that are on nobody's chart (Tactical/Sites).

local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Mining = require("@lt/Core/Tactical/Mining")
local Ores = require("@lt/Core/Data/Ores")
local Rng = require("@lt/Core/Kernel/Rng")
local Sites = require("@lt/Core/Tactical/Sites")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Sites")

-- A game with the pilot's ship in space, at rest, and the first look at
-- the system's sites taken. 'peaceful' unless said.
local function inSpace(historySeed: number, pirates: boolean?): Core.Game
  local game = Core.New({ galaxySeed = 1, historySeed = historySeed, peaceful = not pirates })
  assert(Core.Submit(game, { kind = "Undock", actor = game.state.player.ship }))
  Core.Step(game)
  assert(Core.Submit(game, { kind = "Stop", actor = game.state.player.ship }))
  Core.Step(game)
  return game
end

local function scan(game: Core.Game): (boolean, string?)
  local ok, why = Core.Submit(game, { kind = "Scan", actor = game.state.player.ship })
  -- (the order is carried out on the next tick, and the scanner is busy from then)
  for _ = 1, Sites.SCAN + 1 do
    Core.Step(game)
  end
  return ok, why
end

-- Put the pilot's ship at a place (the flight is Space's to test).
local function go(game: Core.Game, id: number)
  local state = game.state
  local place = assert(Space.Object(state, id))
  local ball = state.balls[state.player.ship]
  ball.system = id // 10000
  ball.x, ball.y, ball.z = place.x + 500, place.y, place.z
  Space.AssignGrid(state, ball)
  assert(ball.grid == id, "a site should be a grid of its own")
end

-- The first site of a kind in the pilot's system over some history
-- seeds: the game and the site.
local function first(kind: string, pirates: boolean?): (Core.Game, State.Site)
  for seed = 1, 60 do
    local game = inSpace(seed, pirates)
    for _, site in Sites.In(game.state, 1) do
      if site.kind == kind then
        return game, site
      end
    end
  end
  error(`no history seed up to 60 gives the first system a {kind} site`)
end

suite:Case("a system the pilot comes to has its sites, as many as its kind of space has, and they are not on the overview", function(t)
  local kinds: { [string]: number } = {}
  for seed = 1, 20 do
    local game = inSpace(seed)
    local state = game.state
    -- (a wormhole, on a day one is open there, is a signal and not one
    -- of the system's sites: Tactical/Wormholes)
    local here: { State.Site } = {}
    for _, site in Sites.In(state, 1) do
      if site.kind ~= "wormhole" then
        table.insert(here, site)
      end
    end
    t.eq(#here, Sites.COUNT.secure)
    for _, site in here do
      kinds[site.kind] = (kinds[site.kind] or 0) + 1
      local place = assert(Space.Object(state, site.id))
      t.eq({ place.kind, place.site, place.variety } :: { any }, { "belt", site.id, "site." .. site.kind } :: { any })
      -- A den is not hiding. The others are signals to be worked.
      t.eq(site.strength, if site.kind == "combat" then 1 else 0)
      t.ok(Sites.Hidden(state, site.id) == (site.kind ~= "combat"))
    end
    for _, entry in Core.Query.Overview(game) do
      local site = state.sites[entry.id]
      t.ok(site == nil or site.kind == "combat", `{entry.name} is on the overview unfound`)
      t.ok(entry.kind ~= "belt" or site == nil, "a site should not be listed as a belt")
      if site then
        t.eq(entry.kind, "site")
      end
    end
    -- (the scanner lists a wormhole among the signals, on a day one is open there)
    local listed, wait = Core.Query.Sites(game)
    t.eq({ #listed, wait }, { #Sites.In(state, 1), 0 })
    for _, row in listed do
      t.ok(row.found or (row.kind == "" and string.sub(row.name, 1, 7) == "Signal "), "an unfound site should say nothing of itself")
    end
  end
  t.ok((kinds.combat or 0) > 5 and (kinds.ore or 0) > 5 and (kinds.relic or 0) > 3, "a kind of site hardly ever turns up")
  -- (a vapour field and a listening post are the rare ones, and are there to be found all the same)
  t.ok((kinds.gas or 0) >= 1 and (kinds.data or 0) >= 1, `a kind of site never turns up: {kinds.gas or 0} gas, {kinds.data or 0} data`)
  print(`     sites: of 40 in safe space, {kinds.combat} dens, {kinds.ore} belts, {kinds.gas} fields, {kinds.relic} derelicts, {kinds.data} posts`)
  -- (and the other kinds of space have more)
  local game = inSpace(1)
  for system = 2, 3 do
    local ball = game.state.balls[game.state.player.ship]
    ball.system = system
    Space.AssignGrid(game.state, ball)
    Core.Step(game)
    -- (its own sites: a moon the pirates hold with a tower is a place of another kind)
    local own = 0
    for _, site in Sites.In(game.state, system) do
      own += if site.kind == "keep" then 0 else 1
    end
    t.eq(own, Sites.COUNT[Galaxy.Band(game.state.galaxy.systems[system].security)])
  end
end)

suite:Case("scanning brings every signal nearer, a scan at a time, and a found site can be warped to", function(t)
  local game, site = first("ore")
  local state = game.state
  local ship = state.player.ship
  t.eq({ Core.Validate(game, { kind = "WarpTo", actor = ship, target = site.id }) } :: { any }, { true } :: { any })
  local scans = 0
  while site.strength < 1 do
    scans += 1
    t.ok((scan(game)), "a scan was refused")
    t.ok(scans <= Sites.SCANS.ore, "a hidden belt took more scans than it should")
  end
  t.eq(scans, Sites.SCANS.ore)
  local listed = false
  for _, entry in Core.Query.Overview(game) do
    listed = listed or (entry.id == site.id and entry.kind == "site")
  end
  t.ok(listed, "a found site is not on the overview")
  -- The scanner takes a while, and skill makes a scan worth more.
  t.ok(Core.Submit(game, { kind = "Scan", actor = ship }))
  Core.Step(game)
  t.eq({ Core.Validate(game, { kind = "Scan", actor = ship }) } :: { any }, { false, "the scanner is still cycling" } :: { any })
  local _, wait = Core.Query.Sites(game)
  t.ok(wait > 0 and wait <= Sites.SCAN)
  state.skills.astrometrics = 5
  t.near(Sites.Gain(state, "ore"), 1.5 / Sites.SCANS.ore, 1e-6)
  t.eq(Sites.Gain(state, "combat"), 1)
  -- And so does a hull built for exploration: half as much again from the Orun's Falchion, and nothing from
  -- the Gladius it is made of.
  local seeker = Space.NewShip(state, "cruiser.falchion", "Seeker", "player", 0)
  local cruiser = Space.NewShip(state, "cruiser.gladius", "Plain", "player", 0)
  t.near(Sites.Gain(state, "ore", seeker.id), 1.5 * 1.5 / Sites.SCANS.ore, 1e-6)
  t.near(Sites.Gain(state, "ore", cruiser.id), 1.5 / Sites.SCANS.ore, 1e-6)
  t.eq(Sites.Gain(state, "combat", seeker.id), 1)
  -- Not from a station.
  local docked = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  t.eq({ Core.Validate(docked, { kind = "Scan", actor = docked.state.player.ship }) } :: { any }, { false, "docked" } :: { any })
end)

suite:Case("a derelict has hulls to loot, and is gone when they are empty", function(t)
  local game, site = first("relic")
  local state = game.state
  local hulls: { number } = {}
  for _, id in state.wreckIds do
    if state.wrecks[id].grid == site.id then
      table.insert(hulls, id)
      t.ok(#Items.In(state, id, "cargo") >= 3, "a derelict hull with next to nothing aboard")
      -- Each has a datacore or two (what an invention is worked out from),
      -- and nothing of the tech 2 make, which is nobody's to find.
      local datacores = 0
      for _, item in Items.In(state, id, "cargo") do
        datacores += if item.type == "datacore" then item.quantity else 0
        t.ok(string.sub(item.type, -3) ~= ".ii", `a derelict had a {item.type} aboard`)
      end
      t.ok(datacores >= 1 and datacores <= 2, `{datacores} datacores in a derelict hull where order is kept`)
    end
  end
  t.ok(#hulls >= 2 and #hulls <= 3)
  go(game, site.id)
  for _ = 1, Sites.CHECK + 5 do
    Core.Step(game)
  end
  t.ok(not site.gone)
  -- Emptied, it goes at the next look, once the pilot has left.
  for _, id in hulls do
    for _, item in Items.In(state, id, "cargo") do
      Items.Take(state, item, item.quantity)
    end
  end
  for _ = 1, Sites.CHECK + 5 do
    Core.Step(game)
  end
  t.ok(not site.gone, "a site went from under the pilot")
  go(game, state.player.home)
  for _ = 1, Sites.CHECK + 5 do
    Core.Step(game)
  end
  t.ok(site.gone)
  t.ok(Sites.Hidden(state, site.id))
  -- (and another comes in its place)
  t.eq(#Sites.In(state, 1), Sites.COUNT.secure)
end)

suite:Case("a hidden belt has big rocks, some of the rare ores, and can be mined out", function(t)
  local rare, rocks = 0, 0
  for seed = 1, 60 do
    local game = inSpace(seed)
    for _, site in Sites.In(game.state, 1) do
      if site.kind == "ore" then
        for _, object in Space.Describe(game.state, 1).objects do
          if object.kind == "asteroid" and object.site == site.id then
            rocks += 1
            rare += if object.variety == "ore.cobaltite" or object.variety == "ore.iridite" then 1 else 0
            t.ok(object.radius >= 500, "a hidden belt's rocks are big")
            t.ok(Mining.Left(game.state, object) > 0)
          end
        end
      end
    end
  end
  t.ok(rocks > 50)
  t.ok(rare > 0, "no hidden belt in secure space had any rare ore")
  t.ok(rare < rocks / 2)
end)

suite:Case("a vapour field has clouds of the one gas, a few kilometres apart, each holding what a cloud of its size does", function(t)
  local clouds, fields = 0, 0
  for seed = 1, 60 do
    local game = inSpace(seed)
    for _, site in Sites.In(game.state, 1) do
      if site.kind == "gas" then
        fields += 1
        local here, gas = 0, ""
        local place = assert(Space.Object(game.state, site.id))
        t.eq(string.sub(place.name, 1, 13), "Vapour Field ")
        for _, object in Space.Describe(game.state, 1).objects do
          if object.kind == "asteroid" and object.site == site.id then
            here += 1
            gas = if gas == "" then object.variety else gas
            t.eq(object.variety, gas, "a field of two gases")
            t.eq(object.name, assert(Ores.gasById[object.variety]).name)
            t.ok(Mining.Cloud(object) and not Mining.Rock(object))
            t.ok(object.radius >= 700 and object.radius <= 1300)
            t.eq(Mining.Left(game.state, object), math.floor(object.radius / 2))
            local far = math.sqrt((object.x - place.x) ^ 2 + (object.z - place.z) ^ 2)
            t.ok(far >= 3000 and far <= 9000, `a cloud {far} m from the middle of its field`)
          end
        end
        t.ok(here >= 4 and here <= 5, `{here} clouds in a field where order is kept`)
        clouds += here
      end
    end
  end
  t.ok(fields >= 3, `only {fields} vapour fields over 60 histories`)
  -- (a belt's rock is no cloud)
  local game = inSpace(1)
  for _, object in Space.Describe(game.state, 1).objects do
    if object.kind == "asteroid" and game.state.sites[object.site] == nil then
      t.ok(Mining.Rock(object) and not Mining.Cloud(object))
      break
    end
  end
end)

suite:Case("a cloud is drawn off with a gas harvester and nothing else, and a field with nothing left in it goes", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local ship = state.player.ship
  state.skills.mining = 2
  for _, item in Items.Fitted(state, ship) do
    if Modules.byId[item.type].weapon then
      Items.Take(state, item, 1)
    end
  end
  local harvester = Items.Equip(state, ship, "miner.gas", nil)
  local laser = Items.Equip(state, ship, "miner.small", nil)
  assert(Core.Submit(game, { kind = "Undock", actor = ship }))
  Core.Step(game)
  assert(Core.Submit(game, { kind = "Stop", actor = ship }))
  Core.Step(game)
  local site = assert(Sites.Plant(state, 1, "gas", Rng.For(3, 3), game.events))
  local clouds: { System.Object } = {}
  for _, object in Space.Describe(state, 1).objects do
    if object.site == site.id and object.kind == "asteroid" then
      table.insert(clouds, object)
    end
  end
  local cloud = clouds[1]
  local ball = state.balls[ship]
  -- Beside the first cloud: a kilometre off its edge.
  ball.x, ball.y, ball.z = cloud.x + cloud.radius + 1000, cloud.y, cloud.z
  ball.vx, ball.vy, ball.vz = 0, 0, 0
  Space.AssignGrid(state, ball)
  t.eq(ball.grid, site.id)
  -- On the overview here, as a rock is.
  local listed = false
  for _, entry in Core.Query.Overview(game) do
    listed = listed or (entry.id == cloud.id and entry.kind == "asteroid" and entry.variety == cloud.variety)
  end
  t.ok(listed, "a cloud should be on the overview of a ship in its field")
  local function refused(command: State.Command): string?
    local ok, why = Core.Validate(game, command)
    return if ok then "(accepted)" else why
  end
  t.eq(refused({ kind = "ActivateModule", actor = ship, item = harvester.id, target = cloud.id }), "no locked target")
  assert(Core.Submit(game, { kind = "LockTarget", actor = ship, target = cloud.id }))
  for _ = 1, 30 do
    Core.Step(game)
  end
  -- A laser that cuts rock does nothing to a cloud.
  t.eq(refused({ kind = "ActivateModule", actor = ship, item = laser.id, target = cloud.id }), "a cloud of gas wants a harvester")
  local whole = Mining.Left(state, cloud)
  assert(Core.Submit(game, { kind = "ActivateModule", actor = ship, item = harvester.id, target = cloud.id }))
  Core.TakeEvents(game)
  local mined: { [string]: any }? = nil
  local ticks = 0
  while mined == nil and ticks < 70 do
    Core.Step(game)
    ticks += 1
    for _, event in Core.TakeEvents(game) do
      mined = if event.kind == "Mined" then event else mined
    end
  end
  -- (50 m3 a minute of a gas at a cubic metre a unit, and a twentieth more for the second level of Mining)
  t.eq({ ticks, assert(mined).ore, assert(mined).units } :: { any }, { 61, cloud.variety, 52 } :: { any })
  t.eq(Mining.Left(state, cloud), whole - 52)
  local aboard = 0
  for _, item in Items.In(state, ship, "cargo") do
    aboard += if item.type == cloud.variety then item.quantity else 0
  end
  t.eq(aboard, 52)
  -- Too far off, it will not begin; and a harvester does nothing to a rock.
  assert(Core.Submit(game, { kind = "DeactivateModule", actor = ship, item = harvester.id }))
  for _ = 1, 70 do
    Core.Step(game)
  end
  ball.x += 3000
  t.eq(refused({ kind = "ActivateModule", actor = ship, item = harvester.id, target = cloud.id }), "too far from the cloud")
  ball.x -= 3000
  local rock: System.Object? = nil
  for _, object in Space.Describe(state, 1).objects do
    if Mining.Rock(object) then
      rock = object
      break
    end
  end
  t.eq(refused({ kind = "ActivateModule", actor = ship, item = harvester.id, target = assert(rock).id }), "no locked target")
  -- Nearly drawn off, the cycle takes what is left and the cloud is gone from the overview.
  Mining.Take(state, cloud, Mining.Left(state, cloud) - 5)
  assert(Core.Submit(game, { kind = "ActivateModule", actor = ship, item = harvester.id, target = cloud.id }))
  local stopped = ""
  for _ = 1, 70 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      stopped = if event.kind == "ModuleStopped" then event.reason else stopped
    end
  end
  t.eq({ Mining.Left(state, cloud), stopped } :: { any }, { 0, "the cloud is drawn off" } :: { any })
  t.eq(refused({ kind = "ActivateModule", actor = ship, item = harvester.id, target = cloud.id }), "that cloud is drawn off")
  -- With every cloud empty the field goes, once the pilot has left.
  for _, each in clouds do
    Mining.Take(state, each, Mining.Left(state, each))
  end
  go(game, state.player.home)
  for _ = 1, Sites.CHECK + 5 do
    Core.Step(game)
  end
  t.ok(site.gone, "a field with nothing in it is still there")
end)

suite:Case("a listening post has vaults, each locked with a vault's lock, with datacores and drawings in them and nothing that was fitted", function(t)
  local posts = 0
  for seed = 1, 60 do
    local game = inSpace(seed)
    local state = game.state
    for _, site in Sites.In(state, 1) do
      if site.kind == "data" then
        posts += 1
        t.eq(string.sub(assert(Space.Object(state, site.id)).name, 1, 15), "Listening Post ")
        -- (too faint for the ship's scanner alone, as a derelict is)
        t.eq({ Sites.ALONE.data, Sites.SCANS.data } :: { any }, { 0.5, 5 } :: { any })
        local vaults = 0
        for _, id in state.wreckIds do
          local wreck = state.wrecks[id]
          if wreck.grid == site.id then
            vaults += 1
            t.eq({ wreck.name, wreck.locked, wreck.lock, wreck.salvaged } :: { any }, { Sites.VAULT, true, "vault", true } :: { any })
            local datacores, drawings = 0, 0
            for _, item in Items.In(state, id, "cargo") do
              datacores += if item.type == "datacore" then item.quantity else 0
              drawings += if string.sub(item.type, 1, 10) == "blueprint." then item.quantity else 0
              t.ok(Modules.byId[item.type] == nil, `a vault had a {item.type} in it`)
              t.ok(string.sub(item.type, -3) ~= ".ii", `a vault had {item.type} in it before anybody opened its archive`)
            end
            t.ok(datacores >= 3 and datacores <= 5, `{datacores} datacores in a vault where order is kept`)
            t.ok(drawings >= 1 and drawings <= 2)
          end
        end
        t.ok(vaults >= 2 and vaults <= 3)
      end
    end
  end
  t.ok(posts >= 2, `only {posts} listening posts over 60 histories`)
end)

suite:Case("a den has the pirates' stores, and a tougher pack than the belts of its space", function(t)
  local game, site = first("combat", true)
  local state = game.state
  local stores = 0
  for _, id in state.wreckIds do
    local wreck = state.wrecks[id]
    if wreck.grid == site.id then
      stores += 1
      t.eq(wreck.name, "Pirate Stores")
      local tags, customs = 0, 0
      for _, item in Items.In(state, id, "cargo") do
        tags += if item.type == "tag.pirate" then item.quantity else 0
        local module = Modules.byId[item.type]
        customs += if module and module.meta then item.quantity else 0
        t.ok(module == nil or module.tech ~= 2, "a den's stores had a tech 2 module")
      end
      t.ok(tags >= 2)
      -- (and something the pack took that is better than it looks: a custom make)
      t.ok(customs >= 1, "a den's stores should have a custom module")
    end
  end
  t.eq(stores, 1)
  go(game, site.id)
  local names: { string } = {}
  for _ = 1, 3 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      if event.kind == "BallAdded" and state.ships[event.ball] and state.ships[event.ball].owner == "pirates" then
        table.insert(names, state.ships[event.ball].name)
      end
    end
  end
  t.ok(#names >= 2, `{#names} pirates at a den in secure space`)
  for _, name in names do
    t.ok(name ~= "Pirate Scout", "a den's pack should not be scouts")
  end
end)

suite:Case("a site lasts so long, sites are in the save, and an older save is given its own", function(t)
  local game = inSpace(4)
  local state = game.state
  local site = Sites.In(state, 1)[1]
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  for _ = 1, 700 do
    Core.Step(game)
    Core.Step(loaded)
  end
  t.eq(Core.Hash(loaded), Core.Hash(game))
  state.tick = site.expires + 1
  state.sitesDue[1] = 0
  Core.Step(game)
  t.ok(site.gone, "a site outlasted its time")

  local fresh = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local saved, savedLength = Core.Save(fresh)
  local file = Codec.Decode(saved, savedLength)
  file.saveVersion = 18
  for _, name in { "sites", "siteIds", "sitesDue", "sitesSeen", "scanReady" } do
    file.state[name] = nil
  end
  local old, oldLength = Codec.Encode(file)
  local before = Core.Load(old, oldLength)
  t.eq(#before.state.siteIds, 0)
  Core.Step(before)
  t.eq(#Sites.In(before.state, 1), Sites.COUNT.secure)
end)

suite:Case("a den's stores, emptied, now and then give away a stronghold a jump off: found already, richer, and the end of the trail", function(t)
  local led, quiet = 0, 0
  for seed = 1, 60 do
    local game = inSpace(seed)
    local state = game.state
    local den: State.Site? = nil
    for _, site in Sites.In(state, 1) do
      den = den or (if site.kind == "combat" then site else nil)
    end
    if den then
      go(game, den.id)
      local me = state.balls[state.player.ship]
      local stores: State.Wreck? = nil
      for _, id in state.wreckIds do
        if state.wrecks[id].grid == den.id then
          stores = state.wrecks[id]
        end
      end
      local wreck = assert(stores, "a den with no stores")
      -- (all but the tags are put over the side, so that the rest fits a Courier's hold)
      for _, item in Items.In(state, wreck.id, "cargo") do
        if item.type ~= "tag.pirate" then
          Items.Take(state, item, item.quantity)
        end
      end
      me.x, me.y, me.z = wreck.x + 500, wreck.y, wreck.z
      Core.TakeEvents(game)
      t.ok(Core.Submit(game, { kind = "Loot", actor = me.id, target = wreck.id }))
      Core.Step(game)
      t.eq(den.led, true)
      local trail: { [string]: any }? = nil
      for _, event in Core.TakeEvents(game) do
        trail = trail or (if event.kind == "TrailFound" then event else nil)
      end
      if trail then
        led += 1
        local stronghold = state.sites[trail.site]
        t.eq({ stronghold.kind, stronghold.depth, stronghold.strength, stronghold.gone, trail.from } :: { any },
          { "combat", 1, 1, false, den.id } :: { any })
        -- In the least safe system a jump away (the den's own was a homeworld's).
        local least = 1
        for _, neighbor in state.galaxy.systems[1].neighbors do
          least = if state.galaxy.systems[neighbor].security < state.galaxy.systems[least].security then neighbor else least
        end
        t.eq({ stronghold.system, trail.system }, { least, least })
        local place = assert(Space.Object(state, stronghold.id))
        t.ok(string.sub(place.name, 1, 17) == "Pirate Stronghold" and trail.name == place.name)
        -- Its stores hold three times what a den's would there.
        local tags, customs = 0, 0
        for _, id in state.wreckIds do
          if state.wrecks[id].grid == stronghold.id then
            for _, item in Items.In(state, id, "cargo") do
              tags += if item.type == "tag.pirate" then item.quantity else 0
              local module = Modules.byId[item.type]
              customs += if module and module.meta then item.quantity else 0
            end
          end
        end
        t.ok(customs >= 3, `a stronghold's stores had {customs} custom modules`)
        local band = Galaxy.Band(state.galaxy.systems[least].security)
        t.eq(tags, 2 * 3 * (if band == "secure" then 1 elseif band == "low" then 2 else 4))
        -- And it leads nowhere further, however often it is asked.
        Sites.Lead(state, stronghold, game.events)
        t.eq(stronghold.led, false)
        for _, event in Core.TakeEvents(game) do
          t.ok(event.kind ~= "TrailFound", "a stronghold led on to another")
        end
      else
        quiet += 1
      end
      -- (asked again, a den has nothing more to say)
      local sites = #state.siteIds
      Sites.Lead(state, den, game.events)
      t.eq(#state.siteIds, sites)
    end
  end
  t.ok(led >= 3 and quiet >= 3, `{led} dens led on to a stronghold and {quiet} did not`)
  t.ok(led < quiet * 2, "about two dens in five should lead somewhere")
  -- A save from before there were strongholds: its sites are none, and have led nowhere.
  local game = inSpace(1)
  local data, length = Core.Save(game)
  local file = Codec.Decode(data, length)
  file.saveVersion = 31
  for _, site in file.state.sites do
    site.depth, site.led = nil, nil
  end
  local old, oldLength = Codec.Encode(file)
  t.eq(Core.Hash(Core.Load(old, oldLength)), Core.Hash(game))
end)

-- Steps until the pilot's probes have all got where they were going.
local function settle(game: Core.Game)
  for _ = 1, 200 do
    local moving = false
    for _, id in game.state.probeIds do
      moving = moving or game.state.probes[id].tx ~= nil
    end
    if not moving then
      return
    end
    Core.Step(game)
  end
  error("the probes never got there")
end

suite:Case("probes want a launcher and probes in the hold: put out at once round the ship, called in, an hour long, and kept in a save", function(t)
  -- (the owner, 2026-11-18: "Probe launcher module")
  local game, site = first("relic")
  local state = game.state
  local ship = state.player.ship
  local me = state.balls[ship]
  -- The ship's scanner alone gets a derelict half way, and says which planet it is by.
  for _ = 1, 6 do
    t.ok((scan(game)))
  end
  t.eq(site.strength, Sites.ALONE.relic)
  local rows, _, probes = Core.Query.Sites(game)
  local row: Core.SiteStatus? = nil
  for _, each in rows do
    row = row or (if each.id == site.id then each else nil)
  end
  local shown = assert(row)
  local place = assert(Space.Object(state, site.id))
  local planet = assert(Space.Object(state, place.parent))
  t.eq({ shown.found, shown.faint, shown.near, shown.probes } :: { any }, { false, true, planet.name, 0 } :: { any })
  t.eq({ probes.here, probes.out, probes.max, probes.carried, probes.range, probes.launcher } :: { any },
    { 0, 0, Sites.PROBES, 0, Sites.RANGE, "" } :: { any })
  -- A launcher, and probes in the hold.
  t.eq({ Core.Validate(game, { kind = "LaunchProbe", actor = ship }) } :: { any }, { false, "no probe launcher fitted" } :: { any })
  Items.Equip(state, ship, "scanner.probe")
  t.eq({ Core.Validate(game, { kind = "LaunchProbe", actor = ship }) } :: { any }, { false, "no scan probe in the hold" } :: { any })
  t.eq({ Core.Validate(game, { kind = "RecallProbes", actor = ship }) } :: { any }, { false, "no probes are out in this system" } :: { any })
  Items.Add(state, Sites.PROBE, 10, ship, "cargo")
  -- All that may be out go out at once, and fly from the ship to the corners of a box round it.
  t.ok(Core.Submit(game, { kind = "LaunchProbe", actor = ship }))
  Core.Step(game)
  t.eq({ #state.probeIds, select(3, Core.Query.Sites(game)).carried }, { Sites.PROBES, 2 })
  settle(game)
  for _, id in state.probeIds do
    t.eq(state.probes[id].strength, 1)
  end
  local reach = Sites.Reach(state)
  for _, id in state.probeIds do
    local probe = state.probes[id]
    local d = math.sqrt((probe.x - me.x) ^ 2 + (probe.y - me.y) ^ 2 + (probe.z - me.z) ^ 2)
    t.near(d / reach, 0.5, 1e-6)
  end
  t.eq({ Core.Validate(game, { kind = "LaunchProbe", actor = ship }) } :: { any }, { false, `{Sites.PROBES} probes are out already` } :: { any })
  -- Called in, those in this system are in the hold again.
  t.ok(Core.Submit(game, { kind = "RecallProbes", actor = ship }))
  Core.Step(game)
  t.eq({ #state.probeIds, select(3, Core.Query.Sites(game)).carried }, { 0, 10 })
  -- (a Scan Rangefinding Array fitted: the next ones launched the stronger, 2026-11-20)
  Items.Equip(state, ship, "scan.rangefinder")
  t.ok(Core.Submit(game, { kind = "LaunchProbe", actor = ship }))
  Core.Step(game)
  for _, id in state.probeIds do
    t.near(state.probes[id].strength, 1.1, 1e-9)
  end
  t.ok(Core.Submit(game, { kind = "RecallProbes", actor = ship }))
  Core.Step(game)
  -- A probe lasts an hour, and is in the save meanwhile.
  t.ok(Core.Submit(game, { kind = "LaunchProbe", actor = ship }))
  Core.Step(game)
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq({ Core.Hash(loaded), #loaded.state.probeIds } :: { any }, { Core.Hash(game), Sites.PROBES } :: { any })
  local lost = 0
  for _ = 1, Sites.PROBE_LIFE + 2 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      lost += if event.kind == "ProbeLost" then 1 else 0
    end
  end
  t.ok(lost == Sites.PROBES and #state.probeIds == 0, "a probe outlasted its hour")
  -- A save from before probes were put anywhere: its probes read as a plain launcher's, and reach as a new pilot's.
  local file = Codec.Decode(data, length)
  file.saveVersion = 87
  file.state.probeRange = nil
  for _, probe in file.state.probes do
    probe.strength, probe.tx, probe.ty, probe.tz = nil, nil, nil, nil
  end
  local old, oldLength = Codec.Encode(file)
  local migrated = Core.Load(old, oldLength).state
  t.eq(migrated.probeRange, Sites.RANGE)
  for _, id in migrated.probeIds do
    t.eq(migrated.probes[id].strength, 1)
  end
  -- And one from before there were probes at all.
  file.saveVersion = 33
  file.state.probes, file.state.probeIds = nil, nil
  old, oldLength = Codec.Encode(file)
  t.eq(#Core.Load(old, oldLength).state.probeIds, 0)
end)

suite:Case("where a signal may be is known by how many probes reach it: a sphere, a ring, two points, a point in a ring", function(t)
  -- (the owner, 2026-11-18: "Geometry, per scan". Plain numbers here: a
  -- vector is too coarse at the size of a system)
  local game, site = first("relic")
  local state = game.state
  local place = assert(Space.Object(state, site.id))
  local AU = 149597870700
  local function gap(x: number, y: number, z: number): number
    return math.sqrt((x - place.x) ^ 2 + (y - place.y) ^ 2 + (z - place.z) ^ 2) / AU
  end
  -- Probes put down by hand, each as far from the signal as its offset (AU) says.
  local function put(offsets: { { number } })
    state.probes, state.probeIds = {}, {}
    for _, offset in offsets do
      local probe: State.Probe = { id = State.NewId(state), system = site.system, x = place.x + offset[1] * AU,
        y = place.y + offset[2] * AU, z = place.z + offset[3] * AU, expires = state.tick + 100, strength = 1 }
      state.probes[probe.id] = probe
      table.insert(state.probeIds, probe.id)
    end
  end
  state.probeRange = 4
  -- One: on a sphere round it, as far out as it is.
  put({ { 1, 0.2, 0 } })
  local reading = Sites.Read(state, site)
  local scan = assert(site.scan)
  t.eq(scan.probes, 1)
  t.ok(reading > 0 and reading <= Sites.CAPS[1], `one probe read {reading}`)
  t.near(scan.radius / AU, math.sqrt(1.04), 1e-9)
  -- Two: on the ring where their spheres meet; the signal is on it.
  put({ { 1, 0, 0 }, { -0.5, 0.5, 1 } })
  reading = Sites.Read(state, site)
  scan = assert(site.scan)
  t.ok(scan.probes == 2 and reading <= Sites.CAPS[2])
  local ox, oy, oz = place.x - scan.x, place.y - scan.y, place.z - scan.z
  t.near((ox * scan.nx + oy * scan.ny + oz * scan.nz) / AU, 0, 1e-9)
  t.near(math.sqrt(ox * ox + oy * oy + oz * oz) / scan.radius, 1, 1e-9)
  -- Three: at one of two points, and it is the first.
  put({ { 1, 0, 0 }, { 0, 0.3, 1 }, { -1, -0.2, 0.2 } })
  reading = Sites.Read(state, site)
  scan = assert(site.scan)
  t.ok(scan.probes == 3 and reading <= Sites.CAPS[3])
  t.near(gap(scan.x, scan.y, scan.z), 0, 1e-9)
  t.ok(gap(scan.ox, scan.oy, scan.oz) > 0.01, "the other point is the same point")
  -- Four or more: within a ring round a point.
  put({ { 1, 0, 0 }, { 0, 0.3, 1 }, { -1, -0.2, 0.2 }, { 0, -0.4, -1 } })
  reading = Sites.Read(state, site)
  scan = assert(site.scan)
  t.ok(scan.probes == 4 and reading < 1)
  t.ok(gap(scan.x, scan.y, scan.z) <= scan.radius / AU + 1e-9, "the signal is outside the ring")
  -- A box of eight close round it at a small reach: all of it read, and the ring is nothing.
  state.probeRange = 0.25
  local box: { { number } } = {}
  for index = 1, 8 do
    local cx, cy, cz = Sites.Corner(index, Sites.Reach(state))
    table.insert(box, { cx / AU, cy / AU, cz / AU })
  end
  put(box)
  t.eq(Sites.Read(state, site), 1)
  t.eq(assert(site.scan).radius, 0)
  -- Out of reach of them all: nothing is read, and nothing is kept of the last.
  put({ { 3, 0, 0 } })
  t.eq(Sites.Read(state, site), 0)
  t.eq(site.scan, nil)
end)

suite:Case("probes are sent anywhere, one or all of them; and a scan finds with them what the ship's scanner cannot", function(t)
  local game, site = first("relic")
  local state = game.state
  local ship = state.player.ship
  local place = assert(Space.Object(state, site.id))
  Items.Equip(state, ship, "scanner.probe")
  Items.Add(state, Sites.PROBE, 8, ship, "cargo")
  t.ok(Core.Submit(game, { kind = "LaunchProbe", actor = ship }))
  Core.Step(game)
  settle(game)
  -- One by itself, and only to a probe out here, and not past the edge of things.
  local first = state.probeIds[1]
  t.eq({ Core.Validate(game, { kind = "MoveProbes", actor = ship, target = 999999, x = 0, y = 0, z = 0 }) } :: { any },
    { false, "no such probe here" } :: { any })
  t.eq({ Core.Validate(game, { kind = "MoveProbes", actor = ship, target = 0, x = 1e15, y = 0, z = 0 }) } :: { any },
    { false, "too far out" } :: { any })
  t.ok(Core.Submit(game, { kind = "MoveProbes", actor = ship, target = first, x = place.x, y = place.y, z = place.z }))
  Core.Step(game)
  settle(game)
  local probe = state.probes[first]
  t.eq({ probe.x, probe.y, probe.z }, { place.x, place.y, place.z })
  -- All of them, their middle to the signal: at the reach a new pilot's
  -- have, they read it, and do not find it.
  t.ok(Core.Submit(game, { kind = "FormProbes", actor = ship }))
  Core.Step(game)
  t.ok(Core.Submit(game, { kind = "MoveProbes", actor = ship, target = 0, x = place.x, y = place.y, z = place.z }))
  Core.Step(game)
  settle(game)
  local mx, my, mz = Sites.Middle(state, site.system)
  t.near(math.sqrt((mx - place.x) ^ 2 + (my - place.y) ^ 2 + (mz - place.z) ^ 2), 0, 1)
  t.ok((scan(game)))
  local reading = assert(site.scan).reading
  t.ok(reading > 0 and reading < 1 and site.strength < 1, `read {reading} of it at {Sites.RANGE} AU`)
  t.eq(assert(site.scan).probes, Sites.PROBES)
  -- Their reach made small and the box formed again round it: found.
  t.eq({ Core.Validate(game, { kind = "ProbeRange", actor = ship, quantity = 3 }) } :: { any }, { false, "no such reach" } :: { any })
  t.ok(Core.Submit(game, { kind = "ProbeRange", actor = ship, quantity = 0.5 }))
  Core.Step(game)
  t.ok(Core.Submit(game, { kind = "FormProbes", actor = ship }))
  Core.Step(game)
  settle(game)
  t.ok((scan(game)))
  t.eq(site.strength, 1)
  t.ok(not Sites.Hidden(state, site.id), "found, it is on the overview")
end)

suite:Case("a probe launcher is easier to fit on a hull built to explore; the tech 2 one's probes read a quarter more", function(t)
  local Attributes = require("@lt/Core/Attributes")
  local Ships = require("@lt/Core/Data/Ships")
  local plain = Modules.byId["scanner.probe"]
  local better = assert(Modules.Improved("scanner.probe"))
  t.eq({ assert(plain.probes).strength, assert(better.probes).strength }, { 1, 1.25 })
  local explorer: Ships.ShipType? = nil
  local other: Ships.ShipType? = nil
  for _, hull in Ships.list do
    if hull.explorer then
      explorer = explorer or hull
    elseif hull.class == "frigate" then
      other = other or hull
    end
  end
  local cpu = Attributes.Needs(assert(other), plain)
  local easy = Attributes.Needs(assert(explorer), plain)
  t.eq({ cpu, easy }, { plain.cpu, plain.cpu * Ships.PROBE_FITTING })
end)

return suite
