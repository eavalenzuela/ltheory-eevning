--!strict
-- An object's info window: a ribbon of tabs (Overview, Assets, Cargo,
-- Market, ...) over the selected tab's content (Luau port of
-- Widget/ObjectInfo.lts). Opened from the HUD (player menu, target badges,
-- hardpoints) inside a Browser.

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Icons = require("@lt/Icons")
local Tab = require("@lt/Widget/Tab")
local Widgets = require("@lt/Widgets")

local AssetsTab = require("@lt/Widget/Object/Assets")
local CargoTab = require("@lt/Widget/Object/Cargo")
local DatabaseTab = require("@lt/Widget/Object/Database")
local MarketTab = require("@lt/Widget/Object/Market")
local OverviewTab = require("@lt/Widget/Object/Overview")
local SocketsTab = require("@lt/Widget/Object/Sockets")
local TasksTab = require("@lt/Widget/Object/Tasks")

local ObjectInfo = {}

type State = { activeTab: string }

local ring = Glyph_Arc(0, 1, 0.01, 1, 1, 0, 1)

local function circleIcon(icon: Icon): Widget
  return Widget_Luau(Widget_Create(), {
    PreDraw = function(_, w: Widget)
      local c = 2 * Colors.Primary
      Glyph_Draw(ring, w:Center(), 0.5 * w.size, c, 0.025)
      Glyph_Draw(ring, w:Center(), 0.625 * w.size, c, 0.0125)
      Icon_Draw(icon, w:Center(), 0.4 * w.size, c, 1)
    end,
  })
end

local function ribbon(player: Player, object: Object, state: State): Widget
  return Widget_Luau(Widget_ListHorizontal(24, Widget_Create()), {
    CreateChildren = function(): { Widget }
      local tabs = {}
      local function tab(label: string, icon: Icon, selected: boolean?)
        table.insert(tabs, Components.AlignCenter(Components.MinSize(64,
          Tab.CreateIcon("objectinfo", label, icon, Colors.Primary, Colors.Secondary, true, true, selected == true))))
      end
      tab("Overview", Icons.MagnifyingGlass(), true)
      if object:HasComponentAssets() then tab("Assets", Icons.Assets()) end
      if object:HasComponentCargo() then tab("Cargo", Icons.Cargo()) end
      if object:HasComponentCrew() then tab("Crew", Icons.Assets()) end
      if object:HasComponentAccount() then tab("Account", Icons.Credits()) end
      if object:HasComponentMarket() then tab("Market", Icons.Trade()) end
      if object:HasComponentProjects() then tab("Projects", Icons.Refresh()) end
      if object:IsPlayer() then tab("Messages", Icons.Mail()) end
      if object:GetID() == player:GetID() then tab("Notes", Icons.Log()) end
      if object:HasComponentSockets() then tab("Hardpoints", Icons.Hardpoints()) end
      if object:HasComponentDatabase() then tab("Database", Icons.Database()) end
      if object:HasComponentTasks() then tab("Tasks", Icons.Gear()) end

      table.insert(tabs, Components.GreedyX(Components.Expand(Widget_Create())))
      table.insert(tabs, Components.AlignCenter(Widgets.ListH(8,
        Components.AlignCenter(Widgets.Text(Fonts.Medium(), string.upper(object:GetName()), 24, vector.create(1, 1, 1))),
        Components.AlignCenter(Components.MinSize(64, circleIcon(object:GetIcon()))),
        Components.AlignCenter(Widgets.Text(Fonts.Heading(), string.upper(object:GetType()), 14, Colors.Primary)))))
      return tabs
    end,
    Receive = function(_, w: Widget, message: any)
      if type(message) == "table" and message.type == "TabSelect" then
        w:SendDown(message)
        state.activeTab = message.label
      end
    end,
  })
end

-- The active tab's content, with a background grid (stronger for real
-- content than for placeholders)
local function content(player: Player, object: Object, state: State): Widget
  local current = ""
  local opacity = 0
  return Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      current = state.activeTab
      local widget: Widget
      if current == "Overview" then
        opacity, widget = 1, OverviewTab.Create(player, object)
      elseif current == "Assets" then
        opacity, widget = 1, AssetsTab.Create(player, object)
      elseif current == "Cargo" then
        opacity, widget = 1, CargoTab.Create(player, object)
      elseif current == "Database" then
        opacity, widget = 0.1, DatabaseTab.Create(player, object)
      elseif current == "Market" then
        opacity, widget = 0.4, MarketTab.Create(player, object)
      elseif current == "Hardpoints" then
        opacity, widget = 0.1, SocketsTab.Create(player, object)
      elseif current == "Tasks" then
        opacity, widget = 0.1, TasksTab.Create(player, object)
      else
        widget = Widget_Create()
      end
      return { Components.Padding(8, 8, widget) }
    end,
    PreDraw = function(_, w: Widget)
      Glyph_Draw(Glyph_Grid(w:TopLeft(), w:BottomRight(), Colors.Primary, 1, 0, 0.25), 0, 1, 1, 0.1 * opacity)
      ClipRegion_Push(w.pos, w.size)
    end,
    PostDraw = function()
      ClipRegion_Pop()
    end,
    PreUpdate = function(_, w: Widget)
      if current ~= state.activeTab then
        w:Rebuild()
      end
      ClipRegion_Push(w.pos, w.size)
    end,
    PostUpdate = function()
      ClipRegion_Pop()
    end,
  })
end

local function info(player: Player, object: Object): Widget
  local state: State = { activeTab = "Overview" }
  return Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return {
        Components.Expand(Components.Padding(vector.create(24, 12), vector.create(24, 12), ribbon(player, object, state))),
        Components.GreedyY(Components.Expand(Widget_Stack(content(player, object, state)))),
      }
    end,
    -- Tabs ask for info views of other objects (an asset, an owner)
    Receive = function(_, _w: Widget, message: any)
      if type(message) == "table" and message.type == "CreateObjectInfo" then
        message.widget = Components.Expand(Components.Named(message.object:GetName(),
          Widget_ListVertical(0, info(message.player, message.object))))
      end
    end,
  })
end

function ObjectInfo.Create(player: Player, object: Object | Player): Widget
  local target = object :: Object
  return Components.Backdrop(vector.create(0.075, 0.075, 0.075), 0.95, 1, 0, Components.Expand(
    Components.Named(target:GetName(), Widget_ListVertical(0, info(player, target)))))
end

ObjectInfo.CreateWindow = ObjectInfo.Create

return ObjectInfo
