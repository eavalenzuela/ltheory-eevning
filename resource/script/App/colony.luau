--!strict
-- A generated star system's name on a blank panel (Luau port of
-- App/colony.lts, the start of a colony view).

local AppShell = require("@lt/AppShell")
local Colors = require("@lt/Colors")
local Fonts = require("@lt/Fonts")
local Icons = require("@lt/Icons")

return AppShell.Create(function(): Widget
  local system = Object_Universe(42, 0)
  while not system:IsSystem() do
    system = system:GetInteriorObjects():Get()
  end
  return Widget_Layer(Compositor_Basic(0.1, 0.1, vector.create(0.25, 0.50, 0.75)), Mesh_Quad(), 1,
    Widget_Luau(Widget_Create(), {
      PreDraw = function(_, w: Widget)
        WidgetRenderer_DrawPanel(w.pos, w.size, 0.1, 1, 1, 0)
      end,
      PostDraw = function()
        Icon_Draw(Icons.Cursors.Pointer(), Cursor_Get(), 12, 4 * Colors.Secondary, 0.5)
        WidgetRenderer_DrawText(Fonts.Heading(), system:GetName(), vector.create(16, 32), 72, 0.3, 1, false)
      end,
    }))
end)
