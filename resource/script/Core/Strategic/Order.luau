--!strict
-- Order: how firmly each system is held, how much piracy it suffers, how
-- safe that leaves it, and what all of it does to trade.
--
-- Piracy is not ships. It is a pressure in every system, from 0 to 1:
-- dens raise it, lawlessness lets it grow, it spreads along the gates,
-- and policing and garrisons push it down. (Pirate fleets exist too, for
-- raids and for building dens: Strategic/Raiders.)
--
-- An owner's hold on a system (its control) grows with policing, with
-- nearness to the capital and with a garrison, and is worn down by
-- pirate pressure. How safe a system is follows from the two. Safety is
-- what trade sees: a lane costs more to use the less safe its ends are,
-- pirates take a share of what crosses it, and war or an embargo closes
-- it.
--
-- Step runs every period (ten minutes); Lanes every round, so that a
-- blockade bites at once.

local Atlas = require("@lt/Core/Strategic/Atlas")
local Powers = require("@lt/Core/Data/Powers")
local World = require("@lt/Core/Strategic/World")

local Order = {}

-- Is this system at a front: under siege, or beside a system of someone
-- its owner is at war with?
local function front(world: World.World, system: number): boolean
  local s = world.systems[system]
  if s.siege ~= nil then
    return true
  end
  if s.owner == 0 or #world.wars == 0 then
    return false
  end
  for _, n in world.galaxy.systems[system].neighbors do
    local other = world.systems[n].owner
    if other > 0 and other ~= s.owner and World.WarBetween(world, s.owner, other) then
      return true
    end
  end
  return false
end

function Order.Security(world: World.World, system: number): number
  local s = world.systems[system]
  local calm = 1 - Powers.SECURITY_PRESSURE * s.pressure
  if s.owner == 0 then
    return Powers.LOCAL_ORDER * calm
  end
  return math.clamp(s.control * calm * (if front(world, system) then Powers.FRONT else 1), 0, 1)
end

function Order.Step(world: World.World)
  local hours = Powers.PERIOD_HOURS
  local systems = world.systems
  local count = #systems

  -- Pressure: every system's new level from the old ones.
  local pressure: { number } = table.create(count, 0)
  for id, s in systems do
    local neighbors = world.galaxy.systems[id].neighbors
    local around = 0
    for _, n in neighbors do
      around += systems[n].pressure
    end
    around = if #neighbors > 0 then around / #neighbors else s.pressure
    local garrison = if s.owner > 0 then math.min(1, World.StrengthAt(world, id, s.owner) / Powers.GARRISON) else 0
    local policed = if s.owner > 0 then world.factions[s.owner].policing * s.control else 0
    local rise = (if s.den then Powers.PRESSURE_DEN else 0) + Powers.PRESSURE_LAWLESS * (1 - s.security)
      + Powers.PRESSURE_SPREAD * (around - s.pressure)
    local fall = Powers.PRESSURE_DECAY + Powers.PRESSURE_POLICED * policed + Powers.PRESSURE_GARRISON * garrison
    -- (the fall is a rate on what is there, so a long period cannot overshoot)
    pressure[id] = math.clamp((s.pressure + rise * hours) / (1 + fall * hours), 0, 1)
  end

  for id, s in systems do
    s.pressure = pressure[id]
    if s.owner > 0 then
      local faction = world.factions[s.owner]
      local garrison = math.min(1, World.StrengthAt(world, id, s.owner) / Powers.GARRISON)
      local target = Powers.CONTROL_BASE + Powers.CONTROL_POLICE * faction.policing
        + Powers.CONTROL_NEAR * Powers.CONTROL_FADE ^ math.max(0, faction.hops[id])
        + Powers.CONTROL_GARRISON * garrison - Powers.CONTROL_PRESSURE * s.pressure
      if World.Foreign(world, id, s.owner) then
        target *= Powers.OCCUPIED
      end
      -- A system under siege is slipping away; one in arrears is neglected.
      if s.siege ~= nil then
        target = 0
      elseif faction.arrears > 0 then
        target *= 0.7
      end
      target = math.clamp(target, 0.05, 1)
      s.control += math.clamp(target - s.control, -Powers.CONTROL_FALL * hours, Powers.CONTROL_RISE * hours)
    end
    -- Defences are rebuilt when nobody is shooting at them.
    if s.siege == nil and s.fighting == 0 and s.defence < 1 then
      s.defence = math.min(1, s.defence + Powers.DEFENCE_REPAIR * hours)
    end
  end
  for id, s in systems do
    s.security = Order.Security(world, id)
  end
end

-- Cut off: a siege is past the point of standing off.
local function blockaded(s: World.System): boolean
  local siege = s.siege
  return siege ~= nil and siege.kind == "siege"
end

-- Set every lane's cost, losses, haulage and whether it is open from who
-- holds its ends and how safe they are. Lane i of the atlas is edge i of
-- the economy.
function Order.Lanes(world: World.World)
  local systems = world.systems
  local edges = world.econ.edges
  local factions = world.factions
  local anyWar = #world.wars > 0
  for at, lane in world.atlas.lanes do
    local edge = edges[at]
    local a, b = systems[lane.a], systems[lane.b]
    local oa, ob = a.owner, b.owner
    local open = not (blockaded(a) or blockaded(b))
    local border = oa ~= ob and oa > 0 and ob > 0
    if open and border then
      if anyWar and World.WarBetween(world, oa, ob) then
        open = false
      elseif factions[oa].stance[ob] > 0 or factions[ob].stance[oa] > 0 then
        open = false
      end
    end
    local pressure = math.max(a.pressure, b.pressure)
    edge.open = open
    edge.cost = Atlas.COST_JUMP + (if border then Atlas.COST_BORDER else 0)
      + Atlas.COST_RISK * (1 - math.min(a.security, b.security))
    edge.loss = Powers.THEFT * pressure
    edge.conductance = lane.conductance * (1 - Powers.PRESSURE_HAULAGE * pressure)
  end
end

return Order
