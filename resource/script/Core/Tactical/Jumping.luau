--!strict
-- Jump drives: a ship that goes to another system without a gate.
--
-- A hull that is built with a jump drive (Data/Ships' 'jump': a
-- faction's line says which, Data/Factions) can leave the system it is
-- in from anywhere in space and be in another, as far off as its drive
-- reaches on the map and however many gates lie between:
--   - It reaches Jumping.RANGE light years, and a tenth further for
--     each level of Jump Drive Operation, which it takes one level of to
--     use at all.
--   - It burns fuel blocks out of the hold (the fuel a tower burns:
--     Data/Structures), so many a light year for the mass of the hull.
--   - It takes most of a full capacitor, and leaves little of it.
--   - It cannot be done from warp, with a warp scrambler on the ship, or
--     again until the drive has cooled (Jumping.COOLDOWN).
--   - And there has to be a beacon lit in the system it goes to (the
--     project owner's rule, 2026-11-13): a Jump Beacon anchored and
--     online at a lit tower of the pilot's there (Data/Structures,
--     Assets/Starbases), or a ship of the pilot's fleet out in space
--     there with a Jump Beacon Generator running (Data/Modules: a hired
--     pilot keeps theirs running, Tactical/Fleet).
-- The ship comes out at rest a little way off the beacon: the tower,
-- or the ship that lit one. (A tower's before a ship's, where there are
-- both.) What it had out and near comes with it, as into a warp
-- (Tactical/Drones).
--
-- A hired pilot whose ship has a drive uses it (Tactical/Fleet): to go
-- after the pilot, or wherever their orders send them, they jump where a
-- beacon is lit within reach and the fuel is aboard, and go by the gates
-- where not.
--
-- (Every figure is a first proposal. Not yet: a choice between beacons
-- in one system; anybody else's beacon; space a drive does not reach
-- into.)

local Constants = require("@lt/Core/Data/Constants")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Skills = require("@lt/Core/Data/Skills")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local Modules = require("@lt/Core/Data/Modules")
local Space = require("@lt/Core/Tactical/Space")
local Starbases = require("@lt/Core/Assets/Starbases")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local Vitals = require("@lt/Core/Tactical/Vitals")

local Jumping = {}

export type Event = { [string]: any }

-- Light years a drive reaches, and how much further for each level of
-- the skill.
Jumping.RANGE = 20
Jumping.FURTHER = 0.1
Jumping.SKILL = "jump.drives"
-- Kilograms of hull a fuel block takes a light year.
Jumping.FUEL_MASS = 50000000
-- What a level of Lean Burn takes off the fuel of a jump (Data/Skills).
Jumping.LEAN = 0.05
-- The share of its capacitor a ship has to have to jump, and the share
-- it is left with.
Jumping.CAPACITOR = 0.7
Jumping.LEFT = 0.05
-- Seconds before the drive will fire again.
Jumping.COOLDOWN = 300
-- How far from what it comes out at a ship comes out, m.
Jumping.LAND = 20000

-- Whether a ship has a jump drive.
function Jumping.Fitted(state: State.State, ship: number): boolean
  local record = state.ships[ship]
  local hull = if record then Ships.byId[record.type] else nil
  return hull ~= nil and hull.jump == true
end

-- How far a ship's drive reaches, light years, with whoever flies it.
function Jumping.Range(state: State.State, ship: number): number
  local levels = Items.Levels(state, ship)
  local level = if levels then math.max(0, levels[Jumping.SKILL] or 0) else 5
  return Jumping.RANGE * (1 + Jumping.FURTHER * level)
end

-- How far it is from one system to another, light years: through
-- space, which has a height as well as the two ways the map lies
-- (Describe/Galaxy).
function Jumping.Distance(state: State.State, from: number, to: number): number
  return Galaxy.Apart(state.galaxy, from, to)
end

-- The fuel blocks a ship burns to jump so far.
function Jumping.Fuel(state: State.State, ship: number, distance: number): number
  local hull = Ships.byId[state.ships[ship].type]
  -- (less of it, for a pilot who has learned Lean Burn)
  local lean = 1 - Jumping.LEAN * Skills.Level(Items.Levels(state, ship), "lean.burn")
  return math.max(1, math.ceil(distance * hull.mass / Jumping.FUEL_MASS * lean - 1e-9))
end

-- The fuel blocks in a ship's hold.
function Jumping.Held(state: State.State, ship: number): number
  local held = 0
  for _, item in Items.In(state, ship, "cargo") do
    held += if item.type == Structures.FUEL.id then item.quantity else 0
  end
  return held
end

-- The seconds until a ship's drive will fire again (0: it is ready).
function Jumping.Cooling(state: State.State, ship: number): number
  local record = state.ships[ship]
  local last = if record then record.jumped else nil
  return if last then math.max(0, Jumping.COOLDOWN - (state.tick - last) * Constants.TICK) else 0
end

-- A beacon that is lit: where it is, how big the thing that has it is,
-- what that is (a tower's place in its system's description, or a
-- ship), its name, and which kind of beacon it is.
export type Beacon = { system: number, x: number, y: number, z: number, radius: number, id: number, name: string, kind: "tower" | "ship" }

-- The beacons lit for a ship's owner, in every system: the towers
-- first, in the order they were put up, and then the ships of the
-- fleet, in the order of their ids. (Not the ship's own: nobody jumps
-- to where they are.)
function Jumping.Beacons(state: State.State, ship: number): { Beacon }
  local record = state.ships[ship]
  local found: { Beacon } = {}
  if record == nil then
    return found
  end
  for _, id in state.starbaseIds do
    local starbase = state.starbases[id]
    local place = Space.Object(state, id)
    if starbase.owner == record.owner and place and Starbases.Has(state, starbase, "beacon") then
      table.insert(found, { system = Space.SystemOf(state, id), x = place.x, y = place.y, z = place.z, radius = place.radius, id = id,
        name = place.name, kind = "tower" })
    end
  end
  for _, id in state.shipIds do
    local other = state.ships[id]
    local ball = state.balls[id]
    if id ~= ship and other.owner == record.owner and ball and not ball.warp then
      for _, running in ball.vitals.running do
        local item = state.items[running.item]
        if item and Modules.byId[item.type] and Modules.byId[item.type].beacon then
          table.insert(found, { system = ball.system, x = ball.x, y = ball.y, z = ball.z, radius = ball.radius, id = id, name = ball.name,
            kind = "ship" })
          break
        end
      end
    end
  end
  return found
end

-- The beacon a ship jumping into a system comes out at, if one is lit
-- there for it.
function Jumping.Beacon(state: State.State, ship: number, system: number): Beacon?
  for _, beacon in Jumping.Beacons(state, ship) do
    if beacon.system == system then
      return beacon
    end
  end
  return nil
end

-- Whether a ship that cannot jump to a system now will be able to with
-- nothing done but waiting: there is a beacon lit there within its
-- reach, whoever flies it can use the drive, and the fuel is aboard.
-- (What is left to be in the way passes: a drive that is cooling, a
-- capacitor that is short, a scrambler.)
function Jumping.Soon(state: State.State, ship: number, to: number): boolean
  local ball = state.balls[ship]
  if ball == nil or not Jumping.Fitted(state, ship) or state.galaxy.systems[to] == nil or to == ball.system
    or Jumping.Beacon(state, ship, to) == nil then
    return false
  elseif state.galaxy.systems[to].uncharted or state.galaxy.systems[ball.system].uncharted then
    return false
  end
  local levels = Items.Levels(state, ship)
  if levels and math.max(0, levels[Jumping.SKILL] or 0) < 1 then
    return false
  end
  local distance = Jumping.Distance(state, ball.system, to)
  return distance <= Jumping.Range(state, ship) and Jumping.Held(state, ship) >= Jumping.Fuel(state, ship, distance)
end

function Jumping.Validate(state: State.State, command: State.Command): (boolean, string?)
  local ship = state.ships[command.actor]
  if ship == nil then
    return false, "no such ship"
  end
  local ball = state.balls[ship.id]
  local to = command.target or 0
  if not Jumping.Fitted(state, ship.id) then
    return false, "this hull has no jump drive"
  elseif ball == nil then
    return false, "docked"
  elseif ball.warp then
    return false, "in warp"
  elseif ball.vitals.scrambled then
    return false, "warp scrambled"
  elseif state.galaxy.systems[to] == nil then
    return false, "no such system"
  elseif to == ball.system then
    return false, "that is the system you are in"
  elseif state.galaxy.systems[to].uncharted or state.galaxy.systems[ball.system].uncharted then
    -- (a drive works out its jump from the map: Tactical/Wormholes)
    return false, "no drive finds its way in or out of uncharted space"
  elseif Jumping.Beacon(state, ship.id, to) == nil then
    return false, "no beacon is lit there"
  end
  local levels = Items.Levels(state, ship.id)
  if levels and math.max(0, levels[Jumping.SKILL] or 0) < 1 then
    return false, "needs Jump Drive Operation 1"
  end
  local distance, range = Jumping.Distance(state, ball.system, to), Jumping.Range(state, ship.id)
  if distance > range then
    return false, string.format("out of reach: %.1f light years, and the drive reaches %.1f", distance, range)
  end
  local cooling = Jumping.Cooling(state, ship.id)
  if cooling > 0 then
    return false, `the drive is cooling: {math.ceil(cooling)} s`
  elseif ball.vitals.capacitor < Jumping.CAPACITOR * ball.vitals.capacitorMax then
    return false, `needs {math.floor(Jumping.CAPACITOR * 100 + 0.5)}% of the capacitor`
  end
  local fuel, held = Jumping.Fuel(state, ship.id, distance), Jumping.Held(state, ship.id)
  if held < fuel then
    return false, `needs {fuel} fuel blocks in the hold, and there are {held}`
  end
  return true
end

function Jumping.Apply(state: State.State, command: State.Command, events: { Event })
  local ship = state.ships[command.actor]
  local ball = state.balls[ship.id]
  local to = command.target :: number
  local from = ball.system
  local distance = Jumping.Distance(state, from, to)
  local left = Jumping.Fuel(state, ship.id, distance)
  for _, item in Items.In(state, ship.id, "cargo") do
    if item.type == Structures.FUEL.id and left > 0 then
      local take = math.min(left, item.quantity)
      left -= take
      Items.Take(state, item, take)
    end
  end
  ball.vitals.capacitor = Jumping.LEFT * ball.vitals.capacitorMax
  ball.vitals.running, ball.vitals.locks = {}, {}
  ship.jumped = state.tick
  local beacon = Jumping.Beacon(state, ship.id, to) :: Beacon
  -- (a point so far from it, in a direction rolled for this jump)
  local rng = Rng.For(state.historySeed, state.tick, ball.id, 37)
  local angle = Rng.Float(rng, 0, 2 * math.pi)
  local out = beacon.radius + Jumping.LAND + ball.radius
  ball.system = to
  ball.x, ball.y, ball.z = beacon.x + out * math.cos(angle), beacon.y + Rng.Float(rng, -0.1, 0.1) * out, beacon.z + out * math.sin(angle)
  ball.vx, ball.vy, ball.vz = 0, 0, 0
  ball.tvx, ball.tvy, ball.tvz = 0, 0, 0
  ball.mode, ball.target = "stop", 0
  ball.warp, ball.intent = nil, nil
  Space.AssignGrid(state, ball)
  Vitals.Refresh(state, ball)
  -- (a jump, to everything that minds one: 'gate' is 0 for a drive's)
  table.insert(events, { kind = "Jumped", ship = ball.id, from = from, to = to, gate = 0, arrival = beacon.id, drive = true,
    distance = distance, beacon = beacon.name })
end

return Jumping
