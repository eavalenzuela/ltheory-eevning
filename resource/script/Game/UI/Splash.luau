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

-- Seconds: the mark and name coming up, standing (at the least: it stands
-- until a key or a click sends it on), and the black clearing.
Splash.RISE = 1.2
Splash.STAND = 3.0
Splash.CLEAR = 1.1
-- And how long before a key sends it on (so that the key that started
-- the program does not).
local DEAF = 0.3

Splash.TITLE = "LIMITLESS SPACE"

-- Where the mark and the name stand above the middle of the screen, and
-- the band of shade behind them, in the mark's sizes: between the black
-- hole at the top of the picture and the fleet below (2026-11-27).
local MARK_AT, NAME_AT = 0.46, 0.16
local BAND_TOP, BAND = 0.78, 0.94

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
-- Whether a key or a click has sent it on: until then it stands, as it
-- says (the owner, 2026-11-27: it went by itself after a few seconds).
local sent = false
-- Seconds it has been up, for the pulse of "press any key" while it waits.
local shownFor = 0

function Splash.Begin()
  age = 0
  begun = true
  sent = false
  shownFor = 0
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

-- The mark, about a point, 'size' from side to side: an infinity sign,
-- one fine line that runs on round itself, and three lights going round
-- it for ever (the owner, 2026-11-27: "The logo should be an actual
-- infinity symbol"; the fourth of four tried). Its way round: the
-- lemniscate of Bernoulli, a little taller than it is.
local function along(t: number, half: number): vector
  local s, c = math.sin(t), math.cos(t)
  local d = 1 + s * s
  return vector.create(half * c / d, half * 1.25 * s * c / d)
end

-- Steps of the line round, and the lights on it.
local STEPS = 200
local LIGHTS = 3

local function mix(a: vector, b: vector, k: number): vector
  return a + (b - a) * k
end

-- The line round, so wide (half, pixels), in fine lines laid side by side
-- a little under a pixel apart: the glyphs add their light, so a filled
-- shape would glow at every seam, and lines do not. Blue round the left,
-- white round the right.
local function trace(cx: number, cy: number, half: number, wide: number, alpha: number, tinted: boolean)
  local lines = math.max(1, math.ceil(2 * wide / 0.8))
  local last: { vector } = {}
  for i = 0, STEPS do
    local t = i / STEPS * 2 * math.pi
    local p = along(t, half)
    local way = vector.normalize(along(t + 0.002, half) - p)
    local n = vector.create(-way.y, way.x)
    local centre = vector.create(cx, cy) + p
    local color = if tinted then mix(MARK, INK, (1 + math.cos(t)) / 2) else MARK
    for k = 0, lines - 1 do
      local o = -wide + (k + 0.5) * 2 * wide / lines
      local at = centre + n * o
      if i > 0 then
        Glyph_Draw(Glyph_Line(last[k] * Theme.scale, at * Theme.scale, 1, 1), 0, 1, color, alpha)
      end
      last[k] = at
    end
  end
end

local function mark(cx: number, cy: number, size: number, alpha: number, turn: number)
  local half = size * 0.62
  -- (a soft glow, and the line in it)
  trace(cx, cy, half, 4, alpha * 0.06, false)
  trace(cx, cy, half, 1.2, alpha * 0.8, true)
  for k = 0, LIGHTS - 1 do
    local at = vector.create(cx, cy) + along(turn * 0.7 + k * 2 * math.pi / LIGHTS, half)
    Glyph_Draw(Glyph_Circle(at * Theme.scale, 9 * Theme.scale, 1, 1), 0, 1, WARM, alpha * 0.18)
    Glyph_Draw(Glyph_Circle(at * Theme.scale, 3.5 * Theme.scale, 1, 1), 0, 1, WARM, alpha)
  end
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
    sent = true
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
    local band = size * BAND
    Im.Fill(left, cy - size * BAND_TOP, width, band, vector.create(0, 0, 0), 0.45 * come)
    Im.Fill(left, cy - size * BAND_TOP - 24, width, 24, vector.create(0, 0, 0), 0.22 * come)
    Im.Fill(left, cy - size * BAND_TOP + band, width, 24, vector.create(0, 0, 0), 0.22 * come)
  end
  mark(cx, cy - size * MARK_AT, size, shown, age * 0.55 - 1.2)
  local title = math.clamp(height * 0.075, 36, 84)
  centred(Fonts.Heading(), Splash.TITLE, cx, cy - size * NAME_AT, title, INK, shown)
  -- a rule under the name, drawn out from its middle as the name comes up
  local rule = Im.HeadingWidth(Splash.TITLE, title) * 0.5 * (if age < stand then eased(age / (Splash.RISE * 1.4)) else 1)
  Im.Fill(cx - rule, cy - size * NAME_AT + title * 1.22, rule * 2, 1, MARK, 0.7 * shown)
  if age > Splash.RISE and age < stand then
    local pulse = 0.35 + 0.25 * math.sin(shownFor * 3)
    centred(Fonts.Default(), "press any key", cx, top + height - 64, 13, INK, pulse)
  end
  age += seconds
  shownFor += seconds
  -- (it stands until it is sent on)
  if not sent and age >= stand then
    age = stand - 1e-3
  end
  if age >= stand + Splash.CLEAR then
    age = -1
  end
end

return Splash
