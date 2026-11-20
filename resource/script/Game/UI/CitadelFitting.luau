--!strict
-- A citadel of the pilot's own, laid out as the ship fitting window is
-- (the owner's, 2026-11-19: "it should look like the regular ship
-- fitting window"). Drawn in the Starbase window (Game/UI/Starbase),
-- which is called "Citadel" at one.
--
-- In the middle is the citadel as it stands in space, the camera going
-- slowly round it (Scene.ShowStation), in a wheel of its slots: its
-- services along the top, its shield modules down the right, its one
-- defence module at the bottom. A slot is clicked to pick it; a module
-- in one has, while the cursor is on it, a cross at its corner that
-- takes it out. Under the wheel: how full each kind of slot is, whether
-- it is lit, the system's claim, and taking it down.
--
-- On the left is what goes in the kind of slot picked: what is to hand
-- (the hold, the hangar here and the corporation's), or what the market
-- here sells. On the right is what it comes to: fuel, each layer with
-- what it stops of each kind of damage, how it stands under fire, its
-- guns and how far it tethers, and what its running costs.
--
-- A script's names: "Citadel:slot:<rack><n>", "Citadel:from:<hand or
-- market>", "Citadel:module:<type>" (a row: a double click fits it),
-- "Citadel:fit" (the row picked), "Anchor:<type>" (the row picked's
-- button too), "Unanchor:<type>" (the cross on a fitted module),
-- "Citadel:fuel" and "Tower:down".

local Catalog = require("@lt/Core/Data/Catalog")
local CitadelGuns = require("@lt/Core/Tactical/CitadelGuns")
local Core = require("@lt/Core/Api")
local Fitting = require("@lt/Game/UI/Fitting")
local Format = require("@lt/Game/Format")
local Icons = require("@lt/Game/UI/Icons")
local Im = require("@lt/Game/UI/Im")
local Info = require("@lt/Game/UI/Info")
local ItemIcon = require("@lt/Game/UI/ItemIcon")
local Session = require("@lt/Game/Session")
local Starbases = require("@lt/Core/Assets/Starbases")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local Theme = require("@lt/Game/UI/Theme")
local Types = require("@lt/Core/Data/Types")

local CitadelFitting = {}

-- How the citadel is drawn in the wheel: set by the HUD each frame (the
-- scene's, Scene.ShowStation); nil, or false back, and its icon is drawn.
CitadelFitting.Show = nil :: ((station: number, cx: number, cy: number, round: number) -> boolean)?

-- The window's size at a citadel: the ship fitting window's.
CitadelFitting.WIDTH, CitadelFitting.HEIGHT = 1040, 720

local LEFT_W, RIGHT_W = 326, 280
local RING = 150
local SLOT = 38

-- The kinds of slot, where each sits on the wheel (in turns, 0 to the
-- right and a quarter straight down), how much of it each may take, and
-- the name over it.
type Rack = { id: string, name: string, one: string, middle: number, span: number }
local RACKS: { Rack } = {
  { id = "service", name = "SERVICES", one = "Service", middle = 0.75, span = 0.30 },
  { id = "shield", name = "SHIELD", one = "Shield", middle = 0.0, span = 0.16 },
  { id = "guns", name = "DEFENCE", one = "Defence", middle = 0.25, span = 0.10 },
}

local EM, THERMAL, KINETIC, EXPLOSIVE = vector.create(0.35, 0.65, 1.0), vector.create(0.88, 0.38, 0.31),
  vector.create(0.64, 0.69, 0.74), vector.create(0.95, 0.64, 0.24)
local KINDS = { EM, THERMAL, KINETIC, EXPLOSIVE }
local KIND_HEADS = { "EM", "THERM", "KIN", "EXPL" }

-- The kind of slot picked, and which of it; where the list is of, and the row picked.
local pickedRack, pickedSlot = "service", 0
local source = "hand"
local chosen = ""
-- The tax asked for, in points, at which citadel: shown until the game has it (it changes a second at a time, and
-- presses may come faster).
local asked: { station: number, points: number }? = nil

local function shorten(text: string, limit: number): string
  return if #text > limit then string.sub(text, 1, limit - 1) .. "." else text
end

-- Which kind of slot a citadel module goes in.
local function rackOf(module: Structures.ModuleType): string
  return if module.service == "shield" then "shield" elseif module.service == "weapons" then "guns" else "service"
end

local function onWheel(cx: number, cy: number, radius: number, turn: number): (number, number)
  local angle = 2 * math.pi * turn
  return cx + radius * math.cos(angle), cy + radius * math.sin(angle)
end

local function arc(cx: number, cy: number, inner: number, outer: number, from: number, to: number, color: vector, alpha: number)
  if to > from then
    WidgetRenderer_DrawPanelRadial(Theme.Point(cx, cy), inner * Theme.scale, outer * Theme.scale, ((from + to) / 2) % 1, to - from, color, alpha,
      alpha, 0)
  end
end

-- ---------------------------------------------------------------------
-- The wheel

local function drawWheel(session: Session.Session, status: Core.StarbaseStatus, station: number, cx: number, cy: number)
  WidgetRenderer_DrawPanelRadial(Theme.Point(cx, cy), 0, (RING - 28) * Theme.scale, 0, 1, vector.create(0.02, 0.03, 0.045), 0.9, 0.9, 0)
  local show = CitadelFitting.Show
  if not (show and show(station, cx, cy, RING - 30)) then
    ItemIcon.Draw(status.tower.id, cx - 40, cy - 40, 80)
  end
  arc(cx, cy, RING - 1, RING + 1, 0, 1, Im.DIM, 0.22)

  -- What is in each kind of slot, in the order it was fitted.
  local fitted: { [string]: { { type: string, online: boolean, wait: number } } } = { service = {}, shield = {}, guns = {} }
  for _, module in status.modules do
    table.insert(fitted[rackOf(Structures.moduleById[module.type])], module)
  end
  local counts: { [string]: number } = { service = status.serviceSlots, shield = status.shieldSlots, guns = 1 }
  for _, rack in RACKS do
    local count = counts[rack.id]
    if count <= 0 then
      continue
    end
    local pitch = math.min(0.045, rack.span / count)
    local size = math.clamp(math.floor(2 * math.pi * RING * pitch) - 4, 8, SLOT)
    -- (its name, on the rim before its first slot)
    local firstTurn = rack.middle + (1 - (count + 1) / 2) * pitch
    local labelWidth = Im.StrongWidth(rack.name, 11)
    local lx, ly = onWheel(cx, cy, RING, firstTurn - (size / 2 + labelWidth / 2 + 7) / (2 * math.pi * RING))
    Im.Flat(lx - labelWidth / 2 - 4, ly - 8, labelWidth + 8, 16, Theme.PANEL)
    Im.Strong(rack.name, lx - labelWidth / 2, ly - 6, 11, if pickedRack == rack.id then Theme.ACCENT else Theme.DIM)
    for slot = 1, count do
      local turn = rack.middle + (slot - (count + 1) / 2) * pitch
      local sx, sy = onWheel(cx, cy, RING, turn)
      local left, top = math.floor(sx - size / 2), math.floor(sy - size / 2)
      local module = fitted[rack.id][slot]
      local isPicked = pickedRack == rack.id and pickedSlot == slot
      local hot, clicked = Im.Area(`Citadel:slot:{rack.id}{slot}`, left, top, size, size, true)
      if module then
        local type = Structures.moduleById[module.type]
        Im.Flat(left, top, size, size, if hot then Theme.CONTROL_HOT else Theme.CONTROL)
        ItemIcon.Draw(type.id, left + 2, top + 2, size - 4)
        -- (not yet online: dimmed, with how long)
        if not module.online then
          Im.Flat(left, top, size, size, Theme.PANEL, 0.55)
        end
        if hot then
          Im.Tip(type.name, if module.online then `{rack.one} slot {slot}, online`
            elseif module.wait > 0 then `{rack.one} slot {slot}, online in {Format.Duration(module.wait)}`
            else `{rack.one} slot {slot}, no power: the citadel is dark`)
        end
        -- taking it out: a cross at its corner, while the cursor is on it
        local remove: State.Command = { kind = "UnanchorModule", actor = 0, type = type.id }
        local canRemove = (Session.CanDo(session, remove))
        local ux, uy = left + size - 2, top + 2
        local crossHot, out = Im.Area(`Unanchor:{type.id}`, ux - 7, uy - 7, 14, 14, canRemove)
        if (hot or crossHot) and canRemove then
          Im.Flat(ux - 7, uy - 7, 14, 14, if crossHot then Theme.BAD else Theme.RAISED)
          Im.Edge(ux - 7, uy - 7, 14, 14, Theme.EDGE_STRONG)
          Icons.Draw("close", ux, uy, 3.5, Theme.TEXT, 1)
        end
        if crossHot and canRemove then
          Im.Tip(`Take the {type.name} out`, "Into the citadel's hangar")
        end
        if out then
          Session.Do(session, remove)
        end
      else
        Im.Flat(left, top, size, size, Theme.WELL, 0.8)
        if hot then
          Im.Flat(left, top, size, size, Theme.TEXT, 0.07)
          Im.Tip(`{rack.one} slot {slot}: empty`, "Click to list what goes in it")
        end
      end
      if isPicked then
        Im.Flat(left, top, size, size, Theme.ACCENT, 0.14)
      end
      Im.Edge(left, top, size, size, if isPicked then Theme.ACCENT elseif module then Theme.EDGE_STRONG else Theme.EDGE)
      if clicked then
        if pickedRack ~= rack.id then
          chosen = ""
          Im.ScrollTo("citadel modules", 0)
        end
        pickedRack, pickedSlot = rack.id, slot
      end
    end
  end
end

-- How full a kind of slot is: a bar, and the two numbers.
local function useBar(label: string, used: number, capacity: number, color: vector, x: number, y: number, w: number)
  Im.Text(label, x, y, 13, Theme.DIM)
  local bx, bw = x + 118, w - 118 - 70
  Im.Flat(bx, y + 4, bw, 8, Theme.WELL)
  Im.Edge(bx, y + 4, bw, 8, Theme.EDGE)
  local share = if capacity > 0 then math.clamp(used / capacity, 0, 1) else 0
  if share > 0 then
    Im.Flat(bx, y + 4, math.max(2, bw * share), 8, color)
  end
  local of = ` / {capacity}`
  local ofWidth = Im.TextWidth(of, 13)
  Im.Text(of, x + w - ofWidth, y, 13, Theme.FAINT)
  local taken = tostring(used)
  Im.Strong(taken, x + w - ofWidth - Im.StrongWidth(taken, 13), y, 13, if used < capacity then Theme.CAUTION else Theme.TEXT)
end

-- ---------------------------------------------------------------------
-- What there is to fit, down the left.

type Row = { type: string, item: State.Item?, name: string, count: number, where: string, ask: number?, can: boolean, why: string }

-- What the market here sells for a kind of slot: asked once in a few
-- ticks, and not once a frame.
local selling = { station = 0, tick = -100, rack = "", size = 0, rows = {} :: { Row } }

local function onSale(game: Core.Game, station: number, rack: string, size: number): { Row }
  local tick = game.state.tick
  if selling.station ~= station or selling.rack ~= rack or selling.size ~= size or tick < selling.tick or tick - selling.tick >= 5 then
    local rows: { Row } = {}
    for _, entry in Catalog.Listing("structure") do
      local info = entry.info
      local module = if info then Structures.moduleById[info.id] else nil
      if info and module and module.citadel and rackOf(module) == rack and (module.fits == nil or module.fits == size) then
        local quote = Core.Query.Quote(game, station, info.id)
        if quote.ask and quote.stock > 0 then
          table.insert(rows, { type = info.id, name = module.name, count = quote.stock, where = "market", ask = quote.ask, can = true, why = "" })
        end
      end
    end
    selling = { station = station, tick = tick, rack = rack, size = size, rows = rows }
  end
  return selling.rows
end

local function drawBrowser(session: Session.Session, game: Core.Game, player: Core.PlayerInfo, status: Core.StarbaseStatus, x: number,
  y: number, w: number, h: number)
  local station = player.docked
  local rack: Rack = RACKS[1]
  for _, each in RACKS do
    if each.id == pickedRack then
      rack = each
    end
  end
  Im.Text("For the slot picked:", x + 10, y + 10, 12, Theme.DIM)
  Im.Strong(rack.name .. (if pickedSlot > 0 then ` {pickedSlot}` else ""), x + 16 + Im.TextWidth("For the slot picked:", 12), y + 10, 12,
    Theme.ACCENT)
  local note = if rack.id == "service" then "What the citadel offers: a market, a refinery, a factory, clone bays."
    elseif rack.id == "shield" then "Its shield: an extender adds to it, a hardener lets less through."
    else `Its guns: one defence module of its size mounts them all.`
  Im.Wrapped(note, x + 10, y + 30, w - 20, 12, Theme.DIM, 16)

  -- Where from: what is to hand, or what the market here sells.
  local tx = x + 10
  for _, each in { { "hand", "To hand" }, { "market", "On the market here" } } do
    local wide = Im.TextWidth(each[2], 13) + 18
    if Im.Toggle(each[2], tx, y + 70, wide, 24, source == each[1], `Citadel:from:{each[1]}`) and source ~= each[1] then
      source = each[1]
      chosen = ""
      Im.ScrollTo("citadel modules", 0)
    end
    tx += wide + 6
  end

  local size = status.tower.size
  local rows: { Row } = {}
  if source == "market" then
    rows = onSale(game, station, rack.id, size)
  else
    for _, place in { "cargo", "hangar", "corporate" } do
      for _, item in Core.Query.Items(game, if place == "cargo" then player.ship else station, place) do
        local module = Structures.moduleById[item.type]
        if module and module.citadel and rackOf(module) == rack.id then
          local can, why = Session.CanDo(session, { kind = "AnchorModule", actor = 0, item = item.id })
          table.insert(rows, { type = item.type, item = item, name = module.name, count = item.quantity,
            where = if place == "cargo" then "hold" elseif place == "hangar" then "hangar" else "corporation", can = can,
            why = if can then "" else tostring(why) })
        end
      end
    end
  end
  table.sort(rows, function(a: Row, b: Row): boolean
    if a.can ~= b.can then
      return a.can
    end
    return if a.name ~= b.name then a.name < b.name else a.where < b.where
  end)

  local top = y + 106
  Im.Flat(x, top - 4, w, 1, Theme.EDGE)
  local rowH = 26
  local foot = 46
  local visible = math.max(1, (h - (top - y) - foot) // rowH)
  local first = Im.Scroll("citadel modules", x + 4, top, w - 8, visible * rowH, #rows, visible)
  if #rows == 0 then
    Im.Wrapped(if source == "market" then "The market here sells nothing that goes there."
      else "Nothing in the hold or the hangars goes there. The markets sell citadel modules under Structures.", x + 10, top + 6, w - 20, 13,
      Theme.DIM, 18)
  end
  local picked: Row? = nil
  for _, row in rows do
    if row.type == chosen and (picked == nil or row.can) then
      picked = row
    end
  end
  local function act(row: Row)
    local item = row.item
    if item then
      Session.Do(session, { kind = "AnchorModule", actor = 0, item = item.id })
    elseif Fitting.Market then
      Fitting.Market(row.type)
    end
  end
  for index = 1, visible do
    local row = rows[index + first]
    if row == nil then
      break
    end
    local at = top + (index - 1) * rowH
    local hot, clicked = Im.Area(`Citadel:module:{row.type}`, x + 4, at, w - 18, rowH - 2, true)
    if row.type == chosen then
      Im.Flat(x + 4, at, w - 18, rowH - 2, Theme.ACCENT, 0.14)
    elseif hot then
      Im.Flat(x + 4, at, w - 18, rowH - 2, Theme.TEXT, 0.05)
    end
    ItemIcon.Draw(row.type, x + 10, at + 2, 20)
    Im.Text(shorten(row.name, 28), x + 36, at + 4, 13, if row.can then Theme.TEXT else Theme.DIM)
    local last = if row.ask then Format.Price(row.ask) else `x{row.count} {row.where}`
    Im.TextRight(last, x + w - 18, at + 5, 12, Theme.DIM)
    if hot and not row.can then
      Im.Tip(row.name, row.why)
    end
    if clicked then
      if chosen == row.type and Im.DoublePressed() then
        act(row)
      end
      chosen = row.type
    end
  end

  -- At its foot: what is done with the row picked.
  local bottom = y + h - 38
  if picked then
    local row = picked :: Row
    local label = if row.item then "Fit" else "See it on the market"
    Im.Because(if row.can then nil else row.why)
    if Im.Button(label, x + 10, bottom, 180, 28, row.can and (row.item ~= nil or Fitting.Market ~= nil), if row.item then "Citadel:fit" else
      "Citadel:market") then
      act(row)
    end
    if Im.Button("Info", x + 198, bottom, 60, 28, true, `Info:{row.type}`) then
      Info.Open(row.type)
    end
  else
    Im.Text("Pick a row, then Fit (or double-click it).", x + 10, bottom + 6, 12, Theme.DIM)
  end
end

-- ---------------------------------------------------------------------
-- What it comes to, down the right.

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

local function drawFigures(session: Session.Session, game: Core.Game, player: Core.PlayerInfo, status: Core.StarbaseStatus, x: number,
  y: number, width: number)
  local tower = status.tower
  -- Fuel: what is aboard, what it burns, and loading what is to hand.
  local line = section("Fuel", x, y, width)
  line = figure("Aboard", `{Format.Whole(status.fuel)} blocks`, x, line, width, if status.lit then Theme.TEXT else Theme.CAUTION)
  line = figure("Burns", `{status.burn} an hour`, x, line, width)
  line = figure("Lasts", if status.fuel > 0 then Format.Duration(status.hours * 3600) else "none left", x, line, width,
    if status.hours >= 24 then Theme.TEXT else Theme.CAUTION)
  local fuel: State.Item? = nil
  for _, place in { "cargo", "hangar", "corporate" } do
    for _, item in Core.Query.Items(game, if place == "cargo" then player.ship else player.docked, place) do
      if fuel == nil and item.type == Structures.FUEL.id then
        fuel = item
      end
    end
  end
  local loading: State.Command? = if fuel then { kind = "Fuel", actor = 0, item = (fuel :: State.Item).id } else nil
  Im.Because(if fuel then nil else "No fuel blocks in the hold or the hangars")
  if Im.Button(if fuel then `Load {Format.Whole((fuel :: State.Item).quantity)} blocks` else "Load fuel", x, line + 2, width, 24,
    loading ~= nil and (Session.CanDo(session, loading :: State.Command)), "Citadel:fuel") and loading then
    Session.Do(session, loading)
  end
  line += 32

  -- Each layer: what it has, and what it stops of each kind of damage.
  line = section("Defence", x, line + 6, width)
  local cellAt, cellPitch = x + 108, (width - 108) / 4
  Im.Strong("HP", x + 98 - Im.StrongWidth("HP", 10), line, 10, Theme.DIM)
  for index, color in KINDS do
    local name = KIND_HEADS[index]
    Im.Strong(name, cellAt + (index - 1) * cellPitch + cellPitch - 7 - Im.StrongWidth(name, 10), line, 10, color)
  end
  line += 15
  local vitals = status.vitals
  for _, layer in { { "Shield", "shield", tower.shield }, { "Armour", "armor", tower.armor }, { "Structure", "hull", tower.hull } } :: { { any } } do
    local most: number = if vitals then (vitals :: any)[`{layer[2]}Max`] else layer[3]
    Im.Text(layer[1], x, line, 13, Theme.DIM)
    -- (a citadel's run to millions: written short, to stand clear of the layer's name)
    local text = if most >= 1e6 then string.format("%.2fM", most / 1e6) else Format.Whole(math.floor(most + 0.5))
    Im.Text(text, x + 98 - Im.TextWidth(text, 13), line, 13, Theme.TEXT)
    local resonances: { number }? = if vitals then (vitals :: any)[`{layer[2]}Resonance`] else nil
    for index, color in KINDS do
      local resonance = if resonances then resonances[index] else 1
      local cell = cellAt + (index - 1) * cellPitch
      local cellWidth = cellPitch - 3
      Im.Flat(cell, line, cellWidth, 16, Theme.CONTROL, 0.5)
      Im.Flat(cell, line + 14, math.max(0, cellWidth * (1 - resonance)), 2, color)
      local stops = string.format("%.0f", (1 - resonance) * 100)
      Im.Text(stops, cell + cellWidth - 4 - Im.TextWidth(stops, 12), line + 1, 12, Theme.TEXT)
    end
    line += 20
  end

  -- How it stands under fire.
  line = section("Condition", x, line + 8, width)
  local function share(value: number): string
    return `{math.ceil(value * 100)}%`
  end
  local hurt = status.shield < 0.999 or status.armor < 0.999 or status.hull < 0.999
  Im.Text(`Shield {share(status.shield)}  armour {share(status.armor)}  structure {share(status.hull)}`, x, line, 13,
    if hurt then Theme.CAUTION else Theme.TEXT)
  line += 19
  local layer = if status.phase == "armor" then "armour" elseif status.phase == "hull" then "structure" else "shield"
  if status.reinforced > 0 then
    Im.Wrapped(`REINFORCED for {Format.Duration(status.reinforced)}: nothing touches it. Then its {layer} is fought.`, x, line, width, 12,
      Theme.CAUTION, 16)
    line += 34
  elseif status.phase and status.phase ~= "shield" then
    Im.Wrapped(`Its {layer} is being fought.`, x, line, width, 12, Theme.CAUTION, 16)
    line += 18
  else
    Im.Wrapped("Shot down to its armour, and again to its structure, it is reinforced for an hour.", x, line, width, 12, Theme.DIM, 16)
    line += 34
  end

  -- Its guns, and how far it holds its own.
  line = section("Guns", x, line + 6, width)
  local module = if status.defenceModule ~= "" then Structures.moduleById[status.defenceModule] else nil
  if module and module.defence then
    for _, group in Structures.CITADEL_DEFENCE[tower.size] do
      line = figure(Types.Info(CitadelGuns.Weapon(module.defence, group.range, group.size)).name, `x{group.count}`, x, line, width)
    end
    Im.Wrapped("Each fires on its own: on pirates, on whoever strikes it or your ships, and on your war enemies.", x, line, width, 12,
      Theme.DIM, 16)
    line += 34
  else
    Im.Wrapped("No defence module: it has no guns.", x, line, width, 12, Theme.CAUTION, 16)
    line += 20
  end
  line = figure("Tethers your ships within", Format.Distance(Structures.TETHER), x, line, width)

  -- What it costs to run.
  local running = status.running
  line = section("Running", x, line + 8, width)
  line = figure("Fuel burnt so far", `{Format.Whole(running.used)} blocks`, x, line, width)
  figure("Fuel a day", `{Format.Whole(running.fuelADay)} cr`, x, line, width, if status.lit then Theme.TEXT else Theme.DIM)
end

-- ---------------------------------------------------------------------
-- The whole

function CitadelFitting.Draw(session: Session.Session, game: Core.Game, player: Core.PlayerInfo, status: Core.StarbaseStatus, x: number,
  y: number, w: number, h: number)
  local station = player.docked
  local tower = status.tower
  -- (a citadel module carried here from the inventory is fitted)
  local carried = Im.Drop("Citadel:onto", x, y, w, h)
  if carried and carried.items then
    for _, id in carried.items :: { number } do
      local item = game.state.items[id]
      if item and Structures.moduleById[item.type] then
        Session.Do(session, { kind = "AnchorModule", actor = 0, item = item.id })
      elseif item and item.type == Structures.FUEL.id then
        Session.Do(session, { kind = "Fuel", actor = 0, item = item.id })
      elseif item then
        Session.Say(session, `{Types.Info(item.type).name} is not something a citadel is fitted with`, "bad")
      end
    end
  end
  local note = "carry a module here from the inventory, or double-click it in the list"
  Im.Text(note, x + w - 12 - Im.TextWidth(note, 12), y + 11, 12, Theme.DIM)
  Im.Flat(x + 1, y + 32, w - 2, 1, Theme.EDGE)
  local top, room = y + 33, h - 34
  Im.Flat(x + LEFT_W, top, 1, room, Theme.EDGE)
  Im.Flat(x + w - RIGHT_W, top, 1, room, Theme.EDGE)

  drawBrowser(session, game, player, status, x + 1, top, LEFT_W - 1, room)

  -- The middle: the citadel in its wheel, its name over it.
  local middle = w - LEFT_W - RIGHT_W
  local cx, cy = math.floor(x + LEFT_W + middle / 2), top + 236
  local title = string.upper(shorten(tower.name, 24))
  local titleWidth = Im.HeadingWidth(title, 16)
  local across = 28 + titleWidth + 12 + 46
  ItemIcon.Draw(tower.id, cx - across / 2, top + 10, 22)
  Im.Heading(title, cx - across / 2 + 28, top + 13, 16, Theme.TEXT)
  if Im.Button("Info", cx + across / 2 - 46, top + 10, 46, 22, true, `Info:{tower.id}`) then
    Info.Open(tower.id)
  end
  drawWheel(session, status, station, cx, cy)

  -- Under it: how full its slots are, and whether it is lit.
  local bx, bw = x + LEFT_W + 28, middle - 56
  local by = cy + RING + 50
  useBar("Services", status.services, status.serviceSlots, Theme.ACCENT, bx, by, bw)
  useBar("Shield modules", status.shields, status.shieldSlots, Theme.SHIELD, bx, by + 22, bw)
  useBar("Defence module", if status.defenceModule ~= "" then 1 else 0, 1, Theme.ARMOR, bx, by + 44, bw)
  by += 74
  if status.sealed > 0 then
    Im.Text(`SEALED: it opens in {Format.Duration(status.sealed)}.`, bx, by, 13, Theme.CAUTION)
  elseif not status.anchored then
    Im.Text(`Anchoring: done in {Format.Duration(status.wait)}.`, bx, by, 13, Theme.CAUTION)
  elseif status.lit then
    Im.Text("Lit: its services have power and its guns are manned.", bx, by, 13, Theme.GOOD)
  else
    Im.Text("DARK: no fuel. Its services and its guns give nothing.", bx, by, 13, Theme.CAUTION)
  end
  by += 22
  -- The pilot's claim on the system, if a claim module here makes one.
  local here = Core.Query.Player(game).system
  local how, gone, takes = Core.Query.Claim(game, here)
  if how == "claiming" then
    Im.Text(`Claiming this system: {gone} of {takes} hours`, bx, by, 13, Theme.ACCENT)
  elseif how == "contested" then
    Im.Text("The claim makes nothing: the system is somebody's.", bx, by, 13, Theme.CAUTION)
  elseif how == "held" then
    Im.Text(if gone > 0 then `Yours, but no beacon is lit: let go in {takes - gone} h` else "This system is yours", bx, by, 13,
      if gone > 0 then Theme.CAUTION else Theme.GOOD)
  end

  -- Who may dock at it: its owner's side alone, or anybody not hostile, at a tax its owner takes of what they trade
  -- and have done there (Assets/Starbases' SetAccess; a point at a time, to the most there is).
  local accessY = y + h - 82
  Im.Text("Access", bx, accessY + 4, 13, Theme.DIM)
  local closed = not status.open
  if Im.Toggle("Closed", bx + 70, accessY, 76, 24, closed, "Citadel:closed") and not closed then
    Session.Do(session, { kind = "SetAccess", actor = 0, open = false })
  end
  if Im.Toggle("Open", bx + 152, accessY, 64, 24, status.open, "Citadel:open") and closed then
    Session.Do(session, { kind = "SetAccess", actor = 0, open = true, tax = status.tax })
  end
  if Im.Inside(bx + 70, accessY, 146, 24) then
    Im.Tip("Access", if closed then "Only you and your corporation dock here" else "Anybody not hostile may dock here, and pays your tax")
  end
  if status.open then
    local points = math.floor(status.tax * 100 + 0.5)
    local wanted = asked
    if wanted and wanted.station == station and wanted.points ~= points then
      points = wanted.points
    else
      asked = nil
    end
    local most = math.floor(Starbases.TAX_MOST * 100 + 0.5)
    Im.Text("tax", bx + 232, accessY + 4, 13, Theme.DIM)
    if Im.Button("-", bx + 262, accessY, 24, 24, points > 0, "Citadel:tax:down") then
      Session.Do(session, { kind = "SetAccess", actor = 0, open = true, tax = (points - 1) / 100 })
      asked = { station = station, points = points - 1 }
    end
    local shown = `{points}%`
    Im.Text(shown, bx + 310 - Im.TextWidth(shown, 13) / 2, accessY + 4, 13, Theme.TEXT)
    if Im.Button("+", bx + 334, accessY, 24, 24, points < most, "Citadel:tax:up") then
      Session.Do(session, { kind = "SetAccess", actor = 0, open = true, tax = (points + 1) / 100 })
      asked = { station = station, points = points + 1 }
    end
  end

  -- At its foot: taking it down (with nothing in it, it says why not when it cannot be).
  if Im.Button("Take down", bx + bw - 130, y + h - 40, 130, 28, true, "Tower:down") then
    Session.Do(session, { kind = "UnanchorTower", actor = 0 })
  end

  drawFigures(session, game, player, status, x + w - RIGHT_W + 14, top + 14, RIGHT_W - 28)
end

return CitadelFitting
