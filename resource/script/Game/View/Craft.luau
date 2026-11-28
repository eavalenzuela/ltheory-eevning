--!strict
-- Small craft: combat drones, fighters and bombers, laid out as aircraft
-- are (the owner's, 2026-11-25: "a generator that produces fighter
-- aircraft like shapes"). Each is a seed's: a body lofted nose to tail,
-- wings of one family or another, a tail to suit them, engines in the
-- tail or in pods, and what its work wants: a gun, a canopy, a
-- torpedo. Their rulings:
--   - general aircraft layout, after no aircraft in particular;
--   - smooth skins, with the details on them plated;
--   - no canopy on a drone (a sensor in its nose); fighters and bombers
--     have one;
--   - no moving parts;
--   - one people's manner to begin with, the Talmar's: rounded, grown,
--     symmetric, with swellings and pods on it, and no corners on what
--     is skin. (Other peoples' later, each its own.)
-- The combat drones are laid out by the same rules, smaller and stubbier.
-- A sentry drone, which never moves, is a ball with a turret above and
-- below it and antennas round its middle (Craft.Sentry). Mining and
-- repair drones are not made here.
--
--   local drawn = Craft.Draw(b, seed, "fighter")
--
-- Drawn nose to +z, its body two units long (z from -1 to 1), up +y,
-- starboard +x. Every figure here is mine.

local Plates = require("@lt/Game/View/Plates")
local Int = require("@lt/Int")

local Craft = {}

local PLATING, PATCH, FRAME, GLOW, TRIM = Plates.PLATING, Plates.PATCH, Plates.FRAME, Plates.GLOW, Plates.TRIM
local LAMP_RED, LAMP_GREEN = Plates.LAMP_RED, Plates.LAMP_GREEN
local TAU = 2 * math.pi

local function v(x: number, y: number, z: number): vector
  return vector.create(x, y, z)
end

type Builder = Plates.Builder

local function lerp(a: number, b: number, t: number): number
  return a + (b - a) * t
end

-- Where an engine's fire leaves it, as a hull's (Game/View/Hull's Exhaust).
export type Exhaust = { at: vector, radius: number }
-- What drawing a craft says of it: where its engines' fire leaves it,
-- and the mouths of its guns (or the nose of its torpedo), where its
-- shots leave from.
export type Drawn = { exhausts: { Exhaust }, muzzles: { vector } }

-- The kinds of craft, in the order the hull browser steps through them.
Craft.ROLES = { "light", "medium", "heavy", "fighter", "bomber" }

-- What each kind is, as ranges its dice pick from: how fat its body is
-- for its length ('wide', half its width; 'tall', its height for its
-- width), how far its wings reach tip to tip, how many engines it has
-- in its tail ('engines'), in pods ('pods'), the wing families it may
-- have, its guns, and whether it has a canopy or a torpedo.
type Role = {
  wide: { number }, tall: { number }, span: { number }, nose: { number }, engines: { number }, pods: { number },
  families: { string }, guns: number, canopy: boolean, torpedo: boolean, drone: boolean, thick: { number },
}
local ROLES: { [string]: Role } = {
  -- (small and stubby, a single engine and a gun under its chin)
  light = { wide = { 0.20, 0.26 }, tall = { 0.80, 1.0 }, span = { 1.9, 2.4 }, nose = { 0.16, 0.24 }, engines = { 1, 1 },
    pods = { 0, 0 }, families = { "delta", "tailless", "straight", "swept" }, guns = 1, canopy = false, torpedo = false, drone = true,
    thick = { 0.11, 0.15 } },
  medium = { wide = { 0.17, 0.22 }, tall = { 0.78, 0.95 }, span = { 2.0, 2.5 }, nose = { 0.18, 0.26 }, engines = { 1, 2 },
    pods = { 0, 0 }, families = { "delta", "swept", "canard", "tailless" }, guns = 2, canopy = false, torpedo = false, drone = true,
    thick = { 0.10, 0.14 } },
  -- (bulkier, with more plate on it)
  heavy = { wide = { 0.20, 0.27 }, tall = { 0.85, 1.05 }, span = { 2.0, 2.6 }, nose = { 0.16, 0.24 }, engines = { 2, 3 },
    pods = { 0, 0 }, families = { "delta", "swept", "straight", "canard" }, guns = 2, canopy = false, torpedo = false, drone = true,
    thick = { 0.11, 0.15 } },
  -- (slender, long in the nose)
  fighter = { wide = { 0.11, 0.15 }, tall = { 0.80, 1.0 }, span = { 1.4, 2.0 }, nose = { 0.28, 0.40 }, engines = { 1, 2 },
    pods = { 0, 0 }, families = { "delta", "swept", "canard", "forward", "tailless", "straight" }, guns = 2, canopy = true,
    torpedo = false, drone = false, thick = { 0.07, 0.10 } },
  -- (big wings, a heavy body, engines in its tail or under its wings, and its torpedo slung under it)
  bomber = { wide = { 0.15, 0.20 }, tall = { 0.85, 1.05 }, span = { 2.2, 3.0 }, nose = { 0.22, 0.32 }, engines = { 0, 2 },
    pods = { 0, 4 }, families = { "straight", "swept", "tailless", "delta" }, guns = 1, canopy = true, torpedo = true, drone = false,
    thick = { 0.09, 0.13 } },
}

-- Whether a kind of craft is a drone (and so has no canopy, and nobody's
-- lit ports in it).
function Craft.IsDrone(role: string): boolean
  local of = ROLES[role]
  return role == "sentry" or (of ~= nil and of.drone)
end

-- A skin through rows of points (each row a closed loop round, the rows
-- along), turned out: which way round its faces are wound is found from
-- the first row with any width to it, so that the side away from the
-- middle of its rows is the outside. Its two ends are left open.
local function sheet(b: Builder, part: number, rows: { { vector } })
  local count, round = #rows, #rows[1]
  local points: { number } = {}
  for _, row in rows do
    for _, p in row do
      table.insert(points, p.x)
      table.insert(points, p.y)
      table.insert(points, p.z)
    end
  end
  local function at(i: number, j: number): vector
    return rows[i + 1][j % round + 1]
  end
  -- (the winding: a quad of the first row wide enough, against the way out of it)
  local flip = false
  for i = 0, count - 2 do
    local middle = v(0, 0, 0)
    for _, p in rows[i + 1] do
      middle += p
    end
    middle /= round
    local j = round // 4
    local a, c, d = at(i, j), at(i, j + 1), at(i + 1, j)
    local n = vector.cross(c - a, d - a)
    local out = (a + c + d) / 3 - middle
    if vector.magnitude(n) > 1e-12 and vector.magnitude(out) > 1e-9 then
      flip = vector.dot(n, out) < 0
      break
    end
  end
  local faces: { number } = {}
  for i = 0, count - 2 do
    for j = 0, round - 1 do
      local a, c = i * round + j + 1, i * round + (j + 1) % round + 1
      local d, e = (i + 1) * round + j + 1, (i + 1) * round + (j + 1) % round + 1
      if flip then
        table.insert(faces, a); table.insert(faces, d); table.insert(faces, c)
        table.insert(faces, c); table.insert(faces, d); table.insert(faces, e)
      else
        table.insert(faces, a); table.insert(faces, c); table.insert(faces, d)
        table.insert(faces, c); table.insert(faces, e); table.insert(faces, d)
      end
    end
  end
  Plates.Skin(b, part, points, faces)
end

-- A wing (or a fin, a tailplane, a canard): from 'root' (its leading
-- edge there) out along 'span' (a unit way) 'length' far, its chord
-- running 'back' (a unit way): 'chord' long at its root and 'tip' at
-- its tip, its leading edge 'sweep' further back at the tip than at the
-- root (forward, if less than nothing). 'thick' is how thick it is for
-- its chord. 'curved': its chord falls away to its tip as a quarter of
-- an ellipse does, not straight. Its tip is rounded off, its root open
-- (inside what it stands out of). With 'mirror', a twin of it the other
-- side of the middle line. Where its tip is, and its chord there.
local function wing(b: Builder, part: number, root: vector, span: vector, length: number, back: vector, chord: number, tip: number,
  sweep: number, thick: number, curved: boolean, mirror: boolean): (vector, number)
  local up = vector.normalize(vector.cross(span, back))
  local STATIONS, ROUND = 22, 22
  local rows: { { vector } } = {}
  local tipAt, tipChord = root, chord
  for i = 0, STATIONS do
    -- (closer together toward the tip, where it is rounded off)
    local t = math.sin(i / STATIONS * math.pi / 2)
    local c = if curved then math.max(tip, chord * math.sqrt(math.max(0, 1 - t * t))) else lerp(chord, tip, t)
    local lead = sweep * t + (if curved then (chord - c) * 0.3 else 0)
    -- (its last stretch rounded: thinner and shorter in chord to nothing at the very tip)
    local k = math.clamp((t - 0.86) / 0.14, 0, 1)
    local full = math.sqrt(math.max(0, 1 - k * k))
    local shortened = c * (0.35 + 0.65 * full)
    lead += (c - shortened) * 0.5
    c = shortened
    local edge = root + span * (length * t) + back * lead
    local row: { vector } = {}
    for j = 0, ROUND - 1 do
      local a = j / ROUND * TAU
      local x = (1 + math.cos(a)) / 2
      local side = if math.abs(math.sin(a)) < 1e-9 then 0 else math.sign(math.sin(a))
      -- (a plain symmetric section, closed at its trailing edge)
      local half = 5 * thick * (0.2969 * math.sqrt(x) - 0.1260 * x - 0.3516 * x * x + 0.2843 * x ^ 3 - 0.1036 * x ^ 4)
      table.insert(row, edge + back * (x * c) + up * (side * half * c * full))
    end
    table.insert(rows, row)
    tipAt, tipChord = edge, c
  end
  sheet(b, part, rows)
  if mirror then
    local twin: { { vector } } = {}
    for _, row in rows do
      local other: { vector } = {}
      for _, p in row do
        table.insert(other, v(-p.x, p.y, p.z))
      end
      table.insert(twin, other)
    end
    sheet(b, part, twin)
  end
  return tipAt, tipChord
end

-- A nozzle let into the tail at 'at', facing aft, its mouth 'r' across
-- (half) and 'long' deep: a round bell with a lit throat. Where its
-- fire leaves it.
local function nozzle(b: Builder, at: vector, r: number, long: number): Exhaust
  -- (a closed section of its wall, run clockwise as Plates.Revolve wants: out from the axis, then along it)
  Plates.RevolveAt(b, FRAME, { v(r * 1.04, long * 0.15, 0), v(r * 0.98, -long, 0), v(r * 0.80, -long, 0), v(r * 0.72, long * 0.1, 0) },
    24, true, at, v(0, 0, 1))
  -- (its throat, lit, facing aft)
  Plates.RevolveAt(b, GLOW, { v(0.001, -long * 0.85, 0), v(r * 0.80, -long * 0.85, 0) }, 24, false, at, v(0, 0, 1))
  return { at = at + v(0, 0, -long), radius = r * 0.8 }
end

-- A round thing turned about 'axis' through 'at': a ball 'r' across (half).
-- (run from its top down, clockwise as Plates.Revolve wants: run upwards
-- it was inside out, its near side not drawn)
local function ball(b: Builder, part: number, at: vector, r: number, axis: vector)
  local profile: { vector } = {}
  for step = 0, 16 do
    local a = (0.002 + step / 16 * 0.996) * math.pi
    table.insert(profile, v(r * math.sin(a), r * math.cos(a), 0))
  end
  Plates.RevolveAt(b, part, profile, 24, false, at, axis)
end

-- A sentry drone (the owner's, 2026-11-25): "a larger central body,
-- spherical, with a cannon base on top and bottom, with turrets on each
-- (i.e. the pair-of-guns rule). new-style antennas protruding from near
-- the central equatorial line, with up to 15 degree vertical variance.
-- maybe 3-6 antennas". A ball a unit round, its poles up and down under
-- the two bases; the turrets on them and the antennas are not drawn
-- here (Game/View/Arms, Game/View/Movers): where they stand is said.
export type Sentry = {
  mounts: { { at: vector, up: vector } },
  -- (each antenna's foot on the ball, the way it stands out, how long it is drawn right out, and its blink's own pace and phase)
  antennas: { { at: vector, up: vector, long: number, pace: number, phase: number } },
}
function Craft.Sentry(b: Builder, seed: number): Sentry
  local rng = RNG_MTG(Int.Signed(math.floor(seed) * 7 + 77711))
  -- (the ball: about the up axis, so that its poles are under the bases)
  local profile: { vector } = {}
  for step = 0, 32 do
    local a = (0.002 + step / 32 * 0.996) * math.pi
    table.insert(profile, v(math.sin(a), math.cos(a), 0))
  end
  Plates.RevolveAt(b, PLATING, profile, 64, false, v(0, 0, 0), v(0, 1, 0))
  -- (a base on each pole: a round plinth with a chamfered top, and a ring where it meets the ball; as wide as a
  -- medium turret's ring reaches, drawn on a sentry's size, so that the whole of it stands on the base: the rule
  -- of hardpoints, Game/View/Hull)
  local r = rng:Float(0.53, 0.58)
  local high = 1 + rng:Float(0.12, 0.2)
  local foot = math.sqrt(1 - r * r)
  local mounts: { { at: vector, up: vector } } = {}
  for _, side in { 1, -1 } do
    local up = v(0, side, 0)
    -- (open at its foot, a little way into the ball: nothing of it is shut inside the ball to darken it, as the
    -- shade the occlusion is worked out from would)
    Plates.RevolveAt(b, PATCH, { v(0.001, high, 0), v(r * 0.9, high, 0), v(r, high - 0.04, 0), v(r, foot - 0.03, 0) },
      48, false, v(0, 0, 0), up)
    local ring: { vector } = {}
    for step = 0, 15 do
      local a = step / 16 * TAU
      table.insert(ring, v(r + 0.02 + 0.03 * math.cos(a), foot + 0.01 - 0.03 * math.sin(a), 0))
    end
    Plates.RevolveAt(b, TRIM, ring, 64, true, v(0, 0, 0), up)
    table.insert(mounts, { at = up * high, up = up })
  end
  -- (what it is, to stand a turret on: the ball and its two bases)
  Plates.Stands(b, function(p: vector): boolean
    local out = math.sqrt(p.x * p.x + p.z * p.z)
    return vector.magnitude(p) < 1 or (out < r and math.abs(p.y) < high and math.abs(p.y) > foot - 0.08)
  end)
  -- (its antennas: round near its middle, a little above or below it, each its own length)
  local antennas = {}
  local count = rng:Int(3, 6)
  local first = rng:Float(0, TAU)
  for index = 0, count - 1 do
    local round = first + (index + rng:Float(-0.25, 0.25)) / count * TAU
    local tilt = math.rad(rng:Float(-15, 15))
    local n = v(math.cos(tilt) * math.cos(round), math.sin(tilt), math.cos(tilt) * math.sin(round))
    table.insert(antennas, { at = n, up = n, long = rng:Float(0.6, 1.1), pace = rng:Float(0.85, 1.15), phase = rng:Float(0, 1) })
  end
  return { mounts = mounts, antennas = antennas }
end

-- Draw a small craft of a kind ("light", "medium", "heavy", "fighter",
-- "bomber") from its seed: where its engines' fire leaves it, and its
-- guns' mouths.
function Craft.Draw(b: Builder, seed: number, role: string): Drawn
  local of = ROLES[role] or ROLES.fighter
  local rng = RNG_MTG(Int.Signed(math.floor(seed) * 7 + 50023 + (table.find(Craft.ROLES, role) or 4) * 104729))
  local function within(range: { number }): number
    return rng:Float(range[1], range[2])
  end
  local function oneOf<T>(list: { T }): T
    return list[rng:Int(1, #list)]
  end
  local exhausts: { Exhaust } = {}
  local muzzles: { vector } = {}

  -- Its body: how fat, how long in the nose, where it is widest.
  local W = within(of.wide)
  local H = W * within(of.tall)
  local nose = within(of.nose)
  local widest = rng:Float(-0.35, 0.05)
  local blunt = of.drone
  -- (its engines: in its tail, how many and how big, and so how wide its tail is)
  local engines = rng:Int(of.engines[1], of.engines[2])
  local pods = 0
  if of.pods[2] > 0 then
    -- (a bomber's: two in its tail, or two or four in pods under its wings)
    local how = rng:Int(1, 3)
    engines, pods = if how == 1 then 2 else 0, if how == 1 then 0 elseif how == 2 then 2 else 4
  end
  local re = if engines == 1 then W * rng:Float(0.55, 0.7) elseif engines == 2 then W * rng:Float(0.40, 0.48) else W * rng:Float(0.36, 0.42)
  local tw, th
  if engines == 0 then
    tw, th = W * 0.22, H * 0.22
  elseif engines == 1 then
    tw, th = re * 1.12, re * 1.12
  elseif engines == 2 then
    tw, th = re * 2.15, re * 1.15
  else
    tw, th = re * 2.2, re * 2.05
  end
  local droop = -H * rng:Float(0, 0.25)
  local tipR = if blunt then W * rng:Float(0.5, 0.6) else W * 0.06
  local TAIL = -0.88
  local outline: Plates.Outline = {
    { TAIL, tw, th, 0 },
    { -0.65, lerp(tw, W, if blunt then 0.55 else 0.75), lerp(th, H, if blunt then 0.55 else 0.75), 0 },
    { widest, W, H, 0 },
    { 1 - 2 * nose, W * 0.92, H * 0.92, H * 0.04 + droop * 0.2 },
    { 1 - nose, W * (if blunt then 0.8 else 0.62), H * (if blunt then 0.8 else 0.6), droop * 0.6 },
    { 0.93, if blunt then lerp(W * 0.8, tipR, 0.6) else lerp(W * 0.62, tipR, 0.75),
      if blunt then lerp(H * 0.8, tipR, 0.6) else lerp(H * 0.6, tipR, 0.75), droop * 0.9 },
    { 1.0, tipR, tipR, droop },
  }
  Plates.Loft(b, PLATING, outline)
  local function surface(z: number, around: number): (vector, vector)
    return Plates.Point(outline, z, around), Plates.Normal(outline, z, around)
  end

  -- Engines in its tail.
  local long = re * 1.1
  local spots: { vector } = {}
  if engines == 1 then
    spots = { v(0, 0, 0) }
  elseif engines == 2 then
    spots = { v(re * 1.05, 0, 0), v(-re * 1.05, 0, 0) }
  elseif engines == 3 then
    spots = { v(re * 1.05, -re * 0.5, 0), v(-re * 1.05, -re * 0.5, 0), v(0, re * 0.85, 0) }
  end
  for _, spot in spots do
    table.insert(exhausts, nozzle(b, v(spot.x, spot.y, TAIL + 0.02), re, long))
  end

  -- Its wings: a family, and the tail that goes with it.
  local family = oneOf(of.families)
  local span = within(of.span) / 2
  local thick = within(of.thick)
  local low = oneOf({ -0.45, -0.2, 0, 0.35 }) * H
  local dihedral = math.rad(rng:Float(-4, 9))
  local spanWay = vector.normalize(v(math.cos(dihedral), math.sin(dihedral), 0))
  local BACK = v(0, 0, -1)
  local x0 = W * 0.35
  local reach = span - x0
  local curved = rng:Float(0, 1) < 0.4
  local chord, tip, sweep, lead
  local tailplane, fins, canards = false, 1, false
  if family == "delta" then
    lead = rng:Float(0.3, 0.55)
    chord = math.min(lead - TAIL - 0.02, rng:Float(1.1, 1.4))
    tip = chord * rng:Float(0.04, 0.12)
    sweep = chord - tip - rng:Float(0, 0.08)
    fins = oneOf({ 0, 1, 1, 2 })
    canards = rng:Float(0, 1) < 0.25
    curved = false
  elseif family == "canard" then
    lead = rng:Float(0.05, 0.25)
    chord = math.min(lead - TAIL - 0.02, rng:Float(0.8, 1.1))
    tip = chord * rng:Float(0.1, 0.25)
    sweep = chord - tip - rng:Float(0, 0.1)
    fins, canards = oneOf({ 1, 2 }), true
  elseif family == "tailless" then
    lead = rng:Float(0.15, 0.4)
    chord = math.min(lead - TAIL - 0.02, rng:Float(0.8, 1.05))
    tip = chord * rng:Float(0.25, 0.4)
    sweep = reach * rng:Float(0.6, 1.0)
    fins = oneOf({ 0, 2, 2 })
  elseif family == "forward" then
    lead = rng:Float(-0.25, -0.05)
    chord = rng:Float(0.5, 0.65)
    tip = chord * rng:Float(0.35, 0.5)
    sweep = -reach * rng:Float(0.35, 0.55)
    fins, canards = oneOf({ 1, 2 }), true
  elseif family == "swept" then
    lead = rng:Float(0.05, 0.3)
    chord = rng:Float(0.5, 0.75)
    tip = chord * rng:Float(0.25, 0.45)
    sweep = reach * rng:Float(0.5, 0.9)
    tailplane, fins = true, oneOf({ 1, 1, 2 })
  else -- straight
    lead = rng:Float(0.05, 0.3)
    chord = rng:Float(0.45, 0.65)
    tip = chord * rng:Float(0.4, 0.7)
    sweep = (chord - tip) * rng:Float(0.2, 0.6)
    tailplane, fins = true, oneOf({ 1, 1, 2 })
  end
  -- (its trailing edge no further back than its tail)
  chord = math.min(chord, lead - TAIL + 0.02)
  local root = v(x0, low, lead)
  local tipAt, tipChord = wing(b, PLATING, root, spanWay, reach, BACK, chord, tip, sweep, thick, curved, true)
  -- (where on the wing a point 'along' its span and 'into' its chord is: for pods, guns and lamps)
  local function onWing(along: number, into: number): vector
    local t = along
    local c = if curved then math.max(tip, chord * math.sqrt(math.max(0, 1 - t * t))) else lerp(chord, tip, t)
    local edge = root + spanWay * (reach * t) + BACK * (sweep * t + (if curved then (chord - c) * 0.3 else 0))
    return edge + BACK * (c * into)
  end
  -- (and a running light on each tip: red to port, green to starboard)
  local lamp = W * 0.05
  local tipMiddle = tipAt + BACK * (tipChord * 0.4)
  Plates.Block(b, LAMP_GREEN, tipMiddle + spanWay * lamp, v(lamp, lamp, lamp), nil, 0.5)
  Plates.Block(b, LAMP_RED, v(-tipMiddle.x, tipMiddle.y, tipMiddle.z) + v(-spanWay.x, spanWay.y, 0) * lamp, v(lamp, lamp, lamp), nil, 0.5)

  -- Its tail: a tailplane, and one fin on its back or two canted out.
  local finThick = thick * 0.9
  if tailplane then
    local c = chord * rng:Float(0.45, 0.6)
    local at = v(tw * 0.3, low * 0.3, TAIL + c + 0.04)
    wing(b, PLATING, at, spanWay, (span - x0) * rng:Float(0.35, 0.45), BACK, c, c * 0.45, c * 0.5, finThick, curved, true)
  end
  if fins == 1 then
    local c = rng:Float(0.35, 0.5)
    local _, top = Plates.Girth(outline, TAIL + c * 0.5)
    local at = v(0, top * 0.6, TAIL + c + 0.03)
    wing(b, PATCH, at, v(0, 1, 0), H * rng:Float(1.8, 2.6), BACK, c, c * 0.4, c * rng:Float(0.4, 0.8), finThick, curved, false)
  elseif fins == 2 then
    local c = rng:Float(0.3, 0.42)
    local cant = math.rad(rng:Float(12, 40))
    local wide = Plates.Girth(outline, TAIL + c * 0.5)
    local x = if family == "tailless" then 0 else wide * 0.6
    if family == "tailless" then
      -- (on a wing with no tail, its fins stand on its wings' tips)
      local at = tipAt + BACK * (tipChord * 0.05)
      local cc = tipChord * 0.95
      wing(b, PATCH, at, vector.normalize(v(math.sin(cant) * 0.5, 1, 0)), H * rng:Float(1.2, 1.8), BACK, cc, cc * 0.5, cc * 0.4,
        finThick, false, true)
    else
      local _, top = Plates.Girth(outline, TAIL + c * 0.5)
      local at = v(x, top * 0.5, TAIL + c + 0.03)
      wing(b, PATCH, at, vector.normalize(v(math.sin(cant), math.cos(cant), 0)), H * rng:Float(1.6, 2.2), BACK, c, c * 0.4,
        c * rng:Float(0.4, 0.7), finThick, curved, true)
    end
  end
  if canards then
    local c = rng:Float(0.18, 0.28)
    local z = 1 - nose * 1.6
    local at = v(W * 0.4, H * 0.25, z)
    wing(b, PLATING, at, spanWay, W * rng:Float(1.2, 2.0), BACK, c, c * 0.4, c * 0.6, finThick, false, true)
  end

  -- Engines in pods under its wings (a bomber's).
  for index = 1, pods // 2 do
    local along = if pods == 2 then rng:Float(0.3, 0.45) elseif index == 1 then 0.28 else 0.58
    local under = onWing(along, 0.35)
    local r = W * rng:Float(0.32, 0.4)
    local y = under.y - thick * chord * 0.4 - r * 1.2
    local half = 0.34
    local podLine: Plates.Outline = { { under.z - half, r, r, 0 }, { under.z - half * 0.3, r * 1.05, r * 1.05, 0 },
      { under.z + half * 0.6, r * 0.95, r * 0.95, 0 }, { under.z + half, r * 0.6, r * 0.6, 0 } }
    for _, side in { 1, -1 } do
      Plates.Loft(b, PLATING, podLine, under.x * side, y)
      Plates.Block(b, FRAME, v(under.x * side, (y + under.y) / 2, under.z), v(r * 0.18, (under.y - y) / 2, half * 0.5), nil, 0.3)
      table.insert(exhausts, nozzle(b, v(under.x * side, y, under.z - half + 0.02), r * 0.9, r * 1.0))
    end
  end

  -- Grown on it, as the Talmar's are: a swelling along its back, and
  -- pairs of them low on its flanks.
  local backFrom = if of.canopy then 1 - nose * 1.7 - 0.25 else 0.2
  Plates.Fairing(b, PATCH, outline, (backFrom + TAIL + 0.3) / 2, math.pi / 2, (backFrom - TAIL) * 0.6, W * rng:Float(0.5, 0.8),
    H * rng:Float(0.18, 0.3))
  for _ = 1, rng:Int(1, 2) do
    local z = rng:Float(-0.5, 0.3)
    local around = rng:Float(-0.5, 0.1)
    local length, width, height = rng:Float(0.35, 0.6), W * rng:Float(0.35, 0.55), H * rng:Float(0.12, 0.22)
    for _, turn in { around, math.pi - around } do
      Plates.Fairing(b, PATCH, outline, z, turn, length, width, height)
    end
  end

  -- Its canopy, or its sensor.
  if of.canopy then
    local z = 1 - nose * (if role == "bomber" then 1.1 else 1.35)
    Plates.Fairing(b, FRAME, outline, z, math.pi / 2, nose * rng:Float(0.9, 1.2), W * rng:Float(0.75, 0.95), H * rng:Float(0.4, 0.55))
  else
    -- (an eye set in its rounded nose)
    ball(b, GLOW, v(0, droop, 1.0 + tipR * 0.3), tipR * 0.55, v(0, 0, 1))
  end

  -- Its guns: plated housings, and their barrels out ahead.
  local function gun(at: vector, out: vector, size: number)
    Plates.Block(b, PATCH, at + out * (size * 0.5), v(size * 0.9, size * 0.8, size * 3.2), nil, 0.25)
    Plates.Block(b, FRAME, at + out * (size * 0.5) + v(0, 0, size * 3.0), v(size * 0.6, size * 0.55, size * 0.5), nil, 0.3)
    local mouth = at + out * (size * 0.5) + v(0, 0, size * 3.4)
    Plates.Tube(b, FRAME, { mouth, mouth + v(0, 0, size * 3.0), mouth + v(0, 0, size * 3.3) }, { size * 0.28, size * 0.24, size * 0.2 }, 10)
    table.insert(muzzles, mouth + v(0, 0, size * 3.3))
  end
  local size = W * 0.16
  if of.guns == 1 then
    -- (under its chin)
    local z = 1 - nose * 1.4
    local at = surface(z, -math.pi / 2)
    gun(at + v(0, size * 0.2, 0), v(0, -1, 0), size)
  else
    -- (on each flank, or each wing's root)
    local onRoot = rng:Float(0, 1) < 0.5 and family ~= "forward"
    for _, side in { 1, -1 } do
      if onRoot then
        local at = onWing(0.12, 0.05)
        gun(v(at.x * side, at.y, at.z - size * 2), v(0, 1, 0), size)
      else
        local z = 1 - nose * 1.5
        local at, out = surface(z, if side > 0 then -0.25 else math.pi + 0.25)
        gun(at - out * (size * 0.3), out, size)
      end
    end
  end

  -- And a heavy drone's armour: plates over its flanks.
  if role == "heavy" then
    for _, side in { 1, -1 } do
      local at, out = surface(-0.1, if side > 0 then 0.15 else math.pi - 0.15)
      Plates.Block(b, PATCH, at + out * (W * 0.05), v(W * 0.08, H * 0.45, 0.32), nil, 0.25)
    end
  end

  -- A bomber's torpedo, slung under it on a pylon, with its own small fins.
  if of.torpedo then
    local r = W * rng:Float(0.28, 0.36)
    local z = rng:Float(-0.25, 0.05)
    local _, bottom = Plates.Girth(outline, z)
    local y = -bottom - r * 1.5
    local half = rng:Float(0.42, 0.55)
    Plates.Loft(b, TRIM, { { z - half, r * 0.5, r * 0.5, 0 }, { z - half * 0.6, r, r, 0 }, { z + half * 0.5, r, r, 0 },
      { z + half, r * 0.45, r * 0.45, 0 } }, 0, y)
    Plates.Block(b, FRAME, v(0, (y - bottom) / 2, z), v(r * 0.25, (-bottom - y) / 2, half * 0.5), nil, 0.3)
    -- (what it launches leaves from the torpedo's nose)
    muzzles = { v(0, y, z + half) }
    for _, turn in { 0.25, -0.25 } do
      local a = turn * math.pi
      wing(b, FRAME, v(0, y, z - half * 0.55), v(math.cos(a), math.sin(a), 0), r * 1.3, BACK, half * 0.3, half * 0.15, half * 0.1, 0.08,
        false, true)
    end
  end

  return { exhausts = exhausts, muzzles = muzzles }
end

return Craft
