--!strict
-- Badges for the ship's current targets (Luau port of
-- Widget/HUD/Targets.lts).

local Components = require("@lt/Widget/Components")
local ObjectBadge = require("@lt/Widget/HUD/ObjectBadge")

local Targets = {}

function Targets.Create(player: Player, object: Object): Widget
  local targets = Widget_Luau(Widget_Create(), {
    GetName = function()
      return "Targets"
    end,
    CreateChildren = function(): { Widget }
      local badges = {}
      local it = object:GetTargets()
      while it:HasMore() do
        table.insert(badges, Components.MinSize(128, ObjectBadge.Create(player, it:Get(), false)))
        it:Advance()
      end
      return badges
    end,
  })
  return Widget_Dynamic(Widget_ListHorizontal(4, targets))
end

return Targets
