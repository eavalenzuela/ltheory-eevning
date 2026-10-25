--!strict
-- The app around a single root widget (Luau port of App/widget.lts, which
-- most LTSL demos used through `widget:Create`). It draws the widget every
-- frame; Ctrl+Tab toggles the developer panel and T recompiles shaders.
--
--   return AppShell.Create(function() return myRootWidget end)

local DevPanel = require("@lt/Widget/DevPanel")

local AppShell = {}

-- 'build' runs in Initialize and returns the root widget
function AppShell.Create(build: () -> Widget)
  local ui: Interface
  local devPanel: Widget? = nil
  local app = {}

  function app:Initialize()
    ui = Interface_Create("UI")
    ui:Add(build())
  end

  function app:Update()
    if Key_Control() and Key_Pressed(Key_Tab()) then
      devPanel = DevPanel.Toggle(ui, devPanel)
    end
    if Key_Pressed(Key_T()) then
      Shader_RecompileAll()
    end
    ui:Update()
    ui:Draw()
  end

  return app
end

return AppShell
