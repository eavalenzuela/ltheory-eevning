--!strict
-- The image editor on a random screenshot (Luau port of App/image.lts).

local AppShell = require("@lt/AppShell")
local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Icons = require("@lt/Icons")
local ImageEditor = require("@lt/Widget/ImageEditor")
local RandomScreenshot = require("@lt/Texture/RandomScreenshot")

return AppShell.Create(function(): Widget
  local root = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return { Components.Expand(Components.Margin(16, 16, ImageEditor.Create(RandomScreenshot.Get(), "image.png"))) }
    end,
    PreDraw = function(_, w: Widget)
      WidgetRenderer_DrawPanel(w.pos, w.size, 0.01, 1, 1, 0)
      Glyph_Draw(Glyph_Grid(w:TopLeft(), w:BottomRight(), 1, 1, 0, 0.25), 0, 1, Colors.Primary, 0.2)
    end,
    PostDraw = function()
      Icon_Draw(Icons.Cursors.Pointer(), Cursor_Get(), 12, 4 * Colors.Primary, 0.3)
    end,
    PostUpdate = function()
      Thread_SleepMS(16)
    end,
  })
  return Widget_Layer(Compositor_None(), Mesh_Quad(), 1, Widget_Stack(root))
end)
