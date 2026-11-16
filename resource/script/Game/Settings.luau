--!strict
-- What a person has set, kept between one run of the game and the next:
-- whether there is sound, how loud its effects and its music are, and
-- the keys that are not what they were at first (Game/UI/Keys). A few
-- lines of "key=value" in save/settings.txt. (And how the window opens,
-- where the windows inside it were left, and what of the picture is
-- switched off.)
--
-- A script's run has the defaults and keeps nothing: a test neither
-- depends on what somebody has set nor changes it.

local Settings = {}

-- (effects and music: 0 to 100; keys: "action:key,action:key", only
-- those a person has changed; windows: where the windows that are
-- moved about were left, as Game/UI/Windows writes it; window: how the
-- game's own window opens, "" for as it sees fit, "borderless" for the
-- screen's size with no border, or "WxH": read by the program as it
-- starts, src/launch; graphics: the stages of the picture that are
-- switched off, as Game/View/Graphics writes them, "" for none; scale:
-- how big the interface is drawn, per cent: 100, 125 or 150)
export type Settings = { sound: boolean, effects: number, music: number, keys: string, windows: string, window: string,
  graphics: string, scale: number }

local PATH = "save/settings.txt"

function Settings.Load(): Settings
  local settings: Settings = { sound = true, effects = 70, music = 70, keys = "", windows = "", window = "", graphics = "", scale = 100 }
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
    settings.keys = found.keys or ""
    settings.windows = found.windows or ""
    settings.window = found.window or ""
    settings.graphics = found.graphics or ""
    local scale = tonumber(found.scale or "") or 100
    settings.scale = if scale >= 140 then 150 elseif scale >= 115 then 125 else 100
  end
  return settings
end

function Settings.Save(settings: Settings)
  if Host.scripted then
    return
  end
  Host.MakeDir("save")
  Host.WriteFile(PATH, `sound={if settings.sound then 1 else 0}\neffects={settings.effects}\nmusic={settings.music}\n`
    .. `keys={settings.keys}\nwindows={settings.windows}\nwindow={settings.window}\ngraphics={settings.graphics}\nscale={settings.scale}\n`)
end

return Settings
