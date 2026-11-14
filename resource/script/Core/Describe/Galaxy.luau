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
  -- A name where somebody holds the system, and where nobody does the
  -- mark it has in the surveys (Galaxy.Marks).
  name: string,
  x: number,              -- light years on the map
  y: number,
  -- And above the plane of the map (below it, if less than nothing): the
  -- map has a gentle relief (Galaxy.Heights), which is in how far apart
  -- two systems are (Galaxy.Apart) and in nothing else of the galaxy.
  z: number,
  neighbors: { number },  -- ids of systems one jump away, ascending
  -- Whose it is (Galaxy.Claim): the id of a faction (Data/Factions), or
  -- "" for space nobody holds.
  owner: string,
  -- Whose towers the stations there are: the holder's, if the holder is
  -- one of the human factions; else the human faction's whose homeworld
  -- is nearest on the map.
  nearest: string,
  home: boolean,          -- it is a faction's homeworld
  hops: number,           -- jumps to the nearest homeworld
  -- How safe it is, from 1 (a homeworld) to 0 (space nobody holds, or
  -- the pirates do).
  -- What comes to a belt or waits at a gate follows from it
  -- (Tactical/Pirates), and what ore the belts have (Describe/System).
  security: number,
  -- Where it is on the map of names (Galaxy.Regions): its region, and
  -- its constellation within that, by their ids.
  region: number,
  constellation: number,
}

-- A region is a score or so of systems that lie together, and a
-- constellation a handful of those: names to find one's way by.
export type Region = { id: number, name: string }
export type Constellation = { id: number, name: string, region: number }

-- The three kinds of space a security figure makes.
export type Band = "secure" | "low" | "lawless"

function Galaxy.Band(security: number): Band
  return if security >= 0.7 then "secure" elseif security >= 0.3 then "low" else "lawless"
end

-- How many systems a faction holds, its homeworld among them; but all
-- the factions together hold no more than this share of a galaxy, so
-- in one too small for that they hold fewer each.
Galaxy.TERRITORY = 90
Galaxy.CLAIMED = 0.7
-- A faction for every this many systems, up to as many as there are.
Galaxy.SYSTEMS_A_FACTION = 10
-- A homeworld is a system with this many gates or more, this far (light
-- years on the map) or further from every other homeworld: or as near
-- to that as the galaxy has.
Galaxy.HOME_GATES = 5
Galaxy.HOME_APART = 100
-- How many times the homeworlds are drawn at a distance apart before
-- that distance is given up for a shorter one, in a galaxy with room
-- for whole territories.
Galaxy.HOME_DRAWS = 40

-- Whether a faction keeps order in the space it holds. The pirates do
-- not: what is theirs is lawless, with nobody to patrol it, nobody to
-- guard its gates and nobody to mind what is done there.
function Galaxy.KeepsOrder(faction: string): boolean
  local its = Factions.byId[faction]
  return its ~= nil and its.kind ~= "pirate"
end

-- The faction that keeps order in a system: whoever holds it, if they
-- keep order. "" for nobody.
function Galaxy.Keeper(system: SystemNode): string
  return if Galaxy.KeepsOrder(system.owner) then system.owner else ""
end

-- The factions that hold space in a galaxy, in the order of the list:
-- those with a homeworld in it. (Worked out once for a galaxy and kept
-- beside it, not in it: the homeworlds say it all.)
local holders: { [any]: { string } } = setmetatable({}, { __mode = "k" }) :: any
function Galaxy.Holders(galaxy: Galaxy): { string }
  local kept = holders[galaxy]
  if kept == nil then
    local has: { [string]: boolean } = {}
    for _, system in galaxy.systems do
      if system.home then
        has[system.owner] = true
      end
    end
    kept = {}
    for _, faction in Factions.list do
      if has[faction.id] then
        table.insert(kept, faction.id)
      end
    end
    holders[galaxy] = kept
  end
  return kept
end

-- A heap of numbered things, the least 'key' at its head and of those
-- as small the lower-numbered: put one in, and take the head out.
local function heapPush(keys: { number }, ids: { number }, key: number, id: number)
  local hole = #keys + 1
  while hole > 1 do
    local parent = hole // 2
    if key < keys[parent] or (key == keys[parent] and id < ids[parent]) then
      keys[hole], ids[hole] = keys[parent], ids[parent]
      hole = parent
    else
      break
    end
  end
  keys[hole], ids[hole] = key, id
end

local function heapPop(keys: { number }, ids: { number }): (number, number)
  local size = #keys
  local key, id = keys[1], ids[1]
  local lastKey, lastId = keys[size], ids[size]
  keys[size], ids[size] = nil, nil
  size -= 1
  if size > 0 then
    local hole = 1
    while true do
      local child = hole * 2
      if child > size then
        break
      end
      if child < size and (keys[child + 1] < keys[child] or (keys[child + 1] == keys[child] and ids[child + 1] < ids[child])) then
        child += 1
      end
      if keys[child] < lastKey or (keys[child] == lastKey and ids[child] < lastId) then
        keys[hole], ids[hole] = keys[child], ids[child]
        hole = child
      else
        break
      end
    end
    keys[hole], ids[hole] = lastKey, lastId
  end
  return key, id
end

-- Say whose each system is, and so how safe. This is done when all the
-- systems and their gates are made, and takes nothing from the order
-- they were made in but where a pilot starts.
--
-- Every faction has a homeworld. The first faction's is the first
-- system, where a pilot starts. Each of the others' is drawn from the
-- systems with five gates or more that are a hundred light years or
-- further from every homeworld already placed, and next door to none.
-- (A galaxy too small for that: with as many gates as enough of its
-- systems have, and as far apart as they can be.) A small galaxy has
-- fewer factions, the first of the list.
--
-- Then they take their space in turns, a system a turn, round and
-- round in the order of the list: each takes the system nearest its
-- homeworld of those it has a gate to from what it already holds, so
-- that what is a faction's is all of a piece and near its homeworld.
-- (One shut in, with no such system left, takes the nearest that
-- nobody has, wherever it is.) They stop at Galaxy.TERRITORY systems
-- each, or sooner in a galaxy too small for it (Galaxy.CLAIMED); so
-- every faction has as much as any other, and nobody holds the rest.
--
-- Security is 1 at a homeworld and falls with the jumps from it through
-- its faction's own space, never below "low" in space somebody holds,
-- and is nothing in space nobody does, or that the pirates do. So the
-- smallest galaxy that has three systems has one of each kind of space.
--
-- (Who holds what does not change: when the strategic layer joins the
-- game, ownership and security are what its powers make them.)
function Galaxy.Claim(galaxy: Galaxy)
  local systems = galaxy.systems
  local count = #systems
  local factions = Factions.list
  local wanted = math.clamp(count // Galaxy.SYSTEMS_A_FACTION, 1, #factions)
  local each = math.max(1, math.min(Galaxy.TERRITORY, math.floor(count * Galaxy.CLAIMED / wanted)))
  -- (how far apart two systems are on the map, squared)
  local function apart2(a: number, b: number): number
    return (systems[a].x - systems[b].x) ^ 2 + (systems[a].y - systems[b].y) ^ 2
  end

  -- The homeworlds.
  local homes: { number } = { 1 }
  if wanted > 1 then
    local gates = Galaxy.HOME_GATES
    local choice: { number } = {}
    while true do
      choice = {}
      for id = 2, count do
        if #systems[id].neighbors >= gates then
          table.insert(choice, id)
        end
      end
      if #choice >= 3 * wanted or gates <= 1 then
        break
      end
      gates -= 1
    end
    -- (they are drawn again a tenth nearer one another until every one
    -- has a place: and in a galaxy so small that they are all but on top
    -- of one another, next door will do. In a galaxy with room for whole
    -- territories a distance is not given up at the first draw that
    -- fails, since a draw can paint itself into a corner where another
    -- would not: it is drawn Galaxy.HOME_DRAWS times before it is.)
    local apart = Galaxy.HOME_APART
    local attempt = 0
    local patience = if each >= Galaxy.TERRITORY then Galaxy.HOME_DRAWS else 1
    local failed = 0
    while #homes < wanted do
      attempt += 1
      local rng = Rng.For(galaxy.seed, 4407, attempt)
      local placed: { number } = { 1 }
      for index = 2, wanted do
        local fit: { number } = {}
        for _, id in choice do
          local clear = true
          for _, home in placed do
            if id == home or apart2(id, home) < apart ^ 2 or (apart >= 0.01 and table.find(systems[home].neighbors, id) ~= nil) then
              clear = false
              break
            end
          end
          if clear then
            table.insert(fit, id)
          end
        end
        if #fit == 0 then
          break
        end
        placed[index] = fit[Rng.Int(rng, #fit) + 1]
      end
      if #placed == wanted then
        homes = placed
      else
        failed += 1
        if failed >= patience then
          apart *= 0.9
          failed = 0
        end
      end
    end
  end

  -- Their space: whose[id] is which faction of the list holds a system.
  local whose: { number } = table.create(count, 0)
  local keys: { { number } }, ids: { { number } } = {}, {}
  for index = 1, wanted do
    keys[index], ids[index] = {}, {}
  end
  local function take(index: number, id: number)
    whose[id] = index
    for _, neighbor in systems[id].neighbors do
      if whose[neighbor] == 0 then
        heapPush(keys[index], ids[index], apart2(neighbor, homes[index]), neighbor)
      end
    end
  end
  for index, home in homes do
    whose[home] = index
  end
  for index, home in homes do
    take(index, home)
  end
  for _ = 2, each do
    for index = 1, wanted do
      local got = 0
      while #keys[index] > 0 do
        local _, id = heapPop(keys[index], ids[index])
        if whose[id] == 0 then
          got = id
          break
        end
      end
      if got == 0 then
        local least = math.huge
        for id = 1, count do
          if whose[id] == 0 and apart2(id, homes[index]) < least then
            got, least = id, apart2(id, homes[index])
          end
        end
      end
      if got ~= 0 then
        take(index, got)
      end
    end
  end

  -- Jumps to the nearest homeworld, whoever's.
  local hops: { number } = table.create(count, -1)
  local queue: { number } = {}
  for _, home in homes do
    hops[home] = 0
    table.insert(queue, home)
  end
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
  -- Jumps from a faction's homeworld through its own space, and how far
  -- that goes.
  local within: { number } = table.create(count, -1)
  local reach: { number } = table.create(wanted, 0)
  for index, home in homes do
    within[home] = 0
    queue, at = { home }, 1
    while at <= #queue do
      local id = queue[at]
      at += 1
      reach[index] = math.max(reach[index], within[id])
      for _, neighbor in systems[id].neighbors do
        if whose[neighbor] == index and within[neighbor] < 0 then
          within[neighbor] = within[id] + 1
          table.insert(queue, neighbor)
        end
      end
    end
  end

  for id, system in systems do
    local index = whose[id]
    local faction = if index > 0 then factions[index] else nil
    system.owner = if faction then faction.id else ""
    system.home = index > 0 and homes[index] == id
    system.hops = hops[id]
    -- (whose towers the stations are: the holder's, if they are people;
    -- else the people's whose homeworld is nearest on the map)
    if faction and faction.kind == "human" then
      system.nearest = faction.id
    else
      local best, least = 1, math.huge
      for other, home in homes do
        if factions[other].kind == "human" and apart2(id, home) < least then
          best, least = other, apart2(id, home)
        end
      end
      system.nearest = factions[best].id
    end
    if faction and faction.kind ~= "pirate" then
      -- (a system of theirs that their own space does not reach is as
      -- unsafe as held space gets)
      system.security = if within[id] < 0 then 0.3 else math.max(0.3, 1 - within[id] / (reach[index] + 1))
    else
      system.security = 0
    end
  end
end

-- Space nobody holds has nobody to name it: its systems go by their
-- survey marks (Names.Mark). The marks follow from the galaxy's seed
-- alone, and take nothing from what places the systems, so the map is
-- the one it would have been and the systems that keep names keep the
-- same ones. For a galaxy that is being made: a galaxy of a save keeps
-- the names it has.
function Galaxy.Marks(galaxy: Galaxy)
  local rng = Rng.For(galaxy.seed, 3301)
  local used: { [string]: boolean } = {}
  for _, system in galaxy.systems do
    if system.owner == "" then
      system.name = Names.UnusedMark(rng, used)
    end
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
  -- The systems reached and not yet settled, as a heap: the least cost
  -- at its head, and of those as cheap the lower-numbered. A system
  -- reached again more cheaply is put in again, and what is left of it
  -- further down is passed over when it comes up.
  local costs: { number }, ids: { number } = { 0 }, { from }
  local size = 1
  while size > 0 do
    local least, at = costs[1], ids[1]
    local lastCost, lastId = costs[size], ids[size]
    costs[size], ids[size] = nil, nil
    size -= 1
    if size > 0 then
      local hole = 1
      while true do
        local child = hole * 2
        if child > size then
          break
        end
        if child < size and (costs[child + 1] < costs[child] or (costs[child + 1] == costs[child] and ids[child + 1] < ids[child])) then
          child += 1
        end
        if costs[child] < lastCost or (costs[child] == lastCost and ids[child] < lastId) then
          costs[hole], ids[hole] = costs[child], ids[child]
          hole = child
        else
          break
        end
      end
      costs[hole], ids[hole] = lastCost, lastId
    end
    if not done[at] and least == cost[at] then
      if at == to then
        break
      end
      done[at] = true
      for _, neighbor in systems[at].neighbors do
        local reached = least + 1 + (if safest then RISK[Galaxy.Band(systems[neighbor].security)] else 0)
        if reached < cost[neighbor] then
          cost[neighbor] = reached
          before[neighbor] = at
          size += 1
          local hole = size
          while hole > 1 do
            local parent = hole // 2
            if reached < costs[parent] or (reached == costs[parent] and neighbor < ids[parent]) then
              costs[hole], ids[hole] = costs[parent], ids[parent]
              hole = parent
            else
              break
            end
          end
          costs[hole], ids[hole] = reached, neighbor
        end
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
  regions: { Region },      -- regions[id]
  constellations: { Constellation },
}

-- Systems to a region, and to a constellation, more or less.
Galaxy.REGION = 16
Galaxy.CONSTELLATION = 5

local REGION_KINDS = { "Reach", "Expanse", "Marches", "Deep", "Verge", "Span", "Drift", "Hollow" }

local SPACING = 4 -- light years between neighbours, roughly

-- How far a gate reaches, light years on the map: when a galaxy's gates
-- have been made, every one longer than this is taken out again. (The
-- project owner's, 2026-11-13: "a post-gen step of removing gates with
-- jumps further than x LY", and then "Lower the gate jump removal
-- length to 50 ly".)
-- The gates are a tree first, each system to the nearest made before
-- it, so the first few dozen systems of a big galaxy, which had nothing
-- near them when they were made, gate right across it: 625 light years
-- of an 800 light year map at ten thousand systems. Those few gates put
-- everything a few jumps from everything, however big the galaxy
-- (ten thousand systems were 38 jumps across, and homeworlds 440 light
-- years apart 12 jumps), which leaves a faction's space no depth and
-- its borders no meaning. Without them the same galaxy is 102 jumps
-- across and its homeworlds 51 apart; and one of five thousand is some
-- 70 across, with homeworlds 35 apart, where it was 30 and 12. Some
-- seventy gates of thirteen thousand go, and it is seldom that anything
-- is cut off by it (a gate or none is put in to join what is). A galaxy
-- narrower than this has no such gate to lose: one of forty systems is
-- 50 light years across, and its gates are as they were.
Galaxy.GATE_REACH = 50

-- Places on the map kept by the square each falls in, so that what is
-- nearest a place is found without looking at every other. The places
-- are numbered, and are where 'xs' and 'ys' say.
type Grid = {
  cell: number,
  xs: { number },
  ys: { number },
  squares: { [number]: { number } },
  -- (the squares that have anything in them lie within these)
  left: number,
  right: number,
  low: number,
  high: number,
}

local function gridOf(cell: number, xs: { number }, ys: { number }): Grid
  return { cell = cell, xs = xs, ys = ys, squares = {}, left = math.huge, right = -math.huge, low = math.huge, high = -math.huge }
end

local function gridAdd(grid: Grid, index: number)
  local sx, sy = math.floor(grid.xs[index] / grid.cell), math.floor(grid.ys[index] / grid.cell)
  local key = (sx + 1048576) * 2097152 + (sy + 1048576)
  local square = grid.squares[key]
  if square == nil then
    square = {}
    grid.squares[key] = square
  end
  table.insert(square, index)
  grid.left, grid.right = math.min(grid.left, sx), math.max(grid.right, sx)
  grid.low, grid.high = math.min(grid.low, sy), math.max(grid.high, sy)
end

-- The place in the grid nearest (x, y), and of those as near the
-- lower-numbered; but none that 'skip' says to pass over. Nil if
-- there is none. The squares are gone through in rings about the one
-- (x, y) is in, until nothing in a ring further out could be nearer.
local function gridNearest(grid: Grid, x: number, y: number, skip: ((number) -> boolean)?): number?
  local cell, xs, ys, squares = grid.cell, grid.xs, grid.ys, grid.squares
  local sx, sy = math.floor(x / cell), math.floor(y / cell)
  local rings = math.max(sx - grid.left, grid.right - sx, sy - grid.low, grid.high - sy)
  local best: number? = nil
  local least = math.huge
  for ring = 0, rings do
    -- (what is in this ring or beyond is at least a square less than
    -- the ring away)
    if ring > 1 and least < ((ring - 1) * cell) ^ 2 * (1 - 1e-9) then
      break
    end
    for dx = -ring, ring do
      local step = if dx == -ring or dx == ring then 1 else 2 * ring
      for dy = -ring, ring, math.max(1, step) do
        local square = squares[(sx + dx + 1048576) * 2097152 + (sy + dy + 1048576)]
        if square then
          for _, index in square do
            local d = (xs[index] - x) ^ 2 + (ys[index] - y) ^ 2
            if (d < least or (d == least and index < (best :: number))) and not (skip and skip(index)) then
              best, least = index, d
            end
          end
        end
      end
    end
  end
  return best
end

-- Whether anything in the grid is nearer (x, y) than 'within', which
-- is no more than a square of the grid.
local function gridCrowded(grid: Grid, x: number, y: number, within: number): boolean
  local cell, xs, ys, squares = grid.cell, grid.xs, grid.ys, grid.squares
  local sx, sy = math.floor(x / cell), math.floor(y / cell)
  for dx = -1, 1 do
    for dy = -1, 1 do
      local square = squares[(sx + dx + 1048576) * 2097152 + (sy + dy + 1048576)]
      if square then
        for _, index in square do
          if (xs[index] - x) ^ 2 + (ys[index] - y) ^ 2 < within ^ 2 then
            return true
          end
        end
      end
    end
  end
  return false
end

-- (with fewer places than this, looking at every one is as quick)
local GRIDDED = 16

-- Share 'members' (systems, by id) out into 'count' groups, each joined
-- up by gates among its own: the hearts of the groups are spread
-- evenly over the map, and every member goes to the heart fewest jumps
-- away through the members. A group that comes out with fewer
-- than 'least' goes in with a neighbour. Returns each member's group,
-- and how many groups there are in the end.
local function share(systems: { SystemNode }, members: { number }, count: number, least: number): ({ [number]: number }, number)
  local among: { [number]: boolean } = {}
  for _, id in members do
    among[id] = true
  end
  -- Where the hearts are: begin with members far apart on the map, then
  -- move each to the middle of the members nearest it, a few times over,
  -- so that the groups come out much of a size.
  local cx: { number }, cy: { number } = { systems[members[1]].x }, { systems[members[1]].y }
  -- (how near each member is to the nearest heart so far)
  local nearSoFar: { number } = table.create(#members, math.huge)
  while #cx < math.min(count, #members) do
    local newest = #cx
    local best, most = 0, -1
    for at, id in members do
      local near = math.min(nearSoFar[at], (systems[id].x - cx[newest]) ^ 2 + (systems[id].y - cy[newest]) ^ 2)
      nearSoFar[at] = near
      if near > most then
        best, most = id, near
      end
    end
    table.insert(cx, systems[best].x)
    table.insert(cy, systems[best].y)
  end
  -- (with many hearts or many members, the nearest is found on a grid:
  -- the answer is the same, and of those as near the lower-numbered)
  local gridded = #cx >= GRIDDED
  local left, right, low, high = math.huge, -math.huge, math.huge, -math.huge
  for _, id in members do
    left, right = math.min(left, systems[id].x), math.max(right, systems[id].x)
    low, high = math.min(low, systems[id].y), math.max(high, systems[id].y)
  end
  for _ = 1, 8 do
    local sx: { number }, sy: { number }, n: { number } = table.create(#cx, 0), table.create(#cx, 0), table.create(#cx, 0)
    local grid: Grid? = nil
    if gridded then
      local made = gridOf(math.max(1e-3, math.sqrt(math.max(1e-3, right - left) * math.max(1e-3, high - low) / #cx)), cx, cy)
      for index = 1, #cx do
        gridAdd(made, index)
      end
      grid = made
    end
    for _, id in members do
      local best, near = 1, math.huge
      if grid then
        best = gridNearest(grid, systems[id].x, systems[id].y) :: number
      else
        for index = 1, #cx do
          local d = (systems[id].x - cx[index]) ^ 2 + (systems[id].y - cy[index]) ^ 2
          if d < near then
            best, near = index, d
          end
        end
      end
      sx[best] += systems[id].x
      sy[best] += systems[id].y
      n[best] += 1
    end
    for index = 1, #cx do
      if n[index] > 0 then
        cx[index], cy[index] = sx[index] / n[index], sy[index] / n[index]
      end
    end
  end
  -- (a heart is the member nearest each of those places)
  local hearts: { number } = {}
  local taken: { [number]: boolean } = {}
  local memberGrid: Grid? = nil
  if gridded then
    local xs: { number }, ys: { number } = {}, {}
    for _, id in members do
      xs[id], ys[id] = systems[id].x, systems[id].y
    end
    local made = gridOf(2 * SPACING, xs, ys)
    for _, id in members do
      gridAdd(made, id)
    end
    memberGrid = made
  end
  local function isTaken(id: number): boolean
    return taken[id] == true
  end
  for index = 1, #cx do
    local best, near = 0, math.huge
    if memberGrid then
      best = gridNearest(memberGrid, cx[index], cy[index], isTaken) or 0
    else
      for _, id in members do
        local d = (systems[id].x - cx[index]) ^ 2 + (systems[id].y - cy[index]) ^ 2
        if not taken[id] and d < near then
          best, near = id, d
        end
      end
    end
    if best ~= 0 then
      taken[best] = true
      table.insert(hearts, best)
    end
  end
  local group: { [number]: number } = {}
  local queue: { number } = {}
  for index, heart in hearts do
    if group[heart] == nil then
      group[heart] = index
      table.insert(queue, heart)
    end
  end
  local at = 1
  while at <= #queue do
    local id = queue[at]
    at += 1
    for _, neighbor in systems[id].neighbors do
      if among[neighbor] and group[neighbor] == nil then
        group[neighbor] = group[id]
        table.insert(queue, neighbor)
      end
    end
  end
  -- (anything the gates among the members do not reach goes with the first)
  for _, id in members do
    group[id] = group[id] or 1
  end
  -- A group too small to be worth a name joins the group next to it:
  -- the smallest first, into the neighbour its lowest member touches.
  while true do
    local sizes: { number } = table.create(#hearts, 0)
    for _, id in members do
      sizes[group[id]] += 1
    end
    local small, fewest = 0, least
    for index, size in sizes do
      if size > 0 and size < fewest then
        small, fewest = index, size
      end
    end
    local into = 0
    if small ~= 0 then
      for _, id in members do
        if group[id] == small and into == 0 then
          for _, neighbor in systems[id].neighbors do
            if among[neighbor] and group[neighbor] ~= small and into == 0 then
              into = group[neighbor]
            end
          end
        end
      end
    end
    if into == 0 then
      break
    end
    for _, id in members do
      if group[id] == small then
        group[id] = into
      end
    end
  end
  -- Number the groups there are from 1, in the order of their first members.
  local renumbered: { [number]: number } = {}
  local groups = 0
  for _, id in members do
    if renumbered[group[id]] == nil then
      groups += 1
      renumbered[group[id]] = groups
    end
    group[id] = renumbered[group[id]]
  end
  return group, groups
end

-- Give the galaxy its regions and constellations, and every system its
-- place in them. They follow from the galaxy's seed and its gates, so
-- a galaxy always has the same.
function Galaxy.Regions(galaxy: Galaxy)
  local systems = galaxy.systems
  local rng = Rng.For(galaxy.seed, 2002)
  local used: { [string]: boolean } = {}
  local function name(): string
    return Names.Unused(rng, used)
  end
  local all: { number } = {}
  for id = 1, #systems do
    all[id] = id
  end
  local inRegion, regions = share(systems, all, math.max(1, math.floor(#systems / Galaxy.REGION + 0.5)), Galaxy.REGION // 3)
  galaxy.regions, galaxy.constellations = {}, {}
  local membersOf: { { number } } = {}
  for region = 1, regions do
    membersOf[region] = {}
  end
  for id = 1, #systems do
    table.insert(membersOf[inRegion[id]], id)
  end
  for region = 1, regions do
    galaxy.regions[region] = { id = region, name = `{name()} {REGION_KINDS[Rng.Int(rng, #REGION_KINDS) + 1]}` }
    local members = membersOf[region]
    if #members > 0 then
      local inConstellation, count = share(systems, members, math.max(1, math.floor(#members / Galaxy.CONSTELLATION + 0.5)), 2)
      local first = #galaxy.constellations
      for index = 1, count do
        table.insert(galaxy.constellations, { id = first + index, name = name(), region = region })
      end
      for _, id in members do
        systems[id].region = region
        systems[id].constellation = first + inConstellation[id]
      end
    end
  end
end

-- How far out of the plane of the map a system can lie, as a share of
-- how far the map is across; and the least and the most that is, light
-- years, whatever the size of the galaxy.
Galaxy.RELIEF = 0.06
Galaxy.RELIEF_LEAST, Galaxy.RELIEF_MOST = 2, 25

-- Give every system its height over the plane of the map: a gentle
-- relief over the whole of it, so that systems near each other lie at
-- much the same height, and a little of each system's own. It follows
-- from the galaxy's seed and from where each system is on the map, and
-- from nothing else, so a galaxy of a save from before there were
-- heights is given the ones it would have had.
function Galaxy.Heights(galaxy: Galaxy)
  local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
  for _, system in galaxy.systems do
    minX, maxX = math.min(minX, system.x), math.max(maxX, system.x)
    minY, maxY = math.min(minY, system.y), math.max(maxY, system.y)
  end
  local span = math.max(1e-3, maxX - minX, maxY - minY)
  local high = math.clamp(Galaxy.RELIEF * span, Galaxy.RELIEF_LEAST, Galaxy.RELIEF_MOST)
  local rng = Rng.For(galaxy.seed, 7411)
  local a, b, c = Rng.Float(rng, 0, 2 * math.pi), Rng.Float(rng, 0, 2 * math.pi), Rng.Float(rng, 0, 2 * math.pi)
  for _, system in galaxy.systems do
    local u, v = (system.x - minX) / span * 2 * math.pi, (system.y - minY) / span * 2 * math.pi
    local wave = 0.6 * math.sin(1.3 * u + a) * math.cos(0.9 * v + b) + 0.4 * math.sin(2.1 * (u + v) + c)
    local own = Rng.Float(Rng.For(galaxy.seed, system.id, 7412), -0.15, 0.15)
    -- (to a hundredth of a light year: nobody quotes it finer)
    system.z = math.floor(high * (wave + own) * 100 + 0.5) / 100
  end
end

-- How far apart two systems are, light years: through space, and not
-- along the gates.
function Galaxy.Apart(galaxy: Galaxy, from: number, to: number): number
  local a, b = galaxy.systems[from], galaxy.systems[to]
  return if a and b then math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) else math.huge
end

function Galaxy.Describe(seed: number, count: number): Galaxy
  assert(count >= 1 and count % 1 == 0, "a galaxy needs a whole number of systems")
  local rng = Rng.For(seed, 1001)
  local systems: { SystemNode } = {}
  local used: { [string]: boolean } = {}
  local radius = SPACING * math.sqrt(count)

  local xs: { number }, ys: { number } = table.create(count, 0), table.create(count, 0)
  -- (the systems whose names had to be longer ones, the plain names
  -- having run out when they were made)
  local drawnOut: { boolean } = table.create(count, false)
  local placed = gridOf(2 * SPACING, xs, ys)
  for id = 1, count do
    -- A place not too close to any earlier system.
    local x, y = 0, 0
    for _ = 1, 200 do
      local angle = Rng.Float(rng, 0, 2 * math.pi)
      local r = radius * math.sqrt(Rng.Next(rng))
      x, y = r * math.cos(angle), r * math.sin(angle)
      if not gridCrowded(placed, x, y, SPACING * 0.6) then
        break
      end
    end
    xs[id], ys[id] = x, y
    gridAdd(placed, id)
    local name, long = Names.Unused(rng, used)
    drawnOut[id] = long
    systems[id] = { id = id, name = name, x = x, y = y, z = 0, neighbors = {}, owner = "", nearest = "", home = false, hops = 0,
      security = 1, region = 1, constellation = 1 }
  end

  local function link(a: number, b: number)
    if a ~= b and not table.find(systems[a].neighbors, b) then
      table.insert(systems[a].neighbors, b)
      table.insert(systems[b].neighbors, a)
    end
  end

  -- A tree first, so every system can be reached: each system gates to
  -- the nearest one made before it. Then some shortcuts: to the nearest
  -- it has no gate to.
  local earlier = gridOf(2 * SPACING, xs, ys)
  gridAdd(earlier, 1)
  for id = 2, count do
    link(id, gridNearest(earlier, xs[id], ys[id]) :: number)
    gridAdd(earlier, id)
  end
  for id = 1, count do
    if count > 3 and Rng.Chance(rng, 0.35) then
      local gated = systems[id].neighbors
      local other = gridNearest(earlier, xs[id], ys[id], function(other: number): boolean
        return other == id or table.find(gated, other) ~= nil
      end)
      if other then
        link(id, other)
      end
    end
  end
  -- No gate reaches farther than Galaxy.GATE_REACH: the ones that do
  -- are taken out. What that cuts off from the rest (seldom anything:
  -- the long gates are few, and the shortcuts go round most) is joined
  -- to it again by the shortest gate that does it, the smallest piece
  -- first.
  local reach = Galaxy.GATE_REACH
  local cut = false
  local first = 0
  for id, system in systems do
    for at = #system.neighbors, 1, -1 do
      local other = system.neighbors[at]
      if (xs[id] - xs[other]) ^ 2 + (ys[id] - ys[other]) ^ 2 > reach * reach then
        table.remove(system.neighbors, at)
        cut = true
        first += if id == 1 then 1 else 0
      end
    end
  end
  -- (The first system is where a pilot starts and is a homeworld
  -- whatever gates it has (Galaxy.Claim), and a homeworld is to have
  -- its five: being the first made, it is the one that loses most. So
  -- for every gate it lost it has one to the nearest system it has
  -- none to, until it has five again.)
  for _ = 1, first do
    local gated = systems[1].neighbors
    if #gated >= Galaxy.HOME_GATES then
      break
    end
    local other = gridNearest(earlier, xs[1], ys[1], function(other: number): boolean
      return other == 1 or table.find(gated, other) ~= nil
    end)
    if other == nil then
      break
    end
    link(1, other)
  end
  if cut then
    -- (the pieces: which each system is of, and the systems of each)
    local piece: { number } = table.create(count, 0)
    local members: { { number } } = {}
    for id = 1, count do
      if piece[id] == 0 then
        local queue = { id }
        piece[id] = #members + 1
        local head = 1
        while head <= #queue do
          for _, next in systems[queue[head]].neighbors do
            if piece[next] == 0 then
              piece[next] = #members + 1
              table.insert(queue, next)
            end
          end
          head += 1
        end
        table.insert(members, queue)
      end
    end
    for _ = 2, #members do
      -- The smallest piece there is, the earliest of those as small.
      local least = 0
      for index, of in members do
        if #of > 0 and (least == 0 or #of < #members[least]) then
          least = index
        end
      end
      -- Its system nearest a system of another piece, and that one.
      local from, to, gap = 0, 0, math.huge
      for _, id in members[least] do
        local other = gridNearest(earlier, xs[id], ys[id], function(other: number): boolean
          return piece[other] == least
        end) :: number
        local d = (xs[id] - xs[other]) ^ 2 + (ys[id] - ys[other]) ^ 2
        if d < gap or (d == gap and id < from) then
          from, to, gap = id, other, d
        end
      end
      link(from, to)
      local into = piece[to]
      for _, id in members[least] do
        piece[id] = into
        table.insert(members[into], id)
      end
      members[least] = {}
    end
  end
  for _, system in systems do
    table.sort(system.neighbors)
  end

  local galaxy: Galaxy = { seed = seed, systems = systems, regions = {}, constellations = {} }
  Galaxy.Heights(galaxy)
  Galaxy.Claim(galaxy)
  Galaxy.Marks(galaxy)
  -- A galaxy of thousands ran out of plain names as it was made, long
  -- before anybody knew which systems would be held. Most are not, and
  -- have given their names up for marks: a held system that was left
  -- with a longer name has a plain one of those now.
  local plain: { [string]: boolean } = {}
  for _, system in systems do
    plain[system.name] = true
  end
  local renaming = Rng.For(seed, 3302)
  for id, system in systems do
    if drawnOut[id] and system.owner ~= "" then
      system.name = Names.Unused(renaming, plain)
    end
  end
  Galaxy.Regions(galaxy)
  return galaxy
end

return Galaxy
