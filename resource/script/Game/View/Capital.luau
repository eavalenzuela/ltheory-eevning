--!strict
-- The Kethri's colony ships: what they have where another people has a
-- station. A people with no fixed place, they live aboard these: ten
-- kilometres of ship, with the docks, the yards and the markets a
-- station would have. (The first of a class of ship above capitals.)
--
-- Drawn with Game/View/Plates, in flat plates with sharp edges
-- (Plates.Facet), lying along z with the bow at +z. It is laid out as
-- every hull is, two long; and built five times that, a unit of the
-- model to a kilometre of the ship, which is the scale the plating's
-- seams, its wear and the shade baked into it are made for.
--
--   local ship = Capital.Larmes()     -- { model, radius }
--
-- "Les Larmes de Nova": an arrowhead. A long blade from the point of
-- the bow back to two barbs; a tail between the barbs, with the engines
-- in the end of it; the docking bays along the flat of the underside; a
-- conning tower on the back of the tail, as tall as a tall building and
-- very small on the ship; and smaller buildings along the spine.

local Hull = require("@lt/Game/View/Hull")
local Plates = require("@lt/Game/View/Plates")

local Capital = {}

local PLATING, PATCH, FRAME, GLOW, TRIM, FIRE = Plates.PLATING, Plates.PATCH, Plates.FRAME, Plates.GLOW, Plates.TRIM, Plates.FIRE
local block, beam, facet, flat = Plates.Block, Plates.Beam, Plates.Facet, Plates.Flat

type Builder = Plates.Builder

export type Made = { model: Model, radius: number }

-- Units of the model to a unit of the layout.
local SCALE = 5

local function v(x: number, y: number, z: number): vector
  return vector.create(x * SCALE, y * SCALE, z * SCALE)
end

local DOWN = v(0, -1, 0)

-- "Les Larmes de Nova", 'beam' units across at the barbs (a fifth of a
-- unit is the kilometre of a ship ten long).
local function larmes(b: Builder, across: number)
  local w = across / 2
  -- How deep it is: its back at the highest, its keel, and the flat
  -- strip along the keel that the docks are let into.
  local top, keel = 0.030 + 0.05 * w, 0.014 + 0.03 * w
  local strip = 0.34 * w
  local tailW, sternW = 0.40 * w, 0.33 * w
  local barbZ, notchZ, peakZ = -0.60, -0.45, -0.34
  local wall = 0.45 * top

  -- The blade: from the bow to the barbs, and in to the notches where
  -- the tail begins. Its edge is sharp all the way round.
  for _, side in { 1, -1 } do
    local bow = v(0, 0, 1)
    local barb = v(side * w, 0, barbZ)
    local notch = v(side * tailW, 0, notchZ)
    local peak = v(0, top, peakZ)
    local ridge = v(0, top, notchZ)
    local out = v(side * 0.2, 1, 0)
    facet(b, PLATING, bow, barb, peak, out)
    facet(b, PLATING, peak, barb, notch, out)
    facet(b, PLATING, peak, notch, ridge, out)
    -- (underneath: down to the flat strip along the keel)
    local nose = v(0, -keel, 0.42)
    local aft = v(side * strip, -keel, notchZ)
    local under = v(side * 0.2, -1, 0)
    facet(b, PLATING, bow, nose, barb, under)
    facet(b, PLATING, nose, aft, barb, under)
    facet(b, PLATING, aft, notch, barb, under)
    facet(b, PATCH, nose, aft, v(0, -keel, notchZ), DOWN)
    -- (the edges, marked)
    beam(b, TRIM, bow, barb, 0.0035 * SCALE, 0.1)
    beam(b, TRIM, barb, notch, 0.003 * SCALE, 0.1)
  end

  -- The tail: a long house between the barbs, its roof a ridge, flat
  -- underneath, with the engines in its end.
  local front, stern = notchZ + 0.03, -1
  for _, side in { 1, -1 } do
    local out = v(side, 0.2, 0)
    local a, c = v(side * tailW, wall, front), v(side * sternW, wall * 0.9, stern)
    local a0, c0 = v(side * tailW, -keel, front), v(side * sternW, -keel, stern)
    local r1, r2 = v(0, top, front), v(0, top * 0.82, stern)
    flat(b, PLATING, { r1, a, c, r2 }, v(side * 0.3, 1, 0))
    flat(b, PLATING, { a, a0, c0, c }, out)
    flat(b, PATCH, { a0, v(0, -keel, front), v(0, -keel, stern), c0 }, DOWN)
    -- (the end of it, and its front, where it stands out of the blade)
    flat(b, FRAME, { r2, c, c0, v(0, -keel, stern) }, v(0, 0, -1))
    flat(b, PLATING, { r1, a, a0, v(0, -keel, front) }, v(0, 0, 1))
  end
  -- The engines: a row of throats across the end, lit.
  for index = 1, 5 do
    local x = (index - 3) * sternW * 0.36
    local high = if index == 3 then 0.55 else 0.42
    block(b, FRAME, v(x, top * 0.18, stern - 0.004), v(sternW * 0.15, top * high, 0.008), nil, 0.25)
    block(b, FIRE, v(x, top * 0.18, stern - 0.011), v(sternW * 0.115, top * high * 0.78, 0.003), nil, 0.3)
  end

  -- The docks: bays let into the flat of the underside, a row of them
  -- down the keel, bigger as it widens, and a great one under the tail,
  -- each lit within.
  local function bay(x: number, z: number, wide: number, long: number)
    block(b, FRAME, v(x, -keel - 0.0012, z), v(wide, 0.0022, long), nil, 0.05)
    block(b, GLOW, v(x, -keel - 0.0030, z), v(wide * 0.78, 0.0008, long * 0.86), nil, 0.05)
    block(b, TRIM, v(x, -keel - 0.0034, z), v(wide * 0.10, 0.0010, long * 0.92), nil, 0.05)
  end
  for index = 1, 4 do
    local z = 0.16 - index * 0.135
    local room = strip * (0.42 - z) / (0.42 - notchZ)
    bay(0, z, room * 0.62, 0.046)
  end
  bay(0, -0.72, sternW * 0.62, 0.15)

  -- The conning tower: on the back of the tail, a narrow blade with the
  -- bridge across the top of it. Four hundred metres of it.
  local foot = v(0, top * 0.97, front - 0.10)
  block(b, PLATING, foot + v(0, 0.036, 0), v(0.0065, 0.040, 0.020), nil, 0.05)
  block(b, PATCH, foot + v(0, 0.020, -0.012), v(0.010, 0.022, 0.016), nil, 0.05)
  block(b, PATCH, foot + v(0, 0.079, 0.004), v(0.024, 0.0055, 0.012), nil, 0.08)
  block(b, GLOW, foot + v(0, 0.079, 0.0165), v(0.021, 0.0020, 0.0010), nil, 0.1)
  beam(b, FRAME, foot + v(0, 0.084, -0.004), foot + v(0, 0.096, -0.004), 0.0012 * SCALE, 0.1)

  -- The buildings along the spine: blocks of all sizes, astride the
  -- ridge from behind the bow to the foot of the tower, and a few on
  -- the roof of the tail behind it.
  local spine: { { number } } = {
    { 0.46, 0.006, 0.006, 0.020 }, { 0.36, 0.009, 0.008, 0.030 }, { 0.27, 0.007, 0.012, 0.018 }, { 0.17, 0.012, 0.009, 0.034 },
    { 0.07, 0.010, 0.016, 0.022 }, { -0.03, 0.014, 0.010, 0.040 }, { -0.13, 0.011, 0.020, 0.024 }, { -0.22, 0.016, 0.012, 0.036 },
    { -0.30, 0.012, 0.024, 0.022 }, { -0.38, 0.018, 0.014, 0.030 },
  }
  for index, each in spine do
    local z = each[1]
    local y = top * (1 - z) / (1 - peakZ)
    local height = math.min(y, top)
    block(b, if index % 3 == 0 then PATCH else PLATING, v(0, height + each[3] * 0.5, z), v(each[2], each[3], each[4]), nil, 0.06)
    if index % 2 == 0 then
      block(b, GLOW, v(each[2], height + each[3] * 0.7, z), v(0.0006, each[3] * 0.18, each[4] * 0.7), nil, 0.1)
      block(b, GLOW, v(-each[2], height + each[3] * 0.7, z), v(0.0006, each[3] * 0.18, each[4] * 0.7), nil, 0.1)
    end
  end
  for index, z in { -0.66, -0.76, -0.86, -0.94 } do
    local size = 0.008 + 0.003 * (index % 2)
    block(b, if index % 2 == 0 then PATCH else PLATING, v(0, top * 0.9 + size * 0.6, z), v(size * 1.3, size, 0.022), nil, 0.06)
  end
end

local made: { [number]: Made } = {}

-- The model of a colony ship of the class "Les Larmes de Nova", and
-- half the length of the model. 'across' is how wide it is at the
-- barbs, in units of a ship two long (a fifth, if not said: a kilometre
-- of beam to ten of length).
function Capital.Larmes(across: number?): Made
  local beamWidth = across or 0.2
  local kept = made[beamWidth]
  if kept then
    return kept
  end
  local b = Plates.New(7.31 + beamWidth, 0.02 * SCALE)
  -- (plate after plate the same grey, near enough)
  b.even = 0.75
  larmes(b, beamWidth)
  -- (sheets of eighty metres: it is their smallness that says how big it is)
  local model, lower, upper = Plates.Finish(b, Hull.looks.kethri, 60 / SCALE)
  local size = upper - lower
  local result = { model = model, radius = math.max(size.x, size.y, size.z) / 2 }
  made[beamWidth] = result
  return result
end

return Capital
