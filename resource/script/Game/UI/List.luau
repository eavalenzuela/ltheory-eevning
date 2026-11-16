--!strict
-- The one list: what every list of the interface is to be drawn with,
-- as each window is made over (the market's first). Columns with heads
-- that sort, rows that are picked, headings that fold what is under
-- them, a thumb when there is more than fits, and a foot that says how
-- much of it there is. A name too long for its column is cut short, and
-- said in full while the cursor is on its row.
--
-- It draws and says what was clicked: what is listed, in what order and
-- how it is narrowed are whoever lists it's own. (Game/UI/Im draws, to
-- the new look: call it between Im.Plain(true) and putting that back.)
--
--   local columns = List.Columns({ { id = "name", label = "Item", width = 0 }, { id = "ask", label = "Ask", width = 84, right = true } }, x, w)
--   local clicked = List.Head("market", x, y, w, columns, sortBy, sortDown)
--   local first, visible = List.Body("market", x, y + List.HEAD, w, h, #rows)
--   for row = 1, visible do
--     local hot, picked = List.Row(x, rowY, w, selected, id)
--     List.Text(name, columns.name, rowY, hot)

local Icons = require("@lt/Game/UI/Icons")
local Im = require("@lt/Game/UI/Im")
local Theme = require("@lt/Game/UI/Theme")

local List = {}

List.HEAD = 24   -- the height of the heads
List.ROW = Theme.ROW
List.FOOT = 26
local PAD, GAP = 10, 10

export type Column = { id: string, label: string, width: number, right: boolean?, sort: boolean? }
-- Where a column is: its left edge, its width, and whether what is in
-- it is set to the right.
export type Cell = { x: number, w: number, right: boolean }
export type Layout = { [string]: Cell }

-- Lay columns out across a width: each as wide as it says, and the one
-- that says 0 as wide as what is left.
function List.Columns(columns: { Column }, x: number, w: number): Layout
  local fixed, flexible = 0, 0
  for _, column in columns do
    if column.width > 0 then
      fixed += column.width
    else
      flexible += 1
    end
  end
  local rest = math.max(40, w - 2 * PAD - GAP * (#columns - 1) - fixed)
  local layout: Layout = {}
  local at = x + PAD
  for _, column in columns do
    local wide = if column.width > 0 then column.width else rest / math.max(1, flexible)
    layout[column.id] = { x = at, w = wide, right = column.right == true }
    at += wide + GAP
  end
  return layout
end

-- The heads, over the rows: the one the list is sorted by is bright and
-- says which way. Returns the id of a head that was clicked (the
-- columns that sort: all, but those that say not).
function List.Head(name: string, x: number, y: number, w: number, columns: { Column }, layout: Layout, by: string, down: boolean): string?
  Im.Flat(x, y, w, List.HEAD, Theme.RAISED, 0.6)
  Im.Flat(x, y + List.HEAD - 1, w, 1, Theme.EDGE)
  local clicked: string? = nil
  for _, column in columns do
    local cell = layout[column.id]
    local sorted = by == column.id
    local label = string.upper(column.label)
    local wide = Im.StrongWidth(label, 11) + (if sorted then 12 else 0)
    local tx = if cell.right then cell.x + cell.w - wide else cell.x
    local hot, pressed = false, false
    if column.sort ~= false and column.label ~= "" then
      hot, pressed = Im.Area(`{name}:sort:{column.id}`, cell.x, y, cell.w, List.HEAD, true)
    end
    Im.Strong(label, tx, y + 7, 11, if sorted or hot then Theme.TEXT else Theme.DIM)
    if sorted then
      Icons.Draw(if down then "down" else "up", tx + wide - 5, y + 12, 4, Theme.TEXT, 1)
    end
    if pressed then
      clicked = column.id
    end
  end
  return clicked
end

-- The rows' room: how far the list is scrolled (the first row shown is
-- the one after it) and how many rows fit, with a thumb down the right
-- edge when there are more than fit. The wheel scrolls it.
function List.Body(name: string, x: number, y: number, w: number, h: number, count: number, rowHeight: number?): (number, number)
  local visible = math.max(1, h // (rowHeight or List.ROW))
  local first = Im.Scroll(name, x, y, w, h, count, visible)
  return first, visible
end

-- A row: whether the cursor is on it, whether it was clicked, and
-- whether that was a double click.
function List.Row(x: number, y: number, w: number, selected: boolean, id: string?, h: number?): (boolean, boolean, boolean)
  return Im.Row(x, y, w, h or List.ROW, selected, id)
end

-- A text cut to a width, with ".." where it was cut: and whether it was.
local cuts: { [string]: { any } } = {}
local function cut(s: string, width: number, size: number, strong: boolean): (string, boolean)
  local key = `{size}:{math.floor(width)}:{if strong then 1 else 0}:{s}`
  local known = cuts[key]
  if known then
    return known[1], known[2]
  end
  local function measure(text: string, px: number): number
    if strong then
      return Im.StrongWidth(text, px)
    end
    return Im.TextWidth(text, px)
  end
  local out, was = s, false
  if measure(s, size) > width then
    was = true
    local low, high = 0, #s
    while low < high do
      local mid = (low + high + 1) // 2
      if measure(string.sub(s, 1, mid) .. "..", size) <= width then
        low = mid
      else
        high = mid - 1
      end
    end
    out = string.sub(s, 1, low) .. ".."
  end
  cuts[key] = { out, was }
  return out, was
end

List.Cut = cut

-- Text in a cell of a row at 'y': cut to the cell if it is too long for
-- it, and then said in full while the cursor is on the row ('hot').
-- 'inset' is how much of the cell's left is taken already (a sign, an
-- indent). Returns how wide what was drawn is.
function List.Text(s: string, cell: Cell, y: number, hot: boolean, color: vector, size: number?, strong: boolean?, inset: number?, note: string?): number
  local px = size or 14
  local room = cell.w - (inset or 0)
  local shown, was = cut(s, room, px, strong == true)
  local wide = if strong then Im.StrongWidth(shown, px) else Im.TextWidth(shown, px)
  local tx = if cell.right then cell.x + cell.w - wide else cell.x + (inset or 0)
  local ty = y + (List.ROW - px) / 2 - 1
  if strong then
    Im.Strong(shown, tx, ty, px, color)
  else
    Im.Text(shown, tx, ty, px, color)
  end
  if hot and (was or note) then
    Im.Tip(s, note)
  end
  return wide
end

-- A heading among the rows, over what is of a kind: its name, a note at
-- its right (how many), and a mark of whether what is under it is laid
-- open or folded (nil: it does not fold). Returns whether it was clicked.
function List.Group(label: string, note: string, x: number, y: number, w: number, open: boolean?, id: string?): boolean
  Im.Flat(x, y, w, List.HEAD, Theme.RAISED, 0.5)
  Im.Flat(x, y, w, 1, Theme.EDGE)
  local tx = x + PAD
  if open ~= nil then
    Icons.Draw(if open then "down" else "right", x + PAD + 4, y + 12, 4, Theme.DIM, 1)
    tx += 14
  end
  Im.Strong(string.upper(label), tx, y + 7, 11, Theme.DIM)
  if note ~= "" then
    Im.Text(note, x + w - PAD - Im.TextWidth(note, 12), y + 6, 12, Theme.FAINT)
  end
  if open ~= nil and id then
    local _, pressed = Im.Area(id, x, y, w, List.HEAD, true)
    return pressed
  end
  return false
end

-- The foot: what is shown of how much, and what is kept back.
function List.Foot(x: number, y: number, w: number, left: string, right: string?)
  Im.Flat(x, y, w, 1, Theme.EDGE)
  Im.Text(left, x + PAD, y + 7, 12, Theme.DIM)
  if right and right ~= "" then
    Im.Text(right, x + w - PAD - Im.TextWidth(right, 12), y + 7, 12, Theme.DIM)
  end
end

-- A switch that narrows a list ("Sold here"): as wide as its label.
-- Returns whether it was clicked, and how wide it came to.
function List.Chip(label: string, x: number, y: number, on: boolean, id: string): (boolean, number)
  local width = Im.StrongWidth(label, 13) + 18
  return Im.Toggle(label, x, y, width, 22, on, id), width
end

return List
