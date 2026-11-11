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
-- "Map:destination", "Map:clear", "Map:safest", "Map:autopilot".

local Colors = require("@lt/Colors")
local Core = require("@lt/Core/Api")
local Factions = require("@lt/Core/Data/Factions")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Im = require("@lt/Game/UI/Im")
local Session = require("@lt/Game/Session")

local Map = {}

local SIDE = 300          -- the panel beside the map
local MARGIN = 28

local UNCLAIMED = vector.create(0.34, 0.35, 0.38)
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

-- What is made once: where each system is on the map (in pixels from
-- the map's middle), the gates as one icon, and the systems as an icon
-- for every colour they are drawn in.
type Drawn = {
  epoch: number, width: number, height: number,
  at: { vector },
  gates: Icon,
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

local function colorOf(faction: string): vector
  return WHOSE[faction] or UNCLAIMED
end

local function make(galaxy: Galaxy.Galaxy, epoch: number, width: number, height: number): Drawn
  local systems = galaxy.systems
  local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
  for _, system in systems do
    minX, maxX = math.min(minX, system.x), math.max(maxX, system.x)
    minY, maxY = math.min(minY, system.y), math.max(maxY, system.y)
  end
  local scale = math.min((width - 2 * MARGIN) / math.max(1e-3, maxX - minX), (height - 2 * MARGIN) / math.max(1e-3, maxY - minY))
  local at: { vector } = {}
  for id, system in systems do
    at[id] = vector.create((system.x - (minX + maxX) / 2) * scale, (system.y - (minY + maxY) / 2) * scale)
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
  return { epoch = epoch, width = width, height = height, at = at, gates = gates, owned = ownedList, banded = bandedList }
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

  -- The map.
  local mapW, mapH = w - SIDE - 16, h - 56
  local kept = drawn
  local made: Drawn
  if kept == nil or kept.epoch ~= session.epoch or kept.width ~= mapW or kept.height ~= mapH or #kept.at ~= #systems then
    made = make(galaxy, session.epoch, mapW, mapH)
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
  Icon_Draw(made.gates, centre, 1, Im.DIM, 0.35)
  local groups: { { icon: Icon, color: vector } } = if bySecurity then made.banded else made.owned
  for _, group in groups do
    Icon_Draw(group.icon, centre, 1, group.color, 0.95)
  end

  local player = Core.Query.Player(game)
  local here = player.system
  local route = Session.Route(session)
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
  if session.destination ~= 0 and session.destination ~= here then
    mark(session.destination, 11, Im.ACCENT, true)
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
  line += 30
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
  line += 44
  if session.destination ~= 0 then
    Im.Text(`Going to {systems[session.destination].name}: {math.max(0, #route - 1)} jumps`, px, line, 13, Im.ACCENT)
    line += 22
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
