--!strict
-- The developer panel's clock and date (Luau port of
-- Widget/DevPanel/Clock.lts).

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Widgets = require("@lt/Widgets")

local white = vector.create(1, 1, 1)
local SIZE = 24

local function twoDigits(n: number): string
  return string.format("%02d", n)
end

local function part(font: Font, text: string, size: number, color: vector): Widget
  return Components.AlignCenter(Widgets.Text(font, text, size, color))
end

return {
  Create = function(): Widget
    return Widget_ListHorizontal(16, Widget_Luau(Widget_Create(), {
      CreateChildren = function(): { Widget }
        local time = Time_Current()
        local ampm = if time.hour < 12 then "AM" else "PM"
        local clock = Widgets.ListH(2,
          part(Fonts.Medium(), tostring(time.hour), SIZE, white),
          part(Fonts.Default(), ":", SIZE - 8, Colors.Primary),
          part(Fonts.Medium(), twoDigits(time.minute), SIZE, white),
          part(Fonts.Default(), ":", SIZE - 8, Colors.Primary),
          part(Fonts.Medium(), twoDigits(time.second), SIZE, white),
          part(Fonts.Default(), ampm, SIZE, Colors.Primary))
        local date = Widgets.ListH(2,
          part(Fonts.Medium(), tostring(time.month), 14, white),
          part(Fonts.Default(), "/", 14, Colors.Primary),
          part(Fonts.Medium(), tostring(time.day), 14, white),
          part(Fonts.Default(), "/", 14, Colors.Primary),
          part(Fonts.Medium(), tostring(time.year), 14, white))
        return { Components.AlignCenter(Widgets.ListV(4, Components.AlignCenter(clock), Components.AlignCenter(date))) }
      end,
      PreUpdate = function(_, w: Widget)
        w:Rebuild()
      end,
    }))
  end,
}
