--!strict
-- The in-space interface: brackets on everything in view, the overview
-- list, the selected-item panel with its orders, the navigation bar, and
-- the station panel while docked. Drawn every frame by one widget
-- (Game/UI/Im); it reads the Core through queries and acts on it only
-- through Session.Order.

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Core = require("@lt/Core/Api")
local Format = require("@lt/Game/Format")
local Im = require("@lt/Game/UI/Im")
local Scene = require("@lt/Game/View/Scene")
local Session = require("@lt/Game/Session")
local State = require("@lt/Core/Kernel/State")

local Hud = {}

local overInterface = false
local overviewScroll = 0

-- Whether the cursor was over a panel last frame (the camera then leaves
-- the mouse alone).
function Hud.CursorOverInterface(): boolean
  return overInterface
end

local ORBIT_RANGE = 5000
local KEEP_RANGE = 10000

local TAGS: { [string]: string } = {
  sun = "SUN", planet = "PLN", moon = "MON", belt = "BLT", asteroid = "AST",
  station = "STA", gate = "GAT", ship = "SHP",
}

-- ---------------------------------------------------------------------
-- Bracket icons, one per kind, built on first use.

local function v(x: number, y: number): vector
  return vector.create(x, y)
end

local icons: { [string]: Icon } = {}

local function icon(kind: string): Icon
  local made: Icon? = icons[kind]
  if made then
    return made
  end
  local glyphs: { Glyph }
  if kind == "ship" then
    -- the corners of a square
    glyphs = {}
    for _, c in { v(-1, -1), v(1, -1), v(1, 1), v(-1, 1) } do
      table.insert(glyphs, Glyph_Line(c, v(c.x * 0.4, c.y), 1, 1))
      table.insert(glyphs, Glyph_Line(c, v(c.x, c.y * 0.4), 1, 1))
    end
  elseif kind == "station" then
    glyphs = { Glyph_Line(v(-1, -1), v(1, -1), 1, 1), Glyph_Line(v(1, -1), v(1, 1), 1, 1),
      Glyph_Line(v(1, 1), v(-1, 1), 1, 1), Glyph_Line(v(-1, 1), v(-1, -1), 1, 1), Glyph_Circle(0, 0.5, 1, 1) }
  elseif kind == "gate" then
    glyphs = { Glyph_Ring(0, 1, 1, 1, 0), Glyph_Line(v(-1.4, 0), v(-1, 0), 1, 1), Glyph_Line(v(1, 0), v(1.4, 0), 1, 1) }
  elseif kind == "sun" then
    glyphs = { Glyph_Ring(0, 1, 1, 1, 0), Glyph_Circle(0, 0.6, 1, 1) }
  elseif kind == "belt" then
    glyphs = { Glyph_Circle(v(-0.7, 0.5), 0.45, 1, 1), Glyph_Circle(v(0.7, 0.5), 0.45, 1, 1), Glyph_Circle(v(0, -0.6), 0.45, 1, 1) }
  elseif kind == "asteroid" then
    glyphs = { Glyph_Circle(0, 0.5, 1, 1) }
  else
    glyphs = { Glyph_Ring(0, 1, 1, 1, 0) }
  end
  local built = Icon_Create()
  for _, glyph in glyphs do
    Icon_AddGlyph(built, glyph)
  end
  icons[kind] = built
  return built
end

-- ---------------------------------------------------------------------

-- What the ship is doing, in words.
local function describe(game: Core.Game, ball: State.Ball): string
  local function name(id: number): string
    local body = Core.Query.Body(game, id)
    return if body then body.name else "?"
  end
  local intent = ball.intent
  local warp = ball.warp
  if warp then
    local verb = if warp.stage == "warp" then "Warping to" else "Aligning to"
    return `{verb} {name(warp.target)}`
  elseif intent then
    return `{if intent.kind == "dock" then "Docking at" else "Jumping through"} {name(intent.target)}`
  elseif ball.mode == "approach" then
    return `Approaching {name(ball.target)}`
  elseif ball.mode == "orbit" then
    return `Orbiting {name(ball.target)} at {Format.Distance(ball.range)}`
  elseif ball.mode == "keep" then
    return `Keeping {name(ball.target)} at {Format.Distance(ball.range)}`
  elseif ball.mode == "goto" or ball.mode == "align" then
    return "Flying"
  end
  return "Stopped"
end

local function drawBrackets(session: Session.Session, scene: Scene.Scene, entries: { Core.Entry }, w: Widget)
  local camera = scene.camera
  local cursor = Im.Cursor()
  local clicked = 0
  local nearest = 14 ^ 2
  for _, entry in entries do
    local at = scene.screen[entry.id]
    if at then
      local projected = Camera_Project(camera, at)
      if projected.z > 0 then
        local p = Position_Frame(projected)
        if p.x >= w.pos.x and p.x <= w.pos.x + w.size.x and p.y >= w.pos.y and p.y <= w.pos.y + w.size.y then
          local selected = entry.id == session.selected
          local d2 = (p.x - cursor.x) ^ 2 + (p.y - cursor.y) ^ 2
          local hot = d2 < 14 ^ 2 and not overInterface
          local small = entry.kind == "asteroid"
          local color = if selected then Colors.White elseif entry.onGrid then Im.ACCENT else Im.DIM
          Icon_Draw(icon(entry.kind), p, if small then 4 else 8, color, if selected or hot then 1 else 0.7)
          if selected or hot then
            Im.Text(entry.name, p.x + 14, p.y - 16, 14, Im.TEXT)
            Im.Text(Format.Distance(entry.distance), p.x + 14, p.y, 13, Im.DIM)
          end
          if hot and d2 < nearest then
            nearest = d2
            clicked = entry.id
          end
        end
      end
    end
  end
  if clicked ~= 0 and Im.Pressed() and not overInterface then
    session.selected = clicked
  end
end

local function drawOverview(session: Session.Session, entries: { Core.Entry }, x: number, y: number, width: number, height: number)
  local rowHeight = 22
  Im.Panel(x, y, width, height)
  Im.Heading(`OVERVIEW  {#entries}`, x + 12, y + 8, 16, Im.DIM)
  local top = y + 34
  local visible = math.max(1, (height - 42) // rowHeight)
  if Im.Inside(x, y, width, height) then
    overviewScroll -= 3 * Mouse_GetScrollDelta()
  end
  overviewScroll = math.clamp(math.floor(overviewScroll + 0.5), 0, math.max(0, #entries - visible))
  for row = 1, visible do
    local entry = entries[row + overviewScroll]
    if entry == nil then
      break
    end
    local rowY = top + (row - 1) * rowHeight
    local _, clicked, double = Im.Row(x + 4, rowY, width - 8, rowHeight, entry.id == session.selected)
    local color = if entry.onGrid then Im.TEXT else Im.DIM
    Im.Text(TAGS[entry.kind] or "?", x + 12, rowY + 3, 13, Im.DIM)
    Im.Text(entry.name, x + 52, rowY + 3, 14, color)
    Im.TextRight(Format.Distance(entry.distance), x + width - 12, rowY + 3, 14, color)
    if clicked then
      session.selected = entry.id
    end
    if double then
      -- The obvious thing: fly to what is here, warp to what is not.
      if entry.onGrid then
        Session.Order(session, "Approach", entry.id, 0)
      else
        Session.Order(session, "WarpTo", entry.id, 0)
      end
    end
  end
end

local function drawSelected(session: Session.Session, entries: { Core.Entry }, x: number, y: number, width: number)
  local selected: Core.Entry? = nil
  for _, entry in entries do
    if entry.id == session.selected then
      selected = entry
      break
    end
  end
  Im.Panel(x, y, width, 126)
  if selected == nil then
    Im.Heading("NOTHING SELECTED", x + 12, y + 8, 16, Im.DIM)
    Im.Text("Click a bracket or an overview row.", x + 12, y + 36, 14, Im.DIM)
    return
  end
  local entry: Core.Entry = selected
  Im.Heading(string.upper(entry.name), x + 12, y + 8, 16, Im.TEXT)
  local what = if entry.variety ~= "" and entry.kind ~= "ship" then `{entry.variety} {entry.kind}` else entry.kind
  Im.Text(what, x + 12, y + 32, 14, Im.DIM)
  Im.TextRight(Format.Distance(entry.distance), x + width - 12, y + 32, 14, Im.TEXT)

  local orders: { { label: string, kind: string, range: number? } } = {
    { label = "Approach", kind = "Approach", range = 0 },
    { label = "Orbit 5 km", kind = "Orbit", range = ORBIT_RANGE },
    { label = "Keep 10 km", kind = "KeepAtRange", range = KEEP_RANGE },
    { label = "Warp to", kind = "WarpTo", range = 0 },
    { label = "Align", kind = "AlignTo" },
    if entry.kind == "gate" then { label = "Jump", kind = "Jump" } else { label = "Dock", kind = "Dock" },
  }
  local buttonWidth = (width - 24 - 16) / 3
  for index, order in orders do
    local column, line = (index - 1) % 3, (index - 1) // 3
    local can = Session.Can(session, order.kind, entry.id, order.range)
    if Im.Button(order.label, x + 12 + column * (buttonWidth + 8), y + 58 + line * 32, buttonWidth, 26, can) then
      Session.Order(session, order.kind, entry.id, order.range)
    end
  end
end

local function drawNavigation(session: Session.Session, ball: State.Ball, x: number, y: number, width: number)
  local game = session.game
  Im.Panel(x, y, width, 66)
  local speed = math.sqrt(ball.vx ^ 2 + ball.vy ^ 2 + ball.vz ^ 2)
  Im.Heading(Format.Speed(speed), x + 14, y + 8, 26, Im.TEXT)
  Im.Text(describe(game, ball), x + 14, y + 40, 15, Im.ACCENT)
  -- how much of its top speed, as a bar
  local share = math.clamp(speed / ball.maxVelocity, 0, 1)
  Im.Fill(x + 150, y + 22, 150, 4, Im.DIM, 0.4)
  Im.Fill(x + 150, y + 22, 150 * share, 4, Im.ACCENT, 1)
  local inWarp = ball.warp ~= nil and ball.warp.stage == "warp"
  if Im.Button("STOP", x + width - 92, y + 8, 80, 24, not inWarp) then
    Session.Order(session, "Stop")
  end
end

local function drawClock(session: Session.Session, x: number, y: number)
  local clock = session.clock
  Im.Panel(x, y, 214, 34)
  if Im.Button("-", x + 6, y + 5, 28, 24, clock.scale > 1) then
    clock.scale = math.max(1, clock.scale / 2)
  end
  Im.Text(if clock.paused then "paused" else `time x{clock.scale}`, x + 44, y + 9, 14, if clock.paused then Im.WARN else Im.TEXT)
  if Im.Button("+", x + 118, y + 5, 28, 24, clock.scale < 16) then
    clock.scale = math.min(16, clock.scale * 2)
  end
  if Im.Button(if clock.paused then "run" else "pause", x + 152, y + 5, 56, 24, true) then
    clock.paused = not clock.paused
  end
end

function Hud.Create(session: Session.Session, scene: Scene.Scene): Widget
  -- Expanded, so that it covers the window: a bare widget has no size.
  return Components.Expand(Widget_Luau(Widget_Create(), {
    PostDraw = function(_, w: Widget)
      local wasOver = overInterface
      Im.Begin()
      local game = session.game
      local player = Core.Query.Player(game)
      local ball = Core.Query.Ball(game, player.ship)
      local entries = Core.Query.Overview(game)
      local left, top = w.pos.x, w.pos.y
      local right, bottom = left + w.size.x, top + w.size.y

      -- Brackets go under the panels and use last frame's answer to "is
      -- the cursor over a panel".
      overInterface = wasOver
      drawBrackets(session, scene, entries, w)

      -- Where we are.
      Im.Heading(string.upper(player.systemName), left + 24, top + 18, 30, Im.TEXT)
      Im.Text(`{player.shipName}  -  {player.hull.name}`, left + 24, top + 54, 15, Im.DIM)
      if session.message ~= "" and game.state.tick - session.messageTick < 8 then
        Im.Text(session.message, left + 24, top + 78, 16, Im.WARN)
      end

      if scene.warp > 0 and ball and ball.warp then
        local target = Core.Query.Body(game, ball.warp.target)
        local cx = left + w.size.x / 2
        local title = "WARP DRIVE ACTIVE"
        Im.Heading(title, cx - 118, top + 120, 26, Im.ACCENT)
        local line = `{if target then target.name else "?"}   {Format.Distance(scene.warpLeft)}   {math.ceil(scene.warpSeconds)} s`
        Im.Text(line, cx - Im.TextWidth(line, 16) / 2, top + 154, 16, Im.TEXT)
      end

      local panelWidth = 372
      local panelX = right - panelWidth - 16
      if ball then
        drawSelected(session, entries, panelX, top + 16, panelWidth)
        drawOverview(session, entries, panelX, top + 150, panelWidth, math.min(620, bottom - top - 240))
        drawNavigation(session, ball, left + (w.size.x - 520) / 2, bottom - 86, 520)
      else
        local station = Core.Query.Body(game, player.docked)
        local x, y = left + (w.size.x - 460) / 2, top + 24
        Im.Panel(x, y, 460, 92)
        Im.Heading("DOCKED", x + 14, y + 10, 16, Im.DIM)
        Im.Heading(if station then station.name else "?", x + 14, y + 32, 20, Im.TEXT)
        if Im.Button("UNDOCK", x + 14, y + 60, 110, 24, true) then
          Session.Order(session, "Undock")
        end
        if Im.Button("Save", x + 134, y + 60, 70, 24, true) then
          Session.Save(session, "quick")
        end
        if Im.Button("Load", x + 212, y + 60, 70, 24, true) then
          Session.Load(session, "quick")
        end
      end
      drawClock(session, left + 24, bottom - 54)
      overInterface = Im.over
    end,
  }))
end

return Hud
