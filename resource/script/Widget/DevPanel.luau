--!strict
-- The developer panel (Luau port of Widget/DevPanel.lts): a clock, a task
-- list, the apps and frame statistics, on a blurred screenshot at the left
-- of the screen. Apps show it with Ctrl+Tab (DevPanel.Toggle).

local Apps = require("@lt/Widget/DevPanel/Apps")
local Clock = require("@lt/Widget/DevPanel/Clock")
local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Icons = require("@lt/Icons")
local Performance = require("@lt/Widget/DevPanel/Performance")
local RandomScreenshot = require("@lt/Texture/RandomScreenshot")
local Status = require("@lt/Widget/DevPanel/Status")
local Tasks = require("@lt/Widget/DevPanel/Tasks")
local Widgets = require("@lt/Widgets")

local DevPanel = {}

local background: Texture? = nil

-- A section that takes the remaining height, at least 'minSize'
local function section(widget: Widget, minSize: vector?): Widget
  local body = if minSize then Components.MinSize(minSize, widget) else widget
  return Components.Expand(Components.GreedyY(Widgets.ListV(0,
    Widget_Create(),
    Components.Expand(Components.GreedyY(body)))))
end

local function panel(): Widget
  return Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      local title = Components.Expand(Components.Padding(vector.create(24, 16), vector.create(24, 16),
        Components.MinSize(vector.create(400, 0), Components.AlignCenter(Widgets.ListH(16,
          Components.AlignCenter(Widgets.ListH(2,
            Components.AlignCenter(Widgets.Text(Fonts.Medium(), "LT", 32, vector.create(1, 1, 1))),
            Components.AlignCenter(Widgets.Text(Fonts.Default(), "DEVELOPER", 32, Colors.Primary)))),
          Components.AlignCenter(Widgets.EmptySpaceH()),
          Components.AlignCenter(Clock.Create()))))))
      return {
        title,
        section(Tasks.Create(), vector.create(128, 420)),
        section(Apps.Create(), vector.create(128, 120)),
        section(Performance.Create()),
        Components.Expand(Status.Create()),
      }
    end,
    PostDraw = function(_, w: Widget)
      local c = Cursor_Get()
      if c.x > w.pos.x and c.y > w.pos.y and c.x <= w.pos.x + w.size.x and c.y <= w.pos.y + w.size.y then
        Icon_Draw(Icons.Cursors.Pointer(), c, 12, Colors.Primary, 1)
      end
    end,
  })
end

function DevPanel.Create(): Widget
  local bg = background or RandomScreenshot.Get()
  background = bg
  return Components.Backdrop(vector.create(0.01, 0.01, 0.01), 0.5, 1, 0, Widgets.ListH(0,
    Components.CaptureKey(Components.CaptureMouse(Components.CaptureScroll(
      Components.Backdrop(vector.create(0.1, 0.1, 0.1), 0.75, 1, 0,
        Components.BackdropTexture(bg, 0,
          Components.Expand(Widget_ListVertical(2, panel()))))))),
    Widgets.EmptySpaceH()))
end

-- The panel composited over the app, as the LTSL apps showed it
function DevPanel.Layer(): Widget
  return Widget_Layer(Compositor_Basic(0.1, 0.1, vector.create(0.4, 0.5, 0.75)), Mesh_Quad(), 1, DevPanel.Create())
end

-- Show the panel in 'ui' if 'shown' is nil, otherwise remove it; returns
-- the panel now shown, if any
function DevPanel.Toggle(ui: Interface, shown: Widget?): Widget?
  if shown then
    shown:Delete()
    return nil
  end
  local layer = DevPanel.Layer()
  ui:Add(layer)
  return layer
end

return DevPanel
