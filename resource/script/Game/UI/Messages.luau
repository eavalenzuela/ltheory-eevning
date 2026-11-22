--!strict
-- The log of what the game has said to the pilot: the notices that come
-- and go at the top of the screen, kept (Session.log), the newest first,
-- each with when in the game it was said. The owner, 2026-11-22: "a
-- small history of notices", opened by clicking the notice.
--
-- A window (Game/UI/Windows), open in space or docked. "Messages:close"
-- shuts it, as any window's close does.

local Format = require("@lt/Game/Format")
local Im = require("@lt/Game/UI/Im")
local List = require("@lt/Game/UI/List")
local Session = require("@lt/Game/Session")
local Theme = require("@lt/Game/UI/Theme")
local Windows = require("@lt/Game/UI/Windows")

local Messages = {}

Messages.ID = "messages"
Messages.WIDTH, Messages.HEIGHT = 640, 420

local current: Session.Session? = nil

function Messages.Open()
  Windows.Open(Messages.ID)
  Windows.Raise(Messages.ID)
end

function Messages.Close()
  Windows.Close(Messages.ID)
end

function Messages.IsOpen(): boolean
  return Windows.IsOpen(Messages.ID)
end

-- Once a frame, before the windows are drawn: whose game it is.
function Messages.Frame(session: Session.Session)
  current = session
end

local WHEN_W = 130
local ROW = 22

local function draw(_: Windows.Window, x: number, y: number, w: number, h: number)
  local session = current
  if session == nil then
    return
  end
  local log = session.log
  local was = Im.Plain(true)
  if #log == 0 then
    Im.Text("Nothing has been said yet.", x + 14, y + 14, 14, Theme.DIM)
    Im.Plain(was)
    return
  end
  local first, visible = List.Body("Messages:list", x, y + 4, w, h - 8, #log, ROW)
  for row = 1, visible do
    local index = #log - (first + row - 1)
    local entry = log[index]
    if entry == nil then
      break
    end
    local ly = y + 4 + (row - 1) * ROW
    local kind = entry.kind
    local tint = if kind == "good" then Theme.GOOD elseif kind == "warn" then Theme.CAUTION elseif kind == "bad" then Theme.BAD else Theme.TEXT
    Im.Flat(x + 6, ly + 4, 3, ROW - 8, if kind == "plain" then Theme.EDGE else tint)
    Im.Text(Format.Clock(entry.tick), x + 16, ly + 4, 12, Theme.DIM)
    -- (a long one is cut here: its whole is read on the row's hover)
    local room = w - WHEN_W - 34
    local text = List.Cut(entry.text, room, 13, false)
    Im.Text(text, x + 16 + WHEN_W, ly + 3, 13, tint)
    local cursor = Im.Cursor()
    if text ~= entry.text and cursor.x >= x and cursor.x < x + w - 14 and cursor.y >= ly and cursor.y < ly + ROW then
      Im.Tip(Format.Clock(entry.tick), entry.text)
    end
  end
  Im.Plain(was)
end

Windows.Kind(Messages.ID, draw)
Windows.Make(Messages.ID, Messages.ID, "Messages", 420, 150, Messages.WIDTH, Messages.HEIGHT, 420, 200, nil)

return Messages
