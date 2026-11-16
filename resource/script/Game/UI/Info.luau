--!strict
-- The information window: everything there is to say about one type of
-- item (Core/Data/Facts), with its icon, in a panel beside whatever
-- opened it. A row that names another item opens that item's; Back
-- returns.
--
--   Info.Open("frigate.battleaxe")      (GameDebug.Info does this)
--   Info.Draw(x, y)                  every frame; draws nothing while shut

local Facts = require("@lt/Core/Data/Facts")
local Im = require("@lt/Game/UI/Im")
local Theme = require("@lt/Game/UI/Theme")
local ItemIcon = require("@lt/Game/UI/ItemIcon")
local Scene = require("@lt/Game/View/Scene")
local Ships = require("@lt/Core/Data/Ships")

local Info = {}

Info.WIDTH = 400
Info.HEIGHT = 600

local ROW = 20
local SIZE = 13

-- How tall the picture of a hull is, at the top of its sheet.
local PICTURE = 150

local showing: string? = nil
local history: { string } = {}
local turning = 0

-- Show the sheet of a type. False if there is no such type.
function Info.Open(type: string): boolean
  if Facts.Of(type) == nil then
    return false
  end
  if showing and showing ~= type then
    table.insert(history, showing)
  end
  showing = type
  Im.ScrollTo("info", 0)
  return true
end

function Info.Close()
  showing = nil
  table.clear(history)
end

-- The type whose sheet is open, or "".
function Info.Showing(): string
  return showing or ""
end

-- A name that opens the sheet of 'type' when clicked: for lists of items.
function Info.Name(type: string, label: string, x: number, y: number, size: number, color: vector): boolean
  if Im.Link(label, x, y, size, color, `Info:{type}`) then
    Info.Open(type)
    return true
  end
  return false
end

-- 'text' in lines no wider than 'width'.
local function wrap(text: string, size: number, width: number): { string }
  local lines: { string } = {}
  local line = ""
  for word in string.gmatch(text, "%S+") do
    local longer = if line == "" then word else `{line} {word}`
    if line ~= "" and Im.TextWidth(longer, size) > width then
      table.insert(lines, line)
      line = word
    else
      line = longer
    end
  end
  if line ~= "" then
    table.insert(lines, line)
  end
  return lines
end

-- 'text', cut short with dots if it is wider than 'width'.
local function fit(text: string, size: number, width: number): string
  if Im.TextWidth(text, size) <= width then
    return text
  end
  local cut = text
  while #cut > 1 and Im.TextWidth(cut .. "...", size) > width do
    cut = string.sub(cut, 1, #cut - 1)
  end
  return cut .. "..."
end

type Line = { kind: "note" | "title" | "row" | "gap", text: string, value: string, link: string? }

-- The sheet as lines of the window. A row whose label and value do not
-- fit side by side takes two: the value goes under, to the right.
local function lines(sheet: Facts.Sheet, width: number): { Line }
  local out: { Line } = {}
  for _, text in wrap(sheet.note, SIZE, width) do
    table.insert(out, { kind = "note", text = text, value = "" })
  end
  for _, section in sheet.sections do
    if #out > 0 then
      table.insert(out, { kind = "gap", text = "", value = "" })
    end
    table.insert(out, { kind = "title", text = string.upper(section.title), value = "" })
    for _, row in section.rows do
      if Im.TextWidth(row.label, SIZE) + Im.TextWidth(row.value, SIZE) + 24 > width then
        table.insert(out, { kind = "row", text = row.label, value = "", link = row.link })
        table.insert(out, { kind = "row", text = "", value = fit(row.value, SIZE, width) })
      else
        table.insert(out, { kind = "row", text = row.label, value = row.value, link = row.link })
      end
    end
  end
  return out
end

-- Draw the window with its top-left corner at (x, y), if it is open.
function Info.Draw(x: number, y: number)
  local type = showing
  local sheet = if type then Facts.Of(type) else nil
  if type == nil or sheet == nil then
    showing = nil
    return
  end
  local width, height = Info.WIDTH, Info.HEIGHT
  Im.Panel(x, y, width, height)
  ItemIcon.Draw(type, x + 16, y + 14, 40)
  Im.Heading(fit(sheet.name, 17, width - 68 - 100), x + 68, y + 12, 17, Im.TEXT)
  Im.Text(sheet.kind, x + 68, y + 37, SIZE, Im.DIM)
  if Im.Button("x", x + width - 38, y + 12, 24, 24, true, "Info:close") then
    Info.Close()
    return
  end
  if #history > 0 and Im.Button("Back", x + width - 98, y + 12, 54, 24, true, "Info:back") then
    showing = table.remove(history)
    Im.ScrollTo("info", 0)
    return
  end

  local left, right = x + 16, x + width - 18
  local top = y + 70
  -- A hull has its picture first: the model the game draws for it,
  -- turning.
  local hull = Ships.byId[type]
  if hull then
    local model = Scene.Preview(type, hull.radius)
    turning += 0.3 * FrameTimer_Get()
    local bound = Renderable_GetBound(model)
    local size = bound.upper - bound.lower
    local fov = math.rad(0.02)
    local distance = math.max(size.x, size.y, size.z) * 0.36 / math.tan(0.5 * fov)
    local from = vector.normalize(vector.create(math.cos(turning), 0.38, math.sin(turning))) * distance
    Im.Fill(left, top, right - left, PICTURE, vector.create(0.02, 0.03, 0.045), 0.9)
    WidgetRenderer_DrawRenderable(model, Transform_Identity(), from, -1 * vector.normalize(from), vector.create(0, 1, 0), fov,
      Theme.Point(left + (right - left - PICTURE * 1.6) / 2, top), vector.create(Theme.Px(PICTURE * 1.6), Theme.Px(PICTURE)),
      vector.create(0.55, 0.80, 1.0), 0.95, turning)
    top += PICTURE + 10
  end
  local all = lines(sheet, right - left)
  local visible = (y + height - 16 - top) // ROW
  local first = Im.Scroll("info", x + 4, top, width - 8, visible * ROW, #all, visible)
  for index = 1, visible do
    local line = all[index + first]
    if line == nil then
      break
    end
    local at = top + (index - 1) * ROW
    if line.kind == "note" then
      Im.Text(line.text, left, at, SIZE, Im.TEXT, 0.85)
    elseif line.kind == "title" then
      Im.Text(line.text, left, at + 2, 12, Im.ACCENT, 0.9)
      Im.Fill(left, at + ROW - 2, right - left, 1, Im.DIM, 0.35)
    elseif line.kind == "row" then
      if line.link then
        Info.Name(line.link, line.text, left, at, SIZE, Im.TEXT)
      else
        Im.Text(line.text, left, at, SIZE, Im.DIM)
      end
      Im.TextRight(line.value, right, at, SIZE, Im.TEXT)
    end
  end
end

return Info
