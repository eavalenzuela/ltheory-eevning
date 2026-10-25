--!strict
-- The model editor's top-down view (Luau port of
-- Widget/ModelEditor/Editor.lts): drag pieces to move them, scroll to zoom,
-- WASD to pan. Mirrored copies show where symmetry is on.

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Types = require("@lt/Widget/ModelEditor/Types")

local Editor = {}

function Editor.Create(options: Types.Options, model: Types.ModelT): Widget
  local zoom = 1
  local pan = vector.create(0, 0)
  local dragging: Types.Piece? = nil
  local hovered: Types.Piece? = nil
  local camPos = vector.create(0, -100, 0)
  local camLook = vector.create(0, 1, 0)
  local camUp = vector.create(0, 0, 1)
  local camFov = math.pi / 180

  local view = Widget_Luau(Widget_Create(), {
    PreDraw = function(_, w: Widget)
      ClipRegion_Push(w.pos, w.size)
      hovered = nil
      local size = math.min(w.size.x, w.size.y)
      local cursor = Cursor_Get()
      local function screen(x: number, z: number): vector
        return w:Center() + 0.5 * size * (vector.create(x, z) + pan) / zoom
      end
      for _, piece in model.pieces do
        local p = screen(piece.center.x, -piece.center.z)
        local s = 0.5 * size * vector.create(piece.scale.x, piece.scale.z) / zoom
        local lo, hi = p - 0.5 * s, p + 0.5 * s
        local focus = cursor.x >= lo.x and cursor.y >= lo.y and cursor.x <= hi.x and cursor.y <= hi.y
        if focus and not hovered then
          hovered = piece
        end
        local r = piece.bevel * math.min(s.x, s.y)
        WidgetRenderer_DrawPanel(lo, s, 0.1, 1, 1, r)
        WidgetRenderer_DrawRenderable(piece.model, Transform_ST(0.5 * piece.scale, piece.center),
          camPos, camLook, camUp, camFov, w.pos, w.size, Colors.Primary, 1, 0)

        if options.symmetryX and math.abs(piece.center.x) > 0 then
          WidgetRenderer_DrawPanel(screen(-piece.center.x, -piece.center.z) - 0.5 * s, s, 0.1, 0.2, 0.5, r)
        end
        if options.symmetryZ and math.abs(piece.center.z) > 0 then
          WidgetRenderer_DrawPanel(screen(piece.center.x, piece.center.z) - 0.5 * s, s, 0.1, 0.5, 0.5, r)
        end
        if focus then
          WidgetRenderer_DrawPanel(lo, s, Colors.Primary, 1, 1, r)
        end
      end
    end,
    PostDraw = function()
      ClipRegion_Pop()
    end,
    PostUpdate = function(_, w: Widget)
      if Mouse_LeftPressed() and hovered then
        dragging = hovered
      end
      local piece = dragging
      if piece then
        local dp = Cursor_GetDelta() / w.size
        piece.center = vector.create(piece.center.x + 4 * dp.x * zoom, piece.center.y, piece.center.z - 2 * dp.y * zoom)
      end
      if w.focusScroll then
        zoom *= 1 - 0.1 * Mouse_GetScrollDelta()
      end
      if w.focusKey then
        local amount = FrameTimer_Get() * zoom
        if Key_Down(Key_W()) then pan -= vector.create(0, amount) end
        if Key_Down(Key_S()) then pan += vector.create(0, amount) end
        if Key_Down(Key_A()) then pan -= vector.create(amount, 0) end
        if Key_Down(Key_D()) then pan += vector.create(amount, 0) end
      end
      if Mouse_LeftReleased() then
        dragging = nil
      end
    end,
  })
  return Components.Expand(Components.GreedyX(Components.Backdrop(vector.create(0.05, 0.05, 0.05), 0.5, 1, 0,
    Components.CaptureMouse(Components.CaptureKey(Components.CaptureScroll(view))))))
end

return Editor
