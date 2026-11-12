--!strict
-- Implants: what a pilot has put in their own head.
--
-- An implant is an item until it is plugged in, and then part of the
-- pilot: it makes every ship they fly a little better at one thing, for
-- as long as they keep it. There are five places for one, and two
-- implants to choose between for each; and for the fifth place, four
-- more, each for one kind of weapon: whatever of that kind the pilot
-- fires does a twentieth more damage. One that is taken out is
-- destroyed, and a pilot whose capsule is destroyed loses them all
-- (Character/Implants has the rules).
--
-- (Hardwirings, cut down. Not yet: grades of the same implant, sets.)

local Modules = require("@lt/Core/Data/Modules")

export type Implant = {
  id: string,
  name: string,
  slot: number,           -- 1 to 5: the place it goes
  passive: { Modules.Modifier },
  note: string,
}

-- Every implant takes up next to nothing, and one for a later place
-- costs more.
local VOLUME, PRICE = 0.1, 400000

local function ship(attribute: string, factor: number): { Modules.Modifier }
  return { { on = "ship", attribute = attribute, op = "mul", value = factor } }
end

-- (every weapon of a family: Data/Modules)
local function weapons(family: string, attribute: string, factor: number): { Modules.Modifier }
  return { { on = "weapons", family = family, attribute = attribute, op = "mul", value = factor } }
end

local Implants = {}

Implants.SLOTS = 5

Implants.list = {
  { id = "implant.shield", name = "Field Lattice Implant", slot = 1, passive = ship("shield", 1.05), note = "5% more shield." },
  { id = "implant.armor", name = "Plating Sense Implant", slot = 1, passive = ship("armor", 1.05), note = "5% more armor." },
  { id = "implant.capacitor", name = "Deep Cell Implant", slot = 2, passive = ship("capacitor", 1.05), note = "5% more capacitor." },
  { id = "implant.recharge", name = "Flux Regulator Implant", slot = 2, passive = ship("capacitorRecharge", 0.95),
    note = "The capacitor refills 5% sooner." },
  { id = "implant.velocity", name = "Drive Tuner Implant", slot = 3, passive = ship("maxVelocity", 1.04), note = "4% more speed." },
  { id = "implant.agility", name = "Balance Implant", slot = 3, passive = ship("inertia", 0.95), note = "5% quicker to turn." },
  { id = "implant.cpu", name = "Co-processor Implant", slot = 4, passive = ship("cpu", 1.04), note = "4% more CPU." },
  { id = "implant.powergrid", name = "Grid Governor Implant", slot = 4, passive = ship("powergrid", 1.04), note = "4% more powergrid." },
  { id = "implant.targeting", name = "Long Eye Implant", slot = 5, passive = ship("lockRange", 1.08), note = "8% more targeting range." },
  { id = "implant.scan", name = "Quick Eye Implant", slot = 5, passive = ship("scanResolution", 1.08), note = "Locks 8% sooner." },
  -- For a kind of weapon: the fifth place is the eye's or the hand's.
  { id = "implant.laser", name = "Lens Hand Implant", slot = 5, passive = weapons("laser", "damageMultiplier", 1.05),
    note = "Lasers do 5% more damage." },
  { id = "implant.projectile", name = "Recoil Hand Implant", slot = 5, passive = weapons("projectile", "damageMultiplier", 1.05),
    note = "Projectile guns do 5% more damage." },
  { id = "implant.hybrid", name = "Coil Hand Implant", slot = 5, passive = weapons("hybrid", "damageMultiplier", 1.05),
    note = "Hybrid guns do 5% more damage." },
  { id = "implant.missile", name = "Flight Hand Implant", slot = 5, passive = weapons("missile", "damageMultiplier", 1.05),
    note = "Missiles do 5% more damage." },
} :: { Implant }

Implants.byId = {} :: { [string]: Implant }
for _, implant in Implants.list do
  Implants.byId[implant.id] = implant
end

Implants.VOLUME = VOLUME

-- What an implant costs.
function Implants.Price(implant: Implant): number
  return PRICE * implant.slot
end

return Implants
