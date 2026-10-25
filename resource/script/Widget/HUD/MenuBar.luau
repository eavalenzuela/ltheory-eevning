--!strict
-- The row of round buttons at the top of the HUD (Luau port of
-- Widget/HUD/MenuBar.lts). The first opens the player's info window.

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Icons = require("@lt/Icons")
local Messages = require("@lt/Widget/Messages")

local MenuBar = {}

local Browser = require("@lt/Widget/Browser")
local ObjectInfo = require("@lt/Widget/ObjectInfo")

local ring = Glyph_Arc(0, 1, 0.01, 1, 1, 0, 1)

local function circleIcon(icon: Icon, color: vector): Widget
  return Widget_Luau(Widget_Create(), {
    PreDraw = function(_, w: Widget)
      Glyph_Draw(ring, w:Center(), 0.5 * w.size, color, 0.1)
      if w.focusMouse then
        Glyph_Draw(ring, w:Center(), 0.6 * w.size, 2 * Colors.Primary, 1)
      end
      Icon_Draw(icon, w:Center(), 0.3 * w.size, color, 1)
    end,
  })
end

function MenuBar.Create(player: Player): Widget
  local info: Widget? = nil
  local bar = Widget_Create()
  local color = 1.5 * Colors.Primary
  local size = 42
  local function button(icon: Icon, name: string): Widget
    return Components.CaptureMouse(Components.Tooltip(Components.Named(name,
      Components.MinSize(size, circleIcon(icon, color)))))
  end
  Widget_Luau(bar, {
    CreateChildren = function(): { Widget }
      return {
        Components.CaptureMouse(Components.Tooltip(Components.Named("Player",
          Components.Clickable({ type = "Info" }, bar, Components.MinSize(size, circleIcon(Icons.Person(), color)))))),
        button(Icons.Assets(), "Assets"),
        button(Icons.Credits(), "Account"),
        button(Icon_Refresh(), "Projects"),
      }
    end,
    Receive = function(_, w: Widget, message: any)
      if type(message) == "table" and message.type == "Info" then
        if info and info:HasParent() then
          info:Delete()
          info = nil
        else
          local window = Browser.Create(ObjectInfo.Create(player, player))
          info = window
          w:SendUp(Messages.AddWidget(window))
        end
      end
    end,
  })
  return Widget_ListHorizontal(8, bar)
end

return MenuBar
