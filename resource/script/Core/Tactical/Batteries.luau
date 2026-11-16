--!strict
-- Batteries: the guns of a station.
--
-- A station's gun and missile batteries (Data/Structures) fire on what
-- has no business on its grid: any pirate, and a pilot the patrols have
-- marked (Tactical/Traffic). A pilot's own starbase fires on pirates
-- and never on its owner, and only while it is lit. A battery does not
-- miss: it is a big gun on a still platform with nothing else to do.
--
-- A battery stands outside its station's field (Tactical/Fields: the
-- owner's ruling, 2026-11-14), where it can shoot and be shot at. It
-- is a thing in space as a ship is, of the class "works" (Data/Ships):
-- anybody outside the field can lock it and destroy it. One that is
-- destroyed fires no more, and is built again REBUILD later.
--
-- Only the station the pilot is at is looked at (their ship in space on
-- its grid, or docked in it), as with everything else that happens
-- where the pilot is not: its batteries are stood there when the pilot
-- comes (Batteries.Stand) and taken away when the pilot goes, whole
-- again when they are stood the next time. All that is kept of the rest
-- is which are down, and until when. Docked or in space, they fire on
-- what comes near. (Four of them in space cost a docked second next to
-- nothing: measured, 2026-11-14.)
--
-- A colony ship of the nomads has no field and its batteries are
-- aboard it: they fire from the ship, as they always did, and are
-- nothing to shoot at. A gate in space somebody holds is guarded the
-- same way, by sentry guns: they fire on pirates and on a marked pilot
-- at the gate.
--
-- (Not yet: sentries as things that can be shot at, a battery's own
-- range and tracking, a starbase's batteries waiting to come online.)

local Combat = require("@lt/Core/Tactical/Combat")
local Fields = require("@lt/Core/Tactical/Fields")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Stations = require("@lt/Core/Assets/Stations")
local Structures = require("@lt/Core/Data/Structures")
local System = require("@lt/Core/Describe/System")

local Batteries = {}

export type Event = { [string]: any }
export type Hit = { target: number, by: number, damage: { number } }

-- How far from the tower a battery reaches, m.
Batteries.RANGE = 45000
-- How long a destroyed battery is gone, ticks (two hours: mine).
Batteries.REBUILD = 7200
-- A battery's volley (EM, thermal, kinetic, explosive) and the ticks
-- between volleys: twenty points a second from a gun battery, fifteen
-- from a missile battery.
local GUN = { every = 3, damage = { 0, 15, 30, 15 } }
local MISSILE = { every = 6, damage = { 0, 0, 45, 45 } }

-- A people's tower's gun batteries fire its turret family (the owner,
-- 2026-11-16): a volley as big as a gun battery's, split between the
-- four kinds of damage as the family's small tech 1 charges split it,
-- taken together (the game's own charges: projectile and hybrid all
-- four alike, lasers EM and thermal). Then the tower's bonus on top
-- (Structures.TOWER_DAMAGE). A gate's sentries are nobody's people's,
-- and fire as a gun battery did.
local VOLLEY = 60
local FAMILY: { [string]: { number } } = {}
do
  local sums: { [string]: { number } } = {}
  for _, charge in Modules.charges do
    if charge.size == 1 and (charge.tech == nil or charge.tech == 1) then
      local sum = sums[charge.family] or { 0, 0, 0, 0 }
      for kind = 1, 4 do
        sum[kind] += charge.damage[kind] or 0
      end
      sums[charge.family] = sum
    end
  end
  for family, sum in sums do
    local all = sum[1] + sum[2] + sum[3] + sum[4]
    if all > 0 then
      FAMILY[family] = { VOLLEY * sum[1] / all, VOLLEY * sum[2] / all, VOLLEY * sum[3] / all, VOLLEY * sum[4] / all }
    end
  end
end

-- What a battery of a kind does from a tower: its beat, its volley, and
-- (for the scene) the gun it fires like.
type Battery = { every: number, damage: { number }, missile: boolean, look: string? }
-- (the large gun of each family a battery stands as, Game/View/Starbase's too)
Batteries.LOOKS = { projectile = "artillery.large", hybrid = "railgun.large", laser = "laser.pulse.large" }

local function armed(module: string, tower: Structures.Tower?): Battery?
  if module == "battery.missile" then
    local times = if tower then tower.missileBonus else 1
    local damage = table.clone(MISSILE.damage)
    for kind = 1, 4 do
      damage[kind] *= times
    end
    return { every = MISSILE.every, damage = damage, missile = true }
  elseif module == "battery.gun" then
    local mix = if tower then FAMILY[tower.gun] else nil
    if tower == nil or mix == nil then
      return { every = GUN.every, damage = table.clone(GUN.damage), missile = false }
    end
    local damage = {}
    for kind = 1, 4 do
      damage[kind] = mix[kind] * tower.gunBonus
    end
    return { every = GUN.every, damage = damage, missile = false, look = Batteries.LOOKS[tower.gun] }
  end
  return nil
end

-- What a battery of a kind does from a tower: for whoever says so (a sheet, a test).
function Batteries.Of(module: string, tower: string?): ({ number }?, number)
  local battery = armed(module, if tower then Structures.towerById[tower] else nil)
  return if battery then battery.damage else nil, if battery then battery.every else 0
end

-- The hull that stands for each kind of battery, and what is on it to
-- be seen (it fires as a battery does, above, and not as its fit would).
local STANDS: { [string]: { hull: string, name: string, fit: string, charge: string } } = {
  ["battery.gun"] = { hull = "works.battery.gun", name = "Gun Battery", fit = "autocannon.small", charge = "ammo.emp" },
  ["battery.missile"] = { hull = "works.battery.missile", name = "Missile Battery", fit = "launcher.light", charge = "missile.light.kinetic" },
}

-- What of a station's is a battery that stands outside it, in the
-- station's own order: nothing for a colony ship (its guns are aboard),
-- for a station with nothing for defence, or for a tower whose field
-- is down.
local function posted(state: State.State, station: System.Object?): { string }
  local kinds: { string } = {}
  if station == nil or station.kind ~= "station" or Fields.Of(state, station.id) == nil
    or not Stations.Has(state, station.id, "defence") then
    return kinds
  end
  local makeup = Stations.Makeup(state, station.id)
  if makeup then
    for _, module in makeup.modules do
      if STANDS[module] then
        table.insert(kinds, module)
      end
    end
  end
  return kinds
end

local function same(a: { string }, b: { string }): boolean
  if #a ~= #b then
    return false
  end
  for index, kind in a do
    if b[index] ~= kind then
      return false
    end
  end
  return true
end

-- Take a battery's ship out of the game (it is not destroyed: nobody is
-- there to see it).
local function remove(state: State.State, id: number, events: { Event })
  local ball = state.balls[id]
  if ball then
    Space.RemoveBall(state, ball)
    table.insert(events, { kind = "BallRemoved", ball = id, reason = "left" })
  end
  for _, item in Items.In(state, id, nil) do
    Items.Take(state, item, item.quantity)
  end
  if state.ships[id] then
    state.ships[id] = nil
    State.RemoveId(state.shipIds, id)
  end
end

-- Whether a battery of a station is down now.
local function down(state: State.State, station: number, index: number): boolean
  for _, lost in state.batteries.down do
    if lost.station == station and lost.index == index and state.tick < lost.back then
      return true
    end
  end
  return false
end

-- The batteries of the station the pilot is at, by the station's own
-- order: the ship that is each, 0 for one that is down. Nothing where
-- none stand.
function Batteries.Standing(state: State.State): { number }
  return state.batteries.balls
end

-- Stand the batteries of the station the pilot is at (in space there,
-- or docked in it), each tick before they fire: put there when the
-- pilot comes, taken away when they go
-- (or the station is one that has none any more), the destroyed ones
-- written down, and those whose time has come built again.
function Batteries.Stand(state: State.State, events: { Event })
  local record = state.batteries
  local me = state.balls[state.player.ship]
  local mine = state.ships[state.player.ship]
  local at = if me then me.grid elseif mine then mine.docked else 0
  -- (what a station of somebody else's has does not change: it is gone
  -- through when the pilot comes to it, and not again each second they
  -- are there. A pilot's own tower is, every tick: its modules come and
  -- go, and its field with its fuel.)
  if at == record.at and state.starbases[at] == nil and record.station == 0 then
    return
  end
  local station = if at ~= 0 then Space.Object(state, at) else nil
  local kinds: { string } = if at == record.at and state.starbases[at] == nil then record.kinds else posted(state, station)
  record.at = at
  local id = if station and #kinds > 0 then station.id else 0
  if record.station ~= id or not same(record.kinds, kinds) then
    for _, standing in record.balls do
      if standing ~= 0 then
        remove(state, standing, events)
      end
    end
    record.station, record.kinds, record.balls = id, kinds, {}
  end
  -- (what has been built again is forgotten)
  for index = #record.down, 1, -1 do
    if state.tick >= record.down[index].back then
      table.remove(record.down, index)
    end
  end
  if station == nil or id == 0 then
    return
  end
  local own = state.starbases[id] ~= nil
  for index, kind in kinds do
    local standing = record.balls[index]
    if standing and standing ~= 0 and state.balls[standing] == nil then
      -- (it was destroyed in the second that has just passed)
      table.insert(record.down, { station = id, index = index, back = state.tick + Batteries.REBUILD })
      record.balls[index] = 0
      table.insert(events, { kind = "BatteryLost", station = id, battery = index, own = own })
    elseif (standing == nil or standing == 0) and not down(state, id, index) then
      local stand = STANDS[kind]
      local ship = Space.NewShip(state, stand.hull, stand.name, if own then "starbase" else Stations.People(state, id), 0)
      for _ = 1, Ships.byId[stand.hull].highs do
        Items.Equip(state, ship.id, stand.fit, stand.charge)
      end
      local x, y, z = Structures.Post(station.radius, station.seed, index)
      local ball = Space.Launch(state, ship, Space.SystemOf(state, id), station.x + x, station.y + y, station.z + z)
      record.balls[index] = ball.id
      table.insert(events, { kind = "BallAdded", ball = ball.id })
    elseif standing == nil then
      record.balls[index] = 0
    end
  end
end

-- What the batteries of the station the pilot is at do this tick: the
-- hits they land, for Combat to apply with everybody else's.
function Batteries.Fire(state: State.State, events: { Event }): { Hit }
  local hits: { Hit } = {}
  local me = state.balls[state.player.ship]
  -- (docked in a station, the pilot is there: its batteries fire on
  -- what comes near, as they do with the pilot in space)
  local mine = state.ships[state.player.ship]
  local at = if me then me.grid elseif mine then mine.docked else 0
  local station = if at ~= 0 then Space.Object(state, at) else nil
  if station == nil or (me == nil and state.batteries.station ~= station.id) then
    return hits
  end
  local system = Space.SystemOf(state, station.id)
  -- A gate in space somebody holds has sentry guns: three where order
  -- is kept, two where it is thin. (Nobody guards a gate that is nobody's.)
  local sentries = 0
  if station.kind == "gate" then
    local node = state.galaxy.systems[system]
    -- (a stargate's: the gate of a pirate camp is nobody's to guard)
    sentries = if Galaxy.Keeper(node) == "" or station.variety == "passage" then 0 elseif Galaxy.Band(node.security) == "secure" then 3 else 2
    if sentries == 0 then
      return hits
    end
  elseif station.kind ~= "station" then
    return hits
  end
  -- (what stands outside a field fires from where it stands, while it
  -- stands. A colony ship's are aboard, and a gate's are its own.)
  local record = state.batteries
  local stands = sentries == 0 and record.station == station.id
  if sentries == 0 and not stands and not Stations.Has(state, station.id, "defence") then
    return hits
  end
  local field = Fields.Of(state, station.id)
  local own = state.starbases[station.id] ~= nil
  local marked = not own and state.tick < state.player.marked
  local targets: { number } = {}
  for _, id in state.ballIds do
    local ball = state.balls[id]
    local ship = state.ships[id]
    if ball.system == system and ball.grid == station.id and ship and Ships.byId[ship.type].class ~= "capsule"
      and (ship.owner == "pirates" or (marked and me ~= nil and id == me.id))
      and not (ball.warp and ball.warp.stage == "warp") and not Combat.Cloaked(state, id)
      and Space.Distance(ball :: any, station :: any) <= Batteries.RANGE
      -- (nothing fires across a field: whoever is in it is out of their reach)
      and not (stands and field ~= nil and Fields.Within(field, ball :: any)) then
      table.insert(targets, id)
    end
  end
  if #targets == 0 then
    return hits
  end
  local makeup = if sentries > 0 then nil else Stations.Makeup(state, station.id)
  local modules: { string } = if sentries > 0 then table.create(sentries, "battery.gun")
    elseif stands then record.kinds
    else (makeup :: any).modules
  -- (whose people's tower it is: what its batteries fire, and how hard)
  local tower = if makeup and makeup.tower then Structures.towerById[makeup.tower] else nil
  local index = 0
  for _, module in modules do
    local battery = armed(module, tower)
    if battery then
      index += 1
      -- (one that is down fires nothing)
      local from = if stands then record.balls[index] or 0 else station.id
      if from == 0 or (stands and state.balls[from] == nil) then
        continue
      end
      -- (each on its own beat, and each at its own one of them, in turn)
      if (state.tick + index * 2) % battery.every == 0 then
        local target = targets[(index - 1) % #targets + 1]
        table.insert(hits, { target = target, by = from, damage = table.clone(battery.damage) })
        table.insert(events, { kind = "BatteryFired", station = station.id, battery = index, from = from, to = target,
          missile = battery.missile, look = battery.look })
      end
    end
  end
  return hits
end

return Batteries
