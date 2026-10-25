--!strict
-- Where the player is: system, zone and sovereignty (Luau port of
-- Widget/HUD/Container.lts).

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Icons = require("@lt/Icons")
local Widgets = require("@lt/Widgets")

local Container = {}

function Container.Create(player: Player): Widget
  local white = vector.create(1, 1, 1)
  local function row(value: string, kind: string): Widget
    return Widgets.ListH(4,
      Components.AlignCenter(Widgets.WidgetGlyph(Glyph_Circle(0, 1, 1, 1), vector.create(16, 16), 2 * Colors.Primary)),
      Widgets.Text(Fonts.Default(), value, 16, white),
      Components.AlignCenter(Widgets.Text(Fonts.Heading(), kind, 12, Colors.Primary)))
  end
  local location = Widget_Luau(Widget_Create(), {
    GetName = function()
      return "Location"
    end,
    CreateChildren = function(): { Widget }
      local ship = player:GetPiloting()
      local zone = ship:GetZone()
      return {
        Widgets.ListH(8,
          Components.AlignCenter(Widgets.Text(Fonts.Medium(), string.upper(ship:GetContainer():GetName()), 28, white)),
          Components.AlignCenter(Components.MinSize(32, Widgets.Icon(Icons.Assets(), 2 * Colors.Primary))),
          Components.AlignCenter(Widgets.Text(Fonts.Heading(), "SYSTEM", 12, Colors.Primary))),
        row(if zone then zone:GetName() else "Open Space", "ZONE"),
        row("Unclaimed", "SOVEREIGNTY"),
      }
    end,
    PostUpdate = function(_, w: Widget)
      w:Rebuild()
    end,
  })
  return Widget_ListVertical(2, location)
end

return Container
