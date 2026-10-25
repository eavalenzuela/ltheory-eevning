--!strict
-- A 32-ship free-for-all around your ship (Luau port of App/war.lts). T
-- recompiles shaders; hold H for 20x speed; P pauses.

local HUD = require("@lt/Widget/HUD")
local SceneView = require("@lt/SceneView")

local SHIP_COUNT = 32

local App = {}
local system: Object
local player: Player
local camera: Camera
local ui: Interface
local gameView: Interface

function App:Initialize()
  local rng = RNG_MTG(0)
  camera = Camera_Create()
  camera:Push()
  ui = Interface_Create("UI")
  gameView = SceneView.Create(camera, ui)

  system = Object_System(vector.create(15.012, 15.012, 15.012), 33)

  local ship = Item_ShipType(10000, 20, 1, 1, 1, 1, 1, 1):Instantiate()
  ship:SetPos(vector.create(0, 0, 0))
  local weaponType = Item_WeaponType(54)
  for _ = 1, 4 do
    ship:Plug(weaponType)
  end
  system:AddInterior(ship)

  player = Player_Human()
  player:AddAsset(ship)
  player:Pilot(ship)

  -- A combat zone. It isn't added to the system, but creating it fills
  -- the system with its asteroids
  Object_Zone(system, 0, vector.create(1000, 1000, 1000), vector.create(10000, 10000, 10000), SDF_Sphere(vector.create(0, 0, 0), 1), 128, 1, 0, 0, 0)

  local types = {
    Item_ShipType(10000, 20, 1, 1, 1, 1, 1, 1),
    Item_ShipType(100000, 20, 1, 1, 1, 1, 1, 1),
    Item_ShipType(1000000, 20, 1, 1, 1, 1, 1, 1),
    Item_ShipType(10000000, 20, 1, 1, 1, 1, 1, 1),
  }
  local ships: { Object } = {}
  for _ = 1, SHIP_COUNT do
    local other = types[rng:Int(1, 4)]:Instantiate()
    other:SetPos(5000 * rng:Direction())
    system:AddInterior(other)
    local otherWeapon = Item_WeaponType(rng:Int())
    for _ = 1, 4 do
      other:Plug(otherWeapon)
    end
    if #ships > 0 then
      other:PushTask(Task_Destroy(ships[rng:Int(#ships) + 1]))
    end
    table.insert(ships, other)
  end

  ui:Add(HUD.Create(player))
end

function App:Update()
  if Key_Pressed(Key_T()) then
    Shader_RecompileAll()
  end
  camera:SetTarget(player:GetPiloting())
  local dt = SceneView.TimeStep()
  if not SceneView.Paused() then
    system:Update(dt)
  end
  ui:Update()
  gameView:Update()
  gameView:Draw()
end

return App
