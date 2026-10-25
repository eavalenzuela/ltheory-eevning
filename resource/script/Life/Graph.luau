--!strict
-- A graph of binary cells (Luau port of App/Life/Graph.lts). Each step a
-- node's value becomes the parity of its neighbours' previous values.
-- Indices are 1-based.

local Graph = {}

export type Node = {
  p: vector,
  value: number,
  valueLast: number,
  heat: number,
  valueAvg: number,
  heatAvg: number,
}
export type Edge = { src: number, dst: number, boundary: boolean }
export type Graph = { nodes: { Node }, edges: { Edge } }

function Graph.New(): Graph
  return { nodes = {}, edges = {} }
end

function Graph.NewNode(p: vector): Node
  return { p = p, value = 0, valueLast = 0, heat = 0, valueAvg = 0, heatAvg = 0 }
end

local function mix(a: number, b: number, t: number): number
  return a + (b - a) * t
end

-- An sx by sy grid wrapping at the edges, rotated 45 degrees
function Graph.AddLatticeGrid(self: Graph, sx: number, sy: number)
  local angle = 3 * math.pi / 4
  local c, s = math.cos(angle), math.sin(angle)
  local index = 0
  for y = 0, sy - 1 do
    for x = 0, sx - 1 do
      local p = 2 * vector.create(x / (sx - 1), y / (sy - 1)) - vector.create(1, 1)
      p = vector.create(c * p.x + s * p.y, c * p.y - s * p.x)
      p = vector.create(p.x * math.sqrt(2), p.y)
      p = 0.5 * p + vector.create(0.5, 0.5)
      table.insert(self.nodes, Graph.NewNode(p))

      local xp, yp = x + 1, y + 1
      local boundaryX, boundaryY = false, false
      if xp >= sx then
        xp -= sx
        boundaryX = true
      end
      if yp >= sy then
        yp -= sy
        boundaryY = true
      end
      local function edge(dst: number, boundary: boolean)
        table.insert(self.edges, { src = index + 1, dst = dst + 1, boundary = boundary })
      end
      edge(yp * sx + x, boundaryY)
      edge(y * sx + xp, boundaryX)
      edge(yp * sx + xp, boundaryX or boundaryY)
      index += 1
    end
  end
end

-- Concentric rings of a 'poly'-sided polygon, 'radius' rings deep
function Graph.AddLattice(self: Graph, poly: number, radius: number)
  local countLast, indexLast = 0, 0
  local anchors: { vector } = {}
  for i = 0, poly - 1 do
    local phase = 2 * math.pi * (i / poly) + math.pi / 2
    table.insert(anchors, vector.create(math.cos(phase), math.sin(phase)))
  end
  local function edge(src: number, dst: number, boundary: boolean)
    table.insert(self.edges, { src = src + 1, dst = dst + 1, boundary = boundary })
  end

  for i = 0, radius - 1 do
    local count = math.max(1, poly * i)
    local r = i / radius
    local index = #self.nodes
    for j = 0, count - 1 do
      local phase = 2 * math.pi * (j / count) + math.pi / 2
      local p = vector.create(math.cos(phase), math.sin(phase))
      if i > 0 then
        local a = j // i
        local b = (a + 1) % poly
        local pa, pb = anchors[a + 1], anchors[b + 1]
        local n = vector.normalize(pb - pa)
        p = pa + n * vector.dot(n, p - pa)
      end
      p = vector.create(0.5, 0.5) + 0.5 * r * p
      table.insert(self.nodes, Graph.NewNode(p))

      edge(index + j, index + (j + 1) % count, false)
      if i > 0 and i + 1 == radius and j % i == 0 then
        edge(index + j, index + (j + count // 2) % count, true)
      end
      if i > 0 then
        local proj = (j // i) * (i - 1)
        local m = j % i
        if m == 0 then
          edge(index + j, indexLast + proj, false)
        else
          edge(index + j, indexLast + proj + m - 1, false)
          edge(index + j, indexLast + (proj + m) % countLast, false)
        end
      end
    end
    countLast = count
    indexLast = index
  end
end

function Graph.Step(self: Graph)
  local factor = 1 - Float_ExpDecay(1, 10)
  for _, node in self.nodes do
    node.valueLast = node.value
    node.value = 0
  end
  for _, edge in self.edges do
    local src, dst = self.nodes[edge.src], self.nodes[edge.dst]
    src.value += dst.valueLast
    dst.value += src.valueLast
  end
  for _, node in self.nodes do
    node.value %= 2
    node.valueAvg = mix(node.valueAvg, node.value, factor)
    if node.value == node.valueLast then
      node.heat += 1
      node.heatAvg = mix(node.heatAvg, 1, factor)
    else
      node.heat = 0
      node.heatAvg = mix(node.heatAvg, 0, factor)
    end
  end
end

return Graph
