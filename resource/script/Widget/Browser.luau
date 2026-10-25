--!strict
-- A window with back / forward history over the widgets it has shown, and
-- a breadcrumb of their names (Luau port of Widget/Browser.lts). Children
-- open a new page with a { type = "Link", widget = w } message; Escape
-- closes it.

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local IconButton = require("@lt/Widget/IconButton")
local Icons = require("@lt/Icons")
local Widgets = require("@lt/Widgets")

local Browser = {}

function Browser.Create(first: Widget): Widget
  local pages = { first }
  local index = 1
  local browser = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      local bar = Widget_ListHorizontal(2, Widget_Create())
      bar:AddChild(Components.AlignCenter(Widgets.ListH(8,
        Components.MinSize(32, IconButton.Create({ type = "BrowserBack" }, Icons.ArrowLeft())),
        Components.MinSize(32, IconButton.Create({ type = "BrowserForward" }, Icons.ArrowRight())))))
      bar:AddChild(Components.MinSize(vector.create(8, 0), Widget_Create()))
      for i, page in pages do
        if i > 1 then
          bar:AddChild(Components.AlignCenter(Widgets.Text(Fonts.Medium(), "/", 22, Colors.Primary)))
        end
        bar:AddChild(Components.AlignCenter(Widgets.Text(Fonts.Medium(), string.upper(page:GetName()), 14,
          if i <= index then Colors.White else Colors.DGray)))
      end
      bar:AddChild(Widgets.EmptySpaceH())
      bar:AddChild(Components.AlignCenter(Components.MinSize(28, IconButton.Create(0, Icons.Star()))))
      return {
        Components.Expand(Components.Padding(vector.create(12, 8), vector.create(12, 8), bar)),
        Components.GreedyY(pages[index]),
      }
    end,
    PreDraw = function(_, w: Widget)
      ClipRegion_Push(w.pos, w.size)
    end,
    PostDraw = function()
      ClipRegion_Pop()
    end,
    PreUpdate = function(_, w: Widget)
      ClipRegion_Push(w.pos, w.size)
    end,
    PostUpdate = function(_, w: Widget)
      ClipRegion_Pop()
      if w.focusKey and Key_Pressed(Key_Escape()) then
        w:Delete()
      end
    end,
    Receive = function(_, w: Widget, message: any)
      if type(message) ~= "table" then
        return
      end
      if message.type == "Link" then
        Sound_Play("ui/objectmenuopen.ogg", 0.1)
        while #pages > index do
          table.remove(pages)
        end
        table.insert(pages, message.widget)
        index = #pages
        w:Rebuild()
      elseif message.type == "BrowserBack" and index > 1 then
        index -= 1
        w:Rebuild()
      elseif message.type == "BrowserForward" and index < #pages then
        index += 1
        w:Rebuild()
      end
    end,
  })
  return Components.Backdrop(vector.create(0.075, 0.075, 0.075), 0.95, 1, 16,
    Components.CaptureKey(Components.Expand(Widget_ListVertical(0, browser))))
end

return Browser
