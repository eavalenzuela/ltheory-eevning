--!strict
-- The real HUD and station windows, starting docked at a station with ore
-- in the hold, for scripted UI checks of trading and fitting with the
-- harness (no flying needed):
--
--   bin/launch test_station --do "wait 8; find DEPOSIT; click; ..."

local HUD = require("@lt/Widget/HUD")

local App = {}

local camera: Camera
local system: Object
local player: Player
local ui: Interface

function App:Initialize()
  camera = Camera_Create()
  camera:Push()

  system = Object_Universe(39, 0)
  while not system:IsSystem() do
    system = system:GetInteriorObjects():Get()
  end

  local station: Object? = nil
  local objects = system:GetInteriorObjects()
  while objects:HasMore() do
    local o = objects:Get()
    if o:HasComponentDockable() and o:HasComponentMarket() then
      station = o
    end
    objects:Advance()
  end
  local home = assert(station, "no station with a market")

  local ship = Item_ShipType(20000, 55, 1, 1, 1, 1, 1, 1):Instantiate()
  ship:Plug(Item_TransferUnitType(1, 1, 1, 1, 1, 1))
  local weapon = Item_WeaponType(46)
  while ship:Plug(weapon) do end
  -- Ten of each ore the system's stations buy
  for i = 0, system:GetResourceCount() - 1 do
    ship:AddItem(system:GetResource(i), 10)
  end
  system:AddInterior(ship)
  home:Dock(ship)

  player = Player_Human()
  player:AddCredits(10000)
  player:AddAsset(ship)
  player:Pilot(ship)
  player:SetName("Tester")
  print(`docked at {home:GetName()} with {ship:GetUsedCapacity()} of {ship:GetCapacity()} cargo`)

  local root = Widget_Stack(Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      local passes = New.Vector_Reference_RenderPassT()
      passes:Append(RenderPass_Clear(0))
      passes:Append(RenderPass_Camera(camera))
      return { Widget_Rendered(passes), HUD.Create(player) }
    end,
    PreUpdate = function()
      camera:SetTarget(player:GetPiloting())
      system:Update(math.min(0.1, FrameTimer_Get()))
    end,
  }))
  ui = Interface_Create("UI")
  ui:Add(root)
end

function App:Update()
  ui:Update()
  ui:Draw()
end

return App
