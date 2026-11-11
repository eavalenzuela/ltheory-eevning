--!strict
-- What can be done at a station (Assets/Stations): only what it has a
-- module for.

local Core = require("@lt/Core/Api")
local State = require("@lt/Core/Kernel/State")
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

suite:Case("the galaxy has stations that lack a service, and no other station has everything", function(t)
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
      lacking += if Stations.Has(game.state, station.id, "market") then 0 else 1
    end
  end
  t.ok(lacking > 0, "every station has a market: this galaxy cannot show a service being refused")
end)

suite:Case("what a station has no module for is refused there, by name, and allowed at the starter", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1 })
  local state = game.state
  local player = Core.Query.Player(game)
  local buy: State.Command = { kind = "BuyNow", actor = player.ship, type = "ammo.emp", quantity = 10 }
  local fit: State.Command = { kind = "Fit", actor = player.ship, item = 0 }
  for _, item in Core.Query.Items(game, player.docked, "hangar") do
    if item.type == "shield.extender.small" then
      fit.item = item.id
    end
  end
  t.ok(Stations.Validate(state, buy), "the starter station refused a purchase")
  t.ok(Stations.Validate(state, fit), "the starter station refused a fitting")

  -- Moor the same ship at each other station in turn: what it lacks, it refuses.
  local home = state.ships[player.ship].docked
  local refused = 0
  for _, station in stations(game) do
    if station.id ~= home then
      state.ships[player.ship].docked = station.id
      for _, command in { buy, fit } :: { State.Command } do
        local service: Structures.Service = if command.kind == "BuyNow" then "market" else "fitting"
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

return suite
