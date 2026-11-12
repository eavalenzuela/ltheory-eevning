--!strict
-- The pilot's corporation: the business their hired pilots work for.
--
-- A pilot starts as nobody's business but their own. A corporation is
-- founded once, docked at any station, for a fee and under a name of
-- the pilot's choosing. From then on:
--   - it has an account of its own, with a journal of its own. What the
--     hired pilots cost comes out of it (signing one on, their wages,
--     the mending of a ship one of them flies), and what they bring in
--     goes into it (whatever a pilot told to sell sells, and the
--     bounties on what they destroy with the pilot somewhere else).
--     Where the account is short the pilot's own wallet makes up the
--     difference, so nobody leaves for want of a wage while there is
--     the money for it anywhere;
--   - the pilot puts credits into it and takes them out, docked;
--   - it has places for more pilots than the pilot's Leadership
--     commands (Corporation.STAFF more).
-- It keeps count of all it has earned and all it has spent, what its
-- founder pays in and takes out aside, so that its books say plainly
-- what the pilots make against what they cost.
--
-- Before there is one, the same payments are the pilot's own, as they
-- always were: everything here that pays or is paid falls through to
-- the wallet.
--
-- (The beginning of the corporation. Not yet: hangars of its own, the
-- pilot's structures on its books, anybody else's corporation.)

local State = require("@lt/Core/Kernel/State")
local Wallet = require("@lt/Core/Assets/Wallet")

local Corporation = {}

export type Event = { [string]: any }

-- What founding one costs, how many pilots it has places for beside
-- those the pilot's Leadership commands, and how long its name may be.
Corporation.FEE = 250000
Corporation.STAFF = 2
Corporation.SHORTEST = 3
Corporation.LONGEST = 24

local JOURNAL_LENGTH = 200

-- A corporation that has not been founded: what a new game has.
function Corporation.None(): State.Corporation
  return { name = "", founded = 0, wallet = 0, journal = {}, earned = 0, spent = 0 }
end

function Corporation.Founded(state: State.State): boolean
  return state.corporation.name ~= ""
end

-- How many pilots more than their Leadership commands the pilot can
-- have hired.
function Corporation.Staff(state: State.State): number
  return if Corporation.Founded(state) then Corporation.STAFF else 0
end

-- A name as it would be kept (the spaces at its ends gone, and runs of
-- them inside it made one), or nil and why it will not do.
function Corporation.Name(text: string): (string?, string?)
  local name = string.gsub(string.gsub(string.gsub(text, "^%s+", ""), "%s+$", ""), "%s+", " ")
  if #name < Corporation.SHORTEST then
    return nil, `a name has {Corporation.SHORTEST} letters at least`
  elseif #name > Corporation.LONGEST then
    return nil, `a name has {Corporation.LONGEST} letters at most`
  elseif string.find(name, "[^%w '&%.%-]") then
    return nil, "a name is of letters, figures and spaces"
  elseif not string.find(name, "%a") then
    return nil, "a name has a letter in it"
  end
  return name
end

-- Credits into the account (negative, out of it), for a reason its
-- journal shows. 'own': it is the founder's own money moved, which is
-- neither earned nor spent.
local function post(state: State.State, amount: number, reason: string, own: boolean, events: { Event })
  if amount == 0 then
    return
  end
  local corporation = state.corporation
  corporation.wallet += amount
  if not own then
    corporation.earned += math.max(0, amount)
    corporation.spent += math.max(0, -amount)
  end
  table.insert(corporation.journal, { tick = state.tick, amount = amount, reason = reason, balance = corporation.wallet })
  if #corporation.journal > JOURNAL_LENGTH then
    table.remove(corporation.journal, 1)
  end
  table.insert(events, { kind = "CorporationChanged", amount = amount, reason = reason, balance = corporation.wallet })
end

-- Whether the business has so much to pay with: the account, and the
-- pilot's own wallet behind it.
function Corporation.Afford(state: State.State, amount: number): boolean
  return state.corporation.wallet + state.wallet >= amount
end

-- The business pays so much, for a reason: out of the account as far as
-- that goes, and the rest out of the pilot's wallet. (All of it out of
-- the wallet, where there is no corporation.)
function Corporation.Spend(state: State.State, amount: number, reason: string, events: { Event })
  local theirs = if Corporation.Founded(state) then math.min(amount, math.max(0, state.corporation.wallet)) else 0
  post(state, -theirs, reason, false, events)
  Wallet.Pay(state, -(amount - theirs), reason, events)
end

-- The business is paid so much, for a reason: into the account, or the
-- pilot's wallet where there is no corporation.
function Corporation.Earn(state: State.State, amount: number, reason: string, events: { Event })
  if Corporation.Founded(state) then
    post(state, amount, reason, false, events)
  else
    Wallet.Pay(state, amount, reason, events)
  end
end

function Corporation.Validate(state: State.State, command: State.Command): (boolean, string?)
  local ship = state.ships[command.actor]
  if ship == nil or ship.id ~= state.player.ship then
    return false, "no such ship"
  elseif ship.docked == 0 then
    return false, "not docked"
  end
  local kind = command.kind
  if kind == "FoundCorporation" then
    if Corporation.Founded(state) then
      return false, `{state.corporation.name} is founded already`
    end
    local name, why = Corporation.Name(command.what or "")
    if name == nil then
      return false, why
    elseif state.wallet < Corporation.FEE then
      return false, "not enough credits"
    end
    return true
  end
  if not Corporation.Founded(state) then
    return false, "there is no corporation"
  end
  local amount = command.quantity or 0
  if amount < 1 or amount % 1 ~= 0 then
    return false, "how much?"
  elseif kind == "CorporationDeposit" then
    return state.wallet >= amount, if state.wallet >= amount then nil else "not enough credits"
  elseif kind == "CorporationWithdraw" then
    local has = state.corporation.wallet >= amount
    return has, if has then nil else "the corporation has not that much"
  end
  return false, `unknown command '{kind}'`
end

function Corporation.Apply(state: State.State, command: State.Command, events: { Event })
  local kind = command.kind
  if kind == "FoundCorporation" then
    local name = Corporation.Name(command.what :: string) :: string
    Wallet.Pay(state, -Corporation.FEE, "founding a corporation", events)
    state.corporation.name = name
    state.corporation.founded = state.tick
    table.insert(events, { kind = "CorporationFounded", name = name })
  elseif kind == "CorporationDeposit" then
    local amount = command.quantity :: number
    Wallet.Pay(state, -amount, "to the corporation", events)
    post(state, amount, "from its founder", true, events)
  elseif kind == "CorporationWithdraw" then
    local amount = command.quantity :: number
    post(state, -amount, "to its founder", true, events)
    Wallet.Pay(state, amount, "from the corporation", events)
  end
end

return Corporation
