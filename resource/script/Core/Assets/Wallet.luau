--!strict
-- The player's money. Every change goes through Pay, which keeps the
-- journal and tells the interface.

local State = require("@lt/Core/Kernel/State")

local Wallet = {}

export type Event = { [string]: any }

local JOURNAL_LENGTH = 200

-- Add 'amount' credits (negative to spend), for a reason shown to the player.
function Wallet.Pay(state: State.State, amount: number, reason: string, events: { Event })
  if amount == 0 then
    return
  end
  state.wallet += amount
  table.insert(state.journal, { tick = state.tick, amount = amount, reason = reason, balance = state.wallet })
  if #state.journal > JOURNAL_LENGTH then
    table.remove(state.journal, 1)
  end
  table.insert(events, { kind = "WalletChanged", amount = amount, reason = reason, balance = state.wallet })
end

return Wallet
