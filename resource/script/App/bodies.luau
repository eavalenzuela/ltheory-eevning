--!strict
-- The bodies sheet: every kind of star (and, as they are made, planet
-- and moon) side by side, for looking at and for the golden images.
--
--   bin/launch bodies
--
-- Left to right: red dwarf, orange dwarf, yellow dwarf, yellow-white
-- star, white star.

local AppShell = require("@lt/AppShell")
local Bodies = require("@lt/Game/View/Bodies")
local SceneView = require("@lt/SceneView")
local StarTypes = require("@lt/Game/View/StarTypes")

local RADIUS = 1000
local SPACING = 3700

-- For scripted runs (the harness's `lua` command): look at one body from
-- a distance, or at the whole sheet again.
local focus = { index = 0, distance = 12500 }
;(_G :: any).BodiesDebug = {
  Focus = function(index: number, distance: number)
    focus.index, focus.distance = index, distance
  end,
  Sheet = function()
    focus.index, focus.distance = 0, 12500
  end,
}

return AppShell.Create(function(): Widget
  local camera = Camera_Create()
  camera:Push()
  local view = SceneView.Rendered(camera)
  local system = Object_System(vector.create(8.012, 8.012, 8.012), 31)

  local stars: { Bodies.Star } = {}
  local middle = (#StarTypes.list + 1) / 2
  for index, t in StarTypes.list do
    local star = Bodies.NewStar(t.id, index)
    -- (the camera looks from +z, where +x is to the left)
    Bodies.PlaceStar(star, vector.create((middle - index) * SPACING, 0, 0), RADIUS)
    system:AddInterior(star.face)
    system:AddInterior(star.corona)
    table.insert(stars, star)
  end

  local clock = 0
  local watching = -1
  return Widget_Stack(Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return { view }
    end,
    PreUpdate = function()
      local dt = FrameTimer_Get()
      clock += dt
      for _, star in stars do
        Bodies.TickStar(star, clock)
      end
      if watching ~= focus.index then
        watching = focus.index
        camera:SetTarget(stars[if watching > 0 then watching else math.ceil(middle)].face)
      end
      -- (the camera's "relative" position is a place in the scene)
      local at = stars[if watching > 0 then watching else math.ceil(middle)].face:GetPos()
      camera:SetRelativePos(at + vector.create(0, 0, focus.distance))
      camera:SetRelativeLookAt(at)
      camera:SetRigidity(8)
      system:Update(dt)
    end,
  }))
end)
