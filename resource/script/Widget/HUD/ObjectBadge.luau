--!strict
-- An object's icon, name and health ring; click to open its info window
-- (Luau port of Widget/HUD/ObjectBadge.lts).

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Messages = require("@lt/Widget/Messages")

local ObjectBadge = {}

local ObjectInfoWindow = ltsl("Widget/ObjectInfo:CreateWindow")

function ObjectBadge.Create(player: Player, object: Object, _fancy: boolean): Widget
  local info: Widget? = nil
  local badge = Widget_Create()
  Widget_Luau(badge, {
    GetHash = function()
      return object:GetHash()
    end,
    GetName = function()
      return object:GetName()
    end,
    PostDraw = function(_, w: Widget)
      local color = if object:GetOwner() == player then 2 * Colors.Friendly else 2 * Colors.Primary
      Icon_Draw(object:GetIcon(), w:Center(), 0.25 * w.size, color, 1)
      WidgetRenderer_DrawText(Fonts.Heading(), object:GetName(), w:BottomCenter(), 14, 1, 1, true)
      local health = object:GetHealthNormalized()
      local segments = 12
      for i = 0, segments - 1 do
        local opacity = math.clamp((health - i / segments) * segments, 0.1, 1)
        local arc = Glyph_Arc(0, 1, 0.05, 1, 1, 0.5 * i / (segments - 1), 0.25 / segments - 0.005)
        Glyph_Draw(arc, w:Center(), 0.4 * w.size, Colors.Primary, opacity)
      end
    end,
    Receive = function(_, w: Widget, message: any)
      if type(message) == "table" and message.type == "Click" then
        if info and info:HasParent() then
          info:Delete()
          info = nil
        else
          local window = ObjectInfoWindow(player, object)
          info = window
          w:SendUp(Messages.AddWidget(window))
        end
      end
    end,
  })
  return Components.CaptureMouse(Components.Clickable({ type = "Click" }, badge, badge))
end

return ObjectBadge
