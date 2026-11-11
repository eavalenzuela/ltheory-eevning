--!strict
local Codec = require("@lt/Core/Persist/Codec")
local Constants = require("@lt/Core/Data/Constants")
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

return suite
