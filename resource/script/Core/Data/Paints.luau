--!strict
-- Paints and designs: what a pilot has a ship painted in. (The owner's
-- list of 2026-11-15: "paint system in-game (apply different designs +
-- paint sets to ships, that you buy on market)".)
--
-- A paint is a set of colours: what the hull's plating is painted, the
-- plates that are not like the rest, what is marked on it, its bare
-- structure, and the colour a design is laid on in. A design is a
-- figure laid over the plating in that last colour: a stripe, hoops, a
-- cap on the bow. Each is a thing bought on a market, and used up by
-- being made the pilot's own (Assets/Paintwork): it is then theirs for
-- good, and any ship they fly is painted in it as often as they like.
--
-- A design needs a paint under it: a hull as it left the yard is in
-- its builder's colours or in bare metal, and a design has no colour
-- of its own.
--
-- The colours are numbers here, and it is the view that paints with
-- them (Game/View/Hull): nothing in the rules cares what colour a ship
-- is. Every paint, design, colour and price is a first one, and mine.

local Paints = {}

export type Colour = { number }

export type Paint = {
  id: string,
  name: string,
  plating: Colour,
  patch: Colour,
  trim: Colour,
  frame: Colour,
  accent: Colour,     -- what a design is laid on in
  price: number,
  note: string,
}

export type Design = {
  id: string,
  name: string,
  -- Which figure it is, as the hull's shader numbers them
  -- (shader/fragment/material/hull.jsl), and how many of the figure
  -- there are to the hull's length (or, of the bow's cap, how far
  -- forward of the middle it begins, in the hull's own lengths).
  figure: number,
  scale: number,
  price: number,
  note: string,
}

-- (What is bare structure on a hull is a good part of one the generator
-- grew: dark, but not black, or a painted hull is mostly shadow.)
local FRAME: Colour = { 0.24, 0.24, 0.26 }

Paints.paints = {
  { id = "paint.crimson", name = "Crimson", plating = { 0.58, 0.10, 0.08 }, patch = { 0.26, 0.24, 0.25 }, trim = { 0.70, 0.52, 0.18 },
    frame = FRAME, accent = { 0.80, 0.76, 0.70 }, price = 60000, note = "Deep red over charcoal, marked in gold; a design is laid on in bone white." },
  { id = "paint.cobalt", name = "Cobalt", plating = { 0.09, 0.20, 0.50 }, patch = { 0.46, 0.48, 0.52 }, trim = { 0.80, 0.80, 0.82 },
    frame = FRAME, accent = { 0.84, 0.85, 0.88 }, price = 60000, note = "Blue over pale grey, marked in white; a design is laid on in white." },
  { id = "paint.glacier", name = "Glacier", plating = { 0.62, 0.66, 0.70 }, patch = { 0.34, 0.48, 0.60 }, trim = { 0.08, 0.14, 0.30 },
    frame = FRAME, accent = { 0.10, 0.22, 0.46 }, price = 75000, note = "White over ice blue, marked in navy; a design is laid on in deep blue." },
  { id = "paint.onyx", name = "Onyx", plating = { 0.10, 0.10, 0.115 }, patch = { 0.22, 0.22, 0.25 }, trim = { 0.55, 0.06, 0.06 },
    frame = { 0.15, 0.15, 0.17 }, accent = { 0.62, 0.08, 0.07 }, price = 120000, note = "Black over graphite, marked in red; a design is laid on in red." },
  { id = "paint.forest", name = "Forest", plating = { 0.15, 0.31, 0.14 }, patch = { 0.34, 0.34, 0.18 }, trim = { 0.55, 0.48, 0.30 },
    frame = FRAME, accent = { 0.05, 0.09, 0.05 }, price = 45000, note = "Dark green over olive, marked in tan; a design is laid on in near black." },
  { id = "paint.sunflare", name = "Sunflare", plating = { 0.80, 0.42, 0.05 }, patch = { 0.28, 0.28, 0.30 }, trim = { 0.06, 0.06, 0.06 },
    frame = FRAME, accent = { 0.07, 0.07, 0.08 }, price = 75000, note = "Orange over dark grey, marked in black; a design is laid on in black." },
  { id = "paint.royal", name = "Royal", plating = { 0.33, 0.12, 0.50 }, patch = { 0.48, 0.48, 0.52 }, trim = { 0.72, 0.56, 0.18 },
    frame = FRAME, accent = { 0.76, 0.60, 0.20 }, price = 150000, note = "Purple over silver, marked in gold; a design is laid on in gold." },
  { id = "paint.sandstorm", name = "Sandstorm", plating = { 0.56, 0.45, 0.29 }, patch = { 0.37, 0.26, 0.15 }, trim = { 0.20, 0.13, 0.08 },
    frame = FRAME, accent = { 0.25, 0.16, 0.09 }, price = 45000, note = "Desert tan over brown, marked in umber; a design is laid on in umber." },
  { id = "paint.verdigris", name = "Verdigris", plating = { 0.11, 0.38, 0.36 }, patch = { 0.45, 0.25, 0.12 }, trim = { 0.62, 0.36, 0.16 },
    frame = FRAME, accent = { 0.70, 0.42, 0.18 }, price = 90000, note = "Sea green over copper, marked in copper; a design is laid on in bright copper." },
  { id = "paint.gunmetal", name = "Gunmetal", plating = { 0.30, 0.32, 0.36 }, patch = { 0.20, 0.21, 0.24 }, trim = { 0.80, 0.62, 0.05 },
    frame = FRAME, accent = { 0.82, 0.64, 0.06 }, price = 45000, note = "Steel grey over dark grey, marked in warning yellow; a design is laid on in yellow." },
  { id = "paint.bone", name = "Bone", plating = { 0.68, 0.64, 0.54 }, patch = { 0.43, 0.39, 0.33 }, trim = { 0.12, 0.11, 0.10 },
    frame = FRAME, accent = { 0.40, 0.09, 0.07 }, price = 60000, note = "Bone white over stone, marked in black; a design is laid on in ox-blood red." },
  { id = "paint.aurora", name = "Aurora", plating = { 0.09, 0.40, 0.29 }, patch = { 0.19, 0.15, 0.39 }, trim = { 0.58, 0.78, 0.68 },
    frame = FRAME, accent = { 0.35, 0.19, 0.60 }, price = 150000, note = "Green over violet, marked in pale mint; a design is laid on in violet." },
} :: { Paint }

Paints.designs = {
  { id = "design.stripe", name = "Racing Stripe", figure = 1, scale = 5.5, price = 40000,
    note = "A broad stripe down the middle of the hull from bow to stern, and a thin one either side of it." },
  { id = "design.hoops", name = "Hoops", figure = 2, scale = 2.2, price = 40000, note = "Bands round the hull, bow to stern." },
  { id = "design.chevrons", name = "Chevrons", figure = 3, scale = 1.9, price = 60000, note = "Bands that meet in a point on the hull's middle line, pointing aft." },
  { id = "design.halves", name = "Port and Starboard", figure = 4, scale = 1, price = 40000, note = "One side of the hull in the paint's own colour and the other in the design's." },
  { id = "design.bowcap", name = "Bow Cap", figure = 5, scale = 0.28, price = 40000, note = "The forward part of the hull in the design's colour." },
  { id = "design.dazzle", name = "Dazzle", figure = 6, scale = 3.2, price = 90000, note = "Hard-edged blocks at odd angles all over the hull, to break up its lines." },
  { id = "design.tiger", name = "Tiger", figure = 7, scale = 2.6, price = 90000, note = "Wavering stripes round the hull, no two alike." },
  { id = "design.chequers", name = "Chequers", figure = 8, scale = 4.5, price = 60000, note = "Squares, turn about, over the whole hull." },
} :: { Design }

Paints.paintById = {} :: { [string]: Paint }
for _, paint in Paints.paints do
  Paints.paintById[paint.id] = paint
end
Paints.designById = {} :: { [string]: Design }
for _, design in Paints.designs do
  Paints.designById[design.id] = design
end

-- What each takes up in a hold (a drum of paint; a set of masks and a plan).
Paints.VOLUME = 2

-- What a thing of either kind is called as an item.
function Paints.ItemName(id: string): string
  local paint, design = Paints.paintById[id], Paints.designById[id]
  return if paint then `{paint.name} (paint)` elseif design then `{design.name} (design)` else id
end

return Paints
