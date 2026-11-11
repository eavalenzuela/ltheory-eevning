--!strict
-- Planets worked (Data/Planets, Assets/Colonies), through the Core's
-- front door.

local Blueprints = require("@lt/Core/Data/Blueprints")
local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Items = require("@lt/Core/Assets/Items")
local Planets = require("@lt/Core/Data/Planets")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")
local Test = require("@lt/Tool/Test")
local Types = require("@lt/Core/Data/Types")

local suite = Test.Suite("Colonies")

local CENTRE = Planets.CENTRE.id
local CYCLE = Planets.CYCLE

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

local function steps(game: Core.Game, count: number)
  for _ = 1, count do
    Core.Step(game)
  end
end

local function stepUntil(game: Core.Game, kind: string, limit: number): Space.Event
  for _ = 1, limit do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      if event.kind == kind then
        return event
      end
    end
  end
  error(`no {kind} within {limit} ticks`, 2)
end

local function carry(game: Core.Game, type: string, quantity: number): State.Item
  return Items.Add(game.state, type, quantity, game.state.player.ship, "cargo")
end

local function stored(game: Core.Game, planet: number, type: string): number
  for _, held in assert(Core.Query.Colony(game, planet)).store do
    if held.type == type then
      return held.quantity
    end
  end
  return 0
end

-- A rich pilot in space near a planet of the first system, a command
-- centre in the hold: the game, the planet and the centre. (The ship is
-- put there: the flight is Space's to test.)
local function atPlanet(t: Test.Context): (Core.Game, System.Object, State.Item)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  game.state.wallet = 5000000
  local centre = carry(game, CENTRE, 1)
  order(t, game, { kind = "Undock", actor = 0 })
  local planet: System.Object? = nil
  for _, object in Core.Query.Objects(game, 1) do
    if object.kind == "planet" and planet == nil then
      planet = object
    end
  end
  local found = assert(planet, "the first system has no planet")
  order(t, game, { kind = "WarpTo", actor = 0, target = found.id, range = found.radius })
  stepUntil(game, "WarpEnded", 900)
  return game, found, centre
end

-- The same with the colony put down: the game, the planet, and the raw
-- material it is richest in.
local function colony(t: Test.Context): (Core.Game, number, string)
  local game, planet, centre = atPlanet(t)
  order(t, game, { kind = "DeployColony", actor = 0, item = centre.id, target = planet.id })
  local best, richest = "", 0
  for _, deposit in Core.Query.Deposits(game, planet.id) do
    if deposit.richness > richest then
      best, richest = deposit.raw, deposit.richness
    end
  end
  return game, planet.id, best
end

local function build(t: Test.Context, game: Core.Game, planet: number, type: string, what: string?): number
  order(t, game, { kind = "BuildFacility", actor = 0, target = planet, type = type, what = what })
  local facilities = assert(Core.Query.Colony(game, planet)).facilities
  return facilities[#facilities].id
end

suite:Case("every kind of planet can be worked, and everything taken from one has a use", function(t)
  for _, variety in { "temperate", "ocean", "barren", "lava", "ice", "gas" } do
    local deposits = Planets.Deposits(variety, 12345)
    t.eq(#deposits, 3)
    for _, deposit in deposits do
      t.ok(deposit.richness >= 0.6 and deposit.richness <= 1.4, `{variety}: a richness of {deposit.richness}`)
      t.eq(Planets.Richness(12345, deposit.raw), deposit.richness)
      t.ok(Planets.productOf[deposit.raw] ~= nil, `nothing is made of {deposit.raw}`)
    end
  end
  t.eq(#Planets.Deposits("moon", 1), 0)
  -- (richness is the planet's own: another planet, another figure)
  t.ok(Planets.Richness(1, "raw.gas") ~= Planets.Richness(2, "raw.gas"))
  for _, raw in Planets.raws do
    local found = false
    for _, deposits in Planets.DEPOSITS do
      found = found or table.find(deposits, raw.id) ~= nil
    end
    t.ok(found, `no kind of planet has {raw.name}`)
    t.eq(Types.Info(raw.id).category, "planetary")
  end
  for _, product in Planets.products do
    local called = false
    for _, blueprint in Blueprints.list do
      for _, material in blueprint.materials do
        called = called or material.type == product.id
      end
    end
    t.ok(called, `no blueprint calls for {product.name}`)
    -- (and it is worth more than what went into it)
    t.ok(product.output * product.basePrice > product.input * Planets.rawById[product.from].basePrice)
  end
end)

suite:Case("fuel and structures are built of what planets give", function(t)
  local function uses(product: string, part: string): number
    for _, material in Blueprints.byProduct[product].materials do
      if material.type == part then
        return material.quantity
      end
    end
    return 0
  end
  for _, part in { "planet.isotopes", "planet.water", "planet.catalysts" } do
    t.ok(uses("fuel.block", part) > 0, `fuel blocks take no {part}`)
  end
  for _, product in { "tower.vessari.small", "tower.vessari.large", "array.refining", "battery.gun" } do
    for _, part in { "planet.alloys", "planet.ceramics", "planet.polymers" } do
      t.ok(uses(product, part) > 0, `{product} takes no {part}`)
    end
  end
  t.ok(uses("tower.vessari.large", "planet.alloys") > uses("tower.vessari.small", "planet.alloys"))
  -- (a command centre is built of nothing a colony makes)
  for _, material in Blueprints.byProduct[CENTRE].materials do
    t.ok(Planets.productById[material.type] == nil, "the first command centre would need a colony to build")
  end
end)

suite:Case("a programme brings up less each cycle, so a short one takes more in an hour", function(t)
  t.eq(Planets.Yield(1, 0), Planets.YIELD)
  local last = math.huge
  local rates: { number } = {}
  for _, hours in Planets.PROGRAMMES do
    local total = 0
    for k = 0, hours * 3600 // CYCLE - 1 do
      total += Planets.Yield(1, k)
    end
    t.ok(total / hours < last, `a {hours} hour programme takes as much in an hour as a shorter one`)
    last = total / hours
    table.insert(rates, total)
  end
  -- (but a longer one always takes more in all)
  for index = 2, #rates do
    t.ok(rates[index] > rates[index - 1])
  end
end)

suite:Case("a command centre is put down from the hold, near a planet, once", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local centre = carry(game, CENTRE, 2)
  local ore = carry(game, "ore.ferrite", 10)
  local planet: System.Object?, moon: System.Object? = nil, nil
  for _, object in Core.Query.Objects(game, 1) do
    if object.kind == "planet" then
      planet = planet or object
    elseif object.kind == "moon" then
      moon = moon or object
    end
  end
  local world, other = assert(planet), assert(moon)
  t.eq(refused(game, { kind = "DeployColony", actor = 0, item = centre.id, target = world.id }), "docked")
  order(t, game, { kind = "Undock", actor = 0 })
  t.eq(refused(game, { kind = "DeployColony", actor = 0, item = centre.id, target = world.id }), "too far from the planet")
  t.eq(refused(game, { kind = "DeployColony", actor = 0, item = ore.id, target = world.id }), "no command centre in the hold")
  t.eq(refused(game, { kind = "DeployColony", actor = 0, item = centre.id, target = other.id }), "a colony is put down on a planet")
  order(t, game, { kind = "WarpTo", actor = 0, target = world.id, range = world.radius })
  stepUntil(game, "WarpEnded", 900)
  t.eq(#Core.Query.Colonies(game), 0)
  t.eq(Core.Query.Colony(game, world.id), nil)
  order(t, game, { kind = "DeployColony", actor = 0, item = centre.id, target = world.id })
  t.eq(centre.quantity, 1)
  t.eq(Core.Query.Colonies(game), { world.id })
  local status = assert(Core.Query.Colony(game, world.id))
  t.eq({ status.name, status.variety, status.mine, status.near, #status.facilities, #status.store, status.room, status.used } :: { any },
    { world.name, world.variety, true, true, 0, 0, Planets.CENTRE.room, 0 } :: { any })
  t.eq(#status.deposits, 3)
  t.eq(refused(game, { kind = "DeployColony", actor = 0, item = centre.id, target = world.id }), "that planet has a colony already")
end)

suite:Case("facilities are raised for credits, on what the planet has, within what the centre supplies", function(t)
  local game, planet, raw = colony(t)
  local absent = ""
  for _, candidate in Planets.raws do
    if not table.find(Planets.DEPOSITS[assert(Core.Query.Colony(game, planet)).variety], candidate.id) then
      absent = candidate.id
    end
  end
  t.eq(refused(game, { kind = "BuildFacility", actor = 0, target = planet, type = "extractor", what = absent }),
    "an extractor is set on something the planet has")
  t.eq(refused(game, { kind = "BuildFacility", actor = 0, target = planet, type = "processor", what = Planets.productOf[absent].id }),
    `nothing here to make {Planets.productOf[absent].name} from`)
  t.eq(refused(game, { kind = "BuildFacility", actor = 0, target = planet, type = "dome", what = raw }), "no such facility")
  t.eq(refused(game, { kind = "BuildFacility", actor = 0, target = planet + 1, type = "extractor", what = raw }), "no colony of yours there")

  local before = game.state.wallet
  build(t, game, planet, "extractor", raw)
  t.eq(before - game.state.wallet, Planets.facilityById["extractor"].cost)
  game.state.wallet = 100
  t.eq(refused(game, { kind = "BuildFacility", actor = 0, target = planet, type = "extractor", what = raw }), "not enough credits")
  game.state.wallet = 5000000

  -- Three extractors and three processors use all the CPU there is: no storage.
  build(t, game, planet, "extractor", raw)
  build(t, game, planet, "extractor", raw)
  for _ = 1, 3 do
    build(t, game, planet, "processor", Planets.productOf[raw].id)
  end
  local status = assert(Core.Query.Colony(game, planet))
  t.eq({ status.powergrid, status.cpu, #status.facilities }, { 4800, 1200, 6 })
  t.eq(refused(game, { kind = "BuildFacility", actor = 0, target = planet, type = "storage" }), "the command centre has not the CPU")
  build(t, game, planet, "extractor", raw)
  t.eq(refused(game, { kind = "BuildFacility", actor = 0, target = planet, type = "extractor", what = raw }),
    "the command centre has not the powergrid")
end)

suite:Case("a colony is run from anywhere", function(t)
  local game, planet, raw = colony(t)
  order(t, game, { kind = "Dock", actor = 0, target = game.state.player.home })
  stepUntil(game, "Docked", 900)
  local pin = build(t, game, planet, "extractor", raw)
  order(t, game, { kind = "StartExtraction", actor = 0, target = planet, pin = pin, hours = 1 })
  local status = assert(Core.Query.Colony(game, planet))
  t.eq({ status.near, status.facilities[1].working } :: { any }, { false, true } :: { any })
end)

suite:Case("an extractor works through its programme and stops", function(t)
  local game, planet, raw = colony(t)
  local richness = Planets.Richness(assert(Space.Object(game.state, planet)).seed, raw)
  local pin = build(t, game, planet, "extractor", raw)
  t.eq(refused(game, { kind = "StartExtraction", actor = 0, target = planet, pin = pin, hours = 3 }), "a programme runs 1, 4, 12, 24 hours")
  t.eq(refused(game, { kind = "StartExtraction", actor = 0, target = planet, pin = pin + 1, hours = 1 }), "no such extractor")
  steps(game, CYCLE * 2)
  t.eq(stored(game, planet, raw), 0)
  order(t, game, { kind = "StartExtraction", actor = 0, target = planet, pin = pin, hours = 1 })
  local facility = assert(Core.Query.Colony(game, planet)).facilities[1]
  t.eq({ facility.working, facility.rate } :: { any }, { true, Planets.Yield(richness, 0) } :: { any })
  t.ok(facility.left > 3590 and facility.left <= 3600)
  steps(game, CYCLE - 2)
  t.eq(stored(game, planet, raw), 0)
  steps(game, 2)
  t.eq(stored(game, planet, raw), Planets.Yield(richness, 0))
  local ended = stepUntil(game, "ExtractionEnded", 3 * CYCLE + 2)
  t.eq({ ended.planet, ended.pin, ended.raw } :: { any }, { planet, pin, raw } :: { any })
  local hour = Planets.Yield(richness, 0) + Planets.Yield(richness, 1) + Planets.Yield(richness, 2) + Planets.Yield(richness, 3)
  t.eq(stored(game, planet, raw), hour)
  steps(game, CYCLE * 2)
  t.eq(stored(game, planet, raw), hour)
  t.ok(not assert(Core.Query.Colony(game, planet)).facilities[1].working)
  -- (a programme started again starts from the top)
  order(t, game, { kind = "StartExtraction", actor = 0, target = planet, pin = pin, hours = 4 })
  steps(game, CYCLE)
  t.eq(stored(game, planet, raw), hour + Planets.Yield(richness, 0))
end)

suite:Case("a processor makes its product of what the extractors bring up", function(t)
  local game, planet, raw = colony(t)
  local product = Planets.productOf[raw]
  local extractor = build(t, game, planet, "extractor", raw)
  build(t, game, planet, "extractor", raw)
  build(t, game, planet, "processor", product.id)
  for _, pin in { extractor, extractor + 1 } do
    order(t, game, { kind = "StartExtraction", actor = 0, target = planet, pin = pin, hours = 4 })
  end
  steps(game, 4 * 3600 + CYCLE + 5)
  local made, left = stored(game, planet, product.id), stored(game, planet, raw)
  t.ok(made >= product.output * 8, `only {made} {product.name} in four hours`)
  t.eq(made % product.output, 0)
  -- nothing is made of nothing: what was brought up is what was used and what is left
  local richness = Planets.Richness(assert(Space.Object(game.state, planet)).seed, raw)
  local brought = 0
  for k = 0, 15 do
    brought += 2 * Planets.Yield(richness, k)
  end
  local inHand = if assert(Core.Query.Colony(game, planet)).facilities[3].working then product.input else 0
  t.eq(made / product.output * product.input + left + inHand, brought)
end)

suite:Case("raw material that finds no room is lost, and storage is room", function(t)
  local game, planet, raw = colony(t)
  for index = 1, 3 do
    local pin = build(t, game, planet, "extractor", raw)
    t.eq(pin, index)
    order(t, game, { kind = "StartExtraction", actor = 0, target = planet, pin = pin, hours = 24 })
  end
  steps(game, 24 * 3600 + 10)
  local status = assert(Core.Query.Colony(game, planet))
  t.eq(status.room, Planets.CENTRE.room)
  t.near(status.used, status.room, 1e-6)
  t.eq(stored(game, planet, raw), math.floor(Planets.CENTRE.room / Planets.rawById[raw].volume + 0.5))
  build(t, game, planet, "storage")
  t.eq(assert(Core.Query.Colony(game, planet)).room, Planets.CENTRE.room + Planets.facilityById["storage"].room)
  -- (and it cannot be taken away from under what it holds)
  order(t, game, { kind = "StartExtraction", actor = 0, target = planet, pin = 1, hours = 1 })
  steps(game, CYCLE + 1)
  t.eq(refused(game, { kind = "RemoveFacility", actor = 0, target = planet, pin = 4 }), "it holds more than there would be room for")
  t.eq(refused(game, { kind = "RemoveFacility", actor = 0, target = planet, pin = 9 }), "no such facility")
  order(t, game, { kind = "RemoveFacility", actor = 0, target = planet, pin = 2 })
  local after = assert(Core.Query.Colony(game, planet))
  t.eq({ #after.facilities, after.facilities[2].id }, { 3, 3 })
  -- (a number is not given twice)
  t.eq(build(t, game, planet, "extractor", raw), 5)
end)

suite:Case("a ship near the planet takes goods up into its hold, and pays the tax", function(t)
  local game, planet, raw = colony(t)
  local product = Planets.productOf[raw]
  local pin = build(t, game, planet, "extractor", raw)
  build(t, game, planet, "processor", product.id)
  order(t, game, { kind = "StartExtraction", actor = 0, target = planet, pin = pin, hours = 4 })
  steps(game, 4 * 3600)
  local made = stored(game, planet, product.id)
  t.ok(made >= 20)
  t.eq(refused(game, { kind = "Export", actor = 0, target = planet, type = "planet.none" }), "the colony has none of that")
  t.eq(refused(game, { kind = "Export", actor = 0, target = planet, type = product.id, quantity = made + 1 }), "not that many")
  local status = assert(Core.Query.Colony(game, planet))
  t.ok(status.near)
  for _, held in status.store do
    if held.type == product.id then
      t.eq(held.fits, made)
    end
  end
  local before = game.state.wallet
  order(t, game, { kind = "Export", actor = 0, target = planet, type = product.id, quantity = 20 })
  t.eq(stored(game, planet, product.id), made - 20)
  local inHold = 0
  for _, item in Core.Query.Items(game, game.state.player.ship, "cargo") do
    inHold += if item.type == product.id then item.quantity else 0
  end
  t.eq(inHold, 20)
  t.eq(before - game.state.wallet, math.ceil(20 * product.basePrice * Planets.EXPORT_TAX))
  -- A hold has only so much room, and the tax has to be paid.
  local rawLeft = stored(game, planet, raw)
  if rawLeft * Planets.rawById[raw].volume > 200 then
    t.eq(refused(game, { kind = "Export", actor = 0, target = planet, type = raw }), "not enough room in the hold")
  end
  game.state.wallet = 0
  t.eq(refused(game, { kind = "Export", actor = 0, target = planet, type = product.id, quantity = 1 }), "not enough credits for the export tax")
  game.state.wallet = 5000000
  -- From far off, nothing comes up.
  order(t, game, { kind = "Dock", actor = 0, target = game.state.player.home })
  stepUntil(game, "WarpStarted", 300)
  t.eq(refused(game, { kind = "Export", actor = 0, target = planet, type = product.id, quantity = 1 }), "in warp")
  stepUntil(game, "Docked", 900)
  t.eq(refused(game, { kind = "Export", actor = 0, target = planet, type = product.id, quantity = 1 }), "docked")
end)

suite:Case("a colony is in the save, and the game goes on the same from it", function(t)
  local game, planet, raw = colony(t)
  local pin = build(t, game, planet, "extractor", raw)
  build(t, game, planet, "processor", Planets.productOf[raw].id)
  order(t, game, { kind = "StartExtraction", actor = 0, target = planet, pin = pin, hours = 4 })
  steps(game, 3000)
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  steps(game, 6000)
  steps(loaded, 6000)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.eq(stored(loaded, planet, raw), stored(game, planet, raw))
  t.ok(stored(loaded, planet, Planets.productOf[raw].id) > 0)
end)

suite:Case("a save from before planets were worked opens with no colonies, and its markets know the new goods", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local station = Core.Query.Player(game).docked
  Core.Query.Quote(game, station, "ore.ferrite")
  local data, length = Core.Save(game)
  local file = Codec.Decode(data, length)
  file.saveVersion = 12
  file.state.colonies = nil
  file.state.colonyIds = nil
  for _, market in file.state.markets do
    for index = #market.classes, 1, -1 do
      local id: string = market.classes[index].id
      if string.sub(id, 1, 4) == "raw." or string.sub(id, 1, 7) == "planet." or string.sub(id, 1, 7) == "colony." then
        table.remove(market.classes, index)
        for _, name in { "initial", "produced", "consumed", "used", "anchorIn", "anchorOut", "bought", "sold", "moved", "lost" } do
          table.remove(market[name], index)
        end
        for _, name in { "stock", "target", "anchor", "taste" } do
          table.remove(market.nodes[1][name], index)
        end
      end
    end
  end
  local old, oldLength = Codec.Encode(file)
  local loaded = Core.Load(old, oldLength)
  t.eq(#loaded.state.colonyIds, 0)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.ok(Core.Query.Quote(loaded, station, "planet.isotopes").stock > 0)
  t.ok(Core.Query.Quote(loaded, station, CENTRE).ask ~= nil)
end)

return suite
