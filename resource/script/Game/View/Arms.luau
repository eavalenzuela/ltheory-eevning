--!strict
-- What is mounted on a hull's hardpoints: a model for every weapon
-- module, the same on whatever hull it is fitted to. A
-- hardpoint belongs to the hull and what sits on it to the pilot: any
-- turret goes on any turret hardpoint, any launcher on any launcher
-- hardpoint, and nothing here knows what faction built the ship.
--
-- A hull's hardpoint is a pair of mounts on opposite sides of it (see
-- Game/View/Hull), and a weapon fitted to it stands on both: there are
-- two of everything here on a ship, and the one that faces the target
-- is the one that fires.
--
-- A turret is two models: a base that turns on its mount, and a gun
-- that tips up and down in the base's cheeks. A launcher is one model,
-- a rack of tubes that does not move. Both are drawn once, in units of
-- their own, with the gun's barrel toward +z and the mount under y = 0,
-- and Arms.SIZE says how many metres a unit is for a small, a medium
-- and a large weapon.
--
-- Everything stands on the same foot: a square mounting ring, Arms.FOOT
-- units from its middle to its edge. So there are three footprints in
-- all, one for each size of weapon (about 4, 8 and 14 m across), and a
-- hull's pad for a size takes anything of that size (and the cover that
-- goes on an empty hardpoint).
--
--   local piece = Arms.Build("artillery.medium")
--   local muzzle = Arms.Place(piece, objects, origin, up, fore, aim, metres)

local Modules = require("@lt/Core/Data/Modules")
local Plates = require("@lt/Game/View/Plates")

local Arms = {}

local PLATING, PATCH, FRAME, GLOW, TRIM = Plates.PLATING, Plates.PATCH, Plates.FRAME, Plates.GLOW, Plates.TRIM
local block, beam = Plates.Block, Plates.Beam

-- How many metres a unit of the drawings is, for a small, a medium and
-- a large weapon. A weapon's size is its own and not the hull's, and
-- the sizes are fixed ones: a small
-- autocannon about 7 m long (on a frigate of 60 m or so, where it
-- looks big), a large pulse laser about 20 m (on a battleship of 800
-- to 1,600 m, where it looks small). The medium is put between the
-- two. So a gun on a big hull barely shows, which is as it should be:
-- it is noticed when it fires. The fourth is the XL size, which a
-- siege dreadnought mounts four of: about three times the large (a
-- first figure: a gun some 60 m long on a hull of 1,900).
Arms.SIZE = { 1.35, 2.5, 4.5, 14 }
-- Half the width of the mounting ring, in the drawings' units.
Arms.FOOT = 1.55
-- How far from its middle the ring reaches as a turret turns on it (its
-- corners, which are rounded): what a hardpoint has to have hull under.
Arms.REACH = 1.25 * Arms.FOOT
-- How far under the ring the hull may lie at the edge of that reach (a
-- flat ring on a curved skin), and how far down the ring's foundation
-- goes: a little farther, so that there is never air under a mount. On
-- a flat face the foundation is inside the hull, and the ring stands
-- flush as it always did. (Game/View/Hull holds every design to it:
-- Plates.Rests.)
Arms.GAP = 0.33 * Arms.FOOT
Arms.DEEP = Arms.GAP + 0.07 * Arms.FOOT

export type Piece = {
  base: Model?,           -- the part that turns on the mount; nil for a launcher
  gun: Model,             -- the part that aims (or the whole rack)
  pivot: vector,          -- where the gun's pivot is above the mount, in the drawings' units
  muzzle: vector,         -- where its shots leave, from the pivot, likewise
  turns: boolean,
  rate: number,           -- radians a second it can swing
  scale: number,          -- Arms.SIZE of its size: metres to a unit
}

local function v(x: number, y: number, z: number): vector
  return vector.create(x, y, z)
end

-- Gunmetal, with a band and a glow in the colour of the weapon's kind.
local function look(trim: { number }, glow: { number }): Plates.Look
  return { plating = { 0.30, 0.31, 0.33 }, patch = { 0.45, 0.45, 0.43 }, frame = { 0.12, 0.12, 0.13 }, glow = glow, trim = trim,
    wear = 0.55, rust = 0.22, sheets = 0.42 }
end

local LOOKS = {
  laser = look({ 0.55, 0.12, 0.10 }, { 1.0, 0.30, 0.16 }),
  beam = look({ 0.14, 0.26, 0.55 }, { 0.40, 0.68, 1.0 }),
  projectile = look({ 0.60, 0.48, 0.18 }, { 1.0, 0.80, 0.40 }),
  hybrid = look({ 0.14, 0.42, 0.36 }, { 0.36, 1.0, 0.74 }),
  rail = look({ 0.20, 0.34, 0.50 }, { 0.58, 0.82, 1.0 }),
  missile = look({ 0.52, 0.28, 0.08 }, { 1.0, 0.62, 0.26 }),
  miner = look({ 0.24, 0.44, 0.20 }, { 0.38, 1.0, 0.58 }),
}

local PIVOT = v(0, 1.9, 0)

-- The foot of everything that goes on a hardpoint: the mounting ring,
-- and under it its foundation, the ring's own outline carried down into
-- the hull (the owner's, 2026-11-11: "so they never have 'air' beneath
-- them ... on a curve there's a 'foundation' underneath that will
-- always reach the hull").
local function ring(b: Plates.Builder)
  block(b, FRAME, v(0, 0.22, 0), v(Arms.FOOT, 0.22, Arms.FOOT), nil, 0.45)
  block(b, FRAME, v(0, (0.10 - Arms.DEEP) / 2, 0), v(Arms.FOOT, (0.10 + Arms.DEEP) / 2, Arms.FOOT), nil, 0.45)
end

-- The base every turret stands on: the ring as a turntable, a pedestal,
-- and two cheeks for the gun's trunnions.
local function turntable(b: Plates.Builder)
  ring(b)
  block(b, PLATING, v(0, 0.85, -0.1), v(1.05, 0.55, 1.15), nil, 0.2)
  block(b, PLATING, v(0.98, 1.75, -0.05), v(0.16, 0.85, 0.75), nil, 0.25)
  block(b, PLATING, v(-0.98, 1.75, -0.05), v(0.16, 0.85, 0.75), nil, 0.25)
  block(b, TRIM, v(0, 0.50, 0), v(1.10, 0.07, 1.20), nil, 0.2)
  block(b, FRAME, v(0, 1.9, 0), v(1.20, 0.16, 0.16), nil, 0.5)
end

-- Each gun, about its pivot. Returns where its shots leave.
local GUNS: { [string]: (b: Plates.Builder) -> vector } = {
  -- twin short emitters, lensed
  ["laser.pulse"] = function(b)
    block(b, PLATING, v(0, 0.05, -0.15), v(0.72, 0.55, 1.05), nil, 0.2)
    for _, x in { -0.34, 0.34 } do
      block(b, PLATING, v(x, 0.08, 1.85), v(0.22, 0.22, 1.25), nil, 0.35)
      block(b, FRAME, v(x, 0.08, 2.95), v(0.27, 0.27, 0.10), nil, 0.4)
      block(b, GLOW, v(x, 0.08, 3.12), v(0.16, 0.16, 0.03), nil, 0.5)
    end
    for _, z in { -0.7, -0.3, 0.1 } do
      block(b, PATCH, v(0, 0.66, z), v(0.50, 0.10, 0.07))
    end
    return v(0, 0.08, 3.2)
  end,
  -- one long emitter with focusing rings, and its capacitor beside it
  ["laser.beam"] = function(b)
    block(b, PLATING, v(0, 0.05, -0.2), v(0.70, 0.58, 1.15), nil, 0.2)
    block(b, PLATING, v(0, 0.05, 3.0), v(0.25, 0.25, 2.5), nil, 0.4)
    for _, z in { 1.3, 2.9, 4.5 } do
      block(b, FRAME, v(0, 0.05, z), v(0.38, 0.38, 0.12), nil, 0.4)
    end
    block(b, GLOW, v(0, 0.05, 5.53), v(0.19, 0.19, 0.03), nil, 0.5)
    block(b, PATCH, v(-0.52, -0.25, -0.1), v(0.30, 0.30, 0.85), nil, 0.55)
    return v(0, 0.05, 5.6)
  end,
  -- two thin barrels, and a drum of rounds
  ["autocannon"] = function(b)
    block(b, PLATING, v(0, 0.02, -0.1), v(0.66, 0.50, 1.10), nil, 0.2)
    for _, x in { -0.24, 0.24 } do
      beam(b, FRAME, v(x, 0.05, 0.9), v(x, 0.05, 3.7), 0.11, 0.3)
      block(b, FRAME, v(x, 0.05, 3.62), v(0.15, 0.15, 0.14), nil, 0.3)
    end
    block(b, FRAME, v(0, 0.05, 1.5), v(0.42, 0.20, 0.16), nil, 0.3)
    block(b, PATCH, v(-0.55, -0.20, -0.25), v(0.42, 0.42, 0.50), v(0, 0, 0.3), 0.55)
    block(b, TRIM, v(0, 0.54, -0.2), v(0.50, 0.05, 0.60))
    return v(0, 0.05, 3.8)
  end,
  -- one heavy barrel in a recoil sleeve, with a brake at the muzzle
  ["artillery"] = function(b)
    block(b, PLATING, v(0, 0.08, -0.25), v(0.86, 0.70, 1.40), nil, 0.2)
    block(b, PLATING, v(0, 0.08, 1.9), v(0.42, 0.42, 0.95), nil, 0.3)
    beam(b, FRAME, v(0, 0.08, 2.6), v(0, 0.08, 6.5), 0.24, 0.2)
    block(b, FRAME, v(0, 0.08, 6.35), v(0.38, 0.30, 0.32), nil, 0.25)
    block(b, PATCH, v(0, 0.82, -0.5), v(0.60, 0.08, 0.80))
    block(b, TRIM, v(0, 0.08, 1.1), v(0.46, 0.46, 0.09), nil, 0.3)
    return v(0, 0.08, 6.8)
  end,
  -- a short wide throat ringed with coils, glowing
  ["blaster"] = function(b)
    block(b, PLATING, v(0, 0.02, -0.2), v(0.92, 0.66, 1.00), nil, 0.2)
    block(b, PLATING, v(0, 0.02, 1.55), v(0.50, 0.50, 0.85), nil, 0.4)
    for _, z in { 1.0, 1.55, 2.1 } do
      block(b, FRAME, v(0, 0.02, z), v(0.60, 0.60, 0.10), v(0, 0, math.pi / 4), 0.4)
    end
    block(b, GLOW, v(0, 0.02, 2.42), v(0.36, 0.36, 0.03), nil, 0.5)
    for _, x in { -1.0, 1.0 } do
      block(b, PATCH, v(x, 0.1, -0.2), v(0.06, 0.50, 0.70))
    end
    return v(0, 0.02, 2.5)
  end,
  -- two long rails with the light between them
  ["railgun"] = function(b)
    block(b, PLATING, v(0, 0.02, -0.3), v(0.80, 0.60, 1.20), nil, 0.2)
    for _, x in { -0.34, 0.34 } do
      block(b, PLATING, v(x, 0.02, 3.4), v(0.11, 0.40, 2.75), nil, 0.2)
    end
    block(b, GLOW, v(0, 0.02, 3.4), v(0.04, 0.10, 2.60), nil, 0.3)
    for _, z in { 1.2, 3.0, 4.8 } do
      block(b, FRAME, v(0, 0.02, z), v(0.50, 0.48, 0.12), nil, 0.3)
    end
    block(b, TRIM, v(0, 0.64, -0.3), v(0.56, 0.05, 0.70))
    return v(0, 0.02, 6.3)
  end,
  -- a lens in a dish, on a short arm
  ["miner"] = function(b)
    block(b, PLATING, v(0, 0.0, -0.1), v(0.55, 0.45, 0.80), nil, 0.25)
    beam(b, FRAME, v(0, 0.0, 0.6), v(0, 0.0, 1.5), 0.18, 0.3)
    block(b, PATCH, v(0, 0.0, 1.6), v(0.70, 0.70, 0.16), nil, 0.5)
    block(b, FRAME, v(0, 0.0, 1.74), v(0.50, 0.50, 0.06), v(0, 0, math.pi / 4), 0.5)
    block(b, GLOW, v(0, 0.0, 1.82), v(0.26, 0.26, 0.03), nil, 0.5)
    return v(0, 0.0, 1.9)
  end,
}

-- Which gun a module type has, and whose colours: by the start of its id.
local KINDS: { { string } } = {
  { "laser.pulse", "laser.pulse", "laser" }, { "laser.beam", "laser.beam", "beam" },
  { "autocannon", "autocannon", "projectile" }, { "artillery", "artillery", "projectile" },
  { "blaster", "blaster", "hybrid" }, { "railgun", "railgun", "rail" }, { "miner", "miner", "miner" },
}

-- Launchers: how many tubes across and up, and half the rack's size.
local RACKS: { [string]: { any } } = {
  ["launcher.light"] = { 2, 2, v(0.85, 0.75, 2.1) },
  ["launcher.heavy"] = { 3, 2, v(1.15, 0.80, 2.3) },
  ["launcher.cruise"] = { 3, 3, v(1.20, 1.15, 2.6) },
  ["launcher.siege"] = { 4, 3, v(1.45, 1.15, 2.9) },
}

-- A rack of tubes on a short pylon on the ring, mouths forward. Returns
-- where its missiles leave.
local function rack(b: Plates.Builder, columns: number, rows: number, half: vector): vector
  local center = v(0, half.y + 0.95, 0)
  ring(b)
  block(b, FRAME, v(0, 0.70, -half.z * 0.1), v(half.x * 0.55, 0.28, half.z * 0.42), nil, 0.2)
  block(b, PLATING, center, half, nil, 0.08)
  block(b, TRIM, center + v(0, 0, -half.z * 0.3), v(half.x * 1.04, half.y * 1.04, half.z * 0.10), nil, 0.1)
  block(b, FRAME, center + v(0, 0, half.z), v(half.x * 0.93, half.y * 0.93, half.z * 0.04), nil, 0.1)
  block(b, PATCH, center + v(0, half.y, -half.z * 0.55), v(half.x * 0.6, 0.06, half.z * 0.25))
  for column = 1, columns do
    for row = 1, rows do
      local x = (column - (columns + 1) / 2) * (1.76 * half.x / columns)
      local y = (row - (rows + 1) / 2) * (1.76 * half.y / rows)
      block(b, FRAME, center + v(x, y, half.z * 1.05), v(0.64 * half.x / columns, 0.64 * half.y / rows, half.z * 0.04), nil, 0.5)
    end
  end
  return center + v(0, 0, half.z * 1.1)
end

local built: { [string]: Piece } = {}
local blank: Model? = nil

-- 1 small, 2 medium, 3 large: the size of a weapon module.
function Arms.SizeOf(type: string): number
  local module = Modules.byId[type]
  local weapon = if module then module.weapon else nil
  if weapon then
    return weapon.size
  end
  return if string.find(type, ".xl", 1, true) or string.find(type, "siege", 1, true) then 4
    elseif string.find(type, "large", 1, true) or string.find(type, "strip", 1, true) then 3
    elseif string.find(type, "medium", 1, true) then 2
    else 1
end

-- The models of a module that takes a hardpoint, or nil if the type has
-- none to show. Made once for each kind and kept.
function Arms.Build(type: string): Piece?
  local size = Arms.SizeOf(type)
  local racks = nil
  for prefix, spec in RACKS do
    if string.sub(type, 1, #prefix) == prefix then
      racks = spec
    end
  end
  local kind: { string }? = nil
  for _, candidate in KINDS do
    if string.sub(type, 1, #candidate[1]) == candidate[1] then
      kind = candidate
    end
  end
  local key = if racks then `rack:{racks[1]}x{racks[2]}` elseif kind then kind[2] else ""
  if key == "" then
    return nil
  end
  local made = built[key]
  if made == nil then
    if racks then
      local b = Plates.New(#key * 3.1, 0.9)
      local muzzle = rack(b, racks[1], racks[2], racks[3])
      made = { base = nil, gun = (Plates.Finish(b, LOOKS.missile)), pivot = v(0, 0, 0), muzzle = muzzle, turns = false, rate = 0, scale = 1 }
    else
      local which = kind :: { string }
      local b = Plates.New(#key * 3.1, 0.9)
      turntable(b)
      local base = Plates.Finish(b, LOOKS[which[3]])
      local g = Plates.New(#key * 5.3, 0.9)
      local muzzle = GUNS[which[2]](g)
      made = { base = base, gun = (Plates.Finish(g, LOOKS[which[3]])), pivot = PIVOT, muzzle = muzzle, turns = true, rate = 1.6, scale = 1 }
    end
    built[key] = made
  end
  -- (the same models at every size: only the scale differs, and a big
  -- gun swings more slowly)
  local piece = table.clone(made)
  piece.scale = Arms.SIZE[size] or 1
  piece.rate = made.rate / ((piece.scale / Arms.SIZE[1]) ^ 0.7)
  return piece
end

-- The cover on a hardpoint with nothing fitted.
function Arms.Blank(): Model
  if blank == nil then
    local b = Plates.New(1.7, 0.9)
    ring(b)
    block(b, PATCH, v(0, 0.47, 0), v(0.95, 0.05, 0.95), v(math.pi / 4, 0, 0), 0.3)
    beam(b, FRAME, v(-0.9, 0.53, 0), v(0.9, 0.53, 0), 0.06)
    beam(b, FRAME, v(0, 0.53, -0.9), v(0, 0.53, 0.9), 0.06)
    blank = (Plates.Finish(b, LOOKS.projectile))
  end
  return blank :: Model
end

-- How far down and up a gun can tip from level: not through its own
-- mount, nor quite straight up.
local LOW, HIGH = -0.12, 1.5

-- Whether a turret can be brought to bear on something: 'facing' is how
-- squarely its mount faces it (the way out of the hull there, dotted
-- with the way to the target). If not, the hull is in the way, and the
-- shot is for the turret's twin on the far side.
function Arms.Sees(facing: number): boolean
  return facing >= math.sin(LOW)
end

-- The level way a mount faces at rest, and the level way to its side.
local function frame(up: vector, fore: vector): (vector, vector)
  local level = fore - up * vector.dot(fore, up)
  level = if vector.magnitude(level) > 1e-4 then vector.normalize(level) else vector.normalize(vector.cross(up, vector.create(1, 0, 0)))
  return level, vector.cross(up, level)
end

-- Turn a turret toward 'aim' (or back to rest, with nil) for 'seconds',
-- no faster than it can swing. 'yaw' and 'lift' are where it is now:
-- radians round from rest, and up from level. Returns where it gets to,
-- and that as the way to point, for Arms.Place. (A launcher stays put.)
function Arms.Swing(piece: Piece, up: vector, fore: vector, aim: vector?, yaw: number, lift: number, seconds: number): (number, number, vector)
  local level, side = frame(up, fore)
  local wantYaw, wantLift = 0, 0
  if aim and piece.turns then
    local x, z = vector.dot(aim, side), vector.dot(aim, level)
    if x * x + z * z > 1e-6 then
      wantYaw = math.atan2(x, z)
    end
    wantLift = math.clamp(math.asin(math.clamp(vector.dot(aim, up), -1, 1)), LOW, HIGH)
  end
  local most = piece.rate * seconds
  -- (the short way round)
  local turn = (wantYaw - yaw + math.pi) % (2 * math.pi) - math.pi
  yaw += math.clamp(turn, -most, most)
  lift += math.clamp(wantLift - lift, -most, most)
  local flat = level * math.cos(yaw) + side * math.sin(yaw)
  return yaw, lift, flat * math.cos(lift) + up * math.sin(lift)
end

-- Stand a piece on a mount and point it. 'origin' is the mount, 'up'
-- the way out of the hull there and 'fore' the way it faces at rest
-- (both of length 1, in the scene); 'aim' is the way to its target, or
-- nil to rest; 'metres' is how long a metre is in the scene. Returns
-- where its shots leave from, and the way it now points.
function Arms.Place(piece: Piece, base: Object?, gun: Object, origin: vector, up: vector, fore: vector, aim: vector?,
  metres: number): (vector, vector)
  local size = piece.scale * metres
  local level = frame(up, fore)
  local toward = level
  local point = level
  if aim and piece.turns then
    local flat = aim - up * vector.dot(aim, up)
    if vector.magnitude(flat) > 1e-3 then
      toward = vector.normalize(flat)
    end
    local lift = math.clamp(math.asin(math.clamp(vector.dot(aim, up), -1, 1)), LOW, HIGH)
    point = toward * math.cos(lift) + up * math.sin(lift)
  end
  if base then
    base:SetPos(origin)
    Object_SetAxes(base, toward, up)
    base:SetScale(vector.create(size, size, size))
  end
  local right = vector.cross(up, toward)
  local pivot = origin + (right * piece.pivot.x + up * piece.pivot.y + toward * piece.pivot.z) * size
  gun:SetPos(pivot)
  Object_SetAxes(gun, point, up)
  gun:SetScale(vector.create(size, size, size))
  local gunUp = vector.normalize(up - point * vector.dot(up, point))
  local gunRight = vector.cross(gunUp, point)
  return pivot + (gunRight * piece.muzzle.x + gunUp * piece.muzzle.y + point * piece.muzzle.z) * size, point
end

return Arms
