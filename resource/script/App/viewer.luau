--!strict
-- The viewer: one window that goes through a list of views of a body
-- and saves a picture of each, and does it again whenever asked.
--
--   bin/launch viewer --no-present --scale 2 --out cache/viewer/shots
--
-- It is for working on how things look without opening a window per
-- picture: it is started once, can be minimised, and stays. To have it
-- reload every shader and take the pictures again, change the contents
-- of cache/viewer/request.txt (any text; a counter will do). It prints
-- "VIEWER DONE n" when a pass is complete.
--
-- cache/viewer/params.txt, if it exists, overrides settings for every
-- view: one "name value" a line (seaLevel 0.5), from Planet.TEMPERATE.

local AppShell = require("@lt/AppShell")
local Planet = require("@lt/Game/View/Planet")
local SceneView = require("@lt/SceneView")

local RADIUS = 1000
local SETTLE = 20       -- frames between setting a view up and saving it
local REQUEST = "cache/viewer/request.txt"
local PARAMS = "cache/viewer/params.txt"

type View = {
  name: string,
  seed: number,
  eye: vector,            -- where the camera is, in planet radii from its centre
  look: vector,           -- what it looks at, likewise
  light: vector,          -- the direction the light comes from
  set: { [string]: number }?,
}

local FRONT = vector.create(0, 0.15, 2.7)
local CENTRE = vector.create(0, 0, 0)
local DAY = vector.create(-0.45, 0.35, 0.82)
local SIDE = vector.create(-0.98, 0.15, 0.12)

local VIEWS: { View } = {
  { name = "temperate-1-day", seed = 1, eye = FRONT, look = CENTRE, light = DAY },
  { name = "temperate-2-terminator", seed = 1, eye = FRONT, look = CENTRE, light = SIDE },
  { name = "temperate-3-limb", seed = 1, eye = vector.create(0.2, 0.5, 1.75), look = vector.create(0.55, 0.62, 0), light = SIDE },
  { name = "temperate-4-close", seed = 1, eye = vector.create(0.25, 0.35, 1.32), look = vector.create(0.1, 0.2, 0), light = DAY },
  { name = "temperate-5-seed2", seed = 2, eye = FRONT, look = CENTRE, light = DAY },
  { name = "temperate-6-seed3", seed = 3, eye = FRONT, look = CENTRE, light = DAY },
  { name = "temperate-7-islands", seed = 1, eye = FRONT, look = CENTRE, light = DAY, set = { seaLevel = 0.56 } },
  { name = "temperate-8-dry", seed = 1, eye = FRONT, look = CENTRE, light = DAY, set = { seaLevel = 0.36, cloudCover = 0.3 } },
}

-- "name value" lines of a file, as a table.
local function readParams(): { [string]: number }
  local out: { [string]: number } = {}
  local ok, text = pcall(File_Read, PARAMS)
  if ok and type(text) == "string" then
    for name, value in string.gmatch(text, "([%a%.]+)%s+([%-%d%.]+)") do
      out[name] = tonumber(value) or 0
    end
  end
  return out
end

local function readRequest(): string
  local ok, text = pcall(File_Read, REQUEST)
  return if ok and type(text) == "string" then text else ""
end

return AppShell.Create(function(): Widget
  local camera = Camera_Create()
  camera:Push()
  local view = SceneView.Rendered(camera)
  local system = Object_System(vector.create(8.012, 8.012, 8.012), 31)

  local lamp: Object? = nil
  local interior = system:GetInteriorObjects()
  while interior:HasMore() do
    if interior:Get():IsStar() then
      lamp = interior:Get()
    end
    interior:Advance()
  end

  local world: Planet.World? = nil
  local built = -1          -- the seed of the world now standing; -1 for none
  local index = 0           -- the view being taken; 0 when idle
  local frames = 0
  local passes = 0
  local request = readRequest()
  local params: { [string]: number } = {}

  local function setUp(v: View)
    if built ~= v.seed or world == nil then
      if world then
        Object_Delete(world.body)
      end
      local made = Planet.NewTemperate(v.seed)
      made.body:SetScale(vector.create(RADIUS, RADIUS, RADIUS))
      system:AddInterior(made.body)
      camera:SetTarget(made.body)
      world, built = made, v.seed
    end
    local w = world :: Planet.World
    for name, value in Planet.TEMPERATE do
      local override: { [string]: number } = v.set or {}
      Planet.Set(w, name, override[name] or params[name] or value)
    end
    -- (judged in white light: the scene's own star is whatever colour
    -- its system rolled)
    Planet.Set(w, "whiteLight", params.whiteLight or 1)
    if lamp then
      lamp:SetPos(vector.normalize(v.light) * 500000)
    end
    frames = 0
  end

  local function begin()
    Shader_RecompileAll()
    params = readParams()
    built = -1
    index = 1
    setUp(VIEWS[1])
  end
  begin()

  return Widget_Stack(Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return { view }
    end,
    PreUpdate = function()
      if index > 0 then
        local v = VIEWS[index]
        -- (the camera's "relative" position is a place in the scene)
        camera:SetRelativePos(v.eye * RADIUS)
        camera:SetRelativeLookAt(v.look * RADIUS)
        camera:SetRigidity(60)
        frames += 1
        if frames == SETTLE then
          Screenshot_Save(v.name)
        elseif frames > SETTLE + 1 then
          index += 1
          if index > #VIEWS then
            index = 0
            passes += 1
            print(`VIEWER DONE {passes}`)
          else
            setUp(VIEWS[index])
          end
        end
      else
        frames += 1
        if frames % 30 == 0 then
          local now = readRequest()
          if now ~= request then
            request = now
            begin()
          end
        end
      end
      system:Update(FrameTimer_Get())
    end,
  }))
end)
