--!strict
-- A faction's page (the owner, 2026-11-24: "Yes" to a page with its logo
-- large, what it holds, the pilot's standing with it and its wars):
-- opened from its name wherever an emblem stands beside one (the
-- standings, the header's holder, the star map's legend). Core's
-- Query.Faction says what is on it.

local Core = require("@lt/Core/Api")
local Emblems = require("@lt/Game/UI/Emblems")
local Im = require("@lt/Game/UI/Im")
local Session = require("@lt/Game/Session")
local Theme = require("@lt/Game/UI/Theme")
local Windows = require("@lt/Game/UI/Windows")

local FactionPage = {}

FactionPage.ID = "faction"

local current: Session.Session? = nil
-- The faction shown.
local shown = ""

function FactionPage.Open(faction: string)
  shown = faction
  Windows.Open(FactionPage.ID)
  Windows.Raise(FactionPage.ID)
end

function FactionPage.IsOpen(): boolean
  return Windows.IsOpen(FactionPage.ID)
end

-- The faction shown, or "".
function FactionPage.Shown(): string
  return if FactionPage.IsOpen() then shown else ""
end

-- Once a frame, before the windows are drawn.
function FactionPage.Frame(session: Session.Session)
  current = session
end

-- A faction's name that opens its page when clicked, its emblem before
-- it where it has one; 'id' is its name for a script. Returns how wide
-- it was drawn.
function FactionPage.Name(faction: string, name: string, x: number, y: number, size: number, color: vector, id: string,
  strong: boolean?): number
  local across = x
  if Emblems.Draw(faction, x + size * 0.7, y + size * 0.62, size * 1.7) then
    across += size * 1.7
  end
  local wide = if strong then Im.StrongWidth(name, size) else Im.TextWidth(name, size)
  local hot, pressed = Im.Area(id, across, y - 2, wide, size + 6, Emblems.Has(faction))
  local tone = if hot and Emblems.Has(faction) then Theme.ACCENT else color
  if strong then
    Im.Strong(name, across, y, size, tone)
  else
    Im.Text(name, across, y, size, tone)
  end
  if pressed then
    FactionPage.Open(faction)
  end
  return across + wide - x
end

local KINDS: { [string]: string } = { human = "Human", pirate = "Pirates", alien = "Alien" }
local WEAPONS: { [string]: string } = { projectile = "projectile guns", hybrid = "hybrid guns", laser = "lasers" }
local TANKS: { [string]: string } = { armor = "armour", shield = "shields", hull = "hull" }

local function section(label: string, x: number, y: number, w: number): number
  Im.Strong(label, x, y, 11, Theme.DIM)
  Im.Flat(x, y + 17, w, 1, Theme.EDGE)
  return y + 26
end

-- What is between two factions, in words.
local function feeling(value: number): string
  return if value >= 50 then "allied" elseif value >= 15 then "friendly" elseif value > -15 then "wary"
    elseif value > -50 then "hostile" else "bitter"
end

Windows.Kind(FactionPage.ID, function(_: Windows.Window, x: number, y: number, w: number, h: number)
  local session = current
  if session == nil or shown == "" then
    return
  end
  local info = Core.Query.Faction(session.game, shown)
  if info == nil then
    return
  end
  local was = Im.Plain(true)
  local inner = x + 16
  local width = w - 32

  -- Its logo, and beside it who it is.
  local logo = 168
  Emblems.Logo(info.id, inner, y + 12, logo)
  local tx = inner + logo + 16
  local textWidth = width - logo - 16
  Im.Heading(string.upper(info.name), tx, y + 18, 26, Theme.WHOSE[info.id] or Theme.TEXT)
  local line = y + 54
  local craft = `{KINDS[info.kind] or info.kind}. {info.hulls} hull designs; {WEAPONS[info.weapon] or info.weapon}, {TANKS[info.tank] or info.tank}`
  line = Im.Wrapped(craft, tx, line, textWidth, 13, Theme.DIM)
  local holds = if info.systems == 0 then "Holds no space"
    elseif info.home ~= "" then `Holds {info.systems} system{if info.systems == 1 then "" else "s"}, from {info.home}`
    else `Holds {info.systems} system{if info.systems == 1 then "" else "s"}`
  Im.Text(holds, tx, line + 4, 13, Theme.TEXT)
  line += 26
  -- (how it thinks of the pilot)
  local standing = string.format("%+.1f", info.standing)
  local tone = if info.hostile then Theme.BAD elseif info.standing > 0 then Theme.GOOD else Theme.TEXT
  local pill = Im.Pill(`STANDING {standing}`, tx, line, tone)
  if info.hostile then
    Im.Strong("Hostile to you", tx + pill + 10, line + 1, 13, Theme.BAD)
  elseif info.serving then
    Im.Strong("You serve them in a war", tx + pill + 10, line + 1, 13, Theme.GOOD)
  end

  line = math.max(line + 30, y + 12 + logo + 12)
  line = Im.Wrapped(info.note, inner, line, width, 13, Theme.TEXT) + 6

  -- Its wars.
  line = section("WARS", inner, line + 4, width)
  if #info.wars == 0 then
    Im.Text("At peace", inner, line, 13, Theme.DIM)
    line += 22
  end
  for index, war in info.wars do
    local said = `{war.hours} h`
    local ahead = if war.score > 0 then `, {war.score} claim{if war.score == 1 then "" else "s"} ahead`
      elseif war.score < 0 then `, {-war.score} claim{if war.score == -1 then "" else "s"} behind` else ""
    local wide = FactionPage.Name(war.faction, war.name, inner, line, 13, Theme.BAD, `Faction:war{index}`)
    Im.Text(said .. ahead, inner + wide + 12, line, 13, Theme.DIM)
    line += 24
  end

  -- What is between it and the others that hold space.
  line = section("BETWEEN IT AND THE OTHERS", inner, line + 6, width)
  if #info.relations == 0 then
    Im.Text("No other faction holds space in this galaxy", inner, line, 13, Theme.DIM)
  end
  for index, other in info.relations do
    if line > y + h - 24 then
      break
    end
    FactionPage.Name(other.faction, other.name, inner, line, 13, Theme.TEXT, `Faction:other{index}`)
    local says = if other.war then "at war" elseif other.truce then "in a truce" else feeling(other.value)
    local color = if other.war then Theme.BAD elseif other.truce then Theme.CAUTION elseif other.value >= 15 then Theme.GOOD
      elseif other.value <= -15 then Theme.CAUTION else Theme.DIM
    local value = string.format("%+.0f", other.value)
    Im.Text(value, inner + 200 - Im.TextWidth(value, 13), line, 13, Theme.DIM)
    Im.Text(says, inner + 214, line, 13, color)
    line += 24
  end
  Im.Plain(was)
end)
Windows.Make(FactionPage.ID, FactionPage.ID, "Faction", 620, 120, 540, 640, 460, 480, nil)
Windows.Icon(FactionPage.ID, "map")

return FactionPage
