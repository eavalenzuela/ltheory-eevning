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
-- Two more menus are of the same kind. A right click on one of the
-- plain buttons that give an order at a distance (Orbit, Keep, Warp to)
-- brings up that order's distances and nothing else, and one picked is
-- the button's from then on: no order is given (Context.Set). And a
-- right click on empty space brings up what there is in the system to
-- go to, by kind (stations, gates, belts, planets, moons, places
-- marked), each kind opening a list of them, nearest first; one picked
-- is selected, and the menu becomes the one for it (Context.OpenSpace).
--
-- Its rows' names, for a script (Im.Press): "Menu:<order>" ("Menu:Orbit",
-- "Menu:KeepAtRange", "Menu:WarpTo", "Menu:Approach", ...), and in a
-- menu of distances "Menu:<order>:<metres>" ("Menu:Orbit:10000"); for a
-- button's distances "Set:<order>:<metres>"; and out in space
-- "Space:stop", "Space:<kind>" ("Space:station") and, in a kind's list,
-- "Space:<kind>:<n>" for the nth of them.

local Core = require("@lt/Core/Api")
local Format = require("@lt/Game/Format")
local Im = require("@lt/Game/UI/Im")
local Inventory = require("@lt/Game/UI/Inventory")
local Rebuild = require("@lt/Game/UI/Rebuild")
local Session = require("@lt/Game/Session")

local Context = {}

-- The distances there are to choose from, metres.
Context.ORBITS = { 1000, 3000, 5000, 10000, 15000, 25000, 50000, 100000 }
Context.WARPS = { 0, 10000, 20000, 30000, 50000, 70000, 100000 }

-- The distance each order is given at when none is said.
local ranges: { [string]: number } = { Orbit = 5000, KeepAtRange = 10000, WarpTo = 0 }

local WIDTH, SUB_WIDTH, ROW = 172, 112, 24

-- (what the menu is for: an overview entry's id; 0: there is none; -1:
-- empty space; -2: the distances of the order 'setting')
local open = 0
local SPACE, SET = -1, -2
local setting = ""
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

-- The distances of an order, to choose the one its plain button gives
-- it at: nothing is ordered.
function Context.Set(kind: string, x: number, y: number)
  open, setting, atX, atY, out, fresh = SET, kind, x, y, "", true
end

-- What there is in the system to go to, for a right click on empty space.
function Context.OpenSpace(x: number, y: number)
  open, atX, atY, out, fresh = SPACE, x, y, "", true
end

-- What the menu is: "" (none), "space", "set", or "thing".
function Context.Kind(): string
  return if open == 0 then "" elseif open == SPACE then "space" elseif open == SET then "set" else "thing"
end

-- The kinds of place a right click on empty space lists, each with what
-- it is called there. (Rocks, ships and wrecks are on the overview.)
local PLACES: { { string } } = {
  { "station", "Stations" }, { "gate", "Stargates" }, { "belt", "Asteroid belts" }, { "planet", "Planets" },
  { "moon", "Moons" }, { "site", "Sites found" }, { "bookmark", "Places marked" },
}
-- How many of a kind are listed at most: the nearest.
local LISTED = 14

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
    { label = if Core.Query.IsTower(session.game, entry.id) then "Enter field" else "Dock", kind = "Dock" },
    { label = "Jump", kind = "Jump" },
    { label = "Lock target", kind = "LockTarget" },
    { label = "Unlock target", kind = "UnlockTarget" },
    { label = "Loot", kind = "Loot" },
    { label = "Hack", kind = "StartHack" },
    -- (a citadel's hulk: the pane that says what rebuilding it takes)
    { label = "Rebuild", kind = "Rebuild" },
    { label = "Forget this place", kind = "ForgetBookmark" },
    -- (a place of the system's, marked by itself: Game/UI/Places)
    { label = "Bookmark", kind = "Bookmark" },
  }
  local found: { Row } = {}
  for _, row in all do
    -- (an order with distances is there if it can be given at any of them)
    local can = false
    if row.kind == "Rebuild" then
      -- (there whatever is lacking: the pane says what)
      can = Rebuild.Of(session, entry.id)
    elseif row.near and not entry.onGrid then
      can = false
    elseif row.ranges then
      for _, range in row.ranges do
        can = can or Session.Can(session, row.kind, entry.id, range)
      end
    else
      can = Session.Can(session, row.kind, entry.id, row.range)
    end
    if can then
      -- (a camp's gate is gone through, not jumped: it leads to a place.
      -- And so is a wormhole, which is no gate.)
      table.insert(found, if row.kind == "Jump" and (entry.variety == "passage" or entry.variety == "site.wormhole")
        then { label = "Go through", kind = "Jump" } else row)
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
  if open == SET then
    -- The distances of one order: the one picked is its button's from now on.
    local distances: { number } = if setting == "WarpTo" then Context.WARPS else Context.ORBITS
    local height = #distances * ROW + 30
    local x = math.clamp(atX, left + 4, math.max(left + 4, right - SUB_WIDTH - 24))
    local y = math.clamp(atY, top + 4, math.max(top + 4, bottom - height - 4))
    local width = SUB_WIDTH + 20
    local within = Im.Inside(x, y, width, height)
    Im.Panel(x, y, width, height)
    Im.Text(if setting == "Orbit" then "Orbit at" elseif setting == "KeepAtRange" then "Keep at" else "Warp to at", x + 10, y + 6, 12, Im.DIM)
    local picked = false
    for at, range in distances do
      local rowY = y + 26 + (at - 1) * ROW
      local hot, clicked = Im.Area(`Set:{setting}:{range}`, x + 2, rowY, width - 4, ROW, true)
      if hot then
        Im.Fill(x + 2, rowY, width - 4, ROW, Im.ACCENT, 0.3)
      end
      Im.Text(Context.Distance(range), x + 12, rowY + 4, 14, if range == ranges[setting] then Im.ACCENT else Im.TEXT)
      if clicked then
        ranges[setting] = range
        picked = true
      end
    end
    if picked or (not fresh and not within and (Im.Pressed() or Im.RightPressed())) then
      Context.Close()
    end
    fresh = false
    return
  elseif open == SPACE then
    -- Empty space: stop, and what there is to go to, by kind.
    local kinds: { { string } } = {}
    local of: { [string]: { Core.Entry } } = {}
    for _, each in entries do
      local list = of[each.kind]
      if list == nil then
        list = {}
        of[each.kind] = list
      end
      table.insert(list, each)
    end
    for _, place in PLACES do
      if of[place[1]] then
        table.insert(kinds, place)
      end
    end
    local height = (#kinds + 1) * ROW + 30
    local x = math.clamp(atX, left + 4, math.max(left + 4, right - WIDTH - 4))
    local y = math.clamp(atY, top + 4, math.max(top + 4, bottom - height - 4))
    local within = Im.Inside(x, y, WIDTH, height)
    Im.Panel(x, y, WIDTH, height)
    Im.Text("Out here", x + 10, y + 6, 12, Im.DIM)
    local done = false
    local canStop = Session.Can(session, "Stop", 0, nil)
    local stopHot, stopClicked = Im.Area("Space:stop", x + 2, y + 26, WIDTH - 4, ROW, canStop)
    if stopHot and canStop then
      Im.Fill(x + 2, y + 26, WIDTH - 4, ROW, Im.ACCENT, 0.3)
      out = ""
    end
    Im.Text("Stop the ship", x + 10, y + 30, 14, if canStop then Im.TEXT else Im.DIM)
    if stopClicked and canStop then
      Session.Order(session, "Stop")
      done = true
    end
    local chosen: Core.Entry? = nil
    for index, place in kinds do
      local rowY = y + 26 + index * ROW
      local hot, clicked = Im.Area(`Space:{place[1]}`, x + 2, rowY, WIDTH - 4, ROW, true)
      if hot or out == place[1] then
        Im.Fill(x + 2, rowY, WIDTH - 4, ROW, Im.ACCENT, if hot then 0.3 else 0.16)
      end
      Im.Text(place[2], x + 10, rowY + 4, 14, Im.TEXT)
      Im.TextRight(">", x + WIDTH - 10, rowY + 4, 14, Im.DIM)
      if hot or clicked then
        out = place[1]
      end
      if out == place[1] then
        -- Those of the kind, nearest first, beside the row.
        local list = table.clone(of[place[1]])
        table.sort(list, function(a: Core.Entry, b: Core.Entry): boolean
          if a.distance ~= b.distance then
            return a.distance < b.distance
          end
          return a.id < b.id
        end)
        local shown = math.min(#list, LISTED)
        local listWidth = 250
        local subHeight = shown * ROW + 8
        local subX = if x + WIDTH + listWidth + 4 <= right then x + WIDTH - 2 else x - listWidth + 2
        local subY = math.clamp(rowY - 4, top + 4, math.max(top + 4, bottom - subHeight - 4))
        within = within or Im.Inside(subX, subY, listWidth, subHeight)
        Im.Panel(subX, subY, listWidth, subHeight)
        for at = 1, shown do
          local each = list[at]
          local subRowY = subY + 4 + (at - 1) * ROW
          local subHot, subClicked = Im.Area(`Space:{place[1]}:{at}`, subX + 2, subRowY, listWidth - 4, ROW, true)
          if subHot then
            Im.Fill(subX + 2, subRowY, listWidth - 4, ROW, Im.ACCENT, 0.3)
          end
          local name = if #each.name > 26 then string.sub(each.name, 1, 24) .. ".." else each.name
          Im.Text(name, subX + 10, subRowY + 4, 13, if each.onGrid then Im.TEXT else Im.DIM)
          Im.TextRight(Format.Distance(each.distance), subX + listWidth - 10, subRowY + 5, 12, Im.DIM)
          if subClicked then
            chosen = each
          end
        end
      end
    end
    if chosen then
      -- (picked out, and the menu is the one for it, where this one was)
      session.selected = chosen.id
      Context.Open(chosen.id, x, y)
      return
    end
    if done or (not fresh and not within and (Im.Pressed() or Im.RightPressed())) then
      Context.Close()
    end
    fresh = false
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
      -- (a wreck or a container is opened: what is in it is in the inventory, to take or to leave)
      if row.kind == "Loot" then
        Inventory.Show(entry.id)
      elseif row.kind == "Rebuild" then
        Rebuild.Open(session, entry.id)
      elseif row.kind == "Bookmark" then
        -- (marking a place is no order to the ship: the autopilot goes on)
        Session.Do(session, { kind = "Bookmark", actor = 0, target = entry.id })
      else
        Session.Order(session, row.kind, entry.id, row.range)
      end
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
