--!strict
-- The scanner window. It has two sides. "Signals": what the ship's
-- scanner shows of the system, the signals it has not resolved yet, the
-- scanning of them and the probes. "Directional": the directional
-- scanner (Core/Tactical/Dscan), which says what ships, wrecks and
-- structures are within a range, all round or in a cone pointed at what
-- is selected or the way the camera looks.
--
-- Open in space, from the Scan button on the overview or the dock: a
-- window (Game/UI/Windows) since 2026-11-16. It reads the Core through
-- queries and acts on it only through the Session. Its buttons' names, for a script
-- (Im.Press): "Scanner:close", "Scanner:signals", "Scanner:directional";
-- "Scan", "Probe:launch", "Probe:recall" and "SiteWarp:<n>" for the nth
-- site listed; "Dscan:scan", "Dscan:angle:<degrees>" (360, 90, 30, 10),
-- "Dscan:range:<AU>" (14, 5, 1, 0.1), and "Dscan:aim:selected" and
-- "Dscan:aim:camera" for what a cone is pointed by.

local Constants = require("@lt/Core/Data/Constants")
local Core = require("@lt/Core/Api")
local Dscan = require("@lt/Core/Tactical/Dscan")
local Format = require("@lt/Game/Format")
local Im = require("@lt/Game/UI/Im")
local List = require("@lt/Game/UI/List")
local Session = require("@lt/Game/Session")
local State = require("@lt/Core/Kernel/State")
local Signs = require("@lt/Game/UI/Signs")
local Theme = require("@lt/Game/UI/Theme")
local SystemMap = require("@lt/Game/UI/SystemMap")
local Windows = require("@lt/Game/UI/Windows")

local Scanner = {}

Scanner.ID = "scanner"
Scanner.WIDTH = 820
Scanner.HEIGHT = 460
local KINDS: { [string]: string } = { combat = "pirate den", ore = "hidden belt", gas = "vapour field", relic = "derelict",
  data = "listening post", mission = "camp to clear", keep = "pirate tower", wormhole = "wormhole" }

local open = false
local side: "signals" | "directional" = "signals"
local current: Session.Session? = nil
local currentLook: vector? = nil
-- (whether the window was shown last frame: shut from its corner then, the scanner is shut)
local shown = false

-- The directional scanner: how it is set, and what its last scan had
-- (a scan is of a moment: the list stands until the next one).
local angle, range = 360, 14
local aim: "selected" | "camera" = "selected"
local sightings: { Core.Sighting } = {}
local scans = 0             -- how many have been made
local scannedTick = -1      -- the tick of the last
local scannedIn = 0         -- and the system it was made in
local scannedHow = ""       -- and how it was set

function Scanner.Open()
  open = true
end

function Scanner.Close()
  open = false
end

-- Once a frame, before the windows are drawn: whose game it is, the way
-- the camera looks, and whether the pilot is in space (the scanner is
-- shown only there, and open again on the next undocking if it was).
function Scanner.Frame(session: Session.Session, look: vector?, inSpace: boolean)
  current, currentLook = session, look
  if shown and not Windows.IsOpen(Scanner.ID) then
    open = false
  end
  local show = open and inSpace
  if show ~= Windows.IsOpen(Scanner.ID) then
    if show then
      Windows.Open(Scanner.ID)
    else
      Windows.Close(Scanner.ID)
    end
  end
  shown = show
end

function Scanner.IsOpen(): boolean
  return open
end

-- What the last directional scan had, and how many scans have been made.
function Scanner.Sightings(): ({ Core.Sighting }, number)
  return sightings, scans
end

-- ---------------------------------------------------------------------
-- The window (Game/UI/Windows), laid out as the market is since
-- 2026-11-16: the two sides as pages along the top, what is done on
-- that side in a strip under them, and what it found as the one list.

local SIGNAL_COLUMNS: { List.Column } = {
  { id = "name", label = "Signal", width = 0 }, { id = "what", label = "What it is", width = 230 },
  { id = "strength", label = "Found", width = 150 }, { id = "distance", label = "Distance", width = 90, right = true },
  { id = "warp", label = "", width = 66 },
}
local SIGHT_COLUMNS: { List.Column } = {
  { id = "name", label = "Name", width = 0 }, { id = "type", label = "Type", width = 220 }, { id = "kind", label = "Kind", width = 90 },
  { id = "grid", label = "", width = 60, right = true },
}

-- ('look': the way the camera looks, as the Core has its directions.)
local function drawDirectional(session: Session.Session, x: number, y: number, width: number, height: number, look: vector?)
  local game = session.game
  local state = game.state
  local left = x + 12
  local system = Core.Query.Player(game).system
  -- (a list from another system, or from before a game was loaded, is nobody's)
  if scannedTick > state.tick or (scannedIn ~= 0 and scannedIn ~= system) then
    sightings, scannedTick, scannedIn, scannedHow = {}, -1, 0, ""
  end
  local toward = if session.selected ~= 0 then session.selected else nil
  local body = if toward then Core.Query.Body(game, toward) else nil
  -- A cone is pointed at what is selected, or the way the camera looks.
  local along: { number }? = if aim == "camera" and look then { look.x, look.y, look.z } else nil
  local cx = left
  Im.Text("Cone", cx, y + 13, 12, Theme.FAINT)
  cx += 40
  for _, degrees in Dscan.ANGLES do
    local pressed, wide = List.Chip(if degrees == 360 then "All round" else `{degrees} deg`, cx, y + 8, angle == degrees, `Dscan:angle:{degrees}`)
    if pressed then
      angle = degrees
    end
    cx += wide + 4
  end
  cx += 14
  Im.Text("Range", cx, y + 13, 12, Theme.FAINT)
  cx += 46
  for _, reach in Dscan.RANGES do
    local pressed, wide = List.Chip(`{reach} AU`, cx, y + 8, range == reach, `Dscan:range:{reach}`)
    if pressed then
      range = reach
    end
    cx += wide + 4
  end
  cx = left
  Im.Text("Pointed", cx, y + 45, 12, Theme.FAINT)
  cx += 56
  for _, each in { { "selected", "At what is selected" }, { "camera", "Where I look" } } do
    local pressed, wide = List.Chip(each[2], cx, y + 40, aim == each[1], `Dscan:aim:{each[1]}`)
    if pressed then
      aim = each[1] :: any
    end
    cx += wide + 4
  end
  local name = if body then body.name else nil
  Im.Text(List.Cut(if along then "the way the camera looks: turn it, and scan" elseif name then name else "nothing: select something to point a cone at",
    x + width - cx - 150, 13, false), cx + 10, y + 45, 13, if along or name then Theme.TEXT else Theme.DIM)
  local _, can, whyNot = Core.Query.Directional(game, toward, angle, range * Constants.AU, along)
  Im.Tone("primary")
  if Im.Button("Scan", x + width - 132, y + 8, 120, 56, can, "Dscan:scan") then
    sightings = Core.Query.Directional(game, toward, angle, range * Constants.AU, along)
    -- (a new list is read from its top)
    Im.ScrollTo("sightings", 0)
    scans += 1
    scannedTick, scannedIn = state.tick, system
    scannedHow = if angle == 360 then `all round, {range} AU`
      elseif along then `{angle} deg where the camera looked, {range} AU`
      else `{angle} deg at {name or "?"}, {range} AU`
  end
  Im.Because(whyNot)
  Im.Flat(x + 1, y + 72, width - 2, 1, Theme.EDGE)

  local top = y + 73
  local layout = List.Columns(SIGHT_COLUMNS, x, width - 6)
  List.Head("sightings head", x, top, width, SIGHT_COLUMNS, layout, "", false)
  local body0 = top + List.HEAD
  local first, visible = List.Body("sightings", x, body0, width, height - (body0 - y) - List.FOOT, #sightings)
  if scannedTick >= 0 and #sightings == 0 then
    Im.Text("Nothing there.", x + 12, body0 + 10, 14, Theme.DIM)
  elseif scannedTick < 0 then
    Im.Text("It says what is there and not where: that is worked out by narrowing the range, and the cone, on a thing or where you look.",
      x + 12, body0 + 10, 13, Theme.DIM)
  end
  for index = 1, visible do
    local sighting = sightings[index + first]
    if sighting == nil then
      break
    end
    local rowY = body0 + (index - 1) * List.ROW
    local hot = List.Row(x, rowY, width - 5, false)
    List.Text(sighting.name, layout.name, rowY, hot, Theme.TEXT, 14)
    List.Text(sighting.type, layout.type, rowY, hot, Theme.DIM, 13)
    List.Text(sighting.kind, layout.kind, rowY, false, Theme.FAINT, 12)
    if sighting.onGrid then
      List.Text("here", layout.grid, rowY, false, Theme.GOOD, 12)
    end
  end
  local age = if scannedTick >= 0 then math.floor((state.tick - scannedTick) * Constants.TICK) else 0
  List.Foot(x, y + height - List.FOOT, width,
    if scannedTick >= 0 then `{#sightings} found, {if age <= 0 then "now" else `{age} s ago`}` elseif can then "ready" else tostring(whyNot),
    scannedHow)
end

local function drawSignals(session: Session.Session, x: number, y: number, width: number, height: number)
  local game = session.game
  local left = x + 12
  local listed, wait, probes = Core.Query.Sites(game)
  -- (what is still to be found first: what is found is on the overview too)
  local sites: { Core.SiteStatus } = {}
  for _, site in listed do
    if not site.found then
      table.insert(sites, site)
    end
  end
  for _, site in listed do
    if site.found then
      table.insert(sites, site)
    end
  end
  local scan: State.Command = { kind = "Scan", actor = 0 }
  local can, whyNot = Session.CanDo(session, scan)
  Im.Tone("primary")
  if Im.Button("Scan", left, y + 8, 110, 28, can, "Scan") then
    Session.Do(session, scan)
  end
  Im.Text(if wait > 0 then `cycling: {math.ceil(wait)} s` elseif can then "ready" else tostring(whyNot), left + 122, y + 15, 13,
    if can then Theme.GOOD else Theme.DIM)
  -- The probes: put out round the ship, and all of them called in; and
  -- the system map, where they are put where they are wanted.
  local launch: State.Command = { kind = "LaunchProbe", actor = 0 }
  local canLaunch, whyNotLaunch = Session.CanDo(session, launch)
  local px = x + width - 12 - 120 - 6 - 90 - 6 - 110
  Im.Because(whyNotLaunch)
  if Im.Button("Launch probes", px, y + 8, 120, 28, canLaunch, "Probe:launch") then
    Session.Do(session, launch)
  end
  local recall: State.Command = { kind = "RecallProbes", actor = 0 }
  if Im.Button("Recall", px + 126, y + 8, 90, 28, (Session.CanDo(session, recall)), "Probe:recall") then
    Session.Do(session, recall)
  end
  if Im.Button("System map", px + 222, y + 8, 110, 28, true, "Scanner:systemmap") then
    SystemMap.Open()
  end
  local probeLine = `{probes.here} probes out here, {probes.carried} in the hold`
  Im.Text(probeLine, px - 16 - Im.TextWidth(probeLine, 12), y + 16, 12, Theme.DIM)
  Im.Flat(x + 1, y + 44, width - 2, 1, Theme.EDGE)

  local top = y + 45
  local layout = List.Columns(SIGNAL_COLUMNS, x, width - 6)
  List.Head("signals head", x, top, width, SIGNAL_COLUMNS, layout, "", false)
  local body0 = top + List.HEAD
  local first, visible = List.Body("signals", x, body0, width, height - (body0 - y) - List.FOOT, #sites)
  if #sites == 0 then
    Im.Text("Nothing but what is on the charts.", x + 12, body0 + 10, 14, Theme.DIM)
  end
  for row = 1, visible do
    local index = row + first
    local site = sites[index]
    if site == nil then
      break
    end
    local rowY = body0 + (row - 1) * List.ROW
    local hot = List.Row(x, rowY, width - 5, false)
    -- (its sign: what kind of site, once found; a signal till then)
    local signed = Signs.Draw(Signs.Site(site.kind, site.name), layout.name.x + 9, rowY + 12, Signs.SIZE,
      if site.found then Theme.ACCENT else Theme.DIM)
    List.Text(site.name, layout.name, rowY, hot, if site.found then Theme.TEXT else Theme.DIM, 14, false, if signed then 22 else 0)
    -- (what it is; or which planet it is by, and whether it wants a probe taken there; a wormhole says how big a hull it lets through)
    local through = if site.found and site.kind == "wormhole" then Core.Query.Wormhole(game, site.id) else nil
    local about = if through then `{through.sizeName} wormhole: up to {through.lets}, mass {through.strain}`
      elseif site.found then KINDS[site.kind] or site.kind
      elseif site.scan then `{site.scan.probes} {if site.scan.probes == 1 then "probe" else "probes"} read it`
        .. (if site.near ~= "" then `, by {site.near}` else "")
      elseif site.faint then `too faint: put probes over it, by {site.near}`
      elseif site.near ~= "" then `by {site.near}`
      else "unresolved"
    List.Text(about, layout.what, rowY, hot, if site.faint then Theme.CAUTION else Theme.DIM, 13)
    -- how far the scanner has got with it
    local bar = layout.strength
    Im.Flat(bar.x, rowY + 10, bar.w - 44, 5, Theme.EDGE)
    Im.Flat(bar.x, rowY + 10, (bar.w - 44) * math.clamp(site.strength, 0, 1), 5, if site.found then Theme.GOOD else Theme.ACCENT)
    Im.Text(`{math.floor(site.strength * 100)}%`, bar.x + bar.w - 38, rowY + 5, 12, Theme.DIM)
    if site.found then
      List.Text(Format.Distance(site.distance), layout.distance, rowY, false, Theme.DIM, 12)
      if Im.Button("Warp", layout.warp.x + 4, rowY + 2, layout.warp.w - 8, List.ROW - 4, (Session.Can(session, "WarpTo", site.id, 0)),
        `SiteWarp:{index}`) then
        session.selected = site.id
        Session.Order(session, "WarpTo", site.id, 0)
      end
    end
  end
  List.Foot(x, y + height - List.FOOT, width, `{#sites} in this system`,
    "the ship's scanner finds belts, clouds and wormholes; probes, placed on the system map, find everything")
end

Windows.Kind(Scanner.ID, function(_: Windows.Window, x: number, y: number, width: number, height: number)
  local session = current
  if session == nil then
    return
  end
  local was = Im.Plain(true)
  if Im.Hook("Scanner:close", true) then
    open = false
    Windows.Close(Scanner.ID)
  end
  local tx = x + 10
  for _, each in { { "signals", "Signals" }, { "directional", "Directional" } } do
    local pressed, wide = Im.Tab(each[2], tx, y + 4, 28, side == each[1], `Scanner:{each[1]}`)
    if pressed then
      side = each[1] :: any
    end
    tx += wide + 2
  end
  Im.Flat(x + 1, y + 32, width - 2, 1, Theme.EDGE)
  if side == "directional" then
    drawDirectional(session, x, y + 33, width, height - 33, currentLook)
  else
    drawSignals(session, x, y + 33, width, height - 33)
  end
  Im.Plain(was)
end)
Windows.Make(Scanner.ID, Scanner.ID, "Scanner", 300, 150, Scanner.WIDTH, Scanner.HEIGHT, 700, 380, nil)
Windows.Icon(Scanner.ID, "scanner")

return Scanner
