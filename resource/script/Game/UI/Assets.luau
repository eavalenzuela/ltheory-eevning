--!strict
-- The assets window: everything the pilot owns, place by place: the
-- hold, and every station with a ship or goods of theirs in it.
--
-- A window (Game/UI/Windows), open in space or docked: from the
-- inventory's "All assets" button. It only reads the Core, and sets the
-- session's destination: a station somewhere else has a button
-- ("Assets:course:<station>") that sets the pilot's course for its
-- system. Its close button is "assets:close" (Im.Press).

local Catalog = require("@lt/Core/Data/Catalog")
local Core = require("@lt/Core/Api")
local Format = require("@lt/Game/Format")
local Im = require("@lt/Game/UI/Im")
local Info = require("@lt/Game/UI/Info")
local List = require("@lt/Game/UI/List")
local ItemIcon = require("@lt/Game/UI/ItemIcon")
local Session = require("@lt/Game/Session")
local Ships = require("@lt/Core/Data/Ships")
local State = require("@lt/Core/Kernel/State")
local Theme = require("@lt/Game/UI/Theme")
local Types = require("@lt/Core/Data/Types")
local Windows = require("@lt/Game/UI/Windows")

local Assets = {}

Assets.WIDTH = 1100
Assets.HEIGHT = 620

-- The window's id, and whose game it shows (Assets.Frame).
local ID = "assets"
local current: Session.Session? = nil

function Assets.Open()
  Windows.Open(ID)
end

function Assets.Close()
  Windows.Close(ID)
end

function Assets.IsOpen(): boolean
  return Windows.IsOpen(ID)
end

-- Once a frame, before the windows are drawn: whose game it is.
-- The pilot's course for a station of theirs somewhere else: its system,
-- and the station itself, which the autopilot docks at when it is there
-- (Session.Autopilot's 'berth'; the owner, 2026-11-23: the system alone
-- left them at its gate).
function Assets.Course(session: Session.Session, system: number, station: number)
  session.destination, session.goal, session.berth = system, 0, station
  local body = Core.Query.Body(session.game, station)
  Session.Say(session, `Destination: {if body then body.name else "the station"}`)
end

function Assets.Frame(session: Session.Session)
  current = session
end

-- ---------------------------------------------------------------------
-- Set out as the market is (2026-11-16): the places down the left, each
-- with what it holds is worth; what is at the place picked as the one
-- list, sortable by its heads, with a search over everything everywhere
-- ("Assets:search"); and the place itself on the right, with the way
-- there. To a script: "Assets:place:<all, or a station; 0 the hold>",
-- "Assets:course:<station>", "assets:sort:<name, qty, volume, worth, where>".

local TREE_W, DETAIL_W = 230, 260
local COLUMNS: { List.Column } = {
  { id = "name", label = "Name", width = 0 }, { id = "qty", label = "Qty", width = 70, right = true },
  { id = "volume", label = "m3", width = 70, right = true }, { id = "worth", label = "Worth", width = 100, right = true },
  { id = "where", label = "Where", width = 150 },
}
local picked = -1   -- the place picked: a station, 0 the hold, -1 every place
local search = ""
local sortBy, sortDown = "worth", true

-- A row of the list: a ship, or a stack, at a place.
type Row = { place: Core.AssetsAt, ship: State.Ship?, item: State.Item?, corporate: boolean, name: string, quantity: number,
  volume: number, worth: number, type: string }

local function rowsOf(places: { Core.AssetsAt }): { Row }
  local rows: { Row } = {}
  local needle = string.lower(search)
  for _, place in places do
    if picked == -1 or place.station == picked or needle ~= "" then
      for _, ship in place.ships do
        local hull = Ships.byId[ship.type]
        table.insert(rows, { place = place, ship = ship, corporate = false, name = ship.name, quantity = 1, volume = hull.volume,
          worth = hull.basePrice, type = hull.id })
      end
      for _, each in { { place.items, false }, { place.business, true } } :: { { any } } do
        for _, item in each[1] :: { State.Item } do
          local info = Types.Info(item.type)
          table.insert(rows, { place = place, item = item, corporate = each[2], name = info.name, quantity = item.quantity,
            volume = info.volume * item.quantity, worth = info.basePrice * item.quantity, type = item.type })
        end
      end
    end
  end
  if needle ~= "" then
    local kept: { Row } = {}
    for _, row in rows do
      if string.find(string.lower(row.name), needle, 1, true) then
        table.insert(kept, row)
      end
    end
    rows = kept
  end
  table.sort(rows, function(a: Row, b: Row): boolean
    local x: any, y: any
    if sortBy == "name" then
      x, y = a.name, b.name
    elseif sortBy == "qty" then
      x, y = a.quantity, b.quantity
    elseif sortBy == "volume" then
      x, y = a.volume, b.volume
    elseif sortBy == "where" then
      x, y = a.place.name, b.place.name
    else
      x, y = a.worth, b.worth
    end
    if x ~= y then
      return if sortDown then x > y else x < y
    end
    if a.type ~= b.type then
      return Catalog.Before(a.type, b.type)
    end
    return (if a.item then a.item.id elseif a.ship then a.ship.id else 0) < (if b.item then b.item.id elseif b.ship then b.ship.id else 0)
  end)
  return rows
end

local function draw(_: Windows.Window, x: number, y: number, width: number, height: number)
  local session = current
  if session == nil then
    return
  end
  local game = session.game
  local was = Im.Plain(true)
  local places = Core.Query.Assets(game)
  local here = Core.Query.Player(game).system
  local total = game.state.wallet
  local held: { [number]: boolean } = {}
  for _, place in places do
    total += place.worth
    held[place.station] = true
  end
  if picked ~= -1 and not held[picked] then
    picked = -1
  end
  -- (the way to every station somewhere else, for a script, as the list had them)
  for _, place in places do
    local elsewhere = place.station ~= 0 and place.system ~= here
    if elsewhere and Im.Hook(`Assets:course:{place.station}`, session.berth ~= place.station) then
      Assets.Course(session, place.system, place.station)
    end
  end

  -- The places.
  local sought = Im.Words("Assets:search", search, x + 10, y + 10, TREE_W - 20, 26, 40, "Search everything")
  if sought ~= search then
    search = sought
    Im.ScrollTo("assets", 0)
  end
  local top = y + 46
  local tree = { { -1, "Everywhere", total - game.state.wallet, "" } } :: { { any } }
  for _, place in places do
    table.insert(tree, { place.station, place.name, place.worth, place.systemName } :: { any })
  end
  local first, visible = List.Body("asset places", x + 1, top, TREE_W - 2, height - 46 - List.FOOT, #tree, 38)
  for index = 1, visible do
    local entry = tree[index + first]
    if entry == nil then
      break
    end
    local rowY = top + (index - 1) * 38
    local hot, clicked = List.Row(x + 1, rowY, TREE_W - 7, picked == entry[1], `Assets:place:{entry[1]}`, 36)
    local cell = { x = x + 12, w = TREE_W - 30, right = false }
    List.Text(entry[2], cell, rowY - 4, hot, if entry[1] == 0 or entry[1] == -1 then Theme.TEXT else Theme.ACCENT, 13)
    Im.Text(List.Cut(if entry[1] == 0 then "your ship's holds" elseif entry[4] ~= "" then entry[4] else "every place", TREE_W - 120, 11, false),
      x + 12, rowY + 19, 11, Theme.FAINT)
    local worth = `{Format.Whole(entry[3])} cr`
    Im.Text(worth, x + TREE_W - 18 - Im.TextWidth(worth, 11), rowY + 19, 11, Theme.DIM)
    if clicked then
      picked = entry[1]
      Im.ScrollTo("assets", 0)
    end
  end
  List.Foot(x + 1, y + height - List.FOOT, TREE_W - 2, `{#places} places`, "")
  Im.Flat(x + TREE_W, y, 1, height, Theme.EDGE)

  -- What is there.
  local lx = x + TREE_W + 1
  local listW = width - TREE_W - DETAIL_W - 1
  local rows = rowsOf(places)
  local layout = List.Columns(COLUMNS, lx, listW - 6)
  local clicked = List.Head("assets", lx, y, listW, COLUMNS, layout, sortBy, sortDown)
  if clicked then
    if sortBy ~= clicked then
      sortBy, sortDown = clicked, clicked == "worth" or clicked == "qty" or clicked == "volume"
    else
      sortDown = not sortDown
    end
  end
  local bodyTop = y + List.HEAD
  local firstRow, shown = List.Body("assets", lx, bodyTop, listW, height - List.HEAD - List.FOOT, #rows)
  if #rows == 0 then
    Im.Text(if search ~= "" then "Nothing of yours is called that." else "Nothing here.", lx + 12, bodyTop + 10, 14, Theme.DIM)
  end
  for index = 1, shown do
    local row = rows[index + firstRow]
    if row == nil then
      break
    end
    local rowY = bodyTop + (index - 1) * List.ROW
    local hot = List.Row(lx, rowY, listW - 5, false)
    ItemIcon.Draw(row.type, layout.name.x, rowY + 3, 19)
    local note = if row.ship then (if row.ship.id == game.state.player.ship then "you are aboard" else "assembled")
      elseif row.corporate then "the corporation's" else nil
    if hot then
      Im.Tip(row.name, note)
    end
    Info.Name(row.type, List.Cut(row.name, layout.name.w - 30, 14, false), layout.name.x + 26, rowY + 5, 14,
      if row.ship then Theme.ACCENT elseif row.corporate then Theme.CAUTION else Theme.TEXT)
    List.Text(Format.Whole(row.quantity), layout.qty, rowY, false, Theme.TEXT, 13)
    List.Text(Format.Whole(row.volume), layout.volume, rowY, false, Theme.DIM, 13)
    List.Text(Format.Whole(row.worth), layout.worth, rowY, false, Theme.TEXT, 13)
    List.Text(row.place.name, layout.where, rowY, hot, Theme.DIM, 12)
  end
  local sum = 0
  for _, row in rows do
    sum += row.worth
  end
  List.Foot(lx, y + height - List.FOOT, listW, `{#rows} shown, worth {Format.Whole(sum)} cr at base prices`, "")
  Im.Flat(lx + listW, y, 1, height, Theme.EDGE)

  -- The place picked.
  local dx, dw = lx + listW + 15, DETAIL_W - 30
  local line = y + 14
  local place: Core.AssetsAt? = nil
  for _, each in places do
    if each.station == picked then
      place = each
    end
  end
  if place == nil then
    Im.Strong("Everywhere", dx, line, 17, Theme.TEXT)
    line += 30
    Im.Text("ALL YOU OWN", dx, line, 11, Theme.ACCENT)
    Im.Flat(dx, line + 15, dw, 1, Theme.EDGE)
    line += 24
    for _, each in { { "In the wallet", game.state.wallet }, { "In goods and ships", total - game.state.wallet }, { "Together", total } } :: { { any } } do
      Im.Text(each[1], dx, line, 13, Theme.DIM)
      Im.TextRight(`{Format.Whole(each[2])} cr`, dx + dw, line, 13, Theme.TEXT)
      line += 20
    end
  else
    Im.Wrapped(place.name, dx, line, dw, 16, Theme.TEXT)
    line += 44
    Im.Text("WHERE", dx, line, 11, Theme.ACCENT)
    Im.Flat(dx, line + 15, dw, 1, Theme.EDGE)
    line += 24
    Im.Text(if place.station == 0 then "your ship" else place.systemName, dx, line, 14, Theme.TEXT)
    line += 20
    Im.Text(if place.here then "here" elseif place.station == 0 then "with you" else "elsewhere", dx, line, 13,
      if place.here then Theme.GOOD else Theme.DIM)
    line += 30
    Im.Text("HELD THERE", dx, line, 11, Theme.ACCENT)
    Im.Flat(dx, line + 15, dw, 1, Theme.EDGE)
    line += 24
    for _, each in { { "Ships", `{#place.ships}` }, { "Stacks", `{#place.items}` }, { "The corporation's", `{#place.business}` },
      { "Volume", `{Format.Whole(place.volume)} m3` }, { "Worth", `{Format.Whole(place.worth)} cr` } } do
      Im.Text(each[1], dx, line, 13, Theme.DIM)
      Im.TextRight(each[2], dx + dw, line, 13, Theme.TEXT)
      line += 20
    end
    if place.station ~= 0 and place.system ~= here then
      line += 10
      local set = session.destination == place.system and session.berth == place.station
      Im.Tone("primary")
      if Im.Button(if set then "Course set" else "Set course", dx, line, dw, 30, not set, "Assets:course") then
        Assets.Course(session, place.system, place.station)
      end
    end
  end
  Im.Plain(was)
end

Windows.Kind(ID, draw)
Windows.Make(ID, ID, "Assets", 300, 130, Assets.WIDTH, Assets.HEIGHT, 900, 420, nil)
Windows.Icon(ID, "inventory")

return Assets
