--!strict
-- Neural sandbox (Luau port of App/brain.lts): 1024 nodes in a disc
-- exchanging complex-valued energy along random local edges, with total
-- energy conserved. Click to amplify the nodes near the cursor.

local AppShell = require("@lt/AppShell")
local Colors = require("@lt/Colors")
local Fonts = require("@lt/Fonts")
local Icons = require("@lt/Icons")

type Node = { position: vector, energy: vector }
type Edge = { src: number, dst: number, energy: vector, mult: number, cooldown: number }

local NODE_COUNT = 1024
local EDGE_COUNT = 8
local DT = 0.01

-- Complex multiplication of two 2D vectors
local function cmult(a: vector, b: vector): vector
  return vector.create(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x)
end

local function length(v: vector): number
  return vector.magnitude(v)
end

local function normalize(v: vector): vector
  local l = length(v)
  return if l > 0 then v / l else v
end

return AppShell.Create(function(): Widget
  local nodes: { Node } = {}
  local edges: { Edge } = {}
  local frame = 0

  local function nodeEnergy(): number
    local e = 0
    for _, node in nodes do
      e += length(node.energy)
    end
    return e
  end
  local function edgeEnergy(): number
    local e = 0
    for _, edge in edges do
      e += length(edge.energy)
    end
    return e
  end

  local rng = RNG_MTG(Int_Random())
  for _ = 1, NODE_COUNT do
    local angle = 2 * math.pi * rng:Float()
    local position = vector.create(math.cos(angle), math.sin(angle)) * rng:Float() ^ 0.5
    table.insert(nodes, { position = position, energy = rng:Float() * rng:Vec2(-1, 1) })
  end
  for src = 1, NODE_COUNT do
    local made = 0
    while made < EDGE_COUNT do
      local dst = rng:Int(NODE_COUNT) + 1
      if src ~= dst then
        local distance = length(nodes[src].position - nodes[dst].position)
        if rng:Float() < Float_ExpDecay(distance, 0.05) then
          table.insert(edges, { src = src, dst = dst, mult = 1, cooldown = 0,
            energy = vector.create(rng:Float(-1, 1), rng:Float(-1, 1)) })
          made += 1
        end
      end
    end
  end
  local totalEnergy = nodeEnergy()
  local totalEdgeEnergy = edgeEnergy()
  local glyph = Glyph_Circle(0, 1, 1, 1)

  return Widget_Layer(Compositor_None(), Mesh_Quad(), 1, Widget_Stack(Widget_Luau(Widget_Create(), {
    PreUpdate = function(_, w: Widget)
      -- Add energy
      if Mouse_LeftPressed() then
        local cursor = Cursor_Get()
        local center = w:Center()
        local s = 0.5 * math.min(w.size.x, w.size.y)
        for _, node in nodes do
          local dist = length(cursor - (center + s * node.position))
          node.energy *= 1 + 500 * Float_ExpDecay(dist, 16)
        end
      end

      -- Energy transfer
      for _, edge in edges do
        if edge.cooldown <= 0 then
          local node1, node2 = nodes[edge.src], nodes[edge.dst]
          local e1, e2 = length(node1.energy), length(node2.energy)
          if e1 > 0 and e2 > 0 then
            local transfer = cmult(node1.energy, edge.energy)
            local dot = math.clamp(vector.dot(normalize(transfer), normalize(node2.energy)), 0, 1)
            local factor = 1 - Float_ExpDecay(edge.mult * DT * (e1 / e2), 1)
            local finalTransfer = transfer * factor
            node1.energy -= finalTransfer
            node2.energy += finalTransfer
            edge.energy *= Float_ExpDecay(DT * (1 - dot), 1)
          end
        end
      end

      -- Energy rotation
      for _, node in nodes do
        local angle = DT * length(node.energy)
        node.energy = cmult(node.energy, vector.create(math.cos(angle), math.sin(angle)))
      end

      -- Energy conservation
      local nodeFactor = totalEnergy / nodeEnergy()
      for _, node in nodes do
        node.energy *= nodeFactor
      end
      local edgeFactor = totalEdgeEnergy / edgeEnergy()
      for _, edge in edges do
        edge.energy *= edgeFactor
      end

      frame += 1
    end,
    PreDraw = function(_, w: Widget)
      WidgetRenderer_DrawPanel(w.pos, w.size, 0.1, 1, 1, 0)
    end,
    PostDraw = function(_, w: Widget)
      Icon_Draw(Icons.Cursors.Cross(), Cursor_Get(), 12, 4 * Colors.Primary, 0.3)
      WidgetRenderer_DrawText(Fonts.Heading(), "Neural Sandbox", w:TopLeft() + vector.create(16, 48), 72, 0.3, 0.5, false)
      local center = w:Center()
      local s = 0.4 * math.min(w.size.x, w.size.y)
      for _, node in nodes do
        Glyph_Draw(glyph, center + s * node.position, 12, Colors.Primary, math.clamp(length(node.energy), 0, 1))
      end
      for _, edge in edges do
        local node1, node2 = nodes[edge.src], nodes[edge.dst]
        local psrc = center + s * node1.position
        local pdst = center + s * node2.position
        local t = length(node1.energy)
        Glyph_Draw(Glyph_LineFade(psrc, pdst, 1, 1), 0, 1, 0.02, 1)
        if t > 0.001 then
          Glyph_Draw(Glyph_LineFade(psrc, pdst, 1, 1), 0, 1, Colors.Primary, 0.2 * t)
        end
      end
    end,
  })))
end)
