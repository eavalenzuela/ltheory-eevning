--!strict
-- The plate mesh model editor over a screenshot (Luau port of
-- App/platemesh.lts). Tab toggles the 3D preview.

local AppShell = require("@lt/AppShell")
local Components = require("@lt/Widget/Components")
local Desktop = require("@lt/Widget/Desktop")
local ModelEditor = require("@lt/Widget/ModelEditor")

return AppShell.Create(function(): Widget
  local desktop = Desktop.Create(Components.Expand(Components.Margin(0, 0, ModelEditor.Create())),
    { backdrop = vector.create(0.1, 0.1, 0.1), cursorSize = 12 })
  return Widget_Layer(Compositor_Basic(0, 0, vector.create(0.40, 0.50, 0.75)), Mesh_Quad(), 1, desktop)
end)
