--!strict
-- Object info demo (Luau port of App/objectinfo.lts): a player with a fleet
-- of assets across three systems, a cargo hold and a station market, shown
-- in the info browser. Run with `bin/launch objectinfo`.

local Browser = require("@lt/Widget/Browser")
local Components = require("@lt/Widget/Components")
local Desktop = require("@lt/Widget/Desktop")
local ObjectInfo = require("@lt/Widget/ObjectInfo")

local App = {}
local station: Object
local ui: Interface

local function seed(rng: RNG): number
  return rng:Int() % 2147483648
end

function App:Initialize()
  local rng = RNG_MTG(42)
  local player = Player_Human()
  player:AddCredits(100000)
  player:SetName("V'ewy Tyred")
  local trader = Player_Human()
  trader:AddCredits(100000)

  local stationType = Item_StationType(1000000, 12, 1, 1, 1, 1)
  station = stationType:Instantiate()
  station:SetName("Konryz Mining Outpost LZ-882")

  for _ = 1, 9 do
    rng:Int()
  end
  local systems: { Object } = {}
  for _ = 1, 3 do
    local s = Object_System(vector.create(rng:Float(), rng:Float(), rng:Float()), seed(rng))
    s:SetName(String_CapitalCase(Grammar_Get("$system", rng)))
    table.insert(systems, s)
  end

  local ship = Item_ShipType(1000000, 9094, 1, 1, 1, 1, 1, 1):Instantiate()
  ship:SetName("Blue Dragon")
  local weapon = Item_WeaponType(42)
  for _ = 1, 4 do
    ship:Plug(weapon)
  end
  systems[1]:AddInterior(ship)
  player:AddAsset(ship)
  player:Pilot(ship)

  -- A fleet scattered over the systems, some of it damaged
  local fighter = Item_ShipType(100000, 315, 1, 1, 1, 1, 1, 1)
  local hauler = Item_ShipType(1000000, 515, 1, 1, 1, 1, 1, 1)
  local battleship = Item_ShipType(10000000, 415, 1, 1, 1, 1, 1, 1)
  local assets: { Object } = {}
  for i = 0, 31 do
    local choice = rng:Float()
    local object
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
    if rng:Float() < 0.3 then
      object:SetHealth(math.max(0, math.floor(object:GetHealth() - 5000 * rng:Exp())))
    end
    object:SetPos(10000 * rng:Sphere())
    systems[rng:Int(0, #systems - 1) + 1]:AddInterior(object)
    player:AddAsset(object)
    table.insert(assets, object)
  end

  local items: { Item } = {}
  for _ = 1, 32 do
    table.insert(items, Item_WeaponType(seed(rng)))
  end
  for _ = 1, 8 do
    table.insert(items, Item_OreType(10 * rng:Exp(), seed(rng)))
  end
  local function randomItem(): Item
    return items[rng:Int(0, #items - 1) + 1]
  end

  for _, object in assets do
    if rng:Float() < 0.5 and object:HasComponentTasks() then
      object:PushTask(Task_Goto(assets[rng:Int(0, #assets - 1) + 1], 500))
    end
    for _ = 1, 8 do
      object:AddItem(randomItem(), 2)
    end
  end
  for _ = 1, 128 do
    local item = randomItem()
    ship:AddItem(item, 1)
    station:AddItem(item, 1)
  end

  local storage = station:GetStorageLocker(trader)
  for _ = 1, 256 do
    local item = randomItem()
    local volume = rng:Int(1, 100)
    local price = item:GetValue() + math.floor(1000 * rng:Exp())
    if rng:Float() < 0.1 then
      storage:AddItem(item, volume)
      station:AddMarketSellOrder(trader, item, volume, price)
    else
      station:AddMarketBuyOrder(trader, item, volume, price)
    end
  end

  local desktop = Desktop.Create(Components.Margin(vector.create(128, 64), vector.create(128, 64), Components.Expand(
    Browser.Create(ObjectInfo.Create(player, player:GetPiloting())))),
    { backdrop = vector.create(0.005, 0.005, 0.005), textureAlpha = 0.2, cursorSize = 8 })
  ui = Interface_Create("UI")
  ui:Add(Desktop.Layer(desktop))
end

function App:Update()
  station:Update(FrameTimer_Get())
  ui:Update()
  ui:Draw()
end

return App
