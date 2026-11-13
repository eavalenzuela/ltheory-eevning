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
-- The ship comes out at rest a little way off a station of the system
-- it went to (the first there is), or off a gate where there is no
-- station. What it had out and near comes with it, as into a warp
-- (Tactical/Drones).
--
-- (Every figure is a first proposal. Not yet: anybody but the pilot
-- jumping; a place to come out at that the pilot chooses, or that
-- somebody lights for them; space a drive does not reach into.)

local Constants = require("@lt/Core/Data/Constants")
local Items = require("@lt/Core/Assets/Items")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local System = require("@lt/Core/Describe/System")
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

-- How far it is from one system to another on the map, light years.
function Jumping.Distance(state: State.State, from: number, to: number): number
  local a, b = state.galaxy.systems[from], state.galaxy.systems[to]
  return if a and b then math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) else math.huge
end

-- The fuel blocks a ship burns to jump so far.
function Jumping.Fuel(state: State.State, ship: number, distance: number): number
  local hull = Ships.byId[state.ships[ship].type]
  return math.max(1, math.ceil(distance * hull.mass / Jumping.FUEL_MASS))
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

-- What a ship jumping into a system comes out beside: its first
-- station, or its first gate if it has none.
function Jumping.Beacon(state: State.State, system: number): System.Object?
  local gate: System.Object? = nil
  for _, object in Space.Describe(state, system).objects do
    if object.kind == "station" then
      return object
    elseif object.kind == "gate" and gate == nil then
      gate = object
    end
  end
  return gate
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
  elseif Jumping.Beacon(state, to) == nil then
    return false, "nothing there to come out beside"
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
  local beacon = Jumping.Beacon(state, to) :: System.Object
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
    distance = distance })
end

return Jumping
