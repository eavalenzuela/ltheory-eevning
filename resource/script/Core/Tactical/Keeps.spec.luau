--!strict
-- The pirates' own towers, and the bringing down of them (Tactical/Keeps).

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Blueprints = require("@lt/Core/Data/Blueprints")
local Codec = require("@lt/Core/Persist/Codec")
local Ships = require("@lt/Core/Data/Ships")
local Constants = require("@lt/Core/Data/Constants")
local Core = require("@lt/Core/Api")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Keeps = require("@lt/Core/Tactical/Keeps")
local Space = require("@lt/Core/Tactical/Space")
local Starbases = require("@lt/Core/Assets/Starbases")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local System = require("@lt/Core/Describe/System")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Keeps")

local HOUR = math.floor(3600 / Constants.TICK + 0.5)

local function steps(game: Core.Game, count: number)
  for _ = 1, count do
    Core.Step(game)
  end
end

-- A galaxy of forty systems with the pilot out in space at home.
local function galaxy(): Core.Game
  local game = Core.New({ galaxySeed = 1, historySeed = 1, systems = 40 })
  assert(Core.Submit(game, { kind = "Undock", actor = game.state.player.ship }))
  Core.Step(game)
  return game
end

-- Put the pilot's ship in a system, beside a thing of it, at rest.
local function put(game: Core.Game, system: number, beside: System.Object?)
  local state = game.state
  local ball = state.balls[state.player.ship]
  local at = beside or Space.Describe(state, system).objects[1]
  ball.system = system
  ball.x, ball.y, ball.z = at.x + at.radius + 3000, at.y, at.z
  ball.vx, ball.vy, ball.vz = 0, 0, 0
  ball.tvx, ball.tvy, ball.tvz = 0, 0, 0
  ball.mode, ball.target = "stop", 0
  ball.warp, ball.intent = nil, nil
  Space.AssignGrid(state, ball)
end

-- The moons of a system with the rarest under them.
local function rare(game: Core.Game, system: number): { System.Object }
  local found: { System.Object } = {}
  for _, object in Space.Describe(game.state, system).objects do
    local deposit = if object.kind == "moon" then Starbases.Deposit(game.state, object.id) else nil
    if deposit and deposit.material.grade >= Keeps.GRADE then
      table.insert(found, object)
    end
  end
  return found
end

-- A game with the pilot beside a keep: the game, the keep and what it is.
local function atKeep(): (Core.Game, State.Keep, State.Ball)
  local game = galaxy()
  local state = game.state
  for id, node in state.galaxy.systems do
    if Galaxy.Band(node.security) == "lawless" and #rare(game, id) > 0 then
      put(game, id, nil)
      Core.Step(game)
      local keep = state.keeps[state.keepIds[1]]
      put(game, id, assert(Space.Object(state, keep.id)))
      Core.Step(game)
      Core.TakeEvents(game)
      return game, keep, assert(state.balls[keep.core])
    end
  end
  error("no lawless system has a moon with the rarest under it")
end

-- The pirates of a keep's place that are there: those that fly, and those that stand.
local function about(game: Core.Game, keep: State.Keep): (number, number)
  local flying, standing = 0, 0
  for _, id in game.state.pilotIds do
    local ball = game.state.balls[id]
    if game.state.pilots[id].home == keep.id and ball and id ~= keep.core then
      flying += if ball.maxVelocity > 0 then 1 else 0
      standing += if ball.maxVelocity > 0 then 0 else 1
    end
  end
  return flying, standing
end

-- So many ticks with the pilot's ship made whole after each, and with
-- more hull than a tick of anything can take off it (these are about
-- the keep, not about who outlasts what comes for them: and which keep
-- it is, and so what comes, is as the galaxy falls out).
local function held(game: Core.Game, count: number)
  for _ = 1, count do
    local mine = game.state.balls[game.state.player.ship]
    if mine then
      mine.vitals.hullMax = 1e9
      mine.vitals.shield, mine.vitals.armor, mine.vitals.hull = mine.vitals.shieldMax, mine.vitals.armorMax, mine.vitals.hullMax
    end
    Core.Step(game)
  end
end

local function said(game: Core.Game, kind: string): { [string]: any }?
  local found: { [string]: any }? = nil
  for _, event in Core.TakeEvents(game) do
    found = if event.kind == kind then event else found
  end
  return found
end

suite:Case("where nobody keeps order pirates hold every moon with the rarest under it, with a tower and its batteries; and nowhere else", function(t)
  local game = galaxy()
  local state = game.state
  local held, lawless = 0, 0
  for id, node in state.galaxy.systems do
    local band = Galaxy.Band(node.security)
    put(game, id, nil)
    local before = #state.keepIds
    Core.Step(game)
    local here = #state.keepIds - before
    if (node.depth or 0) > Galaxy.PIRATE_DEPTH then
      -- (past the third depth of uncharted space not even pirates live)
      t.eq(here, 0, `a keep where no pirate lives, in system {id}`)
    elseif band == "lawless" then
      lawless += 1
      t.eq(here, #rare(game, id), `system {id}`)
      held += here
    else
      t.eq(here, 0, `a keep where order is kept, in system {id}`)
    end
    -- (once, however often the pilot comes)
    Core.Step(game)
    t.eq(#state.keepIds - before, here)
  end
  t.ok(lawless > 0 and held > 0, `{held} keeps in {lawless} lawless systems`)
  print(`     keeps: {held} moons held in {lawless} lawless systems of forty`)
  for _, id in state.keepIds do
    local keep = state.keeps[id]
    local place = assert(Space.Object(state, id))
    local moon = assert(Space.Object(state, keep.moon))
    local core = assert(state.balls[keep.core])
    t.eq({ place.name, place.parent, state.sites[id].kind, state.sites[id].strength } :: { any },
      { `{moon.name} - Pirate Tower`, moon.id, "keep", 1 } :: { any })
    t.eq({ state.ships[keep.core].type, state.ships[keep.core].owner, core.grid, core.maxVelocity, keep.charges } :: { any },
      { "works.keep", "pirates", id, 0, Keeps.HOURS } :: { any })
    local flying, standing = about(game, keep)
    t.eq({ flying, standing }, { 0, Keeps.BATTERIES })
    t.eq(Keeps.At(state, moon.id), keep)
    t.eq(Keeps.Of(state, keep.core), keep)
  end
  -- They stay as they are left, with the pilot far off.
  put(game, 1, nil)
  local count = #state.pilotIds
  steps(game, 600)
  t.eq(#state.pilotIds, count)
end)

suite:Case("nobody anchors a tower at a moon the pirates hold", function(t)
  local game, keep = atKeep()
  local state = game.state
  local moon = assert(Space.Object(state, keep.moon))
  put(game, keep.system, moon)
  local tower = Items.Add(state, "tower.vessari.small", 1, state.player.ship, "cargo")
  local ok, why = Core.Validate(game, { kind = "AnchorTower", actor = state.player.ship, item = tower.id, target = moon.id })
  t.eq({ ok, why } :: { any }, { false, "pirates hold that moon: bring their tower down first" } :: { any })
end)

suite:Case("under fire a keep calls for help, and its shield at a quarter it seals: it cannot be locked, those who came go, and its batteries stand", function(t)
  local game, keep, core = atKeep()
  local state = game.state
  local me = state.player.ship
  t.ok((Core.Validate(game, { kind = "LockTarget", actor = me, target = core.id })))
  -- Its shield hurt: a pack comes, and after a while another; and no more.
  core.vitals.shield = 0.8 * core.vitals.shieldMax
  held(game, 2)
  local called = said(game, "KeepCalled")
  t.ok(called ~= nil and (called :: any).call == 1, "the keep did not call for help")
  local first = about(game, keep)
  t.ok(first >= 2, `{first} came to its help`)
  core.vitals.shield = 0.8 * core.vitals.shieldMax
  held(game, math.ceil(Keeps.CALL / Constants.TICK) + 2)
  local second = about(game, keep)
  t.ok(second > first and keep.calls == 2, `{second} are there after its second call`)
  core.vitals.shield = 0.8 * core.vitals.shieldMax
  held(game, math.ceil(Keeps.CALL / Constants.TICK) + 2)
  t.eq(keep.calls, Keeps.CALLS)
  -- At a quarter: sealed, for its hours.
  Core.TakeEvents(game)
  core.vitals.shield = 0.2 * core.vitals.shieldMax
  held(game, 2)
  local sealed = said(game, "KeepSealed")
  t.ok(sealed ~= nil and (sealed :: any).hours == Keeps.HOURS, "the keep did not seal")
  t.eq({ Keeps.Sealed(state, keep), keep.charges } :: { any }, { true, 0 } :: { any })
  local flying, standing = about(game, keep)
  t.eq({ flying, standing }, { 0, Keeps.BATTERIES })
  local ok, why = Core.Validate(game, { kind = "LockTarget", actor = me, target = core.id })
  t.eq({ ok, why } :: { any }, { false, "the tower has sealed itself" } :: { any })
  -- (in the save, sealed)
  local data, length = Core.Save(game)
  t.eq(Core.Hash(Core.Load(data, length)), Core.Hash(game))
  -- It opens with its shield where it was, and nothing to seal with
  -- again. (The pilot waits out of the way of its batteries.)
  put(game, 1, nil)
  steps(game, Keeps.HOURS * HOUR)
  t.ok(said(game, "KeepOpened") ~= nil, "the keep did not open")
  t.near(core.vitals.shield / core.vitals.shieldMax, Keeps.QUARTER, 0.02)
  put(game, keep.system, assert(Space.Object(state, keep.id)))
  held(game, 1)
  t.ok((Core.Validate(game, { kind = "LockTarget", actor = me, target = core.id })))
  core.vitals.shield = 0.1 * core.vitals.shieldMax
  held(game, 3)
  t.eq(Keeps.Sealed(state, keep), false)
  -- Left alone for a day, it is whole again, has its charges, and a
  -- battery for the one it lost.
  for _, id in table.clone(state.pilotIds) do
    if state.pilots[id].home == keep.id and id ~= keep.core then
      Aftermath.Destroy(state, id, me, game.events)
      break
    end
  end
  t.eq(Keeps.Batteries(state, keep), Keeps.BATTERIES - 1)
  put(game, 1, nil)
  steps(game, Keeps.RESTOCK * HOUR + 5)
  t.ok(said(game, "KeepRestocked") ~= nil, "nobody said it was resupplied")
  t.eq({ keep.charges, core.vitals.shield, core.vitals.armor, Keeps.Batteries(state, keep) } :: { any },
    { Keeps.HOURS, core.vitals.shieldMax, core.vitals.armorMax, Keeps.BATTERIES } :: { any })
end)

suite:Case("a keep destroyed pays its bounty and leaves what it had in its wreck; its place is gone, and the moon is anybody's", function(t)
  local game, keep, core = atKeep()
  local state = game.state
  local moon = assert(Space.Object(state, keep.moon))
  local deposit = assert(Starbases.Deposit(state, keep.moon))
  local wallet = state.wallet
  Aftermath.Destroy(state, core.id, state.player.ship, game.events)
  local lost = said(game, "KeepLost")
  t.ok(lost ~= nil and (lost :: any).moon == moon.id, "nobody said the keep was lost")
  t.ok(state.wallet - wallet >= 500000, `it paid {state.wallet - wallet}`)
  t.eq({ state.keeps[keep.id], #state.keepIds == 0 or Keeps.At(state, moon.id) == nil, state.sites[keep.id].gone } :: { any },
    { nil, true, true } :: { any })
  local wreck = state.wrecks[state.wreckIds[#state.wreckIds]]
  local stock, charges, hullPrints, towerCopies = 0, 0, 0, 0
  for _, item in Items.In(state, wreck.id, "cargo") do
    stock += if item.type == deposit.material.id then item.quantity else 0
    charges += if item.type == Structures.SEAL.id then item.quantity else 0
    -- (the drawings of a pirate hull, the original: the owner's, 2026-11-16)
    local print, copy = Blueprints.Of(item.type)
    local made = if print then Ships.byId[print.product] else nil
    hullPrints += if print and not copy and made and made.lineage == "unbound" then item.quantity else 0
    -- (and, its commander an officer by name, a copy of a pirate tower's)
    local tower = if print then Structures.towerById[print.product] else nil
    towerCopies += if copy and tower and tower.faction == "unbound" then 1 else 0
  end
  t.ok(stock >= Keeps.STOCK[1] and stock <= Keeps.STOCK[2], `{stock} units of the moon's material in its wreck`)
  t.eq(charges, Keeps.CHARGES)
  t.eq({ hullPrints, towerCopies } :: { any }, { 1, 1 } :: { any }, "a pirate hull's print, and a copy of a pirate tower's")
  -- The moon takes the pilot's tower now.
  put(game, keep.system, moon)
  local tower = Items.Add(state, "tower.vessari.small", 1, state.player.ship, "cargo")
  local ok, why = Core.Validate(game, { kind = "AnchorTower", actor = state.player.ship, item = tower.id, target = moon.id })
  t.ok(ok, `anchoring at the freed moon was refused: {tostring(why)}`)
  -- And it is not put up again, however often the pilot comes back.
  steps(game, 50)
  t.eq(Keeps.At(state, moon.id), nil)
end)

suite:Case("a save from before there were keeps opens with none, and they are put up as the pilot comes to each system", function(t)
  local game, keep = atKeep()
  local data, length = Core.Save(game)
  local file = Codec.Decode(data, length)
  file.saveVersion = 62
  file.state.keeps, file.state.keepIds, file.state.keepsSeen = nil, nil, nil
  local old, oldLength = Codec.Encode(file)
  local opened = Core.Load(old, oldLength)
  t.eq({ #opened.state.keepIds, opened.state.keepsSeen[keep.system] } :: { any }, { 0, nil } :: { any })
  Core.Step(opened)
  t.ok(#opened.state.keepIds > 0, "the keeps of the system the pilot is in should be put up")
end)

return suite
