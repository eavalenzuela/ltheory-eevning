--!strict
-- A vertically scrolling frame (Luau port of Widget/ScrollFrame.lts and the
-- ScrollFrame helpers in Widgets.lts). Mouse wheel, PageUp/PageDown and
-- Home/End scroll it; a bar shows the position when content overflows.

local Components = require("@lt/Widget/Components")

local ScrollFrame = {}

local function mix(a: number, b: number, t: number): number
  return a + (b - a) * t
end

local function vertical(): any
  local scroll, target, innerSize, excess = 0, 0, 0, 0
  local function clip(w: Widget)
    ClipRegion_Push(vector.create(-100000, w.pos.y), vector.create(200000, w.size.y))
  end
  return {
    PrePosition = function(_, w: Widget)
      innerSize = w.minSize.y
      w.minSize = vector.create(w.minSize.x, 0)
    end,
    PostPosition = function(_, w: Widget)
      local children = w:GetChildren()
      while children:HasMore() do
        local child = children:Get()
        child.pos -= vector.create(0, scroll)
        children:Advance()
      end
      excess = math.max(0, innerSize - w.size.y)
    end,
    PreDraw = function(_, w: Widget)
      clip(w)
    end,
    PostDraw = function(_, w: Widget)
      ClipRegion_Pop()
      if excess > 0 then
        local topRight, bottomRight = w:TopRight(), w:BottomRight()
        local z = 0.5 * w.size.y * (w.size.y / innerSize)
        local y = mix(topRight.y, bottomRight.y - z, scroll / excess)
        WidgetRenderer_DrawPanel(vector.create(topRight.x - 4, w.pos.y), vector.create(2, w.size.y), 0.1, 0.5, 0.5, 0)
        WidgetRenderer_DrawPanel(vector.create(topRight.x - 6, y), vector.create(6, z), 0.2, 1, 0.5, 0)
      end
    end,
    PreUpdate = function(_, w: Widget)
      clip(w)
    end,
    PostUpdate = function(_, w: Widget)
      ClipRegion_Pop()
      if w.focusKey then
        if Key_Pressed(Key_PageDown()) then target += w.size.y end
        if Key_Pressed(Key_PageUp()) then target -= w.size.y end
        if Key_Pressed(Key_Home()) then target = 0 end
        if Key_Pressed(Key_End()) then target = excess end
      end
      if w.focusScroll then
        target -= 0.1 * w.size.y * Mouse_GetScrollDelta()
      end
      target = math.clamp(target, 0, excess)
      scroll = mix(scroll, target, 1 - Float_ExpDecay(FrameTimer_Get(), 0.1))
    end,
  }
end

-- 'widget' in a frame that scrolls vertically
function ScrollFrame.V(widget: Widget): Widget
  local frame = Widget_Luau(Widget_Stack(Widget_Create()), vertical())
  frame:AddChild(Components.Margin(0, vector.create(8, 0), widget))
  return Components.CaptureKey(Components.CaptureScroll(Components.Expand(Components.GreedyY(frame))))
end

-- Horizontal scrolling was never implemented in LTSL either: the content
-- is shown unscrolled
function ScrollFrame.H(widget: Widget): Widget
  local frame = Widget_Stack(Widget_Create())
  frame:AddChild(Components.Margin(0, vector.create(8, 0), widget))
  return Components.CaptureKey(Components.CaptureScroll(Components.Expand(Components.GreedyY(frame))))
end

return ScrollFrame
