--!strict
-- The menus: the one the game opens on (continue, new game, load,
-- quit), and the one Escape brings up in play (resume, save, load, back
-- to the first, quit).
--
-- While a menu is up the game stands still and nothing else of the
-- interface is drawn (Game/UI/Hud asks Menu.IsOpen). Drawn every frame
-- with Game/UI/Im. Its buttons' names, for a script (Im.Press):
-- "Menu:continue", "Menu:new", "Menu:load", "Menu:save", "Menu:resume",
-- "Menu:main", "Menu:quit", "Menu:back", "Menu:start", "Menu:random",
-- "Load:<slot>", "Save:<slot>", "Delete:<slot>"; the seed field is
-- "Seed".

local Format = require("@lt/Game/Format")
local Im = require("@lt/Game/UI/Im")
local Session = require("@lt/Game/Session")

local Menu = {}

Menu.WIDTH = 560

-- The slots a pilot saves to by hand. (F9 saves to "quick", and docking
-- to "auto".)
local SLOTS = { "save 1", "save 2", "save 3", "save 4", "save 5" }

-- "": no menu. "main" is the opening menu and "pause" the one in play;
-- "new", "load" and "save" are their pages.
local page = ""
local root = "main"       -- where Back goes
local seed = 1
local size = 40           -- systems in a new galaxy
local wasPaused = false   -- the clock, before the pause menu stopped it
local saves: { Session.SaveInfo } = {}

local function refresh()
  saves = Session.Saves()
end

-- Whether sound is on, and the asking of it to be otherwise: the game
-- says how (Menu.Sound), since the menu does not own the sound.
local soundOn = true
local setSound: ((on: boolean) -> ())? = nil

function Menu.Sound(on: boolean, set: (on: boolean) -> ())
  soundOn, setSound = on, set
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

-- Open the menu of a game in play, or close it if it is open.
function Menu.Toggle(session: Session.Session)
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
  if page == "" then
    return
  end
  local w = Menu.WIDTH
  local h = if page == "load" or page == "save" then 420 else 340
  local x, y = left + (width - w) / 2, top + (height - h) / 2 - 40
  -- (the game behind is dimmed, so the menu is what there is to read)
  Im.Fill(left, top, width, height, vector.create(0, 0, 0), 0.45)
  Im.Panel(x, y, w, h)
  Im.Fill(x, y, w, h, vector.create(0.02, 0.03, 0.045), 0.9)
  local cx = x + w / 2
  local function button(label: string, row: number, enabled: boolean, id: string): boolean
    return Im.Button(label, cx - 130, y + 96 + row * 44, 260, 34, enabled, id)
  end
  if (page == "main" or page == "pause") and setSound then
    if Im.Button(if soundOn then "Sound: on" else "Sound: off", x + w - 126, y + 14, 110, 26, true, "Menu:sound") then
      soundOn = not soundOn
      setSound(soundOn)
    end
  end

  if page == "main" then
    Im.Heading("LIMIT THEORY", cx - 118, y + 26, 30, Im.TEXT)
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
    if button("Quit", 3.4, true, "Menu:quit") then
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
    if button("Main menu", 3, true, "Menu:main") then
      page, root = "main", "main"
    end
    if button("Quit", 4, true, "Menu:quit") then
      Host.Exit(0)
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
    size = math.clamp(math.floor(Im.Number("Systems", size, x + 190, y + 148, 120, 28)), 3, 400)
    for index, preset in { 3, 40, 120, 400 } do
      if Im.Button(tostring(preset), x + 322 + (index - 1) * 46, y + 148, 42, 28, true, `Systems:{preset}`) then
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
    Im.Text("F9 saves to 'quick' at any time, and docking saves to 'auto'.", x + 24, line + 8, 12, Im.DIM, 0.8)
    if Im.Button("Back", cx - 130, y + h - 50, 260, 34, true, "Menu:back") then
      page = root
    end
  end
end

return Menu
