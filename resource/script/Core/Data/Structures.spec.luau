--!strict
-- What stations are made of (Data/Structures).

local Factions = require("@lt/Core/Data/Factions")
local Structures = require("@lt/Core/Data/Structures")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Structures")

local VARIETIES = { "trade hub", "shipyard", "refinery", "habitat", "outpost" }

suite:Case("each human faction has a tower in each of three sizes, each twice the last", function(t)
  local humans = 0
  for _, faction in Factions.list do
    if faction.kind == "human" then
      humans += 1
      local last = 0
      for size, word in Structures.SIZES do
        local tower = Structures.towerById[`tower.{faction.id}.{word}`]
        t.ok(tower ~= nil, `{faction.id} has no {word} tower`)
        t.eq(tower.size, size)
        t.eq(tower.faction, faction.id)
        t.ok(tower.powergrid > last, `the {word} tower supplies no more than the one below it`)
        last = tower.powergrid
      end
    end
  end
  t.eq(#Structures.towers, humans * 3)
end)

suite:Case("no module belongs to a faction", function(t)
  for _, module in Structures.modules do
    for _, faction in Factions.list do
      t.ok(string.find(module.id, faction.id, 1, true) == nil, `{module.id} names a faction`)
      t.ok(string.find(string.lower(module.name), string.lower(faction.name), 1, true) == nil, `{module.name} names a faction`)
    end
  end
end)

suite:Case("a station of any kind and size has a module for every service a docked pilot uses", function(t)
  for _, variety in VARIETIES do
    for _, radius in { 2000, 3999, 4000, 5999, 6000, 8000 } do
      local makeup = Structures.Makeup(variety, radius, "vessari")
      local has: { [string]: boolean } = {}
      for _, id in makeup.modules do
        has[Structures.moduleById[id].service] = true
      end
      for _, service in { "market", "fitting", "refining", "industry" } do
        t.ok(has[service], `a {variety} of {radius} m has nothing for {service}`)
      end
    end
  end
end)

suite:Case("a tower is never given more than it can power, and a bigger one carries more", function(t)
  for _, variety in VARIETIES do
    local last = 0
    for _, radius in { 3000, 5000, 7000 } do
      local makeup = Structures.Makeup(variety, radius, "vessari")
      local tower = Structures.towerById[makeup.tower]
      t.eq(tower.size, Structures.SizeFor(radius))
      local powergrid, cpu = 0, 0
      for _, id in makeup.modules do
        powergrid += Structures.moduleById[id].powergrid
        cpu += Structures.moduleById[id].cpu
      end
      t.ok(powergrid <= tower.powergrid, `a {variety} of {radius} m draws {powergrid} MW of {tower.powergrid}`)
      t.ok(cpu <= tower.cpu, `a {variety} of {radius} m uses {cpu} tf of {tower.cpu}`)
      t.ok(#makeup.modules > last, `a {variety} of {radius} m has no more modules than the size below`)
      last = #makeup.modules
    end
  end
end)

suite:Case("a kind of station has more of what it is for than another kind has", function(t)
  local function count(variety: string, id: string): number
    local n = 0
    for _, module in Structures.Makeup(variety, 7000, "vessari").modules do
      if module == id then
        n += 1
      end
    end
    return n
  end
  t.ok(count("shipyard", "array.assembly") > count("trade hub", "array.assembly"))
  t.ok(count("refinery", "array.refining") > count("shipyard", "array.refining"))
  t.ok(count("trade hub", "array.trade") > count("refinery", "array.trade"))
  t.ok(count("habitat", "array.habitat") > count("refinery", "array.habitat"))
end)

suite:Case("the makeup is the same every time it is asked for, larger modules first", function(t)
  local a = Structures.Makeup("shipyard", 6500, "vessari")
  local b = Structures.Makeup("shipyard", 6500, "vessari")
  t.eq(table.concat(a.modules, ","), table.concat(b.modules, ","))
  for index = 2, #a.modules do
    t.ok(Structures.moduleById[a.modules[index - 1]].radius >= Structures.moduleById[a.modules[index]].radius)
  end
end)

return suite
