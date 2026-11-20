--!strict
-- The factions' citadels (Assets/Citadels; where, Describe/CitadelSites):
-- stations of their people's, more of them the more secure a system,
-- and brought down by the world.

local CitadelSites = require("@lt/Core/Describe/CitadelSites")
local State = require("@lt/Core/Kernel/State")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Fields = require("@lt/Core/Tactical/Fields")
local Combat = require("@lt/Core/Tactical/Combat")
local CitadelGuns = require("@lt/Core/Tactical/CitadelGuns")
local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Citadels = require("@lt/Core/Assets/Citadels")
local Core = require("@lt/Core/Api")
local Items = require("@lt/Core/Assets/Items")
local Space = require("@lt/Core/Tactical/Space")
local Stations = require("@lt/Core/Assets/Stations")
local Structures = require("@lt/Core/Data/Structures")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Citadels")

local function galaxy(): Core.Game
  return Core.New({ galaxySeed = 3, historySeed = 1, systems = 120, peaceful = true })
end

suite:Case("held space has a station or a citadel at half its planets times its security; core space all but always a citadel", function(t)
  local game = galaxy()
  local state = game.state
  local held, withCitadel, standing, fallen, top = 0, 0, 0, 0, 0
  for id = 2, 120 do
    local node = state.galaxy.systems[id]
    local description = Space.Describe(state, id)
    local planets, stations, hosted = 0, 0, {} :: { [number]: boolean }
    local byId: { [number]: any } = {}
    for _, object in description.objects do
      byId[object.id] = object
    end
    for _, object in description.objects do
      if object.kind == "planet" then
        planets += 1
      elseif object.kind == "station" then
        stations += 1
        local host = byId[object.parent]
        if host then
          hosted[if host.kind == "moon" then host.parent else host.id] = true
        end
      end
    end
    local citadels = 0
    for _, record in Citadels.Of(state, id) do
      local tower = assert(Structures.towerById[record.tower], record.tower)
      t.ok(tower.citadel, record.tower)
      if record.fallen then
        fallen += 1
        t.eq(node.owner, "", "a hulk in held space from the start")
      else
        standing += 1
        citadels += 1
        t.eq(record.owner, node.owner)
        if table.find(Structures.CITADEL_ALIEN_PEOPLES, record.owner) then
          t.eq(tower.faction, record.owner, record.tower)
        else
          t.eq(tower.faction, "", record.tower)
        end
        if tower.kind == "generator" then
          t.ok(tower.size == 3 or tower.size == 4)
        end
      end
    end
    local free = 0
    for _, object in description.objects do
      if object.kind == "planet" and not hosted[object.id] then
        free += 1
      end
    end
    if node.owner ~= "" and CitadelSites.Builds(node.owner) and not node.uncharted then
      held += 1
      withCitadel += if citadels > 0 then 1 else 0
      if node.security >= 1 then
        top += 1
        t.ok(planets - free + citadels >= math.floor(planets / 2 + 0.5) or citadels == free, `{node.name}: not every other planet served`)
      end
      -- (something at half its planets times its security: a station at it or its moons, or a citadel, as far as there are planets free)
      local wanted = math.floor(planets * CitadelSites.SHARE * node.security + 0.5)
      local served = planets - free + citadels
      t.ok(served >= wanted or citadels == free, `{node.name} ({node.security}): {served} of {planets} planets served, {wanted} wanted`)
    else
      t.eq(citadels, 0, `{node.name}: a citadel standing in space nobody builds in`)
    end
  end
  t.ok(held >= 10, `{held} held systems`)
  -- (most held systems have one: the more secure, the likelier)
  t.ok(withCitadel >= held * 0.5, `{withCitadel} of {held} held systems have a citadel`)
  t.ok(standing >= held * 0.75, `{standing} standing in {held} held systems`)
  -- (a system of the highest security has something at every other planet)
  t.ok(top > 0, "no system of the highest security looked at")
  -- (the same galaxy has the same citadels)
  local again = galaxy()
  local first = state.citadelIds[1]
  Space.Describe(again.state, state.citadels[first].system)
  t.eq(again.state.citadels[first].tower, state.citadels[first].tower)
end)

suite:Case("a faction's citadel is a station of its people's, with its kind's services; its system lost, they fall and leave their hulks", function(t)
  local game = galaxy()
  local state = game.state
  local system = 0
  for id = 2, 120 do
    if system == 0 then
      Space.Describe(state, id)
      local records = Citadels.Of(state, id)
      if #records >= 2 and not records[1].fallen then
        system = id
      end
    end
  end
  t.ok(system ~= 0, "no system with two citadels")
  local records = Citadels.Of(state, system)
  local citadel = records[1]
  local station = assert(Space.Object(state, citadel.station), "the citadel is not in its system")
  t.eq({ station.kind, station.variety, station.parent } :: { any }, { "station", "citadel", citadel.body } :: { any })
  t.ok(records[2].body ~= citadel.body, "two citadels at one body")
  t.eq(Stations.People(state, station.id), citadel.owner)
  local makeup = assert(Stations.Makeup(state, station.id))
  t.eq(makeup.tower, citadel.tower)
  local tower = Structures.towerById[citadel.tower]
  -- (its services, as its slots let it, and its people's defence module)
  t.ok(#makeup.modules >= 2 and #makeup.modules <= (tower.slots or 2) + 1, `{#makeup.modules} modules`)
  t.eq(makeup.modules[#makeup.modules], Citadels.Defence(citadel))
  t.ok(Stations.Has(state, station.id, "market") and Stations.Has(state, station.id, "fitting"), "no market or repairs")
  -- Its system is lost: within the hour all of them fall, and their places are their hulks'.
  state.galaxy.systems[system].owner = ""
  local events: { Citadels.Event } = {}
  state.tick = 3600
  Citadels.Step(state, events)
  for _, record in records do
    t.ok(record.fallen and record.wreck ~= 0, "one did not fall")
    t.eq(state.wrecks[record.wreck].hulk, record.tower)
    t.eq(assert(Space.Object(state, record.station)).variety, "hulk")
  end
  t.eq(Stations.Makeup(state, station.id), nil)
  -- (an alien people's has the drawing of it in its hulk)
  if tower.faction ~= "" then
    local drawn = false
    for _, item in Items.In(state, citadel.wreck, "cargo") do
      drawn = drawn or string.find(item.type, tower.id, 1, true) ~= nil
    end
    t.ok(drawn, "no drawing in an alien people's hulk")
  end
  -- (and each falls once)
  Citadels.Fall(state, system, events)
  local hulks = 0
  for _, id in state.wreckIds do
    hulks += if state.wrecks[id].hulk and state.wrecks[id].system == system then 1 else 0
  end
  t.eq(hulks, #records)
end)

suite:Case("a citadel far off is there to be looked at before anybody goes; an old save has them put down where it has been", function(t)
  local game = galaxy()
  local state = game.state
  -- (a station of a system never described: its makeup is the citadel's, and asking puts nothing in the save)
  local hash = Core.Hash(game)
  local far: { system: number, station: number, tower: string }? = nil
  for id = 2, 120 do
    if far == nil and state.systems[id] == nil then
      for _, object in Space.Glance(state, id).objects do
        if far == nil and object.kind == "station" and object.variety == "citadel" then
          local makeup = assert(Stations.Makeup(state, object.id), "a citadel far off has no makeup")
          far = { system = id, station = object.id, tower = makeup.tower :: string }
        end
      end
    end
  end
  local record = assert(far, "no citadel far off")
  t.eq(Core.Hash(game), hash, "looking at a citadel far off changed the save")
  t.eq(state.systems[record.system], nil)
  t.eq(#Citadels.Of(state, record.system), 0)
  -- (and described later, it is the same station, put down now)
  Space.Describe(state, record.system)
  t.eq(assert(Space.Object(state, record.station)).variety, "citadel")
  t.eq(assert(Stations.Makeup(state, record.station)).tower, record.tower)
  t.ok(#Citadels.Of(state, record.system) >= 1)
  -- A save from before: none, until it is loaded.
  local old = galaxy()
  old.state.citadels = nil :: any
  old.state.citadelIds = nil :: any
  old.state.citadelsSeen = nil :: any
  local before = #Space.Describe(old.state, record.system).objects
  Citadels.Place(old.state)
  t.eq(#Space.Describe(old.state, record.system).objects, before + #Citadels.Of(old.state, record.system))
  t.ok(#Citadels.Of(old.state, record.system) >= 1)
end)

suite:Case("a faction's citadel is fought as a pilot's is: no field, its core, its guns, reinforced, and brought down to its hulk", function(t)
  local game = galaxy()
  local state = game.state
  local system, record = 0, nil :: State.Citadel?
  for id = 2, 120 do
    if system == 0 then
      Space.Describe(state, id)
      local records = Citadels.Of(state, id)
      if #records >= 1 and not records[1].fallen then
        system, record = id, records[1]
      end
    end
  end
  local citadel = assert(record, "no citadel standing")
  local events: { Citadels.Event } = {}
  Citadels.Cores(state, system, events)
  local core = assert(state.balls[citadel.core or 0], "no core")
  local tower = Structures.towerById[citadel.tower]
  t.eq({ Fields.Of(state, citadel.station), core.vitals.shieldMax, core.vitals.phase, state.ships[core.id].owner,
    state.ships[core.id].stands } :: { any }, { nil, tower.shield, "shield", citadel.owner, citadel.station } :: { any })
  -- Its guns fire on a pirate that comes in reach.
  local pirate = Pirates.Spawn(state, Pirates.kindById.raider, system, core.x + core.radius + 3000, core.y, core.z, core.grid)
  local shots = 0
  for _ = 1, 15 do
    local fired: { Citadels.Event } = {}
    CitadelGuns.Fire(state, fired)
    for _, event in fired do
      shots += if event.kind == "Shot" and event.from == core.id then 1 else 0
    end
    state.tick += 1
  end
  t.ok(shots >= 2, `shots {shots}`)
  -- Shot down layer by layer, reinforced between, and falling to its hulk when its structure goes.
  local v = core.vitals
  local function strike(amount: number)
    Combat.Step(state, events, { { target = core.id, by = pirate.id, damage = { amount, 0, 0, 0 } } })
  end
  -- (each strike well past what is left of the layer, whatever it resists)
  strike(v.shield * 10)
  t.eq(v.phase, "armor")
  state.tick = v.reinforced or state.tick
  strike(v.armor * 10)
  t.eq(v.phase, "hull")
  Aftermath.Destroy(state, core.id, pirate.id, events)
  t.ok(citadel.fallen and citadel.wreck ~= 0 and citadel.core == nil, "it did not fall to its hulk")
end)

return suite
