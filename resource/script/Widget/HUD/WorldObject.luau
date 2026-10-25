--!strict
-- A marker over an object in the world, with a radial menu on right-click
-- (Luau port of Widget/HUD/WorldObject.lts). Hold the right button on the
-- marker, move onto an action, release.

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Icons = require("@lt/Icons")
local Messages = require("@lt/Widget/Messages")
local RadialList = require("@lt/Widget/RadialList")
local Widgets = require("@lt/Widgets")

local WorldObject = {}

-- Sent up to the app, which owns the mining state
export type Mine = { type: "Mine", object: Object }

type Action = { type: "WorldAction", action: string }

local Market = require("@lt/Widget/Object/Market")
local Firework = require("@lt/Object/Firework")

local function option(menu: Widget, name: string, icon: Icon, message: any): Widget
  local button = Widget_Luau(Widget_Create(), {
    CreateChildren = function(_, w: Widget): { Widget }
      local c = if w.focusMouse then vector.create(-1, -1, -1) else 2 * Colors.Primary
      return { Components.MinSize(36, Widgets.Icon(icon, c)) }
    end,
  })
  return Components.Named(name, Components.AlignCenter(Components.FocusRebuild(Components.Tooltip(
    Components.ClickableRightRelease(message, menu, Widget_Stack(button))))))
end

local function menu(player: Player, object: Object): Widget
  local function action(name: string): Action
    return { type = "WorldAction", action = name }
  end
  local menuWidget = Widget_Create()
  Widget_Luau(menuWidget, {
    CreateChildren = function(_, w: Widget): { Widget }
      local options = {}
      if object:GetOwner() then
        table.insert(options, option(w, "Communications", Icons.Comm(), action("comm")))
        table.insert(options, option(w, "Owner", Icons.Person(), action("owner")))
      end
      if object:HasComponentMarket() then
        table.insert(options, option(w, "Trade", Icons.Trade(), action("trade")))
      end
      if object:HasComponentDockable() then
        table.insert(options, option(w, "Dock", Icons.Station(), action("dock")))
      end
      if object:HasComponentMineable() then
        local mine: Mine = { type = "Mine", object = object }
        table.insert(options, option(w, "Mine", Icons.Cargo(), mine))
      end
      table.insert(options, option(w, "[DEV] Jump To", Icons.JumpTo(), action("jump")))
      table.insert(options, option(w, "[DEV] Fireworks!", Icons.Assets(), action("fireworks")))
      table.insert(options, option(w, "Information", Icons.QuestionMark(), action("info")))
      table.insert(options, option(w, "Target", Icons.Target(), action("target")))
      return options
    end,
    Receive = function(_, w: Widget, message: any)
      if type(message) ~= "table" then
        return
      end
      if message.type == "Mine" then
        w:SendUp(message)
        return
      end
      if message.type ~= "WorldAction" then
        return
      end
      local ship = player:GetPiloting()
      local act = (message :: Action).action
      if act == "dock" then
        ship:ClearTasks()
        ship:PushTask(Task_Dock(object))
        player:AddLog(`Docking at {object:GetName()}`)
        Sound_Play("ui/targetacquired.ogg", 0.2)
      elseif act == "fireworks" then
        Firework.ShootFrom(object)
      elseif act == "jump" then
        ship:SetPos(object:GetPos() - (1.5 * object:GetRadius() + 1000) * ship:GetLook())
      elseif act == "target" then
        if ship:HasTarget(object) then
          ship:RemoveTarget(object)
          Sound_Play("ui/targetlost.ogg", 0.2)
        else
          ship:AddTarget(object)
          Sound_Play("ui/targetacquired.ogg", 0.2)
        end
      elseif act == "trade" then
        w:SendUp(Messages.AddWidget(Market.Create(player, object)))
      end
      -- "comm", "owner" and "info" did nothing in LTSL either
    end,
  })
  return RadialList.Create(96, menuWidget)
end

-- The marker itself: the object's icon, colored by relation, with range
-- shown when targeted; T toggles targeting while hovered
local function marker(player: Player, object: Object): Widget
  local ring = Glyph_Arc(0, 1, 0.01, 1, 1, 0, 1)
  return Widget_Luau(Widget_Create(), {
    GetHash = function()
      return object:GetHash()
    end,
    GetName = function()
      return object:GetName()
    end,
    PostDraw = function(_, w: Widget)
      local ship = player:GetPiloting()
      local targeted = ship:HasTarget(object)
      local color = 2 * Colors.Primary
      local alpha = w.alpha
      if object:GetOwner() == player then
        color = 2 * Colors.Friendly
      end
      if object:GetName() == "Pirate" then
        color = 2 * Colors.Hostile
      end
      if w.focusMouse or targeted then
        color = 2 * Colors.Secondary
        alpha = 1
      end
      local center = w.pos + w.size / 2
      Icon_Draw(object:GetIcon(), center, w.size / 2, color, alpha)
      if targeted then
        Glyph_Draw(ring, center, w.size * 0.8, 2 * Colors.Secondary, alpha)
        local km = math.round(object:GetDistance(ship)) / 1000
        WidgetRenderer_DrawText(Fonts.Default(), `{km}km`, center + vector.create(0, 1.2 * w.size.y), 12, 1, 1, true)
      end
      if w.focusMouse and Key_Pressed(Key_T()) then
        if targeted then
          ship:RemoveTarget(object)
          Sound_Play("ui/targetlost.ogg", 0.2)
        else
          ship:AddTarget(object)
          Sound_Play("ui/targetacquired.ogg", 0.2)
        end
      end
    end,
    Receive = function(_, _w: Widget, message: any)
      if Messages.Is(message, "GetObject") then
        message.object = object
      end
    end,
  })
end

function WorldObject.Create(player: Player, object: Object): Widget
  return Components.ContextMenu(menu(player, object),
    Components.Tooltip(Components.CaptureMouse(marker(player, object))))
end

return WorldObject
