--!strict
-- Citadels as they are drawn: a generator of their own (the owner,
-- 2026-11-17: "They will be their own dedicated generator, but they will
-- reuse eg the antennas, greebles, and lights we just built for ships";
-- and of the first sheets, "Push it more towards intersecting cubes and
-- rectangles, and with an asymmetry flag. It should also have hangar
-- entrance, with air shield effects").
--
-- A citadel is grown from a seed, at one of its five sizes
-- (Data/Structures' CITADEL_SIZES), out of blocks that cut into each
-- other: a core, and blocks grown off the faces of those already there,
-- each pushed part of the way into the one it grows from: cubes, slabs
-- and long beams. Mirrored side to side and fore and aft, unless it is
-- grown asymmetrical ('asym'), when nothing of it is the twin of
-- anything. Its bigger blocks have hangar entrances on their sides: a
-- dark mouth let into the face, lit round its edges, with an air shield
-- across it (a sheet of force, drawn as a tower's field is:
-- airshield.jsl). Over all that, the hull's surface detail (Game/View/
-- Hull: antennas, pipes, greebles, lights, rivets). Every shape and
-- number here is mine; which seed each size is drawn from is the
-- owner's to pick (Citadel.PICKS).

local Hull = require("@lt/Game/View/Hull")
local Int = require("@lt/Int")
local Plates = require("@lt/Game/View/Plates")

local Citadel = {}

local PLATING, PATCH, FRAME, GLOW = Plates.PLATING, Plates.PATCH, Plates.FRAME, Plates.GLOW
local v = vector.create

-- What each size is drawn from until the owner picks: stand-ins.
-- (seed, whether it is asymmetrical, and the kinds of its surface detail)
Citadel.PICKS = {
  { seed = 1, asym = false, detail = "antennas pipes greebles lights rivets" },
  { seed = 2, asym = false, detail = "antennas pipes greebles lights rivets" },
  { seed = 3, asym = false, detail = "antennas pipes greebles lights rivets" },
  { seed = 4, asym = false, detail = "antennas pipes greebles lights rivets" },
  { seed = 5, asym = false, detail = "antennas pipes greebles lights rivets" },
} :: { { seed: number, asym: boolean, detail: string } }

-- A hangar's mouth: the middle of the opening, the way out of it, and
-- half of it across and up (in the generator's units).
export type Mouth = { at: vector, n: vector, wide: number, high: number }

type Block = { center: vector, half: vector, part: number }

-- The plates of a citadel grown from a seed at a size (1 to 5), and its
-- hangar mouths, in the hull generator's units.
function Citadel.Grow(seed: number, size: number, asym: boolean?): ({ Hull.Plate }, { Mouth })
  local rng = RNG_MTG(Int.Signed(seed * 31 + size * 7 + 4001))
  local blocks: { Block } = {}
  local reach = 3.2 + 1.3 * size
  -- Put a block in, and its mirror images where it has them.
  local function add(center: vector, half: vector, part: number)
    table.insert(blocks, { center = center, half = half, part = part })
    if asym then
      return
    end
    local xs: { number } = if math.abs(center.x) > 1e-3 then { 1, -1 } else { 1 }
    local zs: { number } = if math.abs(center.z) > 1e-3 then { 1, -1 } else { 1 }
    for _, sx in xs do
      for _, sz in zs do
        if sx ~= 1 or sz ~= 1 then
          table.insert(blocks, { center = v(center.x * sx, center.y, center.z * sz), half = half, part = part })
        end
      end
    end
  end

  -- The core: a big block, a cube or a slab or a tower.
  local unit = 0.9 + 0.3 * size
  local coreKind = rng:Int(3)
  local core = if coreKind == 0 then v(1, 1, 1) * unit * 1.3
    elseif coreKind == 1 then v(1.6, 0.7, 1.6) * unit
    else v(0.9, 1.9, 0.9) * unit
  add(v(0, 0, 0), core, PLATING)

  -- Blocks grown off the faces of those there are, each pushed part of
  -- the way into the one it grows from.
  local ways = { v(1, 0, 0), v(-1, 0, 0), v(0, 1, 0), v(0, -1, 0), v(0, 0, 1), v(0, 0, -1) }
  -- (twice as many for one grown asymmetrical: it has no twins to fill it out)
  local grown = (5 + 4 * size + rng:Int(0, 4)) * (if asym then 2 else 1)
  for _ = 1, grown do
    local from = blocks[rng:Int(#blocks) + 1]
    local way = ways[rng:Int(6) + 1]
    local scale = math.max(from.half.x, from.half.y, from.half.z) * rng:Float(0.35, 0.85)
    local kind = rng:Int(5)
    local half: vector
    local part = PLATING
    if kind == 0 then
      -- a cube
      half = v(1, 1, 1) * scale * rng:Float(0.6, 0.9)
    elseif kind == 1 then
      -- a slab, flat across the upright
      half = v(scale * rng:Float(1.0, 1.6), scale * rng:Float(0.18, 0.35), scale * rng:Float(1.0, 1.6))
      part = PATCH
    elseif kind == 2 then
      -- a long beam out the way it grows
      local long = scale * rng:Float(1.4, 2.6)
      local thin = scale * rng:Float(0.15, 0.3)
      half = v(if way.x ~= 0 then long else thin, if way.y ~= 0 then long else thin, if way.z ~= 0 then long else thin)
      part = FRAME
    elseif kind == 3 then
      -- a tall block, standing up
      half = v(scale * rng:Float(0.4, 0.7), scale * rng:Float(1.1, 1.8), scale * rng:Float(0.4, 0.7))
    else
      -- a long block lying across the way it grows
      local long = scale * rng:Float(1.2, 2.0)
      half = if way.x ~= 0 then v(scale * 0.5, scale * 0.55, long) else v(long, scale * 0.55, scale * 0.5)
      part = PATCH
    end
    -- (its middle: out of the face it grows from by part of itself, and
    -- off the middle of that face by some of the face)
    local outFrom = math.abs(vector.dot(from.half, way))
    local outOwn = math.abs(vector.dot(half, way))
    local across = v(1, 1, 1) - v(math.abs(way.x), math.abs(way.y), math.abs(way.z))
    local slide = v(rng:Float(-0.6, 0.6), rng:Float(-0.6, 0.6), rng:Float(-0.6, 0.6)) * from.half * across
    local center = from.center + way * (outFrom + outOwn * rng:Float(-0.5, 0.4)) + slide
    -- (kept within its reach, and in the symmetrical a block that strays
    -- just over the middle line is put on it, so its twin does not cut it in two)
    if vector.magnitude(center) + math.max(half.x, half.y, half.z) <= reach then
      if not asym then
        if math.abs(center.x) < half.x * 0.6 then
          center = v(0, center.y, center.z)
        end
        if math.abs(center.z) < half.z * 0.6 then
          center = v(center.x, center.y, 0)
        end
      end
      add(center, half, part)
    end
  end

  -- Whether a point is inside a block (a hair in from its faces).
  local function inside(p: vector): boolean
    for _, block in blocks do
      local d = p - block.center
      if math.abs(d.x) < block.half.x - 1e-4 and math.abs(d.y) < block.half.y - 1e-4 and math.abs(d.z) < block.half.z - 1e-4 then
        return true
      end
    end
    return false
  end

  -- Hangar entrances: on the side faces of the bigger blocks, where the
  -- whole mouth looks out into nothing. One a size and one more, mirrored
  -- with their blocks.
  local mouths: { Mouth } = {}
  local extra: { Hull.Plate } = {}
  local order: { Block } = table.clone(blocks)
  table.sort(order, function(a: Block, b: Block): boolean
    local ka, kb = a.half.x * a.half.y * a.half.z, b.half.x * b.half.y * b.half.z
    if ka ~= kb then
      return ka > kb
    end
    return a.center.y < b.center.y or (a.center.y == b.center.y and (a.center.x < b.center.x or (a.center.x == b.center.x and a.center.z < b.center.z)))
  end)
  local wanted = (1 + size) * (if asym then 1 else 2)
  local sides = { v(1, 0, 0), v(-1, 0, 0), v(0, 0, 1), v(0, 0, -1) }
  for _, block in order do
    if #mouths >= wanted then
      break
    end
    for _, n in sides do
      if #mouths >= wanted then
        break
      end
      local alongFace = if n.x ~= 0 then block.half.z else block.half.x
      local out = math.abs(vector.dot(block.half, n))
      local wide, high = alongFace * 0.55, block.half.y * 0.45
      if wide > 0.25 and high > 0.15 then
        local face = block.center + n * out
        local a = if n.x ~= 0 then v(0, 0, 1) else v(1, 0, 0)
        local clear = true
        for _, corner in { { 0, 0 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
          local q = face + a * (corner[1] * wide) + v(0, corner[2] * high, 0)
          if inside(q + n * 0.02) or inside(q + n * 0.6) then
            clear = false
          end
        end
        -- (and not where a mouth already is)
        for _, other in mouths do
          if vector.magnitude(other.at - face) < 0.5 then
            clear = false
          end
        end
        if clear then
          table.insert(mouths, { at = face + n * 0.02, n = n, wide = wide, high = high })
          -- the dark of the hangar, let into the face
          local deep = math.min(out * 0.6, wide)
          local hole = v(math.abs(a.x) * wide + math.abs(n.x) * 0.01, high, math.abs(a.z) * wide + math.abs(n.z) * 0.01)
          table.insert(extra, { center = face + n * 0.005, size = hole, part = FRAME, single = true })
          -- lit round its edges
          local bar = 0.03
          for _, s in { 1, -1 } do
            table.insert(extra, { center = face + n * 0.012 + v(0, s * (high + bar), 0),
              size = v(math.abs(a.x) * (wide + bar) + math.abs(n.x) * 0.012, bar, math.abs(a.z) * (wide + bar) + math.abs(n.z) * 0.012),
              part = GLOW, single = true })
            table.insert(extra, { center = face + n * 0.012 + a * (s * (wide + bar)),
              size = v(math.abs(a.x) * bar + math.abs(n.x) * 0.012, high, math.abs(a.z) * bar + math.abs(n.z) * 0.012),
              part = GLOW, single = true })
          end
          local _ = deep
        end
      end
    end
  end

  local plates: { Hull.Plate } = {}
  for _, block in blocks do
    table.insert(plates, { center = block.center, size = block.half, part = block.part, single = true })
  end
  table.move(extra, 1, #extra, #plates + 1, plates)
  return plates, mouths
end

export type Made = { model: Model, radius: number, lower: vector, upper: vector }

local made: { [string]: Made } = {}

local SHIELD_TINT = v(0.45, 0.75, 1.0)

-- How a citadel is painted where nobody has painted it (the owner,
-- 2026-11-17: "a very dark grey base"): near-black plating, a shade
-- lighter where it is patched, darker structure, little wear. Its
-- plating is in many more sheets to a unit than a ship's (the owner:
-- "The rivet lines look huge for a structure this size"): a citadel is
-- kilometres across, drawn the size of a hull. (The sheets go up with
-- its size: CITADEL_SHEETS a size.)
Citadel.LOOK = {
  plating = { 0.10, 0.10, 0.11 }, patch = { 0.15, 0.15, 0.16 }, frame = { 0.07, 0.07, 0.075 },
  glow = { 0.70, 0.90, 1.0 }, trim = { 0.20, 0.20, 0.22 }, wear = 0.15, rust = 0.05, sheets = 3.2,
} :: Plates.Look
local CITADEL_SHEETS = 9
-- How far a block's edges are eased: hardly at all ("not rounded edges").
local EASED = 0.015

-- The air shields of a citadel's hangar mouths, as one shell: a quad
-- across each, a hair out from the face, in the model's units.
local function shields(mouths: { Mouth }): Mesh?
  if #mouths == 0 then
    return nil
  end
  local mesh = Mesh_Create()
  local count = 0
  local G = Hull.GROWN
  for _, mouth in mouths do
    local a = if mouth.n.x ~= 0 then v(0, 0, 1) else v(1, 0, 0)
    local up = v(0, 1, 0)
    local mid = (mouth.at + mouth.n * 0.03) * G
    local w, h = mouth.wide * G, mouth.high * G
    local corners = { mid - a * w - up * h, mid + a * w - up * h, mid + a * w + up * h, mid - a * w + up * h }
    local uvs = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } }
    for index, corner in corners do
      Mesh_AddVertex(mesh, corner, mouth.n, uvs[index][1], uvs[index][2])
    end
    Mesh_AddTriangle(mesh, count, count + 1, count + 2)
    Mesh_AddTriangle(mesh, count, count + 2, count + 3)
    count += 4
  end
  return mesh
end

local shieldShader: ShaderInstance? = nil
local function shieldOf(): ShaderInstance
  if shieldShader == nil then
    local shader = ShaderInstance_Create(Shader_Create("npm.jsl", "airshield.jsl"))
    ShaderInstance_SetState(shader, "BlendModeAdditive")
    ShaderInstance_SetState(shader, "ZWritableOff")
    ShaderInstance_SetState(shader, "CullModeDisabled")
    ShaderInstance_SetVec3(shader, "shieldTint", SHIELD_TINT)
    ShaderInstance_SetFloat(shader, "shieldGlow", 0.8)
    ShaderInstance_Link(shader)
    shieldShader = shader
  end
  return shieldShader :: ShaderInstance
end

-- A citadel drawn: grown from 'seed' at 'size' (asymmetrical with
-- 'asym'), in a paint (Hull.looks; Citadel.LOOK, a very dark grey, if none), with
-- surface detail ('detail', words of Hull.DETAILS), detailed as a thing
-- 'metres' across would be. Made once for each and kept.
function Citadel.Build(seed: number, size: number, paint: string?, detail: string?, metres: number?, asym: boolean?): Made
  local key = `{seed}:{size}:{paint or ""}:{detail or ""}:{asym == true}`
  local kept = made[key]
  if kept then
    return kept
  end
  local plates, mouths = Citadel.Grow(seed, size, asym)
  local b = Plates.New(seed * 1.91 + size, 0.04)
  Hull.DrawPlates(b, plates, EASED)
  local words: { string } = {}
  for word in string.gmatch(detail or "", "%a+") do
    table.insert(words, word)
  end
  local wanted = Hull.DetailOf(words)
  if wanted then
    -- (the detail keeps off the hangar mouths: they are what it is seen from)
    local off: { vector } = {}
    local most = 0
    for _, mouth in mouths do
      table.insert(off, mouth.at)
      most = math.max(most, mouth.wide, mouth.high)
    end
    Hull.DetailPlates(b, plates, seed * 13 + size, wanted, metres or 1500 * size, off, most * 1.15)
  end
  local look = if paint then Hull.looks[paint] or Citadel.LOOK else Citadel.LOOK
  local model, lower, upper = Plates.Finish(b, look, CITADEL_SHEETS * (1 + size))
  local sheet = shields(mouths)
  if sheet then
    Model_AddShell(model, sheet, shieldOf())
  end
  local across = upper - lower
  local result = { model = model, radius = math.max(across.x, across.y, across.z) / 2, lower = lower, upper = upper }
  made[key] = result
  return result
end

-- The citadel a size is drawn as in the game (Citadel.PICKS).
function Citadel.OfSize(size: number, paint: string?): Made
  local pick = Citadel.PICKS[size] or Citadel.PICKS[1]
  return Citadel.Build(pick.seed, size, paint, pick.detail, nil, pick.asym)
end

return Citadel
