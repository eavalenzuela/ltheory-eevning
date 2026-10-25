--!strict
-- The selected item's details with Buy / Sell / Withdraw (Luau port of
-- Widget/Market/RightPanel.lts). Withdraw moves the item from your hangar
-- here into your ship's hold.

local Button = require("@lt/Widget/Button")
local Components = require("@lt/Widget/Components")
local ItemInfo = require("@lt/Widget/ItemInfo")
local Messages = require("@lt/Widget/Messages")
local Widgets = require("@lt/Widgets")

local RightPanel = {}

export type Trade = { type: "Buy" | "Sell", item: Item }

local function itemPanel(player: Player, market: Object, item: Item): Widget
  local panel = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      local function button(message: any, label: string): Widget
        return Components.Expand(Components.GreedyX(Button.Create(message, label, 16)))
      end
      local buy: Trade = { type = "Buy", item = item }
      local sell: Trade = { type = "Sell", item = item }
      return {
        Components.Expand(Components.GreedyY(ItemInfo.Create(player, item))),
        Components.Expand(Widgets.ListH(4,
          button(buy, "BUY"),
          button(sell, "SELL"),
          button({ type = "Withdraw" }, "WITHDRAW"))),
      }
    end,
    Receive = function(_, w: Widget, message: any)
      if type(message) ~= "table" then
        return
      end
      if message.type == "UnselectItem" and message.item == item then
        w:Delete()
      elseif message.type == "Withdraw" then
        local ship = player:GetPiloting()
        if ship:GetContainer() == market then
          local moved = market:GetStorageLocker(player):TransferItem(ship, item, 1000000)
          if moved > 0 then
            player:AddLog(`Moved {moved} {item:GetName()} to your cargo hold`)
          else
            player:AddLog("None in your hangar, or no room in your cargo hold")
          end
          w:SendUp(Messages.Refresh())
        else
          player:AddLog(`Dock at {market:GetName()} to withdraw items`)
        end
      end
    end,
  })
  return Components.Expand(Components.GreedyY(Components.MinSize(vector.create(320, 0), Widget_ListVertical(8, panel))))
end

-- Shows a panel for each item selected in the list
function RightPanel.Create(player: Player, market: Object): Widget
  return Widget_ListHorizontal(8, Widget_Luau(Widget_Create(), {
    Receive = function(_, w: Widget, message: any)
      if type(message) == "table" and message.type == "SelectItem" then
        w:AddChild(itemPanel(player, market, message.item))
      end
    end,
  }))
end

return RightPanel
