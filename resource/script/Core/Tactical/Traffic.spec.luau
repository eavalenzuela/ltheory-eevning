--!strict
-- The other ships about (Tactical/Traffic).

local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Jumping = require("@lt/Core/Tactical/Jumping")
local Modules = require("@lt/Core/Data/Modules")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")
local Traffic = require("@lt/Core/Tactical/Traffic")

local suite = Test.Suite("Traffic")

local function busy(historySeed: number?): Core.Game
  return Core.New({ galaxySeed = 1, historySeed = historySeed or 1, peaceful = true, traffic = true })
end

local function steps(game: Core.Game, count: number)
  for _ = 1, count do
    Core.Step(game)
  end
end

-- How many of the traffic are haulers, and how many patrol.
local function count(state: State.State): (number, number)
  local haulers, patrols = 0, 0
  for _, id in state.trafficIds do
    local kind = state.traffic[id].kind
    if kind == "patrol" then
      patrols += 1
    elseif kind == "in" or kind == "out" then
      haulers += 1
    end
  end
  return haulers, patrols
end

-- The ships of the traffic of a kind.
local function ofKind(state: State.State, kind: string): { number }
  local found: { number } = {}
  for _, id in state.trafficIds do
    if state.traffic[id].kind == kind then
      table.insert(found, id)
    end
  end
  return found
end

-- Put the pilot's ship in space in a system (the flight is Space's to test).
local function move(game: Core.Game, system: number)
  local state = game.state
  if state.balls[state.player.ship] == nil then
    assert(Core.Submit(game, { kind = "Undock", actor = state.player.ship }))
    Core.Step(game)
  end
  local ball = state.balls[state.player.ship]
  local sun = Space.Describe(state, system).objects[1]
  ball.system = system
  ball.x, ball.y, ball.z = sun.x + 5e10, sun.y, sun.z
  Space.AssignGrid(state, ball)
end

-- How many ships there are, not counting the batteries of the station
-- the pilot is at, which stand in space as ships do (Tactical/Batteries).
local function shipsOf(state: State.State): number
  local count = #state.shipIds
  for _, id in state.batteries.balls do
    count -= if id ~= 0 and state.ships[id] then 1 else 0
  end
  return count
end

suite:Case("a game with no traffic has none, and a secure system fills up to what it should have and no more", function(t)
  local quiet = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  steps(quiet, 600)
  t.eq({ #quiet.state.trafficIds, shipsOf(quiet.state) }, { 0, 1 })

  local game = busy()
  local state = game.state
  local most = 0
  for _ = 1, 40 do
    steps(game, 60)
    local haulers, patrols = count(state)
    t.ok(haulers <= Traffic.HAULERS.secure and patrols <= Traffic.PATROLS.secure, `{haulers} haulers and {patrols} patrols about`)
    most = math.max(most, haulers)
  end
  local haulers, patrols = count(state)
  t.ok(most >= 3, `never more than {most} haulers about in a homeworld's system`)
  t.eq(patrols, Traffic.PATROLS.secure)
  t.ok(haulers >= 1)
  -- Every one is a real ship of the first system, in a hauler's hull or
  -- a patrol's, of the faction whose space it is or anybody's.
  for _, id in state.trafficIds do
    local record, ship = state.traffic[id], state.ships[id]
    local hull = Ships.byId[ship.type]
    t.eq(record.system, 1)
    if record.kind == "patrol" then
      t.eq({ ship.owner, hull.lineage } :: { any }, { "vessari", "vessari" } :: { any })
      t.ok(hull.class == "frigate" or hull.class == "destroyer")
      t.ok(#Items.Fitted(state, id) >= 3, "a patrol ship should be armed")
    elseif record.kind == "miner" or record.kind == "home" then
      -- (in a barge of the people whose space it is: there are no hulls nobody's yards build, since 2026-11-18)
      t.eq({ hull.class, ship.owner } :: { any }, { "barge", "civilian" } :: { any })
    else
      -- (a hauler; or, of a trader's, now and then a freighter)
      t.ok(hull.class == "industrial" or (hull.class == "freighter" and ship.owner == "civilian"), ship.type)
      t.ok(ship.owner == "vessari" or ship.owner == "civilian")
    end
  end
  -- Nothing but the traffic and the pilot's own, and nothing of a ship that has gone.
  t.eq(shipsOf(state), 1 + #state.trafficIds)
  for _, id in state.itemIds do
    local item = state.items[id]
    t.ok(item.holder == state.player.home or state.ships[item.holder] ~= nil, `an item is held by {item.holder}, which is gone`)
  end
  -- (and nobody was sent on into a system nobody has seen)
  local described = 0
  for _ in state.systems do
    described += 1
  end
  t.eq(described, 1)
end)

suite:Case("haulers come in by a gate to dock, and go out from a station to a gate, and are gone", function(t)
  local game = busy()
  local state = game.state
  local docked, jumped = 0, 0
  local seen: { [number]: string } = {}
  for _ = 1, 3000 do
    Core.Step(game)
    for _, id in state.trafficIds do
      seen[id] = state.traffic[id].kind
    end
    for _, event in Core.TakeEvents(game) do
      if event.kind == "BallRemoved" and seen[event.ball] then
        docked += if event.reason == "docked" and seen[event.ball] == "in" then 1 else 0
        jumped += if event.reason == "jumped" and seen[event.ball] == "out" then 1 else 0
        t.ok(state.ships[event.ball] == nil or event.reason == "docked", "a hauler that has gone is still a ship")
      end
    end
  end
  t.ok(docked >= 3, `only {docked} haulers docked in fifty minutes`)
  t.ok(jumped >= 3, `only {jumped} haulers left by a gate in fifty minutes`)
  -- (the pilot's own, and no more than the haulers, patrols and miners a secure system has)
  t.ok(shipsOf(state) <= 1 + Traffic.HAULERS.secure + Traffic.PATROLS.secure + Traffic.MINERS.secure)
end)

suite:Case("where order is kept a trader is now and then a freighter, with a great deal of room aboard; nobody flies one where it is not", function(t)
  local freighters, traders, most = 0, 0, 0
  for seed = 1, 4 do
    local game = busy(seed)
    local state = game.state
    move(game, 1)
    local seen: { [number]: boolean } = {}
    for _ = 1, 40 do
      steps(game, Traffic.INTERVAL)
      for _, id in state.trafficIds do
        local ship = state.ships[id]
        if ship and not seen[id] and ship.owner == "civilian" then
          seen[id] = true
          local aboard = 0
          for _, item in Items.In(state, id, "cargo") do
            aboard += item.quantity
          end
          -- (the hauler or the freighter of the people whose space it is: no trader flies a plain hull)
          local class = Ships.byId[ship.type].class
          t.ok(Ships.byId[ship.type].lineage ~= "" or (class ~= "industrial" and class ~= "freighter"),
            `a trader in somebody's space flies a {ship.type}`)
          if class == "freighter" then
            freighters += 1
            most = math.max(most, aboard)
            t.eq(ship.name, "Freighter")
            -- (what it has aboard is what the economy has sent its way,
            -- and in a galaxy where nothing has gone anywhere yet that is
            -- nothing: Strategic/Commerce.spec has haulers with a hold of it)
            t.eq(aboard, 0)
            t.ok(Ships.byId[ship.type].cargo >= 5 * Ships.byId["industrial.mizumushi"].cargo, "a freighter should have many times a hauler's room")
          elseif Ships.byId[ship.type].class == "industrial" then
            traders += 1
          end
        end
      end
    end
  end
  t.ok(freighters >= 2, `only {freighters} freighters among the traders of four histories`)
  t.ok(traders > freighters, "most traders should fly a hauler")
  t.eq(most, 0)
  -- Where order is thin, none.
  local wild = busy(1)
  local low = 0
  for id, node in wild.state.galaxy.systems do
    low = if Galaxy.Band(node.security) ~= "secure" and low == 0 then id else low
  end
  move(wild, low)
  for _ = 1, 60 do
    steps(wild, Traffic.INTERVAL)
    for _, id in wild.state.trafficIds do
      local ship = wild.state.ships[id]
      t.ok(ship == nil or ship.type ~= "freighter.yoruzake", "a freighter outside secure space")
    end
  end
end)

suite:Case("how many are about follows from how safe the system is, and they do not outlast the pilot's leaving", function(t)
  local game = busy()
  local state = game.state
  steps(game, 600)
  t.ok(#state.trafficIds >= 3)
  for system, node in state.galaxy.systems do
    if system ~= 1 then
      move(game, system)
      Core.Step(game)
      for _, id in state.trafficIds do
        t.eq(state.traffic[id].system, system)
      end
      steps(game, 900)
      local band = Galaxy.Band(node.security)
      local haulers, patrols = count(state)
      t.ok(haulers <= Traffic.HAULERS[band], `{haulers} haulers in {band} space`)
      t.eq(patrols, Traffic.PATROLS[band])
      for _, id in state.trafficIds do
        local ship = state.ships[id]
        if band == "lawless" then
          t.eq(ship.owner, "civilian")
        end
      end
    end
  end
end)

suite:Case("firing on a ship that is no pirate's marks the pilot, and the patrol there fights them until it lapses", function(t)
  local game = busy()
  local state = game.state
  assert(Core.Submit(game, { kind = "Undock", actor = state.player.ship }))
  steps(game, 400)
  local patrol: State.Ball? = nil
  for _, id in state.trafficIds do
    if state.traffic[id].kind == "patrol" and patrol == nil then
      patrol = state.balls[id]
    end
  end
  local target = assert(patrol, "no patrol came to a homeworld's system")
  -- Beside it, and a lock.
  local me = state.balls[state.player.ship]
  me.x, me.y, me.z = target.x + 1500, target.y, target.z
  Space.AssignGrid(state, me)
  t.eq(me.grid, target.grid)
  t.ok(Core.Submit(game, { kind = "Stop", actor = me.id }))
  t.ok(Core.Submit(game, { kind = "LockTarget", actor = me.id, target = target.id }))
  steps(game, 15)
  t.eq(state.player.marked, 0)
  t.eq(state.pilots[target.id], nil)
  local hostile = false
  for _, entry in Core.Query.Overview(game) do
    hostile = hostile or entry.hostile
  end
  t.ok(not hostile, "a patrol is nobody's enemy until they make it one")
  -- Open fire.
  local gun = Items.Fitted(state, me.id)[1]
  t.ok(Core.Submit(game, { kind = "ActivateModule", actor = me.id, item = gun.id, target = target.id }))
  local marked = false
  for _ = 1, 3 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      marked = marked or event.kind == "Marked"
    end
  end
  t.ok(marked, "nothing said the pilot was marked")
  t.eq(state.player.marked > state.tick + Traffic.MARKED - 10, true)
  t.ok(state.pilots[target.id] ~= nil, "the patrol took no notice")
  local shield = me.vitals.shield
  steps(game, 40)
  t.ok(me.vitals.shield < shield or state.balls[me.id] == nil, "the patrol did not fire back")
  for _, entry in Core.Query.Overview(game) do
    if entry.id == target.id then
      t.ok(entry.hostile)
    end
  end
  -- It lapses, and the patrol stands down (if both are still there).
  state.player.marked = state.tick + 2
  steps(game, 5)
  if state.ships[target.id] then
    t.eq(state.pilots[target.id], nil)
    t.eq(#target.vitals.running, 0)
  end
end)

suite:Case("traffic is in the save, and the game goes on the same from it", function(t)
  local game = busy(3)
  steps(game, 700)
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  steps(game, 700)
  steps(loaded, 700)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.ok(#loaded.state.trafficIds >= 2)
end)

suite:Case("a save from before there was traffic opens as a game that has it", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local data, length = Core.Save(game)
  local file = Codec.Decode(data, length)
  file.saveVersion = 15
  file.state.traffic, file.state.trafficIds, file.state.trafficDue, file.state.trafficOn = nil, nil, nil, nil
  file.state.player.marked = nil
  local old, oldLength = Codec.Encode(file)
  local loaded = Core.Load(old, oldLength)
  t.eq({ loaded.state.trafficOn, loaded.state.player.marked, #loaded.state.trafficIds } :: { any }, { true, 0, 0 } :: { any })
  steps(loaded, 300)
  t.ok(#loaded.state.trafficIds >= 1)
end)

suite:Case("where order is kept there are miners at the belts, who cut rock and take it home", function(t)
  local game = busy()
  local state = game.state
  -- (the pilot sits docked at home, in a homeworld's system)
  local seen: { [number]: boolean } = {}
  local most, mined, home = 0, 0, 0
  for _ = 1, 1500 do
    Core.Step(game)
    local miners = ofKind(state, "miner")
    most = math.max(most, #miners + #ofKind(state, "home"))
    for _, id in miners do
      seen[id] = true
      local ball = state.balls[id]
      local record = state.traffic[id]
      t.eq({ Ships.byId[state.ships[id].type].class, state.ships[id].owner, #Items.Fitted(state, id) } :: { any }, { "barge", "civilian", 2 } :: { any })
      t.ok(ball == nil or ball.grid == 0 or ball.grid == record.goal or ball.intent ~= nil, "a miner is somewhere other than its belt")
      mined = math.max(mined, Items.CargoUsed(state, id))
    end
    home = math.max(home, #ofKind(state, "home"))
  end
  t.ok(most >= 1 and most <= Traffic.MINERS.secure, `{most} miners about at once`)
  t.ok(mined > 100, `no miner had more than {mined} m3 of ore aboard`)
  t.ok(home >= 1, "no miner ever went home with a full hold")
  -- The rocks are the worse for it.
  t.ok(#state.rockIds > 0)
  -- One that is shot at goes home at once.
  local miners = ofKind(state, "miner")
  if #miners > 0 then
    local ball = state.balls[miners[1]]
    ball.vitals.shield = 0
    steps(game, 2)
    t.eq(state.traffic[miners[1]].kind, "home")
  end
end)

suite:Case("in secure space the police come for a marked pilot, follow them, and go when the mark has lapsed", function(t)
  local game = busy()
  local state = game.state
  move(game, 1)
  local me = state.balls[state.player.ship]
  steps(game, 60)
  t.eq(#ofKind(state, "police"), 0)
  state.player.marked = state.tick + 300
  local arrived = 0
  for _ = 1, 2 * Traffic.INTERVAL do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      arrived += if event.kind == "PoliceArrived" then event.count else 0
    end
    -- (the first pair is enough to look at: a tick for them to see the pilot)
    if arrived > 0 then
      Core.Step(game)
      break
    end
  end
  local lawmen = ofKind(state, "police")
  t.ok(arrived >= 2 and #lawmen == arrived, `{arrived} police arrived`)
  for _, id in lawmen do
    local ball = state.balls[id]
    t.eq({ ball.grid, state.ships[id].owner } :: { any }, { me.grid, state.galaxy.systems[1].owner } :: { any })
    t.ok(state.pilots[id] ~= nil, "a police ship is not fighting the marked pilot")
    t.ok(Space.Distance(ball :: any, me :: any) < 15000)
  end
  -- No more than four of them, however long it goes on.
  steps(game, 8 * Traffic.INTERVAL)
  t.ok(#ofKind(state, "police") <= Traffic.POLICE + 2, `{#ofKind(state, "police")} police about`)
  -- The pilot moves a long way off in the system: they come after.
  me.x += 4e7
  Space.AssignGrid(state, me)
  local followed = false
  for _ = 1, 300 do
    Core.Step(game)
    for _, id in ofKind(state, "police") do
      local ball = state.balls[id]
      followed = followed or (ball ~= nil and ball.grid == me.grid and me.grid ~= 0)
    end
    state.player.marked = math.max(state.player.marked, state.tick + 60)
    if followed then
      break
    end
  end
  t.ok(followed or state.balls[me.id] == nil, "the police did not follow the pilot")
  -- When the mark has lapsed they go.
  if state.balls[me.id] then
    state.player.marked = state.tick
    steps(game, 3)
    t.eq(#ofKind(state, "police"), 0)
  end
end)

suite:Case("the police come in what it takes: destroyers for a small ship, cruisers for a cruiser, battleships for a battleship", function(t)
  for _, case in { { "frigate.courier", "destroyer", 1 }, { "cruiser.ouyou", "cruiser", 2 }, { "battleship.owari", "battleship", 3 } } :: { { any } } do
    local game = busy()
    local state = game.state
    move(game, 1)
    state.ships[state.player.ship].type = case[1]
    state.player.marked = state.tick + 300
    steps(game, 2 * Traffic.INTERVAL + 1)
    local lawmen = ofKind(state, "police")
    t.ok(#lawmen >= 2, `nobody came for a {case[1]}`)
    for _, id in lawmen do
      local hull = Ships.byId[state.ships[id].type]
      t.eq({ hull.class, hull.lineage } :: { any }, { case[2], state.galaxy.systems[1].owner } :: { any })
      -- (armed for its size: every weapon it carries is of the hull's size)
      local guns = 0
      for _, item in Items.Fitted(state, id) do
        local weapon = Modules.byId[item.type].weapon
        if weapon then
          guns += 1
          t.eq(weapon.size, case[3], `{hull.name} carries a {item.type}`)
        end
      end
      t.ok(guns >= 3, `{hull.name} has {guns} weapons`)
    end
  end
end)

suite:Case("nobody comes for a marked pilot where order is thin", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true, traffic = true, systems = 3 })
  local state = game.state
  local low = 0
  for id, node in state.galaxy.systems do
    if Galaxy.Band(node.security) == "low" then
      low = id
    end
  end
  t.ok(low ~= 0)
  move(game, low)
  state.player.marked = state.tick + 600
  steps(game, 6 * Traffic.INTERVAL)
  t.eq(#ofKind(state, "police"), 0)
end)

suite:Case("an alien faction keeps order in its own space, in its own hulls; the pirates hold theirs and keep none", function(t)
  -- (a galaxy of a hundred systems has all the factions in it)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true, traffic = true, systems = 100 })
  local state = game.state
  local function homeOf(faction: string): number
    for id, node in state.galaxy.systems do
      if node.home and node.owner == faction then
        return id
      end
    end
    error(`{faction} has no homeworld`)
  end
  local theirs = homeOf("vail")
  t.eq({ Galaxy.Band(state.galaxy.systems[theirs].security), Galaxy.Keeper(state.galaxy.systems[theirs]) } :: { string }, { "secure", "vail" })
  move(game, theirs)
  steps(game, 900)
  local _, patrols = count(state)
  t.eq(patrols, Traffic.PATROLS.secure)
  local own = 0
  for _, id in state.trafficIds do
    local ship = state.ships[id]
    if state.traffic[id].kind == "patrol" then
      t.eq({ ship.owner, Ships.byId[ship.type].lineage }, { "vail", "vail" })
    end
    -- (and of the hauliers, those that are a faction's are theirs)
    t.ok(ship.owner == "vail" or ship.owner == "civilian", `a ship of {ship.owner} in the Vail's space`)
    own += if ship.owner == "vail" then 1 else 0
  end
  t.ok(own >= patrols)

  local lair = homeOf("unbound")
  t.eq({ state.galaxy.systems[lair].security, Galaxy.Keeper(state.galaxy.systems[lair]) } :: { any }, { 0, "" } :: { any })
  move(game, lair)
  steps(game, 900)
  _, patrols = count(state)
  t.eq(patrols, 0)
  for _, id in state.trafficIds do
    t.eq(state.ships[id].owner, "civilian")
  end
end)

suite:Case("the Vail work the belts of their own space in fleets, which jump out to a station of theirs when one of them is hit: all but what is held or too far off", function(t)
  -- (a galaxy of a hundred systems has all the factions in it)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true, traffic = true, systems = 100 })
  local state = game.state
  -- Nobody else flies them: not where the pilot begins, whatever the day's roll.
  local home = Space.SystemOf(state, state.player.home)
  t.ok(Galaxy.Keeper(state.galaxy.systems[home]) ~= "vail")
  t.eq(Traffic.FleetDue(state, home), false)
  -- A system of the Vail's where a fleet is at work today: one with a belt on the chart, and a station of
  -- theirs in another system for the fleet to run to.
  local system, refuge = 0, 0
  local theirs, due = 0, 0
  for id, node in state.galaxy.systems do
    if Galaxy.Keeper(node) == "vail" then
      theirs += 1
      if Traffic.FleetDue(state, id) then
        due += 1
        local belt = false
        for _, object in Space.Describe(state, id).objects do
          belt = belt or (object.kind == "belt" and state.sites[object.id] == nil)
        end
        local to, station = Traffic.Refuge(state, id, "vail", 30)
        if system == 0 and belt and station then
          system, refuge = id, to
          t.ok(to ~= id and Galaxy.Keeper(state.galaxy.systems[to]) == "vail" and station.kind == "station")
        end
      end
    end
  end
  -- (about half of their systems, by the day)
  t.ok(theirs >= 4 and due >= 1 and due < theirs, `{due} of the Vail's {theirs} systems have a fleet due`)
  t.ok(system ~= 0, "no system of the Vail's has a fleet at work with a belt and somewhere to run to")
  -- (and not in one whose fleet is away)
  state.miningFleets[system] = state.tick + 50
  t.eq(Traffic.FleetDue(state, system), false)
  state.miningFleets[system] = nil

  move(game, system)
  steps(game, 2 * Traffic.INTERVAL)
  local jump, boss, barges = ofKind(state, "fleet.jump"), ofKind(state, "fleet.boss"), ofKind(state, "fleet.barge")
  t.eq({ #jump, #boss, #barges }, { 1, 1, Traffic.FLEET_BARGES })
  t.eq({ state.ships[jump[1]].type, state.ships[boss[1]].type, state.ships[barges[1]].type },
    { "ultracapital.archangel", "capitalindustrial.embrace", "barge.panacea" })
  for _, id in { jump[1], boss[1], barges[1], barges[4] } do
    t.eq({ state.ships[id].owner, state.balls[id].system } :: { any }, { "vail", system } :: { any })
  end
  -- Every one of them is within the jumpship's field, and each barge has its strip miners.
  local along: { [number]: boolean } = {}
  for _, id in Jumping.Along(state, jump[1]) do
    along[id] = true
  end
  t.ok(along[boss[1]], "the ship that leads the fleet is outside the jumpship's field")
  for _, id in barges do
    t.ok(along[id], "a barge is outside the jumpship's field")
    t.eq(#Items.Fitted(state, id), Ships.byId["barge.panacea"].turrets)
  end
  -- They work: before long a barge is cutting, and nobody has taken fright.
  steps(game, 240)
  local cutting = 0
  for _, id in barges do
    cutting += if #state.balls[id].vitals.running > 0 or Items.CargoUsed(state, id) > 0 then 1 else 0
  end
  t.ok(cutting >= 1, "no barge of the fleet is cutting rock")
  t.eq({ #ofKind(state, "fleet.jump"), state.traffic[jump[1]].wait }, { 1, 0 })

  -- One of them is hit: the jumpship makes its drive ready.
  local hit = state.balls[barges[2]]
  hit.vitals.shield = 0.5 * hit.vitals.shieldMax
  Core.Step(game)
  t.eq(state.traffic[jump[1]].wait, state.tick + Traffic.SPOOL)
  -- (and the fleet leaves its work and closes on it)
  for _, id in barges do
    t.eq({ state.balls[id].mode, state.balls[id].target } :: { any }, { "approach", jump[1] } :: { any })
  end
  -- (the last ticks by the traffic's own step, so that what is set here by hand stands)
  -- Held itself (which takes a capital's disruptor), it does not jump when the drive is ready.
  local lead = state.balls[jump[1]]
  state.traffic[jump[1]].wait = state.tick
  lead.vitals.scrambled = true
  local events: { Traffic.Event } = {}
  Traffic.Step(state, events)
  t.eq({ #ofKind(state, "fleet.jump"), #ofKind(state, "fleet.barge") }, { 1, Traffic.FLEET_BARGES })
  -- Let go, it jumps: with the fleet, but for a barge that is warp disrupted and one that has strayed too far.
  lead.vitals.scrambled = false
  -- (wherever their work has taken them by now, they are put where this is about: the ship that leads them
  -- and three barges close by the jumpship, and the fourth barge well outside its field)
  for index, id in { boss[1], barges[1], barges[2], barges[4] } do
    local ball = state.balls[id]
    ball.x, ball.y, ball.z = lead.x + lead.radius + ball.radius + 1500, lead.y + 600 * index, lead.z
    ball.warp = nil
  end
  local held, strayed = state.balls[barges[1]], state.balls[barges[3]]
  held.vitals.scrambled = true
  strayed.x, strayed.y, strayed.z, strayed.warp = lead.x + 20000, lead.y, lead.z, nil
  events = {}
  Traffic.Step(state, events)
  t.eq({ state.ships[jump[1]], state.ships[boss[1]], state.ships[barges[2]], state.ships[barges[4]] } :: { any }, {})
  t.eq({ state.balls[barges[1]] ~= nil, state.balls[barges[3]] ~= nil }, { true, true })
  -- (the two that were left make for a station here, as a miner does)
  t.eq({ state.traffic[barges[1]].kind, state.traffic[barges[3]].kind }, { "home", "home" })
  local jumped, said = 0, nil :: any
  for _, event in events do
    if event.kind == "Jumped" then
      jumped += 1
      t.eq({ event.from, event.to, event.drive } :: { any }, { system, refuge, true } :: { any })
    elseif event.kind == "FleetJumped" then
      said = event
    end
  end
  t.eq(jumped, 4)
  t.eq({ said.took, said.left, said.to, said.jumped } :: { any }, { 3, 2, refuge, true } :: { any })
  -- No fleet works the system again for a while.
  t.eq({ state.miningFleets[system], Traffic.FleetDue(state, system) } :: { any }, { state.tick + Traffic.FLEET_AWAY, false } :: { any })
  held.vitals.scrambled = false
  steps(game, 3 * Traffic.INTERVAL)
  t.eq(#ofKind(state, "fleet.jump"), 0)

  -- A fleet that loses its jumpship is not replaced for a day.
  state.miningFleets[system] = nil
  steps(game, 2 * Traffic.INTERVAL)
  local again = ofKind(state, "fleet.jump")
  t.eq(#again, 1)
  local lost = state.ships[again[1]]
  Space.RemoveBall(state, state.balls[lost.id])
  state.ships[lost.id] = nil
  State.RemoveId(state.shipIds, lost.id)
  Core.Step(game)
  t.eq(state.miningFleets[system], state.tick + Traffic.FLEET_LOST)
  -- (and what is left of it goes in to dock)
  Core.Step(game)
  t.eq({ #ofKind(state, "fleet.boss"), #ofKind(state, "fleet.barge") }, { 0, 0 })
  steps(game, 20)
end)

return suite
