--!strict
-- What a ship scanner, a cargo scanner or a survey scanner read (module
-- expansion, 2026-11-16): a window of its own (Game/UI/Windows), opened
-- when a reading comes in. The reading is the session's (Session.scanned):
-- what was scanned, and a list of what was found, as the market lists its
-- types (an icon, a name, a count).

local Im = require("@lt/Game/UI/Im")
local ItemIcon = require("@lt/Game/UI/ItemIcon")
local List = require("@lt/Game/UI/List")
local Session = require("@lt/Game/Session")
local Theme = require("@lt/Game/UI/Theme")
local Types = require("@lt/Core/Data/Types")
local Windows = require("@lt/Game/UI/Windows")

local Scans = {}

Scans.ID = "scans"

local current: Session.Session? = nil

function Scans.Open()
  Windows.Open(Scans.ID)
  Windows.Raise(Scans.ID)
end

function Scans.IsOpen(): boolean
  return Windows.IsOpen(Scans.ID)
end

local COLUMNS: { List.Column } = {
  { id = "name", label = "Name", width = 0, sort = false },
  { id = "value", label = "", width = 140, right = true, sort = false },
}

-- Once a frame, before the windows are drawn: whose game it is, and a
-- reading come in since the last frame opens the window.
local seen = 0
function Scans.Frame(session: Session.Session)
  current = session
  local scanned = session.scanned
  if scanned and scanned.serial ~= seen then
    seen = scanned.serial
    Scans.Open()
  end
end

Windows.Kind(Scans.ID, function(_: Windows.Window, x: number, y: number, w: number, h: number)
  local session = current
  local scanned = if session then session.scanned else nil
  if scanned == nil then
    Im.Text("Nothing scanned yet: switch on a scanner.", x + 14, y + 14, 14, Theme.DIM)
    return
  end
  Im.Heading(List.Cut(scanned.title, w - 28, 18, true), x + 14, y + 10, 18, Theme.TEXT)
  Im.Text(List.Cut(scanned.note, w - 28, 13, false), x + 14, y + 34, 13, Theme.DIM)
  local top = y + 58
  local layout = List.Columns(COLUMNS, x + 1, w - 8)
  List.Head("scans", x + 1, top, w - 2, COLUMNS, layout, "", false)
  top += List.HEAD
  if #scanned.rows == 0 then
    Im.Text("Nothing.", x + 14, top + 8, 13, Theme.FAINT)
  end
  local first, visible = List.Body("scans", x + 1, top, w - 2, y + h - top - 4, #scanned.rows)
  for index = 1, visible do
    local row = scanned.rows[index + first]
    if row == nil then
      break
    end
    local rowY = top + (index - 1) * List.ROW
    local hot = List.Row(x + 1, rowY, w - 7, false)
    local inset = 0
    if row.type and Types.Get(row.type) then
      ItemIcon.Draw(row.type, layout.name.x + 6, rowY + 3, 19)
      inset = 25
    end
    List.Text(row.label, layout.name, rowY, hot, Theme.TEXT, 14, false, inset)
    List.Text(row.value, layout.value, rowY, false, Theme.DIM, 13)
  end
end)
Windows.Make(Scans.ID, Scans.ID, "Scan results", 600, 160, 460, 420, 360, 260, nil)
Windows.Icon(Scans.ID, "scanner")

return Scans
