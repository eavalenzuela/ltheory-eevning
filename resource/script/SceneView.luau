--!strict
-- Helpers shared by the space demo apps (dogfight, war, rails, ...).

local SceneView = {}

-- The game view interface: 'camera' rendered with SMAA and dither, with
-- the 'ui' interface composited in
function SceneView.Create(camera: Camera, ui: Interface): Interface
  local passes = New.Vector_Reference_RenderPassT()
  passes:Append(RenderPass_Clear(0))
  passes:Append(RenderPass_Camera(camera))
  passes:Append(RenderPass_SMAA())
  passes:Append(RenderPass_Interface(ui))
  passes:Append(RenderPass_PostFilter("post/dither.jsl"))
  local view = Interface_Create("Game View")
  view:Add(Widget_Rendered(passes))
  return view
end

-- The camera's view as a widget, without UI
function SceneView.Rendered(camera: Camera): Widget
  local passes = New.Vector_Reference_RenderPassT()
  passes:Append(RenderPass_Clear(0))
  passes:Append(RenderPass_Camera(camera))
  passes:Append(RenderPass_SMAA())
  passes:Append(RenderPass_PostFilter("post/dither.jsl"))
  return Widget_Rendered(passes)
end

-- This frame's simulation step: capped at 0.1 s, 20x while H is held
function SceneView.TimeStep(): number
  local dt = math.min(FrameTimer_Get(), 0.1)
  if Key_Down(Key_H()) then
    dt *= 20
  end
  return dt
end

-- Toggled by P; true while the simulation should pause
local paused = false
function SceneView.Paused(): boolean
  if Key_Pressed(Key_P()) then
    paused = not paused
  end
  return paused
end

return SceneView
