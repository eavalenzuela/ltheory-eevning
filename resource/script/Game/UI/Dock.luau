--!strict
-- The dock: a strip down the screen's left edge with a button for every
-- window there is, docked or in space. A button is a sign and no words
-- (Game/UI/Icons): what it is, the key that does it and why it cannot be
-- had here are said beside it while the cursor is on it. One whose
-- window is open has a bar of the accent at its left; one with news has
-- a count on it; one that is a station's own is dim in space.
--
-- This draws the buttons and says which was pressed. What a press does,
-- and what state each button is in, are whoever draws it's to say
-- (Game/UI/Hud): the dock knows nothing of the windows.
--
-- A script's names (Im.Press): the buttons that took the place of the
-- foot of the screen's keep the names those had ("Inventory", "Map",
-- "Events", "Colonies", "Guide"); the rest are "Dock:<id>"
-- ("Dock:market", "Dock:skills").

local Icons = require("@lt/Game/UI/Icons")
local Im = require("@lt/Game/UI/Im")
local Theme = require("@lt/Game/UI/Theme")

local Dock = {}

Dock.WIDTH = Theme.DOCK

export type Entry = { id: string, name: string, press: string }

-- The state a button is in.
export type State = {
  open: boolean,     -- its window is open
  can: boolean,      -- it can be had here
  note: string?,     -- a line more: what it is doing, or why it cannot be had
  key: string?,      -- the key that does it
  badge: number?,    -- how much news it has
}

-- The buttons, from the top: what is to hand at a station and in a
-- hold, the pilot's own affairs, the world, and the game. (false: a gap.)
Dock.ENTRIES = {
  { id = "inventory", name = "Inventory", press = "Inventory" },
  { id = "fitting", name = "Fitting", press = "Dock:fitting" },
  { id = "ships", name = "Ships", press = "Dock:ships" },
  { id = "market", name = "Market", press = "Dock:market" },
  { id = "contracts", name = "Contracts", press = "Dock:contracts" },
  { id = "industry", name = "Industry", press = "Dock:industry" },
  { id = "jobs", name = "Jobs", press = "Dock:jobs" },
  false,
  { id = "character", name = "Character", press = "Dock:character" },
  { id = "skills", name = "Skills", press = "Dock:skills" },
  { id = "wallet", name = "Wallet", press = "Dock:wallet" },
  { id = "crew", name = "Crew and fleet", press = "Dock:crew" },
  { id = "corporation", name = "Corporation", press = "Dock:corporation" },
  false,
  { id = "map", name = "Star map", press = "Map" },
  { id = "systemmap", name = "System map", press = "Dock:systemmap" },
  { id = "places", name = "Places", press = "Dock:places" },
  { id = "scanner", name = "Scanner", press = "Dock:scanner" },
  { id = "colonies", name = "Colonies", press = "Colonies" },
  { id = "events", name = "Events", press = "Events" },
  false,
  { id = "guide", name = "Guide", press = "Guide" },
  { id = "menu", name = "Menu", press = "Dock:menu" },
} :: { Entry | boolean }

local BUTTON_W, BUTTON_H, PITCH, GAP = 44, 42, 44, 13

-- Draw the dock from 'top' to 'bottom' with its left edge at x, each
-- button in the state 'of' says it is in. Returns the id of the button
-- that was pressed, if one was. (The foot of the dock, FOOT high, is
-- left for whoever draws it to put the clock in.)
Dock.FOOT = 84

function Dock.Draw(x: number, top: number, bottom: number, of: (id: string) -> State): string?
  local width = Dock.WIDTH
  Im.Flat(x, top, width, bottom - top, Theme.PANEL, 0.95)
  Im.Flat(x + width - 1, top, 1, bottom - top, Theme.EDGE)
  if Im.Inside(x, top, width, bottom - top) then
    Im.over = true
  end
  local pressed: string? = nil
  local y = top + 8
  for _, each in Dock.ENTRIES do
    if each == false or each == true then
      Im.Flat(x + 12, y + 6, width - 24, 1, Theme.EDGE)
      y += GAP
      continue
    end
    local entry = each :: Entry
    local state = of(entry.id)
    local bx = x + (width - BUTTON_W) / 2
    local hot, clicked = Im.Area(entry.press, bx, y, BUTTON_W, BUTTON_H, state.can)
    if state.open then
      Im.Flat(bx, y, BUTTON_W, BUTTON_H, Theme.ACCENT, 0.10)
      Im.Flat(x, y + 7, 3, BUTTON_H - 14, Theme.ACCENT)
    end
    if hot and state.can then
      Im.Flat(bx, y, BUTTON_W, BUTTON_H, Theme.TEXT, 0.07)
    end
    local color = if not state.can then Theme.FAINT elseif hot or state.open then Theme.TEXT else Theme.DIM
    Icons.Draw(entry.id, bx + BUTTON_W / 2, y + BUTTON_H / 2, 11, color, if state.can then 1 else 0.55)
    local badge = state.badge
    if badge and badge > 0 then
      local text = tostring(badge)
      local wide = math.max(15, Im.StrongWidth(text, 11) + 6)
      Im.Flat(bx + BUTTON_W - wide - 2, y + 3, wide, 15, Theme.CAUTION)
      Im.Strong(text, bx + BUTTON_W - wide - 2 + (wide - Im.StrongWidth(text, 11)) / 2, y + 5, 11, vector.create(0.08, 0.07, 0.04))
    end
    if hot then
      Im.Tip(entry.name, state.note, if state.can then state.key else nil, x + width + 6, y + 6)
    end
    if clicked then
      pressed = entry.id
    end
    y += PITCH
  end
  return pressed
end

return Dock
