--!strict
-- The UI fonts (Luau port of Fonts.lts), loaded on first use.

local cache: { [string]: Font } = {}

local function get(path: string): Font
  local font = cache[path]
  if not font then
    font = Font_Get(path)
    cache[path] = font
  end
  return font
end

return {
  Medium = function(): Font return get("Rajdhani/Medium.ttf") end,
  ChineseSimp = function(): Font return get("NotoSansCJKSC/Regular.otf") end,
  Light = function(): Font return get("Rajdhani/Light.ttf") end,
  Default = function(): Font return get("Rajdhani/Regular.ttf") end,
  Heading = function(): Font return get("Iceland/Regular.ttf") end,
  Subheading = function(): Font return get("Iceland/Regular.ttf") end,
  Unicode = function(): Font return get("NotoSans/Regular.ttf") end,
}
