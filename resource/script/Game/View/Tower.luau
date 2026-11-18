--!strict
-- Towers built in sections (for the stations: Game/View/Starbase).
--
-- The towers grown as a hull is (Hull.GrownTower, taken out 2026-11-16) were all one thing: the
-- same plates in fours about a spine, drawn in to a spindle, with a lit
-- band and two collars at the waist of every one. (The owner, of them,
-- 2026-11-15: "the tower generator is not very varied right now. All of
-- them have the same basic set of 'plates' and shapes that grow as you
-- increase size (no toruses, horizontal gantries or antennas, etc).
-- Also, the 'ice cream sandwich' center stays the same (and is always
-- present)"; and, of how unalike the towers of different peoples can
-- be, three pictures: one with its weight low under a cross of antenna
-- booms, one a dome and a broad disc over a cage of struts on a thin
-- stem, one a pod off its middle over gantries of panels.)
--
-- A tower here is a thin stem, and things along it (which the owner
-- found "fine for the human factions"; the Nimia's is to be a sphere
-- and the Vail's a torus, which are not here yet):
--
--   bodies    what it is made of, one after another up the stem, each of
--             a kind (tiers, a taper, a cage of struts, open lattice,
--             pods strapped round), with or without bare stem between
--   sides     what stands out sideways (a ring on spokes, a disc, gantry
--             arms, antenna booms, racks of panels, fins, a mooring
--             band, a dish on an arm, one pod off to a side)
--   a top     a spire, a dome, masts, a dish, a cap
--   a tail    a needle, spikes, a bell, a keel, a weight
--
-- Two things say what a tower is like, and the seed says which tower of
-- that it is:
--
--   its build    which of those it may be made of, and where its weight
--                is (Tower.BUILDS): the shape it cuts
--   its manner   how what it is made of is made (Tower.MANNERS): in
--                flat plate, in round skins, in open frames, as if
--                poured. The same tower in another manner has the same
--                things in the same places, made otherwise.
--
-- And two things the seed says can be said over it: how many times a
-- thing is there about the upright (Tower.FOLDS), and where its weight
-- is (Tower.PLANS). The rest of the tower is as it was.
--
-- A bigger tower has more bodies and more standing out of it, and not
-- only more of the same.
--
-- It lies along z, its top toward +z, as a grown tower does: whoever
-- draws it stands it up. Nothing about it would stand on a floor (the
-- owner's rule for anything anchored in space).
--
-- (Every build and manner here, and every number, is mine: the owner
-- picks among what they make, a seed at a time, as with the ships.
-- Nothing moves yet: rings that turn, dishes, panels that face the sun
-- and hazard lights are wanted, and come after.)

local Int = require("@lt/Int")
local Plates = require("@lt/Game/View/Plates")

local Tower = {}

type Builder = Plates.Builder
local PLATING, PATCH, FRAME, GLOW, TRIM = Plates.PLATING, Plates.PATCH, Plates.FRAME, Plates.GLOW, Plates.TRIM
local block, beam, truss = Plates.Block, Plates.Beam, Plates.Truss

local TAU = 2 * math.pi

local function v(x: number, y: number, z: number): vector
  return vector.create(x, y, z)
end

-- The upright that things are drawn about: the tower's own, through
-- the middle of it, or (for a small tower standing off from it: 'aside')
-- one of its own, so far from that.
local asideX, asideY = 0, 0

-- So far 'out' at an 'angle' round an upright: the way and the length, from wherever.
local function around(angle: number, out: number): vector
  return v(math.cos(angle) * out, math.sin(angle) * out, 0)
end

-- A point 'out' from the upright, 'angle' round it, 'z' along it.
local function at(angle: number, out: number, z: number): vector
  return v(asideX + math.cos(angle) * out, asideY + math.sin(angle) * out, z)
end

-- A point on the upright, 'z' along it.
local function axis(z: number): vector
  return v(asideX, asideY, z)
end

-- A box turned to face out from the upright at 'angle': 'half' is how
-- far it goes outward, round, and along.
local function facing(b: Builder, part: number, angle: number, out: number, z: number, half: vector, bevel: number?)
  block(b, part, at(angle, out, z), half, v(0, 0, angle), bevel)
end

local function oneOf(rng: RNG, list: { string }): string
  return list[rng:Int(1, #list)]
end

local function chance(rng: RNG, share: number): boolean
  return rng:Float(0, 1) < share
end

-- Dice of a thing's own, from the tower's: so that however a thing is
-- made, and however many times it is there, the things after it are
-- what they were.
local function own(rng: RNG): RNG
  return RNG_MTG(rng:Int(1, 2000000000))
end

-- The corners of a figure of so many sides, 'out' from the upright (a
-- flat of it, and not a corner, toward +x).
local function corners(sides: number, out: number): { vector }
  local ring: { vector } = {}
  for index = 1, sides do
    ring[index] = at((index - 0.5) / sides * TAU, out, 0)
  end
  return ring
end

-- A solid about the upright, in flat plates: of so many sides, and as
-- far out at each of the places along it as is said ({ z, out }).
local function prism(b: Builder, part: number, sides: number, places: { { number } })
  local sections: { Plates.Section } = {}
  for index, place in places do
    sections[index] = { z = place[1], ring = corners(sides, math.max(place[2], 0.004)) }
  end
  Plates.Hard(b, part, sections, 0.5)
end

-- The same in a round skin, whose middle line may be 'x' and 'y' aside.
local function skin(b: Builder, part: number, places: { { number } }, x: number?, y: number?)
  local outline: Plates.Outline = {}
  for index, place in places do
    outline[index] = { place[1], math.max(place[2], 0.004), math.max(place[2], 0.004) }
  end
  Plates.Loft(b, part, outline, asideX + (x or 0), asideY + (y or 0))
end

-- How a tower's things are made.
type Manner = {
  hard: boolean,      -- in flat plate, sharp at its edges; or in round skins
  frame: boolean,     -- what is solid is held in an open frame, and what reaches is braced
  bowed: boolean,     -- what reaches is bowed, and nothing is braced: as if poured
  ease: number,       -- how far a box's edges are eased
  girth: number,      -- how stout it is
  thin: number,       -- how thick its members are
}

local MANNERS: { [string]: Manner } = {
  -- (flat plate, hard at its edges, stout: as the Vessari's hulls are)
  blocky = { hard = true, frame = false, bowed = false, ease = 0.06, girth = 1.1, thin = 1.0 },
  -- (round and swelling: as the Talmar's)
  cloud = { hard = false, frame = false, bowed = false, ease = 0.5, girth = 1.15, thin = 1.15 },
  -- (slim, in long members and open frames, with masts on everything: as the Orun's)
  spar = { hard = true, frame = true, bowed = false, ease = 0.2, girth = 0.78, thin = 0.65 },
  -- (smooth and close, nothing braced: for a people whose things are not built of plate)
  poured = { hard = false, frame = false, bowed = true, ease = 0.5, girth = 1.0, thin = 1.6 },
}

-- The manners a tower can be made in, in the order they are shown in.
Tower.MANNERS = { "blocky", "cloud", "spar", "poured" }

-- What a build is: what a tower of it may be made of.
type Build = {
  folds: { number },      -- how many times a thing is there about the upright
  plans: { string },      -- where its weight is
  bodies: { string },
  sides: { string },
  tops: { string },
  tails: { string },
  girth: number,          -- how stout it is
  bare: number,           -- how often bare stem shows between two bodies
  many: number,           -- how much stands out sideways, for its size
}

local BUILDS: { [string]: Build } = {
  -- (its weight low: tapers under a slim head, booms across it, a long needle)
  pylon = { folds = { 4, 4, 6, 8 }, plans = { "low", "low", "middle" }, bodies = { "taper", "taper", "tiers" },
    sides = { "booms", "booms", "band", "fins", "arms", "dish" }, tops = { "spire", "spire", "masts" }, tails = { "needle", "needle", "keel" },
    girth = 0.8, bare = 0.25, many = 0.6 },
  -- (its weight high: a dome and a disc over struts and a thin stem)
  parasol = { folds = { 6, 8, 3, 4 }, plans = { "high", "high", "ends" }, bodies = { "cage", "cage", "taper", "tiers" },
    sides = { "disc", "disc", "torus", "booms", "arms" }, tops = { "dome", "dome", "cap", "spire" }, tails = { "needle", "needle", "weight" },
    girth = 1.0, bare = 0.6, many = 0.7 },
  -- (a working tower: lattice, gantries of panels, a pod off to a side)
  gantry = { folds = { 2, 2, 4, 3 }, plans = { "high", "middle", "beads" }, bodies = { "lattice", "lattice", "pods", "tiers" },
    sides = { "racks", "racks", "arms", "pod", "booms", "dish", "band" }, tops = { "masts", "dish", "spire", "dome" }, tails = { "keel", "spikes", "needle" },
    girth = 0.9, bare = 0.45, many = 1.0 },
  -- (rings on spokes about its bodies)
  ring = { folds = { 3, 4, 6 }, plans = { "middle", "ends", "beads" }, bodies = { "tiers", "tiers", "taper", "pods", "lattice" },
    sides = { "torus", "torus", "torus", "disc", "band", "arms" }, tops = { "dome", "cap", "dish", "spire" }, tails = { "bell", "weight", "needle" },
    girth = 0.9, bare = 0.4, many = 0.8 },
  -- (bodies one on another, close, with decks and fins)
  stack = { folds = { 4, 4, 8, 6 }, plans = { "beads", "low", "middle", "ends" }, bodies = { "tiers", "tiers", "taper", "pods" },
    sides = { "disc", "fins", "band", "arms", "pod" }, tops = { "cap", "masts", "spire" }, tails = { "bell", "keel", "spikes" },
    girth = 1.15, bare = 0.15, many = 0.6 },
  -- (anything: to see how far apart two towers can be)
  mixed = { folds = { 2, 3, 4, 6, 8 }, plans = { "low", "high", "middle", "ends", "beads" },
    bodies = { "tiers", "taper", "cage", "lattice", "pods" },
    sides = { "torus", "disc", "arms", "booms", "racks", "fins", "band", "dish", "pod" },
    tops = { "spire", "dome", "masts", "dish", "cap" }, tails = { "needle", "spikes", "bell", "keel", "weight" },
    girth = 1.0, bare = 0.4, many = 0.8 },
  -- (about a torus, and about a sphere: what is said here is of the
  -- structures at the ends of its spokes, and of what is at its poles)
  toroidal = { folds = { 3, 3, 6, 4, 8 }, plans = { "middle", "middle", "low", "high", "beads" },
    bodies = { "taper", "taper", "tiers", "pods", "cage" }, sides = { "booms", "fins", "band", "disc" },
    tops = { "spire", "dome", "masts", "cap" }, tails = { "needle", "spikes", "keel", "weight" }, girth = 1.0, bare = 0, many = 0 },
  spherical = { folds = { 4, 6, 8, 3 }, plans = { "beads", "beads", "high", "low", "middle", "ends" },
    bodies = { "taper", "tiers", "cage" }, sides = { "booms", "fins", "band", "disc" },
    tops = { "spire", "masts", "dish", "dome" }, tails = { "needle", "spikes", "weight", "keel" }, girth = 1.0, bare = 0, many = 0 },
}

-- The builds a tower can be of, in the order they are shown in.
Tower.BUILDS = { "pylon", "parasol", "gantry", "ring", "stack", "mixed", "toroidal", "spherical" }
-- How many times a thing may be there about the upright, and where a
-- tower's weight may be: what can be said over the seed.
Tower.FOLDS = { 2, 3, 4, 6, 8 }
Tower.PLANS = { "low", "high", "middle", "ends", "beads" }

-- A tower: its seed, how much there is of it (1 to 8), its build and
-- its manner; and, over what the seed says, its fold and its plan.
export type Spec = { seed: number, size: number, build: string, manner: string, fold: number?, plan: string? }

-- How much of a tower's weight is at 't' of the way up it (0 to 1), by
-- its plan; 'index' is which of its bodies that is.
local function weight(plan: string, t: number, index: number): number
  local function about(middle: number): number
    return math.exp(-((t - middle) / 0.24) ^ 2)
  end
  if plan == "low" then
    return about(0.22)
  elseif plan == "high" then
    return about(0.82)
  elseif plan == "middle" then
    return about(0.5)
  elseif plan == "ends" then
    return math.max(about(0.1), about(0.9))
  elseif plan == "beads" then
    return if index % 2 == 1 then 0.9 else 0.25
  end
  return 0.6
end

-- What is being built: the builder, how it is made, how many times a
-- thing is there about the upright, how many sides a solid has, and how
-- thick the stem is.
--
-- Some of a tower moves (the owner, 2026-11-15: "rotating parts, or even
-- solar panels that face the sun. rotating habitation rings, radio
-- antenna dishes, hazard lights, etc."). What moves is drawn as a piece
-- of its own, about a place of its own (its pivot, in the tower's
-- measure), with how it moves: whoever puts the tower in a scene puts
-- each piece there and moves it (Game/View/Starbase's Animate). Pieces
-- are made only where a maker of them is given ('make'): without one,
-- everything is drawn into the one builder, still.
export type Motion = {
  kind: string,        -- "spin", "scan", "track", "blink" or "turn"
  rate: number?,       -- spin and turn: radians a second (spin: about the tower's upright)
  axis: vector?,       -- turn: what it turns about, in the tower's own axes, through its pivot
  toward: vector?,     -- scan: the way it looks at the middle of its sweep
  cone: number?,       -- scan: how far off that it goes, radians
  arm: vector?,        -- track: the way out along its arm, which it turns about to face the sun
  period: number?,     -- scan and blink: seconds for once round
  phase: number?,      -- scan and blink: how far round it starts, 0 to 1
  lit: number?,        -- blink: the share of its period it is lit for
}
export type Piece = { b: Builder, pivot: vector, motion: Motion }
-- (the lamps that blink: in so many groups, each lit in its turn)
type Blink = { groups: { Builder }, count: number }
type Work = { b: Builder, m: Manner, fold: number, sides: number, stem: number, make: (() -> Builder)?, pieces: { Piece }?, blink: Blink? }

-- A solid about the upright through places along it ({ z, out }), as
-- the manner makes one.
local function solid(w: Work, part: number, places: { { number } })
  if w.m.hard then
    prism(w.b, part, w.sides, places)
  else
    skin(w.b, part, places)
  end
end

-- A ring about the upright: 'out' from it, 'thick' through. In as many
-- lengths as the manner has it: a figure of the tower's sides, or round.
local function hoop(w: Work, part: number, z: number, out: number, thick: number)
  local count = if w.m.hard then math.max(8, w.sides * 2) else 24
  for index = 1, count do
    beam(w.b, part, at((index - 0.5) / count * TAU, out, z), at((index + 0.5) / count * TAU, out, z), thick, if w.m.hard then 0.15 else 0.45)
  end
end

-- A flat disc about the upright, 'thick' through at its middle.
local function deck(w: Work, part: number, z: number, out: number, thick: number)
  prism(w.b, part, if w.m.hard then math.max(8, w.sides * 2) else 20, { { z - thick, out * 0.92 }, { z, out }, { z + thick, out * 0.92 } })
end

-- Something that reaches from one place to another, 'wide': braced
-- lattice in a manner of frames, a bowed limb in a poured one, else a
-- bar. ('across' is the way its width lies; 'bow' the way it bows.)
local function limb(w: Work, from: vector, to: vector, wide: number, across: vector, bow: vector?)
  if w.m.frame then
    truss(w.b, from, to, wide, math.max(2, math.floor(vector.magnitude(to - from) / wide / 1.5)), across)
  elseif w.m.bowed and bow then
    local points: { vector } = {}
    for step = 0, 6 do
      local t = step / 6
      points[step + 1] = from + (to - from) * t + bow * (4 * t * (1 - t) * vector.magnitude(to - from) * 0.16)
    end
    Plates.Conduit(w.b, points, wide * 0.3 * w.m.thin)
  else
    beam(w.b, FRAME, from, to, wide * 0.3 * w.m.thin, if w.m.hard then 0.15 else 0.45)
  end
end

-- Lamps round a body: so many, 'out' from the upright.
local function lamps(w: Work, z: number, out: number, count: number, size: number, turn: number?)
  local lit = math.min(size, 0.022)
  for index = 1, count do
    facing(w.b, GLOW, (index - 0.5) / count * TAU + (turn or 0), out, z, v(lit * 0.4, lit, lit * 0.6), 0.3)
  end
end

-- A lamp at a place: a hazard lamp, which blinks where the tower's
-- pieces are being made (in a dark housing, which is what is seen of it
-- when it is not lit), and is else lit and still. One of another paint
-- is that paint's, and still.
local function lamp(w: Work, where: vector, size: number, part: number?)
  local blink = w.blink
  if blink and (part == nil or part == GLOW) then
    blink.count += 1
    block(blink.groups[blink.count % #blink.groups + 1], GLOW, where, v(size, size, size), nil, 0.4)
    block(w.b, FRAME, where, v(size * 0.7, size * 0.7, size * 0.7), nil, 0.4)
  else
    block(w.b, part or GLOW, where, v(size, size, size), nil, 0.4)
  end
end

-- Draw a thing that moves, whose pivot is on the upright at 'z': as a
-- piece of its own, about its own pivot (which 'draw' is told: it is
-- then at no height, and 'apart'), where pieces are being made; else
-- where it is, with the rest.
local function moving(w: Work, z: number, motion: Motion, draw: (w: Work, z: number, apart: boolean) -> ())
  local make, pieces = w.make, w.pieces
  if make and pieces then
    local piece: Piece = { b = make(), pivot = axis(z), motion = motion }
    table.insert(pieces, piece)
    local mine: Work = { b = piece.b, m = w.m, fold = w.fold, sides = w.sides, stem = w.stem }
    local keptX, keptY = asideX, asideY
    asideX, asideY = 0, 0
    draw(mine, 0, true)
    asideX, asideY = keptX, keptY
  else
    draw(w, z, false)
  end
end

-- ---------------------------------------------------------------------
-- Bodies: each from 'low' to 'high' along the upright, 'out' from it at
-- its widest; 'up' is whether it is in the upper half of the tower (a
-- thing that narrows, narrows away from the middle).

-- Tiers: boxes one on another; or drums; or, in a manner of frames, a
-- core in a frame of posts and decks.
local function tiers(w: Work, rng: RNG, low: number, high: number, out: number, up: boolean)
  local count = rng:Int(1, 3)
  local each = (high - low) / count
  local corner = TAU / w.sides / 2
  for tier = 1, count do
    local from = low + (tier - 1) * each
    -- (each tier its own girth: stepping in away from the tower's middle, more often than not)
    local step = if up then tier - 1 else count - tier
    local wide = out * (1 - 0.16 * step * rng:Float(0.4, 1.3)) * rng:Float(0.9, 1.05)
    local part = if rng:Int(1, 4) == 1 then PATCH else PLATING
    local lit = chance(rng, 0.6)
    local where, rows = rng:Float(0.3, 0.7), rng:Int(1, 2)
    if w.m.frame then
      -- (a core, and a deck under it out to the posts)
      local core = wide * 0.62
      prism(w.b, part, w.sides, { { from + each * 0.1, core }, { from + each * 0.9, core } })
      deck(w, PATCH, from + 0.01, wide, 0.012)
      if lit then
        lamps(w, from + each * where, core, w.sides * rows, each * 0.05, corner)
      end
    elseif w.m.hard then
      if w.sides == 4 then
        block(w.b, part, axis(from + each / 2), v(wide, wide, each / 2 - 0.012), nil, w.m.ease)
      else
        prism(w.b, part, w.sides, { { from + 0.012, wide }, { from + each - 0.012, wide } })
      end
      -- (a dark joint between two tiers)
      if tier > 1 then
        block(w.b, FRAME, axis(from), v(wide * 0.8, wide * 0.8, 0.014), nil, 0.1)
      end
      if lit then
        lamps(w, from + each * where, wide, w.sides * rows, each * 0.05, if w.sides == 4 then TAU / 8 else corner)
      end
    else
      -- (a drum, and every other one slimmer)
      local drum = if count > 1 and tier % 2 == 0 then wide * 0.72 else wide
      skin(w.b, part, { { from, drum * 0.82 }, { from + each * 0.12, drum }, { from + each * 0.88, drum }, { from + each, drum * 0.82 } })
      hoop(w, FRAME, from + each * 0.25, drum * 1.01, drum * 0.03)
      hoop(w, FRAME, from + each * 0.75, drum * 1.01, drum * 0.03)
      if lit then
        lamps(w, from + each * 0.5, drum * 0.99, 8, each * 0.04)
      end
    end
  end
  if w.m.frame then
    -- (the posts, the whole length of it, and a deck over the last tier)
    for index = 1, w.sides do
      local angle = (index - 0.5) / w.sides * TAU
      beam(w.b, FRAME, at(angle, out * 0.94, low), at(angle, out * 0.94, high), out * 0.035)
    end
    deck(w, PATCH, high - 0.01, out, 0.012)
  end
end

-- A taper: wide at a shoulder near the tower's middle, drawn in away
-- from it. Faceted; or a bulb.
local function taper(w: Work, rng: RNG, low: number, high: number, out: number, up: boolean)
  local long = high - low
  local shoulder, narrow = rng:Float(0.15, 0.3), rng:Float(0.25, 0.55)
  local way = if up then 1 else -1
  local wide = if up then low else high
  local belt = wide + way * long * shoulder
  if w.m.hard then
    local far = wide + way * long
    local places = { { wide, out * 0.8 }, { belt, out }, { far - way * long * 0.08, out * narrow }, { far, out * narrow * 0.8 } }
    if not up then
      places = { places[4], places[3], places[2], places[1] }
    end
    prism(w.b, PLATING, w.sides, places)
    if w.m.frame then
      -- (ribs outside it, from its shoulder to its narrow end)
      for index = 1, w.sides do
        local angle = (index - 0.5) / w.sides * TAU
        beam(w.b, FRAME, at(angle, out * 1.12, belt), at(angle, out * narrow * 1.15, far - way * long * 0.08), out * 0.03)
      end
    end
  else
    local fat = shoulder + 0.12
    local places = { { wide, out * 0.5 }, { wide + way * long * fat, out }, { wide + way * long * 0.7, out * 0.7 }, { wide + way * long, out * 0.22 } }
    if not up then
      places = { places[4], places[3], places[2], places[1] }
    end
    skin(w.b, PLATING, places)
    belt = wide + way * long * fat
  end
  hoop(w, TRIM, belt, out * 1.0, out * 0.035)
  lamps(w, belt + way * long * 0.12, out * 0.93, math.max(6, w.sides), long * 0.02)
end

-- A cage: struts from a hoop at its wide end, out and in to the stem at
-- the other, about something small on the stem.
local function cage(w: Work, rng: RNG, low: number, high: number, out: number, up: boolean)
  local long = high - low
  local count = math.max(3, w.fold)
  local wide = if up then low else high
  local way = if up then 1 else -1
  local belly = rng:Float(0.9, 1.25)
  -- (bowed all the way, or in two straight lengths)
  local steps = if w.m.hard then 2 else 6
  for index = 1, count do
    local angle = (index - 0.5) / count * TAU
    local points: { vector } = {}
    for step = 0, steps do
      local t = step / steps
      -- (out at the hoop, a belly part of the way along, in to the stem)
      local far = out * ((1 - t) ^ 1.6 + 1.6 * t * (1 - t) * belly) + w.stem * 1.2 * t
      points[step + 1] = at(angle, far, wide + way * long * t)
    end
    Plates.Conduit(w.b, points, out * 0.035 * w.m.thin)
  end
  hoop(w, PLATING, wide, out, out * 0.06)
  hoop(w, FRAME, wide + way * long * 0.5, out * (0.25 + 0.4 * belly), out * 0.022 * w.m.thin)
  local core = out * rng:Float(0.22, 0.34)
  local middle = low + long * 0.45
  if w.m.hard then
    prism(w.b, PATCH, w.sides, { { middle - core * 1.2, core * 0.7 }, { middle - core * 0.6, core }, { middle + core * 0.6, core }, { middle + core * 1.2, core * 0.7 } })
  else
    skin(w.b, PATCH, { { middle - core * 1.4, core * 0.5 }, { middle, core }, { middle + core * 1.4, core * 0.5 } })
  end
  lamps(w, middle, core * 0.98, 6, long * 0.015)
end

-- Lattice: girders up it, decks across it, and a thing carried inside.
local function lattice(w: Work, rng: RNG, low: number, high: number, out: number, up: boolean)
  local count = math.clamp(w.fold, 3, 4)
  local far = out * 0.72
  local long = high - low
  for index = 1, count do
    local angle = (index - 0.5) / count * TAU
    if w.m.hard then
      truss(w.b, at(angle, far, low), at(angle, far, high), out * 0.3, math.max(2, math.floor(long / (out * 0.5))), around(angle + TAU / 4, 1))
    else
      limb(w, at(angle, far, low), at(angle, far, high), out * 0.2, around(angle + TAU / 4, 1), around(angle, 1))
    end
  end
  local middle = low + long * rng:Float(0.35, 0.65)
  for _, z in { low, high, middle } do
    if w.m.hard then
      deck(w, PATCH, z, out * 0.86, 0.012)
    else
      hoop(w, PATCH, z, far, out * 0.05)
    end
  end
  local inside = out * rng:Float(0.32, 0.46)
  local from = low + long * rng:Float(0.1, 0.4)
  if w.m.hard then
    block(w.b, PLATING, axis(from + inside), v(inside, inside, inside), nil, w.m.ease)
    lamps(w, from + inside, inside, 4, inside * 0.12, TAU / 8)
  else
    skin(w.b, PLATING, { { from, inside * 0.5 }, { from + inside, inside }, { from + inside * 2, inside * 0.5 } })
    lamps(w, from + inside, inside * 0.98, 6, inside * 0.1)
  end
  local _ = up
end

-- Pods: so many of a thing strapped round the stem.
local function pods(w: Work, rng: RNG, low: number, high: number, out: number, up: boolean)
  local count = math.clamp(w.fold, 2, 6)
  local long = high - low
  local fat = out * math.min(0.42, 1.5 / count)
  local far = out - fat
  local from, to = low + long * 0.06, high - long * 0.06
  for index = 1, count do
    local angle = (index - 0.5) / count * TAU
    local part = if index % 2 == 0 then PATCH else PLATING
    if w.m.hard then
      facing(w.b, part, angle, far, (from + to) / 2, v(fat * 0.8, fat * 0.8, (to - from) / 2), w.m.ease)
    else
      skin(w.b, part, { { from, fat * 0.5 }, { from + (to - from) * 0.2, fat }, { from + (to - from) * 0.8, fat }, { to, fat * 0.5 } },
        math.cos(angle) * far, math.sin(angle) * far)
    end
    -- (held to the stem at two places)
    for _, share in { 0.3, 0.7 } do
      beam(w.b, FRAME, axis(low + long * share), at(angle, far, low + long * share), fat * 0.14 * w.m.thin)
    end
  end
  hoop(w, TRIM, low + long * 0.5, far + fat * 0.2, fat * 0.07)
  if chance(rng, 0.5) then
    lamps(w, low + long * 0.5, out * (if w.m.hard then 0.9 else 1.0), count, long * 0.03)
  end
  local _ = up
end

local BODIES: { [string]: (w: Work, rng: RNG, low: number, high: number, out: number, up: boolean) -> () } = {
  tiers = tiers, taper = taper, cage = cage, lattice = lattice, pods = pods,
}

-- ---------------------------------------------------------------------
-- Sides: what stands out sideways at 'z', where the tower is 'out' from
-- the upright; 'reach' is how far a thing of this tower may stand out.

-- (how many arms a tower of a fold has: two, three or four)
local function armsOf(fold: number): number
  return if fold > 4 then fold // 2 else math.max(2, fold)
end

local function torus(w: Work, rng: RNG, z: number, out: number, reach: number)
  local far = math.max(out * 1.5, reach * rng:Float(0.55, 1.0))
  local thick = far * rng:Float(0.07, 0.13)
  hoop(w, PLATING, z, far, thick)
  -- (a second, slimmer one beside it, now and then)
  if chance(rng, 0.3) then
    hoop(w, PATCH, z + thick * 2.6, far * 0.94, thick * 0.6)
  end
  local spokes = math.max(3, w.fold)
  for index = 1, spokes do
    local angle = (index - 0.5) / spokes * TAU
    limb(w, at(angle, out * 0.5, z), at(angle, far, z), thick * 1.1, v(0, 0, 1), v(0, 0, 1))
  end
  lamps(w, z, far + thick * 0.95, 12, thick * 0.3)
end

local function disc(w: Work, rng: RNG, z: number, out: number, reach: number)
  local far = math.max(out * 1.4, reach * rng:Float(0.5, 0.95))
  local thick = far * rng:Float(0.03, 0.06)
  deck(w, PLATING, z, far, thick)
  hoop(w, TRIM, z, far * 1.0, thick * 0.5)
  -- (posts at its rim, hanging or standing, with a lamp at the end of each)
  local posts = math.max(3, w.fold)
  local way = if chance(rng, 0.5) then 1 else -1
  local long = far * rng:Float(0.12, 0.3)
  for index = 1, posts do
    local angle = (index - 0.5) / posts * TAU
    beam(w.b, FRAME, at(angle, far * 0.9, z), at(angle, far * 0.9, z + way * long), thick * 0.4 * w.m.thin)
    lamp(w, at(angle, far * 0.9, z + way * (long + thick * 0.4)), thick * 0.45)
  end
end

local function arms(w: Work, rng: RNG, z: number, out: number, reach: number)
  local count = armsOf(w.fold)
  local long = reach * rng:Float(0.6, 1.1)
  local wide = reach * rng:Float(0.07, 0.11)
  local ends = rng:Int(1, 3)
  for index = 1, count do
    local angle = (index - 0.5) / count * TAU
    limb(w, at(angle, out * 0.6, z), at(angle, long, z), wide, v(0, 0, 1), v(0, 0, 1))
    if ends == 1 then
      -- (a pod at its end)
      local fat = wide * 1.5
      if w.m.hard then
        facing(w.b, PLATING, angle, long + fat * 0.6, z, v(fat * 0.8, fat * 0.8, fat * 1.6), w.m.ease)
      else
        skin(w.b, PLATING, { { z - fat * 1.8, fat * 0.5 }, { z - fat * 0.9, fat }, { z + fat * 0.9, fat }, { z + fat * 1.8, fat * 0.5 } },
          math.cos(angle) * (long + fat * 0.6), math.sin(angle) * (long + fat * 0.6))
      end
      facing(w.b, GLOW, angle, long + fat * 1.6, z, v(fat * 0.1, fat * 0.3, fat * 0.5), 0.3)
    elseif ends == 2 then
      -- (a block, where something is berthed)
      facing(w.b, PATCH, angle, long + wide, z, v(wide * 1.2, wide * 1.6, wide * 0.9), w.m.ease)
      facing(w.b, TRIM, angle, long + wide * 2.2, z, v(wide * 0.1, wide * 1.6, wide * 0.3), 0.1)
    else
      -- (a mast across it, and a lamp)
      beam(w.b, FRAME, at(angle, long, z - wide * 3), at(angle, long, z + wide * 3), wide * 0.16)
      lamp(w, at(angle, long, z + wide * 3.2), wide * 0.2)
    end
  end
end

local function booms(w: Work, rng: RNG, z: number, out: number, reach: number)
  local count = if chance(rng, 0.4) then 2 else armsOf(w.fold)
  -- (all of a length, or each its own)
  local alike = chance(rng, 0.5)
  local long = reach * rng:Float(0.8, 1.5)
  local thick = reach * 0.022 * w.m.thin
  for index = 1, count do
    local angle = (index - 0.5) / count * TAU
    local far = if alike then long else long * rng:Float(0.45, 1.1)
    beam(w.b, FRAME, at(angle, out * 0.4, z), at(angle, far, z), thick)
    -- (spars across it, shorter toward its end)
    for spar = 1, rng:Int(1, 3) do
      local where = far * (0.45 + 0.17 * spar)
      local half = reach * (0.16 - 0.035 * spar)
      beam(w.b, FRAME, at(angle, where, z - half), at(angle, where, z + half), thick * 0.6)
    end
    lamp(w, at(angle, far + thick, z), thick * 1.3)
  end
end

local function racks(w: Work, rng: RNG, z: number, out: number, reach: number)
  local count = if w.fold == 3 then 3 elseif w.fold >= 4 and chance(rng, 0.4) then 4 else 2
  local long = reach * rng:Float(0.9, 1.4)
  local panels = rng:Int(2, 4)
  local tall = reach * rng:Float(0.16, 0.3)
  -- (the panels stand edge on to the tower, or lie flat to its upright:
  -- where they are still. Where they move, each arm turns about itself
  -- to put its panels' faces to the sun)
  local flat = chance(rng, 0.35)
  local function arm(mine: Work, angle: number, level: number, lying: boolean)
    beam(mine.b, FRAME, at(angle, out * 0.5, level), at(angle, long, level), reach * 0.028 * mine.m.thin)
    local first = math.max(out * 1.3, long * 0.35)
    local each = (long - first) / panels
    for panel = 1, panels do
      local where = first + (panel - 0.5) * each
      for _, side in { 1, -1 } do
        local off = side * (tall * 0.55 + reach * 0.03)
        if lying then
          block(mine.b, PATCH, at(angle, where, level) + around(angle + TAU / 4, off), v(each * 0.44, tall * 0.5, 0.008), v(0, 0, angle), 0.05)
        else
          facing(mine.b, PATCH, angle, where, level + off, v(each * 0.44, 0.008, tall * 0.5), 0.05)
        end
      end
    end
    lamp(mine, at(angle, long + reach * 0.03, level), reach * 0.025)
  end
  for index = 1, count do
    local angle = (index - 0.5) / count * TAU
    moving(w, z, { kind = "track", arm = around(angle, 1) }, function(mine: Work, level: number, apart: boolean)
      -- (apart, it is drawn along its own x, its panels' faces to its own y: Starbase.Animate turns it from there)
      arm(mine, if apart then 0 else angle, level, flat and not apart)
    end)
  end
end

local function fins(w: Work, rng: RNG, z: number, out: number, reach: number)
  local count = math.max(3, w.fold)
  local wide = reach * rng:Float(0.3, 0.6)
  local tall = reach * rng:Float(0.25, 0.7)
  for index = 1, count do
    local angle = (index - 0.5) / count * TAU
    facing(w.b, PLATING, angle, out * 0.7 + wide * 0.5, z, v(wide * 0.5, reach * 0.022 * w.m.thin, tall * 0.5), if w.m.hard then 0.05 else 0.4)
    facing(w.b, TRIM, angle, out * 0.7 + wide, z, v(reach * 0.012, reach * 0.028 * w.m.thin, tall * 0.5), 0.05)
  end
end

-- (the grown towers' lit band between two collars, where ships moor: here one thing a tower may have)
local function band(w: Work, rng: RNG, z: number, out: number, reach: number)
  local wide = math.max(out * 1.12, reach * 0.3)
  local gap = wide * rng:Float(0.12, 0.2)
  deck(w, TRIM, z + gap, wide, 0.02)
  deck(w, GLOW, z, wide * 0.93, 0.014)
  deck(w, TRIM, z - gap, wide, 0.02)
end

-- The bowl of a dish on the upright: from 'z', looking the 'way' along
-- it (1 up, -1 down), 'wide' at its rim and 'deep', with its feed out
-- in front of it.
local function bowl(w: Work, z: number, way: number, wide: number, deep: number)
  prism(w.b, PATCH, 16, { { z, wide * 0.1 }, { z + way * deep * 0.55, wide * 0.7 }, { z + way * deep, wide } })
  hoop(w, TRIM, z + way * deep, wide, wide * 0.03)
  beam(w.b, FRAME, axis(z + way * deep * 0.1), axis(z + way * deep * 1.8), wide * 0.035)
  lamp(w, axis(z + way * deep * 1.8), wide * 0.06)
end

-- (a dish on an arm, looking up the tower or down it, and out a little:
-- where it moves, it goes slowly round about where it looks. Nothing
-- answers it across the tower)
local function dish(w: Work, rng: RNG, z: number, out: number, reach: number)
  local angle = rng:Float(0, TAU)
  local far = out * 0.6 + reach * rng:Float(0.5, 0.9)
  local wide = reach * rng:Float(0.22, 0.38)
  local way = if chance(rng, 0.7) then 1 else -1
  local deep = wide * rng:Float(0.3, 0.45)
  local slow = rng:Float(0, 1)
  limb(w, at(angle, out * 0.5, z), at(angle, far, z), wide * 0.3, v(0, 0, 1), v(0, 0, 1))
  -- (the bowl is about an upright of its own, at the arm's end)
  local keptX, keptY = asideX, asideY
  asideX, asideY = keptX + math.cos(angle) * far, keptY + math.sin(angle) * far
  local toward = vector.normalize(v(0, 0, way) * math.cos(0.6) + around(angle, 1) * math.sin(0.6))
  moving(w, z + way * deep * 0.15, { kind = "scan", toward = toward, cone = 0.3, period = 45 + 30 * slow, phase = slow },
    function(mine: Work, level: number, apart: boolean)
      -- (apart, it looks up its own z: Starbase.Animate points it)
      bowl(mine, level, if apart then 1 else way, wide, deep * 0.85)
    end)
  asideX, asideY = keptX, keptY
end

-- (one thing, off to one side: nothing answers it across the tower)
local function pod(w: Work, rng: RNG, z: number, out: number, reach: number)
  local angle = rng:Float(0, TAU)
  local fat = reach * rng:Float(0.22, 0.4)
  local long = fat * rng:Float(1.6, 3.2)
  local far = out * 0.6 + fat * rng:Float(1.0, 1.6)
  if w.m.hard then
    facing(w.b, PLATING, angle, far, z, v(fat * 0.8, fat * 0.8, long * 0.42), w.m.ease)
    facing(w.b, PATCH, angle, far, z + long * 0.46, v(fat * 0.55, fat * 0.55, long * 0.08), w.m.ease)
  else
    skin(w.b, PLATING, { { z - long / 2, fat * 0.4 }, { z - long * 0.25, fat }, { z + long * 0.2, fat * 0.9 }, { z + long / 2, fat * 0.35 } },
      math.cos(angle) * far, math.sin(angle) * far)
  end
  for _, share in { -0.2, 0.15 } do
    limb(w, axis(z + long * share), at(angle, far, z + long * share), fat * 0.25, v(0, 0, 1), nil)
  end
  facing(w.b, GLOW, angle, far + fat * (if w.m.hard then 0.82 else 0.98), z, v(fat * 0.05, fat * 0.5, long * 0.04), 0.3)
end

local SIDES: { [string]: (w: Work, rng: RNG, z: number, out: number, reach: number) -> () } = {
  torus = torus, disc = disc, arms = arms, booms = booms, racks = racks, fins = fins, band = band, dish = dish, pod = pod,
}

-- Stand a thing out of a tower. (A ring on spokes turns about the
-- upright, spokes and all, where the tower's pieces are being made:
-- one way, and the next the other.)
local function stand(w: Work, kind: string, rng: RNG, z: number, out: number, reach: number)
  if kind == "torus" then
    local pieces = w.pieces
    moving(w, z, { kind = "spin", rate = (if pieces and #pieces % 2 == 1 then -1 else 1) * 0.14 }, function(mine: Work, level: number)
      SIDES.torus(mine, rng, level, out, reach)
    end)
  else
    SIDES[kind](w, rng, z, out, reach)
  end
end

-- ---------------------------------------------------------------------
-- Ends: a top from 'z' upward and a tail from 'z' downward, where the
-- tower is 'out' from the upright.

local function top(w: Work, rng: RNG, kind: string, z: number, out: number, reach: number)
  if kind == "dome" then
    local wide = math.max(out, reach * rng:Float(0.3, 0.6))
    local tall = wide * rng:Float(0.5, 1.0)
    solid(w, PLATING, { { z - tall * 0.3, wide * 0.96 }, { z, wide }, { z + tall * 0.6, wide * 0.7 }, { z + tall, wide * 0.2 } })
    hoop(w, TRIM, z - tall * 0.05, wide * 1.0, wide * 0.035)
    beam(w.b, FRAME, axis(z + tall), axis(z + tall * 1.5), w.stem * 0.5)
    lamp(w, axis(z + tall * 1.5), w.stem * 0.8)
  elseif kind == "masts" then
    for index = 1, rng:Int(3, 6) do
      local angle = rng:Float(0, TAU)
      local far = out * rng:Float(0.15, 0.8)
      local long = reach * rng:Float(0.5, 1.6)
      beam(w.b, FRAME, at(angle, far, z - 0.05), at(angle, far, z + long), w.stem * 0.3)
      for spar = 1, rng:Int(0, 2) do
        local half = around(angle + TAU / 4, long * (0.16 - 0.05 * spar))
        local where = at(angle, far, z + long * (0.5 + 0.2 * spar))
        beam(w.b, FRAME, where - half, where + half, w.stem * 0.2)
      end
      lamp(w, at(angle, far, z + long), w.stem * 0.45, if index == 1 then GLOW else TRIM)
    end
  elseif kind == "dish" then
    local wide = math.max(out * 1.1, reach * rng:Float(0.35, 0.6))
    local deep = wide * rng:Float(0.3, 0.5)
    local slow = rng:Float(0, 1)
    beam(w.b, FRAME, axis(z), axis(z + deep * 0.5), w.stem)
    -- (looking up the tower: where it moves, it goes slowly round about that)
    moving(w, z + deep * 0.4, { kind = "scan", toward = v(0, 0, 1), cone = 0.25, period = 50 + 30 * slow, phase = slow },
      function(mine: Work, level: number)
        bowl(mine, level, 1, wide, deep * 0.6)
      end)
  elseif kind == "cap" then
    local wide = math.max(out * 1.25, reach * rng:Float(0.3, 0.55))
    prism(w.b, PLATING, if w.m.hard then math.max(8, w.sides * 2) else 20, { { z, wide * 0.7 }, { z + wide * 0.08, wide }, { z + wide * 0.16, wide * 0.94 } })
    lamps(w, z + wide * 0.08, wide * 1.0, 12, wide * 0.02)
    beam(w.b, FRAME, axis(z + wide * 0.16), axis(z + wide * 0.6), w.stem * 0.5)
    lamp(w, axis(z + wide * 0.6), w.stem * 0.8)
  else
    -- (a spire: thinner by steps, with a lamp at its head)
    local long = reach * rng:Float(0.9, 2.0)
    local thick, from = w.stem * 1.6, z
    for _ = 1, 3 do
      block(w.b, PLATING, axis(from + long / 6), v(thick, thick, long / 6), nil, 0.3)
      from += long / 3
      thick *= 0.55
    end
    lamp(w, axis(z + long), w.stem * 0.7)
  end
end

local function tail(w: Work, rng: RNG, kind: string, z: number, out: number, reach: number)
  if kind == "spikes" then
    for index = 1, 3 do
      local angle = (index - 0.5) / 3 * TAU
      local long = reach * rng:Float(0.6, 1.8)
      beam(w.b, FRAME, at(angle, out * 0.35, z + 0.05), at(angle, out * 0.2, z - long), w.stem * 0.45)
      lamp(w, at(angle, out * 0.2, z - long), w.stem * 0.5, if index == 1 then GLOW else TRIM)
    end
  elseif kind == "bell" then
    -- (drawn in to a throat and out again a little, about a spike that
    -- goes on down past it: not a foot, which nothing here has)
    local wide = math.max(out * 0.7, reach * rng:Float(0.2, 0.34))
    local long = wide * rng:Float(1.2, 2.0)
    prism(w.b, PATCH, if w.m.hard then math.max(8, w.sides * 2) else 16,
      { { z - long, wide * 0.5 }, { z - long * 0.7, wide * 0.32 }, { z - long * 0.2, wide * 0.8 }, { z, wide * 0.6 } })
    hoop(w, TRIM, z - long, wide * 0.5, wide * 0.035)
    local spike = long * rng:Float(0.8, 1.6)
    beam(w.b, FRAME, axis(z - long * 0.9), axis(z - long - spike), w.stem * 0.7)
    lamp(w, axis(z - long - spike), w.stem * 0.7)
  elseif kind == "keel" then
    local long = reach * rng:Float(1.2, 2.4)
    beam(w.b, PLATING, axis(z), axis(z - long), w.stem * 1.1)
    -- (a spar across its end, and a lamp under it)
    local half = reach * rng:Float(0.15, 0.4)
    beam(w.b, FRAME, axis(z - long * 0.9) - v(half, 0, 0), axis(z - long * 0.9) + v(half, 0, 0), w.stem * 0.4)
    lamp(w, axis(z - long - w.stem), w.stem * 0.8)
  elseif kind == "weight" then
    -- (a weight hung under it on the stem)
    local drop = reach * rng:Float(0.4, 1.0)
    local fat = math.max(out * 0.6, reach * rng:Float(0.15, 0.3))
    beam(w.b, FRAME, axis(z + 0.02), axis(z - drop - fat * 0.6), w.stem * 0.8)
    solid(w, PATCH, { { z - drop - fat * 2.4, fat * 0.2 }, { z - drop - fat * 1.4, fat }, { z - drop - fat * 0.6, fat * 0.8 }, { z - drop, fat * 0.3 } })
    lamp(w, axis(z - drop - fat * 2.5), w.stem * 0.7)
  else
    -- (a needle: long, and to a point)
    local long = reach * rng:Float(1.6, 3.2)
    local thick = math.max(w.stem * 1.8, out * 0.3)
    prism(w.b, PLATING, if w.m.hard then w.sides else 10, { { z - long, 0.004 }, { z - long * 0.25, thick * 0.7 }, { z, thick } })
    hoop(w, TRIM, z - long * 0.25, thick * 0.72, thick * 0.08)
  end
end

-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- A torus and a sphere, and what stands on them: for the peoples whose
-- towers are not a stem with things along it. (The owner, 2026-11-15:
-- "The 2 alien factions in k-space (i.e. not the drowned) will have a
-- torus and a sphere as their bases": the Vail a torus, with "spokes
-- from the torus with structures at their ends (not station modules for
-- now)"; the Nimia a sphere, with "antennas and towers rising from it,
-- and maybe even hab domes with visible terrain (could use snippets
-- from the temperate planets)". The domes here have plain ground under
-- them: a planet's ground wants a second paint on one model, which a
-- tower has not got yet.)

-- A list in an order the dice say.
local function shuffled(rng: RNG, list: { string }): { string }
  local mixed = table.clone(list)
  for index = #mixed, 2, -1 do
    local other = rng:Int(1, index)
    mixed[index], mixed[other] = mixed[other], mixed[index]
  end
  return mixed
end

-- Two ways across a way: for laying a thing out about a line that is
-- not the upright.
local function across(way: vector): (vector, vector)
  local aside = if math.abs(way.z) > 0.9 then v(1, 0, 0) else v(0, 0, 1)
  local one = vector.normalize(vector.cross(way, aside))
  return one, vector.cross(way, one)
end

-- A wheel about the upright at 'z', in one piece: its tube 'thick' in
-- radius, the middle of the tube 'out' from the upright. One round skin;
-- or, in plate, of so many straight lengths with so many faces to its
-- tube; or, in a manner of frames, three rails braced to one another.
local function wheel(w: Work, part: number, z: number, out: number, thick: number, lengths: number, faces: number)
  local b = w.b
  if w.m.frame then
    local rails = { { out + thick, z }, { out - thick * 0.6, z + thick * 0.9 }, { out - thick * 0.6, z - thick * 0.9 } }
    local count = math.max(12, lengths)
    for index = 1, count do
      local a0, a1 = (index - 1) / count * TAU, index / count * TAU
      for rail, here in rails do
        local there = rails[rail % 3 + 1]
        beam(b, FRAME, at(a0, here[1], here[2]), at(a1, here[1], here[2]), thick * 0.09)
        beam(b, FRAME, at(a0, here[1], here[2]), at(a0, there[1], there[2]), thick * 0.06)
        beam(b, FRAME, at(a0, here[1], here[2]), at(a1, there[1], there[2]), thick * 0.05)
      end
      -- (and every third length of it is closed in: a cabin)
      if index % 3 == 0 then
        local middle = (a0 + a1) / 2
        facing(b, part, middle, out, z, v(thick * 0.6, out * (a1 - a0) * 0.42, thick * 0.6), w.m.ease)
      end
    end
  elseif w.m.hard then
    for index = 1, lengths do
      local a0, a1 = (index - 1) / lengths * TAU, index / lengths * TAU
      local middle = (at(a0, out, z) + at(a1, out, z)) / 2
      for face = 1, faces do
        local f0, f1 = (face - 0.5) / faces * TAU, (face + 0.5) / faces * TAU
        local p1 = at(a0, out + thick * math.cos(f0), z + thick * math.sin(f0))
        local p2 = at(a1, out + thick * math.cos(f0), z + thick * math.sin(f0))
        local p3 = at(a1, out + thick * math.cos(f1), z + thick * math.sin(f1))
        local p4 = at(a0, out + thick * math.cos(f1), z + thick * math.sin(f1))
        Plates.Flat(b, part, { p1, p2, p3, p4 }, (p1 + p2 + p3 + p4) / 4 - middle)
      end
    end
  else
    local round, about = 48, 14
    local points: { number } = {}
    for i = 0, round - 1 do
      for j = 0, about - 1 do
        local p = at(i / round * TAU, out + thick * math.cos(j / about * TAU), z + thick * math.sin(j / about * TAU))
        table.insert(points, p.x)
        table.insert(points, p.y)
        table.insert(points, p.z)
      end
    end
    local function id(i: number, j: number): number
      return (i % round) * about + (j % about) + 1
    end
    local corners3: { number } = {}
    for i = 0, round - 1 do
      for j = 0, about - 1 do
        local a, c, d, e = id(i, j), id(i + 1, j), id(i + 1, j + 1), id(i, j + 1)
        for _, corner in { a, c, d, a, d, e } do
          table.insert(corners3, corner)
        end
      end
    end
    Plates.Skin(b, part, points, corners3)
  end
end

-- A ball on the upright at 'z'. One round skin; or, in plate, faceted,
-- of so many lengths round it; or, in a manner of frames, a cage of
-- ribs about a core.
local function ball(w: Work, part: number, z: number, radius: number, lengths: number)
  local b = w.b
  local function faceted(far: number, round: number, bands: number)
    local centre = axis(z)
    for band = 1, bands do
      local l0, l1 = ((band - 1) / bands - 0.5) * math.pi, (band / bands - 0.5) * math.pi
      for index = 1, round do
        local a0, a1 = (index - 1) / round * TAU, index / round * TAU
        local plate: { vector }
        if band == 1 then
          plate = { axis(z - far), at(a0, far * math.cos(l1), z + far * math.sin(l1)), at(a1, far * math.cos(l1), z + far * math.sin(l1)) }
        elseif band == bands then
          plate = { at(a0, far * math.cos(l0), z + far * math.sin(l0)), at(a1, far * math.cos(l0), z + far * math.sin(l0)), axis(z + far) }
        else
          plate = { at(a0, far * math.cos(l0), z + far * math.sin(l0)), at(a1, far * math.cos(l0), z + far * math.sin(l0)),
            at(a1, far * math.cos(l1), z + far * math.sin(l1)), at(a0, far * math.cos(l1), z + far * math.sin(l1)) }
        end
        local middle = v(0, 0, 0)
        for _, p in plate do
          middle += p
        end
        Plates.Flat(b, part, plate, middle / #plate - centre)
      end
    end
  end
  if w.m.frame then
    local ribs = math.max(6, lengths)
    for index = 1, ribs do
      local angle = (index - 0.5) / ribs * TAU
      local points: { vector } = {}
      for step = 0, 12 do
        local up = (step / 12 - 0.5) * math.pi
        points[step + 1] = at(angle, radius * math.cos(up), z + radius * math.sin(up))
      end
      Plates.Conduit(b, points, radius * 0.02)
    end
    for _, up in { -0.95, -0.5, 0, 0.5, 0.95 } do
      hoop(w, FRAME, z + radius * math.sin(up), radius * math.cos(up), radius * 0.018)
    end
    faceted(radius * 0.56, math.max(6, lengths), 4)
    for index = 1, ribs do
      local angle = (index - 0.5) / ribs * TAU
      beam(b, FRAME, at(angle, radius * 0.5, z), at(angle, radius, z), radius * 0.015)
    end
  elseif w.m.hard then
    faceted(radius, math.max(8, lengths), 6)
  else
    local round, bands = 32, 16
    local points: { number } = { asideX, asideY, z - radius }
    for band = 1, bands - 1 do
      local up = (band / bands - 0.5) * math.pi
      for i = 0, round - 1 do
        local p = at(i / round * TAU, radius * math.cos(up), z + radius * math.sin(up))
        table.insert(points, p.x)
        table.insert(points, p.y)
        table.insert(points, p.z)
      end
    end
    table.insert(points, asideX)
    table.insert(points, asideY)
    table.insert(points, z + radius)
    local last = 2 + (bands - 1) * round
    local function id(i: number, band: number): number
      return if band <= 0 then 1 elseif band >= bands then last else 2 + (band - 1) * round + (i % round)
    end
    local corners3: { number } = {}
    for band = 0, bands - 1 do
      for i = 0, round - 1 do
        local a, c, d, e = id(i, band), id(i + 1, band), id(i + 1, band + 1), id(i, band + 1)
        if band > 0 then
          for _, corner in { a, c, d } do
            table.insert(corners3, corner)
          end
        end
        if band < bands - 1 then
          for _, corner in { a, d, e } do
            table.insert(corners3, corner)
          end
        end
      end
    end
    Plates.Skin(b, part, points, corners3)
  end
end

-- Something standing straight out of a surface: from 'foot', the 'way'
-- it stands, so 'long' and so 'thick' at its foot, in lengths each
-- thinner than the last, with a lamp at its head. A slim one has spars
-- across it (an antenna); a stout one a collar and lit ports (a tower).
local function spike(w: Work, rng: RNG, foot: vector, way: vector, long: number, thick: number)
  local shares: { number } = if rng:Int(1, 2) == 1 then { 0.5, 0.3, 0.2 } else { 0.62, 0.38 }
  local parts = { PLATING, PATCH, FRAME }
  local from, girth = foot - way * thick, thick
  local one, other = across(way)
  local slim = thick < long * 0.05
  for index, share in shares do
    local reach = long * share
    beam(w.b, if slim then FRAME else parts[index], from, from + way * (reach + thick), girth, if w.m.hard then 0.12 else 0.4)
    if index == 1 and not slim then
      -- (a collar where it steps in, and ports under it)
      beam(w.b, TRIM, from + way * (reach + thick * 0.7), from + way * (reach + thick), girth * 1.25, 0.1)
      for _, side in { one, other, -one, -other } do
        block(w.b, GLOW, from + way * (reach * 0.6 + thick) + side * girth, v(girth * 0.14, girth * 0.14, girth * 0.14), nil, 0.4)
      end
    end
    from += way * (reach + thick * 0.2)
    girth *= 0.55
  end
  local head = foot + way * long
  if slim then
    for spar = 1, rng:Int(1, 3) do
      local where = foot + way * (long * (0.45 + 0.15 * spar))
      local half = long * (0.14 - 0.03 * spar)
      beam(w.b, FRAME, where - one * half, where + one * half, thick * 0.6)
      if spar == 1 then
        beam(w.b, FRAME, where - other * half, where + other * half, thick * 0.6)
      end
    end
  end
  lamp(w, head, math.max(thick * 0.5, long * 0.012))
end

-- A dome on a surface: a ring 'wide' in radius at 'foot', facing the
-- 'way' it stands, ground inside the ring, ribs over it where glass
-- would be, and what is built on the ground.
local function dome(w: Work, rng: RNG, foot: vector, way: vector, wide: number, sunk: number)
  local one, other = across(way)
  local round = 14
  local ground: { vector } = {}
  for index = 1, round do
    local angle = index / round * TAU
    ground[index] = foot + (one * math.cos(angle) + other * math.sin(angle)) * wide
  end
  Plates.Flat(w.b, PATCH, ground, way)
  -- (a wall under its rim, down to what it stands on)
  for index = 1, round do
    local a, c = ground[index], ground[index % round + 1]
    beam(w.b, TRIM, a - way * sunk * 0.5, c - way * sunk * 0.5, math.max(wide * 0.045, sunk * 0.55), 0.2)
  end
  local ribs = 8
  for rib = 1, ribs do
    local angle = rib / ribs * TAU
    local out = one * math.cos(angle) + other * math.sin(angle)
    local points: { vector } = {}
    for step = 0, 6 do
      local up = step / 6 * math.pi / 2
      points[step + 1] = foot + out * (wide * math.cos(up)) + way * (wide * 0.85 * math.sin(up))
    end
    Plates.Conduit(w.b, points, wide * 0.022)
  end
  -- (a hoop half way up the ribs)
  local up = math.pi / 4
  for index = 1, round do
    local a0, a1 = index / round * TAU, (index + 1) / round * TAU
    beam(w.b, FRAME, foot + (one * math.cos(a0) + other * math.sin(a0)) * (wide * math.cos(up)) + way * (wide * 0.85 * math.sin(up)),
      foot + (one * math.cos(a1) + other * math.sin(a1)) * (wide * math.cos(up)) + way * (wide * 0.85 * math.sin(up)), wide * 0.016)
  end
  for _ = 1, rng:Int(3, 7) do
    local angle, far = rng:Float(0, TAU), wide * rng:Float(0, 0.62)
    local base = foot + (one * math.cos(angle) + other * math.sin(angle)) * far
    local tall = wide * rng:Float(0.12, 0.5) * (1 - far / wide * 0.6)
    local broad = wide * rng:Float(0.04, 0.09)
    beam(w.b, if rng:Int(1, 3) == 1 then GLOW else PLATING, base, base + way * tall, broad, 0.1)
  end
end

-- A small tower standing off from the tower's upright: 'x' and 'y' from
-- it, about 'z' along it ('way': 1 it stands up from there, -1 it hangs
-- down, 0 its middle is there), 'out' at its widest and so 'long'; of
-- one body or two, with or without ends, and a thing standing out of it.
local function small(w: Work, rng: RNG, build: Build, x: number, y: number, z: number, way: number, out: number, long: number, bodies: number,
  ends: boolean, thing: boolean)
  local keptX, keptY = asideX, asideY
  asideX, asideY = keptX + x, keptY + y
  local mine: Work = { b = w.b, m = w.m, fold = w.fold, sides = w.sides, stem = math.max(out * 0.12, w.stem * 0.5), make = w.make,
    pieces = w.pieces, blink = w.blink }
  local low = if way > 0 then z elseif way < 0 then z - long else z - long / 2
  local each = long / bodies
  for index = 1, bodies do
    local from = low + (index - 1) * each
    local kind = oneOf(rng, build.bodies)
    local wide = out * (if bodies > 1 and index == (if way < 0 then 1 else bodies) then 0.7 else 1)
    BODIES[kind](mine, own(rng), from + each * 0.03, from + each * 0.97, wide, from + each / 2 > z)
  end
  local over, under = oneOf(rng, build.tops), oneOf(rng, build.tails)
  local overDice, underDice, thingDice = own(rng), own(rng), own(rng)
  local which = oneOf(rng, build.sides)
  if ends then
    top(mine, overDice, over, low + long, out * 0.7, out * 1.3)
    tail(mine, underDice, under, low, out * 0.7, out * 1.3)
  else
    lamp(mine, axis(low + long + mine.stem), mine.stem * 0.8)
    lamp(mine, axis(low - mine.stem), mine.stem * 0.8, TRIM)
  end
  if thing then
    stand(mine, which, thingDice, low + long * 0.5, out, out * 1.5)
  end
  block(w.b, FRAME, axis(low + long / 2), v(mine.stem, mine.stem, long / 2 + 0.01), nil, 0.3)
  asideX, asideY = keptX, keptY
end

-- A tower about a torus: the wheel, spokes out from it with a structure
-- at the end of each, and more as it is bigger.
local function toroidal(w: Work, build: Build, rng: RNG, size: number, plan: string, girth: number)
  local out = girth * rng:Float(0.95, 1.25)
  local thick = out * rng:Float(0.09, 0.22)
  local faces = ({ 4, 6, 8, 3 })[rng:Int(1, 4)]
  -- (in plate it is of many lengths, or of as few straight sides as it has spokes)
  local cornered = chance(rng, 0.4)
  local long = out * rng:Float(0.45, 1.0)
  local unalike = chance(rng, 0.3)
  local turned = chance(rng, 0.5)
  local extras = shuffled(rng, { "hub", "crown", "second", "inner" })
  local endSeed, otherSeed, hubDice, extraDice = rng:Int(1, 2000000000), rng:Int(1, 2000000000), own(rng), own(rng)

  local spokes = math.max(3, w.fold)
  local lengths = if cornered then spokes else spokes * (if spokes <= 4 then 4 else 2)
  wheel(w, PLATING, 0, out, thick, lengths, faces)
  -- (a spoke is at a corner of it, where it has corners; else where the dice say)
  local function angleOf(index: number): number
    return (index - (if cornered or turned then 0 else 0.5)) / spokes * TAU
  end
  lamps(w, 0, out + thick * (if w.m.hard and cornered then 0.75 else 0.98), lengths * (if cornered then 4 else 1), thick * 0.2,
    if cornered then 0 else TAU / lengths / 2)

  -- The structures at the ends of its spokes: more of each as it is bigger.
  local level = (size + 1) // 2
  local wide, tall = out * (0.09 + 0.035 * level), out * (0.28 + 0.14 * level)
  for index = 1, spokes do
    local angle = angleOf(index)
    local short = unalike and index % 2 == 0
    local reach = out + thick + long * (if short then 0.55 else 1)
    limb(w, at(angle, out + thick * 0.7, 0), at(angle, reach, 0), thick * 0.9, v(0, 0, 1), v(0, 0, 1))
    -- (where its weight is: hung under the spokes, stood on them, or about them; in beads, one up and the next down)
    local way = if plan == "low" then -1 elseif plan == "high" then 1 elseif plan == "beads" then (if index % 2 == 0 then -1 else 1) else 0
    local spot = around(angle, reach + wide * 0.5)
    small(w, RNG_MTG(if short then otherSeed else endSeed), build, spot.x, spot.y, 0, way, wide * (if short then 0.8 else 1),
      tall * (if short then 0.7 else 1), if level >= 4 then 2 else 1, level >= 2, level >= 3)
  end

  -- And, a size in two, one thing more.
  local hub = 0
  for index = 1, math.min(size // 2, #extras) do
    local extra = extras[index]
    if extra == "hub" then
      -- (something at its middle, on spokes inward)
      hub = out * 0.2
      small(w, hubDice, build, 0, 0, 0, 0, hub, out * rng:Float(0.6, 1.0), 1, true, false)
      for spoke = 1, spokes do
        local angle = angleOf(spoke)
        limb(w, at(angle, hub * 0.6, 0), at(angle, out - thick * 0.7, 0), thick * 0.6, v(0, 0, 1), v(0, 0, 1))
      end
    elseif extra == "crown" then
      -- (prongs on the wheel, between its spokes: up, or down where its weight is low)
      local way = if plan == "low" then -1 else 1
      local reach = out * extraDice:Float(0.3, 0.7)
      for prong = 1, spokes do
        local angle = angleOf(prong) + TAU / spokes / 2
        beam(w.b, PLATING, at(angle, out, way * thick * 0.6), at(angle, out, way * (thick + reach * 0.6)), thick * 0.22)
        beam(w.b, FRAME, at(angle, out, way * (thick + reach * 0.6)), at(angle, out, way * (thick + reach)), thick * 0.1)
        lamp(w, at(angle, out, way * (thick + reach)), thick * 0.14)
      end
    elseif extra == "second" then
      -- (a second wheel: a slimmer one, outside the first where the spokes go through it, or over it)
      if extraDice:Int(1, 2) == 1 then
        wheel(w, PATCH, 0, out + thick + long * 0.5, thick * 0.4, lengths, faces)
      else
        local up = if plan == "low" then -1 else 1
        wheel(w, PATCH, up * thick * 2.4, out * 0.92, thick * 0.5, lengths, faces)
        for post = 1, spokes do
          local angle = angleOf(post) + TAU / spokes / 2
          beam(w.b, FRAME, at(angle, out, 0), at(angle, out * 0.92, up * thick * 2.4), thick * 0.12)
        end
      end
    elseif extra == "inner" then
      -- (things inside the wheel, on short spokes inward)
      local reach = out * extraDice:Float(0.25, 0.45)
      local seed = extraDice:Int(1, 2000000000)
      for spoke = 1, spokes do
        local angle = angleOf(spoke) + TAU / spokes / 2
        limb(w, at(angle, out - thick * 0.7, 0), at(angle, out - thick - reach, 0), thick * 0.3, v(0, 0, 1), v(0, 0, 1))
        local spot = around(angle, out - thick - reach)
        small(w, RNG_MTG(seed), build, spot.x, spot.y, 0, 0, out * 0.07, out * 0.3, 1, false, false)
      end
    end
  end
end

-- A tower about a sphere: the ball, a thing at each of its poles, rings
-- of towers, antennas and domes round it, and more as it is bigger.
local function spherical(w: Work, build: Build, rng: RNG, size: number, plan: string, girth: number)
  local radius = girth * rng:Float(0.8, 1.0)
  local over, under = oneOf(rng, build.tops), oneOf(rng, build.tails)
  local overDice, underDice = own(rng), own(rng)
  -- (five places up it that a ring of things can be, in the order the dice say)
  local order = shuffled(rng, { "1", "2", "3", "4", "5" })
  local rings: { { kind: string, turn: number, twice: boolean, seed: number, far: number } } = {}
  for index = 1, 5 do
    rings[index] = { kind = oneOf(rng, { "tower", "tower", "antenna", "antenna", "dome", "dome", "blister" }), turn = rng:Float(0, 1),
      twice = chance(rng, 0.3), seed = rng:Int(1, 2000000000), far = rng:Float(0, 1) }
  end
  local extras = shuffled(rng, { "girdle", "moon", "halo", "skirt" })
  local extraDice = own(rng)

  ball(w, PLATING, 0, radius, w.sides * 2)
  local reach = radius * 0.6

  -- Its rings of things: a size in two, one more.
  local slots = { -0.98, -0.5, 0, 0.5, 0.98 }
  local girdled = false
  for index = 1, math.min(size // 2, #extras) do
    girdled = girdled or extras[index] == "girdle"
  end
  for index = 1, math.clamp(1 + (size + 1) // 2, 2, 5) do
    local ring = rings[index]
    local up = slots[tonumber(order[index]) :: number]
    -- (where its weight is: its things toward one pole, or its middle, or away from its middle)
    if plan == "low" then
      up = up * 0.7 - 0.35
    elseif plan == "high" then
      up = up * 0.7 + 0.35
    elseif plan == "middle" then
      up *= 0.55
    elseif plan == "ends" then
      up = if up == 0 then 0.75 else math.sign(up) * (0.55 + 0.35 * math.abs(up))
    end
    -- (a wheel round its middle has the middle to itself)
    if girdled and math.abs(up) < 0.2 then
      up = 0.3
    end
    local count = w.fold * (if ring.twice and ring.kind ~= "dome" then 2 else 1)
    local level = radius * math.cos(up)
    for each = 1, count do
      local angle = (each - 1 + ring.turn) / count * TAU
      local way = v(math.cos(angle) * math.cos(up), math.sin(angle) * math.cos(up), math.sin(up))
      local foot = axis(0) + way * radius
      local dice = RNG_MTG(ring.seed)
      if ring.kind == "tower" then
        spike(w, dice, foot - way * radius * 0.04, way, radius * (0.45 + 0.6 * ring.far), radius * (0.06 + 0.03 * ring.far))
      elseif ring.kind == "antenna" then
        spike(w, dice, foot - way * radius * 0.04, way, radius * (0.7 + 0.9 * ring.far), radius * 0.018)
      elseif ring.kind == "dome" then
        -- (no wider than there is room for so many of them round it there)
        local wide = math.min(radius * (0.2 + 0.14 * ring.far), level * math.pi / count * 0.8)
        local sunk = radius - math.sqrt(math.max(radius * radius - wide * wide, 0))
        dome(w, dice, foot + way * radius * 0.01, way, wide, sunk * (if w.m.hard then 2 else 1) + radius * 0.02)
      else
        -- (a blister: a lesser ball half out of it)
        local keptX, keptY = asideX, asideY
        local fat = math.min(radius * (0.14 + 0.1 * ring.far), level * math.pi / count * 0.8)
        asideX, asideY = keptX + way.x * radius, keptY + way.y * radius
        ball(w, PATCH, way.z * radius, fat, 8)
        asideX, asideY = keptX, keptY
        lamp(w, foot + way * fat, fat * 0.12)
      end
    end
  end

  -- And, the other size in two, one thing more.
  local foot = -radius
  for index = 1, math.min(size // 2, #extras) do
    local extra = extras[index]
    if extra == "girdle" then
      -- (a wheel round its middle, on spokes)
      local far = radius * extraDice:Float(1.35, 1.75)
      local thick = radius * extraDice:Float(0.05, 0.1)
      -- (which turns about it, spokes and all, where the tower's pieces are being made)
      moving(w, 0, { kind = "spin", rate = 0.1 }, function(mine: Work, level: number)
        wheel(mine, PATCH, level, far, thick, w.sides * 2, 4)
        for spoke = 1, math.max(3, w.fold) do
          local angle = (spoke - 0.5) / math.max(3, w.fold) * TAU
          limb(mine, at(angle, radius * 0.96, level), at(angle, far - thick * 0.7, level), thick * 0.5, v(0, 0, 1), v(0, 0, 1))
        end
        lamps(mine, level, far + thick, 12, thick * 0.25)
      end)
    elseif extra == "moon" then
      -- (a lesser ball under it, on the stem)
      local less = radius * extraDice:Float(0.28, 0.42)
      local drop = radius * extraDice:Float(0.5, 0.9)
      beam(w.b, FRAME, axis(-radius * 0.95), axis(-radius - drop), w.stem)
      ball(w, PATCH, -radius - drop - less, less, w.sides * 2)
      hoop(w, TRIM, -radius - drop - less, less * 1.02, less * 0.04)
      foot = -radius - drop - 2 * less
    elseif extra == "halo" then
      -- (a slim wheel standing off over its head, on posts)
      local far = radius * extraDice:Float(0.45, 0.7)
      local high = radius * extraDice:Float(1.12, 1.3)
      -- (the wheel turns on its posts)
      moving(w, high, { kind = "spin", rate = -0.2 }, function(mine: Work, level: number)
        wheel(mine, TRIM, level, far, radius * 0.03, w.sides * 2, 4)
      end)
      for post = 1, math.max(3, w.fold) do
        local angle = (post - 0.5) / math.max(3, w.fold) * TAU
        local up = math.acos(math.clamp(far / radius, 0, 1))
        beam(w.b, FRAME, at(angle, far, radius * math.sin(up) * 0.98), at(angle, far, high), radius * 0.012)
      end
    elseif extra == "skirt" then
      -- (long aerials hanging from under it)
      local count = w.fold * 2
      for each = 1, count do
        local angle = (each - 0.5) / count * TAU
        local long = radius * extraDice:Float(0.5, 1.3)
        local hang = at(angle, radius * 0.62, -radius * 0.78)
        beam(w.b, FRAME, hang, hang - v(0, 0, long), radius * 0.012)
        lamp(w, hang - v(0, 0, long), radius * 0.02, if each % 2 == 0 then GLOW else TRIM)
      end
    end
  end

  top(w, overDice, over, radius * 0.97, radius * 0.3, reach)
  tail(w, underDice, under, foot + radius * 0.03, radius * 0.3, reach)
end

-- The most bodies a tower has, and the most things standing out of it.
local MOST, MOST_OUT = 6, 7

-- Draw a tower. It lies along z, its top toward +z.
-- 'make', if given, makes a builder for each piece of it that moves:
-- those are what is given back, each with its pivot and how it moves
-- (a piece may have nothing in it). Without it, all of the tower is
-- drawn into 'b', and nothing is given back.
function Tower.Build(b: Builder, spec: Spec, make: (() -> Builder)?): { Piece }
  local build = BUILDS[spec.build] or BUILDS.mixed
  local m = MANNERS[spec.manner] or MANNERS.blocky
  local size = math.clamp(math.floor(spec.size), 1, 8)
  -- (the tower's own dice say what it is and where, and are thrown the
  -- same number of times whatever is asked of it; what each thing is
  -- like is by dice of that thing's own. So the same seed in another
  -- manner, or with its fold or its plan said over it, is otherwise the
  -- tower it was; and the same seed a size bigger is the tower it was
  -- with a body more on top, or a thing more standing out of it)
  local rng = RNG_MTG(Int.Signed(math.floor(spec.seed) * 7919 + (table.find(Tower.BUILDS, spec.build) or 0) * 104729 + 31))
  local fold = build.folds[rng:Int(1, #build.folds)]
  local plan = oneOf(rng, build.plans)
  if spec.fold and table.find(Tower.FOLDS, spec.fold) then
    fold = spec.fold
  end
  if spec.plan and table.find(Tower.PLANS, spec.plan) then
    plan = spec.plan
  end
  -- (a bigger tower is a little stouter, as well as longer)
  local girth = build.girth * m.girth * (0.9 + 0.035 * size)
  -- (what is solid in it has so many sides: its fold, or twice it for a tower of few)
  local sides = if fold == 2 then 4 elseif fold == 3 then 6 else fold
  local w: Work = { b = b, m = m, fold = fold, sides = sides, stem = 0.045 * girth * math.max(1, m.thin * 0.8) }
  local pieces: { Piece } = {}
  if make then
    -- (its hazard lamps: two lots of them, lit turn about)
    local groups: { Builder } = {}
    for group = 1, 2 do
      groups[group] = make()
      table.insert(pieces, { b = groups[group], pivot = v(0, 0, 0), motion = { kind = "blink", period = 1.2, phase = (group - 1) / 2, lit = 0.45 } })
    end
    w.make, w.pieces, w.blink = make, pieces, { groups = groups, count = 0 }
  end
  asideX, asideY = 0, 0
  -- (the two that are not a stem with things along it)
  if spec.build == "toroidal" then
    toroidal(w, build, rng, size, plan, girth)
    return pieces
  elseif spec.build == "spherical" then
    spherical(w, build, rng, size, plan, girth)
    return pieces
  end

  -- What the seed says of every body it might have, of every thing that
  -- might stand out of it, and of its ends.
  local said: { { girth: number, long: number, kind: string, dice: RNG, bare: boolean, gap: number, close: number } } = {}
  for index = 1, MOST do
    said[index] = { girth = rng:Float(0.85, 1.15), long = rng:Float(0.7, 1.3), kind = oneOf(rng, build.bodies), dice = own(rng),
      bare = chance(rng, build.bare), gap = rng:Float(0.25, 0.8), close = rng:Float(0.02, 0.07) }
  end
  local out: { { kind: string, where: number, along: number, dice: RNG } } = {}
  for index = 1, MOST_OUT do
    out[index] = { kind = oneOf(rng, build.sides), where = rng:Float(0, 0.999), along = rng:Float(0.25, 0.75), dice = own(rng) }
  end
  local over, under = oneOf(rng, build.tops), oneOf(rng, build.tails)
  local overDice, underDice = own(rng), own(rng)

  -- Its bodies, from the foot up: how long each is and how far out. A
  -- size in two is a body more (two of them at the first size, six at
  -- the eighth).
  local count = math.clamp(2 + size // 2, 2, MOST)
  local places: { { low: number, high: number, out: number, kind: string, dice: RNG } } = {}
  local z = 0
  local widest = 0
  for index = 1, count do
    local body = said[index]
    local heavy = weight(plan, (index - 0.5) / count, index)
    local far = girth * (0.13 + 0.42 * heavy) * body.girth
    local long = (0.45 + 0.75 * heavy) * body.long
    -- (a cage or open lattice is nothing if it is slim: it is given some girth)
    if body.kind == "cage" or body.kind == "lattice" then
      far = math.max(far, girth * 0.3)
      long = math.max(long, far * 1.6)
    end
    table.insert(places, { low = z, high = z + long, out = far, kind = body.kind, dice = body.dice })
    widest = math.max(widest, far)
    z += long + (if body.bare then body.gap else body.close)
  end
  local head = places[#places].high
  -- (how far a thing may stand out of this tower)
  local reach = math.max(widest * 1.6, 0.5 * girth)

  if m.bowed then
    -- (as if poured: its tiers and its tapers are not things on a stem
    -- but the stem itself, swelling out into each and drawn in again
    -- between, in one skin from foot to head. What is open, or strapped
    -- round, is what it would be, about the neck that runs through it)
    local neck = w.stem * 2.2
    local run: { { number } } = { { -0.05, neck * 0.8 } }
    for _, place in places do
      local long = place.high - place.low
      local up = (place.low + place.high) / 2 > head / 2
      if place.kind == "tiers" then
        local waist = place.dice:Float(0.7, 0.95)
        table.insert(run, { place.low + long * 0.04, neck * 1.1 })
        table.insert(run, { place.low + long * 0.24, place.out })
        table.insert(run, { place.low + long * 0.5, place.out * waist })
        table.insert(run, { place.low + long * 0.76, place.out })
        table.insert(run, { place.high - long * 0.04, neck * 1.1 })
      elseif place.kind == "taper" then
        local fat = place.dice:Float(0.24, 0.4)
        table.insert(run, { place.low + long * 0.03, neck * 1.1 })
        table.insert(run, { place.low + long * (if up then fat else 1 - fat), place.out })
        table.insert(run, { place.high - long * 0.03, neck * 1.1 })
      else
        table.insert(run, { place.low, neck })
        table.insert(run, { place.high, neck })
        BODIES[place.kind](w, place.dice, place.low, place.high, place.out, up)
      end
    end
    table.insert(run, { head + 0.05, neck * 0.8 })
    skin(b, PLATING, run)
    -- (a lit seam round the widest of each swelling)
    for _, place in places do
      if place.kind == "tiers" or place.kind == "taper" then
        lamps(w, (place.low + place.high) / 2, place.out * (if place.kind == "tiers" then 0.93 else 0.8), 10, 0.014)
      end
    end
  else
    for _, place in places do
      BODIES[place.kind](w, place.dice, place.low, place.high, place.out, (place.low + place.high) / 2 > head / 2)
    end
  end

  -- What stands out of it: at a body, or at the bare stem between two.
  -- The other size in two is a thing more.
  local wanted = math.clamp(math.floor(build.many * 2 + 0.5) - 1 + (size + 1) // 2, 0, MOST_OUT)
  local slots = 2 * count - 1
  local taken: { [number]: boolean } = {}
  for index = 1, math.min(wanted, slots) do
    local thing = out[index]
    local where = math.floor(thing.where * slots) + 1
    -- (two things are not at one place: the second goes to the next that is free)
    while taken[where] do
      where = where % slots + 1
    end
    taken[where] = true
    local body = places[(where + 1) // 2]
    if where % 2 == 1 then
      -- (at a body: somewhere along it)
      stand(w, thing.kind, thing.dice, body.low + (body.high - body.low) * thing.along, body.out, reach)
    else
      -- (between two)
      local next = places[where // 2 + 1]
      stand(w, thing.kind, thing.dice, (body.high + next.low) / 2, math.min(w.stem * 2.5, body.out), reach)
    end
  end

  -- Its ends, and the stem through all of it.
  top(w, overDice, over, head, places[#places].out, reach)
  tail(w, underDice, under, 0, places[1].out, reach)
  block(b, FRAME, axis(head / 2), v(w.stem, w.stem, head / 2 + 0.02), nil, 0.3)

  -- (in a manner of frames there are masts on everything: by dice that are nobody else's)
  if m.frame then
    local masts = RNG_MTG(Int.Signed(math.floor(spec.seed) * 613 + 17))
    for _ = 1, 2 + size // 2 do
      local body = places[masts:Int(1, count)]
      local angle = masts:Float(0, TAU)
      local foot = at(angle, body.out * 0.9, body.low + (body.high - body.low) * masts:Float(0.1, 0.9))
      local long = reach * masts:Float(0.5, 1.3)
      local way = if masts:Int(1, 4) == 1 then -1 else 1
      local tip = foot + around(angle, long * 0.25) + v(0, 0, way * long)
      beam(b, FRAME, foot, tip, w.stem * 0.28)
      lamp(w, tip, w.stem * 0.4, if masts:Int(1, 3) == 1 then GLOW else TRIM)
    end
  end
  return pieces
end

return Tower
