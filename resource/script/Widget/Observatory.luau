--!strict
-- A free camera orbiting its target, with clickable markers on nearby
-- objects and the system's name (Luau port of Widget/Observatory.lts).
-- Scroll to zoom, right-drag to orbit, click a marker to orbit that
-- object instead. F3 shows frame statistics.

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local FrameInfo = require("@lt/Widget/Dev/FrameInfo")
local Icons = require("@lt/Icons")
local Messages = require("@lt/Widget/Messages")
local SceneView = require("@lt/SceneView")
local Widgets = require("@lt/Widgets")

local Observatory = {}

-- Markers show within this many radii of an object
local VIEW_DISTANCE = 100
local MARKER_SIZE = 64

local function marker(camera: Camera, object: Object): Widget
  return Components.CaptureMouse(Widget_Luau(Widget_Create(), {
    GetHash = function(): number
      return object:GetHash()
    end,
    PreDraw = function(_, w: Widget)
      if w.focusMouse then
        Icon_Draw(object:GetIcon(), w:Center(), 32, 1, 1)
      end
    end,
    PostUpdate = function(_, w: Widget)
      if w.focusMouse and Mouse_LeftPressed() then
        camera:SetTarget(object)
      end
    end,
    Receive = function(_, _w: Widget, message: any)
      if Messages.Is(message, "GetObject") then
        message.object = object
      end
    end,
  }))
end

-- Markers for the nameable objects near enough to the camera
local function markers(camera: Camera): Widget
  return Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      local list = {}
      local system = camera:GetSystem()
      if system then
        local it = system:GetInteriorObjects()
        while it:HasMore() do
          local object = it:Get()
          if object:HasComponentNameable() and Camera_CanSee(object, VIEW_DISTANCE * object:GetRadius()) then
            table.insert(list, marker(camera, object))
          end
          it:Advance()
        end
      end
      return list
    end,
    PostPosition = function(_, w: Widget)
      local children = w:GetChildren()
      while children:HasMore() do
        local child = children:Get()
        local object = Messages.GetObject(child)
        if object then
          local proj = Camera_Project(camera, object:GetPos())
          local distance = vector.magnitude(camera:GetPos() - object:GetPos())
          local viewDistance = VIEW_DISTANCE * object:GetRadius()
          if proj.z > 0 and distance < viewDistance then
            child.alpha = 1 - distance / viewDistance
            local ss = w.pos + w.size * (vector.create(0.5, 0.5) + vector.create(0.5, -0.5) * vector.create(proj.x, proj.y))
            local lo, hi = vector.create(4, 4), w.size - vector.create(8, 8)
            ss = vector.create(math.clamp(ss.x, lo.x, math.max(lo.x, hi.x)), math.clamp(ss.y, lo.y, math.max(lo.y, hi.y)))
            child.pos = ss - vector.create(0.5 * MARKER_SIZE, 0.5 * MARKER_SIZE)
            child.size = vector.create(MARKER_SIZE, MARKER_SIZE)
          else
            child.alpha = 0
            child.pos = vector.create(0, 0)
            child.size = vector.create(0, 0)
          end
        end
        children:Advance()
      end
    end,
  })
end

local function title(camera: Camera): Widget
  return Widget_ListHorizontal(8, Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      local target = camera:GetTarget()
      local system = target and target:GetSystem()
      local name = if system then string.upper(system:GetName()) else ""
      return { Widgets.Text(Fonts.Medium(), name, 48, vector.create(1, 1, 1)) }
    end,
    PreDraw = function(_, w: Widget)
      Glyph_Draw(Glyph_Gradient(0, 1, 0.02, 0, 0.02, 1), w.pos, w.size, 1, 1)
    end,
  }))
end

local function overlay(camera: Camera): Widget
  return Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return {
        Components.AlignBottomLeft(Components.ExpandX(Components.Padding(32, 32, title(camera)))),
        Components.Expand(Widget_Dynamic(Widget_Stack(markers(camera)))),
      }
    end,
  })
end

function Observatory.Create(camera: Camera): Widget
  local radius, radiusT = 10000, 10000
  local pitch = -0.9 * math.pi / 2
  local yaw = 1.5
  local view = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      -- LTSL also ran a custom filter pass here, but every branch it
      -- enabled returned the frame unchanged
      return {
        SceneView.Rendered(camera),
        Widget_Layer(Compositor_Basic(0.05, 0.10, vector.create(0.40, 0.50, 0.75)), Mesh_Quad(), 1,
          Widget_Stack(overlay(camera))),
      }
    end,
    PostDraw = function(_, w: Widget)
      Icon_Draw(Icons.Cursors.Cross(), Cursor_Get(), 8, Colors.Primary, 1)
      if Key_Down(Key_F3()) then
        FrameInfo.Draw(w)
      end
    end,
    PreUpdate = function()
      radiusT *= 1 - 0.1 * Mouse_GetScrollDelta()
      if Mouse_RightDown() then
        local delta = Cursor_GetDelta()
        yaw -= 0.01 * delta.x
        pitch += 0.01 * delta.y
      end
      radius += (radiusT - radius) * (1 - Float_ExpDecay(FrameTimer_Get(), 0.1))
      local target = camera:GetTarget()
      local origin = if target then target:GetPos() else vector.create(0, 0, 0)
      local p = origin + radius * vector.create(math.sin(pitch) * math.cos(yaw), math.cos(pitch), math.sin(pitch) * math.sin(yaw))
      camera:SetRelativePos(p)
      camera:SetRelativeLookAt(origin)
      camera:SetRigidity(32)
    end,
  })
  return Components.Expand(Widget_Stack(view))
end

return Observatory
