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
    plating = { 0.56, 0.58, 0.60 }, patch = { 0.40, 0.46, 0.54 }, frame = { 0.20, 0.22, 0.26 },
    glow = { 0.55, 0.80, 1.0 }, trim = { 0.14, 0.27, 0.50 }, wear = 0.22, rust = 0.05, sheets = 3.0,
  },
  -- The pirates: whatever paint was on it, gone dark, the new plate
  -- bare, a red light.
  unbound = {
    plating = { 0.25, 0.19, 0.16 }, patch = { 0.50, 0.48, 0.44 }, frame = { 0.13, 0.12, 0.12 },
    glow = { 1.0, 0.25, 0.10 }, trim = { 0.50, 0.08, 0.05 }, wear = 0.85, rust = 0.85, sheets = 3.2,
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
-- grown, not built and not blown up: the first drawings were a few
-- smooth fat lobes, and "too blimp-y, and not organic growth". So a
-- Talmar hull is a body that swells and narrows along its length, with
-- pods of every size swelling out of it in turn, the same on both
-- sides (they are symmetrical, the owner again); round engines in a
-- cluster at the stern; and, theirs being a theocracy, a dome and
-- slender spires on the larger ones. (All v0s.)

-- A lobe: a rounded mass.
local function lobe(b: Builder, part: number, center: vector, half: vector, turn: vector?)
  block(b, part, center, half, turn, 0.92)
end

-- A number from 0 to 1 that follows from 'n'.
local function chance(n: number): number
  return (math.sin(n * 12.9898) * 43758.5453) % 1
end

-- The outline of a body, from stern to bow: at each place along z, half
-- its width and half its height there, and how high its middle is (0
-- if not said).
type Outline = { { number } }

-- Half the width and height of an outline at 'z', and its middle's height.
local function girth(outline: Outline, z: number): (number, number, number)
  for index = 1, #outline - 1 do
    local a, c = outline[index], outline[index + 1]
    if z <= c[1] or index == #outline - 1 then
      local t = math.clamp((z - a[1]) / (c[1] - a[1]), 0, 1)
      return a[2] + (c[2] - a[2]) * t, a[3] + (c[3] - a[3]) * t, (a[4] or 0) + ((c[4] or 0) - (a[4] or 0)) * t
    end
  end
  return outline[1][2], outline[1][3], outline[1][4] or 0
end

-- A grown body: lobes run together along an outline, so that it swells
-- and narrows as it goes. With 'x' it is two bodies, one that far to
-- each side; 'y' lifts it.
local function grown(b: Builder, part: number, outline: Outline, x: number?, y: number?)
  for index, at in outline do
    local before = if index > 1 then at[1] - outline[index - 1][1] else outline[2][1] - at[1]
    local after = if index < #outline then outline[index + 1][1] - at[1] else before
    local long = math.max(math.max(before, after) * 0.85, math.min(at[2], at[3]) * 0.7)
    local skin = if index % 3 == 0 then PATCH else part
    local center = v(x or 0, (at[4] or 0) + (y or 0), at[1])
    lobe(b, skin, center, v(at[2], at[3], long))
    if x and x ~= 0 then
      lobe(b, skin, v(-center.x, center.y, center.z), v(at[2], at[3], long))
    end
  end
end

-- Growths: 'count' pods swelling out of a body's skin anywhere along
-- its outline, a few of them big and most small ('size' is the middling
-- one), each lying along the body and flat to it. What grows on one
-- side grows on the other; what grows on the back or the keel grows on
-- the middle line. ('x' and 'y' as for the body they are on.)
local function growths(b: Builder, outline: Outline, count: number, size: number, seed: number, x: number?, y: number?)
  local first, last = outline[1][1], outline[#outline][1]
  local aside = x or 0
  for index = 1, count do
    local n = seed * 17.3 + index * 3.1
    local z = first + (last - first) * (0.06 + 0.86 * chance(n))
    local w, h, middle = girth(outline, z)
    -- (a body on the middle line grows them from keel round one side to
    -- its back; one out to the side, all the way round)
    local around = if aside == 0 then (chance(n + 0.37) - 0.5) * math.pi else chance(n + 0.37) * 2 * math.pi
    local big = size * (0.45 + 1.9 * chance(n + 0.71) ^ 3)
    local half = v(big * 0.62, big * 0.36, big * (1.3 + 1.6 * chance(n + 0.13)))
    local skin = if index % 3 == 0 then PATCH else PLATING
    local out = v(math.cos(around), math.sin(around), 0)
    local at = v(aside + out.x * w * 0.93, middle + (y or 0) + out.y * h * 0.93, z)
    if aside == 0 and math.abs(out.x) * w < big * 0.5 then
      lobe(b, skin, v(0, at.y, z), half)
    else
      lobe(b, skin, at, half, v(0, 0, around - math.pi / 2))
      lobe(b, skin, v(-at.x, at.y, z), half, v(0, 0, math.pi / 2 - around))
    end
  end
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

-- The Rapier, a frigate: a teardrop, grown over, with a hump for its
-- bridge and three engines.
local RAPIER: Outline = { { -0.58, 0.15, 0.12 }, { -0.28, 0.24, 0.18 }, { 0.08, 0.27, 0.20 }, { 0.44, 0.21, 0.16 }, { 0.78, 0.13, 0.10 }, { 1.00, 0.06, 0.05 } }
local function rapier(b: Builder)
  grown(b, PLATING, RAPIER)
  growths(b, RAPIER, 14, 0.10, 1)
  growths(b, RAPIER, 12, 0.045, 2)
  lobe(b, PATCH, v(0, 0.18, 0.10), v(0.12, 0.09, 0.24))
  block(b, GLOW, v(0, 0.21, 0.33), v(0.08, 0.02, 0.012), nil, 0.6)
  thruster(b, v(0, 0.02, -0.72), 0.20, 0.10)
  for _, side in { -1, 1 } do
    thruster(b, v(side * 0.17, -0.03, -0.66), 0.16, 0.075)
    ports(b, v(side * 0.262, 0.07, -0.20), v(side * 0.262, 0.07, 0.20), 4, 0.010)
  end
end

-- The Sabre, a destroyer: a long body that swells twice along its
-- length, with a pontoon grown out on a neck each side.
local SABRE: Outline = { { -1.10, 0.14, 0.12 }, { -0.80, 0.21, 0.18 }, { -0.45, 0.17, 0.15 }, { -0.05, 0.24, 0.20 }, { 0.35, 0.22, 0.18 },
  { 0.70, 0.15, 0.13 }, { 1.00, 0.17, 0.14 }, { 1.28, 0.10, 0.08 }, { 1.44, 0.05, 0.04 } }
local SABRE_PONTOON: Outline = { { -0.70, 0.07, 0.065 }, { -0.30, 0.09, 0.08 }, { 0.15, 0.085, 0.075 }, { 0.50, 0.05, 0.045 } }
local function sabre(b: Builder)
  grown(b, PLATING, SABRE)
  growths(b, SABRE, 18, 0.09, 3)
  growths(b, SABRE, 14, 0.04, 4)
  grown(b, PLATING, SABRE_PONTOON, 0.36, -0.06)
  growths(b, SABRE_PONTOON, 6, 0.04, 5, 0.36, -0.06)
  lobe(b, PATCH, v(0, 0.20, 0.20), v(0.10, 0.07, 0.18))
  block(b, GLOW, v(0, 0.22, 0.37), v(0.065, 0.018, 0.010), nil, 0.6)
  for _, side in { -1, 1 } do
    lobe(b, PLATING, v(side * 0.27, -0.04, 0.12), v(0.07, 0.05, 0.09))
    lobe(b, PLATING, v(side * 0.27, -0.04, -0.42), v(0.07, 0.05, 0.09))
    thruster(b, v(side * 0.36, -0.06, -0.84), 0.12, 0.06)
    thruster(b, v(side * 0.10, 0.0, -1.22), 0.16, 0.085)
    ports(b, v(side * 0.243, 0.06, -0.22), v(side * 0.243, 0.06, 0.30), 5, 0.010)
  end
end

-- The Falchion, a cruiser: a great body with a wing grown out and
-- swept back each side, a domed sanctuary on its back with a spire,
-- and six engines.
local FALCHION: Outline = { { -1.00, 0.24, 0.18 }, { -0.60, 0.33, 0.24 }, { -0.10, 0.37, 0.27 }, { 0.40, 0.34, 0.25 }, { 0.85, 0.26, 0.20 },
  { 1.25, 0.18, 0.14 }, { 1.58, 0.09, 0.07 } }
local FALCHION_WING: Outline = { { -0.85, 0.13, 0.07 }, { -0.50, 0.24, 0.10 }, { -0.10, 0.22, 0.10 }, { 0.25, 0.12, 0.07 } }
local function falchion(b: Builder)
  grown(b, PLATING, FALCHION)
  growths(b, FALCHION, 24, 0.12, 6)
  growths(b, FALCHION, 20, 0.05, 7)
  grown(b, PLATING, FALCHION_WING, 0.52, -0.04)
  growths(b, FALCHION_WING, 8, 0.06, 8, 0.52, -0.04)
  lobe(b, PATCH, v(0, 0.30, -0.15), v(0.20, 0.13, 0.28))
  block(b, GLOW, v(0, 0.32, 0.12), v(0.13, 0.022, 0.012), nil, 0.6)
  block(b, TRIM, v(0, 0.285, -0.15), v(0.205, 0.012, 0.285), nil, 0.9)
  spire(b, v(0, 0.41, -0.22), 0.60, 0.022)
  for _, side in { -1, 1 } do
    thruster(b, v(side * 0.15, 0.09, -1.14), 0.20, 0.10)
    thruster(b, v(side * 0.16, -0.10, -1.12), 0.18, 0.09)
    thruster(b, v(side * 0.52, -0.04, -0.98), 0.12, 0.06)
    ports(b, v(side * 0.368, 0.09, -0.40), v(side * 0.368, 0.09, 0.50), 9, 0.011)
  end
end

-- The Claymore, a battleship: a cathedral in a cloud, with a sword for
-- a prow. A great body with a lesser one grown along each flank, a
-- keel under it and a second tier on its back, all grown over; on the
-- tier a dome with blisters ringing it like a halo, and three spires;
-- six engines. Its bow narrows and flattens into a long blade, flat and
-- level, that runs out ahead of it to a point. (The blade at the
-- project owner's word, in place of a nose that "looks like a blimp";
-- and it has no guard across it: that was drawn, and taken off again
-- at the same word.)
local CLAYMORE: Outline = { { -2.00, 0.30, 0.24 }, { -1.50, 0.44, 0.33 }, { -0.80, 0.50, 0.37 }, { 0.00, 0.50, 0.36 }, { 0.80, 0.44, 0.32 },
  { 1.45, 0.38, 0.22 }, { 1.95, 0.40, 0.12 } }
local CLAYMORE_FLANK: Outline = { { -1.50, 0.18, 0.14 }, { -1.00, 0.28, 0.21 }, { -0.30, 0.30, 0.22 }, { 0.40, 0.24, 0.18 }, { 0.90, 0.13, 0.10 } }
local CLAYMORE_TIER: Outline = { { -1.30, 0.22, 0.14 }, { -0.80, 0.32, 0.21 }, { -0.30, 0.33, 0.22 }, { 0.20, 0.26, 0.17 }, { 0.55, 0.14, 0.10 } }
local CLAYMORE_KEEL: Outline = { { -0.60, 0.16, 0.10 }, { -0.10, 0.25, 0.16 }, { 0.50, 0.24, 0.15 }, { 1.00, 0.14, 0.09 } }
local function claymore(b: Builder)
  grown(b, PLATING, CLAYMORE)
  growths(b, CLAYMORE, 34, 0.16, 10)
  growths(b, CLAYMORE, 30, 0.06, 11)
  grown(b, PLATING, CLAYMORE_FLANK, 0.62, -0.10)
  growths(b, CLAYMORE_FLANK, 12, 0.09, 12, 0.62, -0.10)
  grown(b, PATCH, CLAYMORE_TIER, 0, 0.40)
  growths(b, CLAYMORE_TIER, 10, 0.07, 13, 0, 0.40)
  grown(b, PLATING, CLAYMORE_KEEL, 0, -0.40)
  growths(b, CLAYMORE_KEEL, 6, 0.06, 14, 0, -0.40)
  -- the blade, in three lengths, each narrower and thinner, and a ridge
  -- down the middle of it above and below
  lobe(b, PLATING, v(0, -0.02, 2.55), v(0.50, 0.075, 0.86))
  lobe(b, PATCH, v(0, -0.02, 3.42), v(0.38, 0.058, 0.72))
  lobe(b, PLATING, v(0, -0.02, 4.10), v(0.22, 0.042, 0.52))
  lobe(b, TRIM, v(0, 0.045, 3.10), v(0.055, 0.032, 1.30))
  lobe(b, TRIM, v(0, -0.085, 3.10), v(0.055, 0.032, 1.30))
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
    thruster(b, v(side * 0.22, 0.12, -2.14), 0.26, 0.14)
    thruster(b, v(side * 0.24, -0.16, -2.10), 0.24, 0.13)
    thruster(b, v(side * 0.62, -0.10, -1.66), 0.22, 0.12)
    ports(b, v(side * 0.925, -0.04, -0.90), v(side * 0.925, -0.04, 0.10), 10, 0.012)
    ports(b, v(side * 0.335, 0.47, -0.80), v(side * 0.335, 0.47, -0.10), 8, 0.012)
  end
end

-- The Packet, a hauler, as a packet boat is: a slim hull that carries
-- its parcels where they can be seen. A slender grown spine with the
-- bridge at its bow and the engines at its stern, and under it, in a
-- row, four cargo sacs, each hung by a neck and grown over like the
-- rest of it. (The third drawing. The first was a heap of fat lobes,
-- and ugly; the second had this plan, which was liked, but its cargo
-- was four smooth balls and it was "too blimp-y".)
local PACKET: Outline = { { -1.05, 0.10, 0.09, 0.30 }, { -0.60, 0.15, 0.12, 0.30 }, { 0.00, 0.17, 0.13, 0.30 }, { 0.60, 0.15, 0.12, 0.30 },
  { 1.05, 0.10, 0.085, 0.29 }, { 1.32, 0.05, 0.045, 0.28 } }
local function packet(b: Builder)
  grown(b, PLATING, PACKET)
  growths(b, PACKET, 12, 0.06, 21)
  lobe(b, PATCH, v(0, 0.41, 0.78), v(0.10, 0.065, 0.19))
  block(b, GLOW, v(0, 0.425, 0.965), v(0.065, 0.018, 0.010), nil, 0.6)
  for index, z in { 0.74, 0.25, -0.24, -0.73 } do
    -- (no two quite the same size)
    local swell = 1 + 0.10 * (if index % 2 == 0 then 1 else -1)
    local sac: Outline = { { z - 0.17, 0.17 * swell, 0.16 * swell, -0.13 }, { z, 0.25 * swell, 0.23 * swell, -0.13 },
      { z + 0.17, 0.17 * swell, 0.16 * swell, -0.13 } }
    grown(b, if index % 2 == 0 then PATCH else PLATING, sac)
    growths(b, sac, 7, 0.085, 30 + index)
    growths(b, sac, 5, 0.04, 40 + index)
    lobe(b, PLATING, v(0, 0.15, z), v(0.07, 0.07, 0.09))
  end
  for _, side in { -1, 1 } do
    thruster(b, v(side * 0.11, 0.31, -1.12), 0.17, 0.085)
    ports(b, v(side * 0.165, 0.32, -0.40), v(side * 0.165, 0.32, 0.40), 6, 0.010)
  end
  thruster(b, v(0, 0.12, -1.06), 0.12, 0.06)
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
  -- middle line.)
  ["frigate.harrier"] = {
    faction = "talmar", draw = rapier,
    turrets = { abeam(v(0.27, 0.0, 0.08), v(-0.27, 0.0, 0.08)), over(v(0, 0.27, 0.10), v(0, -0.20, 0.08)) },
    launchers = { abeam(v(0.235, 0.0, -0.30), v(-0.235, 0.0, -0.30)), over(v(0, 0.16, 0.46), v(0, -0.17, -0.28)) },
    fit = { "autocannon.small", "autocannon.small", "launcher.light", "launcher.light" },
  },
  ["destroyer.sabre"] = {
    faction = "talmar", draw = sabre, sheets = 3.5,
    turrets = {
      over(v(0, 0.20, -0.05), v(0, -0.20, -0.05)), over(v(0, 0.18, -0.80), v(0, -0.18, -0.80)),
      abeam(v(0.445, -0.06, 0.15), v(-0.445, -0.06, 0.15)), abeam(v(0.45, -0.06, -0.30), v(-0.45, -0.06, -0.30)),
    },
    launchers = { over(v(0, 0.14, 1.00), v(0, -0.14, 1.00)), over(v(0, 0.17, 0.60), v(0, -0.17, 0.42)) },
    fit = { "autocannon.small", "autocannon.small", "autocannon.small", "autocannon.small", "launcher.light", "launcher.light" },
  },
  ["cruiser.falchion"] = {
    faction = "talmar", draw = falchion, sheets = 4.5,
    turrets = {
      over(v(0, 0.25, 0.42), v(0, -0.25, 0.40)), abeam(v(0.76, -0.04, -0.50), v(-0.76, -0.04, -0.50)),
      over(v(0, 0.22, -0.72), v(0, -0.23, -0.66)),
    },
    launchers = { over(v(0, 0.43, -0.15), v(0, -0.27, -0.10)) },
    fit = { "autocannon.medium", "autocannon.medium", "autocannon.medium", "launcher.heavy" },
  },
  ["battleship.claymore"] = {
    faction = "talmar", draw = claymore, sheets = 7.0,
    turrets = {
      over(v(0, 0.28, 1.20), v(0, -0.28, 1.20)), abeam(v(0.92, -0.10, -0.30), v(-0.92, -0.10, -0.30)),
      abeam(v(0.90, -0.10, -1.00), v(-0.90, -0.10, -1.00)), over(v(0, 0.62, -0.10), v(0, -0.56, 0.20)),
      over(v(0, 0.29, -1.72), v(0, -0.29, -1.72)),
    },
    launchers = { abeam(v(0.40, 0.0, 1.25), v(-0.40, 0.0, 1.25)), over(v(0, 0.59, -1.05), v(0, -0.37, -0.90)) },
    fit = { "artillery.large", "artillery.large", "artillery.large", "artillery.large", "artillery.large", "launcher.cruise", "launcher.cruise" },
  },
  ["industrial.packet"] = {
    faction = "talmar", draw = packet, sheets = 3.5,
    -- (its one gun on the spine's back, and under a cargo sac)
    turrets = { over(v(0, 0.43, 0.0), v(0, -0.36, 0.25)) },
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
