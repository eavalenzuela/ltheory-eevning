--!strict
-- Contracts: a station's board, through the Core's front door.

local Attributes = require("@lt/Core/Attributes")
local Blueprints = require("@lt/Core/Data/Blueprints")
local Codec = require("@lt/Core/Persist/Codec")
local Constants = require("@lt/Core/Data/Constants")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Space = require("@lt/Core/Tactical/Space")
local Contracts = require("@lt/Core/Assets/Contracts")
local Core = require("@lt/Core/Api")
local Items = require("@lt/Core/Assets/Items")
local Market = require("@lt/Core/Assets/Market")
local Modules = require("@lt/Core/Data/Modules")
local Ships = require("@lt/Core/Data/Ships")
local State = require("@lt/Core/Kernel/State")
local Fits = require("@lt/Core/Fits")
local Skills = require("@lt/Core/Data/Skills")
local Test = require("@lt/Tool/Test")
local Types = require("@lt/Core/Data/Types")

local suite = Test.Suite("Contracts")

local DAY, HOUR = 86400, 3600

local function newGame(): (Core.Game, number)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  return game, game.state.player.home
end

local function order(t: Test.Context, game: Core.Game, command: State.Command)
  command.actor = game.state.player.ship
  local ok, reason = Core.Submit(game, command)
  t.ok(ok, `{command.kind} was refused: {tostring(reason)}`)
  Core.Step(game)
end

local function refused(game: Core.Game, command: State.Command): string?
  command.actor = game.state.player.ship
  local ok, reason = Core.Validate(game, command)
  return if ok then "(accepted)" else reason
end

local function hangar(game: Core.Game, type: string): number
  local count = 0
  for _, item in Items.In(game.state, game.state.player.home, "hangar") do
    if item.type == type then
      count += item.quantity
    end
  end
  return count
end

local function stack(game: Core.Game, type: string): State.Item
  for _, item in Items.In(game.state, game.state.player.home, "hangar") do
    if item.type == type then
      return item
    end
  end
  error(`no {type} in the hangar`, 2)
end

-- So many hours at the boards alone: what Core.Step does for them, an
-- hour at a time, and what came of the listings in them (not the
-- wallet's own events).
local function hours(game: Core.Game, n: number): { Contracts.Event }
  local state = game.state
  local events: { Contracts.Event } = {}
  state.tick -= state.tick % HOUR
  for _ = 1, n do
    state.tick += HOUR
    Contracts.Step(state, events)
  end
  local came: { Contracts.Event } = {}
  for _, event in events do
    if string.sub(event.kind, 1, 8) == "Contract" then
      table.insert(came, event)
    end
  end
  return came
end

local function lot(game: Core.Game, station: number, side: string, slot: number): Contracts.Lot
  return assert(Contracts.Lot(game.state, station, side, slot), `no {side} {slot} on the board`)
end

suite:Case("a station's board has lots for sale and lots wanted: the same all day, and others tomorrow", function(t)
  local game, home = newGame()
  local state = game.state
  local board = Contracts.Board(state, home)
  t.eq(#board, Contracts.OFFERS + Contracts.WANTS)
  t.eq(Contracts.Board(state, home), board, "asked again, it is the same board")
  -- A hull with what it would be fitted with, and something to fire.
  local ship = board[1]
  local hull = assert(Ships.byId[ship.stacks[1].type], "the first lot should be a hull's")
  t.eq({ ship.side, ship.slot, ship.stacks[1].quantity, ship.title } :: { any }, { "offer", 1, 1, `{hull.name}, fitted out` } :: { any })
  t.ok(#ship.stacks >= 3, "a hull, its fit and its rounds")
  t.ok(not hull.restricted and not hull.rare and hull.tech ~= 2 and not Ships.Capital(hull.class), hull.id)
  -- A copy of a blueprint.
  local copy = board[2]
  local blueprint, isCopy = Blueprints.Of(copy.stacks[1].type)
  t.ok(blueprint ~= nil and isCopy and #copy.stacks == 1, "the second lot should be a copy")
  -- A few of a module no station sells.
  local few = board[3]
  local module = assert(Modules.byId[few.stacks[1].type], "the third lot should be modules")
  t.ok(Types.Info(module.id).scarce and few.stacks[1].quantity >= 1 and few.stacks[1].quantity <= 3)
  -- And two lots wanted, of what nobody sells: paid for at more than its base price.
  for index = Contracts.OFFERS + 1, #board do
    local want = board[index]
    local info = Types.Info(want.stacks[1].type)
    t.eq({ want.side, want.slot, #want.stacks } :: { any }, { "want", index - Contracts.OFFERS, 1 } :: { any })
    t.ok(info.scarce and Market.Index(info.id) ~= nil, info.id)
    t.ok(want.price >= want.worth * 1.1 - 1 and want.price <= want.worth * 1.4, `{want.title} pays {want.price} for {want.worth}`)
  end

  -- Every lot, over a month and at every station of the first system: well made, and priced by what it is.
  local stations: { number } = {}
  for _, object in Core.Query.Objects(game, 1) do
    if object.kind == "station" then
      table.insert(stations, object.id)
    end
  end
  t.ok(#stations >= 2)
  local titles: { [string]: boolean } = {}
  local kinds = 0
  for day = 0, 29 do
    state.tick = day * DAY + 5
    for _, station in stations do
      local lots = Contracts.Board(state, station)
      t.eq(#lots, Contracts.OFFERS + Contracts.WANTS)
      for _, each in lots do
        t.ok(each.title ~= "" and #each.stacks > 0 and each.price > 0, each.key)
        t.eq(each.worth, Contracts.Base(each.stacks), each.key)
        for _, stack in each.stacks do
          t.ok(Types.Get(stack.type) ~= nil and stack.quantity >= 1 and stack.quantity % 1 == 0, `{each.key}: {stack.type}`)
        end
        local share = each.price / each.worth
        if each.side == "offer" and each.slot == 1 then
          t.ok(share >= 0.88 and share <= 1.07, `{each.title} at {share} of its worth`)
        elseif each.side == "offer" and each.slot == 2 then
          t.ok(share >= 0.8 and share <= 2.6, `{each.title} at {share} of its worth`)
        elseif each.side == "offer" then
          t.ok(share >= 1.0 and share <= 1.51, `{each.title} at {share} of its worth`)
        end
        if not titles[each.title] then
          titles[each.title] = true
          kinds += 1
        end
      end
    end
  end
  t.ok(kinds > 60, `a month of boards should have many different lots, and has {kinds}`)
  -- Tomorrow's board is not today's, and what is no station has none.
  state.tick = 5
  local today = Contracts.Board(state, home)
  state.tick = DAY + 5
  local tomorrow = Contracts.Board(state, home)
  t.ok(today[1].key ~= tomorrow[1].key)
  t.eq(Contracts.Board(state, 4242), {})
end)

suite:Case("a lot for sale is paid for and is in the hangar, and nobody else has it that day", function(t)
  local game, home = newGame()
  local state = game.state
  -- (a lot of a few modules: a hull bought fitted out is a ship, below)
  local ship = lot(game, home, "offer", 3)
  t.eq(refused(game, { kind = "AcceptContract", actor = 0, target = 3 }), if ship.price > state.wallet then "not enough credits" else "(accepted)")
  state.wallet = ship.price + 1000
  t.eq(refused(game, { kind = "AcceptContract", actor = 0, target = 9 }), "that is not on the board")
  local before: { number } = {}
  for index, stack in ship.stacks do
    before[index] = hangar(game, stack.type)
  end
  Core.TakeEvents(game)
  order(t, game, { kind = "AcceptContract", actor = 0, target = 3 })
  t.eq({ state.wallet, state.journal[#state.journal].reason } :: { any }, { 1000, "contract" } :: { any })
  for index, stack in ship.stacks do
    t.eq(hangar(game, stack.type) - before[index], stack.quantity, stack.type)
  end
  local accepted: any = nil
  for _, event in Core.TakeEvents(game) do
    accepted = if event.kind == "ContractAccepted" then event else accepted
  end
  t.eq({ accepted.title, accepted.price, accepted.station } :: { any }, { ship.title, ship.price, home } :: { any })
  -- It is off the board for the day, and the rest of the board is as it was.
  t.eq(Contracts.Lot(state, home, "offer", 3), nil)
  t.eq(#Contracts.Board(state, home), Contracts.OFFERS + Contracts.WANTS - 1)
  t.eq(refused(game, { kind = "AcceptContract", actor = 0, target = 3 }), "that is not on the board")
  -- Tomorrow there is another in its place, and yesterday's taking is forgotten when the next is taken.
  state.tick = DAY + 10
  local next = lot(game, home, "offer", 3)
  state.wallet = next.price
  order(t, game, { kind = "AcceptContract", actor = 0, target = 3 })
  t.eq({ #state.contractsTaken, state.wallet }, { 1, 0 })
  -- From space too, naming the station: what is bought is in the hangar
  -- there (the owner, 2026-11-16: "you can buy any contract, from any
  -- location"). Naming none, out of a station, there is nothing to take.
  order(t, game, { kind = "Undock", actor = 0 })
  for _ = 1, 20 do
    Core.Step(game)
  end
  t.eq(refused(game, { kind = "AcceptContract", actor = 0, target = 2 }), "not docked, and no station named")
  local far = lot(game, home, "offer", 2)
  state.wallet = far.price
  local had = 0
  for _, item in Items.In(state, home, "hangar") do
    had += if item.type == far.stacks[1].type then item.quantity else 0
  end
  order(t, game, { kind = "AcceptContract", actor = 0, target = 2, station = home })
  local now = 0
  for _, item in Items.In(state, home, "hangar") do
    now += if item.type == far.stacks[1].type then item.quantity else 0
  end
  t.eq({ state.wallet, now - had } :: { any }, { 0, far.stacks[1].quantity } :: { any }, "bought from space, delivered to the hangar there")
  t.eq(Items.In(state, state.player.ship, "cargo") ~= nil, true)
end)

suite:Case("the alien peoples' prints are on boards now and then: the Vail's and the Nimia's in their own space, the Drowned's outside secure space", function(t)
  -- (the owner, 2026-11-16: their blueprints "should also be on contracts")
  local game = newGame()
  local state = game.state
  local ticks = math.ceil(86400 / Constants.TICK)
  local seen: { [string]: number } = {}
  for _, people in { "vail", "nimia", "drowned" } do
    t.ok(#Blueprints.OfPeople(people).hulls > 0, `{people} have hull prints`)
  end
  -- (some boards of the galaxy, over many days)
  local stations = Contracts.Stations(state)
  for index = 1, #stations, math.max(1, #stations // 40) do
    local station = stations[index]
    local node = state.galaxy.systems[Space.SystemOf(state, station)]
    for day = 0, 2999 do
      local people = Contracts.Alien(state, station, day)
      if people and not Contracts.Pirated(state, station, day) then
        seen[people] = (seen[people] or 0) + 1
        if people == "drowned" then
          t.ok(Galaxy.Band(node.security) ~= "secure", "a Drowned print in secure space")
        else
          t.eq(node.owner, people, "a print of theirs outside their space")
        end
        if (seen[people] or 0) == 1 then
          state.tick = day * ticks
          local lot = assert(Contracts.Lot(state, station, "offer", 2))
          local print, copy = Blueprints.Of(lot.stacks[1].type)
          t.ok(print ~= nil and not copy, lot.title)
          local theirs = Blueprints.OfPeople(people)
          t.ok(table.find(theirs.hulls, assert(print)) ~= nil or table.find(theirs.towers, assert(print)) ~= nil, `{lot.title} is {people}'s`)
          t.ok(lot.price > lot.worth, "an alien print should be dear")
        end
      end
    end
  end
  t.ok((seen.drowned or 0) > 0, "no Drowned print on any board looked at")
end)

suite:Case("a hull fitted out on a board is mostly of better makes than the plain, now and then with an officer's module, and always fits", function(t)
  -- (the owner, 2026-11-18: "should lean towards them being t2 or meta
  -- fittings (faction or dead space, with a rare officer module, e.g. one
  -- in every 50 contracts might have one officer mod)")
  local game = newGame()
  local state = game.state
  local ticks = math.ceil(86400 / Constants.TICK)
  local stations = Contracts.Stations(state)
  local lots, modules, plain, officers = 0, 0, 0, 0
  local kinds: { [string]: number } = {}
  for index = 1, #stations, math.max(1, #stations // 40) do
    for day = 0, 99 do
      state.tick = day * ticks
      local lot = Contracts.Lot(state, stations[index], "offer", 1)
      if lot and lot.fitted then
        lots += 1
        local hull = Ships.byId[lot.stacks[1].type]
        local fit = assert(lot.fit)
        local standard = Fits.Standard(hull)
        t.eq(#fit, #standard, `{lot.title}: the standard fit's layout`)
        t.ok((Attributes.Check(hull, fit)), `{lot.title} does not fit`)
        local had = 0
        for _, id in fit do
          local module = Modules.byId[id]
          modules += 1
          if module.officer then
            had += 1
            kinds.officer = (kinds.officer or 0) + 1
          elseif module.tech == 2 then
            kinds.tech2 = (kinds.tech2 or 0) + 1
          elseif module.site then
            kinds.site = (kinds.site or 0) + 1
          elseif module.meta == 3 then
            kinds.people = (kinds.people or 0) + 1
          else
            plain += 1
          end
        end
        t.ok(had <= 1, `{lot.title} has {had} officer's modules`)
        officers += had
      end
    end
  end
  t.ok(lots >= 400, `only {lots} fitted lots looked at`)
  t.ok(plain < modules * 0.3, `{plain} of {modules} modules are plain`)
  t.ok((kinds.tech2 or 0) > 0 and (kinds.site or 0) > 0 and (kinds.people or 0) > 0, "some of each make")
  -- (one lot in fifty: between one in a hundred and one in twenty-five, of so many)
  t.ok(officers >= lots / 100 and officers <= lots / 25, `{officers} officer's modules in {lots} lots`)
  state.tick = 0
end)

suite:Case("a hull bought fitted out is a ship at the station, assembled, fitted and loaded; and it does not undock with what the pilot cannot use", function(t)
  -- (the owner, 2026-11-16: "it should already be assembled with the
  -- modules fitted. You just shouldn't be able to undock with it if some
  -- of the modules you can't use")
  local game, home = newGame()
  local state = game.state
  local lot = lot(game, home, "offer", 1)
  t.ok(lot.fitted == true, lot.title)
  local hull = Ships.byId[lot.stacks[1].type]
  state.wallet = lot.price
  Core.TakeEvents(game)
  order(t, game, { kind = "AcceptContract", actor = 0, target = 1 })
  local assembled: any = nil
  for _, event in Core.TakeEvents(game) do
    assembled = if event.kind == "ShipAssembled" then event else assembled
  end
  t.ok(assembled ~= nil, "no ship was assembled")
  local made = state.ships[assembled.ship]
  t.eq({ made.type, made.owner, made.docked } :: { any }, { hull.id, "player", home } :: { any })
  local fit = assert(lot.fit, "a fitted lot says what it is fitted with")
  local fitted = Items.Fitted(state, made.id)
  t.eq(#fitted, #fit, "every module of the lot is fitted")
  local types: { string } = {}
  for _, item in fitted do
    table.insert(types, item.type)
  end
  local wanted = table.clone(fit)
  table.sort(types)
  table.sort(wanted)
  t.eq(types, wanted, "what is fitted is the lot's fit")
  for _, item in Items.In(state, home, "hangar") do
    t.ok(item.type ~= hull.id, "the hull is not left packaged in the hangar")
  end
  for _, item in fitted do
    local module = Modules.byId[item.type]
    if module.weapon and Fits.Charge(item.type, hull) then
      t.ok(item.charge ~= "" and item.rounds > 0, `{module.name} is loaded`)
    end
  end
  -- Boarded by a pilot with the hull's skill and nothing else: not out of the station.
  for _, need in Skills.Needs(hull.id) do
    state.skills[need.skill] = need.level
  end
  order(t, game, { kind = "BoardShip", actor = 0, target = made.id })
  local wanting = false
  local kept = table.clone(state.skills)
  for _, item in fitted do
    for _, need in Skills.Needs(item.type) do
      if (state.skills[need.skill] or 0) < need.level then
        wanting = true
      end
    end
  end
  if wanting then
    local why = refused(game, { kind = "Undock", actor = 0 }) :: string
    t.ok(string.find(why, "fitted", 1, true) ~= nil, why)
  end
  -- With the skills for all of it, out it goes.
  for _, skill in Skills.list do
    state.skills[skill.id] = 5
  end
  t.eq(refused(game, { kind = "Undock", actor = 0 }), "(accepted)")
  state.skills = kept
end)

suite:Case("every board in the galaxy is listed, the nearest first, and a lot taken is off the list", function(t)
  local game = newGame()
  local state = game.state
  local rows = Core.Query.ContractSearch(game, "offer")
  t.eq(#rows, #Contracts.Stations(state) * Contracts.OFFERS)
  t.eq({ rows[1].jumps, rows[1].station } :: { any }, { 0, rows[1].station } :: { any })
  for index = 2, #rows do
    t.ok(rows[index].jumps >= rows[index - 1].jumps, "the nearest first")
  end
  -- (within a reach, no farther)
  for _, row in Core.Query.ContractSearch(game, "offer", 1) do
    t.ok(row.jumps <= 1)
  end
  -- A lot far off, bought from here: off the list, and in the hangar where it was.
  local far = rows[#rows]
  t.ok(far.jumps > 0, "the farthest lot should be some jumps off")
  state.wallet = far.lot.price
  order(t, game, { kind = "AcceptContract", actor = 0, target = far.lot.slot, station = far.station })
  local left = Core.Query.ContractSearch(game, "offer")
  t.eq(#left, #rows - 1)
  local there = 0
  for _, item in Items.In(state, far.station, "hangar") do
    there += if item.type == far.lot.stacks[1].type then item.quantity else 0
  end
  t.ok(there >= far.lot.stacks[1].quantity, "what was bought is in the hangar of the station it was at")
end)

suite:Case("a lot wanted is filled from the hangar, and pays more than a market would for so many", function(t)
  local game, home = newGame()
  local state = game.state
  local want = lot(game, home, "want", 1)
  local type, count = want.stacks[1].type, want.stacks[1].quantity
  local name = Types.Info(type).name
  t.eq(refused(game, { kind = "FillContract", actor = 0, target = 1 }), `needs {count} more {name} in your hangar there`)
  Items.Add(state, type, count + 3, home, "hangar")
  if count > 1 then
    Items.Take(state, stack(game, type), 4)
    t.eq(refused(game, { kind = "FillContract", actor = 0, target = 1 }), `needs 1 more {name} in your hangar there`)
    Items.Add(state, type, 4, home, "hangar")
  end
  -- (what the market here would give for the same lot, sold at once)
  local market = Core.Query.SellValue(game, home, type, count)
  local wallet = state.wallet
  Core.TakeEvents(game)
  order(t, game, { kind = "FillContract", actor = 0, target = 1 })
  t.eq({ state.wallet - wallet, hangar(game, type), state.journal[#state.journal].reason } :: { any }, { want.price, 3, "contract" } :: { any })
  local filled: any = nil
  for _, event in Core.TakeEvents(game) do
    filled = if event.kind == "ContractFilled" then event else filled
  end
  t.eq({ filled.title, filled.price } :: { any }, { want.title, want.price } :: { any })
  t.eq(Contracts.Lot(state, home, "want", 1), nil)
  t.eq(refused(game, { kind = "FillContract", actor = 0, target = 1 }), "that is not on the board")
  if count >= 8 then
    t.ok(want.price > market, `a want for {count} pays {want.price}, and the market would give {market}`)
  end
  -- The other want is still there.
  t.ok(Contracts.Lot(state, home, "want", 2) ~= nil)
end)

suite:Case("a pilot's listing is held by the board, and taken when its price is near what it is worth", function(t)
  local game, home = newGame()
  local state = game.state
  state.wallet = 1000000
  -- The chance an hour, by what is asked against the worth: sure well under it, never well over.
  t.eq({ Contracts.Chance(85, 100), Contracts.Chance(50, 100), Contracts.Chance(106, 100), Contracts.Chance(10, 0) }, { 1, 1, 0, 0 })
  t.near(Contracts.Chance(100, 100), 0.07, 1e-9)
  t.near(Contracts.Chance(105, 100), 0.02, 1e-9)
  t.ok(Contracts.Chance(90, 100) > Contracts.Chance(95, 100) and Contracts.Chance(95, 100) > Contracts.Chance(100, 100))

  -- A copy good for a hundred runs. No market deals in it: to the builders here it is worth near its base price.
  Items.Add(state, "copy.ammo.emp", 300, home, "hangar")
  local base = Types.Info("copy.ammo.emp").basePrice
  local worth = Contracts.Worth(state, home, "copy.ammo.emp", 100)
  t.ok(worth > base * 100 * 0.9 and worth < base * 100, `a hundred runs worth {base * 100} at base are worth {worth} here`)
  local copies = stack(game, "copy.ammo.emp")
  t.eq(refused(game, { kind = "ListContract", actor = 0, item = copies.id, quantity = 301, price = 100 }), "no such quantity")
  t.eq(refused(game, { kind = "ListContract", actor = 0, item = copies.id, quantity = 2.5, price = 100 }), "no such quantity")
  t.eq(refused(game, { kind = "ListContract", actor = 0, item = copies.id, quantity = 100, price = 0 }), "no such price")
  t.eq(refused(game, { kind = "ListContract", actor = 0, item = 4242, quantity = 1, price = 100 }), "that is not in a station's hangar")
  local price = math.floor(worth * 0.8)
  local queried, fee, chance = Core.Query.ContractWorth(game, home, "copy.ammo.emp", 100, price)
  t.eq({ queried, fee, chance }, { worth, math.ceil(price * 0.03), 1 })
  Core.TakeEvents(game)
  order(t, game, { kind = "ListContract", actor = 0, item = copies.id, quantity = 100, price = price })
  t.eq({ state.wallet, hangar(game, "copy.ammo.emp"), state.journal[#state.journal].reason } :: { any },
    { 1000000 - fee, 200, "broker's fee" } :: { any })
  local listings = Contracts.Listings(state, home)
  t.eq({ #listings, listings[1].type, listings[1].quantity, listings[1].price, listings[1].ends - listings[1].placed } :: { any },
    { 1, "copy.ammo.emp", 100, price, 7 * DAY } :: { any })
  local seen = Core.Query.Contracts(game, home)
  t.eq({ #seen.listings, seen.listings[1].worth, seen.listings[1].chance, seen.listings[1].here, seen.limit } :: { any },
    { 1, worth, 1, true, Contracts.LISTINGS } :: { any })

  -- Within the hour somebody takes it: the pilot is paid, less the sales tax, wherever they are.
  local wallet = state.wallet
  local sold: any = nil
  for _ = 1, HOUR do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      sold = if event.kind == "ContractSold" then event else sold
    end
  end
  local paid = math.floor(price * 0.98)
  t.eq({ sold.type, sold.quantity, sold.price, sold.paid, sold.station } :: { any }, { "copy.ammo.emp", 100, price, paid, home } :: { any })
  t.eq({ state.wallet - wallet, #Contracts.Listings(state), hangar(game, "copy.ammo.emp") }, { paid, 0, 200 })

  -- The builders here have had a hundred: the next hundred are worth less to them, until they have forgotten.
  local second = Contracts.Worth(state, home, "copy.ammo.emp", 100)
  t.ok(second < worth * 0.97, `the next hundred should be worth less than {worth}, and are worth {second}`)
  state.tick += Contracts.FORGET
  local later = Contracts.Worth(state, home, "copy.ammo.emp", 100)
  t.ok(later > second and later < worth, `three days on, {later} should be between {second} and {worth}`)
  state.tick += 20 * Contracts.FORGET
  t.near(Contracts.Worth(state, home, "copy.ammo.emp", 100), worth, 2)
  -- However many are put up, they are never worth more than a few times what a station's builders want of them.
  Items.Add(state, "copy.ammo.emp", 1000000, home, "hangar")
  t.ok(Contracts.Worth(state, home, "copy.ammo.emp", 1000000) < Contracts.APPETITE * 8)

  -- Asked too much for, a listing is never taken: its week up, the lot is back in the hangar.
  local dear = math.floor(Contracts.Worth(state, home, "copy.ammo.emp", 50) * 1.2)
  order(t, game, { kind = "ListContract", actor = 0, item = stack(game, "copy.ammo.emp").id, quantity = 50, price = dear })
  local had = hangar(game, "copy.ammo.emp")
  local events = hours(game, 7 * 24 - 1)
  t.eq({ #events, #Contracts.Listings(state) }, { 0, 1 })
  events = hours(game, 2)
  t.eq({ #events, events[1].kind, events[1].quantity, #Contracts.Listings(state), hangar(game, "copy.ammo.emp") - had } :: { any },
    { 1, "ContractExpired", 50, 0, 50 } :: { any })

  -- Called off from anywhere (since 2026-11-16): the lot is back in the hangar where it was up, and the broker keeps the fee.
  order(t, game, { kind = "ListContract", actor = 0, item = stack(game, "copy.ammo.emp").id, quantity = 10, price = 100000 })
  t.eq(state.journal[#state.journal].amount, -3000)
  local up = Contracts.Listings(state)[1]
  wallet = state.wallet
  had = hangar(game, "copy.ammo.emp")
  t.eq(refused(game, { kind = "CancelContract", actor = 0, order = 4242 }), "no such listing")
  state.ships[state.player.ship].docked = 4242
  t.eq(refused(game, { kind = "CancelContract", actor = 0, order = up.id }), "(accepted)")
  state.ships[state.player.ship].docked = home
  order(t, game, { kind = "CancelContract", actor = 0, order = up.id })
  t.eq({ state.wallet, hangar(game, "copy.ammo.emp") - had, #Contracts.Listings(state) }, { wallet, 10, 0 })

  -- Ten at a time.
  for _ = 1, Contracts.LISTINGS do
    order(t, game, { kind = "ListContract", actor = 0, item = stack(game, "copy.ammo.emp").id, quantity = 1, price = 100000 })
  end
  t.eq(refused(game, { kind = "ListContract", actor = 0, item = stack(game, "copy.ammo.emp").id, quantity = 1, price = 100000 }),
    `{Contracts.LISTINGS} listings at a time`)
  -- And the broker is paid first.
  order(t, game, { kind = "CancelContract", actor = 0, order = Contracts.Listings(state)[1].id })
  state.wallet = 2999
  t.eq(refused(game, { kind = "ListContract", actor = 0, item = stack(game, "copy.ammo.emp").id, quantity = 1, price = 100000 }),
    "not enough credits for the broker")
end)

suite:Case("a listing of what a market deals in is worth what the market would give, lands in the market, and is no way round it", function(t)
  local game, home = newGame()
  local state = game.state
  state.wallet = 10000000
  Items.Add(state, "mineral.iron", 20000, home, "hangar")
  local worth = Contracts.Worth(state, home, "mineral.iron", 20000)
  -- (what selling them at once would bring, before the tax)
  t.near(worth, Core.Query.SellValue(game, home, "mineral.iron", 20000) / 0.98, 2)
  local before = Core.Query.Quote(game, home, "mineral.iron")
  local price = math.floor(worth * 0.85)
  order(t, game, { kind = "ListContract", actor = 0, item = stack(game, "mineral.iron").id, quantity = 20000, price = price })
  t.eq(Core.Query.Quote(game, home, "mineral.iron").stock, before.stock, "up on the board, it is in nobody's market yet")
  local events = hours(game, 1)
  t.eq({ #events, events[1].kind, events[1].paid } :: { any }, { 1, "ContractSold", math.floor(price * 0.98) } :: { any })
  local after = Core.Query.Quote(game, home, "mineral.iron")
  t.eq(after.stock, before.stock + 20000)
  t.ok(after.bid < before.bid, "what is sold by contract moves the market as what is sold there does")

  -- Bought at a market and put up on its board at the most anybody would ever pay, a lot loses money: the
  -- broker and the tax are more than the board can add.
  for _, count in { 100, 5000, 40000 } do
    local fresh = newGame()
    fresh.state.wallet = 100000000
    local cost = assert(Core.Query.BuyCost(fresh, home, "mineral.titanium", count))
    order(t, fresh, { kind = "BuyNow", actor = 0, type = "mineral.titanium", quantity = count })
    local most = math.floor(Contracts.Worth(fresh.state, home, "mineral.titanium", count) * Contracts.NEVER)
    local back = math.floor(most * 0.98) - Contracts.Fee(fresh.state, home, most)
    t.ok(back < cost, `{count} bought for {cost} would come back as {back}`)
    t.ok(Contracts.Chance(most + 1, Contracts.Worth(fresh.state, home, "mineral.titanium", count)) == 0)
  end
end)

suite:Case("boards are in the save, and a save from before there were any opens with nothing up", function(t)
  local game, home = newGame()
  local state = game.state
  state.wallet = 10000000
  Items.Add(state, "copy.ammo.emp", 500, home, "hangar")
  order(t, game, { kind = "ListContract", actor = 0, item = stack(game, "copy.ammo.emp").id, quantity = 100, price = 1000 })
  hours(game, 1)
  order(t, game, { kind = "ListContract", actor = 0, item = stack(game, "copy.ammo.emp").id, quantity = 100, price = 19000 })
  state.wallet = lot(game, home, "offer", 3).price
  order(t, game, { kind = "AcceptContract", actor = 0, target = 3 })
  t.eq({ #state.contractIds, #state.contractsTaken, state.contractsHad[home]["copy.ammo.emp"].units } :: { any }, { 1, 1, 100 } :: { any })
  local loaded = Core.Load(Core.Save(game))
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.eq(Contracts.Board(loaded.state, home), Contracts.Board(state, home))
  local mine, theirs = hours(game, 200), hours(loaded, 200)
  t.eq(#mine, 1, "in a week the listing is taken or its time is up")
  t.eq(theirs, mine)
  t.eq(Core.Hash(loaded), Core.Hash(game))

  -- An older save: no boards in it.
  local plain = newGame()
  local file = Codec.Decode(Core.Save(plain))
  file.saveVersion = 71
  file.state.contracts, file.state.contractIds, file.state.contractsTaken, file.state.contractsHad = nil, nil, nil, nil
  local old, length = Codec.Encode(file)
  local opened = Core.Load(old, length)
  t.eq(Core.Hash(opened), Core.Hash(plain))
  t.eq({ #opened.state.contractIds, #opened.state.contractsTaken, #Contracts.Board(opened.state, home) }, { 0, 0, 5 })
end)

suite:Case("a pirate hull's print is now and then on a board where order is thin, and never in secure space", function(t)
  -- (the owner, 2026-11-16: the Unbound's ship prints are found "on the
  -- market via contracts", and of how often, "One in 500")
  local game, home = newGame()
  local state = game.state
  t.near(Contracts.PIRATED, 1 / 500, 1e-12)
  local lawless = 0
  for id, node in state.galaxy.systems do
    if lawless == 0 and Galaxy.Band(node.security) ~= "secure" then
      for _, object in Space.Describe(state, id).objects do
        if lawless == 0 and object.kind == "station" then
          lawless = object.id
        end
      end
    end
  end
  t.ok(lawless ~= 0, "no station where order is thin")
  -- (one board, many days: about one day in five hundred; never at a secure station)
  local there, here = 0, 0
  for day = 0, 49999 do
    there += if Contracts.Pirated(state, lawless, day) then 1 else 0
    here += if Contracts.Pirated(state, home, day) then 1 else 0
  end
  t.ok(there >= 70 and there <= 130, `{there} days of fifty thousand`)
  t.eq(here, 0)
  -- And on such a day the board's blueprint lot is the print, dear.
  local ticks = math.ceil(86400 / Constants.TICK)
  local day = 0
  while not Contracts.Pirated(state, lawless, day) do
    day += 1
  end
  state.tick = day * ticks
  local lot = assert(Contracts.Lot(state, lawless, "offer", 2))
  local print, copy = Blueprints.Of(lot.stacks[1].type)
  t.ok(print ~= nil and not copy and Ships.byId[print.product].lineage == "unbound", lot.title)
  t.ok(lot.price > lot.worth, "a pirate hull's print should be dear")
end)

return suite
