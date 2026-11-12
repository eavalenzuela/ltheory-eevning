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
-- "Les Larmes de Nova": an arrowhead, and nothing behind it. From the
-- point of the bow back to the points of two barbs; the stern in the
-- notch between the barbs, with the engines across it; the docking bays
-- along the flat of the underside; a conning tower on the back before
-- the stern, as tall as a tall building and very small on the ship; and
-- smaller buildings along the spine.

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

-- How far forward of the barbs' points the stern lies, for a ship
-- 'across' broad: the notch of the arrowhead, deeper the broader it is.
local function notchOf(across: number): number
  return math.clamp(across, 0.16, 0.36)
end

-- Where along it the conning tower of a ship 'across' broad stands (in
-- units of a ship two long, the bow at 1).
function Capital.Conning(across: number?): number
  return -1 + notchOf(across or 0.2) + 0.09
end

-- "Les Larmes de Nova", 'across' units broad at the barbs (a fifth of a
-- unit is the kilometre of a ship ten long).
local function larmes(b: Builder, across: number)
  local w = across / 2
  -- How deep it is: its back at the highest, its keel, and the flat
  -- strip along the keel that the docks are let into.
  local top, keel = 0.030 + 0.05 * w, 0.014 + 0.03 * w
  local strip = 0.34 * w
  -- The stern: the flat between the barbs, which run on back past it.
  local sternW = 0.42 * w
  local sternZ = -1 + notchOf(across)
  local peakZ = sternZ + 0.22

  -- The head: from the point of the bow back to the points of the two
  -- barbs, and in and forward from those to the stern. Its edge is
  -- sharp all the way round.
  for _, side in { 1, -1 } do
    local bow = v(0, 0, 1)
    local barb = v(side * w, 0, -1)
    local corner = v(side * sternW, 0, sternZ)
    local peak = v(0, top, peakZ)
    local ridge = v(0, top * 0.92, sternZ)
    local out = v(side * 0.2, 1, 0)
    facet(b, PLATING, bow, barb, peak, out)
    facet(b, PLATING, peak, barb, corner, out)
    facet(b, PLATING, peak, corner, ridge, out)
    -- (underneath: down to the flat strip along the keel)
    local nose = v(0, -keel, 0.42)
    local aft = v(side * strip, -keel, sternZ)
    local under = v(side * 0.2, -1, 0)
    facet(b, PLATING, bow, nose, barb, under)
    facet(b, PLATING, nose, aft, barb, under)
    facet(b, PLATING, aft, corner, barb, under)
    facet(b, PATCH, nose, aft, v(0, -keel, sternZ), DOWN)
    -- (the stern)
    flat(b, FRAME, { ridge, corner, aft, v(0, -keel, sternZ) }, v(0, 0, -1))
    -- (the edges, marked)
    beam(b, TRIM, bow, barb, 0.0035 * SCALE, 0.1)
    beam(b, TRIM, barb, corner, 0.003 * SCALE, 0.1)
  end
  -- The engines: a row of throats across the stern, lit.
  for index = 1, 5 do
    local x = (index - 3) * sternW * 0.30
    local middle = index == 3
    local high = top * (if middle then 0.40 else 0.25)
    local y = top * (if middle then 0.15 else 0.05)
    block(b, FRAME, v(x, y, sternZ - 0.004), v(sternW * 0.125, high, 0.008), nil, 0.25)
    block(b, FIRE, v(x, y, sternZ - 0.011), v(sternW * 0.095, high * 0.78, 0.003), nil, 0.3)
  end

  -- The docks: bays let into the flat of the underside, a row of them
  -- down the keel, bigger as it widens, and a great one before the
  -- stern, each lit within.
  local span = 0.42 - sternZ
  local function bay(along: number, long: number)
    local z, wide = 0.42 - along * span, strip * along * 0.62
    block(b, FRAME, v(0, -keel - 0.0012, z), v(wide, 0.0022, long), nil, 0.05)
    block(b, GLOW, v(0, -keel - 0.0030, z), v(wide * 0.78, 0.0008, long * 0.86), nil, 0.05)
    block(b, TRIM, v(0, -keel - 0.0034, z), v(wide * 0.10, 0.0010, long * 0.92), nil, 0.05)
  end
  for _, along in { 0.36, 0.50, 0.64, 0.78 } do
    bay(along, 0.046)
  end
  bay(0.925, 0.052)

  -- The conning tower: on the back, before the stern, a narrow blade
  -- with the bridge across the top of it. Four hundred metres of it.
  local towerZ = Capital.Conning(across)
  local foot = v(0, top * 0.93, towerZ)
  block(b, PLATING, foot + v(0, 0.036, 0), v(0.0065, 0.040, 0.020), nil, 0.05)
  block(b, PATCH, foot + v(0, 0.020, -0.012), v(0.010, 0.022, 0.016), nil, 0.05)
  block(b, PATCH, foot + v(0, 0.079, 0.004), v(0.024, 0.0055, 0.012), nil, 0.08)
  block(b, GLOW, foot + v(0, 0.079, 0.0165), v(0.021, 0.0020, 0.0010), nil, 0.1)
  beam(b, FRAME, foot + v(0, 0.084, -0.004), foot + v(0, 0.096, -0.004), 0.0012 * SCALE, 0.1)

  -- The buildings along the spine: blocks of all sizes, astride the
  -- ridge from behind the bow to the foot of the tower, the bigger ones
  -- sternward, and one more behind it.
  local sizes: { { number } } = {
    { 0.006, 0.006, 0.020 }, { 0.009, 0.008, 0.030 }, { 0.007, 0.012, 0.018 }, { 0.012, 0.009, 0.034 },
    { 0.010, 0.016, 0.022 }, { 0.014, 0.010, 0.038 }, { 0.008, 0.007, 0.020 }, { 0.011, 0.020, 0.024 },
    { 0.016, 0.012, 0.036 }, { 0.009, 0.010, 0.022 }, { 0.012, 0.024, 0.022 }, { 0.018, 0.014, 0.030 },
  }
  local function house(index: number, z: number, size: { number })
    local height = if z > peakZ then top * (1 - z) / (1 - peakZ) else top * (0.92 + 0.08 * (z - sternZ) / (peakZ - sternZ))
    block(b, if index % 3 == 0 then PATCH else PLATING, v(0, height + size[2] * 0.5, z), v(size[1], size[2], size[3]), nil, 0.06)
    if index % 2 == 0 then
      for _, side in { 1, -1 } do
        block(b, GLOW, v(side * size[1], height + size[2] * 0.7, z), v(0.0006, size[2] * 0.18, size[3] * 0.7), nil, 0.1)
      end
    end
  end
  local first, last = 0.50, towerZ + 0.07
  for index, size in sizes do
    house(index, first + (last - first) * (index - 1) / (#sizes - 1), size)
  end
  house(1, towerZ - 0.055, { 0.010, 0.008, 0.016 })
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

-- The model of a colony ship of a class (Core/Data/Structures).
function Capital.Build(_class: string): Made
  -- (there is the one class so far)
  return Capital.Larmes()
end

return Capital
