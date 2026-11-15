--!strict
-- Windows: panels that can be moved about, lie over one another, are
-- made bigger and smaller, and are closed; and are where they were left
-- the next time the game is run.
--
-- A window is of a kind, and a kind is a function that draws what is in
-- it (Windows.Kind): the window gives it the room it has, under its
-- title. There can be any number of windows of a kind, each with a
-- state of its own that the kind keeps what it likes in.
--
-- Once a frame, Windows.Begin says where the open windows are, so that
-- whatever is drawn before them takes the cursor to be on nothing
-- there; and Windows.Draw draws them, from the one at the back to the
-- one in front, each with the cursor on nothing where one in front of it
-- lies. A press on a window brings it to the front. Its title is taken
-- hold of to move it, and its corner to change its size.
--
-- (Game/UI/Im draws: this only says where and in what order. The first
-- to use it is the inventory, Game/UI/Inventory; the screens that are
-- fixed panels still can be windows when somebody makes them so.)

local Im = require("@lt/Game/UI/Im")

local Windows = {}

export type Window = {
  id: string, kind: string, title: string,
  x: number, y: number, w: number, h: number, minW: number, minH: number,
  open: boolean,
  -- (whatever its kind keeps: what it is showing, how)
  state: any,
}

-- The height of a window's title, which what is in it is drawn under.
Windows.TITLE = 30
local BACKING = vector.create(0.025, 0.04, 0.055)

local windows: { [string]: Window } = {}
-- (from the back to the front)
local order: { string } = {}
local kinds: { [string]: (window: Window, x: number, y: number, w: number, h: number) -> () } = {}
-- The window being moved, or made another size, by the mouse: and where
-- on it the cursor has hold.
local held: { id: string, dx: number, dy: number, size: boolean }? = nil
-- Whether where the windows are has changed since anybody asked.
local changed = false
-- Where windows were when the game was last run, by id: for one that is
-- made after that is read.
local remembered: { [string]: { number } } = {}
-- The screen, as it was last drawn on: a window is kept on it.
local screen = { 0, 0, 1920, 1080 }

-- What draws the inside of the windows of a kind.
function Windows.Kind(kind: string, draw: (window: Window, x: number, y: number, w: number, h: number) -> ())
  kinds[kind] = draw
end

-- A window, made if there is none of that id: closed, at a place and of
-- a size (which are where it was when the game was last run, if it was
-- there then), and never smaller than 'minW' by 'minH'.
function Windows.Make(id: string, kind: string, title: string, x: number, y: number, w: number, h: number, minW: number, minH: number,
  state: any): Window
  local window = windows[id]
  if window == nil then
    window = { id = id, kind = kind, title = title, x = x, y = y, w = w, h = h, minW = minW, minH = minH, open = false, state = state }
    local was = remembered[id]
    if was then
      window.x, window.y, window.w, window.h = was[1], was[2], math.max(minW, was[3]), math.max(minH, was[4])
    end
    windows[id] = window
    table.insert(order, id)
  end
  return window
end

function Windows.Get(id: string): Window?
  return windows[id]
end

-- The windows of a kind there are, open or not, in the order they were made.
function Windows.Of(kind: string): { Window }
  local found: { Window } = {}
  for _, id in order do
    if windows[id].kind == kind then
      table.insert(found, windows[id])
    end
  end
  table.sort(found, function(a: Window, b: Window): boolean
    return a.id < b.id
  end)
  return found
end

-- Bring a window in front of the others.
function Windows.Raise(id: string)
  local at = table.find(order, id)
  if at and at ~= #order then
    table.remove(order, at)
    table.insert(order, id)
  end
end

function Windows.Open(id: string)
  local window = windows[id]
  if window then
    if not window.open then
      window.open = true
      changed = true
    end
    Windows.Raise(id)
  end
end

function Windows.Close(id: string)
  local window = windows[id]
  if window and window.open then
    window.open = false
    changed = true
  end
end

function Windows.IsOpen(id: string): boolean
  return windows[id] ~= nil and windows[id].open
end

-- A window is done with for good (one opened for a place that is gone).
function Windows.Forget(id: string)
  local at = table.find(order, id)
  if at then
    table.remove(order, at)
    windows[id] = nil
  end
end

-- Whether the cursor is on an open window (so that a click there is
-- not for the space behind it).
function Windows.Under(): boolean
  local cursor = Im.Cursor()
  for _, id in order do
    local window = windows[id]
    if window.open and cursor.x >= window.x and cursor.x < window.x + window.w and cursor.y >= window.y
      and cursor.y < window.y + window.h then
      return true
    end
  end
  return false
end

-- Whether where the windows are has changed since this was last asked:
-- for whoever keeps it between runs.
function Windows.Changed(): boolean
  local was = changed
  changed = false
  return was
end

-- Where the windows are, as a line of text; and the other way about.
-- ("id=x,y,w,h,open" for each, with ";" between. Only the windows whose
-- ids have no ":" in them are kept: the others are made as they are
-- wanted, and are gone when the game is.)
function Windows.Layout(): string
  local parts: { string } = {}
  local ids = table.clone(order)
  table.sort(ids)
  for _, id in ids do
    local window = windows[id]
    if string.find(id, ":", 1, true) == nil then
      table.insert(parts, string.format("%s=%d,%d,%d,%d,%d", id, window.x, window.y, window.w, window.h, if window.open then 1 else 0))
    end
  end
  return table.concat(parts, ";")
end

function Windows.Restore(text: string)
  for id: string, x: string, y: string, w: string, h: string, open: string
    in string.gmatch(text, "([%w_]+)=(%-?%d+),(%-?%d+),(%d+),(%d+),(%d)") :: any do
    local was = { tonumber(x) or 0, tonumber(y) or 0, tonumber(w) or 0, tonumber(h) or 0, tonumber(open) or 0 }
    remembered[id] = was
    local window = windows[id]
    if window then
      window.x, window.y, window.w, window.h = was[1], was[2], math.max(window.minW, was[3]), math.max(window.minH, was[4])
      window.open = was[5] == 1
    end
  end
end

-- Whether a window that was there when the game was last run was open
-- then (nil: it was not there).
function Windows.WasOpen(id: string): boolean?
  local was = remembered[id]
  return if was then was[5] == 1 else nil
end

-- Keep a window where some of its title can be got hold of.
local function keep(window: Window)
  local left, top, right, bottom = screen[1], screen[2], screen[3], screen[4]
  window.w = math.clamp(window.w, window.minW, math.max(window.minW, right - left))
  window.h = math.clamp(window.h, window.minH, math.max(window.minH, bottom - top))
  window.x = math.clamp(window.x, left - window.w + 80, right - 80)
  window.y = math.clamp(window.y, top, bottom - Windows.TITLE)
end

-- Once a frame, before anything is drawn that windows may lie over:
-- where they are is where the cursor is on nothing, until they are drawn.
function Windows.Begin(left: number, top: number, right: number, bottom: number)
  screen = { left, top, right, bottom }
  local rects: { { number } } = {}
  for _, id in order do
    local window = windows[id]
    if window.open then
      keep(window)
      table.insert(rects, { window.x, window.y, window.x + window.w, window.y + window.h })
    end
  end
  Im.Shield(rects)
end

-- Once a frame, after what the windows lie over: the open ones, from
-- the back to the front.
function Windows.Draw()
  local cursor = Im.Cursor()
  -- The one in hand goes where the cursor takes it, while the button is down.
  local hold = held
  if hold then
    local window = windows[hold.id]
    if window == nil or not window.open or not Mouse_LeftDown() then
      held = nil
      changed = true
    elseif hold.size then
      window.w, window.h = cursor.x + hold.dx - window.x, cursor.y + hold.dy - window.y
      keep(window)
    else
      window.x, window.y = cursor.x - hold.dx, cursor.y - hold.dy
      keep(window)
    end
  end
  local open: { Window } = {}
  for _, id in order do
    if windows[id].open then
      table.insert(open, windows[id])
    end
  end
  local raise: string? = nil
  for index, window in open do
    -- (the cursor is on nothing of this one where one in front of it lies)
    local over: { { number } } = {}
    for above = index + 1, #open do
      local other = open[above]
      table.insert(over, { other.x, other.y, other.x + other.w, other.y + other.h })
    end
    Im.Shield(over)
    local x, y, w, h = window.x, window.y, window.w, window.h
    -- (what lies under a window does not show through it: it may be another window, or a screen)
    Im.Fill(x + 2, y + 2, w - 4, h - 4, BACKING, 1)
    Im.Panel(x, y, w, h)
    Im.Fill(x + 1, y + 1, w - 2, Windows.TITLE - 2, Im.ACCENT, if index == #open then 0.16 else 0.07)
    Im.Heading(string.upper(window.title), x + 12, y + 8, 14, if index == #open then Im.TEXT else Im.DIM)
    if Im.Button("x", x + w - 28, y + 4, 22, 22, true, `{window.id}:close`) then
      window.open = false
      changed = true
    end
    if Im.Pressed() and Im.Inside(x, y, w, h) then
      raise = window.id
      if held == nil and Im.Inside(x, y, w - 32, Windows.TITLE) then
        held = { id = window.id, dx = cursor.x - x, dy = cursor.y - y, size = false }
      elseif held == nil and Im.Inside(x + w - 16, y + h - 16, 16, 16) then
        held = { id = window.id, dx = x + w - cursor.x, dy = y + h - cursor.y, size = true }
      end
    end
    local draw = kinds[window.kind]
    if draw and window.open then
      draw(window, x, y + Windows.TITLE, w, h - Windows.TITLE)
    end
    -- (the corner it is made bigger and smaller by)
    Im.Fill(x + w - 12, y + h - 4, 9, 2, Im.DIM, 0.7)
    Im.Fill(x + w - 4, y + h - 12, 2, 10, Im.DIM, 0.7)
  end
  Im.Shield({})
  if raise then
    Windows.Raise(raise)
  end
  if held then
    Im.over = true
  end
end

return Windows
