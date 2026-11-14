--!strict
-- The interface while docked: the ship's fit, the market, industry,
-- skills, the ships kept here and the wallet, a tab each; and, at the
-- station a new pilot starts at, the career agents (Game/UI/Careers).
--
-- Drawn every frame with Game/UI/Im. It reads the Core through queries
-- and acts on it only through the Session. Every button has a name a
-- script can press it by (Im.Press): its label, or the id given here.

local Blueprints = require("@lt/Core/Data/Blueprints")
local Careers = require("@lt/Game/UI/Careers")
local Catalog = require("@lt/Core/Data/Catalog")
local Constants = require("@lt/Core/Data/Constants")
local Core = require("@lt/Core/Api")
local Fleet = require("@lt/Core/Tactical/Fleet")
local Chart = require("@lt/Game/UI/Chart")
local Format = require("@lt/Game/Format")
local Im = require("@lt/Game/UI/Im")
local Industry = require("@lt/Core/Assets/Industry")
local Info = require("@lt/Game/UI/Info")
local ItemIcon = require("@lt/Game/UI/ItemIcon")
local Modules = require("@lt/Core/Data/Modules")
local Ores = require("@lt/Core/Data/Ores")
local Reactions = require("@lt/Core/Data/Reactions")
local Session = require("@lt/Game/Session")
local Assault = require("@lt/Core/Tactical/Assault")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")
local State = require("@lt/Core/Kernel/State")
local Moons = require("@lt/Core/Data/Moons")
local Structures = require("@lt/Core/Data/Structures")
local Types = require("@lt/Core/Data/Types")

local Station = {}

Station.WIDTH = 940
Station.HEIGHT = 600

local TABS: { string } = { "Fitting", "Market", "Industry", "Skills", "Ships", "Crew", "Wallet", "Missions" }
-- (and one more at a starbase of the pilot's own: the running of it)
local OWN: { string } = { "Fitting", "Market", "Industry", "Skills", "Ships", "Crew", "Wallet", "Missions", "Starbase" }
-- (and at the station the career agents are at: them)
local SCHOOL: { string } = { "Fitting", "Market", "Industry", "Skills", "Ships", "Crew", "Wallet", "Missions", "Careers" }
-- The services each tab's doings are done by (Core/Assets/Stations).
local WANTS: { [string]: { string } } = {
  Fitting = { "fitting" }, Market = { "market" }, Industry = { "refining", "industry", "research" }, Ships = { "fitting" },
}
local tab = "Fitting"
local dockedAt = 0    -- the station the screen was last drawn for

-- The market: the category listed, the type shown, and what is entered.
local CATEGORIES: { { string } } = {
  { "module", "Modules" }, { "charge", "Charges" }, { "drone", "Drones" }, { "ship", "Ships" }, { "structure", "Structures" }, { "ore", "Ore" }, { "mineral", "Minerals" },
  { "moon", "Moon" }, { "planetary", "Planetary" }, { "component", "Components" },
  { "blueprint", "Blueprints" }, { "skillbook", "Skill books" }, { "implant", "Implants" }, { "goods", "Goods" },
}
local category = "module"
local chosen = ""
local quantity = 1
local sellPrice, buyPrice = 0, 0    -- 0: the best price that fills now
-- The side of the chosen type that is shown: "trade" (buying, selling
-- and orders) or "history" (its price day by day).
local marketPage = "trade"
-- How many days of a price are shown.
local HISTORY = 30

-- Where else the thing chosen is to be had (Core.Query.Sources): asked
-- again when what is asked changes and a couple of times a second, not
-- every frame.
local elsewhere = { key = "", age = 0, list = {} :: { Core.Source } }

-- The job whose "Call off" has been pressed once, and the frames it
-- stays asked for: a second press within them calls it off.
local calling = { job = 0, left = 0 }

-- How much over what a market asks now a pilot sent there may pay, a
-- unit, on the average of a purchase: prices move while they fly. And
-- one who is to keep a thing in stock from now on, more: prices move
-- further in a week than in an hour.
local LEEWAY = 1.1
local STANDING = 1.25

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
  for _, known in { OWN, SCHOOL } do
    if table.find(known, name) then
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
  -- (no market deals in a blueprint copy: there is nothing to open it at)
  if info == nil or info.unlisted then
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

-- The side of the market's chosen type that is shown: "trade" or
-- "history".
function Station.MarketPage(): string
  return marketPage
end

-- Open the industry tab at a blueprint, or at a copy of one, as
-- clicking its row would.
function Station.Blueprint(type: string): boolean
  if Blueprints.Of(type) == nil then
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
    -- (one that would take it: of its size, and tech 2 for a tech 2 charge)
    if weapon and weapon.family == family
      and (Core.Validate(game, { kind = "LoadCharge", actor = ship, item = item.id, other = charge.id })) then
      if item.charge == "" then
        return item
      elseif item.charge ~= charge.type and other == nil then
        other = item
      end
    end
  end
  return other
end

-- The fitting screen. In the middle is the ship,
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
export type Preview = { { model: Renderable | Model, transform: Transform, at: vector, look: vector, up: vector, size: number } }

-- ('show' draws the ship as it is in space, in a round window about a
-- point: Scene.Showcase. Where it cannot, 'preview' is drawn the old
-- way, as a hologram.)
export type Show = (cx: number, cy: number, round: number) -> boolean

local function drawWheel(session: Session.Session, game: Core.Game, player: Core.PlayerInfo, cx: number, cy: number,
  preview: Preview?, show: Show?)
  local ship = player.ship
  local hull = player.hull
  local stats = Core.Query.Stats(game, ship)
  local cpu, powergrid = Core.Query.FittingUse(game, ship)

  -- The ship, turning.
  WidgetRenderer_DrawPanelRadial(vector.create(cx, cy), 0, RING - 28, 0, 1, vector.create(0.02, 0.03, 0.045), 0.9, 0.9, 0)
  if show and show(cx, cy, RING - 30) then
    -- (the ship as it is in space: Scene.Showcase has drawn it)
  elseif preview and preview[1] then
    -- (A hull of no design of ours, which the scene cannot stand in
    -- space for the fitting screen: a hologram of it, as every hull was
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
    -- (a rack of many slots, as a dreadnought's twenty highs are, has
    -- them smaller: as wide as the arc has room for each)
    local size = math.max(14, math.min(SLOT, 2 * math.pi * RING * pitch * 0.94))
    local small = math.min(20, size * 0.72)
    -- (its name, inside the wheel at the start of its arc)
    local lx, ly = onWheel(cx, cy, RING - 4, middle - pitch * (count + 1) / 2 - 0.004)
    Im.Text(string.upper(label), lx - Im.TextWidth(string.upper(label), 10) / 2, ly - 6, 10, Im.DIM)
    for slot = 1, count do
      local turn = middle + (slot - (count + 1) / 2) * pitch
      local sx, sy = onWheel(cx, cy, RING, turn)
      local left, top = sx - size / 2, sy - size / 2
      local item = fitted[name][slot]
      if item then
        local module = Modules.byId[item.type]
        local hot, clicked = Im.Area(`Info:{item.type}`, left, top, size, size, true)
        ItemIcon.Draw(item.type, left, top, size)
        if hot then
          Im.Fill(left, top, size, size, Im.ACCENT, 0.18)
          hint = `{label} {slot}:  {module.name}`
        end
        if clicked then
          Info.Open(item.type)
        end
        -- what it is loaded with, inside the wheel
        if module.weapon then
          local ix, iy = onWheel(cx, cy, RING - 36, turn)
          if item.charge ~= "" then
            ItemIcon.Draw(item.charge, ix - small / 2, iy - small / 2, small)
            if hot or Im.Inside(ix - small / 2, iy - small / 2, small, small) then
              hint = `{label} {slot}:  {module.name},  {Types.Info(item.charge).name}`
                .. (if module.weapon.clip > 0 then ` x{item.rounds}` else "")
            end
          else
            WidgetRenderer_DrawPanel(vector.create(ix - small / 2, iy - small / 2), vector.create(small, small), Im.WARN, 0.15, 0.6, 3)
            if hot then
              hint ..= ",  nothing loaded"
            end
          end
        end
        -- taking it out: the corner away from the middle
        local ux, uy = onWheel(sx, sy, size * 0.62, turn)
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
        WidgetRenderer_DrawPanel(vector.create(left, top), vector.create(size, size), vector.create(0.22, 0.32, 0.42), 0.18, 0.75, 5)
        if Im.Inside(left, top, size, size) then
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
  preview: Preview?, show: Show?)
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
    elseif info.category == "ship" and Core.Query.ShipBay(game, ship) > 0 then
      -- (a packed hull goes in the ship bay of a hull that has one, a
      -- logistics capital: as many of the stack as there is room for)
      local size, used = Core.Query.ShipBay(game, ship)
      local room = math.floor((size - used + 1e-9) / info.volume)
      local toBay: State.Command = { kind = "MoveItems", actor = 0, item = item.id, to = "shipbay", quantity = math.min(item.quantity, room) }
      if Im.Button("Bay", left + 178, line, 46, 21, room >= 1 and (Session.CanDo(session, toBay)), `ToShipBay:{item.type}`) then
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
  -- (three lines of it; two on a hull with an ore hold, which has the
  -- third: below)
  local oreSize, oreUsed = Core.Query.OreHold(game, ship)
  -- (or its ship bay, on a hull that carries ships: it has the one or
  -- the other, and the same line of the panel)
  local baySize, bayUsed = Core.Query.ShipBay(game, ship)
  local second = oreSize > 0 or baySize > 0
  local shown = if second then 2 else 3
  for index, item in hold do
    if index > shown then
      Im.Text(`and {#hold - shown} more`, left + (if second then 150 else 0), line - (if second then 24 * shown + 22 else 0), 13,
        Im.DIM)
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

  -- The ore hold of a hull that has one (a capital industrial), on the
  -- hold's third line: how full it is, and a button that puts all of it
  -- in the hangar ("OreToHangar"), where it can be refined or sold.
  -- (What is in it, stack by stack, is on the assets window.)
  if oreSize > 0 then
    line = y + 78 + 24 + visible * 24 + 8 + 24 + 2 * 24
    Im.Heading(string.format("ORE HOLD  %s / %s m3", Format.Whole(math.floor(oreUsed + 0.5)), Format.Whole(oreSize)), left, line + 4, 13,
      Im.DIM)
    local stacks = Core.Query.Items(game, ship, "orehold")
    if Im.Button("To hangar", left + 200, line, 74, 21, #stacks > 0, "OreToHangar") then
      for _, item in stacks do
        Session.Do(session, { kind = "MoveItems", actor = 0, item = item.id, to = "hangar" })
      end
    end
  elseif baySize > 0 then
    -- The ship bay of a hull that has one (a logistics capital), on the
    -- same line: how full it is of packed hulls, and a button that puts
    -- them all in the hangar ("BayToHangar"). They go in from the
    -- hangar's list, a hull's "Bay" button.
    line = y + 78 + 24 + visible * 24 + 8 + 24 + 2 * 24
    Im.Heading(string.format("SHIP BAY  %s / %s m3", Format.Whole(math.floor(bayUsed + 0.5)), Format.Whole(baySize)), left, line + 4, 13,
      Im.DIM)
    local stacks = Core.Query.Items(game, ship, "shipbay")
    if Im.Button("To hangar", left + 200, line, 74, 21, #stacks > 0, "BayToHangar") then
      for _, item in stacks do
        Session.Do(session, { kind = "MoveItems", actor = 0, item = item.id, to = "hangar" })
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
  drawWheel(session, game, player, cx, cy, preview, show)

  drawFigures(game, player, x + 672, y + 76, 252)
end

-- ---------------------------------------------------------------------
-- Market

-- A price typed for an order and not yet set, by the order's id.
local repriced: { [number]: number } = {}

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
    if here then
      -- (an order here has its price in a field: another typed there,
      -- and Set, is its price from then on)
      local shown = repriced[order.id] or order.price
      local typed = Im.Number(`OrderPrice:{row + first}`, shown, x + 328, line, 92, 22)
      repriced[order.id] = if typed ~= order.price then typed else nil :: any
      local change: State.Command = { kind = "ModifyOrder", actor = 0, order = order.id, price = typed }
      if Im.Button("Set", x + 424, line, 40, 22, typed ~= order.price and (Session.CanDo(session, change)), `SetOrder:{row + first}`) then
        Session.Do(session, change)
        repriced[order.id] = nil
      end
      Im.Text("here", x + 474, line + 4, 12, Im.DIM)
    else
      Im.TextRight(`at {Format.Credits(order.price)}`, x + 420, line + 3, 14, Im.TEXT)
      Im.Text(shorten(if where then where.name else "?", 22), x + 436, line + 4, 12, Im.DIM)
    end
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
    Im.Text(shorten(untrained, 30), dx + 110, line, 13, Im.WARN)
  end
  -- (the two sides of a type: trading in it, and its price day by day)
  if Im.Toggle("Trade", dx + 314, line - 5, 64, 22, marketPage == "trade", "Market:trade") then
    marketPage = "trade"
  end
  if Im.Toggle("History", dx + 382, line - 5, 64, 22, marketPage == "history", "Market:history") then
    marketPage = "history"
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

  -- Its price here day by day, and what was traded in it: the going
  -- price each day closed at, today's being what it is now.
  local series = Core.Query.PriceHistory(game, station, chosen, HISTORY)
  local low, high = Chart.Range(series)
  local units, worth = Chart.Traded(series)
  local level = high - low < high * 0.002
  if marketPage == "history" then
    Im.Heading(`PRICE HERE, {#series} {if #series == 1 then "DAY" else "DAYS"}`, dx, line, 14, Im.DIM)
    local picked = Chart.Draw(series, dx, line + 24, 446, 170, 44, false)
    local day = series[picked or #series]
    -- (the day under the cursor, or today)
    local said = if picked and picked < #series then `day {day.day + 1} closed at {Format.Price(day.price)}` else `now {Format.Price(day.price)}`
    if day.volume > 0 then
      said ..= `, {Format.Whole(day.volume)} traded at {Format.Price(day.value / day.volume)}`
    end
    Im.TextRight(said, dx + 446, line + 2, 12, Im.TEXT)
    line += 24 + 170 + 6 + 44 + 6
    Im.Text(`day {series[1].day + 1}`, dx, line, 11, Im.DIM)
    Im.TextRight("today", dx + 446, line, 11, Im.DIM)
    -- (what the tallest bar stands for)
    local busiest = Chart.Busiest(series)
    local scale = if busiest > 0 then `bars: units traded, the tallest {Format.Whole(busiest)}` else "nothing traded in these days"
    Im.Text(scale, dx + 223 - Im.TextWidth(scale, 11) / 2, line, 11, Im.DIM)
    line += 24
    Im.Text("Lowest", dx, line, 13, Im.DIM)
    Im.Text(Format.Price(low), dx + 80, line, 13, Im.TEXT)
    Im.Text("Highest", dx + 230, line, 13, Im.DIM)
    Im.Text(Format.Price(high), dx + 310, line, 13, Im.TEXT)
    line += 20
    Im.Text("Traded", dx, line, 13, Im.DIM)
    Im.Text(if units > 0 then `{Format.Whole(units)} units, at {Format.Price(worth / units)} on average` else "nothing, by you or yours", dx + 80, line,
      13, if units > 0 then Im.TEXT else Im.DIM)
    line += 24
    Im.Wrapped("The price is the station's going price, between what it asks and what it bids. It moves when somebody trades, and comes home when left alone.",
      dx, line, 446, 12, Im.DIM)
    return
  end

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
  line += 18

  -- Where else it is to be had: the best market within a few jumps, what
  -- it asks, and a hired pilot whose ship is docked here to send for it.
  -- They buy as many as the quantity above and bring them here.
  local asked = math.max(1, math.floor(quantity))
  local key = `{station}:{chosen}:{asked}`
  elsewhere.age += 1
  if elsewhere.key ~= key or elsewhere.age > 30 then
    elsewhere.key, elsewhere.age, elsewhere.list = key, 0, Core.Query.Sources(game, station, chosen, asked)
  end
  local best = elsewhere.list[1]
  if best then
    local here = if cost then cost / asked else nil
    Im.Text("Elsewhere", dx, line, 12, Im.DIM)
    Im.Text(shorten(best.name, 36), dx + 64, line, 12, Im.TEXT)
    local far = if best.jumps == 0 then "in this system" elseif best.jumps == 1 then `1 jump, in {best.system}`
      else `{best.jumps} jumps, in {best.system}`
    Im.Text(shorten(`{far}: {Format.Price(best.each)} each` .. (if best.units < asked then `, has {Format.Whole(best.units)}` else ""), 50),
      dx + 64, line + 15, 12, if here == nil or best.each < here then GOOD else Im.DIM)
    -- (who goes: the first of the pilots docked here who is doing nothing else)
    local goes: Core.FleetRow? = nil
    for _, row in Core.Query.Fleet(game) do
      local ship = game.state.ships[row.ship]
      if goes == nil and ship and ship.docked == station and (row.order == "follow" or row.order == "stay") then
        -- (one keeping stock here already is busy: called back from the Crew tab first)
        goes = row
      end
    end
    local fetch: State.Command = { kind = "FleetOrder", actor = 0, what = "buy", pilot = if goes then goes.id else 0, target = best.id,
      type = chosen, quantity = asked, price = math.ceil(best.each * LEEWAY) }
    -- (or, as a standing order: so many kept in the hangar here from now on)
    local keep: State.Command = { kind = "FleetOrder", actor = 0, what = "stock", pilot = if goes then goes.id else 0, target = best.id,
      type = chosen, quantity = asked, price = math.ceil(best.each * STANDING) }
    local can, why = false, nil :: string?
    local canKeep = false
    if goes then
      can, why = Session.CanDo(session, fetch)
      canKeep = (Session.CanDo(session, keep))
    end
    if Im.Button(if goes then shorten(`Send {string.match(goes.name, "^%S+") or goes.name}`, 11) else "Send", dx + 318, line, 82, 26,
      can, "Fetch") then
      Session.Do(session, fetch)
    end
    if Im.Button("Keep", dx + 404, line, 42, 26, canKeep, "Fetch:keep") then
      Session.Do(session, keep)
    end
    if goes and not can and why then
      Im.Text(shorten(why, 44), dx + 64, line + 30, 11, Im.WARN)
    end
  else
    Im.Text("Elsewhere", dx, line, 12, Im.DIM)
    Im.Text(`no market within {Fleet.SHOPS} jumps has any`, dx + 64, line, 12, Im.DIM, 0.8)
  end
  line += 38

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

  -- Its price here lately, at a glance: clicked, the History side.
  Im.Heading("PRICE HERE", dx, line, 14, Im.DIM)
  Im.TextRight(if level then `steady at {Format.Price(high)}` else `{Format.Price(low)} to {Format.Price(high)}`
    .. (if units > 0 then `, {Format.Whole(units)} traded` else ""), dx + 446, line + 2, 12, Im.DIM)
  line += 22
  Chart.Draw(series, dx, line, 446, 30, 10, true)
  local _, opened = Im.Area("Market:chart", dx, line, 446, 46, true)
  if opened then
    marketPage = "history"
  end
end

-- ---------------------------------------------------------------------
-- Industry

local function drawIndustry(session: Session.Session, game: Core.Game, player: Core.PlayerInfo, x: number, y: number)
  local station = player.docked
  local top = y + 78
  local left = x + 16
  local hangar = Core.Query.Items(game, station, "hangar")

  -- On the left, what is here: blueprints (and copies of them), ore, and
  -- the jobs running. On the right, the blueprint chosen: the job it
  -- would be, and what a laboratory does with it.

  -- Blueprints here.
  local blueprints: { State.Item } = {}
  local ores: { State.Item } = {}
  for _, item in hangar do
    if Blueprints.Of(item.type) then
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
  local visible = 6
  local first = Im.Scroll("blueprints", left - 4, line, 434, visible * 24, #blueprints, visible)
  for row = 1, visible do
    local item = blueprints[row + first]
    if item == nil then
      break
    end
    local blueprint, copy = Blueprints.Of(item.type)
    assert(blueprint)
    local rowY = line + (row - 1) * 24
    local _, clicked = Im.Row(left - 4, rowY, 430, 24, blueprintChosen == item.type)
    Im.Text(shorten(Types.Info(blueprint.product).name, 34), left + 4, rowY + 4, 14, Im.TEXT)
    -- (a copy says how many runs it is still good for)
    Im.TextRight(if copy then `copy: {Format.Whole(item.quantity)} {if item.quantity == 1 then "run" else "runs"} left`
      else `makes {blueprint.perRun} a run`, left + 418, rowY + 5, 12, if copy then Im.ACCENT else Im.DIM)
    if clicked then
      blueprintChosen = item.type
      runs = 1
    end
  end

  -- Ore to refine.
  line = top + 26 + visible * 24 + 14
  Im.Heading(`ORE HERE  {#ores}`, left, line, 16, Im.DIM)
  line += 26
  if #ores == 0 then
    Im.Text("None. Mine some at a belt and bring it back.", left, line, 14, Im.DIM, 0.8)
  end
  local oreRows = 3
  local firstOre = Im.Scroll("ores", left - 4, line, 434, oreRows * 26, #ores, oreRows)
  for row = 1, oreRows do
    local item = ores[row + firstOre]
    if item == nil then
      break
    end
    local rowY = line + (row - 1) * 26
    Im.Text(`{Types.Info(item.type).name}  x{Format.Whole(item.quantity)}`, left + 4, rowY + 3, 14, Im.TEXT)
    local can = Session.CanDo(session, { kind = "Reprocess", actor = 0, item = item.id })
    if Im.Button("Refine", left + 348, rowY, 70, 22, can, `Refine:{item.type}`) then
      Session.Do(session, { kind = "Reprocess", actor = 0, item = item.id })
    end
  end

  -- Jobs running, here and elsewhere.
  calling.left = math.max(0, calling.left - 1)
  local jobs = Core.Query.Jobs(game, nil)
  line += oreRows * 26 + 14
  Im.Heading(`JOBS  {#jobs} / {Core.Query.JobSlots(game)}`, left, line, 16, Im.DIM)
  line += 26
  if #jobs == 0 then
    Im.Text("Nothing is being built.", left, line, 14, Im.DIM, 0.8)
  end
  local jobRows = 3
  local firstJob = Im.Scroll("jobs", left - 4, line, 434, jobRows * 42, #jobs, jobRows)
  for row = 1, jobRows do
    local index = row + firstJob
    local job = jobs[index]
    if job == nil then
      break
    end
    local rowY = line + (row - 1) * 42
    local where = Core.Query.Body(game, job.station)
    local remaining = job.ends - game.state.tick
    -- (a copying and an inventing are named for what the blueprint
    -- builds, as the rows above are)
    local held = Blueprints.Of(job.blueprint)
    local drawing = if held then held.name else Types.Info(job.blueprint).name
    local builds = if held then Types.Info(held.product).name else drawing
    Im.Text(if job.research == "copy" then `Copying, {Format.Whole(job.quantity)} {if job.quantity == 1 then "run" else "runs"}: {shorten(builds, 28)}`
      elseif job.research == "invent" then `Inventing from a copy: {shorten(builds, 24)}`
      elseif job.research ~= "" then `Research ({job.research}): {shorten(drawing, 26)}`
      else `{Format.Whole(job.quantity)} x {shorten(Types.Info(job.product).name, 30)}`, left + 4, rowY, 14, Im.TEXT)
    Im.TextRight(Format.Duration(remaining * Constants.TICK), left + 418, rowY, 14, Im.TEXT)
    Im.Text(if job.station == station then "here" else shorten(if where then where.name else "?", 30), left + 4, rowY + 18, 12, Im.DIM)
    local span = math.max(1, job.ends - job.started)
    -- (called off where it runs: pressed once it asks, and pressed again
    -- within a few seconds it is done. What went into the runs not
    -- finished is lost.)
    local cancel: State.Command = { kind = "CancelJob", actor = 0, target = job.id }
    local armed = calling.job == job.id and calling.left > 0
    if job.station == station and Im.Button(if armed then "Sure?" else "Call off", left + 64, rowY + 16, 76, 20, (Session.CanDo(session, cancel)),
      `Job:cancel:{index}`) then
      if armed then
        Session.Do(session, cancel)
        calling.job, calling.left = 0, 0
      else
        calling.job, calling.left = job.id, 240
      end
    end
    Im.Fill(left + 154, rowY + 23, 264, 4, Im.DIM, 0.25)
    Im.Fill(left + 154, rowY + 23, 264 * math.clamp(1 - remaining / span, 0, 1), 4, Im.ACCENT, 0.95)
  end

  -- The job the chosen blueprint would be.
  local dx = x + 470
  line = top
  local chosenItem = inHangar(game, station, blueprintChosen)
  local plan = if chosenItem then Core.Query.JobPlan(game, station, blueprintChosen, math.max(1, runs)) else nil
  if plan == nil or chosenItem == nil then
    Im.Heading("NEW JOB", dx, line, 16, Im.DIM)
    Im.Text("Choose a blueprint.", dx, line + 28, 14, Im.DIM, 0.8)
    return
  end
  local product = Types.Info(plan.blueprint.product)
  local _, isCopy = Blueprints.Of(blueprintChosen)
  Im.Heading(if isCopy then "NEW JOB, FROM A COPY" else "NEW JOB", dx, line, 16, Im.DIM)
  line += 26
  Im.Text("Runs", dx, line + 5, 14, Im.DIM)
  runs = Im.Number("Runs", runs, dx + 80, line, 100, 26)
  -- as many runs as the minerals here allow (and as a copy has left)
  local most = if isCopy then math.min(100, chosenItem.quantity) else 100
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
  -- (a hull or a tower is built of a dozen things and more: as many as
  -- fit, and the wheel for the rest)
  local materialRows = 7
  local firstMaterial = Im.Scroll("materials", dx, line, 452, materialRows * 20, #plan.materials, materialRows)
  for row = 1, materialRows do
    local m = plan.materials[row + firstMaterial]
    if m == nil then
      break
    end
    local enough = m.have >= m.need
    Im.Text(Types.Info(m.type).name, dx + 12, line, 14, Im.DIM)
    Im.TextRight(Format.Whole(m.need), dx + 240, line, 14, if enough then Im.TEXT else Im.WARN)
    Im.TextRight(`{Format.Whole(m.have)} here`, dx + 440, line, 13, if enough then Im.DIM else Im.WARN)
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
  -- The laboratory: what the pilot has learned of this design and the
  -- next level of each kind, a copy of it, and the inventing of its
  -- tech 2 make.
  local research = Core.Query.Research(game, plan.blueprint.id)
  if research == nil then
    return
  end
  Im.Heading("LABORATORY", dx, line, 14, Im.DIM)
  Im.TextRight(`researched: materials -{research.material}%, time -{research.time * 2}%`, dx + 446, line + 1, 12, Im.DIM)
  line += 24
  if isCopy then
    Im.Text("Research and copying take the blueprint itself, not a copy.", dx, line, 12, Im.DIM, 0.8)
    line += 22
  else
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
    -- (a copy good for the runs entered above: what a job or an
    -- invention can use up in place of the blueprint)
    local copying = Core.Query.CopyPlan(game, blueprintChosen, math.max(1, runs))
    if copying then
      local copy: State.Command = { kind = "StartResearch", actor = 0, item = chosenItem.id, what = "copy", quantity = runs }
      local canCopy, whyNotCopy = Session.CanDo(session, copy)
      if Im.Button("Copy", dx, line, 150, 26, canCopy, "Copy") then
        Session.Do(session, copy)
      end
      Im.Text(`a copy good for {Format.Whole(copying.runs)} {if copying.runs == 1 then "run" else "runs"}, {Format.Duration(copying.seconds)}`,
        dx + 156, line - 1, 12, Im.DIM)
      Im.Text(if canCopy then Format.Credits(copying.fee) else shorten(tostring(whyNotCopy), 44), dx + 156, line + 13, 12,
        if canCopy then Im.DIM else Im.WARN)
      line += 34
    end
  end
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
-- And the further stations they would collect at on the way, in the
-- order they were added (a round of several: Core/Tactical/Fleet).
local haulAlso: { [number]: { number } } = {}
-- (and the stations picked as more to carry to, by the pilot's id)
local haulMore: { [number]: { number } } = {}
local CARGO: { [string]: string } = { ore = "ore", mineral = "minerals", moon = "moon ore", planetary = "planetary", component = "components",
  all = "all goods" }

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
    "3 cruisers, 4 battleships and freighters. You command one a level", "of Leadership. A ship lost is insured; its pilot is not lost.",
    "In space one can be set to mine a belt, to hold a place against", "pirates (Patrol here) or to go with another pilot (Guard);",
    "one docked here to haul what is in your hangar elsewhere (+", "adds a station to collect at on the way: a round); any to",
    "sell what they bring in. They learn by it, to grade 5." } do
    -- (eleven lines in the room ten had)
    Im.Text(text, left, line + 6 + index * 15.5, 12, Im.DIM)
  end

  -- The pilots hired, and for each the ships here they could be given.
  local free: { State.Ship } = {}
  for _, ship in Core.Query.Ships(game, station) do
    if ship.id ~= player.ship and ship.pilot == 0 and Ships.byId[ship.type].class ~= "capsule" then
      table.insert(free, ship)
    end
  end
  line = y + 78
  -- (whose they are, where a corporation has been founded: the Wallet tab has its books)
  local whose = Core.Query.Corporation(game)
  Im.Heading(if whose.founded then `{string.upper(shorten(whose.name, 24))}  {#fleet} / {most}` else `YOUR PILOTS  {#fleet} / {most}`,
    right, line, 16, Im.DIM)
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
    -- (and how they stand toward the pilot)
    Im.Text(row.mood, right + 352, line + 1, 13, if row.mood == "wary" then Im.WARN elseif row.mood == "devoted" then GOOD else Im.DIM)
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
      elseif row.order == "buy" then
        where = row.doing
        note = `{Format.Whole(row.need)} {row.want} still to buy at {row.from}, to bring to {row.to}`
      elseif row.order == "stock" then
        where = row.doing
        note = `Keeps {Format.Whole(row.keep)} {row.want} in the hangar {if here then "here" else `at {row.to}`}, from {row.from}`
      elseif row.order == "haul" then
        where = row.doing
        -- (a round of several stations says how many it collects at)
        note = if #row.stops > 1 then `Hauling {CARGO[row.cargo] or row.cargo} from {#row.stops} stations to {row.to}: {row.hauled} units`
          else `Hauling {CARGO[row.cargo] or row.cargo} to {row.to}: {row.hauled} units`
      elseif row.order == "patrol" then
        where = `{row.doing}: {row.post}`
      elseif row.order == "guard" then
        where = `{row.doing} {row.ward}` .. (if here then ", docked here" else `, {row.where}`)
      elseif row.order == "stay" then
        where ..= ", told to stay"
      end
      if row.earned > 0 then
        note = if note ~= "" then `{note}, sold for {Format.Credits(row.earned)}` else `What they brought in has sold for {Format.Credits(row.earned)}`
      end
      -- (one who is gone for with the pilot somewhere else: that first, and plainly)
      if row.hunted then
        Im.Text(shorten(`{row.shipName}: UNDER ATTACK in {row.where}` .. (if row.post ~= "" then `, at {row.post}` else ""), 58),
          right + 24, line + 22, 12, Im.WARN)
      else
        Im.Text(shorten(`{row.shipName} ({Ships.byId[row.hull].name}), {where}`, 58), right + 24, line + 22, 12, Im.DIM)
      end
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
      if Im.Button(if target then shorten(`to {target.name}`, 17) else "nowhere to go", right + 116, line + 42, 124, 24, #targets > 1,
        `Haul:to:{index}`) then
        haulTo[row.id] = to % #targets + 1
      end
      -- (and the station shown, as one more to collect at on the way: a
      -- round of several. Pressed again, it is not one.)
      local also: { number } = haulAlso[row.id] or {}
      haulAlso[row.id] = also
      local added = if target then table.find(also, target.id) else nil
      if Im.Toggle("+", right + 244, line + 42, 22, 24, added ~= nil, `Haul:also:{index}`) and target then
        if added then
          table.remove(also, added)
        elseif #also + 1 < Fleet.STOPS then
          table.insert(also, target.id)
        end
      end
      -- (or as one more to carry to: a load to each in turn, the one
      -- picked last first. Pressed again, it is not one.)
      local more: { number } = haulMore[row.id] or {}
      haulMore[row.id] = more
      local dropped = if target then table.find(more, target.id) else nil
      if Im.Toggle("&", right + 268, line + 42, 22, 24, dropped ~= nil, `Haul:drop:{index}`) and target then
        if dropped then
          table.remove(more, dropped)
        elseif #more + 1 < Fleet.DROPS then
          table.insert(more, target.id)
        end
      end
      local haul: State.Command = { kind = "FleetOrder", actor = 0, what = "haul", pilot = row.id, target = if target then target.id else 0,
        type = kind, stops = if #also > 0 then table.clone(also) else nil, drops = if #more > 0 then table.clone(more) else nil }
      local can, whyNot = Session.CanDo(session, haul)
      if Im.Button("Haul", right + 292, line + 42, 48, 24, can, `Haul:go:{index}`) then
        Session.Do(session, haul)
      end
      reason = if can then nil else whyNot
      if target and row.order ~= "haul" and row.order ~= "buy" and row.order ~= "stock" then
        note = `{target.name}: ` .. (if target.jumps == 0 then "in this system" elseif target.jumps == 1 then `1 jump, in {target.system}`
          else `{target.jumps} jumps, in {target.system}`) .. (if target.market then ", has a market" else ", no market")
      end
      if #also > 0 then
        -- (the round as it stands: here, and the stations added with +, in order)
        local names: { string } = {}
        for _, id in also do
          local stop = Core.Query.Body(game, id)
          table.insert(names, if stop then shorten(stop.name, 22) else "?")
        end
        note = `Collecting here, then at {table.concat(names, ", ")}` .. (if target and not added then `; to {target.name}` else "; + is another, then pick where to")
      end
      if #more > 0 then
        -- (and where else it is carried to, a load to each in turn)
        local names: { string } = {}
        for _, id in more do
          local drop = Core.Query.Body(game, id)
          table.insert(names, if drop then shorten(drop.name, 22) else "?")
        end
        note = (if target and not dropped then `A load to {shorten(target.name, 22)}, then to ` else "A load in turn to ")
          .. table.concat(names, ", ") .. (if #also > 0 then " (collecting at more than here)" else "")
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

-- The level of each line of work with levels that the list shows: the
-- hardest there is, until the pilot steps it down.
local ladder: { [string]: number } = {}

-- Which level of a line of work ("assault", "mining", "courier",
-- "defence") the list shows: given one, it is set to that. 0: the
-- hardest there is.
function Station.Level(kind: string, to: number?): number
  if to then
    ladder[kind] = to
  end
  return ladder[kind] or 0
end

local function drawMissions(session: Session.Session, game: Core.Game, x: number, y: number)
  local status = Core.Query.Missions(game)
  local left, right = x + 16, x + 480
  local line = y + 78
  local function about(mission: State.Mission, jumps: number, ward: number): string
    if mission.kind == "bounty" then
      local _, band = Core.Query.Security(game, mission.system)
      return `in {game.state.galaxy.systems[mission.system].name} ({band or "?"} space): {mission.done} of {mission.need} destroyed`
    elseif mission.kind == "assault" and (mission.aim == "hold" or Assault.Tender(mission.aim) or mission.aim == "lost") then
      -- (where the rig is, or the tender; and, once the job is taken, how it is going and how the thing is)
      local name = game.state.galaxy.systems[mission.system].name
      local place = if mission.site ~= 0 then Core.Query.Body(game, mission.site) else nil
      local escort = Assault.Tender(mission.aim)
      local convoy = mission.aim == "convoy"
      if place == nil then
        -- (they do not wait their turn, as a camp's keepers do)
        return `in {name}: {#mission.waves} waves, {Assault.PRESS // 60} minutes apart`
          .. (if convoy then (if mission.system == Core.Query.Player(game).system then ", the last off this station" else ", the last at the gate home")
            elseif escort then ", while it flies out" else "")
      elseif mission.done >= mission.need then
        return `{place.name}, in {name}: {if convoy then "in" elseif escort then "through" else "held"}`
      elseif convoy and mission.done >= 1 then
        -- (away from its place, and on its way in)
        local dest = Core.Query.Body(game, mission.to)
        return `away to {if dest then shorten(dest.name, 28) else "the station"}: see it in`
          .. (if ward >= 0 then `, the tender at {math.ceil(ward * 100)}%` else "")
      elseif ward < 0 then
        return `{place.name}, in {name}: they come when you do`
      elseif escort then
        return `{place.name}, {name}: wave {mission.wave} of {#mission.waves}, the tender at {math.ceil(ward * 100)}%`
      end
      return `{place.name}, {name}: wave {mission.wave} of {#mission.waves}, {mission.done}/{mission.need} down, the rig at `
        .. `{math.ceil(ward * 100)}%`
    elseif mission.kind == "assault" then
      -- (where the camp is; and, once the job is taken, how it is going)
      local name = game.state.galaxy.systems[mission.system].name
      local camp = if mission.site ~= 0 then Core.Query.Body(game, mission.site) else nil
      local rooms = if #mission.ends == 1 then "one room" else `{#mission.ends} rooms`
      if camp == nil then
        return `in {name}: {rooms}, {#mission.waves} waves`
      elseif mission.aim ~= "fetch" and mission.done >= mission.need then
        return `{camp.name}, in {name}: done`
      end
      -- (how far in the pilot has got: the rooms whose way is found)
      local open = 0
      for _, room in mission.rooms do
        open += if Core.Query.Found(game, room) then 1 else 0
      end
      local where = if #mission.rooms > 1 then `room {open} of {#mission.rooms}, ` else ""
      local how = if mission.aim == "chief" then "the chief comes with the last"
        elseif mission.aim == "fetch" then "the cargo is in the last room"
        elseif mission.aim == "raze" then `{mission.done}/{mission.need} of its works razed, in the last room`
        else `{mission.done}/{mission.need} down`
      return `{camp.name}, {name}: {where}wave {mission.wave} of {#mission.waves}, {how}`
    elseif mission.kind == "mining" then
      -- (where the pocket is; and whether anybody disputes it)
      local name = game.state.galaxy.systems[mission.system].name
      local place = if mission.site ~= 0 then Core.Query.Body(game, mission.site) else nil
      local disputed = if #mission.waves > 0 then ", disputed" else ""
      return if place then `{place.name}, in {name}{disputed}` else `a pocket in {name}{disputed}`
    elseif mission.kind == "courier" then
      -- (where to, and how far that is)
      local to = Core.Query.Body(game, mission.to)
      local far = if jumps == 0 then "this system" elseif jumps == 1 then "1 jump" else `{jumps} jumps`
      return `{far}: to {if to then shorten(to.name, 40) else "?"}`
    end
    local at = Core.Query.Body(game, mission.station)
    return `to {if at then shorten(at.name, 40) else "?"}`
  end

  Im.Heading(if storeOpen then "LOYALTY STORE" else "JOBS OFFERED HERE", left, line, 16, Im.DIM)
  -- (the faction's store, and the way back from it)
  if Im.Toggle(if storeOpen then `Back to the jobs  ({status.loyalty} LP)` else `Loyalty store: {status.loyalty} LP`, left + 230, line - 4,
    200, 24, storeOpen, "LoyaltyStore") then
    storeOpen = not storeOpen
  end
  line += 30
  -- The store: what the faction lets a pilot have for loyalty points.
  if storeOpen then
    if #status.store == 0 then
      Im.Text("There is no store here.", left, line, 14, Im.DIM, 0.8)
    end
    -- (more than fit: the list scrolls)
    local visible = 21
    local first = Im.Scroll("LoyaltyStore", left, line, 440, visible * 20, #status.store, visible)
    for index, row in status.store do
      if index <= first then
        continue
      elseif index > first + visible then
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
  -- The day's jobs, each a row; then the fourth agent's assault, the
  -- fifth's mining contract, the sixth's courier contract and the
  -- seventh's defence job, a row each: the level shown is stepped up
  -- and down, as far as the pilot's standing has opened.
  local offers: { Core.MissionStatus } = if storeOpen then {} else status.offers
  local function offered(offer: Core.MissionStatus, id: string, kind: string?, level: number, levels: number)
    -- (a job with levels says its level in a word less: the steps beside it say the rest)
    Im.Text(shorten(if kind then (string.gsub(offer.title, ", level", "", 1)) else offer.title, if kind then 30 else 34), left, line, 15,
      Im.TEXT)
    Im.TextRight(Format.Credits(offer.mission.reward), left + 356, line, 15, GOOD)
    local accept: State.Command = { kind = "AcceptMission", actor = 0, what = offer.mission.key }
    local can, whyNot = Session.CanDo(session, accept)
    Im.Text(if can then shorten(about(offer.mission, offer.jumps, offer.ward), 44) else shorten(tostring(whyNot), 44), left, line + 21, 12,
      if can then Im.DIM else Im.WARN)
    -- (who gives it, what they think of the pilot once they think anything, and the points it is worth)
    local thinks = if offer.regard ~= 0 then string.format(" (%.1f)", offer.regard) else ""
    Im.TextRight(`{shorten(offer.mission.agent, 16)}{thinks}  +{offer.mission.loyalty} LP`, left + 356, line + 21, 12,
      if offer.regard > 0 then GOOD elseif offer.regard < 0 then Im.WARN else Im.DIM)
    if kind and levels > 1 then
      if Im.Button("<", left + 236, line - 1, 20, 20, level > 1, `Level:{kind}:down`) then
        ladder[kind] = level - 1
      end
      if Im.Button(">", left + 260, line - 1, 20, 20, level < levels, `Level:{kind}:up`) then
        ladder[kind] = level + 1
      end
    end
    if Im.Button("Accept", left + 364, line + 4, 66, 28, can, id) then
      Session.Do(session, accept)
    end
    line += 50
  end
  local daily = 0
  for _, offer in offers do
    if offer.mission.level == 0 then
      daily += 1
      offered(offer, `Accept:{daily}`, nil, 0, 0)
    end
  end
  for _, kind in { "assault", "mining", "courier", "defence" } do
    local levels: { Core.MissionStatus } = {}
    for _, offer in offers do
      if offer.line == kind then
        table.insert(levels, offer)
      end
    end
    if #levels > 0 then
      local level = math.clamp(if (ladder[kind] or 0) == 0 then #levels else ladder[kind], 1, #levels)
      offered(levels[level], `Accept:{kind}`, kind, level, #levels)
    end
  end

  -- What every faction thinks of the pilot (it is their stations' fees,
  -- their jobs' pay and, at the worst, their patrols' guns).
  if not storeOpen then
    line = y + 78 + 30 + 7 * 50 + 16
    Im.Heading("STANDINGS", left, line, 14, Im.DIM)
    for index, row in Core.Query.Standings(game) do
      -- (four to a row: the four human factions, and under them any
      -- other that has come to think something of the pilot)
      local sx = left + (index - 1) % 4 * 110
      local sy = line + (index - 1) // 4 * 44
      Im.Text(row.name, sx, sy + 24, 13, Im.DIM)
      Im.Text(string.format("%.1f", row.standing), sx, sy + 42, 15, if row.hostile then HOSTILE elseif row.standing < 0 then Im.WARN else Im.TEXT)
      if row.hostile then
        Im.Text("hostile", sx + 44, sy + 44, 12, HOSTILE)
      end
    end
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
    -- (a rig that is going down says so in the colour of a warning)
    Im.Text(shorten(about(held.mission, held.jumps, held.ward), 68), right, line + 21, 12,
      if held.ward >= 0 and held.ward < 0.5 and held.mission.done < held.mission.need then Im.WARN else Im.DIM)
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
-- Careers: the agents who show a new pilot the ropes (Game/UI/Careers
-- draws them: the list on the left, the one picked out on the right)

local function drawCareers(session: Session.Session, game: Core.Game, x: number, y: number)
  local status = Core.Query.Careers(game)
  local left, right = x + 16, x + 480
  Im.Heading("CAREER AGENTS", left, y + 78, 16, Im.DIM)
  Im.Text("Seven people who teach a way of making a living each, and pay for the learning.", left, y + 104, 13, Im.DIM)
  Im.Text("A lesson from each can be in hand at once. The Guide (top left) shows them in space.", left, y + 122, 13, Im.DIM)
  Careers.List(status, left - 8, y + 152, 448)
  Careers.Detail(session, status, right, y + 78, 444)
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
  -- (taken down into the hold, with nothing on it and nothing in it:
  -- pressed when it cannot be, it says why not)
  if Im.Button("Take down", left + 300, line - 1, 100, 24, true, "Tower:down") then
    Session.Do(session, { kind = "UnanchorTower", actor = 0 })
  end
  line += 30
  if status.sealed > 0 then
    Im.Text(`SEALED: nothing can touch it, and it does nothing. It opens in {Format.Duration(status.sealed)}.`, left, line, 13, Im.WARN)
  elseif status.lit then
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
  line += 44

  -- Its moon: what is under it, and how the drilling of it stands.
  local drilling = status.drilling
  local deposit = drilling.deposit
  Im.Heading(shorten(`MOON  {string.upper(status.moon)}`, 40), left, line, 16, Im.DIM)
  line += 24
  if deposit then
    ItemIcon.Draw(deposit.material.id, left, line - 1, 18)
    Info.Name(deposit.material.id, deposit.material.name, left + 24, line, 13, Im.TEXT)
    Im.TextRight(`{Moons.Word(deposit.richness)}: a drill brings up {Format.Whole(drilling.perHour)} an hour`, left + 400, line, 13, Im.DIM)
    line += 20
    local full = drilling.stored >= drilling.room
    local held = `{Format.Whole(drilling.stored)} of {Format.Whole(drilling.room)} in the hangar`
    if not drilling.anchored then
      Im.Text("No drill is anchored: a Moon Drill gets at it.", left, line, 13, Im.DIM)
    elseif full then
      Im.Text(`Full, {held}: take some away, or anchor a Storage Array.`, left, line, 13, Im.WARN)
    elseif drilling.online then
      Im.Text(`Drilling: {held}`, left, line, 13, GOOD)
      Im.TextRight(`more in {Format.Duration(status.next)}`, left + 400, line, 13, Im.DIM)
    else
      Im.Text(`The drill is not working: {held}`, left, line, 13, Im.WARN)
    end
  else
    Im.Text("Nothing under it worth a drill.", left, line, 13, Im.DIM)
    line += 20
  end
  line += 20
  -- What it has against the pirates who come for what a drill brings
  -- up, where order is thin: its batteries and whoever holds the place.
  if status.raidMost == 0 then
    Im.Text("Order is kept here: nobody raids it.", left, line, 13, Im.DIM)
  else
    local parts = `{status.batteries} {if status.batteries == 1 then "battery" else "batteries"}, {status.patrol} on patrol`
    Im.Text(`Defence {status.defence} ({parts})`, left, line, 13, if status.defence >= status.raidMost then GOOD
      elseif status.defence >= status.raidLeast then Im.TEXT else Im.WARN)
    Im.TextRight(`raids here come {status.raidLeast} to {status.raidMost} strong`, left + 400, line, 13, Im.DIM)
  end
  line += 20
  -- Under fire: what is left of its shield, its armour and its
  -- structure, the sealing charges it has, and who is after it.
  local function share(value: number): string
    return `{math.ceil(value * 100)}%`
  end
  local hurt = status.shield < 0.999 or status.armor < 0.999 or status.hull < 0.999
  Im.Text(`Shield {share(status.shield)}   armour {share(status.armor)}   structure {share(status.hull)}`, left, line, 13,
    if hurt then Im.WARN else Im.DIM)
  Im.TextRight(`sealing charges {status.charges} / {status.bay}`, left + 400, line, 13,
    if status.charges == 0 and status.besieged then Im.WARN else Im.DIM)
  line += 20
  if status.siege > 0 then
    Im.Text(if status.sealed > 0 then `They will be back when it opens: {status.siege} strong against your {status.defence}.`
      else `UNDER SIEGE: {status.siege} strong against your {status.defence}.`, left, line, 13, Im.WARN)
  elseif status.besieged then
    Im.Text(if status.charges > 0 then `A raid it does not match is a siege here: it seals for {status.charges} h at a quarter shield.`
      else "A raid it does not match is a siege here, and with no charge it does not seal.", left, line, 13,
      if status.charges > 0 then Im.DIM else Im.WARN)
  else
    Im.Text("Nobody comes to bring a tower down here.", left, line, 13, Im.DIM, 0.8)
  end
  line += 26

  -- What is anchored round it.
  Im.Heading(`ANCHORED  {#status.modules}`, left, line, 16, Im.DIM)
  line += 26
  if #status.modules == 0 then
    Im.Text("Nothing yet. A module to hand is anchored from the list on the right.", left, line, 13, Im.DIM, 0.8)
  end
  local visible = 4
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

  -- What there is to hand, in the hold and in the tower's hangar (the
  -- pilot's own there, and the corporation's), to burn or to anchor.
  local right = x + 480
  line = y + 78
  local hand: { { item: State.Item, where: string } } = {}
  for _, place in { "cargo", "hangar", "corporate" } do
    for _, item in Core.Query.Items(game, if place == "cargo" then player.ship else station, place) do
      if item.type == Structures.FUEL.id or item.type == Structures.SEAL.id or Structures.moduleById[item.type] then
        table.insert(hand, { item = item, where = if place == "cargo" then "hold" elseif place == "hangar" then "hangar" else "corporation" })
      end
    end
  end
  Im.Heading(`TO HAND  {#hand}`, right, line, 16, Im.DIM)
  line += 26
  if #hand == 0 then
    Im.Text("No fuel and no modules in the hold or the hangar.", right, line, 13, Im.DIM, 0.8)
    Im.Text("A market sells both, under Structures.", right, line + 20, 13, Im.DIM, 0.8)
  end
  -- (a tower with a reactor has that under the list, and a shorter list)
  local reacting = status.reacting
  local shown = if reacting.anchored then 10 else 13
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
    -- (a sealing charge goes in its bay as fuel goes in its tank)
    local seal = item.type == Structures.SEAL.id
    local command: State.Command = { kind = if fuel or seal then "Fuel" else "AnchorModule", actor = 0, item = item.id }
    local can, whyNot = Session.CanDo(session, command)
    if Im.Button(if fuel then "Fuel" elseif seal then "Load" else "Anchor", right + 250, line, 60, 21, can,
      if fuel then `Fuel:{entry.where}` elseif seal then `Seal:{entry.where}` else `Anchor:{item.type}`) then
      Session.Do(session, command)
    end
    if not can then
      Im.Text(shorten(tostring(whyNot), 20), right + 318, line + 3, 12, Im.WARN)
    end
    line += 26
  end

  -- Its running since it was anchored, priced: what it has burnt
  -- against what it has brought up, and what a day of it costs and
  -- brings. (The corporation's books have every tower's: the Wallet tab.)
  local running = status.running
  line = y + 78 + 26 + shown * 26 + 12
  if reacting.anchored then
    -- Its reactor: what it is set to make (a press sets it, and "Off"
    -- stops it), what of each thing that is made of there is in the
    -- hangars, and when the next batch is.
    local making = reacting.making
    -- (whether there is too little of either thing for its next batch)
    local short = false
    if making then
      for index in making.from do
        short = short or reacting.have[index] < Reactions.BATCH
      end
    end
    Im.Heading("REACTOR", right, line, 16, Im.DIM)
    Im.TextRight(if not reacting.online then "not working: the tower is dark, or it is not online yet"
      elseif making == nil then "making nothing"
      elseif reacting.starved then "idle: not enough to make it of"
      elseif short then `not enough for the batch due in {Format.Duration(status.reacts)}`
      else `{Format.Whole(Reactions.BATCH)} more in {Format.Duration(status.reacts)}`, right + 440, line + 2, 12,
      if reacting.online and making and not reacting.starved and not short then GOOD elseif making or not reacting.online then Im.WARN
        else Im.DIM)
    line += 24
    local across = right
    for _, composite in Reactions.composites do
      local wide = Im.TextWidth(composite.name, 13) + 18
      if Im.Toggle(composite.name, across, line, wide, 21, making == composite, `React:{composite.id}`) and making ~= composite then
        Session.Do(session, { kind = "SetReaction", actor = 0, type = composite.id })
      end
      across += wide + 6
    end
    if Im.Button("Off", across, line, 40, 21, making ~= nil, "React:off") then
      Session.Do(session, { kind = "SetReaction", actor = 0, type = "" })
    end
    line += 26
    if making then
      local parts: { string } = {}
      for index, from in making.from do
        table.insert(parts, `{Types.Info(from).name} {Format.Whole(reacting.have[index])}`)
      end
      Im.Text(shorten(`{table.concat(parts, "   ")}`, 44), right, line, 13, if short then Im.WARN else Im.TEXT)
      Im.TextRight(`{Format.Whole(Reactions.BATCH)} of each an hour`, right + 440, line, 12, Im.DIM)
    else
      Im.Text("It makes a composite of the two moon materials of a grade.", right, line, 13, Im.DIM, 0.8)
    end
    line += 28
  end
  Im.Heading("RUNNING", right, line, 16, Im.DIM)
  Im.TextRight("in credits' worth, since it was anchored", right + 440, line + 2, 12, Im.DIM)
  line += 26
  Im.Text(`Fuel burnt: {Format.Whole(running.used)} blocks`, right, line, 13, Im.DIM)
  Im.TextRight(`-{Format.Whole(running.usedWorth)}`, right + 440, line, 13, if running.used > 0 then Im.WARN else Im.DIM)
  line += 20
  Im.Text(`Brought up: {Format.Whole(running.raised)}` .. (if running.robbed > 0 then `, and {Format.Whole(running.robbed)} carried off`
    else ""), right, line, 13, Im.DIM)
  Im.TextRight(`+{Format.Whole(running.raisedWorth - running.robbedWorth)}`, right + 440, line, 13,
    if running.raised > 0 then GOOD else Im.DIM)
  line += 20
  Im.Text("A day, as it stands", right, line, 13, Im.DIM)
  Im.TextRight(`+{Format.Whole(running.yieldADay)}  -{Format.Whole(running.fuelADay)}`, right + 440, line, 13,
    if running.yieldADay >= running.fuelADay and running.yieldADay > 0 then GOOD elseif status.lit then Im.WARN else Im.DIM)
end

-- ---------------------------------------------------------------------
-- Wallet

-- Which side of the Wallet tab is shown (the pilot's own, or their
-- corporation's); the name a corporation would be founded under; and
-- how much is to go into its account or come out of it.
local books = "mine"
local corporationName = ""
local corporationAmount = 0
-- And which of the corporation's pages: its journal, its books by
-- head with the towers on them, or its hangar at the station.
local corporationPage: "journal" | "books" | "hangar" = "journal"

-- The corporation's books: on the left what has come in and gone out
-- under each head, and what that makes; on the right the pilot's
-- towers, each with what it has burnt, brought up and lost since it
-- was anchored, priced, and what a day of it costs and brings.
local function drawBooks(corporation: Core.CorporationInfo, left: number, top: number)
  local line = top
  Im.Heading("BY HEAD", left, line, 14, Im.DIM)
  Im.TextRight("since it was founded", left + 400, line + 1, 12, Im.DIM)
  line += 24
  if #corporation.heads == 0 then
    Im.Text("Nothing has been earned or spent yet.", left, line, 13, Im.DIM, 0.8)
    line += 22
  end
  for _, head in corporation.heads do
    Im.Text(head.name, left, line, 14, Im.TEXT)
    Im.TextRight((if head.amount >= 0 then "+" else "") .. Format.Whole(head.amount), left + 400, line, 14,
      if head.amount >= 0 then GOOD else Im.WARN)
    line += 22
  end
  local net = corporation.earned - corporation.spent
  Im.Fill(left, line + 2, 400, 1, Im.DIM, 0.4)
  line += 8
  Im.Text("Which makes", left, line, 14, Im.DIM)
  Im.TextRight((if net >= 0 then "+" else "") .. Format.Whole(net), left + 400, line, 14, if net >= 0 then GOOD else Im.WARN)
  line += 34
  -- (the towers, all told: what they have burnt against what they have brought up, in credits' worth)
  local burnt, raised, robbed, fuelADay, yieldADay = 0, 0, 0, 0, 0
  for _, tower in corporation.towers do
    burnt += tower.running.usedWorth
    raised += tower.running.raisedWorth
    robbed += tower.running.robbedWorth
    fuelADay += tower.running.fuelADay
    yieldADay += tower.running.yieldADay
  end
  if #corporation.towers > 0 then
    Im.Heading("THE TOWERS, ALL TOLD", left, line, 14, Im.DIM)
    Im.TextRight("in credits' worth", left + 400, line + 1, 12, Im.DIM)
    line += 24
    local told: { { name: string, worth: number, gain: boolean } } = {
      { name = "Brought up", worth = raised, gain = true }, { name = "Carried off by raiders", worth = robbed, gain = false },
      { name = "Fuel burnt", worth = burnt, gain = false },
    }
    for _, row in told do
      Im.Text(row.name, left, line, 14, Im.TEXT)
      Im.TextRight((if row.worth == 0 then "" elseif row.gain then "+" else "-") .. Format.Whole(row.worth), left + 400, line, 14,
        if row.worth == 0 then Im.DIM elseif row.gain then GOOD else Im.WARN)
      line += 22
    end
    Im.Text("A day, as they stand", left, line, 14, Im.DIM)
    Im.TextRight(`+{Format.Whole(yieldADay)}  -{Format.Whole(fuelADay)}`, left + 400, line, 14,
      if yieldADay >= fuelADay then GOOD else Im.WARN)
  end

  local right = left + 470
  line = top
  Im.Heading(`TOWERS  {#corporation.towers}`, right, line, 14, Im.DIM)
  line += 24
  if #corporation.towers == 0 then
    Im.Text("You have no tower. One is anchored at a moon, from the hold.", right, line, 13, Im.DIM, 0.8)
  end
  local visible = 5
  local first = Im.Scroll("corporation towers", right - 4, line, 440, visible * 68, #corporation.towers, visible)
  for row = 1, visible do
    local tower = corporation.towers[row + first]
    if tower == nil then
      break
    end
    local running = tower.running
    Im.Text(shorten(tower.name, 38), right, line, 14, Im.TEXT)
    Im.TextRight(if tower.lit then tower.system else `{tower.system}: DARK`, right + 436, line + 1, 12, if tower.lit then Im.DIM else Im.WARN)
    local what = if running.material ~= "" then Types.Info(running.material).name else "nothing under it"
    Im.Text(`burnt {Format.Whole(running.used)} blocks ({Format.Whole(running.usedWorth)})`, right, line + 21, 12, Im.DIM)
    Im.TextRight(if running.material == "" then what
      else `{Format.Whole(running.raised)} {what} up ({Format.Whole(running.raisedWorth)})`
        .. (if running.robbed > 0 then `, {Format.Whole(running.robbed)} lost` else ""), right + 436, line + 21, 12,
      if running.robbed > 0 then Im.WARN else Im.DIM)
    Im.Text(`a day: {Format.Whole(running.fuelADay)} of fuel`, right, line + 39, 12, Im.DIM)
    Im.TextRight(if running.yieldADay > 0 then `brings up {Format.Whole(running.yieldADay)}` else "brings up nothing", right + 436,
      line + 39, 12, if running.yieldADay > running.fuelADay then GOOD else Im.DIM)
    line += 68
  end
end

-- The corporation's hangar at the station: what is in it on the left,
-- each stack to be taken into the pilot's own hangar or sold for the
-- corporation's account; and the pilot's own hangar on the right, each
-- stack to be given.
local function drawCorporateHangar(session: Session.Session, game: Core.Game, station: number, left: number, top: number)
  local function sorted(place: string): { State.Item }
    local items = table.clone(Core.Query.Items(game, station, place))
    table.sort(items, function(a: State.Item, b: State.Item): boolean
      if a.type ~= b.type then
        return Catalog.Before(a.type, b.type)
      end
      return a.id < b.id
    end)
    return items
  end
  local visible = 11
  local width = 440
  for column, place in { "corporate", "hangar" } do
    local x = left + (column - 1) * (width + 28)
    local items = sorted(place)
    Im.Heading(if place == "corporate" then `THE CORPORATION'S HANGAR HERE  {#items}` else `YOUR HANGAR HERE  {#items}`, x, top, 16, Im.DIM)
    local line = top + 26
    if #items == 0 then
      Im.Text(if place == "corporate" then "Nothing: what your pilots bring in here is put here." else "nothing here", x, line, 13, Im.DIM, 0.8)
    end
    local first = Im.Scroll(if place == "corporate" then "corporate hangar" else "own hangar", x - 4, line, width, visible * 24, #items, visible)
    for row = 1, visible do
      local item = items[row + first]
      if item == nil then
        break
      end
      local info = Types.Info(item.type)
      local name = shorten(info.name, 24)
      ItemIcon.Draw(item.type, x, line + 1, 20)
      Info.Name(item.type, name, x + 26, line + 3, 13, Im.TEXT)
      Im.Text(`x{Format.Whole(item.quantity)}`, x + 30 + Im.TextWidth(name, 13), line + 3, 12, Im.DIM)
      if place == "corporate" then
        local take: State.Command = { kind = "MoveItems", actor = 0, item = item.id, to = "hangar" }
        if Im.Button("Take", x + width - 116, line, 52, 21, (Session.CanDo(session, take)), `FromCorp:{item.type}`) then
          Session.Do(session, take)
        end
        local sell: State.Command = { kind = "SellNow", actor = 0, item = item.id, quantity = item.quantity }
        if Im.Button("Sell", x + width - 60, line, 52, 21, (Session.CanDo(session, sell)), `SellCorp:{item.type}`) then
          Session.Do(session, sell)
        end
      else
        local give: State.Command = { kind = "MoveItems", actor = 0, item = item.id, to = "corporate" }
        if Im.Button("Give", x + width - 60, line, 52, 21, (Session.CanDo(session, give)), `ToCorp:{item.type}`) then
          Session.Do(session, give)
        end
      end
      line += 24
    end
  end
  local foot = top + 26 + visible * 24 + 10
  Im.Text("Your hired pilots put what they bring in into the corporation's hangar and carry away what is in it; they leave your own alone.",
    left, foot, 13, Im.DIM)
  Im.Text("What is sold out of it is paid to the corporation's account. A tower's drill fills the corporation's hangar there.", left,
    foot + 19, 13, Im.DIM)
end

local function drawWallet(session: Session.Session, game: Core.Game, x: number, y: number)
  local top = y + 78
  local left = x + 16
  local corporation = Core.Query.Corporation(game)
  if Im.Toggle("Mine", x + 700, top - 6, 80, 26, books == "mine", "Wallet:mine") then
    books = "mine"
  end
  if Im.Toggle("Corporation", x + 784, top - 6, 140, 26, books == "corporation", "Wallet:corporation") then
    books = "corporation"
  end
  local journal = Core.Query.Journal(game)
  local line = top + 40
  if books == "corporation" and not corporation.founded then
    -- Nobody's yet: what one is, and the founding of it.
    Im.Heading("NO CORPORATION", left, top, 16, Im.DIM)
    line = top + 34
    for _, text in { "A corporation is the business your hired pilots work for. It has an account of its own:",
      "their signing on, their wages and the mending of their ships come out of it, and what they sell",
      "and the bounties they earn with you elsewhere go into it, so its books say what they make against",
      `what they cost. It has places for {corporation.staff} more pilots than your Leadership commands. Where its account`,
      "is short, your own wallet pays the difference. It is founded once, here, under a name of yours." } do
      Im.Text(text, left, line, 13, Im.DIM)
      line += 19
    end
    line += 14
    Im.Text("Name", left, line + 5, 14, Im.DIM)
    corporationName = Im.Words("Corporation:name", corporationName, left + 60, line, 300, 28, 24, "three letters to twenty-four")
    local found: State.Command = { kind = "FoundCorporation", actor = 0, what = corporationName }
    local can, whyNot = Session.CanDo(session, found)
    if Im.Button(`Found it: {Format.Credits(corporation.fee)}`, left + 372, line, 200, 28, can, "Corporation:found") then
      Session.Do(session, found)
      books = "corporation"
    end
    if not can and corporationName ~= "" then
      Im.Text(tostring(whyNot), left + 584, line + 6, 13, Im.WARN)
    end
    return
  elseif books == "corporation" then
    journal = corporation.journal
    Im.Heading(string.upper(corporation.name), left, top, 16, Im.DIM)
    Im.Heading(Format.Credits(corporation.wallet), left, top + 24, 22, Im.TEXT)
    Im.Text(`founded {Format.Clock(corporation.since)}`, left + 2, top + 54, 12, Im.DIM)
    -- Its books: what its pilots have made against what they have cost.
    local net = corporation.earned - corporation.spent
    Im.Text("earned", left + 250, top + 26, 12, Im.DIM)
    Im.TextRight(Format.Whole(corporation.earned), left + 400, top + 24, 14, GOOD)
    Im.Text("spent", left + 250, top + 46, 12, Im.DIM)
    Im.TextRight(Format.Whole(corporation.spent), left + 400, top + 44, 14, Im.WARN)
    Im.Text("which makes", left + 420, top + 26, 12, Im.DIM)
    Im.TextRight((if net >= 0 then "+" else "") .. Format.Whole(net), left + 600, top + 24, 14, if net >= 0 then GOOD else Im.WARN)
    Im.Text("wages a day", left + 420, top + 46, 12, Im.DIM)
    Im.TextRight(Format.Whole(corporation.wages), left + 600, top + 44, 14, Im.TEXT)
    -- Into its account from the pilot's own wallet, and out of it.
    corporationAmount = Im.Number("Corporation:amount", corporationAmount, left + 620, top + 34, 110, 26)
    local deposit: State.Command = { kind = "CorporationDeposit", actor = 0, quantity = corporationAmount }
    if Im.Button("Pay in", left + 736, top + 34, 76, 26, (Session.CanDo(session, deposit)), "Corporation:deposit") then
      Session.Do(session, deposit)
    end
    local withdraw: State.Command = { kind = "CorporationWithdraw", actor = 0, quantity = corporationAmount }
    if Im.Button("Take out", left + 816, top + 34, 92, 26, (Session.CanDo(session, withdraw)), "Corporation:withdraw") then
      Session.Do(session, withdraw)
    end
    -- Its pages: the journal, the books by head, and its hangar here.
    if Im.Toggle("Journal", x + 404, top - 6, 90, 26, corporationPage == "journal", "Corporation:journal") then
      corporationPage = "journal"
    end
    if Im.Toggle("Books", x + 498, top - 6, 90, 26, corporationPage == "books", "Corporation:books") then
      corporationPage = "books"
    end
    if Im.Toggle("Hangar", x + 592, top - 6, 90, 26, corporationPage == "hangar", "Corporation:hangar") then
      corporationPage = "hangar"
    end
    line = top + 84
    if corporationPage == "books" then
      drawBooks(corporation, left, line)
      return
    elseif corporationPage == "hangar" then
      drawCorporateHangar(session, game, Core.Query.Player(game).docked, left, line)
      return
    end
  else
    Im.Heading("BALANCE", left, top, 16, Im.DIM)
    Im.Heading(Format.Credits(game.state.wallet), left + 110, top - 4, 22, Im.TEXT)
  end
  Im.Text("WHEN", left, line, 12, Im.DIM)
  Im.Text("WHAT", left + 150, line, 12, Im.DIM)
  Im.TextRight("AMOUNT", left + 600, line, 12, Im.DIM)
  Im.TextRight("BALANCE", left + 780, line, 12, Im.DIM)
  line += 20
  if #journal == 0 then
    Im.Text("Nothing has been paid or earned yet.", left, line, 14, Im.DIM, 0.8)
  end
  local visible = if books == "corporation" then 16 else 18
  local first = Im.Scroll(if books == "corporation" then "corporation journal" else "journal", left - 4, line, 900, visible * 22, #journal,
    visible)
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
  preview: Preview?, show: Show?)
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
  -- And where the career agents are, there is them.
  local careers = Core.Query.Careers(game)
  local school = careers.station == player.docked
  if tab == "Careers" and not school then
    tab = "Fitting"
  end
  local tabs: { string } = if own then OWN elseif school then SCHOOL else TABS
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
  elseif school and not careers.begun and tab ~= "Careers" and select(2, Core.Query.Guide(game)) < 12 then
    -- (a pilot who has not met them yet is told they are here; one who
    -- has done half of what there is to do without them is not new)
    Im.Text("New here? The career agents teach the ropes, and pay: Careers.", x + 16, y + 58, 13, Im.ACCENT)
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
    drawWallet(session, game, x, y)
  elseif tab == "Crew" then
    drawCrew(session, game, player, x, y)
  elseif tab == "Missions" then
    drawMissions(session, game, x, y)
  elseif tab == "Careers" then
    drawCareers(session, game, x, y)
  elseif tab == "Starbase" and own then
    drawStarbase(session, game, player, own, x, y)
  else
    drawFitting(session, game, player, x, y, preview, show)
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
