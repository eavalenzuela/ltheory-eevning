--!strict
-- An open system as the pilot's own (Assets/Sovereignty).

local Galaxy = require("@lt/Core/Describe/Galaxy")
local Members = require("@lt/Core/Assets/Members")
local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Core = require("@lt/Core/Api")
local Sovereignty = require("@lt/Core/Assets/Sovereignty")
local Space = require("@lt/Core/Tactical/Space")
local Standings = require("@lt/Core/Assets/Standings")
local Starbases = require("@lt/Core/Assets/Starbases")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local Test = require("@lt/Tool/Test")
local Wars = require("@lt/Core/Strategic/Wars")

local suite = Test.Suite("Sovereignty")

local function hours(game: Core.Game, count: number): { [string]: { any } }
  local said: { [string]: { any } } = {}
  for _ = 1, count * Sovereignty.HOUR do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      said[event.kind] = said[event.kind] or {}
      table.insert(said[event.kind], event)
    end
  end
  return said
end

-- A game, an open system next to space a faction holds that has a moon,
-- that faction, and a lit tower of the pilot's there with a claim
-- beacon online.
local function claiming(wars: boolean): (Core.Game, number, string, State.Starbase)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, systems = 40, peaceful = true, wars = wars })
  local state = game.state
  for id = 2, 40 do
    local node = state.galaxy.systems[id]
    local beside = ""
    for _, neighbor in node.neighbors do
      local owner = state.galaxy.systems[neighbor].owner
      beside = if owner ~= "" and beside == "" then owner else beside
    end
    if node.owner == "" and beside ~= "" then
      for _, object in Space.Describe(state, id).objects do
        if object.kind == "moon" then
          local base = Starbases.Raise(state, id, object, Structures.towerById["tower.vessari.small"], "player",
            object.x + object.radius * 3, object.y, object.z)
          local starbase = state.starbases[base]
          starbase.ready, starbase.fuel, starbase.burnt = state.tick, 1000000, state.tick
          table.insert(starbase.modules, { type = Structures.CLAIM, ready = state.tick })
          return game, id, beside, starbase
        end
      end
    end
  end
  error("no open system next to anybody's space has a moon")
end

suite:Case("a claim beacon at a lit tower makes an open system the pilot's: named for them, with order kept, while it stands", function(t)
  local game, system, _, starbase = claiming(false)
  local state = game.state
  local node = state.galaxy.systems[system]
  t.ok(Starbases.Has(state, starbase, "claim"), "the beacon is not online")
  t.eq({ node.owner, node.security } :: { any }, { "", 0 } :: { any })
  t.eq({ Core.Query.Claim(game, system) } :: { any }, { "claiming", 0, Sovereignty.CLAIM } :: { any })
  t.eq({ Core.Query.Claim(game, 1) } :: { any }, { "none", 0, Sovereignty.CLAIM } :: { any })
  -- (not in a few hours)
  hours(game, Sovereignty.CLAIM - 1)
  t.eq({ node.owner, (select(2, Core.Query.Claim(game, system))) } :: { any }, { "", Sovereignty.CLAIM - 1 } :: { any })
  local said = hours(game, 1)
  t.eq({ node.owner, Galaxy.Order(node), state.wars.claims[system] } :: { any }, { "player", Wars.ORDER, "player" } :: { any })
  t.eq({ said.SystemTaken[1].system, said.SystemTaken[1].by, said.SystemTaken[1].from } :: { any }, { system, "player", "" } :: { any })
  t.eq((Core.Query.Claim(game, system)), "held")
  -- It is theirs to name.
  local name = node.name
  local function refused(what: string, target: number): string?
    local ok, why = Core.Validate(game, { kind = "RenameSystem", actor = state.player.ship, target = target, what = what })
    return if ok then "(accepted)" else why
  end
  t.eq(refused("Haven", 1), "that system is not yours to name")
  t.eq(refused("", system), "a place has a name")
  t.eq(refused(state.galaxy.systems[1].name, system), "another system has that name")
  t.eq(refused("New Haven", system), "(accepted)")
  assert(Core.Submit(game, { kind = "RenameSystem", actor = state.player.ship, target = system, what = "  New   Haven " }))
  Core.Step(game)
  t.eq({ node.name, state.systems[system].name, name ~= "New Haven" } :: { any }, { "New Haven", "New Haven", true } :: { any })
  -- With the tower dark it is kept half a day, and then let go: and is as lawless as it was.
  starbase.fuel = 0
  hours(game, Sovereignty.LAPSE - 2)
  t.eq(node.owner, "player")
  starbase.fuel = 1000000
  starbase.burnt = state.tick
  hours(game, 2)
  t.eq({ node.owner, state.sovereignty.dark[system] } :: { any }, { "player", nil } :: { any })
  starbase.fuel = 0
  said = hours(game, Sovereignty.LAPSE + 1)
  t.eq({ node.owner, node.security, state.wars.claims[system] } :: { any }, { "", 0, nil } :: { any })
  t.eq({ said.ClaimLapsed[1].system, said.ClaimLapsed[1].by } :: { any }, { system, "player" } :: { any })
  local data, length = Core.Save(game)
  t.eq(Core.Hash(Core.Load(data, length)), Core.Hash(game))
end)

suite:Case("a neighbour that thinks badly of the pilot declares on them and besieges their system, and stops when it thinks better", function(t)
  local game, system, neighbour, _ = claiming(true)
  local state = game.state
  -- (the factions are claiming open space all round meanwhile, and none of them begins on the one the pilot's beacon stands in)
  local early = hours(game, Sovereignty.CLAIM)
  t.eq(state.galaxy.systems[system].owner, "player")
  t.ok(#early.OperationBegan >= 1, "nobody claimed anything in six hours")
  for _, event in early.OperationBegan do
    t.ok(event.system ~= system, "a faction began a claim of a system the pilot had spoken for")
  end
  state.standings[neighbour] = 2
  -- While the neighbour thinks well enough of the pilot, nothing.
  local said = hours(game, 3)
  local quiet: { any } = said.WarDeclared or {}
  for _, event in quiet do
    t.ok(event.on ~= "player", "war on a pilot nobody thinks badly of")
  end
  for _, operation in state.wars.operations do
    t.ok(operation.system ~= system, "a siege of the pilot's system with nobody at war with them")
  end
  -- It comes to think badly of them: war, and a siege of what they hold next to it.
  -- (with the least a siege is sent with: the tower and its guns are a match for it)
  state.standings[neighbour] = Standings.HOSTILE - 1
  state.wars.strength[neighbour] = Wars.SIEGE_FORCE
  said = hours(game, 2)
  local declared: any = nil
  for _, event in said.WarDeclared do
    declared = if event.on == "player" then event else declared
  end
  t.eq({ declared.by, declared.on }, { neighbour, "player" })
  t.ok(Wars.AtWar(state.wars, neighbour, "player"))
  local siege: any = nil
  local begun: { any } = said.OperationBegan or {}
  for _, event in begun do
    siege = if event.system == system then event else siege
  end
  t.ok(siege ~= nil, "nobody besieged the pilot's system")
  t.eq({ siege.by, siege.against, siege.what }, { neighbour, "player", "siege" })
  local wars = Core.Query.Wars(game)
  t.eq({ wars[1].a ~= "", wars[1].b } :: { any }, { true, "you" } :: { any })
  -- It thinks better of them: a truce, and the siege is called off.
  state.standings[neighbour] = 2
  said = hours(game, 2)
  local made: any = nil
  for _, event in said.PeaceMade do
    made = if event.b == "player" then event else made
  end
  t.eq({ made.a, made.b }, { neighbour, "player" })
  t.eq(Wars.AtWar(state.wars, neighbour, "player"), false)
  for _, operation in state.wars.operations do
    t.ok(operation.system ~= system, "the siege went on after the truce")
  end
  t.eq(state.galaxy.systems[system].owner, "player")
  -- (and for two days it does not begin again, whatever it thinks)
  state.standings[neighbour] = Standings.HOSTILE - 1
  said = hours(game, 4)
  local again: { any } = said.WarDeclared or {}
  for _, event in again do
    t.ok(event.on ~= "player", "war on the pilot again within the truce")
  end
end)

suite:Case("the corporation declares its own wars, takes a faction's claim by besieging it in person, and makes its own peace", function(t)
  local game, system, neighbour, starbase = claiming(true)
  local state = game.state
  local me = state.player.ship
  local function refused(kind: string, what: string): string?
    local ok, why = Core.Validate(game, { kind = kind, actor = me, what = what })
    return if ok then "(accepted)" else why
  end
  -- (the system is the neighbour's claim, with the pilot's beacon standing in it: it claims nothing)
  state.galaxy.systems[system].owner = neighbour
  state.wars.claims[system] = neighbour
  t.eq((Core.Query.Claim(game, system)), "contested")
  -- A war is a corporation's to declare, on somebody who holds space, once.
  t.eq(refused("DeclareWar", neighbour), "a war is a corporation's to declare: found one first")
  state.wallet = 50000000
  assert(Core.Submit(game, { kind = "FoundCorporation", actor = me, what = "Haven Holdings" }))
  Core.Step(game)
  t.eq(refused("DeclareWar", "nobody"), "nobody of that name holds space")
  t.eq(refused("ProposePeace", neighbour), "you are not at war with them")
  t.eq(refused("DeclareWar", neighbour), "(accepted)")
  assert(Core.Submit(game, { kind = "DeclareWar", actor = me, what = neighbour }))
  Core.Step(game)
  t.ok(Wars.AtWar(state.wars, "player", neighbour))
  t.ok(Standings.Hostile(state, neighbour), "a faction the corporation is at war with should be the pilot's enemy")
  t.eq(refused("DeclareWar", neighbour), "you are at war with them already")
  t.eq(string.sub(refused("ProposePeace", neighbour) or "", 1, 31), "they will not hear of it yet: 2")
  -- The beacon in their claim is a siege of the pilot's own, within a round: and nothing is reckoned for it unseen.
  local began: any = nil
  for _ = 1, 2 * Wars.ROUND do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      began = if event.kind == "OperationBegan" and event.by == "player" then event else began
    end
  end
  t.eq({ began.system, began.against, began.what } :: { any }, { system, neighbour, "siege" } :: { any })
  local operation: State.Operation? = nil
  for _, other in state.wars.operations do
    operation = if other.system == system then other else operation
  end
  local siege = assert(operation)
  t.eq({ siege.by, siege.defence, siege.force } :: { any }, { "player", Wars.GARRISON, Sovereignty.PERSONAL } :: { any })
  state.wars.strength[neighbour] = 0
  hours(game, 2)
  t.eq(state.galaxy.systems[system].owner, neighbour)
  t.ok(siege.defence >= Wars.GARRISON and siege.force == Sovereignty.PERSONAL, "the siege was fought with nobody there")
  -- The pilot comes to the lines: the garrison is there as ships, and nobody of the pilot's is put there for them.
  assert(Core.Submit(game, { kind = "Undock", actor = me }))
  Core.Step(game)
  local ball = state.balls[me]
  ball.system = system
  ball.x, ball.y, ball.z = 4e9, 0, 0
  Space.AssignGrid(state, ball)
  Core.Step(game)
  local front = assert(state.fronts[siege.id], "the pilot's siege has no lines")
  local place = assert(Space.Object(state, front.site))
  ball.x, ball.y, ball.z = place.x, place.y + 30000, place.z
  Space.AssignGrid(state, ball)
  Core.Step(game)
  local garrison = 0
  for id, record in front.ships do
    t.eq({ record.side, record.attacking } :: { any }, { neighbour, false } :: { any })
    garrison += 1
  end
  t.ok(garrison >= 2, `{garrison} ships of the garrison are at the lines`)
  -- They are destroyed: the defence gives way, and the system is the pilot's.
  for id in front.ships do
    Aftermath.Destroy(state, id, me, game.events)
  end
  local taken: any = nil
  for _ = 1, 2 * Wars.STAGE do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      taken = if event.kind == "SystemTaken" and event.system == system then event else taken
    end
    if taken then
      break
    end
  end
  t.eq({ taken.by, taken.from }, { "player", neighbour })
  t.eq({ state.galaxy.systems[system].owner, Galaxy.Order(state.galaxy.systems[system]) } :: { any }, { "player", Wars.ORDER } :: { any })
  t.eq((Wars.Feud(state.wars, "player", neighbour) :: State.Feud).score, 1)
  -- Peace is heard once the war is a day old: a truce, and they are the pilot's enemies no longer.
  state.tick += Wars.LEAST
  t.eq(refused("ProposePeace", neighbour), "(accepted)")
  assert(Core.Submit(game, { kind = "ProposePeace", actor = me, what = neighbour }))
  Core.Step(game)
  t.eq({ Wars.AtWar(state.wars, "player", neighbour), Wars.Truce(state.wars, "player", neighbour), Standings.Hostile(state, neighbour) } :: { any },
    { false, true, false } :: { any })
  t.eq(refused("DeclareWar", neighbour), "there is a truce between you")
  t.ok(starbase.fuel > 0)
  -- A war the pilot began leaves them thought no better of than before it
  -- (the owner, 2026-11-22): one begun at -4.5 ends at -4.5, not -4.
  state.wars.truces = {}
  state.standings[neighbour] = -4.5
  assert(Core.Submit(game, { kind = "DeclareWar", actor = me, what = neighbour }))
  Core.Step(game)
  state.tick += Wars.LEAST
  assert(Core.Submit(game, { kind = "ProposePeace", actor = me, what = neighbour }))
  Core.Step(game)
  t.eq(Standings.Of(state, neighbour), -4.5)
  -- Set upon and the better of it, the pilot comes out of it better thought of.
  state.wars.truces = {}
  state.standings[neighbour] = -6
  table.insert(state.wars.feuds, { a = neighbour, b = "player", since = state.tick - Wars.LEAST, score = -4 })
  assert(Core.Submit(game, { kind = "ProposePeace", actor = me, what = neighbour }))
  Core.Step(game)
  t.eq(Standings.Of(state, neighbour), Standings.HOSTILE + 1 + 4 * Sovereignty.IMPRESSED)
end)

suite:Case("a system of the pilot's pays a levy by the day, and those who fly for the pilot there stand with it in a siege", function(t)
  local game, system, neighbour, _ = claiming(true)
  local state = game.state
  hours(game, Sovereignty.CLAIM)
  t.eq(state.galaxy.systems[system].owner, "player")
  -- (to the pilot, with no corporation: so much for the people there, a day)
  local wallet = state.wallet
  local said = hours(game, 24 - Sovereignty.CLAIM)
  local due = math.floor(Sovereignty.LEVY * state.commerce.nodes[system].population * 24)
  t.ok(due > 0, "nobody lives in the system")
  -- (and, since 2026-11-16, what its trade pays: the sales tax on what its
  -- market sold its people, and dues on what went along its lanes, read
  -- once a day and counted afresh after)
  local paid = said.LevyPaid[1]
  t.eq({ paid.amount, paid.systems, state.wallet - wallet } :: { any }, { due, 1, due + paid.tax + paid.dues } :: { any })
  t.ok(paid.tax > 0, "its people bought nothing all day")
  -- (counted afresh: what it has sold since is less than the day's)
  t.ok((state.commerce.nodes[system].sales or 0) < paid.tax / Sovereignty.SALES_TAX, "the day's trade was not set back to nothing")
  -- A hired pilot's ship is in the system when it is besieged: the defence is the tower and them.
  local ship = Space.NewShip(state, "frigate.courier", "Second", "player", state.player.home)
  -- (a member of the pilot's corporation, asked into the fleet: since 2026-11-21 nobody is hired)
  state.wallet = 10000000
  if state.corporation.name == "" then
    state.corporation.name, state.corporation.founded = "Test Crew", state.tick
  end
  state.membership.share = 0
  local crewman = Members.Recruit(state, "Crewman", "fighter", 2, {})
  assert(Core.Submit(game, { kind = "InviteToFleet", actor = state.player.ship, what = `member:{crewman.id}` }))
  Core.Step(game)
  local wing = state.fleet[state.fleetIds[#state.fleetIds]]
  wing.ship, wing.order = ship.id, "stay"
  local place = Space.Describe(state, system).objects[1]
  Space.Launch(state, ship, system, place.x + 5e9, 0, 0)
  state.standings[neighbour] = Standings.HOSTILE - 1
  state.wars.strength[neighbour] = Wars.SIEGE_FORCE
  local relief: any = nil
  for _ = 1, 3 * Sovereignty.HOUR do
    -- (kept there, whatever its pilot would rather do: this is about who is in the system when the siege comes)
    local theirs = state.balls[ship.id]
    if theirs then
      theirs.system, theirs.warp, theirs.intent = system, nil, nil
    end
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      relief = if event.kind == "ReliefSent" and event.by == "player" then event else relief
    end
    if relief then
      break
    end
  end
  t.ok(relief ~= nil, "nobody who flies for the pilot stood with their system")
  t.eq({ relief.system, relief.against, relief.force } :: { any }, { system, neighbour, Sovereignty.POSTED } :: { any })
  for _, operation in state.wars.operations do
    if operation.system == system then
      t.eq(operation.defended, Wars.GARRISON * Wars.TOWER + Sovereignty.POSTED)
    end
  end
end)

return suite
