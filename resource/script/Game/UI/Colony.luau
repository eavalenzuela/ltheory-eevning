--!strict
-- The colonies window: a planet's deposits, and for a planet the pilot
-- has a colony on, its facilities and its store.
--
-- Open in space or docked (a colony is run from anywhere): from the
-- Colonies button, or from a selected planet. Drawn every frame with
-- Game/UI/Im; it reads the Core through queries and acts on it only
-- through the Session. Its buttons' names, for a script (Im.Press):
-- "Colony:close", "Colony:next", "Colony:deploy", "Extractor:<raw>",
-- "Processor:<product>", "Storage", "Programme:<facility>:<hours>",
-- "Remove:<facility>", "Take:<type>".

local Core = require("@lt/Core/Api")
local Format = require("@lt/Game/Format")
local Im = require("@lt/Game/UI/Im")
local Info = require("@lt/Game/UI/Info")
local ItemIcon = require("@lt/Game/UI/ItemIcon")
local Planets = require("@lt/Core/Data/Planets")
local Session = require("@lt/Game/Session")
local State = require("@lt/Core/Kernel/State")
local Types = require("@lt/Core/Data/Types")

local Colony = {}

Colony.WIDTH = 468
Colony.HEIGHT = 660

local GOOD = vector.create(0.45, 0.85, 0.55)

local open = false
local showing = 0     -- the planet shown; 0 for the first colony there is

-- Open the window, on a planet if one is given.
function Colony.Open(planet: number?)
  open = true
  showing = planet or showing
end

function Colony.Close()
  open = false
end

function Colony.IsOpen(): boolean
  return open
end

-- The planet shown, or 0.
function Colony.Showing(): number
  return if open then showing else 0
end

local function shorten(text: string, limit: number): string
  return if #text > limit then string.sub(text, 1, limit - 1) .. "." else text
end

local function title(word: string): string
  return string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
end

-- A bar of what is used of what there is, with the figures over it.
local function supply(label: string, used: number, capacity: number, unit: string, x: number, y: number, width: number)
  Im.Text(label, x, y, 12, Im.DIM)
  Im.TextRight(`{Format.Whole(used)} / {Format.Whole(capacity)} {unit}`, x + width, y, 12, Im.TEXT)
  Im.Fill(x, y + 18, width, 5, Im.DIM, 0.25)
  Im.Fill(x, y + 18, width * math.clamp(used / math.max(1, capacity), 0, 1), 5, if used > capacity * 0.9 then Im.WARN else Im.ACCENT, 0.95)
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

function Colony.Draw(session: Session.Session, x: number, y: number)
  if not open then
    return
  end
  local game = session.game
  local width, height = Colony.WIDTH, Colony.HEIGHT
  local left, right = x + 16, x + width - 16
  Im.Panel(x, y, width, height)
  Im.Heading("COLONIES", left, y + 12, 16, Im.DIM)
  if Im.Button("x", x + width - 38, y + 10, 24, 24, true, "Colony:close") then
    open = false
    return
  end

  -- Which planet: the one asked for, else the first colony there is.
  local mine = Core.Query.Colonies(game)
  if showing == 0 or Core.Query.Body(game, showing) == nil then
    showing = mine[1] or 0
  end
  if #mine > 1 or (#mine == 1 and mine[1] ~= showing) then
    if Im.Button(`Next of {#mine}`, x + width - 138, y + 10, 92, 24, true, "Colony:next") then
      local at = table.find(mine, showing) or 0
      showing = mine[at % #mine + 1]
    end
  end
  local body = Core.Query.Body(game, showing)
  if showing == 0 or body == nil then
    Im.Text("You have no colonies.", left, y + 50, 14, Im.TEXT)
    Im.Text("A market sells a Planetary Command Centre, under", left, y + 78, 13, Im.DIM)
    Im.Text("Structures. Carry it to a planet, select the planet,", left, y + 96, 13, Im.DIM)
    Im.Text("and put it down from orbit.", left, y + 114, 13, Im.DIM)
    return
  end

  local status = Core.Query.Colony(game, showing)
  local deposits: { Planets.Deposit } = if status then status.deposits else Core.Query.Deposits(game, showing)
  Im.Heading(shorten(body.name, 30), left, y + 42, 17, Im.TEXT)
  local kind = if body.kind == "planet" then `{title((body :: any).variety or "")} planet` else body.kind
  Im.Text(kind, left, y + 66, 13, Im.DIM)
  local line = y + 92

  if status and status.mine then
    local third = (right - left - 24) / 3
    supply("Powergrid", status.powergrid, Planets.CENTRE.powergrid, "MW", left, line, third)
    supply("CPU", status.cpu, Planets.CENTRE.cpu, "tf", left + third + 12, line, third)
    supply("Store", status.used, status.room, "m3", left + 2 * (third + 12), line, third)
    line += 38
  elseif #deposits == 0 then
    Im.Text("Nothing can be worked here.", left, line, 13, Im.DIM)
    return
  else
    Im.Text("No colony here.", left, line, 13, Im.DIM)
    local command: State.Command = { kind = "DeployColony", actor = 0, item = centre(session), target = showing }
    local can, whyNot = Session.CanDo(session, command)
    if Im.Button("Put down a command centre", left + 130, line - 4, 220, 24, can, "Colony:deploy") then
      Session.Do(session, command)
    end
    if not can then
      Im.Text(tostring(whyNot), left + 130, line + 24, 12, Im.WARN)
    end
    line += 50
  end

  -- What the planet has, and (at a colony) what to raise on it.
  Im.Heading("DEPOSITS", left, line, 15, Im.DIM)
  line += 24
  for _, deposit in deposits do
    local raw = Planets.rawById[deposit.raw]
    local product = Planets.productOf[raw.id]
    ItemIcon.Draw(raw.id, left, line + 1, 20)
    Info.Name(raw.id, raw.name, left + 26, line + 3, 13, Im.TEXT)
    Im.Text(`{math.floor(deposit.richness * 100 + 0.5)}%`, left + 150, line + 3, 13,
      if deposit.richness >= 1.1 then GOOD elseif deposit.richness < 0.8 then Im.WARN else Im.DIM)
    if status and status.mine then
      local extract: State.Command = { kind = "BuildFacility", actor = 0, target = showing, type = "extractor", what = raw.id }
      if Im.Button("Extractor", left + 200, line, 96, 21, (Session.CanDo(session, extract)), `Extractor:{raw.id}`) then
        Session.Do(session, extract)
      end
      local process: State.Command = { kind = "BuildFacility", actor = 0, target = showing, type = "processor", what = product.id }
      if Im.Button("Processor", left + 302, line, 96, 21, (Session.CanDo(session, process)), `Processor:{product.id}`) then
        Session.Do(session, process)
      end
    else
      Im.Text(`makes {product.name}`, left + 200, line + 3, 13, Im.DIM)
    end
    line += 25
  end
  if status == nil or not status.mine then
    return
  end
  local store: State.Command = { kind = "BuildFacility", actor = 0, target = showing, type = "storage" }
  local canStore, whyNot = Session.CanDo(session, store)
  if Im.Button("Storage", left + 200, line, 96, 21, canStore, "Storage") then
    Session.Do(session, store)
  end
  local costs = `{Format.Whole(Planets.facilityById["extractor"].cost)} / {Format.Whole(Planets.facilityById["processor"].cost)} / `
    .. `{Format.Whole(Planets.facilityById["storage"].cost)} cr`
  Im.Text(if canStore or whyNot == nil then costs else shorten(whyNot, 30), left, line + 3, 12, if canStore then Im.DIM else Im.WARN)
  line += 34

  -- The facilities there are.
  Im.Heading(`FACILITIES  {#status.facilities}`, left, line, 15, Im.DIM)
  line += 24
  if #status.facilities == 0 then
    Im.Text("None yet. An extractor brings a raw material up, a", left, line, 12, Im.DIM, 0.8)
    Im.Text("processor makes of it something worth carrying.", left, line + 16, 12, Im.DIM, 0.8)
  end
  local visible = 8
  local first = Im.Scroll("facilities", left - 4, line, width - 24, visible * 25, #status.facilities, visible)
  for row = 1, visible do
    local facility = status.facilities[row + first]
    if facility == nil then
      break
    end
    local what = if facility.what ~= "" then Types.Info(facility.what).name else ""
    Im.Text(`{facility.id}`, left, line + 3, 12, Im.DIM)
    Im.Text(shorten(if facility.kind == "storage" then "Storage" else what, 18), left + 20, line + 3, 13, Im.TEXT)
    if facility.kind == "extractor" then
      if facility.working then
        Im.Text(`{Format.Duration(facility.left)}  {Format.Whole(facility.rate)}`, left + 150, line + 3, 12, GOOD)
      else
        Im.Text("idle: start", left + 150, line + 3, 12, Im.WARN)
      end
      for index, hours in Planets.PROGRAMMES do
        local start: State.Command = { kind = "StartExtraction", actor = 0, target = showing, pin = facility.id, hours = hours }
        if Im.Button(`{hours}h`, left + 250 + (index - 1) * 38, line, 35, 21, true, `Programme:{facility.id}:{hours}`) then
          Session.Do(session, start)
        end
      end
    elseif facility.kind == "processor" then
      Im.Text(if facility.working then `making  {Format.Duration(facility.left)}` else "waiting for material", left + 150, line + 3, 12,
        if facility.working then GOOD else Im.DIM)
    end
    local remove: State.Command = { kind = "RemoveFacility", actor = 0, target = showing, pin = facility.id }
    if Im.Button("x", right - 24, line, 24, 21, (Session.CanDo(session, remove)), `Remove:{facility.id}`) then
      Session.Do(session, remove)
    end
    line += 25
  end
  line = y + 92 + 38 + 24 + 3 * 25 + 34 + 24 + visible * 25 + 10

  -- What is in the store, and what a ship here can take of it.
  Im.Heading("STORE", left, line, 15, Im.DIM)
  Im.TextRight(if status.near then "your ship is in reach" else "fly to the planet to take goods up", right, line + 2, 12,
    if status.near then GOOD else Im.DIM)
  line += 24
  if #status.store == 0 then
    Im.Text("empty", left, line, 13, Im.DIM, 0.6)
  end
  local shown = 6
  local top = Im.Scroll("colonystore", left - 4, line, width - 24, shown * 25, #status.store, shown)
  for row = 1, shown do
    local held = status.store[row + top]
    if held == nil then
      break
    end
    local name = shorten(Types.Info(held.type).name, 20)
    ItemIcon.Draw(held.type, left, line + 1, 20)
    Info.Name(held.type, name, left + 26, line + 3, 13, Im.TEXT)
    Im.Text(`x{Format.Whole(held.quantity)}`, left + 30 + Im.TextWidth(name, 13), line + 3, 12, Im.DIM)
    local take: State.Command = { kind = "Export", actor = 0, target = showing, type = held.type, quantity = held.fits }
    if Im.Button(if held.fits > 0 then `Take {Format.Whole(held.fits)}` else "Take", left + 290, line, 110, 21, held.fits > 0,
      `Take:{held.type}`) then
      Session.Do(session, take)
    end
    line += 25
  end
end

return Colony
