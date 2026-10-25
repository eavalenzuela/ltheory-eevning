--!strict
-- An animated loading screen (Luau port of App/loading.lts): a ring of
-- springs that random pulses ripple around, brighter near the cursor.

local AppShell = require("@lt/AppShell")
local Colors = require("@lt/Colors")
local Fonts = require("@lt/Fonts")
local Icons = require("@lt/Icons")

type Node = { energy: number, v: number }

local NODE_COUNT = 512
local ELASTICITY = 10.0
local SPEED = 1.0
local DAMPING = 50.0

local function mix(a: number, b: number, t: number): number
  return a + (b - a) * t
end

return AppShell.Create(function(): Widget
  local nodes: { Node } = {}
  for _ = 1, NODE_COUNT do
    table.insert(nodes, { energy = 0, v = 0 })
  end
  local time = 0
  local point = Glyph_Circle(0, 1, 1, 1)
  local c1 = vector.create(0.1, 0.5, 1.0)
  local c2 = vector.create(0.5, 0.7, 1.0)

  return Widget_Layer(Compositor_Basic(0.2, 0.3, vector.create(0.4, 0.5, 0.9)), Mesh_Quad(), 1,
    Widget_Luau(Widget_Create(), {
      PostUpdate = function()
        local dt = FrameTimer_Get()
        local factor = 1 - Float_ExpDecay(dt, 1)
        for _ = 1, 5 do
          for i, node1 in nodes do
            local node2 = nodes[i % #nodes + 1]
            local delta = node1.energy - node2.energy
            node2.v += ELASTICITY * factor * delta
            node1.v -= ELASTICITY * factor * delta
          end
          for _, node in nodes do
            node.energy += SPEED * factor * node.v
            node.v *= Float_ExpDecay(dt, DAMPING)
          end
        end

        -- An occasional pulse somewhere on the ring
        if Float_Random() < 0.01 then
          local base = math.abs(Int_Random()) % #nodes
          local variance = mix(0.05, 0.4, Float_Random())
          for i = 0, 63 do
            local t = 2 * (i / 64) - 1
            local node = nodes[(base + i) % #nodes + 1]
            node.energy += 0.5 * math.exp(-1 * (math.abs(t) / variance))
          end
        end
      end,
      PreDraw = function(_, w: Widget)
        WidgetRenderer_DrawPanel(w.pos, w.size, 0.04, 1, 1, 0)
      end,
      PostDraw = function(_, w: Widget)
        WidgetRenderer_DrawText(Font_Get("Gafata/Regular.ttf"), `{FrameTimer_GetEMA10() * 1000} ms`,
          w.pos + vector.create(16, w.size.y - 16), 10, 0.1, 1, false)
        Icon_Draw(Icons.Cursors.Pointer(), Cursor_Get(), 12, 2 * Colors.Primary, 1)

        time += FrameTimer_Get()
        local completion = math.floor(100 * math.abs(0.5 + 0.5 * math.sin(time / 3)))
        WidgetRenderer_DrawText(Fonts.Default(), `[ LOADING  //  {completion}% ]`, w:Center(), 20, 0.3, 1, true)
        WidgetRenderer_DrawText(Fonts.Heading(), "LIMIT THEORY", w.size * vector.create(0.5, 1) - vector.create(0, 64),
          72, 0.1, 1, true)

        local center = w:Center()
        for i, node in nodes do
          local t = (i - 1) / #nodes
          local angle = 2 * math.pi * t
          local dir = vector.create(math.cos(angle), math.sin(angle))
          local p1 = center + dir * 128
          local mult = 1 + Float_ExpDecay(vector.magnitude(Cursor_Get() - p1), 64)
          local h = 2 * node.energy * mult
          local c = 8 * math.abs(node.v) * (c1 + (c2 - c1) * math.abs(2 * t - 1))
          local p2 = center + dir * (256 + 128 * h)
          Glyph_Draw(point, p1, 8, c, 1)
          Glyph_Draw(point, p2, 16, c, 1)
          Glyph_Draw(Glyph_LineFade(p1, p2, 1, 1), 0, 1, c1, 0.05)
        end
      end,
    }))
end)
