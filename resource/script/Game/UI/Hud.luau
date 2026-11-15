--!strict
-- The interface. In space: brackets on everything in view, shots drawn
-- between ships, the overview, the selected item and its orders, locked
-- targets, the ship's condition, its module rack and the navigation bar.
-- Docked: the station's screens (Game/UI/Station).
--
-- One widget draws all of it every frame (Game/UI/Im). It reads the Core
-- through queries and acts on it only through the Session.

local Assets = require("@lt/Game/UI/Assets")
local Events = require("@lt/Game/UI/Events")
local Boosters = require("@lt/Core/Data/Boosters")
local Colony = require("@lt/Game/UI/Colony")
local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Constants = require("@lt/Core/Data/Constants")
local Context = require("@lt/Game/UI/Context")
local Core = require("@lt/Core/Api")
local Format = require("@lt/Game/Format")
local Guide = require("@lt/Game/UI/Guide")
local Im = require("@lt/Game/UI/Im")
local Inventory = require("@lt/Game/UI/Inventory")
local Info = require("@lt/Game/UI/Info")
local Keys = require("@lt/Game/UI/Keys")
local Map = require("@lt/Game/UI/Map")
local Menu = require("@lt/Game/UI/Menu")
local Modules = require("@lt/Core/Data/Modules")
local Ores = require("@lt/Core/Data/Ores")
local Hack = require("@lt/Game/UI/Hack")
local Scanner = require("@lt/Game/UI/Scanner")
local Scene = require("@lt/Game/View/Scene")
local Session = require("@lt/Game/Session")
local Ships = require("@lt/Core/Data/Ships")
local Splash = require("@lt/Game/UI/Splash")
local State = require("@lt/Core/Kernel/State")
local Station = require("@lt/Game/UI/Station")
local Waypoints = require("@lt/Game/Waypoints")
local Windows = require("@lt/Game/UI/Windows")
local Moons = require("@lt/Core/Data/Moons")
local Structures = require("@lt/Core/Data/Structures")
local Types = require("@lt/Core/Data/Types")

local Hud = {}

local overInterface = false
local overviewScroll = 0
-- How the overview is listed: by which column ("distance", "name" or
-- "type"), and whether the other way round (farthest first, Z to A).
local overviewSort, overviewDown = "distance", false

-- Whether the cursor was over a panel last frame (the camera then leaves
-- the mouse alone).
function Hud.CursorOverInterface(): boolean
  return overInterface
end

-- The light a jump through a gate whites the view out with.
local VEIL = vector.create(0.80, 0.92, 1.0)
-- What a cloud of gas does to the view from inside it, and how far it
-- has come on (0 to 1).
local HAZE = vector.create(0.78, 0.74, 0.66)
local haze = 0

local TAGS: { [string]: string } = {
  sun = "SUN", planet = "PLN", moon = "MON", belt = "BLT", asteroid = "AST",
  station = "STA", gate = "GAT", ship = "SHP", wreck = "WRK", site = "SIT", bookmark = "BKM",
}

-- What a site (Tactical/Sites) is called, by the variety of its place.
local SITES: { [string]: string } = { ["site.combat"] = "pirate den", ["site.ore"] = "hidden belt", ["site.relic"] = "derelict",
  ["site.gas"] = "vapour field", ["site.data"] = "listening post", ["site.mission"] = "camp to clear", ["site.keep"] = "pirate tower",
  ["site.wormhole"] = "wormhole", ["site.front"] = "two factions' forces: warp here to see the fight" }

-- Whether a row of the overview is a vault (Core/Tactical/Sites): a
-- wreck to the Core, and not one to the pilot.
local function vaulted(entry: Core.Entry): boolean
  return entry.kind == "wreck" and string.sub(entry.variety, 1, 6) == "vault."
end

-- Whether a row of the overview is a cloud of gas (Core/Data/Ores): a
-- rock to the Core, and not one to the pilot.
local function cloudy(entry: Core.Entry): boolean
  return entry.kind == "asteroid" and Ores.gasById[entry.variety] ~= nil
end

-- The three kinds of space (Describe/Galaxy), as the pilot is told.
local BANDS: { [string]: string } = { secure = "SECURE SPACE", low = "LOW SECURITY", lawless = "LAWLESS SPACE" }
local SAFE = vector.create(0.45, 0.85, 0.55)

local SHIELD = vector.create(0.35, 0.65, 1.0)
local ARMOR = vector.create(0.95, 0.75, 0.3)
local HULL = vector.create(0.85, 0.35, 0.3)
-- (a ship of the pilot's side: a drone, or a hired pilot's)
local OURS = vector.create(0.45, 0.85, 0.55)
-- Where the pilot is next to go (Game/Waypoints): the gate of the way
-- they have planned, the place a job is done or paid.
local NEXT = vector.create(1.0, 0.80, 0.28)
local CAPACITOR = vector.create(1.0, 0.9, 0.5)
-- (how full an ore hold is: the colour of rock)
local ORE = vector.create(0.66, 0.56, 0.44)

-- ---------------------------------------------------------------------
-- Bracket icons, one per kind, built on first use.

local function v(x: number, y: number): vector
  return vector.create(x, y)
end

local icons: { [string]: Icon } = {}

local function icon(kind: string): Icon
  local made: Icon? = icons[kind]
  if made then
    return made
  end
  local glyphs: { Glyph }
  if kind == "ship" then
    -- the corners of a square
    glyphs = {}
    for _, c in { v(-1, -1), v(1, -1), v(1, 1), v(-1, 1) } do
      table.insert(glyphs, Glyph_Line(c, v(c.x * 0.4, c.y), 1, 1))
      table.insert(glyphs, Glyph_Line(c, v(c.x, c.y * 0.4), 1, 1))
    end
  elseif kind == "station" then
    glyphs = { Glyph_Line(v(-1, -1), v(1, -1), 1, 1), Glyph_Line(v(1, -1), v(1, 1), 1, 1),
      Glyph_Line(v(1, 1), v(-1, 1), 1, 1), Glyph_Line(v(-1, 1), v(-1, -1), 1, 1), Glyph_Circle(0, 0.5, 1, 1) }
  elseif kind == "gate" then
    glyphs = { Glyph_Ring(0, 1, 1, 1, 0), Glyph_Line(v(-1.4, 0), v(-1, 0), 1, 1), Glyph_Line(v(1, 0), v(1.4, 0), 1, 1) }
  elseif kind == "sun" then
    glyphs = { Glyph_Ring(0, 1, 1, 1, 0), Glyph_Circle(0, 0.6, 1, 1) }
  elseif kind == "belt" then
    glyphs = { Glyph_Circle(v(-0.7, 0.5), 0.45, 1, 1), Glyph_Circle(v(0.7, 0.5), 0.45, 1, 1), Glyph_Circle(v(0, -0.6), 0.45, 1, 1) }
  elseif kind == "asteroid" then
    glyphs = { Glyph_Circle(0, 0.5, 1, 1) }
  elseif kind == "wreck" then
    glyphs = { Glyph_Line(v(-1, -1), v(1, 1), 1, 1), Glyph_Line(v(-1, 1), v(1, -1), 1, 1) }
  elseif kind == "bookmark" then
    -- a pin: a diamond on a stalk
    glyphs = { Glyph_Line(v(0, -1), v(0.7, -0.2), 1, 1), Glyph_Line(v(0.7, -0.2), v(0, 0.4), 1, 1),
      Glyph_Line(v(0, 0.4), v(-0.7, -0.2), 1, 1), Glyph_Line(v(-0.7, -0.2), v(0, -1), 1, 1), Glyph_Line(v(0, 0.4), v(0, 1.2), 1, 1) }
  else
    glyphs = { Glyph_Ring(0, 1, 1, 1, 0) }
  end
  local built = Icon_Create()
  for _, glyph in glyphs do
    Icon_AddGlyph(built, glyph)
  end
  icons[kind] = built
  return built
end

-- ---------------------------------------------------------------------
-- Small pieces

-- A bar showing 'value' of 'max'.
local function bar(x: number, y: number, w: number, h: number, value: number, max: number, color: vector)
  Im.Fill(x, y, w, h, Im.DIM, 0.25)
  if max > 0 then
    Im.Fill(x, y, w * math.clamp(value / max, 0, 1), h, color, 0.95)
  end
end

local function shorten(name: string, limit: number): string
  return if #name > limit then (string.gsub(string.sub(name, 1, limit - 1), "%s+$", "")) .. "." else name
end

local function whole(n: number): string
  return tostring(math.floor(n + 0.5))
end

-- What the ship is doing, in words.
local function describe(game: Core.Game, ball: State.Ball): string
  local function name(id: number): string
    local body = Core.Query.Body(game, id)
    return if body then body.name else "?"
  end
  local intent = ball.intent
  local warp = ball.warp
  if warp then
    -- (a fleet's warp waits for the fleet: Core/Tactical/Space)
    local verb = if warp.stage == "warp" then "Warping to" elseif warp.gang then "Fleet forming up for" else "Aligning to"
    return `{verb} {name(warp.target)}`
  elseif intent then
    return `{if intent.kind == "dock" then "Docking at" else "Jumping through"} {name(intent.target)}`
  elseif ball.mode == "approach" then
    return `Approaching {name(ball.target)}`
  elseif ball.mode == "orbit" then
    return `Orbiting {name(ball.target)} at {Format.Distance(ball.range)}`
  elseif ball.mode == "keep" then
    return `Keeping {name(ball.target)} at {Format.Distance(ball.range)}`
  elseif ball.mode == "goto" or ball.mode == "align" then
    return "Flying"
  end
  return "Stopped"
end

local function lockOf(ball: State.Ball, target: number): State.Lock?
  for _, lock in ball.vitals.locks do
    if lock.target == target then
      return lock
    end
  end
  return nil
end

-- Where a body is on screen, or nil if it is behind the camera.
local function onScreen(scene: Scene.Scene, id: number): vector?
  local at = scene.screen[id]
  if at then
    local projected = Camera_Project(scene.camera, at)
    if projected.z > 0 then
      return Position_Frame(projected)
    end
  end
  return nil
end

-- ---------------------------------------------------------------------
-- In space

local function drawBrackets(session: Session.Session, scene: Scene.Scene, entries: { Core.Entry }, w: Widget,
  ball: State.Ball?, marks: Waypoints.Marks)
  local cursor = Im.Cursor()
  local clicked = 0
  local onGrid = false
  local nearest = 14 ^ 2
  for _, entry in entries do
    local p = onScreen(scene, entry.id)
    if p and p.x >= w.pos.x and p.x <= w.pos.x + w.size.x and p.y >= w.pos.y and p.y <= w.pos.y + w.size.y then
      local selected = entry.id == session.selected
      local d2 = (p.x - cursor.x) ^ 2 + (p.y - cursor.y) ^ 2
      local hot = d2 < 14 ^ 2 and not overInterface
      local small = entry.kind == "asteroid"
      local lock = if ball then lockOf(ball, entry.id) else nil
      local hostile = entry.hostile
      -- (where the pilot is next to go stands out, and says what it is)
      local goal = marks[entry.id] ~= nil
      local color = if selected then Colors.White elseif hostile then HULL elseif goal then NEXT elseif entry.own then OURS
        elseif entry.onGrid then Im.ACCENT else Im.DIM
      Icon_Draw(icon(entry.kind), p, if small then 4 else 8, color, if selected or hot or goal then 1 else 0.7)
      if goal then
        Glyph_Draw(Glyph_Ring(p, 12, 1, 1, 0), 0, 1, NEXT, 0.8)
      end
      if lock then
        -- a ring round a target: closing while it locks, steady once locked
        Glyph_Draw(Glyph_Ring(p, if lock.locked then 14 else 20, 1, 1, 0), 0, 1, Colors.White, if lock.locked then 0.9 else 0.5)
      end
      if selected or hot then
        Im.Text(entry.name, p.x + 18, p.y - 16, 14, Im.TEXT)
        Im.Text(Format.Distance(entry.distance), p.x + 18, p.y, 13, Im.DIM)
      elseif goal then
        Im.Text(entry.name, p.x + 18, p.y - 8, 13, NEXT)
      end
      if hot and d2 < nearest then
        nearest = d2
        clicked = entry.id
        onGrid = entry.onGrid
      end
    end
  end
  if clicked ~= 0 and Im.Pressed() and not overInterface then
    session.selected = clicked
  end
  -- A double click out in space flies the ship: to what is under the
  -- cursor, as a double click on its row of the overview would (fly to
  -- what is here, warp to what is not); or, with nothing there, the way
  -- the cursor points.
  if ball and Im.DoublePressed() and not overInterface then
    if clicked ~= 0 then
      Session.Order(session, if onGrid then "Approach" else "WarpTo", clicked, 0)
    else
      local ray = Camera_GetRay(scene.camera, cursor)
      local way = Ray_GetPoint(ray, 1000) - Ray_GetPoint(ray, 0)
      session.autopilot = false
      Session.Do(session, { kind = "Goto", actor = 0, x = way.x, y = way.y, z = way.z })
    end
  end
  -- (a right click picks it out too, and brings up what can be done about
  -- it; and on empty space, what there is in the system to go to)
  if clicked ~= 0 and Im.RightPressed() and not overInterface then
    session.selected = clicked
    Context.Open(clicked, cursor.x, cursor.y)
  elseif ball and Im.RightPressed() and not overInterface then
    Context.OpenSpace(cursor.x, cursor.y)
  end
end

-- What a row of the overview says a thing is, in three letters.
local function tagOf(entry: Core.Entry): string
  return if cloudy(entry) then "GAS" elseif vaulted(entry) then "VLT" else TAGS[entry.kind] or "?"
end

-- The overview as it is listed: what the Core gives (nearest first) put
-- in the order the pilot has asked for, by a column; and where the pilot
-- is next to go first, whatever the order: the gate of the way they
-- have planned, the place a job is done or paid.
local function listed(all: { Core.Entry }, marks: Waypoints.Marks): { Core.Entry }
  local sorted = all
  if overviewSort ~= "distance" or overviewDown then
    -- (each with its place as the Core gave it: what is alike by the column stays nearest first)
    local order: { { entry: Core.Entry, key: string, at: number } } = {}
    for at, entry in all do
      table.insert(order, { entry = entry, at = at,
        key = if overviewSort == "name" then string.lower(entry.name) elseif overviewSort == "type" then tagOf(entry) else "" })
    end
    local down = overviewDown
    table.sort(order, function(a, b): boolean
      if a.key ~= b.key then
        return (a.key < b.key) ~= down
      elseif overviewSort == "distance" then
        return a.at > b.at
      end
      return a.at < b.at
    end)
    sorted = {}
    for _, each in order do
      table.insert(sorted, each.entry)
    end
  end
  if next(marks) == nil then
    return sorted
  end
  local entries: { Core.Entry } = {}
  for _, entry in sorted do
    if marks[entry.id] then
      table.insert(entries, entry)
    end
  end
  for _, entry in sorted do
    if not marks[entry.id] then
      table.insert(entries, entry)
    end
  end
  return entries
end

-- How the overview is listed, and (given a column) a way to say so:
-- the column it is listed by, and whether the other way round. Asking
-- for the column it is already listed by turns it round.
function Hud.Sort(by: string?): (string, boolean)
  if by == "distance" or by == "name" or by == "type" then
    overviewDown = if by == overviewSort then not overviewDown else false
    overviewSort = by
    overviewScroll = 0
  end
  return overviewSort, overviewDown
end

-- The names on the overview as it is listed, top first: for a script.
function Hud.Listed(session: Session.Session): { string }
  local names: { string } = {}
  for _, entry in listed(Core.Query.Overview(session.game), Waypoints.Of(session)) do
    table.insert(names, entry.name)
  end
  return names
end

local function drawOverview(session: Session.Session, all: { Core.Entry }, x: number, y: number, width: number, height: number,
  marks: Waypoints.Marks)
  local rowHeight = 22
  local entries = listed(all, marks)
  Im.Panel(x, y, width, height)
  Im.Heading(`OVERVIEW  {#entries}`, x + 12, y + 8, 16, Im.DIM)
  -- (the ship's scanner, for what is on nobody's chart: it takes the
  -- place the colonies and assets windows take)
  -- (and the marking of where the ship is, to warp back to: it is on
  -- the overview from then on, in this system)
  local mark: State.Command = { kind = "Bookmark", actor = 0 }
  if Im.Button("Mark", x + width - 144, y + 5, 64, 22, (Session.CanDo(session, mark)), "Bookmark") then
    Session.Do(session, mark)
  end
  if Im.Button("Scan", x + width - 76, y + 5, 64, 22, true, "Scanner") then
    if Scanner.IsOpen() then
      Scanner.Close()
    else
      Scanner.Open()
      Colony.Close()
      Guide.Close()
    end
  end
  -- The columns' heads: a click lists by that column, and another turns
  -- it round. The one it is listed by says which way.
  local function head(column: string, label: string, at: number, right: boolean)
    local text = if overviewSort == column then label .. (if overviewDown then " v" else " ^") else label
    local hx = if right then at - Im.TextWidth(text, 11) else at
    if Im.Link(text, hx, y + 33, 11, if overviewSort == column then Im.TEXT else Im.DIM, `Overview:sort:{column}`) then
      Hud.Sort(column)
    end
  end
  head("type", "TYPE", x + 12, false)
  head("name", "NAME", x + 52, false)
  head("distance", "DISTANCE", x + width - 12, true)
  local top = y + 50
  local visible = math.max(1, (height - 58) // rowHeight)
  if Im.Inside(x, y, width, height) then
    overviewScroll -= 3 * Mouse_GetScrollDelta()
  end
  overviewScroll = math.clamp(math.floor(overviewScroll + 0.5), 0, math.max(0, #entries - visible))
  for row = 1, visible do
    local entry = entries[row + overviewScroll]
    if entry == nil then
      break
    end
    local rowY = top + (row - 1) * rowHeight
    local hot, clicked, double = Im.Row(x + 4, rowY, width - 8, rowHeight, entry.id == session.selected)
    if hot and Im.RightPressed() then
      session.selected = entry.id
      Context.Open(entry.id, Im.Cursor().x, Im.Cursor().y)
    end
    local goal = marks[entry.id] ~= nil
    local color = if entry.hostile then HULL elseif goal then NEXT elseif entry.own then OURS elseif entry.onGrid then Im.TEXT else Im.DIM
    if goal then
      Im.Fill(x + 4, rowY + 2, 3, rowHeight - 4, NEXT, 0.95)
    end
    Im.Text(tagOf(entry), x + 12, rowY + 3, 13, if goal then NEXT else Im.DIM)
    Im.Text(entry.name, x + 52, rowY + 3, 14, color)
    Im.TextRight(Format.Distance(entry.distance), x + width - 12, rowY + 3, 14, color)
    -- (a ship in a cloud of gas says so, before its distance: it is locked only from close in)
    if entry.veiled then
      Im.TextRight("in vapour", x + width - 86, rowY + 4, 12, Im.ACCENT)
    end
    if clicked then
      session.selected = entry.id
    end
    if double then
      -- The obvious thing: fly to what is here, warp to what is not.
      if entry.onGrid then
        Session.Order(session, "Approach", entry.id, 0)
      else
        Session.Order(session, "WarpTo", entry.id, 0)
      end
    end
  end
end

-- The hired pilot the fleet's orders are for (by their id), or 0: everybody.
local fleetPicked = 0

-- What each order to the ship is to the keyboard, given at what is
-- selected (an action of Game/UI/Keys, which says what key that is).
local ORDER_KEYS: { [string]: string } = {
  Approach = "approach", Orbit = "orbit", KeepAtRange = "keep", AlignTo = "align", WarpTo = "warp", Dock = "dock", Jump = "dock",
  LockTarget = "lock", UnlockTarget = "lock",
}

-- The marked place whose name is shown as a field in the panel of what
-- is selected, what the field holds, and the tick a new name for it was
-- sent to the Core (-1 with none on its way).
local naming = 0
local named = ""
local sentAt = -1


-- The camera follows the pilot's target, by itself (the project
-- owner's, 2026-11-13: "when you lock (and target) a ship, your camera
-- should automatically track it, so you don't need to constantly pan
-- with the mouse to keep it in view", and of several things locked at
-- once, "The camera would track to the targeted one"). Which thing is
-- the target is Session.Aim's to say: when that becomes another, and it
-- is a ship, the camera goes to it; when there is none, it follows
-- nothing. A hand on the camera takes it back, and so does C: it is the
-- pilot's until their target is another. (Ships only: a rock that is
-- being mined does not move, and wants nobody's eye kept on it.)
local following = { target = 0, on = 0 }
local function followTarget(session: Session.Session, scene: Scene.Scene, game: Core.Game)
  local target = session.target
  -- (taken from it since: by a hand, by C, or by its going from the grid)
  if scene.tracking ~= following.on then
    following.on = 0
  end
  if target ~= following.target then
    if target ~= 0 and Core.Query.Ball(game, target) then
      Scene.Track(scene, target)
      following.on = target
    elseif following.on ~= 0 then
      Scene.Track(scene, 0)
      following.on = 0
    end
    following.target = target
  end
end

-- What a weapon switched on now fires at (or a mining laser cuts, or a
-- projector holds): the pilot's target if it is locked; else what is
-- selected, if that is; else the first thing locked. 0 with nothing.
local function aimOf(session: Session.Session, ball: State.Ball): number
  for _, wanted in { session.target, session.selected } do
    local lock = lockOf(ball, wanted)
    if lock and lock.locked then
      return wanted
    end
  end
  for _, lock in ball.vitals.locks do
    if lock.locked then
      return lock.target
    end
  end
  return 0
end

local function drawSelected(session: Session.Session, entries: { Core.Entry }, ball: State.Ball, x: number, y: number, width: number)
  local selected: Core.Entry? = nil
  for _, entry in entries do
    if entry.id == session.selected then
      selected = entry
      break
    end
  end
  Im.Panel(x, y, width, 158)
  if selected == nil then
    Im.Heading("NOTHING SELECTED", x + 12, y + 8, 16, Im.DIM)
    Im.Text("Click a bracket or an overview row.", x + 12, y + 36, 14, Im.DIM)
    return
  end
  local entry: Core.Entry = selected
  if entry.kind == "bookmark" then
    -- A place the pilot marked is called what they like: its name is a
    -- field, and what is typed there is its name when the typing is done.
    local tick = session.game.state.tick
    if naming ~= entry.id then
      naming, named, sentAt = entry.id, entry.name, -1
    end
    named = Im.Words("Bookmark:name", named, x + 8, y + 4, width - 120, 24, 32)
    if not Im.Typing() and named ~= entry.name then
      local rename: State.Command = { kind = "RenameBookmark", actor = 0, target = entry.id, what = named }
      if sentAt >= 0 and tick > sentAt then
        -- (the name sent is the place's now, tidied: the field shows it as it is kept)
        named, sentAt = entry.name, -1
      elseif sentAt < 0 and Session.CanDo(session, rename) then
        Session.Do(session, rename)
        sentAt = tick
      elseif sentAt < 0 then
        -- (no name at all, or one that will not do: it is called what it was)
        named = entry.name
      end
    elseif not Im.Typing() then
      sentAt = -1
    end
  else
    naming = 0
    Im.Heading(string.upper(entry.name), x + 12, y + 8, 16, Im.TEXT)
  end
  local what = if entry.variety ~= "" and entry.kind ~= "ship" then `{entry.variety} {entry.kind}` else entry.kind
  if entry.kind == "station" and entry.variety == "colony ship" then
    -- (a station to moor at, and a ship: it says the second)
    what = "colony ship"
  end
  if entry.kind == "ship" and Core.Query.Berth(session.game, entry.id) then
    -- (and the nomads' are ships that are stations: it says so, since
    -- Dock is the thing to do with one)
    what = "colony ship: dock here"
  end
  if entry.kind == "bookmark" then
    what = "a place you marked"
  end
  -- (a hauler with a hold of what the economy sends along the lanes says so: it is real, and whose)
  local haul = if entry.kind == "ship" then Core.Query.Haul(session.game, entry.id) else nil
  if haul then
    what = `carrying {Format.Whole(haul.amount)} {haul.name} for {haul.system}`
  end
  -- (and a ship that is a member's of the pilot's corporation says whose it is, and what it is at)
  local fellow = if entry.kind == "ship" then Core.Query.Fellow(session.game, entry.id) else nil
  if fellow then
    what = `member, {fellow.trade}: {fellow.doing}`
  end
  if entry.kind == "site" then
    what = SITES[entry.variety] or "site"
  end
  if vaulted(entry) then
    what = if entry.variety == "vault.locked" then "vault, locked" else "vault, open"
  end
  if cloudy(entry) then
    -- (and how much of it there is still to draw off)
    what = `cloud of gas, {math.floor(Core.Query.Left(session.game, entry.id) * 100 + 0.5)}% left`
  end
  local tone = Im.DIM
  if entry.kind == "moon" then
    -- (a moon says what is under it, for whoever would put a tower and a drill there)
    local deposit = Core.Query.Deposit(session.game, entry.id)
    what = if deposit then `moon: {deposit.material.name}, {Moons.Word(deposit.richness)}` else "moon: nothing under it"
    tone = if deposit then NEXT else Im.DIM
    -- (and whether it is anybody's to put one at: Tactical/Keeps)
    if Core.Query.Keep(session.game, entry.id) then
      what ..= ": pirates hold it"
      tone = Im.WARN
    end
  end
  -- (the pirates' tower, or its place, says how it stands)
  local held = if entry.variety == "site.keep" or entry.variety == "works.keep" then Core.Query.Keep(session.game, entry.id) else nil
  if held then
    what = if held.sealed > 0 then `pirate tower: SEALED, opens in {Format.Duration(held.sealed)}`
      elseif held.resupplied > 0 then `pirate tower: nothing to seal with for {Format.Duration(held.resupplied)}`
      else `pirate tower: {held.batteries} {if held.batteries == 1 then "battery" else "batteries"} round it`
    tone = if held.sealed > 0 then Im.DIM elseif held.resupplied > 0 then NEXT else Im.WARN
  end
  -- (a wormhole says where it leads, how big a hull it lets through,
  -- and how long it has: Core/Tactical/Wormholes)
  local through = if entry.variety == "site.wormhole" then Core.Query.Wormhole(session.game, entry.id) else nil
  if through then
    -- (short: the line shares its row with how far off the thing is.
    -- What a size lets through is on the scanner's row for it, and in
    -- the refusal if the ship is too big.)
    local left = if through.left >= 3600 then `{through.left // 3600} h left` else `{math.max(1, through.left // 60)} min left`
    what = if through.fits then `{through.sizeName} wormhole to {through.leads}, {left}`
      else `{through.sizeName} wormhole: nothing over {through.lets} fits`
    tone = if through.fits then NEXT else Im.WARN
  end
  if entry.kind == "gate" and entry.variety == "passage" then
    -- (a camp's gate: shut until its room is cleared)
    what = if Session.Can(session, "Jump", entry.id) then "the camp's gate: open" else "the camp's gate: shut"
  elseif entry.kind == "gate" then
    -- (a gate says what kind of space is on the other side of it)
    local gate: any = Core.Query.Body(session.game, entry.id)
    local _, band = Core.Query.Security(session.game, if gate then gate.to else 0)
    if band then
      what = `gate to {string.lower(BANDS[band])}`
      tone = if band == "secure" then SAFE elseif band == "low" then Im.WARN else HULL
    end
  end
  Im.Text(what, x + 12, y + 32, 14, tone)
  Im.TextRight(Format.Distance(entry.distance), x + width - 12, y + 32, 14, Im.TEXT)

  local targeted = lockOf(ball, entry.id) ~= nil
  -- (what is done at a moon is to anchor a tower there: the one in the hold)
  local tower = 0
  if entry.kind == "moon" then
    for _, item in Core.Query.Items(session.game, ball.id, "cargo") do
      if Structures.towerById[item.type] then
        tower = item.id
        break
      end
    end
  end
  local orders: { { label: string, kind: string, range: number? } } = {
    { label = "Approach", kind = "Approach", range = 0 },
    -- (at the distances last picked from the menu a right click brings up)
    { label = `Orbit {Context.Distance(Context.Range("Orbit"))}`, kind = "Orbit", range = Context.Range("Orbit") },
    { label = `Keep {Context.Distance(Context.Range("KeepAtRange"))}`, kind = "KeepAtRange", range = Context.Range("KeepAtRange") },
    { label = if Context.Range("WarpTo") > 0 then `Warp to {Context.Distance(Context.Range("WarpTo"))}` else "Warp to", kind = "WarpTo",
      range = Context.Range("WarpTo") },
    { label = "Align", kind = "AlignTo" },
    if entry.kind == "gate" or through then { label = if entry.variety == "passage" or through then "Go through" else "Jump", kind = "Jump" }
      elseif entry.kind == "bookmark" then { label = "Forget", kind = "ForgetBookmark" }
      elseif entry.kind == "moon" then { label = "Anchor tower", kind = "AnchorTower" }
      elseif entry.kind == "planet" then { label = "Colony", kind = "Colony" }
      else { label = "Dock", kind = "Dock" },
    if targeted then { label = "Unlock", kind = "UnlockTarget" } else { label = "Lock", kind = "LockTarget" },
    { label = "Loot", kind = "Loot" },
  }
  if entry.kind == "wreck" then
    -- (a sealed hold is hacked open before it is looted)
    table.insert(orders, { label = "Hack", kind = "StartHack" })
  end
  local buttonWidth = (width - 24 - 16) / 3
  for index, order in orders do
    local column, line = (index - 1) % 3, (index - 1) // 3
    local bx, by = x + 12 + column * (buttonWidth + 8), y + 58 + line * 32
    if order.kind == "AnchorTower" then
      local command: State.Command = { kind = "AnchorTower", actor = 0, item = tower, target = entry.id }
      if Im.Button(order.label, bx, by, buttonWidth, 26, (Session.CanDo(session, command))) then
        Session.Do(session, command)
      end
    elseif order.kind == "Colony" then
      -- (what a planet has, the colony there, and the putting down of one)
      if Im.Button(order.label, bx, by, buttonWidth, 26, true) then
        Colony.Open(entry.id)
      end
    else
      local can = Session.Can(session, order.kind, entry.id, order.range)
      local key = ORDER_KEYS[order.kind]
      local pressed = key ~= nil and Keys.Did(key) and can
      if Im.Button(order.label, bx, by, buttonWidth, 26, can) or pressed then
        -- (a wreck or a container is opened: what is in it is in the inventory, to take or to leave)
        if order.kind == "Loot" then
          Inventory.Show(entry.id)
        else
          Session.Order(session, order.kind, entry.id, order.range)
        end
      end
      -- (a right click on one that is given at a distance: its distances,
      -- for the one this button gives it at from now on)
      if (order.kind == "Orbit" or order.kind == "KeepAtRange" or order.kind == "WarpTo") and Im.Inside(bx, by, buttonWidth, 26)
        and Im.RightPressed() then
        Context.Set(order.kind, Im.Cursor().x, Im.Cursor().y)
      end
    end
  end
end

-- The targets the ship has locked or is locking, in a row, with how
-- many it has of how many it can have. One of them is the pilot's
-- target (Session.Aim), and is lit and says so: a click on another
-- makes that one it.
local function drawTargets(session: Session.Session, game: Core.Game, ball: State.Ball, x: number, y: number)
  local now = game.state.tick * Constants.TICK
  if #ball.vitals.locks > 0 then
    Im.Text(`TARGETS  {#ball.vitals.locks} / {ball.vitals.maxTargets}`, x, y - 15, 11, Im.DIM)
  end
  for index, lock in ball.vitals.locks do
    local body = Core.Query.Body(game, lock.target)
    if body then
      local bx = x + (index - 1) * 168
      local aimed = lock.target == session.target
      Im.Panel(bx, y, 160, 62)
      local _, clicked = Im.Row(bx, y, 160, 62, aimed, `Target:{index}`)
      if clicked then
        session.selected = lock.target
        session.target = lock.target
      end
      Im.Text(shorten(body.name, if aimed then 15 else 22), bx + 8, y + 5, 14, Im.TEXT)
      if aimed then
        Im.TextRight("TARGET", bx + 152, y + 7, 11, Im.ACCENT)
      end
      if not lock.locked then
        Im.Text(string.format("locking  %.0f s", math.max(0, lock.done - now)), bx + 8, y + 26, 13, Im.WARN)
      else
        local other = Core.Query.Ball(game, lock.target)
        if other then
          local v = other.vitals
          bar(bx + 8, y + 28, 144, 5, v.shield, v.shieldMax, SHIELD)
          bar(bx + 8, y + 36, 144, 5, v.armor, v.armorMax, ARMOR)
          bar(bx + 8, y + 44, 144, 5, v.hull, v.hullMax, HULL)
        else
          Im.Text("locked", bx + 8, y + 26, 13, Im.DIM)
        end
      end
    end
  end
end

-- The ship's own condition; and, for a hull with an ore hold, how full
-- that is, m3 (the panel grows upward by a row for it: its foot stays
-- where it is).
local function drawStatus(game: Core.Game, ball: State.Ball, x: number, y: number)
  local v = ball.vitals
  local rows: { { label: string, value: number, max: number, color: vector } } = {
    { label = "Shield", value = v.shield, max = v.shieldMax, color = SHIELD },
    { label = "Armor", value = v.armor, max = v.armorMax, color = ARMOR },
    { label = "Hull", value = v.hull, max = v.hullMax, color = HULL },
    { label = "Capacitor", value = v.capacitor, max = v.capacitorMax, color = CAPACITOR },
  }
  -- (a hull with no shield has no row for one: the Nimia's)
  if v.shieldMax <= 0 then
    table.remove(rows, 1)
    y += 22
  end
  local oreSize, oreUsed = Core.Query.OreHold(game, ball.id)
  if oreSize > 0 then
    table.insert(rows, { label = "Ore hold", value = oreUsed, max = oreSize, color = ORE })
    y -= 22
  end
  local baySize, bayUsed = Core.Query.ShipBay(game, ball.id)
  if baySize > 0 then
    table.insert(rows, { label = "Ship bay", value = bayUsed, max = baySize, color = ORE })
    y -= 22
  end
  Im.Panel(x, y, 220, 12 + #rows * 22)
  for index, row in rows do
    local rowY = y + 10 + (index - 1) * 22
    Im.Text(row.label, x + 10, rowY - 2, 13, Im.DIM)
    bar(x + 78, rowY + 3, 92, 8, row.value, row.max, row.color)
    Im.TextRight(whole(row.value), x + 212, rowY - 2, 13, Im.TEXT)
  end
end

-- The pilot's boosters (Core/Character/Boosters): those at work, each
-- with the time it has left, and those to hand (in the hold, and in the
-- hangar where the ship is docked), each with a button to take it. A
-- panel that is there only when there is something to put in it, its
-- foot at 'foot'. A script's names: "Booster:<id>" ("Booster:redline").
local BOOSTER_ROWS = 5
local function drawBoosters(session: Session.Session, x: number, foot: number)
  local working, hand = Core.Query.Boosters(session.game)
  local rows = math.min(BOOSTER_ROWS, #working + #hand)
  if rows == 0 then
    return
  end
  local width, height = 316, 30 + rows * 22
  local y = foot - height
  Im.Panel(x, y, width, height)
  Im.Heading("BOOSTERS", x + 10, y + 7, 13, Im.DIM)
  local line = y + 28
  local shown = 0
  for _, row in working do
    if shown < rows then
      shown += 1
      Info.Name(row.booster.id, row.booster.name, x + 10, line, 13, Im.TEXT)
      -- (how much of its time is left, as a bar and in figures: the bar
      -- in the colour of a warning for one that sat badly, whose ill
      -- effect is at work too)
      Im.Fill(x + 148, line + 6, 90, 5, Im.DIM, 0.25)
      Im.Fill(x + 148, line + 6, 90 * math.clamp(row.left / math.max(row.whole, Boosters.SECONDS), 0, 1), 5,
        if row.wrong then Im.WARN else Im.ACCENT, 0.95)
      Im.TextRight(Format.Duration(row.left), x + width - 10, line, 12, Im.DIM)
      line += 22
    end
  end
  for _, row in hand do
    if shown < rows then
      shown += 1
      Info.Name(row.booster.id, row.booster.name, x + 10, line, 13, if row.refused then Im.DIM else Im.TEXT)
      Im.Text(`x{row.quantity}`, x + 148, line, 12, Im.DIM)
      local take: State.Command = { kind = "TakeBooster", actor = 0, item = row.item }
      if Im.Button("Take", x + width - 74, line - 2, 64, 20, row.refused == nil,
        `Booster:{string.sub(row.booster.id, #"booster." + 1)}`) then
        Session.Do(session, take)
      end
      line += 22
    end
  end
end

-- The fitted modules, as buttons: click to switch one on or off. A row
-- for each kind of slot that has anything in it: the high slots on top,
-- the mid slots under them, and the low slots (and the rigs) under
-- those, each row in the middle of the screen, the lowest at 'foot'. A row
-- is no wider than 'span': with more in it than fit at their full
-- width, they are drawn narrower. (They were one row, which ran under
-- the ship's own panel with five modules and off the screen with a
-- battleship's.)
local RACK_ROWS: { [string]: number } = { high = 1, mid = 2, low = 3, rig = 3 }
local function drawRack(session: Session.Session, game: Core.Game, ball: State.Ball, cx: number, foot: number, span: number)
  local fitted = Core.Query.Fitted(game, ball.id)
  if #fitted == 0 then
    return
  end
  local now = game.state.tick * Constants.TICK
  local gap, pitch = 6, 52
  -- (how many are in each row, and how many rows there are)
  local counts: { number } = { 0, 0, 0 }
  for _, item in fitted do
    counts[RACK_ROWS[item.place] or 3] += 1
  end
  local below: { number } = { 0, 0, 0 }
  for row = 2, 1, -1 do
    below[row] = below[row + 1] + (if counts[row + 1] > 0 then 1 else 0)
  end
  local placed: { number } = { 0, 0, 0 }
  for index, item in fitted do
    local module = Modules.byId[item.type]
    local row = RACK_ROWS[item.place] or 3
    local width = math.min(128, math.floor((span + gap) / counts[row]) - gap)
    local letters = math.max(6, math.floor((width - 16) / 6.2))
    local bx = cx - (counts[row] * (width + gap) - gap) / 2 + placed[row] * (width + gap)
    placed[row] += 1
    local y = foot - below[row] * pitch
    local running: State.Running? = nil
    for _, r in ball.vitals.running do
      if r.item == item.id then
        running = r
      end
    end
    local active = module.weapon ~= nil or module.repair ~= nil or module.boost ~= nil or module.miner ~= nil
      or module.hex ~= nil or module.salvager ~= nil
    Im.Panel(bx, y, width, 46)
    local hot, clicked = Im.Row(bx, y, width, 46, running ~= nil)
    -- (and by its key: F1 for the first of the rack, until a person says otherwise)
    local key = Keys.Rack(index)
    if key and active then
      Im.TextRight(Keys.Of(key), bx + width - 6, y + 5, 11, Im.DIM)
      clicked = Keys.Did(key) or clicked
    end
    Im.Text(shorten(module.short or module.name, letters - (if key and active then 2 else 0)), bx + 8, y + 5, 13,
      if active then Im.TEXT else Im.DIM)
    local note = if not active then "passive" else ""
    if module.weapon then
      note = if item.charge == "" then "empty"
        elseif module.weapon.clip > 0 then `{item.rounds} rounds`
        else shorten(Types.Info(item.charge).name, letters)
    end
    if module.miner then
      note = if running then "mining" else "idle"
    end
    if module.hex then
      note = if not running then "idle" elseif Modules.Mends(module) then "mending"
        elseif module.hex.kind == "capacitor" then "feeding" else "holding"
    end
    if module.salvager then
      note = if running then "salvaging" else "idle"
    end
    if module.cloak then
      note = if running then "cloaked" else "idle"
    end
    if running then
      local duration = if module.weapon then module.weapon.duration
        elseif module.repair then module.repair.duration
        elseif module.miner then module.miner.duration
        elseif module.hex then module.hex.duration
        elseif module.salvager then module.salvager.duration
        else module.boostDuration or 1
      bar(bx + 8, y + 38, width - 16, 3, duration - math.max(0, running.next - now), duration, Im.ACCENT)
      if running.stopping then
        note = "stopping"
      end
    end
    Im.Text(note, bx + 8, y + 22, 12, Im.DIM)
    if clicked and active then
      if running then
        Session.Do(session, { kind = "DeactivateModule", actor = 0, item = item.id })
      elseif module.salvager then
        -- (on the wreck that is selected: a wreck needs no lock)
        Session.Do(session, { kind = "ActivateModule", actor = 0, item = item.id, target = session.selected })
      elseif module.weapon or module.miner or module.hex then
        -- (at the pilot's target: aimOf)
        Session.Do(session, { kind = "ActivateModule", actor = 0, item = item.id, target = aimOf(session, ball) })
      else
        Session.Do(session, { kind = "ActivateModule", actor = 0, item = item.id })
      end
    end
    local _ = hot
  end
end

local function drawNavigation(session: Session.Session, ball: State.Ball, x: number, y: number, width: number)
  local game = session.game
  Im.Panel(x, y, width, 66)
  local speed = math.sqrt(ball.vx ^ 2 + ball.vy ^ 2 + ball.vz ^ 2)
  Im.Heading(Format.Speed(speed), x + 14, y + 8, 26, Im.TEXT)
  Im.Text(describe(game, ball), x + 14, y + 40, 15, Im.ACCENT)
  -- how much of its top speed, as a bar
  bar(x + 150, y + 22, 150, 4, speed, ball.maxVelocity, Im.ACCENT)
  -- (and what somebody else is doing about either: Tactical/Combat)
  if ball.vitals.scrambled then
    Im.Text("WARP SCRAMBLED", x + 310, y + 44, 13, HULL)
  end
  if ball.vitals.entangle < 1 then
    Im.Text("ENTANGLED", x + 310, y + 28, 13, HULL)
  end
  if ball.vitals.paint > 1 or ball.vitals.damp < 1 then
    Im.Text(if ball.vitals.damp < 1 then "DAMPENED" else "PAINTED", x + 310, y + 12, 13, Im.WARN)
  end
  -- (and whether anybody can see the ship at all)
  if Core.Query.Cloaked(game, ball.id) then
    -- (up against the buttons, and not under them)
    Im.TextRight("CLOAKED", x + width - 104, y + 12, 13, Im.ACCENT)
  else
    -- (or only from close in: in a cloud of gas. Said over the panel, where there is room for it)
    local veiled, sight = Core.Query.Veiled(game, ball.id)
    if veiled then
      Im.Text(`IN VAPOUR: nothing locks you from beyond {Format.Distance(sight)}, nor you it`, x + 14, y - 20, 13, Im.ACCENT)
    end
  end
  local inWarp = ball.warp ~= nil and ball.warp.stage == "warp"
  local stop = Keys.Did("stop") and not inWarp
  if Im.Button("STOP", x + width - 92, y + 8, 80, 24, not inWarp) or stop then
    Session.Order(session, "Stop")
  end
  -- (and a hull with a cloak of its own has it here, on and off: there
  -- is no module of it in the rack. Tactical/Combat)
  local has, on = Core.Query.OwnCloak(game, ball.id)
  if has then
    local key = Keys.Did("cloak") and not inWarp
    if Im.Button(if on then "UNCLOAK" else "CLOAK", x + width - 92, y + 36, 80, 24, not inWarp, "Cloak") or key then
      Session.Do(session, { kind = if on then "Uncloak" else "Cloak", actor = 0 })
    end
  end
end

local function drawClock(session: Session.Session, x: number, y: number)
  local clock = session.clock
  Im.Panel(x, y, 214, 34)
  if Im.Button("-", x + 6, y + 5, 28, 24, clock.scale > 1, "Clock:slower") then
    clock.scale = math.max(1, clock.scale / 2)
  end
  Im.Text(if clock.paused then "paused" else `time x{clock.scale}`, x + 44, y + 9, 14, if clock.paused then Im.WARN else Im.TEXT)
  -- (time is run faster only at a station)
  local docked = Core.Query.Player(session.game).docked ~= 0
  if Im.Button("+", x + 118, y + 5, 28, 24, docked and clock.scale < 16, "Clock:faster") then
    clock.scale = math.min(16, clock.scale * 2)
    clock.forced = false
  end
  if Im.Button(if clock.paused then "run" else "pause", x + 152, y + 5, 56, 24, true) then
    clock.paused = not clock.paused
  end
end

-- ---------------------------------------------------------------------

-- The docked screen and the star map are windows (Game/UI/Windows) that
-- draw themselves as they did when they were panels: each is moved by
-- its heading, where there is nothing to press, and by a strip along
-- its top. What they draw with is set down each frame, before the
-- windows are drawn.
local dockedAs: { session: Session.Session, game: Core.Game, player: Core.PlayerInfo, preview: any, show: any }? = nil
local mapOf: Session.Session? = nil
Windows.Kind("station", function(_: Windows.Window, x: number, y: number)
  local now = dockedAs
  if now then
    Station.Draw(now.session, now.game, now.player, x, y, now.preview, now.show)
  end
end)
Windows.Screen("station", "station", Station.WIDTH, Station.HEIGHT, { { 0, 0, 356, 34 }, { 0, 0, Station.WIDTH, 10 } })
Windows.Kind("map", function(_: Windows.Window, x: number, y: number, w: number, h: number)
  if mapOf then
    Map.DrawAt(mapOf, x, y, w, h)
  end
end)
Windows.Screen("map", "map", 1400, 820, { { 0, 0, 232, 40 }, { 0, 0, 1400, 6 } })

function Hud.Create(session: Session.Session, scene: Scene.Scene): Widget
  -- Expanded, so that it covers the window: a bare widget has no size.
  return Components.Expand(Widget_Luau(Widget_Create(), {
    PostDraw = function(_, w: Widget)
      local wasOver = overInterface
      Im.Begin()
      -- The splash is over everything while it is up: nothing behind it
      -- is drawn (or pressed) until its black begins to clear.
      if Splash.Hides() then
        Splash.Draw(w.pos.x, w.pos.y, w.size.x, w.size.y, math.min(0.1, FrameTimer_Get()))
        overInterface = true
        return
      end
      -- A menu is all there is while it is up.
      if Menu.IsOpen() then
        Menu.Draw(session, w.pos.x, w.pos.y, w.size.x, w.size.y)
        Splash.Draw(w.pos.x, w.pos.y, w.size.x, w.size.y, math.min(0.1, FrameTimer_Get()))
        overInterface = true
        return
      end
      local game = session.game
      local player = Core.Query.Player(game)
      local ball = Core.Query.Ball(game, player.ship)
      local entries = Core.Query.Overview(game)
      local left, top = w.pos.x, w.pos.y
      local right, bottom = left + w.size.x, top + w.size.y
      -- (the map is a window, in the middle of the screen until it is put
      -- somewhere: open when the map is)
      mapOf = session
      Windows.Default("map", Map.Covers(left, top, w.size.x, w.size.y))
      if Map.IsOpen() ~= Windows.IsOpen("map") then
        if Map.IsOpen() then
          Windows.Open("map")
        else
          Windows.Close("map")
        end
      end
      -- (and the windows go over what is drawn before them: Game/UI/Windows)
      Inventory.Frame(session, player.docked ~= 0)
      Assets.Frame(session)
      Events.Frame(session)
      Windows.Begin(left, top, right, bottom)

      -- Through a gate the view whites out, under everything written on it.
      if scene.veil > 0 then
        Im.Fill(left, top, w.size.x, w.size.y, VEIL, math.min(1, scene.veil))
      end
      -- And in a cloud of gas it is hazed, a little: it comes on and
      -- goes off over a second or so. (A grey box of being in a cloud.)
      local veiled = ball ~= nil and (Core.Query.Veiled(game, ball.id))
      haze += ((if veiled then 1 else 0) - haze) * 0.05
      if haze > 0.01 then
        -- (a fill's alpha is not linear: this is about a tenth of the way to the haze's colour)
        Im.Fill(left, top, w.size.x, w.size.y, HAZE, 0.36 * haze)
      end

      -- (with a right click's menu up, a click is the menu's: Context.Draw)
      if Context.IsOpen() then
        if ball then
          Im.Hold()
        else
          Context.Close()
        end
      end

      -- Brackets and shots go under the panels and use last frame's
      -- answer to "is the cursor over a panel".
      overInterface = wasOver
      local marks = Waypoints.Of(session)
      if ball then
        drawBrackets(session, scene, entries, w, ball, marks)
      end

      -- Where we are and what we have.
      Im.Heading(string.upper(player.systemName), left + 24, top + 18, 30, Im.TEXT)
      -- (and where that is: its constellation and its region)
      -- (uncharted space is all one: Core/Describe/Galaxy)
      Im.Text(if player.uncharted then player.region else `{player.constellation}, {player.region}`,
        left + 24 + Im.HeadingWidth(string.upper(player.systemName), 30) + 16, top + 30, 13, Im.DIM)
      -- (how safe it is here: what comes to a belt follows from it)
      local _, band = Core.Query.Security(game, player.system)
      local whose = if player.owner ~= "" then string.upper(player.owner) else "UNCLAIMED"
      local standing = string.format("%s  -  %s  %.1f", whose, BANDS[band or "secure"], player.security)
      -- (off the map: nobody's, and how deep in it lies says what lives there)
      if player.uncharted then
        standing = `ON NO MAP  -  DEPTH {player.depth} OF {player.depths}`
      end
      Im.Text(standing, left + 24, top + 51, 13, if band == "secure" then SAFE elseif band == "low" then Im.WARN else HULL)
      -- (and whether somebody's fleet has its lanes shut: Core/Strategic/Wars)
      local blockading, why = Core.Query.Blockade(game)
      if blockading then
        Im.Text(`BLOCKADED by the {blockading}: {if why == "siege" then "a siege" else "they are claiming it"}. Little comes in or goes out`,
          left + 24, top + 107 + 20, 13, Im.WARN)
      end
      -- (and whether pirates are massing here: Tactical/Surges)
      local surge = Core.Query.Surge(game)
      if surge and surge.system == player.system then
        Im.Text(`PIRATE SURGE  bounties doubled, {Format.Duration(surge.left)} left`, left + 24 + Im.TextWidth(standing, 13) + 16, top + 51, 13,
          HULL)
      end
      Im.Text(`{player.shipName}  -  {player.hull.name}`, left + 24, top + 68, 15, Im.DIM)
      Im.Text(`{game.state.wallet} credits`, left + 24, top + 87, 15, Im.DIM)
      if session.message ~= "" and game.state.tick - session.messageTick < 10 then
        Im.Text(session.message, left + 24, top + 107, 16, Im.WARN)
      end
      -- The guide: what there is to do, and how much of it is done. Its
      -- window takes the place the colonies and assets windows take.
      local steps, guided = Core.Query.Guide(game)
      if Im.Button(`Guide  {guided} / {#steps}`, left + 300, top + 60, 118, 28, true, "Guide") then
        if Guide.IsOpen() then
          Guide.Close()
        else
          Guide.Open()
          Colony.Close()
          Scanner.Close()
        end
      end

      if scene.warp > 0 and ball and ball.warp then
        local target = Core.Query.Body(game, ball.warp.target)
        local cx = left + w.size.x / 2
        Im.Heading("WARP DRIVE ACTIVE", cx - 118, top + 120, 26, Im.ACCENT)
        local line = `{if target then target.name else "?"}   {Format.Distance(scene.warpLeft)}   {math.ceil(scene.warpSeconds)} s`
        Im.Text(line, cx - Im.TextWidth(line, 16) / 2, top + 154, 16, Im.TEXT)
      end

      local panelWidth = 372
      local panelX = right - panelWidth - 16
      if ball then
        local navX = left + (w.size.x - 520) / 2
        -- (beside the Guide button, not over it)
        drawTargets(session, game, ball, left + 430, top + 20)
        -- A key (Tab) picks out the next ship that would fire on the pilot,
        -- nearest first and round again.
        if Keys.Did("next") then
          local first, after, passed = 0, 0, false
          for _, entry in entries do
            if entry.hostile and entry.onGrid then
              first = if first == 0 then entry.id else first
              after = if passed and after == 0 then entry.id else after
            end
            passed = passed or entry.id == session.selected
          end
          if first ~= 0 then
            session.selected = if after ~= 0 then after else first
          end
        end
        -- A key (C) has the camera follow what is selected, and again lets it go.
        if Keys.Did("camera") then
          Scene.Track(scene, if scene.tracking == session.selected then 0 else session.selected)
        end
        -- (and it follows the pilot's target, with no key)
        Session.Aim(session)
        followTarget(session, scene, game)
        if scene.tracking ~= 0 then
          -- (what it is on, where that is not what is picked out, whose panel this is over)
          local on = if scene.tracking == session.selected then nil else Core.Query.Body(game, scene.tracking)
          Im.TextRight(if on then `camera following {on.name} ({Keys.Of("camera")})` else `camera following ({Keys.Of("camera")})`,
            panelX + panelWidth - 12, top + 2, 11, Im.ACCENT)
        end
        drawSelected(session, entries, ball, panelX, top + 16, panelWidth)
        drawOverview(session, entries, panelX, top + 182, panelWidth, math.min(600, bottom - top - 272), marks)
        -- (over the ship's own panel, and no wider than leaves the drones'
        -- row and the fleet's panel, which end 464 px in, clear)
        drawRack(session, game, ball, left + w.size.x / 2, bottom - 172, math.max(400, w.size.x - 2 * 476))
        drawNavigation(session, ball, navX, bottom - 86, 520)
        drawStatus(game, ball, navX - 232, bottom - 120)
      else
        -- The docked screen is a window (Game/UI/Windows): in the middle
        -- until it is put somewhere, moved by its heading, and drawn
        -- with the other windows, below.
        -- (the ship on the fitting screen is a thing of the scene, drawn as the scene draws: Scene.Showcase)
        Windows.Default("station", left + (w.size.x - Station.WIDTH) / 2, top + 130)
        dockedAs = { session = session, game = game, player = player,
          preview = Scene.Dressed(game, player.ship, player.hull.id, player.hull.radius),
          show = function(cx: number, cy: number, round: number): boolean
            return Scene.Showcase(scene, game, player.ship, player.hull.id, player.hull.radius, cx, cy, round)
          end }
        if not Windows.IsOpen("station") then
          Windows.Open("station")
        end
        local stationAt = Windows.Get("station")
        if stationAt then
          Info.Draw(stationAt.x + Station.WIDTH + 12, stationAt.y)
        end
      end
      if ball and Windows.IsOpen("station") then
        Windows.Close("station")
      end
      -- (beside the ship's own panels in space, and in the same place docked)
      drawBoosters(session, left + (w.size.x - 520) / 2 + 532, bottom - 20)
      drawClock(session, left + 24, bottom - 54)
      -- Colonies are run from anywhere, in space or docked, and what
      -- the pilot owns can be looked over from anywhere. The two windows
      -- take the same place: opening one closes the other.
      -- (these end short of the ship's own panel, which in space begins
      -- 468 px in on a screen 1920 wide)
      if Im.Button("Colonies", left + 246, bottom - 54, 84, 34, true) then
        if Colony.IsOpen() then
          Colony.Close()
        else
          Colony.Open()
          Scanner.Close()
          Guide.Close()
        end
      end
      -- What is in reach, and the moving of it: a window that goes where
      -- it is put (Game/UI/Inventory). Everything the pilot owns
      -- anywhere, the assets window, is opened from it.
      if Im.Button("Inventory", left + 334, bottom - 54, 84, 34, true) or (Keys.Did("inventory") and not Im.Typing()) then
        if Inventory.IsOpen() then
          Inventory.Close()
        else
          Inventory.Open()
        end
      end
      if Inventory.WantsAssets() then
        -- (a window of its own, which goes where it is put: Game/UI/Assets)
        if Assets.IsOpen() then
          Assets.Close()
        else
          Assets.Open()
        end
      end
      if Im.Button("Map", left + 422, bottom - 54, 42, 34, true) or Keys.Did("map") then
        if Map.IsOpen() then
          Map.Close()
        else
          Map.Open()
        end
      end
      -- (what is going on in the galaxy: a window of its own, Game/UI/Events)
      if Im.Button("Events", left + 468, bottom - 54, 64, 34, true) then
        if Events.IsOpen() then
          Events.Close()
        else
          Events.Open()
        end
      end
      Colony.Draw(session, left + 16, top + 130)
      Guide.Draw(session, left + 16, top + 130)
      if ball then
        Scanner.Draw(session, left + 16, top + 130, scene.camera:GetLook())
        -- (a hack under way has the middle of the screen)
        Hack.Draw(session, left + (w.size.x - Hack.WIDTH) / 2, top + 150)
      end
      -- Where the pilot means to go, and the autopilot's switch: a row
      -- of its own over the buttons at the foot of the screen (beside
      -- them is the ship's own panel, in space), whatever else is open.
      if session.destination ~= 0 then
        local route = Session.Route(session)
        local name = game.state.galaxy.systems[session.destination].name
        Im.Panel(left + 24, bottom - 96, 440, 34)
        Im.Text(`To {name}: {math.max(0, #route - 1)} {if #route == 2 then "jump" else "jumps"}`, left + 36, bottom - 87, 14, Im.ACCENT)
        if Im.Toggle(if session.autopilot then "Autopilot on" else "Autopilot", left + 338, bottom - 93, 120, 28, session.autopilot,
          "Autopilot") then
          session.autopilot = not session.autopilot
        end
      end
      -- The drones, if there are any aboard or out: a row over that.
      if ball then
        local drones = Core.Query.Drones(game)
        if drones.carried + drones.out > 0 then
          local dy = bottom - 138
          Im.Panel(left + 24, dy, 440, 34)
          Im.Text(`DRONES  {drones.out} out, {drones.carried} aboard`, left + 36, dy + 9, 13,
            if drones.out > 0 then Im.TEXT else Im.DIM)
          if Im.Button("Launch", left + 226, dy + 4, 70, 26, (Session.CanDo(session, { kind = "LaunchDrones", actor = 0 })),
            "Drones:launch") then
            Session.Do(session, { kind = "LaunchDrones", actor = 0 })
          end
          -- (at what is selected, if it is a ship, or a rock for the mining
          -- drones; else at the first thing locked)
          local target = session.selected
          local picked = Core.Query.Body(game, target)
          if game.state.balls[target] == nil and not (picked and picked.kind == "asteroid") then
            target = 0
            for _, lock in ball.vitals.locks do
              if lock.locked and game.state.balls[lock.target] then
                target = lock.target
                break
              end
            end
          end
          local engage: State.Command = { kind = "EngageDrones", actor = 0, target = target }
          if Im.Button("Engage", left + 300, dy + 4, 76, 26, (Session.CanDo(session, engage)), "Drones:engage") then
            Session.Do(session, engage)
          end
          if Im.Button("Recall", left + 380, dy + 4, 76, 26, (Session.CanDo(session, { kind = "RecallDrones", actor = 0 })),
            "Drones:recall") then
            Session.Do(session, { kind = "RecallDrones", actor = 0 })
          end
        end
      end
      -- The hired pilots, if there are any: who, in what, where, and how
      -- their ships are holding up. Over the drones' row.
      local fleet = Core.Query.Fleet(game)
      if #fleet > 0 then
        local fy = bottom - 210 - 22 * #fleet
        Im.Panel(left + 24, fy, 440, 64 + 22 * #fleet)
        -- An order is for everybody, or for the one pilot whose row has
        -- been picked out by a click (and a click again lets them go).
        local one: Core.FleetRow? = nil
        for _, row in fleet do
          if row.id == fleetPicked then
            one = row
          end
        end
        local only: number? = if one then one.id else nil
        fleetPicked = if one then one.id else 0
        Im.Text(if one then "ONE PILOT" else `FLEET  {#fleet}`, left + 36, fy + 9, 13, if one then Im.ACCENT else Im.TEXT)
        -- (at what is selected, if it is a ship. else at the first thing locked)
        local target = session.selected
        if game.state.balls[target] == nil then
          target = 0
          if ball then
            for _, lock in ball.vitals.locks do
              if lock.locked and game.state.balls[lock.target] then
                target = lock.target
                break
              end
            end
          end
        end
        local engage: State.Command = { kind = "FleetOrder", actor = 0, what = "engage", target = target, pilot = only }
        if Im.Button("Engage", left + 150, fy + 4, 70, 26, (Session.CanDo(session, engage)), "Fleet:engage") then
          Session.Do(session, engage)
        end
        local staying = (if one then one.order else fleet[1].order) == "stay"
        if Im.Button("Regroup", left + 224, fy + 4, 76, 26, true, "Fleet:follow") then
          Session.Do(session, { kind = "FleetOrder", actor = 0, what = "follow", pilot = only })
        end
        if Im.Toggle("Stay", left + 304, fy + 4, 60, 26, staying, "Fleet:stay") then
          Session.Do(session, { kind = "FleetOrder", actor = 0, what = if staying then "follow" else "stay", pilot = only })
        end
        -- (at a belt: those with a mining laser work it from now on)
        local mine: State.Command = { kind = "FleetOrder", actor = 0, what = "mine", pilot = only }
        if Im.Button("Mine here", left + 368, fy + 4, 88, 26, (Session.CanDo(session, mine)), "Fleet:mine") then
          Session.Do(session, mine)
        end
        -- A second row, of the orders for when the pilot is not there:
        -- those with a weapon hold this place; and the one picked out
        -- goes with another pilot, whose ship is what is selected.
        local hold: State.Command = { kind = "FleetOrder", actor = 0, what = "patrol", pilot = only }
        if Im.Button("Patrol here", left + 150, fy + 34, 104, 26, (Session.CanDo(session, hold)), "Fleet:patrol") then
          Session.Do(session, hold)
        end
        local guard: State.Command = { kind = "FleetOrder", actor = 0, what = "guard", pilot = only, target = session.selected }
        local canGuard, whyNotGuard = Session.CanDo(session, guard)
        if Im.Button("Guard", left + 258, fy + 34, 70, 26, canGuard, "Fleet:guard") then
          Session.Do(session, guard)
        end
        if one and not canGuard then
          Im.Text(if string.sub(tostring(whyNotGuard), 1, 4) == "pick" then "select another's ship" else "", left + 36, fy + 41, 11,
            Im.DIM)
        end
        -- (to what is selected, all together: those who follow form up on
        -- the pilot, and everybody goes at once and arrives at once)
        local canWarp = Session.Can(session, "FleetWarp", session.selected)
        if Im.Button("Warp fleet", left + 368, fy + 34, 88, 26, canWarp, "Fleet:warp") then
          Session.Order(session, "FleetWarp", session.selected)
        end
        for index, row in fleet do
          local ry = fy + 64 + (index - 1) * 22
          local hull = Ships.byId[row.hull]
          local _, clicked = Im.Row(left + 28, ry - 2, 432, 21, row.id == fleetPicked, `Fleet:pick:{index}`)
          if clicked then
            fleetPicked = if row.id == fleetPicked then 0 else row.id
          end
          Im.Text(row.name, left + 36, ry, 13, if row.near then OURS else Im.TEXT)
          local flying = if hull == nil then "no ship" elseif row.order == "mine" and row.near then `{hull.name}: {row.doing}` else hull.name
          Im.Text(if #flying > 20 then string.sub(flying, 1, 19) .. "." else flying, left + 180, ry, 12, Im.DIM)
          if row.near then
            -- shield, armour and hull, as three short bars
            for at, share in { row.shield, row.armor, row.structure } do
              local bx = left + 300 + (at - 1) * 34
              Im.Fill(bx, ry + 5, 30, 6, Im.DIM, 0.25)
              Im.Fill(bx, ry + 5, 30 * math.clamp(share, 0, 1), 6, if at == 1 then SHIELD elseif at == 2 then ARMOR else HULL, 0.95)
            end
            Im.TextRight(Format.Distance(row.distance), left + 456, ry, 12, Im.DIM)
          else
            -- (a pilot who should be here and is not, in the colour of a warning)
            local ship = game.state.ships[row.ship]
            local here = ship ~= nil and ship.docked ~= 0 and ship.docked == player.docked
            local where = if here then "docked here" else row.where
            -- (one set to mine is where they should be, wherever that is)
            if row.order == "mine" or row.order == "haul" then
              where = `{row.doing}, {row.hauled} units in`
            elseif row.order == "buy" or row.order == "stock" then
              where = `{row.doing}: {row.want}`
            elseif row.order == "patrol" then
              where = `{row.doing}: {row.post}`
            elseif row.order == "guard" then
              where = `{row.doing} {row.ward}`
            end
            -- (one who is gone for with the pilot somewhere else says so)
            if row.hunted then
              where = `under attack, {row.where}`
            end
            Im.TextRight(if #where > 34 then string.sub(where, 1, 32) .. ".." else where, left + 456, ry, 12,
              if row.hunted then Im.WARN elseif here or row.order ~= "follow" or row.ship == 0 then Im.DIM else Im.WARN)
          end
        end
      end
      -- The windows, over all of that: and over them the menu one of
      -- them has up, and whatever is being carried from one to another.
      Windows.Draw()
      Im.Overlay(right, bottom)
      -- The menu a right click brought up, over all of that.
      Context.Draw(session, entries, left, top, right, bottom)
      -- (and the last of the splash, clearing, where there was no menu under it)
      Splash.Draw(w.pos.x, w.pos.y, w.size.x, w.size.y, math.min(0.1, FrameTimer_Get()))
      Keys.EndFrame()
      overInterface = Im.over
    end,
  }))
end

return Hud
