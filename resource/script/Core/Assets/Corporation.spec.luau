--!strict
-- The pilot's corporation (Assets/Corporation).

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Corporation = require("@lt/Core/Assets/Corporation")
local Fleet = require("@lt/Core/Tactical/Fleet")
local Items = require("@lt/Core/Assets/Items")
local Market = require("@lt/Core/Assets/Market")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Corporation")

local function submit(game: Core.Game, command: State.Command): (boolean, string?)
  command.actor = game.state.player.ship
  local ok, why = Core.Submit(game, command)
  Core.Step(game)
  return ok, why
end

local function refused(game: Core.Game, command: State.Command): string?
  command.actor = game.state.player.ship
  local ok, why = Core.Validate(game, command)
  return if ok then "(accepted)" else why
end

-- A game with so much in the pilot's wallet, docked at home.
local function rich(credits: number): Core.Game
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  game.state.wallet = credits
  return game
end

-- A game whose pilot has founded a corporation, with so much left in
-- their own wallet after.
local function founded(left: number): Core.Game
  local game = rich(Corporation.FEE + left)
  assert(submit(game, { kind = "FoundCorporation", actor = 0, what = "Merear Carriers" }))
  Core.TakeEvents(game)
  return game
end

-- The events of a kind since they were last taken.
local function said(game: Core.Game, kind: string): { { [string]: any } }
  local found: { { [string]: any } } = {}
  for _, event in Core.TakeEvents(game) do
    if event.kind == kind then
      table.insert(found, event)
    end
  end
  return found
end

suite:Case("a corporation is founded once, docked, for a fee and under a name", function(t)
  -- A name: three letters to twenty-four, of letters, figures and spaces (and a few marks), tidied.
  t.eq(Corporation.Name("  Merear   Carriers "), "Merear Carriers")
  t.eq(Corporation.Name("Black & Sons Ltd."), "Black & Sons Ltd.")
  t.eq(Corporation.Name("O'Neil-7"), "O'Neil-7")
  t.eq({ Corporation.Name("ab") } :: { any }, { nil, "a name has 3 letters at least" } :: { any })
  t.eq({ Corporation.Name("   a   ") } :: { any }, { nil, "a name has 3 letters at least" } :: { any })
  t.eq(select(2, Corporation.Name(string.rep("a", 25))), "a name has 24 letters at most")
  t.eq(select(2, Corporation.Name("Merear;Carriers")), "a name is of letters, figures and spaces")
  t.eq(select(2, Corporation.Name("1234")), "a name has a letter in it")

  local game = rich(Corporation.FEE - 1)
  local state = game.state
  local none = Core.Query.Corporation(game)
  t.eq({ none.founded, none.name, none.wallet, #none.journal, none.fee, none.staff } :: { any },
    { false, "", 0, 0, Corporation.FEE, Corporation.STAFF } :: { any })
  -- Not without the fee, nor a name, nor out in space.
  t.eq(refused(game, { kind = "FoundCorporation", actor = 0, what = "Merear Carriers" }), "not enough credits")
  state.wallet = Corporation.FEE + 700
  t.eq(refused(game, { kind = "FoundCorporation", actor = 0, what = "x" }), "a name has 3 letters at least")
  t.eq(refused(game, { kind = "FoundCorporation", actor = 0 }), "a name has 3 letters at least")
  t.eq(refused(game, { kind = "CorporationDeposit", actor = 0, quantity = 10 }), "there is no corporation")
  -- Founded: the fee is paid, and it is there, with nothing in its account.
  t.ok((submit(game, { kind = "FoundCorporation", actor = 0, what = " Merear  Carriers " })))
  local events = said(game, "CorporationFounded")
  t.eq({ #events, events[1].name } :: { any }, { 1, "Merear Carriers" } :: { any })
  local info = Core.Query.Corporation(game)
  t.eq({ info.founded, info.name, info.wallet, info.earned, info.spent, state.wallet } :: { any },
    { true, "Merear Carriers", 0, 0, 0, 700 } :: { any })
  t.eq(info.since, state.tick)
  t.eq(state.journal[#state.journal].reason, "founding a corporation")
  -- Once.
  t.eq(refused(game, { kind = "FoundCorporation", actor = 0, what = "Another" }), "Merear Carriers is founded already")
  -- It is in the save; and a save from before there were any has none.
  local data, length = Core.Save(game)
  t.eq(Core.Hash(Core.Load(data, length)), Core.Hash(game))
  local plain = rich(1000)
  local file = Codec.Decode(Core.Save(plain))
  file.saveVersion = 44
  file.state.corporation = nil
  local old, oldLength = Codec.Encode(file)
  t.eq(Core.Hash(Core.Load(old, oldLength)), Core.Hash(plain))
  -- Not in space.
  t.ok((submit(plain, { kind = "Undock", actor = 0 })))
  plain.state.wallet = Corporation.FEE
  t.eq(refused(plain, { kind = "FoundCorporation", actor = 0, what = "Merear Carriers" }), "not docked")
end)

suite:Case("its founder pays into its account and takes out of it, which is neither earning nor spending", function(t)
  local game = founded(5000)
  local state = game.state
  t.eq(refused(game, { kind = "CorporationDeposit", actor = 0, quantity = 5001 }), "not enough credits")
  t.eq(refused(game, { kind = "CorporationDeposit", actor = 0, quantity = 0 }), "how much?")
  t.eq(refused(game, { kind = "CorporationDeposit", actor = 0, quantity = 1.5 }), "how much?")
  t.eq(refused(game, { kind = "CorporationWithdraw", actor = 0, quantity = 1 }), "the corporation has not that much")
  t.ok((submit(game, { kind = "CorporationDeposit", actor = 0, quantity = 4000 })))
  t.eq({ state.wallet, state.corporation.wallet }, { 1000, 4000 })
  t.eq({ state.journal[#state.journal].reason, state.journal[#state.journal].amount } :: { any }, { "to the corporation", -4000 } :: { any })
  local line = state.corporation.journal[1]
  t.eq({ #state.corporation.journal, line.reason, line.amount, line.balance } :: { any }, { 1, "from its founder", 4000, 4000 } :: { any })
  local changed = said(game, "CorporationChanged")
  t.eq({ #changed, changed[1].amount, changed[1].balance }, { 1, 4000, 4000 })
  t.ok((submit(game, { kind = "CorporationWithdraw", actor = 0, quantity = 1500 })))
  t.eq({ state.wallet, state.corporation.wallet }, { 2500, 2500 })
  t.eq({ state.corporation.journal[2].reason, state.journal[#state.journal].reason }, { "to its founder", "from the corporation" })
  t.eq({ state.corporation.earned, state.corporation.spent }, { 0, 0 })
  -- Money is neither made nor lost by it.
  t.eq(state.wallet + state.corporation.wallet, 5000)
end)

suite:Case("what the hired pilots cost comes out of its account, and the pilot's own wallet makes up what it is short", function(t)
  local game = founded(1000000)
  local state = game.state
  state.skills.leadership = 1
  local candidates = Core.Query.Candidates(game, state.player.home)
  local fee, wage = candidates[1].fee, candidates[1].wage
  -- Signed on with the account short of the fee: the account pays what it has, and the pilot the rest.
  t.ok((submit(game, { kind = "CorporationDeposit", actor = 0, quantity = fee - 100 })))
  local own = state.wallet
  t.ok((submit(game, { kind = "HirePilot", actor = 0, what = candidates[1].key })))
  t.eq({ state.corporation.wallet, own - state.wallet, state.corporation.spent }, { 0, 100, fee - 100 })
  t.eq(state.corporation.journal[#state.corporation.journal].reason, "hiring")
  -- A day on: the wage, out of the account, which has it now.
  t.ok((submit(game, { kind = "CorporationDeposit", actor = 0, quantity = wage * 3 })))
  own = state.wallet
  for _ = 1, Fleet.DAY + 2 do
    Core.Step(game)
  end
  t.eq({ state.corporation.wallet, state.wallet, #state.fleetIds }, { wage * 2, own, 1 })
  t.eq(state.corporation.journal[#state.corporation.journal].reason, "wages")
  t.eq(Core.Query.Corporation(game).wages, wage)
  -- With nothing in the account the pilot's own wallet pays, and nobody leaves.
  t.ok((submit(game, { kind = "CorporationWithdraw", actor = 0, quantity = wage * 2 })))
  own = state.wallet
  for _ = 1, Fleet.DAY do
    Core.Step(game)
  end
  t.eq({ state.corporation.wallet, own - state.wallet, #state.fleetIds }, { 0, wage, 1 })
  -- With nothing anywhere, they go.
  state.wallet = wage - 1
  for _ = 1, Fleet.DAY do
    Core.Step(game)
  end
  t.eq(#state.fleetIds, 0)
  -- The books: what was spent on them, the founder's own payments aside.
  t.eq({ state.corporation.spent, state.corporation.earned }, { fee - 100 + wage, 0 })
end)

suite:Case("a corporation has places for two more pilots than Leadership commands, and none for a pilot with no Leadership", function(t)
  local plain = rich(10000000)
  plain.state.skills.leadership = 1
  t.eq(Fleet.Max(plain.state), 1)
  local game = founded(10000000)
  local state = game.state
  state.skills.leadership = 0
  t.eq({ Fleet.Max(state), select(2, Core.Query.Candidates(game, state.player.home)) }, { 0, 0 })
  local candidates = Core.Query.Candidates(game, state.player.home)
  t.eq(refused(game, { kind = "HirePilot", actor = 0, what = candidates[1].key }), "needs Leadership 1")
  state.skills.leadership = 1
  t.eq(Fleet.Max(state), 1 + Corporation.STAFF)
  for index = 1, 3 do
    t.ok((submit(game, { kind = "HirePilot", actor = 0, what = candidates[index].key })), `the pilot {index}`)
  end
  t.eq(#state.fleetIds, 3)
  -- (the next day's candidates: there is no place for a fourth)
  for _ = 1, Fleet.DAY do
    Core.Step(game)
  end
  local more = Core.Query.Candidates(game, state.player.home)
  t.eq(refused(game, { kind = "HirePilot", actor = 0, what = more[1].key }), "Merear Carriers has places for 3 pilots and no more")
end)

suite:Case("what its pilots bring in is the corporation's: what they sell, and the bounties on what they destroy with the pilot elsewhere", function(t)
  for _, with in { true, false } do
    local game = if with then founded(1000) else rich(1000)
    local state = game.state
    local home = state.player.home
    -- A sale that is the business's (a hired pilot's), and one that is the pilot's own.
    Items.Add(state, "ore.ferrite", 2000, home, "hangar")
    local ore = Items.In(state, home, "hangar")
    local stack: State.Item? = nil
    for _, item in ore do
      stack = if item.type == "ore.ferrite" then item else stack
    end
    local own, account = state.wallet, state.corporation.wallet
    local made = Market.Sell(state, home, assert(stack), 1000, game.events, true)
    t.ok(made > 0)
    t.eq({ state.wallet - own, state.corporation.wallet - account }, if with then { 0, made } else { made, 0 })
    own, account = state.wallet, state.corporation.wallet
    local mine = Market.Sell(state, home, assert(stack), 500, game.events)
    t.eq({ state.wallet - own, state.corporation.wallet - account }, { mine, 0 })
    -- A pirate destroyed where the pilot is: the bounty is the pilot's. Where the pilot is not: half, the business's.
    t.ok((submit(game, { kind = "Undock", actor = 0 })))
    local me = state.balls[state.player.ship]
    local near = Pirates.Spawn(state, Pirates.SCOUT, me.system, me.x + 3000, me.y, me.z, me.grid)
    local far = Pirates.Spawn(state, Pirates.SCOUT, me.system, me.x + 5e8, me.y, me.z, 0)
    Space.AssignGrid(state, far)
    t.ok(far.grid ~= me.grid)
    own, account = state.wallet, state.corporation.wallet
    Aftermath.Destroy(state, near.id, state.player.ship, game.events)
    t.eq({ state.wallet - own, state.corporation.wallet - account }, { Pirates.SCOUT.bounty, 0 })
    own, account = state.wallet, state.corporation.wallet
    Aftermath.Destroy(state, far.id, state.player.ship, game.events)
    local half = math.floor(Pirates.SCOUT.bounty * Aftermath.AWAY)
    t.eq({ state.wallet - own, state.corporation.wallet - account }, if with then { 0, half } else { half, 0 })
    -- The books say what was earned.
    t.eq({ state.corporation.earned, state.corporation.spent }, { if with then made + half else 0, 0 })
    if with then
      local journal = state.corporation.journal
      t.eq({ journal[#journal - 1].reason, journal[#journal].reason }, { "market sale", "bounty" })
    else
      t.eq(#state.corporation.journal, 0)
    end
  end
end)

return suite
