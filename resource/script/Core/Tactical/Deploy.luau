--!strict
-- Deploy: what a pilot puts out into space from the hold, and picks up
-- again (Data/Deployables; the owner's, 2026-11-20).
--
-- One is put out from the ship's hold, in space, out of warp, clear of
-- stations and gates; and picked up into the hold again, from close by,
-- once it is empty. It is a container in space of the pilot's (a wreck
-- that is a 'can': Tactical/Aftermath), so that what is jettisoned near
-- it goes into it, and what is in it is looted out of it, as far as its
-- hold lets it. Each does what its kind does:
--
--   depot     a ship near it may be refitted there (Assets/Items): what
--             comes out of the ship goes into the depot
--   tractor   draws the nearest wreck in its reach to itself, at a
--             tractor beam's speed, and takes what is in it when it is
--             there; then the next
--   beacon    is a lit beacon for the pilot's jump drives (Tactical/
--             Jumping)
--   bubble    holds an interdiction field where it stands (Tactical/
--             Combat)
--
-- One with a life (a tractor, a beacon) becomes a plain container at its
-- end, with what is in it, which then goes as a jettisoned one does.

local Constants = require("@lt/Core/Data/Constants")
local Deployables = require("@lt/Core/Data/Deployables")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Types = require("@lt/Core/Data/Types")

export type Event = { [string]: any }

local Deploy = {}

-- A tick no game reaches: one that lasts until it is picked up.
local NEVER = 2 ^ 50
-- How fast a tractor draws a wreck in (a tractor beam's: m/s, mine), and
-- how long what is left of a container lasts once its life is over.
Deploy.PULL = 1000
local LEFT = 7200

-- The deployable a container is, if it is one.
function Deploy.Of(wreck: State.Wreck?): Deployables.Deployable?
  return if wreck and wreck.deploy then Deployables.byId[wreck.deploy] else nil
end

-- The pilot's deployable of a kind nearest a ship and in reach of it, if
-- there is one.
function Deploy.Near(state: State.State, ship: number, kind: string): State.Wreck?
  local ball = state.balls[ship]
  if ball == nil then
    return nil
  end
  local best: State.Wreck?, least = nil, Deployables.REACH
  for _, id in state.wreckIds do
    local wreck = state.wrecks[id]
    local what = Deploy.Of(wreck)
    if what and what.kind == kind and wreck.system == ball.system then
      local gap = Space.Gap(ball :: any, wreck :: any)
      if gap <= least then
        best, least = wreck, gap
      end
    end
  end
  return best
end

-- How much is in one's hold, m3.
function Deploy.Used(state: State.State, wreck: State.Wreck): number
  local used = 0
  for _, item in Items.In(state, wreck.id, nil) do
    used += Types.Info(item.type).volume * item.quantity
  end
  return used
end

function Deploy.Validate(state: State.State, command: State.Command): (boolean, string?)
  local ship = state.ships[command.actor]
  local ball = if ship then state.balls[ship.id] else nil
  if ship == nil or ball == nil then
    return false, "not in space"
  elseif ball.warp and ball.warp.stage == "warp" then
    return false, "in warp"
  end
  if command.kind == "Deploy" then
    local item = state.items[command.item or 0]
    local what = if item then Deployables.byId[item.type] else nil
    if item == nil or what == nil then
      return false, "nothing to put out"
    elseif item.holder ~= ship.id or item.place ~= "cargo" then
      return false, "it has to be in the ship's hold"
    end
    -- (clear of what is anchored for everybody: stations and gates)
    local description = state.systems[ball.system]
    local objects: { any } = if description then description.objects else {}
    for _, object in objects do
      if (object.kind == "station" or object.kind == "gate") and Space.Gap(ball :: any, object :: any) < Deployables.CLEAR then
        return false, `too near the {object.kind}: keep {math.floor(Deployables.CLEAR / 1000)} km off`
      end
    end
    if what.kind == "bubble" and Galaxy.Band(state.galaxy.systems[ball.system].security) == "secure" then
      return false, "not where order is kept"
    end
    return true
  elseif command.kind == "Scoop" then
    local wreck = state.wrecks[command.target or 0]
    local what = Deploy.Of(wreck)
    if wreck == nil or what == nil then
      return false, "nothing to pick up"
    elseif what.kind == "beacon" then
      -- (a beacon lit stays lit till its time is out: the owner, 2026-11-22.
      -- What has a hold, a depot or a tractor, is picked up and put out
      -- again as often as liked)
      return false, "a lit beacon burns till its time is out"
    elseif wreck.system ~= ball.system or Space.Gap(ball :: any, wreck :: any) > Deployables.REACH then
      return false, "too far away"
    elseif #Items.In(state, wreck.id, nil) > 0 then
      return false, "empty it first"
    elseif Items.ShipStats(state, ship.id).cargo - Items.CargoUsed(state, ship.id) < what.volume then
      return false, "no room in the hold"
    end
    return true
  end
  return false, `unknown command '{command.kind}'`
end

function Deploy.Apply(state: State.State, command: State.Command, events: { Event })
  local ship = state.ships[command.actor]
  local ball = state.balls[ship.id]
  if command.kind == "Deploy" then
    local item = state.items[command.item :: number]
    local what = Deployables.byId[item.type]
    Items.Take(state, item, 1)
    -- (a little way off the ship, as a container is)
    local made: State.Wreck = {
      id = State.NewId(state), kind = "wreck", name = what.name, system = ball.system, grid = ball.grid,
      x = ball.x + ball.radius + what.size + 80, y = ball.y, z = ball.z, radius = what.size, hull = "", expires = NEVER,
      salvaged = true, locked = false, lock = "", can = true, deploy = what.id,
      ends = if what.life then state.tick + math.ceil(what.life / Constants.TICK) else nil,
    }
    state.wrecks[made.id] = made
    table.insert(state.wreckIds, made.id)
    if what.kind == "bubble" then
      local bubbles = state.bubbles or {}
      state.bubbles = bubbles
      local field: State.Bubble = { id = State.NewId(state), system = made.system, grid = made.grid, x = made.x, y = made.y, z = made.z,
        radius = what.reach :: number, owner = ship.owner, expires = NEVER }
      table.insert(bubbles, field)
      made.field = field.id
    end
    table.insert(events, { kind = "WreckAdded", wreck = made.id })
    table.insert(events, { kind = "Deployed", ship = ship.id, wreck = made.id, type = what.id })
  elseif command.kind == "Scoop" then
    local wreck = state.wrecks[command.target :: number]
    local what = assert(Deploy.Of(wreck))
    Deploy.Remove(state, wreck)
    Items.Add(state, what.id, 1, ship.id, "cargo")
    table.insert(events, { kind = "Scooped", ship = ship.id, type = what.id })
  end
end

-- Take one out of space (picked up, or its life over: it is a plain
-- container then, Deploy.Step), and its field with it.
function Deploy.Remove(state: State.State, wreck: State.Wreck)
  if wreck.field and state.bubbles then
    for index = #state.bubbles, 1, -1 do
      if state.bubbles[index].id == wreck.field then
        table.remove(state.bubbles, index)
      end
    end
  end
  wreck.field = nil
  state.wrecks[wreck.id] = nil
  State.RemoveId(state.wreckIds, wreck.id)
end

-- A tractor's work this second: the wreck it is drawing in comes nearer,
-- and one that is there is emptied into it (as much as its hold takes);
-- then the next nearest in its reach. (Not a container: a wreck.)
local function tractor(state: State.State, post: State.Wreck, what: Deployables.Deployable, events: { Event })
  local target: State.Wreck? = state.wrecks[post.pulls or 0]
  if target == nil or target.can or target.hulk or target.system ~= post.system or #Items.In(state, target.id, nil) == 0 then
    target = nil
    local least = what.reach or 0
    for _, id in state.wreckIds do
      local wreck = state.wrecks[id]
      if not wreck.can and not wreck.hulk and not wreck.locked and wreck.system == post.system
        and #Items.In(state, wreck.id, nil) > 0 then
        local gap = Space.Gap(post :: any, wreck :: any)
        if gap <= least then
          target, least = wreck, gap
        end
      end
    end
    post.pulls = if target then target.id else nil
  end
  local wreck = target
  if wreck == nil then
    return
  end
  local dx, dy, dz = post.x - wreck.x, post.y - wreck.y, post.z - wreck.z
  local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
  local room = distance - post.radius - wreck.radius - Deployables.REACH * 0.5
  if room > 0 and distance > 0 then
    local step = math.min(room, Deploy.PULL * Constants.TICK)
    wreck.x += dx / distance * step
    wreck.y += dy / distance * step
    wreck.z += dz / distance * step
    wreck.grid = post.grid
    return
  end
  -- There: what is in it, as far as there is room.
  local free = what.hold - Deploy.Used(state, post)
  local taken = 0
  for _, item in Items.In(state, wreck.id, nil) do
    local volume = Types.Info(item.type).volume
    local quantity = if volume > 0 then math.min(item.quantity, math.floor((free + 1e-9) / volume)) else item.quantity
    if quantity > 0 then
      local type = item.type
      Items.Take(state, item, quantity)
      Items.Add(state, type, quantity, post.id, "cargo")
      free -= quantity * volume
      taken += quantity
    end
  end
  post.pulls = nil
  if taken > 0 then
    table.insert(events, { kind = "TractorLooted", wreck = wreck.id, post = post.id, quantity = taken })
  end
end

function Deploy.Step(state: State.State, events: { Event })
  for _, id in table.clone(state.wreckIds) do
    local wreck = state.wrecks[id]
    local what = Deploy.Of(wreck)
    if wreck and what then
      if wreck.ends and state.tick >= wreck.ends then
        -- (its life over: a plain container with what is in it, that goes as one does)
        Deploy.Remove(state, wreck)
        local left: State.Wreck = table.clone(wreck)
        left.deploy, left.ends, left.pulls, left.field = nil, nil, nil, nil
        left.name, left.expires = "Cargo Container", state.tick + LEFT
        if #Items.In(state, wreck.id, nil) > 0 then
          state.wrecks[left.id] = left
          table.insert(state.wreckIds, left.id)
        end
        table.insert(events, { kind = "DeployableSpent", wreck = wreck.id, type = what.id })
      elseif what.kind == "tractor" then
        tractor(state, wreck, what, events)
      end
    end
  end
end

return Deploy
