--!strict
-- A small immediate-mode layer for the game's interface. One widget draws
-- everything each frame by calling these; a button is a function that
-- draws itself and says whether it was just clicked. There is no widget
-- tree to rebuild, so a list of a few hundred rows costs what it draws.
--
-- Coordinates are window pixels. Call Im.Begin once at the start of the
-- frame's drawing.

local Colors = require("@lt/Colors")
local Fonts = require("@lt/Fonts")

local Im = {}

-- True once the cursor has been found over a panel this frame.
Im.over = false

local cursor = vector.create(0, 0)
local pressed = false
local double = false

Im.TEXT = vector.create(0.82, 0.86, 0.9)
Im.DIM = vector.create(0.5, 0.55, 0.6)
Im.ACCENT = Colors.Primary
Im.WARN = Colors.Secondary

function Im.Begin()
  Im.over = false
  cursor = Cursor_Get()
  pressed = Mouse_LeftPressed()
  double = Mouse_DoubleClicked()
end

function Im.Cursor(): vector
  return cursor
end

-- Whether the mouse button went down this frame (anywhere).
function Im.Pressed(): boolean
  return pressed
end

local function inside(x: number, y: number, w: number, h: number): boolean
  return cursor.x >= x and cursor.x < x + w and cursor.y >= y and cursor.y < y + h
end

Im.Inside = inside

function Im.TextWidth(s: string, size: number): number
  return WidgetRenderer_GetTextSize(Fonts.Default(), s, size).x
end

-- Text with its top-left corner at (x, y).
function Im.Text(s: string, x: number, y: number, size: number, color: vector, alpha: number?)
  WidgetRenderer_DrawText(Fonts.Default(), s, vector.create(x, y + 0.8 * size), size, color, alpha or 1, false)
end

-- Text ending at x.
function Im.TextRight(s: string, x: number, y: number, size: number, color: vector, alpha: number?)
  Im.Text(s, x - Im.TextWidth(s, size), y, size, color, alpha)
end

function Im.Heading(s: string, x: number, y: number, size: number, color: vector)
  WidgetRenderer_DrawText(Fonts.Heading(), s, vector.create(x, y + 0.8 * size), size, color, 1, false)
end

-- A panel background. The camera ignores the mouse while it is over one.
function Im.Panel(x: number, y: number, w: number, h: number)
  WidgetRenderer_DrawPanel(vector.create(x, y), vector.create(w, h), vector.create(0.03, 0.05, 0.07), 0.9, 0.92, 6)
  if inside(x, y, w, h) then
    Im.over = true
  end
end

-- A rectangle of solid colour.
function Im.Fill(x: number, y: number, w: number, h: number, color: vector, alpha: number)
  WidgetRenderer_DrawPanel(vector.create(x, y), vector.create(w, h), color, alpha, alpha, 0)
end

-- A button; true on the frame it is clicked. A disabled one is drawn
-- dimmed and never clicks.
function Im.Button(label: string, x: number, y: number, w: number, h: number, enabled: boolean): boolean
  local hot = enabled and inside(x, y, w, h)
  local base = if hot then vector.create(0.1, 0.3, 0.45) else vector.create(0.07, 0.12, 0.17)
  WidgetRenderer_DrawPanel(vector.create(x, y), vector.create(w, h), base, 0.9, if enabled then 1 else 0.45, 4)
  local size = math.min(15, h - 8)
  Im.Text(label, x + (w - Im.TextWidth(label, size)) / 2, y + (h - size) / 2 - 1, size,
    if enabled then Im.TEXT else Im.DIM, if enabled then 1 else 0.6)
  return hot and pressed
end

-- A list row; returns whether the cursor is on it, whether it was just
-- clicked, and whether that click was a double click.
function Im.Row(x: number, y: number, w: number, h: number, selected: boolean): (boolean, boolean, boolean)
  local hot = inside(x, y, w, h)
  if selected then
    Im.Fill(x, y, w, h, Im.ACCENT, 0.22)
  elseif hot then
    Im.Fill(x, y, w, h, Im.ACCENT, 0.1)
  end
  return hot, hot and pressed, hot and double
end

return Im
