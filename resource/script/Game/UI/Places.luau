--!strict
-- Places: every place the pilot has marked, wherever it is (the owner,
-- 2026-11-17, "can you save stations as bookmarks?", and the three
-- things put to them: a place marked by itself, this window, and marks
-- on the star map; "all 3"). A window of its own (Game/UI/Windows),
-- opened from the dock.
--
-- The marks are listed by system, the one the pilot is in first and
-- then the nearest by the way the star map goes (shortest or safest, as
-- it is set there). Each one can be:
--
--   Go      gone to: the autopilot takes the ship there, gate by gate,
--           and then docks at it if it is a station, or warps to it
--   Route   made the star map's destination, without the autopilot
--   Forget  forgotten
--
-- A click on one picks it out, and its name can be changed at the foot.
-- At the top, the station the ship is docked at, or where the ship is
-- in space, is marked.

local Core = require("@lt/Core/Api")
local Im = require("@lt/Game/UI/Im")
local List = require("@lt/Game/UI/List")
local Session = require("@lt/Game/Session")
local State = require("@lt/Core/Kernel/State")
local Theme = require("@lt/Game/UI/Theme")
local Windows = require("@lt/Game/UI/Windows")

local Places = {}

Places.ID = "places"

-- What a mark of a place by itself says it is.
local WHAT: { [string]: string } = {
  station = "station", gate = "stargate", planet = "planet", moon = "moon", belt = "asteroid belt", sun = "star", site = "site",
  wormhole = "wormhole", ice = "ice field",
}

local current: Session.Session? = nil
local picked = 0
local naming, named, sentAt = 0, "", -1

function Places.Open()
  Windows.Open(Places.ID)
  Windows.Raise(Places.ID)
end

function Places.Close()
  Windows.Close(Places.ID)
end

function Places.IsOpen(): boolean
  return Windows.IsOpen(Places.ID)
end

-- Once a frame, before the windows are drawn: whose game it is.
function Places.Frame(session: Session.Session)
  current = session
end

-- Go to a mark: the autopilot takes the ship to its system and then to it.
function Places.Go(session: Session.Session, mark: State.Bookmark)
  session.destination, session.goal, session.autopilot, session.berth = mark.system, mark.id, true, 0
  Session.Say(session, `Autopilot: to {mark.name}`)
end

-- How far a system is, in words, and the jumps (0 here; -1 for no way known).
local function away(session: Session.Session, here: number, system: number): (string, number)
  if system == here then
    return "here", 0
  end
  local way = Session.Way(session, here, system, session.safest)
  if #way < 2 then
    local node = session.game.state.galaxy.systems[system]
    return if node and node.uncharted then "uncharted: no way known" else "no way known", -1
  end
  local jumps = #way - 1
  return `{jumps} {if jumps == 1 then "jump" else "jumps"}`, jumps
end

type Line = { system: number, mark: State.Bookmark?, label: string, jumps: number }

-- The marks, by system: nearest first, and in each system by name.
local function lines(session: Session.Session): { Line }
  local game = session.game
  local here = Core.Query.Player(game).system
  local by: { [number]: { State.Bookmark } } = {}
  local systems: { number } = {}
  for _, mark in Core.Query.Bookmarks(game) do
    if by[mark.system] == nil then
      by[mark.system] = {}
      table.insert(systems, mark.system)
    end
    table.insert(by[mark.system], mark)
  end
  local far: { [number]: number } = {}
  local said: { [number]: string } = {}
  for _, system in systems do
    said[system], far[system] = away(session, here, system)
  end
  table.sort(systems, function(a: number, b: number): boolean
    local fa, fb = if far[a] < 0 then math.huge else far[a], if far[b] < 0 then math.huge else far[b]
    if fa ~= fb then
      return fa < fb
    end
    return a < b
  end)
  local out: { Line } = {}
  for _, system in systems do
    table.insert(out, { system = system, label = said[system], jumps = far[system] })
    local marks = by[system]
    table.sort(marks, function(a: State.Bookmark, b: State.Bookmark): boolean
      if a.name ~= b.name then
        return a.name < b.name
      end
      return a.id < b.id
    end)
    for _, mark in marks do
      table.insert(out, { system = system, mark = mark, label = said[system], jumps = far[system] })
    end
  end
  return out
end

Windows.Kind(Places.ID, function(_: Windows.Window, x: number, y: number, w: number, h: number)
  local session = current
  if session == nil then
    return
  end
  local game = session.game
  local state = game.state
  local player = Core.Query.Player(game)
  local galaxy = state.galaxy
  local was = Im.Plain(true)
  -- Marking where the ship is: the station, docked; the spot, in space.
  local markHere: State.Command = { kind = "Bookmark", actor = 0 }
  local can, why = Session.CanDo(session, markHere)
  Im.Tone("primary")
  Im.Because(why)
  if Im.Button(if player.at ~= 0 then "Bookmark this station" else "Bookmark here", x + 12, y + 10, 170, 26, can, "Places:mark") then
    Session.Do(session, markHere)
  end
  local count = #state.bookmarkIds
  Im.Text(`{count} of {Core.Query.BookmarksMost()} bookmarks`, x + 196, y + 15, 13, Theme.DIM)
  if session.goal ~= 0 and state.bookmarks[session.goal] then
    Im.TextRight(`going to {state.bookmarks[session.goal].name}{if session.autopilot then "" else " (autopilot off)"}`, x + w - 14, y + 15,
      13, Theme.ACCENT)
  end
  local all = lines(session)
  local top = y + 46
  local foot = 46
  local listH = h - (top - y) - foot
  if #all == 0 then
    Im.Text("Nothing is marked yet. Right-click a station, a gate or anything else in space and pick Bookmark,", x + 14, top + 8, 13,
      Theme.FAINT)
    Im.Text("or mark where you are with the button above.", x + 14, top + 26, 13, Theme.FAINT)
  end
  local first, visible = List.Body("places", x + 1, top, w - 2, listH, #all)
  for index = 1, visible do
    local line = all[index + first]
    if line == nil then
      break
    end
    local rowY = top + (index - 1) * List.ROW
    local node = galaxy.systems[line.system]
    local one = line.mark
    if one == nil then
      -- A system's heading: its name, and how far.
      Im.Strong(string.upper(if node then node.name else "?"), x + 12, rowY + 7, 12, if line.jumps == 0 then Theme.ACCENT else Theme.DIM)
      Im.TextRight(line.label, x + w - 14, rowY + 7, 12, Theme.FAINT)
      continue
    end
    local mark: State.Bookmark = one
    local hot, clicked = List.Row(x + 1, rowY, w - 8, mark.id == picked, `Places:row:{mark.id}`)
    if clicked then
      picked = mark.id
    end
    Im.Text(List.Cut(mark.name, w - 420, 14, false), x + 24, rowY + 5, 14, if hot then Theme.TEXT else Theme.TEXT)
    local what = if mark.what then WHAT[mark.what] or mark.what else "a spot in space"
    Im.Text(what, x + w - 390, rowY + 6, 12, Theme.DIM)
    local bx = x + w - 252
    local reach = line.jumps >= 0
    Im.Because(if reach then nil else "No way there is known")
    if Im.Button("Go", bx, rowY + 2, 70, List.ROW - 4, reach, `Places:go:{mark.id}`) then
      Places.Go(session, mark)
    end
    Im.Because(if line.jumps > 0 then nil elseif line.jumps == 0 then "It is in this system" else "No way there is known")
    if Im.Button("Route", bx + 76, rowY + 2, 80, List.ROW - 4, line.jumps > 0, `Places:route:{mark.id}`) then
      session.destination, session.goal, session.autopilot, session.berth = mark.system, mark.id, false, 0
      Session.Say(session, `Destination: {mark.name}`)
    end
    Im.Tone("danger")
    if Im.Button("Forget", bx + 162, rowY + 2, 76, List.ROW - 4, true, `Places:forget:{mark.id}`) then
      Session.Do(session, { kind = "ForgetBookmark", actor = 0, target = mark.id })
      if session.goal == mark.id then
        session.goal = 0
      end
    end
  end
  -- The one picked out: its name.
  local chosen = state.bookmarks[picked]
  local fy = y + h - foot + 8
  Im.Flat(x + 1, fy - 8, w - 2, 1, Theme.EDGE)
  if chosen then
    if naming ~= chosen.id then
      naming, named, sentAt = chosen.id, chosen.name, -1
    end
    Im.Text("Name", x + 14, fy + 6, 13, Theme.DIM)
    named = Im.Words("Places:name", named, x + 64, fy, w - 80, 28, 32)
    if not Im.Typing() and named ~= chosen.name then
      local rename: State.Command = { kind = "RenameBookmark", actor = 0, target = chosen.id, what = named }
      if sentAt >= 0 and state.tick > sentAt then
        -- (the name sent is the place's now, tidied: shown as it is kept)
        named, sentAt = chosen.name, -1
      elseif sentAt < 0 and Session.CanDo(session, rename) then
        Session.Do(session, rename)
        sentAt = state.tick
      elseif sentAt < 0 then
        named = chosen.name
      end
    elseif not Im.Typing() then
      sentAt = -1
    end
  else
    naming = 0
    Im.Text("Pick a bookmark to change its name.", x + 14, fy + 6, 13, Theme.FAINT)
  end
  Im.Plain(was)
end)
Windows.Make(Places.ID, Places.ID, "Bookmarks", 480, 140, 760, 520, 620, 300, nil)
Windows.Icon(Places.ID, "places")

return Places
