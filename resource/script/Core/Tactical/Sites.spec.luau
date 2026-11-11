--!strict
-- Places that are on nobody's chart (Tactical/Sites).

local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Mining = require("@lt/Core/Tactical/Mining")
local Sites = require("@lt/Core/Tactical/Sites")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
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
    local here = Sites.In(state, 1)
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
    local listed, wait = Core.Query.Sites(game)
    t.eq({ #listed, wait }, { Sites.COUNT.secure, 0 })
    for _, row in listed do
      t.ok(row.found or (row.kind == "" and string.sub(row.name, 1, 7) == "Signal "), "an unfound site should say nothing of itself")
    end
  end
  t.ok((kinds.combat or 0) > 5 and (kinds.ore or 0) > 5 and (kinds.relic or 0) > 5, "a kind of site hardly ever turns up")
  -- (and the other kinds of space have more)
  local game = inSpace(1)
  for system = 2, 3 do
    local ball = game.state.balls[game.state.player.ship]
    ball.system = system
    Space.AssignGrid(game.state, ball)
    Core.Step(game)
    t.eq(#Sites.In(game.state, system), Sites.COUNT[Galaxy.Band(game.state.galaxy.systems[system].security)])
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

suite:Case("a derelict is too faint for the ship's scanner alone: a probe put out by its planet finds it, and makes every scan worth more", function(t)
  local game, site = first("relic")
  local state = game.state
  local ship = state.player.ship
  local me = state.balls[ship]
  -- From where the ship is, half way and no further.
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
  t.eq({ probes.here, probes.out, probes.max, probes.carried }, { 0, 0, Sites.PROBES, 0 })
  -- A probe wants one in the hold, and goes out where the ship is.
  t.eq({ Core.Validate(game, { kind = "LaunchProbe", actor = ship }) } :: { any }, { false, "no scan probe in the hold" } :: { any })
  t.eq({ Core.Validate(game, { kind = "RecallProbes", actor = ship }) } :: { any }, { false, "no probes are out in this system" } :: { any })
  Items.Add(state, Sites.PROBE, 6, ship, "cargo")
  t.ok(Core.Submit(game, { kind = "LaunchProbe", actor = ship }))
  Core.Step(game)
  t.eq({ #state.probeIds, select(3, Core.Query.Sites(game)).carried }, { 1, 5 })
  -- Out here it is nowhere near the signal, and helps not at all.
  t.ok((scan(game)))
  t.eq(site.strength, Sites.ALONE.relic)
  -- Taken to the planet the scanner named, one does: a scan is worth twice as much, and the cap is off.
  me.x, me.y, me.z = planet.x + planet.radius * 3, planet.y, planet.z
  Space.AssignGrid(state, me)
  t.ok(Core.Submit(game, { kind = "LaunchProbe", actor = ship }))
  Core.Step(game)
  me.x += 20 * 149597870700
  Space.AssignGrid(state, me)
  local near = Sites.Covered(state, site, me)
  t.eq(near, 1)
  t.ok((scan(game)))
  t.near(site.strength, math.min(1, Sites.ALONE.relic + 2 * Sites.Gain(state, "relic")), 1e-6)
  t.eq(site.strength, 1)
  -- Four out at most. Called in, those in this system are in the hold again.
  for _ = 1, 2 do
    t.ok(Core.Submit(game, { kind = "LaunchProbe", actor = ship }))
    Core.Step(game)
  end
  t.eq({ Core.Validate(game, { kind = "LaunchProbe", actor = ship }) } :: { any }, { false, `{Sites.PROBES} probes are out already` } :: { any })
  t.ok(Core.Submit(game, { kind = "RecallProbes", actor = ship }))
  Core.Step(game)
  t.eq({ #state.probeIds, select(3, Core.Query.Sites(game)).carried }, { 0, 6 })
  -- A probe lasts an hour, and is in the save meanwhile.
  t.ok(Core.Submit(game, { kind = "LaunchProbe", actor = ship }))
  Core.Step(game)
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq({ Core.Hash(loaded), #loaded.state.probeIds } :: { any }, { Core.Hash(game), 1 } :: { any })
  local lost = false
  for _ = 1, Sites.PROBE_LIFE + 2 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      lost = lost or event.kind == "ProbeLost"
    end
  end
  t.ok(lost and #state.probeIds == 0, "a probe outlasted its hour")
  local file = Codec.Decode(data, length)
  file.saveVersion = 33
  file.state.probes, file.state.probeIds = nil, nil
  local old, oldLength = Codec.Encode(file)
  t.eq(#Core.Load(old, oldLength).state.probeIds, 0)
end)

suite:Case("a probe by a hidden belt makes each scan of it worth as much again", function(t)
  local game, site = first("ore")
  local state = game.state
  local ship = state.player.ship
  local me = state.balls[ship]
  local place = assert(Space.Object(state, site.id))
  Items.Add(state, Sites.PROBE, 2, ship, "cargo")
  local from = { me.x, me.y, me.z }
  me.x, me.y, me.z = place.x + 5e7, place.y, place.z
  for _ = 1, 2 do
    t.ok(Core.Submit(game, { kind = "LaunchProbe", actor = ship }))
    Core.Step(game)
  end
  me.x, me.y, me.z = from[1] + 30 * 149597870700, from[2], from[3]
  Space.AssignGrid(state, me)
  t.eq(Sites.Covered(state, site, me), 2)
  t.ok((scan(game)))
  -- (three scans' worth in one: found at once)
  t.eq(site.strength, 1)
end)

return suite
