--!strict
-- The interface while docked: the ship's fit, the market, industry,
-- skills, the ships kept here and the wallet, a tab each.
--
-- Drawn every frame with Game/UI/Im. It reads the Core through queries
-- and acts on it only through the Session. Every button has a name a
-- script can press it by (Im.Press): its label, or the id given here.

local Blueprints = require("@lt/Core/Data/Blueprints")
local Catalog = require("@lt/Core/Data/Catalog")
local Constants = require("@lt/Core/Data/Constants")
local Core = require("@lt/Core/Api")
local Fleet = require("@lt/Core/Tactical/Fleet")
local Format = require("@lt/Game/Format")
local Im = require("@lt/Game/UI/Im")
local Industry = require("@lt/Core/Assets/Industry")
local Info = require("@lt/Game/UI/Info")
local ItemIcon = require("@lt/Game/UI/ItemIcon")
local Modules = require("@lt/Core/Data/Modules")
local Ores = require("@lt/Core/Data/Ores")
local Session = require("@lt/Game/Session")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local Types = require("@lt/Core/Data/Types")

local Station = {}

Station.WIDTH = 940
Station.HEIGHT = 600

local TABS: { string } = { "Fitting", "Market", "Industry", "Skills", "Ships", "Crew", "Wallet", "Missions" }
-- (and one more at a starbase of the pilot's own: the running of it)
local OWN: { string } = { "Fitting", "Market", "Industry", "Skills", "Ships", "Crew", "Wallet", "Missions", "Starbase" }
-- The services each tab's doings are done by (Core/Assets/Stations).
local WANTS: { [string]: { string } } = {
  Fitting = { "fitting" }, Market = { "market" }, Industry = { "refining", "industry", "research" }, Ships = { "fitting" },
}
local tab = "Fitting"
local dockedAt = 0    -- the station the screen was last drawn for

-- The market: the category listed, the type shown, and what is entered.
local CATEGORIES: { { string } } = {
  { "module", "Modules" }, { "charge", "Charges" }, { "drone", "Drones" }, { "ship", "Ships" }, { "structure", "Structures" }, { "ore", "Ore" }, { "mineral", "Minerals" },
  { "planetary", "Planetary" }, { "component", "Components" },
  { "blueprint", "Blueprints" }, { "skillbook", "Skill books" }, { "implant", "Implants" }, { "goods", "Goods" },
}
local category = "module"
local chosen = ""
local quantity = 1
local sellPrice, buyPrice = 0, 0    -- 0: the best price that fills now

-- Industry: the blueprint shown and the runs entered.
local blueprintChosen = ""
local runs = 1

local GOOD = vector.create(0.45, 0.85, 0.55)
local HOSTILE = vector.create(0.85, 0.35, 0.3)

-- ---------------------------------------------------------------------
-- Small pieces

local function shorten(text: string, limit: number): string
  return if #text > limit then string.sub(text, 1, limit - 1) .. "." else text
end

-- A type's stack in a station's hangar, and how many it holds.
local function inHangar(game: Core.Game, station: number, type: string): (State.Item?, number)
  for _, item in Core.Query.Items(game, station, "hangar") do
    if item.type == type then
      return item, item.quantity
    end
  end
  return nil, 0
end

-- Show a tab, as clicking it would: for scripted runs.
function Station.Show(name: string): boolean
  for _, known in OWN do
    if known == name then
      tab = name
      return true
    end
  end
  return false
end

function Station.Tab(): string
  return tab
end

-- Open the market at a type, as clicking through to it would.
function Station.Choose(type: string): boolean
  local info = Types.Get(type)
  if info == nil then
    return false
  end
  tab = "Market"
  category = info.category
  if chosen ~= type then
    chosen = type
    quantity = 1
    sellPrice, buyPrice = 0, 0
    -- (bring its row into the list, a little way down from the top)
    for index, entry in Catalog.Listing(category) do
      if entry.info and entry.info.id == type then
        Im.ScrollTo("market", index - 4)
      end
    end
  end
  return true
end

-- Open the industry tab at a blueprint, as clicking its row would.
function Station.Blueprint(type: string): boolean
  if Blueprints.byId[type] == nil then
    return false
  end
  tab = "Industry"
  if blueprintChosen ~= type then
    blueprintChosen = type
    runs = 1
  end
  return true
end

-- ---------------------------------------------------------------------
-- Fitting: the fit, the hangar and the hold

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

-- The fitting screen is set out as EVE's is. In the middle is the ship,
-- turning, inside a wheel of its slots: high slots along the top, mid
-- slots down the right, low slots along the bottom, and on the left two
-- arcs that fill as the fit uses the hull's CPU and powergrid. A slot
-- shows what is fitted in it, and inside the wheel what a weapon is
-- loaded with. To the right is what the fit comes to: capacitor,
-- offence, defence layer by layer with what each resists, targeting,
-- navigation. To the left are the hangar and the hold, to fit from.

local RING = 150          -- from the middle of the wheel to the middle of a slot
local SLOT = 36

-- Where each rack sits on the wheel, in turns (0 is to the right, a
-- quarter is straight down): the middle of its arc, and how much of the
-- wheel it may take.
local RACKS: { { any } } = {
  { "high", "High", 0.75, 0.32 },
  { "mid", "Mid", 0.02, 0.20 },
  { "low", "Low", 0.28, 0.28 },
}

local EM, THERMAL, KINETIC, EXPLOSIVE = vector.create(0.35, 0.62, 1.0), vector.create(1.0, 0.40, 0.30),
  vector.create(0.72, 0.74, 0.78), vector.create(1.0, 0.70, 0.25)
local KINDS = { EM, THERMAL, KINETIC, EXPLOSIVE }
local CPU_COLOR, GRID_COLOR = vector.create(0.40, 0.75, 1.0), vector.create(1.0, 0.62, 0.25)
local OVER = vector.create(1.0, 0.25, 0.2)

local function onWheel(cx: number, cy: number, radius: number, turn: number): (number, number)
  local angle = 2 * math.pi * turn
  return cx + radius * math.cos(angle), cy + radius * math.sin(angle)
end

-- An arc of a ring round (cx, cy), from one turn to another.
local function arc(cx: number, cy: number, inner: number, outer: number, from: number, to: number, color: vector, alpha: number)
  if to > from then
    WidgetRenderer_DrawPanelRadial(vector.create(cx, cy), inner, outer, ((from + to) / 2) % 1, to - from, color, alpha, alpha, 0)
  end
end

-- A gauge along an arc: how much of 'capacity' is 'used'. It fills from
-- 'from' toward 'to', whichever way round that is.
local function gauge(cx: number, cy: number, from: number, to: number, used: number, capacity: number, color: vector)
  arc(cx, cy, RING - 9, RING + 9, math.min(from, to), math.max(from, to), Im.DIM, 0.3)
  local share = math.min(1, if capacity > 0 then used / capacity else 0)
  local reached = from + (to - from) * share
  arc(cx, cy, RING - 9, RING + 9, math.min(from, reached), math.max(from, reached), if used > capacity then OVER else color, 0.95)
end

local turning = 0

-- What the fitting screen draws of the ship: its hull first, then
-- whatever stands on it, each with where it stands in the hull's units.
export type Preview = { { model: Renderable | Model, transform: Transform } }

local function drawWheel(session: Session.Session, game: Core.Game, player: Core.PlayerInfo, cx: number, cy: number,
  preview: Preview?)
  local ship = player.ship
  local hull = player.hull
  local stats = Core.Query.Stats(game, ship)
  local cpu, powergrid = Core.Query.FittingUse(game, ship)

  -- The ship, turning.
  WidgetRenderer_DrawPanelRadial(vector.create(cx, cy), 0, RING - 28, 0, 1, vector.create(0.02, 0.03, 0.045), 0.9, 0.9, 0)
  if preview and preview[1] then
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
        vector.create(cx - side / 2, cy - side / 2), vector.create(side, side),
        if index == 1 then vector.create(0.55, 0.80, 1.0) else vector.create(1.0, 0.72, 0.30), if index == 1 then 0.95 else 1.0, turning)
    end
  else
    ItemIcon.Draw(hull.id, cx - 40, cy - 40, 80)
  end

  -- The rim the slots sit on.
  arc(cx, cy, RING - 1, RING + 1, 0, 1, Im.DIM, 0.22)

  -- What the fit takes of the hull's CPU and powergrid, on the left.
  gauge(cx, cy, 0.505, 0.570, cpu, stats.cpu, CPU_COLOR)
  gauge(cx, cy, 0.495, 0.430, powergrid, stats.powergrid, GRID_COLOR)

  -- The slots.
  local hint = ""
  local fitted: { [string]: { [number]: State.Item } } = { high = {}, mid = {}, low = {}, rig = {} }
  local turretsUsed, launchersUsed = 0, 0
  for _, item in Core.Query.Fitted(game, ship) do
    fitted[item.place][item.slot] = item
    local hardpoint = Modules.byId[item.type].hardpoint
    if hardpoint == "turret" then
      turretsUsed += 1
    elseif hardpoint == "launcher" then
      launchersUsed += 1
    end
  end
  local counts = { high = hull.highs, mid = hull.mids, low = hull.lows }
  for _, rack in RACKS do
    local name: string, label: string, middle: number, span: number = rack[1], rack[2], rack[3], rack[4]
    local count = counts[name]
    local pitch = math.min(0.047, span / math.max(1, count))
    -- (its name, inside the wheel at the start of its arc)
    local lx, ly = onWheel(cx, cy, RING - 4, middle - pitch * (count + 1) / 2 - 0.004)
    Im.Text(string.upper(label), lx - Im.TextWidth(string.upper(label), 10) / 2, ly - 6, 10, Im.DIM)
    for slot = 1, count do
      local turn = middle + (slot - (count + 1) / 2) * pitch
      local sx, sy = onWheel(cx, cy, RING, turn)
      local left, top = sx - SLOT / 2, sy - SLOT / 2
      local item = fitted[name][slot]
      if item then
        local module = Modules.byId[item.type]
        local hot, clicked = Im.Area(`Info:{item.type}`, left, top, SLOT, SLOT, true)
        ItemIcon.Draw(item.type, left, top, SLOT)
        if hot then
          Im.Fill(left, top, SLOT, SLOT, Im.ACCENT, 0.18)
          hint = `{label} {slot}:  {module.name}`
        end
        if clicked then
          Info.Open(item.type)
        end
        -- what it is loaded with, inside the wheel
        if module.weapon then
          local ix, iy = onWheel(cx, cy, RING - 36, turn)
          if item.charge ~= "" then
            ItemIcon.Draw(item.charge, ix - 10, iy - 10, 20)
            if hot or Im.Inside(ix - 10, iy - 10, 20, 20) then
              hint = `{label} {slot}:  {module.name},  {Types.Info(item.charge).name}`
                .. (if module.weapon.clip > 0 then ` x{item.rounds}` else "")
            end
          else
            WidgetRenderer_DrawPanel(vector.create(ix - 10, iy - 10), vector.create(20, 20), Im.WARN, 0.15, 0.6, 3)
            if hot then
              hint ..= ",  nothing loaded"
            end
          end
        end
        -- taking it out: the corner away from the middle
        local ux, uy = onWheel(sx, sy, SLOT * 0.62, turn)
        local unfitHot, unfit = Im.Area(`Unfit:{name}{slot}`, ux - 8, uy - 8, 16, 16,
          (Session.CanDo(session, { kind = "Unfit", actor = 0, item = item.id })))
        WidgetRenderer_DrawPanel(vector.create(ux - 8, uy - 8), vector.create(16, 16),
          if unfitHot then OVER else vector.create(0.07, 0.12, 0.17), 0.9, 1, 8)
        Glyph_Draw(Glyph_Line(vector.create(-1, -1), vector.create(1, 1), 1, 1), vector.create(ux, uy), 3, Im.TEXT, 0.9)
        Glyph_Draw(Glyph_Line(vector.create(-1, 1), vector.create(1, -1), 1, 1), vector.create(ux, uy), 3, Im.TEXT, 0.9)
        if unfitHot then
          hint = `Take the {module.name} out`
        end
        if unfit then
          Session.Do(session, { kind = "Unfit", actor = 0, item = item.id })
        end
      else
        WidgetRenderer_DrawPanel(vector.create(left, top), vector.create(SLOT, SLOT), vector.create(0.22, 0.32, 0.42), 0.18, 0.75, 5)
        if Im.Inside(left, top, SLOT, SLOT) then
          hint = `{label} {slot}:  empty`
        end
      end
    end
  end

  -- The rigs: a row of their own inside the foot of the wheel (the ring
  -- is full). A rig taken out is destroyed, and its cross says so.
  local rigs = hull.rigs or 0
  if rigs > 0 then
    local size = 30
    Im.Text("RIGS", cx - Im.TextWidth("RIGS", 10) / 2, cy + 76, 10, Im.DIM)
    for slot = 1, rigs do
      local left, top = cx + (slot - (rigs + 1) / 2) * (size + 8) - size / 2, cy + 92
      local item = fitted.rig[slot]
      if item then
        local module = Modules.byId[item.type]
        local hot, clicked = Im.Area(`Info:{item.type}`, left, top, size, size, true)
        ItemIcon.Draw(item.type, left, top, size)
        if hot then
          Im.Fill(left, top, size, size, Im.ACCENT, 0.18)
          hint = `Rig {slot}:  {module.name}`
        end
        if clicked then
          Info.Open(item.type)
        end
        local ux, uy = left + size, top
        local unfitHot, unfit = Im.Area(`Unfit:rig{slot}`, ux - 8, uy - 8, 16, 16,
          (Session.CanDo(session, { kind = "Unfit", actor = 0, item = item.id })))
        WidgetRenderer_DrawPanel(vector.create(ux - 8, uy - 8), vector.create(16, 16),
          if unfitHot then OVER else vector.create(0.07, 0.12, 0.17), 0.9, 1, 8)
        Glyph_Draw(Glyph_Line(vector.create(-1, -1), vector.create(1, 1), 1, 1), vector.create(ux, uy), 3, Im.TEXT, 0.9)
        Glyph_Draw(Glyph_Line(vector.create(-1, 1), vector.create(1, -1), 1, 1), vector.create(ux, uy), 3, Im.TEXT, 0.9)
        if unfitHot then
          hint = `Take the {module.name} out: it will be destroyed`
        end
        if unfit then
          Session.Do(session, { kind = "Unfit", actor = 0, item = item.id })
        end
      else
        WidgetRenderer_DrawPanel(vector.create(left, top), vector.create(size, size), vector.create(0.22, 0.32, 0.42), 0.18, 0.75, 5)
        if Im.Inside(left, top, size, size) then
          hint = `Rig {slot}:  empty`
        end
      end
    end
  end

  -- Hardpoints, as pips: lit for each one in use.
  local function pips(label: string, used: number, total: number, px: number, py: number)
    Im.Text(label, px, py, 11, Im.DIM)
    for index = 1, total do
      WidgetRenderer_DrawPanel(vector.create(px + 66 + (index - 1) * 11, py + 3), vector.create(7, 7),
        if index <= used then Im.ACCENT else Im.DIM, if index <= used then 1 else 0.2, if index <= used then 1 else 0.5, 3)
    end
  end
  pips("TURRETS", turretsUsed, hull.turrets, cx - RING - 14, cy - RING - 44)
  pips("LAUNCHERS", launchersUsed, hull.launchers, cx - RING - 14, cy - RING - 28)

  -- Under the wheel: what the gauges say, and what the cursor is on.
  local below = cy + RING + 48
  local cpuText = string.format("CPU  %.0f / %.0f tf", cpu, stats.cpu)
  local gridText = string.format("Powergrid  %.0f / %.0f MW", powergrid, stats.powergrid)
  Im.Fill(cx - 170, below + 3, 8, 8, CPU_COLOR, 1)
  Im.Text(cpuText, cx - 156, below, 13, if cpu > stats.cpu then OVER else Im.TEXT)
  Im.Fill(cx + 8, below + 3, 8, 8, GRID_COLOR, 1)
  Im.Text(gridText, cx + 22, below, 13, if powergrid > stats.powergrid then OVER else Im.TEXT)
  if hint ~= "" then
    Im.Text(hint, cx - Im.TextWidth(hint, 13) / 2, below + 20, 13, Im.ACCENT)
  end
end

-- A heading of the column of figures, and the y of its first line.
local function block(title: string, x: number, y: number, width: number): number
  Im.Text(title, x, y, 11, Im.ACCENT, 0.9)
  Im.Fill(x, y + 15, width, 1, Im.DIM, 0.35)
  return y + 20
end

local function figure(label: string, value: string, x: number, y: number, width: number): number
  Im.Text(label, x, y, 13, Im.DIM)
  Im.TextRight(value, x + width, y, 13, Im.TEXT)
  return y + 19
end

-- What the fit comes to, down the right.
local function drawFigures(game: Core.Game, player: Core.PlayerInfo, x: number, y: number, width: number)
  local stats = Core.Query.Stats(game, player.ship)
  local offence = Core.Query.Offence(game, player.ship)

  local line = block("CAPACITOR", x, y, width)
  line = figure("Capacity", string.format("%.0f GJ", stats.capacitor), x, line, width)
  line = figure("Recharges in", Format.Duration(stats.capacitorRecharge), x, line, width)

  line = block("OFFENCE", x, line + 8, width)
  line = figure("Damage a second", string.format("%.1f", offence.dps), x, line, width)
  line = figure("A volley", string.format("%.0f", offence.volley), x, line, width)
  if offence.dps > 0 then
    -- how it divides between the four kinds of damage
    local at = x
    for index, color in KINDS do
      local share = offence.kinds[index] / offence.dps
      Im.Fill(at, line + 4, width * share, 6, color, 0.9)
      at += width * share
    end
    line += 16
    line = figure("Reaches", Format.Distance(offence.range), x, line, width)
  end

  -- Each layer: what it has, and what it stops of each kind of damage.
  line = block("DEFENCE", x, line + 8, width)
  local effective = 0
  for _, layer in { { "Shield", "shield" }, { "Armour", "armor" }, { "Hull", "hull" } } do
    local points = stats[layer[2]]
    Im.Text(layer[1], x, line, 13, Im.DIM)
    Im.TextRight(string.format("%.0f", points), x + 104, line, 13, Im.TEXT)
    local through = 0
    for index, color in KINDS do
      local resonance = stats[`{layer[2]}Resonance.{index}`]
      through += resonance / 4
      local cell = x + 114 + (index - 1) * ((width - 114) / 4)
      local cellWidth = (width - 114) / 4 - 3
      Im.Fill(cell, line + 2, cellWidth, 13, color, 0.14)
      Im.Fill(cell, line + 2, cellWidth * (1 - resonance), 13, color, 0.55)
      local text = string.format("%.0f", (1 - resonance) * 100)
      Im.Text(text, cell + (cellWidth - Im.TextWidth(text, 11)) / 2, line + 2, 11, Im.TEXT)
    end
    effective += points / through
    line += 19
  end
  line = figure("Effective", string.format("%.0f HP", effective), x, line + 2, width)

  line = block("TARGETING", x, line + 8, width)
  line = figure("Lock range", Format.Distance(stats.lockRange), x, line, width)
  line = figure("Scan resolution", string.format("%.0f mm", stats.scanResolution), x, line, width)
  line = figure("Signature", string.format("%.0f m", stats.signature), x, line, width)

  line = block("NAVIGATION", x, line + 8, width)
  line = figure("Top speed", string.format("%.0f m/s", stats.maxVelocity), x, line, width)
  line = figure("Aligns in", string.format("%.1f s", 1.3863 * stats.tau), x, line, width)
  figure("Warp speed", string.format("%.1f AU/s", stats.warpSpeed), x, line, width)
end

local function drawFitting(session: Session.Session, game: Core.Game, player: Core.PlayerInfo, x: number, y: number,
  preview: Preview?)
  local ship = player.ship
  local stats = Core.Query.Stats(game, ship)

  -- The hangar, to fit from, and the hold.
  local left = x + 16
  local columnWidth = 284
  local line = y + 78
  -- (set out as the market is: modules, then charges, and so on)
  local hangar = table.clone(Core.Query.Items(game, player.docked, "hangar"))
  table.sort(hangar, function(a: State.Item, b: State.Item): boolean
    if a.type ~= b.type then
      return Catalog.Before(a.type, b.type)
    end
    return a.id < b.id
  end)
  Im.Heading(`HANGAR  {#hangar}`, left, line, 16, Im.DIM)
  line += 24
  if #hangar == 0 then
    Im.Text("nothing here", left, line, 14, Im.DIM, 0.6)
  end
  local visible = 12
  local first = Im.Scroll("hangar", left - 4, line, columnWidth, visible * 24, #hangar, visible)
  for row = 1, visible do
    local item = hangar[row + first]
    if item == nil then
      break
    end
    local info = Types.Info(item.type)
    local name = shorten(info.name, 18)
    ItemIcon.Draw(item.type, left, line + 1, 20)
    Info.Name(item.type, name, left + 26, line + 3, 13, Im.TEXT)
    Im.Text(`x{item.quantity}`, left + 30 + Im.TextWidth(name, 13), line + 3, 12, Im.DIM)
    if info.category == "module" then
      local can = Session.CanDo(session, { kind = "Fit", actor = 0, item = item.id })
      if Im.Button("Fit", left + 178, line, 46, 21, can, `Fit:{item.type}`) then
        Session.Do(session, { kind = "Fit", actor = 0, item = item.id })
      end
    elseif info.category == "charge" then
      local weapon = weaponFor(game, ship, item)
      if Im.Button("Load", left + 178, line, 46, 21, weapon ~= nil, `Load:{item.type}`) and weapon then
        Session.Do(session, { kind = "LoadCharge", actor = 0, item = weapon.id, other = item.id })
      end
    elseif info.category == "ore" then
      local can = Session.CanDo(session, { kind = "Reprocess", actor = 0, item = item.id })
      if Im.Button("Refine", left + 178, line, 46, 21, can, `Refine:{item.type}`) then
        Session.Do(session, { kind = "Reprocess", actor = 0, item = item.id })
      end
    elseif info.category == "drone" then
      -- (a drone goes in the drone bay: as many of the stack as there is room for)
      local room = math.floor((Core.Query.Drones(game).bay - Core.Query.Drones(game).bayUsed + 1e-9) / info.volume)
      local toBay: State.Command = { kind = "MoveItems", actor = 0, item = item.id, to = "dronebay", quantity = math.min(item.quantity, room) }
      if Im.Button("Bay", left + 178, line, 46, 21, room >= 1 and (Session.CanDo(session, toBay)), `ToBay:{item.type}`) then
        Session.Do(session, toBay)
      end
    end
    local toHold = Session.CanDo(session, { kind = "MoveItems", actor = 0, item = item.id, to = "cargo" })
    if Im.Button("Hold", left + 228, line, 46, 21, toHold, `ToHold:{item.type}`) then
      Session.Do(session, { kind = "MoveItems", actor = 0, item = item.id, to = "cargo" })
    end
    line += 24
  end

  line = y + 78 + 24 + visible * 24 + 8
  Im.Heading(string.format("HOLD  %.1f / %.0f m3", Core.Query.CargoUsed(game, ship), stats.cargo), left, line, 16, Im.DIM)
  line += 24
  local hold = Core.Query.Items(game, ship, "cargo")
  if #hold == 0 then
    Im.Text("empty", left, line, 14, Im.DIM, 0.6)
  end
  for index, item in hold do
    if index > 3 then
      Im.Text(`and {#hold - 3} more`, left, line, 13, Im.DIM)
      break
    end
    local held = shorten(Types.Info(item.type).name, 18)
    ItemIcon.Draw(item.type, left, line + 1, 20)
    Info.Name(item.type, held, left + 26, line + 3, 13, Im.TEXT)
    Im.Text(`x{item.quantity}`, left + 30 + Im.TextWidth(held, 13), line + 3, 12, Im.DIM)
    if Im.Button("Hangar", left + 214, line, 60, 21, true, `ToHangar:{item.type}`) then
      Session.Do(session, { kind = "MoveItems", actor = 0, item = item.id, to = "hangar" })
    end
    line += 24
  end

  -- The drone bay, under the hold: what is in it, a stack to a line.
  local drones = Core.Query.Drones(game)
  if drones.bay > 0 then
    line = y + 78 + 24 + visible * 24 + 8 + 24 + 3 * 24 + 2
    Im.Heading(string.format("DRONE BAY  %.0f / %.0f m3", drones.bayUsed, drones.bay), left, line, 13, Im.DIM)
    -- (a click on a stack puts it back in the hangar)
    local bx = left
    for index, item in Core.Query.Items(game, ship, "dronebay") do
      if index <= 2 then
        local label = shorten(`{item.quantity} {Types.Info(item.type).name}`, 21)
        if Im.Button(label, bx, line + 17, 138, 20, true, `FromBay:{item.type}`) then
          Session.Do(session, { kind = "MoveItems", actor = 0, item = item.id, to = "hangar" })
        end
        bx += 142
      end
    end
  end

  -- The ship: its name over the wheel.
  local cx, cy = x + 480, y + 296
  local title = string.upper(shorten(player.hull.name, 20))
  local titleWidth = Im.TextWidth(title, 15) * 1.12
  ItemIcon.Draw(player.hull.id, cx + RING - 42 - titleWidth - 28, y + 74, 22)
  Im.Heading(title, cx + RING - 42 - titleWidth, y + 77, 15, Im.TEXT)
  if Im.Button("Info", cx + RING - 28, y + 74, 46, 21, true, `Info:{player.hull.id}`) then
    Info.Open(player.hull.id)
  end
  drawWheel(session, game, player, cx, cy, preview)

  drawFigures(game, player, x + 672, y + 76, 252)
end

-- ---------------------------------------------------------------------
-- Market

local function drawOrders(session: Session.Session, game: Core.Game, station: number, x: number, y: number, width: number)
  local orders = Core.Query.Orders(game, nil)
  Im.Heading(`MY ORDERS  {#orders}`, x, y, 16, Im.DIM)
  if #orders == 0 then
    Im.Text("No standing orders. Place one from an item's page.", x, y + 30, 14, Im.DIM, 0.8)
    return
  end
  local line = y + 28
  local visible = 16
  local first = Im.Scroll("orders", x - 4, line, width, visible * 26, #orders, visible)
  for row = 1, visible do
    local order = orders[row + first]
    if order == nil then
      break
    end
    local here = order.station == station
    local where = Core.Query.Body(game, order.station)
    Im.Text(if order.side == "sell" then "SELL" else "BUY", x, line + 4, 12, if order.side == "sell" then Im.WARN else GOOD)
    Im.Text(`{shorten(Types.Info(order.type).name, 28)}  x{Format.Whole(order.quantity)}`, x + 44, line + 3, 14, Im.TEXT)
    Im.TextRight(`at {Format.Credits(order.price)}`, x + 420, line + 3, 14, Im.TEXT)
    Im.Text(if here then "here" else shorten(if where then where.name else "?", 22), x + 436, line + 4, 12, Im.DIM)
    if Im.Button("Cancel", x + width - 80, line, 72, 22, here, `CancelOrder:{row + first}`) then
      Session.Do(session, { kind = "CancelOrder", actor = 0, order = order.id })
    end
    line += 26
  end
end

local function drawMarket(session: Session.Session, game: Core.Game, player: Core.PlayerInfo, x: number, y: number)
  local station = player.docked
  local top = y + 78

  -- What to list.
  for index, entry in CATEGORIES do
    if Im.Toggle(entry[2], x + 16, top + (index - 1) * 30, 118, 26, category == entry[1], `Category:{entry[1]}`) then
      category = entry[1]
    end
  end
  if Im.Toggle("My orders", x + 16, top + #CATEGORIES * 30 + 12, 118, 26, category == "orders", "Category:orders") then
    category = "orders"
  end

  local listX = x + 146
  if category == "orders" then
    drawOrders(session, game, station, listX + 4, top, 774)
    return
  end

  -- The types of the category, group by group under headings
  -- (Data/Catalog), with what the station asks for one.
  local list = Catalog.Listing(category)
  local rowHeight = 22
  local visible = 20
  Im.Text("ITEM", listX + 8, top, 12, Im.DIM)
  Im.TextRight("ASKS", listX + 296, top, 12, Im.DIM)
  local first = Im.Scroll("market", listX, top + 18, 304, visible * rowHeight, #list, visible)
  for row = 1, visible do
    local entry = list[row + first]
    if entry == nil then
      break
    end
    local rowY = top + 18 + (row - 1) * rowHeight
    local info = entry.info
    if info then
      local _, clicked = Im.Row(listX, rowY, 300, rowHeight, chosen == info.id)
      local quote = Core.Query.Quote(game, station, info.id)
      local color = if quote.ask then Im.TEXT else Im.DIM
      ItemIcon.Draw(info.id, listX + 6, rowY + 2, 18)
      Im.Text(shorten(info.name, 28), listX + 30, rowY + 3, 13, color)
      Im.TextRight(if quote.ask then Format.Whole(math.ceil(quote.ask)) else "none", listX + 296, rowY + 3, 13, color)
      if clicked then
        Station.Choose(info.id)
      end
    else
      Im.Text(string.upper(entry.header or ""), listX + 6, rowY + 6, 11, Im.ACCENT, 0.9)
      Im.Fill(listX + 6, rowY + rowHeight - 2, 290, 1, Im.DIM, 0.3)
    end
  end

  -- The type chosen.
  local dx = x + 470
  local info = Types.Get(chosen)
  if info == nil then
    Im.Text("Choose an item to see its prices.", dx, top + 4, 14, Im.DIM, 0.8)
    return
  end
  local quote = Core.Query.Quote(game, station, chosen)
  local stack, have = inHangar(game, station, chosen)
  local tax, fee = Core.Query.Fees(game)
  ItemIcon.Draw(chosen, dx, top - 6, 28)
  Im.Heading(shorten(info.name, 28), dx + 36, top - 4, 20, Im.TEXT)
  if Im.Button("Info", dx + 392, top - 4, 54, 22, true, `Info:{chosen}`) then
    Info.Open(chosen)
  end
  local line = top + 28
  local untrained = Core.Query.Untrained(game, chosen)
  Im.Text(string.format("%s m3 a unit", tostring(info.volume)), dx, line, 13, Im.DIM)
  if untrained then
    Im.Text(untrained, dx + 130, line, 13, Im.WARN)
  end
  line += 26
  Im.Text("The station asks", dx, line, 14, Im.DIM)
  Im.Text(if quote.ask then Format.Price(quote.ask) else "nothing: it has none", dx + 150, line, 14, Im.TEXT)
  Im.TextRight(`{Format.Whole(quote.stock)} in stock`, dx + 446, line, 14, Im.DIM)
  line += 22
  Im.Text("and bids", dx, line, 14, Im.DIM)
  Im.Text(Format.Price(quote.bid), dx + 150, line, 14, Im.TEXT)
  Im.TextRight(`{Format.Whole(have)} in your hangar`, dx + 446, line, 14, if have > 0 then Im.TEXT else Im.DIM)
  line += 36

  -- A trade at once.
  Im.Text("Quantity", dx, line + 5, 14, Im.DIM)
  quantity = Im.Number("Quantity", quantity, dx + 80, line, 100, 26)
  for index, preset in { 1, 10, 100, 1000 } do
    if Im.Button(Format.Whole(preset), dx + 190 + (index - 1) * 52, line, 48, 26, true, `Quantity:{preset}`) then
      quantity = preset
    end
  end
  if Im.Button("All", dx + 398, line, 48, 26, have > 0, "Quantity:all") then
    quantity = have
  end
  line += 36
  local whole = quantity >= 1
  local cost = if whole then Core.Query.BuyCost(game, station, chosen, quantity) else nil
  local canBuy, whyNot = Session.CanDo(session, { kind = "BuyNow", actor = 0, type = chosen, quantity = quantity })
  if Im.Button(if cost then `Buy now   {Format.Credits(cost)}` else "Buy now", dx, line, 218, 30, canBuy, "BuyNow") then
    Session.Do(session, { kind = "BuyNow", actor = 0, type = chosen, quantity = quantity })
  end
  local canSell = stack ~= nil and whole and quantity <= have
  local value = if canSell then Core.Query.SellValue(game, station, chosen, quantity) else 0
  if Im.Button(if canSell then `Sell now   {Format.Credits(value)}` else "Sell now", dx + 228, line, 218, 30, canSell, "SellNow")
    and stack then
    Session.Do(session, { kind = "SellNow", actor = 0, item = stack.id, quantity = quantity })
  end
  line += 34
  if not canBuy and whole then
    Im.Text(tostring(whyNot), dx, line, 12, Im.WARN)
  end
  line += 26

  -- Standing orders.
  Im.Heading("STANDING ORDERS", dx, line, 14, Im.DIM)
  Im.TextRight(string.format("broker %.1f%%   sales tax %.1f%%", fee * 100, tax * 100), dx + 446, line + 2, 12, Im.DIM)
  line += 26
  local bestSell = math.max(1, math.floor(quote.sellAt))
  local sellAt = if sellPrice > 0 then sellPrice else bestSell
  Im.Text("Sell at", dx, line + 5, 14, Im.DIM)
  local enteredSell = Im.Number("SellPrice", sellAt, dx + 80, line, 100, 26)
  if enteredSell ~= sellAt then
    sellPrice = enteredSell
    sellAt = enteredSell
  end
  local sellOrder: State.Command = { kind = "PlaceOrder", actor = 0, to = "sell", item = if stack then stack.id else 0,
    quantity = quantity, price = sellAt }
  if Im.Button("Place sell order", dx + 190, line, 256, 26, stack ~= nil and Session.CanDo(session, sellOrder), "PlaceSell") then
    Session.Do(session, sellOrder)
  end
  line += 28
  Im.Text(if sellAt <= quote.sellAt then `fills at once, at the pace of the station's customers`
    else `waits: customers pay up to {Format.Whole(bestSell)} now`, dx + 80, line, 12, if sellAt <= quote.sellAt then GOOD else Im.DIM)
  line += 24
  local bestBuy = if quote.buyAt then math.ceil(quote.buyAt) else math.ceil(quote.bid)
  local buyAt = if buyPrice > 0 then buyPrice else bestBuy
  Im.Text("Buy at", dx, line + 5, 14, Im.DIM)
  local enteredBuy = Im.Number("BuyPrice", buyAt, dx + 80, line, 100, 26)
  if enteredBuy ~= buyAt then
    buyPrice = enteredBuy
    buyAt = enteredBuy
  end
  local buyOrder: State.Command = { kind = "PlaceOrder", actor = 0, to = "buy", type = chosen, quantity = quantity, price = buyAt }
  if Im.Button("Place buy order", dx + 190, line, 256, 26, (Session.CanDo(session, buyOrder)), "PlaceBuy") then
    Session.Do(session, buyOrder)
  end
  line += 28
  local fillsNow = quote.buyAt ~= nil and buyAt >= quote.buyAt
  Im.Text(if fillsNow then `fills at once, at the pace of the station's customers`
    else `waits: sellers take {Format.Whole(bestBuy)} or more now`, dx + 80, line, 12, if fillsNow then GOOD else Im.DIM)
  line += 30

  -- What has traded here lately.
  Im.Heading("TRADED HERE", dx, line, 14, Im.DIM)
  line += 24
  local history = Core.Query.History(game, station, chosen)
  if #history == 0 then
    Im.Text("nothing yet", dx, line, 13, Im.DIM, 0.7)
  end
  for index = #history, math.max(1, #history - 2), -1 do
    local day = history[index]
    Im.Text(`day {day.day + 1}`, dx, line, 13, Im.DIM)
    Im.Text(`{Format.Whole(day.volume)} units`, dx + 80, line, 13, Im.TEXT)
    Im.TextRight(`average {Format.Price(day.value / math.max(1, day.volume))}`, dx + 446, line, 13, Im.TEXT)
    line += 20
  end
end

-- ---------------------------------------------------------------------
-- Industry

local function drawIndustry(session: Session.Session, game: Core.Game, player: Core.PlayerInfo, x: number, y: number)
  local station = player.docked
  local top = y + 78
  local left = x + 16
  local hangar = Core.Query.Items(game, station, "hangar")

  -- Blueprints here.
  local blueprints: { State.Item } = {}
  local ores: { State.Item } = {}
  for _, item in hangar do
    if Blueprints.byId[item.type] then
      table.insert(blueprints, item)
    elseif Ores.byId[item.type] then
      table.insert(ores, item)
    end
  end
  Im.Heading(`BLUEPRINTS HERE  {#blueprints}`, left, top, 16, Im.DIM)
  local line = top + 26
  if #blueprints == 0 then
    Im.Text("None. The market sells them, under Blueprints.", left, line, 14, Im.DIM, 0.8)
  end
  local visible = 9
  local first = Im.Scroll("blueprints", left - 4, line, 434, visible * 24, #blueprints, visible)
  for row = 1, visible do
    local item = blueprints[row + first]
    if item == nil then
      break
    end
    local blueprint = Blueprints.byId[item.type]
    local rowY = line + (row - 1) * 24
    local _, clicked = Im.Row(left - 4, rowY, 430, 24, blueprintChosen == item.type)
    Im.Text(shorten(Types.Info(blueprint.product).name, 34), left + 4, rowY + 4, 14, Im.TEXT)
    Im.TextRight(`makes {blueprint.perRun} a run`, left + 418, rowY + 5, 12, Im.DIM)
    if clicked then
      blueprintChosen = item.type
      runs = 1
    end
  end

  -- Ore to refine.
  line = top + 26 + visible * 24 + 16
  Im.Heading(`ORE HERE  {#ores}`, left, line, 16, Im.DIM)
  line += 26
  if #ores == 0 then
    Im.Text("None. Mine some at a belt and bring it back.", left, line, 14, Im.DIM, 0.8)
  end
  for index, item in ores do
    if index > 5 then
      break
    end
    Im.Text(`{Types.Info(item.type).name}  x{Format.Whole(item.quantity)}`, left + 4, line + 3, 14, Im.TEXT)
    local can = Session.CanDo(session, { kind = "Reprocess", actor = 0, item = item.id })
    if Im.Button("Refine", left + 348, line, 70, 22, can, `Refine:{item.type}`) then
      Session.Do(session, { kind = "Reprocess", actor = 0, item = item.id })
    end
    line += 26
  end

  -- The job the chosen blueprint would be.
  local dx = x + 470
  line = top
  local chosenItem = inHangar(game, station, blueprintChosen)
  local plan = if chosenItem then Core.Query.JobPlan(game, station, blueprintChosen, math.max(1, runs)) else nil
  if plan == nil or chosenItem == nil then
    Im.Heading("NEW JOB", dx, line, 16, Im.DIM)
    Im.Text("Choose a blueprint.", dx, line + 28, 14, Im.DIM, 0.8)
    line += 200
  else
    local product = Types.Info(plan.blueprint.product)
    Im.Heading("NEW JOB", dx, line, 16, Im.DIM)
    line += 26
    Im.Text("Runs", dx, line + 5, 14, Im.DIM)
    runs = Im.Number("Runs", runs, dx + 80, line, 100, 26)
    -- as many runs as the minerals here allow
    local most = 100
    for _, m in plan.blueprint.materials do
      local _, have = inHangar(game, station, m.type)
      most = math.min(most, have // m.quantity)
    end
    for index, preset in { 1, 10 } do
      if Im.Button(tostring(preset), dx + 190 + (index - 1) * 52, line, 48, 26, true, `Runs:{preset}`) then
        runs = preset
      end
    end
    if Im.Button(`Most ({most})`, dx + 294, line, 100, 26, most >= 1, "Runs:most") then
      runs = most
    end
    line += 36
    Im.Text(`Makes {Format.Whole(plan.quantity)} x {product.name}`, dx, line, 14, Im.TEXT)
    line += 24
    for _, m in plan.materials do
      local enough = m.have >= m.need
      Im.Text(Types.Info(m.type).name, dx + 12, line, 14, Im.DIM)
      Im.TextRight(Format.Whole(m.need), dx + 240, line, 14, if enough then Im.TEXT else Im.WARN)
      Im.TextRight(`{Format.Whole(m.have)} here`, dx + 446, line, 13, if enough then Im.DIM else Im.WARN)
      line += 20
    end
    line += 6
    Im.Text(`Takes {Format.Duration(plan.seconds)}`, dx, line, 14, Im.TEXT)
    Im.TextRight(`fee {Format.Credits(plan.fee)}`, dx + 446, line, 14, Im.TEXT)
    line += 28
    local job: State.Command = { kind = "StartJob", actor = 0, item = chosenItem.id, quantity = runs }
    local can, whyNot = Session.CanDo(session, job)
    if Im.Button("Start job", dx, line, 160, 30, can, "StartJob") then
      Session.Do(session, job)
    end
    if not can then
      Im.Text(tostring(whyNot), dx + 172, line + 8, 13, Im.WARN)
    end
    line += 40
    -- Research, in a laboratory: what the pilot has learned of this
    -- design, and the next level of each kind.
    local research = Core.Query.Research(game, plan.blueprint.id)
    if research then
      Im.Text(`Researched: materials -{research.material}%, time -{research.time * 2}%`, dx, line, 13, Im.DIM)
      line += 22
      for index, what in { "material", "time" } do
        local next: Industry.ResearchPlan? = if what == "material" then research.nextMaterial else research.nextTime
        local study: State.Command = { kind = "StartResearch", actor = 0, item = chosenItem.id, what = what }
        local canStudy = next ~= nil and (Session.CanDo(session, study))
        local bx = dx + (index - 1) * 226
        if Im.Button(if what == "material" then "Research materials" else "Research time", bx, line, 150, 26, canStudy,
          `Research:{what}`) then
          Session.Do(session, study)
        end
        Im.Text(if next then `{Format.Duration(next.seconds)}` else "done", bx + 156, line - 1, 12, Im.DIM)
        if next then
          Im.Text(Format.Credits(next.fee), bx + 156, line + 13, 12, Im.DIM)
        end
      end
      line += 34
      -- (and the inventing of its tech 2 make, where there is one)
      local invention = research.invention
      if invention then
        local invent: State.Command = { kind = "StartResearch", actor = 0, item = chosenItem.id, what = "invent" }
        local canInvent, whyNotInvent = Session.CanDo(session, invent)
        if Im.Button("Invent tech 2", dx, line, 150, 26, canInvent, "Invent") then
          Session.Do(session, invent)
        end
        Im.Text(string.format("%d datacores, %s, %d%% chance", invention.datacores, Format.Duration(invention.seconds),
          math.floor(invention.chance * 100 + 0.5)), dx + 156, line - 1, 12, Im.DIM)
        Im.Text(if canInvent then Format.Credits(invention.fee) else shorten(tostring(whyNotInvent), 44), dx + 156, line + 13, 12,
          if canInvent then Im.DIM else Im.WARN)
        line += 34
      end
    end
  end

  -- Jobs running, here and elsewhere.
  local jobs = Core.Query.Jobs(game, nil)
  line = math.max(line, top + 250)
  Im.Heading(`JOBS  {#jobs} / {Core.Query.JobSlots(game)}`, dx, line, 16, Im.DIM)
  line += 26
  if #jobs == 0 then
    Im.Text("Nothing is being built.", dx, line, 14, Im.DIM, 0.8)
  end
  for index, job in jobs do
    if index > 6 then
      break
    end
    local where = Core.Query.Body(game, job.station)
    local remaining = job.ends - game.state.tick
    Im.Text(if job.research ~= "" then `Research ({job.research}): {shorten(Types.Info(job.blueprint).name, 22)}`
      else `{Format.Whole(job.quantity)} x {shorten(Types.Info(job.product).name, 26)}`, dx, line, 14, Im.TEXT)
    Im.TextRight(Format.Duration(remaining * Constants.TICK), dx + 446, line, 14, Im.TEXT)
    line += 18
    Im.Text(if job.station == station then "here" else shorten(if where then where.name else "?", 30), dx, line, 12, Im.DIM)
    local span = math.max(1, job.ends - job.started)
    Im.Fill(dx + 150, line + 5, 296, 4, Im.DIM, 0.25)
    Im.Fill(dx + 150, line + 5, 296 * math.clamp(1 - remaining / span, 0, 1), 4, Im.ACCENT, 0.95)
    line += 24
  end
end

-- ---------------------------------------------------------------------
-- Skills

local function drawSkills(session: Session.Session, game: Core.Game, player: Core.PlayerInfo, x: number, y: number)
  local station = player.docked
  local top = y + 78
  local left = x + 16
  local skills = Core.Query.Skills(game)
  local known = 0
  for _, info in skills do
    if info.level >= 0 then
      known += 1
    end
  end
  Im.Heading(`SKILLS  {known} of {#skills}`, left, top, 16, Im.DIM)
  local rowHeight = 23
  local visible = 19
  local line = top + 26
  local first = Im.Scroll("skills", left - 4, line, 600, visible * rowHeight, #skills, visible)
  for row = 1, visible do
    local info = skills[row + first]
    if info == nil then
      break
    end
    local skill = info.skill
    local rowY = line + (row - 1) * rowHeight
    Im.Row(left - 4, rowY, 596, rowHeight, false)
    Im.Text(skill.name, left, rowY + 4, 14, if info.level >= 0 then Im.TEXT else Im.DIM)
    for level = 1, Skills.MAX_LEVEL do
      local px = left + 178 + (level - 1) * 13
      if level <= info.level then
        Im.Fill(px, rowY + 7, 10, 10, Im.ACCENT, 0.95)
      elseif level <= info.queued then
        Im.Fill(px, rowY + 7, 10, 10, Im.ACCENT, 0.4)
      else
        Im.Fill(px, rowY + 7, 10, 10, Im.DIM, 0.25)
      end
    end
    Im.Text(shorten(skill.note, 37), left + 252, rowY + 5, 12, Im.DIM)
    local bx = left + 504
    if info.level < 0 then
      local book = inHangar(game, station, Skills.Book(skill.id))
      if book then
        local can = Session.CanDo(session, { kind = "LearnSkill", actor = 0, item = book.id })
        if Im.Button("Learn", bx, rowY + 1, 84, 21, can, `Learn:{skill.id}`) then
          Session.Do(session, { kind = "LearnSkill", actor = 0, item = book.id })
        end
      elseif Im.Button("Buy book", bx, rowY + 1, 84, 21, true, `Book:{skill.id}`) then
        Station.Choose(Skills.Book(skill.id))
      end
    elseif info.queued < Skills.MAX_LEVEL then
      local can = Session.CanDo(session, { kind = "TrainSkill", actor = 0, type = skill.id })
      if Im.Button(`Train {info.queued + 1}`, bx, rowY + 1, 84, 21, can, `Train:{skill.id}`) then
        Session.Do(session, { kind = "TrainSkill", actor = 0, type = skill.id })
      end
    else
      Im.Text(if info.level >= Skills.MAX_LEVEL then "mastered" else "queued", bx + 14, rowY + 5, 12, Im.DIM)
    end
  end

  -- The queue.
  local dx = x + 628
  local queue = Core.Query.Training(game)
  Im.Heading(`TRAINING  {#queue} / {Skills.QUEUE_LENGTH}`, dx, top, 16, Im.DIM)
  line = top + 26
  if #queue == 0 then
    Im.Text("Nothing is training.", dx, line, 14, Im.WARN)
    Im.Text("Training goes on while you fly.", dx, line + 20, 12, Im.DIM)
  end
  for index, entry in queue do
    Im.Text(`{shorten(Skills.byId[entry.skill].name, 20)} {entry.level}`, dx, line + 2, 14, if index == 1 then Im.TEXT else Im.DIM)
    Im.TextRight(Format.Duration(entry.left), dx + 262, line + 2, 13, if index == 1 then Im.TEXT else Im.DIM)
    if Im.Button("x", dx + 272, line, 24, 20, true, `CancelTraining:{index}`) then
      Session.Do(session, { kind = "CancelTraining", actor = 0, quantity = index })
    end
    line += 22
    if index == 1 then
      Im.Fill(dx, line, 262, 4, Im.DIM, 0.25)
      Im.Fill(dx, line, 262 * math.clamp(1 - entry.left / math.max(1, entry.seconds), 0, 1), 4, Im.ACCENT, 0.95)
      line += 12
    end
  end

  -- The pilot's implants: the five places, and what in the hangar could
  -- go into one. (Under the queue at its longest.)
  local places, open = Core.Query.Implants(game)
  line = top + 266
  Im.Heading("IMPLANTS", dx, line, 14, Im.DIM)
  line += 22
  for slot, place in places do
    local implant = place.implant
    Im.Text(`{slot}`, dx, line + 2, 12, Im.DIM)
    if implant then
      Info.Name(implant.id, shorten(implant.name, 24), dx + 16, line + 2, 13, Im.TEXT)
      Im.Text(shorten(implant.note, 20), dx + 16 + 150, line + 3, 11, Im.DIM)
      if Im.Button("x", dx + 272, line, 24, 18, true, `Unplug:{slot}`) then
        Session.Do(session, { kind = "UnplugImplant", actor = 0, what = implant.id })
      end
    else
      Im.Text(if slot <= open then "empty" else `needs Cybernetics {slot}`, dx + 16, line + 2, 12, Im.DIM, 0.8)
    end
    line += 20
  end
  local shown = 0
  for _, item in Core.Query.Items(game, player.docked, "hangar") do
    if Types.Info(item.type).category == "implant" and shown < 2 then
      shown += 1
      line += 4
      local plug: State.Command = { kind = "PlugImplant", actor = 0, item = item.id }
      local can, whyNot = Session.CanDo(session, plug)
      if Im.Button("Plug in", dx, line, 70, 20, can, `Plug:{item.type}`) then
        Session.Do(session, plug)
      end
      Im.Text(shorten(if can then Types.Info(item.type).name else tostring(whyNot), 32), dx + 78, line + 3, 12,
        if can then Im.TEXT else Im.WARN)
      line += 20
    end
  end
end

-- ---------------------------------------------------------------------
-- Ships

local function drawShips(session: Session.Session, game: Core.Game, player: Core.PlayerInfo, x: number, y: number)
  local station = player.docked
  local top = y + 78
  local left = x + 16
  local ships = Core.Query.Ships(game, station)
  Im.Heading(`YOUR SHIPS HERE  {#ships}`, left, top, 16, Im.DIM)
  local line = top + 28
  for index, ship in ships do
    if index > 8 then
      Im.Text(`and {#ships - 8} more`, left, line, 13, Im.DIM)
      line += 26
      break
    end
    local hull = Ships.byId[ship.type]
    local aboard = ship.id == player.ship
    Im.Text(ship.name, left, line + 4, 15, Im.TEXT)
    ItemIcon.Draw(hull.id, left + 192, line + 2, 20)
    Info.Name(hull.id, hull.name, left + 220, line + 5, 13, Im.DIM)
    Im.Text(`{#Core.Query.Fitted(game, ship.id)} modules fitted`, left + 420, line + 5, 13, Im.DIM)
    if aboard then
      Im.Text("you are aboard", left + 620, line + 5, 13, GOOD)
    else
      local board: State.Command = { kind = "BoardShip", actor = 0, target = ship.id }
      local can, whyNot = Session.CanDo(session, board)
      if Im.Button("Board", left + 620, line, 90, 26, can, `Board:{index}`) then
        Session.Do(session, board)
      end
      if not can then
        Im.Text(tostring(whyNot), left + 722, line + 6, 13, Im.WARN)
      end
    end
    line += 32
  end

  line += 16
  Im.Heading("HULLS IN THE HANGAR", left, line, 16, Im.DIM)
  line += 28
  local any = false
  for _, item in Core.Query.Items(game, station, "hangar") do
    local hull = Ships.byId[item.type]
    if hull then
      any = true
      Im.Text(`{hull.name}  x{item.quantity}`, left, line + 4, 15, Im.TEXT)
      local untrained = Core.Query.Untrained(game, item.type)
      if untrained then
        Im.Text(`to fly it: {untrained}`, left + 420, line + 5, 13, Im.WARN)
      end
      if Im.Button("Assemble", left + 620, line, 90, 26, (Session.CanDo(session, { kind = "Assemble", actor = 0, item = item.id })),
        `Assemble:{item.type}`) then
        Session.Do(session, { kind = "Assemble", actor = 0, item = item.id })
      end
      line += 32
    end
  end
  if not any then
    Im.Text("None. The market sells hulls, under Ships; a bought hull is assembled here.", left, line, 14, Im.DIM, 0.8)
  end
end

-- ---------------------------------------------------------------------
-- Crew: pilots to hire, and the pilots hired (Core/Tactical/Fleet)

-- What a pilot docked here would be set to carry, and where to: which
-- of the kinds, and which of the places, by the pilot's id.
local haulWhat: { [number]: number } = {}
local haulTo: { [number]: number } = {}
local CARGO: { [string]: string } = { ore = "ore", mineral = "minerals", planetary = "planetary", component = "components", all = "all goods" }

local function drawCrew(session: Session.Session, game: Core.Game, player: Core.PlayerInfo, x: number, y: number)
  local station = player.docked
  local left, right = x + 16, x + 400
  local line = y + 78
  local candidates, most = Core.Query.Candidates(game, station)
  local fleet = Core.Query.Fleet(game)

  Im.Heading("LOOKING FOR WORK HERE", left, line, 16, Im.DIM)
  line += 30
  if #candidates == 0 then
    Im.Text("Nobody more today.", left, line, 14, Im.DIM, 0.8)
  end
  for index, found in candidates do
    Im.Text(found.name, left, line, 15, Im.TEXT)
    Im.TextRight(`grade {found.skill}`, left + 350, line, 15, Im.ACCENT)
    Im.Text(`{Format.Credits(found.wage)} a day`, left, line + 21, 12, Im.DIM)
    Im.TextRight(`{Format.Credits(found.fee)} to sign`, left + 350, line + 21, 12, Im.DIM)
    local hire: State.Command = { kind = "HirePilot", actor = 0, what = found.key }
    local can, whyNot = Session.CanDo(session, hire)
    if Im.Button("Hire", left, line + 42, 90, 24, can, `Hire:{index}`) then
      Session.Do(session, hire)
    end
    if not can then
      Im.Text(shorten(tostring(whyNot), 38), left + 100, line + 46, 12, Im.WARN)
    end
    line += 84
  end
  line = y + 78 + 30 + 3 * 84 + 4
  Im.Heading("WHAT A PILOT IS", left, line, 14, Im.DIM)
  for index, text in { "A hired pilot flies a ship of yours and goes where you go:", "out when you undock, to warp and through gates after you,",
    "into a fight beside you. Every skill counts as their grade.", "Grade 1 flies frigates and haulers, 2 destroyers and barges,",
    "3 cruisers, 4 battleships. You command one for each level", "of Leadership. A ship lost is insured; its pilot is not lost.",
    "One with a mining laser can be set to mine a belt (Mine here,", "in space); one docked here to haul what is in your hangar to",
    "another station; and any to sell what they bring in. They", "learn by all of it, and go up a grade, to 5 at most." } do
    Im.Text(text, left, line + 6 + index * 17, 12, Im.DIM)
  end

  -- The pilots hired, and for each the ships here they could be given.
  local free: { State.Ship } = {}
  for _, ship in Core.Query.Ships(game, station) do
    if ship.id ~= player.ship and ship.pilot == 0 and Ships.byId[ship.type].class ~= "capsule" then
      table.insert(free, ship)
    end
  end
  line = y + 78
  Im.Heading(`YOUR PILOTS  {#fleet} / {most}`, right, line, 16, Im.DIM)
  line += 30
  if #fleet == 0 then
    Im.Text("Nobody is hired.", right, line, 14, Im.DIM, 0.8)
  end
  for index, row in fleet do
    if index > 5 then
      break
    end
    Im.Text(row.name, right, line, 15, Im.TEXT)
    -- (their grade, and how far they are toward the next)
    Im.Text(if row.needed > 0 then `grade {row.skill}  {row.experience} / {row.needed}` else `grade {row.skill}`, right + 210, line + 1,
      13, Im.ACCENT)
    Im.TextRight(`{Format.Credits(row.wage)} a day`, right + 520, line + 1, 13, Im.DIM)
    local reason: string? = nil
    local note = ""
    local here = false
    if row.ship ~= 0 then
      ItemIcon.Draw(row.hull, right, line + 20, 18)
      local ship = game.state.ships[row.ship]
      here = ship ~= nil and ship.docked == station
      local where = if here then "docked here" else row.where
      if row.order == "mine" then
        where = `{row.doing}: {row.hauled} units of ore brought in`
      elseif row.order == "haul" then
        where = row.doing
        note = `Hauling {CARGO[row.cargo] or row.cargo} to {row.to}: {row.hauled} units`
      elseif row.order == "stay" then
        where ..= ", told to stay"
      end
      if row.earned > 0 then
        note = if note ~= "" then `{note}, sold for {Format.Credits(row.earned)}` else `What they brought in has sold for {Format.Credits(row.earned)}`
      end
      Im.Text(shorten(`{row.shipName} ({Ships.byId[row.hull].name}), {where}`, 58), right + 24, line + 22, 12, Im.DIM)
    else
      Im.Text("No ship: give them one of yours that is docked here.", right, line + 22, 12, Im.WARN)
    end
    if row.ship == 0 then
      -- (the ships here they could have: the first three)
      local bx = right
      for at, ship in free do
        if at > 3 then
          break
        end
        local give: State.Command = { kind = "AssignShip", actor = 0, pilot = row.id, target = ship.id }
        local can, whyNot = Session.CanDo(session, give)
        if Im.Button(shorten(`Give {ship.name}`, 16), bx, line + 42, 124, 24, can, `Give:{index}:{at}`) then
          Session.Do(session, give)
        end
        reason = reason or (if can then nil else whyNot)
        bx += 128
      end
      if #free == 0 then
        Im.Text("No ship of yours is free here (Ships tab).", right, line + 46, 12, Im.DIM)
      end
    elseif here then
      -- Docked here: what in the hangar they are to carry, and where to.
      local targets = Core.Query.HaulTargets(game, row.id, if session.destination ~= 0 then session.destination else nil)
      local what = math.clamp(haulWhat[row.id] or 1, 1, #Fleet.CARGO)
      local to = math.clamp(haulTo[row.id] or 1, 1, math.max(1, #targets))
      local kind = Fleet.CARGO[what]
      if Im.Button(`Carry {CARGO[kind]}`, right, line + 42, 112, 24, true, `Haul:what:{index}`) then
        haulWhat[row.id] = what % #Fleet.CARGO + 1
      end
      local target = targets[to]
      if Im.Button(if target then shorten(`to {target.name}`, 24) else "nowhere to carry to", right + 116, line + 42, 172, 24, #targets > 1,
        `Haul:to:{index}`) then
        haulTo[row.id] = to % #targets + 1
      end
      local haul: State.Command = { kind = "FleetOrder", actor = 0, what = "haul", pilot = row.id, target = if target then target.id else 0,
        type = kind }
      local can, whyNot = Session.CanDo(session, haul)
      if Im.Button("Haul", right + 292, line + 42, 48, 24, can, `Haul:go:{index}`) then
        Session.Do(session, haul)
      end
      reason = if can then nil else whyNot
      if target and row.order ~= "haul" then
        note = `{target.name}: ` .. (if target.jumps == 0 then "in this system" elseif target.jumps == 1 then `1 jump, in {target.system}`
          else `{target.jumps} jumps, in {target.system}`) .. (if target.market then ", has a market" else ", no market")
      end
    else
      -- Out flying: called back, they come to where you are.
      local recall: State.Command = { kind = "FleetOrder", actor = 0, what = "follow", pilot = row.id }
      if Im.Button("Recall", right, line + 42, 90, 24, row.order ~= "follow" and (Session.CanDo(session, recall)), `Recall:{index}`) then
        Session.Do(session, recall)
      end
    end
    if row.ship ~= 0 then
      -- (what they bring in, mined or carried, is sold where there is a market)
      local sell: State.Command = { kind = "FleetOrder", actor = 0, what = if row.sells then "keep" else "sell", pilot = row.id }
      if Im.Toggle("Sell", right + 344, line + 42, 40, 24, row.sells, `Sells:{index}`) then
        Session.Do(session, sell)
      end
    end
    local off: State.Command = { kind = "AssignShip", actor = 0, pilot = row.id, target = 0 }
    if row.ship ~= 0 and Im.Button("Take off", right + 388, line + 42, 64, 24, (Session.CanDo(session, off)), `TakeOff:{index}`) then
      Session.Do(session, off)
    end
    local dismiss: State.Command = { kind = "DismissPilot", actor = 0, pilot = row.id }
    if Im.Button("Dismiss", right + 456, line + 42, 64, 24, (Session.CanDo(session, dismiss)), `Dismiss:{index}`) then
      Session.Do(session, dismiss)
    end
    if reason then
      Im.Text(shorten(reason, 70), right, line + 69, 12, Im.WARN)
    elseif note ~= "" then
      Im.Text(shorten(note, 84), right, line + 69, 12, Im.DIM)
    end
    line += 90
  end
end

-- ---------------------------------------------------------------------
-- Missions: the jobs a station has, and the jobs in hand

-- (Whether the left of it shows the faction's loyalty store in place of
-- the jobs offered.)
local storeOpen = false

local function drawMissions(session: Session.Session, game: Core.Game, x: number, y: number)
  local status = Core.Query.Missions(game)
  local left, right = x + 16, x + 480
  local line = y + 78
  local function about(mission: State.Mission): string
    if mission.kind == "bounty" then
      local _, band = Core.Query.Security(game, mission.system)
      return `in {game.state.galaxy.systems[mission.system].name} ({band or "?"} space): {mission.done} of {mission.need} destroyed`
    elseif mission.kind == "courier" then
      local to = Core.Query.Body(game, mission.to)
      return `to {if to then shorten(to.name, 40) else "?"}`
    end
    local at = Core.Query.Body(game, mission.station)
    return `to {if at then shorten(at.name, 40) else "?"}`
  end

  Im.Heading(if storeOpen then "LOYALTY STORE" else "JOBS OFFERED HERE", left, line, 16, Im.DIM)
  if status.faction ~= "" then
    Im.TextRight(string.format("%s standing  %.1f", status.faction, status.standing), left + 430, line + 2, 13,
      if status.standing < 0 then Im.WARN else Im.TEXT)
  end
  line += 30
  -- The store: what the faction lets a pilot have for loyalty points.
  if storeOpen then
    if #status.store == 0 then
      Im.Text("There is no store here.", left, line, 14, Im.DIM, 0.8)
    end
    for index, row in status.store do
      if index > 20 then
        break
      end
      Info.Name(row.stock.type, shorten(row.name, 30), left, line + 1, 13, if row.can then Im.TEXT else Im.DIM)
      if row.can or string.sub(row.why, 1, 5) ~= "needs" then
        Im.TextRight(`{row.stock.points} LP` .. (if row.stock.credits > 0 then `  {Format.Credits(row.stock.credits)}` else ""),
          left + 372, line + 2, 12, Im.DIM)
      else
        Im.TextRight(shorten(row.why, 36), left + 372, line + 2, 11, Im.WARN)
      end
      if Im.Button("Get", left + 380, line, 50, 18, row.can, `Redeem:{row.stock.type}`) then
        Session.Do(session, { kind = "RedeemLoyalty", actor = 0, type = row.stock.type, quantity = 1 })
      end
      line += 20
    end
  elseif #status.offers == 0 then
    Im.Text("Nothing more today.", left, line, 14, Im.DIM, 0.8)
  end
  local offers: { Core.MissionStatus } = if storeOpen then {} else status.offers
  for index, offer in offers do
    Im.Text(offer.title, left, line, 15, Im.TEXT)
    Im.TextRight(Format.Credits(offer.mission.reward), left + 430, line, 15, GOOD)
    Im.Text(about(offer.mission), left, line + 21, 12, Im.DIM)
    Im.TextRight(`{offer.mission.agent}  +{offer.mission.loyalty} LP`, left + 430, line + 21, 12, Im.DIM)
    local accept: State.Command = { kind = "AcceptMission", actor = 0, what = offer.mission.key }
    local can, whyNot = Session.CanDo(session, accept)
    if Im.Button("Accept", left, line + 42, 90, 24, can, `Accept:{index}`) then
      Session.Do(session, accept)
    end
    if not can then
      Im.Text(tostring(whyNot), left + 100, line + 46, 12, Im.WARN)
    end
    line += 84
  end

  -- What every faction thinks of the pilot (it is their stations' fees,
  -- their jobs' pay and, at the worst, their patrols' guns).
  if not storeOpen then
    line = y + 78 + 30 + 3 * 84 + 4
    Im.Heading("STANDINGS", left, line, 14, Im.DIM)
    for index, row in Core.Query.Standings(game) do
      local sx = left + (index - 1) * 110
      Im.Text(row.name, sx, line + 24, 13, Im.DIM)
      Im.Text(string.format("%.1f", row.standing), sx, line + 42, 15, if row.hostile then HOSTILE elseif row.standing < 0 then Im.WARN else Im.TEXT)
      if row.hostile then
        Im.Text("hostile", sx + 44, line + 44, 12, HOSTILE)
      end
    end
  end
  -- (the store, and the way back from it: at the foot of the column)
  -- (under the standings; under the store's list when that is open)
  if Im.Toggle(if storeOpen then `Back to the jobs  ({status.loyalty} points)` else `Loyalty store: {status.loyalty} points`, left,
    y + (if storeOpen then 516 else 78 + 30 + 3 * 84 + 78), 250, 26, storeOpen, "LoyaltyStore") then
    storeOpen = not storeOpen
  end

  line = y + 78
  Im.Heading(`IN HAND  {#status.inHand} / 5`, right, line, 16, Im.DIM)
  Im.TextRight(`{status.done} done`, right + 430, line + 2, 13, Im.DIM)
  line += 30
  if #status.inHand == 0 then
    Im.Text("No jobs in hand.", right, line, 14, Im.DIM, 0.8)
  end
  for index, held in status.inHand do
    Im.Text(held.title, right, line, 15, Im.TEXT)
    Im.TextRight(Format.Credits(held.mission.reward), right + 430, line, 15, GOOD)
    Im.Text(about(held.mission), right, line + 21, 12, Im.DIM)
    -- (how long it can still be kept: in the colour of a warning at the last)
    Im.TextRight(Format.Duration(held.left), right + 430, line + 21, 12, if held.left < 6 * 3600 then Im.WARN else Im.DIM)
    local complete: State.Command = { kind = "CompleteMission", actor = 0, target = held.mission.id }
    if Im.Button("Complete", right, line + 42, 90, 24, held.ready, `Complete:{index}`) then
      Session.Do(session, complete)
    end
    if not held.ready then
      Im.Text(shorten(held.why, 34), right + 100, line + 46, 12, Im.DIM)
    end
    if Im.Button("Abandon", right + 350, line + 42, 80, 24, true, `Abandon:{index}`) then
      Session.Do(session, { kind = "AbandonMission", actor = 0, target = held.mission.id })
    end
    line += 84
  end
end

-- ---------------------------------------------------------------------
-- Starbase: the running of a tower of the pilot's own

-- A bar of what is used of what there is, with the figures over it.
local function supply(label: string, used: number, capacity: number, unit: string, x: number, y: number, width: number)
  Im.Text(label, x, y, 13, Im.DIM)
  Im.TextRight(`{Format.Whole(used)} / {Format.Whole(capacity)} {unit}`, x + width, y, 13, Im.TEXT)
  Im.Fill(x, y + 20, width, 6, Im.DIM, 0.25)
  Im.Fill(x, y + 20, width * math.clamp(used / math.max(1, capacity), 0, 1), 6, if used > capacity * 0.9 then Im.WARN else Im.ACCENT, 0.95)
end

local function drawStarbase(session: Session.Session, game: Core.Game, player: Core.PlayerInfo, status: Core.StarbaseStatus,
  x: number, y: number)
  local station = player.docked
  local left = x + 16
  local line = y + 78
  local tower = status.tower

  -- The tower: its fuel, and what it supplies.
  Im.Heading("TOWER", left, line, 16, Im.DIM)
  line += 26
  ItemIcon.Draw(tower.id, left, line, 22)
  Info.Name(tower.id, tower.name, left + 30, line + 3, 15, Im.TEXT)
  line += 30
  if status.lit then
    Im.Text("Lit: its field is up and its modules have power.", left, line, 13, GOOD)
  else
    Im.Text("DARK: no fuel. Its field is down and its modules give nothing.", left, line, 13, Im.WARN)
  end
  line += 24
  Im.Text("Fuel", left, line, 13, Im.DIM)
  Im.TextRight(`{Format.Whole(status.fuel)} blocks`, left + 400, line, 13, if status.lit then Im.TEXT else Im.WARN)
  line += 20
  Im.Text(`It burns {tower.fuel} an hour`, left, line, 13, Im.DIM)
  Im.TextRight(if status.fuel > 0 then `{Format.Duration(status.hours * 3600)} left` else "none left", left + 400, line, 13,
    if status.hours >= 1 then Im.TEXT else Im.WARN)
  line += 30
  supply("Powergrid", status.powergrid, tower.powergrid, "MW", left, line, 400)
  line += 38
  supply("CPU", status.cpu, tower.cpu, "tf", left, line, 400)
  line += 46

  -- What is anchored round it.
  Im.Heading(`ANCHORED  {#status.modules}`, left, line, 16, Im.DIM)
  line += 26
  if #status.modules == 0 then
    Im.Text("Nothing yet. A module to hand is anchored from the list on the right.", left, line, 13, Im.DIM, 0.8)
  end
  local visible = 8
  local first = Im.Scroll("anchored", left - 4, line, 420, visible * 26, #status.modules, visible)
  for row = 1, visible do
    local module = status.modules[row + first]
    if module == nil then
      break
    end
    local type = Structures.moduleById[module.type]
    ItemIcon.Draw(type.id, left, line + 1, 20)
    Info.Name(type.id, shorten(type.name, 24), left + 26, line + 3, 13, Im.TEXT)
    if module.online then
      Im.Text("online", left + 214, line + 3, 13, GOOD)
    elseif module.wait > 0 then
      Im.Text(`online in {Format.Duration(module.wait)}`, left + 214, line + 3, 13, Im.DIM)
    else
      Im.Text("no power", left + 214, line + 3, 13, Im.WARN)
    end
    local unanchor: State.Command = { kind = "UnanchorModule", actor = 0, type = type.id }
    if Im.Button("Unanchor", left + 320, line, 80, 21, (Session.CanDo(session, unanchor)), `Unanchor:{type.id}`) then
      Session.Do(session, unanchor)
    end
    line += 26
  end

  -- What there is to hand, in the hold and in the tower's hangar, to
  -- burn or to anchor.
  local right = x + 480
  line = y + 78
  local hand: { { item: State.Item, where: string } } = {}
  for _, place in { "cargo", "hangar" } do
    for _, item in Core.Query.Items(game, if place == "cargo" then player.ship else station, place) do
      if item.type == Structures.FUEL.id or Structures.moduleById[item.type] then
        table.insert(hand, { item = item, where = if place == "cargo" then "hold" else "hangar" })
      end
    end
  end
  Im.Heading(`TO HAND  {#hand}`, right, line, 16, Im.DIM)
  line += 26
  if #hand == 0 then
    Im.Text("No fuel and no modules in the hold or the hangar.", right, line, 13, Im.DIM, 0.8)
    Im.Text("A market sells both, under Structures.", right, line + 20, 13, Im.DIM, 0.8)
  end
  local shown = 16
  local top = Im.Scroll("tohand", right - 4, line, 448, shown * 26, #hand, shown)
  for row = 1, shown do
    local entry = hand[row + top]
    if entry == nil then
      break
    end
    local item = entry.item
    local name = shorten(Types.Info(item.type).name, 22)
    ItemIcon.Draw(item.type, right, line + 1, 20)
    Info.Name(item.type, name, right + 26, line + 3, 13, Im.TEXT)
    Im.Text(`x{item.quantity}  {entry.where}`, right + 30 + Im.TextWidth(name, 13), line + 3, 12, Im.DIM)
    local fuel = item.type == Structures.FUEL.id
    local command: State.Command = { kind = if fuel then "Fuel" else "AnchorModule", actor = 0, item = item.id }
    local can, whyNot = Session.CanDo(session, command)
    if Im.Button(if fuel then "Fuel" else "Anchor", right + 250, line, 60, 21, can,
      if fuel then `Fuel:{entry.where}` else `Anchor:{item.type}`) then
      Session.Do(session, command)
    end
    if not can then
      Im.Text(shorten(tostring(whyNot), 20), right + 318, line + 3, 12, Im.WARN)
    end
    line += 26
  end
end

-- ---------------------------------------------------------------------
-- Wallet

local function drawWallet(game: Core.Game, x: number, y: number)
  local top = y + 78
  local left = x + 16
  local journal = Core.Query.Journal(game)
  Im.Heading("BALANCE", left, top, 16, Im.DIM)
  Im.Heading(Format.Credits(game.state.wallet), left + 110, top - 4, 22, Im.TEXT)
  local line = top + 40
  Im.Text("WHEN", left, line, 12, Im.DIM)
  Im.Text("WHAT", left + 150, line, 12, Im.DIM)
  Im.TextRight("AMOUNT", left + 600, line, 12, Im.DIM)
  Im.TextRight("BALANCE", left + 780, line, 12, Im.DIM)
  line += 20
  if #journal == 0 then
    Im.Text("Nothing has been paid or earned yet.", left, line, 14, Im.DIM, 0.8)
  end
  local visible = 18
  local first = Im.Scroll("journal", left - 4, line, 900, visible * 22, #journal, visible)
  for row = 1, visible do
    -- newest first
    local entry = journal[#journal - (row + first) + 1]
    if entry == nil then
      break
    end
    local rowY = line + (row - 1) * 22
    Im.Text(Format.Clock(entry.tick), left, rowY + 3, 13, Im.DIM)
    Im.Text(entry.reason, left + 150, rowY + 3, 14, Im.TEXT)
    Im.TextRight((if entry.amount >= 0 then "+" else "") .. Format.Whole(entry.amount), left + 600, rowY + 3, 14,
      if entry.amount >= 0 then GOOD else Im.WARN)
    Im.TextRight(Format.Whole(entry.balance), left + 780, rowY + 3, 14, Im.DIM)
  end
end

-- ---------------------------------------------------------------------

-- 'preview' is the player's ship as it is fitted, for the fitting
-- screen to show (Scene.Dressed).
function Station.Draw(session: Session.Session, game: Core.Game, player: Core.PlayerInfo, x: number, y: number,
  preview: Preview?)
  local width, height = Station.WIDTH, Station.HEIGHT
  local ship = player.ship
  local station = Core.Query.Body(game, player.docked)
  Im.Panel(x, y, width, height)
  Im.Heading("DOCKED", x + 16, y + 12, 16, Im.DIM)
  Im.Heading(if station then shorten(station.name, 32) else "?", x + 16, y + 36, 17, Im.TEXT)
  -- At a starbase of the pilot's own there is the running of it too,
  -- which is what the pilot has come for: it is open on arrival.
  local starbase = Core.Query.Starbase(game, player.docked)
  local own: Core.StarbaseStatus? = if starbase and starbase.mine then starbase else nil
  if player.docked ~= dockedAt then
    if own then
      tab = "Starbase"
    end
    dockedAt = player.docked
  end
  if tab == "Starbase" and own == nil then
    tab = "Fitting"
  end
  local tabs: { string } = if own then OWN else TABS
  local pitch = (width - 364 - 12) / #tabs
  for index, name in tabs do
    if Im.Toggle(name, x + 364 + (index - 1) * pitch, y + 18, pitch - 4, 28, tab == name) then
      tab = name
    end
  end
  -- What can be done here is what the station has a module for: say
  -- what the tab that is open wants and the station has not.
  local _, services = Core.Query.Station(game, player.docked)
  local has: { [string]: boolean } = {}
  for _, service in services do
    has[service] = true
  end
  local lacking: { string } = {}
  local wanted: { string } = WANTS[tab] or {}
  for _, service in wanted do
    if not has[service] then
      table.insert(lacking, Structures.Provider(service :: Structures.Service))
    end
  end
  if #lacking > 0 then
    Im.Text(`This station has no {table.concat(lacking, " and no ")}.`, x + 16, y + 58, 13, Im.WARN)
  end

  if tab == "Market" then
    drawMarket(session, game, player, x, y)
  elseif tab == "Industry" then
    drawIndustry(session, game, player, x, y)
  elseif tab == "Skills" then
    drawSkills(session, game, player, x, y)
  elseif tab == "Ships" then
    drawShips(session, game, player, x, y)
  elseif tab == "Wallet" then
    drawWallet(game, x, y)
  elseif tab == "Crew" then
    drawCrew(session, game, player, x, y)
  elseif tab == "Missions" then
    drawMissions(session, game, x, y)
  elseif tab == "Starbase" and own then
    drawStarbase(session, game, player, own, x, y)
  else
    drawFitting(session, game, player, x, y, preview)
  end

  -- What a pilot does here, whatever the tab.
  local bottom = y + height - 44
  if Im.Button("UNDOCK", x + 16, bottom, 120, 28, true) then
    Session.Order(session, "Undock")
  end
  local canRepair = Session.CanDo(session, { kind = "Repair", actor = 0 })
  local shipRecord = game.state.ships[ship]
  local damaged = shipRecord.armorDamage + shipRecord.hullDamage > 0
  local label = if damaged then `Repair  {Core.Query.RepairCost(game)} cr` else "No damage"
  if Im.Button(label, x + 146, bottom, 170, 28, canRepair, "Repair") then
    Session.Do(session, { kind = "Repair", actor = 0 })
  end
  local training = Core.Query.Training(game)
  if #training > 0 then
    local now = training[1]
    Im.Text(`Training {Skills.byId[now.skill].name} {now.level}: {Format.Duration(now.left)}`, x + 332, bottom + 7, 13, Im.DIM)
  else
    Im.Text("No skill in training", x + 332, bottom + 7, 13, Im.WARN)
  end
  if Im.Button("Save", x + width - 176, bottom, 76, 28, true) then
    Session.Save(session, "quick")
  end
  if Im.Button("Load", x + width - 92, bottom, 76, 28, true) then
    Session.Load(session, "quick")
  end
end

return Station
