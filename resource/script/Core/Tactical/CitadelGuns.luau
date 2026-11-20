--!strict
-- CitadelGuns: a citadel's defence module at work (the owner's rulings,
-- 2026-11-18 and 2026-11-19). A citadel has no batteries: one defence
-- module, "<Size> <Laser/Missile/Hybrid/Cannon> Defense Module", mounts
-- the weapons of its family on the citadel's hardpoints, so many of each
-- size and of the family's short-range or long-range make as
-- Data/Structures' CITADEL_DEFENCE has them for the citadel's size. They
-- are the game's own weapons, and fire as they do on a ship (the
-- gunnery rules; a launcher's missiles fly after their targets), with
-- nobody aiming them. Each gun fires on its own (the owner's, 2026-11-19),
-- at a ship in its reach that the citadel counts hostile, the guns of a
-- kind sharing out those in reach, nearest first:
--
--   - a pirate's, or the Drowned's;
--   - one that has struck the citadel, or a ship of its owner's, these
--     last minutes (Tactical/Combat keeps who struck whose);
--   - for a pilot's citadel, a ship of a faction at war with the side
--     the pilot has served (Tactical/Sides).
--
-- Only while the citadel is lit and the module online. (Which make of
-- each family is short and which long, how long a stroke is remembered,
-- and that the guns fire as a pilot with no skills would, are mine.)
local Citadels = require("@lt/Core/Assets/Citadels")
local Constants = require("@lt/Core/Data/Constants")
local Factions = require("@lt/Core/Data/Factions")
local Gunnery = require("@lt/Core/Tactical/Gunnery")
local Modules = require("@lt/Core/Data/Modules")
local PointDefence = require("@lt/Core/Tactical/PointDefence")
local Rng = require("@lt/Core/Kernel/Rng")
local Sides = require("@lt/Core/Tactical/Sides")
local Starbases = require("@lt/Core/Assets/Starbases")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local Wars = require("@lt/Core/Strategic/Wars")

export type Event = { [string]: any }
export type Hit = { target: number, by: number, damage: { number } }

local CitadelGuns = {}

-- How long a stroke against a citadel or its owner's ships is remembered.
CitadelGuns.MEMORY = math.floor(900 / Constants.TICK)

-- The weapon a family mounts, by its make ("short", "long") and the
-- size of hardpoint ("medium", "large", "xl").
local WORD = { medium = 2, large = 3, xl = 4 }
local TURRETS = {
  laser = { short = "laser.pulse", long = "laser.beam" },
  projectile = { short = "autocannon", long = "artillery" },
  hybrid = { short = "blaster", long = "railgun" },
} :: { [string]: { [string]: string } }
local LAUNCHERS = {
  short = { "launcher.rocket", "launcher.assault", "launcher.torpedo", "launcher.bombard" },
  long = { "launcher.light", "launcher.heavy", "launcher.cruise", "launcher.siege" },
}
function CitadelGuns.Weapon(family: string, range: string, size: string): string
  if family == "missile" then
    return LAUNCHERS[range][WORD[size]]
  end
  return `{TURRETS[family][range]}.{size}`
end

-- The defence module online in a citadel, if one is.
function CitadelGuns.Module(state: State.State, starbase: State.Starbase): Structures.ModuleType?
  for _, fitted in starbase.modules do
    local module = Structures.moduleById[fitted.type]
    if module.defence and state.tick >= fitted.ready then
      return module
    end
  end
  return nil
end

-- What a weapon fires: the first charge there is for it.
local loads: { [string]: Modules.ChargeType } = {}
local function load(module: Modules.ModuleType): Modules.ChargeType?
  local known = loads[module.id]
  if known then
    return known
  end
  for _, charge in Modules.charges do
    if Modules.Fits(module, charge) and charge.tech ~= 2 then
      loads[module.id] = charge
      return charge
    end
  end
  return nil
end

-- Whether a citadel of an owner's counts a ship hostile. (A faction's
-- citadel, since 2026-11-20, as a pilot's: whoever has struck it or its
-- people's ships, and those its people are at war with: another faction's
-- ships, or the pilot, who has served a side its people fight.)
local function hostile(state: State.State, owner: string, core: number, id: number): boolean
  local ship = state.ships[id]
  if ship == nil or id == core or ship.owner == "starbase" or ship.stands ~= nil then
    return false
  end
  local drone = state.drones[id]
  local whose = if drone and state.ships[drone.owner] then state.ships[drone.owner].owner else ship.owner
  local ours = whose == "player" or whose == "member"
  if whose == owner or (owner == "player" and ours) then
    return false
  elseif whose == "pirates" or whose == "drowned" then
    return true
  end
  local struck = state.aggressors and state.aggressors[if drone then drone.owner else id]
  if struck and struck[owner] and state.tick - struck[owner] <= CitadelGuns.MEMORY then
    return true
  end
  if owner == "player" then
    return Factions.byId[whose] ~= nil and Sides.EnemyOf(state, whose) ~= nil
  elseif ours then
    return Sides.EnemyOf(state, owner) ~= nil
  end
  return Factions.byId[whose] ~= nil and Factions.byId[owner] ~= nil and Wars.AtWar(state.wars, whose, owner)
end

-- A citadel to fire for: whose it is, what stands for it under fire, what
-- it is, its defence module (nil: it has none online), and where its guns'
-- times and its turrets' aims are kept (a pilot's starbase, or a faction's
-- citadel's record).
type Unit = { owner: string, core: State.Ball, tower: Structures.Tower, module: Structures.ModuleType?,
  holder: { guns: { number }?, pds: { { ax: number, ay: number, az: number } }? } }

-- A citadel's point defence (the owner's, 2026-11-18 and 2026-11-19): built
-- into every citadel, no module, on its point defence hardpoints (so many
-- as Data/Structures' CITADEL_HARDPOINTS says), each a medium autocannon.
-- While the citadel is lit, every one of them streams at whatever of the
-- hostiles' is in the air near it (missiles, drones, fighters), as a
-- ship's point defence turret does (Tactical/PointDefence), and never
-- runs out. Its figures are a ship's turret's, a medium gun's reach and
-- hitting harder at a drone. (These are mine.)
CitadelGuns.PDS = { rate = 10, traverse = math.rad(90), tracking = 3000, optimal = 5000, falloff = 5000, damage = 0.25,
  accuracy = 0.08 } :: Modules.PointDefence

-- What a citadel's point defence fires: the first plain medium projectile round.
local pdsRound: string? = nil
local function round(): string
  if pdsRound == nil then
    for _, charge in Modules.charges do
      if charge.family == "projectile" and charge.size == 2 and charge.tech ~= 2 then
        pdsRound = charge.id
        break
      end
    end
  end
  return pdsRound or ""
end

local function defend(state: State.State, unit: Unit, time: number, hits: { Hit }, events: { Event })
  local core = unit.core
  local count = Structures.CITADEL_HARDPOINTS[unit.tower.size].pds
  local aims = unit.holder.pds or {}
  unit.holder.pds = aims
  local function enemy(id: number): boolean
    return hostile(state, unit.owner, core.id, id)
  end
  -- (the nearest hostile on its grid, that its turrets turn to while they have nothing to shoot at: so that they
  -- are on the way its missiles will come)
  local threat: State.Ball? = nil
  local nearest = math.huge
  for _, other in state.ballIds do
    local ball = state.balls[other]
    if ball and ball.system == core.system and ball.grid == core.grid and enemy(other) then
      local gap = (ball.x - core.x) ^ 2 + (ball.y - core.y) ^ 2 + (ball.z - core.z) ^ 2
      if gap < nearest then
        threat, nearest = ball, gap
      end
    end
  end
  for k = 1, count do
    local aim = aims[k]
    if aim == nil then
      -- (each looks out its own way to begin with)
      local turn = 2 * math.pi * k / count
      aim = { ax = math.cos(turn), ay = 0, az = math.sin(turn) }
      aims[k] = aim
    end
    -- (a gun that is never out of rounds: as many as it could fire in the second)
    local item = { id = -k, charge = round(), rounds = 1000 } :: any
    local before = #events
    PointDefence.Cycle(state, core, item, aim :: any, CitadelGuns.PDS, time, hits, events, enemy, k)
    local towards = threat
    if #events == before and towards then
      -- (idle: it swings toward the threat, as far as it swings in a second)
      local dx, dy, dz = towards.x - core.x, towards.y - core.y, towards.z - core.z
      local length = math.max(1e-6, math.sqrt(dx * dx + dy * dy + dz * dz))
      dx, dy, dz = dx / length, dy / length, dz / length
      local angle = math.acos(math.clamp(aim.ax * dx + aim.ay * dy + aim.az * dz, -1, 1))
      local part = if angle <= CitadelGuns.PDS.traverse then 1 else CitadelGuns.PDS.traverse / angle
      local ax, ay, az = aim.ax + (dx - aim.ax) * part, aim.ay + (dy - aim.ay) * part, aim.az + (dz - aim.az) * part
      local norm = math.max(1e-6, math.sqrt(ax * ax + ay * ay + az * az))
      aim.ax, aim.ay, aim.az = ax / norm, ay / norm, az / norm
    end
  end
end

-- One citadel's turn: its point defence, and the guns of its defence
-- module that are due firing.
local function fireFor(state: State.State, unit: Unit, time: number, hits: { Hit }, events: { Event })
  local core = unit.core
  local tower = unit.tower
  defend(state, unit, time, hits, events)
  local module = unit.module
  if module then
      local family = module.defence :: string
      local mounted = Structures.CITADEL_DEFENCE[tower.size]
      local guns = unit.holder.guns or {}
      unit.holder.guns = guns
      -- (who is about that it counts hostile, nearest first)
      type Near = { ball: State.Ball, gap: number }
      local near: { Near } = {}
      for _, other in state.ballIds do
        local ball = state.balls[other]
        if ball and ball.system == core.system and ball.grid == core.grid and not (ball.warp and ball.warp.stage == "warp")
          and hostile(state, unit.owner, core.id, other) then
          local gap = math.sqrt((ball.x - core.x) ^ 2 + (ball.y - core.y) ^ 2 + (ball.z - core.z) ^ 2) - core.radius - ball.radius
          table.insert(near, { ball = ball, gap = math.max(0, gap) })
        end
      end
      table.sort(near, function(a: Near, b: Near): boolean
        return a.gap < b.gap or (a.gap == b.gap and a.ball.id < b.ball.id)
      end)
      -- Each gun on its own (the owner's, 2026-11-19: the guns fire independently): its own time, the first one
      -- spread over its cycle so that they do not all fire at once, and its own target, the guns of a kind taking the
      -- hostiles in their reach in turn, nearest first, so that their fire is spread among those who come.
      local g = 0
      for _, group in mounted do
        local gun = Modules.byId[CitadelGuns.Weapon(family, group.range, group.size)]
        local weapon = if gun then gun.weapon else nil
        local charge = if gun then load(gun) else nil
        if gun and weapon and charge then
          local cycle = math.max(1, math.ceil(weapon.duration / Constants.TICK))
          local missile = weapon.family == "missile"
          local reach = if missile then charge.velocity * charge.flightTime * (weapon.flight or 1)
            else weapon.optimal * charge.rangeMultiplier + weapon.falloff
          local inReach: { Near } = {}
          for _, each in near do
            if each.gap <= reach then
              table.insert(inReach, each)
            end
          end
          for k = 1, group.count do
            g += 1
            if guns[g] == nil then
              guns[g] = state.tick + (g * 7) % cycle
            end
            if #inReach > 0 and state.tick >= guns[g] then
              guns[g] = state.tick + cycle
              local target = inReach[(k - 1) % #inReach + 1]
              local ball = target.ball
              if missile then
                -- (its missile, flying after its target: Tactical/Combat)
                local flight = target.gap / charge.velocity
                local damage: { number } = {}
                for kind = 1, 4 do
                  damage[kind] = charge.damage[kind] * weapon.damageMultiplier
                end
                local missileId = State.NewId(state)
                table.insert(state.missiles, { from = core.id, to = ball.id, item = 0, charge = charge.id, damage = damage,
                  impact = time + flight, blast = weapon.blast, id = missileId, born = time, lx = core.x, ly = core.y, lz = core.z,
                  x = core.x, y = core.y, z = core.z, vx = 0, vy = 0, vz = 0, at = time, speed = charge.velocity, grid = core.grid,
                  expires = time + charge.flightTime * (weapon.flight or 1) })
                table.insert(events, { kind = "Shot", from = core.id, item = 0, to = ball.id, family = "missile", outcome = "launched",
                  damage = 0, flight = flight, missile = missileId, look = gun.id, mount = k })
              else
                -- (its shot, rolled as a ship's is: how fast the target crosses, how big it is, how far)
                local rx, ry, rz = ball.x - core.x, ball.y - core.y, ball.z - core.z
                local distance = math.max(1e-6, math.sqrt(rx * rx + ry * ry + rz * rz))
                local along = (ball.vx * rx + ball.vy * ry + ball.vz * rz) / distance
                local across = math.sqrt(math.max(0, ball.vx ^ 2 + ball.vy ^ 2 + ball.vz ^ 2 - along * along))
                local chance = Gunnery.HitChance(across / distance, weapon.tracking * (charge.tracking or 1), ball.vitals.signature,
                  target.gap, weapon.optimal * charge.rangeMultiplier, weapon.falloff)
                local quality = Gunnery.Quality(Rng.Next(Rng.For(state.historySeed, state.tick, core.id, g, 79)), chance)
                local damage, total = { 0, 0, 0, 0 }, 0
                for kind = 1, 4 do
                  damage[kind] = charge.damage[kind] * weapon.damageMultiplier * quality
                  total += damage[kind]
                end
                if total > 0 then
                  table.insert(hits, { target = ball.id, by = core.id, damage = damage })
                end
                table.insert(events, { kind = "Shot", from = core.id, item = 0, to = ball.id, family = weapon.family,
                  outcome = if quality == 0 then "miss" elseif quality == 3 then "wreck" else "hit", damage = total, look = gun.id,
                  mount = k })
              end
            end
          end
        end
      end
  end
end

-- Every lit citadel's point defence, and its defence module's weapons
-- that are due firing at the nearest hostile in their reach: the hits of
-- its turrets (for the tick's combat to apply), and its launchers'
-- missiles put in the air. A pilot's, and (since 2026-11-20) a faction's
-- that stands, whose core is there (Assets/Citadels): always manned, and
-- with its people's defence module (Citadels.Defence).
function CitadelGuns.Fire(state: State.State, events: { Event }): { Hit }
  local hits: { Hit } = {}
  local time = state.tick * Constants.TICK
  for _, id in state.starbaseIds do
    local starbase = state.starbases[id]
    local tower = Structures.towerById[starbase.tower]
    local core = state.balls[starbase.core]
    if tower.citadel and core and Starbases.Lit(state, starbase) then
      fireFor(state, { owner = starbase.owner, core = core, tower = tower, module = CitadelGuns.Module(state, starbase),
        holder = starbase :: any }, time, hits, events)
    end
  end
  local keys: { number } = state.citadelIds or {}
  for _, key in keys do
    local record = state.citadels[key]
    local core = if record.core and not record.fallen then state.balls[record.core] else nil
    local tower = Structures.towerById[record.tower]
    if core and tower then
      fireFor(state, { owner = record.owner, core = core, tower = tower, module = Structures.moduleById[Citadels.Defence(record)],
        holder = record :: any }, time, hits, events)
    end
  end
  return hits
end

return CitadelGuns
