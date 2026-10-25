--!strict
-- A labelled button that flips options[key] when clicked (Luau port of
-- Widget/ToggleButton.lts), lit while it is true.

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Widgets = require("@lt/Widgets")

return {
  Create = function(options: { [string]: boolean }, key: string, text: string): Widget
    return Components.Padding(16, 16, Components.CaptureMouse(Widget_Stack(Widget_Luau(Widget_Create(), {
      GetName = function(): string
        return text
      end,
      CreateChildren = function(): { Widget }
        return { Widgets.Text(Fonts.Default(), text, 14, vector.create(1, 1, 1)) }
      end,
      PreDraw = function(_, w: Widget)
        local c = if options[key] then Colors.Primary else vector.create(0.1, 0.1, 0.1)
        WidgetRenderer_DrawPanel(w.pos, w.size, c, 0.75, 1, 0)
      end,
      PostUpdate = function(_, w: Widget)
        if w.focusMouse and Mouse_LeftPressed() then
          options[key] = not options[key]
        end
      end,
    }))))
  end,
}
