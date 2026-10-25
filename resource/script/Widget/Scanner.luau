--!strict
-- The scanner window: the object's frequency spectrum, with a sound that
-- follows it (Luau port of Widget/Scanner.lts).

local Colors = require("@lt/Colors")
local Fonts = require("@lt/Fonts")

local Scanner = {}

local RESOLUTION = 256

function Scanner.Create(_player: Player, object: Object): Widget
  local output = Object_GetScannerOutput(object, RESOLUTION)
  local loop: Sound? = nil
  local box = Glyph_Box(0, 1, 1, 1)
  return Widget_Luau(Widget_Create(), {
    Create = function()
      Sound_Play("ui/scanneropen.wav", 0.9)
      loop = Sound_PlayLooped("scanner/loop.wav", 0.3)
    end,
    Destroy = function()
      Sound_Play("ui/scannerclose.wav", 0.4)
      local sound = loop
      if sound then
        sound:Delete()
      end
    end,
    PreDraw = function(_, w: Widget)
      local count = output:Size()
      local dy = 0.25 * w.size.y
      local y = w.pos.y + w.size.y
      local color = 2 * Colors.Primary
      local barWidth = 0.45 * w.size.x / math.max(1, count - 1)
      local last = vector.create(0, 0)
      for i = 0, count - 1 do
        local x = w.pos.x + w.size.x * (i / math.max(1, count - 1))
        local v = 1 - Float_ExpDecay(output:Get(i), 2.5)
        local p1 = vector.create(x, y)
        local p2 = p1 - v * vector.create(0, dy)
        Glyph_Draw(box, 0.5 * (p1 + p2), vector.create(barWidth, 0.5 * math.abs(p2.y - p1.y)), color, 0.05)
        if i > 0 then
          Glyph_Draw(Glyph_Line(last, p2, 1, 1), 0, 1, color, 0.5)
        end
        last = p2
      end

      local font = Fonts.Subheading()
      local white = vector.create(1, 1, 1)
      for i = 0, 7 do
        local x = w.pos.x + w.size.x * (i / 7)
        Glyph_Draw(Glyph_LineFade(vector.create(x, y), vector.create(x, y + 16), 1, 1), 0, 1, color, 1)
        WidgetRenderer_DrawText(font, "10", vector.create(x, y + 32), 20, white, 1, true)
        WidgetRenderer_DrawText(font, tostring(i), vector.create(x + 16, y + 24), 15, white, 1, true)
      end
      WidgetRenderer_DrawText(font, "frequency", vector.create(w.pos.x + w.size.x / 2, y + 24), 20, white, 1, true)
      Glyph_Draw(Glyph_Line(w:BottomLeft(), w:BottomRight(), 1, 1), 0, 1, color, 0.3)
    end,
    PreUpdate = function()
      output:Blend(Object_GetScannerOutput(object, RESOLUTION), 1 - Float_ExpDecay(FrameTimer_Get(), 0.1))
      local sound = loop
      if sound then
        sound:SetVolume(0.1 + 0.5 * (1 - Float_ExpDecay(output:AverageAmplitude(), 1)))
        sound:SetPitch(0.5 + output:AverageFrequency())
      end
    end,
  })
end

return Scanner
