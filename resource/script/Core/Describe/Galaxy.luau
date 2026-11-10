--!strict
-- The galaxy as data: systems on a map and the gates between them.
-- Describe is a pure function of the galaxy seed. Nothing here creates an
-- engine object; the layout inside each system is Describe/System. Who
-- lives where and what is made there is Strategic/Atlas; distances in
-- jumps are Strategic/Routes.

local Names = require("@lt/Core/Describe/Names")
local Rng = require("@lt/Core/Kernel/Rng")

local Galaxy = {}

export type SystemNode = {
  id: number,
  name: string,
  x: number,              -- light years on the map
  y: number,
  neighbors: { number },  -- ids of systems one jump away, ascending
}

export type Galaxy = {
  seed: number,
  systems: { SystemNode },  -- systems[id]
}

local SPACING = 4 -- light years between neighbours, roughly

function Galaxy.Describe(seed: number, count: number): Galaxy
  assert(count >= 1 and count % 1 == 0, "a galaxy needs a whole number of systems")
  local rng = Rng.For(seed, 1001)
  local systems: { SystemNode } = {}
  local used: { [string]: boolean } = {}
  local radius = SPACING * math.sqrt(count)

  for id = 1, count do
    -- A place not too close to any earlier system.
    local x, y = 0, 0
    for _ = 1, 200 do
      local angle = Rng.Float(rng, 0, 2 * math.pi)
      local r = radius * math.sqrt(Rng.Next(rng))
      x, y = r * math.cos(angle), r * math.sin(angle)
      local clear = true
      for _, other in systems do
        if (other.x - x) ^ 2 + (other.y - y) ^ 2 < (SPACING * 0.6) ^ 2 then
          clear = false
          break
        end
      end
      if clear then
        break
      end
    end
    local name = Names.System(rng)
    while used[name] do
      name = Names.System(rng)
    end
    used[name] = true
    systems[id] = { id = id, name = name, x = x, y = y, neighbors = {} }
  end

  local function link(a: number, b: number)
    if a ~= b and not table.find(systems[a].neighbors, b) then
      table.insert(systems[a].neighbors, b)
      table.insert(systems[b].neighbors, a)
    end
  end
  local function nearest(id: number, limit: number, skip: { number }): number?
    local best: number? = nil
    local bestDistance = math.huge
    for other = 1, limit do
      if other ~= id and not table.find(skip, other) then
        local d = (systems[other].x - systems[id].x) ^ 2 + (systems[other].y - systems[id].y) ^ 2
        if d < bestDistance then
          best, bestDistance = other, d
        end
      end
    end
    return best
  end

  -- A tree first, so every system can be reached: each system gates to
  -- the nearest one made before it. Then some shortcuts.
  for id = 2, count do
    link(id, nearest(id, id - 1, {}) :: number)
  end
  for id = 1, count do
    if count > 3 and Rng.Chance(rng, 0.35) then
      local other = nearest(id, count, systems[id].neighbors)
      if other then
        link(id, other)
      end
    end
  end
  for _, system in systems do
    table.sort(system.neighbors)
  end

  return { seed = seed, systems = systems }
end

return Galaxy
