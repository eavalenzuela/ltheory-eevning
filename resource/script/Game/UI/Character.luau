--!strict
-- The pilot's character, in play (the owner, 2026-11-17: "there is no
-- character page, that shows the character's summary and portrait";
-- asked where, "In the main menu" and "In game"): who they are, their
-- face and name; what they know and are training; and what they have
-- in this galaxy: where they are, their ship, their wallet, their
-- corporation and how the peoples think of them. Docked or in space.
-- (The main menu's Characters page is its other half: Game/UI/Menu.)

local Core = require("@lt/Core/Api")
local Format = require("@lt/Game/Format")
local Im = require("@lt/Game/UI/Im")
local List = require("@lt/Game/UI/List")
local Portrait = require("@lt/Game/UI/Portrait")
local Session = require("@lt/Game/Session")
local Skills = require("@lt/Core/Data/Skills")
local Theme = require("@lt/Game/UI/Theme")
local Windows = require("@lt/Game/UI/Windows")

local Character = {}

Character.ID = "character"

local current: Session.Session? = nil

function Character.Open()
  Windows.Open(Character.ID)
  Windows.Raise(Character.ID)
end

function Character.Close()
  Windows.Close(Character.ID)
end

function Character.IsOpen(): boolean
  return Windows.IsOpen(Character.ID)
end

-- Once a frame, before the windows are drawn.
function Character.Frame(session: Session.Session)
  current = session
end

local function section(label: string, x: number, y: number, w: number)
  Im.Strong(label, x, y, 11, Theme.DIM)
  Im.Flat(x, y + 17, w, 1, Theme.EDGE)
end

-- A row of a label and what it is.
local function row(label: string, value: string, x: number, y: number, w: number)
  Im.Text(label, x, y, 13, Theme.DIM)
  Im.Text(List.Cut(value, w - 150, 13, false), x + 150, y, 13, Theme.TEXT)
end

Windows.Kind(Character.ID, function(_: Windows.Window, x: number, y: number, w: number, h: number)
  local session = current
  if session == nil then
    return
  end
  local game = session.game
  local who = Session.Character(session.character)
  local inner, width = x + 16, w - 32
  local top = y + 14
  local was = Im.Plain(true)

  -- Who: the face, the name.
  local face = 120
  if who then
    Portrait.Draw(who.portrait, inner, top, face)
    Im.Heading(List.Cut(who.name, width - face - 20, 24, true), inner + face + 16, top + 8, 24, Theme.TEXT)
  else
    Im.Heading("Pilot", inner + face + 16, top + 8, 24, Theme.TEXT)
  end
  local player = Core.Query.Player(game)
  Im.Text(List.Cut(`{player.systemName}, {if player.docked ~= 0 then "docked" else "in space"}  -  {player.hull.name}`,
    width - face - 20, 13, false), inner + face + 16, top + 44, 13, Theme.DIM)
  Im.Text(`{Format.Whole(game.state.wallet)} cr`, inner + face + 16, top + 64, 14, Theme.ACCENT)
  local corporation = Core.Query.Corporation(game)
  Im.Text(if corporation.founded then `of {corporation.name}` else "in no corporation", inner + face + 16, top + 86, 13, Theme.DIM)

  -- What they know and are training.
  local y1 = top + face + 18
  section("SKILLS", inner, y1, width)
  local known, levels = 0, 0
  for _, info in Core.Query.Skills(game) do
    if info.level > 0 then
      known += 1
      levels += info.level
    end
  end
  row("Known", `{known} skills, {levels} levels in all`, inner, y1 + 26, width)
  local queue = Core.Query.Training(game)
  if #queue == 0 then
    row("Training", "nothing", inner, y1 + 46, width)
  else
    for index = 1, math.min(4, #queue) do
      local entry = queue[index]
      local skill = Skills.byId[entry.skill]
      row(if index == 1 then "Training" else "", `{if skill then skill.name else entry.skill} {entry.level}  -  {Format.Duration(entry.left)}`,
        inner, y1 + 26 + index * 20, width)
    end
  end

  -- How the peoples think of them.
  local y2 = y1 + 26 + (math.max(1, math.min(4, #queue)) + 1) * 20 + 10
  section("STANDINGS", inner, y2, width)
  local line = y2 + 26
  for _, standing in Core.Query.Standings(game) do
    if line > y + h - 24 then
      break
    end
    local value = string.format("%+.1f", standing.standing)
    Im.Text(standing.name, inner, line, 13, Theme.DIM)
    Im.Text(value .. (if standing.hostile then "  hostile" else ""), inner + 150, line, 13,
      if standing.hostile then Theme.BAD elseif standing.standing > 0 then Theme.GOOD else Theme.TEXT)
    line += 20
  end
  Im.Plain(was)
end)
Windows.Make(Character.ID, Character.ID, "Character", 560, 110, 520, 560, 420, 420, nil)
Windows.Icon(Character.ID, "character")

return Character
