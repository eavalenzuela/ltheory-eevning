--!strict
-- Hulls designed by hand, faction by faction, out of plates: boxes with
-- a centre, a half-size and a turn, each tagged with the part of the hull
-- it is (plating, a patched-in plate, bare structure, something lit,
-- trim) so that one shader can paint the lot (material/hull.jsl).
--
-- A design is a function that adds plates through the pieces below
-- (block, beam, truss, nacelle, tank, mast, ...). It is drawn in the
-- hull's own units, nose toward +z and up toward +y, about its own
-- middle; Hull.Build makes the model and says how big it came out, and
-- whoever draws it scales it to the size the game says the hull is.
--
-- The Vessari (the first faction drawn, after the project owner's
-- sketch and direction: mercantilists; blocky, utilitarian; conduits
-- showing, heavy armour, missiles, engines out on struts): a spine of bare
-- girders with armoured boxes hung on it, nothing quite symmetrical,
-- plates of two colours where repairs have been made, tanks strapped on
-- outside, masts and fins, and rust.

local Arms = require("@lt/Game/View/Arms")
local Imported = require("@lt/Game/View/Imported")
local Int = require("@lt/Int")
local Paints = require("@lt/Core/Data/Paints")
local Plates = require("@lt/Game/View/Plates")
local Fits = require("@lt/Core/Fits")
local Ships = require("@lt/Core/Data/Ships")
local Structures = require("@lt/Core/Data/Structures")

local Hull = {}

local PLATING, PATCH, FRAME, GLOW, TRIM = Plates.PLATING, Plates.PATCH, Plates.FRAME, Plates.GLOW, Plates.TRIM

type Builder = Plates.Builder
export type Look = Plates.Look

Hull.looks = {
  vessari = {
    plating = { 0.52, 0.31, 0.16 }, patch = { 0.56, 0.52, 0.43 }, frame = { 0.17, 0.16, 0.16 },
    glow = { 1.0, 0.72, 0.32 }, trim = { 0.46, 0.12, 0.07 }, wear = 0.65, rust = 0.65, sheets = 3.2,
  },
  -- The Talmar: pale, in a patchwork of small panels, clean; deep blue
  -- for what is marked, a soft blue-white light.
  talmar = {
    plating = { 0.50, 0.50, 0.50 }, patch = { 0.40, 0.42, 0.46 }, frame = { 0.20, 0.22, 0.26 },
    glow = { 0.75, 0.88, 1.0 }, trim = { 0.14, 0.27, 0.50 }, wear = 0.22, rust = 0.05, sheets = 3.0, mottle = 0.8, lights = 0.6,
  },
  -- The Kethri: flat grey plate, clean, in big sheets; what is marked is
  -- near black; a cold white light, and many lit ports.
  kethri = {
    plating = { 0.36, 0.37, 0.39 }, patch = { 0.29, 0.30, 0.33 }, frame = { 0.12, 0.12, 0.13 },
    glow = { 0.85, 0.93, 1.0 }, trim = { 0.15, 0.16, 0.18 }, fire = { 0.70, 0.92, 1.0 }, wear = 0.15, rust = 0.02, sheets = 3.4,
    mottle = 0.35, lights = 0.5,
  },
  -- The Vail (the owner's drawings): brown and charcoal in broad bands,
  -- what is marked black, lit in amber; kept, not new.
  vail = {
    plating = { 0.33, 0.20, 0.10 }, patch = { 0.11, 0.11, 0.11 }, frame = { 0.10, 0.10, 0.10 },
    glow = { 1.0, 0.66, 0.24 }, trim = { 0.045, 0.045, 0.05 }, fire = { 1.0, 0.56, 0.18 }, wear = 0.30, rust = 0.12, sheets = 3.0,
  },
  -- The pirates: whatever paint was on it, gone dark, the new plate
  -- bare, a red light.
  unbound = {
    plating = { 0.25, 0.19, 0.16 }, patch = { 0.50, 0.48, 0.44 }, frame = { 0.13, 0.12, 0.12 },
    glow = { 1.0, 0.25, 0.10 }, trim = { 0.50, 0.08, 0.05 }, wear = 0.85, rust = 0.85, sheets = 3.2, mottle = 1.0,
  },
  -- A pirate veteran's: the same dark hull, kept from rusting through,
  -- with what was patched in and the trim painted bone white. And a
  -- captain's: black and well kept, what was patched in painted their
  -- red, gold trim, lit ports. (So the two are told from the pack by
  -- eye. First drafts.)
  veteran = {
    plating = { 0.20, 0.16, 0.15 }, patch = { 0.86, 0.83, 0.72 }, frame = { 0.12, 0.11, 0.11 },
    glow = { 1.0, 0.25, 0.10 }, trim = { 0.86, 0.83, 0.72 }, wear = 0.55, rust = 0.40, sheets = 3.2, mottle = 0.9,
  },
  captain = {
    plating = { 0.05, 0.045, 0.05 }, patch = { 0.55, 0.05, 0.04 }, frame = { 0.08, 0.07, 0.07 },
    glow = { 1.0, 0.45, 0.12 }, trim = { 0.90, 0.66, 0.15 }, wear = 0.22, rust = 0.15, sheets = 3.2, mottle = 0.6, lights = 0.3,
  },
  -- Hulls no faction owns: plain blue-grey, a yellow stripe, a cold light.
  civil = {
    plating = { 0.40, 0.44, 0.48 }, patch = { 0.62, 0.62, 0.58 }, frame = { 0.16, 0.16, 0.17 },
    glow = { 0.70, 0.90, 1.0 }, trim = { 0.74, 0.52, 0.10 }, wear = 0.40, rust = 0.20, sheets = 3.2,
  },
  -- No paint: the bare metal the engine's first generator left its
  -- hulls in (Plates' 'bare'). A hull drawn from a seed is in this
  -- unless it is asked for painted. (The colours are what its wreck is
  -- charred from, and the light of its engines.)
  bare = {
    plating = { 0.50, 0.51, 0.52 }, patch = { 0.58, 0.58, 0.57 }, frame = { 0.42, 0.43, 0.44 },
    glow = { 0.70, 0.90, 1.0 }, trim = { 0.50, 0.51, 0.52 }, wear = 0.40, rust = 0.20, sheets = 3.2, bare = true,
  },
} :: { [string]: Look }
-- How finely the generator meshed its hulls (Item/ShipType/Generate),
-- and so how finely a bare one is.
local BARE_QUALITY = 12

local block, beam, truss, conduit = Plates.Block, Plates.Beam, Plates.Truss, Plates.Conduit

local function v(x: number, y: number, z: number): vector
  return vector.create(x, y, z)
end

-- An engine pod, faceted (two boxes, one turned an eighth), with an
-- intake collar, a strap, and a lit throat at the back. 'length' and
-- 'radius' are half-sizes.
-- Where an engine's fire leaves the hull: the middle of its mouth and
-- half the mouth's width, in the design's own units. The fire goes aft.
export type Exhaust = { at: vector, radius: number }

-- (The exhausts of the design being drawn: Hull.Build takes them from here.)
local exhausts: { Exhaust } = {}
local function exhaust(at: vector, radius: number)
  table.insert(exhausts, { at = at, radius = radius })
end

-- A hull that was modelled in another program (Game/View/Imported): the
-- drawing of it is the reading of its file from resource/model, and its
-- engines are where the file has fire.
local function vessel(file: string, options: Imported.Options?): (b: Builder) -> ()
  return function(b: Builder)
    local model = Imported.Load(file, options)
    Imported.Draw(b, model)
    for _, engine in model.engines do
      exhaust(v(engine.x, engine.y, engine.z), engine.radius)
    end
  end
end

local function nacelle(b: Builder, center: vector, length: number, radius: number)
  block(b, PLATING, center, v(radius, radius, length), nil, 0.16)
  block(b, PLATING, center + v(0, 0, -length * 0.04), v(radius * 0.94, radius * 0.94, length * 0.9), v(0, 0, math.pi / 4), 0.16)
  block(b, FRAME, center + v(0, 0, length * 0.96), v(radius * 1.10, radius * 1.10, length * 0.07), nil, 0.2)
  block(b, FRAME, center + v(0, 0, length * 0.1), v(radius * 1.08, radius * 1.08, length * 0.05), v(0, 0, math.pi / 4), 0.2)
  block(b, PATCH, center + v(radius * 0.72, radius * 0.72, length * 0.35), v(radius * 0.35, radius * 0.35, length * 0.3), v(0, 0, math.pi / 4), 0.12)
  -- the throat
  block(b, FRAME, center + v(0, 0, -length * 1.06), v(radius * 0.86, radius * 0.86, length * 0.16), nil, 0.22)
  block(b, FRAME, center + v(0, 0, -length * 1.08), v(radius * 0.80, radius * 0.80, length * 0.12), v(0, 0, math.pi / 4), 0.22)
  block(b, GLOW, center + v(0, 0, -length * 1.235), v(radius * 0.60, radius * 0.60, length * 0.02), v(0, 0, math.pi / 8), 0.5)
  exhaust(center + v(0, 0, -length * 1.26), radius * 0.60)
end

-- A tank strapped on: a rounded drum lying along z, with two bands.
local function tank(b: Builder, center: vector, radius: number, length: number, part: number?)
  block(b, part or PATCH, center, v(radius, radius, length), nil, 0.55)
  block(b, FRAME, center + v(0, 0, length * 0.45), v(radius * 1.06, radius * 1.06, length * 0.06), nil, 0.3)
  block(b, FRAME, center + v(0, 0, -length * 0.45), v(radius * 1.06, radius * 1.06, length * 0.06), nil, 0.3)
end

-- A mast: a pole with spars across it and a vane or two.
local function mast(b: Builder, foot: vector, height: number, lean: number)
  local top = foot + v(lean, height, -height * 0.12)
  beam(b, FRAME, foot, top, height * 0.035, 0.1)
  for index, share in { 0.45, 0.72, 0.92 } do
    local at = foot + (top - foot) * share
    local reach = height * (0.26 - 0.06 * index)
    beam(b, FRAME, at + v(-reach, 0, 0), at + v(reach, 0, 0), height * 0.018, 0.1)
  end
  block(b, PATCH, foot + (top - foot) * 0.6 + v(0, 0, -height * 0.10), v(height * 0.012, height * 0.16, height * 0.08), nil, 0.1)
end

-- A row of lit ports along z.
local function ports(b: Builder, from: vector, to: vector, count: number, size: number)
  for index = 1, count do
    block(b, GLOW, from + (to - from) * ((index - 0.5) / count), v(size * 0.25, size, size * 1.6), nil, 0.3)
  end
end

-- A block of launch cells: a box with a grid of hatches on its top.
local function silos(b: Builder, center: vector, half: vector, columns: number, rows: number)
  block(b, PLATING, center, half, nil, 0.06)
  block(b, FRAME, center + v(0, half.y, 0), v(half.x * 0.94, half.y * 0.04, half.z * 0.94), nil, 0.1)
  for column = 1, columns do
    for row = 1, rows do
      local x = (column - (columns + 1) / 2) * (1.8 * half.x / columns)
      local z = (row - (rows + 1) / 2) * (1.8 * half.z / rows)
      local lid = if (column + row) % 5 == 0 then PATCH else TRIM
      block(b, lid, center + v(x, half.y * 1.05, z), v(0.66 * half.x / columns, half.y * 0.035, 0.66 * half.z / rows), nil, 0.3)
    end
  end
end

-- Battlements along the top of a wall that runs along z: a row of
-- small blocks with gaps between.
local function battlements(b: Builder, from: vector, to: vector, count: number, size: number)
  for index = 1, count do
    if index % 3 ~= 0 then
      block(b, if index % 4 == 0 then PATCH else PLATING, from + (to - from) * ((index - 0.5) / count),
        v(size * 0.8, size, size * 1.1 * vector.magnitude(to - from) / count / size * 0.36), nil, 0.12)
    end
  end
end

-- ---------------------------------------------------------------------
-- The Vessari

-- The Javelin, a missile frigate. A long armoured box on a spine of
-- girders (which shows where the body is in two lengths), the bow a
-- separate block set a little to one side, a small
-- bridge up on the starboard shoulder, a missile rack under the port
-- bow and another on the starboard flank, tanks along the port quarter,
-- and an engine pod out on a strut each side: the starboard one bigger,
-- higher and further forward than the port one.
local function javelin(b: Builder)
  -- the spine, showing between the blocks and out past the stern
  truss(b, v(0, -0.02, -0.94), v(0, -0.02, 1.02), 0.22, 8)
  truss(b, v(0, -0.02, -0.94), v(0, -0.02, 1.02), 0.20, 8, v(1, 0, 0))

  -- the body, in two unequal lengths with the frame showing between
  block(b, PLATING, v(0.00, 0.02, 0.22), v(0.27, 0.23, 0.36))
  block(b, PLATING, v(-0.02, 0.00, -0.42), v(0.24, 0.26, 0.20))
  block(b, FRAME, v(0.00, 0.00, -0.17), v(0.19, 0.18, 0.06))
  -- armour hung on the sides, no two slabs alike
  block(b, PATCH, v(-0.295, 0.04, 0.30), v(0.022, 0.19, 0.24), v(0, 0, 0.05))
  block(b, PLATING, v(-0.290, -0.02, -0.02), v(0.020, 0.15, 0.10), v(0, 0, -0.04))
  block(b, PLATING, v(0.300, 0.09, 0.02), v(0.022, 0.12, 0.17), v(0, 0, -0.06))
  block(b, PATCH, v(0.295, -0.11, 0.36), v(0.020, 0.09, 0.19))
  block(b, PLATING, v(0.02, 0.265, 0.10), v(0.20, 0.022, 0.25), v(0, 0.03, 0))
  block(b, PATCH, v(-0.05, -0.245, 0.24), v(0.17, 0.020, 0.21))

  -- the bow: its own block, off to starboard and a little low
  block(b, PLATING, v(0.05, -0.04, 0.86), v(0.19, 0.17, 0.24))
  block(b, PATCH, v(0.05, -0.04, 1.11), v(0.15, 0.13, 0.04), nil, 0.2)
  block(b, FRAME, v(0.05, -0.04, 1.17), v(0.10, 0.09, 0.03), nil, 0.2)
  beam(b, FRAME, v(-0.06, 0.02, 1.15), v(-0.10, 0.06, 1.55), 0.008, 0.1)
  beam(b, FRAME, v(0.14, -0.10, 1.15), v(0.16, -0.12, 1.42), 0.006, 0.1)

  -- the bridge, up on the starboard shoulder
  block(b, PATCH, v(0.15, 0.20, 0.80), v(0.10, 0.075, 0.15), nil, 0.14)
  block(b, GLOW, v(0.15, 0.225, 0.955), v(0.075, 0.020, 0.006), nil, 0.3)
  block(b, FRAME, v(0.15, 0.285, 0.76), v(0.06, 0.012, 0.08))

  -- a pylon under the port bow, for a launcher to hang from (its twin
  -- stands on the back; the other pair goes on the flanks)
  block(b, FRAME, v(-0.20, -0.125, 0.80), v(0.07, 0.012, 0.16), nil, 0.2)
  beam(b, FRAME, v(-0.20, -0.12, 0.70), v(-0.10, -0.03, 0.70), 0.014)
  beam(b, FRAME, v(-0.20, -0.12, 0.92), v(-0.10, -0.03, 0.92), 0.014)

  -- tanks strapped along the port quarter
  tank(b, v(-0.32, -0.12, -0.44), 0.075, 0.19)
  tank(b, v(-0.33, 0.07, -0.47), 0.06, 0.15, PLATING)
  conduit(b, { v(-0.33, 0.07, -0.30), v(-0.33, 0.12, -0.20), v(-0.26, 0.16, -0.08), v(-0.26, 0.16, 0.10) }, 0.012)

  -- conduits over the back, and down the starboard side
  conduit(b, { v(0.09, 0.30, 0.66), v(0.09, 0.30, 0.34), v(0.12, 0.30, 0.20), v(0.12, 0.30, -0.36), v(0.12, 0.24, -0.60) }, 0.013)
  conduit(b, { v(0.03, 0.30, 0.34), v(0.03, 0.30, -0.14), v(-0.06, 0.30, -0.24), v(-0.06, 0.28, -0.62) }, 0.010)
  conduit(b, { v(0.29, -0.20, 0.52), v(0.29, -0.24, 0.10), v(0.27, -0.26, -0.50) }, 0.012)

  -- engineering, and the main engine at the stern
  block(b, PLATING, v(0.00, -0.02, -0.80), v(0.20, 0.21, 0.16))
  block(b, FRAME, v(0.00, -0.02, -1.00), v(0.15, 0.15, 0.07), nil, 0.2)
  block(b, FRAME, v(0.00, -0.02, -1.02), v(0.14, 0.14, 0.05), v(0, 0, math.pi / 4), 0.2)
  block(b, GLOW, v(0.00, -0.02, -1.085), v(0.105, 0.105, 0.012), v(0, 0, math.pi / 8), 0.5)
  exhaust(v(0.00, -0.02, -1.10), 0.105)
  ports(b, v(0.205, 0.05, -0.90), v(0.205, 0.05, -0.70), 3, 0.014)

  -- the engine pods: starboard the bigger, higher and further forward
  nacelle(b, v(0.74, 0.14, -0.30), 0.40, 0.125)
  truss(b, v(0.26, 0.06, -0.20), v(0.62, 0.13, -0.24), 0.12, 3, v(0, 0, 1))
  beam(b, FRAME, v(0.24, -0.08, -0.56), v(0.66, 0.08, -0.46), 0.016)
  conduit(b, { v(0.26, 0.14, -0.10), v(0.45, 0.19, -0.12), v(0.62, 0.22, -0.16) }, 0.010)
  nacelle(b, v(-0.66, -0.13, -0.58), 0.31, 0.10)
  truss(b, v(-0.24, -0.08, -0.62), v(-0.57, -0.12, -0.60), 0.10, 2, v(0, 0, 1))
  beam(b, FRAME, v(-0.22, 0.10, -0.30), v(-0.60, -0.06, -0.44), 0.014)

  -- a mast over the back, a fin under the keel
  mast(b, v(-0.08, 0.27, -0.38), 0.50, -0.03)
  block(b, PLATING, v(0.04, -0.37, -0.05), v(0.016, 0.13, 0.26), v(0, 0.10, 0))
  beam(b, FRAME, v(0.04, -0.26, 0.18), v(0.04, -0.48, 0.02), 0.010)
end

-- The Courier, the ship anyone can have (and a pirate scout's too): a
-- plain box on a spine, the cockpit at the front, a cargo box slung
-- under, an engine pod each side on a short strut. (A v0, like all of
-- these: the quickest thing that reads as what it is.)
local function courier(b: Builder)
  truss(b, v(0, 0, -0.80), v(0, 0, 0.70), 0.18, 6)
  block(b, PLATING, v(0, 0.02, 0.10), v(0.24, 0.20, 0.42))
  block(b, PLATING, v(0, -0.02, -0.52), v(0.20, 0.18, 0.22))
  block(b, FRAME, v(0, 0.0, -0.31), v(0.15, 0.14, 0.04))
  block(b, PATCH, v(0, 0.06, 0.66), v(0.17, 0.14, 0.18), nil, 0.2)
  block(b, GLOW, v(0, 0.10, 0.842), v(0.11, 0.035, 0.006), nil, 0.3)
  block(b, TRIM, v(0, 0.225, 0.10), v(0.08, 0.010, 0.36))
  block(b, PATCH, v(0, -0.30, 0.06), v(0.18, 0.10, 0.30), nil, 0.08)
  ports(b, v(0.245, 0.06, -0.10), v(0.245, 0.06, 0.30), 3, 0.014)
  for _, side in { -1, 1 } do
    nacelle(b, v(side * 0.46, 0.0, -0.44), 0.30, 0.10)
    truss(b, v(side * 0.22, 0, -0.42), v(side * 0.37, 0, -0.44), 0.09, 2, v(0, 0, 1))
  end
  mast(b, v(-0.08, 0.22, -0.30), 0.34, 0.02)
end

-- The Dray, a freighter: anybody's, and the biggest thing a pilot flies
-- that is not a warship. A long keel girder with cargo racked along it
-- in two tiers, six bays to a side, no two rows quite alike; a
-- bulkhead across the bow with the bridge high on it; tanks slung
-- under; and a wall of engines across the stern. Nothing to fight
-- with, and nowhere to put it. (A v0: it reads as what it is.)
local function dray(b: Builder)
  local stern, bow = -0.92, 0.92
  truss(b, v(0, -0.08, stern), v(0, -0.08, bow), 0.16, 12)
  truss(b, v(0, 0.24, stern + 0.10), v(0, 0.24, bow - 0.22), 0.09, 9)
  local bays = 6
  local first, last = stern + 0.20, bow - 0.24
  local length = (last - first) / bays
  for bay = 1, bays do
    local z = first + (bay - 0.5) * length
    local tall = 0.13 + 0.03 * ((bay * 5) % 3)
    for _, side in { -1, 1 } do
      local low = if (bay + (if side > 0 then 1 else 0)) % 3 == 0 then PATCH else PLATING
      local high = if (bay + (if side > 0 then 0 else 2)) % 4 == 0 then TRIM else PLATING
      block(b, low, v(side * 0.27, -0.12, z), v(0.17, 0.17, length * 0.44), nil, 0.06)
      block(b, FRAME, v(side * 0.27, -0.12, z), v(0.176, 0.024, length * 0.45), nil, 0.1)
      block(b, high, v(side * 0.24, 0.06 + tall, z + 0.01 * side), v(0.14, tall, length * 0.41), nil, 0.06)
    end
    -- (a frame across at the end of each bay, low and high)
    beam(b, FRAME, v(-0.45, -0.30, z + length / 2), v(0.45, -0.30, z + length / 2), 0.020, 0.08)
    beam(b, FRAME, v(-0.39, 0.06, z + length / 2), v(0.39, 0.06, z + length / 2), 0.015, 0.08)
  end
  -- the bow: a bulkhead across the front of the racks, the bridge high on it, a mast
  block(b, PLATING, v(0, 0.04, bow - 0.13), v(0.44, 0.34, 0.07), nil, 0.08)
  block(b, PATCH, v(0, 0.46, bow - 0.15), v(0.22, 0.085, 0.12), nil, 0.2)
  block(b, GLOW, v(0, 0.48, bow - 0.028), v(0.17, 0.022, 0.006), nil, 0.3)
  block(b, TRIM, v(0, 0.385, bow - 0.15), v(0.23, 0.012, 0.125))
  ports(b, v(0.445, 0.10, bow - 0.17), v(0.445, 0.10, bow - 0.09), 2, 0.012)
  mast(b, v(-0.12, 0.54, bow - 0.20), 0.30, 0.03)
  -- the engines: a wall across the stern, four mouths
  block(b, PLATING, v(0, 0.0, stern + 0.07), v(0.46, 0.36, 0.11), nil, 0.08)
  for _, x in { -0.31, -0.105, 0.105, 0.31 } do
    block(b, FRAME, v(x, 0.0, stern - 0.07), v(0.085, 0.17, 0.06), nil, 0.25)
    block(b, GLOW, v(x, 0.0, stern - 0.135), v(0.06, 0.13, 0.008), nil, 0.5)
    exhaust(v(x, 0.0, stern - 0.145), 0.075)
  end
  -- tanks under the keel, and a conduit along the back
  tank(b, v(0, -0.40, stern + 0.42), 0.085, 0.28)
  tank(b, v(0, -0.40, 0.22), 0.075, 0.22, PLATING)
  conduit(b, { v(0.05, 0.33, stern + 0.2), v(0.05, 0.33, bow - 0.3), v(0.10, 0.39, bow - 0.24) }, 0.013)
end

-- ---------------------------------------------------------------------
-- Hulls in the manner of the engine's first generator
-- (Item/ShipType/Generate): a few big plates with their edges well
-- eased, laid in rows along the hull with a slighter plate through each
-- row, every one of them there again on the other side, a broad flat
-- deck under them, and the whole then bent by two warps: one that humps
-- the middle of it up and lets the sides fall away, one that spreads it
-- apart behind the bow. They are drawn in the generator's own units, six
-- to a hull's one. (The project owner, 2026-11-12: the engine's old
-- hulls looked better than the working ships drawn as boxes on girders.
-- So those are drawn this way.)

local GROWN = 1 / 6
local EASED = 0.25      -- how far the generator eased a plate's edges
-- (Plates' 'fine' for such a hull: its plates are few and big, and all
-- but the smallest have their edges eased finely)
local MANNER_FINE = 0.04

-- The sizes a generated hull comes in, 1 to 8: the generator's own
-- measure of a hull (the root of its mass, more or less). It grows two
-- plates and the root of this more, and from ten up lays a broad deck
-- under every plate. (It made a frigate at about 5, and the biggest
-- hull a pilot flew at about 18.)
Hull.SIZES = { 1, 4, 9, 12, 16, 25, 36, 49 }

-- How many plates the generator grows at a size, and whether with decks.
function Hull.GrownSize(size: number): (number, boolean)
  local measure = Hull.SIZES[size] or Hull.SIZES[2]
  return 2 + math.floor(math.sqrt(measure)), measure >= 10
end

-- The two warps, as one bend and the way back (Plates.Bend). 'spread':
-- how far each side is pushed out; 'bow': from where along z that falls
-- off toward the nose; 'hump': how far the middle is lifted, out to
-- 'crown' either side of the centre line. (The generator's own: 0.5
-- from 1.0, and 1.0 out to 1.25.)
-- ('taper': over how long the spread falls off, squared; a quarter, if
-- not said, which is abrupt: the generator's.)
-- ('wedge': the share of its width the hull keeps at its bow, narrowing
-- evenly from its stern, which makes a triangle of it from above; and
-- 'thin' the share of its height it keeps there. 1, if not said: the
-- generator narrowed nothing. 'aft' and 'fore' are where the hull's own
-- stern and bow are, which the growing fills in.)
-- ('spindle': the share of its girth a thing keeps at both its ends,
-- swelling to all of it at its middle: a tower's. Not, if not said.)
type Warps = { spread: number, bow: number, hump: number, crown: number, taper: number?, wedge: number?, thin: number?,
  aft: number?, fore: number?, spindle: number? }
type Bend = (p: vector) -> vector
local OLD: Warps = { spread = 0.5, bow = 1.0, hump = 1.0, crown = 1.25 }

-- A style: the generator's own numbers, which it never varied. With
-- other numbers the same growing makes another family of hulls.
export type Style = {
  name: string,
  -- The most plates it lays in a row along the hull (its own: 5).
  rows: number,
  -- Whether a row stops where the hull may reach no further (its own
  -- ran on past, which is where its long thin hulls come from).
  held: boolean,
  -- How far the hull may reach each way from its middle (3, 2, 6).
  bound: vector,
  -- The two plates it starts from, as half-sizes: one across, one along.
  cross: { vector },
  -- How far a plate's edges are eased (0.25).
  eased: number,
  warps: Warps,
  -- A hull that is not the same on both sides (the generator's always
  -- were). 'lop': the chance that what is grown off the hull is grown
  -- on one side of it only, and everything grown off that with it.
  -- 'slip': how far along the hull, at most, one whole side is slid
  -- from the other. 'less': the least that the lighter side may be of
  -- the heavier (it is the same plates, made that much smaller and
  -- drawn in toward the middle). 'boom': the chance of a long pod held
  -- out on struts from the heavier side. None of them, if not said.
  lop: number?,
  slip: number?,
  less: number?,
  boom: number?,
  -- A flat deck under the whole of it from stern to bow, which a wedge
  -- makes a triangle of: how far past the grown plates it reaches each
  -- side (1: no further than they), and how thick it is. By the seed
  -- there are smaller ones on it, and under it. None, if not said.
  deck: { reach: number, thick: number }?,
  -- The same kind of hull with far more left to the seed (the owner,
  -- 2026-11-15, of the first: "really good, but they are too same-y.
  -- There needs to be more noise/variety in them"): how sharp its point
  -- and how thin its bow, what plan its deck has (whole, forked, a hull
  -- with wings, a swallowtail), what stands on it and where, what hangs
  -- under it, and small panels and dark lines over its deck. 'reach'
  -- and 'thick' as a deck's. None, if not said.
  wedges: { reach: number, thick: number }?,
}

-- The styles there are, the generator's own first. (All but that one
-- are first drafts, for the owner's eye: 'stout' keeps its rows short
-- and inside its bounds, 'broad' is low and wide with more of a hump,
-- 'tall' is narrow and deep, 'spear' long with a nose drawn out, 'slab'
-- flat with hard edges, 'soft' rounded. And two the owner asked for by
-- name, 2026-11-15: 'triangular', a flat hull broad at the stern that
-- comes to a point at the bow, and 'asymmetrical', the generator's own
-- hull with one side of it not the other's twin. And of those, the same
-- day: 'triangular_v2', the triangle with more left to the seed; and
-- any style at all with its sides unalike, Hull.ASYM.)
Hull.STYLES = {
  { name = "old", rows = 5, held = false, bound = v(3, 2, 6), cross = { v(2.0, 0.5, 0.5), v(0.5, 1.0, 2.0) }, eased = 0.25, warps = OLD },
  { name = "stout", rows = 3, held = true, bound = v(3, 2, 5), cross = { v(2.0, 0.5, 0.5), v(0.5, 1.0, 2.0) }, eased = 0.25, warps = OLD },
  { name = "broad", rows = 3, held = true, bound = v(4.5, 1.5, 5), cross = { v(2.6, 0.4, 0.6), v(0.6, 0.8, 2.0) }, eased = 0.25,
    warps = { spread = 0.7, bow = 1.0, hump = 1.3, crown = 1.6, taper = 1.5 } },
  { name = "tall", rows = 3, held = true, bound = v(2.2, 3.2, 5.5), cross = { v(1.4, 0.6, 0.5), v(0.5, 1.5, 2.0) }, eased = 0.25,
    warps = { spread = 0.3, bow = 1.5, hump = 0.5, crown = 1.0 } },
  { name = "spear", rows = 4, held = true, bound = v(2.2, 1.6, 7), cross = { v(1.5, 0.4, 0.5), v(0.45, 0.8, 2.6) }, eased = 0.25,
    warps = { spread = 0.6, bow = -1.0, hump = 0.8, crown = 0.9, taper = 9 } },
  { name = "slab", rows = 3, held = true, bound = v(3.5, 1.6, 5.5), cross = { v(2.2, 0.4, 0.6), v(0.6, 0.8, 2.2) }, eased = 0.07,
    warps = { spread = 0.5, bow = 0.5, hump = 0.25, crown = 2.0, taper = 4 } },
  { name = "soft", rows = 3, held = true, bound = v(3, 2.2, 5), cross = { v(2.0, 0.6, 0.6), v(0.6, 1.1, 2.0) }, eased = 0.5,
    warps = { spread = 0.5, bow = 1.0, hump = 1.2, crown = 1.0, taper = 1.5 } },
  { name = "triangular", rows = 3, held = true, bound = v(3.2, 1.5, 5), cross = { v(2.2, 0.45, 0.8), v(0.7, 0.8, 2.6) }, eased = 0.12,
    warps = { spread = 0.1, bow = -2.0, hump = 0.3, crown = 1.8, taper = 12, wedge = 0.06, thin = 0.55 },
    deck = { reach = 1.12, thick = 0.26 } },
  { name = "asymmetrical", rows = 4, held = true, bound = v(3.2, 2, 5.5), cross = { v(2.0, 0.5, 0.5), v(0.5, 1.0, 2.0) }, eased = 0.25,
    warps = OLD, lop = 0.45, slip = 1.0, less = 0.55, boom = 0.45 },
  -- (the triangle again, with far more left to the seed: Style.wedges)
  { name = "triangular_v2", rows = 4, held = true, bound = v(3.4, 1.6, 5.2), cross = { v(2.2, 0.45, 0.8), v(0.7, 0.8, 2.6) }, eased = 0.12,
    warps = { spread = 0.1, bow = -2.0, hump = 0.3, crown = 1.8, taper = 12, wedge = 0.06, thin = 0.55 },
    wedges = { reach = 1.1, thick = 0.26 } },
} :: { Style }

-- Any style can be had with its two sides not each other's twin: its
-- name with this after it ("stout+asym"). (The owner, 2026-11-15, of
-- the style that was only that: "almost like a variant of stout or one
-- of the other styles. Is it possible to add asymmetry to the others
-- with e.g. a symmetry toggle?") It is the style's own numbers with the
-- 'asymmetrical' style's lop, slip, less and boom.
Hull.ASYM = "+asym"
local lopsided: { [string]: Style } = {}

-- The style of a name: the generator's own, if there is none of that name.
local function styleOf(name: string?): Style
  local base, asym = name, false
  if name and #name > #Hull.ASYM and string.sub(name, -#Hull.ASYM) == Hull.ASYM then
    base, asym = string.sub(name, 1, #name - #Hull.ASYM), true
  end
  local found = Hull.STYLES[1]
  for _, style in Hull.STYLES do
    if style.name == base then
      found = style
    end
  end
  if not asym then
    return found
  end
  local kept = lopsided[found.name]
  if kept == nil then
    kept = table.clone(found)
    kept.name = found.name .. Hull.ASYM
    kept.lop, kept.slip, kept.less, kept.boom = found.lop or 0.45, found.slip or 1.0, found.less or 0.55, found.boom or 0.45
    lopsided[found.name] = kept
  end
  return kept
end

local function warped(w: Warps, middle: vector?): (Bend, Bend)
  local taper = w.taper or 0.25
  local function out(z: number): number
    return w.spread * math.exp(-(math.max(0, z - w.bow) ^ 2) / taper)
  end
  local function lift(x: number): number
    -- (less half of it: the hull stays about its own middle)
    return w.hump * (math.exp(-math.max(0, math.abs(x) - w.crown)) - 0.5)
  end
  -- (a wedge: how much of its width, and of its height, the hull has
  -- left at z, from all of it at its stern to its shares at its bow)
  local wedge, thin = w.wedge or 1, w.thin or 1
  local aft, fore = w.aft or -6, w.fore or 6
  local function along(z: number): number
    return math.clamp((z - aft) / math.max(0.01, fore - aft), 0, 1)
  end
  -- (a spindle: how much of its girth the thing has left, so far along)
  local spindle = w.spindle
  local function girth(t: number): number
    return if spindle then 1 - (1 - spindle) * math.abs(2 * t - 1) ^ 1.7 else 1
  end
  local off = middle or v(0, 0, 0)
  local function bend(p: vector): vector
    local x, y, z = p.x / GROWN, p.y / GROWN, p.z / GROWN
    local side = if x > 0 then 1 elseif x < 0 then -1 else 0
    local t = along(z)
    local round = girth(t)
    local narrowed = x * (1 - (1 - wedge) * t) * round
    return vector.create(narrowed + side * out(z), y * (1 - (1 - thin) * t) * round + lift(narrowed), z) * GROWN - off
  end
  local function unbend(p: vector): vector
    p += off
    local x, y, z = p.x / GROWN, p.y / GROWN, p.z / GROWN
    local wide = out(z)
    local t = along(z)
    local round = girth(t)
    -- (what lies between the two halves was on the centre line)
    local was = if x > wide then x - wide elseif x < -wide then x + wide else 0
    return vector.create(was / ((1 - (1 - wedge) * t) * round), (y - lift(was)) / ((1 - (1 - thin) * t) * round), z) * GROWN
  end
  return bend, unbend
end

-- (The bend of the design being drawn: its engines' fire is put where
-- the bend takes it.)
local bending: Bend = function(p: vector): vector
  return p
end

-- Draw what follows in this manner, bent so.
local function manner(b: Builder, w: Warps)
  local bend, unbend = warped(w)
  Plates.Bend(b, bend, unbend)
  bending = bend
end

-- A plate on the centre line, in the generator's units.
local function mid(b: Builder, part: number, center: vector, half: vector, bevel: number?)
  block(b, part, center * GROWN, half * GROWN, nil, bevel or EASED)
end

-- A plate and its twin on the other side.
local function twin(b: Builder, part: number, center: vector, half: vector, bevel: number?)
  block(b, part, center * GROWN, half * GROWN, nil, bevel or EASED)
  block(b, part, center * v(-1, 1, 1) * GROWN, half * (0.99 * GROWN), nil, bevel or EASED)
end

-- A row of plates along the hull, as the generator laid them: 'count'
-- of them a plate's length apart, with a slighter one through each that
-- joins it to the next; and their twins.
local function ribs(b: Builder, part: number, center: vector, half: vector, count: number, through: number?)
  for index = 0, count - 1 do
    local at = center + v(0, 0, index * 3 * half.z)
    twin(b, part, at, half)
    twin(b, through or FRAME, at, half * v(0.5, 0.5, 1.5))
  end
end

-- An engine: a housing, a dark throat let into the back of it and the
-- fire in that. 'center' is the middle of the housing and 'half' its
-- half-size; with 'both', its twin on the other side too.
local function jet(b: Builder, center: vector, half: vector, both: boolean?)
  local back = center - v(0, 0, half.z)
  local throat = v(half.x * 0.80, half.y * 0.72, 0.24)
  local fire = v(half.x * 0.62, half.y * 0.52, 0.03)
  local put: (b: Builder, part: number, center: vector, half: vector, bevel: number?) -> () = if both then twin else mid
  put(b, PLATING, center, half)
  put(b, FRAME, back - v(0, 0, 0.10), throat, 0.3)
  put(b, GLOW, back - v(0, 0, 0.36), fire, 0.5)
  local sides: { number } = if both then { 1, -1 } else { 1 }
  for _, side in sides do
    exhaust(bending((back - v(0, 0, 0.40)) * v(side, 1, 1) * GROWN), math.min(fire.x, fire.y) * 1.25 * GROWN)
  end
end

-- A bridge: a low house with a lit window across its front.
local function cabin(b: Builder, center: vector, half: vector)
  mid(b, PATCH, center, half, 0.3)
  mid(b, GLOW, center + v(0, half.y * 0.25, half.z + 0.005), v(half.x * 0.72, half.y * 0.26, 0.03), 0.4)
end

-- What the generator grows from a seed: 'steps' plates grown off a
-- cross of two, each in a row of one to five along the hull with a
-- slighter one through it, and (with 'decks') a broad flat one under
-- each. The draws are the generator's own, in its order. Each plate
-- stands for itself and its twin on the other side; 'middle' is where
-- the middle of the hull comes to once it is bent (the generator
-- centred its hulls), and 'across' how far it then reaches each way.
-- ('single': it has no twin. Only in a style whose hulls are not the
-- same on both sides.) 'warps' are the style's, with where this hull's
-- own stern and bow are.
export type Plate = { center: vector, size: vector, part: number, single: boolean? }
type Growth = { plates: { Plate }, middle: vector, across: vector, style: Style, warps: Warps, seed: number }

local function growth(seed: number, steps: number, decks: boolean, style: Style): Growth
  local rng = RNG_MTG(Int.Signed(seed + 102))
  -- ('side': 0 for a plate that has its twin, 1 or -1 for one that is on that side of the hull only)
  type Box = { center: vector, size: vector, side: number }
  local boxes: { Box } = {
    { center = v(0, 0, 0), size = style.cross[1], side = 0 },
    { center = v(0, 0, 0), size = style.cross[2], side = 0 },
  }
  local slight: { Box } = {}
  local lower, upper = -style.bound, style.bound
  local axes = { v(-1, 0, 0), v(1, 0, 0), v(0, -1, 0), v(0, 1, 0), v(0, 0, -1), v(0, 0, 1) }
  -- A hull that is not the same on both sides: which side has the
  -- more of it, and how far the other is slid along. (By dice of their
  -- own: the generator's draws are what they always were, so a seed is
  -- the same hull in every style, as far as the style lets it be.)
  local lop, slip, less = style.lop or 0, 0, 1
  local lopped = 0
  local heavy = 1
  local dice: RNG? = nil
  if lop > 0 or (style.slip or 0) > 0 or style.less or style.boom then
    local own = RNG_MTG(Int.Signed(seed + 7001))
    heavy = if own:Int(2) == 0 then 1 else -1
    slip = (style.slip or 0) * own:Float(0.3, 1.0) * (if own:Int(2) == 0 then 1 else -1)
    less = if style.less then own:Float(style.less, math.min(1, style.less + 0.3)) else 1
    dice = own
  end
  for step = 1, steps do
    rng:Int(#boxes)
    local box = boxes[step]
    local dir = axes[rng:Int(6) + 1]
    local size = box.size * rng:Vec3(v(0.9, 0.9, 0.9), v(0.99, 0.99, 0.99))
    local center = vector.clamp(box.center + dir * (box.size + size), lower + size, upper - size)
    -- (what is grown off one side only is on that side only; and what
    -- is grown off both may be: then it is put by whichever of its
    -- plate and the plate's twin is on that side)
    local side = box.side
    if side == 0 and dice and dice:Float() < lop then
      side = if dice:Float() < 0.7 then heavy else -heavy
      center = v(side * math.abs(center.x), center.y, center.z)
      -- (one that lies across the centre line makes no side heavier)
      if math.abs(center.x) >= size.x then
        lopped += 1
      end
    end
    for row = 1, rng:Int(1, style.rows) do
      -- (a row that is held stops where the hull may reach no further)
      if style.held and row > 1 and center.z + size.z > upper.z then
        break
      end
      table.insert(boxes, { center = center, size = size, side = side })
      table.insert(slight, { center = center, size = size * v(0.5, 0.5, 1.5), side = side })
      center += size * v(0, 0, 3)
    end
  end
  local wide = v(1.25, 0.50, 2.00)
  local under = v(1, -0.5, 1)
  local plates: { Plate } = {}
  -- A box as the plates it is: itself and its twin; or, in a hull whose
  -- one side is slid along from the other, one each side, the one on
  -- the light side slid (not one that lies across the centre line: that
  -- is the hull's spine, and stays); or itself alone. And the deck
  -- under it the same way.
  local lopsided = slip ~= 0 or less ~= 1
  -- (where a plate is on the lighter side: drawn in toward the middle
  -- of the hull and made smaller, as all of that side is, and slid along)
  local function lighter(center: vector, size: vector): (vector, vector)
    return center * less + v(0, 0, slip), size * less
  end
  local function lay(box: Box, part: number, deck: number?)
    local across = math.abs(box.center.x) < box.size.x
    local function put(center: vector, size: vector, single: boolean?)
      table.insert(plates, { center = center, size = size, part = part, single = single })
      if decks and deck then
        table.insert(plates, { center = center * under, size = size * wide, part = deck, single = single })
      end
    end
    if box.side ~= 0 then
      if box.center.x * heavy < 0 and not across then
        local center, size = lighter(box.center, box.size)
        put(center, size, true)
      else
        put(box.center, box.size, true)
      end
    elseif not lopsided or across then
      put(box.center, box.size)
    else
      local out = math.abs(box.center.x)
      put(v(heavy * out, box.center.y, box.center.z), box.size, true)
      local center, size = lighter(v(-heavy * out, box.center.y, box.center.z), box.size * 0.99)
      put(center, size, true)
    end
  end
  for _, box in boxes do
    lay(box, PLATING, PATCH)
  end
  for _, box in slight do
    lay(box, FRAME, FRAME)
  end
  -- How far the plates reach, so far.
  local function reaches(): (vector, vector)
    local least, most = v(math.huge, math.huge, math.huge), v(-math.huge, -math.huge, -math.huge)
    for _, plate in plates do
      least, most = vector.min(least, plate.center - plate.size), vector.max(most, plate.center + plate.size)
      if not plate.single then
        least = vector.min(least, plate.center * v(-1, 1, 1) - plate.size)
        most = vector.max(most, plate.center * v(-1, 1, 1) + plate.size)
      end
    end
    return least, most
  end
  -- A boom: a long pod held out from the heavier side on two struts.
  -- (By the dice; and always where nothing else has made one side of
  -- the hull unlike the other.)
  if dice and style.boom and (dice:Float() < style.boom or lopped == 0) then
    local least, most = reaches()
    local edge = if heavy > 0 then most.x else -least.x
    local long = (most.z - least.z) / 2 * dice:Float(0.45, 0.75)
    local pod = v(dice:Float(0.4, 0.62), dice:Float(0.4, 0.7), long)
    local gap = dice:Float(0.3, 0.7)
    -- (astern of the middle, more often than not: it has an engine in its end)
    local at = v(heavy * (edge + gap + pod.x), dice:Float(-0.4, 0.4), (least.z + most.z) / 2 + dice:Float(-1, 0.6) * long * 0.5)
    table.insert(plates, { center = at, size = pod, part = PLATING, single = true })
    -- (a slighter plate through it, as every plate the generator laid had)
    table.insert(plates, { center = at, size = pod * v(0.5, 0.5, 1.25), part = FRAME, single = true })
    local reach = (edge + gap) / 2 + 0.3
    for _, along in { -0.45, 0.45 } do
      table.insert(plates, { center = v(heavy * reach, at.y, at.z + along * long), size = v(reach, pod.y * 0.45, 0.3), part = FRAME,
        single = true })
    end
  end
  -- The decks: one under the whole hull, from a little astern of it to
  -- a nose past its bow, and by the seed one or two smaller on that,
  -- from the stern forward, and one under it. (Each is one plate on the
  -- centre line: the wedge makes a triangle of it.)
  local deck = style.deck
  if deck then
    local own = RNG_MTG(Int.Signed(seed + 9001))
    local least, most = reaches()
    local half = math.max(most.x, -least.x) * deck.reach * own:Float(0.95, 1.15)
    local aft, fore = least.z - own:Float(0.1, 0.7), most.z + own:Float(0.4, 1.6)
    local long = (fore - aft) / 2
    -- (no slimmer than a dagger: a long hull has a deck broad enough for its length)
    half = math.max(half, long * own:Float(0.42, 0.62))
    local level = own:Float(-0.45, -0.1)
    local kind = own:Int(10)
    if kind < 3 then
      -- (forked: two decks with a gap between them, which the wedge closes at the bow)
      local gap = half * own:Float(0.12, 0.3)
      table.insert(plates, { center = v((half + gap) / 2, level, aft + long), size = v((half - gap) / 2, deck.thick, long), part = PLATING })
    else
      table.insert(plates, { center = v(0, level, aft + long), size = v(half, deck.thick, long), part = PLATING, single = true })
    end
    if kind >= 7 then
      -- (barbed: a broader deck over the after part of it)
      local back = long * own:Float(0.35, 0.5)
      table.insert(plates, { center = v(0, level, aft + back), size = v(half * own:Float(1.25, 1.5), deck.thick * 0.8, back), part = PLATING,
        single = true })
    end
    local top = level + deck.thick
    local span, far = half, long
    for _ = 1, own:Int(0, 2) do
      span, far = span * own:Float(0.6, 0.8), far * own:Float(0.62, 0.82)
      local thick = deck.thick * own:Float(0.9, 1.5)
      table.insert(plates, { center = v(0, top + thick, aft + own:Float(0, 0.3) + far), size = v(span, thick, far), part = PATCH,
        single = true })
      top += 2 * thick
    end
    -- (and more often than not a conning tower astern: a neck, and a bar across the head of it)
    if own:Int(10) < 7 then
      local at = aft + far * own:Float(0.25, 0.5)
      local neck = v(span * own:Float(0.18, 0.3), deck.thick * own:Float(1.4, 2.4), far * own:Float(0.1, 0.16))
      local high = math.max(top, most.y * 0.6)
      table.insert(plates, { center = v(0, high + neck.y, at), size = neck, part = PLATING, single = true })
      table.insert(plates, { center = v(0, high + 2 * neck.y + deck.thick * 0.6, at), size = v(neck.x * own:Float(2.2, 3.2), deck.thick * 0.6,
        neck.z * 0.8), part = PATCH, single = true })
    end
    if own:Int(2) == 0 then
      local thick = deck.thick * own:Float(0.8, 1.3)
      local belly, back = half * own:Float(0.4, 0.6), long * own:Float(0.5, 0.7)
      table.insert(plates, { center = v(0, level - deck.thick - thick, aft + own:Float(0.2, 0.8) + back), size = v(belly, thick, back),
        part = PATCH, single = true })
    end
  end
  -- The triangle with more left to the seed (Style.wedges). By dice of
  -- its own, so that nothing above draws otherwise for it.
  local sharp: number? = nil     -- how much of its width the hull has left at its bow, if the seed says
  local slim: number? = nil      -- and of its height
  local arch: number? = nil      -- and how far its back is humped
  local wedges = style.wedges
  if wedges then
    local own = RNG_MTG(Int.Signed(seed + 9101))
    local least, most = reaches()
    local T = wedges.thick
    -- (from a needle to a blunt snout; from a blade to a slab; flat-backed or arched)
    sharp, slim, arch = own:Float(0.04, 0.34), own:Float(0.38, 0.9), own:Float(0, 0.7)
    local half = math.max(most.x, -least.x) * wedges.reach * own:Float(0.9, 1.3)
    local aft, fore = least.z - own:Float(0.1, 0.9), most.z + own:Float(0.2, 1.8)
    local long = (fore - aft) / 2
    -- (from a dart to a broad delta)
    half = math.max(half, long * own:Float(0.35, 0.78))
    local level = own:Float(-0.5, -0.05)
    local middle = aft + long
    -- (in a hull whose sides are unalike, what stands on it stands to its heavier side)
    local lean = if dice then heavy else 0
    local function one(part: number, center: vector, size: vector)
      table.insert(plates, { center = center, size = size, part = part, single = true })
    end
    local function both(part: number, center: vector, size: vector)
      table.insert(plates, { center = center, size = size, part = part })
    end
    -- The plan of its deck.
    local plan = own:Int(10)
    if plan < 2 then
      -- (forked: two decks with a gap between, which the wedge closes at the bow)
      local gap = half * own:Float(0.12, 0.3)
      both(PLATING, v((half + gap) / 2, level, middle), v((half - gap) / 2, T, long))
    elseif plan < 5 then
      -- (a hull with wings: a slimmer deck the whole length, and a broad thin one about the after part of it)
      local inner = half * own:Float(0.42, 0.66)
      one(PLATING, v(0, level, middle), v(inner, T, long))
      local back = long * own:Float(0.38, 0.72)
      one(PLATING, v(0, level - T * own:Float(0.2, 0.9), aft + own:Float(0, 0.5) + back), v(half * own:Float(1.0, 1.35), T * 0.7, back))
    elseif plan < 7 then
      -- (a swallowtail: the whole deck, and a prong astern of each quarter)
      one(PLATING, v(0, level, middle), v(half, T, long))
      local prong = long * own:Float(0.14, 0.3)
      both(PLATING, v(half * own:Float(0.55, 0.72), level, aft - prong * 0.9), v(half * own:Float(0.2, 0.3), T * 0.9, prong))
    else
      one(PLATING, v(0, level, middle), v(half, T, long))
      if own:Int(3) == 0 then
        -- (barbed: a broader deck over the after part of it)
        local back = long * own:Float(0.3, 0.5)
        one(PLATING, v(0, level, aft + back), v(half * own:Float(1.2, 1.5), T * 0.8, back))
      end
    end
    -- Decks on the deck: none to three, each smaller than the one under
    -- it, and anywhere along it; now and then two ridges where one would be.
    local top = level + T
    local span, far = half, long
    for _ = 1, own:Int(0, 3) do
      span, far = span * own:Float(0.5, 0.85), far * own:Float(0.45, 0.85)
      local thick = T * own:Float(0.7, 1.7)
      local from = aft + own:Float(0, 1) * 2 * (long - far) * own:Float(0, 0.7)
      if own:Int(4) == 0 then
        both(PATCH, v(span * 0.62, top + thick, from + far), v(span * 0.3, thick, far))
      else
        one(PATCH, v(lean * span * 0.15, top + thick, from + far), v(span, thick, far))
      end
      top += 2 * thick
    end
    -- What stands on it: nothing, a conning tower, two of them abreast,
    -- or a spine along its back.
    local stands = own:Int(10)
    local high = math.max(top, most.y * 0.6)
    if stands >= 3 and stands < 6 then
      local at = aft + far * own:Float(0.2, 0.9)
      local neck = v(span * own:Float(0.16, 0.3), T * own:Float(1.4, 2.6), far * own:Float(0.08, 0.16))
      one(PLATING, v(lean * span * 0.4, high + neck.y, at), neck)
      one(PATCH, v(lean * span * 0.4, high + 2 * neck.y + T * 0.6, at), v(neck.x * own:Float(2.0, 3.2), T * 0.6, neck.z * 0.8))
    elseif stands >= 6 and stands < 8 then
      local at = aft + far * own:Float(0.2, 0.7)
      local neck = v(span * own:Float(0.1, 0.18), T * own:Float(1.2, 2.2), far * own:Float(0.08, 0.2))
      both(PLATING, v(span * own:Float(0.4, 0.7), high + neck.y, at), neck)
    elseif stands >= 8 then
      local ridge = v(span * own:Float(0.08, 0.16), T * own:Float(0.8, 1.8), far * own:Float(0.5, 0.95))
      one(PLATING, v(lean * span * 0.3, high + ridge.y, aft + own:Float(0.1, 0.6) + ridge.z), ridge)
    end
    -- (a bridge forward, as often as not: a low house with a lit front)
    if own:Int(5) < 2 then
      local at = aft + 2 * long * own:Float(0.5, 0.72)
      local house = v(half * own:Float(0.1, 0.2), T * own:Float(0.6, 1.1), long * own:Float(0.05, 0.1))
      one(PATCH, v(0, level + T + house.y, at), house)
      one(GLOW, v(0, level + T + house.y * 1.2, at + house.z + 0.01), v(house.x * 0.7, house.y * 0.25, 0.03))
    end
    -- Under it: nothing, a smaller deck, or a keel.
    local below = own:Int(4)
    if below == 0 then
      local thick = T * own:Float(0.8, 1.3)
      local back = long * own:Float(0.45, 0.72)
      one(PATCH, v(0, level - T - thick, aft + own:Float(0.2, 0.8) + back), v(half * own:Float(0.35, 0.6), thick, back))
    elseif below == 1 then
      local deep = T * own:Float(1.6, 3.2)
      local back = long * own:Float(0.3, 0.6)
      one(PLATING, v(0, level - T - deep, aft + own:Float(0.3, 1.2) + back), v(half * own:Float(0.05, 0.1), deep, back))
    end
    -- (pods at its quarters, now and then: on the heavier side alone, where it has one)
    if own:Int(5) < 2 then
      local pod = v(half * own:Float(0.08, 0.14), T * own:Float(1.2, 2.0), long * own:Float(0.22, 0.42))
      local at = v(half * own:Float(0.78, 0.98), level + own:Float(-0.3, 0.3) * T, aft + own:Float(-0.2, 0.3) * long + pod.z)
      if lean ~= 0 then
        one(PLATING, at * v(lean, 1, 1), pod)
        one(FRAME, at * v(lean, 1, 1), pod * v(0.5, 0.5, 1.2))
      else
        both(PLATING, at, pod)
        both(FRAME, at, pod * v(0.5, 0.5, 1.2))
      end
    end
    -- (blocks out of its stern, where engines go)
    for index = 1, own:Int(0, 3) do
      local block = v(half * own:Float(0.07, 0.16), T * own:Float(0.9, 1.6), long * own:Float(0.06, 0.14))
      both(PLATING, v(half * (index - 0.5) / 3.6, level + own:Float(-0.2, 0.4) * T, aft - block.z * 0.7), block)
    end
    -- Noise over its deck: small raised panels, and dark lines let into it.
    for _ = 1, own:Int(3, 9) do
      local panel = v(half * own:Float(0.05, 0.17), T * own:Float(0.14, 0.42), long * own:Float(0.03, 0.13))
      both(PATCH, v(half * own:Float(0.12, 0.8), level + T + panel.y, aft + 2 * long * own:Float(0.04, 0.8)), panel)
    end
    for _ = 1, own:Int(1, 3) do
      local line = long * own:Float(0.35, 0.85)
      both(FRAME, v(half * own:Float(0.15, 0.75), level + T + 0.012, aft + own:Float(0.05, 0.5) * long + line), v(half * 0.022, 0.02, line))
    end
  end
  -- (where its stern and bow are, for a style that narrows toward the bow)
  local warps = table.clone(style.warps)
  if sharp and slim and arch then
    warps.wedge, warps.thin, warps.hump = sharp, slim, arch
  end
  local aft, fore = math.huge, -math.huge
  for _, plate in plates do
    aft, fore = math.min(aft, plate.center.z - plate.size.z), math.max(fore, plate.center.z + plate.size.z)
  end
  warps.aft, warps.fore = aft, fore
  local plain = warped(warps)
  local low, high = v(math.huge, math.huge, math.huge), v(-math.huge, -math.huge, -math.huge)
  for _, plate in plates do
    for corner = 0, 7 do
      local way = v(if corner % 2 == 0 then -1 else 1, if (corner // 2) % 2 == 0 then -1 else 1, if corner // 4 == 0 then -1 else 1)
      local sides: { number } = if plate.single then { 1 } else { 1, -1 }
      for _, side in sides do
        local at = plain((plate.center + plate.size * way) * v(side, 1, 1) * GROWN)
        low, high = vector.min(low, at), vector.max(high, at)
      end
    end
  end
  return { plates = plates, middle = (low + high) / 2, across = high - low, style = style, warps = warps, seed = seed }
end

-- A hull as the generator grew one: its plates, and its bend about
-- where its middle comes to.
local function grown(b: Builder, g: Growth)
  for _, plate in g.plates do
    if plate.single then
      mid(b, plate.part, plate.center, plate.size, g.style.eased)
    else
      twin(b, plate.part, plate.center, plate.size, g.style.eased)
    end
  end
  local bend, unbend = warped(g.warps, g.middle)
  Plates.Bend(b, bend, unbend)
  bending = bend
end

-- The Prospector, a mining frigate: anybody's. A keel with a bar across
-- it at the shoulders, three ore pods a side along it on a broad deck,
-- and at the bow a blunt head, where its lasers stand, between two jaws
-- that reach out past it and turn in toward each other; the cabin on
-- the keel's back, a big engine at the end of the keel and one under
-- each shoulder. (A v0.)
local PROSPECTOR: Warps = { spread = 0.5, bow = 2.0, hump = 0.8, crown = 1.0 }
local function prospector(b: Builder)
  manner(b, PROSPECTOR)
  mid(b, PLATING, v(0, 0, -0.5), v(0.55, 0.85, 3.3))
  twin(b, PLATING, v(1.2, 0.0, -1.9), v(1.3, 0.45, 0.75))
  -- the pods, and the deck under them
  ribs(b, PLATING, v(1.3, 0.15, -2.6), v(0.7, 0.6, 0.55), 3)
  twin(b, PATCH, v(1.15, -0.55, -0.9), v(1.4, 0.24, 2.6))
  -- the head, and the jaws either side of it: a band of warning paint
  -- round each, a dark tip, and a lamp in the tip
  mid(b, PLATING, v(0, 0.0, 3.2), v(0.8, 0.6, 0.9))
  twin(b, PLATING, v(1.15, -0.15, 3.4), v(0.4, 0.34, 1.9))
  twin(b, TRIM, v(1.15, -0.15, 4.4), v(0.415, 0.355, 0.18), 0.2)
  twin(b, FRAME, v(1.15, -0.15, 5.35), v(0.3, 0.25, 0.35))
  twin(b, GLOW, v(1.15, -0.15, 5.72), v(0.15, 0.12, 0.03), 0.5)
  cabin(b, v(0, 0.95, 1.5), v(0.42, 0.22, 0.7))
  -- the engines
  jet(b, v(1.25, 0.0, -3.5), v(0.6, 0.42, 0.75), true)
  jet(b, v(0, 0.05, -4.0), v(0.5, 0.6, 0.7))
end

-- The Quarry, a mining barge: anybody's. A long keel on a broad deck,
-- four ore bins a side along it with their hatches in warning paint and
-- a rail of smaller plates outboard of them; across the bow a working
-- deck, where its three heads stand, over two short jaws; at the stern
-- a tower on the keel with the bridge on top of it, and three engines.
-- (A v0.)
local QUARRY: Warps = { spread = 0.5, bow = 3.0, hump = 1.0, crown = 1.25 }
local function quarry(b: Builder)
  manner(b, QUARRY)
  mid(b, PLATING, v(0, 0, -0.6), v(0.6, 1.0, 4.4))
  twin(b, PATCH, v(1.55, -0.62, -0.5), v(1.85, 0.28, 4.3))
  -- the bins and their hatches, and the rail
  ribs(b, PLATING, v(1.55, 0.2, -3.3), v(0.95, 0.68, 0.58), 4)
  for bin = 0, 3 do
    twin(b, TRIM, v(1.55, 0.89, -3.3 + bin * 1.74), v(0.6, 0.04, 0.36), 0.2)
  end
  ribs(b, PLATING, v(2.95, -0.25, -3.0), v(0.38, 0.38, 0.5), 4)
  -- the working deck: painted on top, a lamp along its face; and the jaws under it
  mid(b, PLATING, v(0, 0.0, 4.6), v(1.9, 0.5, 0.9))
  mid(b, TRIM, v(0, 0.505, 4.6), v(1.75, 0.02, 0.75), 0.1)
  mid(b, GLOW, v(0, -0.05, 5.505), v(1.2, 0.09, 0.03), 0.4)
  twin(b, PLATING, v(1.6, -0.45, 5.2), v(0.3, 0.3, 1.0))
  twin(b, FRAME, v(1.6, -0.45, 6.2), v(0.22, 0.22, 0.25))
  -- the tower at the stern, and the bridge
  mid(b, PLATING, v(0, 1.2, -3.6), v(0.5, 0.45, 0.9))
  cabin(b, v(0, 1.8, -3.4), v(0.8, 0.22, 0.7))
  -- the engines
  jet(b, v(1.6, -0.05, -4.9), v(0.8, 0.5, 0.8), true)
  jet(b, v(0, 0.0, -5.3), v(0.55, 0.7, 0.7))
end

-- The Mule, a hauler: anybody's, and the plainest there is. A long
-- spine on a deck, six holds a side along it and a tier of smaller ones
-- on their backs; a blunt head at the bow with the bridge on it; a
-- block across the stern, and two engines in that. (A v0.)
local MULE: Warps = { spread = 0.4, bow = 3.2, hump = 0.7, crown = 1.0 }
local function mule(b: Builder)
  manner(b, MULE)
  mid(b, PLATING, v(0, 0.05, -0.3), v(0.5, 0.8, 4.9))
  twin(b, PLATING, v(1.25, -0.9, -0.2), v(1.55, 0.2, 4.4))
  -- the holds, low and high
  ribs(b, PATCH, v(1.3, -0.15, -3.6), v(0.85, 0.7, 0.5), 6)
  ribs(b, PLATING, v(0.95, 0.72, -2.85), v(0.5, 0.3, 0.5), 5)
  -- the head, a lamp across its face, and the bridge on it
  mid(b, PLATING, v(0, 0.1, 5.0), v(1.1, 0.75, 0.8))
  mid(b, GLOW, v(0, 0.0, 5.805), v(0.7, 0.08, 0.03), 0.4)
  cabin(b, v(0, 1.0, 4.7), v(0.6, 0.22, 0.6))
  -- the stern, and its engines
  mid(b, PLATING, v(0, 0.0, -4.9), v(1.5, 0.8, 0.7))
  jet(b, v(1.0, 0.0, -5.6), v(0.6, 0.5, 0.6), true)
end

-- The Caravan, a hauler. A cage of heavy girders, wider at the keel
-- than at the top, with three cargo bays in it that do not match
-- (containers in two, drums in the third); the pilot in a pod out on a
-- stalk above the bow, off to starboard; a block of engines across the
-- stern behind slanted plates; a boom and tanks on the port side.
local function caravan(b: Builder)
  local keel, top = 0.56, 0.30         -- half-widths of the cage, low and high
  local low, high = -0.44, 0.44
  local stern, bow = -0.98, 1.02

  -- the cage: four rails the length of it, and a frame at each end of a bay
  for _, side in { -1, 1 } do
    beam(b, FRAME, v(side * keel, low, stern), v(side * keel, low, bow), 0.035, 0.08)
    beam(b, FRAME, v(side * top, high, stern), v(side * top, high, bow), 0.030, 0.08)
  end
  for frame = 0, 3 do
    local z = stern + (bow - stern) * frame / 3
    beam(b, FRAME, v(-keel, low, z), v(keel, low, z), 0.032, 0.08)
    beam(b, FRAME, v(-top, high, z), v(top, high, z), 0.028, 0.08)
    for _, side in { -1, 1 } do
      beam(b, FRAME, v(side * keel, low, z), v(side * top, high, z), 0.030, 0.08)
    end
    if frame < 3 then
      local next = stern + (bow - stern) * (frame + 1) / 3
      -- a brace across each side of each bay, leaning turn about
      for _, side in { -1, 1 } do
        if (frame + (if side > 0 then 1 else 0)) % 2 == 0 then
          beam(b, FRAME, v(side * keel, low, z), v(side * top, high, next), 0.018)
        else
          beam(b, FRAME, v(side * top, high, z), v(side * keel, low, next), 0.018)
        end
      end
    end
  end

  -- the bays, from the stern: containers, drums, containers
  local length = (bow - stern) / 3
  local function containers(z: number, lower: number, upper: number)
    block(b, lower, v(0, -0.21, z), v(0.47, 0.19, length * 0.43), nil, 0.06)
    block(b, upper, v(-0.04, 0.20, z + 0.02), v(0.31, 0.18, length * 0.40), nil, 0.06)
    block(b, FRAME, v(0, -0.21, z), v(0.475, 0.03, length * 0.44), nil, 0.1)
  end
  containers(stern + length * 0.5, PLATING, PATCH)
  containers(stern + length * 2.5, PATCH, PLATING)
  block(b, TRIM, v(0.10, 0.20, stern + length * 2.5 + 0.02), v(0.10, 0.185, length * 0.405), nil, 0.06)
  for index, x in { -0.34, 0.0, 0.34 } do
    tank(b, v(x, -0.22, stern + length * 1.5), 0.15, length * 0.40, if index == 2 then PLATING else PATCH)
  end
  tank(b, v(-0.14, 0.20, stern + length * 1.5), 0.13, length * 0.36, PLATING)
  tank(b, v(0.15, 0.22, stern + length * 1.5 - 0.03), 0.11, length * 0.30)

  -- the pilot's pod, on its stalk above the bow, off to starboard
  local pod = v(0.22, 0.74, bow + 0.34)
  beam(b, FRAME, v(0.12, high, bow - 0.30), pod + v(-0.02, -0.07, -0.10), 0.030, 0.1)
  beam(b, FRAME, v(0.24, high, bow - 0.02), pod + v(0, -0.07, -0.02), 0.018, 0.1)
  block(b, PATCH, pod, v(0.115, 0.085, 0.17), nil, 0.2)
  block(b, GLOW, pod + v(0, 0.02, 0.172), v(0.085, 0.022, 0.006), nil, 0.3)
  block(b, FRAME, pod + v(0, 0.095, -0.03), v(0.07, 0.012, 0.09))
  beam(b, FRAME, pod + v(0.03, 0.10, -0.08), pod + v(0.05, 0.36, -0.14), 0.007, 0.1)

  -- the bow: a plate across the front of the cage, and the docking ring
  block(b, PLATING, v(0, -0.06, bow + 0.05), v(0.42, 0.30, 0.035), v(0, 0.06, 0), 0.08)
  block(b, FRAME, v(-0.12, -0.10, bow + 0.10), v(0.13, 0.13, 0.04), v(0, 0, math.pi / 4), 0.25)
  block(b, GLOW, v(-0.12, -0.10, bow + 0.142), v(0.05, 0.05, 0.004), nil, 0.3)

  -- the engines: a block across the stern, behind plates set at a slant
  block(b, PLATING, v(0, -0.02, stern - 0.20), v(0.50, 0.34, 0.16), nil, 0.08)
  block(b, PLATING, v(0, 0.33, stern - 0.30), v(0.46, 0.022, 0.22), v(0, -0.38, 0), 0.08)
  block(b, PATCH, v(0, -0.38, stern - 0.30), v(0.52, 0.022, 0.22), v(0, 0.38, 0), 0.08)
  for index, x in { -0.32, 0.0, 0.32 } do
    block(b, FRAME, v(x, -0.03, stern - 0.40), v(0.12, 0.13, 0.07), nil, 0.25)
    block(b, GLOW, v(x, -0.03, stern - 0.482), v(0.085, 0.095, 0.010), nil, 0.5)
    exhaust(v(x, -0.03, stern - 0.495), 0.09)
  end
  conduit(b, { v(0.30, high + 0.03, stern + 0.10), v(0.30, high + 0.03, stern - 0.08), v(0.36, 0.30, stern - 0.12) }, 0.016)
  conduit(b, { v(-0.22, high + 0.03, bow - 0.10), v(-0.22, high + 0.03, stern + 0.30), v(-0.30, 0.30, stern - 0.10) }, 0.014)

  -- the port side: a boom with its gear, and tanks hung low
  beam(b, FRAME, v(-top, high, 0.20), v(-0.95, 0.62, 0.36), 0.022, 0.1)
  beam(b, FRAME, v(-keel, low, 0.30), v(-0.95, 0.62, 0.36), 0.014, 0.1)
  block(b, PATCH, v(-0.97, 0.60, 0.36), v(0.05, 0.05, 0.11), nil, 0.2)
  beam(b, FRAME, v(-0.97, 0.56, 0.36), v(-0.97, 0.18, 0.38), 0.006, 0.1)
  tank(b, v(-0.66, -0.36, -0.46), 0.085, 0.24)
  tank(b, v(-0.66, -0.36, 0.10), 0.07, 0.17, PLATING)
  -- a platform on the top rails forward, for its one gun, and another
  -- under the keel for that gun's twin
  block(b, PLATING, v(-0.06, high + 0.035, bow - 0.24), v(0.15, 0.018, 0.13), nil, 0.2)
  block(b, PLATING, v(0.06, low - 0.05, bow - 0.24), v(0.15, 0.018, 0.13), nil, 0.2)
  -- starboard: a mast, and a slab of plate over the middle bay
  mast(b, v(0.20, high, -0.50), 0.55, 0.04)
  block(b, PLATING, v(0.47, 0.02, stern + length * 1.5), v(0.018, 0.30, length * 0.36), v(0, 0, -0.29), 0.06)
end

-- The Halberd, a missile destroyer, drawn as the weapon it is named
-- for: a long pole of girders with the ship's works strung along it,
-- and at the bow a great blade of armour hanging below the pole, with a
-- spike out ahead. To balance the blade the engines are stacked above
-- the pole at the stern, so that the whole ship runs on a slant.
local function halberd(b: Builder)
  -- the pole
  truss(b, v(0, 0, -1.42), v(0, 0, 1.40), 0.20, 12)
  truss(b, v(0, 0, -1.42), v(0, 0, 1.40), 0.18, 12, v(1, 0, 0))
  -- the spike
  beam(b, FRAME, v(0, 0.02, 1.36), v(0, 0.05, 2.20), 0.022, 0.1)
  beam(b, FRAME, v(0.05, -0.04, 1.36), v(0.07, -0.05, 1.82), 0.011, 0.1)
  block(b, PLATING, v(0, 0.01, 1.42), v(0.10, 0.10, 0.07), nil, 0.2)

  -- the blade: three slabs that make an axe-head under the bow, and a
  -- fluke above it
  block(b, PLATING, v(0.00, -0.36, 1.00), v(0.060, 0.36, 0.32), nil, 0.06)
  block(b, PLATING, v(-0.01, -0.84, 0.86), v(0.055, 0.24, 0.26), v(0, 0.30, 0), 0.06)
  block(b, PATCH, v(0.01, -0.62, 0.58), v(0.050, 0.26, 0.14), v(0, -0.22, 0), 0.06)
  block(b, PLATING, v(0.00, 0.24, 1.10), v(0.050, 0.15, 0.17), v(0, -0.25, 0), 0.06)
  -- its edge, in trim, and ribs across it
  block(b, TRIM, v(0.00, -0.50, 1.325), v(0.064, 0.30, 0.018), v(0, 0.06, 0), 0.2)
  block(b, TRIM, v(-0.01, -0.99, 1.10), v(0.060, 0.11, 0.018), v(0, 0.62, 0), 0.2)
  for _, y in { -0.16, -0.42, -0.68 } do
    beam(b, FRAME, v(0.066, y, 0.72), v(0.066, y - 0.06, 1.28), 0.012)
    beam(b, FRAME, v(-0.066, y, 0.72), v(-0.066, y - 0.06, 1.28), 0.012)
  end
  beam(b, FRAME, v(0, -0.10, 0.50), v(0, -0.60, 0.70), 0.020)
  beam(b, FRAME, v(0, -0.08, 0.20), v(0, -0.84, 0.66), 0.016)
  ports(b, v(0.062, -0.08, 0.82), v(0.062, -0.08, 1.18), 5, 0.012)

  -- the works, strung along the pole
  block(b, PLATING, v(0.03, 0.17, 0.42), v(0.17, 0.15, 0.27))
  block(b, PATCH, v(0.11, 0.37, 0.50), v(0.095, 0.060, 0.13), nil, 0.14)
  block(b, GLOW, v(0.11, 0.39, 0.634), v(0.070, 0.018, 0.006), nil, 0.3)
  block(b, FRAME, v(0.11, 0.44, 0.46), v(0.055, 0.010, 0.07))
  block(b, PLATING, v(0.00, -0.04, -0.14), v(0.21, 0.20, 0.30))
  block(b, PATCH, v(-0.225, 0.00, -0.10), v(0.020, 0.16, 0.22), v(0, 0, 0.05))
  block(b, PLATING, v(0.228, -0.05, -0.20), v(0.020, 0.13, 0.17), v(0, 0, -0.05))
  block(b, PLATING, v(0.00, 0.06, -0.84), v(0.24, 0.22, 0.25))
  block(b, FRAME, v(0.00, 0.02, -0.50), v(0.15, 0.15, 0.05))
  tank(b, v(0.15, -0.31, -0.18), 0.085, 0.24)
  tank(b, v(-0.14, -0.30, -0.26), 0.070, 0.18, PLATING)
  conduit(b, { v(0.06, 0.33, 0.20), v(0.06, 0.22, 0.10), v(0.06, 0.18, -0.50), v(0.06, 0.30, -0.62) }, 0.014)
  conduit(b, { v(-0.08, 0.17, -0.40), v(-0.08, 0.30, -0.56), v(-0.08, 0.30, -0.98) }, 0.012)

  -- the engines, stacked above the pole on a pylon; a small one below
  truss(b, v(0, 0.24, -0.92), v(0, 0.98, -0.92), 0.16, 4, v(0, 0, 1))
  nacelle(b, v(0.00, 0.52, -1.08), 0.44, 0.145)
  nacelle(b, v(-0.03, 0.92, -0.96), 0.34, 0.110)
  beam(b, FRAME, v(0.0, 0.30, -0.62), v(0.0, 0.80, -0.80), 0.018)
  block(b, FRAME, v(0.00, -0.02, -1.14), v(0.13, 0.13, 0.07), nil, 0.2)
  block(b, GLOW, v(0.00, -0.02, -1.222), v(0.09, 0.09, 0.010), v(0, 0, math.pi / 8), 0.5)
  exhaust(v(0.00, -0.02, -1.235), 0.09)
  mast(b, v(-0.03, 1.03, -0.86), 0.42, 0.02)

  -- out to starboard, a boom with its drum
  truss(b, v(0.22, 0.00, -0.30), v(0.82, 0.06, -0.36), 0.10, 4, v(0, 0, 1))
  tank(b, v(0.90, 0.06, -0.36), 0.10, 0.22, PLATING)
  beam(b, FRAME, v(0.90, 0.16, -0.30), v(0.94, 0.52, -0.40), 0.008, 0.1)
end

-- The Cuirass, a missile cruiser, which goes into a fight behind its
-- breastplate: a great shield of slabs standing off the bow and wrapped
-- back along the whole port side, held on struts. The starboard side
-- behind it is left bare and is where it fights from: a gun deck runs
-- most of its length there, every hardpoint in a line along it, to give
-- a broadside. The bridge looks over the top of the shield from a tower;
-- the engines hang off a beam across the stern, three of them, none the
-- same size or the same way out. (Made longer, and given the gun deck,
-- at the project owner's word.)
local function cuirass(b: Builder)
  -- the keel and the long body on it, in three lengths
  truss(b, v(0.05, -0.20, -2.00), v(0.05, -0.20, 1.72), 0.26, 16)
  truss(b, v(0.05, -0.20, -2.00), v(0.05, -0.20, 1.72), 0.24, 16, v(1, 0, 0))
  block(b, PLATING, v(0.05, 0.04, 1.02), v(0.28, 0.25, 0.50))
  block(b, PLATING, v(0.04, 0.03, 0.00), v(0.27, 0.27, 0.40))
  block(b, PLATING, v(0.03, 0.02, -1.00), v(0.26, 0.28, 0.42))
  block(b, FRAME, v(0.05, 0.02, 0.47), v(0.20, 0.20, 0.07))
  block(b, FRAME, v(0.04, 0.02, -0.50), v(0.20, 0.20, 0.08))
  block(b, PATCH, v(0.05, 0.305, 0.96), v(0.22, 0.022, 0.36))
  block(b, PLATING, v(0.04, 0.31, -0.98), v(0.19, 0.020, 0.30), v(0, 0.03, 0))
  block(b, PLATING, v(0.03, 0.31, 0.02), v(0.20, 0.020, 0.28))

  -- the breastplate: the face of it across the bow, canted
  block(b, PLATING, v(-0.06, 0.06, 1.96), v(0.50, 0.56, 0.050), v(0.10, -0.06, 0), 0.05)
  block(b, PATCH, v(0.30, -0.36, 1.995), v(0.19, 0.17, 0.030), v(0.10, -0.06, 0), 0.08)
  block(b, TRIM, v(-0.08, 0.36, 2.012), v(0.44, 0.045, 0.012), v(0.10, -0.06, 0), 0.2)
  block(b, TRIM, v(-0.08, 0.22, 2.018), v(0.44, 0.020, 0.012), v(0.10, -0.06, 0), 0.2)
  -- its shoulder, turning the corner to port
  block(b, PLATING, v(-0.66, 0.03, 1.70), v(0.050, 0.52, 0.30), v(0.55, 0, 0), 0.05)
  -- and its flank, back along the port side in five lengths that step down
  block(b, PLATING, v(-0.80, 0.00, 1.12), v(0.050, 0.48, 0.34), v(0.10, 0, 0), 0.05)
  block(b, PATCH, v(-0.82, -0.04, 0.46), v(0.045, 0.42, 0.30), v(0.02, 0, 0.04), 0.05)
  block(b, PLATING, v(-0.82, -0.08, -0.16), v(0.045, 0.36, 0.30), nil, 0.05)
  block(b, PLATING, v(-0.81, -0.12, -0.78), v(0.045, 0.30, 0.29), v(-0.03, 0, 0), 0.05)
  block(b, PATCH, v(-0.78, -0.15, -1.36), v(0.040, 0.24, 0.26), v(-0.10, 0, 0), 0.05)
  block(b, TRIM, v(-0.855, 0.30, 1.12), v(0.012, 0.045, 0.33), v(0.10, 0, 0), 0.2)
  block(b, TRIM, v(-0.868, 0.20, 0.16), v(0.012, 0.030, 0.60), nil, 0.2)
  -- a brow over the top, and a chin under
  block(b, PLATING, v(-0.16, 0.66, 1.72), v(0.42, 0.045, 0.26), v(0, -0.30, 0), 0.05)
  block(b, PLATING, v(-0.10, -0.56, 1.76), v(0.38, 0.040, 0.22), v(0, 0.34, 0), 0.05)
  -- the struts that carry it
  for _, y in { -0.18, 0.20 } do
    for _, z in { 1.20, 0.50, -0.14, -0.76, -1.30 } do
      beam(b, FRAME, v(-0.22, y, z), v(-0.77, y - 0.03, z - 0.04), 0.022)
    end
    beam(b, FRAME, v(-0.10, y, 1.52), v(-0.20, y, 1.90), 0.022)
    beam(b, FRAME, v(0.20, y, 1.52), v(0.30, y, 1.92), 0.022)
  end
  beam(b, FRAME, v(-0.22, 0.20, 1.20), v(-0.77, -0.20, 0.50), 0.014)
  beam(b, FRAME, v(-0.22, 0.20, -0.14), v(-0.77, -0.20, -0.76), 0.014)
  beam(b, FRAME, v(0.05, 0.30, 1.42), v(-0.10, 0.62, 1.66), 0.018)
  beam(b, FRAME, v(0.05, -0.30, 1.42), v(-0.06, -0.54, 1.68), 0.018)

  -- the bare side: the gun deck, a shelf along it on brackets, with a
  -- low wall at its edge between the mounts. Its weapons stand on it
  -- and hang under it, in two tiers; a tank is slung aft of them.
  block(b, PLATING, v(0.47, 0.04, 0.12), v(0.15, 0.026, 1.26), nil, 0.1)
  block(b, FRAME, v(0.33, 0.10, 0.12), v(0.02, 0.05, 1.22), nil, 0.1)
  for _, z in { 1.22, 0.72, 0.22, -0.28, -0.78 } do
    beam(b, FRAME, v(0.32, -0.20, z), v(0.58, 0.02, z), 0.020)
    block(b, PLATING, v(0.605, 0.085, z + 0.25), v(0.014, 0.045, 0.10), nil, 0.1)
  end
  block(b, TRIM, v(0.622, 0.04, 0.12), v(0.006, 0.020, 1.24), nil, 0.2)
  tank(b, v(0.42, -0.14, -1.14), 0.085, 0.22)
  tank(b, v(0.40, -0.16, 1.58), 0.075, 0.16, PLATING)
  conduit(b, { v(0.36, -0.30, 1.30), v(0.36, -0.32, 0.20), v(0.36, -0.30, -1.30) }, 0.016)
  conduit(b, { v(0.56, -0.02, 1.34), v(0.56, -0.05, 1.50), v(0.34, -0.05, 1.56) }, 0.014)
  conduit(b, { v(0.34, 0.20, -0.92), v(0.34, 0.24, -1.40), v(0.30, 0.20, -1.60) }, 0.016)

  -- the tower, and the bridge on it that sees over the brow
  block(b, PLATING, v(0.16, 0.52, 0.86), v(0.13, 0.22, 0.15))
  block(b, FRAME, v(0.16, 0.76, 0.86), v(0.10, 0.03, 0.11))
  block(b, PATCH, v(0.16, 0.86, 0.92), v(0.18, 0.075, 0.22), nil, 0.14)
  block(b, GLOW, v(0.16, 0.885, 1.144), v(0.14, 0.022, 0.006), nil, 0.3)
  block(b, GLOW, v(0.343, 0.885, 0.96), v(0.004, 0.020, 0.12), nil, 0.3)
  mast(b, v(0.10, 0.93, 0.82), 0.52, 0.03)
  beam(b, FRAME, v(0.24, 0.93, 1.00), v(0.26, 1.22, 0.96), 0.008, 0.1)
  -- a second, lower house aft
  block(b, PLATING, v(0.00, 0.44, -0.86), v(0.15, 0.12, 0.22))
  block(b, PATCH, v(0.02, 0.59, -0.80), v(0.10, 0.04, 0.12), nil, 0.14)
  ports(b, v(0.152, 0.46, -1.02), v(0.152, 0.46, -0.70), 4, 0.012)

  -- a magazine slung under the middle
  block(b, PLATING, v(0.04, -0.52, -0.10), v(0.21, 0.15, 0.56), nil, 0.08)
  block(b, TRIM, v(0.04, -0.52, 0.20), v(0.216, 0.155, 0.03), nil, 0.1)
  for _, z in { -0.56, 0.36 } do
    beam(b, FRAME, v(0.20, -0.30, z), v(0.20, -0.40, z), 0.018)
    beam(b, FRAME, v(-0.12, -0.30, z), v(-0.12, -0.40, z), 0.018)
  end

  -- the engines: a beam across the stern, and three pods hung off it
  block(b, PLATING, v(0.04, 0.00, -1.62), v(0.24, 0.24, 0.20))
  truss(b, v(-0.92, 0.20, -1.76), v(1.12, -0.04, -1.72), 0.16, 9)
  nacelle(b, v(0.04, -0.14, -2.12), 0.50, 0.21)
  nacelle(b, v(-0.84, 0.30, -1.90), 0.40, 0.14)
  nacelle(b, v(1.10, -0.10, -1.80), 0.44, 0.165)
  beam(b, FRAME, v(-0.30, 0.20, -1.40), v(-0.80, 0.26, -1.70), 0.020)
  beam(b, FRAME, v(0.34, -0.10, -1.36), v(1.02, -0.08, -1.64), 0.020)
  -- (the family's slanted plates, over and under the middle engine)
  block(b, PLATING, v(0.04, 0.18, -2.06), v(0.26, 0.020, 0.26), v(0, -0.26, 0), 0.08)
  block(b, PATCH, v(0.04, -0.44, -2.08), v(0.28, 0.020, 0.26), v(0, 0.28, 0), 0.08)
end

-- A tower: a shaft, a narrower stage on it, and a crown that steps out
-- again, with slits lit in the stage and merlons at the crown's corners.
-- 'foot' is the middle of its base; 'width' is half its width.
local function tower(b: Builder, foot: vector, width: number, height: number, part: number?)
  local shaft = height * 0.55
  block(b, part or PLATING, foot + v(0, shaft / 2, 0), v(width, shaft / 2, width), nil, 0.06)
  block(b, FRAME, foot + v(0, shaft + height * 0.02, 0), v(width * 0.86, height * 0.02, width * 0.86), nil, 0.1)
  block(b, PLATING, foot + v(0, shaft + height * 0.17, 0), v(width * 0.78, height * 0.15, width * 0.78), nil, 0.06)
  block(b, PATCH, foot + v(0, height * 0.93, 0), v(width * 1.08, height * 0.07, width * 1.08), nil, 0.10)
  for _, side in { -1, 1 } do
    block(b, GLOW, foot + v(side * width * 0.785, shaft + height * 0.17, 0), v(0.004, height * 0.07, width * 0.35), nil, 0.3)
    for _, end_ in { -1, 1 } do
      block(b, PLATING, foot + v(side * width * 0.86, height * 1.03, end_ * width * 0.86), v(width * 0.2, height * 0.035, width * 0.2), nil, 0.15)
    end
  end
end

-- The Bastion, a missile battleship: a castle. A long, low hull, and on
-- it two curtain walls running nearly its whole length, the port one the
-- longer, with battlements along their tops and towers rising out of
-- them at intervals, no two the same height: a gatehouse of two at the
-- bow, watchtowers along the walls, and aft of the middle the keep, the
-- tallest thing on the ship, with the bridge at its top. The missiles
-- sit in blocks of cells in the yard between the walls, among halls and
-- gantries. The port wall runs on past the bow as a ram. (Drawn long at
-- the project owner's word: it was squat, and a castle is not.)
local function bastion(b: Builder)
  local port, starboard = -0.46, 0.48
  local foot = -0.40                  -- where the walls stand
  local stern, bow = -3.00, 2.70

  -- the hull under it all: a long keel, and a deck the length of the yard
  truss(b, v(0, -0.52, stern - 0.2), v(0, -0.52, bow), 0.24, 26)
  truss(b, v(0, -0.52, stern - 0.2), v(0, -0.52, bow), 0.56, 26, v(1, 0, 0))
  block(b, FRAME, v(0.01, -0.36, -0.10), v(0.40, 0.05, 2.80), nil, 0.04)
  block(b, PLATING, v(0.01, -0.44, 1.30), v(0.44, 0.07, 1.20), nil, 0.05)
  block(b, PLATING, v(0.00, -0.45, -1.50), v(0.46, 0.08, 1.30), nil, 0.05)

  -- A length of curtain wall along z, from the foot up to 'top'.
  local function wall(x: number, from: number, to: number, top: number, part: number)
    block(b, part, v(x, (top + foot) / 2, (from + to) / 2), v(0.085, (top - foot) / 2, (to - from) / 2), nil, 0.035)
    battlements(b, v(x, top + 0.04, from + 0.04), v(x, top + 0.04, to - 0.04), math.floor((to - from) / 0.105), 0.042)
  end
  -- the port wall, stern to bow: it climbs to the keep and falls away to the ram
  wall(port, -3.00, -2.20, 0.06, PLATING)
  wall(port, -2.20, -1.42, 0.14, PATCH)
  wall(port, -1.42, -0.60, 0.24, PLATING)
  wall(port, -0.60, 0.22, 0.16, PLATING)
  wall(port, 0.22, 1.04, 0.08, PATCH)
  wall(port, 1.04, 1.86, 0.02, PLATING)
  wall(port, 1.86, 2.66, -0.04, PLATING)
  -- the ram: the wall carried on past the bow, tapering, edged in trim
  block(b, PLATING, v(port, -0.22, 3.02), v(0.075, 0.20, 0.38), v(0, 0.08, 0), 0.05)
  block(b, PLATING, v(port, -0.28, 3.62), v(0.060, 0.13, 0.26), v(0, 0.16, 0), 0.05)
  block(b, TRIM, v(port, -0.31, 3.885), v(0.066, 0.115, 0.018), v(0, 0.16, 0), 0.2)
  block(b, TRIM, v(port - 0.088, -0.12, 0.60), v(0.010, 0.035, 2.40), nil, 0.2)
  -- the starboard wall: shorter at both ends, and lower
  wall(starboard, -2.60, -1.80, -0.02, PLATING)
  wall(starboard, -1.80, -1.00, 0.06, PLATING)
  wall(starboard, -1.00, -0.18, 0.12, PATCH)
  wall(starboard, -0.18, 0.64, 0.06, PLATING)
  wall(starboard, 0.64, 1.44, 0.00, PLATING)
  wall(starboard, 1.44, 2.10, -0.06, PATCH)
  block(b, TRIM, v(starboard + 0.088, -0.16, -0.20), v(0.010, 0.035, 2.20), nil, 0.2)
  -- rows of lit ports along both, to say how big it is
  ports(b, v(port - 0.090, -0.22, -2.90), v(port - 0.090, -0.22, 2.50), 64, 0.008)
  ports(b, v(port - 0.090, -0.02, -1.36), v(port - 0.090, -0.02, 0.16), 22, 0.008)
  ports(b, v(starboard + 0.090, -0.26, -2.50), v(starboard + 0.090, -0.26, 2.00), 54, 0.008)

  -- the towers. The gatehouse: two at the bow, with a bridge between
  tower(b, v(port, -0.04, 2.36), 0.15, 0.80)
  tower(b, v(starboard, -0.06, 1.96), 0.14, 0.62)
  truss(b, v(port + 0.12, 0.22, 2.30), v(starboard - 0.12, 0.14, 2.00), 0.10, 5, v(0, 0, 1))
  -- watchtowers along the walls, none the same
  tower(b, v(port, 0.08, 1.04), 0.11, 0.50, PATCH)
  tower(b, v(starboard, 0.06, 0.30), 0.12, 0.94)
  tower(b, v(starboard, -0.02, -1.74), 0.13, 0.58, PATCH)
  tower(b, v(port, 0.06, -2.24), 0.14, 0.66)
  tower(b, v(starboard - 0.02, 0.00, -0.96), 0.09, 0.40)
  mast(b, v(starboard, 1.02, 0.30), 0.40, 0.02)
  -- the keep: up out of the port wall, aft of the middle, in four stages
  block(b, PLATING, v(port + 0.08, 0.50, -1.00), v(0.25, 0.30, 0.32), nil, 0.05)
  block(b, TRIM, v(port + 0.08, 0.78, -0.672), v(0.255, 0.035, 0.012), nil, 0.2)
  block(b, PATCH, v(port + 0.10, 0.98, -0.98), v(0.19, 0.20, 0.25), nil, 0.05)
  block(b, FRAME, v(port + 0.10, 1.21, -0.98), v(0.15, 0.035, 0.20))
  block(b, PLATING, v(port + 0.10, 1.40, -0.98), v(0.13, 0.17, 0.17), nil, 0.06)
  block(b, PLATING, v(port + 0.14, 1.66, -0.90), v(0.25, 0.09, 0.32), nil, 0.12)
  block(b, GLOW, v(port + 0.14, 1.685, -0.576), v(0.20, 0.024, 0.006), nil, 0.3)
  block(b, GLOW, v(port + 0.394, 1.685, -0.86), v(0.004, 0.022, 0.22), nil, 0.3)
  ports(b, v(port + 0.332, 0.50, -1.24), v(port + 0.332, 0.50, -0.76), 8, 0.010)
  ports(b, v(port + 0.292, 0.98, -1.16), v(port + 0.292, 0.98, -0.80), 6, 0.010)
  mast(b, v(port + 0.04, 1.75, -1.06), 0.66, 0.03)
  mast(b, v(port + 0.26, 1.75, -0.78), 0.42, -0.02)
  battlements(b, v(port + 0.33, 0.84, -1.28), v(port + 0.33, 0.84, -0.70), 6, 0.04)
  beam(b, FRAME, v(port + 0.26, 0.80, -1.28), v(port + 0.34, 1.50, -1.16), 0.018)
  beam(b, FRAME, v(port + 0.30, 0.74, -0.74), v(starboard - 0.10, 0.20, -0.50), 0.018)

  -- the yard: blocks of launch cells down the middle, a hall, gantries
  silos(b, v(0.02, -0.20, 1.50), v(0.28, 0.12, 0.26), 4, 4)
  silos(b, v(0.00, -0.16, 0.74), v(0.30, 0.16, 0.30), 4, 5)
  silos(b, v(0.14, -0.20, -0.02), v(0.20, 0.12, 0.26), 3, 4)
  silos(b, v(0.04, -0.18, -1.92), v(0.30, 0.14, 0.30), 4, 4)
  silos(b, v(0.02, -0.22, -2.58), v(0.26, 0.10, 0.24), 3, 3)
  -- (the hall, under the family's slanted plates)
  block(b, PLATING, v(0.16, -0.14, -1.20), v(0.18, 0.18, 0.30), nil, 0.06)
  block(b, PATCH, v(0.07, 0.10, -1.20), v(0.13, 0.016, 0.32), v(0, 0, 0.50), 0.08)
  block(b, PLATING, v(0.25, 0.10, -1.20), v(0.13, 0.016, 0.32), v(0, 0, -0.50), 0.08)
  truss(b, v(port + 0.10, 0.04, 1.14), v(starboard - 0.09, -0.06, 1.10), 0.10, 6, v(0, 0, 1))
  truss(b, v(port + 0.10, 0.10, 0.36), v(starboard - 0.09, 0.02, 0.36), 0.12, 6, v(0, 0, 1))
  truss(b, v(port + 0.10, 0.02, -2.24), v(starboard - 0.09, -0.08, -2.20), 0.10, 6, v(0, 0, 1))
  conduit(b, { v(port + 0.11, -0.10, 2.40), v(port + 0.11, -0.06, 0.40), v(port + 0.13, -0.02, -0.50), v(port + 0.11, -0.10, -2.80) }, 0.020)
  conduit(b, { v(starboard - 0.11, -0.18, 1.90), v(starboard - 0.11, -0.14, -2.40) }, 0.018)
  -- the gate: the bow of the yard, a lit mouth under the gatehouse bridge
  block(b, PLATING, v(0.04, -0.24, 2.14), v(0.38, 0.18, 0.05), v(0, 0.10, 0), 0.06)
  block(b, GLOW, v(0.06, -0.22, 2.196), v(0.20, 0.05, 0.006), v(0, 0.10, 0), 0.3)
  block(b, PLATING, v(0.02, -0.40, 2.50), v(0.30, 0.05, 0.30), v(0, -0.12, 0), 0.06)

  -- under the bow, a pad below each gatehouse tower, for the twin of
  -- the gun on its top
  block(b, PLATING, v(-0.36, -0.53, 2.30), v(0.10, 0.020, 0.10), nil, 0.2)
  block(b, PLATING, v(0.37, -0.53, 1.90), v(0.10, 0.020, 0.10), nil, 0.2)

  -- under the keel, the magazines: two drums in cradles
  tank(b, v(0.06, -0.82, 0.80), 0.19, 0.62, PLATING)
  tank(b, v(-0.04, -0.80, -1.10), 0.17, 0.52)
  for _, z in { 0.36, 1.26, -1.50, -0.72 } do
    beam(b, FRAME, v(-0.20, -0.54, z), v(-0.12, -0.72, z), 0.022)
    beam(b, FRAME, v(0.28, -0.54, z), v(0.22, -0.72, z), 0.022)
  end
  -- out to starboard, a boom
  truss(b, v(starboard + 0.08, -0.26, 0.90), v(1.26, -0.16, 1.00), 0.12, 5, v(0, 0, 1))
  block(b, PATCH, v(1.32, -0.16, 1.00), v(0.07, 0.07, 0.16), nil, 0.2)
  beam(b, FRAME, v(1.32, -0.09, 1.00), v(1.36, 0.38, 0.94), 0.009, 0.1)

  -- the stern: a block that joins the walls, and five engines in it,
  -- behind the family's slanted plates
  block(b, PLATING, v(0.01, -0.20, stern - 0.22), v(0.56, 0.34, 0.22), nil, 0.05)
  block(b, PLATING, v(0.00, 0.20, stern - 0.40), v(0.50, 0.026, 0.32), v(0, -0.34, 0), 0.06)
  block(b, PATCH, v(0.02, -0.62, stern - 0.40), v(0.54, 0.026, 0.32), v(0, 0.34, 0), 0.06)
  nacelle(b, v(-0.26, -0.12, stern - 0.52), 0.36, 0.19)
  nacelle(b, v(0.24, -0.26, stern - 0.56), 0.40, 0.22)
  nacelle(b, v(0.30, 0.04, stern - 0.46), 0.26, 0.10)
  nacelle(b, v(-0.34, -0.42, stern - 0.46), 0.26, 0.11)
  nacelle(b, v(-0.02, 0.06, stern - 0.44), 0.22, 0.085)
end

-- ---------------------------------------------------------------------
-- The Talmar. Their hulls are like clouds (the project owner's draft:
-- "cloud-like, with rounded edges and protrusions", Star Wars' Mon
-- Calamari cruisers the point of reference), and like those they look
-- grown, not built and not blown up. They are not made of plates. A
-- Talmar hull is a skin (Plates.Loft): one surface drawn through oval
-- sections, that swells and narrows from stern to bow without a break,
-- with lesser skins run into it for a wing, a tier or a keel, and
-- slender fairings lying along all of them (Plates.Fairing), a few long
-- and most short. It is the same on both sides (the owner again). Its
-- plating is a patchwork of small panels with pinpoint lights; its
-- engines are round, in a cluster at the stern; and, theirs being a
-- theocracy, the larger carry a dome and slender spires.
--
-- (Two earlier tries were plates: first a few smooth fat lobes, "too
-- blimp-y", then lobes with pods grown on them, which was nearer but
-- still stacked boxes. The Claymore was the first drawn as skins, and
-- "looks MUCH better"; the rest followed. All v0s.)

-- A lobe: a rounded mass (a plate with its corners all but gone), for
-- the few things that are still plates: a dome, an engine, a bead.
local function lobe(b: Builder, part: number, center: vector, half: vector, turn: vector?)
  block(b, part, center, half, turn, 0.92)
end

-- A number from 0 to 1 that follows from 'n'.
local function chance(n: number): number
  return (math.sin(n * 12.9898) * 43758.5453) % 1
end

-- A round engine: a pod with a lit mouth.
local function thruster(b: Builder, center: vector, length: number, radius: number)
  lobe(b, PLATING, center, v(radius, radius, length))
  block(b, FRAME, center + v(0, 0, -length * 0.86), v(radius * 0.84, radius * 0.84, length * 0.16), nil, 0.6)
  block(b, GLOW, center + v(0, 0, -length * 1.02), v(radius * 0.62, radius * 0.62, length * 0.03), nil, 0.9)
  exhaust(center + v(0, 0, -length * 1.06), radius * 0.62)
end

-- A spire: a slender rounded mast, with a bead part way up it.
local function spire(b: Builder, foot: vector, height: number, thick: number)
  beam(b, PLATING, foot, foot + v(0, height * 0.62, 0), thick, 0.9)
  beam(b, PATCH, foot + v(0, height * 0.58, 0), foot + v(0, height, 0), thick * 0.5, 0.9)
  lobe(b, TRIM, foot + v(0, height * 0.60, 0), v(thick * 1.6, thick * 1.2, thick * 1.6))
end

-- Fairings: 'count' slender swellings on a skin, lying along it, a few
-- of them long and most short ('length' is the middling one), anywhere
-- from 'from' to 'to' along it. The same on both sides; those on the
-- back or the keel lie on the middle line. ('x' and 'y' as for the skin.)
local function fairings(b: Builder, outline: Plates.Outline, count: number, length: number, seed: number, from: number, to: number,
  x: number?, y: number?)
  local aside = x or 0
  for index = 1, count do
    local n = seed * 17.3 + index * 3.1
    local z = from + (to - from) * chance(n)
    local long = length * (0.45 + 1.8 * chance(n + 0.71) ^ 3)
    local wide = long * (0.11 + 0.07 * chance(n + 0.13))
    local skin = if index % 3 == 0 then PATCH else PLATING
    if aside == 0 then
      -- (from the keel round the starboard side to the back)
      local around = (chance(n + 0.37) - 0.5) * math.pi
      if math.abs(math.cos(around)) < 0.22 then
        Plates.Fairing(b, skin, outline, z, if around > 0 then math.pi / 2 else -math.pi / 2, long, wide, wide * 0.5, 0, y)
      else
        Plates.Fairing(b, skin, outline, z, around, long, wide, wide * 0.5, 0, y)
        Plates.Fairing(b, skin, outline, z, math.pi - around, long, wide, wide * 0.5, 0, y)
      end
    else
      local around = chance(n + 0.37) * 2 * math.pi
      Plates.Fairing(b, skin, outline, z, around, long, wide, wide * 0.5, aside, y)
      Plates.Fairing(b, skin, outline, z, math.pi - around, long, wide, wide * 0.5, -aside, y)
    end
  end
end

-- A skin and its twin, one that far to each side.
local function pair(b: Builder, part: number, outline: Plates.Outline, x: number, y: number)
  Plates.Loft(b, part, outline, x, y)
  Plates.Loft(b, part, outline, -x, y)
end

-- (Where on a skin a mount goes.)
local on = Plates.Point
local BACK, KEEL, STARBOARD_SIDE, PORT_SIDE = math.pi / 2, -math.pi / 2, 0, math.pi

-- The Rapier, a frigate: a teardrop, with a blister on its back for the
-- bridge and three engines.
local RAPIER: Plates.Outline = { { -0.62, 0.10, 0.08 }, { -0.35, 0.22, 0.16 }, { 0.05, 0.27, 0.19 }, { 0.45, 0.21, 0.15 },
  { 0.80, 0.12, 0.09 }, { 1.05, 0.04, 0.03 } }
local RAPIER_BRIDGE: Plates.Outline = { { -0.14, 0.03, 0.02 }, { 0.06, 0.11, 0.065 }, { 0.30, 0.07, 0.045 }, { 0.42, 0.02, 0.015 } }
local function rapier(b: Builder)
  Plates.Loft(b, PLATING, RAPIER)
  Plates.Loft(b, PATCH, RAPIER_BRIDGE, 0, 0.17)
  block(b, GLOW, v(0, 0.215, 0.33), v(0.045, 0.012, 0.03), nil, 0.6)
  fairings(b, RAPIER, 10, 0.30, 1, -0.50, 0.70)
  fairings(b, RAPIER, 8, 0.13, 2, -0.50, 0.80)
  thruster(b, v(0, 0.01, -0.66), 0.17, 0.085)
  for _, side in { -1, 1 } do
    thruster(b, v(side * 0.15, -0.03, -0.60), 0.14, 0.065)
  end
end

-- The Sabre, a destroyer: a long slender body that swells twice along
-- its length, with a pontoon out on necks each side.
local SABRE: Plates.Outline = { { -1.18, 0.08, 0.07 }, { -0.85, 0.20, 0.17 }, { -0.45, 0.16, 0.14 }, { -0.05, 0.24, 0.19 },
  { 0.40, 0.21, 0.17 }, { 0.75, 0.14, 0.12 }, { 1.05, 0.15, 0.12 }, { 1.32, 0.08, 0.06 }, { 1.50, 0.03, 0.02 } }
local SABRE_PONTOON: Plates.Outline = { { -0.75, 0.03, 0.03 }, { -0.40, 0.085, 0.075 }, { 0.10, 0.09, 0.08 }, { 0.50, 0.03, 0.03 } }
local SABRE_BRIDGE: Plates.Outline = { { 0.00, 0.03, 0.02 }, { 0.18, 0.09, 0.055 }, { 0.36, 0.06, 0.04 }, { 0.46, 0.02, 0.015 } }
local function sabre(b: Builder)
  Plates.Loft(b, PLATING, SABRE)
  pair(b, PLATING, SABRE_PONTOON, 0.36, -0.06)
  Plates.Loft(b, PATCH, SABRE_BRIDGE, 0, 0.16)
  block(b, GLOW, v(0, 0.20, 0.39), v(0.04, 0.011, 0.025), nil, 0.6)
  fairings(b, SABRE, 14, 0.32, 3, -1.00, 1.20)
  fairings(b, SABRE, 10, 0.13, 4, -1.00, 1.30)
  fairings(b, SABRE_PONTOON, 3, 0.20, 5, -0.55, 0.30, 0.36, -0.06)
  for _, side in { -1, 1 } do
    lobe(b, PLATING, v(side * 0.27, -0.04, 0.10), v(0.08, 0.045, 0.08))
    lobe(b, PLATING, v(side * 0.26, -0.04, -0.40), v(0.08, 0.045, 0.08))
    thruster(b, v(side * 0.36, -0.06, -0.78), 0.10, 0.05)
    thruster(b, v(side * 0.085, 0.0, -1.22), 0.14, 0.07)
  end
end

-- The Falchion, a cruiser: a great body with a broad flat wing swept
-- back from each side of it, a tier laid along its back, a small domed
-- sanctuary on that with a spire, and six engines.
local FALCHION: Plates.Outline = { { -1.05, 0.16, 0.12 }, { -0.65, 0.32, 0.23 }, { -0.10, 0.37, 0.26 }, { 0.40, 0.33, 0.24 },
  { 0.85, 0.25, 0.18 }, { 1.25, 0.15, 0.11 }, { 1.60, 0.04, 0.03 } }
local FALCHION_WING: Plates.Outline = { { -0.90, 0.06, 0.03 }, { -0.60, 0.24, 0.08 }, { -0.15, 0.26, 0.09 }, { 0.25, 0.14, 0.06 },
  { 0.50, 0.03, 0.02 } }
local FALCHION_TIER: Plates.Outline = { { -0.75, 0.08, 0.05 }, { -0.40, 0.22, 0.12 }, { 0.05, 0.20, 0.11 }, { 0.45, 0.07, 0.04 } }
local function falchion(b: Builder)
  Plates.Loft(b, PLATING, FALCHION)
  pair(b, PLATING, FALCHION_WING, 0.50, -0.04)
  Plates.Loft(b, PATCH, FALCHION_TIER, 0, 0.22)
  fairings(b, FALCHION, 22, 0.42, 6, -0.90, 1.30)
  fairings(b, FALCHION, 16, 0.16, 7, -0.90, 1.40)
  fairings(b, FALCHION_WING, 5, 0.26, 8, -0.70, 0.30, 0.50, -0.04)
  fairings(b, FALCHION_TIER, 3, 0.20, 9, -0.55, 0.30, 0, 0.22)
  lobe(b, PLATING, v(0, 0.36, -0.30), v(0.10, 0.07, 0.13))
  block(b, GLOW, v(0, 0.37, -0.16), v(0.05, 0.014, 0.012), nil, 0.6)
  spire(b, v(0, 0.42, -0.34), 0.50, 0.018)
  for _, side in { -1, 1 } do
    thruster(b, v(side * 0.11, 0.07, -1.12), 0.16, 0.08)
    thruster(b, v(side * 0.12, -0.08, -1.10), 0.15, 0.075)
    thruster(b, v(side * 0.50, -0.04, -0.94), 0.10, 0.05)
  end
end

-- The Claymore, a battleship: a cathedral in a cloud, with a sword for
-- a prow. It is one skin from its stern to the point of its blade: a
-- great body that narrows and flattens at the bow into a blade, flat
-- and level, running out ahead of it. A lesser body lies along each
-- flank, a keel under it and a second tier on its back, each a skin of
-- its own; slender fairings lie along all of them. On the tier a dome
-- with blisters ringing it like a halo, and three spires; six engines.
-- (The blade is at the project owner's word, in place of a nose that
-- "looks like a blimp"; it has no guard across it, and is a third
-- shorter than it was first drawn, both at their word too.)
local CLAYMORE: Plates.Outline = { { -2.10, 0.26, 0.20 }, { -1.60, 0.44, 0.32 }, { -0.80, 0.52, 0.37 }, { 0.00, 0.52, 0.36 },
  { 0.80, 0.46, 0.31 }, { 1.45, 0.42, 0.20 }, { 1.95, 0.46, 0.10, -0.02 }, { 2.50, 0.42, 0.065, -0.02 }, { 3.05, 0.30, 0.05, -0.02 },
  { 3.50, 0.16, 0.04, -0.02 }, { 3.78, 0.04, 0.02, -0.02 } }
local CLAYMORE_FLANK: Plates.Outline = { { -1.60, 0.14, 0.11 }, { -1.00, 0.28, 0.20 }, { -0.30, 0.31, 0.22 }, { 0.40, 0.24, 0.17 },
  { 0.95, 0.10, 0.07 } }
local CLAYMORE_TIER: Plates.Outline = { { -1.35, 0.16, 0.10 }, { -0.80, 0.32, 0.20 }, { -0.30, 0.34, 0.22 }, { 0.20, 0.26, 0.16 },
  { 0.60, 0.10, 0.06 } }
local CLAYMORE_KEEL: Plates.Outline = { { -0.65, 0.12, 0.07 }, { -0.10, 0.25, 0.15 }, { 0.50, 0.24, 0.14 }, { 1.05, 0.10, 0.06 } }
local function claymore(b: Builder)
  Plates.Loft(b, PLATING, CLAYMORE)
  pair(b, PLATING, CLAYMORE_FLANK, 0.60, -0.10)
  Plates.Loft(b, PATCH, CLAYMORE_TIER, 0, 0.40)
  Plates.Loft(b, PLATING, CLAYMORE_KEEL, 0, -0.40)
  fairings(b, CLAYMORE, 30, 0.55, 10, -1.90, 1.60)
  fairings(b, CLAYMORE, 26, 0.22, 11, -1.90, 1.70)
  fairings(b, CLAYMORE_FLANK, 9, 0.40, 12, -1.40, 0.70, 0.60, -0.10)
  fairings(b, CLAYMORE_TIER, 7, 0.34, 13, -1.20, 0.40, 0, 0.40)
  fairings(b, CLAYMORE_KEEL, 4, 0.30, 14, -0.50, 0.90, 0, -0.40)
  -- a ridge down the middle of the blade, above and below
  Plates.Fairing(b, TRIM, CLAYMORE, 2.80, BACK, 1.80, 0.10, 0.035)
  Plates.Fairing(b, TRIM, CLAYMORE, 2.80, KEEL, 1.80, 0.10, 0.035)
  -- the dome, its halo, and the spires
  lobe(b, PLATING, v(0, 0.66, -0.60), v(0.24, 0.18, 0.34))
  block(b, TRIM, v(0, 0.63, -0.60), v(0.245, 0.014, 0.345), nil, 0.9)
  block(b, GLOW, v(0, 0.70, -0.27), v(0.15, 0.024, 0.012), nil, 0.6)
  for index = 1, 8 do
    local angle = (index - 0.5) / 8 * 2 * math.pi
    lobe(b, PATCH, v(0.30 * math.cos(angle), 0.60, -0.60 + 0.42 * math.sin(angle)), v(0.05, 0.045, 0.05))
  end
  spire(b, v(0, 0.82, -0.60), 1.10, 0.03)
  for _, side in { -1, 1 } do
    spire(b, v(side * 0.20, 0.58, -0.95), 0.62, 0.022)
    thruster(b, v(side * 0.17, 0.10, -2.20), 0.22, 0.12)
    thruster(b, v(side * 0.18, -0.12, -2.18), 0.20, 0.11)
    thruster(b, v(side * 0.60, -0.10, -1.72), 0.18, 0.10)
  end
end

-- The Packet, a hauler, as a packet boat is: a slim hull that carries
-- its parcels where they can be seen. A slender spine with a blister
-- for the bridge at its bow and the engines at its stern, and under it,
-- in a row, four cargo sacs hung by necks: each a skin like the rest,
-- fuller toward its front, no two quite the same size. (The plan was
-- liked from the second drawing on; this is the fourth.)
local PACKET: Plates.Outline = { { -1.10, 0.04, 0.04, 0.30 }, { -0.70, 0.13, 0.11, 0.30 }, { 0.00, 0.17, 0.13, 0.30 },
  { 0.70, 0.14, 0.11, 0.30 }, { 1.10, 0.09, 0.07, 0.29 }, { 1.36, 0.03, 0.025, 0.28 } }
local PACKET_BRIDGE: Plates.Outline = { { 0.58, 0.02, 0.015 }, { 0.74, 0.08, 0.05 }, { 0.92, 0.055, 0.035 }, { 1.02, 0.02, 0.012 } }
local PACKET_SACS = { 0.74, 0.25, -0.24, -0.73 }
-- The outline of the cargo sac at 'z' (the 'index'th from the bow).
local function sac(index: number): Plates.Outline
  local z = PACKET_SACS[index]
  local swell = 1 + 0.10 * (if index % 2 == 0 then 1 else -1)
  return { { z - 0.21, 0.04, 0.04 }, { z - 0.09, 0.21 * swell, 0.19 * swell }, { z + 0.05, 0.25 * swell, 0.23 * swell },
    { z + 0.21, 0.05, 0.05 } }
end
local function packet(b: Builder)
  Plates.Loft(b, PLATING, PACKET)
  Plates.Loft(b, PATCH, PACKET_BRIDGE, 0, 0.405)
  block(b, GLOW, v(0, 0.44, 0.935), v(0.035, 0.009, 0.02), nil, 0.6)
  fairings(b, PACKET, 8, 0.30, 21, -0.90, 1.00)
  for index, z in PACKET_SACS do
    local outline = sac(index)
    Plates.Loft(b, if index % 2 == 0 then PATCH else PLATING, outline, 0, -0.13)
    fairings(b, outline, 4, 0.16, 30 + index, z - 0.12, z + 0.12, 0, -0.13)
    lobe(b, PLATING, v(0, 0.14, z), v(0.06, 0.07, 0.08))
  end
  for _, side in { -1, 1 } do
    thruster(b, v(side * 0.09, 0.31, -1.10), 0.15, 0.075)
  end
  thruster(b, v(0, 0.13, -1.04), 0.11, 0.055)
end

-- ---------------------------------------------------------------------
-- The Orun Confederation (the project owner's draft: human, anarchist;
-- "ships are very different in style from each other, because they're
-- designed by different groups within the confederation. Unifying visual
-- feature is red and gold highlights. Also, they tend to have a lot of
-- antenna masts"; and two pictures to go by, a long heavy warship built
-- in sections with frames wrapped round it, and a sheet of small craft
-- with forked noses, twin booms and engines in pods, no two alike).
--
-- So no two of their hulls are laid out alike or painted alike: a
-- forked gunboat, a ship of two hulls side by side, a long hull in
-- lengths, a ship of three hulls with a citadel on the middle one, two
-- slim hulls with a load of containers slung between them. (Of the
-- first five drawn the owner liked the ship of two hulls best by far,
-- and had the battleship and the hauler drawn again as ships of
-- several hulls.) What they share is heavy
-- plating in plain boxes, a red mark and a gold one on every hull, and
-- aerials wherever there is room for one. (All v0s.)

-- The paint of an Orun hull: its builders' own choice of plating, and
-- the Confederation's red and gold.
local function orun(plating: { number }, wear: number, rust: number): Look
  return {
    plating = plating, patch = { 0.74, 0.52, 0.13 }, frame = { 0.13, 0.13, 0.14 }, glow = { 1.0, 0.84, 0.50 },
    trim = { 0.62, 0.09, 0.07 }, wear = wear, rust = rust, sheets = 3.4, lights = 0.25,
    -- (their lights are warm and their engines burn blue: the owner's ruling)
    fire = { 0.40, 0.66, 1.0 },
  }
end
Hull.looks.orun = orun({ 0.36, 0.37, 0.39 }, 0.45, 0.20)
-- (for what else of theirs is painted by its builders: Game/View/Starbase)
Hull.OrunPaint = orun

-- An aerial: a thin pole from 'foot' the way 'toward' points (up, if
-- not said), with two cross-pieces and a gold tip.
local function aerial(b: Builder, foot: vector, height: number, toward: vector?)
  local dir = vector.normalize(toward or v(0, 1, 0))
  local side = vector.cross(dir, v(0, 0, 1))
  if vector.magnitude(side) < 0.3 then
    side = vector.cross(dir, v(1, 0, 0))
  end
  side = vector.normalize(side)
  local top = foot + dir * height
  local thick = math.max(0.006, height * 0.018)
  beam(b, FRAME, foot, top, thick, 0.1)
  -- (a stouter foot, with a red band round it)
  beam(b, FRAME, foot, foot + dir * (height * 0.22), thick * 1.7, 0.1)
  beam(b, TRIM, foot + dir * (height * 0.22), foot + dir * (height * 0.27), thick * 1.8, 0.1)
  for index, share in { 0.48, 0.66, 0.84 } do
    local at = foot + dir * (height * share)
    local reach = height * (0.20 - 0.045 * index)
    beam(b, FRAME, at - side * reach, at + side * reach, thick * 0.6, 0.1)
  end
  local tip = thick * 1.6
  block(b, PATCH, top, v(tip, tip, tip), nil, 0.5)
end

-- A stand of aerials in a row from one point to another, no two the
-- same height.
local function aerials(b: Builder, from: vector, to: vector, count: number, height: number, toward: vector?)
  for index = 1, count do
    local at = from + (to - from) * (if count == 1 then 0.5 else (index - 1) / (count - 1))
    aerial(b, at, height * (0.5 + 0.5 * chance(index * 7.1 + height * 31.7 + from.z * 3.3)), toward)
  end
end

-- An engine in a box: a square housing with a lit throat. 'length',
-- 'wide' and 'high' are half-sizes.
local function burner(b: Builder, center: vector, length: number, wide: number, high: number)
  block(b, PLATING, center, v(wide, high, length), nil, 0.10)
  block(b, FRAME, center + v(0, 0, -length * 0.92), v(wide * 0.90, high * 0.90, length * 0.14), nil, 0.2)
  block(b, Plates.FIRE, center + v(0, 0, -length * 1.05), v(wide * 0.68, high * 0.68, length * 0.03), nil, 0.3)
  exhaust(center + v(0, 0, -length * 1.09), math.min(wide, high) * 0.68)
end

-- The Mastiff, a frigate, from a works that builds small and fast: a
-- short thick body with two prongs run out ahead of it and a gap
-- between them, an engine in a pod out on a stub wing each side and a
-- third in the stern, a fin on each pod.
local function mastiff(b: Builder)
  block(b, PLATING, v(0, 0, -0.15), v(0.20, 0.11, 0.42), nil, 0.12)
  block(b, PLATING, v(0, 0.12, -0.26), v(0.13, 0.045, 0.26), nil, 0.2)
  block(b, GLOW, v(0, 0.125, 0.02), v(0.075, 0.022, 0.035), nil, 0.4)
  block(b, FRAME, v(0, -0.02, 0.30), v(0.10, 0.05, 0.07), nil, 0.1)
  for _, side in { -1, 1 } do
    -- a prong, stepped down to its tip, with a red stripe along its back
    -- (wide enough for a small gun's ring to turn on)
    block(b, PLATING, v(side * 0.17, -0.01, 0.56), v(0.070, 0.075, 0.38), nil, 0.14)
    block(b, PLATING, v(side * 0.17, -0.02, 1.02), v(0.045, 0.05, 0.12), nil, 0.2)
    block(b, TRIM, v(side * 0.17, 0.066, 0.62), v(0.045, 0.006, 0.26), nil, 0.2)
    block(b, PATCH, v(side * 0.17, -0.02, 1.15), v(0.032, 0.036, 0.015), nil, 0.3)
    -- the pod on its stub wing
    block(b, PLATING, v(side * 0.33, -0.02, -0.36), v(0.15, 0.024, 0.15), v(side * -0.22, 0, 0), 0.1)
    burner(b, v(side * 0.50, -0.02, -0.50), 0.24, 0.085, 0.085)
    block(b, PATCH, v(side * 0.50, -0.02, -0.245), v(0.094, 0.094, 0.014), nil, 0.2)
    block(b, PLATING, v(side * 0.53, 0.15, -0.60), v(0.012, 0.09, 0.11), v(0, 0, side * -0.30), 0.1)
    block(b, TRIM, v(side * 0.557, 0.235, -0.60), v(0.013, 0.012, 0.11), v(0, 0, side * -0.30), 0.1)
    aerial(b, v(side * 0.17, 0.03, 1.12), 0.24, v(side * 0.35, 0.25, 1))
    aerial(b, v(side * 0.50, -0.105, -0.40), 0.20, v(side * 0.2, -1, -0.2))
  end
  burner(b, v(0, 0, -0.66), 0.13, 0.10, 0.07)
  aerial(b, v(0.05, 0.165, -0.34), 0.50, v(0, 1, -0.35))
  aerial(b, v(-0.06, 0.165, -0.46), 0.34, v(-0.12, 1, -0.30))
  aerial(b, v(0.09, 0.165, -0.14), 0.26, v(0.15, 1, -0.2))
  aerial(b, v(0, -0.11, -0.10), 0.30, v(0, -1, -0.30))
  aerial(b, v(-0.08, -0.11, -0.40), 0.22, v(-0.1, -1, -0.4))
end

-- The Boar, a destroyer, from a yard that builds everything in pairs:
-- two long hulls side by side with a low deck between them and the
-- command house standing on that, girders across at bow and stern, and
-- two engines, one over the other, in the stern of each hull.
local function boar(b: Builder)
  for _, side in { -1, 1 } do
    local x = side * 0.36
    block(b, PLATING, v(x, 0, 0.05), v(0.15, 0.17, 1.05), nil, 0.10)
    block(b, PLATING, v(x, 0.02, 1.24), v(0.11, 0.12, 0.20), nil, 0.18)
    block(b, TRIM, v(x, 0.02, 1.45), v(0.08, 0.085, 0.03), nil, 0.25)
    block(b, PLATING, v(x + side * 0.13, -0.03, -0.20), v(0.06, 0.11, 0.55), nil, 0.12)
    block(b, PATCH, v(x, 0, 0.62), v(0.154, 0.174, 0.03), nil, 0.1)
    for _, z in { -0.62, 0.20 } do
      block(b, FRAME, v(x, 0, z), v(0.158, 0.178, 0.018), nil, 0.1)
    end
    ports(b, v(x + side * 0.152, 0.09, 0.30), v(x + side * 0.152, 0.09, 1.00), 5, 0.012)
    burner(b, v(x, 0.085, -1.16), 0.16, 0.11, 0.07)
    burner(b, v(x, -0.085, -1.16), 0.16, 0.11, 0.07)
    aerial(b, v(side * 0.55, 0.02, -0.55), 0.40, v(side, 0.30, -0.25))
    aerial(b, v(x, 0.14, 1.36), 0.34, v(side * 0.2, 0.5, 1))
  end
  block(b, PLATING, v(0, -0.04, 0.10), v(0.24, 0.05, 0.50), nil, 0.08)
  truss(b, v(-0.30, 0, 0.86), v(0.30, 0, 0.86), 0.12, 4)
  truss(b, v(-0.30, 0, -0.76), v(0.30, 0, -0.76), 0.14, 4)
  -- the house, with the bridge on top of it under a red roof
  block(b, PLATING, v(0, 0.10, 0.22), v(0.13, 0.10, 0.24), nil, 0.12)
  block(b, PLATING, v(0, 0.235, 0.14), v(0.09, 0.04, 0.13), nil, 0.2)
  block(b, GLOW, v(0, 0.24, 0.275), v(0.07, 0.014, 0.008), nil, 0.3)
  block(b, TRIM, v(0, 0.278, 0.14), v(0.092, 0.006, 0.133), nil, 0.2)
  aerials(b, v(-0.07, 0.28, 0.04), v(0.07, 0.28, 0.22), 5, 0.60)
  aerial(b, v(0, -0.09, 0.30), 0.34, v(0, -1, 0.25))
  aerial(b, v(0.10, -0.09, -0.20), 0.26, v(0.1, -1, -0.2))
  for _, side in { -1, 1 } do
    aerial(b, v(side * 0.36, 0.17, -0.90), 0.36, v(side * 0.15, 1, -0.3))
    aerial(b, v(side * 0.36, 0.17, 0.30), 0.28, v(side * 0.2, 1, 0.1))
  end
end

-- The Aurochs, a cruiser, from a yard that builds a hull a length at a
-- time and bolts the lengths together: five of them, no two quite the
-- same girth, with a neck showing between each and the next; rails
-- standing off the plating from stern to bow; a head split into two
-- cheeks; a house on its back, a bay under it, a sponson each side; and
-- four engines in the last length.
local AUROCHS: { { number } } = {
  -- (each length: where its middle is along z, half its length, half its width, half its height, how high it sits)
  { -1.15, 0.30, 0.36, 0.33, 0.00 }, { -0.52, 0.28, 0.26, 0.22, 0.03 }, { 0.08, 0.28, 0.34, 0.29, 0.00 },
  { 0.68, 0.27, 0.24, 0.20, 0.04 }, { 1.27, 0.28, 0.35, 0.32, -0.02 },
}
local function aurochs(b: Builder)
  for index, s in AUROCHS do
    block(b, PLATING, v(0, s[5], s[1]), v(s[3], s[4], s[2]), nil, 0.10)
    if index < #AUROCHS then
      local neck = s[1] + s[2] + 0.02
      block(b, FRAME, v(0, 0, neck), v(0.22, 0.19, 0.045), nil, 0.1)
      -- (a hoop round the neck, out at the rails)
      for _, side in { -1, 1 } do
        beam(b, FRAME, v(side * 0.39, -0.20, neck), v(side * 0.39, 0.20, neck), 0.020, 0.2)
        beam(b, FRAME, v(side * 0.39, 0.20, neck), v(side * 0.20, 0.345, neck), 0.020, 0.2)
        beam(b, FRAME, v(side * 0.39, -0.20, neck), v(side * 0.20, -0.345, neck), 0.020, 0.2)
      end
      beam(b, FRAME, v(-0.20, 0.345, neck), v(0.20, 0.345, neck), 0.020, 0.2)
      beam(b, FRAME, v(-0.20, -0.345, neck), v(0.20, -0.345, neck), 0.020, 0.2)
    end
  end
  for _, side in { -1, 1 } do
    for _, level in { -1, 1 } do
      beam(b, FRAME, v(side * 0.39, level * 0.20, -1.38), v(side * 0.39, level * 0.20, 1.46), 0.024, 0.2)
      -- (and one along each shoulder of the back and the belly)
      beam(b, FRAME, v(side * 0.20, level * 0.345, -1.38), v(side * 0.20, level * 0.345, 1.46), 0.022, 0.2)
    end
    -- a cheek of the head, with a red face
    block(b, PLATING, v(side * 0.22, -0.02, 1.69), v(0.11, 0.25, 0.15), nil, 0.14)
    block(b, TRIM, v(side * 0.22, -0.02, 1.845), v(0.095, 0.21, 0.010), nil, 0.14)
    -- a sponson, with a gold panel
    block(b, PLATING, v(side * 0.43, -0.06, 0.08), v(0.10, 0.14, 0.22), nil, 0.12)
    block(b, PATCH, v(side * 0.533, -0.06, 0.08), v(0.006, 0.10, 0.18), nil, 0.1)
    ports(b, v(side * 0.263, 0.12, -0.74), v(side * 0.263, 0.12, -0.30), 4, 0.013)
    ports(b, v(side * 0.243, 0.12, 0.46), v(side * 0.243, 0.12, 0.90), 4, 0.013)
    ports(b, v(side * 0.353, 0.10, 1.05), v(side * 0.353, 0.10, 1.50), 4, 0.013)
    for _, level in { -1, 1 } do
      burner(b, v(side * 0.16, level * 0.14, -1.50), 0.14, 0.12, 0.10)
    end
    aerial(b, v(side * 0.28, 0.22, 1.56), 0.66, v(side * 0.18, 0.28, 1))
    aerial(b, v(side * 0.30, -0.26, 1.52), 0.44, v(side * 0.25, -0.5, 1))
    aerial(b, v(side * 0.24, 0.24, 0.62), 0.42, v(side * 0.3, 1, 0))
    aerial(b, v(side * 0.30, 0.33, -1.20), 0.50, v(side * 0.25, 1, -0.2))
  end
  block(b, FRAME, v(0, -0.02, 1.60), v(0.11, 0.16, 0.06), nil, 0.1)
  block(b, TRIM, v(0, 0, -0.93), v(0.365, 0.335, 0.03), nil, 0.1)
  -- the house on its back, the bridge at the front of it under a gold roof
  block(b, PLATING, v(0, 0.36, 0.02), v(0.16, 0.08, 0.20), nil, 0.14)
  block(b, GLOW, v(0, 0.385, 0.225), v(0.11, 0.015, 0.008), nil, 0.3)
  block(b, PATCH, v(0, 0.445, 0.02), v(0.165, 0.008, 0.205), nil, 0.14)
  aerials(b, v(-0.12, 0.45, -0.14), v(0.12, 0.45, 0.10), 5, 0.62)
  -- the bay under it, its mouth lit
  block(b, PLATING, v(0, -0.36, -0.40), v(0.20, 0.07, 0.30), nil, 0.1)
  block(b, GLOW, v(0, -0.36, -0.095), v(0.15, 0.035, 0.006), nil, 0.2)
  aerial(b, v(0, -0.29, 1.20), 0.46, v(0, -1, 0.3))
  aerial(b, v(0.12, -0.31, -1.10), 0.34, v(0.15, -1, -0.2))
end

-- The Mammoth, a battleship, from a yard that builds in threes: a great
-- hull in the middle, tall, with a citadel rising in three stages from
-- its back, and a lesser hull out on each side of it, lower and set
-- back, each joined to it by a wing of deck and two girders. Ten
-- engines: four in the middle hull and two, one over the other, in
-- each of the others. (Redrawn as a ship of several hulls at the
-- project owner's word, who liked the Boar best of the first five: it
-- was one slab of a hull with jaws for a bow.)
local function mammoth(b: Builder)
  -- the middle hull, its bow stepped down twice to a red nose
  block(b, PLATING, v(0, 0, 0.10), v(0.34, 0.40, 2.30), nil, 0.08)
  block(b, PLATING, v(0, 0.03, 2.74), v(0.26, 0.30, 0.36), nil, 0.14)
  block(b, PLATING, v(0, 0.05, 3.24), v(0.17, 0.20, 0.17), nil, 0.2)
  block(b, TRIM, v(0, 0.05, 3.42), v(0.14, 0.165, 0.012), nil, 0.2)
  block(b, PATCH, v(0, 0, 1.60), v(0.345, 0.405, 0.05), nil, 0.08)
  for _, z in { -1.45, -0.20, 0.85 } do
    block(b, FRAME, v(0, 0, z), v(0.35, 0.41, 0.025), nil, 0.1)
  end
  block(b, TRIM, v(0, 0, -2.10), v(0.348, 0.408, 0.035), nil, 0.08)
  for _, side in { -1, 1 } do
    for _, level in { -1, 1 } do
      burner(b, v(side * 0.165, level * 0.195, -2.40), 0.22, 0.145, 0.165)
    end
    ports(b, v(side * 0.343, 0.22, 1.75), v(side * 0.343, 0.22, 2.35), 5, 0.016)
    ports(b, v(side * 0.343, 0.22, -1.25), v(side * 0.343, 0.22, -0.35), 7, 0.016)
    ports(b, v(side * 0.263, 0.57, -1.00), v(side * 0.263, 0.57, -0.10), 6, 0.016)
    ports(b, v(side * 0.183, 0.86, -0.92), v(side * 0.183, 0.86, -0.38), 4, 0.014)

    -- an outer hull
    local x = side * 0.92
    block(b, PLATING, v(x, -0.12, -0.60), v(0.20, 0.24, 1.55), nil, 0.10)
    block(b, PLATING, v(x, -0.10, 1.18), v(0.15, 0.17, 0.26), nil, 0.16)
    block(b, TRIM, v(x, -0.10, 1.45), v(0.115, 0.125, 0.012), nil, 0.16)
    block(b, PATCH, v(x, -0.12, 0.40), v(0.204, 0.244, 0.04), nil, 0.1)
    for _, z in { -1.50, -0.45 } do
      block(b, FRAME, v(x, -0.12, z), v(0.208, 0.248, 0.022), nil, 0.1)
    end
    block(b, PLATING, v(x + side * 0.17, -0.16, -0.80), v(0.07, 0.15, 0.70), nil, 0.12)
    ports(b, v(x + side * 0.203, 0.02, 0.00), v(x + side * 0.203, 0.02, 0.95), 7, 0.015)
    burner(b, v(x, 0.00, -2.31), 0.19, 0.15, 0.10)
    burner(b, v(x, -0.24, -2.31), 0.19, 0.15, 0.10)
    -- what joins it to the middle hull
    truss(b, v(side * 0.34, -0.10, 0.60), v(side * 0.72, -0.10, 0.60), 0.24, 3)
    truss(b, v(side * 0.34, -0.10, -1.75), v(side * 0.72, -0.10, -1.75), 0.24, 3)
    block(b, PLATING, v(side * 0.53, -0.14, -0.55), v(0.20, 0.045, 0.85), nil, 0.08)
    aerial(b, v(x, 0.07, 1.30), 0.60, v(side * 0.25, 0.5, 1))
    aerial(b, v(x + side * 0.10, 0.12, -0.30), 0.55, v(side * 0.35, 1, 0))
    aerial(b, v(x + side * 0.10, 0.12, -1.60), 0.42, v(side * 0.3, 1, -0.2))
    aerial(b, v(x, -0.36, 0.20), 0.40, v(side * 0.2, -1, 0.2))
    aerial(b, v(side * 0.20, 0.40, 2.20), 0.70, v(side * 0.2, 1, 0.4))
  end
  -- the citadel, the bridge at the top of it under a gold roof
  block(b, PLATING, v(0, 0.56, -0.55), v(0.26, 0.16, 0.55), nil, 0.10)
  block(b, PLATING, v(0, 0.85, -0.65), v(0.18, 0.13, 0.34), nil, 0.12)
  block(b, PLATING, v(0, 1.06, -0.70), v(0.11, 0.085, 0.20), nil, 0.16)
  block(b, GLOW, v(0, 1.07, -0.495), v(0.085, 0.02, 0.008), nil, 0.3)
  block(b, PATCH, v(0, 1.15, -0.70), v(0.115, 0.008, 0.205), nil, 0.16)
  aerials(b, v(-0.09, 1.155, -0.86), v(0.09, 1.155, -0.58), 6, 0.95)
  aerials(b, v(-0.22, 0.72, -1.04), v(0.22, 0.72, -1.04), 4, 0.60)
  aerial(b, v(0, 0.21, 3.30), 0.80, v(0, 0.45, 1))
  aerial(b, v(0, -0.40, 0.60), 0.62, v(0, -1, 0.2))
  aerial(b, v(0, -0.40, -1.20), 0.46, v(0, -1, -0.15))
end

-- The Ox, a hauler, from people who move boxes: two slim hulls set
-- well apart, with the load slung between them on beams, three boxes
-- abreast above and below, nobody's two alike; and the house at the
-- stern on a span from one hull to the other, tall and narrow, with
-- the bridge on top of it looking out over the load. (Redrawn as a
-- ship of two hulls at the project owner's word: it was one flat bed.)
local OX_BOXES = { PLATING, PLATING, TRIM, PLATING, PATCH, PLATING, PLATING, PLATING, TRIM, PLATING }
local function ox(b: Builder)
  for _, side in { -1, 1 } do
    local x = side * 0.43
    block(b, PLATING, v(x, 0, 0.00), v(0.09, 0.13, 1.30), nil, 0.10)
    block(b, PLATING, v(x, 0.01, 1.43), v(0.065, 0.09, 0.14), nil, 0.2)
    block(b, TRIM, v(x, 0.01, 1.58), v(0.05, 0.068, 0.012), nil, 0.2)
    block(b, PATCH, v(x, 0, 1.06), v(0.094, 0.134, 0.025), nil, 0.1)
    for _, z in { -0.80, 0.14 } do
      block(b, FRAME, v(x, 0, z), v(0.096, 0.136, 0.015), nil, 0.1)
    end
    ports(b, v(x + side * 0.092, 0.06, -0.60), v(x + side * 0.092, 0.06, 0.95), 9, 0.011)
    burner(b, v(x, 0, -1.44), 0.15, 0.085, 0.10)
    aerial(b, v(x, 0.10, 1.48), 0.34, v(side * 0.25, 0.6, 1))
    aerial(b, v(x + side * 0.09, 0.02, -0.30), 0.36, v(side, 0.35, -0.2))
    aerial(b, v(x, -0.13, 0.60), 0.26, v(side * 0.2, -1, 0.2))
  end
  -- the load, hung from a beam at the head of each row
  local n = 0
  for row = 1, 5 do
    local z = 0.90 - (row - 1) * 0.42
    beam(b, FRAME, v(-0.35, 0, z + 0.208), v(0.35, 0, z + 0.208), 0.022, 0.2)
    for column = -1, 1 do
      for _, level in { 1, -1 } do
        n += 1
        -- (a place or two is empty)
        if chance(n * 3.7) > 0.12 then
          local tall = 0.09 + 0.05 * chance(n * 1.3)
          block(b, OX_BOXES[(n * 7) % #OX_BOXES + 1], v(column * 0.213, level * (0.012 + tall), z), v(0.098, tall, 0.19), nil, 0.05)
        end
      end
    end
  end
  beam(b, FRAME, v(-0.35, 0, -0.99), v(0.35, 0, -0.99), 0.022, 0.2)
  truss(b, v(-0.34, 0, 1.22), v(0.34, 0, 1.22), 0.12, 4)
  -- the span at the stern, and the house on it
  block(b, PLATING, v(0, 0.02, -1.12), v(0.35, 0.07, 0.13), nil, 0.1)
  block(b, PLATING, v(0, 0.25, -1.13), v(0.15, 0.16, 0.11), nil, 0.12)
  block(b, PLATING, v(0, 0.47, -1.11), v(0.20, 0.06, 0.13), nil, 0.14)
  block(b, GLOW, v(0, 0.48, -0.975), v(0.17, 0.022, 0.008), nil, 0.3)
  block(b, PATCH, v(0, 0.535, -1.11), v(0.205, 0.008, 0.135), nil, 0.14)
  aerials(b, v(-0.16, 0.54, -1.20), v(0.16, 0.54, -1.05), 6, 0.56)
  aerial(b, v(0, -0.05, -1.12), 0.30, v(0, -1, -0.2))
end

-- ---------------------------------------------------------------------
-- The Kethri
--
-- Nomads (their draft is in Core/Data/Factions): "lots of sharp edges,
-- flat grey plates, arrowheads, conning towers", in the manner of Star
-- Wars' Empire without being any ship of it. Every hull is a blade in
-- flat plates (Plates.Hard): it comes to a point at the bow, is widest
-- at its barbs well aft, and is sharp at its edge all the way round;
-- its barbs run on back past the stern; a conning tower stands on its
-- back toward the stern, small on the hull; and its engines are in a
-- row across the stern. Flat grey throughout, the edge marked dark.

-- A blade is drawn through rows, bow to stern. A row: where it is along
-- z; half the blade's width at its edge there; how high its back stands
-- over the edge, and half the width of the flat along the back; how
-- deep its keel is, and half the width of the flat along that; and, if
-- the blade is not on the hull's middle line at the height of its
-- edge, how far aside and how high.
type Row = { number }

local function sectionOf(row: Row): Plates.Section
  local z, w, t, d, k, f, x, y = row[1], row[2], row[3], row[4], row[5], row[6], row[7] or 0, row[8] or 0
  return { z = z, ring = { v(x + d, y + t, 0), v(x + w, y, 0), v(x + f, y - k, 0), v(x - f, y - k, 0), v(x - w, y, 0), v(x - d, y + t, 0) } }
end

local function hard(b: Builder, part: number, rows: { Row })
  local sections: { Plates.Section } = {}
  for index, row in rows do
    sections[index] = sectionOf(row)
  end
  Plates.Hard(b, part, sections)
end

-- A blade as it is at 'z', between its rows.
local function rowAt(rows: { Row }, z: number): Row
  for index = 1, #rows - 1 do
    local a, c = rows[index], rows[index + 1]
    if z <= a[1] and z >= c[1] then
      local s = (a[1] - z) / math.max(a[1] - c[1], 1e-6)
      local out: Row = { z }
      for field = 2, 8 do
        local p, q = a[field] or 0, c[field] or 0
        out[field] = p + (q - p) * s
      end
      return out
    end
  end
  local last = rows[#rows]
  return { last[1], last[2], last[3], last[4], last[5], last[6], last[7] or 0, last[8] or 0 }
end

-- Places on a blade: on the middle of its back, under the middle of its
-- keel, and on its edge to one side (1 starboard, -1 port).
local function topOf(rows: { Row }, z: number, lift: number?): vector
  local row = rowAt(rows, z)
  return v(row[7], row[8] + row[3] + (lift or 0), z)
end

local function keelOf(rows: { Row }, z: number): vector
  local row = rowAt(rows, z)
  return v(row[7], row[8] - row[5], z)
end

local function edgeOf(rows: { Row }, z: number, side: number): vector
  local row = rowAt(rows, z)
  return v(row[7] + side * row[2], row[8], z)
end

-- A barb: a lesser blade lying beside the hull, from where it leaves
-- the hull's edge back to a point. 'side' is which side; it is 'x'
-- aside at its root and 'to' at its point.
local function barbOf(side: number, from: number, back: number, x: number, to: number, w: number, t: number, k: number): { Row }
  return { { from, w, t, 0, k, 0, side * x, 0 }, { back, 0, 0, 0, 0, 0, side * to, 0 } }
end

-- A tier: a low blade laid along a hull's back. Each of 'steps' is
-- where along z, half its width at the foot, how high it stands, and
-- half the width of its flat top.
local function tierOn(rows: { Row }, steps: { { number } }): { Row }
  local tier: { Row } = {}
  for index, step in steps do
    local under = rowAt(rows, step[1])
    -- (its foot goes down as far as the back it stands on has fallen
    -- away by there, and a little into it)
    local fallen = if step[2] > under[4] then under[3] * (step[2] - under[4]) / math.max(under[2] - under[4], 1e-6) else 0
    tier[index] = { step[1], step[2], step[3], step[4], fallen + 0.012, step[2], under[7], under[8] + under[3] - 0.006 }
  end
  return tier
end

-- The edge of a blade, marked: a dark line along it each side.
local function edged(b: Builder, rows: { Row }, thick: number)
  for index = 1, #rows - 1 do
    for _, side in { 1, -1 } do
      beam(b, TRIM, edgeOf(rows, rows[index][1], side), edgeOf(rows, rows[index + 1][1], side), thick, 0.1)
    end
  end
end

-- A conning tower: a narrow blade standing on the back, the bridge
-- across the top of it and lit forward, a house at its foot and a mast.
local function conning(b: Builder, foot: vector, height: number)
  local h = height
  block(b, PLATING, foot + v(0, h * 0.46, 0), v(h * 0.085, h * 0.50, h * 0.24), nil, 0.05)
  block(b, PATCH, foot + v(0, h * 0.20, -h * 0.16), v(h * 0.14, h * 0.24, h * 0.22), nil, 0.05)
  block(b, PATCH, foot + v(0, h * 0.99, h * 0.05), v(h * 0.30, h * 0.07, h * 0.15), nil, 0.08)
  block(b, GLOW, foot + v(0, h * 0.99, h * 0.205), v(h * 0.26, h * 0.026, h * 0.012), nil, 0.1)
  beam(b, FRAME, foot + v(0, h * 1.05, -h * 0.05), foot + v(0, h * 1.34, -h * 0.05), h * 0.022, 0.1)
end

-- A house on a hull's back: a plain block, some of them lit along a side.
local function house(b: Builder, foot: vector, wide: number, high: number, long: number, lit: boolean?)
  block(b, if lit then PATCH else PLATING, foot + v(0, high * 0.6, 0), v(wide, high, long), nil, 0.06)
  if lit then
    for _, side in { 1, -1 } do
      block(b, GLOW, foot + v(side * wide, high * 0.9, 0), v(wide * 0.04, high * 0.16, long * 0.7), nil, 0.1)
    end
  end
end

-- A drive: a throat standing out of the stern, lit. 'at' is the middle
-- of it on the stern's face; 'wide' and 'high' are half its size.
local function drive(b: Builder, at: vector, wide: number, high: number)
  block(b, FRAME, at + v(0, 0, -0.02), v(wide, high, 0.05), nil, 0.2)
  block(b, Plates.FIRE, at + v(0, 0, -0.074), v(wide * 0.78, high * 0.74, 0.008), nil, 0.3)
  exhaust(at + v(0, 0, -0.09), math.min(wide, high) * 0.78)
end

-- Where a weapon stands on a blade. A hardpoint is never on a surface
-- too small for the whole foot of what stands on it (the owner's rule,
-- for every ship; it was these hulls that showed it, with guns out on
-- the sharp edge "hanging off into space"). So a mount here is on one of
-- a blade's faces, and is refused where the face is too small: the flat
-- along its back or along its keel, or the sloped armour between a flat
-- and the edge, topside or underneath.

-- How far a weapon's foot reaches from its middle on a hull (as far as
-- a turret's ring does while it turns), in the hull's own units: the
-- hull's type, half the length it is drawn, and the weapon's size (1
-- small to 3 large).
-- (The hulls these drawings were of are gone, the Kethri's ships being
-- the owner's list of them now, and the drawings are nobody's: each is
-- still measured as the hull of its class it was drawn for.)
local DRAWN_FOR: { [string]: number } = { frigate = 42, destroyer = 75, cruiser = 150, industrial = 180, battleship = 400 }
local function footOn(type: string, reach: number, size: number): number
  local hull = Ships.byId[type]
  local radius = if hull then hull.radius else DRAWN_FOR[string.match(type, "^(%a+)%.") or ""] or 42
  return Arms.REACH * Arms.SIZE[size] * reach / radius
end

-- A place on a face of a blade at 'z'. On the back or the keel, its
-- middle line. On a slope ("top" or "bottom", to the side 'side'),
-- 'share' of the way from the flat to the edge.
local function faceAt(rows: { Row }, z: number, face: string, side: number, share: number): vector
  local row = rowAt(rows, z)
  if face == "back" then
    return v(row[7], row[8] + row[3], z)
  elseif face == "keel" then
    return v(row[7], row[8] - row[5], z)
  elseif face == "top" then
    return v(row[7] + side * (row[4] + (row[2] - row[4]) * share), row[8] + row[3] * (1 - share), z)
  end
  return v(row[7] + side * (row[6] + (row[2] - row[6]) * share), row[8] - row[5] * (1 - share), z)
end

-- A mount on a face of a blade, standing straight out of it. 'foot' is
-- footOn's. On a slope it stands in the middle of what is free of the
-- slope: all of it, or what a tier laid on the back ('under') leaves
-- uncovered. An error if the face has not room for the foot there.
local function mountOn(name: string, rows: { Row }, z: number, face: string, side: number, foot: number, under: { Row }?): Mount
  local share = 0.5
  for _, at in { z - foot, z, z + foot } do
    local row = rowAt(rows, at)
    local room: number
    if face == "back" then
      room = row[4]
    elseif face == "keel" then
      room = row[6]
    else
      -- (how long the slope is, and how much of it, from the flat, is covered)
      local flat = if face == "top" then row[4] else row[6]
      local long = math.sqrt((row[2] - flat) ^ 2 + (if face == "top" then row[3] else row[5]) ^ 2)
      local covered = 0
      if under and face == "top" and at <= under[1][1] and at >= under[#under][1] then
        covered = math.max(0, rowAt(under, at)[2] - flat) / math.max(row[2] - flat, 1e-6)
      end
      if at == z then
        share = (covered + 1) / 2
      end
      room = long * (1 - covered) / 2
    end
    assert(room >= foot, `the {name} has a mount on its {face} at {z} where there is not room for it: {room} to stand on, and a foot of {foot}`)
  end
  -- (the way out of the face: across it, and along it)
  local e = 0.01
  local along = faceAt(rows, z + e, face, side, share) - faceAt(rows, z - e, face, side, share)
  local across = if face == "top" or face == "bottom"
    then faceAt(rows, z, face, side, share + e) - faceAt(rows, z, face, side, share - e)
    else v(1, 0, 0)
  local out = vector.normalize(vector.cross(along, across))
  if (out.y < 0) ~= (face == "keel" or face == "bottom") then
    out = -out
  end
  return { at = faceAt(rows, z, face, side, share), up = out }
end

-- A hardpoint on the sloped armour: one mount topside on the side
-- 'side' of the hull, and its twin underneath on the other.
local function slopes(name: string, rows: { Row }, z: number, side: number, foot: number, under: { Row }?): Hardpoint
  return { mountOn(name, rows, z, "top", side, foot, under), mountOn(name, rows, z, "bottom", -side, foot) }
end

-- A hardpoint on the flats: one mount on a back (the hull's, or a
-- tier's), and its twin under the keel.
local function flats(name: string, back: { Row }, backZ: number, keel: { Row }, keelZ: number, foot: number): Hardpoint
  return { mountOn(name, back, backZ, "back", 0, foot), mountOn(name, keel, keelZ, "keel", 0, foot) }
end

-- The Lancer, a frigate: a spearhead. One blade from its point to two
-- short barbs, a tower over the stern, two drives.
local LANCER: { Row } = {
  { 1.20, 0, 0, 0, 0, 0 }, { 0.55, 0.13, 0.045, 0.012, 0.030, 0.03 }, { -0.35, 0.36, 0.10, 0.05, 0.06, 0.10 },
  { -0.62, 0.22, 0.11, 0.07, 0.06, 0.10 }, { -0.80, 0.20, 0.10, 0.07, 0.055, 0.09 },
}
local LANCER_FOOT = footOn("frigate.lancer", 1.10, 1)
local function lancer(b: Builder)
  hard(b, PLATING, LANCER)
  for _, side in { 1, -1 } do
    hard(b, PLATING, barbOf(side, -0.26, -1.00, 0.29, 0.42, 0.075, 0.024, 0.016))
  end
  edged(b, LANCER, 0.007)
  house(b, topOf(LANCER, 0.08, -0.012), 0.032, 0.022, 0.10)
  house(b, topOf(LANCER, -0.17, -0.012), 0.048, 0.028, 0.075, true)
  conning(b, topOf(LANCER, -0.50, -0.012), 0.17)
  drive(b, v(0.085, 0.022, -0.80), 0.058, 0.048)
  drive(b, v(-0.085, 0.022, -0.80), 0.058, 0.048)
end

-- The Gantry, a destroyer: a sword. A long narrow blade with a low tier
-- along its back from the middle aft, long barbs, three drives.
local GANTRY: { Row } = {
  { 1.55, 0, 0, 0, 0, 0 }, { 0.90, 0.12, 0.05, 0.02, 0.04, 0.04 }, { -0.30, 0.30, 0.12, 0.07, 0.08, 0.12 },
  { -0.95, 0.42, 0.13, 0.09, 0.08, 0.14 }, { -1.18, 0.25, 0.13, 0.09, 0.07, 0.12 }, { -1.35, 0.23, 0.12, 0.09, 0.065, 0.11 },
}
local GANTRY_TIER = tierOn(GANTRY, { { 0.45, 0, 0, 0 }, { -0.10, 0.085, 0.05, 0.045 }, { -1.02, 0.12, 0.07, 0.075 }, { -1.22, 0.09, 0.06, 0.055 } })
local GANTRY_FOOT = footOn("destroyer.gantry", 1.585, 1)
local function gantry(b: Builder)
  hard(b, PLATING, GANTRY)
  hard(b, PLATING, GANTRY_TIER)
  for _, side in { 1, -1 } do
    hard(b, PLATING, barbOf(side, -0.84, -1.62, 0.34, 0.50, 0.085, 0.028, 0.018))
  end
  edged(b, GANTRY, 0.008)
  house(b, topOf(GANTRY, 0.62, -0.012), 0.030, 0.022, 0.09)
  house(b, topOf(GANTRY_TIER, -0.22, -0.012), 0.040, 0.026, 0.085, true)
  house(b, topOf(GANTRY_TIER, -0.50, -0.012), 0.055, 0.034, 0.075)
  conning(b, topOf(GANTRY_TIER, -0.86, -0.012), 0.22)
  for _, x in { -0.125, 0, 0.125 } do
    drive(b, v(x, 0.028, -1.35), 0.050, 0.055)
  end
end

-- The Trellis, a cruiser: a broadhead. A wide blade with a citadel on
-- its back, a long barb out on each side past a deep notch, four drives.
local TRELLIS: { Row } = {
  { 1.60, 0, 0, 0, 0, 0 }, { 0.60, 0.30, 0.10, 0.04, 0.06, 0.10 }, { -0.55, 0.74, 0.17, 0.12, 0.10, 0.24 },
  { -0.95, 0.36, 0.17, 0.12, 0.10, 0.20 }, { -1.15, 0.32, 0.16, 0.12, 0.09, 0.18 },
}
local TRELLIS_TIER = tierOn(TRELLIS, { { 0.15, 0, 0, 0 }, { -0.28, 0.16, 0.06, 0.10 }, { -1.00, 0.20, 0.08, 0.13 }, { -1.12, 0.16, 0.07, 0.10 } })
local TRELLIS_BARB: { [number]: { Row } } = {
  [1] = barbOf(1, -0.46, -1.62, 0.60, 0.74, 0.15, 0.05, 0.03), [-1] = barbOf(-1, -0.46, -1.62, 0.60, 0.74, 0.15, 0.05, 0.03),
}
local TRELLIS_FOOT = footOn("cruiser.trellis", 1.61, 2)
local function trellis(b: Builder)
  hard(b, PLATING, TRELLIS)
  hard(b, PLATING, TRELLIS_TIER)
  for _, side in { 1, -1 } do
    hard(b, PLATING, TRELLIS_BARB[side])
  end
  edged(b, TRELLIS, 0.009)
  house(b, topOf(TRELLIS, 0.72, -0.012), 0.035, 0.024, 0.10)
  house(b, topOf(TRELLIS, 0.38, -0.012), 0.050, 0.030, 0.085, true)
  house(b, topOf(TRELLIS_TIER, -0.18, -0.012), 0.060, 0.036, 0.085)
  house(b, topOf(TRELLIS_TIER, -0.45, -0.012), 0.085, 0.045, 0.075, true)
  conning(b, topOf(TRELLIS_TIER, -0.76, -0.012), 0.28)
  for _, x in { -0.205, -0.07, 0.07, 0.205 } do
    drive(b, v(x, 0.035, -1.15), 0.052, 0.060)
  end
end

-- The Spire, a battleship: a great broadhead in three tiers, each a
-- blade laid on the one below, with the tower the class is named for
-- standing tall on the last, a fin under the keel below it, long barbs,
-- and three great drives.
local SPIRE: { Row } = {
  { 2.70, 0, 0, 0, 0, 0 }, { 1.40, 0.34, 0.12, 0.05, 0.10, 0.10 }, { -0.90, 1.00, 0.26, 0.16, 0.18, 0.32 },
  { -1.60, 0.54, 0.27, 0.18, 0.18, 0.30 }, { -2.00, 0.48, 0.25, 0.18, 0.16, 0.26 },
}
local SPIRE_TIER = tierOn(SPIRE, { { 1.15, 0, 0, 0 }, { 0.30, 0.20, 0.07, 0.12 }, { -1.55, 0.34, 0.11, 0.20 }, { -1.90, 0.26, 0.09, 0.16 } })
local SPIRE_CROWN = tierOn(SPIRE_TIER, { { -0.10, 0, 0, 0 }, { -0.50, 0.13, 0.06, 0.08 }, { -1.45, 0.17, 0.07, 0.10 }, { -1.62, 0.12, 0.05, 0.07 } })
local SPIRE_BARB: { [number]: { Row } } = {
  [1] = barbOf(1, -0.80, -2.70, 0.80, 0.98, 0.22, 0.07, 0.05), [-1] = barbOf(-1, -0.80, -2.70, 0.80, 0.98, 0.22, 0.07, 0.05),
}
local SPIRE_FOOT = footOn("battleship.spire", 2.70, 3)
local function spireShip(b: Builder)
  hard(b, PLATING, SPIRE)
  hard(b, PLATING, SPIRE_TIER)
  hard(b, PLATING, SPIRE_CROWN)
  for _, side in { 1, -1 } do
    hard(b, PLATING, SPIRE_BARB[side])
  end
  edged(b, SPIRE, 0.012)
  for index, z in { 1.70, 1.32, 0.95, 0.62 } do
    house(b, topOf(if z > 1.15 then SPIRE else SPIRE_TIER, z, -0.014), 0.034 + 0.012 * index, 0.026 + 0.006 * index, 0.11, index % 2 == 0)
  end
  house(b, topOf(SPIRE_TIER, 0.22, -0.014), 0.085, 0.050, 0.10, true)
  house(b, topOf(SPIRE_CROWN, -0.62, -0.014), 0.070, 0.045, 0.09)
  house(b, topOf(SPIRE_CROWN, -0.90, -0.014), 0.090, 0.055, 0.08, true)
  conning(b, topOf(SPIRE_CROWN, -1.22, -0.014), 0.62)
  -- the fin under the keel, below the tower
  local under = keelOf(SPIRE, -1.25)
  block(b, PLATING, under + v(0, -0.20, 0.02), v(0.022, 0.22, 0.34), v(0.10, 0, 0), 0.05)
  block(b, TRIM, under + v(0, -0.43, -0.02), v(0.026, 0.014, 0.30), v(0.10, 0, 0), 0.1)
  for _, x in { -0.27, 0, 0.27 } do
    drive(b, v(x, 0.045, -2.00), 0.105, if x == 0 then 0.135 else 0.11)
  end
end

-- The Lighter, a hauler: a hold with a wedge for a bow. A long six-sided
-- body, flat on its back and its keel, drawn to a level edge at the
-- bow; hatches along the back, cargo doors down each flank, the bridge
-- in a tower over the stern as a freighter's is, two drives.
local LIGHTER: { Row } = {
  { 1.40, 0.24, 0, 0.24, 0, 0.24 }, { 0.85, 0.44, 0.24, 0.26, 0.24, 0.28 }, { -0.85, 0.44, 0.24, 0.26, 0.24, 0.28 },
  { -1.15, 0.40, 0.22, 0.24, 0.20, 0.24 }, { -1.35, 0.34, 0.18, 0.20, 0.16, 0.20 },
}
local LIGHTER_FOOT = footOn("industrial.lighter", 1.42, 1)
local function lighter(b: Builder)
  hard(b, PLATING, LIGHTER)
  edged(b, LIGHTER, 0.009)
  for index, z in { 0.60, 0.28, -0.04, -0.36, -0.68 } do
    block(b, PATCH, v(0, 0.243, z), v(0.19, 0.008, 0.13), nil, 0.1)
    block(b, FRAME, v(0, 0.250, z), v(0.012, 0.006, 0.12), nil, 0.1)
    for _, side in { 1, -1 } do
      block(b, if (index + side) % 2 == 0 then PATCH else PLATING, v(side * 0.45, 0, z), v(0.035, 0.11, 0.125), nil, 0.08)
    end
  end
  conning(b, topOf(LIGHTER, -1.02, -0.012), 0.26)
  drive(b, v(0.135, 0.01, -1.35), 0.085, 0.085)
  drive(b, v(-0.135, 0.01, -1.35), 0.085, 0.085)
end

-- A mount: a place on the hull where a weapon can stand. Where it is,
-- the way out of the hull there, and the way what stands on it faces at
-- rest (forward, if not said).
export type Mount = { at: vector, up: vector, fore: vector? }

-- A hardpoint is a pair of mounts on opposite sides of the hull (the
-- project owner's note): whichever way the ship is heading,
-- one of the two can see the target, so a ship's heading never keeps it
-- from firing, and only range, angle and how fast its guns can turn
-- decide a shot. What is fitted to a hardpoint stands on both of its
-- mounts and fires from the one that faces what it shoots at. What that
-- is is the pilot's business (Game/View/Arms).
export type Hardpoint = { Mount }

local UP, DOWN, PORT, STARBOARD = v(0, 1, 0), v(0, -1, 0), v(-1, 0, 0), v(1, 0, 0)

-- A hardpoint whose mounts are a deck apart: one on top, one beneath.
local function over(top: vector, bottom: vector, fore: vector?): Hardpoint
  return { { at = top, up = UP, fore = fore }, { at = bottom, up = DOWN, fore = fore } }
end

-- A hardpoint whose mounts are a beam apart: one to starboard, one to port.
local function abeam(starboard: vector, port: vector): Hardpoint
  return { { at = starboard, up = STARBOARD }, { at = port, up = PORT } }
end

-- A mount on a hull drawn in the generator's manner: where it stands
-- and which way is up for it as the hull is drawn, in the generator's
-- units, taken through the hull's bend (the face it stands on is tilted
-- by the bend, and it with the face).
local function bentBy(bend: Bend, at: vector, up: vector): Mount
  local p = at * GROWN
  -- (the bend breaks on the centre line: the tilt is measured a little
  -- to one side of it, and stepping away from it)
  local small = 0.002
  local from = if math.abs(p.x) < small then p + v(small, 0, 0) else p
  local one = vector.normalize(vector.cross(up, if math.abs(up.z) < 0.9 then v(0, 0, 1) else v(1, 0, 0)))
  local other = vector.cross(up, one)
  local function along(way: vector): vector
    if way.x * from.x < 0 then
      way = -way
    end
    return (bend(from + way * small) - bend(from)) / small
  end
  local tilted = vector.normalize(vector.cross(along(one), along(other)))
  if vector.dot(tilted, up) < 0 then
    tilted = -tilted
  end
  return { at = bend(p), up = tilted }
end

local function bentMount(w: Warps, at: vector, up: vector): Mount
  return bentBy(warped(w), at, up)
end

local function bentOver(w: Warps, top: vector, bottom: vector): Hardpoint
  return { bentMount(w, top, UP), bentMount(w, bottom, DOWN) }
end

local function bentAbeam(w: Warps, starboard: vector, port: vector): Hardpoint
  return { bentMount(w, starboard, STARBOARD), bentMount(w, port, PORT) }
end

-- Hardpoints, and exhausts, so many times as far from the middle of the
-- hull they are on: for a hull that is made bigger than it was drawn
-- (a bare one: Plates' 'scale').
local function hardpointsOut(points: { Hardpoint }, by: number): { Hardpoint }
  local out: { Hardpoint } = {}
  for _, point in points do
    local moved: Hardpoint = {}
    for _, mount in point do
      table.insert(moved, { at = mount.at * by, up = mount.up, fore = mount.fore })
    end
    table.insert(out, moved)
  end
  return out
end
local function exhaustsOut(by: number): { Exhaust }
  local out: { Exhaust } = {}
  for _, one in exhausts do
    table.insert(out, { at = one.at * by, radius = one.radius * by })
  end
  return out
end

-- ---------------------------------------------------------------------
-- A generated hull made a ship: engines on the ends it has astern, and
-- hardpoints wherever the whole foot of a weapon has hull under it and
-- nothing over it: on the hull's own faces, or, where they will not
-- take every mount, on seats let into it (seatsOf). (The old engine did both by casting rays at the
-- finished hull, at random. Here the plates are asked, so the same seed
-- is always the same ship, and the rule of hardpoints is kept: a pair
-- of mounts on opposite sides, each wholly on the hull.)

type Box = { center: vector, size: vector, part: number }
-- Where an engine goes: the middle of a face that looks aft, half its
-- width and height, and whether there is one on the other side too.
type End = { at: vector, wide: number, high: number, both: boolean }
-- A seat: a low block let into the hull for a mount to stand on, where
-- no face of the hull is flat enough to take the whole foot of one.
type Seat = { center: vector, half: vector }
-- ('clear': where its mounts stand, as the hull is before its bend, and
-- 'reach' how far a foot reaches: its surface detail keeps off them.)
type Ship = { growth: Growth, ends: { End }, turrets: { Hardpoint }, launchers: { Hardpoint }, seats: { Seat }, clear: { vector },
  reach: number }

-- Every plate of a growth and its twin, as boxes.
local function boxesOf(g: Growth): { Box }
  local out: { Box } = {}
  for _, plate in g.plates do
    table.insert(out, { center = plate.center, size = plate.size, part = plate.part })
    if plate.center.x ~= 0 and not plate.single then
      table.insert(out, { center = plate.center * v(-1, 1, 1), size = plate.size * 0.99, part = plate.part })
    end
  end
  return out
end

-- The faces a hull has astern with nothing behind them, the biggest
-- 'most' of those in the aftmost third of it (or, if it has none there,
-- of them all). Each is for itself and its twin.
local function endsOf(boxes: { Box }, most: number): { End }
  local stern, bow = math.huge, -math.huge
  for _, box in boxes do
    stern = math.min(stern, box.center.z - box.size.z)
    bow = math.max(bow, box.center.z + box.size.z)
  end
  local function open(x: number, y: number, z: number, self: Box): boolean
    for _, box in boxes do
      if box ~= self and math.abs(x - box.center.x) < box.size.x and math.abs(y - box.center.y) < box.size.y
        and box.center.z - box.size.z < z - 0.01 then
        return false
      end
    end
    return true
  end
  local found: { End } = {}
  local aft: { End } = {}
  for _, box in boxes do
    if box.center.x >= 0 and box.size.x >= 0.18 and box.size.y >= 0.12 then
      local z = box.center.z - box.size.z
      local all = true
      for _, way in { { 0, 0 }, { 0.6, 0 }, { -0.6, 0 }, { 0, 0.6 }, { 0, -0.6 } } do
        if not open(box.center.x + way[1] * box.size.x, box.center.y + way[2] * box.size.y, z, box) then
          all = false
          break
        end
      end
      if all then
        -- (a plate that reaches over the centre line is one with its twin)
        local across = box.center.x < 0.6 * box.size.x
        local place: End = if across then { at = v(0, box.center.y, z), wide = box.center.x + box.size.x, high = box.size.y, both = false }
          else { at = v(box.center.x, box.center.y, z), wide = box.size.x, high = box.size.y, both = true }
        table.insert(found, place)
        if z <= stern + (bow - stern) / 3 then
          table.insert(aft, place)
        end
      end
    end
  end
  local picked: { End } = if #aft > 0 then aft else found
  table.sort(picked, function(a: End, c: End): boolean
    local areaA, areaC = a.wide * a.high, c.wide * c.high
    if areaA ~= areaC then
      return areaA > areaC
    elseif a.at.z ~= c.at.z then
      return a.at.z < c.at.z
    elseif a.at.x ~= c.at.x then
      return a.at.x < c.at.x
    end
    return a.at.y < c.at.y
  end)
  -- (not two in one place: a plate and the deck's plate under it can end together)
  local kept: { End } = {}
  for _, place in picked do
    local free = true
    for _, other in kept do
      if math.abs(place.at.x - other.at.x) < place.wide + other.wide and math.abs(place.at.y - other.at.y) < place.high + other.high
        and math.abs(place.at.z - other.at.z) < 0.8 then
        free = false
      end
    end
    if free and #kept < most then
      table.insert(kept, place)
    end
  end
  return kept
end

-- An engine let into each of those faces: a dark throat and the fire in it.
local function jets(b: Builder, ends: { End })
  for _, place in ends do
    local put: (b: Builder, part: number, center: vector, half: vector, bevel: number?) -> () = if place.both then twin else mid
    local fire = v(place.wide * 0.62, place.high * 0.52, 0.03)
    put(b, FRAME, place.at - v(0, 0, 0.10), v(place.wide * 0.80, place.high * 0.72, 0.24), 0.3)
    put(b, GLOW, place.at - v(0, 0, 0.36), fire, 0.5)
    local sides: { number } = if place.both then { 1, -1 } else { 1 }
    for _, side in sides do
      exhaust(bending((place.at - v(0, 0, 0.40)) * v(side, 1, 1) * GROWN), math.min(fire.x, fire.y) * 1.25 * GROWN)
    end
  end
end

-- How much of a plate's face a foot can stand on, from the middle of
-- the face toward one edge: a plate's edges are eased over the last
-- quarter of it, and a foot may reach out over the easing as far as the
-- face has fallen away under it by no more than 'gap'. 'half' is half
-- the plate that way and 'deep' half its thickness.
local function flatOf(half: number, deep: number, gap: number, eased: number): number
  local fall = eased * deep
  local over = if gap >= fall then 1 else math.sqrt(1 - (1 - gap / fall) ^ 2)
  return half * (1 - eased + eased * over)
end

-- The places on a hull's plates where a foot that reaches 'reach' has
-- a flat of plate under all of it and nothing of the hull standing over
-- it: on top of them ('up' is +y), under them (-y), or on their
-- starboard faces (+x). In the generator's units, as the hull is before
-- its bend.
local function standsOf(boxes: { Box }, up: vector, reach: number, gap: number, eased: number): { vector }
  -- (which of x and y the face looks along, and which it lies across)
  local out = if up.x ~= 0 then v(1, 0, 0) else v(0, 1, 0)
  local across = if up.x ~= 0 then v(0, 1, 0) else v(1, 0, 0)
  local way = up.x + up.y
  local found: { vector } = {}
  for _, box in boxes do
    local deep = vector.dot(box.size, out)
    local wide = flatOf(vector.dot(box.size, across), deep, gap, eased)
    local room = flatOf(box.size.z, deep, gap, eased) - reach
    -- (the starboard faces of the plates to starboard: their twins have the port ones)
    if box.part ~= FRAME and wide >= reach and room >= 0 and (up.x == 0 or box.center.x > 0) then
      -- (a plate's twin to port is a hundredth smaller: a place on a
      -- starboard face is put where the port face is, so that the twin
      -- of what stands there stands on its plate and not over it)
      local level = vector.dot(box.center, out) + way * deep * (if up.x ~= 0 then 0.99 else 1)
      local places = math.floor(2 * room / (2.4 * reach))
      for index = 0, places do
        local along = if places == 0 then 0 else -room + index * 2 * room / places
        local p = out * level + across * vector.dot(box.center, across) + v(0, 0, box.center.z + along)
        local clear = true
        for ring = 0, 8 do
          local a = vector.dot(p, across) + (if ring == 0 then 0 else reach * math.cos(ring * math.pi / 4))
          local z = p.z + (if ring == 0 then 0 else reach * math.sin(ring * math.pi / 4))
          for _, other in boxes do
            if other ~= box and math.abs(a - vector.dot(other.center, across)) < vector.dot(other.size, across)
              and math.abs(z - other.center.z) < other.size.z
              and way * (vector.dot(other.center, out) + way * vector.dot(other.size, out)) > way * level + 0.01 then
              clear = false
            end
          end
        end
        if clear then
          table.insert(found, p)
        end
      end
    end
  end
  -- (in one order whatever order the plates came in: from the bow aft)
  table.sort(found, function(a: vector, c: vector): boolean
    if a.z ~= c.z then
      return a.z > c.z
    elseif a.x ~= c.x then
      return a.x > c.x
    end
    return a.y > c.y
  end)
  return found
end

-- A seat's shape, in the reach of the foot it is for: half its width;
-- how far its top stands over the highest of the hull under it; how
-- far over the face it is let into its top may be at the most (no
-- towers), and how far under its top the hull may lie at any corner of
-- it (no stilts); how far into the lowest of the hull under it it
-- goes; and how far its own edges are eased.
local SEAT_WIDE, SEAT_LIFT, SEAT_RISE, SEAT_DROP, SEAT_SINK, SEAT_EASED = 1.1, 0.12, 0.8, 2.2, 0.3, 0.12
-- How far apart the places asked are, in the same, and how many of them
-- are kept for a face at the most.
local SEAT_STEP, SEAT_MOST = 1.2, 400

-- The places on a hull where a seat for a foot that reaches 'reach' can
-- be let in: on top of it, under it, or on its starboard side, as
-- standsOf has them. A hull grown of narrow strips has no one face wide
-- enough for a gun, but strips run side by side: a seat lies across
-- them. It has hull under the whole of it (under its middle, its
-- corners and the middles of its sides there is a plate's face, clear
-- of where the face is eased away, and near enough), its top is over
-- everything of the hull that is under it, and it is let into the
-- lowest of that. The places are asked on a grid over the whole of the
-- hull, the centre line among them. Each is where the mount stands (the
-- middle of the seat's top) and the seat. In the generator's units, as
-- the hull is before its bend.
local function seatsOf(boxes: { Box }, up: vector, reach: number, eased: number): { { at: vector, seat: Seat } }
  local out = if up.x ~= 0 then v(1, 0, 0) else v(0, 1, 0)
  local across = if up.x ~= 0 then v(0, 1, 0) else v(1, 0, 0)
  local way = up.x + up.y
  local half = SEAT_WIDE * reach
  -- (each plate as numbers: where it is across and along, half of it
  -- each way, how far out its face is the way the seat looks, and
  -- whether a seat may rest on it)
  type Flat = { a: number, z: number, ha: number, hz: number, top: number, rests: boolean }
  local flats: { Flat } = {}
  local least, most, aft, fore = math.huge, -math.huge, math.huge, -math.huge
  for _, box in boxes do
    local flat: Flat = { a = vector.dot(box.center, across), z = box.center.z, ha = vector.dot(box.size, across), hz = box.size.z,
      top = way * vector.dot(box.center, out) + vector.dot(box.size, out), rests = box.part ~= FRAME }
    table.insert(flats, flat)
    least, most = math.min(least, flat.a - flat.ha), math.max(most, flat.a + flat.ha)
    aft, fore = math.min(aft, flat.z - flat.hz), math.max(fore, flat.z + flat.hz)
  end
  local keep = 1 - 0.5 * eased
  -- The hull at a place: how far out the face of it is that a seat
  -- could rest on there (nil: none), and how far out anything of it is.
  local function under(a: number, z: number): (number?, number)
    local face: number? = nil
    local over = -math.huge
    for _, flat in flats do
      local da, dz = math.abs(a - flat.a), math.abs(z - flat.z)
      if da < flat.ha and dz < flat.hz then
        over = math.max(over, flat.top)
        if flat.rests and da < flat.ha * keep and dz < flat.hz * keep and (face == nil or flat.top > face) then
          face = flat.top
        end
      end
    end
    return face, over
  end
  local CORNERS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
  local step = SEAT_STEP * reach
  local found: { { at: vector, seat: Seat } } = {}
  -- (the starboard side's places are mirrored for the port side's: on
  -- top and beneath, the grid has the centre line and both sides of it)
  local first = math.ceil(least / step)
  for column = first, math.floor(most / step) do
    local a = column * step
    for row = math.ceil(aft / step), math.floor(fore / step) do
      local z = row * step
      local level, over = under(a, z)
      if level then
        local top, low = over, level
        local good = true
        for _, corner in CORNERS do
          local face, above = under(a + corner[1] * half, z + corner[2] * half)
          if face == nil then
            good = false
            break
          end
          top, low = math.max(top, above), math.min(low, face)
        end
        top += SEAT_LIFT * reach
        if good and top - level <= SEAT_RISE * reach and top - low <= SEAT_DROP * reach then
          local bottom = low - SEAT_SINK * reach
          table.insert(found, {
            at = out * (way * top) + across * a + v(0, 0, z),
            seat = { center = out * (way * (top + bottom) / 2) + across * a + v(0, 0, z),
              half = out * ((top - bottom) / 2) + across * half + v(0, 0, half) },
          })
        end
      end
    end
  end
  -- (no more of them than can be gone through: evenly, of those there are)
  if #found > SEAT_MOST then
    local kept: { { at: vector, seat: Seat } } = {}
    for index = 1, SEAT_MOST do
      table.insert(kept, found[1 + math.floor((index - 1) * #found / SEAT_MOST)])
    end
    found = kept
  end
  table.sort(found, function(one, other): boolean
    local p, q = one.at, other.at
    if p.z ~= q.z then
      return p.z > q.z
    elseif p.x ~= q.x then
      return p.x > q.x
    end
    return p.y > q.y
  end)
  return found
end

-- The seats a ship's mounts stand on, let into its hull.
local function seated(b: Builder, seats: { Seat })
  for _, seat in seats do
    mid(b, PLATING, seat.center, seat.half, SEAT_EASED)
  end
end

-- What a growth is as a ship 'metres' in radius that carries what 'fit'
-- names on so many turret and launcher hardpoints, with so many engines
-- (each with its twin, where it is not on the centre line); or nothing,
-- and why, if it has not the room for the hardpoints. A hardpoint is a
-- place on top with one beneath it (on the other side of the centre
-- line, if there is one there), or a place on the starboard side with
-- its twin to port; each is taken as far as can be from those taken
-- before it, the first being the one nearest the bow.
local function shipOf(g: Growth, metres: number, fit: { string }, turrets: number, launchers: number, engines: number): (Ship?, string)
  local boxes = boxesOf(g)
  local bend = warped(g.warps, g.middle)
  local ship: Ship = { growth = g, ends = endsOf(boxes, engines), turrets = {}, launchers = {}, seats = {}, clear = {}, reach = 0 }
  local wanted = turrets + launchers
  if wanted == 0 then
    return ship, ""
  end
  -- (as it will be asked when it is built, of the plates themselves)
  local scratch = Plates.New(0, MANNER_FINE)
  grown(scratch, g)
  local radius = math.max(g.across.x, g.across.y, g.across.z) / 2
  local size, least = 1, math.huge
  for _, type in fit do
    size = math.max(size, Arms.SizeOf(type))
    least = math.min(least, Arms.SizeOf(type))
  end
  -- (a tenth over: the engines make the hull a little longer than its plates)
  local unit = 1.1 * Arms.SIZE[size] * radius / metres
  -- (Every mount is for the biggest thing the hull carries, and so has
  -- the room for any of it; but how far under a foot the hull may lie is
  -- by the smallest, which stands closest: a hull that carries two sizes
  -- of gun has each of its mounts good for either.)
  -- (And not a tenth over, for that: a foot may reach less far than is
  -- allowed for, but it may not stand higher.)
  local reach, gap = Arms.REACH * unit, Arms.GAP * unit / 1.1 * Arms.SIZE[math.min(size, least)] / Arms.SIZE[size]
  type Stand = { at: vector, mount: Mount, seat: Seat? }
  local function stands(up: vector, mirrored: boolean?): { Stand }
    local out: { Stand } = {}
    for _, p in standsOf(boxes, up, reach / GROWN, gap / GROWN, g.style.eased) do
      local at = if mirrored then p * v(-1, 1, 1) else p
      local mount = bentBy(bend, at, if mirrored then -up else up)
      if Plates.Rests(scratch, mount.at, mount.up, v(0, 0, 1), reach, gap) then
        table.insert(out, { at = at, mount = mount })
      end
    end
    return out
  end
  -- (the same on seats let into the hull: each is asked with its seat there)
  local function seats(up: vector, mirrored: boolean?): { Stand }
    local out: { Stand } = {}
    for _, place in seatsOf(boxes, up, reach / GROWN, g.style.eased) do
      local flip = if mirrored then v(-1, 1, 1) else v(1, 1, 1)
      local seat: Seat = { center = place.seat.center * flip, half = place.seat.half }
      local at = place.at * flip
      local mount = bentBy(bend, at, if mirrored then -up else up)
      table.insert(scratch.solids, { center = seat.center * GROWN, half = seat.half * GROWN, turn = v(0, 0, 0) })
      local rests = Plates.Rests(scratch, mount.at, mount.up, v(0, 0, 1), reach, gap)
      table.remove(scratch.solids)
      if rests then
        table.insert(out, { at = at, mount = mount, seat = seat })
      end
    end
    return out
  end
  local apart = 2.4 * reach / GROWN
  -- The hardpoints, from the places there are: all that are wanted, or
  -- none and why not.
  local function choose(tops: { Stand }, bottoms: { Stand }, starboard: { Stand }, port: { Stand }): ({ Hardpoint }?, { Stand }, string)
    local taken: { Stand } = {}     -- every mount taken
    local firsts: { Stand } = {}    -- and the first of each hardpoint
    -- (two mounts that look the same way are kept apart)
    local function free(stand: Stand): boolean
      for _, other in taken do
        if vector.dot(stand.mount.up, other.mount.up) > 0.5 and vector.magnitude(stand.at - other.at) < apart then
          return false
        end
      end
      return true
    end
    local function away(stand: Stand): number
      local least = math.huge
      for _, first in firsts do
        least = math.min(least, vector.magnitude(stand.at - first.at))
      end
      return least
    end
    local points: { Hardpoint } = {}
    for _ = 1, wanted do
      local best: Stand? = nil
      local other: Stand? = nil
      local bestAway = -1
      for _, top in tops do
        local far = away(top)
        if far > bestAway and free(top) then
          -- (beneath, and on the other side of the centre line if it can be)
          local wish = v(-top.at.x, top.at.y, top.at.z)
          local match: Stand? = nil
          local near = math.huge
          for _, bottom in bottoms do
            local off = vector.magnitude((bottom.at - wish) * v(1, 0, 1))
            if off < near and vector.dot(top.mount.up, bottom.mount.up) < -0.6 and free(bottom) then
              match, near = bottom, off
            end
          end
          if match then
            best, other, bestAway = top, match, far
          end
        end
      end
      for _, side in starboard do
        -- (a place on top is taken before one on the side that is as far off)
        local far = 0.999 * away(side)
        if far > bestAway and free(side) then
          for _, twinned in port do
            if twinned.at == side.at * v(-1, 1, 1) and free(twinned) and vector.dot(side.mount.up, twinned.mount.up) < -0.6 then
              best, other, bestAway = side, twinned, far
            end
          end
        end
      end
      if best == nil or other == nil then
        return nil, taken, `room for {#points} of {wanted} hardpoints ({#tops} places on top, {#bottoms} beneath, {#starboard} a side)`
      end
      table.insert(taken, best)
      table.insert(taken, other)
      table.insert(firsts, best)
      table.insert(points, { best.mount, other.mount })
    end
    return points, taken, ""
  end
  -- On the hull's own faces if they will take every mount whole. If
  -- they will not, on seats let into it; and if seats alone will not
  -- do either, on both.
  local tops, bottoms = stands(UP), stands(DOWN)
  local starboard, port = stands(STARBOARD), stands(STARBOARD, true)
  local points, taken, why = choose(tops, bottoms, starboard, port)
  if points == nil then
    local seatTops, seatBottoms = seats(UP), seats(DOWN)
    local seatStarboard, seatPort = seats(STARBOARD), seats(STARBOARD, true)
    local plain = why
    points, taken, why = choose(seatTops, seatBottoms, seatStarboard, seatPort)
    if points == nil then
      local function both(one: { Stand }, other: { Stand }): { Stand }
        local all = table.clone(one)
        table.move(other, 1, #other, #all + 1, all)
        return all
      end
      points, taken, why = choose(both(tops, seatTops), both(bottoms, seatBottoms), both(starboard, seatStarboard), both(port, seatPort))
    end
    if points == nil then
      return nil, `{plain}; and on seats, {why}`
    end
  end
  for _, stand in taken do
    if stand.seat then
      table.insert(ship.seats, stand.seat)
    end
    table.insert(ship.clear, stand.at)
  end
  ship.reach = reach / GROWN
  for index, point in points :: { Hardpoint } do
    local list: { Hardpoint } = if index <= turrets then ship.turrets else ship.launchers
    table.insert(list, point)
  end
  return ship, ""
end

-- ---------------------------------------------------------------------
-- Surface detail on a grown hull (B1 on the roadmap; the project
-- owner's answers of 2026-11-17): what is laid over the hull's own
-- plates and changes nothing of its shape or its hardpoints, each kind
-- switched on hull by hull (resource/hull/seeds.txt; the hull browser,
-- App/hulls). Antennas, which always stand straight out of the face
-- they are on ("90 degrees from the face"); pipes and conduits along
-- the faces; greebles (boxes, vents and fins); lights (running lights
-- red to port and green to starboard, white at the bow, stern and
-- masthead, and rows of lit windows on the bigger hulls); and rivets
-- and finer panel lines over the sheets of plating, which are the
-- shader's (material/hull.jsl). The rest are plates like any other, and
-- are bent with the hull. By dice of the hull's own seed: a hull is
-- always detailed the same way. Every figure and size here is mine.

export type Detail = { antennas: boolean?, pipes: boolean?, greebles: boolean?, lights: boolean?, rivets: boolean? }
-- The kinds, in the order the hull browser's number keys switch them.
Hull.DETAILS = { "antennas", "pipes", "greebles", "lights", "rivets" }

local LAMP_RED, LAMP_GREEN, LAMP_WHITE = Plates.LAMP_RED, Plates.LAMP_GREEN, Plates.LAMP_WHITE
local BOW, STERN = v(0, 0, 1), v(0, 0, -1)

-- The half-size of a box that stands 'along' out of a face whose normal
-- is 'n' (one of the six ways) and is 'one' and 'other' across it (in
-- the face's first and second ways, as faceWays has them).
local function faceWays(n: vector): (vector, vector)
  if n.x ~= 0 then
    return v(0, 0, 1), v(0, 1, 0)
  elseif n.y ~= 0 then
    return v(0, 0, 1), v(1, 0, 0)
  end
  return v(1, 0, 0), v(0, 1, 0)
end

local function standing(n: vector, along: number, one: number, other: number): vector
  local a, b2 = faceWays(n)
  local out = v(math.abs(n.x), math.abs(n.y), math.abs(n.z))
  return out * along + a * one + b2 * other
end

-- A face of a plate: where its middle is, its normal, how far it reaches
-- each of its two ways, and whether it is drawn with its twin.
type Face = { at: vector, n: vector, h1: number, h2: number, twin: boolean }

local function detailed(b: Builder, ship: Ship, detail: Detail, metres: number)
  local g = ship.growth
  local boxes = boxesOf(g)
  for _, seat in ship.seats do
    table.insert(boxes, { center = seat.center, size = seat.half, part = PLATING })
  end
  local rng = RNG_MTG(Int.Signed(g.seed + 9301))
  -- How big the hull is, in the generator's units, and what a detail's
  -- sizes are taken from: a bigger ship's are a little finer, and more.
  local R = math.max(g.across.x, g.across.y, g.across.z) / 2 / GROWN
  local u = R * math.clamp((150 / math.max(metres, 1)) ^ 0.2, 0.6, 1.25)
  local more = math.clamp((metres / 150) ^ 0.5, 0.7, 2.5)
  local EPS = 0.004 * R

  -- (whether a point is in the hull: in a plate, a hair in from its faces)
  local function inside(p: vector): boolean
    for _, box in boxes do
      local d = p - box.center
      if math.abs(d.x) < box.size.x - 1e-4 and math.abs(d.y) < box.size.y - 1e-4 and math.abs(d.z) < box.size.z - 1e-4 then
        return true
      end
    end
    return false
  end
  -- (and whether it is clear of the mounts and the engines)
  local function clearOf(p: vector, room: number): boolean
    local keep = ship.reach * 1.6 + room
    for _, at in ship.clear do
      if vector.magnitude(p - at) < keep then
        return false
      end
    end
    for _, place in ship.ends do
      local xs: { number } = if place.both then { place.at.x, -place.at.x } else { place.at.x }
      for _, x in xs do
        if math.abs(p.x - x) < place.wide * 1.4 + room and math.abs(p.y - place.at.y) < place.high * 1.4 + room
          and p.z < place.at.z + 0.6 + room then
          return false
        end
      end
    end
    return true
  end
  -- Whether something standing 'tall' out of a face at 'p', 'w1' by
  -- 'w2' across it, has the face under all of it and nothing of the
  -- hull in its way.
  local function fits(p: vector, n: vector, w1: number, w2: number, tall: number): boolean
    local a, c = faceWays(n)
    for _, corner in { { 0, 0 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
      local q = p + a * (corner[1] * w1) + c * (corner[2] * w2)
      if not inside(q - n * EPS) then
        return false
      end
      for _, up in { 1, 0.5, 0.25, 0.08 } do
        if inside(q + n * math.max(EPS, tall * up)) then
          return false
        end
      end
    end
    return clearOf(p, math.max(w1, w2))
  end

  -- The faces there are to put things on: of every plate that is not
  -- slight structure or lit, each of its faces that looks out of the
  -- hull (for a plate drawn with its twin, the twin's are its own,
  -- mirrored).
  local faces: { Face } = {}
  for _, plate in g.plates do
    if plate.part ~= FRAME and plate.part ~= GLOW then
      local side = if plate.single and plate.center.x < 0 then -1 else 1
      for _, n in { UP, DOWN, STARBOARD * side, BOW, STERN } do
        local a, c = faceWays(n)
        local out = v(math.abs(n.x), math.abs(n.y), math.abs(n.z))
        local at = plate.center + n * vector.dot(plate.size, out)
        local h1, h2 = vector.dot(plate.size, a), vector.dot(plate.size, c)
        if h1 > 2 * EPS and h2 > 2 * EPS and not inside(at + n * EPS) then
          table.insert(faces, { at = at, n = n, h1 = h1, h2 = h2, twin = not plate.single })
        end
      end
    end
  end
  if #faces == 0 then
    return
  end
  -- (a place on a face, by the dice: within the middle of it, clear of its eased edges)
  local function spot(face: Face): vector
    local a, c = faceWays(face.n)
    return face.at + a * (face.h1 * rng:Float(-0.72, 0.72)) + c * (face.h2 * rng:Float(-0.72, 0.72))
  end
  -- (a face by the dice, the bigger likelier; one looking one of 'ways', if they are named)
  local function pick(ways: { vector }?): Face?
    local total = 0
    local good: { Face } = {}
    for _, face in faces do
      local ok = ways == nil
      if ways then
        for _, way in ways do
          if face.n == way or (way == STARBOARD and face.n == PORT) then
            ok = true
          end
        end
      end
      if ok then
        table.insert(good, face)
        total += face.h1 * face.h2
      end
    end
    if #good == 0 then
      return nil
    end
    local roll = rng:Float(0, total)
    for _, face in good do
      roll -= face.h1 * face.h2
      if roll <= 0 then
        return face
      end
    end
    return good[#good]
  end
  -- Put a box in: with its twin on the other side, where its face has one.
  local function put(face: Face, part: number, center: vector, half: vector, bevel: number?)
    if face.twin and center.x > 1e-3 then
      twin(b, part, center, half, bevel)
    else
      mid(b, part, center, half, bevel)
    end
  end

  -- Antennas: a mast straight out of its face, on a foot, and now and
  -- then a crossbar, a pod or a second mast beside it; a lamp on top.
  if detail.antennas then
    local count = math.floor(rng:Int(2, 6) * more + 0.5)
    for _ = 1, count do
      local face = pick({ UP, UP, STARBOARD, DOWN, BOW })
      if face then
        for _ = 1, 8 do
          local p = spot(face)
          local n = face.n
          local tall = u * rng:Float(0.07, 0.2) * (if n == UP then 1.2 else 0.8)
          local thin = math.max(u * 0.0045, tall * 0.025)
          if fits(p, n, thin * 3, thin * 3, tall) then
            put(face, PATCH, p + n * (thin * 0.6), standing(n, thin * 0.6, thin * 3, thin * 3), 0.3)
            put(face, FRAME, p + n * (tall / 2), standing(n, tall / 2, thin, thin), 0.2)
            local kind = rng:Int(4)
            local a, c = faceWays(n)
            if kind == 1 then
              put(face, FRAME, p + n * (tall * 0.78), standing(n, thin * 0.8, tall * 0.18, thin * 0.8), 0.2)
            elseif kind == 2 then
              put(face, PATCH, p + n * (tall * 0.82), standing(n, tall * 0.07, thin * 3.2, thin * 2.2), 0.3)
            elseif kind == 3 then
              local beside = p + c * (tall * 0.09)
              if fits(beside, n, thin * 2, thin * 2, tall * 0.7) then
                put(face, FRAME, beside + n * (tall * 0.35), standing(n, tall * 0.35, thin, thin), 0.2)
              end
            end
            if detail.lights then
              put(face, if n == UP and rng:Int(2) == 0 then LAMP_RED else LAMP_WHITE, p + n * (tall + thin), v(thin, thin, thin) * 1.5, 0.5)
            end
            local _ = a
            break
          end
        end
      end
    end
  end

  -- Pipes and conduits: runs of one to three pipes along a face, the
  -- long way of it, with clamps over them; never over a gap.
  if detail.pipes then
    local count = math.floor(rng:Int(4, 9) * more + 0.5)
    for _ = 1, count do
      local face = pick({ UP, STARBOARD, STARBOARD, DOWN })
      if face then
        local a, c = faceWays(face.n)
        local long, across, hl, ha = a, c, face.h1, face.h2
        if face.h2 > face.h1 then
          long, across, hl, ha = c, a, face.h2, face.h1
        end
        local r = u * rng:Float(0.006, 0.011)
        local length = hl * rng:Float(0.45, 0.9)
        local start = rng:Float(-hl * 0.85 + length, hl * 0.85) - length
        local offset = ha * rng:Float(-0.6, 0.6)
        local runs = rng:Int(1, 3)
        local good = true
        local function at(t: number, k: number): vector
          return face.at + long * (start + t) + across * (offset + k * r * 2.7)
        end
        for k = 0, runs - 1 do
          for step = 0, 8 do
            local q = at(length * step / 8, k)
            if not inside(q - face.n * EPS) or inside(q + face.n * (r * 2.2)) or not clearOf(q, r) then
              good = false
            end
          end
        end
        if good and length > r * 8 then
          for k = 0, runs - 1 do
            local middle = at(length / 2, k)
            local half = long * (length / 2) + across * r + face.n * r
            put(face, FRAME, middle + face.n * (r * 1.05), half, 0.9)
          end
          -- (the clamps: across all the run, every so far along it)
          local clamps = math.max(2, math.floor(length / (r * 14)))
          for index = 0, clamps do
            local t = length * (0.04 + 0.92 * index / clamps)
            local middle = (at(t, 0) + at(t, runs - 1)) / 2
            local half = long * (r * 0.55) + across * (r * (runs - 1) * 1.35 + r * 1.5) + face.n * (r * 1.4)
            put(face, PATCH, middle + face.n * (r * 1.3), half, 0.3)
          end
        end
      end
    end
  end

  -- Greebles: clusters of small boxes on a face, now and then a vent
  -- (slats over a frame) or a bank of fins.
  if detail.greebles then
    local count = math.floor(rng:Int(12, 22) * more + 0.5)
    for _ = 1, count do
      local face = pick(nil)
      if face then
        local middle = spot(face)
        local a, c = faceWays(face.n)
        local spread = u * rng:Float(0.03, 0.08)
        local kind = rng:Int(5)
        if kind == 0 then
          -- (a vent)
          local w1, w2, high = u * rng:Float(0.018, 0.035), u * rng:Float(0.012, 0.025), u * 0.004
          if fits(middle, face.n, w1, w2, high * 3) then
            put(face, FRAME, middle + face.n * high, standing(face.n, high, w1, w2), 0.2)
            local slats = rng:Int(3, 6)
            for index = 1, slats do
              local along = -w1 + 2 * w1 * (index - 0.5) / slats
              put(face, PATCH, middle + a * along + face.n * (high * 2.2), standing(face.n, high * 0.8, w1 / slats * 0.35, w2 * 0.9), 0.2)
            end
          end
        elseif kind == 1 then
          -- (a bank of fins)
          local w1, w2, high = u * rng:Float(0.02, 0.04), u * rng:Float(0.012, 0.022), u * rng:Float(0.008, 0.016)
          if fits(middle, face.n, w1, w2, high * 2) then
            local fins = rng:Int(4, 8)
            for index = 1, fins do
              local along = -w1 + 2 * w1 * (index - 0.5) / fins
              put(face, FRAME, middle + a * along + face.n * high, standing(face.n, high, w1 / fins * 0.28, w2), 0.15)
            end
          end
        else
          -- (boxes, overlapping, of a few sizes)
          for _ = 1, rng:Int(4, 9) do
            local p = middle + a * (spread * rng:Float(-1, 1)) + c * (spread * rng:Float(-1, 1))
            local w1, w2, high = u * rng:Float(0.012, 0.045), u * rng:Float(0.012, 0.045), u * rng:Float(0.005, 0.02)
            if fits(p, face.n, w1, w2, high * 2) then
              local part = ({ PATCH, PLATING, FRAME, PATCH })[rng:Int(4) + 1]
              put(face, part, p + face.n * high, standing(face.n, high, w1, w2), 0.25)
            end
          end
        end
      end
    end
  end

  -- Lights: running lights at the ends of it, red to port and green to
  -- starboard, white at the bow and stern and on its top; and on a hull
  -- of a cruiser's size or more, rows of lit windows along its sides.
  if detail.lights then
    local lamp = u * 0.007
    local function farthest(n: vector): Face?
      local best: Face? = nil
      local bestReach = -math.huge
      for _, face in faces do
        local reach = vector.dot(face.at, n)
        if face.n == n and reach > bestReach and clearOf(face.at, lamp) then
          best, bestReach = face, reach
        end
      end
      return best
    end
    local starboard = farthest(STARBOARD)
    if starboard then
      mid(b, LAMP_GREEN, starboard.at + STARBOARD * lamp, v(lamp, lamp, lamp), 0.5)
      if starboard.twin then
        mid(b, LAMP_RED, (starboard.at + STARBOARD * lamp) * v(-1, 1, 1), v(lamp, lamp, lamp), 0.5)
      end
    end
    local port = farthest(PORT)
    if port then
      mid(b, LAMP_RED, port.at + PORT * lamp, v(lamp, lamp, lamp), 0.5)
    end
    for _, n in { BOW, STERN, UP } do
      local face = farthest(n)
      if face then
        mid(b, LAMP_WHITE, face.at + n * lamp, v(lamp, lamp, lamp), 0.5)
      end
    end
    if metres >= 150 then
      local window = u * 0.0055
      local left = math.floor(60 * math.min(more, 1.5))
      for _ = 1, 6 do
        local face = pick({ STARBOARD })
        if face and left > 0 then
          local a, c = faceWays(face.n)
          local hl = face.h1
          local level = face.h2 * rng:Float(-0.4, 0.4)
          local from, to = -hl * 0.8, hl * 0.8
          local stepBy = window * rng:Float(3, 5)
          local z = from
          while z <= to and left > 0 do
            local p = face.at + a * z + c * level
            if fits(p, face.n, window, window * 0.7, window) then
              put(face, GLOW, p + face.n * (window * 0.15), standing(face.n, window * 0.2, window, window * 0.6), 0.3)
              left -= 1
            end
            z += stepBy
          end
        end
      end
    end
  end

  b.rivets = detail.rivets == true
end

-- Plates laid out by something else that is grown (a citadel: Game/View/
-- Citadel), in the generator's units and unbent: drawn, and detailed as
-- a hull is ('metres': how big it will be, for the sizes of things).
-- Each plate is drawn alone unless it has a twin ('single' false).
function Hull.DrawPlates(b: Builder, plates: { Plate }, eased: number?)
  for _, plate in plates do
    if plate.single == false then
      twin(b, plate.part, plate.center, plate.size, eased)
    else
      mid(b, plate.part, plate.center, plate.size, eased)
    end
  end
end

function Hull.DetailPlates(b: Builder, plates: { Plate }, seed: number, detail: Detail, metres: number, keepOff: { vector }?,
  keepReach: number?)
  local low, high = v(math.huge, math.huge, math.huge), v(-math.huge, -math.huge, -math.huge)
  local single: { Plate } = {}
  for _, plate in plates do
    low, high = vector.min(low, plate.center - plate.size), vector.max(high, plate.center + plate.size)
    table.insert(single, { center = plate.center, size = plate.size, part = plate.part, single = plate.single ~= false })
  end
  local g: Growth = { plates = single, middle = (low + high) / 2 * GROWN, across = (high - low) * GROWN, style = styleOf(nil),
    warps = styleOf(nil).warps, seed = seed }
  -- (what it keeps off, as a hull's detail keeps off its mounts)
  detailed(b, { growth = g, ends = {}, turrets = {}, launchers = {}, seats = {}, clear = keepOff or {}, reach = (keepReach or 0) / 1.6 },
    detail, metres)
end

-- The generator's units: a plate of size 1 is so many of a model's.
Hull.GROWN = GROWN

-- A detail from the words of a seed line or a sheet (Hull.DETAILS);
-- nil if none is among them.
function Hull.DetailOf(words: { string }): Detail?
  local detail: Detail = {}
  local any = false
  for _, word in words do
    if table.find(Hull.DETAILS, word) then
      (detail :: any)[word] = true
      any = true
    end
  end
  return if any then detail else nil
end

-- How the Vail's battleship is read: its bridge stands on its back
-- without putting the hull about it in shade.
local BATTLESHIP_FILE: Imported.Options = { apart = { "bridge" } }

type Design = {
  faction: string,
  draw: (b: Builder) -> (),
  -- (A pirate hull is somebody else's design, patched: Plates' 'patch'.)
  patch: number?,
  -- (And that it is such a copy, with guns bolted on beside the ones it
  -- was built for: the rule of hardpoints is not kept on it. What the
  -- pirates built themselves is patched too, and is held to the rule.)
  copied: boolean?,
  -- (A bigger ship is plated in more and smaller sheets for its size:
  -- it is one of the things that says how big it is.)
  sheets: number?,
  -- Its own paint, where its faction's hulls are not all painted alike
  -- (the Orun's). Its faction's, if not said.
  look: Look?,
  -- How alike its plates are in tone (Plates' 'even'): as unlike as
  -- plates come, if not said.
  even: number?,
  -- How small a plate of it still has its edges eased finely (Plates'
  -- 'fine'): 0.11, if not said.
  fine: number?,
  -- How finely its plates are meshed (Plates.New's 'quality'): as the
  -- game's hulls are, if not said.
  quality: number?,
  -- Half the length it is drawn, where its mounts were worked out from
  -- that (the Kethri's: footOn). Hull.Build checks it is so.
  reach: number?,
  turrets: { Hardpoint },
  launchers: { Hardpoint },
  -- Its hardpoints, where they are not known until it is built (a hull
  -- read from a file has its mounts put on its surface: Imported.Mounts):
  -- its turrets and its launchers, asked for once, the first time.
  place: (() -> ({ Hardpoint }, { Hardpoint }))?,
  -- What it is shown carrying where nobody has fitted it (a gallery):
  -- turrets, then launchers, in the order of its hardpoints.
  fit: { string },
}

local designs: { [string]: Design } = {
  -- (The five hulls of the Vail's that were modelled from the owner's
  -- drawings. Their ships are the owner's list of generator seeds since
  -- 2026-11-15, and none of these is a hull of the game now: the
  -- drawings of them are kept, as the Talmar's are further down.)
  -- The Vail's frigate, modelled from the owner's first drawing
  -- (script/modelgen): a gun on the back and one beneath where the hull
  -- is highest and flattest, and a pair abreast on the broad of it aft.
  -- (Farther forward its back falls away too fast for a gun's foot.)
  ["frigate.thorn"] = {
    faction = "vail", draw = vessel("vail/frigate.obj"), turrets = {}, launchers = {},
    place = function(): ({ Hardpoint }, { Hardpoint })
      local model = Imported.Load("vail/frigate.obj")
      return { Imported.Mounts(model, 0, 0.04), Imported.Mounts(model, 0.14, -0.24), Imported.Mounts(model, -0.14, -0.24) }, {}
    end,
    fit = { "laser.pulse.small", "laser.pulse.small", "laser.pulse.small" },
  },
  -- Their destroyer, from the third drawing: its guns in a line down its
  -- back and its keel, the last two abreast between its shoulders.
  ["destroyer.barb"] = {
    faction = "vail", draw = vessel("vail/destroyer.obj"), sheets = 4.0, turrets = {}, launchers = {},
    place = function(): ({ Hardpoint }, { Hardpoint })
      local model = Imported.Load("vail/destroyer.obj")
      return { Imported.Mounts(model, 0, 0.26), Imported.Mounts(model, 0, 0.10), Imported.Mounts(model, 0, -0.06),
        Imported.Mounts(model, 0, -0.22), Imported.Mounts(model, 0.06, -0.36), Imported.Mounts(model, -0.06, -0.36) }, {}
    end,
    fit = { "laser.pulse.small", "laser.pulse.small", "laser.pulse.small", "laser.pulse.small", "laser.pulse.small", "laser.pulse.small" },
  },
  -- Their cruiser, from the second: a gun on each face of its roof and
  -- of its keel, forward and aft, inboard of the armour on its shoulders.
  ["cruiser.pike"] = {
    faction = "vail", draw = vessel("vail/cruiser.obj"), sheets = 6.5, turrets = {}, launchers = {},
    place = function(): ({ Hardpoint }, { Hardpoint })
      local model = Imported.Load("vail/cruiser.obj")
      return { Imported.Mounts(model, 0.04, 0.22), Imported.Mounts(model, -0.04, 0.22), Imported.Mounts(model, 0.04, -0.10),
        Imported.Mounts(model, -0.04, -0.10) }, {}
    end,
    fit = { "laser.pulse.medium", "laser.pulse.medium", "laser.pulse.medium", "laser.pulse.medium" },
  },
  -- Their battleship. Its shape is the owner's (the hull and engine
  -- housings of a model worked up in another program and in Blender: a
  -- flattened arrowhead); the Vail's bands, lights, nozzles and its
  -- bridge are put on it by script/modelgen. A gun forward on its back
  -- and three pairs abreast down its length, clear of the bridge; each
  -- with its twin beneath.
  ["battleship.harpoon"] = {
    faction = "vail", draw = vessel("vail/battleship.obj", BATTLESHIP_FILE), sheets = 13, turrets = {}, launchers = {},
    place = function(): ({ Hardpoint }, { Hardpoint })
      local model = Imported.Load("vail/battleship.obj", BATTLESHIP_FILE)
      return { Imported.Mounts(model, 0, 0.42), Imported.Mounts(model, 0.11, -0.10), Imported.Mounts(model, -0.11, -0.10),
        Imported.Mounts(model, 0.11, -0.30), Imported.Mounts(model, -0.11, -0.30), Imported.Mounts(model, 0.11, -0.48),
        Imported.Mounts(model, -0.11, -0.48) }, {}
    end,
    fit = { "laser.beam.large", "laser.beam.large", "laser.beam.large", "laser.beam.large", "laser.beam.large", "laser.beam.large",
      "laser.beam.large" },
  },
  -- Their hauler, from the fifth: one gun, on its back before the bay.
  ["industrial.drover"] = {
    faction = "vail", draw = vessel("vail/hauler.obj"), sheets = 4.0, turrets = {}, launchers = {},
    place = function(): ({ Hardpoint }, { Hardpoint })
      return { Imported.Mounts(Imported.Load("vail/hauler.obj"), 0, 0.42) }, {}
    end,
    fit = { "laser.pulse.small" },
  },
  ["frigate.javelin"] = {
    faction = "vessari", draw = javelin,
    -- (its gun on and under the bow; a rack on each flank; a rack on the
    -- back and one hung under the port bow)
    turrets = { over(v(-0.05, 0.13, 0.96), v(0.06, -0.21, 0.94)) },
    launchers = {
      abeam(v(0.322, 0.09, 0.02), v(-0.317, 0.06, 0.30)),
      over(v(-0.10, 0.287, 0.16), v(-0.20, -0.137, 0.80)),
    },
    fit = { "autocannon.small", "launcher.light", "launcher.light" },
  },
  ["destroyer.halberd"] = {
    faction = "vessari", draw = halberd, sheets = 4.0,
    -- (its guns on the works and under them; its racks on the two faces
    -- of the blade, four to a face)
    turrets = { over(v(-0.06, 0.32, 0.30), v(-0.03, -0.24, 0.05)), over(v(0.12, 0.28, -0.72), v(-0.10, -0.16, -0.78)) },
    launchers = {
      abeam(v(0.060, -0.31, 1.14), v(-0.060, -0.31, 1.14)), abeam(v(0.060, -0.31, 0.86), v(-0.060, -0.31, 0.86)),
      abeam(v(0.060, -0.57, 1.14), v(-0.060, -0.57, 1.14)), abeam(v(0.060, -0.57, 0.86), v(-0.060, -0.57, 0.86)),
    },
    fit = { "autocannon.small", "autocannon.small", "launcher.light", "launcher.light", "launcher.light", "launcher.light" },
  },
  ["cruiser.cuirass"] = {
    faction = "vessari", draw = cuirass, sheets = 6.5,
    -- (the broadside: every hardpoint in a line along the gun deck, a
    -- weapon standing on it and its twin hanging under it, all facing out)
    turrets = { over(v(0.47, 0.066, 0.97), v(0.47, 0.014, 0.97), STARBOARD) },
    launchers = {
      over(v(0.47, 0.066, 0.47), v(0.47, 0.014, 0.47), STARBOARD), over(v(0.47, 0.066, -0.03), v(0.47, 0.014, -0.03), STARBOARD),
      over(v(0.47, 0.066, -0.53), v(0.47, 0.014, -0.53), STARBOARD),
    },
    fit = { "artillery.medium", "launcher.heavy", "launcher.heavy", "launcher.heavy" },
  },
  ["battleship.bastion"] = {
    faction = "vessari", draw = bastion, sheets = 13,
    -- (its guns on the gatehouse towers, each with a twin under the
    -- hull below it; its launchers along the outsides of both walls)
    turrets = { over(v(-0.46, 0.76, 2.36), v(-0.36, -0.55, 2.30)), over(v(0.48, 0.56, 1.96), v(0.37, -0.55, 1.90)) },
    launchers = {
      abeam(v(0.565, -0.24, 1.60), v(-0.545, -0.24, 1.60)), abeam(v(0.565, -0.24, 0.70), v(-0.545, -0.24, 0.70)),
      abeam(v(0.565, -0.24, -0.20), v(-0.545, -0.24, -0.20)), abeam(v(0.565, -0.24, -1.30), v(-0.545, -0.24, -1.30)),
      abeam(v(0.565, -0.24, -2.20), v(-0.545, -0.24, -2.20)),
    },
    fit = { "artillery.large", "artillery.large", "launcher.cruise", "launcher.cruise", "launcher.cruise", "launcher.cruise", "launcher.cruise" },
  },
  ["industrial.caravan"] = {
    faction = "vessari", draw = caravan, sheets = 4.0,
    -- (its one gun on the platform over the forward bay, and under the keel there)
    turrets = { over(v(-0.06, 0.493, 0.78), v(0.06, -0.508, 0.78)) },
    launchers = {},
    fit = { "autocannon.small" },
  },
  -- The Talmar. (Their hulls are the same on both sides, and so are
  -- their mounts: each pair is a beam apart, or back and keel on the
  -- middle line. They are taken from the skins themselves.)
  ["frigate.harrier"] = {
    faction = "talmar", draw = rapier, sheets = 5.0,
    turrets = {
      abeam(on(RAPIER, 0.08, STARBOARD_SIDE), on(RAPIER, 0.08, PORT_SIDE)),
      -- (on the back behind the bridge: the bridge's blister is too small to stand a gun on)
      over(on(RAPIER, -0.30, BACK), on(RAPIER, 0.08, KEEL)),
    },
    launchers = {
      -- (on the flanks where the body is fullest: farther aft it draws in too fast for a rack's foot)
      abeam(on(RAPIER, -0.14, STARBOARD_SIDE), on(RAPIER, -0.14, PORT_SIDE)),
      over(on(RAPIER, 0.52, BACK), on(RAPIER, -0.28, KEEL)),
    },
    fit = { "autocannon.small", "autocannon.small", "launcher.light", "launcher.light" },
  },
  ["destroyer.sabre"] = {
    faction = "talmar", draw = sabre, sheets = 6.0,
    turrets = {
      over(on(SABRE, -0.05, BACK), on(SABRE, -0.05, KEEL)), over(on(SABRE, -0.85, BACK), on(SABRE, -0.85, KEEL)),
      -- (on the pontoons' backs and under them, one pontoon's back and the
      -- other's keel to a pair: a pontoon's flank is too slight for a gun's ring)
      over(on(SABRE_PONTOON, 0.10, BACK, 0.36, -0.06), on(SABRE_PONTOON, 0.10, KEEL, -0.36, -0.06)),
      over(on(SABRE_PONTOON, -0.34, BACK, -0.36, -0.06), on(SABRE_PONTOON, -0.34, KEEL, 0.36, -0.06)),
    },
    launchers = { over(on(SABRE, 1.05, BACK), on(SABRE, 1.05, KEEL)), over(on(SABRE, 0.62, BACK), on(SABRE, 0.45, KEEL)) },
    fit = { "autocannon.small", "autocannon.small", "autocannon.small", "autocannon.small", "launcher.light", "launcher.light" },
  },
  ["cruiser.falchion"] = {
    faction = "talmar", draw = falchion, sheets = 7.0,
    turrets = {
      over(on(FALCHION, 0.65, BACK), on(FALCHION, 0.60, KEEL)),
      -- (on the wings' broad faces, the starboard wing's back and the port
      -- wing's underside: a wing's edge is too thin to stand a gun on)
      over(on(FALCHION_WING, -0.30, BACK, 0.50, -0.04), on(FALCHION_WING, -0.30, KEEL, -0.50, -0.04)),
      -- (on the tier's back and under the body, ahead of where the tail draws in)
      over(on(FALCHION_TIER, -0.45, BACK, 0, 0.22), on(FALCHION, -0.55, KEEL)),
    },
    launchers = { over(on(FALCHION_TIER, 0.08, BACK, 0, 0.22), on(FALCHION, -0.10, KEEL)) },
    fit = { "autocannon.medium", "autocannon.medium", "autocannon.medium", "launcher.heavy" },
  },
  ["battleship.claymore"] = {
    faction = "talmar", draw = claymore, sheets = 9.0,
    turrets = {
      over(on(CLAYMORE, 1.20, BACK), on(CLAYMORE, 1.20, KEEL)),
      abeam(on(CLAYMORE_FLANK, -0.30, STARBOARD_SIDE, 0.60, -0.10), on(CLAYMORE_FLANK, -0.30, PORT_SIDE, -0.60, -0.10)),
      abeam(on(CLAYMORE_FLANK, -1.00, STARBOARD_SIDE, 0.60, -0.10), on(CLAYMORE_FLANK, -1.00, PORT_SIDE, -0.60, -0.10)),
      over(on(CLAYMORE_TIER, -0.05, BACK, 0, 0.40), on(CLAYMORE_KEEL, 0.20, KEEL, 0, -0.40)),
      over(on(CLAYMORE, -1.55, BACK), on(CLAYMORE, -1.55, KEEL)),
    },
    launchers = {
      abeam(on(CLAYMORE, 1.25, STARBOARD_SIDE), on(CLAYMORE, 1.25, PORT_SIDE)),
      over(on(CLAYMORE_TIER, -1.05, BACK, 0, 0.40), on(CLAYMORE, -1.00, KEEL)),
    },
    fit = { "artillery.large", "artillery.large", "artillery.large", "artillery.large", "artillery.large", "launcher.cruise", "launcher.cruise" },
  },
  ["industrial.packet"] = {
    faction = "talmar", draw = packet, sheets = 6.0,
    -- (its one gun on the spine's back, and under a cargo sac)
    turrets = { over(on(PACKET, 0.0, BACK), on(sac(2), 0.27, KEEL, 0, -0.13)) },
    launchers = {},
    fit = { "autocannon.small" },
  },
  -- The Orun. (Each from a different yard: its own paint as well as its
  -- own shape. Their guns are hybrids, all on turrets.)
  ["frigate.mastiff"] = {
    faction = "orun", draw = mastiff, sheets = 4.0, look = orun({ 0.60, 0.60, 0.57 }, 0.35, 0.10),
    -- (a gun on the body's back and under it; one on the outside of each
    -- prong; one on top of the starboard prong and under the port one)
    turrets = {
      over(v(0, 0.165, -0.12), v(0, -0.11, -0.20)), abeam(v(0.235, -0.01, 0.50), v(-0.235, -0.01, 0.50)),
      over(v(0.17, 0.072, 0.30), v(-0.17, -0.085, 0.30)),
    },
    launchers = {},
    fit = { "blaster.small", "blaster.small", "blaster.small" },
  },
  ["destroyer.boar"] = {
    faction = "orun", draw = boar, sheets = 5.5, look = orun({ 0.17, 0.18, 0.20 }, 0.50, 0.15),
    -- (on and under each hull, fore and aft; and on the outside of each)
    turrets = {
      over(v(0.36, 0.17, 0.80), v(0.36, -0.17, 0.80)), over(v(-0.36, 0.17, 0.80), v(-0.36, -0.17, 0.80)),
      over(v(0.36, 0.17, -0.45), v(0.36, -0.17, -0.45)), over(v(-0.36, 0.17, -0.45), v(-0.36, -0.17, -0.45)),
      abeam(v(0.55, -0.03, -0.20), v(-0.55, -0.03, -0.20)), abeam(v(0.51, 0, 0.92), v(-0.51, 0, 0.92)),
    },
    launchers = {},
    fit = { "blaster.small", "blaster.small", "blaster.small", "blaster.small", "blaster.small", "blaster.small" },
  },
  ["cruiser.aurochs"] = {
    faction = "orun", draw = aurochs, sheets = 7.0, look = orun({ 0.33, 0.35, 0.37 }, 0.55, 0.30),
    -- (on and under the head and the length behind it; on each sponson;
    -- on the back of the fourth length and under the bay)
    turrets = {
      over(v(0, 0.30, 1.27), v(0, -0.34, 1.27)), over(v(0, 0.24, 0.68), v(0, -0.16, 0.68)),
      abeam(v(0.54, -0.06, 0.08), v(-0.54, -0.06, 0.08)), over(v(0, 0.25, -0.62), v(0, -0.43, -0.45)),
    },
    launchers = {},
    fit = { "railgun.medium", "railgun.medium", "railgun.medium", "railgun.medium" },
  },
  ["battleship.mammoth"] = {
    faction = "orun", draw = mammoth, sheets = 12, look = orun({ 0.24, 0.27, 0.31 }, 0.50, 0.25),
    -- (on and under the middle hull, three times along it; on the first
    -- stage of the citadel and under the hull below it; on and under each
    -- outer hull; and on the outside of each)
    turrets = {
      over(v(0, 0.40, 2.00), v(0, -0.40, 2.00)), over(v(0, 0.40, 1.00), v(0, -0.40, 1.00)),
      over(v(0, 0.72, -0.14), v(0, -0.40, -0.40)), over(v(0, 0.40, -1.75), v(0, -0.40, -1.75)),
      over(v(0.92, 0.12, 0.65), v(0.92, -0.36, 0.65)), over(v(-0.92, 0.12, 0.65), v(-0.92, -0.36, 0.65)),
      abeam(v(1.16, -0.16, -0.80), v(-1.16, -0.16, -0.80)),
    },
    launchers = {},
    fit = { "railgun.large", "railgun.large", "railgun.large", "railgun.large", "railgun.large", "railgun.large", "railgun.large" },
  },
  ["industrial.ox"] = {
    faction = "orun", draw = ox, sheets = 5.0, look = orun({ 0.42, 0.41, 0.39 }, 0.70, 0.50),
    -- (its one gun on the starboard hull's bow and under it)
    turrets = { over(v(0.43, 0.13, 1.12), v(0.43, -0.13, 1.12)) },
    launchers = {},
    fit = { "blaster.small" },
  },
  -- The Kethri. (Lasers, all on turrets. Each pair stands on the sloped
  -- armour, one topside to one side and its twin underneath to the
  -- other, turn about along the hull; and the last pair on the flats,
  -- on the back behind the tower and under the keel.)
  ["frigate.lancer"] = {
    faction = "kethri", draw = lancer, sheets = 5.0, even = 0.7, reach = 1.10,
    turrets = {
      slopes("Lancer", LANCER, 0.30, 1, LANCER_FOOT), slopes("Lancer", LANCER, -0.20, -1, LANCER_FOOT),
      flats("Lancer", LANCER, -0.69, LANCER, -0.50, LANCER_FOOT),
    },
    launchers = {},
    fit = { "laser.pulse.small", "laser.pulse.small", "laser.pulse.small" },
  },
  ["destroyer.gantry"] = {
    faction = "kethri", draw = gantry, sheets = 6.0, even = 0.7, reach = 1.585,
    turrets = {
      slopes("Gantry", GANTRY, 0.56, 1, GANTRY_FOOT), slopes("Gantry", GANTRY, 0.26, -1, GANTRY_FOOT, GANTRY_TIER),
      slopes("Gantry", GANTRY, -0.08, 1, GANTRY_FOOT, GANTRY_TIER), slopes("Gantry", GANTRY, -0.44, -1, GANTRY_FOOT, GANTRY_TIER),
      slopes("Gantry", GANTRY, -0.76, 1, GANTRY_FOOT, GANTRY_TIER), flats("Gantry", GANTRY_TIER, -1.10, GANTRY, -0.95, GANTRY_FOOT),
    },
    launchers = {},
    fit = { "laser.pulse.small", "laser.pulse.small", "laser.pulse.small", "laser.pulse.small", "laser.pulse.small", "laser.pulse.small" },
  },
  ["cruiser.trellis"] = {
    faction = "kethri", draw = trellis, sheets = 7.5, even = 0.7, reach = 1.61,
    turrets = {
      slopes("Trellis", TRELLIS, 0.85, 1, TRELLIS_FOOT), slopes("Trellis", TRELLIS, 0.25, -1, TRELLIS_FOOT, TRELLIS_TIER),
      slopes("Trellis", TRELLIS, -0.32, 1, TRELLIS_FOOT, TRELLIS_TIER), flats("Trellis", TRELLIS_TIER, -1.00, TRELLIS, -0.45, TRELLIS_FOOT),
    },
    launchers = {},
    fit = { "laser.pulse.medium", "laser.pulse.medium", "laser.pulse.medium", "laser.pulse.medium" },
  },
  ["battleship.spire"] = {
    faction = "kethri", draw = spireShip, sheets = 12, even = 0.7, reach = 2.70,
    turrets = {
      slopes("Spire", SPIRE, 1.80, 1, SPIRE_FOOT), slopes("Spire", SPIRE, 1.25, -1, SPIRE_FOOT, SPIRE_TIER),
      slopes("Spire", SPIRE, 0.62, 1, SPIRE_FOOT, SPIRE_TIER), slopes("Spire", SPIRE, 0.00, -1, SPIRE_FOOT, SPIRE_TIER),
      slopes("Spire", SPIRE, -0.62, 1, SPIRE_FOOT, SPIRE_TIER), slopes("Spire", SPIRE, -1.25, -1, SPIRE_FOOT, SPIRE_TIER),
      flats("Spire", SPIRE_TIER, -1.76, SPIRE, -1.80, SPIRE_FOOT),
    },
    launchers = {},
    fit = { "laser.beam.large", "laser.beam.large", "laser.beam.large", "laser.beam.large", "laser.beam.large", "laser.beam.large",
      "laser.beam.large" },
  },
  ["industrial.lighter"] = {
    faction = "kethri", draw = lighter, sheets = 5.0, even = 0.7, reach = 1.42,
    -- (its one gun on the flat of the back ahead of the first hatch, and under the keel there)
    turrets = { flats("Lighter", LIGHTER, 0.79, LIGHTER, 0.79, LIGHTER_FOOT) },
    launchers = {},
    fit = { "laser.pulse.small" },
  },
  -- (a freighter has nothing on it to fight with)
  ["freighter.dray"] = { faction = "civil", draw = dray, sheets = 6.0, turrets = {}, launchers = {}, fit = {} },
  -- (And the three plain working hulls anybody flies: the mining
  -- frigate, the mining barge and the hauler.)
  ["frigate.prospector"] = {
    faction = "civil", draw = prospector, fine = MANNER_FINE,
    -- (a mining laser on the head and under it; one on each shoulder)
    turrets = { bentOver(PROSPECTOR, v(0, 0.6, 3.45), v(0, -0.6, 3.45)), bentAbeam(PROSPECTOR, v(2.5, 0, -1.9), v(-2.5, 0, -1.9)) },
    launchers = {},
    fit = { "miner.small", "miner.small" },
  },
  ["barge.quarry"] = {
    faction = "civil", draw = quarry, sheets = 5.0, fine = MANNER_FINE,
    -- (its three heads on the working deck: the middle one above and
    -- below, the others above on one side and below on the other)
    turrets = { bentOver(QUARRY, v(0, 0.525, 4.6), v(0, -0.5, 4.6)), bentOver(QUARRY, v(0.85, 0.525, 4.6), v(-0.85, -0.5, 4.6)),
      bentOver(QUARRY, v(-0.85, 0.525, 4.6), v(0.85, -0.5, 4.6)) },
    launchers = {},
    fit = { "miner.strip", "miner.strip", "miner.strip" },
  },
  ["industrial.hauler"] = {
    faction = "civil", draw = mule, sheets = 4.5, fine = MANNER_FINE,
    -- (its one gun on the bridge's roof, and under the head)
    turrets = { bentOver(MULE, v(0, 1.22, 4.7), v(0, -0.65, 5.0)) },
    launchers = {},
    fit = { "autocannon.small" },
  },
  ["frigate.courier"] = {
    faction = "civil", draw = courier,
    -- (a gun on the back and under the cargo box; a gun on each flank)
    turrets = { over(v(0, 0.235, 0.36), v(0, -0.40, 0.10)), abeam(v(0.24, 0.04, -0.06), v(-0.24, 0.04, -0.06)) },
    launchers = {},
    fit = { "autocannon.small", "autocannon.small" },
  },
}

-- Stand-ins. A hull of a class nobody has drawn (the project owner's
-- ladder of 2026-11-12: the two battlecruisers and the capitals), which
-- no line of resource/hull/seeds.txt names either, is drawn by the
-- generator from a seed that follows from its name: the first from
-- there on with the room for its hardpoints. Nothing is meant by which
-- seed that is: it stands in until the hull's own is picked. It is
-- worked out when the hull is first wanted and not before ('pending'):
-- there are dozens of them, and most are never looked at.
-- (At the size the generator made its biggest hulls: a bigger one is
-- seconds in the making, and these are many.)
local STAND_SIZE: { [string]: number } = { attackbattlecruiser = 4, battlecruiser = 5, carrier = 5, dreadnought = 5,
  siegedreadnought = 5, capitalindustrial = 5, supercarrier = 5 }
local pending: { [string]: () -> Design? } = {}

-- A design drawn for a hull there no longer is (a faction's ships
-- reworked: the Talmar's, 2026-11-13, whose hulls are now the
-- generator's, by resource/hull/seeds.txt) is nobody's: the drawing
-- of it is kept above, and is not a hull of the game.
for id in designs do
  if Ships.byId[id] == nil then
    designs[id] = nil
  end
end

-- The design of a hull type, if it has one (a stand-in is made here,
-- the first time it is asked for).
local function designOf(type: string): Design?
  local wait = pending[type]
  if wait then
    pending[type] = nil
    local made = wait()
    if made then
      designs[type] = made
    end
  end
  return designs[type]
end

-- What a hull with no design of its own is shown carrying: its
-- faction's kind of gun and launchers, of the size its class is for.
-- (Core/Fits says which: it is what such a hull is measured with too,
-- in the balance report, and the two are not to differ.)
local function standFit(hull: Ships.ShipType): { string }
  return Fits.Weapons(hull)
end

-- How many engines a hull of a size is given, where the seed has the
-- ends for them.
local function enginesFor(hull: Ships.ShipType): number
  return if hull.radius < 60 then 2 elseif hull.radius < 200 then 3 elseif hull.radius < 700 then 4 else 6
end

-- The design of a generated hull as a ship. (As the generator made it:
-- its own mesh, and no paint. Painted, it is drawn as the game's hulls
-- are, in the paint of the design it takes the place of, or its
-- faction's.)
local function grownDesign(ship: Ship, hull: Ships.ShipType, had: Design?, fit: { string }, painted: boolean?, detail: Detail?): Design
  return {
    faction = if had then had.faction elseif Hull.looks[hull.lineage] then hull.lineage else "civil",
    look = if painted then (if had then had.look else nil) else Hull.looks.bare,
    sheets = if had then had.sheets else nil, even = if had then had.even else nil, fine = MANNER_FINE,
    quality = if painted then nil else BARE_QUALITY,
    draw = function(b: Builder)
      grown(b, ship.growth)
      seated(b, ship.seats)
      jets(b, ship.ends)
      if detail then
        detailed(b, ship, detail, hull.radius)
      end
    end,
    turrets = ship.turrets, launchers = ship.launchers, fit = fit,
  }
end

local function standIn(hull: Ships.ShipType): Design?
  local seed = 0
  for index = 1, #hull.id do
    seed = (seed * 31 + string.byte(hull.id, index)) % 9973
  end
  local steps, decks = Hull.GrownSize(STAND_SIZE[hull.class])
  local fit = standFit(hull)
  for try = 0, 39 do
    local ship = shipOf(growth(seed + try, steps, decks, styleOf(nil)), hull.radius, fit, hull.turrets, hull.launchers, enginesFor(hull))
    if ship then
      return grownDesign(ship, hull, nil, fit, false)
    end
  end
  return nil
end

for _, hull in Ships.list do
  if STAND_SIZE[hull.class] and hull.tech ~= 2 and designs[hull.id] == nil then
    pending[hull.id] = function(): Design?
      return standIn(hull)
    end
  end
end

-- A hull of the game's drawn as the generator grows one from a seed,
-- at a size (Hull.SIZES), carrying what the design it takes the place
-- of is shown with (or, if it has none of its own, what its class and
-- its faction say), on the hardpoints the hull has by the data.
-- Nothing, and why, if there is no such hull or the seed has not the
-- room for its hardpoints.
local function seeded(type: string, seed: number, size: number, style: string?, painted: boolean?, detail: Detail?): (Design?, string)
  local hull = Ships.byId[type]
  local had = designs[type]
  if hull == nil then
    return nil, "there is no such hull"
  elseif Hull.SIZES[size] == nil then
    return nil, `sizes are 1 to {#Hull.SIZES}`
  end
  local fit = if had then table.clone(had.fit) else standFit(hull)
  while #fit < hull.turrets + hull.launchers do
    table.insert(fit, if #fit < hull.turrets then "autocannon.small" else "launcher.light")
  end
  local steps, decks = Hull.GrownSize(size)
  if style and styleOf(style).name ~= style then
    return nil, `there is no style called '{style}'`
  end
  local ship, why = shipOf(growth(seed, steps, decks, styleOf(style)), hull.radius, fit, hull.turrets, hull.launchers, enginesFor(hull))
  if ship == nil then
    return nil, why
  end
  return grownDesign(ship, hull, had, fit, painted, detail), ""
end

-- The hulls that are drawn by seed: resource/hull/seeds.txt, a hull's
-- type, a seed and a size to a line. (Read here, before the designs that
-- follow other designs are made: a pirate's copy and a tech 2 make are
-- of the hull as it is drawn.)
Hull.SEEDS = "resource/hull/seeds.txt"
-- Every hull the list names, as its line has it (for the hull browser,
-- which can be asked for one by name and build it again).
export type SeedLine = { name: string, seed: number, size: number, style: string?, painted: boolean, detail: { string } }
Hull.SEEDED = {} :: { SeedLine }
do
  local ok, text = pcall(File_Read, Hull.SEEDS)
  if ok and type(text) == "string" then
    for line in string.gmatch(text, "[^\r\n]+") do
      local name, seed, size, words = string.match(line, "^%s*([%a%d%._]+)%s+(%d+)%s+(%d+)%s*([%w%s_%+]-)%s*$")
      if name and string.sub(name, 1, 1) ~= "#" then
        -- (after the size, in any order: a style, "painted", and the
        -- kinds of surface detail it has (Hull.DETAILS). A style's name
        -- may have a figure and a line in it, and Hull.ASYM after it:
        -- triangular_v2+asym.)
        local style: string? = nil
        local painted = false
        local kinds: { string } = {}
        for word in string.gmatch(words or "", "[%w_%+]+") do
          if word == "painted" then
            painted = true
          elseif table.find(Hull.DETAILS, word) then
            table.insert(kinds, word)
          else
            style = word
          end
        end
        table.insert(Hull.SEEDED, { name = name, seed = tonumber(seed) or 0, size = tonumber(size) or 0, style = style, painted = painted,
          detail = kinds })
        local design, why = seeded(name, tonumber(seed) or 0, tonumber(size) or 0, style, painted, Hull.DetailOf(kinds))
        if design then
          designs[name] = design
          pending[name] = nil
        else
          print(`{Hull.SEEDS}: {name} is not drawn from seed {seed} at size {size}: {why}`)
        end
      end
    end
  end
end

-- How much of a pirate's ship is not as its builders left it.
local PATCHED = 0.8

-- The pirates' own hulls. Each began as a human hull (its 'donor' in
-- Core/Data/Ships) and is that hull's design, patched, with more guns
-- bolted on than it was built for: the donor's hardpoints, and beside
-- them as many more as the pirate hull has. Where nobody has drawn the
-- donor yet, the Vessari hull of its class stands in for it.
for _, hull in Ships.list do
  if hull.lineage == "unbound" and designs[hull.id] == nil then
    local base: Design? = if hull.donor then designs[hull.donor] else nil
    if base == nil then
      for id, design in designs do
        local other = Ships.byId[id]
        if design.faction == "vessari" and other and other.class == hull.class then
          base = design
        end
      end
    end
    if base then
      local points: { Hardpoint } = {}
      for _, point in base.turrets do
        table.insert(points, point)
      end
      for _, point in base.launchers do
        table.insert(points, point)
      end
      local had = #points
      local extra = 0
      while #points < hull.turrets + hull.launchers and had > 0 do
        extra += 1
        -- (beside one of those it has, a little way aft)
        local like = points[(extra - 1) % had + 1]
        local shift = v(0, 0, -0.17 * math.ceil(extra / had))
        table.insert(points, {
          { at = like[1].at + shift, up = like[1].up, fore = like[1].fore },
          { at = like[2].at + shift, up = like[2].up, fore = like[2].fore },
        })
      end
      local gun = if #base.turrets > 0 then base.fit[1] else "autocannon.small"
      local rack = if #base.launchers > 0 then base.fit[#base.turrets + 1] else "launcher.light"
      local derived: Design = { faction = "unbound", draw = base.draw, patch = PATCHED, copied = true, sheets = base.sheets,
        fine = base.fine, turrets = {},
        launchers = {}, fit = {} }
      for index, point in points do
        if index <= hull.turrets then
          table.insert(derived.turrets, point)
        elseif index <= hull.turrets + hull.launchers then
          table.insert(derived.launchers, point)
        end
      end
      for _ = 1, #derived.turrets do
        table.insert(derived.fit, gun)
      end
      for _ = 1, #derived.launchers do
        table.insert(derived.fit, rack)
      end
      if #derived.turrets == hull.turrets and #derived.launchers == hull.launchers then
        designs[hull.id] = derived
      end
    end
  end
end

-- Tech 2 hulls. Each is the hull it is the improved make of
-- (Core/Data/Ships): the same shape with the same hardpoints, repainted.
-- Its plating is dark, most of the way to black; its patches, its
-- markings and its lights are as they were, and it is kept cleaner.
local function rebuilt(look: Look): Look
  local p = look.plating
  return {
    plating = { p[1] * 0.42 + 0.02, p[2] * 0.42 + 0.02, p[3] * 0.42 + 0.03 }, patch = look.patch, frame = look.frame,
    glow = look.glow, trim = look.trim, fire = look.fire, wear = look.wear * 0.6, rust = look.rust * 0.4,
    sheets = look.sheets, mottle = look.mottle, lights = look.lights,
  }
end

-- (A hull in bare metal has no paint to darken: its tech 2 make is as
-- it is.)
local function improved(base: Design): Design
  local look = base.look or Hull.looks[base.faction]
  return { faction = base.faction, draw = base.draw, sheets = base.sheets, even = base.even, reach = base.reach,
    fine = base.fine, quality = base.quality, look = if look.bare then look else rebuilt(look), turrets = base.turrets,
    launchers = base.launchers, fit = base.fit }
end
for _, hull in Ships.list do
  local from = if hull.tech == 2 then hull.base else nil
  local base: Design? = if from then designs[from] else nil
  if base and designs[hull.id] == nil then
    designs[hull.id] = improved(base)
  elseif from and pending[from] and designs[hull.id] == nil then
    -- (the tech 2 make of a stand-in: when that is wanted)
    pending[hull.id] = function(): Design?
      local stood = designOf(from)
      return if stood then improved(stood) else nil
    end
  end
end

-- ---------------------------------------------------------------------
-- What a pirate camp is built of (Core/Tactical/Assault): things that
-- stand where they are put. None of them is a ship and none is drawn as
-- one: no bow, no engines, and as much beneath as above. They are the
-- pirates' own work, of whatever was to hand.

-- A crate lashed on: a box with two straps round it.
local function crate(b: Builder, center: vector, half: vector, part: number?)
  block(b, part or PLATING, center, half, nil, 0.08)
  for _, side in { -0.5, 0.5 } do
    block(b, FRAME, center + v(0, 0, side * half.z), v(half.x * 1.05, half.y * 1.05, half.z * 0.06), nil, 0.2)
  end
end

-- The Cache, a store: a length of girder with crates lashed to it on
-- every side, no two the same size, a tank or two among them, a mast,
-- and a lamp at each end.
local function cache(b: Builder)
  truss(b, v(0, 0, -0.85), v(0, 0, 0.85), 0.16, 6)
  truss(b, v(0, 0, -0.85), v(0, 0, 0.85), 0.16, 6, v(1, 0, 0))
  crate(b, v(0.30, 0.02, 0.42), v(0.20, 0.22, 0.34))
  crate(b, v(-0.27, -0.05, 0.50), v(0.17, 0.17, 0.26), PATCH)
  crate(b, v(0.02, 0.31, -0.05), v(0.24, 0.19, 0.30))
  crate(b, v(-0.04, -0.33, -0.12), v(0.22, 0.21, 0.36))
  crate(b, v(0.29, -0.03, -0.45), v(0.18, 0.18, 0.28), PATCH)
  crate(b, v(-0.31, 0.06, -0.30), v(0.20, 0.24, 0.40))
  tank(b, v(-0.22, 0.30, 0.52), 0.11, 0.26)
  tank(b, v(0.24, -0.30, 0.55), 0.10, 0.22)
  mast(b, v(0.02, 0.50, -0.05), 0.40, 0.05)
  block(b, GLOW, v(0, 0, 0.87), v(0.05, 0.05, 0.02), nil, 0.3)
  block(b, GLOW, v(0, 0, -0.87), v(0.05, 0.05, 0.02), nil, 0.3)
end

-- The Depot, a big store: a boxed girder with a deck through it, crates
-- in a row along its back and another under its belly, no two alike; a
-- great tank out on arms on either flank, one forward and one aft; and
-- the keepers' quarters on one side, lit, with a mast.
local function depot(b: Builder)
  for _, side in { -1, 1 } do
    truss(b, v(side * 0.10, 0, -0.98), v(side * 0.10, 0, 0.98), 0.20, 10)
  end
  block(b, FRAME, v(0, 0, 0), v(0.13, 0.03, 0.96), nil, 0.1)
  for row = 1, 5 do
    local z = -0.78 + (row - 1) * 0.39
    local tall = 0.13 + 0.05 * ((row * 7) % 3)
    crate(b, v(0, 0.12 + tall, z), v(0.20 + 0.03 * (row % 2), tall, 0.17), if row % 3 == 0 then PATCH else PLATING)
    local deep = 0.12 + 0.05 * ((row * 5) % 3)
    crate(b, v(0, -0.12 - deep, z + 0.04), v(0.22 - 0.03 * (row % 2), deep, 0.16), if row % 4 == 0 then PATCH else PLATING)
  end
  for _, side in { -1, 1 } do
    local z = 0.30 * side
    tank(b, v(side * 0.42, 0.02 * side, z), 0.17, 0.52, PLATING)
    for _, at in { -0.3, 0.3 } do
      beam(b, FRAME, v(side * 0.12, 0, z + at), v(side * 0.30, 0.02 * side, z + at), 0.025, 0.1)
    end
  end
  block(b, PLATING, v(-0.36, 0.05, -0.55), v(0.14, 0.12, 0.20), nil, 0.1)
  ports(b, v(-0.505, 0.07, -0.70), v(-0.505, 0.07, -0.40), 4, 0.022)
  beam(b, FRAME, v(-0.12, 0, -0.55), v(-0.24, 0.03, -0.55), 0.03, 0.1)
  mast(b, v(-0.36, 0.17, -0.55), 0.42, -0.04)
end

-- The Battery, a gun emplacement: an armoured drum of eight sides with a
-- flat deck above and beneath, its launchers on the decks; a belt of
-- slab armour round its waist, a slab gone; and a boom out to one side
-- with its eyes on it.
local BATTERY_DECK = 0.20
local BATTERY_GUNS: { vector } = { v(0, 0, 0.27), v(0.25, 0, -0.16), v(-0.25, 0, -0.16) }
local function battery(b: Builder)
  block(b, PLATING, v(0, 0, 0), v(0.52, BATTERY_DECK, 0.52), nil, 0.08)
  block(b, PLATING, v(0, 0, 0), v(0.52, BATTERY_DECK, 0.52), v(math.pi / 4, 0, 0), 0.08)
  for index = 0, 6 do
    local angle = index * math.pi / 4 + math.pi / 8
    block(b, if index % 3 == 1 then PATCH else PLATING, v(0.60 * math.sin(angle), 0, 0.60 * math.cos(angle)), v(0.17, 0.13, 0.035),
      v(angle, 0, 0), 0.12)
  end
  for _, side in { -1, 1 } do
    block(b, FRAME, v(0, side * (BATTERY_DECK + 0.015), 0), v(0.07, 0.02, 0.07), v(math.pi / 4, 0, 0), 0.2)
    block(b, GLOW, v(0, side * (BATTERY_DECK + 0.04), 0), v(0.035, 0.008, 0.035), nil, 0.3)
  end
  beam(b, FRAME, v(0.50, 0, 0.10), v(0.95, 0.04, 0.20), 0.03, 0.1)
  mast(b, v(0.95, 0.04, 0.20), 0.36, 0.03)
  block(b, PATCH, v(0.95, -0.06, 0.20), v(0.06, 0.08, 0.06), nil, 0.15)
end

-- The Redoubt, a fort: a keep, with a narrower storey above it and one
-- beneath, lit; four bastions at its corners, no two the same height,
-- each joined to the keep by a wall and to the next by a curtain, with
-- a launcher on its head and one under its foot; and a mast on the keep.
local REDOUBT_OUT = 0.72
local REDOUBT_HIGH: { number } = { 0.17, 0.20, 0.17, 0.20 }
local function bastionAt(index: number): (vector, number)
  local angle = math.pi / 4 + (index - 1) * math.pi / 2
  return v(REDOUBT_OUT * math.sin(angle), 0, REDOUBT_OUT * math.cos(angle)), angle
end
local function redoubt(b: Builder)
  block(b, PLATING, v(0, 0, 0), v(0.34, 0.30, 0.34), nil, 0.08)
  for _, side in { -1, 1 } do
    block(b, PLATING, v(0, side * 0.40, 0), v(0.24, 0.10, 0.24), v(math.pi / 4, 0, 0), 0.10)
    block(b, FRAME, v(0, side * 0.515, 0), v(0.20, 0.015, 0.20), v(math.pi / 4, 0, 0), 0.1)
    for _, face in { -1, 1 } do
      block(b, GLOW, v(face * 0.343, side * 0.12, 0), v(0.004, 0.035, 0.20), nil, 0.3)
    end
  end
  for index = 1, 4 do
    local at, angle = bastionAt(index)
    block(b, if index == 3 then PATCH else PLATING, at, v(0.17, REDOUBT_HIGH[index], 0.17), v(angle, 0, 0), 0.08)
    block(b, PLATING, at * 0.62, v(0.05, 0.11, 0.20), v(angle, 0, 0), 0.08)
    -- (the curtain to the next bastion round, with a gap in one of them)
    if index ~= 2 then
      local along = angle + math.pi / 4
      local out = REDOUBT_OUT * math.cos(math.pi / 4)
      block(b, PLATING, v(out * math.sin(along), 0, out * math.cos(along)), v(0.36, 0.09, 0.03), v(along, 0, 0), 0.10)
    end
  end
  mast(b, v(0, 0.53, 0), 0.40, 0.03)
end

designs["works.cache"] = { faction = "unbound", draw = cache, patch = PATCHED, turrets = {}, launchers = {}, fit = {} }
designs["works.depot"] = { faction = "unbound", draw = depot, patch = PATCHED, sheets = 5.0, turrets = {}, launchers = {}, fit = {} }
do
  local guns: { Hardpoint } = {}
  for _, at in BATTERY_GUNS do
    table.insert(guns, over(at + v(0, BATTERY_DECK, 0), at - v(0, BATTERY_DECK, 0)))
  end
  designs["works.battery"] = { faction = "unbound", draw = battery, patch = PATCHED, turrets = {}, launchers = guns,
    fit = { "launcher.light", "launcher.light", "launcher.light" } }
  -- A station's batteries (Core/Tactical/Batteries), which stand
  -- outside its field: the same drum in good repair, with its whole
  -- belt and no boom, guns on the decks of the one and launchers on
  -- the other.
  local function post(b: Builder)
    block(b, PLATING, v(0, 0, 0), v(0.52, BATTERY_DECK, 0.52), nil, 0.08)
    block(b, PLATING, v(0, 0, 0), v(0.52, BATTERY_DECK, 0.52), v(math.pi / 4, 0, 0), 0.08)
    for index = 0, 7 do
      local angle = index * math.pi / 4 + math.pi / 8
      block(b, PLATING, v(0.60 * math.sin(angle), 0, 0.60 * math.cos(angle)), v(0.17, 0.13, 0.035), v(angle, 0, 0), 0.12)
    end
    for _, side in { -1, 1 } do
      block(b, FRAME, v(0, side * (BATTERY_DECK + 0.015), 0), v(0.07, 0.02, 0.07), v(math.pi / 4, 0, 0), 0.2)
      block(b, GLOW, v(0, side * (BATTERY_DECK + 0.04), 0), v(0.035, 0.008, 0.035), nil, 0.3)
    end
  end
  local function mounts(): { Hardpoint }
    local points: { Hardpoint } = {}
    for _, at in BATTERY_GUNS do
      table.insert(points, over(at + v(0, BATTERY_DECK, 0), at - v(0, BATTERY_DECK, 0)))
    end
    return points
  end
  designs["works.battery.gun"] = { faction = "civil", draw = post, turrets = mounts(), launchers = {},
    fit = { "autocannon.small", "autocannon.small", "autocannon.small" } }
  designs["works.battery.missile"] = { faction = "civil", draw = post, turrets = {}, launchers = mounts(),
    fit = { "launcher.light", "launcher.light", "launcher.light" } }
  local heavy: { Hardpoint } = {}
  for index = 1, 4 do
    local at = bastionAt(index)
    table.insert(heavy, over(at + v(0, REDOUBT_HIGH[index], 0), at - v(0, REDOUBT_HIGH[index], 0)))
  end
  designs["works.redoubt"] = { faction = "unbound", draw = redoubt, patch = PATCHED, sheets = 4.0, turrets = {}, launchers = heavy,
    fit = { "launcher.heavy", "launcher.heavy", "launcher.heavy", "launcher.heavy" } }
end

-- The Survey Rig, what a defence job is to hold (Core/Tactical/Assault):
-- anybody's, and no ship, so no bow and no engines. A square deck with
-- its edges in warning paint; a derrick of four legs over the middle of
-- it, a lamp at its head; under the deck the drum of its instruments
-- and a long probe let down from that, lit at the tip; an outrigger to
-- a pad at each corner; the crew's house on the deck to one side, lit,
-- and a dish on a post at the far corner. The bigger ones (there are
-- four sizes) carry more: tanks slung under the deck, then a second
-- house and a stand of masts, then a mast at every pad. (A v0.)
local function rigOf(size: number): (b: Builder) -> ()
  return function(b: Builder)
    -- the deck
    block(b, PLATING, v(0, 0, 0), v(0.46, 0.035, 0.46), nil, 0.06)
    for _, side in { -1, 1 } do
      block(b, TRIM, v(side * 0.43, 0.037, 0), v(0.03, 0.004, 0.46))
      block(b, TRIM, v(0, 0.037, side * 0.43), v(0.40, 0.004, 0.03))
    end
    -- the derrick, braced twice on the way up
    local top = v(0, 0.86, 0)
    for _, x in { -1, 1 } do
      for _, z in { -1, 1 } do
        beam(b, FRAME, v(x * 0.24, 0.03, z * 0.24), top + v(x * 0.03, 0, z * 0.03), 0.022, 0.1)
      end
    end
    for _, share in { 0.33, 0.66 } do
      local wide = 0.24 - 0.21 * share
      local y = 0.03 + 0.83 * share
      for _, side in { -1, 1 } do
        beam(b, FRAME, v(-wide, y, side * wide), v(wide, y, side * wide), 0.014, 0.1)
        beam(b, FRAME, v(side * wide, y, -wide), v(side * wide, y, wide), 0.014, 0.1)
      end
    end
    block(b, GLOW, top + v(0, 0.02, 0), v(0.035, 0.02, 0.035), nil, 0.3)
    -- the instruments under the deck, and the probe
    block(b, PATCH, v(0, -0.17, 0), v(0.18, 0.13, 0.18), nil, 0.45)
    block(b, FRAME, v(0, -0.31, 0), v(0.10, 0.03, 0.10), nil, 0.3)
    beam(b, FRAME, v(0, -0.32, 0), v(0, -0.84, 0), 0.028, 0.1)
    block(b, GLOW, v(0, -0.86, 0), v(0.04, 0.03, 0.04), nil, 0.4)
    -- an outrigger to a pad at each corner, strutted from under the deck
    for _, x in { -1, 1 } do
      for _, z in { -1, 1 } do
        beam(b, FRAME, v(x * 0.44, 0, z * 0.44), v(x * 0.74, -0.06, z * 0.74), 0.026, 0.1)
        beam(b, FRAME, v(x * 0.20, -0.20, z * 0.20), v(x * 0.74, -0.06, z * 0.74), 0.016, 0.1)
        block(b, PLATING, v(x * 0.76, -0.06, z * 0.76), v(0.07, 0.05, 0.07), nil, 0.2)
        if size >= 4 then
          mast(b, v(x * 0.76, -0.01, z * 0.76), 0.30, 0)
        end
      end
    end
    -- the crew's house, to port and forward
    block(b, PATCH, v(-0.26, 0.11, 0.24), v(0.13, 0.075, 0.16), nil, 0.15)
    ports(b, v(-0.125, 0.12, 0.12), v(-0.125, 0.12, 0.36), 3, 0.014)
    -- the dish, on a post at the far corner
    beam(b, FRAME, v(0.32, 0.03, -0.32), v(0.32, 0.30, -0.32), 0.018, 0.1)
    block(b, PATCH, v(0.32, 0.33, -0.32), v(0.13, 0.022, 0.13), nil, 0.5)
    block(b, FRAME, v(0.32, 0.36, -0.32), v(0.09, 0.010, 0.09), nil, 0.5)
    beam(b, FRAME, v(0.32, 0.36, -0.32), v(0.32, 0.46, -0.32), 0.010, 0.1)
    if size >= 2 then
      -- tanks slung under the deck, either side of the instruments
      tank(b, v(0.32, -0.11, 0.06), 0.07, 0.24)
      tank(b, v(-0.32, -0.11, -0.06), 0.07, 0.24, PLATING)
    end
    if size >= 3 then
      -- a second house, aft, and a stand of masts by it
      block(b, PLATING, v(-0.24, 0.10, -0.28), v(0.15, 0.065, 0.11), nil, 0.15)
      ports(b, v(-0.085, 0.11, -0.36), v(-0.085, 0.11, -0.20), 2, 0.014)
      mast(b, v(-0.34, 0.165, -0.30), 0.34, 0.02)
      mast(b, v(0.30, 0.035, 0.32), 0.26, -0.02)
    end
  end
end

-- What stands for a pilot's control tower where it is shot at
-- (Assets/Starbases): the tower itself is drawn as a station is, and
-- this is the collar of shield emitters round its waist: a ring of
-- girder with an emitter at every third joint, lit, on spokes from a
-- hub. Bigger towers have more to the ring.
local function collarOf(size: number): (b: Builder) -> ()
  return function(b: Builder)
    local joints = 9 + 3 * size
    local function at(index: number, out: number): vector
      local angle = index * 2 * math.pi / joints
      return v(math.cos(angle) * out, 0, math.sin(angle) * out)
    end
    for index = 0, joints - 1 do
      beam(b, FRAME, at(index, 0.95), at(index + 1, 0.95), 0.022, 0.1)
      if index % 3 == 0 then
        block(b, PLATING, at(index, 0.95), v(0.07, 0.11, 0.07), v(-index * 2 * math.pi / joints, 0, 0), 0.2)
        block(b, GLOW, at(index, 0.95) + v(0, 0.118, 0), v(0.04, 0.008, 0.04), nil, 0.5)
        block(b, GLOW, at(index, 0.95) - v(0, 0.118, 0), v(0.04, 0.008, 0.04), nil, 0.5)
        beam(b, FRAME, at(index, 0.12), at(index, 0.88), 0.014, 0.1)
      end
    end
    block(b, FRAME, v(0, 0, 0), v(0.10, 0.10, 0.10), v(0, 0, math.pi / 4), 0.3)
  end
end
for size = 1, 3 do
  designs[`works.tower.{size}`] = { faction = "civil", draw = collarOf(size), sheets = 3.0, turrets = {}, launchers = {}, fit = {} }
end
-- (and each people's tower's own core, since 2026-11-16: the same collar)
for _, kind in Structures.towers do
  designs[Structures.Core(kind)] = designs[`works.tower.{kind.size}`]
end

-- The Pirate Tower, what the pirates hold a moon with (Core/Tactical/
-- Keeps): somebody's control tower once, taken and made over. A spine of
-- girder, tall; three storeys of armour stacked on it, no two of them
-- square to each other, the middle one lit; round its waist the collar
-- of shield emitters, a third of the ring gone and what is left of it
-- patched; a store of crates and a tank lashed on under the lowest
-- storey; and masts at its head. It has nothing to shoot with: that is
-- what its batteries are for. (A v0.)
local function keep(b: Builder)
  truss(b, v(0, -0.95, 0), v(0, 0.78, 0), 0.16, 9, v(1, 0, 0))
  truss(b, v(0, -0.95, 0), v(0, 0.78, 0), 0.16, 9, v(0, 0, 1))
  block(b, PLATING, v(0, 0.02, 0), v(0.25, 0.19, 0.25), nil, 0.08)
  for _, face in { -1, 1 } do
    block(b, GLOW, v(face * 0.253, 0.05, 0), v(0.004, 0.03, 0.15), nil, 0.3)
    block(b, GLOW, v(0, 0.05, face * 0.253), v(0.15, 0.03, 0.004), nil, 0.3)
  end
  block(b, PLATING, v(0, 0.38, 0), v(0.18, 0.13, 0.18), v(math.pi / 4, 0, 0), 0.10)
  block(b, PATCH, v(0.02, 0.60, 0.01), v(0.12, 0.07, 0.14), v(math.pi / 9, 0, 0), 0.10)
  block(b, PLATING, v(0, -0.36, 0), v(0.20, 0.12, 0.20), v(math.pi / 8, 0, 0), 0.10)
  block(b, PATCH, v(0.21, -0.34, 0.05), v(0.025, 0.09, 0.11), v(math.pi / 8, 0, 0), 0.1)
  block(b, FRAME, v(0, -0.93, 0), v(0.11, 0.03, 0.11), v(math.pi / 4, 0, 0), 0.2)
  block(b, GLOW, v(0, -0.97, 0), v(0.04, 0.012, 0.04), nil, 0.4)
  -- the collar: nine joints of twelve, an emitter at every third
  local joints = 12
  local function at(index: number, out: number): vector
    local angle = index * 2 * math.pi / joints
    return v(math.cos(angle) * out, 0.02, math.sin(angle) * out)
  end
  for index = 0, 8 do
    if index < 8 then
      beam(b, FRAME, at(index, 0.92), at(index + 1, 0.92), 0.022, 0.1)
    end
    if index % 3 == 0 then
      -- (tall enough that none of them is a small part, to go missing
      -- from under its lamps: Plates' patching)
      block(b, if index == 3 then PATCH else PLATING, at(index, 0.92), v(0.07, 0.125, 0.07), v(-index * 2 * math.pi / joints, 0, 0), 0.2)
      if index ~= 3 then
        block(b, GLOW, at(index, 0.92) + v(0, 0.133, 0), v(0.04, 0.008, 0.04), nil, 0.5)
        block(b, GLOW, at(index, 0.92) - v(0, 0.133, 0), v(0.04, 0.008, 0.04), nil, 0.5)
      end
      beam(b, FRAME, at(index, 0.26), at(index, 0.86), 0.014, 0.1)
    end
  end
  -- (a spoke that holds nothing any more)
  beam(b, FRAME, at(10, 0.26), at(10, 0.58), 0.014, 0.1)
  -- its stores, under the lowest storey
  crate(b, v(0.13, -0.60, 0.10), v(0.10, 0.07, 0.12))
  crate(b, v(-0.14, -0.63, -0.06), v(0.08, 0.09, 0.10), PATCH)
  crate(b, v(-0.02, -0.76, 0.12), v(0.09, 0.05, 0.08))
  tank(b, v(0.16, -0.70, -0.12), 0.07, 0.15)
  mast(b, v(0.03, 0.67, 0.02), 0.32, 0.03)
  mast(b, v(-0.08, 0.67, -0.07), 0.20, -0.04)
end
designs["works.keep"] = { faction = "unbound", draw = keep, patch = PATCHED, sheets = 4.0, turrets = {}, launchers = {}, fit = {} }

for size = 1, 4 do
  designs[`works.rig.{size}`] = { faction = "civil", draw = rigOf(size), sheets = 3.0 + 0.6 * size, turrets = {}, launchers = {}, fit = {} }
end

-- The tenders, what an escort is to see through (Core/Tactical/Assault):
-- anybody's haulers, with nothing on them to shoot with. The two
-- smaller are the Mule's drawing and the two bigger the Dray's, at
-- their own sizes. (A v0: they are told from those by their names.)
for size = 1, 4 do
  designs[`convoy.tender.{size}`] = { faction = "civil", draw = if size <= 2 then mule else dray, sheets = 4.0 + 0.6 * size,
    fine = if size <= 2 then MANNER_FINE else nil,
    turrets = {}, launchers = {}, fit = {} }
end

-- ---------------------------------------------------------------------

export type Built = {
  model: Model,
  radius: number,       -- half the longest way across it, in its own units
  turrets: { Hardpoint },   -- its hardpoints, in its own units
  launchers: { Hardpoint },
  fit: { string },
  engines: { Exhaust }, -- where its engines' fire leaves it
  glow: { number },     -- and the colour of that fire (the look's 'fire', or its 'glow')
  lower: vector,        -- the corners of the box it fills
  upper: vector,
  -- The mounts that are not wholly on the hull, each in a line of words
  -- (none, for a design that is as it should be: Hull.Audit).
  hanging: { string },
  -- What it is made of, and the same drawn cloaked, once that has been
  -- asked for (Hull.Ghost).
  meshes: { Mesh },
  ghost: Model?,
}

local built: { [string]: Built } = {}

-- Whether there is a design for a hull type.
function Hull.Has(type: string): boolean
  return designs[type] ~= nil or pending[type] ~= nil
end

-- The types there are designs for.
function Hull.Types(): { string }
  local out: { string } = {}
  for type in designs do
    table.insert(out, type)
  end
  for type in pending do
    table.insert(out, type)
  end
  table.sort(out)
  return out
end

-- A paint a pilot has had put on a hull, and the design laid on that
-- (Core/Data/Paints), as a look: the paint's colours, new and clean,
-- with what is lit on the hull lit as its builder lit it ('yard': the
-- look it left the yard in). Nothing, with no such paint.
local function coatOf(paint: string?, figure: string?, yard: Look): Look?
  local set = if paint then Paints.paintById[paint] else nil
  if set == nil then
    return nil
  end
  local laid = if figure then Paints.designById[figure] else nil
  -- (new paint is brighter than a yard's: a quarter over what the numbers say, and no more than white)
  local function fresh(colour: { number }): { number }
    return { math.min(1, colour[1] * 1.25), math.min(1, colour[2] * 1.25), math.min(1, colour[3] * 1.25) }
  end
  return {
    plating = fresh(set.plating), patch = fresh(set.patch), frame = fresh(set.frame), trim = fresh(set.trim), glow = yard.glow,
    fire = yard.fire, wear = 0.10, rust = 0.02, sheets = yard.sheets, mottle = 0, lights = yard.lights,
    design = if laid then laid.figure else nil, designScale = if laid then laid.scale else nil, designPaint = fresh(set.accent),
  }
end

-- The model of a hull type and how big it came out, or nil if nobody
-- has designed it. Made once and kept. 'pirate' asks for the hull as a
-- pirate flies it, whoever built it: patched, and in their paint (a
-- pirate hull is that anyway). 'rank': it is a pirate veteran's (1) or
-- a captain's (2), and is painted as theirs are. 'paint' and 'figure':
-- the paint its pilot has had it painted in, and the design on that
-- (Core/Data/Paints; not a pirate's). A hull drawn from a seed is
-- painted on its own mesh, as finely made as it is bare.
function Hull.Build(type: string, pirate: boolean?, rank: number?, paint: string?, figure: string?): Built?
  local design = designOf(type)
  if design == nil then
    return nil
  end
  local patched = pirate == true and design.patch == nil
  local ranked = if pirate == true and rank == 1 then Hull.looks.veteran elseif pirate == true and rank == 2 then Hull.looks.captain else nil
  local yard: Look = design.look or Hull.looks[design.faction] or Hull.looks.civil
  -- (what is lit on a hull that left the yard bare is lit as its builder's hulls are)
  local coat = if pirate then nil
    else coatOf(paint, figure, if yard.bare then Hull.looks[design.faction] or Hull.looks.civil else yard)
  local key = (if patched then type .. ":pirate" else type) .. (if ranked then `:{rank}` else "")
    .. (if coat then `:{paint}:{figure or ""}` else "")
  local made = built[key]
  if made then
    return made
  end
  local look = coat or ranked or (if patched then Hull.looks.unbound else yard)
  -- (its hardpoints, if they are where the building of it says)
  local place = design.place
  if place then
    design.turrets, design.launchers = place()
    design.place = nil
  end
  local b = Plates.New(#type * 1.37, design.fine, design.quality)
  -- (a bare hull is the generator's, and is made the size it made them)
  local grow = if look.bare then 1 / GROWN else 1
  b.bare, b.scale = look.bare, grow
  b.patch = if patched then PATCHED else design.patch
  -- (a pirate's is a patchwork whatever it was)
  b.even = if patched then nil else design.even
  table.clear(exhausts)
  design.draw(b)
  local model, lower, upper, meshes = Plates.Finish(b, look, design.sheets)
  local size = (upper - lower) / grow
  -- (a design has to have the hardpoints the game says the hull has)
  local hull = Ships.byId[type]
  assert(hull == nil or (#design.turrets == hull.turrets and #design.launchers == hull.launchers),
    `the design of {type} has {#design.turrets} turret and {#design.launchers} launcher mounts; the hull has {if hull then hull.turrets else 0} and {if hull then hull.launchers else 0}`)
  -- (and a hardpoint is two mounts that look away from each other)
  for _, points in { design.turrets, design.launchers } do
    for _, point in points do
      assert(#point == 2 and vector.dot(point[1].up, point[2].up) < -0.5,
        `a hardpoint of {type} is not a pair of mounts on opposite sides`)
    end
  end
  local radius = math.max(size.x, size.y, size.z) / 2
  assert(design.reach == nil or math.abs(design.reach - radius) < 0.03 * radius,
    `the design of {type} says it is drawn {design.reach} long each way, and it came out {radius}`)
  -- A hardpoint is never on a surface too small for what stands on it
  -- (the project owner's rule, 2026-11-11, for every ship): the whole
  -- foot of the weapon it is shown with (as far as its ring reaches
  -- while it turns) has to have hull under it, at the size the weapon
  -- really is beside this hull, and no farther under it than the
  -- ring's foundation goes down. (A pirate's patched
  -- copy, with guns bolted on beside the ones it was built for, is not
  -- held to it.)
  local hanging: { string } = {}
  if hull and not patched and not design.copied then
    local metres = hull.radius / radius
    local at = 0
    for kind, points in { design.turrets, design.launchers } do
      for _, point in points do
        at += 1
        local unit = Arms.SIZE[Arms.SizeOf(design.fit[at] or "")] / metres
        for index, mount in point do
          -- (a turret's ring turns with it; a launcher's rack stays as it is)
          local rests, off = Plates.Rests(b, mount.at, mount.up, mount.fore or v(0, 0, 1), Arms.REACH * unit, Arms.GAP * unit,
            if kind == 2 then Arms.FOOT * unit else nil)
          if not rests then
            table.insert(hanging, string.format("%s: hardpoint %d, mount %d at (%.3f, %.3f, %.3f), reach %.3f: %d of 17 places have no hull under them",
              type, at, index, mount.at.x, mount.at.y, mount.at.z, Arms.REACH * unit, off))
          end
        end
      end
    end
  end
  local result: Built = { model = model, radius = radius * grow, turrets = hardpointsOut(design.turrets, grow),
    launchers = hardpointsOut(design.launchers, grow), fit = design.fit, engines = exhaustsOut(grow), glow = look.fire or look.glow,
    lower = lower, upper = upper, hanging = hanging, meshes = meshes }
  built[key] = result
  return result
end

-- A hull as the engine's first generator grows one from a seed, in the
-- game's paint: for looking through what it makes (the viewer's
-- "grown-", and the hull browser, App/hulls). 'steps': how many plates it grows off its cross (it grew
-- four for a frigate and six for the biggest); 'decks': with the broad
-- flat plates under, as its bigger hulls had. No hardpoints, and no
-- engines.
function Hull.Grown(seed: number, steps: number, decks: boolean, paint: string?, style: string?, detail: Detail?): Built
  -- (in a faction's paint, if one is named: the civil blue-grey if not;
  -- bare, as the generator made it, if that is)
  local look = Hull.looks[paint or "civil"] or Hull.looks.civil
  local b = Plates.New(seed * 1.37, MANNER_FINE, if look.bare then BARE_QUALITY else nil)
  if look.bare then
    b.bare, b.scale = true, 1 / GROWN
  end
  table.clear(exhausts)
  local g = growth(seed, steps, decks, styleOf(style))
  grown(b, g)
  if detail then
    -- (with no hardpoints and no engines: as a cruiser, for the sizes of things)
    detailed(b, { growth = g, ends = {}, turrets = {}, launchers = {}, seats = {}, clear = {}, reach = 0 }, detail, 150)
  end
  local model, lower, upper, meshes = Plates.Finish(b, look, nil)
  local size = upper - lower
  return { model = model, radius = math.max(size.x, size.y, size.z) / 2, turrets = {}, launchers = {}, fit = {}, engines = {},
    glow = look.fire or look.glow, lower = lower, upper = upper, hanging = {}, meshes = meshes }
end

-- How far such a hull reaches across, up and down, and along, without
-- making it: to tell the broad ones from the long thin ones, which are
-- most of what the generator grows.
function Hull.GrownShape(seed: number, steps: number, decks: boolean, style: string?): vector
  return growth(seed, steps, decks, styleOf(style)).across
end

-- Such a hull as the engine made them: bare metal, with no paint, and
-- nothing lit. (Of the generator's own style it is plate for plate what
-- Item/ShipType/Generate makes.)
function Hull.GrownBare(seed: number, steps: number, decks: boolean, style: string?): Model
  local g = growth(seed, steps, decks, styleOf(style))
  local mesh = PlateMesh_Create(12)
  local zero = v(0, 0, 0)
  for _, plate in g.plates do
    PlateMesh_AddPlate(mesh, plate.center, plate.size, zero, g.style.eased)
    if not plate.single then
      PlateMesh_AddPlate(mesh, plate.center * v(-1, 1, 1), plate.size * 0.99, zero, g.style.eased)
    end
  end
  local bend = warped(g.warps, g.middle)
  PlateMesh_AddWarp(mesh, Warp_Custom({
    GetDelta = function(_, p: vector): vector
      -- (the bend is in a hull's units, and these plates in the generator's)
      return bend(p * GROWN) / GROWN - p
    end,
  }))
  local made = PlateMesh_GetMesh(mesh)
  Mesh_ComputeOcclusion(made)
  local model = Model_Create()
  Model_Add(model, made, Material_Metal())
  return model
end

-- A generated hull as a ship: 'metres' in radius, with engines on the
-- ends it has astern and what 'fit' names on so many turret and
-- launcher hardpoints, put where the rule of hardpoints allows. Nothing,
-- and why, if the hull has not the room for them.
function Hull.GrownShip(seed: number, steps: number, decks: boolean, paint: string?, metres: number, fit: { string }, turrets: number,
  launchers: number, engines: number, style: string?, detail: Detail?): (Built?, string)
  local ship, why = shipOf(growth(seed, steps, decks, styleOf(style)), metres, fit, turrets, launchers, engines)
  if ship == nil then
    return nil, why
  end
  -- (in a faction's paint, if one is named; bare, as the generator made
  -- it, if that is; the civil blue-grey if nothing is)
  local look = Hull.looks[paint or "civil"] or Hull.looks.civil
  local b = Plates.New(seed * 1.37, MANNER_FINE, if look.bare then BARE_QUALITY else nil)
  local grow = if look.bare then 1 / GROWN else 1
  b.bare, b.scale = look.bare, grow
  table.clear(exhausts)
  grown(b, ship.growth)
  seated(b, ship.seats)
  jets(b, ship.ends)
  if detail then
    detailed(b, ship, detail, metres)
  end
  local model, lower, upper, meshes = Plates.Finish(b, look, nil)
  local size = upper - lower
  return { model = model, radius = math.max(size.x, size.y, size.z) / 2, turrets = hardpointsOut(ship.turrets, grow),
    launchers = hardpointsOut(ship.launchers, grow), fit = fit,
    engines = exhaustsOut(grow), glow = look.fire or look.glow, lower = lower, upper = upper, hanging = {}, meshes = meshes }, ""
end

-- A built hull as it is drawn cloaked: its own shape, as light bending
-- round something that is not seen. Made once and kept.
local GHOST = vector.create(0.45, 0.75, 1.0)
function Hull.Ghost(made: Built): Model
  local ghost: Model = made.ghost or Plates.Ghost(made.meshes, GHOST, 0.42)
  made.ghost = ghost
  return ghost
end

-- Every design's mounts that are not wholly on its hull, in words: none,
-- when every hull is as it should be. (It builds every hull to find out.)
function Hull.Audit(): { string }
  local found: { string } = {}
  for _, type in Hull.Types() do
    local made = Hull.Build(type)
    if made then
      for _, line in made.hanging do
        table.insert(found, line)
      end
    end
  end
  return found
end

-- ---------------------------------------------------------------------
-- Wrecks

-- What is left of a ship nobody has designed: a length of spine with
-- some of its plating still on, a dead engine out on its strut, a tank.
local function debris(b: Builder)
  truss(b, v(0.02, 0.00, -0.88), v(-0.03, 0.04, 0.84), 0.26, 6)
  truss(b, v(0.02, 0.00, -0.88), v(-0.03, 0.04, 0.84), 0.24, 6, v(1, 0, 0))
  block(b, PLATING, v(0.02, 0.03, 0.30), v(0.26, 0.22, 0.34))
  block(b, PLATING, v(-0.03, -0.02, -0.42), v(0.22, 0.24, 0.24))
  block(b, PLATING, v(0.05, -0.05, 0.80), v(0.17, 0.15, 0.15))
  block(b, PATCH, v(0.29, 0.02, 0.22), v(0.020, 0.17, 0.26), v(0, 0, 0.12))
  block(b, PLATING, v(-0.27, 0.05, -0.32), v(0.020, 0.15, 0.20), v(0, 0, -0.10))
  block(b, PATCH, v(0.00, 0.27, 0.12), v(0.20, 0.020, 0.30), v(0, 0.06, 0))
  block(b, PLATING, v(-0.02, -0.27, -0.30), v(0.18, 0.020, 0.26))
  block(b, PATCH, v(0.10, 0.17, 0.74), v(0.09, 0.07, 0.13), nil, 0.14)
  nacelle(b, v(0.52, 0.08, -0.50), 0.30, 0.11)
  truss(b, v(0.22, 0.03, -0.44), v(0.42, 0.07, -0.46), 0.10, 2, v(0, 0, 1))
  tank(b, v(-0.34, -0.12, 0.06), 0.08, 0.20)
  conduit(b, { v(0.08, 0.29, 0.50), v(0.08, 0.29, -0.20), v(0.02, 0.26, -0.62) }, 0.013)
  mast(b, v(-0.06, 0.26, -0.36), 0.40, 0.03)
end

-- Paint after a fire: everything toward soot, the lights out, more rust.
local function charred(look: Look): Look
  local function soot(c: { number }, keep: number): { number }
    return { c[1] * keep + 0.015, c[2] * keep * 0.94 + 0.015, c[3] * keep * 0.88 + 0.015 }
  end
  return {
    plating = soot(look.plating, 0.30), patch = soot(look.patch, 0.26), frame = soot(look.frame, 0.60), glow = { 0, 0, 0 },
    trim = soot(look.trim, 0.36), wear = 0.45, rust = 1.0, sheets = look.sheets,
  }
end

-- The paint of a hull nobody has designed.
local PLAIN: Look = {
  plating = { 0.40, 0.38, 0.36 }, patch = { 0.48, 0.46, 0.43 }, frame = { 0.17, 0.17, 0.17 }, glow = { 0, 0, 0 },
  trim = { 0.34, 0.20, 0.12 }, wear = 0.75, rust = 0.5, sheets = 3.2,
}

-- What is adrift and is not the wreck of anything: it is drawn whole,
-- as it was left, and is no ship's hull (so it is not one of the
-- designs). A wreck says it is one by its 'hull' (Core/Tactical/Sites).

-- The Relay, a vault at a listening post: a squat drum in a cage of
-- girders, a lit band round it, a wide dish on a boom to one side with
-- its horn, and a stand of aerials on top.
local function relay(b: Builder)
  block(b, PLATING, v(0, 0, 0), v(0.34, 0.26, 0.34), nil, 0.45)
  block(b, GLOW, v(0, 0.06, 0), v(0.345, 0.02, 0.345), nil, 0.45)
  block(b, PATCH, v(0, 0.29, 0), v(0.22, 0.04, 0.22), nil, 0.3)
  block(b, PATCH, v(0, -0.29, 0), v(0.22, 0.04, 0.22), nil, 0.3)
  for _, x in { -1, 1 } do
    for _, z in { -1, 1 } do
      beam(b, FRAME, v(x * 0.40, -0.40, z * 0.40), v(x * 0.40, 0.40, z * 0.40), 0.03, 0.1)
    end
    beam(b, FRAME, v(x * 0.40, 0.40, -0.40), v(x * 0.40, 0.40, 0.40), 0.025, 0.1)
    beam(b, FRAME, v(x * 0.40, -0.40, -0.40), v(x * 0.40, -0.40, 0.40), 0.025, 0.1)
    beam(b, FRAME, v(-0.40, x * 0.40, x * 0.40), v(0.40, x * 0.40, x * 0.40), 0.025, 0.1)
    beam(b, FRAME, v(-0.40, x * 0.40, -x * 0.40), v(0.40, x * 0.40, -x * 0.40), 0.025, 0.1)
  end
  -- (the dish, out on its boom, and the horn it is fed from)
  beam(b, FRAME, v(0.34, 0, 0), v(0.78, 0.05, 0), 0.03, 0.1)
  block(b, PATCH, v(0.80, 0.05, 0), v(0.03, 0.30, 0.30), nil, 0.5)
  block(b, FRAME, v(0.84, 0.05, 0), v(0.012, 0.22, 0.22), nil, 0.5)
  beam(b, FRAME, v(0.86, 0.05, 0), v(1.0, 0.05, 0), 0.015, 0.1)
  aerials(b, v(-0.20, 0.33, -0.16), v(-0.20, 0.33, 0.16), 3, 0.50)
  aerial(b, v(0.10, -0.33, 0.05), 0.36, v(0, -1, 0))
end

local adrift: { [string]: (b: Builder) -> () } = { relay = relay }

-- A ship in pieces: the model of each, the middle of each in the
-- ship's own units (a piece turns about its middle as the wreck drifts
-- apart), and the radius the whole ship had in those units.
export type Wreckage = { pieces: { { model: Model, middle: vector } }, radius: number }

local wrecks: { [string]: Wreckage } = {}

-- The wreck of a hull type: the hull itself, as designed, broken across
-- in two or three (three for a big one), with plates gone, the rest
-- knocked about and burnt, and nothing lit. A hull without a design
-- (and "", for a wreck that does not say what it was) leaves plain
-- wreckage. Made once for each type and kept.
function Hull.Wreck(type: string): Wreckage
  local made = wrecks[type]
  if made then
    return made
  end
  local left = adrift[type]
  if left then
    -- (in one piece, as it was left: unburnt and unbroken, and lit)
    local b = Plates.New(#type * 1.37)
    left(b)
    local model, a, c = Plates.Finish(b, Hull.looks.unbound, nil)
    table.clear(exhausts)
    local size = c - a
    local result: Wreckage = { pieces = { { model = model, middle = (a + c) / 2 } }, radius = math.max(size.x, size.y, size.z) / 2 }
    wrecks[type] = result
    return result
  end
  local design = designOf(type)
  local whole = Hull.Build(type)
  local draw: (b: Builder) -> () = if design then design.draw else debris
  local look = charred(if design then design.look or Hull.looks[design.faction] else PLAIN)
  local lower, upper = if whole then whole.lower.z else -1.0, if whole then whole.upper.z else 1.0
  local hull = Ships.byId[type]
  local breaks: { number } = if hull and hull.radius >= 100 then { 0.36, 0.69 } else { 0.47 }
  local edges: { number } = { -math.huge }
  for _, at in breaks do
    table.insert(edges, lower + (upper - lower) * at)
  end
  table.insert(edges, math.huge)

  local pieces: { { model: Model, middle: vector } } = {}
  local low: vector? = nil
  local high: vector? = nil
  for index = 1, #edges - 1 do
    -- (the seed the whole hull was built with: the same plates, in the same tones)
    local b = Plates.New(#type * 1.37, if design then design.fine else nil)
    b.patch = if design then design.patch else nil
    b.even = if design then design.even else nil
    b.ruin = { from = edges[index], to = edges[index + 1], loss = 0.42 }
    draw(b)
    if b.kept >= 4 then
      local model, a, c = Plates.Finish(b, look, if design then design.sheets else nil)
      table.insert(pieces, { model = model, middle = (a + c) / 2 })
      low = if low then vector.min(low, a) else a
      high = if high then vector.max(high, c) else c
    end
  end
  table.clear(exhausts)
  local radius = if whole then whole.radius
    elseif low and high then math.max(high.x - low.x, high.y - low.y, high.z - low.z) / 2
    else 1
  local result: Wreckage = { pieces = pieces, radius = radius }
  wrecks[type] = result
  return result
end

-- Draw a hull of the game's from a seed from now on (what is already in
-- the scene stays as it is until it is made again; a pirate's copy and
-- a tech 2 make of it are not changed: resource/hull/seeds.txt, read
-- when the game starts, does it for them too). False, and why, if there
-- is no such hull or the seed has not the room for its hardpoints.
function Hull.Seed(type: string, seed: number, size: number, style: string?, painted: boolean?, detail: Detail?): (boolean, string)
  local design, why = seeded(type, math.floor(seed), size, style, painted, detail)
  if design == nil then
    return false, why
  end
  designs[type] = design
  pending[type] = nil
  for key in built do
    if key == type or string.sub(key, 1, #type + 1) == type .. ":" then
      built[key] = nil
    end
  end
  wrecks[type] = nil
  return true, ""
end

return Hull
