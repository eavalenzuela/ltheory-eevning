--!strict
-- Raids: pirates come for a pilot's tower.
--
-- A tower where order is kept is left alone. One in low security or in
-- lawless space is raided now and then: the less safe the space, the
-- oftener and the harder. What stands against a raid is what the tower
-- has to shoot with (each gun or missile battery that is online) and
-- whoever of the pilot's hired pilots is holding the place (set to
-- patrol there, and in space on its grid).
--
-- With the pilot there (in space on the tower's grid, or moored at it)
-- a raid is a pack that arrives, and is fought as any fight is: the
-- batteries fire (Tactical/Batteries), the patrol fights, the pilot
-- may. With the pilot somewhere else it is settled at once, strength
-- against strength:
--   - beaten off, if the defence is as strong as the raid;
--   - and if it is not, the raiders get at what the drill has brought
--     up. They carry off a share of the moon material in the tower's
--     hangar, the bigger the more they outmatch the defence (never all
--     of it), and the drill is out for an hour.
-- Nothing else of the pilot's is touched, and the tower stands: such a
-- raid is after what can be carried, and what a drill brings up is
-- lying in the open.
--
-- Where nobody keeps order at all, a raid the defence does not match is
-- no robbery: it is a siege. They have come to bring the tower down.
--   - A tower has a shield, armour and a structure (Data/Structures),
--     and a thing at its heart that stands for it where it is shot at
--     (its core: Assets/Starbases). With the pilot there the pack
--     arrives and most of it goes for the core; it is fought as any
--     fight is.
--   - When its shield is down to a quarter (Raids.QUARTER), a lit tower
--     with sealing charges aboard seals itself: an hour for each charge.
--     Sealed, nothing can touch it and it does nothing; those who came
--     go away. They are back the moment it opens, with its shield where
--     it was: that is the pilot's warning, and the time they have to be
--     there with whatever they can bring.
--   - With the pilot somewhere else it is settled at once: the first
--     time, the shield is brought to the quarter and the tower seals,
--     if it can; and when they come back, a defence that matches them
--     sees them off, and one that does not loses the tower.
--   - A tower with no charge to burn does not seal. One whose core is
--     destroyed is lost: the tower, what was anchored on it and what
--     was in its hangars, all of it. A ship moored there is put out
--     into space, and one left there is found at the home station.
-- A tower that has seen a siege off mends: its shield by itself, and
-- its armour and structure a twentieth an hour while it is lit.
--
-- (Every figure is a first proposal.)

local Constants = require("@lt/Core/Data/Constants")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Hulks = require("@lt/Core/Assets/Hulks")
local Items = require("@lt/Core/Assets/Items")
local Moons = require("@lt/Core/Data/Moons")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Reactions = require("@lt/Core/Data/Reactions")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local Starbases = require("@lt/Core/Assets/Starbases")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local Wars = require("@lt/Core/Strategic/Wars")

local Raids = {}

export type Event = { [string]: any }

local HOUR = math.floor(3600 / Constants.TICK + 0.5)

-- Hours from one raid to the next, at least and at most, by how safe
-- the tower's system is. (None where order is kept.)
Raids.EVERY = { low = { 8, 14 }, lawless = { 3, 6 } } :: { [string]: { number } }
-- How many times as often a station is raided that holds a Wormhole
-- Bridge open. (Mine.)
Raids.BRIDGED = 2
-- How strong a raid is, at least and at most.
Raids.STRENGTH = { low = { 2, 4 }, lawless = { 4, 9 } } :: { [string]: { number } }
-- What a battery online is worth against one, and a hired pilot's ship
-- holding the place, by its class.
Raids.BATTERY = 2
Raids.PATROL = { frigate = 1, destroyer = 2, cruiser = 4, attackbattlecruiser = 5, battlecruiser = 6, battleship = 8,
  carrier = 20, siegedreadnought = 16, dreadnought = 24, supercarrier = 40, ultracapital = 100 } :: { [string]: number }
-- The most of what is there that raiders carry off, and how long the
-- drill is out after they have been (seconds).
Raids.MOST = 0.8
Raids.DOWN = 3600
-- How long a siege at its strongest (Raids.STRENGTH's most, 9) would be
-- bringing a whole tower down, with the pilot there to see it: its
-- shield, its armour and its structure, s. Weaker sieges are the longer,
-- as their strength is less. Since 2026-11-20, when towers took the
-- reference's shield, armour and structure (the owner's "Reference
-- as-is"), what a pack shoots does next to nothing to one, and a siege
-- is its bombardment: as long as any of those who have come are on the
-- tower's grid (Raids.Bombard). (Mine: a shield to its sealing quarter
-- in about a quarter of an hour at the strongest.)
Raids.SIEGE_TIME = 1800
Raids.STRONGEST = 9

-- The share of its shield at which a tower seals itself, and comes out
-- with; and the share of its armour and structure a lit tower mends in
-- an hour.
Raids.QUARTER = 0.25
Raids.MEND = 0.05

-- How safe a starbase's system is: "secure", "low" or "lawless". A
-- system the pilot has claimed is raided as the open space it was (the
-- owner, 2026-11-22: claimed systems still get raids): the order kept
-- in it is for those who live and pass there, not a wall round a tower.
function Raids.Band(state: State.State, starbase: State.Starbase): string
  local node = state.galaxy.systems[Space.SystemOf(state, starbase.id)]
  if node.owner == Wars.PILOT then
    return "lawless"
  end
  return Galaxy.Band(Galaxy.Order(node))
end

-- How much harder a raid is in uncharted space, for each depth past the
-- first (the owner, 2026-11-22: raid strength grows with depth; mine:
-- half as strong again at the third, twice at the fifth). The Drowned
-- are those who come at the fourth and fifth (Tactical/Pirates).
Raids.DEPTH = 0.25
function Raids.Deepened(state: State.State, starbase: State.Starbase): number
  local depth = state.galaxy.systems[Space.SystemOf(state, starbase.id)].depth or 0
  return 1 + Raids.DEPTH * math.max(0, depth - 1)
end

-- What a starbase has against a raid: its strength in all, how many
-- batteries of it are online, and how many hired pilots hold the place.
function Raids.Defence(state: State.State, starbase: State.Starbase): (number, number, number)
  local batteries, patrol, strength = 0, 0, 0
  if Starbases.Lit(state, starbase) then
    -- (a citadel has no batteries: its defence module mounts weapons on its
    -- hardpoints, and its shield modules hold. Counted as batteries: half a
    -- battery a medium hardpoint, one a large, two an XL; one a shield
    -- module. The weights are mine, 2026-11-22: a citadel's raids were
    -- reckoned as a tower's, and it had no defence at all)
    local tower = Structures.towerById[starbase.tower]
    local points = if tower.citadel then Structures.CITADEL_HARDPOINTS[tower.size] else nil
    for _, module in starbase.modules do
      local service = Structures.moduleById[module.type].service
      if state.tick >= module.ready then
        if service == "defence" then
          batteries += 1
          strength += Raids.BATTERY
        elseif service == "weapons" and points then
          local worth = 0.5 * points.medium + points.large + 2 * points.xl
          batteries += math.floor(worth)
          strength += Raids.BATTERY * worth
        elseif service == "shield" then
          batteries += 1
          strength += Raids.BATTERY
        end
      end
    end
  end
  for _, id in state.fleetIds do
    local wing = state.fleet[id]
    local ship = state.ships[wing.ship]
    local ball = if ship then state.balls[ship.id] else nil
    if wing.order == "patrol" and wing.post == starbase.id and ship and ball and ball.grid == starbase.id
      and ball.system == Space.SystemOf(state, starbase.id) then
      local worth = Raids.PATROL[Ships.byId[ship.type].class] or 0
      if worth > 0 then
        patrol += 1
        strength += worth
      end
    end
  end
  return strength, batteries, patrol
end

-- When the next raid on a starbase is due, from now: the tick. (0 for
-- one that is left alone.)
local function due(state: State.State, starbase: State.Starbase): number
  local every = Raids.EVERY[Raids.Band(state, starbase)]
  if every == nil then
    return 0
  end
  local rng = Rng.For(state.historySeed, starbase.id, starbase.raids, 811)
  -- (a station with a Wormhole Bridge open is found the oftener: anybody
  -- may come through it, the owner's 2026-11-22. Tactical/Wormholes)
  local hole = if starbase.hole then state.wormholes[starbase.hole] else nil
  local sooner = if hole and hole.bridge then Raids.BRIDGED else 1
  return state.tick + math.floor(Rng.Float(rng, every[1], every[2]) * HOUR / sooner)
end

-- Whether the pilot is at a starbase: moored there, or in space on its grid.
local function present(state: State.State, starbase: State.Starbase): boolean
  local ship = state.ships[state.player.ship]
  local ball = state.balls[state.player.ship]
  if ship and ship.docked == starbase.id then
    return true
  end
  return ball ~= nil and ball.grid == starbase.id and ball.system == Space.SystemOf(state, starbase.id)
end

-- Those who came for a starbase go: there is nothing for them to shoot at.
local function withdraw(state: State.State, id: number, events: { Event })
  for _, pilotId in table.clone(state.pilotIds) do
    local pilot = state.pilots[pilotId]
    local ball = state.balls[pilotId]
    if pilot.home == id and ball then
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

-- A tower seals itself, if it can: lit, with a charge to burn. An hour
-- for each charge it has; those who came for it go, and are back when
-- it opens. True if it did.
function Raids.Seal(state: State.State, starbase: State.Starbase, events: { Event }): boolean
  if starbase.charges <= 0 or not Starbases.Lit(state, starbase) then
    return false
  end
  local hours = starbase.charges
  starbase.sealed = state.tick + hours * HOUR
  starbase.charges = 0
  local core = state.balls[starbase.core]
  if core then
    core.vitals.shield = math.max(core.vitals.shield, Raids.QUARTER * core.vitals.shieldMax)
  end
  withdraw(state, starbase.id, events)
  table.insert(events, { kind = "TowerSealed", station = starbase.id, hours = hours, opens = starbase.sealed, strength = starbase.siege })
  return true
end

-- A tower is lost: brought down, with what was anchored on it and what
-- was in its hangars. A ship of the pilot's moored there is put out
-- into space where it was; any other of theirs is found at the home
-- station.
function Raids.Lose(state: State.State, starbase: State.Starbase, events: { Event })
  local id = starbase.id
  local object = Space.Object(state, id)
  local name = if object then object.name else "the tower"
  Space.Rehome(state, id)
  local mine = state.ships[state.player.ship]
  if mine and mine.docked == id then
    Space.Apply(state, { kind = "Undock", actor = mine.id }, events)
  end
  for _, shipId in state.shipIds do
    local ship = state.ships[shipId]
    if ship.docked == id then
      ship.docked = state.player.home
    end
  end
  -- (a citadel leaves its hulk, with half of what was stored in it:
  -- Assets/Hulks. What is left here is lost.)
  local stored = #Items.Stored(state, id)
  local hulk = Hulks.Leave(state, starbase, events)
  local lost = if hulk then math.max(0, stored - #Items.In(state, hulk.id, "cargo")) else 0
  for _, item in Items.Stored(state, id) do
    lost += 1
    Items.Take(state, item, item.quantity)
  end
  for _, jobId in table.clone(state.jobIds) do
    if state.jobs[jobId].station == id then
      state.jobs[jobId] = nil
      State.RemoveId(state.jobIds, jobId)
    end
  end
  withdraw(state, id, events)
  local modules = #starbase.modules
  Starbases.Remove(state, id, events)
  if hulk then
    Hulks.Stand(state, hulk, id)
  end
  table.insert(events, { kind = "TowerLost", station = id, name = name, tower = starbase.tower, modules = modules, stacks = lost,
    hulk = if hulk then hulk.id else nil })
end

-- A ship has been destroyed: if it was what stands for a tower under
-- fire, the tower is lost.
function Raids.CoreLost(state: State.State, ship: number, events: { Event })
  local starbase = Starbases.OfCore(state, ship)
  if starbase then
    starbase.core = 0
    Raids.Lose(state, starbase, events)
  end
end

-- A siege's bombardment, this second, of each tower that is under one
-- with the pilot there (Raids.SIEGE_TIME): so much of all that holds it
-- up, by the siege's strength, from the first of those who came that is
-- on its grid, in every kind of damage alike. Nothing while it is sealed,
-- or while none of them is there.
export type Hit = { target: number, by: number, damage: { number } }
function Raids.Bombard(state: State.State): { Hit }
  local hits: { Hit } = {}
  for _, id in state.starbaseIds do
    local starbase = state.starbases[id]
    local core = state.balls[starbase.core]
    if starbase.siege > 0 and core and not Starbases.Sealed(state, starbase) then
      local by = 0
      for _, other in state.ballIds do
        local ball = state.balls[other]
        local ship = state.ships[other]
        if by == 0 and ball and ship and ship.owner == "pirates" and ball.system == core.system and ball.grid == core.grid then
          by = other
        end
      end
      if by ~= 0 then
        local v = core.vitals
        local whole = v.shieldMax + v.armorMax + v.hullMax
        local each = whole / Raids.SIEGE_TIME * Constants.TICK * math.min(1, starbase.siege / Raids.STRONGEST) / 4
        table.insert(hits, { target = core.id, by = by, damage = { each, each, each, each } })
      end
    end
  end
  return hits
end

-- Whether a starbase is under siege: somebody has come to bring it
-- down, and is there or will be back.
function Raids.Besieged(state: State.State, starbase: State.Starbase): boolean
  return starbase.siege > 0
end

-- Once a tick: a tower that was sealed opens; one whose shield is failing
-- seals; a raid that is due comes; and a lit tower mends.
function Raids.Step(state: State.State, events: { Event })
  for _, id in table.clone(state.starbaseIds) do
    local starbase = state.starbases[id]
    local band = Raids.Band(state, starbase)
    local ranges = Raids.STRENGTH[band]
    local core = state.balls[starbase.core]
    -- Sealed, and its time is up: it opens, with its shield where it
    -- was, and those who came for it are back.
    if starbase.sealed ~= 0 and state.tick >= starbase.sealed then
      starbase.sealed = 0
      if core then
        core.vitals.shield = Raids.QUARTER * core.vitals.shieldMax
      end
      table.insert(events, { kind = "TowerOpened", station = id, siege = starbase.siege > 0 })
      if starbase.siege > 0 then
        starbase.raid = state.tick
      end
    end
    local sealed = Starbases.Sealed(state, starbase)
    -- Under fire, with its shield down to the quarter: it seals, if it can.
    if core and not sealed and core.vitals.shield <= Raids.QUARTER * core.vitals.shieldMax and starbase.siege > 0 then
      sealed = Raids.Seal(state, starbase, events)
    end
    -- (and a lit tower mends: a twentieth of its armour and structure an hour)
    if core and Starbases.Lit(state, starbase) and (state.tick + id) % HOUR == 0 then
      core.vitals.armor = math.min(core.vitals.armorMax, core.vitals.armor + Raids.MEND * core.vitals.armorMax)
      core.vitals.hull = math.min(core.vitals.hullMax, core.vitals.hull + Raids.MEND * core.vitals.hullMax)
    end
    if sealed then
      -- (nobody comes for a sealed tower: there is nothing to be had)
    elseif (ranges == nil and starbase.siege == 0) or not Starbases.Anchored(state, starbase) then
      starbase.raid = 0
    elseif starbase.raid == 0 then
      starbase.raid = due(state, starbase)
    elseif state.tick >= starbase.raid and not state.peaceful then
      local rng = Rng.For(state.historySeed, starbase.id, starbase.raids, 823)
      -- (those who were sent away by its sealing are the same who come back)
      local back = starbase.siege > 0
      local strength = if back or ranges == nil then starbase.siege
        else math.floor((ranges[1] + Rng.Int(rng, ranges[2] - ranges[1] + 1)) * Raids.Deepened(state, starbase) + 0.5)
      local defence = Raids.Defence(state, starbase)
      local station = Space.Object(state, id)
      -- Where nobody keeps order, a raid the defence does not match is
      -- a siege: they have come for the tower itself.
      local siege = back or (band == "lawless" and defence < strength and core ~= nil)
      local here = present(state, starbase) and station ~= nil
      starbase.raids += 1
      starbase.raid = due(state, starbase)
      if siege and here and station then
        -- The pilot is there: they come, and it is fought. Most of them
        -- go for the tower (Tactical/Pirates).
        starbase.siege = strength
        Pirates.Arrive(state, Space.SystemOf(state, id), station, band, false, events)
        table.insert(events, { kind = "TowerRaided", station = id, outcome = "siege", strength = strength, defence = defence, taken = 0,
          back = back })
      elseif siege and back then
        -- They are back, and nobody is there but what the tower has.
        starbase.siege = 0
        if defence >= strength then
          table.insert(events, { kind = "TowerRaided", station = id, outcome = "beaten", strength = strength, defence = defence, taken = 0,
            back = true })
        else
          table.insert(events, { kind = "TowerRaided", station = id, outcome = "lost", strength = strength, defence = defence, taken = 0,
            back = true })
          Raids.Lose(state, starbase, events)
        end
      elseif siege then
        -- The first time, with nobody there: its shield is brought to
        -- the quarter, and it seals if it can. One that cannot is lost.
        starbase.siege = strength
        table.insert(events, { kind = "TowerRaided", station = id, outcome = "siege", strength = strength, defence = defence, taken = 0,
          back = false })
        if core then
          core.vitals.shield = Raids.QUARTER * core.vitals.shieldMax
        end
        if not Raids.Seal(state, starbase, events) then
          starbase.siege = 0
          table.insert(events, { kind = "TowerRaided", station = id, outcome = "lost", strength = strength, defence = defence, taken = 0,
            back = false })
          Raids.Lose(state, starbase, events)
        end
      elseif here and station then
        -- The pilot is there: they come, and it is fought.
        Pirates.Arrive(state, Space.SystemOf(state, id), station, band, false, events)
        table.insert(events, { kind = "TowerRaided", station = id, outcome = "fought", strength = strength, defence = defence, taken = 0 })
      elseif defence >= strength then
        table.insert(events, { kind = "TowerRaided", station = id, outcome = "beaten", strength = strength, defence = defence, taken = 0 })
      else
        -- They get in at what the drill has brought up, and the drill.
        local share = math.min(Raids.MOST, (strength - defence) / strength)
        local taken, type = 0, ""
        -- (out of the pilot's hangar there and the corporation's alike)
        for _, item in Items.Stored(state, id) do
          -- (and at what its reactor has made of that)
          if Moons.byId[item.type] or Reactions.byId[item.type] then
            local units = math.floor(item.quantity * share)
            if units > 0 then
              taken += units
              type = item.type
              Items.Take(state, item, units)
            end
          end
        end
        for _, module in starbase.modules do
          if module.type == Structures.DRILL then
            module.ready = math.max(module.ready, state.tick + math.ceil(Raids.DOWN / Constants.TICK))
          end
        end
        starbase.robbed += taken
        table.insert(events, { kind = "TowerRaided", station = id, outcome = "robbed", strength = strength, defence = defence,
          taken = taken, type = type })
      end
    elseif state.tick >= starbase.raid then
      -- (a game with no pirates in it has no raids: ask again later)
      starbase.raids += 1
      starbase.raid = due(state, starbase)
    end
    -- A siege that was fought is over when nobody of it is left and the
    -- tower is not sealed: they have been seen off. (Not in the moment
    -- before they come, or come back.)
    local coming = starbase.raid ~= 0 and state.tick >= starbase.raid
    if state.starbases[id] and starbase.siege > 0 and not Starbases.Sealed(state, starbase) and not coming
      and state.tick > (state.spawned[id] or 0) + 2 then
      local about = false
      for _, pilotId in state.pilotIds do
        about = about or (state.pilots[pilotId].home == id and state.balls[pilotId] ~= nil)
      end
      if not about then
        starbase.siege = 0
        table.insert(events, { kind = "SiegeBroken", station = id })
      end
    end
  end
end

return Raids
