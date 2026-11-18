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
-- A scripted run can hold one view still instead, by name, with nothing
-- read from those files: Viewer.Show('gallery'). The golden images of
-- the bodies and of the effects are taken that way (test/golden).
--
-- cache/viewer/params.txt, if it exists, overrides settings for every
-- view, one a line: a name from the kind being looked at (Planet.kinds)
-- and a number (seaLevel 0.5), or three for a colour
-- (rockPale 0.6 0.5 0.4).

local AppShell = require("@lt/AppShell")
local Arms = require("@lt/Game/View/Arms")
local Capital = require("@lt/Game/View/Capital")
local Effects = require("@lt/Game/View/Effects")
local Citadel = require("@lt/Game/View/Citadel")
local Hull = require("@lt/Game/View/Hull")
local Paints = require("@lt/Core/Data/Paints")
local Starbase = require("@lt/Game/View/Starbase")
local Structures = require("@lt/Core/Data/Structures")
local Planet = require("@lt/Game/View/Planet")
local Ships = require("@lt/Core/Data/Ships")
local Star = require("@lt/Game/View/Star")
local SceneView = require("@lt/SceneView")

local RADIUS = 1000
local SETTLE = 20       -- frames between setting a view up and saving it
local REQUEST = "cache/viewer/request.txt"
local PARAMS = "cache/viewer/params.txt"
local DONE = "cache/viewer/done.txt"

type View = {
  name: string,
  kind: string,           -- a kind of planet (Planet.kinds), "star-" and a class of star, or
                          -- "hull-" and a hull type that has a design (Game/View/Hull)
  seed: number,
  eye: vector,            -- where the camera is, in planet radii from its centre
  look: vector,           -- what it looks at, likewise
  light: vector,          -- the direction the light comes from
  set: { [string]: number }?,
  radius: number?,        -- how big to make the body, if not RADIUS
  -- For a view of weapons firing in place of a body: one row to a
  -- weapon, each fired this long before the picture is taken.
  fire: { Fire }?,
  -- For a view of ships blowing up: a row to each radius, and along
  -- the row the explosion at each of these ages.
  explode: { radii: { number }, ages: { number } }?,
  -- For a view of several bodies at once, in rows of four.
  gallery: { { kind: string, seed: number } }?,
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
-- (from as near as takes the whole stage in: the golden image of the
-- effects, where they cover the most pixels)
table.insert(VIEWS, { name = "fx-5-landing-near", kind = "fx", seed = 1, eye = vector.create(0, 0, 800), look = CENTRE, light = DAY, radius = 1,
  fire = firing(LANDING, "hit") })

-- A frigate, a cruiser and a battleship blowing up, at four moments.
table.insert(VIEWS, { name = "fx-6-explosions", kind = "fx", seed = 1, eye = vector.create(0, 0, 5200), look = CENTRE, light = DAY, radius = 1,
  explode = { radii = { 25, 90, 250 }, ages = { 0.06, 0.3, 0.8, 1.8 } } })

-- Every hull that has a design, from six sides. (The light is kept on
-- the camera's side of the hull, as it must be: see SIDE.)
local HULL_VIEWS: { { any } } = {
  { "1-bow-quarter", vector.create(1.05, 0.55, 1.35), CENTRE },
  { "2-side", vector.create(1.9, 0.12, 0.05), CENTRE },
  { "3-above", vector.create(0.2, 1.9, 0.25), CENTRE },
  { "4-stern-quarter", vector.create(-1.15, 0.45, -1.35), CENTRE },
  { "5-below", vector.create(-0.95, -0.95, 1.15), CENTRE },
  { "6-close", vector.create(0.55, 0.30, 0.80), vector.create(0.05, 0.05, 0.30) },
}
for _, type in Hull.Types() do
  -- ("javelin" for frigate.javelin, and "javelin-ii" for its tech 2 make)
  local short = (string.gsub(string.match(type, "^%a+%.(.+)$") or type, "%.", "-"))
  for _, view in HULL_VIEWS do
    local eye: vector = view[2]
    table.insert(VIEWS, { name = `hull-{short}-{view[1]}`, kind = `hull-{type}`, seed = 1, eye = eye, look = view[3],
      light = eye + vector.create(0.5, 0.9, 0.2) * (0.6 * vector.magnitude(eye)) })
  end
end

-- What that generator makes in the game's own paint (Hull.Grown), to
-- look through for shapes ("grown-"): twelve seeds as it grew a frigate,
-- and twelve as it grew its biggest. The kind is "grown-", the plates it
-- grows, and "d" for with decks under.
for _, make in { "4", "6d" } do
  for seed = 1, 12 do
    for at, view in HULL_VIEWS do
      if at == 1 or at == 3 then
        local eye: vector = view[2]
        table.insert(VIEWS, { name = `grown-{make}-{string.format("%02d", seed)}-{view[1]}`, kind = `grown-{make}`,
          seed = seed, eye = eye, look = view[3], light = eye + vector.create(0.5, 0.9, 0.2) * (0.6 * vector.magnitude(eye)) })
      end
    end
  end
end

-- The hulls the engine's first generator makes (Item/ShipType/Generate:
-- boxes grown off a cross, mirrored, pinched and flared), to set beside
-- the designed ones ("old-"): at the size of a frigate, of a barge and of
-- a hauler, a few seeds of each. The kind is "old-" and the radius.
for _, size in { 44, 110, 160 } do
  for _, seed in { 1, 2, 3, 4, 5, 6, 55, 77 } do
    for at, view in HULL_VIEWS do
      if at == 1 or at == 3 or at == 4 then
        local eye: vector = view[2]
        table.insert(VIEWS, { name = `old-{size}-{seed}-{view[1]}`, kind = `old-{size}`, seed = seed, eye = eye, look = view[3],
          light = eye + vector.create(0.5, 0.9, 0.2) * (0.6 * vector.magnitude(eye)), radius = size })
      end
    end
  end
end

-- The pirates' ranks: a hull of theirs as one of the pack flies it, as
-- a veteran does and as a captain does ("rank-"; the kind is the hull
-- and "@" the rank: Hull.Build's).
for rank, who in { [0] = "0-pack", "1-veteran", "2-captain" } do
  for _, hull in { "frigate.cutthroat", "cruiser.marauder" } do
    local short = string.match(hull, "^%a+%.(.+)$") or hull
    for at, view in HULL_VIEWS do
      if at == 1 or at == 3 then
        local eye: vector = view[2]
        table.insert(VIEWS, { name = `rank-{short}-{who}-{view[1]}`, kind = `hull-{hull}@{rank}`, seed = 1, eye = eye, look = view[3],
          light = eye + vector.create(0.5, 0.9, 0.2) * (0.6 * vector.magnitude(eye)) })
      end
    end
  end
end

-- Wrecks: each designed hull's, and the plain wreckage of a ship nobody
-- has designed ("wreck-plain"), as they lie half a minute after.
local WRECKS = Hull.Types()
table.insert(WRECKS, "")
for _, type in WRECKS do
  local short = if type == "" then "plain" else (string.gsub(string.match(type, "^%a+%.(.+)$") or type, "%.", "-"))
  for _, view in { HULL_VIEWS[1], HULL_VIEWS[2] } do
    local eye: vector = view[2]
    table.insert(VIEWS, { name = `wreck-{short}-{view[1]}`, kind = `wreck-{type}`, seed = 1, eye = eye * 1.25, look = view[3],
      light = eye + vector.create(0.5, 0.9, 0.2) * (0.6 * vector.magnitude(eye)) })
  end
end

-- The Kethri's colony ship (Game/View/Capital): as long as said and a
-- tenth of that across ("colony-1"), and broader ("colony-2"), from
-- about, from below where the docks are, and close to the conning tower.
local COLONY_VIEWS: { { any } } = {
  { "1-bow-quarter", vector.create(0.92, 0.50, 1.22), vector.create(0, 0, 0.02), vector.create(1.2, 1.4, 0.9) },
  { "2-side", vector.create(1.25, 0.05, 0), CENTRE, vector.create(1.3, 1.0, 0.5) },
  { "3-above", vector.create(0.02, 1.3, 0), CENTRE, vector.create(0.6, 1.5, 0.4) },
  { "4-stern-quarter", vector.create(-0.55, 0.32, -1.75), vector.create(0, 0, -0.45), vector.create(-0.9, 1.3, -1.2) },
  { "5-below", vector.create(-0.60, -0.62, 0.45), vector.create(0, 0, -0.30), vector.create(-0.5, -1.4, 0.6) },
}
for index, across in { 0.2, 0.45 } do
  for _, view in COLONY_VIEWS do
    local eye: vector = view[2]
    table.insert(VIEWS, { name = `colony-{index}-{view[1]}`, kind = `colony-{across}`, seed = 1, eye = eye, look = view[3],
      light = view[4] })
  end
  local tower = vector.create(0, 0.06, Capital.Conning(across))
  table.insert(VIEWS, { name = `colony-{index}-6-tower`, kind = `colony-{across}`, seed = 1, eye = tower + vector.create(0.22, 0.07, 0.24),
    look = tower, light = vector.create(0.9, 0.8, 0.7) })
end

-- Stations (Game/View/Starbase). The three sizes of tower side by side,
-- at the sizes they stand in fields of 3, 5 and 7 km; every module in
-- rows, at their own sizes beside each other; and whole stations laid
-- out, with their fields, from outside and from among the modules.
for index, eye in { vector.create(0.5, 0.25, 2.7), vector.create(-1.7, 1.0, 2.1) } do
  table.insert(VIEWS, { name = `base-towers-{index}`, kind = "towers", seed = 1, eye = eye, look = vector.create(-0.15, 0, 0),
    light = vector.create(1.5, 1.6, 2.5) })
end
for index, eye in { vector.create(0.5, 0.25, 2.7), vector.create(-1.7, 1.0, 2.1) } do
  table.insert(VIEWS, { name = `base-towers-talmar-{index}`, kind = "towers:talmar", seed = 1, eye = eye, look = vector.create(-0.15, 0, 0),
    light = vector.create(1.5, 1.6, 2.5) })
end
for index, eye in { vector.create(0.5, 0.25, 2.7), vector.create(-1.7, 1.0, 2.1) } do
  table.insert(VIEWS, { name = `base-towers-orun-{index}`, kind = "towers:orun", seed = 1, eye = eye, look = vector.create(-0.15, 0, 0),
    light = vector.create(1.5, 1.6, 2.5) })
end
for index, eye in { vector.create(0.5, 1.1, 2.9), vector.create(-1.9, 0.8, -2.4) } do
  table.insert(VIEWS, { name = `base-modules-{index}`, kind = "modules", seed = 1, eye = eye, look = vector.create(0, -0.1, 0),
    light = if index == 1 then vector.create(1.5, 1.8, 2.5) else vector.create(-2.0, 1.8, -1.5) })
end
for index, eye in { vector.create(1.3, 0.6, 2.3), vector.create(2.6, 0.3, 0.5) } do
  table.insert(VIEWS, { name = `base-gate-{index}`, kind = "gate", seed = 1, eye = eye, look = CENTRE, light = vector.create(1.5, 1.8, 2.5) })
end
for index, base in { { "outpost", 3000 }, { "shipyard", 5000 }, { "trade hub", 7500 } } :: { { any } } do
  local word = ({ "small", "medium", "large" })[index]
  table.insert(VIEWS, { name = `base-{index}-{word}-1-outside`, kind = `starbase:{base[1]}:{base[2]}`, seed = 3 + index,
    eye = vector.create(1.5, 0.7, 2.5), look = CENTRE, light = vector.create(2.5, 2.2, 3.0) })
  table.insert(VIEWS, { name = `base-{index}-{word}-2-inside`, kind = `starbase:{base[1]}:{base[2]}`, seed = 3 + index,
    eye = vector.create(-0.55, 0.22, 0.75), look = vector.create(0, 0.05, 0), light = vector.create(-1.5, 1.6, 2.2) })
end

-- What goes on hardpoints: every weapon's model, small, in rows (the
-- eye and what it looks at are in the units the models are drawn in:
-- see Game/View/Arms), from the front and the back.
local ARMS = { "laser.pulse.small", "laser.beam.small", "autocannon.small", "artillery.small", "blaster.small", "railgun.small",
  "miner.small", "launcher.light", "launcher.heavy", "launcher.cruise" }
table.insert(VIEWS, { name = "arms-1-front", kind = "arms", seed = 1, eye = vector.create(14, 18, 37), look = vector.create(0, 1.0, 0),
  light = vector.create(0.5, 0.9, 0.6), radius = 30 })
table.insert(VIEWS, { name = "arms-2-back", kind = "arms", seed = 1, eye = vector.create(-16, 16, -36), look = vector.create(0, 1.0, 0),
  light = vector.create(-0.5, 0.9, -0.6), radius = 30 })

-- And the three sizes side by side, small to large from the left: a
-- turret, a launcher and the cover of an empty hardpoint at each, to
-- show that all three stand on the one mounting ring of their size.
local ARM_SIZES = { { "artillery.small", "artillery.medium", "artillery.large" }, { "launcher.light", "launcher.heavy", "launcher.cruise" } }
table.insert(VIEWS, { name = "arms-3-sizes", kind = "arms-sizes", seed = 1, eye = vector.create(-8, 46, 100), look = vector.create(-1, 2, 0),
  light = vector.create(0.5, 0.9, 0.6), radius = 30 })
table.insert(VIEWS, { name = "arms-4-sizes-above", kind = "arms-sizes", seed = 1, eye = vector.create(-1, 125, 9), look = vector.create(-1, 0, 5),
  light = vector.create(0.3, 0.9, 0.5), radius = 30 })

-- One of everything, for a single picture of how the bodies look.
table.insert(VIEWS, { name = "gallery", kind = "gallery", seed = 0, eye = vector.create(0, 0, 9.6), look = CENTRE, light = DAY,
  gallery = {
    { kind = "temperate", seed = 1 }, { kind = "ocean", seed = 2 }, { kind = "barren", seed = 1 }, { kind = "moon", seed = 1 },
    { kind = "ice", seed = 2 }, { kind = "lava", seed = 1 }, { kind = "gas", seed = 5 }, { kind = "star-orange", seed = 1 },
  } })

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
  if lamp then
    -- (white light: this system's own star is green, and hulls are lit
    -- by it; the worlds are told to take white light themselves)
    Star_SetColor(lamp, vector.create(1.15, 1.15, 1.15))
  end

  local worlds: { Planet.World } = {}
  local stage: { Object } = {}    -- what stands in the scene for the view
  local units: { number } = {}    -- and how big each is, to a radius of 1
  local extras: { Object } = {}   -- what is mounted on it (placed and sized as made)
  local fx: Effects.Fx? = nil
  local built = ""          -- what the stage was built for
  local index = 0           -- the view being taken; 0 when idle
  local held: View? = nil   -- a view being held still (Viewer.Show)
  local frames = 0
  local request = readRequest()
  local params: Planet.Tweaks = {}
  local views: { View } = VIEWS

  -- A body of a kind (a planet's, "star-" and a class of star, "hull-"
  -- and a hull type), and how big it is as made.
  local function make(kind: string, seed: number, tweaks: Planet.Tweaks, resolution: number?): (Object, number)
    local class = string.match(kind, "^star%-(%a+)$")
    if class then
      return Star.New(class, seed, tweaks), 1
    end
    local hull = string.match(kind, "^hull%-(.+)$")
    local dressed, coat = string.match(hull or "", "^([^~]+)~(.+)$")
    if dressed and coat then
      -- ("~livery": in the paint its faction's own ships wear in space, if
      -- it has one; or "~" a paint, and "~" a design on it if any)
      local ship = Ships.byId[dressed]
      local paint, figure = Paints.Dress(if ship then ship.lineage else "", false)
      if coat ~= "livery" then
        paint, figure = string.match(coat, "^([^~]+)"), string.match(coat, "~(.+)$")
        assert(Paints.paintById[paint :: string], `no paint '{paint}'`)
        assert(figure == nil or Paints.designById[figure], `no design '{figure}'`)
      end
      local built = assert(Hull.Build(dressed, nil, nil, paint, figure), `no design for the hull '{dressed}'`)
      local object = Object_Scenery({})
      Object_SetRenderable(object, built.model)
      return object, built.radius
    end
    if hull then
      -- ("@1": as a pirate veteran flies it; "@2", a captain; "@0", one of the pack)
      local plain, rank = string.match(hull, "^(.+)@(%d)$")
      local built = if plain then assert(Hull.Build(plain, true, tonumber(rank)), `no design for the hull '{plain}'`)
        else assert(Hull.Build(hull), `no design for the hull '{hull}'`)
      local object = Object_Scenery({})
      Object_SetRenderable(object, built.model)
      return object, built.radius
    end
    -- ("citadel-" a size, "~" a paint, "~" the kinds of its detail with
    -- "+" between, "~" its style: Game/View/Citadel, grown from the view's seed)
    local big, lop, painted, words, style = string.match(kind, "^citadel%-(%d)(a?)~([^~]*)~([^~]*)~?(.*)$")
    if big then
      local built = Citadel.Build(seed, tonumber(big) or 1, if painted == "" then nil else painted, (string.gsub(words or "", "%+", " ")),
        nil, lop == "a", if style == nil or style == "" then nil else style)
      local object = Object_Scenery({})
      Object_SetRenderable(object, built.model)
      -- (its middle in the middle)
      object:SetPos(-(built.lower + built.upper) * 0.5)
      return object, built.radius
    end
    local steps, decks = string.match(kind, "^grown%-(%d+)(d?)$")
    if steps then
      local built = Hull.Grown(seed, tonumber(steps) or 4, decks == "d")
      local object = Object_Scenery({})
      Object_SetRenderable(object, built.model)
      return object, built.radius
    end
    local old = string.match(kind, "^old%-(%d+)$")
    if old then
      -- (the generator sizes a hull by its value: Game/View/Scene. It is
      -- made at its size, and is not to be rescaled.)
      local radius = tonumber(old) or 44
      local item = Item_ShipType((radius / 0.0675) ^ 2, seed, 1, 1, 1, 1, 1, 1)
      local ship = item:Instantiate()
      -- (its own origin is wherever its first plate was: its middle goes in the middle)
      ship:SetPos(-ship:GetCenter())
      return ship, radius
    end
    local across = string.match(kind, "^colony%-(.+)$")
    if across then
      local built = Capital.Larmes(tonumber(across))
      local object = Object_Scenery({})
      Object_SetRenderable(object, built.model)
      return object, built.radius
    end
    local planet = Planet.New(kind, seed, resolution, tweaks)
    table.insert(worlds, planet)
    return planet.body, 1
  end

  -- A weapon's model stood on a mount, as scenery. 'aim' is where it
  -- points, or nil for at rest.
  local function mountArm(type: string, origin: vector, up: vector, fore: vector, aim: vector?, metres: number, small: boolean?)
    local piece = Arms.Build(type)
    if piece == nil then
      return
    end
    if small then
      piece.scale = Arms.SIZE[1]
    end
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
    Arms.Place(piece, base, gun, origin, up, fore, aim, metres)
  end

  -- A hull's hardpoints, carrying what its design says it is shown with.
  local function dress(type: string, radius: number)
    local built = Hull.Build(type)
    local hull = Ships.byId[type]
    if built == nil or hull == nil then
      return
    end
    local unit = radius / built.radius      -- one of the hull's own units, in the scene
    local metres = radius / hull.radius
    local fore = vector.create(0, 0, 1)
    local at = 0
    local function each(points: { Hull.Hardpoint })
      for index, point in points do
        at += 1
        -- (the same weapon on both mounts of the hardpoint)
        for _, mount in point do
          local rest = mount.fore or fore
          -- (the guns slewed off to one side and up a little, turn about, to show that they do)
          local side = vector.cross(mount.up, rest)
          local aim = vector.normalize(rest + side * (if index % 2 == 0 then -0.7 else 0.7) + mount.up * 0.35)
          mountArm(built.fit[at], mount.at * unit, mount.up, rest, aim, metres)
        end
      end
    end
    each(built.turrets)
    each(built.launchers)
    -- (and its engines burning, at most of what they have)
    local effects = Effects.New(system)
    local color = vector.create(built.glow[1], built.glow[2], built.glow[3])
    for index, engine in built.engines do
      Effects.Thrust(effects, index, engine.at * unit, vector.create(0, 0, -1), engine.radius * unit, 0.75, color, 0)
    end
    Effects.Update(effects, 0, {})
    fx = effects
  end

  local function setUp(v: View)
    local tweaks = table.clone(params)
    local key = `{v.name}:{v.kind}:{v.seed}:{v.radius or RADIUS}`
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
      local effects = Effects.New(system)
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
            -- (between two ships the size of cruisers)
            Effects.Fire(effects, shot.type, 2 * row - 1, 2 * row, 40, 40, shot.outcome, shot.flight or 0, shot.struck, now)
          end
        end
        Effects.Update(effects, now, where)
        now += 0.01
      end
      fx = effects
    end
    local explode = v.explode
    if explode then
      local effects = Effects.New(system)
      for row, radius in explode.radii do
        for column, age in explode.ages do
          local at = vector.create((column - (#explode.ages + 1) / 2) * 2300, ((#explode.radii + 1) / 2 - row) * 1700, 0)
          Effects.Explode(effects, at, radius, -age)
        end
      end
      Effects.Update(effects, 0, {})
      fx = effects
    end
    if built ~= key or #stage == 0 then
      for _, object in stage do
        Object_Delete(object)
      end
      for _, object in extras do
        Object_Delete(object)
      end
      table.clear(extras)
      table.clear(stage)
      table.clear(units)
      table.clear(worlds)
      local radius = v.radius or RADIUS
      if v.kind == "arms" then
        -- every weapon's model in two rows, 13 m apart, some swung round
        table.insert(stage, Object_Scenery({}))
        table.insert(units, 1)
        for index, type in ARMS do
          local column, row = (index - 1) % 5, (index - 1) // 5
          local aim = vector.normalize(vector.create(0.5 * ((index % 3) - 1), 0.25 + 0.1 * (index % 2), 1))
          -- (all at the size of a small weapon, to compare them)
          mountArm(type, vector.create((column - 2) * 11, 0, (0.5 - row) * 14) * radius, vector.create(0, 1, 0),
            vector.create(0, 0, 1), aim, radius / Arms.SIZE[1], true)
        end
      elseif string.sub(v.kind, 1, 6) == "wreck-" then
        -- the pieces of a wreck, parted and turned as they are after a while
        table.insert(stage, Object_Scenery({}))
        table.insert(units, 1)
        local started = os.clock()
        local wreckage = Hull.Wreck(string.sub(v.kind, 7))
        print(`viewer: the wreck of '{string.sub(v.kind, 7)}' took {math.floor((os.clock() - started) * 1000)} ms to make`)
        local scale = radius / wreckage.radius
        for index, piece in wreckage.pieces do
          local object = Object_Scenery({})
          Object_SetRenderable(object, piece.model)
          object:SetScale(vector.create(scale, scale, scale))
          system:AddInterior(object)
          table.insert(extras, object)
          local away = vector.normalize(piece.middle + vector.create(0.2 * index - 0.4, 0.15 * index - 0.3, 0.01))
          local tilt = 0.9 * (index - (#wreckage.pieces + 1) / 2) + 0.2
          local look = vector.normalize(vector.create(math.sin(tilt), 0.4 * math.sin(tilt * 1.7), math.cos(tilt)))
          local up = vector.normalize(vector.create(0.3 * math.sin(tilt * 2.1), 1, 0) - look * (0.3 * math.sin(tilt * 2.1) * look.x + look.y))
          local right = vector.cross(up, look)
          local m = piece.middle
          object:SetPos((m + away * 0.30 * wreckage.radius) * scale - (right * m.x + up * m.y + look * m.z) * scale)
          Object_SetAxes(object, look, up)
        end
      elseif string.sub(v.kind, 1, 6) == "towers" or v.kind == "modules" or v.kind == "gate" or string.sub(v.kind, 1, 9) == "starbase:" then
        table.insert(stage, Object_Scenery({}))
        table.insert(units, 1)
        local fore = vector.create(0, 0, 1)
        local layout: Starbase.Layout
        local metres: number
        if string.sub(v.kind, 1, 6) == "towers" then
          -- (a metre is such that the large tower is the view's radius high and a bit)
          metres = radius / 1960
          local parts: { Starbase.Part } = {}
          -- (seen from +z, +x is to the left: the small one is out there)
          local faction = if #v.kind > 7 then string.sub(v.kind, 8) else "vessari"
          for size, across in { 1650, 350, -1500 } do
            local towerRadius = ({ 3000, 5000, 7000 })[size] * Starbase.TOWER
            table.insert(parts, Starbase.TowerPart(faction, size, vector.create(across, 0, 0), towerRadius))
          end
          layout = { tower = parts[1], modules = { parts[2], parts[3] }, field = 0 }
        elseif v.kind == "gate" then
          metres = radius / 2000
          local made = Starbase.Gate()
          layout = { tower = { id = "gate", model = made.model, at = vector.create(0, 0, 0), look = fore, scale = 2000 / made.radius,
            radius = 2000 }, modules = {}, field = 0 }
        elseif v.kind == "modules" then
          metres = radius / 900
          local parts: { Starbase.Part } = {}
          for index, module in Structures.modules do
            local made = Starbase.Module(module.id)
            local column, row = (index - 1) % 5, (index - 1) // 5
            local part: Starbase.Part = { id = module.id, model = made.model,
              at = vector.create((2 - column) * 900, 0, (0.5 - row) * 1300), look = fore, scale = module.radius / made.radius,
              radius = module.radius }
            if module.id == "battery.gun" then
              part.arm, part.unit = "artillery.large", 26
            elseif module.id == "battery.missile" then
              part.arm, part.unit = "launcher.cruise", 26
            end
            table.insert(parts, part)
          end
          layout = { tower = table.remove(parts, 1) :: Starbase.Part, modules = parts, field = 0 }
        else
          local variety, size = string.match(v.kind, "^starbase:(.+):(%d+)$")
          local started = os.clock()
          layout = Starbase.Layout(variety or "outpost", tonumber(size) or 3000, v.seed)
          print(`viewer: the station '{v.kind}' took {math.floor((os.clock() - started) * 1000)} ms to lay out and make`)
          metres = radius / layout.field
        end
        for _, object in (Starbase.Raise(layout, system, vector.create(0, 0, 0), metres)) do
          table.insert(extras, object)
        end
      elseif v.kind == "arms-sizes" then
        table.insert(stage, Object_Scenery({}))
        table.insert(units, 1)
        local up, fore = vector.create(0, 1, 0), vector.create(0, 0, 1)
        -- (a row: cover, launcher, turret at each size, and seen from
        -- the front +x is on the left, so the small ones are out at +x)
        for size, x in { 53, 28, -27 } do
          local apart = ({ 5, 11, 26 })[size]
          local unit = radius / Arms.SIZE[1]
          mountArm(ARM_SIZES[1][size], vector.create(x - apart, 0, 0) * radius, up, fore, vector.normalize(vector.create(0, 0.2, 1)), unit)
          mountArm(ARM_SIZES[2][size], vector.create(x, 0, 0) * radius, up, fore, nil, unit)
          local cover = Object_Scenery({})
          Object_SetRenderable(cover, Arms.Blank())
          cover:SetPos(vector.create(x + apart, 0, 0) * radius)
          local scale = Arms.SIZE[size] * unit
          cover:SetScale(vector.create(scale, scale, scale))
          system:AddInterior(cover)
          table.insert(extras, cover)
        end
      elseif fire or explode then
        -- (something for the camera to be told to look at)
        table.insert(stage, Object_Scenery({}))
        table.insert(units, 1)
      elseif v.gallery then
        for at, item in v.gallery do
          local made, unit = make(item.kind, item.seed, tweaks, 512)
          made:SetPos(vector.create(((at - 1) % 4 - 1.5) * 2.8, (0.5 - (at - 1) // 4) * 2.8, 0) * radius)
          table.insert(stage, made)
          table.insert(units, unit)
        end
      else
        local made, unit = make(v.kind, v.seed, tweaks, nil)
        table.insert(stage, made)
        table.insert(units, unit)
      end
      for index, object in stage do
        local size = radius / units[index]
        if size ~= 1 then
          object:SetScale(vector.create(size, size, size))
        end
        system:AddInterior(object)
      end
      local hull = string.match(v.kind, "^hull%-(.+)$")
      if hull then
        dress((string.gsub(string.gsub(hull, "@%d$", ""), "~.*$", "")), radius)
      end
      camera:SetTarget(stage[1])
      built = key
    end
    -- (judged in white light: the scene's own star is whatever colour
    -- its system rolled)
    local white = params.whiteLight
    for _, world in worlds do
      Planet.Set(world, "whiteLight", if type(white) == "number" then white else 1)
    end
    if lamp then
      -- (the old hulls are bare bright metal, and burn out in the light the painted ones are judged in)
      local bright = if string.sub(v.kind, 1, 4) == "old-" then 0.5 else 1.15
      Star_SetColor(lamp, vector.create(bright, bright, bright))
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

  -- A hull of the game's from the bow quarter, in its faction's livery:
  -- from farther off than the hull views, so that a wide hull has room
  -- in a square about it, which the art is cut to (script/artgen).
  -- ('paint' and 'figure': in that paint and design in place of the livery)
  local function shipView(type: string, paint: string?, figure: string?): View
    local eye: vector = HULL_VIEWS[1][2] * 1.45
    local coat = if paint then paint .. (if figure then `~{figure}` else "") else "livery"
    return { name = `ship-{type}`, kind = `hull-{type}~{coat}`, seed = 1, eye = eye, look = CENTRE,
      light = eye + vector.create(0.5, 0.9, 0.2) * (0.6 * vector.magnitude(eye)) }
  end

  -- A citadel held still, from a little above its side: Game/View/Citadel.
  local function citadelView(seed: number, size: number, paint: string?, detail: string?, asym: boolean?, style: string?): View
    local eye = vector.create(1.3, 0.6, 1.9)
    return { name = `citadel-{seed}-{size}`,
      kind = `citadel-{size}{if asym then "a" else ""}~{paint or ""}~{string.gsub(detail or "", " ", "+")}~{style or ""}`, seed = seed,
      eye = eye, look = CENTRE, light = eye + vector.create(0.5, 0.9, 0.2) * (0.6 * vector.magnitude(eye)) }
  end

  _G.Viewer = {
    -- Hold the view called 'name' still, as its kind's own settings make
    -- it. False if there is none.
    Show = function(name: string): boolean
      for _, v in VIEWS do
        if v.name == name then
          params = {}
          built = ""
          index = 0
          held = v
          setUp(v)
          return true
        end
      end
      return false
    end,
    -- Take every hull of a faction ('lineage'; "" for nobody's) that has
    -- a design, from the bow quarter, in its faction's livery: a picture
    -- each, "ship-" and its type, then done. For the art made from them
    -- (script/artgen). Returns how many.
    Ships = function(lineage: string): number
      views = {}
      for _, ship in Ships.list do
        if ship.lineage == lineage and Hull.Has(ship.id) then
          table.insert(views, shipView(ship.id))
        end
      end
      params, held, built, index, frames = {}, nil, "", if #views > 0 then 1 else 0, 0
      if #views > 0 then
        setUp(views[1])
      end
      return #views
    end,
    -- Hold one hull still as Ships takes it ('type': frigate.akashi), or
    -- in a paint ('paint.crimson') and a design on it ('design.flames').
    -- False if it has no design.
    Ship = function(type: string, paint: string?, figure: string?): boolean
      if not Hull.Has(type) then
        return false
      end
      params, built, index, frames = {}, "", 0, 0
      held = shipView(type, paint, figure)
      setUp(held :: View)
      return true
    end,
    -- Hold a citadel as Game/View/Citadel grows it: its seed, its size (1
    -- to 5), its paint (Hull.looks: the civil blue-grey if none) and the
    -- kinds of its surface detail ("antennas lights", or "" for none), and
    -- its style (Citadel.STYLES; blocks if none).
    Citadel = function(seed: number, size: number, paint: string?, detail: string?, asym: boolean?, style: string?): boolean
      if size < 1 or size > 5 then
        return false
      end
      params, built, index, frames = {}, "", 0, 0
      held = citadelView(seed, size, paint, detail, asym, style)
      setUp(held :: View)
      return true
    end,
    -- Cel shading on or off (the engine's "Smooth Shading" switched off,
    -- or on again): light/global.jsl. 'worn': the first look of it (Cel
    -- V1, over the worn paint), not the second (Game/View/Graphics).
    Cel = function(on: boolean, worn: boolean?)
      RenderPass_SetEnabled("Smooth Shading", not on)
      RenderPass_SetEnabled("Flat Paint", worn ~= true)
    end,
  }

  return Widget_Stack(Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return { view }
    end,
    PreUpdate = function()
      local showing = held or (if index > 0 then views[index] else nil)
      if showing then
        -- (the camera's "relative" position is a place in the scene)
        camera:SetRelativePos(showing.eye * (showing.radius or RADIUS))
        camera:SetRelativeLookAt(showing.look * (showing.radius or RADIUS))
        camera:SetRigidity(60)
      end
      if held then
        frames += 1
      elseif index > 0 then
        local v = views[index]
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
