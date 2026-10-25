--!strict
-- Market demo (Luau port of App/market.lts): a station with a random market
-- of weapons and ores, in its info window. Run with `bin/launch market`.

local Browser = require("@lt/Widget/Browser")
local Components = require("@lt/Widget/Components")
local Desktop = require("@lt/Widget/Desktop")
local FrameInfo = require("@lt/Widget/Dev/FrameInfo")
local ObjectInfo = require("@lt/Widget/ObjectInfo")

local App = {}
local station: Object
local ui: Interface

function App:Initialize()
  local rng = RNG_MTG(42)
  local player = Player_Human()
  player:AddCredits(100000)
  local trader = Player_Human()
  trader:AddCredits(100000)

  station = Item_StationType(1000000, 0, 1, 1, 1, 1):Instantiate()

  local items: { Item } = {}
  for _ = 1, 32 do
    table.insert(items, Item_WeaponType(rng:Int() % 2147483648))
  end
  for _ = 1, 8 do
    table.insert(items, Item_OreType(10 * rng:Exp(), rng:Int() % 2147483648))
  end

  local storage = station:GetStorageLocker(trader)
  for _ = 1, 256 do
    local item = items[rng:Int(0, #items - 1) + 1]
    local volume = rng:Int(1, 100)
    local price = item:GetValue() + math.floor(1000 * rng:Exp())
    if rng:Float() < 0.1 then
      storage:AddItem(item, volume)
      station:AddMarketSellOrder(trader, item, volume, price)
    else
      station:AddMarketBuyOrder(trader, item, volume, price)
    end
  end

  local desktop = Desktop.Create(Components.Margin(64, 64, Components.Expand(
    Browser.Create(ObjectInfo.Create(player, station)))), { cursorSize = 8 })
  Widget_Luau(desktop, {
    PostDraw = function(_, w: Widget)
      FrameInfo.Draw(w)
    end,
  })
  ui = Interface_Create("UI")
  ui:Add(Desktop.Layer(desktop))
end

function App:Update()
  station:Update(FrameTimer_Get())
  ui:Update()
  ui:Draw()
end

return App
