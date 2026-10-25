--!strict
-- A one-line text input (Luau port of Widget/TextField.lts). Click to
-- focus; typing edits it; Return or a click elsewhere ends editing.
-- 'contents' is shared with the owner, which reads contents.text.

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Widgets = require("@lt/Widgets")

local TextField = {}

export type Contents = { text: string }

function TextField.Create(size: number, contents: Contents): Widget
  local cursor = #contents.text
  local focus = false
  local t = 0
  local caret = Glyph_Box(0.5, vector.create(0.5, 0.3), 1, 1)
  local field = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return { Components.AlignLeftCenter(Widgets.Text(Fonts.Default(), contents.text, size, vector.create(1, 1, 1))) }
    end,
    PreDraw = function(_, w: Widget)
      WidgetRenderer_DrawPanel(w.pos, w.size, 0.15, 0.5, 1, 0)
      local c = if focus then 2.5 * Colors.Primary else vector.create(0.15, 0.15, 0.15)
      WidgetRenderer_DrawPanel(w.pos, vector.create(4, w.size.y), c, 0.5, 1, 0)
    end,
    PostDraw = function(_, w: Widget)
      if focus then
        local before = WidgetRenderer_GetTextSize(Fonts.Default(), string.sub(contents.text, 1, cursor), size)
        local blink = math.sin(t)
        local alpha = 0.5 + 0.5 * math.sign(blink) * math.abs(blink) ^ 0.2
        Glyph_Draw(caret, w.pos + vector.create(14 + before.x, 0), vector.create(0.5, w.size.y), 2 * Colors.Primary, alpha)
      end
    end,
    PostUpdate = function(_, w: Widget)
      if Mouse_LeftPressed() then
        focus = w.focusMouse
        t = 0
      end
      if focus then
        if Key_Down(Key_Return()) then
          focus = false
        end
        local text, before = contents.text, cursor
        local typed = Keyboard_GetText()
        if #typed > 0 then
          text = string.sub(text, 1, cursor) .. typed .. string.sub(text, cursor + 1)
          cursor += #typed
        end
        if Key_Pressed(Key_BackSpace()) and cursor > 0 then
          local cut = cursor - 1
          if Key_Control() then
            while cut > 0 and string.sub(text, cut, cut) ~= " " do
              cut -= 1
            end
          end
          text = string.sub(text, 1, cut) .. string.sub(text, cursor + 1)
          cursor = cut
        end
        contents.text = text
        if cursor ~= before then
          Sound_Play("ui/entertext.wav", 0.1)
          w:Rebuild()
        end
      end
      t += 12 * FrameTimer_Get()
    end,
  })
  return Components.FocusGlow(Components.CaptureMouse(Components.Padding(vector.create(12, 4), vector.create(8, 4),
    Components.MinSize(vector.create(128, 0), Widget_Stack(field)))))
end

return TextField
