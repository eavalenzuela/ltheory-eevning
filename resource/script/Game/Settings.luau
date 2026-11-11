--!strict
-- What a person has set, kept between one run of the game and the next:
-- whether there is sound, and how loud. A few lines of "key=value" in
-- save/settings.txt.
--
-- A script's run has the defaults and keeps nothing: a test neither
-- depends on what somebody has set nor changes it.

local Settings = {}

export type Settings = { sound: boolean, volume: number }  -- volume: 0 to 100

local PATH = "save/settings.txt"

function Settings.Load(): Settings
  local settings: Settings = { sound = true, volume = 70 }
  local file = if Host.scripted then nil else Host.ReadFile(PATH)
  if file then
    for key: string, value: string in string.gmatch(buffer.tostring(file), "(%w+)=([^\n]*)") :: any do
      if key == "sound" then
        settings.sound = value ~= "0"
      elseif key == "volume" then
        settings.volume = math.clamp(math.floor(tonumber(value) or 70), 0, 100)
      end
    end
  end
  return settings
end

function Settings.Save(settings: Settings)
  if Host.scripted then
    return
  end
  Host.MakeDir("save")
  Host.WriteFile(PATH, `sound={if settings.sound then 1 else 0}\nvolume={settings.volume}\n`)
end

return Settings
