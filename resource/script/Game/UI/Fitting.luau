--!strict
-- Fitting: a window of its own (Game/UI/Windows), the second of a
-- station's services to be one. Opened from the dock, at a station (and
-- open when the pilot docks, as the fitting screen was what a docked
-- pilot first saw); shut when they undock.
--
-- In the middle is the ship, turning, in a wheel of its slots: the high
-- slots along the top, the mid slots down the right, the low slots along
-- the bottom and the rigs up the left. Under the wheel is what the fit
-- takes of what the hull has (CPU, powergrid, calibration, hold), its
-- hardpoints, the mending of the ship and the stripping of the fit.
--
-- On the left, on the Fitting page, is what goes in the slot picked (a
-- click on a slot picks it): what the hangar has, or what the market
-- here sells, what fits now first and then what does not yet, with why;
-- and under that the charges the fitted weapons take. On the Appearance
-- page the left is the paints and designs that are the pilot's
-- (Core/Assets/Paintwork). On the right is what the fit comes to:
-- capacitor (and where it holds with everything running), offence,
-- defence layer by layer with what each resists, targeting, navigation.
--
-- It fits out the ship flown, or another of the pilot's at the station,
-- not boarded (the owner, 2026-11-23: ships are managed in the
-- inventory, whose "Fit" on one opens this on it: Fitting.Edit). What is
-- done here is then done for that ship (Session's 'as'), and the wheel
-- shows it; "Fitting:mine" goes back to the ship flown.
--
-- A ship is still fitted from the inventory too (Game/UI/Inventory): a
-- module carried onto this window is fitted, and a charge is loaded into
-- a weapon that takes it. ("Fitting:onto", to a script: Im.Carry.)
--
-- A script's names are what they were when this was a tab of the docked
-- screen: "Unfit:<rack><n>", "Info:<type>", "Repair", "Paint:<id>",
-- "Paint:bare", "Paint:plain", "Try:stop". New with the window:
-- "Fitting:fitting" and "Fitting:appearance" (its pages),
-- "Fitting:slot:<rack><n>" (a slot, picked), "Fitting:takeout" (what is
-- in the slot picked), "Fitting:from:<hangar or market>",
-- "Fitting:filter", "Fitting:module:<type>" (a row of the list: a double
-- click fits it), "Fitting:fit" (the row picked), "Fitting:load:<type>",
-- "Fitting:strip", and "fitting:close".

local Catalog = require("@lt/Core/Data/Catalog")
local Hulls = require("@lt/Core/Data/Ships")
local Core = require("@lt/Core/Api")
local Format = require("@lt/Game/Format")
local Icons = require("@lt/Game/UI/Icons")
local Im = require("@lt/Game/UI/Im")
local Info = require("@lt/Game/UI/Info")
local ItemIcon = require("@lt/Game/UI/ItemIcon")
local List = require("@lt/Game/UI/List")
local Modules = require("@lt/Core/Data/Modules")
local Paints = require("@lt/Core/Data/Paints")
local Session = require("@lt/Game/Session")
local State = require("@lt/Core/Kernel/State")
local Theme = require("@lt/Game/UI/Theme")
local Types = require("@lt/Core/Data/Types")
local Windows = require("@lt/Game/UI/Windows")

local Fitting = {}

Fitting.ID = "fitting"

-- How the market is opened at a type: set by Game/UI/Market, which
-- draws on this window and so cannot be drawn on from here.
Fitting.Market = nil :: ((type: string) -> boolean)?

-- The page shown ("fitting" or "appearance").
local page = "fitting"
-- The slot picked: its rack, and which of it (0: the rack, and no one slot).
local slotRack, slotNumber = "high", 0
-- Where what the list offers is ("hangar" or "market"), what its names
-- are narrowed by, and the type of the row picked.
local source = "hangar"
local filter = ""
local chosen = ""
-- The fit's stripping, asked for once: a second press within so many
-- frames does it.
local stripping = 0
-- Whether what is being tried on has been shown on its page already.
local triedShown = false

local function shorten(text: string, limit: number): string
  return if #text > limit then string.sub(text, 1, limit - 1) .. "." else text
end

-- The fitted weapons a stack of charges goes in: whether any of them
-- takes it or holds it, and those it would be loaded into now (which
-- take it, and hold something else or nothing). 'only': of weapons of
-- one type alone.
local function takers(game: Core.Game, ship: number, charge: State.Item, only: string?): (boolean, { State.Item })
  local family = Modules.chargeById[charge.type].family
  local any = false
  local into: { State.Item } = {}
  for _, item in Core.Query.Fitted(game, ship) do
    -- (a weapon, or a module that is loaded as one is: a booster, an ancillary repairer)
    local weapon = Modules.Takes(Modules.byId[item.type])
    if weapon and weapon.family == family and (only == nil or item.type == only) then
      if item.charge == charge.type then
        any = true
      -- (one that would take it: of its size, and tech 2 for a tech 2 charge)
      elseif (Core.Validate(game, { kind = "LoadCharge", actor = ship, item = item.id, other = charge.id })) then
        any = true
        table.insert(into, item)
      end
    end
  end
  return any, into
end

-- ---------------------------------------------------------------------
-- The wheel

local RING = 150          -- from the middle of the wheel to the middle of a slot of its first row
local SLOT = 38

-- Where each rack sits on the wheel, in turns (0 is to the right, a
-- quarter is straight down): its name for one slot of it, the middle of
-- its arc, how much of the wheel it may take, and which way round its
-- slots are counted. Each begins at a gap of its own between the racks,
-- where its name is: the high slots from the upper left, the mid slots
-- from the upper right, the low slots from the lower right and the rigs
-- from the lower left.
local RACKS: { { any } } = {
  { "high", "High", 0.75, 0.28, 1 },
  { "mid", "Mid", 0.0, 0.18, 1 },
  { "low", "Low", 0.25, 0.28, -1 },
  { "rig", "Rig", 0.5, 0.14, 1 },
}
local RACK_NAMES: { [string]: string } = { high = "HIGH", mid = "MID", low = "LOW", rig = "RIGS" }

local EM, THERMAL, KINETIC, EXPLOSIVE = vector.create(0.35, 0.65, 1.0), vector.create(0.88, 0.38, 0.31),
  vector.create(0.64, 0.69, 0.74), vector.create(0.95, 0.64, 0.24)
local KINDS = { EM, THERMAL, KINETIC, EXPLOSIVE }

local function onWheel(cx: number, cy: number, radius: number, turn: number): (number, number)
  local angle = 2 * math.pi * turn
  return cx + radius * math.cos(angle), cy + radius * math.sin(angle)
end

-- An arc of a ring round (cx, cy), from one turn to another.
local function arc(cx: number, cy: number, inner: number, outer: number, from: number, to: number, color: vector, alpha: number)
  if to > from then
    -- (an arc is the engine's, in pixels: Theme.scale)
    WidgetRenderer_DrawPanelRadial(Theme.Point(cx, cy), inner * Theme.scale, outer * Theme.scale, ((from + to) / 2) % 1, to - from, color, alpha,
      alpha, 0)
  end
end

local turning = 0

-- What the window draws of the ship where the scene cannot stand it in
-- space: its hull first, then whatever stands on it, each with where it
-- stands in the hull's units.
export type Preview = { { model: Renderable | Model, transform: Transform, at: vector, look: vector, up: vector, size: number } }

-- ('show' draws the ship as it is in space, in a round window about a
-- point: Scene.Showcase. Where it cannot, 'preview' is drawn the old
-- way, as a hologram.)
export type Show = (cx: number, cy: number, round: number) -> boolean

-- The ship in its wheel of slots. A slot is clicked to pick it (the
-- list beside the wheel is of what goes in it); one with something in
-- it has, while the cursor is on it, a cross at its corner that takes
-- it out.
-- The ship being fitted out, where it is not the one flown (0 for that).
local subject = 0

local function drawWheel(session: Session.Session, game: Core.Game, player: Core.PlayerInfo, cx: number, cy: number,
  preview: Preview?, show: Show?)
  local ship = player.ship
  local hull = player.hull

  -- The ship, turning.
  WidgetRenderer_DrawPanelRadial(Theme.Point(cx, cy), 0, (RING - 28) * Theme.scale, 0, 1, vector.create(0.02, 0.03, 0.045), 0.9, 0.9, 0)
  if show and show(cx, cy, RING - 30) then
    -- (the ship as it is in space: Scene.Showcase has drawn it)
  elseif preview and preview[1] then
    -- (A hull of no design of ours, which the scene cannot stand in
    -- space for the fitting window: a hologram of it, as every hull was
    -- shown until 2026-11-13.)
    turning += 0.25 * FrameTimer_Get()
    local bound = Renderable_GetBound(preview[1].model)
    local size = bound.upper - bound.lower
    local fov = math.rad(0.02)
    local distance = math.max(size.x, size.y, size.z) * 0.47 / math.tan(0.5 * fov)
    local from = vector.normalize(vector.create(math.cos(turning), 0.42, math.sin(turning))) * distance
    local side = 2 * (RING - 44)
    -- (the hull, then what stands on its mounts, in another colour:
    -- a gun is a few pixels on a big hull, and would not be found in
    -- the hull's own)
    for index, part in preview do
      WidgetRenderer_DrawRenderable(part.model, part.transform, from, -1 * vector.normalize(from), vector.create(0, 1, 0), fov,
        Theme.Point(cx - side / 2, cy - side / 2), vector.create(Theme.Px(side), Theme.Px(side)),
        if index == 1 then vector.create(0.55, 0.80, 1.0) else vector.create(1.0, 0.72, 0.30), if index == 1 then 0.95 else 1.0, turning)
    end
  else
    ItemIcon.Draw(hull.id, cx - 40, cy - 40, 80)
  end

  -- The rim the slots sit on.
  arc(cx, cy, RING - 1, RING + 1, 0, 1, Im.DIM, 0.22)

  local fitted: { [string]: { [number]: State.Item } } = { high = {}, mid = {}, low = {}, rig = {} }
  for _, item in Core.Query.Fitted(game, ship) do
    fitted[item.place][item.slot] = item
  end
  local counts: { [string]: number } = { high = hull.highs, mid = hull.mids, low = hull.lows, rig = hull.rigs or 0 }
  for _, each in RACKS do
    local name: string, one: string, middle: number, span: number, way: number = each[1], each[2], each[3], each[4], each[5]
    local count = counts[name]
    if count <= 0 then
      continue
    end
    -- (a rack of more slots than its arc has room for, as a
    -- dreadnought's twenty highs are, goes on in a second row outside
    -- the first, and a third: and then its slots are smaller)
    local rows = 1
    while rows < 3 and 2 * math.pi * RING * span / math.ceil(count / rows) < 26 do
      rows += 1
    end
    local perRow = math.ceil(count / rows)
    local pitch = math.min(0.045, span / perRow)
    local size = math.clamp(math.floor(2 * math.pi * RING * pitch) - 4, 8, SLOT)
    local step = size + 5
    -- (its name, on the rim before its first slot)
    local inFirst = math.min(perRow, count)
    local firstTurn = middle + way * (1 - (inFirst + 1) / 2) * pitch
    local label = RACK_NAMES[name]
    local labelWidth = Im.StrongWidth(label, 11)
    local lx, ly = onWheel(cx, cy, RING, firstTurn - way * ((size / 2 + labelWidth / 2 + 7) / (2 * math.pi * RING)))
    Im.Flat(lx - labelWidth / 2 - 4, ly - 8, labelWidth + 8, 16, Theme.PANEL)
    Im.Strong(label, lx - labelWidth / 2, ly - 6, 11, if slotRack == name then Theme.ACCENT else Theme.DIM)
    for slot = 1, count do
      local row = (slot - 1) // perRow
      local inRow = math.min(perRow, count - row * perRow)
      local index = slot - row * perRow
      local radius = RING + row * step
      local turn = middle + way * (index - (inRow + 1) / 2) * pitch * RING / radius
      local sx, sy = onWheel(cx, cy, radius, turn)
      local left, top = math.floor(sx - size / 2), math.floor(sy - size / 2)
      local item = fitted[name][slot]
      local isPicked = slotRack == name and slotNumber == slot
      local hot, clicked = Im.Area(`Fitting:slot:{name}{slot}`, left, top, size, size, true)
      if item then
        local module = Modules.byId[item.type]
        Im.Flat(left, top, size, size, if hot then Theme.CONTROL_HOT else Theme.CONTROL)
        ItemIcon.Draw(item.type, left + 2, top + 2, size - 4)
        -- what it is loaded with, inside the wheel
        if Modules.Takes(module) and row == 0 and size >= 26 then
          local small = 16
          local ix, iy = onWheel(cx, cy, RING - size / 2 - 5 - small / 2, turn)
          if item.charge ~= "" then
            ItemIcon.Draw(item.charge, ix - small / 2, iy - small / 2, small)
          else
            Im.Flat(ix - 3, iy - 3, 6, 6, Theme.CAUTION)
          end
        end
        if hot then
          local note = `{one} slot {slot}`
          local takes = Modules.Takes(module)
          if takes then
            note ..= if item.charge ~= "" then `, loaded with {Types.Info(item.charge).name}`
              .. (if takes.clip > 0 then ` x{item.rounds}` else "") else ", nothing loaded"
          end
          -- (an adaptive hardener: where its resistance has gone)
          if module.adaptive and item.adapt then
            note ..= string.format(", EM %d%% thermal %d%% kinetic %d%% explosive %d%%", item.adapt[1] * 100, item.adapt[2] * 100,
              item.adapt[3] * 100, item.adapt[4] * 100)
          end
          Im.Tip(module.name, note)
        end
        -- taking it out: a cross at its corner, while the cursor is on it
        local ux, uy = left + size - 2, top + 2
        local canUnfit = Session.CanDo(session, { kind = "Unfit", actor = 0, item = item.id })
        local crossHot, unfit = Im.Area(`Unfit:{name}{slot}`, ux - 7, uy - 7, 14, 14, canUnfit)
        if (hot or crossHot) and canUnfit then
          Im.Flat(ux - 7, uy - 7, 14, 14, if crossHot then Theme.BAD else Theme.RAISED)
          Im.Edge(ux - 7, uy - 7, 14, 14, Theme.EDGE_STRONG)
          Icons.Draw("close", ux, uy, 3.5, Theme.TEXT, 1)
        end
        -- (a rig taken out is destroyed: it asks again, the cross red the while)
        local key = `Unfit:{name}{slot}`
        if crossHot and canUnfit then
          Im.Tip(`Take the {module.name} out`, if name ~= "rig" then nil
            elseif Im.Asking(key) then "Click again: the rig is destroyed" else "A rig taken out is destroyed: click twice")
        end
        if unfit and (name ~= "rig" or Im.Confirm(key)) then
          Session.Do(session, { kind = "Unfit", actor = 0, item = item.id })
        end
      else
        Im.Flat(left, top, size, size, Theme.WELL, 0.8)
        if hot then
          Im.Flat(left, top, size, size, Theme.TEXT, 0.07)
          Im.Tip(`{one} slot {slot}: empty`, "Click to list what goes in it")
        end
      end
      if isPicked then
        Im.Flat(left, top, size, size, Theme.ACCENT, 0.14)
      end
      Im.Edge(left, top, size, size, if isPicked then Theme.ACCENT elseif item then Theme.EDGE_STRONG else Theme.EDGE)
      if clicked then
        if slotRack ~= name then
          chosen = ""
          Im.ScrollTo("fitting modules", 0)
        end
        slotRack, slotNumber = name, slot
      end
    end
  end
end

-- How much of what the hull has the fit takes: a bar, and the two numbers.
local function useBar(label: string, used: number, capacity: number, unit: string, color: vector, x: number, y: number, w: number)
  Im.Text(label, x, y, 13, Theme.DIM)
  local bx, bw = x + 88, w - 88 - 128
  local over = used > capacity + 1e-6
  Im.Flat(bx, y + 4, bw, 8, Theme.WELL)
  Im.Edge(bx, y + 4, bw, 8, Theme.EDGE)
  local share = if capacity > 0 then math.clamp(used / capacity, 0, 1) elseif used > 0 then 1 else 0
  if share > 0 then
    Im.Flat(bx, y + 4, math.max(2, bw * share), 8, if over then Theme.BAD else color)
  end
  local of = ` / {Format.Whole(math.floor(capacity + 0.5))} {unit}`
  local ofWidth = Im.TextWidth(of, 13)
  Im.Text(of, x + w - ofWidth, y, 13, Theme.FAINT)
  local taken = Format.Whole(math.floor(used + 0.5))
  Im.Strong(taken, x + w - ofWidth - Im.StrongWidth(taken, 13), y, 13, if over then Theme.BAD else Theme.TEXT)
end

-- ---------------------------------------------------------------------
-- What the fit comes to, down the right.

local function section(title: string, x: number, y: number, width: number): number
  Im.Strong(string.upper(title), x, y, 11, Theme.ACCENT)
  Im.Flat(x, y + 15, width, 1, Theme.EDGE)
  return y + 22
end

local function figure(label: string, value: string, x: number, y: number, width: number, tone: vector?): number
  Im.Text(label, x, y, 13, Theme.DIM)
  Im.Text(value, x + width - Im.TextWidth(value, 13), y, 13, tone or Theme.TEXT)
  return y + 19
end

local KIND_HEADS = { "EM", "THERM", "KIN", "EXPL" }
local KIND_NAMES = { "EM", "thermal", "kinetic", "explosive" }

local function drawFigures(game: Core.Game, ship: number, x: number, y: number, width: number)
  local stats = Core.Query.Stats(game, ship)
  local offence = Core.Query.Offence(game, ship)
  local capacitor = Core.Query.Capacitor(game, ship)

  local line = section("Capacitor", x, y, width)
  line = figure("Holds", `{Format.Whole(math.floor(stats.capacitor + 0.5))} GJ`, x, line, width)
  line = figure("Recharges in", Format.Duration(stats.capacitorRecharge), x, line, width)
  -- (with everything it has that is switched on running, cycle after cycle: Assets/Items)
  local holds, lasts = capacitor.holds, capacitor.lasts
  line = figure("With everything running", if holds then `holds at {math.floor(holds * 100 + 0.5)}%` else `lasts {Format.Duration(lasts or 0)}`,
    x, line, width, if holds then Theme.GOOD else Theme.CAUTION)

  line = section("Offence", x, line + 8, width)
  line = figure("Damage a second", string.format("%.1f", offence.dps), x, line, width)
  line = figure("A volley", Format.Whole(math.floor(offence.volley + 0.5)), x, line, width)
  if offence.dps > 0 then
    line = figure("Reaches", Format.Distance(offence.range), x, line, width)
    -- how it divides between the four kinds of damage: a bar, and under it the kinds by name
    local at, named = x, x
    for index, color in KINDS do
      local share = offence.kinds[index] / offence.dps
      if share > 0.004 then
        Im.Flat(at, line + 4, math.max(1, width * share - 2), 6, color)
        local text = `{KIND_NAMES[index]} {math.floor(share * 100 + 0.5)}%`
        Im.Text(text, named, line + 14, 12, color)
        named += Im.TextWidth(text, 12) + 12
      end
      at += width * share
    end
    line += 32
  end

  -- Each layer: what it has, and what it stops of each kind of damage,
  -- under heads that say which kind is which.
  line = section("Defence", x, line + 8, width)
  local cellAt, cellPitch = x + 108, (width - 108) / 4
  Im.Strong("HP", x + 98 - Im.StrongWidth("HP", 10), line, 10, Theme.DIM)
  for index, color in KINDS do
    local name = KIND_HEADS[index]
    Im.Strong(name, cellAt + (index - 1) * cellPitch + cellPitch - 7 - Im.StrongWidth(name, 10), line, 10, color)
  end
  line += 15
  local effective = 0
  for _, layer in { { "Shield", "shield" }, { "Armour", "armor" }, { "Hull", "hull" } } do
    local points: number = (stats :: any)[layer[2]]
    Im.Text(layer[1], x, line, 13, Theme.DIM)
    local text = Format.Whole(math.floor(points + 0.5))
    Im.Text(text, x + 98 - Im.TextWidth(text, 13), line, 13, Theme.TEXT)
    local through = 0
    for index, color in KINDS do
      local resonance: number = (stats :: any)[`{layer[2]}Resonance.{index}`]
      through += resonance / 4
      local cell = cellAt + (index - 1) * cellPitch
      local cellWidth = cellPitch - 3
      Im.Flat(cell, line, cellWidth, 16, Theme.CONTROL, 0.5)
      Im.Flat(cell, line + 14, math.max(0, cellWidth * (1 - resonance)), 2, color)
      local stops = string.format("%.0f", (1 - resonance) * 100)
      Im.Text(stops, cell + cellWidth - 4 - Im.TextWidth(stops, 12), line + 1, 12, Theme.TEXT)
    end
    effective += points / math.max(0.01, through)
    line += 20
  end
  line = figure("Effective", `{Format.Whole(math.floor(effective + 0.5))} HP`, x, line + 2, width)

  line = section("Targeting", x, line + 8, width)
  line = figure("Lock range", Format.Distance(stats.lockRange), x, line, width)
  line = figure("Scan resolution", string.format("%.0f mm", stats.scanResolution), x, line, width)
  line = figure("Signature", string.format("%.0f m", stats.signature), x, line, width)

  line = section("Navigation", x, line + 8, width)
  line = figure("Top speed", string.format("%.0f m/s", stats.maxVelocity), x, line, width)
  line = figure("Aligns in", string.format("%.1f s", 1.3863 * stats.tau), x, line, width)
  figure("Warp speed", string.format("%.1f AU/s", stats.warpSpeed), x, line, width)
end

-- ---------------------------------------------------------------------
-- The Appearance page

-- What the ship is painted in, as two lists down the left: the paints
-- that are the pilot's, and their designs (Core/Assets/Paintwork). A row
-- is clicked and the ship is in it, as often as they like; the first row
-- of each takes it off. One that lies bought in the hangar here and is
-- not yet theirs is on the list too, marked new: clicked, it is made
-- theirs (and used up) and put on. And under them, what is being tried
-- on (Session.Try), which paints nothing. (The owner's ruling,
-- 2026-11-15: "Unlocked for good, switch via a list in fitting screen".)
--
-- To a script a row is "Paint:<id>" with the paint's or the design's
-- id, the first rows are "Paint:bare" and "Paint:plain", and what ends
-- a trying on is "Try:stop".
local PAINT_ROWS, DESIGN_ROWS = 11, 8

local function drawPaints(session: Session.Session, game: Core.Game, player: Core.PlayerInfo, x: number, y: number, width: number)
  local own = game.state.ships[player.ship]
  local mine = game.state.paints
  if own == nil then
    return
  end
  -- (what is theirs, and what lies in the hangar here to be made theirs, each in the order it is listed in)
  type Line = { id: string, name: string, new: State.Item? }
  local here: { [string]: State.Item } = {}
  for _, item in Core.Query.Items(game, player.at, "hangar") do
    if Paints.paintById[item.type] or Paints.designById[item.type] then
      here[item.type] = item
    end
  end
  -- (what is new comes first, where it is seen)
  local function lines(first: string, ids: { string }, names: { string }): { Line }
    local found: { Line } = { { id = "", name = first } }
    for index, id in ids do
      if not mine[id] and here[id] then
        table.insert(found, { id = id, name = names[index], new = here[id] })
      end
    end
    for index, id in ids do
      if mine[id] then
        table.insert(found, { id = id, name = names[index] })
      end
    end
    return found
  end
  local ids: { string }, names: { string } = {}, {}
  for _, one in Paints.paints do
    table.insert(ids, one.id)
    table.insert(names, one.name)
  end
  local paints = lines("As built", ids, names)
  ids, names = {}, {}
  for _, one in Paints.designs do
    table.insert(ids, one.id)
    table.insert(names, one.name)
  end
  local designs = lines("No design", ids, names)

  -- One list: its heading, and its rows; what the ship has is marked.
  local function list(title: string, name: string, rows: { Line }, visible: number, top: number, has: string?, bare: string): number
    List.Group(title, tostring(#rows - 1), x, top, width, nil)
    top += List.HEAD
    local first = Im.Scroll(name, x, top, width, visible * List.ROW, #rows, visible)
    for row = 1, math.min(visible, #rows - first) do
      local line = rows[row + first]
      local at = top + (row - 1) * List.ROW
      local command: State.Command = if line.id == "" then { kind = "StripPaint", actor = 0, what = if bare == "plain" then "design" else nil }
        else { kind = "Paint", actor = 0, type = line.id }
      local selected = (has or "") == line.id
      local _, clicked = List.Row(x, at, width - 5, selected, `Paint:{if line.id == "" then bare else line.id}`)
      local stack = line.new
      local can = selected or (Session.CanDo(session, command))
      if line.id ~= "" then
        ItemIcon.Draw(line.id, x + 10, at + 4, 17)
      end
      -- (a name too long for its row is cut to what fits)
      local inset = if line.id ~= "" then 34 else 12
      local label = List.Cut(line.name, width - inset - (if stack then 50 else 14), 14, false)
      Im.Text(label, x + inset, at + 5, 14, if can then Theme.TEXT else Theme.FAINT)
      if stack then
        Im.Strong("NEW", x + width - 14 - Im.StrongWidth("NEW", 11), at + 7, 11, Theme.ACCENT)
      end
      -- (refused, the session says why)
      if clicked and not selected then
        Session.Do(session, command)
      end
    end
    return top + visible * List.ROW
  end

  local foot = list("Paint", "fitting:paints", paints, PAINT_ROWS, y, own.paint, "bare")
  if #paints == 1 and #designs == 1 then
    Im.Wrapped("None of your own yet: the market sells paints and designs (Paints).", x + 12, y + List.HEAD + List.ROW + 8, width - 24, 13,
      Theme.DIM)
  end
  foot = list("Design", "fitting:designs", designs, DESIGN_ROWS, foot + 8, own.design, "plain")

  local trying = session.trying
  if trying.paint or trying.design then
    local tried = if trying.paint then Paints.paintById[trying.paint] else nil
    local laid = if trying.design then Paints.designById[trying.design] else nil
    local what = (if tried then tried.name else "") .. (if tried and laid then ", " else "") .. (if laid then laid.name else "")
    Im.Flat(x, foot + 8, width, 1, Theme.EDGE)
    Im.Strong("TRYING ON", x + 12, foot + 18, 11, Theme.CAUTION)
    Im.Text(List.Cut(what, width - 96, 14, false), x + 12, foot + 34, 14, Theme.CAUTION)
    Im.Text(if laid and tried == nil and own.paint == nil then "a design shows on a paint" else "not yours, not painted", x + 12, foot + 54, 12,
      Theme.DIM)
    if Im.Button("Stop", x + width - 72, foot + 18, 60, 24, true, "Try:stop") then
      Session.Try(session, nil)
    end
  end
end

-- ---------------------------------------------------------------------
-- Saved fits, down the left (the owner, 2026-11-18: "need saved
-- fittings in the fitting window (new tab, next to fitting and
-- appearance)"): the ship's fit saved under a name, and the fits kept
-- for this hull, each to be put on (Core/Assets/SavedFits). One picked
-- says what of it is not at hand here, and offers to buy that on the
-- market here and put the fit on ("Fit what you have + buy rest").

local fitName = ""
local fitPicked = 0

local function drawFits(session: Session.Session, game: Core.Game, player: Core.PlayerInfo, x: number, y: number, width: number,
  height: number)
  -- Save what is fitted now.
  local top = y + 10
  Im.Strong("SAVE THIS FIT", x + 12, top, 11, Theme.DIM)
  top += 18
  fitName = Im.Words("fitting:fitname", fitName, x + 12, top, width - 100, 28, 40, "a name")
  local save: State.Command = { kind = "SaveFit", actor = 0, name = fitName }
  -- (a name this hull has a fit under already is that fit written over: the button says so)
  local wanted = string.match(fitName, "^%s*(.-)%s*$") or ""
  local over = false
  for _, fit in Core.Query.Fits(game, player.hull.id) do
    over = over or fit.name == wanted
  end
  if Im.Button(if over then "Overwrite" else "Save", x + width - 80, top, 68, 28, (Session.CanDo(session, save)), "Fits:save") then
    if Session.Do(session, save) then
      fitName = ""
    end
  end
  top += 40
  -- The fits kept for this hull.
  local fits = Core.Query.Fits(game, player.hull.id)
  List.Group(`Saved for the {player.hull.name}`, tostring(#fits), x, top, width, nil)
  top += List.HEAD
  local picked: Core.FitInfo? = nil
  for _, fit in fits do
    if fit.id == fitPicked then
      picked = fit
    end
  end
  if picked == nil and #fits > 0 then
    picked = fits[1]
    fitPicked = fits[1].id
  end
  local visible = math.max(3, math.min(#fits, 8))
  local first = Im.Scroll("fitting:fits", x, top, width, visible * List.ROW, #fits, visible)
  for row = 1, math.min(visible, #fits - first) do
    local fit = fits[row + first]
    local at = top + (row - 1) * List.ROW
    local _, clicked = List.Row(x, at, width - 5, fit.id == fitPicked, `Fit:{fit.id}`)
    Im.Text(List.Cut(fit.name, width - 130, 14, false), x + 12, at + 5, 14, Theme.TEXT)
    local note = if #fit.missing == 0 then "all at hand" else `{#fit.missing} missing`
    Im.Text(note, x + width - 14 - Im.TextWidth(note, 12), at + 6, 12, if #fit.missing == 0 then Theme.GOOD else Theme.CAUTION)
    if clicked then
      fitPicked = fit.id
    end
  end
  if #fits == 0 then
    Im.Wrapped("No fits saved for this hull yet: fit it, name the fit above and save it.", x + 12, top + 8, width - 24, 13, Theme.DIM)
  end
  top += visible * List.ROW + 10
  local fit = picked
  if fit == nil then
    return
  end
  -- The one picked: what of it is not at hand, and what buying that here costs.
  Im.Flat(x, top, width, 1, Theme.EDGE)
  top += 10
  Im.Strong(string.upper((List.Cut(fit.name, width - 24, 11, true))), x + 12, top, 11, Theme.TEXT)
  top += 18
  local total, buyable = 0, true
  for _, gap in fit.missing do
    if top > y + height - 80 then
      break
    end
    ItemIcon.Draw(gap.type, x + 12, top, 17)
    Im.Text(List.Cut(`{gap.want - gap.have} x {gap.name}`, width - 150, 13, false), x + 34, top + 2, 13, Theme.CAUTION)
    local cost = gap.cost
    local price = if cost then Format.Credits(cost) else "not sold here"
    Im.Text(price, x + width - 14 - Im.TextWidth(price, 12), top + 3, 12, if cost then Theme.DIM else Theme.BAD)
    total += cost or 0
    buyable = buyable and cost ~= nil
    top += 22
  end
  if #fit.missing == 0 then
    Im.Text("Everything for it is here or fitted.", x + 12, top, 13, Theme.GOOD)
    top += 22
  end
  -- Its buttons: put it on; buy what is missing and put it on; forget it.
  local load: State.Command = { kind = "LoadFit", actor = 0, target = fit.id }
  local bw = (width - 24 - 16) / 3
  local by = math.min(top + 6, y + height - 40)
  if Im.Button("Fit", x + 12, by, bw, 28, (Session.CanDo(session, load)), "Fits:load") then
    Session.Do(session, load)
  end
  local affordable = #fit.missing > 0 and buyable and total <= game.state.wallet
  if Im.Button(if #fit.missing > 0 then `Buy {Format.Credits(total)}` else "Buy missing", x + 20 + bw, by, bw, 28,
    affordable and (Session.CanDo(session, load)), "Fits:buy") then
    for _, gap in fit.missing do
      Session.Do(session, { kind = "BuyNow", actor = 0, type = gap.type, quantity = gap.want - gap.have })
    end
    Session.Do(session, { kind = "LoadFit", actor = 0, target = fit.id })
  end
  if Im.Button("Delete", x + 28 + bw * 2, by, bw, 28, true, "Fits:delete") then
    Session.Do(session, { kind = "DeleteFit", actor = 0, target = fit.id })
    fitPicked = 0
  end
end

-- ---------------------------------------------------------------------
-- What there is to fit, down the left.

-- A row of the list: a type, the stack of it in the hangar (or none: it
-- is the market's), what it takes of the hull, how many there are (or
-- what one costs), and whether it can be fitted now, with why not.
type Row = { type: string, item: State.Item?, name: string, cpu: number, grid: number, count: number, ask: number?, can: boolean, why: string }

-- What the market here sells that goes in a rack: asked once in a few
-- ticks, and not once a frame.
local selling = { station = 0, tick = -100, rack = "", fit = "", rows = {} :: { Row } }

local function onSale(game: Core.Game, station: number, ship: number, rack: string): { Row }
  local tick = game.state.tick
  -- (made again when the fit changes too: what fits now is by what is fitted)
  local fit = tostring(ship)
  for _, item in Core.Query.Fitted(game, ship) do
    fit ..= `,{item.id}`
  end
  if selling.station ~= station or selling.rack ~= rack or selling.fit ~= fit or tick < selling.tick or tick - selling.tick >= 5 then
    local rows: { Row } = {}
    for _, entry in Catalog.Listing("module") do
      local info = entry.info
      local module = if info then Modules.byId[info.id] else nil
      if info and module and module.slot == rack then
        local quote = Core.Query.Quote(game, station, info.id)
        local ask = quote.ask
        if ask and quote.stock > 0 then
          -- (judged as one from the hangar is: skills, and whether this hull takes it, the owner, 2026-11-23: an XL
          -- launcher was said to fit a battleship)
          local can, why = Core.Query.CanFit(game, ship, info.id)
          table.insert(rows, { type = info.id, name = module.name, cpu = module.cpu, grid = module.powergrid, count = quote.stock, ask = ask,
            can = can, why = tostring(why or "") })
        end
      end
    end
    selling = { station = station, tick = tick, rack = rack, fit = fit, rows = rows }
  end
  return selling.rows
end

local function columnsFor(last: string, wide: number): { List.Column }
  return {
    { id = "name", label = "Module", width = 0, sort = false }, { id = "cpu", label = "tf", width = 28, right = true, sort = false },
    { id = "grid", label = "MW", width = 36, right = true, sort = false }, { id = "last", label = last, width = wide, right = true, sort = false },
  }
end
local HANGAR_COLUMNS, MARKET_COLUMNS = columnsFor("Qty", 30), columnsFor("Price", 60)

local function drawBrowser(session: Session.Session, game: Core.Game, station: number, ship: number, x: number, y: number, w: number, h: number)
  -- The slot picked, and what is in it.
  local inSlot: State.Item? = nil
  for _, item in Core.Query.Fitted(game, ship) do
    if item.place == slotRack and item.slot == slotNumber then
      inSlot = item
    end
  end
  Im.Text("For the slot picked:", x + 10, y + 10, 12, Theme.DIM)
  Im.Strong(RACK_NAMES[slotRack] .. (if slotNumber > 0 and slotRack ~= "rig" then ` {slotNumber}` elseif slotNumber > 0 then `, {slotNumber}` else ""),
    x + 16 + Im.TextWidth("For the slot picked:", 12), y + 10, 12, Theme.ACCENT)
  if inSlot then
    local within = inSlot
    local module = Modules.byId[within.type]
    ItemIcon.Draw(within.type, x + 10, y + 30, 22)
    Im.Text(List.Cut(module.name, w - 46 - 138, 14, false), x + 38, y + 34, 14, Theme.TEXT)
    if Im.Button("Info", x + w - 132, y + 30, 46, 22, true, `Info:{within.type}`) then
      Info.Open(within.type)
    end
    local out: State.Command = { kind = "Unfit", actor = 0, item = within.id }
    local can, why = Session.CanDo(session, out)
    Im.Because(why)
    if Im.Button("Take out", x + w - 82, y + 30, 72, 22, can, "Fitting:takeout") then
      Session.Do(session, out)
    end
  else
    Im.Text(if slotNumber > 0 then "Empty." else "Click a slot on the wheel to pick it.", x + 10, y + 34, 13, Theme.FAINT)
  end
  Im.Flat(x, y + 60, w, 1, Theme.EDGE)
  -- Where what is offered is, and what its names are narrowed by.
  local cx = x + 10
  for _, each in { { "hangar", "In the hangar" }, { "market", "On the market here" } } do
    local pressed, wide = List.Chip(each[2], cx, y + 70, source == each[1], `Fitting:from:{each[1]}`)
    if pressed and source ~= each[1] then
      source = each[1]
      chosen = ""
      Im.ScrollTo("fitting modules", 0)
    end
    cx += wide + 4
  end
  local sought = Im.Words("Fitting:filter", filter, x + 10, y + 100, w - 20, 26, 32, "Filter")
  if sought ~= filter then
    filter = sought
    Im.ScrollTo("fitting modules", 0)
  end
  local wanted = string.lower(filter)

  -- What fits now first; then what does not yet, with why.
  local fits: { Row }, others: { Row } = {}, {}
  local function add(row: Row)
    if wanted == "" or string.find(string.lower(row.name), wanted, 1, true) then
      table.insert(if row.can then fits else others, row)
    end
  end
  if source == "market" then
    for _, row in onSale(game, station, ship, slotRack) do
      add(row)
    end
  end
  -- (and the charges in the hangar that the fitted weapons take: those
  -- of the weapon in the slot picked, if it holds one)
  local weapon: string? = if inSlot and Modules.Takes(Modules.byId[inSlot.type]) then inSlot.type else nil
  local charges: { { item: State.Item, into: { State.Item } } } = {}
  for _, item in Core.Query.Items(game, station, "hangar") do
    local info = Types.Info(item.type)
    if info.category == "module" and source == "hangar" then
      local module = Modules.byId[item.type]
      if module.slot == slotRack then
        local can, why = Session.CanDo(session, { kind = "Fit", actor = 0, item = item.id })
        add({ type = item.type, item = item, name = module.name, cpu = module.cpu, grid = module.powergrid, count = item.quantity, can = can,
          why = tostring(why or "") })
      end
    elseif info.category == "charge" then
      local any, into = takers(game, ship, item, weapon)
      if any then
        table.insert(charges, { item = item, into = into })
      end
    end
  end
  local function byName(a: Row, b: Row): boolean
    return if a.name ~= b.name then a.name < b.name else a.type < b.type
  end
  table.sort(fits, byName)
  table.sort(others, byName)
  type Line = { heading: string?, count: number?, row: Row? }
  local lines: { Line } = {}
  for _, part in { { "Fits now", fits }, { "Does not yet", others } } :: { { any } } do
    local rows: { Row } = part[2]
    if #rows > 0 then
      table.insert(lines, { heading = part[1], count = #rows })
      for _, row in rows do
        table.insert(lines, { row = row })
      end
    end
  end
  local columns = if source == "market" then MARKET_COLUMNS else HANGAR_COLUMNS
  local layout = List.Columns(columns, x, w - 6)
  local top = y + 134
  List.Head("fitting", x, top, w, columns, layout, "", false)
  top += List.HEAD
  local chargeRows = 4
  local chargeRoom = 30 + chargeRows * List.ROW
  local room = h - (top - y) - 42 - chargeRoom
  local first, visible = List.Body("fitting modules", x, top, w, room, #lines)
  if #lines == 0 then
    Im.Text(if filter ~= "" then "Nothing of that name." elseif source == "market" then "The market here sells nothing that goes there."
      else "Nothing in the hangar goes there.", x + 10, top + 10, 13, Theme.DIM)
  end
  local picked: Row? = nil
  for _, line in lines do
    if line.row and line.row.type == chosen then
      picked = line.row
    end
  end
  -- (what a row picked does, picked again: it is fitted, or the market is opened at it)
  local function act(row: Row)
    local item = row.item
    if item then
      Session.Do(session, { kind = "Fit", actor = 0, item = item.id })
    elseif Fitting.Market then
      Fitting.Market(row.type)
    end
  end
  for index = 1, visible do
    local line = lines[index + first]
    if line == nil then
      break
    end
    local rowY = top + (index - 1) * List.ROW
    local row = line.row
    if row == nil then
      List.Group(line.heading or "", tostring(line.count or 0), x, rowY, w - 5, nil)
      continue
    end
    local hot, clicked, double = List.Row(x, rowY, w - 5, chosen == row.type, `Fitting:module:{row.type}`)
    ItemIcon.Draw(row.type, layout.name.x, rowY + 3, 19)
    if row.can then
      List.Text(row.name, layout.name, rowY, hot, Theme.TEXT, 14, false, 25)
      List.Text(tostring(row.cpu), layout.cpu, rowY, false, Theme.DIM, 13)
      List.Text(tostring(row.grid), layout.grid, rowY, false, Theme.DIM, 13)
    else
      -- (what cannot be fitted yet: its name dimmed, and why not where what it takes would be)
      local span = layout.grid.x + layout.grid.w - layout.name.x - 25
      local why = List.Cut(row.why, span * 0.5, 12, false)
      local whyWidth = Im.TextWidth(why, 12)
      Im.Text(List.Cut(row.name, span - whyWidth - 8, 14, false), layout.name.x + 25, rowY + 5, 14, Theme.DIM)
      Im.Text(why, layout.grid.x + layout.grid.w - whyWidth, rowY + 6, 12, Theme.BAD)
      if hot then
        Im.Tip(row.name, row.why)
      end
    end
    local ask = row.ask
    List.Text(if ask then Format.Whole(ask) else Format.Whole(row.count), layout.last, rowY, false, Theme.TEXT, 13)
    if clicked then
      chosen = row.type
    end
    if double and (row.can or row.item == nil) then
      act(row)
    end
  end
  -- The row picked, fitted (or looked up on the market): or why it cannot be.
  local fy = top + room + 8
  Im.Tone("primary")
  local label, can = "Fit", false
  if picked == nil then
    Im.Because("Pick a module in the list")
  elseif picked.item then
    label, can = `Fit {List.Cut(picked.name, w - 80, 14, true)}`, picked.can
    Im.Because(picked.why)
  else
    label, can = "See it on the market", Fitting.Market ~= nil
  end
  if Im.Button(label, x + 10, fy, w - 20, 26, can, "Fitting:fit") and picked then
    act(picked)
  end
  -- The charges.
  local cy = fy + 36
  Im.Flat(x, cy - 1, w, 1, Theme.EDGE)
  Im.Strong(List.Cut(if weapon then `CHARGES FOR THE {string.upper(Modules.byId[weapon].name)}` else "CHARGES FOR THE FITTED WEAPONS", w - 20, 11,
    true), x + 10, cy + 8, 11, Theme.DIM)
  cy += 26
  if #charges == 0 then
    Im.Text("None in the hangar.", x + 10, cy + 4, 13, Theme.FAINT)
  end
  local from = Im.Scroll("fitting charges", x, cy, w, chargeRows * List.ROW, #charges, chargeRows)
  for index = 1, chargeRows do
    local charge = charges[index + from]
    if charge == nil then
      break
    end
    local rowY = cy + (index - 1) * List.ROW
    local type = charge.item.type
    ItemIcon.Draw(type, x + 10, rowY + 3, 19)
    Im.Text(List.Cut(Types.Info(type).name, w - 166, 14, false), x + 35, rowY + 5, 14, Theme.TEXT)
    local count = Format.Whole(charge.item.quantity)
    Im.Text(count, x + w - 80 - Im.TextWidth(count, 13), rowY + 5, 13, Theme.DIM)
    if #charge.into == 0 then
      Im.Text("loaded", x + w - 16 - Im.TextWidth("loaded", 13), rowY + 5, 13, Theme.GOOD)
    elseif Im.Button("Load", x + w - 70, rowY + 2, 58, 21, true, `Fitting:load:{type}`) then
      -- (into every weapon that takes it and has something else in it, or nothing)
      for _, into in charge.into do
        Session.Do(session, { kind = "LoadCharge", actor = 0, item = into.id, other = charge.item.id })
      end
    end
  end
end

-- ---------------------------------------------------------------------
-- The window

-- Whose game it is, and what the wheel draws the ship with (Fitting.Frame).
local current: Session.Session? = nil
local scenery: { preview: Preview?, show: Show? } = {}

function Fitting.Open()
  Windows.Open(Fitting.ID)
  Windows.Raise(Fitting.ID)
end

function Fitting.Close()
  Windows.Close(Fitting.ID)
end

function Fitting.IsOpen(): boolean
  return Windows.IsOpen(Fitting.ID)
end

-- The page shown ("fitting", "fits" or "appearance"): given one, the window is
-- opened at it.
function Fitting.Show(to: string?): string
  if to == "fitting" or to == "appearance" or to == "fits" then
    page = to
    Fitting.Open()
  end
  return page
end

-- Fit out a ship of the pilot's at the station, without boarding it (or,
-- 0, the one flown): the window opens on it.
function Fitting.Edit(ship: number)
  subject = ship
  page = "fitting"
  Fitting.Open()
end

-- The ship the window fits out: the one picked (Fitting.Edit), while it
-- is one of the pilot's where they are that nobody else has; else the
-- one flown.
function Fitting.Subject(game: Core.Game): number
  local state = game.state
  local other = state.ships[subject]
  local mine = state.ships[state.player.ship]
  if other and mine and other.owner == "player" and other.pilot == 0 and other.member == nil and State.At(other) ~= 0
    and State.At(other) == State.At(mine) then
    return other.id
  end
  subject = 0
  return state.player.ship
end

-- Once a frame, before the windows are drawn: whose game it is, whether
-- the pilot is docked, and what the wheel draws the ship with (the
-- scene's: Scene.Dressed and Scene.Showcase). The window is a
-- station's (Windows.Berthed), and open at the first: it is what a
-- docked pilot first sees.
function Fitting.Frame(session: Session.Session, docked: boolean, preview: Preview?, show: Show?)
  current = session
  scenery = { preview = preview, show = show }
  Windows.Berthed(Fitting.ID, docked, true)
end

local LEFT_W, RIGHT_W = 326, 280

Windows.Kind(Fitting.ID, function(_: Windows.Window, x: number, y: number, w: number, h: number)
  local session = current
  if session == nil then
    return
  end
  local game = session.game
  local player = Core.Query.Player(game)
  if player.at == 0 then
    Im.Text("A ship is fitted at a station: dock at one, or enter the field of a tower of yours.", x + 14, y + 14, 14, Theme.DIM)
    return
  end
  -- (another of the pilot's ships here, being fitted out: what is said of
  -- "the player's" ship below is said of it, and what is done is done for it)
  local flown = player.ship
  local other = Fitting.Subject(game)
  if other ~= flown then
    local record = game.state.ships[other]
    player = table.clone(player)
    player.ship, player.shipName, player.hull = other, record.name, Hulls.byId[record.type]
  end
  session.as = other
  local ship = player.ship
  -- What a ship is fitted from is the inventory too: a module carried
  -- here from it is fitted, and a charge is loaded into a weapon that
  -- takes it.
  local carried = Im.Drop("Fitting:onto", x, y, w, h)
  if carried and carried.items then
    for _, id in carried.items :: { number } do
      local item = game.state.items[id]
      local category = if item then Types.Info(item.type).category else ""
      if item and category == "module" then
        Session.Do(session, { kind = "Fit", actor = 0, item = item.id })
      elseif item and category == "charge" then
        -- (into every weapon that takes it and has something else in it,
        -- or nothing, as the Load button does: the owner, 2026-11-23)
        local any, into = takers(game, ship, item)
        for _, weapon in into do
          Session.Do(session, { kind = "LoadCharge", actor = 0, item = weapon.id, other = item.id })
        end
        if not any then
          Session.Say(session, `Nothing fitted takes {Types.Info(item.type).name}`, "bad")
        end
      elseif item then
        Session.Say(session, `{Types.Info(item.type).name} is not something a ship is fitted with`, "bad")
      end
    end
  end
  local was = Im.Plain(true)
  -- (something tried on is looked at on the page it is tried on: once, when it begins)
  local trying = session.trying.paint ~= nil or session.trying.design ~= nil
  if trying and not triedShown then
    page = "appearance"
  end
  triedShown = trying
  -- The pages.
  local tx = x + 10
  for _, each in { { "fitting", "Fitting" }, { "fits", "Saved fits" }, { "appearance", "Appearance" } } do
    local pressed, wide = Im.Tab(each[2], tx, y + 4, 28, page == each[1], `Fitting:{each[1]}`)
    if pressed then
      page = each[1]
    end
    tx += wide + 2
  end
  -- (what can be done here is what the station has a module for)
  local _, services = Core.Query.Station(game, player.at)
  local fits = false
  for _, service in services do
    fits = fits or (service :: string) == "fitting"
  end
  local note = if fits then "carry a module here from the inventory, or double-click it in the list" else "This station has no fitting service."
  if ship ~= flown then
    -- (not the ship flown: said, and the way back to it)
    note = `{shorten(player.shipName, 26)}: not the ship you fly`
    if Im.Button("Your ship", x + w - 100, y + 4, 90, 24, true, "Fitting:mine") then
      subject = 0
    end
    Im.Text(note, x + w - 112 - Im.TextWidth(note, 12), y + 11, 12, Theme.CAUTION)
  else
    Im.Text(note, x + w - 12 - Im.TextWidth(note, 12), y + 11, 12, if fits then Theme.DIM else Theme.CAUTION)
  end
  Im.Flat(x + 1, y + 32, w - 2, 1, Theme.EDGE)
  local top, room = y + 33, h - 34
  Im.Flat(x + LEFT_W, top, 1, room, Theme.EDGE)
  Im.Flat(x + w - RIGHT_W, top, 1, room, Theme.EDGE)

  -- The left: what there is to fit, or what there is to paint it in.
  if page == "appearance" then
    drawPaints(session, game, player, x + 1, top, LEFT_W - 1)
  elseif page == "fits" then
    drawFits(session, game, player, x + 1, top, LEFT_W - 1, room)
  else
    drawBrowser(session, game, player.at, ship, x + 1, top, LEFT_W - 1, room)
  end

  -- The middle: the ship in its wheel, its name over it.
  local middle = w - LEFT_W - RIGHT_W
  local cx, cy = math.floor(x + LEFT_W + middle / 2), top + 236
  local title = string.upper(shorten(player.hull.name, 24))
  local titleWidth = Im.HeadingWidth(title, 16)
  local across = 28 + titleWidth + 12 + 46
  ItemIcon.Draw(player.hull.id, cx - across / 2, top + 10, 22)
  Im.Heading(title, cx - across / 2 + 28, top + 13, 16, Theme.TEXT)
  if Im.Button("Info", cx + across / 2 - 46, top + 10, 46, 22, true, `Info:{player.hull.id}`) then
    Info.Open(player.hull.id)
  end
  drawWheel(session, game, player, cx, cy, scenery.preview, scenery.show)

  -- Under it: what the fit takes of what the hull has, and its hardpoints.
  local hull = player.hull
  local stats = Core.Query.Stats(game, ship)
  local cpu, powergrid = Core.Query.FittingUse(game, ship)
  local fitted = Core.Query.Fitted(game, ship)
  local turrets, launchers, calibration, loose = 0, 0, 0, 0
  for _, item in fitted do
    local module = Modules.byId[item.type]
    turrets += if module.hardpoint == "turret" then 1 else 0
    launchers += if module.hardpoint == "launcher" then 1 else 0
    calibration += if item.place == "rig" then module.calibration or 0 else 0
    loose += if item.place ~= "rig" then 1 else 0
  end
  local bx, bw = x + LEFT_W + 28, middle - 56
  local by = cy + RING + 66
  useBar("CPU", cpu, stats.cpu, "tf", Theme.ACCENT, bx, by, bw)
  useBar("Powergrid", powergrid, stats.powergrid, "MW", Theme.ARMOR, bx, by + 22, bw)
  by += 44
  if (hull.rigs or 0) > 0 then
    useBar("Calibration", calibration, hull.calibration or 0, "", Theme.CAPACITOR, bx, by, bw)
    by += 22
  end
  for _, place in Core.Query.Places(game) do
    if place.kind == "cargo" and place.holder == ship then
      useBar("Hold", place.used, place.capacity, "m3", Theme.DIM, bx, by, bw)
      by += 22
      break
    end
  end
  local across2 = bx
  for _, each in { { "Turret hardpoints", turrets, hull.turrets }, { "Launcher hardpoints", launchers, hull.launchers } } :: { { any } } do
    Im.Text(each[1], across2, by + 6, 13, Theme.DIM)
    across2 += Im.TextWidth(each[1], 13) + 8
    local count = `{each[2]} / {each[3]}`
    Im.Text(count, across2, by + 6, 13, if each[2] > each[3] then Theme.BAD else Theme.TEXT)
    across2 += Im.TextWidth(count, 13) + 22
  end

  -- At its foot: the mending of the ship, and the stripping of the fit.
  local foot = y + h - 40
  local canRepair, whyNotRepair = Session.CanDo(session, { kind = "Repair", actor = 0 })
  local record = game.state.ships[ship]
  local damaged = record.armorDamage + record.hullDamage > 0
  Im.Because(if damaged then whyNotRepair else "Its armour and its hull are whole")
  if Im.Button(if damaged then `Repair  {Format.Whole(Core.Query.RepairCost(game, ship))} cr` else "No damage to mend", bx, foot, 180, 28,
    canRepair, "Repair") then
    Session.Do(session, { kind = "Repair", actor = 0 })
  end
  stripping = math.max(0, stripping - 1)
  Im.Because("Nothing is fitted that comes out whole")
  if stripping > 0 then
    Im.Tone("danger")
  end
  if Im.Button(if stripping > 0 then "Sure? Strip it" else "Strip the fit", bx + bw - 130, foot, 130, 28, loose > 0, "Fitting:strip") then
    if stripping > 0 then
      -- (every module to the hangar: a rig stays, since taking one out destroys it)
      for _, item in fitted do
        if item.place ~= "rig" then
          Session.Do(session, { kind = "Unfit", actor = 0, item = item.id })
        end
      end
      stripping = 0
    else
      stripping = 180
    end
  end

  -- The right: what it comes to.
  drawFigures(game, ship, x + w - RIGHT_W + 14, top + 14, RIGHT_W - 28)
  Im.Plain(was)
  session.as = nil
end)
Windows.Make(Fitting.ID, Fitting.ID, "Fitting", 534, 130, 1040, 720, 1040, 700, nil)
Windows.Icon(Fitting.ID, "fitting")

return Fitting
