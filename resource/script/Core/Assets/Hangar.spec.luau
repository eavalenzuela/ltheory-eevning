--!strict
-- The pilot's ships (Assets/Hangar, 2026-11-23): leaving one for the
-- capsule, docked and in space, boarding one left in space, naming one,
-- one taken where it was left, the corporation's hangar of ships, and
-- fitting out a ship that is not the one flown.

local Core = require("@lt/Core/Api")
local Hangar = require("@lt/Core/Assets/Hangar")
local Items = require("@lt/Core/Assets/Items")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Hangar")

local function newGame(): (Core.Game, number)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  return game, game.state.player.home
end

local function order(t: Test.Context, game: Core.Game, command: State.Command)
  command.actor = command.actor ~= 0 and command.actor or game.state.player.ship
  local ok, reason = Core.Submit(game, command)
  t.ok(ok, `{command.kind} was refused: {tostring(reason)}`)
  Core.Step(game)
end

local function refused(game: Core.Game, command: State.Command): string?
  command.actor = command.actor ~= 0 and command.actor or game.state.player.ship
  local ok, reason = Core.Validate(game, command)
  return if ok then "(accepted)" else reason
end

local function class(game: Core.Game): string
  return Ships.byId[game.state.ships[game.state.player.ship].type].class
end

suite:Case("docked, a pilot leaves their ship for a capsule they keep, and boards it again", function(t)
  local game, home = newGame()
  local state = game.state
  local ship = state.player.ship
  order(t, game, { kind = "LeaveShip", actor = 0 })
  t.eq(class(game), "capsule")
  t.eq({ state.ships[ship].docked, state.ships[state.player.ship].docked }, { home, home })
  t.eq(refused(game, { kind = "LeaveShip", actor = 0 }), "you are in your capsule already")
  -- (nobody puts them in a ship: they chose the capsule)
  for _ = 1, 5 do
    Core.Step(game)
  end
  t.eq(class(game), "capsule")
  local pod = state.player.ship
  order(t, game, { kind = "BoardShip", actor = 0, target = ship })
  t.eq(state.player.ship, ship)
  t.eq(state.ships[pod], nil)
end)

suite:Case("a ship is named, within reason", function(t)
  local game, home = newGame()
  local state = game.state
  local spare = Space.NewShip(state, "frigate.akashi", "Spare", "player", home)
  t.eq(refused(game, { kind = "RenameShip", actor = 0, target = spare.id, name = "  " }), "give it a name")
  t.eq(refused(game, { kind = "RenameShip", actor = 0, target = spare.id, name = string.rep("x", Hangar.NAME + 1) }),
    `a name is {Hangar.NAME} letters at most`)
  order(t, game, { kind = "RenameShip", actor = 0, target = spare.id, name = " Kestrel's Due " })
  t.eq(spare.name, "Kestrel's Due")
  order(t, game, { kind = "RenameShip", actor = 0, target = state.player.ship, name = "Mine" })
  t.eq(state.ships[state.player.ship].name, "Mine")
end)

suite:Case("in space, a ship left floats where it was, is boarded again from the capsule close by, and may be taken by a station's people", function(t)
  local game = newGame()
  local state = game.state
  local ship = state.player.ship
  Core.Submit(game, { kind = "Undock", actor = ship })
  Core.Step(game)
  local ball = assert(state.balls[ship])
  order(t, game, { kind = "LeaveShip", actor = 0 })
  local pod = state.player.ship
  t.eq(class(game), "capsule")
  t.ok(state.balls[pod] ~= nil and state.balls[ship] == ball, "the capsule is not out beside the ship")
  t.eq({ ball.mode, state.ships[ship].left ~= nil } :: { any }, { "stop", true } :: { any })
  -- (from the capsule, close by: and not from a ship)
  t.eq(refused(game, { kind = "BoardShip", actor = 0, target = ship }), "(accepted)")
  local pb = state.balls[pod]
  pb.x += 50000
  t.eq(refused(game, { kind = "BoardShip", actor = 0, target = ship }), `get within {Hangar.BOARD_RANGE} m of it`)
  pb.x -= 50000
  order(t, game, { kind = "BoardShip", actor = 0, target = ship })
  t.eq(state.player.ship, ship)
  t.eq({ state.ships[pod], state.balls[pod], state.ships[ship].left } :: { any }, { nil, nil, nil } :: { any })
  -- Left again, on grid with a station somebody else keeps: taken, in time.
  order(t, game, { kind = "LeaveShip", actor = 0 })
  local place = Space.Object(state, ball.grid)
  t.ok(place ~= nil and place.kind == "station", "the ship left is not on a station's grid")
  local theft = Hangar.THEFT
  Hangar.THEFT = 1
  local taken = false
  for _ = 1, 2 * Hangar.HOUR + 1 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      taken = taken or (event.kind == "ShipStolen" and event.ship == ship)
    end
  end
  Hangar.THEFT = theft
  t.ok(taken and state.ships[ship] == nil, "the ship left was not taken")
end)

suite:Case("ships go into the corporation's hangar and out; one is assembled there; another of the pilot's here is fitted out without boarding it", function(t)
  local game, home = newGame()
  local state = game.state
  local spare = Space.NewShip(state, "frigate.akashi", "Spare", "player", home)
  t.eq(refused(game, { kind = "MoveShip", actor = 0, target = spare.id, to = "corporate" }), "there is no corporation: found one first")
  state.wallet = 80000000
  order(t, game, { kind = "FoundCorporation", actor = 0, what = "Haven Holdings" })
  t.eq(refused(game, { kind = "MoveShip", actor = 0, target = state.player.ship, to = "corporate" }), "you are aboard it: board another first")
  order(t, game, { kind = "MoveShip", actor = 0, target = spare.id, to = "corporate" })
  t.eq(spare.corporate, true)
  t.eq(refused(game, { kind = "MoveShip", actor = 0, target = spare.id, to = "corporate" }), "it is in the corporation's hangar already")
  -- (the assets: the corporation's apart from the pilot's)
  local at: Core.AssetsAt? = nil
  for _, place in Core.Query.Assets(game) do
    at = if place.station == home then place else at
  end
  local there = assert(at)
  t.eq({ #there.ships, #there.corpShips, there.corpShips[1].id } :: { any }, { 1, 1, spare.id } :: { any })
  -- (a packaged hull in the corporation's hangar is assembled into a ship of its)
  local hull = Items.Add(state, "frigate.akashi", 1, home, "corporate")
  order(t, game, { kind = "Assemble", actor = 0, item = hull.id })
  local made = Core.Query.Ships(game, home)[3]
  t.eq({ made.type, made.corporate } :: { any }, { "frigate.akashi", true } :: { any })
  -- Fitted out where it lies, not boarded: what fitting is, for that ship; not for one elsewhere.
  local gun = Items.Add(state, "autocannon.small", 1, home, "hangar")
  state.skills.gunnery = 5
  order(t, game, { kind = "Fit", actor = spare.id, item = gun.id })
  t.eq(#Items.Fitted(state, spare.id), 1)
  t.eq(state.player.ship ~= spare.id, true)
  local away = Space.NewShip(state, "frigate.akashi", "Away", "player", 0)
  away.docked = state.galaxy.systems[1].id + 100000
  local more = Items.Add(state, "autocannon.small", 1, home, "hangar")
  t.eq(refused(game, { kind = "Fit", actor = away.id, item = more.id }), "that ship is not where you are")
  order(t, game, { kind = "MoveShip", actor = 0, target = spare.id, to = "hangar" })
  t.eq(spare.corporate, nil)
end)

return suite
