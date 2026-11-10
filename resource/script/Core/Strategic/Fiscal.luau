--!strict
-- A power's money: what comes in and what goes out, every period.
--
-- In: the levy on what its people spend, system by system, in
-- proportion to how well they are supplied and how firmly it holds
-- them. That is all a power's income is. (The people's own money is not
-- simulated, so the levy enters from the world; the ledger shows it.)
--
-- Out: holding its systems, policing them, paying its crews, and the
-- fuel and ammunition its fleets use, bought on the market wherever
-- each fleet lies in its own space. A fleet abroad lives on what it
-- carries, and fights at half strength when that is gone.
--
-- A power that ends a period owing is in arrears. Nothing is scrapped
-- for it: ships can be laid up (a government's decision, in
-- Strategic/Mind), and after a grace the power loses its hold on one
-- system a period, the one it holds least firmly.

local Goods = require("@lt/Core/Data/Goods")
local Orders = require("@lt/Core/Strategic/Orders")
local Powers = require("@lt/Core/Data/Powers")
local World = require("@lt/Core/Strategic/World")

local Fiscal = {}

local FUEL = Goods.Index("fuel")
local AMMUNITION = Goods.Index("ammunition")

-- How fast the smoothed income and costs follow the latest period.
local SMOOTHING = 0.3

-- What a faction's crews cost an hour: those serving, and those laid up.
function Fiscal.Crews(world: World.World, faction: World.Faction): number
  local laidUp = 0
  for class, count in faction.reserve do
    laidUp += count * Powers.ships[class].strength
  end
  return World.Navy(world, faction.id) * Powers.PAY + laidUp * Powers.PAY_RESERVE
end

-- What holding and policing its systems costs a faction an hour.
function Fiscal.Fixed(world: World.World, faction: World.Faction): (number, number)
  local sov, police = 0, 0
  for id, s in world.systems do
    if s.owner == faction.id then
      sov += World.SovCost(world, faction, id, faction.systems)
      police += faction.policing * Powers.POLICE * (1 + world.atlas.systems[id].population)
    end
  end
  return sov, police
end

function Fiscal.Step(world: World.World)
  local hours = Powers.PERIOD_HOURS
  local factions = world.factions
  local n = #factions
  local levy: { number } = table.create(n, 0)
  local sov: { number } = table.create(n, 0)
  local police: { number } = table.create(n, 0)
  local crews: { number } = table.create(n, 0)
  local before: { number } = table.create(n, 0)
  for id, faction in factions do
    before[id] = faction.credits
  end

  for id, s in world.systems do
    local owner = s.owner
    if owner > 0 then
      local faction = factions[owner]
      levy[owner] += World.Yield(world, id, s.control) * hours
      sov[owner] += World.SovCost(world, faction, id, faction.systems) * hours
      police[owner] += faction.policing * Powers.POLICE * (1 + world.atlas.systems[id].population) * hours
    end
  end

  -- Fleets: crews are paid; supplies are bought where the fleet lies in
  -- its own space, and come out of its holds anywhere else.
  for _, id in World.FleetIds(world) do
    local fleet = world.fleets[id]
    local faction = factions[fleet.owner]
    if faction.pirate then
      -- Pirates live off the land, and pay their crews while they can.
      fleet.supply = Orders.SupplyRoom(fleet)
      World.Pay(world, faction.id, 0, math.min(math.max(0, faction.credits), World.FullStrength(fleet) * Powers.PAY * hours),
        "crews")
      continue
    end
    crews[fleet.owner] += World.FullStrength(fleet) * Powers.PAY * hours
    local need = World.SupplyRate(fleet) * hours
    local at = fleet.system
    if at > 0 and world.systems[at].owner == fleet.owner then
      local fuel = Orders.Buy(world, faction, at, FUEL, need * Powers.SUPPLY_FUEL, "supply")
      local got = fuel / Powers.SUPPLY_FUEL
      local ammunition = Orders.Buy(world, faction, at, AMMUNITION, got * Powers.SUPPLY_AMMUNITION, "supply")
      need -= math.min(got, ammunition / Powers.SUPPLY_AMMUNITION)
    end
    fleet.supply = math.max(0, fleet.supply - need)
  end

  for id, faction in factions do
    if faction.alive and not faction.pirate then
      local laidUp = 0
      for class, count in faction.reserve do
        laidUp += count * Powers.ships[class].strength
      end
      crews[id] += laidUp * Powers.PAY_RESERVE * hours
      local supplies = before[id] - faction.credits
      World.Pay(world, 0, id, levy[id], "levy")
      World.Pay(world, id, 0, sov[id], "sovereignty")
      World.Pay(world, id, 0, police[id], "policing")
      World.Pay(world, id, 0, crews[id], "crews")

      local spent = (sov[id] + police[id] + crews[id] + supplies) / hours
      local earned = levy[id] / hours
      if faction.periods == 0 then
        faction.income, faction.costs = earned, spent
      else
        faction.income += SMOOTHING * (earned - faction.income)
        faction.costs += SMOOTHING * (spent - faction.costs)
      end
      faction.periods += 1
      if faction.credits < 0 then
        faction.arrears += 1
        faction.periodsInArrears += 1
      else
        faction.arrears = 0
      end
      if faction.arrears > Powers.ARREARS_GRACE then
        local lost, least = 0, math.huge
        for system, s in world.systems do
          if s.owner == id and system ~= faction.capital and s.control < least then
            lost, least = system, s.control
          end
        end
        if lost > 0 then
          World.Transfer(world, lost, 0)
          World.Count(world, "systems lost to arrears")
          World.Log(world, "lapse", `{faction.name} loses its hold on {World.SystemName(world, lost)}: its bills are unpaid`,
            lost, id)
        end
      end
    end
  end
end

return Fiscal
