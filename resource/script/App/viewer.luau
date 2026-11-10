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
local Effects = require("@lt/Game/View/Effects")
local Planet = require("@lt/Game/View/Planet")
local Star = require("@lt/Game/View/Star")
local SceneView = require("@lt/SceneView")

local RADIUS = 1000
local SETTLE = 20       -- frames between setting a view up and saving it
local REQUEST = "cache/viewer/request.txt"
local PARAMS = "cache/viewer/params.txt"
local DONE = "cache/viewer/done.txt"

type View = {
  name: string,
  kind: string,           -- a kind of planet (Planet.kinds), or "star-" and a class of star
  seed: number,
  eye: vector,            -- where the camera is, in planet radii from its centre
  look: vector,           -- what it looks at, likewise
  light: vector,          -- the direction the light comes from
  set: { [string]: number }?,
  radius: number?,        -- how big to make the body, if not RADIUS
  -- For a view of weapons firing in place of a body: one row to a
  -- weapon, each fired this long before the picture is taken.
  fire: { Fire }?,
}

type Fire = { type: string, age: number, outcome: string, struck: string, flight: number? }

local FRONT = vector.create(0, 0.15, 2.7)
local NEAR = vector.create(0.25, 0.35, 1.32)
local CENTRE = vector.create(0, 0, 0)
local DAY = vector.create(-0.45, 0.35, 0.82)
-- (The light may not come from in front of the camera: the engine's
-- star in view whites the picture out. A night side is seen across the
-- terminator.)
local SIDE = vector.create(-0.98, 0.15, 0.12)

local CLOSE = vector.create(0.1, 0.2, 0)

-- Four views of a kind: by day, across the terminator, close to, and
-- another seed (which, for a kind that comes in several colourings, is
-- another of those).
local function four(kind: string): { View }
  return {
    { name = `{kind}-1-day`, kind = kind, seed = 1, eye = FRONT, look = CENTRE, light = DAY },
    { name = `{kind}-2-terminator`, kind = kind, seed = 1, eye = FRONT, look = CENTRE, light = SIDE },
    { name = `{kind}-3-close`, kind = kind, seed = 1, eye = NEAR, look = CLOSE, light = SIDE },
    { name = `{kind}-4-seed2`, kind = kind, seed = 2, eye = FRONT, look = CENTRE, light = DAY },
  }
end

local VIEWS: { View } = {
  { name = "temperate-1-day", kind = "temperate", seed = 1, eye = FRONT, look = CENTRE, light = DAY },
  { name = "temperate-2-terminator", kind = "temperate", seed = 1, eye = FRONT, look = CENTRE, light = SIDE },
  { name = "temperate-3-limb", kind = "temperate", seed = 1, eye = vector.create(0.2, 0.5, 1.75), look = vector.create(0.55, 0.62, 0), light = SIDE },
  { name = "temperate-4-close", kind = "temperate", seed = 1, eye = NEAR, look = CLOSE, light = DAY },
  { name = "gas-5-seed3", kind = "gas", seed = 3, eye = FRONT, look = CENTRE, light = DAY },
  { name = "gas-6-seed4", kind = "gas", seed = 4, eye = FRONT, look = CENTRE, light = DAY },
  { name = "gas-7-seed5", kind = "gas", seed = 5, eye = FRONT, look = CENTRE, light = SIDE },
  { name = "gas-8-close", kind = "gas", seed = 5, eye = NEAR, look = CLOSE, light = DAY },
  { name = "rings-1-day", kind = "gas", seed = 1, eye = vector.create(0, 1.6, 6.5), look = CENTRE, light = DAY, set = { rings = 1 } },
  { name = "rings-2-side", kind = "gas", seed = 3, eye = vector.create(0, 1.2, 6.5), look = CENTRE, light = SIDE, set = { rings = 1 } },
  { name = "rings-3-under", kind = "gas", seed = 4, eye = vector.create(1.5, -1.4, 6), look = CENTRE, light = DAY, set = { rings = 1 } },
  { name = "rings-4-near", kind = "gas", seed = 5, eye = vector.create(0.6, 0.5, 2.6), look = CENTRE, light = DAY, set = { rings = 1 } },
}
for _, kind in { "moon", "barren", "ice", "icemoon", "lava", "gas" } do
  for _, view in four(kind) do
    table.insert(VIEWS, view)
  end
end
-- A star of each class: from well off, with its whole corona, and near.
for _, class in { "yellow", "orange", "red", "white", "blue" } do
  local kind = `star-{class}`
  table.insert(VIEWS, { name = `{kind}-1-far`, kind = kind, seed = 1, eye = vector.create(0, 0.6, 9), look = CENTRE, light = DAY })
  table.insert(VIEWS, { name = `{kind}-2-near`, kind = kind, seed = 1, eye = FRONT, look = CENTRE, light = DAY })
  table.insert(VIEWS, { name = `{kind}-3-close`, kind = kind, seed = 1, eye = NEAR, look = CLOSE, light = DAY })
end
-- Weapons firing, left to right over 1200 m, a row to each: in flight,
-- and as they land (on a shield, on armour, on the hull, and a miss).
local ROWS = { "laser.pulse.small", "laser.beam.medium", "autocannon.small", "artillery.medium", "blaster.small",
  "railgun.medium", "launcher.light", "miner.small" }
local STRUCK = { "shield", "armor", "hull", "shield", "armor", "hull", "armor", "" }
local IN_FLIGHT = { 0.10, 0.35, 0.22, 0.30, 0.40, 0.12, 1.3, 0.25 }
local LANDING = { 0.16, 0.50, 0.36, 0.56, 0.72, 0.30, 2.15, 0.40 }
local function firing(ages: { number }, outcome: string): { Fire }
  local out: { Fire } = {}
  for row, type in ROWS do
    local how: string = if type == "launcher.light" and outcome ~= "miss" then "launched" else outcome
    local shot: Fire = { type = type, age = ages[row], outcome = how, struck = STRUCK[row], flight = 2.0 }
    table.insert(out, shot)
  end
  return out
end
local STAGE = vector.create(0, 0, 1500)
table.insert(VIEWS, { name = "fx-1-flight", kind = "fx", seed = 1, eye = STAGE, look = CENTRE, light = DAY, radius = 1, fire = firing(IN_FLIGHT, "hit") })
table.insert(VIEWS, { name = "fx-2-landing", kind = "fx", seed = 1, eye = STAGE, look = CENTRE, light = DAY, radius = 1, fire = firing(LANDING, "hit") })
table.insert(VIEWS, { name = "fx-3-landing-close", kind = "fx", seed = 1, eye = vector.create(380, 0, 520), look = vector.create(560, 0, 0),
  light = DAY, radius = 1, fire = firing(LANDING, "hit") })
table.insert(VIEWS, { name = "fx-4-miss", kind = "fx", seed = 1, eye = STAGE, look = CENTRE, light = DAY, radius = 1, fire = firing(LANDING, "miss") })

-- A star as the game draws one from five radii off: 120 km across at
-- 600 km, so that the far side of its corona is past the renderer's
-- reach.
table.insert(VIEWS, { name = "star-red-4-as-in-game", kind = "star-red", seed = 1, eye = vector.create(0, 0.3, 5),
  look = CENTRE, light = DAY, radius = 120000 })

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
  local body: Object? = nil
  local fx: Effects.Fx? = nil
  local built = ""          -- the kind and seed of the world now standing
  local index = 0           -- the view being taken; 0 when idle
  local frames = 0
  local request = readRequest()
  local params: Planet.Tweaks = {}
  local views: { View } = VIEWS

  local function setUp(v: View)
    local tweaks = table.clone(params)
    local key = `{v.kind}:{v.seed}:{v.radius or RADIUS}`
    if v.set then
      for name, value in v.set do
        tweaks[name] = value
        key ..= `:{name}={value}`
      end
    end
    if fx then
      Effects.Clear(fx, false)
      fx = nil
    end
    local fire = v.fire
    if fire then
      -- Fire each row's weapon the right time ago, and play the time
      -- since, so that what has landed has flashed.
      local stage = Effects.New(system)
      local where: { [number]: vector } = {}
      local longest = 0
      for row, shot in fire do
        local y = (#fire / 2 - row + 0.5) * 95
        where[2 * row - 1] = vector.create(-600, y, 0)
        where[2 * row] = vector.create(600, y, 0)
        longest = math.max(longest, shot.age)
      end
      local now = -longest
      while now <= 0 do
        for row, shot in fire do
          if math.abs(now + shot.age) < 0.005 then
            Effects.Fire(stage, shot.type, 2 * row - 1, 2 * row, 20, 20, shot.outcome, shot.flight or 0, shot.struck, now)
          end
        end
        Effects.Update(stage, now, where)
        now += 0.01
      end
      fx = stage
      key = `fx:{v.name}`
    end
    if built ~= key or body == nil then
      if body then
        Object_Delete(body)
      end
      local class = string.match(v.kind, "^star%-(%a+)$")
      local made: Object
      if fire then
        -- (something for the camera to be told to look at)
        made, world = Object_Scenery({}), nil
      elseif class then
        made, world = Star.New(class, v.seed, tweaks), nil
      else
        local planet = Planet.New(v.kind, v.seed, nil, tweaks)
        made, world = planet.body, planet
      end
      local radius = v.radius or RADIUS
      made:SetScale(vector.create(radius, radius, radius))
      system:AddInterior(made)
      camera:SetTarget(made)
      body, built = made, key
    end
    if world then
      -- (judged in white light: the scene's own star is whatever colour
      -- its system rolled)
      local white = params.whiteLight
      Planet.Set(world, "whiteLight", if type(white) == "number" then white else 1)
    end
    if lamp then
      -- (far enough off to be behind the camera whatever the body's size)
      lamp:SetPos(vector.normalize(v.light) * math.max(500000, 20 * (v.radius or RADIUS)))
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
        camera:SetRelativePos(v.eye * (v.radius or RADIUS))
        camera:SetRelativeLookAt(v.look * (v.radius or RADIUS))
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
        -- Nothing to do: wait to be asked, without drawing flat out (it
        -- would take the graphics card from whatever else is running).
        Thread_SleepMS(100)
        frames += 1
        if frames % 3 == 0 then
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
