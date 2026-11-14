--!strict
-- The standard fit (Core/Fits), and the balance report that measures
-- every hull with it (Tool/balance).

local Attributes = require("@lt/Core/Attributes")
local Balance = require("@lt/Tool/balance")
local Factions = require("@lt/Core/Data/Factions")
local Fits = require("@lt/Core/Fits")
local Modules = require("@lt/Core/Data/Modules")
local Ships = require("@lt/Core/Data/Ships")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Fits")

suite:Case("a hull's standard weapons are its faction's kind, of its class's size, one to a hardpoint, and it can carry every one", function(t)
  for _, hull in Ships.list do
    local faction = Factions.byId[hull.lineage]
    if faction and hull.class ~= "drone" then
      local weapons = Fits.Weapons(hull)
      t.eq(#weapons, hull.turrets + hull.launchers, hull.id)
      local turrets, launchers = 0, 0
      for _, type in weapons do
        local module = assert(Modules.byId[type], `{hull.id} is shown with '{type}', which is no module`)
        turrets += if module.hardpoint == "turret" then 1 else 0
        launchers += if module.hardpoint == "launcher" then 1 else 0
        -- (what it is measured with is loaded: there is a charge for every one, but a mining turret)
        t.ok(module.weapon == nil or Fits.Charge(type) ~= nil, `nothing to load {type} with`)
      end
      t.eq({ turrets, launchers } :: { any }, { hull.turrets, hull.launchers } :: { any }, hull.id)
      -- Every one of them goes on, with nothing else fitted: a hull that could not carry its own guns
      -- would be a hull nobody could fly as it is drawn.
      t.eq({ Attributes.Check(hull, weapons) } :: { any }, { true } :: { any }, hull.id)
    end
  end
  -- The kinds: lasers for a laser people, blasters for a hybrid one, autocannons and then artillery for a
  -- projectile one; and the sizes by class.
  t.eq(Fits.Weapons(Ships.byId["frigate.battleaxe"])[1], "laser.pulse.small")
  t.eq(Fits.Weapons(Ships.byId["frigate.oon"])[1], "blaster.small")
  t.eq(Fits.Weapons(Ships.byId["cruiser.gladius"])[1], "blaster.medium")
  t.eq(Fits.Weapons(Ships.byId["battleship.rru"])[1], "blaster.large")
  t.eq(Fits.Weapons(Ships.byId["siegedreadnought.sword"])[1], "blaster.xl")
  -- A mass-miner's turrets are for mining, and a barge's.
  t.eq(Fits.Weapons(Ships.byId["capitalindustrial.okami"])[1], "miner.strip")
  t.eq(Fits.Weapons(Ships.byId["barge.scarab"]), { "miner.strip", "miner.strip", "miner.strip" })
end)

suite:Case("the standard fit is the weapons and then a plain tank, each thing put on if it goes and left off with the reason if not", function(t)
  local akashi = Ships.byId["frigate.akashi"]
  t.eq(Fits.Size(akashi), "small")
  t.eq(Fits.Tank(akashi), { "afterburner.1mn", "shield.extender.small", "shield.extender.small", "armor.plate.200mm",
    "armor.repairer.small", "damage.control", "armor.plate.200mm" })
  t.eq({ Fits.Size(Ships.byId["cruiser.gladius"]), Fits.Size(Ships.byId["battleship.owari"]), Fits.Size(Ships.byId["carrier.katana"]) } :: { any },
    { "medium", "large", "large" } :: { any })
  -- A hull with no shield has its people's lattice where the extenders would go.
  local oon = Ships.byId["frigate.oon"]
  t.eq({ Fits.Tank(oon)[2], Fits.Tank(oon)[3] } :: { any }, { "mend.lattice", "mend.lattice" } :: { any })
  for _, hull in Ships.list do
    if Factions.byId[hull.lineage] and hull.class ~= "drone" then
      local on, off = Fits.Standard(hull)
      t.eq(#on + #off, #Fits.Weapons(hull) + 7, hull.id)
      -- What is on is a fit the hull can carry; and nothing was left off without a reason.
      t.eq({ Attributes.Check(hull, on) } :: { any }, { true } :: { any }, hull.id)
      for _, refused in off do
        t.ok(refused.why ~= "", `{hull.id}: {refused.type} left off for no reason`)
        t.ok(Modules.byId[refused.type] == nil or Modules.byId[refused.type].hardpoint == "", `{hull.id} cannot carry its own {refused.type}`)
      end
    end
  end
end)

suite:Case("the balance report has a line for every hull that is flown, with figures that make sense, and says who is the same as whom", function(t)
  local rows = Balance.Report()
  local flown = 0
  for _, hull in Ships.list do
    flown += if hull.class ~= "drone" and hull.class ~= "capsule" and hull.class ~= "works" then 1 else 0
  end
  t.eq(#rows, flown)
  local byId: { [string]: Balance.Row } = {}
  for _, row in rows do
    byId[row.id] = row
    t.ok(row.ehp > 0 and row.speed > 0 and row.price > 0 and row.capacitor > 0, row.id)
    t.ok(row.weapons <= row.wanted and row.fitted >= row.weapons, row.id)
    t.ok(row.cpu <= row.cpuMax + 1e-6 and row.powergrid <= row.powergridMax + 1e-6, row.id)
    t.ok(row.burn >= row.speed and row.lasts > 0, row.id)
    -- (it does damage if it has guns: a hull with no hardpoint, or with mining turrets on them, does none)
    t.eq(row.dps > 0, row.weapons > 0 and row.class ~= "barge" and row.id ~= "capitalindustrial.okami", row.id)
  end
  -- A hull of the Nimia's has no shield and mends; a tech 2 hull takes more to destroy than the one it comes of.
  local oon = byId["frigate.oon"]
  t.eq({ oon.shield, oon.mend > 5, oon.what } :: { any }, { 0, true, "mends" } :: { any })
  t.ok(byId["cruiser.falchion"].ehp > 1.3 * byId["cruiser.gladius"].ehp)
  t.eq(byId["frigate.skiver"].what, "own cloak, black ops")
  -- Two hulls of a class that a faction builds alike are said to be alike, each of the other; and two
  -- that are not (one holds ore and the other ships) are not.
  local function flagged(row: Balance.Row, words: string): boolean
    for _, flag in row.flags do
      if string.find(flag, words, 1, true) then
        return true
      end
    end
    return false
  end
  t.ok(flagged(byId["frigate.skinner"], "the same to the rules as Orun Knife") and flagged(byId["frigate.knife"], "the same to the rules as Orun Skinner"))
  t.ok(not flagged(byId["capitalindustrial.knuu"], "the same to the rules"))
  -- A tech 2 hull is not flagged for being more than the plain hulls of its class.
  t.ok(not flagged(byId["cruiser.falchion"], "for its class"))
end)

return suite
