--!strict
-- Who builds what: the factions, as far as their ships and stations go.
--
-- Four human factions, each with hull designs of its own. The pirates,
-- whose hulls are other people's, patched together. Three alien
-- factions, whose ships are not built the way humans build. A hull's
-- 'lineage' (Data/Ships) is its faction's id.
--
-- A faction is what makes its ships differ from another's: how they are
-- shaped, what they shoot, how they take a hit. The numbers here
-- multiply a class's standard hull (Data/Ships), so a faction's
-- character holds from its frigate to its battleship.
--
-- (The strategic simulation's table of powers, Data/Powers, is older
-- and has not been brought into line with this one.)

local Factions = {}

-- Colours as red, green, blue from 0 to 1.
export type Paint = { primary: { number }, secondary: { number }, glow: { number } }

export type Faction = {
  id: string,
  name: string,
  kind: "human" | "pirate" | "alien",
  -- How its hulls are built up (Game/View/Hull). Human: "slab" broad
  -- armoured plates, "cloud" rounded lobes with blisters and no corners
  -- (the Talmar, by their draft), "motley" no two hulls built in the
  -- same manner (the Orun, by theirs), "blade" arrowheads in flat plates,
  -- sharp at every edge, each with its conning tower (the Kethri, by
  -- theirs).
  -- Pirate: "patchwork", somebody
  -- else's hull with parts missing and parts bolted on. Alien: "crystal"
  -- shards grown outward from a core, "carapace" segmented and curled
  -- like something alive, "monolith" rings and slabs without a seam.
  style: "slab" | "cloud" | "motley" | "blade" | "patchwork" | "crystal" | "carapace" | "monolith",
  weapon: string,           -- the turret family its warships carry
  launchers: number,        -- the share of a warship's hardpoints that are launchers
  tank: "armor" | "shield" | "hull",
  note: string,
  paint: Paint,
  -- multipliers on the class's standard hull
  shield: number,
  armor: number,
  hull: number,
  velocity: number,
  mass: number,
  cpu: number,
  powergrid: number,
  capacitor: number,
  lockRange: number,
  cargo: number,
  price: number,
  -- slots added to (or taken from) the standard layout
  mids: number,
  lows: number,
  hardpoints: number,
  -- its hulls, by class
  hulls: { [string]: string },
  -- Pirates only: whose hull each of theirs was, by class (a faction id).
  donors: { [string]: string }?,
  -- A people with no fixed place: it builds no towers, and where another
  -- faction has a station it has a colony ship (Data/Structures).
  nomad: boolean?,
}

Factions.list = {
  -- The four human factions.
  {
    -- (After the project owner's first sketch, 2026-11-10: mercantilists,
    -- blocky utilitarian ships: exposed conduits, heavy armour, missiles,
    -- engine nacelles. The guns on the hardpoints that are not launchers
    -- are projectile ones, which suits that; the sketch
    -- does not say.)
    id = "vessari", name = "Vessari", kind = "human", style = "slab", weapon = "projectile", launchers = 0.7, tank = "armor",
    note = "Missiles and heavy armour. Blocky, hard-working hulls with their conduits bare and their engines out on struts: a merchant people's ships, built to be hit and keep flying.",
    paint = { primary = { 0.72, 0.58, 0.30 }, secondary = { 0.22, 0.20, 0.18 }, glow = { 1.0, 0.75, 0.35 } },
    shield = 0.8, armor = 1.35, hull = 1.05, velocity = 0.92, mass = 1.1, cpu = 1.1, powergrid = 0.95, capacitor = 0.9,
    lockRange = 1.1, cargo = 1.15, price = 1, mids = -1, lows = 1, hardpoints = 0,
    hulls = { frigate = "Javelin", destroyer = "Halberd", cruiser = "Cuirass", battleship = "Bastion", industrial = "Caravan" },
  },
  {
    -- (After the project owner's draft, 2026-11-10: humans, an
    -- ethno-theocracy; ships "kind of cloud-like, with rounded edges and
    -- protrusions", with Star Wars' Mon Calamari cruisers as the visual
    -- point of reference. The draft says nothing of weapons or defence:
    -- those are as they were.)
    id = "talmar", name = "Talmar", kind = "human", style = "cloud", weapon = "projectile", launchers = 0.35, tank = "shield",
    note = "Guns, missiles and shields. Hulls like clouds: rounded, lobed and blistered, without a corner on them, fast for their class.",
    paint = { primary = { 0.62, 0.66, 0.70 }, secondary = { 0.15, 0.32, 0.55 }, glow = { 0.45, 0.75, 1.0 } },
    shield = 1.2, armor = 0.85, hull = 0.95, velocity = 1.1, mass = 0.92, cpu = 1.1, powergrid = 0.95, capacitor = 0.95,
    lockRange = 1.0, cargo = 0.95, price = 1, mids = 1, lows = -1, hardpoints = 0,
    hulls = { frigate = "Rapier", destroyer = "Sabre", cruiser = "Falchion", battleship = "Claymore", industrial = "Packet" },
  },
  {
    -- (After the project owner's draft, 2026-11-11: the Orun
    -- Confederation; human, anarchist; "ships are very different in
    -- style from each other, because they're designed by different
    -- groups within the confederation. Unifying visual feature is red
    -- and gold highlights. Also, they tend to have a lot of antenna
    -- masts." The draft says nothing of weapons or defence, nor of what
    -- the hulls are called: those are as they were.)
    id = "orun", name = "Orun", kind = "human", style = "motley", weapon = "hybrid", launchers = 0, tank = "armor",
    note = "Blasters, railguns and sheer bulk. The Confederation's hulls come from yards that agree on nothing: no two are built alike, and all of them wear red and gold and a thicket of aerials. Slow, hard to kill, and they carry a great deal.",
    paint = { primary = { 0.36, 0.37, 0.39 }, secondary = { 0.62, 0.09, 0.07 }, glow = { 1.0, 0.84, 0.50 } },
    shield = 0.9, armor = 1.15, hull = 1.4, velocity = 0.9, mass = 1.12, cpu = 0.95, powergrid = 1.1, capacitor = 1.0,
    lockRange = 0.9, cargo = 1.25, price = 1, mids = 0, lows = 0, hardpoints = 0,
    hulls = { frigate = "Mastiff", destroyer = "Boar", cruiser = "Aurochs", battleship = "Mammoth", industrial = "Ox" },
  },
  {
    -- (Lasers and armour by the project owner's decision, 2026-11-10,
    -- when the Vessari took missiles. By the owner's draft of 2026-11-11
    -- they are nomads: "no fixed stations, instead they have massive
    -- (talking 10km long, 1km wide) colony ships, that serve as mobile
    -- stations and fleet docks", in the manner of "sharp edges, flat grey
    -- plates, arrowheads, conning towers". The draft says nothing of what
    -- the hulls are called: the names below are still the placeholders
    -- from before it, and were thought of for open-framed hulls.)
    id = "kethri", name = "Kethri", kind = "human", style = "blade", weapon = "laser", launchers = 0, tank = "armor", nomad = true,
    note = "Lasers and armour. Nomads, who keep no stations and live aboard colony ships ten kilometres long. Their hulls are blades in flat grey plate, sharp at every edge, each with its conning tower: deep capacitors, long sight, and never out of ammunition.",
    paint = { primary = { 0.24, 0.30, 0.46 }, secondary = { 0.80, 0.80, 0.84 }, glow = { 0.55, 0.60, 1.0 } },
    shield = 0.85, armor = 1.25, hull = 1.0, velocity = 0.97, mass = 1.03, cpu = 0.95, powergrid = 1.1, capacitor = 1.15,
    lockRange = 1.2, cargo = 1.0, price = 1, mids = -1, lows = 1, hardpoints = 0,
    hulls = { frigate = "Lancer", destroyer = "Gantry", cruiser = "Trellis", battleship = "Spire", industrial = "Lighter" },
  },

  -- The pirates. Every hull of theirs began as one of the four above:
  -- stripped for speed, over-gunned, and held together by what was to
  -- hand. Cheap, quick, and worse at everything that takes care.
  {
    id = "unbound", name = "Unbound", kind = "pirate", style = "patchwork", weapon = "projectile", launchers = 0.3, tank = "hull",
    note = "Other people's hulls, cut down and bolted back together. More guns and more speed than the original, and less of everything else.",
    paint = { primary = { 0.34, 0.24, 0.18 }, secondary = { 0.50, 0.48, 0.44 }, glow = { 1.0, 0.25, 0.10 } },
    shield = 0.8, armor = 0.85, hull = 1.1, velocity = 1.12, mass = 0.9, cpu = 0.85, powergrid = 1.0, capacitor = 0.85,
    lockRange = 0.85, cargo = 1.2, price = 0.55, mids = 0, lows = 0, hardpoints = 1,
    hulls = { frigate = "Cutthroat", destroyer = "Jackal", cruiser = "Marauder", battleship = "Ravager", industrial = "Fence" },
    donors = { frigate = "talmar", destroyer = "orun", cruiser = "vessari", battleship = "kethri", industrial = "orun" },
  },

  -- The three alien factions. Nothing of theirs is sold on a human
  -- market, and nobody has a blueprint for it.
  {
    id = "vael", name = "Vael", kind = "alien", style = "crystal", weapon = "laser", launchers = 0, tank = "shield",
    note = "Ships grown as crystal around a bright core. Beams of great reach and shields that mend in moments, around a hull that shatters.",
    paint = { primary = { 0.55, 0.85, 0.90 }, secondary = { 0.90, 0.95, 1.0 }, glow = { 0.60, 1.0, 1.0 } },
    shield = 1.5, armor = 0.5, hull = 0.6, velocity = 1.05, mass = 0.8, cpu = 1.3, powergrid = 1.3, capacitor = 1.5,
    lockRange = 1.4, cargo = 0.5, price = 3, mids = 2, lows = -2, hardpoints = 0,
    hulls = { frigate = "Shard", destroyer = "Prism", cruiser = "Lattice-Song", battleship = "Cathedral", industrial = "Seed" },
  },
  {
    id = "skarn", name = "Skarn", kind = "alien", style = "carapace", weapon = "hybrid", launchers = 0, tank = "armor",
    note = "Ships that are animals, or were. They close fast, tear at short range, and their plating knits itself back together.",
    paint = { primary = { 0.30, 0.16, 0.22 }, secondary = { 0.55, 0.50, 0.20 }, glow = { 0.85, 1.0, 0.20 } },
    shield = 0.4, armor = 1.6, hull = 1.2, velocity = 1.2, mass = 1.0, cpu = 0.8, powergrid = 1.2, capacitor = 0.9,
    lockRange = 0.7, cargo = 0.8, price = 3, mids = -1, lows = 2, hardpoints = 1,
    hulls = { frigate = "Stinger", destroyer = "Render", cruiser = "Broodguard", battleship = "Leviathan", industrial = "Gorger" },
  },
  {
    id = "tessellate", name = "Tessellate", kind = "alien", style = "monolith", weapon = "projectile", launchers = 0.4, tank = "hull",
    note = "Machines that build machines. Seamless rings and slabs, slow and patient, that strike from beyond sight and take a long time to break.",
    paint = { primary = { 0.10, 0.10, 0.12 }, secondary = { 0.75, 0.75, 0.78 }, glow = { 1.0, 0.95, 0.80 } },
    shield = 0.9, armor = 1.1, hull = 2.2, velocity = 0.7, mass = 1.5, cpu = 1.4, powergrid = 1.2, capacitor = 1.2,
    lockRange = 1.6, cargo = 1.0, price = 3, mids = 0, lows = 0, hardpoints = 0,
    hulls = { frigate = "Tile", destroyer = "Pylon", cruiser = "Annulus", battleship = "Monolith", industrial = "Reliquary" },
  },
} :: { Faction }

Factions.byId = {} :: { [string]: Faction }
for _, faction in Factions.list do
  Factions.byId[faction.id] = faction
end

-- The classes every faction builds, smallest first.
Factions.CLASSES = { "frigate", "destroyer", "cruiser", "battleship", "industrial" }

return Factions
