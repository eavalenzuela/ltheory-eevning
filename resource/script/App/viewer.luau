--!strict
-- The viewer: one window that goes through a list of views of a body
-- and saves a picture of each, and does it again whenever asked.
--
--   script/viewer start [FILTER]     open it and take the views
--   script/viewer again [FILTER]     reload the shaders, take them again
--   script/viewer sheet PREFIX       the pictures side by side
--   script/viewer stop
--
-- It is for working on how things look without opening a window per
-- picture: it is started once, can be minimised, and stays. Shaders and
-- settings are reloaded on every pass; a change to a script needs it
-- started again.
--
-- How it is told what to do (script/viewer does this): it takes its
-- views again whenever the contents of cache/viewer/request.txt change.
-- If that has a second word, only views with that word in their names
-- are taken. When a pass is complete it copies the request to
-- cache/viewer/done.txt.
--
-- cache/viewer/params.txt, if it exists, overrides settings for every
-- view, one a line: a name from the kind being looked at (Planet.kinds)
-- and a number (seaLevel 0.5), or three for a colour
-- (rockPale 0.6 0.5 0.4).

local AppShell = require("@lt/AppShell")
local Planet = require("@lt/Game/View/Planet")
local SceneView = require("@lt/SceneView")

local RADIUS = 1000
local SETTLE = 20       -- frames between setting a view up and saving it
local REQUEST = "cache/viewer/request.txt"
local PARAMS = "cache/viewer/params.txt"
local DONE = "cache/viewer/done.txt"

type View = {
  name: string,
  kind: string,
  seed: number,
  eye: vector,            -- where the camera is, in planet radii from its centre
  look: vector,           -- what it looks at, likewise
  light: vector,          -- the direction the light comes from
  set: { [string]: number }?,
}

local FRONT = vector.create(0, 0.15, 2.7)
local NEAR = vector.create(0.25, 0.35, 1.32)
local CENTRE = vector.create(0, 0, 0)
local DAY = vector.create(-0.45, 0.35, 0.82)
local SIDE = vector.create(-0.98, 0.15, 0.12)

local VIEWS: { View } = {
  { name = "temperate-1-day", kind = "temperate", seed = 1, eye = FRONT, look = CENTRE, light = DAY },
  { name = "temperate-2-terminator", kind = "temperate", seed = 1, eye = FRONT, look = CENTRE, light = SIDE },
  { name = "temperate-3-limb", kind = "temperate", seed = 1, eye = vector.create(0.2, 0.5, 1.75), look = vector.create(0.55, 0.62, 0), light = SIDE },
  { name = "temperate-4-close", kind = "temperate", seed = 1, eye = NEAR, look = vector.create(0.1, 0.2, 0), light = DAY },
  { name = "moon-1-day", kind = "moon", seed = 1, eye = FRONT, look = CENTRE, light = DAY },
  { name = "moon-2-terminator", kind = "moon", seed = 1, eye = FRONT, look = CENTRE, light = SIDE },
  { name = "moon-3-close", kind = "moon", seed = 1, eye = NEAR, look = vector.create(0.1, 0.2, 0), light = SIDE },
  { name = "moon-4-seed2", kind = "moon", seed = 2, eye = FRONT, look = CENTRE, light = SIDE },
  { name = "barren-1-day", kind = "barren", seed = 1, eye = FRONT, look = CENTRE, light = DAY },
  { name = "barren-2-terminator", kind = "barren", seed = 1, eye = FRONT, look = CENTRE, light = SIDE },
  { name = "barren-3-close", kind = "barren", seed = 1, eye = NEAR, look = vector.create(0.1, 0.2, 0), light = SIDE },
  { name = "barren-4-seed2", kind = "barren", seed = 2, eye = FRONT, look = CENTRE, light = DAY },
}

-- The settings in the params file.
local function readParams(): Planet.Tweaks
  local out: Planet.Tweaks = {}
  local ok, text = pcall(File_Read, PARAMS)
  if ok and type(text) == "string" then
    for line in string.gmatch(text, "[^\n]+") do
      local name = string.match(line, "^%s*([%a%.]+)")
      local numbers: { number } = {}
      for word in string.gmatch(line, "%s([%-%d%.]+)") do
        table.insert(numbers, tonumber(word) or 0)
      end
      if name and #numbers == 1 then
        out[name] = numbers[1]
      elseif name and #numbers == 3 then
        out[name] = numbers
      end
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
  local built = ""          -- the kind and seed of the world now standing
  local index = 0           -- the view being taken; 0 when idle
  local frames = 0
  local request = readRequest()
  local params: Planet.Tweaks = {}
  local views: { View } = VIEWS

  local function setUp(v: View)
    local tweaks = table.clone(params)
    local key = `{v.kind}:{v.seed}`
    if v.set then
      for name, value in v.set do
        tweaks[name] = value
        key ..= `:{name}={value}`
      end
    end
    if built ~= key or world == nil then
      if world then
        Object_Delete(world.body)
      end
      local made = Planet.New(v.kind, v.seed, nil, tweaks)
      made.body:SetScale(vector.create(RADIUS, RADIUS, RADIUS))
      system:AddInterior(made.body)
      camera:SetTarget(made.body)
      world, built = made, key
    end
    -- (judged in white light: the scene's own star is whatever colour
    -- its system rolled)
    local white = params.whiteLight
    Planet.Set(world :: Planet.World, "whiteLight", if type(white) == "number" then white else 1)
    if lamp then
      lamp:SetPos(vector.normalize(v.light) * 500000)
    end
    frames = 0
  end

  local function begin()
    Shader_RecompileAll()
    params = readParams()
    local filter = string.match(request, "^%S+%s+(%S+)")
    views = {}
    for _, v in VIEWS do
      if filter == nil or string.find(v.name, filter, 1, true) then
        table.insert(views, v)
      end
    end
    if #views == 0 then
      views = VIEWS
    end
    built = ""
    index = 1
    setUp(views[1])
  end
  begin()

  return Widget_Stack(Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return { view }
    end,
    PreUpdate = function()
      if index > 0 then
        local v = views[index]
        -- (the camera's "relative" position is a place in the scene)
        camera:SetRelativePos(v.eye * RADIUS)
        camera:SetRelativeLookAt(v.look * RADIUS)
        camera:SetRigidity(60)
        frames += 1
        if frames == SETTLE then
          Screenshot_Save(v.name)
        elseif frames > SETTLE + 1 then
          index += 1
          if index > #views then
            index = 0
            File_Write(DONE, request)
          else
            setUp(views[index])
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
