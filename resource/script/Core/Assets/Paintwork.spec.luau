--!strict
-- A ship painted, and stripped (Assets/Paintwork, Data/Paints).

local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Items = require("@lt/Core/Assets/Items")
local Market = require("@lt/Core/Assets/Market")
local Paints = require("@lt/Core/Data/Paints")
local State = require("@lt/Core/Kernel/State")
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

suite:Case("docked, a paint in the hangar is put on the ship and used up; a design wants a paint under it; and both come off", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local home = state.player.home
  local ship = state.ships[state.player.ship]
  t.eq({ ship.paint, ship.design } :: { any }, {})
  t.eq(refused(game, { kind = "StripPaint", actor = 0 }), "the ship is as it left the yard")
  t.eq(refused(game, { kind = "Paint", actor = 0, item = 424242 }), "that is not in the hangar here")
  local crimson = Items.Add(state, "paint.crimson", 2, home, "hangar")
  local hoops = Items.Add(state, "design.hoops", 1, home, "hangar")
  local ore = Items.Add(state, "ore.ferrite", 5, home, "hangar")
  t.eq(refused(game, { kind = "Paint", actor = 0, item = ore.id }), "that is neither a paint nor a design")
  t.eq(refused(game, { kind = "Paint", actor = 0, item = hoops.id }), "a design needs a paint under it: paint the ship first")
  local told = assert(act(t, game, { kind = "Paint", actor = 0, item = crimson.id }), "nothing was said of the painting")
  t.eq({ told.ship, told.with, told.paint, told.design } :: { any }, { ship.id, "paint.crimson", "paint.crimson", nil } :: { any })
  t.eq({ ship.paint, ship.design, crimson.quantity } :: { any }, { "paint.crimson", nil, 1 } :: { any })
  t.eq(refused(game, { kind = "Paint", actor = 0, item = crimson.id }), "the ship is in that paint already")
  -- The design over it, and then another paint under the design: each takes the place of what was there.
  act(t, game, { kind = "Paint", actor = 0, item = hoops.id })
  t.eq({ ship.paint, ship.design } :: { any }, { "paint.crimson", "design.hoops" } :: { any })
  t.eq(state.items[hoops.id], nil, "the design should be used up")
  local onyx = Items.Add(state, "paint.onyx", 1, home, "hangar")
  act(t, game, { kind = "Paint", actor = 0, item = onyx.id })
  t.eq({ ship.paint, ship.design } :: { any }, { "paint.onyx", "design.hoops" } :: { any })
  -- It is in the save.
  local bytes, length = Core.Save(game)
  local loaded = Core.Load(bytes, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.eq(loaded.state.ships[ship.id].paint, "paint.onyx")
  -- Out in space there is no painting; and back in, it is stripped, and nothing is given back.
  act(t, game, { kind = "Undock", actor = 0 })
  t.eq(refused(game, { kind = "Paint", actor = 0, item = crimson.id }), "not docked")
  t.eq(refused(game, { kind = "StripPaint", actor = 0 }), "not docked")
  local again = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local theirs = again.state.ships[again.state.player.ship]
  theirs.paint, theirs.design = "paint.onyx", "design.hoops"
  local stripped = assert(act(t, again, { kind = "StripPaint", actor = 0 }))
  t.eq({ stripped.stripped, theirs.paint, theirs.design } :: { any }, { true, nil, nil } :: { any })
  t.eq(#Items.In(again.state, again.state.player.home, "hangar"), #Items.In(Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true }).state,
    again.state.player.home, "hangar"))
  local _ = Codec
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
