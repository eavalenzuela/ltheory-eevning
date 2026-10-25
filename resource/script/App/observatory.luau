--!strict
-- A 32-ship battle near a mining outpost, watched through the observatory
-- camera (Luau port of App/observatory.lts). Scroll to zoom, right-drag to
-- orbit, click a marker to follow that object. Hold H for 20x speed; P
-- pauses.

local AppShell = require("@lt/AppShell")
local Observatory = require("@lt/Widget/Observatory")
local SceneView = require("@lt/SceneView")

return AppShell.Create(function(): Widget
  local rng = RNG_MTG(0)
  local camera = Camera_Create()
  camera:Push()

  local system = Object_System(vector.create(15.012, 15.012, 15.012), 1200)
  local oreType = Item_OreType(10, 13)
  oreType:SetName("Mercoxit")
  system:AddResource(oreType, 1)

  local zone = Object_Zone(system, 0, vector.create(1000, 1000, 1000), vector.create(10000, 10000, 10000),
    SDF_Sphere(vector.create(0, 0, 0), 1), 1024, 1, 0, 0, 0)
  system:AddInterior(zone)

  local station = Item_StationType(10000000, 12, 1, 1, 1, 1):Instantiate()
  station:SetName("Konryz Mining Outpost LZ-882")
  station:SetPos(1000 * rng:Sphere())
  system:AddInterior(station)

  -- The battle: everyone attacks someone at random
  local type1 = Item_ShipType(100000, 512, 1, 1, 1, 1, 1, 1)
  local type2 = Item_ShipType(1000000, 101, 1, 1, 1, 1, 1, 1)
  local type3 = Item_ShipType(10000000, 181, 1, 1, 1, 1, 1, 1)
  local ships: { Object } = {}
  for _ = 1, 32 do
    -- Coin flips down the list; LTSL flips a third time, though both
    -- outcomes give type3
    local shipType = type3
    if rng:Float() < 0.5 then
      shipType = type1
    else
      local second = rng:Float()
      if second < 0.5 then
        shipType = type2
      else
        rng:Float()
      end
    end
    local ship = shipType:Instantiate()
    ship:SetPos(10000 * rng:Sphere())
    system:AddInterior(ship)
    local weaponType = Item_WeaponType(rng:Int())
    for _ = 1, 4 do
      ship:Plug(weaponType)
    end
    table.insert(ships, ship)
  end
  for _, ship in ships do
    ship:PushTask(Task_Destroy(ships[rng:Int(#ships) + 1]))
  end

  camera:SetTarget(station)

  return Widget_Stack(Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return { Observatory.Create(camera) }
    end,
    PreUpdate = function()
      local dt = SceneView.TimeStep()
      if not SceneView.Paused() then
        system:Update(dt)
      end
    end,
  }))
end)
