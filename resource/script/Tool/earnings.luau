--!strict
-- The earnings report: what a pilot earns an hour at each kind of job,
-- measured by playing the jobs. A pilot takes a job at a station and
-- does it in the Core's own rules, as a player would with the commands
-- a player has: undocks, flies the gates, warps, fights, mines, loots,
-- docks and hands it in. The ticks from taking the job to being paid
-- for it are its time (a tick is a second of game time, at the
-- ordinary clock), and what it paid is its pay.
--
--   bin/ltcore Tool/earnings [--runs N] [--only LINE] [--out DIR]
--
-- LINE is one of courier, assault, defence, mining, daily. N jobs are
-- played of each kind and level (3 by default), at as many stations or
-- days as it takes to find them. With --out DIR, writes
-- DIR/earnings.txt as well (script/earnings does, into cache/earnings).
--
-- What it is and is not:
-- - Each level is flown in the ship it is for: the frigate, hauler or
--   freighter whose hold the courier level is laid out for, the class
--   the assault spec flies a camp level in (Tactical/Assault.spec), a
--   barge for mining contracts. Plain tech 1 fits, every plain skill at
--   a level, and the standing that opens the level and no more.
-- - The galaxy is peaceful: nobody roams the lanes, so there is no risk
--   in it and no time lost to it. A courier run is as quick as it can
--   be; a camp's own keepers are fought as they are.
-- - A courier run is counted one way (its cargo taken, carried and
--   handed over, in as many trips as the ship's hold needs): a pilot
--   who chains them takes the next where the last was handed in. The
--   trip home is not counted, and nor is time spent looking for work.
-- - Combat is counted from taking the job to handing it in at its
--   station: going out, every room, and coming back. Loot and salvage
--   are not counted.
-- - Jobs that pay in a module (one in five at a people's own station)
--   are passed over: their worth is about what the credits would be.
-- Nothing here decides anything: it says what the rules come to.

local Assault = require("@lt/Core/Tactical/Assault")
local Attributes = require("@lt/Core/Attributes")
local Constants = require("@lt/Core/Data/Constants")
local Core = require("@lt/Core/Api")
local Fits = require("@lt/Core/Fits")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Mining = require("@lt/Core/Tactical/Mining")
local Missions = require("@lt/Core/Assets/Missions")
local Modules = require("@lt/Core/Data/Modules")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Types = require("@lt/Core/Data/Types")

local Earnings = {}

-- The galaxy the jobs are played in: big enough for a freighter's run
-- of sixteen jumps that keeps out of lawless space.
local SYSTEMS = 600
-- The most ticks a job is given before it is given up as not done: six
-- hours of game time.
local LIMIT = 6 * 3600

-- The ship each level of a line is flown in, the skill level of its
-- pilot, and (for a fight) the range it orbits at. Combat is the
-- assault spec's ladder; the rest are mine.
local COMBAT: { { any } } = {
  { "frigate.akashi", 2, 2000 }, { "destroyer.nozomi", 3, 2500 }, { "cruiser.paestro", 4, 5000 }, { "battleship.owari", 4, 12000 },
}
local COURIER: { { any } } = {
  { "frigate.courier", 2 }, { "industrial.mizumushi", 3 }, { "industrial.mizumushi", 3 }, { "freighter.rhino", 4 },
}
local WILD: { any } = { "industrial.mizumushi", 3 }
local MINING: { { any } } = {
  { "barge.anteater", 2 }, { "barge.anteater", 3 }, { "barge.anteater", 4 }, { "barge.anteater", 4 },
}

export type Result = {
  line: string, level: number, what: string, hull: string,
  pay: number, ticks: number, ok: boolean, why: string, jumps: number, trips: number,
}

-- ---------------------------------------------------------------------
-- The pilot and their ship

local function trained(state: State.State, type: string)
  for _, need in Skills.Needs(type) do
    state.skills[need.skill] = math.max(state.skills[need.skill] or 0, need.level)
  end
end

-- A combat hull's plain fit, as the assault spec flies it: a gun or a
-- launcher of its size on every hardpoint, then a web, an afterburner,
-- a painter, two extenders, a plate, a repairer, a damage control, a
-- gyrostabiliser and another plate, as there is room. Tech 1.
local function combatFit(hullId: string): { { string } }
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
    table.insert(types, entry[1])
    if Attributes.Check(hull, types) then
      table.insert(fit, entry)
    else
      table.remove(types)
    end
  end
  return fit
end

-- A pilot with every plain skill at a level boards a new hull at their
-- home station, fitted: for a fight as above, for anything else its
-- standard fit (Core/Fits: a barge's strip miners, a hauler's tank).
-- With a bay of light drones where it has a bay.
local function board(game: Core.Game, hullId: string, skill: number, combat: boolean): number
  local state = game.state
  for _, entry in Skills.list do
    if not entry.craft then
      state.skills[entry.id] = skill
    end
  end
  trained(state, hullId)
  local ship = Space.NewShip(state, hullId, "Measured", "player", state.player.home)
  if combat then
    for _, entry in combatFit(hullId) do
      trained(state, entry[1])
      Items.Equip(state, ship.id, entry[1], entry[2])
      if entry[2] then
        Items.Add(state, entry[2], 3000, ship.id, "cargo")
      end
    end
  else
    for _, type in (Fits.Standard(Ships.byId[hullId])) do
      trained(state, type)
      Items.Equip(state, ship.id, type, Fits.Charge(type, Ships.byId[hullId]))
    end
  end
  local hull = Ships.byId[hullId]
  local drones = if (hull.drones or Ships.DRONES[hull.class] or 0) > 0 then math.floor((hull.bay or Ships.BAY[hull.class] or 0) / 5) else 0
  if drones > 0 then
    trained(state, "drone.light")
    Items.Add(state, "drone.light", drones, ship.id, "dronebay")
  end
  state.player.ship = ship.id
  return ship.id
end

-- ---------------------------------------------------------------------
-- Flying

-- One job's play: the game, the ship, and whether it has gone wrong.
type Play = { game: Core.Game, state: State.State, ship: number, start: number, lost: string?, jumps: number, trips: number }

local Lost = {}

local function fail(play: Play, why: string): never
  play.lost = why
  error(Lost)
end

local verbose = false
local engage: (play: Play, orbit: number, works: boolean) -> number

local function step(play: Play)
  if verbose and play.state.tick % 1000 == 0 then
    local ball = play.state.balls[play.ship]
    print("      tick", play.state.tick, os.clock(), ball and ball.system, ball and ball.mode, ball and ball.warp and ball.warp.stage)
  end
  Core.Step(play.game)
  Core.TakeEvents(play.game)
  local state = play.state
  if state.player.ship ~= play.ship or state.ships[play.ship] == nil then
    fail(play, "ship destroyed")
  elseif state.tick - play.start > LIMIT then
    fail(play, "out of time")
  end
end

local function submit(play: Play, command: State.Command): (boolean, string?)
  command.actor = play.ship
  return Core.Submit(play.game, command)
end

local function me(play: Play): State.Ball?
  return play.state.balls[play.ship]
end

local function docked(play: Play): number
  local ship = play.state.ships[play.ship]
  return if ship then ship.docked else 0
end

-- Step until 'done' says so, or fail with 'what' after 'ticks'.
local function waitFor(play: Play, what: string, ticks: number, done: () -> boolean)
  for _ = 1, ticks do
    if done() then
      return
    end
    step(play)
  end
  if not done() then
    fail(play, `stuck: {what}`)
  end
end

-- Ask until it is taken (a command refused while in warp, or as a gate
-- spits a ship out, is asked again the next tick).
local function insist(play: Play, what: string, command: State.Command)
  local why: string? = nil
  for _ = 1, 120 do
    local ok, reason = submit(play, table.clone(command))
    if ok then
      step(play)
      return
    end
    why = reason
    step(play)
  end
  fail(play, `{what} refused: {tostring(why)}`)
end

local function undock(play: Play)
  if docked(play) ~= 0 then
    insist(play, "undock", { kind = "Undock", actor = 0 })
    waitFor(play, "undocking", 120, function()
      return me(play) ~= nil
    end)
  end
end

-- The next system on the way to 'to': the way that keeps out of
-- lawless space where there is one (as a courier job's jumps are
-- counted), else the shortest.
local function nextSystem(state: State.State, from: number, to: number): number
  local reach = Missions.Reach(state.galaxy, to)
  local here = reach[from]
  if here then
    for _, next in state.galaxy.systems[from].neighbors do
      if reach[next] == here - 1 then
        return next
      end
    end
  end
  local route = Galaxy.Route(state.galaxy, from, to)
  assert(#route >= 2, "no way there")
  return route[2]
end

-- Fly to a system by its gates.
local function toSystem(play: Play, system: number)
  undock(play)
  local state = play.state
  while (me(play) :: State.Ball).system ~= system do
    local from = (me(play) :: State.Ball).system
    local next = nextSystem(state, from, system)
    local gate: number = 0
    for _, object in Space.Describe(state, from).objects do
      if object.kind == "gate" and object.variety ~= "passage" and object.to == next then
        gate = object.id
      end
    end
    if gate == 0 then
      fail(play, `no gate from {from} to {next}`)
    end
    insist(play, "jump", { kind = "Jump", actor = 0, target = gate })
    waitFor(play, "the jump", 1800, function()
      local ball = me(play)
      return ball ~= nil and ball.system == next
    end)
    play.jumps += 1
  end
end

-- Warp to something in this system (and wait out the warp); if it is
-- too close to warp to, fly to it.
local function warpTo(play: Play, target: number, range: number?)
  undock(play)
  local ok, why = submit(play, { kind = "WarpTo", actor = 0, target = target, range = range or 0 })
  if not ok then
    if why == "too close to warp" then
      submit(play, { kind = "Approach", actor = 0, target = target, range = range or 0 })
      return
    end
    -- (in warp already, or just out of a gate: once more, a tick on)
    step(play)
    insist(play, "warp", { kind = "WarpTo", actor = 0, target = target, range = range or 0 })
  else
    step(play)
  end
  waitFor(play, "the warp", 900, function()
    local ball = me(play)
    return ball ~= nil and ball.warp == nil
  end)
end

local function dockAt(play: Play, station: number)
  toSystem(play, Space.SystemOf(play.state, station))
  if docked(play) == station then
    return
  end
  -- (too near it to warp, and too far to fly in good time: out to
  -- something else in the system and back in, as a pilot would)
  local ball = me(play)
  local object = Space.Object(play.state, station)
  if ball and object and Space.Gap(ball :: any, object :: any) > 30000
    and Space.Distance(ball :: any, object :: any) < Constants.WARP_MIN_DISTANCE + 10000 then
    local out: number = 0
    for _, other in Space.Describe(play.state, ball.system).objects do
      if out == 0 and (other.kind == "planet" or other.kind == "gate" or other.kind == "station")
        and Space.Distance(other :: any, object :: any) > 2 * Constants.WARP_MIN_DISTANCE
        and Space.Distance(other :: any, ball :: any) > 2 * Constants.WARP_MIN_DISTANCE then
        out = other.id
      end
    end
    if out ~= 0 then
      warpTo(play, out, 0)
    end
  end
  insist(play, "dock", { kind = "Dock", actor = 0, target = station })
  waitFor(play, "docking", 1800, function()
    local b = me(play)
    if verbose and b and (play.state.tick % 300 == 0 or b.warp ~= nil) and object then
      print(string.format("      docking t%d: gap %.0f speed %.0f mode %s target %d station %d warp %s->%s intent %s", play.state.tick,
        Space.Gap(b :: any, object :: any), math.sqrt(b.vx * b.vx + b.vy * b.vy + b.vz * b.vz), b.mode, b.target, station,
        tostring(b.warp and b.warp.stage), tostring(b.warp and b.warp.target), tostring(b.intent and b.intent.target)))
    end
    -- (held there by a warp disruptor: it is fought off first)
    if b and b.warp == nil and b.vitals.scrambled then
      engage(play, 2500, false)
      return false
    end
    -- (held from warping when the order was given, it flies: once free, it warps)
    if b and b.warp == nil and b.mode == "approach" and object and not b.vitals.scrambled
      and Space.Distance(b :: any, object :: any) > Constants.WARP_MIN_DISTANCE + 10000 then
      submit(play, { kind = "Dock", actor = 0, target = station })
    end
    return docked(play) == station
  end)
end

-- ---------------------------------------------------------------------
-- Fighting

-- The ship a defence job is for (a rig or a tender) on the pilot's grid.
local function wardOf(play: Play): State.Ball?
  local state = play.state
  local mine = me(play) :: State.Ball
  for _, id in state.shipIds do
    local ball = state.balls[id]
    local kind = state.ships[id].type
    if ball and ball.system == mine.system and ball.grid == mine.grid
      and (string.sub(kind, 1, 14) == "convoy.tender." or string.sub(kind, 1, 10) == "works.rig.") then
      return ball
    end
  end
  return nil
end

-- The pilot goes for one hostile ship on their grid, as the scenarios'
-- fight helper does (App/game's Debug.Engage): what a camp is built of
-- first when the job is to raze it; else whoever is nearest the ward of
-- a defence job; else the nearest. Orbits it, locks it, and switches on
-- every weapon, repairer and booster; the drones go for it too. How
-- many hostiles there are on the grid.
engage = function(play: Play, orbit: number, works: boolean): number
  local game, state = play.game, play.state
  local mine = me(play)
  if mine == nil or mine.warp then
    return 0
  end
  -- (whoever flies before what stands, as the assault spec flies it: what
  -- a camp is built of shoots, but is not the job unless it is to be razed)
  local nearest: number, built: number, count = 0, 0, 0
  local least, leastBuilt = math.huge, math.huge
  local ward = wardOf(play)
  for _, entry in Core.Query.Overview(game) do
    local ball = state.balls[entry.id]
    if entry.hostile and entry.onGrid and ball then
      count += 1
      local from = ward or mine
      local gap = Space.Distance(ball :: any, from :: any)
      local ship = state.ships[entry.id]
      if ship and Ships.byId[ship.type].class == "works" then
        if gap < leastBuilt then
          built, leastBuilt = entry.id, gap
        end
      elseif gap < least then
        nearest, least = entry.id, gap
      end
    end
  end
  local target = if built ~= 0 and (works or nearest == 0) then built else nearest
  if target == 0 then
    return 0
  end
  if not (mine.mode == "orbit" and mine.target == target) then
    submit(play, { kind = "Orbit", actor = 0, target = target, range = orbit })
  end
  local targeted, locked = false, false
  for _, lock in mine.vitals.locks do
    if lock.target == target then
      targeted, locked = true, lock.locked
    end
  end
  if not targeted then
    submit(play, { kind = "LockTarget", actor = 0, target = target })
  elseif locked then
    for _, item in Items.Fitted(state, play.ship) do
      local module = Modules.byId[item.type]
      local on = false
      for _, running in mine.vitals.running do
        on = on or running.item == item.id
      end
      if not on and (module.weapon or (module.hex and not Modules.Friendly(module))) then
        submit(play, { kind = "ActivateModule", actor = 0, item = item.id, target = target })
      elseif not on and (module.repair or module.boost) then
        submit(play, { kind = "ActivateModule", actor = 0, item = item.id })
      end
    end
    submit(play, { kind = "LaunchDrones", actor = 0 })
    submit(play, { kind = "EngageDrones", actor = 0, target = target })
  end
  return count
end

-- How many of a type the pilot's ship holds.
local function holding(play: Play, type: string): number
  local count = 0
  for _, place in { "cargo", "orehold" } do
    for _, item in Items.In(play.state, play.ship, place) do
      count += if item.type == type then item.quantity else 0
    end
  end
  return count
end

-- Whether a combat job's work out there is done (Missions.Ready, but for being docked).
local function fought(play: Play, mission: State.Mission): boolean
  if mission.aim == "lost" then
    fail(play, if Missions.Escort(mission) then "tender destroyed" else "rig destroyed")
  elseif mission.aim == "fetch" then
    return holding(play, mission.type) >= mission.need
  end
  return mission.done >= mission.need
end

-- A tender the pilot is to see in, wherever it is now.
local function tender(play: Play): State.Ball?
  local state = play.state
  for _, id in state.shipIds do
    local ball = state.balls[id]
    if ball and string.sub(state.ships[id].type, 1, 14) == "convoy.tender." then
      return ball
    end
  end
  return nil
end

-- A combat job, out there: to its system, to its place, through each of
-- its rooms, and back.
local function fight(play: Play, mission: State.Mission, orbit: number)
  local state = play.state
  toSystem(play, mission.system)
  warpTo(play, mission.site)
  local quiet = 0
  while not fought(play, mission) do
    local mine = me(play) :: State.Ball
    local hostiles = engage(play, orbit, mission.aim == "raze")
    if verbose and state.tick % 15 == 0 then
      local v = mine.vitals
      local names: { string } = {}
      for _, entry in Core.Query.Overview(play.game) do
        if entry.hostile and entry.onGrid then
          local b = state.balls[entry.id]
          table.insert(names, string.format("%s@%.0f", state.ships[entry.id] and state.ships[entry.id].type or entry.kind,
            if b then Space.Distance(b :: any, mine :: any) else -1))
        end
      end
      print(string.format("      t%d grid %d wave %d done %d/%d  me %.0f/%.0f/%.0f mode %s locks %d running %d  %s", state.tick, mine.grid,
        mission.wave, mission.done, mission.need, v.shield, v.armor, v.hull, mine.mode, #v.locks, #v.running, table.concat(names, " ")))
    end
    local box = if mission.aim == "fetch" then state.wrecks[mission.mark] else nil
    if hostiles > 0 then
      quiet = 0
    elseif box and box.grid == mine.grid and mine.warp == nil then
      -- (what the camp took: to it, and looted)
      if not (submit(play, { kind = "Loot", actor = 0, target = box.id })) then
        if not (mine.mode == "approach" and mine.target == box.id) then
          submit(play, { kind = "Approach", actor = 0, target = box.id, range = 500 })
        end
      end
    elseif mine.warp == nil then
      quiet += 1
      local gate = Assault.Gate(state, mine.grid)
      local ward = tender(play)
      if gate and (Core.Validate(play.game, { kind = "Jump", actor = play.ship, target = gate.id })) then
        -- (on to the next room)
        local room = mine.grid
        submit(play, { kind = "Jump", actor = 0, target = gate.id })
        waitFor(play, "the way to the next room", 900, function()
          local ball = me(play)
          return ball ~= nil and ball.grid ~= room and ball.warp == nil
        end)
        quiet = 0
      elseif Missions.Convoy(mission) and ward and (ward.system ~= mine.system or ward.grid ~= mine.grid) and quiet > 3 then
        -- (after the tender: through the gate it took, or to where it is)
        if ward.system ~= mine.system then
          toSystem(play, ward.system)
        elseif ward.warp == nil then
          warpTo(play, ward.id, 2000)
        end
        quiet = 0
      elseif quiet > 300 and mine.grid ~= mission.site and not Assault.Tender(mission.aim) then
        warpTo(play, mission.site)
        quiet = 0
      end
    end
    step(play)
  end
  -- (whoever is left and holds the ship from warping is seen to first)
  waitFor(play, "getting free of a warp disruptor", 1800, function()
    local ball = me(play)
    if ball == nil or not ball.vitals.scrambled then
      return true
    end
    engage(play, orbit, false)
    return false
  end)
  dockAt(play, mission.station)
end

-- ---------------------------------------------------------------------
-- Mining

local function free(play: Play): number
  local state = play.state
  local stats = Items.ShipStats(state, play.ship)
  local oreMax, ore = Items.OreHold(state, play.ship)
  return math.max(stats.cargo - Items.CargoUsed(state, play.ship), oreMax - ore)
end

-- Everything in the ship's holds that is of a type, put in the hangar of the station it is docked at.
local function unload(play: Play, type: string)
  for _, place in { "cargo", "orehold" } do
    for _, item in Items.In(play.state, play.ship, place) do
      if item.type == type then
        submit(play, { kind = "MoveItems", actor = 0, item = item.id, to = "hangar" })
      end
    end
  end
end

local function mine(play: Play, mission: State.Mission)
  local state = play.state
  local station = mission.station
  local function ready(): boolean
    local ship = state.ships[play.ship]
    return ship.docked == station and (Missions.Ready(state, ship, mission))
  end
  while true do
    toSystem(play, mission.system)
    warpTo(play, mission.site)
    local rock: number = 0
    waitFor(play, "a full hold", 7200, function()
      engage(play, 1500, false)
      if free(play) < 1 then
        return true
      end
      local mineBall = me(play) :: State.Ball
      if verbose and state.tick % 300 == 0 then
        local o = if rock ~= 0 then Space.Object(state, rock) else nil
        print(string.format("      mining t%d rock %d gap %.0f left %.0f free %.0f mode %s locks %d running %d hull %.0f", state.tick, rock,
          if o then Space.Gap(mineBall :: any, o :: any) else -1, if o then Mining.Left(state, o) else -1, free(play), mineBall.mode,
          #mineBall.vitals.locks, #mineBall.vitals.running, mineBall.vitals.hull))
      end
      local object = if rock ~= 0 then Space.Object(state, rock) else nil
      if object == nil or Mining.Left(state, object) <= 0 then
        rock = 0
        local least = math.huge
        for _, other in Space.Describe(state, mineBall.system).objects do
          if other.kind == "asteroid" and other.site == mission.site and other.variety == mission.type and Mining.Left(state, other) > 0 then
            local gap = Space.Gap(mineBall :: any, other :: any)
            if gap < least then
              rock, least = other.id, gap
            end
          end
        end
        if rock == 0 then
          return true   -- (the pocket is mined out)
        end
        submit(play, { kind = "Approach", actor = 0, target = rock, range = 3000 })
        return false
      end
      -- (an approach ended by a fight in between is given again)
      if Space.Gap(mineBall :: any, object :: any) >= 9000 and not (mineBall.mode == "approach" and mineBall.target == rock) then
        submit(play, { kind = "Approach", actor = 0, target = rock, range = 3000 })
      end
      if Space.Gap(mineBall :: any, object :: any) < 9000 then
        submit(play, { kind = "LockTarget", actor = 0, target = rock })
        for _, item in Items.Fitted(state, play.ship) do
          local module = Modules.byId[item.type]
          if module.miner then
            submit(play, { kind = "ActivateModule", actor = 0, item = item.id, target = rock })
          end
        end
      end
      return false
    end)
    dockAt(play, station)
    unload(play, mission.type)
    step(play)
    play.trips += 1
    if ready() then
      return
    end
    undock(play)
  end
end

-- ---------------------------------------------------------------------
-- Carrying

local function carry(play: Play, mission: State.Mission)
  local state = play.state
  local home = mission.station
  while true do
    -- (what is left of the crates here, as much as the hold takes)
    local room = free(play)
    for _, item in Items.In(state, home, "hangar") do
      if item.type == mission.type and room >= 1 then
        local volume = Types.Info(item.type).volume
        local take = math.min(item.quantity, math.floor(room / volume))
        if take > 0 then
          insist(play, "load", { kind = "MoveItems", actor = 0, item = item.id, to = "cargo", quantity = take })
          room -= take * volume
        end
      end
    end
    dockAt(play, mission.to)
    unload(play, mission.type)
    step(play)
    play.trips += 1
    local ship = state.ships[play.ship]
    if (Missions.Ready(state, ship, mission)) then
      return
    end
    dockAt(play, home)
  end
end

-- ---------------------------------------------------------------------
-- The jobs

-- The kind of offer each line's levels are, and how it is played.
local function lineOf(offer: State.Mission): string
  if offer.slot <= Missions.OFFERS then
    return "daily"
  end
  return Missions.Line(offer)
end

-- Every station that gives jobs in a galaxy, the pilot's home first.
local function stationsOf(state: State.State): { number }
  local found: { number } = { state.player.home }
  for id in state.galaxy.systems do
    for _, object in Space.Describe(state, id).objects do
      if object.kind == "station" and object.id ~= state.player.home and state.starbases[object.id] == nil then
        table.insert(found, object.id)
      end
    end
  end
  return found
end

-- Play one job: the game is new, the pilot docked at its home with the
-- ship given. Returns what came of it.
local function play(game: Core.Game, offer: State.Mission, line: string, hull: string, orbit: number): Result
  local state = game.state
  local result: Result = {
    line = line, level = offer.level, what = if line == "daily" then offer.kind else offer.aim, hull = hull,
    pay = offer.reward, ticks = 0, ok = false, why = "", jumps = 0, trips = 0,
  }
  local session: Play = { game = game, state = state, ship = state.player.ship, start = state.tick, jumps = 0, trips = 0 }
  local ok, err = pcall(function()
    insist(session, "accept", { kind = "AcceptMission", actor = 0, what = offer.key })
    local mission = state.missions[state.missionIds[#state.missionIds]]
    if mission.kind == "courier" then
      carry(session, mission)
    elseif mission.kind == "mining" then
      mine(session, mission)
    else
      fight(session, mission, orbit)
    end
    local wallet = state.wallet
    insist(session, "hand in", { kind = "CompleteMission", actor = 0, target = mission.id })
    result.pay = state.wallet - wallet
  end)
  result.ticks = state.tick - session.start
  result.jumps, result.trips = session.jumps, session.trips
  if ok then
    result.ok = true
  else
    result.why = if err == Lost then session.lost or "lost" else tostring(err)
  end
  return result
end

-- Find offers of a line and level and play 'runs' of them, each in a
-- game of its own, from the home station (moved where the offer is).
local function measure(line: string, level: number, runs: number, kind: string?): { Result }
  local results: { Result } = {}
  local tried: { [string]: boolean } = {}
  for seed = 1, 12 do
    if #results >= runs then
      break
    end
    local scout = Core.New({ galaxySeed = 1, historySeed = seed, peaceful = true, systems = SYSTEMS })
    for _, station in stationsOf(scout.state) do
      if #results >= runs then
        break
      end
      local state = scout.state
      local faction = state.galaxy.systems[Space.SystemOf(state, station)].nearest
      -- (the standing that opens the level, and no more)
      state.standings[faction] = Assault.STANDING[level] or 0
      -- (the seventh agent's every third job is an escort and every sixth a convoy: the one wanted, next)
      state.holds[station] = if kind == "convoy" then Assault.CONVOYS - 1 elseif kind == "escort" then Assault.ESCORTS - 1 else 0
      for _, offer in Missions.Offers(state, station) do
        local mine = lineOf(offer) == line and (line == "daily" or offer.level == level) and offer.prize == nil
          and (kind == nil or offer.kind == kind or offer.aim == kind)
        if mine and not tried[`{seed}:{offer.key}`] and #results < runs then
          tried[`{seed}:{offer.key}`] = true
          -- A game of its own, the pilot at home at this station, in the level's ship.
          local game = Core.New({ galaxySeed = 1, historySeed = seed, peaceful = true, systems = SYSTEMS })
          local gs = game.state
          -- (its system described, as the scout's were, so that its station is there to be at)
          Space.Describe(gs, Space.SystemOf(gs, station))
          gs.standings[faction] = state.standings[faction]
          gs.holds[station] = state.holds[station]
          gs.player.home = station
          gs.ships[gs.player.ship].docked = station
          local hull: string, skill: number, orbit: number
          if line == "courier" then
            local ship = if offer.aim == "wild" then WILD else COURIER[level]
            hull, skill, orbit = ship[1], ship[2], 0
          elseif line == "mining" then
            hull, skill, orbit = MINING[level][1], MINING[level][2], 0
          elseif line == "daily" and offer.kind == "courier" then
            hull, skill, orbit = "industrial.mizumushi", 3, 0
          else
            local ship = COMBAT[math.max(1, level)]
            hull, skill, orbit = ship[1], ship[2], ship[3]
          end
          board(game, hull, skill, line ~= "courier" and line ~= "mining" and not (line == "daily" and offer.kind == "courier"))
          gs.ships[gs.player.ship].docked = station
          -- (the same offer, in this game: by its key)
          local same: State.Mission? = nil
          for _, other in Missions.Offers(gs, station) do
            if other.key == offer.key then
              same = other
            end
          end
          if verbose then
            print(`    playing {offer.key} at {station}: {same ~= nil}`)
          end
          if same then
            local result = play(game, same, line, hull, orbit)
            if verbose then
              print(string.format("    %s %d %s seed %d at %d: %s, %d ticks, %d paid, %d jumps, %d trips", line, level, result.what, seed,
                station, if result.ok then "done" else result.why, result.ticks, result.pay, result.jumps, result.trips))
            end
            table.insert(results, result)
          end
        end
      end
    end
  end
  return results
end

-- ---------------------------------------------------------------------
-- The report

local function millions(n: number): string
  return string.format("%.2fM", n / 1e6)
end

-- What is to be measured: each line's levels, and the kinds within a line worth telling apart.
local PLAN: { { line: string, level: number, kind: string? } } = {
  { line = "courier", level = 1 }, { line = "courier", level = 2 }, { line = "courier", level = 3 },
  { line = "courier", level = 4, kind = "run" }, { line = "courier", level = 4, kind = "wild" },
  { line = "assault", level = 1 }, { line = "assault", level = 2 }, { line = "assault", level = 3 }, { line = "assault", level = 4 },
  { line = "defence", level = 1, kind = "hold" }, { line = "defence", level = 2, kind = "hold" },
  { line = "defence", level = 3, kind = "hold" }, { line = "defence", level = 4, kind = "hold" },
  { line = "defence", level = 1, kind = "escort" }, { line = "defence", level = 2, kind = "escort" },
  { line = "defence", level = 3, kind = "escort" }, { line = "defence", level = 4, kind = "escort" },
  { line = "defence", level = 2, kind = "convoy" }, { line = "defence", level = 3, kind = "convoy" },
  { line = "defence", level = 4, kind = "convoy" },
  { line = "mining", level = 1 }, { line = "mining", level = 2 }, { line = "mining", level = 3 }, { line = "mining", level = 4 },
  { line = "daily", level = 0, kind = "courier" },
}

function Earnings.Main(args: { string }): number
  local runs, only, out = 3, "", ""
  for index, arg in args do
    if arg == "--runs" then
      runs = tonumber(args[index + 1]) or runs
    elseif arg == "--only" then
      only = args[index + 1] or ""
    elseif arg == "--verbose" then
      verbose = true
    elseif arg == "--out" then
      out = args[index + 1] or ""
    end
  end
  local lines: { string } = {}
  local function say(text: string)
    print(text)
    table.insert(lines, text)
  end
  say(string.format("%-8s %-2s %-7s %-22s %4s %10s %8s %10s  %s", "line", "lv", "kind", "ship", "done", "pay", "minutes", "per hour", "notes"))
  for _, entry in PLAN do
    if only == "" or only == entry.line then
      local results = measure(entry.line, entry.level, runs, entry.kind)
      local pay, ticks, done, jumps, trips = 0, 0, 0, 0, 0
      local why: { string } = {}
      local hull = ""
      for _, result in results do
        hull = result.hull
        if result.ok then
          done += 1
          pay += result.pay
          ticks += result.ticks
          jumps += result.jumps
          trips += result.trips
        else
          table.insert(why, result.why)
        end
      end
      local name = if hull ~= "" then Ships.byId[hull].name else "-"
      local notes: { string } = {}
      if done > 0 then
        table.insert(notes, string.format("%.1f jumps", jumps / done))
        if trips > done then
          table.insert(notes, string.format("%.1f trips", trips / done))
        end
      end
      if #why > 0 then
        table.insert(notes, "failed: " .. table.concat(why, "; "))
      end
      if #results == 0 then
        table.insert(notes, "no such job found")
      end
      local minutes = if done > 0 then ticks / done / 60 else 0
      local hourly = if ticks > 0 then pay / (ticks / 3600) else 0
      say(string.format("%-8s %-2s %-7s %-22s %2d/%-1d %10s %8.1f %10s  %s", entry.line, if entry.level > 0 then tostring(entry.level) else "-",
        entry.kind or "", name, done, #results, if done > 0 then millions(pay / done) else "-", minutes,
        if done > 0 then millions(hourly) else "-", table.concat(notes, ", ")))
    end
  end
  -- Jobs that ask for goods to be brought, which the market where they
  -- are handed in may sell: what the goods cost there, beside the pay.
  if only == "" or only == "bought" then
    say("")
    say("Jobs filled from the station's own market (bought there and handed straight in):")
    say(string.format("%-8s %-2s %-24s %7s %10s %10s %10s", "line", "lv", "goods", "units", "pay", "cost", "profit"))
    local scout = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true, systems = SYSTEMS })
    local shown: { [string]: number } = {}
    for _, station in stationsOf(scout.state) do
      local state = scout.state
      state.standings[state.galaxy.systems[Space.SystemOf(state, station)].nearest] = 5
      for _, offer in Missions.Offers(state, station) do
        local tag = `{offer.kind}{offer.level}`
        if (offer.kind == "supply" or offer.kind == "mining") and offer.prize == nil and (shown[tag] or 0) < 2 then
          local cost = Core.Query.BuyCost(scout, station, offer.type, offer.need)
          if cost then
            shown[tag] = (shown[tag] or 0) + 1
            say(string.format("%-8s %-2s %-24s %7d %10s %10s %10s", offer.kind, if offer.level > 0 then tostring(offer.level) else "-",
              Types.Info(offer.type).name, offer.need, millions(offer.reward), millions(cost), millions(offer.reward - cost)))
          end
        end
      end
    end
  end
  if out ~= "" then
    local text = table.concat(lines, "\n") .. "\n"
    Host.WriteFile(out .. "/earnings.txt", text, #text)
    print(`earnings: wrote {out}/earnings.txt`)
  end
  return 0
end

return Earnings
