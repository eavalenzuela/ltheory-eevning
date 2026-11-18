--!strict
-- A ship painted, and stripped (Assets/Paintwork, Data/Paints).

local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Items = require("@lt/Core/Assets/Items")
local Market = require("@lt/Core/Assets/Market")
local Paints = require("@lt/Core/Data/Paints")
local State = require("@lt/Core/Kernel/State")
local Stations = require("@lt/Core/Assets/Stations")
local Test = require("@lt/Tool/Test")
local Types = require("@lt/Core/Data/Types")

local suite = Test.Suite("Paintwork")

local function refused(game: Core.Game, command: State.Command): string?
  command.actor = game.state.player.ship
  local ok, reason = Core.Validate(game, command)
  return if ok then "(accepted)" else reason
end

local function act(t: Test.Context, game: Core.Game, command: State.Command): { [string]: any }?
  command.actor = game.state.player.ship
  local ok, why = Core.Submit(game, command)
  t.ok(ok, `{command.kind} was refused: {tostring(why)}`)
  Core.Step(game)
  local told: { [string]: any }? = nil
  for _, event in Core.TakeEvents(game) do
    told = if event.kind == "Painted" then event else told
  end
  return told
end

suite:Case("every paint and design is a thing a market deals in, and each has its own colours or figure", function(t)
  local figures: { [number]: string } = {}
  t.ok(#Paints.paints >= 8 and #Paints.designs >= 6)
  for _, paint in Paints.paints do
    local info = Types.Info(paint.id)
    t.eq({ info.category, info.name, info.basePrice, info.scarce } :: { any }, { "paint", paint.name .. " (paint)", paint.price, nil } :: { any })
    t.ok(Market.Index(paint.id) ~= nil, paint.id)
    for _, colour in { paint.plating, paint.patch, paint.trim, paint.frame, paint.accent } do
      t.ok(#colour == 3 and colour[1] >= 0 and colour[1] <= 1 and colour[2] >= 0 and colour[2] <= 1 and colour[3] >= 0 and colour[3] <= 1,
        paint.id)
    end
    -- (a design shows on its paint: the colour it is laid on in is not the plating's)
    local apart = math.abs(paint.accent[1] - paint.plating[1]) + math.abs(paint.accent[2] - paint.plating[2])
      + math.abs(paint.accent[3] - paint.plating[3])
    t.ok(apart > 0.25, `{paint.id}: a design would not show on it`)
  end
  for _, design in Paints.designs do
    t.eq(Types.Info(design.id).category, "paint")
    t.ok(design.figure >= 1 and design.figure % 1 == 0 and figures[design.figure] == nil, `{design.id} has the figure of {tostring(figures[design.figure])}`)
    figures[design.figure] = design.id
  end
end)

suite:Case("a paint made the pilot's is used up and theirs for good: a ship is painted in it and out of it for nothing", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local home = state.player.home
  local ship = state.ships[state.player.ship]
  t.eq({ ship.paint, ship.design, next(state.paints) } :: { any }, {})
  t.eq(refused(game, { kind = "StripPaint", actor = 0 }), "the ship is as it left the yard")
  t.eq(refused(game, { kind = "UnlockPaint", actor = 0, item = 424242 }), "that is not in the hangar here, nor in the hold")
  local crimson = Items.Add(state, "paint.crimson", 2, home, "hangar")
  local hoops = Items.Add(state, "design.hoops", 1, home, "hangar")
  local ore = Items.Add(state, "ore.ferrite", 5, home, "hangar")
  t.eq(refused(game, { kind = "UnlockPaint", actor = 0, item = ore.id }), "that is neither a paint nor a design")
  t.eq(refused(game, { kind = "Paint", actor = 0, type = "ore.ferrite" }), "that is neither a paint nor a design")
  t.eq(refused(game, { kind = "Paint", actor = 0, type = "paint.onyx" }), "that is not one of yours: a market sells it")

  -- Made theirs: one is used up, and the ship is not painted by it.
  act(t, game, { kind = "UnlockPaint", actor = 0, item = crimson.id })
  t.eq({ state.paints["paint.crimson"], crimson.quantity, ship.paint } :: { any }, { true, 1, nil } :: { any })
  t.eq(refused(game, { kind = "UnlockPaint", actor = 0, item = crimson.id }), "it is yours already")
  -- Painted in it: nothing more is used.
  t.eq(refused(game, { kind = "Paint", actor = 0, type = "design.hoops" }), "a design needs a paint under it: paint the ship first")
  local told = assert(act(t, game, { kind = "Paint", actor = 0, type = "paint.crimson" }), "nothing was said of the painting")
  t.eq({ told.ship, told.with, told.paint, told.design } :: { any }, { ship.id, "paint.crimson", "paint.crimson", nil } :: { any })
  t.eq({ ship.paint, ship.design, crimson.quantity } :: { any }, { "paint.crimson", nil, 1 } :: { any })
  t.eq(refused(game, { kind = "Paint", actor = 0, type = "paint.crimson" }), "the ship is in that paint already")
  -- One that lies in the hangar and is not theirs yet is made theirs by the painting.
  act(t, game, { kind = "Paint", actor = 0, type = "design.hoops" })
  t.eq({ ship.paint, ship.design, state.paints["design.hoops"] } :: { any }, { "paint.crimson", "design.hoops", true } :: { any })
  t.eq(state.items[hoops.id], nil, "the design should be used up")
  t.eq(refused(game, { kind = "Paint", actor = 0, type = "design.hoops" }), "the ship has that design already")
  -- One in the hold is made theirs from there; and the ship goes from one paint to another and back, the design staying.
  local onyx = Items.Add(state, "paint.onyx", 1, ship.id, "cargo")
  act(t, game, { kind = "UnlockPaint", actor = 0, item = onyx.id })
  t.eq(state.items[onyx.id], nil)
  act(t, game, { kind = "Paint", actor = 0, type = "paint.onyx" })
  t.eq({ ship.paint, ship.design } :: { any }, { "paint.onyx", "design.hoops" } :: { any })
  act(t, game, { kind = "Paint", actor = 0, type = "paint.crimson" })
  t.eq({ ship.paint, ship.design, crimson.quantity } :: { any }, { "paint.crimson", "design.hoops", 1 } :: { any })
  -- The design comes off alone.
  act(t, game, { kind = "StripPaint", actor = 0, what = "design" })
  t.eq({ ship.paint, ship.design } :: { any }, { "paint.crimson", nil } :: { any })
  t.eq(refused(game, { kind = "StripPaint", actor = 0, what = "design" }), "the ship has no design on it")
  act(t, game, { kind = "Paint", actor = 0, type = "design.hoops" })

  -- It is in the save.
  local bytes, length = Core.Save(game)
  local loaded = Core.Load(bytes, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.eq({ loaded.state.ships[ship.id].paint, loaded.state.paints["paint.onyx"], loaded.state.paints["design.hoops"] } :: { any },
    { "paint.crimson", true, true } :: { any })

  -- Out in space there is no painting, but a paint in the hold can be made theirs; and back to the yard's, what is theirs stays theirs.
  local bone = Items.Add(state, "paint.bone", 1, ship.id, "cargo")
  act(t, game, { kind = "Undock", actor = 0 })
  t.eq(refused(game, { kind = "Paint", actor = 0, type = "paint.onyx" }), "not docked")
  t.eq(refused(game, { kind = "StripPaint", actor = 0 }), "not docked")
  act(t, game, { kind = "UnlockPaint", actor = 0, item = bone.id })
  t.eq(state.paints["paint.bone"], true)
  local again = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local theirs = again.state.ships[again.state.player.ship]
  theirs.paint, theirs.design = "paint.onyx", "design.hoops"
  again.state.paints["paint.onyx"], again.state.paints["design.hoops"] = true, true
  local stripped = assert(act(t, again, { kind = "StripPaint", actor = 0 }))
  t.eq({ stripped.stripped, theirs.paint, theirs.design, again.state.paints["paint.onyx"] } :: { any }, { true, nil, nil, true } :: { any })
  act(t, again, { kind = "Paint", actor = 0, type = "paint.onyx" })
  t.eq(theirs.paint, "paint.onyx")
end)

suite:Case("a save from when a paint was used up by a painting: what the pilot's ships are in is theirs", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local ship = state.ships[state.player.ship]
  ship.paint, ship.design = "paint.cobalt", "design.tiger"
  local data, length = Core.Save(game)
  local file = Codec.Decode(data, length)
  file.saveVersion = 82
  file.state.paints = nil
  local old, oldLength = Codec.Encode(file)
  local opened = Core.Load(old, oldLength).state
  t.eq({ opened.paints["paint.cobalt"], opened.paints["design.tiger"], opened.paints["paint.onyx"] } :: { any }, { true, true, nil } :: { any })
  t.eq(opened.ships[ship.id].paint, "paint.cobalt")
end)

suite:Case("a faction's livery is its own: sold at its stations to anybody, with its design, and worn by its ships", function(t)
  local Factions = require("@lt/Core/Data/Factions")
  for _, faction in Factions.list do
    local livery = Paints.liveryOf[faction.id]
    if faction.kind == "human" then
      t.ok(livery ~= nil and livery.group == "livery", `the {faction.name} have no livery`)
      t.ok(Paints.designById[livery.wears or ""] ~= nil, `{livery.id} wears no design`)
      t.eq({ Paints.Dress(faction.id, false) } :: { any }, { livery.id, livery.wears } :: { any })
      t.eq({ Paints.Dress(faction.id, true) } :: { any }, { Paints.POLICE.paint, Paints.POLICE.design } :: { any })
    else
      -- (nobody has said what the others' are)
      t.eq(livery, nil, `{faction.name} have a livery`)
    end
  end
  t.ok(Paints.paintById[Paints.POLICE.paint] ~= nil and Paints.designById[Paints.POLICE.design] ~= nil)
  t.eq({ Paints.Dress("player", false) } :: { any }, {})
  t.eq({ Paints.Dress("pirates", true) } :: { any }, {})

  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local home = state.player.home
  local people = Stations.People(state, home)
  local theirs = Paints.liveryOf[people]
  local others: Paints.Paint? = nil
  for _, paint in Paints.paints do
    if paint.faction and paint.faction ~= people then
      others = others or paint
    end
  end
  assert(theirs and others, `no livery to buy where the {people} are`)
  state.wallet = 10000000
  -- Theirs is there to be had, a few of them; somebody else's is not.
  t.ok(Market.BuyCost(state, home, theirs.id, Market.OWN_STOCK) ~= nil, `{theirs.id} is not in stock at one of its people's stations`)
  t.eq(Market.BuyCost(state, home, others.id, 1), nil, `{others.id} is in stock at a station of {people}'s`)
  -- (to anybody, whatever they think of the pilot: a market is not
  -- gated by standing, only the loyalty stores are)
  state.standings[people] = -4
  act(t, game, { kind = "BuyNow", actor = 0, type = theirs.id, quantity = 1 })
  -- Made theirs, the design its ships wear comes with it.
  local bought: State.Item? = nil
  for _, item in Items.In(state, home, "hangar") do
    bought = if item.type == theirs.id then item else bought
  end
  assert(bought, "the livery bought is not in the hangar")
  act(t, game, { kind = "UnlockPaint", actor = 0, item = bought.id })
  t.eq({ state.paints[theirs.id], state.paints[theirs.wears :: string] } :: { any }, { true, true } :: { any })
  act(t, game, { kind = "Paint", actor = 0, type = theirs.id })
  act(t, game, { kind = "Paint", actor = 0, type = theirs.wears })
  local ship = state.ships[state.player.ship]
  t.eq({ ship.paint, ship.design } :: { any }, { theirs.id, theirs.wears } :: { any })
end)

suite:Case("a paint is bought on a market like anything else", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  state.wallet = 1000000
  local ok, why = Core.Submit(game, { kind = "BuyNow", actor = state.player.ship, type = "paint.cobalt", quantity = 1 })
  t.ok(ok, tostring(why))
  Core.Step(game)
  local bought: State.Item? = nil
  for _, item in Items.In(state, state.player.home, "hangar") do
    bought = if item.type == "paint.cobalt" then item else bought
  end
  t.ok(bought ~= nil, "the paint bought is not in the hangar")
  t.ok(state.wallet < 1000000 and state.wallet > 1000000 - 4 * Types.Info("paint.cobalt").basePrice)
end)

return suite
