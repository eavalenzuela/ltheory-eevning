--!strict
-- The tower browser: the towers the generators make for the stations
-- (Game/View/Tower's, built in sections, and Game/View/Hull's
-- GrownTower, grown as a hull is: by way of Game/View/Starbase), one at
-- a time, by seed. (The owner, 2026-11-15, of the first grown towers:
-- "much better, but I'd like to maybe see if we can make a generator
-- for them, so I can pick seeds and styles".) A person runs it in a
-- window (bin/launch towers) and goes through the seeds; script/towers
-- makes a sheet of many of them, off the screen.
--
--   Left, Right    the seed before, the seed after
--   Down, Up       ten seeds back, ten on
--   R              a seed at random
--   S              the next style (Starbase.TOWER_STYLES): the builds
--                  of a tower built in sections (pylon, parasol,
--                  gantry, ring, stack, mixed: the shape it cuts), and
--                  after them the styles of one grown as a hull is
--                  (blocky, cloud, spar, poured, stout, needle, bulb,
--                  fins), which are to go
--   [ and ]        a smaller tower, a bigger one: how much there is of
--                  it (the game's small, middling and large towers are
--                  sizes 2, 4 and 6)
--   of a tower built in sections:
--   N              the next manner (blocky, cloud, spar, poured): how
--                  what it is made of is made. The same tower, made
--                  otherwise
--   F              its fold: how many times a thing is there about its
--                  upright (as the seed says, then 2, 3, 4, 6, 8)
--   W              where its weight is (as the seed says, then low,
--                  high, middle, ends, beads)
--   of a tower grown as a hull is:
--   Q              four sides or eight: whether every plate is there
--                  four times about the tower's upright, or eight
--   M              one more mast out of its top (none after six)
--   P              the next paint: each faction's whose look there is
--   K              keep this one: its line goes in cache/towers-kept.txt
--   Space          stop it turning, or start it
--   right-drag turns it, the wheel moves in and out
--
-- A tower is what its seed, its size and its style make it, with its
-- manner, its fold and its weight (or its sides and its masts),
-- whatever the paint. What is kept is a pick, as
-- Game/View/Starbase's table of each faction's towers has them: a kept
-- line is what goes there.

local AppShell = require("@lt/AppShell")
local Components = require("@lt/Widget/Components")
local Im = require("@lt/Game/UI/Im")
local SceneView = require("@lt/SceneView")
local Starbase = require("@lt/Game/View/Starbase")

-- How big a tower is drawn, whatever it is.
local RADIUS = 1000

-- (the builds first: what is shown to begin with is a tower built in sections)
local STYLES: { string } = {}
for _, style in Starbase.TOWER_STYLES do
  if Starbase.Sectioned(style) then
    table.insert(STYLES, style)
  end
end
for _, style in Starbase.TOWER_STYLES do
  if not Starbase.Sectioned(style) then
    table.insert(STYLES, style)
  end
end
local MANNERS = Starbase.TOWER_MANNERS
local FOLDS = Starbase.TOWER_FOLDS
local PLANS = Starbase.TOWER_PLANS
local SIZES = Starbase.TOWER_SIZES
local PAINTS = Starbase.TOWER_PAINTS
-- The most masts it is shown with.
local MASTS = 6

local KEPT = "cache/towers-kept.txt"

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

  local seed, size, style, paint = 1, 4, 1, 1
  local square, masts = false, 0
  -- (of a tower built in sections: its manner, and its fold and its plan, 0 being as the seed says)
  local manner, fold, plan = 1, 0, 0
  local shown: Object? = nil
  -- (what moves of it: rings that turn, dishes, panels that face the
  -- light, hazard lamps. Each a thing of its own, moved every frame)
  local moving: { Starbase.Moving } = {}
  local clock = 0           -- seconds it has been moving for
  local sunward = vector.create(0, 1, 0)
  local key = ""            -- what is shown
  local took = 0            -- how long it took to make, in milliseconds
  -- (seen from a little above its middle, until it is turned)
  local TURN, TILT, ZOOM = 0.66, 0.16, 1.9
  local turn, tilt = TURN, TILT
  local zoom, zoomTo = ZOOM, ZOOM
  local turning = true
  local plain = false       -- nothing written over the picture (a script's sheet)
  local note = ""           -- what was last kept

  local function sectioned(): boolean
    return Starbase.Sectioned(STYLES[style])
  end

  local function chosen(): Starbase.Pick
    if sectioned() then
      return { seed = seed, size = size, style = STYLES[style], square = false, masts = 0, manner = MANNERS[manner], fold = FOLDS[fold],
        plan = PLANS[plan] }
    end
    return { seed = seed, size = size, style = STYLES[style], square = square, masts = masts }
  end

  -- What is shown, as a line: what is kept, and what a pick is written from.
  local function line(): string
    if sectioned() then
      return `seed {seed}  size {size}  build {STYLES[style]}  manner {MANNERS[manner]}  fold {FOLDS[fold] or "seed's"}  weight {PLANS[plan] or "seed's"}`
    end
    return `seed {seed}  size {size} ({SIZES[size]} plates)  style {STYLES[style]}  {if square then "eight sides" else "four sides"}  masts {masts}`
  end

  local function show()
    local now = `{seed}:{size}:{style}:{square}:{masts}:{manner}:{fold}:{plan}:{paint}`
    if now == key then
      return
    end
    key = now
    local old = shown
    local started = os.clock()
    local made = Starbase.Grown(chosen(), PAINTS[paint])
    took = math.floor((os.clock() - started) * 1000)
    local bound = Renderable_GetBound(made.model)
    -- (the box that holds it and what moves of it, wherever that is turned)
    local lower, upper = made.lower or bound.lower, made.upper or bound.upper
    local across = upper - lower
    -- (it lies along z and is stood up: as tall as fits a picture that
    -- is wider than it is high, and no wider than fits either)
    local scale = RADIUS / math.max(0.92 * across.z / 2, across.x / 2, across.y / 2)
    local object = Object_Scenery({})
    Object_SetRenderable(object, made.model)
    object:SetScale(vector.create(scale, scale, scale))
    -- (its top, which is toward +z as it is grown, upward)
    Object_SetAxes(object, vector.create(0, 1, 0), vector.create(0, 0, -1))
    -- (its middle in the middle: it is grown about its own upright, and
    -- its ends are not the same way off from where it began)
    local middle = vector.create(0, -(lower.z + upper.z) * 0.5 * scale, 0)
    object:SetPos(middle)
    system:AddInterior(object)
    -- (the camera draws the system of what it follows)
    camera:SetTarget(object)
    if old then
      Object_Delete(old)
    end
    for _, piece in moving do
      Object_Delete(piece.object)
    end
    moving = Starbase.Movers(made.movers, function(model: Model): Object
      local piece = Object_Scenery({})
      Object_SetRenderable(piece, model)
      system:AddInterior(piece)
      return piece
    end, middle, vector.create(0, 1, 0), vector.create(0, 0, -1), scale)
    Starbase.Animate(moving, clock, sunward)
    shown = object
  end
  show()

  local function keep()
    local had = ""
    local ok, text = pcall(File_Read, KEPT)
    if ok and type(text) == "string" then
      had = text
    end
    local kept = `{line()}  paint {PAINTS[paint]}`
    File_Write(KEPT, had .. kept .. "\n")
    note = `kept: {kept}  (in {KEPT})`
  end

  _G.Towers = {
    -- Show a tower, still: its seed, its size (1 to 8), its style's
    -- name, whether it has eight sides, how many masts, and its paint's
    -- name (each as it was, if not said); and, of a tower built in
    -- sections, its manner's name, its fold (0: as the seed says) and
    -- where its weight is ("": as the seed says). False if there is no
    -- such size, style, paint, manner, fold or weight.
    Show = function(toSeed: number, toSize: number?, toStyle: string?, eight: boolean?, toMasts: number?, toPaint: string?,
      toManner: string?, toFold: number?, toPlan: string?): boolean
      local how = table.find(STYLES, toStyle or STYLES[style])
      local at = table.find(PAINTS, toPaint or PAINTS[paint])
      local big = toSize or size
      local made = table.find(MANNERS, toManner or MANNERS[manner])
      local times = if toFold == nil then fold elseif toFold == 0 then 0 else table.find(FOLDS, toFold)
      local heavy = if toPlan == nil then plan elseif toPlan == "" then 0 else table.find(PLANS, toPlan)
      if how == nil or at == nil or SIZES[big] == nil or toSeed < 0 or made == nil or times == nil or heavy == nil then
        return false
      end
      seed, size, style, paint = math.floor(toSeed), big, how, at
      manner, fold, plan = made, times, heavy
      if eight ~= nil then
        square = eight
      end
      masts = math.clamp(math.floor(toMasts or masts), 0, MASTS)
      turning, plain = false, true
      turn, tilt, zoom, zoomTo = TURN, TILT, ZOOM, ZOOM
      show()
      return true
    end,
    -- What is shown: its seed, its size, its style, whether it has
    -- eight sides, its masts and its paint; and its manner, its fold
    -- and where its weight is (0 and "": as the seed says).
    Now = function(): (number, number, string, boolean, number, string, string, number, string)
      return seed, size, STYLES[style], square, masts, PAINTS[paint], MANNERS[manner], FOLDS[fold] or 0, PLANS[plan] or ""
    end,
    -- What moves of it, as it is so many seconds on: for a picture of
    -- it at a time. (It goes on from there.)
    At = function(seconds: number)
      clock = seconds
      Starbase.Animate(moving, clock, sunward)
    end,
    -- How many things of it move, and how each does ("spin", "scan",
    -- "track", "blink"), in a row.
    Moving = function(): (number, string)
      local kinds: { string } = {}
      for _, piece in moving do
        table.insert(kinds, piece.motion.kind)
      end
      return #moving, table.concat(kinds, " ")
    end,
    -- Look at it from somewhere else: how far round (in turns of a
    -- circle), how far above (the same, 0.25 being from straight over
    -- it) and from how many of its heights off. It stays still.
    Look = function(round: number, above: number?, off: number?)
      turn, tilt = round * 2 * math.pi, math.clamp((above or 0.03) * 2 * math.pi, -1.5, 1.5)
      zoom = off or ZOOM
      zoomTo = zoom
      turning = false
    end,
  }

  local hud = Components.CaptureScroll(Components.Expand(Widget_Luau(Widget_Create(), {
    PostDraw = function(_, w: Widget)
      if plain then
        return
      end
      Im.Begin()
      local x, y = w.pos.x + 24, w.pos.y + 20
      Im.Text(`SEED {seed}`, x, y, 30, Im.TEXT)
      if sectioned() then
        Im.Text(`size {size} of {#SIZES}      build: {STYLES[style]}      manner: {MANNERS[manner]}      fold: {FOLDS[fold] or "as the seed says"}      weight: {PLANS[plan] or "as the seed says"}      paint: {PAINTS[paint]}      made in {took} ms`,
          x, y + 40, 16, Im.DIM)
      else
        Im.Text(`size {size} of {#SIZES}: {SIZES[size]} plates grown      style: {STYLES[style]} (grown as a hull is)      {if square then "eight sides" else "four sides"}      masts: {masts}      paint: {PAINTS[paint]}      made in {took} ms`,
          x, y + 40, 16, Im.DIM)
      end
      if note ~= "" then
        Im.Text(note, x, y + 66, 14, Im.ACCENT)
      end
      local foot = w.pos.y + w.size.y - 54
      Im.Text("Left / Right: seed      Down / Up: ten seeds      R: random      S: style      [ / ]: size      "
        .. (if sectioned() then "N: manner      F: fold      W: weight" else "Q: four sides or eight      M: masts")
        .. "      P: paint      K: keep      Space: turning", x, foot, 15, Im.DIM)
      Im.Text("right-drag turns it, the wheel moves in and out", x, foot + 22, 15, Im.DIM)
    end,
    PostUpdate = function(_, w: Widget)
      if Key_Pressed(Key_Right()) then seed += 1 end
      if Key_Pressed(Key_Left()) then seed = math.max(0, seed - 1) end
      if Key_Pressed(Key_Up()) then seed += 10 end
      if Key_Pressed(Key_Down()) then seed = math.max(0, seed - 10) end
      if Key_Pressed(Key_R()) then seed = Int_Random(0, 99999) end
      if Key_Pressed(Key_RBracket()) then size = math.min(#SIZES, size + 1) end
      if Key_Pressed(Key_LBracket()) then size = math.max(1, size - 1) end
      if Key_Pressed(Key_S()) then style = style % #STYLES + 1 end
      if sectioned() then
        if Key_Pressed(Key_N()) then manner = manner % #MANNERS + 1 end
        if Key_Pressed(Key_F()) then fold = (fold + 1) % (#FOLDS + 1) end
        if Key_Pressed(Key_W()) then plan = (plan + 1) % (#PLANS + 1) end
      else
        if Key_Pressed(Key_Q()) then square = not square end
        if Key_Pressed(Key_M()) then masts = (masts + 1) % (MASTS + 1) end
      end
      if Key_Pressed(Key_P()) then paint = paint % #PAINTS + 1 end
      if Key_Pressed(Key_Space()) then turning = not turning end
      if Key_Pressed(Key_K()) then keep() end
      show()

      local dt = FrameTimer_Get()
      if w.focusScroll then
        zoomTo = math.clamp(zoomTo * (1 - 0.1 * Mouse_GetScrollDelta()), 1.2, 12)
      end
      if Mouse_RightDown() then
        local delta = Cursor_GetDelta()
        turn -= 0.01 * delta.x
        tilt = math.clamp(tilt + 0.01 * delta.y, -1.5, 1.5)
      elseif turning then
        turn += 0.25 * dt
      end
      zoom += (zoomTo - zoom) * (1 - math.exp(-dt / 0.1))
      local eye = vector.create(math.cos(tilt) * math.sin(turn), math.sin(tilt), math.cos(tilt) * math.cos(turn)) * (zoom * RADIUS)
      camera:SetRelativePos(eye)
      camera:SetRelativeLookAt(vector.create(0, 0, 0))
      camera:SetRigidity(60)
      local light = lamp
      if light then
        -- (the light over the camera's shoulder, as it must be: the
        -- engine's star in view whites the picture out)
        Star_SetColor(light, vector.create(1.15, 1.15, 1.15))
        local side = vector.normalize(vector.cross(vector.create(0, 1, 0), eye))
        sunward = vector.normalize(eye + side * (0.5 * vector.magnitude(eye)) + vector.create(0, 0.7 * vector.magnitude(eye), 0))
        light:SetPos(sunward * 500000)
      end
      -- (what moves of it, moved: its panels face the light, which is over the camera's shoulder)
      clock += dt
      Starbase.Animate(moving, clock, sunward)
    end,
  })))

  return Widget_Stack(Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return { view, Widget_Layer(Compositor_None(), Mesh_Quad(), 1, hud) }
    end,
    PreUpdate = function()
      system:Update(FrameTimer_Get())
    end,
  }))
end)
