--!strict
-- Harmonic neural network toy (Luau port of App/hnn.lts): a line of
-- oscillators exchanging energy along their edges. Click to inject an
-- impulse near the cursor; Up / Down change the simulation speed.

local AppShell = require("@lt/AppShell")
local Colors = require("@lt/Colors")
local Components = require("@lt/Widget/Components")
local Fonts = require("@lt/Fonts")
local Icons = require("@lt/Icons")
local Widgets = require("@lt/Widgets")

type Node = { pos: vector, normal: vector, energy: number, angle: number, mass: number }
type Edge = { node1: number, node2: number, w: number }

local TAU = 2 * math.pi
local DT = 0.03

local nodes: { Node } = {}
local edges: { Edge } = {}

local function createLine(p1: vector, p2: vector, count: number)
  for i = 0, count - 1 do
    local t = i / (count - 1)
    if i > 0 then
      local index = #nodes + 1
      table.insert(edges, { node1 = index - 1, node2 = index, w = 1 })
    end
    table.insert(nodes, { pos = p1 + (p2 - p1) * t, normal = vector.create(0, 1), energy = 0, angle = 0, mass = 0 })
  end
end

local function update(dt: number)
  -- Edge forces
  for _, edge in edges do
    local node1, node2 = nodes[edge.node1], nodes[edge.node2]
    local delta = dt * edge.w * (node2.energy - node1.energy)
    node1.mass += delta
    node2.mass -= delta
  end
  -- Velocity
  for _, node in nodes do
    node.angle += dt * node.energy
    node.energy += dt * node.mass
    while node.angle >= TAU do
      node.angle -= TAU
    end
  end
end

return AppShell.Create(function(): Widget
  local selected = 1
  local speed = 10
  local glyph = Glyph_Circle(0, 1, 1, 1)

  local network = Widget_ListVertical(8, Widget_Luau(Widget_Create(), {
    CreateChildren = function(): { Widget }
      return { Widgets.Text(Fonts.Heading(), "Harmonic Neural Network", 16, vector.create(1, 1, 1)) }
    end,
    PreUpdate = function(_, w: Widget)
      if #nodes == 0 then
        createLine(vector.create(16, 0.25 * w.size.y), vector.create(w.size.x - 16, 0.25 * w.size.y), 512)
        for _ = 1, 2 do
          local n1 = math.abs(Int_Random()) % #nodes + 1
          local n2 = math.abs(Int_Random()) % #nodes + 1
          table.insert(edges, { node1 = n1, node2 = n2, w = 0.1 })
        end
      end

      -- Selection: the node nearest the cursor
      local c = Cursor_Get()
      selected = 1
      local dist = vector.magnitude(nodes[1].pos - c)
      for i = 2, #nodes do
        local d = vector.magnitude(nodes[i].pos - c)
        if d < dist then
          dist = d
          selected = i
        end
      end

      if Key_Pressed(Key_Up()) then
        speed *= 2
        print(speed)
      end
      if Key_Pressed(Key_Down()) then
        speed = speed // 2
        print(speed)
      end

      -- Impulse
      if Mouse_LeftPressed() then
        for i = 0, 63 do
          local t = 2 * (i / 63) - 1
          local node = nodes[selected + i]
          if node then
            node.energy += math.exp(-1 * (math.abs(t) / 0.5) ^ 2)
          end
        end
      end

      for _ = 1, speed do
        update(DT)
      end
    end,
    PreDraw = function(_, w: Widget)
      WidgetRenderer_DrawPanel(w.pos, w.size, 0.1, 1, 1, 0)
      Icon_Draw(Icons.Cursors.Cross(), Cursor_Get(), 12, 4 * Colors.Primary, 0.3)
      for i, node in nodes do
        local vec = node.energy * vector.create(math.cos(node.angle), math.sin(node.angle))
        local p2 = node.pos + 128 * vec.x * node.normal
        local color = if i == selected then Colors.Secondary else Colors.Primary
        Glyph_Draw(glyph, node.pos, 16 * node.energy, node.angle * color, 1)
        Glyph_Draw(Glyph_Line(node.pos, p2, 1, 1), 0, 1, color, 1)
      end
      w:Rebuild()
    end,
  }))
  return Widget_Layer(Compositor_None(), Mesh_Quad(), 1, Components.Padding(16, 16, network))
end)
