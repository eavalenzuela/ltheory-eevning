--!strict
-- Fortresses: one to a lawless region, fought ring, guard and core, sealing at a quarter, and found again elsewhere when fallen.

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Blueprints = require("@lt/Core/Data/Blueprints")
local Captains = require("@lt/Core/Tactical/Captains")
local Core = require("@lt/Core/Api")
local Fortresses = require("@lt/Core/Tactical/Fortresses")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Fortresses")

type Event = { [string]: any }

local function said(events: { Event }, kind: string): Event?
  for _, event in events do
    if event.kind == kind then
      return event
    end
  end
  return nil
end

-- The pilot's ship put in a system, at a point, at rest.
local function put(state: State.State, system: number, x: number, y: number, z: number)
  local ball = state.balls[state.player.ship]
  ball.system = system
  ball.x, ball.y, ball.z = x, y, z
  ball.vx, ball.vy, ball.vz = 0, 0, 0
  ball.warp, ball.intent = nil, nil
  Space.AssignGrid(state, ball)
end

-- Whoever of the fortress's place is of its ring, or of its guard.
local function of(state: State.State, fortress: State.Fortress, moving: boolean): { number }
  local found: { number } = {}
  for _, id in table.clone(state.pilotIds) do
    local ball = state.balls[id]
    if ball and state.pilots[id].home == fortress.place and id ~= fortress.core and id ~= fortress.hoard
      and (ball.maxVelocity > 0) == moving then
      table.insert(found, id)
    end
  end
  return found
end

suite:Case("a lawless region has a fortress: its ring, then its guard of capitals led by name, then the core, which seals at a quarter; fallen, it leaves a pirate capital's drawings", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, systems = 120 })
  local state = game.state
  t.ok(Core.Submit(game, { kind = "Undock", actor = state.player.ship }))
  Core.Step(game)
  local lawless = 0
  for id = 1, Galaxy.Charted(state.galaxy) do
    if lawless == 0 and Galaxy.Band(state.galaxy.systems[id].security) == "lawless" and not state.galaxy.systems[id].home then
      lawless = id
    end
  end
  t.ok(lawless ~= 0, "no lawless system")
  local region = state.galaxy.systems[lawless].region
  put(state, lawless, 1e12, 0, 0)
  Core.TakeEvents(game)
  Core.Step(game)
  local known = said(Core.TakeEvents(game), "FortressKnown")
  local fortress = assert(state.fortresses.list[region], "no fortress in the region")
  t.ok(known ~= nil and known.system == fortress.system)
  t.eq({ state.galaxy.systems[fortress.system].region, Galaxy.Band(state.galaxy.systems[fortress.system].security) } :: { any },
    { region, "lawless" } :: { any })
  -- Nothing in space till the pilot is in its system.
  if fortress.system ~= lawless then
    t.eq(fortress.place, 0)
  end
  put(state, fortress.system, 1e12, 0, 0)
  Core.Step(game)
  local place = assert(Space.Object(state, fortress.place), "it was not put in space")
  t.eq({ state.ships[fortress.core].type, #of(state, fortress, false), state.ships[fortress.hoard].type } :: { any },
    { "works.fortress", #Fortresses.RING_KINDS, "capitalindustrial.hoard" } :: { any })
  put(state, fortress.system, place.x + 30000, place.y, place.z)
  t.eq(state.balls[state.player.ship].grid, fortress.place)
  Core.Step(game)
  t.eq(fortress.cover, "its batteries cover it: bring them down first")
  -- The ring down: the guard comes, led by name in a Matriarch.
  for _, id in of(state, fortress, false) do
    Aftermath.Destroy(state, id, state.player.ship, game.events)
  end
  Core.TakeEvents(game)
  Core.Step(game)
  local events = Core.TakeEvents(game)
  local came = assert(said(events, "FortressGuard"), "no guard came")
  local guard = of(state, fortress, true)
  t.eq(#guard, #Fortresses.GUARD + 1)
  local leader = assert(Captains.Get(state, fortress.captain))
  t.eq(came.name, `Captain {leader.name}`)
  local capitals = 0
  for _, id in guard do
    capitals += if Ships.Capital(Ships.byId[state.ships[id].type].class) then 1 else 0
  end
  t.eq(capitals, 4)
  t.eq(fortress.cover, "its guard covers it: bring them down first")
  local ok, why = Core.Validate(game, { kind = "LockTarget", actor = state.player.ship, target = fortress.core })
  t.eq({ ok, why } :: { any }, { false, fortress.cover } :: { any })
  for _, id in guard do
    if state.balls[id] then
      Aftermath.Destroy(state, id, state.player.ship, game.events)
    end
  end
  t.eq(leader.alive, false, "the guard's leader was not gone for good")
  Core.Step(game)
  t.eq(fortress.cover, "")
  -- At a quarter, sealed; open again with its shield where it was.
  local core = state.balls[fortress.core]
  core.vitals.shield = 0.2 * core.vitals.shieldMax
  Core.Step(game)
  t.ok(Fortresses.Sealed(state, fortress) and fortress.cover == "the fortress has sealed itself")
  state.tick = fortress.sealed
  Core.Step(game)
  t.ok(not Fortresses.Sealed(state, fortress) and fortress.charges == 0)
  -- (in the save)
  local data, length = Core.Save(game)
  t.eq(Core.Hash(Core.Load(data, length)), Core.Hash(game))
  -- Brought down: its commander's things and a pirate capital's drawings in the wreck, and it is gone.
  Core.TakeEvents(game)
  Aftermath.Destroy(state, fortress.core, state.player.ship, game.events)
  t.ok(said(Core.TakeEvents(game), "FortressLost") ~= nil)
  local wreck = state.wrecks[state.wreckIds[#state.wreckIds]]
  local drawings = 0
  for _, item in Items.In(state, wreck.id, "cargo") do
    local print = Blueprints.byId[item.type]
    local hull = if print then Ships.byId[print.product] else nil
    drawings += if hull and Ships.Capital(hull.class) and hull.lineage == "unbound" then 1 else 0
  end
  t.eq(drawings, 1)
  t.eq(state.fortresses.list[region], nil)
  t.eq(state.fortresses.fell[region], state.tick)
  -- (and no other in the region for a day)
  Core.Step(game)
  t.eq(state.fortresses.list[region], nil)
  t.ok(Pirates.kindById.fortress.bounty > 0)
end)

return suite
