--!strict
-- The game (Luau port of App/ltheory.lts): fly, mine, dock, trade, refit,
-- fend off pirates. Run with `bin/launch ltheory`.
--
-- Right-click an asteroid and choose Mine (the ship approaches and mines
-- it); right-click a station to Dock or Trade. Ctrl+Tab toggles the
-- developer panel; hold H to run the simulation 20x faster.

local HUD = require("@lt/Widget/HUD")

local UNIVERSE_SEED = 39
local MINING_REACH = 4000
local PIRATE_INTERVAL = 120
local MAX_PIRATES = 2
-- Weapon value is 10x its DPS; the starter ship has 120 health
local MAX_PIRATE_WEAPON_VALUE = 100

local DevPanelCreate = ltsl("Widget/DevPanel:Create")

-- The starter ship: weapons plus a transfer unit for mining
local function createStarterShip(): Object
  local ship = Item_ShipType(20000, 55, 1, 1, 1, 1, 1, 1):Instantiate()
  ship:Plug(Item_TransferUnitType(1, 1, 1, 1, 1, 1))
  local weapon = Item_WeaponType(46)
  while ship:Plug(weapon) do end
  return ship
end

local function cargoCount(ship: Object): number
  local n = 0
  local it = ship:GetCargo()
  while it:HasMore() do
    n += it:GetQuantity()
    it:Advance()
  end
  return n
end

local camera: Camera
local system: Object
local homeStation: Object?
local player: Player
local ui: Interface
local root: Widget
local devPanel: Widget? = nil

local miningTarget: Object? = nil
local minedSinceReport = 0
local lastCargo = 0
local reportTimer = 0
local pirateTimer = 0
local pirates: { Object } = {}

---------------------------------------------------------------- Mining

local function startMining(rock: Object)
  local ship = player:GetPiloting()
  if miningTarget == rock then
    miningTarget = nil
    player:AddLog("Stopped mining")
    return
  end
  miningTarget = rock
  lastCargo = cargoCount(ship)
  minedSinceReport = 0
  -- Approach the rock first, like EVE's approach-and-mine
  ship:ClearTasks()
  ship:PushTask(Task_Goto(rock, 0.5 * MINING_REACH))
  player:AddLog(`Mining {rock:GetName()}; yield is best from the right side of the rock`)
end

-- Fire every transfer unit on the ship at the rock
local function fireMiners(ship: Object, rock: Object)
  local sockets = ship:GetSockets()
  while sockets:HasMore() do
    local module = sockets:Get()
    if module then
      local mining = false
      local children = module:GetChildren()
      while children:HasMore() do
        mining = mining or children:Get():IsTransferUnit()
        children:Advance()
      end
      if mining then
        module:Broadcast(MessageFire())
        module:Broadcast(MessageTargetPosition(rock:GetCenter()))
      end
    end
    sockets:Advance()
  end
end

local function updateMining(dt: number)
  local ship = player:GetPiloting()
  local rock = miningTarget
  if not rock then
    return
  end
  if ship:GetContainer() ~= rock:GetContainer() then
    miningTarget = nil
    player:AddLog("Stopped mining")
    return
  end

  local reach = vector.magnitude(rock:GetCenter() - ship:GetPos()) - rock:GetRadius()
  if reach < MINING_REACH then
    fireMiners(ship, rock)
  end

  local cargo = cargoCount(ship)
  minedSinceReport += cargo - lastCargo
  lastCargo = cargo
  reportTimer += dt
  if reportTimer > 5 then
    reportTimer = 0
    if reach >= MINING_REACH then
      player:AddLog(`Too far to mine; move closer to {rock:GetName()}`)
    elseif minedSinceReport > 0 then
      player:AddLog(`Mined {minedSinceReport} ore (cargo {cargo})`)
    else
      player:AddLog("No yield; try another side of the rock")
    end
    minedSinceReport = 0
  end

  if ship:GetUsedCapacity() >= 0.98 * ship:GetCapacity() then
    miningTarget = nil
    player:AddLog("Cargo hold full; dock at a station to sell")
  end
end

--------------------------------------------------------------- Pirates

-- Keep a couple of hostile pirates hunting the player
local function updatePirates(dt: number)
  local ship = player:GetPiloting()
  local alive = {}
  for _, pirate in pirates do
    if pirate:GetHealth() > 0 then
      table.insert(alive, pirate)
    end
  end
  pirates = alive

  pirateTimer += dt
  if pirateTimer <= PIRATE_INTERVAL or #pirates >= MAX_PIRATES or ship:GetContainer() ~= system then
    return
  end
  pirateTimer = 0
  local rng = RNG_MTG(Int_Random())
  -- RNG:Int is signed; ship seeds are unsigned and weapon ids signed, so
  -- use the range both accept
  local function seed(): number
    return rng:Int() % 2147483648
  end
  local pirateType = Item_ShipType(15000, seed(), 1, 1, 1, 1, 1, 1)
  -- Random weapons run up to ~400 DPS, which kills the starter ship in
  -- well under a second; re-roll until it's a light one
  local weapon = Item_WeaponType(seed())
  for _ = 1, 50 do
    if weapon:GetValue() <= MAX_PIRATE_WEAPON_VALUE then
      break
    end
    weapon = Item_WeaponType(seed())
  end
  local pirate = pirateType:Instantiate()
  pirate:Plug(weapon)
  pirate:SetName("Pirate")
  pirate:SetPos(ship:GetPos() + rng:Float(3000, 5000) * rng:Direction())
  pirate:PushTask(Task_Destroy(ship))
  system:AddInterior(pirate)
  table.insert(pirates, pirate)
  player:AddLog("A pirate is closing in!")
  Sound_Play("ui/targetacquired.ogg", 0.3)
end

-- A destroyed ship is replaced by a fresh starter ship at the home station
local function updateRespawn(w: Widget)
  local station = homeStation
  if player:GetPiloting():GetHealth() > 0 or not station then
    return
  end
  local ship = createStarterShip()
  system:AddInterior(ship)
  station:Dock(ship)
  player:AddAsset(ship)
  player:Pilot(ship)
  miningTarget = nil
  lastCargo = 0
  player:AddLog(`Your ship was destroyed. A replacement waits at {station:GetName()}`)
  w:Rebuild()
end

-- Y / U: start / stop using the last target (warp nodes, ...)
local function useTarget(start: boolean)
  local ship = player:GetPiloting()
  local target: Object? = nil
  local it = ship:GetTargets()
  while it:HasMore() do
    target = it:Get()
    it:Advance()
  end
  if target then
    target:Send(if start then MessageStartUsing(ship) else MessageStopUsing(ship))
  end
end

-------------------------------------------------------------------- App

local App = {}

function App:Initialize()
  camera = Camera_Create()
  camera:Push()

  system = Object_Universe(UNIVERSE_SEED, 0)
  while not system:IsSystem() do
    system = system:GetInteriorObjects():Get()
  end

  local objects = system:GetInteriorObjects()
  while objects:HasMore() do
    if objects:Get():HasComponentDockable() then
      homeStation = objects:Get()
    end
    objects:Advance()
  end

  local rng = RNG_MTG(0)
  local ship = createStarterShip()
  local station = homeStation
  ship:SetPos(if station then station:GetPos() + 10000 * rng:Sphere() else 100000 * rng:Sphere())
  system:AddInterior(ship)

  player = Player_Human()
  player:AddCredits(10000)
  player:AddAsset(ship)
  player:Pilot(ship)
  player:SetName("SuperSpaceSquirrel")
  player:AddLog("Right-click an asteroid and choose Mine; right-click a station to Dock or Trade (G hides markers)")
  player:AddLog("Docked, use the station panel to sell ore, buy modules and refit")

  Sound_PlayLooped("system/ambiance/089.wav", 0.05)

  root = Widget_Stack(Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      local passes = New.Vector_Reference_RenderPassT()
      passes:Append(RenderPass_Clear(0))
      passes:Append(RenderPass_Camera(camera))
      passes:Append(RenderPass_SMAA())
      passes:Append(RenderPass_PostFilter("post/dither.jsl"))
      return { Widget_Rendered(passes), HUD.Create(player) }
    end,
    Receive = function(_, _w: Widget, message: any)
      if type(message) == "table" and message.type == "Mine" then
        startMining(message.object)
      end
    end,
    PreUpdate = function(_, w: Widget)
      local ship = player:GetPiloting()
      camera:SetTarget(ship)

      if Key_Pressed(Key_Y()) then
        useTarget(true)
      end
      if Key_Pressed(Key_U()) then
        useTarget(false)
      end

      local dt = math.min(0.1, FrameTimer_Get())
      if Key_Down(Key_H()) then
        dt *= 20
      end

      updateMining(dt)
      updatePirates(dt)
      updateRespawn(w)

      -- While docked, keep simulating the whole system, not just the station
      local container = ship:GetContainer()
      if container:HasComponentDockable() then
        container = container:GetContainer()
      end
      container:Update(dt)
    end,
  }))

  ui = Interface_Create("UI")
  ui:Add(root)
end

function App:Update()
  if Key_Control() and Key_Pressed(Key_Tab()) then
    local panel = devPanel
    if panel then
      panel:Delete()
      devPanel = nil
    else
      local shown = Widget_Layer(Compositor_Basic(0.1, 0.1, vector.create(0.4, 0.5, 0.75)), Mesh_Quad(), 1, DevPanelCreate())
      devPanel = shown
      ui:Add(shown)
    end
  end
  ui:Update()
  ui:Draw()
end

return App
