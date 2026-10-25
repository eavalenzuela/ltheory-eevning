--!strict
-- Frame time, frame rate and draw statistics (Luau port of
-- Widget/Dev/FrameInfo.lts), drawn at the top left of 'widget'.

local Fonts = require("@lt/Fonts")

return {
  Draw = function(widget: Widget)
    local frame = FrameTimer_GetEMA01()
    local font = Fonts.Medium()
    WidgetRenderer_DrawText(font, `{math.round(frame * 1000)} ms`, widget.pos + vector.create(12, 16), 12, 1, 1, false)
    WidgetRenderer_DrawText(font, `{math.round(1 / frame)} fps`, widget.pos + vector.create(64, 16), 12, 1, 1, false)
    WidgetRenderer_DrawText(font, `{Renderer_GetPolyCount()} polys // {Renderer_GetDrawCallCount()} calls`,
      widget.pos + vector.create(128, 16), 12, 1, 1, false)
  end,
}
