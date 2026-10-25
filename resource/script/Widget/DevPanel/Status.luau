--!strict
-- The developer panel's status bar (Luau port of
-- Widget/DevPanel/Status.lts).

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Widgets = require("@lt/Widgets")

return {
  Create = function(): Widget
    local status = Widget_ListHorizontal(8, Widget_Luau(Widget_Create(), {
      CreateChildren = function(): { Widget }
        local ms = math.round(FrameTimer_GetEMA01() * 1000)
        return {
          Widgets.EmptySpaceH(),
          Widgets.ListH(2,
            Components.AlignCenter(Widgets.Text(Fonts.Default(), "RENDERED IN", 14, vector.create(0.3, 0.3, 0.3))),
            Components.AlignCenter(Widgets.Text(Fonts.Medium(), `{ms} ms`, 14, Colors.Primary))),
        }
      end,
      PreDraw = function(_, w: Widget)
        WidgetRenderer_DrawPanel(w.pos, w.size, 0.1, 0.5, 1, 0)
      end,
      PreUpdate = function(_, w: Widget)
        w:Rebuild()
      end,
    }))
    return Components.Backdrop(vector.create(0.1, 0.1, 0.1), 0, 1, 0, Components.Padding(8, 8, status))
  end,
}
