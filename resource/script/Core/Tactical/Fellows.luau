--!strict
-- Fellows: the corporation's members as ships, where the pilot is.
--
-- What a member does is done to the galaxy by the hour, wherever the
-- pilot is (Assets/Members). Where the pilot is, they are there to be
-- seen at it: every member working in the system the pilot is in has
-- their own ship there, under their own name, in the hull they own.
--
--   - A miner is at a belt, cutting rock (the rocks are the worse for
--     it), and goes in to a station when the hold is full, when a
--     pirate goes for them, or when somebody shoots at them; and after
--     a while comes out again. (A pirate that is after somebody else
--     is somebody else's business: they go on cutting.)
--   - A hauler comes in by a gate and docks, and after a while comes
--     out and goes on by the gate for where their goods go for most.
--     What is aboard on the way out is the economy's, for real: taken
--     from this system's stock, and in the next one's when they are
--     through the gate (or in the wreck, if they never are).
--   - A fighter keeps a post, at a gate or a belt. Pirates who come
--     there are fought; and when pirates come for anybody of the
--     pilot's side or the corporation's anywhere in the open in the
--     system (a belt, a gate, a tower of the pilot's), the fighter
--     warps to them. Badly hurt, they go in to a station to mend, and
--     come out again.
--   - A scout goes from place to place about the system, a while at
--     each.
--
-- The pirates take a member's ship for what it is, one of the pilot's
-- side (Tactical/Pirates). A ship that is destroyed is the member's
-- loss (Assets/Members says what that costs them). Nothing of this is
-- anywhere the pilot is not: when the pilot leaves the system the ships
-- are taken away, and their owners go on as they were, unseen.
--
-- At a siege of a system of the pilot's the fighters are at the lines
-- (Tactical/Fronts puts them there, and has them while it lasts).
--
-- (First figures.)

local Attributes = require("@lt/Core/Attributes")
local Commerce = require("@lt/Core/Strategic/Commerce")
local Constants = require("@lt/Core/Data/Constants")
local Digger = require("@lt/Core/Tactical/Digger")
local Economy = require("@lt/Core/Strategic/Economy")
local Factions = require("@lt/Core/Data/Factions")
local Happenings = require("@lt/Core/Strategic/Happenings")
local Fits = require("@lt/Core/Fits")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Members = require("@lt/Core/Assets/Members")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")
local Traffic = require("@lt/Core/Tactical/Traffic")
local Types = require("@lt/Core/Data/Types")
local Wars = require("@lt/Core/Strategic/Wars")

local Fellows = {}

export type Event = { [string]: any }

-- Ticks a member is in a station between one time out and the next;
-- ticks a hauler is gone beyond a gate before it comes back by it; and
-- ticks a scout is at one place before it goes on to another.
Fellows.REST = math.ceil(120 / Constants.TICK)
Fellows.AWAY = math.ceil(180 / Constants.TICK)
Fellows.SURVEY = math.ceil(60 / Constants.TICK)
-- The share of itself a fighter has to be down to before it goes in to
-- mend; and the share of its shield a miner or a scout has to be down
-- to before it runs.
Fellows.HURT, Fellows.SHAKEN = 0.35, 0.6
-- How far off its post a fighter keeps, and how far off the pirates it
-- goes to it comes out of warp: metres.
Fellows.POST, Fellows.ANSWER = 6000, 8000

local MINER, STRIP = "miner.small", "miner.strip"

local function order(state: State.State, command: State.Command, events: { Event }): boolean
  if Space.Validate(state, command) then
    Space.Apply(state, command, events)
    return true
  end
  return false
end

-- A point a few kilometres off a place, rolled.
local function near(rng: Rng.Rng, site: System.Object, least: number, most: number): (number, number, number)
  local angle = Rng.Float(rng, 0, 2 * math.pi)
  local out = site.radius + Rng.Float(rng, least, most)
  return site.x + out * math.cos(angle), site.y + Rng.Float(rng, -1500, 1500), site.z + out * math.sin(angle)
end

-- What a member's ship is as a ship that fights: their own hull, with
-- their people's guns on it.
function Fellows.Kind(member: State.Member): Pirates.Kind
  local faction = Factions.byId[member.people]
  return Traffic.Fitted(member.hull, if faction then faction.weapon else nil, member.name)
end

-- The places of a system a member's ship has to do with: its stargates,
-- the belts that are on everybody's chart, the stations a member goes
-- in to (anybody's, and the pilot's own towers), and the planets and
-- moons.
local function places(state: State.State, system: number): ({ System.Object }, { System.Object }, { System.Object }, { System.Object })
  local gates: { System.Object }, belts: { System.Object } = {}, {}
  local stations: { System.Object }, worlds: { System.Object } = {}, {}
  for _, object in Space.Describe(state, system).objects do
    if object.kind == "gate" and object.variety ~= "passage" then
      table.insert(gates, object)
    elseif object.kind == "belt" and state.sites[object.id] == nil and (object.variety :: string) ~= "ice" then
      table.insert(belts, object)
    elseif object.kind == "station" and (state.starbases[object.id] == nil or state.starbases[object.id].owner == Wars.PILOT) then
      table.insert(stations, object)
    elseif object.kind == "planet" or object.kind == "moon" then
      table.insert(worlds, object)
    end
  end
  return gates, belts, stations, worlds
end

-- The station nearest a ship, of those a member goes in to.
local function nearestStation(state: State.State, ball: State.Ball): System.Object?
  local _, _, stations = places(state, ball.system)
  local best: System.Object?, least = nil, math.huge
  for _, object in stations do
    local far = Space.Distance(object :: any, ball :: any)
    if far < least then
      best, least = object, far
    end
  end
  return best
end

-- Whether a pirate is on a ship's grid (one that is not on its way out).
local function pirateNear(state: State.State, ball: State.Ball): boolean
  for _, id in state.pilotIds do
    local other = state.balls[id]
    if other and other.system == ball.system and other.grid == ball.grid and state.ships[id].owner == "pirates"
      and not state.pilots[id].fleeing then
      return true
    end
  end
  return false
end

-- Whether a pirate is after a ship.
local function hunted(state: State.State, ship: number): boolean
  for _, id in state.pilotIds do
    if state.pilots[id].prey == ship and state.ships[id] and state.ships[id].owner == "pirates" then
      return true
    end
  end
  return false
end

-- A pirate somewhere else in the system that is after a ship of the
-- pilot's side or the corporation's (or what stands for a tower of the
-- pilot's), in the open: at a belt, a gate or a tower, and not at a
-- place that is somebody's job or somebody's den. The first there is.
local function trouble(state: State.State, ball: State.Ball): State.Ball?
  for _, id in state.pilotIds do
    local other, pilot = state.balls[id], state.pilots[id]
    local prey = state.ships[pilot.prey]
    if other and prey and state.ships[id].owner == "pirates" and other.system == ball.system and other.grid ~= 0
      and other.grid ~= ball.grid and other.warp == nil and state.sites[other.grid] == nil
      and (prey.owner == "player" or prey.owner == "member" or prey.owner == "starbase") then
      return other
    end
  end
  return nil
end

-- What a ship has left to lose, as a share of what it had.
local function left(ball: State.Ball): number
  local v = ball.vitals
  return (v.shield + v.armor + v.hull) / math.max(1, v.shieldMax + v.armorMax + v.hullMax)
end

-- The mining lasers a miner's hull carries: one on every turret
-- hardpoint, a barge's the big ones where they fit.
local function lasers(state: State.State, ship: State.Ship)
  local hull = Ships.byId[ship.type]
  local types: { string } = {}
  for _ = 1, hull.turrets do
    table.insert(types, if hull.class == "barge" then STRIP else MINER)
    if not Attributes.Check(hull, types) then
      types[#types] = MINER
      if not Attributes.Check(hull, types) then
        table.remove(types)
        break
      end
    end
  end
  for _, type in types do
    Items.Equip(state, ship.id, type, nil)
  end
end

-- A member's ship, new: in a station, or nowhere yet (0).
local function build(state: State.State, member: State.Member, station: number): State.Ship
  local ship = Space.NewShip(state, member.hull, member.name, "member", station)
  if member.fitFor == member.hull then
    -- (what they have bought for it, and the charges they have: Assets/Members)
    for _, type in member.fit do
      local module = Modules.byId[type]
      local charge = if module and module.weapon and member.ammo > 0 then Fits.Charge(type, Ships.byId[member.hull]) else nil
      Items.Equip(state, ship.id, type, charge)
    end
  elseif Members.Acts(member) == "miner" then
    lasers(state, ship)
  elseif Members.Acts(member) == "fighter" then
    Pirates.Equip(state, ship, Fellows.Kind(member))
  end
  member.ship = ship.id
  member.since, member.wait = state.tick, 0
  return ship
end

-- Put a member's ship into space at a point, as if it had been there.
local function launch(state: State.State, member: State.Member, system: number, x: number, y: number, z: number, events: { Event },
  gate: number?): State.Ball
  local ship = build(state, member, 0)
  local ball = Space.Launch(state, ship, system, x, y, z)
  table.insert(events, { kind = "BallAdded", ball = ball.id, gate = gate })
  return ball
end

-- A member's ship comes out of the station they were in.
local function undock(state: State.State, member: State.Member, station: number, events: { Event }): State.Ship
  local ship = build(state, member, station)
  order(state, { kind = "Undock", actor = ship.id }, events)
  return ship
end

-- The gate a hauler goes out by: the way to where their goods go for
-- most (Assets/Members), or failing that one that is theirs by habit.
-- And the goods: the class in the economy, and the system they are for
-- (0, 0: nothing pays).
local function lane(state: State.State, member: State.Member, system: number, gates: { System.Object }): (System.Object, number, number)
  local class, to, gap = Members.Haul(state, system)
  if class ~= 0 and gap > 0 then
    -- (round a closed gate, and round a surge or an invasion where there is a way round: Strategic/Happenings)
    local route = Happenings.Way(state, system, to)
    for _, gate in gates do
      if route[2] and gate.to == route[2] then
        return gate, class, to
      end
    end
  end
  return gates[member.id % #gates + 1], 0, 0
end

-- A member who is working in the system the pilot is in, and has no
-- ship there: put it there, at what they do.
local function appear(state: State.State, member: State.Member, system: number, events: { Event })
  if Ships.byId[member.hull] == nil then
    return
  end
  local gates, belts, stations, worlds = places(state, system)
  local rng = Rng.For(state.historySeed, state.tick, member.id, 163)
  -- (the station they are in, if they went in to one here)
  local berth = 0
  if member.task == "rest" then
    for _, station in stations do
      berth = if station.id == member.goal then station.id else berth
    end
  end
  if Members.Acts(member) == "miner" then
    if #belts == 0 then
      return
    end
    local belt = belts[member.id % #belts + 1]
    if berth ~= 0 then
      undock(state, member, berth, events)
      member.task, member.goal = "out", belt.id
    else
      local x, y, z = near(rng, belt, 6000, 16000)
      launch(state, member, system, x, y, z, events)
      member.task, member.goal = "work", belt.id
    end
  elseif Members.Acts(member) == "hauler" then
    if #gates == 0 or #stations == 0 then
      return
    end
    local gate, class, to = lane(state, member, system, gates)
    local back: System.Object? = nil
    if member.task == "away" then
      for _, other in gates do
        back = if other.id == member.goal then other else back
      end
    end
    -- (one seen for the first time is as likely on the way in as on the way out)
    if berth ~= 0 or (back == nil and Rng.Chance(rng, 0.5)) then
      local station = if berth ~= 0 then berth else stations[Rng.Int(rng, #stations) + 1].id
      local ship = undock(state, member, station, events)
      member.task, member.goal = "out", gate.id
      -- (what they take out is this system's, until it is the next one's)
      local node = state.commerce.nodes[system]
      if class ~= 0 and node and state.commerce.nodes[to] then
        local type = Commerce.goods[class]
        local units = math.floor(math.min(Ships.byId[member.hull].cargo * Commerce.FILL / Types.Info(type).volume, node.stock[class]))
        if units >= 1 then
          Economy.Draw(state.commerce, system, class, units)
          Items.Add(state, type, units, ship.id, "cargo")
          member.carries = { node = to, class = class, amount = units }
        end
      end
    else
      local from = back or gate
      local x, y, z = near(rng, from, 3000, 8000)
      local ball = launch(state, member, system, x, y, z, events, from.id)
      local station = stations[member.id % #stations + 1]
      member.task, member.goal = "home", station.id
      order(state, { kind = "Dock", actor = ball.id, target = station.id }, events)
    end
  elseif Members.Acts(member) == "fighter" then
    local posts: { System.Object } = {}
    for _, list in { gates, belts } do
      for _, object in list do
        table.insert(posts, object)
      end
    end
    if #posts == 0 then
      posts = stations
    end
    if #posts == 0 then
      return
    end
    local post = posts[member.id % #posts + 1]
    if berth ~= 0 then
      undock(state, member, berth, events)
      member.task, member.goal = "out", post.id
    else
      local x, y, z = near(rng, post, 5000, 9000)
      local ball = launch(state, member, system, x, y, z, events)
      member.task, member.goal = "work", post.id
      order(state, { kind = "Orbit", actor = ball.id, target = post.id, range = Fellows.POST }, events)
    end
  else
    local sights: { System.Object } = {}
    for _, list in { worlds, belts } do
      for _, object in list do
        table.insert(sights, object)
      end
    end
    if #sights == 0 then
      return
    end
    local sight = sights[Rng.Int(rng, #sights) + 1]
    local x, y, z = near(rng, sight, 8000, 20000)
    launch(state, member, system, x, y, z, events)
    member.task, member.goal = "work", sight.id
  end
end

-- A member's ship goes in to the nearest station (or, with none to go
-- in to, away).
local function goHome(state: State.State, member: State.Member, ball: State.Ball, events: { Event })
  local id = ball.id
  if state.pilots[id] then
    state.pilots[id] = nil
    State.RemoveId(state.pilotIds, id)
  end
  ball.vitals.locks = {}
  ball.vitals.running = {}
  local station = nearestStation(state, ball)
  if station and order(state, { kind = "Dock", actor = id, target = station.id }, events) then
    member.task, member.goal, member.since = "home", station.id, state.tick
  else
    Members.Recall(state, member, events)
    member.task, member.back = "", state.tick + Fellows.AWAY
  end
end

-- Send a ship on to the place it is for, when it is not there and not
-- on its way: by warp, or under its own power if that is refused.
local function make(state: State.State, ball: State.Ball, goal: number, events: { Event })
  if ball.intent == nil and ball.mode ~= "approach" then
    if not order(state, { kind = "WarpTo", actor = ball.id, target = goal }, events) then
      order(state, { kind = "Approach", actor = ball.id, target = goal }, events)
    end
  end
end

-- A member's ship that is out: one tick of what it is at.
local function drive(state: State.State, member: State.Member, events: { Event })
  local id = member.ship
  local ship = state.ships[id]
  local ball = state.balls[id]
  -- (home is a tower: nobody docks at one, 2026-11-22. The ship is parked
  -- in its field for its rest, there to be seen, and then goes on)
  if ball and member.task == "home" and ship.moored ~= nil and ship.moored == member.goal then
    member.task, member.back = "parked", state.tick + Fellows.REST
    order(state, { kind = "Stop", actor = id }, events)
    return
  elseif member.task == "parked" then
    if state.tick >= member.back then
      local station = member.goal
      Members.Recall(state, member, events, "docked")
      member.task, member.goal, member.back = "rest", station, state.tick
    end
    return
  end
  if ship.docked ~= 0 and member.task == "home" then
    -- In: and out again after a while.
    local station = ship.docked
    Members.Recall(state, member, events, "docked")
    member.task, member.goal, member.back = "rest", station, state.tick + Fellows.REST
    return
  elseif ball == nil then
    -- (in a station, and meant to be out of it: the order to leave came to nothing, so it is given again)
    order(state, { kind = "Undock", actor = id }, events)
    return
  elseif ball.warp ~= nil then
    return
  elseif member.task == "home" then
    -- (an order to dock that came to nothing: give it again)
    if ball.intent == nil and state.tick - member.since > 30 then
      member.since = state.tick
      if not order(state, { kind = "Dock", actor = id, target = member.goal }, events) then
        goHome(state, member, ball, events)
      end
    end
    return
  end
  local shaken = ball.vitals.shield < Fellows.SHAKEN * ball.vitals.shieldMax
  if Members.Acts(member) == "miner" then
    local post = Space.Object(state, member.goal)
    if member.task == "out" and post and ball.grid ~= post.id then
      make(state, ball, post.id, events)
    elseif post == nil or ball.grid ~= post.id or shaken or hunted(state, id) or not Digger.Work(state, ball, post, events) then
      goHome(state, member, ball, events)
    else
      member.task = "work"
    end
  elseif Members.Acts(member) == "hauler" then
    -- (bound for its gate: there, a moment, and it is through)
    if ball.grid == member.goal then
      member.wait += 1
      if member.wait > 5 then
        local gate = member.goal
        Members.Recall(state, member, events, "jumped", gate)
        member.task, member.goal, member.back = "away", gate, state.tick + Fellows.AWAY
      end
    else
      make(state, ball, member.goal, events)
    end
  elseif Members.Acts(member) == "fighter" then
    local fighting = state.pilots[id] ~= nil
    if left(ball) < Fellows.HURT then
      goHome(state, member, ball, events)
    elseif pirateNear(state, ball) then
      -- (from here it does what anybody does who fights: Pirates.Think)
      if not fighting then
        state.pilots[id] = { ship = id, range = Fellows.Kind(member).range, prey = 0, home = member.goal, alone = 0, bounty = 0, tags = 0,
          side = Wars.PILOT }
        State.InsertId(state.pilotIds, id)
      end
    else
      if fighting then
        state.pilots[id] = nil
        State.RemoveId(state.pilotIds, id)
        ball.vitals.locks = {}
        ball.vitals.running = {}
      end
      local foe = trouble(state, ball)
      if foe then
        order(state, { kind = "WarpTo", actor = id, target = foe.id, range = Fellows.ANSWER }, events)
      elseif ball.grid ~= member.goal then
        make(state, ball, member.goal, events)
      else
        member.task = "work"
        if not (ball.mode == "orbit" and ball.target == member.goal) then
          order(state, { kind = "Orbit", actor = id, target = member.goal, range = Fellows.POST }, events)
        end
      end
    end
  else
    -- A scout: on to somewhere else when they have been here a while, or it is no place to be.
    if shaken or hunted(state, id) or state.tick - member.since >= Fellows.SURVEY then
      local _, belts, _, worlds = places(state, ball.system)
      local sights: { System.Object } = {}
      for _, list in { worlds, belts } do
        for _, object in list do
          if object.id ~= member.goal then
            table.insert(sights, object)
          end
        end
      end
      if #sights > 0 then
        local sight = sights[Rng.Int(Rng.For(state.historySeed, state.tick, member.id, 167), #sights) + 1]
        if order(state, { kind = "WarpTo", actor = id, target = sight.id, range = 12000 }, events) then
          member.goal, member.since = sight.id, state.tick
        end
      end
    end
  end
end

-- Once a tick. 'first' is where this tick's events begin in 'events'.
function Fellows.Step(state: State.State, events: { Event }, first: number)
  local membership = state.membership
  if #membership.memberIds == 0 then
    return
  end
  -- A member's ship that was destroyed this tick is their loss.
  for at = first, #events do
    local event = events[at]
    if event.kind == "BallDestroyed" then
      local member = Members.Of(state, event.ball)
      if member then
        Members.Lost(state, member, event.by, events)
      end
    end
  end
  local me = state.ships[state.player.ship]
  local mine = state.balls[state.player.ship]
  local system = if mine then mine.system elseif me then Space.SystemOf(state, me.docked) else 0
  for _, id in table.clone(membership.memberIds) do
    local member = membership.members[id]
    if member == nil then
      continue
    end
    if member.ship ~= 0 and state.ships[member.ship] == nil then
      -- (gone, and nobody said it was destroyed: it is not lost)
      member.ship, member.task = 0, ""
    end
    -- (one in the pilot's fleet flies a ship of theirs there: Tactical/Fleet)
    if member.fleet ~= 0 then
      if member.ship ~= 0 then
        Members.Recall(state, member, events)
        member.task = ""
      end
      continue
    end
    if member.ship ~= 0 then
      local pilot = state.pilots[member.ship]
      if pilot and pilot.worth then
        -- (at a siege's lines: Tactical/Fronts has it)
        continue
      elseif member.system ~= system then
        Members.Recall(state, member, events)
        member.task, member.back = "", 0
      else
        drive(state, member, events)
      end
    elseif member.system ~= system then
      member.task, member.back = "", 0
    elseif state.tick >= member.back and state.tick >= member.refit then
      appear(state, member, system, events)
    end
  end
end

return Fellows
