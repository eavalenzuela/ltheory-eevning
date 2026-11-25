--!strict
-- Items: where everything a pilot owns is, and the orders that move it
-- (fit, unfit, load, move between hangar and cargo).
--
-- An item is a stack of one type in one place: a station's hangar (the
-- pilot's own, or their corporation's there: "corporate"), a ship's
-- cargo hold, its drone bay, its ore hold if it has one (a capital
-- industrial's: ore and gas and nothing else), or a slot in one of a
-- ship's racks. Loose stacks of
-- the same type in the same place merge. A fitted module is always a
-- stack of one. A weapon's loaded charge is recorded on the weapon.
--
-- Fitting happens docked: the ship and the item must be at the same
-- station.

local Attributes = require("@lt/Core/Attributes")
local Corporation = require("@lt/Core/Assets/Corporation")
local Deployables = require("@lt/Core/Data/Deployables")
local DroneKinds = require("@lt/Core/Data/Drones")
local Factions = require("@lt/Core/Data/Factions")
local Modules = require("@lt/Core/Data/Modules")
local Ores = require("@lt/Core/Data/Ores")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")
local State = require("@lt/Core/Kernel/State")
local Types = require("@lt/Core/Data/Types")

local Items = {}

export type Event = { [string]: any }

local RACKS = { "high", "mid", "low" }

-- ---------------------------------------------------------------------
-- Looking

-- The items held by 'holder', optionally only those in one place, in id
-- order.
function Items.In(state: State.State, holder: number, place: string?): { State.Item }
  local found = {}
  for _, id in state.itemIds do
    local item = state.items[id]
    if item.holder == holder and (place == nil or item.place == place) then
      table.insert(found, item)
    end
  end
  return found
end

-- Whether a place is one of the two a station keeps things in for a
-- pilot: their own hangar, or their corporation's.
function Items.IsStore(place: string): boolean
  return place == "hangar" or place == "corporate"
end

-- What a station keeps for a pilot, in both: in id order.
function Items.Stored(state: State.State, station: number): { State.Item }
  local found = {}
  for _, id in state.itemIds do
    local item = state.items[id]
    if item.holder == station and Items.IsStore(item.place) then
      table.insert(found, item)
    end
  end
  return found
end

-- A ship's fitted modules, rack by rack (high, mid, low), slot by slot.
function Items.Fitted(state: State.State, ship: number): { State.Item }
  local found = {}
  for _, id in state.itemIds do
    local item = state.items[id]
    if item.holder == ship and item.slot > 0 then
      table.insert(found, item)
    end
  end
  local rank = { high = 1, mid = 2, low = 3, rig = 4 }
  table.sort(found, function(a: State.Item, b: State.Item): boolean
    local ra, rb = rank[a.place :: "high"], rank[b.place :: "high"]
    if ra ~= rb then
      return ra < rb
    end
    return a.slot < b.slot
  end)
  return found
end

-- The fit as the attribute engine wants it. 'running' says which module
-- items are switched on, by item id.
function Items.Fit(state: State.State, ship: number, running: { [number]: boolean }?): { Attributes.Fitted }
  local fit = {}
  for _, item in Items.Fitted(state, ship) do
    table.insert(fit, { type = item.type, running = running ~= nil and running[item.id] == true, adapt = item.adapt })
  end
  -- (and with it what the pilot has in their own head, for a ship they
  -- fly themselves: Data/Implants)
  local record = state.ships[ship]
  if record and record.owner == "player" and record.pilot == 0 and Ships.byId[record.type].class ~= "drone" then
    for _, implant in state.implants do
      table.insert(fit, { type = implant, running = false })
    end
    -- (and whatever boosters are at work on them: Data/Boosters)
    for _, boosted in state.boosters do
      table.insert(fit, { type = boosted.type, running = false, spared = not boosted.wrong })
    end
  end
  return fit
end

-- What a hired pilot knows: every skill at the one level.
local HIRED: { Attributes.Levels } = {}
for level = 1, Skills.MAX_LEVEL do
  HIRED[level] = {}
  for _, skill in Skills.list do
    HIRED[level][skill.id] = level
  end
end
Items.HIRED = HIRED

-- How well the pilots of those who are not the player know every skill
-- (the owner, 2026-11-18, asked whether the world's pilots should have
-- skill levels by how tough they are: "yes"): a pirate or a trader on
-- the lanes the first level, an empire's pilot or a corporation's
-- member the third, the Drowned the fourth. A ship's own 'skill' says
-- otherwise where its spawning does: a pirate veteran the third, a
-- captain the fourth, an officer by name the fifth. What nobody flies
-- (a tower, a battery) knows nothing. (The levels are mine.)
Items.NPC_LEVEL = { pirates = 1, civilian = 1, member = 3, faction = 3, drowned = 4 }

-- The skills that bear on a ship: the player's, if it is theirs; a
-- hired pilot's, if one flies it (Tactical/Fleet); its pilot's, by who
-- they are, otherwise.
function Items.Levels(state: State.State, ship: number): Attributes.Levels?
  local record = state.ships[ship]
  if record.owner == "player" then
    local wing = state.fleet[record.pilot]
    -- (one of the player's own characters flies with their own skills, not every one at the fifth)
    local member = if wing and state.membership then state.membership.members[wing.member] else nil
    if member and member.alt and member.skills then
      return member.skills
    end
    return if wing then HIRED[wing.skill] else state.skills
  end
  local level = record.skill or Items.NPC_LEVEL[record.owner]
    or (if Factions.byId[record.owner] then Items.NPC_LEVEL.faction else nil)
  return if level and level > 0 then HIRED[math.min(level, Skills.MAX_LEVEL)] else nil
end

-- A ship's attributes with its present fit, nothing running.
function Items.ShipStats(state: State.State, ship: number): Attributes.Stats
  return Attributes.Ship(Ships.byId[state.ships[ship].type], Items.Fit(state, ship, nil), Items.Levels(state, ship))
end

-- What a ship's weapons come to on paper with what is loaded in them:
-- damage a volley and damage a second, the second split by kind (EM,
-- thermal, kinetic, explosive), and how far the longest of them reaches
-- (a turret's optimal range and falloff, a missile's flight).
export type Offence = { volley: number, dps: number, kinds: { number }, range: number }

-- How far a weapon reaches with a charge: a turret's optimal range and
-- falloff, a missile's flight (5% longer a level of Long Burn:
-- Tactical/Combat's LONG_BURN).
local function reach(weapon: Modules.Weapon, charge: Modules.ChargeType, levels: Attributes.Levels?): number
  return if weapon.optimal > 0 then weapon.optimal * charge.rangeMultiplier + weapon.falloff
    else charge.velocity * (if weapon.volley then weapon.volley.speed / (weapon.volley.stretch or 1) else 1) * charge.flightTime
      * (weapon.flight or 1)
      * (1 + 0.05 * Skills.Level(levels, "long.burn"))
end

-- How far one fitted weapon reaches with what is loaded in it, with the
-- ship's fit and its pilot's skills (the rack's tip: Game/UI/Hud). Nil
-- for what is not a weapon or is empty.
function Items.Reach(state: State.State, ship: number, item: State.Item): number?
  if not Modules.byId[item.type].weapon or item.charge == "" then
    return nil
  end
  local levels = Items.Levels(state, ship)
  local weapon = Attributes.Weapon(Items.Fit(state, ship, nil), item.type, levels, Ships.byId[state.ships[ship].type])
  return reach(weapon, Modules.chargeById[item.charge], levels)
end

function Items.Offence(state: State.State, ship: number): Offence
  local fit = Items.Fit(state, ship, nil)
  local levels = Items.Levels(state, ship)
  local out: Offence = { volley = 0, dps = 0, kinds = { 0, 0, 0, 0 }, range = 0 }
  local hull = Ships.byId[state.ships[ship].type]
  for _, item in Items.Fitted(state, ship) do
    if Modules.byId[item.type].weapon and item.charge ~= "" then
      local weapon = Attributes.Weapon(fit, item.type, levels, hull)
      local charge = Modules.chargeById[item.charge]
      for index = 1, 4 do
        -- (more of the kind its hull leans to: Data/Ships' affinity; and a volley is so much of its missile, all told)
        local hit = charge.damage[index] * weapon.damageMultiplier * Ships.Dealt(hull, index) * (if weapon.volley then weapon.volley.share else 1)
        out.volley += hit
        out.dps += hit / weapon.duration
        out.kinds[index] += hit / weapon.duration
      end
      out.range = math.max(out.range, reach(weapon, charge, levels))
    end
    -- (and a Fighter Pylon's fighter, on it: what its gun does, as it carries it)
    local pylon = Modules.byId[item.type].pylon
    if pylon and item.charge ~= "" then
      local kind = DroneKinds.byId[pylon.drone]
      local gun = Modules.byId[kind.gun].weapon
      local charge = Modules.chargeById[kind.charge]
      if gun and charge then
        for index = 1, 4 do
          local hit = charge.damage[index] * gun.damageMultiplier
          out.volley += hit
          out.dps += hit / gun.duration
          out.kinds[index] += hit / gun.duration
        end
      end
    end
  end
  return out
end

-- Where a capacitor comes to rest with so much drawn from it a second,
-- as a share of full (nil if it does not: more is drawn than it can make
-- good); and then how long it lasts from full, in seconds.
--
-- A capacitor of 'max' that recharges in 'time' makes good
-- max * (10 / time) * r * (1 - r) a second, r being the root of how
-- full it is (Tactical/Gunnery's Recharge): most at a quarter full,
-- 2.5 * max / time. Drawn on for less than that it settles where what it
-- makes good is what is drawn, on the fuller side of the quarter.
function Items.Holds(max: number, time: number, drain: number): (number?, number?)
  if drain <= 0 or max <= 0 or time <= 0 then
    return if max > 0 then 1 else 0, nil
  end
  local k = drain * time / (10 * max)
  if k < 0.25 then
    local r = (1 + math.sqrt(1 - 4 * k)) / 2
    return r * r, nil
  end
  -- (it runs dry: a second at a time from full, for an hour at the most)
  local level, seconds = max, 0
  while level > 0 and seconds < 3600 do
    local r = math.sqrt(level / max)
    level += max * (10 / time) * r * (1 - r) - drain
    seconds += 1
  end
  return nil, seconds
end

-- What a ship's fit draws from its capacitor with everything it has
-- that is switched on running, cycle after cycle (GJ a second); the
-- most its capacitor can make good; and where that leaves it
-- (Items.Holds): the share of full it holds at, or how long it lasts.
export type Capacitor = { drain: number, peak: number, holds: number?, lasts: number? }

function Items.Capacitor(state: State.State, ship: number): Capacitor
  local fit = Items.Fit(state, ship, nil)
  local levels = Items.Levels(state, ship)
  local stats = Items.ShipStats(state, ship)
  local drain = 0
  for _, item in Items.Fitted(state, ship) do
    local module = Modules.byId[item.type]
    if module.weapon then
      local weapon = Attributes.Weapon(fit, item.type, levels, Ships.byId[state.ships[ship].type])
      drain += weapon.capacitor / math.max(0.1, weapon.duration)
    elseif module.miner then
      drain += module.miner.capacitor / math.max(0.1, module.miner.duration)
    elseif module.salvager then
      drain += module.salvager.capacitor / math.max(0.1, module.salvager.duration)
    elseif module.hex then
      drain += module.hex.capacitor / math.max(0.1, module.hex.duration)
    elseif module.repair then
      drain += module.repair.capacitor / math.max(0.1, module.repair.duration)
    elseif module.boost then
      drain += (module.boostCapacitor or 0) / math.max(0.1, module.boostDuration or 1)
    end
  end
  local holds, lasts = Items.Holds(stats.capacitor, stats.capacitorRecharge, drain)
  return { drain = drain, peak = if stats.capacitorRecharge > 0 then 2.5 * stats.capacitor / stats.capacitorRecharge else 0,
    holds = holds, lasts = lasts }
end

-- Cubic metres in a ship's hold.
function Items.CargoUsed(state: State.State, ship: number): number
  local used = 0
  for _, item in Items.In(state, ship, "cargo") do
    used += item.quantity * Types.Info(item.type).volume
  end
  return used
end

-- Cubic metres of drones in a ship's drone bay.
function Items.BayUsed(state: State.State, ship: number): number
  local used = 0
  for _, item in Items.In(state, ship, "dronebay") do
    used += item.quantity * Types.Info(item.type).volume
  end
  return used
end

-- Whether a type is what an ore hold takes: an ore, or a gas.
function Items.IsOre(type: string): boolean
  return Types.Info(type).category == "ore" or Ores.gasById[type] ~= nil
end

-- How big a ship's ore hold is, m3 (0: its hull has none), and the cubic
-- metres in it.
function Items.OreHold(state: State.State, ship: number): (number, number)
  local record = state.ships[ship]
  -- (and as much more as the hull's own bonus to it: Data/HullBonuses)
  local size = if record then (Ships.byId[record.type].ore or 0) * Ships.Bonus(Ships.byId[record.type], "ore", "hold",
    Items.Levels(state, ship)) else 0
  local used = 0
  if size > 0 then
    for _, item in Items.In(state, ship, "orehold") do
      used += item.quantity * Types.Info(item.type).volume
    end
  end
  return size, used
end

-- Whether a type is what a ship bay takes: a hull, packed.
function Items.IsHull(type: string): boolean
  return Ships.byId[type] ~= nil and Types.Get(type) ~= nil
end

-- How big a ship's bay for ships is, m3 (0: its hull has none: only a
-- logistics capital has), and the cubic metres of packed hulls in it.
function Items.ShipBay(state: State.State, ship: number): (number, number)
  local record = state.ships[ship]
  local size = if record then Ships.byId[record.type].shipbay or 0 else 0
  local used = 0
  if size > 0 then
    for _, item in Items.In(state, ship, "shipbay") do
      used += item.quantity * Types.Info(item.type).volume
    end
  end
  return size, used
end

-- ---------------------------------------------------------------------
-- Making and moving

-- Add 'quantity' of a type to a hangar or hold, merging with a stack that
-- is already there. Returns the stack.
function Items.Add(state: State.State, type: string, quantity: number, holder: number,
  place: "hangar" | "corporate" | "cargo" | "dronebay" | "orehold" | "shipbay"): State.Item
  assert(Types.Get(type), `no item type '{type}'`)
  assert(quantity > 0 and quantity % 1 == 0, "a quantity is a positive whole number")
  for _, item in Items.In(state, holder, place) do
    if item.type == type then
      item.quantity += quantity
      return item
    end
  end
  local item: State.Item = {
    id = State.NewId(state), type = type, quantity = quantity, holder = holder, place = place,
    slot = 0, charge = "", rounds = 0,
  }
  state.items[item.id] = item
  table.insert(state.itemIds, item.id)
  return item
end

-- Take 'quantity' out of a stack; the stack goes when it is empty.
function Items.Take(state: State.State, item: State.Item, quantity: number)
  assert(quantity > 0 and quantity <= item.quantity, "cannot take more than the stack holds")
  item.quantity -= quantity
  if item.quantity == 0 then
    state.items[item.id] = nil
    State.RemoveId(state.itemIds, item.id)
  end
end

-- Take ore (or gas) aboard a ship: into its ore hold, if it has one,
-- while there is room there, and what is left over into its hold.
-- 'free' is the room in its hold, m3 (which goes by its fit as it is:
-- the caller has it). Returns how many units were taken aboard.
function Items.StowOre(state: State.State, ship: number, type: string, units: number, free: number): number
  local volume = Types.Info(type).volume
  local size, used = Items.OreHold(state, ship)
  local first = math.min(units, math.max(0, math.floor((size - used + 1e-9) / volume)))
  if first > 0 then
    Items.Add(state, type, first, ship, "orehold")
  end
  local rest = math.min(units - first, math.max(0, math.floor((free + 1e-9) / volume)))
  if rest > 0 then
    Items.Add(state, type, rest, ship, "cargo")
  end
  return first + rest
end

-- Fit a new module straight onto a ship, loaded if a charge is named:
-- how a ship that was never in a hangar gets its fit (a new game's
-- starter ship, a pirate). Raises if the hull cannot carry it.
function Items.Equip(state: State.State, ship: number, type: string, charge: string?): State.Item
  local module = assert(Modules.byId[type], `no module '{type}'`)
  local hull = Ships.byId[state.ships[ship].type]
  local types = { type }
  local taken: { [number]: boolean } = {}
  for _, fitted in Items.Fitted(state, ship) do
    table.insert(types, fitted.type)
    if fitted.place == module.slot then
      taken[fitted.slot] = true
    end
  end
  local ok, why = Attributes.Check(hull, types)
  assert(ok, `{type} does not fit a {hull.name}: {tostring(why)}`)
  local slot = 1
  while taken[slot] do
    slot += 1
  end
  local item: State.Item = {
    id = State.NewId(state), type = type, quantity = 1, holder = ship, place = module.slot,
    slot = slot, charge = "", rounds = 0,
  }
  if charge then
    local takes = assert(Modules.Takes(module), `{type} takes no charge`)
    -- (a Fighter Pylon is loaded with its fighter: Data/Modules)
    assert((module.pylon and module.pylon.drone == charge) or (Modules.chargeById[charge] and Modules.Fits(module, Modules.chargeById[charge])),
      `{charge} does not fit {type}`)
    item.charge = charge
    item.rounds = takes.clip
  end
  state.items[item.id] = item
  table.insert(state.itemIds, item.id)
  return item
end

-- ---------------------------------------------------------------------
-- Orders

-- The station a ship and an item share, or nil with the reason they do
-- not: the ship is in space, or the item is elsewhere.
-- The pilot's Field Depot a ship in space is in reach of, if there is
-- one (Data/Deployables, Tactical/Deploy): it is refitted there, from its
-- own hold and the depot's, and what comes out of it goes into the depot.
local function depotNear(state: State.State, ship: State.Ship): State.Wreck?
  local ball = state.balls[ship.id]
  if ball == nil or ship.owner ~= "player" or (ball.warp and ball.warp.stage == "warp") then
    return nil
  end
  for _, id in state.wreckIds do
    local wreck = state.wrecks[id]
    local what = if wreck.deploy then Deployables.byId[wreck.deploy] else nil
    if what and what.kind == "depot" and wreck.system == ball.system then
      local gap = math.sqrt((wreck.x - ball.x) ^ 2 + (wreck.y - ball.y) ^ 2 + (wreck.z - ball.z) ^ 2) - wreck.radius - ball.radius
      if gap <= Deployables.REACH then
        return wreck
      end
    end
  end
  return nil
end
Items.DepotNear = depotNear

-- The volume of the charge loaded in a weapon (none, unloaded).
local function loadedVolume(weapon: State.Item): number
  local module = Modules.byId[weapon.type]
  local takes = if module then Modules.Takes(module) else nil
  if weapon.charge == "" or takes == nil then
    return 0
  end
  local quantity = if takes.clip == 0 then 1 else weapon.rounds
  return quantity * Types.Info(weapon.charge).volume
end

-- Whether 'volume' more fits where loose items go: anywhere but a Field
-- Depot (a station's hangar holds anything), and in a depot's hold as far
-- as it has room (Data/Deployables).
local function depotTakes(state: State.State, holder: number, volume: number): boolean
  local wreck = state.wrecks[holder]
  local what = if wreck and wreck.deploy then Deployables.byId[wreck.deploy] else nil
  if what == nil or volume <= 0 then
    return true
  end
  local used = 0
  for _, held in Items.In(state, holder, nil) do
    used += Types.Info(held.type).volume * held.quantity
  end
  return used + volume <= what.hold + 1e-9
end

local function sharedStation(state: State.State, ship: State.Ship, item: State.Item): (number?, string?)
  if State.At(ship) == 0 then
    local depot = depotNear(state, ship)
    if depot == nil then
      return nil, "not docked, nor by a Field Depot of yours"
    elseif not (item.holder == ship.id or (item.holder == depot.id and item.place == "cargo")) then
      return nil, "that item is not here"
    end
    return depot.id, nil
  end
  local here = item.holder == State.At(ship) and Items.IsStore(item.place)
  local aboard = item.holder == ship.id
  if not (here or aboard) then
    return nil, "that item is not here"
  end
  return State.At(ship), nil
end

local function freeSlot(state: State.State, ship: number, rack: string, size: number): number
  local taken: { [number]: boolean } = {}
  for _, item in Items.In(state, ship, rack) do
    taken[item.slot] = true
  end
  for slot = 1, size do
    if not taken[slot] then
      return slot
    end
  end
  return 0
end

-- Another ship of the pilot's own that lies in the station a ship is
-- docked in, with nobody flying it: its holds are in reach from there.
local function berthed(state: State.State, ship: State.Ship, other: number): State.Ship?
  local its = state.ships[other]
  if its and its.id ~= ship.id and State.At(ship) ~= 0 and its.docked == State.At(ship) and its.owner == "player" and its.pilot == 0 then
    return its
  end
  return nil
end

-- Whether a move is one that can be made. What can be moved is what is
-- aboard the ship (in space too: from one of its holds to another), and,
-- docked, what is in the station's stores or aboard another ship of the
-- pilot's that lies there. Where it can go: a hold of the ship's, or
-- ('target') of another ship of the pilot's that lies there; and,
-- docked, the station's stores.
local function validateMove(state: State.State, ship: State.Ship, item: State.Item, command: State.Command): (boolean, string?)
  if item.slot > 0 then
    return false, "unfit it first"
  end
  local aboard = item.holder == ship.id
  local stored = State.At(ship) ~= 0 and item.holder == State.At(ship) and Items.IsStore(item.place)
  if not (aboard or stored or berthed(state, ship, item.holder) ~= nil) then
    -- (what is in a station's stores is the station's to move: out in space it is nobody's)
    return false, if State.At(ship) ~= 0 then "that item is not here" elseif Items.IsStore(item.place) then "not docked"
      else "that item is not aboard"
  end
  local quantity = command.quantity or item.quantity
  if quantity <= 0 or quantity % 1 ~= 0 or quantity > item.quantity then
    return false, "no such quantity"
  end
  local into = ship
  if command.target and command.target ~= 0 and command.target ~= ship.id then
    local other = berthed(state, ship, command.target)
    if other == nil then
      return false, "no ship of yours lies here by that name"
    end
    into = other
  end
  local to = command.to
  local there = item.holder == into.id and item.place == to
  local volume = quantity * Types.Info(item.type).volume
  if to == "cargo" then
    if there then
      return false, "already in the hold"
    end
    local free = Items.ShipStats(state, into.id).cargo - Items.CargoUsed(state, into.id)
    if volume > free + 1e-9 then
      return false, "not enough room in the hold"
    end
    return true
  elseif to == "hangar" or to == "corporate" then
    if State.At(ship) == 0 then
      return false, "not docked"
    elseif to == "hangar" then
      return item.place ~= "hangar" or item.holder ~= State.At(ship), "already in the hangar"
    elseif not Corporation.Founded(state) then
      return false, "there is no corporation to give it to"
    end
    return item.place ~= "corporate", "already in the corporation's hangar"
  elseif to == "orehold" then
    -- (ore and gas, and as much as the ore hold has room for)
    local size, used = Items.OreHold(state, into.id)
    if there then
      return false, "already in the ore hold"
    elseif size == 0 then
      return false, "this hull has no ore hold"
    elseif not Items.IsOre(item.type) then
      return false, "only ore and gas go in an ore hold"
    elseif volume > size - used + 1e-9 then
      return false, "not enough room in the ore hold"
    end
    return true
  elseif to == "shipbay" then
    -- (packed hulls, and as many as the bay has room for)
    local size, used = Items.ShipBay(state, into.id)
    if there then
      return false, "already in the ship bay"
    elseif size == 0 then
      return false, "this hull has no ship bay"
    elseif not Items.IsHull(item.type) then
      return false, "only packed hulls go in a ship bay"
    elseif volume > size - used + 1e-9 then
      return false, "not enough room in the ship bay"
    end
    return true
  elseif to == "dronebay" then
    -- (drones, and as many as the bay has room for)
    local bay = Ships.byId[into.type].bay or 0
    if there then
      return false, "already in the drone bay"
    elseif Types.Info(item.type).category ~= "drone" then
      return false, "only drones go in a drone bay"
    elseif DroneKinds.byId[item.type] and DroneKinds.byId[item.type].craft
      and not Ships.Carries(Ships.byId[into.type], DroneKinds.byId[item.type].craft :: string) then
      -- (a fighter goes only in a carrier's bay or bigger, a bomber only
      -- in one whose hull launches bombers: Data/Ships' Carries)
      return false, `this hull has no bay for a {string.lower(DroneKinds.byId[item.type].name)}`
    elseif volume > bay - Items.BayUsed(state, into.id) + 1e-9 then
      return false, if bay == 0 then "this hull has no drone bay" else "not enough room in the drone bay"
    end
    return true
  end
  return false, "move it where?"
end

function Items.Validate(state: State.State, command: State.Command): (boolean, string?)
  local ship = state.ships[command.actor]
  if ship == nil then
    return false, "no such ship"
  end
  local item = state.items[command.item or 0]
  if item == nil then
    return false, "no such item"
  end
  if command.kind == "MoveItems" then
    return validateMove(state, ship, item, command)
  end
  local station, why = sharedStation(state, ship, item)
  if station == nil then
    return false, why
  end
  local hull = Ships.byId[ship.type]
  local kind = command.kind

  if kind == "Fit" then
    local module = Modules.byId[item.type]
    if module == nil then
      return false, "not a module"
    elseif item.slot > 0 then
      return false, "already fitted"
    end
    local missing = Skills.Missing(Skills.Needs(item.type), state.skills)
    if missing then
      return false, Skills.Describe(missing)
    end
    local types = {}
    for _, fitted in Items.Fitted(state, ship.id) do
      table.insert(types, fitted.type)
    end
    table.insert(types, item.type)
    return Attributes.Check(hull, types, Items.Levels(state, ship.id))

  elseif kind == "Unfit" then
    if item.slot == 0 or item.holder ~= ship.id then
      return false, "not fitted to this ship"
    end
    -- (at a Field Depot, what comes out goes into its hold, as far as there is room)
    local module = Modules.byId[item.type]
    if module.slot ~= "rig" and not depotTakes(state, station, Types.Info(item.type).volume + loadedVolume(item)) then
      return false, "no room in the Field Depot"
    end
    return true

  elseif kind == "LoadCharge" then
    local module = Modules.byId[item.type]
    -- (a weapon, or a module that is loaded as one is: a booster, an ancillary repairer)
    if item.slot == 0 or item.holder ~= ship.id or module == nil or Modules.Takes(module) == nil then
      return false, "not a fitted weapon"
    end
    local charge = state.items[command.other or 0]
    if charge == nil or charge.slot > 0 then
      return false, "no such charge"
    end
    -- (what was loaded comes out, into a Field Depot's hold as far as there is room)
    if not depotTakes(state, station, loadedVolume(item)) then
      return false, "no room in the Field Depot"
    end
    local _, chargeWhy = sharedStation(state, ship, charge)
    if chargeWhy then
      return false, chargeWhy
    end
    -- (a Fighter Pylon takes its own fighter, and only in a station: Data/Modules)
    if module.pylon then
      if charge.type ~= module.pylon.drone then
        return false, "only its fighter goes on a Fighter Pylon"
      elseif State.At(ship) == 0 then
        return false, "a fighter is put on its pylon only in a station"
      end
      return true
    end
    local chargeType = Modules.chargeById[charge.type]
    local takes = assert(Modules.Takes(module))
    if chargeType and chargeType.tech == 2 and module.tech ~= 2 and takes.family == chargeType.family then
      return false, "a tech 2 charge wants a tech 2 weapon"
    elseif chargeType == nil or not Modules.Fits(module, chargeType) then
      return false, if module.weapon then "that does not fit this weapon" else "that does not go in this"
    end
    return true

  end
  return false, `unknown command '{kind}'`
end

-- Put a weapon's loaded charge back where loose items go (the hangar; at
-- a Field Depot, its hold: 'place').
local function unload(state: State.State, weapon: State.Item, station: number, place: ("hangar" | "cargo")?)
  local module = Modules.byId[weapon.type]
  local takes = Modules.Takes(module)
  if weapon.charge ~= "" and takes then
    -- A crystal is one item; rounds are however many are left.
    local quantity = if takes.clip == 0 then 1 else weapon.rounds
    if quantity > 0 then
      Items.Add(state, weapon.charge, quantity, station, place or "hangar")
    end
  end
  weapon.charge = ""
  weapon.rounds = 0
end

function Items.Apply(state: State.State, command: State.Command, events: { Event })
  local ship = state.ships[command.actor]
  local item = state.items[command.item :: number]
  local station = State.At(ship)
  -- (in space, by a Field Depot: it is where things come out to)
  local place: "hangar" | "cargo" = "hangar"
  if station == 0 and (command.kind == "Unfit" or command.kind == "LoadCharge") then
    local depot = depotNear(state, ship)
    if depot then
      station, place = depot.id, "cargo"
    end
  end
  local kind = command.kind

  if kind == "Fit" then
    local module = Modules.byId[item.type]
    local hull = Ships.byId[ship.type] :: any
    local slot = freeSlot(state, ship.id, module.slot, hull[module.slot .. "s"])
    -- One leaves the stack and goes into the rack.
    local fitted: State.Item = {
      id = State.NewId(state), type = item.type, quantity = 1, holder = ship.id, place = module.slot,
      slot = slot, charge = "", rounds = 0,
    }
    Items.Take(state, item, 1)
    state.items[fitted.id] = fitted
    table.insert(state.itemIds, fitted.id)
    table.insert(events, { kind = "Fitted", ship = ship.id, item = fitted.id })

  elseif kind == "Unfit" then
    unload(state, item, station, place)
    local type = item.type
    Items.Take(state, item, 1)
    -- (a rig does not come out whole: it is gone)
    if Modules.byId[type].slot == "rig" then
      table.insert(events, { kind = "RigDestroyed", ship = ship.id, type = type })
    else
      Items.Add(state, type, 1, station, place)
      table.insert(events, { kind = "Unfitted", ship = ship.id, type = type })
    end

  elseif kind == "LoadCharge" then
    local weapon = assert(Modules.Takes(Modules.byId[item.type]))
    local charge = state.items[command.other :: number]
    local type = charge.type
    unload(state, item, station, place)
    -- (unloading may have merged into, but cannot have removed, the stack
    -- being loaded from)
    local stack = state.items[charge.id]
    local quantity = if weapon.clip == 0 then 1 else math.min(weapon.clip, stack.quantity)
    Items.Take(state, stack, quantity)
    item.charge = type
    item.rounds = if weapon.clip == 0 then 0 else quantity
    table.insert(events, { kind = "ChargeLoaded", ship = ship.id, item = item.id, charge = type })

  elseif kind == "MoveItems" then
    local quantity = command.quantity or item.quantity
    local type = item.type
    -- (into a hold of this ship's, or of another of the pilot's that lies here)
    local into = if command.target and command.target ~= 0 and state.ships[command.target] then command.target else ship.id
    Items.Take(state, item, quantity)
    if command.to == "cargo" then
      Items.Add(state, type, quantity, into, "cargo")
    elseif command.to == "dronebay" then
      Items.Add(state, type, quantity, into, "dronebay")
    elseif command.to == "orehold" then
      Items.Add(state, type, quantity, into, "orehold")
    elseif command.to == "shipbay" then
      Items.Add(state, type, quantity, into, "shipbay")
    elseif command.to == "corporate" then
      Items.Add(state, type, quantity, station, "corporate")
    else
      Items.Add(state, type, quantity, station, "hangar")
    end
    table.insert(events, { kind = "ItemsMoved", ship = ship.id, type = type, quantity = quantity, to = command.to })
  end
end

Items.RACKS = RACKS

return Items
