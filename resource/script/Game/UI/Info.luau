--!strict
-- The information window: everything there is to say about one type of
-- item (Core/Data/Facts), with its icon, in a panel beside whatever
-- opened it. A row that names another item opens that item's; Back
-- returns.
--
--   Info.Open("frigate.battleaxe")      (GameDebug.Info does this)
--
-- A window (Game/UI/Windows) since 2026-11-16, with its sections on
-- tabs ("Info:tab:<about, attributes, requires, industry, market>"),
-- "Info:back", "Info:close" (or "info:close"), and on the Market tab
-- "Info:market".

local Facts = require("@lt/Core/Data/Facts")
local Im = require("@lt/Game/UI/Im")
local Theme = require("@lt/Game/UI/Theme")
local ItemIcon = require("@lt/Game/UI/ItemIcon")
local Scene = require("@lt/Game/View/Scene")
local Ships = require("@lt/Core/Data/Ships")
local Windows = require("@lt/Game/UI/Windows")

local Info = {}

Info.ID = "info"
Info.WIDTH = 520
Info.HEIGHT = 640

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
  if showing and showing ~= type and Windows.IsOpen(Info.ID) then
    table.insert(history, showing)
  end
  showing = type
  Im.ScrollTo("info", 0)
  Windows.Open(Info.ID)
  Windows.Raise(Info.ID)
  return true
end

function Info.Close()
  showing = nil
  table.clear(history)
  Windows.Close(Info.ID)
end

-- The type whose sheet is open, or "" (the window shut by its corner's
-- button is a sheet shut).
function Info.Showing(): string
  if showing and not Windows.IsOpen(Info.ID) then
    showing = nil
    table.clear(history)
  end
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

-- The sheet's sections, by the tab they are on (2026-11-16, laid out as
-- the other windows are): what it is and its picture; what it does
-- and is made of; what a pilot needs for it; what it is built from and
-- into; and what it sells for. A tab with nothing on it is not shown.
local TABS: { { string } } = {
  { "about", "Description" }, { "attributes", "Attributes" }, { "requires", "Requirements" }, { "industry", "Industry" },
  { "market", "Market" },
}
local TAB_OF: { [string]: string } = {
  ["Requires"] = "requires", ["Skill"] = "requires",
  ["Made into"] = "industry", ["Materials a run"] = "industry", ["Makes"] = "industry", ["Refined from"] = "industry",
  ["Processed into"] = "industry", ["Processed from"] = "industry", ["Reacted from"] = "industry", ["Use"] = "industry",
  ["Facilities"] = "industry", ["Supplies"] = "industry", ["Deposit"] = "industry", ["Found on"] = "industry",
  ["Trade"] = "market",
}
local function tabOf(title: string): string
  if string.sub(title, 1, 10) == "Refines to" then
    return "industry"
  end
  return TAB_OF[title] or "attributes"
end
local tab = "about"

-- How a hull is shown as it is in space, in its base paint, in a box
-- whose middle is (cx, cy), 'half' high from the middle and 'aspect'
-- times as wide: the scene's (Scene.Showcase), set by the HUD each
-- frame. False if it cannot be shown so. (The owner, 2026-11-16: "don't
-- use wireframe for any ships, they should look just like the base
-- paint in the fitting view".)
Info.Show = nil :: ((type: string, radius: number, cx: number, cy: number, half: number, aspect: number) -> boolean)?

-- How the market is opened at a type: set by Game/UI/Market, which
-- cannot be drawn on from here without a circle.
Info.Market = nil :: ((type: string) -> boolean)?

type Line = { kind: "note" | "title" | "row" | "gap", text: string, value: string, link: string? }

-- The lines of the sections of a tab. A row whose label and value do not
-- fit side by side takes two: the value goes under, to the right.
local function lines(sheet: Facts.Sheet, width: number, on: string): { Line }
  local out: { Line } = {}
  for _, section in sheet.sections do
    if tabOf(section.title) == on then
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
  end
  return out
end

-- The window's contents, in its frame (Game/UI/Windows).
local function draw(_: Windows.Window, x: number, y: number, width: number, height: number)
  local type = showing
  local sheet = if type then Facts.Of(type) else nil
  if type == nil or sheet == nil then
    showing = nil
    return
  end
  local was = Im.Plain(true)
  if Im.Hook("Info:close", true) then
    Info.Close()
    Im.Plain(was)
    return
  end
  local left, right = x + 16, x + width - 16
  ItemIcon.Draw(type, left, y + 10, 44)
  Im.Strong(fit(sheet.name, 17, right - left - 60 - 70), left + 56, y + 10, 17, Theme.TEXT)
  Im.Text(sheet.kind, left + 56, y + 34, SIZE, Theme.DIM)
  if #history > 0 and Im.Button("Back", right - 60, y + 14, 60, 24, true, "Info:back") then
    showing = table.remove(history)
    Im.ScrollTo("info", 0)
    Im.Plain(was)
    return
  end
  -- The tabs that have something on them.
  local has: { [string]: boolean } = { about = true }
  for _, section in sheet.sections do
    has[tabOf(section.title)] = true
  end
  if not has[tab] then
    tab = "about"
  end
  local tx = x + 10
  for _, each in TABS do
    if has[each[1]] then
      local pressed, wide = Im.Tab(each[2], tx, y + 62, 28, tab == each[1], `Info:tab:{each[1]}`)
      if pressed and tab ~= each[1] then
        tab = each[1]
        Im.ScrollTo("info", 0)
      end
      tx += wide + 2
    end
  end
  Im.Flat(x + 1, y + 90, width - 2, 1, Theme.EDGE)
  local top = y + 104
  if tab == "about" then
    -- A hull has its picture first: the model the game draws for it, turning.
    local hull = Ships.byId[type]
    if hull then
      local tall = math.min(PICTURE * 1.4, (right - left) / 1.6)
      local wide = right - left
      Im.Fill(left, top, wide, tall, vector.create(0.02, 0.03, 0.045), 0.9)
      local shown = Info.Show ~= nil and Info.Show(type, hull.radius, left + wide / 2, top + tall / 2, tall / 2, wide / tall)
      if not shown then
        -- (where the scene cannot stand it, as the fitting window does
        -- not: its model, lit as a ship in space is, turning)
        local model = Scene.Preview(type, hull.radius)
        turning += 0.3 * FrameTimer_Get()
        local bound = Renderable_GetBound(model)
        local size = bound.upper - bound.lower
        local fov = math.rad(0.02)
        local distance = math.max(size.x, size.y, size.z) * 0.36 / math.tan(0.5 * fov)
        local from = vector.normalize(vector.create(math.cos(turning), 0.38, math.sin(turning))) * distance
        WidgetRenderer_DrawRenderable(model, Transform_Identity(), from, -1 * vector.normalize(from), vector.create(0, 1, 0), fov,
          Theme.Point(left + (wide - tall * 1.6) / 2, top), vector.create(Theme.Px(tall * 1.6), Theme.Px(tall)),
          vector.create(0.55, 0.80, 1.0), 0.95, turning)
      end
      top += tall + 14
    end
    Im.Wrapped(sheet.note, left, top, right - left, 14, Theme.TEXT, 20)
    Im.Plain(was)
    return
  end
  if tab == "market" and Info.Market and Im.Button("Show it on the market", right - 200, y + height - 40, 200, 28, true, "Info:market") then
    Info.Market(type)
  end
  local all = lines(sheet, right - left, tab)
  local foot = if tab == "market" then 50 else 14
  local visible = math.max(1, (y + height - foot - top) // ROW)
  local first = Im.Scroll("info", x + 4, top, width - 8, visible * ROW, #all, visible)
  for index = 1, visible do
    local line = all[index + first]
    if line == nil then
      break
    end
    local at = top + (index - 1) * ROW
    if line.kind == "title" then
      Im.Text(line.text, left, at + 2, 11, Theme.ACCENT)
      Im.Flat(left, at + ROW - 3, right - left, 1, Theme.EDGE)
    elseif line.kind == "row" then
      if line.link then
        Info.Name(line.link, line.text, left, at, SIZE, Theme.TEXT)
      else
        Im.Text(line.text, left, at, SIZE, Theme.DIM)
      end
      Im.TextRight(line.value, right, at, SIZE, Theme.TEXT)
    end
  end
  Im.Plain(was)
end

Windows.Kind(Info.ID, draw)
Windows.Make(Info.ID, Info.ID, "Information", 1300, 140, Info.WIDTH, Info.HEIGHT, 420, 420, nil)
Windows.Icon(Info.ID, "guide")

return Info
