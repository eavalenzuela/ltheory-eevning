--!strict
-- The colonies window: a planet's deposits, and for a planet the pilot
-- has a colony on, its facilities and its store.
--
-- Open in space or docked (a colony is run from anywhere): from the
-- Colonies button, or from a selected planet. A window (Game/UI/Windows)
-- laid out as the market is since 2026-11-16: the pilot's colonies down
-- the left ("Colony:pick:<planet>"), the planet picked in the middle
-- with its deposits and its facilities, and its store on the right. It
-- reads the Core through queries and acts on it only through the
-- Session. Its buttons' names, for a script (Im.Press):
-- "Colony:close", "Colony:next", "Colony:deploy", "Extractor:<raw>",
-- "Processor:<product>", "Storage", "Programme:<facility>:<hours>",
-- "Remove:<facility>", "Take:<type>".

local Core = require("@lt/Core/Api")
local Format = require("@lt/Game/Format")
local Im = require("@lt/Game/UI/Im")
local List = require("@lt/Game/UI/List")
local Info = require("@lt/Game/UI/Info")
local ItemIcon = require("@lt/Game/UI/ItemIcon")
local Planets = require("@lt/Core/Data/Planets")
local Session = require("@lt/Game/Session")
local Signs = require("@lt/Game/UI/Signs")
local State = require("@lt/Core/Kernel/State")
local Theme = require("@lt/Game/UI/Theme")
local Types = require("@lt/Core/Data/Types")
local Windows = require("@lt/Game/UI/Windows")

local Colony = {}

Colony.ID = "colony"
Colony.WIDTH = 1060
Colony.HEIGHT = 600

local current: Session.Session? = nil
local showing = 0     -- the planet shown; 0 for the first colony there is

-- Open the window, on a planet if one is given.
function Colony.Open(planet: number?)
  showing = planet or showing
  Windows.Open(Colony.ID)
  Windows.Raise(Colony.ID)
end

function Colony.Close()
  Windows.Close(Colony.ID)
end

function Colony.IsOpen(): boolean
  return Windows.IsOpen(Colony.ID)
end

-- The planet shown, or 0.
function Colony.Showing(): number
  return if Colony.IsOpen() then showing else 0
end

-- Once a frame, before the windows are drawn: whose game it is.
function Colony.Frame(session: Session.Session)
  current = session
end

local function title(word: string): string
  return string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
end

-- A bar of what is used of what there is, with the figures over it.
local function supply(label: string, used: number, capacity: number, unit: string, x: number, y: number, width: number)
  Im.Text(label, x, y, 12, Theme.DIM)
  Im.TextRight(`{Format.Whole(used)} / {Format.Whole(capacity)} {unit}`, x + width, y, 12, Theme.TEXT)
  Im.Flat(x, y + 18, width, 5, Theme.EDGE)
  Im.Flat(x, y + 18, width * math.clamp(used / math.max(1, capacity), 0, 1), 5, if used > capacity * 0.9 then Theme.CAUTION else Theme.ACCENT)
end

-- The command centre in the hold of the pilot's ship, if there is one.
local function centre(session: Session.Session): number
  local game = session.game
  for _, item in Core.Query.Items(game, game.state.player.ship, "cargo") do
    if item.type == Planets.CENTRE.id then
      return item.id
    end
  end
  return 0
end

local TREE_W, STORE_W = 220, 320
local DEPOSIT_COLUMNS: { List.Column } = {
  { id = "raw", label = "Deposit", width = 0 }, { id = "rich", label = "Richness", width = 70, right = true },
  { id = "act", label = "", width = 216, right = true },
}
local FACILITY_COLUMNS: { List.Column } = {
  { id = "what", label = "Facility", width = 0 }, { id = "doing", label = "Doing", width = 150 },
  { id = "act", label = "", width = 236, right = true },
}

-- A planet's sign, by its kind (Describe/System's 'variety'): the owner's
-- picks, 2026-11-24.
local PLANET_SIGNS: { [string]: string } = { temperate = "temperate", ocean = "ocean", barren = "barren", lava = "lava",
  ice = "iceplanet", gas = "gasgiant" }
local function planetSign(body: any): string
  return if body and body.kind == "planet" then PLANET_SIGNS[body.variety or ""] or "" else ""
end

-- Down the left: the pilot's colonies, and the planet shown if it is none of them.
local function drawColonies(game: Core.Game, mine: { number }, x: number, y: number, w: number, h: number)
  local listed = table.clone(mine)
  if showing ~= 0 and not table.find(listed, showing) then
    table.insert(listed, showing)
  end
  Im.Text("YOUR COLONIES", x + 10, y + 10, 11, Theme.ACCENT)
  local top = y + 30
  local first, visible = List.Body("colonies", x, top, w, h - 30 - List.FOOT, #listed)
  for index = 1, visible do
    local planet = listed[index + first]
    if planet == nil then
      break
    end
    local body = Core.Query.Body(game, planet)
    local rowY = top + (index - 1) * List.ROW
    local hot, clicked = List.Row(x, rowY, w - 5, planet == showing, `Colony:pick:{planet}`)
    local cell = { x = x + 10, w = w - 30, right = false }
    -- (each planet's sign before its name)
    local signed = Signs.Draw(planetSign(body), x + 19, rowY + 12, Signs.SIZE, if table.find(mine, planet) then Theme.ACCENT else Theme.DIM)
    List.Text(if body then body.name else "?", cell, rowY, hot, if table.find(mine, planet) then Theme.TEXT else Theme.DIM, 14, false,
      if signed then 22 else 0)
    if clicked then
      showing = planet
    end
  end
  if #listed == 0 then
    Im.Wrapped("You have no colonies. A market sells a Planetary Command Centre, under Structures. Carry it to a planet, select the planet, and put it down from orbit.",
      x + 10, top + 6, w - 20, 13, Theme.DIM)
  end
  -- (the next of them, for a script, as it always was)
  if #mine > 1 or (#mine == 1 and mine[1] ~= showing) then
    if Im.Hook("Colony:next", true) then
      local at = table.find(mine, showing) or 0
      showing = mine[at % #mine + 1]
    end
  end
  List.Foot(x, y + h - List.FOOT, w, `{#mine} {if #mine == 1 then "colony" else "colonies"}`, "")
end

local function drawPlanet(session: Session.Session, game: Core.Game, body: any, status: Core.ColonyStatus?, x: number, y: number, w: number,
  h: number)
  local left, right = x + 14, x + w - 14
  local deposits: { Planets.Deposit } = if status then status.deposits else Core.Query.Deposits(game, showing)
  -- (its sign, large, before its name; and, a colony of the pilot's, the command centre's before that it is theirs)
  local named = if Signs.Draw(planetSign(body), left + 16, y + 26, 32, Theme.ACCENT) then left + 40 else left
  Im.Strong(List.Cut(body.name, w - 28 - (named - left), 17, true), named, y + 10, 17, Theme.TEXT)
  local kind = if body.kind == "planet" then `{title(body.variety or "")} planet` else body.kind
  Im.Text(kind, named, y + 34, 13, Theme.DIM)
  if status and status.mine then
    local after = named + Im.TextWidth(kind, 13) + 14
    local mark = if Signs.Draw("command", after + 7, y + 42, 14, Theme.GOOD) then after + 18 else after
    Im.Text("your colony", mark, y + 34, 13, Theme.GOOD)
  end
  local line = y + 60
  if status and status.mine then
    local third = (right - left - 24) / 3
    supply("Powergrid", status.powergrid, Planets.CENTRE.powergrid, "MW", left, line, third)
    supply("CPU", status.cpu, Planets.CENTRE.cpu, "tf", left + third + 12, line, third)
    supply("Store", status.used, status.room, "m3", left + 2 * (third + 12), line, third)
    line += 36
  elseif #deposits == 0 then
    Im.Text("Nothing can be worked here.", left, line, 14, Theme.DIM)
    return
  else
    Im.Text("No colony here.", left, line + 4, 14, Theme.DIM)
    local command: State.Command = { kind = "DeployColony", actor = 0, item = centre(session), target = showing }
    local can, whyNot = Session.CanDo(session, command)
    Im.Tone("primary")
    if Im.Button("Put down a command centre", right - 240, line - 2, 240, 28, can, "Colony:deploy") then
      Session.Do(session, command)
    end
    Im.Because(whyNot)
    line += 36
  end

  -- What the planet has, and (at a colony) what to raise on it.
  local layout = List.Columns(DEPOSIT_COLUMNS, x, w - 6)
  List.Head("deposits", x, line, w, DEPOSIT_COLUMNS, layout, "", false)
  line += List.HEAD
  for _, deposit in deposits do
    local raw = Planets.rawById[deposit.raw]
    local product = Planets.productOf[raw.id]
    local hot = List.Row(x, line, w - 5, false)
    ItemIcon.Draw(raw.id, layout.raw.x, line + 3, 19)
    if hot then
      Im.Tip(raw.name, `makes {product.name}`)
    end
    Info.Name(raw.id, raw.name, layout.raw.x + 26, line + 5, 14, Theme.TEXT)
    List.Text(`{math.floor(deposit.richness * 100 + 0.5)}%`, layout.rich, line, false,
      if deposit.richness >= 1.1 then Theme.GOOD elseif deposit.richness < 0.8 then Theme.CAUTION else Theme.DIM, 13)
    if status and status.mine then
      local ax = layout.act.x + layout.act.w - 210
      local extract: State.Command = { kind = "BuildFacility", actor = 0, target = showing, type = "extractor", what = raw.id }
      local canExtract, whyNotExtract = Session.CanDo(session, extract)
      if Im.Button("Extractor", ax, line + 2, 102, List.ROW - 4, canExtract, `Extractor:{raw.id}`) then
        Session.Do(session, extract)
      end
      Im.Because(whyNotExtract)
      local process: State.Command = { kind = "BuildFacility", actor = 0, target = showing, type = "processor", what = product.id }
      local canProcess, whyNotProcess = Session.CanDo(session, process)
      if Im.Button("Processor", ax + 108, line + 2, 102, List.ROW - 4, canProcess, `Processor:{product.id}`) then
        Session.Do(session, process)
      end
      Im.Because(whyNotProcess)
    else
      List.Text(`makes {product.name}`, layout.act, line, false, Theme.DIM, 13)
    end
    line += List.ROW
  end
  if status == nil or not status.mine then
    return
  end
  local store: State.Command = { kind = "BuildFacility", actor = 0, target = showing, type = "storage" }
  local canStore, whyNot = Session.CanDo(session, store)
  line += 6
  if Im.Button("Add storage", right - 110, line, 110, 24, canStore, "Storage") then
    Session.Do(session, store)
  end
  Im.Because(whyNot)
  Im.Text(`an extractor {Format.Whole(Planets.facilityById["extractor"].cost)} cr, a processor {Format.Whole(Planets.facilityById["processor"].cost)} cr, storage {Format.Whole(Planets.facilityById["storage"].cost)} cr`,
    left, line + 5, 12, Theme.DIM)
  line += 34

  -- The facilities there are.
  local fLayout = List.Columns(FACILITY_COLUMNS, x, w - 6)
  List.Head("facilities head", x, line, w, FACILITY_COLUMNS, fLayout, "", false)
  line += List.HEAD
  local room = y + h - line - List.FOOT
  local first, visible = List.Body("facilities", x, line, w, room, #status.facilities)
  if #status.facilities == 0 then
    Im.Text("None yet. An extractor brings a raw material up; a processor makes of it something worth carrying.", x + 12, line + 8,
      13, Theme.DIM)
  end
  for row = 1, visible do
    local facility = status.facilities[row + first]
    if facility == nil then
      break
    end
    local rowY = line + (row - 1) * List.ROW
    local hot = List.Row(x, rowY, w - 5, false)
    local what = if facility.kind == "storage" then "Storage" elseif facility.what ~= "" then Types.Info(facility.what).name else ""
    -- (its sign: extractor, processor or storage)
    local signed = Signs.Draw(facility.kind, fLayout.what.x + 9, rowY + 12, Signs.SIZE, Theme.ACCENT)
    List.Text(if what ~= "" then what else title(facility.kind), fLayout.what, rowY, hot, Theme.TEXT, 14, false, if signed then 22 else 0,
      `{title(facility.kind)} {facility.id}`)
    if facility.kind == "extractor" then
      List.Text(if facility.working then `{Format.Duration(facility.left)} left, {Format.Whole(facility.rate)} a cycle` else "idle: start it",
        fLayout.doing, rowY, hot, if facility.working then Theme.GOOD else Theme.CAUTION, 12)
      for index, hours in Planets.PROGRAMMES do
        local start: State.Command = { kind = "StartExtraction", actor = 0, target = showing, pin = facility.id, hours = hours }
        if Im.Button(`{hours}h`, fLayout.act.x + (index - 1) * 38, rowY + 2, 35, List.ROW - 4, true, `Programme:{facility.id}:{hours}`) then
          Session.Do(session, start)
        end
      end
    elseif facility.kind == "processor" then
      List.Text(if facility.working then `making, {Format.Duration(facility.left)}` else "waiting for material", fLayout.doing, rowY, hot,
        if facility.working then Theme.GOOD else Theme.DIM, 12)
    end
    local remove: State.Command = { kind = "RemoveFacility", actor = 0, target = showing, pin = facility.id }
    if Im.Button("Remove", fLayout.act.x + fLayout.act.w - 70, rowY + 2, 70, List.ROW - 4, (Session.CanDo(session, remove)),
      `Remove:{facility.id}`) then
      Session.Do(session, remove)
    end
  end
  List.Foot(x, y + h - List.FOOT, w, `{#status.facilities} {if #status.facilities == 1 then "facility" else "facilities"}`, "")
end

-- The right: what is in the store, and what a ship here can take of it.
local function drawStore(session: Session.Session, status: Core.ColonyStatus?, x: number, y: number, w: number, h: number)
  Im.Text("STORE", x + 12, y + 10, 11, Theme.ACCENT)
  if status == nil or not status.mine then
    Im.Text("No colony here.", x + 12, y + 32, 13, Theme.DIM)
    return
  end
  Im.Text(if status.near then "your ship is in reach" else "fly to the planet to take goods up", x + 12, y + 30, 12,
    if status.near then Theme.GOOD else Theme.DIM)
  local top = y + 52
  local first, visible = List.Body("colonystore", x, top, w, h - 52 - List.FOOT, #status.store)
  if #status.store == 0 then
    Im.Text("empty", x + 12, top + 6, 13, Theme.DIM)
  end
  for row = 1, visible do
    local held = status.store[row + first]
    if held == nil then
      break
    end
    local rowY = top + (row - 1) * List.ROW
    local hot = List.Row(x, rowY, w - 5, false)
    ItemIcon.Draw(held.type, x + 10, rowY + 3, 19)
    local cell = { x = x + 36, w = w - 36 - 100, right = false }
    List.Text(`{Types.Info(held.type).name} x{Format.Whole(held.quantity)}`, cell, rowY, hot, Theme.TEXT, 13)
    local take: State.Command = { kind = "Export", actor = 0, target = showing, type = held.type, quantity = held.fits }
    if Im.Button(if held.fits > 0 then `Take {Format.Whole(held.fits)}` else "Take", x + w - 98, rowY + 2, 88, List.ROW - 4, held.fits > 0,
      `Take:{held.type}`) then
      Session.Do(session, take)
    end
  end
  List.Foot(x, y + h - List.FOOT, w, `{#status.store} {if #status.store == 1 then "kind" else "kinds"} of goods`, "")
  local _ = session
end

Windows.Kind(Colony.ID, function(_: Windows.Window, x: number, y: number, w: number, h: number)
  local session = current
  if session == nil then
    return
  end
  local was = Im.Plain(true)
  if Im.Hook("Colony:close", true) then
    Colony.Close()
  end
  local game = session.game
  -- Which planet: the one asked for, else the first colony there is.
  local mine = Core.Query.Colonies(game)
  if showing == 0 or Core.Query.Body(game, showing) == nil then
    showing = mine[1] or 0
  end
  drawColonies(game, mine, x + 1, y, TREE_W - 1, h)
  Im.Flat(x + TREE_W, y, 1, h, Theme.EDGE)
  local middleW = w - TREE_W - STORE_W
  local body = Core.Query.Body(game, showing)
  local status = if body then Core.Query.Colony(game, showing) else nil
  if body then
    drawPlanet(session, game, body, status, x + TREE_W + 1, y, middleW - 1, h)
  else
    Im.Text("Pick a planet: select one in space, and Colonies.", x + TREE_W + 14, y + 14, 14, Theme.DIM)
  end
  Im.Flat(x + TREE_W + middleW, y, 1, h, Theme.EDGE)
  drawStore(session, status, x + TREE_W + middleW + 1, y, STORE_W - 2, h)
  Im.Plain(was)
end)
Windows.Make(Colony.ID, Colony.ID, "Colonies", 300, 150, Colony.WIDTH, Colony.HEIGHT, 980, 480, nil)
Windows.Icon(Colony.ID, "colonies")

return Colony
