--!strict
-- A citadel's hulk (the owner's B2, 2026-11-17: a citadel brought down
-- "leave[s] a giant derelict hulk, which 1) is a loot container, 2) can
-- be salvaged to clear it, or 3) can be rebuilt into a working citadel
-- owned by whoever loads the materials into the 'container' and clicks
-- rebuild").
--
-- A citadel that falls, in a fight or to a raid nobody saw, leaves its
-- hulk where it stood: a wreck that does not drift off (Kernel/State's
-- 'hulk'), on a grid of its own, a place in its system's description
-- that can be warped to. In it is half of what was stored there (the
-- owner, 2026-11-18: "Half survives", each stack by its own roll, as a
-- ship's wreck), and some of what was fitted in it, packed.
--
-- Anybody may loot it (Tactical/Aftermath's Loot), from a little off its
-- hull. A salvager brings off a hulk's worth a cycle at a time, so many
-- cycles by its size (Tactical/Combat): it is gone when there is no
-- more of it to salvage and nothing left in it.
--
-- Or it is rebuilt (the command Rebuild): for half of what its print
-- takes (the owner, the same day: "half the materials, and the rebuild
-- pane (right-click -> rebuild) will tell you which materials are
-- needed for it. It picks the materials needed"), taken from the
-- rebuilding ship's hold. It is then that pilot's citadel, where it
-- stood, unfuelled and anchoring again, with nothing fitted; what was
-- left in it is in its hangar.
--
-- An alien people's citadel (Data/Structures' CITADEL_ALIEN) has the
-- drawing of it in its hulk (the owner, 2026-11-18: "Copy, rare
-- original"): a copy of one to three runs, and one hulk in ten the
-- original.
--
-- (Every figure here is mine but the half and the alien drawings: the
-- cycles, the share of what was fitted that is found, how near a ship
-- has to be.)

local Blueprints = require("@lt/Core/Data/Blueprints")
local Constants = require("@lt/Core/Data/Constants")
local Items = require("@lt/Core/Assets/Items")
local Rng = require("@lt/Core/Kernel/Rng")
local Space = require("@lt/Core/Tactical/Space")
local Starbases = require("@lt/Core/Assets/Starbases")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local System = require("@lt/Core/Describe/System")
local Types = require("@lt/Core/Data/Types")

local Hulks = {}

export type Event = { [string]: any }

-- The variety of a hulk's place in its system's description.
Hulks.VARIETY = "hulk"
-- A salvager's cycles of a hulk, by the citadel's size.
Hulks.CYCLES = { 20, 40, 100, 200, 400 }
-- What a salvager brings off a hulk in a cycle, by its size: so many
-- times a ship wreck's least.
Hulks.PIECES = { 4, 6, 10, 14, 20 }
-- The share of what was stored there that is found in it, and of what
-- was fitted in it.
Hulks.STORED = 0.5
Hulks.FITTED = 1 / 3
-- One alien hulk in so many has its citadel's original print, and the
-- others a copy of so many runs at most.
Hulks.ORIGINAL = 1 / 10
Hulks.RUNS = 3
-- The share of its print's materials that rebuilds it.
Hulks.REBUILD = 0.5
-- How near a ship has to be to rebuild it, from its hull: as near as for
-- looting.
Hulks.REACH = 2500
-- (it lasts until it is cleared: this far off)
local NEVER = 2 ^ 50

-- Whether a wreck is a hulk.
function Hulks.Is(wreck: State.Wreck?): boolean
  return wreck ~= nil and wreck.hulk ~= nil
end

-- A hulk's wreck, where a citadel stood ('object', its station), with
-- nothing in it yet.
local function newHulk(state: State.State, system: number, object: System.Object, tower: Structures.Tower): State.Wreck
  local wreck: State.Wreck = {
    id = State.NewId(state), kind = "wreck", name = `{tower.name} Hulk`, system = system, grid = object.id,
    x = object.x, y = object.y, z = object.z, radius = tower.reach or object.radius, hull = "", expires = NEVER,
    salvaged = false, locked = false, lock = "",
    hulk = tower.id, salvage = Hulks.CYCLES[tower.size] or Hulks.CYCLES[1], under = object.parent,
  }
  state.wrecks[wreck.id] = wreck
  table.insert(state.wreckIds, wreck.id)
  return wreck
end

-- What of a citadel's fittings is found in its hulk (each by its own
-- roll), and an alien people's drawing of it.
local function found(state: State.State, wreck: State.Wreck, tower: Structures.Tower, fitted: { string }, at: number)
  for index, type in fitted do
    local rng = Rng.For(state.historySeed, state.tick, at, index, 5102)
    if Types.Get(type) and Rng.Chance(rng, Hulks.FITTED) then
      Items.Add(state, type, 1, wreck.id, "cargo")
    end
  end
  local print = Blueprints.byProduct[tower.id]
  if tower.faction ~= "" and print then
    local rng = Rng.For(state.historySeed, state.tick, at, 5103)
    if Rng.Chance(rng, Hulks.ORIGINAL) then
      Items.Add(state, print.id, 1, wreck.id, "cargo")
    else
      Items.Add(state, Blueprints.Copy(print), 1 + Rng.Int(rng, Hulks.RUNS), wreck.id, "cargo")
    end
  end
end

-- A pilot's citadel falls: its hulk, with what of its hangar and its
-- fittings survives (what does not is gone). Its station's place is
-- still a station's here: Hulks.Stand makes it the hulk's, once the
-- station is removed (Assets/Starbases' Remove). Nil if it is no
-- citadel.
function Hulks.Leave(state: State.State, starbase: State.Starbase, events: { Event }): State.Wreck?
  local tower = Structures.towerById[starbase.tower]
  local object = Space.Object(state, starbase.id)
  if tower == nil or not tower.citadel or object == nil then
    return nil
  end
  local wreck = newHulk(state, Space.SystemOf(state, starbase.id), object, tower)
  for _, item in Items.Stored(state, starbase.id) do
    local rng = Rng.For(state.historySeed, state.tick, starbase.id, item.id, 5101)
    local type, quantity = item.type, item.quantity
    Items.Take(state, item, quantity)
    if Rng.Chance(rng, Hulks.STORED) then
      Items.Add(state, type, quantity, wreck.id, "cargo")
    end
  end
  local fitted: { string } = {}
  for _, module in starbase.modules do
    table.insert(fitted, module.type)
  end
  found(state, wreck, tower, fitted, starbase.id)
  table.insert(events, { kind = "WreckAdded", wreck = wreck.id, hulk = true })
  return wreck
end

-- A faction's citadel falls, or the pilot first comes where one fell
-- long ago (Assets/Citadels): its hulk, where its station is, with what
-- of its fittings ('fitted') is found. Its place is the hulk's now.
function Hulks.Make(state: State.State, system: number, object: System.Object, tower: Structures.Tower, fitted: { string },
  events: { Event }): State.Wreck
  local wreck = newHulk(state, system, object, tower)
  found(state, wreck, tower, fitted, object.id)
  Hulks.Stand(state, wreck, object.id)
  table.insert(events, { kind = "WreckAdded", wreck = wreck.id, hulk = true })
  return wreck
end

-- Its place in the system's description, the hulk's: somewhere to warp
-- to, the middle of a grid of its own, as big as the citadel was (the
-- station's that was: 'at'). Whoever is near is on its grid again.
function Hulks.Stand(state: State.State, wreck: State.Wreck, at: number)
  local object = Space.Object(state, at)
  if object == nil then
    return
  end
  wreck.grid = at
  object.kind, object.variety, object.site, object.parent, object.radius, object.to =
    "belt", Hulks.VARIETY, object.id, wreck.under or 0, wreck.radius, 0
  if string.sub(object.name, -5) ~= " Hulk" then
    object.name = `{object.name} Hulk`
  end
  for _, id in state.ballIds do
    local ball = state.balls[id]
    if ball.system == wreck.system and not (ball.warp and ball.warp.stage == "warp")
      and Space.Distance(ball :: any, object :: any) < Constants.GRID_RADIUS then
      Space.AssignGrid(state, ball)
    end
  end
  for _, id in state.wreckIds do
    local other = state.wrecks[id]
    if other.system == wreck.system and Space.Distance(other :: any, object :: any) < Constants.GRID_RADIUS then
      other.grid = object.id
    end
  end
end

-- A hulk is gone (salvaged out and emptied, or rebuilt): its place is
-- nothing, as a tower's taken down is (Assets/Starbases' Remove).
function Hulks.Clear(state: State.State, wreck: State.Wreck)
  local object = Space.Object(state, wreck.grid)
  if object and object.variety == Hulks.VARIETY then
    object.kind, object.site, object.parent, object.variety, object.radius, object.to = "gone", 0, 0, "", 0, 0
    for _, id in state.ballIds do
      local ball = state.balls[id]
      if ball.grid == object.id then
        Space.AssignGrid(state, ball)
      end
    end
  end
end

-- What rebuilding a hulk takes: half of what its print takes, each
-- material rounded up. Empty if there is no print of it.
function Hulks.Needs(tower: string): { { type: string, quantity: number } }
  local print = Blueprints.byProduct[tower]
  local needs: { { type: string, quantity: number } } = {}
  if print == nil then
    return needs
  end
  for _, material in print.materials do
    table.insert(needs, { type = material.type, quantity = math.ceil(material.quantity * Hulks.REBUILD) })
  end
  return needs
end

-- How much of a type is in a ship's hold.
local function held(state: State.State, ship: number, type: string): number
  local count = 0
  for _, item in Items.In(state, ship, "cargo") do
    if item.type == type then
      count += item.quantity
    end
  end
  return count
end

-- What rebuilding it takes, each with how much of it the ship has.
function Hulks.Lacking(state: State.State, ship: number, tower: string): { { type: string, quantity: number, have: number } }
  local out: { { type: string, quantity: number, have: number } } = {}
  for _, need in Hulks.Needs(tower) do
    table.insert(out, { type = need.type, quantity = need.quantity, have = held(state, ship, need.type) })
  end
  return out
end

-- The moon or planet a hulk stood at, if it is there still.
local function underOf(state: State.State, wreck: State.Wreck): System.Object?
  local under = if wreck.under and wreck.under ~= 0 then Space.Object(state, wreck.under) else nil
  return if under and (under.kind == "moon" or under.kind == "planet") then under else nil
end

function Hulks.Validate(state: State.State, command: State.Command): (boolean, string?)
  local ship = state.ships[command.actor]
  local ball = if ship then state.balls[ship.id] else nil
  if ship == nil then
    return false, "no such ship"
  elseif ball == nil then
    return false, "docked"
  elseif ball.warp and ball.warp.stage == "warp" then
    return false, "in warp"
  end
  local wreck = state.wrecks[command.target or 0]
  if wreck == nil or wreck.hulk == nil then
    return false, "not a citadel's hulk"
  elseif wreck.system ~= ball.system or Space.Gap(ball :: any, wreck :: any) > Hulks.REACH then
    return false, "too far from the hulk"
  end
  local under = underOf(state, wreck)
  if under == nil then
    return false, "what it was anchored at is not there"
  end
  for _, object in Space.Describe(state, ball.system).objects do
    if object.kind == "station" and object.parent == under.id and state.starbases[object.id] then
      return false, `that {under.kind} has a tower or a citadel already`
    end
  end
  local needs = Hulks.Lacking(state, ship.id, wreck.hulk)
  if #needs == 0 then
    return false, "nobody knows how it was built"
  end
  for _, need in needs do
    if need.have < need.quantity then
      return false, `not enough {Types.Info(need.type).name} in the hold: {need.have} of {need.quantity}`
    end
  end
  return true
end

-- Rebuild it: the materials out of the hold, the hulk gone, and a
-- citadel of the ship's owner's where it stood, anchoring.
function Hulks.Apply(state: State.State, command: State.Command, events: { Event })
  local ship = state.ships[command.actor]
  local ball = state.balls[ship.id]
  local wreck = state.wrecks[command.target :: number]
  local tower = Structures.towerById[wreck.hulk :: string]
  for _, need in Hulks.Needs(tower.id) do
    local left = need.quantity
    for _, item in Items.In(state, ship.id, "cargo") do
      if left > 0 and item.type == need.type then
        local taken = math.min(left, item.quantity)
        Items.Take(state, item, taken)
        left -= taken
      end
    end
  end
  local under = underOf(state, wreck) :: System.Object
  Hulks.Clear(state, wreck)
  local id = Starbases.Raise(state, wreck.system, under, tower, ship.owner, wreck.x, wreck.y, wreck.z)
  -- (what was left in it is in the new citadel's hangar)
  for _, item in Items.In(state, wreck.id, nil) do
    local type, quantity = item.type, item.quantity
    Items.Take(state, item, quantity)
    Items.Add(state, type, quantity, id, "hangar")
  end
  state.wrecks[wreck.id] = nil
  State.RemoveId(state.wreckIds, wreck.id)
  table.insert(events, { kind = "WreckRemoved", wreck = wreck.id })
  for _, other in state.ballIds do
    local near = state.balls[other]
    if near.system == ball.system and not (near.warp and near.warp.stage == "warp") then
      Space.AssignGrid(state, near)
    end
  end
  table.insert(events, { kind = "HulkRebuilt", station = id, tower = tower.id, by = ship.id })
end

return Hulks
