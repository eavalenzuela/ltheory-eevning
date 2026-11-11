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

-- The parts a plate can be: the whole number of its tag.
Plates.PLATING, Plates.PATCH, Plates.FRAME, Plates.GLOW, Plates.TRIM = 0, 1, 2, 3, 4

-- How a thing is painted and how worn it is.
export type Look = {
  plating: { number },
  patch: { number },
  frame: { number },
  glow: { number },
  trim: { number },
  wear: number,
  rust: number,
  sheets: number,       -- sheets of plating to a unit of the model
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
  kept: number,         -- how many plates have gone in
}

local ZERO = vector.create(0, 0, 0)

function Plates.New(seed: number, fine: number?): Builder
  return { big = PlateMesh_Create(9), small = PlateMesh_Create(4), count = 0, seed = seed, fine = fine or 0.11, ruin = nil, kept = 0 }
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
  local tag = part + own(b)
  local ruin = b.ruin
  if ruin then
    if math.floor(part) == Plates.GLOW then
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
  ShaderInstance_SetFloat(skin, "wear", look.wear)
  ShaderInstance_SetFloat(skin, "rust", look.rust)
  ShaderInstance_SetFloat(skin, "sheets", sheets or look.sheets)
  ShaderInstance_Link(skin)

  local model = Model_Create()
  Model_AddShell(model, mesh, skin)
  local bound = Renderable_GetBound(model)
  return model, bound.lower, bound.upper
end

return Plates
