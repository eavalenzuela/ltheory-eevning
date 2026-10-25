--!strict
-- Universe lattice simulation (Luau port of App/universe.lts): nodes on
-- spiral shells, each linked to its three nearest neighbours, passing an
-- integer quantity between them.

local AppShell = require("@lt/AppShell")
local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local FrameInfo = require("@lt/Widget/Dev/FrameInfo")
local Icons = require("@lt/Icons")
local Widgets = require("@lt/Widgets")

local UNIVERSE_SIZE = 512

type Node = { p: vector, x: number, y: number, n1: number, n2: number, n3: number }

local function build(): { Node }
  local nodes: { Node } = {}
  local radius, count, countLast, remaining = 0, 1, 0, 1
  for _ = 1, UNIVERSE_SIZE do
    local angle = 2 * math.pi * (remaining / count)
    table.insert(nodes, { p = radius * vector.create(math.cos(angle), math.sin(angle)), x = 0, y = 0, n1 = 0, n2 = 0, n3 = 0 })
    remaining -= 1
    if remaining == 0 then
      local newCount = count * 3 - countLast
      countLast = count
      count = newCount
      remaining = count
      radius += 0.1 * math.sqrt(newCount)
    end
  end

  -- The three nearest neighbours of each node (as 1-based indices)
  for i, node in nodes do
    local n1, n2, n3 = i % #nodes + 1, (i + 1) % #nodes + 1, (i + 2) % #nodes + 1
    local d1, d2, d3 = 1000000, 1000000, 1000000
    for j, neighbor in nodes do
      if i ~= j then
        local d = vector.magnitude(neighbor.p - node.p)
        if d < d1 then
          d3, n3, d2, n2, d1, n1 = d2, n2, d1, n1, d, j
        elseif d < d2 then
          d3, n3, d2, n2 = d2, n2, d, j
        elseif d < d3 then
          d3, n3 = d, j
        end
      end
    end
    node.n1, node.n2, node.n3 = n1, n2, n3
  end
  return nodes
end

-- C++ integer division: truncates toward zero
local function idiv(a: number, b: number): number
  local q = a / b
  return if q < 0 then math.ceil(q) else math.floor(q)
end

local function step(nodes: { Node })
  for _, node in nodes do
    local n1, n2, n3 = nodes[node.n1], nodes[node.n2], nodes[node.n3]
    local sum = node.x + n1.x + n2.x + n3.x
    node.y -= sum
    local out = idiv(sum, 3)
    n1.y += out
    n2.y += out
    n3.y += out
    node.y += 3 * out - sum
  end
  for _, node in nodes do
    node.x += node.y
    node.y = 0
  end
end

return AppShell.Create(function(): Widget
  local nodes: { Node } = {}
  local glyph = Glyph_Circle(0, 1, 1, 1)
  local lattice = Widget_ListVertical(8, Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return { Widgets.Text(Fonts.Heading(), "Universe Lattice Simulation", 16, vector.create(1, 1, 1)) }
    end,
    PreUpdate = function()
      if #nodes == 0 then
        nodes = build()
      end
      step(nodes)
    end,
    PreDraw = function(_, w: Widget)
      WidgetRenderer_DrawPanel(w.pos, w.size, 0.1, 1, 1, 0)
      Icon_Draw(Icons.Cursors.Cross(), Cursor_Get(), 12, 4 * Colors.Primary, 0.3)
      FrameInfo.Draw(w)
      local center = w:Center()
      local scale = 0.5 * math.max(w.size.x, w.size.y)
      for _, node in nodes do
        local pos = center + scale * node.p
        Glyph_Draw(glyph, pos, 16 * node.x, Colors.Primary, 1)
        for _, n in { node.n1, node.n2, node.n3 } do
          Glyph_Draw(Glyph_Line(pos, center + scale * nodes[n].p, 1, 1), 0, 1, 0.1, 1)
        end
      end
    end,
  }))
  return Widget_Layer(Compositor_None(), Mesh_Quad(), 1, Components.Padding(16, 16, lattice))
end)
