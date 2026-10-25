--!strict
-- Station services, shown while the player is docked at a station with a
-- market. Luau port of Widget/HUD/Station.lts; the HUD creates it with
-- (Luau_CreateWidget "@lt/Widget/HUD/Station" player). Layout helpers still
-- live in LTSL and are called through ltsl().

local AlignCenter = ltsl("Widget/Components:AlignCenter")
local Expand = ltsl("Widget/Components:Expand")
local GreedyX = ltsl("Widget/Components:GreedyX")
local Padding = ltsl("Widget/Components:Padding")
local ListH4 = ltsl("Widgets:ListH4")
local Text = ltsl("Widgets:Text")
local Button = ltsl("Widget/Button:Create")
local Subheading = ltsl("Fonts:Subheading")
local MarketCreate = ltsl("Widget/Object/Market:Create")
local FittingCreate = ltsl("Widget/Fitting:Create")

local function vec2(x: number, y: number): Vec2
  local v = New.Vec2()
  v.x = x
  v.y = y
  return v
end

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
  table.insert(children,
    AlignCenter(Text(Subheading(), `DOCKED AT {string.upper(station:GetName())}`, 16, white)))

  local function button(action: Action, label: string): Widget
    return Expand(GreedyX(Button(action, label, 14)))
  end
  table.insert(children, Expand(ListH4(8,
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
    local add = ltsl_new("Widget/Messages:MessageAddWidget")
    add.widget = if action == "market"
      then MarketCreate(self.player, station)
      else FittingCreate(self.player, station)
    widget:SendUp(add)
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
  return Padding(vec2(16, 8), vec2(16, 8), Widget_ListVertical(8, panel))
end

return {
  Create = Create,
}
