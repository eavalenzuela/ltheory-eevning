--!strict
-- A dogfight (Luau port of App/dogfight.lts): your ship and ten hostile
-- fighters near a planet. T recompiles shaders; hold H for 20x speed.

local HUD = require("@lt/Widget/HUD")
local SceneView = require("@lt/SceneView")

local SHIP_COUNT = 10

local App = {}
local system: Object
local ui: Interface
local gameView: Interface

function App:Initialize()
  local rng = RNG_MTG(0)
  local camera = Camera_Create()
  camera:Push()
  ui = Interface_Create("UI")
  gameView = SceneView.Create(camera, ui)

  system = Object_System(vector.create(15.012, 15.012, 15.012), 369369)

  local ship = Item_ShipType(1000000, 55, 1, 1, 1, 1, 1, 1):Instantiate()
  ship:SetPos(vector.create(0, 0, 0))
  local weaponType = Item_WeaponType(74)
  for _ = 1, 4 do
    ship:Plug(weaponType)
  end
  system:AddInterior(ship)

  local planet = Item_PlanetType(155):Instantiate()
  planet:SetScale(vector.create(100000, 100000, 100000))
  planet:SetPos(vector.create(-400000, 0, 0))
  system:AddInterior(planet)

  local player = Player_Human()
  player:AddAsset(ship)
  player:Pilot(ship)

  -- A combat zone. It isn't added to the system, but creating it fills
  -- the system with its asteroids
  Object_Zone(system, 0, vector.create(1000, 1000, 1000), vector.create(100000, 100000, 100000), SDF_Sphere(vector.create(0, 0, 0), 1), 128, 1, 0, 0, 0)

  local enemyType = Item_ShipType(100000, 20, 1, 1, 1, 1, 1, 1)
  for _ = 1, SHIP_COUNT do
    rng:Int(1, 2) -- drawn but unused, as in LTSL
    local enemy = enemyType:Instantiate()
    enemy:SetPos(5000 * rng:Direction())
    system:AddInterior(enemy)
    local enemyWeapon = Item_WeaponType(rng:Int())
    for _ = 1, 4 do
      enemy:Plug(enemyWeapon)
    end
    enemy:PushTask(Task_Destroy(ship))
  end

  ui:Add(HUD.Create(player))
end

function App:Update()
  if Key_Pressed(Key_T()) then
    Shader_RecompileAll()
  end
  system:Update(SceneView.TimeStep())
  ui:Update()
  gameView:Update()
  gameView:Draw()
end

return App
