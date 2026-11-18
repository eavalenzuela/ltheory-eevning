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
-- owner's to pick (Citadel.Pick).

local Arms = require("@lt/Game/View/Arms")
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
--   pyramid   a four-sided pyramid in flat plate (on nothing: the
--             owner, 2026-11-18, "this is not a structure on the ground")
--   diamond   a cut stone: a flat table, a crown sloping out to the
--             girdle and a deep point under it (eight sides, or four)
-- The pyramid and the stone grow more of themselves off their facets
-- (the owner, 2026-11-18: "attaching additional pyramid/diamonds to them,
-- facet-to-facet"; and of how, "both, depending on seed. size steps
-- double the number of attached pieces"): each one smaller, either laid
-- with a facet of its own flush on a facet it grows from, or stood on it
-- by its base (a pyramid) or its table (a stone). On their facets lie
-- flush modules, boxes and drums, as the seed has it ("Decorative, from
-- the seed"), and their hangars are let into the facets themselves, each
-- door a trapezoid: the facet's own shape brought in from its edges and
-- cut to a band beside its widest edge (the owner's drawing, the same day).
--   wormhole  a lightless sphere in the middle, rings round it each
--             turning its own way about an axis of its own, and outside
--             them a level ring that stands still, with hangars at its
--             quarters and towers standing through it
Citadel.STYLES = { "blocks", "pyramid", "diamond", "wormhole" }

-- What each citadel is drawn as: its seed, whether it is asymmetrical,
-- the kinds of its surface detail, its style, and its paint (the
-- owner's, 2026-11-17: a design wears the paint it was picked in, "for
-- now", where its owner is a pilot; a faction's citadel wears the
-- faction's). ('doors': the most hangar doors it has, 1, 2 or 4;
-- Citadel.DOORS if not said.)
export type Pick = { seed: number, asym: boolean, detail: string, style: string, paint: string, doors: number?, stand: boolean? }
-- The citadels there are to pick, 35 of them (the owner, 2026-11-18):
--   standard  habitation, trade hub, refinery, research station and
--             shipyard at every size, for every human people (Vessari,
--             Talmar, Orun, and the Unbound) and for pilots, each in its
--             owner's paint; and the generator citadel, large and
--             extra-large, its generator module making it a gravity or a
--             wormhole station ("the module you fit will determine which
--             it is"), the sphere black or deep purple by which. (The
--             Kethri build none: theirs are colony ships.)
--   vail,     the alien peoples who build citadels, four each: a huge
--   nimia     shipyard, an extra-large refinery, a large habitation and a
--             large research station; no small or medium ones.
Citadel.PEOPLES = { "standard", "vail", "nimia" }
Citadel.SLOTS = {
  standard = { habitation = { 1, 2, 3, 4, 5 }, tradehub = { 1, 2, 3, 4, 5 }, refinery = { 1, 2, 3, 4, 5 },
    research = { 1, 2, 3, 4, 5 }, shipyard = { 1, 2, 3, 4, 5 }, generator = { 3, 4 } },
  vail = { shipyard = { 5 }, refinery = { 4 }, habitation = { 3 }, research = { 3 } },
  nimia = { shipyard = { 5 }, refinery = { 4 }, habitation = { 3 }, research = { 3 } },
} :: { [string]: { [string]: { number } } }
-- (the kinds as the browser goes through them: Data/Structures' gravity
-- and wormhole kinds are both the generator citadel)
Citadel.KINDS = { "habitation", "tradehub", "refinery", "research", "shipyard", "generator" }
Citadel.KIND_NAMES = { habitation = "Habitation", tradehub = "Trade Hub", refinery = "Refinery",
  research = "Research Station", shipyard = "Shipyard", generator = "Generator Citadel" } :: { [string]: string }

-- The kind a citadel is picked as: a gravity or wormhole station is the
-- generator citadel.
function Citadel.Slot(kind: string?): string
  if kind == "gravity" or kind == "wormhole" then
    return "generator"
  end
  return kind or "habitation"
end

-- Whether a people has a citadel of a kind at a size: one of the 35.
function Citadel.HasSlot(people: string, kind: string, size: number): boolean
  local sizes = (Citadel.SLOTS[people] or {})[Citadel.Slot(kind)]
  return sizes ~= nil and table.find(sizes, size) ~= nil
end

-- The owner's picks, as they come (people, kind, size). Everything picked
-- before 2026-11-18 is to be picked again from the generator as it is now
-- (the owner: "I'm going to re-do all of the previously-picked
-- stations"); until a slot is, it is drawn from a stand-in (STAND).
local ALL = "antennas pipes greebles lights rivets"
local PICKED: { [string]: { [string]: { [number]: Pick } } } = {
  standard = {
    habitation = {
      [1] = { seed = 4464, asym = false, detail = ALL, style = "blocks", paint = "kethri", doors = 2 },
      [2] = { seed = 4464, asym = false, detail = ALL, style = "blocks", paint = "kethri", doors = 1 },
      [3] = { seed = 69839, asym = false, detail = ALL, style = "blocks", paint = "kethri", doors = 1 },
      [4] = { seed = 70790, asym = true, detail = ALL, style = "blocks", paint = "kethri", doors = 1 },
      [5] = { seed = 21271, asym = true, detail = ALL, style = "blocks", paint = "kethri", doors = 1 },
    },
    tradehub = {
      [1] = { seed = 30100, asym = true, detail = ALL, style = "blocks", paint = "civil", doors = 1 },
      [2] = { seed = 38177, asym = true, detail = ALL, style = "blocks", paint = "civil", doors = 1 },
      [3] = { seed = 24873, asym = false, detail = ALL, style = "blocks", paint = "civil", doors = 1 },
      [4] = { seed = 24876, asym = false, detail = ALL, style = "blocks", paint = "civil", doors = 1 },
      [5] = { seed = 49226, asym = false, detail = ALL, style = "blocks", paint = "civil", doors = 2 },
    },
    refinery = {
      [1] = { seed = 96942, asym = false, detail = ALL, style = "blocks", paint = "orun", doors = 1 },
      [2] = { seed = 96944, asym = false, detail = ALL, style = "blocks", paint = "orun", doors = 1 },
      [3] = { seed = 73003, asym = true, detail = ALL, style = "blocks", paint = "orun", doors = 1 },
      [4] = { seed = 58779, asym = true, detail = ALL, style = "blocks", paint = "orun", doors = 1 },
      [5] = { seed = 63425, asym = false, detail = ALL, style = "blocks", paint = "orun", doors = 1 },
    },
    research = {
      [1] = { seed = 18567, asym = true, detail = ALL, style = "blocks", paint = "dark", doors = 1 },
      [2] = { seed = 53556, asym = false, detail = ALL, style = "blocks", paint = "dark", doors = 1 },
      [3] = { seed = 53558, asym = false, detail = ALL, style = "blocks", paint = "dark", doors = 1 },
      [4] = { seed = 41107, asym = false, detail = ALL, style = "blocks", paint = "dark", doors = 2 },
      [5] = { seed = 41118, asym = false, detail = ALL, style = "blocks", paint = "dark", doors = 1 },
    },
    shipyard = {
      [1] = { seed = 57102, asym = false, detail = ALL, style = "blocks", paint = "vessari", doors = 1 },
      [2] = { seed = 53322, asym = true, detail = ALL, style = "blocks", paint = "vessari", doors = 1 },
      [3] = { seed = 54353, asym = false, detail = ALL, style = "blocks", paint = "vessari", doors = 2 },
      [4] = { seed = 57191, asym = true, detail = ALL, style = "blocks", paint = "vessari", doors = 1 },
      [5] = { seed = 57191, asym = true, detail = ALL, style = "blocks", paint = "vessari", doors = 1 },
    },
    generator = {
      [3] = { seed = 44806, asym = true, detail = ALL, style = "wormhole", paint = "vail", doors = 1 },
      [4] = { seed = 69913, asym = true, detail = ALL, style = "wormhole", paint = "vail", doors = 1 },
    },
  },
  vail = {
    habitation = {
      [3] = { seed = 30387, asym = false, detail = ALL, style = "pyramid", paint = "vail", doors = 1 },
    },
    research = {
      [3] = { seed = 84597, asym = false, detail = ALL, style = "pyramid", paint = "vail", doors = 1 },
    },
    refinery = {
      [4] = { seed = 25499, asym = false, detail = ALL, style = "pyramid", paint = "vail", doors = 1 },
    },
    shipyard = {
      [5] = { seed = 22336, asym = true, detail = ALL, style = "pyramid", paint = "vail", doors = 1 },
    },
  },
  nimia = {
    habitation = {
      [3] = { seed = 34398, asym = false, detail = ALL, style = "diamond", paint = "civil", doors = 1 },
    },
    research = {
      [3] = { seed = 46386, asym = false, detail = ALL, style = "diamond", paint = "civil", doors = 1 },
    },
    refinery = {
      [4] = { seed = 13170, asym = false, detail = ALL, style = "diamond", paint = "civil", doors = 1 },
    },
    shipyard = {
      [5] = { seed = 38719, asym = false, detail = ALL, style = "diamond", paint = "civil", doors = 2 },
    },
  },
}
-- The stand-ins: the old picks, a kind's small one grown to every size
-- it has no pick at (marked 'stand').
local STAND: { [string]: Pick } = {
  habitation = { seed = 74919, asym = true, detail = ALL, style = "blocks", paint = "vessari", stand = true },
  tradehub = { seed = 50243, asym = true, detail = ALL, style = "blocks", paint = "talmar", stand = true },
  refinery = { seed = 47535, asym = false, detail = ALL, style = "blocks", paint = "orun", stand = true },
  research = { seed = 20247, asym = false, detail = ALL, style = "blocks", paint = "vail", stand = true },
  shipyard = { seed = 47336, asym = false, detail = ALL, style = "blocks", paint = "civil", stand = true },
  generator = { seed = 49070, asym = true, detail = ALL, style = "wormhole", paint = "dark", stand = true },
}

-- The pick a citadel is drawn from: of its people (standard, if it is
-- not an alien people's or they have no such citadel), its kind (a
-- habitation's, if no such kind) and its size. A size there is no
-- citadel of (a small generator citadel) is drawn as the nearest there is.
function Citadel.Pick(kind: string?, size: number, people: string?): Pick
  local slot = Citadel.Slot(kind)
  if STAND[slot] == nil then
    slot = "habitation"
  end
  local who = if people and Citadel.HasSlot(people, slot, size) then people else "standard"
  local sizes = Citadel.SLOTS[who][slot]
  local nearest = sizes[1]
  for _, has in sizes do
    if math.abs(has - size) < math.abs(nearest - size) then
      nearest = has
    end
  end
  local own = PICKED[who][slot]
  return (own and own[nearest]) or (if who ~= "standard" then (PICKED.standard[slot] or {})[nearest] else nil) or STAND[slot]
end

-- How many of the 35 are picked, and how many there are.
function Citadel.Picked(): (number, number)
  local done, all = 0, 0
  for _, people in Citadel.PEOPLES do
    for slot, sizes in Citadel.SLOTS[people] do
      for _, size in sizes do
        all += 1
        if (PICKED[people][slot] or {})[size] then
          done += 1
        end
      end
    end
  end
  return done, all
end

-- The people a faction's citadels are drawn as: its own, if it is an
-- alien people who builds them, and else the standard ones.
function Citadel.PeopleOf(faction: string?): string
  if faction and Citadel.SLOTS[faction] then
    return faction
  end
  return "standard"
end

-- A hangar's mouth: the middle of the opening, the way out of it, and
-- half of it across and up (in the generator's units).
-- (and on a facet, the door's corners in order round it: a trapezoid)
export type Mouth = { at: vector, n: vector, wide: number, high: number, corners: { vector }? }

-- A solid in flat plates (a pyramid, a cut stone): its faces, each its
-- corners in order round it, and a point inside it. Convex.
-- ('closed': the faces that lie against something, the plinth or the
-- facet it grows from: nothing goes on them.)
-- ('role': what it is, where it is not the citadel's body: "piece" (grown
-- off it), "module", "mast", "deck" (what stands on a deck). Hardpoints
-- go on the body and its pieces.)
export type Solid = { faces: { { vector } }, part: number, middle: vector, closed: { [number]: boolean }?, role: string? }
-- A ring of a wormhole citadel, round its middle: how far out, how
-- thick, the way its plane faces, what it turns about (in its plane),
-- how fast (radians a second; the next one the other way; 0 for the
-- outermost, which stands still and is part of the citadel's own
-- model) and how far round it starts.
-- ('center': where its middle is, if not the citadel's: a ring standing
-- on a deck. A ring that turns is always about the middle.)
export type Ring = { radius: number, thick: number, normal: vector, axis: vector, rate: number, phase: number, center: vector? }
-- A citadel grown, in the hull generator's units: its blocks as plates,
-- its hangar mouths, its solids, its rings, and the radius of the sphere
-- of its wormhole (0 for none).
-- A hardpoint: where its mount stands, the way out from it there, a way
-- along the face it stands on (what its gun faces at rest), the size of
-- weapon it takes (2 medium, 3 large, 4 XL), what it is for ("weapon",
-- "pds" or "super") and how far its foot reaches from its middle.
-- ('twin': the mount it is a pair with, on the far side, by its place in
-- the list; 0 for one with none, a super weapon's.)
export type Mount = { at: vector, n: vector, fore: vector, size: number, kind: string, radius: number, twin: number }
-- And a faceted citadel's masts' beams of light (from the tip, out to
-- 'to', so wide) and balls of energy (the middle, the radius).
export type Beam = { from: vector, to: vector, width: number }
export type Ball = { at: vector, radius: number }
export type Shape = { plates: { Hull.Plate }, mouths: { Mouth }, solids: { Solid }, rings: { Ring }, hole: number, beams: { Beam },
  balls: { Ball }, mounts: { Mount }, metres: number }

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

-- What a solid is, for telling whether two cut into each other: its
-- corners, the ways its faces look, its edges' ways, and how far it
-- reaches from its middle. Worked out once a solid.
type Geometry = { corners: { vector }, normals: { vector }, edges: { vector }, radius: number }
local geometries = setmetatable({} :: { [Solid]: Geometry }, { __mode = "k" })
local function geometryOf(solid: Solid): Geometry
  local known = geometries[solid]
  if known then
    return known
  end
  local corners: { vector } = {}
  local normals: { vector } = {}
  local edges: { vector } = {}
  local radius = 0
  for _, face in solid.faces do
    for index, corner in face do
      local seen = false
      for _, other in corners do
        if vector.magnitude(other - corner) < 1e-6 then
          seen = true
          break
        end
      end
      if not seen then
        table.insert(corners, corner)
        radius = math.max(radius, vector.magnitude(corner - solid.middle))
      end
      local edge = face[index % #face + 1] - corner
      if vector.magnitude(edge) > 1e-6 then
        local way = vector.normalize(edge)
        local same = false
        for _, other in edges do
          if math.abs(vector.dot(other, way)) > 0.9999 then
            same = true
            break
          end
        end
        if not same then
          table.insert(edges, way)
        end
      end
    end
    local n = vector.cross(face[2] - face[1], face[3] - face[1])
    if vector.magnitude(n) > 1e-9 then
      table.insert(normals, vector.normalize(n))
    end
  end
  local made: Geometry = { corners = corners, normals = normals, edges = edges, radius = radius }
  geometries[solid] = made
  return made
end

-- Whether two convex solids cut into each other by more than 'slack'
-- (touching, face to face, is not cutting): there is no way to look
-- along which they are apart (the separating axes: the ways the faces of
-- each look, and the ways across an edge of each).
local function cut(a: Solid, b: Solid, slack: number): boolean
  local ga, gb = geometryOf(a), geometryOf(b)
  if vector.magnitude(a.middle - b.middle) > ga.radius + gb.radius then
    return false
  end
  local function apart(axis: vector): boolean
    local loA, hiA, loB, hiB = math.huge, -math.huge, math.huge, -math.huge
    for _, p in ga.corners do
      local d = vector.dot(p, axis)
      loA, hiA = math.min(loA, d), math.max(hiA, d)
    end
    for _, p in gb.corners do
      local d = vector.dot(p, axis)
      loB, hiB = math.min(loB, d), math.max(hiB, d)
    end
    return hiA <= loB + slack or hiB <= loA + slack
  end
  for _, n in ga.normals do
    if apart(n) then
      return false
    end
  end
  for _, n in gb.normals do
    if apart(n) then
      return false
    end
  end
  for _, ea in ga.edges do
    for _, eb in gb.edges do
      local axis = vector.cross(ea, eb)
      if vector.magnitude(axis) > 1e-4 and apart(vector.normalize(axis)) then
        return false
      end
    end
  end
  return true
end

-- A box as a solid (for telling what cuts into it).
local function boxSolid(center: vector, half: vector): Solid
  local c: { vector } = {}
  for _, sx in { -1, 1 } do
    for _, sy in { -1, 1 } do
      for _, sz in { -1, 1 } do
        table.insert(c, center + v(sx * half.x, sy * half.y, sz * half.z))
      end
    end
  end
  -- (corners by x, y, z: 1 is ---, 2 --+, 3 -+-, 4 -++, 5 +--, 6 +-+, 7 ++-, 8 +++)
  local faces = { { c[1], c[2], c[4], c[3] }, { c[5], c[7], c[8], c[6] }, { c[1], c[5], c[6], c[2] }, { c[3], c[4], c[8], c[7] },
    { c[1], c[3], c[7], c[5] }, { c[2], c[6], c[8], c[4] } }
  return { faces = faces, part = PLATING, middle = center }
end

-- How many pieces a faceted citadel (a pyramid's, a stone's) grows off
-- its facets at the smallest size, twice as many each size up; and how
-- many modules lie on its facets, a size. (Mine.)
Citadel.PIECES = 2
Citadel.MODULES = 3
-- The most hangar doors a citadel has, of any style: the biggest faces
-- have them first, and after so many there are no more (the owner,
-- 2026-11-18: "a total cap of e.g. 4 door, after which the generator will
-- just stop placing them. That's useful for the 'block' citadels too").
-- A design may have fewer: one of Citadel.DOOR_CAPS (the owner, the same
-- day: "a toggle to cycle 1, 2, or 4 hangar doors max on a given citadel").
Citadel.DOORS = 4
Citadel.DOOR_CAPS = { 4, 2, 1 }
-- How wide the foot of a research station's observatory is, and of a
-- refinery's mining turret, as a share of the citadel's width (mine; the
-- observatory's base smaller, the owner, 2026-11-18, "so we can reuse it
-- on the blocky citadels too": its telescope keeps its size).
Citadel.OBSERVATORY = 0.035
Citadel.MINER = 0.04
-- (the telescope, as many times the dome as before its base was made smaller)
local SCOPE = 0.05 / 0.035

local function centroid(face: { vector }): vector
  local sum = v(0, 0, 0)
  for _, corner in face do
    sum += corner
  end
  return sum / #face
end

-- The way out of a face of a solid.
local function outward(face: { vector }, middle: vector): vector
  local n = vector.normalize(vector.cross(face[2] - face[1], face[3] - face[1]))
  return if vector.dot(n, centroid(face) - middle) < 0 then -n else n
end

-- How far the middle of a face is from the nearest of its edges.
local function inradius(face: { vector }): number
  local c = centroid(face)
  local least = math.huge
  for index, a in face do
    local b = face[index % #face + 1]
    local along = b - a
    least = math.min(least, vector.magnitude(vector.cross(along, c - a)) / math.max(1e-9, vector.magnitude(along)))
  end
  return least
end

-- Whether a point in a face's plane is inside it ('n' its way out).
local function onFace(face: { vector }, n: vector, p: vector): boolean
  local sign = 0
  for index, a in face do
    local b = face[index % #face + 1]
    local side = vector.dot(vector.cross(b - a, p - a), n)
    if math.abs(side) > 1e-7 then
      local now = if side > 0 then 1 else -1
      if sign ~= 0 and now ~= sign then
        return false
      end
      sign = now
    end
  end
  return true
end

-- Whether two shapes on the same face overlap (a corner or the middle of
-- either inside the other).
local function overlap(a: { vector }, b: { vector }, n: vector): boolean
  for _, p in a do
    if onFace(b, n, p) then
      return true
    end
  end
  for _, p in b do
    if onFace(a, n, p) then
      return true
    end
  end
  return onFace(b, n, centroid(a)) or onFace(a, n, centroid(b))
end

-- A face's key: where its middle is, to a thousandth (its mirror images have their own).
local function keyOf(face: { vector }): string
  local c = centroid(face)
  return `{math.floor(c.x * 1000 + 0.5)},{math.floor(c.y * 1000 + 0.5)},{math.floor(c.z * 1000 + 0.5)}`
end

-- A face's widest edge: the most level of its edges, the longest of those
-- (a pyramid's foot, a stone's girdle). Its index (the edge from that
-- corner to the next).
local function levelEdge(face: { vector }): number
  local wide, at, level = 0, 1, math.huge
  for index, a in face do
    local edge = face[index % #face + 1] - a
    local length = vector.magnitude(edge)
    local tilt = math.abs(edge.y) / math.max(1e-9, length)
    if tilt < level - 0.05 or (math.abs(tilt - level) <= 0.05 and length > wide) then
      wide, at, level = length, index, math.min(level, tilt)
    end
  end
  return at
end

-- A door in a facet (the owner's drawing): the facet brought in from its
-- edges by 'margin' (of its size), and cut to a band beside its widest
-- edge, from 'near' to 'far' of the way across it. Nil where there is no
-- room for one.
local function doorIn(face: { vector }, margin: number, near: number, far: number): { vector }?
  if #face ~= 3 and #face ~= 4 then
    return nil
  end
  local at = levelEdge(face)
  local wide = vector.magnitude(face[at % #face + 1] - face[at])
  local function corner(k: number): vector
    return face[(at - 1 + k) % #face + 1]
  end
  local A, B = corner(0), corner(1)
  local C = corner(2)
  local D = if #face == 4 then corner(3) else C
  -- (in from its edges: toward its incentre, a triangle's; a four-sided one's middle)
  local middle: vector
  if #face == 3 then
    local a, b, c = vector.magnitude(B - C), vector.magnitude(C - A), vector.magnitude(A - B)
    middle = (A * a + B * b + C * c) / (a + b + c)
  else
    middle = centroid(face)
  end
  local r = inradius(face)
  local k = 1 - margin * wide / math.max(1e-9, r)
  if k <= 0.2 then
    return nil
  end
  local function pull(p: vector): vector
    return middle + (p - middle) * k
  end
  A, B, C, D = pull(A), pull(B), pull(C), pull(D)
  local function left(f: number): vector
    return A + (D - A) * f
  end
  local function right(f: number): vector
    return B + (C - B) * f
  end
  return { left(near), right(near), right(far), left(far) }
end

-- A citadel grown from a seed at a size (1 to 5), in a style
-- (Citadel.STYLES; blocks, if not said), in the hull generator's units.
-- ('kind': the citadel's kind, Structures.CITADEL_KINDS, for what only some
-- kinds have on them: a research station's observatory, a refinery's
-- mining turret.)
function Citadel.Shape(seed: number, size: number, asym: boolean?, style: string?, doors: number?, kind: string?): Shape
  local cap = doors or Citadel.DOORS
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
  local unit = 0.9 + 0.3 * size

  -- The faceted styles: a pyramid's and a stone's, and what grows off them.
  -- (In the hull generator's units; each piece a solid in flat plate.)
  local keepClear: { vector } = {}
  -- (what pieces must keep out of beside the solids and the blocks: a ring
  -- standing on a deck, by its box)
  local obstacles: { Solid } = {}
  local mouthsMade: { Mouth } = {}
  -- (the mirror images a piece has: none for one grown asymmetrical, else
  -- the eight of a square, which a pyramid and a stone have)
  local images: { (vector) -> vector } = { function(p: vector): vector
    return p
  end }
  if not asym then
    for _, way in { { 1, 1, false }, { -1, 1, false }, { 1, -1, false }, { -1, -1, false }, { 1, 1, true }, { -1, 1, true },
      { 1, -1, true }, { -1, -1, true } } :: { { any } } do
      local sx, sz, swap = way[1] :: number, way[2] :: number, way[3] :: boolean
      if sx ~= 1 or sz ~= 1 or swap then
        table.insert(images, function(p: vector): vector
          return if swap then v(p.z * sx, p.y, p.x * sz) else v(p.x * sx, p.y, p.z * sz)
        end)
      end
    end
  end
  local function moved(faces: { { vector } }, image: (vector) -> vector): { { vector } }
    local out: { { vector } } = {}
    for _, face in faces do
      local f: { vector } = {}
      for _, corner in face do
        table.insert(f, image(corner))
      end
      table.insert(out, f)
    end
    return out
  end
  local function solidOf(faces: { { vector } }, part: number, closed: { [number]: boolean }?): Solid
    local middle, count = v(0, 0, 0), 0
    for _, face in faces do
      for _, corner in face do
        middle += corner
        count += 1
      end
    end
    return { faces = faces, part = part, middle = middle / math.max(1, count), closed = closed }
  end
  -- Whether a solid would go in clear of all there is: none of its
  -- corners in anything, nothing's corners in it, nothing kept clear in
  -- it, and within reach.
  local function fits(candidate: Solid, also: { Solid }): boolean
    for _, face in candidate.faces do
      for _, corner in face do
        if vector.magnitude(corner) > reach then
          return false
        end
        for _, block in blocks do
          local d = corner - block.center
          if math.abs(d.x) < block.half.x - 1e-4 and math.abs(d.y) < block.half.y - 1e-4 and math.abs(d.z) < block.half.z - 1e-4 then
            return false
          end
        end
      end
    end
    -- (and nothing it cuts into: not a corner's matter, two pieces on
    -- facets side by side can cross with no corner of either in the other)
    for _, block in blocks do
      if cut(candidate, boxSolid(block.center, block.half), 2e-3 * unit) then
        return false
      end
    end
    for _, list in { solids, also, obstacles } do
      for _, other in list do
        if cut(candidate, other, 2e-3 * unit) then
          return false
        end
      end
    end
    for _, block in blocks do
      if within(candidate, block.center) then
        return false
      end
    end
    for _, p in keepClear do
      if within(candidate, p) then
        return false
      end
    end
    return true
  end

  -- The shapes a piece may be, in a frame of its own, the face it is laid
  -- on by first ('flat'), the others ('side').
  type Local = { faces: { { vector } }, flat: number, sides: { number }, part: number }
  local function pyramidLocal(h: number): Local
    local base = { v(1, 0, 1), v(-1, 0, 1), v(-1, 0, -1), v(1, 0, -1) }
    local apex = v(0, h, 0)
    local faces: { { vector } } = { base }
    for index = 1, 4 do
      table.insert(faces, { base[index], base[index % 4 + 1], apex })
    end
    return { faces = faces, flat = 1, sides = { 2, 3, 4, 5 }, part = PLATING }
  end
  -- (two pyramids joined at their bases: the owner, 2026-11-18, "a diamond
  -- is/can be 2 pyramids attached at their bases")
  local function bipyramidLocal(up: number, down: number): Local
    local girdle = { v(1, 0, 1), v(-1, 0, 1), v(-1, 0, -1), v(1, 0, -1) }
    local top, bottom = v(0, up, 0), v(0, -down, 0)
    local faces: { { vector } } = {}
    local sides: { number } = {}
    for index = 1, 4 do
      local after = index % 4 + 1
      table.insert(faces, { girdle[index], girdle[after], top })
      table.insert(sides, #faces)
      table.insert(faces, { girdle[after], girdle[index], bottom })
      table.insert(sides, #faces)
    end
    return { faces = faces, flat = 1, sides = sides, part = PLATING }
  end
  local function stoneLocal(n: number, T: number, Hc: number, Hp: number): Local
    local function ring(r: number, y: number): { vector }
      local corners: { vector } = {}
      local out = r / math.cos(math.pi / n)
      for index = 0, n - 1 do
        local a = math.pi / n + index * 2 * math.pi / n
        table.insert(corners, v(math.cos(a) * out, y, math.sin(a) * out))
      end
      return corners
    end
    local top, girdle = ring(T, Hc), ring(1, 0)
    local culet = v(0, -Hp, 0)
    local faces: { { vector } } = { top }
    local sides: { number } = {}
    for index = 1, n do
      local after = index % n + 1
      table.insert(faces, { top[index], top[after], girdle[after], girdle[index] })
      table.insert(sides, #faces)
      table.insert(faces, { girdle[index], girdle[after], culet })
      table.insert(sides, #faces)
    end
    -- (stood on its table, its point out: the table is the face it is laid on)
    return { faces = faces, flat = 1, sides = sides, part = PLATING }
  end
  -- A module: a box or a drum, its back face the one laid on the facet.
  local function boxLocal(a: number, c: number, t: number, part: number): Local
    local corners = { v(a, 0, c), v(-a, 0, c), v(-a, 0, -c), v(a, 0, -c) }
    local tops = { v(a, t, c), v(-a, t, c), v(-a, t, -c), v(a, t, -c) }
    local faces: { { vector } } = { corners, tops }
    for index = 1, 4 do
      local after = index % 4 + 1
      table.insert(faces, { corners[index], corners[after], tops[after], tops[index] })
    end
    return { faces = faces, flat = 1, sides = {}, part = part }
  end
  local function drumLocal(r: number, t: number, part: number): Local
    local low, high = {}, {}
    for index = 0, 7 do
      local a = index * math.pi / 4 + math.pi / 8
      table.insert(low, v(math.cos(a) * r, 0, math.sin(a) * r))
      table.insert(high, v(math.cos(a) * r, t, math.sin(a) * r))
    end
    local faces: { { vector } } = { low, high }
    for index = 1, 8 do
      local after = index % 8 + 1
      table.insert(faces, { low[index], low[after], high[after], high[index] })
    end
    return { faces = faces, flat = 1, sides = {}, part = part }
  end

  -- Lay a shape on a facet: its face 'by' flush on the facet, at a point
  -- of it, turned to line up with the facet's longest edge, at 'scale'.
  -- Its faces, where they go.
  -- (the frame of a shape's face: its middle, the way out of it, and two
    -- ways along it)
  local function frameOf(shape: Local, by: number): (vector, vector, vector, vector)
    local face = shape.faces[by]
    local localMiddle = v(0, 0, 0)
    local count = 0
    for _, f in shape.faces do
      for _, corner in f do
        localMiddle += corner
        count += 1
      end
    end
    localMiddle /= count
    local nf = outward(face, localMiddle)
    local uf = vector.normalize(face[2] - face[1])
    return centroid(face), nf, uf, vector.cross(nf, uf)
  end
  local function laid(shape: Local, by: number, scale: number, at: vector, n: vector, along: vector): { { vector } }
    local cf, nf, uf, wf = frameOf(shape, by)
    local nt = -n
    local ut = along
    local wt = vector.cross(nt, ut)
    local out: { { vector } } = {}
    for _, f in shape.faces do
      local placed: { vector } = {}
      for _, corner in f do
        local q = (corner - cf) * scale
        table.insert(placed, at + ut * vector.dot(q, uf) + wt * vector.dot(q, wf) + nt * vector.dot(q, nf))
      end
      table.insert(out, placed)
    end
    return out
  end

  -- The open facets there are: each solid's, but those lying against
  -- something, the biggest first.
  type Facet = { solid: Solid, index: number, face: { vector }, n: vector, key: string, room: number }
  local function facets(): { Facet }
    local found: { Facet } = {}
    for _, each in solids do
      for index, face in each.faces do
        if not (each.closed and each.closed[index]) then
          table.insert(found, { solid = each, index = index, face = face, n = outward(face, each.middle), key = keyOf(face),
            room = inradius(face) })
        end
      end
    end
    table.sort(found, function(a: Facet, b: Facet): boolean
      if a.room ~= b.room then
        return a.room > b.room
      end
      return a.key < b.key
    end)
    return found
  end
  -- What lies on each facet already (doors, and what was laid on it).
  local onIt: { [string]: { { vector } } } = {}
  local function free(key: string, shape: { vector }, n: vector): boolean
    local there: { { vector } } = onIt[key] or {}
    for _, other in there do
      if overlap(other, shape, n) then
        return false
      end
    end
    return true
  end
  local function note(key: string, shape: { vector })
    local list = onIt[key]
    if list == nil then
      list = {}
      onIt[key] = list
    end
    table.insert(list, shape)
  end

  -- How big a shape's face can be laid on a facet and still be wholly on
  -- it, lined up with the facet's widest edge, either way round, and
  -- anywhere from that edge to across from it: the scale, where, and which
  -- way along (the owner, 2026-11-18: "size their attached pieces to fit
  -- the width of the facet they're attaching to").
  local function fill(shape: Local, by: number, facet: Facet): (number, vector, vector)
    local face = shape.faces[by]
    local cf, _, uf, wf = frameOf(shape, by)
    local coords: { vector } = {}
    local reachOf = 0
    for _, corner in face do
      local q = corner - cf
      table.insert(coords, v(vector.dot(q, uf), vector.dot(q, wf), 0))
      reachOf = math.max(reachOf, vector.magnitude(q))
    end
    local F = facet.face
    local i = levelEdge(F)
    local A, B = F[i], F[i % #F + 1]
    local O = if #F == 3 then F[(i + 1) % 3 + 1] else (F[(i + 1) % #F + 1] + F[(i + 2) % #F + 1]) * 0.5
    local foot = (A + B) * 0.5
    local along = vector.normalize(B - A)
    local size = 0
    for index, a in F do
      size = math.max(size, vector.magnitude(F[index % #F + 1] - a))
    end
    local best, bestAt, bestAlong = 0, centroid(F), along
    for _, sign in { 1, -1 } do
      local ut = along * sign
      local wt = vector.cross(-facet.n, ut)
      for step = 1, 15 do
        local at = foot + (O - foot) * (step / 16)
        local lo, hi = 0, 2 * size / math.max(1e-9, reachOf)
        for _ = 1, 14 do
          local mid = (lo + hi) * 0.5
          local inside = true
          for _, c in coords do
            if not onFace(F, facet.n, at + ut * (c.x * mid) + wt * (c.y * mid)) then
              inside = false
              break
            end
          end
          if inside then
            lo = mid
          else
            hi = mid
          end
        end
        if lo > best then
          best, bestAt, bestAlong = lo, at, ut
        end
      end
    end
    return best * 0.94, bestAt, bestAlong
  end

  -- Lay a piece on a facet, with its mirror images: true if it went in.
  -- ('filling': as big as the facet holds, Citadel's fill; else somewhere
  -- on it, as big as the room round that spot lets it be.)
  local function lay(shape: Local, by: number, facet: Facet, part: number, smallest: number, biggest: number, filling: boolean?): boolean
    local face = shape.faces[by]
    local cf = centroid(face)
    local reachOf = 0
    for _, corner in face do
      reachOf = math.max(reachOf, vector.magnitude(corner - cf))
    end
    -- (somewhere on the facet, wholly on it: a point of it, and as big as
    -- the room round that point lets it be)
    local longest, along = 0, v(1, 0, 0)
    for index, a in facet.face do
      local b = facet.face[index % #facet.face + 1]
      if vector.magnitude(b - a) > longest then
        longest, along = vector.magnitude(b - a), vector.normalize(b - a)
      end
    end
    local corners = facet.face
    local fan = rng:Int(#corners - 2) + 2
    local r1, r2 = rng:Float(), rng:Float()
    if r1 + r2 > 1 then
      r1, r2 = 1 - r1, 1 - r2
    end
    local at = corners[1] + (corners[fan] - corners[1]) * r1 + (corners[fan + 1] - corners[1]) * r2
    -- (the middle, now and then: the most room there is)
    if rng:Float() < 0.6 then
      at = centroid(corners)
    end
    local room = math.huge
    for index, a in corners do
      local b = corners[index % #corners + 1]
      room = math.min(room, vector.magnitude(vector.cross(b - a, at - a)) / math.max(1e-9, vector.magnitude(b - a)))
    end
    local scale = math.min(room * 0.9 / reachOf, biggest) * rng:Float(0.75, 1.0)
    if filling then
      scale, at, along = fill(shape, by, facet)
    end
    if scale * reachOf < smallest then
      return false
    end
    local faces = laid(shape, by, scale, at, facet.n, along)
    local footprint = faces[by]
    -- (and its images, all of them clear, or none goes in)
    local group: { Solid } = {}
    local prints: { { key: string, shape: { vector }, n: vector } } = {}
    for _, image in images do
      local f = moved(faces, image)
      local candidate = solidOf(f, part, { [by] = true })
      local twin = false
      for _, other in group do
        if vector.magnitude(other.middle - candidate.middle) < 1e-3 then
          twin = true
        end
      end
      if not twin then
        local print = f[by]
        local n = image(facet.n + facet.face[1]) - image(facet.face[1])
        local key = keyOf(moved({ facet.face }, image)[1])
        if not free(key, print, n) or not fits(candidate, group) then
          return false
        end
        table.insert(group, candidate)
        table.insert(prints, { key = key, shape = print, n = n })
      end
    end
    for _, each in group do
      each.role = if filling then "piece" else "module"
      table.insert(solids, each)
    end
    for _, each in prints do
      note(each.key, each.shape)
    end
    local _ = footprint
    return true
  end

  -- Doors in the facets that have room, as many as are wanted: each with
  -- its images, where the way out of it is clear; and never more than one
  -- on a piece (the owner, 2026-11-18: "each pyramid should only ever have
  -- at most 1 hangar door on it, never multiple facets with doors each").
  -- Doors have no mirror images: each is where it is, whatever the rest
  -- of the citadel is (the owner, the same day: "hangar door placement
  -- should be excluded from the symmetricality rules").
  local wantedDoors = math.min(cap, (1 + size) * (if asym then 1 else 2))
  local doored: { [Solid]: boolean } = {}
  local function placeDoors()
    local all = facets()
    local pieceOf: { [string]: Solid } = {}
    for _, facet in all do
      pieceOf[facet.key] = facet.solid
    end
    for _, facet in all do
      if #mouthsMade >= wantedDoors then
        return
      end
      -- (not in a facet that looks straight up or straight down)
      if math.abs(facet.n.y) < 0.8 and facet.room > 0.14 and not doored[facet.solid] then
        local door = doorIn(facet.face, 0.1, 0.08, 0.5)
        if door then
          local made: { Mouth } = {}
          local keys: { string } = {}
          local pieces: { Solid } = {}
          local ok = true
          for _, image in { images[1] } do
            local corners = moved({ door }, image)[1]
            local n = image(facet.n + facet.face[1]) - image(facet.face[1])
            local key = keyOf(moved({ facet.face }, image)[1])
            local middle = centroid(corners)
            local twin = false
            for _, other in made do
              if vector.magnitude(other.at - (middle + n * 0.02)) < 1e-3 then
                twin = true
              end
            end
            if not twin then
              if not free(key, corners, n) then
                ok = false
              end
              -- (one door a piece: not on one that has one, nor twice on one)
              local piece = pieceOf[key]
              if piece == nil or doored[piece] or table.find(pieces, piece) then
                ok = false
              else
                table.insert(pieces, piece)
              end
              for index, other in made do
                if keys[index] == key and overlap(other.corners :: { vector }, corners, n) then
                  ok = false
                end
              end
              for _, d in { 0.05, 0.4, 0.9 } do
                local p = middle + n * d * unit
                for _, each in solids do
                  if within(each, p) then
                    ok = false
                  end
                end
              end
              -- (half across and half up, for what keeps off it)
              local wide = vector.magnitude(corners[2] - corners[1]) * 0.5
              local high = vector.magnitude((corners[1] + corners[2]) * 0.5 - (corners[3] + corners[4]) * 0.5) * 0.5
              table.insert(made, { at = middle + n * 0.02, n = n, wide = wide, high = high, corners = corners })
              table.insert(keys, key)
            end
          end
          if ok then
            for _, piece in pieces do
              doored[piece] = true
            end
            for index, mouth in made do
              table.insert(mouthsMade, mouth)
              table.insert(keepClear, mouth.at + mouth.n * 0.3 * unit)
              table.insert(keepClear, mouth.at + mouth.n * 0.8 * unit)
              note(keys[index], mouth.corners :: { vector })
            end
          end
        end
      end
    end
  end

  -- Pieces like the first, off its facets and off one another's: so many
  -- a size, twice as many a size up, laid flush by a facet or stood on
  -- the base or the table, as the seed has it.
  local function grow(make: () -> Local, flushOnly: boolean?)
    -- (as far out as half as far again as the first piece goes)
    local far = 0
    for _, face in solids[1].faces do
      for _, corner in face do
        far = math.max(far, vector.magnitude(corner))
      end
    end
    reach = math.max(reach, far * 1.5)
    -- (0: stood on their bases, 1: laid by a facet, 2: either; a diamond's
    -- always by a facet, the owner's of 2026-11-18: "facet-to-facet,
    -- rather than top-to-facet")
    local manner = if flushOnly then 1 else rng:Int(3)
    local wanted = Citadel.PIECES * 2 ^ (size - 1)
    local start = #solids
    for _ = 1, wanted * 40 do
      if #solids - start >= wanted then
        break
      end
      local open = facets()
      if #open == 0 then
        break
      end
      -- (any facet with room for one, alike: the biggest, a pyramid's foot,
      -- would have them all, under it)
      local roomy: { Facet } = {}
      for _, facet in open do
        if facet.room > 0.3 * unit then
          table.insert(roomy, facet)
        end
      end
      local pick = if #roomy > 0 then roomy[rng:Int(#roomy) + 1] else open[1]
      local shape = make()
      local flush = manner == 1 or (manner == 2 and rng:Float() < 0.5)
      local by = if flush then shape.sides[rng:Int(#shape.sides) + 1] else shape.flat
      lay(shape, by, pick, PLATING, 0.12 * unit, math.huge, true)
    end
  end

  -- Modules flush on the facets: boxes, flat or standing, and drums.
  local function modules()
    local wanted = Citadel.MODULES * size
    local laidOn = 0
    for _ = 1, wanted * 10 do
      if laidOn >= wanted then
        break
      end
      local open = facets()
      local pick = open[rng:Int(#open) + 1]
      if pick and math.abs(pick.n.y) < 0.95 then
        local kind = rng:Int(3)
        local shape = if kind == 0 then boxLocal(1, rng:Float(0.4, 1.0), rng:Float(0.12, 0.3), PATCH)
          elseif kind == 1 then boxLocal(rng:Float(0.4, 0.7), rng:Float(0.4, 0.7), rng:Float(0.6, 1.4), PLATING)
          else drumLocal(1, rng:Float(0.3, 0.9), FRAME)
        if lay(shape, 1, pick, shape.part, 0.06 * unit, 0.45 * unit) then
          laidOn += 1
        end
      end
    end
  end

  -- Masts at the points (the owner, 2026-11-18: "keep them, but ... give
  -- them some more 'design' character ... and 'utility', even if it's
  -- alien, unknowable utility"; and their picks: a faceted spike, a
  -- segmented spire or forked prongs; a beam of light out of the tip, or
  -- a crimson ball of energy held in the prongs, or neither). One shape
  -- and one use a citadel, for all its masts, by the seed. Their room is
  -- kept clear before anything grows (Citadel's planMast), and they are
  -- built last (buildMasts).
  local beams: { Beam } = {}
  local balls: { Ball } = {}
  local mastShape, mastUse, mastLength = -1, 0, 0
  local mastPlans: { { at: vector, d: vector } } = {}
  local function planMast(at: vector, d: vector)
    if mastShape < 0 then
      mastUse = rng:Int(3) -- 0: none, 1: a beam, 2: a harness
      mastShape = if mastUse == 2 then 2 else rng:Int(3) -- 0: a spike, 1: a spire, 2: prongs
      mastLength = unit * rng:Float(1.4, 2.3)
    end
    table.insert(mastPlans, { at = at, d = d })
    -- (and the ball a harness holds over the spikes, with its crackles)
    local over = if mastUse == 2 then 0.6 * unit else 0
    table.insert(obstacles, boxSolid(at + d * ((mastLength + over) * 0.5), v(0.5 * unit, (mastLength + over) * 0.5 + 0.2 * unit, 0.5 * unit)))
  end
  -- A rod from a to b, square across, w0 to a side at a and w1 at b (a
  -- point, if 0); 'flat' times as thick one way as the other, that way
  -- across 'across' (fins).
  local function rod(a: vector, b: vector, w0: number, w1: number, part: number, flat: number?, across: vector?)
    local dir = vector.normalize(b - a)
    local helper = across or (if math.abs(dir.y) < 0.9 then v(0, 1, 0) else v(1, 0, 0))
    local u = vector.normalize(vector.cross(dir, helper))
    local w = vector.cross(dir, u)
    local f = flat or 1
    local function square(c: vector, r: number): { vector }
      return { c + u * r + w * r * f, c - u * r + w * r * f, c - u * r - w * r * f, c + u * r - w * r * f }
    end
    local A = square(a, w0)
    local faces: { { vector } } = { A }
    if w1 <= 1e-6 then
      for index = 1, 4 do
        table.insert(faces, { A[index], A[index % 4 + 1], b })
      end
    else
      local B = square(b, w1)
      table.insert(faces, B)
      for index = 1, 4 do
        local after = index % 4 + 1
        table.insert(faces, { A[index], A[after], B[after], B[index] })
      end
    end
    local made = solidOf(faces, part)
    made.role = "mast"
    table.insert(solids, made)
  end
  -- The ways out from a mast, round it: 'count' of them, a turn apart.
  local function around(d: vector, count: number, turn: number): { vector }
    local a = vector.normalize(vector.cross(d, if math.abs(d.y) < 0.9 then v(0, 1, 0) else v(1, 0, 0)))
    local b = vector.cross(d, a)
    local out: { vector } = {}
    for index = 0, count - 1 do
      local t = turn + index * 2 * math.pi / count
      table.insert(out, a * math.cos(t) + b * math.sin(t))
    end
    return out
  end
  -- (each grows out of its point: its foot sunk well into the point, and
  -- narrower than the point is there, so that the point's faces close
  -- round it, as the first masts did; the owner, 2026-11-18: "now they
  -- sit on top of the pyramid point, instead of 'growing' out of it")
  local SUNK = 0.45
  local function buildMasts()
    for _, plan in mastPlans do
      local at, d, L = plan.at, plan.d, mastLength
      local tip = at + d * L
      local foot = at - d * SUNK * unit
      if mastShape == 0 then
        -- A faceted spike, fins now and then.
        rod(foot, tip, 0.13 * unit, 0, PLATING)
        if rng:Float() < 0.6 then
          for _, r in around(d, 4, math.pi / 4) do
            rod(at + d * 0.1 * unit + r * 0.12 * unit, at + d * L * 0.5 + r * 0.03 * unit, 0.13 * unit, 0.01 * unit, FRAME, 0.12,
              vector.cross(r, d))
          end
        end
      elseif mastShape == 1 then
        -- A spire in sections, narrowing, collars between, lit bands, a few antennas.
        local count = 3 + (#mastPlans % 2) + (math.floor(L / unit) % 2)
        local base = foot
        for index = 1, count do
          local w = 0.13 * unit + (0.05 * unit - 0.13 * unit) * (index - 1) / math.max(1, count - 1)
          local top = at + d * (L * index / count)
          rod(base, top, w, w * 0.88, PLATING)
          if index < count then
            rod(top - d * 0.03 * unit, top + d * 0.03 * unit, w * 1.35, w * 1.35, PATCH)
            if index % 2 == 1 then
              for _, r in around(d, 2, index * 0.9) do
                rod(top + r * w * 1.2, top + r * (w * 1.2 + 0.32 * unit) + d * 0.1 * unit, 0.014 * unit, 0.007 * unit, FRAME)
              end
            end
          end
          if index % 2 == 0 then
            local mid = (base + top) * 0.5
            rod(mid - d * 0.02 * unit, mid + d * 0.02 * unit, w * 0.97, w * 0.97, GLOW)
          end
          base = top
        end
        rod(tip, tip + d * 0.35 * unit, 0.05 * unit, 0, PLATING)
        tip += d * 0.35 * unit
      else
        -- A stem out of the point, and spikes out of its head, out and up: no cage, only enough to say a harness (the
        -- owner, 2026-11-18: "just 4 spikes out and up, that imply the
        -- harness").
        -- (no collar between: the spikes grow straight out of the stem's
        -- head, their feet a little way into it)
        local head = at + d * (L * 0.3)
        rod(foot, head, 0.12 * unit, 0.09 * unit, PLATING)
        for _, r in around(d, if mastUse == 2 then 4 else 3, math.pi / 4) do
          rod(head - d * 0.06 * unit + r * 0.04 * unit, head + d * (L * 0.6) + r * 0.42 * unit, 0.05 * unit, 0, PLATING)
        end
        tip = head + d * 0.06 * unit
      end
      if mastUse == 1 then
        table.insert(beams, { from = tip, to = tip + d * 14 * unit, width = 0.22 * unit })
      elseif mastUse == 2 then
        -- (above the spikes' tips, its crackles clear of them: the owner,
        -- 2026-11-18, "a little further 'up', so its energy isn't
        -- intersecting the spikes")
        table.insert(balls, { at = at + d * (L * 0.9 + 0.28 * unit), radius = 0.26 * unit })
      end
    end
  end

  -- The kind's own (a research station's observatory, a refinery's mining
  -- turret), on a faceted citadel: placed once the pieces and the doors
  -- are, before the modules, in the middle of the best open facet of the
  -- body or a piece (for an observatory, the one that looks most up and
  -- out; for a mining turret, the one that looks most out and least up or
  -- down) that holds at least half of it, and the room over it kept clear
  -- of the modules. (Placed with the hardpoints, it found no room: the
  -- modules had had the facets. Placed before the pieces, it barred them:
  -- a piece and its mirror images go in together or not at all.) Given to
  -- the hardpoints below.
  local reserved: Mount? = nil
  local function reserveSpecial()
    local special = if kind == "research" then "observatory" elseif kind == "refinery" then "miner" else nil
    local body = solids[1]
    -- (where the deck has it already, nothing)
    if special == nil or body == nil or reserved ~= nil then
      return
    end
    local far = 0
    for _, face in body.faces do
      for _, corner in face do
        far = math.max(far, vector.magnitude(corner - body.middle))
      end
    end
    local want = far * 2 * (if special == "observatory" then Citadel.OBSERVATORY else Citadel.MINER)
    local best: Facet? = nil
    local bestScore = -math.huge
    for _, facet in facets() do
      local role = facet.solid.role
      local at = centroid(facet.face)
      local square = { at + v(1, 0, 0) * 1e-3 }
      if (role == nil or role == "piece") and facet.room * 0.6 >= want * 0.5 and free(facet.key, square, facet.n) then
        local out = vector.dot(facet.n, vector.normalize(at - body.middle))
        local score = if special == "observatory" then out + facet.n.y else out - math.abs(facet.n.y)
        if score > bestScore then
          best, bestScore = facet, score
        end
      end
    end
    local facet = best
    if facet == nil then
      return
    end
    local r = math.min(want, facet.room * 0.6)
    local at = centroid(facet.face)
    local i = levelEdge(facet.face)
    local along = vector.normalize(facet.face[i % #facet.face + 1] - facet.face[i])
    local side = vector.cross(facet.n, along)
    note(facet.key, { at + along * r + side * r, at - along * r + side * r, at - along * r - side * r, at + along * r - side * r })
    for _, up in { 0.5, 1.2, 2.2, 3.2 } do
      table.insert(keepClear, at + facet.n * r * up)
    end
    reserved = { at = at, n = facet.n, fore = along, size = 0, kind = special, radius = r, twin = 0 }
  end

  -- A deck: the flat face of a pyramid's base or a stone's table, level,
  -- its middle at 'c', a square of 'half' on it clear, facing 'up' (1
  -- up, -1 down). Nothing grows on it: on it stands, by the seed, a
  -- facility or a monument (the owner, 2026-11-18: "the base could be
  -- facing 'upwards', with a large facility or even statue erected on
  -- it". Weapons for show were tried there and taken off again: "remove
  -- the non-functional 'weapons'").
  local function deck(c: vector, half: number, up: number)
    local slab = 0.05 * unit
    add(v(c.x, c.y + up * slab, c.z), v(half * 0.82, slab, half * 0.82), PATCH)
    local top = c.y + up * 2 * slab
    -- (a research station's observatory, or a refinery's mining turret,
    -- full size, where the deck has one: the owner, 2026-11-18, "keeping
    -- them full-size, and placing them on the base areas")
    local special = if kind == "research" then "observatory" elseif kind == "refinery" then "miner" else nil
    local body = solids[1]
    if special and body then
      local far = 0
      for _, face in body.faces do
        for _, corner in face do
          far = math.max(far, vector.magnitude(corner - body.middle))
        end
      end
      local r = math.min(far * 2 * (if special == "observatory" then Citadel.OBSERVATORY else Citadel.MINER), half * 0.7)
      local at = v(c.x, top, c.z)
      local n = v(0, up, 0)
      reserved = { at = at, n = n, fore = v(1, 0, 0), size = 0, kind = special, radius = r, twin = 0 }
      for _, high in { 0.5, 1.2, 2.2, 3.2 } do
        table.insert(keepClear, at + n * r * high)
      end
      return
    end
    local feature = rng:Int(2)
    if feature == 0 then
      -- A facility: blocks grown off one another, standing on the deck.
      local a, h = half * rng:Float(0.28, 0.42), half * rng:Float(0.25, 0.5)
      local list: { Block } = { { center = v(c.x, top + up * h, c.z), half = v(a, h, a), part = PLATING } }
      add(list[1].center, list[1].half, PLATING)
      local ways = { v(1, 0, 0), v(-1, 0, 0), v(0, 0, 1), v(0, 0, -1), v(0, up, 0) }
      for _ = 1, 30 do
        if #list >= 4 + 2 * size then
          break
        end
        local from = list[rng:Int(#list) + 1]
        local way = ways[rng:Int(#ways) + 1]
        local scale = math.max(from.half.x, from.half.y, from.half.z) * rng:Float(0.35, 0.8)
        local pick = rng:Int(4)
        local own = if pick == 0 then v(1, 1, 1) * scale * rng:Float(0.6, 0.9)
          elseif pick == 1 then v(scale * rng:Float(1.0, 1.5), scale * rng:Float(0.2, 0.35), scale * rng:Float(1.0, 1.5))
          elseif pick == 2 then v(scale * rng:Float(0.35, 0.6), scale * rng:Float(1.1, 1.8), scale * rng:Float(0.35, 0.6))
          else v(scale * rng:Float(0.15, 0.3), scale * rng:Float(1.4, 2.4), scale * rng:Float(0.15, 0.3))
        local outFrom = math.abs(vector.dot(from.half, way))
        local outOwn = math.abs(vector.dot(own, way))
        local across = v(1, 1, 1) - v(math.abs(way.x), math.abs(way.y), math.abs(way.z))
        local slide = v(rng:Float(-0.5, 0.5), 0, rng:Float(-0.5, 0.5)) * from.half * across
        local at = from.center + way * (outFrom + outOwn * rng:Float(-0.5, 0.3)) + slide
        -- (on the deck, within it, and not through it)
        if way.y == 0 then
          at = v(at.x, top + up * own.y, at.z)
        end
        local onDeck = math.abs(at.x - c.x) + own.x <= half * 0.8 and math.abs(at.z - c.z) + own.z <= half * 0.8
        if onDeck and (at.y - top) * up - own.y >= -1e-6 then
          local made: Block = { center = at, half = own, part = if pick == 1 then PATCH else PLATING }
          table.insert(list, made)
          add(at, own, made.part)
        end
      end
    elseif feature == 1 then
      -- A monument: an obelisk, a ring standing on edge, or a spire.
      local which = rng:Int(3)
      if which == 0 then
        local s = half * rng:Float(0.09, 0.14)
        local high = half * rng:Float(0.7, 1.2)
        add(v(c.x, top + up * s * 0.5, c.z), v(s * 2.2, s * 0.5, s * 2.2), PATCH)
        local foot = top + up * s
        add(v(c.x, foot + up * high, c.z), v(s, high, s), PLATING)
        local tip = foot + up * 2 * high
        local cap = { v(c.x + s, tip, c.z + s), v(c.x - s, tip, c.z + s), v(c.x - s, tip, c.z - s), v(c.x + s, tip, c.z - s) }
        local apex = v(c.x, tip + up * s * 2.6, c.z)
        local faces: { { vector } } = { cap }
        for index = 1, 4 do
          table.insert(faces, { cap[index], cap[index % 4 + 1], apex })
        end
        local monument = solidOf(faces, PATCH, { [1] = true })
        monument.role = "deck"
        table.insert(solids, monument)
      elseif which == 1 then
        local thick = unit * rng:Float(0.08, 0.12)
        local radius = half * rng:Float(0.45, 0.65)
        local middle = v(c.x, top + up * (radius + thick * 2.2), c.z)
        local facing = if rng:Float() < 0.5 then v(1, 0, 0) else v(0, 0, 1)
        table.insert(rings, { radius = radius, thick = thick, normal = facing, axis = v(0, 1, 0), rate = 0, phase = 0, center = middle })
        -- (cradled at its foot)
        local along = v(1, 1, 1) - v(math.abs(facing.x), 1, math.abs(facing.z))
        add(v(c.x, top + up * thick * 1.2, c.z) , v(1, 0, 1) * thick * 1.6 + along * radius * 0.25 + v(0, thick * 1.2, 0), PATCH)
        table.insert(obstacles, boxSolid(middle, v(1, 1, 1) * (radius + thick)))
      else
        local s = half * rng:Float(0.22, 0.32)
        local high = half * rng:Float(1.2, 2.0)
        local foot = { v(c.x + s, top, c.z + s), v(c.x - s, top, c.z + s), v(c.x - s, top, c.z - s), v(c.x + s, top, c.z - s) }
        local apex = v(c.x, top + up * high, c.z)
        local faces: { { vector } } = { foot }
        for index = 1, 4 do
          table.insert(faces, { foot[index], foot[index % 4 + 1], apex })
        end
        local monument = solidOf(faces, PLATING, { [1] = true })
        monument.role = "deck"
        table.insert(solids, monument)
      end
    end
  end

  if which == 2 then
    -- A pyramid, a mast at its point. (No plinth: it is in space.)
    local W = unit * rng:Float(2.0, 2.6)
    local H = W * rng:Float(1.0, 1.6)
    -- (point up, its deck under it; or turned over, its deck on top)
    local s = if rng:Float() < 0.5 then 1 else -1
    local y0 = -H * 0.38 * s
    local apex = v(0, y0 + H * s, 0)
    if asym then
      apex += v(rng:Float(-0.35, 0.35) * W, 0, rng:Float(-0.35, 0.35) * W)
    end
    local base = { v(W, y0, W), v(-W, y0, W), v(-W, y0, -W), v(W, y0, -W) }
    local faces: { { vector } } = { base }
    for index = 1, 4 do
      table.insert(faces, { base[index], base[index % 4 + 1], apex })
    end
    -- (its base is the deck: nothing grows on it)
    table.insert(solids, solidOf(faces, PLATING, { [1] = true }))
    planMast(apex, v(0, s, 0))
    deck(v(0, y0, 0), W * 0.95, -s)
    local tall = rng:Float(0.8, 1.6)
    grow(function(): Local
      return pyramidLocal(tall * rng:Float(0.8, 1.25))
    end)
    placeDoors()
    reserveSpecial()
    modules()
    buildMasts()

  elseif which == 3 and rng:Float() < 0.5 then
    -- Two pyramids joined at their bases (the owner, 2026-11-18: "a
    -- diamond is/can be 2 pyramids attached at their bases"); a mast at
    -- each point. What grows off it is the same, by a facet.
    local W = unit * rng:Float(2.0, 2.5)
    local up, down = W * rng:Float(0.9, 1.5), W * rng:Float(1.0, 1.8)
    local top, bottom = v(0, up, 0), v(0, -down, 0)
    if asym then
      top += v(rng:Float(-0.3, 0.3) * W, 0, rng:Float(-0.3, 0.3) * W)
      bottom += v(rng:Float(-0.35, 0.35) * W, 0, rng:Float(-0.35, 0.35) * W)
    end
    local girdle = { v(W, 0, W), v(-W, 0, W), v(-W, 0, -W), v(W, 0, -W) }
    local faces: { { vector } } = {}
    for index = 1, 4 do
      local after = index % 4 + 1
      table.insert(faces, { girdle[index], girdle[after], top })
      table.insert(faces, { girdle[after], girdle[index], bottom })
    end
    table.insert(solids, solidOf(faces, PLATING))
    planMast(top, v(0, 1, 0))
    planMast(bottom, v(0, -1, 0))
    local ratio = down / up
    grow(function(): Local
      local high = rng:Float(0.9, 1.5)
      return bipyramidLocal(high, high * ratio * rng:Float(0.85, 1.15))
    end, true)
    placeDoors()
    reserveSpecial()
    modules()
    buildMasts()

  elseif which == 3 then
    -- A cut stone: a flat table, a crown out to the girdle, and a deep
    -- point under it; masts at the table and the point.
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
    -- (its table is a deck, as a pyramid's base is: nothing grows on it)
    table.insert(solids, solidOf(faces, PLATING, { [1] = true }))
    deck(v(tableShift.x, Hc, tableShift.z), if n == 4 then T * 0.95 else T * 0.68, 1)
    planMast(culet, v(0, -1, 0))
    local round = if rng:Float() < 0.5 then n else 8
    grow(function(): Local
      return stoneLocal(round, rng:Float(0.4, 0.6), rng:Float(0.45, 0.7), rng:Float(1.1, 1.6))
    end, true)
    placeDoors()
    reserveSpecial()
    modules()
    buildMasts()

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
    local shapeOf = rng:Int(5)
    local half: vector
    local part = PLATING
    if shapeOf == 0 then
      -- a cube
      half = v(1, 1, 1) * scale * rng:Float(0.6, 0.9)
    elseif shapeOf == 1 then
      -- a slab, flat across the upright
      half = v(scale * rng:Float(1.0, 1.6), scale * rng:Float(0.18, 0.35), scale * rng:Float(1.0, 1.6))
      part = PATCH
    elseif shapeOf == 2 then
      -- a long beam out the way it grows
      local long = scale * rng:Float(1.4, 2.6)
      local thin = scale * rng:Float(0.15, 0.3)
      half = v(if way.x ~= 0 then long else thin, if way.y ~= 0 then long else thin, if way.z ~= 0 then long else thin)
      part = FRAME
    elseif shapeOf == 3 then
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
  -- with their blocks, and never more than Citadel.DOORS.
  local mouths: { Mouth } = table.clone(mouthsMade)
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
  local wanted = math.min(cap, (1 + size) * (if asym then 1 else 2))
  local faces = { v(1, 0, 0), v(-1, 0, 0), v(0, 0, 1), v(0, 0, -1) }
  -- (a faceted citadel's are in its facets, made above)
  if #mouthsMade > 0 then
    order = {}
  end
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
      -- (round a wormhole, only the faces that look out from it: one that
      -- looks in looks into the rings)
      if wide > 0.25 and high > 0.15 and not (hole > 0 and vector.dot(n, block.center) <= 0) then
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

  -- Hardpoints (the owner's table, 2026-11-18: Structures.CITADEL_HARDPOINTS),
  -- in batteries (their word): weapons of a size two to four together in
  -- a row on one face, point defence in rows beside them. Each mount is
  -- as big as its weapon is, in metres (the owner: "True ship scale"), so
  -- the citadel's own size in metres says how big that is here. On the
  -- citadel's body and the pieces grown off it (not on a module, a mast or
  -- what stands on a deck), never on a door, and with room above it.
  local mounts: { Mount } = {}
  local lo, hi = v(math.huge, math.huge, math.huge), v(-math.huge, -math.huge, -math.huge)
  for _, each in solids do
    for _, face in each.faces do
      for _, corner in face do
        lo, hi = vector.min(lo, corner), vector.max(hi, corner)
      end
    end
  end
  for _, block in blocks do
    lo, hi = vector.min(lo, block.center - block.half), vector.max(hi, block.center + block.half)
  end
  for _, ring in rings do
    local r = ring.radius + ring.thick
    local c = ring.center or v(0, 0, 0)
    lo, hi = vector.min(lo, c - v(r, r, r)), vector.max(hi, c + v(r, r, r))
  end
  local across = hi - lo
  local metres = Structures.CITADEL_REACH[size] / math.max(1e-6, math.max(across.x, across.y, across.z) / 2)
  do
    -- (the faces there are to stand on: the body's and the pieces' open
    -- facets, and every face of a block that is not covered)
    type Surface = { face: { vector }, n: vector, key: string, room: number, along: vector }
    local surfaces: { Surface } = {}
    for _, facet in facets() do
      if facet.solid.role == nil or facet.solid.role == "piece" then
        local i = levelEdge(facet.face)
        local along = vector.normalize(facet.face[i % #facet.face + 1] - facet.face[i])
        table.insert(surfaces, { face = facet.face, n = facet.n, key = facet.key, room = facet.room, along = along })
      end
    end
    for _, block in blocks do
      if block.part ~= FRAME then
        local h = block.half
        for _, n in { v(1, 0, 0), v(-1, 0, 0), v(0, 1, 0), v(0, -1, 0), v(0, 0, 1), v(0, 0, -1) } do
          local a = if n.x ~= 0 then v(0, 1, 0) else v(1, 0, 0)
          local b = vector.cross(n, a)
          local ha, hb = math.abs(vector.dot(h, a)), math.abs(vector.dot(h, b))
          local c = block.center + n * math.abs(vector.dot(h, n))
          if not inside(c + n * 0.02) then
            local face = { c + a * ha + b * hb, c - a * ha + b * hb, c - a * ha - b * hb, c + a * ha - b * hb }
            table.insert(surfaces, { face = face, n = n, key = keyOf(face), room = math.min(ha, hb),
              along = if n.y ~= 0 then v(1, 0, 0) else b })
          end
        end
      end
    end
    local hard = Structures.CITADEL_HARDPOINTS[size]
    local function footprint(sz: number): number
      return Arms.REACH * Arms.SIZE[sz] / metres
    end
    -- A row of so many mounts on a surface, about a point of it: the
    -- mounts and their footprints, or nil if it does not fit there.
    local function row(surface: Surface, middle: vector, count: number, kind: string, sz: number, r: number):
      ({ Mount }?, { { vector } })
      local spacing = r * 2.6
      local side = vector.cross(surface.n, surface.along)
      local placed: { Mount } = {}
      local prints: { { vector } } = {}
      for index = 1, count do
        local at = middle + surface.along * ((index - (count + 1) / 2) * spacing)
        local print = { at + surface.along * r + side * r, at - surface.along * r + side * r, at - surface.along * r - side * r,
          at + surface.along * r - side * r }
        for _, corner in print do
          if not onFace(surface.face, surface.n, corner) then
            return nil, prints
          end
        end
        if not free(surface.key, print, surface.n) then
          return nil, prints
        end
        for _, other in prints do
          if overlap(other, print, surface.n) then
            return nil, prints
          end
        end
        -- (room above it, and no hangar mouth there; and none of its foot
        -- inside anything, where blocks overlap: the owner, 2026-11-18,
        -- "make sure there's a check that no turrets are placed inside
        -- overlapping blocks")
        if inside(at + surface.n * r * 0.6) or inside(at + surface.n * r * 2.5) or inside(at + surface.n * r * 0.05) then
          return nil, prints
        end
        for _, corner in print do
          if inside(corner + surface.n * r * 0.05) or inside(corner + surface.n * r * 0.6) then
            return nil, prints
          end
        end
        for _, mouth in mouths do
          if not mouth.corners and vector.magnitude(mouth.at - at) < math.max(mouth.wide, mouth.high) + r then
            return nil, prints
          end
        end
        table.insert(placed, { at = at, n = surface.n, fore = surface.along, size = sz, kind = kind, radius = r, twin = 0 })
        table.insert(prints, print)
      end
      return placed, prints
    end
    -- A point of a surface, at the dice.
    local function somewhere(surface: Surface): vector
      local corners = surface.face
      local fan = rng:Int(#corners - 2) + 2
      local r1, r2 = rng:Float(), rng:Float()
      if r1 + r2 > 1 then
        r1, r2 = 1 - r1, 1 - r2
      end
      return corners[1] + (corners[fan] - corners[1]) * r1 + (corners[fan + 1] - corners[1]) * r2
    end
    local byKey: { [string]: Surface } = {}
    for _, each in surfaces do
      byKey[each.key] = each
    end
    -- How squarely each surface looks out from the citadel's middle (1
    -- straight out, -1 straight in): batteries go on the outward walls
    -- first (the owner, 2026-11-18: "bias them to outwards-facing walls,
    -- if possible").
    local centre = (lo + hi) * 0.5
    local outward: { [Surface]: number } = {}
    for _, each in surfaces do
      local from = centroid(each.face) - centre
      outward[each] = if vector.magnitude(from) > 1e-6 then vector.dot(each.n, vector.normalize(from)) else 0
    end
    -- One of some surfaces, the more outward the likelier (an inward one
    -- only now and then).
    local function pickOut(pool: { Surface }): Surface
      local total = 0
      local weights: { number } = {}
      for index, each in pool do
        local w = math.max(0.02, (outward[each] or 0) + 0.25) ^ 3
        weights[index] = w
        total += w
      end
      local roll = rng:Float(0, total)
      for index, each in pool do
        roll -= weights[index]
        if roll <= 0 then
          return each
        end
      end
      return pool[#pool]
    end
    -- (the far side: half a turn about the upright)
    local function turned(p: vector): vector
      return v(-p.x, p.y, -p.z)
    end
    -- Put a battery of so many of a kind and size in, somewhere, and (but
    -- for a super weapon) its twin on the far side: a hardpoint is a pair
    -- of mounts on opposite sides, as a ship's is, and the one that faces
    -- what it shoots at is the one that fires (the owner, 2026-11-18,
    -- choosing to twin them as ships do, so that the table's counts are
    -- the hardpoints and its strength holds). True if it went in.
    local function battery(kind: string, sz: number, count: number, r: number, near: boolean): boolean
      local pool: { Surface } = {}
      for _, each in surfaces do
        if each.room > r * 1.4 and (not near or onIt[each.key] ~= nil) then
          table.insert(pool, each)
        end
      end
      -- (an observatory on a face that looks up, where there is one)
      if kind == "observatory" then
        local up: { Surface } = {}
        for _, each in pool do
          if each.n.y > 0.3 then
            table.insert(up, each)
          end
        end
        if #up > 0 then
          pool = up
        end
      end
      if #pool == 0 then
        return false
      end
      local surface = pickOut(pool)
      local middle = somewhere(surface)
      local placed, prints = row(surface, middle, count, kind, sz, r)
      if placed == nil then
        return false
      end
      local twins: { Mount }? = nil
      local twinPrints: { { vector } } = {}
      local twinSurface: Surface? = nil
      if kind == "weapon" or kind == "pds" then
        -- (where its sides are alike, the battery turned half round, on the
        -- face that is there; else on a face that looks the other way)
        local image = byKey[keyOf(moved({ surface.face }, turned)[1])]
        if image and image ~= surface then
          local imaged = { face = image.face, n = image.n, key = image.key, room = image.room, along = turned(surface.along) }
          twins, twinPrints = row(imaged, turned(middle), count, kind, sz, r)
          twinSurface = image
        end
        if twins == nil then
          local away = turned(surface.n)
          local facing: { Surface } = {}
          for _, other in surfaces do
            if other ~= surface and other.room > r * 1.4 and vector.dot(other.n, away) > 0.6 then
              table.insert(facing, other)
            end
          end
          for _ = 1, if #facing > 0 then 24 else 0 do
            local other = pickOut(facing)
            do
              twins, twinPrints = row(other, somewhere(other), count, kind, sz, r)
              if twins then
                twinSurface = other
                break
              end
            end
          end
        end
        if twins == nil then
          return false
        end
      end
      for _, print in prints do
        note(surface.key, print)
      end
      local first = #mounts
      table.move(placed, 1, #placed, #mounts + 1, mounts)
      local pairs = twins
      local where = twinSurface
      if pairs and where then
        for _, print in twinPrints do
          note(where.key, print)
        end
        for index, mount in pairs do
          table.insert(mounts, mount)
          mount.twin = first + index
          mounts[first + index].twin = #mounts
        end
      end
      return true
    end
    local function place(kind: string, sz: number, total: number, r: number)
      local left = total
      for attempt = 1, 400 do
        if left <= 0 then
          break
        end
        local most = if kind == "super" then 1 elseif kind == "pds" then 6 else 4
        local count = math.min(left, if attempt > 200 then 1 else rng:Int(math.max(1, most - 1)) + 2)
        -- (point defence beside the batteries, mostly)
        if battery(kind, sz, count, r, kind == "pds" and attempt <= 150 and rng:Float() < 0.7) then
          left -= count
        end
      end
    end
    -- The kind's own, first: a research station's observatory, a
    -- refinery's mining turret (the owner, 2026-11-18). These are
    -- buildings, not guns, and are drawn as big as a building on the
    -- citadel reads (a share of it: mine), not to a gun's measure.
    local special = if kind == "research" then "observatory" elseif kind == "refinery" then "miner" else nil
    local kept = reserved
    if kept then
      table.insert(mounts, kept)
      special = nil
    end
    if special then
      local big = math.max(across.x, across.y, across.z) * (if special == "observatory" then Citadel.OBSERVATORY else Citadel.MINER)
      for _ = 1, 200 do
        if battery(special, 0, 1, big, false) then
          break
        end
      end
    end
    if hard.super > 0 then
      place("super", 4, hard.super, footprint(4) * 4)
    end
    place("weapon", 4, hard.xl, footprint(4))
    place("weapon", 3, hard.large, footprint(3))
    place("weapon", 2, hard.medium, footprint(2))
    place("pds", 2, hard.pds, footprint(2))
  end

  local plates: { Hull.Plate } = {}
  for _, block in blocks do
    table.insert(plates, { center = block.center, size = block.half, part = block.part, single = true })
  end
  table.move(extra, 1, #extra, #plates + 1, plates)
  return { plates = plates, mouths = mouths, solids = solids, rings = rings, hole = hole, beams = beams, balls = balls, mounts = mounts,
    metres = metres }
end

-- The plates of a citadel grown from a seed at a size (1 to 5), and its
-- hangar mouths, in the hull generator's units (of its blocks: a
-- style's solids and rings are Citadel.Shape's).
function Citadel.Grow(seed: number, size: number, asym: boolean?, style: string?, doors: number?, kind: string?): ({ Hull.Plate }, { Mouth })
  local shape = Citadel.Shape(seed, size, asym, style, doors, kind)
  return shape.plates, shape.mouths
end

-- What of a citadel turns (a wormhole citadel's rings), each a model of
-- its own about its pivot (Game/View/Starbase's movers: Starbase.Animate
-- turns it).
export type Mover = { model: Model, pivot: vector, motion: Tower.Motion }
-- ('mounts': its hardpoints, in the model's units; 'metres': how many
-- metres a unit of the model is, as big as the citadel really is.)
export type Made = { model: Model, radius: number, lower: vector, upper: vector, movers: { Mover }?, mounts: { Mount }, metres: number }

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
    -- (a door in a facet: its own trapezoid, a hair out)
    local own = mouth.corners
    if own then
      corners = {}
      for _, corner in own do
        table.insert(corners, (corner + mouth.n * 0.03) * G)
      end
    end
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

-- A hulk's hangar mouth: black, where the air shield was (hangarvoid.jsl).
local voidShader: ShaderInstance? = nil
local function voidOf(): ShaderInstance
  local known: ShaderInstance? = voidShader
  if not known then
    local shader = ShaderInstance_Create(Shader_Create("npm.jsl", "hangarvoid.jsl"))
    ShaderInstance_SetState(shader, "BlendModeAlpha")
    ShaderInstance_SetState(shader, "ZWritableOff")
    ShaderInstance_SetState(shader, "CullModeDisabled")
    ShaderInstance_Link(shader)
    voidShader = shader
    return shader
  end
  return known :: ShaderInstance
end

local beamShader: ShaderInstance? = nil
local function beamOf(): ShaderInstance
  if beamShader == nil then
    local shader = ShaderInstance_Create(Shader_Create("npm.jsl", "mastbeam.jsl"))
    ShaderInstance_SetState(shader, "BlendModeAdditive")
    ShaderInstance_SetState(shader, "ZWritableOff")
    ShaderInstance_SetState(shader, "CullModeDisabled")
    ShaderInstance_SetVec3(shader, "beamTint", v(0.7, 0.9, 1.0))
    ShaderInstance_Link(shader)
    beamShader = shader
  end
  return beamShader :: ShaderInstance
end
-- (the ball, a lightless sphere of a dark crimson, and the crackles round
-- it on a sphere BALL_HALO times as big: energyball.jsl, which is told
-- each sphere's radius, in the model's units, to find its middle by)
local BALL_HALO = 1.8
local ballShaders: { [string]: ShaderInstance } = {}
local function ballOf(halo: number, radius: number): ShaderInstance
  local key = `{halo}:{radius}`
  local known: ShaderInstance? = ballShaders[key]
  if not known then
    local shader = ShaderInstance_Create(Shader_Create("npm.jsl", "energyball.jsl"))
    ShaderInstance_SetState(shader, if halo > 0.5 then "BlendModeAdditive" else "BlendModeAlpha")
    ShaderInstance_SetState(shader, "ZWritableOff")
    ShaderInstance_SetState(shader, "CullModeDisabled")
    ShaderInstance_SetVec3(shader, "ballTint", v(0.55, 0.03, 0.05))
    ShaderInstance_SetFloat(shader, "ballHalo", halo)
    ShaderInstance_SetFloat(shader, "ballRadius", radius)
    ShaderInstance_Link(shader)
    ballShaders[key] = shader
    known = shader
  end
  return known :: ShaderInstance
end

-- A mast's beam as crossed sheets (in the model's units), and a ball as a sphere.
local function beamMesh(beam: Beam): Mesh
  local G = Hull.GROWN
  local mesh = Mesh_Create()
  local d = vector.normalize(beam.to - beam.from)
  local a = vector.normalize(vector.cross(d, if math.abs(d.y) < 0.9 then v(0, 1, 0) else v(1, 0, 0)))
  local b = vector.cross(d, a)
  local count = 0
  for _, side in { a, b, vector.normalize(a + b), vector.normalize(a - b) } do
    local w = side * beam.width * G
    local p0, p1 = beam.from * G, beam.to * G
    local n = vector.cross(d, side)
    Mesh_AddVertex(mesh, p0 - w, n, 0, 0)
    Mesh_AddVertex(mesh, p0 + w, n, 1, 0)
    Mesh_AddVertex(mesh, p1 + w, n, 1, 1)
    Mesh_AddVertex(mesh, p1 - w, n, 0, 1)
    Mesh_AddTriangle(mesh, count, count + 1, count + 2)
    Mesh_AddTriangle(mesh, count, count + 2, count + 3)
    count += 4
  end
  return mesh
end
local function ballMesh(at: vector, radius: number): Mesh
  local G = Hull.GROWN
  local mesh = Mesh_Create()
  local stacks, slices = 12, 18
  for i = 0, stacks do
    local lat = math.pi * i / stacks
    for j = 0, slices do
      local lon = 2 * math.pi * j / slices
      local n = v(math.sin(lat) * math.cos(lon), math.cos(lat), math.sin(lat) * math.sin(lon))
      Mesh_AddVertex(mesh, (at + n * radius) * G, n, j / slices, i / stacks)
    end
  end
  for i = 0, stacks - 1 do
    for j = 0, slices - 1 do
      local a = i * (slices + 1) + j
      local b = a + slices + 1
      Mesh_AddTriangle(mesh, a, b, a + 1)
      Mesh_AddTriangle(mesh, a + 1, b, b + 1)
    end
  end
  return mesh
end

-- The colours of a generator citadel's sphere, by what its generator
-- makes (the owner, 2026-11-18: "slightly different hues, black for
-- gravity vs deep purple for wormhole"): its middle, and the thin ring of
-- bent light round it. (The purples are mine.)
local HOLE_HUES: { [string]: { core: vector, ring: vector } } = {
  gravity = { core = v(0, 0, 0), ring = v(0.55, 0.62, 0.75) },
  wormhole = { core = v(0.035, 0.0, 0.07), ring = v(0.62, 0.38, 0.9) },
}
local holeShaders: { [string]: ShaderInstance } = {}
local function holeOf(kind: string?): ShaderInstance
  local hue = if kind == "wormhole" then "wormhole" else "gravity"
  local known: ShaderInstance? = holeShaders[hue]
  if not known then
    -- (as a wormhole in space is drawn: Game/View/Scene)
    local shader = ShaderInstance_Create(Shader_Create("npm.jsl", "wormhole.jsl"))
    ShaderInstance_SetState(shader, "BlendModeAlpha")
    ShaderInstance_SetState(shader, "ZWritableOff")
    ShaderInstance_SetState(shader, "CullModeDisabled")
    ShaderInstance_SetVec3(shader, "holeCore", HOLE_HUES[hue].core)
    ShaderInstance_SetVec3(shader, "holeRing", HOLE_HUES[hue].ring)
    ShaderInstance_Link(shader)
    holeShaders[hue] = shader
    return shader
  end
  return known :: ShaderInstance
end

-- A ring drawn into a builder: so many lengths of plate round it, a lit
-- strip along its inside, and a pod at each quarter (in the model's
-- units).
-- ('glow': the part its lit strip is drawn in, FRAME on a hulk.)
local function drawRing(b: Plates.Builder, ring: Ring, size: number, glow: number)
  local G = Hull.GROWN
  local n = ring.normal
  local e1 = vector.normalize(vector.cross(n, if math.abs(n.y) > 0.9 then v(1, 0, 0) else v(0, 1, 0)))
  local e2 = vector.cross(n, e1)
  local R, t = ring.radius * G, ring.thick * G
  local lengths = 32 + 4 * size
  local middle = (ring.center or v(0, 0, 0)) * G
  local function at(index: number, r: number): vector
    local a = index / lengths * 2 * math.pi
    return middle + (e1 * math.cos(a) + e2 * math.sin(a)) * r
  end
  for index = 0, lengths - 1 do
    Plates.Beam(b, PLATING, at(index, R), at(index + 1, R), t, EASED)
    Plates.Beam(b, glow, at(index, R - t * 1.05), at(index + 1, R - t * 1.05), t * 0.22, EASED)
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
-- A box drawn in flat plate, square to its own ways (u, w, n), so many to
-- each side; and a drum, round its axis from its foot, of 'sides' sides.
local function slab(b: Plates.Builder, part: number, c: vector, u: vector, w: vector, n: vector, hu: number, hw: number, hn: number)
  local function P(su: number, sw: number, sn: number): vector
    return c + u * (su * hu) + w * (sw * hw) + n * (sn * hn)
  end
  Plates.Flat(b, part, { P(1, 1, 1), P(-1, 1, 1), P(-1, -1, 1), P(1, -1, 1) }, n)
  Plates.Flat(b, part, { P(1, 1, -1), P(1, -1, -1), P(-1, -1, -1), P(-1, 1, -1) }, -n)
  Plates.Flat(b, part, { P(1, 1, 1), P(1, -1, 1), P(1, -1, -1), P(1, 1, -1) }, u)
  Plates.Flat(b, part, { P(-1, 1, 1), P(-1, 1, -1), P(-1, -1, -1), P(-1, -1, 1) }, -u)
  Plates.Flat(b, part, { P(1, 1, 1), P(1, 1, -1), P(-1, 1, -1), P(-1, 1, 1) }, w)
  Plates.Flat(b, part, { P(1, -1, 1), P(-1, -1, 1), P(-1, -1, -1), P(1, -1, -1) }, -w)
end
local function drum(b: Plates.Builder, part: number, foot: vector, axis: vector, r: number, h: number, sides: number)
  local a = vector.normalize(vector.cross(axis, if math.abs(axis.y) < 0.9 then v(0, 1, 0) else v(1, 0, 0)))
  local c = vector.cross(axis, a)
  local low, high = {}, {}
  for index = 0, sides - 1 do
    local t = index * 2 * math.pi / sides
    local out = (a * math.cos(t) + c * math.sin(t)) * r
    table.insert(low, foot + out)
    table.insert(high, foot + axis * h + out)
  end
  for index = 1, sides do
    local after = index % sides + 1
    local mid = (low[index] + low[after]) * 0.5 - foot
    Plates.Flat(b, part, { low[index], low[after], high[after], high[index] }, mid)
  end
  local top: { vector } = {}
  for index = sides, 1, -1 do
    table.insert(top, high[index])
  end
  Plates.Flat(b, part, top, axis)
  Plates.Flat(b, part, low, -axis)
end

-- ('kind': its kind, for what only some kinds have on them; 'idle': its
-- wormhole's generator is not running, so there is no wormhole and its
-- rings stand still: the owner, 2026-11-18, the wormhole and gravity
-- stations' working tied to the station being fuelled "AND the module
-- being installed", and hidden when not.)
-- ('offline': its kind's module, the observatory or the mining turret, is
-- fitted but not working, unfuelled or switched off: it is there, but dark,
-- its lights out and nothing of it turning: the owner, 2026-11-18.)
function Citadel.Build(seed: number, size: number, paint: string?, detail: string?, metres: number?, asym: boolean?, style: string?,
  doors: number?, kind: string?, idle: boolean?, offline: boolean?, dead: boolean?): Made
  local key = `{seed}:{size}:{paint or ""}:{detail or ""}:{asym == true}:{style or "blocks"}:{doors or Citadel.DOORS}:{kind or ""}`
    .. `:{idle == true}:{offline == true}:{dead == true}`
  local kept = made[key]
  if kept then
    return kept
  end
  local shape = Citadel.Shape(seed, size, asym, style, doors, kind)
  local plates, mouths = shape.plates, shape.mouths
  -- (a hulk: nothing of it is lit, Citadel.Hulk)
  local glow = if dead then FRAME else GLOW
  if dead then
    local cold: { Hull.Plate } = {}
    for _, plate in plates do
      local part = math.floor(plate.part)
      if part == GLOW or part == Plates.FIRE or part >= Plates.LAMP_RED then
        local copy = table.clone(plate)
        copy.part = FRAME
        table.insert(cold, copy)
      else
        table.insert(cold, plate)
      end
    end
    plates = cold
  end
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
  -- (a door in a facet: the dark of the hangar let into it, lit round its edges)
  for _, mouth in mouths do
    local own = mouth.corners
    if own then
      local corners: { vector } = {}
      for _, corner in own do
        table.insert(corners, (corner + mouth.n * 0.006) * G)
      end
      Plates.Flat(b, FRAME, corners, mouth.n)
      for index, a in own do
        local after = own[index % #own + 1]
        Plates.Beam(b, glow, (a + mouth.n * 0.012) * G, (after + mouth.n * 0.012) * G, 0.03 * G, EASED)
      end
    end
  end
  -- (each hardpoint a socket: its ring, and a cover on it, flush on its
  -- face; what is fitted stands on it, Citadel.Arm)
  -- (an observatory's dome and a mining turret's foot: their turning
  -- parts, the telescope and the gun, are movers, below)
  -- (lit, while the module works; dark, offline)
  local lit = if offline or dead then FRAME else GLOW
  local turners: { { builder: Plates.Builder, pivot: vector, axis: vector } } = {}
  for _, mount in shape.mounts do
    local n, a = mount.n, mount.fore
    local c = vector.cross(n, a)
    local R = mount.radius * G
    local at = mount.at * G
    if mount.kind == "observatory" then
      -- A dome: rings of plate up to a cap, and a slot in it.
      local rings: { { vector } } = {}
      for _, phi in { 0, 0.42, 0.85, 1.22 } do
        local ring: { vector } = {}
        for index = 0, 11 do
          local t = index * math.pi / 6
          table.insert(ring, at + (a * math.cos(t) + c * math.sin(t)) * (R * math.cos(phi)) + n * (R * math.sin(phi)))
        end
        table.insert(rings, ring)
      end
      for k = 1, #rings - 1 do
        for index = 1, 12 do
          local after = index % 12 + 1
          local quad = { rings[k][index], rings[k][after], rings[k + 1][after], rings[k + 1][index] }
          Plates.Flat(b, if k == 1 then PLATING else PATCH, quad, (quad[1] + quad[3]) * 0.5 - at)
        end
      end
      local cap: { vector } = {}
      for index = 12, 1, -1 do
        table.insert(cap, rings[#rings][index])
      end
      Plates.Flat(b, PATCH, cap, n)
      -- (round its foot: plant, in boxes, and lights on its rim, and a mast
      -- with a light at its head)
      for index = 0, 7 do
        local t = index * math.pi / 4 + math.pi / 8
        local out = a * math.cos(t) + c * math.sin(t)
        local across = vector.cross(n, out)
        local big = if index % 2 == 0 then 0.16 else 0.1
        slab(b, if index % 3 == 0 then FRAME else PATCH, at + out * (R * 1.12) + n * (R * big * 0.6), out, across, n, R * big * 0.7,
          R * big, R * big * 0.6)
      end
      for index = 0, 11 do
        local t = index * math.pi / 6
        local out = a * math.cos(t) + c * math.sin(t)
        slab(b, lit, at + out * (R * 0.99) + n * (R * 0.03), out, vector.cross(n, out), n, R * 0.025, R * 0.025, R * 0.025)
      end
      local mast = at + c * (R * 0.55) + n * (R * 0.7)
      drum(b, FRAME, mast, n, R * 0.02, R * 0.55, 6)
      slab(b, lit, mast + n * (R * 0.57), a, c, n, R * 0.035, R * 0.035, R * 0.035)
      -- (the telescope, on a yoke above the cap: it turns to what it scans)
      local tb = Plates.New(seed * 2.3 + #turners, 0.04)
      local pivot = at + n * (R * 1.0)
      local look = vector.normalize(a * 0.75 + n * 0.65)
      local side = vector.normalize(vector.cross(n, look))
      local T = R * SCOPE
      -- (drawn about its pivot, where Starbase.Movers stands it)
      slab(tb, FRAME, -n * (T * 0.06), side, vector.cross(side, n), n, T * 0.28, T * 0.12, T * 0.06)
      drum(tb, PLATING, -look * (T * 0.35), look, T * 0.17, T * 1.45, 10)
      drum(tb, lit, look * (T * 1.08), look, T * 0.13, T * 0.03, 10)
      -- (its works on the yoke, and a light on the tube)
      slab(tb, PATCH, side * (T * 0.22) + n * (T * 0.04), side, vector.cross(side, n), n, T * 0.06, T * 0.08, T * 0.06)
      slab(tb, PATCH, -side * (T * 0.22) + n * (T * 0.04), side, vector.cross(side, n), n, T * 0.06, T * 0.08, T * 0.06)
      slab(tb, lit, look * (T * 0.5) + vector.normalize(vector.cross(look, side)) * (T * 0.18), side, look, vector.cross(side, look),
        T * 0.025, T * 0.025, T * 0.025)
      table.insert(turners, { builder = tb, pivot = pivot, axis = n })
    elseif mount.kind == "miner" then
      -- A squat foot, and on it the gun: a housing and one long barrel.
      -- (an octagon, for some definition: the owner, 2026-11-18)
      drum(b, PLATING, at, n, R, R * 0.32, 8)
      drum(b, FRAME, at + n * (R * 0.32), n, R * 0.82, R * 0.08, 8)
      -- (plant on its sides, and lights round its rim)
      for index = 0, 7 do
        local t = index * math.pi / 4
        local out = a * math.cos(t) + c * math.sin(t)
        local across = vector.cross(n, out)
        slab(b, if index % 2 == 0 then PATCH else FRAME, at + out * (R * 0.94) + n * (R * 0.16), out, across, n, R * 0.08,
          R * (if index % 2 == 0 then 0.2 else 0.12), R * 0.1)
        slab(b, lit, at + out * (R * 0.86) + n * (R * 0.34), out, across, n, R * 0.025, R * 0.025, R * 0.025)
      end
      local gb = Plates.New(seed * 3.1 + #turners, 0.04)
      local pivot = at + n * (R * 0.4)
      local aim = vector.normalize(a * 0.85 + n * 0.5)
      local side = vector.normalize(vector.cross(n, a))
      slab(gb, PATCH, n * (R * 0.32), a, side, n, R * 0.62, R * 0.5, R * 0.32)
      drum(gb, PLATING, n * (R * 0.38) + a * (R * 0.4), aim, R * 0.13, R * 2.4, 8)
      drum(gb, FRAME, n * (R * 0.38) + a * (R * 0.4) + aim * (R * 2.3), aim, R * 0.19, R * 0.22, 8)
      -- (vents and works on the housing, and lights: on its back and the muzzle)
      for _, s2 in { -1, 1 } do
        slab(gb, FRAME, n * (R * 0.32) + side * (s2 * R * 0.53), a, side, n, R * 0.4, R * 0.04, R * 0.2)
        slab(gb, PATCH, n * (R * 0.66) - a * (R * 0.3) + side * (s2 * R * 0.25), a, side, n, R * 0.14, R * 0.1, R * 0.05)
      end
      slab(gb, lit, n * (R * 0.5) - a * (R * 0.63), a, side, n, R * 0.025, R * 0.12, R * 0.025)
      drum(gb, lit, n * (R * 0.38) + a * (R * 0.4) + aim * (R * 2.52), aim, R * 0.15, R * 0.02, 8)
      table.insert(turners, { builder = gb, pivot = pivot, axis = n })
    end
  end
  for _, mount in shape.mounts do
    if mount.kind == "observatory" or mount.kind == "miner" then
      continue
    end
    local a = mount.fore
    local c = vector.cross(mount.n, a)
    local function square(r: number, up: number): { vector }
      local at = mount.at + mount.n * up
      return { (at + a * r + c * r) * G, (at - a * r + c * r) * G, (at - a * r - c * r) * G, (at + a * r - c * r) * G }
    end
    Plates.Flat(b, FRAME, square(mount.radius, mount.radius * 0.04), mount.n)
    Plates.Flat(b, PATCH, square(mount.radius * 0.72, mount.radius * 0.09), mount.n)
  end
  -- (the ring that stands still is the citadel's own)
  for _, ring in shape.rings do
    if ring.rate == 0 then
      drawRing(b, ring, size, glow)
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
  -- (a hulk's hangars hold no air: no shield across them, and nothing
  -- lit inside, so they are black)
  local sheet = shields(mouths)
  if sheet then
    Model_AddShell(model, sheet, if dead then voidOf() else shieldOf())
  end
  -- The masts' beams and balls of energy.
  local beams: { Beam } = if dead then {} else shape.beams
  for _, beam in beams do
    Model_AddShell(model, beamMesh(beam), beamOf())
  end
  local balls: { Ball } = if dead then {} else shape.balls
  for _, ball in balls do
    Model_AddShell(model, ballMesh(ball.at, ball.radius), ballOf(0, ball.radius * G))
    Model_AddShell(model, ballMesh(ball.at, ball.radius * BALL_HALO), ballOf(1, ball.radius * BALL_HALO * G))
  end
  -- The wormhole: a sphere at the middle, drawn lightless (wormhole.jsl):
  -- while its generator runs.
  if shape.hole > 0 and not idle then
    local r = shape.hole * G
    Model_AddShell(model, Mesh_Scale(Mesh_BoxSphere(16, true), v(r, r, r)), holeOf(kind))
  end
  -- What turns: each ring a model of its own, about the middle.
  local movers: { Mover } = {}
  for index, ring in shape.rings do
    if ring.rate ~= 0 then
      local rb = Plates.New(seed * 3.7 + index * 11.3, 0.04)
      drawRing(rb, ring, size, glow)
      local turning = Plates.Finish(rb, look, sheets)
      table.insert(movers, { model = turning, pivot = v(0, 0, 0),
        motion = { kind = "turn", axis = ring.axis, rate = if idle then 0 else ring.rate, phase = ring.phase } })
      local far = (ring.radius + ring.thick) * G
      lower, upper = vector.min(lower, v(-far, -far, -far)), vector.max(upper, v(far, far, far))
    end
  end
  -- (and an observatory's telescope and a mining turret's gun, each about
  -- its foot: they sweep slowly round until what they work at is known,
  -- Tactical's, and turns them to it)
  for index, turner in turners do
    table.insert(movers, { model = (Plates.Finish(turner.builder, look, sheets)), pivot = turner.pivot,
      motion = { kind = "turn", axis = turner.axis, rate = if offline then 0 else 0.05 * (if index % 2 == 0 then -1 else 1),
        phase = index * 0.37 } })
  end
  local across = upper - lower
  local radius = math.max(across.x, across.y, across.z) / 2
  local mounts: { Mount } = {}
  for _, mount in shape.mounts do
    table.insert(mounts, { at = mount.at * G, n = mount.n, fore = mount.fore, size = mount.size, kind = mount.kind,
      radius = mount.radius * G, twin = mount.twin })
  end
  local result: Made = { model = model, radius = radius, lower = lower, upper = upper,
    movers = if #movers > 0 then movers else nil, mounts = mounts, metres = shape.metres / G }
  made[key] = result
  return result
end

-- The weapon a defence module of a family ("cannon", "laser", "hybrid",
-- "missile") mounts on each weapon hardpoint of a citadel of a size, in
-- the order of its mounts (Structures.CITADEL_DEFENCE: so many of a size,
-- short-range then long-range); "autocannon.medium" on each point defence
-- mount, which every citadel has; "" where nothing goes (a super weapon's,
-- or a weapon hardpoint with no module, 'family' nil).
local SHORT: { [string]: string } = { cannon = "autocannon", laser = "laser.pulse", hybrid = "blaster" }
local LONG: { [string]: string } = { cannon = "artillery", laser = "laser.beam", hybrid = "railgun" }
local MISSILE_SHORT = { medium = "launcher.assault", large = "launcher.torpedo", xl = "launcher.bombard" }
local MISSILE_LONG = { medium = "launcher.heavy", large = "launcher.cruise", xl = "launcher.siege" }
local SIZE_WORDS = { [2] = "medium", [3] = "large", [4] = "xl" }
function Citadel.Armed(mounts: { Mount }, size: number, family: string?): { string }
  local out: { string } = {}
  local used: { [string]: number } = {}
  for index, mount in mounts do
    local word = SIZE_WORDS[mount.size] or "medium"
    -- (a twin carries what the first of its pair does: a pair is one hardpoint)
    if mount.twin ~= 0 and mount.twin < index then
      out[index] = out[mount.twin]
    elseif mount.kind == "pds" then
      out[index] = "autocannon.medium"
    elseif mount.kind ~= "weapon" or family == nil then
      out[index] = ""
    else
      -- (the next of this size: short-range first, then long)
      local nth = (used[word] or 0) + 1
      used[word] = nth
      local range = "long"
      local counted = 0
      for _, each in Structures.CITADEL_DEFENCE[size] do
        if each.size == word then
          counted += each.count
          if nth <= counted then
            range = each.range
            break
          end
        end
      end
      if family == "missile" then
        out[index] = if range == "short" then MISSILE_SHORT[word] else MISSILE_LONG[word]
      else
        local make = if range == "short" then SHORT[family] else LONG[family]
        out[index] = `{make}.{word}`
      end
    end
  end
  return out
end

-- The citadel a kind and a size is drawn as in the game (Citadel.Pick):
-- in a faction's paint, if it is a faction's, and else in its design's.
-- ('generating': what a generator station's generator makes, "gravity"
-- or "wormhole": nil, and its sphere is not there and its rings still.)
function Citadel.Of(kind: string?, size: number, faction: string?, generating: string?): Made
  local pick = Citadel.Pick(kind, size, Citadel.PeopleOf(faction))
  local paint = if faction and faction ~= "" and Hull.looks[faction] then faction else pick.paint
  local drawn = if kind == "generator" or kind == "gravity" or kind == "wormhole" then generating or kind else kind
  local idle = (kind == "generator" or kind == "gravity" or kind == "wormhole") and generating == nil
  return Citadel.Build(pick.seed, size, paint, pick.detail, nil, pick.asym, pick.style, pick.doors, drawn, idle)
end

-- A citadel's hulk (Core/Assets/Hulks): the citadel a kind and a size is
-- drawn as, in the citadels' own dark grey, every light out, nothing
-- turning and no wormhole ('people': whose design, Citadel.PEOPLES).
function Citadel.Hulk(kind: string?, size: number, people: string?): Made
  local pick = Citadel.Pick(kind, size, people)
  local words: { string } = {}
  for _, word in string.split(pick.detail, " ") do
    if word ~= "" and string.sub(word, 1, 6) ~= "lights" then
      table.insert(words, word)
    end
  end
  return Citadel.Build(pick.seed, size, nil, table.concat(words, " "), nil, pick.asym, pick.style, pick.doors, kind, true, true, true)
end

-- The hangar doors of the citadel a kind and a size is drawn as (the
-- owner, 2026-11-17: "we should also make sure ships undocking exit
-- through one of the hangar doors"): each door's middle, from the
-- station's middle in the citadel's own radii (as Game/View/Starbase
-- stands it: its middle where the station is, as big as its reach),
-- and the way out of it. The game's rules cannot grow a citadel (that is
-- the engine's), so what this says is written into Core/Data/
-- CitadelDoors by script/citadeldoors, whenever a pick changes.
-- ('people': an alien people's own design, Citadel.PEOPLES.)
function Citadel.Doors(kind: string, size: number, people: string?): { { at: vector, n: vector } }
  local pick = Citadel.Pick(kind, size, people)
  local made = Citadel.Build(pick.seed, size, pick.paint, pick.detail, nil, pick.asym, pick.style, pick.doors, kind)
  local mid = (made.lower + made.upper) * 0.5
  local doors: { { at: vector, n: vector } } = {}
  for _, mouth in Citadel.Shape(pick.seed, size, pick.asym, pick.style, pick.doors, kind).mouths do
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
  -- (each kind, and each alien people's kinds as "vail.shipyard")
  local keys: { { key: string, kind: string, people: string? } } = {}
  for _, kind in Structures.CITADEL_KINDS do
    table.insert(keys, { key = kind, kind = kind })
  end
  for _, people in Structures.CITADEL_ALIEN_PEOPLES do
    for _, each in Structures.CITADEL_ALIEN do
      table.insert(keys, { key = `{people}.{each.kind}`, kind = each.kind, people = people })
    end
  end
  for _, entry in keys do
    table.insert(lines, if string.find(entry.key, ".", 1, true) then `  ["{entry.key}"] = \{` else `  {entry.key} = \{`)
    for size = 1, 5 do
      local doors: { string } = {}
      for _, door in Citadel.Doors(entry.kind, size, entry.people) do
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
