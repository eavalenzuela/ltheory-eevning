--!strict
-- An item's name, icon, type and stats (Luau port of Widget/ItemInfo.lts).

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Widgets = require("@lt/Widgets")

local ItemInfo = {}

local function stats(item: Item): { Widget }
  local white = vector.create(1, 1, 1)
  local rows = {}
  local function stat(label: string, value: string, size: number)
    table.insert(rows, Widgets.Pair(8,
      Widgets.Text(Fonts.Subheading(), label, 14, Colors.Primary),
      Widgets.Text(Fonts.Default(), value, size, white)))
  end
  if item:HasValue() then stat("ESTIMATED VALUE", `{item:GetValue()} cr`, 18) end
  if item:HasIntegrity() then stat("INTEGRITY", tostring(item:GetIntegrity()), 18) end
  if item:HasMass() then stat("MASS", `{item:GetMass()} kg`, 16) end
  if item:HasPowerDrain() then stat("POWER DRAW", `{item:GetPowerDrain()} W`, 18) end
  if item:HasRange() then stat("RANGE", `{item:GetRange()} m`, 18) end
  if item:HasRate() then stat("RATE", `{item:GetRate()} Hz`, 18) end
  if item:HasSpeed() then stat("SPEED", `{item:GetSpeed()} m/s`, 18) end
  return rows
end

function ItemInfo.Create(_player: Player, item: Item): Widget
  local white = vector.create(1, 1, 1)
  local header = Components.Backdrop(vector.create(0.05, 0.05, 0.05), 0.5, 1, 0,
    Components.Expand(Components.Padding(vector.create(16, 8), vector.create(16, 8), Components.AlignRightCenter(
      Widgets.ListH(8,
        Components.AlignCenter(Widgets.Text(Fonts.Medium(), string.upper(item:GetName()), 20, white)),
        Components.AlignCenter(Components.MinSize(48, Widgets.Icon(item:GetIcon(), 2 * Colors.Primary))),
        Components.AlignCenter(Widgets.Text(Fonts.Subheading(), string.upper(item:GetTypeString()), 14, Colors.Primary)))))))

  local contents = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return stats(item)
    end,
  })

  local info = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return { header, Components.GreedyY(Components.Expand(Components.Padding(16, 16, Widget_ListVertical(8, contents)))) }
    end,
    PreDraw = function(_, w: Widget)
      WidgetRenderer_DrawPanel(w.pos, w.size, 0.05, 0.75, 1, 0)
    end,
  })
  return Components.Expand(Widget_ListVertical(4, info))
end

return ItemInfo
