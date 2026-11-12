--!strict
-- The hacking window: a lock (Core/Tactical/Hacking) while the pilot is
-- at it. The matrix of codes, with the row or column the next pick has
-- to be in marked; the keys to get in, beside it; and the buffer under
-- it. A lock that is on a clock (a vault's) shows it: how long there
-- will be, before the first pick, and how long there is, after.
--
-- There while a hack is under way, and gone when it is over: it has no
-- opening or closing of its own. Drawn every frame with Game/UI/Im; it
-- reads the Core through Query.Hack and acts on it only through the
-- Session. Its buttons' names, for a script (Im.Press): "Hack:<n>" for
-- the nth cell of the matrix (left to right, top row first), and
-- "Hack:abandon" (which leaves the lock before the first pick, and
-- ends the hack after it).

local Core = require("@lt/Core/Api")
local Im = require("@lt/Game/UI/Im")
local Session = require("@lt/Game/Session")
local State = require("@lt/Core/Kernel/State")

local Hack = {}

Hack.WIDTH = 484
Hack.HEIGHT = 468

-- (a matrix of five across at its full size; a bigger one in the same room)
local FULL_W, FULL_H, GAP = 56, 44, 6
local GOOD = vector.create(0.45, 0.85, 0.55)
local BACK = vector.create(0.02, 0.03, 0.05)

-- The cell picked last, and the tick it was picked in: the Core takes
-- it up on its next tick, and until then another click is not another
-- pick.
local tried, triedTick = 0, -1

-- Whether a hack is under way, and so the window is there.
function Hack.IsOpen(session: Session.Session): boolean
  return session.game.state.hack ~= nil
end

-- A code in a box: one of a key's, or one of the buffer's.
local function chip(code: string, x: number, y: number, w: number, h: number, tone: vector, alpha: number, ink: vector)
  Im.Fill(x, y, w, h, tone, alpha)
  local size = math.min(15, h - 8)
  Im.Text(code, x + (w - Im.TextWidth(code, size)) / 2, y + (h - size) / 2 - 1, size, ink)
end

function Hack.Draw(session: Session.Session, x: number, y: number)
  local hack = Core.Query.Hack(session.game)
  if hack == nil then
    return
  end
  local width, height = Hack.WIDTH, Hack.HEIGHT
  local left, right = x + 16, x + width - 16
  Im.Panel(x, y, width, height)
  -- (it lies over the middle of the view, the hull being hacked often
  -- behind it: darker than a panel is, so that it reads)
  Im.Fill(x + 2, y + 2, width - 4, height - 4, BACK, 0.82)
  Im.Heading("HACKING", left, y + 12, 16, Im.DIM)
  Im.TextRight(hack.name, right, y + 14, 13, Im.DIM)

  -- The matrix, with the row or the column the next pick is in marked.
  local size = hack.size
  local gridX, gridY = left, y + 46
  local span = 5 * FULL_W + 4 * GAP
  local tall = 5 * FULL_H + 4 * GAP
  local CELL_W, CELL_H = (span - (size - 1) * GAP) / size, (tall - (size - 1) * GAP) / size
  local glyph = if size > 5 then 14 else 16
  -- The clock, if the lock is on one: over the matrix, running down.
  if hack.clock > 0 then
    local begun = #hack.buffer > 0
    local share = math.clamp(hack.left / hack.clock, 0, 1)
    local tone = if begun and share < 0.34 then Im.WARN else Im.ACCENT
    Im.Fill(gridX, y + 36, span, 4, Im.DIM, 0.25)
    Im.Fill(gridX, y + 36, span * share, 4, tone, 0.95)
    Im.TextRight(if begun then `{math.ceil(hack.left)} s` else `{math.ceil(hack.clock)} s from the first pick`, right, y + 30, 12,
      if begun then tone else Im.DIM)
  end
  if hack.along == "row" then
    Im.Fill(gridX - 4, gridY + (hack.line - 1) * (CELL_H + GAP) - 4, span + 8, CELL_H + 8, Im.ACCENT, 0.16)
  else
    Im.Fill(gridX + (hack.line - 1) * (CELL_W + GAP) - 4, gridY - 4, CELL_W + 8, tall + 8, Im.ACCENT, 0.16)
  end
  local tick = session.game.state.tick
  local waiting = tick == triedTick
  for index, cell in hack.cells do
    local column, row = (index - 1) % size, (index - 1) // size
    local cx, cy = gridX + column * (CELL_W + GAP), gridY + row * (CELL_H + GAP)
    local hot, clicked = Im.Area(`Hack:{index}`, cx, cy, CELL_W, CELL_H, cell.open)
    if cell.used then
      Im.Fill(cx, cy, CELL_W, CELL_H, Im.DIM, 0.08)
      Im.Text(cell.code, cx + (CELL_W - Im.TextWidth(cell.code, glyph)) / 2, cy + (CELL_H - glyph) / 2 - 1, glyph, Im.DIM, 0.3)
    elseif cell.open then
      Im.Fill(cx, cy, CELL_W, CELL_H, Im.ACCENT, if hot then 0.62 else 0.36)
      Im.Text(cell.code, cx + (CELL_W - Im.TextWidth(cell.code, glyph)) / 2, cy + (CELL_H - glyph) / 2 - 1, glyph, Im.TEXT)
    else
      Im.Fill(cx, cy, CELL_W, CELL_H, Im.DIM, 0.16)
      Im.Text(cell.code, cx + (CELL_W - Im.TextWidth(cell.code, glyph)) / 2, cy + (CELL_H - glyph) / 2 - 1, glyph, Im.DIM)
    end
    if waiting and tried == index then
      -- (the one being picked now: a bar under it until the Core has taken it up)
      Im.Fill(cx, cy + CELL_H - 3, CELL_W, 3, Im.TEXT, 0.9)
    end
    if clicked and not waiting then
      local command: State.Command = { kind = "HackNode", actor = 0, pin = index }
      if Session.Do(session, command) then
        tried, triedTick = index, tick
        waiting = true
      end
    end
  end

  -- The keys, beside it: each a run of codes, lit as far as the end of
  -- the buffer has begun it, and green when it is in.
  local keyX = gridX + span + 18
  local line = gridY - 2
  for _, key in hack.keys do
    Im.Text(key.name, keyX, line, 13, if key.done then GOOD else Im.TEXT)
    Im.TextRight(if key.done then "in" else "", right, line, 13, GOOD)
    for at, code in key.codes do
      local lit = key.done or at <= key.begun
      chip(code, keyX + (at - 1) * 30, line + 20, 27, 22, if key.done then GOOD elseif lit then Im.ACCENT else Im.DIM,
        if lit then 0.5 else 0.18, if lit then Im.TEXT else Im.DIM)
    end
    Im.Text(key.what, keyX, line + 46, 11, Im.DIM, 0.85)
    line += 82
  end

  -- The buffer: what has been picked, and the room there is left.
  local foot = gridY + tall + 16
  Im.Text("Buffer", left, foot + 6, 13, Im.DIM)
  for at = 1, hack.room do
    local code = hack.buffer[at]
    chip(code or "", left + 60 + (at - 1) * 42, foot, 38, 28, if code then Im.ACCENT else Im.DIM, if code then 0.42 else 0.3, Im.TEXT)
  end
  local begun = #hack.buffer > 0
  local next = if not begun then "The first pick is anywhere in the top row."
    elseif hack.along == "row" then `The next pick is in row {hack.line}.`
    else `The next pick is in column {hack.line}.`
  Im.Text(next, left, foot + 40, 13, Im.TEXT)
  Im.Text("A pick puts its code in the buffer, and the next is across it: a row and a", left, foot + 64, 12, Im.DIM, 0.8)
  Im.Text("column by turns. A key is in when its codes stand there one after another.", left, foot + 80, 12, Im.DIM, 0.8)
  Im.Text(if begun and hack.clock > 0 then "It is over when the buffer is full, when the time is up, or when you end it."
    elseif begun then "It is over when the buffer is full, or when you end it."
    elseif hack.clock > 0 then "Look as long as you like: the clock starts with the first pick."
    else "Until the first pick the lock can be left as it is, and come back to.", left, foot + 96, 12, Im.DIM, 0.8)
  local abandon: State.Command = { kind = "AbandonHack", actor = 0 }
  if Im.Button(if begun then "End it" else "Leave", right - 90, y + height - 38, 90, 26, true, "Hack:abandon") then
    Session.Do(session, abandon)
  end
end

return Hack
