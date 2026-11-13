--!strict
-- The star map: every system of the galaxy and the gates between them,
-- whose each is or how safe, where the pilot is, where they mean to go,
-- and the way there.
--
-- Open in space or docked, from the Map button. Click a system to pick
-- it; the panel at the side says what it is and sets it as the
-- destination, which the autopilot flies to. Drawn every frame with
-- Game/UI/Im; the systems and gates are drawn from icons made once for
-- a galaxy and a window size. Its buttons' names, for a script
-- (Im.Press): "Map:close", "Map:factions", "Map:security",
-- "Map:destination", "Map:clear", "Map:safest", "Map:autopilot", and
-- "Map:jump" for a hull with a jump drive.
--
-- The galaxy has a height as well as the two ways it lies (every system
-- is a little above or below the plane of the map: Describe/Galaxy), so
-- the map is seen from a slant: each system stands on a stalk over the
-- place on the plane it is above (or hangs under it), and the plane's
-- edge is drawn. Dragging with the right button turns it and tilts it;
-- "Map:flat" lays it flat (seen from straight over, as a chart), and
-- "Map:left" and "Map:right" turn it a step. For a hull with a jump
-- drive the sphere its drive reaches is drawn round where the pilot is
-- (it grows with the skill), and the systems inside it are picked out.
--
-- And it is looked at as near as is wanted: the wheel over the map nears
-- it and draws back, about what the cursor is on; the left button held
-- drags it about; "Map:in" and "Map:out" are a notch of the wheel,
-- "Map:fit" is all of it again, and "Map:here" (or a double click on a
-- system) puts the pilot's system (or that one) in the middle, near
-- enough to read. As fewer systems are in sight the map says more: the
-- constellations' names, then every system's. A measure in the corner
-- says how long so many light years are.

local Colors = require("@lt/Colors")
local Core = require("@lt/Core/Api")
local Factions = require("@lt/Core/Data/Factions")
local Format = require("@lt/Game/Format")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Im = require("@lt/Game/UI/Im")
local Session = require("@lt/Game/Session")
local Waypoints = require("@lt/Game/Waypoints")

local Map = {}

local SIDE = 300          -- the panel beside the map
local MARGIN = 28

local UNCLAIMED = vector.create(0.34, 0.35, 0.38)
-- (where the pilot is next to go: the gold the overview uses for it)
local NEXT = vector.create(1.0, 0.80, 0.28)
-- A faction's colour on the map. (Not its hull paint, which is chosen
-- to look right on a hull: several of them are greys and browns.)
local WHOSE: { [string]: vector } = {
  vessari = vector.create(1.0, 0.72, 0.28), talmar = vector.create(0.45, 0.78, 1.0),
  orun = vector.create(0.55, 0.9, 0.5), kethri = vector.create(0.82, 0.55, 1.0),
  unbound = vector.create(0.95, 0.38, 0.32), vail = vector.create(0.25, 0.85, 0.80),
  skarn = vector.create(1.0, 0.45, 0.78), tessellate = vector.create(0.93, 0.93, 0.96),
}
local BAND: { [string]: vector } = {
  secure = vector.create(0.45, 0.85, 0.55), low = vector.create(0.95, 0.75, 0.3), lawless = vector.create(0.85, 0.35, 0.3),
}
local BAND_NAME: { [string]: string } = { secure = "Secure space", low = "Low security", lawless = "Lawless space" }

local open = false
local picked = 0          -- the system picked on the map, or 0
local bySecurity = false  -- colour by security, not by whose
-- How the map is looked at: how far it is turned about the upright
-- (radians), and how steeply it is looked down on (a quarter turn is
-- from straight over it). And where the cursor was a frame ago, while
-- the right button is held: the map turns by how far it has moved.
local TURNED, TILTED = 0.5, 0.75
local yaw, pitch = TURNED, TILTED
local dragged: vector? = nil
-- How near it is looked at: 1 is the whole galaxy, and so many times
-- nearer than that. 'zoom' is what it is now and 'zoomTo' what it is
-- easing to. (The nearest it goes is by how many systems there are:
-- Map.Nearest.)
local NEARER = 1.25       -- a notch of the wheel, or a press of + or -
local zoom, zoomTo = 1, 1
-- What the middle of the map is on, when it is looked at nearer than the
-- whole: a place in the galaxy (light years, with its height), or nil
-- for the middle of all of it. And where the middle is on its way there
-- ('look' eases to 'focus').
local focus: vector? = nil
local look: vector? = nil
-- While it nears or draws back: the place in the galaxy that stays where
-- it is in the window (what the cursor is on, for the wheel), and where
-- in the window that is, in pixels from the middle of the map.
local hold: { place: vector, at: vector }? = nil
-- The left button, held from a press on the map: where it went down,
-- where the cursor was a frame ago, the system it went down on, and
-- whether it has gone far enough to be a drag (which moves the map) and
-- not a click (which picks the system).
local grab: { from: vector, last: vector, on: number, moved: boolean }? = nil
-- What a script has asked for (Map.Zoom), until the map is next drawn.
local asked: { zoom: number?, on: number? }? = nil
-- How many systems were in sight on the map as it was last drawn, and
-- whether each had its name by it.
local inView, allNamed = 0, false
-- Where the map's own middle was in the window as it was last drawn, and
-- how near it was looked at: where a system is in the window follows.
local shownFrom, shownNear = vector.zero, 1
-- With so many regions in sight or fewer, they are named; with so many
-- systems in sight or fewer, the constellations are; and with so many
-- or fewer, every system is.
local REGIONS, CONSTELLATIONS, NAMES = 48, 160, 60
-- And with more systems in sight than this, the chart is drawn fainter.
local CROWD = 2500

-- What is made once for a galaxy: its gates as an icon, and its systems
-- as an icon for every colour they are drawn in. Their glyphs stand at
-- places in space (Icon_AddLine3, Icon_AddBox3: light years from the
-- galaxy's middle), so however the map is turned, moved or neared, the
-- engine is told how it is looked at (Icon_View) and nothing is made
-- again: a galaxy of thousands is turned as lightly as one of forty.
type Chart = {
  epoch: number, count: number,
  -- (the middle of the galaxy, light years, and the corners of its plane)
  middle: vector,
  corners: { vector },
  gates: Icon,
  -- (each system's stalk to the plane; and the plane's edge)
  stalks: Icon,
  edge: Icon,
  -- (how big a system's dot is, in pixels, however near the map is
  -- looked at: before it swells a little with nearness)
  dot: number,
  -- (the dots are an icon for every colour, by whose the systems are or
  -- by how safe: whichever is shown, and made again for the other)
  bySecurity: boolean,
  dots: { { icon: Icon, color: vector } },
}
local chart: Chart? = nil

-- What follows from how the map is looked at: where each system is on
-- it (in pixels from the map's middle, with all the galaxy shown).
type Drawn = {
  epoch: number, width: number, height: number,
  -- (how it was looked at when it was made, how many pixels a light
  -- year is, the middle of the galaxy in light years, and where the
  -- middle of what is drawn is, in pixels, from that)
  yaw: number, pitch: number, scale: number, middle: vector, shift: vector,
  -- (and the sphere that was given room on it: round which system, and
  -- how far it reaches; 0 and 0 for none)
  round: number, reach: number,
  at: { vector },
  -- (how near the map was looked at when the dots were last given
  -- their size: an icon is drawn as many times bigger as the map is
  -- nearer, dots and all, so they are that many times smaller on it)
  near: number,
  -- (the middle of each region's systems and of each constellation's,
  -- where its name goes)
  regionsAt: { [number]: vector },
  constellationsAt: { [number]: vector },
}
local drawn: Drawn? = nil

function Map.Open(system: number?)
  open = true
  picked = system or picked
end

function Map.Close()
  open = false
end

function Map.IsOpen(): boolean
  return open
end

-- The system picked on the map, or 0.
function Map.Picked(): number
  return picked
end

-- How the map is looked at: turned so far, tilted so far (radians).
-- Given either, it is looked at so from now on.
function Map.View(turn: number?, tilt: number?): (number, number)
  yaw = turn or yaw
  pitch = math.clamp(tilt or pitch, 0.3, math.pi / 2)
  return yaw, pitch
end

-- The nearest a map of so many systems is looked at: near enough that
-- neighbours stand a few hundred pixels apart.
function Map.Nearest(count: number): number
  return math.max(4, 0.4 * math.sqrt(count))
end

-- How near the map is looked at, how many systems are in sight on it,
-- and whether each has its name by it. Given how near, it is looked at
-- so (at once, not eased) from the next frame it is drawn; given a
-- system, with that system in the middle. For scripts.
function Map.Zoom(to: number?, on: number?): (number, number, boolean)
  if to or on then
    asked = { zoom = to, on = on }
  end
  return zoom, inView, allNamed
end

-- Where a system was in the window when the map was last drawn (it may
-- be off the map's edge), or nil if the map has not been drawn. For
-- scripts, which click on one.
function Map.Where(system: number): vector?
  local made = drawn
  local at = if made then made.at[system] else nil
  return if at then shownFrom + at * shownNear else nil
end

-- Where a place in the galaxy (light years, 'z' its height) is on a map
-- looked at so, in light years across and down the screen from the
-- place 'middle'.
local function seen(x: number, y: number, z: number, middle: vector, turn: number, tilt: number): vector
  local dx, dy = x - middle.x, y - middle.y
  local c, sn = math.cos(turn), math.sin(turn)
  local rx, ry = dx * c - dy * sn, dx * sn + dy * c
  return vector.create(rx, ry * math.sin(tilt) - z * math.cos(tilt))
end

-- Where a place in the galaxy is on the map as it was made (pixels from
-- its middle, with all the galaxy shown); and the other way about: the
-- place in the galaxy, at a height, that is at a point of it.
local function fitted(made: Drawn, place: vector): vector
  return seen(place.x, place.y, place.z, made.middle, made.yaw, made.pitch) * made.scale - made.shift
end

local function placed(made: Drawn, point: vector, z: number): vector
  local across = (point.x + made.shift.x) / made.scale
  local down = (point.y + made.shift.y) / made.scale
  local ry = (down + z * math.cos(made.pitch)) / math.sin(made.pitch)
  local c, sn = math.cos(made.yaw), math.sin(made.yaw)
  return vector.create(made.middle.x + across * c + ry * sn, made.middle.y - across * sn + ry * c, z)
end

local function colorOf(faction: string): vector
  return WHOSE[faction] or UNCLAIMED
end

-- How many times bigger a system's dot is with the map looked at so
-- near: a little, so that it is still a dot.
local function swollen(near: number): number
  return math.min(2.2, near ^ 0.45)
end

-- The systems as icons, one for every colour they are drawn in (by how
-- safe they are, or by whose): a dot each at its place in space, bigger
-- for a homeworld. (A box glyph: a circle glyph is a point of light
-- with a halo, not a disc.)
local function dotted(systems: { Galaxy.SystemNode }, middle: vector, safety: boolean): { { icon: Icon, color: vector } }
  local icons: { [string]: Icon? } = {}
  local list: { { icon: Icon, color: vector } } = {}
  for _, system in systems do
    local size = if system.home then 1.7 else 1
    local key = if safety then Galaxy.Band(system.security) else system.owner
    local its: Icon? = icons[key]
    if not its then
      local fresh = Icon_Create()
      icons[key] = fresh
      table.insert(list, { icon = fresh, color = if safety then BAND[key] else colorOf(key) })
      its = fresh
    end
    Icon_AddBox3(its, vector.create(system.x - middle.x, system.y - middle.y, system.z), vector.create(size, size))
  end
  return list
end

-- A galaxy's chart: made once, whatever is done with the map after.
local function charted(galaxy: Galaxy.Galaxy, epoch: number, safety: boolean): Chart
  local systems = galaxy.systems
  local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
  for _, system in systems do
    minX, maxX = math.min(minX, system.x), math.max(maxX, system.x)
    minY, maxY = math.min(minY, system.y), math.max(maxY, system.y)
  end
  local middle = vector.create((minX + maxX) / 2, (minY + maxY) / 2)
  local function place(system: Galaxy.SystemNode, z: number): vector
    return vector.create(system.x - middle.x, system.y - middle.y, z)
  end
  local stalks = Icon_Create()
  for _, system in systems do
    if math.abs(system.z) > 0.05 then
      Icon_AddLine3(stalks, place(system, system.z), place(system, 0))
    end
  end
  -- (the edge of the plane, a little outside the outermost systems)
  local edge = 0.04 * math.max(maxX - minX, maxY - minY)
  local corners = { vector.create(minX - edge, minY - edge), vector.create(maxX + edge, minY - edge),
    vector.create(maxX + edge, maxY + edge), vector.create(minX - edge, maxY + edge) }
  local rim = Icon_Create()
  for index, corner in corners do
    local following = corners[index % 4 + 1]
    Icon_AddLine3(rim, vector.create(corner.x - middle.x, corner.y - middle.y, 0),
      vector.create(following.x - middle.x, following.y - middle.y, 0))
  end
  local gates = Icon_Create()
  for id, system in systems do
    for _, neighbor in system.neighbors do
      if neighbor > id then
        Icon_AddLine3(gates, place(system, system.z), place(systems[neighbor], systems[neighbor].z))
      end
    end
  end
  return { epoch = epoch, count = #systems, middle = middle, corners = corners, gates = gates, stalks = stalks, edge = rim,
    -- A dot a system, smaller as there are more.
    dot = if #systems > 1200 then 1.4 elseif #systems > 150 then 2 elseif #systems > 40 then 2.6 else 3.4,
    bySecurity = safety, dots = dotted(systems, middle, safety) }
end

-- Have the chart's icons looked at as the map is: all of them, or with
-- 'dotsOnly' the dots alone, which are a size for how near it is.
local function view(its: Chart, made: Drawn, near: number, dotsOnly: boolean?)
  local c, sn = math.cos(made.yaw), math.sin(made.yaw)
  local right = vector.create(c, -sn, 0)
  local down = vector.create(sn * math.sin(made.pitch), c * math.sin(made.pitch), -math.cos(made.pitch))
  local offset = -made.shift
  if not dotsOnly then
    Icon_View(its.gates, right, down, offset, made.scale, 1)
    Icon_View(its.stalks, right, down, offset, made.scale, 1)
    Icon_View(its.edge, right, down, offset, made.scale, 1)
  end
  for _, group in its.dots do
    Icon_View(group.icon, right, down, offset, made.scale, its.dot * swollen(near) / near)
  end
  made.near = near
end

-- ('round' and 'reach': a sphere to leave room for, round a system and
-- so many light years out from it, for a hull with a jump drive; 0 and
-- 0 for none.)
-- ('near': how near the map is looked at, for the size of the dots.)
local function make(galaxy: Galaxy.Galaxy, its: Chart, width: number, height: number, round: number, reach: number, near: number): Drawn
  local systems = galaxy.systems
  local middle = its.middle
  -- (as it is looked at: every system, and the place on the plane under
  -- it, and the room all of that takes. This is done again for every
  -- frame the map is turned in, so it is done plainly: what 'seen' does,
  -- with the turn and the tilt worked out once.)
  local c, sn = math.cos(yaw), math.sin(yaw)
  local slant, rise = math.sin(pitch), math.cos(pitch)
  local low, high = vector.create(math.huge, math.huge), vector.create(-math.huge, -math.huge)
  local over: { vector } = table.create(#systems)
  for id, system in systems do
    local dx, dy = system.x - middle.x, system.y - middle.y
    local across, down = dx * c - dy * sn, (dx * sn + dy * c) * slant
    local above = vector.create(across, down - system.z * rise)
    over[id] = above
    low, high = vector.min(low, above), vector.max(high, above)
    if down < low.y or down > high.y then
      local below = vector.create(across, down)
      low, high = vector.min(low, below), vector.max(high, below)
    end
  end
  -- (and the edge of the plane; and the sphere, which is a circle
  -- however it is looked at)
  for _, corner in its.corners do
    local p = seen(corner.x, corner.y, 0, middle, yaw, pitch)
    low, high = vector.min(low, p), vector.max(high, p)
  end
  if over[round] and reach > 0 then
    low, high = vector.min(low, over[round] - vector.create(reach, reach)), vector.max(high, over[round] + vector.create(reach, reach))
  end
  local scale = math.min((width - 2 * MARGIN) / math.max(1e-3, high.x - low.x), (height - 2 * MARGIN) / math.max(1e-3, high.y - low.y))
  local shift = (low + high) / 2 * scale
  local at: { vector } = table.create(#systems)
  -- Where the regions' names go, and the constellations'.
  local regions, constellations = #galaxy.regions, #galaxy.constellations
  local regionsAt: { [number]: vector } = table.create(regions, vector.zero)
  local constellationsAt: { [number]: vector } = table.create(constellations, vector.zero)
  local regionCount: { number } = table.create(regions, 0)
  local constellationCount: { number } = table.create(constellations, 0)
  for id, system in systems do
    local p = over[id] * scale - shift
    at[id] = p
    local region, constellation = system.region, system.constellation
    regionsAt[region] += p
    regionCount[region] += 1
    constellationsAt[constellation] += p
    constellationCount[constellation] += 1
  end
  for id = 1, regions do
    regionsAt[id] = if regionCount[id] > 0 then regionsAt[id] / regionCount[id] else nil :: any
  end
  for id = 1, constellations do
    constellationsAt[id] = if constellationCount[id] > 0 then constellationsAt[id] / constellationCount[id] else nil :: any
  end
  local made: Drawn = { epoch = its.epoch, width = width, height = height, yaw = yaw, pitch = pitch, scale = scale, middle = middle,
    shift = shift, round = round, reach = reach, at = at, near = near, regionsAt = regionsAt, constellationsAt = constellationsAt }
  view(its, made, near)
  return made
end

-- The part of a window the map takes up when it is open: where it is,
-- and how wide and how high. (It goes over everything, so what is drawn
-- before it leaves the mouse alone there: Im.Cover.)
function Map.Covers(left: number, top: number, width: number, height: number): (number, number, number, number)
  local w, h = math.min(width - 80, 1400), math.min(height - 150, 820)
  return left + (width - w) / 2, top + (height - h) / 2 - 10, w, h
end

function Map.Draw(session: Session.Session, left: number, top: number, width: number, height: number)
  if not open then
    return
  end
  Im.Uncover()
  local game = session.game
  local galaxy = game.state.galaxy
  local systems = galaxy.systems
  local x, y, w, h = Map.Covers(left, top, width, height)
  Im.Panel(x, y, w, h)
  -- (a panel lets what is behind it show; a map is read, so it does not)
  Im.Fill(x, y, w, h, vector.create(0.02, 0.03, 0.045), 0.97)
  Im.Heading(`GALAXY  {#systems} SYSTEMS`, x + 16, y + 12, 16, Im.DIM)
  if Im.Button("x", x + w - 38, y + 10, 24, 24, true, "Map:close") then
    open = false
    return
  end
  if Im.Toggle("Factions", x + 260, y + 8, 100, 26, not bySecurity, "Map:factions") then
    bySecurity = false
  end
  if Im.Toggle("Security", x + 364, y + 8, 100, 26, bySecurity, "Map:security") then
    bySecurity = true
  end
  -- How it is looked at: flat (from straight over) or from a slant, and
  -- turned a step either way. (The right button, held, turns and tilts
  -- it by hand: below.)
  local flat = pitch >= math.pi / 2 - 1e-3
  if Im.Toggle("Flat", x + 500, y + 8, 60, 26, flat, "Map:flat") then
    -- (flat, it is a chart: square to the window, the way it was drawn
    -- before it had a height)
    yaw, pitch = if flat then TURNED else 0, if flat then TILTED else math.pi / 2
  end
  if Im.Button("<", x + 566, y + 8, 28, 26, true, "Map:left") then
    yaw -= math.pi / 12
  end
  if Im.Button(">", x + 598, y + 8, 28, 26, true, "Map:right") then
    yaw += math.pi / 12
  end
  -- How near it is looked at: a notch nearer or further, all of it
  -- again, and the pilot's system in the middle. (The wheel over the map
  -- nears it by hand, and the left button drags it: below.)
  local limit = Map.Nearest(#systems)
  local step, fit, toHere = 0, false, false
  if Im.Button("-", x + 644, y + 8, 28, 26, zoomTo > 1, "Map:out") then
    step = -1
  end
  if Im.Button("+", x + 676, y + 8, 28, 26, zoomTo < limit, "Map:in") then
    step = 1
  end
  if Im.Button("Fit", x + 708, y + 8, 44, 26, zoomTo > 1, "Map:fit") then
    fit = true
  end
  if Im.Button("Here", x + 756, y + 8, 54, 26, true, "Map:here") then
    toHere = true
  end
  if zoom > 1 then
    Im.Text(string.format("x%.1f", zoom), x + 820, y + 14, 12, Im.DIM)
  end

  -- The map.
  local mapW, mapH = w - SIDE - 16, h - 56
  local mapX, mapY = x + 8, y + 48
  local kept = drawn
  local made: Drawn
  -- (the right button held over the map turns it and tilts it)
  local pointer = Im.Cursor()
  local onMap = Im.Inside(mapX, mapY, mapW, mapH)
  if Mouse_RightDown() and (dragged ~= nil or onMap) then
    local was = dragged or pointer
    yaw += (pointer.x - was.x) * 0.008
    pitch = math.clamp(pitch + (pointer.y - was.y) * 0.006, 0.3, math.pi / 2)
    dragged = pointer
  else
    dragged = nil
  end
  -- (a hull with a jump drive has the sphere it reaches drawn round where
  -- the pilot is, and the map leaves room for it)
  local player = Core.Query.Player(game)
  local here = player.system
  local reaching = Core.Query.JumpDrive(game)
  local round = if reaching then here else 0
  local reach = if reaching then reaching.range else 0
  local had = chart
  local its: Chart
  if had == nil or had.epoch ~= session.epoch or had.count ~= #systems then
    its = charted(galaxy, session.epoch, bySecurity)
    chart = its
    kept = nil
  else
    its = had
  end
  if kept == nil then
    -- (another galaxy: all of it, to begin with)
    zoom, zoomTo, focus, look, hold, grab = 1, 1, nil, nil, nil, nil
  end
  if kept == nil or kept.width ~= mapW or kept.height ~= mapH
    or kept.yaw ~= yaw or kept.pitch ~= pitch or kept.round ~= round or kept.reach ~= reach then
    made = make(galaxy, its, mapW, mapH, round, reach, zoom)
    drawn = made
    if systems[picked] == nil then
      picked = 0
    end
  else
    made = kept
  end
  local centre = vector.create(mapX + mapW / 2, mapY + mapH / 2)

  -- How near it is looked at, and what its middle is on. 'pan' is where
  -- the middle of the window is on the map as it was made (pixels of it
  -- with all the galaxy shown): with all of it shown that is its own
  -- middle and nowhere else, and from twice as near it is anywhere on it.
  local function bounded(p: vector): vector
    local slack = math.clamp(zoom - 1, 0, 1)
    return vector.create(math.clamp(p.x, -mapW / 2 * slack, mapW / 2 * slack), math.clamp(p.y, -mapH / 2 * slack, mapH / 2 * slack))
  end
  local function whereIs(id: number): vector
    local system = systems[id]
    return vector.create(system.x, system.y, system.z)
  end
  local function level(): number
    local on = focus
    return if on then on.z else 0
  end
  -- (a system in the middle, and near enough that every system in sight
  -- round it has its name by it: twice as near as all the galaxy at the
  -- least, which is how near anywhere on the map can be the middle)
  local function centred(id: number)
    focus, hold = whereIs(id), nil
    local middle = made.at[id]
    local to = math.clamp(zoomTo, math.min(2, limit), limit)
    while to < limit do
      local about = 0
      for _, at in made.at do
        if math.abs(at.x - middle.x) * to <= mapW / 2 and math.abs(at.y - middle.y) * to <= mapH / 2 then
          about += 1
        end
      end
      if about <= NAMES then
        break
      end
      to = math.min(limit, to * NEARER)
    end
    zoomTo = to
  end
  -- (where it was as it was last drawn)
  local resting = look or focus
  local pan = if resting then bounded(fitted(made, resting)) else vector.zero
  local want = asked
  if want then
    asked = nil
    zoom = math.clamp(want.zoom or zoom, 1, limit)
    zoomTo, hold = zoom, nil
    local on = want.on
    if on and systems[on] then
      focus = whereIs(on)
      look = focus
    end
  end
  if fit then
    zoomTo, hold = 1, nil
  end
  if toHere then
    centred(here)
  end
  -- (a notch: of the wheel, about what the cursor is on; or of the
  -- buttons, about the middle of what is shown, and from all of the
  -- galaxy about the system picked, or the one the pilot is in)
  local notches = step + (if onMap then Mouse_GetScrollDelta() else 0)
  if notches ~= 0 then
    local to = math.clamp(zoomTo * NEARER ^ notches, 1, limit)
    if to ~= zoomTo then
      zoomTo = to
      if step == 0 then
        local at = pointer - centre
        hold = { place = placed(made, pan + at / zoom, level()), at = at }
      elseif zoom <= 1.001 then
        local place = whereIs(if picked ~= 0 then picked else here)
        hold = { place = place, at = (fitted(made, place) - pan) * zoom }
      else
        hold = nil
      end
    end
  end
  local share = 1 - math.exp(-18 * math.clamp(FrameTimer_Get(), 1 / 240, 0.1))
  if zoom ~= zoomTo then
    zoom *= (zoomTo / zoom) ^ share
    if math.abs(zoomTo / zoom - 1) < 0.004 then
      zoom = zoomTo
    end
  end
  local holding, aim = hold, focus
  if holding then
    pan = bounded(fitted(made, holding.place) - holding.at / zoom)
    focus = placed(made, pan, level())
    look = focus
    if zoom == zoomTo then
      hold = nil
    end
  elseif aim then
    local from = look or placed(made, vector.zero, aim.z)
    local now = from + (aim - from) * share
    if vector.magnitude(aim - now) * made.scale * zoom < 0.5 then
      now = aim
    end
    look = now
    pan = bounded(fitted(made, now))
  else
    pan = vector.zero
  end
  -- (the left button held and moved drags the map about)
  local grabbed = grab
  if grabbed and Mouse_LeftDown() then
    grabbed.moved = grabbed.moved or vector.magnitude(pointer - grabbed.from) > 5
    if grabbed.moved and zoom > 1 then
      pan = bounded(pan - (pointer - grabbed.last) / zoom)
      focus = placed(made, pan, level())
      look, hold = focus, nil
    end
    grabbed.last = pointer
  end
  if zoom == 1 and zoomTo == 1 then
    focus, look, hold = nil, nil, nil
    pan = vector.zero
  end
  if its.bySecurity ~= bySecurity then
    its.dots, its.bySecurity = dotted(systems, its.middle, bySecurity), bySecurity
    view(its, made, zoom, true)
  elseif made.near ~= zoom then
    view(its, made, zoom, true)
  end
  -- Where things are in the window: the map's own middle, and a system.
  local origin = centre - pan * zoom
  shownFrom, shownNear = origin, zoom
  local function spot(id: number): vector
    return origin + made.at[id] * zoom
  end
  local function sighted(p: vector, by: number): boolean
    return p.x >= mapX - by and p.x <= mapX + mapW + by and p.y >= mapY - by and p.y <= mapY + mapH + by
  end

  -- Which systems are in sight, and which of them the cursor is on.
  local hot, nearest = 0, 14 ^ 2
  local count = 0
  local few: { number } = {}
  for id, at in made.at do
    local sx, sy = origin.x + at.x * zoom, origin.y + at.y * zoom
    if sx >= mapX and sx <= mapX + mapW and sy >= mapY and sy <= mapY + mapH then
      count += 1
      if count <= NAMES then
        few[count] = id
      end
      if onMap then
        local d2 = (sx - pointer.x) ^ 2 + (sy - pointer.y) ^ 2
        if d2 < nearest then
          hot, nearest = id, d2
        end
      end
    end
  end
  inView, allNamed = count, zoom > 1 and count <= NAMES
  -- A click on a system picks it (a click: the button let go where it
  -- went down, not a drag of the map), and a double click puts it in the
  -- middle.
  if Im.Pressed() and onMap then
    grab = { from = pointer, last = pointer, on = hot, moved = false }
    if Im.DoublePressed() and hot ~= 0 then
      centred(hot)
    end
  end
  local down = grab
  if down and not Mouse_LeftDown() then
    if not down.moved and hot ~= 0 and hot == down.on then
      picked = hot
    end
    grab = nil
  end

  Im.Fill(mapX, mapY, mapW, mapH, vector.create(0.015, 0.02, 0.03), 0.85)
  ClipRegion_Push(vector.create(mapX, mapY), vector.create(mapW, mapH))
  -- The regions' names, each over the middle of its systems, under
  -- everything else; and, with few enough systems in sight, the
  -- constellations'.
  -- (a region's name is drawn while few enough of them are in sight to
  -- be read: a galaxy of thousands, all of it shown, would be under them)
  local regional: { number } = {}
  for _, region in galaxy.regions do
    local at = made.regionsAt[region.id]
    if at and sighted(origin + at * zoom, 160) then
      table.insert(regional, region.id)
    end
  end
  if #regional <= REGIONS then
    for _, id in regional do
      local label = string.upper(galaxy.regions[id].name)
      local middle = origin + made.regionsAt[id] * zoom
      Im.Text(label, middle.x - Im.TextWidth(label, 15) / 2, middle.y - 8, 15, Im.DIM, 0.85)
    end
  end
  if zoom > 1 and count <= CONSTELLATIONS then
    for _, constellation in galaxy.constellations do
      local at = made.constellationsAt[constellation.id]
      local middle = if at then origin + at * zoom else nil
      if middle and sighted(middle, 100) then
        -- (in capitals as a region's is, but small: a system's name is not)
        local label = string.upper(constellation.name)
        Im.Text(label, middle.x - Im.TextWidth(label, 11) / 2, middle.y + 14, 11, Im.DIM, 0.6)
      end
    end
  end
  -- (of the chart, what comes within the map: with the map looked at
  -- near that is little of it, and the rest costs nothing)
  local from, to = vector.create(mapX - 8, mapY - 8), vector.create(mapX + mapW + 8, mapY + mapH + 8)
  -- (every glyph has a glow to it, and thousands of them in sight at
  -- once add up to a white cloud: past CROWD of them they are fainter)
  local faint = if count > CROWD then math.max(0.12, (CROWD / count) ^ 1.2) else 1
  Icon_DrawWithin(its.edge, origin, zoom, Im.DIM, 0.22, from, to)
  -- (looked at from straight over, a stalk is a point under its system)
  if math.cos(pitch) > 0.02 then
    Icon_DrawWithin(its.stalks, origin, zoom, Im.DIM, 0.22 * faint, from, to)
  end
  Icon_DrawWithin(its.gates, origin, zoom, Im.DIM, 0.35 * faint, from, to)
  for _, group in its.dots do
    Icon_DrawWithin(group.icon, origin, zoom, group.color, 0.95 * math.sqrt(faint), from, to)
  end

  local route = Session.Route(session)
  -- (the systems the pilot's jobs lie in, in order of their ids)
  local jobSystems: { number } = {}
  for id in Waypoints.Systems(session) do
    table.insert(jobSystems, id)
  end
  table.sort(jobSystems)
  for index = 2, #route do
    Glyph_Draw(Glyph_Line(spot(route[index - 1]), spot(route[index]), 1, 1), 0, 1, Colors.White, 0.9)
  end

  -- (the systems that have their names by them already)
  local named: { [number]: boolean } = {}
  local function mark(id: number, radius: number, color: vector, label: boolean)
    local p = spot(id)
    Glyph_Draw(Glyph_Ring(p, radius, 1, 1, 0), 0, 1, color, 0.95)
    if label and not named[id] then
      named[id] = true
      Im.Text(systems[id].name, p.x + radius + 4, p.y - 8, 13, Im.TEXT)
    end
  end
  mark(here, 11, Colors.White, true)
  -- Where the nomads' colony fleets are: a box round the system each
  -- is in, in its people's colour. (They move on every quarter of an
  -- hour: Tactical/Nomads.)
  local roaming = Core.Query.Nomads(game)
  for _, fleet in roaming do
    local p = spot(fleet.system)
    if sighted(p, 0) then
      local half = 7
      local corners = { vector.create(p.x - half, p.y - half), vector.create(p.x + half, p.y - half),
        vector.create(p.x + half, p.y + half), vector.create(p.x - half, p.y + half) }
      for index, corner in corners do
        Glyph_Draw(Glyph_Line(corner, corners[index % 4 + 1], 1, 1), 0, 1, colorOf(fleet.faction), 0.9)
      end
    end
  end
  -- For a hull with a jump drive: the sphere its drive reaches, round
  -- where the pilot is (its outline, which is a circle however the map
  -- is looked at, and three rings round it that turn with the map: the
  -- level one, and two that stand upright); the systems inside it, each
  -- with a small ring; and where a beacon is lit for it, brighter where
  -- the drive reaches.
  local within = 0
  if reaching then
    local home = systems[here]
    local function place(px: number, py: number, pz: number): vector
      return origin + (seen(px, py, pz, made.middle, made.yaw, made.pitch) * made.scale - made.shift) * zoom
    end
    Glyph_Draw(Glyph_Ring(spot(here), reach * made.scale * zoom, 1, 1, 0), 0, 1, NEXT, 0.55)
    -- (in more steps the nearer it is looked at: it is a ring, not a polygon)
    local STEPS = math.clamp(math.ceil(48 * math.sqrt(zoom)), 48, 160)
    for ring = 1, 3 do
      local before: vector? = nil
      for index = 0, STEPS do
        local angle = index / STEPS * 2 * math.pi
        local c, sn = reach * math.cos(angle), reach * math.sin(angle)
        local point = if ring == 1 then place(home.x + c, home.y + sn, home.z)
          elseif ring == 2 then place(home.x + c, home.y, home.z + sn)
          else place(home.x, home.y + c, home.z + sn)
        if before and (sighted(before, 0) or sighted(point, 0)) then
          Glyph_Draw(Glyph_Line(before, point, 1, 1), 0, 1, NEXT, if ring == 1 then 0.35 else 0.16)
        end
        before = point
      end
    end
    local ringed = 4.5 * swollen(zoom)
    for id in systems do
      if id ~= here and Galaxy.Apart(galaxy, here, id) <= reach then
        within += 1
        local p = spot(id)
        if sighted(p, ringed) then
          Glyph_Draw(Glyph_Ring(p, ringed, 1, 1, 0), 0, 1, NEXT, 0.5)
        end
      end
    end
    for _, beacon in reaching.beacons do
      if beacon.system ~= here then
        mark(beacon.system, 7, if beacon.reached then NEXT else Im.DIM, false)
      end
    end
  end
  if session.destination ~= 0 and session.destination ~= here then
    mark(session.destination, 11, Im.ACCENT, true)
  end
  -- Where pirates are massing (Tactical/Surges), ringed twice in red.
  local surge = Core.Query.Surge(game)
  if surge then
    mark(surge.system, 13, BAND.lawless, surge.system ~= here and surge.system ~= session.destination)
    mark(surge.system, 16, BAND.lawless, false)
  end
  -- Where the pilot is next to go, in the gold the overview picks such
  -- places out in: the next system of the way to the destination, and
  -- the systems their jobs in hand are next to be done or paid in.
  local nextStop = if #route >= 2 then route[2] else 0
  if nextStop ~= 0 and nextStop ~= session.destination then
    mark(nextStop, 8, NEXT, true)
  end
  for _, id in jobSystems do
    if id ~= nextStop then
      mark(id, 6, NEXT, id == hot or id == picked)
    end
  end
  if picked ~= 0 and picked ~= here and picked ~= session.destination then
    mark(picked, 9, Im.WARN, true)
  end
  if hot ~= 0 and hot ~= here and hot ~= picked and hot ~= session.destination then
    mark(hot, 8, Im.DIM, true)
  end
  -- Looked at near enough that few are in sight, every system has its
  -- name by it.
  if allNamed then
    -- (clear of the ring a system within a jump drive's reach has round it)
    local beside = 4.5 * swollen(zoom) + 5
    for _, id in few do
      if not named[id] then
        local p = spot(id)
        Im.Text(systems[id].name, p.x + beside, p.y - 8, 12, Im.TEXT, 0.72)
      end
    end
  end
  -- A measure: how long so many light years are, across the window.
  -- (Across it, that is so however the map is turned; up and down it, a
  -- tilt shortens them.)
  local perLightYear = made.scale * zoom
  local measure = 1
  for _, many in { 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000 } do
    if many * perLightYear <= 150 then
      measure = many
    end
  end
  local mx, my = mapX + 16, mapY + mapH - 16
  local long = measure * perLightYear
  Glyph_Draw(Glyph_Line(vector.create(mx, my), vector.create(mx + long, my), 1, 1), 0, 1, Im.DIM, 0.9)
  Glyph_Draw(Glyph_Line(vector.create(mx, my - 4), vector.create(mx, my + 4), 1, 1), 0, 1, Im.DIM, 0.9)
  Glyph_Draw(Glyph_Line(vector.create(mx + long, my - 4), vector.create(mx + long, my + 4), 1, 1), 0, 1, Im.DIM, 0.9)
  Im.Text(`{measure} ly`, mx + long + 8, my - 8, 12, Im.DIM)
  ClipRegion_Pop()

  -- The panel: the system picked (or the one the pilot is in), and the
  -- way there.
  local px, line = x + w - SIDE, y + 56
  local shown = if picked ~= 0 then picked else here
  local system = systems[shown]
  local band = Galaxy.Band(system.security)
  local owner = Factions.byId[system.owner]
  Im.Heading(string.upper(system.name), px, line, 20, Im.TEXT)
  line += 28
  Im.Text(`{galaxy.constellations[system.constellation].name}, {galaxy.regions[system.region].name}`, px, line, 13, Im.DIM)
  line += 24
  Im.Text(if owner then `{owner.name} space` else "Nobody's", px, line, 14, if owner then colorOf(system.owner) else UNCLAIMED)
  if system.home then
    Im.Text("homeworld", px + 170, line, 13, Im.DIM)
  end
  line += 22
  Im.Text(string.format("%s  %.1f", BAND_NAME[band], system.security), px, line, 14, BAND[band])
  line += 22
  Im.Text(`{#system.neighbors} {if #system.neighbors == 1 then "gate" else "gates"}`, px, line, 13, Im.DIM)
  line += 20
  -- (a colony fleet that is there now, and for how long)
  for _, fleet in roaming do
    if fleet.system == shown then
      local minutes = math.max(1, math.ceil(fleet.leaves / 60))
      Im.Text(`{fleet.name} is here`, px, line, 13, colorOf(fleet.faction))
      Im.Text(`with its fleet, for {minutes} min more, then to {systems[fleet.next].name}`, px, line + 16, 12, Im.DIM)
      line += 36
    end
  end
  -- (what the pilot knows is there: a den found, a stronghold a den gave away)
  for index, name in Core.Query.KnownSites(game, shown) do
    if index <= 3 then
      Im.Text(name, px, line, 12, Im.WARN)
      line += 16
    end
  end
  line += 10
  if shown == here then
    Im.Text("You are here.", px, line, 13, Im.DIM)
  else
    local way = Session.Way(session, here, shown, session.safest)
    local wild = 0
    for index = 2, #way do
      wild += if Galaxy.Band(systems[way[index]].security) == "lawless" then 1 else 0
    end
    Im.Text(`{#way - 1} {if #way == 2 then "jump" else "jumps"} by the {if session.safest then "safest" else "shortest"} way`, px, line, 13,
      Im.TEXT)
    if wild > 0 then
      Im.Text(`{wild} of them into lawless space`, px, line + 18, 13, BAND.lawless)
    end
  end
  line += 46
  if Im.Button("Set destination", px, line, 150, 28, shown ~= here and shown ~= session.destination, "Map:destination") then
    session.destination = shown
  end
  if Im.Button("Clear", px + 156, line, 80, 28, session.destination ~= 0, "Map:clear") then
    session.destination, session.autopilot = 0, false
  end
  line += 36
  if Im.Toggle(if session.safest then "Safest way" else "Shortest way", px, line, 150, 28, session.safest, "Map:safest") then
    session.safest = not session.safest
  end
  line += 36
  if Im.Toggle(if session.autopilot then "Autopilot on" else "Autopilot", px, line, 150, 28, session.autopilot, "Map:autopilot")
    and session.destination ~= 0 then
    session.autopilot = not session.autopilot
  end
  line += 40
  -- A hull with a jump drive: how far it reaches, what the system shown
  -- would take, and the jump itself ("Map:jump"), which says why not
  -- when it cannot be made.
  local drive = Core.Query.JumpDrive(game, shown)
  if drive then
    Im.Heading("JUMP DRIVE", px, line, 14, Im.DIM)
    Im.TextRight(string.format("reaches %.1f ly: %d %s", drive.range, within, if within == 1 then "system" else "systems"),
      px + SIDE - 24, line + 1, 12, NEXT)
    line += 22
    if shown == here then
      Im.Text(`{Format.Whole(drive.held)} fuel blocks in the hold` .. (if drive.cooling > 0
        then `, cooling {Format.Duration(drive.cooling)}` else ""), px, line, 13, Im.DIM)
      line += 24
    else
      Im.Text(string.format("%.1f light years: %s fuel blocks of %s", drive.distance, Format.Whole(drive.fuel), Format.Whole(drive.held)),
        px, line, 13, if drive.distance <= drive.range and drive.held >= drive.fuel then Im.TEXT else Im.WARN)
      line += 22
      if Im.Button("Jump", px, line, 90, 28, drive.ready, "Map:jump") then
        Session.Do(session, { kind = "JumpDrive", actor = 0, target = shown })
      end
      line += 34
      if not drive.ready then
        line = Im.Wrapped(drive.why, px, line, SIDE - 28, 12, Im.WARN) + 6
      end
    end
    -- (it comes out at a beacon: the ones that are lit, nearest first)
    local lit = table.clone(drive.beacons)
    table.sort(lit, function(a: Core.JumpBeacon, b: Core.JumpBeacon): boolean
      if a.distance ~= b.distance then
        return a.distance < b.distance
      end
      return a.system < b.system
    end)
    if #lit == 0 then
      Im.Text("No beacon is lit: a Jump Beacon at a tower of", px, line, 12, Im.DIM)
      Im.Text("yours, or a fleet ship with a generator running.", px, line + 15, 12, Im.DIM)
      line += 34
    end
    for index, beacon in lit do
      if index <= 3 then
        Im.Text(string.format("Beacon: %s, %s (%.1f ly)", systems[beacon.system].name, beacon.kind, beacon.distance), px, line, 12,
          if beacon.reached then NEXT else Im.DIM)
        line += 16
      end
    end
  end
  line += 4
  if session.destination ~= 0 then
    Im.Text(`Going to {systems[session.destination].name}: {math.max(0, #route - 1)} jumps`, px, line, 13, Im.ACCENT)
    line += 20
    if nextStop ~= 0 then
      Im.Text(`Next: {systems[nextStop].name}`, px, line, 13, NEXT)
      line += 20
    end
  end
  if surge then
    Im.Text(`Pirate surge in {surge.name}: ` .. (if surge.jumps == 0 then "here" elseif surge.jumps == 1 then "1 jump" else `{surge.jumps} jumps`)
      .. `, {Format.Duration(surge.left)} left`, px, line, 12, BAND.lawless)
    line += 20
  end
  if #jobSystems > 0 then
    -- (the ringed systems: what is in hand there)
    local names: { string } = {}
    for index, id in jobSystems do
      if index <= 3 then
        table.insert(names, systems[id].name)
      end
    end
    Im.Text(`In hand at {table.concat(names, ", ")}` .. (if #jobSystems > 3 then ` and {#jobSystems - 3} more` else ""), px, line, 12, NEXT)
    line += 20
  end

  -- What the colours mean: the kinds of space, or the factions that hold
  -- any of this galaxy.
  local holders = Galaxy.Holders(galaxy)
  line = y + h - 60 - 18 * (if bySecurity then 3 else #holders + 1)
  Im.Heading(if bySecurity then "SECURITY" else "WHOSE", px, line, 14, Im.DIM)
  line += 22
  if bySecurity then
    for _, name in { "secure", "low", "lawless" } do
      Im.Fill(px, line + 3, 10, 10, BAND[name], 0.95)
      Im.Text(BAND_NAME[name], px + 18, line, 13, Im.DIM)
      line += 18
    end
  else
    for _, id in holders do
      Im.Fill(px, line + 3, 10, 10, colorOf(id), 0.95)
      Im.Text(Factions.byId[id].name, px + 18, line, 13, Im.DIM)
      line += 18
    end
    Im.Fill(px, line + 3, 10, 10, UNCLAIMED, 0.95)
    Im.Text("Nobody's", px + 18, line, 13, Im.DIM)
  end
end

return Map
