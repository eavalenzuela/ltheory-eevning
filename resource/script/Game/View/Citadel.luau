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
local Structures = require("@lt/Core/Data/Structures")
local Tower = require("@lt/Game/View/Tower")

local Citadel = {}

local PLATING, PATCH, FRAME, GLOW = Plates.PLATING, Plates.PATCH, Plates.FRAME, Plates.GLOW
local v = vector.create

-- The styles a citadel is grown in (the owner, 2026-11-17: "let's add
-- more styles to the citadel generator: diamond, pyramid, wormhole
-- (wormhole in center, surrounded by counter-rotating rings, like the
-- gantry in Contact)"):
--   blocks    blocks that cut into each other, grown off one another
--   pyramid   a four-sided pyramid in flat plate on a plinth, ledges
--             cut through it, hangars in blocks round its foot
--   diamond   a cut stone: a flat table, a crown sloping out to the
--             girdle and a deep point under it (eight sides, or four),
--             hangars in blocks round the girdle
--   wormhole  a lightless sphere in the middle, rings round it each
--             turning its own way about an axis of its own, and outside
--             them a level ring that stands still, with hangars at its
--             quarters and towers standing through it
Citadel.STYLES = { "blocks", "pyramid", "diamond", "wormhole" }

-- What each kind of citadel (Data/Structures' CITADEL_KINDS) is drawn
-- as at each size: its seed, whether it is asymmetrical, the kinds of its
-- surface detail, its style, and its paint (the owner's, 2026-11-17: a
-- design wears the paint it was picked in, "for now", where its owner
-- is a pilot; a faction's citadel wears the faction's). The small ones
-- are the owner's first picks, 2026-11-17; a size not yet picked is the
-- small one's seed grown to it, a stand-in.
export type Pick = { seed: number, asym: boolean, detail: string, style: string, paint: string }
local ALL = "antennas pipes greebles lights rivets"
local SMALL: { [string]: Pick } = {
  habitation = { seed = 74919, asym = true, detail = ALL, style = "blocks", paint = "vessari" },
  tradehub = { seed = 50243, asym = true, detail = ALL, style = "blocks", paint = "talmar" },
  refinery = { seed = 47535, asym = false, detail = ALL, style = "blocks", paint = "orun" },
  research = { seed = 20247, asym = false, detail = ALL, style = "blocks", paint = "vail" },
  shipyard = { seed = 47336, asym = false, detail = ALL, style = "blocks", paint = "civil" },
}
Citadel.PICKS = {} :: { [string]: { Pick } }
for kind, small in SMALL do
  Citadel.PICKS[kind] = { small, small, small, small, small }
end

-- The pick a kind of citadel is drawn from at a size (a habitation's, if no such kind).
function Citadel.Pick(kind: string?, size: number): Pick
  local picks = Citadel.PICKS[kind or "habitation"] or Citadel.PICKS.habitation
  return picks[size] or picks[1]
end

-- A hangar's mouth: the middle of the opening, the way out of it, and
-- half of it across and up (in the generator's units).
export type Mouth = { at: vector, n: vector, wide: number, high: number }

-- A solid in flat plates (a pyramid, a cut stone): its faces, each its
-- corners in order round it, and a point inside it. Convex.
export type Solid = { faces: { { vector } }, part: number, middle: vector }
-- A ring of a wormhole citadel, round its middle: how far out, how
-- thick, the way its plane faces, what it turns about (in its plane),
-- how fast (radians a second; the next one the other way; 0 for the
-- outermost, which stands still and is part of the citadel's own
-- model) and how far round it starts.
export type Ring = { radius: number, thick: number, normal: vector, axis: vector, rate: number, phase: number }
-- A citadel grown, in the hull generator's units: its blocks as plates,
-- its hangar mouths, its solids, its rings, and the radius of the sphere
-- of its wormhole (0 for none).
export type Shape = { plates: { Hull.Plate }, mouths: { Mouth }, solids: { Solid }, rings: { Ring }, hole: number }

type Block = { center: vector, half: vector, part: number, dock: boolean? }

-- Whether a point is inside a convex solid (a hair in from its faces).
local function within(solid: Solid, p: vector): boolean
  for _, face in solid.faces do
    local a = face[1]
    local n = vector.cross(face[2] - a, face[3] - a)
    if vector.dot(n, a - solid.middle) < 0 then
      n = -n
    end
    if vector.dot(p - a, n) > -1e-4 * vector.magnitude(n) then
      return false
    end
  end
  return true
end

-- A citadel grown from a seed at a size (1 to 5), in a style
-- (Citadel.STYLES; blocks, if not said), in the hull generator's units.
function Citadel.Shape(seed: number, size: number, asym: boolean?, style: string?): Shape
  local which = table.find(Citadel.STYLES, style or "blocks") or 1
  -- (the blocks are grown from the dice they always were)
  local rng = RNG_MTG(Int.Signed(seed * 31 + size * 7 + 4001 + (which - 1) * 100003))
  local blocks: { Block } = {}
  local solids: { Solid } = {}
  local rings: { Ring } = {}
  local hole = 0
  local reach = 3.2 + 1.3 * size
  -- Put a block in, and its mirror images where it has them. ('dock':
  -- it is for hangars: where any is, only those have mouths.)
  local function add(center: vector, half: vector, part: number, dock: boolean?)
    table.insert(blocks, { center = center, half = half, part = part, dock = dock })
    if asym then
      return
    end
    local xs: { number } = if math.abs(center.x) > 1e-3 then { 1, -1 } else { 1 }
    local zs: { number } = if math.abs(center.z) > 1e-3 then { 1, -1 } else { 1 }
    for _, sx in xs do
      for _, sz in zs do
        if sx ~= 1 or sz ~= 1 then
          table.insert(blocks, { center = v(center.x * sx, center.y, center.z * sz), half = half, part = part, dock = dock })
        end
      end
    end
  end
  -- Put a block in on each of the four sides, each way round from the
  -- one given (its x and z swapped for the sides across): mirrored, or
  -- for one grown asymmetrical, on some of the sides only and each a
  -- little unlike the others.
  local function sides(center: vector, half: vector, part: number, dock: boolean?)
    if not asym then
      add(center, half, part, dock)
      add(v(center.z, center.y, center.x), v(half.z, half.y, half.x), part, dock)
      return
    end
    for index, way in { v(1, 1, 1), v(-1, 1, 1), v(1, 1, -1), v(-1, 1, -1) } do
      if index == 1 or rng:Float() < 0.7 then
        local grow = rng:Float(0.75, 1.3)
        local swap = index > 2
        local c = if swap then v(center.z * way.z, center.y, center.x * way.x) else v(center.x * way.x, center.y, center.z * way.z)
        local h = if swap then v(half.z, half.y * grow, half.x) else v(half.x, half.y * grow, half.z)
        table.insert(blocks, { center = c, half = h, part = part, dock = dock })
      end
    end
  end
  -- A solid of these faces.
  local function solid(faces: { { vector } }, part: number)
    local middle, count = v(0, 0, 0), 0
    for _, face in faces do
      for _, corner in face do
        middle += corner
        count += 1
      end
    end
    table.insert(solids, { faces = faces, part = part, middle = middle / math.max(1, count) })
  end
  local unit = 0.9 + 0.3 * size

  if which == 2 then
    -- A pyramid on a plinth, ledges through it, blocks at its corners
    -- and hangars round its foot; a mast at its point.
    local W = unit * rng:Float(2.0, 2.6)
    local H = W * rng:Float(1.0, 1.6)
    local y0 = -H * 0.38
    local apex = v(0, y0 + H, 0)
    if asym then
      apex += v(rng:Float(-0.35, 0.35) * W, 0, rng:Float(-0.35, 0.35) * W)
    end
    local base = { v(W, y0, W), v(-W, y0, W), v(-W, y0, -W), v(W, y0, -W) }
    local faces: { { vector } } = { base }
    for index = 1, 4 do
      table.insert(faces, { base[index], base[index % 4 + 1], apex })
    end
    solid(faces, PLATING)
    add(v(0, y0 - 0.15 * unit, 0), v(W * 1.12, 0.15 * unit, W * 1.12), PATCH)
    for _ = 1, rng:Int(0, 3) do
      local f = rng:Float(0.2, 0.75)
      local w = W * (1 - f)
      local at = v(0, y0, 0) * (1 - f) + apex * f
      add(v(at.x * 0, at.y, at.z * 0) + (if asym then v(at.x, 0, at.z) else v(0, 0, 0)), v(w * 1.07, 0.07 * unit, w * 1.07), PATCH)
    end
    if rng:Float() < 0.6 then
      local q = unit * rng:Float(0.35, 0.55)
      add(v(W, y0 + q, W), v(q, q, q), PLATING)
    end
    local annex = v(unit * rng:Float(0.5, 0.8), unit * rng:Float(0.4, 0.6), unit * rng:Float(0.6, 1.0))
    sides(v(W * 0.9 + annex.x * 0.6, y0 + annex.y, 0), annex, PATCH, true)
    add(apex + v(0, -0.1 * unit, 0), v(0.3 * unit, 0.12 * unit, 0.3 * unit), PATCH)
    add(apex + v(0, 0.35 * unit, 0), v(0.1 * unit, 0.55 * unit, 0.1 * unit), FRAME)

  elseif which == 3 then
    -- A cut stone: a flat table, a crown out to the girdle, and a deep
    -- point under it; a band round the girdle, hangars in blocks on it.
    local n = if rng:Float() < 0.3 then 4 else 8
    local G0 = unit * rng:Float(1.8, 2.3)
    local Hc = G0 * rng:Float(0.45, 0.7)
    local T = G0 * rng:Float(0.4, 0.6)
    local Hp = G0 * rng:Float(1.1, 1.6)
    local tableShift, culetShift = v(0, 0, 0), v(0, 0, 0)
    if asym then
      tableShift = v(rng:Float(-0.25, 0.25), 0, rng:Float(-0.25, 0.25)) * G0
      culetShift = v(rng:Float(-0.4, 0.4), 0, rng:Float(-0.4, 0.4)) * G0
    end
    local function ring(r: number, y: number, shift: vector): { vector }
      local corners: { vector } = {}
      local out = r / math.cos(math.pi / n)
      for index = 0, n - 1 do
        local a = math.pi / n + index * 2 * math.pi / n
        table.insert(corners, v(math.cos(a) * out, y, math.sin(a) * out) + shift)
      end
      return corners
    end
    local top, girdle = ring(T, Hc, tableShift), ring(G0, 0, v(0, 0, 0))
    local culet = v(0, -Hp, 0) + culetShift
    local faces: { { vector } } = { top }
    for index = 1, n do
      local after = index % n + 1
      table.insert(faces, { top[index], top[after], girdle[after], girdle[index] })
      table.insert(faces, { girdle[index], girdle[after], culet })
    end
    solid(faces, PLATING)
    if rng:Float() < 0.6 then
      add(v(0, 0, 0), v(G0 * 1.03, 0.09 * unit, G0 * 1.03), PATCH)
    end
    local dock = v(unit * rng:Float(0.45, 0.65), unit * rng:Float(0.38, 0.5), unit * rng:Float(0.7, 1.0))
    sides(v(G0 + dock.x * 0.5, 0, 0), dock, PATCH, true)
    add(v(tableShift.x, Hc + 0.06 * unit, tableShift.z), v(T * 0.55, 0.06 * unit, T * 0.55), PATCH)
    add(v(tableShift.x, Hc + 0.45 * unit, tableShift.z), v(0.13 * unit, 0.42 * unit, 0.13 * unit), FRAME)
    add(culet + v(0, -0.3 * unit, 0), v(0.08 * unit, 0.45 * unit, 0.08 * unit), FRAME)

  elseif which == 4 then
    -- A wormhole in a ring that stands still: the sphere in the middle,
    -- rings round it that turn (each in a plane of its own, about an
    -- axis in that plane, the next the other way), and outside those the
    -- outermost ring, which does not turn, and which everything else of
    -- the citadel is built onto: hangars at its four quarters, towers
    -- standing through it between them (the owner, 2026-11-17: "the
    -- outermost ring should be stationary, which is where the other
    -- components can attach to").
    hole = unit * rng:Float(0.8, 1.0)
    local count = 2 + rng:Int(0, 2)
    local thick = unit * rng:Float(0.07, 0.11)
    local planes = { { normal = v(0, 0, 1), axis = v(0, 1, 0) }, { normal = v(1, 0, 0), axis = v(0, 0, 1) },
      { normal = v(0, 1, 0), axis = v(1, 0, 0) }, { normal = v(0, 0, 1), axis = v(1, 0, 0) } }
    local outer = hole
    for index = 1, count do
      local radius = hole * 1.2 + index * (thick * 2.2 + unit * rng:Float(0.25, 0.4))
      local plane = planes[index]
      local rate = rng:Float(0.08, 0.18) * (if index % 2 == 0 then -1 else 1)
      table.insert(rings, { radius = radius, thick = thick, normal = plane.normal, axis = plane.axis, rate = rate, phase = rng:Float() })
      outer = radius + thick
    end
    -- (the ring that stands still: level, heavier, clear of the others' sweep)
    local still = thick * rng:Float(2.0, 2.8)
    local R = outer + unit * rng:Float(0.3, 0.45) + still
    table.insert(rings, { radius = R, thick = still, normal = v(0, 1, 0), axis = v(0, 1, 0), rate = 0, phase = 0 })
    -- Hangars at its quarters, out from it.
    local dock = v(unit * rng:Float(0.5, 0.75), unit * rng:Float(0.38, 0.55), unit * rng:Float(0.55, 0.85))
    sides(v(R + dock.x * 0.55, 0, 0), dock, PATCH, true)
    -- Towers standing through it, between them.
    local post = unit * rng:Float(0.28, 0.42)
    local high = unit * rng:Float(0.8, 1.6)
    local d = R * math.sqrt(0.5)
    if asym then
      for _, way in { v(1, 0, 1), v(-1, 0, 1), v(1, 0, -1), v(-1, 0, -1) } do
        if rng:Float() < 0.75 then
          local tall = high * rng:Float(0.6, 1.4)
          table.insert(blocks, { center = v(d * way.x, rng:Float(-0.3, 0.3) * tall, d * way.z), half = v(post, tall, post), part = PLATING })
        end
      end
    else
      add(v(d, 0, d), v(post, high, post), PLATING)
    end
    -- And what more is fixed to it here and there: blocks astride it.
    for _ = 1, rng:Int(1, 3) do
      local a = rng:Float(0.15, 0.35) * math.pi
      local q = unit * rng:Float(0.2, 0.32)
      add(v(math.cos(a) * R, rng:Float(-0.1, 0.1) * unit, math.sin(a) * R), v(q * 1.4, q, q * 1.4), PATCH)
    end

  else
  -- The core: a big block, a cube or a slab or a tower.
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
  end

  -- Whether a point is inside a block or a solid (a hair in from its faces).
  local function inside(p: vector): boolean
    for _, block in blocks do
      local d = p - block.center
      if math.abs(d.x) < block.half.x - 1e-4 and math.abs(d.y) < block.half.y - 1e-4 and math.abs(d.z) < block.half.z - 1e-4 then
        return true
      end
    end
    for _, each in solids do
      if within(each, p) then
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
  -- (only those for hangars, where some are)
  local order: { Block } = {}
  for _, block in blocks do
    if block.dock then
      table.insert(order, block)
    end
  end
  if #order == 0 then
    order = table.clone(blocks)
  end
  table.sort(order, function(a: Block, b: Block): boolean
    local ka, kb = a.half.x * a.half.y * a.half.z, b.half.x * b.half.y * b.half.z
    if ka ~= kb then
      return ka > kb
    end
    return a.center.y < b.center.y or (a.center.y == b.center.y and (a.center.x < b.center.x or (a.center.x == b.center.x and a.center.z < b.center.z)))
  end)
  local wanted = (1 + size) * (if asym then 1 else 2)
  local faces = { v(1, 0, 0), v(-1, 0, 0), v(0, 0, 1), v(0, 0, -1) }
  for _, block in order do
    if #mouths >= wanted then
      break
    end
    for _, n in faces do
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
          local dark = v(math.abs(a.x) * wide + math.abs(n.x) * 0.01, high, math.abs(a.z) * wide + math.abs(n.z) * 0.01)
          table.insert(extra, { center = face + n * 0.005, size = dark, part = FRAME, single = true })
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
  return { plates = plates, mouths = mouths, solids = solids, rings = rings, hole = hole }
end

-- The plates of a citadel grown from a seed at a size (1 to 5), and its
-- hangar mouths, in the hull generator's units (of its blocks: a
-- style's solids and rings are Citadel.Shape's).
function Citadel.Grow(seed: number, size: number, asym: boolean?, style: string?): ({ Hull.Plate }, { Mouth })
  local shape = Citadel.Shape(seed, size, asym, style)
  return shape.plates, shape.mouths
end

-- What of a citadel turns (a wormhole citadel's rings), each a model of
-- its own about its pivot (Game/View/Starbase's movers: Starbase.Animate
-- turns it).
export type Mover = { model: Model, pivot: vector, motion: Tower.Motion }
export type Made = { model: Model, radius: number, lower: vector, upper: vector, movers: { Mover }? }

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

local holeShader: ShaderInstance? = nil
local function holeOf(): ShaderInstance
  if holeShader == nil then
    -- (as a wormhole in space is drawn: Game/View/Scene)
    local shader = ShaderInstance_Create(Shader_Create("npm.jsl", "wormhole.jsl"))
    ShaderInstance_SetState(shader, "BlendModeAlpha")
    ShaderInstance_SetState(shader, "ZWritableOff")
    ShaderInstance_SetState(shader, "CullModeDisabled")
    ShaderInstance_Link(shader)
    holeShader = shader
  end
  return holeShader :: ShaderInstance
end

-- A ring drawn into a builder: so many lengths of plate round it, a lit
-- strip along its inside, and a pod at each quarter (in the model's
-- units).
local function drawRing(b: Plates.Builder, ring: Ring, size: number)
  local G = Hull.GROWN
  local n = ring.normal
  local e1 = vector.normalize(vector.cross(n, if math.abs(n.y) > 0.9 then v(1, 0, 0) else v(0, 1, 0)))
  local e2 = vector.cross(n, e1)
  local R, t = ring.radius * G, ring.thick * G
  local lengths = 32 + 4 * size
  local function at(index: number, r: number): vector
    local a = index / lengths * 2 * math.pi
    return (e1 * math.cos(a) + e2 * math.sin(a)) * r
  end
  for index = 0, lengths - 1 do
    Plates.Beam(b, PLATING, at(index, R), at(index + 1, R), t, EASED)
    Plates.Beam(b, GLOW, at(index, R - t * 1.05), at(index + 1, R - t * 1.05), t * 0.22, EASED)
    if index % (lengths // 4) == 0 then
      Plates.Block(b, PATCH, at(index, R), v(t, t, t) * 1.8, nil, EASED)
    end
  end
end

-- A citadel drawn: grown from 'seed' at 'size' (asymmetrical with
-- 'asym'), in a style (Citadel.STYLES; blocks, if not said), in a paint
-- (Hull.looks; Citadel.LOOK, a very dark grey, if none), with surface
-- detail ('detail', words of Hull.DETAILS), detailed as a thing 'metres'
-- across would be. Made once for each and kept.
function Citadel.Build(seed: number, size: number, paint: string?, detail: string?, metres: number?, asym: boolean?, style: string?): Made
  local key = `{seed}:{size}:{paint or ""}:{detail or ""}:{asym == true}:{style or "blocks"}`
  local kept = made[key]
  if kept then
    return kept
  end
  local shape = Citadel.Shape(seed, size, asym, style)
  local plates, mouths = shape.plates, shape.mouths
  local G = Hull.GROWN
  local b = Plates.New(seed * 1.91 + size, 0.04)
  Hull.DrawPlates(b, plates, EASED)
  -- (its solids in flat plate, and what stands on them knows they are there)
  for _, each in shape.solids do
    for _, face in each.faces do
      local corners: { vector } = {}
      local middle = v(0, 0, 0)
      for _, corner in face do
        table.insert(corners, corner * G)
        middle += corner
      end
      Plates.Flat(b, each.part, corners, (middle / #face - each.middle) * G)
    end
    Plates.Stands(b, function(p: vector): boolean
      return within(each, p / G)
    end)
  end
  -- (the ring that stands still is the citadel's own)
  for _, ring in shape.rings do
    if ring.rate == 0 then
      drawRing(b, ring, size)
    end
  end
  local words: { string } = {}
  -- (each kind may have a seed of its own after it: antennas:17)
  for word in string.gmatch(detail or "", "[%a%d:]+") do
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
  local sheets = CITADEL_SHEETS * (1 + size)
  local model, lower, upper = Plates.Finish(b, look, sheets)
  local sheet = shields(mouths)
  if sheet then
    Model_AddShell(model, sheet, shieldOf())
  end
  -- The wormhole: a sphere at the middle, drawn lightless (wormhole.jsl).
  if shape.hole > 0 then
    local r = shape.hole * G
    Model_AddShell(model, Mesh_Scale(Mesh_BoxSphere(16, true), v(r, r, r)), holeOf())
  end
  -- What turns: each ring a model of its own, about the middle.
  local movers: { Mover } = {}
  for index, ring in shape.rings do
    if ring.rate ~= 0 then
      local rb = Plates.New(seed * 3.7 + index * 11.3, 0.04)
      drawRing(rb, ring, size)
      local turning = Plates.Finish(rb, look, sheets)
      table.insert(movers, { model = turning, pivot = v(0, 0, 0),
        motion = { kind = "turn", axis = ring.axis, rate = ring.rate, phase = ring.phase } })
      local far = (ring.radius + ring.thick) * G
      lower, upper = vector.min(lower, v(-far, -far, -far)), vector.max(upper, v(far, far, far))
    end
  end
  local across = upper - lower
  local result: Made = { model = model, radius = math.max(across.x, across.y, across.z) / 2, lower = lower, upper = upper,
    movers = if #movers > 0 then movers else nil }
  made[key] = result
  return result
end

-- The citadel a kind and a size is drawn as in the game (Citadel.PICKS):
-- in a faction's paint, if it is a faction's, and else in its design's.
function Citadel.Of(kind: string?, size: number, faction: string?): Made
  local pick = Citadel.Pick(kind, size)
  local paint = if faction and faction ~= "" and Hull.looks[faction] then faction else pick.paint
  return Citadel.Build(pick.seed, size, paint, pick.detail, nil, pick.asym, pick.style)
end

-- The hangar doors of the citadel a kind and a size is drawn as (the
-- owner, 2026-11-17: "we should also make sure ships undocking exit
-- through one of the hangar doors"): each door's middle, from the
-- station's middle in the citadel's own radii (as Game/View/Starbase
-- stands it: its middle where the station is, as big as its reach),
-- and the way out of it. The game's rules cannot grow a citadel (that is
-- the engine's), so what this says is written into Core/Data/
-- CitadelDoors by script/citadeldoors, whenever a pick changes.
function Citadel.Doors(kind: string, size: number): { { at: vector, n: vector } }
  local pick = Citadel.Pick(kind, size)
  local made = Citadel.Build(pick.seed, size, pick.paint, pick.detail, nil, pick.asym, pick.style)
  local mid = (made.lower + made.upper) * 0.5
  local doors: { { at: vector, n: vector } } = {}
  for _, mouth in Citadel.Shape(pick.seed, size, pick.asym, pick.style).mouths do
    table.insert(doors, { at = (mouth.at * Hull.GROWN - mid) / made.radius, n = mouth.n })
  end
  return doors
end

-- Core/Data/CitadelDoors as it should be now, as text.
function Citadel.DoorsFile(): string
  local lines = {
    "--!strict",
    "-- The hangar doors of each kind of citadel at each size: written by",
    "-- script/citadeldoors from Game/View/Citadel (Citadel.Doors), which",
    "-- grows them; not to be edited by hand. Each door: where its middle",
    "-- is from the station's middle, in the citadel's radii, and the way",
    "-- out of it (x, y, z, then nx, ny, nz). Assets of Tactical/Space's",
    "-- undocking: a ship leaves a citadel by one of its doors.",
    "",
    "return {",
  }
  for _, kind in Structures.CITADEL_KINDS do
    table.insert(lines, `  {kind} = \{`)
    for size = 1, 5 do
      local doors: { string } = {}
      for _, door in Citadel.Doors(kind, size) do
        table.insert(doors, string.format("{ %.4f, %.4f, %.4f, %g, %g, %g }", door.at.x, door.at.y, door.at.z, door.n.x, door.n.y, door.n.z))
      end
      table.insert(lines, `    \{ {table.concat(doors, ", ")} \},`)
    end
    table.insert(lines, "  },")
  end
  table.insert(lines, "} :: { [string]: { { { number } } } }")
  return table.concat(lines, "\n") .. "\n"
end

return Citadel
