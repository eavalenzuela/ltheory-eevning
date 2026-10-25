--!strict
-- A station's market window (Luau port of Widget/Object/Market.lts):
-- categories, the item list, the selected item's panel and the buy / sell
-- dialog. Opened from the station panel or a station's Trade action.

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Icons = require("@lt/Icons")
local LeftPanel = require("@lt/Widget/Market/LeftPanel")
local MidPanel = require("@lt/Widget/Market/MidPanel")
local Transaction = require("@lt/Widget/Market/Transaction")
local Widgets = require("@lt/Widgets")

local Market = {}

local function toolbar(player: Player): Widget
  return Widget_Luau(Widget_ListHorizontal(8, Widget_Create()), {
    CreateChildren = function(): { Widget }
      local color = 1.5 * Colors.Primary
      local function icon(i: Icon): Widget
        return Components.AlignCenter(Components.MinSize(24, Widgets.Icon(i, color)))
      end
      return {
        Components.GreedyX(Components.Expand(Widget_Create())),
        Components.Padding(12, 12, Widgets.ListH(24, icon(Icons.Person()), icon(Icons.Trade()), icon(Icons.Comm()))),
        Components.AlignCenter(Widgets.Text(Fonts.Default(), `ACCOUNT : {player:GetCredits()} LTC`, 14, vector.create(1, 1, 1))),
      }
    end,
    Receive = function(_, w: Widget, message: any)
      if type(message) == "table" and message.type == "Refresh" then
        w:Rebuild()
      end
    end,
  })
end

function Market.Create(player: Player, market: Object): Widget
  local body = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return {
        Components.Backdrop(vector.create(0.08, 0.08, 0.08), 0.5, 1, 0, Components.Expand(toolbar(player))),
        Components.Expand(Components.GreedyY(Widgets.ListH(16,
          Components.Expand(LeftPanel.Create(market)),
          Components.Expand(Components.GreedyX(MidPanel.Create(player, market)))))),
      }
    end,
    Receive = function(_, w: Widget, message: any)
      if type(message) == "table" and (message.type == "SelectItem" or message.type == "UnselectItem") then
        w:SendDown(message)
      end
    end,
  })

  local frame = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return { Components.Expand(Widget_ListVertical(8, body)) }
    end,
    Receive = function(_, w: Widget, message: any)
      if type(message) ~= "table" then
        return
      end
      if message.type == "Buy" or message.type == "Sell" then
        w:AddChild(Transaction.Create(player, market, message.item, message.type == "Buy"))
      elseif message.type == "Refresh" or message.type == "GetLabel" then
        -- Labels (the selected category) live in other branches of the window
        w:SendDown(message)
      end
    end,
  })
  return Components.Expand(Components.AlignCenter(Widget_Stack(frame)))
end

return Market
