--!strict
-- The menu a right click brings up on something in space: what the ship
-- can do about it, with the orders that are given at a distance (orbit,
-- keep at range, warp to) opening a second menu of distances.
--
-- A right click on a row of the overview or on a bracket opens it for
-- that thing (Game/UI/Hud does, with Context.Open). It is drawn last,
-- over everything, and while it is up a click is the menu's: on a row
-- it gives the order, anywhere else it closes the menu, and nothing
-- under it is clicked (Im.Hold).
--
-- A distance picked from a menu is remembered, for as long as the game
-- runs: the plain order of that kind (the selected thing's button, the
-- key) is given at it from then on (Context.Range).
--
-- Its rows' names, for a script (Im.Press): "Menu:<order>" ("Menu:Orbit",
-- "Menu:KeepAtRange", "Menu:WarpTo", "Menu:Approach", ...), and in a
-- menu of distances "Menu:<order>:<metres>" ("Menu:Orbit:10000").

local Core = require("@lt/Core/Api")
local Im = require("@lt/Game/UI/Im")
local Session = require("@lt/Game/Session")

local Context = {}

-- The distances there are to choose from, metres.
Context.ORBITS = { 1000, 3000, 5000, 10000, 15000, 25000, 50000, 100000 }
Context.WARPS = { 0, 10000, 20000, 30000, 50000, 70000, 100000 }

-- The distance each order is given at when none is said.
local ranges: { [string]: number } = { Orbit = 5000, KeepAtRange = 10000, WarpTo = 0 }

local WIDTH, SUB_WIDTH, ROW = 172, 112, 24

local open = 0            -- what the menu is for (an overview entry's id); 0: there is none
local atX, atY = 0, 0
local out = ""            -- the order whose distances are out beside it; "": none
local fresh = false       -- opened this frame: the click that opened it is not one to close it

-- The distance an order is given at when none is said.
function Context.Range(kind: string): number
  return ranges[kind] or 0
end

-- 5 km, 2.5 km
function Context.Distance(metres: number): string
  return string.format("%g km", metres / 1000)
end

function Context.IsOpen(): boolean
  return open ~= 0
end

function Context.Open(id: number, x: number, y: number)
  open, atX, atY, out, fresh = id, x, y, "", true
end

function Context.Close()
  open, out = 0, ""
end

-- (an order with 'near' is for what is here, on the ship's own grid:
-- what is not is warped to first)
type Row = { label: string, kind: string, range: number?, ranges: { number }?, near: boolean? }

-- What can be done about an entry now, in the order it is listed.
local function rowsFor(session: Session.Session, entry: Core.Entry): { Row }
  local all: { Row } = {
    { label = "Approach", kind = "Approach", range = 0, near = true },
    { label = "Orbit", kind = "Orbit", ranges = Context.ORBITS, near = true },
    { label = "Keep at", kind = "KeepAtRange", ranges = Context.ORBITS, near = true },
    { label = "Warp to", kind = "WarpTo", ranges = Context.WARPS },
    { label = "Align to", kind = "AlignTo" },
    { label = "Dock", kind = "Dock" },
    { label = "Jump", kind = "Jump" },
    { label = "Lock target", kind = "LockTarget" },
    { label = "Unlock target", kind = "UnlockTarget" },
    { label = "Loot", kind = "Loot" },
    { label = "Hack", kind = "StartHack" },
    { label = "Forget this place", kind = "ForgetBookmark" },
  }
  local found: { Row } = {}
  for _, row in all do
    -- (an order with distances is there if it can be given at any of them)
    local can = false
    if row.near and not entry.onGrid then
      can = false
    elseif row.ranges then
      for _, range in row.ranges do
        can = can or Session.Can(session, row.kind, entry.id, range)
      end
    else
      can = Session.Can(session, row.kind, entry.id, row.range)
    end
    if can then
      -- (a camp's gate is gone through, not jumped: it leads to a place)
      table.insert(found, if row.kind == "Jump" and entry.variety == "passage" then { label = "Go through", kind = "Jump" } else row)
    end
  end
  return found
end

-- Draw the menu, if there is one, and take the click. 'entries' is the
-- overview; the window is from (left, top) to (right, bottom).
function Context.Draw(session: Session.Session, entries: { Core.Entry }, left: number, top: number, right: number, bottom: number)
  Im.Release()
  if open == 0 then
    return
  end
  local entry: Core.Entry? = nil
  for _, each in entries do
    if each.id == open then
      entry = each
      break
    end
  end
  -- (what it was for is gone, or the pilot has docked)
  if entry == nil then
    Context.Close()
    return
  end
  local rows = rowsFor(session, entry)
  local height = math.max(1, #rows) * ROW + 30
  local x = math.clamp(atX, left + 4, math.max(left + 4, right - WIDTH - 4))
  local y = math.clamp(atY, top + 4, math.max(top + 4, bottom - height - 4))
  local within = Im.Inside(x, y, WIDTH, height)
  Im.Panel(x, y, WIDTH, height)
  local name = if #entry.name > 22 then string.sub(entry.name, 1, 20) .. ".." else entry.name
  Im.Text(name, x + 10, y + 6, 12, Im.DIM)
  if #rows == 0 then
    Im.Text("Nothing to do about it", x + 10, y + 30, 13, Im.DIM)
  end
  local picked = false
  for index, row in rows do
    local rowY = y + 26 + (index - 1) * ROW
    local distances = row.ranges
    local hot, clicked = Im.Area(`Menu:{row.kind}`, x + 2, rowY, WIDTH - 4, ROW, true)
    if hot or out == row.kind then
      Im.Fill(x + 2, rowY, WIDTH - 4, ROW, Im.ACCENT, if hot then 0.3 else 0.16)
    end
    Im.Text(row.label, x + 10, rowY + 4, 14, Im.TEXT)
    if distances then
      Im.TextRight(">", x + WIDTH - 10, rowY + 4, 14, Im.DIM)
      -- (its distances come out when the cursor is on it, or it is clicked)
      if hot or clicked then
        out = row.kind
      end
    elseif hot then
      out = ""
    end
    if clicked and distances == nil then
      Session.Order(session, row.kind, entry.id, row.range)
      picked = true
    end
    if distances and out == row.kind then
      -- The distances, beside the row: on its right, or its left where
      -- there is no room.
      local subHeight = #distances * ROW + 8
      local subX = if x + WIDTH + SUB_WIDTH + 4 <= right then x + WIDTH - 2 else x - SUB_WIDTH + 2
      local subY = math.clamp(rowY - 4, top + 4, math.max(top + 4, bottom - subHeight - 4))
      within = within or Im.Inside(subX, subY, SUB_WIDTH, subHeight)
      Im.Panel(subX, subY, SUB_WIDTH, subHeight)
      for at, range in distances do
        local subRowY = subY + 4 + (at - 1) * ROW
        local can = Session.Can(session, row.kind, entry.id, range)
        local subHot, subClicked = Im.Area(`Menu:{row.kind}:{range}`, subX + 2, subRowY, SUB_WIDTH - 4, ROW, can)
        if subHot and can then
          Im.Fill(subX + 2, subRowY, SUB_WIDTH - 4, ROW, Im.ACCENT, 0.3)
        end
        local usual = range == ranges[row.kind]
        Im.Text(Context.Distance(range), subX + 12, subRowY + 4, 14, if not can then Im.DIM elseif usual then Im.ACCENT else Im.TEXT,
          if can then 1 else 0.6)
        if subClicked then
          ranges[row.kind] = range
          Session.Order(session, row.kind, entry.id, range)
          picked = true
        end
      end
    end
  end
  -- A click that is not on the menu puts it away (but not the click
  -- that brought it up).
  if picked or (not fresh and not within and (Im.Pressed() or Im.RightPressed())) then
    Context.Close()
  end
  fresh = false
end

return Context
