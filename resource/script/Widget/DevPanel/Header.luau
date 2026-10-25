--!strict
-- The icon-and-title bar at the top of each developer panel section.

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Widgets = require("@lt/Widgets")

return {
  Create = function(icon: Icon, title: string): Widget
    return Components.Backdrop(vector.create(0.1, 0.1, 0.1), 0.25, 1, 0,
      Components.Padding(vector.create(24, 16), vector.create(24, 16), Components.Expand(Widgets.ListH(16,
        Components.AlignCenter(Components.MinSize(32, Widgets.Icon(icon, 1.5 * Colors.Primary))),
        Components.AlignCenter(Widgets.Text(Fonts.Default(), title, 20, vector.create(1, 1, 1)))))))
  end,
}
