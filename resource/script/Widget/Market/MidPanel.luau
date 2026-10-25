--!strict
-- The market's item list with prices, supply / demand and what you hold
-- here, plus the search bar (Luau port of Widget/Market/MidPanel.lts).
-- Click an item to select it (shift-click to select several).

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Messages = require("@lt/Widget/Messages")
local RightPanel = require("@lt/Widget/Market/RightPanel")
local ScrollFrame = require("@lt/Widget/ScrollFrame")
local TextField = require("@lt/Widget/TextField")
local Widgets = require("@lt/Widgets")

local MidPanel = {}

-- Best price and total volume of a list of orders ('best' picks max/min)
local function summarize(book: Vector_Reference_OrderT, best: (number, number) -> number): (string, string)
  if book:Size() == 0 then
    return " - ", " - "
  end
  local price, volume = book:Get(0).price, 0
  for i = 0, book:Size() - 1 do
    local order = book:Get(i)
    price = best(price, order.price)
    volume += order.volume
  end
  return tostring(price), tostring(volume)
end

local function element(player: Player, market: Object, item: Item): Widget
  local selected = false
  local row = Widget_Luau(Widget_Create(), {
    GetName = function()
      return item:GetName()
    end,
    GetHash = function()
      return item:GetHash()
    end,
    Destroy = function(_, w: Widget)
      if selected then
        w:SendUp(Messages.UnselectItem(item))
      end
    end,
    CreateChildren = function(): { Widget }
      local data = market:GetMarketData(item)
      local sellPrice, demand = summarize(data.bids, math.max)
      local buyPrice, supply = summarize(data.asks, math.min)
      local textColor = if selected then vector.create(0.1, 0.1, 0.1) else vector.create(1, 1, 1)
      local valueColor = if selected then vector.create(0.1, 0.1, 0.1) else 1.5 * Colors.Primary
      local iconColor = if selected then -1 * Colors.Primary else Colors.Primary
      local held = market:GetStorageLocker(player):GetItemCount(item)
      local font = Fonts.Default()
      local function column(width: number, text: string, size: number, color: vector): Widget
        return Components.MinSize(vector.create(width, 0), Components.AlignCenter(Widgets.Text(font, text, size, color)))
      end
      return {
        Components.Margin(vector.create(4, 0), vector.create(8, 0), Components.MinSize(24, Widgets.Icon(item:GetIcon(), iconColor))),
        column(200, item:GetName(), 16, textColor),
        column(96, buyPrice, 14, valueColor),
        column(96, sellPrice, 14, valueColor),
        column(96, `{supply} / {demand}`, 14, valueColor),
        Components.AlignCenter(Widgets.Text(font, if held > 0 then tostring(held) else "", 14, valueColor)),
      }
    end,
    PreDraw = function(_, w: Widget)
      local c = if selected then 2 * Colors.Primary else vector.create(0.1, 0.1, 0.1)
      WidgetRenderer_DrawPanel(w.pos, w.size, c, 0.5, 1, 0)
    end,
    PostUpdate = function(_, w: Widget)
      if not Mouse_LeftPressed() or not w.focusMouse then
        return
      end
      local shift = Key_Down(Key_LShift())
      if selected and shift then
        selected = false
        w:Rebuild()
        w:SendUp(Messages.UnselectItem(item))
      elseif not selected then
        selected = true
        w:Rebuild()
        w:SendUp(Messages.SelectItem(item))
        Sound_Play("ui/elementselect.wav", 0.2)
        if not shift then
          w:SendUp(Messages.Selected(w))
        end
      end
    end,
    Receive = function(_, w: Widget, message: any)
      if type(message) == "table" and message.type == "Selected" and message.widget ~= w and selected then
        selected = false
        w:Rebuild()
        w:SendUp(Messages.UnselectItem(item))
      end
    end,
  })
  return Components.FocusGlow(Components.Expand(Components.AlignCenter(Components.Padding(8, 8, Widget_ListHorizontal(8, row)))))
end

-- The listings matching the selected category and the search text
local function contentList(player: Player, market: Object, filter: TextField.Contents): Widget
  return Widget_Luau(Widget_Create(), {
    CreateChildren = function(_, w: Widget): { Widget }
      local rows = {}
      local category = string.lower(tostring(Messages.GetLabel(w, "category") or "all"))
      local search = string.lower(filter.text)
      local listings = market:GetMarketListings()
      while listings:HasMore() do
        local item = listings:Get().item
        local name = string.lower(item:GetName())
        local kind = string.lower(item:GetTypeString())
        if string.find(name, search, 1, true)
          and (category == "all" or string.find(kind, category, 1, true)) then
          table.insert(rows, element(player, market, item))
        end
        listings:Advance()
      end
      return rows
    end,
    Receive = function(_, w: Widget, message: any)
      if type(message) ~= "table" then
        return
      end
      if message.type == "Refresh" then
        w:Rebuild()
      elseif message.type == "Selected" then
        w:SendDown(message)
      end
    end,
  })
end

local function attributeBar(): Widget
  local dim = vector.create(0.3, 0.3, 0.3)
  local function heading(width: number, text: string, size: number, center: boolean): Widget
    local label = Widgets.Text(Fonts.Subheading(), text, size, dim)
    return Components.MinSize(vector.create(width, 0),
      if center then Components.AlignCenter(label) else Components.AlignLeftCenter(label))
  end
  return Widget_Luau(Widget_ListHorizontal(8, Widget_Create()), {
    CreateChildren = function(): { Widget }
      return {
        Components.MinSize(vector.create(40, 0), Widget_Create()),
        heading(200, "ITEM", 15, true),
        heading(96, "BUY PRICE", 15, false),
        heading(96, "SELL PRICE", 15, false),
        heading(96, "SUPPLY / DEMAND", 14, false),
      }
    end,
    PreDraw = function(_, w: Widget)
      WidgetRenderer_DrawPanel(w.pos, w.size, 0.1, 0.5, 1, 0)
    end,
  })
end

function MidPanel.Create(player: Player, market: Object): Widget
  local filter: TextField.Contents = { text = "" }
  local dim = vector.create(0.4, 0.4, 0.4)
  local panel = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return {
        Components.Expand(Components.Padding(vector.create(12, 8), 8, attributeBar())),
        Components.Expand(Components.GreedyY(Widgets.ListH(8,
          Components.GreedyX(ScrollFrame.V(Components.Expand(Widget_Dynamic(Components.Padding(4, 4,
            Widget_ListVertical(8, contentList(player, market, filter))))))),
          Components.Expand(RightPanel.Create(player, market))))),
        Components.Expand(Components.Padding(vector.create(12, 4), vector.create(12, 4),
          Components.Backdrop(vector.create(0.1, 0.1, 0.1), 0.5, 1, 0, Widgets.ListH(8,
            Components.AlignCenter(Widgets.Text(Fonts.Subheading(), "SEARCH", 16, dim)),
            Components.AlignCenter(TextField.Create(16, filter)))))),
      }
    end,
  })
  return Widget_ListVertical(4, panel)
end

return MidPanel
