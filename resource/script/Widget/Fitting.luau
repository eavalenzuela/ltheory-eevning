--!strict
-- The fitting window (Luau port of Widget/Fitting.lts): remove weapons and
-- transfer units from the ship into your hangar at this station, or fit
-- them from the hangar.

local Button = require("@lt/Widget/Button")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Widgets = require("@lt/Widgets")
local Window = require("@lt/Widget/Window")

local Fitting = {}

type Fit = { type: "Fit", item: Item }
type Unplug = { type: "Unplug", module: Object }

local function isFittable(item: Item): boolean
  return item:IsWeaponType() or item:IsTransferUnitType()
end

-- The weapon or transfer unit a turret socket holds, if any
local function payload(module: Object): Object?
  local held: Object? = nil
  local children = module:GetChildren()
  while children:HasMore() do
    local child = children:Get()
    if child:IsWeapon() or child:IsTransferUnit() then
      held = child
    end
    children:Advance()
  end
  return held
end

local function row(label: string, button: Widget?): Widget
  local white = vector.create(1, 1, 1)
  return Components.Expand(Components.Padding(vector.create(8, 4), 4, Widgets.ListH(16,
    Components.MinSize(vector.create(280, 0), Components.AlignLeftCenter(Widgets.Text(Fonts.Default(), label, 15, white))),
    Components.MinSize(vector.create(96, 0), button or Widget_Create()))))
end

local function fittingList(player: Player, station: Object): Widget
  local dim = vector.create(0.5, 0.5, 0.5)
  return Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      local rows = {}
      local ship = player:GetPiloting()
      local locker = station:GetStorageLocker(player)

      table.insert(rows, Components.AlignLeftCenter(
        Widgets.Text(Fonts.Subheading(), `INSTALLED ON {string.upper(ship:GetName())}`, 15, dim)))
      local installed = 0
      local sockets = ship:GetSockets()
      while sockets:HasMore() do
        local module = sockets:Get()
        local held = module and payload(module)
        if module and held then
          installed += 1
          local unplug: Unplug = { type = "Unplug", module = module }
          -- The item type's name; the object itself is just "Weapon"
          table.insert(rows, row(held:GetSupertype():GetName(), Button.Create(unplug, "REMOVE", 14)))
        end
        sockets:Advance()
      end
      if installed == 0 then
        table.insert(rows, row("(nothing removable installed)"))
      end

      table.insert(rows, Components.AlignLeftCenter(
        Widgets.Text(Fonts.Subheading(), `IN YOUR HANGAR AT {string.upper(station:GetName())}`, 15, dim)))
      local available = 0
      local cargo = locker:GetCargo()
      while cargo:HasMore() do
        local item = cargo:GetItem()
        if isFittable(item) then
          available += 1
          local fit: Fit = { type = "Fit", item = item }
          table.insert(rows, row(`{item:GetName()} x{cargo:GetQuantity()}`, Button.Create(fit, "FIT", 14)))
        end
        cargo:Advance()
      end
      if available == 0 then
        table.insert(rows, row("(no weapons or transfer units; buy some at the market)"))
      end
      return rows
    end,
    Receive = function(_, w: Widget, message: any)
      if type(message) ~= "table" then
        return
      end
      local ship = player:GetPiloting()
      local locker = station:GetStorageLocker(player)
      if message.type == "Fit" then
        local item = (message :: Fit).item
        if ship:Plug(item) then
          locker:RemoveItem(item, 1)
          player:AddLog(`Fitted {item:GetName()}`)
          Sound_Play("ui/elementselect.wav", 0.2)
        else
          player:AddLog(`No free slot for {item:GetName()}`)
        end
        w:Rebuild()
      elseif message.type == "Unplug" then
        local item = ship:Unplug((message :: Unplug).module)
        if item then
          locker:AddItem(item, 1)
          player:AddLog(`Removed {item:GetName()} to your hangar`)
          Sound_Play("ui/elementselect.wav", 0.2)
        end
        w:Rebuild()
      end
    end,
  })
end

function Fitting.Create(player: Player, station: Object): Widget
  return Window.Create("Fitting", Components.Padding(16, 16, Widget_ListVertical(4, fittingList(player, station))))
end

return Fitting
