--!strict
-- Flight-handling test bed (Luau port of App/handling.lts): your ship with
-- transfer units, two damaged pirates, and 16 of your assets with cargo for
-- the object info windows. Hold H for 20x speed; P pauses.

local AppShell = require("@lt/AppShell")
local HUD = require("@lt/Widget/HUD")
local Int = require("@lt/Int")
local SceneView = require("@lt/SceneView")

return AppShell.Create(function(): Widget
  local rng = RNG_MTG(0)
  local camera = Camera_Create()
  camera:Push()

  local system = Object_System(vector.create(14.019, 14.019, 14.019), 841)
  local oreType = Item_OreType(10, 13)
  oreType:SetName("Mercoxit")
  system:AddResource(oreType, 1)
  system:SetName("Fermat's Last")

  local shipType = Item_ShipType(1000000, 6, 1, 1, 1, 1, 1, 1)
  local ship = shipType:Instantiate()
  ship:SetPos(vector.create(0, 0, 0))
  for _ = 1, 2 do
    local pirate = shipType:Instantiate()
    pirate:SetPos(1000 * rng:Sphere())
    pirate:SetHealth(rng:Int(pirate:GetMaxHealth()))
    pirate:SetName("Pirate")
    system:AddInterior(pirate)
  end
  local equipment = Item_TransferUnitType(1, 1, 1, 1, 1, 1)
  while ship:Plug(equipment) do end
  system:AddInterior(ship)

  local player = Player_Human()
  player:AddAsset(ship)
  player:Pilot(ship)
  player:AddLog("Buy order for 100 x TETRITE succeeded (-600 cr)")
  player:AddLog("Received new message from Darth Vader")

  -- Assets for the object info demo
  local stationType = Item_StationType(100000000, 18, 1, 1, 1, 1)
  local station = stationType:Instantiate()
  station:SetName("Konryz Mining Outpost LZ-882")

  local fighter = Item_ShipType(100000, 315, 1, 1, 1, 1, 1, 1)
  local hauler = Item_ShipType(1000000, 515, 1, 1, 1, 1, 1, 1)
  local battleship = Item_ShipType(10000000, 415, 1, 1, 1, 1, 1, 1)
  local assets: { Object } = {}
  for i = 0, 15 do
    local choice = rng:Float()
    local object: Object
    if choice < 0.5 then
      object = fighter:Instantiate()
      object:SetName(`Fighter {i}`)
    elseif choice < 0.8 then
      object = hauler:Instantiate()
      object:SetName(`Hauler {i}`)
    elseif choice < 0.9 then
      object = battleship:Instantiate()
      object:SetName(`Battleship {i}`)
    else
      object = stationType:Instantiate()
      object:SetName(String_CapitalCase(Grammar_Get("$station", rng)))
    end
    if rng:Float() < 0.15 then
      object:SetHealth(math.floor(object:GetHealth() * rng:Float()))
    end
    object:SetPos(10000 * rng:Sphere())
    system:AddInterior(object)
    player:AddAsset(object)
    table.insert(assets, object)
  end

  local items: { Item } = {}
  for _ = 1, 32 do
    table.insert(items, Item_WeaponType(rng:Int()))
  end
  for _ = 1, 8 do
    local value = 10 * rng:Exp()
    table.insert(items, Item_OreType(value, Int.Unsigned(rng:Int())))
  end
  local function randomItem(): Item
    return items[rng:Int(#items) + 1]
  end

  for _, asset in assets do
    if rng:Float() < 0.5 and asset:HasComponentTasks() then
      asset:PushTask(Task_Goto(assets[rng:Int(#assets) + 1], 500))
    end
    for _ = 1, 8 do
      asset:AddItem(randomItem(), 2)
    end
  end
  for _ = 1, 128 do
    local item = randomItem()
    ship:AddItem(item, 1)
    station:AddItem(item, 1)
  end

  -- A combat zone. It isn't added to the system, but creating it fills
  -- the system with its asteroids
  Object_Zone(system, 0, vector.create(1000, 1000, 1000), vector.create(100000, 100000, 100000), SDF_Sphere(vector.create(0, 0, 0), 1), 128, 1, 0, 0, 0)

  return Widget_Stack(Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return { SceneView.Rendered(camera), HUD.Create(player) }
    end,
    PreUpdate = function()
      camera:SetTarget(player:GetPiloting())
      local dt = SceneView.TimeStep()
      if not SceneView.Paused() then
        system:Update(dt)
      end
    end,
  }))
end)
