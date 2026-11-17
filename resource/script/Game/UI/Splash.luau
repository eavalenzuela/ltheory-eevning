--!strict
-- The splash: what a person sees when the game starts, before the menu.
-- (The owner's list of 2026-11-15: "splash screen for startup".)
--
-- The screen is black; the game's mark and its name come up out of it,
-- stand a few seconds, and the black then clears to the game standing
-- behind its menu. Any key or a click sends it on its way at once.
--
-- The mark is drawn, not a picture: two rings that cross, as the sign
-- for what has no end, with a star where they cross and a small world
-- on the further ring. (A first one, and mine: the owner may have a
-- mark of their own in mind.)
--
-- Behind them, out of the black, a picture: the game's own fleet,
-- redrawn in the retro-anime manner that is the game's look (the
-- owner's word of 2026-11-17, "update splash art": a Vessari fleet
-- posed in the game and cel-shaded, then redrawn by script/artgen;
-- resource/texture/splash-art.jpg, put to the owner for review). It
-- fills the screen, cut to it, and a band of shade lies behind the name.
--
-- A script is not shown it (its pictures are of the game), unless it
-- asks: Splash.Begin, and GameDebug.Splash in the game app.

local Fonts = require("@lt/Fonts")
local Theme = require("@lt/Game/UI/Theme")
local Im = require("@lt/Game/UI/Im")
local Keys = require("@lt/Game/UI/Keys")

local Splash = {}

-- Seconds: the mark and name coming up, standing, and the black clearing.
Splash.RISE = 1.2
Splash.STAND = 3.0
Splash.CLEAR = 1.1
-- And how long before a key sends it on (so that the key that started
-- the program does not).
local DEAF = 0.3

Splash.TITLE = "LIMITLESS SPACE"
Splash.UNDER = "A  SPACE  SANDBOX  OF  YOUR  OWN"

local INK = vector.create(0.82, 0.90, 0.97)
local MARK = vector.create(0.45, 0.78, 1.0)
local WARM = vector.create(1.0, 0.86, 0.60)

-- The picture behind, loaded the first time it is shown (false if it could not be).
local ART = "texture/splash-art.jpg"
local ART_ASPECT = 1.5
local art: Texture? = nil
local tried = false
local function picture(): Texture?
  if not tried then
    tried = true
    local ok, texture = pcall(Texture_LoadFrom, Location_Resource(ART))
    art = if ok then texture else nil
  end
  return art
end

-- How far through it is, in seconds; negative when it is not up.
local age = -1
-- Whether it has begun since it was last asked (for whoever plays its sound).
local begun = false

function Splash.Begin()
  age = 0
  begun = true
end

function Splash.IsOpen(): boolean
  return age >= 0
end

-- Whether the black still hides everything behind it (so that nothing
-- behind need be drawn, or pressed).
function Splash.Hides(): boolean
  return age >= 0 and age < Splash.RISE + Splash.STAND
end

-- True once, after it has begun.
function Splash.Began(): boolean
  local was = begun
  begun = false
  return was
end

-- How far through it is: "rise", "stand", "clear", or "" when it is not up.
function Splash.Stage(): string
  return if age < 0 then "" elseif age < Splash.RISE then "rise" elseif age < Splash.RISE + Splash.STAND then "stand" else "clear"
end

local function eased(t: number): number
  t = math.clamp(t, 0, 1)
  return t * t * (3 - 2 * t)
end

-- A ring some pixels thick: the glyph's own is a hair.
local function ring(at: vector, radius: number, thick: number, color: vector, alpha: number)
  for step = 0, thick - 1 do
    Glyph_Draw(Glyph_Ring(at * Theme.scale, (radius - step * 0.75) * Theme.scale, 1, 1, 0), 0, 1, color, alpha)
  end
end

-- The mark, about a point, 'size' from side to side.
local function mark(cx: number, cy: number, size: number, alpha: number, turn: number)
  local r = size * 0.27
  local apart = r * 0.82
  local left, right = vector.create(cx - apart, cy), vector.create(cx + apart, cy)
  ring(left, r, 3, MARK, alpha * 0.95)
  ring(right, r, 3, INK, alpha * 0.85)
  -- (a faint wider ring about both: the reach of it)
  Glyph_Draw(Glyph_Ring((vector.create(cx, cy)) * Theme.scale, (r + apart + 10) * Theme.scale, 1, 1, 0), 0, 1, MARK, alpha * 0.22)
  -- the star where they cross
  Glyph_Draw(Glyph_Circle((vector.create(cx, cy)) * Theme.scale, 4.5 * Theme.scale, 1, 1), 0, 1, WARM, alpha)
  Glyph_Draw(Glyph_Circle((vector.create(cx, cy)) * Theme.scale, 11 * Theme.scale, 1, 1), 0, 1, WARM, alpha * 0.16)
  for _, way in { vector.create(1, 0), vector.create(0, 1) } do
    Glyph_Draw(Glyph_LineFade((vector.create(cx, cy)) * Theme.scale, (vector.create(cx, cy) + way * 26) * Theme.scale, 1, 1), 0, 1, WARM, alpha * 0.7)
    Glyph_Draw(Glyph_LineFade((vector.create(cx, cy)) * Theme.scale, (vector.create(cx, cy) - way * 26) * Theme.scale, 1, 1), 0, 1, WARM, alpha * 0.7)
  end
  -- a small world going round the further ring
  local world = right + vector.create(math.cos(turn), math.sin(turn)) * r
  Glyph_Draw(Glyph_Circle(world * Theme.scale, 5.5 * Theme.scale, 1, 1), 0, 1, vector.create(0.02, 0.03, 0.05), alpha)
  Glyph_Draw(Glyph_Circle(world * Theme.scale, 3.5 * Theme.scale, 1, 1), 0, 1, INK, alpha)
end

local function centred(font: Font?, s: string, cx: number, y: number, size: number, color: vector, alpha: number)
  -- (in pixels: the interface's scale is Theme's)
  local big = Theme.Px(size)
  local wide = WidgetRenderer_GetTextSize(font, s, big).x
  WidgetRenderer_DrawText(font, s, vector.create(Theme.Px(cx) - wide / 2, Theme.Px(y) + 0.8 * big), big, color, alpha, false)
end

-- Draw it over whatever is there, and move it on by a frame of
-- 'seconds'. (Whatever is behind is drawn first, by whoever calls,
-- once Splash.Hides says it shows.)
function Splash.Draw(left: number, top: number, width: number, height: number, seconds: number)
  if age < 0 then
    return
  end
  local stand = Splash.RISE + Splash.STAND
  -- (a key or a click sends it on)
  if age > DEAF and age < stand and (Im.Pressed() or Im.RightPressed() or Keys.Heard() ~= nil or Key_Pressed(Key_Space())
    or Key_Pressed(Key_Return()) or Key_Pressed(Key_Escape())) then
    age = stand
  end
  local veil = if age < stand then 1 else 1 - eased((age - stand) / Splash.CLEAR)
  local shown = (if age < stand then eased(age / Splash.RISE) else 1) * (if age < stand then 1 else veil * veil)
  Im.Fill(left, top, width, height, vector.create(0, 0, 0), veil)
  local cx, cy = left + width / 2, top + height / 2
  local size = math.clamp(height * 0.34, 180, 420)
  -- (the picture, cut to fill the screen: it comes up a little behind
  -- the name, and goes with the black)
  local texture = picture()
  if texture then
    local w, h = width, width / ART_ASPECT
    if h < height then
      w, h = height * ART_ASPECT, height
    end
    local come = if age < stand then eased(age / (Splash.RISE * 1.3)) else veil
    WidgetRenderer_DrawTexture(texture, vector.create(Theme.Px(cx - w / 2), Theme.Px(cy - h / 2)), vector.create(Theme.Px(w), Theme.Px(h)),
      come)
    -- (a band of shade where the mark and the name stand)
    local band = size * 1.25
    Im.Fill(left, cy - size * 0.75, width, band, vector.create(0, 0, 0), 0.45 * come)
    Im.Fill(left, cy - size * 0.75 - 24, width, 24, vector.create(0, 0, 0), 0.22 * come)
    Im.Fill(left, cy - size * 0.75 + band, width, 24, vector.create(0, 0, 0), 0.22 * come)
  end
  mark(cx, cy - size * 0.36, size, shown, age * 0.55 - 1.2)
  local title = math.clamp(height * 0.075, 36, 84)
  centred(Fonts.Heading(), Splash.TITLE, cx, cy + size * 0.14, title, INK, shown)
  -- a rule under the name, drawn out from its middle as the name comes up
  local rule = Im.HeadingWidth(Splash.TITLE, title) * 0.5 * (if age < stand then eased(age / (Splash.RISE * 1.4)) else 1)
  Im.Fill(cx - rule, cy + size * 0.14 + title * 1.22, rule * 2, 1, MARK, 0.7 * shown)
  centred(Fonts.Default(), Splash.UNDER, cx, cy + size * 0.14 + title * 1.42, math.max(12, title * 0.22), MARK, 0.75 * shown)
  if age > Splash.RISE and age < stand then
    local pulse = 0.35 + 0.25 * math.sin(age * 3)
    centred(Fonts.Default(), "press any key", cx, top + height - 64, 13, INK, pulse)
  end
  age += seconds
  if age >= stand + Splash.CLEAR then
    age = -1
  end
end

return Splash
