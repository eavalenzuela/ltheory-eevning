--!strict
-- The overview's signs: a white glyph for each kind of thing in space
-- (resource/texture/glyphs, drawn by script/artgen glyphs from
-- script/overviewglyphs.txt), tinted by what it is to the pilot. The
-- owner, 2026-11-23: "I do like this manner", and 16 px "the best
-- compromise of size and clarity". A ship's is its class's: chevrons
-- for warships, crates for haulers, a heavy bar under a capital, as its
-- insignia in the inventory are.

local Core = require("@lt/Core/Api")
local GlyphSet = require("@lt/Game/UI/GlyphSet")
local Ores = require("@lt/Core/Data/Ores")
local Ships = require("@lt/Core/Data/Ships")
local Theme = require("@lt/Game/UI/Theme")

local Signs = {}

-- The size a sign is drawn at, before the interface's scale.
Signs.SIZE = 16

local KINDS: { [string]: string } = { sun = "sun", planet = "planet", moon = "moon", belt = "belt", asteroid = "asteroid",
  station = "station", gate = "gate", wormhole = "wormhole", wreck = "wreck", site = "site", bookmark = "bookmark" }

-- The sign of a thing on the overview, or "" where there is none.
function Signs.Of(entry: Core.Entry): string
  local kind = entry.kind
  local variety = entry.variety
  local found = ""
  if kind == "ship" then
    if string.sub(variety, 1, 6) == "works." then
      -- (a station's battery, a tower, a pirates' keep or fortress)
      found = if string.find(variety, "battery", 1, true) then "battery"
        elseif string.find(variety, "tower", 1, true) then "tower" else "station"
    elseif string.sub(variety, 1, 6) == "drone." then
      found = if string.find(variety, "bomber", 1, true) then "bomber"
        elseif string.find(variety, "fighter", 1, true) or string.find(variety, "trident", 1, true) then "fighter"
        else "drone"
    else
      local hull = Ships.byId[variety]
      found = if hull then hull.class else "frigate"
    end
  elseif kind == "station" then
    found = if variety == "citadel" then "citadel" elseif variety == "starbase" then "tower" else "station"
  elseif kind == "gate" then
    found = if variety == "passage" then "wormhole" else "gate"
  elseif kind == "asteroid" then
    found = if Ores.gasById[variety] ~= nil then "cloud" elseif string.sub(variety, 1, 4) == "ice." then "ice" else "asteroid"
  elseif kind == "belt" then
    found = if variety == "ice" then "ice" else "belt"
  elseif kind == "wreck" then
    found = if string.sub(variety, 1, 6) == "vault." then "vault" elseif variety == "sealed" then "container"
      elseif variety ~= "" then "depot" else "wreck"
  else
    found = KINDS[kind] or ""
  end
  return if GlyphSet.kinds[found] then found else ""
end

-- What each tag is drawn in (Core's Entry 'tag'): the shape says what
-- it is, and its colour, at a glance, whether it matters now.
Signs.TAG_COLORS = {
  wartarget = vector.create(1.0, 0.42, 0.85), jobtarget = Theme.CAUTION,
  wanted = vector.create(1.0, 0.6, 0.22), fleet = vector.create(0.72, 0.56, 1.0),
  corp = Theme.GOOD, friendly = Theme.SHIELD,
} :: { [string]: vector }

-- The four kinds of damage, in Attributes' order (EM, thermal, kinetic,
-- explosive), and a ship's three layers: the fitting screen's signs (the
-- owner's picks, 2026-11-24).
Signs.DAMAGE = { "em", "thermal", "kinetic", "explosive" }
Signs.LAYERS = { shield = "shield", armor = "armour", hull = "hull" } :: { [string]: string }

-- The red dot beside the name of a ship after the pilot's (Core's Entry
-- 'aggressor'), about (cx, cy).
function Signs.Aggressor(cx: number, cy: number, alpha: number?)
  local a = alpha or 1
  WidgetRenderer_DrawPanelRadial(Theme.Point(cx, cy), 0, 3.5 * Theme.scale, 0, 1, Theme.BAD, a, a, 0)
end

-- Draw a ship's tag about (cx, cy), 'size' across: false for none.
function Signs.Tag(tag: string?, cx: number, cy: number, size: number, alpha: number?): boolean
  if tag == nil then
    return false
  end
  local color: vector? = Signs.TAG_COLORS[tag]
  if color then
    return Signs.Draw(tag, cx, cy, size, color, alpha)
  end
  return false
end

local textures: { [string]: Texture } = {}
-- (a sign whose picture would not load, not tried again)
local missing: { [string]: boolean } = {}

local function texture(sign: string, px: number): Texture?
  local size = GlyphSet.sizes[#GlyphSet.sizes]
  for _, each in GlyphSet.sizes do
    if each >= px then
      size = each
      break
    end
  end
  local path = `texture/glyphs/{size}/{sign}.png`
  local made: Texture? = textures[path]
  if made == nil and not missing[path] then
    local ok, loaded = pcall(Texture_LoadFrom, Location_Resource(path))
    if ok and loaded then
      textures[path] = loaded
      made = loaded
    else
      missing[path] = true
    end
  end
  return made
end

-- Draw a sign about (cx, cy), 'size' across (in the interface's units,
-- as Icons.Draw's), in one colour. False where the sign is not in.
function Signs.Draw(sign: string, cx: number, cy: number, size: number, color: vector, alpha: number?): boolean
  if sign == "" then
    return false
  end
  local scale = Theme.scale
  local px = math.floor(size * scale + 0.5)
  local made = texture(sign, px)
  if made == nil then
    return false
  end
  -- (on whole pixels, so a stroke stays sharp)
  local x = math.floor(cx * scale - px / 2 + 0.5)
  local y = math.floor(cy * scale - px / 2 + 0.5)
  WidgetRenderer_DrawTextureTinted(made, vector.create(x, y), vector.create(px, px), color, alpha or 1)
  return true
end

return Signs
