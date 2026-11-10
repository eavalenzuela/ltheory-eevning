--!strict
-- Who has what: the galaxy as the economy sees it.
--
-- Describe/Galaxy says where the systems are and which gates join them.
-- The atlas adds what makes them different: who owns each, how safe it
-- is, how many people live there, what can be dug up, and what is made.
-- From that it builds the galaxy's economy (Strategic/Economy): a node a
-- system, an edge a gate.
--
-- Ownership here is fixed: eight powers, each grown outward from a
-- homeworld, with the far reaches unclaimed. (Wars that move the
-- borders are the faction layer's business.)
--
-- Industry is sized, not rolled: the atlas works out how much of
-- everything the galaxy's people use, and how much of every stage that
-- takes, and hands out that much capacity plus some slack. Which systems
-- get it is rolled. So the galaxy as a whole can always feed itself, and
-- no single system can: that difference is the trade.

local Economy = require("@lt/Core/Strategic/Economy")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Goods = require("@lt/Core/Data/Goods")
local Rng = require("@lt/Core/Kernel/Rng")

local Atlas = {}

export type SystemInfo = {
  id: number,
  owner: number,        -- faction id; 0 if unclaimed
  hops: number,         -- jumps to the nearest homeworld
  security: number,     -- 1 at a homeworld, falling to 0 in unclaimed space
  population: number,
  home: boolean,
  hub: boolean,
  resources: { [string]: number },  -- richness of ore, rare, ice, gas, life, wrecks; 0 for none
  taste: { number },    -- by class index: what its people use, relative to normal
  facilities: { { recipe: number, capacity: number } },
}

export type Faction = { id: number, name: string, home: number }

export type Lane = { a: number, b: number, conductance: number, cost: number, border: boolean }

export type Atlas = {
  seed: number,
  factions: { Faction },
  systems: { SystemInfo },    -- systems[id], as in the galaxy
  lanes: { Lane },            -- one per gate pair, a < b, in order
  population: number,         -- total
}

-- Tuning. Each of these is watched by a threshold in Tool/EconProbe.
Atlas.FACTIONS = 8
-- The share of systems that some power claims.
Atlas.CLAIMED = 0.78
-- Capacity handed out over what the galaxy needs.
Atlas.SLACK = 1.35
-- What a lane can carry: credits an hour of each class, per unit of
-- price gap beyond its cost, per unit of population at its ends.
Atlas.HAUL = 12
-- A lane's cost, as a share of the goods' price: a jump, a border, and
-- the risk of lawless space.
Atlas.COST_JUMP = 0.02
Atlas.COST_BORDER = 0.04
Atlas.COST_RISK = 0.06
-- How far mining follows people: a system's share of what is dug goes
-- with its richness times its population to this power. At 1 every
-- system digs in proportion to its people; lower, and the thinly peopled
-- frontier digs more than its share and has to ship it in.
Atlas.DIG = 0.5
-- Industry clusters: this share of every step's capacity stands where
-- its inputs are made, in proportion to how much of them (by value) is
-- made there, so that a chain's stages are neighbours. The rest goes by
-- population. (Refining follows its raw material more closely still:
-- ore is the costliest thing to haul.)
Atlas.AT_SOURCE = 0.5
Atlas.REFINED_AT_SOURCE = 0.7
-- The smallest share of a step's capacity a system is given. Kept low
-- on purpose: many small works near their customers save more haulage
-- than they cost to simulate (at 0.001 people are 2% worse supplied).
Atlas.SLIVER = 0.0002
-- How safe the outermost claimed systems are. Unclaimed space is at 0.
Atlas.SECURITY_FLOOR = 0.25
-- How readily a homeworld's anchor trades: shares of its own hourly
-- throughput, per unit of price gap from normal.
Atlas.ANCHOR = 1.5
-- (For experiments: let the anchors trade raw materials and parts too.)
Atlas.ANCHOR_ALL = false

local FACTION_NAMES = { "Vessari Compact", "Talmar League", "Orun Hegemony", "Sable Concord", "Kethri Union",
  "Dominion of Ash", "Meridian Trust", "Halcyon Reach" }

-- Jumps from 'source' to every system.
local function hopsFrom(galaxy: Galaxy.Galaxy, source: number): { number }
  local dist: { number } = table.create(#galaxy.systems, -1)
  dist[source] = 0
  local queue = { source }
  local head = 1
  while head <= #queue do
    local a = queue[head]
    head += 1
    for _, b in galaxy.systems[a].neighbors do
      if dist[b] < 0 then
        dist[b] = dist[a] + 1
        table.insert(queue, b)
      end
    end
  end
  return dist
end

local RESOURCES: { { any } } = {
  -- name, chance a system has it, least and most richness
  { "ore", 0.65, 0.3, 1.5 }, { "rare", 0.30, 0.3, 1.5 }, { "ice", 0.35, 0.3, 1.5 }, { "gas", 0.35, 0.3, 1.5 },
  { "life", 0.30, 0.3, 1.5 },
}

-- The chance a system hosts a step, by the tier of what the step makes.
-- (Battleship yards are at homeworlds and hubs only.)
local HOSTS: { [string]: number } = {
  refined = 0.14, part = 0.25, consumer = 0.25, military = 0.18, hull = 0.10, construction = 0.12,
}


function Atlas.Describe(galaxy: Galaxy.Galaxy, seed: number): Atlas
  local count = #galaxy.systems
  local rng = Rng.For(seed, 2001)
  local factionCount = math.max(1, math.min(Atlas.FACTIONS, count // 12))

  -- Homeworlds, spread out: the first at random, each next one as far
  -- as can be from those already chosen.
  local homes: { number } = { Rng.Int(rng, count) + 1 }
  local nearest = hopsFrom(galaxy, homes[1])
  local owner: { number } = table.create(count, 1)
  while #homes < factionCount do
    local best, bestHops = 1, -1
    for id = 1, count do
      if nearest[id] > bestHops then
        best, bestHops = id, nearest[id]
      end
    end
    table.insert(homes, best)
    for id, hops in hopsFrom(galaxy, best) do
      if hops < nearest[id] then
        nearest[id] = hops
        owner[id] = #homes
      end
    end
  end

  -- The nearest systems to any homeworld are claimed; the rest are not.
  local sorted = table.clone(nearest)
  table.sort(sorted)
  local reach = sorted[math.max(1, math.floor(count * Atlas.CLAIMED))]

  local factions: { Faction } = {}
  for id, home in homes do
    table.insert(factions, { id = id, name = FACTION_NAMES[id], home = home })
  end

  local systems: { SystemInfo } = {}
  local classes = Goods.list
  for id = 1, count do
    local hops = nearest[id]
    local claimed = hops <= reach
    local home = hops == 0
    local security = if claimed
      then Atlas.SECURITY_FLOOR + (1 - Atlas.SECURITY_FLOOR) * math.clamp(1 - hops / math.max(1, reach), 0, 1)
      else 0
    local population = if home then 40
      elseif claimed then math.max(0.4, 12 * 0.72 ^ hops * Rng.Float(rng, 0.5, 1.5))
      else Rng.Float(rng, 0.2, 1.0)
    local resources: { [string]: number } = {}
    for _, r in RESOURCES do
      resources[r[1]] = if Rng.Chance(rng, r[2]) then Rng.Float(rng, r[3], r[4]) else 0
    end
    if home then
      resources.life = 1.5
      resources.ore = math.max(resources.ore, 1)
    end
    -- Ships are lost wherever pilots fly, and more where nobody keeps order.
    resources.wrecks = 1.5 - security
    -- People in safe space buy more comforts; people on the frontier
    -- lose more ships.
    local taste: { number } = {}
    for g, class in classes do
      taste[g] = if class.tier == "military" or class.tier == "hull" then 0.6 + 1.2 * (1 - security)
        elseif class.tier == "consumer" then 0.8 + 0.4 * security
        else 1
    end
    systems[id] = {
      id = id, owner = if claimed then owner[id] else 0, hops = hops, security = security, population = population,
      home = home, hub = false, resources = resources, taste = taste, facilities = {},
    }
  end

  -- Two hubs a power: its best connected systems a few jumps from home.
  for _, faction in factions do
    for _ = 1, 2 do
      local best, bestScore = 0, -1
      for id = 1, count do
        local info = systems[id]
        if info.owner == faction.id and not info.home and not info.hub and info.hops >= 2 then
          local score = #galaxy.systems[id].neighbors * 10 - info.hops
          if score > bestScore then
            best, bestScore = id, score
          end
        end
      end
      if best ~= 0 then
        systems[best].hub = true
        systems[best].population = math.max(10, systems[best].population * 3)
      end
    end
  end

  -- What the galaxy uses an hour, and so what every step must make.
  local population = 0
  local used: { number } = table.create(#classes, 0)
  for _, info in systems do
    population += info.population
    for g, class in classes do
      used[g] += info.population * class.need * info.taste[g]
    end
  end
  local _, runs = Goods.Required(used)

  -- Hand each step's capacity out among the systems that host it. What
  -- each system makes of each class is kept (units an hour at capacity,
  -- by class index), so that the next stage can stand beside it.
  local makes: { { number } } = table.create(count)
  for id = 1, count do
    makes[id] = table.create(#classes, 0)
  end
  for at, step in Goods.steps do
    local madeIndex = Goods.Index(step.makes)
    local made = classes[madeIndex]
    local capacity = runs[at] * Atlas.SLACK
    local weights: { number } = table.create(count, 0)
    local total = 0
    -- The value of this step's inputs that each system makes itself.
    local source: { number } = table.create(count, 0)
    local sourceTotal = 0
    for id = 1, count do
      local info = systems[id]
      local weight = 0
      if made.tier == "raw" then
        local richness = info.resources[made.resource] or 0
        if made.resource == "wrecks" then
          weight = richness * info.population
        elseif richness > 0 then
          weight = richness * (0.3 + info.population ^ Atlas.DIG)
        end
      elseif step.makes == "hulls.battleship" then
        weight = if info.home or info.hub then info.population else 0
      else
        -- in class order, so the sum is the same every time
        for g, class in classes do
          local amount = step.inputs[class.id]
          if amount then
            source[id] += math.min(makes[id][g], 1e30) * class.par
          end
        end
        sourceTotal += source[id]
        if info.home or Rng.Chance(rng, HOSTS[made.tier]) then
          weight = info.population ^ 1.1
        end
      end
      weights[id] = weight
      total += weight
    end
    assert(total > 0, `no system can host {step.id}`)
    local atSource = if sourceTotal <= 0 or step.makes == "hulls.battleship" then 0
      elseif made.tier == "refined" then Atlas.REFINED_AT_SOURCE
      else Atlas.AT_SOURCE
    -- A sliver of a factory is no factory: shares under SLIVER are
    -- dropped and the rest scaled up to make the whole.
    local shares: { number } = table.create(count, 0)
    local kept = 0
    for id = 1, count do
      local share = (1 - atSource) * weights[id] / total
      if atSource > 0 then
        share += atSource * source[id] / sourceTotal
      end
      if share >= Atlas.SLIVER then
        shares[id] = share
        kept += share
      end
    end
    assert(kept > 0, `nothing but slivers of {step.id}`)
    for id = 1, count do
      if shares[id] > 0 then
        local here = capacity * shares[id] / kept
        table.insert(systems[id].facilities, { recipe = at, capacity = here })
        makes[id][madeIndex] += here
      end
    end
  end

  -- A lane a gate.
  local lanes: { Lane } = {}
  for a = 1, count do
    for _, b in galaxy.systems[a].neighbors do
      if a < b then
        local sa, sb = systems[a], systems[b]
        local border = sa.owner ~= sb.owner
        table.insert(lanes, {
          a = a, b = b, border = border,
          conductance = Atlas.HAUL * Goods.SCALE * (1 + (sa.population + sb.population) / 2),
          cost = Atlas.COST_JUMP + (if border then Atlas.COST_BORDER else 0)
            + Atlas.COST_RISK * (1 - math.min(sa.security, sb.security)),
        })
      end
    end
  end

  return { seed = seed, factions = factions, systems = systems, lanes = lanes, population = population }
end

-- The galaxy's economy, every stock at its normal level.
function Atlas.Economy(galaxy: Galaxy.Galaxy, atlas: Atlas): Economy.Economy
  local econ = Economy.New(Goods.Classes(), Goods.Recipes())
  for id, info in atlas.systems do
    local node = Economy.AddNode(econ, galaxy.systems[id].name, info.population, info.facilities, info.taste)
    assert(node == id)
    -- A homeworld's own vast economy, which is not otherwise simulated,
    -- sells and buys the things people use near their normal prices.
    -- Raw materials and parts are not among them: industry has to be
    -- fed from space.
    if info.home then
      local n = econ.nodes[node]
      for g, class in econ.classes do
        if class.need > 0 or Atlas.ANCHOR_ALL then
          n.anchor[g] = Atlas.ANCHOR * n.target[g] / class.cover
        end
      end
    end
  end
  for _, lane in atlas.lanes do
    Economy.AddEdge(econ, lane.a, lane.b, lane.conductance, lane.cost)
  end
  return econ
end

return Atlas
