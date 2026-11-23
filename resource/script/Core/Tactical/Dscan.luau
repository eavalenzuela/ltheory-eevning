--!strict
-- The directional scanner: what ships, wrecks and structures are about
-- the pilot's ship, on its grid or far off it, within a range and
-- within a cone.
--
-- It says what is there and nothing of where: a name and a kind of
-- hull. The where is for the pilot to work out, by narrowing: a shorter
-- range, or a tighter cone. It reaches fourteen astronomical units at
-- most, all round or in a cone of 90, 30 or 10 degrees. The cone is
-- pointed at something (a place on the overview, a ship, a place the
-- pilot has marked), or along a line: the way the pilot is looking. A
-- cloaked ship is not seen.
--
-- The structures it picks up are stations (a pilot's starbase is one,
-- and a nomad's colony ship) and gates. A camp's gate is seen only once
-- its room is found: the scanner is not a way round finding things.
-- (Belts, moons and planets are not on it: they are where the charts
-- say, and the overview has every one.)
--
-- It changes nothing, so it is a question and not a command: asked
-- twice in a tick, it has the same answer.
--
-- (A directional scanner, cut down.)

local Combat = require("@lt/Core/Tactical/Combat")
local Constants = require("@lt/Core/Data/Constants")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")

local Dscan = {}

-- The ranges it can be set to, in astronomical units, and the cones, in
-- degrees from side to side (360: all round).
Dscan.RANGES = { 14, 5, 1, 0.1 }
Dscan.ANGLES = { 360, 90, 30, 10 }
Dscan.REACH = 14 * Constants.AU

-- Something the scanner has picked up: a ship (a drone is one), a wreck
-- or a structure, by its name and what it is; and whether it is on the
-- pilot's own grid, where the overview has it too.
export type Sighting = { id: number, kind: "ship" | "wreck" | "structure", name: string, type: string, onGrid: boolean }

-- The line a cone is about, given as a line and not a thing to point
-- at: of length 1, or nil if it is no line at all.
local function lineOf(along: { number }?): (number?, number?, number?)
  if along == nil then
    return nil
  end
  local long = math.sqrt(along[1] ^ 2 + along[2] ^ 2 + along[3] ^ 2)
  if long < 1e-9 then
    return nil
  end
  return along[1] / long, along[2] / long, along[3] / long
end

-- Whether a scan can be made: from a ship in space, with a cone of less
-- than all round pointed along a line ('along': x, y and z of it), or
-- at something that is somewhere else.
function Dscan.Can(state: State.State, ship: number, toward: number?, angle: number, along: { number }?): (boolean, string?)
  local me = state.balls[ship]
  if me == nil then
    return false, "docked"
  elseif angle < 360 and lineOf(along) == nil then
    local at = if toward then Space.Body(state, toward) or Space.Marked(state, toward) else nil
    if at == nil or toward == ship then
      return false, "a cone has to be pointed at something"
    elseif Space.Distance(me :: any, at) <= 0 then
      return false, "a cone has to be pointed at something"
    end
  end
  return true
end

-- What is within 'range' metres of a ship (centre to centre), and, with
-- a cone of 'angle' degrees, within half that of the line 'along', or
-- of the line to 'toward' where no line is given. By name, then by id.
-- Empty if the scan cannot be made.
function Dscan.Scan(state: State.State, ship: number, toward: number?, angle: number, range: number, along: { number }?): { Sighting }
  local found: { Sighting } = {}
  if not Dscan.Can(state, ship, toward, angle, along) then
    return found
  end
  local me = state.balls[ship]
  range = math.min(range, Dscan.REACH)
  -- (the line the cone is about, and how near it a thing has to be)
  local ax, ay, az, least = 0, 0, 0, -1
  if angle < 360 then
    local lx, ly, lz = lineOf(along)
    if lx and ly and lz then
      ax, ay, az = lx, ly, lz
    else
      local at = (Space.Body(state, toward :: number) or Space.Marked(state, toward :: number)) :: Space.Body
      local far = Space.Distance(me :: any, at)
      ax, ay, az = (at.x - me.x) / far, (at.y - me.y) / far, (at.z - me.z) / far
    end
    least = math.cos(math.rad(angle / 2))
  end
  local function within(x: number, y: number, z: number): boolean
    local dx, dy, dz = x - me.x, y - me.y, z - me.z
    local far = math.sqrt(dx * dx + dy * dy + dz * dz)
    if far > range then
      return false
    end
    -- (what is where the ship is, is in any cone)
    return far <= 0 or (dx * ax + dy * ay + dz * az) / far >= least
  end
  for _, id in state.ballIds do
    local ball = state.balls[id]
    if id ~= ship and ball.system == me.system and within(ball.x, ball.y, ball.z) and not Combat.Cloaked(state, id) then
      local hull = Ships.byId[state.ships[id].type]
      table.insert(found, { id = id, kind = "ship", name = ball.name, type = if hull then hull.name else "ship",
        onGrid = me.grid ~= 0 and ball.grid == me.grid })
    end
  end
  for _, id in state.wreckIds do
    local wreck = state.wrecks[id]
    if wreck.system == me.system and within(wreck.x, wreck.y, wreck.z) then
      table.insert(found, { id = id, kind = "wreck", name = wreck.name, type = if wreck.lock == "vault" or wreck.lock == "habitat" then (if wreck.locked then "locked vault" else "vault")
          elseif wreck.locked then "sealed wreck" else "wreck",
        onGrid = me.grid ~= 0 and wreck.grid == me.grid })
    end
  end
  -- Stations and gates. (What stands at a place nobody has found yet,
  -- or that is gone, is not seen: a camp's gate, until its room is.)
  for _, object in Space.Describe(state, me.system).objects do
    if (object.kind == "station" or object.kind == "gate") and within(object.x, object.y, object.z) then
      local site = state.sites[object.site]
      if site == nil or (site.strength >= 1 and not site.gone) then
        local type = if object.kind == "gate" then (if object.variety == "passage" then "camp gate" else "stargate")
          elseif object.variety ~= "" then object.variety else "station"
        table.insert(found, { id = object.id, kind = "structure", name = object.name, type = type,
          onGrid = me.grid ~= 0 and object.site == me.grid })
      end
    end
  end
  table.sort(found, function(a: Sighting, b: Sighting): boolean
    if a.name ~= b.name then
      return a.name < b.name
    end
    return a.id < b.id
  end)
  return found
end

return Dscan
