--!strict
-- An object's cargo tab: the items it holds, details of the selected one,
-- and a (decorative) composition chart (Luau port of
-- Widget/Object/Cargo.lts).

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local GridList = require("@lt/Widget/GridList")
local ItemInfo = require("@lt/Widget/ItemInfo")
local ScrollFrame = require("@lt/Widget/ScrollFrame")
local Widgets = require("@lt/Widgets")

local Cargo = {}

type Selection = { item: Item? }

local ring = Glyph_Arc(0, 1, 0.01, 1, 1, 0, 1)

local function badge(item: Item, selection: Selection): Widget
  return Widget_Luau(Widget_Create(), {
    PreDraw = function(_, w: Widget)
      local selected = selection.item == item
      local c = if selected then 3 * Colors.Primary else 1.5 * Colors.Primary
      Glyph_Draw(ring, w:Center(), 0.4 * w.size, c, if selected then 0.5 else 0.1)
      if w:GetParent().focusMouse then
        Glyph_Draw(ring, w:Center(), 0.5 * w.size, c, 1)
      end
      Icon_Draw(item:GetIcon(), w:Center(), 0.2 * w.size, c, 1)
    end,
  })
end

local function row(object: Object, item: Item, selection: Selection): Widget
  local size = 48
  local entry = Widget_Luau(Widget_Create(), {
    GetHash = function()
      return item:GetHash()
    end,
    CreateChildren = function(): { Widget }
      return {
        Components.MinSize(size, badge(item, selection)),
        Components.AlignCenter(Widgets.ListV(0,
          Components.AlignLeftCenter(Widgets.Text(Fonts.Default(), item:GetName(), 16, vector.create(1, 1, 1))),
          Components.AlignLeftCenter(Widgets.Text(Fonts.Heading(), item:GetTypeString(), 14, Colors.Primary)))),
        Components.Expand(Components.GreedyX(Widget_Create())),
        Components.Margin(0, vector.create(16, 0), Components.AlignCenter(
          Widgets.Text(Fonts.Medium(), tostring(object:GetItemCount(item)), 16, Colors.Primary))),
      }
    end,
    PreDraw = function(_, w: Widget)
      local selected = selection.item == item
      WidgetRenderer_DrawPanel(w.pos, w.size, 0.1, if w.focusMouse or selected then 0.75 else 0.25, 1, 0)
      if selected then
        local half = 0.5 * size
        local h2 = half + 2
        Glyph_Draw(Glyph_Line(w:TopLeft() + vector.create(h2, 0), w:TopRight() - vector.create(h2, 0), 1, 1), 0, 1, Colors.Primary, 1)
        Glyph_Draw(Glyph_Line(w:BottomLeft() + vector.create(h2, 0), w:BottomRight() - vector.create(h2, 0), 1, 1), 0, 1, Colors.Primary, 1)
        Glyph_Draw(Glyph_Arc(0, 1, 0.01, 1, 1, 0, 0.25), w:LeftCenter() + vector.create(half, 0), half, Colors.Primary, 1)
        Glyph_Draw(Glyph_Arc(0, 1, 0.01, 1, 1, 0.5, 0.25), w:RightCenter() - vector.create(half, 0), half, Colors.Primary, 1)
      end
    end,
    Receive = function(_, _w: Widget, message: any)
      if type(message) == "table" and message.type == "Click" then
        selection.item = item
      end
    end,
  })
  local clickable = Components.CaptureMouse(Components.Expand(Widget_ListHorizontal(8, entry)))
  return Components.Clickable({ type = "Click" }, clickable, clickable)
end

local function contents(object: Object, selection: Selection): Widget
  return Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      local rows = {}
      local cargo = object:GetCargo()
      while cargo:HasMore() do
        table.insert(rows, row(object, cargo:GetItem(), selection))
        cargo:Advance()
      end
      return rows
    end,
  })
end

-- Decorative slices, fixed by seed (the LTSL tab shows the same)
local function pieChart(): Widget
  local phases, angles = {}, {}
  local rng = RNG_MTG(12)
  local total = 0
  for i = 1, 5 do
    angles[i] = rng:Float()
    total += angles[i]
  end
  local cumulative = 0
  for i = 1, 5 do
    angles[i] /= total
    phases[i] = cumulative
    cumulative += angles[i]
  end
  return Widget_Luau(Widget_Create(), {
    PreDraw = function(_, w: Widget)
      local r = 0.4 * math.min(w.size.x, w.size.y)
      local center = w:Center()
      for i = 1, #phases do
        local phase, angle = phases[i], angles[i]
        local s = math.sqrt(i / (#phases + 1))
        Glyph_Draw(Glyph_Arc(0, 0.5, 0.5, 1, 1, phase, 0.49 * 0.5 * angle), center, s * r, Colors.Primary, 0.1)
        Glyph_Draw(Glyph_Arc(0, 0.99, 0.001, 1, 1, phase, 0.49 * 0.5 * angle), center, s * r, Colors.Primary, 1)
        for _, edge in { phase + 0.245 * angle, phase - 0.245 * angle } do
          local a = 2 * math.pi * edge
          Glyph_Draw(Glyph_LineFade(center - s * r * vector.create(math.cos(a), math.sin(a)), center, 1, 1), 0, 1, Colors.Primary, 1)
        end
      end
      Glyph_Draw(Glyph_Arc(0, 1, 0.1, 1, 1, 0, 1), center, 4, Colors.Primary, 0.1)
    end,
  })
end

function Cargo.Create(player: Player, object: Object): Widget
  local selection: Selection = { item = nil }

  local list = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return {
        GridList.Create("CARGO", contents(object, selection)),
        Components.Padding(8, 8, ScrollFrame.V(Widget_Dynamic(Components.Expand(
          Widget_ListVertical(8, contents(object, selection)))))),
      }
    end,
    PreDraw = function(_, w: Widget)
      WidgetRenderer_DrawPanel(w.pos, w.size, 0.05, 0.75, 1, 0)
    end,
  })

  local shown: Item? = nil
  local preview = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      shown = selection.item
      local item = shown
      return if item then { ItemInfo.Create(player, item) } else {}
    end,
    PrePosition = function(_, w: Widget)
      if shown then
        w.greed = vector.create(1, 1)
      end
    end,
    PreUpdate = function(_, w: Widget)
      if shown ~= selection.item then
        w:Rebuild()
      end
    end,
  })

  local info = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return { Components.MinSize(256, pieChart()) }
    end,
    PreDraw = function(_, w: Widget)
      WidgetRenderer_DrawPanel(w.pos, w.size, 0.05, 0.75, 1, 0)
    end,
  })

  local body = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return {
        Components.Expand(Components.GreedyY(Widgets.ListH(8,
          Components.Expand(Components.Greedy(vector.create(5, 0), Widget_ListVertical(0, list))),
          Components.Expand(Widgets.ListV(8,
            Components.ExpandX(Widget_Stack(preview)),
            Widgets.EmptySpaceV(),
            Components.Expand(Components.Padding(16, 16, Widget_ListVertical(4, info)))))))),
      }
    end,
  })
  return Components.Expand(Widget_Stack(body))
end

return Cargo
