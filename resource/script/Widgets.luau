--!strict
-- Basic widgets: text, lists, stacks, spacers, icons (Luau port of the core
-- of Widgets.lts with Widget/Text, Spacer, Icon, Grid and FocusWindow).
-- Lists and stacks take any number of children:
--
--   Widgets.ListH(8, left, middle, right)

local Components = require("@lt/Widget/Components")

local Widgets = {}

-- Text hashes let rebuilt widget trees keep the identity of unchanged text
local function hash(text: string): number
  local h = 2166136261
  for i = 1, #text do
    h = bit32.bxor(h, string.byte(text, i))
    h = (h * 16777619) % 4294967296
  end
  return h
end

local function textWidget(font: Font, text: string, size: number, color: vector, glow: boolean): Widget
  local textHash = hash(text)
  return Widget_Luau(Widget_Create(), {
    GetHash = function()
      return textHash
    end,
    PreDraw = function(_, w: Widget)
      local offset = vector.create(0, 0.5 * (w.size.y + 0.2 * size))
      if glow then
        WidgetRenderer_DrawTextGlow(font, text, w.pos + offset, size, color, w.alpha, false)
      else
        WidgetRenderer_DrawText(font, text, w.pos + offset, size, color, w.alpha, false)
      end
    end,
    PrePosition = function(_, w: Widget)
      w.minSize = WidgetRenderer_GetTextSize(font, text, size) + vector.create(2, 0)
    end,
  })
end

function Widgets.Text(font: Font, text: string, size: number, color: vector): Widget
  return textWidget(font, text, size, color, false)
end

function Widgets.TextGlow(font: Font, text: string, size: number, color: vector): Widget
  return textWidget(font, text, size, color, true)
end

---------------------------------------------------------------- Layouts

local function withChildren(layout: Widget, children: { Widget }): Widget
  for _, child in children do
    layout:AddChild(child)
  end
  return layout
end

-- Children left to right, 'spacing' apart
function Widgets.ListH(spacing: number, ...: Widget): Widget
  return withChildren(Widget_ListHorizontal(spacing, Widget_Create()), { ... })
end

-- Children top to bottom, 'spacing' apart
function Widgets.ListV(spacing: number, ...: Widget): Widget
  return withChildren(Widget_ListVertical(spacing, Widget_Create()), { ... })
end

-- Children on top of each other
function Widgets.Stack(...: Widget): Widget
  return withChildren(Widget_Stack(Widget_Create()), { ... })
end

-- 'left' and 'right' pushed to opposite ends of a row
function Widgets.Pair(spacing: number, left: Widget, right: Widget): Widget
  return Components.Expand(Widgets.ListH(spacing,
    Components.AlignLeftCenter(left),
    Components.Expand(Components.GreedyX(Widget_Create())),
    Components.AlignRightCenter(right)))
end

function Widgets.EmptySpaceH(): Widget
  return Components.GreedyX(Components.Expand(Widget_Create()))
end

function Widgets.EmptySpaceV(): Widget
  return Components.GreedyY(Components.Expand(Widget_Create()))
end

-- Children in rows of 'cellSize' squares, at least 'minCols' wide
function Widgets.Grid(cellSize: number, spacing: number, minCols: number, widget: Widget): Widget
  local width = 0
  local cell = cellSize + spacing
  return Widget_Luau(widget, {
    PrePosition = function(_, w: Widget)
      local minWidth = minCols * cell
      width = math.max(width, minWidth)
      local columns = math.max(1, math.floor(width / cell))
      local rows = math.max(1, math.ceil(w:GetChildren():Size() / columns))
      w.minSize = vector.create(minWidth, rows * cell)
    end,
    PostPosition = function(_, w: Widget)
      width = w.size.x
      local x, y = 0.5 * spacing, 0.5 * spacing
      local children = w:GetChildren()
      while children:HasMore() do
        local child = children:Get()
        child.pos += w.pos + vector.create(x, y)
        child.size = vector.create(cellSize, cellSize)
        x += cell
        if x + cellSize > width then
          x = 0.5 * spacing
          y += cell
        end
        children:Advance()
      end
    end,
  })
end

------------------------------------------------------------------ Spacers

-- A thin horizontal rule 'size' tall
function Widgets.SpacerH(size: number): Widget
  return Components.Expand(Components.AlignCenter(Widget_Luau(Widget_Create(), {
    PreDraw = function(_, w: Widget)
      WidgetRenderer_DrawPanel(w:LeftCenter(), vector.create(w.size.x, 2), 0.2, 1, 0.5, 4)
    end,
    PrePosition = function(_, w: Widget)
      w.minSize = vector.create(w.minSize.x, size)
    end,
  })))
end

-- A thin vertical rule 'size' wide
function Widgets.SpacerV(size: number): Widget
  return Components.Expand(Components.AlignCenter(Widget_Luau(Widget_Create(), {
    PreDraw = function(_, w: Widget)
      WidgetRenderer_DrawPanel(w:TopCenter(), vector.create(2, w.size.y), 0.2, 1, 0.5, 4)
    end,
    PrePosition = function(_, w: Widget)
      w.minSize = vector.create(size, w.minSize.y)
    end,
  })))
end

------------------------------------------------------------------- Icons

function Widgets.Icon(icon: Icon, color: vector): Widget
  return Widget_Luau(Widget_Create(), {
    PreDraw = function(_, w: Widget)
      Icon_Draw(icon, w:Center(), 0.5 * math.min(w.size.x, w.size.y), color, w.alpha)
    end,
  })
end

-- An icon inside a faint ring
function Widgets.IconRing(icon: Icon, color: vector): Widget
  local ring = Glyph_Arc(0, 1, 0.001, 1, 1, 0, 1)
  return Widget_Luau(Widget_Create(), {
    PreDraw = function(_, w: Widget)
      local r = 0.5 * math.min(w.size.x, w.size.y)
      Glyph_Draw(ring, w:Center(), r, color, 0.1 * w.alpha)
      Icon_Draw(icon, w:Center(), 0.7 * r, color, w.alpha)
    end,
  })
end

function Widgets.WidgetGlyph(glyph: Glyph, size: vector, color: vector): Widget
  return Widget_Luau(Widget_Create(), {
    PreDraw = function(_, w: Widget)
      Glyph_Draw(glyph, w:Center(), w.size, color, w.alpha)
    end,
    PrePosition = function(_, w: Widget)
      w.minSize = size
    end,
  })
end

----------------------------------------------------------------- Windows

-- A full-screen dimmed layer holding 'widget' that takes all input; it
-- closes itself when its content is gone
function Widgets.FocusWindow(opacity: number, widget: Widget): Widget
  local window = Widget_Stack(Widget_Luau(Widget_Create(), {
    Create = function()
      Sound_Play("ui/windowopen.wav", 0.1)
    end,
    Destroy = function()
      Sound_Play("ui/windowclose.wav", 0.2)
    end,
    CreateChildren = function(): { Widget }
      return { widget }
    end,
    PreDraw = function(_, w: Widget)
      WidgetRenderer_DrawPanel(w.pos, w.size, 0.05, 1, opacity, 0)
    end,
    PostUpdate = function(_, w: Widget)
      if w:GetChildren():Size() == 0 then
        w:Delete()
      end
    end,
  }))
  return Components.CaptureKey(Components.CaptureMouse(Components.CaptureScroll(Components.Expand(window))))
end

return Widgets
