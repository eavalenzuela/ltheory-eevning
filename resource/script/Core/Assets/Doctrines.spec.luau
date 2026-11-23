--!strict
-- Doctrines (Assets/Doctrines, 2026-11-23): roles of saved fits, applied
-- to the fleet with the corporation's ships ready, or put together out of
-- its hangar from exact parts.

local Core = require("@lt/Core/Api")
local Corporation = require("@lt/Core/Assets/Corporation")
local Doctrines = require("@lt/Core/Assets/Doctrines")
local Items = require("@lt/Core/Assets/Items")
local Members = require("@lt/Core/Assets/Members")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Doctrines")

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

-- A fit kept by hand: a hull and its modules.
local function saved(state: State.State, name: string, hull: string, modules: { string }): State.SavedFit
  local fit: State.SavedFit = { id = State.NewId(state), name = name, hull = hull, modules = {} }
  for _, type in modules do
    table.insert(fit.modules, { type = type, charge = "" })
  end
  state.fits[fit.id] = fit
  table.insert(state.fitIds, fit.id)
  return fit
end

suite:Case("a doctrine applied gives each member of the fleet a ship fitted as their role is: one ready, or one put together from exact parts", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local home = state.player.home
  t.eq(refused(game, { kind = "NewDoctrine", actor = 0, name = "Line" }), "there is no corporation: found one first")
  state.corporation.name, state.corporation.founded = "Test Crew", state.tick
  state.membership.share = 0
  t.ok(Corporation.Founded(state))
  local dps = saved(state, "Two guns", "frigate.courier", { "autocannon.small", "autocannon.small" })
  local point = saved(state, "One gun", "frigate.courier", { "autocannon.small" })
  t.ok((submit(game, { kind = "NewDoctrine", actor = 0, name = "Line" })))
  t.eq(refused(game, { kind = "NewDoctrine", actor = 0, name = "line" }), "there is a doctrine of that name")
  local doctrine = Doctrines.List(state)[1]
  t.eq(refused(game, { kind = "ApplyDoctrine", actor = 0, target = doctrine.id }), "it has no roles yet")
  t.ok((submit(game, { kind = "AddDoctrineRole", actor = 0, target = doctrine.id, name = "DPS", item = dps.id })))
  t.ok((submit(game, { kind = "AddDoctrineRole", actor = 0, target = doctrine.id, name = "Tackle", item = point.id })))
  t.eq(refused(game, { kind = "AddDoctrineRole", actor = 0, target = doctrine.id, name = "dps", item = dps.id }), "it has a role of that name")
  t.eq(refused(game, { kind = "ApplyDoctrine", actor = 0, target = doctrine.id }), "nobody is in your fleet")
  -- Two members in the fleet, one set to tackle.
  local first = Members.Recruit(state, "Ana", "fighter", 2, {})
  local second = Members.Recruit(state, "Bo", "fighter", 2, {})
  for _, member in { first, second } do
    t.ok((submit(game, { kind = "InviteToFleet", actor = 0, what = `member:{member.id}` })))
  end
  t.ok((submit(game, { kind = "SetDoctrineRole", actor = 0, target = second.id, name = "Tackle" })))
  t.eq((assert(Doctrines.RoleFor(doctrine, second))).name, "Tackle")
  -- A ship of the corporation's as the first role is; the parts for the second's.
  local ready = Space.NewShip(state, "frigate.courier", "Ready", "player", home)
  ready.corporate = true
  for _ = 1, 2 do
    Items.Equip(state, ready.id, "autocannon.small", nil)
  end
  -- (and one of the pilot's own as it is: not the corporation's, not given)
  local mine = Space.NewShip(state, "frigate.courier", "Mine", "player", home)
  Items.Equip(state, mine.id, "autocannon.small", nil)
  Items.Add(state, "frigate.courier", 1, home, "corporate")
  local guns = Items.Add(state, "autocannon.small", 1, home, "corporate")
  local given, already, missed, short = Core.Query.DoctrinePlan(game, doctrine.id)
  t.eq({ given, already, #missed, short } :: { any }, { 2, 0, 0, "" } :: { any })
  t.ok((submit(game, { kind = "ApplyDoctrine", actor = 0, target = doctrine.id })))
  local a, b = state.fleet[first.fleet], state.fleet[second.fleet]
  t.eq(a.ship, ready.id)
  local made = state.ships[b.ship]
  t.ok(made ~= nil and made.corporate == true and Doctrines.Matches(state, made, point), "the tackle's ship was not put together")
  t.eq({ second.assigned, made.member, mine.pilot, state.items[guns.id] } :: { any }, { made.id, second.id, 0, nil } :: { any })
  -- Again: everybody flies theirs already. A third with nothing to make theirs of: short, said.
  given, already, missed, short = Core.Query.DoctrinePlan(game, doctrine.id)
  t.eq({ given, already, #missed } :: { any }, { 0, 2, 0 } :: { any })
  local third = Members.Recruit(state, "Cy", "fighter", 2, {})
  t.ok((submit(game, { kind = "InviteToFleet", actor = 0, what = `member:{third.id}` })))
  given, already, missed, short = Core.Query.DoctrinePlan(game, doctrine.id)
  t.eq({ given, already, #missed } :: { any }, { 0, 2, 1 } :: { any })
  t.ok(string.find(short, "Courier", 1, true) ~= nil and string.find(short, "2 x", 1, true) ~= nil, `short of: {short}`)
  -- (the first role put first again, and a role taken out)
  t.ok((submit(game, { kind = "MainDoctrineRole", actor = 0, target = doctrine.id, quantity = 2 })))
  t.eq(doctrine.roles[1].name, "Tackle")
  t.ok((submit(game, { kind = "RemoveDoctrineRole", actor = 0, target = doctrine.id, quantity = 2 })))
  t.eq(#doctrine.roles, 1)
  -- (in the save)
  local data, length = Core.Save(game)
  t.eq(Core.Hash(Core.Load(data, length)), Core.Hash(game))
  t.ok((submit(game, { kind = "DeleteDoctrine", actor = 0, target = doctrine.id })))
  t.eq(#Doctrines.List(state), 0)
end)

return suite
