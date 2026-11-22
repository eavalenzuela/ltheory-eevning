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
local Citadel = require("@lt/Game/View/Citadel")
local Hull = require("@lt/Game/View/Hull")
local Plates = require("@lt/Game/View/Plates")
local Structures = require("@lt/Core/Data/Structures")
local Tower = require("@lt/Game/View/Tower")

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
  -- A moon drill: a bore column longer than anything else round the
  -- tower, through a collar of girders, with its drive in a drum at the
  -- head and a cutting head lit at the foot; and two hoppers, piped to
  -- the column, for what comes up.
  ["array.drill"] = function(b)
    -- the collar, braced to the head and to the column
    for _, z in { -0.30, 0.30 } do
      beam(b, FRAME, v(-0.42, 0.10, z), v(0.42, 0.10, z), 0.032)
    end
    for _, x in { -0.42, 0.42 } do
      beam(b, FRAME, v(x, 0.10, -0.30), v(x, 0.10, 0.30), 0.032)
    end
    for _, corner in { v(-0.42, 0.10, -0.30), v(0.42, 0.10, -0.30), v(-0.42, 0.10, 0.30), v(0.42, 0.10, 0.30) } do
      beam(b, FRAME, corner, v(corner.x * 0.3, 0.58, corner.z * 0.3), 0.020)
      beam(b, FRAME, corner, v(0, -0.42, 0), 0.018)
    end
    -- the column, banded, and the drive at its head
    block(b, PLATING, v(0, -0.15, 0), v(0.075, 0.72, 0.075), nil, 0.3)
    for _, y in { 0.30, -0.10, -0.50 } do
      block(b, FRAME, v(0, y, 0), v(0.10, 0.025, 0.10), nil, 0.3)
    end
    drum(b, v(0, 0.70, 0), 0.20, 0.30, PLATING)
    block(b, TRIM, v(0, 0.53, 0), v(0.215, 0.020, 0.215), nil, 0.3)
    windows(b, v(0, 0.70, 0), 0.196, 2, 0.018)
    -- the cutting head: wider than the column, banded in warning, and
    -- lit where it bites
    block(b, FRAME, v(0, -0.86, 0), v(0.13, 0.07, 0.13), nil, 0.3)
    block(b, TRIM, v(0, -0.775, 0), v(0.135, 0.015, 0.135), nil, 0.3)
    block(b, FRAME, v(0, -0.95, 0), v(0.085, 0.04, 0.085), v(math.pi / 4, 0, 0), 0.3)
    block(b, GLOW, v(0, -0.996, 0), v(0.05, 0.008, 0.05), nil, 0.4)
    -- the hoppers, unlike, on arms from the collar
    drum(b, v(0.60, 0.02, 0.04), 0.15, 0.50)
    drum(b, v(-0.58, -0.06, -0.06), 0.13, 0.40, PLATING)
    beam(b, FRAME, v(0.42, 0.10, 0.04), v(0.60, 0.10, 0.04), 0.024)
    beam(b, FRAME, v(-0.42, 0.10, -0.06), v(-0.58, 0.10, -0.06), 0.024)
    conduit(b, { v(0.075, -0.30, 0), v(0.34, -0.38, 0.02), v(0.60, -0.25, 0.04) }, 0.028)
    conduit(b, { v(-0.075, -0.44, 0), v(-0.32, -0.48, -0.04), v(-0.58, -0.27, -0.06) }, 0.026)
    -- a cabin on the collar, and a mast on the drive
    block(b, PATCH, v(0.20, 0.20, 0.38), v(0.12, 0.09, 0.09), nil, 0.14)
    block(b, GLOW, v(0.20, 0.22, 0.474), v(0.08, 0.02, 0.004), nil, 0.3)
    mast(b, v(0.05, 0.85, 0.04), 0.15, 0.01)
  end,
  -- A jump beacon: a tall mast on a small drum, with three rings round it
  -- that grow toward its head, each lit, braced to the mast by spokes;
  -- and a lamp at its head and one at its foot. (A v0.)
  ["array.beacon"] = function(b)
    beam(b, FRAME, v(0, -0.90, 0), v(0, 0.90, 0), 0.035, 0.1)
    drum(b, v(0, -0.62, 0), 0.20, 0.30, PLATING)
    block(b, TRIM, v(0, -0.45, 0), v(0.215, 0.018, 0.215), nil, 0.3)
    for index, ring in { { -0.10, 0.26 }, { 0.30, 0.40 }, { 0.70, 0.56 } } do
      local y, out = ring[1], ring[2]
      local sides = 8
      for side = 0, sides - 1 do
        local a, c = side * 2 * math.pi / sides, (side + 1) * 2 * math.pi / sides
        beam(b, if index == 2 then PATCH else PLATING, v(out * math.cos(a), y, out * math.sin(a)), v(out * math.cos(c), y, out * math.sin(c)), 0.03, 0.1)
        if side % 2 == 0 then
          beam(b, FRAME, v(0, y, 0), v(out * math.cos(a), y, out * math.sin(a)), 0.012, 0.1)
          block(b, GLOW, v(out * math.cos(a), y + 0.035, out * math.sin(a)), v(0.03, 0.008, 0.03), nil, 0.4)
        end
      end
    end
    block(b, GLOW, v(0, 0.93, 0), v(0.04, 0.02, 0.04), v(math.pi / 4, 0, 0), 0.45)
    block(b, GLOW, v(0, -0.93, 0), v(0.03, 0.015, 0.03), v(math.pi / 4, 0, 0), 0.45)
  end,
  -- A reactor: a vessel of eight sides in a cage of girders, banded in
  -- warning and lit at its waist; a feed drum out on an arm either side
  -- of it, one for each thing it is fed, piped in at the top; what it
  -- makes let down into a hopper under it; and a stack on its head, lit
  -- where it vents.
  ["array.reactor"] = function(b)
    -- the vessel
    block(b, PLATING, v(0, 0.02, 0), v(0.27, 0.36, 0.27), nil, 0.3)
    block(b, PLATING, v(0, 0.02, 0), v(0.27, 0.36, 0.27), v(math.pi / 4, 0, 0), 0.3)
    block(b, TRIM, v(0, 0.30, 0), v(0.30, 0.018, 0.30), v(math.pi / 8, 0, 0), 0.3)
    block(b, TRIM, v(0, -0.26, 0), v(0.30, 0.018, 0.30), v(math.pi / 8, 0, 0), 0.3)
    windows(b, v(0, 0.02, 0), 0.272, 3, 0.022)
    -- its cage
    for _, x in { -0.40, 0.40 } do
      for _, z in { -0.40, 0.40 } do
        beam(b, FRAME, v(x, -0.50, z), v(x, 0.50, z), 0.028)
      end
    end
    for _, y in { -0.50, 0.50 } do
      for _, z in { -0.40, 0.40 } do
        beam(b, FRAME, v(-0.40, y, z), v(0.40, y, z), 0.024)
      end
      for _, x in { -0.40, 0.40 } do
        beam(b, FRAME, v(x, y, -0.40), v(x, y, 0.40), 0.024)
      end
    end
    beam(b, FRAME, v(-0.40, -0.50, 0.40), v(0.40, 0.50, 0.40), 0.014)
    beam(b, FRAME, v(0.40, -0.50, -0.40), v(-0.40, 0.50, -0.40), 0.014)
    -- the stack, and where it vents
    block(b, FRAME, v(0, 0.50, 0), v(0.12, 0.13, 0.12), nil, 0.3)
    block(b, PLATING, v(0, 0.74, 0), v(0.075, 0.13, 0.075), v(math.pi / 4, 0, 0), 0.3)
    block(b, GLOW, v(0, 0.88, 0), v(0.05, 0.012, 0.05), v(math.pi / 4, 0, 0), 0.45)
    -- a feed drum either side, on an arm, piped in at the top
    for index, side in { -1, 1 } do
      local at = v(side * 0.74, 0.10 * side, 0.06 * side)
      drum(b, at, 0.15, 0.58, if index == 1 then PATCH else PLATING)
      beam(b, FRAME, v(side * 0.40, -0.10, 0), at + v(-side * 0.14, -0.14, 0), 0.026)
      beam(b, FRAME, v(side * 0.40, 0.20, 0), at + v(-side * 0.14, 0.14, 0), 0.020)
      conduit(b, { at + v(0, 0.30, 0), at + v(-side * 0.16, 0.44, 0), v(side * 0.20, 0.44, 0) }, 0.028)
    end
    -- the hopper under it
    block(b, FRAME, v(0, -0.44, 0), v(0.10, 0.08, 0.10), nil, 0.3)
    block(b, PLATING, v(0, -0.68, 0), v(0.22, 0.14, 0.18), nil, 0.1)
    block(b, TRIM, v(0, -0.535, 0), v(0.225, 0.012, 0.185), nil, 0.1)
    block(b, GLOW, v(0.224, -0.68, 0), v(0.004, 0.03, 0.10), nil, 0.3)
    mast(b, v(0.38, 0.52, -0.38), 0.34, 0.02)
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

-- A piece of a tower that moves (Game/View/Tower): its model, drawn
-- about its pivot; where its pivot is, in the tower's own measure; and
-- how it moves.
export type Mover = { model: Model, pivot: vector, motion: Tower.Motion }

-- Something made: its model and how big it came out. A tower built in
-- sections has also what moves of it, and the corners of the box that
-- holds it and all of that, wherever it is turned.
export type Made = { model: Model, radius: number, movers: { Mover }?, lower: vector?, upper: vector? }

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

-- The towers of each people, by faction: for each of its three sizes,
-- a pick. A pick is what the tower browser shows and keeps (bin/launch
-- towers, App/towers.luau: the owner, 2026-11-15, "a generator for
-- them, so I can pick seeds and styles"), of a tower built in sections
-- (Game/View/Tower): its seed, its size (1 to 8: how much there is of
-- it), its build ('style': the shape it cuts) and its manner (how what
-- it is made of is made); its fold and where its weight is, where those
-- are said over what its seed says; and the paint it wears, where that
-- is not its people's own. A seed is a tower: any whole number is
-- another. Every one here is the owner's, as the browser's kept lines
-- said them. (Towers were grown as a hull is, Hull.GrownTower, from
-- 2026-11-15 until every people's were picks of the builds, the next
-- day: the owner's "remove the old grown styles", the fourth step of
-- the rework. The towers drawn by hand before either are kept, and are
-- what is built with Starbase.GROWN false.)
Starbase.GROWN = true
export type Pick = { seed: number, size: number, style: string, manner: string?, fold: number?, plan: string?,
  -- (one of Starbase.TOWER_PAINTS, as the browser's kept line says it)
  paint: string? }
local function sections(seed: number, size: number, build: string, manner: string, fold: number?, plan: string?, paint: string?): Pick
  return { seed = seed, size = size, style = build, manner = manner, fold = fold, plan = plan, paint = paint }
end
local PICKS: { [string]: { Pick } } = {
  -- The owner's picks, 2026-11-15 ("vessari towers", a line each as the
  -- browser keeps them: seed | size | build | manner | fold | weight |
  -- paint | tower_size): the small, the middling and the large. Every
  -- one is of size 8, its fold as its seed says, its weight in beads,
  -- and kept in the Talmar's paint.
  vessari = { sections(14051, 8, "gantry", "poured", nil, "beads", "talmar"), sections(56725, 8, "parasol", "poured", nil, "beads", "talmar"),
    sections(41148, 8, "ring", "poured", nil, "beads", "talmar") },
  -- ("talmar towers", the same day and the same way: three rings in flat
  -- plate, six-fold, in the civil paint; the large one's weight at its ends.)
  talmar = { sections(74964, 8, "ring", "blocky", 6, "beads", "civil"), sections(92814, 8, "ring", "blocky", 6, "beads", "civil"),
    sections(41595, 8, "ring", "blocky", 6, "ends", "civil") },
  -- ("orun towers", the same day: three of the mixed build in round skins,
  -- in their own paint; the small one six-fold with its weight at its
  -- ends, the others' weight in their middles and their fold as their
  -- seeds say.)
  orun = { sections(41597, 8, "mixed", "cloud", 6, "ends", "orun"), sections(36333, 8, "mixed", "cloud", nil, "middle", "orun"),
    sections(74142, 8, "mixed", "cloud", nil, "middle", "orun") },
  -- ("unbound towers", the same day: the pirates', who had the
  -- Vessari's until then. Three of the mixed build, two in open frames
  -- and the large one in flat plate, kept in the paint the browser calls
  -- the Nimia's: for which, the Nimia having no look of their own yet,
  -- it shows the Vessari's. They wear what was seen.)
  unbound = { sections(79278, 8, "mixed", "spar", nil, "middle", "nimia"), sections(44225, 8, "mixed", "spar", nil, "middle", "nimia"),
    sections(96371, 8, "mixed", "blocky", nil, "middle", "nimia") },
  -- ("nimia towers", the last of the lists: three about a sphere, as was
  -- ruled for them, in the Talmar's paint. The small and the middling
  -- are of size 2, poured, their weight at their ends; the large of size
  -- 8, in round skins, three-fold, its weight high.)
  nimia = { sections(27181, 2, "spherical", "poured", nil, "ends", "talmar"), sections(20172, 2, "spherical", "poured", nil, "ends", "talmar"),
    sections(34670, 8, "spherical", "cloud", 3, "high", "talmar") },
  -- ("vail towers", the same day: three about a torus, as was ruled for
  -- them, in round skins and the Orun's paint; of three, six and eight
  -- spokes, the middling one of size 7.)
  vail = { sections(66932, 8, "toroidal", "cloud", 3, "middle", "orun"), sections(2582, 7, "toroidal", "cloud", 6, "middle", "orun"),
    sections(88513, 8, "toroidal", "cloud", 8, "middle", "orun") },
}
-- What a pick can be: its size (1 to so many), its build ('style'), its
-- manner, and its fold and where its weight is, which can be said over
-- what its seed says (how many times a thing is there about its
-- upright; and low, high, in its middle, at its ends, in beads).
Starbase.TOWER_SIZES = 8
Starbase.TOWER_STYLES = Tower.BUILDS
Starbase.TOWER_MANNERS = Tower.MANNERS
Starbase.TOWER_FOLDS = Tower.FOLDS
Starbase.TOWER_PLANS = Tower.PLANS

-- The paints a tower can be shown in by the browser: the factions whose look there is.
Starbase.TOWER_PAINTS = { "vessari", "talmar", "orun", "kethri", "nimia", "vail", "civil" }

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

-- The tower of a pick, made: built in sections, with what moves of it apart.
local function towerOf(key: string, chosen: Pick, look: Plates.Look, sheets: number): Made
  local kept = made[key]
  if kept then
    return kept
  end
  local b = Plates.New(#key * 2.31, 0.04)
  local count = 0
  local pieces = Tower.Build(b, { seed = chosen.seed, size = chosen.size, build = chosen.style, manner = chosen.manner or Tower.MANNERS[1],
    fold = chosen.fold, plan = chosen.plan }, function(): Builder
    count += 1
    return Plates.New(#key * 2.31 + count * 7.7, 0.04)
  end)
  local model, lower, upper = Plates.Finish(b, look, sheets)
  local movers: { Mover } = {}
  for _, piece in pieces do
    if piece.b.kept > 0 then
      local turning, low, high = Plates.Finish(piece.b, look, sheets)
      local kind = piece.motion.kind
      if kind == "blink" then
        -- (which is where it is)
        lower, upper = vector.min(lower, low), vector.max(upper, high)
      elseif kind == "spin" then
        -- (as far out as it reaches, all the way round the upright)
        local far = math.max(math.abs(low.x), math.abs(high.x), math.abs(low.y), math.abs(high.y))
        lower = vector.min(lower, piece.pivot + vector.create(-far, -far, low.z))
        upper = vector.max(upper, piece.pivot + vector.create(far, far, high.z))
      else
        -- (as far as it reaches, whichever way it is turned)
        local far = math.max(vector.magnitude(low), vector.magnitude(high))
        lower = vector.min(lower, piece.pivot - vector.create(far, far, far))
        upper = vector.max(upper, piece.pivot + vector.create(far, far, far))
      end
      table.insert(movers, { model = turning, pivot = piece.pivot, motion = piece.motion })
    end
  end
  local size = upper - lower
  local result: Made = { model = model, radius = math.max(size.x, size.y, size.z) / 2, movers = movers, lower = lower, upper = upper }
  made[key] = result
  return result
end

-- A tower to be tried in the game before it is anybody's
-- (GameDebug.TowerPick): until the game is closed, a faction's tower of
-- a size (1 to 3) is this pick; or, with none, what it was. Stations
-- made before are what they were made as.
local TRIED: { [string]: Pick? } = {}
function Starbase.Try(faction: string, size: number, chosen: Pick?)
  TRIED[`{faction}.{size}`] = chosen
end

-- The model of a faction's tower of a size (1 to 3). A faction whose
-- tower nobody has drawn yet gets the Vessari's.
function Starbase.Tower(faction: string, size: number): Made
  if Starbase.GROWN then
    -- (a people's towers are its picks, whether it has a look of its own
    -- or not: a pick says what it is painted in. Until 2026-11-16 one
    -- with no look, as the Nimia are, was given the Vessari's towers)
    local owner = if PICKS[faction] then faction else "vessari"
    local paints = PAINTS[owner]
    -- (the look a pick is drawn in: the one it says, or its own people's)
    local function lookOf(chosen: Pick): Plates.Look
      local wears = chosen.paint
      if wears and PAINTS[wears] then
        return PAINTS[wears][size]
      elseif wears then
        -- (a paint with no look of its own is the Vessari's, as the browser shows it: Starbase.Grown)
        return Hull.looks[wears] or Hull.looks.vessari
      end
      return if paints then paints[size] else Hull.looks[owner] or Hull.looks.vessari
    end
    local tried = TRIED[`{faction}.{size}`]
    if tried then
      return towerOf(`tower.tried.{owner}.{size}.{tried.seed}.{tried.size}.{tried.style}.{tried.manner}.{tried.fold}.{tried.plan}.{tried.paint}`,
        tried, lookOf(tried), 4.5 + 2.5 * size)
    end
    local picked = PICKS[owner][size]
    return towerOf(`tower.picked.{owner}.{size}`, picked, lookOf(picked), 4.5 + 2.5 * size)
  end
  local designs = TOWERS[faction] or TOWERS.vessari
  local owner = if TOWERS[faction] then faction else "vessari"
  local paints = PAINTS[owner]
  return finish(`tower.{owner}.{size}`, designs[size], if paints then paints[size] else Hull.looks[owner], 4.5 + 2.5 * size, 0.11)
end

-- A tower as the generator builds it from a pick, in a faction's paint
-- (one of Starbase.TOWER_PAINTS): for the tower browser. It lies along
-- z, its top toward +z. Made once and kept.
function Starbase.Shown(chosen: Pick, paint: string): Made
  local paints = PAINTS[paint]
  local look = if paints then paints[2] else Hull.looks[paint] or Hull.looks.vessari
  local shade = math.clamp((chosen.size + 1) // 2, 1, 3)
  return towerOf(`tower.pick.{chosen.seed}.{chosen.size}.{chosen.style}.{chosen.manner}.{chosen.fold}.{chosen.plan}.{paint}`,
    chosen, look, 4.5 + 2.5 * shade)
end

-- A faction's tower of a size as a thing to put in a scene (Raise): its
-- middle at 'at' and 'towerRadius' metres in radius, upright whichever
-- way its drawing lies.
function Starbase.TowerPart(faction: string, size: number, at: vector, towerRadius: number): Part
  local made = Starbase.Tower(faction, size)
  -- (a tower that is a pick lies along z, whoever's it is)
  local lying = Starbase.GROWN or (LYING[faction] == true and TOWERS[faction] ~= nil)
  local scale = towerRadius / made.radius
  -- (a tower built in sections is not built about its own middle, and
  -- its ends are not the same way off from where it began: it is stood
  -- with its middle where the station is, as the browser stands it.
  -- Until its first was picked, 2026-11-15, one stood as much as half
  -- its height off)
  local lower, upper = made.lower, made.upper
  if lying and lower and upper then
    at += vector.create(0, -(lower.z + upper.z) * 0.5 * scale, 0)
  end
  return {
    id = `tower.{faction}.{size}`, model = made.model, at = at,
    look = if lying then vector.create(0, 1, 0) else vector.create(0, 0, 1),
    up = if lying then vector.create(0, 0, -1) else nil,
    scale = scale, radius = towerRadius, movers = made.movers,
    wide = if lying and lower and upper then math.max(math.abs(lower.x), math.abs(upper.x), math.abs(lower.y), math.abs(upper.y)) * scale
      else nil,
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

local bubbleShell: Model? = nil

-- An interdiction field (module expansion, 2026-11-16): the field's own
-- shell, in a warning amber. A unit sphere to be scaled to its radius.
function Starbase.Bubble(): Model
  if bubbleShell == nil then
    local shader = ShaderInstance_Create(Shader_Create("npm.jsl", "field.jsl"))
    ShaderInstance_SetState(shader, "BlendModeAdditive")
    ShaderInstance_SetState(shader, "ZWritableOff")
    ShaderInstance_SetState(shader, "CullModeDisabled")
    ShaderInstance_SetVec3(shader, "fieldTint", vector.create(1.0, 0.58, 0.22))
    ShaderInstance_SetFloat(shader, "fieldGlow", 0.35)
    ShaderInstance_Link(shader)
    local model = Model_Create()
    Model_AddShell(model, Mesh_SetU(Mesh_BoxSphere(40, true), 1), shader)
    bubbleShell = model
  end
  return bubbleShell :: Model
end

-- The model of a stargate. (One for everybody, until gates are somebody's.)
function Starbase.Gate(): Made
  return finish("gate", gate, WORKS, 4.0, 0.11)
end

-- Stargate mock-ups (2026-11-21, the owner: "redo the warp gates with a
-- similar, Stargate-esque vibe" to the wormhole citadel's round rings
-- with a light band round the middle). Eight were mocked up, all
-- in smooth turned rings (Plates.Revolve, as the hulls' tori are), each
-- with its band of light. Front toward +z, as Starbase.Gate's; a ship
-- comes in from -z. In the game since 2026-11-21 (Core's Galaxy.GateDesign
-- says which a gate is); the viewer's 'gate-N' views show them too.
-- (the owner kept three of the eight, 2026-11-21, liked in this order; the
-- game is to use more than one: the dial the standard human gate, the
-- gyre for alien-held systems, and a mix of the two to unclaimed space;
-- the bell for the longest tenth of gates, its build what keeps a long
-- jump stable; the orrery, theirs too, an alien long gate)
Starbase.GATE_DESIGNS = { "gyre", "bell", "dial", "orrery" }

-- A closed cross-section for a ring: a rounded box (a superellipse,
-- 'p' 2 for an ellipse, higher for squarer) 'w' out from the axis each
-- way and 'd' along it, its middle 'r' out and 'z' along; run clockwise
-- in (out, along). (Run anticlockwise, as Plates.Revolve's note says a
-- torus should be, it came out inside out and lit dark: checked in the
-- viewer 2026-11-21 beside a plated block.)
local function section(r: number, z: number, w: number, d: number, p: number?): { vector }
  local points: { vector } = {}
  local e = 2 / (p or 2)
  local steps = 28
  for i = 0, steps - 1 do
    local a = i / steps * 2 * math.pi
    local c, s = math.cos(a), math.sin(a)
    local x = math.sign(c) * math.abs(c) ^ e
    local y = math.sign(s) * math.abs(s) ^ e
    table.insert(points, v(r + w * x, z - d * y, 0))
  end
  return points
end
local function ring(b: Builder, part: number, r: number, z: number, w: number, d: number, p: number?, sides: number?)
  Plates.Revolve(b, part, section(r, z, w, d, p), sides or 120, true)
end
-- (a ring about another axis or through another point, or an arc of one)
local function ringAt(b: Builder, part: number, at: vector, axis: vector, r: number, w: number, d: number, p: number?, from: number?,
  to: number?)
  Plates.RevolveAt(b, part, section(r, 0, w, d, p), 120, true, at, axis, from, to)
end
-- A smooth rod through points, so thick at each.
local function rod(b: Builder, part: number, path: { vector }, radii: { number })
  Plates.Tube(b, part, path, radii, 14)
end
-- A smooth pod (an ellipsoid) 'w' round and 'd' long, along 'axis' at 'at'.
local function pod(b: Builder, part: number, at: vector, axis: vector, w: number, d: number)
  local profile: { vector } = {}
  for i = 0, 12 do
    local a = -math.pi / 2 + i / 12 * math.pi
    table.insert(profile, v(math.max(1e-4, math.cos(a) * w), -math.sin(a) * d, 0))
  end
  Plates.RevolveAt(b, part, profile, 28, false, at, axis)
end
local function around(a: number, r: number, z: number): vector
  return v(math.cos(a) * r, math.sin(a) * r, z)
end
-- A turn (as Plates.Block takes one) that lays a box's x along the way
-- round at angle 'a' and its y out from the middle.
local function rolled(a: number): vector
  return v(0, 0, a - math.pi / 2)
end

-- What turns of a stargate (2026-11-21, the owner: the gyre's gimbals
-- turn, the dial's inner ring "should spin slowly at rest, then speed up
-- as ships approach to jump", the bell "should roll at moderate speed, at
-- all times"): each piece a model of its own, drawn about the gate's
-- middle, turning about 'axis' (in the axes of what it rides on: the
-- gate, or the piece 'parent', by its place in the list) at 'rate'
-- radians a second, from 'rest' radians round. A 'steady' piece keeps
-- its rate whatever the gate's pace.
export type GatePiece = { model: Model, axis: vector, rate: number, rest: number, parent: number?, steady: boolean? }
-- A stargate made: what of it stands still (nil if all of it turns), how
-- far it reaches from its middle, and what turns.
-- 'opening': how far out the mouth is (what flies through it), in the
-- same units.
export type GateMade = { model: Model?, radius: number, opening: number, pieces: { GatePiece } }

-- How wide a stargate's mouth is drawn, a share of the gate's radius in
-- the Core (Describe/System: 1500 m), whichever design it is: the
-- designs reach out as far as they each do round it. (Starbase.Gate's lit
-- ring was about this far out.)
Starbase.GATE_OPENING = 0.70
local GATE_OPENINGS: { [string]: number } = { dial = 0.805, gyre = 0.875, bell = 0.85, orrery = 0.85 }
-- ('piece' gives the new piece's builder and its place in the list, for a piece that rides on it)
type GateParts = { b: Builder, piece: (axis: vector, rate: number, rest: number, parent: number?, steady: boolean?) -> (Builder, number) }

local GATE_DRAWN: { [string]: (parts: GateParts) -> () } = {}

-- The paints of the gates (the owner, 2026-11-21): the dial "more
-- slate-like, black-grey"; the gyre "a burnt-ochre dark red-orange, with
-- stone-like texture"; the bell "a solid, dark grey-black metal" (its
-- collar is frame, which is bare metal with no sheets or seams: the
-- plating's straight seams ran at odd angles over its curves).
local GATE_LOOKS: { [string]: Plates.Look } = {
  dial = {
    plating = { 0.115, 0.12, 0.13 }, patch = { 0.16, 0.165, 0.175 }, frame = { 0.06, 0.062, 0.068 }, glow = { 0.78, 0.93, 1.0 },
    trim = { 0.2, 0.2, 0.21 }, wear = 0.12, rust = 0.02, sheets = 2.0, stone = 0.55,
  },
  gyre = {
    plating = { 0.31, 0.125, 0.05 }, patch = { 0.27, 0.10, 0.04 }, frame = { 0.10, 0.06, 0.045 }, glow = { 0.78, 0.93, 1.0 },
    trim = { 0.5, 0.3, 0.1 }, wear = 0.08, rust = 0.04, sheets = 2.0, stone = 1.0,
  },
  bell = {
    plating = { 0.34, 0.37, 0.41 }, patch = { 0.55, 0.56, 0.55 }, frame = { 0.075, 0.078, 0.085 }, glow = { 0.78, 0.93, 1.0 },
    trim = { 0.74, 0.55, 0.08 }, wear = 0.1, rust = 0.02, sheets = 4.0,
  },
}
GATE_LOOKS.orrery = GATE_LOOKS.gyre

-- Dial: a heavy outer ring and, inside it, a thinner one marked all
-- round with lit glyphs, which turns; the band of light in the gap
-- between them, and four guides lapping over the inner ring's faces
-- from the outer.
GATE_DRAWN.dial = function(parts: GateParts)
  local b = parts.b
  ring(b, PLATING, 1.08, 0, 0.12, 0.11, 4)
  ring(b, FRAME, 1.08, 0.108, 0.08, 0.006, 4)
  ring(b, FRAME, 1.08, -0.108, 0.08, 0.006, 4)
  for index = 0, 8 do
    local a = math.pi / 2 + index / 9 * 2 * math.pi
    for _, z in { 0.116, -0.116 } do
      block(b, GLOW, around(a, 1.08, z), v(0.018, 0.04, 0.004), rolled(a), 0.3)
    end
  end
  ring(b, GLOW, 0.937, 0, 0.012, 0.05, 2)
  for index = 0, 3 do
    local a = math.pi / 4 + index * math.pi / 2
    for _, z in { 0.093, -0.093 } do
      block(b, FRAME, around(a, 0.95, z), v(0.05, 0.06, 0.012), rolled(a), 0.35)
    end
    block(b, GLOW, around(a, 1.205, 0), v(0.04, 0.012, 0.06), rolled(a), 0.4)
  end
  local inner = parts.piece(v(0, 0, 1), 0.06, 0)
  ring(inner, PATCH, 0.86, 0, 0.055, 0.075, 3)
  for index = 0, 38 do
    local a = index / 39 * 2 * math.pi
    local long = index % 3 == 0
    block(inner, GLOW, around(a, 0.86, 0.076), v(0.014, if long then 0.03 else 0.018, 0.004), rolled(a), 0.3)
    block(inner, GLOW, around(a, 0.86, -0.076), v(0.014, if long then 0.03 else 0.018, 0.004), rolled(a), 0.3)
  end
end

-- Two gimbals, nested, round what stands still ('still', reaching 'from'
-- out from the middle where the first's pivots are): the first turns on
-- pivots at its sides, the second on pivots at the first's top and foot,
-- carried round with it. Each drawn in the plane of the gate and turned
-- out of it.
local function gimbals(parts: GateParts, still: Builder, from: number, R1: number, R2: number)
  -- (a bearing: an axle out from the ring within, a hub on the gimbal, a
  -- lit collar round the hub, a cap beyond)
  local function bearing(within: Builder, gimbal: Builder, way: vector, from: number, r: number)
    for _, s in { 1, -1 } do
      local p = way * s
      rod(within, FRAME, { p * from, p * (r + 0.1) }, { 0.04, 0.04 })
      pod(gimbal, PLATING, p * r, p, 0.1, 0.085)
      ringAt(gimbal, GLOW, p * r, p, 0.1, 0.006, 0.014, 2)
      pod(gimbal, PATCH, p * (r + 0.1), p, 0.05, 0.04)
    end
  end
  local first, carrier = parts.piece(v(1, 0, 0), 0.15, 0.55)
  ring(first, PATCH, R1, 0, 0.055, 0.065, 2.8)
  ring(first, GLOW, R1 - 0.057, 0, 0.007, 0.026, 2)
  bearing(still, first, v(1, 0, 0), from, R1)
  local second = parts.piece(v(0, 1, 0), -0.22, -0.5, carrier)
  ring(second, PATCH, R2, 0, 0.055, 0.065, 2.8)
  ring(second, GLOW, R2 - 0.057, 0, 0.007, 0.026, 2)
  bearing(first, second, v(0, 1, 0), R1 + 0.055, R2)
end

-- Gyre: a ring in two gimbals, nested: the first turns on pivots at the
-- ring's sides, the second on pivots at the first's top and foot, and is
-- carried round with it (the wormhole citadel's turning rings, kin to
-- it). Every ring lit.
GATE_DRAWN.gyre = function(parts: GateParts)
  local b = parts.b
  ring(b, PLATING, 1.0, 0, 0.11, 0.09, 3)
  ring(b, FRAME, 0.99, 0.088, 0.06, 0.01, 3)
  ring(b, FRAME, 0.99, -0.088, 0.06, 0.01, 3)
  ring(b, GLOW, 0.884, 0, 0.01, 0.04, 2.5)
  gimbals(parts, b, 1.11, 1.27, 1.5)
end

-- Bell: a deep collar, flared at both lips and pinched at its throat,
-- a nozzle to fly through: a band of light round the throat and a thin
-- one round each lip, ribs down its outside. All of it rolls.
-- (the bell's body, into 'b', its collar drawn as 'part'; with its lit belt round the outside middle, or not)
local function bellBody(b: Builder, belt: boolean, part: number)
  -- (the profile anticlockwise: along the outside aft to fore, round the
  -- fore lip, back through the throat, round the aft lip)
  local profile: { vector } = {}
  local function add(r: number, z: number)
    table.insert(profile, v(r, z, 0))
  end
  local steps = 18
  for i = 0, steps do
    local t = i / steps
    local z = -0.5 + t
    add(1.24 - 0.06 * math.sin(t * math.pi), z)
  end
  add(1.22, 0.53)
  add(1.17, 0.545)
  for i = steps, 0, -1 do
    local t = i / steps
    local z = -0.5 + t
    -- (the inside: flared at the lips, pinched to 0.86 at the middle)
    local u = (t - 0.5) * 2
    add(0.86 + 0.26 * u * u, z)
  end
  add(1.17, -0.545)
  add(1.22, -0.53)
  -- (that runs anticlockwise in (out, along): turned about, to run as section's do)
  local turned: { vector } = {}
  for i = #profile, 1, -1 do
    table.insert(turned, profile[i])
  end
  Plates.Revolve(b, part, turned, 120, true)
  ring(b, GLOW, 0.856, 0, 0.008, 0.07, 2)
  ring(b, GLOW, 1.13, 0.545, 0.012, 0.004, 2)
  ring(b, GLOW, 1.13, -0.545, 0.012, 0.004, 2)
  -- (ribs along its outside, following the barrel's waist; two collars
  -- near its lips; between, a lit belt broken by the ribs)
  local function outside(z: number): number
    return 1.24 - 0.06 * math.sin((z + 0.5) * math.pi)
  end
  for index = 0, 11 do
    local a = (index + 0.5) / 12 * 2 * math.pi
    local path: { vector } = {}
    local radii: { number } = {}
    for k = 0, 8 do
      local z = -0.46 + 0.92 * k / 8
      table.insert(path, around(a, outside(z) + 0.012, z))
      table.insert(radii, 0.024)
    end
    rod(b, FRAME, path, radii)
  end
  for _, z in { 0.4, -0.4 } do
    ring(b, FRAME, outside(z) + 0.008, z, 0.02, 0.035, 3)
  end
  if belt then
    ring(b, GLOW, outside(0) + 0.004, 0, 0.006, 0.018, 2)
  end
end

GATE_DRAWN.bell = function(parts: GateParts)
  bellBody((parts.piece(v(0, 0, 1), 0.3, 0, nil, true)), true, FRAME)
end

-- Orrery (the owner's idea, 2026-11-21: an alien long gate, "bell-in-the-
-- middle-gyres-around ... in the alien stone material"): the bell, rolling
-- inside a collar that stands still round its waist, and the gyre's two
-- nested gimbals pivoted on the collar, clear of the bell's sweep.
GATE_DRAWN.orrery = function(parts: GateParts)
  local b = parts.b
  bellBody((parts.piece(v(0, 0, 1), 0.3, 0, nil, true)), false, PLATING)
  ring(b, PLATING, 1.29, 0, 0.05, 0.07, 3)
  ring(b, GLOW, 1.342, 0, 0.006, 0.03, 2)
  for index = 0, 3 do
    local a = math.pi / 4 + index * math.pi / 2
    block(b, PATCH, around(a, 1.3, 0), v(0.06, 0.06, 0.09), rolled(a), 0.4)
  end
  gimbals(parts, b, 1.34, 1.52, 1.76)
end

local gatesMade: { [string]: GateMade } = {}

-- A stargate mock-up, by its number in Starbase.GATE_DESIGNS: what of it
-- stands still and what turns. Made once and kept.
function Starbase.GateDesign(index: number): GateMade
  local name = Starbase.GATE_DESIGNS[index]
  assert(name, `no stargate design {index}`)
  local kept = gatesMade[name]
  if kept then
    return kept
  end
  local seed = #name * 2.31
  local b = Plates.New(seed, 0.11)
  local drawn: { { b: Builder, axis: vector, rate: number, rest: number, parent: number?, steady: boolean? } } = {}
  GATE_DRAWN[name]({ b = b, piece = function(axis: vector, rate: number, rest: number, parent: number?, steady: boolean?): (Builder, number)
    local own = Plates.New(seed + (#drawn + 1) * 7.7, 0.11)
    table.insert(drawn, { b = own, axis = axis, rate = rate, rest = rest, parent = parent, steady = steady })
    return own, #drawn
  end })
  local look = GATE_LOOKS[name]
  local reach = 0
  local model: Model? = nil
  if b.kept > 0 then
    local still, lower, upper = Plates.Finish(b, look, nil)
    model = still
    reach = math.max(-lower.x, -lower.y, -lower.z, upper.x, upper.y, upper.z)
  end
  local pieces: { GatePiece } = {}
  for _, it in drawn do
    local turning, lower, upper = Plates.Finish(it.b, look, nil)
    -- (as far as it reaches, whichever way it is turned: about as far as its box's farthest side)
    reach = math.max(reach, -lower.x, -lower.y, -lower.z, upper.x, upper.y, upper.z)
    table.insert(pieces, { model = turning, axis = it.axis, rate = it.rate, rest = it.rest, parent = it.parent, steady = it.steady })
  end
  local made = { model = model, radius = reach, opening = GATE_OPENINGS[name], pieces = pieces }
  gatesMade[name] = made
  return made
end

-- The same, by its name.
function Starbase.GateNamed(name: string): GateMade
  local index = table.find(Starbase.GATE_DESIGNS, name)
  assert(index, `no stargate design {name}`)
  return Starbase.GateDesign(index)
end

-- A gate's turning pieces in a scene, and how far round each is.
export type GateMoving = { objects: { Object }, pieces: { GatePiece }, angles: { number }, look: vector, up: vector }

-- Put what turns of a gate into a scene: 'add' makes a thing of a model,
-- in the scene (placed and sized by the caller, at the gate's middle);
-- the gate faces 'look', with 'up' above it.
function Starbase.GateMovers(made: GateMade, add: (model: Model) -> Object, look: vector, up: vector): GateMoving
  local moving: GateMoving = { objects = {}, pieces = made.pieces, angles = {}, look = vector.normalize(look), up = vector.normalize(up) }
  for _, piece in made.pieces do
    table.insert(moving.objects, add(piece.model))
    table.insert(moving.angles, piece.rest)
  end
  Starbase.AnimateGate(moving, 0, 1)
  return moving
end

-- A vector turned 'angle' about the unit 'k' (Rodrigues' rule).
local function turnAbout(p: vector, k: vector, angle: number): vector
  local c, s = math.cos(angle), math.sin(angle)
  return p * c + vector.cross(k, p) * s + k * (vector.dot(k, p) * (1 - c))
end

-- Turn a gate's pieces on by 'dt' seconds, at 'pace' times their rates
-- at rest (1 at rest: the game raises it as ships come to jump; a steady
-- piece pays it no heed).
function Starbase.AnimateGate(moving: GateMoving, dt: number, pace: number)
  -- (each piece's axes, in the gate's: its x, y and z where they have been turned to)
  local frames: { { vector } } = {}
  local look, up = moving.look, moving.up
  local right = vector.cross(up, look)
  for index, piece in moving.pieces do
    moving.angles[index] += dt * piece.rate * (if piece.steady then 1 else pace)
    local angle = moving.angles[index]
    local base = if piece.parent then frames[piece.parent] else { v(1, 0, 0), v(0, 1, 0), v(0, 0, 1) }
    -- (its axis is in what it rides on's axes)
    local k = vector.normalize(base[1] * piece.axis.x + base[2] * piece.axis.y + base[3] * piece.axis.z)
    local frame = { turnAbout(base[1], k, angle), turnAbout(base[2], k, angle), turnAbout(base[3], k, angle) }
    frames[index] = frame
    local function world(p: vector): vector
      return right * p.x + up * p.y + look * p.z
    end
    Object_SetAxes(moving.objects[index], world(frame[3]), world(frame[2]))
  end
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

-- How many lights there are in a citadel's ring.
local RING_LAMPS = 96

-- How big a tower stands in its field: its radius, as a share of the
-- field's. (It stands large for its field, which is a small one.)
Starbase.TOWER = 0.28

-- The weapons a battery may carry, of each kind. Which one a given
-- battery has follows from the station's seed.
local GUNS = { "artillery.large", "railgun.large", "laser.beam.large", "blaster.large", "laser.pulse.large", "autocannon.large" }
-- (a people's tower's gun batteries carry its turret family's guns: Core/Tactical/Batteries)
local FAMILY_GUNS: { [string]: { string } } = {
  projectile = { "artillery.large", "autocannon.large" }, hybrid = { "railgun.large", "blaster.large" },
  laser = { "laser.pulse.large", "laser.beam.large" },
}
-- Metres to one of a weapon drawing's units, on a battery.
local BATTERY = 26

-- One thing of a station to draw: where its middle is from the middle
-- of the station (metres), which way it faces, and how many metres one
-- of its model's units is. 'arm' is the weapon type standing on a
-- battery, and 'unit' then how many metres one of that weapon's is.
-- ('up' is which way the model's own top goes, if not up.)
export type Part = { id: string, model: Model, at: vector, look: vector, up: vector?, scale: number, radius: number, arm: string?,
  unit: number?, movers: { Mover }?,
  -- (of a tower built in sections: how far from its upright it reaches, rings and arms and all)
  wide: number? }

-- (A citadel's: 'ring', the radius of the ring of lights that marks how
-- far its tether reaches, with no field; and 'arms', the weapons on its
-- mounts, each where it stands, which way its face is and which way is
-- ahead, and how big a metre of the weapon is.)
-- ('twin': the second of a pair of mounts, which are one hardpoint: it
-- carries what the first does, and it is the first that fires.)
export type Arm = { type: string, at: vector, n: vector, fore: vector, unit: number, twin: boolean?, pds: boolean? }
export type Layout = { tower: Part, modules: { Part }, field: number, ring: number?, arms: { Arm }?,
  -- (a citadel's observatory or mining turret, fitted: what it is, and where it stands from the station's middle, m)
  special: { kind: string, at: vector }? }

local function dice(n: number): number
  return (math.sin(n * 12.9898) * 43758.5453) % 1
end

-- A station laid out: 'variety' and 'radius' are the station's own
-- (Describe/System), and 'seed' its seed. The field is the station's
-- radius; the tower stands in the middle of it; its modules stand round
-- it inside the field, the big ones nearer, on several levels and clear
-- of each other; its batteries stand outside it, high and low.
--
-- 'given' is what the station is made of, if the game has said
-- (Core.Query.Station): its tower then says whose it is. Without it,
-- it is what a station of that kind and size would be that is nobody's
-- starting place. 'dark' is a tower with no fuel: it has no field.
--
-- Its batteries stand outside the field (Core/Tactical/Fields: nothing
-- fires across it), where the game says (Structures.Post). In the game
-- they are things in space as ships are, there to be shot at, and are
-- drawn as those (Core/Tactical/Batteries): 'bare' leaves them out of
-- what is laid out here, and 'down' are those of them that have been
-- destroyed and not built again, by their place in the station's order.
function Starbase.Layout(variety: string, radius: number, seed: number, faction: string?, given: Structures.Makeup?,
  dark: boolean?, bare: boolean?, down: { number }?): Layout
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
  -- (a citadel is as big as it is, the owner's sizes: its field is wider)
  local towerRadius = if type.citadel and type.reach then type.reach else radius * Starbase.TOWER
  local guns = FAMILY_GUNS[type.gun] or GUNS
  local tower: Part
  if type.citadel then
    -- A citadel (Game/View/Citadel): grown, upright, its middle where
    -- the station is; what is fitted in it is inside it.
    -- (a generator station's sphere is there while its generator is:
    -- black for gravity, purple for a wormhole)
    -- (an alien people's citadel is theirs, whoever holds it: Data/Structures' CITADEL_ALIEN)
    -- (and a research station's observatory, or a refinery's mining turret, is there while its module is fitted:
    -- working, or dark with the citadel)
    local fitted = false
    for _, id in makeup.modules do
      local module = Structures.moduleById[id]
      local works = module and module.works
      fitted = fitted or (works == "observatory" and type.kind == "research") or (works ~= nil and works ~= "observatory"
        and type.kind == "refinery")
    end
    local special = if type.kind ~= "research" and type.kind ~= "refinery" then nil elseif not fitted then "absent"
      elseif dark then "off" else "on"
    local made = Citadel.Of(type.kind, type.size, faction or (if type.faction ~= "" then type.faction else nil),
      if dark then nil else Structures.Generating(makeup.modules), special)
    -- (centred on its middle; but one with a sphere at its heart, on that:
    -- the way through a jump bridge or a wormhole station goes to the
    -- station's own place, Core/Tactical/Space)
    local centred = if made.hole > 0 then vector.create(0, 0, 0) else -(made.lower + made.upper) * 0.5 * (towerRadius / made.radius)
    tower = { id = type.id, model = made.model, at = centred,
      look = vector.create(0, 0, 1), scale = towerRadius / made.radius, radius = towerRadius, movers = made.movers }
    -- (no field, the owner's 2026-11-19: a ring of lights at the tether's reach; and on its mounts the weapons its
    -- defence module mounts, of its family, and its point defence, which every citadel has)
    local family: string? = nil
    for _, id in makeup.modules do
      local defence = Structures.moduleById[id] and Structures.moduleById[id].defence
      if defence then
        family = if defence == "projectile" then "cannon" else defence
      end
    end
    local arms: { Arm } = {}
    local scale = towerRadius / made.radius
    for index, armed in Citadel.Armed(made.mounts, type.size, family) do
      local mount = made.mounts[index]
      if armed ~= "" and mount then
        table.insert(arms, { type = armed, at = tower.at + mount.at * scale, n = mount.n, fore = mount.fore, unit = scale / made.metres,
          twin = mount.twin ~= 0 and mount.twin < index, pds = mount.kind == "pds" })
      end
    end
    local layout: Layout = { tower = tower, modules = {}, field = 0, ring = if dark then nil else radius, arms = arms }
    if special == "on" then
      for _, mount in made.mounts do
        if mount.kind == "observatory" or mount.kind == "miner" then
          local kind: string = mount.kind
          layout.special = { kind = kind, at = tower.at + (mount.at + mount.n * mount.radius) * scale }
        end
      end
    end
    return layout
  else
    tower = Starbase.TowerPart(owner, type.size, vector.create(0, 0, 0), towerRadius)
  end
  tower.id = type.id
  local layout: Layout = { tower = tower, modules = {}, field = if dark then 0 else radius }
  -- (how far from the tower's upright the modules keep: clear of a
  -- narrow tower as they were, and of the rings and arms of a broad one)
  local clearOf = math.max(towerRadius * 0.55, (tower.wide or 0) * 1.04)

  -- Where each would like to be: round the tower by turns of the golden
  -- angle, on three levels, batteries farthest out.
  local start = dice(seed) * 2 * math.pi
  local arrays, batteries = 0, 0
  local posts: { Part } = {}
  for _, id in makeup.modules do
    local module = Structures.moduleById[id]
    -- (a citadel's services are fitted inside it: nothing stands round it but its batteries)
    if module.citadel then
      continue
    end
    local model = Starbase.Module(id)
    local battery = module.service == "defence"
    local angle, out, height
    if battery then
      batteries += 1
      if bare or (down and table.find(down, batteries)) then
        continue
      end
      -- (outside the field, where the game stands it)
      local x, y, z = Structures.Post(radius, seed, batteries)
      local post = vector.create(x, y, z)
      local away = vector.normalize(vector.create(x, 0, z))
      table.insert(posts, {
        id = id, model = model.model, at = post, look = away, scale = module.radius / model.radius, radius = module.radius,
        arm = if id == "battery.missile" then "launcher.cruise" else guns[math.floor(dice(seed + batteries * 3.7) * #guns) + 1],
        unit = BATTERY,
      })
      continue
    else
      arrays += 1
      angle = start + arrays * 2.399963
      out = clearOf + module.radius + radius * (0.10 + 0.07 * (arrays % 3))
      height = radius * ({ 0.05, -0.24, 0.30 })[arrays % 3 + 1]
    end
    local flat = vector.create(math.cos(angle), 0, math.sin(angle))
    local part: Part = {
      id = id, model = model.model, at = flat * math.min(out, radius * 0.9 - module.radius) + vector.create(0, height, 0),
      -- (a shipyard lies along the way round; everything else faces out)
      look = if id == "array.assembly" then vector.create(-flat.z, 0, flat.x) else flat,
      scale = module.radius / model.radius, radius = module.radius,
    }
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
      local clear = clearOf * 1.09 + a.radius
      if off < clear and math.abs(a.at.y) < towerRadius + a.radius then
        a.at += (if off > 1e-3 then flat / off else vector.create(1, 0, 0)) * (clear - off)
      end
      local far = vector.magnitude(a.at)
      if far + a.radius > radius * 0.94 then
        a.at *= (radius * 0.94 - a.radius) / far
      end
    end
  end
  -- (the batteries are where they are: outside all that)
  for _, post in posts do
    table.insert(layout.modules, post)
  end
  return layout
end

local UP = vector.create(0, 1, 0)

-- A piece of a tower that moves, in a scene: the thing it is there, how
-- it moves, how big it is drawn, and the tower's own axes there (which
-- way its drawing's z, y and x go in the scene).
export type Moving = { object: Object, motion: Tower.Motion, size: number, look: vector, up: vector, right: vector, lit: boolean?,
  -- (a citadel's telescope or mining gun: the way, in the scene, it is to turn to, and how far round it is)
  aim: vector?, angle: number?,
  -- (and how far it is tilted from as built, and where its muzzle is in the scene now)
  pitch: number?, tip: vector?,
  -- (a hinged piece's place at rest, which it goes round from)
  base: vector? }

-- Put what moves of a tower into a scene: for a tower whose middle is
-- at 'at', drawn 'size' to one of its own units, facing 'look' with
-- 'up' above it. 'add' makes a thing of a model, in the scene. What is
-- given back is for Starbase.Animate, every frame.
function Starbase.Movers(movers: { Mover }?, add: (model: Model) -> Object, at: vector, look: vector, up: vector, size: number): { Moving }
  local moving: { Moving } = {}
  local l = vector.normalize(look)
  local u = vector.normalize(up - l * vector.dot(up, l))
  local right = vector.cross(u, l)
  if movers then
    for _, mover in movers do
      local object = add(mover.model)
      object:SetScale(vector.create(size, size, size))
      object:SetPos(at + (right * mover.pivot.x + u * mover.pivot.y + l * mover.pivot.z) * size)
      Object_SetAxes(object, l, u)
      table.insert(moving, { object = object, motion = mover.motion, size = size, look = l, up = u, right = right })
    end
  end
  return moving
end

-- Move what moves of a tower: 'time' is in seconds, and 'sun' the way
-- to the sun from where the tower is.
--   spin    it turns about the tower's upright
--   scan    what it looks along goes slowly round, a little off the way it looks
--   track   it turns about its own arm to put its face to the sun
--   blink   it is lit for a share of its period, and for the rest is not there
--   turn    it turns about an axis of its own through its pivot (a
--           wormhole citadel's rings: Game/View/Citadel)
function Starbase.Animate(moving: { Moving }, time: number, sun: vector)
  for _, piece in moving do
    local motion = piece.motion
    local function world(p: vector): vector
      return piece.right * p.x + piece.up * p.y + piece.look * p.z
    end
    if motion.kind == "spin" then
      local angle = time * (motion.rate or 0)
      Object_SetAxes(piece.object, piece.look, world(vector.create(-math.sin(angle), math.cos(angle), 0)))
    elseif motion.kind == "scan" then
      local toward = motion.toward or vector.create(0, 0, 1)
      local aside = if math.abs(toward.z) > 0.9 then vector.create(1, 0, 0) else vector.create(0, 0, 1)
      local one = vector.normalize(vector.cross(toward, aside))
      local other = vector.cross(toward, one)
      local round = (time / (motion.period or 60) + (motion.phase or 0)) * 2 * math.pi
      local cone = motion.cone or 0.3
      local looks = toward * math.cos(cone) + (one * math.cos(round) + other * math.sin(round)) * math.sin(cone)
      Object_SetAxes(piece.object, world(looks), world(one))
    elseif motion.kind == "track" then
      -- (its own x is along its arm, and its face is its own y)
      local arm = world(motion.arm or vector.create(1, 0, 0))
      local face = sun - arm * vector.dot(sun, arm)
      if vector.magnitude(face) > 0.05 then
        face = vector.normalize(face)
        Object_SetAxes(piece.object, vector.cross(arm, face), face)
      end
    elseif motion.kind == "turn" then
      -- (its own z and y, turned so far about the axis: Rodrigues' rule)
      local k = vector.normalize(motion.axis or vector.create(0, 1, 0))
      local angle = time * (motion.rate or 0) + (motion.phase or 0) * 2 * math.pi
      local aim, fore = piece.aim, motion.fore
      local tilt = piece.pitch or 0
      if aim and fore and motion.rate ~= 0 then
        -- (turned to what it works at, about its foot, and its barrel raised or lowered to it: eased there, a
        -- radian a second at most)
        local wanted = vector.normalize(vector.create(vector.dot(aim, piece.right), vector.dot(aim, piece.up), vector.dot(aim, piece.look)))
        local p = wanted - k * vector.dot(wanted, k)
        local f = fore - k * vector.dot(fore, k)
        if vector.magnitude(p) > 1e-4 and vector.magnitude(f) > 1e-4 then
          local target = math.atan2(vector.dot(k, vector.cross(f, p)), vector.dot(f, p))
          local now = piece.angle or angle
          local step = (target - now + math.pi) % (2 * math.pi) - math.pi
          local most = 1 / 60
          now += math.clamp(step, -most, most)
          piece.angle = now
          angle = now
          -- (up off its foot: from a little below level to nearly straight up; only what is built to tilt)
          local lift = motion.lift
          if lift then
            local up = math.clamp(math.asin(math.clamp(vector.dot(wanted, k), -1, 1)), -0.15, 1.45)
            tilt += math.clamp(up - lift - tilt, -most, most)
            piece.pitch = tilt
          end
        end
      end
      local c, s = math.cos(angle), math.sin(angle)
      local function turned(p: vector): vector
        return p * c + vector.cross(k, p) * s + k * (vector.dot(k, p) * (1 - c))
      end
      -- (tilted first, about the way across its barrel, and then turned about its foot)
      local across = if fore then vector.cross(fore, k) else vector.create(1, 0, 0)
      across = if vector.magnitude(across) > 1e-4 then vector.normalize(across) else vector.create(1, 0, 0)
      local tc, ts = math.cos(tilt), math.sin(tilt)
      local function posed(p: vector): vector
        local q = if tilt ~= 0 then p * tc + vector.cross(across, p) * ts + across * (vector.dot(across, p) * (1 - tc)) else p
        return turned(q)
      end
      Object_SetAxes(piece.object, world(posed(vector.create(0, 0, 1))), world(posed(vector.create(0, 1, 0))))
      local hinge = motion.hinge
      if hinge then
        -- (round the upright, as what it is hinged on goes round)
        local base = piece.base or piece.object:GetPos()
        piece.base = base
        piece.object:SetPos(base + world(turned(hinge) - hinge) * piece.size)
      end
      local muzzle = motion.muzzle
      if muzzle then
        piece.tip = piece.object:GetPos() + world(posed(muzzle)) * piece.size
      end
    elseif motion.kind == "blink" then
      local lit = (time / (motion.period or 1.2) + (motion.phase or 0)) % 1 < (motion.lit or 0.5)
      if lit ~= piece.lit then
        piece.lit = lit
        local size = if lit then piece.size else piece.size * 0.001
        piece.object:SetScale(vector.create(size, size, size))
      end
    end
  end
end

-- Put a laid-out station into a scene: its tower, its modules, what
-- stands on its batteries, and its field (if it has one), as scenery in
-- 'container' with the station's middle at 'origin'. 'metres' is how
-- long a metre is there. Returns the objects, the tower first.
function Starbase.Raise(layout: Layout, container: Object, origin: vector, metres: number): ({ Object }, { Moving })
  local objects: { Object } = {}
  local moving: { Moving } = {}
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
    -- (and what moves of it, each a thing of its own: Starbase.Animate moves them)
    for _, piece in Starbase.Movers(part.movers, scenery, origin + part.at * metres, part.look, part.up or UP, size) do
      table.insert(moving, piece)
    end
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
  -- (a citadel's weapons on its mounts, at rest)
  for _, each in layout.arms or {} :: { Arm } do
    local arm = Arms.Build(each.type)
    if arm then
      local base: Object? = if arm.base then scenery(arm.base) else nil
      local gun = scenery(arm.gun)
      Arms.Place(arm, base, gun, origin + each.at * metres, each.n, each.fore, nil, each.unit * metres)
    end
  end
  -- (and its ring of lights, two lots of them lit turn about, where its tether reaches)
  local ring = layout.ring
  if ring and ring > 0 then
    local lamp = finish("ring.lamp", function(b: Builder)
      block(b, GLOW, v(0, 0, 0), v(1, 1, 1), nil, 0.7)
    end, Hull.looks.vessari, 1, 0.04).model
    local size = math.max(ring * 0.005, 50) * metres
    for n = 1, RING_LAMPS do
      local angle = (n - 1) / RING_LAMPS * 2 * math.pi
      local object = scenery(lamp)
      object:SetScale(vector.create(size, size, size))
      object:SetPos(origin + vector.create(math.cos(angle), 0, math.sin(angle)) * (ring * metres))
      table.insert(moving, { object = object, motion = { kind = "blink", period = 1.6, phase = (n % 2) / 2, lit = 0.5 }, size = size,
        look = vector.create(0, 0, 1), up = UP, right = vector.create(1, 0, 0) })
    end
  end
  return objects, moving
end

return Starbase
