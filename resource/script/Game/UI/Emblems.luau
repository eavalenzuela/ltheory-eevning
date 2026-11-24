--!strict
-- The factions' emblems (resource/texture/factions, put in by script/artgen
-- emblems). The owner, 2026-11-24: "full-size logos for the factions, pure
-- art not icons, and then derive icons from those"; an icon "2-layer ... in
-- their livery colors, and the border glow behind each one will be their
-- interface color". So an icon is drawn in layers, each tinted: its body
-- in the livery's first colour, its detail in the second, and (the
-- Unbound's sash alone, "a special exception") an accent in the livery's
-- glow; behind them a glow round its outer edge in Theme.WHOSE's colour.

local EmblemSet = require("@lt/Game/UI/EmblemSet")
local Factions = require("@lt/Core/Data/Factions")
local Theme = require("@lt/Game/UI/Theme")

local Emblems = {}

local textures: { [string]: Texture } = {}
-- (a picture that would not load, not tried again)
local missing: { [string]: boolean } = {}

local function load(path: string): Texture?
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

local function color(rgb: { number }): vector
  return vector.create(rgb[1], rgb[2], rgb[3])
end

-- Whether a faction has an emblem.
function Emblems.Has(faction: string): boolean
  return EmblemSet.factions[faction] ~= nil
end

-- The faction of this name ("Vessari"), or "".
function Emblems.Named(name: string): string
  for _, faction in Factions.list do
    if faction.name == name then
      return faction.id
    end
  end
  return ""
end

-- Draw a faction's icon about (cx, cy), 'size' across with its glow (in
-- the interface's units). False where it has none.
function Emblems.Draw(faction: string, cx: number, cy: number, size: number, alpha: number?): boolean
  local set = EmblemSet.factions[faction]
  local data = Factions.byId[faction]
  if set == nil or data == nil then
    return false
  end
  local scale = Theme.scale
  local px = math.floor(size * scale + 0.5)
  local pick = EmblemSet.sizes[#EmblemSet.sizes]
  for _, each in EmblemSet.sizes do
    if each >= px then
      pick = each
      break
    end
  end
  local x = math.floor(cx * scale - px / 2 + 0.5)
  local y = math.floor(cy * scale - px / 2 + 0.5)
  local at, wide = vector.create(x, y), vector.create(px, px)
  local a = alpha or 1
  local paint = data.paint
  local layers: { { name: string, tint: vector } } = {
    { name = "glow", tint = Theme.WHOSE[faction] or Theme.ACCENT },
    { name = "body", tint = color(paint.primary) },
    { name = "detail", tint = color(paint.secondary) },
  }
  if set.accent then
    table.insert(layers, { name = "accent", tint = color(paint.glow) })
  end
  for _, layer in layers do
    local texture = load(`texture/factions/{pick}/{faction}.{layer.name}.png`)
    if texture == nil then
      return false
    end
    WidgetRenderer_DrawTextureTinted(texture, at, wide, layer.tint, a)
  end
  return true
end

-- Draw a faction's full logo, its corner at (x, y), 'size' across. False
-- where it has none.
function Emblems.Logo(faction: string, x: number, y: number, size: number, alpha: number?): boolean
  if EmblemSet.factions[faction] == nil then
    return false
  end
  local texture = load(`texture/factions/logo/{faction}.png`)
  if texture == nil then
    return false
  end
  local scale = Theme.scale
  WidgetRenderer_DrawTexture(texture, vector.create(math.floor(x * scale + 0.5), math.floor(y * scale + 0.5)),
    vector.create(math.floor(size * scale + 0.5), math.floor(size * scale + 0.5)), alpha or 1)
  return true
end

return Emblems
