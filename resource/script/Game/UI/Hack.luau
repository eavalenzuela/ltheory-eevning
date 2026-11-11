--!strict
-- The hacking window: the board of a hold's lock (Core/Tactical/Hacking)
-- while the pilot is at it.
--
-- There while a hack is under way, and gone when it is over: it has no
-- opening or closing of its own. Drawn every frame with Game/UI/Im; it
-- reads the Core through Query.Hack, which shows of a node only what
-- the pilot has found out, and acts on it only through the Session.
-- Its buttons' names, for a script (Im.Press): "Hack:<n>" for the nth
-- node of the board (left to right, top row first), and "Hack:abandon".

local Core = require("@lt/Core/Api")
local Im = require("@lt/Game/UI/Im")
local Session = require("@lt/Game/Session")
local State = require("@lt/Core/Kernel/State")

local Hack = {}

Hack.WIDTH = 468
Hack.HEIGHT = 506

local CELL_W, CELL_H, GAP = 66, 54, 6
local GOOD = vector.create(0.45, 0.85, 0.55)
local WALL = vector.create(0.9, 0.35, 0.3)
local CORE = vector.create(0.95, 0.75, 0.3)
local BACK = vector.create(0.02, 0.03, 0.05)

-- The node tried last, and the tick it was tried in: the Core takes it
-- up on its next tick, and until then another click is not another try
-- (or a second click on a node not known yet would be a blow at it).
local tried, triedTick = 0, -1

-- Whether a hack is under way, and so the window is there.
function Hack.IsOpen(session: Session.Session): boolean
  return session.game.state.hack ~= nil
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
  -- behind it: darker than a panel is, so the board reads)
  Im.Fill(x + 2, y + 2, width - 4, height - 4, BACK, 0.82)
  Im.Heading("HACKING", left, y + 12, 16, Im.DIM)
  Im.TextRight(hack.name, right, y + 14, 13, Im.DIM)

  -- What the pilot has left to lose, and what a blow of theirs is worth.
  local share = math.clamp(hack.coherence / math.max(1, hack.most), 0, 1)
  Im.Text(`Coherence  {hack.coherence} / {hack.most}`, left, y + 44, 14, Im.TEXT)
  Im.TextRight(`Strength  {hack.strength}`, right, y + 44, 14, Im.TEXT)
  Im.Fill(left, y + 66, width - 32, 6, Im.DIM, 0.25)
  Im.Fill(left, y + 66, (width - 32) * share, 6, if share > 0.5 then GOOD elseif share > 0.25 then CORE else WALL, 0.95)

  -- The board.
  local boardX = x + (width - (hack.width * CELL_W + (hack.width - 1) * GAP)) / 2
  local boardY = y + 88
  local about, aboutTone = "", Im.DIM
  local tick = session.game.state.tick
  local waiting = tick == triedTick
  for index, node in hack.nodes do
    local column, row = (index - 1) % hack.width, (index - 1) // hack.width
    local cx, cy = boardX + column * (CELL_W + GAP), boardY + row * (CELL_H + GAP)
    local standing = node.kind == "firewall" or node.kind == "core"
    local hot, clicked = Im.Area(`Hack:{index}`, cx, cy, CELL_W, CELL_H, node.open)
    if node.cleared then
      -- (the way the pilot has made: each node of it says how far off the core is)
      Im.Fill(cx, cy, CELL_W, CELL_H, GOOD, 0.18)
      if index == hack.start then
        Im.Text("way in", cx + (CELL_W - Im.TextWidth("way in", 12)) / 2, cy + 8, 12, Im.DIM)
      elseif node.kind == "repair" then
        Im.Text("repair", cx + (CELL_W - Im.TextWidth("repair", 12)) / 2, cy + 8, 12, GOOD)
      elseif node.kind == "firewall" then
        Im.Text("down", cx + (CELL_W - Im.TextWidth("down", 12)) / 2, cy + 8, 12, Im.DIM)
      end
      local steps = tostring(node.steps)
      Im.Text(steps, cx + (CELL_W - Im.TextWidth(steps, 20)) / 2,
        cy + (if node.kind == "empty" and index ~= hack.start then 15 else 25), 20, if node.steps <= 1 then CORE else Im.TEXT)
      if hot then
        about = `{node.steps} {if node.steps == 1 then "step" else "steps"} from here to the core`
      end
    elseif standing then
      -- (found, and still standing: what it has left, and what its answer costs)
      local tone = if node.kind == "core" then CORE else WALL
      local name = if node.kind == "core" then "CORE" else "FIREWALL"
      Im.Fill(cx, cy, CELL_W, CELL_H, tone, if hot then 0.6 else 0.42)
      Im.Text(name, cx + (CELL_W - Im.TextWidth(name, 11)) / 2, cy + 6, 11, Im.TEXT)
      local standingAt = tostring(node.hp)
      Im.Text(standingAt, cx + (CELL_W - Im.TextWidth(standingAt, 18)) / 2, cy + 19, 18, Im.TEXT)
      local answer = `hits {node.strength}`
      Im.Text(answer, cx + (CELL_W - Im.TextWidth(answer, 11)) / 2, cy + 39, 11, Im.TEXT, 0.8)
      if hot then
        local blows = math.ceil(node.hp / math.max(1, hack.strength))
        local cost = (blows - 1) * node.strength
        about = `{blows} {if blows == 1 then "blow" else "blows"} to bring it down, for {cost} coherence`
        aboutTone = if cost >= hack.coherence then WALL else Im.TEXT
      end
    elseif node.open then
      Im.Fill(cx, cy, CELL_W, CELL_H, Im.ACCENT, if hot then 0.6 else 0.38)
      Im.Text("?", cx + (CELL_W - Im.TextWidth("?", 20)) / 2, cy + 15, 20, Im.TEXT)
      if hot then
        about = "Not known yet: try it"
      end
    else
      Im.Fill(cx, cy, CELL_W, CELL_H, Im.DIM, 0.2)
    end
    if waiting and tried == index then
      -- (the one being tried now: a bar under it until the Core has taken it up)
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

  local foot = boardY + hack.height * (CELL_H + GAP)
  Im.Text(about, left, foot + 2, 13, aboutTone)
  Im.Text("Try a node next to one that is cleared. A cleared node says how", left, foot + 28, 12, Im.DIM, 0.8)
  Im.Text("many steps off the core is. A firewall, and the core, answer every", left, foot + 44, 12, Im.DIM, 0.8)
  Im.Text("blow they survive: out of coherence, half the hold is burnt.", left, foot + 60, 12, Im.DIM, 0.8)
  local abandon: State.Command = { kind = "AbandonHack", actor = 0 }
  if Im.Button("Give up", right - 90, y + height - 38, 90, 26, true, "Hack:abandon") then
    Session.Do(session, abandon)
  end
end

return Hack
