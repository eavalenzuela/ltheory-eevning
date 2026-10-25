--!strict
-- The static description of the galaxy (the "Describe" half of system
-- generation): system positions, gate links, resources and the stations
-- in each system, all as plain data. Nothing here creates engine objects,
-- so 400+ systems cost milliseconds. Jump distances and first hops
-- between every pair of systems are precomputed for routing.

local Data = require("@lt/Sim/Data")
local Rng = require("@lt/Sim/Rng")

local Galaxy = {}

export type StationDesc = { id: number, system: number, kind: string, name: string }
export type SystemDesc = {
  id: number,
  name: string,
  x: number,
  y: number,
  neighbors: { number },
  resources: { [string]: number },   -- richness of ferrite / silicate / ice
  stations: { number },              -- station ids
}
export type Galaxy = {
  seed: number,
  systems: { SystemDesc },
  stations: { StationDesc },
  hops: { { number } },              -- hops[a][b]: gate jumps from a to b
  nextHop: { { number } },           -- nextHop[a][b]: first system after a on the way to b
}

local SYLLABLES = { "ka", "ve", "ro", "sha", "tor", "mi", "len", "dra", "os", "thi", "ul", "xen", "qua", "bel",
  "nor", "is", "za", "pha", "rik", "an", "ves", "do", "cal", "ny" }

local function makeName(rng: Rng.Rng, used: { [string]: boolean }): string
  while true do
    local parts = {}
    for _ = 1, 2 + Rng.Int(rng, 2) do
      table.insert(parts, SYLLABLES[Rng.Int(rng, #SYLLABLES) + 1])
    end
    local name = table.concat(parts)
    name = string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
    if not used[name] then
      used[name] = true
      return name
    end
  end
end

-- Positions in a disc, kept apart by dart throwing
local function place(rng: Rng.Rng, count: number): { { x: number, y: number } }
  local radius = 12 * math.sqrt(count)
  local minDistance = 8
  local points: { { x: number, y: number } } = {}
  local attempts = 0
  while #points < count do
    attempts += 1
    local angle = Rng.Float(rng, 0, 2 * math.pi)
    local r = radius * math.sqrt(Rng.Next(rng))
    local p = { x = r * math.cos(angle), y = r * math.sin(angle) }
    local ok = true
    if attempts < count * 200 then
      for _, q in points do
        if (p.x - q.x) ^ 2 + (p.y - q.y) ^ 2 < minDistance ^ 2 then
          ok = false
          break
        end
      end
    end
    if ok then
      table.insert(points, p)
    end
  end
  return points
end

-- A minimum spanning tree (so every system is reachable) plus a few short
-- extra links for loops and alternative routes
local function link(rng: Rng.Rng, points: { { x: number, y: number } }): { { number } }
  local n = #points
  local neighbors: { { number } } = {}
  local linked: { [number]: boolean } = {}
  local function d2(a: number, b: number): number
    return (points[a].x - points[b].x) ^ 2 + (points[a].y - points[b].y) ^ 2
  end
  local function connect(a: number, b: number)
    local key = math.min(a, b) * 100000 + math.max(a, b)
    if a ~= b and not linked[key] then
      linked[key] = true
      table.insert(neighbors[a], b)
      table.insert(neighbors[b], a)
    end
  end
  for i = 1, n do
    neighbors[i] = {}
  end

  -- Prim's algorithm, O(n^2)
  local inTree = { [1] = true }
  local best: { number } = {}
  local from: { number } = {}
  for i = 2, n do
    best[i] = d2(1, i)
    from[i] = 1
  end
  for _ = 2, n do
    local pick, pickD = 0, math.huge
    for i = 2, n do
      if not inTree[i] and best[i] < pickD then
        pick, pickD = i, best[i]
      end
    end
    inTree[pick] = true
    connect(pick, from[pick])
    for i = 2, n do
      if not inTree[i] then
        local d = d2(pick, i)
        if d < best[i] then
          best[i] = d
          from[i] = pick
        end
      end
    end
  end

  -- Extra links to one of the three nearest systems
  for a = 1, n do
    if Rng.Chance(rng, 0.35) then
      local nearest: { number } = {}
      for b = 1, n do
        if b ~= a then
          table.insert(nearest, b)
        end
      end
      table.sort(nearest, function(p, q)
        local dp, dq = d2(a, p), d2(a, q)
        if dp ~= dq then
          return dp < dq
        end
        return p < q
      end)
      connect(a, nearest[Rng.Int(rng, 3) + 1])
    end
  end
  for i = 1, n do
    table.sort(neighbors[i])
  end
  return neighbors
end

-- Breadth-first search from every system
local function routes(neighbors: { { number } }): ({ { number } }, { { number } })
  local n = #neighbors
  local hops: { { number } } = {}
  local nextHop: { { number } } = {}
  for source = 1, n do
    local dist: { number } = table.create(n, -1)
    local first: { number } = table.create(n, 0)
    dist[source] = 0
    first[source] = source
    local queue = { source }
    local head = 1
    while head <= #queue do
      local a = queue[head]
      head += 1
      for _, b in neighbors[a] do
        if dist[b] < 0 then
          dist[b] = dist[a] + 1
          first[b] = if a == source then b else first[a]
          table.insert(queue, b)
        end
      end
    end
    hops[source] = dist
    nextHop[source] = first
  end
  return hops, nextHop
end

local function pickKind(rng: Rng.Rng, resources: { [string]: number }): string
  local weights: { { id: string, w: number } } = {}
  local total = 0
  for _, kind in Data.Stations do
    local w = kind.weight
    if kind.id == "mine" then
      w *= (resources.ferrite + resources.silicate)
    elseif kind.id == "harvester" then
      w *= resources.ice * 2
    end
    if w > 0 then
      table.insert(weights, { id = kind.id, w = w })
      total += w
    end
  end
  local roll = Rng.Float(rng, 0, total)
  for _, entry in weights do
    roll -= entry.w
    if roll <= 0 then
      return entry.id
    end
  end
  return weights[#weights].id
end

local function richness(rng: Rng.Rng): number
  return if Rng.Chance(rng, 0.35) then 0 else Rng.Float(rng, 0.3, 1.5)
end

function Galaxy.Describe(seed: number, count: number): Galaxy
  local rng = Rng.For(seed, 1)
  local points = place(rng, count)
  local neighbors = link(rng, points)
  local hops, nextHop = routes(neighbors)

  local used: { [string]: boolean } = {}
  local galaxy: Galaxy = { seed = seed, systems = {}, stations = {}, hops = hops, nextHop = nextHop }
  local STATION_COUNTS = { 0, 1, 1, 1, 2, 2, 2, 3, 3, 4 }
  for i = 1, count do
    local system: SystemDesc = {
      id = i,
      name = makeName(rng, used),
      x = points[i].x,
      y = points[i].y,
      neighbors = neighbors[i],
      resources = { ferrite = richness(rng), silicate = richness(rng), ice = richness(rng) },
      stations = {},
    }
    table.insert(galaxy.systems, system)
    for _ = 1, STATION_COUNTS[Rng.Int(rng, #STATION_COUNTS) + 1] do
      Galaxy.AddStation(galaxy, i, pickKind(rng, system.resources))
    end
    -- About one system in twelve has a shipyard
    if Rng.Chance(rng, 1 / 12) then
      Galaxy.AddStation(galaxy, i, "shipyard")
    end
  end
  return galaxy
end

function Galaxy.AddStation(galaxy: Galaxy, system: number, kind: string): number
  local id = #galaxy.stations + 1
  local desc = galaxy.systems[system]
  table.insert(galaxy.stations, {
    id = id,
    system = system,
    kind = kind,
    name = `{desc.name} {Data.StationById[kind].name}`,
  })
  table.insert(desc.stations, id)
  return id
end

-- The systems from 'from' to 'to', excluding 'from'
function Galaxy.Path(galaxy: Galaxy, from: number, to: number): { number }
  local path = {}
  local at = from
  while at ~= to do
    at = galaxy.nextHop[at][to]
    table.insert(path, at)
  end
  return path
end

function Galaxy.HasStation(galaxy: Galaxy, system: number, kind: string): boolean
  for _, id in galaxy.systems[system].stations do
    if galaxy.stations[id].kind == kind then
      return true
    end
  end
  return false
end

return Galaxy
