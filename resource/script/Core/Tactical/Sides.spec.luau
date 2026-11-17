--!strict
-- Sides: whose side the pilot is on in the factions' wars, and what the
-- other side does about it (the owner's four rulings, 2026-11-16: "Enemy
-- of your side", "Blockades stop you", "Stations shut", "Neutral is
-- safe").

local Core = require("@lt/Core/Api")
local Items = require("@lt/Core/Assets/Items")
local Rng = require("@lt/Core/Kernel/Rng")
local Sides = require("@lt/Core/Tactical/Sides")
local Space = require("@lt/Core/Tactical/Space")
local Standings = require("@lt/Core/Assets/Standings")
local Test = require("@lt/Tool/Test")
local Traffic = require("@lt/Core/Tactical/Traffic")
local Wars = require("@lt/Core/Strategic/Wars")

local suite = Test.Suite("Sides")

local function newGame(): Core.Game
  return Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
end

-- The faction the pilot's home system is held by, and another.
local function twoSides(game: Core.Game): (string, string)
  local state = game.state
  local home = state.galaxy.systems[Space.SystemOf(state, state.player.home)].owner
  local other = if home == "talmar" then "vessari" else "talmar"
  return home, other
end

suite:Case("one who has served neither side is nobody's enemy; one who has served a side is its foe's, while the war lasts and they are not forgiven", function(t)
  local game = newGame()
  local state = game.state
  local home, other = twoSides(game)
  t.eq(Sides.EnemyOf(state, home), nil, "neutral is safe")
  t.eq(Sides.EnemyOf(state, other), nil)
  -- (served one side, with no war on: nobody's enemy yet)
  local events = {}
  Sides.Serve(state, other, events)
  t.eq({ #events, events[1].kind, events[1].faction } :: { any }, { 1, "SideTaken", other } :: { any })
  Standings.Change(state, home, -1)
  t.eq(Sides.EnemyOf(state, home), nil, "no war, no enemy")
  -- (at war: the home side counts them its enemy)
  Wars.Declare(state.wars, other, home, state.tick)
  t.eq(Sides.EnemyOf(state, home), other)
  t.eq(Sides.EnemyOf(state, other), nil, "the side served is no enemy")
  -- (forgiven when their standing has come back)
  Standings.Change(state, home, 1)
  t.eq(Sides.EnemyOf(state, home), nil)
  Standings.Change(state, home, -1)
  t.eq(Sides.EnemyOf(state, home), other)
  -- (and when the war is over)
  Wars.Settle(state.wars, other, home, state.tick)
  t.eq(Sides.EnemyOf(state, home), nil)
end)

suite:Case("a side shuts its stations to one on its foe's books", function(t)
  local game = newGame()
  local state = game.state
  local home, other = twoSides(game)
  t.eq(Sides.StationOf(state, state.player.home, Space.SystemOf(state, state.player.home)), home)
  -- (out of the station, and asked to dock again)
  assert(Core.Submit(game, { kind = "Undock", actor = state.player.ship }))
  for _ = 1, 30 do
    Core.Step(game)
  end
  local dock = { kind = "Dock", actor = state.player.ship, target = state.player.home }
  t.ok((Core.Validate(game, dock)), "the pilot's own station takes them")
  Sides.Serve(state, other)
  Standings.Change(state, home, -1)
  Wars.Declare(state.wars, other, home, state.tick)
  local ok, why = Core.Validate(game, dock)
  t.eq(ok, false)
  t.ok(string.find(tostring(why), "shut their stations", 1, true) ~= nil, tostring(why))
end)

suite:Case("a blockade's pickets at a gate are two of the blockading side's warships, one with a warp disruptor", function(t)
  local game = newGame()
  local state = game.state
  local home = twoSides(game)
  assert(Core.Submit(game, { kind = "Undock", actor = state.player.ship }))
  for _ = 1, 30 do
    Core.Step(game)
  end
  local mine = state.balls[state.player.ship]
  local gate = nil
  for _, object in Space.Describe(state, mine.system).objects do
    if object.kind == "gate" and gate == nil then
      gate = object
    end
  end
  assert(gate, "no gate in the home system")
  local events = {}
  local before = #state.shipIds
  local count = Traffic.Picket(state, mine, gate :: any, home, Rng.For(1, 2, 3), events)
  t.eq(count, Traffic.PICKETS)
  local disruptors = 0
  for index = before + 1, #state.shipIds do
    local ship = state.ships[state.shipIds[index]]
    t.eq(ship.owner, home)
    for _, item in Items.Fitted(state, ship.id) do
      disruptors += if item.type == "disruptor.warp" then 1 else 0
    end
  end
  t.eq(disruptors, 1)
  t.eq(events[#events].kind, "PicketArrived")
end)

return suite
