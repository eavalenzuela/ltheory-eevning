--!strict
-- What a person has set, kept between one run of the game and the next:
-- whether there is sound, and how loud its effects and its music are. A
-- few lines of "key=value" in save/settings.txt.
--
-- A script's run has the defaults and keeps nothing: a test neither
-- depends on what somebody has set nor changes it.

local Settings = {}

-- (effects and music: 0 to 100)
export type Settings = { sound: boolean, effects: number, music: number }

local PATH = "save/settings.txt"

function Settings.Load(): Settings
  local settings: Settings = { sound = true, effects = 70, music = 70 }
  local file = if Host.scripted then nil else Host.ReadFile(PATH)
  if file then
    local found: { [string]: string } = {}
    for key: string, value: string in string.gmatch(buffer.tostring(file), "(%w+)=([^\n]*)") :: any do
      found[key] = value
    end
    local function level(value: string?, otherwise: number): number
      return math.clamp(math.floor(tonumber(value or "") or otherwise), 0, 100)
    end
    if found.sound then
      settings.sound = found.sound ~= "0"
    end
    -- (there used to be the one loudness, for everything: a file from
    -- then sets both)
    local both = level(found.volume, 70)
    settings.effects = level(found.effects, both)
    settings.music = level(found.music, both)
  end
  return settings
end

function Settings.Save(settings: Settings)
  if Host.scripted then
    return
  end
  Host.MakeDir("save")
  Host.WriteFile(PATH, `sound={if settings.sound then 1 else 0}\neffects={settings.effects}\nmusic={settings.music}\n`)
end

return Settings
