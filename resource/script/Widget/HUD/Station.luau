--!strict
-- Station services, shown while the player is docked at a station with a
-- market (Luau port of Widget/HUD/Station.lts): market, fitting, deposit
-- cargo into your hangar, undock.

local Button = require("@lt/Widget/Button")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Messages = require("@lt/Widget/Messages")
local Widgets = require("@lt/Widgets")

local Market = require("@lt/Widget/Object/Market")
local Fitting = require("@lt/Widget/Fitting")

-- What the panel's buttons send up when pressed
type Action = { action: "market" | "fitting" | "deposit" | "undock" }

local StationPanel = {}
StationPanel.__index = StationPanel

type StationPanel = typeof(setmetatable({} :: {
  player: Player,
  station: Object?,
}, StationPanel))

function StationPanel.new(player: Player): StationPanel
  return setmetatable({ player = player, station = nil :: Object? }, StationPanel)
end

-- The station the player is docked at, if it has a market
function StationPanel.DockedAt(self: StationPanel): Object?
  local ship = self.player:GetPiloting()
  if not ship then
    return nil
  end
  local container = ship:GetContainer()
  if container and container:HasComponentDockable() and container:HasComponentMarket() then
    return container
  end
  return nil
end

function StationPanel.CreateChildren(self: StationPanel, widget: Widget): { Widget }
  local children: { Widget } = {}
  self.station = self:DockedAt()
  local station = self.station
  if not station then
    return children
  end

  local white = vector.create(1, 1, 1)
  table.insert(children, Components.AlignCenter(
    Widgets.Text(Fonts.Subheading(), `DOCKED AT {string.upper(station:GetName())}`, 16, white)))

  local function button(action: Action, label: string): Widget
    return Components.Expand(Components.GreedyX(Button.Create(action, label, 14)))
  end
  table.insert(children, Components.Expand(Widgets.ListH(8,
    button({ action = "market" }, "MARKET"),
    button({ action = "fitting" }, "FITTING"),
    button({ action = "deposit" }, "DEPOSIT CARGO"),
    button({ action = "undock" }, "UNDOCK"))))
  return children
end

function StationPanel.PreDraw(self: StationPanel, widget: Widget)
  if self.station then
    WidgetRenderer_DrawPanel(widget.pos, widget.size, 0.05, 0.8, 1, 8)
  end
end

-- Show or hide as the player docks and undocks
function StationPanel.PreUpdate(self: StationPanel, widget: Widget)
  if self:DockedAt() ~= self.station then
    widget:Rebuild()
  end
end

function StationPanel.Receive(self: StationPanel, widget: Widget, message: any)
  if type(message) ~= "table" then
    return
  end
  local station = self.station
  local ship = self.player:GetPiloting()
  if not station or not ship then
    return
  end

  local action = (message :: Action).action
  if action == "market" or action == "fitting" then
    local window = if action == "market"
      then Market.Create(self.player, station)
      else Fitting.Create(self.player, station)
    widget:SendUp(Messages.AddWidget(window))
  elseif action == "deposit" then
    local moved = ship:TransferCargo(station:GetStorageLocker(self.player))
    if moved > 0 then
      self.player:AddLog(`Moved {moved} items to your hangar at {station:GetName()}`)
    else
      self.player:AddLog("Nothing to deposit")
    end
    Sound_Play("ui/elementselect.wav", 0.2)
  elseif action == "undock" then
    ship:Undock()
    self.player:AddLog(`Undocked from {station:GetName()}`)
    widget:Rebuild()
  end
end

local function Create(player: Player): Widget
  local panel = Widget_Luau(Widget_Create(), StationPanel.new(player))
  local inset = vector.create(16, 8)
  return Components.Padding(inset, inset, Widget_ListVertical(8, panel))
end

return {
  Create = Create,
}
