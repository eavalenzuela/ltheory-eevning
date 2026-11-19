--!strict
-- How hard an assault of each level is (Tactical/Assault): a plain ship
-- of the class the level is for, flown simply, against every camp the
-- level can be. (The job itself, its camp and its pay are Assets/Missions'
-- spec.)

local Assault = require("@lt/Core/Tactical/Assault")
local Core = require("@lt/Core/Api")
local Attributes = require("@lt/Core/Attributes")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")
local Space = require("@lt/Core/Tactical/Space")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Assault")

-- A plain fit for a hull: a gun or a launcher of its size on every
-- hardpoint, and then what there is room for of a web (an entanglement
-- projector), an afterburner, a target painter, two shield extenders, a
-- plate, a repairer, a damage control, a gyrostabiliser and another
-- plate. Nothing custom, nothing tech 2. And a drone bay full of light
-- combat drones. (The web, the painter and the drones since
-- 2026-11-18, when guns were set from the reference and a big gun all
-- but misses a small ship: what a pilot does about the smaller pirates a
-- level is made of, as the reference's pilots do.)
-- The three sets of modules a level is flown with (the owner, 2026-11-18:
-- "test 3 sets of modules with a run: tech 1, tech 2, and max-fit,
-- officer/deadspace/masterwork"): the plain modules; the tech 2 make of
-- whatever has one, with tech 2 rounds in it; and the best make there is
-- of each, an officer's where an officer carries it, else the deepest
-- deadspace make, else a masterwork. (Tech 2 drones for both of those.)
local TIERS: { string } = { "t1", "t2", "max" }

local function make(id: string, tier: string): string
  if tier == "t2" then
    return if Modules.Improved(id) then id .. ".ii" else id
  elseif tier == "max" then
    return Modules.Officer(id, "Test Officer") or (if rawget(Modules.byId, id .. ".site3") then id .. ".site3" else nil)
      or (if rawget(Modules.byId, id .. ".master") then id .. ".master" else nil) or id
  end
  return id
end

local function plain(hullId: string, given: string?): { { string } }
  local tier = given or "t1"
  local hull = Ships.byId[hullId]
  local size = if hull.class == "battleship" then "large" elseif hull.class == "cruiser" then "medium" else "small"
  local rack = if size == "large" then "launcher.cruise" elseif size == "medium" then "launcher.heavy" else "launcher.light"
  local missile = if size == "large" then "missile.cruise.kinetic" elseif size == "medium" then "missile.heavy.kinetic"
    else "missile.light.kinetic"
  local rounds = if size == "small" then "ammo.fusion" else "ammo.fusion." .. size
  local plate = if size == "small" then "armor.plate.200mm" else "armor.plate." .. size
  local wanted: { { string } } = {}
  for _ = 1, hull.turrets do
    table.insert(wanted, { "autocannon." .. size, rounds })
  end
  for _ = 1, hull.launchers do
    table.insert(wanted, { rack, missile })
  end
  for _, module in { "projector.entanglement", if size == "small" then "afterburner.1mn" else "afterburner." .. size, "painter.target",
    "shield.extender." .. size, "shield.extender." .. size, plate, "armor.repairer." .. size, "damage.control", "gyrostabilizer", plate } do
    table.insert(wanted, { module })
  end
  local types: { string } = {}
  local fit: { { string } } = {}
  for _, entry in wanted do
    assert(Modules.byId[entry[1]], `no module {entry[1]}`)
    local module = make(entry[1], tier)
    -- (a tech 2 gun takes the tech 2 make of its rounds)
    local charge = entry[2]
    if charge and tier == "t2" and Modules.ImprovedCharge(charge) then
      charge = charge .. ".ii"
    end
    table.insert(types, module)
    if Attributes.Check(hull, types) then
      table.insert(fit, { module, charge })
    else
      table.remove(types)
    end
  end
  return fit
end

-- A pilot with every skill at a level, in a hull fitted plainly, takes
-- some waves in turn, each from thirty kilometres off: they orbit the
-- nearest of them at a range, lock it, and switch everything on. Whether
-- they came through it, and the share of the ship's shield, armour and
-- hull that was left. 'works': what the camp is built of stands eight
-- kilometres off from the first, firing if it can, and is destroyed
-- when the last of the waves is: whoever flies is gone for first.
local function fight(hullId: string, level: number, orbit: number, waves: { { string } }, works: { string }?, tier: string?): (boolean, number)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  -- (the plain skills, every one at the level: not the crafts of a trade, which nothing is laid out on the
  -- footing that a pilot has, and which make all of this easier for one who does)
  for _, skill in Skills.list do
    if not skill.craft then
      state.skills[skill.id] = level
    end
  end
  -- (and a pilot who flies tech 2, or better, has what it asks for, where theirs is less)
  local function trained(type: string)
    for _, need in Skills.Needs(type) do
      state.skills[need.skill] = math.max(state.skills[need.skill] or 0, need.level)
    end
  end
  local ship = Space.NewShip(state, hullId, "Test", "player", state.player.home)
  for _, entry in plain(hullId, tier) do
    trained(entry[1])
    Items.Equip(state, ship.id, entry[1], entry[2])
    if entry[2] then
      Items.Add(state, entry[2], 3000, ship.id, "cargo")
    end
  end
  local hull = Ships.byId[hullId]
  -- (a bay full: as many as it controls, and spares)
  local drones = if (hull.drones or Ships.DRONES[hull.class] or 0) > 0 then math.floor((hull.bay or Ships.BAY[hull.class] or 0) / 5) else 0
  if drones > 0 then
    -- (the tech 2 make for a tier above the plain one, where the pilot has the Drones it takes)
    local better = (tier or "t1") ~= "t1"
    local drone = if better then "drone.light.ii" else "drone.light"
    trained(drone)
    if better then
      state.skills.drones = math.max(state.skills.drones or 0, 4)
    end
    Items.Add(state, drone, drones, ship.id, "dronebay")
  end
  state.player.ship = ship.id
  local id = ship.id
  local undocked, why = Core.Submit(game, { kind = "Undock", actor = id })
  assert(undocked, `{hullId} could not undock: {tostring(why)}`)
  Core.Step(game)
  local me = state.balls[id]
  me.x += 5e7
  me.vx, me.vy, me.vz = 0, 0, 0
  Space.AssignGrid(state, me)
  -- (the place is a job's camp, as far as those who come to it can tell: they are there to defend it, so nobody
  -- breaks off, and they come on at their own speed)
  state.sites[me.grid] = { id = me.grid, system = me.system, kind = "mission", gone = false } :: any
  local standing: { string } = works or {}
  for n, kind in standing do
    Pirates.Spawn(state, Pirates.kindById[kind], me.system, me.x + 8000 * math.cos(2.1 * n), me.y, me.z + 8000 * math.sin(2.1 * n), me.grid)
  end
  -- (the waves in turn, and then, with nobody left flying, what stands)
  for round = 1, #waves + (if #standing > 0 then 1 else 0) do
    for n, kind in waves[round] or {} :: { string } do
      Pirates.Spawn(state, Pirates.kindById[kind], me.system, me.x + 30000 * math.cos(2.1 * n), me.y, me.z + 30000 * math.sin(2.1 * n),
        me.grid)
    end
    local engaged = 0
    for _ = 1, 3000 do
      if state.player.ship ~= id or state.balls[id] == nil then
        return false, 0
      end
      local nearest: number, least = 0, math.huge
      for _, other in state.pilotIds do
        local ball = state.balls[other]
        local flies = Ships.byId[state.ships[other].type].class ~= "works"
        if ball and ball.grid == me.grid and (flies or round > #waves) and Space.Distance(ball :: any, me :: any) < least then
          nearest, least = other, Space.Distance(ball :: any, me :: any)
        end
      end
      if nearest == 0 then
        break
      end
      if not (me.mode == "orbit" and me.target == nearest) then
        Core.Submit(game, { kind = "Orbit", actor = id, target = nearest, range = orbit })
      end
      local targeted, locked = false, false
      for _, lock in me.vitals.locks do
        if lock.target == nearest then
          targeted, locked = true, lock.locked
        end
      end
      if not targeted then
        Core.Submit(game, { kind = "LockTarget", actor = id, target = nearest })
      elseif locked then
        for _, item in Items.Fitted(state, id) do
          local module = Modules.byId[item.type]
          local on = false
          for _, running in me.vitals.running do
            on = on or running.item == item.id
          end
          if not on and (module.weapon or module.repair or module.boost or module.hex) then
            Core.Submit(game, { kind = "ActivateModule", actor = id, item = item.id,
              target = if module.weapon or module.hex then nearest else nil })
          end
        end
        -- (the drones out, and on what the guns are on)
        Core.Submit(game, { kind = "LaunchDrones", actor = id })
        if engaged ~= nearest and (Core.Submit(game, { kind = "EngageDrones", actor = id, target = nearest })) then
          engaged = nearest
        end
      end
      Core.Step(game)
      Core.TakeEvents(game)
    end
  end
  local vitals = state.balls[id].vitals
  return true, (vitals.shield + vitals.armor + vitals.hull) / (vitals.shieldMax + vitals.armorMax + vitals.hullMax)
end

-- Every camp a level can be: each choice of its waves, in each order.
local function camps(level: number): { { { string } } }
  local out: { { { string } } } = {}
  local packs = Assault.PACKS[level]
  local used: { boolean } = {}
  local chosen: { { string } } = {}
  local function go()
    if #chosen == Assault.WAVES[level] then
      table.insert(out, table.clone(chosen))
      return
    end
    for index, pack in packs do
      if not used[index] then
        used[index] = true
        table.insert(chosen, pack)
        go()
        table.remove(chosen)
        used[index] = false
      end
    end
  end
  go()
  return out
end

-- The ship a level is for: a frigate with a pilot of little skill, and
-- on up. And the range it fights at.
local FOR: { { any } } = {
  { "frigate.akashi", 2, 2000 }, { "destroyer.nozomi", 3, 2500 }, { "cruiser.paestro", 4, 5000 }, { "battleship.owari", 4, 12000 },
}

-- What a level's ship must do, flown with each set of modules (the
-- owner's rule, 2026-11-18): with the plain ones, nothing ("If only t1
-- fails consistently, it's not an issue"); with the tech 2 ones, not
-- fail time and again ("If t2 also consistently fails, the room is
-- overpowered": here, more than a quarter of the time, which is mine);
-- with the best there is, die no more than one time in ten ("if
-- max-fit dies more than 1/10 times, it's WAY too powerful").
local TECH2_FAILS, MAX_DIES = 0.25, 0.1

suite:Case("a ship of the class a level is for comes through that level's camps as it is fitted, and the class below it through few", function(t)
  local said: { string } = {}
  for level, ship in FOR do
    local name = Ships.byId[ship[1]].name
    local line: { string } = {}
    for _, tier in TIERS do
      local wins, least, total = 0, 1, 0
      for _, waves in camps(level) do
        total += 1
        local won, left = fight(ship[1], ship[2], ship[3], waves, nil, tier)
        wins += if won then 1 else 0
        least = if won then math.min(least, left) else least
      end
      table.insert(line, `{tier} {wins}/{total} least {math.floor(least * 100)}%`)
      if tier == "t2" then
        t.ok(total - wins <= total * TECH2_FAILS, `a {name} with tech 2 modules came through {wins} of {total} level {level} camps`)
      elseif tier == "max" then
        t.ok(total - wins <= total * MAX_DIES, `a {name} with the best modules there are died in {total - wins} of {total} level {level} camps`)
      end
    end
    table.insert(said, `{Ships.byId[ship[1]].class} L{level}: {table.concat(line, ", ")}`)
    -- The class below, plainly fitted: the level is not for it.
    local below = FOR[level - 1]
    if below then
      local theirs = 0
      for _, waves in camps(level) do
        theirs += if fight(below[1], below[2], below[3], waves) then 1 else 0
      end
      t.ok(theirs < #camps(level) / 2, `a {Ships.byId[below[1]].name} came through {theirs} of {#camps(level)} camps of level {level}`)
    end
  end
  print("     assault: " .. table.concat(said, "; "))
end)

-- (The job is what the camp is built of, which stands in its last room,
-- and whoever is in that room is on the pilot while they are at it: at
-- the worst every wave the last room can have, one after another, with
-- the emplacements firing all the while. Whoever flies is gone for
-- first, which is the way to do it.)
suite:Case("a ship of the class a level is for razes a camp of that level as it is fitted, with every wave its last room can have on them", function(t)
  local lines: { string } = {}
  for level = 1, #Assault.PACKS do
    local hull: string, skill: number, orbit: number = FOR[level][1], FOR[level][2], FOR[level][3]
    -- (the most waves a last room has: all of them but one for each room before it)
    local most = Assault.WAVES[level] - Assault.LEAST[level] + 1
    local every = camps(level)
    local line: { string } = {}
    for _, tier in TIERS do
      local won, tried, worst = 0, 0, 1
      -- (every other camp the level can be: enough to say)
      for index = 1, #every, 2 do
        local waves = table.move(every[index], #every[index] - most + 1, #every[index], 1, {})
        local ok, left = fight(hull, skill, orbit, waves, Assault.WORKS[level], tier)
        tried += 1
        won += if ok then 1 else 0
        worst = if ok then math.min(worst, left) else worst
      end
      table.insert(line, `{tier} {won}/{tried} least {math.floor(worst * 100)}%`)
      if tier == "t2" then
        t.ok(tried - won <= tried * TECH2_FAILS, `a {hull} with tech 2 modules razed {won} of {tried} level {level} camps`)
      elseif tier == "max" then
        t.ok(tried - won <= tried * MAX_DIES, `a {hull} with the best modules there are died in {tried - won} of {tried} level {level} camps`)
      end
    end
    table.insert(lines, `{(string.match(hull, "^%a+"))} L{level}: {table.concat(line, ", ")}`)
  end
  print("     raze: " .. table.concat(lines, "; "))
end)

suite:Case("a camp of a level has that level's packs, and a harder level's are worth more", function(t)
  local last = 0
  for level = 1, #Assault.PACKS do
    local every = camps(level)
    t.ok(#every >= 6, `level {level} can be {#every} camps`)
    local least, most = math.huge, 0
    for _, waves in every do
      local ships, bounty = Assault.Count(waves)
      t.ok(ships >= Assault.WAVES[level] and ships <= 3 * Assault.WAVES[level])
      local pay, credit = Assault.Pay(level, waves)
      t.eq(pay, math.floor(Assault.SHARE * bounty) + Assault.BASE * level)
      t.near(credit, 0.15 * level, 1e-9)
      least, most = math.min(least, pay), math.max(most, pay)
    end
    t.ok(least > last, `the least a level {level} camp pays is {least}, and the most the level below is {last}`)
    last = most
  end
end)

suite:Case("a camp is laid out in as many rooms as its level may have, each with a wave at least, and the job there is one of four", function(t)
  for level = 1, #Assault.PACKS do
    local rooms: { [number]: number } = {}
    local aims: { [string]: number } = {}
    for seed = 1, 400 do
      local ends, aim = Assault.Shape(Rng.For(seed, level, 7), level)
      rooms[#ends] = (rooms[#ends] or 0) + 1
      aims[aim] = (aims[aim] or 0) + 1
      -- Every room has a wave, in order, and the last wave is in the last room.
      t.eq(ends[#ends], Assault.WAVES[level])
      for index, last in ends do
        t.ok(last > (ends[index - 1] or 0), `level {level}: a room with no wave`)
      end
      t.ok(#ends <= Assault.ROOMS[level] and #ends <= Assault.WAVES[level], `level {level}: {#ends} rooms`)
    end
    -- One room at the first level, one or two at the second, two at the third, two or three at the fourth.
    local counts: { number } = {}
    for count = 1, 3 do
      counts[count] = if (rooms[count] or 0) > 0 then 1 else 0
    end
    t.eq(counts, ({ { 1, 0, 0 }, { 1, 1, 0 }, { 0, 1, 0 }, { 0, 1, 1 } })[level], `the rooms of level {level}`)
    -- To clear it three times in ten, to raze it two, and each of the others about a quarter.
    t.near((aims.clear or 0) / 400, 0.3, 0.08)
    t.near((aims.raze or 0) / 400, 0.2, 0.08)
    t.near((aims.chief or 0) / 400, 0.25, 0.08)
    t.near((aims.fetch or 0) / 400, 0.25, 0.08)
    -- What a job counts: the ships, what the camp is built of, the one chief, or ten crates a level.
    local waves = Assault.Plan(Rng.For(level, 11), level)
    t.eq({ Assault.Need("clear", level, waves), Assault.Need("raze", level, waves), Assault.Need("chief", level, waves),
      Assault.Need("fetch", level, waves) }, { (Assault.Count(waves)), #Assault.WORKS[level], 1, 10 * level })
    -- And a camp to raze pays for what it is built of beside its keepers.
    local _, standing = Assault.Count({ Assault.WORKS[level] })
    t.eq(Assault.Pay(level, waves, "raze") - Assault.Pay(level, waves), math.floor(0.6 * (select(2, Assault.Count(waves)) + standing))
      - math.floor(0.6 * select(2, Assault.Count(waves))))
  end
end)

return suite
