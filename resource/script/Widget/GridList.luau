--!strict
-- A titled list with List / Grid view tabs (Luau port of
-- Widget/GridList.lts). Only the toolbar was ever implemented: the grid
-- view and the contents were disabled in LTSL, and stay so here.

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Icons = require("@lt/Icons")
local Tab = require("@lt/Widget/Tab")
local Widgets = require("@lt/Widgets")

local GridList = {}

function GridList.Create(name: string, _widget: Widget): Widget
  local toolbar = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      local color = 0.75 * Colors.Primary
      local dim = vector.create(0.125, 0.125, 0.125)
      return {
        Components.AlignCenter(Widgets.Text(Fonts.Default(), name, 14, vector.create(1, 1, 1))),
        Components.Expand(Components.GreedyX(Widget_Create())),
        Components.AlignCenter(Widgets.ListH(8,
          Components.MinSize(32, Tab.CreateIcon("mode", "List", Icons.Log(), dim, color, false, false, true)),
          Components.MinSize(32, Tab.CreateIcon("mode", "Grid", Icons.Cargo(), dim, color, false, false, false)))),
      }
    end,
    PreDraw = function(_, w: Widget)
      WidgetRenderer_DrawPanel(w.pos, w.size, 0.05, 0.5, 1, 16)
    end,
    Receive = function(_, w: Widget, message: any)
      if type(message) == "table" and message.type == "TabSelect" then
        w:SendDown(message)
      end
    end,
  })
  local inset = vector.create(12, 8)
  return Components.Expand(Widgets.ListV(4,
    Components.Expand(Components.Padding(inset, inset, Widget_ListHorizontal(4, toolbar)))))
end

return GridList
