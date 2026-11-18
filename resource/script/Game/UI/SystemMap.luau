--!strict
-- The system map: one system, its sun, planets and their orbits, moons,
-- belts, stations, gates and found sites, where the pilot's ship is, and
-- the scan probes, which are put where they are wanted here (the owner,
-- 2026-11-18: a system map and real probes, "Slanted, like the star
-- map"). A window of its own (Game/UI/Windows), opened from the dock,
-- docked or in space, and from the star map's panel for a system the
-- pilot has been to.
--
-- It is seen from a slant, as the star map is: what is above or below
-- the plane of the planets stands on a stalk. The right button held
-- turns it and tilts it, the wheel nears it about what the cursor is
-- on, and the left button held on nothing drags it about.
--
-- The probes (Tactical/Sites): the left button held on one drags it,
-- across the plane at its height; with Shift held, up and down. The
-- ring at the middle of them drags them all. Each probe's reach is
-- drawn round it, faint. After a scan, what the probes read of each
-- signal is drawn where it may be: a sphere (one probe reached it), a
-- ring (two), two points (three) or a point in a ring (four or more),
-- coloured by how much of it was read: red, then amber, yellow, green.
--
-- Its buttons' names, for a script (Im.Press): "SystemMap:scan",
-- "SystemMap:launch", "SystemMap:form", "SystemMap:recall",
-- "SystemMap:reach-", "SystemMap:reach+", "SystemMap:signal:<n>" (pick
-- the nth signal listed: the map goes to it), "SystemMap:centre:<n>"
-- (the probes, all of them, to what was read of it), "SystemMap:warp:<n>"
-- (a found one), "SystemMap:flat", "SystemMap:left", "SystemMap:right",
-- "SystemMap:in", "SystemMap:out", "SystemMap:fit", "SystemMap:here".

local Constants = require("@lt/Core/Data/Constants")
local Core = require("@lt/Core/Api")
local Im = require("@lt/Game/UI/Im")
local List = require("@lt/Game/UI/List")
local Session = require("@lt/Game/Session")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")
local Theme = require("@lt/Game/UI/Theme")
local Windows = require("@lt/Game/UI/Windows")

local SystemMap = {}

SystemMap.ID = "systemmap"

local AU = Constants.AU
local SIDE = 320
local NEARER = 1.25
local MOST = 4000          -- the nearest it is looked at: so many times nearer than the whole system

local SUN = vector.create(1.0, 0.82, 0.38)
-- (the probes and their reach in a neon purple, hard: nothing else on
-- the map is that colour, the orbits least of all. The owner, 2026-11-18:
-- "they need to be 1) hard lines, and 2) visually distinct from the
-- planet orbit lines. let's try a neon-purple hue")
local PROBE = vector.create(0.78, 0.32, 1.0)
local SHIP = vector.create(1.0, 0.80, 0.28)
local FOUND = vector.create(0.45, 0.85, 0.75)
local KINDS: { [string]: string } = { combat = "pirate den", ore = "hidden belt", gas = "vapour field", relic = "derelict",
  data = "listening post", mission = "camp to clear", keep = "pirate tower", wormhole = "wormhole" }

local current: Session.Session? = nil
local shown = 0             -- the system shown; 0 for the pilot's
local wasShown = -1         -- (the one shown last frame: another, and the view is fitted to it again)
-- How it is looked at: turned (radians), tilted (a quarter turn is from
-- straight over), how near (1: all of the system), and what is in the
-- middle (astronomical units: x and z of the system across, y up).
local TURNED, TILTED = 0.4, 0.85
local yaw, pitch = TURNED, TILTED
local zoom = 1
local focus = vector.zero
-- The left button, held from a press on the map: where it went down,
-- where the cursor was a frame ago, whether it has moved enough to be a
-- drag, and what it is dragging: the map ("pan"), a probe ("probe", its
-- id), all of them ("all"). 'at' is where what is dragged is now (AU).
type Grab = { from: vector, last: vector, moved: boolean, what: string, probe: number, at: vector, on: number }
local grab: Grab? = nil
local turning: vector? = nil
local picked = 0            -- the signal or place picked, by its id

function SystemMap.Open(system: number?)
  shown = system or 0
  Windows.Open(SystemMap.ID)
  Windows.Raise(SystemMap.ID)
end

function SystemMap.Close()
  Windows.Close(SystemMap.ID)
end

function SystemMap.IsOpen(): boolean
  return Windows.IsOpen(SystemMap.ID)
end

-- Once a frame, before the windows are drawn: whose game it is.
function SystemMap.Frame(session: Session.Session)
  current = session
end

-- The view: where a place (AU) is in the window, from the middle of the
-- map 'centre', at 'scale' pixels an AU.
local function project(p: vector, centre: vector, scale: number): vector
  local dx, dy, dh = p.x - focus.x, p.z - focus.z, p.y - focus.y
  local c, s = math.cos(yaw), math.sin(yaw)
  local rx, ry = dx * c - dy * s, dx * s + dy * c
  return vector.create(centre.x + rx * scale, centre.y + (ry * math.sin(pitch) - dh * math.cos(pitch)) * scale)
end

-- And the other way about: the place at a height (AU) under a point of the window.
local function unproject(point: vector, height: number, centre: vector, scale: number): vector
  local rx = (point.x - centre.x) / scale
  local down = (point.y - centre.y) / scale
  local ry = (down + (height - focus.y) * math.cos(pitch)) / math.sin(pitch)
  local c, s = math.cos(yaw), math.sin(yaw)
  return vector.create(focus.x + rx * c + ry * s, height, focus.z - rx * s + ry * c)
end

local function au(x: number, y: number, z: number): vector
  return vector.create(x / AU, y / AU, z / AU)
end

local function line(a: vector, b: vector, color: vector, alpha: number)
  Glyph_Draw(Glyph_Line(a * Theme.scale, b * Theme.scale, 1, 1), 0, 1, color, alpha)
end

local function ring(p: vector, radius: number, color: vector, alpha: number)
  if radius > 0.5 and radius < 20000 then
    Glyph_Draw(Glyph_Ring(p * Theme.scale, radius * Theme.scale, 1, 1, 0), 0, 1, color, alpha)
  end
end

local function dot(p: vector, radius: number, color: vector, alpha: number?)
  Glyph_Draw(Glyph_Circle(p * Theme.scale, radius * Theme.scale, 1, 1), 0, 1, color, alpha or 1)
end

-- A circle in space (AU): its middle, radius, and the way it faces.
local function circle(middle: vector, radius: number, normal: vector, centre: vector, scale: number, color: vector, alpha: number,
  steps: number?)
  local n = vector.normalize(normal)
  local helper = if math.abs(n.y) < 0.9 then vector.create(0, 1, 0) else vector.create(1, 0, 0)
  local u = vector.normalize(vector.cross(n, helper))
  local v = vector.cross(n, u)
  local before: vector? = nil
  local count = steps or 64
  for step = 0, count do
    local a = step / count * 2 * math.pi
    local p = project(middle + (u * math.cos(a) + v * math.sin(a)) * radius, centre, scale)
    if before then
      line(before, p, color, alpha)
    end
    before = p
  end
end

-- The names drawn on the map this frame, so that none is drawn over
-- another: a name that would be is left out (those drawn first win).
local labels: { { number } } = {}
-- ('always': drawn whatever it is over, and kept clear of after.)
local function label(text: string, x: number, y: number, color: vector, always: boolean?): boolean
  local size = 11
  local w, h = Im.TextWidth(text, size), size + 3
  for _, other in labels do
    if not always and x < other[3] and x + w > other[1] and y < other[4] and y + h > other[2] then
      return false
    end
  end
  table.insert(labels, { x, y, x + w, y + h })
  Im.Text(text, x, y, size, color)
  return true
end

-- What is named first when names crowd: the sun, the planets, the
-- gates, the stations, and the rest.
local FIRST: { [string]: number } = { sun = 1, planet = 2, gate = 3, station = 4 }

-- Whether the probes' reach is drawn as a sphere of wire (an equator,
-- two meridians and two rings of latitude) or as a flat ring
-- ("SystemMap:spheres"). Where a signal may be is a sphere of wire always.
local wire = false

-- A ring two pixels wide, of hard lines (the engine's ring glyph glows
-- inward, which washed the map over).
local function bold(p: vector, radius: number, color: vector, alpha: number)
  if radius < 1 or radius > 20000 then
    return
  end
  local count = math.clamp(math.floor(radius / 3), 24, 96)
  for _, r in { radius, radius + 1 } do
    local before = p + vector.create(r, 0)
    for step = 1, count do
      local a = step / count * 2 * math.pi
      local now = p + vector.create(r * math.cos(a), r * math.sin(a))
      line(before, now, color, alpha)
      before = now
    end
  end
end

-- A sphere (AU): of wire, or ('flat') a ring the size of it on the screen.
local function sphere(middle: vector, radius: number, centre: vector, scale: number, color: vector, alpha: number, flat: boolean?)
  if flat then
    bold(project(middle, centre, scale), radius * scale, color, alpha)
    return
  end
  if radius * scale < 2 or radius * scale > 20000 then
    return
  end
  local up = vector.create(0, 1, 0)
  circle(middle, radius, up, centre, scale, color, alpha, 40)
  circle(middle, radius, vector.create(1, 0, 0), centre, scale, color, alpha * 0.8, 40)
  circle(middle, radius, vector.create(0, 0, 1), centre, scale, color, alpha * 0.8, 40)
  for _, at in { 0.5, -0.5 } do
    circle(middle + up * (radius * at), radius * math.sqrt(1 - at * at), up, centre, scale, color, alpha * 0.6, 32)
  end
end

-- The colour of what was read of a signal, by how much.
local function readColor(reading: number): vector
  return if reading >= 0.75 then Theme.GOOD elseif reading >= 0.5 then Theme.CAUTION
    elseif reading >= 0.25 then vector.create(1.0, 0.6, 0.25) else Theme.BAD
end

-- Where to look to see a signal's reading: its middle (AU).
local function readingAt(scan: State.SiteScan): vector
  if scan.probes == 3 then
    return au((scan.x + scan.ox) / 2, (scan.y + scan.oy) / 2, (scan.z + scan.oz) / 2)
  end
  return au(scan.x, scan.y, scan.z)
end

-- How the places of a kind are drawn: size, colour, and whether named
-- from far away.
local function looks(object: System.Object): (number, vector, boolean)
  local kind = object.kind
  if kind == "sun" then
    return 7, SUN, true
  elseif kind == "planet" then
    return 4.5, Theme.TEXT, true
  elseif kind == "moon" then
    return 2, Theme.FAINT, false
  elseif kind == "belt" then
    return 2.5, Theme.DIM, false
  elseif kind == "station" then
    return 3.5, Theme.ACCENT, false
  elseif kind == "gate" then
    return 4, Theme.GOOD, true
  end
  return 3, FOUND, false
end

-- The probes: the controls at the top of the panel. Returns how far down they went.
local function probeControls(session: Session.Session, x: number, y: number, w: number, probes: Core.ProbeStatus, wait: number): number
  local scan: State.Command = { kind = "Scan", actor = 0 }
  local can, why = Session.CanDo(session, scan)
  Im.Tone("primary")
  Im.Because(why)
  if Im.Button("Scan", x, y, 110, 28, can, "SystemMap:scan") then
    Session.Do(session, scan)
  end
  Im.Text(if wait > 0 then `cycling: {math.ceil(wait)} s` elseif can then "ready" else tostring(why), x + 120, y + 7, 13,
    if can then Theme.GOOD else Theme.DIM)
  y += 36
  local launch: State.Command = { kind = "LaunchProbe", actor = 0 }
  local canLaunch, whyLaunch = Session.CanDo(session, launch)
  Im.Because(whyLaunch)
  if Im.Button("Launch", x, y, 92, 26, canLaunch, "SystemMap:launch") then
    Session.Do(session, launch)
  end
  local form: State.Command = { kind = "FormProbes", actor = 0 }
  local canForm, whyForm = Session.CanDo(session, form)
  Im.Because(whyForm)
  if Im.Button("Form up", x + 98, y, 92, 26, canForm, "SystemMap:form") then
    Session.Do(session, form)
  end
  local recall: State.Command = { kind = "RecallProbes", actor = 0 }
  local canRecall, whyRecall = Session.CanDo(session, recall)
  Im.Because(whyRecall)
  if Im.Button("Recall", x + 196, y, 92, 26, canRecall, "SystemMap:recall") then
    Session.Do(session, recall)
  end
  y += 34
  -- How far they reach: a step in or out.
  local ranges = Core.Query.ProbeRanges()
  local at = table.find(ranges, probes.range) or 1
  Im.Text("Reach", x, y + 6, 13, Theme.DIM)
  if Im.Button("-", x + 52, y, 28, 26, at > 1, "SystemMap:reach-") then
    Session.Do(session, { kind = "ProbeRange", actor = 0, quantity = ranges[at - 1] })
  end
  local said = `{probes.range} AU`
  Im.Text(said, x + 116 - Im.TextWidth(said, 14) / 2, y + 5, 14, Theme.TEXT)
  if Im.Button("+", x + 152, y, 28, 26, at < #ranges, "SystemMap:reach+") then
    Session.Do(session, { kind = "ProbeRange", actor = 0, quantity = ranges[at + 1] })
  end
  Im.Text("smaller reads stronger", x + 190, y + 6, 12, Theme.FAINT)
  y += 32
  Im.Text(`{probes.here} of {probes.max} out here, {probes.carried} in the hold`, x, y, 12, Theme.DIM)
  y += 16
  Im.Text(if probes.launcher ~= "" then probes.launcher else "No probe launcher fitted", x, y, 12,
    if probes.launcher ~= "" then Theme.DIM else Theme.CAUTION)
  return y + 20
end

local function drawPanel(session: Session.Session, x: number, y: number, w: number, h: number, mine: boolean, inSpace: boolean,
  sites: { Core.SiteStatus }, probes: Core.ProbeStatus, wait: number, name: string)
  Im.Flat(x, y, 1, h, Theme.EDGE)
  local left = x + 12
  Im.Strong(string.upper(name), left, y + 4, 14, Theme.TEXT)
  Im.Text(if mine then "where you are" else "a system you have been to", left, y + 22, 12, Theme.DIM)
  local top = y + 44
  if mine and inSpace then
    top = probeControls(session, left, top, w - 24, probes, wait)
  elseif mine then
    Im.Text("Undock to scan and to put out probes.", left, top, 13, Theme.DIM)
    top += 22
  end
  Im.Flat(x + 1, top, w - 2, 1, Theme.EDGE)
  top += 6
  if not mine then
    return
  end
  -- The signals: what is still to be found first.
  local ordered: { Core.SiteStatus } = {}
  for _, site in sites do
    if not site.found then
      table.insert(ordered, site)
    end
  end
  for _, site in sites do
    if site.found then
      table.insert(ordered, site)
    end
  end
  Im.Text(`{#ordered} {if #ordered == 1 then "signal" else "signals"}`, left, top, 12, Theme.DIM)
  top += 18
  local ROW = 44
  local bodyH = h - (top - y) - 8
  local first, visible = List.Body("systemmap signals", x + 1, top, w - 2, bodyH, #ordered, ROW)
  for row = 1, visible do
    local index = row + first
    local site = ordered[index]
    if site == nil then
      break
    end
    local rowY = top + (row - 1) * ROW
    local hot, clicked = List.Row(x + 1, rowY, w - 8, site.id == picked, `SystemMap:signal:{index}`, ROW)
    if clicked then
      picked = site.id
      -- (and the map goes to it: where it is, or where the probes read it)
      local object: System.Object? = nil
      for _, one in Core.Query.Objects(session.game, Core.Query.Player(session.game).system) do
        if one.id == site.id then
          object = one
        end
      end
      if site.found and object then
        focus = au(object.x, object.y, object.z)
      elseif site.scan then
        focus = readingAt(site.scan)
      end
    end
    Im.Text(site.name, left, rowY + 4, 13, if site.found then Theme.TEXT elseif hot then Theme.TEXT else Theme.DIM)
    local about = if site.found then KINDS[site.kind] or site.kind
      elseif site.scan then `{site.scan.probes} {if site.scan.probes == 1 then "probe" else "probes"} on it`
        .. (if site.near ~= "" then `, by {site.near}` else "")
      elseif site.faint then "too faint: put probes over it"
      elseif site.near ~= "" then `by {site.near}`
      else "unresolved"
    Im.Text(about, left, rowY + 22, 12, if site.faint and not site.scan then Theme.CAUTION else Theme.FAINT)
    local bx = x + w - 98
    if site.found then
      local can = Session.Can(session, "WarpTo", site.id, 0)
      if Im.Button("Warp", bx + 16, rowY + 8, 70, 26, can, `SystemMap:warp:{index}`) then
        session.selected = site.id
        Session.Order(session, "WarpTo", site.id, 0)
      end
    else
      local bar = 54
      Im.Flat(bx, rowY + 10, bar, 5, Theme.EDGE)
      Im.Flat(bx, rowY + 10, bar * math.clamp(site.strength, 0, 1), 5, if site.scan then readColor(site.reading) else Theme.ACCENT)
      Im.Text(`{math.floor(site.strength * 100)}%`, bx + bar + 6, rowY + 5, 12, Theme.DIM)
      local scan = site.scan
      if scan and probes.here > 0 then
        local to = readingAt(scan) * AU
        local move: State.Command = { kind = "MoveProbes", actor = 0, target = 0, x = to.x, y = to.y, z = to.z }
        Im.Because("Send all the probes to where it was read")
        if Im.Button("Probes here", bx - 4, rowY + 20, 92, 20, (Session.CanDo(session, move)), `SystemMap:centre:{index}`) then
          Session.Do(session, move)
        end
      end
    end
  end
end

Windows.Kind(SystemMap.ID, function(_: Windows.Window, x: number, y: number, w: number, h: number)
  local session = current
  if session == nil then
    return
  end
  local game = session.game
  local was = Im.Plain(true)
  local player = Core.Query.Player(game)
  local system = if shown ~= 0 then shown else player.system
  local mine = system == player.system
  local inSpace = player.docked == 0
  local objects = Core.Query.Chart(game, system)
  if wasShown ~= system then
    wasShown, zoom, focus, picked = system, 1, vector.zero, 0
  end
  Im.Fill(x, y, w, h, vector.create(0.02, 0.03, 0.045), 0.97)

  -- How it is looked at, along the top.
  local tx = x + 10
  local flat = pitch >= math.pi / 2 - 1e-3
  if Im.Toggle("Flat", tx, y + 6, 60, 24, flat, "SystemMap:flat") then
    yaw, pitch = if flat then TURNED else 0, if flat then TILTED else math.pi / 2
  end
  if Im.Button("<", tx + 66, y + 6, 28, 24, true, "SystemMap:left") then
    yaw -= math.pi / 12
  end
  if Im.Button(">", tx + 98, y + 6, 28, 24, true, "SystemMap:right") then
    yaw += math.pi / 12
  end
  local step = 0
  if Im.Button("-", tx + 144, y + 6, 28, 24, zoom > 1, "SystemMap:out") then
    step = -1
  end
  if Im.Button("+", tx + 176, y + 6, 28, 24, zoom < MOST, "SystemMap:in") then
    step = 1
  end
  if Im.Button("Fit", tx + 208, y + 6, 44, 24, zoom > 1 or focus ~= vector.zero, "SystemMap:fit") then
    zoom, focus = 1, vector.zero
  end
  local ball = Core.Query.Ball(game, player.ship)
  local toHere = Im.Button("Here", tx + 256, y + 6, 54, 24, mine and ball ~= nil, "SystemMap:here")
  if Im.Toggle("Spheres", tx + 330, y + 6, 84, 24, wire, "SystemMap:spheres") then
    wire = not wire
  end
  Im.Flat(x + 1, y + 36, w - 2, 1, Theme.EDGE)

  local mapX, mapY, mapW, mapH = x + 1, y + 37, w - SIDE - 2, h - 38
  local centre = vector.create(mapX + mapW / 2, mapY + mapH / 2)
  -- (the whole system fits the map at a zoom of 1)
  local extent = 0.5
  for _, object in objects do
    extent = math.max(extent, math.sqrt(object.x ^ 2 + object.z ^ 2) / AU)
  end
  local fit = (math.min(mapW, mapH) / 2 - 24) / (extent * 1.05)
  local pointer = Im.Cursor()
  local onMap = Im.Inside(mapX, mapY, mapW, mapH)
  local notches = step + (if onMap then Mouse_GetScrollDelta() else 0)
  if notches ~= 0 then
    local to = math.clamp(zoom * NEARER ^ notches, 1, MOST)
    if to ~= zoom then
      -- (about what the cursor is on, at the height of the middle; or the middle)
      local about = if step == 0 then unproject(pointer, focus.y, centre, fit * zoom) else focus
      focus = about - (about - focus) * (zoom / to)
      zoom = to
    end
  end
  if toHere and ball then
    focus = au(ball.x, ball.y, ball.z)
    zoom = math.max(zoom, math.min(MOST, extent / 2))
  end
  if zoom <= 1 then
    focus = vector.create(focus.x, 0, focus.z)
  end
  local scale = fit * zoom
  -- (the right button held over the map turns it and tilts it)
  if Mouse_RightDown() and (turning ~= nil or onMap) then
    local before = turning or pointer
    yaw += (pointer.x - before.x) * 0.008
    pitch = math.clamp(pitch + (pointer.y - before.y) * 0.006, 0.3, math.pi / 2)
    turning = pointer
  else
    turning = nil
  end

  -- What there is to draw: the probes (only in the pilot's system) and the signals.
  local probeList: { Core.ProbeInfo } = if mine then Core.Query.Probes(game) else {}
  local sites: { Core.SiteStatus } = {}
  local wait, probes = 0, { here = 0, out = 0, max = 8, carried = 0, range = 8, launcher = "" } :: Core.ProbeStatus
  if mine then
    sites, wait, probes = Core.Query.Sites(game)
  end
  local reach = probes.range
  local middle = vector.zero
  for _, probe in probeList do
    middle += au(probe.tx, probe.ty, probe.tz)
  end
  if #probeList > 0 then
    middle /= #probeList
  end

  -- The left button: on a probe it drags the probe, on the ring at their
  -- middle all of them, and on nothing the map. A press that does not
  -- move picks the place it is on.
  local function near(p: vector, within: number): boolean
    return vector.magnitude(project(p, centre, scale) - pointer) <= within
  end
  if Im.Pressed() and onMap and grab == nil then
    local what, id, at = "pan", 0, vector.zero
    for _, probe in probeList do
      local p = au(probe.tx, probe.ty, probe.tz)
      if near(p, 8) then
        what, id, at = "probe", probe.id, p
      end
    end
    if what == "pan" and #probeList > 1 and near(middle, 12) then
      what, at = "all", middle
    end
    local on = 0
    for _, object in objects do
      if near(au(object.x, object.y, object.z), 7) then
        on = object.id
      end
    end
    grab = { from = pointer, last = pointer, moved = false, what = what, probe = id, at = at, on = on }
  end
  local held = grab
  if held then
    if Mouse_LeftDown() then
      held.moved = held.moved or vector.magnitude(pointer - held.from) > 4
      if held.moved then
        if held.what == "pan" then
          local a, b = unproject(held.last, focus.y, centre, scale), unproject(pointer, focus.y, centre, scale)
          focus -= b - a
        elseif Key_Down(Key_LShift()) or Key_Down(Key_RShift()) then
          -- (up and down: not when the map is seen from straight over)
          local tilt = math.cos(pitch)
          if tilt > 0.05 then
            held.at = vector.create(held.at.x, held.at.y - (pointer.y - held.last.y) / (scale * tilt), held.at.z)
          end
        else
          held.at = unproject(pointer, held.at.y, centre, scale)
        end
      end
      held.last = pointer
    else
      if held.moved and held.what ~= "pan" then
        local to = held.at * AU
        Session.Do(session, { kind = "MoveProbes", actor = 0, target = if held.what == "probe" then held.probe else 0,
          x = to.x, y = to.y, z = to.z })
      elseif not held.moved and held.on ~= 0 then
        picked = held.on
        if mine then
          session.selected = held.on
        end
      end
      grab = nil
    end
  end

  ClipRegion_Push(vector.create(mapX, mapY), vector.create(mapW, mapH))
  labels = {}
  -- The orbits of the planets, in the plane.
  local sun = vector.zero
  for _, object in objects do
    if object.kind == "planet" then
      local r = math.sqrt(object.x ^ 2 + object.z ^ 2) / AU
      circle(sun, r, vector.create(0, 1, 0), centre, scale, Theme.EDGE_STRONG, 0.8)
    end
  end
  -- The places: on stalks from the plane, named where there is room.
  local named = scale * 0.02 > 30
  local ordered = table.clone(objects)
  table.sort(ordered, function(a: System.Object, b: System.Object): boolean
    local fa, fb = FIRST[a.kind] or 5, FIRST[b.kind] or 5
    if fa ~= fb then
      return fa < fb
    end
    return a.id < b.id
  end)
  for _, object in ordered do
    local p = au(object.x, object.y, object.z)
    local s = project(p, centre, scale)
    local size, color, always = looks(object)
    if math.abs(p.y) * scale > 3 then
      line(s, project(vector.create(p.x, 0, p.z), centre, scale), color, 0.3)
    end
    if object.kind == "station" then
      Im.Flat(s.x - size, s.y - size, size * 2, size * 2, color)
    elseif object.kind == "gate" then
      line(s + vector.create(0, -size), s + vector.create(size, 0), color, 1)
      line(s + vector.create(size, 0), s + vector.create(0, size), color, 1)
      line(s + vector.create(0, size), s + vector.create(-size, 0), color, 1)
      line(s + vector.create(-size, 0), s + vector.create(0, -size), color, 1)
    else
      dot(s, size, color)
    end
    if object.id == picked then
      ring(s, size + 5, Theme.ACCENT, 0.9)
    end
    if always or named or object.id == picked then
      label(object.name, s.x + size + 4, s.y - 7, if object.kind == "sun" or object.kind == "planet" then Theme.TEXT else Theme.DIM)
    end
  end
  -- The pilot's ship.
  if mine and ball then
    local p = au(ball.x, ball.y, ball.z)
    local s = project(p, centre, scale)
    line(s + vector.create(0, -6), s + vector.create(5, 4), SHIP, 1)
    line(s + vector.create(5, 4), s + vector.create(-5, 4), SHIP, 1)
    line(s + vector.create(-5, 4), s + vector.create(0, -6), SHIP, 1)
    label("you", s.x - Im.TextWidth("you", 11) / 2, s.y + 7, SHIP, true)
  end
  -- What the probes read of each signal, where it may be.
  for _, site in sites do
    local scan = site.scan
    if scan and not site.found then
      local color = readColor(scan.reading)
      local alpha = if site.id == picked then 1 else 0.75
      local c = au(scan.x, scan.y, scan.z)
      local s = project(c, centre, scale)
      if scan.probes == 1 then
        sphere(c, scan.radius / AU, centre, scale, color, alpha * 0.6)
      elseif scan.probes == 2 then
        circle(c, scan.radius / AU, vector.create(scan.nx, scan.ny, scan.nz), centre, scale, color, alpha)
      elseif scan.probes == 3 then
        for _, p in { c, au(scan.ox, scan.oy, scan.oz) } do
          local q = project(p, centre, scale)
          line(q + vector.create(-4, -4), q + vector.create(4, 4), color, alpha)
          line(q + vector.create(-4, 4), q + vector.create(4, -4), color, alpha)
        end
      else
        dot(s, 3, color, alpha)
        if scan.radius / AU * scale >= 6 then
          sphere(c, scan.radius / AU, centre, scale, color, alpha * 0.8)
        else
          ring(s, math.max(4, scan.radius / AU * scale), color, alpha * 0.8)
        end
      end
      label(`{site.name}: probes read {math.floor(scan.reading * 100)}%`, s.x + 8, s.y + 4, color, true)
    end
  end
  -- The probes, their reach round each, and the ring at their middle.
  for _, probe in probeList do
    local p = au(probe.x, probe.y, probe.z)
    local to = au(probe.tx, probe.ty, probe.tz)
    local dragged = held and held.moved and held.what == "probe" and held.probe == probe.id
    if dragged and held then
      to = held.at
    elseif held and held.moved and held.what == "all" then
      to += held.at - middle
    end
    local s, t = project(p, centre, scale), project(to, centre, scale)
    if probe.moving or vector.magnitude(t - s) > 1 then
      line(s, t, PROBE, 0.6)
    end
    if math.abs(to.y) * scale > 3 then
      line(t, project(vector.create(to.x, 0, to.z), centre, scale), PROBE, 0.5)
    end
    local hot = dragged or vector.magnitude(t - pointer) <= 8
    sphere(to, reach, centre, scale, PROBE, if hot then 1 else 0.8, not wire)
    dot(t, 3.5, PROBE)
    dot(s, 2, PROBE, 0.8)
  end
  if #probeList > 1 then
    local m = middle
    if held and held.moved and held.what == "all" then
      m = held.at
    end
    bold(project(m, centre, scale), 9, PROBE, 1)
  end
  -- A measure in the corner: how long an AU, or a tenth of one, is.
  local unit = 1
  while unit * scale > 160 do
    unit /= 10
  end
  while unit * scale < 30 do
    unit *= 10
  end
  local mx, my = mapX + 16, mapY + mapH - 18
  line(vector.create(mx, my), vector.create(mx + unit * scale, my), Theme.DIM, 0.9)
  Im.Text(if unit >= 1 then `{unit} AU` else `{unit} AU`, mx, my - 16, 11, Theme.DIM)
  if mine and inSpace and #probeList > 0 then
    Im.Text("Drag a probe to move it, Shift to raise or lower it; the ring at their middle moves them all.", mapX + 16, mapY + 8, 12,
      Theme.FAINT)
  end
  ClipRegion_Pop()

  local node = game.state.galaxy.systems[system]
  drawPanel(session, x + w - SIDE, y + 37, SIDE, h - 38, mine, inSpace, sites, probes, wait, if node then node.name else "?")
  Im.Plain(was)
end)
Windows.Make(SystemMap.ID, SystemMap.ID, "System map", 300, 100, 1240, 760, 900, 560, nil)
Windows.Icon(SystemMap.ID, "systemmap")

return SystemMap
