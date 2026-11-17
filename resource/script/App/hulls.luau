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
--   S              the next style: the generator's own numbers, then the
--                  other sets of them there are (Hull.STYLES: how long
--                  its rows are, how far it may reach, how it is bent,
--                  how far its plates' edges are eased)
--   A              its two sides alike, or not: any style can be had
--                  with one side of the hull not the other's twin
--                  (Hull.ASYM: what is kept says "+asym" after the style)
--   F              as a ship: a frigate's guns and engines on it, then a
--                  destroyer's, a cruiser's, a battleship's, then each
--                  class of the ladder above (attack battlecruiser,
--                  battlecruiser, capital industrial, siege dreadnought,
--                  carrier, dreadnought, supercarrier), then the three
--                  that work (hauler, mining barge, freighter), then none.
--                  The engines go on the ends the hull has astern and
--                  the guns where the game's rule of hardpoints lets
--                  them (Hull.GrownShip); it says so if there is no room
--   1 to 5         surface detail, each kind on or off (Hull.DETAILS):
--                  antennas, pipes, greebles, lights, rivets
--   the search box (top right; click it, type, Return): a seed, to go
--                  to it; or a hull's name, or part of one (owari,
--                  cruiser.ouyou), to build it again as
--                  resource/hull/seeds.txt has it: its seed, size,
--                  style and detail, as a ship of its class, painted if
--                  its line says so. Return again goes to the next hull
--                  the words fit.
--   K              keep this one: its line goes in cache/hulls-kept.txt
--                  (for a hull found by name, as a line of seeds.txt)
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
local Ships = require("@lt/Core/Data/Ships")

-- How big a hull is drawn, whatever it is.
local RADIUS = 1000

local SIZES = Hull.SIZES
local STYLES = Hull.STYLES

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
  -- (the owner's ladder of 2026-11-12: its sizes and its hardpoints. A
  -- dreadnought's twenty are ten of a battleship's guns and ten of a
  -- cruiser's, shown here as ten large turrets and ten heavy launchers;
  -- a carrier, a supercarrier and a capital industrial have none.)
  { name = "attackbattlecruiser", metres = 200, turret = "laser.beam.large", turrets = 4, launcher = "launcher.cruise", launchers = 0, engines = 3 },
  { name = "battlecruiser", metres = 300, turret = "artillery.medium", turrets = 6, launcher = "launcher.heavy", launchers = 2, engines = 4 },
  { name = "capitalindustrial", metres = 700, turret = "laser.beam.large", turrets = 0, launcher = "launcher.cruise", launchers = 0, engines = 6 },
  { name = "siegedreadnought", metres = 950, turret = "laser.beam.xl", turrets = 4, launcher = "launcher.siege", launchers = 0, engines = 6 },
  { name = "carrier", metres = 1000, turret = "laser.beam.large", turrets = 0, launcher = "launcher.cruise", launchers = 0, engines = 6 },
  { name = "dreadnought", metres = 1300, turret = "laser.beam.large", turrets = 10, launcher = "launcher.heavy", launchers = 10, engines = 6 },
  { name = "supercarrier", metres = 1300, turret = "laser.beam.large", turrets = 0, launcher = "launcher.cruise", launchers = 0, engines = 6 },
  -- (and the classes that work: a hauler's one gun, a mining barge's
  -- three strip miners, and a freighter, which has no hardpoint)
  { name = "industrial", metres = 180, turret = "autocannon.small", turrets = 1, launcher = "launcher.light", launchers = 0, engines = 3 },
  { name = "barge", metres = 160, turret = "miner.strip", turrets = 3, launcher = "launcher.light", launchers = 0, engines = 3 },
  { name = "freighter", metres = 650, turret = "autocannon.small", turrets = 0, launcher = "launcher.light", launchers = 0, engines = 4 },
}

local KEPT = "cache/hulls-kept.txt"

-- A hull is broad if it is at least this much as wide as it is long.
local BROAD = 1 / 3

local function stepsOf(size: number): number
  return (Hull.GrownSize(size))
end

local function decksOf(size: number): boolean
  local _, decks = Hull.GrownSize(size)
  return decks
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

  local seed, size, paint, style = 1, 2, 1, 1
  local asym = false        -- its two sides are not each other's twin (Hull.ASYM: any style can be had so)
  -- The name of the style shown (or of another), with that.
  local function named(how: number?): string
    return STYLES[how or style].name .. (if asym then Hull.ASYM else "")
  end
  local class = 0           -- which of CLASSES it is shown as; 0, as a bare hull
  local fitted = ""         -- how that went: what is on it, or why it is not
  local dim = true          -- what is shown is bare metal, and is lit as that is
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
  -- Which kinds of surface detail are on (Hull.DETAILS), and as words.
  local detail: { [string]: boolean } = {}
  local function detailWords(): string
    local words: { string } = {}
    for _, kind in Hull.DETAILS do
      if detail[kind] then
        table.insert(words, kind)
      end
    end
    return table.concat(words, " ")
  end
  local function detailOf(): Hull.Detail?
    return Hull.DetailOf(string.split(detailWords(), " "))
  end
  local query = ""          -- what is in the search box
  local found = 0           -- which of the hulls it fits was gone to last
  local lastSearch = ""     -- and for which words
  local listed: Hull.SeedLine? = nil   -- the hull of the list gone to by name, while it is what is shown
  local models: { [string]: Renderable | Model } = {}

  local ships: { [string]: Hull.Built } = {}

  -- The hull as a ship of a class, or nothing and why. (In the paint it
  -- is shown in: bare, it is still the generator's own mesh and metal,
  -- with its engines let into it and seats for its guns where it needs
  -- them.)
  local function ship(as: Class): (Hull.Built?, string)
    local name = `{seed}:{size}:{paint}:{style}:{asym}:{as.name}:{detailWords()}`
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
    local built, why = Hull.GrownShip(seed, stepsOf(size), decksOf(size), PAINTS[paint],
      as.metres, fit, as.turrets, as.launchers, as.engines, named(), detailOf())
    if built then
      ships[name] = built
    end
    return built, why
  end

  local function make(): Renderable | Model
    local wanted = detailOf()
    if wanted then
      return Hull.Grown(seed, stepsOf(size), decksOf(size), PAINTS[paint], named(), wanted).model
    end
    if PAINTS[paint] == "bare" then
      -- (the generator's own model, where the style is its own)
      return if style == 1 and not asym then Generate.Main(SIZES[size], seed) else Hull.GrownBare(seed, stepsOf(size), decksOf(size), named())
    end
    return Hull.Grown(seed, stepsOf(size), decksOf(size), PAINTS[paint], named()).model
  end

  local function show()
    local now = `{seed}:{size}:{paint}:{style}:{asym}:{class}:{detailWords()}`
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
    dim = PAINTS[paint] == "bare"
    local plain = `{seed}:{size}:{paint}:{style}:{asym}:{detailWords()}`
    local model: Renderable | Model = if built then built.model else models[plain] or make()
    if built == nil then
      models[plain] = model
    end
    took = math.floor((os.clock() - started) * 1000)
    local bound = Renderable_GetBound(model)
    local across = bound.upper - bound.lower
    -- (as big as fits, seen from off the bow: a picture is wider than
    -- it is high, and a hull as broad as it is long is longest corner
    -- to corner)
    local box = vector.create(across.x, 1.7 * across.y, across.z)
    local scale = RADIUS / math.max(math.max(box.x, box.y, box.z) / 2, 0.4 * vector.magnitude(box))
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
  local function beam(of: number, big: number, how: number?): number
    local across = Hull.GrownShape(of, stepsOf(big), decksOf(big), named(how))
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
    local words = detailWords()
    local line = `seed {seed}  size {size}  ({stepsOf(size)} plates{if decksOf(size) then ", decks" else ""})  style {named()}  paint {PAINTS[paint]}`
      .. (if words ~= "" then `  detail {words}` else "")
    if as then
      line ..= `  {fitted}`
    end
    -- (a hull of the list, as its line of resource/hull/seeds.txt would be now)
    local was = listed
    if was then
      local parts = { was.name, tostring(seed), tostring(size) }
      if style ~= 1 or asym then
        table.insert(parts, named())
      end
      if was.painted then
        table.insert(parts, "painted")
      end
      if words ~= "" then
        table.insert(parts, words)
      end
      line = table.concat(parts, " ")
    end
    File_Write(KEPT, had .. line .. "\n")
    note = `kept: {line}  (in {KEPT})`
  end

  -- Go to what the search box says: a seed, or the next hull of the
  -- list whose name the words are part of, built as its line has it.
  local function search(words: string)
    local text = string.lower(string.match(words, "^%s*(.-)%s*$") or "")
    if text == "" then
      return
    end
    local number = tonumber(text)
    if number then
      seed = math.max(0, math.floor(number))
      listed = nil
      note = `seed {seed}`
      return
    end
    local fits: { Hull.SeedLine } = {}
    for _, line in Hull.SEEDED do
      if string.find(string.lower(line.name), text, 1, true) then
        table.insert(fits, line)
      end
    end
    -- (a whole name is that hull alone)
    for _, line in fits do
      if string.lower(line.name) == text then
        fits = { line }
        break
      end
    end
    if #fits == 0 then
      note = `no hull of {Hull.SEEDS} is called anything like '{text}'`
      return
    end
    if text ~= lastSearch then
      found, lastSearch = 0, text
    end
    found = found % #fits + 1
    local line = fits[found]
    seed, size = line.seed, math.clamp(line.size, 1, #SIZES)
    -- (its style, and whether its sides are unalike)
    local wanted = line.style or STYLES[1].name
    local lop = #wanted > #Hull.ASYM and string.sub(wanted, -#Hull.ASYM) == Hull.ASYM
    local base = if lop then string.sub(wanted, 1, #wanted - #Hull.ASYM) else wanted
    style, asym = 1, lop
    for index, known in STYLES do
      if known.name == base then
        style = index
      end
    end
    -- (as a ship of its class; painted as its people's, if its line says painted)
    local hull = Ships.byId[line.name]
    class = 0
    for index, known in CLASSES do
      if hull and known.name == hull.class then
        class = index
      end
    end
    paint = 1
    if line.painted then
      paint = table.find(PAINTS, if hull then hull.lineage else "civil") or table.find(PAINTS, "civil") or 1
    end
    table.clear(detail)
    for _, kind in line.detail do
      detail[kind] = true
    end
    listed = line
    note = `{line.name} ({found} of {#fits} that fit '{text}'): seed {line.seed}, size {line.size}{if line.style then ", " .. line.style else ""}`
      .. (if line.painted then ", painted" else "") .. (if #line.detail > 0 then ", " .. table.concat(line.detail, " ") else "")
  end

  _G.Hulls = {
    -- Show a hull, still, from the bow quarter: its seed, its size (1 to
    -- 8), its paint's name, the name of a class to show it as a ship of
    -- (or nil), its style's name (the generator's own, if not said), and
    -- the kinds of surface detail it has, as words ("antennas lights").
    -- False if there is no such size, paint, class or style.
    Show = function(toSeed: number, toSize: number?, toPaint: string?, toClass: string?, toStyle: string?, toDetail: string?): boolean
      local at = table.find(PAINTS, toPaint or PAINTS[paint])
      local big = toSize or size
      local as = 0
      for index, known in CLASSES do
        if known.name == toClass then
          as = index
        end
      end
      -- (a style's name with Hull.ASYM after it is that style with its sides unalike)
      local lop = toStyle ~= nil and #toStyle > #Hull.ASYM and string.sub(toStyle, -#Hull.ASYM) == Hull.ASYM
      local base = if lop and toStyle then string.sub(toStyle, 1, #toStyle - #Hull.ASYM) else toStyle
      local how = if toStyle == nil then 1 else 0
      for index, known in STYLES do
        if known.name == base then
          how = index
        end
      end
      if at == nil or SIZES[big] == nil or toSeed < 0 or (toClass ~= nil and as == 0) or how == 0 then
        return false
      end
      seed, size, paint, class, style, asym = math.floor(toSeed), big, at, as, how, lop
      table.clear(detail)
      for word in string.gmatch(toDetail or "", "%a+") do
        if table.find(Hull.DETAILS, word) then
          detail[word] = true
        end
      end
      listed = nil
      turning, plain = false, true
      turn, tilt, zoom, zoomTo = TURN, TILT, ZOOM, ZOOM
      show()
      return true
    end,
    -- Go to what the search box would: a seed, or a hull of the list by
    -- name. What it says of it.
    Find = function(words: string): string
      search(words)
      show()
      return note
    end,
    -- The kinds of surface detail on what is shown, as words (none: "").
    Detail = function(words: string)
      table.clear(detail)
      for word in string.gmatch(words, "%a+") do
        if table.find(Hull.DETAILS, word) then
          detail[word] = true
        end
      end
      show()
    end,
    -- Show it in another paint (one of the browser's: bare, civil, a
    -- people's). False if there is no such paint.
    Paint = function(name: string): boolean
      local at = table.find(PAINTS, name)
      if at == nil then
        return false
      end
      paint = at
      show()
      return true
    end,
    -- Hold it still, from the bow quarter, with nothing written over it.
    Still = function()
      turning, plain = false, true
      turn, tilt, zoom, zoomTo = TURN, TILT, ZOOM, ZOOM
    end,
    -- What is shown: its seed, its size, its paint, how many plates
    -- the generator grew for it, how wide it is for its length, and
    -- its style.
    Now = function(): (number, number, string, number, number, string)
      return seed, size, PAINTS[paint], stepsOf(size), beam(seed, size), named()
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
    -- size and in a style (the generator's own, if not named), with
    -- commas between (of the next 'count' times forty).
    Broad = function(from: number, count: number, big: number, inStyle: string?): string
      local found: { string } = {}
      local at = math.max(0, math.floor(from))
      local last = at + 40 * count
      local how = 1
      for index, known in STYLES do
        if known.name == inStyle then
          how = index
        end
      end
      while #found < count and at < last and SIZES[big] ~= nil do
        if beam(at, big, how) >= BROAD then
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
      Im.Text(`size {size} of {#SIZES}: {stepsOf(size)} plates grown{decks}      style: {STYLES[style].name}      {if asym then "sides unalike" else "sides alike"}      paint: {PAINTS[paint]}{only}      made in {took} ms`,
        x, y + 40, 16, Im.DIM)
      if fitted ~= "" then
        Im.Text(fitted, x, y + 64, 16, if string.find(fitted, "no room", 1, true) then Im.WARN else Im.TEXT)
      end
      local on: { string } = {}
      for index, kind in Hull.DETAILS do
        table.insert(on, `{index} {kind}: {if detail[kind] then "ON" else "off"}`)
      end
      Im.Text("detail      " .. table.concat(on, "      "), x, y + 90, 16, if detailWords() ~= "" then Im.ACCENT else Im.DIM)
      if note ~= "" then
        Im.Text(note, x, y + 116, 14, Im.ACCENT)
      end
      -- (the search box: a seed, or a hull of the list by name)
      local wide = 320
      local was = Im.Typing()
      query = Im.Words("hulls:search", query, w.pos.x + w.size.x - wide - 24, y, wide, 32, 40, "seed, or a hull's name: Return")
      if was and not Im.Typing() and Key_Pressed(Key_Return()) then
        search(query)
      end
      local foot = w.pos.y + w.size.y - 54
      Im.Text("Left / Right: seed      Down / Up: ten seeds      R: random      B: broad only      [ / ]: size      S: style      A: sides alike or not      P: paint      F: as a ship      1-5: detail      K: keep      Space: turn",
        x, foot, 15, Im.DIM)
      Im.Text("right-drag turns it, the wheel moves in and out", x, foot + 22, 15, Im.DIM)
    end,
    PostUpdate = function(_, w: Widget)
      -- (nothing is a key while the search box is being typed in)
      if Im.Typing() then
        show()
        return
      end
      for index, key in { Key_N1(), Key_N2(), Key_N3(), Key_N4(), Key_N5() } do
        if Key_Pressed(key) then
          local kind = Hull.DETAILS[index]
          detail[kind] = not detail[kind]
        end
      end
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
      if Key_Pressed(Key_S()) then
        style = style % #STYLES + 1
        step(0)
      end
      if Key_Pressed(Key_A()) then
        asym = not asym
        step(0)
      end
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
        local bright = if dim then 0.5 else 1.15
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
