--!strict
-- Fields: the field round a station.
--
-- A station is a tower with a field round it (its radius is the field's:
-- Describe/System, Data/Structures), and the field is a wall to whatever
-- is shot (the owner's ruling, 2026-11-14):
--
--   Nothing is locked across it, in or out, so nothing fires across it
--   and nothing is held, mended or drained across it either. A missile
--   on its way when its target goes in comes to nothing against it.
--
--   Whoever the station's guns would fire on is kept out: a pirate, and
--   a pilot the patrols have marked (with their drones and their hired
--   pilots), at a station that is not their own. They come to the
--   field's edge and no farther, and one that is inside when that
--   becomes true of it is put out.
--
--   The tower itself can be shot at from outside, as it always could:
--   it is what the field is hung on. (A pilot's own tower is a thing
--   with a shield and armour of its own, Tactical/Raids. Anybody else's
--   takes no harm.)
--
--   A station's batteries stand outside the field (Tactical/Batteries),
--   so they shoot and are shot at as anything else outside is.
--
-- The field is up at every station but two: a pilot's tower that is not
-- anchored yet or has no fuel (it is dark), and a colony ship of the
-- nomads, which is a ship and has none. A tower that has sealed itself
-- keeps its field.
--
-- It is all worked out from where things are: nothing is kept but the
-- station the pilot was last inside the field of, to say so once when
-- they go in and once when they come out.

local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")

local Fields = {}

export type Event = { [string]: any }

-- What nobody may do across a field, as whoever tries is told.
Fields.REFUSED = "the station's field is between you"
-- How far a ship that may not be inside is put out in a second, m, when
-- it is deep inside (one that has only just crossed is put back at the
-- edge whatever its speed).
Fields.THROW = 1500

-- Whether a station's field is up.
local function up(state: State.State, object: System.Object): boolean
  if object.kind ~= "station" or object.radius <= 0 or Space.Colony(state, object.id) then
    return false
  end
  local starbase = state.starbases[object.id]
  return starbase == nil or (state.tick >= starbase.ready and starbase.fuel > 0)
end

-- The station whose field is up on a grid (a station's grid is the
-- station), if there is one.
function Fields.Of(state: State.State, grid: number): System.Object?
  if grid == 0 then
    return nil
  end
  local object = Space.Object(state, grid)
  return if object and up(state, object) then object else nil
end

-- Whether something is inside a field: its middle is.
function Fields.Within(field: System.Object, body: Space.Body): boolean
  return Space.Distance(field :: any, body) < field.radius
end

-- The station whose field a ship is inside, if it is inside one.
function Fields.Around(state: State.State, ball: State.Ball): System.Object?
  local field = Fields.Of(state, ball.grid)
  return if field and Fields.Within(field, ball :: any) then field else nil
end

-- Whether a ship is one a station keeps out of its field: whoever its
-- batteries would fire on (Tactical/Batteries).
function Fields.Barred(state: State.State, field: System.Object, id: number): boolean
  local ship = state.ships[id]
  if ship == nil then
    return false
  elseif ship.owner == "pirates" then
    return true
  end
  -- (a pilot's own tower takes its owner in whatever the patrols think of them)
  return ship.owner == "player" and state.tick < state.player.marked and state.starbases[field.id] == nil
end

-- Whether a field stands between a ship and something it would lock:
-- one of them is inside the field of the station they are at and the
-- other is not. Never for the tower itself (the station, or what stands
-- for a pilot's own where it is shot at).
function Fields.Between(state: State.State, ball: State.Ball, target: Space.Body): boolean
  local field = Fields.Of(state, ball.grid)
  if field == nil or target.id == field.id then
    return false
  end
  local starbase = state.starbases[field.id]
  if starbase and starbase.core == target.id then
    return false
  end
  -- (what is on another grid is nothing to this one's field)
  local other = state.balls[target.id]
  if other and other.grid ~= ball.grid then
    return false
  end
  return Fields.Within(field, ball :: any) ~= Fields.Within(field, target)
end

-- How far a ship is from something it would shoot at, surface to
-- surface. A pilot's tower stands in the middle of its field, and is
-- shot at from outside it (it is what the field is hung on): to
-- whoever is outside, the field is the tower's surface.
function Fields.Gap(state: State.State, ball: State.Ball, target: Space.Body): number
  local field = Fields.Of(state, ball.grid)
  local starbase = if field then state.starbases[field.id] else nil
  if field and starbase and starbase.core == target.id and not Fields.Within(field, ball :: any) then
    return Space.Gap(ball :: any, field :: any)
  end
  return Space.Gap(ball :: any, target)
end

-- Each tick, after the ships have flown: whoever may not be inside a
-- field is put out of it, and the pilot is told when they go into one
-- and when they come out.
function Fields.Step(state: State.State, events: { Event })
  -- (a grid's field is looked up once a tick, however many ships are on it)
  local known: { [number]: System.Object } = {}
  local none: { [number]: boolean } = {}
  for _, id in state.ballIds do
    local ball = state.balls[id]
    if ball.grid == 0 or (ball.warp and ball.warp.stage == "warp") then
      continue
    end
    local field: System.Object? = known[ball.grid]
    if field == nil and not none[ball.grid] then
      field = Fields.Of(state, ball.grid)
      if field then
        known[ball.grid] = field
      else
        none[ball.grid] = true
      end
    end
    if field == nil or not Fields.Barred(state, field, id) then
      continue
    end
    local edge = field.radius + ball.radius
    local dx, dy, dz = ball.x - field.x, ball.y - field.y, ball.z - field.z
    local far = math.sqrt(dx * dx + dy * dy + dz * dz)
    if far >= edge then
      continue
    end
    local ux, uy, uz = 1, 0, 0
    if far > 0 then
      ux, uy, uz = dx / far, dy / far, dz / far
    end
    -- (as far as it can have come in a second it is put straight back.
    -- From deeper in, which is a ship the field has only now turned
    -- against, it is carried out at a pace that can be watched.)
    local speed = math.sqrt(ball.vx * ball.vx + ball.vy * ball.vy + ball.vz * ball.vz)
    local step = math.min(edge - far, math.max(Fields.THROW, speed * 2))
    ball.x, ball.y, ball.z = ball.x + ux * step, ball.y + uy * step, ball.z + uz * step
    -- (and it is not going inward any more)
    local inward = ball.vx * ux + ball.vy * uy + ball.vz * uz
    if inward < 0 then
      ball.vx, ball.vy, ball.vz = ball.vx - inward * ux, ball.vy - inward * uy, ball.vz - inward * uz
    end
  end

  local me = state.balls[state.player.ship]
  local around = if me then Fields.Around(state, me) else nil
  local now = if around then around.id else 0
  local was = state.player.field or 0
  if now ~= was then
    state.player.field = if now ~= 0 then now else nil
    -- (docking and undocking say what they are themselves: only a ship
    -- that flew across is told)
    if me and now ~= 0 then
      table.insert(events, { kind = "FieldEntered", station = now })
    elseif me and was ~= 0 then
      table.insert(events, { kind = "FieldLeft", station = was })
    end
  end
end

return Fields
