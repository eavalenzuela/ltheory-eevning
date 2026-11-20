--!strict
-- PointDefence: a point defence turret against missiles and drones (the
-- owner's rulings, 2026-11-19). A small projectile turret in a turret
-- hardpoint; switched on, it engages by itself, with no lock:
--
--   - it shoots at any enemy missile within its reach, the one aimed at
--     its own ship or at another's, so that it screens its friends;
--   - it has to swing to each one at its traverse, and fires all the
--     while it swings, so that it wastes a great many rounds, and a
--     salvo of many can get through it;
--   - each round is rolled by the gunnery rules (Tactical/Gunnery), the
--     missile a small and quick target, and a missile is downed by so
--     many hits (PointDefence.HITS);
--   - with no missile in reach it shoots at the enemy's drones;
--   - it holds 120 rounds and reloads from the hold.
--
-- A missile in flight is where it has flown (PointDefence.At; one from
-- an older save, where its path would have brought it):
-- a plain one on the straight way from where it was fired to its target
-- as its target is now; a vertical launch's straight up for a quarter of
-- its flight and then down on its target, faster and faster; a swarm's
-- the straight way, jinking across it as it goes. Each second of the game
-- a turret has that second to spend: swinging, then firing, then
-- swinging to the next. (Every figure here is mine.)
local Gunnery = require("@lt/Core/Tactical/Gunnery")
local Modules = require("@lt/Core/Data/Modules")
local Rng = require("@lt/Core/Kernel/Rng")
local State = require("@lt/Core/Kernel/State")

export type Event = { [string]: any }
export type Hit = { target: number, by: number, damage: { number } }

local PointDefence = {}

-- How many hits down a missile, by the size of what it is (1 light, 2
-- heavy, 3 cruise, 4 siege), and a swarm's and a vertical launch's
-- whatever their size (the owner's: a vertical launch's takes two).
PointDefence.HITS = { 1, 2, 4, 8 }
PointDefence.SWARM_HITS = 1
PointDefence.VERTICAL_HITS = 2
-- How big a missile is to a gun's tracking (m), likewise.
PointDefence.SIGNATURE = { 10, 15, 25, 40 }
PointDefence.SWARM_SIGNATURE = 8
PointDefence.VERTICAL_SIGNATURE = 15
-- How hard a swarm's missile jinks: so much of its speed across its way.
PointDefence.JINK = 0.4
-- How much easier to hit, each round, a missile is, by the hits it takes
-- to down: a bigger one is larger and steadier. Set so that one turret
-- stops about half of what a lone launcher of each size throws at it
-- (the owner's "mostly misses", 2026-11-19: Tool/pdsmeasure's runs).
PointDefence.EASIER = { [1] = 1, [2] = 3.2, [4] = 5.6, [8] = 8 } :: { [number]: number }

local function owner(state: State.State, id: number): string?
  local drone = state.drones[id]
  if drone then
    id = drone.owner
  end
  local ship = state.ships[id]
  return if ship then ship.owner else nil
end

-- Whether two owners are of one side: the same, or the pilot's and a
-- member's of the pilot's corporation (as Tactical/Jumping has it).
local function friendly(one: string, other: string): boolean
  local function ours(who: string): boolean
    return who == "player" or who == "member"
  end
  return one == other or (ours(one) and ours(other))
end

-- Where a missile is at 'time', and how fast it is going (m/s, each
-- way); nil before it has left its cell, or with its target gone.
function PointDefence.At(state: State.State, missile: State.Missile, time: number): (number?, number, number, number, number, number)
  -- (one in flight of itself: where it was last, carried on as it was going, Tactical/Combat)
  if missile.x and missile.at then
    if time < (missile.born or 0) then
      return nil, 0, 0, 0, 0, 0
    end
    local vx, vy, vz = missile.vx or 0, missile.vy or 0, missile.vz or 0
    local since = time - math.max(missile.at :: number, missile.born or 0)
    return (missile.x :: number) + vx * since, (missile.y :: number) + vy * since, (missile.z :: number) + vz * since, vx, vy, vz
  end
  local target = state.balls[missile.to]
  local born = missile.born or (missile.impact - 1)
  if target == nil or missile.lx == nil or time < born then
    return nil, 0, 0, 0, 0, 0
  end
  local lx, ly, lz = missile.lx :: number, missile.ly :: number, missile.lz :: number
  -- (it ends at its target's surface, on the side it comes from: Tactical/Combat's flight is to the surface)
  local ex, ey, ez = target.x - lx, target.y - ly, target.z - lz
  local length = math.sqrt(ex * ex + ey * ey + ez * ez)
  local short = if length > 0 then math.max(0, 1 - target.radius / length) else 1
  local tx, ty, tz = lx + ex * short, ly + ey * short, lz + ez * short
  local function at(t: number): (number, number, number)
    local f = math.clamp((t - born) / math.max(missile.impact - born, 1e-6), 0, 1)
    if missile.path == "arc" then
      local dx, dy, dz = tx - lx, ty - ly, tz - lz
      local high = 0.25 * math.sqrt(dx * dx + dy * dy + dz * dz)
      if f < 0.25 then
        return lx, ly + high * f / 0.25, lz
      end
      local g = ((f - 0.25) / 0.75) ^ 2
      return lx + dx * g, ly + high + (dy - high) * g, lz + dz * g
    end
    return lx + (tx - lx) * f, ly + (ty - ly) * f, lz + (tz - lz) * f
  end
  local x, y, z = at(time)
  local x2, y2, z2 = at(time + 0.1)
  return x, y, z, (x2 - x) * 10, (y2 - y) * 10, (z2 - z) * 10
end

-- How many hits down a missile, and how big it is to a gun.
local function toughness(missile: State.Missile): (number, number)
  local charge = Modules.chargeById[missile.charge]
  local size = if charge then charge.size else 1
  if missile.path == "arc" then
    return PointDefence.VERTICAL_HITS, PointDefence.VERTICAL_SIGNATURE
  elseif missile.path == "zig" then
    return PointDefence.SWARM_HITS, PointDefence.SWARM_SIGNATURE
  end
  return PointDefence.HITS[size] or 8, PointDefence.SIGNATURE[size] or 40
end

-- One second of a point defence turret's work: whatever it swings to and
-- shoots at in that second. Its rounds are taken from what is loaded;
-- what it downs is taken out of the state's missiles; what it does to a
-- drone goes on 'hits'. ('enemy': who it counts an enemy, by the ship
-- that fired a missile or by a drone, for a turret that is not a ship's
-- own: a citadel's, Tactical/CitadelGuns. Nil: whoever is not of its
-- ship's side. 'mount': which of its turrets it is, said in its events.)
function PointDefence.Cycle(state: State.State, ball: State.Ball, item: State.Item, running: State.Running,
  pds: Modules.PointDefence, time: number, hits: { Hit }, events: { Event }, enemy: ((id: number) -> boolean)?, mount: number?)
  local mine = owner(state, ball.id) or ""
  if (enemy == nil and mine == "") or item.charge == "" or item.rounds <= 0 then
    return
  end
  local function against(id: number): boolean
    if enemy then
      return enemy(id)
    end
    local whose = owner(state, id)
    return whose ~= nil and not friendly(whose, mine)
  end
  local reach = pds.optimal + pds.falloff
  local rng = Rng.For(state.historySeed, state.tick, ball.id, item.id, 73)
  local budget = 1
  local ax, ay, az = running.ax or 0, running.ay or 0, running.az or 1

  -- (the enemy's missiles on its grid that are in the air this second)
  local pool: { State.Missile } = {}
  for _, missile in state.missiles do
    local from = state.balls[missile.from]
    -- (a plasma torpedo is past shooting down: Data/Modules' 'path')
    if against(missile.from) and from and from.system == ball.system and from.grid == ball.grid
      and missile.impact > time and (missile.born or time) < time + 1 and missile.path ~= "plasma" then
      table.insert(pool, missile)
    end
  end

  local downed: { [State.Missile]: boolean } = {}
  local fired = 0
  local engaged = false
  while budget > 1e-6 and item.rounds > fired and #pool > 0 do
    -- The one in reach now that it can swing to soonest (the second so far: what has landed is past shooting
    -- at, and what has not left its cell, or come in reach, is not yet there to shoot at).
    local clock = time + (1 - budget)
    local best, bestAngle = 0, math.huge
    local bx, by, bz, bvx, bvy, bvz, bdistance = 0, 0, 0, 0, 0, 0, 0
    for index = #pool, 1, -1 do
      local missile = pool[index]
      if missile.impact <= clock then
        table.remove(pool, index)
        best = if best > index then best - 1 else best
      else
        local x, y, z, vx, vy, vz = PointDefence.At(state, missile, clock)
        if x then
          local dx, dy, dz = x - ball.x, (y :: number) - ball.y, (z :: number) - ball.z
          local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
          if distance <= reach then
            local angle = math.acos(math.clamp((ax * dx + ay * dy + az * dz) / math.max(distance, 1e-6), -1, 1))
            if angle < bestAngle then
              best, bestAngle = index, angle
              bx, by, bz, bvx, bvy, bvz, bdistance = x, y :: number, z :: number, vx, vy, vz, distance
            end
          end
        end
      end
    end
    if best == 0 then
      -- (nothing in reach just now: it waits, and fires nothing)
      budget -= 0.1
      continue
    end
    engaged = true
    local missile = pool[best]
    local length = math.max(bdistance, 1e-6)
    local dx, dy, dz = (bx - ball.x) / length, (by - ball.y) / length, (bz - ball.z) / length
    -- Swinging to it, firing all the while.
    local swing = bestAngle / pds.traverse
    if swing >= budget then
      local part = budget / swing
      ax, ay, az = ax + (dx - ax) * part, ay + (dy - ay) * part, az + (dz - az) * part
      local norm = math.max(math.sqrt(ax * ax + ay * ay + az * az), 1e-6)
      ax, ay, az = ax / norm, ay / norm, az / norm
      fired += math.floor(budget * pds.rate)
      budget = 0
      break
    end
    fired += math.floor(swing * pds.rate)
    budget -= swing
    ax, ay, az = dx, dy, dz
    -- Then on it, round by round, until it is down, it has landed, or the second is spent.
    local need, signature = toughness(missile)
    local rvx, rvy, rvz = bvx - ball.vx, bvy - ball.vy, bvz - ball.vz
    local along = rvx * dx + rvy * dy + rvz * dz
    local across = math.sqrt(math.max(0, rvx * rvx + rvy * rvy + rvz * rvz - along * along))
    if missile.path == "zig" then
      across += PointDefence.JINK * math.sqrt(bvx ^ 2 + bvy ^ 2 + bvz ^ 2)
    end
    -- (most rounds go wide of a missile; a bigger one, steadier and larger, is the easier)
    local steadier = PointDefence.EASIER[need] or need
    local chance = math.min(0.95, pds.accuracy * steadier
      * Gunnery.HitChance(across / length, pds.tracking, signature, bdistance, pds.optimal, pds.falloff))
    local struck, rounds = missile.struck or 0, 0
    while budget > 1e-6 and item.rounds > fired and struck < need and time + (1 - budget) < missile.impact do
      fired += 1
      rounds += 1
      budget -= 1 / pds.rate
      if Rng.Next(rng) < chance then
        struck += 1
      end
    end
    missile.struck = struck
    local down = struck >= need
    if down then
      downed[missile] = true
    end
    table.remove(pool, best)
    table.insert(events, { kind = "PointDefence", from = ball.id, item = item.id, missile = missile.id,
      rounds = rounds, down = down, x = bx, y = by, z = bz, mount = mount })
  end

  -- Nothing in the air: the enemy's drones.
  if not engaged and fired == 0 then
    local best: State.Ball? = nil
    local bestDistance = reach
    for id in state.drones do
      local other = state.balls[id]
      if other and against(id) and other.system == ball.system and other.grid == ball.grid then
        local distance = math.sqrt((other.x - ball.x) ^ 2 + (other.y - ball.y) ^ 2 + (other.z - ball.z) ^ 2)
        if distance <= bestDistance then
          best, bestDistance = other, distance
        end
      end
    end
    if best then
      local length = math.max(bestDistance, 1e-6)
      local dx, dy, dz = (best.x - ball.x) / length, (best.y - ball.y) / length, (best.z - ball.z) / length
      local swing = math.acos(math.clamp(ax * dx + ay * dy + az * dz, -1, 1)) / pds.traverse
      ax, ay, az = dx, dy, dz
      local shooting = math.max(0, budget - swing)
      local rounds = math.min(math.floor(budget * pds.rate), item.rounds - fired)
      fired += rounds
      local rvx, rvy, rvz = best.vx - ball.vx, best.vy - ball.vy, best.vz - ball.vz
      local along = rvx * dx + rvy * dy + rvz * dz
      local across = math.sqrt(math.max(0, rvx * rvx + rvy * rvy + rvz * rvz - along * along))
      local chance = Gunnery.HitChance(across / length, pds.tracking, best.vitals.signature, bestDistance, pds.optimal, pds.falloff)
      local charge = Modules.chargeById[item.charge]
      local damage = { 0, 0, 0, 0 }
      local total = 0
      for _ = 1, math.min(rounds, math.floor(shooting * pds.rate)) do
        local quality = Gunnery.Quality(Rng.Next(rng), chance)
        for index = 1, 4 do
          damage[index] += charge.damage[index] * pds.damage * quality
        end
      end
      for index = 1, 4 do
        total += damage[index]
      end
      if total > 0 then
        table.insert(hits, { target = best.id, by = ball.id, damage = damage })
      end
      table.insert(events, { kind = "PointDefence", from = ball.id, item = item.id, to = best.id, rounds = rounds,
        down = false, x = best.x, y = best.y, z = best.z, mount = mount })
    end
  end

  item.rounds -= math.min(fired, item.rounds)
  running.ax, running.ay, running.az = ax, ay, az
  if next(downed) then
    local flying: { State.Missile } = {}
    for _, missile in state.missiles do
      if downed[missile] then
        table.insert(events, { kind = "MissileDowned", missile = missile.id, from = missile.from, to = missile.to, by = ball.id })
      else
        table.insert(flying, missile)
      end
    end
    state.missiles = flying
  end
end

return PointDefence
