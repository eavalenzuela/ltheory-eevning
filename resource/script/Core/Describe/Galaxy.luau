--!strict
-- The galaxy as data: systems on a map and the gates between them.
-- Describe is a pure function of the galaxy seed. Nothing here creates an
-- engine object; the layout inside each system is Describe/System. Who
-- lives where and what is made there is Strategic/Atlas; distances in
-- jumps are Strategic/Routes.

local Factions = require("@lt/Core/Data/Factions")
local Names = require("@lt/Core/Describe/Names")
local Rng = require("@lt/Core/Kernel/Rng")

local Galaxy = {}

export type SystemNode = {
  id: number,
  name: string,
  x: number,              -- light years on the map
  y: number,
  neighbors: { number },  -- ids of systems one jump away, ascending
  -- Whose it is (Galaxy.Claim): the id of a human faction
  -- (Data/Factions), or "" for space nobody holds.
  owner: string,
  -- The faction whose homeworld is nearest, holder or not: whose towers
  -- the stations there are, and whose ships come by.
  nearest: string,
  home: boolean,          -- it is a faction's homeworld
  hops: number,           -- jumps to the nearest homeworld
  -- How safe it is, from 1 (a homeworld) to 0 (space nobody holds).
  -- What comes to a belt or waits at a gate follows from it
  -- (Tactical/Pirates), and what ore the belts have (Describe/System).
  security: number,
}

-- The three kinds of space a security figure makes.
export type Band = "secure" | "low" | "lawless"

function Galaxy.Band(security: number): Band
  return if security >= 0.7 then "secure" elseif security >= 0.3 then "low" else "lawless"
end

-- The share of a galaxy's systems that some faction holds.
Galaxy.CLAIMED = 0.7
-- A faction for every this many systems, up to the four there are.
Galaxy.SYSTEMS_A_FACTION = 10

-- Jumps from 'source' to every system.
local function hopsFrom(systems: { SystemNode }, source: number): { number }
  local hops: { number } = table.create(#systems, -1)
  hops[source] = 0
  local queue = { source }
  local at = 1
  while at <= #queue do
    local id = queue[at]
    at += 1
    for _, neighbor in systems[id].neighbors do
      if hops[neighbor] < 0 then
        hops[neighbor] = hops[id] + 1
        table.insert(queue, neighbor)
      end
    end
  end
  return hops
end

-- Say whose each system is, and so how safe.
--
-- The human factions have a homeworld each: the first faction's is the
-- first system, where a pilot starts, and each next one's is as far as
-- can be from those already chosen. A small galaxy has fewer factions.
-- The systems nearest a homeworld are its faction's, seven in ten of
-- them all told; the rest, the farthest from anybody, nobody holds.
-- Security is 1 at a homeworld and falls with the jumps from it, never
-- below "low" in space somebody holds, and is nothing in space nobody
-- does. So the smallest galaxy that has three systems has one of each
-- kind of space.
--
-- (The aliens are not on the map yet: where they live is not settled.
-- And who holds what does not change: when the strategic layer joins
-- the game, ownership and security are what its powers make them.)
function Galaxy.Claim(galaxy: Galaxy)
  local systems = galaxy.systems
  local count = #systems
  local humans: { string } = {}
  for _, faction in Factions.list do
    if faction.kind == "human" then
      table.insert(humans, faction.id)
    end
  end
  local wanted = math.clamp(count // Galaxy.SYSTEMS_A_FACTION, 1, #humans)
  local hops = hopsFrom(systems, 1)
  local nearest: { number } = table.create(count, 1)
  local homes = 1
  while homes < wanted do
    local best, most = 1, -1
    for id = 1, count do
      if hops[id] > most then
        best, most = id, hops[id]
      end
    end
    homes += 1
    for id, far in hopsFrom(systems, best) do
      if far < hops[id] then
        hops[id] = far
        nearest[id] = homes
      end
    end
  end

  -- The nearest to a homeworld first, and of those as near, the lower id.
  local order: { number } = {}
  for id = 1, count do
    order[id] = id
  end
  table.sort(order, function(a: number, b: number): boolean
    if hops[a] ~= hops[b] then
      return hops[a] < hops[b]
    end
    return a < b
  end)
  local claimed = math.max(1, math.floor(count * Galaxy.CLAIMED))
  local reach = hops[order[claimed]]
  for rank, id in order do
    local system = systems[id]
    local held = rank <= claimed
    system.owner = if held then humans[nearest[id]] else ""
    system.nearest = humans[nearest[id]]
    system.hops = hops[id]
    system.home = hops[id] == 0
    system.security = if held then math.max(0.3, 1 - hops[id] / (reach + 1)) else 0
  end
end

-- What a jump into a system counts for when the safest way is wanted,
-- beside the jump itself: nothing where order is kept, a little where
-- it is thin, and a great deal where there is none, so that a route
-- goes through lawless space only when there is no other way, and then
-- through as little of it as it can.
local RISK: { [string]: number } = { secure = 0, low = 2, lawless = 30 }

-- The way from one system to another: the systems in order, both ends
-- included (one system, if they are the same). The fewest jumps, or
-- with 'safest' the least dangerous way. Of ways as good, the one
-- through the lower-numbered systems.
function Galaxy.Route(galaxy: Galaxy, from: number, to: number, safest: boolean?): { number }
  local systems = galaxy.systems
  assert(systems[from] and systems[to], "no such system")
  local count = #systems
  local cost: { number } = table.create(count, math.huge)
  local before: { number } = table.create(count, 0)
  local done: { boolean } = table.create(count, false)
  cost[from] = 0
  for _ = 1, count do
    local at, least = 0, math.huge
    for id = 1, count do
      if not done[id] and cost[id] < least then
        at, least = id, cost[id]
      end
    end
    if at == 0 or at == to then
      break
    end
    done[at] = true
    for _, neighbor in systems[at].neighbors do
      local step = 1 + (if safest then RISK[Galaxy.Band(systems[neighbor].security)] else 0)
      if least + step < cost[neighbor] then
        cost[neighbor] = least + step
        before[neighbor] = at
      end
    end
  end
  local route: { number } = { to }
  while route[1] ~= from do
    table.insert(route, 1, before[route[1]])
  end
  return route
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
    systems[id] = { id = id, name = name, x = x, y = y, neighbors = {}, owner = "", nearest = "", home = false, hops = 0, security = 1 }
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
  Galaxy.Claim(galaxy)
  return galaxy
end

return Galaxy
