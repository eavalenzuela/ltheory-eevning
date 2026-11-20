--!strict
-- CitadelGuns: a citadel's defence module at work (the owner's rulings,
-- 2026-11-18 and 2026-11-19). A citadel has no batteries: one defence
-- module, "<Size> <Laser/Missile/Hybrid/Cannon> Defense Module", mounts
-- the weapons of its family on the citadel's hardpoints, so many of each
-- size and of the family's short-range or long-range make as
-- Data/Structures' CITADEL_DEFENCE has them for the citadel's size. They
-- are the game's own weapons, and fire as they do on a ship (the
-- gunnery rules; a launcher's missiles fly after their targets), with
-- nobody aiming them. Each group fires on its own, at the nearest ship
-- in its reach that the citadel counts hostile:
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
local Constants = require("@lt/Core/Data/Constants")
local Factions = require("@lt/Core/Data/Factions")
local Gunnery = require("@lt/Core/Tactical/Gunnery")
local Modules = require("@lt/Core/Data/Modules")
local Rng = require("@lt/Core/Kernel/Rng")
local Sides = require("@lt/Core/Tactical/Sides")
local Starbases = require("@lt/Core/Assets/Starbases")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")

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

-- Whether a citadel counts a ship hostile.
local function hostile(state: State.State, starbase: State.Starbase, id: number): boolean
  local ship = state.ships[id]
  if ship == nil or id == starbase.core or ship.owner == "starbase" then
    return false
  end
  local drone = state.drones[id]
  local owner = if drone and state.ships[drone.owner] then state.ships[drone.owner].owner else ship.owner
  if owner == starbase.owner or (starbase.owner == "player" and owner == "member") then
    return false
  elseif owner == "pirates" or owner == "drowned" then
    return true
  end
  local struck = state.aggressors and state.aggressors[if drone then drone.owner else id]
  if struck and struck[starbase.owner] and state.tick - struck[starbase.owner] <= CitadelGuns.MEMORY then
    return true
  end
  if starbase.owner == "player" and Factions.byId[owner] and Sides.EnemyOf(state, owner) ~= nil then
    return true
  end
  return false
end

-- Every lit citadel's defence module, its weapons that are due firing at
-- the nearest hostile in their reach: the hits of its turrets (for the
-- tick's combat to apply), and its launchers' missiles put in the air.
function CitadelGuns.Fire(state: State.State, events: { Event }): { Hit }
  local hits: { Hit } = {}
  local time = state.tick * Constants.TICK
  for _, id in state.starbaseIds do
    local starbase = state.starbases[id]
    local tower = Structures.towerById[starbase.tower]
    local core = state.balls[starbase.core]
    local module = if tower.citadel and core and Starbases.Lit(state, starbase) then CitadelGuns.Module(state, starbase) else nil
    if module and core then
      local family = module.defence :: string
      local mounted = Structures.CITADEL_DEFENCE[tower.size]
      local guns = starbase.guns or {}
      starbase.guns = guns
      -- (who is about that it counts hostile, nearest first)
      type Near = { ball: State.Ball, gap: number }
      local near: { Near } = {}
      for _, other in state.ballIds do
        local ball = state.balls[other]
        if ball and ball.system == core.system and ball.grid == core.grid and not (ball.warp and ball.warp.stage == "warp")
          and hostile(state, starbase, other) then
          local gap = math.sqrt((ball.x - core.x) ^ 2 + (ball.y - core.y) ^ 2 + (ball.z - core.z) ^ 2) - core.radius - ball.radius
          table.insert(near, { ball = ball, gap = math.max(0, gap) })
        end
      end
      table.sort(near, function(a: Near, b: Near): boolean
        return a.gap < b.gap or (a.gap == b.gap and a.ball.id < b.ball.id)
      end)
      for index, group in mounted do
        local gun = Modules.byId[CitadelGuns.Weapon(family, group.range, group.size)]
        local weapon = if gun then gun.weapon else nil
        local charge = if gun then load(gun) else nil
        if gun and weapon and charge and state.tick >= (guns[index] or 0) and #near > 0 then
          local missile = weapon.family == "missile"
          local reach = if missile then charge.velocity * charge.flightTime * (weapon.flight or 1)
            else weapon.optimal * charge.rangeMultiplier + weapon.falloff
          local target: Near? = nil
          for _, each in near do
            if each.gap <= reach then
              target = each
              break
            end
          end
          if target then
            guns[index] = state.tick + math.max(1, math.ceil(weapon.duration / Constants.TICK))
            local ball = target.ball
            if missile then
              -- (each launcher's missile, flying after its target: Tactical/Combat)
              local flight = target.gap / charge.velocity
              for _ = 1, group.count do
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
                  damage = 0, flight = flight, missile = missileId, look = gun.id })
              end
            else
              -- (each turret's shot, rolled as a ship's is: how fast the target crosses, how big it is, how far)
              local rx, ry, rz = ball.x - core.x, ball.y - core.y, ball.z - core.z
              local distance = math.max(1e-6, math.sqrt(rx * rx + ry * ry + rz * rz))
              local along = (ball.vx * rx + ball.vy * ry + ball.vz * rz) / distance
              local across = math.sqrt(math.max(0, ball.vx ^ 2 + ball.vy ^ 2 + ball.vz ^ 2 - along * along))
              local chance = Gunnery.HitChance(across / distance, weapon.tracking * (charge.tracking or 1), ball.vitals.signature,
                target.gap, weapon.optimal * charge.rangeMultiplier, weapon.falloff)
              local rng = Rng.For(state.historySeed, state.tick, core.id, index, 79)
              local damage, total, landed = { 0, 0, 0, 0 }, 0, 0
              for _ = 1, group.count do
                local quality = Gunnery.Quality(Rng.Next(rng), chance)
                if quality > 0 then
                  landed += 1
                  for kind = 1, 4 do
                    damage[kind] += charge.damage[kind] * weapon.damageMultiplier * quality
                  end
                end
              end
              for kind = 1, 4 do
                total += damage[kind]
              end
              if total > 0 then
                table.insert(hits, { target = ball.id, by = core.id, damage = damage })
              end
              table.insert(events, { kind = "Shot", from = core.id, item = 0, to = ball.id, family = weapon.family,
                outcome = if landed == 0 then "miss" else "hit", damage = total, look = gun.id, guns = group.count })
            end
          end
        end
      end
    end
  end
  return hits
end

return CitadelGuns
