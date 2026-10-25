--!strict
-- Fills a new star system (Luau port of Object/System.lts): a planet with
-- colonies, an asteroid belt and an orbital rail; two asteroid fields,
-- each with a trading outpost and pirates fighting patrols; rails between
-- the points of interest; and two AI players. The engine calls Init for
-- each system. Random draws are in the same order as the LTSL version, so
-- a seed gives the same system.

local Icons = require("@lt/Icons")
local Int = require("@lt/Int")
local WarpNode = require("@lt/Object/WarpNode")

local PLAYER_CREDITS = 1500000
local SYSTEM_SCALE = 100000
local PLANET_COUNT = 1
local PLAYER_COUNT = 2
local ZONE_COUNT = 2
-- Draws skipped before the zones, so they don't follow the planet's
local ZONE_SEED = 1000

type POI = { pos: vector, radius: number }

local function splat(x: number): vector
  return vector.create(x, x, x)
end

local function randomTraits(rng: RNG): Traits
  local traits = New.Traits()
  traits.Aggressive = Float_Saturate(rng:Exp())
  traits.Creative = Float_Saturate(rng:Exp())
  traits.Explorative = Float_Saturate(rng:Exp())
  traits.Greedy = Float_Saturate(rng:Exp())
  traits.Intellectual = Float_Saturate(rng:Exp())
  traits.Lawless = Float_Saturate(rng:Exp())
  traits.Sociable = Float_Saturate(rng:Exp())
  return traits
end

local function addColonies(system: Object, rng: RNG, planet: Object)
  local kScale = 0.001
  for _ = 1, rng:Int(1, 3) do
    local item = Item_WeaponType(53)
    local traits = randomTraits(rng)
    local colonyType = Item_ColonyType("Colony", Icons.City(), Task_Spawn(item, 1.0), traits)
    local colony = Object_Colony(Int.Unsigned(rng:Int()), colonyType, planet, 100)
    colony:SetName(String_CapitalCase(Grammar_Get("$station_midfix", rng)))

    local governor = Player_AI(New.Traits())
    governor:SetName(colony:GetName() .. " Governor")
    governor:AddAsset(colony)
    governor:AddCredits(1000000)

    local orientation = rng:Direction()
    local transform = Transform_Look(orientation * (1 - kScale), orientation)
    transform.scale = splat(kScale)
    planet:Attach(colony, transform)
  end
end

local function addPlanets(system: Object, rng: RNG, pois: { POI }): vector
  local origin = vector.create(0, 0, 0)
  local planetPos = origin
  for _ = 1, PLANET_COUNT do
    local radius = SYSTEM_SCALE * (1 + 0.1 * rng:Exp())
    local angle = rng:Angle()
    local pos = origin + 0.5 * SYSTEM_SCALE * Vec3_Cylinder(0, angle, 0.001 * rng:Gaussian())
    planetPos = pos

    local planet = Object_Planet(Item_PlanetType(Int.Unsigned(rng:Int() + 8)))
    planet:SetPos(pos)
    planet:SetScale(splat(radius))
    planet:SetName("Melian Prime")
    system:AddInterior(planet)
    table.insert(pois, { pos = pos, radius = 2 * radius })

    addColonies(system, rng, planet)

    local belt = Object_Zone(system, Int.Unsigned(rng:Int()), planet:GetPos(), planet:GetScale(),
      SDF_Scale(SDF_Torus(origin, 2, 0.4), vector.create(1, 0.05, 1)), 0, 1, 0, 0, 0)
    belt:SetName(planet:GetName() .. " Belt")
    system:AddInterior(belt)

    -- An orbital rail in four arcs, with gaps between them
    local center = pos + vector.create(0, -0.02 * radius, 0)
    for quarter = 0, 3 do
      WarpNode.BuildRailRadial(system, center, 2 * radius, 0.25 * quarter, 0.25 * (quarter + 1) - 0.05)
    end
  end
  return planetPos
end

-- A station selling random modules and buying the system's ores
local function addOutpost(system: Object, rng: RNG, zoneIndex: number, pos: vector, scale: number, commonItems: { Item })
  local stationType = Item_StationType(1000000000, Int.Unsigned(rng:Int()), 1, 1, 1, 1)
  local station = stationType:Instantiate()
  station:SetPos(pos + rng:Sphere() * scale)
  station:SetName(String_CapitalCase(Grammar_Get("$station", rng)))
  system:AddInterior(station)

  local manager = Player_AI(New.Traits())
  manager:SetName(station:GetName() .. " Manager")
  manager:AddAsset(station)
  manager:AddCredits(1000000)

  local storage = station:GetStorageLocker(manager)
  for _ = 1, 32 do
    local item = commonItems[rng:Int(0, #commonItems - 1) + 1]
    local volume = rng:Int(1, 8)
    local price = item:GetValue() + math.floor(Int.Float32(1 + Int.Float32(10 * rng:Exp())))
    storage:AddItem(item, volume)
    station:AddMarketSellOrder(manager, item, volume, price)
  end

  -- Standing demand for the system's ores, so mining pays. A separate
  -- RNG keeps the rest of the generated system unchanged.
  local demandRng = RNG_MTG(Int.Signed(system:GetSeed() + zoneIndex + 1))
  for resourceIndex = 0, system:GetResourceCount() - 1 do
    local ore = system:GetResource(resourceIndex)
    local bidVolume = demandRng:Int(200, 1000)
    local bidPrice = math.max(1, math.floor(Int.Float32(ore:GetValue() * demandRng:Float(0.8, 1.1))))
    station:AddMarketBuyOrder(manager, ore, bidVolume, bidPrice)
  end
end

-- Invulnerable patrols, each fighting three invulnerable pirates
local function addPirates(system: Object, rng: RNG, zone: Object, pos: vector, scale: number, patrolShip: Item,
  pirateShip: Item, pirateWeapon: Item)
  for _ = 1, 2 do
    local patrol = patrolShip:Instantiate()
    patrol:SetPos(pos + rng:Sphere() * scale)
    while patrol:Plug(pirateWeapon) do end
    patrol:SetName(zone:GetName() .. " Patrol Unit")
    patrol:SetHealth(1000000000)
    system:AddInterior(patrol)

    for _ = 1, 3 do
      local pirate = pirateShip:Instantiate()
      for _ = 1, 2 do
        pirate:Plug(pirateWeapon)
      end
      pirate:SetPos(patrol:GetPos() + patrol:GetRadius() * rng:Direction())
      pirate:SetName("Pirate")
      pirate:SetHealth(1000000000)
      pirate:PushTask(Task_Destroy(patrol))
      patrol:PushTask(Task_Destroy(pirate))
      system:AddInterior(pirate)
    end
  end
end

local function addPlayers(system: Object, rng: RNG, spawnZones: { Object })
  local shipTypeBoss = Item_ShipType(100000000, Int.Unsigned(rng:Int()), 1, 1, 1, 1, 1, 1)
  local transferUnit = Item_TransferUnitType(1, Int.Unsigned(rng:Int()), 1, 1, 1, 1)
  for _ = 1, PLAYER_COUNT do
    local weapon = Item_WeaponType(rng:Int())
    local spawnZone = spawnZones[rng:Int(0, #spawnZones - 1) + 1]
    local player = Player_AI(New.Traits())
    local ship = shipTypeBoss:Instantiate()
    player:AddAsset(ship)
    player:AddCredits(PLAYER_CREDITS)
    player:Pilot(ship)
    player:PushTask(Task_Play(player))
    ship:SetPos(spawnZone:GetPos() + rng:Sphere() * spawnZone:GetScale())
    for _ = 1, 4 do
      ship:Plug(transferUnit)
    end
    while ship:Plug(weapon) do end
    system:AddInterior(ship)
  end
end

return {
  Init = function(self: Object)
    local rng = RNG_MTG(Int.Signed(self:GetSeed()))
    local pois: { POI } = {}

    self:SetName(String_CapitalCase(Grammar_Get("$system", rng)))
    local planetPos = addPlanets(self, rng, pois)

    local commonItems: { Item } = {}
    for _ = 1, 32 do
      table.insert(commonItems, Item_WeaponType(rng:Int()))
    end
    table.insert(commonItems, Item_DroneBayType(1500, 1, 1, 1))
    table.insert(commonItems, Item_ProductionLabType(10000, 1, 1, 1, 1))
    table.insert(commonItems, Item_TechLabType(50000, 1, 1, 1, 1))
    table.insert(commonItems, Item_TransferUnitType(100, 1, 1, 1, 1, 1))

    local patrolShip = Item_ShipType(10000000, Int.Unsigned(rng:Int()), 1, 1, 1, 1, 1, 1)
    local pirateShip = Item_ShipType(100000, Int.Unsigned(rng:Int()), 1, 1, 1, 1, 1, 1)
    local pirateWeapon = Item_WeaponType(Int.Signed(rng:Int() + 4))

    for _ = 1, ZONE_SEED do
      rng:Int()
    end

    local spawnZones: { Object } = {}
    for zoneIndex = 0, ZONE_COUNT - 1 do
      local angle = 2 * math.pi * (if zoneIndex == 0 then 0.950 else 0.675)
      local distance = rng:Float(3.5, 3.5)
      local pos = planetPos + SYSTEM_SCALE * Vec3_Cylinder(distance, angle, 0.2 + rng:Gaussian(0.5))
      local scale = 0.4 * SYSTEM_SCALE
      local seed = rng:Int()
      local shape = SDF_Sphere(vector.create(0, 0, 0), 1) * rng:Vec3(splat(1), splat(2))
      local zone = Object_Zone(self, Int.Unsigned(seed), pos, splat(scale), shape, 96, 1, 0, 0, 0)

      addOutpost(self, rng, zoneIndex, pos, scale, commonItems)

      zone:SetName(`{self:GetName()} Field #{zoneIndex + 1}`)
      self:AddInterior(zone)
      table.insert(pois, { pos = pos, radius = scale })
      table.insert(spawnZones, zone)

      addPirates(self, rng, zone, pos, scale, patrolShip, pirateShip, pirateWeapon)
    end

    -- Rails from the planet to every other point of interest
    local a = pois[1]
    for i = 2, #pois do
      local b = pois[i]
      local ab = vector.normalize(b.pos - a.pos)
      WarpNode.BuildRail(self, a.pos + a.radius * ab, b.pos - b.radius * ab)
    end

    addPlayers(self, rng, spawnZones)
  end,
}
