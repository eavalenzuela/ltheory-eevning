--!strict
-- Scripted check of the core gameplay loop, run with `bin/launch test_gameplay`:
-- mine a rock, dock (Task_Dock), move ore to the station locker, sell it into
-- the station's ore bids, buy a weapon, fit and unplug it, undock, and dock a
-- spare ship with the Dock binding. Prints each step; no input needed.

local App = {}

local camera: Camera
local ui: Interface
local system: Object
local station: Object
local rock: Object
local ship: Object
local player: Player
local frame = 0
local phase = 0
local dockTime = 0

local function findSystem(universe: Object): Object
  local found = universe
  while not found:IsSystem() do
    found = found:GetInteriorObjects():Get()
  end
  return found
end

local function cargoCount(): number
  local n = 0
  local it = ship:GetCargo()
  while it:HasMore() do
    n += it:GetQuantity()
    it:Advance()
  end
  return n
end

local function fireMiners()
  local sockets = ship:GetSockets()
  while sockets:HasMore() do
    local module = sockets:Get()
    if module then
      local mining = false
      local children = module:GetChildren()
      while children:HasMore() do
        if children:Get():IsTransferUnit() then
          mining = true
        end
        children:Advance()
      end
      if mining then
        module:Broadcast(New.MessageFire())
        local aim = New.MessageTargetPosition()
        aim.position = rock:GetCenter()
        module:Broadcast(aim)
      end
    end
    sockets:Advance()
  end
end

function App:Initialize()
  camera = Camera_Create()
  camera:Push()
  system = findSystem(Object_Universe(39, 0))

  local foundStation: Object? = nil
  local foundRock: Object? = nil
  local it = system:GetInteriorObjects()
  while it:HasMore() do
    local o = it:Get()
    if o:HasComponentDockable() and o:HasComponentMarket() and not foundStation then
      foundStation = o
    end
    if o:HasComponentMineable() and not foundRock then
      foundRock = o
    end
    it:Advance()
  end
  station = assert(foundStation, "no station with a market")
  rock = assert(foundRock, "no mineable rock")
  print(`station: {station:GetName()}  rock radius: {rock:GetRadius()} pos-center: {vector.magnitude(rock:GetPos() - rock:GetCenter())}`)

  ship = Item_ShipType(20000, 55, 1, 1, 1, 1, 1, 1):Instantiate()
  ship:Plug(Item_TransferUnitType(1, 1, 1, 1, 1, 1))
  ship:SetPos(rock:GetPos() + (rock:GetRadius() + ship:GetRadius() + 20) * vector.create(1, 0, 0))
  system:AddInterior(ship)
  player = Player_Human()
  player:AddCredits(10000)
  player:AddAsset(ship)
  player:Pilot(ship)
  camera:SetTarget(ship)
  print(`ship capacity: {ship:GetCapacity()}`)

  local passes = New.Vector_Reference_RenderPassT()
  passes:Append(RenderPass_Clear(0))
  passes:Append(RenderPass_Camera(camera))
  ui = Interface_Create("UI")
  ui:Add(Widget_Rendered(passes))
end

local function sellAndBuy()
  local locker = station:GetStorageLocker(player)
  print(`credits before selling: {player:GetCredits()}`)

  -- Collect first: selling escrows items out of the locker mid-iteration
  local ores: { Item } = {}
  local cargo = locker:GetCargo()
  while cargo:HasMore() do
    table.insert(ores, cargo:GetItem())
    cargo:Advance()
  end

  for _, ore in ores do
    local count = locker:GetItemCount(ore)
    local bids = station:GetMarketData(ore).bids
    local best = 0
    for i = 0, bids:Size() - 1 do
      best = math.max(best, bids:Get(i).price)
    end
    print(`  {ore:GetName()} x{count} best bid {best} ({bids:Size()} bids)`)
    if best > 0 then
      station:AddMarketSellOrder(player, ore, count, best)
    end
  end
  print(`credits after placing sell orders: {player:GetCredits()}`)

  -- Buy the cheapest weapon on sale
  local cheapest: Item? = nil
  local cheapestPrice = 1000000000
  local shown = 0
  local listings = station:GetMarketListings()
  while listings:HasMore() do
    local listing = listings:Get()
    if listing.item:IsWeaponType() then
      local asks = listing.asks
      for i = 0, asks:Size() - 1 do
        local price = asks:Get(i).price
        if price < cheapestPrice then
          cheapestPrice = price
          cheapest = listing.item
        end
      end
      if shown < 6 then
        print(`  weapon {listing.item:GetName()} value {listing.item:GetValue()}`)
        shown += 1
      end
    end
    listings:Advance()
  end

  local weapon = assert(cheapest, "no weapon for sale")
  print(`cheapest weapon {weapon:GetName()} at {cheapestPrice} (item value {weapon:GetValue()})`)
  station:AddMarketBuyOrder(player, weapon, 1, cheapestPrice)
  print(`bought: locker has {locker:GetItemCount(weapon)}; credits {player:GetCredits()}`)

  -- Fit it, then remove it again
  print(`plug returned {ship:Plug(weapon)}`)
  local fitted: Object? = nil
  local sockets = ship:GetSockets()
  while sockets:HasMore() do
    local module = sockets:Get()
    if module then
      local children = module:GetChildren()
      while children:HasMore() do
        if children:Get():IsWeapon() then
          fitted = module
        end
        children:Advance()
      end
    end
    sockets:Advance()
  end
  local removed = ship:Unplug(fitted)
  print(`unplugged item: {removed:GetName()} same as bought: {removed == weapon}`)

  print(`UNDOCK returned {ship:Undock()} container is system: {ship:GetContainer() == system}`)
  local spare = Item_ShipType(20000, 7, 1, 1, 1, 1, 1, 1):Instantiate()
  system:AddInterior(spare)
  print(`DOCK binding returned {station:Dock(spare)} spare inside station: {spare:GetContainer() == station}`)
end

function App:Update()
  local dt = 0.05
  frame += 1

  if phase == 0 then
    if frame % 20 == 0 then
      local rng = RNG_MTG(frame)
      ship:SetPos(rock:GetCenter() + (rock:GetRadius() + ship:GetRadius() + 10) * rng:Direction())
    end
    fireMiners()
    if frame % 40 == 0 then
      print(`mining: frame {frame} cargo items {cargoCount()}`)
    end
    if frame >= 600 then
      print(`MINED {cargoCount()} items`)
      ship:PushTask(Task_Dock(station))
      phase = 1
    end
  elseif phase == 1 then
    dockTime += dt
    if ship:GetContainer() == station then
      print(`DOCKED after {dockTime} s`)
      local moved = ship:TransferCargo(station:GetStorageLocker(player))
      print(`TRANSFERRED {moved} items; ship cargo now {cargoCount()}`)
      phase = 2
    elseif dockTime > 300 then
      print("DOCK TIMEOUT")
      phase = 2
    end
  elseif phase == 2 then
    sellAndBuy()
    dockTime = 0
    phase = 3
  elseif phase == 3 then
    dockTime += dt
    if dockTime > 3 then
      print(`credits after market updates: {player:GetCredits()}`)
      phase = 4
    end
  end

  system:Update(dt)
  ui:Update()
  ui:Draw()
end

return App
