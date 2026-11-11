--!strict
local Codec = require("@lt/Core/Persist/Codec")
local Constants = require("@lt/Core/Data/Constants")
local Factions = require("@lt/Core/Data/Factions")
local Galaxy = require("@lt/Core/Describe/Galaxy")
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

suite:Case("the human factions share out most of a galaxy from a homeworld each, and nobody holds the rest", function(t)
  local humans: { string } = {}
  for _, faction in Factions.list do
    if faction.kind == "human" then
      table.insert(humans, faction.id)
    end
  end
  for seed = 1, 8 do
    for _, count in { 3, 12, 40, 200 } do
      local galaxy = Galaxy.Describe(seed, count)
      local factions = math.clamp(count // Galaxy.SYSTEMS_A_FACTION, 1, #humans)
      local homes: { [string]: number } = {}
      local held: { [string]: number } = {}
      local claimed = 0
      for _, system in galaxy.systems do
        t.ok(table.find(humans, system.nearest) ~= nil, `seed {seed}: system {system.id} is nearest nobody`)
        if system.home then
          t.eq(system.hops, 0)
          t.eq(system.security, 1)
          t.eq(homes[system.owner], nil)
          homes[system.owner] = system.id
        end
        if system.owner ~= "" then
          claimed += 1
          t.eq(system.owner, system.nearest)
          t.ok(system.security >= 0.3, `seed {seed}: held space with a security of {system.security}`)
          held[system.owner] = (held[system.owner] or 0) + 1
        else
          t.eq(system.security, 0)
        end
      end
      t.eq(claimed, math.floor(count * Galaxy.CLAIMED))
      -- (the first factions of the list, the first of them at the first system)
      for index = 1, #humans do
        if index <= factions then
          t.ok(homes[humans[index]] ~= nil, `seed {seed}, {count} systems: {humans[index]} has no homeworld`)
          t.ok(held[humans[index]] >= 2 or count < 12, `seed {seed}, {count} systems: {humans[index]} holds only its homeworld`)
        else
          t.eq(homes[humans[index]], nil)
        end
      end
      t.eq(homes[humans[1]], 1)
      -- (and nobody's homeworld is next door to another's)
      if factions > 1 then
        for _, system in galaxy.systems do
          if system.home then
            for _, neighbor in system.neighbors do
              t.ok(not galaxy.systems[neighbor].home, `seed {seed}, {count} systems: two homeworlds a jump apart`)
            end
          end
        end
      end
      -- security never rises going away from home
      for _, system in galaxy.systems do
        for _, neighbor in system.neighbors do
          local other = galaxy.systems[neighbor]
          if other.hops > system.hops then
            t.ok(other.security <= system.security, `seed {seed}: it gets safer going away from home`)
          end
        end
      end
    end
  end
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
