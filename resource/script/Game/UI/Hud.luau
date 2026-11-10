--!strict
-- The interface. In space: brackets on everything in view, shots drawn
-- between ships, the overview, the selected item and its orders, locked
-- targets, the ship's condition, its module rack and the navigation bar.
-- Docked: the ship's fit, the hangar and the hold.
--
-- One widget draws all of it every frame (Game/UI/Im). It reads the Core
-- through queries and acts on it only through the Session.

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Constants = require("@lt/Core/Data/Constants")
local Core = require("@lt/Core/Api")
local Format = require("@lt/Game/Format")
local Im = require("@lt/Game/UI/Im")
local Modules = require("@lt/Core/Data/Modules")
local Scene = require("@lt/Game/View/Scene")
local Session = require("@lt/Game/Session")
local State = require("@lt/Core/Kernel/State")
local Types = require("@lt/Core/Data/Types")

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
  station = "STA", gate = "GAT", ship = "SHP", wreck = "WRK",
}

local SHIELD = vector.create(0.35, 0.65, 1.0)
local ARMOR = vector.create(0.95, 0.75, 0.3)
local HULL = vector.create(0.85, 0.35, 0.3)
local CAPACITOR = vector.create(1.0, 0.9, 0.5)

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
  elseif kind == "wreck" then
    glyphs = { Glyph_Line(v(-1, -1), v(1, 1), 1, 1), Glyph_Line(v(-1, 1), v(1, -1), 1, 1) }
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
-- Small pieces

-- A bar showing 'value' of 'max'.
local function bar(x: number, y: number, w: number, h: number, value: number, max: number, color: vector)
  Im.Fill(x, y, w, h, Im.DIM, 0.25)
  if max > 0 then
    Im.Fill(x, y, w * math.clamp(value / max, 0, 1), h, color, 0.95)
  end
end

local function shorten(name: string, limit: number): string
  return if #name > limit then string.sub(name, 1, limit - 1) .. "." else name
end

local function whole(n: number): string
  return tostring(math.floor(n + 0.5))
end

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

local function lockOf(ball: State.Ball, target: number): State.Lock?
  for _, lock in ball.vitals.locks do
    if lock.target == target then
      return lock
    end
  end
  return nil
end

-- Where a body is on screen, or nil if it is behind the camera.
local function onScreen(scene: Scene.Scene, id: number): vector?
  local at = scene.screen[id]
  if at then
    local projected = Camera_Project(scene.camera, at)
    if projected.z > 0 then
      return Position_Frame(projected)
    end
  end
  return nil
end

-- ---------------------------------------------------------------------
-- In space

local function drawShots(scene: Scene.Scene)
  for _, shot in scene.shots do
    local from, to = onScreen(scene, shot.from), onScreen(scene, shot.to)
    if from and to then
      local age = scene.time - shot.born
      if shot.family == "missile" then
        -- a dot travelling to the target, then a flash there
        if shot.outcome == "launched" and age < shot.flight then
          local at = from + (to - from) * (age / shot.flight)
          Glyph_Draw(Glyph_Circle(at, 3, 1, 1), 0, 1, ARMOR, 1)
        elseif shot.outcome == "launched" then
          Glyph_Draw(Glyph_Ring(to, 10 + 40 * (age - shot.flight), 1, 1, 0), 0, 1, ARMOR, 1 - (age - shot.flight) / Scene.SHOT_SECONDS)
        end
      else
        local fade = 1 - age / Scene.SHOT_SECONDS
        local color = if shot.family == "laser" then HULL else CAPACITOR
        if shot.outcome == "miss" then
          -- past the target, to one side
          local past = to + (to - from) * 0.15 + vector.create(18, -14)
          Glyph_Draw(Glyph_Line(from, past, 1, 1), 0, 1, color, 0.35 * fade)
        else
          Glyph_Draw(Glyph_Line(from, to, 1, 1), 0, 1, color, fade)
          if shot.outcome == "wreck" then
            Glyph_Draw(Glyph_Ring(to, 14, 1, 1, 0), 0, 1, Colors.White, fade)
          end
        end
      end
    end
  end
end

local function drawBrackets(session: Session.Session, scene: Scene.Scene, entries: { Core.Entry }, w: Widget,
  ball: State.Ball?)
  local cursor = Im.Cursor()
  local clicked = 0
  local nearest = 14 ^ 2
  for _, entry in entries do
    local p = onScreen(scene, entry.id)
    if p and p.x >= w.pos.x and p.x <= w.pos.x + w.size.x and p.y >= w.pos.y and p.y <= w.pos.y + w.size.y then
      local selected = entry.id == session.selected
      local d2 = (p.x - cursor.x) ^ 2 + (p.y - cursor.y) ^ 2
      local hot = d2 < 14 ^ 2 and not overInterface
      local small = entry.kind == "asteroid"
      local lock = if ball then lockOf(ball, entry.id) else nil
      local hostile = entry.kind == "ship"
      local color = if selected then Colors.White elseif hostile then HULL elseif entry.onGrid then Im.ACCENT else Im.DIM
      Icon_Draw(icon(entry.kind), p, if small then 4 else 8, color, if selected or hot then 1 else 0.7)
      if lock then
        -- a ring round a target: closing while it locks, steady once locked
        Glyph_Draw(Glyph_Ring(p, if lock.locked then 14 else 20, 1, 1, 0), 0, 1, Colors.White, if lock.locked then 0.9 else 0.5)
      end
      if selected or hot then
        Im.Text(entry.name, p.x + 18, p.y - 16, 14, Im.TEXT)
        Im.Text(Format.Distance(entry.distance), p.x + 18, p.y, 13, Im.DIM)
      end
      if hot and d2 < nearest then
        nearest = d2
        clicked = entry.id
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
    local color = if entry.kind == "ship" then HULL elseif entry.onGrid then Im.TEXT else Im.DIM
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

local function drawSelected(session: Session.Session, entries: { Core.Entry }, ball: State.Ball, x: number, y: number, width: number)
  local selected: Core.Entry? = nil
  for _, entry in entries do
    if entry.id == session.selected then
      selected = entry
      break
    end
  end
  Im.Panel(x, y, width, 158)
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

  local targeted = lockOf(ball, entry.id) ~= nil
  local orders: { { label: string, kind: string, range: number? } } = {
    { label = "Approach", kind = "Approach", range = 0 },
    { label = "Orbit 5 km", kind = "Orbit", range = ORBIT_RANGE },
    { label = "Keep 10 km", kind = "KeepAtRange", range = KEEP_RANGE },
    { label = "Warp to", kind = "WarpTo", range = 0 },
    { label = "Align", kind = "AlignTo" },
    if entry.kind == "gate" then { label = "Jump", kind = "Jump" } else { label = "Dock", kind = "Dock" },
    if targeted then { label = "Unlock", kind = "UnlockTarget" } else { label = "Lock", kind = "LockTarget" },
    { label = "Loot", kind = "Loot" },
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

-- The targets the ship has locked or is locking, in a row.
local function drawTargets(session: Session.Session, game: Core.Game, ball: State.Ball, x: number, y: number)
  local now = game.state.tick * Constants.TICK
  for index, lock in ball.vitals.locks do
    local body = Core.Query.Body(game, lock.target)
    if body then
      local bx = x + (index - 1) * 168
      Im.Panel(bx, y, 160, 62)
      local _, clicked = Im.Row(bx, y, 160, 62, lock.target == session.selected)
      if clicked then
        session.selected = lock.target
      end
      Im.Text(shorten(body.name, 22), bx + 8, y + 5, 14, Im.TEXT)
      if not lock.locked then
        Im.Text(string.format("locking  %.0f s", math.max(0, lock.done - now)), bx + 8, y + 26, 13, Im.WARN)
      else
        local other = Core.Query.Ball(game, lock.target)
        if other then
          local v = other.vitals
          bar(bx + 8, y + 28, 144, 5, v.shield, v.shieldMax, SHIELD)
          bar(bx + 8, y + 36, 144, 5, v.armor, v.armorMax, ARMOR)
          bar(bx + 8, y + 44, 144, 5, v.hull, v.hullMax, HULL)
        else
          Im.Text("locked", bx + 8, y + 26, 13, Im.DIM)
        end
      end
    end
  end
end

-- The ship's own condition.
local function drawStatus(ball: State.Ball, x: number, y: number)
  local v = ball.vitals
  Im.Panel(x, y, 220, 100)
  local rows: { { label: string, value: number, max: number, color: vector } } = {
    { label = "Shield", value = v.shield, max = v.shieldMax, color = SHIELD },
    { label = "Armor", value = v.armor, max = v.armorMax, color = ARMOR },
    { label = "Hull", value = v.hull, max = v.hullMax, color = HULL },
    { label = "Capacitor", value = v.capacitor, max = v.capacitorMax, color = CAPACITOR },
  }
  for index, row in rows do
    local rowY = y + 10 + (index - 1) * 22
    Im.Text(row.label, x + 10, rowY - 2, 13, Im.DIM)
    bar(x + 78, rowY + 3, 92, 8, row.value, row.max, row.color)
    Im.TextRight(whole(row.value), x + 212, rowY - 2, 13, Im.TEXT)
  end
end

-- The fitted modules, as buttons: click to switch one on or off.
local function drawRack(session: Session.Session, game: Core.Game, ball: State.Ball, cx: number, y: number)
  local fitted = Core.Query.Fitted(game, ball.id)
  if #fitted == 0 then
    return
  end
  local now = game.state.tick * Constants.TICK
  local width, gap = 128, 6
  local x = cx - (#fitted * (width + gap) - gap) / 2
  for index, item in fitted do
    local module = Modules.byId[item.type]
    local bx = x + (index - 1) * (width + gap)
    local running: State.Running? = nil
    for _, r in ball.vitals.running do
      if r.item == item.id then
        running = r
      end
    end
    local active = module.weapon ~= nil or module.repair ~= nil or module.boost ~= nil
    Im.Panel(bx, y, width, 46)
    local hot, clicked = Im.Row(bx, y, width, 46, running ~= nil)
    Im.Text(shorten(module.name, 18), bx + 8, y + 5, 13, if active then Im.TEXT else Im.DIM)
    local note = if not active then "passive" else ""
    if module.weapon then
      note = if item.charge == "" then "empty"
        elseif module.weapon.clip > 0 then `{item.rounds} rounds`
        else shorten(Types.Info(item.charge).name, 18)
    end
    if running then
      local duration = if module.weapon then module.weapon.duration
        elseif module.repair then module.repair.duration
        else module.boostDuration or 1
      bar(bx + 8, y + 38, width - 16, 3, duration - math.max(0, running.next - now), duration, Im.ACCENT)
      if running.stopping then
        note = "stopping"
      end
    end
    Im.Text(note, bx + 8, y + 22, 12, Im.DIM)
    if clicked and active then
      if running then
        Session.Do(session, { kind = "DeactivateModule", actor = 0, item = item.id })
      elseif module.weapon then
        -- at the selected target if it is locked, else the first locked one
        local target = 0
        local chosen = lockOf(ball, session.selected)
        if chosen and chosen.locked then
          target = session.selected
        else
          for _, lock in ball.vitals.locks do
            if lock.locked then
              target = lock.target
              break
            end
          end
        end
        Session.Do(session, { kind = "ActivateModule", actor = 0, item = item.id, target = target })
      else
        Session.Do(session, { kind = "ActivateModule", actor = 0, item = item.id })
      end
    end
    local _ = hot
  end
end

local function drawNavigation(session: Session.Session, ball: State.Ball, x: number, y: number, width: number)
  local game = session.game
  Im.Panel(x, y, width, 66)
  local speed = math.sqrt(ball.vx ^ 2 + ball.vy ^ 2 + ball.vz ^ 2)
  Im.Heading(Format.Speed(speed), x + 14, y + 8, 26, Im.TEXT)
  Im.Text(describe(game, ball), x + 14, y + 40, 15, Im.ACCENT)
  -- how much of its top speed, as a bar
  bar(x + 150, y + 22, 150, 4, speed, ball.maxVelocity, Im.ACCENT)
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

-- ---------------------------------------------------------------------
-- Docked: the fit, the hangar and the hold

-- The fitted weapon a charge stack would be loaded into: one of its
-- family that is empty, else one holding something else.
local function weaponFor(game: Core.Game, ship: number, charge: State.Item): State.Item?
  local family = Modules.chargeById[charge.type].family
  local other: State.Item? = nil
  for _, item in Core.Query.Fitted(game, ship) do
    local weapon = Modules.byId[item.type].weapon
    if weapon and weapon.family == family then
      if item.charge == "" then
        return item
      elseif item.charge ~= charge.type and other == nil then
        other = item
      end
    end
  end
  return other
end

local function drawDocked(session: Session.Session, game: Core.Game, player: Core.PlayerInfo, x: number, y: number)
  local width, height = 940, 600
  local ship = player.ship
  local station = Core.Query.Body(game, player.docked)
  local stats = Core.Query.Stats(game, ship)
  Im.Panel(x, y, width, height)
  Im.Heading("DOCKED", x + 16, y + 12, 16, Im.DIM)
  Im.Heading(if station then station.name else "?", x + 16, y + 34, 22, Im.TEXT)

  -- The ship and what it comes to with this fit.
  local left = x + 16
  local line = y + 78
  Im.Heading(string.upper(player.hull.name), left, line, 16, Im.TEXT)
  line += 26
  local cpu, powergrid = Core.Query.FittingUse(game, ship)
  local facts = {
    string.format("CPU %.0f / %.0f tf     Powergrid %.0f / %.0f MW", cpu, stats.cpu, powergrid, stats.powergrid),
    string.format("Shield %.0f   Armor %.0f   Hull %.0f", stats.shield, stats.armor, stats.hull),
    string.format("Speed %.0f m/s   Align %.1f s   Capacitor %.0f GJ", stats.maxVelocity, 1.3863 * stats.tau, stats.capacitor),
  }
  for _, fact in facts do
    Im.Text(fact, left, line, 14, Im.DIM)
    line += 20
  end

  line += 10
  Im.Heading("FITTED", left, line, 16, Im.DIM)
  line += 24
  local racks = { { "high", "High", player.hull.highs }, { "mid", "Mid", player.hull.mids }, { "low", "Low", player.hull.lows } } :: { { any } }
  for _, rack in racks do
    local bySlot: { [number]: State.Item } = {}
    for _, item in Core.Query.Items(game, ship, rack[1]) do
      bySlot[item.slot] = item
    end
    for slot = 1, rack[3] do
      local item = bySlot[slot]
      Im.Text(`{rack[2]} {slot}`, left, line + 3, 13, Im.DIM)
      if item then
        local module = Modules.byId[item.type]
        Im.Text(module.name, left + 56, line + 3, 14, Im.TEXT)
        if module.weapon then
          local loaded = if item.charge == "" then "nothing loaded"
            elseif module.weapon.clip > 0 then `{Types.Info(item.charge).name} x{item.rounds}`
            else Types.Info(item.charge).name
          Im.Text(loaded, left + 250, line + 3, 13, if item.charge == "" then Im.WARN else Im.DIM)
        end
        if Im.Button("Unfit", left + 396, line, 54, 22, true) then
          Session.Do(session, { kind = "Unfit", actor = 0, item = item.id })
        end
      else
        Im.Text("empty", left + 56, line + 3, 14, Im.DIM, 0.6)
      end
      line += 26
    end
  end

  -- The hangar and the hold.
  local right = x + 490
  line = y + 78
  Im.Heading("HANGAR", right, line, 16, Im.DIM)
  line += 24
  local hangar = Core.Query.Items(game, player.docked, "hangar")
  if #hangar == 0 then
    Im.Text("nothing here", right, line, 14, Im.DIM, 0.6)
    line += 24
  end
  for index, item in hangar do
    if index > 9 then
      Im.Text(`and {#hangar - 9} more`, right, line, 13, Im.DIM)
      line += 24
      break
    end
    local info = Types.Info(item.type)
    Im.Text(`{info.name}  x{item.quantity}`, right, line + 3, 14, Im.TEXT)
    if info.category == "module" then
      local can = Session.CanDo(session, { kind = "Fit", actor = 0, item = item.id })
      if Im.Button("Fit", right + 286, line, 54, 22, can) then
        Session.Do(session, { kind = "Fit", actor = 0, item = item.id })
      end
    elseif info.category == "charge" then
      local weapon = weaponFor(game, ship, item)
      if Im.Button("Load", right + 286, line, 54, 22, weapon ~= nil) and weapon then
        Session.Do(session, { kind = "LoadCharge", actor = 0, item = weapon.id, other = item.id })
      end
    end
    local toHold = Session.CanDo(session, { kind = "MoveItems", actor = 0, item = item.id, to = "cargo" })
    if Im.Button("To hold", right + 346, line, 78, 22, toHold) then
      Session.Do(session, { kind = "MoveItems", actor = 0, item = item.id, to = "cargo" })
    end
    line += 26
  end

  line += 10
  Im.Heading(string.format("HOLD  %.1f / %.0f m3", Core.Query.CargoUsed(game, ship), stats.cargo), right, line, 16, Im.DIM)
  line += 24
  local hold = Core.Query.Items(game, ship, "cargo")
  if #hold == 0 then
    Im.Text("empty", right, line, 14, Im.DIM, 0.6)
  end
  for index, item in hold do
    if index > 6 then
      Im.Text(`and {#hold - 6} more`, right, line, 13, Im.DIM)
      break
    end
    Im.Text(`{Types.Info(item.type).name}  x{item.quantity}`, right, line + 3, 14, Im.TEXT)
    if Im.Button("To hangar", right + 326, line, 98, 22, true) then
      Session.Do(session, { kind = "MoveItems", actor = 0, item = item.id, to = "hangar" })
    end
    line += 26
  end

  -- What a pilot does here.
  local bottom = y + height - 44
  if Im.Button("UNDOCK", x + 16, bottom, 120, 28, true) then
    Session.Order(session, "Undock")
  end
  local canRepair = Session.CanDo(session, { kind = "Repair", actor = 0 })
  local shipRecord = game.state.ships[ship]
  local damaged = shipRecord.armorDamage + shipRecord.hullDamage > 0
  local label = if damaged then `Repair  {Core.Query.RepairCost(game)} cr` else "No damage"
  if Im.Button(label, x + 146, bottom, 170, 28, canRepair) then
    Session.Do(session, { kind = "Repair", actor = 0 })
  end
  if Im.Button("Save", x + width - 176, bottom, 76, 28, true) then
    Session.Save(session, "quick")
  end
  if Im.Button("Load", x + width - 92, bottom, 76, 28, true) then
    Session.Load(session, "quick")
  end
end

-- ---------------------------------------------------------------------

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

      -- Brackets and shots go under the panels and use last frame's
      -- answer to "is the cursor over a panel".
      overInterface = wasOver
      if ball then
        drawShots(scene)
        drawBrackets(session, scene, entries, w, ball)
      end

      -- Where we are and what we have.
      Im.Heading(string.upper(player.systemName), left + 24, top + 18, 30, Im.TEXT)
      Im.Text(`{player.shipName}  -  {player.hull.name}`, left + 24, top + 54, 15, Im.DIM)
      Im.Text(`{game.state.wallet} credits`, left + 24, top + 76, 15, Im.DIM)
      if session.message ~= "" and game.state.tick - session.messageTick < 10 then
        Im.Text(session.message, left + 24, top + 102, 16, Im.WARN)
      end

      if scene.warp > 0 and ball and ball.warp then
        local target = Core.Query.Body(game, ball.warp.target)
        local cx = left + w.size.x / 2
        Im.Heading("WARP DRIVE ACTIVE", cx - 118, top + 120, 26, Im.ACCENT)
        local line = `{if target then target.name else "?"}   {Format.Distance(scene.warpLeft)}   {math.ceil(scene.warpSeconds)} s`
        Im.Text(line, cx - Im.TextWidth(line, 16) / 2, top + 154, 16, Im.TEXT)
      end

      local panelWidth = 372
      local panelX = right - panelWidth - 16
      if ball then
        local navX = left + (w.size.x - 520) / 2
        drawTargets(session, game, ball, left + 300, top + 16)
        drawSelected(session, entries, ball, panelX, top + 16, panelWidth)
        drawOverview(session, entries, panelX, top + 182, panelWidth, math.min(600, bottom - top - 272))
        drawRack(session, game, ball, left + w.size.x / 2, bottom - 140)
        drawNavigation(session, ball, navX, bottom - 86, 520)
        drawStatus(ball, navX - 232, bottom - 120)
      else
        drawDocked(session, game, player, left + (w.size.x - 940) / 2, top + 130)
      end
      drawClock(session, left + 24, bottom - 54)
      overInterface = Im.over
    end,
  }))
end

return Hud
