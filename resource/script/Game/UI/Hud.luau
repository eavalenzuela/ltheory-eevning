--!strict
-- The interface. In space: brackets on everything in view, shots drawn
-- between ships, the overview, the selected item and its orders, locked
-- targets, the ship's condition, its module rack and the navigation bar.
-- Docked: the station's services, each a window of its own (Game/UI/Fitting and the rest).
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
local ContractsWindow = require("@lt/Game/UI/Contracts")
local Core = require("@lt/Core/Api")
local Dock = require("@lt/Game/UI/Dock")
local Fitting = require("@lt/Game/UI/Fitting")
local Format = require("@lt/Game/Format")
local Guide = require("@lt/Game/UI/Guide")
local Im = require("@lt/Game/UI/Im")
local IndustryWindow = require("@lt/Game/UI/Industry")
local Inventory = require("@lt/Game/UI/Inventory")
local JobsWindow = require("@lt/Game/UI/Jobs")
local Info = require("@lt/Game/UI/Info")
local ItemIcon = require("@lt/Game/UI/ItemIcon")
local Icons = require("@lt/Game/UI/Icons")
local Keys = require("@lt/Game/UI/Keys")
local List = require("@lt/Game/UI/List")
local Map = require("@lt/Game/UI/Map")
local Market = require("@lt/Game/UI/Market")
local Menu = require("@lt/Game/UI/Menu")
local Modules = require("@lt/Core/Data/Modules")
local Ores = require("@lt/Core/Data/Ores")
local Hack = require("@lt/Game/UI/Hack")
local Scanner = require("@lt/Game/UI/Scanner")
local Scene = require("@lt/Game/View/Scene")
local Session = require("@lt/Game/Session")
local Ships = require("@lt/Core/Data/Ships")
local ShipsWindow = require("@lt/Game/UI/Ships")
local Skills = require("@lt/Core/Data/Skills")
local SkillSheet = require("@lt/Game/UI/Skills")
local Splash = require("@lt/Game/UI/Splash")
local State = require("@lt/Core/Kernel/State")
local CrewWindow = require("@lt/Game/UI/Crew")
local SchoolWindow = require("@lt/Game/UI/School")
local StarbaseWindow = require("@lt/Game/UI/Starbase")
local WalletWindow = require("@lt/Game/UI/Wallet")
local CorporationWindow = require("@lt/Game/UI/Corporation")
local Theme = require("@lt/Game/UI/Theme")
local Waypoints = require("@lt/Game/Waypoints")
local Windows = require("@lt/Game/UI/Windows")
local Moons = require("@lt/Core/Data/Moons")
local Structures = require("@lt/Core/Data/Structures")
local Types = require("@lt/Core/Data/Types")

local Hud = {}

local overInterface = false
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

-- Where a body is on screen, in the interface's units, or nil if it is
-- behind the camera.
local function onScreen(scene: Scene.Scene, id: number): vector?
  local at = scene.screen[id]
  if at then
    local projected = Camera_Project(scene.camera, at)
    if projected.z > 0 then
      return Position_Frame(projected) / Theme.scale
    end
  end
  return nil
end

-- The window the interface is drawn in: where it is and how big, in the
-- interface's units.
type Area = { pos: vector, size: vector }

-- ---------------------------------------------------------------------
-- In space

local function drawBrackets(session: Session.Session, scene: Scene.Scene, entries: { Core.Entry }, w: Area,
  ball: State.Ball?, marks: Waypoints.Marks)
  local cursor = Im.Cursor()
  -- (a sign in space is drawn by the engine, in pixels: where it is and how big)
  local scale = Theme.scale
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
      Icon_Draw(icon(entry.kind), p * scale, (if small then 4 else 8) * scale, color, if selected or hot or goal then 1 else 0.7)
      if goal then
        Glyph_Draw(Glyph_Ring(p * scale, 12 * scale, 1, 1, 0), 0, 1, NEXT, 0.8)
      end
      if lock then
        -- a ring round a target: closing while it locks, steady once locked
        Glyph_Draw(Glyph_Ring(p * scale, (if lock.locked then 14 else 20) * scale, 1, 1, 0), 0, 1, Colors.White, if lock.locked then 0.9 else 0.5)
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
      local ray = Camera_GetRay(scene.camera, cursor * scale)
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

-- What a thing on the overview is, for its row: a ship says its class,
-- a battery that it is one; and the sign that stands for it (Game/UI/Icons).
local CLASS_NAMES: { [string]: string } = { frigate = "Frigate", destroyer = "Destroyer", cruiser = "Cruiser",
  attackbattlecruiser = "Battlecruiser", battlecruiser = "Battlecruiser", battleship = "Battleship", carrier = "Carrier",
  siegedreadnought = "Dreadnought", dreadnought = "Dreadnought", supercarrier = "Supercarrier", ultracapital = "Ultracapital",
  industrial = "Industrial", capitalindustrial = "Industrial", freighter = "Freighter", barge = "Barge", capsule = "Capsule",
  drone = "Drone" }
local KIND_NAMES: { [string]: string } = { sun = "Sun", planet = "Planet", moon = "Moon", belt = "Belt", asteroid = "Asteroid",
  station = "Station", gate = "Gate", wreck = "Wreck", site = "Site", bookmark = "Marked" }
local KIND_SIGNS: { [string]: string } = { sun = "sun", planet = "planet", moon = "moon", belt = "belt", asteroid = "rock",
  station = "station", gate = "gate", wreck = "wreck", site = "site", bookmark = "mark" }

-- Whether a ship of the overview is a drone, or a battery of a station's or a tower's.
local function droneOf(entry: Core.Entry): boolean
  return entry.kind == "ship" and string.sub(entry.variety, 1, 6) == "drone."
end

local function batteryOf(entry: Core.Entry): boolean
  return entry.kind == "ship" and string.sub(entry.variety, 1, 6) == "works."
end

local function typeOf(entry: Core.Entry): string
  if entry.kind == "ship" then
    if batteryOf(entry) then
      return if string.find(entry.variety, "battery", 1, true) then "Battery" else "Structure"
    end
    local hull = Ships.byId[entry.variety]
    return if hull then CLASS_NAMES[hull.class] or "Ship" else "Ship"
  end
  return if cloudy(entry) then "Gas cloud" elseif vaulted(entry) then "Vault" else KIND_NAMES[entry.kind] or "?"
end

local function signOf(entry: Core.Entry): string
  if entry.kind == "ship" then
    return if droneOf(entry) then "drone" elseif batteryOf(entry) then "battery" else "ships"
  end
  return if cloudy(entry) then "cloud" else KIND_SIGNS[entry.kind] or "site"
end

-- The overview's presets (the owner's, 2026-11-15: "Default, Combat,
-- Mining, Exploration, Travel, Salvaging", and of what each lists, "All
-- of them should also show ships"): what each lists beside the ships,
-- and how the foot says so. Drones and batteries are of the fight, and
-- are on Combat's alone.
local PRESETS: { { string } } = {
  { "default", "Default", "ships, stations, gates, belts, wrecks, sites, marks" },
  { "combat", "Combat", "ships, drones, batteries" },
  { "mining", "Mining", "ships, rocks, gas, belts, stations" },
  { "exploration", "Exploration", "ships, sites, wormholes, wrecks, marks" },
  { "travel", "Travel", "ships, stations, gates, planets, moons, belts" },
  { "salvaging", "Salvaging", "ships, wrecks, containers" },
}
local PRESET_KINDS: { [string]: { [string]: boolean } } = {
  default = { station = true, gate = true, belt = true, wreck = true, site = true, bookmark = true },
  combat = {},
  mining = { asteroid = true, belt = true, station = true },
  exploration = { site = true, wreck = true, bookmark = true },
  travel = { station = true, gate = true, planet = true, moon = true, belt = true, bookmark = true, sun = true },
  salvaging = { wreck = true },
}
local overviewPreset = "default"

local function inPreset(entry: Core.Entry): boolean
  if entry.kind == "ship" then
    return overviewPreset == "combat" or not (droneOf(entry) or batteryOf(entry))
  end
  return PRESET_KINDS[overviewPreset][entry.kind] == true
end

-- The overview as it is listed: what the Core gives (nearest first),
-- narrowed to what the preset lists, and put in the order the pilot has
-- asked for, by a column; with where the pilot is next to go first,
-- whatever the order (the gate of the way they have planned, the place
-- a job is done or paid). What the pilot is next to go to, has picked
-- out or has locked is listed whatever the preset ('kept').
local function listed(all: { Core.Entry }, marks: Waypoints.Marks, kept: { [number]: boolean }): { Core.Entry }
  local shown: { Core.Entry } = {}
  for _, entry in all do
    if inPreset(entry) or marks[entry.id] or kept[entry.id] then
      table.insert(shown, entry)
    end
  end
  local sorted = shown
  if overviewSort ~= "distance" or overviewDown then
    -- (each with its place as the Core gave it: what is alike by the column stays nearest first)
    local order: { { entry: Core.Entry, key: string, at: number } } = {}
    for at, entry in shown do
      table.insert(order, { entry = entry, at = at,
        key = if overviewSort == "name" then string.lower(entry.name) elseif overviewSort == "type" then typeOf(entry) else "" })
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

-- What is listed whatever the preset: what is picked out, and what the
-- ship has locked or is locking.
local function keptOf(session: Session.Session): { [number]: boolean }
  local kept: { [number]: boolean } = { [session.selected] = true }
  local ball = Core.Query.Ball(session.game, Core.Query.Player(session.game).ship)
  if ball then
    for _, lock in ball.vitals.locks do
      kept[lock.target] = true
    end
  end
  return kept
end

-- How the overview is listed, and (given a column) a way to say so:
-- the column it is listed by, and whether the other way round. Asking
-- for the column it is already listed by turns it round.
function Hud.Sort(by: string?): (string, boolean)
  if by == "distance" or by == "name" or by == "type" then
    overviewDown = if by == overviewSort then not overviewDown else false
    overviewSort = by
    Im.ScrollTo("overview", 0)
  end
  return overviewSort, overviewDown
end

-- Which preset the overview is on ("default", "combat", "mining",
-- "exploration", "travel", "salvaging"): and, given one, that one.
function Hud.Preset(to: string?): string
  if to and PRESET_KINDS[to] then
    overviewPreset = to
    Im.ScrollTo("overview", 0)
  end
  return overviewPreset
end

-- The names on the overview as it is listed, top first: for a script.
function Hud.Listed(session: Session.Session): { string }
  local names: { string } = {}
  for _, entry in listed(Core.Query.Overview(session.game), Waypoints.Of(session), keptOf(session)) do
    table.insert(names, entry.name)
  end
  return names
end

-- The overview, on the one list (Game/UI/List): a preset to a tab, a
-- sign for what a thing is, its name in the colour of what it is to the
-- pilot (hostile, theirs, where they are going), its kind, how far off
-- it is and, for a ship, how fast it is going. (A script's names:
-- "Overview:sort:<column>", "Overview:preset:<preset>", and "Bookmark"
-- and "Scanner" as before.)
local OVERVIEW_COLUMNS: { List.Column } = {
  { id = "sign", label = "", width = 16, sort = false }, { id = "name", label = "Name", width = 0 },
  { id = "type", label = "Type", width = 76 }, { id = "distance", label = "Distance", width = 66, right = true },
  { id = "speed", label = "m/s", width = 38, right = true, sort = false },
}
local function drawOverview(session: Session.Session, all: { Core.Entry }, x: number, y: number, width: number, height: number,
  marks: Waypoints.Marks)
  local game = session.game
  local entries = listed(all, marks, keptOf(session))
  local here = Core.Query.Player(game).systemName
  Im.Frame(x, y, width, height)
  local was = Im.Plain(true)
  Im.Heading("OVERVIEW", x + 12, y + 9, 16, Theme.DIM)
  -- (the marking of where the ship is, to warp back to: it is on the
  -- overview from then on, in this system; and the ship's scanner, for
  -- what is on nobody's chart)
  local mark: State.Command = { kind = "Bookmark", actor = 0 }
  Im.Because("Not here")
  if Im.Button("Mark here", x + width - 156, y + 6, 78, 22, (Session.CanDo(session, mark)), "Bookmark") then
    Session.Do(session, mark)
  end
  if Im.Button("Scan", x + width - 72, y + 6, 62, 22, true, "Scanner") then
    if Scanner.IsOpen() then
      Scanner.Close()
    else
      Scanner.Open()
    end
  end
  -- The presets.
  local tx = x + 6
  for _, preset in PRESETS do
    local wide = Im.StrongWidth(preset[2], 13) + 14
    local on = overviewPreset == preset[1]
    local hot, pressed = Im.Area(`Overview:preset:{preset[1]}`, tx, y + 34, wide, 26, true)
    if on then
      Im.Flat(tx, y + 34, wide, 26, Theme.ACCENT, 0.07)
      Im.Flat(tx, y + 58, wide, 2, Theme.ACCENT)
    elseif hot then
      Im.Flat(tx, y + 34, wide, 26, Theme.TEXT, 0.04)
    end
    Im.Strong(preset[2], tx + 7, y + 40, 13, if on or hot then Theme.TEXT else Theme.DIM)
    if pressed then
      Hud.Preset(preset[1])
    end
    tx += wide
  end
  Im.Flat(x + 1, y + 60, width - 2, 1, Theme.EDGE)
  -- The columns' heads: a click lists by that column, and another turns
  -- it round. The one it is listed by says which way.
  local layout = List.Columns(OVERVIEW_COLUMNS, x, width - 6)
  local clicked = List.Head("Overview", x + 1, y + 61, width - 2, OVERVIEW_COLUMNS, layout, overviewSort, overviewDown)
  if clicked then
    Hud.Sort(clicked)
  end
  local top = y + 61 + List.HEAD
  local room = height - 61 - List.HEAD - List.FOOT
  local first, visible = List.Body("overview", x + 1, top, width - 2, room, #entries)
  for row = 1, visible do
    local entry = entries[row + first]
    if entry == nil then
      break
    end
    local rowY = top + (row - 1) * List.ROW
    local hot, picked, double = List.Row(x + 1, rowY, width - 7, entry.id == session.selected)
    if hot and Im.RightPressed() then
      session.selected = entry.id
      Context.Open(entry.id, Im.Cursor().x, Im.Cursor().y)
    end
    local goal = marks[entry.id] ~= nil
    local color = if entry.hostile then Theme.BAD elseif goal then Theme.CAUTION elseif entry.own then Theme.GOOD
      elseif entry.onGrid then Theme.TEXT else Theme.DIM
    if goal or entry.hostile or entry.own then
      Im.Flat(x + 1, rowY + 3, 3, List.ROW - 6, color)
    end
    Icons.Draw(signOf(entry), layout.sign.x + 8, rowY + 12, 6,
      if entry.hostile or goal or entry.own then color elseif entry.kind == "ship" and not batteryOf(entry) then Theme.SHIELD else Theme.DIM,
      if entry.onGrid then 1 else 0.7)
    -- (a place of this system is called by what is its own: "III - Moon 2
    -- - Refinery 1", where every row would begin with the system's name)
    local name = entry.name
    if entry.kind ~= "ship" and string.sub(name, 1, #here + 1) == here .. " " and #name - #here > 5 then
      name = string.sub(name, #here + 2)
    end
    List.Text(name, layout.name, rowY, hot, color, 14, false, 0, if name ~= entry.name then entry.name else nil)
    -- (a ship in a cloud of gas says so, where its kind would be: it is locked only from close in)
    List.Text(if entry.veiled then "in vapour" else typeOf(entry), layout.type, rowY, false, if entry.veiled then Theme.ACCENT else Theme.DIM, 13)
    List.Text(Format.Distance(entry.distance), layout.distance, rowY, false, color)
    local other = if entry.kind == "ship" and entry.onGrid and not batteryOf(entry) then Core.Query.Ball(game, entry.id) else nil
    List.Text(if other then tostring(math.floor(math.sqrt(other.vx ^ 2 + other.vy ^ 2 + other.vz ^ 2) + 0.5)) else "-", layout.speed, rowY, false,
      if other then Theme.DIM else Theme.FAINT, 13)
    if picked then
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
  local says = ""
  for _, preset in PRESETS do
    if preset[1] == overviewPreset then
      says = preset[3]
    end
  end
  List.Foot(x + 1, y + height - List.FOOT, width - 2, `{#entries} of {#all} here`, says)
  Im.Plain(was)
end

-- The hired pilot the fleet's orders are for (by their id), or 0: everybody.
local fleetPicked = 0
-- Whether the fleet's orders are dropped down, and where (drawn last, over the rest).
local fleetMenu = false
local menuAt: any = nil

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
  Im.Frame(x, y, width, 158)
  if selected == nil then
    Im.Heading("NOTHING SELECTED", x + 12, y + 9, 16, Theme.DIM)
    Im.Text("Click a bracket or a row of the overview.", x + 12, y + 36, 14, Theme.DIM)
    return
  end
  local entry: Core.Entry = selected
  local was = Im.Plain(true)
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
    local name = List.Cut(entry.name, width - 110, 17, true)
    Im.Strong(name, x + 12, y + 7, 17, Theme.TEXT)
    -- (and what it is to the pilot)
    if entry.hostile or entry.own then
      Im.Pill(if entry.hostile then "HOSTILE" else "YOURS", x + 12 + Im.StrongWidth(name, 17) + 8, y + 9, if entry.hostile then Theme.BAD else Theme.GOOD)
    end
  end
  local what = if entry.kind == "ship" then string.lower(typeOf(entry)) elseif entry.variety ~= "" then `{entry.variety} {entry.kind}` else entry.kind
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
  local far = Format.Distance(entry.distance)
  Im.Text(List.Cut(what, width - 36 - Im.StrongWidth(far, 14), 14, false), x + 12, y + 32, 14, tone)
  Im.Strong(far, x + width - 12 - Im.StrongWidth(far, 14), y + 32, 14, Theme.TEXT)

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
  elseif entry.kind == "ship" and Types.Get(entry.variety) then
    -- (and what there is to know of a hull)
    table.insert(orders, { label = "Info", kind = "Info" })
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
    elseif order.kind == "Info" then
      if Im.Button(order.label, bx, by, buttonWidth, 26, true, `Info:{entry.variety}`) then
        Info.Open(entry.variety)
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
  Im.Plain(was)
end

-- The targets the ship has locked or is locking, in a row, with how
-- many it has of how many it can have. One of them is the pilot's
-- target (Session.Aim), and is lit and says so: a click on another
-- makes that one it.
local function drawTargets(session: Session.Session, game: Core.Game, ball: State.Ball, entries: { Core.Entry }, x: number, y: number,
  room: number)
  local now = game.state.tick * Constants.TICK
  local wide, tall, gap = 168, 70, 6
  local across = math.max(1, (room + gap) // (wide + gap))
  for index, lock in ball.vitals.locks do
    local body = Core.Query.Body(game, lock.target)
    if body then
      local bx = x + ((index - 1) % across) * (wide + gap)
      local by = y + ((index - 1) // across) * (tall + gap)
      local aimed = lock.target == session.target
      Im.Flat(bx, by, wide, tall, Theme.PANEL, 0.94)
      Im.Edge(bx, by, wide, tall, if aimed then Theme.ACCENT else Theme.EDGE)
      if aimed then
        Im.Flat(bx, by, wide, 2, Theme.ACCENT)
      end
      local hot, clicked = Im.Area(`Target:{index}`, bx, by, wide, tall, true)
      if hot then
        Im.over = true
      end
      if clicked then
        session.selected = lock.target
        session.target = lock.target
      end
      Im.Strong(List.Cut(body.name, wide - (if aimed then 70 else 18), 14, true), bx + 9, by + 7, 14, Theme.TEXT)
      if aimed then
        Im.Pill("TARGET", bx + wide - 9 - (Im.StrongWidth("TARGET", 11) + 12), by + 7, Theme.ACCENT)
      end
      -- (how far off it is, and how fast it is going)
      local far = ""
      for _, entry in entries do
        if entry.id == lock.target then
          far = Format.Distance(entry.distance)
        end
      end
      local other = Core.Query.Ball(game, lock.target)
      if not lock.locked then
        local left = math.max(0, lock.done - now)
        Im.Text(string.format("locking  %.0f s", left), bx + 9, by + 27, 13, Theme.CAUTION)
        Im.Text(far, bx + wide - 9 - Im.TextWidth(far, 13), by + 27, 13, Theme.TEXT)
      else
        if other then
          local speed = `{math.floor(math.sqrt(other.vx ^ 2 + other.vy ^ 2 + other.vz ^ 2) + 0.5)} m/s`
          Im.Text(speed, bx + 9, by + 27, 13, Theme.DIM)
        else
          Im.Text("locked", bx + 9, by + 27, 13, Theme.DIM)
        end
        Im.Text(far, bx + wide - 9 - Im.TextWidth(far, 13), by + 27, 13, Theme.TEXT)
        if other then
          local v = other.vitals
          for layer, each in { { v.shield, v.shieldMax, Theme.SHIELD }, { v.armor, v.armorMax, Theme.ARMOR }, { v.hull, v.hullMax, Theme.HULL } } :: { { any } } do
            local ly = by + 46 + (layer - 1) * 6
            Im.Flat(bx + 9, ly, wide - 18, 4, Theme.DIM, 0.18)
            if each[2] > 0 then
              Im.Flat(bx + 9, ly, (wide - 18) * math.clamp(each[1] / each[2], 0, 1), 4, each[3])
            end
          end
        end
      end
    end
  end
end

-- The ship's own console, at the foot of the screen: one panel of the new
-- look (Game/UI/Theme) for what were two (its condition, and its speed
-- and what it is doing), with its modules beside it (drawRack).
--
-- On the left its three layers and its capacitor: and, for a hull with
-- an ore hold or a bay for ships, how full that is (the panel grows
-- upward by a row for each: its foot stays where it is). On the right
-- how fast it is going, of how fast it can; what it is doing; what
-- somebody else is doing about it; and its own buttons: to stop, and,
-- for a hull that has them, its own cloak and the gun along its bow.
-- Returns where the panel's top is. (A script's names are what they
-- were: "STOP", "Cloak", "BowGun".)
local STATE_W, STATE_H = 620, 140
local function drawState(session: Session.Session, ball: State.Ball, x: number, bottom: number): number
  local game = session.game
  local v = ball.vitals
  local rows: { { label: string, value: number, max: number, color: vector } } = {
    { label = "Shield", value = v.shield, max = v.shieldMax, color = Theme.SHIELD },
    { label = "Armour", value = v.armor, max = v.armorMax, color = Theme.ARMOR },
    { label = "Hull", value = v.hull, max = v.hullMax, color = Theme.HULL },
  }
  -- (a hull with no shield has no row for one: the Nimia's)
  if v.shieldMax <= 0 then
    table.remove(rows, 1)
  end
  local oreSize, oreUsed = Core.Query.OreHold(game, ball.id)
  if oreSize > 0 then
    table.insert(rows, { label = "Ore hold", value = oreUsed, max = oreSize, color = ORE })
  end
  local baySize, bayUsed = Core.Query.ShipBay(game, ball.id)
  if baySize > 0 then
    table.insert(rows, { label = "Ship bay", value = bayUsed, max = baySize, color = ORE })
  end
  local height = STATE_H + math.max(0, #rows - 3) * 22
  local y = bottom - 8 - height
  local split = 286
  Im.Frame(x, y, STATE_W, height)
  Im.Flat(x + split, y + 1, 1, height - 2, Theme.EDGE)

  -- Its condition.
  local line = y + 13
  for _, row in rows do
    Im.Text(row.label, x + 14, line, 13, Theme.DIM)
    Im.Flat(x + 74, line + 4, 106, 8, Theme.DIM, 0.18)
    if row.max > 0 then
      Im.Flat(x + 74, line + 4, 106 * math.clamp(row.value / row.max, 0, 1), 8, row.color)
    end
    local of = ` / {Format.Whole(math.floor(row.max + 0.5))}`
    Im.Text(of, x + split - 14 - Im.TextWidth(of, 13), line, 13, Theme.FAINT)
    local now = Format.Whole(math.floor(row.value + 0.5))
    Im.Text(now, x + split - 14 - Im.TextWidth(of, 13) - Im.TextWidth(now, 13), line, 13, Theme.TEXT)
    line += 22
  end
  -- (its capacitor, in twenty cells)
  line = y + height - 50
  Im.Text("Capacitor", x + 14, line, 13, Theme.DIM)
  local of = ` / {Format.Whole(math.floor(v.capacitorMax + 0.5))}`
  Im.Text(of, x + split - 14 - Im.TextWidth(of, 13), line, 13, Theme.FAINT)
  local now = Format.Whole(math.floor(v.capacitor + 0.5))
  Im.Text(now, x + split - 14 - Im.TextWidth(of, 13) - Im.TextWidth(now, 13), line, 13, Theme.TEXT)
  local lit = if v.capacitorMax > 0 then math.floor(20 * math.clamp(v.capacitor / v.capacitorMax, 0, 1) + 0.5) else 0
  local cell = (split - 28 - 19 * 2) / 20
  for index = 1, 20 do
    Im.Flat(x + 14 + (index - 1) * (cell + 2), line + 21, cell, 14, Theme.CAPACITOR, if index <= lit then 1 else 0.16)
  end

  -- Its speed, and what it is doing.
  local rx, rw = x + split + 14, STATE_W - split - 28
  local speed = math.sqrt(ball.vx ^ 2 + ball.vy ^ 2 + ball.vz ^ 2)
  local fast = Format.Speed(speed)
  Im.Strong(fast, rx, y + 10, 28, Theme.TEXT)
  Im.Text(`of {Format.Speed(ball.maxVelocity)}`, rx + Im.StrongWidth(fast, 28) + 10, y + 23, 13, Theme.DIM)
  Im.Flat(rx, y + 48, rw - 98, 6, Theme.DIM, 0.18)
  if ball.maxVelocity > 0 then
    Im.Flat(rx, y + 48, (rw - 98) * math.clamp(speed / ball.maxVelocity, 0, 1), 6, Theme.ACCENT)
  end
  local doing = describe(game, ball)
  while #doing > 4 and Im.StrongWidth(doing, 14) > rw - 98 do
    doing = string.sub(doing, 1, -6) .. "..."
  end
  Im.Strong(doing, rx, y + 62, 14, Theme.ACCENT)
  -- (and what somebody else is doing about either: Tactical/Combat. And
  -- whether anybody can see the ship at all, or only from close in: in
  -- a cloud of gas.)
  local across = rx
  local function flag(word: string, color: vector)
    across += Im.Pill(word, across, y + 86, color) + 6
  end
  if v.scrambled then
    flag("WARP SCRAMBLED", Theme.BAD)
  end
  if v.entangle < 1 then
    flag("ENTANGLED", Theme.BAD)
  end
  if v.paint > 1 or v.damp < 1 then
    flag(if v.damp < 1 then "DAMPENED" else "PAINTED", Theme.CAUTION)
  end
  if Core.Query.Cloaked(game, ball.id) then
    flag("CLOAKED", Theme.ACCENT)
  else
    local veiled, sight = Core.Query.Veiled(game, ball.id)
    if veiled then
      flag("IN VAPOUR", Theme.ACCENT)
      Im.Text(`nothing locks you from beyond {Format.Distance(sight)}, nor you it`, rx, y + 108, 12, Theme.DIM)
    end
  end

  -- Its own buttons.
  local was = Im.Plain(true)
  local bx = x + STATE_W - 14 - 84
  local inWarp = ball.warp ~= nil and ball.warp.stage == "warp"
  local stop = Keys.Did("stop") and not inWarp
  Im.Tone("danger")
  Im.Because("Not in warp")
  if Im.Button("STOP", bx, y + 12, 84, 28, not inWarp) or stop then
    Session.Order(session, "Stop")
  end
  -- (a hull with a cloak of its own has it here, on and off: there is
  -- no module of it in the rack. Tactical/Combat)
  local has, on = Core.Query.OwnCloak(game, ball.id)
  local by = y + 46
  if has then
    local key = Keys.Did("cloak") and not inWarp
    Im.Because("Not in warp")
    if Im.Button(if on then "UNCLOAK" else "CLOAK", bx, by, 84, 26, not inWarp, "Cloak") or key then
      Session.Do(session, { kind = if on then "Uncloak" else "Cloak", actor = 0 })
    end
    by += 32
  end
  -- (and a hull with a gun of its own, fixed along its bow, fires it
  -- from here, at what is aimed at: the ship turns for it, and the gun
  -- fires when it is pointed. Tactical/Combat)
  local gun = Core.Query.Spinal(game, ball.id)
  if gun then
    local key = Keys.Did("bowgun") and not inWarp
    local label = if gun.aiming then "AIMING" elseif gun.cycling > 0 then `{math.ceil(gun.cycling)} s` else "BOW GUN"
    if Im.Button(label, bx, by, 84, 26, not inWarp and not gun.aiming and gun.cycling <= 0, "BowGun")
      or (key and not gun.aiming and gun.cycling <= 0) then
      Session.Do(session, { kind = "FireSpinal", actor = 0, target = aimOf(session, ball) })
    end
  end
  Im.Plain(was)
  return y
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

-- The fitted modules, as buttons beside the ship's state: click one, or
-- press its key, to switch it on or off. Three rows (the owner's,
-- 2026-11-15, with a picture of what was meant: "Rather than
-- side-by-side, you should have 3 rows"): the high slots on top, the mid
-- slots under them, the low slots under those, each as long as it needs
-- to be, from 'x' and no further than 'room' wide. A button is the
-- thing's sign with its key, how many rounds it has and how far through
-- its cycle it is: what it is called and what it is doing are said
-- while the cursor is on it. One that does nothing by itself is dim.
--
-- In a row with more in it than STACK_OVER, or than fit, the weapons
-- that are the same (the same make, loaded with the same thing) are one
-- button with their number on it, and are switched on and off together
-- (the owner's: a hull of a hundred and forty hardpoints). The keys go
-- by the buttons then, the first for the first.
-- (A script's names: "Rack:<n>", the buttons counted from the first.)
local RACK_ROWS: { [string]: number } = { high = 1, mid = 2, low = 3 }
local RACK_LABELS = { "HIGH", "MID", "LOW" }
local SLOT, SLOT_PITCH = 44, 48
local STACK_OVER = 8
type Slot = { items: { State.Item }, first: number, module: Modules.ModuleType }

local function drawRack(session: Session.Session, game: Core.Game, ball: State.Ball, x: number, top: number, room: number)
  local fitted = Core.Query.Fitted(game, ball.id)
  if #fitted == 0 then
    return
  end
  local counts: { number } = { 0, 0, 0 }
  for _, item in fitted do
    local row = RACK_ROWS[item.place]
    if row then
      counts[row] += 1
    end
  end
  local fits = math.max(4, (room - 34) // SLOT_PITCH)
  local rows: { { Slot } } = { {}, {}, {} }
  local stacked = false
  for index, item in fitted do
    local row = RACK_ROWS[item.place]
    if row == nil then
      continue
    end
    local module = Modules.byId[item.type]
    local into: Slot? = nil
    if module.weapon and (counts[row] > STACK_OVER or counts[row] > fits) then
      for _, slot in rows[row] do
        if slot.items[1].type == item.type and slot.items[1].charge == item.charge then
          into = slot
        end
      end
    end
    if into then
      table.insert(into.items, item)
      stacked = true
    else
      local slot: Slot = { items = { item }, first = index, module = module }
      table.insert(rows[row], slot)
    end
  end
  local runs: { [number]: State.Running } = {}
  for _, running in ball.vitals.running do
    runs[running.item] = running
  end
  local now = game.state.tick * Constants.TICK
  local ordinal, pressable = 0, 0
  for row = 1, 3 do
    local y = top + (row - 1) * SLOT_PITCH
    if #rows[row] > 0 then
      Im.Strong(RACK_LABELS[row], x, y + 17, 10, Theme.DIM)
    end
    for place, slot in rows[row] do
      ordinal += 1
      local bx = x + 34 + (place - 1) * SLOT_PITCH
      if bx + SLOT > x + room then
        break
      end
      local module = slot.module
      local item = slot.items[1]
      local running: State.Running? = nil
      local going = 0
      for _, each in slot.items do
        if runs[each.id] then
          running = running or runs[each.id]
          going += 1
        end
      end
      local active = module.weapon ~= nil or module.repair ~= nil or module.boost ~= nil or module.miner ~= nil
        or module.hex ~= nil or module.salvager ~= nil or module.injector ~= nil or module.smartbomb ~= nil
      if active then
        pressable += 1
      end
      local hot, clicked = Im.Area(`Rack:{ordinal}`, bx, y, SLOT, SLOT, active)
      if hot then
        Im.over = true
      end
      -- (on: green; off: a plain button, lighter under the cursor; one that does nothing by itself: dim)
      if running then
        Im.Flat(bx, y, SLOT, SLOT, vector.create(0.11, 0.21, 0.16), 0.94)
        Im.Edge(bx, y, SLOT, SLOT, Theme.GOOD)
      elseif active then
        Im.Flat(bx, y, SLOT, SLOT, if hot then Theme.CONTROL else Theme.RAISED, 0.94)
        Im.Edge(bx, y, SLOT, SLOT, Theme.EDGE_STRONG)
      else
        Im.Flat(bx, y, SLOT, SLOT, Theme.PANEL, 0.7)
        Im.Edge(bx, y, SLOT, SLOT, Theme.EDGE)
      end
      ItemIcon.Draw(item.type, bx + 9, y + 9, 26)
      if not active then
        Im.Flat(bx + 1, y + 1, SLOT - 2, SLOT - 2, Theme.PANEL, 0.6)
      end
      -- (by its key: F1 for the first of the rack, until a person says otherwise)
      local key = Keys.Rack(if stacked then pressable else slot.first)
      if key and active then
        Im.Strong(Keys.Of(key), bx + 3, y + 1, 10, Theme.DIM)
        clicked = Keys.Did(key) or clicked
      end
      -- What it is doing, in a word, for whoever asks.
      local note = if not active then "does its work by itself" else "off"
      local rounds: number? = nil
      local takes = Modules.Takes(module)
      if takes then
        if item.charge == "" then
          note = "empty"
        elseif takes.clip > 0 then
          rounds = item.rounds
          for _, each in slot.items do
            rounds = math.min(rounds :: number, each.rounds)
          end
          note = `{Types.Info(item.charge).name}, {rounds} {if rounds == 1 then "round" else "rounds"}`
        else
          note = Types.Info(item.charge).name
        end
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
      if rounds then
        local text = tostring(rounds)
        Im.Strong(text, bx + SLOT - 3 - Im.StrongWidth(text, 11), y + 1, 11, Theme.TEXT)
      end
      if #slot.items > 1 then
        local text = `x{#slot.items}`
        Im.Flat(bx + 1, y + SLOT - 18, Im.StrongWidth(text, 11) + 6, 13, Theme.PANEL, 0.85)
        Im.Strong(text, bx + 4, y + SLOT - 18, 11, Theme.ACCENT)
      end
      if running then
        local duration = if module.weapon then module.weapon.duration
          elseif module.repair then module.repair.duration
          elseif module.miner then module.miner.duration
          elseif module.hex then module.hex.duration
          elseif module.salvager then module.salvager.duration
          else module.boostDuration or 1
        Im.Flat(bx + 1, y + SLOT - 5, SLOT - 2, 4, Theme.GOOD, 0.2)
        Im.Flat(bx + 1, y + SLOT - 5, (SLOT - 2) * math.clamp((duration - math.max(0, running.next - now)) / duration, 0, 1), 4, Theme.GOOD)
        if running.stopping then
          note = "stopping"
        elseif module.weapon and going > 0 then
          note = `firing: {note}`
        end
      end
      if hot then
        Im.Tip(if #slot.items > 1 then `{#slot.items} x {module.name}` else module.name, note, if key and active then Keys.Of(key) else nil,
          bx - 20, top - 54)
      end
      if clicked and active then
        -- (a button of several is all of them: off, if any is on; else on)
        for _, each in slot.items do
          if running then
            if runs[each.id] then
              Session.Do(session, { kind = "DeactivateModule", actor = 0, item = each.id })
            end
          elseif module.salvager then
            -- (on the wreck that is selected: a wreck needs no lock)
            Session.Do(session, { kind = "ActivateModule", actor = 0, item = each.id, target = session.selected })
          elseif module.weapon or module.miner or module.hex then
            -- (at the pilot's target: aimOf)
            Session.Do(session, { kind = "ActivateModule", actor = 0, item = each.id, target = aimOf(session, ball) })
          else
            Session.Do(session, { kind = "ActivateModule", actor = 0, item = each.id })
          end
        end
      end
    end
  end
end

-- The clock, in the foot of the dock (Game/UI/Dock): to stop time and
-- let it run, how fast it is running, and to run it slower and faster.
-- (A script's names are what they were when it was a strip at the foot
-- of the screen: "pause" or "run", "Clock:slower", "Clock:faster".)
local function drawClock(session: Session.Session, x: number, bottom: number)
  local clock = session.clock
  local width = Dock.WIDTH
  local y = bottom - Dock.FOOT
  Im.Flat(x + 12, y, width - 24, 1, Theme.EDGE)
  local name = if clock.paused then "run" else "pause"
  Im.Flat(x + 6, y + 10, width - 12, 24, Theme.CONTROL, 0.92)
  local toggled, onPause = Im.IconButton(name, x + 6, y + 10, width - 12, 24, true, name, if clock.paused then Theme.CAUTION else Theme.TEXT)
  if toggled then
    clock.paused = not clock.paused
  end
  if onPause then
    Im.Tip(if clock.paused then "Let time run" else "Stop time", nil, Keys.Of("pause"), x + width + 6, y + 8)
  end
  local speed = if clock.paused then "paused" else `x{clock.scale}`
  Im.Strong(speed, x + (width - Im.StrongWidth(speed, 13)) / 2, y + 39, 13, if clock.paused then Theme.CAUTION else Theme.TEXT)
  -- (time is run faster only at a station)
  local docked = Core.Query.Player(session.game).docked ~= 0
  Im.Flat(x + 6, y + 58, 19, 20, Theme.CONTROL, 0.92)
  Im.Flat(x + 27, y + 58, 19, 20, Theme.CONTROL, 0.92)
  local slower, onSlower = Im.IconButton("minus", x + 6, y + 58, 19, 20, clock.scale > 1, "Clock:slower", Theme.TEXT)
  if slower then
    clock.scale = math.max(1, clock.scale / 2)
  end
  local faster, onFaster = Im.IconButton("plus", x + 27, y + 58, 19, 20, docked and clock.scale < 16, "Clock:faster", Theme.TEXT)
  if faster then
    clock.scale = math.min(16, clock.scale * 2)
    clock.forced = false
  end
  if onSlower or onFaster then
    Im.Tip(if onSlower then "Run time slower" else "Run time faster", if docked then nil else "Time runs faster only at a station", nil,
      x + width + 6, y + 56)
  end
end

-- ---------------------------------------------------------------------

-- The star map is a window (Game/UI/Windows) that draws itself as it did
-- when it was a panel: it is moved by its heading, where there is
-- nothing to press, and by a strip along its top. Whose it is is set
-- down each frame, before the windows are drawn. (The docked screen was
-- another such, until the last of its tabs was a window of its own.)
local mapOf: Session.Session? = nil
local mapShown = false
Windows.Kind("map", function(_: Windows.Window, x: number, y: number, w: number, h: number)
  if mapOf then
    Map.DrawAt(mapOf, x, y, w, h)
  end
end)
Windows.Make("map", "map", "Star map", 260, 110, 1400, 820, 980, 600, nil)
Windows.Icon("map", "map")
-- (it lies over the others, and nothing is put clear of it)
Windows.Auto("map", false, true)

-- (The guide, the colonies, the scanner and what is said of a type of
-- thing were panels drawn by themselves at a place of their own; since
-- 2026-11-16 each is a window of its own module, set out as the market
-- is. Where each opens first is said here, below.)

-- What a pilot does at any station, in a panel beside the corner's
-- while they are docked: to undock; to make the station home, for its
-- fee, with where home is now under it; to mend the ship, where it is
-- damaged (the fitting window mends it too); at the station the career
-- agents are at, the way to them; and at a starbase of the pilot's own,
-- the way to its running. Under those, what is in training. (They were
-- the foot of the docked screen.) Returns how wide it came to.
--
-- To a script: "UNDOCK", "SetHome", "Station:repair", "Station:careers",
-- "Station:starbase".
local function drawBerth(session: Session.Session, game: Core.Game, player: Core.PlayerInfo, x: number, y: number): number
  local was = Im.Plain(true)
  local home = Core.Query.Home(game)
  local move: State.Command = { kind = "SetHome", actor = 0 }
  local canMove, whyNotMove = Session.CanDo(session, move)
  local record = game.state.ships[player.ship]
  local damaged = record ~= nil and record.armorDamage + record.hullDamage > 0
  local careers = Core.Query.Careers(game)
  local school = careers.station == player.docked
  -- (a pilot who has done half of what there is to do without the agents is not new)
  local new = school and not careers.begun and select(2, Core.Query.Guide(game)) < 12
  local own = StarbaseWindow.Here(game, player)
  local width = 12 + 124 + 8 + 176 + (if damaged then 8 + 168 else 0) + (if school then 8 + 132 else 0) + (if own then 8 + 110 else 0) + 12
  Im.Frame(x, y, width, 94)
  Im.Tone("primary")
  if Im.Button("UNDOCK", x + 12, y + 12, 124, 34, true) then
    Session.Order(session, "Undock")
  end
  local across = x + 12 + 124 + 8
  Im.Because(if home.here then "This station is your home already" else whyNotMove)
  if Im.Button(if home.here then "Home is here" else `Make home  {Format.Credits(home.fee)}`, across, y + 12, 176, 34, canMove, "SetHome") then
    Session.Do(session, move)
  end
  across += 176 + 8
  if damaged then
    local mend: State.Command = { kind = "Repair", actor = 0 }
    local canMend, whyNotMend = Session.CanDo(session, mend)
    Im.Because(whyNotMend)
    if Im.Button(`Repair  {Format.Whole(Core.Query.RepairCost(game))} cr`, across, y + 12, 168, 34, canMend, "Station:repair") then
      Session.Do(session, mend)
    end
    across += 168 + 8
  end
  if school then
    if Im.Button("Career agents", across, y + 12, 132, 34, true, "Station:careers") then
      if SchoolWindow.IsOpen() then
        SchoolWindow.Close()
      else
        SchoolWindow.Open()
      end
    end
    if Im.Inside(across, y + 12, 132, 34) then
      Im.Tip("Career agents", if new then "New here? They teach the ropes, and pay" else "Seven people who teach a way of making a living each")
    end
    across += 132 + 8
  end
  if own then
    if Im.Button("Starbase", across, y + 12, 110, 34, true, "Station:starbase") then
      if StarbaseWindow.IsOpen() then
        StarbaseWindow.Close()
      else
        StarbaseWindow.Open()
      end
    end
    if Im.Inside(across, y + 12, 110, 34) then
      Im.Tip("Starbase", "The running of this tower of yours")
    end
  end
  -- Under them: where home is (or why this station cannot be made it), and what is in training.
  local far = if home.jumps < 0 then "out of reach" elseif home.jumps == 0 then "in this system"
    elseif home.jumps == 1 then "1 jump off" else `{home.jumps} jumps off`
  local where = if home.here then "This station is your home." elseif canMove then `Home: {home.name}, {far}`
    else `Home is {far}: {tostring(whyNotMove)}`
  Im.Text(List.Cut(where, width - 24, 12, false), x + 12, y + 54, 12, if home.here or canMove then Theme.DIM else Theme.CAUTION)
  local training = Core.Query.Training(game)
  local now = training[1]
  if now then
    Im.Text(List.Cut(`Training {Skills.byId[now.skill].name} {now.level}: {Format.Duration(now.left)}`, width - 24, 12, false), x + 12, y + 72, 12,
      Theme.DIM)
  else
    Im.Text("No skill in training", x + 12, y + 72, 12, Theme.CAUTION)
  end
  Im.Plain(was)
  return width
end
-- (how many jobs are in hand, counted once a tick and not once a frame)
local jobsTick, jobsHeld = -1, {} :: { Core.MissionStatus }

-- Whether the interface is drawn at all: not, for a picture of the
-- scene alone (Hud.Hide, and GameDebug.Hud in the game app).
local hidden = false

function Hud.Hide(on: boolean)
  hidden = on
end

function Hud.Create(session: Session.Session, scene: Scene.Scene): Widget
  -- Expanded, so that it covers the window: a bare widget has no size.
  return Components.Expand(Widget_Luau(Widget_Create(), {
    PostDraw = function(_, whole: Widget)
      -- (the window's size, in the interface's units: Theme.scale)
      local w: Area = { pos = whole.pos / Theme.scale, size = whole.size / Theme.scale }
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
        -- (in the look: its panel, its buttons)
        local wasPlain = Im.Plain(true)
        Menu.Draw(session, w.pos.x, w.pos.y, w.size.x, w.size.y)
        Im.Plain(wasPlain)
        Splash.Draw(w.pos.x, w.pos.y, w.size.x, w.size.y, math.min(0.1, FrameTimer_Get()))
        overInterface = true
        return
      end
      -- (and nothing at all, for a picture of the scene alone)
      if hidden then
        overInterface = false
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
      -- (shut by its corner's button, the map is shut)
      if mapShown and not Windows.IsOpen("map") and Map.IsOpen() then
        Map.Close()
      end
      if Map.IsOpen() ~= Windows.IsOpen("map") then
        if Map.IsOpen() then
          Windows.Open("map")
        else
          Windows.Close("map")
        end
      end
      mapShown = Map.IsOpen()
      -- (and the windows go over what is drawn before them: Game/UI/Windows)
      Inventory.Frame(session, player.docked ~= 0)
      Market.Frame(session, player.docked ~= 0)
      ShipsWindow.Frame(session, player.docked ~= 0)
      SkillSheet.Frame(session)
      IndustryWindow.Frame(session, player.docked ~= 0)
      JobsWindow.Frame(session)
      ContractsWindow.Frame(session)
      CrewWindow.Frame(session, player.docked ~= 0)
      WalletWindow.Frame(session, player.docked ~= 0)
      SchoolWindow.Frame(session, player.docked ~= 0 and Core.Query.Careers(game).station == player.docked)
      -- (the running of a starbase of the pilot's own, which is what they have come there for: open on arrival)
      StarbaseWindow.Frame(session, game, player)
      Assets.Frame(session)
      Events.Frame(session)
      Guide.Frame(session)
      CorporationWindow.Frame(session)
      -- The dock is down the left edge (Game/UI/Dock): the windows keep
      -- clear of it, and what was set out from the screen's left edge
      -- is set out from the dock's.
      local edge = left + Dock.WIDTH
      Windows.Begin(edge, top, right, bottom)

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

      -- Where we are and what we have: a panel of its own in the corner,
      -- beside the dock. The system, how safe it is and whose, where in
      -- it the pilot is, and the ship and the wallet.
      local whereX, whereY = edge + 8, top + 12
      local system = string.upper(player.systemName)
      -- (how safe it is here: what comes to a belt follows from it)
      local _, band = Core.Query.Security(game, player.system)
      local tone = if player.uncharted then Theme.BAD elseif band == "secure" then Theme.GOOD elseif band == "low" then Theme.CAUTION else Theme.BAD
      -- (off the map: nobody's, and how deep in it lies says what lives there)
      local safety = if player.uncharted then `DEPTH {player.depth} OF {player.depths}`
        else string.format("%.1f %s", player.security, BANDS[band or "secure"])
      local whose = if player.uncharted then "On no map" elseif player.owner ~= "" then player.owner else "Unclaimed"
      -- (and where that is: its constellation and its region; uncharted space is all one: Core/Describe/Galaxy)
      local region = if player.uncharted then player.region else `{player.constellation}, {player.region}`
      local berth = if player.docked ~= 0 then Core.Query.Body(game, player.docked) else nil
      local place = if player.docked == 0 then "In space" elseif berth then `Docked: {berth.name}` else "Docked"
      local craft = `{player.shipName}  -  {player.hull.name}`
      local wallet = `{Format.Whole(game.state.wallet)} cr`
      local whereWidth = math.max(300, Im.HeadingWidth(system, 26) + 28,
        Im.StrongWidth(safety, 11) + Im.StrongWidth(whose, 13) + Im.TextWidth(region, 13) + 60, Im.TextWidth(place, 13) + 28,
        Im.TextWidth(craft, 13) + Im.StrongWidth(wallet, 13) + 48)
      local whereHeight = 94
      Im.Frame(whereX, whereY, whereWidth, whereHeight)
      Im.Flat(whereX, whereY, 3, whereHeight, tone)
      Im.Heading(system, whereX + 14, whereY + 9, 26, Theme.TEXT)
      local across = whereX + 14
      across += Im.Pill(safety, across, whereY + 38, tone) + 10
      Im.Strong(whose, across, whereY + 38, 13, Theme.CAUTION)
      Im.Text(region, across + Im.StrongWidth(whose, 13) + 10, whereY + 38, 13, Theme.DIM)
      Im.Text(place, whereX + 14, whereY + 56, 13, Theme.TEXT)
      Im.Text(craft, whereX + 14, whereY + 73, 13, Theme.DIM)
      Im.Strong(wallet, whereX + whereWidth - 12 - Im.StrongWidth(wallet, 13), whereY + 73, 13, Theme.TEXT)
      -- (and docked, beside it: what a pilot does at any station)
      local berthWidth = if player.docked ~= 0 then drawBerth(session, game, player, whereX + whereWidth + 12, whereY) else 0
      -- Under it, what is the matter with the system, if anything is.
      local said = whereY + whereHeight + 6
      -- (whether pirates are massing here: Tactical/Surges)
      local surge = Core.Query.Surge(game)
      local surgeHere = surge ~= nil and surge.system == player.system
      if surge and surgeHere then
        Im.Text(`PIRATE SURGE  bounties doubled, {Format.Duration(surge.left)} left`, whereX + 2, said, 13, Theme.BAD)
      end
      -- (and whether somebody's fleet has its lanes shut: Core/Strategic/Wars)
      local blockading, why = Core.Query.Blockade(game)
      local blockadedHere = blockading ~= nil
      if blockading then
        Im.Text(`BLOCKADED by the {blockading}: {if why == "siege" then "a siege" else "they are claiming it"}. Little comes in or goes out`,
          whereX + 2, said + (if surgeHere then 18 else 0), 13, Theme.CAUTION)
      end

      if scene.warp > 0 and ball and ball.warp then
        local target = Core.Query.Body(game, ball.warp.target)
        local cx = left + w.size.x / 2
        Im.Heading("WARP DRIVE ACTIVE", cx - 118, top + 120, 26, Im.ACCENT)
        local line = `{if target then target.name else "?"}   {Format.Distance(scene.warpLeft)}   {math.ceil(scene.warpSeconds)} s`
        Im.Text(line, cx - Im.TextWidth(line, 16) / 2, top + 154, 16, Im.TEXT)
      end

      local panelWidth = 400
      local panelX = right - panelWidth - 12
      -- The ship's own console is at the foot of the screen, a little left
      -- of its middle, with the modules beside it on the right: or as far
      -- right as leaves the rows beside the dock (the fleet's, the
      -- drones': 440 px wide) clear.
      local consoleX = math.max(edge + 8 + 440 + 8, left + (w.size.x - STATE_W) / 2 - 130)
      -- (the boosters: over the console's right end in space, and at the foot of the screen docked)
      local boostersX, boostersFoot = consoleX + STATE_W - 316, bottom - 20
      -- Beside the corner's panel, under what is locked: the last thing
      -- that happened, for a few seconds, in the colour of what kind of
      -- thing it is (Session.Say).
      local noticeX, noticeY = whereX + whereWidth + 12 + (if berthWidth > 0 then berthWidth + 12 else 0), top + 12
      if ball then
        local room = panelX - 12 - noticeX
        local perRow = math.max(1, (room + 6) // 174)
        noticeY += ((#ball.vitals.locks + perRow - 1) // perRow) * 76
      end
      if session.message ~= "" and game.state.tick - session.messageTick < 10 then
        local kind = session.messageKind
        local tint = if kind == "good" then Theme.GOOD elseif kind == "warn" then Theme.CAUTION elseif kind == "bad" then Theme.BAD else Theme.DIM
        local wide = Im.TextWidth(session.message, 14) + 26
        Im.Flat(noticeX, noticeY, wide, 28, Theme.PANEL, 0.94)
        Im.Edge(noticeX, noticeY, wide, 28, Theme.EDGE)
        Im.Flat(noticeX, noticeY, 3, 28, tint)
        Im.Text(session.message, noticeX + 13, noticeY + 6, 14, if kind == "plain" then Theme.TEXT else tint)
      end
      if ball then
        -- (beside the corner's panel, not over it)
        drawTargets(session, game, ball, entries, whereX + whereWidth + 12, top + 12, panelX - 12 - (whereX + whereWidth + 12))
        -- The jobs in hand, under the corner's panel: what each still
        -- wants and how long it can be kept. In space they were not to
        -- be seen at all. (Docked, they are the Jobs page's.)
        if jobsTick ~= game.state.tick then
          jobsTick, jobsHeld = game.state.tick, Core.Query.Missions(game).inHand
        end
        if #jobsHeld > 0 then
          local shown = math.min(4, #jobsHeld)
          local jy = said + (if blockadedHere then 20 else 0) + (if surgeHere then 18 else 0)
          local tall = 30 + shown * 44 + (if #jobsHeld > shown then 18 else 0)
          Im.Frame(whereX, jy, whereWidth, tall)
          Im.Heading(`IN HAND  {#jobsHeld}`, whereX + 12, jy + 8, 15, Theme.DIM)
          for index = 1, shown do
            local held = jobsHeld[index]
            local ry = jy + 30 + (index - 1) * 44
            Im.Flat(whereX + 1, ry - 2, whereWidth - 2, 1, Theme.EDGE)
            local kept = Format.Duration(held.left)
            Im.Text(kept, whereX + whereWidth - 12 - Im.TextWidth(kept, 12), ry + 5, 12, if held.left < 6 * 3600 then Theme.CAUTION else Theme.DIM)
            Im.Strong(List.Cut(held.title, whereWidth - 36 - Im.TextWidth(kept, 12), 14, true), whereX + 12, ry + 3, 14, Theme.TEXT)
            Im.Text(List.Cut(if held.ready then "done: hand it in" else held.why, whereWidth - 24, 12, false), whereX + 12, ry + 22, 12,
              if held.ready then Theme.GOOD else Theme.DIM)
          end
          if #jobsHeld > shown then
            Im.Text(`and {#jobsHeld - shown} more`, whereX + 12, jy + tall - 20, 12, Theme.FAINT)
          end
        end
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
        -- (out of the station, nothing is being tried on the ship any more)
        if session.trying.paint or session.trying.design then
          session.trying = {}
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
        -- (the overview ends short of the modules, which are under it at the foot of the screen)
        drawOverview(session, entries, panelX, top + 182, panelWidth, math.min(600, bottom - top - 182 - STATE_H - 28), marks)
        local stateTop = drawState(session, ball, consoleX, bottom)
        local rackX = consoleX + STATE_W + 10
        drawRack(session, game, ball, rackX, bottom - 8 - STATE_H, right - 8 - rackX)
        boostersFoot = stateTop - 8
      else
        -- (the ship in the fitting window is a thing of the scene, drawn
        -- as the scene draws, Scene.Showcase: and in whatever paint is
        -- being tried on it, Session.Try)
        Scene.Try(session.trying.paint, session.trying.design)
        -- (the fitting window, which is a station's own: open when the
        -- pilot docks, if it was when they last left one. What its wheel
        -- shows the ship with is the scene's)
        Fitting.Frame(session, true, Scene.Dressed(game, player.ship, player.hull.id, player.hull.radius),
          function(cx: number, cy: number, round: number): boolean
            -- (where the scene draws it is the screen's: in pixels)
            return Scene.Showcase(scene, game, player.ship, player.hull.id, player.hull.radius, Theme.Px(cx), Theme.Px(cy), Theme.Px(round))
          end)
      end
      if ball then
        Fitting.Frame(session, false, nil, nil)
      end
      -- (beside the ship's own panels in space, and in the same place docked)
      drawBoosters(session, boostersX, boostersFoot)
      -- The dock, down the left edge (Game/UI/Dock): drawn before the
      -- windows, which keep clear of it, so that what one of its buttons
      -- opens is drawn this same frame.
      local docked = ball == nil
      if jobsTick ~= game.state.tick then
        jobsTick, jobsHeld = game.state.tick, Core.Query.Missions(game).inHand
      end
      local jobsInHand = #jobsHeld
      local steps, guided = Core.Query.Guide(game)
      local pressed = Dock.Draw(w.pos.x, top, bottom, function(id: string): Dock.State
        if id == "wallet" then
          return { open = WalletWindow.IsOpen(), can = docked, note = if docked then nil else "At a station only" }
        elseif id == "corporation" then
          -- (a window of its own since 2026-11-16, docked or in space: Game/UI/Corporation)
          return { open = CorporationWindow.IsOpen(), can = true }
        elseif id == "crew" then
          return { open = CrewWindow.IsOpen(), can = docked, note = if docked then nil else "At a station only" }
        elseif id == "contracts" then
          -- (galaxy-wide, and dealt with from anywhere: Game/UI/Contracts)
          return { open = ContractsWindow.IsOpen(), can = true }
        elseif id == "fitting" then
          -- (a station's own, and a window of its own: Game/UI/Fitting)
          return { open = Fitting.IsOpen(), can = docked, note = if docked then nil else "At a station only" }
        elseif id == "ships" then
          return { open = ShipsWindow.IsOpen(), can = docked, note = if docked then nil else "At a station only" }
        elseif id == "skills" then
          -- (the pilot's own, wherever they are: Game/UI/Skills)
          return { open = SkillSheet.IsOpen(), can = true }
        elseif id == "industry" then
          return { open = IndustryWindow.IsOpen(), can = docked, note = if docked then nil else "At a station only" }
        elseif id == "jobs" then
          -- (the jobs in hand are the pilot's wherever they are: Game/UI/Jobs)
          return { open = JobsWindow.IsOpen(), can = true, badge = jobsInHand }
        elseif id == "inventory" then
          return { open = Inventory.IsOpen(), can = true, key = Keys.Of("inventory") }
        elseif id == "market" then
          -- (a station's own, and a window of its own: Game/UI/Market)
          return { open = Market.IsOpen(), can = docked, note = if docked then nil else "At a station only" }
        elseif id == "map" then
          return { open = Map.IsOpen(), can = true, key = Keys.Of("map") }
        elseif id == "scanner" then
          return { open = not docked and Scanner.IsOpen(), can = not docked, note = if docked then "In space only" else nil }
        elseif id == "colonies" then
          return { open = Colony.IsOpen(), can = true }
        elseif id == "events" then
          return { open = Events.IsOpen(), can = true }
        elseif id == "guide" then
          return { open = Guide.IsOpen(), can = true, note = `{guided} of {#steps} done` }
        end
        return { open = false, can = true, key = "Esc" }
      end)
      drawClock(session, w.pos.x, bottom)
      -- (a script that pressed the docked screen's Market tab, when the
      -- market was one, opens the market's window: it is never shut by this)
      if Im.Hook("Market", docked) then
        Market.Open()
      end
      -- (and one that pressed its Fitting tab, the fitting window's: and
      -- its other tabs, which a script pressed when the screen was always
      -- open, open it at that tab now that it is not)
      if Im.Hook("Fitting", docked) then
        Fitting.Open()
      end
      if Im.Hook("Ships", docked) then
        ShipsWindow.Open()
      end
      if Im.Hook("Skills", true) then
        SkillSheet.Open()
      end
      if Im.Hook("Industry", docked) then
        IndustryWindow.Open()
      end
      if Im.Hook("Missions", true) then
        JobsWindow.Open()
      end
      -- (the board was a page of the market's: its name opens the contracts' window)
      if Im.Hook("Category:contracts", true) then
        ContractsWindow.Open()
      end
      if Im.Hook("Crew", docked) then
        CrewWindow.Open()
      end
      if Im.Hook("Wallet", docked) then
        WalletWindow.Open()
      end
      if Im.Hook("Careers", docked and Core.Query.Careers(game).station == player.docked) then
        SchoolWindow.Open()
      end
      if Im.Hook("Starbase", docked and StarbaseWindow.Here(game, player)) then
        StarbaseWindow.Open()
      end
      if pressed then
        if pressed == "wallet" then
          -- (pressed again, it is put away)
          if WalletWindow.IsOpen() then
            WalletWindow.Close()
          else
            WalletWindow.Open()
          end
        elseif pressed == "corporation" then
          if CorporationWindow.IsOpen() then
            CorporationWindow.Close()
          else
            CorporationWindow.Open()
          end
        elseif pressed == "contracts" then
          if ContractsWindow.IsOpen() then
            ContractsWindow.Close()
          else
            ContractsWindow.Open()
          end
        elseif pressed == "crew" then
          if CrewWindow.IsOpen() then
            CrewWindow.Close()
          else
            CrewWindow.Open()
          end
        elseif pressed == "fitting" then
          if Fitting.IsOpen() then
            Fitting.Close()
          else
            Fitting.Open()
          end
        elseif pressed == "ships" then
          if ShipsWindow.IsOpen() then
            ShipsWindow.Close()
          else
            ShipsWindow.Open()
          end
        elseif pressed == "skills" then
          if SkillSheet.IsOpen() then
            SkillSheet.Close()
          else
            SkillSheet.Open()
          end
        elseif pressed == "industry" then
          if IndustryWindow.IsOpen() then
            IndustryWindow.Close()
          else
            IndustryWindow.Open()
          end
        elseif pressed == "jobs" then
          if JobsWindow.IsOpen() then
            JobsWindow.Close()
          else
            JobsWindow.Open()
          end
        elseif pressed == "inventory" then
          if Inventory.IsOpen() then
            Inventory.Close()
          else
            Inventory.Open()
          end
        elseif pressed == "market" then
          if Market.IsOpen() then
            Market.Close()
          else
            Market.Open()
          end
        elseif pressed == "map" then
          if Map.IsOpen() then
            Map.Close()
          else
            Map.Open()
          end
        elseif pressed == "scanner" then
          if Scanner.IsOpen() then
            Scanner.Close()
          else
            Scanner.Open()
          end
        elseif pressed == "colonies" then
          if Colony.IsOpen() then
            Colony.Close()
          else
            Colony.Open()
          end
        elseif pressed == "events" then
          if Events.IsOpen() then
            Events.Close()
          else
            Events.Open()
          end
        elseif pressed == "guide" then
          if Guide.IsOpen() then
            Guide.Close()
          else
            Guide.Open()
          end
        elseif pressed == "menu" then
          Menu.Toggle(session)
        end
      end
      -- What is in reach, and the moving of it: a window that goes where
      -- it is put (Game/UI/Inventory), opened from the dock or by its
      -- key. Everything the pilot owns anywhere, the assets window, is
      -- opened from it.
      if Keys.Did("inventory") and not Im.Typing() then
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
      if Keys.Did("map") then
        if Map.IsOpen() then
          Map.Close()
        else
          Map.Open()
        end
      end
      -- The guide, the colonies, the scanner and what is said of a type
      -- of thing: each a window (above), open when the thing is. Where
      -- nobody has put one it is beside the dock, or beside the docked
      -- screen for what is said of a thing: and from there finds itself
      -- a place clear of what is open (Windows.Open).
      Windows.Default(Colony.ID, edge + 8, top + 130, Colony.WIDTH, Colony.HEIGHT)
      Colony.Frame(session)
      Windows.Default(Scanner.ID, edge + 8, top + 130, Scanner.WIDTH, Scanner.HEIGHT)
      Scanner.Frame(session, if ball then scene.camera:GetLook() else nil, ball ~= nil)
      -- (the sheet on a thing: at the right of the screen docked, and left of the overview in space)
      Windows.Default(Info.ID, (if ball then panelX else right) - Info.WIDTH - 12, top + 130, Info.WIDTH, Info.HEIGHT)
      local _ = Info.Showing()
      -- (a hull on its sheet is shown as the scene draws it, in its base paint, as the fitting window shows the pilot's)
      Info.Show = function(type: string, radius: number, cx: number, cy: number, half: number, aspect: number): boolean
        return Scene.Showcase(scene, game, 0, type, radius, Theme.Px(cx), Theme.Px(cy), Theme.Px(half), "info", aspect)
      end
      if ball then
        -- (a hack under way has the middle of the screen)
        local wasPlain = Im.Plain(true)
        Hack.Draw(session, left + (w.size.x - Hack.WIDTH) / 2, top + 150)
        Im.Plain(wasPlain)
      end
      -- (from here down, what was set out from the screen's left edge is set out from the dock's)
      left = edge - 16
      -- Beside the dock at the foot of the screen, one over another from
      -- the foot up, each there only when there is something to put in
      -- it: where the pilot means to go, with the autopilot's switch
      -- (docked or in space, whatever else is open); the drones; and the
      -- hired pilots. To the new look.
      local wasPlain = Im.Plain(true)
      local stack = bottom - 8
      if session.destination ~= 0 then
        local route = Session.Route(session)
        local name = game.state.galaxy.systems[session.destination].name
        stack -= 34
        Im.Frame(left + 24, stack, 440, 34)
        Im.Strong(`To {name}`, left + 36, stack + 9, 14, Theme.CAUTION)
        Im.Text(`{math.max(0, #route - 1)} {if #route == 2 then "jump" else "jumps"}`, left + 44 + Im.StrongWidth(`To {name}`, 14), stack + 9, 14, Theme.DIM)
        if Im.Toggle(if session.autopilot then "Autopilot on" else "Autopilot", left + 344, stack + 4, 114, 26, session.autopilot,
          "Autopilot") then
          session.autopilot = not session.autopilot
        end
        stack -= 8
      end
      -- The drones, if there are any aboard or out: a row over that.
      if ball then
        local drones = Core.Query.Drones(game)
        if drones.carried + drones.out > 0 then
          local dy = stack - 34
          stack = dy - 8
          Im.Frame(left + 24, dy, 440, 34)
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
        local fy = stack - (64 + 22 * #fleet)
        Im.Frame(left + 24, fy, 440, 64 + 22 * #fleet)
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
        -- The orders, in a menu (2026-11-16, of the strip of buttons there
        -- was): for everybody, or the one picked out; each with why it
        -- cannot be given, where it cannot. The menu drops from Orders,
        -- and a right click on a pilot's row brings it up for them.
        -- (Each order keeps its name for a script: "Fleet:engage", ...)
        local staying = (if one then one.order else fleet[1].order) == "stay"
        type Order = { id: string, label: string, command: State.Command?, warp: boolean? }
        local orders: { Order } = {
          { id = "engage", label = "Engage the target", command = { kind = "FleetOrder", actor = 0, what = "engage", target = target, pilot = only } },
          { id = "follow", label = "Regroup on me", command = { kind = "FleetOrder", actor = 0, what = "follow", pilot = only } },
          { id = "stay", label = if staying then "Follow me again" else "Stay here",
            command = { kind = "FleetOrder", actor = 0, what = if staying then "follow" else "stay", pilot = only } },
          { id = "mine", label = "Mine this belt", command = { kind = "FleetOrder", actor = 0, what = "mine", pilot = only } },
          { id = "patrol", label = "Patrol here", command = { kind = "FleetOrder", actor = 0, what = "patrol", pilot = only } },
          { id = "guard", label = "Guard the ship selected",
            command = { kind = "FleetOrder", actor = 0, what = "guard", pilot = only, target = session.selected } },
          { id = "warp", label = "Warp the fleet to the selected", warp = true },
        }
        local function can(order: Order): (boolean, string?)
          if order.warp then
            return Session.Can(session, "FleetWarp", session.selected), "select where to warp to"
          end
          return Session.CanDo(session, order.command :: State.Command)
        end
        local function give(order: Order)
          if order.warp then
            Session.Order(session, "FleetWarp", session.selected)
          else
            Session.Do(session, order.command :: State.Command)
          end
          fleetMenu = false
        end
        for _, order in orders do
          if Im.Hook(`Fleet:{order.id}`, (can(order))) then
            give(order)
          end
        end
        local engage = orders[1].command :: State.Command
        if Im.Button("Engage", left + 236, fy + 4, 76, 26, (Session.CanDo(session, engage)), "Fleet:engage:now") then
          Session.Do(session, engage)
        end
        if Im.Button(if fleetMenu then "Orders  ^" else "Orders  v", left + 318, fy + 4, 138, 26, true, "Fleet:orders") then
          fleetMenu = not fleetMenu
        end
        Im.Text(if one then "the one picked: click again to let go" else "click a pilot to give one alone an order", left + 36, fy + 38, 11, Im.DIM)
        if fleetMenu then
          menuAt = { x = left + 318, y = fy + 32, orders = orders, can = can, give = give }
        end
        for index, row in fleet do
          local ry = fy + 64 + (index - 1) * 22
          local hull = Ships.byId[row.hull]
          local rowHot, clicked = Im.Row(left + 28, ry - 2, 432, 21, row.id == fleetPicked, `Fleet:pick:{index}`)
          if clicked then
            fleetPicked = if row.id == fleetPicked then 0 else row.id
          end
          if rowHot and Im.RightPressed() then
            fleetPicked, fleetMenu = row.id, true
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
        -- The orders, dropped down over what is under them: a row each,
        -- greyed with its reason where it cannot be given. A click on a
        -- row gives it; one anywhere else puts the menu away.
        if fleetMenu and menuAt then
          local menu = menuAt
          local rows = #menu.orders
          local mw, mh = 250, rows * 26 + 8
          local my = menu.y - mh - 34
          Im.Flat(menu.x - 112, my, mw, mh, Theme.RAISED, 1)
          Im.Edge(menu.x - 112, my, mw, mh, Theme.EDGE_STRONG)
          local over = Im.Inside(menu.x - 112, my, mw, mh)
          for index, order in menu.orders do
            local ok, reason = menu.can(order)
            local oy = my + 4 + (index - 1) * 26
            local hot, clicked = Im.Row(menu.x - 108, oy, mw - 8, 25, false, `Fleet:menu:{order.id}`)
            Im.Text(order.label, menu.x - 98, oy + 5, 13, if ok then Theme.TEXT else Theme.FAINT)
            if hot and not ok and reason then
              Im.Tip(order.label, reason)
            end
            if clicked and ok then
              menu.give(order)
            end
          end
          if Im.Pressed() and not over and not Im.Inside(menu.x, menu.y - 28, 138, 26) then
            fleetMenu = false
          end
          if over then
            Im.over = true
          end
        end
        menuAt = nil
      else
        fleetMenu = false
      end
      Im.Plain(wasPlain)
      -- The windows, over all of that; and over them the menu one of
      -- them has up, whatever is being carried from one to another, and
      -- what is said of the thing the cursor is on.
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
