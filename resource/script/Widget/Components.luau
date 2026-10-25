--!strict
-- Layout and interaction components for widgets (Luau port of
-- Widget/Components.lts and Widget/Component/*.lts). Each function adds a
-- component to 'widget' and returns it, so they nest like the LTSL ones:
--
--   Components.AlignCenter(Components.MinSize(36, icon))
--
-- Sizes and offsets are vectors (x, y); a number means the same value for
-- both.

local Colors = require("@lt/Colors")
local Fonts = require("@lt/Fonts")

local Components = {}

local function v2(value: vector | number): vector
  if type(value) == "number" then
    return vector.create(value, value)
  end
  return value
end

local function mix(a: number, b: number, t: number): number
  return a + (b - a) * t
end

-- Whether the cursor is over the visible part of 'widget'
local function underCursor(widget: Widget): boolean
  local c = Cursor_Get()
  local p1 = vector.max(widget.pos, ClipRegion_GetMin())
  local p2 = vector.min(widget.pos + widget.size, ClipRegion_GetMax())
  return p1.x <= c.x and p1.y <= c.y and c.x <= p2.x and c.y <= p2.y
end

-- Fraction of the way to move toward a target this frame (smoothing)
local function approach(rate: number): number
  return 1 - Float_ExpDecay(FrameTimer_Get(), rate)
end

---------------------------------------------------------------- Alignment

-- Place 'widget' within its available space: 0 = left/top, 1 = right/bottom
function Components.Align(scale: vector, widget: Widget): Widget
  return Widget_Luau(widget, {
    PostPosition = function(_, w: Widget)
      w.pos += (w.maxSize - w.size) * scale
    end,
  })
end

function Components.AlignCenter(widget: Widget): Widget
  return Components.Align(vector.create(0.5, 0.5), widget)
end
function Components.AlignTopCenter(widget: Widget): Widget
  return Components.Align(vector.create(0.5, 0.0), widget)
end
function Components.AlignTopLeft(widget: Widget): Widget
  return Components.Align(vector.create(0.0, 0.0), widget)
end
function Components.AlignTopRight(widget: Widget): Widget
  return Components.Align(vector.create(1.0, 0.0), widget)
end
function Components.AlignLeftCenter(widget: Widget): Widget
  return Components.Align(vector.create(0.0, 0.5), widget)
end
function Components.AlignRightCenter(widget: Widget): Widget
  return Components.Align(vector.create(1.0, 0.5), widget)
end
function Components.AlignBottomCenter(widget: Widget): Widget
  return Components.Align(vector.create(0.5, 1.0), widget)
end
function Components.AlignBottomLeft(widget: Widget): Widget
  return Components.Align(vector.create(0.0, 1.0), widget)
end
function Components.AlignBottomRight(widget: Widget): Widget
  return Components.Align(vector.create(1.0, 1.0), widget)
end

------------------------------------------------------------------ Sizing

-- Grow toward the available space: 0 = minimum size, 1 = all of it
function Components.ExpandCustom(scale: vector, widget: Widget): Widget
  return Widget_Luau(widget, {
    PostPosition = function(_, w: Widget)
      local minSize, maxSize = w.minSize, w.maxSize
      w.size = vector.create(mix(minSize.x, maxSize.x, scale.x), mix(minSize.y, maxSize.y, scale.y))
    end,
  })
end

function Components.Expand(widget: Widget): Widget
  return Components.ExpandCustom(vector.create(1, 1), widget)
end
function Components.ExpandX(widget: Widget): Widget
  return Components.ExpandCustom(vector.create(1, 0), widget)
end
function Components.ExpandY(widget: Widget): Widget
  return Components.ExpandCustom(vector.create(0, 1), widget)
end

-- How strongly 'widget' claims spare space in a list
function Components.Greedy(greed: vector, widget: Widget): Widget
  return Widget_Luau(widget, {
    PrePosition = function(_, w: Widget)
      w.greed = greed
    end,
  })
end

function Components.GreedyX(widget: Widget): Widget
  return Components.Greedy(vector.create(1, 0), widget)
end
function Components.GreedyY(widget: Widget): Widget
  return Components.Greedy(vector.create(0, 1), widget)
end

function Components.Margin(inner: vector | number, outer: vector | number, widget: Widget): Widget
  local i, o = v2(inner), v2(outer)
  return Widget_Luau(widget, {
    PrePosition = function(_, w: Widget)
      w.minSize += i + o
    end,
    PostPosition = function(_, w: Widget)
      w.maxSize -= i + o
      w.size -= i + o
      w.pos += i
    end,
  })
end

function Components.MaxSize(size: vector | number, widget: Widget): Widget
  local s = v2(size)
  return Widget_Luau(widget, {
    PostPosition = function(_, w: Widget)
      w.maxSize = vector.min(w.maxSize, s)
      w.size = vector.min(w.size, s)
    end,
  })
end

function Components.MinSize(size: vector | number, widget: Widget): Widget
  local s = v2(size)
  return Widget_Luau(widget, {
    PrePosition = function(_, w: Widget)
      w.minSize = vector.max(s, w.minSize)
    end,
  })
end

-- Space between a layout's edge and its children (the layout reads it)
function Components.Padding(inner: vector | number, outer: vector | number, widget: Widget): Widget
  local i, o = v2(inner), v2(outer)
  local padding = New.Vec4f()
  padding.x, padding.y, padding.z, padding.w = i.x, i.y, o.x, o.y
  return Widget_Luau(widget, {
    GetPadding = function()
      return padding
    end,
  })
end

-- Offset 'widget' by 'pos'; { setPos = vector } messages move it
function Components.Positioned(pos: vector | number, widget: Widget): Widget
  local offset = v2(pos)
  return Widget_Luau(widget, {
    PrePosition = function(_, w: Widget)
      w.pos += offset
    end,
    Receive = function(_, _w: Widget, message: any)
      if type(message) == "table" and message.setPos then
        offset = message.setPos
      elseif lt.typeof(message) == "MessageSetPos" then
        offset = message.pos
      end
    end,
  })
end

------------------------------------------------------------------- Focus

function Components.CaptureKey(widget: Widget): Widget
  return Widget_Luau(widget, {
    CaptureFocus = function(_, w: Widget)
      w.focusKey = underCursor(w)
    end,
  })
end

function Components.CaptureMouse(widget: Widget): Widget
  return Widget_Luau(widget, {
    CaptureFocus = function(_, w: Widget)
      w.focusMouse = underCursor(w)
    end,
  })
end

function Components.CaptureScroll(widget: Widget): Widget
  return Widget_Luau(widget, {
    CaptureFocus = function(_, w: Widget)
      w.focusScroll = underCursor(w)
    end,
  })
end

-- Rebuild the widget whenever mouse focus changes (to restyle it)
function Components.FocusRebuild(widget: Widget): Widget
  local focus = false
  return Widget_Luau(widget, {
    PostUpdate = function(_, w: Widget)
      if w.focusMouse ~= focus then
        focus = w.focusMouse
        w:Rebuild()
      end
    end,
  })
end

-- Fade from 'baseAlpha' to opaque while the mouse is over the widget
function Components.FocusFade(baseAlpha: number, widget: Widget): Widget
  local alpha = 0
  return Components.CaptureMouse(Widget_Luau(widget, {
    PreDraw = function(_, w: Widget)
      w.alpha = alpha
    end,
    PostUpdate = function(_, w: Widget)
      local target = if w:HasFocusMouseRecursive() then 1 else baseAlpha
      alpha = mix(alpha, target, approach(0.1))
    end,
  }))
end

-- Corner brackets that fade in while the mouse is over the widget
function Components.FocusGlow(widget: Widget): Widget
  local t = 0
  return Components.CaptureMouse(Widget_Luau(widget, {
    PostDraw = function(_, w: Widget)
      if t <= 0.001 then
        return
      end
      local c = 2 * Colors.Primary
      local pos, size = w.pos, w.size
      local p1 = pos + vector.create(-2, -2)
      local p2 = pos + vector.create(2, -2) + vector.create(size.x, 0)
      local p3 = pos + vector.create(-2, 2) + vector.create(0, size.y)
      local p4 = pos + vector.create(2, 2) + size
      Glyph_Draw(Glyph_Line(p1, p2, 1, 1), 0, 1, c, t)
      Glyph_Draw(Glyph_Line(p3 + vector.create(0, -2), p1 + vector.create(0, 2), 1, 1), 0, 1, c, t)
      Glyph_Draw(Glyph_Line(p4, p3, 1, 1), 0, 1, c, t)
      Glyph_Draw(Glyph_Line(p2 + vector.create(0, 2), p4 + vector.create(0, -2), 1, 1), 0, 1, c, t)
    end,
    PostUpdate = function(_, w: Widget)
      if w.focusMouse then
        if t < 0.001 then
          Sound_Play("ui/hover.wav", 0.008)
        end
        t = mix(t, 1, approach(0.1))
      else
        t = mix(t, 0, approach(0.1))
      end
    end,
  }))
end

-- A panel behind the widget that lights up while the mouse is over it
function Components.FocusPanel(widget: Widget): Widget
  local focus = false
  return Components.CaptureMouse(Widget_Luau(widget, {
    PreDraw = function(_, w: Widget)
      local c = if focus then 2.5 * Colors.Primary else vector.create(0.15, 0.15, 0.15)
      WidgetRenderer_DrawPanel(w.pos, w.size, c, 0.5, 1, 0)
      WidgetRenderer_DrawPanel(w.pos, vector.create(4, w.size.y), c, 0.5, 1, 0)
    end,
    PostUpdate = function(_, w: Widget)
      if w.focusMouse ~= focus then
        focus = w.focusMouse
        w:Rebuild()
        if focus then
          Sound_Play("ui/hover.wav", 0.008)
        end
      end
    end,
  }))
end

------------------------------------------------------------- Backgrounds

function Components.Backdrop(color: vector, innerAlpha: number, alpha: number, bevel: number, widget: Widget): Widget
  return Widget_Luau(widget, {
    PreDraw = function(_, w: Widget)
      WidgetRenderer_DrawPanel(w.pos, w.size, color, innerAlpha, alpha, bevel)
    end,
  })
end

function Components.BackdropGrid(color: vector, alpha: number, widget: Widget): Widget
  return Widget_Luau(widget, {
    PreDraw = function(_, w: Widget)
      Glyph_Draw(Glyph_Grid(w:TopLeft(), w:BottomRight(), 1, 1, 0, 0.25), 0, 1, color, alpha)
    end,
  })
end

function Components.BackdropTexture(texture: Texture, alpha: number, widget: Widget): Widget
  return Widget_Luau(widget, {
    PreDraw = function(_, w: Widget)
      ClipRegion_Push(w.pos, w.size)
      local size = vector.create(texture:GetWidth(), texture:GetHeight())
      WidgetRenderer_DrawTexture(texture, w:TopLeft(), size, alpha)
      ClipRegion_Pop()
    end,
  })
end

-- For debugging layouts
function Components.RedBG(widget: Widget): Widget
  return Components.Backdrop(vector.create(1, 0, 0), 1, 1, 0, widget)
end

------------------------------------------------------------- Interaction

local function clickable(message: any, receiver: Widget, left: boolean, press: boolean, widget: Widget): Widget
  return Widget_Luau(widget, {
    PostUpdate = function(_, w: Widget)
      if not w.focusMouse then
        return
      end
      local fired
      if left then
        fired = if press then Mouse_LeftPressed() else Mouse_LeftReleased()
      else
        fired = if press then Mouse_RightPressed() else Mouse_RightReleased()
      end
      if fired then
        receiver:Send(message)
      end
    end,
  })
end

-- Send 'message' to 'receiver' when the widget is left-clicked
function Components.Clickable(message: any, receiver: Widget, widget: Widget): Widget
  return clickable(message, receiver, true, true, widget)
end

-- Send 'message' to 'receiver' when the right button is released over it
function Components.ClickableRightRelease(message: any, receiver: Widget, widget: Widget): Widget
  return clickable(message, receiver, false, false, widget)
end

-- Drag the widget with the left button; it snaps to a 32-pixel grid
function Components.Draggable(widget: Widget): Widget
  local snap = 32
  local offset = vector.create(0, 0)
  local dragging = false
  return Components.CaptureMouse(Widget_Luau(widget, {
    PrePosition = function(_, w: Widget)
      if dragging then
        offset += Cursor_GetDelta()
      end
      w.pos += offset
    end,
    PostUpdate = function(_, w: Widget)
      if w.focusMouse and Mouse_LeftPressed() then
        dragging = true
        Sound_Play("ui/dragbegin.wav", 0.05)
      end
      if dragging and Mouse_LeftReleased() then
        Sound_Play("ui/dragend.wav", 0.05)
        dragging = false
        offset = snap * vector.floor(offset / snap + vector.create(0.5, 0.5))
      end
    end,
  }))
end

function Components.Named(name: string, widget: Widget): Widget
  return Widget_Luau(widget, {
    GetName = function()
      return name
    end,
  })
end

-- Show the widget's name beside it after the mouse rests on it
function Components.Tooltip(widget: Widget): Widget
  local delay = 0.2
  local timer = 0
  local circle = Glyph_Circle(0, 1, 1, 1)
  return Widget_Luau(widget, {
    PostDraw = function(_, w: Widget)
      if not w.focusMouse then
        timer = 0
        return
      end
      timer += FrameTimer_Get()
      local alpha = 1 - Float_ExpDecay(math.max(0, timer - delay), 0.05)
      local pos, size = w.pos, w.size
      local p1 = pos + vector.create(size.x, 0)
      local dir = vector.create(1, -1)
      if pos.y < 64 then
        p1 = vector.create(p1.x, pos.y + size.y)
        dir = vector.create(1, 1)
      end
      p1 += 4 * dir
      local p2 = p1 + 28 * dir
      local p3 = p1 + 32 * dir

      ClipRegion_PushNoClip()
      WidgetRenderer_DrawText(Fonts.Medium(), w:GetName(), p3, 16, 1, alpha, false)
      Glyph_Draw(circle, p1, 32, Colors.Primary, 2 * alpha)
      Glyph_Draw(Glyph_LineFade(p1, p2, 1, 1), 0, 1, Colors.Primary, alpha)
      ClipRegion_Pop()
    end,
  })
end

-- While the right button is held over 'widget', show 'menu' at the cursor
function Components.ContextMenu(menu: Widget, widget: Widget): Widget
  local visible = false
  local popup: Widget? = nil
  return Components.CaptureMouse(Widget_Luau(widget, {
    PostUpdate = function(_, w: Widget)
      if not visible and w.focusMouse and Mouse_RightPressed() then
        visible = true
        local shown = Components.Positioned(Cursor_Get(), Widget_Stack(Widget_Create()))
        shown:AddChild(menu)
        popup = shown
        -- The HUD (still LTSL) expects its own message type
        local message = ltsl_new("Widget/Messages:MessageAddContextMenu")
        message.widget = shown
        w:SendUp(message)
      end
      if visible and not Mouse_RightDown() then
        visible = false
        if popup then
          popup:Delete()
          popup = nil
        end
      end
    end,
  }))
end

return Components
