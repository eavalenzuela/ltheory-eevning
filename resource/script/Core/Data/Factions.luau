--!strict
-- Who builds what: the factions, as far as their ships and stations go.
--
-- Four human factions, each with hull designs of its own. The pirates,
-- whose hulls are other people's, patched together. Three alien
-- factions, whose ships are not built the way humans build: two that
-- hold space on the map, and one that is met only in the deep of
-- uncharted space. A hull's 'lineage' (Data/Ships) is its faction's id.
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
  -- else's hull with parts missing and parts bolted on. Alien: "wedge"
  -- broad flat hulls drawn to a point, stepped with decks and towers,
  -- some with one side not the other's twin (the Vail, by the owner's
  -- picks of them from the generator), "liquid" round masses of living
  -- metal without a seam (the Nimia, by the owner's word), "outrigger"
  -- windowless hulls with a lesser hull out on one side, which houses
  -- the generator of the cloak each has (the Drowned, by the owner's
  -- word and picks).
  style: "slab" | "cloud" | "motley" | "blade" | "patchwork" | "wedge" | "liquid" | "outrigger",
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
  -- The kind of damage its ships lean to (the project owner's ruling,
  -- 2026-11-14: "the 4 human factions each have one ship damage
  -- affinity, which they both deal out more and guard better against";
  -- which is whose is theirs too): 1 EM, 2 thermal, 3 kinetic, 4
  -- explosive. Nil for the pirates and the aliens, who are a mix.
  affinity: number?,
  -- Hulls that mend by themselves (the Nimia's): the share of its armour
  -- and of its hull that a hull of theirs gets back each second. Nil
  -- for everybody whose hulls do not.
  mends: { armor: number, hull: number }?,
  -- its hulls, by class
  hulls: { [string]: string },
  -- Or its ships hull by hull, where the project owner has gone through
  -- the faction's (a faction at a time): it then has these and no
  -- others, as many of a class as are named here and none of a class
  -- that is not, and 'hulls' is not read for it.
  line: { Hull }?,
  -- Pirates only: whose hull each of theirs was, by class (a faction id).
  -- And, where that hull is not of the same class, of what class it is
  -- ('cut': a hull of theirs cut down from a bigger one).
  donors: { [string]: string }?,
  cut: { [string]: string }?,
  -- A people with no fixed place: it builds no towers, and where another
  -- faction has a station it has a colony ship (Data/Structures).
  nomad: boolean?,
  -- A people of the deep: it holds no space on the map (Describe/
  -- Galaxy's Claim passes it by), and is met in the deepest of uncharted
  -- space and nowhere else (Tactical/Pirates). The Drowned.
  deep: boolean?,
  -- Every hull of its line that is not a tech 2 make has a cloak of its
  -- own, built in (Data/Ships' 'cloak'). The Drowned's.
  cloaks: boolean?,
  -- The make of gun its warships carry, where that is not the first of
  -- its family: "railgun", of the hybrids. (The first, if not said: a
  -- blaster.)
  gun: string?,
  -- What a wreck of a hull of theirs has in it beside what the ship
  -- carried: the stuff the hull is made of (an item's id, Data/Types).
  wreck: string?,
}

-- A hull of a faction's line: its name and its class, and what it is
-- beside the plain hull of that class. 'role' "combat" is a hauler
-- built to be shot at (a combat hauler). 'tech' 2 with 'of' is the tech
-- 2 make of another hull of the line, by that hull's name: a hull of
-- its own, with its own name and looks. 'jump': it has a jump drive
-- (Tactical/Jumping). What a tech 2 hull is for, where the project
-- owner has said (one that says nothing is the plain tech 2 make, and
-- by their word: the Vessari's Kanau, the Orun's Kama):
-- 'stealth': it is built to go unseen (a black ops hull, "one that can
-- cloak"): a cloak does not slow it, and is broken only from half as
-- far (Tactical/Combat); and a cloaking device, which is very dear to
-- fit to another hull, asks a tenth as much of it (Ships.CLOAK_FITTING).
-- 'cloak': it has a cloak of its own, built in: nothing to fit, no slot
-- taken (Tactical/Combat).
-- 'explorer': it is built for exploration: a cloaking device asks the
-- same tenth of it to fit, its scanner works a signal better and its
-- pilot hacks with a longer buffer (Ships.EXPLORER).
-- 'role' "miner" is a capital industrial that mines for itself (a
-- mass-miner): 'hardpoints' is then how many mining turrets it has.
-- 'role' "transport" is a capital industrial that carries ships (a
-- logistics capital): it has a bay for packed hulls where another has
-- an ore hold.
-- 'radius' is how big it is, m, for a hull of a class that has no size
-- of its own (an ultracapital).
-- 'guns' is its hardpoints by the size of weapon each is for (so many
-- small, medium, large and XL), where they are not all of the size its
-- class carries: the Kethri's colony ship has 140, of every size. Of
-- each size its builders make their share launchers (Data/Ships).
-- 'rare': nobody sells it, nor the blueprint for it.
-- 'jumpField': its jump drive has a field, so many metres deep: every
-- friendly ship within it goes where the hull goes when it jumps
-- (Tactical/Jumping). The Vail's Archangel, by the owner's word.
-- A hull whose name begins "The" goes by that name alone, and every
-- other by its people's name and its own (Data/Ships): "The Reaper",
-- and "Drowned Coffin".
export type Hull = { name: string, class: string, role: string?, tech: number?, of: string?, jump: boolean?, stealth: boolean?,
  cloak: boolean?, explorer: boolean?, hardpoints: number?, radius: number?, guns: { number }?, rare: boolean?,
  jumpField: number? }

Factions.list = {
  -- The four human factions.
  {
    -- (After the project owner's first sketch, 2026-11-10: mercantilists,
    -- blocky utilitarian ships: exposed conduits, heavy armour, missiles,
    -- engine nacelles. The guns on the hardpoints that are not launchers
    -- are projectile ones, which suits that; the sketch
    -- does not say.)
    id = "vessari", name = "Vessari", kind = "human", style = "slab", weapon = "projectile", launchers = 0.7, tank = "armor",
    affinity = 4,
    note = "Missiles and heavy armour. Blocky, hard-working hulls with their conduits bare and their engines out on struts: a merchant people's ships, built to be hit and keep flying.",
    paint = { primary = { 0.72, 0.58, 0.30 }, secondary = { 0.22, 0.20, 0.18 }, glow = { 1.0, 0.75, 0.35 } },
    shield = 0.8, armor = 1.35, hull = 1.05, velocity = 0.92, mass = 1.1, cpu = 1.1, powergrid = 0.95, capacitor = 0.9,
    lockRange = 1.1, cargo = 1.15, price = 1, mids = -1, lows = 1, hardpoints = 0,
    hulls = {},
    -- (The project owner's list of the Vessari's ships, 2026-11-13, with
    -- the seed each is drawn from in resource/hull/seeds.txt. They have
    -- no attack battlecruiser, dreadnought, siege dreadnought or
    -- supercarrier, and no barge of their own. Their ultracapital is
    -- four kilometres wide: the hull its seed grows is very nearly as
    -- wide as it is long, so it is 2,060 m in radius.)
    line = {
      { name = "Akashi", class = "frigate" }, { name = "Kabuto", class = "frigate" },
      { name = "Nozomi", class = "destroyer" },
      { name = "Kanau", class = "destroyer", tech = 2, of = "Nozomi" },
      { name = "Ouyou", class = "cruiser" },
      { name = "Naishou", class = "battlecruiser" },
      { name = "Owari", class = "battleship" }, { name = "Yoake", class = "battleship" },
      { name = "Azayake", class = "carrier" },
      { name = "Daiichi", class = "ultracapital", radius = 2060 },
      { name = "Mizumushi", class = "industrial" },
      { name = "Akaboshi", class = "industrial", tech = 2, of = "Mizumushi", stealth = true },
      { name = "Yoruzake", class = "freighter" },
      { name = "Okami", class = "capitalindustrial", role = "miner", hardpoints = 10 },
    },
  },
  {
    -- (After the project owner's draft, 2026-11-10: humans, an
    -- ethno-theocracy; ships "kind of cloud-like, with rounded edges and
    -- protrusions", with Star Wars' Mon Calamari cruisers as the visual
    -- point of reference. The draft says nothing of weapons or defence:
    -- those are as they were.)
    id = "talmar", name = "Talmar", kind = "human", style = "cloud", weapon = "projectile", launchers = 0.35, tank = "shield",
    affinity = 3,
    note = "Guns, missiles and shields. Hulls like clouds: rounded, lobed and blistered, without a corner on them, fast for their class.",
    paint = { primary = { 0.62, 0.66, 0.70 }, secondary = { 0.15, 0.32, 0.55 }, glow = { 0.45, 0.75, 1.0 } },
    shield = 1.2, armor = 0.85, hull = 0.95, velocity = 1.1, mass = 0.92, cpu = 1.1, powergrid = 0.95, capacitor = 0.95,
    lockRange = 1.0, cargo = 0.95, price = 1, mids = 1, lows = -1, hardpoints = 0,
    hulls = {},
    -- (The project owner's rework of the Talmar's ships, 2026-11-13:
    -- every hull of theirs, by name, with the seed each is drawn from in
    -- resource/hull/seeds.txt. They have no attack battlecruiser and no
    -- siege dreadnought.)
    line = {
      { name = "Carvarro", class = "frigate" }, { name = "Creavo", class = "frigate" },
      { name = "Meseolo", class = "destroyer" },
      { name = "Paestro", class = "cruiser" }, { name = "Stenanno", class = "cruiser" },
      { name = "Sopholto", class = "battlecruiser" },
      { name = "Phaeto", class = "battleship" }, { name = "Losiano", class = "battleship" },
      { name = "Scoppo", class = "carrier", jump = true },
      { name = "Concorso", class = "dreadnought" },
      { name = "Nullo", class = "supercarrier" },
      { name = "Sunfish", class = "industrial" },
      { name = "Tarantula", class = "industrial", tech = 2, of = "Sunfish", stealth = true },
      { name = "Armadillo", class = "industrial", role = "combat" },
      { name = "Anteater", class = "barge" },
      { name = "Rhino", class = "freighter" },
      { name = "Sugarglider", class = "freighter", tech = 2, of = "Rhino", jump = true },
      { name = "Jaguar", class = "capitalindustrial" },
      { name = "Rapa", class = "capitalindustrial", tech = 2, of = "Jaguar", jump = true },
    },
  },
  {
    -- (After the project owner's draft, 2026-11-11: the Orun
    -- Confederation; human, anarchist; "ships are very different in
    -- style from each other, because they're designed by different
    -- groups within the confederation. Unifying visual feature is red
    -- and gold highlights. Also, they tend to have a lot of antenna
    -- masts." The draft says nothing of weapons or defence: those are as
    -- they were.)
    id = "orun", name = "Orun", kind = "human", style = "motley", weapon = "hybrid", launchers = 0, tank = "armor",
    affinity = 2,
    note = "Blasters, railguns and sheer bulk. The Confederation's hulls come from yards that agree on nothing: no two are built alike, and all of them wear red and gold and a thicket of aerials. Slow, hard to kill, and they carry a great deal.",
    paint = { primary = { 0.36, 0.37, 0.39 }, secondary = { 0.62, 0.09, 0.07 }, glow = { 1.0, 0.84, 0.50 } },
    shield = 0.9, armor = 1.15, hull = 1.4, velocity = 0.9, mass = 1.12, cpu = 0.95, powergrid = 1.1, capacitor = 1.0,
    lockRange = 0.9, cargo = 1.25, price = 1, mids = 0, lows = 0, hardpoints = 0,
    hulls = {},
    -- (The project owner's list of the Orun's ships, 2026-11-13, with
    -- the seed each is drawn from in resource/hull/seeds.txt. A tech 2
    -- hull of theirs is grown from the seed of the hull it comes of, at
    -- another size. They have no attack battlecruiser, dreadnought or
    -- supercarrier. The Stag leads a mining fleet: a capital industrial
    -- as the class is, with the ore hold the fleet's barges fill.)
    line = {
      { name = "Skinner", class = "frigate" },
      { name = "Skiver", class = "frigate", tech = 2, of = "Skinner", stealth = true, cloak = true },
      { name = "Knife", class = "frigate" },
      { name = "Scythe", class = "destroyer" },
      { name = "Kama", class = "destroyer", tech = 2, of = "Scythe" },
      { name = "Armer", class = "cruiser" }, { name = "Gladius", class = "cruiser" },
      { name = "Falchion", class = "cruiser", tech = 2, of = "Gladius", explorer = true },
      { name = "Zweihander", class = "battlecruiser" },
      { name = "Claymore", class = "battleship" },
      { name = "Katana", class = "carrier" },
      { name = "Sword", class = "siegedreadnought" },
      { name = "Scarab", class = "barge" },
      { name = "Pill", class = "industrial" },
      { name = "Longhorn", class = "industrial", tech = 2, of = "Pill", stealth = true },
      { name = "Tiger", class = "freighter" },
      { name = "Stag", class = "capitalindustrial" },
    },
  },
  {
    -- (Lasers and armour by the project owner's decision, 2026-11-10,
    -- when the Vessari took missiles. By the owner's draft of 2026-11-11
    -- they are nomads: "no fixed stations, instead they have massive
    -- (talking 10km long, 1km wide) colony ships, that serve as mobile
    -- stations and fleet docks", in the manner of "sharp edges, flat grey
    -- plates, arrowheads, conning towers".)
    -- (2026-11-13, the owner: "an 80/20 mix of lasers/missiles": two
    -- hardpoints in ten are launchers. Their frigate, the hull written
    -- out by hand in Data/Ships, is small enough to be all lasers.)
    id = "kethri", name = "Kethri", kind = "human", style = "blade", weapon = "laser", launchers = 0.2, tank = "armor", nomad = true,
    affinity = 1,
    note = "Lasers, with missiles beside them, and armour. Nomads, who keep no stations and live aboard colony ships ten kilometres long. Their hulls are blades in flat grey plate, sharp at every edge, each with its conning tower: deep capacitors, long sight, and never out of ammunition.",
    paint = { primary = { 0.24, 0.30, 0.46 }, secondary = { 0.80, 0.80, 0.84 }, glow = { 0.55, 0.60, 1.0 } },
    shield = 0.85, armor = 1.25, hull = 1.0, velocity = 0.97, mass = 1.03, cpu = 0.95, powergrid = 1.1, capacitor = 1.15,
    lockRange = 1.2, cargo = 1.0, price = 1, mids = -1, lows = 1, hardpoints = 0,
    hulls = {},
    -- (The project owner's list of the Kethri's ships, 2026-11-13, with
    -- the seed each is drawn from in resource/hull/seeds.txt. It is a
    -- short list, "mostly because of the ultracapital": they have no
    -- cruiser, attack battlecruiser, dreadnought, siege dreadnought or
    -- supercarrier. The Battleaxe is the hand-written laser frigate of
    -- Data/Ships, which was the Lancer. The Piton leads a mining fleet,
    -- as the Orun's Stag does.
    -- The last is their colony ship, the class "Les Larmes de Nova": ten
    -- kilometres long, with "50 Sm/40 Md /30 Lg /20 XL turrets"; "not
    -- purchaseable anywhere... though it may be *buildable* via
    -- extremely rare blueprint". It roams their space with its support
    -- fleet in tow: Tactical/Nomads.)
    line = {
      { name = "Battleaxe", class = "frigate" },
      { name = "Sentry", class = "destroyer" },
      { name = "Extremis", class = "battlecruiser" },
      { name = "Teardrop", class = "battleship" },
      { name = "Tennit", class = "carrier" },
      { name = "Porter", class = "industrial" },
      { name = "Hiven", class = "freighter" },
      { name = "Pulley", class = "barge" },
      { name = "Piton", class = "capitalindustrial" },
      { name = "Les Larmes de Nova", class = "ultracapital", radius = 5000, guns = { 50, 40, 30, 20 }, rare = true },
    },
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
    hulls = { frigate = "Cutthroat", destroyer = "Jackal", cruiser = "Marauder", battleship = "Ravager", industrial = "Fence",
      attackbattlecruiser = "Reaver", battlecruiser = "Brigand", carrier = "Warren", dreadnought = "Tyrant", siegedreadnought = "Despoiler", capitalindustrial = "Hoard", supercarrier = "Matriarch" },
    -- (Nobody builds an attack battlecruiser now that every human
    -- faction's ships are the owner's list of them: the pirates' is the
    -- Kethri's battlecruiser, cut down. And the capitals the Kethri
    -- built are from those who build them still.)
    cut = { attackbattlecruiser = "battlecruiser" },
    donors = { frigate = "talmar", destroyer = "orun", cruiser = "vessari", battleship = "kethri", industrial = "orun",
      attackbattlecruiser = "kethri", battlecruiser = "vessari", carrier = "orun", dreadnought = "talmar", siegedreadnought = "orun",
      capitalindustrial = "talmar", supercarrier = "talmar" },
  },

  -- The three alien factions. Nothing of theirs is sold on a human
  -- market, and nobody has a blueprint for it.
  --
  -- The Vail (the owner's, 2026-11-11): aliens who go on two legs and
  -- crew their ships as people do.
  -- Their ships are the owner's list of them (2026-11-15, the "Vail
  -- Ship Rework"): seventeen hulls by name, each a seed in the
  -- generator's triangular styles (resource/hull/seeds.txt), some with
  -- their sides unalike. The list takes the place of the hulls there
  -- were: five modelled from the owner's drawings (docs/concepts/vail,
  -- script/modelgen; the models are kept, and are no hull of the game
  -- now) and seven stand-ins. They build no hauler, no siege
  -- dreadnought and no supercarrier.
  -- Two of the seventeen are tech 2 hulls. The Aberration is the
  -- Adoration's, of its seed, and the plain tech 2 make (the owner's
  -- word: "aberration is plain t2 package"). The Interstition is "black
  -- ops": built to go unseen, as the Nimia's Hano is; it is taken for
  -- the make of the Enervation, the one plain cruiser they build,
  -- though its seed is its own. The Embrace ("mining fleet boss") leads
  -- a mining fleet as the Orun's Stag does: a capital industrial as the
  -- class is, with the ore hold the fleet's barges fill.
  -- The Archangel ("mining fleet jumpship" on the list) is their
  -- ultracapital, by the owner's word the same day: "roughly 1.5x as
  -- large as the plain Embrace, but its real feature is that it has an
  -- AOE jump drive, allowing it to jump any friendly ships within a
  -- certain distance (5km). This allows it to evac its mining fleet."
  -- So it is 1,050 m in radius where the Embrace is 700, of the
  -- Embrace's seed grown bigger, and its jump drive has a field five
  -- kilometres deep ('jumpField': Tactical/Jumping). It is a hull of
  -- its own in that class and no tech 2 make (a tech 2 make is of its
  -- hull's class), and being so much smaller than the class is written
  -- for it is that much less of one in bulk (Data/Ships).
  -- Their weapons, their defences and the figures below are still what
  -- was put here before any of it came: none of that is the owner's yet.
  -- (Their towers and their paint are still from the drawings: brown
  -- and charcoal, lit in amber.)
  {
    id = "vail", name = "Vail", kind = "alien", style = "wedge", weapon = "laser", launchers = 0, tank = "shield",
    note = "Ships like spearheads: broad flat hulls drawn to a point, stepped with decks and towers, and some with one side not the other's twin. Beams of great reach, behind shields that mend in moments.",
    paint = { primary = { 0.40, 0.27, 0.16 }, secondary = { 0.14, 0.14, 0.14 }, glow = { 1.0, 0.66, 0.24 } },
    shield = 1.5, armor = 0.5, hull = 0.6, velocity = 1.05, mass = 0.8, cpu = 1.3, powergrid = 1.3, capacitor = 1.5,
    lockRange = 1.4, cargo = 0.5, price = 3, mids = 2, lows = -2, hardpoints = 0,
    hulls = {},
    line = {
      { name = "Prostration", class = "frigate" }, { name = "Undulation", class = "frigate" },
      { name = "Exaltation", class = "destroyer" }, { name = "Adoration", class = "destroyer" },
      { name = "Aberration", class = "destroyer", tech = 2, of = "Adoration" },
      { name = "Enervation", class = "cruiser" },
      { name = "Interstition", class = "cruiser", tech = 2, of = "Enervation", stealth = true },
      { name = "Intervention", class = "attackbattlecruiser" },
      { name = "Innocence", class = "battlecruiser" },
      { name = "Penance", class = "battleship" }, { name = "Extravagance", class = "battleship" },
      { name = "Accordance", class = "carrier" },
      { name = "Awe", class = "dreadnought" },
      { name = "Panacea", class = "barge" },
      { name = "Indulgence", class = "freighter" },
      { name = "Embrace", class = "capitalindustrial" },
      { name = "Archangel", class = "ultracapital", radius = 1050, jump = true, jumpField = 5000 },
    },
  },
  -- The Nimia (the owner's, 2026-11-13; they were the "Skarn", a
  -- stand-in of animal ships, until the owner said who they are): "Not
  -- crystalline aliens, bipedal and bird-like, with liquid-metal,
  -- bulbous, self-healing ships. No shields, but hull and armor
  -- self-repair over time. Faction-specific shipmods, modules (low
  -- slots), and skills that increase repair rate. Short-range plasma
  -- weapons."
  -- So a hull of theirs has no shield at all, and its armour and its
  -- hull mend by themselves ('mends': the share of each that comes back
  -- in a second, Tactical/Combat), which rigs, a low-slot module and two
  -- skills of their own make faster (Data/Modules, Data/Skills). Their
  -- guns are blasters, the short-range hybrid turret, which is what
  -- fires plasma (weapons are nobody's own, by the owner's rule: this
  -- is what they carry, and what their hulls are shown with).
  -- Their ships are the owner's list of them, each a seed in the
  -- generator's "soft" style (resource/hull/seeds.txt). The figures
  -- (how much armour and hull stands in for the shield they have not,
  -- how fast it mends, the slots) are first ones.
  -- Their mining capital (the Zzna) is taken for a plain capital
  -- industrial, an ore hold and no turret, as the Orun's and the
  -- Kethri's are; and their logistics capital (the Knuu, "ship
  -- transport") for a capital industrial with a bay for packed hulls
  -- where the others have an ore hold ('role' "transport": Data/Ships).
  {
    id = "nimia", name = "Nimia", kind = "alien", style = "liquid", weapon = "hybrid", launchers = 0, tank = "armor",
    note = "Ships of living metal, round and without a seam. They carry no shield: their armour and their hull flow back together by themselves. They close fast and burn at short range, with plasma.",
    paint = { primary = { 0.62, 0.64, 0.68 }, secondary = { 0.30, 0.34, 0.40 }, glow = { 0.55, 0.85, 1.0 } },
    shield = 0, armor = 1.8, hull = 1.5, velocity = 1.15, mass = 1.0, cpu = 0.9, powergrid = 1.2, capacitor = 0.9,
    lockRange = 0.7, cargo = 0.8, price = 3, mids = -1, lows = 2, hardpoints = 1,
    mends = { armor = 0.004, hull = 0.002 },
    hulls = {},
    line = {
      { name = "O'on", class = "frigate" },
      { name = "Kri", class = "destroyer" },
      { name = "Ka'va", class = "cruiser" }, { name = "Hon", class = "cruiser" },
      { name = "Hano", class = "cruiser", tech = 2, of = "Hon", stealth = true },
      { name = "Hoku", class = "battlecruiser" },
      { name = "R'ru", class = "battleship" },
      { name = "Zzk", class = "siegedreadnought" },
      { name = "Takk", class = "carrier" },
      { name = "Yuln", class = "supercarrier" },
      { name = "Rikn", class = "industrial" },
      { name = "Joj'k", class = "freighter" },
      { name = "Zzna", class = "capitalindustrial" },
      { name = "Knuu", class = "capitalindustrial", role = "transport" },
    },
  },
  -- The Drowned (the owner's, 2026-11-15; they were the "Tessellate", a
  -- stand-in of machines, until the owner said who they are): "An
  -- aquatic alien species who get their name because of both their
  -- windowless, fluid-filled ships, and because they have never been
  -- seen or captured alive; any time their ships are captured and
  -- opened, they are already dead. It's unknown whether this is due to
  -- suicide to avoid capture, a function of pressure-loss at having
  -- their hull opened, or some other cause. Some have speculated that
  -- they have been dead for millennia, preserved in their pressurized
  -- fluid capsules, and their ship AIs are simply carrying on fighting
  -- themselves. They are found in the 'deep' wormhole systems, and their
  -- ships are both dangerous and lucrative, made up of exotic hull
  -- materials to handle the extreme pressure differential between their
  -- native environment and space. Their ships' most discernible feature
  -- - an outrigger-like hull used for housing a special cloaking
  -- generator - has been adopted into several advanced human ship
  -- designs. All of their non-t2 hulls have this builtin cloak, which
  -- does not eat into their CPU/PG for fitting (but obviously does use
  -- power when running)."
  -- So they are the people of the deep the fourth and fifth depths of
  -- uncharted space were kept for ('deep': they hold nothing on the
  -- map, and are met there and nowhere else, Tactical/Pirates); every
  -- plain hull of theirs has a cloak of its own ('cloaks'), which takes
  -- nothing to fit and draws on the capacitor while it is on
  -- (Tactical/Combat); and a wreck of theirs has the stuff of its hull
  -- in it ('wreck': Tactical/Aftermath).
  -- Their ships are the owner's list of them, each a seed in the
  -- generator's asymmetrical styles (resource/hull/seeds.txt): the
  -- lesser hull out on one side is the outrigger. Two are tech 2 hulls
  -- ("no builtin cloak. can fit jumpdrive"): the Rebirth, of the
  -- Casket, and the Resurrection, of the Cemetery; each has a jump
  -- drive, and no cloak of its own. The End is their ultracapital and
  -- their special ship ("special, fixed bow railgun": Data/Ships'
  -- 'spinal'), and the Griever a capital industrial that mines for
  -- itself and refines what it mines ("mass-miner, mobile refinery").
  -- What is not the owner's: that their guns are railguns (the one gun
  -- of theirs that is named is one), that they hold nothing on the map,
  -- the name of what their hulls are made of, and every figure. The
  -- figures are the stand-in's, which suit a heavy hull full of water.
  {
    id = "drowned", name = "Drowned", kind = "alien", style = "outrigger", weapon = "hybrid", gun = "railgun", launchers = 0, tank = "hull",
    deep = true, cloaks = true, wreck = "alloy.benthic",
    note = "Nobody has seen one alive. Their ships are windowless and full of fluid, and whoever is aboard is dead by the time a hull is opened: some say they have been dead for millennia, and the ships fight on by themselves. They are met only in the deepest uncharted space. Every hull carries a cloak in the lesser hull on its flank, and is built of alloys made for crushing depths, which are worth a great deal.",
    paint = { primary = { 0.10, 0.10, 0.12 }, secondary = { 0.75, 0.75, 0.78 }, glow = { 1.0, 0.95, 0.80 } },
    shield = 0.9, armor = 1.1, hull = 2.2, velocity = 0.7, mass = 1.5, cpu = 1.4, powergrid = 1.2, capacitor = 1.2,
    lockRange = 1.6, cargo = 1.0, price = 3, mids = 0, lows = 0, hardpoints = 0,
    hulls = {},
    line = {
      { name = "Cairn", class = "frigate" }, { name = "Charon", class = "frigate" },
      { name = "Gravestone", class = "destroyer" },
      { name = "Casket", class = "cruiser" },
      { name = "Rebirth", class = "cruiser", tech = 2, of = "Casket", jump = true },
      { name = "Graveyard Keeper", class = "battlecruiser" },
      { name = "Coffin", class = "battleship" },
      { name = "Funeral Procession", class = "carrier" },
      { name = "The Reaper", class = "dreadnought" },
      { name = "The Mercy", class = "siegedreadnought" },
      { name = "The End", class = "ultracapital" },
      { name = "Hearse", class = "industrial" },
      { name = "Griever", class = "capitalindustrial", role = "miner", hardpoints = 10 },
      { name = "Cemetery", class = "freighter" },
      { name = "Resurrection", class = "freighter", tech = 2, of = "Cemetery", jump = true },
    },
  },
} :: { Faction }

Factions.byId = {} :: { [string]: Faction }
for _, faction in Factions.list do
  Factions.byId[faction.id] = faction
end

-- The classes every faction builds: the first five, and then (by the
-- project owner's ladder of 2026-11-12) the two kinds of battlecruiser
-- and the capitals. (The names of the hulls of those, above, are first
-- drafts.)
Factions.CLASSES = { "frigate", "destroyer", "cruiser", "battleship", "industrial",
  "attackbattlecruiser", "battlecruiser", "carrier", "dreadnought", "siegedreadnought", "capitalindustrial", "supercarrier" }

return Factions
