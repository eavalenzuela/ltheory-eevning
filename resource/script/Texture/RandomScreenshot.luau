--!strict
-- A random screenshot from the folder the launcher's F1 key saves to, or
-- the splash image if there aren't any yet (Luau port of
-- Texture/RandomScreenshot.lts).

local DIR = "cache/screenshot/"
local SPLASH = "resource/texture/splash.png"

return {
  Get = function(): Texture
    local path = SPLASH
    if OS_IsDirectory(DIR) then
      local contents = Directory_List(DIR)
      if contents.size > 0 then
        path = DIR .. contents:Get(Int_Random(contents.size))
      end
    end
    return Texture_LoadFrom(Location_File(path))
  end,
}
