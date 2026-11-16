--!strict
-- What stations are made of (Data/Structures).

local Factions = require("@lt/Core/Data/Factions")
local Ships = require("@lt/Core/Data/Ships")
local Structures = require("@lt/Core/Data/Structures")
local Batteries = require("@lt/Core/Tactical/Batteries")
local Test = require("@lt/Tool/Test")
local Types = require("@lt/Core/Data/Types")

local suite = Test.Suite("Structures")

local VARIETIES = { "trade hub", "shipyard", "refinery", "habitat", "outpost" }

suite:Case("each people that holds stations has a tower in each of three sizes, each twice the last", function(t)
  -- (the human factions that keep to a place, the pirates, the Nimia and
  -- the Vail: the owner, 2026-11-16. Not the Kethri nor the Drowned)
  t.eq(Structures.TOWER_PEOPLES, { "vessari", "talmar", "orun", "unbound", "nimia", "vail" })
  for _, people in Structures.TOWER_PEOPLES do
    local faction = Factions.byId[people]
    local last = 0
    for size, word in Structures.SIZES do
      local tower = Structures.towerById[`tower.{faction.id}.{word}`]
      t.ok(tower ~= nil, `{faction.id} has no {word} tower`)
      t.eq(tower.size, size)
      t.eq(tower.faction, faction.id)
      t.ok(tower.powergrid > last, `the {word} tower supplies no more than the one below it`)
      last = tower.powergrid
      -- (the baseline's, whoever's it is)
      t.eq({ tower.cpu, tower.shield, tower.armor, tower.hull, tower.field, tower.fuel } :: { any }, { Structures.SUPPLY[size].cpu,
        Structures.SUPPLY[size].shield, Structures.SUPPLY[size].armor, Structures.SUPPLY[size].hull, Structures.SUPPLY[size].field,
        Structures.SUPPLY[size].fuel } :: { any })
    end
  end
  t.eq(#Structures.towers, #Structures.TOWER_PEOPLES * 3)
  t.eq(Structures.towerById["tower.kethri.small"], nil)
end)

suite:Case("a people's tower is better at what its people are: its guns, its missiles, its layer", function(t)
  -- (the owner, 2026-11-16: about 15% to the faction's bonuses, the
  -- gun batteries firing its turret family, missiles too, and "+15 points"
  -- on every resistance of its layer)
  t.eq({ Structures.TOWER_DAMAGE, Structures.TOWER_RESIST } :: { any }, { 1.15, 0.15 } :: { any })
  for _, tower in Structures.towers do
    local people = Factions.byId[tower.faction]
    t.eq({ tower.gun, tower.gunBonus, tower.tank, tower.resist } :: { any }, { people.weapon, 1.15, people.tank, 0.15 } :: { any }, tower.id)
    t.eq(tower.missileBonus, if people.launchers >= 0.3 then 1.15 else 1, tower.id)
    -- Its core: the baseline's resistances, with its people's layer 15 points better at every kind of damage.
    local core = assert(Ships.byId[Structures.Core(tower)], `{tower.id} has no core`)
    local plain = Ships.byId[`works.tower.{tower.size}`]
    for _, layer in { "shield", "armor", "hull" } do
      local mine, theirs = (core :: any)[`{layer}Resonance`], (plain :: any)[`{layer}Resonance`]
      for kind = 1, 4 do
        t.near(mine[kind], if layer == tower.tank then math.max(0, theirs[kind] - 0.15) else theirs[kind], 1e-12, `{tower.id} {layer} {kind}`)
      end
    end
    t.eq({ core.shield, core.armor, core.hull } :: { any }, { tower.shield, tower.armor, tower.hull } :: { any })
  end
  -- The guns: a volley as big as a battery's ever was, of the people's family's kinds, 15% more.
  for _, tower in Structures.towers do
    local damage = assert((Batteries.Of("battery.gun", tower.id)))
    t.near(damage[1] + damage[2] + damage[3] + damage[4], 60 * 1.15, 1e-9, tower.id)
    if tower.gun == "laser" then
      t.eq({ damage[3], damage[4] } :: { any }, { 0, 0 } :: { any }, "a laser does no kinetic or explosive damage")
    end
    local missile = assert((Batteries.Of("battery.missile", tower.id)))
    t.near(missile[1] + missile[2] + missile[3] + missile[4], 90 * tower.missileBonus, 1e-9, tower.id)
  end
  -- (a gate's sentries are nobody's people's)
  t.eq((Batteries.Of("battery.gun", nil)), { 0, 15, 30, 15 })
end)

suite:Case("no module belongs to a faction", function(t)
  for _, module in Structures.modules do
    for _, faction in Factions.list do
      t.ok(string.find(module.id, faction.id, 1, true) == nil, `{module.id} names a faction`)
      t.ok(string.find(string.lower(module.name), string.lower(faction.name), 1, true) == nil, `{module.name} names a faction`)
    end
  end
end)

local function services(makeup: Structures.Makeup): { [string]: boolean }
  local has: { [string]: boolean } = {}
  for _, id in makeup.modules do
    has[Structures.moduleById[id].service] = true
  end
  return has
end

suite:Case("the station a pilot starts at has everything the round of play needs, whatever its kind and size", function(t)
  for _, variety in VARIETIES do
    for _, radius in { 2000, 3999, 4000, 5999, 6000, 8000 } do
      local has = services(Structures.Makeup(variety, radius, "vessari", true))
      for _, service in { "market", "fitting", "refining", "industry", "research", "storage" } do
        t.ok(has[service], `a starter {variety} of {radius} m has nothing for {service}`)
      end
    end
  end
end)

suite:Case("any other station has what its kind is for, and not everything", function(t)
  local first = { ["trade hub"] = "market", shipyard = "industry", refinery = "refining", habitat = "quarters", outpost = "fitting" }
  for _, variety in VARIETIES do
    for _, radius in { 3000, 5000, 7000 } do
      local has = services(Structures.Makeup(variety, radius, "vessari"))
      t.ok(has[first[variety]], `a {variety} of {radius} m has nothing for {first[variety]}`)
      local count = 0
      for _, service in { "market", "fitting", "refining", "industry" } do
        count += if has[service] then 1 else 0
      end
      t.ok(count < 4, `a {variety} of {radius} m does everything, which only the starter should`)
    end
  end
  -- (and some are missing what a pilot will go looking for)
  t.ok(not services(Structures.Makeup("refinery", 3000, "vessari")).market, "a small refinery should have no market")
  t.ok(not services(Structures.Makeup("trade hub", 3000, "vessari")).refining, "a small trade hub should not refine")
  t.ok(not services(Structures.Makeup("habitat", 3000, "vessari")).fitting, "a small habitat should have no ship maintenance")
end)

suite:Case("a tower is never given more than it can power, and a bigger one carries more", function(t)
  for _, variety in VARIETIES do
    local last = 0
    for _, radius in { 3000, 5000, 7000 } do
      local makeup = Structures.Makeup(variety, radius, "vessari")
      local tower = Structures.towerById[makeup.tower :: string]
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
  t.ok(count("shipyard", "array.assembly") == 2, "a large shipyard should have two assembly arrays")
end)

suite:Case("the makeup is the same every time it is asked for, larger modules first", function(t)
  local a = Structures.Makeup("shipyard", 6500, "vessari")
  local b = Structures.Makeup("shipyard", 6500, "vessari")
  t.eq(table.concat(a.modules, ","), table.concat(b.modules, ","))
  for index = 2, #a.modules do
    t.ok(Structures.moduleById[a.modules[index - 1]].radius >= Structures.moduleById[a.modules[index]].radius)
  end
end)

suite:Case("a tower, a module and a day's fuel for the largest tower each go, packed, in the hold of any industrial a pilot can buy", function(t)
  local smallest = math.huge
  for _, ship in Ships.list do
    -- (a hauler: a combat hauler is built to be shot at, and has half the hold)
    if ship.class == "industrial" and not ship.restricted and ship.role == nil then
      smallest = math.min(smallest, ship.cargo)
    end
  end
  t.ok(smallest < math.huge, "there is no industrial")
  for _, tower in Structures.towers do
    t.ok(tower.volume <= smallest, `{tower.name} is {tower.volume} m3 and the smallest industrial holds {smallest}`)
  end
  for _, module in Structures.modules do
    t.ok(module.volume <= smallest, `{module.name} is {module.volume} m3 and the smallest industrial holds {smallest}`)
  end
  t.ok(Structures.towers[3].fuel * 24 * Structures.FUEL.volume <= smallest, "a day's fuel for a large tower does not go in an industrial")
end)

suite:Case("a bigger tower has a wider field, burns more, takes longer to anchor and costs more", function(t)
  for index = 2, 3 do
    local a, b = Structures.towerById[`tower.vessari.{Structures.SIZES[index - 1]}`], Structures.towerById[`tower.vessari.{Structures.SIZES[index]}`]
    t.ok(b.field > a.field and b.fuel > a.fuel and b.anchor > a.anchor and b.basePrice > a.basePrice and b.volume > a.volume)
  end
end)

suite:Case("the Kethri build no towers: their stations are colony ships with everything aboard", function(t)
  t.ok(Factions.byId.kethri.nomad, "the Kethri should be nomads")
  for _, word in Structures.SIZES do
    t.eq(Structures.towerById[`tower.kethri.{word}`], nil)
    t.eq(Types.Get(`tower.kethri.{word}`), nil)
  end
  local class = assert(Structures.ColonyShip("kethri"))
  t.eq(class.name, "Les Larmes de Nova")
  t.eq(class.length, 10000)
  t.eq(Structures.ColonyShip("vessari"), nil)
  -- whatever kind and size of station it would have been, and starter or not
  for _, variety in VARIETIES do
    for _, radius in { 2500, 5000, 7500 } do
      local makeup = Structures.Makeup(variety, radius, "kethri")
      t.eq(makeup.ship, class.id)
      t.eq(makeup.tower, nil)
      local has = services(makeup)
      for _, service in Structures.SERVICES do
        -- (all but a moon drill, a reactor and a jump beacon: those are a pilot's tower's)
        t.eq(has[service] == true, service ~= "extraction" and service ~= "reaction" and service ~= "beacon", `a colony ship and {service}`)
      end
    end
  end
  -- and the others' are towers still
  local makeup = Structures.Makeup("outpost", 3000, "talmar")
  t.eq(makeup.ship, nil)
  t.eq(makeup.tower, "tower.talmar.small")
end)

return suite
