--!strict
-- The other ships about (Tactical/Traffic).

local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
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

suite:Case("a game with no traffic has none, and a secure system fills up to what it should have and no more", function(t)
  local quiet = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  steps(quiet, 600)
  t.eq({ #quiet.state.trafficIds, #quiet.state.shipIds }, { 0, 1 })

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
      t.eq({ hull.class, ship.owner } :: { any }, { "frigate", "civilian" } :: { any })
    else
      -- (a hauler; or, of a trader's, now and then a freighter)
      t.ok(hull.class == "industrial" or (hull.class == "freighter" and ship.owner == "civilian"), ship.type)
      t.ok(ship.owner == "vessari" or ship.owner == "civilian")
    end
  end
  -- Nothing but the traffic and the pilot's own, and nothing of a ship that has gone.
  t.eq(#state.shipIds, 1 + #state.trafficIds)
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
  t.ok(#state.shipIds <= 1 + Traffic.HAULERS.secure + Traffic.PATROLS.secure + Traffic.MINERS.secure)
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
          if ship.type == "freighter.dray" then
            freighters += 1
            most = math.max(most, aboard)
            t.eq(ship.name, "Freighter")
            -- (what it has aboard is what the economy has sent its way,
            -- and in a galaxy where nothing has gone anywhere yet that is
            -- nothing: Strategic/Commerce.spec has haulers with a hold of it)
            t.eq(aboard, 0)
            t.ok(Ships.byId[ship.type].cargo >= 5 * Ships.byId["industrial.hauler"].cargo, "a freighter should have many times a hauler's room")
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
      t.ok(ship == nil or ship.type ~= "freighter.dray", "a freighter outside secure space")
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
      t.eq({ state.ships[id].type, state.ships[id].owner, #Items.Fitted(state, id) } :: { any }, { "frigate.prospector", "civilian", 2 } :: { any })
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

return suite
