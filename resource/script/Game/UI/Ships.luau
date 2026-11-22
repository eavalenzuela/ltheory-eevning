--!strict
-- Ships: a window of its own (Game/UI/Windows), the third of a station's
-- services to be one. Opened from the dock, at a station; shut when the
-- pilot undocks.
--
-- One list: the pilot's ships that lie at the station they are docked
-- at, each with its hull, how many modules it has fitted and a button
-- that boards it (the one they are aboard says so); and under them the
-- hulls in the hangar here, bought and not yet put together, each with a
-- button that assembles it. A row clicked twice opens the sheet on its
-- hull.
--
-- A script's names are what they were when this was a tab of the docked
-- screen: "Board:<n>" (the ships counted as they are listed) and
-- "Assemble:<type>"; and "Repackage:<n>", which packs a ship up again
-- into a hull for the market (what is fitted and carried goes into the
-- hangar). "Ships", the tab's name, opens the window; and
-- "ships:close" shuts it.

local Core = require("@lt/Core/Api")
local Hulls = require("@lt/Core/Data/Ships")
local Im = require("@lt/Game/UI/Im")
local Info = require("@lt/Game/UI/Info")
local ItemIcon = require("@lt/Game/UI/ItemIcon")
local List = require("@lt/Game/UI/List")
local Session = require("@lt/Game/Session")
local State = require("@lt/Core/Kernel/State")
local Theme = require("@lt/Game/UI/Theme")
local Windows = require("@lt/Game/UI/Windows")

local Ships = {}

Ships.ID = "ships"

local current: Session.Session? = nil

function Ships.Open()
  Windows.Open(Ships.ID)
  Windows.Raise(Ships.ID)
end

function Ships.Close()
  Windows.Close(Ships.ID)
end

function Ships.IsOpen(): boolean
  return Windows.IsOpen(Ships.ID)
end

-- Once a frame, before the windows are drawn: whose game it is, and
-- whether the pilot is docked (the window is a station's: Windows.Berthed).
function Ships.Frame(session: Session.Session, docked: boolean)
  current = session
  Windows.Berthed(Ships.ID, docked)
end

-- A class's name as a heading has it: its first letter a capital.
local function title(s: string): string
  return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2)
end

local COLUMNS: { List.Column } = {
  { id = "name", label = "Ship", width = 0, sort = false }, { id = "hull", label = "Hull", width = 170, sort = false },
  { id = "class", label = "Class", width = 110, sort = false }, { id = "fitted", label = "Fitted", width = 54, right = true, sort = false },
  { id = "act", label = "", width = 214, sort = false },
}

Windows.Kind(Ships.ID, function(_: Windows.Window, x: number, y: number, w: number, h: number)
  local session = current
  if session == nil then
    return
  end
  local game = session.game
  local player = Core.Query.Player(game)
  if player.at == 0 then
    Im.Text("Ships are boarded and put together at a station: dock at one, or enter the field of a tower of yours.", x + 14, y + 14, 14, Theme.DIM)
    return
  end
  local was = Im.Plain(true)
  local station = player.at
  local ships = Core.Query.Ships(game, station)
  local hulls: { State.Item } = {}
  for _, item in Core.Query.Items(game, station, "hangar") do
    if Hulls.byId[item.type] then
      table.insert(hulls, item)
    end
  end
  -- (the rows: a heading, a ship with its place among the ships, a hull to assemble, or a line that says there is none)
  type Line = { heading: string?, count: number?, ship: State.Ship?, index: number?, item: State.Item?, none: string? }
  local lines: { Line } = { { heading = "Your ships here", count = #ships } }
  for index, ship in ships do
    table.insert(lines, { ship = ship, index = index })
  end
  table.insert(lines, { heading = "Hulls in the hangar, to be assembled", count = #hulls })
  for _, item in hulls do
    table.insert(lines, { item = item })
  end
  if #hulls == 0 then
    table.insert(lines, { none = "None. The market sells hulls, under Ships: a hull bought is assembled here." })
  end

  local layout = List.Columns(COLUMNS, x, w - 6)
  List.Head("ships", x, y, w, COLUMNS, layout, "", false)
  local top = y + List.HEAD
  local row = 30
  local first, visible = List.Body("ships list", x, top, w, h - List.HEAD - List.FOOT, #lines, row)
  for at = 1, visible do
    local line = lines[at + first]
    if line == nil then
      break
    end
    local rowY = top + (at - 1) * row
    local textY = rowY + (row - List.ROW) / 2
    local ship, item = line.ship, line.item
    if line.heading then
      List.Group(line.heading, tostring(line.count or 0), x, rowY + (row - List.HEAD), w - 5, nil)
    elseif line.none then
      Im.Text(line.none, x + 12, rowY + 8, 13, Theme.DIM)
    elseif ship then
      local hull = Hulls.byId[ship.type]
      local aboard = ship.id == player.ship
      local hot, _, double = List.Row(x, rowY, w - 5, aboard, nil, row)
      ItemIcon.Draw(hull.id, layout.name.x, rowY + 4, 22)
      List.Text(ship.name, layout.name, textY, hot, Theme.TEXT, 14, true, 30)
      List.Text(hull.name, layout.hull, textY, hot, Theme.DIM, 13)
      List.Text(title(hull.class), layout.class, textY, false, Theme.DIM, 13)
      List.Text(tostring(#Core.Query.Fitted(game, ship.id)), layout.fitted, textY, false, Theme.TEXT, 13)
      if aboard then
        Im.Strong("ABOARD", layout.act.x + 4, rowY + 9, 11, Theme.GOOD)
      else
        local board: State.Command = { kind = "BoardShip", actor = 0, target = ship.id }
        local can, whyNot = Session.CanDo(session, board)
        Im.Because(whyNot)
        if Im.Button("Board", layout.act.x, rowY + 3, 100, 24, can, `Board:{line.index or 0}`) then
          Session.Do(session, board)
        end
        -- (packed up for the market: what is fitted and carried goes into the hangar)
        local pack: State.Command = { kind = "Repackage", actor = 0, target = ship.id }
        local canPack, whyNotPack = Session.CanDo(session, pack)
        Im.Because(whyNotPack)
        -- (its rigs do not come out whole: with any fitted, it says so, and asks again)
        local rigs = 0
        for _, fitted in Core.Query.Items(game, ship.id, "rig") do
          rigs += fitted.quantity
        end
        local packKey = `Repackage:{line.index or 0}`
        local sure = rigs > 0 and Im.Asking(packKey)
        if sure then
          Im.Tone("danger")
        end
        if Im.Button(if sure then "Sure?" else "Repackage", layout.act.x + 106, rowY + 3, 108, 24, canPack, packKey)
          and (rigs == 0 or Im.Confirm(packKey)) then
          Session.Do(session, pack)
        end
        if rigs > 0 and canPack and Im.Inside(layout.act.x + 106, rowY + 3, 108, 24) then
          Im.Tip("Repackage", `{rigs} rig{if rigs == 1 then " is" else "s are"} destroyed in packing it. Press twice.`)
        end
      end
      if double then
        Info.Open(hull.id)
      end
    elseif item then
      local hull = Hulls.byId[item.type]
      local hot, _, double = List.Row(x, rowY, w - 5, false, nil, row)
      ItemIcon.Draw(hull.id, layout.name.x, rowY + 4, 22)
      List.Text(hull.name .. (if item.quantity > 1 then `  x{item.quantity}` else ""), layout.name, textY, hot, Theme.TEXT, 14, false, 30)
      -- (what the pilot wants yet to fly it, where the hull's own name would be)
      local untrained = Core.Query.Untrained(game, item.type)
      List.Text(untrained or "not assembled", layout.hull, textY, hot, if untrained then Theme.CAUTION else Theme.FAINT, 13)
      List.Text(title(hull.class), layout.class, textY, false, Theme.DIM, 13)
      local assemble: State.Command = { kind = "Assemble", actor = 0, item = item.id }
      local can, whyNot = Session.CanDo(session, assemble)
      Im.Because(whyNot)
      if Im.Button("Assemble", layout.act.x, rowY + 3, layout.act.w, 24, can, `Assemble:{item.type}`) then
        Session.Do(session, assemble)
      end
      if double then
        Info.Open(hull.id)
      end
    end
  end
  List.Foot(x, y + h - List.FOOT, w, `{#ships} {if #ships == 1 then "ship" else "ships"} here`, "double-click a row for the sheet on its hull")
  Im.Plain(was)
end)
Windows.Make(Ships.ID, Ships.ID, "Ships", 534, 130, 760, 420, 680, 260, nil)
Windows.Icon(Ships.ID, "ships")

return Ships
