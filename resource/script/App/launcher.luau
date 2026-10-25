--!strict
-- The list of apps over a screenshot (Luau port of App/launcher.lts).

local AppShell = require("@lt/AppShell")
local Apps = require("@lt/Widget/DevPanel/Apps")
local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local FrameInfo = require("@lt/Widget/Dev/FrameInfo")
local Icons = require("@lt/Icons")
local RandomScreenshot = require("@lt/Texture/RandomScreenshot")
local Widgets = require("@lt/Widgets")

return AppShell.Create(function(): Widget
  local texture = RandomScreenshot.Get()
  local selector = Widget_ListVertical(8, Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      local rows = {}
      for _, name in Apps.List() do
        table.insert(rows, Widgets.Text(Fonts.Default(), name, 16, vector.create(1, 1, 1)))
      end
      return rows
    end,
  }))
  local root = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return { Components.AlignCenter(selector) }
    end,
    PreDraw = function(_, w: Widget)
      WidgetRenderer_DrawPanel(w.pos, w.size, vector.create(0.1, 0.2, 0.3), 1, 1, 0)
      WidgetRenderer_DrawTexture(texture, w.pos, w.size, 1)
    end,
    PostDraw = function(_, w: Widget)
      Icon_Draw(Icons.Cursors.Pointer(), Cursor_Get(), 12, 4 * Colors.Primary, 0.3)
      FrameInfo.Draw(w)
    end,
  })
  return Widget_Layer(Compositor_None(), Mesh_Quad(), 1, Widget_Stack(root))
end)
