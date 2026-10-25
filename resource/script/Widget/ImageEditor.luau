--!strict
-- An image editor shell (Luau port of Widget/ImageEditor.lts): applies a
-- fixed filter chain to the image, saves the result to newImage.png and
-- shows it.

local Components = require("@lt/Widget/Components")
local Colors = require("@lt/Colors")
local Filters = require("@lt/Texture/Filters")
local Fonts = require("@lt/Fonts")
local Icons = require("@lt/Icons")
local Widgets = require("@lt/Widgets")

local ImageEditor = {}

-- The filter chain the LTSL editor ran: erode, brighten, grade
local function process(image: Texture): Texture
  local result = Filters.Gain(1.75, Filters.CircleMin(12, image))
  return Filters.ColorGrade(
    vector.create(0.00, 0.00, 0.10),
    vector.create(0.25, 0.25, 0.25),
    vector.create(0.50, 0.75, 0.50),
    vector.create(1.25, 1.00, 0.75),
    vector.create(1.50, 1.00, 1.00),
    result)
end

-- The image fitted inside the widget, with a 1-pixel border
local function preview(getImage: () -> Texture): Widget
  return Widget_Luau(Widget_Create(), {
    PreDraw = function(_, w: Widget)
      local image = getImage()
      local size = vector.create(image:GetWidth(), image:GetHeight())
      local expand = w.size / size
      size = size * math.min(expand.x, expand.y)
      size = vector.create(math.round(size.x), math.round(size.y))
      local p = w.pos + 0.5 * (w.size - size)
      p = vector.create(math.round(p.x), math.round(p.y)) + vector.create(8, 8)
      size -= vector.create(16, 16)
      WidgetRenderer_DrawPanel(p - vector.create(1, 1), size + vector.create(2, 2), 0, 1, 1, 0)
      WidgetRenderer_DrawTexture(image, p, size, 1)
    end,
  })
end

function ImageEditor.Create(source: Texture, name: string): Widget
  local image = process(source)
  image:SaveTo("newImage.png")
  local white = vector.create(1, 1, 1)

  local function sidePanel(width: number): Widget
    return Components.Expand(Components.Backdrop(vector.create(0.2, 0.2, 0.2), 0.4, 1, 0,
      Components.MinSize(vector.create(width, 0), Widget_Create())))
  end

  local editor = Widget_ListVertical(0, Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return {
        Components.Expand(Components.Backdrop(vector.create(0.05, 0.05, 0.05), 0.75, 1, 16,
          Components.Padding(vector.create(24, 12), vector.create(24, 12), Widgets.ListH(16,
            Components.AlignCenter(Components.MinSize(32, Widgets.Icon(Icons.Person(), 2 * Colors.Primary))),
            Components.AlignCenter(Widgets.Text(Fonts.Medium(), "IMAGE EDITOR", 24, white)),
            Widgets.EmptySpaceH(),
            Components.AlignCenter(Widgets.Text(Fonts.Light(), "v0.0.1", 16, vector.create(0.3, 0.3, 0.3))))))),
        Widgets.SpacerH(4),
        Components.GreedyY(Components.Expand(Widgets.ListH(0,
          sidePanel(200),
          Components.GreedyX(Components.Expand(Components.Backdrop(vector.create(0.1, 0.1, 0.1), 0.5, 1, 0,
            preview(function() return image end)))),
          sidePanel(320)))),
        Components.Expand(Components.Padding(vector.create(8, 4), vector.create(8, 4), Widgets.ListH(0,
          Widgets.Text(Fonts.Medium(), name, 12, vector.create(0.3, 0.3, 0.3)),
          Widget_Create()))),
      }
    end,
    PreDraw = function(_, w: Widget)
      WidgetRenderer_DrawPanel(w.pos, w.size, 0.08, 0.95, 1, 16)
    end,
  }))
  return editor
end

return ImageEditor
