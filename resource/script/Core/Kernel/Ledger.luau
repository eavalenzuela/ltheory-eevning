--!strict
-- A double-entry ledger for whatever must be conserved: credits, and
-- each good.
--
-- Every movement is posted as "amount of unit, from one account to
-- another, for a reason". An account is anything that holds the unit: a
-- faction's wallet ("actor:3"), a system's stock ("node:17"), or the
-- outside world ("world"), which is where things are created and
-- destroyed. Nothing appears or disappears except through "world", so
-- the flows through it, by reason, are exactly the sources and sinks.
--
-- The ledger keeps its own balance for every account. Reconcile compares
-- those with what the state actually holds. A wallet or a stock changed
-- without a posting shows up there as a residual, which is the bug this
-- exists to catch: an economy that leaks.
--
-- The ledger is plain data and belongs in the state, so it is saved and
-- hashed with it.

local Ledger = {}

export type Ledger = {
  -- balance[unit][account]: net amount posted into the account
  balance: { [string]: { [string]: number } },
  -- flow[unit][reason]: total amount posted for the reason
  flow: { [string]: { [string]: number } },
  -- source[unit][reason] and sink[unit][reason]: the part of 'flow' that
  -- came out of, or went into, the world
  source: { [string]: { [string]: number } },
  sink: { [string]: { [string]: number } },
  postings: number,
}

Ledger.WORLD = "world"

function Ledger.New(): Ledger
  return { balance = {}, flow = {}, source = {}, sink = {}, postings = 0 }
end

local function add(map: { [string]: { [string]: number } }, unit: string, key: string, amount: number)
  local row = map[unit]
  if row == nil then
    row = {}
    map[unit] = row
  end
  row[key] = (row[key] or 0) + amount
end

-- Move 'amount' of 'unit' from one account to another. The amount must
-- not be negative: a refund is a posting in the other direction, with its
-- own reason.
function Ledger.Post(ledger: Ledger, unit: string, from: string, to: string, amount: number, reason: string)
  if not (amount >= 0) then
    error(`Ledger: a posting of {amount} {unit} from {from} to {to} ({reason}); amounts cannot be negative`, 2)
  end
  if from == to then
    error(`Ledger: a posting from {from} to itself ({reason})`, 2)
  end
  if amount == 0 then
    return
  end
  add(ledger.balance, unit, from, -amount)
  add(ledger.balance, unit, to, amount)
  add(ledger.flow, unit, reason, amount)
  if from == Ledger.WORLD then
    add(ledger.source, unit, reason, amount)
  elseif to == Ledger.WORLD then
    add(ledger.sink, unit, reason, amount)
  end
  ledger.postings += 1
end

-- What the ledger says 'account' holds of 'unit'.
function Ledger.Balance(ledger: Ledger, unit: string, account: string): number
  local row = ledger.balance[unit]
  return if row then row[account] or 0 else 0
end

export type Residual = { account: string, ledger: number, actual: number }

-- Compare the ledger's balances for 'unit' with what the state holds.
-- 'actual' maps every account that holds the unit to its holding; the
-- world is left out. Returns the accounts that disagree by more than
-- 'tolerance' (0 for integer units), in account order. An empty result
-- means nothing leaked.
function Ledger.Reconcile(ledger: Ledger, unit: string, actual: { [string]: number }, tolerance: number?): { Residual }
  local limit = tolerance or 0
  local names: { string } = {}
  local seen: { [string]: boolean } = {}
  for account in actual do
    seen[account] = true
    table.insert(names, account)
  end
  local booked: { [string]: number } = ledger.balance[unit] or {}
  for account in booked do
    if not seen[account] and account ~= Ledger.WORLD then
      table.insert(names, account)
    end
  end
  table.sort(names)
  local residuals: { Residual } = {}
  for _, account in names do
    local expected = booked[account] or 0
    local held = actual[account] or 0
    if math.abs(expected - held) > limit then
      table.insert(residuals, { account = account, ledger = expected, actual = held })
    end
  end
  return residuals
end

export type Line = { reason: string, amount: number }

local function lines(row: { [string]: number }?): { Line }
  local out: { Line } = {}
  local entries: { [string]: number } = row or {}
  for reason, amount in entries do
    table.insert(out, { reason = reason, amount = amount })
  end
  table.sort(out, function(a: Line, b: Line): boolean
    return a.reason < b.reason
  end)
  return out
end

-- What entered the game from the world, and what left it, by reason, in
-- reason order.
function Ledger.Sources(ledger: Ledger, unit: string): { Line }
  return lines(ledger.source[unit])
end

function Ledger.Sinks(ledger: Ledger, unit: string): { Line }
  return lines(ledger.sink[unit])
end

return Ledger
