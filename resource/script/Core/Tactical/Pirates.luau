--!strict
-- Pirates: where they turn up, what they fly and how they fight.
--
-- They haunt asteroid belts, and in lawless space they wait at gates.
-- When the player's ship comes to a place that has seen none for a
-- while, a pack arrives some way off, closes in, and attacks. What
-- comes follows from how safe the system is (Describe/Galaxy): a scout
-- or two where order is kept, raiders and a destroyer where it is
-- thin, and cruisers, now and then a battleship, where there is none.
--
-- They fly their own hulls, the Unbound's (Data/Ships): other people's
-- ships cut down and bolted back together. A kind of pirate is a hull,
-- what it would like fitted (it takes as much of that as the hull has
-- room, power and hardpoints for), how far off it likes to fight, and
-- what killing it pays. The bounty is on the pilot, not the hull.
--
-- Each flies with the same orders a player gives (orbit, lock,
-- activate), so anything a pirate can do, a pilot can. They ignore
-- capsules. A pack left alone for a few minutes goes away.
--
-- (When the strategic layer arrives, how many come and where will follow
-- from pirate pressure in the system instead of these fixed rules.)

local Combat = require("@lt/Core/Tactical/Combat")
local Dogma = require("@lt/Core/Dogma")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Mend = require("@lt/Core/Tactical/Mend")
local Modules = require("@lt/Core/Data/Modules")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")

local Pirates = {}

export type Event = { [string]: any }

-- Ticks before a place that had pirates gets more.
local RESPAWN = 1200
-- Ticks a pack waits on an empty grid before leaving.
local PATIENCE = 300
-- How often a gate in lawless space has a pack waiting at it.
local CAMPED = 0.4

-- 'fit' is what it would like, in order: a module, and the charge for
-- it if it matters which (else the first there is of its kind and size).
export type Kind = {
  id: string, hull: string, name: string,
  range: number,      -- m: how far from its prey it likes to fight
  bounty: number,
  tags: number,       -- pirate tags in its wreck
  fit: { { string } },
}

local function times(count: number, module: string, charge: string?): { { string } }
  local entries: { { string } } = {}
  for _ = 1, count do
    table.insert(entries, if charge then { module, charge } else { module })
  end
  return entries
end

local function all(...: { { string } }): { { string } }
  local entries: { { string } } = {}
  for _, list in { ... } do
    for _, entry in list do
      table.insert(entries, entry)
    end
  end
  return entries
end

-- A scout is a raider's hull with one gun on it and nothing else: what
-- a new pilot in a Courier can beat. A raider carries a warp disruptor
-- and a destroyer a webifier (and each the other's, if it has the room):
-- away from where order is kept, a pack holds what it catches.
local KINDS: { Kind } = {
  { id = "scout", hull = "frigate.cutthroat", name = "Pirate Scout", range = 1500, bounty = 6000, tags = 1,
    fit = { { "autocannon.small", "ammo.fusion" } } },
  { id = "raider", hull = "frigate.cutthroat", name = "Pirate Raider", range = 2000, bounty = 15000, tags = 1,
    fit = all(times(3, "autocannon.small", "ammo.fusion"), times(1, "launcher.light"),
      { { "disruptor.warp" }, { "afterburner.1mn" }, { "armor.plate.200mm" }, { "damage.control" }, { "gyrostabilizer" },
        { "web.stasis" } }) },
  { id = "jackal", hull = "destroyer.jackal", name = "Pirate Jackal", range = 3000, bounty = 40000, tags = 2,
    fit = all(times(6, "autocannon.small", "ammo.fusion"), times(3, "launcher.light"),
      { { "web.stasis" }, { "afterburner.1mn" }, { "armor.plate.200mm" }, { "damage.control" }, { "gyrostabilizer" },
        { "disruptor.warp" }, { "armor.plate.200mm" } }) },
  { id = "marauder", hull = "cruiser.marauder", name = "Pirate Marauder", range = 6000, bounty = 120000, tags = 4,
    fit = all(times(5, "autocannon.medium"), times(3, "launcher.heavy"),
      { { "armor.plate.medium" }, { "damage.control" }, { "gyrostabilizer" }, { "gyrostabilizer" }, { "ballistic.control" },
        { "disruptor.warp" }, { "painter.target" }, { "shield.extender.medium" }, { "shield.extender.medium" } }) },
  { id = "ravager", hull = "battleship.ravager", name = "Pirate Ravager", range = 15000, bounty = 400000, tags = 10,
    fit = all(times(6, "artillery.large"), times(4, "launcher.cruise"),
      { { "armor.plate.large" }, { "damage.control" }, { "gyrostabilizer" }, { "armor.plate.large" }, { "shield.extender.large" } }) },
  -- Not one of the ladder: a mender has little to shoot with. It keeps
  -- the rest of its pack whole, and is the one to shoot first.
  { id = "mender", hull = "frigate.cutthroat", name = "Pirate Mender", range = 4500, bounty = 25000, tags = 1,
    fit = { { "remote.armor.small" }, { "remote.armor.small" }, { "autocannon.small", "ammo.fusion" }, { "afterburner.1mn" },
      { "armor.plate.200mm" }, { "damage.control" } } },
}

Pirates.kinds = KINDS
Pirates.kindById = {} :: { [string]: Kind }
for _, kind in KINDS do
  Pirates.kindById[kind.id] = kind
end
Pirates.SCOUT = Pirates.kindById["scout"]

-- What comes, by how safe the system is: each a pack, and its share of
-- the times one comes. (Where order is kept it is a scout, or two.)
local PACKS: { [string]: { { any } } } = {
  secure = { { 0.3, { "scout", "scout" } }, { 0.7, { "scout" } } },
  low = { { 0.5, { "raider", "raider" } }, { 0.3, { "jackal", "raider" } }, { 0.2, { "jackal", "raider", "raider" } } },
  lawless = { { 0.4, { "jackal", "jackal", "raider" } }, { 0.35, { "marauder", "mender", "raider" } },
    { 0.2, { "marauder", "jackal", "raider" } }, { 0.05, { "ravager", "mender", "jackal" } } },
}
Pirates.PACKS = PACKS

-- The charge a weapon is loaded with when nobody says: the first there
-- is of its family and size.
local function chargeFor(module: Modules.ModuleType): string?
  local weapon = module.weapon
  if weapon then
    for _, candidate in Modules.charges do
      if candidate.family == weapon.family and candidate.size == weapon.size then
        return candidate.id
      end
    end
  end
  return nil
end

-- What a kind of pirate ends up fitted with: as much of what it would
-- like, in order, as its hull takes. Each entry is a module and its
-- charge ("" for none).
function Pirates.Fit(kind: Kind): { { string } }
  local hull = Ships.byId[kind.hull]
  local types: { string } = {}
  local fitted: { { string } } = {}
  for _, entry in kind.fit do
    local module = Modules.byId[entry[1]]
    if module then
      table.insert(types, module.id)
      if Dogma.Check(hull, types) then
        table.insert(fitted, { module.id, entry[2] or chargeFor(module) or "" })
      else
        table.remove(types)
      end
    end
  end
  return fitted
end

-- Fit a ship as a kind is fitted, loaded, with more of what it fires in
-- its hold. (For anybody's ship that is fitted from a list: the
-- factions' patrols are, Tactical/Traffic.)
function Pirates.Equip(state: State.State, ship: State.Ship, kind: Kind)
  local carried: { [string]: boolean } = {}
  for _, entry in Pirates.Fit(kind) do
    local charge: string? = if entry[2] ~= "" then entry[2] else nil
    Items.Equip(state, ship.id, entry[1], charge)
    -- (and more of what it fires in the hold, a crystal aside, which lasts)
    local loaded = if charge then Modules.chargeById[charge] else nil
    if charge and loaded and loaded.family ~= "laser" and not carried[charge] then
      carried[charge] = true
      Items.Add(state, charge, if loaded.family == "missile" then 200 else 2000, ship.id, "cargo")
    end
  end
end

-- A pirate ship of a kind, in space at a point.
function Pirates.Spawn(state: State.State, kind: Kind, system: number, x: number, y: number, z: number, home: number): State.Ball
  local ship = Space.NewShip(state, kind.hull, kind.name, "pirates", 0)
  Pirates.Equip(state, ship, kind)
  local ball = Space.Launch(state, ship, system, x, y, z)
  state.pilots[ship.id] = { ship = ship.id, range = kind.range, prey = 0, home = home, alone = 0, bounty = kind.bounty, tags = kind.tags }
  table.insert(state.pilotIds, ship.id)
  return ball
end

local function pirateOnGrid(state: State.State, system: number, grid: number): boolean
  for _, id in state.pilotIds do
    local ball = state.balls[id]
    if ball and ball.system == system and ball.grid == grid then
      return true
    end
  end
  return false
end

-- Bring pirates to where the player is, if the place is due some: a
-- belt anywhere, or a gate in lawless space.
function Pirates.Populate(state: State.State, events: { Event })
  local me = state.balls[state.player.ship]
  if state.peaceful or me == nil or me.grid == 0 or Ships.byId[state.ships[me.id].type].class == "capsule" then
    return
  end
  local site = Space.Object(state, me.grid)
  if site == nil then
    return
  end
  local band: string = Galaxy.Band(state.galaxy.systems[me.system].security)
  local camp = site.kind == "gate" and band == "lawless"
  if site.kind ~= "belt" and not camp then
    return
  end
  -- A site (Tactical/Sites) is a belt to everything else. A den has a
  -- pack a kind of space tougher than the belts here bring, and nobody
  -- troubles a derelict where order is kept.
  local hidden = state.sites[site.id]
  if hidden and hidden.kind == "combat" then
    band = if band == "secure" then "low" else "lawless"
  elseif hidden and hidden.kind == "relic" and band == "secure" then
    return
  end
  local last = state.spawned[site.id]
  if (last and state.tick - last < RESPAWN) or pirateOnGrid(state, me.system, site.id) then
    return
  end
  local rng = Rng.For(state.historySeed, state.tick, site.id, 41)
  state.spawned[site.id] = state.tick
  -- (a gate is not always watched: ask again when it would be due more)
  if camp and not Rng.Chance(rng, CAMPED) then
    return
  end
  local roll = Rng.Next(rng)
  local packs = PACKS[band]
  local pack: { string } = packs[#packs][2]
  for _, entry in packs do
    roll -= entry[1]
    if roll < 0 then
      pack = entry[2]
      break
    end
  end
  for _, id in pack do
    -- Somewhere 25 to 35 km out from the middle of the place.
    local angle = Rng.Float(rng, 0, 2 * math.pi)
    local out = Rng.Float(rng, 25000, 35000)
    local ball = Pirates.Spawn(state, Pirates.kindById[id], me.system,
      site.x + out * math.cos(angle), site.y + Rng.Float(rng, -3000, 3000), site.z + out * math.sin(angle), site.id)
    table.insert(events, { kind = "BallAdded", ball = ball.id })
  end
  table.insert(events, { kind = "PiratesArrived", grid = site.id, count = #pack })
end

local function give(state: State.State, command: State.Command, events: { Event }): boolean
  local combat = command.kind == "LockTarget" or command.kind == "ActivateModule"
  if combat then
    if Combat.Validate(state, command) then
      Combat.Apply(state, command, events)
      return true
    end
  elseif Space.Validate(state, command) then
    Space.Apply(state, command, events)
    return true
  end
  return false
end

-- What a pirate here would go for: the nearest ship of the pilot's
-- side (their own, or a hired pilot's) that is worth shooting. One
-- pirate in three goes for a drone instead when any are out, and any
-- of them does when there is nothing else.
local function pickPrey(state: State.State, ball: State.Ball): State.Ball?
  local best: State.Ball?, least = nil, math.huge
  local drone: State.Ball?, droneLeast = nil, math.huge
  local function consider(other: State.Ball?, small: boolean)
    -- (what is cloaked is not there to be gone for)
    if other == nil or other.system ~= ball.system or other.grid ~= ball.grid or Combat.Cloaked(state, other.id) then
      return
    end
    local far = Space.Distance(other :: any, ball :: any)
    if small then
      if far < droneLeast then
        drone, droneLeast = other, far
      end
    elseif far < least and Ships.byId[state.ships[other.id].type].class ~= "capsule" then
      best, least = other, far
    end
  end
  consider(state.balls[state.player.ship], false)
  for _, id in state.fleetIds do
    consider(state.balls[state.fleet[id].ship], false)
  end
  for _, id in state.droneIds do
    if state.ships[id] and state.ships[id].owner == "player" then
      consider(state.balls[id], true)
    end
  end
  if drone and (best == nil or Rng.Chance(Rng.For(state.historySeed, ball.id, 53), 1 / 3)) then
    return drone
  end
  return best
end

-- Whoever on a ship's grid is after anybody of the pilot's side, the
-- nearest to that ship first: what its drones and its fleet go for
-- when nothing has been pointed out to them. 0 for nobody.
function Pirates.Hunting(state: State.State, near: State.Ball): number
  local best, least = 0, math.huge
  for _, id in state.pilotIds do
    local other = state.balls[id]
    local prey = state.ships[state.pilots[id].prey]
    if other and prey and prey.owner == "player" and other.system == near.system and other.grid == near.grid then
      local far = Space.Distance(other :: any, near :: any)
      if far < least then
        best, least = id, far
      end
    end
  end
  return best
end

-- Each pirate decides what to do this tick.
function Pirates.Think(state: State.State, events: { Event })
  local player = state.balls[state.player.ship]
  for _, id in table.clone(state.pilotIds) do
    local pilot = state.pilots[id]
    local ball = state.balls[id]
    if ball == nil or (ball.warp and ball.warp.stage == "warp") then
      continue
    end

    -- Prey: a ship of the pilot's side, if one is here and worth shooting.
    local prey: State.Ball? = state.balls[pilot.prey]
    if prey == nil or prey.system ~= ball.system or prey.grid ~= ball.grid or Combat.Cloaked(state, prey.id) then
      prey = pickPrey(state, ball)
      pilot.prey = if prey then prey.id else 0
    end

    -- Leave if nobody has been here for a while.
    local company = prey ~= nil or (player ~= nil and player.system == ball.system and player.grid == ball.grid)
    pilot.alone = if company then 0 else pilot.alone + 1
    if pilot.alone > PATIENCE then
      Space.RemoveBall(state, ball)
      for _, item in Items.In(state, id, nil) do
        Items.Take(state, item, item.quantity)
      end
      state.ships[id] = nil
      State.RemoveId(state.shipIds, id)
      state.pilots[id] = nil
      State.RemoveId(state.pilotIds, id)
      table.insert(events, { kind = "BallRemoved", ball = id, reason = "left" })
      continue
    end

    if prey == nil then
      if ball.mode ~= "stop" then
        give(state, { kind = "Stop", actor = id }, events)
      end
      continue
    end

    if not (ball.mode == "orbit" and ball.target == prey.id) then
      give(state, { kind = "Orbit", actor = id, target = prey.id, range = pilot.range }, events)
    end
    local locked = false
    local targeted = false
    for _, lock in ball.vitals.locks do
      if lock.target == prey.id then
        targeted = true
        locked = lock.locked
      end
    end
    if not targeted then
      give(state, { kind = "LockTarget", actor = id, target = prey.id }, events)
    end
    -- Everything it has for another ship: its guns, and what holds the
    -- prey where it is (each is refused until it is in reach). And what
    -- it has for its own side: a remote repairer goes on whoever of the
    -- pack is worst hurt (Tactical/Mend).
    local mends = false
    for _, item in Items.Fitted(state, id) do
      local module = Modules.byId[item.type]
      if module.hex and Modules.Mends(module) then
        mends = true
      elseif locked and (module.weapon or module.hex) then
        give(state, { kind = "ActivateModule", actor = id, item = item.id, target = prey.id }, events)
      end
    end
    if mends then
      local pack: { number } = {}
      for _, other in state.pilotIds do
        if state.ships[other] and state.ships[other].owner == state.ships[id].owner then
          table.insert(pack, other)
        end
      end
      Mend.Tend(state, ball, pack, events)
    end
  end
end

return Pirates
