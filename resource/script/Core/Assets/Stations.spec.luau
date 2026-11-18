--!strict
-- What can be done at a station (Assets/Stations): only what it has a
-- module for.

local Core = require("@lt/Core/Api")
local Items = require("@lt/Core/Assets/Items")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Nomads = require("@lt/Core/Tactical/Nomads")
local Stations = require("@lt/Core/Assets/Stations")
local Structures = require("@lt/Core/Data/Structures")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Stations")

-- Every station of the galaxy: its id and what it is made of.
local function stations(game: Core.Game): { { id: number, makeup: Structures.Makeup } }
  local found = {}
  for system = 1, 3 do
    for _, object in Core.Query.Objects(game, system) do
      if object.kind == "station" then
        table.insert(found, { id = object.id, makeup = assert(Stations.Makeup(game.state, object.id)) })
      end
    end
  end
  return found
end

suite:Case("a new pilot starts at the starter station, which has every service the round of play needs", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1 })
  local player = Core.Query.Player(game)
  t.eq(player.docked, Core.Query.Starter(game))
  for _, service in { "market", "fitting", "refining", "industry", "storage" } :: { Structures.Service } do
    t.ok(Stations.Has(game.state, player.docked, service), `the starter station has nothing for {service}`)
  end
end)

suite:Case("every station has a market and a ship maintenance array; the galaxy has stations that lack another service, and no other station has everything", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1 })
  local starter = Core.Query.Starter(game)
  local lacking = 0
  for _, station in stations(game) do
    if station.id ~= starter then
      local all = true
      for _, service in { "market", "fitting", "refining", "industry" } :: { Structures.Service } do
        all = all and Stations.Has(game.state, station.id, service)
      end
      t.ok(not all, `station {station.id} has everything, which only the starter should`)
      -- (a market at every station: the owner, 2026-11-17, "Every station")
      t.ok(Stations.Has(game.state, station.id, "market"), `station {station.id} has no market`)
      -- (and a ship maintenance array: the owner, 2026-11-18, so a ship
      -- bought there can be boarded there)
      t.ok(Stations.Has(game.state, station.id, "fitting"), `station {station.id} has no ship maintenance array`)
      lacking += if Stations.Has(game.state, station.id, "refining") then 0 else 1
    end
  end
  t.ok(lacking > 0, "every station refines: this galaxy cannot show a service being refused")
end)

suite:Case("what a station has no module for is refused there, by name, and allowed at the starter", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1 })
  local state = game.state
  local player = Core.Query.Player(game)
  local buy: State.Command = { kind = "BuyNow", actor = player.ship, type = "ammo.emp", quantity = 10 }
  local refine: State.Command = { kind = "Reprocess", actor = player.ship, item = 0 }
  refine.item = Items.Add(state, "ore.ferrite", 100, player.docked, "hangar").id
  t.ok(Stations.Validate(state, buy), "the starter station refused a purchase")
  t.ok(Stations.Validate(state, refine), "the starter station refused to refine")

  -- Moor the same ship at each other station in turn: what it lacks, it refuses.
  local home = state.ships[player.ship].docked
  local refused = 0
  for _, station in stations(game) do
    if station.id ~= home then
      state.ships[player.ship].docked = station.id
      refine.item = Items.Add(state, "ore.ferrite", 100, station.id, "hangar").id
      for _, command in { buy, refine } :: { State.Command } do
        local service: Structures.Service = if command.kind == "BuyNow" then "market" else "refining"
        local ok, why = Core.Validate(game, command)
        if Stations.Has(state, station.id, service) then
          t.ok(ok or not string.find(why or "", "this station has no", 1, true), `station {station.id} has the module and refused for want of it`)
        else
          refused += 1
          t.ok(not ok, `station {station.id} has no module for {service} and allowed {command.kind}`)
          t.ok(string.find(why or "", Structures.Provider(service), 1, true) ~= nil, `the refusal does not name the module: {tostring(why)}`)
        end
      end
    end
  end
  state.ships[player.ship].docked = home
  t.ok(refused > 0, "nothing was refused anywhere")
end)

suite:Case("a ship in space is not refused for want of a station's module", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1 })
  local player = Core.Query.Player(game)
  t.ok(Core.Submit(game, { kind = "Undock", actor = player.ship }))
  for _ = 1, 3 do
    Core.Step(game)
  end
  t.ok(Stations.Validate(game.state, { kind = "LoadCharge", actor = player.ship, item = 0 }))
  t.ok(Stations.Validate(game.state, { kind = "BuyNow", actor = player.ship, type = "ammo.emp", quantity = 1 }))
end)

suite:Case("a station's tower is of the faction whose homeworld is nearest of those who build them; the nomads have no station anywhere but their colony ships, which roam", function(t)
  local game = Core.New({ galaxySeed = 3, historySeed = 1, systems = 40, peaceful = true })
  local state = game.state
  local seen: { [string]: boolean } = {}
  local theirs = 0
  for system = 1, 40 do
    local node = state.galaxy.systems[system]
    local stations = 0
    for _, object in Space.Describe(state, system).objects do
      if object.kind == "station" then
        stations += 1
        local makeup = assert(Stations.Makeup(state, object.id))
        -- (a tower, whoever's: no colony ship lies moored anywhere)
        t.eq(makeup.ship, nil, object.name)
        t.ok(object.variety ~= "colony ship", object.name)
        t.eq(Structures.towerById[makeup.tower :: string].faction, node.nearest)
        seen[node.nearest] = true
      end
    end
    -- Among the Kethri there is no station at all; and their towers are nowhere, since they build none: a
    -- system nobody holds has the towers of the nearest people who do.
    if node.owner == "kethri" then
      theirs += 1
      t.eq({ stations, node.nearest } :: { any }, { 0, "kethri" } :: { any }, node.name)
    else
      t.ok(stations >= 1 and node.nearest ~= "kethri", `{node.name}: {stations} stations, of the {node.nearest}`)
    end
  end
  t.ok(theirs >= 1, "the Kethri hold nothing in a galaxy of forty")
  for _, faction in { "vessari", "talmar", "orun" } do
    t.ok(seen[faction], `no station of the {faction} in a galaxy of forty`)
  end
  t.eq(seen.kethri, nil)
  -- Their stations are their colony ships: each a station with an id of its own, in whatever system its
  -- fleet is in now, with everything aboard that a station gives.
  local fleets = Nomads.Fleets(state.galaxy)
  t.ok(#fleets >= 1)
  for _, fleet in fleets do
    local id = Nomads.StationId(fleet.index)
    t.eq(fleet.faction, "kethri")
    local object = assert(Space.Object(state, id), "a colony ship is not a place")
    t.eq({ object.id, object.kind, object.variety, object.radius, object.name } :: { any },
      { id, "station", "colony ship", 5000, fleet.name } :: { any })
    local makeup = assert(Stations.Makeup(state, id))
    t.eq(Structures.colonyShipById[makeup.ship :: string].faction, "kethri")
    -- (all but a moon drill, a reactor and a jump beacon: those are a pilot's tower's)
    t.eq(#Stations.Services(state, id), #Structures.SERVICES - 3)
    local system = Space.SystemOf(state, id)
    t.eq(system, (Nomads.At(fleet, state.tick)))
    t.eq(state.galaxy.systems[system].owner, "kethri")
    -- It lies off a gate of that system, which is what it is said to be by.
    local gate = assert(Space.Peek(state, object.parent))
    t.eq({ gate.kind, gate.id // 10000 } :: { any }, { "gate", system } :: { any })
  end
  -- An id that is nobody's colony ship is no place.
  t.eq(Space.Object(state, Nomads.StationId(#fleets + 1)), nil)
  -- (and a pilot still starts at a station that has everything, in the first faction's space)
  t.eq(state.galaxy.systems[1].owner, "vessari")
  t.eq(Core.Query.Player(game).owner, "Vessari")
end)

return suite
