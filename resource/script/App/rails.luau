--!strict
-- A warp rail between two stations, with 64 ships shuttling along it
-- (Luau port of App/rails.lts). Target a warp node and press Y to ride
-- the rail, U to leave it. T recompiles shaders.

local HUD = require("@lt/Widget/HUD")
local SceneView = require("@lt/SceneView")
local WarpRail = require("@lt/Object/WarpRail")

local NODE_COUNT = 8
local SHIP_COUNT = 64

local App = {}
local system: Object
local player: Player
local camera: Camera
local ui: Interface
local gameView: Interface

-- The last thing the player's ship targeted, if any
local function lastTarget(): Object?
  local target: Object? = nil
  local it = player:GetPiloting():GetTargets()
  while it:HasMore() do
    target = it:Get()
    it:Advance()
  end
  return target
end

function App:Initialize()
  local rng = RNG_MTG(0)
  camera = Camera_Create()
  camera:Push()
  ui = Interface_Create("UI")
  gameView = SceneView.Create(camera, ui)

  system = Object_System(vector.create(15.012, 15.012, 15.012), 1340)

  local ship = Item_ShipType(20000, 55, 1, 1, 1, 1, 1, 1):Instantiate()
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
  Object_Zone(system, 0, vector.create(1000, 1000, 1000), vector.create(100000, 100000, 100000), SDF_Sphere(vector.create(0, 0, 0), 1), 256, 1, 0, 0, 0)

  local stationType = Item_StationType(100000000, 162, 1, 1, 1, 1)
  local pos = vector.create(0, 0, 2000)
  local station1 = stationType:Instantiate()
  station1:SetPos(pos - vector.create(10000, 0, 10000))
  system:AddInterior(station1)

  local previous: Object? = nil
  for _ = 1, NODE_COUNT do
    local node = Object_WarpNode()
    node:SetPos(pos)
    node:SetScale(vector.create(100, 100, 100))
    node:SetLook(vector.create(0, 0, 1))
    system:AddInterior(node)
    if previous then
      system:AddInterior(WarpRail.Create(node, previous))
    end
    previous = node
    pos += vector.create(0, 0, 10000)
  end

  local station2 = stationType:Instantiate()
  station2:SetPos(pos)
  system:AddInterior(station2)
  ship:SetPos(pos - vector.create(0, 0, 10000))

  local types = {
    Item_ShipType(10000, 20, 1, 1, 1, 1, 1, 1),
    Item_ShipType(100000, 20, 1, 1, 1, 1, 1, 1),
    Item_ShipType(1000000, 20, 1, 1, 1, 1, 1, 1),
    Item_ShipType(10000000, 20, 1, 1, 1, 1, 1, 1),
  }
  for _ = 1, SHIP_COUNT do
    local shuttle = types[rng:Int(1, 4)]:Instantiate()
    shuttle:SetPos(10000 * rng:Sphere() * vector.create(1, 1, 0))
    for _ = 1, 8 do
      shuttle:PushTask(Task_Goto(station1, 512))
      shuttle:PushTask(Task_Goto(station2, 512))
    end
    shuttle:PushTask(Task_Wait(rng:Float(0, 10)))
    system:AddInterior(shuttle)
  end

  ui:Add(HUD.Create(player))
end

function App:Update()
  if Key_Pressed(Key_T()) then
    Shader_RecompileAll()
  end
  local ship = player:GetPiloting()
  if Key_Pressed(Key_Y()) then
    local target = lastTarget()
    if target then
      target:Send(MessageStartUsing(ship))
    end
  end
  if Key_Pressed(Key_U()) then
    local target = lastTarget()
    if target then
      target:Send(MessageStopUsing(ship))
    end
  end
  camera:SetTarget(ship)
  system:Update(math.min(FrameTimer_Get(), 0.1))
  ui:Update()
  gameView:Update()
  gameView:Draw()
end

return App
