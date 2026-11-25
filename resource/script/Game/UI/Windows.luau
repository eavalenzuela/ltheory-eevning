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

local Icons = require("@lt/Game/UI/Icons")
local Im = require("@lt/Game/UI/Im")
local Signs = require("@lt/Game/UI/Signs")
local Theme = require("@lt/Game/UI/Theme")

local Windows = {}

export type Window = {
  id: string, kind: string, title: string,
  x: number, y: number, w: number, h: number, minW: number, minH: number,
  open: boolean,
  -- (whatever its kind keeps: what it is showing, how)
  state: any,
  -- A screen that was a panel before there were windows, and draws all
  -- of itself (its own ground, its own heading, its own way of being
  -- shut): it is given no title and no corner, is the size it is, and
  -- is moved by the parts of itself that are nothing to press (each x,
  -- y, width and height from its own corner).
  grips: { { number } }?,
  -- Whether somebody has put it somewhere: until then it is where
  -- whoever draws the screen says it goes (Windows.Default).
  moved: boolean,
  -- The sign beside its title (Game/UI/Icons), if it has one.
  icon: string?,
  -- Whether, opened where nobody has put it, it finds itself a place
  -- clear of the windows that are open (Windows.Open): and whether it
  -- is in such a place now, which it keeps while it is open.
  auto: boolean,
  placed: boolean,
  -- A window that is meant to lie over the others (the star map):
  -- nothing is put clear of it.
  covers: boolean?,
  -- Pinned where it is (the pin on its title, 2026-11-16: "a pin on
  -- windows", of the mock-ups' list the owner passed): it is not moved
  -- or made another size by the mouse until it is unpinned, and is kept
  -- so from one game to the next.
  pinned: boolean?,
}

-- The height of a window's title, which what is in it is drawn under.
Windows.TITLE = Theme.TITLE
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
    window = { id = id, kind = kind, title = title, x = x, y = y, w = w, h = h, minW = minW, minH = minH, open = false, state = state,
      moved = false, auto = true, placed = false }
    local was = remembered[id]
    if was then
      window.x, window.y, window.w, window.h = was[1], was[2], math.max(minW, was[3]), math.max(minH, was[4])
      window.moved = true
    end
    windows[id] = window
    table.insert(order, id)
  end
  return window
end

function Windows.Get(id: string): Window?
  return windows[id]
end

-- A window that is a screen of its own drawing (see 'grips'): made if
-- there is none, of the size given, which it keeps.
function Windows.Screen(id: string, kind: string, w: number, h: number, grips: { { number } }): Window
  local window = Windows.Make(id, kind, "", 0, 0, w, h, w, h, nil)
  window.grips = grips
  window.w, window.h, window.minW, window.minH = w, h, w, h
  -- (it is where whoever draws it says, unless it is said otherwise: Windows.Auto)
  window.auto = false
  return window
end

-- The sign beside a window's title.
function Windows.Icon(id: string, icon: string)
  local window = windows[id]
  if window then
    window.icon = icon
  end
end

-- Whether a window finds itself a clear place when it is opened where
-- nobody has put it; and whether it is one that lies over the others.
function Windows.Auto(id: string, auto: boolean, covers: boolean?)
  local window = windows[id]
  if window then
    window.auto = auto
    window.covers = covers
  end
end

-- Where a window goes, and how big it is, until somebody has put it
-- somewhere: said every frame by whoever knows where the screen's
-- middle is. (A window of a size of its own keeps that size.)
function Windows.Default(id: string, x: number, y: number, w: number?, h: number?)
  local window = windows[id]
  if window == nil then
    return
  end
  if w and h and window.grips then
    window.w, window.h, window.minW, window.minH = w, h, w, h
  end
  -- (one that found itself a place when it was opened keeps it while it is open)
  if not window.moved and not (window.open and window.placed) then
    window.x, window.y = x, y
  end
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

-- A place for a window that nobody has put anywhere, clear of the
-- windows that are open: where it would be by itself, if nothing is
-- there; else beside one of them, or under one; else a step down and
-- across from where it would be, for each window in its way. (A new
-- window opens beside the others and never on top of one.)
local function place(window: Window)
  local left, top, right, bottom = screen[1], screen[2], screen[3], screen[4]
  local others: { Window } = {}
  for _, id in order do
    local other = windows[id]
    if other.open and other ~= window and not other.covers then
      table.insert(others, other)
    end
  end
  local function clear(x: number, y: number): boolean
    if x < left or y < top or x + window.w > right or y + window.h > bottom then
      return false
    end
    for _, other in others do
      if x < other.x + other.w and other.x < x + window.w and y < other.y + other.h and other.y < y + window.h then
        return false
      end
    end
    return true
  end
  if #others == 0 or clear(window.x, window.y) then
    return
  end
  local gap = Theme.GAP
  for _, other in others do
    if clear(other.x + other.w + gap, other.y) then
      window.x, window.y = other.x + other.w + gap, other.y
      return
    end
  end
  for _, other in others do
    if clear(other.x, other.y + other.h + gap) then
      window.x, window.y = other.x, other.y + other.h + gap
      return
    end
  end
  local step = 0
  for _, other in others do
    if window.x < other.x + other.w and other.x < window.x + window.w and window.y < other.y + other.h and other.y < window.y + window.h then
      step += 1
    end
  end
  window.x, window.y = window.x + 32 * step, window.y + 32 * step
  -- (and all of it on the screen, where it is no bigger than that: a
  -- wide window that opens near the right edge does not go over it)
  window.x = math.max(left, math.min(window.x, right - gap - window.w))
  window.y = math.max(top, math.min(window.y, bottom - gap - window.h))
end

function Windows.Open(id: string)
  local window = windows[id]
  if window then
    if not window.open then
      if window.auto and not window.moved and not window.covers then
        place(window)
        window.placed = true
      end
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
    window.placed = false
    changed = true
  end
end

function Windows.IsOpen(id: string): boolean
  return windows[id] ~= nil and windows[id].open
end

-- A window that is a station's own (the market, fitting, the ships):
-- shut when the pilot undocks, and open again at the next station if it
-- was open when they left the last. Whoever has such a window says once
-- a frame, before the windows are drawn, whether the pilot is docked.
-- 'first': it is open at the first station too, before any was left.
local berthed: { [string]: { was: boolean, open: boolean } } = {}
-- Whether coming to a berth opens again what was open when the pilot
-- last left one: on docking, yes; in a tower's field, never (the owner,
-- 2026-11-22: "nothing opens" there; the windows are opened from the dock).
local reopening = true
function Windows.Reopening(on: boolean)
  reopening = on
end

function Windows.Berthed(id: string, docked: boolean, first: boolean?)
  local state = berthed[id]
  if state == nil then
    state = { was = false, open = first == true }
    berthed[id] = state
  end
  if docked ~= state.was then
    if docked then
      if state.open and reopening then
        Windows.Open(id)
      end
    else
      state.open = Windows.IsOpen(id)
      Windows.Close(id)
    end
    state.was = docked
  end
end

-- Whether one window is in front of another (both open).
function Windows.Above(id: string, other: string): boolean
  local a, b = table.find(order, id), table.find(order, other)
  return a ~= nil and b ~= nil and windows[id].open and windows[other].open and a > b
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
      table.insert(parts, string.format("%s=%d,%d,%d,%d,%d,%d", id, window.x, window.y, window.w, window.h, if window.open then 1 else 0,
        if window.pinned then 1 else 0))
    end
  end
  return table.concat(parts, ";")
end

function Windows.Restore(text: string)
  -- (a window's x, y, width, height, whether it was open, and whether it is pinned: the last since 2026-11-16, and none before)
  for id: string, figures: string in string.gmatch(text, "([%w_]+)=([%-%d,]+)") :: any do
    local read: { number } = {}
    for figure in string.gmatch(figures, "%-?%d+") do
      table.insert(read, tonumber(figure) or 0)
    end
    if #read < 5 then
      continue
    end
    local was = { read[1], read[2], read[3], read[4], read[5], read[6] or 0 }
    remembered[id] = was
    local window = windows[id]
    if window then
      window.x, window.y = was[1], was[2]
      -- (a screen of its own drawing is the size it is)
      if window.grips == nil then
        window.w, window.h = math.max(window.minW, was[3]), math.max(window.minH, was[4])
      end
      window.open = was[5] == 1
      window.pinned = was[6] == 1
      window.moved = true
    end
  end
end

-- The window in front of the others, of those open ("" for none).
function Windows.Front(): string
  for index = #order, 1, -1 do
    local window = windows[order[index]]
    if window and window.open then
      return window.id
    end
  end
  return ""
end

-- Whether a window is pinned where it is.
function Windows.Pinned(id: string): boolean
  return windows[id] ~= nil and windows[id].pinned == true
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
  -- (never under the dock, which is what the screen's left edge is: Game/UI/Dock)
  window.x = math.clamp(window.x, left, math.max(left, right - 80))
  window.y = math.clamp(window.y, top, bottom - Windows.TITLE)
end

-- Once a frame, before anything is drawn that windows may lie over:
-- where they are is where the cursor is on nothing, until they are drawn.
function Windows.Begin(left: number, top: number, right: number, bottom: number)
  -- (the screen another size than it was, in the interface's units: the
  -- game's window was made another size, or the interface is drawn at
  -- another scale. Every window that still fits is brought wholly on to it)
  local resized = screen[3] - screen[1] ~= right - left or screen[4] - screen[2] ~= bottom - top
  screen = { left, top, right, bottom }
  local rects: { { number } } = {}
  for _, id in order do
    local window = windows[id]
    if window.open then
      if resized then
        window.x = math.max(left, math.min(window.x, right - Theme.GAP - window.w))
        window.y = math.max(top, math.min(window.y, bottom - Theme.GAP - window.h))
      end
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
      if window then
        window.moved = true
      end
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
    local grips = window.grips
    if grips then
      -- A screen of its own drawing: it is brought forward and moved
      -- as any window is, by the parts of it that are nothing to press,
      -- and draws the rest itself.
      if Im.Pressed() and Im.Inside(x, y, w, h) then
        raise = window.id
        for _, grip in grips do
          if held == nil and Im.Inside(x + grip[1], y + grip[2], grip[3], grip[4]) then
            held = { id = window.id, dx = cursor.x - x, dy = cursor.y - y, size = false }
            -- (from here it is where it is put, and not where it would be by itself)
            window.moved = true
          end
        end
      end
      -- (nor does what lies under it show through: it may be over another window now)
      Im.Fill(x + 2, y + 2, w - 4, h - 4, BACKING, 1)
      local draw = kinds[window.kind]
      if draw then
        -- (in the look, whatever it is: one that has not been gone over
        -- yet has the look's grounds, edges and buttons all the same)
        local was = Im.Plain(true)
        draw(window, x, y, w, h)
        Im.Plain(was)
      end
      continue
    end
    -- The window's frame (Game/UI/Theme): a plain ground that nothing
    -- under it shows through (it may lie on another window, or a
    -- screen), a hairline about it, and its title on a bar that stands
    -- out of it. The one in front has the stronger line, a line of the
    -- accent along its top, and its title bright.
    local front = index == #open
    Im.Flat(x, y, w, h, Theme.PANEL, 1)
    Im.Flat(x + 1, y + 1, w - 2, Windows.TITLE - 1, Theme.RAISED, 1)
    Im.Flat(x + 1, y + Windows.TITLE - 1, w - 2, 1, Theme.EDGE)
    Im.Edge(x, y, w, h, if front then Theme.EDGE_STRONG else Theme.EDGE)
    if front then
      Im.Flat(x, y, w, 2, Theme.ACCENT)
    end
    if Im.Inside(x, y, w, h) then
      Im.over = true
    end
    local titleAt = x + 12
    if window.icon then
      -- (the dock's sign of it, where there is one; else the overview's of
      -- that name, as the starbase's window has the station's)
      local tone = if front then Theme.ACCENT else Theme.DIM
      if not Signs.Draw(`dock{window.icon}`, x + 18, y + 16, 16, tone, 1) and not Signs.Draw(window.icon, x + 18, y + 16, 16, tone, 1) then
        Icons.Draw(window.icon, x + 18, y + 16, 8, if front then Theme.ACCENT else Theme.DIM, 1)
      end
      titleAt = x + 34
    end
    Im.Heading(string.upper(window.title), titleAt, y + 8, 16, if front then Theme.TEXT else Theme.DIM)
    if Im.IconButton("close", x + w - 28, y + 4, 24, 23, true, `{window.id}:close`) then
      window.open = false
      window.placed = false
      changed = true
    end
    -- (the pin: lit while it is pinned)
    local pinPressed, pinHot = Im.IconButton("pin", x + w - 54, y + 4, 24, 23, true, `{window.id}:pin`,
      if window.pinned then Theme.ACCENT else nil)
    if pinHot then
      Im.Tip(if window.pinned then "Unpin" else "Pin", if window.pinned then "move it and change its size again" else "keep it where it is, this size")
    end
    if pinPressed then
      window.pinned = not window.pinned
      window.moved = true
      changed = true
    end
    if Im.Pressed() and Im.Inside(x, y, w, h) then
      raise = window.id
      if window.pinned then
        -- (pinned: neither moved nor made another size)
      elseif held == nil and Im.Inside(x, y, w - 58, Windows.TITLE) then
        held = { id = window.id, dx = cursor.x - x, dy = cursor.y - y, size = false }
        -- (from here it is where it is put: a window whose place is said
        -- every frame, Windows.Default, is not put back while it is held)
        window.moved = true
      elseif held == nil and Im.Inside(x + w - 16, y + h - 16, 16, 16) then
        held = { id = window.id, dx = x + w - cursor.x, dy = y + h - cursor.y, size = true }
        window.moved = true
      end
    end
    local draw = kinds[window.kind]
    if draw and window.open then
      local was = Im.Plain(true)
      draw(window, x, y + Windows.TITLE, w, h - Windows.TITLE)
      Im.Plain(was)
    end
    -- (the corner it is made bigger and smaller by, unless it is pinned)
    if not window.pinned then
      Im.Flat(x + w - 12, y + h - 4, 9, 2, Theme.EDGE_STRONG)
      Im.Flat(x + w - 4, y + h - 12, 2, 10, Theme.EDGE_STRONG)
    end
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
