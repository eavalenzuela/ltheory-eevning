--!strict
-- Layout skeleton for a structure editor (Luau port of App/strukt.lts): a
-- toolbar, an empty canvas and a status bar. F3 shows frame statistics.

local AppShell = require("@lt/AppShell")
local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local FrameInfo = require("@lt/Widget/Dev/FrameInfo")
local Icons = require("@lt/Icons")

local function bar(height: number): Widget
  return Components.Expand(Components.MinSize(height,
    Components.Backdrop(vector.create(0.1, 0.1, 0.1), 0.5, 1, 0, Widget_Create())))
end

return AppShell.Create(function(): Widget
  local canvas = Components.Expand(Components.GreedyY(Widget_Stack(Widget_Create())))
  local ui = Widget_ListVertical(0, Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return { bar(64), canvas, bar(24) }
    end,
  }))
  local root = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return { Components.Expand(Components.Backdrop(vector.create(0.08, 0.08, 0.08), 1, 1, 0, ui)) }
    end,
    PostDraw = function(_, w: Widget)
      Icon_Draw(Icons.Cursors.Pointer(), Cursor_Get(), 10, Colors.Primary, 1)
      if Key_Down(Key_F3()) then
        FrameInfo.Draw(w)
      end
    end,
  })
  return Widget_Layer(Compositor_Basic(0.05, 0.1, vector.create(0.4, 0.5, 0.9)), Mesh_Quad(), 1, Widget_Stack(root))
end)
