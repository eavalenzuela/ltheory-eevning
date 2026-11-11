--!strict
-- Traffic: the other ships about.
--
-- Wherever the pilot is, the system has ships of its own going about
-- their business: haulers coming in by a gate to dock, haulers leaving a
-- station for a gate, and in space somebody holds, the faction's
-- patrols on station at a gate. How many follows from how safe the
-- system is (Describe/Galaxy). They fly with the orders a pilot gives,
-- in the hulls of the faction whose space it is (or the hull anybody
-- flies), and are real ships: they can be locked, shot and looted.
--
-- Only the system the pilot is in has any: a hauler is put into space
-- at a gate as if it had just jumped in, or in a station as if it had
-- been there, and is taken away again when it docks or reaches the gate
-- it was making for. Nothing follows it to the next system.
--
-- And where order is kept there are miners at the belts: a mining
-- frigate or two cutting rock (the rocks are the worse for it), which
-- go in to a station when their holds are full, when a pirate turns
-- up, or when somebody shoots at them.
--
-- A pilot who fires on anybody but a pirate is marked for a quarter of
-- an hour (Combat does the marking). While that lasts, a patrol that
-- shares a grid with them fights them, as a pirate would. And in secure
-- space the police come: within a quarter of a minute a pair of the
-- faction's ships arrives wherever the marked pilot is (destroyers for
-- a small ship, cruisers for a cruiser, battleships for a battleship),
-- and more after them, up to four, which follow the pilot about the
-- system and go when the mark has lapsed.
--
-- (A stand-in, like the pirates' rules: when the strategic layer joins
-- the game, who is about is who its trade and its navies send.)

local Digger = require("@lt/Core/Tactical/Digger")
local Factions = require("@lt/Core/Data/Factions")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local Standings = require("@lt/Core/Assets/Standings")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")

local Traffic = {}

export type Event = { [string]: any }

-- Ticks between one look for somebody new and the next. (A hauler is
-- about for most of a minute, so a system that may have five has three
-- or so at a time.)
Traffic.INTERVAL = 15
-- Where nobody keeps order hardly anybody comes: the chance, at each
-- look, that somebody does.
Traffic.LAWLESS = 0.15
-- Haulers and patrol ships a system has about at once, by how safe it is.
Traffic.HAULERS = { secure = 5, low = 2, lawless = 1 } :: { [string]: number }
Traffic.PATROLS = { secure = 2, low = 1, lawless = 0 } :: { [string]: number }
-- Miners at the belts, likewise.
Traffic.MINERS = { secure = 2, low = 1, lawless = 0 } :: { [string]: number }
-- Police ships that come for a marked pilot in secure space, at most.
Traffic.POLICE = 4
-- Ticks a pilot stays marked after firing on somebody who is no pirate.
Traffic.MARKED = 900
-- What a miner flies, and cuts with.
local MINER, LASER = "frigate.prospector", "miner.small"
-- What anybody flies.
local CIVILIAN = "industrial.hauler"
-- What a hauler may have aboard, for whoever takes it.
local CARGO = { "ore.ferrite", "mineral.iron", "mineral.silicon", "planet.water", "planet.alloys", "component.plating" }

local GUNS: { [string]: string } = { projectile = "autocannon", laser = "laser.pulse", hybrid = "blaster" }
-- What goes on a hull of each size: its guns' and fittings' size, and
-- its launchers.
local SIZES = { "small", "medium", "large" }
local LAUNCHERS = { "launcher.light", "launcher.heavy", "launcher.cruise" }
local FITTINGS = {
  { "afterburner.1mn", "armor.plate.200mm", "damage.control", "shield.extender.small" },
  { "afterburner.medium", "armor.plate.medium", "damage.control", "shield.extender.medium" },
  { "afterburner.large", "armor.plate.large", "damage.control", "shield.extender.large" },
}

-- A faction's hull of a class, if it has one.
local function hullOf(faction: string, class: string): string?
  for _, hull in Ships.list do
    if hull.lineage == faction and hull.class == class then
      return hull.id
    end
  end
  return nil
end

-- What a patrol ship of a faction is: a hull of its own of a class,
-- with its own kind of gun on every hardpoint, of the size the hull
-- carries (a frigate's and a destroyer's are small, a cruiser's medium,
-- a battleship's large).
local function patrolKind(faction: Factions.Faction, class: string): Pirates.Kind?
  local hull = hullOf(faction.id, class)
  if hull == nil then
    return nil
  end
  local size = if class == "battleship" then 3 elseif class == "cruiser" then 2 else 1
  local fit: { { string } } = {}
  for _ = 1, 8 do
    table.insert(fit, { `{GUNS[faction.weapon] or "autocannon"}.{SIZES[size]}` })
  end
  for _ = 1, 4 do
    table.insert(fit, { LAUNCHERS[size] })
  end
  for _, module in FITTINGS[size] do
    table.insert(fit, { module })
  end
  return { id = "patrol", hull = hull, name = `{faction.name} Patrol`, range = 2500 * size, bounty = 0, tags = 0, fit = fit }
end

-- Take a ship of the traffic out of the game: its ball, what it
-- carries, and every record of it.
local function remove(state: State.State, id: number, reason: string, events: { Event })
  local ball = state.balls[id]
  if ball then
    Space.RemoveBall(state, ball)
    table.insert(events, { kind = "BallRemoved", ball = id, reason = reason })
  end
  for _, item in Items.In(state, id, nil) do
    Items.Take(state, item, item.quantity)
  end
  if state.ships[id] then
    state.ships[id] = nil
    State.RemoveId(state.shipIds, id)
  end
  if state.pilots[id] then
    state.pilots[id] = nil
    State.RemoveId(state.pilotIds, id)
  end
  state.traffic[id] = nil
  State.RemoveId(state.trafficIds, id)
end

local function order(state: State.State, command: State.Command, events: { Event }): boolean
  if Space.Validate(state, command) then
    Space.Apply(state, command, events)
    return true
  end
  return false
end

local function enlist(state: State.State, ship: State.Ship, kind: string, goal: number, system: number)
  state.traffic[ship.id] = { ship = ship.id, kind = kind, goal = goal, system = system, born = state.tick, wait = 0 }
  State.InsertId(state.trafficIds, ship.id)
end

-- A point a few kilometres off a place, rolled.
local function near(rng: Rng.Rng, site: System.Object, least: number, most: number): (number, number, number)
  local angle = Rng.Float(rng, 0, 2 * math.pi)
  local out = site.radius + Rng.Float(rng, least, most)
  return site.x + out * math.cos(angle), site.y + Rng.Float(rng, -1500, 1500), site.z + out * math.sin(angle)
end

-- Bring one hauler into the system: in by a gate and bound for a
-- station, out of a station and bound for a gate, or (where there is no
-- station) passing through from gate to gate.
local function hauler(state: State.State, system: number, rng: Rng.Rng, events: { Event })
  local gates: { System.Object } = {}
  local stations: { System.Object } = {}
  for _, object in Space.Describe(state, system).objects do
    if object.kind == "gate" then
      table.insert(gates, object)
    elseif object.kind == "station" and state.starbases[object.id] == nil then
      table.insert(stations, object)
    end
  end
  if #gates == 0 or (#stations == 0 and #gates < 2) then
    return
  end
  local node = state.galaxy.systems[system]
  local faction = Factions.byId[node.nearest]
  local own = if node.owner ~= "" and Rng.Chance(rng, 0.6) then hullOf(node.owner, "industrial") else nil
  local type = own or CIVILIAN
  local name = if own then `{faction.name} Hauler` else "Trader"
  local owner = if own then node.owner else "civilian"
  local gate = gates[Rng.Int(rng, #gates) + 1]
  local outbound = #stations > 0 and Rng.Chance(rng, 0.5)
  local ship: State.Ship
  if outbound then
    local station = stations[Rng.Int(rng, #stations) + 1]
    ship = Space.NewShip(state, type, name, owner, station.id)
    enlist(state, ship, "out", gate.id, system)
    order(state, { kind = "Undock", actor = ship.id }, events)
  else
    ship = Space.NewShip(state, type, name, owner, 0)
    local x, y, z = near(rng, gate, 3000, 8000)
    local ball = Space.Launch(state, ship, system, x, y, z)
    table.insert(events, { kind = "BallAdded", ball = ball.id })
    if #stations > 0 then
      local station = stations[Rng.Int(rng, #stations) + 1]
      enlist(state, ship, "in", station.id, system)
      order(state, { kind = "Dock", actor = ship.id, target = station.id }, events)
    else
      local other = gates[(table.find(gates, gate) :: number) % #gates + 1]
      enlist(state, ship, "out", other.id, system)
    end
  end
  Items.Add(state, CARGO[Rng.Int(rng, #CARGO) + 1], 50 + Rng.Int(rng, 350), ship.id, "cargo")
end

-- Put a patrol ship of the system's faction on station at a gate (or,
-- with no gate, at a station).
local function patrol(state: State.State, system: number, rng: Rng.Rng, events: { Event })
  local faction = Factions.byId[state.galaxy.systems[system].owner]
  local kind = if faction then patrolKind(faction, if Rng.Chance(rng, 0.4) then "destroyer" else "frigate") else nil
  local sites: { System.Object } = {}
  for _, object in Space.Describe(state, system).objects do
    if object.kind == "gate" then
      table.insert(sites, object)
    end
  end
  if #sites == 0 then
    for _, object in Space.Describe(state, system).objects do
      if object.kind == "station" then
        table.insert(sites, object)
      end
    end
  end
  if faction == nil or kind == nil or #sites == 0 then
    return
  end
  local site = sites[Rng.Int(rng, #sites) + 1]
  local ship = Space.NewShip(state, kind.hull, kind.name, faction.id, 0)
  Pirates.Equip(state, ship, kind)
  local x, y, z = near(rng, site, 5000, 9000)
  local ball = Space.Launch(state, ship, system, x, y, z)
  table.insert(events, { kind = "BallAdded", ball = ball.id })
  enlist(state, ship, "patrol", site.id, system)
  order(state, { kind = "Orbit", actor = ship.id, target = site.id, range = 6000 }, events)
end

-- Put a miner at one of the system's belts (not one that is on nobody's
-- chart), if there is a station for it to go home to.
local function miner(state: State.State, system: number, rng: Rng.Rng, events: { Event })
  local belts: { System.Object } = {}
  local home = false
  for _, object in Space.Describe(state, system).objects do
    if object.kind == "belt" and state.sites[object.id] == nil then
      table.insert(belts, object)
    elseif object.kind == "station" and state.starbases[object.id] == nil then
      home = true
    end
  end
  if #belts == 0 or not home then
    return
  end
  local belt = belts[Rng.Int(rng, #belts) + 1]
  local ship = Space.NewShip(state, MINER, "Miner", "civilian", 0)
  Items.Equip(state, ship.id, LASER, nil)
  Items.Equip(state, ship.id, LASER, nil)
  local x, y, z = near(rng, belt, 6000, 16000)
  local ball = Space.Launch(state, ship, system, x, y, z)
  table.insert(events, { kind = "BallAdded", ball = ball.id })
  enlist(state, ship, "miner", belt.id, system)
end

-- The station nearest a ship, of those anybody may dock at.
local function nearestStation(state: State.State, ball: State.Ball): System.Object?
  local best: System.Object?, least = nil, math.huge
  for _, object in Space.Describe(state, ball.system).objects do
    if object.kind == "station" and state.starbases[object.id] == nil then
      local far = Space.Distance(object :: any, ball :: any)
      if far < least then
        best, least = object, far
      end
    end
  end
  return best
end

-- Whether a pirate is on a ship's grid.
local function pirateNear(state: State.State, ball: State.Ball): boolean
  for _, id in state.pilotIds do
    local other = state.balls[id]
    if other and other.system == ball.system and other.grid == ball.grid and state.ships[id].owner == "pirates" then
      return true
    end
  end
  return false
end

-- The police: two ships of the system's faction, out of warp a few
-- kilometres from the marked pilot. They come in what it takes: in
-- destroyers for anything small, in cruisers for a cruiser, and in
-- battleships for a battleship.
local function police(state: State.State, mine: State.Ball, rng: Rng.Rng, events: { Event }): number
  local faction = Factions.byId[state.galaxy.systems[mine.system].owner]
  local flown = Ships.byId[state.ships[mine.id].type].class
  local class = if flown == "battleship" or flown == "cruiser" then flown else "destroyer"
  local kind = if faction then patrolKind(faction, class) or patrolKind(faction, "destroyer") or patrolKind(faction, "frigate") else nil
  if faction == nil or kind == nil then
    return 0
  end
  for _ = 1, 2 do
    local ship = Space.NewShip(state, kind.hull, `{faction.name} Police`, faction.id, 0)
    Pirates.Equip(state, ship, kind)
    local angle = Rng.Float(rng, 0, 2 * math.pi)
    local out = Rng.Float(rng, 7000, 11000)
    local ball = Space.Launch(state, ship, mine.system, mine.x + out * math.cos(angle), mine.y + Rng.Float(rng, -1500, 1500),
      mine.z + out * math.sin(angle))
    table.insert(events, { kind = "BallAdded", ball = ball.id })
    enlist(state, ship, "police", 0, mine.system)
  end
  table.insert(events, { kind = "PoliceArrived", count = 2, faction = faction.id })
  return 2
end

-- Once a tick: see to the ships there are, and now and then bring
-- another.
function Traffic.Step(state: State.State, events: { Event })
  local me = state.ships[state.player.ship]
  if me == nil or not state.trafficOn then
    return
  end
  local mine = state.balls[me.id]
  local system = if mine then mine.system else Space.SystemOf(state, me.docked)
  -- (a pilot the system's faction thinks ill enough of is fought on
  -- sight, mark or no mark: Assets/Standings)
  local marked = state.tick < state.player.marked or Standings.Hostile(state, state.galaxy.systems[system].owner)
  local haulers, patrols, miners, lawmen = 0, 0, 0, 0
  for _, id in table.clone(state.trafficIds) do
    local record = state.traffic[id]
    local ship = state.ships[id]
    local ball = state.balls[id]
    if ship == nil then
      -- (destroyed: whoever did it has seen to the rest)
      state.traffic[id] = nil
      State.RemoveId(state.trafficIds, id)
    elseif record.system ~= system then
      remove(state, id, "left", events)
    elseif record.kind == "miner" then
      miners += 1
      if ball and ball.warp == nil and ball.intent == nil then
        -- At the belt it cuts rock (Tactical/Digger). A full hold, a belt
        -- with nothing left, a pirate, or somebody's fire sends it home:
        -- from then on it is a ship coming in to dock, like any other.
        local post = Space.Object(state, record.goal)
        local hurt = ball.vitals.shield < 0.6 * ball.vitals.shieldMax
        if post == nil or ball.grid ~= post.id or hurt or pirateNear(state, ball) or not Digger.Work(state, ball, post, events) then
          local station = nearestStation(state, ball)
          if station then
            ball.vitals.locks = {}
            record.kind, record.goal, record.born = "home", station.id, state.tick
            order(state, { kind = "Dock", actor = id, target = station.id }, events)
          else
            remove(state, id, "left", events)
          end
        end
      end
    elseif record.kind == "police" then
      local fighting = state.pilots[id] ~= nil
      local sees = marked and mine ~= nil and ball ~= nil and mine.grid == ball.grid and mine.grid ~= 0
      lawmen += if sees then 1 else 0
      if sees and not fighting then
        state.pilots[id] = { ship = id, range = 2500, prey = 0, home = 0, alone = 0, bounty = 0, tags = 0 }
        State.InsertId(state.pilotIds, id)
      elseif not marked then
        -- (it is over: they go)
        remove(state, id, "left", events)
      elseif not sees and mine and ball and ball.warp == nil and mine.grid ~= 0 then
        -- The pilot has gone somewhere else in the system: after them.
        if fighting then
          state.pilots[id] = nil
          State.RemoveId(state.pilotIds, id)
          ball.vitals.locks = {}
          ball.vitals.running = {}
        end
        order(state, { kind = "WarpTo", actor = id, target = mine.id, range = 8000 }, events)
      end
    elseif record.kind == "patrol" then
      patrols += 1
      local fighting = state.pilots[id] ~= nil
      local sees = marked and mine ~= nil and ball ~= nil and mine.grid == ball.grid
      if sees and not fighting then
        -- (from here it does what a pirate does: Pirates.Think)
        state.pilots[id] = { ship = id, range = 2500, prey = 0, home = record.goal, alone = 0, bounty = 0, tags = 0 }
        State.InsertId(state.pilotIds, id)
      elseif fighting and not marked then
        state.pilots[id] = nil
        State.RemoveId(state.pilotIds, id)
        if ball then
          ball.vitals.locks = {}
          ball.vitals.running = {}
          order(state, { kind = "Orbit", actor = id, target = record.goal, range = 6000 }, events)
        end
      end
    else
      -- (a miner going "home" docks as a hauler coming "in" does)
      if record.kind == "home" then
        miners += 1
      else
        haulers += 1
      end
      if ship.docked ~= 0 and (record.kind == "in" or record.kind == "home") then
        remove(state, id, "docked", events)
      elseif ball and ball.warp == nil and ball.intent == nil then
        if ball.grid == record.goal and record.kind == "out" then
          -- At its gate: a moment, and it is through.
          record.wait += 1
          if record.wait > 5 then
            remove(state, id, "jumped", events)
          end
        elseif record.kind == "out" then
          if not order(state, { kind = "WarpTo", actor = id, target = record.goal }, events) then
            order(state, { kind = "Approach", actor = id, target = record.goal }, events)
          end
        elseif state.tick - record.born > 30 then
          -- (an order to dock that came to nothing: give it again)
          order(state, { kind = "Dock", actor = id, target = record.goal }, events)
        end
      end
    end
  end

  if state.tick < state.trafficDue then
    return
  end
  state.trafficDue = state.tick + Traffic.INTERVAL
  local band = Galaxy.Band(state.galaxy.systems[system].security)
  local rng = Rng.For(state.historySeed, state.tick, system, 57)
  if haulers < Traffic.HAULERS[band] and (band ~= "lawless" or Rng.Chance(rng, Traffic.LAWLESS)) then
    hauler(state, system, rng, events)
  end
  if patrols < Traffic.PATROLS[band] then
    patrol(state, system, rng, events)
  end
  if miners < Traffic.MINERS[band] and state.galaxy.systems[system].owner ~= "" then
    miner(state, system, rng, events)
  end
  -- The police, for a marked pilot in secure space: wherever they are.
  if marked and mine and mine.grid ~= 0 and band == "secure" and lawmen < Traffic.POLICE then
    police(state, mine, rng, events)
  end
end

return Traffic
