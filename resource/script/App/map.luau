--!strict
-- Map demo (Luau port of App/map.lts): a generated system on the system map,
-- simulated at 10x speed. Run with `bin/launch map`.

local Components = require("@lt/Widget/Components")
local Desktop = require("@lt/Widget/Desktop")
local FrameInfo = require("@lt/Widget/Dev/FrameInfo")
local Map = require("@lt/Widget/Map")

local InitSystem = ltsl("Object/System:Init")

local App = {}
local system: Object
local ui: Interface

function App:Initialize()
  system = Object_System(vector.create(15.012, 15.012, 15.012), 1340)
  InitSystem(system)

  local player: Player? = nil
  local objects = system:GetInteriorObjects()
  while objects:HasMore() do
    local owner = objects:Get():GetOwner()
    if owner then
      player = owner
    end
    objects:Advance()
  end
  local viewer = assert(player, "the system has no owned objects")

  local content = Components.Margin(64, 64, Components.Expand(Map.Create(viewer, viewer:GetPiloting():GetSystem())))
  local desktop = Desktop.Create(content)
  Widget_Luau(desktop, {
    PostDraw = function(_, w: Widget)
      FrameInfo.Draw(w)
    end,
  })
  ui = Interface_Create("UI")
  ui:Add(Desktop.Layer(desktop, vector.create(0.25, 0.50, 0.75)))
end

function App:Update()
  system:Update(10 * FrameTimer_Get())
  ui:Update()
  ui:Draw()
end

return App
