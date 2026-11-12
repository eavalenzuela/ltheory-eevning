--!strict
-- How a station looks: a control tower, the modules anchored round it,
-- and the field that holds them (Core/Data/Structures says what a
-- station is made of; this draws it).
--
-- A tower is its faction's, in three sizes, and each size is its own
-- drawing, not one drawing made bigger. It is a thing in space: it
-- stands on nothing, and must not look as if it did (the project
-- owner's correction of the first drawings, which were derricks on
-- feet). A tower is a spindle: widest at its waist, and narrowing from
-- there to both ends.
--
-- The Vessari's are the first: open girders round a plated core, a
-- deck at the waist with fuel drums hung round it, a control house
-- toward the top with its lights on, above that the crown of prongs
-- that throws the field, and below a tail that narrows to a point.
-- They are built from the same plates and painted with the same paint
-- as Vessari hulls (Game/View/Hull).
--
-- A module is nobody's (the project owner's decision): a battery, a
-- shipyard, a storage array is one design wherever it is anchored, in a
-- plain works paint of its own, as a ship's weapons are (Game/View/Arms).
-- A battery's gun or rack is in fact one of those weapons, at the size
-- of a structure.
--
--   local base = Starbase.Layout(variety, radius, seed)
--   -- base.tower, base.modules: each a model, a place and a size

local Arms = require("@lt/Game/View/Arms")
local Capital = require("@lt/Game/View/Capital")
local Hull = require("@lt/Game/View/Hull")
local Plates = require("@lt/Game/View/Plates")
local Structures = require("@lt/Core/Data/Structures")

local Starbase = {}

local PLATING, PATCH, FRAME, GLOW, TRIM = Plates.PLATING, Plates.PATCH, Plates.FRAME, Plates.GLOW, Plates.TRIM
local block, beam, truss, conduit = Plates.Block, Plates.Beam, Plates.Truss, Plates.Conduit

type Builder = Plates.Builder

local function v(x: number, y: number, z: number): vector
  return vector.create(x, y, z)
end

-- The paint of everything that is anchored round a tower, whoever's
-- the tower is: works grey, hazard yellow, cold white light.
local WORKS: Plates.Look = {
  plating = { 0.34, 0.37, 0.41 }, patch = { 0.55, 0.56, 0.55 }, frame = { 0.13, 0.14, 0.15 }, glow = { 0.78, 0.93, 1.0 },
  trim = { 0.74, 0.55, 0.08 }, wear = 0.5, rust = 0.3, sheets = 4.0,
}

-- ---------------------------------------------------------------------
-- Pieces

-- A drum standing on end, with two bands.
local function drum(b: Builder, center: vector, radius: number, height: number, part: number?)
  block(b, part or PATCH, center, v(radius, height / 2, radius), nil, 0.55)
  block(b, FRAME, center + v(0, height * 0.30, 0), v(radius * 1.06, height * 0.03, radius * 1.06), nil, 0.3)
  block(b, FRAME, center + v(0, -height * 0.30, 0), v(radius * 1.06, height * 0.03, radius * 1.06), nil, 0.3)
end

-- A mast: a pole with spars across it.
-- (With a height below zero it hangs down.)
local function mast(b: Builder, foot: vector, height: number, lean: number)
  local top = foot + v(lean, height, lean * 0.6)
  local size = math.abs(height)
  beam(b, FRAME, foot, top, size * 0.03, 0.1)
  for index, share in { 0.45, 0.70, 0.90 } do
    local at = foot + (top - foot) * share
    local reach = size * (0.24 - 0.055 * index)
    beam(b, FRAME, at + v(-reach, 0, 0), at + v(reach, 0, 0), size * 0.016, 0.1)
  end
end

-- Lit windows round a square block: a row on each of its four sides.
local function windows(b: Builder, center: vector, half: number, count: number, size: number)
  for index = 1, count do
    local along = ((index - 0.5) / count - 0.5) * 1.6 * half
    block(b, GLOW, center + v(along, 0, half), v(size * 1.5, size, size * 0.2), nil, 0.3)
    block(b, GLOW, center + v(along, 0, -half), v(size * 1.5, size, size * 0.2), nil, 0.3)
    block(b, GLOW, center + v(half, 0, along), v(size * 0.2, size, size * 1.5), nil, 0.3)
    block(b, GLOW, center + v(-half, 0, along), v(size * 0.2, size, size * 1.5), nil, 0.3)
  end
end

-- One stage of a tower: four corner posts from 'low' to 'high', as far
-- from the middle as 'below' at the bottom and 'above' at the top, so
-- that a stage narrows one way or the other; braced across each side
-- bay by bay; with a plated core through 'plated' of its height from
-- its wider end, stepping in as the stage narrows.
local function stage(b: Builder, low: number, high: number, below: number, above: number, plated: number)
  local wide = math.max(below, above)
  local post = wide * 0.07
  local function half(t: number): number
    return below + (above - below) * t
  end
  for _, x in { -1, 1 } do
    for _, z in { -1, 1 } do
      beam(b, FRAME, v(x * below, low, z * below), v(x * above, high, z * above), post, 0.1)
    end
  end
  local bays = math.max(2, math.floor((high - low) / (wide * 1.5) + 0.5))
  for bay = 0, bays do
    local y, h = low + (high - low) * bay / bays, half(bay / bays)
    for _, side in { -h, h } do
      beam(b, FRAME, v(-h, y, side), v(h, y, side), post * 0.7)
      beam(b, FRAME, v(side, y, -h), v(side, y, h), post * 0.7)
    end
    if bay < bays then
      local y2, h2 = low + (high - low) * (bay + 1) / bays, half((bay + 1) / bays)
      local lean = if bay % 2 == 0 then 1 else -1
      for _, side in { -1, 1 } do
        beam(b, FRAME, v(-h * lean, y, side * h), v(h2 * lean, y2, side * h2), post * 0.55)
        beam(b, FRAME, v(side * h, y, h * lean), v(side * h2, y2, -h2 * lean), post * 0.55)
      end
    end
  end
  for step = 1, 2 do
    -- (from the wider end: 'from' and 'to' are shares of the height)
    local near, far = (step - 1) / 2 * plated, step / 2 * plated
    local from, to = near, far
    if above > below then
      from, to = 1 - far, 1 - near
    end
    local narrow = half(if above > below then from else to)
    block(b, PLATING, v(0, low + (high - low) * (from + to) / 2, 0), v(narrow * 0.72, (high - low) * (to - from) / 2, narrow * 0.72), nil, 0.05)
  end
end

-- The crown that throws the field: a ring, prongs leaning in over it,
-- and the lit core they hold. ('down' turns it over, for one that
-- hangs under a tower.)
local function crown(b: Builder, at: vector, half: number, prongs: number, down: boolean?)
  local s = if down then -1 else 1
  block(b, FRAME, at, v(half, half * 0.07, half), nil, 0.3)
  block(b, TRIM, at + v(0, s * half * 0.09, 0), v(half * 0.8, half * 0.03, half * 0.8), nil, 0.3)
  for index = 1, prongs do
    local angle = (index - 0.5) / prongs * 2 * math.pi
    local out = v(math.cos(angle), 0, math.sin(angle))
    beam(b, PLATING, at + out * (half * 0.92), at + out * (half * 0.30) + v(0, s * half * 1.45, 0), half * 0.085, 0.2)
    beam(b, FRAME, at + out * (half * 0.55), at + out * (half * 0.74) + v(0, s * half * 0.55, 0), half * 0.04)
  end
  block(b, GLOW, at + v(0, s * half * 0.66, 0), v(half * 0.22, half * 0.34, half * 0.22), v(math.pi / 4, 0, 0), 0.45)
  block(b, FRAME, at + v(0, s * half * 0.20, 0), v(half * 0.30, half * 0.12, half * 0.30), nil, 0.2)
end

-- The Vessari's slanted plates: a pair, leaning together like a roof.
local function roof(b: Builder, at: vector, half: vector)
  block(b, PLATING, at + v(-half.x * 0.5, 0, 0), v(half.x * 0.56, half.y, half.z), v(0, 0, 0.45), 0.08)
  block(b, PATCH, at + v(half.x * 0.5, 0, 0), v(half.x * 0.56, half.y, half.z), v(0, 0, -0.45), 0.08)
end

-- What a tower ends in below: a spire from 'top' down, 'thick' at its
-- root and coming to a point, with a beacon lit part way down it and
-- spars across it.
local function tail(b: Builder, top: vector, length: number, thick: number)
  beam(b, PLATING, top, top + v(0, -length * 0.42, 0), thick, 0.2)
  beam(b, FRAME, top + v(0, -length * 0.38, 0), top + v(0, -length * 0.74, 0), thick * 0.6, 0.2)
  beam(b, FRAME, top + v(0, -length * 0.70, 0), top + v(0, -length, 0), thick * 0.28, 0.15)
  block(b, TRIM, top + v(0, -length * 0.40, 0), v(thick * 1.25, thick * 0.4, thick * 1.25), nil, 0.3)
  block(b, GLOW, top + v(0, -length * 0.56, 0), v(thick * 0.85, thick * 0.6, thick * 0.85), v(math.pi / 4, 0, 0), 0.45)
  for index, share in { 0.24, 0.66 } do
    local reach = thick * (4.2 - 1.6 * index)
    local at = top + v(0, -length * share, 0)
    beam(b, FRAME, at + v(-reach, 0, 0), at + v(reach, 0, 0), thick * 0.22, 0.1)
    beam(b, FRAME, at + v(0, 0, -reach), at + v(0, 0, reach), thick * 0.22, 0.1)
  end
end

-- ---------------------------------------------------------------------
-- The Vessari towers

-- Small: a stage up from the waist and a stage down, the house and the
-- crown above, the tail below.
local function vessariSmall(b: Builder)
  block(b, PLATING, v(0, 0, 0), v(0.34, 0.022, 0.34), nil, 0.2)
  block(b, TRIM, v(0, 0.03, 0), v(0.345, 0.010, 0.345), nil, 0.2)
  stage(b, 0.00, 0.62, 0.24, 0.15, 0.60)
  stage(b, -0.72, 0.00, 0.10, 0.24, 0.60)
  -- drums hung round the waist, over and under the deck
  drum(b, v(0.33, -0.22, 0.06), 0.09, 0.36)
  drum(b, v(-0.31, -0.18, -0.12), 0.075, 0.28, PLATING)
  drum(b, v(0.04, 0.19, -0.32), 0.065, 0.26)
  conduit(b, { v(0.33, -0.02, 0.06), v(0.26, 0.10, 0.06), v(0.19, 0.40, 0.06) }, 0.013)
  conduit(b, { v(-0.31, -0.34, -0.12), v(-0.20, -0.46, -0.10), v(-0.12, -0.66, -0.06) }, 0.011)
  block(b, PATCH, v(0.185, 0.24, 0.0), v(0.018, 0.17, 0.10), v(0, 0, 0.145))
  -- the control house, under the family's roof
  block(b, FRAME, v(0, 0.64, 0), v(0.19, 0.018, 0.19), nil, 0.2)
  block(b, PATCH, v(0.03, 0.765, 0.02), v(0.18, 0.105, 0.18), nil, 0.12)
  windows(b, v(0.03, 0.775, 0.02), 0.184, 3, 0.020)
  roof(b, v(0.03, 0.89, 0.02), v(0.20, 0.012, 0.19))
  crown(b, v(0, 0.99, 0), 0.20, 4)
  mast(b, v(-0.12, 0.88, -0.10), 0.50, -0.03)
  tail(b, v(0, -0.70, 0), 0.66, 0.05)
  -- a boom with its dish, out from the waist
  truss(b, v(0.30, 0.04, 0), v(0.70, 0.12, 0.04), 0.08, 3, v(0, 0, 1))
  block(b, PATCH, v(0.76, 0.16, 0.04), v(0.10, 0.012, 0.10), v(0, 0.5, 0.4), 0.3)
end

-- Medium: two stages each way, and arms out from the waist to its banks.
local function vessariMedium(b: Builder)
  block(b, PLATING, v(0, 0, 0), v(0.44, 0.024, 0.44), nil, 0.15)
  block(b, TRIM, v(0, 0.032, 0), v(0.445, 0.011, 0.445), nil, 0.15)
  stage(b, 0.00, 0.58, 0.32, 0.22, 0.65)
  stage(b, 0.58, 1.08, 0.22, 0.15, 0.50)
  stage(b, -0.62, 0.00, 0.20, 0.32, 0.65)
  stage(b, -1.16, -0.62, 0.10, 0.20, 0.50)
  for index, at in { v(0.44, -0.26, 0.10), v(-0.42, -0.22, -0.14), v(0.08, 0.26, -0.44), v(-0.12, -0.24, 0.43), v(0.36, 0.22, -0.30) } do
    drum(b, at, 0.12 - 0.012 * index, 0.46 - 0.04 * index, if index % 2 == 0 then PLATING else PATCH)
  end
  block(b, PATCH, v(0.255, 0.26, 0.02), v(0.020, 0.22, 0.13), v(0, 0, 0.17))
  block(b, PATCH, v(-0.02, -0.30, -0.25), v(0.12, 0.20, 0.020), v(0, -0.19, 0))
  conduit(b, { v(0.44, 0.00, 0.10), v(0.34, 0.14, 0.10), v(0.27, 0.50, 0.10) }, 0.016)
  conduit(b, { v(-0.42, -0.40, -0.14), v(-0.26, -0.56, -0.12), v(-0.16, -1.00, -0.08) }, 0.014)
  -- the arms: a long one with a big bank, a short one with a small
  truss(b, v(0.36, -0.06, 0), v(1.04, 0.02, 0.06), 0.12, 5, v(0, 0, 1))
  block(b, PLATING, v(1.16, 0.02, 0.06), v(0.14, 0.20, 0.17), nil, 0.12)
  block(b, TRIM, v(1.16, 0.18, 0.06), v(0.145, 0.02, 0.175), nil, 0.12)
  beam(b, FRAME, v(0.26, 0.40, 0), v(1.02, 0.08, 0.05), 0.014)
  truss(b, v(-0.36, -0.10, -0.04), v(-0.78, -0.16, -0.10), 0.10, 3, v(0, 0, 1))
  drum(b, v(-0.88, -0.16, -0.10), 0.10, 0.30)
  -- the houses, and the crown
  block(b, PATCH, v(-0.10, 0.74, 0.20), v(0.10, 0.08, 0.05), nil, 0.14)
  block(b, GLOW, v(-0.10, 0.75, 0.252), v(0.07, 0.02, 0.004), nil, 0.3)
  block(b, FRAME, v(0, 1.10, 0), v(0.20, 0.02, 0.20), nil, 0.2)
  block(b, PATCH, v(0.03, 1.235, 0.0), v(0.19, 0.12, 0.19), nil, 0.12)
  windows(b, v(0.03, 1.245, 0.0), 0.194, 4, 0.020)
  roof(b, v(0.03, 1.375, 0.0), v(0.21, 0.013, 0.20))
  crown(b, v(0, 1.48, 0), 0.24, 4)
  mast(b, v(-0.14, 1.36, -0.12), 0.70, -0.04)
  tail(b, v(0, -1.14, 0), 0.86, 0.055)
  truss(b, v(0.20, 0.80, 0), v(0.62, 0.90, -0.06), 0.08, 3, v(0, 0, 1))
  block(b, PATCH, v(0.69, 0.95, -0.06), v(0.12, 0.012, 0.12), v(0, 0.5, 0.4), 0.3)
end

-- Large: a walled deck at the waist with its drum farm, two stages each
-- way, and from each corner of the deck a girder up and a girder down
-- to where the stages narrow, so that the whole is a diamond. A keep
-- for a control house and a crown of six above; below, a lesser crown
-- turned down, and the tail.
local function vessariLarge(b: Builder)
  block(b, PLATING, v(0, 0, 0), v(0.66, 0.026, 0.66), nil, 0.12)
  block(b, TRIM, v(0, 0.035, 0), v(0.665, 0.012, 0.665), nil, 0.12)
  for index = 1, 7 do
    local along = (index - 4) * 0.19
    if index % 3 ~= 0 then
      block(b, PLATING, v(along, 0.065, 0.64), v(0.07, 0.04, 0.02), nil, 0.15)
      block(b, PLATING, v(along, 0.065, -0.64), v(0.07, 0.04, 0.02), nil, 0.15)
      block(b, PLATING, v(0.64, 0.065, along), v(0.02, 0.04, 0.07), nil, 0.15)
      block(b, PLATING, v(-0.64, 0.065, along), v(0.02, 0.04, 0.07), nil, 0.15)
    end
  end
  stage(b, 0.00, 0.75, 0.42, 0.30, 0.70)
  stage(b, 0.75, 1.45, 0.30, 0.20, 0.55)
  stage(b, -0.85, 0.00, 0.28, 0.42, 0.70)
  stage(b, -1.65, -0.85, 0.14, 0.28, 0.55)
  -- the girders that make the diamond
  for index, corner in { v(1, 0, 1), v(-1, 0, 1), v(-1, 0, -1), v(1, 0, -1) } do
    local across = v(corner.z, 0, -corner.x) * 0.7071
    truss(b, v(corner.x * 0.64, 0.03, corner.z * 0.64), v(corner.x * 0.22, 1.32, corner.z * 0.22), 0.11, 7, across)
    truss(b, v(corner.x * 0.64, -0.03, corner.z * 0.64), v(corner.x * 0.16, -1.52, corner.z * 0.16), 0.11, 8, across)
  end
  -- the drum farm, on the deck and hung under it
  for index, at in { v(0.52, 0.24, 0.18), v(0.50, 0.21, -0.24), v(-0.52, 0.23, 0.10), v(-0.48, -0.22, -0.34), v(0.12, -0.21, 0.52), v(-0.22, 0.20, -0.52) } do
    drum(b, at, 0.115 - 0.008 * index, 0.42 - 0.03 * index, if index % 2 == 0 then PLATING else PATCH)
  end
  block(b, PATCH, v(0.345, 0.34, 0.04), v(0.022, 0.28, 0.18), v(0, 0, 0.16))
  block(b, PATCH, v(-0.04, -0.40, -0.335), v(0.17, 0.26, 0.022), v(0, -0.16, 0))
  block(b, PLATING, v(-0.335, -0.36, -0.06), v(0.022, 0.26, 0.15), v(0, 0, 0.16))
  conduit(b, { v(0.52, 0.44, 0.18), v(0.40, 0.60, 0.16), v(0.30, 0.80, 0.14), v(0.24, 1.30, 0.12) }, 0.018)
  conduit(b, { v(-0.48, -0.40, -0.34), v(-0.34, -0.70, -0.24), v(-0.24, -1.00, -0.16), v(-0.16, -1.56, -0.10) }, 0.016)
  -- arms at three heights, none alike
  truss(b, v(0.36, 0.44, 0), v(1.22, 0.56, 0.08), 0.14, 6, v(0, 0, 1))
  block(b, PLATING, v(1.38, 0.56, 0.08), v(0.17, 0.24, 0.20), nil, 0.12)
  block(b, TRIM, v(1.38, 0.75, 0.08), v(0.175, 0.022, 0.205), nil, 0.12)
  beam(b, FRAME, v(0.28, 0.92, 0), v(1.20, 0.62, 0.07), 0.016)
  truss(b, v(-0.36, -0.40, -0.04), v(-0.98, -0.48, -0.14), 0.12, 4, v(0, 0, 1))
  drum(b, v(-1.10, -0.48, -0.14), 0.12, 0.36)
  truss(b, v(0, 1.10, -0.24), v(-0.06, 1.18, -0.82), 0.09, 3, v(1, 0, 0))
  block(b, PATCH, v(-0.06, 1.23, -0.92), v(0.15, 0.012, 0.15), v(0.4, 0.5, 0), 0.3)
  -- the keep: the control house in two steps, under the roof
  block(b, FRAME, v(0, 1.47, 0), v(0.26, 0.02, 0.26), nil, 0.2)
  block(b, PLATING, v(0.03, 1.64, 0.0), v(0.24, 0.15, 0.24), nil, 0.10)
  windows(b, v(0.03, 1.66, 0.0), 0.245, 4, 0.022)
  block(b, TRIM, v(0.03, 1.795, 0.0), v(0.245, 0.013, 0.245), nil, 0.1)
  block(b, PATCH, v(0.04, 1.905, 0.02), v(0.19, 0.10, 0.19), nil, 0.10)
  windows(b, v(0.04, 1.915, 0.02), 0.194, 3, 0.020)
  roof(b, v(0.04, 2.025, 0.02), v(0.21, 0.014, 0.20))
  crown(b, v(0, 2.14, 0), 0.30, 6)
  mast(b, v(-0.17, 2.02, -0.14), 0.95, -0.05)
  mast(b, v(0.18, 2.02, 0.12), 0.56, 0.03)
  -- below
  crown(b, v(0, -1.68, 0), 0.20, 4, true)
  tail(b, v(0, -1.66, 0), 1.10, 0.06)
  mast(b, v(0.10, -1.66, 0.08), -0.50, 0.03)
end

-- ---------------------------------------------------------------------
-- The modules, which are everybody's. Each is drawn about its own
-- middle, about one unit from there to its farthest part, its front
-- toward +z. Like the towers they are things in space, and none has a
-- floor to it, or feet, or anything it could be stood on (the owner's
-- word again): each is built out both ways from its middle.

local MODULES: { [string]: (b: Builder) -> () } = {
  -- A trade hub: a drum of offices, narrowing above and below, with
  -- four arms out to mooring pads and signs lit along the arms.
  ["array.trade"] = function(b)
    drum(b, v(0, 0, 0), 0.30, 0.44, PLATING)
    block(b, PATCH, v(0, 0.29, 0), v(0.21, 0.08, 0.21), nil, 0.4)
    block(b, PATCH, v(0, -0.29, 0), v(0.20, 0.08, 0.20), nil, 0.4)
    block(b, PLATING, v(0, -0.45, 0), v(0.12, 0.09, 0.12), nil, 0.4)
    windows(b, v(0, 0.07, 0), 0.292, 4, 0.02)
    windows(b, v(0, -0.08, 0), 0.292, 4, 0.02)
    for index, out in { v(1, 0, 0), v(-1, 0, 0), v(0, 0, 1), v(0, 0, -1) } do
      local reach = 0.80 + 0.10 * (index % 2)
      truss(b, out * 0.28, out * reach, 0.10, 4, v(0, 1, 0))
      block(b, PLATING, out * (reach + 0.07), v(0.13, 0.035, 0.13), nil, 0.3)
      block(b, TRIM, out * (reach + 0.07) + v(0, 0.038, 0), v(0.10, 0.008, 0.10), nil, 0.2)
      block(b, TRIM, out * (reach + 0.07) + v(0, -0.038, 0), v(0.10, 0.008, 0.10), nil, 0.2)
      block(b, GLOW, out * (reach * 0.6) + v(0, 0.075, 0), v(0.012 + 0.10 * math.abs(out.x), 0.012, 0.012 + 0.10 * math.abs(out.z)), nil, 0.3)
      block(b, GLOW, out * (reach * 0.6) + v(0, -0.075, 0), v(0.012 + 0.10 * math.abs(out.x), 0.012, 0.012 + 0.10 * math.abs(out.z)), nil, 0.3)
    end
    mast(b, v(0.05, 0.37, 0.04), 0.50, 0.02)
    tail(b, v(0, -0.52, 0), 0.44, 0.035)
  end,
  -- A ship maintenance array: a hangar open at the front and lit
  -- inside, its roof a ridge and its underside a keel, a tank slung
  -- under that.
  ["array.hangar"] = function(b)
    block(b, PLATING, v(0.50, 0.0, -0.10), v(0.03, 0.24, 0.74), nil, 0.1)
    block(b, PLATING, v(-0.50, 0.0, -0.10), v(0.03, 0.24, 0.74), nil, 0.1)
    block(b, PATCH, v(-0.25, 0.345, -0.12), v(0.275, 0.025, 0.72), v(0, 0, 0.398), 0.1)
    block(b, PATCH, v(0.25, 0.345, -0.12), v(0.275, 0.025, 0.72), v(0, 0, -0.398), 0.1)
    block(b, PLATING, v(-0.25, -0.345, -0.12), v(0.275, 0.025, 0.72), v(0, 0, -0.398), 0.1)
    block(b, PLATING, v(0.25, -0.345, -0.12), v(0.275, 0.025, 0.72), v(0, 0, 0.398), 0.1)
    beam(b, FRAME, v(0, 0.455, -0.86), v(0, 0.455, 0.64), 0.03)
    beam(b, FRAME, v(0, -0.455, -0.86), v(0, -0.455, 0.64), 0.03)
    -- the back of it, and the light inside
    block(b, PLATING, v(0, 0.0, -0.84), v(0.50, 0.24, 0.03), nil, 0.1)
    block(b, PLATING, v(0, 0.0, -0.84), v(0.30, 0.38, 0.028), nil, 0.1)
    block(b, GLOW, v(0, 0.0, -0.80), v(0.40, 0.20, 0.006), nil, 0.2)
    -- the mouth, edged in trim all the way round
    block(b, TRIM, v(0.50, 0.0, 0.66), v(0.036, 0.25, 0.03), nil, 0.2)
    block(b, TRIM, v(-0.50, 0.0, 0.66), v(0.036, 0.25, 0.03), nil, 0.2)
    beam(b, TRIM, v(-0.50, 0.24, 0.62), v(0, 0.455, 0.62), 0.028)
    beam(b, TRIM, v(0.50, 0.24, 0.62), v(0, 0.455, 0.62), 0.028)
    beam(b, TRIM, v(-0.50, -0.24, 0.62), v(0, -0.455, 0.62), 0.028)
    beam(b, TRIM, v(0.50, -0.24, 0.62), v(0, -0.455, 0.62), 0.028)
    for _, x in { -0.3, 0.3 } do
      beam(b, FRAME, v(x, 0.18, -0.76), v(x, 0.18, 0.60), 0.018)
    end
    -- under the keel a tank on struts, over the ridge a mast, a cabin on the side
    block(b, PATCH, v(0.02, -0.66, -0.26), v(0.10, 0.10, 0.32), nil, 0.55)
    for _, z in { -0.48, -0.04 } do
      beam(b, FRAME, v(0, -0.46, z), v(0.02, -0.58, z), 0.022)
    end
    mast(b, v(-0.04, 0.46, -0.50), 0.42, 0.02)
    mast(b, v(0.02, -0.76, -0.30), -0.28, 0.02)
    block(b, PATCH, v(-0.62, 0.04, -0.46), v(0.09, 0.11, 0.15), nil, 0.14)
    block(b, GLOW, v(-0.712, 0.06, -0.46), v(0.004, 0.02, 0.10), nil, 0.3)
    drum(b, v(0.64, -0.02, -0.36), 0.10, 0.36)
  end,
  -- A refining array: furnace columns of unequal length through a
  -- collar of girders, each with a vent at the top and a nozzle below,
  -- piped together, with a hopper on the side.
  ["array.refining"] = function(b)
    for _, z in { -0.34, 0.34 } do
      beam(b, FRAME, v(-0.54, 0, z), v(0.56, 0, z), 0.035)
    end
    for _, x in { -0.54, -0.08, 0.56 } do
      beam(b, FRAME, v(x, 0, -0.34), v(x, 0, 0.34), 0.030)
    end
    beam(b, FRAME, v(-0.54, 0, -0.34), v(-0.08, 0, 0.34), 0.018)
    beam(b, FRAME, v(-0.08, 0, 0.34), v(0.56, 0, -0.34), 0.018)
    for index, column in { { -0.30, -0.10, -0.55, 0.82 }, { 0.10, 0.12, -0.84, 0.46 }, { 0.38, -0.16, -0.36, 0.62 } } do
      local x, z, low, high = column[1], column[2], column[3], column[4]
      block(b, if index == 2 then PATCH else PLATING, v(x, (low + high) / 2, z), v(0.13, (high - low) / 2, 0.13), nil, 0.3)
      block(b, FRAME, v(x, high, z), v(0.15, 0.03, 0.15), nil, 0.3)
      block(b, GLOW, v(x, high + 0.035, z), v(0.09, 0.008, 0.09), nil, 0.4)
      block(b, TRIM, v(x, 0.10, z), v(0.134, 0.02, 0.134), nil, 0.3)
      -- (the nozzle: it narrows to where the slag is let go)
      block(b, FRAME, v(x, low - 0.05, z), v(0.10, 0.06, 0.10), nil, 0.3)
      block(b, FRAME, v(x, low - 0.14, z), v(0.06, 0.05, 0.06), v(math.pi / 4, 0, 0), 0.3)
      block(b, GLOW, v(x, low - 0.195, z), v(0.035, 0.006, 0.035), nil, 0.4)
    end
    block(b, PLATING, v(-0.08, -0.06, 0.44), v(0.24, 0.17, 0.10), v(0, 0.25, 0), 0.1)
    block(b, PLATING, v(-0.08, -0.28, 0.40), v(0.12, 0.08, 0.07), v(0, 0.25, 0), 0.2)
    conduit(b, { v(-0.30, 0.40, -0.10), v(-0.10, 0.54, 0.0), v(0.10, 0.34, 0.12) }, 0.03)
    conduit(b, { v(0.10, 0.20, 0.12), v(0.24, 0.32, -0.02), v(0.38, 0.24, -0.16) }, 0.03)
    conduit(b, { v(-0.30, -0.30, -0.10), v(-0.10, -0.44, 0.0), v(0.10, -0.40, 0.12) }, 0.028)
    conduit(b, { v(0.10, -0.60, 0.12), v(0.26, -0.50, -0.04), v(0.38, -0.22, -0.16) }, 0.024)
    mast(b, v(-0.52, 0.02, -0.32), 0.50, -0.02)
    mast(b, v(0.54, -0.02, 0.32), -0.40, 0.02)
  end,
  -- A ship assembly array: a cage of hoops along four rails, a crane
  -- over and a crane under, and a hull half built in the middle of it.
  ["array.assembly"] = function(b)
    for _, x in { -0.34, 0.34 } do
      for _, y in { -0.27, 0.27 } do
        beam(b, FRAME, v(x, y, -0.92), v(x, y, 0.92), 0.024, 0.1)
      end
    end
    for index = 0, 5 do
      local z = -0.88 + index * 0.352
      beam(b, FRAME, v(-0.34, -0.27, z), v(-0.34, 0.27, z), 0.018)
      beam(b, FRAME, v(0.34, -0.27, z), v(0.34, 0.27, z), 0.018)
      beam(b, FRAME, v(-0.34, 0.27, z), v(0.34, 0.27, z), 0.018)
      beam(b, FRAME, v(-0.34, -0.27, z), v(0.34, -0.27, z), 0.018)
      block(b, GLOW, v(0, 0.245, z), v(0.05, 0.006, 0.012), nil, 0.3)
      block(b, GLOW, v(0, -0.245, z), v(0.05, 0.006, 0.012), nil, 0.3)
      if index < 5 and index % 2 == 0 then
        beam(b, FRAME, v(0.34, -0.27, z), v(0.34, 0.27, z + 0.352), 0.012)
        beam(b, FRAME, v(-0.34, 0.27, z), v(-0.34, -0.27, z + 0.352), 0.012)
      end
    end
    -- the cranes, and the cab
    block(b, TRIM, v(0, 0.32, 0.30), v(0.38, 0.03, 0.04), nil, 0.2)
    block(b, FRAME, v(0.12, 0.23, 0.30), v(0.04, 0.07, 0.04))
    block(b, TRIM, v(0, -0.32, -0.42), v(0.38, 0.03, 0.04), nil, 0.2)
    block(b, FRAME, v(-0.14, -0.23, -0.42), v(0.04, 0.07, 0.04))
    block(b, PATCH, v(0.44, 0.02, -0.80), v(0.08, 0.09, 0.10), nil, 0.14)
    block(b, GLOW, v(0.358, 0.03, -0.80), v(0.004, 0.02, 0.07), nil, 0.3)
    block(b, PATCH, v(-0.43, -0.04, 0.40), v(0.07, 0.07, 0.24), nil, 0.55)
    -- the hull on the slip: a spine, plating as far as it has got, ribs beyond
    beam(b, FRAME, v(0, 0, -0.70), v(0, 0, 0.66), 0.03)
    block(b, PLATING, v(0, 0.0, -0.40), v(0.15, 0.13, 0.26), nil, 0.1)
    block(b, PATCH, v(-0.01, 0.01, 0.02), v(0.13, 0.11, 0.14), nil, 0.1)
    for index = 0, 3 do
      local z = 0.24 + index * 0.11
      beam(b, FRAME, v(-0.12, -0.10, z), v(0.12, -0.10, z), 0.012)
      beam(b, FRAME, v(-0.12, 0.10, z), v(0.12, 0.10, z), 0.012)
      beam(b, FRAME, v(-0.12, -0.10, z), v(-0.12, 0.10, z), 0.012)
      beam(b, FRAME, v(0.12, -0.10, z), v(0.12, 0.10, z), 0.012)
    end
  end,
  -- A laboratory: pods round a hub, some above it and some below, a
  -- dish on a boom, and aerials both ways.
  ["array.laboratory"] = function(b)
    drum(b, v(0, 0, 0), 0.15, 0.50, PLATING)
    block(b, TRIM, v(0, 0.0, 0), v(0.165, 0.02, 0.165), nil, 0.4)
    block(b, PATCH, v(-0.32, 0.18, 0.06), v(0.25, 0.23, 0.25), nil, 0.7)
    block(b, PLATING, v(0.32, -0.16, -0.10), v(0.20, 0.18, 0.20), nil, 0.7)
    block(b, PATCH, v(0.04, -0.44, 0.24), v(0.16, 0.14, 0.16), nil, 0.7)
    block(b, PLATING, v(0.10, 0.42, -0.26), v(0.13, 0.11, 0.13), nil, 0.7)
    block(b, GLOW, v(-0.32, 0.18, 0.312), v(0.12, 0.02, 0.004), nil, 0.3)
    block(b, GLOW, v(0.32, -0.16, 0.102), v(0.09, 0.016, 0.004), nil, 0.3)
    block(b, GLOW, v(0.04, -0.44, 0.402), v(0.07, 0.014, 0.004), nil, 0.3)
    beam(b, FRAME, v(0, 0.12, 0), v(-0.20, 0.18, 0.04), 0.03)
    beam(b, FRAME, v(0, -0.10, 0), v(0.20, -0.16, -0.06), 0.03)
    beam(b, FRAME, v(0, -0.22, 0.04), v(0.04, -0.36, 0.16), 0.026)
    beam(b, FRAME, v(0, 0.22, -0.04), v(0.08, 0.36, -0.18), 0.026)
    beam(b, FRAME, v(0.10, 0.0, -0.10), v(0.56, 0.30, -0.50), 0.02)
    block(b, PATCH, v(0.60, 0.36, -0.54), v(0.20, 0.014, 0.20), v(0.3, 0.6, 0), 0.4)
    beam(b, FRAME, v(-0.12, -0.06, -0.08), v(-0.62, -0.24, -0.30), 0.016)
    block(b, FRAME, v(-0.66, -0.26, -0.32), v(0.05, 0.05, 0.08), nil, 0.3)
    mast(b, v(0, 0.26, 0), 0.70, 0.02)
    mast(b, v(0, -0.26, 0), -0.52, -0.02)
  end,
  -- A storage array: drums in a cage of girders, the cage drawn in to
  -- a point above and below, with boxes clamped on its sides.
  ["array.storage"] = function(b)
    for _, x in { -0.38, 0.38 } do
      for _, z in { -0.40, 0.40 } do
        beam(b, FRAME, v(x, -0.44, z), v(x, 0.44, z), 0.03, 0.1)
        beam(b, FRAME, v(x, 0.44, z), v(0, 0.86, 0), 0.022)
        beam(b, FRAME, v(x, -0.44, z), v(0, -0.86, 0), 0.022)
      end
    end
    for _, y in { -0.44, 0.44 } do
      for _, z in { -0.40, 0.40 } do
        beam(b, FRAME, v(-0.38, y, z), v(0.38, y, z), 0.026)
      end
      for _, x in { -0.38, 0.38 } do
        beam(b, FRAME, v(x, y, -0.40), v(x, y, 0.40), 0.026)
      end
    end
    for index, at in { v(-0.19, 0, -0.20), v(-0.19, 0, 0.20), v(0.19, 0, -0.20), v(0.19, 0, 0.20) } do
      drum(b, at, 0.165, 0.84, if index == 3 then PLATING else PATCH)
    end
    beam(b, FRAME, v(-0.38, -0.44, -0.40), v(0.38, 0.44, -0.40), 0.016)
    beam(b, FRAME, v(-0.38, 0.44, 0.40), v(0.38, -0.44, 0.40), 0.016)
    block(b, FRAME, v(0, 0.88, 0), v(0.05, 0.04, 0.05), nil, 0.3)
    block(b, FRAME, v(0, -0.88, 0), v(0.05, 0.04, 0.05), nil, 0.3)
    block(b, GLOW, v(0, 0.935, 0), v(0.025, 0.02, 0.025), v(math.pi / 4, 0, 0), 0.45)
    block(b, GLOW, v(0, -0.935, 0), v(0.025, 0.02, 0.025), v(math.pi / 4, 0, 0), 0.45)
    block(b, PLATING, v(0.56, 0.08, -0.10), v(0.15, 0.20, 0.24), nil, 0.06)
    block(b, TRIM, v(-0.55, -0.10, 0.12), v(0.14, 0.16, 0.20), nil, 0.06)
    block(b, PLATING, v(0.04, 0.12, 0.56), v(0.18, 0.15, 0.13), nil, 0.06)
    block(b, GLOW, v(0.714, 0.08, -0.10), v(0.004, 0.02, 0.10), nil, 0.3)
  end,
  -- A habitat: decks on a spine, the widest in the middle and the rest
  -- smaller toward both ends, their ports lit; a dome at the top, a
  -- lesser one turned down at the bottom.
  ["array.habitat"] = function(b)
    beam(b, FRAME, v(0, -0.80, 0), v(0, 0.80, 0), 0.07, 0.1)
    for index, deck in { { -0.40, 0.40 }, { 0.0, 0.56 }, { 0.40, 0.43 } } do
      local y, half = deck[1], deck[2]
      block(b, if index == 2 then PATCH else PLATING, v(0, y, 0), v(half, 0.13, half), nil, 0.5)
      windows(b, v(0, y + 0.02, 0), half * 0.985, 5, 0.018)
      block(b, TRIM, v(0, y + (if y < 0 then 0.11 else -0.11), 0), v(half * 0.9, 0.012, half * 0.9), nil, 0.5)
    end
    block(b, PATCH, v(0, 0.66, 0), v(0.21, 0.12, 0.21), nil, 0.8)
    block(b, PLATING, v(0, -0.66, 0), v(0.18, 0.11, 0.18), nil, 0.8)
    mast(b, v(0.04, 0.76, 0.02), 0.36, 0.02)
    tail(b, v(0, -0.76, 0), 0.34, 0.03)
    drum(b, v(0.50, -0.02, 0.36), 0.08, 0.30)
    drum(b, v(-0.46, 0.20, -0.40), 0.07, 0.24, PLATING)
  end,
  -- What a battery's gun or rack stands on (the gun or rack is one of
  -- the ship's weapons, at the size of a structure): a deck with the
  -- ring for it, and under the deck a body that narrows in steps to a
  -- point, braced to the deck's corners.
  ["battery"] = function(b)
    block(b, PLATING, v(0, -0.06, 0), v(0.62, 0.05, 0.62), nil, 0.3)
    block(b, PLATING, v(0, -0.06, 0), v(0.62, 0.05, 0.62), v(math.pi / 4, 0, 0), 0.3)
    block(b, TRIM, v(0, -0.004, 0), v(0.50, 0.01, 0.50), v(math.pi / 4, 0, 0), 0.3)
    block(b, FRAME, v(0, 0.01, 0), v(0.36, 0.03, 0.36), nil, 0.45)
    block(b, PLATING, v(0, -0.27, 0), v(0.40, 0.16, 0.40), v(math.pi / 4, 0, 0), 0.3)
    block(b, PATCH, v(0, -0.52, 0), v(0.27, 0.12, 0.27), nil, 0.3)
    block(b, TRIM, v(0, -0.41, 0), v(0.28, 0.015, 0.28), nil, 0.3)
    block(b, FRAME, v(0, -0.70, 0), v(0.15, 0.08, 0.15), v(math.pi / 4, 0, 0), 0.3)
    tail(b, v(0, -0.76, 0), 0.46, 0.04)
    for index = 1, 4 do
      local angle = (index - 0.5) / 4 * 2 * math.pi
      local out = v(math.cos(angle), 0, math.sin(angle))
      beam(b, FRAME, out * 0.74 + v(0, -0.10, 0), out * 0.20 + v(0, -0.72, 0), 0.03)
    end
    block(b, PATCH, v(0.42, 0.08, -0.42), v(0.10, 0.10, 0.10), nil, 0.14)
    block(b, GLOW, v(0.42, 0.10, -0.316), v(0.06, 0.02, 0.004), nil, 0.3)
    block(b, GLOW, v(0, -0.52, 0.272), v(0.12, 0.02, 0.004), nil, 0.3)
    drum(b, v(-0.46, -0.30, 0.42), 0.07, 0.24)
  end,
}

-- ---------------------------------------------------------------------

-- A model and half the longest way across it, in its own units.
-- ---------------------------------------------------------------------
-- The Talmar towers
--
-- Grown, as their hulls are (Game/View/Hull): a stem that swells into a
-- head, with lesser bodies budded round it, every surface a skin and
-- not a plate. A tower is round about its axis, where a hull is the
-- same on both sides: what buds from it buds three or six ways.
--
-- A skin is lofted along z, so these are drawn lying down, the top of
-- the tower toward +z, and stood up when they are put in a scene
-- (LYING, Starbase.TowerPart).

-- A skin's outline moved along its length and made bigger or smaller.
local function moved(outline: Plates.Outline, along: number, size: number): Plates.Outline
  local out: Plates.Outline = {}
  for index, station in outline do
    out[index] = { station[1] * size + along, station[2] * size, station[3] * size }
  end
  return out
end

-- A bud: a small body of its own, an egg and not a leaf (round at both
-- ends, fattest a little above its middle).
local BUD: Plates.Outline = { { -0.19, 0.012, 0.012 }, { -0.165, 0.046, 0.046 }, { -0.10, 0.080, 0.080 }, { 0.01, 0.098, 0.098 },
  { 0.11, 0.084, 0.084 }, { 0.165, 0.052, 0.052 }, { 0.19, 0.014, 0.014 } }
-- A spire: a slender body that comes to a point.
local SPIRE: Plates.Outline = { { 0, 0.020, 0.020 }, { 0.10, 0.016, 0.016 }, { 0.34, 0.010, 0.010 }, { 0.50, 0.003, 0.003 } }

-- 'count' of something round the axis, evenly, the first at 'turn':
-- 'each' is given where round it is, and the way out from the axis there.
local function round(count: number, turn: number, each: (around: number, out: vector) -> ())
  for index = 1, count do
    local around = turn + (index - 1) * 2 * math.pi / count
    each(around, v(math.cos(around), math.sin(around), 0))
  end
end

-- Buds on a skin, 'count' round it at 'z', each 'size' big and standing
-- 'off' of its own thickness out of the skin.
local function buds(b: Builder, outline: Plates.Outline, z: number, count: number, turn: number, size: number, off: number)
  round(count, turn, function(around: number, out: vector)
    local skin = Plates.Point(outline, z, around)
    local at = skin + out * (0.085 * size * off)
    Plates.Loft(b, PATCH, moved(BUD, z, size), at.x, at.y)
  end)
end

-- A ring of lit windows round a skin at 'z'.
local function lights(b: Builder, outline: Plates.Outline, z: number, count: number, size: number)
  round(count, 0.3, function(around: number, out: vector)
    local at = Plates.Point(outline, z, around)
    block(b, GLOW, at + out * (size * 0.2), v(size, size, size * 1.6), nil, 0.7)
  end)
end

-- Swellings lying along a skin, 'count' round it.
local function ribs(b: Builder, outline: Plates.Outline, z: number, count: number, turn: number, length: number)
  round(count, turn, function(around: number)
    Plates.Fairing(b, PLATING, outline, z, around, length, length * 0.14, length * 0.07)
  end)
end

local TALMAR_SMALL: Plates.Outline = {
  { -1.00, 0.012, 0.012 }, { -0.72, 0.050, 0.050 }, { -0.42, 0.105, 0.105 }, { -0.16, 0.070, 0.070 }, { 0.10, 0.19, 0.19 },
  { 0.38, 0.27, 0.27 }, { 0.62, 0.21, 0.21 }, { 0.82, 0.09, 0.09 }, { 1.00, 0.015, 0.015 },
}
-- Small: a stem and one head, three buds under the head and a spire on it.
local function talmarSmall(b: Builder)
  Plates.Loft(b, PLATING, TALMAR_SMALL)
  buds(b, TALMAR_SMALL, 0.12, 3, 0.5, 1.0, 0.55)
  buds(b, TALMAR_SMALL, -0.44, 3, 1.55, 0.6, 0.5)
  ribs(b, TALMAR_SMALL, 0.40, 6, 0.0, 0.42)
  lights(b, TALMAR_SMALL, 0.50, 9, 0.012)
  lights(b, TALMAR_SMALL, -0.40, 5, 0.009)
  Plates.Loft(b, TRIM, moved(SPIRE, 0.96, 0.7))
end

local TALMAR_MEDIUM: Plates.Outline = {
  { -1.20, 0.012, 0.012 }, { -0.92, 0.055, 0.055 }, { -0.66, 0.15, 0.15 }, { -0.44, 0.19, 0.19 }, { -0.22, 0.10, 0.10 },
  { 0.02, 0.17, 0.17 }, { 0.34, 0.31, 0.31 }, { 0.62, 0.27, 0.27 }, { 0.86, 0.13, 0.13 }, { 1.06, 0.05, 0.05 }, { 1.24, 0.012, 0.012 },
}
-- Medium: a lesser body below the head, buds in two rings, three spires.
local function talmarMedium(b: Builder)
  Plates.Loft(b, PLATING, TALMAR_MEDIUM)
  buds(b, TALMAR_MEDIUM, 0.16, 3, 0.5, 1.35, 0.6)
  buds(b, TALMAR_MEDIUM, 0.66, 3, 1.55, 0.8, 0.5)
  buds(b, TALMAR_MEDIUM, -0.50, 6, 0.0, 0.75, 0.5)
  ribs(b, TALMAR_MEDIUM, 0.40, 6, 0.26, 0.50)
  ribs(b, TALMAR_MEDIUM, -0.52, 3, 0.5, 0.30)
  lights(b, TALMAR_MEDIUM, 0.46, 12, 0.012)
  lights(b, TALMAR_MEDIUM, 0.74, 8, 0.010)
  lights(b, TALMAR_MEDIUM, -0.40, 8, 0.010)
  Plates.Loft(b, TRIM, moved(SPIRE, 1.18, 0.8))
  round(3, 0.5, function(_, out: vector)
    Plates.Loft(b, PATCH, moved(SPIRE, 0.86, 0.55), out.x * 0.10, out.y * 0.10)
  end)
end

local TALMAR_LARGE: Plates.Outline = {
  { -1.50, 0.012, 0.012 }, { -1.22, 0.06, 0.06 }, { -0.98, 0.14, 0.14 }, { -0.80, 0.17, 0.17 }, { -0.62, 0.10, 0.10 },
  { -0.42, 0.20, 0.20 }, { -0.20, 0.25, 0.25 }, { -0.02, 0.14, 0.14 }, { 0.20, 0.24, 0.24 }, { 0.52, 0.38, 0.38 },
  { 0.82, 0.33, 0.33 }, { 1.06, 0.17, 0.17 }, { 1.28, 0.06, 0.06 }, { 1.50, 0.012, 0.012 },
}
-- Large: three bodies one over another, the head the greatest, a crown
-- of spires, and bodies of their own budded off the head on stalks.
local TALMAR_HOUSE: Plates.Outline = { { -0.30, 0.02, 0.02 }, { -0.14, 0.09, 0.09 }, { 0.04, 0.12, 0.12 }, { 0.20, 0.08, 0.08 },
  { 0.34, 0.015, 0.015 } }
local function talmarLarge(b: Builder)
  Plates.Loft(b, PLATING, TALMAR_LARGE)
  buds(b, TALMAR_LARGE, 0.30, 6, 0.0, 1.3, 0.6)
  buds(b, TALMAR_LARGE, 0.90, 3, 0.5, 1.0, 0.5)
  buds(b, TALMAR_LARGE, -0.30, 6, 0.26, 0.9, 0.5)
  buds(b, TALMAR_LARGE, -0.86, 3, 1.55, 0.7, 0.5)
  ribs(b, TALMAR_LARGE, 0.60, 6, 0.26, 0.60)
  ribs(b, TALMAR_LARGE, -0.22, 6, 0.0, 0.30)
  lights(b, TALMAR_LARGE, 0.56, 16, 0.013)
  lights(b, TALMAR_LARGE, 0.84, 12, 0.012)
  lights(b, TALMAR_LARGE, -0.16, 10, 0.011)
  lights(b, TALMAR_LARGE, -0.84, 6, 0.010)
  -- three houses out on stalks, level with the head
  round(3, 1.55, function(around: number, out: vector)
    local root = Plates.Point(TALMAR_LARGE, 0.56, around)
    local at = out * 0.66
    beam(b, PLATING, root - out * 0.03 + v(0, 0, 0.56) - v(0, 0, root.z), at + v(0, 0, 0.60), 0.028, 0.9)
    Plates.Loft(b, PATCH, moved(TALMAR_HOUSE, 0.60, 1.0), at.x, at.y)
    block(b, GLOW, at + out * 0.115 + v(0, 0, 0.64), v(0.012, 0.012, 0.03), nil, 0.7)
  end)
  Plates.Loft(b, TRIM, moved(SPIRE, 1.42, 1.0))
  round(6, 0.0, function(_, out: vector)
    Plates.Loft(b, PATCH, moved(SPIRE, 1.04, 0.6), out.x * 0.15, out.y * 0.15)
  end)
end

-- ---------------------------------------------------------------------
-- The Orun towers. (The project owner's draft for the Confederation:
-- no two things of theirs designed by the same group, red and gold
-- highlights, a lot of antenna masts; and of the first hulls drawn the
-- one they liked best by far was a ship of two hulls side by side.) So
-- a tower of theirs is not one mass but several long hulls standing on
-- end beside each other, joined by girders, with the control house
-- hung between them: two for the small one, three round an open middle
-- for the medium, and for the large a great one with four lesser ones
-- about it. Each hull steps in to a red cap at both ends, as nothing
-- anchored may look as if it stood on the ground; each has a gold band;
-- and each size is in its builders' own paint.

-- An aerial: a thin pole from 'foot' the way 'toward' points, with
-- cross-pieces, a red band at its foot and a gold tip.
local function aerial(b: Builder, foot: vector, height: number, toward: vector)
  local dir = vector.normalize(toward)
  local side = vector.cross(dir, v(0, 0, 1))
  if vector.magnitude(side) < 0.3 then
    side = vector.cross(dir, v(1, 0, 0))
  end
  side = vector.normalize(side)
  local top = foot + dir * height
  local thick = math.max(0.006, height * 0.018)
  beam(b, FRAME, foot, top, thick, 0.1)
  beam(b, FRAME, foot, foot + dir * (height * 0.22), thick * 1.7, 0.1)
  beam(b, TRIM, foot + dir * (height * 0.22), foot + dir * (height * 0.27), thick * 1.8, 0.1)
  for index, share in { 0.48, 0.66, 0.84 } do
    local at = foot + dir * (height * share)
    local reach = height * (0.20 - 0.045 * index)
    beam(b, FRAME, at - side * reach, at + side * reach, thick * 0.6, 0.1)
  end
  block(b, PATCH, top, v(thick * 1.6, thick * 1.6, thick * 1.6), nil, 0.5)
end

-- A hull standing on end at 'at' (its x and z), from 'low' to 'high':
-- a long box 'wide' to a side that steps in twice at each end to a red
-- cap, with a gold band round it 'band' of the way up, two frames, and
-- 'ports' lit ports up the face that looks 'out'. An aerial stands on
-- each end of it.
local function spar(b: Builder, at: vector, low: number, high: number, wide: number, out: vector, ports: number, band: number)
  local mid, half = (low + high) / 2, (high - low) / 2
  local x, z = at.x, at.z
  block(b, PLATING, v(x, mid, z), v(wide, half * 0.74, wide), nil, 0.10)
  for _, way in { 1, -1 } do
    block(b, PLATING, v(x, mid + way * half * 0.82, z), v(wide * 0.74, half * 0.09, wide * 0.74), nil, 0.16)
    block(b, PLATING, v(x, mid + way * half * 0.94, z), v(wide * 0.50, half * 0.045, wide * 0.50), nil, 0.2)
    block(b, TRIM, v(x, mid + way * half * 0.992, z), v(wide * 0.40, half * 0.008, wide * 0.40), nil, 0.2)
    block(b, FRAME, v(x, mid + way * half * 0.42, z), v(wide * 1.04, half * 0.012, wide * 1.04), nil, 0.1)
    aerial(b, v(x, mid + way * half, z), half * (if way > 0 then 0.42 else 0.30), v(out.x * 0.12, way, out.z * 0.12))
  end
  block(b, PATCH, v(x, low + (high - low) * band, z), v(wide * 1.03, half * 0.022, wide * 1.03), nil, 0.1)
  for index = 1, ports do
    local y = mid + ((index - 0.5) / ports - 0.5) * half * 1.2
    block(b, GLOW, v(x + out.x * wide * 1.005, y, z + out.z * wide * 1.005),
      v(0.004 + math.abs(out.z) * wide * 0.16, half * 0.014, 0.004 + math.abs(out.x) * wide * 0.16), nil, 0.3)
  end
end

-- Small: two hulls side by side, a girder between them above and
-- below, and the house between them at the waist under a red roof.
local function orunSmall(b: Builder)
  for _, side in { -1, 1 } do
    spar(b, v(side * 0.27, 0, 0), -0.95, 0.95, 0.11, v(side, 0, 0), 6, 0.80)
    aerial(b, v(side * 0.38, 0.34, 0), 0.36, v(side, 0.35, 0))
    aerial(b, v(side * 0.38, -0.40, 0.04), 0.26, v(side, -0.4, 0.2))
  end
  truss(b, v(-0.17, 0.56, 0), v(0.17, 0.56, 0), 0.12, 2)
  truss(b, v(-0.17, -0.56, 0), v(0.17, -0.56, 0), 0.12, 2)
  block(b, PLATING, v(0, 0.02, 0), v(0.16, 0.14, 0.18), nil, 0.12)
  block(b, GLOW, v(0, 0.07, 0.182), v(0.11, 0.018, 0.004), nil, 0.3)
  block(b, GLOW, v(0, 0.07, -0.182), v(0.11, 0.018, 0.004), nil, 0.3)
  block(b, TRIM, v(0, 0.168, 0), v(0.165, 0.010, 0.185), nil, 0.12)
  block(b, PATCH, v(0, -0.128, 0), v(0.165, 0.010, 0.185), nil, 0.12)
  aerial(b, v(0.06, 0.18, 0.10), 0.52, v(0.05, 1, 0.1))
  aerial(b, v(-0.07, 0.18, -0.08), 0.38, v(-0.1, 1, -0.1))
  aerial(b, v(0, 0.02, 0.18), 0.34, v(0, 0.2, 1))
  aerial(b, v(0.04, -0.14, -0.06), 0.36, v(0.05, -1, -0.1))
end

-- Medium: three hulls round an open middle, no two at the same height,
-- a ring of girders round them above and below, and the house hung in
-- the middle on a strut from each.
local function orunMedium(b: Builder)
  local posts: { vector } = {}
  for index = 0, 2 do
    local around = index * 2 * math.pi / 3 + math.pi / 2
    local out = v(math.cos(around), 0, math.sin(around))
    local shift = (index - 1) * 0.20
    posts[index + 1] = out * 0.42
    spar(b, out * 0.42, -1.35 + shift, 1.35 + shift, 0.13, out, 8, 0.78)
    beam(b, FRAME, out * 0.30 + v(0, 0.02, 0), out * 0.17 + v(0, 0.02, 0), 0.03, 0.2)
    aerial(b, out * 0.555 + v(0, 0.45 + shift, 0), 0.40, out + v(0, 0.35, 0))
    aerial(b, out * 0.555 + v(0, -0.55 + shift, 0), 0.30, out + v(0, -0.4, 0))
  end
  for index = 1, 3 do
    local from, to = posts[index], posts[index % 3 + 1]
    local inset = (to - from) * 0.22
    truss(b, from + inset + v(0, 0.78, 0), to - inset + v(0, 0.78, 0), 0.14, 3)
    truss(b, from + inset + v(0, -0.78, 0), to - inset + v(0, -0.78, 0), 0.14, 3)
  end
  -- the house: a block and the same turned an eighth, lit all round
  block(b, PLATING, v(0, 0.02, 0), v(0.17, 0.15, 0.17), nil, 0.12)
  block(b, PLATING, v(0, 0.02, 0), v(0.17, 0.13, 0.17), v(math.pi / 4, 0, 0), 0.12)
  windows(b, v(0, 0.07, 0), 0.174, 3, 0.016)
  block(b, PATCH, v(0, 0.178, 0), v(0.175, 0.010, 0.175), nil, 0.12)
  block(b, TRIM, v(0, -0.138, 0), v(0.175, 0.010, 0.175), nil, 0.12)
  for index, lean in { v(0.06, 1, 0.04), v(-0.08, 1, 0.02), v(0.02, 1, -0.09), v(-0.03, 1, 0.08) } do
    aerial(b, v(lean.x * 1.6, 0.19, lean.z * 1.6), 0.74 - 0.12 * index, lean)
  end
  aerial(b, v(0.05, -0.15, 0.03), 0.52, v(0.04, -1, 0.03))
  aerial(b, v(-0.06, -0.15, -0.04), 0.36, v(-0.06, -1, -0.05))
end

-- Large: a great hull in the middle and four lesser ones about it, two
-- of them set high and two low, each joined to the middle one by a
-- wing of deck and two girders; the house a collar round the middle
-- hull's waist, lit all round under a gold roof.
local function orunLarge(b: Builder)
  spar(b, v(0, 0, 0), -2.10, 2.10, 0.24, v(0, 0, 1), 0, 0.84)
  for index = 0, 3 do
    local around = index * math.pi / 2
    local out = v(math.cos(around), 0, math.sin(around))
    local shift = if index % 2 == 0 then 0.38 else -0.38
    local at = out * 0.72
    spar(b, at, -1.25 + shift, 1.25 + shift, 0.14, out, 8, 0.80)
    truss(b, out * 0.24 + v(0, shift + 0.72, 0), out * 0.58 + v(0, shift + 0.72, 0), 0.20, 2)
    truss(b, out * 0.24 + v(0, shift - 0.72, 0), out * 0.58 + v(0, shift - 0.72, 0), 0.20, 2)
    block(b, PLATING, out * 0.41 + v(0, shift, 0), v(0.03 + math.abs(out.x) * 0.15, 0.50, 0.03 + math.abs(out.z) * 0.15), nil, 0.08)
    aerial(b, out * 0.865 + v(0, shift + 0.30, 0), 0.50, out + v(0, 0.3, 0))
    aerial(b, out * 0.865 + v(0, shift - 0.45, 0), 0.36, out + v(0, -0.4, 0))
    -- (ports up the faces of the middle hull that show between the others)
    local between = v(math.cos(around + math.pi / 4), 0, math.sin(around + math.pi / 4))
    aerial(b, between * 0.36 + v(0, 0.12, 0), 0.60, between + v(0, 0.25, 0))
  end
  block(b, PLATING, v(0, 0, 0), v(0.34, 0.13, 0.34), v(math.pi / 4, 0, 0), 0.12)
  windows(b, v(0, 1.30, 0), 0.243, 4, 0.020)
  windows(b, v(0, -1.30, 0), 0.243, 4, 0.020)
  block(b, PATCH, v(0, 0.14, 0), v(0.345, 0.012, 0.345), v(math.pi / 4, 0, 0), 0.12)
  block(b, TRIM, v(0, -0.14, 0), v(0.345, 0.012, 0.345), v(math.pi / 4, 0, 0), 0.12)
  for index, lean in { v(0.10, 1, 0.06), v(-0.12, 1, 0.04), v(0.04, 1, -0.13), v(-0.05, 1, 0.12), v(0.13, 1, -0.05) } do
    aerial(b, v(lean.x * 1.2, 1.96, lean.z * 1.2), 0.95 - 0.11 * index, lean)
  end
  for index, lean in { v(0.10, -1, 0.05), v(-0.09, -1, -0.08), v(0.02, -1, 0.12) } do
    aerial(b, v(lean.x * 1.2, -1.96, lean.z * 1.2), 0.70 - 0.12 * index, lean)
  end
end

export type Made = { model: Model, radius: number }

local TOWERS: { [string]: { (b: Builder) -> () } } = {
  vessari = { vessariSmall, vessariMedium, vessariLarge },
  talmar = { talmarSmall, talmarMedium, talmarLarge },
  orun = { orunSmall, orunMedium, orunLarge },
}
-- A faction whose towers are not all in the one paint: each size in its
-- builders' own (the Orun's, as their hulls are).
local PAINTS: { [string]: { Plates.Look } } = {
  orun = { Hull.OrunPaint({ 0.58, 0.58, 0.55 }, 0.35, 0.10), Hull.OrunPaint({ 0.18, 0.19, 0.21 }, 0.50, 0.15),
    Hull.OrunPaint({ 0.24, 0.27, 0.31 }, 0.50, 0.25) },
}
-- The factions whose towers are drawn lying along z and stood up.
local LYING: { [string]: boolean } = { talmar = true }

local made: { [string]: Made } = {}

local function finish(key: string, draw: (b: Builder) -> (), look: Plates.Look, sheets: number, fine: number): Made
  local kept = made[key]
  if kept then
    return kept
  end
  local b = Plates.New(#key * 2.31, fine)
  draw(b)
  local model, lower, upper = Plates.Finish(b, look, sheets)
  local size = upper - lower
  local result = { model = model, radius = math.max(size.x, size.y, size.z) / 2 }
  made[key] = result
  return result
end

-- The model of a faction's tower of a size (1 to 3). A faction whose
-- tower nobody has drawn yet gets the Vessari's.
function Starbase.Tower(faction: string, size: number): Made
  local designs = TOWERS[faction] or TOWERS.vessari
  local owner = if TOWERS[faction] then faction else "vessari"
  local paints = PAINTS[owner]
  return finish(`tower.{owner}.{size}`, designs[size], if paints then paints[size] else Hull.looks[owner], 4.5 + 2.5 * size, 0.11)
end

-- A faction's tower of a size as a thing to put in a scene (Raise): its
-- middle at 'at' and 'towerRadius' metres in radius, upright whichever
-- way its drawing lies.
function Starbase.TowerPart(faction: string, size: number, at: vector, towerRadius: number): Part
  local made = Starbase.Tower(faction, size)
  local lying = LYING[faction] == true and TOWERS[faction] ~= nil
  return {
    id = `tower.{faction}.{size}`, model = made.model, at = at,
    look = if lying then vector.create(0, 1, 0) else vector.create(0, 0, 1),
    up = if lying then vector.create(0, 0, -1) else nil,
    scale = towerRadius / made.radius, radius = towerRadius,
  }
end

-- The model of a module (Core/Data/Structures' ids). A battery of
-- either kind is its stand: what stands on it is Starbase.Layout's to say.
function Starbase.Module(id: string): Made
  local key = if string.sub(id, 1, 8) == "battery." then "battery" else id
  local draw = MODULES[key]
  assert(draw, `no drawing of a '{id}'`)
  return finish(key, draw, WORKS, 4.0, 0.11)
end

-- A stargate (a v0: the quickest thing that reads as one). A ring to
-- fly through, lit round its inside, with four pylons whose prongs lean
-- in ahead of it and astern. Its front is toward +z, the way a ship
-- leaves through it.
local function gate(b: Builder)
  local count = 12
  for index = 0, count - 1 do
    local a = index / count * 2 * math.pi
    local out = v(math.cos(a), math.sin(a), 0)
    local turn = v(0, 0, a + math.pi / 2)
    block(b, if index % 3 == 1 then PATCH else PLATING, out * 0.80, v(0.215, 0.07, 0.10), turn, 0.15)
    block(b, GLOW, out * 0.722, v(0.12, 0.008, 0.03), turn, 0.3)
    if index % 3 == 0 then
      block(b, PLATING, out * 0.95, v(0.09, 0.13, 0.16), turn, 0.15)
      block(b, TRIM, out * 1.085, v(0.095, 0.012, 0.165), turn, 0.2)
      beam(b, FRAME, out * 0.90 + v(0, 0, 0.12), out * 0.62 + v(0, 0, 0.62), 0.035)
      beam(b, FRAME, out * 0.90 + v(0, 0, -0.12), out * 0.66 + v(0, 0, -0.50), 0.035)
      block(b, GLOW, out * 0.62 + v(0, 0, 0.64), v(0.03, 0.03, 0.03), v(0, 0, a), 0.45)
    end
  end
  block(b, PATCH, v(0.0, 1.14, 0.0), v(0.10, 0.07, 0.12), nil, 0.14)
  block(b, GLOW, v(0, 1.15, 0.122), v(0.07, 0.02, 0.004), nil, 0.3)
  mast(b, v(0.04, 1.21, 0), 0.30, 0.02)
end

-- The model of a stargate. (One for everybody, until gates are somebody's.)
function Starbase.Gate(): Made
  return finish("gate", gate, WORKS, 4.0, 0.11)
end

local shell: Model? = nil

-- The field: a unit sphere to be scaled to the field's radius.
function Starbase.Field(): Model
  if shell == nil then
    local shader = ShaderInstance_Create(Shader_Create("npm.jsl", "field.jsl"))
    ShaderInstance_SetState(shader, "BlendModeAdditive")
    ShaderInstance_SetState(shader, "ZWritableOff")
    ShaderInstance_SetState(shader, "CullModeDisabled")
    ShaderInstance_SetVec3(shader, "fieldTint", vector.create(0.42, 0.68, 1.0))
    ShaderInstance_SetFloat(shader, "fieldGlow", 0.5)
    ShaderInstance_Link(shader)
    local model = Model_Create()
    Model_AddShell(model, Mesh_SetU(Mesh_BoxSphere(40, true), 1), shader)
    shell = model
  end
  return shell :: Model
end

-- How big a tower stands in its field: its radius, as a share of the
-- field's. (EVE's is a tenth to a fifth; ours stands larger in a
-- smaller field.)
Starbase.TOWER = 0.28

-- The weapons a battery may carry, of each kind. Which one a given
-- battery has follows from the station's seed.
local GUNS = { "artillery.large", "railgun.large", "laser.beam.large", "blaster.large", "laser.pulse.large", "autocannon.large" }
-- Metres to one of a weapon drawing's units, on a battery.
local BATTERY = 26

-- One thing of a station to draw: where its middle is from the middle
-- of the station (metres), which way it faces, and how many metres one
-- of its model's units is. 'arm' is the weapon type standing on a
-- battery, and 'unit' then how many metres one of that weapon's is.
-- ('up' is which way the model's own top goes, if not up.)
export type Part = { id: string, model: Model, at: vector, look: vector, up: vector?, scale: number, radius: number, arm: string?,
  unit: number? }

export type Layout = { tower: Part, modules: { Part }, field: number }

local function dice(n: number): number
  return (math.sin(n * 12.9898) * 43758.5453) % 1
end

-- A station laid out: 'variety' and 'radius' are the station's own
-- (Describe/System), and 'seed' its seed. The field is the station's
-- radius; the tower stands in the middle of it; its modules stand round
-- it inside the field, the big ones nearer, on several levels and clear
-- of each other; its batteries stand near the edge, high and low.
--
-- 'given' is what the station is made of, if the game has said
-- (Core.Query.Station): its tower then says whose it is. Without it,
-- it is what a station of that kind and size would be that is nobody's
-- starting place. 'dark' is a tower with no fuel: it has no field.
function Starbase.Layout(variety: string, radius: number, seed: number, faction: string?, given: Structures.Makeup?,
  dark: boolean?): Layout
  local makeup = given or Structures.Makeup(variety, radius, faction or "vessari")
  local class = makeup.ship
  if class then
    -- A colony ship: the ship, as long as the station is across, lying
    -- level and heading where its seed says. Nothing stands round it:
    -- what it has is aboard. (Its 'tower' is the ship.)
    local made = Capital.Build(class)
    local heading = dice(seed) * 2 * math.pi
    return { tower = { id = class, model = made.model, at = vector.create(0, 0, 0),
      look = vector.create(math.cos(heading), 0, math.sin(heading)), scale = radius / made.radius, radius = radius },
      modules = {}, field = 0 }
  end
  local type = Structures.towerById[makeup.tower :: string]
  local owner = faction or type.faction
  local towerRadius = radius * Starbase.TOWER
  local tower = Starbase.TowerPart(owner, type.size, vector.create(0, 0, 0), towerRadius)
  tower.id = type.id
  local layout: Layout = { tower = tower, modules = {}, field = if dark then 0 else radius }

  -- Where each would like to be: round the tower by turns of the golden
  -- angle, on three levels, batteries farthest out.
  local start = dice(seed) * 2 * math.pi
  local arrays, batteries = 0, 0
  for _, id in makeup.modules do
    local module = Structures.moduleById[id]
    local model = Starbase.Module(id)
    local battery = module.service == "defence"
    local angle, out, height
    if battery then
      batteries += 1
      angle = start + 1.1 + batteries * 2.399963
      out = radius * 0.80
      height = radius * (if batteries % 2 == 0 then 0.34 else -0.30)
    else
      arrays += 1
      angle = start + arrays * 2.399963
      out = towerRadius * 0.55 + module.radius + radius * (0.10 + 0.07 * (arrays % 3))
      height = radius * ({ 0.05, -0.24, 0.30 })[arrays % 3 + 1]
    end
    local flat = vector.create(math.cos(angle), 0, math.sin(angle))
    local part: Part = {
      id = id, model = model.model, at = flat * math.min(out, radius * 0.9 - module.radius) + vector.create(0, height, 0),
      -- (a shipyard lies along the way round; everything else faces out)
      look = if id == "array.assembly" then vector.create(-flat.z, 0, flat.x) else flat,
      scale = module.radius / model.radius, radius = module.radius,
    }
    if battery then
      part.arm = if id == "battery.missile" then "launcher.cruise" else GUNS[math.floor(dice(seed + batteries * 3.7) * #GUNS) + 1]
      part.unit = BATTERY
    end
    table.insert(layout.modules, part)
  end

  -- Then they are shouldered apart, and off the tower, and kept in the field.
  for _ = 1, 24 do
    for i, a in layout.modules do
      for j = i + 1, #layout.modules do
        local other = layout.modules[j]
        local apart = a.at - other.at
        local gap = vector.magnitude(apart)
        local need = (a.radius + other.radius) * 1.08
        if gap < need then
          local push = (if gap > 1e-3 then apart / gap else vector.create(1, 0, 0)) * ((need - gap) / 2)
          a.at += push
          other.at -= push
        end
      end
      -- (the tower is tall and narrow: stand clear of its axis)
      local flat = vector.create(a.at.x, 0, a.at.z)
      local off = vector.magnitude(flat)
      local clear = towerRadius * 0.6 + a.radius
      if off < clear and math.abs(a.at.y) < towerRadius + a.radius then
        a.at += (if off > 1e-3 then flat / off else vector.create(1, 0, 0)) * (clear - off)
      end
      local far = vector.magnitude(a.at)
      if far + a.radius > radius * 0.94 then
        a.at *= (radius * 0.94 - a.radius) / far
      end
    end
  end
  return layout
end

local UP = vector.create(0, 1, 0)

-- Put a laid-out station into a scene: its tower, its modules, what
-- stands on its batteries, and its field (if it has one), as scenery in
-- 'container' with the station's middle at 'origin'. 'metres' is how
-- long a metre is there. Returns the objects, the tower first.
function Starbase.Raise(layout: Layout, container: Object, origin: vector, metres: number): { Object }
  local objects: { Object } = {}
  local function scenery(model: Model): Object
    local object = Object_Scenery({})
    Object_SetRenderable(object, model)
    container:AddInterior(object)
    table.insert(objects, object)
    return object
  end
  local function stand(part: Part)
    local object = scenery(part.model)
    local size = part.scale * metres
    object:SetScale(vector.create(size, size, size))
    object:SetPos(origin + part.at * metres)
    Object_SetAxes(object, part.look, part.up or UP)
    local arm = if part.arm then Arms.Build(part.arm) else nil
    if arm then
      -- (on the ring of the battery's stand, facing the way the stand does, at rest)
      local base: Object? = if arm.base then scenery(arm.base) else nil
      local gun = scenery(arm.gun)
      Arms.Place(arm, base, gun, origin + (part.at + vector.create(0, 0.04 * part.scale, 0)) * metres, UP, part.look, nil,
        (part.unit or 1) / arm.scale * metres)
    end
  end
  stand(layout.tower)
  for _, part in layout.modules do
    stand(part)
  end
  if layout.field > 0 then
    local field = scenery(Starbase.Field())
    local size = layout.field * metres
    field:SetScale(vector.create(size, size, size))
    field:SetPos(origin)
  end
  return objects
end

return Starbase
