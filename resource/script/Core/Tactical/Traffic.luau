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
-- Where order is kept, now and then one of the traders is a freighter,
-- with a hold to match.
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
-- And in the space of a people who keep no stations, a colony fleet
-- may be passing through (Tactical/Nomads says where each is): their
-- colony ship and the support fleet it has in tow. It comes in by the
-- gate from the system it was in, crosses to the gate it will go out
-- by, and lies off that until it goes. It is there for the pilot who is
-- there to see it, as all of this is; and it fights whoever its people
-- would fight, with everything it has. It is a station too, the only
-- kind its people have: a pilot docks at it (Tactical/Space), and for a
-- pilot who is aboard it is there with its fleet round it, as it is for
-- one in space beside it.
--
-- And a people whose yards build a jumpship for it work the belts of
-- their own space in fleets (the Vail, whose Archangel's jump drive has
-- a field; the project owner's, 2026-11-15, of whether they should:
-- "yes, but only in their space. They jump back to friendly stations.
-- Warp disrupting a ship prevents the archangel from jumping it."):
--   - A fleet is their mining barges cutting rock, the capital
--     industrial that leads them, whose ore hold the barges empty into,
--     and the jumpship, which keeps by them. In a system of theirs with
--     a belt on the chart there is one at work on about half the days,
--     if there is a station of theirs in another system for it to run
--     to, within its drive's reach.
--   - When anything of it is hit, when a pirate comes on its grid, or a
--     pilot its people fight does, the jumpship makes its drive ready
--     (Traffic.SPOOL), while the fleet leaves its work and closes on
--     it; and then it jumps, with every ship of the fleet that is
--     within its field and that nothing holds (Tactical/Jumping's rule
--     of who a field takes). They are gone to that station, and no
--     fleet works the system again for a while (Traffic.FLEET_AWAY).
--   - A barge that is warp disrupted, or too far off, is left: it makes
--     for a station in the system when it can, as a miner does. The
--     jumpship itself is a capital, and is held only by a capital warp
--     disruptor (Tactical/Combat): held, it waits, and jumps when it is
--     let go.
--   - A fleet whose leader's ore hold is full goes home the same way,
--     with nobody after it. A fleet whose jumpship is destroyed is not
--     replaced for a day, and what is left of it goes in to dock.
--   (How many barges, how often, the warning and the waits are first
--   figures, and not the owner's.)
--
-- (A stand-in, like the pirates' rules: when the strategic layer joins
-- the game, who is about is who its trade and its navies send.)

local Commerce = require("@lt/Core/Strategic/Commerce")
local Constants = require("@lt/Core/Data/Constants")
local Digger = require("@lt/Core/Tactical/Digger")
local Factions = require("@lt/Core/Data/Factions")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Jumping = require("@lt/Core/Tactical/Jumping")
local Mining = require("@lt/Core/Tactical/Mining")
local Nomads = require("@lt/Core/Tactical/Nomads")
local Modules = require("@lt/Core/Data/Modules")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local Sides = require("@lt/Core/Tactical/Sides")
local Space = require("@lt/Core/Tactical/Space")
local Standings = require("@lt/Core/Assets/Standings")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")
local Types = require("@lt/Core/Data/Types")

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
-- Mining fleets (above). The chance, by the day, that a system of a
-- people who fly them has one at work; the barges in one; the ticks
-- from the alarm to the jump; and the ticks a system is without a fleet
-- after one has jumped out of it, and after one has lost its jumpship.
Traffic.FLEETS = 0.5
Traffic.FLEET_BARGES = 4
Traffic.SPOOL = 20
Traffic.FLEET_AWAY = 1800
Traffic.FLEET_LOST = math.ceil(86400 / Constants.TICK)
-- A ship of a fleet has been hit when its shield is under this share of
-- what it holds.
Traffic.FLEET_HIT = 0.9
-- What a fleet's barge cuts with.
local STRIP = "miner.strip"
-- What a fleet's ships are in the traffic: its jumpship, the capital
-- industrial that leads it, and its barges.
local FLEET_JUMP, FLEET_BOSS, FLEET_BARGE = "fleet.jump", "fleet.boss", "fleet.barge"
local FLEET_KINDS: { [string]: boolean } = { [FLEET_JUMP] = true, [FLEET_BOSS] = true, [FLEET_BARGE] = true }
-- How far a fleet's drive reaches, light years: as far as anybody's
-- does who has learned all there is of it (Tactical/Jumping).
local FLEET_REACH = Jumping.RANGE * (1 + 5 * Jumping.FURTHER)
-- And how many gates off its people's nearest station is looked for.
local REFUGE_JUMPS = 6
local DAY = math.ceil(86400 / Constants.TICK)
-- What a miner cuts with (and flies, its people's barge: below).
local LASER = "miner.small"
-- How often a trader who comes to secure space flies a freighter.
Traffic.FREIGHTERS = 0.3
local GUNS: { [string]: string } = { projectile = "autocannon", laser = "laser.pulse", hybrid = "blaster" }
-- What goes on a hull of each size: its guns' and fittings' size, and
-- its launchers. (The fourth size is what only the largest hulls
-- mount: a colony ship has hardpoints of every size.)
local SIZES = { "small", "medium", "large", "xl" }
local LAUNCHERS = { "launcher.light", "launcher.heavy", "launcher.cruise", "launcher.siege" }
-- How far off the gate it lies by a colony ship keeps, and how far off
-- the colony ship the nearest of its support fleet: metres between
-- surfaces.
Traffic.COLONY_OFF = Nomads.OFF
Traffic.ESCORT_OFF = 3000
local FITTINGS = {
  { "afterburner.1mn", "armor.plate.200mm", "damage.control", "shield.extender.small" },
  { "afterburner.medium", "armor.plate.medium", "damage.control", "shield.extender.medium" },
  { "afterburner.large", "armor.plate.large", "damage.control", "shield.extender.large" },
}

-- A faction's hull of a class, if it has one.
local function hullOf(faction: string, class: string): string?
  for _, hull in Ships.list do
    -- (the plain hull: a patrol does not fly its faction's tech 2)
    if hull.lineage == faction and hull.class == class and hull.tech ~= 2 then
      return hull.id
    end
  end
  return nil
end

-- The plain hull of a class of the first people who build one, for a
-- people who build none (since 2026-11-18 there are no hulls nobody's
-- yards build: Data/Ships).
local function anybodys(class: string): string
  for _, hull in Ships.list do
    local people = Factions.byId[hull.lineage]
    if people and people.kind == "human" and hull.class == class and hull.tech ~= 2 and hull.role == nil and not hull.restricted then
      return hull.id
    end
  end
  error(`no people builds a hull of class {class}`)
end

-- A hull as a ship that fights, fitted as a people's patrols are: the
-- kind of gun named (a people's own; anybody's, with none named) on
-- every hardpoint, of the size the hull carries (a frigate's and a
-- destroyer's are small, a cruiser's medium, a battleship's large), its
-- launchers, and what keeps it alive. ('name': what it goes by.)
function Traffic.Fitted(hull: string, weapon: string?, name: string): Pirates.Kind
  local class = Ships.byId[hull].class
  -- (a battlecruiser carries a cruiser's guns: the owner's ladder)
  local size = if class == "battleship" or class == "carrier" then 3 elseif class == "cruiser" or class == "battlecruiser" then 2 else 1
  local fit: { { string } } = {}
  for _ = 1, 8 do
    table.insert(fit, { `{GUNS[weapon or ""] or "autocannon"}.{SIZES[size]}` })
  end
  for _ = 1, 4 do
    table.insert(fit, { LAUNCHERS[size] })
  end
  -- (a hull with no shield, which mends by itself, has its people's own
  -- gear where another's shield extender goes: the Nimia's lattice)
  local mends = (Ships.byId[hull].armorMend or 0) > 0
  for _, module in FITTINGS[size] do
    table.insert(fit, { if mends and string.sub(module, 1, 7) == "shield." then "mend.lattice" else module })
  end
  return { id = "patrol", hull = hull, name = name, range = 2500 * size, bounty = 0, tags = 0, fit = fit }
end

-- What a patrol ship of a faction is: a hull of its own of a class,
-- with its own kind of gun on every hardpoint.
local function patrolKind(faction: Factions.Faction, class: string): Pirates.Kind?
  local hull = hullOf(faction.id, class)
  if hull == nil then
    return nil
  end
  return Traffic.Fitted(hull, faction.weapon, `{faction.name} Patrol`)
end

-- Take a ship of the traffic out of the game: its ball, what it
-- carries, and every record of it. ('gate': the gate it went out by,
-- for one that has jumped: the view lights it.)
local function remove(state: State.State, id: number, reason: string, events: { Event }, gate: number?)
  local ball = state.balls[id]
  if ball then
    Space.RemoveBall(state, ball)
    table.insert(events, { kind = "BallRemoved", ball = id, reason = reason, gate = gate })
  end
  for _, item in Items.In(state, id, nil) do
    Items.Take(state, item, item.quantity)
  end
  -- (a hauler that got where it was going, or went on out of sight:
  -- what it carried of the economy's is where it was for)
  local record = state.traffic[id]
  if record and record.carries then
    Commerce.Deliver(state.commerce, record.carries.node, record.carries.class, record.carries.amount)
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

-- What a ship of a faction's force is (Tactical/Fronts): a hull of its
-- own of a class with its own guns on it, as its patrols are; for the
-- pirates, the kind of theirs that flies that class. Nil for a faction
-- that builds no such hull.
local PIRATE: { [string]: string } = { frigate = "raider", cruiser = "marauder", battleship = "ravager" }
function Traffic.Warship(faction: string, class: string): Pirates.Kind?
  local its = Factions.byId[faction]
  if its == nil then
    return nil
  elseif its.kind == "pirate" then
    return Pirates.kindById[PIRATE[class] or "raider"]
  end
  local kind = patrolKind(its, class)
  if kind then
    kind.name = `{its.name} {if class == "battleship" then "Battleship" elseif class == "cruiser" then "Cruiser" else "Frigate"}`
  end
  return kind
end

local blockading: (state: State.State, system: number, faction: string) -> boolean

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
    -- (a stargate: not the gate of a pirate camp, which leads to a place)
    if object.kind == "gate" and object.variety ~= "passage" then
      table.insert(gates, object)
    elseif object.kind == "station" and state.starbases[object.id] == nil then
      table.insert(stations, object)
    end
  end
  if #gates == 0 or (#stations == 0 and #gates < 2) then
    return
  end
  local node = state.galaxy.systems[system]
  -- (the faction that keeps the system, if any does: its own hauliers
  -- come by, and the pirates' space has none of anybody's)
  local keeper = Galaxy.Keeper(node)
  local own = if keeper ~= "" and Rng.Chance(rng, 0.6) then hullOf(keeper, "industrial") else nil
  -- (a trader in secure space is now and then a freighter: rolled
  -- apart, so that nothing else about who comes follows from it)
  local great = own == nil and Galaxy.Band(Galaxy.Order(node)) == "secure"
    and Rng.Chance(Rng.For(state.historySeed, state.tick, system, 131), Traffic.FREIGHTERS)
  -- A trader who is nobody's flies what is built thereabouts all the
  -- same: the hull of the people whose space it is, or where it is
  -- nobody's of the people nearest. (The owner's, 2026-11-14: no ship
  -- about is one of the plain hulls nobody's yards build. Those are left
  -- for a people who build no such hull.)
  local yard = if keeper ~= "" then keeper else node.nearest
  local plain = if great then hullOf(yard, "freighter") or hullOf(yard, "industrial") or anybodys("freighter")
    else hullOf(yard, "industrial") or anybodys("industrial")
  local type = own or plain
  local name = if own then `{Factions.byId[keeper].name} Hauler` elseif great then "Freighter" else "Trader"
  local owner = if own then keeper else "civilian"
  local gate = gates[Rng.Int(rng, #gates) + 1]
  local outbound = #stations > 0 and Rng.Chance(rng, 0.5)
  -- It carries what the economy has lately sent along one of the lanes
  -- here, for real (Strategic/Commerce): so it comes in by a gate goods
  -- have come by, or goes out by one they have gone by, if any have.
  -- (A system with no station is passed through: nothing is for it.)
  local laden = false
  if #stations > 0 then
    local beyond: { number } = {}
    for _, other in gates do
      table.insert(beyond, other.to)
    end
    local busiest, out = Commerce.Lane(state.commerce, beyond, Rng.Next(rng))
    for _, other in gates do
      if busiest and other.to == busiest then
        gate, outbound, laden = other, out, true
      end
    end
  end
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
    -- (it comes in by the gate, out through it as a ship through a gate
    -- does: Space.ComeThrough. The owner, 2026-11-21: they "should also
    -- visibly move through the gates, not just appear and disappear")
    table.insert(events, { kind = "BallAdded", ball = ball.id, gate = gate.id })
    Space.ComeThrough(state, ball, gate, events)
    if #stations > 0 then
      local station = stations[Rng.Int(rng, #stations) + 1]
      enlist(state, ship, "in", station.id, system)
      -- (and is told to dock once it is out: below)
      state.traffic[ship.id].wait = -1
    else
      local other = gates[(table.find(gates, gate) :: number) % #gates + 1]
      enlist(state, ship, "out", other.id, system)
    end
  end
  -- (what it has aboard is the economy's, and is owed to the system it
  -- is for until it is there. With nothing lately gone its way, it is
  -- in ballast: nothing comes from nowhere.)
  if laden then
    local cargo, units, owed = Commerce.Load(state.commerce, gate.to, outbound, Ships.byId[type].cargo)
    if cargo then
      Items.Add(state, cargo, units, ship.id, "cargo")
      state.traffic[ship.id].carries = { node = owed, class = Commerce.Index(cargo) :: number, amount = units }
    end
  end
end

-- Put a patrol ship of the system's faction on station at a gate (or,
-- with no gate, at a station).
local function patrol(state: State.State, system: number, rng: Rng.Rng, events: { Event })
  local faction = Factions.byId[Galaxy.Keeper(state.galaxy.systems[system])]
  local kind = if faction then patrolKind(faction, if Rng.Chance(rng, 0.4) then "destroyer" else "frigate") else nil
  local sites: { System.Object } = {}
  for _, object in Space.Describe(state, system).objects do
    if object.kind == "gate" and object.variety ~= "passage" then
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
    if object.kind == "belt" and state.sites[object.id] == nil and object.variety ~= "ice" then
      table.insert(belts, object)
    elseif object.kind == "station" and state.starbases[object.id] == nil then
      home = true
    end
  end
  if #belts == 0 or not home then
    return
  end
  local belt = belts[Rng.Int(rng, #belts) + 1]
  -- (in the barge of the people whose space it is, or the people nearest: anybody's, if they build none)
  local node = state.galaxy.systems[system]
  local keeper = Galaxy.Keeper(node)
  local yard = if keeper ~= "" then keeper else node.nearest
  local ship = Space.NewShip(state, hullOf(yard, "barge") or anybodys("barge"), "Miner", "civilian", 0)
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

-- ---------------------------------------------------------------------
-- Mining fleets

-- The hull a people's mining fleets jump out by: one of theirs whose
-- jump drive has a field, if their yards build one.
local function jumpship(faction: string): Ships.ShipType?
  for _, hull in Ships.list do
    if hull.lineage == faction and hull.jump and (hull.jumpField or 0) > 0 and hull.tech ~= 2 then
      return hull
    end
  end
  return nil
end

-- Where a fleet of a people's that jumps out of a system goes: the
-- nearest system of theirs by the gates, other than that one, which is
-- within 'reach' light years and has a station; its number, and the
-- station. 0 and nothing, if there is none within a few gates.
function Traffic.Refuge(state: State.State, system: number, faction: string, reach: number): (number, System.Object?)
  local systems = state.galaxy.systems
  local depth: { [number]: number } = { [system] = 0 }
  local queue: { number } = { system }
  local at = 1
  while at <= #queue do
    local id = queue[at]
    at += 1
    if id ~= system and Galaxy.Keeper(systems[id]) == faction and Galaxy.Apart(state.galaxy, system, id) <= reach then
      for _, object in Space.Describe(state, id).objects do
        if object.kind == "station" and state.starbases[object.id] == nil then
          return id, object
        end
      end
    end
    if depth[id] < REFUGE_JUMPS then
      for _, neighbor in systems[id].neighbors do
        if depth[neighbor] == nil then
          depth[neighbor] = depth[id] + 1
          table.insert(queue, neighbor)
        end
      end
    end
  end
  return 0, nil
end

-- Whether a mining fleet is to be at work in a system now: it is the
-- space of a people who fly them (they build the barge, the capital
-- industrial and the jumpship), the fleet that works it is not away,
-- and the day's roll for the system says so. (Whether it has a belt
-- and a station to run to is seen to when the fleet is put there.)
function Traffic.FleetDue(state: State.State, system: number): boolean
  local node = state.galaxy.systems[system]
  local keeper = if node then Galaxy.Keeper(node) else ""
  if keeper == "" or jumpship(keeper) == nil or hullOf(keeper, "barge") == nil or hullOf(keeper, "capitalindustrial") == nil then
    return false
  elseif (state.miningFleets[system] or 0) > state.tick then
    return false
  end
  return Rng.Chance(Rng.For(state.historySeed, system, state.tick // DAY, 173), Traffic.FLEETS)
end

-- Put a mining fleet at one of a system's belts: the jumpship, the
-- capital industrial beside it, and the barges about them, all well
-- within the jumpship's field. Whether it was put.
local function miningFleet(state: State.State, system: number, rng: Rng.Rng, events: { Event }): boolean
  local keeper = Galaxy.Keeper(state.galaxy.systems[system])
  local faction = Factions.byId[keeper]
  local lead, boss, barge = jumpship(keeper), hullOf(keeper, "capitalindustrial"), hullOf(keeper, "barge")
  local belts: { System.Object } = {}
  for _, object in Space.Describe(state, system).objects do
    if object.kind == "belt" and state.sites[object.id] == nil and object.variety ~= "ice" then
      table.insert(belts, object)
    end
  end
  if faction == nil or lead == nil or boss == nil or barge == nil or #belts == 0 then
    return false
  end
  -- (and somewhere to run to: they work no system they could not leave)
  if (Traffic.Refuge(state, system, keeper, FLEET_REACH)) == 0 then
    return false
  end
  local belt = belts[Rng.Int(rng, #belts) + 1]
  local x, y, z = near(rng, belt, 6000, 12000)
  -- (beside the first of its rocks with anything left in it, if it has
  -- one: the barges begin where the work is, with the others by them)
  for _, object in Space.Describe(state, system).objects do
    if Mining.Rock(object) and object.site == belt.id and Mining.Left(state, object) > 0 then
      x, y, z = object.x + object.radius + 4000, object.y, object.z
      break
    end
  end
  local function put(type: string, kind: string, dx: number, dy: number, dz: number): State.Ship
    local ship = Space.NewShip(state, type, Ships.byId[type].name, keeper, 0)
    local ball = Space.Launch(state, ship, system, x + dx, y + dy, z + dz)
    table.insert(events, { kind = "BallAdded", ball = ball.id })
    enlist(state, ship, kind, belt.id, system)
    return ship
  end
  put(lead.id, FLEET_JUMP, 0, 0, 0)
  put(boss, FLEET_BOSS, 2600, 300, 0)
  -- (the barges on the side of the jumpship away from their leader)
  for index = 1, Traffic.FLEET_BARGES do
    local angle = math.pi / 2 + math.pi * (index - 0.5) / Traffic.FLEET_BARGES
    local ship = put(barge, FLEET_BARGE, 2600 * math.cos(angle), if index % 2 == 0 then 250 else -250, 2600 * math.sin(angle))
    for _ = 1, Ships.byId[barge].turrets do
      Items.Equip(state, ship.id, STRIP, nil)
    end
  end
  table.insert(events, { kind = "MiningFleetArrived", faction = keeper, system = system, belt = belt.id, name = belt.name,
    ships = Traffic.FLEET_BARGES + 2 })
  return true
end

-- A fleet's jumpship makes its drive ready, if it is not doing so
-- already ('why': "attacked", or "full").
local function alarm(state: State.State, jump: number, why: string, events: { Event })
  local record, ball = state.traffic[jump], state.balls[jump]
  if record and ball and record.wait == 0 then
    record.wait = state.tick + Traffic.SPOOL
    table.insert(events, { kind = "FleetSpooling", ship = jump, name = ball.name, grid = ball.grid, system = ball.system,
      seconds = Traffic.SPOOL * Constants.TICK, why = why })
  end
end

-- Put what ore a ship has in its hold across into another's ore hold,
-- as much as there is room for: how many units went across.
local function handOver(state: State.State, from: number, to: number): number
  local moved = 0
  for _, item in Items.In(state, from, "cargo") do
    if Items.IsOre(item.type) then
      local size, used = Items.OreHold(state, to)
      local fits = math.min(item.quantity, math.floor((size - used + 1e-9) / Types.Info(item.type).volume))
      if fits > 0 then
        local type = item.type
        Items.Take(state, item, fits)
        Items.Add(state, type, fits, to, "orehold")
        moved += fits
      end
    end
  end
  return moved
end

-- A ship of the traffic that has done with what it was at makes for
-- the nearest station, as a ship coming in to dock does; and is taken
-- away if there is none.
local function goHome(state: State.State, id: number, events: { Event })
  local record, ball = state.traffic[id], state.balls[id]
  local station = if ball then nearestStation(state, ball) else nil
  if record and ball and station then
    ball.vitals.locks = {}
    record.kind, record.goal, record.born = "home", station.id, state.tick
    order(state, { kind = "Dock", actor = id, target = station.id }, events)
  else
    remove(state, id, "left", events)
  end
end

-- A fleet's jumpship jumps: itself, and every ship of its fleet within
-- its field that nothing holds (Jumping.Along says who a field takes).
-- They are gone to a station of their people's in another system, and
-- the system is without a fleet for a while. What is left makes for a
-- station here. (With nowhere of theirs within reach any more, nobody
-- jumps: they all make for a station here.)
local function evacuate(state: State.State, jump: number, system: number, events: { Event })
  local ball = state.balls[jump]
  local name, grid = ball.name, ball.grid
  local to, station = Traffic.Refuge(state, system, state.ships[jump].owner, Jumping.Range(state, jump))
  local going: { number } = {}
  if station then
    table.insert(going, jump)
    for _, id in Jumping.Along(state, jump) do
      local record = state.traffic[id]
      if record and FLEET_KINDS[record.kind] then
        table.insert(going, id)
      end
    end
  end
  local gone: { [number]: boolean } = {}
  for _, id in going do
    gone[id] = true
    table.insert(events, { kind = "Jumped", ship = id, from = system, to = to, gate = 0, arrival = (station :: System.Object).id,
      drive = true, along = if id ~= jump then jump else nil, radius = state.balls[id].radius })
    remove(state, id, "jumped", events)
  end
  local left = 0
  for _, id in table.clone(state.trafficIds) do
    local record = state.traffic[id]
    if record and FLEET_KINDS[record.kind] and record.system == system and not gone[id] and state.ships[id] then
      left += 1
      goHome(state, id, events)
    end
  end
  state.miningFleets[system] = state.tick + Traffic.FLEET_AWAY
  table.insert(events, { kind = "FleetJumped", ship = jump, name = name, grid = grid, system = system, to = to,
    station = if station then station.name else "", took = math.max(0, #going - 1), left = left, jumped = station ~= nil })
end

-- The police: two ships of the system's faction, out of warp a few
-- kilometres from the marked pilot. They come in what it takes: in
-- destroyers for anything small, in cruisers for a cruiser, and in
-- battleships for a battleship.
local function police(state: State.State, mine: State.Ball, rng: Rng.Rng, events: { Event }): number
  local faction = Factions.byId[Galaxy.Keeper(state.galaxy.systems[mine.system])]
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

-- Whether a faction is blockading a system now (or past that, at its
-- assault).
blockading = function(state: State.State, system: number, faction: string): boolean
  for _, operation in state.wars.operations do
    if operation.system == system and operation.by == faction and (operation.stage == "blockade" or operation.stage == "assault") then
      return true
    end
  end
  return false
end

-- Two ships of a blockading side at a gate, out of warp a few
-- kilometres off it, for the pilot there who is on the other side's
-- books: the first with a warp disruptor beside its guns. They come in
-- what the police would (Traffic.PICKETS ships).
Traffic.PICKETS = 2
function Traffic.Picket(state: State.State, mine: State.Ball, gate: System.Object, faction: string, rng: Rng.Rng, events: { Event }): number
  local its = Factions.byId[faction]
  local flown = Ships.byId[state.ships[mine.id].type].class
  local class = if flown == "battleship" or flown == "cruiser" then flown else "destroyer"
  local kind = if its then patrolKind(its, class) or patrolKind(its, "destroyer") or patrolKind(its, "frigate") else nil
  if its == nil or kind == nil then
    return 0
  end
  for index = 1, Traffic.PICKETS do
    local fitted = table.clone(kind)
    if index == 1 then
      -- (in place of the first of its mid slot's modules, where it has
      -- one, so that it has the room for it; else beside the rest)
      fitted.fit = table.clone(kind.fit)
      local at = nil
      for position, entry in fitted.fit do
        local module = Modules.byId[entry[1]]
        if at == nil and module and module.slot == "mid" then
          at = position
        end
      end
      if at then
        fitted.fit[at] = { "disruptor.warp" }
      else
        table.insert(fitted.fit, { "disruptor.warp" })
      end
    end
    local ship = Space.NewShip(state, fitted.hull, `{its.name} Picket`, its.id, 0)
    Pirates.Equip(state, ship, fitted)
    local x, y, z = near(rng, gate, 3000, 6000)
    local ball = Space.Launch(state, ship, mine.system, x, y, z)
    table.insert(events, { kind = "BallAdded", ball = ball.id })
    enlist(state, ship, "picket", gate.id, mine.system)
    state.traffic[ship.id].wait = 1
  end
  table.insert(events, { kind = "PicketArrived", count = Traffic.PICKETS, faction = its.id, gate = gate.id })
  return Traffic.PICKETS
end

-- What a colony ship is as a ship that fights: a weapon of its
-- hardpoint's size on every hardpoint it has, its people's guns and
-- launchers, and the largest of everything else.
local function colonyKind(faction: Factions.Faction, hull: Ships.ShipType, name: string): Pirates.Kind
  local fit: { { string } } = {}
  local guns: { number }, racks: { number } = hull.guns or {}, hull.racks or {}
  for size = #guns, 1, -1 do
    for _ = 1, guns[size] do
      table.insert(fit, { `{GUNS[faction.weapon] or "autocannon"}.{SIZES[size]}` })
    end
  end
  for size = #racks, 1, -1 do
    for _ = 1, racks[size] do
      table.insert(fit, { LAUNCHERS[size] })
    end
  end
  for _, module in FITTINGS[3] do
    table.insert(fit, { module })
  end
  return { id = "colony", hull = hull.id, name = name, range = Traffic.COLONY_OFF, bounty = 0, tags = 0, fit = fit }
end

-- The stargate of a system that leads to another, if it has one.
local function gateTo(state: State.State, system: number, to: number): System.Object?
  for _, object in Space.Describe(state, system).objects do
    if object.kind == "gate" and object.variety ~= "passage" and object.to == to then
      return object
    end
  end
  return nil
end

-- How far off the colony ship one of its support fleet keeps: each its
-- own distance, so that they ring it and do not bunch.
local function escortOff(id: number): number
  return Traffic.ESCORT_OFF + (id % 6) * 1500
end

-- Put a colony fleet into the system it is in: the colony ship, and
-- round it its support fleet. It has only now come, if the pilot was
-- here to see it come: then it is at the gate it came in by, and warps
-- across to the gate it will go out by. Otherwise it lies off that gate
-- already. (A people with one system has no gate to go by: its fleet
-- lies off the first gate or station there is.)
local function colonyFleet(state: State.State, system: number, fleet: Nomads.Fleet, rng: Rng.Rng, events: { Event })
  local faction = Factions.byId[fleet.faction]
  local hull = Ships.byId[fleet.hull]
  local _, from, to, came = Nomads.At(fleet, state.tick)
  local out = gateTo(state, system, to)
  if out == nil then
    for _, object in Space.Describe(state, system).objects do
      if out == nil and (object.kind == "gate" or object.kind == "station") then
        out = object
      end
    end
  end
  if faction == nil or hull == nil or out == nil then
    return
  end
  local way = gateTo(state, system, from)
  local coming = way ~= nil and state.tick - came <= 3
  -- (and it has a way to go across the system, unless the gate it came
  -- by is the one it goes back by)
  local across = coming and way ~= nil and way.id ~= out.id
  local at: System.Object = if coming and way then way else out
  local x, y, z = near(rng, at, Traffic.COLONY_OFF, Traffic.COLONY_OFF + 8000)
  local ship = Space.NewShip(state, hull.id, fleet.name, faction.id, 0)
  Pirates.Equip(state, ship, colonyKind(faction, hull, fleet.name))
  local ball = Space.Launch(state, ship, system, x, y, z)
  table.insert(events, { kind = "BallAdded", ball = ball.id })
  enlist(state, ship, "colony", out.id, system)
  state.traffic[ship.id].wait = fleet.index
  if across then
    order(state, { kind = "WarpTo", actor = ship.id, target = out.id, range = Traffic.COLONY_OFF }, events)
  else
    order(state, { kind = "Orbit", actor = ship.id, target = out.id, range = Traffic.COLONY_OFF }, events)
  end
  local count = 1
  for _, entry in Nomads.SUPPORT do
    local kind = patrolKind(faction, entry[1])
    for _ = 1, if kind then entry[2] else 0 do
      local escort = Space.NewShip(state, (kind :: Pirates.Kind).hull, `{faction.name} Escort`, faction.id, 0)
      Pirates.Equip(state, escort, kind :: Pirates.Kind)
      local angle = Rng.Float(rng, 0, 2 * math.pi)
      local off = hull.radius + escortOff(escort.id) + Ships.byId[escort.type].radius
      local beside = Space.Launch(state, escort, system, x + off * math.cos(angle), y + Rng.Float(rng, -1500, 1500),
        z + off * math.sin(angle))
      table.insert(events, { kind = "BallAdded", ball = beside.id })
      -- (an escort's 'goal' is the colony ship it keeps by)
      enlist(state, escort, "escort", ship.id, system)
      state.traffic[escort.id].wait = fleet.index
      if across then
        order(state, { kind = "WarpTo", actor = escort.id, target = out.id, range = Traffic.COLONY_OFF }, events)
      else
        order(state, { kind = "Orbit", actor = escort.id, target = ship.id, range = escortOff(escort.id) }, events)
      end
      count += 1
    end
  end
  if coming then
    table.insert(events, { kind = "ColonyFleetArrived", faction = faction.id, name = fleet.name, ships = count })
  end
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
  local keeper = Galaxy.Keeper(state.galaxy.systems[system])
  -- (and so is one who has served a side the keeper is at war with, its
  -- patrols and its police alike: the owner, 2026-11-16, "Enemy of your
  -- side"; Tactical/Sides)
  local marked = state.tick < state.player.marked or Standings.Hostile(state, keeper) or Sides.EnemyOf(state, keeper) ~= nil
  local haulers, patrols, miners, lawmen = 0, 0, 0, 0
  -- (a side's pickets at a gate, by the gate: Traffic.Picket)
  local picketed: { [number]: boolean } = {}
  -- (the colony fleets, and which of them have their colony ship here)
  local fleets = Nomads.Fleets(state.galaxy)
  local here: { [number]: boolean } = {}
  -- (and the gate each lies off, by its fleet: its escorts go out by it
  -- too, and after it)
  local outBy: { [number]: number } = {}
  for _, id in state.trafficIds do
    local record = state.traffic[id]
    if record.kind == "colony" and state.ships[id] then
      outBy[record.wait] = record.goal
    end
  end
  -- (the mining fleet here, if there is one: its jumpship, the ship
  -- that leads it, its barges in the order of their ids, and whether
  -- anything of it has been hit)
  local fleetJump, fleetBoss, fleetSize, fleetHit = 0, 0, 0, false
  local fleetBarges: { number } = {}
  for _, id in state.trafficIds do
    local record = state.traffic[id]
    local there = state.balls[id]
    if FLEET_KINDS[record.kind] and record.system == system and state.ships[id] and there then
      fleetSize += 1
      if record.kind == FLEET_JUMP then
        fleetJump = id
      elseif record.kind == FLEET_BOSS then
        fleetBoss = id
      else
        table.insert(fleetBarges, id)
      end
      fleetHit = fleetHit or there.vitals.shield < Traffic.FLEET_HIT * there.vitals.shieldMax
    end
  end
  for _, id in table.clone(state.trafficIds) do
    local record = state.traffic[id]
    local ship = state.ships[id]
    local ball = state.balls[id]
    if record == nil then
      -- (taken away already this tick: a fleet's ship that jumped with its jumpship)
      continue
    elseif ship == nil then
      -- (destroyed: whoever did it has seen to the rest. A colony ship
      -- is gone for a day before another takes its place.)
      if record.kind == "colony" then
        state.nomads[record.wait] = state.tick + Nomads.GONE
      elseif record.kind == FLEET_JUMP then
        -- (and a mining fleet that has lost its jumpship is not replaced for a day)
        state.miningFleets[record.system] = state.tick + Traffic.FLEET_LOST
      end
      -- (and what a hauler carried of the economy's is in its wreck, or
      -- nowhere: the system it was for goes without)
      if record.carries then
        table.insert(events, { kind = "HaulLost", system = record.carries.node, type = Commerce.goods[record.carries.class],
          amount = record.carries.amount })
      end
      state.traffic[id] = nil
      State.RemoveId(state.trafficIds, id)
    elseif record.system ~= system then
      remove(state, id, "left", events)
    elseif record.kind == "colony" or record.kind == "escort" then
      local fleet = fleets[record.wait]
      -- (the gate the fleet goes out by: none, for an escort whose
      -- colony ship is lost)
      local gate = outBy[record.wait] or 0
      if fleet == nil or (Nomads.At(fleet, state.tick)) ~= system then
        -- Its time here is up: through the gate, and on.
        remove(state, id, "jumped", events, if gate ~= 0 then gate else nil)
      else
        if record.kind == "colony" then
          here[record.wait] = true
        end
        local fighting = state.pilots[id] ~= nil
        local sees = marked and mine ~= nil and ball ~= nil and mine.grid == ball.grid
        if sees and not fighting then
          state.pilots[id] = { ship = id, range = if record.kind == "colony" then Traffic.COLONY_OFF else 2500, prey = 0,
            home = record.goal, alone = 0, bounty = 0, tags = 0 }
          State.InsertId(state.pilotIds, id)
        elseif fighting and not marked then
          state.pilots[id] = nil
          State.RemoveId(state.pilotIds, id)
          if ball then
            ball.vitals.locks = {}
            ball.vitals.running = {}
            ball.mode = "stop"
          end
        end
        -- On station, when it is not fighting and not on its way: the
        -- colony ship off its gate, and an escort by the colony ship (or
        -- off the gate, if that is lost).
        if state.pilots[id] == nil and ball and ball.warp == nil and ball.intent == nil and ball.mode ~= "orbit" then
          if record.kind == "escort" and gate ~= 0 and state.balls[record.goal] and state.balls[record.goal].warp == nil then
            order(state, { kind = "Orbit", actor = id, target = record.goal, range = escortOff(id) }, events)
          elseif record.kind == "colony" then
            order(state, { kind = "Orbit", actor = id, target = record.goal, range = Traffic.COLONY_OFF }, events)
          elseif gate == 0 then
            -- (its colony ship is gone: it stays where it is)
            order(state, { kind = "Stop", actor = id }, events)
          end
        end
      end
    elseif record.kind == FLEET_JUMP then
      -- A mining fleet's jumpship. Anything of the fleet hit, a pirate
      -- on its grid, or a pilot its people fight: it makes its drive
      -- ready, and when that is done it jumps, unless it is held (which
      -- takes a capital's disruptor). Until then it keeps by its barges.
      if ball and ball.warp == nil then
        local threat = fleetHit or pirateNear(state, ball) or (marked and mine ~= nil and mine.grid == ball.grid and mine.grid ~= 0)
        if record.wait == 0 and threat then
          alarm(state, id, "attacked", events)
        elseif record.wait ~= 0 and state.tick >= record.wait and not ball.vitals.scrambled then
          evacuate(state, id, system, events)
        elseif record.wait == 0 and ball.intent == nil then
          local by = fleetBarges[1] or fleetBoss
          if by ~= 0 and not (ball.mode == "orbit" and ball.target == by) then
            order(state, { kind = "Orbit", actor = id, target = by, range = 2500 }, events)
          end
        end
      end
    elseif record.kind == FLEET_BOSS or record.kind == FLEET_BARGE then
      local leader = state.traffic[fleetJump]
      if fleetJump == 0 or leader == nil then
        -- (its jumpship is gone, by its drive or for good: in to dock)
        goHome(state, id, events)
      elseif leader.wait ~= 0 then
        -- (the alarm: it leaves what it is at and makes for the
        -- jumpship, to be inside its field when the drive is ready)
        if ball and ball.warp == nil and not (ball.mode == "approach" and ball.target == fleetJump) then
          order(state, { kind = "Approach", actor = id, target = fleetJump, range = 1000 }, events)
        end
      elseif ball and ball.warp == nil and ball.intent == nil then
        if record.kind == FLEET_BOSS then
          -- (the ship that leads them keeps by its barges)
          local by = fleetBarges[1] or 0
          if by ~= 0 and not (ball.mode == "orbit" and ball.target == by) then
            order(state, { kind = "Orbit", actor = id, target = by, range = 1500 }, events)
          end
        else
          -- A barge cuts rock (Tactical/Digger). With its hold full it
          -- empties it into the ore hold of the ship that leads the
          -- fleet; and when that will take no more (or is lost), or the
          -- belt is cut out, the fleet has done and goes home.
          local post = Space.Object(state, record.goal)
          if post == nil or not Digger.Work(state, ball, post, events) then
            local to = state.balls[fleetBoss]
            if to == nil or to.grid ~= ball.grid or handOver(state, id, fleetBoss) == 0 then
              alarm(state, fleetJump, "full", events)
            end
          end
        end
      end
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
    elseif record.kind == "picket" then
      -- A blockade's picket at a gate: it fights one on the other side's
      -- books who is at its gate, and goes when they have gone from the
      -- system, or are nobody's enemy, or the blockade is over.
      local still = mine ~= nil and mine.system == record.system and record.wait ~= 0
        and Sides.EnemyOf(state, state.ships[id].owner) ~= nil and blockading(state, record.system, state.ships[id].owner)
      if not still then
        remove(state, id, "left", events)
      else
        picketed[record.goal] = true
        local sees = mine ~= nil and ball ~= nil and mine.grid == ball.grid and mine.grid ~= 0
        if sees and state.pilots[id] == nil then
          state.pilots[id] = { ship = id, range = 2000, prey = 0, home = record.goal, alone = 0, bounty = 0, tags = 0 }
          State.InsertId(state.pilotIds, id)
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
      elseif ball and ball.transit then
        -- Going through its gate: once through, it is gone.
        if ball.transit.stage ~= "in" and record.kind == "out" then
          remove(state, id, "jumped", events)
        end
      elseif ball and ball.warp == nil and ball.intent == nil then
        if record.wait == -1 then
          -- Out of the gate it came in by: off to dock.
          record.wait = 0
          order(state, { kind = "Dock", actor = id, target = record.goal }, events)
        elseif ball.grid == record.goal and record.kind == "out" then
          -- At its gate: in close, and through.
          local gate = Space.Object(state, record.goal)
          if gate and gate.kind == "gate" and gate.variety ~= "passage" then
            if Space.Gap(ball :: any, gate :: any) <= Constants.JUMP_RANGE then
              Space.EnterGate(state, ball, gate, events)
            elseif ball.mode ~= "approach" then
              order(state, { kind = "Approach", actor = id, target = record.goal }, events)
            end
          else
            record.wait += 1
            if record.wait > 5 then
              remove(state, id, "jumped", events, record.goal)
            end
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

  -- A colony fleet that is in this system and is not here yet. (With
  -- the pilot in space: nobody watches from a hangar. But a pilot docked
  -- in a colony ship is aboard one of them, and it is there with its
  -- fleet round it: it is what they see from its hangar, and what they
  -- come out beside.)
  if mine or Nomads.FleetOf(state.galaxy, me.docked) then
    for _, fleet in fleets do
      if not here[fleet.index] and not Nomads.Gone(state, fleet) and (Nomads.At(fleet, state.tick)) == system then
        colonyFleet(state, system, fleet, Rng.For(state.historySeed, state.tick, system, fleet.index, 61), events)
      end
    end
  end

  if state.tick < state.trafficDue then
    return
  end
  state.trafficDue = state.tick + Traffic.INTERVAL
  local band = Galaxy.Band(Galaxy.Order(state.galaxy.systems[system]))
  local rng = Rng.For(state.historySeed, state.tick, system, 57)
  if haulers < Traffic.HAULERS[band] and (band ~= "lawless" or Rng.Chance(rng, Traffic.LAWLESS)) then
    hauler(state, system, rng, events)
  end
  if patrols < Traffic.PATROLS[band] then
    patrol(state, system, rng, events)
  end
  if miners < Traffic.MINERS[band] and Galaxy.Keeper(state.galaxy.systems[system]) ~= "" then
    miner(state, system, rng, events)
  end
  -- A mining fleet, in the space of a people who fly them. (By a roll
  -- of its own, so that nothing else about who comes follows from it.)
  if fleetSize == 0 and Traffic.FleetDue(state, system) then
    miningFleet(state, system, Rng.For(state.historySeed, state.tick, system, 179), events)
  end
  -- The police, for a marked pilot in secure space: wherever they are.
  if marked and mine and mine.grid ~= 0 and band == "secure" and lawmen < Traffic.POLICE then
    police(state, mine, rng, events)
  end
  -- A blockade's pickets, for one on the other side's books who comes to
  -- a gate of the system it holds (the owner, 2026-11-16, "Blockades
  -- stop you"): two of the blockading side's warships, one with a warp
  -- disruptor, out of warp at the gate.
  if mine and mine.grid ~= 0 and not picketed[mine.grid] then
    local gate = Space.Object(state, mine.grid)
    if gate and gate.kind == "gate" then
      for _, operation in state.wars.operations do
        if operation.system == mine.system and (operation.stage == "blockade" or operation.stage == "assault")
          and Sides.EnemyOf(state, operation.by) then
          Traffic.Picket(state, mine, gate, operation.by, rng, events)
          break
        end
      end
    end
  end
end

return Traffic
