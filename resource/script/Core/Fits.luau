--!strict
-- A standard fit: what a hull carries where nobody has said. It is what
-- a hull grown from a seed is shown carrying (Game/View/Hull), what a
-- cheat boards a hull with (App/game's Fly), and what every hull is
-- measured with in the balance report (Tool/balance), so that the three
-- do not each have a notion of their own.
--
-- The weapons are the hull's faction's kind of gun and launchers, of
-- the size its class is for (the owner's ladder: a battleship's on an
-- attack battlecruiser, a cruiser's on a battlecruiser, large and
-- medium by turns on a dreadnought, and the largest there are on a
-- siege dreadnought). The rest is a plain tank: an afterburner, two
-- shield extenders, a plate, a repairer, a damage control and another
-- plate, of the hull's size. Nothing of it is anybody's recommended fit:
-- it is the same recipe for every hull, which is what makes two hulls'
-- figures comparable.

local Attributes = require("@lt/Core/Attributes")
local Factions = require("@lt/Core/Data/Factions")
local Modules = require("@lt/Core/Data/Modules")
local Ships = require("@lt/Core/Data/Ships")

local Fits = {}

local GUN: { [string]: string } = { laser = "laser.pulse", projectile = "autocannon", hybrid = "blaster" }
local RACK = { "launcher.light", "launcher.heavy", "launcher.cruise", "launcher.siege" }
local WORD = { "small", "medium", "large", "xl" }
local SIZES: { [string]: { number } } = { frigate = { 1 }, destroyer = { 1 }, cruiser = { 2 }, battleship = { 3 },
  attackbattlecruiser = { 3 }, battlecruiser = { 2 }, dreadnought = { 3, 2 }, siegedreadnought = { 4 } }

-- The weapons a hull is shown and measured with: one for each of its
-- hardpoints, turrets first.
function Fits.Weapons(hull: Ships.ShipType): { string }
  local faction = Factions.byId[hull.lineage]
  local family = if faction then faction.weapon else "projectile"
  -- (the make of gun: its family's first, unless its people carry another: the Drowned's railguns)
  local gun = if faction and faction.gun then faction.gun else GUN[family] or "autocannon"
  local sizes = SIZES[hull.class] or { 1 }
  local fit: { string } = {}
  -- (a hull whose hardpoints are of given sizes, the Kethri's colony
  -- ship: a gun of its size on each, the biggest first, which have the
  -- first pick of where to stand; and its launchers likewise)
  local guns, racks = hull.guns, hull.racks
  if guns and racks then
    for size = #guns, 1, -1 do
      for _ = 1, guns[size] do
        table.insert(fit, `{gun}.{WORD[size]}`)
      end
    end
    for size = #racks, 1, -1 do
      for _ = 1, racks[size] do
        table.insert(fit, RACK[size])
      end
    end
    return fit
  end
  for index = 1, hull.turrets do
    local size = sizes[(index - 1) % #sizes + 1]
    -- (a mass-miner's turrets are for mining, and a barge's; and a
    -- projectile people's bigger guns are artillery, as the Vessari's
    -- hulls were drawn with)
    table.insert(fit, if hull.role == "miner" or hull.class == "barge" then "miner.strip"
      elseif family == "projectile" and size >= 2 then `artillery.{WORD[size]}`
      else `{gun}.{WORD[size]}`)
  end
  for index = 1, hull.launchers do
    table.insert(fit, RACK[sizes[(index - 1) % #sizes + 1]])
  end
  return fit
end

-- The size of module a hull's plain tank is made of.
function Fits.Size(hull: Ships.ShipType): string
  return if hull.class == "battleship" or hull.class == "attackbattlecruiser" or Ships.Capital(hull.class) then "large"
    elseif hull.class == "cruiser" or hull.class == "battlecruiser" then "medium" else "small"
end

-- What a plain fit has beside its weapons, in the order it is tried: an
-- afterburner, two shield extenders, a plate, a repairer, a damage
-- control and another plate, of the hull's size. (A hull with no
-- shield, which mends by itself, has its people's own gear where the
-- extenders would go: the Nimia's lattice, as their patrols have.)
function Fits.Tank(hull: Ships.ShipType): { string }
  local size = Fits.Size(hull)
  local plate = if size == "small" then "armor.plate.200mm" else "armor.plate." .. size
  local extender = if hull.shield <= 0 and (hull.armorMend or 0) > 0 then "mend.lattice" else "shield.extender." .. size
  return { if size == "small" then "afterburner.1mn" else "afterburner." .. size, extender, extender, plate,
    "armor.repairer." .. size, "damage.control", plate }
end

-- The charge a weapon is measured with: the first there is of its
-- family and size (the plain make, not a tech 2 one), and on a hull
-- that leans to a kind of damage (Data/Ships' affinity) the first of
-- that kind, where the weapon fires any. Nil for what is not a weapon,
-- or takes none.
function Fits.Charge(type: string, hull: Ships.ShipType?): string?
  local module = Modules.byId[type]
  local weapon = if module then module.weapon else nil
  if weapon == nil then
    return nil
  end
  local first: string? = nil
  for _, charge in Modules.charges do
    if charge.family == weapon.family and charge.size == weapon.size and charge.tech ~= 2 then
      first = first or charge.id
      if hull and hull.affinity and charge.damage[hull.affinity] > 0 then
        return charge.id
      end
    end
  end
  return first
end

-- What of a standard fit does not go on a hull, and why.
export type Refused = { type: string, why: string }

-- The standard fit of a hull: its weapons and then its plain tank, each
-- thing put on if the hull can carry it with what is on already
-- (Attributes.Check, with no skills), and left off if not. Returns what
-- is on, in that order, and what was left off.
function Fits.Standard(hull: Ships.ShipType): ({ string }, { Refused })
  local on: { string } = {}
  local off: { Refused } = {}
  local function try(list: { string })
    for _, type in list do
      if Modules.byId[type] == nil then
        table.insert(off, { type = type, why = "there is no such module" })
      else
        table.insert(on, type)
        local ok, why = Attributes.Check(hull, on)
        if not ok then
          table.remove(on)
          table.insert(off, { type = type, why = why or "it does not fit" })
        end
      end
    end
  end
  try(Fits.Weapons(hull))
  try(Fits.Tank(hull))
  return on, off
end

return Fits
