--!strict
-- The menus: the one the game opens on (continue, new game, load,
-- options, quit), and the one Escape brings up in play (resume, save,
-- load, options, back to the first, quit). Options is where the sound
-- is set: on or off, and how loud its effects and its music are; and
-- from it, Keys is where each thing a key does (Game/UI/Keys) is given
-- the key a person likes: its button is clicked, and the next key
-- pressed is its key (Escape leaves it as it was). A key another thing
-- had changes hands: that one gets the key this one gave up. And
-- Graphics is where each stage the picture is made in is switched off
-- and on (Game/View/Graphics).
--
-- While a menu is up the game stands still and nothing else of the
-- interface is drawn (Game/UI/Hud asks Menu.IsOpen). Drawn every frame
-- with Game/UI/Im. Its buttons' names, for a script (Im.Press):
-- "Menu:continue", "Menu:new", "Menu:load", "Menu:save", "Menu:resume",
-- "Menu:main", "Menu:quit", "Menu:back", "Menu:start", "Menu:random",
-- "Menu:options", "Menu:sound", "Menu:keys", "Menu:defaults",
-- "Menu:graphics", "Menu:allon", "Graphics:<stage>" (Game/View/Graphics),
-- "Graphics:look:<id>" (standard, cel1, cel2), "Graphics:view", "Graphics:blend",
-- "Key:<action>", "Load:<slot>", "Save:<slot>", "Delete:<slot>"; the
-- seed field is "Seed", and the two sliders are "Effects volume" and
-- "Music volume" (Im.Enter).
--
-- And the characters (Core/Character/Characters, 2026-11-17): the main
-- menu says whose games are played, "Menu:characters" lists them,
-- "Character:play:<id>" plays as one and "Character:delete:<id>" throws
-- one away (twice, to be sure); "Menu:newcharacter" makes one, of the
-- name in "Character name", the face "Face:<n>" picked (the game's own
-- portraits), or the picture in the file named in "Picture file"
-- ("Menu:make").

local Characters = require("@lt/Core/Character/Characters")
local Skills = require("@lt/Core/Data/Skills")
local Format = require("@lt/Game/Format")
local Graphics = require("@lt/Game/View/Graphics")
local Im = require("@lt/Game/UI/Im")
local Keys = require("@lt/Game/UI/Keys")
local List = require("@lt/Game/UI/List")
local Portrait = require("@lt/Game/UI/Portrait")
local Theme = require("@lt/Game/UI/Theme")
local Session = require("@lt/Game/Session")

local Menu = {}

Menu.WIDTH = 560
-- The most systems a new game's galaxy can be asked to have.
Menu.SYSTEMS = 5000

-- The slots a pilot saves to by hand. (F9 saves to "quick", and docking
-- to "auto".)
local SLOTS = { "save 1", "save 2", "save 3", "save 4", "save 5" }

-- "": no menu. "main" is the opening menu and "pause" the one in play;
-- "new", "load", "save" and "options" are their pages, and "keys" and
-- "graphics" are pages of options.
local page = ""
local root = "main"       -- where Back goes
local seed = 1
local size = 40           -- systems in a new galaxy
local wasPaused = false   -- the clock, before the pause menu stopped it
local saves: { Session.SaveInfo } = {}
local characters: { Characters.Character } = {}
-- A character being made: its name, the badge picked, a picture's file;
-- what went wrong last; and a character a Delete has been pressed for once.
local newName, newFace, newPicture, problem, doomed = "", 1, "", "", ""
-- Whether the pane a character is made in is up (over the characters and games).
local making = false

local function refresh()
  saves = Session.Saves()
  characters = Session.Characters()
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

-- How big the interface is drawn, per cent (100, 125 or 150), and the
-- asking for it to be otherwise: the game keeps it and sets it
-- (Menu.Scale), at once. (The owner's "Yes" to a setting for it,
-- 2026-11-15.) A size that would leave the screen too short for the
-- windows is not offered: SCALE_ROOM of the interface's units of height
-- is the least.
local SCALES = { 100, 125, 150 }
local SCALE_ROOM = 800
local scalePercent = 100
local setScale: ((percent: number) -> ())? = nil

function Menu.Scale(percent: number, set: (percent: number) -> ())
  scalePercent, setScale = percent, set
end

-- The action a key is being listened for (the keys page), or "". And
-- what the game does when a key has changed hands (it keeps them:
-- Menu.Keys).
local asking = ""
local setKeys: (() -> ())? = nil

function Menu.Keys(set: () -> ())
  setKeys = set
end

-- What the game does when a stage of the picture has been switched (it
-- keeps what is off: Menu.Graphics).
local setGraphics: (() -> ())? = nil

function Menu.Graphics(set: () -> ())
  setGraphics = set
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

-- ---------------------------------------------------------------------
-- The characters and their games, on one screen (the owner, 2026-11-17:
-- "unify the character and save selection screen, with the save/
-- universe on the right, and the character list on the left, scrolling
-- vertically. A New Character button would open a popover pane").
-- Picking a character plays as them; on the right are who they are,
-- their games by the universe each is in, and a new game. A character
-- is made in a pane over it all.

-- The frame of a page of the menus, as a window's (Game/UI/Windows): a
-- plain ground, its title on a bar that stands out of it, a hairline
-- about it and the accent along its top.
local function frame(x: number, y: number, w: number, h: number, title: string)
  Im.Flat(x, y, w, h, Theme.PANEL, 1)
  Im.Edge(x, y, w, h, Theme.EDGE_STRONG)
  Im.Flat(x, y, w, 2, Theme.ACCENT)
  if title ~= "" then
    Im.Flat(x + 1, y + 2, w - 2, Theme.TITLE - 2, Theme.RAISED, 1)
    Im.Flat(x + 1, y + Theme.TITLE - 1, w - 2, 1, Theme.EDGE)
    Im.Heading(string.upper(title), x + 14, y + 8, 16, Theme.TEXT)
  end
end

-- A small heading in a page: a label in capitals, and a line under it.
local function section(label: string, x: number, y: number, w: number, note: string?)
  Im.Strong(label, x, y, 11, Theme.DIM)
  if note then
    Im.Text(List.Cut(note, w - Im.StrongWidth(label, 11) - 16, 11, false), x + Im.StrongWidth(label, 11) + 12, y, 11, Theme.FAINT)
  end
  Im.Flat(x, y + 17, w, 1, Theme.EDGE)
end

-- What a character is training, in a few words.
local function training(character: Characters.Character): string
  local first = character.training[1]
  if first == nil then
    return "nothing in training"
  end
  local skill = Skills.byId[first.skill]
  return `training {if skill then skill.name else first.skill} {first.level}, {Format.Duration(Characters.Left(character))} queued`
end

-- The universe a save is of, for its heading: and a key to group by.
local function universe(info: Session.SaveInfo): (string, string)
  if info.seed == 0 then
    return "?", "A universe saved before this was noted"
  end
  return `{info.seed}:{info.systems}`, `Universe {info.seed}  -  {Format.Whole(info.systems)} systems`
end

-- The pane a character is made in, over the screen: a name, a face (the
-- game's portraits, or a picture of the player's own), Make or Cancel.
local function drawMaking(session: Session.Session, left: number, top: number, width: number, height: number)
  Im.Uncover()
  Im.Fill(left, top, width, height, vector.create(0, 0, 0), 0.5)
  local w, h = 600, 560
  local x, y = left + (width - w) / 2, top + (height - h) / 2
  frame(x, y, w, h, "New character")
  local inner = x + 20
  Im.Text("Name", inner, y + Theme.TITLE + 24, 13, Theme.DIM)
  newName = Im.Words("Character name", newName, inner + 60, y + Theme.TITLE + 17, w - 100, 28, Characters.NAME_MOST,
    "what they are called")
  section("FACE", inner, y + Theme.TITLE + 62, w - 40)
  -- (the game's portraits, rows of eight, four rows at a time, scrolling
  -- down to the rest; the one picked framed in the accent)
  local size, gap, shown = 64, 6, 4
  local gridY = y + Theme.TITLE + 88
  local rows = math.ceil(Characters.PORTRAITS / 8)
  local firstRow = Im.Scroll("faces", inner, gridY, 8 * (size + gap) + 6, shown * (size + gap), rows, shown)
  for n = firstRow * 8 + 1, math.min(Characters.PORTRAITS, (firstRow + shown) * 8) do
    local col, row = (n - 1) % 8, (n - 1) // 8 - firstRow
    local bx, by = inner + col * (size + gap), gridY + row * (size + gap)
    Portrait.Draw(`portrait:{n}`, bx, by, size)
    local hot, clicked = Im.Area(`Face:{n}`, bx, by, size, size, true)
    if n == newFace and newPicture == "" then
      Im.Edge(bx - 2, by - 2, size + 4, size + 4, Theme.ACCENT, 1)
      Im.Edge(bx - 1, by - 1, size + 2, size + 2, Theme.ACCENT, 1)
    elseif hot then
      Im.Edge(bx - 1, by - 1, size + 2, size + 2, Theme.EDGE_STRONG, 1)
    end
    if clicked then
      newFace, newPicture = n, ""
    end
  end
  local below = gridY + math.min(rows, shown) * (size + gap) + 8
  Im.Text("Or a picture of your own: the whole path of a .png or .jpg file.", inner, below, 12, Theme.DIM)
  newPicture = Im.Words("Picture file", newPicture, inner, below + 20, w - 40, 28, 240, "C:/Users/you/Pictures/me.png")
  if problem ~= "" then
    Im.Text(List.Cut(problem, w - 40, 13, false), inner, below + 58, 13, Theme.BAD)
  end
  Im.Tone("primary")
  if Im.Button("Make", x + w - 20 - 260, y + h - 50, 150, 32, true, "Menu:make") then
    local made, why = Session.MakeCharacter(newName, `portrait:{newFace}`)
    if made and newPicture ~= "" then
      local portrait, failed = Session.ImportPicture(made, newPicture)
      if portrait then
        made.portrait = portrait
        Portrait.Forget(portrait)
        Session.KeepCharacter(made)
      else
        why = `made, with one of the game's faces: {failed}`
      end
    end
    if made then
      Session.Choose(session, made.id)
      refresh()
      problem = why or ""
      making = problem ~= ""
    else
      problem = why or "the character could not be made"
    end
  end
  if Im.Button("Cancel", x + w - 20 - 100, y + h - 50, 100, 32, true, "Menu:cancel") then
    making, problem = false, ""
  end
end

local function drawPlay(session: Session.Session, left: number, top: number, width: number, height: number)
  local w, h = math.min(width - 80, 1180), math.min(height - 80, 700)
  local x, y = left + (width - w) / 2, top + (height - h) / 2
  -- (with the pane up, nothing under it is to be clicked)
  if making then
    Im.Cover(left, top, width, height)
  end
  frame(x, y, w, h, "Characters and games")
  local inner, body = x + 16, y + Theme.TITLE + 14
  local foot = y + h - 48

  -- The characters, down the left: picking one plays as them.
  local listW = 360
  section("CHARACTERS", inner, body, listW, `{#characters}`)
  local rowH = 68
  local listTop = body + 26
  local listH = foot - 12 - listTop
  local first, visible = List.Body("characters", inner, listTop, listW, listH, #characters, rowH)
  local mine: Characters.Character? = nil
  for _, character in characters do
    mine = if character.id == session.character then character else mine
  end
  for index = 1, visible do
    local character = characters[index + first]
    if character == nil then
      break
    end
    local rowY = listTop + (index - 1) * rowH
    local playing = character.id == session.character
    local hot, picked = List.Row(inner, rowY, listW - 6, playing, `Character:play:{character.id}`, rowH)
    Portrait.Draw(character.portrait, inner + 8, rowY + 6, rowH - 12)
    Im.Strong(List.Cut(character.name, listW - rowH - 24, 15, true), inner + rowH + 4, rowY + 12, 15, if playing or hot then Theme.TEXT else Theme.TEXT)
    Im.Text(List.Cut(training(character), listW - rowH - 24, 11, false), inner + rowH + 4, rowY + 37, 11, Theme.DIM)
    if picked and not playing then
      Session.Choose(session, character.id)
      doomed = ""
    end
  end
  if #characters == 0 then
    Im.Text("Nobody yet: make a character to play.", inner + 8, listTop + 10, 13, Theme.DIM)
  end
  if #characters == 0 then
    Im.Tone("primary")
  end
  if Im.Button("New character", inner, foot, listW - 6, 32, true, "Menu:newcharacter") then
    making, newName, newPicture, problem = true, "", "", ""
  end

  -- On the right: who is picked, their games, and a new one.
  local rx = inner + listW + 18
  local rw = x + w - 16 - rx
  Im.Flat(rx - 10, body, 1, foot + 32 - body, Theme.EDGE)
  if mine == nil then
    Im.Text("Pick a character, or make one: a game is a character's.", rx, body + 4, 14, Theme.DIM)
  else
    local who = mine :: Characters.Character
    Portrait.Draw(who.portrait, rx, body, 112)
    Im.Heading(List.Cut(who.name, rw - 260, 22, true), rx + 128, body + 6, 22, Theme.TEXT)
    Im.Text(List.Cut(training(who), rw - 140, 13, false), rx + 128, body + 40, 13, Theme.DIM)
    for index = 2, math.min(4, #who.training) do
      local entry = who.training[index]
      local skill = Skills.byId[entry.skill]
      Im.Text(`then {if skill then skill.name else entry.skill} {entry.level}`, rx + 128, body + 40 + (index - 1) * 17, 12, Theme.FAINT)
    end
    Im.Tone("danger")
    if Im.Button(if doomed == who.id then "Sure? Delete" else "Delete character", rx + rw - 150, body, 150, 28, true,
      `Character:delete:{who.id}`) then
      if doomed == who.id then
        Portrait.Forget(who.portrait)
        Session.DeleteCharacter(session, who.id)
        doomed = ""
        refresh()
      else
        doomed = who.id
      end
    end

    -- Their games, by the universe each is in (and those saved before
    -- there were characters, which any character may take up).
    local gamesTop = body + 134
    local newH = 120
    section("GAMES", rx, gamesTop, rw, "by universe, the newest first")
    local rows: { { heading: string?, info: Session.SaveInfo? } } = {}
    local order: { string } = {}
    local byKey: { [string]: { Session.SaveInfo } } = {}
    local titles: { [string]: string } = {}
    for _, info in saves do
      if info.character == who.id or info.character == "" then
        local key, title = universe(info)
        if info.character == "" then
          key, title = "old", "Saved before there were characters: loaded, a game gives its pilot to a character of their own"
        end
        if byKey[key] == nil then
          byKey[key] = {}
          titles[key] = title
          table.insert(order, key)
        end
        table.insert(byKey[key], info)
      end
    end
    for _, key in order do
      table.insert(rows, { heading = titles[key] })
      for _, info in byKey[key] do
        table.insert(rows, { info = info })
      end
    end
    local gameRow = 40
    local gamesListTop = gamesTop + 26
    local gamesH = foot + 32 - newH - 14 - gamesListTop
    local gfirst, gvisible = List.Body("games", rx, gamesListTop, rw, gamesH, #rows, gameRow)
    if #rows == 0 then
      Im.Text(`{who.name} has no games yet: begin one below.`, rx + 8, gamesListTop + 10, 13, Theme.DIM)
    end
    for index = 1, gvisible do
      local row = rows[index + gfirst]
      if row == nil then
        break
      end
      local rowY = gamesListTop + (index - 1) * gameRow
      if row.heading then
        Im.Strong(List.Cut(row.heading, rw - 16, 12, false), rx + 6, rowY + 18, 12, Theme.ACCENT)
      elseif row.info then
        local info = row.info :: Session.SaveInfo
        local hot = List.Row(rx, rowY, rw - 6, false, nil, gameRow)
        Im.Text(info.slot, rx + 14, rowY + 5, 14, Theme.TEXT)
        Im.Text(List.Cut(describe(info), rw - 330, 12, false), rx + 110, rowY + 4, 12, if hot then Theme.TEXT else Theme.DIM)
        Im.Text(ago(info.time), rx + 110, rowY + 21, 11, Theme.FAINT)
        Im.Tone("primary")
        if Im.Button("Load", rx + rw - 200, rowY + 6, 80, 28, true, `Load:{info.slot}`) then
          if Session.Load(session, info.slot) then
            close(session, false)
            return
          end
        end
        Im.Tone("danger")
        if Im.Button(if doomed == `save:{info.slot}` then "Sure?" else "Delete", rx + rw - 112, rowY + 6, 100, 28, true,
          `Delete:{info.slot}`) then
          if doomed == `save:{info.slot}` then
            Session.Delete(info.slot)
            doomed = ""
            refresh()
          else
            doomed = `save:{info.slot}`
          end
        end
      end
    end

    -- A new game for them: a universe from its seed and size.
    local ny = foot + 32 - newH
    section("NEW GAME", rx, ny, rw, "a universe is made from its seed: the same seed and size, the same universe")
    Im.Text("Seed", rx, ny + 37, 13, Theme.DIM)
    seed = math.max(1, math.floor(Im.Number("Seed", seed, rx + 60, ny + 30, 110, 28)))
    if Im.Button("Random", rx + 176, ny + 30, 90, 28, true, "Menu:random") then
      seed = math.floor(Host.Time()) % 99991 + 1
    end
    Im.Text("Systems", rx, ny + 75, 13, Theme.DIM)
    -- (as many as five thousand: the project owner's, 2026-11-13. It was four hundred.)
    size = math.clamp(math.floor(Im.Number("Systems", size, rx + 60, ny + 68, 110, 28)), 3, Menu.SYSTEMS)
    for index, preset in { 40, 400, 2000, Menu.SYSTEMS } do
      if Im.Button(tostring(preset), rx + 176 + (index - 1) * 60, ny + 68, 56, 28, true, `Systems:{preset}`) then
        size = preset
      end
    end
    Im.Tone("primary")
    if Im.Button(`Begin as {List.Cut(who.name, 160, 14, true)}`, rx + rw - 260, ny + 50, 260, 46, true, "Menu:start") then
      Session.Restart(session, seed, seed, size)
      close(session, false)
      return
    end
  end
  -- (Back, in the title bar)
  if Im.Button("Back", x + w - 96, y + 4, 84, Theme.TITLE - 8, true, "Menu:back") then
    page, making, doomed = root, false, ""
  end
  if making then
    drawMaking(session, left, top, width, height)
  end
end

local function drawPage(session: Session.Session, left: number, top: number, width: number, height: number)
  local w = Menu.WIDTH
  local h = if page == "save" then 420 elseif page == "pause" then 390 elseif page == "main" then 400
    elseif page == "keys" then 550 elseif page == "graphics" then 680 else 340
  local x, y = left + (width - w) / 2, top + (height - h) / 2 - 40
  -- (the options have a line more than they had, under what was there: what is above stays where it was)
  if page == "options" then
    h = 436
  end
  frame(x, y, w, h, if page == "main" then "" else ({ pause = "Paused", options = "Options", keys = "Keys", graphics = "Graphics",
    save = "Save game" } :: { [string]: string })[page] or "")
  local cx = x + w / 2
  local function button(label: string, row: number, enabled: boolean, id: string): boolean
    return Im.Button(label, cx - 130, y + 96 + row * 44, 260, 34, enabled, id)
  end

  if page == "main" then
    Im.Heading("LIMITLESS SPACE", cx - Im.HeadingWidth("LIMITLESS SPACE", 30) / 2, y + 30, 30, Theme.TEXT)
    -- Who is played as: their face, name and training; and Continue is
    -- the newest of their games.
    local mine: Characters.Character? = nil
    for _, character in characters do
      mine = if character.id == session.character then character else mine
    end
    local cardY = y + 78
    Im.Flat(x + 30, cardY, w - 60, 64, Theme.RAISED, 1)
    Im.Edge(x + 30, cardY, w - 60, 64, Theme.EDGE)
    if mine then
      local who = mine :: Characters.Character
      Portrait.Draw(who.portrait, x + 38, cardY + 8, 48)
      Im.Strong(List.Cut(who.name, w - 160, 16, true), x + 98, cardY + 12, 16, Theme.TEXT)
      Im.Text(List.Cut(training(who), w - 160, 12, false), x + 98, cardY + 36, 12, Theme.DIM)
    else
      Im.Text("No character yet: make one to play.", x + 46, cardY + 24, 14, Theme.DIM)
    end
    local newest: Session.SaveInfo? = nil
    for _, info in saves do
      if newest == nil and info.character == session.character and session.character ~= "" then
        newest = info
      end
    end
    local function button(label: string, row: number, enabled: boolean, id: string): boolean
      return Im.Button(label, cx - 150, y + 168 + row * 46, 300, 36, enabled, id)
    end
    Im.Tone("primary")
    if button("Continue", 0, newest ~= nil, "Menu:continue") and newest then
      if Session.Load(session, newest.slot) then
        close(session, false)
      end
    end
    if newest then
      local line = List.Cut(describe(newest), w - 60, 12, false)
      Im.Text(line, cx - Im.TextWidth(line, 12) / 2, y + 168 + 40, 12, Theme.DIM)
    end
    if button("Characters and games", 1.4, true, "Menu:play") then
      page, making, doomed = "play", #characters == 0, ""
    end
    if button("Options", 2.4, true, "Menu:options") then
      page = "options"
    end
    if button("Quit", 3.4, true, "Menu:quit") then
      Host.Exit(0)
    end
  elseif page == "pause" then
    Im.Tone("primary")
    if button("Resume", 0, true, "Menu:resume") then
      close(session, wasPaused)
    end
    if button("Save game", 1, true, "Menu:save") then
      page = "save"
    end
    if button("Load game", 2, true, "Menu:load") then
      page, making, doomed = "play", false, ""
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
    local set = setSound
    local labelX, sliderX, sliderW = x + 70, x + 190, 250
    Im.Text("Sound", labelX, y + 101, 15, Theme.TEXT)
    if set and Im.Button(if soundOn then "On" else "Off", sliderX, y + 96, 90, 28, true, "Menu:sound") then
      soundOn = not soundOn
      set(soundOn, effects, music, true)
    end
    -- How loud: what happens (weapons, engines, the interface), and the
    -- music under it, each on its own. What is heard follows the knob as
    -- it is dragged, and is kept when the knob is let go.
    local wasEffects, wasMusic = effects, music
    Im.Text("Effects", labelX, y + 151, 15, if soundOn then Theme.TEXT else Theme.DIM)
    effects = Im.Slider("Effects volume", effects, 0, 100, sliderX, y + 148, sliderW, 22, soundOn)
    Im.TextRight(`{effects}%`, x + w - 60, y + 151, 14, if soundOn then Theme.TEXT else Theme.DIM)
    Im.Text("Music", labelX, y + 197, 15, if soundOn then Theme.TEXT else Theme.DIM)
    music = Im.Slider("Music volume", music, 0, 100, sliderX, y + 194, sliderW, 22, soundOn)
    Im.TextRight(`{music}%`, x + w - 60, y + 197, 14, if soundOn then Theme.TEXT else Theme.DIM)
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
    if Im.Button("Keys", cx - 130, y + 240, 126, 34, true, "Menu:keys") then
      page = "keys"
    end
    if Im.Button("Graphics", cx + 4, y + 240, 126, 34, true, "Menu:graphics") then
      page = "graphics"
    end
    -- How the game's window opens: a click goes on to the next way. It
    -- is so from the next time the game is started.
    Im.Text("Window", labelX, y + 299, 15, Theme.TEXT)
    local shown = if window == "" then "Automatic" elseif window == "borderless" then "Fits the screen"
      else (string.gsub(window, "x", " x "))
    if Im.Button(shown, sliderX, y + 294, 150, 28, setWindow ~= nil, "Menu:window") and setWindow then
      window = WINDOWS[(table.find(WINDOWS, window) or 0) % #WINDOWS + 1]
      setWindow(window)
    end
    Im.Text("from the next start", sliderX + 160, y + 300, 12, Theme.DIM)
    -- How big the interface is drawn: a click goes on to the next size
    -- the screen has room for. It is so at once.
    Im.Text("Interface", labelX, y + 343, 15, Theme.TEXT)
    -- (the screen's height in pixels is this page's in units, times the size it is drawn at now)
    local tall = height * scalePercent / 100
    local sizes: { number } = {}
    for _, each in SCALES do
      if each == 100 or tall / (each / 100) >= SCALE_ROOM then
        table.insert(sizes, each)
      end
    end
    if Im.Button(`{scalePercent}%`, sliderX, y + 338, 150, 28, setScale ~= nil and #sizes > 1, "Menu:scale") and setScale then
      scalePercent = sizes[(table.find(sizes, scalePercent) or 0) % #sizes + 1]
      setScale(scalePercent)
    end
    Im.Text(if #sizes > 1 then "how big it is all drawn" else "this screen has room for one size", sliderX + 160, y + 344, 12, Theme.DIM)
    if Im.Button("Back", cx - 130, y + h - 50, 260, 34, true, "Menu:back") then
      page = root
    end
  elseif page == "keys" then
    Im.Text(if asking ~= "" then "Press the key it is to have. Escape leaves it as it was."
      else "Click a key to give the thing another. A key something else has changes hands.", x + 30, y + 68, 13,
      if asking ~= "" then Im.ACCENT else Theme.DIM)
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
      Im.Text(action.label, rowX, rowY + 5, 14, if mine then Im.ACCENT else Theme.TEXT)
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
  elseif page == "graphics" then
    -- Each stage the picture is made in, with a switch: off, the stage
    -- is left out of every frame from the next one, and is kept so.
    Im.Wrapped("The stages the picture is made in. All on is the game as it is meant to look: switch one off to see what it "
      .. "does, or to find which one a fault in the picture comes from.", x + 30, y + 64, w - 60, 13, Theme.DIM)
    -- The look hulls are drawn in: one of three, as radio buttons.
    Im.Text("Look", x + 30, y + 112, 14, Theme.TEXT)
    Im.Text("how ships and stations are drawn", x + 30, y + 130, 11, Theme.DIM)
    for index, one in Graphics.LOOKS do
      local bx = x + w - 30 - (#Graphics.LOOKS - index + 1) * 84 + 4
      if Im.Toggle(one.label, bx, y + 114, 80, 26, Graphics.Look() == one.id, `Graphics:look:{one.id}`) then
        Graphics.SetLook(one.id)
        if setGraphics then
          setGraphics()
        end
      end
    end
    Im.Fill(x + 30, y + 112 + 37 - 5, w - 60, 1, Theme.DIM, 0.35)
    for index, stage in Graphics.STAGES do
      local rowY = y + 112 + index * 37
      local on = Graphics.IsOn(stage.id)
      Im.Text(stage.label, x + 30, rowY, 14, if on then Theme.TEXT else Theme.DIM)
      Im.Text(stage.note, x + 30, rowY + 18, 11, Theme.DIM)
      if Im.Toggle(if on then "On" else "Off", x + w - 30 - 84, rowY + 2, 84, 26, on, `Graphics:{stage.id}`) then
        Graphics.Switch(stage.id, not on)
        if setGraphics then
          setGraphics()
        end
      end
    end
    -- Inside the anti-aliasing, for running a fault down to one of its
    -- steps: what it shows, and how its last step blends. A click goes
    -- on to the next. Not kept: a game starts with the picture and the
    -- program's own blend.
    local foot = y + 112 + (#Graphics.STAGES + 1) * 37 + 8
    Im.Fill(x + 30, foot - 5, w - 60, 1, Theme.DIM, 0.35)
    Im.Text("Anti-aliasing shows", x + 30, foot + 6, 14, Theme.TEXT)
    Im.Text("for finding a fault: the edges it found, or the weights it made of them", x + 30, foot + 24, 11, Theme.DIM)
    if Im.Button(Graphics.VIEWS[Graphics.View()], x + w - 30 - 130, foot + 8, 130, 26, true, "Graphics:view") then
      Graphics.AntiAliasing(Graphics.View() % #Graphics.VIEWS + 1, Graphics.Plain())
    end
    Im.Text("Anti-aliasing blends", x + 30, foot + 43, 14, Theme.TEXT)
    Im.Text("for finding a fault: the game's own way, or the plain way of the method", x + 30, foot + 61, 11, Theme.DIM)
    if Im.Button(if Graphics.Plain() then "The plain way" else "Its own way", x + w - 30 - 130, foot + 45, 130, 26, true,
      "Graphics:blend") then
      Graphics.AntiAliasing(Graphics.View(), not Graphics.Plain())
    end
    if Im.Button("All on", cx - 266, y + h - 50, 260, 34, not Graphics.AllOn(), "Menu:allon") then
      Graphics.StagesOn()
      if setGraphics then
        setGraphics()
      end
    end
    if Im.Button("Back", cx + 6, y + h - 50, 260, 34, true, "Menu:back") then
      page = "options"
    end
  elseif page == "save" then
    local line = y + 80
    for _, slot in SLOTS do
      local info = saved(slot)
      Im.Text(slot, x + 24, line + 5, 14, Theme.TEXT)
      Im.Text(if info then describe(info) else "empty", x + 100, line + 2, 12, Theme.DIM, if info then 1 else 0.6)
      if info then
        Im.Text(ago(info.time), x + 100, line + 17, 11, Theme.DIM, 0.7)
      end
      if Im.Button(if info then "Overwrite" else "Save", x + w - 110, line + 2, 86, 26, true, `Save:{slot}`) then
        Session.Save(session, slot)
        refresh()
      end
      line += 36
    end
    Im.Text(`{Keys.Of("save")} saves to 'quick' at any time, and docking saves to 'auto'.`, x + 24, line + 8, 12, Theme.DIM, 0.8)
    if Im.Button("Back", cx - 130, y + h - 50, 260, 34, true, "Menu:back") then
      page = root
    end
  end
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
  -- (drawn to the interface's look, as the windows are: Game/UI/Theme;
  -- and the game behind dimmed, so the menu is what there is to read)
  local was = Im.Plain(true)
  Im.Fill(left, top, width, height, vector.create(0, 0, 0), 0.5)
  if page == "play" then
    drawPlay(session, left, top, width, height)
  else
    drawPage(session, left, top, width, height)
  end
  Im.Uncover()
  Im.Plain(was)
end

return Menu
