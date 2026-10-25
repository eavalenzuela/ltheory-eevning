--!strict
-- A titled window with a close button (Luau port of Widget/Window.lts). The
-- close button, Escape (while the cursor is over it) or a Close message
-- closes it.

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Icons = require("@lt/Icons")
local Messages = require("@lt/Widget/Messages")
local Widgets = require("@lt/Widgets")

local Window = {}

local INNER_MARGIN = vector.create(0, 32)

function Window.Create(title: string, contents: Widget): Widget
  local opacity = 0
  local window = Widget_Luau(Widget_Create(), {
    Create = function()
      Sound_Play("ui/windowopen.wav", 0.1)
    end,
    Destroy = function()
      Sound_Play("ui/windowclose.wav", 0.2)
    end,
    GetName = function()
      return title
    end,
    CreateChildren = function(_, w: Widget): { Widget }
      local close = Components.Named("Close", Components.Margin(8, 8, Components.Tooltip(
        Components.FocusGlow(Components.AlignTopRight(Components.Clickable(Messages.Close(), w,
          Components.MinSize(14, Widgets.Icon(Icons.Cancel(), 1.5 * Colors.Primary))))))))
      return { Components.Margin(INNER_MARGIN, 0, contents), close }
    end,
    PreDraw = function(_, w: Widget)
      WidgetRenderer_DrawPanel(w.pos, w.size, 0.05, 0.95, opacity * w.alpha, 16)
      ClipRegion_Push(w.pos, w.size)
    end,
    PostDraw = function()
      ClipRegion_Pop()
    end,
    PreUpdate = function(_, w: Widget)
      opacity += (1 - opacity) * (1 - Float_ExpDecay(FrameTimer_Get(), 0.25))
      ClipRegion_Push(w.pos, w.size)
    end,
    PostUpdate = function(_, w: Widget)
      ClipRegion_Pop()
      if w.focusKey and Key_Pressed(Key_Escape()) then
        w:Delete()
      end
    end,
    Receive = function(_, w: Widget, message: any)
      if Messages.Is(message, "Close") then
        w:Delete()
      end
    end,
  })
  return Widget_Stack(Components.CaptureKey(window))
end

return Window
