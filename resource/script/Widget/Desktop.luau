--!strict
-- A full-screen root for tool and demo apps: a backdrop (a random
-- screenshot), the pointer, and windows / context menus opened by the
-- widgets inside it (AddWidget, AddContextMenu).

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Icons = require("@lt/Icons")
local Messages = require("@lt/Widget/Messages")
local RandomScreenshot = require("@lt/Texture/RandomScreenshot")

local Desktop = {}

export type Options = {
  backdrop: vector?,          -- panel color behind the texture
  textureAlpha: number?,      -- how strongly the screenshot shows
  cursorSize: number?,
  windowMargin: vector?,      -- around windows opened with AddWidget
}

function Desktop.Create(content: Widget, options: Options?): Widget
  local opts: Options = options or {}
  local texture = RandomScreenshot.Get()
  local root = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return { content }
    end,
    PreDraw = function(_, w: Widget)
      WidgetRenderer_DrawPanel(w.pos, w.size, opts.backdrop or vector.create(0.1, 0.2, 0.3), 1, 1, 0)
      WidgetRenderer_DrawTexture(texture, w.pos, w.size, opts.textureAlpha or 1)
    end,
    PostDraw = function(_, w: Widget)
      Icon_Draw(Icons.Cursors.Pointer(), Cursor_Get(), opts.cursorSize or 12, 4 * Colors.Primary, 0.3)
    end,
    Receive = function(_, w: Widget, message: any)
      if Messages.Is(message, "AddContextMenu") then
        w:AddChild(message.widget)
      elseif Messages.Is(message, "AddWidget") then
        local margin = opts.windowMargin or vector.create(256, 128)
        w:AddChild(Components.Expand(Components.AlignCenter(Components.Margin(margin, margin, message.widget))))
      end
    end,
  })
  return Widget_Stack(root)
end

-- 'widget' composited over the 3D view like the HUD
function Desktop.Layer(widget: Widget, blue: vector?): Widget
  return Widget_Layer(Compositor_Basic(0.05, 0.10, blue or vector.create(0.40, 0.50, 0.75)), Mesh_Quad(), 1, widget)
end

return Desktop
