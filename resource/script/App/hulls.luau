--!strict
-- The hull browser: the hulls the engine's first generator makes
-- (Item/ShipType/Generate), one at a time, by seed. A person runs it in
-- a window (bin/launch hulls) and goes through the seeds; script/hulls
-- makes a sheet of many of them, off the screen.
--
--   Left, Right    the seed before, the seed after
--   Down, Up       ten seeds back, ten on
--   R              a seed at random
--   B              broad hulls only, or all of them: most of what the
--                  generator grows is long and thin, and with this on
--                  the seeds stepped to are those at least a third as
--                  wide as they are long
--   [ and ]        a smaller hull, a bigger one (the generator's "scale":
--                  how many plates it grows, and whether it has decks)
--   P              the next paint: bare, as the engine made them, then
--                  each of the game's
--   F              as a ship: a frigate's guns and engines on it, then a
--                  destroyer's, a cruiser's, a battleship's, then none.
--                  The engines go on the ends the hull has astern and
--                  the guns where the game's rule of hardpoints lets
--                  them (Hull.GrownShip); it says so if there is no room
--   K              keep this one: its line goes in cache/hulls-kept.txt
--   Space          stop it turning, or start it
--   right-drag turns it, the wheel moves in and out
--
-- A hull is what its seed and its size make it, whatever the paint: the
-- bare one is the generator's own model, and the painted one is the
-- same draws through Game/View/Hull (Hull.Grown).

local AppShell = require("@lt/AppShell")
local Arms = require("@lt/Game/View/Arms")
local Components = require("@lt/Widget/Components")
local Effects = require("@lt/Game/View/Effects")
local Generate = require("@lt/Item/ShipType/Generate")
local Hull = require("@lt/Game/View/Hull")
local Im = require("@lt/Game/UI/Im")
local SceneView = require("@lt/SceneView")

-- How big a hull is drawn, whatever it is.
local RADIUS = 1000

-- The sizes: the generator's own measure of a hull (the root of its
-- mass, more or less). It grows two plates and the root of this more,
-- and from ten up lays a broad deck under every plate. (It made a
-- frigate at about 5, and the biggest hull a pilot flew at about 18.)
local SIZES = { 1, 4, 9, 12, 16, 25, 36, 49 }

local PAINTS = { "bare", "civil", "vessari", "talmar", "kethri", "vail", "unbound" }

-- What a hull is shown as when it is shown as a ship: how big such a
-- ship is, what stands on its hardpoints and how many engines it has.
-- (The game's own sizes for the four classes of warship.)
type Class = { name: string, metres: number, turret: string, turrets: number, launcher: string, launchers: number, engines: number }
local CLASSES: { Class } = {
  { name = "frigate", metres = 42, turret = "autocannon.small", turrets = 2, launcher = "launcher.light", launchers = 1, engines = 2 },
  { name = "destroyer", metres = 75, turret = "autocannon.small", turrets = 5, launcher = "launcher.light", launchers = 1, engines = 2 },
  { name = "cruiser", metres = 150, turret = "artillery.medium", turrets = 4, launcher = "launcher.heavy", launchers = 1, engines = 3 },
  { name = "battleship", metres = 400, turret = "laser.beam.large", turrets = 6, launcher = "launcher.cruise", launchers = 2, engines = 4 },
}

local KEPT = "cache/hulls-kept.txt"

-- A hull is broad if it is at least this much as wide as it is long.
local BROAD = 1 / 3

local function stepsOf(size: number): number
  return 2 + math.floor(math.sqrt(SIZES[size]))
end

local function decksOf(size: number): boolean
  return SIZES[size] >= 10
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

  local seed, size, paint = 1, 2, 1
  local class = 0           -- which of CLASSES it is shown as; 0, as a bare hull
  local fitted = ""         -- how that went: what is on it, or why it is not
  local extras: { Object } = {}   -- what stands on it
  local fx: Effects.Fx? = nil     -- its engines' fire
  local shown: Object? = nil
  local key = ""            -- what is shown: its seed, size and paint
  local took = 0            -- how long it took to make, in milliseconds
  -- (seen from off the bow, a little above, until it is turned)
  local TURN, TILT, ZOOM = 0.66, 0.31, 1.9
  local turn, tilt = TURN, TILT
  local zoom, zoomTo = ZOOM, ZOOM
  local turning = true
  local plain = false       -- nothing written over the picture (a script's sheet)
  local broad = false       -- only broad hulls are stepped to
  local note = ""           -- what was last kept
  local models: { [string]: Renderable | Model } = {}

  local ships: { [string]: Hull.Built } = {}

  -- The hull as a ship of a class, or nothing and why. (Painted: a bare
  -- hull is the generator's own model, which has no engines.)
  local function ship(as: Class): (Hull.Built?, string)
    local name = `{seed}:{size}:{paint}:{as.name}`
    local had = ships[name]
    if had then
      return had, ""
    end
    local fit: { string } = {}
    for _ = 1, as.turrets do
      table.insert(fit, as.turret)
    end
    for _ = 1, as.launchers do
      table.insert(fit, as.launcher)
    end
    local built, why = Hull.GrownShip(seed, stepsOf(size), decksOf(size), if PAINTS[paint] == "bare" then "civil" else PAINTS[paint],
      as.metres, fit, as.turrets, as.launchers, as.engines)
    if built then
      ships[name] = built
    end
    return built, why
  end

  local function make(): Renderable | Model
    if PAINTS[paint] == "bare" then
      return Generate.Main(SIZES[size], seed)
    end
    return Hull.Grown(seed, stepsOf(size), decksOf(size), PAINTS[paint]).model
  end

  local function show()
    local now = `{seed}:{size}:{paint}:{class}`
    if now == key then
      return
    end
    key = now
    local old = shown
    for _, object in extras do
      Object_Delete(object)
    end
    table.clear(extras)
    local burning = fx
    if burning then
      Effects.Clear(burning, false)
      fx = nil
    end
    local started = os.clock()
    local as: Class? = CLASSES[class]
    local built: Hull.Built? = nil
    fitted = ""
    if as then
      local why: string
      built, why = ship(as)
      fitted = if built then `as a {as.name} of {as.metres} m: {as.turrets} turrets, {as.launchers} launchers, {#built.engines} engines`
        else `as a {as.name}: no room ({why})`
    end
    local plain = `{seed}:{size}:{paint}`
    local model: Renderable | Model = if built then built.model else models[plain] or make()
    if built == nil then
      models[plain] = model
    end
    took = math.floor((os.clock() - started) * 1000)
    local bound = Renderable_GetBound(model)
    local across = bound.upper - bound.lower
    local scale = RADIUS / (math.max(across.x, across.y, across.z) / 2)
    -- (its middle in the middle, wherever its own origin is)
    local shift = (bound.lower + bound.upper) * (-0.5 * scale)
    local object = Object_Scenery({})
    Object_SetRenderable(object, model)
    object:SetScale(vector.create(scale, scale, scale))
    object:SetPos(shift)
    system:AddInterior(object)
    -- (the camera draws the system of what it follows)
    camera:SetTarget(object)
    if old then
      Object_Delete(old)
    end
    shown = object
    if built and as then
      -- what it carries, on both mounts of each hardpoint, slewed a
      -- little to show that it turns; and its engines burning
      local metres = RADIUS / as.metres
      local at = 0
      for _, points in { built.turrets, built.launchers } do
        for index, point in points do
          at += 1
          local piece = Arms.Build(built.fit[at])
          for _, mount in point do
            if piece then
              local rest = mount.fore or vector.create(0, 0, 1)
              local side = vector.cross(mount.up, rest)
              local aim = vector.normalize(rest + side * (if index % 2 == 0 then -0.7 else 0.7) + mount.up * 0.35)
              local base: Object? = nil
              if piece.base then
                local made = Object_Scenery({})
                Object_SetRenderable(made, piece.base)
                system:AddInterior(made)
                table.insert(extras, made)
                base = made
              end
              local gun = Object_Scenery({})
              Object_SetRenderable(gun, piece.gun)
              system:AddInterior(gun)
              table.insert(extras, gun)
              Arms.Place(piece, base, gun, mount.at * scale + shift, mount.up, rest, aim, metres)
            end
          end
        end
      end
      local effects = Effects.New(system)
      local color = vector.create(built.glow[1], built.glow[2], built.glow[3])
      for index, engine in built.engines do
        Effects.Thrust(effects, index, engine.at * scale + shift, vector.create(0, 0, -1), engine.radius * scale, 0.75, color, 0)
      end
      Effects.Update(effects, 0, {})
      fx = effects
    end
  end
  show()

  -- How wide a seed's hull is for its length, at the size shown.
  local function beam(of: number, big: number): number
    local across = Hull.GrownShape(of, stepsOf(big), decksOf(big))
    return across.x / across.z
  end

  -- The seed 'by' on from this one (or back): with only broad hulls
  -- wanted, the next that is one (it gives up after a thousand).
  local function step(by: number)
    local to = math.max(0, seed + by)
    if broad then
      local way = if by < 0 then -1 else 1
      local tried = 0
      while beam(to, size) < BROAD and tried < 1000 and to + way >= 0 do
        to += way
        tried += 1
      end
      if beam(to, size) < BROAD then
        return
      end
    end
    seed = to
  end

  local function keep()
    local had = ""
    local ok, text = pcall(File_Read, KEPT)
    if ok and type(text) == "string" then
      had = text
    end
    local as: Class? = CLASSES[class]
    local line = `seed {seed}  size {size}  ({stepsOf(size)} plates{if decksOf(size) then ", decks" else ""})  paint {PAINTS[paint]}`
    if as then
      line ..= `  {fitted}`
    end
    File_Write(KEPT, had .. line .. "\n")
    note = `kept: {line}  (in {KEPT})`
  end

  _G.Hulls = {
    -- Show a hull, still, from the bow quarter: its seed, its size (1 to
    -- 8), its paint's name and, to show it as a ship, the name of a
    -- class. False if there is no such size, paint or class.
    Show = function(toSeed: number, toSize: number?, toPaint: string?, toClass: string?): boolean
      local at = table.find(PAINTS, toPaint or PAINTS[paint])
      local big = toSize or size
      local as = 0
      for index, known in CLASSES do
        if known.name == toClass then
          as = index
        end
      end
      if at == nil or SIZES[big] == nil or toSeed < 0 or (toClass ~= nil and as == 0) then
        return false
      end
      seed, size, paint, class = math.floor(toSeed), big, at, as
      turning, plain = false, true
      turn, tilt, zoom, zoomTo = TURN, TILT, ZOOM, ZOOM
      show()
      return true
    end,
    -- What is shown: its seed, its size, its paint, how many plates
    -- the generator grew for it, and how wide it is for its length.
    Now = function(): (number, number, string, number, number)
      return seed, size, PAINTS[paint], stepsOf(size), beam(seed, size)
    end,
    -- Look at it from somewhere else: how far round from the bow (in
    -- turns of a circle: 0.5 is from astern), how far above (the same,
    -- 0.25 being from straight over it) and from how many of its
    -- lengths off. It stays still.
    Look = function(round: number, above: number?, off: number?)
      turn, tilt = round * 2 * math.pi, math.clamp((above or 0.05) * 2 * math.pi, -1.5, 1.5)
      zoom = off or ZOOM
      zoomTo = zoom
      turning = false
    end,
    -- How the hull shown does as a ship: the class it is shown as (""
    -- for none), whether it has the room for that class's hardpoints,
    -- and how many engines it was given.
    Fitted = function(): (string, boolean, number)
      local as: Class? = CLASSES[class]
      if as == nil then
        return "", false, 0
      end
      local built = ship(as)
      return as.name, built ~= nil, if built then #built.engines else 0
    end,
    -- The first 'count' seeds from 'from' on whose hulls are broad at a
    -- size, with commas between (of the next 'count' times forty).
    Broad = function(from: number, count: number, big: number): string
      local found: { string } = {}
      local at = math.max(0, math.floor(from))
      local last = at + 40 * count
      while #found < count and at < last and SIZES[big] ~= nil do
        if beam(at, big) >= BROAD then
          table.insert(found, tostring(at))
        end
        at += 1
      end
      return table.concat(found, ",")
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
      local decks = if decksOf(size) then ", decks under" else ""
      local only = if broad then "      broad hulls only" else ""
      Im.Text(`size {size} of {#SIZES}: {stepsOf(size)} plates grown{decks}      paint: {PAINTS[paint]}{only}      made in {took} ms`, x, y + 40,
        16, Im.DIM)
      if fitted ~= "" then
        Im.Text(fitted, x, y + 64, 16, if string.find(fitted, "no room", 1, true) then Im.WARN else Im.TEXT)
      end
      if note ~= "" then
        Im.Text(note, x, y + 90, 14, Im.ACCENT)
      end
      local foot = w.pos.y + w.size.y - 54
      Im.Text("Left / Right: seed      Down / Up: ten seeds      R: random      B: broad only      [ / ]: size      P: paint      F: as a ship      K: keep      Space: turn",
        x, foot, 15, Im.DIM)
      Im.Text("right-drag turns it, the wheel moves in and out", x, foot + 22, 15, Im.DIM)
    end,
    PostUpdate = function(_, w: Widget)
      if Key_Pressed(Key_B()) then
        broad = not broad
        step(0)
      end
      if Key_Pressed(Key_Right()) then step(1) end
      if Key_Pressed(Key_Left()) then step(-1) end
      if Key_Pressed(Key_Up()) then step(10) end
      if Key_Pressed(Key_Down()) then step(-10) end
      if Key_Pressed(Key_R()) then
        seed = Int_Random(0, 99999)
        step(0)
      end
      if Key_Pressed(Key_RBracket()) then size = math.min(#SIZES, size + 1) end
      if Key_Pressed(Key_LBracket()) then size = math.max(1, size - 1) end
      if Key_Pressed(Key_P()) then paint = paint % #PAINTS + 1 end
      if Key_Pressed(Key_F()) then class = (class + 1) % (#CLASSES + 1) end
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
        -- engine's star in view whites the picture out; and less of it
        -- on bare metal, which burns out in what paint is judged by)
        local bright = if PAINTS[paint] == "bare" then 0.5 else 1.15
        Star_SetColor(light, vector.create(bright, bright, bright))
        local side = vector.normalize(vector.cross(vector.create(0, 1, 0), eye))
        light:SetPos(vector.normalize(eye + side * (0.5 * vector.magnitude(eye)) + vector.create(0, 0.7 * vector.magnitude(eye), 0)) * 500000)
      end
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
