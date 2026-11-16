--!strict
-- The interface's colours and sizes, in one place: what the owner agreed
-- from the mock-ups of 2026-11-15 (docs/roadmap.md, 10, "The rework").
-- What is drawn to the new look takes them from here; a screen that has
-- not been gone over yet still has its own, where it is drawn.
--
-- A colour says one thing each:
--   ACCENT    what is picked, what the cursor is on, what a press does
--   GOOD      yours, a gain, a thing done, safe space
--   CAUTION   where the pilot is going, a warning, a thing wanted
--   BAD       hostile, a loss, a refusal, why a button is off
--   TEXT      what is to be read
--   DIM       labels, units, what matters less
--   FAINT     what is there but not for the pilot now

local Theme = {}

local function rgb(r: number, g: number, b: number): vector
  return vector.create(r / 255, g / 255, b / 255)
end

-- Grounds, from the darkest: a window, what stands out of it (its
-- title, a list's heads), a control, a control with the cursor on it,
-- and a well that is typed into.
Theme.PANEL = rgb(8, 12, 18)
Theme.RAISED = rgb(17, 24, 34)
Theme.CONTROL = rgb(34, 46, 62)
Theme.CONTROL_HOT = rgb(48, 64, 86)
Theme.WELL = rgb(3, 5, 8)
-- A hairline about a panel and between its parts; and the stronger one
-- about the window in front. (They are the one grey-blue at 16 and 34
-- parts in a hundred over a panel, set down as what that comes to, so
-- that a line is the same on whatever it lies.)
Theme.EDGE = rgb(28, 36, 46)
Theme.EDGE_STRONG = rgb(49, 62, 76)

Theme.TEXT = rgb(209, 219, 230)
Theme.DIM = rgb(128, 140, 153)
Theme.FAINT = rgb(86, 97, 109)
Theme.ACCENT = rgb(51, 179, 255)
Theme.GOOD = rgb(115, 217, 140)
Theme.CAUTION = rgb(255, 204, 71)
Theme.BAD = rgb(224, 96, 79)

-- A ship's own: its three layers and its capacitor.
Theme.SHIELD = rgb(89, 166, 255)
Theme.ARMOR = rgb(242, 191, 77)
Theme.HULL = rgb(217, 89, 77)
Theme.CAPACITOR = rgb(255, 230, 128)

-- The interface's scale (the owner's "Yes" to a setting for it,
-- 2026-11-15): 1, 1.25 or 1.5. Everything the interface draws is set out
-- in its own units, which are a screen's pixels at 1 and more of them at
-- more: what draws (Game/UI/Im, and the few that draw past it) turns a
-- length into pixels with Theme.Px, and whoever takes a length from the
-- screen (its size, where the cursor is, where a thing in space is seen)
-- turns it into the interface's with Theme.Units.
Theme.scale = 1

-- The scale: given one, it is set (to one of the three).
function Theme.Scale(to: number?): number
  if to then
    Theme.scale = if to >= 1.4 then 1.5 elseif to >= 1.15 then 1.25 else 1
  end
  return Theme.scale
end

-- A length of the interface's, in the screen's pixels: whole ones, so
-- that a hairline is a pixel or two and not a blur.
function Theme.Px(units: number): number
  local scale = Theme.scale
  return if scale == 1 then units else math.floor(units * scale + 0.5)
end

-- A length of the screen's, in the interface's units.
function Theme.Units(pixels: number): number
  return pixels / Theme.scale
end

-- A point of the interface's, as the engine wants one: in pixels.
function Theme.Point(x: number, y: number): vector
  local scale = Theme.scale
  return if scale == 1 then vector.create(x, y) else vector.create(math.floor(x * scale + 0.5), math.floor(y * scale + 0.5))
end

-- Sizes, in the interface's units: pixels of a screen 1080 high, at a scale of 1.
Theme.TITLE = 30      -- a window's title bar
Theme.DOCK = 52       -- the dock down the left edge
Theme.ROW = 25        -- a row of a list
Theme.GAP = 8         -- between panels, and a panel's own margin

return Theme
