--!strict
-- How a station looks: a control tower, the modules anchored round it,
-- and the field that holds them (Core/Data/Structures says what a
-- station is made of; this draws it).
--
-- A tower is its faction's, in three sizes, and each size is its own
-- drawing, not one drawing made bigger. The Vessari's are the first:
-- derricks of open girders with a plated core, fuel drums strapped
-- round the foot, a control house near the top with its lights on, and
-- above it the crown of prongs that throws the field. They are built
-- from the same plates and painted with the same paint as Vessari hulls
-- (Game/View/Hull).
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
local function mast(b: Builder, foot: vector, height: number, lean: number)
  local top = foot + v(lean, height, lean * 0.6)
  beam(b, FRAME, foot, top, height * 0.03, 0.1)
  for index, share in { 0.45, 0.70, 0.90 } do
    local at = foot + (top - foot) * share
    local reach = height * (0.24 - 0.055 * index)
    beam(b, FRAME, at + v(-reach, 0, 0), at + v(reach, 0, 0), height * 0.016, 0.1)
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

-- One stage of a derrick: four corner posts from 'low' to 'high', 'half'
-- apart from the middle, braced across each side bay by bay, with a
-- plated core up 'plated' of its height.
local function stage(b: Builder, low: number, high: number, half: number, plated: number)
  local post = half * 0.075
  for _, x in { -half, half } do
    for _, z in { -half, half } do
      beam(b, FRAME, v(x, low, z), v(x, high, z), post, 0.1)
    end
  end
  local bays = math.max(2, math.floor((high - low) / (half * 1.5) + 0.5))
  for bay = 0, bays do
    local y = low + (high - low) * bay / bays
    for _, side in { -half, half } do
      beam(b, FRAME, v(-half, y, side), v(half, y, side), post * 0.7)
      beam(b, FRAME, v(side, y, -half), v(side, y, half), post * 0.7)
    end
    if bay < bays then
      local next = low + (high - low) * (bay + 1) / bays
      local lean = if bay % 2 == 0 then 1 else -1
      for _, side in { -half, half } do
        beam(b, FRAME, v(-half * lean, y, side), v(half * lean, next, side), post * 0.55)
        beam(b, FRAME, v(side, y, half * lean), v(side, next, -half * lean), post * 0.55)
      end
    end
  end
  local core = (high - low) * plated
  block(b, PLATING, v(0, low + core / 2, 0), v(half * 0.66, core / 2, half * 0.66), nil, 0.05)
end

-- The crown that throws the field: a ring, prongs leaning in over it,
-- and the lit core they hold.
local function crown(b: Builder, at: vector, half: number, prongs: number)
  block(b, FRAME, at, v(half, half * 0.07, half), nil, 0.3)
  block(b, TRIM, at + v(0, half * 0.09, 0), v(half * 0.8, half * 0.03, half * 0.8), nil, 0.3)
  for index = 1, prongs do
    local angle = (index - 0.5) / prongs * 2 * math.pi
    local out = v(math.cos(angle), 0, math.sin(angle))
    beam(b, PLATING, at + out * (half * 0.92), at + out * (half * 0.42) + v(0, half * 1.25, 0), half * 0.085, 0.2)
    beam(b, FRAME, at + out * (half * 0.55), at + out * (half * 0.80) + v(0, half * 0.55, 0), half * 0.04)
  end
  block(b, GLOW, at + v(0, half * 0.62, 0), v(half * 0.24, half * 0.34, half * 0.24), v(math.pi / 4, 0, 0), 0.45)
  block(b, FRAME, at + v(0, half * 0.20, 0), v(half * 0.30, half * 0.12, half * 0.30), nil, 0.2)
end

-- The Vessari's slanted plates: a pair, leaning together like a roof.
local function roof(b: Builder, at: vector, half: vector)
  block(b, PLATING, at + v(-half.x * 0.5, 0, 0), v(half.x * 0.56, half.y, half.z), v(0, 0, 0.45), 0.08)
  block(b, PATCH, at + v(half.x * 0.5, 0, 0), v(half.x * 0.56, half.y, half.z), v(0, 0, -0.45), 0.08)
end

-- ---------------------------------------------------------------------
-- The Vessari towers

-- Small: one derrick, a house on top of it, the crown on that.
local function vessariSmall(b: Builder)
  stage(b, -1.00, 0.45, 0.20, 0.62)
  block(b, FRAME, v(0, -1.03, 0), v(0.36, 0.03, 0.36), nil, 0.2)
  block(b, PATCH, v(0.14, -0.30, 0.0), v(0.022, 0.26, 0.12))
  block(b, TRIM, v(0, -0.06, 0), v(0.138, 0.02, 0.138), nil, 0.1)
  drum(b, v(0.30, -0.80, 0.05), 0.10, 0.38)
  drum(b, v(-0.28, -0.84, -0.12), 0.08, 0.30, PLATING)
  drum(b, v(0.05, -0.86, -0.31), 0.07, 0.26)
  conduit(b, { v(0.30, -0.60, 0.05), v(0.22, -0.40, 0.05), v(0.21, 0.30, 0.05) }, 0.014)
  conduit(b, { v(-0.28, -0.68, -0.12), v(-0.21, -0.50, -0.12), v(-0.21, 0.10, -0.16) }, 0.012)
  -- the control house, set off to one side, under the family's roof
  block(b, FRAME, v(0, 0.47, 0), v(0.25, 0.02, 0.25), nil, 0.2)
  block(b, PATCH, v(0.06, 0.62, 0.02), v(0.24, 0.13, 0.20), nil, 0.12)
  windows(b, v(0.06, 0.64, 0.02), 0.205, 3, 0.022)
  roof(b, v(0.06, 0.80, 0.02), v(0.26, 0.014, 0.23))
  crown(b, v(0, 0.92, 0), 0.26, 4)
  mast(b, v(-0.16, 0.76, -0.14), 0.62, -0.03)
  -- a boom with its dish
  truss(b, v(0.20, 0.20, 0), v(0.62, 0.30, 0.04), 0.08, 3, v(0, 0, 1))
  block(b, PATCH, v(0.68, 0.34, 0.04), v(0.10, 0.012, 0.10), v(0, 0.5, 0.4), 0.3)
end

-- Medium: two stages with a deck between, and arms out to its banks.
local function vessariMedium(b: Builder)
  stage(b, -1.40, -0.20, 0.30, 0.70)
  stage(b, -0.20, 0.90, 0.20, 0.55)
  block(b, FRAME, v(0, -1.43, 0), v(0.48, 0.03, 0.48), nil, 0.2)
  block(b, PLATING, v(0, -0.20, 0), v(0.42, 0.022, 0.42), nil, 0.15)
  block(b, TRIM, v(0, -0.17, 0), v(0.43, 0.012, 0.43), nil, 0.15)
  block(b, PATCH, v(0.205, -0.80, 0.02), v(0.022, 0.34, 0.15))
  block(b, PATCH, v(-0.02, -1.05, -0.205), v(0.13, 0.20, 0.022))
  for index, at in { v(0.42, -1.18, 0.10), v(-0.40, -1.22, -0.14), v(0.08, -1.24, -0.44), v(-0.12, -1.20, 0.43), v(0.34, -1.26, -0.30) } do
    drum(b, at, 0.12 - 0.012 * index, 0.46 - 0.04 * index, if index % 2 == 0 then PLATING else PATCH)
  end
  conduit(b, { v(0.42, -0.94, 0.10), v(0.31, -0.70, 0.10), v(0.31, -0.24, 0.10) }, 0.016)
  conduit(b, { v(-0.40, -1.00, -0.14), v(-0.31, -0.80, -0.14), v(-0.31, -0.30, -0.20), v(-0.21, -0.10, -0.20), v(-0.21, 0.70, -0.20) }, 0.014)
  -- the arms: a long one with a big bank, a short one with a small
  truss(b, v(0.30, -0.56, 0), v(1.02, -0.46, 0.06), 0.12, 5, v(0, 0, 1))
  block(b, PLATING, v(1.14, -0.46, 0.06), v(0.14, 0.20, 0.17), nil, 0.12)
  block(b, TRIM, v(1.14, -0.30, 0.06), v(0.145, 0.02, 0.175), nil, 0.12)
  beam(b, FRAME, v(0.30, -0.20, 0), v(1.00, -0.40, 0.05), 0.014)
  truss(b, v(-0.30, -0.86, -0.04), v(-0.74, -0.92, -0.10), 0.10, 3, v(0, 0, 1))
  drum(b, v(-0.84, -0.92, -0.10), 0.10, 0.30)
  -- the houses, and the crown
  block(b, PATCH, v(-0.10, 0.10, 0.215), v(0.11, 0.09, 0.05), nil, 0.14)
  block(b, GLOW, v(-0.10, 0.11, 0.268), v(0.08, 0.02, 0.004), nil, 0.3)
  block(b, FRAME, v(0, 0.92, 0), v(0.28, 0.02, 0.28), nil, 0.2)
  block(b, PATCH, v(0.05, 1.08, 0.0), v(0.26, 0.14, 0.23), nil, 0.12)
  windows(b, v(0.05, 1.10, 0.0), 0.235, 4, 0.022)
  roof(b, v(0.05, 1.27, 0.0), v(0.29, 0.015, 0.26))
  crown(b, v(0, 1.40, 0), 0.30, 4)
  mast(b, v(-0.18, 1.22, -0.16), 0.85, -0.04)
  truss(b, v(0.20, 0.50, 0), v(0.66, 0.62, -0.06), 0.08, 3, v(0, 0, 1))
  block(b, PATCH, v(0.73, 0.67, -0.06), v(0.12, 0.012, 0.12), v(0, 0.5, 0.4), 0.3)
end

-- Large: three stages on four splayed legs, a walled deck with its drum
-- farm, a keep for a control house, and a crown of six.
local function vessariLarge(b: Builder)
  stage(b, -2.00, -0.80, 0.42, 0.75)
  stage(b, -0.80, 0.50, 0.30, 0.62)
  stage(b, 0.50, 1.50, 0.20, 0.50)
  -- the legs, each to a footing with a drum on it
  for index, corner in { v(1, 0, 1), v(-1, 0, 1), v(-1, 0, -1), v(1, 0, -1) } do
    local reach = 1.02 + 0.06 * (index % 2)
    local foot = v(corner.x * reach, -2.10, corner.z * reach)
    truss(b, v(corner.x * 0.42, -0.86, corner.z * 0.42), foot, 0.16, 6, v(corner.z, 0, -corner.x) * 0.7071)
    block(b, FRAME, foot + v(0, -0.04, 0), v(0.20, 0.035, 0.20), nil, 0.25)
    drum(b, foot + v(0, 0.16, 0), 0.13, 0.30, if index % 2 == 0 then PLATING else PATCH)
    beam(b, FRAME, v(corner.x * 0.42, -1.90, corner.z * 0.42), foot + v(0, 0.02, 0), 0.02)
  end
  block(b, FRAME, v(0, -2.03, 0), v(0.56, 0.03, 0.56), nil, 0.2)
  -- the walled deck where the first stage ends, and what stands on it
  block(b, PLATING, v(0, -0.80, 0), v(0.66, 0.026, 0.66), nil, 0.12)
  block(b, TRIM, v(0, -0.765, 0), v(0.665, 0.012, 0.665), nil, 0.12)
  for index = 1, 7 do
    local along = (index - 4) * 0.19
    if index % 3 ~= 0 then
      block(b, PLATING, v(along, -0.735, 0.64), v(0.07, 0.04, 0.02), nil, 0.15)
      block(b, PLATING, v(along, -0.735, -0.64), v(0.07, 0.04, 0.02), nil, 0.15)
      block(b, PLATING, v(0.64, -0.735, along), v(0.02, 0.04, 0.07), nil, 0.15)
      block(b, PLATING, v(-0.64, -0.735, along), v(0.02, 0.04, 0.07), nil, 0.15)
    end
  end
  for index, at in { v(0.50, -0.56, 0.20), v(0.48, -0.60, -0.22), v(-0.50, -0.58, 0.10), v(-0.46, -0.62, -0.34), v(0.10, -0.60, 0.50), v(-0.20, -0.62, -0.50) } do
    drum(b, at, 0.115 - 0.008 * index, 0.42 - 0.03 * index, if index % 2 == 0 then PLATING else PATCH)
  end
  block(b, PATCH, v(0.285, -1.40, 0.04), v(0.024, 0.46, 0.20))
  block(b, PATCH, v(-0.04, -1.62, -0.285), v(0.18, 0.26, 0.024))
  block(b, PLATING, v(-0.285, -1.20, -0.06), v(0.024, 0.30, 0.16))
  conduit(b, { v(0.50, -0.36, 0.20), v(0.40, -0.20, 0.20), v(0.31, 0.00, 0.14), v(0.31, 0.44, 0.14) }, 0.018)
  conduit(b, { v(-0.50, -0.38, 0.10), v(-0.31, -0.20, 0.10), v(-0.31, 0.30, 0.04), v(-0.21, 0.56, 0.04), v(-0.21, 1.40, 0.04) }, 0.016)
  -- arms at three heights, none alike
  truss(b, v(0.30, -0.10, 0), v(1.20, 0.04, 0.08), 0.14, 6, v(0, 0, 1))
  block(b, PLATING, v(1.36, 0.04, 0.08), v(0.17, 0.24, 0.20), nil, 0.12)
  block(b, TRIM, v(1.36, 0.23, 0.08), v(0.175, 0.022, 0.205), nil, 0.12)
  beam(b, FRAME, v(0.30, 0.44, 0), v(1.18, 0.10, 0.07), 0.016)
  truss(b, v(-0.30, 0.20, -0.04), v(-0.96, 0.12, -0.14), 0.12, 4, v(0, 0, 1))
  drum(b, v(-1.08, 0.12, -0.14), 0.12, 0.36)
  truss(b, v(0, 0.86, -0.20), v(-0.06, 0.94, -0.80), 0.09, 3, v(1, 0, 0))
  block(b, PATCH, v(-0.06, 0.99, -0.90), v(0.15, 0.012, 0.15), v(0.4, 0.5, 0), 0.3)
  -- the keep: the control house in three steps, under the roof
  block(b, FRAME, v(0, 1.52, 0), v(0.30, 0.02, 0.30), nil, 0.2)
  block(b, PLATING, v(0.04, 1.70, 0.0), v(0.28, 0.16, 0.25), nil, 0.10)
  windows(b, v(0.04, 1.72, 0.0), 0.255, 4, 0.022)
  block(b, PATCH, v(0.06, 1.96, 0.02), v(0.22, 0.11, 0.20), nil, 0.10)
  windows(b, v(0.06, 1.97, 0.02), 0.205, 3, 0.020)
  block(b, TRIM, v(0.04, 1.855, 0.0), v(0.285, 0.014, 0.255), nil, 0.1)
  roof(b, v(0.06, 2.10, 0.02), v(0.25, 0.015, 0.23))
  crown(b, v(0, 2.24, 0), 0.36, 6)
  mast(b, v(-0.20, 2.06, -0.16), 1.10, -0.05)
  mast(b, v(0.22, 2.06, 0.14), 0.66, 0.03)
end

-- ---------------------------------------------------------------------
-- The modules, which are everybody's. Each is drawn about its own
-- middle, about one unit from there to its farthest part, its front
-- toward +z.

local MODULES: { [string]: (b: Builder) -> () } = {
  -- A trade hub: a drum of offices with four arms out to mooring pads,
  -- and signs lit along the arms.
  ["array.trade"] = function(b)
    drum(b, v(0, 0, 0), 0.30, 0.50, PLATING)
    block(b, PATCH, v(0, 0.30, 0), v(0.22, 0.06, 0.22), nil, 0.4)
    windows(b, v(0, 0.05, 0), 0.292, 4, 0.02)
    windows(b, v(0, -0.10, 0), 0.292, 4, 0.02)
    for index, out in { v(1, 0, 0), v(-1, 0, 0), v(0, 0, 1), v(0, 0, -1) } do
      local reach = 0.80 + 0.10 * (index % 2)
      truss(b, out * 0.28, out * reach, 0.10, 4, v(0, 1, 0))
      block(b, PLATING, out * (reach + 0.07) + v(0, -0.02, 0), v(0.13, 0.025, 0.13), nil, 0.2)
      block(b, TRIM, out * (reach + 0.07) + v(0, 0.01, 0), v(0.10, 0.008, 0.10), nil, 0.2)
      block(b, GLOW, out * (reach * 0.6) + v(0, 0.075, 0), v(0.012 + 0.10 * math.abs(out.x), 0.012, 0.012 + 0.10 * math.abs(out.z)), nil, 0.3)
    end
    mast(b, v(0.05, 0.36, 0.04), 0.5, 0.02)
  end,
  -- A ship maintenance array: a hangar open at the front, lit inside.
  ["array.hangar"] = function(b)
    block(b, PLATING, v(0, -0.30, -0.05), v(0.50, 0.03, 0.80), nil, 0.1)
    block(b, PLATING, v(0.50, 0.0, -0.10), v(0.03, 0.30, 0.74), nil, 0.1)
    block(b, PLATING, v(-0.50, 0.0, -0.10), v(0.03, 0.30, 0.74), nil, 0.1)
    block(b, PATCH, v(0, 0.30, -0.14), v(0.53, 0.03, 0.72), nil, 0.1)
    block(b, PLATING, v(0, 0.0, -0.84), v(0.50, 0.30, 0.03), nil, 0.1)
    block(b, GLOW, v(0, 0.0, -0.80), v(0.40, 0.20, 0.006), nil, 0.2)
    block(b, TRIM, v(0.50, 0.0, 0.66), v(0.036, 0.31, 0.03), nil, 0.2)
    block(b, TRIM, v(-0.50, 0.0, 0.66), v(0.036, 0.31, 0.03), nil, 0.2)
    block(b, TRIM, v(0, 0.30, 0.60), v(0.53, 0.034, 0.03), nil, 0.2)
    for _, x in { -0.3, 0.3 } do
      beam(b, FRAME, v(x, 0.24, -0.76), v(x, 0.24, 0.72), 0.02)
    end
    block(b, FRAME, v(0.1, 0.20, 0.20), v(0.42, 0.025, 0.04))
    drum(b, v(0.66, -0.10, -0.40), 0.10, 0.36)
    block(b, PATCH, v(-0.62, 0.10, -0.50), v(0.09, 0.10, 0.14), nil, 0.14)
    block(b, GLOW, v(-0.712, 0.12, -0.50), v(0.004, 0.02, 0.10), nil, 0.3)
  end,
  -- A refining array: furnace stacks of unequal height, piped together,
  -- over a hopper.
  ["array.refining"] = function(b)
    block(b, FRAME, v(0, -0.62, 0), v(0.52, 0.03, 0.46), nil, 0.2)
    for index, at in { v(-0.28, 0, -0.10), v(0.10, 0, 0.12), v(0.36, 0, -0.18) } do
      local height = 1.30 - 0.26 * index
      block(b, if index == 2 then PATCH else PLATING, v(at.x, -0.60 + height / 2, at.z), v(0.13, height / 2, 0.13), nil, 0.3)
      block(b, FRAME, v(at.x, -0.60 + height, at.z), v(0.15, 0.03, 0.15), nil, 0.3)
      block(b, GLOW, v(at.x, -0.60 + height + 0.035, at.z), v(0.09, 0.008, 0.09), nil, 0.4)
      block(b, TRIM, v(at.x, -0.60 + height * 0.7, at.z), v(0.134, 0.02, 0.134), nil, 0.3)
    end
    block(b, PLATING, v(-0.05, -0.36, 0.34), v(0.26, 0.20, 0.12), v(0, 0.25, 0), 0.1)
    conduit(b, { v(-0.28, 0.20, -0.10), v(-0.10, 0.34, 0.0), v(0.10, 0.20, 0.12) }, 0.03)
    conduit(b, { v(0.10, -0.10, 0.12), v(0.24, 0.02, -0.02), v(0.36, -0.10, -0.18) }, 0.03)
    conduit(b, { v(-0.28, -0.30, -0.10), v(-0.48, -0.30, -0.10), v(-0.48, -0.56, -0.10) }, 0.025)
    truss(b, v(-0.50, -0.20, 0.30), v(0.50, -0.20, 0.30), 0.08, 5, v(0, 0, 1))
  end,
  -- A ship assembly array: a cradle of ribs over two rails, a crane
  -- across it, and a hull half built inside.
  ["array.assembly"] = function(b)
    for _, x in { -0.26, 0.26 } do
      truss(b, v(x, -0.22, -0.92), v(x, -0.22, 0.92), 0.08, 12)
    end
    for index = 0, 5 do
      local z = -0.88 + index * 0.352
      beam(b, FRAME, v(-0.30, -0.24, z), v(-0.34, 0.24, z), 0.018)
      beam(b, FRAME, v(0.30, -0.24, z), v(0.34, 0.24, z), 0.018)
      beam(b, FRAME, v(-0.34, 0.24, z), v(0.34, 0.24, z), 0.018)
      block(b, GLOW, v(0, 0.215, z), v(0.05, 0.006, 0.012), nil, 0.3)
    end
    for _, x in { -0.34, 0.34 } do
      beam(b, FRAME, v(x, 0.24, -0.88), v(x, 0.24, 0.88), 0.016)
    end
    -- the crane, and its cab
    block(b, TRIM, v(0, 0.29, 0.30), v(0.38, 0.03, 0.04), nil, 0.2)
    block(b, FRAME, v(0.12, 0.20, 0.30), v(0.04, 0.07, 0.04))
    block(b, PATCH, v(0.44, 0.10, -0.80), v(0.08, 0.09, 0.10), nil, 0.14)
    block(b, GLOW, v(0.358, 0.11, -0.80), v(0.004, 0.02, 0.07), nil, 0.3)
    -- the hull on the slip: a keel, and plating as far as it has got
    beam(b, FRAME, v(0, -0.06, -0.70), v(0, -0.06, 0.62), 0.03)
    block(b, PLATING, v(0, -0.04, -0.40), v(0.15, 0.12, 0.26), nil, 0.1)
    block(b, PATCH, v(-0.01, -0.02, 0.02), v(0.13, 0.10, 0.14), nil, 0.1)
    for index = 0, 3 do
      beam(b, FRAME, v(-0.12, -0.14, 0.24 + index * 0.11), v(0.12, -0.14, 0.24 + index * 0.11), 0.012)
      beam(b, FRAME, v(-0.12, -0.14, 0.24 + index * 0.11), v(-0.12, 0.04, 0.24 + index * 0.11), 0.012)
      beam(b, FRAME, v(0.12, -0.14, 0.24 + index * 0.11), v(0.12, 0.04, 0.24 + index * 0.11), 0.012)
    end
  end,
  -- A laboratory: domes on a deck, a dish, and aerials.
  ["array.laboratory"] = function(b)
    block(b, PLATING, v(0, -0.30, 0), v(0.62, 0.04, 0.50), nil, 0.2)
    block(b, PATCH, v(-0.24, -0.06, 0.06), v(0.26, 0.24, 0.26), nil, 0.7)
    block(b, PLATING, v(0.28, -0.14, -0.14), v(0.18, 0.16, 0.18), nil, 0.7)
    block(b, GLOW, v(-0.24, -0.06, 0.322), v(0.12, 0.02, 0.004), nil, 0.3)
    block(b, GLOW, v(0.28, -0.14, 0.042), v(0.08, 0.016, 0.004), nil, 0.3)
    block(b, FRAME, v(0.30, -0.18, 0.28), v(0.14, 0.10, 0.10))
    beam(b, FRAME, v(0.44, -0.26, -0.36), v(0.56, 0.36, -0.44), 0.02)
    block(b, PATCH, v(0.58, 0.44, -0.46), v(0.20, 0.014, 0.20), v(0.3, 0.6, 0), 0.4)
    mast(b, v(-0.50, -0.26, -0.36), 0.90, 0.02)
    mast(b, v(-0.06, -0.26, -0.40), 0.55, -0.02)
    block(b, TRIM, v(0, -0.25, 0.50), v(0.62, 0.012, 0.012), nil, 0.2)
  end,
  -- A storage array: drums in a cage of girders, and a stack of boxes.
  ["array.storage"] = function(b)
    for _, x in { -0.56, 0.20 } do
      for _, z in { -0.46, 0.46 } do
        beam(b, FRAME, v(x, -0.50, z), v(x, 0.50, z), 0.03, 0.1)
      end
    end
    for _, y in { -0.50, 0.50 } do
      for _, z in { -0.46, 0.46 } do
        beam(b, FRAME, v(-0.56, y, z), v(0.20, y, z), 0.026)
      end
      for _, x in { -0.56, 0.20 } do
        beam(b, FRAME, v(x, y, -0.46), v(x, y, 0.46), 0.026)
      end
    end
    for index, at in { v(-0.37, 0, -0.26), v(-0.37, 0, 0.26), v(0.01, 0, -0.26), v(0.01, 0, 0.26) } do
      drum(b, at, 0.17, 0.92, if index == 3 then PLATING else PATCH)
    end
    beam(b, FRAME, v(-0.56, -0.50, -0.46), v(0.20, 0.50, -0.46), 0.016)
    beam(b, FRAME, v(-0.56, 0.50, 0.46), v(0.20, -0.50, 0.46), 0.016)
    block(b, PLATING, v(0.50, -0.30, -0.16), v(0.18, 0.20, 0.26), nil, 0.06)
    block(b, TRIM, v(0.52, 0.06, -0.20), v(0.15, 0.16, 0.22), nil, 0.06)
    block(b, PLATING, v(0.50, -0.34, 0.34), v(0.16, 0.16, 0.16), nil, 0.06)
    block(b, GLOW, v(0.684, -0.30, -0.16), v(0.004, 0.02, 0.10), nil, 0.3)
  end,
  -- A habitat: three wide decks on a spine, their ports lit, a dome over.
  ["array.habitat"] = function(b)
    beam(b, FRAME, v(0, -0.80, 0), v(0, 0.70, 0), 0.07, 0.1)
    for index, y in { -0.46, -0.04, 0.38 } do
      local half = 0.56 - 0.07 * index
      block(b, if index == 2 then PATCH else PLATING, v(0, y, 0), v(half, 0.13, half), nil, 0.5)
      windows(b, v(0, y + 0.02, 0), half * 0.985, 5, 0.018)
      block(b, TRIM, v(0, y - 0.11, 0), v(half * 0.9, 0.012, half * 0.9), nil, 0.5)
    end
    block(b, PATCH, v(0, 0.62, 0), v(0.20, 0.12, 0.20), nil, 0.8)
    mast(b, v(0.04, 0.72, 0.02), 0.40, 0.02)
    drum(b, v(0.30, -0.76, 0.10), 0.09, 0.26)
    drum(b, v(-0.26, -0.78, -0.14), 0.08, 0.22, PLATING)
  end,
  -- A battery's stand: a deck on struts, with the ring for its gun or
  -- rack (which is one of the ship's weapons, at the size of a structure).
  ["battery"] = function(b)
    block(b, PLATING, v(0, -0.06, 0), v(0.62, 0.05, 0.62), nil, 0.3)
    block(b, PLATING, v(0, -0.06, 0), v(0.62, 0.05, 0.62), v(math.pi / 4, 0, 0), 0.3)
    block(b, TRIM, v(0, -0.004, 0), v(0.50, 0.01, 0.50), v(math.pi / 4, 0, 0), 0.3)
    block(b, FRAME, v(0, 0.01, 0), v(0.36, 0.03, 0.36), nil, 0.45)
    for index = 1, 4 do
      local angle = (index - 0.5) / 4 * 2 * math.pi
      local out = v(math.cos(angle), 0, math.sin(angle))
      beam(b, FRAME, out * 0.50 + v(0, -0.08, 0), out * 0.80 + v(0, -0.62, 0), 0.035)
      block(b, FRAME, out * 0.82 + v(0, -0.66, 0), v(0.08, 0.03, 0.08), nil, 0.3)
    end
    block(b, PATCH, v(0.42, 0.08, -0.42), v(0.10, 0.10, 0.10), nil, 0.14)
    block(b, GLOW, v(0.42, 0.10, -0.316), v(0.06, 0.02, 0.004), nil, 0.3)
    drum(b, v(-0.44, 0.10, 0.40), 0.07, 0.24)
  end,
}

-- ---------------------------------------------------------------------

-- A model and half the longest way across it, in its own units.
export type Made = { model: Model, radius: number }

local TOWERS: { [string]: { (b: Builder) -> () } } = {
  vessari = { vessariSmall, vessariMedium, vessariLarge },
}

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
  return finish(`tower.{owner}.{size}`, designs[size], Hull.looks[owner], 4.5 + 2.5 * size, 0.11)
end

-- The model of a module (Core/Data/Structures' ids). A battery of
-- either kind is its stand: what stands on it is Starbase.Layout's to say.
function Starbase.Module(id: string): Made
  local key = if string.sub(id, 1, 8) == "battery." then "battery" else id
  local draw = MODULES[key]
  assert(draw, `no drawing of a '{id}'`)
  return finish(key, draw, WORKS, 4.0, 0.11)
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
export type Part = { id: string, model: Model, at: vector, look: vector, scale: number, radius: number, arm: string?, unit: number? }

export type Layout = { tower: Part, modules: { Part }, field: number }

local function dice(n: number): number
  return (math.sin(n * 12.9898) * 43758.5453) % 1
end

-- A station laid out: 'variety' and 'radius' are the station's own
-- (Describe/System), and 'seed' its seed. The field is the station's
-- radius; the tower stands in the middle of it; its modules stand round
-- it inside the field, the big ones nearer, on several levels and clear
-- of each other; its batteries stand near the edge, high and low.
function Starbase.Layout(variety: string, radius: number, seed: number, faction: string?): Layout
  local owner = faction or "vessari"
  local makeup = Structures.Makeup(variety, radius, owner)
  local size = Structures.towerById[makeup.tower].size
  local tower = Starbase.Tower(owner, size)
  local towerRadius = radius * Starbase.TOWER
  local layout: Layout = {
    tower = { id = makeup.tower, model = tower.model, at = vector.create(0, 0, 0), look = vector.create(0, 0, 1),
      scale = towerRadius / tower.radius, radius = towerRadius },
    modules = {}, field = radius,
  }

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
    Object_SetAxes(object, part.look, UP)
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
