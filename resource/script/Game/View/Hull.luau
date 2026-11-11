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
-- showing, heavy armour, missiles, engines out on struts; in the manner
-- of EVE's Minmatar without being any ship of theirs): a spine of bare
-- girders with armoured boxes hung on it, nothing quite symmetrical,
-- plates of two colours where repairs have been made, tanks strapped on
-- outside, masts and fins, and rust.

local Plates = require("@lt/Game/View/Plates")
local Ships = require("@lt/Core/Data/Ships")

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
  -- The pirates: whatever paint was on it, gone dark, the new plate
  -- bare, a red light.
  unbound = {
    plating = { 0.25, 0.19, 0.16 }, patch = { 0.50, 0.48, 0.44 }, frame = { 0.13, 0.12, 0.12 },
    glow = { 1.0, 0.25, 0.10 }, trim = { 0.50, 0.08, 0.05 }, wear = 0.85, rust = 0.85, sheets = 3.2, mottle = 1.0,
  },
  -- Hulls no faction owns: plain blue-grey, a yellow stripe, a cold light.
  civil = {
    plating = { 0.40, 0.44, 0.48 }, patch = { 0.62, 0.62, 0.58 }, frame = { 0.16, 0.16, 0.17 },
    glow = { 0.70, 0.90, 1.0 }, trim = { 0.74, 0.52, 0.10 }, wear = 0.40, rust = 0.20, sheets = 3.2,
  },
} :: { [string]: Look }

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

-- A mount: a place on the hull where a weapon can stand. Where it is,
-- the way out of the hull there, and the way what stands on it faces at
-- rest (forward, if not said).
export type Mount = { at: vector, up: vector, fore: vector? }

-- A hardpoint is a pair of mounts on opposite sides of the hull, as in
-- EVE (the project owner's note): whichever way the ship is heading,
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

type Design = {
  faction: string,
  draw: (b: Builder) -> (),
  -- (A pirate hull is somebody else's design, patched: Plates' 'patch'.)
  patch: number?,
  -- (A bigger ship is plated in more and smaller sheets for its size:
  -- it is one of the things that says how big it is.)
  sheets: number?,
  turrets: { Hardpoint },
  launchers: { Hardpoint },
  -- What it is shown carrying where nobody has fitted it (a gallery):
  -- turrets, then launchers, in the order of its hardpoints.
  fit: { string },
}

local designs: { [string]: Design } = {
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
    turrets = { over(v(-0.06, 0.32, 0.30), v(0.00, -0.24, 0.10)), over(v(0.12, 0.28, -0.72), v(-0.10, -0.16, -0.78)) },
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
      over(on(RAPIER_BRIDGE, 0.02, BACK, 0, 0.17), on(RAPIER, 0.08, KEEL)),
    },
    launchers = {
      abeam(on(RAPIER, -0.30, STARBOARD_SIDE), on(RAPIER, -0.30, PORT_SIDE)),
      over(on(RAPIER, 0.52, BACK), on(RAPIER, -0.28, KEEL)),
    },
    fit = { "autocannon.small", "autocannon.small", "launcher.light", "launcher.light" },
  },
  ["destroyer.sabre"] = {
    faction = "talmar", draw = sabre, sheets = 6.0,
    turrets = {
      over(on(SABRE, -0.05, BACK), on(SABRE, -0.05, KEEL)), over(on(SABRE, -0.85, BACK), on(SABRE, -0.85, KEEL)),
      abeam(on(SABRE_PONTOON, 0.10, STARBOARD_SIDE, 0.36, -0.06), on(SABRE_PONTOON, 0.10, PORT_SIDE, -0.36, -0.06)),
      abeam(on(SABRE_PONTOON, -0.38, STARBOARD_SIDE, 0.36, -0.06), on(SABRE_PONTOON, -0.38, PORT_SIDE, -0.36, -0.06)),
    },
    launchers = { over(on(SABRE, 1.05, BACK), on(SABRE, 1.05, KEEL)), over(on(SABRE, 0.62, BACK), on(SABRE, 0.45, KEEL)) },
    fit = { "autocannon.small", "autocannon.small", "autocannon.small", "autocannon.small", "launcher.light", "launcher.light" },
  },
  ["cruiser.falchion"] = {
    faction = "talmar", draw = falchion, sheets = 7.0,
    turrets = {
      over(on(FALCHION, 0.65, BACK), on(FALCHION, 0.60, KEEL)),
      abeam(on(FALCHION_WING, -0.30, STARBOARD_SIDE, 0.50, -0.04), on(FALCHION_WING, -0.30, PORT_SIDE, -0.50, -0.04)),
      over(on(FALCHION, -0.82, BACK), on(FALCHION, -0.80, KEEL)),
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
      over(on(CLAYMORE, -1.72, BACK), on(CLAYMORE, -1.72, KEEL)),
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
  ["frigate.courier"] = {
    faction = "civil", draw = courier,
    -- (a gun on the back and under the cargo box; a gun on each flank)
    turrets = { over(v(0, 0.235, 0.36), v(0, -0.40, 0.10)), abeam(v(0.24, 0.04, -0.06), v(-0.24, 0.04, -0.06)) },
    launchers = {},
    fit = { "autocannon.small", "autocannon.small" },
  },
}

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
      local derived: Design = { faction = "unbound", draw = base.draw, patch = PATCHED, sheets = base.sheets, turrets = {}, launchers = {}, fit = {} }
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

-- ---------------------------------------------------------------------

export type Built = {
  model: Model,
  radius: number,       -- half the longest way across it, in its own units
  turrets: { Hardpoint },   -- its hardpoints, in its own units
  launchers: { Hardpoint },
  fit: { string },
  engines: { Exhaust }, -- where its engines' fire leaves it
  glow: { number },     -- and the colour of that fire
  lower: vector,        -- the corners of the box it fills
  upper: vector,
}

local built: { [string]: Built } = {}

-- Whether there is a design for a hull type.
function Hull.Has(type: string): boolean
  return designs[type] ~= nil
end

-- The types there are designs for.
function Hull.Types(): { string }
  local out: { string } = {}
  for type in designs do
    table.insert(out, type)
  end
  table.sort(out)
  return out
end

-- The model of a hull type and how big it came out, or nil if nobody
-- has designed it. Made once and kept. 'pirate' asks for the hull as a
-- pirate flies it, whoever built it: patched, and in their paint (a
-- pirate hull is that anyway).
function Hull.Build(type: string, pirate: boolean?): Built?
  local design = designs[type]
  if design == nil then
    return nil
  end
  local patched = pirate == true and design.patch == nil
  local key = if patched then type .. ":pirate" else type
  local made = built[key]
  if made then
    return made
  end
  local look = Hull.looks[if patched then "unbound" else design.faction]
  local b = Plates.New(#type * 1.37)
  b.patch = if patched then PATCHED else design.patch
  table.clear(exhausts)
  design.draw(b)
  local model, lower, upper = Plates.Finish(b, look, design.sheets)
  local size = upper - lower
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
  local result: Built = { model = model, radius = math.max(size.x, size.y, size.z) / 2, turrets = design.turrets,
    launchers = design.launchers, fit = design.fit, engines = table.clone(exhausts), glow = look.glow,
    lower = lower, upper = upper }
  built[key] = result
  return result
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
  local design = designs[type]
  local whole = Hull.Build(type)
  local draw: (b: Builder) -> () = if design then design.draw else debris
  local look = charred(if design then Hull.looks[design.faction] else PLAIN)
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
    local b = Plates.New(#type * 1.37)
    b.patch = if design then design.patch else nil
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

return Hull
