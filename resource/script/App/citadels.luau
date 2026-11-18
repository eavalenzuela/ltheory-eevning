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
--   T              the next style: blocks, pyramid, diamond, wormhole
--                  (Citadel.STYLES)
--   P              the next paint: the citadels' own very dark grey,
--                  then the game's others (Hull.looks)
--   L              the next look: the game's standard, Cel V1, Cel V2
--                  (the game's Options, Graphics, Look)
--   1 to 5         surface detail, each kind on or off (Hull.DETAILS):
--                  antennas, pipes, greebles, lights, rivets
--   , and .        the seed of the kind last switched, back and on: it
--                  is laid out afresh and the others stay (kept as
--                  "antennas:17")
--   C              the next kind of citadel: habitation, trade hub,
--                  refinery, research station, shipyard, generator (what
--                  G goes to, and what K keeps it as; Citadel.KINDS)
--   V              whose: the standard citadels (the human peoples' and
--                  pilots'), or an alien people's, Vail or Nimia
--                  (Citadel.PEOPLES; what is theirs to pick: Citadel.SLOTS)
--   G              the citadel the game draws of this kind at this size
--                  now (Citadel.Pick), in its paint
--   the search box (top right; click it, type, Return): a seed, to go
--                  to it; or a size's name (small, medium, large,
--                  extralarge, huge), to go to what the game draws at it
--   F              what its defence module is: none, cannon, laser,
--                  hybrid, missile, round (the weapons it mounts on the
--                  weapon hardpoints; the point defence is always there)
--   W              a generator citadel's generator: making gravity (a
--                  black sphere), making a wormhole (a deep purple one),
--                  or not running (no sphere, its rings still), round
--   O              its kind's module (observatory, mining turret) offline:
--                  there, but dark and still
--   D              its hulk: as it lies when it has been brought down,
--                  the citadels' own dark grey, every light out, nothing
--                  turning (Core/Assets/Hulks; Citadel.Hulk)
--   H              the most hangar doors it has: 4, 2 or 1, round
--                  (Citadel.DOOR_CAPS)
--   K              keep this one: its line goes in cache/citadels-kept.txt,
--                  as a pick for its size
--   Space          stop it turning, or start it
--   right-drag turns it, the wheel moves in and out

local AppShell = require("@lt/AppShell")
local Arms = require("@lt/Game/View/Arms")
local Citadel = require("@lt/Game/View/Citadel")
local Components = require("@lt/Widget/Components")
local Hull = require("@lt/Game/View/Hull")
local Im = require("@lt/Game/UI/Im")
local SceneView = require("@lt/SceneView")
local Starbase = require("@lt/Game/View/Starbase")
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

  local seed, size, paint, look, style = 1, 1, 1, 1, 1
  local KINDS = Citadel.KINDS
  local role = 1            -- which of the kinds of citadel (KINDS) it is for
  local PEOPLES = Citadel.PEOPLES
  local folk = 1            -- whose citadel it is for (PEOPLES)
  local GENERATORS = { "gravity", "wormhole", "off" }
  local making = 1          -- what its generator makes (GENERATORS)
  local asym = false
  local doorCap = 1         -- which of Citadel.DOOR_CAPS: the most doors it has
  local FAMILIES = { "none", "cannon", "laser", "hybrid", "missile" }
  local family = 1          -- which of FAMILIES its defence module is
  local offline = false     -- its kind's module is offline
  local derelict = false    -- shown as its hulk
  local armed: { Object } = {}   -- the weapons on its hardpoints
  local mountsShown, armedShown = 0, 0
  local STYLES = Citadel.STYLES
  local moving: { Starbase.Moving } = {}   -- what of it turns
  local clock = 0
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

  -- The kind of citadel it is drawn as (a generator citadel is a gravity
  -- or a wormhole station, by what its generator makes), whether its
  -- generator is still, and what it is, in words.
  local function drawnAs(): (string, boolean)
    if KINDS[role] == "generator" then
      return if making == 2 then "wormhole" else "gravity", making == 3
    end
    return KINDS[role], making == 3
  end
  local function slotName(): string
    local people = PEOPLES[folk]
    return `{if people == "standard" then "" else string.upper(string.sub(people, 1, 1)) .. string.sub(people, 2) .. " "}{SIZES[size]} {Citadel.KIND_NAMES[KINDS[role]]}`
  end

  -- The citadel the game draws of the kind and at the size shown.
  local function picked()
    local pick = Citadel.Pick(KINDS[role], size, PEOPLES[folk])
    seed, asym = pick.seed, pick.asym
    doorCap = table.find(Citadel.DOOR_CAPS, pick.doors or Citadel.DOORS) or 1
    style = table.find(STYLES, pick.style) or 1
    setDetail(string.split(pick.detail, " "))
    paint = table.find(PAINTS, pick.paint) or 1
    note = `{if Citadel.HasSlot(PEOPLES[folk], KINDS[role], size) then "" else "(there is no such citadel: the nearest) "}`
      .. `what the game draws of a {slotName()}{if pick.stand then " (a stand-in, not picked yet)" else ""}: seed {pick.seed}, {pick.style}`
      .. `{if pick.asym then ", asymmetrical" else ""}, {pick.paint}, {pick.detail}`
  end

  local function show()
    if look ~= lookShown then
      lookShown = look
      RenderPass_SetEnabled("Smooth Shading", LOOKS[look].smooth)
      RenderPass_SetEnabled("Flat Paint", LOOKS[look].flat)
    end
    local now = `{seed}:{size}:{paint}:{asym}:{style}:{detailWords()}:{doorCap}:{family}:{role}:{making}:{offline}:{derelict}`
    if now == key then
      return
    end
    key = now
    local started = os.clock()
    local kind, idle = drawnAs()
    local words = detailWords()
    if derelict then
      -- (a hulk: no paint but the citadels' own, no lights, nothing running)
      local kept: { string } = {}
      for _, word in string.split(words, " ") do
        if word ~= "" and string.sub(word, 1, 6) ~= "lights" then
          table.insert(kept, word)
        end
      end
      words = table.concat(kept, " ")
    end
    local made = Citadel.Build(seed, size, if derelict or PAINTS[paint] == "dark" then nil else PAINTS[paint], words, nil, asym,
      STYLES[style], Citadel.DOOR_CAPS[doorCap], kind, idle or derelict, offline or derelict, derelict)
    took = math.floor((os.clock() - started) * 1000)
    local _, holes = Citadel.Grow(seed, size, asym, STYLES[style], Citadel.DOOR_CAPS[doorCap], kind)
    mouths = #holes
    local box = made.upper - made.lower
    across = math.max(box.x, box.z) / math.max(1e-6, box.y)
    -- (as big as fits: its widest, corner to corner)
    local scale = RADIUS / math.max(math.max(box.x, box.y, box.z) / 2, 0.4 * vector.magnitude(box))
    local object = Object_Scenery({})
    Object_SetRenderable(object, made.model)
    object:SetScale(vector.create(scale, scale, scale))
    local at = (made.lower + made.upper) * (-0.5 * scale)
    object:SetPos(at)
    system:AddInterior(object)
    camera:SetTarget(object)
    local old = shown
    if old then
      Object_Delete(old)
    end
    for _, piece in moving do
      Object_Delete(piece.object)
    end
    shown = object
    -- (and the weapons on its hardpoints, as big as they are, in metres)
    for _, gone in armed do
      Object_Delete(gone)
    end
    armed = {}
    local types = Citadel.Armed(made.mounts, size, if family == 1 then nil else FAMILIES[family])
    local perMetre = scale / made.metres
    -- (hardpoints: pairs of mounts count once)
    mountsShown, armedShown = 0, 0
    for index, mount in made.mounts do
      if mount.twin == 0 or mount.twin > index then
        mountsShown += 1
      end
    end
    for index, mount in made.mounts do
      local piece = if types[index] ~= "" then Arms.Build(types[index]) else nil
      if piece then
        local gun = Object_Scenery({})
        Object_SetRenderable(gun, piece.gun)
        system:AddInterior(gun)
        table.insert(armed, gun)
        local base: Object? = nil
        local turning = piece.base
        if turning then
          local one = Object_Scenery({})
          Object_SetRenderable(one, turning)
          system:AddInterior(one)
          table.insert(armed, one)
          base = one
        end
        Arms.Place(piece, base, gun, at + mount.at * scale, mount.n, mount.fore, nil, perMetre)
        if mount.twin == 0 or mount.twin > index then
          armedShown += 1
        end
      end
    end
    -- (and what turns of it, each a thing of its own: Starbase.Animate turns them)
    moving = Starbase.Movers(made.movers, function(model: Model): Object
      local piece = Object_Scenery({})
      Object_SetRenderable(piece, model)
      system:AddInterior(piece)
      return piece
    end, at, vector.create(0, 0, 1), vector.create(0, 1, 0), scale)
  end
  show()

  local function keep()
    local had = ""
    local ok, text = pcall(File_Read, KEPT)
    if ok and type(text) == "string" then
      had = text
    end
    local words = detailWords()
    local people = PEOPLES[folk]
    local line = `{if people == "standard" then "" else people .. " "}{SIZES[size]} {KINDS[role]}  seed {seed}  style {STYLES[style]}{if asym then "  asym" else ""}  paint {PAINTS[paint]}`
      .. `  doors {Citadel.DOOR_CAPS[doorCap]}`
      .. (if words ~= "" then `  detail {words}` else "")
      .. (if Citadel.HasSlot(people, KINDS[role], size) then "" else "  (not one of the 35)")
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
    Show = function(toSeed: number, toSize: number, toAsym: boolean?, toPaint: string?, toDetail: string?, toLook: string?,
      toStyle: string?): boolean
      local at = table.find(PAINTS, toPaint or "dark")
      local grown = table.find(STYLES, toStyle or "blocks")
      if grown == nil then
        return false
      end
      style = grown
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
    -- paint, its detail as words, how many hangar mouths it has, its
    -- style, and how many of its parts turn.
    Now = function(): (number, number, boolean, string, string, number, string, number)
      return seed, size, asym, PAINTS[paint], detailWords(), mouths, STYLES[style], #moving
    end,
    -- Write Core/Data/CitadelDoors as the picks are now (script/citadeldoors).
    WriteDoors = function(path: string?)
      File_Write(path or "resource/script/Core/Data/CitadelDoors.luau", Citadel.DoorsFile())
    end,
    -- Let so many seconds go by for what turns (a still picture of the
    -- rings turned so far).
    Turn = function(seconds: number)
      clock += seconds
      Starbase.Animate(moving, clock, vector.create(0, 1, 0))
    end,
    -- Fit a defence module of a family ("cannon", "laser", "hybrid",
    -- "missile"; "none" for none). False if there is no such family.
    -- The hardpoints there are, and how many have a weapon on them.
    -- Show it as a kind of citadel (Citadel.KINDS, or Structures'
    -- gravity or wormhole: the generator citadel making that), its
    -- generator running or not, its kind's module online or not, and
    -- whose (Citadel.PEOPLES; standard if not said). False if there is
    -- no such kind or people.
    -- Show it as its hulk, or not.
    Hulk = function(on: boolean)
      derelict = on
      show()
    end,
    Kind = function(name: string, stopped: boolean?, dark: boolean?, people: string?): boolean
      local at = table.find(KINDS, Citadel.Slot(name))
      local whose = table.find(PEOPLES, people or "standard")
      if at == nil or whose == nil then
        return false
      end
      role, offline, folk = at, dark == true, whose
      making = if stopped == true then 3 elseif name == "wormhole" then 2 else 1
      show()
      return true
    end,
    Arm = function(name: string): (boolean, number, number)
      local at = table.find(FAMILIES, name)
      if at == nil then
        return false, 0, 0
      end
      family = at
      show()
      return true, mountsShown, armedShown
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
      local pick = Citadel.Pick(KINDS[role], size, PEOPLES[folk])
      local slot = Citadel.HasSlot(PEOPLES[folk], KINDS[role], size)
      local isPick = slot and not pick.stand and pick.seed == seed and pick.asym == asym and pick.style == STYLES[style]
        and (pick.doors or Citadel.DOORS) == Citadel.DOOR_CAPS[doorCap]
      local done, all = Citadel.Picked()
      Im.Text(`{slotName()}: {if not slot then "not one of the {all}" elseif pick.stand then "not picked yet" else "picked"}      {done} of {all} picked`
        .. `{if KINDS[role] == "generator" or STYLES[style] == "wormhole" then `      generator: {GENERATORS[making]}` else ""}`,
        x + 260, y + 6, 18, if slot then Im.TEXT else Im.DIM)
      Im.Text(`kind: {Citadel.KIND_NAMES[KINDS[role]]}      size {size} of {#SIZES}: {SIZES[size]}, a field of {field}      style: {STYLES[style]}      {if asym then "asymmetrical" else "sides alike"}      paint: {PAINTS[paint]}      look: {LOOKS[look].name}      {mouths} hangar {if mouths == 1 then "mouth" else "mouths"} (at most {Citadel.DOOR_CAPS[doorCap]})      {mountsShown} hardpoints, {armedShown} armed ({FAMILIES[family]})      {string.format("%.1f", across)} times as wide as high      made in {took} ms`,
        x, y + 40, 16, Im.DIM)
      if isPick then
        Im.Text(`the game draws a {slotName()} from this seed`, x, y + 64, 16, Im.ACCENT)
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
      Im.Text("Left / Right: seed      Down / Up: ten seeds      R: random      [ / ]: size      T: style      C: kind      V: whose      A: asymmetrical      F: defence      W: generator      O: offline      D: hulk      H: doors      P: paint      L: look      1-5: detail      , .: its seed      G: the game's pick      K: keep      Space: turn",
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
      if Key_Pressed(Key_H()) then doorCap = doorCap % #Citadel.DOOR_CAPS + 1 end
      if Key_Pressed(Key_F()) then family = family % #FAMILIES + 1 end
      if Key_Pressed(Key_W()) then making = making % #GENERATORS + 1 end
      if Key_Pressed(Key_V()) then folk = folk % #PEOPLES + 1 end
      if Key_Pressed(Key_O()) then offline = not offline end
      if Key_Pressed(Key_D()) then derelict = not derelict end
      if Key_Pressed(Key_T()) then style = style % #STYLES + 1 end
      if Key_Pressed(Key_P()) then paint = paint % #PAINTS + 1 end
      if Key_Pressed(Key_L()) then look = look % #LOOKS + 1 end
      if Key_Pressed(Key_C()) then role = role % #KINDS + 1 end
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
      if not plain then
        clock += dt
        Starbase.Animate(moving, clock, vector.create(0, 1, 0))
      end
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
