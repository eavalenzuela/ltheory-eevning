--!strict
-- A HUD panel frame (Luau port of Widget/HUD/HUDWidget.lts). B unlocks
-- every panel for layout: drag one to move it, shift-drag to resize.

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Icons = require("@lt/Icons")

local HUDWidget = {}

function HUDWidget.Create(size: vector | number, widget: Widget): Widget
  local child = Components.Expand(widget)
  local panelSize = if type(size) == "number" then vector.create(size, size) else size
  local offset = vector.create(0, 0)
  local scalingDir = vector.create(0, 0)
  local locked, moving, scaling = true, false, false

  local frame = Widget_Luau(Widget_Create(), {
    CaptureFocus = function(_, w: Widget)
      if not locked then
        local c = Cursor_Get()
        local p1 = vector.max(w.pos, ClipRegion_GetMin())
        local p2 = vector.min(w.pos + w.size, ClipRegion_GetMax())
        w.focusMouse = p1.x <= c.x and p1.y <= c.y and c.x <= p2.x and c.y <= p2.y
      end
    end,
    CreateChildren = function(): { Widget }
      return { child }
    end,
    PrePosition = function(_, w: Widget)
      if moving then
        offset += Cursor_GetDelta()
      end
      if scaling then
        panelSize += scalingDir * Cursor_GetDelta()
      end
      w.minSize = vector.max(panelSize, w.minSize)
      w.pos += offset
    end,
    PostDraw = function(_, w: Widget)
      if not locked then
        local c = if w.focusMouse then Colors.Secondary else Colors.Primary
        local tl, tr, br, bl = w:TopLeft(), w:TopRight(), w:BottomRight(), w:BottomLeft()
        WidgetRenderer_DrawPanel(w.pos, w.size, 0.1, 0.95, 1, 0)
        Glyph_Draw(Glyph_Line(tl, tr, 1, 1), 0, 1, c, 1)
        Glyph_Draw(Glyph_Line(tr, br, 1, 1), 0, 1, c, 1)
        Glyph_Draw(Glyph_Line(br, bl, 1, 1), 0, 1, c, 1)
        Glyph_Draw(Glyph_Line(bl, tl, 1, 1), 0, 1, c, 1)
        WidgetRenderer_DrawText(Fonts.Default(), string.upper(child:GetName()), w:Center(), 16, 1, 1, true)
        WidgetRenderer_DrawText(Fonts.Default(), `{w.size.x} X {w.size.y}`, w:Center() + vector.create(0, 16), 14, 0.3, 1, true)
        Icon_Draw(Icons.Gear(), w:TopRight() + vector.create(-16, 16), 10, Colors.Primary, 1)
      end
      if Key_Pressed(Key_B()) then
        locked = not locked
        if locked then
          w:AddChild(child)
        else
          w:RemoveChild(child)
        end
      end
    end,
    PostUpdate = function(_, w: Widget)
      if w.focusMouse and Mouse_LeftPressed() then
        if Key_Shift() then
          scaling = true
          local d = Cursor_Get() - w:Center()
          scalingDir = vector.create(math.sign(d.x), math.sign(d.y))
        else
          moving = true
        end
      end
      if (moving or scaling) and Mouse_LeftReleased() then
        moving = false
        scaling = false
      end
    end,
  })
  return Widget_Stack(frame)
end

return HUDWidget
