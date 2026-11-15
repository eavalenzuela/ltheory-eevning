--!strict
-- The corporation's members as ships where the pilot is (Tactical/Fellows).

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Commerce = require("@lt/Core/Strategic/Commerce")
local Core = require("@lt/Core/Api")
local Fellows = require("@lt/Core/Tactical/Fellows")
local Items = require("@lt/Core/Assets/Items")
local Members = require("@lt/Core/Assets/Members")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")
local Test = require("@lt/Tool/Test")
local Types = require("@lt/Core/Data/Types")

local suite = Test.Suite("Fellows")

-- A game with the pilot docked at home, nobody about but who is put
-- there, and the system the pilot is in.
local function begun(): (Core.Game, number)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, systems = 40, peaceful = true })
  return game, Space.SystemOf(game.state, game.state.player.home)
end

-- A member of a trade, joined by hand, working in a system: in the hull
-- of a class that a member of that trade flies.
local function member(game: Core.Game, trade: string, class: string, system: number): State.Member
  local state = game.state
  local one: State.Member = { id = State.NewId(state), name = "Test " .. trade, trade = trade, people = "vessari",
    hull = assert(Members.HullFor(trade, "vessari", class)), bears = 0.3, wealth = 0, earned = 0, paid = 0, joined = state.tick,
    system = system, doing = "idle", call = 0, lean = 0, day = 0,
    ship = 0, task = "", goal = 0, since = 0, wait = 0, back = 0, refit = 0, lost = 0 }
  state.membership.members[one.id] = one
  table.insert(state.membership.memberIds, one.id)
  return one
end

-- Step until something is so, so many ticks at most: whether it came to be.
local function untilSo(game: Core.Game, most: number, so: () -> boolean): boolean
  for _ = 1, most do
    if so() then
      return true
    end
    Core.Step(game)
    Core.TakeEvents(game)
  end
  return so()
end

local function kindOf(state: State.State, id: number): string
  local object = Space.Object(state, id)
  return if object then object.kind else "?"
end

suite:Case("a member who mines is at a belt where the pilot is, cutting rock in their own ship; goes in, and comes out again", function(t)
  local game, home = begun()
  local state = game.state
  local miner = member(game, "miner", "frigate", home)
  t.eq(miner.hull, "frigate.prospector")
  Core.Step(game)
  local ship = state.ships[miner.ship]
  t.ok(ship ~= nil, "the miner has no ship where the pilot is")
  t.eq({ ship.name, ship.owner, ship.type, miner.task, kindOf(state, miner.goal) }, { "Test miner", "member", "frigate.prospector", "work", "belt" })
  t.eq(state.balls[ship.id].grid, miner.goal)
  t.eq(Members.Of(state, ship.id), miner)
  -- It cuts rock: there is ore in the hold before long.
  t.ok(untilSo(game, 240, function()
    return Items.CargoUsed(state, ship.id) > 0
  end), "nothing was mined")
  -- Shot at, it goes in to a station; and after a while it is out again, and at the belt.
  local belt = miner.goal
  state.balls[ship.id].vitals.shield = 0
  Core.Step(game)
  t.eq({ miner.task, kindOf(state, miner.goal) }, { "home", "station" })
  t.ok(untilSo(game, 400, function()
    return miner.task == "rest"
  end), "it never docked")
  t.eq({ miner.ship, state.ships[ship.id] } :: { any }, { 0, nil } :: { any })
  local rested = state.tick
  t.ok(untilSo(game, Fellows.REST + 5, function()
    return miner.ship ~= 0
  end), "it never came out again")
  t.ok(state.tick - rested >= Fellows.REST - 1, `out again after {state.tick - rested} ticks`)
  t.eq({ miner.task, miner.goal } :: { any }, { "out", belt } :: { any })
  t.ok(untilSo(game, 400, function()
    return miner.task == "work" and state.balls[miner.ship] ~= nil and state.balls[miner.ship].grid == belt
  end), "it never got back to the belt")
  -- A pirate at the belt takes it for what it is, one of the pilot's side: and with a pirate after it, it runs.
  local ball = state.balls[miner.ship]
  local pirate = Pirates.Spawn(state, Pirates.kindById["raider"], home, ball.x + 9000, ball.y, ball.z, belt)
  Core.Step(game)
  t.eq({ state.pilots[pirate.id].prey, miner.task } :: { any }, { miner.ship, "work" } :: { any })
  Core.Step(game)
  t.eq(miner.task, "home")
  -- (a save with a member's ship out is the same game loaded)
  local data, length = Core.Save(game)
  t.eq(Core.Hash(Core.Load(data, length)), Core.Hash(game))
  -- When they are working somewhere the pilot is not, there is no ship: it is not lost.
  local was = miner.ship
  miner.system = if home == 1 then 2 else 1
  Core.Step(game)
  t.eq({ miner.ship, miner.task, miner.lost, state.ships[was], state.balls[was] } :: { any }, { 0, "", 0, nil, nil } :: { any })
end)

suite:Case("a member who hauls goes out by the gate for where the goods go for most, with goods that are the economy's", function(t)
  local game, home = begun()
  local state = game.state
  local econ = state.commerce
  -- Something is short next door: that is where a hauler takes it.
  local next = state.galaxy.systems[home].neighbors[1]
  local class = assert(Commerce.Index("ore.ferrite"))
  econ.nodes[next].stock[class] *= 0.1
  local what, to = Members.Haul(state, home)
  t.eq({ what, to }, { class, next })
  local hauler = member(game, "hauler", "industrial", home)
  -- (in the station, as one is who has been in: so it is on its way out that the pilot sees them)
  hauler.task, hauler.goal = "rest", state.player.home
  local had, wanted = econ.nodes[home].stock[class], econ.nodes[next].stock[class]
  Core.Step(game)
  local ship = state.ships[hauler.ship]
  t.ok(ship ~= nil and hauler.carries ~= nil, "the hauler did not come out laden")
  local carries = assert(hauler.carries)
  t.eq({ hauler.task, kindOf(state, hauler.goal), carries.node, carries.class } :: { any }, { "out", "gate", next, class } :: { any })
  t.eq((Space.Object(state, hauler.goal) :: System.Object).to, next)
  t.ok(carries.amount >= 1 and carries.amount == math.floor(carries.amount))
  -- What is aboard came out of this system's stock, and is in the hold.
  t.near(had - econ.nodes[home].stock[class], carries.amount, 1e-6)
  local aboard = 0
  for _, item in Items.In(state, ship.id, "cargo") do
    aboard += if item.type == "ore.ferrite" then item.quantity else 0
  end
  t.eq(aboard, carries.amount)
  t.ok(aboard * Types.Info("ore.ferrite").volume <= Ships.byId[hauler.hull].cargo)
  -- Through the gate, it is the next system's.
  local before = econ.nodes[next].stock[class]
  t.ok(untilSo(game, 500, function()
    if hauler.task ~= "away" then
      before = econ.nodes[next].stock[class]
    end
    return hauler.task == "away"
  end), "it never went through the gate")
  t.ok(state.tick % Commerce.STEP ~= 0, "(the economy stepped on the tick it went through: move the test)")
  t.near(econ.nodes[next].stock[class] - before, carries.amount, 1e-6)
  t.eq({ hauler.ship, hauler.carries, state.ships[ship.id] } :: { any }, { 0, nil, nil } :: { any })
  t.ok(econ.nodes[next].stock[class] > wanted)
  -- And after a while it is back by that gate, and goes in.
  local gate = hauler.goal
  t.ok(untilSo(game, Fellows.AWAY + 5, function()
    return hauler.ship ~= 0
  end), "it never came back")
  t.eq({ hauler.task, kindOf(state, hauler.goal) }, { "home", "station" })
  t.eq(state.balls[hauler.ship].grid, gate)
  t.eq(#Items.In(state, hauler.ship, "cargo"), 0)
  t.ok(untilSo(game, 500, function()
    return hauler.task == "rest"
  end), "it never docked")
end)

suite:Case("a member who fights keeps a post, and goes to the pirates who come for the pilot's side", function(t)
  local game, home = begun()
  local state = game.state
  local fighter = member(game, "fighter", "frigate", home)
  local scout = member(game, "scout", "frigate", home)
  Core.Step(game)
  local ship = state.ships[fighter.ship]
  t.ok(ship ~= nil and state.ships[scout.ship] ~= nil, "they have no ships where the pilot is")
  t.eq({ ship.owner, ship.type, fighter.task }, { "member", fighter.hull, "work" })
  t.ok(#Items.Fitted(state, ship.id) > 0, "a fighter's ship has nothing fitted")
  local post = fighter.goal
  t.ok(kindOf(state, post) == "gate" or kindOf(state, post) == "belt", kindOf(state, post))
  t.eq({ state.balls[ship.id].grid, state.balls[ship.id].mode, state.pilots[ship.id] } :: { any }, { post, "orbit", nil } :: { any })
  -- The pilot is at a belt somewhere else, and a pirate comes for them.
  assert(Core.Submit(game, { kind = "Undock", actor = state.player.ship }))
  Core.Step(game)
  local belt: System.Object? = nil
  for _, object in Space.Describe(state, home).objects do
    if object.kind == "belt" and object.id ~= post and state.sites[object.id] == nil then
      belt = belt or object
    end
  end
  local at = assert(belt, "the home system has no other belt")
  local me = state.balls[state.player.ship]
  me.x, me.y, me.z = at.x, at.y + 20000, at.z
  me.vx, me.vy, me.vz = 0, 0, 0
  Space.AssignGrid(state, me)
  local pirate = Pirates.Spawn(state, Pirates.kindById["raider"], home, me.x + 15000, me.y, me.z, at.id)
  Core.Step(game)
  t.eq(state.pilots[pirate.id].prey, me.id)
  -- The fighter warps to them, and fights the pirate (and nobody else).
  t.ok(untilSo(game, 300, function()
    local record = state.pilots[fighter.ship]
    return record ~= nil and record.prey == pirate.id
  end), "the fighter never came")
  t.eq({ state.balls[fighter.ship].grid, state.pilots[fighter.ship].side } :: { any }, { me.grid, "player" } :: { any })
  local own, hostile = false, false
  for _, entry in Core.Query.Overview(game) do
    if entry.id == fighter.ship then
      own, hostile = entry.own, entry.hostile
    end
  end
  t.eq({ own, hostile }, { true, false })
  -- The pirate gone, they stand down, and go back to their post.
  Aftermath.Destroy(state, pirate.id, fighter.ship, game.events)
  Core.Step(game)
  t.eq(state.pilots[fighter.ship], nil)
  t.ok(untilSo(game, 400, function()
    local ball = state.balls[fighter.ship]
    return ball ~= nil and ball.grid == post and ball.mode == "orbit"
  end), "the fighter never went back to their post")
  t.eq(fighter.lost, 0)
  -- A scout goes from place to place.
  local first = scout.goal
  t.ok(untilSo(game, Fellows.SURVEY + 5, function()
    return scout.goal ~= first
  end), "the scout stayed where they were")
end)

suite:Case("a ship that is destroyed is the member's loss: time out of work, and the best hull they have the price of", function(t)
  local game, home = begun()
  local state = game.state
  local poor = member(game, "fighter", "cruiser", home)
  local rich = member(game, "fighter", "cruiser", home)
  local wronged = member(game, "miner", "frigate", home)
  local cruiser = poor.hull
  rich.wealth = 2 * Types.Info(cruiser).basePrice
  Core.Step(game)
  t.ok(poor.ship ~= 0 and rich.ship ~= 0 and wronged.ship ~= 0, "they have no ships where the pilot is")
  t.eq((select(1, Members.Watching(state, home))), 2)
  -- Somebody else destroys two of them, and the pilot the third.
  local events: { any } = {}
  Aftermath.Destroy(state, poor.ship, 0, events)
  Aftermath.Destroy(state, rich.ship, 0, events)
  Aftermath.Destroy(state, wronged.ship, state.player.ship, events)
  Fellows.Step(state, events, 1)
  local said: { [string]: { any } } = {}
  for _, event in events do
    said[event.kind] = said[event.kind] or {}
    table.insert(said[event.kind], event)
  end
  t.eq(#said.MemberLost, 3)
  -- One with nothing put by is in the first hull of their trade; one with the price of it has the same again, and has paid for it.
  local frigate = assert(Members.HullFor("fighter", "vessari", "frigate"))
  t.eq({ poor.hull, poor.wealth, poor.lost, poor.ship, poor.doing } :: { any }, { frigate, 0, 1, 0, "refitting" } :: { any })
  t.eq({ rich.hull, rich.wealth, rich.lost } :: { any }, { cruiser, Types.Info(cruiser).basePrice, 1 } :: { any })
  t.eq(poor.refit, state.tick + Members.REFIT)
  -- One the pilot's own side destroyed is a member no longer.
  t.eq(state.membership.members[wronged.id], nil)
  t.eq({ said.MemberLeft[1].name, said.MemberLeft[1].why }, { "Test miner", "fired on by their own" })
  -- Until they have another ship they are not out, do no work, and are nobody's defence.
  t.eq((select(1, Members.Watching(state, home))), 0)
  Core.Step(game)
  t.eq({ poor.ship, rich.ship }, { 0, 0 })
  local earned = rich.earned
  state.tick = (state.tick // Members.HOUR + 1) * Members.HOUR
  Members.Step(state, {})
  t.eq({ rich.earned, rich.doing } :: { any }, { earned, "refitting" } :: { any })
  state.tick = poor.refit
  Core.Step(game)
  t.ok(poor.ship ~= 0 and rich.ship ~= 0, "they never came out again")
  t.eq({ state.ships[poor.ship].type, state.ships[rich.ship].type }, { frigate, cruiser })
  t.eq((select(1, Members.Watching(state, home))), 2)
end)

return suite
