--!strict
-- Hired pilots (Tactical/Fleet).

local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Fleet = require("@lt/Core/Tactical/Fleet")
local Items = require("@lt/Core/Assets/Items")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Fleet")

local function submit(game: Core.Game, command: State.Command): (boolean, string?)
  command.actor = game.state.player.ship
  local ok, why = Core.Submit(game, command)
  Core.Step(game)
  return ok, why
end

local function refused(game: Core.Game, command: State.Command): string?
  command.actor = game.state.player.ship
  local ok, why = Core.Validate(game, command)
  return if ok then "(accepted)" else why
end

local function steps(game: Core.Game, count: number)
  for _ = 1, count do
    Core.Step(game)
  end
end

-- Step until something holds, as many as 'limit' ticks. Whether it did.
local function waitFor(game: Core.Game, limit: number, holds: () -> boolean): boolean
  for _ = 1, limit do
    if holds() then
      return true
    end
    Core.Step(game)
  end
  return holds()
end

-- A game with money in the wallet and a second ship in the hangar: a
-- hull with small autocannons in every turret it has room for.
local function docked(hull: string?, systems: number?): (Core.Game, State.Ship)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true, systems = systems })
  local state = game.state
  state.wallet = 10000000
  local second = Space.NewShip(state, hull or "frigate.courier", "Second", "player", state.player.home)
  for _ = 1, math.min(4, Ships.byId[second.type].turrets) do
    Items.Equip(state, second.id, "autocannon.small", "ammo.emp")
  end
  Items.Add(state, "ammo.emp", 4000, second.id, "cargo")
  return game, second
end

-- Hire the first of the home station's candidates, as a pilot of a
-- grade (whatever grade they were), and give them the second ship.
local function hired(game: Core.Game, second: State.Ship?, grade: number?): State.Wingman
  local state = game.state
  local candidates = Core.Query.Candidates(game, state.player.home)
  assert(submit(game, { kind = "HirePilot", actor = 0, what = candidates[1].key }))
  local wing = state.fleet[state.fleetIds[#state.fleetIds]]
  wing.skill = grade or wing.skill
  if second then
    assert(submit(game, { kind = "AssignShip", actor = 0, pilot = wing.id, target = second.id }))
  end
  return wing
end

-- Undock the player and the hired pilot and put both in open space,
-- away from the station (whose batteries would do the fighting).
local function adrift(game: Core.Game, second: State.Ship): (State.Ball, State.Ball)
  local state = game.state
  assert(submit(game, { kind = "Undock", actor = 0 }))
  steps(game, 5)
  local me, theirs = state.balls[state.player.ship], state.balls[second.id]
  for _, ball in { me, theirs } do
    ball.x += 4e6
    ball.vx, ball.vy, ball.vz = 0, 0, 0
    Space.AssignGrid(state, ball)
  end
  assert(submit(game, { kind = "Stop", actor = 0 }))
  steps(game, 20)
  return me, theirs
end

local function belt(game: Core.Game, system: number): number
  for _, object in Core.Query.Objects(game, system) do
    if object.kind == "belt" then
      return object.id
    end
  end
  error("no belt")
end

suite:Case("a station has pilots looking for work, the same all day; one is hired for a fee, as many as Leadership commands", function(t)
  local game = docked()
  local state = game.state
  local home = state.player.home
  local candidates, most = Core.Query.Candidates(game, home)
  t.eq({ #candidates, most }, { Fleet.CANDIDATES, 1 })
  for _, found in candidates do
    t.ok(found.skill >= 1 and found.skill <= 4 and #found.name > 3)
    t.eq({ found.wage, found.fee }, { Fleet.Wage(found.skill), Fleet.Fee(found.skill) })
  end
  steps(game, 500)
  t.eq(Core.Query.Candidates(game, home), candidates)
  t.eq(refused(game, { kind = "HirePilot", actor = 0, what = "nobody" }), "nobody of that name is looking for work here")
  state.wallet = candidates[1].fee - 1
  t.eq(refused(game, { kind = "HirePilot", actor = 0, what = candidates[1].key }), "not enough credits")
  state.wallet = 10000000
  t.ok((submit(game, { kind = "HirePilot", actor = 0, what = candidates[1].key })))
  t.eq(state.wallet, 10000000 - candidates[1].fee)
  local row = Core.Query.Fleet(game)[1]
  t.eq({ row.name, row.skill, row.wage, row.where, row.order } :: { any },
    { candidates[1].name, candidates[1].skill, candidates[1].wage, "no ship", "follow" } :: { any })
  -- Somebody hired is no longer looking, and one pilot is all that Leadership 1 commands.
  local left = Core.Query.Candidates(game, home)
  t.eq(#left, Fleet.CANDIDATES - 1)
  t.eq(refused(game, { kind = "HirePilot", actor = 0, what = candidates[1].key }), "nobody of that name is looking for work here")
  t.eq(refused(game, { kind = "HirePilot", actor = 0, what = left[1].key }), "Leadership 1 commands no more pilots")
  state.skills.leadership = 2
  t.ok((submit(game, { kind = "HirePilot", actor = 0, what = left[1].key })))
  t.eq(#Core.Query.Fleet(game), 2)
  -- Tomorrow there are others.
  steps(game, Fleet.DAY)
  t.eq(#Core.Query.Candidates(game, home), Fleet.CANDIDATES)
  -- Nobody is hired from space.
  local out = docked()
  t.ok((submit(out, { kind = "Undock", actor = 0 })))
  t.eq(refused(out, { kind = "HirePilot", actor = 0, what = "x" }), "not docked")
end)

suite:Case("a hired pilot is given a ship of the player's that is docked there and that they are good enough to fly", function(t)
  local game, second = docked()
  local state = game.state
  local wing = hired(game, nil, 1)
  t.eq(refused(game, { kind = "AssignShip", actor = 0, pilot = 99, target = second.id }), "no such pilot")
  t.eq(refused(game, { kind = "AssignShip", actor = 0, pilot = wing.id, target = state.player.ship }), "that is the ship you are flying")
  t.eq(refused(game, { kind = "AssignShip", actor = 0, pilot = wing.id, target = 0 }), `{wing.name} has no ship`)
  -- A cruiser wants a better pilot, and so does a module that wants a skill at 2.
  local cruiser = Space.NewShip(state, "cruiser.cuirass", "Big", "player", state.player.home)
  t.eq(refused(game, { kind = "AssignShip", actor = 0, pilot = wing.id, target = cruiser.id }),
    `{wing.name} is grade 1: a cruiser wants a pilot of grade 3`)
  local hard = Space.NewShip(state, "frigate.courier", "Hard", "player", state.player.home)
  Items.Equip(state, hard.id, "shield.hardener", nil)
  t.eq(refused(game, { kind = "AssignShip", actor = 0, pilot = wing.id, target = hard.id }), `{wing.name} needs Shield Operation 2`)
  t.eq(Core.Query.CanFly(game, wing.id, hard.id), "needs Shield Operation 2")
  t.eq(Core.Query.CanFly(game, wing.id, second.id), nil)
  t.ok((submit(game, { kind = "AssignShip", actor = 0, pilot = wing.id, target = second.id })))
  t.eq({ wing.ship, second.pilot }, { second.id, wing.id })
  t.eq(refused(game, { kind = "AssignShip", actor = 0, pilot = wing.id, target = second.id }), `{wing.name} flies it already`)
  -- The ship has its pilot's skills, not the player's, and the player cannot take it out.
  t.eq(Items.Levels(state, second.id), Items.HIRED[1])
  t.eq(refused(game, { kind = "BoardShip", actor = 0, target = second.id }), "a hired pilot flies that ship")
  -- Given another, they leave the first; taken off, they have none.
  wing.skill = 3
  t.ok((submit(game, { kind = "AssignShip", actor = 0, pilot = wing.id, target = cruiser.id })))
  t.eq({ wing.ship, second.pilot, cruiser.pilot }, { cruiser.id, 0, wing.id })
  t.ok((submit(game, { kind = "AssignShip", actor = 0, pilot = wing.id, target = 0 })))
  t.eq({ wing.ship, cruiser.pilot }, { 0, 0 })
  -- Dismissed, they are gone and the ship is nobody's.
  t.ok((submit(game, { kind = "AssignShip", actor = 0, pilot = wing.id, target = second.id })))
  t.ok((submit(game, { kind = "DismissPilot", actor = 0, pilot = wing.id })))
  t.eq({ #state.fleetIds, second.pilot }, { 0, 0 })
end)

suite:Case("a hired pilot undocks with the player, warps where the player warps and docks when the player does", function(t)
  local game, second = docked()
  local state = game.state
  local wing = hired(game, second)
  steps(game, 5)
  t.eq(second.docked, state.player.home)
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  t.ok(waitFor(game, 5, function()
    return state.balls[second.id] ~= nil
  end), "the hired pilot stayed docked")
  local me = state.balls[state.player.ship]
  -- With nothing to fight they keep station on the player.
  steps(game, 40)
  t.eq({ state.balls[second.id].mode, state.balls[second.id].target } :: { any }, { "keep", me.id } :: { any })
  local row = Core.Query.Fleet(game)[1]
  t.eq({ row.where, row.near, row.shipName } :: { any }, { "with you", true, "Second" } :: { any })
  t.ok(Core.Query.Overview(game)[1].own or Core.Query.Overview(game)[2].own, "the overview does not know a hired pilot's ship for the player's own")
  -- The player warps to a belt: so do they.
  local rocks = belt(game, 1)
  t.ok((submit(game, { kind = "WarpTo", actor = 0, target = rocks, range = 10000 })))
  t.ok(waitFor(game, 20, function()
    local theirs = state.balls[second.id].warp
    return theirs ~= nil and theirs.target == rocks
  end), "the hired pilot did not warp after the player")
  t.ok(waitFor(game, 400, function()
    local ball = state.balls[second.id]
    return me.grid == rocks and ball.grid == rocks
  end), "the hired pilot did not arrive at the belt")
  t.ok(Space.Distance(me :: any, state.balls[second.id] :: any) < 30000, "the hired pilot arrived a long way from the player")
  -- The player goes home and docks: so do they.
  t.ok((submit(game, { kind = "Dock", actor = 0, target = state.player.home })))
  t.ok(waitFor(game, 600, function()
    return state.ships[state.player.ship].docked == state.player.home and second.docked == state.player.home
  end), "the hired pilot did not dock with the player")
  t.eq(Core.Query.Fleet(game)[1].where, `docked at {(Space.Object(state, state.player.home) :: System.Object).name}`)
  -- (and stays in while the player does)
  steps(game, 20)
  t.eq(second.docked, state.player.home)
  t.eq(wing.ship, second.id)
end)

suite:Case("a hired pilot jumps where the player jumps, and one left behind makes their own way after", function(t)
  local game, second = docked(nil, 3)
  local state = game.state
  hired(game, second)
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  steps(game, 5)
  local next = state.galaxy.systems[1].neighbors[1]
  local gate = System.GateTo(Space.Describe(state, 1), next) :: System.Object
  t.ok((submit(game, { kind = "Jump", actor = 0, target = gate.id })))
  t.ok(waitFor(game, 800, function()
    local me, ball = state.balls[state.player.ship], state.balls[second.id]
    return me.system == next and ball ~= nil and ball.system == next and ball.grid == me.grid
  end), "the hired pilot did not jump after the player")
  -- Left a system behind (put back by hand), they come after by the gate.
  local ball = state.balls[second.id]
  local home = Space.Object(state, state.player.home) :: System.Object
  ball.system, ball.x, ball.y, ball.z = 1, home.x + 2e6, home.y, home.z
  ball.warp, ball.intent = nil, nil
  Space.AssignGrid(state, ball)
  t.ok(waitFor(game, 1000, function()
    local me = state.balls[state.player.ship]
    return ball.system == next and ball.grid == me.grid
  end), "the hired pilot did not catch up from the last system")
end)

suite:Case("a hired pilot fights whoever is after the fleet and what they are pointed at, and the kill is the player's", function(t)
  local game, second = docked("destroyer.jackal")
  local state = game.state
  local wing = hired(game, second, 2)
  local me, theirs = adrift(game, second)
  -- A scout turns up and goes for somebody of the fleet.
  local scout = Pirates.Spawn(state, Pirates.SCOUT, me.system, me.x + 6000, me.y, me.z, me.grid)
  local wallet = state.wallet
  t.ok(waitFor(game, 20, function()
    return theirs.mode == "orbit" and theirs.target == scout.id
  end), "the hired pilot did not go for the pirate")
  local prey = state.pilots[scout.id].prey
  t.ok(prey == me.id or prey == theirs.id)
  t.ok(waitFor(game, 600, function()
    return state.balls[scout.id] == nil
  end), "a destroyer did not kill a scout")
  t.eq(state.wallet - wallet, Pirates.SCOUT.bounty)
  steps(game, 5)
  t.eq({ theirs.mode, theirs.target, #theirs.vitals.locks } :: { any }, { "keep", me.id, 0 } :: { any })
  -- Pointed at somebody who is no pirate, they fire, and the player is marked for it.
  local trader = Space.NewShip(state, "industrial.hauler", "Trader", "civilian", 0)
  local hauler = Space.Launch(state, trader, me.system, me.x + 3000, me.y, me.z)
  t.eq(refused(game, { kind = "FleetOrder", actor = 0, what = "engage", target = theirs.id }), "no such target")
  t.eq(refused(game, { kind = "FleetOrder", actor = 0, what = "dance" }), "no such order")
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "engage", target = hauler.id })))
  t.eq({ wing.target, state.player.marked }, { hauler.id, 0 })
  t.ok(waitFor(game, 60, function()
    return state.player.marked > state.tick
  end), "a hired pilot fired on a trader and nobody was marked")
  -- Called off, they go back to keeping station.
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "follow" })))
  steps(game, 3)
  t.eq({ wing.target, theirs.mode, theirs.target } :: { any }, { 0, "keep", me.id } :: { any })
end)

suite:Case("pirates shoot at a hired pilot's ship and at drones; a ship lost is insured and its pilot is back on the list", function(t)
  local game, second = docked()
  local state = game.state
  -- (nothing to shoot back with)
  for _, item in Items.In(state, second.id, nil) do
    Items.Take(state, item, item.quantity)
  end
  local wing = hired(game, second)
  local me, theirs = adrift(game, second)
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "engage", target = 0 })) == false)
  -- A pack arrives on the far side of the hired pilot.
  theirs.x = me.x + 2000
  local pirates: { State.Ball } = {}
  for index = 1, 3 do
    table.insert(pirates, Pirates.Spawn(state, Pirates.kindById["raider"], me.system, theirs.x + 3000 + 500 * index, theirs.y, theirs.z, me.grid))
  end
  -- Each goes for the nearer ship of the pilot's side, which is the hired pilot's.
  steps(game, 2)
  for _, pirate in pirates do
    t.eq(state.pilots[pirate.id].prey, theirs.id)
  end
  local wallet = state.wallet
  local lost = false
  t.ok(waitFor(game, 900, function()
    for _, event in Core.TakeEvents(game) do
      lost = lost or (event.kind == "WingmanLost" and event.pilot == wing.id)
    end
    return lost
  end), "three raiders did not destroy an unarmed frigate")
  t.eq({ state.ships[second.id], wing.ship } :: { any }, { nil, 0 } :: { any })
  t.eq(state.wallet - wallet, math.floor(Ships.byId["frigate.courier"].basePrice * 0.4))
  t.eq(Core.Query.Fleet(game)[1].where, "no ship")
  -- With it gone they turn on the player, whose drone one of them may go for instead.
  steps(game, 3)
  for _, pirate in pirates do
    t.eq(state.pilots[pirate.id].prey, me.id)
  end
end)

suite:Case("some of a pack go for a drone rather than its owner, and a drone destroyed leaves nothing", function(t)
  local game = docked()
  local state = game.state
  state.skills.drones = 5
  Items.Add(state, "drone.light", 1, state.player.ship, "dronebay")
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  steps(game, 5)
  local me = state.balls[state.player.ship]
  me.x += 4e6
  Space.AssignGrid(state, me)
  t.ok((submit(game, { kind = "LaunchDrones", actor = 0 })))
  local drone = state.balls[state.droneIds[1]]
  local after: { [number]: number } = {}
  local hunters: { State.Ball } = {}
  for index = 1, 12 do
    local pirate = Pirates.Spawn(state, Pirates.SCOUT, me.system, me.x + 4000 + 300 * index, me.y, me.z, me.grid)
    table.insert(hunters, pirate)
  end
  steps(game, 2)
  for _, pirate in hunters do
    local prey = state.pilots[pirate.id].prey
    after[prey] = (after[prey] or 0) + 1
  end
  t.eq((after[me.id] or 0) + (after[drone.id] or 0), 12)
  t.ok((after[drone.id] or 0) >= 1, "nobody went for the drone")
  t.ok((after[me.id] or 0) > (after[drone.id] or 0), `most of a pack should go for the ship: {after[me.id] or 0} did, and {after[drone.id] or 0} for the drone`)
  local wrecks = #state.wreckIds
  local gone = false
  t.ok(waitFor(game, 600, function()
    for _, event in Core.TakeEvents(game) do
      gone = gone or (event.kind == "DroneLost" and event.destroyed == true)
    end
    return gone
  end), "the pirates did not destroy the drone")
  t.eq({ #state.droneIds, Core.Query.Drones(game).out }, { 0, 0 })
  t.ok(#state.wreckIds <= wrecks, "a drone left a wreck")
end)

suite:Case("told to stay, a hired pilot docks at the nearest station and waits there", function(t)
  local game, second = docked()
  local state = game.state
  local wing = hired(game, second)
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  steps(game, 20)
  t.ok(state.balls[second.id] ~= nil)
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "stay", pilot = wing.id })))
  t.ok(waitFor(game, 300, function()
    return second.docked ~= 0
  end), "the hired pilot did not dock")
  -- The player leaves for a belt, and they stay in.
  t.ok((submit(game, { kind = "WarpTo", actor = 0, target = belt(game, 1) })))
  steps(game, 120)
  t.ok(second.docked ~= 0)
  t.eq(refused(game, { kind = "DismissPilot", actor = 0, pilot = wing.id }), "(accepted)")
  -- Told to follow again, they come out and after the player.
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "follow" })))
  t.ok(waitFor(game, 600, function()
    local me, ball = state.balls[state.player.ship], state.balls[second.id]
    return ball ~= nil and me.grid ~= 0 and ball.grid == me.grid
  end), "the hired pilot did not come after the player")
  t.eq(refused(game, { kind = "DismissPilot", actor = 0, pilot = wing.id }), `{wing.name} is out flying`)
end)

suite:Case("a remote repairer puts shield or armour back on a locked ship in reach, a cycle at a time", function(t)
  local game, second = docked()
  local state = game.state
  -- (it wants the skill to fit)
  local item = Items.Add(state, "remote.shield.small", 1, state.player.home, "hangar")
  t.eq(refused(game, { kind = "Fit", actor = 0, item = item.id }), "needs Remote Repair 1")
  state.skills["remote.repair"] = 1
  -- (a Courier has two high slots, and a gun in each: one comes out)
  local gun = Items.Fitted(state, state.player.ship)[1]
  Items.Take(state, gun, 1)
  t.ok((submit(game, { kind = "Fit", actor = 0, item = item.id })))
  hired(game, second)
  local me, theirs = adrift(game, second)
  theirs.vitals.shield = 20
  t.ok((submit(game, { kind = "LockTarget", actor = 0, target = theirs.id })))
  t.ok(waitFor(game, 30, function()
    return me.vitals.locks[1] ~= nil and me.vitals.locks[1].locked
  end))
  local fitted = Items.Fitted(state, me.id)
  local remote = fitted[#fitted]
  for _, each in fitted do
    if each.type == "remote.shield.small" then
      remote = each
    end
  end
  local capacitor = me.vitals.capacitor
  local before = theirs.vitals.shield
  t.ok((submit(game, { kind = "ActivateModule", actor = 0, item = remote.id, target = theirs.id })))
  steps(game, 1)
  -- One cycle at once: fifty points for thirty of capacitor (the shield's own recharge aside).
  t.ok(theirs.vitals.shield >= before + 50 and theirs.vitals.shield < before + 60, `the shield went from {before} to {theirs.vitals.shield}`)
  t.ok(me.vitals.capacitor <= capacitor - 30 + 5)
  local mended = 0
  for _, event in Core.TakeEvents(game) do
    if event.kind == "Mended" and event.target == theirs.id and event.layer == "shield" then
      mended += event.amount
    end
  end
  t.eq(mended, 50)
  -- It never puts back more than there is room for.
  steps(game, 60)
  t.eq(theirs.vitals.shield, theirs.vitals.shieldMax)
  -- Out of reach, it stops.
  theirs.vitals.shield = 20
  theirs.x += 12000
  steps(game, 6)
  t.eq(#me.vitals.running, 0)
  -- And there are three sizes of each kind, the bigger wanting more of the skill.
  local Modules = require("@lt/Core/Data/Modules")
  for _, kind in { "shield", "armor" } do
    local small, large = Modules.byId[`remote.{kind}.small`], Modules.byId[`remote.{kind}.large`]
    t.ok(Modules.Mends(small) and Modules.Mends(large) and Modules.Mends(Modules.byId[`remote.{kind}.medium`]))
    t.ok((large.hex :: any).strength > 5 * (small.hex :: any).strength and (large.hex :: any).range > (small.hex :: any).range)
    t.eq((large.requires :: any)[1], { skill = "remote.repair", level = 4 })
  end
  t.ok(not Modules.Mends(Modules.byId["web.stasis"]))
end)

suite:Case("a hired pilot with a remote repairer mends whoever of the fleet is hurt, and stops when they are whole", function(t)
  local game, second = docked("destroyer.jackal")
  local state = game.state
  Items.Equip(state, second.id, "remote.armor.small", nil)
  hired(game, second, 2)
  local me, theirs = adrift(game, second)
  steps(game, 10)
  t.eq({ #theirs.vitals.locks, #theirs.vitals.running }, { 0, 0 })
  -- The player's armour is knocked about: the pilot locks them and sets to.
  me.vitals.armor = me.vitals.armorMax * 0.3
  t.ok(waitFor(game, 40, function()
    return #theirs.vitals.running == 1 and theirs.vitals.running[1].target == me.id
  end), "the hired pilot did not start mending")
  t.ok(waitFor(game, 300, function()
    return me.vitals.armor >= 0.99 * me.vitals.armorMax
  end), "the armour was not mended")
  -- Whole again: the repairer comes off, and so does the lock.
  t.ok(waitFor(game, 20, function()
    return #theirs.vitals.running == 0 and #theirs.vitals.locks == 0
  end), "the hired pilot went on mending a whole ship")
  t.eq({ theirs.mode, theirs.target } :: { any }, { "keep", me.id } :: { any })
end)

-- A game with a hired pilot in a Prospector with two mining lasers, out
-- at the first belt with the player.
local function atBelt(): (Core.Game, State.Wingman, State.Ship, number)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  state.wallet = 10000000
  local second = Space.NewShip(state, "frigate.prospector", "Digger", "player", state.player.home)
  Items.Equip(state, second.id, "miner.small", nil)
  Items.Equip(state, second.id, "miner.small", nil)
  local wing = hired(game, second, 2)
  local rocks = belt(game, 1)
  assert(submit(game, { kind = "Undock", actor = 0 }))
  steps(game, 5)
  assert(submit(game, { kind = "WarpTo", actor = 0, target = rocks }))
  assert(waitFor(game, 600, function()
    local me, ball = state.balls[state.player.ship], state.balls[second.id]
    return me.grid == rocks and ball ~= nil and ball.grid == rocks
  end), "the two did not get to the belt")
  return game, wing, second, rocks
end

local function oreIn(game: Core.Game, holder: number, place: string): number
  local units = 0
  for _, item in Items.In(game.state, holder, place) do
    if string.sub(item.type, 1, 4) == "ore." then
      units += item.quantity
    end
  end
  return units
end

suite:Case("a hired pilot with a mining laser is set to mine a belt: the hold is filled, taken in to the nearest station, and they go back", function(t)
  local game, wing, second, rocks = atBelt()
  local state = game.state
  local home = state.player.home
  local before = oreIn(game, home, "hangar")
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "mine" })))
  t.eq({ wing.order, wing.post } :: { any }, { "mine", rocks } :: { any })
  local base = wing.base
  t.ok((Space.Object(state, base) :: System.Object).kind == "station")
  t.eq(Core.Query.Fleet(game)[1].doing, "mining")
  -- They go to a rock and cut it.
  t.ok(waitFor(game, 300, function()
    return oreIn(game, second.id, "cargo") > 0
  end), "nothing was mined")
  -- The player goes home and stays in. The pilot carries on: a hold of ore is brought in.
  t.ok((submit(game, { kind = "Dock", actor = 0, target = home })))
  local delivered = 0
  t.ok(waitFor(game, 4000, function()
    for _, event in Core.TakeEvents(game) do
      if event.kind == "OreDelivered" and event.pilot == wing.id then
        delivered += event.units
      end
    end
    return delivered > 0
  end), "no ore was brought in")
  t.eq(wing.hauled, delivered)
  t.eq(oreIn(game, base, "hangar") - (if base == home then before else 0), delivered)
  t.eq(oreIn(game, second.id, "cargo"), 0)
  -- (most of a Prospector's hold of it)
  t.ok(delivered * 0.1 > 0.5 * 480 or delivered > 200, `only {delivered} units came in`)
  -- And out again to the belt, and cutting.
  t.ok(waitFor(game, 600, function()
    local ball = state.balls[second.id]
    return ball ~= nil and ball.grid == rocks and oreIn(game, second.id, "cargo") > 0
  end), "the pilot did not go back to the belt")
  t.eq(Core.Query.Fleet(game)[1].doing, "mining")
  t.eq(Core.Query.Fleet(game)[1].hauled, delivered)
  -- Told to regroup, they stop work and come to the player, who is docked.
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "follow" })))
  t.ok(waitFor(game, 600, function()
    return second.docked == home
  end), "the pilot did not come back when called")
end)

suite:Case("only a pilot with a mining laser, at a belt, in a system with a station, is set to mine; and one who is hunted there goes in", function(t)
  local game, second = docked()
  local state = game.state
  local wing = hired(game, second)
  t.eq(refused(game, { kind = "FleetOrder", actor = 0, what = "mine" }), "docked")
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  steps(game, 5)
  t.eq(refused(game, { kind = "FleetOrder", actor = 0, what = "mine" }), "this is not an asteroid belt")
  local rocks = belt(game, 1)
  t.ok((submit(game, { kind = "WarpTo", actor = 0, target = rocks })))
  t.ok(waitFor(game, 600, function()
    local me, ball = state.balls[state.player.ship], state.balls[second.id]
    return me.grid == rocks and ball.grid == rocks
  end))
  -- (a Courier with autocannons has nothing to mine with)
  t.eq(refused(game, { kind = "FleetOrder", actor = 0, what = "mine" }), "no hired pilot here has a mining laser fitted")
  t.eq(wing.order, "follow")

  local mining, digger, ship = atBelt()
  t.ok((submit(mining, { kind = "FleetOrder", actor = 0, what = "mine", pilot = digger.id })))
  t.ok(waitFor(mining, 300, function()
    return oreIn(mining, ship.id, "cargo") > 0
  end))
  -- Somebody turns up and goes for the fleet: the pilot makes for the station.
  local me = mining.state.balls[mining.state.player.ship]
  Pirates.Spawn(mining.state, Pirates.SCOUT, me.system, me.x + 20000, me.y, me.z, me.grid)
  t.ok(waitFor(mining, 10, function()
    local ball = mining.state.balls[ship.id]
    return ball.intent ~= nil and ball.intent.kind == "dock" and ball.intent.target == digger.base
  end), "a hunted miner stayed at the belt")
  t.eq(Core.Query.Fleet(mining)[1].doing, "taking ore in")
end)

suite:Case("a hired pilot learns from the pirates destroyed where they fly and from the ore they bring in, and goes up a grade", function(t)
  local game, second = docked("destroyer.jackal")
  local state = game.state
  local wing = hired(game, second, 2)
  t.eq({ wing.experience, Fleet.Needed(1), Fleet.Needed(2), Fleet.Needed(4) }, { 0, 200, 800, 3200 })
  local me, theirs = adrift(game, second)
  -- A scout destroyed beside them is worth six points to them, whoever fired.
  Pirates.Spawn(state, Pirates.SCOUT, me.system, me.x + 5000, me.y, me.z, me.grid)
  t.ok(waitFor(game, 600, function()
    return #state.pilotIds == 0
  end), "the scout was not destroyed")
  t.eq(wing.experience, Pirates.SCOUT.bounty // 1000)
  local row = Core.Query.Fleet(game)[1]
  t.eq({ row.experience, row.needed }, { 6, 800 })
  -- One they were not there for is worth nothing to them.
  local before = wing.experience
  Fleet.Credit(state, me.system, me.grid + 1, 400000, game.events)
  t.eq(wing.experience, before)
  -- Enough of it, and they are a grade better, paid as that grade is. What is over is kept.
  Core.TakeEvents(game)
  Fleet.Credit(state, theirs.system, theirs.grid, 900000, game.events)
  t.eq({ wing.skill, wing.wage, wing.experience }, { 3, Fleet.Wage(3), 6 + 900 - 800 })
  local told = false
  for _, event in Core.TakeEvents(game) do
    told = told or (event.kind == "PilotPromoted" and event.pilot == wing.id and event.skill == 3)
  end
  t.ok(told, "nobody said the pilot had been promoted")
  -- Nobody gets better than grade 5.
  Fleet.Credit(state, theirs.system, theirs.grid, 100000000, game.events)
  t.eq({ wing.skill, wing.experience, Core.Query.Fleet(game)[1].needed }, { Fleet.BEST, 0, 0 })
end)

suite:Case("wages are paid by the day, and a pilot who cannot be paid leaves the ship they flew at home", function(t)
  local game, second = docked()
  local state = game.state
  local wing = hired(game, second)
  local wage, id = wing.wage, wing.id
  local wallet = state.wallet
  steps(game, Fleet.DAY - 5)
  t.eq(state.wallet, wallet)
  steps(game, 10)
  t.eq(state.wallet, wallet - wage)
  local journal = Core.Query.Journal(game)
  t.eq({ journal[#journal].reason, journal[#journal].amount } :: { any }, { "wages", -wage } :: { any })
  -- Out in space when the money runs out.
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  steps(game, 10)
  t.ok(state.balls[second.id] ~= nil)
  state.wallet = wage - 1
  local left = false
  for _ = 1, Fleet.DAY do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      left = left or (event.kind == "PilotLeft" and event.pilot == id and event.reason == "unpaid")
    end
    if left then
      break
    end
  end
  t.ok(left, "an unpaid pilot stayed")
  t.eq({ #state.fleetIds, state.balls[second.id], second.docked, second.pilot } :: { any }, { 0, nil, state.player.home, 0 } :: { any })
  t.eq(state.wallet, wage - 1)
end)

suite:Case("a fleet is in the save, and an older save has none", function(t)
  local game, second = docked()
  hired(game, second)
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  steps(game, 20)
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  steps(game, 60)
  steps(loaded, 60)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.eq(Core.Query.Fleet(loaded)[1].where, "with you")
  -- (a save from before a pilot could be set to mine)
  local now, nowLength = Core.Save(game)
  local before = Codec.Decode(now, nowLength)
  before.saveVersion = 24
  for _, wing in before.state.fleet do
    wing.post, wing.base, wing.hauled, wing.experience = nil, nil, nil, nil
  end
  local earlier, earlierLength = Codec.Encode(before)
  t.eq(Core.Hash(Core.Load(earlier, earlierLength)), Core.Hash(game))
  local fresh = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local saved, savedLength = Core.Save(fresh)
  local file = Codec.Decode(saved, savedLength)
  file.saveVersion = 23
  file.state.fleet, file.state.fleetIds, file.state.hired, file.state.hiredDay = nil, nil, nil, nil
  file.state.skills.leadership = nil
  for _, ship in file.state.ships do
    ship.pilot = nil
  end
  local old, oldLength = Codec.Encode(file)
  local opened = Core.Load(old, oldLength)
  t.eq({ #opened.state.fleetIds, opened.state.skills.leadership, opened.state.ships[opened.state.player.ship].pilot }, { 0, 1, 0 })
  t.eq(Core.Hash(opened), Core.Hash(fresh))
end)

return suite
