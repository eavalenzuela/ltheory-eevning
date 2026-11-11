--!strict
-- The directional scanner (Tactical/Dscan).

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Constants = require("@lt/Core/Data/Constants")
local Core = require("@lt/Core/Api")
local Dscan = require("@lt/Core/Tactical/Dscan")
local Items = require("@lt/Core/Assets/Items")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Dscan")

local AU = Constants.AU

local function submit(game: Core.Game, command: State.Command): (boolean, string?)
  command.actor = game.state.player.ship
  local ok, why = Core.Submit(game, command)
  Core.Step(game)
  return ok, why
end

-- The pilot in space and still, in a game where nobody comes for them.
local function still(): (Core.Game, State.Ball)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  assert(submit(game, { kind = "Undock", actor = 0 }))
  assert(submit(game, { kind = "Stop", actor = 0 }))
  local me = game.state.balls[game.state.player.ship]
  me.vx, me.vy, me.vz = 0, 0, 0
  return game, me
end

-- A ship from nowhere, so far from the pilot's along x, and so many
-- degrees round from that line.
local function put(game: Core.Game, me: State.Ball, far: number, degrees: number): number
  local turn = math.rad(degrees)
  return Pirates.Spawn(game.state, Pirates.SCOUT, me.system, me.x + far * math.cos(turn), me.y + far * math.sin(turn), me.z, 0).id
end

-- Which of some things a scan has, in the order asked.
local function has(found: { Core.Sighting }, ids: { number }): { boolean }
  local out: { boolean } = {}
  for index, id in ids do
    out[index] = false
    for _, sighting in found do
      out[index] = out[index] or sighting.id == id
    end
  end
  return out
end

suite:Case("all round, it has every ship and wreck within its range, on the grid or far off it, and says only what they are", function(t)
  local docked = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local nothing, can, why = Core.Query.Directional(docked, nil, 360, Dscan.REACH)
  t.eq({ #nothing, can, why } :: { any }, { 0, false, "docked" } :: { any })

  local game, me = still()
  local state = game.state
  local near, off, far, beyond = put(game, me, 3000, 0), put(game, me, 0.5 * AU, 90), put(game, me, 6 * AU, 200), put(game, me, 20 * AU, 300)
  local ids = { near, off, far, beyond, me.id }
  local found, ok = Core.Query.Directional(game, nil, 360, 14 * AU)
  t.eq(ok, true)
  t.eq(has(found, ids), { true, true, true, false, false })
  t.eq(has(Core.Query.Directional(game, nil, 360, 5 * AU), ids), { true, true, false, false, false })
  t.eq(has(Core.Query.Directional(game, nil, 360, 0.1 * AU), ids), { true, false, false, false, false })
  -- (it reaches fourteen astronomical units, whatever is asked of it)
  t.eq(has(Core.Query.Directional(game, nil, 360, 100 * AU), ids), { true, true, true, false, false })
  -- What it says of one: its name, its hull, and whether the overview has it too.
  for _, sighting in found do
    if sighting.id == near or sighting.id == off then
      t.eq({ sighting.kind, sighting.name, sighting.type, sighting.onGrid } :: { any },
        { "ship", "Pirate Scout", Ships.byId[Pirates.SCOUT.hull].name, sighting.id == near } :: { any })
    end
  end
  -- By name, and those of a name by their ids.
  for index = 2, #found do
    local a, b = found[index - 1], found[index]
    t.ok(a.name < b.name or (a.name == b.name and a.id < b.id), `{a.name} {a.id} is before {b.name} {b.id}`)
  end
  -- The same question has the same answer, and asking changes nothing.
  local before = Core.Hash(game)
  t.eq(Core.Query.Directional(game, nil, 360, 14 * AU), found)
  t.eq(Core.Hash(game), before)

  -- A wreck is on it. A cloaked ship is not.
  Aftermath.Destroy(state, off, 0, game.events)
  local wreck = state.wreckIds[#state.wreckIds]
  local cloak = Items.Equip(state, far, "cloak.device", nil)
  table.insert(state.balls[far].vitals.running, { item = cloak.id, target = 0, next = 1e9, stopping = false, cycles = 0 })
  found = Core.Query.Directional(game, nil, 360, 14 * AU)
  t.eq(has(found, { near, off, far, wreck }), { true, false, false, true })
  for _, sighting in found do
    if sighting.id == wreck then
      t.eq({ sighting.kind, sighting.type, sighting.onGrid } :: { any }, { "wreck", "wreck", false } :: { any })
    end
  end
end)

suite:Case("in a cone, it has what is within half the cone's angle of the line to what it is pointed at", function(t)
  local game, me = still()
  local state = game.state
  local mark = put(game, me, 2 * AU, 0)
  local at: { number } = {}
  for index, degrees in { 4, 6, 14, 16, 44, 46, 180 } do
    at[index] = put(game, me, AU, degrees)
  end
  t.eq(has(Core.Query.Directional(game, mark, 10, 14 * AU), at), { true, false, false, false, false, false, false })
  t.eq(has(Core.Query.Directional(game, mark, 30, 14 * AU), at), { true, true, true, false, false, false, false })
  t.eq(has(Core.Query.Directional(game, mark, 90, 14 * AU), at), { true, true, true, true, true, false, false })
  t.eq(has(Core.Query.Directional(game, mark, 360, 14 * AU), at), { true, true, true, true, true, true, true })
  -- What it is pointed at is in it, if it is in range; and range and cone both count.
  t.eq(has(Core.Query.Directional(game, mark, 10, 14 * AU), { mark }), { true })
  t.eq(has(Core.Query.Directional(game, mark, 10, 1.5 * AU), { mark, at[1] }), { false, true })
  -- Pointed the other way, it has the other one.
  t.eq(has(Core.Query.Directional(game, at[7], 10, 14 * AU), { mark, at[1], at[7] }), { false, false, true })

  -- A cone wants something to be pointed at, somewhere else than the ship.
  local none, ok, why = Core.Query.Directional(game, nil, 10, 14 * AU)
  t.eq({ #none, ok, why } :: { any }, { 0, false, "a cone has to be pointed at something" } :: { any })
  t.eq(select(2, Core.Query.Directional(game, me.id, 10, 14 * AU)), false)
  t.eq(select(2, Core.Query.Directional(game, 987654321, 10, 14 * AU)), false)
  -- A place on the charts will do, and so will one the pilot has marked.
  local sun: number? = nil
  for _, object in Space.Describe(state, me.system).objects do
    sun = if object.kind == "sun" then object.id else sun
  end
  t.eq(select(2, Core.Query.Directional(game, sun, 10, 14 * AU)), true)
  t.ok((submit(game, { kind = "Bookmark", actor = 0 })))
  local marked = state.bookmarkIds[#state.bookmarkIds]
  t.eq(select(2, Core.Query.Directional(game, marked, 10, 14 * AU)), false, "a mark where the ship is points nowhere")
  me.x -= 5000
  t.eq(has(Core.Query.Directional(game, marked, 10, 14 * AU), { mark, at[1], at[7] }), { true, true, false })
end)

return suite
