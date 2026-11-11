--!strict
-- The directional scanner: what ships and wrecks are about the pilot's
-- ship, on its grid or far off it, within a range and within a cone.
--
-- It says what is there and nothing of where: a name and a kind of
-- hull. The where is for the pilot to work out, by narrowing: a shorter
-- range, or a tighter cone pointed at a belt or a moon. It reaches
-- fourteen astronomical units at most, all round or in a cone of 90, 30
-- or 10 degrees pointed at something (a place on the overview, a ship,
-- a place the pilot has marked). A cloaked ship is not seen.
--
-- It changes nothing, so it is a question and not a command: asked
-- twice in a tick, it has the same answer.
--
-- (EVE's directional scanner, cut down. Not yet: places and structures
-- on it, a cone pointed where the camera looks.)

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

-- Something the scanner has picked up: a ship (a drone is one) or a
-- wreck, by its name and what it is; and whether it is on the pilot's
-- own grid, where the overview has it too.
export type Sighting = { id: number, kind: "ship" | "wreck", name: string, type: string, onGrid: boolean }

-- Whether a scan can be made: from a ship in space, with a cone of less
-- than all round pointed at something that is somewhere else.
function Dscan.Can(state: State.State, ship: number, toward: number?, angle: number): (boolean, string?)
  local me = state.balls[ship]
  if me == nil then
    return false, "docked"
  elseif angle < 360 then
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
-- a cone of 'angle' degrees, within half that of the line to 'toward'.
-- By name, then by id. Empty if the scan cannot be made.
function Dscan.Scan(state: State.State, ship: number, toward: number?, angle: number, range: number): { Sighting }
  local found: { Sighting } = {}
  if not Dscan.Can(state, ship, toward, angle) then
    return found
  end
  local me = state.balls[ship]
  range = math.min(range, Dscan.REACH)
  -- (the line the cone is about, and how near it a thing has to be)
  local ax, ay, az, least = 0, 0, 0, -1
  if angle < 360 then
    local at = (Space.Body(state, toward :: number) or Space.Marked(state, toward :: number)) :: Space.Body
    local far = Space.Distance(me :: any, at)
    ax, ay, az = (at.x - me.x) / far, (at.y - me.y) / far, (at.z - me.z) / far
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
      table.insert(found, { id = id, kind = "wreck", name = wreck.name, type = if wreck.locked then "sealed wreck" else "wreck",
        onGrid = me.grid ~= 0 and wreck.grid == me.grid })
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
