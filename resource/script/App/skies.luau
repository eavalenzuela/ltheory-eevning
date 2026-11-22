--!strict
-- A tool: the sky of any system, by the seed the game makes it with
-- (Scene: the galaxy's seed times 7919, and the system's id), looked at
-- any way. For sorting skies into families and baking a picture of each
-- for the stargates' horizons (Game/View/Horizon), with no window on the
-- desktop: run under the harness, which drives it by
--
--   bin/launch skies --no-present --fixed-step 60 --out DIR --do "..."
--
-- with `lua Skies.Show(seed)`, `lua Skies.Look(x, y, z)` (the way the
-- camera looks), `lua Skies.Fov(degrees)`, then `frames N` and `shot`.

local AppShell = require("@lt/AppShell")
local Horizon = require("@lt/Game/View/Horizon")
local SceneView = require("@lt/SceneView")
local Starbase = require("@lt/Game/View/Starbase")

return AppShell.Create(function(): Widget
  local camera = Camera_Create()
  camera:Push()
  local view = SceneView.Rendered(camera)
  local system: Object? = nil
  local look = vector.create(0, 0, 1)
  local fov = 70

  local function show(seed: number)
    local made = Object_System(vector.create(0, 0, 0), seed)
    made:AddInterior(camera)
    -- (the camera wants something to follow: a speck at the eye, too
    -- small to be seen)
    local speck = Object_Scenery({})
    Object_SetRenderable(speck, Starbase.Gate().model)
    speck:SetScale(vector.create(1e-3, 1e-3, 1e-3))
    made:AddInterior(speck)
    camera:SetTarget(speck)
    if system then
      Object_Delete(system :: Object)
    end
    system = made
  end

  -- (where the star is in its sky, as a way to look)
  local function star(): vector
    local s = system
    if s then
      local interior = s:GetInteriorObjects()
      while interior:HasMore() do
        if interior:Get():IsStar() then
          return vector.normalize(interior:Get():GetPos())
        end
        interior:Advance()
      end
    end
    return vector.create(0, 0, 1)
  end

  local globals = _G :: any
  globals.Skies = {
    Show = show,
    Look = function(x: number, y: number, z: number)
      look = vector.normalize(vector.create(x, y, z))
    end,
    Fov = function(degrees: number)
      fov = degrees
    end,
    Star = star,
    -- (look 'off' radians away from the star, swung 'around' radians round it)
    LookOff = function(off: number, around: number)
      local s = star()
      local side = vector.normalize(vector.cross(s, if math.abs(s.y) < 0.9 then vector.create(0, 1, 0) else vector.create(1, 0, 0)))
      local up = vector.cross(side, s)
      local swing = side * math.cos(around) + up * math.sin(around)
      look = vector.normalize(s * math.cos(off) + swing * math.sin(off))
    end,
    -- (the colours its sky is made of, as Horizon works them out, printed)
    Colors = function(seed: number)
      local glow, dust = Horizon.SkyColors(seed)
      print(string.format("SKY %d glow %.4f %.4f %.4f dust %.4f %.4f %.4f", seed, glow.x, glow.y, glow.z, dust.x, dust.y, dust.z))
    end,
  }
  show(1)

  return Widget_Stack(Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return { view }
    end,
    PreUpdate = function()
      camera:SetRelativePos(vector.create(0, 0, 0))
      camera:SetRelativeLookAt(look * 1000)
      camera:SetRigidity(100000)
      camera:SetFov(fov)
      local s = system
      if s then
        s:Update(FrameTimer_Get())
      end
    end,
  }))
end)
