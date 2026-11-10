--!strict
local Codec = require("@lt/Core/Persist/Codec")
local Ledger = require("@lt/Core/Kernel/Ledger")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Ledger")

suite:Case("postings move balances and nothing is created outside the world", function(t)
  local ledger = Ledger.New()
  Ledger.Post(ledger, "credits", Ledger.WORLD, "actor:1", 1000, "tax")
  Ledger.Post(ledger, "credits", "actor:1", "actor:2", 300, "reparations")
  Ledger.Post(ledger, "credits", "actor:2", Ledger.WORLD, 50, "upkeep")
  t.eq(Ledger.Balance(ledger, "credits", "actor:1"), 700)
  t.eq(Ledger.Balance(ledger, "credits", "actor:2"), 250)
  t.eq(Ledger.Balance(ledger, "credits", Ledger.WORLD), -950)
  t.eq(Ledger.Balance(ledger, "ore", "actor:1"), 0, "units are separate")
  local total = 0
  for _, amount in ledger.balance.credits do
    total += amount
  end
  t.eq(total, 0, "balances sum to zero")
end)

suite:Case("sources and sinks are the flows through the world, by reason", function(t)
  local ledger = Ledger.New()
  Ledger.Post(ledger, "credits", Ledger.WORLD, "actor:1", 1000, "tax")
  Ledger.Post(ledger, "credits", Ledger.WORLD, "actor:2", 500, "tax")
  Ledger.Post(ledger, "credits", Ledger.WORLD, "actor:2", 20, "fenced loot")
  Ledger.Post(ledger, "credits", "actor:1", "actor:2", 300, "reparations")
  Ledger.Post(ledger, "credits", "actor:2", Ledger.WORLD, 50, "upkeep")
  t.eq(Ledger.Sources(ledger, "credits"), { { reason = "fenced loot", amount = 20 }, { reason = "tax", amount = 1500 } })
  t.eq(Ledger.Sinks(ledger, "credits"), { { reason = "upkeep", amount = 50 } })
  t.eq(Ledger.Sources(ledger, "ore"), {})
end)

suite:Case("reconcile finds a holding that changed without a posting", function(t)
  local ledger = Ledger.New()
  local wallets = { ["actor:1"] = 0, ["actor:2"] = 0 }
  Ledger.Post(ledger, "credits", Ledger.WORLD, "actor:1", 1000, "tax")
  wallets["actor:1"] += 1000
  Ledger.Post(ledger, "credits", "actor:1", "actor:2", 300, "reparations")
  wallets["actor:1"] -= 300
  wallets["actor:2"] += 300
  t.eq(Ledger.Reconcile(ledger, "credits", wallets), {}, "everything was posted")

  wallets["actor:2"] += 7 -- a leak: credits from nowhere
  t.eq(Ledger.Reconcile(ledger, "credits", wallets), { { account = "actor:2", ledger = 300, actual = 307 } })

  wallets["actor:2"] -= 7
  wallets["actor:3"] = 5 -- an account the ledger never heard of
  wallets["actor:1"] = nil :: any -- and one the state forgot
  t.eq(Ledger.Reconcile(ledger, "credits", wallets), {
    { account = "actor:1", ledger = 700, actual = 0 },
    { account = "actor:3", ledger = 0, actual = 5 },
  })
end)

suite:Case("reconcile allows a tolerance for fractional units", function(t)
  local ledger = Ledger.New()
  Ledger.Post(ledger, "ore", Ledger.WORLD, "node:1", 0.1, "mined")
  Ledger.Post(ledger, "ore", Ledger.WORLD, "node:1", 0.2, "mined")
  t.eq(Ledger.Reconcile(ledger, "ore", { ["node:1"] = 0.3 }, 1e-9), {})
  t.eq(#Ledger.Reconcile(ledger, "ore", { ["node:1"] = 0.31 }, 1e-9), 1)
end)

suite:Case("bad postings are refused; zero is a no-op", function(t)
  local ledger = Ledger.New()
  t.fails(function()
    Ledger.Post(ledger, "credits", "actor:1", "actor:2", -5, "refund")
  end)
  t.fails(function()
    Ledger.Post(ledger, "credits", "actor:1", "actor:1", 5, "self")
  end)
  t.fails(function()
    Ledger.Post(ledger, "credits", "actor:1", "actor:2", 0 / 0, "nan")
  end)
  Ledger.Post(ledger, "credits", "actor:1", "actor:2", 0, "nothing")
  t.eq(ledger.postings, 0)
  t.eq(ledger.balance, {})
end)

suite:Case("a ledger is plain data", function(t)
  local ledger = Ledger.New()
  Ledger.Post(ledger, "credits", Ledger.WORLD, "actor:1", 1000, "tax")
  local data, length = Codec.Encode(ledger)
  t.eq(Codec.Decode(data, length), ledger)
end)

return suite
