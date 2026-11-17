--!strict
-- The guide's window: the things there are to do (Core/Character/Guide),
-- each ticked when the pilot has done it, and for the one picked out how
-- it is done. And a second page: the career agents and their lessons
-- (Game/UI/Careers), so that what a lesson in hand wants can be read
-- again in space.
--
-- A window (Game/UI/Windows), open in space or docked, from the Guide
-- button on the dock. Laid out as the market is (2026-11-16): the
-- groups of things to do down the left, with how many of each are done;
-- the steps of the group in the middle; and the step picked on the
-- right, with how it is done. Its pages are "Guide:steps" and
-- "Guide:lessons", a group "Guide:group:<all, or a group>", a step
-- "Guide:step:<id>"; it is shut by "guide:close" or "Guide:close".

local Careers = require("@lt/Game/UI/Careers")
local Core = require("@lt/Core/Api")
local Im = require("@lt/Game/UI/Im")
local Keys = require("@lt/Game/UI/Keys")
local List = require("@lt/Game/UI/List")
local Session = require("@lt/Game/Session")
local Theme = require("@lt/Game/UI/Theme")
local Windows = require("@lt/Game/UI/Windows")

local Guide = {}

Guide.ID = "guide"
Guide.WIDTH, Guide.HEIGHT = 900, 600

local TREE_W, DETAIL_W = 200, 320

local current: Session.Session? = nil
local picked = ""   -- the step whose "how" is shown; "": the first not done
local group = "all"
local lessons = false   -- whether the page shown is the career agents'

function Guide.Open()
  Windows.Open(Guide.ID)
  Windows.Raise(Guide.ID)
end

function Guide.Close()
  Windows.Close(Guide.ID)
end

function Guide.IsOpen(): boolean
  return Windows.IsOpen(Guide.ID)
end

-- Which page is shown ("steps" or "lessons"): given one, that one is.
function Guide.Page(to: string?): string
  if to then
    lessons = to == "lessons"
  end
  return if lessons then "lessons" else "steps"
end

-- Once a frame, before the windows are drawn: whose game it is.
function Guide.Frame(session: Session.Session)
  current = session
end

local function drawSteps(rows: { Core.GuideRow }, x: number, y: number, w: number, h: number)
  -- The groups, in the order the steps come in, with how many of each are done.
  local groups: { string } = {}
  local done: { [string]: number } = {}
  local of: { [string]: number } = {}
  local all = 0
  for _, row in rows do
    local name = row.step.group
    if of[name] == nil then
      table.insert(groups, name)
      of[name], done[name] = 0, 0
    end
    of[name] += 1
    done[name] += if row.done then 1 else 0
    all += if row.done then 1 else 0
  end
  local ty = y + 8
  local function groupRow(id: string, label: string, have: number, outOf: number)
    local _, clicked = List.Row(x + 1, ty, TREE_W - 6, group == id, `Guide:group:{id}`)
    Im.Text(List.Cut(label, TREE_W - 70, 14, false), x + 11, ty + 5, 14, if have == outOf then Theme.DIM else Theme.TEXT)
    local count = `{have}/{outOf}`
    Im.Text(count, x + TREE_W - 14 - Im.TextWidth(count, 12), ty + 6, 12, if have == outOf then Theme.GOOD else Theme.FAINT)
    if clicked and group ~= id then
      group = id
      Im.ScrollTo("guide list", 0)
    end
    ty += List.ROW
  end
  groupRow("all", "Everything", all, #rows)
  for _, name in groups do
    groupRow(name, (string.gsub(name, "^%l", string.upper)), done[name], of[name])
  end
  Im.Flat(x + TREE_W, y, 1, h, Theme.EDGE)

  -- The step picked, else the first not done.
  local shown: Core.GuideRow? = nil
  for _, row in rows do
    if row.step.id == picked then
      shown = row
    end
  end
  if shown == nil then
    for _, row in rows do
      if not row.done then
        shown = row
        break
      end
    end
  end

  -- The steps of the group.
  local lx = x + TREE_W + 1
  local listW = w - TREE_W - 1 - DETAIL_W
  local listed: { Core.GuideRow } = {}
  for _, row in rows do
    if group == "all" or row.step.group == group then
      table.insert(listed, row)
    end
  end
  local top = y
  local first, visible = List.Body("guide list", lx, top, listW, h - List.FOOT, #listed)
  for index = 1, visible do
    local row = listed[index + first]
    if row == nil then
      break
    end
    local rowY = top + (index - 1) * List.ROW
    local hot, clicked = List.Row(lx, rowY, listW - 5, shown ~= nil and shown.step.id == row.step.id, `Guide:step:{row.step.id}`)
    -- (a box, filled when it is done)
    Im.Edge(lx + 10, rowY + 7, 11, 11, if row.done then Theme.GOOD else Theme.EDGE)
    if row.done then
      Im.Flat(lx + 13, rowY + 10, 5, 5, Theme.GOOD)
    end
    local cell = { x = lx + 30, w = listW - 30 - 60, right = false }
    List.Text(row.step.title, cell, rowY, hot, if row.done then Theme.DIM else Theme.TEXT, 14)
    if row.done then
      Im.TextRight("done", lx + listW - 16, rowY + 6, 12, Theme.GOOD)
    end
    if clicked then
      picked = row.step.id
    end
  end
  List.Foot(lx, y + h - List.FOOT, listW, `{all} of {#rows} done`, "pick one to see how it is done")
  Im.Flat(lx + listW, y, 1, h, Theme.EDGE)

  -- How the step picked is done.
  local dx, dw = lx + listW + 15, DETAIL_W - 30
  if shown == nil then
    Im.Wrapped("Everything here is done.", dx, y + 14, dw, 14, Theme.GOOD)
    return
  end
  local line = y + 14
  Im.Pill(if shown.done then "done" else if shown.step.id == picked then "picked" else "next", dx, line,
    if shown.done then Theme.GOOD else Theme.ACCENT)
  line += 26
  line = Im.Wrapped(shown.step.title, dx, line, dw, 17, Theme.TEXT) + 10
  Im.Text("HOW", dx, line, 11, Theme.ACCENT)
  Im.Flat(dx, line + 15, dw, 1, Theme.EDGE)
  line += 22
  Im.Wrapped(Keys.Say(shown.step.how), dx, line, dw, 13, Theme.TEXT)
end

Windows.Kind(Guide.ID, function(_: Windows.Window, x: number, y: number, w: number, h: number)
  local session = current
  if session == nil then
    return
  end
  local was = Im.Plain(true)
  if Im.Hook("Guide:close", true) then
    Guide.Close()
  end
  local rows, count = Core.Query.Guide(session.game)
  -- The two pages: the things there are to do, and the career agents.
  local tx = x + 10
  for _, each in { { "steps", "Things to do" }, { "lessons", "Lessons" } } do
    local pressed, wide = Im.Tab(each[2], tx, y + 4, 28, Guide.Page() == each[1], `Guide:{each[1]}`)
    if pressed then
      Guide.Page(each[1])
    end
    tx += wide + 2
  end
  local note = `{count} of {#rows} done`
  Im.Text(note, x + w - 12 - Im.TextWidth(note, 12), y + 11, 12, Theme.DIM)
  Im.Flat(x + 1, y + 32, w - 2, 1, Theme.EDGE)
  local top, room = y + 33, h - 34
  if lessons then
    -- The agents down the left, and the one picked on the right.
    local status = Core.Query.Careers(session.game)
    local half = 380
    Careers.List(status, x + 8, top + 8, half - 16)
    Im.Flat(x + half, top, 1, room, Theme.EDGE)
    Careers.Detail(session, status, x + half + 16, top + 12, w - half - 32)
  else
    drawSteps(rows, x, top, w, room)
  end
  Im.Plain(was)
end)
Windows.Make(Guide.ID, Guide.ID, "Guide", 300, 140, Guide.WIDTH, Guide.HEIGHT, 820, 420, nil)
Windows.Icon(Guide.ID, "guide")

return Guide
