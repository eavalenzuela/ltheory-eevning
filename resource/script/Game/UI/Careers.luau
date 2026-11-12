--!strict
-- The career agents' pages (Core/Character/Careers): who they are and
-- how far the pilot has got with each, as a list; and for the one picked
-- out, what its agent has to say: the lessons there are, the one in hand
-- or next to take, what is handed over for it, what it pays, and the
-- button that takes it or reports it done.
--
-- Drawn in two places: the station screen's Careers tab, at the station
-- the agents are at (the list beside the agent), and the guide's window
-- (the list over the agent), which is open anywhere, so that what a
-- lesson wants can be read again in space. A lesson is taken and
-- reported only docked at the agents' station: elsewhere the button
-- says where that is.
--
-- A script picks a career by "Career:<id>", and presses
-- "Lesson:accept:<id>" or "Lesson:report:<id>" (Im.Press).

local Core = require("@lt/Core/Api")
local Format = require("@lt/Game/Format")
local Im = require("@lt/Game/UI/Im")
local Keys = require("@lt/Game/UI/Keys")
local Session = require("@lt/Game/Session")
local Types = require("@lt/Core/Data/Types")

local Careers = {}

local ROW = 46
local GOOD = vector.create(0.45, 0.85, 0.55)

local picked = ""   -- the career whose agent is shown; "": whichever most wants looking at

-- The career whose agent is shown: the one picked out; else the first
-- with a lesson to report, the first with one in hand, the first with
-- one to take.
function Careers.Shown(status: Core.CareersStatus): Core.CareerRow
  local best, rank = status.rows[1], 0
  for _, row in status.rows do
    if row.career.id == picked then
      return row
    end
    local now = if row.taken and row.have >= row.need then 3 elseif row.taken then 2 elseif row.lesson then 1 else 0
    if now > rank then
      best, rank = row, now
    end
  end
  return best
end

-- What a stack of things is called: "Mining Laser", "2 x Scan Probe".
local function named(stack: { type: string, quantity: number }): string
  local name = Types.Info(stack.type).name
  return if stack.quantity == 1 then name else `{Format.Whole(stack.quantity)} x {name}`
end

-- The agents, a row each; a click picks one out. Returns the y below.
function Careers.List(status: Core.CareersStatus, x: number, y: number, width: number): number
  local shown = Careers.Shown(status)
  local line = y
  for _, row in status.rows do
    local career = row.career
    local _, clicked = Im.Row(x, line, width, ROW - 2, shown.career.id == career.id, `Career:{career.id}`)
    if clicked then
      picked = career.id
    end
    local finished = row.lesson == nil
    Im.Text(career.name, x + 10, line + 5, 15, if finished then Im.DIM else Im.TEXT)
    Im.TextRight(`{row.done} / {#career.lessons}`, x + width - 10, line + 6, 13, if finished then GOOD else Im.DIM)
    Im.Text(row.agent, x + 10, line + 25, 12, Im.DIM)
    local lesson = row.lesson
    if lesson == nil then
      Im.TextRight("finished", x + width - 10, line + 25, 12, GOOD)
    elseif row.taken and row.have >= row.need then
      Im.TextRight(`report in: {lesson.title}`, x + width - 10, line + 25, 12, Im.ACCENT)
    elseif row.taken then
      Im.TextRight(`in hand: {lesson.title}`, x + width - 10, line + 25, 12, Im.TEXT)
    else
      Im.TextRight(`next: {lesson.title}`, x + width - 10, line + 25, 12, Im.DIM)
    end
    line += ROW
  end
  return line
end

-- The agent picked out: their lessons, and the one in hand or next.
-- Returns the y below.
function Careers.Detail(session: Session.Session, status: Core.CareersStatus, x: number, y: number, width: number): number
  local row = Careers.Shown(status)
  local career = row.career
  local line = y
  Im.Heading(string.upper(career.name), x, line, 15, Im.DIM)
  Im.TextRight(row.agent, x + width, line + 1, 13, Im.DIM)
  Im.Text(career.about, x, line + 22, 13, Im.DIM)
  line += 48
  -- Their lessons, each ticked when it is done.
  for index, lesson in career.lessons do
    local done, current = index <= row.done, index == row.done + 1
    Im.Fill(x, line + 4, 10, 10, Im.DIM, 0.35)
    if done then
      Im.Fill(x + 2, line + 6, 6, 6, GOOD, 1)
    end
    Im.Text(lesson.title, x + 20, line + 1, 13, if current then Im.TEXT else Im.DIM)
    Im.TextRight(lesson.aim, x + width, line + 2, 12, Im.DIM, if current then 1 else 0.6)
    line += 18
  end
  line += 12

  local lesson = row.lesson
  if lesson == nil then
    Im.Text(`{row.agent} has nothing more to teach.`, x, line, 14, GOOD)
    return line + 24
  end
  Im.Text(lesson.title, x, line, 16, Im.ACCENT)
  line = Im.Wrapped(Keys.Say(lesson.says), x, line + 26, width, 13, Im.TEXT, 18) + 8

  Im.Text("To do", x, line, 12, Im.DIM)
  Im.Text(lesson.aim, x + 92, line - 1, 14, Im.TEXT)
  if row.taken and row.need > 1 then
    Im.TextRight(`{Format.Whole(row.have)} / {Format.Whole(row.need)}`, x + width, line, 13, if row.have >= row.need then GOOD else Im.DIM)
  elseif row.taken and row.have >= row.need then
    Im.TextRight("done", x + width, line, 13, GOOD)
  end
  line += 22
  if #lesson.kit > 0 then
    local kit: { string } = {}
    for _, stack in lesson.kit do
      table.insert(kit, named(stack))
    end
    Im.Text("Handed over", x, line, 12, Im.DIM)
    line = Im.Wrapped(table.concat(kit, ", "), x + 92, line - 1, width - 92, 13, Im.TEXT, 18) + 4
  end
  local pays: { string } = { Format.Credits(lesson.credits) }
  for _, stack in row.gifts do
    table.insert(pays, named(stack))
  end
  Im.Text("Pays", x, line, 12, Im.DIM)
  line = Im.Wrapped(table.concat(pays, ", "), x + 92, line - 1, width - 92, 13, GOOD, 18) + 10

  -- Take it, or report it done; and if that cannot be, why not.
  local kind = if row.taken then "CompleteLesson" else "AcceptLesson"
  local label, id = if row.taken then "Report" else "Accept", if row.taken then `Lesson:report:{career.id}` else `Lesson:accept:{career.id}`
  if Im.Button(label, x, line, 96, 28, row.can, id) then
    Session.Do(session, { kind = kind, actor = 0, what = career.id })
  end
  if not row.can then
    Im.Wrapped(row.why, x + 108, line + 6, width - 108, 13, if status.here then Im.DIM else Im.WARN, 16)
  elseif row.taken then
    Im.Text("It is done: report it.", x + 108, line + 6, 13, GOOD)
  end
  return line + 40
end

-- Pick a career's agent out, as clicking its row would: for scripted
-- runs. "" lets go of it.
function Careers.Pick(id: string)
  picked = id
end

return Careers
