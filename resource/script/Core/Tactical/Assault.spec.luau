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
-- hardpoint, and then what there is room for of an afterburner, two
-- shield extenders, a plate, a repairer, a damage control, a
-- gyrostabiliser and another plate. Nothing custom, nothing tech 2, no
-- drones.
local function plain(hullId: string): { { string } }
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
  for _, module in { if size == "small" then "afterburner.1mn" else "afterburner." .. size, "shield.extender." .. size,
    "shield.extender." .. size, plate, "armor.repairer." .. size, "damage.control", "gyrostabilizer", plate } do
    table.insert(wanted, { module })
  end
  local types: { string } = {}
  local fit: { { string } } = {}
  for _, entry in wanted do
    assert(Modules.byId[entry[1]], `no module {entry[1]}`)
    table.insert(types, entry[1])
    if Attributes.Check(hull, types) then
      table.insert(fit, entry)
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
local function fight(hullId: string, level: number, orbit: number, waves: { { string } }, works: { string }?): (boolean, number)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  -- (the plain skills, every one at the level: not the crafts of a trade, which nothing is laid out on the
  -- footing that a pilot has, and which make all of this easier for one who does)
  for _, skill in Skills.list do
    if not skill.craft then
      state.skills[skill.id] = level
    end
  end
  local ship = Space.NewShip(state, hullId, "Test", "player", state.player.home)
  for _, entry in plain(hullId) do
    Items.Equip(state, ship.id, entry[1], entry[2])
    if entry[2] then
      Items.Add(state, entry[2], 3000, ship.id, "cargo")
    end
  end
  state.player.ship = ship.id
  local id = ship.id
  Core.Submit(game, { kind = "Undock", actor = id })
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
          if not on and (module.weapon or module.repair or module.boost) then
            Core.Submit(game, { kind = "ActivateModule", actor = id, item = item.id, target = if module.weapon then nearest else nil })
          end
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

suite:Case("a plain ship of the class a level is for comes through every camp of that level, and the class below it through few", function(t)
  local said: { string } = {}
  for level, ship in FOR do
    local wins, least, total = 0, 1, 0
    for _, waves in camps(level) do
      total += 1
      local won, left = fight(ship[1], ship[2], ship[3], waves)
      wins += if won then 1 else 0
      least = if won then math.min(least, left) else least
    end
    t.eq(wins, total, `a {Ships.byId[ship[1]].name} at level {level}`)
    t.ok(least > 0.08, `a {Ships.byId[ship[1]].name} came through a level {level} camp with {math.floor(least * 100)}% of itself`)
    table.insert(said, `{Ships.byId[ship[1]].class} L{level} {wins}/{total}, least {math.floor(least * 100)}%`)
    -- The class below: the level is not for it.
    local below = FOR[level - 1]
    if below then
      local theirs = 0
      for _, waves in camps(level) do
        theirs += if fight(below[1], below[2], below[3], waves) then 1 else 0
      end
      t.ok(theirs < total / 2, `a {Ships.byId[below[1]].name} came through {theirs} of {total} camps of level {level}`)
    end
  end
  print("     assault: " .. table.concat(said, "; "))
end)

-- (The job is what the camp is built of, which stands in its last room,
-- and whoever is in that room is on the pilot while they are at it: at
-- the worst every wave the last room can have, one after another, with
-- the emplacements firing all the while. Whoever flies is gone for
-- first, which is the way to do it.)
suite:Case("a plain ship of the class a level is for razes a camp of that level, with every wave its last room can have on them", function(t)
  local lines: { string } = {}
  for level = 1, #Assault.PACKS do
    local hull: string, skill: number, orbit: number = FOR[level][1], FOR[level][2], FOR[level][3]
    -- (the most waves a last room has: all of them but one for each room before it)
    local most = Assault.WAVES[level] - Assault.LEAST[level] + 1
    local every = camps(level)
    local won, tried, worst = 0, 0, 1
    -- (every other camp the level can be: enough to say)
    for index = 1, #every, 2 do
      local waves = table.move(every[index], #every[index] - most + 1, #every[index], 1, {})
      local ok, left = fight(hull, skill, orbit, waves, Assault.WORKS[level])
      tried += 1
      won += if ok then 1 else 0
      worst = math.min(worst, left)
    end
    table.insert(lines, `{(string.match(hull, "^%a+"))} L{level} {won}/{tried}, least {math.floor(worst * 100)}%`)
    t.eq(won, tried, `a {hull} with skills at {skill} should raze every level {level} camp`)
    t.ok(worst > 0.08, `a {hull} razed a level {level} camp with {math.floor(worst * 100)}% of itself`)
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
      t.eq(pay, math.floor(0.6 * bounty) + 5000 * level)
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
