--!strict
-- An open system as the pilot's own (Assets/Sovereignty).

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
  t.eq({ node.owner, node.security, state.wars.claims[system] } :: { any }, { "player", Wars.ORDER, "player" } :: { any })
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

return suite
