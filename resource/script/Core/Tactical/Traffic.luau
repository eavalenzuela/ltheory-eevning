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
-- A pilot who fires on anybody but a pirate is marked for a quarter of
-- an hour (Combat does the marking). While that lasts, a patrol that
-- shares a grid with them fights them, as a pirate would.
--
-- (A stand-in, like the pirates' rules: when the strategic layer joins
-- the game, who is about is who its trade and its navies send. Not yet:
-- police that come, guns on the stations, anybody remembering what a
-- pilot did once the mark has lapsed, miners at the belts.)

local Factions = require("@lt/Core/Data/Factions")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
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
-- Ticks a pilot stays marked after firing on somebody who is no pirate.
Traffic.MARKED = 900
-- What anybody flies.
local CIVILIAN = "industrial.hauler"
-- What a hauler may have aboard, for whoever takes it.
local CARGO = { "ore.ferrite", "mineral.iron", "mineral.silicon", "planet.water", "planet.alloys", "component.plating" }

local GUNS: { [string]: string } = { projectile = "autocannon.small", laser = "laser.pulse.small", hybrid = "blaster.small" }

-- A faction's hull of a class, if it has one.
local function hullOf(faction: string, class: string): string?
  for _, hull in Ships.list do
    if hull.lineage == faction and hull.class == class then
      return hull.id
    end
  end
  return nil
end

-- What a patrol ship of a faction is: a frigate or a destroyer of its
-- own, with its own kind of gun on every hardpoint.
local function patrolKind(faction: Factions.Faction, class: string): Pirates.Kind?
  local hull = hullOf(faction.id, class)
  if hull == nil then
    return nil
  end
  local fit: { { string } } = {}
  for _ = 1, 8 do
    table.insert(fit, { GUNS[faction.weapon] or "autocannon.small" })
  end
  for _ = 1, 4 do
    table.insert(fit, { "launcher.light" })
  end
  for _, module in { "afterburner.1mn", "armor.plate.200mm", "damage.control", "shield.extender.small" } do
    table.insert(fit, { module })
  end
  return { id = "patrol", hull = hull, name = `{faction.name} Patrol`, range = 2500, bounty = 0, tags = 0, fit = fit }
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

-- Once a tick: see to the ships there are, and now and then bring
-- another.
function Traffic.Step(state: State.State, events: { Event })
  local me = state.ships[state.player.ship]
  if me == nil or not state.trafficOn then
    return
  end
  local mine = state.balls[me.id]
  local system = if mine then mine.system else Space.SystemOf(state, me.docked)
  local marked = state.tick < state.player.marked
  local haulers, patrols = 0, 0
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
      haulers += 1
      if ship.docked ~= 0 and record.kind == "in" then
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
end

return Traffic
