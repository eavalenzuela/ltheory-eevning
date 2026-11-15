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
-- of its own. Some designs are in two colours: the second is what the
-- paint marks things in (its 'trim').
--
-- More of both, the owner's of 2026-11-15: "Camo patterns, gaudy and
-- gauche patterns, police ship patterns and paints, etc etc. Also, take
-- a first shot at Faction liveries." A livery is a faction's own paint
-- with the design its ships wear on it: sold at that faction's
-- stations to a pilot they think well of (Assets/Market), and worn by
-- the faction's own ships in space (Paints.Dress, which the view asks).
-- The police of every faction wear the patrol paint and its blocks.
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
  -- What kind of paint it is, for whoever lists them: nothing for a
  -- plain one, "camouflage", "gaudy", "police", or "livery".
  group: string?,
  -- A livery is a faction's own: the faction whose it is, and the
  -- design its ships wear with it (which comes with the paint).
  faction: string?,
  wears: string?,
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
  group: string?,     -- as a paint's
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

  -- Camouflage: three tones that sit near each other, for the designs that break a hull up.
  { id = "paint.woodland", name = "Woodland", group = "camouflage", plating = { 0.30, 0.34, 0.17 }, patch = { 0.22, 0.26, 0.13 },
    trim = { 0.33, 0.23, 0.12 }, frame = FRAME, accent = { 0.06, 0.08, 0.05 }, price = 50000,
    note = "Olive over dark green, marked in earth brown; a design is laid on in black-green, with brown for its second colour." },
  { id = "paint.desert", name = "Desert", group = "camouflage", plating = { 0.66, 0.55, 0.38 }, patch = { 0.52, 0.42, 0.28 },
    trim = { 0.78, 0.70, 0.55 }, frame = FRAME, accent = { 0.40, 0.27, 0.15 }, price = 50000,
    note = "Sand over dun, marked in pale stone; a design is laid on in brown, with pale stone for its second colour." },
  { id = "paint.arctic", name = "Arctic", group = "camouflage", plating = { 0.78, 0.80, 0.82 }, patch = { 0.62, 0.66, 0.70 },
    trim = { 0.55, 0.62, 0.70 }, frame = FRAME, accent = { 0.34, 0.37, 0.42 }, price = 50000,
    note = "Snow white over ice grey, marked in blue-grey; a design is laid on in slate, with blue-grey for its second colour." },
  { id = "paint.urban", name = "Urban", group = "camouflage", plating = { 0.42, 0.43, 0.45 }, patch = { 0.30, 0.31, 0.33 },
    trim = { 0.66, 0.67, 0.68 }, frame = FRAME, accent = { 0.12, 0.12, 0.14 }, price = 50000,
    note = "Mid grey over dark grey, marked in pale grey; a design is laid on in charcoal, with pale grey for its second colour." },
  { id = "paint.void", name = "Void", group = "camouflage", plating = { 0.07, 0.08, 0.13 }, patch = { 0.10, 0.10, 0.18 },
    trim = { 0.05, 0.16, 0.20 }, frame = { 0.13, 0.13, 0.16 }, accent = { 0.20, 0.10, 0.30 }, price = 90000,
    note = "The dark between stars: blue-black, marked in deep teal; a design is laid on in dusk violet, with teal for its second colour." },

  -- Gaudy: colours nobody could miss, and that do not go together.
  { id = "paint.bubblegum", name = "Bubblegum", group = "gaudy", plating = { 0.92, 0.30, 0.58 }, patch = { 0.95, 0.62, 0.76 },
    trim = { 0.95, 0.95, 0.92 }, frame = FRAME, accent = { 0.20, 0.78, 0.82 }, price = 80000,
    note = "Hot pink over candy pink, marked in white; a design is laid on in bright cyan, with white for its second colour." },
  { id = "paint.limelight", name = "Limelight", group = "gaudy", plating = { 0.52, 0.84, 0.10 }, patch = { 0.30, 0.55, 0.08 },
    trim = { 0.95, 0.85, 0.10 }, frame = FRAME, accent = { 0.48, 0.12, 0.62 }, price = 80000,
    note = "Lime over green, marked in yellow; a design is laid on in purple, with yellow for its second colour." },
  { id = "paint.hotrod", name = "Hot Rod", group = "gaudy", plating = { 0.62, 0.05, 0.04 }, patch = { 0.12, 0.12, 0.13 },
    trim = { 0.95, 0.45, 0.05 }, frame = FRAME, accent = { 0.98, 0.82, 0.12 }, price = 110000,
    note = "Fire-engine red over black, marked in orange; a design is laid on in yellow, with orange for its second colour: made for flames." },
  { id = "paint.jester", name = "Jester", group = "gaudy", plating = { 0.42, 0.10, 0.55 }, patch = { 0.10, 0.45, 0.25 },
    trim = { 0.15, 0.62, 0.30 }, frame = FRAME, accent = { 0.95, 0.80, 0.10 }, price = 110000,
    note = "Purple over green, marked in green; a design is laid on in yellow, with green for its second colour." },
  { id = "paint.gilded", name = "Gilded", group = "gaudy", plating = { 0.80, 0.62, 0.18 }, patch = { 0.62, 0.46, 0.12 },
    trim = { 0.10, 0.08, 0.06 }, frame = FRAME, accent = { 0.92, 0.90, 0.84 }, price = 250000,
    note = "Gold over old gold, marked in black; a design is laid on in white, with black for its second colour. It costs what it looks." },
  { id = "paint.savanna", name = "Savanna", group = "gaudy", plating = { 0.78, 0.60, 0.28 }, patch = { 0.66, 0.48, 0.20 },
    trim = { 0.50, 0.32, 0.12 }, frame = FRAME, accent = { 0.10, 0.07, 0.05 }, price = 80000,
    note = "Tawny over ochre, marked in brown; a design is laid on in black, with brown for its second colour: made for a big cat's coat." },
  { id = "paint.tropic", name = "Tropic", group = "gaudy", plating = { 0.05, 0.62, 0.60 }, patch = { 0.95, 0.50, 0.10 },
    trim = { 0.98, 0.90, 0.30 }, frame = FRAME, accent = { 0.95, 0.35, 0.30 }, price = 80000,
    note = "Turquoise over orange, marked in yellow; a design is laid on in coral, with yellow for its second colour." },

  -- Police: what a patrol is known by at a distance.
  { id = "paint.patrol", name = "Patrol", group = "police", plating = { 0.84, 0.85, 0.86 }, patch = { 0.62, 0.64, 0.68 },
    trim = { 0.86, 0.82, 0.10 }, frame = FRAME, accent = { 0.05, 0.20, 0.62 }, price = 70000,
    note = "White over pale grey, marked in warning yellow; a design is laid on in police blue, with yellow for its second colour. What the police of every people fly in." },
  { id = "paint.interceptor", name = "Interceptor", group = "police", plating = { 0.07, 0.07, 0.08 }, patch = { 0.80, 0.80, 0.80 },
    trim = { 0.10, 0.35, 0.85 }, frame = { 0.15, 0.15, 0.17 }, accent = { 0.88, 0.88, 0.88 }, price = 90000,
    note = "Black with white panels, marked in blue; a design is laid on in white, with blue for its second colour." },
  { id = "paint.hivis", name = "Hi-Vis", group = "police", plating = { 0.80, 0.90, 0.10 }, patch = { 0.66, 0.74, 0.10 },
    trim = { 0.90, 0.25, 0.05 }, frame = FRAME, accent = { 0.05, 0.18, 0.55 }, price = 70000,
    note = "The yellow-green nobody overlooks, marked in red; a design is laid on in blue, with red for its second colour." },
  { id = "paint.marshal", name = "Marshal", group = "police", plating = { 0.06, 0.12, 0.30 }, patch = { 0.12, 0.18, 0.36 },
    trim = { 0.78, 0.62, 0.20 }, frame = FRAME, accent = { 0.86, 0.86, 0.84 }, price = 90000,
    note = "Navy over dark blue, marked in gold; a design is laid on in white, with gold for its second colour." },

  -- Liveries: a faction's own colours, with the design its ships wear on
  -- them. A first one for each of the four human factions, and every
  -- colour and choice of design mine: the owner has said only what the
  -- Orun go by (2026-11-11: "unified by red and gold highlights").
  { id = "paint.livery.vessari", name = "Vessari Livery", group = "livery", faction = "vessari", wears = "design.waistband",
    plating = { 0.07, 0.27, 0.22 }, patch = { 0.20, 0.22, 0.22 }, trim = { 0.74, 0.58, 0.20 }, frame = FRAME, accent = { 0.78, 0.72, 0.56 },
    price = 200000,
    note = "The Vessari's own: a trading house's deep green over slate, marked in gold, with a cream band along the waist. It comes with the Waistband design." },
  { id = "paint.livery.talmar", name = "Talmar Livery", group = "livery", faction = "talmar", wears = "design.sash",
    plating = { 0.80, 0.83, 0.86 }, patch = { 0.60, 0.70, 0.80 }, trim = { 0.20, 0.36, 0.62 }, frame = FRAME, accent = { 0.26, 0.50, 0.78 },
    price = 200000,
    note = "The Talmar's own: cloud white over pale sky, marked in deep blue, with a sky-blue sash round the bow. It comes with the Sash design." },
  { id = "paint.livery.orun", name = "Orun Livery", group = "livery", faction = "orun", wears = "design.chevrons",
    plating = { 0.13, 0.12, 0.12 }, patch = { 0.24, 0.22, 0.21 }, trim = { 0.78, 0.60, 0.16 }, frame = { 0.15, 0.15, 0.17 },
    accent = { 0.66, 0.09, 0.07 }, price = 200000,
    note = "The Orun Confederation's own: iron black, marked in gold, with red chevrons. It comes with the Chevrons design." },
  { id = "paint.livery.kethri", name = "Kethri Livery", group = "livery", faction = "kethri", wears = "design.tailbands",
    plating = { 0.58, 0.60, 0.62 }, patch = { 0.44, 0.46, 0.48 }, trim = { 0.10, 0.10, 0.11 }, frame = FRAME, accent = { 0.52, 0.08, 0.07 },
    price = 200000,
    note = "The Kethri's own: fleet grey over dark grey, marked in black, with a crimson band round the stern. It comes with the Tail Bands design." },
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

  -- Camouflage.
  { id = "design.woodland", name = "Woodland Blots", group = "camouflage", figure = 9, scale = 5.0, price = 70000,
    note = "Soft-edged blots all over the hull, in the design's colour and its second." },
  { id = "design.digital", name = "Digital", group = "camouflage", figure = 10, scale = 22, price = 90000,
    note = "Small squares in clumps, in the design's colour and its second: camouflage as a machine draws it." },
  { id = "design.splinter", name = "Splinter", group = "camouflage", figure = 11, scale = 3.0, price = 70000,
    note = "Long hard-edged shards at angles, in three tones." },

  -- Gaudy.
  { id = "design.polka", name = "Polka Dots", group = "gaudy", figure = 12, scale = 7, price = 60000, note = "Dots, row on row, over the whole hull." },
  { id = "design.candy", name = "Candy Stripe", group = "gaudy", figure = 13, scale = 4, price = 60000,
    note = "Bars slanting round the hull, like a stick of rock." },
  { id = "design.harlequin", name = "Harlequin", group = "gaudy", figure = 14, scale = 4, price = 90000,
    note = "Diamonds over the whole hull, in three colours: the paint's, the design's and its second." },
  { id = "design.leopard", name = "Leopard", group = "gaudy", figure = 15, scale = 7, price = 110000,
    note = "Broken rings of the design's colour about spots of its second: a big cat's coat." },
  { id = "design.flames", name = "Flames", group = "gaudy", figure = 16, scale = 0.45, price = 110000,
    note = "Flames licking aft from the bow in the design's colour, with a core of its second." },
  { id = "design.zigzag", name = "Zigzag", group = "gaudy", figure = 17, scale = 3, price = 60000, note = "Bands round the hull that go to and fro." },

  -- Police.
  { id = "design.battenburg", name = "Battenburg", group = "police", figure = 18, scale = 9, price = 80000,
    note = "Two rows of blocks along the waist, turn about in the design's colour and its second: seen and known from far off." },
  { id = "design.chequerband", name = "Chequer Band", group = "police", figure = 19, scale = 20, price = 60000,
    note = "A band of small squares along the waist, three deep." },
  { id = "design.hazard", name = "Hazard Bars", group = "police", figure = 20, scale = 0.5, price = 60000,
    note = "The after part in slanting bars, turn about in the design's colour and its second." },
  { id = "design.waistband", name = "Waistband", group = "police", figure = 21, scale = 0.04, price = 50000,
    note = "A band along the waist from bow to stern, with a thin line of the second colour above it and below." },
  { id = "design.sash", name = "Sash", group = "police", figure = 22, scale = 0.30, price = 50000,
    note = "A slanting band round the forward part, and a narrow one of the second colour behind it." },

  -- And two more for a livery to be made of.
  { id = "design.quarters", name = "Quarters", figure = 23, scale = 1, price = 50000,
    note = "Quartered: the bow to one side and the stern to the other in the design's colour." },
  { id = "design.tailbands", name = "Tail Bands", figure = 24, scale = 0.55, price = 50000,
    note = "A broad band round the after part, and two narrow ones of the second colour ahead of it." },
} :: { Design }

Paints.paintById = {} :: { [string]: Paint }
for _, paint in Paints.paints do
  Paints.paintById[paint.id] = paint
end
Paints.designById = {} :: { [string]: Design }
for _, design in Paints.designs do
  Paints.designById[design.id] = design
end

-- A faction's livery, by the faction's id.
Paints.liveryOf = {} :: { [string]: Paint }
for _, paint in Paints.paints do
  if paint.faction then
    Paints.liveryOf[paint.faction] = paint
  end
end

-- What the police of every faction fly in.
Paints.POLICE = { paint = "paint.patrol", design = "design.battenburg" }

-- What a ship nobody has painted is in, by whose it is: a faction's own
-- ships are in its livery, with the design that goes with it, and its
-- police in theirs. Nothing for anybody else's (a pilot's own is what
-- they have had it painted in; a pirate's is the pirates').
function Paints.Dress(owner: string, police: boolean): (string?, string?)
  local livery = Paints.liveryOf[owner]
  if livery == nil then
    return nil, nil
  elseif police then
    return Paints.POLICE.paint, Paints.POLICE.design
  end
  return livery.id, livery.wears
end

-- What each takes up in a hold (a drum of paint; a set of masks and a plan).
Paints.VOLUME = 2

-- What a thing of either kind is called as an item.
function Paints.ItemName(id: string): string
  local paint, design = Paints.paintById[id], Paints.designById[id]
  return if paint then `{paint.name} (paint)` elseif design then `{design.name} (design)` else id
end

return Paints
