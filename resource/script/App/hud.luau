--!strict
-- The HUD over a screenshot, for a generated system's AI player with ten
-- weapons in the hold (Luau port of App/hud.lts).

local AppShell = require("@lt/AppShell")
local HUD = require("@lt/Widget/HUD")
local RandomScreenshot = require("@lt/Texture/RandomScreenshot")

return AppShell.Create(function(): Widget
  local system = Object_Universe(42, 0)
  while not system:IsSystem() do
    system = system:GetInteriorObjects():Get()
  end
  local player: Player? = nil
  local objects = system:GetInteriorObjects()
  while objects:HasMore() do
    local owner = objects:Get():GetOwner()
    if owner then
      player = owner
    end
    objects:Advance()
  end
  local viewer = assert(player, "the system has no owned objects")
  local ship = viewer:GetPiloting()
  for i = 0, 9 do
    ship:AddItem(Item_WeaponType(i + 100), 1)
  end

  local texture = RandomScreenshot.Get()
  local root = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return { HUD.Create(viewer) }
    end,
    PreDraw = function(_, w: Widget)
      WidgetRenderer_DrawTexture(texture, w.pos, w.size, 1)
    end,
  })
  return Widget_Layer(Compositor_None(), Mesh_Quad(), 1, Widget_Stack(root))
end)
