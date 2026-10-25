--!strict
-- The Escape menu (Luau port of Widget/GameMenu.lts). Its buttons do
-- nothing yet, as in LTSL; Escape closes it.

local Button = require("@lt/Widget/Button")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Widgets = require("@lt/Widgets")

local GameMenu = {}

function GameMenu.Create(): Widget
  local labels = { "SAVE GAME", "SETTINGS", "HELP", "EXIT TO MAIN MENU", "EXIT GAME" }
  local buttons = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      local children = {}
      for _, label in labels do
        table.insert(children, Components.Expand(Button.Create(0, label, 18)))
      end
      return children
    end,
    PreDraw = function(_, w: Widget)
      WidgetRenderer_DrawPanel(w.pos, w.size, 0.1, 0.9, 1, 8)
    end,
  })

  local menu = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return {
        Components.AlignBottomCenter(Components.Margin(8, 8,
          Widgets.Text(Fonts.Heading(), "LIMIT THEORY v0.82.2", 24, vector.create(1, 1, 1)))),
        Components.AlignCenter(Components.Padding(8, 8, Widget_ListVertical(8, buttons))),
      }
    end,
    PreUpdate = function(_, w: Widget)
      if Key_Pressed(Key_Escape()) then
        w:Delete()
      end
    end,
  })
  return Widgets.FocusWindow(0.8, Components.Expand(Widget_Stack(menu)))
end

return GameMenu
