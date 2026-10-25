--!strict
-- Renders one line of text at several sizes into test.bmp and exits, for
-- checking font rendering (Luau port of App/font.lts).

return {
  Initialize = function()
    local texture = Texture2D_Create(1024, 640)
    texture:BeginDrawTo()
    DrawClear(vector.create(0, 0, 0), 1)
    local panel = vector.create(0.1, 0.2, 0.3)
    WidgetRenderer_DrawPanel(0, 1024, panel, 1, 1, 0)
    WidgetRenderer_DrawPanel(0, 256, panel, 1, 1, 0)
    local font = Font_Get("Play/Regular.ttf")
    local text = "LAPWYVTykvAV"
    for i, size in { 8, 2, 1, 0.75, 0.5, 0.25 } do
      local y = ({ 200, 250, 300, 325, 350, 375 })[i]
      WidgetRenderer_DrawText(font, text, vector.create(64, y), size, 1, 1, false)
    end
    texture:EndDrawTo()
    texture:SaveTo("test.bmp")
  end,
}
