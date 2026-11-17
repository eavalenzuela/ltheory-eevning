--!strict
-- A character's face (Core/Character/Characters): one of the game's own
-- portraits (the owner's two drawn sets of sixteen, 2026-11-17:
-- resource/texture/portraits), a badge, or a picture of the player's own.
--
-- The owner's ruling, 2026-11-17: "Pick from a set + import". There is
-- no art for faces, so the set is badges, made the way the item icons
-- are: a field in one of eight colours, banded, with an emblem on it
-- drawn from a few shapes. 'n' runs 1 to Characters.BADGES; each is
-- another colour and another emblem. A picture is a file beside the
-- character (Game/Session), drawn as it is.
--
--   Portrait.Draw("badge:7", x, y, 64)

local Characters = require("@lt/Core/Character/Characters")
local Session = require("@lt/Game/Session")
local Theme = require("@lt/Game/UI/Theme")

local Portrait = {}

local function v(x: number, y: number): vector
  return vector.create(x, y)
end

-- The fields' colours, and the emblem's shapes, in a square -1 to 1.
local FIELDS: { vector } = {
  vector.create(0.20, 0.34, 0.58), vector.create(0.52, 0.22, 0.20), vector.create(0.20, 0.44, 0.32), vector.create(0.46, 0.38, 0.16),
  vector.create(0.36, 0.24, 0.50), vector.create(0.16, 0.42, 0.48), vector.create(0.42, 0.42, 0.44), vector.create(0.50, 0.28, 0.40),
}
local EMBLEMS: { () -> { Glyph } } = {
  -- a chevron
  function()
    return { Glyph_Triangle(v(-0.7, 0.1), v(0, -0.6), v(0.7, 0.1), 1, 1), Glyph_Triangle(v(-0.7, 0.55), v(0, -0.15), v(0.7, 0.55), 1, 0.7) }
  end,
  -- a star of lines
  function()
    local out = {}
    for k = 0, 3 do
      local a = k * math.pi / 4
      table.insert(out, Glyph_Line(v(math.cos(a) * 0.75, math.sin(a) * 0.75), v(-math.cos(a) * 0.75, -math.sin(a) * 0.75), 1, 1))
    end
    table.insert(out, Glyph_Circle(0, 0.18, 1, 1))
    return out
  end,
  -- rings about a dot
  function()
    return { Glyph_Ring(0, 0.75, 1, 1, 0), Glyph_Ring(0, 0.45, 1, 0.7, 0), Glyph_Circle(0, 0.16, 1, 1) }
  end,
  -- a diamond
  function()
    return { Glyph_Triangle(v(0, -0.8), v(-0.55, 0), v(0.55, 0), 1, 1), Glyph_Triangle(v(0, 0.8), v(-0.55, 0), v(0.55, 0), 1, 0.75) }
  end,
  -- a wing
  function()
    return { Glyph_Triangle(v(-0.8, 0.4), v(0.1, -0.7), v(0.2, 0.4), 1, 1), Glyph_Triangle(v(0.2, 0.4), v(0.8, -0.2), v(0.4, 0.4), 1, 0.7),
      Glyph_Box(v(0, 0.6), v(0.8, 0.08), 1, 0.9) }
  end,
  -- a tower of bars
  function()
    return { Glyph_Box(v(0, -0.5), v(0.25, 0.12), 1, 1), Glyph_Box(v(0, -0.05), v(0.45, 0.12), 1, 0.85), Glyph_Box(v(0, 0.4), v(0.65, 0.12), 1, 0.7) }
  end,
}

local built: { [number]: Icon } = {}
local function emblem(index: number): Icon
  local made = built[index]
  if made then
    return made
  end
  local icon = Icon_Create()
  for _, glyph in EMBLEMS[index]() do
    Icon_AddGlyph(icon, glyph)
  end
  built[index] = icon
  return icon
end

-- Pictures by where they are: loaded once (and one that could not be, tried once).
local pictures: { [string]: Texture } = {}
local failed: { [string]: boolean } = {}
local function picture(path: string): Texture?
  if not pictures[path] and not failed[path] then
    -- (the game's own, from its resources; a player's, from their file)
    local n = string.match(path, "^portrait:(%d+)$")
    local ok, texture = pcall(Texture_LoadFrom,
      if n then Location_Resource(string.format("texture/portraits/portrait-%02d.png", tonumber(n) :: number)) else Location_File(path))
    if ok and texture then
      pictures[path] = texture
    else
      failed[path] = true
    end
  end
  return pictures[path]
end

-- Forget a picture (one replaced, or thrown away).
function Portrait.Forget(portrait: string)
  local path = Session.PictureOf(portrait)
  if path then
    pictures[path], failed[path] = nil, nil
  end
end

-- The badge a portrait is, 1 to Characters.BADGES (1 for a picture).
local function badgeOf(portrait: string): number
  local n = tonumber(string.match(portrait, "^badge:(%d+)$") or "") or 1
  return math.clamp(n, 1, Characters.BADGES)
end

-- Draw a portrait with its top-left corner at (x, y), 'size' square.
function Portrait.Draw(portrait: string, x: number, y: number, size: number)
  if Theme.scale ~= 1 then
    x, y, size = Theme.Px(x), Theme.Px(y), Theme.Px(size)
  end
  local own = tonumber(string.match(portrait, "^portrait:(%d+)$") or "")
  local path = if own then `portrait:{math.clamp(own, 1, Characters.PORTRAITS)}` else Session.PictureOf(portrait)
  local texture = if path then picture(path) else nil
  if texture then
    WidgetRenderer_DrawPanel(vector.create(x, y), vector.create(size, size), vector.create(0.05, 0.06, 0.08), 1, 1, 0)
    WidgetRenderer_DrawTexture(texture, vector.create(x, y), vector.create(size, size), 1)
    return
  end
  local n = badgeOf(portrait)
  local field = FIELDS[(n - 1) % #FIELDS + 1]
  local round = math.max(2, size / 10)
  WidgetRenderer_DrawPanel(vector.create(x, y), vector.create(size, size), field, 0.75, 1, round)
  -- (a band across the foot, darker, as the item tiles have their pips)
  WidgetRenderer_DrawPanel(vector.create(x, y + size * 0.78), vector.create(size, size * 0.22), field * 0.55, 0.9, 1, 0)
  -- (eight colours and six emblems, which go round together twenty-four
  -- times before a colour has the same emblem again)
  local index = (n - 1) % #EMBLEMS + 1
  Icon_Draw(emblem(index), vector.create(x + size / 2, y + size * 0.42), size * 0.3, vector.create(0.94, 0.96, 1.0), 1)
end

return Portrait
