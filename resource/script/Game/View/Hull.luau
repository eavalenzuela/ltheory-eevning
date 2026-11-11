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

local Hull = {}

-- The parts a plate can be: the whole number of its tag.
local PLATING, PATCH, FRAME, GLOW, TRIM = 0, 1, 2, 3, 4

-- How a faction's hulls are painted and how worn they are.
export type Look = {
  plating: { number },
  patch: { number },
  frame: { number },
  glow: { number },
  trim: { number },
  wear: number,
  rust: number,
  sheets: number,       -- sheets of plating to a unit of the hull
}

Hull.looks = {
  vessari = {
    plating = { 0.52, 0.31, 0.16 }, patch = { 0.56, 0.52, 0.43 }, frame = { 0.17, 0.16, 0.16 },
    glow = { 1.0, 0.72, 0.32 }, trim = { 0.46, 0.12, 0.07 }, wear = 0.65, rust = 0.65, sheets = 3.2,
  },
} :: { [string]: Look }

type Builder = {
  big: PlateMesh,       -- plates with room for a fine bevel
  small: PlateMesh,     -- beams, pipes, fittings
  count: number,
  seed: number,
}

local ZERO = vector.create(0, 0, 0)

local function v(x: number, y: number, z: number): vector
  return vector.create(x, y, z)
end

-- The next plate's own number: the fraction of its tag.
local function own(b: Builder): number
  b.count += 1
  return ((math.sin(b.count * 12.9898 + b.seed) * 43758.5453) % 1) * 0.97
end

-- A box: where its middle is, half its size each way, and optionally
-- how it is turned (yaw, pitch, roll) and how far its edges are eased.
local function block(b: Builder, part: number, center: vector, half: vector, turn: vector?, bevel: number?)
  local mesh = if math.max(half.x, half.y, half.z) > 0.11 and math.min(half.x, half.y, half.z) > 0.012 then b.big else b.small
  PlateMesh_AddTagged(mesh, center, half, turn or ZERO, bevel or 0.10, part + own(b))
end

-- A bar from one point to another, 'thick' to a side.
local function beam(b: Builder, part: number, from: vector, to: vector, thick: number, bevel: number?)
  local d = to - from
  local length = vector.magnitude(d)
  if length < 1e-4 then
    return
  end
  d /= length
  local turn = v(math.atan2(d.x, d.z), -math.asin(math.clamp(d.y, -1, 1)), 0)
  PlateMesh_AddTagged(b.small, (from + to) / 2, v(thick, thick, length / 2), turn, bevel or 0.15, part + own(b))
end

-- A girder of open lattice between two points: two rails 'width' apart
-- (sideways if 'across' is given, else up and down), cross-braced.
local function truss(b: Builder, from: vector, to: vector, width: number, bays: number, across: vector?)
  local side = (across or v(0, 1, 0)) * (width / 2)
  local thick = width * 0.11
  beam(b, FRAME, from + side, to + side, thick)
  beam(b, FRAME, from - side, to - side, thick)
  for bay = 0, bays do
    local at = from + (to - from) * (bay / bays)
    beam(b, FRAME, at + side, at - side, thick * 0.8)
    if bay < bays then
      local next = from + (to - from) * ((bay + 1) / bays)
      if bay % 2 == 0 then
        beam(b, FRAME, at + side, next - side, thick * 0.7)
      else
        beam(b, FRAME, at - side, next + side, thick * 0.7)
      end
    end
  end
end

-- A pipe run through a list of points.
local function conduit(b: Builder, points: { vector }, thick: number)
  for index = 1, #points - 1 do
    beam(b, FRAME, points[index], points[index + 1], thick, 0.45)
  end
end

-- An engine pod, faceted (two boxes, one turned an eighth), with an
-- intake collar, a strap, and a lit throat at the back. 'length' and
-- 'radius' are half-sizes.
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

-- A missile rack: a box of tubes, its mouths showing at the front, with
-- a band of trim.
local function rack(b: Builder, center: vector, half: vector, columns: number, rows: number)
  block(b, PLATING, center, half, nil, 0.08)
  block(b, TRIM, center + v(0, 0, -half.z * 0.3), v(half.x * 1.04, half.y * 1.04, half.z * 0.12), nil, 0.1)
  block(b, FRAME, center + v(0, 0, half.z), v(half.x * 0.92, half.y * 0.92, half.z * 0.05), nil, 0.1)
  for column = 1, columns do
    for row = 1, rows do
      local x = (column - (columns + 1) / 2) * (1.7 * half.x / columns)
      local y = (row - (rows + 1) / 2) * (1.7 * half.y / rows)
      block(b, FRAME, center + v(x, y, half.z * 1.06), v(0.62 * half.x / columns, 0.62 * half.y / rows, half.z * 0.05), nil, 0.5)
    end
  end
end

-- A row of lit ports along z.
local function ports(b: Builder, from: vector, to: vector, count: number, size: number)
  for index = 1, count do
    block(b, GLOW, from + (to - from) * ((index - 0.5) / count), v(size * 0.25, size, size * 1.6), nil, 0.3)
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

  -- missiles: a rack slung under the port bow, another on the starboard flank
  rack(b, v(-0.20, -0.20, 0.80), v(0.085, 0.065, 0.24), 2, 2)
  beam(b, FRAME, v(-0.20, -0.13, 0.70), v(-0.10, -0.03, 0.70), 0.014)
  beam(b, FRAME, v(-0.20, -0.13, 0.92), v(-0.10, -0.03, 0.92), 0.014)
  rack(b, v(0.36, 0.14, 0.34), v(0.055, 0.075, 0.20), 1, 3)

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
  -- starboard: a mast, and a slab of plate over the middle bay
  mast(b, v(0.20, high, -0.50), 0.55, 0.04)
  block(b, PLATING, v(0.47, 0.02, stern + length * 1.5), v(0.018, 0.30, length * 0.36), v(0, 0, -0.29), 0.06)
end

local designs: { [string]: { faction: string, draw: (b: Builder) -> () } } = {
  ["frigate.javelin"] = { faction = "vessari", draw = javelin },
  ["industrial.caravan"] = { faction = "vessari", draw = caravan },
}

-- ---------------------------------------------------------------------

export type Built = {
  model: Model,
  radius: number,       -- half the longest way across it, in its own units
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
-- has designed it. Made once and kept.
function Hull.Build(type: string): Built?
  local made = built[type]
  if made then
    return made
  end
  local design = designs[type]
  if design == nil then
    return nil
  end
  local look = Hull.looks[design.faction]
  local b: Builder = { big = PlateMesh_Create(9), small = PlateMesh_Create(4), count = 0, seed = #type * 1.37 }
  design.draw(b)
  PlateMesh_AddPlateMesh(b.big, b.small, ZERO, vector.create(1, 1, 1))
  local mesh = PlateMesh_GetMesh(b.big)
  Mesh_ComputeOcclusion(mesh)

  local skin = ShaderInstance_Create(Shader_Create("npm.jsl", "material/hull.jsl"))
  local function color(c: { number }): vector
    return vector.create(c[1], c[2], c[3])
  end
  ShaderInstance_SetVec3(skin, "paintPlating", color(look.plating))
  ShaderInstance_SetVec3(skin, "paintPatch", color(look.patch))
  ShaderInstance_SetVec3(skin, "paintFrame", color(look.frame))
  ShaderInstance_SetVec3(skin, "paintGlow", color(look.glow))
  ShaderInstance_SetVec3(skin, "paintTrim", color(look.trim))
  ShaderInstance_SetFloat(skin, "wear", look.wear)
  ShaderInstance_SetFloat(skin, "rust", look.rust)
  ShaderInstance_SetFloat(skin, "sheets", look.sheets)
  ShaderInstance_Link(skin)

  local model = Model_Create()
  Model_AddShell(model, mesh, skin)
  local bound = Renderable_GetBound(model)
  local size = bound.upper - bound.lower
  local result: Built = { model = model, radius = math.max(size.x, size.y, size.z) / 2 }
  built[type] = result
  return result
end

return Hull
