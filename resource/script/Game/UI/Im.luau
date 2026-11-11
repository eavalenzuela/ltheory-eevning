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
local clicked = false   -- a button was clicked with the mouse this frame
local double = false

-- Buttons drawn this frame and last, by name, with whether they were
-- enabled: so that a script can press one by name (Im.Press).
local seen: { [string]: boolean } = {}
local seenNow: { [string]: boolean } = {}
local pressNow: string? = nil
local pressNext: string? = nil

-- The number field being typed into, and what a script has put in one.
local focus = ""
local typed = ""
local entered: { [string]: number } = {}

-- How far each scrolling list is scrolled, by name.
local scrolls: { [string]: number } = {}

Im.TEXT = vector.create(0.82, 0.86, 0.9)
Im.DIM = vector.create(0.5, 0.55, 0.6)
Im.ACCENT = Colors.Primary
Im.WARN = Colors.Secondary

function Im.Begin()
  Im.over = false
  cursor = Cursor_Get()
  pressed = Mouse_LeftPressed()
  double = Mouse_DoubleClicked()
  seen, seenNow = seenNow, {}
  pressNow, pressNext = pressNext, nil
end

-- Press a button by name on the next frame, as a click would: for
-- scripted runs. A button's name is its 'id', or its label if it has
-- none. Returns false if no such button was drawn enabled last frame.
function Im.Press(name: string): boolean
  if seen[name] ~= true then
    return false
  end
  pressNext = name
  return true
end

-- Whether a button of that name was drawn last frame, and enabled.
function Im.Has(name: string): (boolean, boolean)
  return seen[name] ~= nil, seen[name] == true
end

-- Put a value in a number field by name: for scripted runs.
function Im.Enter(name: string, value: number)
  entered[name] = value
end

-- Whether a number field has the keyboard.
function Im.Typing(): boolean
  return focus ~= ""
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

-- How wide a heading is.
function Im.HeadingWidth(s: string, size: number): number
  return WidgetRenderer_GetTextSize(Fonts.Heading(), s, size).x
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
-- dimmed and never clicks. Give an 'id' where the label alone does not
-- say which button it is (one of a row of "Buy" buttons).
function Im.Button(label: string, x: number, y: number, w: number, h: number, enabled: boolean, id: string?): boolean
  local name = id or label
  if seenNow[name] == nil or enabled then
    seenNow[name] = enabled
  end
  local scripted = enabled and pressNow == name
  if scripted then
    pressNow = nil
  end
  local hot = enabled and inside(x, y, w, h)
  local base = if hot or scripted then vector.create(0.1, 0.3, 0.45) else vector.create(0.07, 0.12, 0.17)
  WidgetRenderer_DrawPanel(vector.create(x, y), vector.create(w, h), base, 0.9, if enabled then 1 else 0.45, 4)
  local size = math.min(15, h - 8)
  Im.Text(label, x + (w - Im.TextWidth(label, size)) / 2, y + (h - size) / 2 - 1, size,
    if enabled then Im.TEXT else Im.DIM, if enabled then 1 else 0.6)
  if hot and pressed then
    clicked = true
  end
  return scripted or (hot and pressed)
end

-- Whether a button has been clicked with the mouse since this was last
-- asked: for whoever makes the click's sound.
function Im.Clicked(): boolean
  local was = clicked
  clicked = false
  return was
end

-- Text that can be clicked, lit while the cursor is on it; true on the
-- frame it is clicked. 'id' is its name for a script (Im.Press).
function Im.Link(label: string, x: number, y: number, size: number, color: vector, id: string): boolean
  seenNow[id] = true
  local scripted = pressNow == id
  if scripted then
    pressNow = nil
  end
  local hot = inside(x, y, Im.TextWidth(label, size), size + 5)
  Im.Text(label, x, y, size, if hot or scripted then Im.ACCENT else color)
  return scripted or (hot and pressed)
end

-- A bare area that can be clicked, for something that draws itself:
-- whether the cursor is on it, and whether it was just clicked. 'id' is
-- its name for a script (Im.Press).
function Im.Area(id: string, x: number, y: number, w: number, h: number, enabled: boolean): (boolean, boolean)
  if seenNow[id] == nil or enabled then
    seenNow[id] = enabled
  end
  local scripted = enabled and pressNow == id
  if scripted then
    pressNow = nil
  end
  local hot = inside(x, y, w, h)
  return hot, scripted or (enabled and hot and pressed)
end

-- A button that stays lit while 'on': a tab, or one of a set of choices.
function Im.Toggle(label: string, x: number, y: number, w: number, h: number, on: boolean, id: string?): boolean
  local clicked = Im.Button(label, x, y, w, h, true, id)
  if on then
    Im.Fill(x, y + h - 3, w, 3, Im.ACCENT, 0.95)
  end
  return clicked
end

-- A field holding a whole number of at most nine digits. Click it and
-- type; Return or a click elsewhere finishes. Returns the number it
-- holds now.
function Im.Number(name: string, value: number, x: number, y: number, w: number, h: number): number
  local set = entered[name]
  if set then
    entered[name] = nil
    value = set
    if focus == name then
      focus = ""
    end
  end
  local hot = inside(x, y, w, h)
  if pressed then
    if hot then
      focus = name
      typed = if value > 0 then tostring(value) else ""
    elseif focus == name then
      focus = ""
    end
  end
  if focus == name then
    for digit in string.gmatch(Keyboard_GetText(), "%d") do
      if #typed < 9 then
        typed ..= digit
      end
    end
    if Key_Pressed(Key_BackSpace()) then
      typed = string.sub(typed, 1, -2)
    end
    if Key_Pressed(Key_Return()) then
      focus = ""
    end
    value = tonumber(typed) or 0
  end
  local focused = focus == name
  WidgetRenderer_DrawPanel(vector.create(x, y), vector.create(w, h), vector.create(0.02, 0.03, 0.04), 0.95, 1, 3)
  if focused then
    Im.Fill(x, y + h - 2, w, 2, Im.ACCENT, 0.95)
  end
  local size = math.min(15, h - 8)
  local text = if focused then typed .. "_" else tostring(value)
  Im.TextRight(text, x + w - 8, y + (h - size) / 2 - 1, size, Im.TEXT)
  return value
end

-- The first row to draw of a scrolling list of 'count' rows of which
-- 'visible' fit, moved by the wheel while the cursor is over the list.
function Im.Scroll(name: string, x: number, y: number, w: number, h: number, count: number, visible: number): number
  local at = scrolls[name] or 0
  if inside(x, y, w, h) then
    at -= 3 * Mouse_GetScrollDelta()
  end
  at = math.clamp(math.floor(at + 0.5), 0, math.max(0, count - visible))
  scrolls[name] = at
  if count > visible then
    -- a thumb down the right edge
    local track = h - 4
    local size = math.max(16, track * visible / count)
    Im.Fill(x + w - 3, y + 2 + (track - size) * at / (count - visible), 3, size, Im.DIM, 0.6)
  end
  return at
end

-- Put a scrolling list at a row (0: its top).
function Im.ScrollTo(name: string, at: number)
  scrolls[name] = at
end

-- A list row; returns whether the cursor is on it, whether it was just
-- clicked, and whether that click was a double click.
function Im.Row(x: number, y: number, w: number, h: number, selected: boolean, id: string?): (boolean, boolean, boolean)
  local hot = inside(x, y, w, h)
  -- (with a name, a script can click it as it can a button: Im.Press)
  local scripted = false
  if id then
    seenNow[id] = true
    scripted = pressNow == id
    if scripted then
      pressNow = nil
    end
  end
  if selected then
    Im.Fill(x, y, w, h, Im.ACCENT, 0.22)
  elseif hot then
    Im.Fill(x, y, w, h, Im.ACCENT, 0.1)
  end
  return hot, (hot and pressed) or scripted, hot and double
end

return Im
