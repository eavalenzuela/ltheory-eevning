--!strict
-- The pilot's corporation (Assets/Corporation).

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Corporation = require("@lt/Core/Assets/Corporation")
local Items = require("@lt/Core/Assets/Items")
local Market = require("@lt/Core/Assets/Market")
local Members = require("@lt/Core/Assets/Members")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Space = require("@lt/Core/Tactical/Space")
local Starbases = require("@lt/Core/Assets/Starbases")
local State = require("@lt/Core/Kernel/State")
local Stations = require("@lt/Core/Assets/Stations")
local Structures = require("@lt/Core/Data/Structures")
local System = require("@lt/Core/Describe/System")
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
-- A member of the corporation made at once, a fighter of grade 3, who
-- is paid nothing by the hour (share 0) so that a case counts its own
-- money: their key, to be asked into the fleet (since 2026-11-21 the
-- fleet is the corporation's members: nobody is hired).
local function crewman(game: Core.Game): string
  game.state.membership.share = 0
  local member = Members.Recruit(game.state, `Crewman {#game.state.membership.memberIds + 1}`, "fighter", 3, {})
  return `member:{member.id}`
end

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

-- The stack of a type in a station's hangar.
local function stack(game: Core.Game, station: number, type: string): State.Item
  for _, item in Items.In(game.state, station, "hangar") do
    if item.type == type then
      return item
    end
  end
  error(`no {type} in the hangar`)
end

suite:Case("its books are kept by head: what came in and went out under each, fuel and moon material under their own", function(t)
  local game = founded(5000000)
  local state = game.state
  local home = state.player.home
  local books = state.corporation.books
  -- What its founder pays in is under no head.
  t.ok((submit(game, { kind = "CorporationDeposit", actor = 0, quantity = 2000000 })))
  t.eq(books, {})
  t.eq(#Core.Query.Corporation(game).heads, 0)
  -- A hired pilot's sale of ore, and of what a drill brought up; their buying of fuel, and of anything else.
  Items.Add(state, "ore.ferrite", 1000, home, "hangar")
  Items.Add(state, "moon.cadmite", 100, home, "hangar")
  local ore = Market.Sell(state, home, stack(game, home, "ore.ferrite"), 1000, game.events, true)
  local moon = Market.Sell(state, home, stack(game, home, "moon.cadmite"), 100, game.events, true)
  local fuel = Market.Buy(state, home, "fuel.block", 50, home, "hangar", game.events, true)
  local other = Market.Buy(state, home, "mineral.iron", 100, home, "hangar", game.events, true)
  t.ok(ore > 0 and moon > 0 and fuel > 0 and other > 0)
  t.eq({ books["market sale"], books["moon sale"], books.fuel, books["market purchase"] }, { ore, moon, -fuel, -other })
  local journal = state.corporation.journal
  t.eq({ journal[#journal - 2].reason, journal[#journal - 1].reason }, { "moon sale", "fuel" })
  -- The pilot's own trade is under none of them.
  Items.Add(state, "ore.ferrite", 10, home, "hangar")
  Market.Sell(state, home, stack(game, home, "ore.ferrite"), 10, game.events)
  t.eq(books["market sale"], ore)
  -- The books list the heads with anything under them, in their own order, and they add up to what was made.
  local info = Core.Query.Corporation(game)
  local names: { string } = {}
  local sum = 0
  for _, head in info.heads do
    table.insert(names, head.name)
    sum += head.amount
  end
  t.eq(names, { "Sales", "Moon material sold", "Fuel bought", "Other purchases" })
  t.eq(sum, info.earned - info.spent)
  t.eq(sum, ore + moon - fuel - other)
  -- In the save. And what a save from before the heads had earned and spent is under "earlier".
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq({ Core.Hash(loaded), loaded.state.corporation.books.fuel } :: { any }, { Core.Hash(game), -fuel } :: { any })
  local file = Codec.Decode(data, length)
  file.saveVersion = 58
  file.state.corporation.books = nil
  local old, oldLength = Codec.Encode(file)
  local before = Core.Query.Corporation(Core.Load(old, oldLength))
  t.eq(before.heads, { { name = "Earlier earnings", amount = ore + moon }, { name = "Earlier spending", amount = -(fuel + other) } })
end)

-- The M7 exit: the corporation runs a mining and hauling operation for
-- fifty game-hours, and its books balance. A miner at a belt brings ore
-- in to the station nearest it. A hauler carries it from there to a
-- market and sells it. A tower with a drill runs beside. Every credit that
-- moved is under a head, every unit of ore that was cut is somewhere
-- or was sold, and the tower's count is what its tank and hangar say.
-- How many of a type a station holds in a place.
local function kept(game: Core.Game, station: number, place: string, type: string): number
  local units = 0
  for _, item in Items.In(game.state, station, place) do
    units += if item.type == type then item.quantity else 0
  end
  return units
end

-- The first stack of a type in a place at a station.
local function stackIn(game: Core.Game, station: number, place: string, type: string): State.Item
  for _, item in Items.In(game.state, station, place) do
    if item.type == type then
      return item
    end
  end
  error(`no {type} in the {place} there`, 2)
end

suite:Case("the corporation has a hangar of its own at a station, beside the pilot's: things are given to it and taken back, docked", function(t)
  -- With no corporation there is none.
  local plain = rich(100000)
  local home = plain.state.player.home
  t.eq(refused(plain, { kind = "MoveItems", actor = 0, item = stackIn(plain, home, "hangar", "ammo.emp").id, to = "corporate" }),
    "there is no corporation to give it to")
  t.eq(Corporation.Store(plain.state), "hangar")

  local game = founded(100000)
  local state = game.state
  t.eq(Corporation.Store(state), "corporate")
  local had = kept(game, home, "hangar", "ammo.emp")
  t.ok(had >= 300, "the starter kit should have rounds to give")
  t.ok((submit(game, { kind = "MoveItems", actor = 0, item = stackIn(game, home, "hangar", "ammo.emp").id, to = "corporate", quantity = 200 })))
  t.eq({ kept(game, home, "corporate", "ammo.emp"), kept(game, home, "hangar", "ammo.emp") }, { 200, had - 200 })
  local moved = said(game, "ItemsMoved")
  t.eq({ #moved, moved[1].to, moved[1].quantity } :: { any }, { 1, "corporate", 200 } :: { any })
  -- (a second lot joins the first: one stack of a type to a hangar)
  t.ok((submit(game, { kind = "MoveItems", actor = 0, item = stackIn(game, home, "hangar", "ammo.emp").id, to = "corporate", quantity = 50 })))
  t.eq(#Items.In(state, home, "corporate"), 1)
  local theirs = stackIn(game, home, "corporate", "ammo.emp")
  t.eq(theirs.quantity, 250)
  t.eq(refused(game, { kind = "MoveItems", actor = 0, item = theirs.id, to = "corporate" }), "already in the corporation's hangar")
  -- Back out of it: to the pilot's hangar, and straight into the hold.
  t.ok((submit(game, { kind = "MoveItems", actor = 0, item = theirs.id, to = "hangar", quantity = 100 })))
  t.ok((submit(game, { kind = "MoveItems", actor = 0, item = theirs.id, to = "cargo", quantity = 30 })))
  t.eq({ kept(game, home, "corporate", "ammo.emp"), kept(game, home, "hangar", "ammo.emp"), kept(game, state.player.ship, "cargo", "ammo.emp") },
    { 120, had - 150, 30 })
  -- What is in it is to hand like anything else at the station: a module is fitted straight from it.
  local module = stackIn(game, home, "hangar", "shield.extender.small")
  t.ok((submit(game, { kind = "MoveItems", actor = 0, item = module.id, to = "corporate" })))
  t.ok(refused(game, { kind = "Fit", actor = 0, item = stackIn(game, home, "corporate", "shield.extender.small").id }) ~= "that item is not here")
  -- It is the station's: out in space it is nobody's to move.
  local data, length = Core.Save(game)
  t.eq(Core.Hash(Core.Load(data, length)), Core.Hash(game))
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  for _ = 1, 30 do
    Core.Step(game)
  end
  t.eq(refused(game, { kind = "MoveItems", actor = 0, item = stackIn(game, home, "corporate", "ammo.emp").id, to = "hangar" }), "not docked")
end)

suite:Case("what is sold out of the corporation's hangar is paid to the corporation, under sales; an order is placed from the pilot's own", function(t)
  local game = founded(100000)
  local state = game.state
  local home = state.player.home
  t.ok((submit(game, { kind = "MoveItems", actor = 0, item = stackIn(game, home, "hangar", "ammo.emp").id, to = "corporate", quantity = 300 })))
  local theirs = stackIn(game, home, "corporate", "ammo.emp")
  t.eq(refused(game, { kind = "PlaceOrder", actor = 0, to = "sell", item = theirs.id, quantity = 100, price = 50 }),
    "an order is placed from your own hangar")
  Core.TakeEvents(game)
  local wallet, account = state.wallet, state.corporation.wallet
  t.ok((submit(game, { kind = "SellNow", actor = 0, item = theirs.id, quantity = 100 })))
  local sold = said(game, "Sold")
  t.eq(#sold, 1)
  local revenue: number = sold[1].revenue
  t.ok(revenue > 0, "the rounds fetched nothing")
  t.eq({ state.wallet - wallet, state.corporation.wallet - account, state.corporation.books["market sale"] }, { 0, revenue, revenue })
  t.eq(kept(game, home, "corporate", "ammo.emp"), 200)
  -- And the pilot's own rounds are the pilot's own, as they were.
  t.ok((submit(game, { kind = "SellNow", actor = 0, item = stackIn(game, home, "hangar", "ammo.emp").id, quantity = 100 })))
  t.ok(state.wallet > wallet and state.corporation.wallet == account + revenue, "the pilot's own sale was not paid to the pilot")
end)

suite:Case("a hired pilot works out of the corporation's hangar and leaves the pilot's own alone", function(t)
  local game = founded(2000000)
  local state = game.state
  local home = state.player.home
  -- A hauler, with a hired pilot in it.
  local mule = Space.NewShip(state, "industrial.mizumushi", "Mule", "player", home)
  state.skills.leadership = 1
  t.ok((submit(game, { kind = "InviteToFleet", actor = 0, what = crewman(game) })))
  local wing = state.fleet[state.fleetIds[#state.fleetIds]]
  t.ok((submit(game, { kind = "AssignShip", actor = 0, pilot = wing.id, target = mule.id })))
  -- Ore at home in both hangars, and the hauler set to carry ore to the nearest other station.
  local from = Space.Object(state, home) :: System.Object
  local other, least = 0, math.huge
  for _, object in Space.Describe(state, 1).objects do
    if object.kind == "station" and object.id ~= home and Space.Distance(from :: any, object :: any) < least then
      other, least = object.id, Space.Distance(from :: any, object :: any)
    end
  end
  assert(other ~= 0, "the home system wants a second station")
  Items.Add(state, "ore.ferrite", 400, home, "hangar")
  Items.Add(state, "ore.ferrite", 700, home, "corporate")
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "haul", pilot = wing.id, target = other, type = "ore" })))
  local delivered = 0
  for _ = 1, 4000 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      if event.kind == "HaulDelivered" then
        delivered += event.units
      end
    end
    if delivered > 0 then
      break
    end
  end
  -- The corporation's ore went, to the corporation's hangar there. The pilot's own did not move.
  t.eq(delivered, 700)
  t.eq({ kept(game, home, "hangar", "ore.ferrite"), kept(game, home, "corporate", "ore.ferrite") }, { 400, 0 })
  t.eq({ kept(game, other, "corporate", "ore.ferrite"), kept(game, other, "hangar", "ore.ferrite") }, { 700, 0 })
end)

suite:Case("a tower's drill fills the corporation's hangar there, its one silo counts both hangars, and a dark tower burns the corporation's fuel first", function(t)
  local game = founded(100000)
  local state = game.state
  local moon: System.Object? = nil
  for _, object in Space.Describe(state, 1).objects do
    if object.kind == "moon" and moon == nil and Starbases.Deposit(state, object.id) then
      moon = object
    end
  end
  local under = assert(moon, "the home system wants a moon with something under it")
  local small = Structures.towerById["tower.vessari.small"]
  local base = Starbases.Raise(state, 1, under, small, "player", under.x + under.radius * 5, under.y, under.z)
  local starbase = state.starbases[base]
  starbase.ready, starbase.burnt, starbase.drilled, starbase.fuel = state.tick, state.tick, state.tick, 600
  table.insert(starbase.modules, { type = Structures.DRILL, ready = state.tick })
  local deposit = assert(Starbases.Deposit(state, under.id))
  local material = deposit.material.id
  -- (some of it the pilot's own already: the silo is one)
  Items.Add(state, material, 100, base, "hangar")
  for _ = 1, 3600 + 5 do
    Core.Step(game)
  end
  local hour = Starbases.Drilling(state, starbase).perHour
  t.eq({ kept(game, base, "corporate", material), kept(game, base, "hangar", material) }, { hour, 100 })
  t.eq(Starbases.Drilling(state, starbase).stored, hour + 100)
  -- A tank run dry: the corporation's fuel is burnt before the pilot's own.
  Items.Add(state, Structures.FUEL.id, 500, base, "hangar")
  Items.Add(state, Structures.FUEL.id, 500, base, "corporate")
  starbase.fuel = 0
  Core.Step(game)
  local day = small.fuel * 24
  t.eq({ starbase.fuel, kept(game, base, "corporate", Structures.FUEL.id), kept(game, base, "hangar", Structures.FUEL.id) },
    { day, 500 - day, 500 })
end)

suite:Case("fifty game-hours of mining and hauling with a tower run beside, and the books balance", function(t)
  local game = founded(30000000)
  local state = game.state
  local home = state.player.home
  local corporation = state.corporation
  state.skills.leadership = 2
  t.ok((submit(game, { kind = "CorporationDeposit", actor = 0, quantity = 5000000 })))
  local digger = Space.NewShip(state, "frigate.courier", "Digger", "player", home)
  Items.Equip(state, digger.id, "miner.small", nil)
  Items.Equip(state, digger.id, "miner.small", nil)
  local mule = Space.NewShip(state, "industrial.mizumushi", "Mule", "player", home)
  local function hire(ship: State.Ship): State.Wingman
    assert(submit(game, { kind = "InviteToFleet", actor = 0, what = crewman(game) }))
    local wing = state.fleet[state.fleetIds[#state.fleetIds]]
    wing.skill = 2
    assert(submit(game, { kind = "AssignShip", actor = 0, pilot = wing.id, target = ship.id }))
    return wing
  end
  local miner, carrier = hire(digger), hire(mule)

  -- Out to a belt with both, and the miner set to work: what they cut goes in to the station nearest the belt.
  local function waitFor(limit: number, holds: () -> boolean): boolean
    for _ = 1, limit do
      if holds() then
        return true
      end
      Core.Step(game)
    end
    return holds()
  end
  local rocks = 0
  for _, object in Space.Describe(state, 1).objects do
    rocks = if object.kind == "belt" and rocks == 0 then object.id else rocks
  end
  assert(rocks ~= 0, "the home system wants a belt")
  assert(submit(game, { kind = "Undock", actor = 0 }))
  assert(submit(game, { kind = "WarpTo", actor = 0, target = rocks }))
  assert(waitFor(900, function()
    local me, theirs = state.balls[state.player.ship], state.balls[digger.id]
    return me ~= nil and me.grid == rocks and theirs ~= nil and theirs.grid == rocks
  end), "the miner did not get to the belt")
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "mine" })))
  t.eq(miner.order, "mine")
  local depot = miner.base
  -- In to that station with the hauler, who is set to carry the ore from there to the nearest other market and sell it.
  local from = Space.Object(state, depot) :: System.Object
  local market, least = 0, math.huge
  for _, object in Space.Describe(state, 1).objects do
    if object.kind == "station" and object.id ~= depot and Stations.Has(state, object.id, "market")
      and Space.Distance(from :: any, object :: any) < least then
      market, least = object.id, Space.Distance(from :: any, object :: any)
    end
  end
  assert(market ~= 0, "the home system wants a market that is not where the ore comes in")
  assert(submit(game, { kind = "Dock", actor = 0, target = depot }))
  assert(waitFor(1500, function()
    return state.ships[state.player.ship].docked == depot and mule.docked == depot
  end), "the pilot and the hauler did not get in")
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "sell", pilot = carrier.id })))
  t.ok((submit(game, { kind = "FleetOrder", actor = 0, what = "haul", pilot = carrier.id, target = market, type = "ore" })))

  -- A tower at a moon with something under it, lit, its drill online.
  local moon: System.Object? = nil
  for _, object in Space.Describe(state, 1).objects do
    if object.kind == "moon" and moon == nil and Starbases.Deposit(state, object.id) then
      moon = object
    end
  end
  local under = assert(moon, "the home system wants a moon with something under it")
  local small = Structures.towerById["tower.vessari.small"]
  local base = Starbases.Raise(state, 1, under, small, "player", under.x + under.radius * 5, under.y, under.z)
  local starbase = state.starbases[base]
  starbase.ready, starbase.burnt, starbase.drilled, starbase.fuel = state.tick, state.tick, state.tick, 600
  table.insert(starbase.modules, { type = Structures.DRILL, ready = state.tick })
  local deposit = assert(Starbases.Deposit(state, under.id))

  -- Where every unit of ore is: the two holds, and the hangars at the two stations (the
  -- corporation's, where its pilots put it, and the pilot's own, where none of it should be).
  local function held(): { [string]: number }
    local found: { [string]: number } = {}
    for _, place in { { digger.id, "cargo" }, { mule.id, "cargo" }, { depot, "corporate" }, { market, "corporate" },
      { depot, "hangar" }, { market, "hangar" } } :: { { any } } do
      for _, item in Items.In(state, place[1], place[2]) do
        if string.sub(item.type, 1, 4) == "ore." then
          found[item.type] = (found[item.type] or 0) + item.quantity
        end
      end
    end
    return found
  end
  local ORES = { "ore.ferrite", "ore.cuprite", "ore.silicate", "ore.titanite", "ore.aurite", "ore.iridite" }
  Core.TakeEvents(game)
  local wallet, account, fuel = state.wallet, corporation.wallet, starbase.fuel
  -- (they stay the fifty hours: members stay until let go, 2026-11-23)
  local made = corporation.earned - corporation.spent
  local under0: { [string]: number } = table.clone(corporation.books)
  local before = held()
  -- (what the miner had cut already and has aboard: brought in during the run, and not cut in it)
  local aboard = 0
  for _, item in Items.In(state, digger.id, "cargo") do
    aboard += if string.sub(item.type, 1, 4) == "ore." then item.quantity else 0
  end
  local paid, posted, all = 0, {} :: { [string]: number }, 0
  local mined, sold = {} :: { [string]: number }, {} :: { [string]: number }
  local revenue, carried, brought, paydays = 0, 0, 0, 0
  for _ = 1, 50 * 3600 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      if event.kind == "WalletChanged" then
        paid += event.amount
      elseif event.kind == "CorporationChanged" then
        posted[event.reason] = (posted[event.reason] or 0) + event.amount
        all += event.amount
        paydays += if event.reason == "wages" then 1 else 0
      elseif event.kind == "Mined" then
        mined[event.ore] = (mined[event.ore] or 0) + event.units
      elseif event.kind == "Sold" then
        sold[event.type] = (sold[event.type] or 0) + event.quantity
      elseif event.kind == "HaulDelivered" then
        revenue += event.revenue
        carried += event.units
      elseif event.kind == "OreDelivered" then
        brought += event.units
      end
    end
  end

  -- The operation ran: ore was cut, brought in, carried and sold.
  t.ok(brought > 0 and carried > 0 and revenue > 0, `{brought} brought in, {carried} carried, {revenue} made`)
  -- Every credit: the account paid for all of it, and the pilot's own wallet was not touched.
  t.eq({ paid, state.wallet - wallet }, { 0, 0 })
  t.eq(corporation.wallet - account, all)
  -- Under a head, each: what the books have under it is what was posted for it, and they add up to what was made.
  local sum = 0
  for _, head in Corporation.HEADS do
    local reason = head.reason
    t.eq((corporation.books[reason] or 0) - (under0[reason] or 0), posted[reason] or 0, reason)
    sum += posted[reason] or 0
  end
  t.eq(sum, all, "something was posted under no head")
  t.eq((corporation.earned - corporation.spent) - made, all)
  -- (no wages: since 2026-11-21 the fleet is the corporation's members, paid by the hour, and here at
  -- a share of nothing; and what the hauler sold is all that came in)
  t.eq({ paydays, posted.wages or 0 } :: { any }, { 0, 0 } :: { any })
  t.eq({ posted["market sale"], carrier.earned }, { revenue, revenue })
  for _, head in Core.Query.Corporation(game).heads do
    t.ok(string.sub(head.name, 1, 7) ~= "Earlier", "the books have something under no head")
  end
  -- Every unit of ore: what was cut is in a hold or a hangar, or was sold.
  local after = held()
  local cut = 0
  for _, ore in ORES do
    t.eq((after[ore] or 0) - (before[ore] or 0), (mined[ore] or 0) - (sold[ore] or 0), ore)
    cut += mined[ore] or 0
  end
  local counted = 0
  for _, units in mined do
    counted += units
  end
  t.eq(counted, cut, "an ore was cut that the count does not know")
  t.ok(cut + aboard >= brought and brought >= carried, `{cut} cut (and {aboard} aboard), {brought} brought in, {carried} carried`)
  -- The tower: what it has burnt is what has gone from its tank, and what it has brought up is
  -- in the corporation's hangar there, none of it in the pilot's own.
  t.eq({ starbase.used, fuel - starbase.fuel }, { 50 * small.fuel, 50 * small.fuel })
  local stored = 0
  for _, item in Items.In(state, base, "corporate") do
    stored += if item.type == deposit.material.id then item.quantity else 0
  end
  t.eq(#Items.In(state, base, "hangar"), 0)
  for _, place in { depot, market } do
    for _, item in Items.In(state, place, "hangar") do
      t.ok(string.sub(item.type, 1, 4) ~= "ore.", "a hired pilot put ore in the pilot's own hangar")
    end
  end
  t.eq({ starbase.raised, starbase.robbed }, { stored, 0 })
  t.ok(stored > 0, "the drill brought nothing up")
  local tower = Core.Query.Corporation(game).towers[1]
  t.eq({ tower.id, tower.running.usedWorth, tower.running.raisedWorth },
    { base, starbase.used * Structures.FUEL.basePrice, stored * deposit.material.basePrice })
  -- And it is all in the save.
  local data, length = Core.Save(game)
  t.eq(Core.Hash(Core.Load(data, length)), Core.Hash(game))
  print(`     books: in fifty hours {cut} ore cut, {brought} brought in, {carried} carried and sold for {revenue}; `
    .. `the tower burnt {starbase.used} blocks and brought up {stored}`)
end)

return suite
