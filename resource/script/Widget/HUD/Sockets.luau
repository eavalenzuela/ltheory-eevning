--!strict
-- The ship's hardpoints and fire groups in a honeycomb (Luau port of
-- Widget/HUD/Sockets.lts). Click a socket for its info window; right-click
-- toggles it; click a group to make it active.

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Messages = require("@lt/Widget/Messages")

local Sockets = {}

local ObjectInfo = require("@lt/Widget/ObjectInfo")

type ActivateGroup = { type: "ActivateGroup", index: number }

local ring = Glyph_Arc(0, 1, 0.001, 1, 1, 0, 1)

local function socket(player: Player, object: Object): Widget
  local active = true
  return Widget_Luau(Widget_Create(), {
    GetHash = function()
      return object:GetHash()
    end,
    GetName = function()
      return object:GetName()
    end,
    PreDraw = function(_, w: Widget)
      local color = if active then Colors.Primary else vector.create(0.2, 0.2, 0.2)
      Glyph_Draw(ring, w:Center(), 0.5 * w.size, color, 0.1)
      if w.focusMouse then
        Glyph_Draw(ring, w:Center(), 0.6 * w.size, 2 * Colors.Secondary, 1)
      end
      -- The icon of what the socket holds, if anything
      local icon = object:GetIcon()
      local mounts = object:GetSockets()
      while mounts:HasMore() do
        local mount = mounts:Get()
        if mount then
          icon = mount:GetIcon()
        end
        mounts:Advance()
      end
      Icon_Draw(icon, w:Center(), 0.5 * w.size - vector.create(8, 8), color, 1)
    end,
    PostUpdate = function(_, w: Widget)
      if w.focusMouse and Mouse_LeftPressed() then
        local shown = object
        local mounts = object:GetSockets()
        if mounts:HasMore() then
          shown = mounts:Get()
        end
        w:SendUp(Messages.AddWidget(ObjectInfo.Create(player, shown)))
      end
      if w.focusMouse and Mouse_RightPressed() then
        active = not active
      end
    end,
  })
end

local function group(index: number, initiallyActive: boolean): Widget
  local active = initiallyActive
  local white = vector.create(1, 1, 1)
  return Widget_Luau(Widget_Create(), {
    GetHash = function()
      return index
    end,
    GetName = function()
      return `Group #{index + 1}`
    end,
    PreDraw = function(_, w: Widget)
      Glyph_Draw(ring, w:Center(), 0.5 * w.size, 1, 0.1)
      if w.focusMouse then
        Glyph_Draw(ring, w:Center(), 0.6 * w.size, 2 * Colors.Secondary, 1)
      end
      if active then
        Glyph_Draw(ring, w:Center(), 0.5 * w.size, 2 * Colors.Primary, 1)
      end
      WidgetRenderer_DrawText(Fonts.Default(), `G{index + 1}`, w:Center(), 12, white, 1, true)
    end,
    PostUpdate = function(_, w: Widget)
      if w.focusMouse and Mouse_LeftPressed() then
        local message: ActivateGroup = { type = "ActivateGroup", index = index }
        w:SendUp(message)
      end
    end,
    Receive = function(_, _w: Widget, message: any)
      if type(message) == "table" and message.type == "ActivateGroup" then
        active = (message :: ActivateGroup).index == index
      end
    end,
  })
end

function Sockets.Create(player: Player, object: Object): Widget
  local activeGroup = 0
  return Widget_Dynamic(Widget_Luau(Widget_Create(), {
    GetName = function()
      return "Hardpoints"
    end,
    CreateChildren = function(): { Widget }
      local children = {}
      for i = 0, 3 do
        table.insert(children, Components.Tooltip(Components.CaptureMouse(group(i, i == activeGroup))))
      end
      local it = object:GetSockets()
      while it:HasMore() do
        local s = it:Get()
        if s then
          table.insert(children, Components.Tooltip(Components.CaptureMouse(socket(player, s))))
        end
        it:Advance()
      end
      return children
    end,
    -- Honeycomb: cells sized to fill the area, alternate rows offset
    PostPosition = function(_, w: Widget)
      local children = w:GetChildren()
      local count = math.max(1, children:Size())
      local cell = math.floor(math.sqrt(w.size.x * w.size.y / count) - 2)
      local margin = cell * 0.3
      local x, y = 0, 0
      local parity = false
      while children:HasMore() do
        local child = children:Get()
        child.pos = vector.create(x, y) + w.pos
        child.size = vector.create(cell - margin, cell - margin)
        x += cell
        if x + cell > w.size.x then
          parity = not parity
          x = if parity then 0.5 * cell else 0
          y += 0.5 * cell * math.sqrt(3)
        end
        children:Advance()
      end
    end,
    Receive = function(_, w: Widget, message: any)
      if type(message) == "table" and message.type == "ActivateGroup" then
        activeGroup = (message :: ActivateGroup).index
        w:SendDown(message)
      end
    end,
  }))
end

return Sockets
