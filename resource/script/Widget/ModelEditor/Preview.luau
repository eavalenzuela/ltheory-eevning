--!strict
-- A 3D preview of a renderable in its own little system (Luau port of
-- Widget/ModelEditor/Preview.lts). Scroll to zoom, right-drag to orbit.

local Components = require("@lt/Widget/Components")
local SceneView = require("@lt/SceneView")

local Preview = {}

function Preview.Create(renderable: Renderable): Widget
  local camera = Camera_Create()
  local system = Object_System(vector.create(15.012, 15.012, 15.012), 1340)
  local object = Object_Custom({})
  object:SetRenderable(renderable)
  object:SetScale(vector.create(100, 100, 100))
  system:AddInterior(object)
  camera:SetTarget(object)
  camera:SetRigidity(32)

  local radius = object:GetRadius()
  local radiusT = radius
  local pitch = -0.02 * math.pi / 2
  local yaw = 0
  local view = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return { SceneView.Rendered(camera) }
    end,
    PreDraw = function()
      camera:Push()
    end,
    PostDraw = function()
      Camera_Pop()
    end,
    PreUpdate = function()
      system:Update(FrameTimer_Get())
    end,
    PostUpdate = function(_, w: Widget)
      if w.focusScroll then
        radiusT *= 1 - 0.1 * Mouse_GetScrollDelta()
      end
      if Mouse_RightDown() then
        local delta = Cursor_GetDelta()
        yaw -= 0.01 * delta.x
        pitch += 0.01 * delta.y
      end
      radius += (radiusT - radius) * (1 - Float_ExpDecay(FrameTimer_Get(), 0.1))
      camera:SetRelativePos(radius * vector.create(math.sin(pitch) * math.cos(yaw), math.cos(pitch),
        math.sin(pitch) * math.sin(yaw)))
      camera:SetRigidity(32)
    end,
  })
  return Components.Expand(Components.Backdrop(vector.create(0.05, 0.05, 0.05), 1, 1, 0,
    Components.CaptureMouse(Components.CaptureScroll(Widget_Stack(view)))))
end

return Preview
