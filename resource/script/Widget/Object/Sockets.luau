--!strict
-- Placeholder for an object's Sockets tab: an icon (Luau port of
-- Widget/Object/Sockets.lts; the tab was never implemented).

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Icons = require("@lt/Icons")
local Widgets = require("@lt/Widgets")

return {
  Create = function(_player: Player, _object: Object): Widget
    return Components.ExpandCustom(vector.create(0.25, 0.25),
      Components.AlignCenter(Widgets.Icon(Icons.Hardpoints(), 2 * Colors.Secondary)))
  end,
}
