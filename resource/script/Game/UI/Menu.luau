--!strict
-- The menus: the one the game opens on (continue, new game, load,
-- options, quit), and the one Escape brings up in play (resume, save,
-- load, options, back to the first, quit). Options is where the sound
-- is set: on or off, and how loud its effects and its music are; and
-- from it, Keys is where each thing a key does (Game/UI/Keys) is given
-- the key a person likes: its button is clicked, and the next key
-- pressed is its key (Escape leaves it as it was). A key another thing
-- had changes hands: that one gets the key this one gave up.
--
-- While a menu is up the game stands still and nothing else of the
-- interface is drawn (Game/UI/Hud asks Menu.IsOpen). Drawn every frame
-- with Game/UI/Im. Its buttons' names, for a script (Im.Press):
-- "Menu:continue", "Menu:new", "Menu:load", "Menu:save", "Menu:resume",
-- "Menu:main", "Menu:quit", "Menu:back", "Menu:start", "Menu:random",
-- "Menu:options", "Menu:sound", "Menu:keys", "Menu:defaults",
-- "Key:<action>", "Load:<slot>", "Save:<slot>", "Delete:<slot>"; the
-- seed field is "Seed", and the two sliders are "Effects volume" and
-- "Music volume" (Im.Enter).

local Format = require("@lt/Game/Format")
local Im = require("@lt/Game/UI/Im")
local Keys = require("@lt/Game/UI/Keys")
local Session = require("@lt/Game/Session")

local Menu = {}

Menu.WIDTH = 560
-- The most systems a new game's galaxy can be asked to have.
Menu.SYSTEMS = 5000

-- The slots a pilot saves to by hand. (F9 saves to "quick", and docking
-- to "auto".)
local SLOTS = { "save 1", "save 2", "save 3", "save 4", "save 5" }

-- "": no menu. "main" is the opening menu and "pause" the one in play;
-- "new", "load", "save" and "options" are their pages, and "keys" is a
-- page of options.
local page = ""
local root = "main"       -- where Back goes
local seed = 1
local size = 40           -- systems in a new galaxy
local wasPaused = false   -- the clock, before the pause menu stopped it
local saves: { Session.SaveInfo } = {}

local function refresh()
  saves = Session.Saves()
end

-- Whether sound is on and how loud its effects and its music are (of
-- 100), and the asking for it to be otherwise: the game says how
-- (Menu.Sound), since the menu does not own the sound. 'done' is false
-- while a slider is still being dragged, and true when a thing is set.
local soundOn = true
local effects, music = 70, 70
local setSound: ((on: boolean, effects: number, music: number, done: boolean) -> ())? = nil
local unsaved = false     -- a slider has been moved and not yet let go of

function Menu.Sound(on: boolean, effectsLevel: number, musicLevel: number,
  set: (on: boolean, effects: number, music: number, done: boolean) -> ())
  soundOn, effects, music, setSound = on, effectsLevel, musicLevel, set
end

-- How the game's window opens (Game/Settings: "" for as the game sees
-- fit, "borderless", or a size), and the asking for it to be otherwise:
-- the game keeps it (Menu.Window), and it is so from the next start.
-- (no size under 1920 by 1080 is offered: the interface is laid out for
-- that and more, and has no way yet of being drawn smaller)
local WINDOWS = { "", "borderless", "1920x1080", "2560x1440" }
local window = ""
local setWindow: ((choice: string) -> ())? = nil

function Menu.Window(choice: string, set: (choice: string) -> ())
  window, setWindow = choice, set
end

-- How the window is set to open now ("": as the game sees fit).
function Menu.WindowChoice(): string
  return window
end

-- The action a key is being listened for (the keys page), or "". And
-- what the game does when a key has changed hands (it keeps them:
-- Menu.Keys).
local asking = ""
local setKeys: (() -> ())? = nil

function Menu.Keys(set: () -> ())
  setKeys = set
end

-- The action the keys page is listening for a key for, or "".
function Menu.Asking(): string
  return asking
end

function Menu.IsOpen(): boolean
  return page ~= ""
end

function Menu.Page(): string
  return page
end

-- Open the opening menu. The game behind it stands still.
function Menu.OpenMain(session: Session.Session)
  page, root = "main", "main"
  session.clock.paused = true
  refresh()
end

-- Open the menu of a game in play, or close it if it is open. (Escape,
-- while a key is being listened for, is "leave it as it was".)
function Menu.Toggle(session: Session.Session)
  if asking ~= "" then
    asking = ""
    return
  end
  if page == "" then
    page, root = "pause", "pause"
    wasPaused = session.clock.paused
    session.clock.paused = true
    refresh()
  elseif root == "pause" then
    page = ""
    session.clock.paused = wasPaused
  end
end

local function close(session: Session.Session, paused: boolean)
  page = ""
  session.clock.paused = paused
end

-- How long ago a save was made, in words.
local function ago(time: number): string
  if time <= 0 then
    return ""
  end
  local seconds = math.max(0, Host.Time() - time)
  if seconds < 90 then
    return "just now"
  elseif seconds < 5400 then
    return `{math.floor(seconds / 60 + 0.5)} min ago`
  elseif seconds < 129600 then
    return `{math.floor(seconds / 3600 + 0.5)} h ago`
  end
  return `{math.floor(seconds / 86400 + 0.5)} days ago`
end

local function describe(info: Session.SaveInfo): string
  if info.system == "" then
    return "an older save"
  end
  return `{info.system}, {if info.docked then "docked" else "in space"}  -  {info.ship}  -  {Format.Whole(info.wallet)} cr  -  {Format.Duration(info.tick)} in`
end

local function saved(slot: string): Session.SaveInfo?
  for _, info in saves do
    if info.slot == slot then
      return info
    end
  end
  return nil
end

function Menu.Draw(session: Session.Session, left: number, top: number, width: number, height: number)
  -- (while a key is listened for, no key does what it otherwise does)
  if page ~= "keys" then
    asking = ""
  end
  Keys.Listen(asking ~= "")
  if page == "" then
    return
  end
  local w = Menu.WIDTH
  local h = if page == "load" or page == "save" then 420 elseif page == "pause" then 390 elseif page == "main" then 370
    elseif page == "keys" then 550 else 340
  local x, y = left + (width - w) / 2, top + (height - h) / 2 - 40
  -- (the options have a line more than they had, under what was there: what is above stays where it was)
  if page == "options" then
    h = 392
  end
  -- (the game behind is dimmed, so the menu is what there is to read)
  Im.Fill(left, top, width, height, vector.create(0, 0, 0), 0.45)
  Im.Panel(x, y, w, h)
  Im.Fill(x, y, w, h, vector.create(0.02, 0.03, 0.045), 0.9)
  local cx = x + w / 2
  local function button(label: string, row: number, enabled: boolean, id: string): boolean
    return Im.Button(label, cx - 130, y + 96 + row * 44, 260, 34, enabled, id)
  end

  if page == "main" then
    Im.Heading("LIMITLESS SPACE", cx - Im.HeadingWidth("LIMITLESS SPACE", 30) / 2, y + 26, 30, Im.TEXT)
    local newest = saves[1]
    if button("Continue", 0, newest ~= nil, "Menu:continue") and newest then
      if Session.Load(session, newest.slot) then
        close(session, false)
      end
    end
    if newest then
      local line = describe(newest)
      Im.Text(line, cx - Im.TextWidth(line, 12) / 2, y + 96 + 37, 12, Im.DIM)
    end
    if button("New game", 1.4, true, "Menu:new") then
      page = "new"
    end
    if button("Load game", 2.4, #saves > 0, "Menu:load") then
      page = "load"
    end
    if button("Options", 3.4, true, "Menu:options") then
      page = "options"
    end
    if button("Quit", 4.4, true, "Menu:quit") then
      Host.Exit(0)
    end
  elseif page == "pause" then
    Im.Heading("PAUSED", cx - 52, y + 26, 26, Im.TEXT)
    if button("Resume", 0, true, "Menu:resume") then
      close(session, wasPaused)
    end
    if button("Save game", 1, true, "Menu:save") then
      page = "save"
    end
    if button("Load game", 2, #saves > 0, "Menu:load") then
      page = "load"
    end
    if button("Options", 3, true, "Menu:options") then
      page = "options"
    end
    if button("Main menu", 4, true, "Menu:main") then
      page, root = "main", "main"
    end
    if button("Quit", 5, true, "Menu:quit") then
      Host.Exit(0)
    end
  elseif page == "options" then
    Im.Heading("OPTIONS", cx - 62, y + 26, 26, Im.TEXT)
    local set = setSound
    local labelX, sliderX, sliderW = x + 70, x + 190, 250
    Im.Text("Sound", labelX, y + 101, 15, Im.TEXT)
    if set and Im.Button(if soundOn then "On" else "Off", sliderX, y + 96, 90, 28, true, "Menu:sound") then
      soundOn = not soundOn
      set(soundOn, effects, music, true)
    end
    -- How loud: what happens (weapons, engines, the interface), and the
    -- music under it, each on its own. What is heard follows the knob as
    -- it is dragged, and is kept when the knob is let go.
    local wasEffects, wasMusic = effects, music
    Im.Text("Effects", labelX, y + 151, 15, if soundOn then Im.TEXT else Im.DIM)
    effects = Im.Slider("Effects volume", effects, 0, 100, sliderX, y + 148, sliderW, 22, soundOn)
    Im.TextRight(`{effects}%`, x + w - 60, y + 151, 14, if soundOn then Im.TEXT else Im.DIM)
    Im.Text("Music", labelX, y + 197, 15, if soundOn then Im.TEXT else Im.DIM)
    music = Im.Slider("Music volume", music, 0, 100, sliderX, y + 194, sliderW, 22, soundOn)
    Im.TextRight(`{music}%`, x + w - 60, y + 197, 14, if soundOn then Im.TEXT else Im.DIM)
    if set then
      local moved = effects ~= wasEffects or music ~= wasMusic
      unsaved = unsaved or moved
      if unsaved and not Im.Sliding() then
        unsaved = false
        set(soundOn, effects, music, true)
      elseif moved then
        set(soundOn, effects, music, false)
      end
    end
    -- (the page is as tall as it was before it had this button: what is above stays where it was)
    if Im.Button("Keys", cx - 130, y + 240, 260, 34, true, "Menu:keys") then
      page = "keys"
    end
    -- How the game's window opens: a click goes on to the next way. It
    -- is so from the next time the game is started.
    Im.Text("Window", labelX, y + 299, 15, Im.TEXT)
    local shown = if window == "" then "Automatic" elseif window == "borderless" then "Fits the screen"
      else (string.gsub(window, "x", " x "))
    if Im.Button(shown, sliderX, y + 294, 150, 28, setWindow ~= nil, "Menu:window") and setWindow then
      window = WINDOWS[(table.find(WINDOWS, window) or 0) % #WINDOWS + 1]
      setWindow(window)
    end
    Im.Text("from the next start", sliderX + 160, y + 300, 12, Im.DIM)
    if Im.Button("Back", cx - 130, y + h - 50, 260, 34, true, "Menu:back") then
      page = root
    end
  elseif page == "keys" then
    Im.Heading("KEYS", cx - 34, y + 26, 26, Im.TEXT)
    Im.Text(if asking ~= "" then "Press the key it is to have. Escape leaves it as it was."
      else "Click a key to give the thing another. A key something else has changes hands.", x + 30, y + 68, 13,
      if asking ~= "" then Im.ACCENT else Im.DIM)
    -- (the key just pressed is the key of what was clicked)
    if asking ~= "" then
      local heard = Keys.Heard()
      if heard then
        Keys.Bind(asking, heard)
        asking = ""
        if setKeys then
          setKeys()
        end
      end
    end
    -- Everything there is a key for, in two columns.
    local half = math.ceil(#Keys.ACTIONS / 2)
    for index, action in Keys.ACTIONS do
      local column = if index > half then 1 else 0
      local rowX = x + 30 + column * 258
      local rowY = y + 98 + ((index - 1) % half) * 31
      local mine = asking == action.id
      Im.Text(action.label, rowX, rowY + 5, 14, if mine then Im.ACCENT else Im.TEXT)
      if Im.Toggle(if mine then "..." else Keys.Of(action.id), rowX + 150, rowY, 84, 26, mine, `Key:{action.id}`) then
        asking = if mine then "" else action.id
      end
    end
    if Im.Button("Defaults", cx - 266, y + h - 50, 260, 34, not Keys.AtFirst(), "Menu:defaults") then
      Keys.Reset()
      asking = ""
      if setKeys then
        setKeys()
      end
    end
    if Im.Button("Back", cx + 6, y + h - 50, 260, 34, true, "Menu:back") then
      page = "options"
    end
  elseif page == "new" then
    Im.Heading("NEW GAME", cx - 72, y + 26, 26, Im.TEXT)
    Im.Text("A galaxy is made from its seed: the same seed and size, the same galaxy.", x + 40, y + 80, 13, Im.DIM)
    Im.Text("Seed", x + 120, y + 117, 14, Im.DIM)
    seed = math.max(1, math.floor(Im.Number("Seed", seed, x + 190, y + 110, 120, 28)))
    if Im.Button("Random", x + 322, y + 110, 100, 28, true, "Menu:random") then
      seed = math.floor(Host.Time()) % 99991 + 1
    end
    Im.Text("Systems", x + 120, y + 155, 14, Im.DIM)
    -- (as many as five thousand: the project owner's, 2026-11-13. It was four hundred.)
    size = math.clamp(math.floor(Im.Number("Systems", size, x + 190, y + 148, 120, 28)), 3, Menu.SYSTEMS)
    for index, preset in { 40, 400, 2000, Menu.SYSTEMS } do
      if Im.Button(tostring(preset), x + 322 + (index - 1) * 56, y + 148, 52, 28, true, `Systems:{preset}`) then
        size = preset
      end
    end
    if Im.Button("Start", cx - 130, y + 206, 260, 34, true, "Menu:start") then
      Session.Restart(session, seed, seed, size)
      close(session, false)
    end
    if Im.Button("Back", cx - 130, y + 250, 260, 34, true, "Menu:back") then
      page = root
    end
  elseif page == "load" then
    Im.Heading("LOAD GAME", cx - 80, y + 26, 26, Im.TEXT)
    local line = y + 80
    for index, info in saves do
      if index > 8 then
        break
      end
      Im.Text(info.slot, x + 24, line + 5, 14, Im.TEXT)
      Im.Text(describe(info), x + 100, line + 2, 12, Im.DIM)
      Im.Text(ago(info.time), x + 100, line + 17, 11, Im.DIM, 0.7)
      if Im.Button("Load", x + w - 150, line + 2, 60, 26, true, `Load:{info.slot}`) then
        if Session.Load(session, info.slot) then
          close(session, false)
        end
      end
      if Im.Button("Delete", x + w - 84, line + 2, 60, 26, true, `Delete:{info.slot}`) then
        Session.Delete(info.slot)
        refresh()
      end
      line += 36
    end
    if #saves == 0 then
      Im.Text("There are no saves.", x + 24, line, 14, Im.DIM)
    end
    if Im.Button("Back", cx - 130, y + h - 50, 260, 34, true, "Menu:back") then
      page = root
    end
  elseif page == "save" then
    Im.Heading("SAVE GAME", cx - 80, y + 26, 26, Im.TEXT)
    local line = y + 80
    for _, slot in SLOTS do
      local info = saved(slot)
      Im.Text(slot, x + 24, line + 5, 14, Im.TEXT)
      Im.Text(if info then describe(info) else "empty", x + 100, line + 2, 12, Im.DIM, if info then 1 else 0.6)
      if info then
        Im.Text(ago(info.time), x + 100, line + 17, 11, Im.DIM, 0.7)
      end
      if Im.Button(if info then "Overwrite" else "Save", x + w - 110, line + 2, 86, 26, true, `Save:{slot}`) then
        Session.Save(session, slot)
        refresh()
      end
      line += 36
    end
    Im.Text(`{Keys.Of("save")} saves to 'quick' at any time, and docking saves to 'auto'.`, x + 24, line + 8, 12, Im.DIM, 0.8)
    if Im.Button("Back", cx - 130, y + h - 50, 260, 34, true, "Menu:back") then
      page = root
    end
  end
end

return Menu
