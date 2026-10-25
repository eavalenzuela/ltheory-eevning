--!strict
-- The market's category tabs with item counts (Luau port of
-- Widget/Market/LeftPanel.lts). The selected tab filters the item list.

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local ScrollFrame = require("@lt/Widget/ScrollFrame")
local Tab = require("@lt/Widget/Tab")
local Widgets = require("@lt/Widgets")

local LeftPanel = {}

local CATEGORIES = {
  "all", "ammo", "armor", "blueprint", "commodity", "compound", "data", "drone",
  "jump drive", "ore", "production lab", "power generator", "scanner", "shield",
  "ship", "station", "tech lab", "thruster", "transfer unit", "weapon", "worker",
}

local function category(market: Object, name: string): Widget
  return Components.Expand(Widget_ListHorizontal(8, Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      local count = 0
      local listings = market:GetMarketListings()
      while listings:HasMore() do
        local kind = string.lower(listings:Get().item:GetTypeString())
        if name == "all" or string.find(kind, name, 1, true) then
          count += 1
        end
        listings:Advance()
      end
      if count > 0 then
        return {
          Components.Expand(Components.GreedyX(Tab.Create("category", string.upper(name)))),
          Components.AlignCenter(Widgets.Text(Fonts.Default(), tostring(count), 14, 1.5 * Colors.Primary)),
        }
      end
      return {
        Components.Expand(Components.GreedyX(Components.Margin(vector.create(12, 4), vector.create(8, 4),
          Widgets.Text(Fonts.Default(), string.upper(name), 13, vector.create(0.3, 0.3, 0.3))))),
      }
    end,
  })))
end

function LeftPanel.Create(market: Object): Widget
  local list = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      local tabs = {}
      for _, name in CATEGORIES do
        table.insert(tabs, category(market, name))
      end
      return tabs
    end,
    Receive = function(_, w: Widget, message: any)
      if type(message) == "table" and message.type == "TabSelect" then
        w:SendDown(message)
      end
    end,
  })
  local bar = Widget_Luau(Widget_Stack(Widget_Create()), {
    CreateChildren = function(): { Widget }
      return { Components.AlignCenter(Widgets.Text(Fonts.Subheading(), "CATEGORY", 16, vector.create(0.4, 0.4, 0.4))) }
    end,
    PreDraw = function(_, w: Widget)
      WidgetRenderer_DrawPanel(w.pos, w.size, 0.1, 0.5, 1, 0)
    end,
  })
  local panel = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return {
        Components.Expand(Components.AlignCenter(Components.Padding(8, 8, bar))),
        ScrollFrame.V(Components.Expand(Components.GreedyY(Widget_ListVertical(0, list)))),
      }
    end,
  })
  return Widget_ListVertical(8, panel)
end

return LeftPanel
