--!strict
-- Building things out of plates: boxes with a centre, a half-size and a
-- turn, each tagged with the part it is (plating, a patched-in plate,
-- bare structure, something lit, trim) and a number of its own, so that
-- one shader can paint a whole model (material/hull.jsl). Hulls are
-- built this way (Game/View/Hull), and what is mounted on them
-- (Game/View/Arms).
--
--   local b = Plates.New(seed)
--   Plates.Block(b, Plates.PLATING, centre, half)
--   Plates.Beam(b, Plates.FRAME, from, to, 0.02)
--   local model, lower, upper = Plates.Finish(b, look)

local Plates = {}

-- The parts a plate can be: the whole number of its tag. (FIRE is an
-- engine's throat where its fire is not the colour of its lights.)
Plates.PLATING, Plates.PATCH, Plates.FRAME, Plates.GLOW, Plates.TRIM, Plates.FIRE = 0, 1, 2, 3, 4, 5
-- And lamps, lit in their own colours whatever the paint: a ship's
-- running lights, red to port, green to starboard, and white (a hull's
-- surface detail, Game/View/Hull).
Plates.LAMP_RED, Plates.LAMP_GREEN, Plates.LAMP_WHITE = 6, 7, 8

-- Whether a part is lit from within (and so is not there on bare metal,
-- nor in a wreck).
local function lit(part: number): boolean
  local kind = math.floor(part)
  return kind == Plates.GLOW or kind == Plates.FIRE or kind >= Plates.LAMP_RED
end

-- How a thing is painted and how worn it is.
export type Look = {
  plating: { number },
  patch: { number },
  frame: { number },
  glow: { number },
  trim: { number },
  fire: { number }?,    -- the colour of its engines' fire, where that is not 'glow'; 'glow' if not said
  wear: number,
  rust: number,
  sheets: number,       -- sheets of plating to a unit of the model
  mottle: number?,      -- how unlike one sheet is to the next, 0 to 1 (a patchwork); 0 if not said
  stone: number?,       -- how far it is stone, not sheets of plate, 0 to 1 (a stargate's); 0 if not said
  lights: number?,      -- how many sheets have a lit port in them, 0 to 1; 0 if not said
  -- A design laid over the plating (Core/Data/Paints): which figure,
  -- how many of it to the hull's length, and the colour it is laid on
  -- in. None, if not said.
  design: number?,
  designScale: number?,
  designPaint: { number }?,
  -- No paint at all: the engine's own bare metal, as its first
  -- generator's hulls were (and then nothing of the thing is lit, and
  -- the colours above are only what its wreck is charred from).
  bare: boolean?,
}

-- To build a thing as the wreck of itself, a piece at a time: only the
-- plates whose middles lie from 'from' to 'to' along z are kept (the
-- line between two pieces is ragged, and each plate falls on one side
-- of it), 'loss' of those are missing, small ones first and most near
-- where it broke, the rest are knocked askew, and nothing is lit.
export type Ruin = { from: number, to: number, loss: number }

-- A thing built, as a shape to ask whether a point is inside: a box
-- (its middle, its half-size and its turn), a skin (its outline, and
-- how far aside and how high its middle line is), or a hull in flat
-- plates (its sections).
export type Solid = {
  center: vector?, half: vector?, turn: vector?,
  outline: { { number } }?, x: number?, y: number?,
  sections: { { z: number, ring: { vector } } }?,
  -- (or a shape of somebody else's making, which says for itself
  -- whether a point is inside it: Plates.Stands)
  within: ((p: vector) -> boolean)?,
}

export type Builder = {
  big: PlateMesh,       -- plates with room for a fine bevel
  small: PlateMesh,     -- beams, pipes, fittings
  count: number,
  seed: number,
  -- Plates smaller than this (the longest half-size) go in the coarse
  -- mesh: 0.11 suits a hull drawn about two units long.
  fine: number,
  ruin: Ruin?,
  -- To build a thing as it is after pirates have had it: from 0 to 1,
  -- how much of its small fittings are gone, its plating swapped for
  -- whatever was to hand or left off down to the frame, and all of it
  -- a little out of true.
  patch: number?,
  kept: number,         -- how many plates have gone in
  -- How alike the plates are in tone, 0 to 1: as unlike as plates come
  -- if not said, and at 1 all the one tone.
  even: number?,
  -- What has been built that a thing can stand on, as shapes: every
  -- box, every skin, every hull in flat plates (Plates.Rests asks them).
  solids: { Solid },
  -- Built to be left bare (a Look's 'bare'): what would be lit is left
  -- out, since bare metal lights nothing. And 'scale': how many times
  -- the size it was drawn at the bare thing is made when it is finished.
  -- (The grain of the engine's metal is in the mesh's own units: a hull
  -- of the first generator's drawn a sixth of the size it made them
  -- would be all of a few great sheets. Whoever asks for it has what
  -- stands on the thing to move out with it.)
  bare: boolean?,
  scale: number?,
  -- Rivets along the seams of its sheets of plating, and finer lines
  -- between (a hull's surface detail, Game/View/Hull: material/hull.jsl).
  rivets: boolean?,
  -- What is not plates: skins lofted through outlines, and what swells
  -- out of them (Plates.Loft, Plates.Fairing). One mesh for all of it.
  skin: Mesh?,
  points: number,       -- how many vertices that mesh has
  -- And a second such mesh, for what stands on a skin and is not to
  -- shelter it: how open to the sky each place is, is worked out for a
  -- mesh by itself, and a low dome on a hull's back would otherwise put
  -- the hull about it in its shade, and the shader's grime with it.
  apart: Mesh?,
  apartPoints: number,
  -- A bend put on all of its plates when it is finished (Plates.Bend):
  -- where a point of the thing as drawn goes, and the way back.
  bend: ((p: vector) -> vector)?,
  unbend: ((p: vector) -> vector)?,
}

local ZERO = vector.create(0, 0, 0)

-- ('quality' is how finely its plates are meshed, the small ones as
-- finely as the big: 9 for the big and 4 for the small if not said,
-- which is what the game's own hulls are drawn at. The engine's first
-- generator meshed its hulls at 12.)
function Plates.New(seed: number, fine: number?, quality: number?): Builder
  return { big = PlateMesh_Create(quality or 9), small = PlateMesh_Create(quality or 4), count = 0, seed = seed, fine = fine or 0.11, ruin = nil,
    patch = nil, kept = 0, skin = nil, points = 0, apart = nil, apartPoints = 0, solids = {}, bend = nil, unbend = nil }
end

-- The next plate's own number: the fraction of its tag.
local function own(b: Builder): number
  b.count += 1
  local tone = ((math.sin(b.count * 12.9898 + b.seed) * 43758.5453) % 1) * 0.97
  local even = b.even
  return if even then 0.485 + (tone - 0.485) * (1 - even) else tone
end

-- A number from 0 to 1 that follows from the plate's count and 'salt'.
local function dice(b: Builder, salt: number): number
  return (math.sin(b.count * 78.233 + salt * 37.719 + b.seed) * 43758.5453) % 1
end

-- Put a plate in; or, building a ruin, perhaps not, or not straight.
local function add(b: Builder, mesh: PlateMesh, part: number, center: vector, half: vector, turn: vector, bevel: number)
  if b.bare and lit(part) then
    return
  end
  local tone = own(b)
  local patch = b.patch
  if patch then
    local kind = math.floor(part)
    if not lit(part) and math.max(half.x, half.y, half.z) < b.fine and dice(b, 11) < patch * 0.30 then
      return
    end
    if kind == Plates.PLATING and dice(b, 12) < patch * 0.40 then
      part = if dice(b, 13) < 0.3 then Plates.FRAME else Plates.PATCH
    elseif kind == Plates.PATCH and dice(b, 12) < patch * 0.30 then
      part = Plates.PLATING
    elseif kind == Plates.TRIM and dice(b, 12) < patch * 0.5 then
      part = Plates.FRAME
    end
    turn += vector.create(dice(b, 14) - 0.5, dice(b, 15) - 0.5, dice(b, 16) - 0.5) * (0.07 * patch)
  end
  local tag = part + tone
  local ruin = b.ruin
  if ruin then
    if lit(part) then
      return
    end
    local size = math.max(half.x, half.y, half.z)
    -- (which side of a break it falls: by its middle, give or take)
    local z = center.z + (dice(b, 1) - 0.5) * 0.3
    if z < ruin.from or z >= ruin.to then
      return
    end
    local near = 1 - math.clamp(math.min(z - ruin.from, ruin.to - z) / 0.3, 0, 1)
    local loss = ruin.loss * (if size < b.fine then 1.5 else 1) * (1 + 1.2 * near)
    if dice(b, 2) < loss then
      return
    end
    local knock = ruin.loss * (0.35 + 0.9 * near)
    turn += vector.create(dice(b, 3) - 0.5, dice(b, 4) - 0.5, dice(b, 5) - 0.5) * knock
    center += vector.create(dice(b, 6) - 0.5, dice(b, 7) - 0.5, dice(b, 8) - 0.5) * (math.min(size, 0.2) * knock)
  end
  b.kept += 1
  table.insert(b.solids, { center = center, half = half, turn = turn })
  PlateMesh_AddTagged(mesh, center, half, turn, bevel, tag)
end

-- A box: where its middle is, half its size each way, and optionally
-- how it is turned (yaw, pitch, roll) and how far its edges are eased.
function Plates.Block(b: Builder, part: number, center: vector, half: vector, turn: vector?, bevel: number?)
  local mesh = if math.max(half.x, half.y, half.z) > b.fine and math.min(half.x, half.y, half.z) > b.fine * 0.11 then b.big else b.small
  add(b, mesh, part, center, half, turn or ZERO, bevel or 0.10)
end

-- A bar from one point to another, 'thick' to a side.
function Plates.Beam(b: Builder, part: number, from: vector, to: vector, thick: number, bevel: number?)
  local d = to - from
  local length = vector.magnitude(d)
  if length < 1e-6 then
    return
  end
  d /= length
  local turn = vector.create(math.atan2(d.x, d.z), -math.asin(math.clamp(d.y, -1, 1)), 0)
  add(b, b.small, part, (from + to) / 2, vector.create(thick, thick, length / 2), turn, bevel or 0.15)
end

-- A girder of open lattice between two points: two rails 'width' apart
-- (sideways if 'across' is given, else up and down), cross-braced.
function Plates.Truss(b: Builder, from: vector, to: vector, width: number, bays: number, across: vector?)
  local side = (across or vector.create(0, 1, 0)) * (width / 2)
  local thick = width * 0.11
  local FRAME = Plates.FRAME
  Plates.Beam(b, FRAME, from + side, to + side, thick)
  Plates.Beam(b, FRAME, from - side, to - side, thick)
  for bay = 0, bays do
    local at = from + (to - from) * (bay / bays)
    Plates.Beam(b, FRAME, at + side, at - side, thick * 0.8)
    if bay < bays then
      local next = from + (to - from) * ((bay + 1) / bays)
      if bay % 2 == 0 then
        Plates.Beam(b, FRAME, at + side, next - side, thick * 0.7)
      else
        Plates.Beam(b, FRAME, at - side, next + side, thick * 0.7)
      end
    end
  end
end

-- A pipe run through a list of points.
function Plates.Conduit(b: Builder, points: { vector }, thick: number)
  for index = 1, #points - 1 do
    Plates.Beam(b, Plates.FRAME, points[index], points[index + 1], thick, 0.45)
  end
end

-- ---------------------------------------------------------------------
-- Skins. A plate is a box, and a hull of boxes has corners however they
-- are rounded. A skin is one surface drawn through a row of oval
-- sections, so that it swells and narrows without a break; and a
-- fairing is a slender swelling lying along such a skin and flush to it.

-- The outline of a skin, from one end to the other along z: at each
-- place, half its width and half its height there, and how high its
-- middle is (0 if not said).
export type Outline = { { number } }

-- A value drawn smoothly through four in a row, 't' of the way from the
-- second to the third.
local function through(a: number, b: number, c: number, d: number, t: number): number
  return 0.5 * ((2 * b) + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (3 * b - a - 3 * c + d) * t * t * t)
end

-- Half the width and half the height of an outline at 'z', and how high
-- its middle is there.
function Plates.Girth(outline: Outline, z: number): (number, number, number)
  local last = #outline
  local index = 1
  while index < last - 1 and z > outline[index + 1][1] do
    index += 1
  end
  local p1, p2 = outline[index], outline[index + 1]
  local p0, p3 = outline[math.max(index - 1, 1)], outline[math.min(index + 2, last)]
  local t = math.clamp((z - p1[1]) / (p2[1] - p1[1]), 0, 1)
  return math.max(through(p0[2], p1[2], p2[2], p3[2], t), 0.001), math.max(through(p0[3], p1[3], p2[3], p3[3], t), 0.001),
    through(p0[4] or 0, p1[4] or 0, p2[4] or 0, p3[4] or 0, t)
end

-- How square a section is: 2 is an ellipse.
local SQUARE = 2.3

-- The point of a skin at 'z' along it and 'around' it (0 to starboard,
-- a quarter turn is its back), for a skin whose middle line is at 'x'
-- and lifted 'y'.
function Plates.Point(outline: Outline, z: number, around: number, x: number?, y: number?): vector
  local w, h, middle = Plates.Girth(outline, z)
  local c, s = math.cos(around), math.sin(around)
  return vector.create((x or 0) + w * math.sign(c) * math.abs(c) ^ (2 / SQUARE),
    (y or 0) + middle + h * math.sign(s) * math.abs(s) ^ (2 / SQUARE), z)
end

-- The way out of a skin at a point of it.
function Plates.Normal(outline: Outline, z: number, around: number): vector
  local e = 0.01
  local round = Plates.Point(outline, z, around + e) - Plates.Point(outline, z, around - e)
  local along = Plates.Point(outline, z + e, around) - Plates.Point(outline, z - e, around)
  local n = vector.cross(round, along)
  return if vector.magnitude(n) > 1e-9 then vector.normalize(n) else vector.create(math.cos(around), math.sin(around), 0)
end

local function skinOf(b: Builder): Mesh
  local skin = b.skin
  if skin == nil then
    skin = Mesh_Create()
    b.skin = skin
  end
  return skin :: Mesh
end

local UNSET = vector.create(0, 1, 0)

-- A skin drawn through an outline, closed to a rounded end at each end
-- of it. 'x' and 'y' put its middle line aside and lift it.
function Plates.Loft(b: Builder, part: number, outline: Outline, x: number?, y: number?)
  local tag = part + own(b)
  local skin = skinOf(b)
  local first, last = outline[1][1], outline[#outline][1]
  local from, to = first, last
  local ruin = b.ruin
  if ruin then
    -- (a wreck: only the length of it that this piece of the wreck is)
    from, to = math.max(first, ruin.from), math.min(last, ruin.to)
    if to - from < 0.05 then
      return
    end
  end
  local sides = 28
  local rings = math.clamp(math.ceil((to - from) / 0.07), 6, 96)
  local base = b.points
  for ring = 0, rings do
    local z = from + (to - from) * ring / rings
    for side = 0, sides - 1 do
      Mesh_AddVertex(skin, Plates.Point(outline, z, side / sides * 2 * math.pi, x, y), UNSET, 1, tag)
    end
  end
  b.points += (rings + 1) * sides
  for ring = 0, rings - 1 do
    for side = 0, sides - 1 do
      local a, c = base + ring * sides + side, base + (ring + 1) * sides + side
      local a2, c2 = base + ring * sides + (side + 1) % sides, base + (ring + 1) * sides + (side + 1) % sides
      Mesh_AddTriangle(skin, a, a2, c)
      Mesh_AddTriangle(skin, a2, c2, c)
    end
  end
  -- the ends, each drawn in to a point a little beyond (not where a
  -- wreck is broken off: that end is left open)
  local function close(z: number, ring: number, out: number)
    local w, h, middle = Plates.Girth(outline, z)
    Mesh_AddVertex(skin, vector.create(x or 0, (y or 0) + middle, z + out * math.min(w, h) * 0.8), UNSET, 1, tag)
    local pole = b.points
    b.points += 1
    for side = 0, sides - 1 do
      local a, a2 = base + ring * sides + side, base + ring * sides + (side + 1) % sides
      if out < 0 then
        Mesh_AddTriangle(skin, pole, a2, a)
      else
        Mesh_AddTriangle(skin, pole, a, a2)
      end
    end
  end
  if from == first then
    close(first, 0, -1)
  end
  if to == last then
    close(last, rings, 1)
  end
  b.kept += 1
  table.insert(b.solids, { outline = outline, x = x or 0, y = y or 0 })
end

-- A surface of revolution (2026-11-20, for what turns on a hull: true
-- rings, domes and dishes, not chunks): 'profile' turned round the z
-- axis through the origin, each point of it (x) out from the axis at
-- (y) along it, in 'sides' steps round. Its outside is to the right of
-- the way the profile runs, drawn with out from the axis to the right
-- and along it up: round a torus, run it CLOCKWISE. (Until 2026-11-21
-- this said anticlockwise, which comes out inside out and lit dark:
-- checked in the viewer beside a plated block, for the stargates' rings
-- and then the hulls' tori, hoops and dishes.) 'closed' joins its last
-- point to its first. Smooth: its points are shared, so it is lit as
-- one rounded thing.
function Plates.Revolve(b: Builder, part: number, profile: { vector }, sides: number, closed: boolean?)
  local tag = part + own(b)
  local skin = skinOf(b)
  local base = b.points
  local count = #profile
  for _, point in profile do
    for side = 0, sides - 1 do
      local a = side / sides * 2 * math.pi
      Mesh_AddVertex(skin, vector.create(point.x * math.cos(a), point.x * math.sin(a), point.y), UNSET, 1, tag)
    end
  end
  b.points += count * sides
  local spans = if closed then count else count - 1
  for i = 0, spans - 1 do
    local j = (i + 1) % count
    for side = 0, sides - 1 do
      local a, c = base + i * sides + side, base + j * sides + side
      local a2, c2 = base + i * sides + (side + 1) % sides, base + j * sides + (side + 1) % sides
      Mesh_AddTriangle(skin, a, c, a2)
      Mesh_AddTriangle(skin, a2, c, c2)
    end
  end
  b.kept += 1
end

-- Plates.Revolve about any axis through any point, and over only part of
-- the way round if asked (2026-11-21, for the stargate mock-ups: rings
-- tilted in gimbals, a cradle's arc): the profile as Plates.Revolve takes
-- it, turned about 'axis' through 'at', from angle 'from' to 'to' (all
-- the way round if not said). A part-way turn of a closed profile is
-- shut at its two ends with flat caps.
function Plates.RevolveAt(b: Builder, part: number, profile: { vector }, sides: number, closed: boolean?, at: vector, axis: vector,
  from: number?, to: number?)
  local n = vector.normalize(axis)
  -- (about z, angle 0 is +x and a quarter round is +y, as Plates.Revolve's)
  local e1 = vector.normalize(vector.cross(if math.abs(n.y) < 0.9 then vector.create(0, 1, 0) else vector.create(1, 0, 0), n))
  local e2 = vector.cross(n, e1)
  local whole = from == nil or to == nil
  local a0, a1 = from or 0, to or 2 * math.pi
  local columns = if whole then sides else sides + 1
  local tag = part + own(b)
  local skin = skinOf(b)
  local base = b.points
  local count = #profile
  local function place(point: vector, a: number): vector
    return at + (e1 * math.cos(a) + e2 * math.sin(a)) * point.x + n * point.y
  end
  for _, point in profile do
    for side = 0, columns - 1 do
      Mesh_AddVertex(skin, place(point, a0 + (a1 - a0) * side / sides), UNSET, 1, tag)
    end
  end
  b.points += count * columns
  local spans = if closed then count else count - 1
  for i = 0, spans - 1 do
    local j = (i + 1) % count
    for side = 0, sides - 1 do
      local next = if whole then (side + 1) % sides else side + 1
      local a, c = base + i * columns + side, base + j * columns + side
      local a2, c2 = base + i * columns + next, base + j * columns + next
      Mesh_AddTriangle(skin, a, c, a2)
      Mesh_AddTriangle(skin, a2, c, c2)
    end
  end
  if not whole and closed then
    -- (each cap its own points, so that it is lit flat, about the middle
    -- of the profile; wound as the rest is, its faces' crosses turned out)
    local middle = vector.create(0, 0, 0)
    for _, point in profile do
      middle += point
    end
    middle /= count
    for _, end_ in { { a = a0, out = -1 }, { a = a1, out = 1 } } do
      local tangent = (-e1 * math.sin(end_.a) + e2 * math.cos(end_.a)) * end_.out
      local pole = b.points
      Mesh_AddVertex(skin, place(middle, end_.a), UNSET, 1, tag)
      for _, point in profile do
        Mesh_AddVertex(skin, place(point, end_.a), UNSET, 1, tag)
      end
      b.points += count + 1
      local p0 = place(middle, end_.a)
      local p1, p2 = place(profile[1], end_.a), place(profile[2], end_.a)
      local flip = vector.dot(vector.cross(p1 - p0, p2 - p0), tangent) < 0
      for k = 0, count - 1 do
        local k1, k2 = pole + 1 + k, pole + 1 + (k + 1) % count
        if flip then
          Mesh_AddTriangle(skin, pole, k2, k1)
        else
          Mesh_AddTriangle(skin, pole, k1, k2)
        end
      end
    end
  end
  b.kept += 1
end

-- A smooth round tube along a path (2026-11-20, for antennas: true
-- rods, tapered tips, a whip's curve): 'path' its middle line, 'radii'
-- how thick it is at each point of it, 'sides' steps round. Its ends are
-- closed flat (open, they let the eye through to its inside, which is not
-- drawn from there: the owner saw rods "half-disappear when looked at
-- from their tip").
function Plates.Tube(b: Builder, part: number, path: { vector }, radii: { number }, sides: number)
  local tag = part + own(b)
  local skin = skinOf(b)
  local base = b.points
  local count = #path
  -- (a frame carried along the path without twisting)
  local function way(i: number): vector
    local d = path[math.min(i + 1, count)] - path[math.max(i - 1, 1)]
    return if vector.magnitude(d) > 1e-9 then vector.normalize(d) else vector.create(0, 1, 0)
  end
  local t = way(1)
  local seed = if math.abs(t.x) < 0.9 then vector.create(1, 0, 0) else vector.create(0, 0, 1)
  local n = vector.normalize(seed - t * vector.dot(seed, t))
  for i = 1, count do
    local ti = way(i)
    n = n - ti * vector.dot(n, ti)
    n = if vector.magnitude(n) > 1e-9 then vector.normalize(n) else vector.normalize(vector.cross(ti, seed))
    local bi = vector.cross(ti, n)
    for side = 0, sides - 1 do
      local a = side / sides * 2 * math.pi
      Mesh_AddVertex(skin, path[i] + (n * math.cos(a) + bi * math.sin(a)) * radii[i], UNSET, 1, tag)
    end
  end
  b.points += count * sides
  for i = 0, count - 2 do
    for side = 0, sides - 1 do
      local a, c = base + i * sides + side, base + (i + 1) * sides + side
      local a2, c2 = base + i * sides + (side + 1) % sides, base + (i + 1) * sides + (side + 1) % sides
      Mesh_AddTriangle(skin, a, a2, c)
      Mesh_AddTriangle(skin, a2, c2, c)
    end
  end
  -- (its sides wound so that their outsides are drawn: the other way, the
  -- eye saw through a rod to its foot, the owner's "the bases are actually
  -- visible through the rod antennas"; and its two ends, each a flat fan
  -- about a point in its middle, wound to match)
  for _, at in { 1, count } do
    Mesh_AddVertex(skin, path[at], UNSET, 1, tag)
    local pole = b.points
    b.points += 1
    local ring = base + (at - 1) * sides
    for side = 0, sides - 1 do
      local a, a2 = ring + side, ring + (side + 1) % sides
      if at == 1 then
        Mesh_AddTriangle(skin, pole, a2, a)
      else
        Mesh_AddTriangle(skin, pole, a, a2)
      end
    end
  end
  b.kept += 1
end

-- A thin blade (2026-11-20, for fins): its leading and trailing edges
-- as points from root to tip ('lead', 'trail'), so thick at each step
-- ('thick') across 'side' (the way its faces look), with flat faces and
-- sharp edges; open at its root (which is in the hull or a root fitting).
-- More steps along a curved edge make a curved, swept blade.
function Plates.Blade(b: Builder, part: number, lead: { vector }, trail: { vector }, thick: { number }, side: vector)
  local count = #lead
  for i = 1, count - 1 do
    local h0, h1 = side * (thick[i] / 2), side * (thick[i + 1] / 2)
    local l0, l1, t0, t1 = lead[i], lead[i + 1], trail[i], trail[i + 1]
    local chord = vector.normalize(((l0 - t0) + (l1 - t1)) / 2)
    -- (its two faces)
    Plates.Facet(b, part, l0 + h0, t0 + h0, t1 + h1, side)
    Plates.Facet(b, part, l0 + h0, t1 + h1, l1 + h1, side)
    Plates.Facet(b, part, l0 - h0, t0 - h0, t1 - h1, -side)
    Plates.Facet(b, part, l0 - h0, t1 - h1, l1 - h1, -side)
    -- (its leading and trailing edges)
    Plates.Facet(b, part, l0 + h0, l0 - h0, l1 - h1, chord)
    Plates.Facet(b, part, l0 + h0, l1 - h1, l1 + h1, chord)
    Plates.Facet(b, part, t0 + h0, t0 - h0, t1 - h1, -chord)
    Plates.Facet(b, part, t0 + h0, t1 - h1, t1 + h1, -chord)
  end
  -- (and its tip)
  local l, t, h = lead[count], trail[count], side * (thick[count] / 2)
  local out = vector.normalize(lead[count] - lead[math.max(1, count - 1)])
  Plates.Facet(b, part, l + h, t + h, t - h, out)
  Plates.Facet(b, part, l + h, t - h, l - h, out)
end

-- A fairing: a slender swelling on a skin, lying along it and flush to
-- it, pointed at both ends. 'z' and 'around' are where its middle is on
-- the skin (Plates.Point); it is 'length' long, 'width' across at its
-- widest, and stands 'height' out there.
function Plates.Fairing(b: Builder, part: number, outline: Outline, z: number, around: number, length: number, width: number,
  height: number, x: number?, y: number?)
  local tone = own(b)
  local ruin = b.ruin
  if ruin and (z < ruin.from or z >= ruin.to or dice(b, 21) < ruin.loss) then
    return
  end
  local patch = b.patch
  if patch then
    -- (a pirate's: some are gone, and some are whatever was to hand)
    if dice(b, 22) < patch * 0.30 then
      return
    elseif dice(b, 23) < patch * 0.40 then
      part = if math.floor(part) == Plates.PATCH then Plates.PLATING else Plates.PATCH
    end
  end
  local tag = part + tone
  local skin = skinOf(b)
  local first, last = outline[1][1], outline[#outline][1]
  local rings, sides = 12, 7
  local base = b.points
  local ahead = vector.create(0, 0, 1)
  for ring = 0, rings do
    local s = -1 + 2 * ring / rings
    local at = math.clamp(z + s * length / 2, first, last)
    local foot, out = Plates.Point(outline, at, around, x, y), Plates.Normal(outline, at, around)
    local across = vector.cross(out, ahead)
    across = if vector.magnitude(across) > 1e-6 then vector.normalize(across) else vector.create(1, 0, 0)
    -- (fullest a little ahead of its middle, and drawn out to a point behind)
    local full = math.max(0, 1 - s * s) ^ 0.7 * (1 + 0.25 * s)
    for side = 0, sides do
      local turn = side / sides * math.pi
      Mesh_AddVertex(skin, foot - out * (0.25 * height * full + 0.004) + across * (0.5 * width * full * math.cos(turn))
        + out * (1.25 * height * full * math.sin(turn)), UNSET, 1, tag)
    end
  end
  b.points += (rings + 1) * (sides + 1)
  for ring = 0, rings - 1 do
    for side = 0, sides - 1 do
      local a, c = base + ring * (sides + 1) + side, base + (ring + 1) * (sides + 1) + side
      Mesh_AddTriangle(skin, a, a + 1, c)
      Mesh_AddTriangle(skin, a + 1, c + 1, c)
    end
  end
  b.kept += 1
end

-- What becomes of a flat plate whose middle is at 'middle', in a wreck
-- or on a pirate's hull: the part it is to be, or nil if it is not
-- there. (A wreck has the plates of the piece of it being built, less
-- what was lost, and nothing lit; a pirate's has some of its plating
-- swapped for whatever was to hand. Anything else has it as it is.)
local function fate(b: Builder, part: number, middle: vector): number?
  local kind = math.floor(part)
  local ruin = b.ruin
  if ruin then
    local z = middle.z + (dice(b, 1) - 0.5) * 0.3
    if lit(kind) or z < ruin.from or z >= ruin.to or dice(b, 2) < ruin.loss then
      return nil
    end
  end
  local patch = b.patch
  if patch then
    if kind == Plates.PLATING and dice(b, 12) < patch * 0.40 then
      return if dice(b, 13) < 0.3 then Plates.FRAME else Plates.PATCH
    elseif kind == Plates.PATCH and dice(b, 12) < patch * 0.30 then
      return Plates.PLATING
    end
  end
  return part
end

-- Three corners of a flat plate with the tag 'tag': their own points,
-- so that it is lit as one face.
local function facet(b: Builder, tag: number, p1: vector, p2: vector, p3: vector, out: vector)
  -- (corners that meet make no plate: an outline that comes to a point)
  if vector.magnitude(vector.cross(p2 - p1, p3 - p1)) < 1e-10 then
    return
  end
  local skin = skinOf(b)
  if vector.dot(vector.cross(p2 - p1, p3 - p1), out) < 0 then
    p2, p3 = p3, p2
  end
  local base = b.points
  Mesh_AddVertex(skin, p1, UNSET, 1, tag)
  Mesh_AddVertex(skin, p2, UNSET, 1, tag)
  Mesh_AddVertex(skin, p3, UNSET, 1, tag)
  Mesh_AddTriangle(skin, base, base + 1, base + 2)
  b.points += 3
end

-- A flat plate with three corners, sharp at every edge. 'out' is the
-- way its outside looks, near enough: the corners are taken in
-- whichever order makes that so.
function Plates.Facet(b: Builder, part: number, p1: vector, p2: vector, p3: vector, out: vector)
  local tone = own(b)
  local as = fate(b, part, (p1 + p2 + p3) / 3)
  if as then
    facet(b, as + tone, p1, p2, p3, out)
    b.kept += 1
  end
end

-- A flat plate with any number of corners, given in order round it
-- (they should lie in a plane, and bulge nowhere inward): one plate,
-- of one tone.
function Plates.Flat(b: Builder, part: number, corners: { vector }, out: vector)
  local tone = own(b)
  local middle = vector.create(0, 0, 0)
  for _, corner in corners do
    middle += corner
  end
  local as = fate(b, part, middle / #corners)
  if as == nil then
    return
  end
  for index = 2, #corners - 1 do
    facet(b, as + tone, corners[1], corners[index], corners[index + 1], out)
  end
  b.kept += 1
end

-- A section of a hull in flat plates: where it is along z, and the
-- corners of its outline there in order round it (their x and y: a
-- corner's own z is not looked at).
export type Section = { z: number, ring: { vector } }

-- A hull in flat plates, sharp at every edge: flat from each section to
-- the next, corner to corner (every section has as many corners as the
-- first, going round the same way, and bulges nowhere inward), and
-- closed flat at both ends. An outline may come to a point, or to a
-- line. A long reach between two sections is laid in several lengths
-- of plate ('reach' long at the most, 0.3 if not said), so that the
-- wreck of it breaks across and not along.
function Plates.Hard(b: Builder, part: number, sections: { Section }, reach: number?)
  local step = reach or 0.3
  local function ringAt(a: Section, c: Section, t: number): ({ vector }, vector)
    local ring: { vector } = {}
    local middle = vector.create(0, 0, 0)
    for index, p in a.ring do
      local q = c.ring[index]
      local at = vector.create(p.x + (q.x - p.x) * t, p.y + (q.y - p.y) * t, a.z + (c.z - a.z) * t)
      ring[index] = at
      middle += at
    end
    return ring, middle / #ring
  end
  for index = 1, #sections - 1 do
    local a, c = sections[index], sections[index + 1]
    local lengths = math.max(1, math.ceil(math.abs(c.z - a.z) / step))
    for length = 1, lengths do
      local near, nearMiddle = ringAt(a, c, (length - 1) / lengths)
      local far, farMiddle = ringAt(a, c, length / lengths)
      local middle = (nearMiddle + farMiddle) / 2
      for corner = 1, #near do
        local after = corner % #near + 1
        Plates.Flat(b, part, { near[corner], near[after], far[after], far[corner] },
          (near[corner] + near[after] + far[after] + far[corner]) / 4 - middle)
      end
    end
  end
  table.insert(b.solids, { sections = sections })
  local first, last = sections[1], sections[#sections]
  local ahead = if last.z > first.z then 1 else -1
  for _, cap in { { section = first, out = -ahead }, { section = last, out = ahead } } do
    local ring: { vector } = {}
    for index, p in cap.section.ring do
      ring[index] = vector.create(p.x, p.y, cap.section.z)
    end
    Plates.Flat(b, part, ring, vector.create(0, 0, cap.out))
  end
end

-- A skin of somebody else's making (Game/View/Imported): points (x, y
-- and z of each, one after another) and faces of three of them (counted
-- from 1, in order counter-clockwise seen from outside), all of one
-- paint and one tone. In a wreck, only the faces of the length of it
-- that this piece of the wreck is, less what was lost, a patch of them
-- at a time; and nothing lit. With 'apart' it is kept from sheltering
-- the rest (a thing standing on a hull, that is not to put the hull
-- about it in shade).
function Plates.Skin(b: Builder, part: number, points: { number }, faces: { number }, apart: boolean?)
  local tag = part + own(b)
  local kind = math.floor(part)
  local ruin = b.ruin
  if ruin and lit(kind) then
    return
  end
  local skin: Mesh
  local base: number
  if apart then
    local other = b.apart
    if other == nil then
      other = Mesh_Create()
      b.apart = other
    end
    skin, base = other :: Mesh, b.apartPoints
    b.apartPoints += #points // 3
  else
    skin, base = skinOf(b), b.points
    b.points += #points // 3
  end
  for at = 1, #points, 3 do
    Mesh_AddVertex(skin, vector.create(points[at], points[at + 1], points[at + 2]), UNSET, 1, tag)
  end
  for at = 1, #faces, 3 do
    local a, c, d = faces[at], faces[at + 1], faces[at + 2]
    local keep = true
    if ruin then
      local x = (points[3 * a - 2] + points[3 * c - 2] + points[3 * d - 2]) / 3
      local y = (points[3 * a - 1] + points[3 * c - 1] + points[3 * d - 1]) / 3
      local z = (points[3 * a] + points[3 * c] + points[3 * d]) / 3
      -- (faces near one another go, or stay, together: as a plate would)
      local patch = math.floor(x * 7) * 12.9898 + math.floor(y * 7) * 78.233 + math.floor(z * 7) * 37.719 + b.seed
      local ragged = (math.sin(patch) * 43758.5453) % 1
      local lost = (math.sin(patch * 1.7 + 4.1) * 43758.5453) % 1
      z += (ragged - 0.5) * 0.3
      keep = z >= ruin.from and z < ruin.to and lost >= ruin.loss
    end
    if keep then
      Mesh_AddTriangle(skin, base + a - 1, base + c - 1, base + d - 1)
    end
  end
  b.kept += 1
end

-- Something has been built that a thing can stand on, which says for
-- itself whether a point is inside it (a closed skin of somebody
-- else's making).
function Plates.Stands(b: Builder, within: (p: vector) -> boolean)
  table.insert(b.solids, { within = within })
end

-- Whether a point is inside something that has been built (a box, a
-- skin or a hull in flat plates; not a beam, a truss or a pipe, which
-- nothing stands on).
function Plates.Inside(b: Builder, p: vector): boolean
  -- (what was built is kept as it was drawn: a point of the bent thing
  -- is asked about where it was before the bend)
  local unbend = b.unbend
  if unbend then
    p = unbend(p)
  end
  for _, solid in b.solids do
    local center, half, turn = solid.center, solid.half, solid.turn
    local outline, sections = solid.outline, solid.sections
    local within = solid.within
    if within then
      if within(p) then
        return true
      end
    elseif center and half and turn then
      -- (a box is turned about y, then x, then z: undo them the other way round)
      local q = p - center
      if turn.x ~= 0 then
        local c, s = math.cos(-turn.x), math.sin(-turn.x)
        q = vector.create(c * q.x + s * q.z, q.y, -s * q.x + c * q.z)
      end
      if turn.y ~= 0 then
        local c, s = math.cos(-turn.y), math.sin(-turn.y)
        q = vector.create(q.x, c * q.y - s * q.z, s * q.y + c * q.z)
      end
      if turn.z ~= 0 then
        local c, s = math.cos(-turn.z), math.sin(-turn.z)
        q = vector.create(c * q.x - s * q.y, s * q.x + c * q.y, q.z)
      end
      if math.abs(q.x) <= half.x and math.abs(q.y) <= half.y and math.abs(q.z) <= half.z then
        return true
      end
    elseif outline then
      if p.z >= outline[1][1] and p.z <= outline[#outline][1] then
        local w, h, middle = Plates.Girth(outline, p.z)
        local dx, dy = math.abs(p.x - (solid.x or 0)) / w, math.abs(p.y - (solid.y or 0) - middle) / h
        if dx ^ SQUARE + dy ^ SQUARE <= 1 then
          return true
        end
      end
    elseif sections then
      for index = 1, #sections - 1 do
        local a, c = sections[index], sections[index + 1]
        local low, high = math.min(a.z, c.z), math.max(a.z, c.z)
        if p.z >= low and p.z <= high and high > low then
          -- (its outline there, between the two sections: inside it if the
          -- point is on the same side of every edge)
          local t = (p.z - a.z) / (c.z - a.z)
          local sign = 0
          local inside = true
          local count = #a.ring
          for corner = 1, count do
            local after = corner % count + 1
            local x1 = a.ring[corner].x + (c.ring[corner].x - a.ring[corner].x) * t
            local y1 = a.ring[corner].y + (c.ring[corner].y - a.ring[corner].y) * t
            local x2 = a.ring[after].x + (c.ring[after].x - a.ring[after].x) * t
            local y2 = a.ring[after].y + (c.ring[after].y - a.ring[after].y) * t
            local turnOf = (x2 - x1) * (p.y - y1) - (y2 - y1) * (p.x - x1)
            if math.abs(turnOf) > 1e-9 then
              local way = if turnOf > 0 then 1 else -1
              if sign == 0 then
                sign = way
              elseif way ~= sign then
                inside = false
                break
              end
            end
          end
          if inside and sign ~= 0 then
            return true
          end
        end
      end
    end
  end
  return false
end

-- Whether a thing that stands on a round foot stands wholly on what
-- has been built: 'at' is the middle of the foot, 'up' the way out of
-- the hull there, 'fore' the way the thing faces, 'reach' how far the
-- foot goes from its middle (as far as a turret's ring reaches while it
-- turns), and 'gap' how far under the foot the hull may lie (a skin
-- curves away under a flat foot, and that is no fault). The middle of
-- the foot, eight places round its rim and eight halfway out have to
-- have hull under them within 'gap': a foot with nothing under part of
-- it hangs off into space. Returns whether it stands, and how many of
-- the seventeen places have nothing under them.
--
-- A foot that does not turn (a launcher's rack) is a square with its
-- corners rounded: 'square' is then half its width, and it reaches
-- 'reach' only toward its corners.
function Plates.Rests(b: Builder, at: vector, up: vector, fore: vector, reach: number, gap: number, square: number?): (boolean, number)
  local level = fore - up * vector.dot(fore, up)
  level = if vector.magnitude(level) > 1e-4 then vector.normalize(level) else vector.normalize(vector.cross(up, vector.create(1, 0, 0)))
  local side = vector.cross(up, level)
  local places: { vector } = { at }
  for step = 0, 7 do
    local way = level * math.cos(step * math.pi / 4) + side * math.sin(step * math.pi / 4)
    local far = if square and step % 2 == 0 then square else reach
    table.insert(places, at + way * far)
    table.insert(places, at + way * (far / 2))
  end
  local hanging = 0
  for _, place in places do
    local held = false
    for _, share in { 0.06, 0.36, 0.68, 1.0 } do
      if Plates.Inside(b, place - up * (share * gap)) then
        held = true
        break
      end
    end
    if not held then
      hanging += 1
    end
  end
  return hanging == 0, hanging
end

-- Bend the whole of what is built of plates, when it is finished: 'bend'
-- gives where a point of it as drawn goes, and 'unbend' is the way
-- back. (The engine's first hulls were made so: plain boxes, and two
-- warps over the lot. Skins are not bent.) What is asked of the thing
-- afterwards (Plates.Inside, Plates.Rests) is asked of it as bent.
function Plates.Bend(b: Builder, bend: (p: vector) -> vector, unbend: (p: vector) -> vector)
  b.bend, b.unbend = bend, unbend
end

-- The model of what has been built, painted as 'look' says, and the
-- corners of the box it fills.
function Plates.Finish(b: Builder, look: Look, sheets: number?): (Model, vector, vector, { Mesh })
  PlateMesh_AddPlateMesh(b.big, b.small, ZERO, vector.create(1, 1, 1))
  local bend = b.bend
  if bend then
    PlateMesh_AddWarp(b.big, Warp_Custom({
      GetDelta = function(_, p: vector): vector
        return bend(p) - p
      end,
    }))
  end
  local mesh = PlateMesh_GetMesh(b.big)

  -- (bare, it is the engine's own metal and nothing else, at the size
  -- that metal's grain is right for)
  if look.bare then
    local scale = b.scale
    if scale and scale ~= 1 then
      Mesh_Scale(mesh, vector.create(scale, scale, scale))
    end
    Mesh_ComputeOcclusion(mesh)
    local metal = Model_Create()
    Model_Add(metal, mesh, Material_Metal())
    -- (and a skin, bare as the rest: a moving part's rings and dishes)
    local lofted = b.skin
    if lofted then
      Mesh_ReverseWinding(lofted)
      Mesh_ComputeNormals(lofted)
      if scale and scale ~= 1 then
        Mesh_Scale(lofted, vector.create(scale, scale, scale))
      end
      Mesh_ComputeOcclusion(lofted)
      Model_Add(metal, lofted, Material_Metal())
    end
    local box = Renderable_GetBound(metal)
    return metal, box.lower, box.upper, { mesh }
  end
  Mesh_ComputeOcclusion(mesh)

  local function color(c: { number }): vector
    return vector.create(c[1], c[2], c[3])
  end
  -- (a design is laid out from the middle of the thing, in halves of
  -- its length: so it is measured first, as a bare model of itself)
  local middle, half = ZERO, 1
  if (look.design or 0) > 0 then
    local probe = Model_Create()
    Model_Add(probe, mesh, Material_Metal())
    local box = Renderable_GetBound(probe)
    -- (a thing that is all smooth skin and no plates, the capsule, is
    -- measured by its skin: else it has no length, and a design repeats
    -- over it hundreds of times. A plated hull is measured as it was.)
    if box.upper.z - box.lower.z < 1e-3 then
      probe = Model_Create()
      for _, lofted in { b.skin :: Mesh?, b.apart :: Mesh? } do
        Model_Add(probe, lofted, Material_Metal())
      end
      box = Renderable_GetBound(probe)
    end
    middle, half = (box.lower + box.upper) / 2, math.max(0.001, (box.upper.z - box.lower.z) / 2)
  end
  -- The paint, once for the plates and once for the smooth skins: the
  -- shader wears paint back to metal along a plate's bevel, where its
  -- smoothed normal comes up short, and across a curved skin every
  -- normal does, so a skin was worn grey all over (the owner, 2026-11-25:
  -- "Is this why all the curved towers types are so grey?"). A skin has
  -- no bevels, and is told so ('skinned').
  local function painted(skinned: boolean): ShaderInstance
    local shader = ShaderInstance_Create(Shader_Create("npm.jsl", "material/hull.jsl"))
    ShaderInstance_SetVec3(shader, "paintPlating", color(look.plating))
    ShaderInstance_SetVec3(shader, "paintPatch", color(look.patch))
    ShaderInstance_SetVec3(shader, "paintFrame", color(look.frame))
    ShaderInstance_SetVec3(shader, "paintGlow", color(look.glow))
    ShaderInstance_SetVec3(shader, "paintTrim", color(look.trim))
    ShaderInstance_SetVec3(shader, "paintFire", color(look.fire or look.glow))
    ShaderInstance_SetFloat(shader, "wear", look.wear)
    ShaderInstance_SetFloat(shader, "rust", look.rust)
    ShaderInstance_SetFloat(shader, "sheets", sheets or look.sheets)
    ShaderInstance_SetFloat(shader, "mottle", look.mottle or 0)
    ShaderInstance_SetFloat(shader, "stone", look.stone or 0)
    ShaderInstance_SetFloat(shader, "lights", look.lights or 0)
    ShaderInstance_SetFloat(shader, "rivets", if b.rivets then 1 else 0)
    ShaderInstance_SetFloat(shader, "skinned", if skinned then 1 else 0)
    ShaderInstance_SetFloat(shader, "design", look.design or 0)
    ShaderInstance_SetFloat(shader, "designScale", look.designScale or 1)
    ShaderInstance_SetVec3(shader, "designMiddle", middle)
    ShaderInstance_SetFloat(shader, "designHalf", half)
    ShaderInstance_SetVec3(shader, "paintDesign", color(look.designPaint or look.trim))
    ShaderInstance_Link(shader)
    return shader
  end

  local model = Model_Create()
  Model_AddShell(model, mesh, painted(false))
  local meshes = { mesh }
  local smooth: ShaderInstance? = nil
  for _, lofted in { b.skin :: Mesh?, b.apart :: Mesh? } do
    -- (the engine's faces turn the other way from the way these were wound)
    Mesh_ReverseWinding(lofted)
    Mesh_ComputeNormals(lofted)
    Mesh_ComputeOcclusion(lofted)
    smooth = smooth or painted(true)
    Model_AddShell(model, lofted, smooth :: ShaderInstance)
    table.insert(meshes, lofted :: Mesh)
  end
  local bound = Renderable_GetBound(model)
  return model, bound.lower, bound.upper, meshes
end

-- The same shape as a finished model (its meshes: Plates.Finish gives
-- them), not painted but drawn as light bending round something that
-- is not seen (fx_ghost.jsl): what a cloaked hull looks like to its
-- own pilot. 'tint' is the colour of that light.
function Plates.Ghost(meshes: { Mesh }, tint: vector, glow: number): Model
  local skin = ShaderInstance_Create(Shader_Create("npm.jsl", "fx_ghost.jsl"))
  ShaderInstance_SetState(skin, "BlendModeAdditive")
  ShaderInstance_SetState(skin, "ZWritableOff")
  ShaderInstance_SetState(skin, "CullModeDisabled")
  ShaderInstance_SetVec3(skin, "ghostTint", tint)
  ShaderInstance_SetFloat(skin, "ghostGlow", glow)
  ShaderInstance_Link(skin)
  local model = Model_Create()
  for _, mesh in meshes do
    Model_AddShell(model, mesh, skin)
  end
  return model
end

return Plates
