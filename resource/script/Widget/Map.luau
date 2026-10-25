--!strict
-- A top-down map of a system (Luau port of Widget/Map.lts). WASD pans, the
-- wheel zooms, double-click an object to follow it; objects have the same
-- right-click menu as in flight.

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Messages = require("@lt/Widget/Messages")
local WorldObject = require("@lt/Widget/HUD/WorldObject")

local Map = {}

local function mix(a: number, b: number, t: number): number
  return a + (b - a) * t
end

local function shown(object: Object): boolean
  return object:HasComponentInterior() or object:HasComponentNavigable()
    or object:HasComponentPilotable() or object:HasComponentResources() or object:IsCustom()
end

function Map.Create(player: Player, container: Object): Widget
  local target: Object? = nil
  local center, centerTarget = vector.create(0, 0), vector.create(0, 0)
  local zoom, zoomTarget = 1000000, 1000000

  local objects = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      local markers = {}
      local it = container:GetInteriorObjects()
      while it:HasMore() do
        local object = it:Get()
        if shown(object) then
          table.insert(markers, WorldObject.Create(player, object))
          if object:IsPlanet() then
            local children = object:GetChildren()
            while children:HasMore() do
              table.insert(markers, WorldObject.Create(player, children:Get()))
              children:Advance()
            end
          end
        end
        it:Advance()
      end
      return markers
    end,
    PreDraw = function(_, w: Widget)
      Glyph_Draw(Glyph_Grid(w:TopLeft(), w:BottomRight(), 1, 1, center / 5000, zoom / 1000000), 0, 1, Colors.Primary, 0.1)
    end,
    PostPosition = function(_, w: Widget)
      local aspect = w.size / math.min(w.size.x, w.size.y)
      local children = w:GetChildren()
      while children:HasMore() do
        local marker = children:Get()
        local object = Messages.GetObject(marker)
        if object then
          local pos = object:GetPos()
          local screen = w:Center() + 0.5 * w.size * ((vector.create(pos.x, pos.z) - center) / zoom) / aspect
          local size = math.clamp(vector.magnitude(object:GetScale()) * (10000 / zoom), 12, 64)
          marker.pos = screen - vector.create(size / 2, size / 2)
          marker.size = vector.create(size, size)
        end
        children:Advance()
      end
    end,
    PostUpdate = function(_, w: Widget)
      local dt = FrameTimer_Get()
      local step = 4 * zoom * dt
      if Key_Down(Key_W()) then centerTarget -= vector.create(0, step) end
      if Key_Down(Key_S()) then centerTarget += vector.create(0, step) end
      if Key_Down(Key_A()) then centerTarget -= vector.create(step, 0) end
      if Key_Down(Key_D()) then centerTarget += vector.create(step, 0) end

      if Mouse_DoubleClicked() then
        local children = w:GetChildren()
        while children:HasMore() do
          local marker = children:Get()
          if marker.focusMouse then
            target = Messages.GetObject(marker)
          end
          children:Advance()
        end
      end
      local followed = target
      if followed then
        local pos = followed:GetPos()
        centerTarget = vector.create(pos.x, pos.z)
      end

      zoomTarget *= 1 - 0.1 * Mouse_GetScrollDelta()
      local t = 1 - Float_ExpDecay(dt, 0.125)
      zoom = mix(zoom, zoomTarget, t)
      center += (centerTarget - center) * t
    end,
  })

  local map = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return { Components.Expand(Widget_Dynamic(objects)) }
    end,
  })
  return Components.Expand(Widget_Stack(map))
end

return Map
