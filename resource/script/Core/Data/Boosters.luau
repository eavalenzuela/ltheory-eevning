--!strict
-- Boosters: what a pilot takes to fly better for a while.
--
-- A booster is made from the gas of a vapour field (Data/Ores,
-- Tactical/Sites), and from nothing a station sells. Taken, it is at
-- work for half an hour: it makes every ship the pilot flies better at
-- one thing and, because nothing of the kind is free, a little worse at
-- another, for exactly as long. There are three kinds (the gunner's,
-- the hull's and the ship's), each made of a gas of its own, and two
-- boosters of each kind; a pilot can have one of each kind at work at
-- once, and has to wait for it to wear off before taking another of
-- that kind (Character/Boosters has the rules).
--
-- (Not yet: a skill that makes one last, boosters of other strengths,
-- one that goes wrong only now and then.)

local Modules = require("@lt/Core/Data/Modules")

export type Booster = {
  id: string,
  name: string,
  kind: number,           -- 1 to 3: the gunner's, the hull's, the ship's
  gas: string,            -- what it is made from (Data/Ores)
  passive: { Modules.Modifier },
  note: string,           -- what it gives
  cost: string,           -- what it takes
}

local FAMILIES = { "laser", "projectile", "hybrid", "missile" }
local TURRETS = { "laser", "projectile", "hybrid" }

local function ship(attribute: string, factor: number): Modules.Modifier
  return { on = "ship", attribute = attribute, op = "mul", value = factor }
end

-- The same change to every weapon of these families.
local function weapons(families: { string }, attribute: string, factor: number): { Modules.Modifier }
  local made: { Modules.Modifier } = {}
  for _, family in families do
    table.insert(made, { on = "weapons", family = family, attribute = attribute, op = "mul", value = factor })
  end
  return made
end

local function all(...: { Modules.Modifier } | Modules.Modifier): { Modules.Modifier }
  local made: { Modules.Modifier } = {}
  for _, part in { ... } do
    local one = part :: any
    if one.attribute then
      table.insert(made, one)
    else
      for _, modifier in one do
        table.insert(made, modifier)
      end
    end
  end
  return made
end

local Boosters = {}

Boosters.KINDS = { "Gunner's", "Hull", "Ship" }
-- Seconds one is at work for.
Boosters.SECONDS = 1800
Boosters.VOLUME = 0.2
Boosters.PRICE = 18000
-- What a run of a booster's blueprint takes of its gas, and of silicon
-- (Data/Blueprints).
Boosters.GAS = 40
Boosters.SILICON = 150

Boosters.list = {
  { id = "booster.redline", name = "Redline", kind = 1, gas = "gas.amber",
    passive = all(weapons(FAMILIES, "damageMultiplier", 1.10), ship("shield", 0.90)),
    note = "Every weapon does 10% more damage.", cost = "10% less shield." },
  { id = "booster.deadeye", name = "Deadeye", kind = 1, gas = "gas.amber",
    passive = all(weapons(TURRETS, "tracking", 1.25), weapons(TURRETS, "optimal", 1.15), ship("maxVelocity", 0.93)),
    note = "Turrets track 25% better and reach 15% further.", cost = "7% less speed." },
  { id = "booster.thickskin", name = "Thickskin", kind = 2, gas = "gas.verdant",
    passive = all(ship("armor", 1.15), ship("maxVelocity", 0.92)),
    note = "15% more armor.", cost = "8% less speed." },
  { id = "booster.halo", name = "Halo", kind = 2, gas = "gas.verdant",
    passive = all(ship("shield", 1.15), ship("shieldRecharge", 0.88), ship("capacitor", 0.92)),
    note = "15% more shield, and it comes back 12% sooner.", cost = "8% less capacitor." },
  { id = "booster.longburn", name = "Longburn", kind = 3, gas = "gas.azure",
    passive = all(ship("capacitorRecharge", 0.80), ship("lockRange", 0.85)),
    note = "The capacitor refills 20% sooner.", cost = "15% less targeting range." },
  { id = "booster.slipstream", name = "Slipstream", kind = 3, gas = "gas.azure",
    passive = all(ship("maxVelocity", 1.15), ship("inertia", 0.90), ship("armor", 0.92)),
    note = "15% more speed, and 10% quicker to turn.", cost = "8% less armor." },
} :: { Booster }

Boosters.byId = {} :: { [string]: Booster }
for _, booster in Boosters.list do
  Boosters.byId[booster.id] = booster
end

return Boosters
