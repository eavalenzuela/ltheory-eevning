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
  -- How safe it is, from 1 (where a pilot starts) to 0 (lawless):
  -- Galaxy.Secure. What comes to a belt or waits at a gate follows
  -- from it (Tactical/Pirates), and what ore the belts have
  -- (Describe/System).
  security: number,
}

-- The three kinds of space a security figure makes.
export type Band = "secure" | "low" | "lawless"

function Galaxy.Band(security: number): Band
  return if security >= 0.7 then "secure" elseif security >= 0.3 then "low" else "lawless"
end

-- Give every system its security: 1 at the first system, falling with
-- the jumps from it, to nothing a little over half way to the farthest.
-- The farthest system of a galaxy of three or more is always lawless,
-- so the smallest galaxy still has somewhere that is.
--
-- (A stand-in: when the strategic layer joins the game a system's
-- security is what its owner's control and the pirates' pressure make
-- it, Strategic/Order.)
function Galaxy.Secure(galaxy: Galaxy)
  local systems = galaxy.systems
  local jumps: { number } = table.create(#systems, -1)
  local queue = { 1 }
  jumps[1] = 0
  local farthest, most = 1, 0
  local at = 1
  while at <= #queue do
    local id = queue[at]
    at += 1
    if jumps[id] > most or (jumps[id] == most and id > farthest) then
      farthest, most = id, jumps[id]
    end
    for _, neighbor in systems[id].neighbors do
      if jumps[neighbor] < 0 then
        jumps[neighbor] = jumps[id] + 1
        table.insert(queue, neighbor)
      end
    end
  end
  local span = math.max(2, math.ceil(most * 0.6))
  for id, system in systems do
    system.security = math.max(0, 1 - math.max(0, jumps[id]) / span)
  end
  if #systems >= 3 then
    systems[farthest].security = 0
  end
end

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
    systems[id] = { id = id, name = name, x = x, y = y, neighbors = {}, security = 1 }
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

  local galaxy: Galaxy = { seed = seed, systems = systems }
  Galaxy.Secure(galaxy)
  return galaxy
end

return Galaxy
