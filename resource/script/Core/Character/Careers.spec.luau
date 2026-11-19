--!strict
-- The career agents (Character/Careers).

local Careers = require("@lt/Core/Character/Careers")
local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Items = require("@lt/Core/Assets/Items")
local Ships = require("@lt/Core/Data/Ships")
local Sites = require("@lt/Core/Tactical/Sites")
local Standings = require("@lt/Core/Assets/Standings")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")
local Types = require("@lt/Core/Data/Types")

local suite = Test.Suite("Careers")

local function new(): (Core.Game, State.State, number, number)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  return game, game.state, game.state.player.ship, game.state.player.home
end

-- How many of a type are loose in a station's hangar.
local function hangar(state: State.State, station: number, type: string): number
  local have = 0
  for _, item in Items.In(state, station, "hangar") do
    have += if item.type == type and item.slot == 0 then item.quantity else 0
  end
  return have
end

-- The events of a kind among those not yet taken.
local function said(game: Core.Game, kind: string): { Careers.Event }
  local found: { Careers.Event } = {}
  for _, event in Core.TakeEvents(game) do
    if event.kind == kind then
      table.insert(found, event)
    end
  end
  return found
end

local function row(game: Core.Game, id: string): Core.CareerRow
  for _, each in Core.Query.Careers(game).rows do
    if each.career.id == id then
      return each
    end
  end
  error(`no career '{id}'`)
end

suite:Case("every career has lessons that say what to do, can be done one way, and give things there are", function(t)
  local ids: { string } = {}
  for _, career in Careers.list do
    table.insert(ids, career.id)
    t.eq(Careers.byId[career.id], career)
    t.ok(#career.name <= 16 and #career.about <= 70, `'{career.name}' says too much of itself`)
    t.ok(#career.lessons >= 4 and #career.lessons <= 5)
    for _, lesson in career.lessons do
      local where = `{career.id}: '{lesson.title}'`
      t.ok(#lesson.title > 3 and #lesson.title <= 24, `{where} is too long a title`)
      t.ok(#lesson.aim > 3 and #lesson.aim <= 36, `{where}: its aim takes {#lesson.aim} letters`)
      -- (what the agent says has to fit its place on the page: seven lines)
      t.ok(#lesson.says > 40 and #lesson.says <= 380, `{where}: the agent says {#lesson.says} letters`)
      t.ok(lesson.credits >= 2000)
      local ways = (if lesson.on ~= "" then 1 else 0) + (if lesson.skill then 1 else 0) + (if lesson.bring then 1 else 0)
      t.eq(ways, 1, `{where} can be done {ways} ways`)
      t.ok(if lesson.bring then lesson.need == 0 else lesson.need >= 1, `{where} wants {lesson.need}`)
      for _, stack in lesson.kit do
        t.ok(Types.Get(stack.type) ~= nil and stack.quantity >= 1, `{where} hands over '{stack.type}', which is nothing`)
      end
      for _, stack in lesson.gifts do
        t.ok(Types.Get(stack.type) ~= nil and stack.quantity >= 1, `{where} gives '{stack.type}', which is nothing`)
      end
      t.ok(lesson.bring == nil or Types.Get(lesson.bring.type) ~= nil)
      t.ok(lesson.site == nil or lesson.site == "ore" or lesson.site == "relic")
    end
  end
  t.eq(ids, { "flight", "industry", "trade", "combat", "survey", "command", "planets" })
end)

suite:Case("a lesson is taken at the agents' station, done in space, reported there, and paid", function(t)
  local game, state, mine, home = new()
  local status = Core.Query.Careers(game)
  t.eq({ #status.rows, status.station, status.here, status.begun } :: { any }, { 7, home, true, false } :: { any })
  local first = status.rows[1]
  t.eq({ first.career.id, first.done, first.taken, first.can, first.lesson and first.lesson.title } :: { any },
    { "flight", 0, false, true, "Out and back" } :: { any })
  t.ok(#first.agent > 3 and first.agent == Careers.Agent(state, "flight") and first.agent ~= Careers.Agent(state, "survey"))
  -- Nothing can be reported that has not been taken, and nobody has a career of no name.
  t.eq({ Core.Validate(game, { kind = "CompleteLesson", actor = mine, what = "flight" }) } :: { any }, { false, "no lesson of theirs is in hand" } :: { any })
  t.eq({ Core.Validate(game, { kind = "AcceptLesson", actor = mine, what = "piracy" }) } :: { any }, { false, "no such career" } :: { any })

  t.ok((Core.Submit(game, { kind = "AcceptLesson", actor = mine, what = "flight" })))
  Core.Step(game)
  t.eq(state.careers.flight, { done = 0, taken = true, count = 0, again = false })
  local taken = said(game, "LessonTaken")
  t.eq({ #taken, taken[1].career, taken[1].lesson, taken[1].title, taken[1].agent } :: { any }, { 1, "flight", 1, "Out and back", first.agent } :: { any })
  t.eq({ Core.Validate(game, { kind = "AcceptLesson", actor = mine, what = "flight" }) } :: { any }, { false, "that lesson is in hand already" } :: { any })
  t.eq({ Core.Validate(game, { kind = "CompleteLesson", actor = mine, what = "flight" }) } :: { any }, { false, "still to do" } :: { any })
  t.eq({ row(game, "flight").have, row(game, "flight").need, row(game, "flight").can } :: { any }, { 0, 1, false } :: { any })
  t.ok(Core.Query.Careers(game).begun)

  -- Out, a warp to a planet, and back.
  local planet = 0
  for _, object in Core.Query.Objects(game, 1) do
    if object.kind == "planet" and planet == 0 then
      planet = object.id
    end
  end
  t.ok((Core.Submit(game, { kind = "Undock", actor = mine })))
  Core.Step(game)
  t.ok((Core.Submit(game, { kind = "WarpTo", actor = mine, target = planet })))
  local ready: { Careers.Event } = {}
  for _ = 1, 400 do
    Core.Step(game)
    for _, event in said(game, "LessonReady") do
      table.insert(ready, event)
    end
    if #ready > 0 and state.balls[mine].warp == nil then
      break
    end
  end
  t.eq({ #ready, ready[1].career, ready[1].title } :: { any }, { 1, "flight", "Out and back" } :: { any })
  t.eq(state.careers.flight.count, 1)
  -- (it is reported at the station, not from out here)
  local can, why = Core.Validate(game, { kind = "CompleteLesson", actor = mine, what = "flight" })
  t.ok(not can and string.find(why or "", "the career agents are at ", 1, true) == 1, why)
  t.ok(not Core.Query.Careers(game).here)
  t.ok((Core.Submit(game, { kind = "Dock", actor = mine, target = home })))
  for _ = 1, 600 do
    Core.Step(game)
    if state.ships[mine].docked == home then
      break
    end
  end
  t.eq(state.ships[mine].docked, home)
  Core.TakeEvents(game)
  local wallet, faction = state.wallet, state.galaxy.systems[1].nearest
  t.ok(row(game, "flight").can)
  t.ok((Core.Submit(game, { kind = "CompleteLesson", actor = mine, what = "flight" })))
  Core.Step(game)
  t.eq(state.careers.flight, { done = 1, taken = false, count = 0, again = false })
  t.eq(state.wallet, wallet + 2000)
  t.near(Standings.Of(state, faction), Careers.STANDING, 1e-9)
  local done = said(game, "LessonDone")
  t.eq({ #done, done[1].career, done[1].lesson, done[1].credits, done[1].finished } :: { any }, { 1, "flight", 1, 2000, false } :: { any })
  -- The agent's next is there to take.
  local next = row(game, "flight")
  t.eq({ next.done, next.taken, next.can, next.lesson and next.lesson.title } :: { any }, { 1, false, true, "A place of your own" } :: { any })
end)

suite:Case("the flight school can be flown from its first lesson to its last", function(t)
  local game, state, mine, home = new()
  local function order(kind: string, target: number?)
    local ok, reason = Core.Submit(game, { kind = kind, actor = mine, target = target })
    t.ok(ok, `{kind} was refused: {tostring(reason)}`)
  end
  local function lesson(kind: string)
    local ok, reason = Core.Submit(game, { kind = kind, actor = mine, what = "flight" })
    t.ok(ok, `{kind} was refused: {tostring(reason)}`)
    Core.Step(game)
  end
  -- Step until an event of a kind that is the pilot's ship's.
  local function till(kind: string, limit: number): Careers.Event
    for _ = 1, limit do
      Core.Step(game)
      for _, event in Core.TakeEvents(game) do
        if event.kind == kind and (event.ship == mine or event.ball == mine) then
          return event
        end
      end
    end
    error(`no {kind} within {limit} ticks`, 2)
  end
  local function nearest(kind: string, but: number?): number
    for _, entry in Core.Query.Overview(game) do
      if entry.kind == kind and entry.id ~= but then
        return entry.id
      end
    end
    return 0
  end
  local function homeAndReport(done: number)
    order("Dock", home)
    till("Docked", 6000)
    lesson("CompleteLesson")
    t.eq(state.careers.flight, { done = done, taken = false, count = 0, again = false })
  end

  -- Out and back.
  lesson("AcceptLesson")
  order("Undock")
  Core.Step(game)
  order("WarpTo", nearest("planet"))
  till("WarpEnded", 600)
  t.eq(state.careers.flight.count, 1)
  homeAndReport(1)
  -- A place of your own.
  lesson("AcceptLesson")
  order("Undock")
  Core.Step(game)
  order("Bookmark")
  Core.Step(game)
  t.eq(state.careers.flight.count, 1)
  homeAndReport(2)
  t.eq(hangar(state, home, "nanofiber"), 1)
  -- Next door: one jump is half of it, and the jump back the rest.
  lesson("AcceptLesson")
  order("Undock")
  Core.Step(game)
  order("Jump", nearest("gate"))
  local out = till("Jumped", 4000)
  t.eq(state.careers.flight.count, 1)
  order("Jump", out.arrival)
  local back = till("Jumped", 4000)
  t.eq({ back.to, state.careers.flight.count }, { 1, 2 })
  homeAndReport(3)
  t.eq(hangar(state, home, "overdrive"), 1)
  -- Another harbour: docking here again is not it. The next station is
  -- (in this system if it has another, else through the gate).
  lesson("AcceptLesson")
  order("Undock")
  Core.Step(game)
  order("Dock", home)
  till("Docked", 2000)
  t.eq(state.careers.flight.count, 0)
  order("Undock")
  Core.Step(game)
  local other = nearest("station", home)
  if other == 0 then
    order("Jump", nearest("gate"))
    out = till("Jumped", 4000)
    other = nearest("station")
  end
  t.ok(other ~= 0 and other ~= home, "there is nowhere else to dock")
  order("Dock", other)
  till("Docked", 6000)
  t.eq(state.careers.flight.count, 1)
  -- (which is not where it is reported)
  local can, why = Core.Validate(game, { kind = "CompleteLesson", actor = mine, what = "flight" })
  t.ok(not can and string.find(why or "", "the career agents are at ", 1, true) == 1, why)
  order("Undock")
  Core.Step(game)
  if Core.Query.Player(game).system ~= 1 then
    order("Jump", out.arrival)
    till("Jumped", 4000)
  end
  Core.TakeEvents(game)
  order("Dock", home)
  till("Docked", 6000)
  lesson("CompleteLesson")
  t.eq(state.careers.flight, { done = 4, taken = false, count = 0, again = false })
  local done = said(game, "LessonDone")
  t.eq({ #done, done[1].finished, done[1].name } :: { any }, { 1, true, "Flight school" } :: { any })
  t.eq(hangar(state, home, "book.evasive.maneuvering"), 1)
  t.near(Standings.Of(state, state.galaxy.systems[1].nearest), 4 * Careers.STANDING, 1e-9)
end)

suite:Case("only what is done with a lesson in hand counts, by the pilot's own ship, and no more than is wanted", function(t)
  local game, state, mine, home = new()
  local function after(event: Careers.Event): { Careers.Event }
    local events = { event }
    Careers.Step(state, events, 1)
    return events
  end
  -- Mining with no lesson taken is nobody's lesson.
  t.eq(#after({ kind = "Mined", ball = mine, units = 300 }), 1)
  t.eq(state.careers.industry, nil)
  -- Taking it hands over a mining laser, beside the pilot's own.
  local lasers = hangar(state, home, "miner.small")
  t.ok((Core.Submit(game, { kind = "AcceptLesson", actor = mine, what = "industry" })))
  Core.Step(game)
  t.eq(hangar(state, home, "miner.small"), lasers + 1)
  t.eq(#after({ kind = "Mined", ball = mine + 1, units = 300 }), 1)
  t.eq(state.careers.industry.count, 0)
  t.eq(#after({ kind = "Mined", ball = mine, units = 250 }), 1)
  t.eq(state.careers.industry.count, 250)
  t.eq({ row(game, "industry").have, row(game, "industry").need } :: { any }, { 250, 400 } :: { any })
  t.eq({ Core.Validate(game, { kind = "CompleteLesson", actor = mine, what = "industry" }) } :: { any }, { false, "250 of 400 so far" } :: { any })
  -- The load that makes it up says so, once; and more is no more.
  local events = after({ kind = "Mined", ball = mine, units = 250 })
  t.eq({ #events, events[2].kind, events[2].career, state.careers.industry.count } :: { any }, { 2, "LessonReady", "industry", 400 } :: { any })
  t.eq(#after({ kind = "Mined", ball = mine, units = 250 }), 1)
  t.eq(state.careers.industry.count, 400)

  -- Some lessons want more of the event than its kind. A station docked
  -- at has to be another; a sale has to be made somewhere else.
  state.careers.flight = { done = 3, taken = true, count = 0, again = false }
  after({ kind = "Docked", ship = mine, station = home })
  t.eq(state.careers.flight.count, 0)
  after({ kind = "Docked", ship = mine + 1, station = home + 1 })
  t.eq(state.careers.flight.count, 0)
  after({ kind = "Docked", ship = mine, station = home + 1 })
  t.eq(state.careers.flight.count, 1)
  state.careers.trade = { done = 3, taken = true, count = 0, again = false }
  after({ kind = "Sold", type = "ore.ferrite", quantity = 5, revenue = 20 })
  t.eq(state.careers.trade.count, 0)
  state.ships[mine].docked = home + 1
  after({ kind = "Sold", type = "ore.ferrite", quantity = 5, revenue = 20 })
  t.eq(state.careers.trade.count, 1)
  state.ships[mine].docked = home
  -- Money that is no bounty is no pirate destroyed; a scan that finds nothing has found nothing.
  state.careers.combat = { done = 4, taken = true, count = 0, again = false }
  after({ kind = "WalletChanged", reason = "mission reward", amount = 5 })
  after({ kind = "WalletChanged", reason = "bounty", amount = 5 })
  after({ kind = "WalletChanged", reason = "bounty", amount = 5 })
  t.eq(state.careers.combat.count, 2)
  t.eq({ Core.Validate(game, { kind = "CompleteLesson", actor = mine, what = "combat" }) } :: { any }, { false, "2 of 5 so far" } :: { any })
  state.careers.survey = { done = 1, taken = true, count = 0, again = false }
  after({ kind = "Scanned", ball = mine, found = 0, signals = 1 })
  t.eq(state.careers.survey.count, 0)
  after({ kind = "Scanned", ball = mine, found = 1, signals = 0 })
  t.eq(state.careers.survey.count, 1)
end)

suite:Case("what is to be brought is handed over, a skill had is enough, and a career ends with something worth having", function(t)
  local game, state, mine, home = new()
  -- The fourth lesson of industry: a thousand Ferrite.
  state.careers.industry = { done = 3, taken = true, count = 0, again = false }
  t.eq({ Core.Validate(game, { kind = "CompleteLesson", actor = mine, what = "industry" }) } :: { any },
    { false, "1000 more Ferrite to bring" } :: { any })
  Items.Add(state, "ore.ferrite", 700, home, "hangar")
  Items.Add(state, "ore.ferrite", 500, mine, "cargo")
  t.eq({ row(game, "industry").have, row(game, "industry").need, row(game, "industry").can } :: { any }, { 1000, 1000, true } :: { any })
  -- (away from the agents' station, what there is of it is what is in the hold)
  state.ships[mine].docked = home + 1
  t.eq({ Careers.Progress(state, "industry") }, { 500, 1000 })
  state.ships[mine].docked = home
  local wallet = state.wallet
  t.ok((Core.Submit(game, { kind = "CompleteLesson", actor = mine, what = "industry" })))
  Core.Step(game)
  t.eq(state.wallet, wallet + 12000)
  local left = hangar(state, home, "ore.ferrite")
  for _, item in Items.In(state, mine, "cargo") do
    left += if item.type == "ore.ferrite" then item.quantity else 0
  end
  t.eq(left, 200)
  -- The fifth: Mining at level 2, which the pilot has not; and then has.
  t.ok((Core.Submit(game, { kind = "AcceptLesson", actor = mine, what = "industry" })))
  Core.Step(game)
  t.eq(state.careers.industry, { done = 4, taken = true, count = 0, again = false })
  t.eq(state.skills.mining, 1)
  t.ok(not row(game, "industry").can)
  Core.TakeEvents(game)
  state.skills.mining = 2
  Core.Step(game)
  t.eq(#said(game, "LessonReady"), 1)
  local lasers = hangar(state, home, "miner.small")
  t.ok((Core.Submit(game, { kind = "CompleteLesson", actor = mine, what = "industry" })))
  Core.Step(game)
  t.eq(hangar(state, home, "miner.small"), lasers + 1)
  local done = said(game, "LessonDone")
  t.eq({ done[1].finished, done[1].name, done[1].gifts } :: { any }, { true, "Industry", 1 } :: { any })
  -- That was the last of them.
  local last = row(game, "industry")
  t.eq({ last.done, last.lesson, last.can } :: { any }, { 5, nil, false } :: { any })
  local can, why = Core.Validate(game, { kind = "AcceptLesson", actor = mine, what = "industry" })
  t.ok(not can and string.find(why or "", "has nothing more to teach", 1, true) ~= nil, why)

  -- The fighter's last gives a combat frigate of the faction whose station it is.
  state.careers.combat = { done = 4, taken = true, count = 5, again = false }
  local frigate = Careers.Frigate(state)
  t.eq({ Ships.byId[frigate].class, Ships.byId[frigate].lineage } :: { any }, { "frigate", state.galaxy.systems[1].nearest } :: { any })
  t.eq(row(game, "combat").gifts, { { type = frigate, quantity = 1 } })
  t.ok((Core.Submit(game, { kind = "CompleteLesson", actor = mine, what = "combat" })))
  Core.Step(game)
  t.eq(hangar(state, home, frigate), 1)
end)

suite:Case("a surveying lesson has something to find for as long as it is in hand", function(t)
  local game, state, mine, home = new()
  local function sites(kind: string, hidden: boolean?): { State.Site }
    local found: { State.Site } = {}
    for _, site in Sites.In(state, 1) do
      if site.kind == kind and (not hidden or site.strength < 1) then
        table.insert(found, site)
      end
    end
    return found
  end
  -- A belt no chart has, for the lesson that is to find one.
  state.careers.survey = { done = 1, taken = false, count = 0, again = false }
  t.ok((Core.Submit(game, { kind = "AcceptLesson", actor = mine, what = "survey" })))
  Core.Step(game)
  local belts = sites("ore", true)
  t.ok(#belts >= 1, "there is no hidden belt to find")
  -- (with one there, there is no call for another)
  for _ = 1, 2 * Careers.CHECK do
    Core.Step(game)
  end
  t.eq(#sites("ore", true), #belts)
  -- Gone, or found by the way, and there is another by the next look.
  for _, site in belts do
    site.gone = true
  end
  for _ = 1, Careers.CHECK do
    Core.Step(game)
  end
  t.ok(#sites("ore", true) >= 1, "the belt went, and no other came")

  -- A derelict with a sealed hold, for the lesson that is to open one;
  -- and what it takes, handed over.
  state.careers.survey = { done = 3, taken = false, count = 0, again = false }
  t.ok((Core.Submit(game, { kind = "AcceptLesson", actor = mine, what = "survey" })))
  Core.Step(game)
  t.eq({ hangar(state, home, "analyzer.data"), hangar(state, home, "probe.scan") }, { 1, 2 })
  local sealed = 0
  for _, site in sites("relic") do
    for _, id in state.wreckIds do
      local wreck = state.wrecks[id]
      sealed += if wreck.grid == site.id and wreck.locked then 1 else 0
    end
  end
  t.ok(sealed >= 1, "there is no sealed hold to open")
end)

suite:Case("how far a pilot has got is in the save, and an older save has begun with nobody", function(t)
  local game, state, mine = new()
  t.ok((Core.Submit(game, { kind = "AcceptLesson", actor = mine, what = "trade" })))
  Core.Step(game)
  state.careers.flight = { done = 2, taken = false, count = 0, again = false }
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.eq(loaded.state.careers, { trade = { done = 0, taken = true, count = 0, again = false }, flight = { done = 2, taken = false, count = 0, again = false } })
  local file = Codec.Decode(data, length)
  file.saveVersion = 43
  file.state.careers = nil
  local old, oldLength = Codec.Encode(file)
  local older = Core.Load(old, oldLength)
  t.eq(older.state.careers, {})
  t.ok(not Core.Query.Careers(older).begun)
end)

suite:Case("a lesson's kit that is lost is handed over again, once, and only what is really gone", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local station = Careers.Station(state)
  local function refused(kind: string, career: string): string?
    local ok, why = Core.Validate(game, { kind = kind, actor = state.player.ship, what = career })
    return if ok then "(accepted)" else why
  end
  local function have(type: string): number
    local units = 0
    for _, item in Items.In(state, station, "hangar") do
      units += if item.type == type then item.quantity else 0
    end
    return units
  end
  local agent = Careers.Agent(state, "survey")
  -- A lesson that hands over a probe launcher and eight probes: the third of the surveyor's.
  t.eq(refused("ReplaceKit", "survey"), "no lesson of theirs is in hand")
  state.careers.survey = { done = 2, taken = false, count = 0, again = false }
  local lesson = assert(Careers.Lesson(state, "survey"))
  t.eq({ lesson.kit[1].type, lesson.kit[1].quantity, lesson.kit[2].type, lesson.kit[2].quantity } :: { any },
    { "scanner.probe", 1, "probe.scan", 8 } :: { any })
  local before = have("probe.scan")
  t.ok(Core.Submit(game, { kind = "AcceptLesson", actor = state.player.ship, what = "survey" }))
  Core.Step(game)
  t.eq(have("probe.scan"), before + 8)
  -- With the kit still there, there is nothing to hand over.
  t.eq(refused("ReplaceKit", "survey"), "you still have what was handed over")
  t.eq(Careers.Lost(state, "survey"), {})
  -- All but one of the eight are gone (and whatever the pilot had besides): those are handed over, and no more.
  for _, item in Items.In(state, station, "hangar") do
    if item.type == "probe.scan" then
      Items.Take(state, item, item.quantity - 1)
    end
  end
  t.eq(Careers.Lost(state, "survey"), { { type = "probe.scan", quantity = 7 } })
  local row: Core.CareerRow? = nil
  for _, each in Core.Query.Careers(game).rows do
    if each.career.id == "survey" then
      row = each
    end
  end
  t.eq(assert(row).again, true)
  t.ok(Core.Submit(game, { kind = "ReplaceKit", actor = state.player.ship, what = "survey" }))
  Core.Step(game)
  t.eq(have("probe.scan"), 8)
  local said = false
  for _, event in Core.TakeEvents(game) do
    said = said or (event.kind == "KitReplaced" and event.agent == agent and event.stacks == 1)
  end
  t.ok(said, "the handing over again should be said")
  -- Lost again: there is no third time.
  for _, item in Items.In(state, station, "hangar") do
    if item.type == "probe.scan" then
      Items.Take(state, item, item.quantity)
    end
  end
  t.eq(refused("ReplaceKit", "survey"), `{agent} has handed it over twice already`)
  -- A lesson that handed nothing over has nothing to ask for, and the next lesson starts afresh.
  state.careers.flight = { done = 0, taken = true, count = 0, again = false }
  t.eq(refused("ReplaceKit", "flight"), "that lesson handed nothing over")
  t.eq(state.careers.survey.again, true)
  state.careers.survey.taken = false
  t.ok(Core.Submit(game, { kind = "AcceptLesson", actor = state.player.ship, what = "survey" }))
  Core.Step(game)
  t.eq(state.careers.survey.again, false)
  -- A save from before has asked for nothing.
  local file = Codec.Decode(Core.Save(game))
  file.saveVersion = 55
  file.state.careers.survey.again = nil
  local old, oldLength = Codec.Encode(file)
  t.eq(Core.Load(old, oldLength).state.careers.survey.again, false)
end)

return suite
