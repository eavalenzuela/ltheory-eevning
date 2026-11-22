--!strict
-- The market: a window of its own (Game/UI/Windows), the first of a
-- station's services to be one and the first made over to the look the
-- owner agreed (Game/UI/Theme; docs/design/interface). Opened from the
-- dock, at a station; shut when the pilot undocks.
--
-- Three pages. Browse: the categories down the left as a tree (each
-- opens to its groups), with a search of every category over it; in the
-- middle the things of what is picked there, in the one list
-- (Game/UI/List: heads that sort, a thing's other makes folded under
-- it, switches that narrow it to what is sold here, what the pilot can
-- use, and a tier); and on the right the thing chosen: what the station
-- asks and bids, buying and selling at once, where else it is to be had,
-- its price day by day and across the map, and standing orders. My
-- orders: the pilot's standing orders everywhere. Contracts: the
-- station's board.
--
-- A script's names (Im.Press) are what they were when this was a tab of
-- the docked screen: "Category:<id>" (and "Category:orders",
-- "Category:contracts"), "Quantity", "Quantity:<n>", "Quantity:all",
-- "BuyNow", "SellNow", "Fetch", "Fetch:keep", "SellPrice", "PlaceSell",
-- "BuyPrice", "PlaceBuy", "Market:map", "Info:<type>", "Try:<type>",
-- "OrderPrice:<n>", "SetOrder:<n>", "CancelOrder:<n>" and the board's
-- "Contract:...". New with the window: "Market:browse",
-- "Group:<category>:<group>", "Market:item:<type>", "Market:fold:<type>",
-- "Market:search", "Market:sold", "Market:usable", "Market:tier:<tier>",
-- "market:sort:<column>", and "market:close".

local Catalog = require("@lt/Core/Data/Catalog")
local Chart = require("@lt/Game/UI/Chart")
local Core = require("@lt/Core/Api")
local Fleet = require("@lt/Core/Tactical/Fleet")
local Format = require("@lt/Game/Format")
local Icons = require("@lt/Game/UI/Icons")
local ContractsWindow = require("@lt/Game/UI/Contracts")
local Fitting = require("@lt/Game/UI/Fitting")
local SkillSheet = require("@lt/Game/UI/Skills")
local Im = require("@lt/Game/UI/Im")
local Info = require("@lt/Game/UI/Info")
local ItemIcon = require("@lt/Game/UI/ItemIcon")
local List = require("@lt/Game/UI/List")
local Map = require("@lt/Game/UI/Map")
local Modules = require("@lt/Core/Data/Modules")
local Session = require("@lt/Game/Session")
local Ships = require("@lt/Core/Data/Ships")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local Theme = require("@lt/Game/UI/Theme")
local Types = require("@lt/Core/Data/Types")
local Windows = require("@lt/Game/UI/Windows")

local Market = {}

Market.ID = "market"

local CATEGORY_NAMES: { [string]: string } = {
  module = "Modules", charge = "Charges", drone = "Drones", ship = "Ships", structure = "Structures", ore = "Ore", mineral = "Minerals",
  moon = "Moon", planetary = "Planetary", component = "Components", blueprint = "Blueprints", skillbook = "Skill books",
  implant = "Implants", paint = "Paints", goods = "Goods",
}

-- What is shown: the page, the category and the group of it picked in
-- the tree ("": all of the category), the thing chosen, and what is
-- entered for it.
local page = "browse"
local category, group = "module", ""
local chosen = ""
local quantity = 1
local sellPrice, buyPrice = 0, 0    -- 0: the best price that fills now
-- How the list is narrowed and sorted.
local search = ""
local soldHere, usable = true, false
local tier = "all"
local sortBy, sortDown = "", false  -- "": as the catalogue sets them out, under their headings
-- The things whose other makes are laid open under them, the categories
-- laid open in the tree, and a thing the list is to be brought to.
local unfolded: { [string]: boolean } = {}
local opened: { [string]: boolean } = { module = true }
local reveal: string? = nil
-- How many days of a price are shown.
local HISTORY = 30

-- What the thing chosen goes for across the map (Core.Query.Prices),
-- and where else it is to be had (Core.Query.Sources): asked again now
-- and then, not every frame.
local across = { key = "", age = 0, here = 1, list = {} :: { Core.PriceAt } }
local elsewhere = { key = "", age = 0, list = {} :: { Core.Source } }
-- How much over what a market asks now a pilot sent there may pay, a
-- unit, on the average of a purchase: prices move while they fly. And
-- one who is to keep a thing in stock from now on, more: prices move
-- further in a week than in an hour.
local LEEWAY = 1.1
local STANDING = 1.25
-- A standing order's price as it is being typed, by the order's id.
local repriced: { [number]: number } = {}

-- The board: the type chosen to put up, how many and at what.

-- Whose game it is (Market.Frame).
local current: Session.Session? = nil

local TREE_W, DETAIL_W = 200, 336

-- ---------------------------------------------------------------------
-- What there is to list

-- The tier of a type: "t1" (the plain make), "t2", "faction" (a
-- people's own make), or "found" (a custom make, a masterwork, an
-- officer's: had only from wrecks). And the make it is another make of.
local function tierOf(id: string): (string, string?)
  local module = rawget(Modules.byId, id)
  if module then
    local of = if module.tech == 2 then "t2" elseif module.meta == 3 then "faction" elseif module.meta then "found" else "t1"
    return of, module.base
  end
  local charge = rawget(Modules.chargeById, id)
  if charge then
    return if charge.tech == 2 then "t2" else "t1", charge.base
  end
  local hull = Ships.byId[id]
  -- (a tech 2 hull is a hull of its own, with a name of its own: it is not folded under another)
  return if hull and hull.tech == 2 then "t2" else "t1", nil
end

local TIER_ORDER: { [string]: number } = { t1 = 0, t2 = 1, faction = 2, found = 3 }

-- What a make is called beside its name, and in what colour.
local function tierLabel(id: string): (string, vector)
  local module = rawget(Modules.byId, id)
  if module then
    if module.tech == 2 then
      return "Tech 2", Theme.CAUTION
    elseif module.meta == 3 then
      return "Faction", Theme.GOOD
    elseif module.meta == 1 then
      return "Custom", Theme.ACCENT
    elseif module.meta == 2 then
      return "Masterwork", Theme.ACCENT
    elseif module.meta then
      return "Officer", Theme.ACCENT
    end
  end
  local of = tierOf(id)
  return if of == "t2" then "Tech 2" else "", Theme.CAUTION
end

-- A kind of thing, with its other makes; and a group of kinds under a heading.
type Kind = { info: Types.Info, variants: { Types.Info } }
type Section = { name: string, kinds: { Kind } }

local sections: { [string]: { Section } } = {}

-- A category as the catalogue sets it out (Data/Catalog), with each
-- thing's other makes gathered under it. (Worked out once.)
local function sectionsOf(of: string): { Section }
  local known = sections[of]
  if known then
    return known
  end
  local made: { Section } = {}
  local kindOf: { [string]: Kind } = {}
  local listed: { [string]: boolean } = {}
  local listing = Catalog.Listing(of)
  for _, entry in listing do
    if entry.info then
      listed[entry.info.id] = true
    end
  end
  local late: { Types.Info } = {}
  for _, entry in listing do
    local info = entry.info
    if info == nil then
      local section: Section = { name = entry.header or "", kinds = {} }
      table.insert(made, section)
    else
      if #made == 0 then
        local section: Section = { name = "", kinds = {} }
        table.insert(made, section)
      end
      local _, base = tierOf(info.id)
      if base and listed[base] then
        table.insert(late, info)
      else
        local kind: Kind = { info = info, variants = {} }
        kindOf[info.id] = kind
        table.insert(made[#made].kinds, kind)
      end
    end
  end
  for _, info in late do
    local _, base = tierOf(info.id)
    table.insert(kindOf[base :: string].variants, info)
  end
  for _, kind in kindOf do
    table.sort(kind.variants, function(a: Types.Info, b: Types.Info): boolean
      local ta, tb = TIER_ORDER[(tierOf(a.id))], TIER_ORDER[(tierOf(b.id))]
      if ta ~= tb then
        return ta < tb
      end
      return if a.name ~= b.name then a.name < b.name else a.id < b.id
    end)
  end
  sections[of] = made
  return made
end

-- What the market knows of a type at the station, and whether the pilot
-- can use it: asked once a tick for each type that is listed, not once a
-- frame.
type Fact = { ask: number?, bid: number, stock: number, untrained: string? }
local facts = { station = 0, tick = -1, of = {} :: { [string]: Fact } }

local function factOf(game: Core.Game, station: number, id: string): Fact
  if facts.station ~= station or facts.tick ~= game.state.tick then
    facts.station, facts.tick, facts.of = station, game.state.tick, {}
  end
  local fact = facts.of[id]
  if fact == nil then
    local quote = Core.Query.Quote(game, station, id)
    fact = { ask = quote.ask, bid = quote.bid, stock = quote.stock, untrained = Core.Query.Untrained(game, id) }
    facts.of[id] = fact
  end
  return fact
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

-- ---------------------------------------------------------------------
-- Opened from elsewhere

function Market.Open()
  Windows.Open(Market.ID)
end

function Market.Close()
  Windows.Close(Market.ID)
end

function Market.IsOpen(): boolean
  return Windows.IsOpen(Market.ID)
end

-- Open the market at a type, as clicking through to it would.
function Market.Choose(type: string): boolean
  local info = Types.Get(type)
  -- (no market deals in a blueprint copy: there is nothing to open it at)
  if info == nil or info.unlisted then
    return false
  end
  page = "browse"
  category, group = info.category, ""
  opened[category] = true
  search = ""
  if chosen ~= type then
    chosen = type
    quantity = 1
    sellPrice, buyPrice = 0, 0
  end
  -- (another make of a thing is under that thing, laid open; and its row is brought into the list)
  local _, base = tierOf(type)
  if base then
    unfolded[base] = true
  end
  reveal = type
  Market.Open()
  return true
end

-- The thing chosen ("" if none), and the page shown.
function Market.Showing(): (string, string)
  return chosen, page
end

-- Open the market's board with a type of the hangar chosen to put up,
-- as clicking its row there would.
-- (the board is a window of its own since 2026-11-16, galaxy-wide: Game/UI/Contracts)
function Market.Contract(type: string): boolean
  return ContractsWindow.Choose(type)
end

-- Once a frame, before the windows are drawn: whose game it is, and
-- whether the pilot is docked. The market is a station's (Windows.Berthed).
function Market.Frame(session: Session.Session, docked: boolean)
  current = session
  Windows.Berthed(Market.ID, docked)
end

-- ---------------------------------------------------------------------
-- Drawing

local function heading(s: string, x: number, y: number, w: number, note: string?, tone: vector?)
  Im.Strong(string.upper(s), x, y, 11, Theme.ACCENT)
  if note then
    Im.Text(note, x + w - Im.TextWidth(note, 12), y - 1, 12, tone or Theme.DIM)
  end
  Im.Flat(x, y + 15, w, 1, Theme.EDGE)
end

-- The pilot's standing orders, everywhere.
local function drawOrders(session: Session.Session, game: Core.Game, station: number, x: number, y: number, w: number, h: number)
  local orders = Core.Query.Orders(game, nil)
  local columns: { List.Column } = {
    { id = "side", label = "", width = 44, sort = false }, { id = "item", label = "Item", width = 0, sort = false },
    { id = "quantity", label = "Quantity", width = 90, right = true, sort = false },
    { id = "price", label = "Price", width = 110, right = true, sort = false }, { id = "where", label = "Where", width = 300, sort = false },
    { id = "act", label = "", width = 150, sort = false },
  }
  local layout = List.Columns(columns, x, w)
  List.Head("orders", x, y, w, columns, layout, "", false)
  if #orders == 0 then
    Im.Text("No standing orders. One is placed from a thing's own page, under Browse.", x + 12, y + List.HEAD + 12, 14, Theme.DIM)
    return
  end
  local top = y + List.HEAD
  local first, visible = List.Body("orders", x, top, w, h - List.HEAD - List.FOOT, #orders, 28)
  for row = 1, visible do
    local order = orders[row + first]
    if order == nil then
      break
    end
    local rowY = top + (row - 1) * 28
    local hot = List.Row(x, rowY, w, false, nil, 28)
    local here = order.station == station
    local where = Core.Query.Body(game, order.station)
    local selling = order.side == "sell"
    Im.Pill(if selling then "SELL" else "BUY", layout.side.x, rowY + 6, if selling then Theme.CAUTION else Theme.GOOD)
    ItemIcon.Draw(order.type, layout.item.x, rowY + 4, 20)
    List.Text(Types.Info(order.type).name, layout.item, rowY + 1, hot, Theme.TEXT, 14, false, 28)
    List.Text(Format.Whole(order.quantity), layout.quantity, rowY + 1, false, Theme.TEXT)
    if here then
      -- (an order here has its price in a field: another typed there,
      -- and Set, is its price from then on)
      local shown = repriced[order.id] or order.price
      local typed = Im.Number(`OrderPrice:{row + first}`, shown, layout.price.x, rowY + 3, layout.price.w, 22, 12)
      repriced[order.id] = if typed ~= order.price then typed else nil :: any
      local change: State.Command = { kind = "ModifyOrder", actor = 0, order = order.id, price = typed }
      local canChange, whyNotChange = Session.CanDo(session, change)
      Im.Because(if typed == order.price then "Type another price first" else whyNotChange)
      if Im.Button("Set", layout.act.x, rowY + 3, 54, 22, typed ~= order.price and canChange, `SetOrder:{row + first}`) then
        Session.Do(session, change)
        repriced[order.id] = nil
      end
      List.Text("here", layout.where, rowY + 1, false, Theme.GOOD)
    else
      List.Text(Format.Credits(order.price), layout.price, rowY + 1, false, Theme.TEXT)
      List.Text(if where then where.name else "?", layout.where, rowY + 1, hot, Theme.DIM)
    end
    Im.Because("An order is called off at the station it is at")
    if Im.Button("Cancel", layout.act.x + 62, rowY + 3, 72, 22, here, `CancelOrder:{row + first}`) then
      Session.Do(session, { kind = "CancelOrder", actor = 0, order = order.id })
    end
  end
  List.Foot(x, y + h - List.FOOT, w, `{#orders} standing {if #orders == 1 then "order" else "orders"}`, "an order's price is changed where it stands")
end

-- What a lot is made of, in a line.
-- The categories, as a tree: each opens to its groups. With a search of
-- every category over it.
local function drawTree(x: number, y: number, w: number, h: number)
  local sought = Im.Words("Market:search", search, x + 10, y + 10, w - 20, 26, 40, "Search every category")
  if sought ~= search then
    -- (what is found is read from its top)
    search = sought
    Im.ScrollTo("market list", 0)
  end
  local rows: { { category: string, group: string?, label: string, count: number, folds: boolean } } = {}
  for _, id in Catalog.CATEGORIES do
    local parts = sectionsOf(id)
    local total = 0
    for _, section in parts do
      total += #section.kinds
    end
    local folds = #parts > 1
    table.insert(rows, { category = id, label = CATEGORY_NAMES[id] or id, count = total, folds = folds })
    if folds and opened[id] then
      for _, section in parts do
        table.insert(rows, { category = id, group = section.name, label = if section.name == "" then "Other" else section.name,
          count = #section.kinds, folds = false })
      end
    end
  end
  local top = y + 46
  local first, visible = List.Body("market tree", x, top, w, h - 46, #rows)
  for index = 1, visible do
    local row = rows[index + first]
    if row == nil then
      break
    end
    local rowY = top + (index - 1) * List.ROW
    local whole = row.group == nil
    local selected = search == "" and category == row.category and (if whole then group == "" else group == row.group)
    local _, clicked = List.Row(x, rowY, w - 5, selected,
      if whole then `Category:{row.category}` else `Group:{row.category}:{row.group}`)
    local tx = x + (if whole then 10 else 26)
    if row.folds then
      Icons.Draw(if opened[row.category] then "down" else "right", tx + 4, rowY + 12, 4, Theme.DIM, 1)
    end
    if whole then
      tx += 14
    end
    Im.Text(List.Cut(row.label, w - (tx - x) - 46, 14, false), tx, rowY + 5, 14, Theme.TEXT)
    local count = tostring(row.count)
    Im.Text(count, x + w - 14 - Im.TextWidth(count, 12), rowY + 6, 12, Theme.FAINT)
    if clicked then
      -- (a click on the category that is picked folds it and lays it open; on another, picks that and lays it open)
      if whole and selected then
        opened[row.category] = not opened[row.category]
      elseif whole then
        opened[row.category] = true
      end
      page, category, group, search = "browse", row.category, row.group or "", ""
      Im.ScrollTo("market list", 0)
    end
  end
end

-- A row of the list: a heading, or a thing (a kind, or another make of
-- one under it).
type Line = { heading: string?, count: number?, info: Types.Info?, child: boolean?, makes: number?, fact: Fact? }

-- What is listed, narrowed and sorted as the switches and the heads say.
local function lines(game: Core.Game, station: number, have: { [string]: number }): ({ Line }, number, number)
  local needle = string.lower(search)
  local function passes(info: Types.Info): boolean
    if info.id == chosen and needle == "" then
      return true
    end
    if needle ~= "" and string.find(string.lower(info.name), needle, 1, true) == nil then
      return false
    end
    local fact = factOf(game, station, info.id)
    if soldHere and fact.ask == nil then
      return false
    end
    return not (usable and fact.untrained ~= nil)
  end
  -- (how many are kept back only by "Sold here", for the foot)
  local hidden = 0
  local function counted(info: Types.Info): boolean
    local ok = passes(info)
    if not ok and soldHere and factOf(game, station, info.id).ask == nil
      and (needle == "" or string.find(string.lower(info.name), needle, 1, true) ~= nil)
      and not (usable and factOf(game, station, info.id).untrained ~= nil) then
      hidden += 1
    end
    return ok
  end
  type Top = { info: Types.Info, under: { Types.Info } }
  local out: { Line } = {}
  local kinds = 0
  local sources: { { label: string, parts: { Section } } } = {}
  if needle ~= "" then
    for _, id in Catalog.CATEGORIES do
      table.insert(sources, { label = CATEGORY_NAMES[id] or id, parts = sectionsOf(id) })
    end
  else
    table.insert(sources, { label = "", parts = sectionsOf(category) })
  end
  local flat: { Top } = {}
  for _, source in sources do
    for _, section in source.parts do
      if needle ~= "" or group == "" or section.name == group then
        local tops: { Top } = {}
        for _, kind in section.kinds do
          if tier == "all" then
            local own = counted(kind.info)
            local under: { Types.Info } = {}
            for _, variant in kind.variants do
              if counted(variant) then
                table.insert(under, variant)
              end
            end
            if own or #under > 0 then
              local top: Top = { info = kind.info, under = under }
              table.insert(tops, top)
            end
          else
            -- (one tier: every make of that tier by itself, nothing folded)
            for _, each in { kind.info, table.unpack(kind.variants) } do
              if tierOf(each.id) == tier and counted(each) then
                local top: Top = { info = each, under = {} }
                table.insert(tops, top)
              end
            end
          end
        end
        if #tops > 0 then
          kinds += #tops
          if sortBy == "" then
            local label = if source.label ~= "" and section.name ~= "" then `{source.label}: {section.name}`
              elseif source.label ~= "" then source.label else section.name
            if label ~= "" and (needle ~= "" or group == "") then
              table.insert(out, { heading = label, count = #tops })
            end
            for _, top in tops do
              table.insert(flat, top)
              table.insert(out, { info = top.info, makes = #top.under, fact = factOf(game, station, top.info.id) })
              if unfolded[top.info.id] or needle ~= "" then
                for _, variant in top.under do
                  table.insert(out, { info = variant, child = true, fact = factOf(game, station, variant.id) })
                end
              end
            end
          else
            for _, top in tops do
              table.insert(flat, top)
            end
          end
        end
      end
    end
  end
  if sortBy ~= "" then
    -- (sorted by a column: one run of rows, no headings; a thing's other makes still under it)
    local function value(info: Types.Info): any
      local fact = factOf(game, station, info.id)
      return if sortBy == "name" then string.lower(info.name) elseif sortBy == "ask" then (fact.ask or math.huge)
        elseif sortBy == "bid" then fact.bid elseif sortBy == "stock" then fact.stock else (have[info.id] or 0)
    end
    table.sort(flat, function(a: Top, b: Top): boolean
      local va, vb = value(a.info), value(b.info)
      if va ~= vb then
        if sortDown then
          return va > vb
        end
        return va < vb
      end
      return a.info.id < b.info.id
    end)
    for _, top in flat do
      table.insert(out, { info = top.info, makes = #top.under, fact = factOf(game, station, top.info.id) })
      if unfolded[top.info.id] or needle ~= "" then
        for _, variant in top.under do
          table.insert(out, { info = variant, child = true, fact = factOf(game, station, variant.id) })
        end
      end
    end
  end
  return out, kinds, hidden
end

local TIERS: { { string } } = { { "all", "All" }, { "t1", "Tech 1" }, { "t2", "Tech 2" }, { "faction", "Faction" }, { "found", "Found" } }
local COLUMNS: { List.Column } = {
  { id = "name", label = "Item", width = 0 }, { id = "ask", label = "Ask", width = 80, right = true },
  { id = "bid", label = "Bid", width = 80, right = true }, { id = "stock", label = "Stock", width = 50, right = true },
  { id = "have", label = "Have", width = 40, right = true },
}

-- The things of what is picked in the tree (or found by the search).
local function drawList(game: Core.Game, station: number, x: number, y: number, w: number, h: number)
  -- What narrows it.
  local cx = x + 10
  -- (a list narrowed another way is read from its top)
  local pressed, wide = List.Chip("Sold here", cx, y + 10, soldHere, "Market:sold")
  if pressed then
    soldHere = not soldHere
    Im.ScrollTo("market list", 0)
  end
  cx += wide + 4
  pressed, wide = List.Chip("I can use", cx, y + 10, usable, "Market:usable")
  if pressed then
    usable = not usable
    Im.ScrollTo("market list", 0)
  end
  cx += wide + 14
  Im.Text("Tier", cx, y + 15, 12, Theme.FAINT)
  cx += Im.TextWidth("Tier", 12) + 8
  for _, each in TIERS do
    pressed, wide = List.Chip(each[2], cx, y + 10, tier == each[1], `Market:tier:{each[1]}`)
    if pressed then
      tier = each[1]
      Im.ScrollTo("market list", 0)
    end
    cx += wide + 4
  end

  local have: { [string]: number } = {}
  for _, item in Core.Query.Items(game, station, "hangar") do
    have[item.type] = (have[item.type] or 0) + item.quantity
  end
  local rows, kinds, hidden = lines(game, station, have)
  local layout = List.Columns(COLUMNS, x, w - 6)
  local clicked = List.Head("market", x, y + 42, w, COLUMNS, layout, sortBy, sortDown)
  if clicked then
    -- (a head sorts by its column; again turns it round; a third time puts the catalogue's order back)
    if sortBy ~= clicked then
      sortBy, sortDown = clicked, clicked ~= "name"
    elseif sortDown == (clicked ~= "name") then
      sortDown = not sortDown
    else
      sortBy, sortDown = "", false
    end
    Im.ScrollTo("market list", 0)
  end
  local top = y + 42 + List.HEAD
  local room = h - 42 - List.HEAD - List.FOOT
  local bring = reveal
  if bring then
    for index, line in rows do
      if line.info and line.info.id == bring then
        Im.ScrollTo("market list", math.max(0, index - 5))
      end
    end
    reveal = nil
  end
  local first, visible = List.Body("market list", x, top, w, room, #rows)
  if #rows == 0 then
    Im.Text(if search ~= "" then "Nothing by that name, as the list is narrowed." else "Nothing here, as the list is narrowed.", x + 12, top + 12,
      14, Theme.DIM)
  end
  for index = 1, visible do
    local line = rows[index + first]
    if line == nil then
      break
    end
    local rowY = top + (index - 1) * List.ROW
    local info = line.info
    if info == nil then
      List.Group(line.heading or "", `{line.count or 0} {if line.count == 1 then "kind" else "kinds"}`, x, rowY, w - 5, nil)
      continue
    end
    local fact = line.fact :: Fact
    local hot, picked = List.Row(x, rowY, w - 5, chosen == info.id, `Market:item:{info.id}`)
    local inset = if line.child then 18 else 0
    local makes = line.makes or 0
    if makes > 0 then
      -- (its other makes: laid open and folded by the mark at its left)
      local _, fold = Im.Area(`Market:fold:{info.id}`, layout.name.x - 4, rowY, 18, List.ROW, true)
      Icons.Draw(if unfolded[info.id] or search ~= "" then "down" else "right", layout.name.x + 4, rowY + 12, 4, Theme.DIM, 1)
      if fold then
        unfolded[info.id] = not unfolded[info.id]
        picked = false
      end
    end
    ItemIcon.Draw(info.id, layout.name.x + 14 + inset, rowY + 3, 20)
    local sold = fact.ask ~= nil
    local color = if not sold or fact.untrained then Theme.DIM else Theme.TEXT
    local label, tone = "", Theme.CAUTION
    if line.child or tier ~= "all" then
      label, tone = tierLabel(info.id)
    end
    local pill = if label ~= "" then Im.StrongWidth(label, 11) + 18 else 0
    local name: List.Cell = { x = layout.name.x, w = layout.name.w - pill, right = false }
    local drawn = List.Text(info.name, name, rowY, hot, color, 14, false, 42 + inset,
      if fact.untrained then fact.untrained elseif not sold then "Not sold here" else nil)
    if label ~= "" then
      Im.Pill(label, layout.name.x + 42 + inset + drawn + 6, rowY + 5, tone)
    end
    List.Text(if fact.ask then Format.Whole(math.ceil(fact.ask)) else "-", layout.ask, rowY, false, if sold then Theme.TEXT else Theme.FAINT)
    List.Text(Format.Whole(math.floor(fact.bid)), layout.bid, rowY, false, Theme.DIM)
    List.Text(if fact.stock > 0 then Format.Whole(fact.stock) else "-", layout.stock, rowY, false, if fact.stock > 0 then Theme.DIM else Theme.FAINT)
    local held = have[info.id] or 0
    List.Text(if held > 0 then Format.Whole(held) else "-", layout.have, rowY, false, if held > 0 then Theme.TEXT else Theme.FAINT)
    if picked and chosen ~= info.id then
      chosen = info.id
      quantity = 1
      sellPrice, buyPrice = 0, 0
    end
  end
  local shown = 0
  for _, line in rows do
    shown += if line.info then 1 else 0
  end
  List.Foot(x, y + h - List.FOOT, w, `{kinds} {if kinds == 1 then "kind" else "kinds"}, {shown} shown with their other makes`,
    if hidden > 0 then `{hidden} not sold here {if hidden == 1 then "is" else "are"} hidden` else "")
end

local function percent(level: number): string
  local off = math.floor((level - 1) * 100 + 0.5)
  return if off == 0 then "normal" elseif off > 0 then `{off}% over` else `{-off}% under`
end

-- The thing chosen: what it is, trading in it at once, where else it is
-- to be had, its price day by day and across the map, and standing orders.
local function drawDetail(session: Session.Session, game: Core.Game, station: number, x: number, y: number, w: number, h: number)
  local info = Types.Get(chosen)
  if info == nil then
    Im.Text("Choose a thing to see its prices.", x + 12, y + 14, 14, Theme.DIM)
    return
  end
  local dx, dw = x + 12, w - 24
  local quote = Core.Query.Quote(game, station, chosen)
  local stack, have = inHangar(game, station, chosen)
  local line = y + 12

  -- What it is.
  ItemIcon.Draw(chosen, dx, line, 40)
  local infoAt = dx + dw - 54
  if Im.Button("Info", infoAt, line, 54, 22, true, `Info:{chosen}`) then
    Info.Open(chosen)
  end
  -- (a paint or a design is tried on the ship before it is bought: the fitting screen shows the ship in it)
  if info.category == "paint" and Im.Button("Try on", infoAt, line + 24, 54, 20, true, `Try:{chosen}`) then
    Session.Try(session, chosen)
    Fitting.Show("appearance")
  end
  Im.Strong(List.Cut(info.name, dw - 110, 17, true), dx + 50, line, 17, Theme.TEXT)
  local kind = Catalog.Group(chosen)
  local label = tierLabel(chosen)
  Im.Text(List.Cut(`{if kind ~= "" then kind else CATEGORY_NAMES[info.category] or ""}{if label ~= "" then ", " .. label else ""}  -  {info.volume} m3`,
    dw - 110, 13, false), dx + 50, line + 22, 13, Theme.DIM)
  line += 46
  local untrained = Core.Query.Untrained(game, chosen)
  if info.category == "paint" and game.state.paints[chosen] then
    -- (a paint or a design that is the pilot's for good is not needed twice)
    Im.Text("yours already: on the fitting screen's list", dx, line, 12, Theme.ACCENT)
  elseif untrained then
    Im.Text(List.Cut(untrained, dw, 12, false), dx, line, 12, Theme.BAD)
  end
  line += 18

  -- What the station asks and bids.
  local box = (dw - 8) / 2
  for index = 1, 2 do
    local bx = dx + (index - 1) * (box + 8)
    Im.Flat(bx, line, box, 60, Theme.RAISED, 0.7)
    Im.Edge(bx, line, box, 60, Theme.EDGE)
    local figure, under, lit = "", "", true
    if index == 1 then
      Im.Text("The station asks", bx + 9, line + 6, 12, Theme.DIM)
      figure, under, lit = if quote.ask then Format.Price(quote.ask) else "nothing", `{Format.Whole(quote.stock)} in stock`, quote.ask ~= nil
    else
      Im.Text("and bids", bx + 9, line + 6, 12, Theme.DIM)
      figure, under = Format.Price(quote.bid), `{Format.Whole(have)} in your hangar`
    end
    Im.Strong(figure, bx + 9, line + 21, 19, if lit then Theme.TEXT else Theme.DIM)
    Im.Text(under, bx + 9, line + 42, 12, if index == 2 and have > 0 then Theme.TEXT else Theme.DIM)
  end
  line += 70

  -- A trade at once.
  Im.Text("Quantity", dx, line + 5, 13, Theme.DIM)
  quantity = Im.Number("Quantity", quantity, dx + 60, line, 78, 26)
  local px = dx + 144
  for _, preset in { 1, 10, 100, 1000 } do
    local text = Format.Whole(preset)
    local wide = if preset == 1000 then 44 else if preset == 100 then 34 else 28
    if Im.Button(text, px, line, wide, 26, true, `Quantity:{preset}`) then
      quantity = preset
    end
    px += wide + 3
  end
  if Im.Button("All", px, line, dx + dw - px, 26, have > 0, "Quantity:all") then
    quantity = have
  end
  line += 34
  local whole = quantity >= 1
  local cost = if whole then Core.Query.BuyCost(game, station, chosen, quantity) else nil
  local canBuy, whyNot = Session.CanDo(session, { kind = "BuyNow", actor = 0, type = chosen, quantity = quantity })
  Im.Tone("primary")
  Im.Because(if whyNot then tostring(whyNot) else nil)
  if Im.Button(if cost then `Buy   {Format.Credits(cost)}` else "Buy", dx, line, box, 34, canBuy, "BuyNow") then
    Session.Do(session, { kind = "BuyNow", actor = 0, type = chosen, quantity = quantity })
  end
  local canSell = stack ~= nil and whole and quantity <= have
  local value = if canSell then Core.Query.SellValue(game, station, chosen, quantity) else 0
  Im.Because(if have == 0 then "You have none in the hangar here" elseif quantity > have then `You have {Format.Whole(have)} here` else nil)
  if Im.Button(if canSell then `Sell   {Format.Credits(value)}` else "Sell", dx + box + 8, line, box, 34, canSell, "SellNow") and stack then
    Session.Do(session, { kind = "SellNow", actor = 0, item = stack.id, quantity = quantity })
  end
  line += 38
  if not canBuy and whole then
    Im.Text(List.Cut(tostring(whyNot), dw, 12, false), dx, line, 12, Theme.BAD)
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
    Im.Text(List.Cut(`Elsewhere: {best.name}`, dw - 130, 12, false), dx, line, 12, Theme.TEXT)
    local far = if best.jumps == 0 then "in this system" elseif best.jumps == 1 then "1 jump" else `{best.jumps} jumps`
    Im.Text(List.Cut(`{far}, {Format.Price(best.each)} each` .. (if best.units < asked then `, has {Format.Whole(best.units)}` else ""), dw - 130, 12,
      false), dx, line + 15, 12, if here == nil or best.each < here then Theme.GOOD else Theme.DIM)
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
    local canKeep, whyNotKeep = false, nil :: string?
    if goes then
      can, why = Session.CanDo(session, fetch)
      canKeep, whyNotKeep = Session.CanDo(session, keep)
    end
    Im.Because(if goes == nil then "No pilot of yours is docked here with nothing else to do" else why)
    if Im.Button(if goes then List.Cut(`Send {string.match(goes.name, "^%S+") or goes.name}`, 68, 14, true) else "Send", dx + dw - 124, line, 76, 26,
      can, "Fetch") then
      Session.Do(session, fetch)
    end
    Im.Because(if goes == nil then "No pilot of yours is docked here with nothing else to do" else whyNotKeep)
    if Im.Button("Keep", dx + dw - 44, line, 44, 26, canKeep, "Fetch:keep") then
      Session.Do(session, keep)
    end
  else
    Im.Text(`Elsewhere: no market within {Fleet.SHOPS} jumps has any`, dx, line + 6, 12, Theme.DIM)
  end
  line += 40

  -- Its price here day by day, and what was traded in it: the going
  -- price each day closed at, today's being what it is now.
  local series = Core.Query.PriceHistory(game, station, chosen, HISTORY)
  local low, high = Chart.Range(series)
  local units, worth = Chart.Traded(series)
  heading(`Price here, {#series} {if #series == 1 then "day" else "days"}`, dx, line, dw)
  local picked = Chart.Draw(series, dx, line + 22, dw, 64, 20, false)
  local _ = Im.Area("Market:chart", dx, line + 22, dw, 84, true)
  local day = series[picked or #series]
  -- (the day under the cursor, or today)
  local said = if picked and picked < #series then `day {day.day + 1} closed at {Format.Price(day.price)}` else `now {Format.Price(day.price)}`
  Im.Text(said, dx + dw - Im.TextWidth(said, 12), line - 1, 12, Theme.TEXT)
  line += 22 + 64 + 4 + 20 + 4
  local spread = if high - low < high * 0.002 then `steady at {Format.Price(high)}` else `{Format.Price(low)} to {Format.Price(high)}`
  Im.Text(spread, dx, line, 12, Theme.DIM)
  local traded = if units > 0 then `{Format.Whole(units)} traded, at {Format.Price(worth / units)}` else "nothing traded, by you or yours"
  Im.Text(traded, dx + dw - Im.TextWidth(traded, 12), line, 12, Theme.DIM)
  line += 24

  -- What it goes for across the map: here, and where it is cheapest
  -- and dearest within reach (Core.Query.Prices). Asked again now and
  -- then, not every frame.
  local mapKey = `{station}:{chosen}`
  across.age += 1
  if across.key ~= mapKey or across.age > 120 then
    across.key, across.age = mapKey, 0
    across.here, across.list = Core.Query.Prices(game, chosen)
  end
  heading(`Within {Core.PRICE_REACH} jumps`, dx, line, dw - 78, `here: {percent(across.here)}`)
  -- (and the whole of it, on the star map: its price layer, of this thing)
  Im.Because("It goes for the same everywhere")
  if Im.Button("On map", dx + dw - 70, line - 6, 70, 22, #across.list > 0, "Market:map") then
    Map.Price(chosen, true)
    Map.Open()
  end
  line += 22
  if #across.list == 0 then
    Im.Text("The same everywhere: built of nothing traded in bulk.", dx, line, 12, Theme.DIM)
  else
    local shown: { { at: Core.PriceAt, tone: vector, tag: string } } = { { at = across.list[1], tone = Theme.GOOD, tag = "cheapest" } }
    if #across.list > 2 then
      table.insert(shown, { at = across.list[2], tone = Theme.GOOD, tag = "" })
    end
    if #across.list > 1 then
      table.insert(shown, { at = across.list[#across.list], tone = Theme.BAD, tag = "dearest" })
    end
    for index, each in shown do
      local rowY = line + (index - 1) * 17
      local wide = Im.TextWidth(List.Cut(each.at.name, 110, 13, false), 13)
      Im.Text(List.Cut(each.at.name, 110, 13, false), dx, rowY, 13, Theme.TEXT)
      if each.tag ~= "" then
        Im.Pill(string.upper(each.tag), dx + wide + 8, rowY - 1, each.tone)
      end
      local jumps = if each.at.jumps == 1 then "1 jump" else `{each.at.jumps} jumps`
      Im.Text(jumps, dx + dw - 96 - Im.TextWidth(jumps, 12), rowY + 1, 12, Theme.DIM)
      local level = percent(each.at.level)
      Im.Text(level, dx + dw - Im.TextWidth(level, 13), rowY, 13, each.tone)
    end
  end
  line += 3 * 17 + 8

  -- Standing orders.
  heading("Standing orders", dx, line, dw)
  line += 22
  local bestSell = math.max(1, math.floor(quote.sellAt))
  local sellAt = if sellPrice > 0 then sellPrice else bestSell
  Im.Text("Sell at", dx, line + 5, 13, Theme.DIM)
  local enteredSell = Im.Number("SellPrice", sellAt, dx + 48, line, 86, 24, 12)
  if enteredSell ~= sellAt then
    sellPrice = enteredSell
    sellAt = enteredSell
  end
  local sellOrder: State.Command = { kind = "PlaceOrder", actor = 0, to = "sell", item = if stack then stack.id else 0,
    quantity = quantity, price = sellAt }
  local canSellOrder, whyNotSellOrder = false, "You have none in the hangar here" :: string?
  if stack ~= nil then
    canSellOrder, whyNotSellOrder = Session.CanDo(session, sellOrder)
  end
  Im.Because(whyNotSellOrder)
  if Im.Button("Place sell order", dx + 140, line, dw - 140, 24, canSellOrder, "PlaceSell") then
    Session.Do(session, sellOrder)
  end
  line += 26
  Im.Text(if sellAt <= quote.sellAt then "fills at once, at the pace of the station's customers"
    else `waits: customers pay up to {Format.Whole(bestSell)} now`, dx, line, 12, if sellAt <= quote.sellAt then Theme.GOOD else Theme.DIM)
  line += 18
  local bestBuy = if quote.buyAt then math.ceil(quote.buyAt) else math.ceil(quote.bid)
  local buyAt = if buyPrice > 0 then buyPrice else bestBuy
  Im.Text("Buy at", dx, line + 5, 13, Theme.DIM)
  local enteredBuy = Im.Number("BuyPrice", buyAt, dx + 48, line, 86, 24, 12)
  if enteredBuy ~= buyAt then
    buyPrice = enteredBuy
    buyAt = enteredBuy
  end
  local buyOrder: State.Command = { kind = "PlaceOrder", actor = 0, to = "buy", type = chosen, quantity = quantity, price = buyAt }
  local canOrder, whyNotOrder = Session.CanDo(session, buyOrder)
  Im.Because(if whyNotOrder then tostring(whyNotOrder) else nil)
  if Im.Button("Place buy order", dx + 140, line, dw - 140, 24, canOrder, "PlaceBuy") then
    Session.Do(session, buyOrder)
  end
  line += 26
  local fillsNow = quote.buyAt ~= nil and buyAt >= quote.buyAt
  Im.Text(if fillsNow then "fills at once, at the pace of the station's customers"
    else `waits: sellers take {Format.Whole(bestBuy)} or more now`, dx, line, 12, if fillsNow then Theme.GOOD else Theme.DIM)
  local _ = h
end

Windows.Kind(Market.ID, function(_: Windows.Window, x: number, y: number, w: number, h: number)
  local session = current
  if session == nil then
    return
  end
  local game = session.game
  local station = Core.Query.Player(game).at
  local was = Im.Plain(true)
  if station == 0 then
    Im.Text("The market is a station's: dock at one, or enter the field of a tower of yours.", x + 14, y + 14, 14, Theme.DIM)
    Im.Plain(was)
    return
  end
  -- (what can be done here is what the station has a module for)
  local lacks = true
  for _, service in select(2, Core.Query.Station(game, station)) do
    lacks = lacks and service ~= "market"
  end
  -- The pages.
  local orders = #Core.Query.Orders(game, nil)
  local tx = x + 10
  for _, each in { { "browse", "Browse", "Market:browse", 0 }, { "orders", "My orders", "Category:orders", orders } } :: { { any } } do
    local pressed, wide = Im.Tab(each[2], tx, y + 4, 28, page == each[1], each[3], each[4])
    if pressed then
      page = each[1]
    end
    tx += wide + 2
  end
  local tax, fee = Core.Query.Fees(game)
  local fees = if lacks then `This station has no {Structures.Provider("market")}.`
    else string.format("broker %.1f%%  -  sales tax %.1f%%", fee * 100, tax * 100)
  Im.Text(fees, x + w - 12 - Im.TextWidth(fees, 12), y + 11, 12, if lacks then Theme.BAD else Theme.DIM)
  Im.Flat(x + 1, y + 32, w - 2, 1, Theme.EDGE)
  local top, room = y + 33, h - 34
  if page == "orders" then
    drawOrders(session, game, station, x + 1, top, w - 2, room)
  else
    local listW = w - TREE_W - DETAIL_W
    drawTree(x + 1, top, TREE_W - 1, room)
    Im.Flat(x + TREE_W, top, 1, room, Theme.EDGE)
    drawList(game, station, x + TREE_W + 1, top, listW - 1, room)
    Im.Flat(x + TREE_W + listW, top, 1, room, Theme.EDGE)
    drawDetail(session, game, station, x + TREE_W + listW + 1, top, DETAIL_W - 2, room)
  end
  Im.Plain(was)
end)
Windows.Make(Market.ID, Market.ID, "Market", 534, 130, 1130, 720, 1000, 700, nil)
Windows.Icon(Market.ID, "market")
-- (the docked screen's own way to it: its Skills tab buys a book here)
Fitting.Market = Market.Choose
SkillSheet.Market = Market.Choose
Info.Market = Market.Choose

return Market
