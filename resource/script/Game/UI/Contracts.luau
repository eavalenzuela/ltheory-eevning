--!strict
-- Contracts: a window of its own (Game/UI/Windows), and galaxy-wide (the
-- owner, 2026-11-16: "we need to rework the contracts to be
-- universe-wide. They will still be *delivered* in the station they're
-- posted in, i.e. the items don't come to you, but you can buy any
-- contract, from any location"). Opened from the dock, docked or in
-- space.
--
-- Laid out as the market's window is (Game/UI/Market), to the look
-- agreed (Game/UI/Theme, Game/UI/List): its pages along the top (For
-- sale, Wanted, My listings); down the left, what the lots are of (a
-- tree, with a search over it); in the middle every lot of the page on
-- every board, on the one list, narrowed by how far off it may be (the
-- switches over it) and sorted by its heads; on the right the lot
-- picked: what is in it, where it is and how far, what it asks against
-- what it is worth, and buying it (it is delivered to your hangar at the
-- station it is at) or delivering what it wants (from your hangar
-- there), or a way set there. On My listings the right is the putting
-- up of another lot, from the hangar of the station the pilot is at.
--
-- A script's names: "Contracts:sale", "Contracts:wanted",
-- "Contracts:mine" (its pages), "Contracts:kind:<all, hull, print,
-- module, other>", "Contracts:search", "Contracts:reach:<0, 5, 10, 20,
-- any>", "contracts:sort:<lot, where, jumps, price>",
-- "Contracts:lot:<station>:<slot>", "Contracts:buy", "Contracts:deliver",
-- "Contracts:route", "contracts:close". And what they were when the
-- board was the market's: "Category:contracts" opens it, and
-- "Contract:buy:<n>" and "Contract:fill:<n>" are the lots of the board
-- of the station the pilot is at; "Contract:cancel:<n>",
-- "Contract:item:<type>", "ContractQuantity", "ContractPrice",
-- "Contract:all", "Contract:worth", "Contract:list".

local Blueprints = require("@lt/Core/Data/Blueprints")
local Core = require("@lt/Core/Api")
local Format = require("@lt/Game/Format")
local Icons = require("@lt/Game/UI/Icons")
local Im = require("@lt/Game/UI/Im")
local Info = require("@lt/Game/UI/Info")
local ItemIcon = require("@lt/Game/UI/ItemIcon")
local List = require("@lt/Game/UI/List")
local Session = require("@lt/Game/Session")
local State = require("@lt/Core/Kernel/State")
local Theme = require("@lt/Game/UI/Theme")
local Types = require("@lt/Core/Data/Types")
local Windows = require("@lt/Game/UI/Windows")

local Board = {}

Board.ID = "contracts"

local current: Session.Session? = nil
-- The page ("sale", "wanted", "mine"), what the lots are of, the search,
-- how far off they may be (nil: anywhere), how the list is sorted, and
-- the lot picked (its station and its place on the board).
local page = "sale"
local kind = "all"
local search = ""
local reach: number? = nil
local sortBy, sortDown = "jumps", false
local picked = { station = 0, slot = 0 }
-- Putting up a lot: what of the hangar, how many, and at what (0: what it is worth).
local listItem = ""
local listQuantity = 1
local listPrice = 0
local listFresh = false

function Board.Open()
  Windows.Open(Board.ID)
  Windows.Raise(Board.ID)
end

function Board.Close()
  Windows.Close(Board.ID)
end

function Board.IsOpen(): boolean
  return Windows.IsOpen(Board.ID)
end

-- Open My listings with a type of the hangar chosen to put up, as
-- clicking its row there would.
function Board.Choose(type: string): boolean
  if Types.Get(type) == nil then
    return false
  end
  page = "mine"
  listItem, listPrice, listFresh = type, 0, true
  Board.Open()
  return true
end

-- Once a frame, before the windows are drawn: whose game it is.
function Board.Frame(session: Session.Session)
  current = session
end

-- ---------------------------------------------------------------------
-- What lots are of

local KINDS: { { string } } = {
  { "all", "Everything" }, { "hull", "Hulls" }, { "print", "Blueprints" }, { "module", "Modules and charges" }, { "other", "Other" },
}

local function kindOf(lot: { stacks: { { type: string, quantity: number } } }): string
  local first = lot.stacks[1]
  if first == nil then
    return "other"
  end
  if Blueprints.Of(first.type) then
    return "print"
  end
  local category = Types.Info(first.type).category
  return if category == "ship" then "hull"
    elseif category == "module" or category == "charge" or category == "drone" then "module"
    else "other"
end

local function contents(stacks: { { type: string, quantity: number } }): string
  local parts: { string } = {}
  for _, stack in stacks do
    local name = Types.Info(stack.type).name
    table.insert(parts, if stack.quantity == 1 then name else `{Format.Whole(stack.quantity)} x {name}`)
  end
  return table.concat(parts, ", ")
end

-- How long a listing is likely to wait, by its chance an hour.
local function waits(chance: number): string
  return if chance >= 1 then "taken within the hour" elseif chance <= 0 then "nobody will pay that"
    else `about {math.max(1, math.floor(1 / chance + 0.5))} hours`
end

local function heading(s: string, x: number, y: number, w: number, note: string?, tone: vector?)
  Im.Strong(string.upper(s), x, y, 11, Theme.ACCENT)
  if note then
    Im.Text(note, x + w - Im.TextWidth(note, 12), y - 1, 12, tone or Theme.DIM)
  end
  Im.Flat(x, y + 15, w, 1, Theme.EDGE)
end

local function bandTone(band: string): vector
  return if band == "secure" then Theme.GOOD elseif band == "low" then Theme.CAUTION else Theme.BAD
end

-- ---------------------------------------------------------------------
-- The rows

-- The lots of the page, narrowed and sorted.
local function rowsOf(game: Core.Game): ({ Core.ContractRow }, { [string]: number })
  local side = if page == "wanted" then "want" else "offer"
  local all = Core.Query.ContractSearch(game, side, reach)
  local counts: { [string]: number } = { all = 0 }
  local needle = string.lower(search)
  local rows: { Core.ContractRow } = {}
  for _, row in all do
    local of = kindOf(row.lot)
    local named = needle == "" or string.find(string.lower(row.lot.title .. " " .. contents(row.lot.stacks)), needle, 1, true) ~= nil
    if named then
      counts.all += 1
      counts[of] = (counts[of] or 0) + 1
      if kind == "all" or kind == of then
        table.insert(rows, row)
      end
    end
  end
  if sortBy ~= "jumps" or sortDown then
    table.sort(rows, function(a, b)
      local x: any, y: any
      if sortBy == "lot" then
        x, y = a.lot.title, b.lot.title
      elseif sortBy == "where" then
        x, y = a.name, b.name
      elseif sortBy == "price" then
        x, y = a.lot.price, b.lot.price
      else
        x, y = a.jumps, b.jumps
      end
      if x ~= y then
        return if sortDown then x > y else x < y
      end
      return if a.station ~= b.station then a.station < b.station else a.lot.slot < b.lot.slot
    end)
  end
  return rows, counts
end

-- The left: what the lots are of, with a search over it.
local function drawKinds(counts: { [string]: number }, x: number, y: number, w: number, h: number)
  local sought = Im.Words("Contracts:search", search, x + 10, y + 10, w - 20, 26, 40, "Search the lots")
  if sought ~= search then
    search = sought
    Im.ScrollTo("contracts list", 0)
  end
  local top = y + 46
  for index, each in KINDS do
    local rowY = top + (index - 1) * List.ROW
    local _, clicked = List.Row(x, rowY, w - 5, kind == each[1], `Contracts:kind:{each[1]}`)
    Im.Text(List.Cut(each[2], w - 70, 14, false), x + 10, rowY + 5, 14, Theme.TEXT)
    local count = tostring(counts[each[1]] or 0)
    Im.Text(count, x + w - 14 - Im.TextWidth(count, 12), rowY + 6, 12, Theme.FAINT)
    if clicked then
      kind = each[1]
      Im.ScrollTo("contracts list", 0)
    end
  end
  local _ = h
end

local OFFER_COLUMNS: { List.Column } = {
  { id = "lot", label = "Lot", width = 0 }, { id = "where", label = "Where", width = 190 },
  { id = "jumps", label = "Jumps", width = 52, right = true }, { id = "price", label = "Price", width = 110, right = true },
}
local WANT_COLUMNS: { List.Column } = {
  { id = "lot", label = "Wanted", width = 0 }, { id = "where", label = "Where", width = 190 },
  { id = "jumps", label = "Jumps", width = 52, right = true }, { id = "price", label = "Pays", width = 110, right = true },
}
local REACHES: { { any } } = { { 0, "This system" }, { 5, "5 jumps" }, { 10, "10 jumps" }, { 20, "20 jumps" }, { false, "Anywhere" } }

-- The middle: every lot of the page on every board.
local function drawLots(game: Core.Game, rows: { Core.ContractRow }, total: number, x: number, y: number, w: number, h: number)
  -- How far off a lot may be.
  local cx = x + 10
  Im.Text("Within", cx, y + 15, 12, Theme.FAINT)
  cx += Im.TextWidth("Within", 12) + 8
  for _, each in REACHES do
    local value: number? = if each[1] == false then nil else each[1]
    local pressed, wide = List.Chip(each[2], cx, y + 10, reach == value, `Contracts:reach:{if value then value else "any"}`)
    if pressed then
      reach = value
      Im.ScrollTo("contracts list", 0)
    end
    cx += wide + 4
  end
  local columns = if page == "wanted" then WANT_COLUMNS else OFFER_COLUMNS
  local layout = List.Columns(columns, x, w - 6)
  local clicked = List.Head("contracts", x, y + 42, w, columns, layout, sortBy, sortDown)
  if clicked then
    -- (a head sorts by its column; again turns it round; a third time puts the nearest first again)
    if sortBy ~= clicked then
      sortBy, sortDown = clicked, clicked == "price" and page == "wanted"
    elseif clicked ~= "jumps" and sortDown == (clicked == "price" and page == "wanted") then
      sortDown = not sortDown
    else
      sortBy, sortDown = "jumps", false
    end
    Im.ScrollTo("contracts list", 0)
  end
  local top = y + 42 + List.HEAD
  local room = h - 42 - List.HEAD - List.FOOT
  local first, visible = List.Body("contracts list", x, top, w, room, #rows)
  if #rows == 0 then
    Im.Text(if search ~= "" then "No lot like that, as the list is narrowed." else "No lot here, as the list is narrowed.", x + 12, top + 12, 14,
      Theme.DIM)
  end
  for index = 1, visible do
    local row = rows[index + first]
    if row == nil then
      break
    end
    local rowY = top + (index - 1) * List.ROW
    local lot = row.lot
    local hot, chosen = List.Row(x, rowY, w - 5, picked.station == row.station and picked.slot == lot.slot,
      `Contracts:lot:{row.station}:{lot.slot}`)
    ItemIcon.Draw(lot.stacks[1].type, layout.lot.x, rowY + 3, 19)
    List.Text(lot.title, layout.lot, rowY, hot, Theme.TEXT, 14, false, 26, contents(lot.stacks))
    List.Text(row.name, layout.where, rowY, hot, Theme.DIM, 13, false, 0, `{row.systemName}, {row.band} space`)
    List.Text(if row.jumps == 0 then "here" else tostring(row.jumps), layout.jumps, rowY, false, bandTone(row.band), 13)
    -- (under its base price is a find, well over is dear)
    List.Text(Format.Credits(lot.price), layout.price, rowY, false,
      if page ~= "wanted" and lot.price < lot.worth then Theme.GOOD else Theme.TEXT, 14, true)
    if chosen then
      picked = { station = row.station, slot = lot.slot }
    end
  end
  List.Foot(x, y + h - List.FOOT, w, `{#rows} {if #rows == 1 then "lot" else "lots"} shown of {total}`,
    if reach == nil then "on every board there is" elseif reach == 0 then "in this system" else `within {reach} jumps`)
end

-- The right: the lot picked.
local function drawLot(session: Session.Session, game: Core.Game, rows: { Core.ContractRow }, x: number, y: number, w: number, h: number)
  local row: Core.ContractRow? = nil
  for _, each in rows do
    if each.station == picked.station and each.lot.slot == picked.slot then
      row = each
    end
  end
  local dx, dw = x + 12, w - 24
  if row == nil then
    Im.Text("Choose a lot to see what is in it.", dx, y + 14, 14, Theme.DIM)
    return
  end
  local lot = row.lot
  local line = y + 12
  local first = lot.stacks[1].type
  ItemIcon.Draw(first, dx, line, 40)
  if Im.Button("Info", dx + dw - 54, line, 54, 22, true, `Info:{first}`) then
    Info.Open(first)
  end
  Im.Strong(List.Cut(lot.title, dw - 110, 17, true), dx + 50, line, 17, Theme.TEXT)
  Im.Text(if lot.side == "want" then "wanted" else "for sale", dx + 50, line + 22, 13, Theme.DIM)
  line += 52

  -- Where it is, and how far.
  heading("Where", dx, line, dw)
  line += 22
  Im.Text(List.Cut(row.name, dw, 14, false), dx, line, 14, Theme.TEXT)
  line += 20
  local across = dx + Im.Pill(`{row.band} space`, dx, line, bandTone(row.band)) + 8
  Im.Text(List.Cut(`{row.systemName}, {if row.jumps == 0 then "this system" elseif row.jumps == 1 then "1 jump" else `{row.jumps} jumps`}`,
    dx + dw - across, 13, false), across, line + 1, 13, Theme.DIM)
  line += 26
  local here = Core.Query.Player(game).system == row.system
  Im.Because(if here then "It is in this system" else nil)
  if Im.Button(if session.destination == row.system then "The way is set there" else "Set the way there", dx, line, dw, 24,
    not here and session.destination ~= row.system, "Contracts:route") then
    session.destination = row.system
  end
  line += 36

  -- What is in it.
  heading(if lot.side == "want" then "It wants" else "In it", dx, line, dw)
  line += 22
  for index, stack in lot.stacks do
    if index > 6 then
      Im.Text(`and {#lot.stacks - 6} more`, dx, line, 12, Theme.FAINT)
      line += 18
      break
    end
    ItemIcon.Draw(stack.type, dx, line, 18)
    Info.Name(stack.type, List.Cut(Types.Info(stack.type).name, dw - 90, 13, false), dx + 24, line + 1, 13, Theme.TEXT)
    local count = Format.Whole(stack.quantity)
    Im.Text(count, dx + dw - Im.TextWidth(count, 13), line + 1, 13, Theme.DIM)
    line += 22
  end
  line += 8

  -- What it asks, against what it is worth; and the doing of it.
  local box = (dw - 8) / 2
  for index = 1, 2 do
    local bx = dx + (index - 1) * (box + 8)
    Im.Flat(bx, line, box, 60, Theme.RAISED, 0.7)
    Im.Edge(bx, line, box, 60, Theme.EDGE)
    if index == 1 then
      Im.Text(if lot.side == "want" then "It pays" else "It asks", bx + 9, line + 6, 12, Theme.DIM)
      Im.Strong(Format.Credits(lot.price), bx + 9, line + 21, 19, Theme.TEXT)
    else
      Im.Text("Its base price", bx + 9, line + 6, 12, Theme.DIM)
      Im.Strong(Format.Credits(lot.worth), bx + 9, line + 21, 19, Theme.DIM)
      local off = if lot.worth > 0 then math.floor((lot.price / lot.worth - 1) * 100 + 0.5) else 0
      Im.Text(if off == 0 then "as it is" elseif off > 0 then `{off}% over` else `{-off}% under`, bx + 9, line + 42, 12,
        if (off < 0) == (lot.side ~= "want") and off ~= 0 then Theme.GOOD else Theme.DIM)
    end
  end
  line += 72
  if lot.side == "want" then
    local fill: State.Command = { kind = "FillContract", actor = 0, target = lot.slot, station = row.station }
    local can, whyNot = Session.CanDo(session, fill)
    local have = row.have[1] or 0
    Im.Text(`{Format.Whole(have)} of {Format.Whole(lot.stacks[1].quantity)} in your hangar there`, dx, line, 13,
      if can then Theme.GOOD else Theme.DIM)
    line += 22
    Im.Tone("primary")
    Im.Because(whyNot)
    if Im.Button("Deliver", dx, line, dw, 30, can, "Contracts:deliver") then
      Session.Do(session, fill)
    end
  else
    local buy: State.Command = { kind = "AcceptContract", actor = 0, target = lot.slot, station = row.station }
    local can, whyNot = Session.CanDo(session, buy)
    Im.Tone("primary")
    Im.Because(whyNot)
    if Im.Button(`Buy for {Format.Credits(lot.price)}`, dx, line, dw, 30, can, "Contracts:buy") then
      Session.Do(session, buy)
    end
    line += 38
    Im.Wrapped(`What is bought is delivered to your hangar at {row.name}: it stays there until it is fetched.`, dx, line, dw, 12, Theme.DIM)
  end
  local _ = h
end

-- ---------------------------------------------------------------------
-- My listings

local LISTING_COLUMNS: { List.Column } = {
  { id = "lot", label = "Lot", width = 0, sort = false }, { id = "where", label = "Where", width = 180, sort = false },
  { id = "price", label = "Price", width = 100, right = true, sort = false }, { id = "left", label = "Left", width = 70, right = true, sort = false },
  { id = "act", label = "", width = 70, sort = false },
}

local function drawListings(session: Session.Session, game: Core.Game, x: number, y: number, w: number, h: number)
  local docked = Core.Query.Player(game).docked
  local board = Core.Query.Contracts(game, docked)
  heading(`Up on boards  {#board.listings} / {board.limit}`, x + 10, y + 14, w - 20)
  local layout = List.Columns(LISTING_COLUMNS, x, w - 6)
  List.Head("listings", x, y + 42, w, LISTING_COLUMNS, layout, "", false)
  local top = y + 42 + List.HEAD
  local row = 34
  local first, visible = List.Body("listings", x, top, w, h - 42 - List.HEAD - 8, #board.listings, row)
  if #board.listings == 0 then
    Im.Text("Nothing up. A lot is put up on the right, for a week.", x + 12, top + 12, 13, Theme.DIM)
  end
  for index = 1, visible do
    local entry = board.listings[index + first]
    if entry == nil then
      break
    end
    local listing = entry.listing
    local rowY = top + (index - 1) * row
    local hot = List.Row(x, rowY, w - 5, false, nil, row)
    ItemIcon.Draw(listing.type, layout.lot.x, rowY + 7, 19)
    List.Text(`{Format.Whole(listing.quantity)} x {Types.Info(listing.type).name}`, layout.lot, rowY + 4, hot, Theme.TEXT, 14, false, 26,
      waits(entry.chance))
    local where = Core.Query.Body(game, listing.station)
    List.Text(if entry.here then "here" elseif where then where.name else "?", layout.where, rowY + 4, hot, Theme.DIM, 13)
    List.Text(Format.Credits(listing.price), layout.price, rowY + 4, false, Theme.TEXT, 13)
    List.Text(Format.Duration(entry.left), layout.left, rowY + 4, false, if entry.chance > 0 then Theme.DIM else Theme.BAD, 12)
    -- (taken down from anywhere: its lot goes back to the hangar where it was up)
    if Im.Button("Cancel", layout.act.x, rowY + 6, layout.act.w, 22, true, `Contract:cancel:{index + first}`) then
      Session.Do(session, { kind = "CancelContract", actor = 0, order = listing.id })
    end
  end
end

-- The right of My listings: another lot, from the hangar of the station the pilot is at.
local function drawNewListing(session: Session.Session, game: Core.Game, x: number, y: number, w: number, h: number)
  local dx, dw = x + 12, w - 24
  local station = Core.Query.Player(game).docked
  heading("New listing", dx, y + 14, dw)
  local line = y + 40
  if station == 0 then
    Im.Wrapped("A lot is put up from the hangar of the station you are docked at, and stays on its board for a week.", dx, line, dw, 13,
      Theme.DIM)
    return
  end
  -- (what no market deals in comes first: it is what a board is for)
  local hangar: { State.Item } = {}
  local stacks = Core.Query.Items(game, station, "hangar")
  for pass = 1, 2 do
    for _, item in stacks do
      if (Types.Info(item.type).unlisted == true) == (pass == 1) then
        table.insert(hangar, item)
      end
    end
  end
  local rows = 8
  if #hangar == 0 then
    Im.Text("The hangar here is empty.", dx, line, 13, Theme.DIM)
  end
  local chosen: State.Item? = nil
  for index, item in hangar do
    if item.type == listItem then
      chosen = item
      if listFresh then
        listQuantity = item.quantity
        Im.ScrollTo("contract hangar", index - 1)
      end
    end
  end
  listFresh = false
  local first = Im.Scroll("contract hangar", x, line, w, rows * List.ROW, #hangar, rows)
  for index = 1, rows do
    local item = hangar[index + first]
    if item == nil then
      break
    end
    local rowY = line + (index - 1) * List.ROW
    local hot, clicked = List.Row(x, rowY, w - 5, item.type == listItem, `Contract:item:{item.type}`)
    ItemIcon.Draw(item.type, dx, rowY + 3, 19)
    Im.Text(List.Cut(Types.Info(item.type).name, dw - 90, 14, false), dx + 26, rowY + 5, 14, Theme.TEXT)
    local count = `x{Format.Whole(item.quantity)}`
    Im.Text(count, dx + dw - Im.TextWidth(count, 12), rowY + 6, 12, Theme.DIM)
    if clicked then
      listItem, listQuantity, listPrice = item.type, item.quantity, 0
      chosen = item
    end
    local _ = hot
  end
  line += rows * List.ROW + 12
  local item = chosen
  if item == nil then
    Im.Text("Choose what to put up.", dx, line + 4, 13, Theme.DIM)
    return
  end
  Im.Text("Quantity", dx, line + 5, 13, Theme.DIM)
  listQuantity = Im.Number("ContractQuantity", listQuantity, dx + 76, line, 110, 26)
  if Im.Button("All", dx + dw - 54, line, 54, 26, true, "Contract:all") then
    listQuantity = item.quantity
  end
  local count = math.clamp(math.floor(listQuantity), 1, item.quantity)
  local worth = Core.Query.ContractWorth(game, station, item.type, count, 1)
  line += 34
  Im.Text("Price", dx, line + 5, 13, Theme.DIM)
  local asked = if listPrice > 0 then listPrice else math.max(1, worth)
  local typed = Im.Number("ContractPrice", asked, dx + 76, line, 110, 26)
  if typed ~= asked then
    listPrice = typed
    asked = typed
  end
  if Im.Button("Worth", dx + dw - 64, line, 64, 26, true, "Contract:worth") then
    listPrice = 0
  end
  local _, fee, chance = Core.Query.ContractWorth(game, station, item.type, count, asked)
  line += 36
  Im.Text(List.Cut(`worth about {Format.Credits(worth)} here; the broker takes {Format.Credits(fee)}`, dw, 12, false), dx, line, 12, Theme.DIM)
  line += 22
  local put: State.Command = { kind = "ListContract", actor = 0, item = item.id, quantity = listQuantity, price = asked }
  local can, whyNot = Session.CanDo(session, put)
  Im.Text(if can then waits(chance) else tostring(whyNot), dx, line, 12,
    if not can or chance <= 0 then Theme.BAD elseif chance >= 1 then Theme.GOOD else Theme.DIM)
  line += 22
  Im.Tone("primary")
  Im.Because(whyNot)
  if Im.Button("Put up", dx, line, dw, 30, can, "Contract:list") then
    Session.Do(session, put)
    listPrice = 0
  end
  local _ = h
end

-- ---------------------------------------------------------------------
-- The window

local TREE_W, DETAIL_W = 200, 336

Windows.Kind(Board.ID, function(_: Windows.Window, x: number, y: number, w: number, h: number)
  local session = current
  if session == nil then
    return
  end
  local game = session.game
  local was = Im.Plain(true)
  -- (the board of the station the pilot is at, by the names it had when
  -- it was the market's: its lots by their places)
  local docked = Core.Query.Player(game).docked
  if docked ~= 0 then
    for _, entry in Core.Query.Contracts(game, docked).lots do
      local lot = entry.lot
      local command: State.Command = { kind = if lot.side == "offer" then "AcceptContract" else "FillContract", actor = 0, target = lot.slot }
      if Im.Hook(`Contract:{if lot.side == "offer" then "buy" else "fill"}:{lot.slot}`, (Session.CanDo(session, command))) then
        Session.Do(session, command)
      end
    end
  end
  -- The pages.
  local board = Core.Query.Contracts(game, docked)
  local tx = x + 10
  for _, each in { { "sale", "For sale", 0 }, { "wanted", "Wanted", 0 }, { "mine", "My listings", #board.listings } } :: { { any } } do
    local pressed, wide = Im.Tab(each[2], tx, y + 4, 28, page == each[1], `Contracts:{each[1]}`, each[3])
    if pressed and page ~= each[1] then
      page = each[1]
      picked = { station = 0, slot = 0 }
      Im.ScrollTo("contracts list", 0)
    end
    tx += wide + 2
  end
  local note = "bought from anywhere: delivered to your hangar where the lot is"
  Im.Text(note, x + w - 12 - Im.TextWidth(note, 12), y + 11, 12, Theme.DIM)
  Im.Flat(x + 1, y + 32, w - 2, 1, Theme.EDGE)
  local top, room = y + 33, h - 34
  if page == "mine" then
    local listW = w - DETAIL_W
    drawListings(session, game, x + 1, top, listW - 1, room)
    Im.Flat(x + listW, top, 1, room, Theme.EDGE)
    drawNewListing(session, game, x + listW + 1, top, DETAIL_W - 2, room)
  else
    local rows, counts = rowsOf(game)
    local listW = w - TREE_W - DETAIL_W
    drawKinds(counts, x + 1, top, TREE_W - 1, room)
    Im.Flat(x + TREE_W, top, 1, room, Theme.EDGE)
    drawLots(game, rows, counts.all, x + TREE_W + 1, top, listW - 1, room)
    Im.Flat(x + TREE_W + listW, top, 1, room, Theme.EDGE)
    drawLot(session, game, rows, x + TREE_W + listW + 1, top, DETAIL_W - 2, room)
  end
  local _ = Icons
  Im.Plain(was)
end)
Windows.Make(Board.ID, Board.ID, "Contracts", 534, 130, 1130, 720, 1000, 640, nil)
Windows.Icon(Board.ID, "contracts")

return Board
