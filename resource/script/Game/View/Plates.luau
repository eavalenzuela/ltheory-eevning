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
  lights: number?,      -- how many sheets have a lit port in them, 0 to 1; 0 if not said
}

-- To build a thing as the wreck of itself, a piece at a time: only the
-- plates whose middles lie from 'from' to 'to' along z are kept (the
-- line between two pieces is ragged, and each plate falls on one side
-- of it), 'loss' of those are missing, small ones first and most near
-- where it broke, the rest are knocked askew, and nothing is lit.
export type Ruin = { from: number, to: number, loss: number }

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
  -- What is not plates: skins lofted through outlines, and what swells
  -- out of them (Plates.Loft, Plates.Fairing). One mesh for all of it.
  skin: Mesh?,
  points: number,       -- how many vertices that mesh has
}

local ZERO = vector.create(0, 0, 0)

function Plates.New(seed: number, fine: number?): Builder
  return { big = PlateMesh_Create(9), small = PlateMesh_Create(4), count = 0, seed = seed, fine = fine or 0.11, ruin = nil,
    patch = nil, kept = 0, skin = nil, points = 0 }
end

-- The next plate's own number: the fraction of its tag.
local function own(b: Builder): number
  b.count += 1
  return ((math.sin(b.count * 12.9898 + b.seed) * 43758.5453) % 1) * 0.97
end

-- A number from 0 to 1 that follows from the plate's count and 'salt'.
local function dice(b: Builder, salt: number): number
  return (math.sin(b.count * 78.233 + salt * 37.719 + b.seed) * 43758.5453) % 1
end

-- Put a plate in; or, building a ruin, perhaps not, or not straight.
local function add(b: Builder, mesh: PlateMesh, part: number, center: vector, half: vector, turn: vector, bevel: number)
  local tone = own(b)
  local patch = b.patch
  if patch then
    local kind = math.floor(part)
    if kind ~= Plates.GLOW and kind ~= Plates.FIRE and math.max(half.x, half.y, half.z) < b.fine and dice(b, 11) < patch * 0.30 then
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
    if math.floor(part) == Plates.GLOW or math.floor(part) == Plates.FIRE then
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

-- The model of what has been built, painted as 'look' says, and the
-- corners of the box it fills.
function Plates.Finish(b: Builder, look: Look, sheets: number?): (Model, vector, vector)
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
  ShaderInstance_SetVec3(skin, "paintFire", color(look.fire or look.glow))
  ShaderInstance_SetFloat(skin, "wear", look.wear)
  ShaderInstance_SetFloat(skin, "rust", look.rust)
  ShaderInstance_SetFloat(skin, "sheets", sheets or look.sheets)
  ShaderInstance_SetFloat(skin, "mottle", look.mottle or 0)
  ShaderInstance_SetFloat(skin, "lights", look.lights or 0)
  ShaderInstance_Link(skin)

  local model = Model_Create()
  Model_AddShell(model, mesh, skin)
  local lofted = b.skin
  if lofted then
    -- (the engine's faces turn the other way from the way these were wound)
    Mesh_ReverseWinding(lofted)
    Mesh_ComputeNormals(lofted)
    Mesh_ComputeOcclusion(lofted)
    Model_AddShell(model, lofted, skin)
  end
  local bound = Renderable_GetBound(model)
  return model, bound.lower, bound.upper
end

return Plates
