--!strict
-- Round icon buttons (Luau port of Widget/IconButton.lts). Pressing one
-- sends 'onPress' up the widget tree.

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")

local IconButton = {}

local ring = Glyph_Arc(0, 1, 0.01, 1, 1, 0, 1)

local function behavior(onPress: any, draw: (w: Widget, focus: boolean) -> ())
  local focus = false
  return {
    PreDraw = function(_, w: Widget)
      draw(w, focus)
    end,
    PostUpdate = function(_, w: Widget)
      if w.focusMouse and not focus then
        focus = true
        Sound_Play("ui/hover.wav", 0.008)
      elseif not w.focusMouse and focus then
        focus = false
        w:Rebuild()
      end
      if w.focusMouse and Mouse_LeftPressed() then
        w:SendUp(onPress)
      end
    end,
  }
end

local function color(focus: boolean): vector
  return if focus then 3 * Colors.Secondary else 1.5 * Colors.Primary
end

function IconButton.Create(onPress: any, icon: Icon): Widget
  return Components.CaptureMouse(Widget_Luau(Widget_Create(), behavior(onPress, function(w, focus)
    local r = 0.5 * math.min(w.size.x, w.size.y)
    local c = color(focus)
    Icon_Draw(icon, w:Center(), 0.6 * r, c, w.alpha)
    Glyph_Draw(ring, w:Center(), r, c, 0.05)
  end)))
end

-- An icon button with a text label beside it
function IconButton.CreateText(onPress: any, icon: Icon, text: string): Widget
  local button = behavior(onPress, function(w, focus)
    local r = w.size.y
    local c = color(focus)
    local center = w:LeftCenter() + vector.create(0.5 * r, 0)
    WidgetRenderer_DrawPanel(w.pos, w.size, 0.1, 0.75, 1, 0)
    Icon_Draw(icon, center, 0.25 * r, c, 1)
    Glyph_Draw(ring, center, 0.4 * r, c, 0.05)
    WidgetRenderer_DrawText(Fonts.Medium(), text, w:LeftCenter() + vector.create(r + 16, 0), 16, 1, 1, false)
    if focus then
      Glyph_Draw(ring, center, 0.5 * r, c, 1)
    end
  end) :: any
  button.GetName = function(): string
    return text
  end
  return Components.CaptureMouse(Widget_ListHorizontal(8, Widget_Luau(Widget_Create(), button)))
end

return IconButton
