--!strict
-- An owner's assets tab: everything they own, with location, health and
-- activity; selecting one shows its own info beside the list (Luau port of
-- Widget/Object/Assets.lts).

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local GridList = require("@lt/Widget/GridList")
local Icons = require("@lt/Icons")
local ScrollFrame = require("@lt/Widget/ScrollFrame")
local Widgets = require("@lt/Widgets")

local Assets = {}

type Selection = { object: Object? }

-- Ask the enclosing ObjectInfo to build an info view of 'object'
export type CreateObjectInfo = { type: "CreateObjectInfo", player: Player, object: Object, widget: Widget? }

local ring = Glyph_Arc(0, 1, 0.01, 1, 1, 0, 1)

local function badge(object: Object, selection: Selection): Widget
  return Widget_Luau(Widget_Create(), {
    PreDraw = function(_, w: Widget)
      local selected = selection.object == object
      local c = if selected then 3 * Colors.Primary else 1.5 * Colors.Primary
      Glyph_Draw(ring, w:Center(), 0.4 * w.size, c, if selected then 0.5 else 0.1)
      if w:GetParent().focusMouse then
        Glyph_Draw(ring, w:Center(), 0.5 * w.size, c, 1)
      end
      Icon_Draw(object:GetIcon(), w:Center(), 0.3 * w.size, c, 1)
    end,
  })
end

local function asset(object: Object, selection: Selection): Widget
  local size = 56
  local selected = false
  local white = vector.create(1, 1, 1)
  local entry = Widget_Luau(Widget_Create(), {
    GetHash = function()
      return object:GetHash()
    end,
    CreateChildren = function(): { Widget }
      local container = object:GetContainer()
      local health = object:GetHealthNormalized()
      local healthColor = Colors.Hostile + (Colors.Friendly - Colors.Hostile) * health
      local children = {
        Components.MinSize(size, badge(object, selection)),
        Components.MinSize(vector.create(196, 0), Components.AlignCenter(Widgets.ListV(2,
          Components.AlignLeftCenter(Widgets.Text(Fonts.Default(), object:GetName(), 16, white)),
          Components.AlignLeftCenter(Widgets.Text(Fonts.Heading(),
            if container then string.upper(container:GetName()) else "---", 14, Colors.Primary))))),
        Components.MinSize(vector.create(64, 0), Components.AlignCenter(Widgets.ListH(8,
          Components.AlignCenter(Components.MinSize(16, Widgets.Icon(Icons.Medic(), healthColor))),
          Components.AlignCenter(Widgets.Text(Fonts.Medium(), `{math.round(100 * health)}%`, 14, healthColor))))),
      }
      if object:HasComponentTasks() then
        local task = object:GetCurrentTask()
        local activity = if object:HasTask() then task.task:GetName() else "Idle"
        table.insert(children, Components.AlignCenter(Widgets.ListH(8,
          Components.AlignCenter(Components.MinSize(16, Widgets.Icon(Icons.Refresh(), Colors.Primary))),
          Components.AlignCenter(Widgets.Text(Fonts.Medium(), activity, 14, Colors.Primary)))))
      end
      return children
    end,
    PostUpdate = function(_, w: Widget)
      if selected and selection.object ~= object then
        selected = false
        w:Rebuild()
      end
    end,
    PreDraw = function(_, w: Widget)
      WidgetRenderer_DrawPanel(w.pos, w.size, 0.1, if w.focusMouse or selected then 0.75 else 0.25, 1, 0)
      if selected then
        local half = 0.5 * size
        local h2 = half + 2
        Glyph_Draw(Glyph_Line(w:TopLeft() + vector.create(h2, 0), w:TopRight() - vector.create(h2, 0), 1, 1), 0, 1, Colors.Primary, 2)
        Glyph_Draw(Glyph_Line(w:BottomLeft() + vector.create(h2, 0), w:BottomRight() - vector.create(h2, 0), 1, 1), 0, 1, Colors.Primary, 2)
        Glyph_Draw(Glyph_Arc(0, 0.99, 0.01, 1, 1, 0, 0.25), w:LeftCenter() + vector.create(half, 0), half, Colors.Primary, 2)
        Glyph_Draw(Glyph_Arc(0, 0.99, 0.01, 1, 1, 0.5, 0.25), w:RightCenter() - vector.create(half, 0), half, Colors.Primary, 2)
      end
    end,
    Receive = function(_, w: Widget, message: any)
      if type(message) == "table" and message.type == "Click" then
        selection.object = object
        selected = true
        w:Rebuild()
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
      local assets = object:GetAssets()
      while assets:HasMore() do
        table.insert(rows, asset(assets:Get(), selection))
        assets:Advance()
      end
      return rows
    end,
  })
end

function Assets.Create(player: Player, object: Object): Widget
  local selection: Selection = { object = nil }

  local list = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return {
        GridList.Create("ASSETS", contents(object, selection)),
        Components.Padding(8, 8, ScrollFrame.V(Widget_Dynamic(Components.Expand(
          Widget_ListVertical(4, contents(object, selection)))))),
      }
    end,
    PreDraw = function(_, w: Widget)
      WidgetRenderer_DrawPanel(w.pos, w.size, 0.05, 0.75, 1, 16)
    end,
  })

  local shown: Object? = nil
  local preview = Widget_Luau(Widget_Create(), {
    CreateChildren = function(_, w: Widget): { Widget }
      shown = selection.object
      local current = shown
      if not current then
        return {}
      end
      local request: CreateObjectInfo = { type = "CreateObjectInfo", player = player, object = current, widget = nil }
      w:SendUp(request)
      local info = request.widget
      return if info then { info } else {}
    end,
    PrePosition = function(_, w: Widget)
      if shown then
        w.greed = vector.create(1, 1)
      end
    end,
    PreUpdate = function(_, w: Widget)
      if shown ~= selection.object then
        w:Rebuild()
      end
    end,
  })

  local body = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return {
        Components.Expand(Components.GreedyY(Widgets.ListH(8,
          Components.GreedyX(Components.Expand(Widget_ListVertical(4, list))),
          Components.Expand(Widget_Stack(preview))))),
      }
    end,
  })
  return Components.Expand(Widget_ListVertical(8, body))
end

return Assets
