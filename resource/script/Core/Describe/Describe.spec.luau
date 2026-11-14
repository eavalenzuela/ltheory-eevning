--!strict
local Codec = require("@lt/Core/Persist/Codec")
local Constants = require("@lt/Core/Data/Constants")
local Factions = require("@lt/Core/Data/Factions")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Names = require("@lt/Core/Describe/Names")
local Rng = require("@lt/Core/Kernel/Rng")
local System = require("@lt/Core/Describe/System")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Describe")
local AU = Constants.AU

suite:Case("a galaxy is a function of its seed", function(t)
  t.eq(Galaxy.Describe(7, 40), Galaxy.Describe(7, 40))
  t.ok(Codec.HashOf(Galaxy.Describe(7, 40)) ~= Codec.HashOf(Galaxy.Describe(8, 40)), "seeds 7 and 8 gave the same galaxy")
end)

suite:Case("every system can be reached, and gates run both ways", function(t)
  for _, count in { 1, 2, 3, 40, 400 } do
    local galaxy = Galaxy.Describe(3, count)
    t.eq(#galaxy.systems, count)
    local seen = { [1] = true }
    local frontier = { 1 }
    local reached = 1
    while #frontier > 0 do
      local id = table.remove(frontier) :: number
      for _, other in galaxy.systems[id].neighbors do
        t.ok(table.find(galaxy.systems[other].neighbors, id), `gate {id} -> {other} has no return`)
        if not seen[other] then
          seen[other] = true
          reached += 1
          table.insert(frontier, other)
        end
      end
    end
    t.eq(reached, count, `{count} systems`)
    local names: { [string]: boolean } = {}
    for _, system in galaxy.systems do
      t.ok(not names[system.name], `two systems are called {system.name}`)
      names[system.name] = true
    end
  end
end)

suite:Case("a system is a function of the galaxy seed and its id", function(t)
  local galaxy = Galaxy.Describe(7, 12)
  t.eq(System.Describe(galaxy, 5), System.Describe(galaxy, 5))
  t.ok(Codec.HashOf(System.Describe(galaxy, 5)) ~= Codec.HashOf(System.Describe(galaxy, 6)))
  -- and it is plain data the save can hold
  Codec.Encode(System.Describe(galaxy, 5))
end)

suite:Case("systems are laid out sanely at astronomical scale", function(t)
  local galaxy = Galaxy.Describe(11, 30)
  for id = 1, 30 do
    local description = System.Describe(galaxy, id)
    local byId: { [number]: System.Object } = {}
    local stations, gates, lastOrbit = 0, 0, 0
    for index, object in description.objects do
      t.eq(object.id, id * Constants.STRUCTURE_ID_SPAN + index, "ids follow the index")
      byId[object.id] = object
    end
    t.eq(description.objects[1].kind, "sun")
    t.eq({ description.objects[1].x, description.objects[1].y, description.objects[1].z }, { 0, 0, 0 })
    for _, object in description.objects do
      local where = `{object.name} in system {id}`
      if object.kind == "planet" then
        local orbit = math.sqrt(object.x ^ 2 + object.z ^ 2)
        t.ok(orbit > lastOrbit, `{where} is not outside the planet before it`)
        t.ok(orbit > 0.25 * AU and orbit < 400 * AU, `{where} orbits at {orbit / AU} AU`)
        lastOrbit = orbit
      elseif object.kind == "station" then
        stations += 1
        local host = byId[object.parent]
        local gap = math.sqrt((object.x - host.x) ^ 2 + (object.y - host.y) ^ 2 + (object.z - host.z) ^ 2)
          - host.radius - object.radius
        t.ok(gap > host.radius, `{where} is {gap} m off the surface of {host.name}`)
        t.eq(object.site, object.id)
      elseif object.kind == "gate" then
        gates += 1
        t.ok(table.find(galaxy.systems[id].neighbors, object.to), `{where} leads nowhere`)
        t.ok(System.GateTo(System.Describe(galaxy, object.to), id), `{where} has no gate coming back`)
        t.ok(math.sqrt(object.x ^ 2 + object.z ^ 2) > lastOrbit, `{where} is inside the planets`)
      elseif object.kind == "asteroid" then
        local belt = byId[object.parent]
        t.eq(belt.kind, "belt")
        t.eq(object.site, belt.id)
        local d = math.sqrt((object.x - belt.x) ^ 2 + (object.y - belt.y) ^ 2 + (object.z - belt.z) ^ 2)
        t.ok(d > 9000 and d < 22000, `{where} is {d} m from its belt`)
      elseif object.kind == "moon" then
        local planet = byId[object.parent]
        local d = math.sqrt((object.x - planet.x) ^ 2 + (object.y - planet.y) ^ 2 + (object.z - planet.z) ^ 2)
        t.ok(d > planet.radius * 10, `{where} is too close to {planet.name}`)
      end
    end
    t.ok(stations >= 1, `system {id} has no station`)
    t.eq(gates, #galaxy.systems[id].neighbors, `system {id}: one gate per neighbour`)
  end
end)

suite:Case("space is safest where a pilot starts, and every galaxy of three or more has somewhere lawless", function(t)
  for seed = 1, 20 do
    for _, count in { 1, 2, 3, 8, 40 } do
      local galaxy = Galaxy.Describe(seed, count)
      t.eq(galaxy.systems[1].security, 1)
      local lawless = 0
      for _, system in galaxy.systems do
        t.ok(system.security >= 0 and system.security <= 1, `seed {seed}: a security of {system.security}`)
        lawless += if Galaxy.Band(system.security) == "lawless" then 1 else 0
        -- (it never rises by more than a band's worth in one jump out of safety:
        -- no neighbour of the first system is lawless unless the galaxy is tiny)
      end
      if count >= 3 then
        t.ok(lawless >= 1, `seed {seed}, {count} systems: nowhere is lawless`)
      end
      if count >= 2 then
        t.ok(lawless < count, `seed {seed}, {count} systems: everywhere is lawless`)
      end
    end
  end
  t.eq({ Galaxy.Band(1), Galaxy.Band(0.7), Galaxy.Band(0.5), Galaxy.Band(0.29), Galaxy.Band(0) } :: { any },
    { "secure", "secure", "low", "lawless", "lawless" } :: { any })
end)

suite:Case("the rare ores are in the belts of lawless space and nowhere else", function(t)
  local wild, tame = 0, 0
  for seed = 1, 12 do
    local galaxy = Galaxy.Describe(seed, 3)
    for id = 1, 3 do
      local lawless = Galaxy.Band(galaxy.systems[id].security) == "lawless"
      for _, object in System.Describe(galaxy, id).objects do
        if object.kind == "asteroid" then
          local rare = object.variety == "ore.cobaltite" or object.variety == "ore.iridite"
          if lawless then
            wild += if rare then 1 else 0
            tame += if rare then 0 else 1
          else
            t.ok(not rare, `seed {seed}: {object.variety} in a system of security {galaxy.systems[id].security}`)
          end
        end
      end
    end
  end
  t.ok(wild > 20, `only {wild} rocks of rare ore in twelve lawless systems`)
  t.ok(tame > wild, "lawless belts are mostly rare ore")
end)

suite:Case("every faction has a homeworld and as much space as any other, of a piece where the gates allow; and nobody holds the rest", function(t)
  local shutIn, heldInAll = 0, 0
  for seed = 1, 8 do
    for _, count in { 3, 12, 40, 100, 400 } do
      local galaxy = Galaxy.Describe(seed, count)
      local systems = galaxy.systems
      local factions = math.clamp(count // Galaxy.SYSTEMS_A_FACTION, 1, #Factions.list)
      local each = math.max(1, math.min(Galaxy.TERRITORY, math.floor(count * Galaxy.CLAIMED / factions)))
      local homes: { [string]: number } = {}
      local held: { [string]: number } = {}
      for _, system in systems do
        -- (whose towers its stations are: people's, and the holder's if the holder is people)
        local builds = Factions.byId[system.nearest]
        t.ok(builds ~= nil and builds.kind == "human", `seed {seed}: the stations of system {system.id} are nobody's`)
        if system.home then
          t.eq(system.hops, 0)
          t.eq(homes[system.owner], nil)
          homes[system.owner] = system.id
        end
        if system.owner ~= "" then
          held[system.owner] = (held[system.owner] or 0) + 1
          if Factions.byId[system.owner].kind == "human" then
            t.eq(system.nearest, system.owner)
          end
          if Galaxy.KeepsOrder(system.owner) then
            t.ok(system.security >= 0.3, `seed {seed}: held space with a security of {system.security}`)
            t.ok(not system.home or system.security == 1, `seed {seed}: a homeworld with a security of {system.security}`)
            t.eq(Galaxy.Keeper(system), system.owner)
          else
            -- (the pirates hold what they hold, and keep no order in it)
            t.eq({ system.security, Galaxy.Keeper(system) } :: { any }, { 0, "" } :: { any })
          end
        else
          t.eq({ system.security, Galaxy.Keeper(system), system.home } :: { any }, { 0, "", false } :: { any })
        end
      end
      -- The first factions of the list, the first of them at the first
      -- system, and every one with as much as any other.
      local holders: { string } = {}
      for index, faction in Factions.list do
        if index <= factions then
          t.ok(homes[faction.id] ~= nil, `seed {seed}, {count} systems: {faction.id} has no homeworld`)
          t.eq(held[faction.id], each, `seed {seed}, {count} systems: what {faction.id} holds`)
          table.insert(holders, faction.id)
        else
          t.eq({ homes[faction.id], held[faction.id] } :: { any }, {})
        end
      end
      t.eq(homes[Factions.list[1].id], 1)
      t.eq(Galaxy.Holders(galaxy), holders)
      -- (and nobody's homeworld is next door to another's)
      for _, system in systems do
        if system.home then
          for _, neighbor in system.neighbors do
            t.ok(not systems[neighbor].home, `seed {seed}, {count} systems: two homeworlds a jump apart`)
          end
        end
      end
      -- A faction's space is all of a piece: from its homeworld every
      -- system of its own is reached through its own. And going away from
      -- home through it, it never gets safer.
      for _, faction in holders do
        local within: { [number]: number } = { [homes[faction]] = 0 }
        local queue = { homes[faction] }
        local at = 1
        while at <= #queue do
          local id = queue[at]
          at += 1
          for _, neighbor in systems[id].neighbors do
            if systems[neighbor].owner == faction and within[neighbor] == nil then
              within[neighbor] = within[id] + 1
              table.insert(queue, neighbor)
            end
          end
        end
        heldInAll += each
        shutIn += each - #queue
        for _, id in queue do
          for _, neighbor in systems[id].neighbors do
            if within[neighbor] and within[neighbor] > within[id] then
              t.ok(systems[neighbor].security <= systems[id].security, `seed {seed}: it gets safer going away from home`)
            end
          end
        end
      end
    end
  end
  -- (a faction shut in, with every gate out of what it holds leading
  -- into another's space, takes the nearest system nobody has and goes
  -- on from there: its space is then in two pieces. The gates being
  -- what they are, with few ways round, that is a few systems in a
  -- hundred in galaxies as crowded as these.)
  t.ok(shutIn <= heldInAll * 0.06, `{shutIn} of {heldInAll} held systems are cut off from their homeworlds`)
  print(`     claim: {shutIn} of {heldInAll} held systems are cut off from their own homeworld`)
end)

suite:Case("in a galaxy with room for it a faction holds ninety systems, from a homeworld of five gates a hundred light years from any other", function(t)
  for seed = 1, 3 do
    local galaxy = Galaxy.Describe(seed, 2000)
    local systems = galaxy.systems
    local homes: { number } = {}
    local held: { [string]: number } = {}
    for id, system in systems do
      if system.home then
        table.insert(homes, id)
      end
      if system.owner ~= "" then
        held[system.owner] = (held[system.owner] or 0) + 1
      end
    end
    t.eq(#homes, #Factions.list)
    for _, faction in Factions.list do
      t.eq(held[faction.id], Galaxy.TERRITORY, `seed {seed}: what {faction.id} holds`)
    end
    for index, home in homes do
      t.ok(#systems[home].neighbors >= Galaxy.HOME_GATES, `seed {seed}: a homeworld with {#systems[home].neighbors} gates`)
      for other = index + 1, #homes do
        local far = math.sqrt((systems[home].x - systems[homes[other]].x) ^ 2 + (systems[home].y - systems[homes[other]].y) ^ 2)
        t.ok(far >= Galaxy.HOME_APART, `seed {seed}: two homeworlds {far} light years apart`)
      end
    end
  end
  -- It follows from the seed, and is the same however often it is worked out.
  local a, b = Galaxy.Describe(4, 400), Galaxy.Describe(4, 400)
  Galaxy.Claim(b)
  t.eq(Codec.HashOf(a), Codec.HashOf(b))
end)

suite:Case("a route is the fewest jumps, or the safest way", function(t)
  for seed = 1, 6 do
    local galaxy = Galaxy.Describe(seed, 60)
    local systems = galaxy.systems
    -- Jumps from the first system, and jumps from it without entering
    -- lawless space (-1: there is no such way).
    local function hops(lawless: boolean): { number }
      local found: { number } = table.create(#systems, -1)
      found[1] = 0
      local queue = { 1 }
      local at = 1
      while at <= #queue do
        local id = queue[at]
        at += 1
        for _, neighbor in systems[id].neighbors do
          if found[neighbor] < 0 and (lawless or Galaxy.Band(systems[neighbor].security) ~= "lawless") then
            found[neighbor] = found[id] + 1
            table.insert(queue, neighbor)
          end
        end
      end
      return found
    end
    local any, kept = hops(true), hops(false)
    for to = 1, #systems do
      for _, safest in { false, true } do
        local route = Galaxy.Route(galaxy, 1, to, safest)
        t.eq({ route[1], route[#route] }, { 1, to })
        local wild = 0
        for index = 2, #route do
          t.ok(table.find(systems[route[index - 1]].neighbors, route[index]) ~= nil, `seed {seed}: a route jumps where there is no gate`)
          wild += if Galaxy.Band(systems[route[index]].security) == "lawless" then 1 else 0
        end
        if not safest then
          t.eq(#route - 1, any[to])
        elseif kept[to] >= 0 then
          t.eq(wild, 0)
        end
        t.ok(#route - 1 >= any[to])
      end
    end
    t.eq(Galaxy.Route(galaxy, 5, 5), { 5 })
    -- (and it is the same way every time it is asked for)
    t.eq(Galaxy.Route(galaxy, 2, 57, true), Galaxy.Route(galaxy, 2, 57, true))
  end
end)

suite:Case("of routes as good, the one through the lower-numbered systems: the way found by looking at every system each time", function(t)
  local RISK: { [string]: number } = { secure = 0, low = 2, lawless = 30 }
  -- The plain way of finding it, which a large galaxy is too big for:
  -- always on from the cheapest system not yet settled, the lowest
  -- numbered of those, found by looking through them all.
  local function plainly(galaxy: Galaxy.Galaxy, from: number, to: number, safest: boolean): { number }
    local systems = galaxy.systems
    local cost: { number } = table.create(#systems, math.huge)
    local before: { number } = table.create(#systems, 0)
    local done: { boolean } = table.create(#systems, false)
    cost[from] = 0
    for _ = 1, #systems do
      local at, least = 0, math.huge
      for id = 1, #systems do
        if not done[id] and cost[id] < least then
          at, least = id, cost[id]
        end
      end
      if at == 0 or at == to then
        break
      end
      done[at] = true
      for _, neighbor in systems[at].neighbors do
        local reached = least + 1 + (if safest then RISK[Galaxy.Band(systems[neighbor].security)] else 0)
        if reached < cost[neighbor] then
          cost[neighbor], before[neighbor] = reached, at
        end
      end
    end
    local route: { number } = { to }
    while route[1] ~= from do
      table.insert(route, 1, before[route[1]])
    end
    return route
  end
  for _, count in { 2, 3, 12, 60, 300 } do
    for seed = 1, 3 do
      local galaxy = Galaxy.Describe(seed, count)
      local rng = Rng.For(seed, count, 77)
      for _ = 1, 40 do
        local from, to = Rng.Int(rng, count) + 1, Rng.Int(rng, count) + 1
        for _, safest in { false, true } do
          t.eq(Galaxy.Route(galaxy, from, to, safest), plainly(galaxy, from, to, safest), `seed {seed}, {count} systems, {from} to {to}`)
        end
      end
    end
  end
end)

suite:Case("space nobody holds goes by its survey marks, and nothing else about a galaxy follows from them", function(t)
  for _, count in { 3, 40, 400 } do
    local galaxy = Galaxy.Describe(5, count)
    local marked = 0
    local seen: { [string]: boolean } = {}
    for _, system in galaxy.systems do
      -- (a mark where nobody is, a name where somebody is)
      t.eq(Names.IsMark(system.name), system.owner == "", `{system.name}, held by "{system.owner}"`)
      if system.owner == "" then
        marked += 1
        -- five letters and figures and a stroke among them, and no vowel
        t.ok(#system.name == 6 and string.match(system.name, "^[BCDFGHJKLMNPQRSTVWXYZ0-9]+%-[BCDFGHJKLMNPQRSTVWXYZ0-9]+$") ~= nil,
          `{system.name} is not a survey mark`)
      else
        t.ok(string.match(system.name, "^%u%l+$") ~= nil, `{system.name} is not a name`)
      end
      t.ok(not seen[system.name], `two systems are called {system.name}`)
      seen[system.name] = true
    end
    t.ok(marked >= 1 and marked < count, `{marked} of {count} systems have marks`)
    -- The marks are given again and the galaxy is as it was: they come
    -- of the seed, and of nothing that was drawn to make the rest.
    local again = Galaxy.Describe(5, count)
    Galaxy.Marks(again)
    t.eq(Codec.HashOf(again), Codec.HashOf(galaxy))
  end
  -- A mark is made of what is drawn for it and nothing else.
  t.eq(Names.Mark(Rng.For(9, 9)), Names.Mark(Rng.For(9, 9)))
end)

suite:Case("a galaxy of thousands of systems is made: every system reached, every one with a name of its own", function(t)
  -- (there are some 3,700 names of the usual length, and the systems are
  -- named as they are made, so the later of them are given longer ones:
  -- but most of so many are held by nobody and go by their marks)
  local count = 6000
  local galaxy = Galaxy.Describe(2, count)
  t.eq(#galaxy.systems, count)
  local hops: { number } = table.create(count, -1)
  hops[1] = 0
  local queue = { 1 }
  local at = 1
  while at <= #queue do
    local id = queue[at]
    at += 1
    for _, neighbor in galaxy.systems[id].neighbors do
      if hops[neighbor] < 0 then
        hops[neighbor] = hops[id] + 1
        table.insert(queue, neighbor)
      end
    end
  end
  t.eq(#queue, count, "systems reached from the first")
  local seen: { [string]: boolean } = {}
  local longest = 0
  for _, system in galaxy.systems do
    t.ok(not seen[system.name], `two systems are called {system.name}`)
    seen[system.name] = true
    t.eq(Names.IsMark(system.name), system.owner == "")
    longest = math.max(longest, #system.name)
    t.ok(galaxy.regions[system.region] ~= nil and galaxy.constellations[system.constellation].region == system.region)
  end
  -- (and the held systems, which are few of so many, all have plain names)
  t.ok(longest <= 10, `the longest name is {longest} letters`)
  seen = {}
  for _, constellation in galaxy.constellations do
    t.ok(not seen[constellation.name], `two constellations are called {constellation.name}`)
    seen[constellation.name] = true
  end
  -- A route across it is the fewest jumps there are.
  for _, to in { 2, 777, 3000, count } do
    t.eq(#Galaxy.Route(galaxy, 1, to) - 1, hops[to])
  end
end)

suite:Case("no gate reaches farther than fifty light years, so a galaxy of thousands is many jumps across, and it is whole for all that", function(t)
  -- Every system reached from the first, how far the farthest is, and the longest gate.
  local function survey(galaxy: Galaxy.Galaxy): (number, number, number)
    local hops: { number } = table.create(#galaxy.systems, -1)
    hops[1] = 0
    local queue = { 1 }
    local at, longest, far = 1, 0, 0
    while at <= #queue do
      local id = queue[at]
      at += 1
      local system = galaxy.systems[id]
      for _, neighbor in system.neighbors do
        local other = galaxy.systems[neighbor]
        longest = math.max(longest, math.sqrt((system.x - other.x) ^ 2 + (system.y - other.y) ^ 2))
        t.ok(table.find(other.neighbors, id) ~= nil, "a gate that runs one way")
        if hops[neighbor] < 0 then
          hops[neighbor] = hops[id] + 1
          far = math.max(far, hops[neighbor])
          table.insert(queue, neighbor)
        end
      end
    end
    return #queue, far, longest
  end
  local reach = Galaxy.GATE_REACH
  t.eq(reach, 50)
  -- A galaxy of four thousand is 500 light years across. With gates as long as they came, it was a few
  -- jumps from anywhere to anywhere; with none over fifty light years it has depth.
  local count = 4000
  local galaxy = Galaxy.Describe(3, count)
  local reached, far, longest = survey(galaxy)
  t.eq(reached, count, "systems reached from the first")
  t.ok(longest <= reach, `a gate of {longest} light years`)
  Galaxy.GATE_REACH = math.huge
  local loose = Galaxy.Describe(3, count)
  local _, near, uncut = survey(loose)
  t.ok(uncut > 250, `the longest gate, left alone, was {uncut} light years`)
  t.ok(far >= near * 2, `{far} jumps from the first system to the farthest, and {near} with the long gates`)
  -- A reach so short that the galaxy falls to pieces: every piece is joined to the rest again, by a gate
  -- between neighbours. (A galaxy is made the same way whatever the reach: same seed, same systems.)
  Galaxy.GATE_REACH = 12
  local tight = Galaxy.Describe(3, count)
  local whole, _, joined = survey(tight)
  Galaxy.GATE_REACH = reach
  t.eq(whole, count, "systems reached from the first, with gates of twelve light years")
  t.ok(joined <= 24, `a gate of {joined} light years where none was to be over twelve`)
  for id, system in tight.systems do
    t.eq({ system.x, system.y } :: { any }, { galaxy.systems[id].x, galaxy.systems[id].y } :: { any })
  end
  -- A galaxy narrower than the reach loses nothing by it: one of thirty systems is 44 light years across.
  -- (And the forty of the specs and the scripts, which is 51 across, has no gate that long either.)
  for _, size in { 30, 40 } do
    for seed = 1, 3 do
      Galaxy.GATE_REACH = math.huge
      local small = Galaxy.Describe(seed, size)
      Galaxy.GATE_REACH = reach
      local same = Galaxy.Describe(seed, size)
      for id, system in small.systems do
        t.eq(system.neighbors, same.systems[id].neighbors)
      end
    end
  end
end)

suite:Case("a galaxy is shared out into regions and constellations, each of systems that gates join, each with a name of its own", function(t)
  for _, count in { 1, 3, 40, 150, 400 } do
    local galaxy = Galaxy.Describe(7, count)
    local systems = galaxy.systems
    -- (about a region to sixteen systems: fewer where one came out too small to keep)
    local most = math.max(1, math.floor(count / Galaxy.REGION + 0.5))
    t.ok(#galaxy.regions >= math.max(1, most // 2) and #galaxy.regions <= most, `{#galaxy.regions} regions for {count} systems`)
    t.ok(#galaxy.constellations >= #galaxy.regions)
    -- Every system is in a constellation of its own region.
    local inRegion: { [number]: { number } } = {}
    local inConstellation: { [number]: { number } } = {}
    for id, system in systems do
      local region = assert(galaxy.regions[system.region], `system {id} is in no region`)
      local constellation = assert(galaxy.constellations[system.constellation], `system {id} is in no constellation`)
      t.eq({ region.id, constellation.id, constellation.region }, { system.region, system.constellation, system.region })
      inRegion[system.region] = inRegion[system.region] or {}
      table.insert(inRegion[system.region], id)
      inConstellation[system.constellation] = inConstellation[system.constellation] or {}
      table.insert(inConstellation[system.constellation], id)
    end
    -- Each group can be crossed without leaving it.
    local function joined(members: { number }, same: (a: number, b: number) -> boolean): boolean
      local seen: { [number]: boolean } = { [members[1]] = true }
      local queue = { members[1] }
      local at = 1
      while at <= #queue do
        local id = queue[at]
        at += 1
        for _, neighbor in systems[id].neighbors do
          if not seen[neighbor] and same(id, neighbor) then
            seen[neighbor] = true
            table.insert(queue, neighbor)
          end
        end
      end
      return #queue == #members
    end
    local names: { [string]: boolean } = {}
    for _, region in galaxy.regions do
      local members = assert(inRegion[region.id], `{region.name} has no systems`)
      t.ok(joined(members, function(a: number, b: number): boolean
        return systems[a].region == systems[b].region
      end), `{region.name} is in pieces`)
      t.ok(not names[region.name] and #region.name > 4, `two regions are called {region.name}`)
      names[region.name] = true
      if count >= 150 then
        t.ok(#members >= Galaxy.REGION // 3 and #members <= 4 * Galaxy.REGION, `{region.name} has {#members} systems`)
      end
    end
    for _, constellation in galaxy.constellations do
      local members = assert(inConstellation[constellation.id], `{constellation.name} has no systems`)
      t.ok(joined(members, function(a: number, b: number): boolean
        return systems[a].constellation == systems[b].constellation
      end), `{constellation.name} is in pieces`)
      t.ok(not names[constellation.name], `two places are called {constellation.name}`)
      names[constellation.name] = true
    end
  end
  -- It follows from the seed, and is the same however often it is worked out.
  local a, b = Galaxy.Describe(3, 60), Galaxy.Describe(3, 60)
  Galaxy.Regions(b)
  t.eq(Codec.HashOf(a), Codec.HashOf(b))
  t.ok(Codec.HashOf(Galaxy.Describe(4, 60).regions) ~= Codec.HashOf(a.regions))
end)

return suite
