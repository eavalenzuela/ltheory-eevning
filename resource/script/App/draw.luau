--!strict
-- Line drawing toy (Luau port of App/draw.lts): drag with the left button
-- to draw a line; hold the right button to grow lines off the existing
-- ones, pushed away from the others.

local AppShell = require("@lt/AppShell")
local Colors = require("@lt/Colors")
local Fonts = require("@lt/Fonts")
local Icons = require("@lt/Icons")

type Line = { p1: vector, p2: vector }

local K_A = 3.0
local K_B = 200.0

return AppShell.Create(function(): Widget
  local lines: { Line } = {}
  local downPos = vector.create(0, 0)
  local down = false
  local dot = Glyph_Circle(0, 1, 1, 1)

  return Widget_Layer(Compositor_Basic(0.1, 0.2, vector.create(0.45, 0.00, 0.9)), Mesh_Quad(), 1,
    Widget_Luau(Widget_Create(), {
      PreDraw = function(_, w: Widget)
        WidgetRenderer_DrawPanel(w.pos, w.size, 0.05, 1, 1, 0)
      end,
      PostDraw = function(_, w: Widget)
        local m = Cursor_Get()
        local c = 4 * Colors.Primary
        Icon_Draw(Icons.Cursors.Cross(), m, 12, c, 0.5)
        WidgetRenderer_DrawText(Fonts.Heading(), "Draw", vector.create(w.size.x / 2, w.size.y - 72), 92, 0.1, 1, true)
        if down then
          Glyph_Draw(Glyph_Line(downPos, m, 1, 1), 0, 1, c, 1)
        end
        for _, line in lines do
          Glyph_Draw(dot, line.p1, 10, c, 1)
          Glyph_Draw(dot, line.p2, 10, c, 1)
          Glyph_Draw(Glyph_Line(line.p1, line.p2, 1, 1), 0, 1, c, 0.1)
        end
      end,
      PostUpdate = function()
        if Mouse_LeftPressed() then
          downPos = Cursor_Get()
          down = true
        end
        if Mouse_LeftReleased() then
          table.insert(lines, { p1 = downPos, p2 = Cursor_Get() })
          down = false
        end

        -- Right-drag grows new lines off existing ones, so it needs at least one
        if Mouse_RightDown() and #lines > 0 then
          local rng = RNG_MTG(Int_Random())
          local index = rng:Int(#lines) + 1
          local p1 = if rng:Float() < 0.5 then lines[index].p1 else lines[index].p2
          local p2 = 2 * rng:Exp() ^ 2.5 * vector.normalize(rng:Vec2(-1, 1)) + p1
          for _ = 1, 5 do
            for j, line in lines do
              if j ~= index then
                local p1to = line.p1 - p2
                local p2to = line.p2 - p2
                p2 += K_B * p1to / (vector.magnitude(p1to) ^ K_A + 1)
                p2 += K_B * p2to / (vector.magnitude(p2to) ^ K_A + 1)
              end
            end
          end
          table.insert(lines, { p1 = p1, p2 = p2 })
        end
      end,
    }))
end)
