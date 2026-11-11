--!strict
-- Missions: work a station has for a pilot.
--
-- Every station that is not a pilot's own offers three jobs a day, each
-- one of three kinds:
--   - a bounty: destroy so many pirates in a system (the station's own
--     or a neighbour's), and come back to be paid;
--   - a courier run: carry sealed cargo to another station, in this
--     system or the next, and be paid there;
--   - a supply order: bring so much of an ore or a mineral to the
--     station, for half as much again as it is worth.
-- What is offered follows from the station and the day, so it is the
-- same however often it is asked for, and is not kept: only what a
-- pilot has taken on is. A pilot has at most five jobs in hand.
--
-- A pirate the pilot destroys in a bounty job's system counts toward it
-- (Tactical/Aftermath does the counting).
--
-- Finishing a job pays its reward and a little standing with the
-- faction whose station it was; abandoning one costs standing. Standing
-- runs from -10 to 10, and each point adds 3% to what that faction's
-- stations pay for a job.
--
-- Each job comes from somebody: a station has three agents, by name,
-- and each has one job a day. A job in hand has to be finished within
-- three days of being taken; one that is not lapses, at the cost in
-- standing of having given it up.
--
-- A finished job also earns loyalty points with the faction, a point
-- for every four hundred credits of its pay, and a faction's stations
-- have a store where they are spent (with some credits beside): on
-- datacores, on implants, and on the blueprints of the tech 2 makes of
-- the faction's own kinds of weapon, which are otherwise only to be
-- invented. What a store will let a pilot have follows from their
-- standing: datacores for anybody it does not think ill of, implants
-- at a standing of 1, blueprints at 2.
--
-- (A first version of the roadmap's agents. Not yet: agents with a
-- standing of their own, jobs made from what the simulation needs, a
-- place made for a job.)

local Constants = require("@lt/Core/Data/Constants")
local Factions = require("@lt/Core/Data/Factions")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Blueprints = require("@lt/Core/Data/Blueprints")
local Implants = require("@lt/Core/Data/Implants")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Names = require("@lt/Core/Describe/Names")
local Rng = require("@lt/Core/Kernel/Rng")
local Space = require("@lt/Core/Tactical/Space")
local Standings = require("@lt/Core/Assets/Standings")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")
local Types = require("@lt/Core/Data/Types")
local Wallet = require("@lt/Core/Assets/Wallet")

local Missions = {}

export type Event = { [string]: any }

Missions.OFFERS = 3
Missions.IN_HAND = 5
Missions.CRATE = "cargo.sealed"
-- Credits of a job's pay to a loyalty point.
Missions.LOYALTY = 400
-- Ticks a job in hand may be kept before it lapses: three days.
Missions.LIMIT = 3 * math.ceil(86400 / Constants.TICK)
-- Ticks in the day a station's offers last.
local DAY = math.ceil(86400 / Constants.TICK)
-- What a pirate killed for a bounty job is worth, by how safe the
-- system is where it has to be done.
local HEAD: { [string]: number } = { secure = 9000, low = 30000, lawless = 90000 }
local SUPPLIES = { "ore.ferrite", "ore.cuprite", "ore.silicate", "mineral.iron", "mineral.silicon", "mineral.copper" }

-- What an offer is called, for the lists.
function Missions.Title(mission: State.Mission): string
  if mission.kind == "bounty" then
    return `Bounty: {mission.need} {if mission.need == 1 then "pirate" else "pirates"}`
  elseif mission.kind == "courier" then
    return `Courier: {mission.need} m3 of sealed cargo`
  end
  return `Supply: {mission.need} {Types.Info(mission.type).name}`
end

-- A pilot's standing with a faction, from -10 to 10 (Assets/Standings).
function Missions.Standing(state: State.State, faction: string): number
  return Standings.Of(state, faction)
end

local function stations(state: State.State, system: number): { System.Object }
  local found: { System.Object } = {}
  for _, object in Space.Describe(state, system).objects do
    if object.kind == "station" and state.starbases[object.id] == nil then
      table.insert(found, object)
    end
  end
  return found
end

-- Who at a station gives its nth job of the day: the same person every
-- day, for as long as the galaxy lasts.
function Missions.Agent(state: State.State, station: number, slot: number): string
  return Names.Person(Rng.For(state.galaxySeed, station, slot, 71))
end

-- The key of an offer: its station, day and place in the list.
local function keyOf(station: number, day: number, slot: number): string
  return `{station}:{day}:{slot}`
end

-- What a station offers today, less what has been taken. Each is a
-- mission as it would be if taken (its id is 0 until it is).
function Missions.Offers(state: State.State, station: number): { State.Mission }
  local object = Space.Object(state, station)
  if object == nil or object.kind ~= "station" or state.starbases[station] then
    return {}
  end
  local system = Space.SystemOf(state, station)
  local node = state.galaxy.systems[system]
  local day = state.tick // DAY
  local bonus = 1 + 0.03 * Missions.Standing(state, node.nearest)
  local offers: { State.Mission } = {}
  for slot = 1, Missions.OFFERS do
    local key = keyOf(station, day, slot)
    if not table.find(state.missionsTaken, key) then
      local rng = Rng.For(state.historySeed, station, day, slot, 83)
      local mission: State.Mission = {
        id = 0, key = key, kind = "bounty", station = station, faction = node.nearest, system = system, need = 1, done = 0,
        type = "", to = station, reward = 0, standing = 0.1, taken = 0,
        agent = Missions.Agent(state, station, slot), loyalty = 0,
      }
      local roll = Rng.Int(rng, 3)
      -- (a neighbour's station, for a courier run that is a jump)
      local next = node.neighbors[Rng.Int(rng, #node.neighbors) + 1]
      local here, there = stations(state, system), if next then stations(state, next) else {}
      if roll == 0 or (roll == 1 and #here < 2 and #there == 0) then
        -- Where order is thinner next door, the bounty may be for there.
        local wilder = next ~= nil and state.galaxy.systems[next].security < node.security and Rng.Chance(rng, 0.5)
        mission.system = if wilder then next else system
        mission.need = 1 + Rng.Int(rng, 3)
        local band = Galaxy.Band(state.galaxy.systems[mission.system].security)
        mission.reward = math.floor(mission.need * HEAD[band] * bonus)
        mission.standing = if band == "secure" then 0.1 elseif band == "low" then 0.2 else 0.4
      elseif roll == 1 then
        mission.kind = "courier"
        local far = #there > 0 and (#here < 2 or Rng.Chance(rng, 0.5))
        local choices = if far then there else here
        local to = choices[Rng.Int(rng, #choices) + 1]
        if to.id == station then
          to = choices[(table.find(choices, to) :: number) % #choices + 1]
        end
        mission.to = to.id
        mission.type = Missions.CRATE
        mission.need = 40 + 10 * Rng.Int(rng, 8)
        mission.reward = math.floor((if far then 9000 else 4000) * (0.8 + mission.need / 200) * bonus)
        mission.standing = if far then 0.15 else 0.1
      else
        mission.kind = "supply"
        mission.type = SUPPLIES[Rng.Int(rng, #SUPPLIES) + 1]
        mission.need = 200 + 100 * Rng.Int(rng, 9)
        mission.reward = math.floor(mission.need * Types.Info(mission.type).basePrice * 1.5 * bonus)
        mission.standing = 0.1
      end
      mission.loyalty = math.max(1, mission.reward // Missions.LOYALTY)
      table.insert(offers, mission)
    end
  end
  return offers
end

-- The jobs in hand, oldest first.
function Missions.InHand(state: State.State): { State.Mission }
  local found: { State.Mission } = {}
  for _, id in state.missionIds do
    table.insert(found, state.missions[id])
  end
  return found
end

-- How many of a type a docked ship has to hand: in its hold and in the
-- hangar of the station it is at.
local function toHand(state: State.State, ship: State.Ship, type: string): number
  local have = 0
  for _, item in Items.In(state, ship.id, "cargo") do
    have += if item.type == type then item.quantity else 0
  end
  for _, item in Items.In(state, ship.docked, "hangar") do
    have += if item.type == type and item.slot == 0 then item.quantity else 0
  end
  return have
end

-- Take 'quantity' of a type from what a docked ship has to hand.
local function hand(state: State.State, ship: State.Ship, type: string, quantity: number)
  for _, place in { { ship.id, "cargo" }, { ship.docked, "hangar" } } :: { { any } } do
    for _, item in Items.In(state, place[1], place[2]) do
      if quantity > 0 and item.type == type and item.slot == 0 then
        local take = math.min(quantity, item.quantity)
        Items.Take(state, item, take)
        quantity -= take
      end
    end
  end
end

-- Where a job is finished, and whether it can be finished now by a ship
-- docked there; if not, why not.
function Missions.Ready(state: State.State, ship: State.Ship, mission: State.Mission): (boolean, string?)
  local where = if mission.kind == "courier" then mission.to else mission.station
  if ship.docked ~= where then
    local object = Space.Object(state, where)
    return false, `finish it at {if object then object.name else "its station"}`
  elseif mission.kind == "bounty" then
    if mission.done < mission.need then
      return false, `{mission.need - mission.done} still to destroy`
    end
  elseif toHand(state, ship, mission.type) < mission.need then
    return false, `{mission.need - toHand(state, ship, mission.type)} more to bring`
  end
  return true
end

function Missions.Validate(state: State.State, command: State.Command): (boolean, string?)
  local ship = state.ships[command.actor]
  if ship == nil then
    return false, "no such ship"
  elseif ship.docked == 0 then
    return false, "not docked"
  end
  local kind = command.kind
  if kind == "RedeemLoyalty" then
    local offer, faction = Missions.Stocked(state, ship.docked, command.type or "")
    local quantity = command.quantity or 1
    if offer == nil then
      return false, "this station's store has no such thing"
    elseif quantity < 1 or quantity % 1 ~= 0 then
      return false, "how many?"
    elseif Standings.Of(state, faction) < offer.standing then
      return false, `needs a standing of {offer.standing} with them`
    elseif (state.loyalty[faction] or 0) < offer.points * quantity then
      return false, `needs {offer.points * quantity} loyalty points`
    elseif state.wallet < offer.credits * quantity then
      return false, "not enough credits"
    end
    return true
  elseif kind == "AcceptMission" then
    for _, offer in Missions.Offers(state, ship.docked) do
      if offer.key == command.what then
        if #state.missionIds >= Missions.IN_HAND then
          return false, `a pilot has {Missions.IN_HAND} jobs in hand at most`
        end
        return true
      end
    end
    return false, "no such job is offered here"
  end
  local mission = state.missions[command.target or 0]
  if mission == nil then
    return false, "no such job in hand"
  elseif kind == "CompleteMission" then
    return Missions.Ready(state, ship, mission)
  elseif kind == "AbandonMission" then
    return true
  end
  return false, `unknown command '{kind}'`
end

local function close(state: State.State, mission: State.Mission)
  state.missions[mission.id] = nil
  State.RemoveId(state.missionIds, mission.id)
end

local function standing(state: State.State, faction: string, change: number)
  Standings.Change(state, faction, change)
end

function Missions.Apply(state: State.State, command: State.Command, events: { Event })
  local ship = state.ships[command.actor]
  local kind = command.kind
  if kind == "RedeemLoyalty" then
    local offer, faction = Missions.Stocked(state, ship.docked, command.type :: string)
    local quantity = command.quantity or 1
    if offer then
      state.loyalty[faction] = (state.loyalty[faction] or 0) - offer.points * quantity
      Wallet.Pay(state, -offer.credits * quantity, "loyalty store", events)
      Items.Add(state, offer.type, quantity, ship.docked, "hangar")
      table.insert(events, { kind = "LoyaltyRedeemed", type = offer.type, quantity = quantity, faction = faction,
        points = offer.points * quantity, left = state.loyalty[faction] })
    end
    return
  elseif kind == "AcceptMission" then
    for _, offer in Missions.Offers(state, ship.docked) do
      if offer.key == command.what then
        offer.id = State.NewId(state)
        offer.taken = state.tick
        state.missions[offer.id] = offer
        table.insert(state.missionIds, offer.id)
        table.insert(state.missionsTaken, offer.key)
        -- (yesterday's offers are gone: so is the list of which were taken)
        local day = `:{state.tick // DAY}:`
        for index = #state.missionsTaken, 1, -1 do
          if not string.find(state.missionsTaken[index], day, 1, true) then
            table.remove(state.missionsTaken, index)
          end
        end
        if offer.kind == "courier" then
          Items.Add(state, Missions.CRATE, offer.need, ship.docked, "hangar")
        end
        table.insert(events, { kind = "MissionAccepted", mission = offer.id, title = Missions.Title(offer) })
      end
    end
    return
  end
  local mission = state.missions[command.target :: number]
  if kind == "CompleteMission" then
    if mission.kind ~= "bounty" then
      hand(state, ship, mission.type, mission.need)
    end
    Wallet.Pay(state, mission.reward, "mission reward", events)
    standing(state, mission.faction, mission.standing)
    state.loyalty[mission.faction] = (state.loyalty[mission.faction] or 0) + mission.loyalty
    close(state, mission)
    state.missionsDone += 1
    table.insert(events, { kind = "MissionCompleted", mission = mission.id, title = Missions.Title(mission), reward = mission.reward,
      faction = mission.faction, standing = Missions.Standing(state, mission.faction), loyalty = mission.loyalty })
  elseif kind == "AbandonMission" then
    -- (a courier's cargo goes back, as much of it as is to hand)
    if mission.kind == "courier" then
      hand(state, ship, mission.type, math.min(mission.need, toHand(state, ship, mission.type)))
    end
    standing(state, mission.faction, -2 * mission.standing)
    close(state, mission)
    table.insert(events, { kind = "MissionAbandoned", mission = mission.id, title = Missions.Title(mission) })
  end
end

-- Once a minute: a job kept past its time lapses, as if it had been
-- given up.
function Missions.Step(state: State.State, events: { Event })
  if state.tick % 60 ~= 0 then
    return
  end
  for _, id in table.clone(state.missionIds) do
    local mission = state.missions[id]
    if state.tick - mission.taken > Missions.LIMIT then
      standing(state, mission.faction, -2 * mission.standing)
      close(state, mission)
      table.insert(events, { kind = "MissionExpired", mission = mission.id, title = Missions.Title(mission) })
    end
  end
end

-- The seconds a job in hand has left before it lapses.
function Missions.Left(state: State.State, mission: State.Mission): number
  return math.max(0, Missions.LIMIT - (state.tick - mission.taken)) * Constants.TICK
end

-- What a faction's store lets a pilot have, for so many loyalty points
-- and so many credits, at a standing of at least so much.
export type Stock = { type: string, points: number, credits: number, standing: number }

local stores: { [string]: { Stock } } = {}

-- A faction's store: a datacore, the implants, and the blueprints of
-- the tech 2 makes of its own kinds of weapon.
function Missions.Store(faction: string): { Stock }
  local made = stores[faction]
  if made then
    return made
  end
  local own = Factions.byId[faction]
  local stock: { Stock } = {}
  if own and own.kind == "human" then
    table.insert(stock, { type = "datacore", points = 50, credits = 5000, standing = 0 })
    for _, implant in Implants.list do
      table.insert(stock, { type = implant.id, points = 120 * implant.slot, credits = Implants.Price(implant) // 2, standing = 1 })
    end
    local families: { [string]: boolean } = { [own.weapon] = true, missile = own.launchers >= 0.3 }
    for _, module in Modules.list do
      local blueprint = Blueprints.byProduct[module.id]
      if module.tech == 2 and module.weapon and families[module.weapon.family] and blueprint then
        table.insert(stock, { type = blueprint.id, points = math.ceil(module.basePrice / 400), credits = 0, standing = 2 })
      end
    end
  end
  stores[faction] = stock
  return stock
end

-- What a station's store has of a type, and whose store it is. Nothing
-- at a pilot's own starbase, or for a type it does not keep.
function Missions.Stocked(state: State.State, station: number, type: string): (Stock?, string)
  local object = Space.Object(state, station)
  if object == nil or object.kind ~= "station" or state.starbases[station] then
    return nil, ""
  end
  local faction = state.galaxy.systems[Space.SystemOf(state, station)].nearest
  for _, stock in Missions.Store(faction) do
    if stock.type == type then
      return stock, faction
    end
  end
  return nil, faction
end

-- The name of the faction a job is for.
function Missions.For(mission: State.Mission): string
  local faction = Factions.byId[mission.faction]
  return if faction then faction.name else "nobody"
end

return Missions
