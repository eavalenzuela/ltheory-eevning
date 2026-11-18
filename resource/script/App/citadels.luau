--!strict
-- The citadel browser: the citadels Game/View/Citadel grows, one at a
-- time, by seed (the owner, 2026-11-17: "build the interactive generator
-- for citadels"). A person runs it in a window (bin/launch citadels) and
-- goes through the seeds to pick one for each size; script/citadels
-- makes a sheet of many of them, off the screen.
--
--   Left, Right    the seed before, the seed after
--   Down, Up       ten seeds back, ten on
--   R              a seed at random
--   [ and ]        a smaller citadel, a bigger one: the five sizes,
--                  small to huge (Data/Structures' CITADEL_SIZES)
--   A              its sides alike, or not (grown asymmetrical: nothing
--                  of it is the twin of anything)
--   P              the next paint: the citadels' own very dark grey,
--                  then the game's others (Hull.looks)
--   L              the next look: the game's standard, Cel V1, Cel V2
--                  (the game's Options, Graphics, Look)
--   1 to 5         surface detail, each kind on or off (Hull.DETAILS):
--                  antennas, pipes, greebles, lights, rivets
--   , and .        the seed of the kind last switched, back and on: it
--                  is laid out afresh and the others stay (kept as
--                  "antennas:17")
--   G              the citadel the game draws at this size now
--                  (Citadel.PICKS)
--   the search box (top right; click it, type, Return): a seed, to go
--                  to it; or a size's name (small, medium, large,
--                  extralarge, huge), to go to what the game draws at it
--   K              keep this one: its line goes in cache/citadels-kept.txt,
--                  as a pick for its size
--   Space          stop it turning, or start it
--   right-drag turns it, the wheel moves in and out

local AppShell = require("@lt/AppShell")
local Citadel = require("@lt/Game/View/Citadel")
local Components = require("@lt/Widget/Components")
local Hull = require("@lt/Game/View/Hull")
local Im = require("@lt/Game/UI/Im")
local SceneView = require("@lt/SceneView")
local Structures = require("@lt/Core/Data/Structures")

-- How big a citadel is drawn, whatever it is.
local RADIUS = 1000

local SIZES = Structures.CITADEL_SIZES

-- The paints: "dark" is the citadels' own (Citadel.LOOK), and the rest
-- are Hull.looks by name.
local PAINTS = { "dark", "civil", "bare", "vessari", "talmar", "orun", "kethri", "vail", "unbound" }

-- The game's looks (Game/View/Graphics): its render passes as each has them.
local LOOKS = {
  { name = "standard", smooth = true, flat = false },
  { name = "Cel V1", smooth = false, flat = false },
  { name = "Cel V2", smooth = false, flat = true },
}

local KEPT = "cache/citadels-kept.txt"

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

  local seed, size, paint, look = 1, 1, 1, 1
  local asym = false
  local lookShown = 0       -- the look the render passes were last set to
  local shown: Object? = nil
  local key = ""            -- what is shown
  local took = 0            -- how long it took to make, in milliseconds
  local mouths = 0          -- how many hangar mouths it has
  local across = 0          -- how wide it is for how high it is
  local TURN, TILT, ZOOM = 0.66, 0.31, 2.1
  local turn, tilt = TURN, TILT
  local zoom, zoomTo = ZOOM, ZOOM
  local turning = true
  local plain = false       -- nothing written over the picture (a script's sheet)
  local note = ""
  local query = ""
  -- Which kinds of surface detail are on, and each kind's own seed (0:
  -- the citadel's own), and the kind the comma and period keys throw
  -- again. (All of them on to begin with, as the game draws citadels.)
  local detail: { [string]: boolean } = {}
  for _, kind in Hull.DETAILS do
    detail[kind] = true
  end
  local detailSeeds: { [string]: number } = {}
  local chosen = Hull.DETAILS[1]
  local function detailWords(): string
    local words: { string } = {}
    for _, kind in Hull.DETAILS do
      if detail[kind] then
        local own = detailSeeds[kind] or 0
        table.insert(words, if own ~= 0 then `{kind}:{own}` else kind)
      end
    end
    return table.concat(words, " ")
  end
  local function setDetail(words: { string })
    table.clear(detail)
    table.clear(detailSeeds)
    for _, word in words do
      local named, own = string.match(word, "^(%a+):(%d+)$")
      local kind: string = named or word
      if table.find(Hull.DETAILS, kind) then
        detail[kind] = true
        detailSeeds[kind] = tonumber(own or "0") or 0
      end
    end
  end

  -- The citadel the game draws at the size shown.
  local function picked()
    local pick = Citadel.PICKS[size]
    if pick then
      seed, asym = pick.seed, pick.asym
      setDetail(string.split(pick.detail, " "))
      paint = 1
      note = `what the game draws at {SIZES[size]}: seed {pick.seed}{if pick.asym then ", asymmetrical" else ""}, {pick.detail}`
    end
  end

  local function show()
    if look ~= lookShown then
      lookShown = look
      RenderPass_SetEnabled("Smooth Shading", LOOKS[look].smooth)
      RenderPass_SetEnabled("Flat Paint", LOOKS[look].flat)
    end
    local now = `{seed}:{size}:{paint}:{asym}:{detailWords()}`
    if now == key then
      return
    end
    key = now
    local started = os.clock()
    local made = Citadel.Build(seed, size, if PAINTS[paint] == "dark" then nil else PAINTS[paint], detailWords(), nil, asym)
    took = math.floor((os.clock() - started) * 1000)
    local _, holes = Citadel.Grow(seed, size, asym)
    mouths = #holes
    local box = made.upper - made.lower
    across = math.max(box.x, box.z) / math.max(1e-6, box.y)
    -- (as big as fits: its widest, corner to corner)
    local scale = RADIUS / math.max(math.max(box.x, box.y, box.z) / 2, 0.4 * vector.magnitude(box))
    local object = Object_Scenery({})
    Object_SetRenderable(object, made.model)
    object:SetScale(vector.create(scale, scale, scale))
    object:SetPos((made.lower + made.upper) * (-0.5 * scale))
    system:AddInterior(object)
    camera:SetTarget(object)
    local old = shown
    if old then
      Object_Delete(old)
    end
    shown = object
  end
  show()

  local function keep()
    local had = ""
    local ok, text = pcall(File_Read, KEPT)
    if ok and type(text) == "string" then
      had = text
    end
    local words = detailWords()
    local line = `{SIZES[size]}  seed {seed}{if asym then "  asym" else ""}  paint {PAINTS[paint]}`
      .. (if words ~= "" then `  detail {words}` else "")
    File_Write(KEPT, had .. line .. "\n")
    note = `kept: {line}  (in {KEPT})`
  end

  local function search(words: string)
    local text = string.lower(string.match(words, "^%s*(.-)%s*$") or "")
    if text == "" then
      return
    end
    local number = tonumber(text)
    if number then
      seed = math.max(0, math.floor(number))
      note = `seed {seed}`
      return
    end
    -- (a size's name, or the start of one: what the game draws at it)
    for index, name in SIZES do
      if string.sub(name, 1, #text) == text or (text == "xl" and name == "extralarge") then
        size = index
        picked()
        return
      end
    end
    note = `'{text}' is not a seed or a size ({table.concat(SIZES, ", ")})`
  end

  _G.Citadels = {
    -- Show a citadel, still: its seed, its size (1 to 5), whether it is
    -- asymmetrical, its paint's name ("dark", the citadels' own, if not
    -- said), its surface detail as words (all of it, if not said), and
    -- the look ("standard", "Cel V1", "Cel V2"). False if there is no
    -- such size, paint or look.
    Show = function(toSeed: number, toSize: number, toAsym: boolean?, toPaint: string?, toDetail: string?, toLook: string?): boolean
      local at = table.find(PAINTS, toPaint or "dark")
      local how = 1
      for index, known in LOOKS do
        if known.name == toLook then
          how = index
        end
      end
      if at == nil or SIZES[toSize] == nil or toSeed < 0 or (toLook ~= nil and LOOKS[how].name ~= toLook) then
        return false
      end
      seed, size, asym, paint, look = math.floor(toSeed), toSize, toAsym == true, at, how
      setDetail(string.split(toDetail or table.concat(Hull.DETAILS, " "), " "))
      turning, plain = false, true
      turn, tilt, zoom, zoomTo = TURN, TILT, ZOOM, ZOOM
      show()
      return true
    end,
    -- Go to what the search box would: a seed, or a size by name. What it says of it.
    Find = function(words: string): string
      search(words)
      show()
      return note
    end,
    -- Keep what is shown, as K does. The line kept.
    Keep = function(): string
      keep()
      return note
    end,
    -- What is shown: its seed, its size, whether it is asymmetrical, its
    -- paint, its detail as words, and how many hangar mouths it has.
    Now = function(): (number, number, boolean, string, string, number)
      return seed, size, asym, PAINTS[paint], detailWords(), mouths
    end,
    -- Look at it from somewhere else (as the hull browser's Look): how
    -- far round, how far above and from how far off. It stays still.
    Look = function(round: number, above: number?, off: number?)
      turn, tilt = round * 2 * math.pi, math.clamp((above or 0.05) * 2 * math.pi, -1.5, 1.5)
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
      local reach = Structures.CITADEL_REACH[size]
      local field = if reach >= 1000 then `{reach // 1000} km` else `{reach} m`
      local pick = Citadel.PICKS[size]
      local isPick = pick and pick.seed == seed and pick.asym == asym
      Im.Text(`size {size} of {#SIZES}: {SIZES[size]}, a field of {field}      {if asym then "asymmetrical" else "sides alike"}      paint: {PAINTS[paint]}      look: {LOOKS[look].name}      {mouths} hangar {if mouths == 1 then "mouth" else "mouths"}      {string.format("%.1f", across)} times as wide as high      made in {took} ms`,
        x, y + 40, 16, Im.DIM)
      if isPick then
        Im.Text(`the game draws a {SIZES[size]} citadel from this seed`, x, y + 64, 16, Im.ACCENT)
      end
      local on: { string } = {}
      for index, kind in Hull.DETAILS do
        local own = detailSeeds[kind] or 0
        table.insert(on, `{if kind == chosen then ">" else ""}{index} {kind}: {if detail[kind] then "ON" else "off"}{if own ~= 0 then ` #{own}` else ""}`)
      end
      Im.Text("detail      " .. table.concat(on, "      "), x, y + 90, 16, if detailWords() ~= "" then Im.ACCENT else Im.DIM)
      if note ~= "" then
        Im.Text(note, x, y + 116, 14, Im.ACCENT)
      end
      local wide = 320
      local was = Im.Typing()
      query = Im.Words("citadels:search", query, w.pos.x + w.size.x - wide - 24, y, wide, 32, 40, "seed, or a size: Return")
      if was and not Im.Typing() and Key_Pressed(Key_Return()) then
        search(query)
      end
      local foot = w.pos.y + w.size.y - 54
      Im.Text("Left / Right: seed      Down / Up: ten seeds      R: random      [ / ]: size      A: asymmetrical      P: paint      L: look      1-5: detail      , .: its seed      G: the game's pick      K: keep      Space: turn",
        x, foot, 15, Im.DIM)
      Im.Text("right-drag turns it, the wheel moves in and out", x, foot + 22, 15, Im.DIM)
    end,
    PostUpdate = function(_, w: Widget)
      if Im.Typing() then
        show()
        return
      end
      for index, key in { Key_N1(), Key_N2(), Key_N3(), Key_N4(), Key_N5() } do
        if Key_Pressed(key) then
          local kind = Hull.DETAILS[index]
          detail[kind] = not detail[kind]
          chosen = kind
        end
      end
      local by = if Key_Pressed(Key_Period()) then 1 elseif Key_Pressed(Key_Comma()) then -1 else 0
      if by ~= 0 and chosen ~= "rivets" then
        detail[chosen] = true
        detailSeeds[chosen] = math.max(0, (detailSeeds[chosen] or 0) + by)
      end
      if Key_Pressed(Key_Right()) then seed += 1 end
      if Key_Pressed(Key_Left()) then seed = math.max(0, seed - 1) end
      if Key_Pressed(Key_Up()) then seed += 10 end
      if Key_Pressed(Key_Down()) then seed = math.max(0, seed - 10) end
      if Key_Pressed(Key_R()) then seed = Int_Random(0, 99999) end
      if Key_Pressed(Key_RBracket()) then size = math.min(#SIZES, size + 1) end
      if Key_Pressed(Key_LBracket()) then size = math.max(1, size - 1) end
      if Key_Pressed(Key_A()) then asym = not asym end
      if Key_Pressed(Key_P()) then paint = paint % #PAINTS + 1 end
      if Key_Pressed(Key_L()) then look = look % #LOOKS + 1 end
      if Key_Pressed(Key_G()) then picked() end
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
        turn += 0.2 * dt
      end
      zoom += (zoomTo - zoom) * (1 - math.exp(-dt / 0.1))
      local eye = vector.create(math.cos(tilt) * math.sin(turn), math.sin(tilt), math.cos(tilt) * math.cos(turn)) * (zoom * RADIUS)
      camera:SetRelativePos(eye)
      camera:SetRelativeLookAt(vector.create(0, 0, 0))
      camera:SetRigidity(60)
      local light = lamp
      if light then
        -- (the light over the camera's shoulder, as in the hull browser)
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
