--!strict
-- The four yards: schools of shipbuilding, each shared by two powers.
--
-- A yard is what makes one power's ships and stations differ from
-- another's: how they are shaped, what they shoot, how they take a
-- hit. Two powers that share a yard build the same hulls and paint them
-- differently. A hull's 'lineage' (Data/Ships) is its yard's id.
--
-- The numbers here multiply a class's standard hull (Data/Ships), so a
-- yard's character holds from its frigate to its battleship.

local Yards = {}

-- Colours as red, green, blue from 0 to 1.
export type Paint = { primary: { number }, secondary: { number }, glow: { number } }

export type Yard = {
  id: string,
  name: string,
  powers: { string },       -- by name, as in Data/Powers
  -- How its hulls are built up (Game/View/Hull): "slab" broad armoured
  -- plates, "blade" long and swept, "bulb" rounded masses, "lattice"
  -- open frames and spars.
  style: "slab" | "blade" | "bulb" | "lattice",
  weapon: string,           -- the turret family its warships carry
  launchers: number,        -- the share of a warship's hardpoints that are launchers
  tank: "armor" | "shield",
  note: string,
  paint: { [string]: Paint },   -- by power name
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
  -- slots added to (or taken from) the standard layout
  mids: number,
  lows: number,
  -- its hulls, by class
  hulls: { [string]: string },
}

Yards.list = {
  {
    id = "vessari", name = "Vessari", powers = { "Vessari Compact", "Sable Concord" }, style = "slab",
    weapon = "laser", launchers = 0, tank = "armor",
    note = "Lasers and armour. Broad, plated hulls that give ground slowly and never run out of ammunition.",
    paint = {
      ["Vessari Compact"] = { primary = { 0.72, 0.58, 0.30 }, secondary = { 0.22, 0.20, 0.18 }, glow = { 1.0, 0.75, 0.35 } },
      ["Sable Concord"] = { primary = { 0.16, 0.17, 0.20 }, secondary = { 0.55, 0.12, 0.14 }, glow = { 1.0, 0.30, 0.25 } },
    },
    shield = 0.85, armor = 1.25, hull = 1.0, velocity = 0.95, mass = 1.05, cpu = 0.95, powergrid = 1.1, capacitor = 1.15,
    lockRange = 1.0, cargo = 1.0, mids = -1, lows = 1,
    hulls = { frigate = "Lancer", destroyer = "Halberd", cruiser = "Cuirass", battleship = "Bastion", industrial = "Caravan" },
  },
  {
    id = "talmar", name = "Talmar", powers = { "Talmar League", "Halcyon Reach" }, style = "blade",
    weapon = "projectile", launchers = 0.35, tank = "shield",
    note = "Guns, missiles and shields. Long, swept hulls that are fast for their class and fight on the move.",
    paint = {
      ["Talmar League"] = { primary = { 0.62, 0.66, 0.70 }, secondary = { 0.15, 0.32, 0.55 }, glow = { 0.45, 0.75, 1.0 } },
      ["Halcyon Reach"] = { primary = { 0.86, 0.86, 0.80 }, secondary = { 0.20, 0.55, 0.50 }, glow = { 0.50, 1.0, 0.85 } },
    },
    shield = 1.2, armor = 0.85, hull = 0.95, velocity = 1.1, mass = 0.92, cpu = 1.1, powergrid = 0.95, capacitor = 0.95,
    lockRange = 1.0, cargo = 0.95, mids = 1, lows = -1,
    hulls = { frigate = "Rapier", destroyer = "Sabre", cruiser = "Falchion", battleship = "Claymore", industrial = "Packet" },
  },
  {
    id = "orun", name = "Orun", powers = { "Orun Hegemony", "Dominion of Ash" }, style = "bulb",
    weapon = "hybrid", launchers = 0, tank = "armor",
    note = "Blasters, railguns and sheer bulk. Heavy, rounded hulls that are slow, hard to kill and carry a great deal.",
    paint = {
      ["Orun Hegemony"] = { primary = { 0.36, 0.40, 0.30 }, secondary = { 0.60, 0.42, 0.18 }, glow = { 0.75, 1.0, 0.40 } },
      ["Dominion of Ash"] = { primary = { 0.30, 0.28, 0.27 }, secondary = { 0.62, 0.30, 0.10 }, glow = { 1.0, 0.50, 0.15 } },
    },
    shield = 0.9, armor = 1.15, hull = 1.4, velocity = 0.9, mass = 1.12, cpu = 0.95, powergrid = 1.1, capacitor = 1.0,
    lockRange = 0.9, cargo = 1.25, mids = 0, lows = 0,
    hulls = { frigate = "Mastiff", destroyer = "Boar", cruiser = "Aurochs", battleship = "Mammoth", industrial = "Ox" },
  },
  {
    id = "kethri", name = "Kethri", powers = { "Kethri Union", "Meridian Trust" }, style = "lattice",
    weapon = "laser", launchers = 0.7, tank = "shield",
    note = "Missiles at long range, behind deep shields. Open-framed hulls that see far and are fragile once the shields are down.",
    paint = {
      ["Kethri Union"] = { primary = { 0.24, 0.30, 0.46 }, secondary = { 0.80, 0.80, 0.84 }, glow = { 0.55, 0.60, 1.0 } },
      ["Meridian Trust"] = { primary = { 0.50, 0.30, 0.52 }, secondary = { 0.85, 0.78, 0.55 }, glow = { 0.90, 0.55, 1.0 } },
    },
    shield = 1.3, armor = 0.75, hull = 0.9, velocity = 1.0, mass = 0.97, cpu = 1.15, powergrid = 0.95, capacitor = 1.0,
    lockRange = 1.3, cargo = 1.0, mids = 1, lows = -1,
    hulls = { frigate = "Spindle", destroyer = "Gantry", cruiser = "Trellis", battleship = "Spire", industrial = "Lighter" },
  },
} :: { Yard }

Yards.byId = {} :: { [string]: Yard }
local byPower: { [string]: Yard } = {}
for _, yard in Yards.list do
  Yards.byId[yard.id] = yard
  for _, power in yard.powers do
    byPower[power] = yard
  end
end

-- The yard a power builds in, by the power's name.
function Yards.Of(power: string): Yard?
  return byPower[power]
end

-- The classes every yard builds, smallest first.
Yards.CLASSES = { "frigate", "destroyer", "cruiser", "battleship", "industrial" }

return Yards
