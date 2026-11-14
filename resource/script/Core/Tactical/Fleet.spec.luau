--!strict
-- Hired pilots (Tactical/Fleet).

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Drones = require("@lt/Core/Tactical/Drones")
local Fleet = require("@lt/Core/Tactical/Fleet")
local Items = require("@lt/Core/Assets/Items")
local Digger = require("@lt/Core/Tactical/Digger")
local Jumping = require("@lt/Core/Tactical/Jumping")
local Ores = require("@lt/Core/Data/Ores")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Rng = require("@lt/Core/Kernel/Rng")
local Sites = require("@lt/Core/Tactical/Sites")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local Starbases = require("@lt/Core/Assets/Starbases")
local State = require("@lt/Core/Kernel/State")
local Stations = require("@lt/Core/Assets/Stations")
local Structures = require("@lt/Core/Data/Structures")
local System = require("@lt/Core/Describe/System")
local Types = require("@lt/Core/Data/Types")
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
  local cruiser = Space.NewShip(state, "cruiser.ouyou", "Big", "player", state.player.home)
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
  -- Each goes for the ship of the pilot's side with least left to lose, which is the hired pilot's (its shield is down).
  theirs.vitals.shield = 0
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
  t.ok(not Modules.Mends(Modules.byId["projector.entanglement"]))
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

suite:Case("a capacitor relay sends what it costs into a locked ship in reach, and no more than there is room for", function(t)
  local game, second = docked()
  local state = game.state
  local Modules = require("@lt/Core/Data/Modules")
  -- (it wants the skill to fit, and goes in the Courier's third high slot, beside the guns)
  local item = Items.Add(state, "remote.capacitor.small", 1, state.player.home, "hangar")
  t.eq(refused(game, { kind = "Fit", actor = 0, item = item.id }), "needs Power Grid Management 2")
  state.skills["engineering"] = 2
  t.ok((submit(game, { kind = "Fit", actor = 0, item = item.id })))
  hired(game, second)
  local me, theirs = adrift(game, second)
  theirs.vitals.capacitor = 10
  t.ok((submit(game, { kind = "LockTarget", actor = 0, target = theirs.id })))
  t.ok(waitFor(game, 30, function()
    return me.vitals.locks[1] ~= nil and me.vitals.locks[1].locked
  end))
  local relay: State.Item? = nil
  for _, each in Items.Fitted(state, me.id) do
    relay = if each.type == "remote.capacitor.small" then each else relay
  end
  local mine, before = me.vitals.capacitor, theirs.vitals.capacitor
  Core.TakeEvents(game)
  t.ok((submit(game, { kind = "ActivateModule", actor = 0, item = assert(relay).id, target = theirs.id })))
  steps(game, 1)
  -- One cycle at once: forty out of one capacitor and into the other (each one's own recharge aside).
  t.ok(theirs.vitals.capacitor >= before + 40 and theirs.vitals.capacitor < before + 50,
    `their capacitor went from {before} to {theirs.vitals.capacitor}`)
  t.ok(me.vitals.capacitor <= mine - 40 + 5 and me.vitals.capacitor >= mine - 40, `mine went from {mine} to {me.vitals.capacitor}`)
  local fed = 0
  for _, event in Core.TakeEvents(game) do
    if event.kind == "Fed" and event.ball == me.id and event.target == theirs.id then
      fed += event.amount
    end
  end
  t.near(fed, 40, 1e-6)
  -- It never puts in more than there is room for: what a full ship is sent is lost.
  theirs.vitals.capacitor = theirs.vitals.capacitorMax - 15
  steps(game, 5)
  t.eq(theirs.vitals.capacitor, theirs.vitals.capacitorMax)
  -- Out of reach, it stops.
  theirs.x += 12000
  steps(game, 6)
  t.eq(#me.vitals.running, 0)
  -- There are three sizes; each sends what it costs, the bigger more and farther, for more of the skill.
  local small, medium, large = Modules.byId["remote.capacitor.small"], Modules.byId["remote.capacitor.medium"],
    Modules.byId["remote.capacitor.large"]
  for size, relayed in { small, medium, large } do
    local hex = relayed.hex :: Modules.Hex
    t.eq({ hex.kind, hex.strength } :: { any }, { "capacitor", hex.capacitor } :: { any }, relayed.id)
    t.eq((relayed.requires :: any)[1], { skill = "engineering", level = size + 1 })
    -- (for a friend, and not one of those that mend; nor is there a tech 2 or a custom make of it)
    t.ok(Modules.Friendly(relayed) and not Modules.Mends(relayed))
    t.eq({ Modules.Improved(relayed.id), Modules.Custom(relayed.id) } :: { any }, { nil, nil } :: { any })
  end
  t.ok((large.hex :: any).strength > (medium.hex :: any).strength and (medium.hex :: any).strength > (small.hex :: any).strength)
  t.ok((large.hex :: any).range > (small.hex :: any).range)
  t.ok(Modules.Friendly(Modules.byId["remote.armor.small"]) and not Modules.Friendly(Modules.byId["neutraliser.small"]))
end)

suite:Case("a hired pilot with a relay feeds whoever of the fleet is short of capacitor, and keeps enough of their own to fly on", function(t)
  local game, second = docked("destroyer.jackal")
  local state = game.state
  Items.Equip(state, second.id, "remote.capacitor.small", nil)
  hired(game, second, 2)
  local me, theirs = adrift(game, second)
  steps(game, 10)
  t.eq({ #theirs.vitals.locks, #theirs.vitals.running }, { 0, 0 })
  -- A pilot short of their own does not begin.
  me.vitals.capacitor = me.vitals.capacitorMax * 0.2
  theirs.vitals.capacitor = theirs.vitals.capacitorMax * 0.4
  steps(game, 12)
  t.eq(#theirs.vitals.running, 0, "a pilot with less than half their own capacitor gave some away")
  -- With enough, they lock the player and set to.
  theirs.vitals.capacitor = theirs.vitals.capacitorMax
  me.vitals.capacitor = me.vitals.capacitorMax * 0.2
  t.ok(waitFor(game, 40, function()
    return #theirs.vitals.running == 1 and theirs.vitals.running[1].target == me.id
  end), "the hired pilot did not start feeding")
  t.ok(waitFor(game, 300, function()
    return me.vitals.capacitor >= 0.9 * me.vitals.capacitorMax
  end), "the capacitor was not filled")
  -- Enough: the relay comes off, and so does the lock.
  t.ok(waitFor(game, 20, function()
    return #theirs.vitals.running == 0 and #theirs.vitals.locks == 0
  end), "the hired pilot went on feeding a ship that had enough")
  t.ok(theirs.vitals.capacitor > theirs.vitals.capacitorMax / 3)
  -- And they stop short of running themselves dry, whoever still wants it.
  me.vitals.capacitor = 0
  t.ok(waitFor(game, 40, function()
    return #theirs.vitals.running == 1
  end))
  theirs.vitals.capacitor = theirs.vitals.capacitorMax * 0.3
  me.vitals.capacitor = 0
  t.ok(waitFor(game, 20, function()
    return #theirs.vitals.running == 0
  end), "the hired pilot went on feeding with under a third of their own left")
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

-- The player in a capital industrial out at a belt of the home system,
-- and a hired pilot there with them, with a Prospector to mine in.
local function tending(hull: string): (Core.Game, State.Wingman, State.Ship, State.Ball, number)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  state.wallet = 10000000
  local second = Space.NewShip(state, "frigate.prospector", "Digger", "player", state.player.home)
  Items.Equip(state, second.id, "miner.small", nil)
  Items.Equip(state, second.id, "miner.small", nil)
  local wing = hired(game, second, 2)
  local great = Space.NewShip(state, hull, "Tender", "player", state.player.home)
  state.player.ship = great.id
  local rocks = belt(game, 1)
  local at = assert(Space.Object(state, rocks))
  local me = Space.Launch(state, great, 1, at.x + 4000, at.y, at.z)
  assert(me.grid == rocks, "the capital should be at the belt")
  -- (the pilot comes out after the player, and to where the player is)
  assert(waitFor(game, 900, function()
    local ball = state.balls[second.id]
    return ball ~= nil and ball.grid == rocks
  end), "the hired pilot did not come out to the belt")
  return game, wing, second, me, rocks
end

suite:Case("an ore hold takes ore and gas and nothing else; what its ship mines goes into it before the hold", function(t)
  -- (a capital industrial has one, and nothing else has)
  t.eq({ Ships.byId["capitalindustrial.jaguar"].ore, Ships.byId["capitalindustrial.okami"].ore, Ships.byId["freighter.dray"].ore,
    Ships.byId["barge.quarry"].ore } :: { any }, { Ships.ORE.capitalindustrial, Ships.ORE.capitalindustrial, 0, 0 } :: { any })
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local home = state.player.home
  local ore, rounds = Items.Add(state, "ore.ferrite", 1000, home, "hangar"), Items.Add(state, "ammo.emp", 100, home, "hangar")
  t.eq(refused(game, { kind = "MoveItems", actor = 0, item = ore.id, to = "orehold" }), "this hull has no ore hold")
  local great = Space.NewShip(state, "capitalindustrial.okami", "Miner", "player", home)
  state.player.ship = great.id
  t.eq(refused(game, { kind = "MoveItems", actor = 0, item = rounds.id, to = "orehold" }), "only ore and gas go in an ore hold")
  t.ok((submit(game, { kind = "MoveItems", actor = 0, item = ore.id, to = "orehold", quantity = 400 })))
  t.eq({ Core.Query.OreHold(game, great.id) } :: { any }, { Ships.ORE.capitalindustrial, 400 * Ores.byId["ore.ferrite"].volume } :: { any })
  t.eq(oreIn(game, great.id, "orehold"), 400)
  -- (no more than there is room for)
  local filler = Items.Add(state, "ore.iridite", 200000, home, "hangar")
  t.eq(refused(game, { kind = "MoveItems", actor = 0, item = filler.id, to = "orehold" }), "not enough room in the ore hold")
  -- And out of it again, to the hangar.
  t.ok((submit(game, { kind = "MoveItems", actor = 0, item = Items.In(state, great.id, "orehold")[1].id, to = "hangar" })))
  t.eq({ oreIn(game, great.id, "orehold"), oreIn(game, home, "hangar") } :: { any }, { 0, 201000 } :: { any })

  -- Out at a belt with mining lasers: what it cuts goes into the ore hold, and the hold stays as it was.
  for _ = 1, 4 do
    Items.Equip(state, great.id, "miner.small", nil)
  end
  local rocks = belt(game, 1)
  local at = assert(Space.Object(state, rocks))
  local me = Space.Launch(state, great, 1, at.x + 4000, at.y, at.z)
  local held = Items.CargoUsed(state, great.id)
  t.ok(waitFor(game, 600, function()
    Digger.Work(state, me, at, {})
    return oreIn(game, great.id, "orehold") > 0
  end), "nothing went into the ore hold")
  t.eq({ oreIn(game, great.id, "cargo"), Items.CargoUsed(state, great.id) } :: { any }, { 0, held } :: { any })
  -- With the ore hold full, the hold takes it.
  local size, used = Items.OreHold(state, great.id)
  Items.Add(state, "ore.iridite", math.floor((size - used) / Ores.byId["ore.iridite"].volume), great.id, "orehold")
  t.ok(waitFor(game, 600, function()
    Digger.Work(state, me, at, {})
    return oreIn(game, great.id, "cargo") > 0
  end), "with the ore hold full nothing went into the hold")
  -- (and it is all in the save)
  local data, length = Core.Save(game)
  t.eq(Core.Hash(Core.Load(data, length)), Core.Hash(game))
end)

suite:Case("with a ship of the player's at the belt that has room in its ore hold, a hired miner puts the ore across to it and does not go in", function(t)
  local game, wing, second, me, rocks = tending("capitalindustrial.jaguar")
  local state = game.state
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "mine" })))
  t.eq({ wing.order, wing.post } :: { any }, { "mine", rocks } :: { any })
  -- A hold is filled, and put across: the pilot never docks with it.
  local across, aboard, docked = 0, "", false
  t.ok(waitFor(game, 5000, function()
    for _, event in Core.TakeEvents(game) do
      if event.kind == "OreHandedOver" and event.pilot == wing.id then
        across += event.units
        aboard = event.aboard
        t.eq(event.to, me.id)
      end
    end
    docked = docked or (state.tick > 60 and second.docked ~= 0)
    return across > 0
  end), "no ore was put across")
  t.ok(not docked, "the pilot went in to the station with it")
  t.eq({ aboard, oreIn(game, me.id, "orehold"), oreIn(game, second.id, "cargo"), wing.hauled } :: { any },
    { "Tender", across, 0, across } :: { any })
  t.ok(Space.Gap(state.balls[second.id] :: any, me :: any) <= Fleet.HANDOVER, "the ore was put across from too far off")
  -- (most of a Prospector's hold of it)
  t.ok(across > 200, `only {across} units were put across`)
  -- And back to the rocks, and cutting.
  t.ok(waitFor(game, 900, function()
    return oreIn(game, second.id, "cargo") > 0
  end), "the pilot did not go back to the rocks")
  -- With no room left in the ore hold, the next hold goes in to the station as it always did.
  local size, used = Items.OreHold(state, me.id)
  Items.Add(state, "ore.iridite", math.floor((size - used) / Ores.byId["ore.iridite"].volume), me.id, "orehold")
  local delivered = 0
  t.ok(waitFor(game, 5000, function()
    for _, event in Core.TakeEvents(game) do
      if event.kind == "OreDelivered" and event.pilot == wing.id then
        delivered += event.units
      end
      t.ok(event.kind ~= "OreHandedOver", "ore was put across with no room for it")
    end
    return delivered > 0
  end), "with the ore hold full no ore was brought in")
  t.eq(wing.hauled, across + delivered)
end)

suite:Case("at a vapour field a hired pilot with a gas harvester draws the gas and brings it in, as a miner does ore", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  state.wallet = 10000000
  local home = state.player.home
  local second = Space.NewShip(state, "frigate.prospector", "Drawer", "player", home)
  Items.Equip(state, second.id, "miner.gas", nil)
  -- (a Gas Harvester wants Mining 2: a pilot of grade 2)
  local wing = hired(game, second, 2)
  t.eq({ #Digger.Lasers(state, second.id), #Digger.Lasers(state, second.id, true) }, { 0, 1 })
  -- A vapour field, found already, and the two out at it.
  local site = assert(Sites.Plant(state, 1, "gas", Rng.For(1, 2, 3), game.events), "no vapour field could be made")
  site.strength = 1
  local place = assert(Space.Object(state, site.id))
  t.ok(Digger.Gassy(state, place), "a vapour field is clouds")
  t.ok(not Digger.Gassy(state, assert(Space.Object(state, belt(game, 1)))), "and a belt is not")
  assert(submit(game, { kind = "Undock", actor = 0 }))
  steps(game, 5)
  assert(submit(game, { kind = "WarpTo", actor = 0, target = site.id }))
  t.ok(waitFor(game, 900, function()
    local me, ball = state.balls[state.player.ship], state.balls[second.id]
    return me ~= nil and me.grid == site.id and ball ~= nil and ball.grid == site.id
  end), "the two did not get to the vapour field")
  local function gasIn(holder: number, where: string): number
    local units = 0
    for _, item in Items.In(state, holder, where) do
      units += if Ores.gasById[item.type] then item.quantity else 0
    end
    return units
  end
  -- Set to work: the harvester is on a cloud, and gas comes aboard.
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "mine" })))
  t.eq({ wing.order, wing.post } :: { any }, { "mine", site.id } :: { any })
  t.ok(waitFor(game, 600, function()
    return gasIn(second.id, "cargo") > 0
  end), "no gas was drawn")
  -- The player goes in. A hold of it, or all the field had, is brought to the station.
  t.ok((submit(game, { kind = "Dock", actor = 0, target = home })))
  local delivered, gas = 0, false
  t.ok(waitFor(game, 9000, function()
    for _, event in Core.TakeEvents(game) do
      if event.kind == "OreDelivered" and event.pilot == wing.id then
        delivered += event.units
        gas = event.gas == true
      end
    end
    return delivered > 0
  end), "no gas was brought in")
  t.ok(gas, "what was brought in should be said to be gas")
  t.eq({ gasIn(wing.base, "hangar"), gasIn(second.id, "cargo"), wing.hauled }, { delivered, 0, delivered })
  -- (and a hauler told to carry ore carries gas with it)
  t.ok(Fleet.Carries("ore", "gas.amber") and Fleet.Carries("all", "gas.amber") and not Fleet.Carries("mineral", "gas.amber"))
  -- A pilot with only a laser is no use at a vapour field.
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "follow" })))
  for _, item in Items.Fitted(state, second.id) do
    if item.type == "miner.gas" then
      Items.Take(state, item, 1)
    end
  end
  t.eq(#Digger.Lasers(state, second.id, true), 0)
end)

-- How many drones are in a ship's drone bay, and how many it has out.
local function dronesOf(game: Core.Game, ship: number): (number, number)
  local aboard = 0
  for _, item in Items.In(game.state, ship, "dronebay") do
    aboard += item.quantity
  end
  return aboard, #Drones.Out(game.state, ship)
end

suite:Case("a pack shoots at one ship: whoever has least left to lose, and whoever mends the others before anybody", function(t)
  -- The player in a Courier and a hired pilot in a destroyer, which has three times as much to lose, with a
  -- remote repairer aboard.
  local game, second = docked("destroyer.jackal")
  local state = game.state
  Items.Equip(state, second.id, "remote.armor.small", nil)
  hired(game, second, 2)
  local me, theirs = adrift(game, second)
  local function all(ball: State.Ball): number
    return ball.vitals.shield + ball.vitals.armor + ball.vitals.hull
  end
  t.ok(all(theirs) > 2 * all(me))
  -- A pack comes in from the destroyer's side, each of them nearer to it than to the Courier. (They are of the
  -- sort that sees a fight through: breaking off is another case's.)
  theirs.x = me.x + 3000
  local pack: { State.Ball } = {}
  for index = 1, 3 do
    local raider = Pirates.Spawn(state, Pirates.kindById["raider"], me.system, theirs.x + 4000 + 700 * index, theirs.y + 900 * index,
      theirs.z, me.grid)
    state.pilots[raider.id].nerve = nil
    table.insert(pack, raider)
  end
  steps(game, 2)
  for _, raider in pack do
    t.ok(Space.Distance(raider :: any, theirs :: any) < Space.Distance(raider :: any, me :: any))
    t.eq(state.pilots[raider.id].prey, me.id, "every one of the pack should be after the Courier, which has least to lose")
  end
  -- The Courier's armour is knocked about, and the hired pilot begins to mend it. Whoever is mending is who a pack
  -- wants gone: every one of them turns on the destroyer. (The Courier is kept from being finished meanwhile.)
  me.vitals.armor = me.vitals.armorMax * 0.5
  t.ok(waitFor(game, 60, function()
    me.vitals.shield, me.vitals.hull = me.vitals.shieldMax, me.vitals.hullMax
    me.vitals.armor = math.max(me.vitals.armor, me.vitals.armorMax * 0.3)
    for _, running in theirs.vitals.running do
      if running.target == me.id then
        return true
      end
    end
    return false
  end), "the hired pilot did not start mending")
  steps(game, 2)
  for _, raider in pack do
    t.eq(state.pilots[raider.id].prey, theirs.id, "the pack should have turned on the ship that is mending")
    t.eq({ raider.mode, raider.target } :: { any }, { "orbit", theirs.id } :: { any })
  end
end)

suite:Case("a hired pilot looses their own drones on whoever they fight, calls them in after, and does not leave them behind", function(t)
  local game, second = docked("destroyer.jackal")
  local state = game.state
  -- Three in the bay of a hull that controls two, flown by a pilot good enough for two.
  Items.Add(state, "drone.light", 3, second.id, "dronebay")
  hired(game, second, 2)
  t.eq(Drones.Max(state, second.id), 2)
  local me, theirs = adrift(game, second)
  steps(game, 20)
  -- With nobody to fight, they stay in the bay.
  t.eq({ dronesOf(game, second.id) }, { 3, 0 })
  -- (and the player's own drone bay and drones are none of the pilot's business)
  t.eq(Core.Query.Drones(game).out, 0)
  -- A raider turns up: the drones go out, as many as can be controlled, at whoever the pilot is fighting.
  local raider = Pirates.Spawn(state, Pirates.kindById.raider, me.system, me.x + 9000, me.y, me.z, me.grid)
  -- (it is after the hired pilot's ship, as it would be if that were the one with least left to lose; and it is
  -- one that sees a fight through, which is not what this is about)
  state.pilots[raider.id].prey = theirs.id
  state.pilots[raider.id].nerve = nil
  t.ok(waitFor(game, 30, function()
    return select(2, dronesOf(game, second.id)) == 2
  end), "the hired pilot's drones did not go out")
  t.eq({ dronesOf(game, second.id) }, { 1, 2 })
  for _, drone in Drones.Out(state, second.id) do
    t.eq({ drone.owner, drone.target, drone.returning } :: { any }, { second.id, raider.id, false } :: { any })
    t.eq(state.ships[drone.ship].owner, "player")
  end
  t.eq(Core.Query.Drones(game).out, 0, "a hired pilot's drones were counted as the player's")
  -- The player warps off in the middle of it. The pilot calls the drones in, waits for them, and only then follows:
  -- none is lost.
  local planet = 0
  for _, entry in Core.Query.Overview(game) do
    planet = if entry.kind == "planet" and planet == 0 then entry.id else planet
  end
  -- (the drones well out, at the raider)
  t.ok(waitFor(game, 60, function()
    for _, drone in Drones.Out(state, second.id) do
      local ball = state.balls[drone.ship]
      if ball and Space.Gap(ball :: any, theirs :: any) > Drones.SCOOP then
        return true
      end
    end
    return false
  end), "no drone got far enough from its owner to be lost by a warp")
  Core.TakeEvents(game)
  t.ok((submit(game, { kind = "WarpTo", actor = 0, target = planet })))
  local lost, waited = 0, 0
  t.ok(waitFor(game, 400, function()
    for _, event in Core.TakeEvents(game) do
      lost += if event.kind == "DroneLost" and event.owner == second.id then 1 else 0
    end
    local ball = state.balls[second.id]
    -- (turning to go is not yet gone: a ship takes its drones aboard as it enters warp)
    local turning = ball ~= nil and ball.warp ~= nil
    waited += if turning then 0 else 1
    return ball ~= nil and ball.warp ~= nil and ball.warp.stage == "warp"
  end), "the hired pilot never followed")
  steps(game, 2)
  for _, event in Core.TakeEvents(game) do
    lost += if event.kind == "DroneLost" and event.owner == second.id then 1 else 0
  end
  t.eq({ lost, dronesOf(game, second.id) } :: { any }, { 0, 3, 0 } :: { any })
  t.ok(waited > 3, "the pilot did not wait for the drones")
end)

suite:Case("a hired pilot's drones come in when the fight is over, and a miner's mining drones work the rock with the lasers", function(t)
  local game, second = docked("destroyer.jackal")
  local state = game.state
  Items.Add(state, "drone.light", 2, second.id, "dronebay")
  hired(game, second, 2)
  local me = adrift(game, second)
  local scout = Pirates.Spawn(state, Pirates.SCOUT, me.system, me.x + 6000, me.y, me.z, me.grid)
  t.ok(waitFor(game, 40, function()
    return select(2, dronesOf(game, second.id)) == 2
  end), "the drones did not go out")
  t.ok(waitFor(game, 600, function()
    return state.balls[scout.id] == nil
  end), "the scout was not destroyed")
  -- Nobody left: called in, and aboard again.
  t.ok(waitFor(game, 120, function()
    return select(2, dronesOf(game, second.id)) == 0
  end), "the drones stayed out with nobody to fight")
  t.eq({ dronesOf(game, second.id) }, { 2, 0 })

  -- A miner with mining drones: they go out when the lasers are cutting, and bring what they cut to the miner.
  local digging, wing, prospector, rocks = atBelt()
  local there = digging.state
  Items.Add(there, "drone.mining", 1, prospector.id, "dronebay")
  t.ok((submit(digging, { kind = "FleetOrder", actor = 0, what = "mine" })))
  t.ok(waitFor(digging, 300, function()
    return select(2, dronesOf(digging, prospector.id)) == 1
  end), "the mining drone did not go out")
  local brought = 0
  t.ok(waitFor(digging, 900, function()
    for _, event in Core.TakeEvents(digging) do
      brought += if event.kind == "DroneDelivered" and event.owner == prospector.id then event.units else 0
    end
    return brought > 0
  end), "the mining drone brought nothing to the miner")
  -- The hold full, the drone is called in before the miner goes: it is in the bay when they dock, not lost.
  local lost = 0
  t.ok(waitFor(digging, 6000, function()
    for _, event in Core.TakeEvents(digging) do
      lost += if event.kind == "DroneLost" and event.owner == prospector.id then 1 else 0
    end
    return prospector.docked ~= 0
  end), "the miner never went in")
  t.eq({ lost, dronesOf(digging, prospector.id) } :: { any }, { 0, 1, 0 } :: { any })
  t.eq({ wing.order, rocks ~= 0 } :: { any }, { "mine", true } :: { any })
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

suite:Case("wages are paid by the day, and a pilot who cannot be paid once too often leaves the ship they flew at home", function(t)
  local game, second = docked()
  local state = game.state
  local wing = hired(game, second)
  local wage, id = wing.wage, wing.id
  local wallet = state.wallet
  local L = Fleet.LOYALTY
  t.eq({ wing.loyalty, Fleet.Mood(wing.loyalty) } :: { any }, { L.start, "steady" } :: { any })
  steps(game, Fleet.DAY - 5)
  t.eq(state.wallet, wallet)
  steps(game, 10)
  t.eq(state.wallet, wallet - wage)
  -- (a day's wage paid is a little more loyalty)
  t.eq(wing.loyalty, L.start + L.paid)
  local journal = Core.Query.Journal(game)
  t.eq({ journal[#journal].reason, journal[#journal].amount } :: { any }, { "wages", -wage } :: { any })
  -- Out in space when the money runs out: the first day worked for nothing they stay, and think the less of it.
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  steps(game, 10)
  t.ok(state.balls[second.id] ~= nil)
  state.wallet = wage - 1
  local left, unpaid = false, 0
  for _ = 1, 2 * Fleet.DAY do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      left = left or (event.kind == "PilotLeft" and event.pilot == id and event.reason == "unpaid")
      if event.kind == "PilotUnpaid" and event.pilot == id then
        unpaid += 1
        t.eq({ event.loyalty, wing.loyalty, Fleet.Mood(wing.loyalty) } :: { any },
          { L.start + L.paid - L.unpaid, L.start + L.paid - L.unpaid, "wary" } :: { any })
        t.eq({ #state.fleetIds, state.wallet }, { 1, wage - 1 })
      end
    end
    if left then
      break
    end
  end
  -- The second, they go.
  t.eq(unpaid, 1)
  t.ok(left, "a pilot unpaid twice stayed")
  t.eq({ #state.fleetIds, state.balls[second.id], second.docked, second.pilot } :: { any }, { 0, nil, state.player.home, 0 } :: { any })
  t.eq(state.wallet, wage - 1)
end)

suite:Case("loyalty grows with the days paid and with a grade gained, a devoted pilot takes a tenth less, and a ship lost under them costs it", function(t)
  local game, second = docked()
  local state = game.state
  local wing = hired(game, second)
  local L = Fleet.LOYALTY
  state.wallet = 100000000
  -- Paid day after day, to the most there is.
  local days = (L.devoted - L.start) // L.paid
  steps(game, days * Fleet.DAY + 5)
  t.eq({ wing.loyalty, Fleet.Mood(wing.loyalty), Fleet.Due(wing) } :: { any },
    { L.devoted, "devoted", math.floor(wing.wage * (1 - L.less)) } :: { any })
  -- Devoted, they are paid a tenth less: and that is what the crew list and the corporation's wages say.
  local before = state.wallet
  steps(game, Fleet.DAY)
  t.eq(before - state.wallet, Fleet.Due(wing))
  local row = Core.Query.Fleet(game)[1]
  t.eq({ row.wage, row.loyalty, row.mood } :: { any }, { Fleet.Due(wing), wing.loyalty, "devoted" } :: { any })
  steps(game, 20 * Fleet.DAY)
  t.eq(wing.loyalty, L.most)
  -- A ship destroyed under them: they are back on the list, less loyal than they were.
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  steps(game, 10)
  Aftermath.Destroy(state, second.id, 0, game.events)
  steps(game, 2)
  t.eq({ wing.ship, wing.loyalty, #state.fleetIds }, { 0, L.most - L.lost, 1 })
  -- One with little loyalty left, who loses another, goes.
  wing.loyalty = L.lost
  local third = Space.NewShip(state, "frigate.courier", "Third", "player", state.player.home)
  third.pilot, wing.ship = wing.id, third.id
  Core.TakeEvents(game)
  state.ships[third.id] = nil
  State.RemoveId(state.shipIds, third.id)
  steps(game, 2)
  local gone = false
  for _, event in Core.TakeEvents(game) do
    gone = gone or (event.kind == "PilotLeft" and event.reason == "lost")
  end
  t.ok(gone, "a pilot with no loyalty left should have gone")
  t.eq(#state.fleetIds, 0)

  -- A grade gained is loyalty gained. And a save from before there was loyalty: they stand where one newly signed on does.
  local other, ship = docked()
  local hand = hired(other, ship)
  hand.experience = Fleet.Needed(hand.skill) - 1
  Fleet.Credit(other.state, 0, 0, 0, other.events)
  local data, length = Core.Save(other)
  local file = Codec.Decode(data, length)
  file.saveVersion = 59
  for _, each in file.state.fleet do
    each.loyalty = nil
  end
  local old, oldLength = Codec.Encode(file)
  local loaded = Core.Load(old, oldLength)
  t.eq(loaded.state.fleet[hand.id].loyalty, L.start)
  t.eq(Core.Hash(loaded), Core.Hash(other))
end)

-- How many of a type somewhere holds.
local function count(game: Core.Game, holder: number, place: string, type: string): number
  local units = 0
  for _, item in Items.In(game.state, holder, place) do
    units += if item.type == type then item.quantity else 0
  end
  return units
end

-- The stations of a system other than the pilot's home: the nearest to
-- home with a market, and one with none.
local function others(game: Core.Game, system: number): (number, number)
  local state = game.state
  local home = Space.Object(state, state.player.home) :: System.Object
  local market, least, plain = 0, math.huge, 0
  for _, object in Space.Describe(state, system).objects do
    if object.kind == "station" and object.id ~= home.id then
      if not Stations.Has(state, object.id, "market") then
        plain = object.id
      elseif Space.Distance(home :: any, object :: any) < least then
        market, least = object.id, Space.Distance(home :: any, object :: any)
      end
    end
  end
  assert(market ~= 0 and plain ~= 0, "the system wants a second market and a station without one")
  return market, plain
end

suite:Case("a hired pilot whose ship is docked is set to haul: what there is of a kind goes to another station a hold at a time, and they wait for more", function(t)
  local game, second = docked("industrial.hauler")
  local state = game.state
  local home = state.player.home
  local other = others(game, 1)
  local wing = hired(game)
  local haul: State.Command = { kind = "FleetOrder", actor = 0, what = "haul", pilot = wing.id, target = other, type = "ore" }
  t.eq(refused(game, haul), `{wing.name} has no ship`)
  t.ok((submit(game, { kind = "AssignShip", actor = 0, pilot = wing.id, target = second.id })))
  t.eq(refused(game, { kind = "FleetOrder", actor = 0, what = "haul", target = other, type = "ore" }), "that is said to one pilot")
  t.eq(refused(game, { kind = "FleetOrder", actor = 0, what = "haul", pilot = wing.id, target = other, type = "gold" }), "no such cargo")
  t.eq(refused(game, { kind = "FleetOrder", actor = 0, what = "haul", pilot = wing.id, target = home, type = "ore" }), "that is where the goods are")
  t.eq(refused(game, { kind = "FleetOrder", actor = 0, what = "haul", pilot = wing.id, target = belt(game, 1), type = "ore" }),
    "that is not a station to carry to")

  -- A hold of ore and five hundred units over, and minerals that are not asked for.
  local each = Types.Info("ore.ferrite").volume
  local hold = math.floor((Items.ShipStats(state, second.id).cargo - Items.CargoUsed(state, second.id)) / each)
  t.ok(hold > 1000, `a hauler's hold takes {hold} units of ore`)
  Items.Add(state, "ore.ferrite", hold + 500, home, "hangar")
  Items.Add(state, "mineral.iron", 1000, home, "hangar")
  t.ok((submit(game, haul)))
  t.eq({ wing.order, wing.post, wing.base, wing.cargo } :: { any }, { "haul", home, other, "ore" } :: { any })
  Core.TakeEvents(game)
  -- Loaded and out, with as much as the hold takes.
  t.ok(waitFor(game, 30, function()
    return state.balls[second.id] ~= nil
  end), "the pilot did not set out")
  t.eq({ count(game, second.id, "cargo", "ore.ferrite"), count(game, home, "hangar", "ore.ferrite") }, { hold, 500 })
  local row = Core.Query.Fleet(game)[1]
  t.eq({ row.doing, row.cargo, row.from, row.to } :: { any },
    { "carrying", "ore", (Space.Object(state, home) :: System.Object).name, (Space.Object(state, other) :: System.Object).name } :: { any })
  -- (one out flying is not given another errand)
  t.eq(refused(game, haul), `{wing.name} has to be docked where the goods are`)
  -- The first hold is in the hangar there, and they go back for the rest.
  t.ok(waitFor(game, 1500, function()
    return count(game, other, "hangar", "ore.ferrite") == hold
  end), "the first hold did not arrive")
  t.ok(waitFor(game, 3000, function()
    return count(game, other, "hangar", "ore.ferrite") == hold + 500
  end), "the rest did not arrive")
  local told, units = 0, 0
  for _, event in Core.TakeEvents(game) do
    if event.kind == "HaulDelivered" and event.pilot == wing.id then
      told += 1
      units += event.units
      t.eq({ event.station, event.revenue }, { other, 0 })
    end
  end
  t.eq({ told, units, wing.hauled, wing.earned }, { 2, hold + 500, hold + 500, 0 })
  -- Back where the goods were, with nothing to carry, they wait: and the minerals are where they were.
  t.ok(waitFor(game, 1500, function()
    return second.docked == home
  end), "the pilot did not go back")
  steps(game, 30)
  t.eq({ second.docked, Core.Query.Fleet(game)[1].doing } :: { any }, { home, "waiting for cargo" } :: { any })
  t.eq({ count(game, home, "hangar", "mineral.iron"), count(game, other, "hangar", "mineral.iron") }, { 1000, 0 })
  -- More turns up, and they are off again.
  Items.Add(state, "ore.ferrite", 40, home, "hangar")
  t.ok(waitFor(game, 1500, function()
    return count(game, other, "hangar", "ore.ferrite") == hold + 540
  end), "what turned up later was not carried")
  -- Called back, they come to the player.
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "follow", pilot = wing.id })))
  t.ok(waitFor(game, 1500, function()
    return second.docked == home and wing.order == "follow"
  end), "the pilot did not come back when called")
  steps(game, 30)
  t.eq(second.docked, home)
end)

suite:Case("a pilot told to sell sells what they carry at the market where they bring it, and puts it in the hangar where there is none", function(t)
  local game, second = docked("industrial.hauler")
  local state = game.state
  local home = state.player.home
  local market, plain = others(game, 1)
  local wing = hired(game, second)
  t.eq(refused(game, { kind = "FleetOrder", actor = 0, what = "sell" }), "that is said to one pilot")
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "sell", pilot = wing.id })))
  t.eq({ wing.sell, wing.order } :: { any }, { true, "follow" } :: { any })
  t.eq(Core.Query.Fleet(game)[1].sells, true)

  Items.Add(state, "mineral.iron", 5000, home, "hangar")
  Items.Add(state, "ore.ferrite", 100, home, "hangar")
  local worth = Core.Query.SellValue(game, market, "mineral.iron", 5000)
  t.ok(worth > 0)
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "haul", pilot = wing.id, target = market, type = "mineral" })))
  local wallet = state.wallet
  Core.TakeEvents(game)
  local revenue = 0
  t.ok(waitFor(game, 1500, function()
    for _, event in Core.TakeEvents(game) do
      if event.kind == "HaulDelivered" then
        revenue += event.revenue
      end
    end
    return revenue > 0
  end), "nothing was sold")
  t.eq({ state.wallet - wallet, wing.earned, wing.hauled }, { revenue, revenue, 5000 })
  t.eq(revenue, worth, "it should fetch what the market gave for it")
  t.eq({ count(game, market, "hangar", "mineral.iron"), count(game, second.id, "cargo", "mineral.iron") }, { 0, 0 })
  t.eq(count(game, home, "hangar", "ore.ferrite"), 100, "ore is not minerals")
  t.eq(Core.Query.Fleet(game)[1].earned, revenue)

  -- To a station with no market: into the hangar there, whatever they were told.
  t.ok(waitFor(game, 1500, function()
    return second.docked == home
  end))
  Items.Add(state, "mineral.iron", 300, home, "hangar")
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "haul", pilot = wing.id, target = plain, type = "all" })))
  t.ok(waitFor(game, 3000, function()
    return count(game, plain, "hangar", "mineral.iron") == 300
  end), "nothing came to the station with no market")
  -- ("all" is ore, minerals, what colonies make and components)
  t.eq(count(game, plain, "hangar", "ore.ferrite"), 100)
  t.eq(wing.earned, revenue)
  -- Told to keep it, they sell no more.
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "keep", pilot = wing.id })))
  t.eq({ wing.sell, wing.order } :: { any }, { false, "haul" } :: { any })
end)

suite:Case("a haul can be to a station systems away, and the list of where to says how far each is and whether it has a market", function(t)
  local game, second = docked("industrial.hauler")
  local state = game.state
  local home = state.player.home
  local wing = hired(game, second)
  local next = state.galaxy.systems[1].neighbors[1]
  local market, plain = others(game, 1)
  -- Where to: the other stations here, and those of the system named, nearest first. (Home is where the ship is.)
  local targets = Core.Query.HaulTargets(game, wing.id, next)
  local far: Core.HaulTarget? = nil
  local seen: { [number]: Core.HaulTarget } = {}
  for index, target in targets do
    seen[target.id] = target
    t.ok(index == 1 or targets[index - 1].jumps <= target.jumps, "the list should be nearest first")
    t.ok(target.id ~= home, "the station the goods are at is not somewhere to carry them")
    if target.jumps == 1 and target.market and far == nil then
      far = target
    end
  end
  t.eq({ seen[market].jumps, seen[market].market, seen[plain].jumps, seen[plain].market } :: { any }, { 0, true, 0, false } :: { any })
  t.eq(#Core.Query.HaulTargets(game, wing.id), 2, "with no other system named, the stations here")
  local there = assert(far, "the next system has no station with a market")
  t.eq(there.system, state.galaxy.systems[next].name)
  -- (with the ship somewhere else, home is first on the list)
  second.docked = market
  t.eq(Core.Query.HaulTargets(game, wing.id)[1].id, home)
  second.docked = home

  Items.Add(state, "component.plating", 20, home, "hangar")
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "haul", pilot = wing.id, target = there.id, type = "component" })))
  t.ok(waitFor(game, 4000, function()
    return count(game, there.id, "hangar", "component.plating") == 20
  end), "the goods did not get to the next system")
  t.eq(Core.Query.Fleet(game)[1].to, there.name)
  -- And home again, to wait for more.
  t.ok(waitFor(game, 4000, function()
    return second.docked == home
  end), "the pilot did not come back from the next system")
  -- It is in the save, half way.
  Items.Add(state, "component.plating", 5, home, "hangar")
  t.ok(waitFor(game, 200, function()
    return state.balls[second.id] ~= nil
  end))
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  steps(game, 200)
  steps(loaded, 200)
  t.eq(Core.Hash(loaded), Core.Hash(game))
end)

suite:Case("a haul can be a round of several stations: each that has something is collected at, in order, and it is all carried to the last", function(t)
  local game, second = docked("industrial.hauler")
  local state = game.state
  local home = state.player.home
  local wing = hired(game, second)
  local second2, third = others(game, 1)
  local function named(id: number): string
    return (Space.Object(state, id) :: System.Object).name
  end
  local function round(stops: { number }, to: number): State.Command
    return { kind = "FleetOrder", actor = 0, what = "haul", pilot = wing.id, target = to, type = "ore", stops = stops }
  end
  -- A round collects at stations, each once, and not at the one it is all carried to; five at most, here among them.
  t.eq(refused(game, round({ third }, third)), "what is collected at the station it is carried to is there already")
  t.eq(refused(game, round({ home }, third)), "a station is collected at once a round")
  t.eq(refused(game, round({ second2, second2 }, third)), "a station is collected at once a round")
  t.eq(refused(game, round({ belt(game, 1) }, third)), "that is not a station to collect at")
  t.eq(refused(game, round({ 1, 2, 3, 4, 5 }, third)), `a round has {Fleet.STOPS} stations to collect at, at most`)
  t.eq(refused(game, round({ second2 }, third)), "(accepted)")

  -- The stations the ship docks at from now on, in order.
  local docks: { number } = {}
  local last = second.docked
  local function watch(limit: number, holds: () -> boolean): boolean
    return waitFor(game, limit, function()
      if second.docked ~= 0 and second.docked ~= last then
        table.insert(docks, second.docked)
      end
      last = second.docked
      return holds()
    end)
  end

  -- Some ore here and some at the second station: both are collected, in that order, and it all goes to the third.
  Items.Add(state, "ore.ferrite", 300, home, "hangar")
  Items.Add(state, "ore.ferrite", 400, second2, "hangar")
  t.ok((submit(game, round({ second2 }, third))))
  t.eq({ wing.order, wing.post, wing.base, wing.stops, wing.leg } :: { any }, { "haul", home, third, { home, second2 }, 0 } :: { any })
  Core.TakeEvents(game)
  t.ok(watch(60, function()
    return state.balls[second.id] ~= nil
  end), "the pilot did not set out")
  t.eq({ count(game, second.id, "cargo", "ore.ferrite"), wing.leg }, { 300, 1 })
  local row = Core.Query.Fleet(game)[1]
  t.eq({ row.doing, row.from, row.to, row.stops } :: { any },
    { "collecting", named(home), named(third), { named(home), named(second2) } } :: { any })
  t.ok(watch(3000, function()
    return count(game, third, "hangar", "ore.ferrite") == 700
  end), "what was collected did not arrive")
  t.eq(docks, { second2, third })
  local told, units = 0, 0
  for _, event in Core.TakeEvents(game) do
    if event.kind == "HaulDelivered" and event.pilot == wing.id then
      told += 1
      units += event.units
    end
  end
  t.eq({ told, units, wing.leg }, { 1, 700, 0 })
  -- Nothing anywhere: back to the first station, to wait.
  t.ok(watch(3000, function()
    return second.docked == home
  end), "the pilot did not go back to the first station")
  steps(game, 40)
  t.eq({ second.docked, Core.Query.Fleet(game)[1].doing } :: { any }, { home, "waiting for cargo" } :: { any })

  -- Something turns up at the second station only: straight there, and on to deliver.
  docks, last = {}, second.docked
  Items.Add(state, "ore.ferrite", 200, second2, "hangar")
  t.ok(watch(3000, function()
    return count(game, third, "hangar", "ore.ferrite") == 900
  end), "what turned up at the second station was not carried")
  t.eq(docks, { second2, third })

  -- A hold's worth and more at the first, and a little at the second: with the hold full they do not go on round, but
  -- deliver; and the rest, and the little, come on the next round.
  t.ok(watch(3000, function()
    return second.docked == home
  end))
  steps(game, 10)
  docks, last = {}, second.docked
  local each = Types.Info("ore.ferrite").volume
  local hold = math.floor((Items.ShipStats(state, second.id).cargo - Items.CargoUsed(state, second.id)) / each)
  Items.Add(state, "ore.ferrite", hold + 100, home, "hangar")
  Items.Add(state, "ore.ferrite", 50, second2, "hangar")
  Core.TakeEvents(game)
  t.ok(watch(6000, function()
    return count(game, third, "hangar", "ore.ferrite") == 900 + hold + 150
  end), "the full hold and what was left did not all arrive")
  t.eq(docks, { third, home, second2, third })
  local loads: { number } = {}
  for _, event in Core.TakeEvents(game) do
    if event.kind == "HaulDelivered" and event.pilot == wing.id then
      table.insert(loads, event.units)
    end
  end
  t.eq(loads, { hold, 150 })

  -- A round is in the save, and a haul of a save from before is a round of the one station it collected at.
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq({ Core.Hash(loaded), loaded.state.fleet[wing.id].stops } :: { any }, { Core.Hash(game), { home, second2 } } :: { any })
  local file = Codec.Decode(data, length)
  file.saveVersion = 48
  file.state.fleet[wing.id].stops, file.state.fleet[wing.id].leg = nil, nil
  local old, oldLength = Codec.Encode(file)
  local kept = Core.Load(old, oldLength).state.fleet[wing.id]
  t.eq({ kept.stops, kept.leg } :: { any }, { { home }, 0 } :: { any })
end)

suite:Case("a hired pilot is sent to buy: to the market named, what the hold takes for no more than they were told, back with it, and again until it is all brought", function(t)
  local game, second = docked("industrial.hauler")
  local state = game.state
  local home = state.player.home
  local other, plain = others(game, 1)
  local wing = hired(game)
  local type = "ore.ferrite"
  local buy: State.Command = { kind = "FleetOrder", actor = 0, what = "buy", pilot = wing.id, target = other, type = type, quantity = 100, price = 10 }
  t.eq(refused(game, buy), `{wing.name} has no ship`)
  t.ok((submit(game, { kind = "AssignShip", actor = 0, pilot = wing.id, target = second.id })))
  t.eq(refused(game, { kind = "FleetOrder", actor = 0, what = "buy", target = other, type = type, quantity = 100, price = 10 }), "that is said to one pilot")
  t.eq(refused(game, { kind = "FleetOrder", actor = 0, what = "buy", pilot = wing.id, target = other, type = "gold", quantity = 100, price = 10 }),
    "no such thing to buy")
  t.eq(refused(game, { kind = "FleetOrder", actor = 0, what = "buy", pilot = wing.id, target = other, type = type, quantity = 0, price = 10 }), "how many?")
  t.eq(refused(game, { kind = "FleetOrder", actor = 0, what = "buy", pilot = wing.id, target = other, type = type, quantity = 100 }),
    "for how much each, at most?")
  t.eq(refused(game, { kind = "FleetOrder", actor = 0, what = "buy", pilot = wing.id, target = home, type = type, quantity = 100, price = 10 }),
    "that is this station: buy it here yourself")
  t.eq(refused(game, { kind = "FleetOrder", actor = 0, what = "buy", pilot = wing.id, target = plain, type = type, quantity = 100, price = 10 }),
    "that is not a station with a market")
  t.eq(refused(game, { kind = "FleetOrder", actor = 0, what = "buy", pilot = wing.id, target = belt(game, 1), type = type, quantity = 100, price = 10 }),
    "that is not a station with a market")
  -- (a hull that is bigger than the hold)
  t.ok(Types.Info("freighter.dray").volume > Items.ShipStats(state, second.id).cargo)
  t.eq(refused(game, { kind = "FleetOrder", actor = 0, what = "buy", pilot = wing.id, target = other, type = "freighter.dray", quantity = 1,
    price = 1e9 }), `one does not fit in {wing.name}'s hold`)

  -- A hold of ore and five hundred units over. Where it is to be had: the
  -- market here in the system is on the list, with what that many cost there.
  local each = Types.Info(type).volume
  local hold = math.floor((Items.ShipStats(state, second.id).cargo - Items.CargoUsed(state, second.id)) / each)
  local want = hold + 500
  local source: Core.Source? = nil
  for _, found in Core.Query.Sources(game, home, type, want) do
    t.ok(found.id ~= home, "the station asked from is not somewhere else")
    if found.id == other then
      source = found
    end
  end
  local there = assert(source, "the other market of the system is not on the list")
  t.eq({ there.jumps, there.units, there.cost }, { 0, want, Core.Query.BuyCost(game, other, type, want) :: number })
  t.near(there.each, there.cost / want, 1e-9)
  local limit = math.ceil(there.each * 1.1)
  buy.quantity, buy.price = want, limit
  local before = state.wallet
  t.ok((submit(game, buy)))
  t.eq({ wing.order, wing.post, wing.base, wing.want, wing.need, wing.limit } :: { any }, { "buy", other, home, type, want, limit } :: { any })
  Core.TakeEvents(game)
  t.ok(waitFor(game, 30, function()
    return state.balls[second.id] ~= nil
  end), "the pilot did not set out")
  local row = Core.Query.Fleet(game)[1]
  t.eq({ row.doing, row.want, row.need, row.from, row.to } :: { any },
    { "going to buy", Types.Info(type).name, want, (Space.Object(state, other) :: System.Object).name, (Space.Object(state, home) :: System.Object).name } :: { any })
  -- (one out flying is not given another errand)
  t.eq(refused(game, buy), `{wing.name} has to be docked where it is to be brought`)
  -- The first hold is in the hangar at home, and they go back for the rest.
  t.ok(waitFor(game, 3000, function()
    return count(game, home, "hangar", type) == hold
  end), "the first hold did not arrive")
  t.eq(wing.need, 500)
  t.ok(waitFor(game, 3000, function()
    return count(game, home, "hangar", type) == want
  end), "the rest did not arrive")
  local made, bought, cost, told, units, left = 0, 0, 0, 0, 0, {}
  for _, event in Core.TakeEvents(game) do
    if event.kind == "BuyMade" and event.pilot == wing.id then
      made += 1
      bought += event.units
      cost += event.cost
      t.ok(event.cost <= limit * event.units, "a purchase came to more each than was allowed")
      t.eq(event.station, other)
    elseif event.kind == "BuyDelivered" and event.pilot == wing.id then
      told += 1
      units += event.units
      table.insert(left, event.left)
      t.eq({ event.station, event.type } :: { any }, { home, type } :: { any })
    end
    t.ok(event.kind ~= "Bought" and event.kind ~= "BuyEnded", `a {event.kind} was said`)
  end
  t.eq({ made, bought, told, units, wing.hauled }, { 2, want, 2, want, want })
  t.eq(left, { 500, 0 })
  -- It was paid for (out of the pilot's wallet, with no corporation), and it is on the market's books.
  t.eq(state.wallet, before - cost)
  local history = Core.Query.History(game, other, type)
  t.eq({ history[#history].volume, history[#history].value }, { want, cost })
  -- Done, they wait where they brought it.
  steps(game, 30)
  t.eq({ wing.order, wing.want, wing.need, second.docked, Core.Query.Fleet(game)[1].doing } :: { any }, { "stay", "", 0, home, "waiting" } :: { any })
end)

suite:Case("a pilot sent to buy pays no more than they were told and no more than there is: they bring what that bought, and say why there is no more", function(t)
  local game, second = docked("industrial.hauler")
  local state = game.state
  local home = state.player.home
  local other = others(game, 1)
  local wing = hired(game, second)
  local type = "autocannon.small"
  -- What a market asks rises with every one it sells: the most to pay each
  -- is what five would come to, and thirty are asked for.
  local limit = math.ceil((Core.Query.BuyCost(game, other, type, 5) :: number) / 5)
  local under = 0
  for units = 1, 30 do
    local cost = Core.Query.BuyCost(game, other, type, units)
    if cost and cost <= limit * units then
      under = units
    end
  end
  t.ok(under >= 5 and under < 30, `{under} of thirty come to no more than {limit} each`)
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "buy", pilot = wing.id, target = other, type = type, quantity = 30, price = limit })))
  Core.TakeEvents(game)
  t.ok(waitFor(game, 3000, function()
    return wing.order == "stay"
  end), "the errand did not end")
  t.eq({ count(game, home, "hangar", type), second.docked, wing.need }, { under, home, 0 })
  local ended: any = nil
  for _, event in Core.TakeEvents(game) do
    if event.kind == "BuyEnded" then
      ended = event
    end
  end
  -- (what one more cost there when they left, which is more than was allowed)
  t.eq({ ended.pilot, ended.short, ended.station } :: { any }, { wing.id, 30 - under, other } :: { any })
  local asked = tonumber(string.match(ended.reason, "^it is (%d+) credits each there now$"))
  t.ok(asked ~= nil and asked > limit, `"{ended.reason}", with {limit} allowed`)

  -- With the money for three and no more, three are brought.
  local three = Core.Query.BuyCost(game, other, type, 3) :: number
  state.wallet = three + 10
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "buy", pilot = wing.id, target = other, type = type, quantity = 10, price = 1e6 })))
  t.ok(waitFor(game, 3000, function()
    return wing.order == "stay"
  end), "the second errand did not end")
  t.eq({ count(game, home, "hangar", type), state.wallet }, { under + 3, 10 })
  for _, event in Core.TakeEvents(game) do
    if event.kind == "BuyEnded" then
      ended = event
    end
  end
  t.eq({ ended.short, ended.reason } :: { any }, { 7, "there is not the money for more" } :: { any })

  -- And with nobody to pay at all, the order is not taken.
  state.wallet = 0
  t.eq(refused(game, { kind = "FleetOrder", actor = 0, what = "buy", pilot = wing.id, target = other, type = type, quantity = 1, price = 1e6 }),
    "not enough credits")
  -- Nor is one for less than a single one costs there now.
  local one = Core.Query.BuyCost(game, other, type, 1) :: number
  t.eq(refused(game, { kind = "FleetOrder", actor = 0, what = "buy", pilot = wing.id, target = other, type = type, quantity = 1, price = one - 1 }),
    `one is {one} credits there now`)

  -- More than the market has: all it has, and that is said.
  state.wallet = 1e9
  local stock = Core.Query.Quote(game, other, "implant.shield").stock
  t.ok(stock >= 1 and stock < 50, `a station has {stock} of an implant`)
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "buy", pilot = wing.id, target = other, type = "implant.shield", quantity = 50, price = 1e9 })))
  t.ok(waitFor(game, 3000, function()
    return wing.order == "stay"
  end), "the third errand did not end")
  local brought = count(game, home, "hangar", "implant.shield")
  t.ok(brought >= stock, `{brought} of the {stock} there were brought`)
  for _, event in Core.TakeEvents(game) do
    if event.kind == "BuyEnded" then
      ended = event
    end
  end
  t.eq({ ended.short, ended.reason } :: { any }, { 50 - brought, "there is no more to be had there" } :: { any })
  -- And a market with none is not one to be sent to.
  if Core.Query.Quote(game, other, "implant.shield").stock < 1 then
    t.eq(refused(game, { kind = "FleetOrder", actor = 0, what = "buy", pilot = wing.id, target = other, type = "implant.shield", quantity = 1,
      price = 1e9 }), "that market has none")
  end
end)

suite:Case("a pilot set to keep a thing in stock buys what the hangar is short of, waits while it is not short, and goes again when it is", function(t)
  local game, second = docked("industrial.hauler")
  local state = game.state
  local home = state.player.home
  local other = others(game, 1)
  local wing = hired(game, second)
  local type = "fuel.block"
  local each = math.ceil((Core.Query.BuyCost(game, other, type, 400) :: number) / 400 * 1.25)
  local keep: State.Command = { kind = "FleetOrder", actor = 0, what = "stock", pilot = wing.id, target = other, type = type, quantity = 400,
    price = each }
  t.eq(refused(game, { kind = "FleetOrder", actor = 0, what = "stock", target = other, type = type, quantity = 400, price = each }),
    "that is said to one pilot")
  t.eq(refused(game, { kind = "FleetOrder", actor = 0, what = "stock", pilot = wing.id, target = home, type = type, quantity = 400, price = each }),
    "that is this station: buy it here yourself")
  t.ok((submit(game, keep)))
  t.eq({ wing.order, wing.post, wing.base, wing.want, wing.keep, wing.limit } :: { any }, { "stock", other, home, type, 400, each } :: { any })
  Core.TakeEvents(game)
  -- The hangar has none: they go for four hundred, and bring them.
  t.ok(waitFor(game, 3000, function()
    return count(game, home, "hangar", type) == 400
  end), "the stock was not brought")
  t.ok(waitFor(game, 60, function()
    return second.docked == home
  end))
  steps(game, 30)
  local row = Core.Query.Fleet(game)[1]
  t.eq({ row.doing, row.keep, row.want, second.docked } :: { any }, { "keeping stock", 400, Types.Info(type).name, home } :: { any })
  t.eq(wing.order, "stock", "a standing order does not end when it is filled")
  -- A little is used: not enough to go for (a tenth is forty).
  local function use(units: number)
    for _, item in Items.In(state, home, "hangar") do
      if item.type == type then
        Items.Take(state, item, units)
      end
    end
  end
  use(30)
  steps(game, 200)
  t.eq({ second.docked, count(game, home, "hangar", type) }, { home, 370 })
  -- More is used: they go, and it is four hundred again.
  use(120)
  t.ok(waitFor(game, 60, function()
    return state.balls[second.id] ~= nil
  end), "the pilot did not go for more")
  t.eq(wing.need, 150)
  t.ok(waitFor(game, 3000, function()
    return count(game, home, "hangar", type) == 400
  end), "the stock was not made up")
  -- The market has none to spare under the price: they say so, come back, and try again in ten minutes.
  wing.limit = 1
  use(200)
  local short: any = nil
  t.ok(waitFor(game, 3000, function()
    for _, event in Core.TakeEvents(game) do
      if event.kind == "StockShort" and event.pilot == wing.id then
        short = event
      end
      t.ok(event.kind ~= "BuyEnded", "a standing order should not end for a market that is short")
    end
    return short ~= nil
  end), "nothing was said of a market with none under the price")
  t.eq({ short.type, short.station } :: { any }, { type, other } :: { any })
  t.ok(waitFor(game, 600, function()
    return second.docked == home
  end))
  local tried = state.tick
  t.ok(wing.retry > tried and wing.retry <= tried + Fleet.RETRY)
  steps(game, 100)
  t.eq({ wing.order, second.docked } :: { any }, { "stock", home } :: { any }, "they should wait for their ten minutes")
  wing.limit = each
  t.ok(waitFor(game, Fleet.RETRY + 3000, function()
    return count(game, home, "hangar", type) == 400
  end), "the stock was not made up after the wait")
  -- It is in the save; an older save has nobody keeping anything; and called back, they stop.
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  local file = Codec.Decode(data, length)
  file.saveVersion = 56
  for _, kept in file.state.fleet do
    kept.keep, kept.retry = nil, nil
  end
  local old, oldLength = Codec.Encode(file)
  local opened = Core.Load(old, oldLength)
  t.eq({ opened.state.fleet[wing.id].keep, opened.state.fleet[wing.id].retry }, { 0, 0 })
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "follow", pilot = wing.id })))
  use(300)
  steps(game, 200)
  t.eq({ wing.order, second.docked } :: { any }, { "follow", home } :: { any })
end)

suite:Case("a market some jumps off is on the list without its system being put in the save; a pilot sent there goes, and the corporation pays", function(t)
  local game, second = docked("industrial.hauler")
  local state = game.state
  local home = state.player.home
  local wing = hired(game, second)
  local type = "fuel.block"
  -- Asking where a thing is to be had changes nothing.
  local described = 0
  for _ in state.systems do
    described += 1
  end
  local hash = Core.Hash(game)
  local sources = Core.Query.Sources(game, home, type, 200)
  local far: Core.Source? = nil
  for index, source in sources do
    t.ok(index == 1 or sources[index - 1].each <= source.each, "the list should be cheapest first")
    t.ok(source.jumps <= Fleet.SHOPS, "a market on the list is within reach")
    if source.jumps >= 1 and far == nil then
      far = source
    end
  end
  local after = 0
  for _ in state.systems do
    after += 1
  end
  t.eq({ after, Core.Hash(game) } :: { any }, { described, hash } :: { any })
  local there = assert(far, "no market a jump or more off sells fuel")
  local system = Space.SystemOf(state, there.id)
  t.ok(system ~= 1 and state.systems[system] == nil, "the market should be in a system nobody has been to")
  t.eq(there.system, state.galaxy.systems[system].name)
  -- The corporation pays for what its pilots buy.
  t.ok((submit(game, { kind = "FoundCorporation", actor = 0, what = "Ferrous Holdings" })))
  t.ok((submit(game, { kind = "CorporationDeposit", actor = 0, quantity = 1000000 })))
  local account, wallet = state.corporation.wallet, state.wallet
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "buy", pilot = wing.id, target = there.id, type = type, quantity = 200,
    price = math.ceil(there.each * 1.1) })))
  t.ok(state.systems[system] ~= nil, "the order should have the market's system described")
  -- Half way there it is in the save.
  t.ok(waitFor(game, 600, function()
    local ball = state.balls[second.id]
    return ball ~= nil and ball.system ~= 1
  end), "the pilot did not leave the system")
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  steps(game, 100)
  steps(loaded, 100)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.ok(waitFor(game, 6000, function()
    return wing.order == "stay"
  end), "the errand did not end")
  -- (what the corporation paid for is put in the corporation's hangar)
  t.eq({ count(game, home, "corporate", type), count(game, home, "hangar", type), second.docked }, { 200, 0, home })
  t.eq({ account - state.corporation.wallet, state.wallet }, { there.cost, wallet })
end)

suite:Case("a mining pilot told to sell sells the ore they bring in, where the station has a market", function(t)
  -- (at the belt nearest a station with a market, which is where the ore will be taken)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  state.wallet = 10000000
  local second = Space.NewShip(state, "frigate.prospector", "Digger", "player", state.player.home)
  Items.Equip(state, second.id, "miner.small", nil)
  Items.Equip(state, second.id, "miner.small", nil)
  local wing = hired(game, second, 2)
  local market = Space.Object(state, (others(game, 1))) :: System.Object
  local rocks, least = 0, math.huge
  for _, object in Space.Describe(state, 1).objects do
    if object.kind == "belt" and Space.Distance(object :: any, market :: any) < least then
      rocks, least = object.id, Space.Distance(object :: any, market :: any)
    end
  end
  assert(submit(game, { kind = "Undock", actor = 0 }))
  steps(game, 5)
  assert(submit(game, { kind = "WarpTo", actor = 0, target = rocks }))
  assert(waitFor(game, 600, function()
    local me, ball = state.balls[state.player.ship], state.balls[second.id]
    return me.grid == rocks and ball ~= nil and ball.grid == rocks
  end), "the two did not get to the belt")

  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "sell", pilot = wing.id })))
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "mine" })))
  t.eq({ wing.order, wing.sell } :: { any }, { "mine", true } :: { any })
  local base = wing.base
  t.ok(Stations.Has(state, base, "market"), "the station the ore goes to should have a market")
  local before = oreIn(game, base, "hangar")
  local wallet = state.wallet
  local units, revenue = 0, 0
  Core.TakeEvents(game)
  t.ok(waitFor(game, 5000, function()
    for _, event in Core.TakeEvents(game) do
      if event.kind == "OreDelivered" and event.pilot == wing.id then
        units += event.units
        revenue += event.revenue
      end
    end
    return units > 0
  end), "no ore was brought in")
  t.ok(revenue > 0, "the ore was not sold")
  t.eq({ state.wallet - wallet, wing.earned, wing.hauled }, { revenue, revenue, units })
  t.eq(oreIn(game, base, "hangar"), before, "ore that is sold should not be in the hangar too")
end)

-- A game with money in the wallet, room for two hired pilots, and a
-- warship in the hangar: a destroyer with its guns and racks filled,
-- plated, flown by a hired pilot of grade 3. Nobody comes for anybody
-- until the test says (state.peaceful).
local function warship(): (Core.Game, State.Wingman, State.Ship)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  state.wallet = 10000000
  state.skills.leadership = 2
  local ship = Space.NewShip(state, "destroyer.nozomi", "Escort", "player", state.player.home)
  for _ = 1, Ships.byId[ship.type].turrets do
    Items.Equip(state, ship.id, "autocannon.small", "ammo.fusion")
  end
  for _ = 1, Ships.byId[ship.type].launchers do
    Items.Equip(state, ship.id, "launcher.light", "missile.light.kinetic")
  end
  Items.Equip(state, ship.id, "armor.plate.200mm", nil)
  Items.Equip(state, ship.id, "armor.repairer.small", nil)
  Items.Add(state, "ammo.fusion", 4000, ship.id, "cargo")
  Items.Add(state, "missile.light.kinetic", 600, ship.id, "cargo")
  return game, hired(game, ship, 3), ship
end

-- Take the player and whoever follows them to a place, and wait until
-- the ships named are there too.
local function everybodyTo(game: Core.Game, place: number, ships: { State.Ship })
  local state = game.state
  if state.balls[state.player.ship] == nil then
    assert(submit(game, { kind = "Undock", actor = 0 }))
    steps(game, 5)
  end
  assert(submit(game, { kind = "WarpTo", actor = 0, target = place }))
  assert(waitFor(game, 900, function()
    local all = state.balls[state.player.ship].grid == place
    for _, ship in ships do
      local ball = state.balls[ship.id]
      all = all and ball ~= nil and ball.grid == place
    end
    return all
  end), "they did not all get there")
end

-- Send the player home, and wait until they are in.
local function home(game: Core.Game)
  local state = game.state
  assert(submit(game, { kind = "Dock", actor = 0, target = state.player.home }))
  assert(waitFor(game, 900, function()
    return state.ships[state.player.ship].docked == state.player.home
  end), "the player did not get home")
end

-- The pirates on a grid.
local function pirates(game: Core.Game, grid: number): { number }
  local found: { number } = {}
  for _, id in game.state.pilotIds do
    local ball = game.state.balls[id]
    if ball and ball.grid == grid and game.state.ships[id].owner == "pirates" then
      table.insert(found, id)
    end
  end
  return found
end

suite:Case("a pilot set to patrol holds a place; pirates come for them there with the player away, and half the bounty is the player's", function(t)
  local game, wing, ship = warship()
  local state = game.state
  local rocks = belt(game, 1)
  -- Only where there is a place to hold, from space, and only pilots with a weapon.
  t.eq(refused(game, { kind = "FleetOrder", actor = 0, what = "patrol" }), "docked")
  everybodyTo(game, rocks, { ship })
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "patrol" })))
  t.eq({ wing.order, wing.post } :: { any }, { "patrol", rocks } :: { any })
  t.ok((Space.Object(state, wing.base) :: System.Object).kind == "station")
  local row = Core.Query.Fleet(game)[1]
  t.eq({ row.doing, row.post, row.hunted } :: { any }, { "patrolling", (Space.Object(state, rocks) :: System.Object).name, false } :: { any })
  -- The player goes home. The pilot stays at their post.
  home(game)
  steps(game, 60)
  local theirs = assert(state.balls[ship.id], "the patrol went in with the player")
  t.eq(theirs.grid, rocks)
  -- Pirates come, as they would for the player: and are fought.
  state.peaceful = false
  Core.TakeEvents(game)
  local arrived, attacked = false, 0
  t.ok(waitFor(game, 60, function()
    for _, event in Core.TakeEvents(game) do
      arrived = arrived or (event.kind == "PiratesArrived" and event.away == true and event.grid == rocks)
      attacked += if event.kind == "FleetAttacked" and event.pilot == wing.id then 1 else 0
    end
    return arrived and attacked > 0
  end), "nobody came for a pilot who was out on their own")
  local pack = pirates(game, rocks)
  t.ok(#pack >= 1)
  local bounties = 0
  for _, id in pack do
    bounties += state.pilots[id].bounty
  end
  t.eq(Core.Query.Fleet(game)[1].hunted, true)
  local wallet, learned = state.wallet, wing.experience
  t.ok(waitFor(game, 1500, function()
    return #pirates(game, rocks) == 0
  end), "the patrol did not see the pirates off")
  for _, event in Core.TakeEvents(game) do
    attacked += if event.kind == "FleetAttacked" then 1 else 0
  end
  t.eq(attacked, 1, "they should say they are attacked once")
  t.ok(state.balls[ship.id] ~= nil, "the patrol's ship was lost to a secure belt's pirates")
  -- Half of each bounty is the player's (they were not there), and the pilot has learned from it.
  local paid = 0
  for _, id in pack do
    paid += 0
  end
  t.eq(state.wallet - wallet, bounties // 2 + paid)
  t.ok(wing.experience > learned)
  -- The place is left alone twice as long as it would be with the player there.
  steps(game, 1300)
  t.eq(#pirates(game, rocks), 0, "pirates came back for a hired pilot as soon as they would for the player")
  t.ok(waitFor(game, 1300, function()
    return #pirates(game, rocks) > 0
  end), "pirates did not come back at all")
end)

suite:Case("a patrol's pilot badly hurt goes in to the nearest station, is mended for what it costs, and goes out again", function(t)
  local game, wing, ship = warship()
  local state = game.state
  local rocks = belt(game, 1)
  everybodyTo(game, rocks, { ship })
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "patrol", pilot = wing.id })))
  -- Most of its armour and hull gone.
  local ball = state.balls[ship.id]
  ball.vitals.armor, ball.vitals.hull = 0.1 * ball.vitals.armorMax, 0.5 * ball.vitals.hullMax
  Core.TakeEvents(game)
  steps(game, 2)
  local retired = false
  for _, event in Core.TakeEvents(game) do
    retired = retired or (event.kind == "PatrolRetired" and event.pilot == wing.id)
  end
  t.ok(retired, "nobody said the patrol was going in")
  t.eq(Core.Query.Fleet(game)[1].doing, "going in to mend")
  -- With nothing to pay for it, they wait in.
  state.wallet = 0
  t.ok(waitFor(game, 900, function()
    return ship.docked ~= 0
  end), "the patrol did not get in")
  t.ok(ship.armorDamage > 0)
  steps(game, 30)
  t.eq({ ship.docked ~= 0, Core.Query.Fleet(game)[1].doing } :: { any }, { true, "mending" } :: { any })
  -- Paid for, they are mended and back at their post.
  state.wallet = 1000000
  local cost = 0
  Core.TakeEvents(game)
  t.ok(waitFor(game, 900, function()
    for _, event in Core.TakeEvents(game) do
      if event.kind == "WalletChanged" and event.reason == "repairs" then
        cost -= event.amount
      end
    end
    local out = state.balls[ship.id]
    return out ~= nil and out.grid == rocks
  end), "the patrol did not go back to its post")
  t.ok(cost > 0, "the mending should have cost something")
  t.eq({ ship.armorDamage, ship.hullDamage, wing.order } :: { any }, { 0, 0, "patrol" } :: { any })
  -- Called back, they come.
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "follow", pilot = wing.id })))
  t.eq(wing.order, "follow")
end)

suite:Case("a pilot set to guard another goes where that one goes, and fights whoever comes for them", function(t)
  local game, guard, escort = warship()
  local state = game.state
  local digger = Space.NewShip(state, "frigate.prospector", "Digger", "player", state.player.home)
  Items.Equip(state, digger.id, "miner.small", nil)
  Items.Equip(state, digger.id, "miner.small", nil)
  local miner = hired(game, digger, 2)
  -- One pilot, and the ship of another: not their own, and not one who is guarding them.
  t.eq(refused(game, { kind = "FleetOrder", actor = 0, what = "guard", target = digger.id }), "that is said to one pilot")
  t.eq(refused(game, { kind = "FleetOrder", actor = 0, what = "guard", pilot = guard.id, target = state.player.ship }),
    "pick the ship of another of your pilots for them to guard")
  t.eq(refused(game, { kind = "FleetOrder", actor = 0, what = "guard", pilot = guard.id, target = escort.id }), "nobody guards themselves")
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "guard", pilot = guard.id, target = digger.id })))
  t.eq({ guard.order, guard.ward } :: { any }, { "guard", miner.id } :: { any })
  t.eq(refused(game, { kind = "FleetOrder", actor = 0, what = "guard", pilot = miner.id, target = escort.id }),
    `{guard.name} is guarding {miner.name}`)
  local row = Core.Query.Fleet(game)[1]
  t.eq({ row.doing, row.ward } :: { any }, { "guarding", miner.name } :: { any })

  -- The miner is set to work at a belt, and the player goes home. The guard stays with the miner.
  local rocks = belt(game, 1)
  everybodyTo(game, rocks, { escort, digger })
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "mine", pilot = miner.id })))
  home(game)
  steps(game, 60)
  t.eq({ assert(state.balls[escort.id]).grid, assert(state.balls[digger.id]).grid }, { rocks, rocks })
  -- Pirates come. The miner, with a guard there, keeps at it; the guard fights, and sees them off.
  state.peaceful = false
  t.ok(waitFor(game, 60, function()
    return #pirates(game, rocks) > 0
  end), "nobody came for them")
  steps(game, 20)
  local working = state.balls[digger.id]
  t.ok(working ~= nil and not (working.intent and working.intent.kind == "dock"), "a guarded miner ran for it")
  t.ok(waitFor(game, 1500, function()
    return #pirates(game, rocks) == 0
  end), "the guard did not see the pirates off")
  t.ok(state.balls[escort.id] ~= nil and state.ships[digger.id] ~= nil, "one of them was lost")
  state.peaceful = true
  -- When the miner takes the ore in, the guard goes with them to the station, and back out to the belt with them.
  local base = miner.base
  local delivered, escorted = false, false
  Core.TakeEvents(game)
  t.ok(waitFor(game, 6000, function()
    for _, event in Core.TakeEvents(game) do
      delivered = delivered or (event.kind == "OreDelivered" and event.pilot == miner.id)
    end
    local with = state.balls[escort.id]
    escorted = escorted or escort.docked == base or (with ~= nil and with.grid == base)
    return delivered and escorted
  end), "the guard did not go in with the miner")
  t.ok(waitFor(game, 1500, function()
    local a, b = state.balls[digger.id], state.balls[escort.id]
    return a ~= nil and b ~= nil and a.grid == rocks and b.grid == rocks
  end), "the guard did not go back out with the miner")
  -- The one they guard dismissed, a guard is the player's again.
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "stay", pilot = miner.id })))
  t.ok(waitFor(game, 900, function()
    return digger.docked ~= 0
  end))
  -- (the guard goes in where the one they guard is)
  t.ok(waitFor(game, 900, function()
    return escort.docked == digger.docked
  end), "the guard did not dock where the miner did")
  t.ok((submit(game, { kind = "DismissPilot", actor = 0, pilot = miner.id })))
  steps(game, 3)
  t.eq({ guard.order, guard.ward } :: { any }, { "follow", 0 } :: { any })
end)

suite:Case("a miner out alone with nobody to guard them goes in when pirates come, and says so", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  state.wallet = 10000000
  local digger = Space.NewShip(state, "frigate.prospector", "Digger", "player", state.player.home)
  Items.Equip(state, digger.id, "miner.small", nil)
  Items.Equip(state, digger.id, "miner.small", nil)
  local miner = hired(game, digger, 2)
  local rocks = belt(game, 1)
  everybodyTo(game, rocks, { digger })
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "mine" })))
  home(game)
  state.peaceful = false
  Core.TakeEvents(game)
  local said, went = false, false
  t.ok(waitFor(game, 400, function()
    for _, event in Core.TakeEvents(game) do
      said = said or (event.kind == "FleetAttacked" and event.pilot == miner.id)
    end
    local ball = state.balls[digger.id]
    went = went or digger.docked ~= 0 or (ball ~= nil and ball.intent ~= nil and ball.intent.kind == "dock")
    return said and went
  end), "a miner gone for should say so and go in")
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
    wing.cargo, wing.sell, wing.earned = nil, nil, nil
    wing.ward, wing.alarm = nil, nil
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

suite:Case("a round that carries to several stations takes a load to each in turn", function(t)
  local game, second = docked()
  local state = game.state
  local home = state.player.home
  local wing = hired(game, second)
  local market, plain = others(game, 1)
  -- A station is carried to once, is not where the goods are, and there are only so many.
  local function haul(drops: { number }): State.Command
    return { kind = "FleetOrder", actor = 0, what = "haul", pilot = wing.id, target = market, type = "ore", drops = drops }
  end
  t.eq(refused(game, haul({ market })), "a station is carried to once a round, and is not one collected at")
  t.eq(refused(game, haul({ home })), "a station is carried to once a round, and is not one collected at")
  t.eq(refused(game, haul({ plain, plain })), "a station is carried to once a round, and is not one collected at")
  t.eq(refused(game, haul({ plain, 1, 2, 3 })), `a round carries to {Fleet.DROPS} stations, at most`)
  t.eq(refused(game, haul({ 999999 })), "that is not a station to carry to")
  -- More ore at home than three holds take, and the round set: to the market, and to the other station as well.
  Items.Add(state, "ore.ferrite", 500000, home, "hangar")
  t.ok((submit(game, haul({ plain }))))
  t.eq({ wing.order, wing.base, #wing.drops, wing.drops[1], wing.turn, Fleet.Drop(wing) } :: { any },
    { "haul", market, 1, plain, 0, market } :: { any })
  t.eq(Core.Query.Fleet(game)[1].drops, 2)
  Core.TakeEvents(game)
  local went: { number } = {}
  for _ = 1, 20000 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      if event.kind == "HaulDelivered" then
        table.insert(went, event.station)
        t.ok(event.units > 0)
      end
    end
    if #went >= 3 then
      break
    end
  end
  -- A load to each in turn, the station named first, and round again.
  t.eq(went, { market, plain, market })
  t.ok(count(game, market, "hangar", "ore.ferrite") > count(game, plain, "hangar", "ore.ferrite")
    and count(game, plain, "hangar", "ore.ferrite") > 0, "the ore is not at the two stations as two loads and one")
  t.eq(Fleet.Drop(wing), plain)
  -- It is in the save; and a save from before there were such rounds opens with none.
  local data, length = Core.Save(game)
  t.eq(Core.Hash(Core.Load(data, length)), Core.Hash(game))
  local file = Codec.Decode(data, length)
  file.saveVersion = 60
  for _, each in file.state.fleet do
    each.drops, each.turn = nil, nil
  end
  local old, oldLength = Codec.Encode(file)
  local loaded = Core.Load(old, oldLength)
  t.eq({ #loaded.state.fleet[wing.id].drops, loaded.state.fleet[wing.id].turn }, { 0, 0 })
  -- A plain order to haul afterwards carries to the one station again.
  local other, ship = docked()
  local hand = hired(other, ship)
  hand.drops, hand.turn = { plain }, 1
  t.ok((submit(other, { kind = "FleetOrder", actor = 0, what = "haul", pilot = hand.id, target = market, type = "ore" })))
  t.eq({ #hand.drops, hand.turn, Fleet.Drop(hand) }, { 0, 0, market })
end)

suite:Case("a hired pilot with a jump beacon generator fitted keeps it running whenever they are out in space: a beacon for the pilot to jump to", function(t)
  local game, second = docked()
  local state = game.state
  local generator = Items.Equip(state, second.id, "beacon.jump", nil)
  hired(game, second, 3)
  local me, theirs = adrift(game, second)
  steps(game, 10)
  local lit = false
  for _, running in theirs.vitals.running do
    lit = lit or running.item == generator.id
  end
  t.ok(lit, "the hired pilot should have lit the beacon")
  -- It is a beacon for the pilot's ship, where the hired pilot is; and it stays lit.
  local beacons = Jumping.Beacons(state, me.id)
  t.eq({ #beacons, beacons[1].kind, beacons[1].id, beacons[1].system } :: { any }, { 1, "ship", second.id, theirs.system } :: { any })
  steps(game, 120)
  t.eq(#Jumping.Beacons(state, me.id), 1)
  -- (and it is nothing they switch on for a fight and off after it, as they do a hardener)
  t.ok(theirs.vitals.capacitor > 0.2 * theirs.vitals.capacitorMax, "the generator should not run a frigate dry")
end)

-- A galaxy of forty with the player out at home in a carrier with a
-- jump drive, a hired pilot of the best grade beside them in another,
-- the skill for the drive, and a system within its reach with a tower
-- of the player's in it, a Jump Beacon lit (and one at home).
local function carriers(): (Core.Game, State.Wingman, State.Ship, State.Ball, number)
  local game, second = docked("carrier.scoppo", 40)
  local state = game.state
  local wing = hired(game, second, 5)
  local home = state.player.home
  local great = Space.NewShip(state, "carrier.scoppo", "Flag", "player", home)
  state.player.ship = great.id
  local station = assert(Space.Object(state, home))
  local me = Space.Launch(state, great, Space.SystemOf(state, home), station.x + 4e6, station.y, station.z)
  assert(waitFor(game, 900, function()
    local ball = state.balls[second.id]
    return ball ~= nil and ball.grid == me.grid and ball.warp == nil
  end), "the hired pilot did not come out to the player")
  state.skills[Jumping.SKILL] = 1
  -- (the farthest system the drive reaches)
  local to, most = 0, -1
  for id in state.galaxy.systems do
    local far = Jumping.Distance(state, me.system, id)
    if id ~= me.system and far <= Jumping.RANGE and far > most then
      to, most = id, far
    end
  end
  assert(to ~= 0, "the galaxy should have a system within a drive's reach")
  for _, system in { to, me.system } do
    local raised = false
    for _, object in Space.Describe(state, system).objects do
      if object.kind == "moon" and not raised then
        local id = Starbases.Raise(state, system, object, Structures.towerById["tower.vessari.small"], "player",
          object.x + object.radius * 3, object.y, object.z)
        local starbase = state.starbases[id]
        starbase.ready, starbase.fuel, starbase.burnt = state.tick, 100000, state.tick
        table.insert(starbase.modules, { type = Structures.BEACON, ready = state.tick })
        raised = true
      end
    end
    assert(raised, `system {system} has no moon to put a tower at`)
  end
  return game, wing, second, me, to
end

suite:Case("a hired pilot whose ship has a jump drive jumps after the player; waits for a drive that is cooling; and without the fuel says so and goes by the gates", function(t)
  local game, wing, second, me, to = carriers()
  local state = game.state
  local home = me.system
  local mine = state.ships[me.id]
  local function ready(ball: State.Ball)
    ball.vitals.capacitor = ball.vitals.capacitorMax
  end
  local function said(): string?
    local why: string? = nil
    for _, event in Core.TakeEvents(game) do
      if event.kind == "FleetCannotJump" and event.pilot == wing.id then
        why = event.why
      end
    end
    return why
  end
  Items.Add(state, Structures.FUEL.id, 5000, me.id, "cargo")
  Items.Add(state, Structures.FUEL.id, 5000, second.id, "cargo")
  local theirs = state.balls[second.id]
  ready(me)
  ready(theirs)
  -- The player jumps: the hired pilot's carrier jumps too, to the same beacon, on its own fuel.
  Core.TakeEvents(game)
  t.ok((submit(game, { kind = "JumpDrive", actor = 0, target = to })))
  t.eq(me.system, to)
  t.ok(waitFor(game, 5, function()
    return theirs.system == to
  end), "the hired pilot did not jump after the player")
  t.eq(said(), nil)
  t.ok(theirs.grid == me.grid and Jumping.Held(state, second.id) < 5000 and Jumping.Cooling(state, second.id) > 0,
    "it should have come out at the same beacon, with fuel burnt and the drive cooling")
  -- Back the other way before the hired pilot's drive has cooled: they wait where they are, and jump when it has.
  mine.jumped = nil
  ready(me)
  ready(theirs)
  t.ok((submit(game, { kind = "JumpDrive", actor = 0, target = home })))
  t.eq(me.system, home)
  steps(game, 20)
  t.eq({ theirs.system, theirs.intent == nil, theirs.warp == nil, said() } :: { any }, { to, true, true, nil } :: { any })
  ready(theirs)
  t.ok(waitFor(game, math.ceil(Jumping.COOLDOWN) + 20, function()
    ready(theirs)
    return theirs.system == home
  end), "the hired pilot did not jump when the drive had cooled")
  -- With no fuel aboard, they say why and set off by the gates.
  t.ok(waitFor(game, 600, function()
    return Jumping.Cooling(state, second.id) == 0 and theirs.grid == me.grid and theirs.warp == nil
  end), "the two did not come together again")
  for _, item in Items.In(state, second.id, "cargo") do
    if item.type == Structures.FUEL.id then
      Items.Take(state, item, item.quantity)
    end
  end
  mine.jumped = nil
  ready(me)
  ready(theirs)
  Core.TakeEvents(game)
  t.ok((submit(game, { kind = "JumpDrive", actor = 0, target = to })))
  local why = tostring(said())
  t.ok(string.find(why, "fuel blocks", 1, true) ~= nil, why)
  t.ok(waitFor(game, 60, function()
    return theirs.warp ~= nil or (theirs.intent ~= nil and theirs.intent.kind == "jump")
  end), "without the fuel the hired pilot did not set off by the gates")
  t.eq(theirs.system, home)
  -- (said once, and not again every tick they are on their way)
  steps(game, 10)
  t.eq(said(), nil)
end)

suite:Case("a hired pilot in a carrier launches its fighters at whoever the fleet fights, and calls them in after", function(t)
  local game, second = docked("carrier.scoppo")
  local state = game.state
  Items.Add(state, "drone.fighter", 12, second.id, "dronebay")
  local wing = hired(game, second, 5)
  t.eq(Fleet.Cannot(state, wing, second), nil)
  -- (ten: what a carrier controls, which a pilot of that grade has in hand and to spare)
  t.eq(Drones.Max(state, second.id), Ships.DRONES.carrier)
  local me = adrift(game, second)
  steps(game, 20)
  t.eq({ dronesOf(game, second.id) }, { 12, 0 })
  local raider = Pirates.Spawn(state, Pirates.kindById.raider, me.system, me.x + 9000, me.y, me.z, me.grid)
  t.ok(waitFor(game, 40, function()
    return select(2, dronesOf(game, second.id)) == Ships.DRONES.carrier
  end), "the hired pilot's fighters did not go out")
  for _, drone in Drones.Out(state, second.id) do
    t.eq({ drone.type, drone.owner, drone.target } :: { any }, { "drone.fighter", second.id, raider.id } :: { any })
  end
  -- They see to it, and come in again.
  t.ok(waitFor(game, 600, function()
    return state.balls[raider.id] == nil
  end), "the fighters did not destroy the raider")
  t.ok(waitFor(game, 300, function()
    return select(2, dronesOf(game, second.id)) == 0
  end), "the fighters were not called in")
  t.eq((dronesOf(game, second.id)), 12)
end)

return suite
