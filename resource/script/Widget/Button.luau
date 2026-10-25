--!strict
-- A labelled push button (Luau port of Widget/Button.lts). Pressing it sends
-- 'onPress' up the widget tree; it is named by its label.

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Widgets = require("@lt/Widgets")

local Button = {}

function Button.Create(onPress: any, text: string, size: number): Widget
  local focus = false
  local button = Widget_Luau(Widget_Create(), {
    GetName = function()
      return text
    end,
    CreateChildren = function(_, w: Widget): { Widget }
      local color = if w.focusMouse then vector.create(0, 0, 0) else vector.create(1, 1, 1)
      return { Components.AlignCenter(Widgets.Text(Fonts.Subheading(), text, size, color)) }
    end,
    PreDraw = function(_, w: Widget)
      local color = if focus then 2.5 * Colors.Primary else vector.create(0.15, 0.15, 0.15)
      WidgetRenderer_DrawPanel(w.pos, w.size, color, 0.5, 1, 0)
    end,
    PostUpdate = function(_, w: Widget)
      if w.focusMouse ~= focus then
        focus = w.focusMouse
        w:Rebuild()
        if focus then
          Sound_Play("ui/hover.wav", 0.008)
        end
      end
      if focus and Mouse_LeftPressed() then
        w:SendUp(onPress)
      end
    end,
  })
  return Components.CaptureMouse(Components.Padding(6, 6, Widget_Stack(button)))
end

return Button
