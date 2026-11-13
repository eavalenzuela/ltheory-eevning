--!strict
-- Boosters: what a pilot takes to fly better for a while.
--
-- A booster is made from the gas of a vapour field (Data/Ores,
-- Tactical/Sites), and from nothing a station sells. Taken, it is at
-- work for half an hour: it makes every ship the pilot flies better at
-- one thing. And nothing of the kind is free: one time in two it sits
-- badly, and makes the ship a little worse at another thing for
-- exactly as long. There are three kinds (the gunner's, the hull's and
-- the ship's), each made of a gas of its own, and two boosters of each
-- kind; a pilot can have one of each kind at work at once, and has to
-- wait for it to wear off before taking another of that kind
-- (Character/Boosters has the rules).
--
-- Each comes in three strengths (Boosters.STRENGTHS). The plain one is
-- as above. A mild one does half the good and never sits badly: it is
-- made of half of everything. A strong one does half as much good
-- again, sits badly oftener, and takes half as much again when it does:
-- it is made of two of the plain one and as much gas and silicon again,
-- so somebody has to have made those first.
--
-- Two skills are for them (Data/Skills): Pharmacology makes one last a
-- fifth longer a level, and Tolerance makes its ill effect strike less
-- often, to one time in ten for a plain one.

local Modules = require("@lt/Core/Data/Modules")

export type Booster = {
  id: string,
  name: string,
  -- The booster it is a strength of ("redline"), and which strength: 1
  -- mild, 2 plain, 3 strong (Boosters.STRENGTHS).
  family: string,
  strength: number,
  kind: number,           -- 1 to 3: the gunner's, the hull's, the ship's
  gas: string,            -- what it is made from (Data/Ores)
  gives: { Modules.Modifier },  -- the good it does,
  takes: { Modules.Modifier },  -- and what it costs when it sits badly;
  passive: { Modules.Modifier },  -- the two together
  note: string,           -- what it gives
  cost: string,           -- what it may take ("" for one that never sits badly)
  wrong: number,          -- the chance that it sits badly, before any skill
  price: number,
}

-- A strength: what it is called, how much of the plain booster's good
-- it does and how much of its ill, the chance that it sits badly, and
-- what one is listed at.
export type Strength = { name: string, suffix: string, good: number, ill: number, wrong: number, price: number }

-- (as it is written below, for a strength: 'k' scales the good it does
-- and 'c' what it costs)
type Written = { family: string, name: string, kind: number, gas: string,
  make: (k: number, c: number) -> ({ Modules.Modifier }, { Modules.Modifier }, string, string) }

-- A factor that is so much more than one, or so much less: to four
-- places, so that a tenth more is 1.1 and seven hundredths less 0.93,
-- as they are written.
local function more(share: number): number
  return math.floor((1 + share) * 10000 + 0.5) / 10000
end
local function less(share: number): number
  return math.floor((1 - share) * 10000 + 0.5) / 10000
end

-- A share as it is said: "10%", "7.5%".
local function pct(value: number): string
  return (string.gsub(string.format("%.1f", value), "%.0$", "")) .. "%"
end

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
-- Seconds one is at work for, and how much longer for each level of
-- Pharmacology.
Boosters.SECONDS = 1800
Boosters.LONGER = 0.2
-- The chance that one sits badly, and how much less it is for each
-- level of Tolerance.
Boosters.WRONG = 0.5
Boosters.TOLERANCE = 0.08
Boosters.VOLUME = 0.2
Boosters.PRICE = 18000
-- What a run of a booster's blueprint takes of its gas, and of silicon
-- (Data/Blueprints); and of the plain booster, for a strong one.
Boosters.GAS = 40
Boosters.SILICON = 150
Boosters.DOSES = 2

-- The strengths, in order. (The plain one's figures are the ones above.
-- The others are first figures, mine.)
Boosters.MILD, Boosters.PLAIN, Boosters.STRONG = 1, 2, 3
Boosters.STRENGTHS = {
  { name = "Mild", suffix = ".mild", good = 0.5, ill = 0, wrong = 0, price = Boosters.PRICE // 2 },
  { name = "", suffix = "", good = 1, ill = 1, wrong = Boosters.WRONG, price = Boosters.PRICE },
  -- (two plain ones and a plain one's makings are in it, at the share of
  -- its price that anything's makings are: Data/Blueprints)
  { name = "Strong", suffix = ".strong", good = 1.5, ill = 1.5, wrong = Boosters.WRONG + 0.15, price = Boosters.PRICE * 13 // 3 },
} :: { Strength }

local written: { Written } = {
  { family = "redline", name = "Redline", kind = 1, gas = "gas.amber", make = function(k: number, c: number)
    return weapons(FAMILIES, "damageMultiplier", more(0.10 * k)), all(ship("shield", less(0.10 * c))),
      `Every weapon does {pct(10 * k)} more damage.`, `{pct(10 * c)} less shield.`
  end },
  { family = "deadeye", name = "Deadeye", kind = 1, gas = "gas.amber", make = function(k: number, c: number)
    return all(weapons(TURRETS, "tracking", more(0.25 * k)), weapons(TURRETS, "optimal", more(0.15 * k))), all(ship("maxVelocity", less(0.07 * c))),
      `Turrets track {pct(25 * k)} better and reach {pct(15 * k)} further.`, `{pct(7 * c)} less speed.`
  end },
  { family = "thickskin", name = "Thickskin", kind = 2, gas = "gas.verdant", make = function(k: number, c: number)
    return all(ship("armor", more(0.15 * k))), all(ship("maxVelocity", less(0.08 * c))),
      `{pct(15 * k)} more armor.`, `{pct(8 * c)} less speed.`
  end },
  { family = "halo", name = "Halo", kind = 2, gas = "gas.verdant", make = function(k: number, c: number)
    return all(ship("shield", more(0.15 * k)), ship("shieldRecharge", less(0.12 * k))), all(ship("capacitor", less(0.08 * c))),
      `{pct(15 * k)} more shield, and it comes back {pct(12 * k)} sooner.`, `{pct(8 * c)} less capacitor.`
  end },
  { family = "longburn", name = "Longburn", kind = 3, gas = "gas.azure", make = function(k: number, c: number)
    return all(ship("capacitorRecharge", less(0.20 * k))), all(ship("lockRange", less(0.15 * c))),
      `The capacitor refills {pct(20 * k)} sooner.`, `{pct(15 * c)} less targeting range.`
  end },
  { family = "slipstream", name = "Slipstream", kind = 3, gas = "gas.azure", make = function(k: number, c: number)
    return all(ship("maxVelocity", more(0.15 * k)), ship("inertia", less(0.10 * k))), all(ship("armor", less(0.08 * c))),
      `{pct(15 * k)} more speed, and {pct(10 * k)} quicker to turn.`, `{pct(8 * c)} less armor.`
  end },
}

-- Every booster, family by family: the plain one first (as the list
-- was before there were strengths), then the mild and the strong.
Boosters.list = {} :: { Booster }
Boosters.byId = {} :: { [string]: Booster }
for _, each in written do
  for _, strength in { Boosters.PLAIN, Boosters.MILD, Boosters.STRONG } do
    local how = Boosters.STRENGTHS[strength]
    local gives, takes, note, cost = each.make(how.good, how.ill)
    if how.ill == 0 then
      takes, cost = {}, ""
    end
    local booster: Booster = {
      id = "booster." .. each.family .. how.suffix, name = if how.name ~= "" then `{how.name} {each.name}` else each.name,
      family = each.family, strength = strength, kind = each.kind, gas = each.gas, gives = gives, takes = takes,
      passive = all(gives, takes), note = note, cost = cost, wrong = how.wrong, price = how.price,
    }
    table.insert(Boosters.list, booster)
    Boosters.byId[booster.id] = booster
  end
end

-- The plain booster a strong one is made of.
function Boosters.Plain(booster: Booster): Booster
  return Boosters.byId["booster." .. booster.family]
end

return Boosters
