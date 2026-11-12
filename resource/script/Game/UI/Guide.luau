--!strict
-- The guide's window: the things there are to do (Core/Character/Guide),
-- group by group, each ticked when the pilot has done it, and for the
-- one picked out a line on how it is done. And a second page: the
-- career agents and their lessons (Game/UI/Careers), so that what a
-- lesson in hand wants can be read again in space.
--
-- Open in space or docked, from the Guide button by the pilot's name.
-- Drawn every frame with Game/UI/Im. Its close button is "Guide:close",
-- and its pages are "Guide:steps" and "Guide:lessons" (Im.Press).

local Careers = require("@lt/Game/UI/Careers")
local Core = require("@lt/Core/Api")
local Im = require("@lt/Game/UI/Im")
local Session = require("@lt/Game/Session")

local Guide = {}

Guide.WIDTH = 468

local ROW = 20
local DONE = vector.create(0.45, 0.85, 0.55)

local open = false
local picked = ""   -- the step whose "how" is shown; "": the first not done
local lessons = false   -- whether the page shown is the career agents'

function Guide.Open()
  open = true
end

function Guide.Close()
  open = false
end

function Guide.IsOpen(): boolean
  return open
end

-- Which page is shown ("steps" or "lessons"): given one, that one is.
function Guide.Page(to: string?): string
  if to then
    lessons = to == "lessons"
  end
  return if lessons then "lessons" else "steps"
end

-- A line of text broken in two at a space, if it is longer than 'limit'.
local function broken(text: string, limit: number): (string, string)
  if #text <= limit then
    return text, ""
  end
  local at = limit
  while at > 1 and string.sub(text, at, at) ~= " " do
    at -= 1
  end
  return string.sub(text, 1, at - 1), string.sub(text, at + 1)
end

function Guide.Draw(session: Session.Session, x: number, y: number)
  if not open then
    return
  end
  local rows, count = Core.Query.Guide(session.game)
  local groups = 0
  for index, row in rows do
    groups += if index == 1 or rows[index - 1].step.group ~= row.step.group then 1 else 0
  end
  local width = Guide.WIDTH
  local height = 46 + #rows * ROW + groups * 30 + 78
  local left = x + 16
  Im.Panel(x, y, width, height)
  Im.Heading(`GUIDE  {count} / {#rows}`, left, y + 12, 16, Im.DIM)
  -- The two pages: the things there are to do, and the career agents.
  if Im.Toggle("Things to do", x + 150, y + 9, 110, 26, not lessons, "Guide:steps") then
    lessons = false
  end
  if Im.Toggle("Lessons", x + 264, y + 9, 90, 26, lessons, "Guide:lessons") then
    lessons = true
  end
  if Im.Button("x", x + width - 38, y + 10, 24, 24, true, "Guide:close") then
    open = false
    return
  end
  if lessons then
    local status = Core.Query.Careers(session.game)
    local below = Careers.List(status, x + 8, y + 50, width - 16)
    Careers.Detail(session, status, left, below + 14, width - 32)
    return
  end

  -- What is shown at the foot: the step picked out, else the first not done.
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

  local line = y + 44
  local group = ""
  for _, row in rows do
    local step = row.step
    if step.group ~= group then
      group = step.group
      Im.Heading(string.upper(group), left, line + 8, 13, Im.DIM)
      line += 30
    end
    local _, clicked = Im.Row(x + 4, line, width - 8, ROW, shown ~= nil and shown.step.id == step.id)
    if clicked then
      picked = step.id
    end
    -- a box, filled when it is done
    Im.Fill(left, line + 6, 10, 10, Im.DIM, 0.35)
    if row.done then
      Im.Fill(left + 2, line + 8, 6, 6, DONE, 1)
    end
    Im.Text(step.title, left + 20, line + 3, 14, if row.done then Im.DIM else Im.TEXT)
    if row.done then
      Im.TextRight("done", x + width - 16, line + 4, 12, DONE)
    end
    line += ROW
  end

  line += 10
  if shown then
    local first, second = broken(shown.step.how, 62)
    Im.Text(if shown.done then shown.step.title else `Next: {shown.step.title}`, left, line, 14, Im.ACCENT)
    Im.Text(first, left, line + 22, 13, Im.TEXT)
    Im.Text(second, left, line + 40, 13, Im.TEXT)
  else
    Im.Text("Everything here is done.", left, line, 14, DONE)
  end
end

return Guide
