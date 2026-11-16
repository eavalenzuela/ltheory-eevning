--!strict
-- Something rare, seen for an hour or two (Tactical/Sightings).

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Blueprints = require("@lt/Core/Data/Blueprints")
local Constants = require("@lt/Core/Data/Constants")
local Structures = require("@lt/Core/Data/Structures")
local Contracts = require("@lt/Core/Assets/Contracts")
local Core = require("@lt/Core/Api")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Happenings = require("@lt/Core/Strategic/Happenings")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Sightings = require("@lt/Core/Tactical/Sightings")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Sightings")

type Event = { [string]: any }

local HOUR = math.floor(3600 / Constants.TICK + 0.5)

local function ended(events: { Event }): Event?
  for _, event in events do
    if event.kind == "HappeningEnded" then
      return event
    end
  end
  return nil
end

-- A game with the pilot's ship in space, at rest, a long way from the station they began at.
local function away(peaceful: boolean?): (Core.Game, State.State, State.Ball)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, systems = 40, peaceful = peaceful })
  local state = game.state
  assert(Core.Submit(game, { kind = "Undock", actor = state.player.ship }))
  Core.Step(game)
  local me = state.balls[state.player.ship]
  me.x += 5e7
  me.vx, me.vy, me.vz, me.tvx, me.tvy, me.tvz = 0, 0, 0, 0, 0, 0
  me.mode = "stop"
  Space.AssignGrid(state, me)
  Core.TakeEvents(game)
  return game, state, me
end

suite:Case("now and then something is sighted within reach of the pilot: never more than three, and each the kind its place allows", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, systems = 40 })
  local state = game.state
  local all = state.happenings
  t.ok(all.sightingDue >= 0.5 * HOUR and all.sightingDue <= HOUR + 1, `the first sighting is due in {all.sightingDue / HOUR} hours`)
  local events: { Event } = {}
  local kinds: { [string]: number } = {}
  local most = 0
  -- (by the minute, for two days, with nobody going anywhere)
  for _ = 1, 48 * 60 do
    state.tick += 60
    Sightings.Step(state, 1, events)
    local on = 0
    for _, one in all.list do
      on += if one.kind == Happenings.SIGHTING then 1 else 0
    end
    most = math.max(most, on)
  end
  local far = Happenings.Reach(state, 1, Sightings.REACH)
  local began = 0
  for _, event in events do
    if event.kind == "HappeningBegan" then
      began += 1
      kinds[event.what] = (kinds[event.what] or 0) + 1
      t.ok(far[event.system] ~= nil, "a sighting out of reach of the pilot")
      local band = Galaxy.Band(state.galaxy.systems[event.system].security)
      t.ok(event.what ~= "captain" or band ~= "secure", "a pirate captain where order is kept")
      t.ok((event.what == "derelict") == (event.name == ""), "a captain and a trader have a name, and a derelict none")
    end
  end
  t.ok(began >= 20 and began <= 48 * 2, `{began} sightings in two days`)
  t.ok(most <= Sightings.MOST and most >= 2, `{most} on at once at the most`)
  t.ok((kinds.captain or 0) > 0 and (kinds.derelict or 0) > 0 and (kinds.trader or 0) > 0, "one of the three kinds never came")
  -- (and all of them were over in their time: none is older than the longest lasts)
  for _, one in all.list do
    t.ok(state.tick - one.began <= 4 * HOUR)
  end
  -- In a game with no pirates there are no captains, and in uncharted space nothing is sighted.
  local quiet = Core.New({ galaxySeed = 1, historySeed = 1, systems = 40, peaceful = true }).state
  local heard: { Event } = {}
  for _ = 1, 24 * 60 do
    quiet.tick += 60
    Sightings.Step(quiet, 1, heard)
  end
  for _, event in heard do
    t.ok(event.kind ~= "HappeningBegan" or event.what ~= "captain", "a captain in a game with no pirates")
  end
  local deep = Core.New({ galaxySeed = 1, historySeed = 1, systems = 40 }).state
  local none: { Event } = {}
  for _ = 1, 6 * 60 do
    deep.tick += 60
    Sightings.Step(deep, Galaxy.Charted(deep.galaxy) + 1, none)
  end
  t.eq(#none, 0)
end)

suite:Case("a captain: their camp is a place when the pilot is in the system, they are there with their escort, and what they carried is in the wreck", function(t)
  local game, state, me = away()
  local one = Happenings.Begin(state, Happenings.SIGHTING, "captain", me.system, 0, 2 * HOUR, 1, "Mara Venn", game.events)
  -- Somewhere else, nothing is put anywhere.
  Sightings.Step(state, 2, game.events)
  t.eq(one.place, 0)
  -- Here, their camp is staked: a place on the overview.
  Sightings.Step(state, me.system, game.events)
  t.ok(one.place ~= 0, "the camp was not staked")
  local place = assert(Space.Object(state, one.place))
  t.ok(string.find(place.name, "Mara Venn's Camp", 1, true) ~= nil, place.name)
  local listed = false
  for _, entry in Core.Query.Overview(game) do
    listed = listed or entry.id == one.place
  end
  t.ok(listed, "the camp is not on the overview")
  t.eq({ one.stage, #state.pilotIds }, { 1, 0 })
  -- The pilot comes to it: the captain and two with them, the captain by name and worth three captains.
  me.x, me.y, me.z = place.x, place.y, place.z
  Space.AssignGrid(state, me)
  t.eq(me.grid, one.place)
  Sightings.Step(state, me.system, game.events)
  t.eq({ one.stage, #state.pilotIds }, { 2, 3 })
  local captain = assert(one.ref)
  local band = if Galaxy.Band(state.galaxy.systems[me.system].security) == "lawless" then "lawless" else "low"
  local kind = Pirates.Graded(Pirates.kindById[Sightings.CAPTAIN[band]], 2)
  t.eq({ state.ships[captain].name, state.balls[captain].name, state.pilots[captain].bounty } :: { any },
    { "Mara Venn", "Mara Venn", kind.bounty * Sightings.BOUNTY } :: { any })
  t.near(Space.Distance(place :: any, state.balls[captain] :: any), Sightings.OUT, 1)
  -- Destroyed: the wreck has what such a one carries, and the sighting is over, taken.
  Core.TakeEvents(game)
  Aftermath.Destroy(state, captain, state.player.ship, game.events)
  Sightings.Step(state, me.system, game.events)
  local over = assert(ended(Core.TakeEvents(game)), "the sighting did not end")
  t.eq({ over.outcome, over.what, over.name, over.kills } :: { any }, { "taken", "captain", "Mara Venn", 1 } :: { any })
  t.eq(Happenings.Get(state, one.id), nil)
  local wreck = 0
  for _, id in state.wreckIds do
    wreck = if state.wrecks[id].name == "Mara Venn Wreck" then id else wreck
  end
  t.ok(wreck ~= 0, "the captain left no wreck")
  local customs, tags, theirs, mutators = 0, 0, 0, 0
  for _, item in Items.In(state, wreck, nil) do
    local module = Modules.byId[item.type]
    customs += if module and module.meta == 1 then item.quantity else 0
    tags += if item.type == "tag.pirate" then item.quantity else 0
    -- (and, an officer by name, modules that are theirs: better than a masterwork, and called by their name)
    theirs += if module and module.officer == "Mara Venn" and module.meta == 4 then item.quantity else 0
    mutators += if item.type == "mutator" then item.quantity else 0
  end
  t.ok(customs >= Sightings.PRIZES, `only {customs} custom makes in the wreck`)
  t.ok(tags >= Sightings.TAGS, `only {tags} tags in the wreck`)
  t.eq({ theirs, mutators }, { Sightings.THEIRS, Sightings.MUTATORS }, "an officer's own modules, and a mutator")
  -- (and a copy of a pirate tower's drawings, good for a run or a few, and never the original: the owner's, 2026-11-16)
  local copies, originals = 0, 0
  for _, item in Items.In(state, wreck, nil) do
    local print, copy = Blueprints.Of(item.type)
    local tower = if print then Structures.towerById[print.product] else nil
    if tower and tower.faction == "unbound" then
      copies += if copy then 1 else 0
      originals += if copy then 0 else 1
      t.ok(not copy or (item.quantity >= 1 and item.quantity <= Pirates.TOWER_RUNS), `{item.quantity} runs`)
    end
  end
  t.eq({ copies, originals } :: { any }, { 1, 0 } :: { any })
  -- (and the camp is let go)
  t.ok(state.sites[one.place].gone)

  -- One nobody comes for is gone when its time is, and its camp with it.
  local second = Happenings.Begin(state, Happenings.SIGHTING, "captain", me.system, 0, HOUR, 1, "Odo Kest", game.events)
  Sightings.Step(state, me.system, game.events)
  t.ok(second.place ~= 0)
  state.tick += HOUR
  Core.TakeEvents(game)
  Sightings.Step(state, me.system, game.events)
  t.eq(assert(ended(Core.TakeEvents(game))).outcome, "gone")
  t.ok(state.sites[second.place].gone)
end)

suite:Case("a derelict: found already where the pilot is, and gone with the sighting", function(t)
  local game, state, me = away(true)
  local one = Happenings.Begin(state, Happenings.SIGHTING, "derelict", me.system, 0, 2 * HOUR, 1, "", game.events)
  Sightings.Step(state, me.system, game.events)
  t.ok(one.place ~= 0, "the derelict was not put there")
  local site = state.sites[one.place]
  t.eq({ site.kind, site.strength, site.expires } :: { any }, { "relic", 1, one.ends } :: { any })
  local found = false
  for _, entry in Core.Query.Overview(game) do
    found = found or entry.id == one.place
  end
  t.ok(found, "a sighted derelict should be on the overview without a scan")
  -- Emptied (the site says so), the sighting is over.
  site.gone = true
  Core.TakeEvents(game)
  Sightings.Step(state, me.system, game.events)
  t.eq(assert(ended(Core.TakeEvents(game))).outcome, "taken")
end)

suite:Case("a trader: three lots of their own on the board of the station they lie at, each theirs once, and gone when they go", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, systems = 40, peaceful = true })
  local state = game.state
  local home = state.player.home
  local plain = #Contracts.Board(state, home)
  local one = Happenings.Begin(state, Happenings.SIGHTING, "trader", 1, home, 2 * HOUR, 1, "Ilse Rahn", game.events)
  local theirs: { Contracts.Lot } = {}
  for _, lot in Contracts.Board(state, home) do
    if lot.slot > Contracts.OFFERS and lot.side == "offer" then
      table.insert(theirs, lot)
    end
  end
  t.eq({ #Contracts.Board(state, home), #theirs }, { plain + Contracts.TRADER, Contracts.TRADER })
  for _, lot in theirs do
    t.ok(string.find(lot.title, "Ilse Rahn", 1, true) ~= nil, lot.title)
    t.ok(lot.price > 0 and lot.price <= lot.worth * 1.2 + 1, `{lot.title}: {lot.price} for what is worth {lot.worth}`)
  end
  -- One is bought: it is in the hangar, and not on the board again.
  local lot = theirs[1]
  state.wallet = lot.price + 1000
  local ok, why = Core.Submit(game, { kind = "AcceptContract", actor = state.player.ship, target = lot.slot })
  t.ok(ok, `the trader's lot was refused: {tostring(why)}`)
  Core.Step(game)
  t.eq(state.wallet, 1000)
  local got = 0
  for _, item in Items.In(state, home, "hangar") do
    got += if item.type == lot.stacks[1].type then item.quantity else 0
  end
  t.ok(got >= lot.stacks[1].quantity, "the lot is not in the hangar")
  t.eq(Contracts.Lot(state, home, "offer", lot.slot), nil)
  t.eq(#Contracts.Board(state, home), plain + Contracts.TRADER - 1)
  -- When they go, so do their lots.
  state.tick = one.ends
  Sightings.Step(state, 1, game.events)
  t.eq(#Contracts.Board(state, home), plain)
end)

return suite
