--!strict
-- The scanner window. It has two sides. "Signals": what the ship's
-- scanner shows of the system, the signals it has not resolved yet, the
-- scanning of them and the probes. "Directional": the directional
-- scanner (Core/Tactical/Dscan), which says what ships, wrecks and
-- structures are within a range, all round or in a cone pointed at what
-- is selected or the way the camera looks.
--
-- Open in space, from the Scan button on the overview. Drawn every
-- frame with Game/UI/Im; it reads the Core through queries and acts on
-- it only through the Session. Its buttons' names, for a script
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
local Session = require("@lt/Game/Session")
local State = require("@lt/Core/Kernel/State")

local Scanner = {}

Scanner.WIDTH = 468
Scanner.HEIGHT = 440

local GOOD = vector.create(0.45, 0.85, 0.55)
local KINDS: { [string]: string } = { combat = "pirate den", ore = "hidden belt", gas = "vapour field", relic = "derelict",
  data = "listening post", mission = "camp to clear", keep = "pirate tower", wormhole = "wormhole" }

local open = false
local side: "signals" | "directional" = "signals"

-- The directional scanner: how it is set, and what its last scan had
-- (a scan is of a moment: the list stands until the next one).
local angle, range = 360, 14
local aim: "selected" | "camera" = "selected"
local sightings: { Core.Sighting } = {}
local scans = 0             -- how many have been made
local scannedTick = -1      -- the tick of the last
local scannedIn = 0         -- and the system it was made in
local scannedHow = ""       -- and how it was set

local ROWS = 8

function Scanner.Open()
  open = true
end

function Scanner.Close()
  open = false
end

function Scanner.IsOpen(): boolean
  return open
end

-- What the last directional scan had, and how many scans have been made.
function Scanner.Sightings(): ({ Core.Sighting }, number)
  return sightings, scans
end

-- ('look': the way the camera looks, as the Core has its directions.)
local function drawDirectional(session: Session.Session, x: number, y: number, width: number, height: number, look: vector?)
  local game = session.game
  local state = game.state
  local left, right = x + 16, x + width - 16
  local system = Core.Query.Player(game).system
  -- (a list from another system, or from before a game was loaded, is nobody's)
  if scannedTick > state.tick or (scannedIn ~= 0 and scannedIn ~= system) then
    sightings, scannedTick, scannedIn, scannedHow = {}, -1, 0, ""
  end
  local toward = if session.selected ~= 0 then session.selected else nil
  local body = if toward then Core.Query.Body(game, toward) else nil
  -- A cone is pointed at what is selected, or the way the camera looks.
  local along: { number }? = if aim == "camera" and look then { look.x, look.y, look.z } else nil
  Im.Text("Pointed", left, y + 48, 13, Im.DIM)
  if Im.Toggle("at what is selected", left + 84, y + 42, 170, 24, aim == "selected", "Dscan:aim:selected") then
    aim = "selected"
  end
  if Im.Toggle("where I look", left + 260, y + 42, 170, 24, aim == "camera", "Dscan:aim:camera") then
    aim = "camera"
  end
  local name = if body then body.name else nil
  if #(name or "") > 40 then
    name = string.sub(name :: string, 1, 39) .. "."
  end
  Im.Text(if along then "the way the camera looks: turn it, and scan" elseif name then name else "nothing: select something to point a cone at",
    left + 84, y + 72, 13, if along or name then Im.TEXT else Im.DIM)
  Im.Text("Cone", left, y + 103, 13, Im.DIM)
  for index, degrees in Dscan.ANGLES do
    local label = if degrees == 360 then "all round" else `{degrees} deg`
    if Im.Toggle(label, left + 84 + (index - 1) * 88, y + 96, 82, 26, angle == degrees, `Dscan:angle:{degrees}`) then
      angle = degrees
    end
  end
  Im.Text("Range", left, y + 135, 13, Im.DIM)
  for index, reach in Dscan.RANGES do
    if Im.Toggle(`{reach} AU`, left + 84 + (index - 1) * 88, y + 128, 82, 26, range == reach, `Dscan:range:{reach}`) then
      range = reach
    end
  end
  local _, can, whyNot = Core.Query.Directional(game, toward, angle, range * Constants.AU, along)
  if Im.Button("Scan", left, y + 164, 110, 28, can, "Dscan:scan") then
    sightings = Core.Query.Directional(game, toward, angle, range * Constants.AU, along)
    -- (a new list is read from its top)
    Im.ScrollTo("sightings", 0)
    scans += 1
    scannedTick, scannedIn = state.tick, system
    scannedHow = if angle == 360 then `all round, {range} AU`
      elseif along then `{angle} deg where the camera looked, {range} AU`
      else `{angle} deg at {name or "?"}, {range} AU`
  end
  if not can then
    Im.Text(tostring(whyNot), left + 122, y + 171, 13, Im.DIM)
  elseif scannedTick >= 0 then
    local age = math.floor((state.tick - scannedTick) * Constants.TICK)
    Im.Text(`{#sightings} found, {if age <= 0 then "now" else `{age} s ago`}`, left + 122, y + 171, 13, GOOD)
    Im.TextRight(scannedHow, right, y + 196, 11, Im.DIM)
  else
    Im.Text("ready", left + 122, y + 171, 13, GOOD)
  end

  local line = y + 214
  if scannedTick >= 0 and #sightings == 0 then
    Im.Text("Nothing there.", left, line, 13, Im.DIM, 0.8)
  end
  -- (eight at a time: the wheel brings the rest, as it does the signals)
  local first = Im.Scroll("sightings", left - 4, line, width - 24, ROWS * 22, #sightings, ROWS)
  for index = first + 1, math.min(#sightings, first + ROWS) do
    local sighting = sightings[index]
    Im.Text(sighting.name, left, line, 14, Im.TEXT)
    Im.Text(sighting.type, left + 210, line + 1, 13, Im.DIM)
    if sighting.onGrid then
      Im.TextRight("here", right, line + 1, 12, GOOD)
    end
    line += 22
  end
  Im.Text("It says what is there and not where: that is worked out by", left, y + height - 46, 12, Im.DIM, 0.8)
  Im.Text("narrowing the range, and the cone, on a thing or where you look.", left, y + height - 30, 12, Im.DIM, 0.8)
end

-- ('look': the way the camera looks, for a cone that is pointed by it.)
function Scanner.Draw(session: Session.Session, x: number, y: number, look: vector?)
  if not open then
    return
  end
  local game = session.game
  local width, height = Scanner.WIDTH, Scanner.HEIGHT
  local left, right = x + 16, x + width - 16
  Im.Panel(x, y, width, height)
  Im.Heading("SCANNER", left, y + 12, 16, Im.DIM)
  if Im.Button("x", x + width - 38, y + 10, 24, 24, true, "Scanner:close") then
    open = false
    return
  end
  if Im.Toggle("Signals", left + 108, y + 8, 84, 26, side == "signals", "Scanner:signals") then
    side = "signals"
  end
  if Im.Toggle("Directional", left + 196, y + 8, 104, 26, side == "directional", "Scanner:directional") then
    side = "directional"
  end
  if side == "directional" then
    drawDirectional(session, x, y, width, height, look)
    return
  end
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
  if Im.Button("Scan", left, y + 44, 110, 28, can, "Scan") then
    Session.Do(session, scan)
  end
  Im.Text(if wait > 0 then `cycling: {math.ceil(wait)} s` elseif can then "ready" else tostring(whyNot), left + 122, y + 51, 13,
    if can then GOOD else Im.DIM)
  Im.TextRight(`{#sites} in this system`, right, y + 51, 13, Im.DIM)
  -- The probes: one put out where the ship is, and all of them called in.
  local launch: State.Command = { kind = "LaunchProbe", actor = 0 }
  local canLaunch, whyNotLaunch = Session.CanDo(session, launch)
  if Im.Button("Launch probe", left, y + 78, 110, 24, canLaunch, "Probe:launch") then
    Session.Do(session, launch)
  end
  local recall: State.Command = { kind = "RecallProbes", actor = 0 }
  if Im.Button("Recall", left + 116, y + 78, 70, 24, (Session.CanDo(session, recall)), "Probe:recall") then
    Session.Do(session, recall)
  end
  Im.Text(if probes.out > 0 or canLaunch then `{probes.here} out here, {probes.carried} in the hold` else tostring(whyNotLaunch), left + 196,
    y + 83, 12, Im.DIM)

  local line = y + 116
  if #sites == 0 then
    Im.Text("Nothing but what is on the charts.", left, line, 13, Im.DIM, 0.8)
  end
  -- (seven at a time: the wheel brings the rest)
  local first = Im.Scroll("signals", left - 4, line, width - 24, 7 * 38, #sites, 7)
  for index = first + 1, math.min(#sites, first + 7) do
    local site = sites[index]
    Im.Text(site.name, left, line, 14, if site.found then Im.TEXT else Im.DIM)
    -- (what it is; or which planet it is by, and whether it wants a probe taken there)
    -- (a wormhole says how big a hull it lets through)
    local through = if site.found and site.kind == "wormhole" then Core.Query.Wormhole(game, site.id) else nil
    local about = if through then `{through.sizeName} wormhole: up to {through.lets}`
      elseif site.found then KINDS[site.kind] or site.kind
      elseif site.faint then `too faint: wants a probe by {site.near}`
      elseif site.near ~= "" then `by {site.near}` .. (if site.probes > 0 then `, {site.probes} {if site.probes == 1 then "probe" else "probes"} on it` else "")
      else "unresolved"
    Im.Text(about, left, line + 17, 12, if site.faint then Im.WARN else Im.DIM)
    -- how far the scanner has got with it
    Im.Fill(left + 190, line + 8, 110, 5, Im.DIM, 0.25)
    Im.Fill(left + 190, line + 8, 110 * math.clamp(site.strength, 0, 1), 5, if site.found then GOOD else Im.ACCENT, 0.95)
    Im.Text(`{math.floor(site.strength * 100)}%`, left + 308, line + 2, 12, Im.DIM)
    if site.found then
      Im.TextRight(Format.Distance(site.distance), right - 66, line + 18, 11, Im.DIM)
      if Im.Button("Warp", right - 58, line + 2, 58, 24, (Session.Can(session, "WarpTo", site.id, 0)), `SiteWarp:{index}`) then
        session.selected = site.id
        Session.Order(session, "WarpTo", site.id, 0)
      end
    end
    line += 38
  end
  Im.Text("Every scan brings each signal nearer to found, and a probe", left, y + height - 46, 12, Im.DIM, 0.8)
  Im.Text("put out by the planet it is near makes each scan worth more.", left, y + height - 30, 12, Im.DIM, 0.8)
end

return Scanner
