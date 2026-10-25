--!strict
-- A graph driven by fixed points (Luau port of App/Life/Organism.lts):
-- each fixed point forces its node through a repeating sequence of
-- values. Save / Load keep it in a text file.

local Graph = require("@lt/Life/Graph")

local Organism = {}

export type FixedPoint = { index: number, sequence: { number } }
export type Organism = { graph: Graph.Graph, points: { FixedPoint }, age: number }

function Organism.New(): Organism
  return { graph = Graph.New(), points = {}, age = 0 }
end

function Organism.Step(self: Organism)
  for _, fp in self.points do
    local node = self.graph.nodes[fp.index]
    local value = fp.sequence[self.age % #fp.sequence + 1]
    node.value = value
    node.valueLast = value
  end
  Graph.Step(self.graph)
  self.age += 1
end

local function num(x: number): string
  return string.format("%.17g", x)
end

function Organism.Save(self: Organism, path: string): boolean
  local out = { `organism 1 {self.age} {#self.graph.nodes} {#self.graph.edges} {#self.points}` }
  for _, n in self.graph.nodes do
    table.insert(out, `{num(n.p.x)} {num(n.p.y)} {n.value} {n.valueLast} {n.heat} {num(n.valueAvg)} {num(n.heatAvg)}`)
  end
  for _, e in self.graph.edges do
    table.insert(out, `{e.src} {e.dst} {if e.boundary then 1 else 0}`)
  end
  for _, fp in self.points do
    table.insert(out, `{fp.index} {table.concat(fp.sequence, " ")}`)
  end
  return File_Write(path, table.concat(out, "\n") .. "\n")
end

-- The organism saved at 'path', or nil if there isn't a valid one
function Organism.Load(path: string): Organism?
  local lines = string.split(File_Read(path), "\n")
  local function numbers(i: number): { number }
    local values = {}
    for token in string.gmatch(lines[i] or "", "%S+") do
      table.insert(values, tonumber(token) :: number)
    end
    return values
  end
  local header = string.split(lines[1] or "", " ")
  if header[1] ~= "organism" or header[2] ~= "1" then
    return nil
  end
  local age, nodeCount, edgeCount, pointCount =
    tonumber(header[3]) :: number, tonumber(header[4]) :: number, tonumber(header[5]) :: number, tonumber(header[6]) :: number
  local self = Organism.New()
  self.age = age
  local line = 2
  for _ = 1, nodeCount do
    local v = numbers(line)
    table.insert(self.graph.nodes, { p = vector.create(v[1], v[2]), value = v[3], valueLast = v[4], heat = v[5],
      valueAvg = v[6], heatAvg = v[7] })
    line += 1
  end
  for _ = 1, edgeCount do
    local v = numbers(line)
    table.insert(self.graph.edges, { src = v[1], dst = v[2], boundary = v[3] == 1 })
    line += 1
  end
  for _ = 1, pointCount do
    local v = numbers(line)
    table.insert(self.points, { index = table.remove(v, 1) :: number, sequence = v })
    line += 1
  end
  return self
end

return Organism
