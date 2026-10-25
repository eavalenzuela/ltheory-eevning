--!strict
-- A colony's info widget: its cultural traits as bars (Luau port of
-- Object/Widget/Colony.lts).

local Colors = require("@lt/Colors")
local Fonts = require("@lt/Fonts")
local Widgets = require("@lt/Widgets")

local TRAITS = { "Aggressive", "Creative", "Explorative", "Greedy", "Intellectual", "Lawless", "Sociable" }

return {
  Create = function(_player: Player, colony: Object): Widget
    local dot = Glyph_Circle(0, 1, 1, 1)
    local bars = Widget_Luau(Widget_Create(), {
      PostDraw = function(_, w: Widget)
        local traits = colony:GetTraits() :: any
        local x1 = w.pos.x + 76
        local x2 = w.pos.x + w.size.x - 4
        local c = 2 * Colors.Primary
        for i, name in TRAITS do
          local y = w.pos.y + 16 * (i - 1)
          local value = traits[name]
          WidgetRenderer_DrawText(Fonts.Default(), name, vector.create(w.pos.x, y), 12, 1, 1, false)
          Glyph_Draw(dot, vector.create(x1, y), 12, c, 1)
          Glyph_Draw(Glyph_LineFade(vector.create(x1, y), vector.create(x1 + (x2 - x1) * value, y), 1, 1), 0, 1, c, 1)
        end
      end,
      PrePosition = function(_, w: Widget)
        w.minSize = vector.create(256, 108)
      end,
    })
    return Widgets.ListV(16, Widgets.Text(Fonts.Default(), "Cultural Traits", 24, vector.create(1, 1, 1)), bars)
  end,
}
