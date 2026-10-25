--!strict
-- The in-flight HUD (Luau port of Widget/HUD.lts): flight controls,
-- reticle, panels, world markers and the windows opened over them.
--
-- Keys: F4 hides the HUD, B unlocks panels for layout, G toggles world
-- markers, F3 shows frame statistics, Escape closes the newest window (or
-- opens the game menu).

local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local FrameInfo = require("@lt/Widget/Dev/FrameInfo")
local GameMenu = require("@lt/Widget/GameMenu")
local Handling = require("@lt/Widget/Handling")
local HUDWidget = require("@lt/Widget/HUD/HUDWidget")
local Icons = require("@lt/Icons")
local Messages = require("@lt/Widget/Messages")
local Reticle = require("@lt/Widget/Reticle/Default")

local Container = require("@lt/Widget/HUD/Container")
local Log = require("@lt/Widget/HUD/Log")
local MenuBar = require("@lt/Widget/HUD/MenuBar")
local Minimap = require("@lt/Widget/HUD/Minimap")
local Miniscanner = require("@lt/Widget/HUD/Miniscanner")
local Sockets = require("@lt/Widget/HUD/Sockets")
local Station = require("@lt/Widget/HUD/Station")
local Targets = require("@lt/Widget/HUD/Targets")
local WorldObjects = require("@lt/Widget/HUD/WorldObjects")

local HUD = {}

local function v(x: number, y: number): vector
  return vector.create(x, y)
end

-- The panels around the screen edges
local function panels(player: Player, visible: () -> boolean): Widget
  local locked = false
  return Widget_Stack(Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      local children = {}
      local ship = player:GetPiloting()
      if Camera_Get() then
        table.insert(children, Handling.Create(ship))
      end
      if not visible() then
        return children
      end
      table.insert(children, Components.AlignCenter(HUDWidget.Create(v(512, 386), Reticle.Create(player, ship))))
      table.insert(children, Components.Align(v(0, 1), Components.Margin(v(256, 32), 32,
        HUDWidget.Create(v(385, 96), Sockets.Create(player, ship)))))
      table.insert(children, Components.AlignTopLeft(Components.Margin(32, 32,
        HUDWidget.Create(v(256, 64), Container.Create(player)))))
      table.insert(children, Components.AlignTopRight(Components.Margin(v(32, 196), 32,
        HUDWidget.Create(v(256, 256), Log.Create(player)))))
      table.insert(children, Components.AlignBottomLeft(Components.Margin(32, 32,
        HUDWidget.Create(196, Minimap.Create(player)))))
      table.insert(children, Components.AlignBottomRight(Components.Margin(32, 32,
        HUDWidget.Create(v(256, 64), Miniscanner.Create(player, ship)))))
      table.insert(children, Components.AlignTopRight(Components.Margin(32, 32,
        HUDWidget.Create(v(512, 128), Targets.Create(player, ship)))))
      table.insert(children, Components.FocusFade(1, Components.AlignTopCenter(Components.Padding(8, 8,
        MenuBar.Create(player)))))
      table.insert(children, Components.AlignTopCenter(Components.Margin(v(0, 80), 32, Station.Create(player))))
      return children
    end,
    PreDraw = function(_, w: Widget)
      if visible() and locked then
        WidgetRenderer_DrawPanel(w.pos, w.size, 0.05, 0.7, 1, 0)
        Glyph_Draw(Glyph_Grid(w:TopLeft(), w:BottomRight(), 1, 1, 0, 0.5), 0, 1, Colors.Primary, 0.2)
      end
    end,
    PostDraw = function(_, w: Widget)
      if Key_Down(Key_F3()) then
        FrameInfo.Draw(w)
      end
    end,
    PostUpdate = function()
      if visible() and Key_Pressed(Key_B()) then
        locked = not locked
      end
    end,
  }))
end

function HUD.Create(player: Player): Widget
  local visible = true
  local hudLayer: Widget? = nil
  -- Windows opened through AddWidget, oldest first, for Escape
  local windows: { Widget } = {}

  local root = Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      local children = {}
      local layer = Components.Expand(panels(player, function()
        return visible
      end))
      hudLayer = layer
      if visible and Camera_Get() then
        table.insert(children, Components.Expand(WorldObjects.Create(player)))
      end
      table.insert(children, layer)
      return children
    end,
    Receive = function(_, _w: Widget, message: any)
      local layer = hudLayer
      if not layer then
        return
      end
      if Messages.Is(message, "AddContextMenu") then
        layer:AddChild(message.widget)
      elseif Messages.Is(message, "AddWidget") then
        local window = Components.Expand(Components.AlignCenter(Components.Margin(128, 128, message.widget)))
        layer:AddChild(window)
        table.insert(windows, window)
      end
    end,
    PostDraw = function(_, w: Widget)
      if Key_Pressed(Key_F4()) then
        visible = not visible
        w:Rebuild()
      end
      if visible then
        local cursor = if Key_Down(Key_Space()) then Icons.Cursors.Cross() else Icons.Cursors.Pointer()
        Icon_Draw(cursor, Cursor_Get(), 12, 2 * Colors.Primary, w.alpha)
      end
    end,
    -- Escape closes the most recent window; with none open, the game menu
    PostUpdate = function(_, w: Widget)
      if w.focusKey and Key_Pressed(Key_Escape()) then
        local open = {}
        for _, window in windows do
          if window:HasParent() then
            table.insert(open, window)
          end
        end
        windows = open
        local top = windows[#windows]
        if top then
          top:Delete()
        else
          w:AddChild(GameMenu.Create())
        end
      end
    end,
  })

  return Components.Expand(Widget_Layer(Compositor_Basic(0.05, 0.10, vector.create(0.40, 0.50, 0.75)), Mesh_Quad(), 1,
    Components.Expand(Components.CaptureKey(Widget_Stack(root)))))
end

return HUD
