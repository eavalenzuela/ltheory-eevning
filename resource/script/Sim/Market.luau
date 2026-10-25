--!strict
-- Station prices from stock: a station pays more for inputs it is short of
-- and sells its outputs cheaper the fuller its storage. Prices therefore
-- differ by station and over time, which is what makes hauling pay.

local Data = require("@lt/Sim/Data")
local State = require("@lt/Sim/State")

local Market = {}

type Profile = { wants: { [string]: number }, makes: { [string]: number } }
local profiles: { [string]: Profile } = {}

function Market.Profile(kind: string): Profile
  local profile = profiles[kind]
  if not profile then
    local wants, makes = State.StationProfile(kind)
    profile = { wants = wants, makes = makes }
    profiles[kind] = profile
  end
  return profile
end

-- What the station pays for 'good' (it buys), or nil if it doesn't
function Market.BuyPrice(station: State.Station, good: string): number?
  local target = Market.Profile(station.kind).wants[good]
  if not target or station.destroyed then
    return nil
  end
  local short = math.max(0, 1 - (station.stock[good] or 0) / target)
  return Data.GoodById[good].base * (0.6 + 0.9 * short)
end

-- What the station asks for 'good' (it sells), or nil if it doesn't
function Market.SellPrice(station: State.Station, good: string): number?
  local perCycle = Market.Profile(station.kind).makes[good]
  if not perCycle or station.destroyed then
    return nil
  end
  local full = math.min(1, (station.stock[good] or 0) / (perCycle * Data.CAP_CYCLES))
  return Data.GoodById[good].base * (1.2 - 0.6 * full)
end

-- How much of 'good' the station would sell
function Market.Surplus(station: State.Station, good: string): number
  local perCycle = Market.Profile(station.kind).makes[good]
  if not perCycle then
    return 0
  end
  return math.max(0, (station.stock[good] or 0) - perCycle * Data.KEEP_CYCLES)
end

-- How much of 'good' the station would buy
function Market.Deficit(station: State.Station, good: string): number
  local target = Market.Profile(station.kind).wants[good]
  if not target then
    return 0
  end
  return math.max(0, target - (station.stock[good] or 0))
end

export type Offer = { station: number, price: number, amount: number }
export type Index = { [string]: { sellers: { Offer }, buyers: { Offer } } }

-- Offers worth less than this many credits aren't worth a convoy
local MIN_OFFER_VALUE = 200

-- Every offer for every good this tick: sellers with surplus and buyers
-- with a deficit, net of what convoys under way already claimed
function Market.Index(state: State.State): Index
  local index: Index = {}
  for _, good in Data.Goods do
    index[good.id] = { sellers = {}, buyers = {} }
  end
  for _, station in state.stations do
    local owner = state.systems[station.system].owner
    if not station.destroyed and (owner == nil or not state.factions[owner].pirate) then
      local profile = Market.Profile(station.kind)
      for good in profile.makes do
        local surplus = Market.Surplus(station, good) - State.Pending(state, "out", station.id, good)
        if surplus * Data.GoodById[good].base > MIN_OFFER_VALUE then
          table.insert(index[good].sellers, { station = station.id, price = Market.SellPrice(station, good) :: number, amount = surplus })
        end
      end
      for good in profile.wants do
        local deficit = Market.Deficit(station, good) - State.Pending(state, "in", station.id, good)
        if deficit * Data.GoodById[good].base > MIN_OFFER_VALUE then
          table.insert(index[good].buyers, { station = station.id, price = Market.BuyPrice(station, good) :: number, amount = deficit })
        end
      end
    end
  end
  return index
end

return Market
