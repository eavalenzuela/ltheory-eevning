--!strict
-- The showcase: scenes of the game played behind the opening menu (the
-- owner, 2026-11-27: "background screens ... of various places and
-- activities ... Basically, showcasing the game"; live, in the game's
-- own render, in Cel V2).
--
-- Each scene is a game of its own, made for it (a small galaxy, a
-- fifth of a second's work), with what the scene is about put into
-- it: a mining fleet at its belt, a freighter warping out, a fleet
-- coming through an alien gate. The game then plays as any does, its
-- ships doing what they do, and the camera goes slowly round what the
-- scene shows (Game/View/Scene's director). The pilot of that game is
-- the camera: sat in a capsule nobody sees, which pirates leave alone
-- where any law is kept (Tactical/Pirates). The view goes to black
-- between one scene and the next (Scene's curtain).
--
-- Nothing of it touches the person's own game, their character or
-- their settings: the scene is drawn from this game while the opening
-- menu is up, and from theirs again when it closes (Scene.Sync starts
-- over for another game's epoch).

local Clock = require("@lt/Game/Clock")
local Combat = require("@lt/Core/Tactical/Combat")
local Constants = require("@lt/Core/Data/Constants")
local Core = require("@lt/Core/Api")
local Drones = require("@lt/Core/Tactical/Drones")
local Items = require("@lt/Core/Assets/Items")
local Mining = require("@lt/Core/Tactical/Mining")
local Starbases = require("@lt/Core/Assets/Starbases")
local Structures = require("@lt/Core/Data/Structures")
local Wormholes = require("@lt/Core/Tactical/Wormholes")
local Factions = require("@lt/Core/Data/Factions")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Nomads = require("@lt/Core/Tactical/Nomads")
local Wars = require("@lt/Core/Strategic/Wars")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Rng = require("@lt/Core/Kernel/Rng")
local Session = require("@lt/Game/Session")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")
local Traffic = require("@lt/Core/Tactical/Traffic")

local Showcase = {}

type Event = { [string]: any }

-- What the camera does (Game/View/Scene's Director: the same shape).
export type Director = { target: number, zoom: number, pitch: number, spin: number, yaw: number, aside: number, fresh: boolean }

-- A scene put into its game: what the camera is on, and what is done
-- each frame while it plays (seconds since it began), if anything: true
-- from it when what the scene is about is over, and the scene ends a
-- moment after.
type Staged = { director: Director, during: ((state: State.State, age: number, events: { Event }) -> boolean?)? }

-- A scene: its name, how long it plays (seconds), and how it is put
-- into a new game (nil if that game has nowhere for it).
type Scene = { name: string, length: number, stage: (state: State.State, rng: Rng.Rng, events: { Event }) -> Staged? }

export type Show = {
  session: Session.Session,
  -- (the scene playing, by its place in the list, how long it has, and
  -- how long it has played)
  index: number,
  length: number,
  age: number,
  staged: Staged?,
  director: Director?,
  curtain: number,
  -- (how many games it has made: each is a new seed, and a new epoch)
  made: number,
}

-- The galaxy a scene's game is made in: big enough to have every
-- people's space and the lawless, small enough to make in a moment.
local SYSTEMS = 400
-- Seconds of black at either end of a scene; and the seconds a scene
-- goes on once what it was about is over.
local FADE = 1.2
local OVER = 3
-- Each game is a different galaxy; and an epoch for the scene that no
-- game of the person's will have (Session's start at 1 and go up by one).
local EPOCHS = 1000000
-- Ticks a scene's game is run before the scene is put in it; and after,
-- before it is shown.
local WARM = 6
local PREROLL = 3

-- The pilot, put at a place as the camera: in a capsule, which nobody
-- draws and pirates leave be where there is law (Tactical/Pirates), in
-- space at x, y, z of a system.
local function cameraAt(state: State.State, system: number, x: number, y: number, z: number, events: { Event })
  local ship = state.ships[state.player.ship]
  if ship.type ~= "capsule" then
    ship = Space.NewShip(state, "capsule", "Capsule", "player", 0)
    state.player.ship = ship.id
  end
  local ball = state.balls[ship.id]
  if ball then
    Space.RemoveBall(state, ball)
  end
  ship.docked, ship.moored = 0, nil
  local out = Space.Launch(state, ship, system, x, y, z)
  table.insert(events, { kind = "BallAdded", ball = out.id })
end

-- The systems of the map in an order of the scene's own, to look
-- through for one that will do.
local function shuffled(state: State.State, rng: Rng.Rng): { number }
  local ids: { number } = {}
  for id = 1, Galaxy.Charted(state.galaxy) do
    table.insert(ids, id)
  end
  for index = #ids, 2, -1 do
    local other = Rng.Int(rng, index) + 1
    ids[index], ids[other] = ids[other], ids[index]
  end
  return ids
end

local function objectsOf(state: State.State, system: number, kind: string): { System.Object }
  local found: { System.Object } = {}
  for _, object in Space.Describe(state, system).objects do
    if object.kind == kind and (kind ~= "gate" or object.variety ~= "passage")
      and (kind ~= "station" or state.starbases[object.id] == nil) then
      table.insert(found, object)
    end
  end
  return found
end

-- (and to the left of the window, the menu standing at its right:
-- 'aside' a share of the distance)
local ASIDE = 0.4
local function director(target: number, zoom: number, pitch: number, spin: number, yaw: number, aside: number?): Director
  return { target = target, zoom = zoom, pitch = pitch, spin = spin, yaw = yaw, aside = aside or ASIDE, fresh = true }
end

-- A ship of a faction's, of a class, fitted as its patrols are, put in
-- space at a place: nil if the faction builds no such hull.
local function warship(state: State.State, faction: string, class: string, system: number, x: number, y: number, z: number,
  events: { Event }): State.Ball?
  local kind = Traffic.Warship(faction, class)
  if kind == nil then
    return nil
  end
  local ship = Space.NewShip(state, kind.hull, kind.name, faction, 0)
  Pirates.Equip(state, ship, kind)
  local ball = Space.Launch(state, ship, system, x, y, z)
  table.insert(events, { kind = "BallAdded", ball = ball.id })
  return ball
end

-- Ships come out of a gate or a wormhole one after another (each 'gap'
-- seconds from 'from' on), as a fleet arrives: a function for a scene's
-- 'during', which makes each ship as its turn comes ('make', nil if it
-- could not be) and brings it out of 'by'. What it has brought out is
-- in 'out'.
local function arrivals(count: number, from: number, gap: number, by: System.Object,
  make: (state: State.State, index: number, events: { Event }) -> State.Ball?, out: { number }):
  (state: State.State, age: number, events: { Event }) -> ()
  local next = 1
  return function(state: State.State, age: number, events: { Event }): ()
    while next <= count and age >= from + (next - 1) * gap do
      local ball = make(state, next, events)
      next += 1
      if ball then
        Space.ComeThrough(state, ball, by, events)
        table.insert(out, ball.id)
      end
    end
  end
end

-- A command a ship flown by the game gives itself, done if it may be
-- (as Tactical/Digger's are).
local function give(state: State.State, command: State.Command, events: { Event })
  if command.kind == "LockTarget" or command.kind == "ActivateModule" then
    if Combat.Validate(state, command) then
      Combat.Apply(state, command, events)
    end
  elseif Space.Validate(state, command) then
    Space.Apply(state, command, events)
  end
end

-- A pirate force put at a station, the camera behind the one of them
-- that it shows: kinds of Tactical/Pirates, 'out' metres beyond the
-- station's field, in a ring 'spread' across. The one shown is the
-- 'lead'th. The station is somewhere a station's people keep it, and
-- not the lawless (where the pirates would go for the camera). Its
-- batteries, outside its field, fire on them (Tactical/Batteries).
local function raid(state: State.State, rng: Rng.Rng, events: { Event }, kinds: { string }, out: number, spread: number,
  lead: number, zoom: number, cloaked: boolean?): (Staged?, { number })
  for _, system in shuffled(state, rng) do
    local node = state.galaxy.systems[system]
    local stations = objectsOf(state, system, "station")
    if Galaxy.Keeper(node) ~= "" and Galaxy.Band(Galaxy.Order(node)) ~= "lawless" and #stations > 0 then
      local station = stations[1]
      local angle = Rng.Float(rng, 0, 2 * math.pi)
      local far = station.radius + out
      local cx, cz = station.x + far * math.cos(angle), station.z + far * math.sin(angle)
      local balls: { number } = {}
      for index, kind in kinds do
        local round = (index - 1) * 2 * math.pi / #kinds
        local ball = Pirates.Spawn(state, Pirates.kindById[kind], system, cx + spread * math.cos(round),
          station.y + Rng.Float(rng, -800, 800), cz + spread * math.sin(round), station.id)
        -- (a hull with a cloak of its own comes under it, if it is to: the Drowned's)
        if cloaked and Combat.HasCloak(state, ball.id) then
          ball.vitals.cloaked = true
        end
        table.insert(events, { kind = "BallAdded", ball = ball.id })
        table.insert(balls, ball.id)
      end
      cameraAt(state, system, station.x + (far - 6000) * math.cos(angle), station.y + 1500,
        station.z + (far - 6000) * math.sin(angle), events)
      -- (behind the one it shows, the station beyond it)
      return { director = director(balls[lead], zoom, 1.35, 0.008, angle + 0.25) }, balls
    end
  end
  return nil, {}
end

-- A people's ship of a hull, fitted as their ships are (Traffic.Fitted:
-- a carrier's bay full), in space at a place.
local function fitted(state: State.State, hull: string, owner: string, system: number, x: number, y: number, z: number,
  events: { Event }): State.Ball
  local faction = Factions.byId[owner]
  local name = `{if faction then faction.name else ""} {Ships.byId[hull].name}`
  local ship = Space.NewShip(state, hull, name, owner, 0)
  Pirates.Equip(state, ship, Traffic.Fitted(hull, if faction then faction.weapon else nil, name))
  local ball = Space.Launch(state, ship, system, x, y, z)
  table.insert(events, { kind = "BallAdded", ball = ball.id })
  return ball
end

-- A ship flown by the game for a side: it goes for the nearest of
-- another side's (Tactical/Pirates), as a front's ships do; a carrier
-- sends its fighters at it (Tactical/Drones).
local function fights(state: State.State, ball: State.Ball, side: string, range: number)
  state.pilots[ball.id] = { ship = ball.id, range = range, prey = 0, home = ball.grid, alone = 0, bounty = 0, tags = 0, side = side }
  State.InsertId(state.pilotIds, ball.id)
end

-- Open space a little way off a planet of a system people keep (not the
-- lawless, where the pirates would go for the camera): its x, y and z
-- (numbers: a vector is too coarse out here); nil if it has no planet.
local function offPlanet(state: State.State, system: number, out: number): { number }?
  for _, planet in objectsOf(state, system, "planet") do
    local far = math.sqrt(planet.x * planet.x + planet.z * planet.z)
    local ax, az = if far > 0 then planet.x / far else 1, if far > 0 then planet.z / far else 0
    -- (on the star's side of it, so that it is lit behind what is there)
    return { planet.x - ax * (planet.radius + out), planet.y, planet.z - az * (planet.radius + out) }
  end
  return nil
end

local function kept(state: State.State, system: number): boolean
  local node = state.galaxy.systems[system]
  return Galaxy.Keeper(node) ~= "" and Galaxy.Band(Galaxy.Order(node)) ~= "lawless"
end

-- Where each of a colony ship's escorts keeps (Nomads.SUPPORT): metres
-- ahead of its middle, to its right and above, for a colony ship 5 km
-- about (Les Larmes de Nova's; another's is scaled to it). The heavy
-- ships on its flanks, the destroyers out ahead, the frigates riding
-- above, the haulers astern: as a battle group keeps about a carrier.
local FORMATION: { [string]: { { number } } } = {
  carrier = { { -400, 3600, 200 } },
  battleship = { { 1600, -3000, -150 }, { -2200, -3000, 250 } },
  battlecruiser = { { 2700, 3100, 0 }, { -3300, 2900, -250 } },
  destroyer = { { 6300, -800, 200 }, { 6800, 0, 450 }, { 6300, 800, 200 } },
  frigate = { { 1200, -1400, 1700 }, { -1200, -1400, 1700 }, { 1200, 1400, 1700 }, { -1200, 1400, 1700 } },
  industrial = { { -6400, -900, 0 }, { -6400, 900, 0 } },
}

local SCENES: { Scene } = {
  -- A mining fleet at work at a belt: its jumpship, the capital
  -- industrial leading it, and its barges cutting rock.
  {
    name = "mining fleet",
    length = 26,
    stage = function(state, rng, events)
      for _, system in shuffled(state, rng) do
        if Galaxy.Keeper(state.galaxy.systems[system]) ~= "" and Traffic.Stage.MiningFleet(state, system, rng, events) then
          local boss: State.Ball? = nil
          for _, id in state.trafficIds do
            if state.traffic[id].kind == "fleet.boss" and state.traffic[id].system == system then
              boss = state.balls[id]
            end
          end
          if boss then
            -- (looking from the side away from the belt's rocks, which
            -- the camera would otherwise go round into)
            local rock: System.Object? = nil
            for _, object in Space.Describe(state, system).objects do
              if object.kind == "asteroid" and (rock == nil
                or Space.Distance(object :: any, boss :: any) < Space.Distance(rock :: any, boss :: any)) then
                rock = object
              end
            end
            local yaw = if rock then math.atan2(boss.z - rock.z, boss.x - rock.x) else Rng.Float(rng, 0, 2 * math.pi)
            cameraAt(state, system, boss.x + 6000 * math.cos(yaw), boss.y + 2000, boss.z + 6000 * math.sin(yaw), events)
            return { director = director(boss.id, 3.4, 1.15, 0.006, yaw - 0.35) }
          end
        end
      end
      return nil
    end,
  },
  -- A freighter pulling away from a station, lining up on a gate, and
  -- going into warp.
  {
    name = "freighter warping",
    length = 22,
    stage = function(state, rng, events)
      for _, system in shuffled(state, rng) do
        local node = state.galaxy.systems[system]
        local keeper = Galaxy.Keeper(node)
        local hull = if keeper ~= "" then Traffic.Stage.HullOf(keeper, "freighter") else nil
        local stations, gates = objectsOf(state, system, "station"), objectsOf(state, system, "gate")
        if hull and #stations > 0 and #gates > 0 then
          local station, gate = stations[1], gates[Rng.Int(rng, #gates) + 1]
          local ship = Space.NewShip(state, hull, Ships.byId[hull].name, keeper, 0)
          -- (a little way off the station, on the line to the gate, already under way)
          local dx, dy, dz = gate.x - station.x, gate.y - station.y, gate.z - station.z
          local far = math.sqrt(dx * dx + dy * dy + dz * dz)
          dx, dy, dz = dx / far, dy / far, dz / far
          local out = station.radius + 9000
          local ball = Space.Launch(state, ship, system, station.x + dx * out, station.y + dy * out, station.z + dz * out)
          ball.vx, ball.vy, ball.vz = dx * ball.maxVelocity * 0.45, dy * ball.maxVelocity * 0.45, dz * ball.maxVelocity * 0.45
          table.insert(events, { kind = "BallAdded", ball = ball.id })
          Traffic.Stage.Enlist(state, ship, "out", gate.id, system)
          Traffic.Stage.Order(state, { kind = "WarpTo", actor = ship.id, target = gate.id, range = 0 }, events)
          cameraAt(state, system, ball.x - dx * 5000, ball.y + 3000, ball.z - dz * 5000, events)
          -- (from behind and above it, looking along the way it goes)
          local yaw = math.atan2(-dz, -dx) + 0.6
          local id = ball.id
          return {
            director = director(id, 3.4, 1.25, 0.012, yaw),
            during = function(state: State.State, age: number, events: { Event }): boolean?
              local going = state.balls[id]
              return going == nil or (going.warp ~= nil and going.warp.stage == "warp")
            end,
          }
        end
      end
      return nil
    end,
  },
  -- An alien people's gate, the ring in its gimbals, and a fleet of
  -- theirs coming out of it one after another.
  {
    name = "alien gate",
    length = 26,
    stage = function(state, rng, events)
      for _, system in shuffled(state, rng) do
        local node = state.galaxy.systems[system]
        local faction = Factions.byId[node.owner]
        if faction and faction.kind == "alien" then
          for _, gate in objectsOf(state, system, "gate") do
            if Galaxy.GateDesign(state.galaxy, system, gate.to) == "gyre" then
              cameraAt(state, system, gate.x + gate.radius * 6, gate.y + gate.radius, gate.z, events)
              local stations = objectsOf(state, system, "station")
              local classes = { "battleship", "cruiser", "cruiser", "destroyer", "frigate", "frigate", "cruiser", "frigate" }
              local next = 1
              return {
                director = director(gate.id, 2.3, 1.38, 0.018, Rng.Float(rng, 0, 2 * math.pi)),
                -- (one through every second and a half, from the third second on)
                during = function(state: State.State, age: number, events: { Event }): boolean?
                  if next <= #classes and age >= 3 + (next - 1) * 1.5 then
                    local ball = warship(state, faction.id, classes[next], system, gate.x, gate.y, gate.z, events)
                      or warship(state, faction.id, "frigate", system, gate.x, gate.y, gate.z, events)
                    next += 1
                    if ball then
                      Space.ComeThrough(state, ball, gate, events)
                      -- (bound for the station, if there is one: they go on in, as traffic does)
                      if #stations > 0 then
                        Traffic.Stage.Enlist(state, state.ships[ball.id], "in", stations[1].id, system)
                        state.traffic[ball.id].wait = -1
                      end
                    end
                  end
                  return nil
                end,
              }
            end
          end
        end
      end
      return nil
    end,
  },
  -- A pirate fleet coming at a station: its batteries, standing off it
  -- outside its field, fire back (Tactical/Batteries), and the pirates
  -- go for them and for whoever is about. A Reaver snipes from far.
  {
    name = "station raid",
    length = 30,
    stage = function(state, rng, events)
      return (raid(state, rng, events, { "ravager", "brigand", "marauder", "marauder", "jackal", "raider", "raider", "reaver" },
        22000, 2500, 1, 3.0))
    end,
  },
  -- A colony ship of the nomads (the Kethri's: their only stations),
  -- lying off a gate, its support fleet close about it in formation as
  -- a battle group sails about a carrier, and the camera in close to
  -- show how big it is (the owner, 2026-11-27). It comes into the system
  -- of itself when the pilot is there (Tactical/Traffic): the camera is
  -- put by the gate, and goes onto it when it is there.
  {
    name = "colony fleet",
    length = 30,
    stage = function(state, rng, events)
      local fleets = Nomads.Fleets(state.galaxy)
      if #fleets == 0 then
        return nil
      end
      local fleet = fleets[Rng.Int(rng, #fleets) + 1]
      local system, _, to = Nomads.At(fleet, state.tick)
      local by: System.Object? = nil
      for _, gate in objectsOf(state, system, "gate") do
        if gate.to == to or by == nil then
          by = gate
        end
      end
      if by == nil then
        return nil
      end
      local gate = by :: System.Object
      cameraAt(state, system, gate.x + Traffic.COLONY_OFF * 0.6, gate.y + 4000, gate.z + Traffic.COLONY_OFF * 0.6, events)
      local shot = director(gate.id, 2.3, 1.4, 0.01, Rng.Float(rng, 0, 2 * math.pi))
      local colony = 0
      local formed: { { id: number, at: { number } } } = {}
      return {
        director = shot,
        during = function(state: State.State, age: number, events: { Event }): boolean?
          if colony == 0 then
            for _, id in state.trafficIds do
              if state.traffic[id].kind == "colony" and state.balls[id] then
                colony = id
              end
            end
            if colony == 0 then
              return nil
            end
            -- (its escorts, each to a place in the formation by its class)
            local taken: { [string]: number } = {}
            for _, id in state.trafficIds do
              local record = state.traffic[id]
              if record.kind == "escort" and record.goal == colony and state.balls[id] then
                local class = Ships.byId[state.ships[id].type].class
                local places = FORMATION[class]
                local index = (taken[class] or 0) + 1
                if places and places[index] then
                  taken[class] = index
                  table.insert(formed, { id = id, at = places[index] })
                end
              end
            end
          end
          local ship = state.balls[colony]
          if ship == nil then
            return nil
          end
          -- (the way it goes, and square to that: the formation's axes)
          local speed = math.sqrt(ship.vx * ship.vx + ship.vy * ship.vy + ship.vz * ship.vz)
          local fx, fy, fz = 1, 0, 0
          if speed > 0.5 then
            fx, fy, fz = ship.vx / speed, ship.vy / speed, ship.vz / speed
          end
          local rx, rz = -fz, fx
          local across = math.sqrt(rx * rx + rz * rz)
          rx, rz = if across > 1e-6 then rx / across else 0, if across > 1e-6 then rz / across else 1
          local scale = Ships.byId[state.ships[colony].type].radius / 5000
          for _, slot in formed do
            local escort = state.balls[slot.id]
            if escort and escort.warp == nil and escort.transit == nil then
              local ahead, right, up = slot.at[1] * scale, slot.at[2] * scale, slot.at[3] * scale
              escort.x = ship.x + fx * ahead + rx * right
              escort.y = ship.y + fy * ahead + up
              escort.z = ship.z + fz * ahead + rz * right
              escort.vx, escort.vy, escort.vz = ship.vx, ship.vy, ship.vz
              escort.tvx, escort.tvy, escort.tvz = ship.tvx, ship.tvy, ship.tvz
              -- (on station, to the traffic: it leaves an escort that is
              -- going round its colony ship to it)
              escort.mode, escort.target, escort.range = "orbit", colony, 1
            end
          end
          -- (and the camera in close on it, low, from its forward quarter, once)
          if shot.target ~= colony then
            shot.target, shot.zoom, shot.pitch, shot.spin, shot.fresh = colony, 1.35, 1.25, 0.008, true
            shot.yaw = math.atan2(fz, fx) + 1.0
          end
          return nil
        end,
      }
    end,
  },
  -- Two peoples' fleets fighting over a system on the open ground
  -- between them: a siege, past its muster, with both forces in it
  -- (Tactical/Fronts puts them there when the pilot is at the lines).
  {
    name = "fleet battle",
    length = 30,
    stage = function(state, rng, events)
      local holders = Galaxy.Holders(state.galaxy)
      local human: { string } = {}
      for _, id in holders do
        if Factions.byId[id] and Factions.byId[id].kind == "human" then
          table.insert(human, id)
        end
      end
      if #human < 2 then
        return nil
      end
      local first = Rng.Int(rng, #human) + 1
      local by, against = human[first], human[first % #human + 1]
      for _, system in shuffled(state, rng) do
        local node = state.galaxy.systems[system]
        if node.owner == "" and state.wars.claims[system] == nil and #objectsOf(state, system, "gate") > 0 then
          node.owner = against
          state.wars.claims[system] = against
          state.wars.version += 1
          if not Wars.AtWar(state.wars, by, against) then
            table.insert(state.wars.feuds, { a = by, b = against, since = state.tick, score = 0 })
          end
          table.insert(state.wars.operations, { id = state.tick * 16 + 15, by = by, system = system, kind = "siege",
            began = state.tick - Wars.STAGE - 1, force = 220, sent = 220, against = against, defence = 200, defended = 200,
            stage = "blockade", relieved = true })
          local gate = objectsOf(state, system, "gate")[1]
          cameraAt(state, system, gate.x + 30000, gate.y, gate.z, events)
          local shot = director(0, 3.2, 1.3, 0.01, Rng.Float(rng, 0, 2 * math.pi))
          local moved = false
          return {
            director = shot,
            -- (to the lines once they are staked, and onto the biggest
            -- of the besiegers once they are there)
            during = function(state: State.State, age: number, events: { Event }): boolean?
              local front = state.fronts[state.frontIds[1] or 0]
              local lines = if front then Space.Object(state, front.site) else nil
              if lines and not moved then
                moved = true
                cameraAt(state, system, lines.x - 14000, lines.y + 4000, lines.z, events)
              end
              if front and shot.target == 0 then
                local best, most = 0, 0
                for id, record in front.ships do
                  local ball = state.balls[id]
                  if record.attacking and ball and record.worth > most then
                    best, most = id, record.worth
                  end
                end
                if best ~= 0 then
                  local ball = state.balls[best]
                  shot.target, shot.fresh = best, true
                  shot.yaw = math.atan2(ball.z - (lines :: any).z, ball.x - (lines :: any).x)
                end
              end
              return nil
            end,
          }
        end
      end
      return nil
    end,
  },
  -- The pirates' capitals at a station: a dreadnought, a siege
  -- dreadnought and a carrier with its fighters out, and escorts.
  {
    name = "capital raid",
    length = 32,
    stage = function(state, rng, events)
      return (raid(state, rng, events, { "tyrant", "warren", "despoiler", "brigand", "marauder", "marauder", "jackal" },
        38000, 6000, 1, 2.2))
    end,
  },
  -- The Drowned come at a station under their cloaks, and are seen only
  -- as each of them comes out of it to fire. The camera is on the
  -- station, and goes onto the first of them it sees.
  {
    name = "drowned",
    length = 32,
    stage = function(state, rng, events)
      local staged, balls = raid(state, rng, events, { "drowned.keeper", "drowned.casket", "drowned.casket", "drowned.gravestone",
        "drowned.cairn", "drowned.cairn" }, 16000, 3000, 1, 2.6, true)
      if staged == nil then
        return nil
      end
      local shot = staged.director
      local seen = false
      -- (on the station they are coming for, from beyond them, till one shows)
      local station = (state.balls[balls[1]] :: State.Ball).grid
      shot.target, shot.zoom, shot.pitch = station, 1.6, 1.3
      staged.during = function(state: State.State, age: number, events: { Event }): boolean?
        if not seen then
          for _, id in balls do
            if state.balls[id] and not Combat.Cloaked(state, id) then
              seen = true
              shot.target, shot.zoom, shot.pitch, shot.fresh = id, 3.2, 1.35, true
              break
            end
          end
        end
        return nil
      end
      return staged
    end,
  },
  -- A wormhole open in a system, and the Drowned coming out of it from
  -- the deep, one after another.
  {
    name = "wormhole",
    length = 28,
    stage = function(state, rng, events)
      for _, system in shuffled(state, rng) do
        local node = state.galaxy.systems[system]
        if Galaxy.Keeper(node) ~= "" and Galaxy.Band(Galaxy.Order(node)) ~= "lawless" then
          -- (to the deepest of uncharted space there is)
          local to, deepest = 0, 0
          for id = Galaxy.Charted(state.galaxy) + 1, #state.galaxy.systems do
            local depth = state.galaxy.systems[id].depth or 1
            if depth > deepest then
              to, deepest = id, depth
            end
          end
          local hole = if to ~= 0 then Wormholes.Open(state, system, to, rng, events, 4, true) else nil
          local place = if hole then Space.Object(state, hole.a) else nil
          if place then
            local mouth = place :: System.Object
            local x = mouth.x + (mouth.radius + 9000)
            cameraAt(state, system, x, mouth.y + 3000, mouth.z, events)
            local kinds = { "drowned.keeper", "drowned.casket", "drowned.gravestone", "drowned.casket", "drowned.cairn", "drowned.cairn" }
            local out: { number } = {}
            local bring = arrivals(#kinds, 3, 1.6, mouth, function(state: State.State, index: number, events: { Event }): State.Ball?
              local ball = Pirates.Spawn(state, Pirates.kindById[kinds[index]], system, mouth.x, mouth.y, mouth.z, mouth.id)
              table.insert(events, { kind = "BallAdded", ball = ball.id })
              return ball
            end, out)
            local shot = director(mouth.id, 2.6, 1.4, 0.015, Rng.Float(rng, 0, 2 * math.pi))
            return {
              director = shot,
              -- (on the mouth while they come, and then on the first of
              -- them, as it makes off, the rest coming out behind it)
              during = function(state: State.State, age: number, events: { Event }): boolean?
                bring(state, age, events)
                local first = out[1]
                if age >= 7 and shot.target == mouth.id and first and state.balls[first] and state.balls[first].transit == nil then
                  local ball = state.balls[first]
                  shot.target, shot.zoom, shot.fresh = first, 3.4, true
                  shot.yaw = math.atan2(ball.z - mouth.z, ball.x - mouth.x)
                end
                return nil
              end,
            }
          end
        end
      end
      return nil
    end,
  },
  -- Barges cutting ice at an ice field, their harvesters on the chunks.
  {
    name = "ice harvest",
    length = 26,
    stage = function(state, rng, events)
      for _, system in shuffled(state, rng) do
        local field: System.Object? = nil
        for _, belt in objectsOf(state, system, "belt") do
          if belt.variety == "ice" then
            field = belt
          end
        end
        local node = state.galaxy.systems[system]
        local yard = if Galaxy.Keeper(node) ~= "" then Galaxy.Keeper(node) else node.nearest
        local hull = Traffic.Stage.HullOf(yard, "barge")
        if field and hull then
          local chunks: { System.Object } = {}
          for _, object in Space.Describe(state, system).objects do
            if Mining.Ice(object) and object.site == (field :: System.Object).id then
              table.insert(chunks, object)
            end
          end
          if #chunks > 0 then
            local barges: { number } = {}
            for index = 1, 4 do
              local chunk = chunks[(index - 1) % #chunks + 1]
              local ship = Space.NewShip(state, hull, "Ice Harvester", yard, 0)
              for _ = 1, Ships.byId[hull].turrets do
                Items.Equip(state, ship.id, "miner.ice", nil)
              end
              local angle = Rng.Float(rng, 0, 2 * math.pi)
              local off = chunk.radius + 2500
              local ball = Space.Launch(state, ship, system, chunk.x + off * math.cos(angle), chunk.y + Rng.Float(rng, -600, 600),
                chunk.z + off * math.sin(angle))
              table.insert(events, { kind = "BallAdded", ball = ball.id })
              table.insert(barges, ball.id)
            end
            local first = state.balls[barges[1]]
            cameraAt(state, system, first.x + 5000, first.y + 2000, first.z, events)
            -- (from the first: they are at it before it is shown)
            local next = -math.huge
            return {
              director = director(first.id, 3.6, 1.25, 0.01, Rng.Float(rng, 0, 2 * math.pi)),
              -- (each barge, now and then: in reach of the chunk nearest it, locked on, harvesters on)
              during = function(state: State.State, age: number, events: { Event }): boolean?
                if age < next then
                  return nil
                end
                next = age + 1
                for _, id in barges do
                  local me = state.balls[id]
                  if me then
                    local chunk: System.Object?, least = nil, math.huge
                    for _, each in chunks do
                      local far = Space.Distance(each :: any, me :: any)
                      if far < least then
                        chunk, least = each, far
                      end
                    end
                    local rock = chunk :: System.Object
                    if Space.Gap(me :: any, rock :: any) > 8000 then
                      give(state, { kind = "Approach", actor = id, target = rock.id, range = 4000 }, events)
                    else
                      local locked = false
                      for _, lock in me.vitals.locks do
                        locked = locked or (lock.target == rock.id and lock.locked)
                      end
                      if #me.vitals.locks == 0 then
                        give(state, { kind = "LockTarget", actor = id, target = rock.id }, events)
                      elseif locked then
                        for _, item in Items.Fitted(state, id) do
                          local running = false
                          for _, on in me.vitals.running do
                            running = running or on.item == item.id
                          end
                          if not running then
                            give(state, { kind = "ActivateModule", actor = id, item = item.id, target = rock.id }, events)
                          end
                        end
                      end
                    end
                  end
                end
                return nil
              end,
            }
          end
        end
      end
      return nil
    end,
  },
  -- A citadel of a people's at a moon, lit, with their ships about it.
  {
    name = "citadel",
    length = 24,
    stage = function(state, rng, events)
      local citadels: { Structures.Tower } = {}
      for _, tower in Structures.towerById do
        if tower.citadel and tower.faction == "" then
          table.insert(citadels, tower)
        end
      end
      table.sort(citadels, function(a, b)
        return a.id < b.id
      end)
      if #citadels == 0 then
        return nil
      end
      for _, system in shuffled(state, rng) do
        local node = state.galaxy.systems[system]
        local keeper = Galaxy.Keeper(node)
        local moons = objectsOf(state, system, "moon")
        if keeper ~= "" and Factions.byId[keeper].kind == "human" and #moons > 0 then
          local moon = moons[Rng.Int(rng, #moons) + 1]
          local tower = citadels[Rng.Int(rng, #citadels) + 1]
          local angle = Rng.Float(rng, 0, 2 * math.pi)
          local out = moon.radius + 30000
          local x, z = moon.x + out * math.cos(angle), moon.z + out * math.sin(angle)
          local id = Starbases.Raise(state, system, moon, tower, keeper, x, moon.y, z)
          local starbase = state.starbases[id]
          starbase.ready, starbase.fuel = state.tick, 20000
          -- (and their ships going round it)
          for index, class in { "battleship", "cruiser", "cruiser", "frigate", "frigate" } do
            local round = index * 2 * math.pi / 5
            local far = tower.field + 3000 + index * 800
            local ball = warship(state, keeper, class, system, x + far * math.cos(round), moon.y + Rng.Float(rng, -1000, 1000),
              z + far * math.sin(round), events)
            if ball then
              give(state, { kind = "Orbit", actor = ball.id, target = id, range = far }, events)
            end
          end
          -- (from the side the star lights: the star is the middle of the system)
          local lit = math.atan2(-z, -x)
          cameraAt(state, system, x + (tower.field + 12000) * math.cos(lit), moon.y + 4000,
            z + (tower.field + 12000) * math.sin(lit), events)
          return { director = director(id, 2.4, 1.3, 0.01, lit - 0.5) }
        end
      end
      return nil
    end,
  },
  -- A hauler come through a gate in a people's space, pirates falling on
  -- it there, and the police coming through after them.
  {
    name = "gate ambush",
    length = 30,
    stage = function(state, rng, events)
      for _, system in shuffled(state, rng) do
        local node = state.galaxy.systems[system]
        local keeper = Galaxy.Keeper(node)
        local gates, stations = objectsOf(state, system, "gate"), objectsOf(state, system, "station")
        local hull = if keeper ~= "" then Traffic.Stage.HullOf(keeper, "industrial") else nil
        if hull and Galaxy.Band(Galaxy.Order(node)) == "secure" and #gates > 0 and #stations > 0
          and Traffic.Warship(keeper, "frigate") then
          local gate = gates[Rng.Int(rng, #gates) + 1]
          -- (the hauler, out of the gate and bound in to dock, as the traffic's are)
          local ship = Space.NewShip(state, hull, "Trader", "civilian", 0)
          local ball = Space.Launch(state, ship, system, gate.x, gate.y, gate.z)
          table.insert(events, { kind = "BallAdded", ball = ball.id, gate = gate.id })
          Space.ComeThrough(state, ball, gate, events)
          Traffic.Stage.Enlist(state, ship, "in", stations[1].id, system)
          state.traffic[ship.id].wait = -1
          local angle = Rng.Float(rng, 0, 2 * math.pi)
          local out = gate.radius + 7000
          for index, kind in { "jackal", "raider", "raider", "raider" } do
            local round = angle + (index - 2.5) * 0.35
            local pirate = Pirates.Spawn(state, Pirates.kindById[kind], system, gate.x + out * math.cos(round),
              gate.y + Rng.Float(rng, -600, 600), gate.z + out * math.sin(round), gate.id)
            table.insert(events, { kind = "BallAdded", ball = pirate.id })
          end
          cameraAt(state, system, gate.x - out * math.cos(angle), gate.y + 2000, gate.z - out * math.sin(angle), events)
          -- (the police: the people's ships, through the gate after them, and set on the pirates there)
          local classes = { "destroyer", "frigate", "frigate", "destroyer" }
          local police: { number } = {}
          local bring = arrivals(#classes, 9, 1.2, gate, function(state: State.State, index: number, events: { Event }): State.Ball?
            local lawman = warship(state, keeper, classes[index], system, gate.x, gate.y, gate.z, events)
              or warship(state, keeper, "frigate", system, gate.x, gate.y, gate.z, events)
            if lawman then
              state.pilots[lawman.id] = { ship = lawman.id, range = 2500, prey = 0, home = gate.id, alone = 0, bounty = 0, tags = 0,
                side = "player" }
              State.InsertId(state.pilotIds, lawman.id)
            end
            return lawman
          end, police)
          return {
            director = director(gate.id, 2.4, 1.36, 0.012, angle + math.pi + 0.4),
            during = function(state: State.State, age: number, events: { Event }): boolean?
              bring(state, age, events)
              return nil
            end,
          }
        end
      end
      return nil
    end,
  },
  -- Two peoples' carrier groups at war, each sending everything in its
  -- bays at the other: the camera on a carrier as its fighters come out,
  -- then riding along with one of them across to the enemy, and at the
  -- last on the enemy's supercarrier under the swarm (the owner,
  -- 2026-11-27: "dueling carrier/supercarriers fleets launching lots and
  -- lots of fighters and bombers").
  {
    name = "carrier battle",
    length = 34,
    stage = function(state, rng, events)
      for _, system in shuffled(state, rng) do
        local at = if kept(state, system) then offPlanet(state, system, 400000) else nil
        if at then
          local cx, cy, cz = at[1], at[2], at[3]
          local angle = Rng.Float(rng, 0, 2 * math.pi)
          local ux, uz = math.cos(angle), math.sin(angle)
          local px, pz = -uz, ux
          local function put(hull: string, owner: string, along: number, across: number, up: number): State.Ball
            local ball = fitted(state, hull, owner, system, cx + ux * along + px * across, cy + up, cz + uz * along + pz * across, events)
            fights(state, ball, owner, 30000)
            return ball
          end
          local flag = put("ultracapital.daiichi", "vessari", -22000, 0, 0)
          local ours = put("carrier.azayake", "vessari", -19000, 3500, 600)
          put("carrier.azayake", "vessari", -19000, -3500, -600)
          local theirs = put("supercarrier.nullo", "talmar", 22000, 0, 0)
          put("carrier.scoppo", "talmar", 19000, 3500, -500)
          put("carrier.scoppo", "talmar", 19000, -3500, 500)
          local _ = flag
          cameraAt(state, system, cx, cy + 6000, cz + 12000 * pz, events)
          -- (behind our carrier, looking across at theirs)
          local shot = director(ours.id, 2.8, 1.3, 0.01, math.atan2(-uz, -ux) + 0.35)
          local riding = 0
          return {
            director = shot,
            during = function(state: State.State, age: number, events: { Event }): boolean?
              -- (onto one of its fighters once a few are out, from behind it)
              if riding == 0 and age >= 7 then
                for _, drone in Drones.Out(state, ours.id) do
                  local ball = state.balls[drone.ship]
                  if riding == 0 and ball then
                    riding = drone.ship
                    shot.target, shot.zoom, shot.pitch, shot.spin, shot.fresh = riding, 10, 1.42, 0, true
                    shot.yaw = math.atan2(-uz, -ux)
                  end
                end
              end
              -- (and at the last on their supercarrier, with the swarm about it)
              if age >= 22 and shot.target ~= theirs.id and state.balls[theirs.id] then
                shot.target, shot.zoom, shot.pitch, shot.spin, shot.fresh = theirs.id, 3.2, 1.3, 0.012, true
                shot.yaw = math.atan2(-uz, -ux) + 0.6
              end
              return nil
            end,
          }
        end
      end
      return nil
    end,
  },
  -- The Kethri's vertical launch batteries rippling their missiles up
  -- out of their cells, close; then from behind their target, the
  -- missiles coming down on it through its point defence's tracers (the
  -- owner, 2026-11-27).
  {
    name = "missile volley",
    length = 32,
    stage = function(state, rng, events)
      for _, system in shuffled(state, rng) do
        local at = if kept(state, system) then offPlanet(state, system, 300000) else nil
        if at then
          local cx, cy, cz = at[1], at[2], at[3]
          local angle = Rng.Float(rng, 0, 2 * math.pi)
          local ux, uz = math.cos(angle), math.sin(angle)
          local px, pz = -uz, ux
          -- (theirs: vertical launch batteries, loaded)
          local shooters: { number } = {}
          -- (each the biggest battery it can fit, and the missiles for it)
          local BATTERIES = { { "launcher.vertical.xl", "missile.vertical.siege.thermal" },
            { "launcher.vertical.large", "missile.vertical.cruise.thermal" }, { "launcher.vertical.medium", "missile.vertical.heavy.thermal" },
            { "launcher.vertical.small", "missile.vertical.light.thermal" } }
          -- (a battleship and two battlecruisers, a battery each: few enough missiles that each is seen, and
          -- the point defence's tracers among them, and not one white wash of contrails, as a dreadnought's
          -- four and the rest made)
          for _, each in { { "battleship.teardrop", 0, 0 }, { "battlecruiser.extremis", 1800, -1200 },
            { "battlecruiser.extremis", -1800, -1200 } } :: { { any } } do
            local ship = Space.NewShip(state, each[1], `Kethri {Ships.byId[each[1]].name}`, "kethri", 0)
            for _ = 1, 1 do
              for _, battery in BATTERIES do
                if pcall(Items.Equip, state, ship.id, battery[1], battery[2]) then
                  Items.Add(state, battery[2], 100, ship.id, "cargo")
                  break
                end
              end
            end
            local ball = Space.Launch(state, ship, system, cx + px * each[2] + ux * each[3], cy, cz + pz * each[2] + uz * each[3])
            table.insert(events, { kind = "BallAdded", ball = ball.id })
            table.insert(shooters, ball.id)
          end
          -- (the pirates': a battleship and two cruisers with a point defence turret on every turret mount,
          -- under way across the line the missiles come along at their cruising speed and nobody's to turn
          -- aside: the owner, 2026-11-27, "the target ship ... looks like it's not moving", and of the tracers,
          -- "barely visible")
          local targets: { number } = {}
          for index, hull in { "battleship.ravager", "cruiser.marauder", "cruiser.marauder" } do
            local off = (index - 2) * 1800
            local ship = Space.NewShip(state, hull, `Pirate {Ships.byId[hull].name}`, "pirates", 0)
            for _ = 1, Ships.byId[hull].turrets do
              pcall(Items.Equip, state, ship.id, "pds.small", "ammo.emp")
            end
            Items.Add(state, "ammo.emp", 4000, ship.id, "cargo")
            local ball = Space.Launch(state, ship, system, cx + ux * 32000 + px * off, cy + (index - 2) * 300, cz + uz * 32000 + pz * off)
            local cruise = ball.maxVelocity * 0.75
            ball.vx, ball.vy, ball.vz = px * cruise, 0, pz * cruise
            give(state, { kind = "Goto", actor = ball.id, x = px, y = 0, z = pz }, events)
            table.insert(events, { kind = "BallAdded", ball = ball.id })
            table.insert(targets, ball.id)
          end
          cameraAt(state, system, cx - ux * 8000, cy + 3000, cz - uz * 8000, events)
          -- (close on the dreadnought, from behind, to one side and a little
          -- below it, looking up: the missiles go up out of their cells)
          local shot = director(shooters[1], 2.7, 1.68, 0.008, math.atan2(-uz, -ux) + 0.7)
          local next, turned = 0, false
          return {
            director = shot,
            during = function(state: State.State, age: number, events: { Event }): boolean?
              if age >= next then
                next = age + 0.5
                local prey = targets[1]
                -- (every battery on the battleship, once it is locked)
                for _, id in shooters do
                  local me = state.balls[id]
                  if me and state.balls[prey] then
                    local locked, asked = false, false
                    for _, lock in me.vitals.locks do
                      -- (locked at once, for the scene: a capital's sensors would take it longer than it lasts)
                      if lock.target == prey then
                        lock.locked, lock.done = true, math.min(lock.done, state.tick)
                      end
                      asked = asked or lock.target == prey
                      locked = locked or (lock.target == prey and lock.locked)
                    end
                    if not asked then
                      give(state, { kind = "LockTarget", actor = id, target = prey }, events)
                    elseif locked then
                      for _, item in Items.Fitted(state, id) do
                        local running = false
                        for _, on in me.vitals.running do
                          running = running or on.item == item.id
                        end
                        if not running then
                          give(state, { kind = "ActivateModule", actor = id, item = item.id, target = prey }, events)
                        end
                      end
                    end
                  end
                end
                -- (their point defence, on)
                for _, id in targets do
                  local them = state.balls[id]
                  if them then
                    for _, item in Items.Fitted(state, id) do
                      if string.sub(item.type, 1, 4) == "pds." then
                        local running = false
                        for _, on in them.vitals.running do
                          running = running or on.item == item.id
                        end
                        if not running then
                          give(state, { kind = "ActivateModule", actor = id, item = item.id }, events)
                        end
                      end
                    end
                  end
                end
              end
              -- (and then from behind their target, looking back up the way they come)
              if not turned and age >= 9 and state.balls[targets[1]] then
                turned = true
                shot.target, shot.zoom, shot.pitch, shot.spin, shot.fresh = targets[1], 6, 1.5, 0.004, true
                shot.yaw = math.atan2(pz, px) + 0.9
              end
              return nil
            end,
          }
        end
      end
      return nil
    end,
  },
}

-- The order they play in: the quiet and the fights by turns.
local ORDER = { "mining fleet", "station raid", "alien gate", "freighter warping", "fleet battle", "ice harvest", "carrier battle",
  "colony fleet", "missile volley", "citadel", "drowned", "capital raid", "wormhole", "gate ambush" }
do
  local rank: { [string]: number } = {}
  for index, name in ORDER do
    rank[name] = index
  end
  table.sort(SCENES, function(a: Scene, b: Scene): boolean
    return (rank[a.name] or 99) < (rank[b.name] or 99)
  end)
end

-- The showcase's game, made anew for a scene: a galaxy of its own, with
-- its traffic about, and nobody at war.
local function newGame(show: Show)
  show.made += 1
  local seed = 7919 * show.made + 17
  local game = Core.New({ galaxySeed = seed, historySeed = seed, systems = SYSTEMS, traffic = true, starter = true })
  -- (nobody comes but who a scene brings: the pirates' own comings and
  -- goings would be about the camera in the lawless)
  game.state.peaceful = true
  -- (a few seconds on, so that it is not the very first moment of the
  -- galaxy: a colony fleet, for one, would be only now coming through
  -- its gate, Tactical/Traffic)
  for _ = 1, WARM do
    Core.Step(game)
  end
  Core.TakeEvents(game)
  show.session.game = game
  show.session.epoch = EPOCHS + show.made
  show.session.clock = Clock.New()
  show.session.events = {}
end

-- Put the next scene that will go into a game of its own (trying the
-- one after, if a galaxy has nowhere for it).
local function nextScene(show: Show)
  for _ = 1, #SCENES * 2 do
    show.index = show.index % #SCENES + 1
    local scene = SCENES[show.index]
    newGame(show)
    local state = show.session.game.state
    local events: { Event } = {}
    local rng = Rng.For(show.made, show.index, 4409)
    local staged = scene.stage(state, rng, events)
    if staged then
      -- (run on a few seconds before it is shown: what is in it is under
      -- way, and not seen setting off and swinging round to its heading
      -- in the first moments, the owner, 2026-11-27. What the scene does
      -- as it plays is done meanwhile, at the seconds before it begins.)
      local game = show.session.game
      for _, event in events do
        table.insert(game.events, event)
      end
      for tick = 1, PREROLL do
        Core.Step(game)
        local during = staged.during
        if during then
          during(state, (tick - PREROLL - 1) * Constants.TICK, game.events)
        end
      end
      Core.TakeEvents(game)
      show.staged, show.director, show.length, show.age = staged, staged.director, scene.length, 0
      return
    end
  end
  show.staged, show.director = nil, nil
end

-- A showcase, its first scene put.
function Showcase.New(): Show
  local show: Show = {
    session = {} :: any, index = 0, length = 0, age = 0, staged = nil, director = nil, curtain = 1, made = 0,
  }
  show.session = {
    game = nil :: any, clock = Clock.New(), events = {}, epoch = EPOCHS, selected = 0, target = 0, aimed = {}, aimedAt = 0,
    message = "", heard = {}, log = {}, messageTick = 0, messageKind = "plain",
  } :: any
  nextScene(show)
  return show
end

-- Play it on by 'seconds': its game goes on, and at the end of a scene
-- the next is put.
function Showcase.Update(show: Show, seconds: number)
  show.age += seconds
  if show.age >= show.length then
    nextScene(show)
  end
  local session = show.session
  local game = session.game
  session.events = {}
  local staged = show.staged
  for _ = 1, Clock.Advance(session.clock, seconds) do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      table.insert(session.events, event)
    end
  end
  -- (what the scene does, after the game has gone on: so that what it
  -- puts where it wants it, as the colony fleet's formation, is drawn
  -- there, whatever the step did; what it brings is seen this frame)
  if staged and staged.during then
    local events: { Event } = {}
    if staged.during(game.state, show.age, events) and show.length > show.age + OVER then
      show.length = show.age + OVER
    end
    for _, event in events do
      table.insert(session.events, event)
    end
  end
  -- (black at either end of the scene)
  local into, left = show.age / FADE, (show.length - show.age) / FADE
  show.curtain = math.clamp(1 - math.min(into, left), 0, 1)
end

-- Its name, for a script: which scene is playing.
function Showcase.Playing(show: Show): string
  local scene = SCENES[show.index]
  return if scene and show.staged then scene.name else ""
end

-- The names of its scenes, in the order they play.
function Showcase.Scenes(): { string }
  local names: { string } = {}
  for _, scene in SCENES do
    table.insert(names, scene.name)
  end
  return names
end

-- Begin at a scene, by its name (for a script, or a picture). False if
-- there is no such scene, or the galaxy has nowhere for it.
function Showcase.Play(show: Show, name: string): boolean
  for index, scene in SCENES do
    if scene.name == name then
      show.index = index - 1
      nextScene(show)
      return show.staged ~= nil and show.index == index
    end
  end
  return false
end

return Showcase
