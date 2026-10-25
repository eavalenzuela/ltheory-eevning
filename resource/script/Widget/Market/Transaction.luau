--!strict
-- The buy / sell dialog for one item (Luau port of
-- Widget/Market/Transaction.lts): pick a quantity, see the price, confirm.
-- Orders are placed against the best standing orders; selling starts at
-- everything you hold, buying at one.

local Colors = require("@lt/Colors")
local Button = require("@lt/Widget/Button")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Messages = require("@lt/Widget/Messages")
local Slider = require("@lt/Widget/Slider")
local Widgets = require("@lt/Widgets")

local Transaction = {}

-- The standing orders a trade fills: asks when buying, bids when selling
local function orders(market: Object, item: Item, buying: boolean): Vector_Reference_OrderT
  local data = market:GetMarketData(item)
  return if buying then data.asks else data.bids
end

local function details(player: Player, market: Object, item: Item, buying: boolean): Widget
  local white = vector.create(1, 1, 1)
  local function row(label: string, value: string, color: vector?): Widget
    return Components.Expand(Widgets.Pair(8,
      Widgets.Text(Fonts.Default(), label, 16, white),
      Widgets.Text(Fonts.Default(), value, 16, color or white)))
  end
  return Widget_Luau(Widget_Create(), {
    CreateChildren = function(_, w: Widget): { Widget }
      local quantity = tonumber(Messages.GetLabel(w, "quantity")) or 0
      local remaining, price = quantity, 0
      local book = orders(market, item, buying)
      for i = 0, book:Size() - 1 do
        if remaining <= 0 then
          break
        end
        local order = book:Get(i)
        local q = math.min(remaining, order.volume)
        remaining -= q
        price += q * order.price
      end
      local credits = player:GetCredits()
      local after = if buying then credits - price else credits + price
      return {
        row("Quantity", tostring(quantity)),
        row("Average Price Per Unit", tostring(if quantity > 0 then price / quantity else 0)),
        row("Total Price", tostring(price)),
        Widgets.SpacerH(8),
        row("Account", `{credits} LTC`),
        row("After Transaction", `{after} LTC`, if buying then Colors.Bad else Colors.Good),
      }
    end,
    PreUpdate = function(_, w: Widget)
      w:Rebuild()
    end,
  })
end

function Transaction.Create(player: Player, market: Object, item: Item, buying: boolean): Widget
  local white = vector.create(1, 1, 1)
  local window = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      local book = orders(market, item, buying)
      local available = 0
      for i = 0, book:Size() - 1 do
        available += book:Get(i).volume
      end
      local minimum, maximum = 1, available
      if not buying then
        local held = market:GetStorageLocker(player):GetItemCount(item)
        minimum = math.min(minimum, held)
        maximum = math.min(maximum, held)
      end
      local start = if buying then minimum else maximum

      return {
        Widgets.ListH(8,
          Components.AlignCenter(Widgets.ListH(0,
            Components.AlignCenter(Widgets.Text(Fonts.Medium(), if buying then "BUY " else "SELL ", 20, Colors.Primary)),
            Components.AlignCenter(Widgets.Text(Fonts.Medium(), string.upper(item:GetName()), 20, white)))),
          Components.AlignCenter(Components.MinSize(32, Widgets.Icon(item:GetIcon(), 2 * Colors.Primary)))),
        Widgets.SpacerH(8),
        Components.Expand(Widget_ListVertical(8, details(player, market, item, buying))),
        Widgets.SpacerH(8),
        Components.AlignCenter(Widgets.Text(Fonts.Default(), if buying then "Transfer To" else "Transfer From", 16, white)),
        Components.Backdrop(vector.create(0.08, 0.08, 0.08), 0.5, 1, 0, Widgets.Text(Fonts.Default(), "STORAGE", 16, white)),
        Widgets.SpacerH(8),
        Components.Expand(Slider.Create("quantity", minimum, maximum, start)),
        Components.Expand(Widgets.ListH(4,
          Components.Expand(Components.GreedyX(Button.Create({ type = "Confirm" }, "CONFIRM", 16))),
          Components.Expand(Components.GreedyX(Button.Create(Messages.Cancel(), "CANCEL", 16))))),
      }
    end,
    PreDraw = function(_, w: Widget)
      WidgetRenderer_DrawPanel(w.pos, w.size, 0.1, 0.5, 1, 8)
    end,
    Receive = function(_, w: Widget, message: any)
      if type(message) ~= "table" then
        return
      end
      if message.type == "Confirm" then
        local remaining = tonumber(Messages.GetLabel(w, "quantity")) or 0
        local book = orders(market, item, buying)
        for i = 0, book:Size() - 1 do
          if remaining <= 0 then
            break
          end
          local order = book:Get(i)
          local q = math.min(remaining, order.volume)
          remaining -= q
          if buying then
            market:AddMarketBuyOrder(player, item, q, order.price)
          else
            market:AddMarketSellOrder(player, item, q, order.price)
          end
        end
        Sound_Play("ui/confirm.ogg", 0.2)
        w:SendUp(Messages.Refresh())
        w:Delete()
      elseif message.type == "Cancel" then
        w:Delete()
      elseif message.type == "GetLabel" then
        w:SendDown(message)
      end
    end,
  })
  return Widgets.FocusWindow(0.9, Components.AlignCenter(Components.MinSize(vector.create(256, 0),
    Components.Padding(16, 16, Widget_ListVertical(8, window)))))
end

return Transaction
