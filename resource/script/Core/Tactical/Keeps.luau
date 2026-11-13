--!strict
-- Keeps: the pirates' own towers, and the bringing down of them.
--
-- Where nobody keeps order, the moons with the rarest deposits under
-- them are not lying idle: pirates hold each with a tower of their own
-- (a keep), batteries round it. A pilot who wants such a moon has to
-- take it, and it is taken as a pilot's own tower is lost
-- (Tactical/Raids), the other way about:
--   - The keep is a thing to shoot at, with a shield, armour and a
--     structure. Its batteries throw missiles at whoever comes in reach,
--     and under fire it calls for help: a pack arrives, and after a
--     while another.
--   - When its shield is down to a quarter it seals itself, for as many
--     hours as it has charges (Keeps.HOURS). Sealed, it cannot be
--     locked, and those who came to its help go; its batteries stand,
--     and can be destroyed while it holds out.
--   - It opens with its shield where it was. It has nothing to seal
--     with again until it has been resupplied, a day after
--     (Keeps.RESTOCK): the pilot who is back in that day finds it to be
--     brought down, and one who is not finds it whole again, its
--     batteries too.
--   - Destroyed, it leaves its bounty, and in its wreck what it had
--     drawn from the moon and a few sealing charges; its place is gone,
--     and the moon is anybody's to anchor a tower at. Until then nobody
--     anchors one there (Assets/Starbases).
--
-- A system's keeps are put up when the pilot first comes there (as its
-- sites are found: Tactical/Sites), and stay as they are left.
--
-- (Every figure is a first proposal: which moons, how strong, how long.)

local Constants = require("@lt/Core/Data/Constants")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Rng = require("@lt/Core/Kernel/Rng")
local Sites = require("@lt/Core/Tactical/Sites")
local Space = require("@lt/Core/Tactical/Space")
local Starbases = require("@lt/Core/Assets/Starbases")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local System = require("@lt/Core/Describe/System")

local Keeps = {}

export type Event = { [string]: any }

local HOUR = math.floor(3600 / Constants.TICK + 0.5)

-- The grade of deposit a moon has to have for pirates to hold it (the
-- rarest), and how far from the moon's middle the keep stands, in the
-- moon's radii.
Keeps.GRADE = 3
Keeps.OUT = 5
-- Its batteries: how many, and how far from it they stand, m.
Keeps.BATTERIES = 3
Keeps.RING = { 5000, 8000 }
-- The share of its shield at which it seals, and comes out with; the
-- hours it seals for; and the hours after it opens until it has charges
-- again.
Keeps.QUARTER = 0.25
Keeps.HOURS = 4
Keeps.RESTOCK = 24
-- Under fire it calls for help: when its shield is under this share,
-- no oftener than every so many seconds, and so many times before it
-- has to seal or fall.
Keeps.ALARM = 0.9
Keeps.CALL = 240
Keeps.CALLS = 2
-- What it has drawn from the moon, in units of the moon's material: at
-- least and at most. And the sealing charges found in its wreck.
Keeps.STOCK = { 1500, 4000 }
Keeps.CHARGES = 3

-- The keep at a moon, if pirates hold it.
function Keeps.At(state: State.State, moon: number): State.Keep?
  for _, id in state.keepIds do
    if state.keeps[id].moon == moon then
      return state.keeps[id]
    end
  end
  return nil
end

-- The keep a ship is, if it is one.
function Keeps.Of(state: State.State, ship: number): State.Keep?
  for _, id in state.keepIds do
    if state.keeps[id].core == ship then
      return state.keeps[id]
    end
  end
  return nil
end

function Keeps.Sealed(state: State.State, keep: State.Keep): boolean
  return keep.sealed ~= 0 and state.tick < keep.sealed
end

-- How many of a keep's batteries stand.
function Keeps.Batteries(state: State.State, keep: State.Keep): number
  local count = 0
  for _, id in state.pilotIds do
    local ball = state.balls[id]
    if state.pilots[id].home == keep.id and id ~= keep.core and ball and ball.maxVelocity == 0 then
      count += 1
    end
  end
  return count
end

-- A battery put up somewhere round a keep's place.
local function battery(state: State.State, place: System.Object, rng: Rng.Rng, turn: number)
  local out = Rng.Float(rng, Keeps.RING[1], Keeps.RING[2])
  Pirates.Spawn(state, Pirates.kindById.battery, Space.SystemOf(state, place.id), place.x + out * math.cos(turn),
    place.y + Rng.Float(rng, -800, 800), place.z + out * math.sin(turn), place.id)
end

-- Put a keep up at a moon, with its batteries; nil if the moon has a
-- tower already (the pirates', or a pilot's), or the system has no room
-- for another place.
function Keeps.Raise(state: State.State, moon: System.Object, events: { Event }): State.Keep?
  local system = Space.SystemOf(state, moon.id)
  local objects = Space.Describe(state, system).objects
  local taken = Keeps.At(state, moon.id) ~= nil or #objects + 4 >= Constants.STRUCTURE_ID_SPAN
  for _, object in objects do
    taken = taken or (object.kind == "station" and object.parent == moon.id and state.starbases[object.id] ~= nil)
  end
  if taken then
    return nil
  end
  local rng = Rng.For(state.historySeed, moon.id, 947)
  local angle = Rng.Float(rng, 0, 2 * math.pi)
  local place: System.Object = {
    id = system * Constants.STRUCTURE_ID_SPAN + #objects + 1, kind = "belt", name = `{moon.name} - Pirate Tower`,
    x = moon.x + moon.radius * Keeps.OUT * math.cos(angle), y = moon.y, z = moon.z + moon.radius * Keeps.OUT * math.sin(angle),
    radius = 0, seed = Rng.Int(rng, 2 ^ 31), parent = moon.id, site = 0, variety = "site.keep", to = 0,
  }
  place.site = place.id
  table.insert(objects, place)
  state.sites[place.id] = { id = place.id, system = system, kind = "keep", code = "", strength = 1, expires = 2 ^ 52, gone = false,
    depth = 0, led = false }
  table.insert(state.siteIds, place.id)
  local core = Pirates.Spawn(state, Pirates.kindById.keep, system, place.x, place.y, place.z, place.id)
  for index = 1, Keeps.BATTERIES do
    battery(state, place, rng, angle + (index + Rng.Float(rng, -0.2, 0.2)) * 2 * math.pi / Keeps.BATTERIES)
  end
  local keep: State.Keep = { id = place.id, system = system, moon = moon.id, core = core.id, sealed = 0, charges = Keeps.HOURS,
    restock = 0, called = 0, calls = 0 }
  state.keeps[place.id] = keep
  State.InsertId(state.keepIds, place.id)
  table.insert(events, { kind = "KeepSighted", site = place.id, system = system, moon = moon.id })
  return keep
end

-- Put a system's keeps up, the first time the pilot is there: one at
-- every moon of a lawless system with a deposit of the rarest grade.
function Keeps.Settle(state: State.State, system: number, events: { Event })
  if state.keepsSeen[system] then
    return
  end
  state.keepsSeen[system] = true
  if Galaxy.Band(state.galaxy.systems[system].security) ~= "lawless" then
    return
  end
  local moons: { System.Object } = {}
  for _, object in Space.Describe(state, system).objects do
    local deposit = if object.kind == "moon" then Starbases.Deposit(state, object.id) else nil
    if deposit and deposit.material.grade >= Keeps.GRADE then
      table.insert(moons, object)
    end
  end
  for _, moon in moons do
    Keeps.Raise(state, moon, events)
  end
end

-- Those who came to a keep's help go (its batteries stand).
local function withdraw(state: State.State, keep: State.Keep, events: { Event })
  for _, pilotId in table.clone(state.pilotIds) do
    local pilot = state.pilots[pilotId]
    local ball = state.balls[pilotId]
    local ship = state.ships[pilotId]
    if pilot.home == keep.id and ball and ship and pilotId ~= keep.core and ball.maxVelocity > 0 then
      Space.RemoveBall(state, ball)
      for _, item in Items.In(state, pilotId, nil) do
        Items.Take(state, item, item.quantity)
      end
      state.ships[pilotId] = nil
      State.RemoveId(state.shipIds, pilotId)
      state.pilots[pilotId] = nil
      State.RemoveId(state.pilotIds, pilotId)
      table.insert(events, { kind = "BallRemoved", ball = pilotId, reason = "left" })
    end
  end
end

-- A keep has been destroyed: its place is gone, the moon is free, and
-- what it had is in its wreck. ('ship' is what was destroyed, and
-- 'home' the place it kept: Tactical/Aftermath asks of every pirate.)
function Keeps.Fell(state: State.State, ship: number, home: number, events: { Event })
  local keep = state.keeps[home]
  if keep == nil or keep.core ~= ship then
    return
  end
  local place = Space.Object(state, keep.id)
  local moon = Space.Object(state, keep.moon)
  local deposit = Starbases.Deposit(state, keep.moon)
  -- (its wreck is the newest there is)
  local wreck = state.wrecks[state.wreckIds[#state.wreckIds] or 0]
  if wreck and wreck.system == keep.system and deposit then
    local rng = Rng.For(state.historySeed, keep.id, 953)
    Items.Add(state, deposit.material.id, Keeps.STOCK[1] + Rng.Int(rng, Keeps.STOCK[2] - Keeps.STOCK[1] + 1), wreck.id, "cargo")
    Items.Add(state, Structures.SEAL.id, Keeps.CHARGES, wreck.id, "cargo")
  end
  state.keeps[keep.id] = nil
  State.RemoveId(state.keepIds, keep.id)
  table.insert(events, { kind = "KeepLost", site = keep.id, system = keep.system, moon = keep.moon,
    name = if place then place.name else "the pirates' tower", moonName = if moon then moon.name else "the moon" })
  Sites.Release(state, keep.id, events)
end

-- Once a tick: the keeps of the system the pilot is in are put up if
-- they never were; and each keep seals when its shield is failing,
-- opens when its time is up, is resupplied a day after, and calls for
-- help under fire.
function Keeps.Step(state: State.State, events: { Event })
  local me = state.ships[state.player.ship]
  local mine = if me then state.balls[me.id] else nil
  if me then
    Keeps.Settle(state, if mine then mine.system else Space.SystemOf(state, me.docked), events)
  end
  for _, id in table.clone(state.keepIds) do
    local keep = state.keeps[id]
    local core = state.balls[keep.core]
    if core then
      local place = Space.Object(state, id)
      local name = if place then place.name else "The pirates' tower"
      if keep.sealed ~= 0 and state.tick >= keep.sealed then
        keep.sealed = 0
        keep.calls = 0
        core.vitals.shield = Keeps.QUARTER * core.vitals.shieldMax
        table.insert(events, { kind = "KeepOpened", site = id, system = keep.system, name = name })
      end
      local sealed = Keeps.Sealed(state, keep)
      if not sealed and keep.charges == 0 and keep.restock ~= 0 and state.tick >= keep.restock then
        -- (resupplied: whole again, with charges to seal with, and a
        -- battery for every one it lost)
        keep.charges, keep.restock, keep.calls = Keeps.HOURS, 0, 0
        core.vitals.shield, core.vitals.armor, core.vitals.hull = core.vitals.shieldMax, core.vitals.armorMax, core.vitals.hullMax
        if place then
          local rng = Rng.For(state.historySeed, id, state.tick, 949)
          for _ = Keeps.Batteries(state, keep) + 1, Keeps.BATTERIES do
            battery(state, place, rng, Rng.Float(rng, 0, 2 * math.pi))
          end
        end
        table.insert(events, { kind = "KeepRestocked", site = id, system = keep.system, name = name })
      end
      local share = core.vitals.shield / math.max(1, core.vitals.shieldMax)
      if not sealed and share <= Keeps.QUARTER and keep.charges > 0 then
        local hours = keep.charges
        keep.sealed = state.tick + hours * HOUR
        keep.charges = 0
        keep.restock = keep.sealed + Keeps.RESTOCK * HOUR
        core.vitals.shield = math.max(core.vitals.shield, Keeps.QUARTER * core.vitals.shieldMax)
        withdraw(state, keep, events)
        table.insert(events, { kind = "KeepSealed", site = id, system = keep.system, name = name, hours = hours, opens = keep.sealed })
      elseif not sealed and share < Keeps.ALARM and keep.calls < Keeps.CALLS and place
        and (keep.called == 0 or (state.tick - keep.called) * Constants.TICK >= Keeps.CALL)
        and mine and mine.system == keep.system and mine.grid == id and not state.peaceful then
        -- Under fire, with the pilot there: it calls, and they come.
        keep.called = state.tick
        keep.calls += 1
        Pirates.Arrive(state, keep.system, place, "lawless", false, events)
        table.insert(events, { kind = "KeepCalled", site = id, system = keep.system, name = name, call = keep.calls })
      end
    end
  end
end

return Keeps
