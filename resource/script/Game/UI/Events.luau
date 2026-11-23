--!strict
-- The events window: what is going on in the galaxy that a pilot could
-- go to (Core/Strategic/Happenings), nearest first, each with where it
-- is, how many jumps off, how long it has left, and a button that sets
-- the pilot's course for it; and under them, what has been left behind.
-- (The owner's ruling, 2026-11-14: "An events window and map marks".)
--
-- A window (Game/UI/Windows), open in space or docked: from the Events
-- button at the foot of the screen (Im.Press "Events"). It only reads
-- the Core, and sets the session's destination. Its close button is
-- "events:close", and a row's button is "Events:course:<id>" with the
-- happening's id.
--
-- Events.Title and Events.Colour say what a happening is called and
-- what colour it goes by, for whoever else shows one (the star map, the
-- line that says one has begun).

local Core = require("@lt/Core/Api")
local Format = require("@lt/Game/Format")
local Im = require("@lt/Game/UI/Im")
local List = require("@lt/Game/UI/List")
local Session = require("@lt/Game/Session")
local Theme = require("@lt/Game/UI/Theme")
local Windows = require("@lt/Game/UI/Windows")

local Events = {}

Events.WIDTH = 1040
Events.HEIGHT = 520

local ID = "events"
local current: Session.Session? = nil
-- What there is to show, as last asked: a screen draws many times a second, and this changes by the minute.
local shown = { age = 1000, epoch = -1, list = {} :: { Core.HappeningInfo }, left = {} :: { Core.AftermathInfo } }

local COLOURS: { [string]: vector } = {
  surge = vector.create(0.95, 0.32, 0.26),
  invasion = vector.create(0.78, 0.42, 0.95),
  sighting = vector.create(0.96, 0.80, 0.30),
  disaster = vector.create(0.96, 0.58, 0.24),
  windfall = vector.create(0.42, 0.86, 0.50),
}

-- The colour a kind of happening goes by.
function Events.Colour(kind: string): vector
  return COLOURS[kind] or Im.TEXT
end

-- What a happening is called, and a line more about it.
function Events.Title(one: { kind: string, what: string, name: string, stage: number, strength: number, kills: number }): (string, string)
  if one.kind == "surge" then
    return "Pirate surge", `bounties doubled there; {one.kills} destroyed, and ten break it`
  elseif one.kind == "invasion" then
    local stage = ({ "a way has opened and their van is through", "they are landed, and dug in", "they are at the stations" })[one.stage]
    local title = if one.what == "great" then "Great invasion: the Drowned in force"
      elseif one.what == "deep5" then "Invasion out of the fifth depth" else "Invasion out of the deep"
    return title, `{stage or "they hold it"}; {math.max(0, math.floor(one.strength))} of them left`
  elseif one.kind == "sighting" then
    if one.what == "captain" then
      return `{one.name}, a pirate captain`, "seen with a small escort: what such a one carries is worth the taking"
    elseif one.what == "derelict" then
      return "A derelict hull", "adrift, and not yet picked over"
    end
    return "A wandering trader", `{one.name}: rare stock, while they stay`
  elseif one.kind == "disaster" then
    if one.what == "gate" then
      return `The gate to {one.name} is closed`, "for repairs: nothing goes through until it is done"
    end
    return `{one.name}: out of use`, "the station cannot do it until it is mended"
  elseif one.kind == "windfall" then
    return "A rich belt found", "rare ore, and nobody's yet"
  end
  return one.kind, ""
end

function Events.Open()
  Windows.Open(ID)
end

function Events.Close()
  Windows.Close(ID)
end

function Events.IsOpen(): boolean
  return Windows.IsOpen(ID)
end

-- Once a frame, before the windows are drawn: whose game it is.
function Events.Frame(session: Session.Session)
  current = session
end

-- What is going on, as the window last asked (and asked again if that was long ago).
function Events.List(session: Session.Session): ({ Core.HappeningInfo }, { Core.AftermathInfo })
  shown.age += 1
  if shown.age > 30 or shown.epoch ~= session.epoch then
    shown.age, shown.epoch = 0, session.epoch
    shown.list = Core.Query.Happenings(session.game)
    shown.left = Core.Query.Aftermath(session.game)
  end
  return shown.list, shown.left
end

local function far(jumps: number, here: boolean): string
  return if here then "here" elseif jumps < 0 then "far off" elseif jumps == 1 then "1 jump" else `{jumps} jumps`
end

-- ---------------------------------------------------------------------
-- The window, laid out as the market is (2026-11-16): what kind of
-- thing is going on down the left, with how many of each; the one list
-- in the middle, nearest first, sorted by its heads; and the one picked
-- on the right, with what it is, where, how long it has, and the way
-- there. What order is left thinner or firmer after them is a kind of
-- its own at the foot of the left.

local KINDS: { { string } } = {
  { "all", "Everything" }, { "surge", "Pirate surges" }, { "invasion", "Invasions" }, { "sighting", "Sightings" },
  { "disaster", "Disasters" }, { "windfall", "Windfalls" },
}
local TREE_W, DETAIL_W = 190, 300
local COLUMNS: { List.Column } = {
  { id = "what", label = "Going on", width = 0 }, { id = "where", label = "Where", width = 150 },
  { id = "jumps", label = "Jumps", width = 56, right = true }, { id = "left", label = "Time left", width = 84, right = true },
}
local LEFT_COLUMNS: { List.Column } = {
  { id = "where", label = "System", width = 0 }, { id = "order", label = "Order", width = 90 },
  { id = "left", label = "For", width = 84, right = true },
}
local kind = "all"
local sortBy, sortDown = "jumps", false
local picked = 0

-- (the sort's key for a happening)
local function keyOf(one: Core.HappeningInfo, by: string): any
  if by == "what" then
    return (Events.Title(one))
  elseif by == "where" then
    return one.where
  elseif by == "left" then
    return one.left
  end
  return if one.here then -1 elseif one.jumps < 0 then math.huge else one.jumps
end

local function drawKinds(list: { Core.HappeningInfo }, behind: { Core.AftermathInfo }, x: number, y: number, w: number)
  local counts: { [string]: number } = { all = #list }
  for _, one in list do
    counts[one.kind] = (counts[one.kind] or 0) + 1
  end
  local rows = table.clone(KINDS)
  table.insert(rows, { "behind", "Left behind" })
  counts.behind = #behind
  for index, each in rows do
    local rowY = y + 8 + (index - 1) * List.ROW + (if each[1] == "behind" then 12 else 0)
    local _, clicked = List.Row(x, rowY, w - 5, kind == each[1], `Events:kind:{each[1]}`)
    if each[1] ~= "all" and each[1] ~= "behind" then
      Im.Flat(x + 8, rowY + 6, 3, List.ROW - 12, Events.Colour(each[1]), 0.9)
    end
    Im.Text(List.Cut(each[2], w - 70, 14, false), x + 18, rowY + 5, 14, Theme.TEXT)
    local count = tostring(counts[each[1]] or 0)
    Im.Text(count, x + w - 14 - Im.TextWidth(count, 12), rowY + 6, 12, Theme.FAINT)
    if clicked then
      kind = each[1]
      Im.ScrollTo("events list", 0)
    end
  end
end

local function drawList(session: Session.Session, list: { Core.HappeningInfo }, x: number, y: number, w: number, h: number)
  local rows: { Core.HappeningInfo } = {}
  for _, one in list do
    if kind == "all" or one.kind == kind then
      table.insert(rows, one)
    end
  end
  if sortBy ~= "jumps" or sortDown then
    table.sort(rows, function(a, b)
      local x1, y1 = keyOf(a, sortBy), keyOf(b, sortBy)
      if x1 ~= y1 then
        return if sortDown then x1 > y1 else x1 < y1
      end
      return a.id < b.id
    end)
  end
  local layout = List.Columns(COLUMNS, x, w - 6)
  local clicked = List.Head("events", x, y, w, COLUMNS, layout, sortBy, sortDown)
  if clicked then
    if sortBy ~= clicked then
      sortBy, sortDown = clicked, false
    elseif clicked ~= "jumps" and not sortDown then
      sortDown = true
    else
      sortBy, sortDown = "jumps", false
    end
  end
  local top = y + List.HEAD
  local room = h - List.HEAD - List.FOOT
  local first, visible = List.Body("events list", x, top, w, room, #rows)
  if #rows == 0 then
    Im.Text(if #list == 0 then "Nothing is going on that anybody has word of." else "Nothing of that kind is going on.", x + 12, top + 12,
      14, Theme.DIM)
  end
  for index = 1, visible do
    local one = rows[index + first]
    if one == nil then
      break
    end
    local rowY = top + (index - 1) * List.ROW
    local hot, chosen = List.Row(x, rowY, w - 5, picked == one.id, `Events:pick:{one.id}`)
    local title, more = Events.Title(one)
    Im.Flat(layout.what.x, rowY + 6, 3, List.ROW - 12, Events.Colour(one.kind), 0.9)
    List.Text(title, layout.what, rowY, hot, Events.Colour(one.kind), 14, false, 10, more)
    List.Text(one.where, layout.where, rowY, hot, Theme.DIM, 13)
    List.Text(far(one.jumps, one.here), layout.jumps, rowY, false, if one.here then Theme.GOOD else Theme.TEXT, 13)
    List.Text(Format.Duration(one.left), layout.left, rowY, false, Theme.DIM, 13)
    if chosen then
      picked = one.id
    end
  end
  local _ = session
  List.Foot(x, y + h - List.FOOT, w, `{#rows} going on`, "the nearest first, unless sorted otherwise")
end

local function drawBehind(behind: { Core.AftermathInfo }, x: number, y: number, w: number, h: number)
  local layout = List.Columns(LEFT_COLUMNS, x, w - 6)
  List.Head("events behind", x, y, w, LEFT_COLUMNS, layout, "", false)
  local top = y + List.HEAD
  local first, visible = List.Body("events list", x, top, w, h - List.HEAD - List.FOOT, #behind)
  if #behind == 0 then
    Im.Text("Nothing that has passed has left a mark.", x + 12, top + 12, 14, Theme.DIM)
  end
  for index = 1, visible do
    local mark = behind[index + first]
    if mark == nil then
      break
    end
    local rowY = top + (index - 1) * List.ROW
    local hot = List.Row(x, rowY, w - 5, false)
    List.Text(mark.name, layout.where, rowY, hot, Theme.TEXT, 14, false, 0, `after {mark.why}`)
    List.Text(if mark.delta < 0 then "thinner" else "firmer", layout.order, rowY, false, if mark.delta < 0 then Theme.BAD else Theme.GOOD, 13)
    List.Text(Format.Duration(mark.left), layout.left, rowY, false, Theme.DIM, 13)
  end
  List.Foot(x, y + h - List.FOOT, w, `{#behind} left behind`, "order kept thinner or firmer for a while after")
end

local function drawPicked(session: Session.Session, list: { Core.HappeningInfo }, x: number, y: number, w: number)
  local one: Core.HappeningInfo? = nil
  for _, each in list do
    if each.id == picked then
      one = each
    end
  end
  local dx, dw = x + 14, w - 28
  if one == nil then
    Im.Text("Choose one to see more of it.", dx, y + 14, 14, Theme.DIM)
    return
  end
  local title, more = Events.Title(one)
  local line = y + 12
  Im.Pill(({ surge = "surge", invasion = "invasion", sighting = "sighting", disaster = "disaster", windfall = "windfall" })[one.kind]
    or one.kind, dx, line, Events.Colour(one.kind))
  line += 26
  line = Im.Wrapped(title, dx, line, dw, 16, Theme.TEXT) + 4
  line = Im.Wrapped(more, dx, line, dw, 13, Theme.DIM) + 14
  Im.Text("WHERE", dx, line, 11, Theme.ACCENT)
  Im.Flat(dx, line + 15, dw, 1, Theme.EDGE)
  line += 22
  Im.Text(List.Cut(one.where, dw, 14, false), dx, line, 14, Theme.TEXT)
  line += 20
  Im.Text(if one.here then "this system" else far(one.jumps, one.here), dx, line, 13, if one.here then Theme.GOOD else Theme.DIM)
  line += 28
  Im.Text("TIME LEFT", dx, line, 11, Theme.ACCENT)
  Im.Flat(dx, line + 15, dw, 1, Theme.EDGE)
  line += 22
  Im.Text(Format.Duration(one.left), dx, line, 14, Theme.TEXT)
  line += 34
  local can = not one.here and one.jumps >= 0 and session.destination ~= one.system
  Im.Tone("primary")
  if Im.Button(if session.destination == one.system then "Course set" else "Set course", dx, line, dw, 30, can, "Events:course") then
    session.destination = one.system
  end
  Im.Because(if one.here then "it is here" elseif one.jumps < 0 then "there is no way there from here" else nil)
end

local function draw(_: Windows.Window, x: number, y: number, width: number, height: number)
  local session = current
  if session == nil then
    return
  end
  local list, behind = Events.List(session)
  -- (every event's own button, by its id, for a script: as the rows had them)
  for _, one in list do
    local can = not one.here and one.jumps >= 0 and session.destination ~= one.system
    if Im.Hook(`Events:course:{one.id}`, can) then
      session.destination = one.system
    end
  end
  local was = Im.Plain(true)
  drawKinds(list, behind, x + 1, y, TREE_W - 1)
  Im.Flat(x + TREE_W, y, 1, height, Theme.EDGE)
  local listW = width - TREE_W - DETAIL_W
  if kind == "behind" then
    drawBehind(behind, x + TREE_W + 1, y, listW - 1, height)
  else
    drawList(session, list, x + TREE_W + 1, y, listW - 1, height)
  end
  Im.Flat(x + TREE_W + listW, y, 1, height, Theme.EDGE)
  drawPicked(session, list, x + TREE_W + listW + 1, y, DETAIL_W - 2)
  Im.Plain(was)
end

Windows.Kind(ID, draw)
Windows.Make(ID, ID, "Events", 420, 150, Events.WIDTH, Events.HEIGHT, 860, 360, nil)
Windows.Icon(ID, "events")

return Events
