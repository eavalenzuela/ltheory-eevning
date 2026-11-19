--!strict
-- Saved fittings (Assets/SavedFits): kept by name for a hull, put back on
-- from what is at hand, and what is not at hand said, to be bought.

local Core = require("@lt/Core/Api")
local Items = require("@lt/Core/Assets/Items")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("SavedFits")

local function refused(game: Core.Game, command: State.Command): string?
  command.actor = game.state.player.ship
  local ok, reason = Core.Validate(game, command)
  return if ok then "(accepted)" else reason
end

local function act(t: Test.Context, game: Core.Game, command: State.Command): { { [string]: any } }
  command.actor = game.state.player.ship
  local ok, reason = Core.Submit(game, command)
  t.ok(ok, `{command.kind} was refused: {tostring(reason)}`)
  Core.TakeEvents(game)
  Core.Step(game)
  return Core.TakeEvents(game)
end

-- What is fitted, as type and charge, rack by rack.
local function fitted(state: State.State, ship: number): { string }
  local out: { string } = {}
  for _, item in Items.Fitted(state, ship) do
    table.insert(out, `{item.type}:{item.charge}`)
  end
  return out
end

suite:Case("a fit is saved by name for its hull, put back on from the hangar with its charges, and what is not at hand is said", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local ship = state.player.ship
  local hull = state.ships[ship].type
  local home = state.ships[ship].docked
  local was = fitted(state, ship)
  t.ok(#was >= 2, "the ship a pilot begins in has little fitted")
  t.eq(refused(game, { kind = "SaveFit", actor = 0, name = "  " }), "give the fit a name")
  act(t, game, { kind = "SaveFit", actor = 0, name = "Starter" })
  local fits = Core.Query.Fits(game, hull)
  t.eq({ #fits, fits[1].name, #fits[1].modules, #fits[1].missing } :: { any }, { 1, "Starter", #was, 0 } :: { any })
  -- Everything off into the hangar: the fit puts it all back, charges and all.
  for _, item in Items.Fitted(state, ship) do
    act(t, game, { kind = "Unfit", actor = 0, item = item.id })
  end
  t.eq(#Items.Fitted(state, ship), 0)
  local events = act(t, game, { kind = "LoadFit", actor = 0, target = fits[1].id })
  t.eq(fitted(state, ship), was)
  local loaded: { [string]: any }? = nil
  for _, event in events do
    if event.kind == "FitLoaded" then
      loaded = event
    end
  end
  t.eq(#assert(loaded, "no word of it").missing, 0)
  -- One module gone from the hangar: the rest goes on, and that one is said, with what buying it here costs.
  local first = Items.Fitted(state, ship)[1]
  local gone = first.type
  act(t, game, { kind = "Unfit", actor = 0, item = first.id })
  for _, item in Items.In(state, home, "hangar") do
    if item.type == gone then
      Items.Take(state, item, item.quantity)
    end
  end
  local info = Core.Query.Fits(game, hull)[1]
  t.eq({ #info.missing, info.missing[1].type, info.missing[1].want - info.missing[1].have } :: { any }, { 1, gone, 1 } :: { any })
  events = act(t, game, { kind = "LoadFit", actor = 0, target = info.id })
  t.eq(#Items.Fitted(state, ship), #was - 1)
  local said: { string } = {}
  for _, event in events do
    if event.kind == "FitLoaded" then
      said = event.missing
    end
  end
  t.eq(said, { gone })
  -- Bought here, it goes on as well.
  local cost = info.missing[1].cost
  if cost then
    state.wallet = math.max(state.wallet, cost)
    act(t, game, { kind = "BuyNow", actor = 0, type = gone, quantity = 1 })
    act(t, game, { kind = "LoadFit", actor = 0, target = info.id })
    t.eq(fitted(state, ship), was)
  end
  -- Saved again under the same name, it is written over; deleted, it is gone.
  act(t, game, { kind = "SaveFit", actor = 0, name = "Starter" })
  t.eq(#Core.Query.Fits(game, hull), 1)
  act(t, game, { kind = "DeleteFit", actor = 0, target = info.id })
  t.eq(#Core.Query.Fits(game, hull), 0)
  t.eq(refused(game, { kind = "LoadFit", actor = 0, target = info.id }), "no such fit")
end)

suite:Case("a fit is for its own hull, and is put on docked", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local ship = state.player.ship
  act(t, game, { kind = "SaveFit", actor = 0, name = "Mine" })
  local fit = state.fits[state.fitIds[1]]
  fit.hull = "frigate.courier" == state.ships[ship].type and "frigate.javelin" or "frigate.courier"
  t.ok(string.find(refused(game, { kind = "LoadFit", actor = 0, target = fit.id }) or "", "that is a fit for", 1, true) ~= nil)
  fit.hull = state.ships[ship].type
  act(t, game, { kind = "Undock", actor = 0 })
  t.eq(refused(game, { kind = "LoadFit", actor = 0, target = fit.id }), "a fit is put on docked")
  -- (and it is in the save)
  local data, length = Core.Save(game)
  t.eq(Core.Hash(Core.Load(data, length)), Core.Hash(game))
end)

return suite
