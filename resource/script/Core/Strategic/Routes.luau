--!strict
-- Distances and routes between systems, in jumps.
--
-- Worked out once for a galaxy and kept here, not in the state: they
-- follow from the gates alone, so a loaded game works them out again and
-- gets the same answer.

local Galaxy = require("@lt/Core/Describe/Galaxy")

local Routes = {}

export type Routes = {
  hops: { { number } },   -- hops[a][b]: jumps from a to b
  next: { { number } },   -- next[a][b]: the system to jump to from a, bound for b (a itself when a == b)
}

local cache: { [Galaxy.Galaxy]: Routes } = setmetatable({}, { __mode = "k" }) :: any

function Routes.For(galaxy: Galaxy.Galaxy): Routes
  local found = cache[galaxy]
  if found then
    return found
  end
  local count = #galaxy.systems
  local hops: { { number } } = table.create(count)
  local next: { { number } } = table.create(count)
  for a = 1, count do
    hops[a] = table.create(count, -1)
    next[a] = table.create(count, 0)
  end
  -- From each destination outward: the system a search reached 'a' from
  -- is the one to jump to from 'a'. Neighbours are in id order, so a tie
  -- between routes always falls the same way.
  local queue: { number } = table.create(count, 0)
  for dest = 1, count do
    hops[dest][dest] = 0
    next[dest][dest] = dest
    queue[1] = dest
    local head, tail = 1, 1
    while head <= tail do
      local at = queue[head]
      head += 1
      for _, a in galaxy.systems[at].neighbors do
        if hops[a][dest] < 0 then
          hops[a][dest] = hops[at][dest] + 1
          next[a][dest] = at
          tail += 1
          queue[tail] = a
        end
      end
    end
  end
  local routes = { hops = hops, next = next }
  cache[galaxy] = routes
  return routes
end

return Routes
