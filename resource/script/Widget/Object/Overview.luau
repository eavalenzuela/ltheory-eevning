--!strict
-- An object's overview tab: owner, integrity, cargo, location, activity and
-- stats beside a rotating preview of its model (Luau port of
-- Widget/Object/Overview.lts). Systems show their map instead. Clicking the
-- owner or location opens their info in the browser.

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Icons = require("@lt/Icons")
local Map = require("@lt/Widget/Map")
local Widgets = require("@lt/Widgets")

local Overview = {}

local white = vector.create(1, 1, 1)

-- A label right-aligned in a fixed column
local function label(widget: Widget): Widget
  return Components.MinSize(vector.create(80, 0), Components.AlignCenter(Widgets.ListH(0,
    Components.Expand(Components.GreedyX(Widget_Create())), widget)))
end

local function line(caption: string, icon: Icon, value: Widget, color: vector?): Widget
  local c = color or Colors.Primary
  return Widgets.ListH(8,
    label(Components.AlignCenter(Widgets.Text(Fonts.Heading(), caption, 12, c))),
    Components.AlignCenter(Components.MinSize(32, Widgets.Icon(icon, c))),
    Components.AlignCenter(value))
end

local function ratio(a: number, b: number, color: vector): Widget
  return Widgets.ListH(2,
    Components.AlignCenter(Widgets.Text(Fonts.Medium(), tostring(a), 20, color)),
    Components.AlignCenter(Widgets.Text(Fonts.Medium(), "/", 20, white)),
    Components.AlignCenter(Widgets.Text(Fonts.Medium(), tostring(b), 20, white)))
end

-- Ask the enclosing ObjectInfo for an info view of 'object' and follow it
local function openInfo(w: Widget, player: Player, object: Object | Player)
  local request = { type = "CreateObjectInfo", player = player, object = object, widget = nil :: Widget? }
  w:SendUp(request)
  local info = request.widget
  if info then
    w:SendUp({ type = "Link", widget = info })
  end
end

-- A clickable row panel around 'widget'; clicks are passed down to it
local function miniWidget(widget: Widget): Widget
  local panel = Widget_Luau(Widget_Stack(Widget_Create()), {
    PreDraw = function(_, w: Widget)
      local c = if w.focusMouse then Colors.Primary else vector.create(0.08, 0.08, 0.08)
      WidgetRenderer_DrawPanel(w.pos, w.size, c, 0.25, 1, 0)
    end,
    PostUpdate = function(_, w: Widget)
      if w.focusMouse and Mouse_LeftPressed() then
        w:SendDown({ type = "Click" })
      end
    end,
  })
  local self = Components.CaptureMouse(Components.Expand(panel))
  self:AddChild(Components.Padding(vector.create(16, 12), vector.create(16, 12), Components.AlignLeftCenter(widget)))
  return self
end

-- A row that rebuilds its contents with 'build' and handles clicks
local function section(build: () -> Widget, onClick: ((w: Widget) -> ())?): Widget
  return Widget_ListVertical(4, Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return { build() }
    end,
    Receive = function(_, w: Widget, message: any)
      if onClick and type(message) == "table" and message.type == "Click" then
        onClick(w)
      end
    end,
  }))
end

local function stats(object: Object): Widget
  local width = 96
  local function stat(caption: string, value: Widget): Widget
    return Widgets.ListH(16,
      Components.MinSize(vector.create(width, 0), Widgets.ListH(0,
        Components.Expand(Components.GreedyX(Widget_Create())),
        Widgets.Text(Fonts.Heading(), caption, 12, Colors.Primary))),
      value)
  end
  local function text(value: string): Widget
    return Components.AlignCenter(Widgets.Text(Fonts.Medium(), value, 14, white))
  end
  local dot = Glyph_Circle(0, 1, 1, 1)
  return Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      local firepower, power = 0, 0
      local sockets = object:GetSockets()
      while sockets:HasMore() do
        local child = sockets:Get()
        if child then
          local kind = child:GetSupertype()
          if kind then
            firepower += kind:GetCapability().Attack
            power += kind:GetCapability().Power
          end
          local mounts = child:GetSockets()
          while mounts:HasMore() do
            local mount = mounts:Get()
            local mountKind = mount and mount:GetSupertype()
            if mountKind then
              firepower += mountKind:GetCapability().Attack
            end
            mounts:Advance()
          end
        end
        sockets:Advance()
      end
      local bound = object:GetRenderable():GetBound()
      local size = object:GetScale() * (bound.upper - bound.lower)
      return {
        stat("MASS", text(`{object:GetMass() / 1000} Mg`)),
        stat("TOTAL INTEGRITY", text(tostring(object:GetMaxHealth()))),
        stat("TOTAL FIREPOWER", text(`{firepower} /s`)),
        stat("POWER OUTPUT", text(`{power / 1000} kW`)),
        stat("DIMENSIONS", Widgets.ListH(2,
          text(`{size.x} m`), Components.AlignCenter(Widgets.Text(Fonts.Medium(), "/", 14, Colors.Primary)),
          text(`{size.y} m`), Components.AlignCenter(Widgets.Text(Fonts.Medium(), "/", 14, Colors.Primary)),
          text(`{size.z} m`))),
      }
    end,
    PreDraw = function(_, w: Widget)
      local p1 = w:TopLeft() + vector.create(width + 6 + 16, 16)
      local p2 = w:BottomLeft() + vector.create(width + 6 + 16, -16)
      Glyph_Draw(Glyph_Line(p1, p2, 1, 1), 0, 1, Colors.Primary, 0.1)
      Glyph_Draw(dot, p1, 16, Colors.Primary, 1)
      Glyph_Draw(dot, p2, 16, Colors.Primary, 1)
    end,
  })
end

-- The object's model, slowly turning, with rulers
local function preview(object: Object): Widget
  local t = 0
  return Widget_Luau(Widget_Create(), {
    PreDraw = function(_, w: Widget)
      t += 0.1 * FrameTimer_Get()
      local renderable = object:GetRenderable()
      if not renderable then
        return
      end
      local fovy = 0.01 * (math.pi / 180)
      local bound = renderable:GetBound()
      local size = bound.upper - bound.lower
      local d = math.max(size.z, size.x * w.size.x / w.size.y) * 0.5 / math.tan(0.5 * fovy)
      local pos = d * vector.create(0, -1, 0)
      WidgetRenderer_DrawRenderable(renderable, Transform_Identity(), pos, -1 * vector.normalize(pos),
        vector.create(0, 0, 1), fovy, w.pos, w.size, Colors.Primary, 1, t)

      for i = 0, 11 do
        local p = w:GetPoint(i / 11, 0)
        Glyph_Draw(Glyph_Line(p, p + vector.create(0, 6), 1, 1), 0, 1, Colors.Primary, 0.5)
        if i > 0 then
          Glyph_Draw(Glyph_Line(p, w:GetPoint((i - 1) / 11, 0), 1, 1), 0, 1, Colors.Primary, 0.1)
        end
      end
      for i = 0, 5 do
        local p = w:GetPoint(1, i / 5)
        Glyph_Draw(Glyph_Line(p, p - vector.create(6, 0), 1, 1), 0, 1, Colors.Primary, 0.5)
        if i > 0 then
          Glyph_Draw(Glyph_Line(p, w:GetPoint(1, (i - 1) / 5), 1, 1), 0, 1, Colors.Primary, 0.1)
        end
      end
    end,
  })
end

local function overview(player: Player, object: Object): Widget
  return Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      local rows = {}
      if object:HasComponentAsset() then
        table.insert(rows, miniWidget(section(function()
          local owner = object:GetOwner()
          return line("PROPERTY OF", Icons.Person(),
            Widgets.Text(Fonts.Medium(), if owner then string.upper(owner:GetName()) else "NO OWNER", 20, white),
            2 * Colors.Primary)
        end, function(w)
          local owner = object:GetOwner()
          if owner then
            openInfo(w, player, owner)
          end
        end)))
      end
      if object:HasComponentIntegrity() then
        table.insert(rows, miniWidget(section(function()
          local color = Colors.Hostile + (Colors.Friendly - Colors.Hostile) * object:GetHealthNormalized()
          return line("INTEGRITY", Icons.Medic(), ratio(object:GetHealth(), object:GetMaxHealth(), color), color)
        end)))
      end
      if object:HasComponentCargo() then
        table.insert(rows, miniWidget(section(function()
          return line("CARGO", Icons.Cargo(), ratio(object:GetUsedCapacity(), object:GetCapacity(), Colors.Primary))
        end)))
      end
      if object:HasComponentOrientation() then
        table.insert(rows, miniWidget(section(function()
          local container = object:GetContainer()
          return line("LOCATION", Icons.Scanner(),
            Widgets.Text(Fonts.Medium(), if container then string.upper(container:GetName()) else "???", 20, white))
        end, function(w)
          local container = object:GetContainer()
          if container then
            openInfo(w, player, container)
          end
        end)))
      end
      if object:HasComponentTasks() then
        table.insert(rows, miniWidget(section(function()
          local activity = if object:HasTask() then object:GetCurrentTask().task:GetName() else "IDLE"
          return line("ACTIVITY", Icons.Refresh(), Widgets.Text(Fonts.Medium(), activity, 20, white))
        end)))
      end
      table.insert(rows, Components.GreedyY(Components.Expand(Components.MinSize(16, Widget_Create()))))
      if object:HasComponentDrawable() then
        table.insert(rows, miniWidget(Widget_ListVertical(4, stats(object))))
      end
      return rows
    end,
  })
end

function Overview.Create(player: Player, object: Object): Widget
  if object:HasComponentInterior() and not object:HasComponentDockable() then
    return Components.Expand(Map.Create(player, object))
  end
  return Components.Expand(Widgets.ListH(16,
    Components.Expand(Components.Padding(0, 0, Widget_ListVertical(8, overview(player, object)))),
    Components.Margin(16, 16, Components.GreedyX(Components.Expand(Widget_Stack(preview(object)))))))
end

return Overview
