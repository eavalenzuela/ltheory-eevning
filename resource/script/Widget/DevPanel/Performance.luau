--!strict
-- The developer panel's frame statistics (Luau port of
-- Widget/DevPanel/Performance.lts).

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Header = require("@lt/Widget/DevPanel/Header")
local Icons = require("@lt/Icons")
local ScrollFrame = require("@lt/Widget/ScrollFrame")
local Widgets = require("@lt/Widgets")

local function stat(caption: string, value: string): Widget
  return Widgets.Pair(8,
    Widgets.Text(Fonts.Subheading(), caption, 14, Colors.Primary),
    Widgets.Text(Fonts.Medium(), value, 14, vector.create(1, 1, 1)))
end

return {
  Create = function(): Widget
    local stats = Widget_ListVertical(4, Widget_Luau(Widget_Create(), {
      CreateChildren = function(): { Widget }
        local frame = FrameTimer_GetEMA01()
        return {
          stat("Frame Time", `{math.round(frame * 1000)} ms`),
          stat("Frame Rate", `{math.round(1 / frame)} fps`),
          stat("Polys Drawn", tostring(Renderer_GetPolyCount())),
          stat("Draw Calls", tostring(Renderer_GetDrawCallCount())),
        }
      end,
      PostUpdate = function(_, w: Widget)
        w:Rebuild()
      end,
    }))
    return Widgets.ListV(2,
      Header.Create(Icons.Scanner(), "PERFORMANCE"),
      ScrollFrame.V(Components.Margin(8, 8, Components.Expand(stats))))
  end,
}
