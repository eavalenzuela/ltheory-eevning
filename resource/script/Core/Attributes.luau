--!strict
-- The attribute engine: what a ship is, given its hull and everything
-- fitted to it.
--
-- Nothing here is stored. A ship's statistics are always worked out from
-- its hull and its modules, so they cannot drift from the fit.
--
-- For each attribute: start from the hull's value, add every "add"
-- modifier, then multiply by every "mul" modifier. Multipliers marked
-- 'stack' are weakened when several of them touch the same attribute:
-- sorted strongest first, the n-th (counting from 0) has its effect
-- scaled by exp(-(n / 2.67)^2): 100%, 87%, 57%, 28%, 11%... Bonuses and
-- penalties are ranked separately. This is what stops five of the same
-- module from being five times as good.

local Boosters = require("@lt/Core/Data/Boosters")
local Implants = require("@lt/Core/Data/Implants")
local Modules = require("@lt/Core/Data/Modules")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")

local Attributes = {}

-- A module on a ship: its type and whether it is running (its 'boost'
-- then applies).
-- ('spared': a booster at work whose ill effect did not strike.)
export type Fitted = { type: string, running: boolean, spared: boolean? }

-- A ship's attributes by name: "shield", "maxVelocity", "armorResonance.2", ...
export type Stats = { [string]: number }

-- A pilot's skill levels by skill id.
export type Levels = { [string]: number }

-- The weight of the n-th strongest of several stacking effects (n from 0).
function Attributes.Penalty(n: number): number
  return math.exp(-(n / 2.67) ^ 2)
end

type Pending = { adds: number, plain: number, bonuses: { number }, penalties: { number } }

local function pendingFor(pending: { [string]: Pending }, attribute: string): Pending
  local p = pending[attribute]
  if p == nil then
    p = { adds = 0, plain = 1, bonuses = {}, penalties = {} }
    pending[attribute] = p
  end
  return p
end

local function collect(pending: { [string]: Pending }, modifier: Modules.Modifier)
  local p = pendingFor(pending, modifier.attribute)
  if modifier.op == "add" then
    p.adds += modifier.value
  elseif not modifier.stack then
    p.plain *= modifier.value
  elseif modifier.value >= 1 then
    table.insert(p.bonuses, modifier.value)
  else
    table.insert(p.penalties, modifier.value)
  end
end

local function resolve(base: number, p: Pending): number
  local value = (base + p.adds) * p.plain
  -- Strongest first: the largest bonuses, the deepest penalties.
  table.sort(p.bonuses, function(a: number, b: number): boolean
    return a > b
  end)
  table.sort(p.penalties)
  for n, m in p.bonuses do
    value *= 1 + (m - 1) * Attributes.Penalty(n - 1)
  end
  for n, m in p.penalties do
    value *= 1 + (m - 1) * Attributes.Penalty(n - 1)
  end
  return value
end

-- The modifiers of a fit, and of the pilot's skills, that apply to 'on'
-- (and, for weapons, 'family'). A skill's bonus is its value times its
-- level, and is never penalised.
-- ('stealth': the hull is built to go unseen, and a cloak that runs on
-- it does not slow it: Data/Ships.)
local function gather(fitted: { Fitted }, on: string, family: string?, levels: Levels?, stealth: boolean?): { [string]: Pending }
  local pending: { [string]: Pending } = {}
  if levels then
    -- in the skill list's order, so the arithmetic is the same every time
    for _, skill in Skills.list do
      local level = levels[skill.id] or 0
      if level > 0 then
        local function apply(bonus: Modules.Modifier)
          -- ("turret": every family of turret, which is every family but missiles)
          if bonus.on == on and (on == "ship" or bonus.family == family or (bonus.family == "turret" and family ~= "missile")) then
            pendingFor(pending, bonus.attribute).plain *= 1 + bonus.value * level
          end
        end
        if skill.bonus then
          apply(skill.bonus)
        end
        for _, bonus in skill.bonuses or {} :: { Modules.Modifier } do
          apply(bonus)
        end
      end
    end
  end
  for _, f in fitted do
    local module = Modules.byId[f.type]
    -- (what is not a module is an implant of the pilot's, or a booster
    -- at work on them: Data/Implants, Data/Boosters)
    local implant = Implants.byId[f.type]
    local passive: { Modules.Modifier } = if module then module.passive elseif implant then implant.passive
      elseif f.spared then Boosters.byId[f.type].gives else Boosters.byId[f.type].passive
    -- (for weapons, "turret" is every family of turret: every one but missiles)
    for _, modifier in passive do
      if modifier.on == on and (on == "ship" or modifier.family == family or (modifier.family == "turret" and family ~= "missile")) then
        collect(pending, modifier)
      end
    end
    if module and f.running and module.boost and not (stealth and module.cloak) then
      for _, modifier in module.boost do
        if modifier.on == on and (on == "ship" or modifier.family == family or (modifier.family == "turret" and family ~= "missile")) then
          collect(pending, modifier)
        end
      end
    end
  end
  return pending
end

local RESONANCES = { "shieldResonance", "armorResonance", "hullResonance" }
-- (the last two are what a hull that mends by itself gets back of its
-- armour and of its hull each second, as a share: nothing, for a hull
-- that does not, whatever is fitted to it)
local PLAIN = { "mass", "inertia", "maxVelocity", "warpSpeed", "radius", "shield", "armor", "hull", "shieldRecharge",
  "signature", "cpu", "powergrid", "capacitor", "capacitorRecharge", "scanResolution", "lockRange", "maxTargets", "cargo" }

local MENDS = { "armorMend", "hullMend" }

-- A ship's attributes with this fit, flown by a pilot with these skills
-- (none, for a ship nobody trained to fly).
function Attributes.Ship(hull: Ships.ShipType, fitted: { Fitted }, levels: Levels?): Stats
  local base: Stats = {}
  local source = hull :: any
  for _, name in PLAIN do
    base[name] = source[name]
  end
  for _, name in MENDS do
    base[name] = source[name] or 0
  end
  for _, name in RESONANCES do
    for index = 1, 4 do
      base[`{name}.{index}`] = source[name][index]
    end
  end
  local pending = gather(fitted, "ship", nil, levels, hull.stealth)
  local stats: Stats = {}
  for name, value in base do
    local p = pending[name]
    stats[name] = if p then resolve(value, p) else value
  end
  -- The time constant of its flight (Tactical/Motion).
  stats.tau = stats.inertia * stats.mass / 1e6
  return stats
end

-- A weapon module's statistics on a ship with this fit.
function Attributes.Weapon(fitted: { Fitted }, type: string, levels: Levels?): Modules.Weapon
  local weapon = assert(Modules.byId[type].weapon, `{type} is not a weapon`)
  local pending = gather(fitted, "weapons", weapon.family, levels)
  local out = table.clone(weapon) :: any
  -- (how far its missiles fly and how wide their blast is, as shares of
  -- the missile's own: 1 where the weapon does not say)
  out.flight, out.blast = out.flight or 1, out.blast or 1
  for name, p in pending do
    out[name] = resolve(out[name], p)
  end
  return out
end

local RIGS = { "small", "medium", "large" }
local GUN_SIZES = { "small", "medium", "large", "XL" }

-- What a module asks of a hull to be fitted to it: CPU, tf, and
-- powergrid, MW. What the module says, but for a cloaking device: it
-- asks a share of the hull's own CPU beside (Data/Modules: it is very
-- dear), and a hull built for one, to go unseen or to explore, asks a
-- tenth of all of it (Ships.CLOAK_FITTING).
function Attributes.Needs(hull: Ships.ShipType, module: Modules.ModuleType): (number, number)
  local cloak = module.cloak
  if cloak == nil then
    return module.cpu, module.powergrid
  end
  local share = if hull.stealth or hull.explorer then Ships.CLOAK_FITTING else 1
  return (module.cpu + hull.cpu * cloak.cpu) * share, module.powergrid * share
end

-- Whether a hull can carry these modules at once; if not, why not.
function Attributes.Check(hull: Ships.ShipType, types: { string }, levels: Levels?): (boolean, string?)
  local slots = { high = 0, mid = 0, low = 0, rig = 0 }
  local hardpoints = { turret = 0, launcher = 0 }
  local cpu, powergrid, calibration = 0, 0, 0
  local fitted: { Fitted } = {}
  for _, id in types do
    local module = Modules.byId[id]
    if module == nil then
      return false, `'{id}' is not a module`
    end
    slots[module.slot] += 1
    if module.hardpoint ~= "" then
      hardpoints[module.hardpoint] += 1
    end
    local tf, mw = Attributes.Needs(hull, module)
    cpu += tf
    powergrid += mw
    calibration += module.calibration or 0
    table.insert(fitted, { type = id, running = false })
  end
  -- (a capital's module goes on a capital and on nothing smaller)
  if not Ships.Capital(hull.class) then
    for _, id in types do
      if Modules.byId[id].capital then
        return false, "only a capital fits that"
      end
    end
  end
  -- (a hull with no shield has nothing for a shield module to work on:
  -- the Nimia's)
  if hull.shield <= 0 and hull.class ~= "capsule" then
    for _, id in types do
      if string.sub(id, 1, 7) == "shield." or string.sub(id, 1, 10) == "rig.shield" then
        return false, "this hull carries no shield"
      end
    end
  end
  if slots.high > hull.highs then
    return false, "no free high slot"
  elseif slots.mid > hull.mids then
    return false, "no free mid slot"
  elseif slots.low > hull.lows then
    return false, "no free low slot"
  elseif slots.rig > (hull.rigs or 0) then
    return false, "no free rig slot"
  elseif calibration > (hull.calibration or 0) then
    return false, string.format("not enough calibration (%d of %d)", calibration, hull.calibration or 0)
  elseif hardpoints.turret > hull.turrets then
    return false, "no free turret hardpoint"
  elseif hardpoints.launcher > hull.launchers then
    return false, "no free launcher hardpoint"
  end
  -- (a hull whose hardpoints are of given sizes: a weapon goes on one
  -- of its own size, or on a bigger one that nothing bigger wants)
  for kind, sized in { turret = hull.guns, launcher = hull.racks } :: { [string]: { number }? } do
    if sized then
      local wanted: { number } = table.create(#sized, 0)
      for _, id in types do
        local module = Modules.byId[id]
        if module.hardpoint == kind then
          wanted[math.clamp(Modules.SizeOf(module), 1, #sized)] += 1
        end
      end
      local free = 0
      for size = #sized, 1, -1 do
        free += sized[size] - wanted[size]
        if free < 0 then
          return false, `no free hardpoint for a {GUN_SIZES[size]} {kind}`
        end
      end
    end
  end
  -- (a rig is made for a size of hull, and goes into no other)
  local takes = Ships.RigSize(hull)
  for _, id in types do
    local module = Modules.byId[id]
    if module.slot == "rig" and takes > 0 and Modules.SizeOf(module) ~= takes then
      return false, `a {RIGS[Modules.SizeOf(module)]} rig does not go into this hull: it takes {RIGS[takes]} ones`
    end
  end
  local stats = Attributes.Ship(hull, fitted, levels)
  if cpu > stats.cpu then
    return false, string.format("not enough CPU (%.0f of %.0f tf)", cpu, stats.cpu)
  elseif powergrid > stats.powergrid then
    return false, string.format("not enough powergrid (%.0f of %.0f MW)", powergrid, stats.powergrid)
  end
  return true
end

return Attributes
