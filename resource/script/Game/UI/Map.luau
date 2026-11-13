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
-- to look right on a hull: two of the four are greys.)
local WHOSE: { [string]: vector } = {
  vessari = vector.create(1.0, 0.72, 0.28), talmar = vector.create(0.45, 0.78, 1.0),
  orun = vector.create(0.55, 0.9, 0.5), kethri = vector.create(0.82, 0.55, 1.0),
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

-- What is made once: where each system is on the map (in pixels from
-- the map's middle), the gates as one icon, and the systems as an icon
-- for every colour they are drawn in.
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
  gates: Icon,
  -- (each system's stalk to the plane, and the plane's edge)
  stalks: Icon,
  owned: { { icon: Icon, color: vector } },
  banded: { { icon: Icon, color: vector } },
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

-- Where a place in the galaxy (light years, 'z' its height) is on a map
-- looked at so, in light years across and down the screen from the
-- place 'middle'.
local function seen(x: number, y: number, z: number, middle: vector, turn: number, tilt: number): vector
  local dx, dy = x - middle.x, y - middle.y
  local c, sn = math.cos(turn), math.sin(turn)
  local rx, ry = dx * c - dy * sn, dx * sn + dy * c
  return vector.create(rx, ry * math.sin(tilt) - z * math.cos(tilt))
end

local function colorOf(faction: string): vector
  return WHOSE[faction] or UNCLAIMED
end

-- ('round' and 'reach': a sphere to leave room for, round a system and
-- so many light years out from it, for a hull with a jump drive; 0 and
-- 0 for none.)
local function make(galaxy: Galaxy.Galaxy, epoch: number, width: number, height: number, round: number, reach: number): Drawn
  local systems = galaxy.systems
  local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
  for _, system in systems do
    minX, maxX = math.min(minX, system.x), math.max(maxX, system.x)
    minY, maxY = math.min(minY, system.y), math.max(maxY, system.y)
  end
  local middle = vector.create((minX + maxX) / 2, (minY + maxY) / 2)
  -- (as it is looked at: every system, and the place on the plane under
  -- it, and the room all of that takes)
  local low, high = vector.create(math.huge, math.huge), vector.create(-math.huge, -math.huge)
  local over: { vector } = {}
  local under: { vector } = {}
  for id, system in systems do
    over[id] = seen(system.x, system.y, system.z, middle, yaw, pitch)
    under[id] = seen(system.x, system.y, 0, middle, yaw, pitch)
    low, high = vector.min(low, vector.min(over[id], under[id])), vector.max(high, vector.max(over[id], under[id]))
  end
  -- (and the edge of the plane, a little outside the outermost systems;
  -- and the sphere, which is a circle however it is looked at)
  local edge = 0.04 * math.max(maxX - minX, maxY - minY)
  local corners = { vector.create(minX - edge, minY - edge), vector.create(maxX + edge, minY - edge),
    vector.create(maxX + edge, maxY + edge), vector.create(minX - edge, maxY + edge) }
  for _, corner in corners do
    local p = seen(corner.x, corner.y, 0, middle, yaw, pitch)
    low, high = vector.min(low, p), vector.max(high, p)
  end
  if over[round] and reach > 0 then
    low, high = vector.min(low, over[round] - vector.create(reach, reach)), vector.max(high, over[round] + vector.create(reach, reach))
  end
  local scale = math.min((width - 2 * MARGIN) / math.max(1e-3, high.x - low.x), (height - 2 * MARGIN) / math.max(1e-3, high.y - low.y))
  local shift = (low + high) / 2 * scale
  local at: { vector } = {}
  for id in systems do
    at[id] = over[id] * scale - shift
  end
  local stalks = Icon_Create()
  for id, system in systems do
    if math.abs(system.z) > 0.05 and vector.magnitude(over[id] - under[id]) * scale > 1.5 then
      Icon_AddGlyph(stalks, Glyph_Line(at[id], under[id] * scale - shift, 1, 1))
    end
  end
  for index, corner in corners do
    local following = corners[index % 4 + 1]
    Icon_AddGlyph(stalks, Glyph_Line(seen(corner.x, corner.y, 0, middle, yaw, pitch) * scale - shift,
      seen(following.x, following.y, 0, middle, yaw, pitch) * scale - shift, 1, 1))
  end
  local gates = Icon_Create()
  for id, system in systems do
    for _, neighbor in system.neighbors do
      if neighbor > id then
        Icon_AddGlyph(gates, Glyph_Line(at[id], at[neighbor], 1, 1))
      end
    end
  end
  -- A dot a system: bigger for a homeworld, and smaller as there are
  -- more. (A box glyph: a circle glyph is a point of light with a halo,
  -- not a disc.)
  local dot = if #systems > 150 then 2 elseif #systems > 40 then 2.6 else 3.4
  local owned: { [string]: Icon? } = {}
  local banded: { [string]: Icon? } = {}
  local ownedList: { { icon: Icon, color: vector } } = {}
  local bandedList: { { icon: Icon, color: vector } } = {}
  for id, system in systems do
    local size = if system.home then dot * 1.7 else dot
    local mine: Icon? = owned[system.owner]
    if not mine then
      local fresh = Icon_Create()
      owned[system.owner] = fresh
      table.insert(ownedList, { icon = fresh, color = colorOf(system.owner) })
      mine = fresh
    end
    Icon_AddGlyph(mine, Glyph_Box(at[id], vector.create(size, size), 1, 1))
    local band = Galaxy.Band(system.security)
    local its: Icon? = banded[band]
    if not its then
      local fresh = Icon_Create()
      banded[band] = fresh
      table.insert(bandedList, { icon = fresh, color = BAND[band] })
      its = fresh
    end
    Icon_AddGlyph(its, Glyph_Box(at[id], vector.create(size, size), 1, 1))
  end
  return { epoch = epoch, width = width, height = height, yaw = yaw, pitch = pitch, scale = scale, middle = middle, shift = shift,
    round = round, reach = reach, at = at, gates = gates, stalks = stalks, owned = ownedList, banded = bandedList }
end

function Map.Draw(session: Session.Session, left: number, top: number, width: number, height: number)
  if not open then
    return
  end
  local game = session.game
  local galaxy = game.state.galaxy
  local systems = galaxy.systems
  local w, h = math.min(width - 80, 1400), math.min(height - 150, 820)
  local x, y = left + (width - w) / 2, top + (height - h) / 2 - 10
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

  -- The map.
  local mapW, mapH = w - SIDE - 16, h - 56
  local kept = drawn
  local made: Drawn
  -- (the right button held over the map turns it and tilts it)
  local pointer = Im.Cursor()
  local onMap = pointer.x >= x + 8 and pointer.x <= x + 8 + mapW and pointer.y >= y + 48 and pointer.y <= y + 48 + mapH
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
  local reaching = Core.Query.JumpDrive(game)
  local round = if reaching then Core.Query.Player(game).system else 0
  local reach = if reaching then reaching.range else 0
  if kept == nil or kept.epoch ~= session.epoch or kept.width ~= mapW or kept.height ~= mapH or #kept.at ~= #systems
    or kept.yaw ~= yaw or kept.pitch ~= pitch or kept.round ~= round or kept.reach ~= reach then
    made = make(galaxy, session.epoch, mapW, mapH, round, reach)
    drawn = made
    if systems[picked] == nil then
      picked = 0
    end
  else
    made = kept
  end
  local centre = vector.create(x + 8 + mapW / 2, y + 48 + mapH / 2)
  Im.Fill(x + 8, y + 48, mapW, mapH, vector.create(0.015, 0.02, 0.03), 0.85)
  -- The regions' names, each over the middle of its systems, under
  -- everything else.
  for _, region in galaxy.regions do
    local sum, count = vector.create(0, 0), 0
    for id, system in systems do
      if system.region == region.id then
        sum += made.at[id]
        count += 1
      end
    end
    if count > 0 then
      local label = string.upper(region.name)
      local middle = centre + sum / count
      Im.Text(label, middle.x - Im.TextWidth(label, 15) / 2, middle.y - 8, 15, Im.DIM, 0.85)
    end
  end
  Icon_Draw(made.stalks, centre, 1, Im.DIM, 0.22)
  Icon_Draw(made.gates, centre, 1, Im.DIM, 0.35)
  local groups: { { icon: Icon, color: vector } } = if bySecurity then made.banded else made.owned
  for _, group in groups do
    Icon_Draw(group.icon, centre, 1, group.color, 0.95)
  end

  local player = Core.Query.Player(game)
  local here = player.system
  local route = Session.Route(session)
  -- (the systems the pilot's jobs lie in, in order of their ids)
  local jobSystems: { number } = {}
  for id in Waypoints.Systems(session) do
    table.insert(jobSystems, id)
  end
  table.sort(jobSystems)
  for index = 2, #route do
    Glyph_Draw(Glyph_Line(centre + made.at[route[index - 1]], centre + made.at[route[index]], 1, 1), 0, 1, Colors.White, 0.9)
  end

  -- Which system the cursor is on, and a click picks it.
  local cursor = Im.Cursor()
  local hot, nearest = 0, 14 ^ 2
  if cursor.x >= x + 8 and cursor.x <= x + 8 + mapW and cursor.y >= y + 48 and cursor.y <= y + 48 + mapH then
    for id, at in made.at do
      local d2 = (centre.x + at.x - cursor.x) ^ 2 + (centre.y + at.y - cursor.y) ^ 2
      if d2 < nearest then
        hot, nearest = id, d2
      end
    end
  end
  if hot ~= 0 and Im.Pressed() then
    picked = hot
  end
  local function mark(id: number, radius: number, color: vector, label: boolean)
    local p = centre + made.at[id]
    Glyph_Draw(Glyph_Ring(p, radius, 1, 1, 0), 0, 1, color, 0.95)
    if label then
      Im.Text(systems[id].name, p.x + radius + 4, p.y - 8, 13, Im.TEXT)
    end
  end
  mark(here, 11, Colors.White, true)
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
      return centre + seen(px, py, pz, made.middle, made.yaw, made.pitch) * made.scale - made.shift
    end
    Glyph_Draw(Glyph_Ring(centre + made.at[here], reach * made.scale, 1, 1, 0), 0, 1, NEXT, 0.55)
    local STEPS = 48
    for ring = 1, 3 do
      local before: vector? = nil
      for step = 0, STEPS do
        local angle = step / STEPS * 2 * math.pi
        local c, sn = reach * math.cos(angle), reach * math.sin(angle)
        local point = if ring == 1 then place(home.x + c, home.y + sn, home.z)
          elseif ring == 2 then place(home.x + c, home.y, home.z + sn)
          else place(home.x, home.y + c, home.z + sn)
        if before then
          Glyph_Draw(Glyph_Line(before, point, 1, 1), 0, 1, NEXT, if ring == 1 then 0.35 else 0.16)
        end
        before = point
      end
    end
    for id in systems do
      if id ~= here and Galaxy.Apart(galaxy, here, id) <= reach then
        within += 1
        Glyph_Draw(Glyph_Ring(centre + made.at[id], 4.5, 1, 1, 0), 0, 1, NEXT, 0.5)
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
    local way = Galaxy.Route(galaxy, here, shown, session.safest)
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

  -- What the colours mean.
  line = y + h - 150
  Im.Heading(if bySecurity then "SECURITY" else "WHOSE", px, line, 14, Im.DIM)
  line += 22
  if bySecurity then
    for _, name in { "secure", "low", "lawless" } do
      Im.Fill(px, line + 3, 10, 10, BAND[name], 0.95)
      Im.Text(BAND_NAME[name], px + 18, line, 13, Im.DIM)
      line += 18
    end
  else
    for _, faction in Factions.list do
      if faction.kind == "human" then
        Im.Fill(px, line + 3, 10, 10, colorOf(faction.id), 0.95)
        Im.Text(faction.name, px + 18, line, 13, Im.DIM)
        line += 18
      end
    end
    Im.Fill(px, line + 3, 10, 10, UNCLAIMED, 0.95)
    Im.Text("Nobody's", px + 18, line, 13, Im.DIM)
  end
end

return Map
