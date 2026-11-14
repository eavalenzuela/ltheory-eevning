--!strict
-- The factions at war (Strategic/Wars).

local Codec = require("@lt/Core/Persist/Codec")
local Commerce = require("@lt/Core/Strategic/Commerce")
local Core = require("@lt/Core/Api")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Test = require("@lt/Tool/Test")
local Wars = require("@lt/Core/Strategic/Wars")

local suite = Test.Suite("Wars")

local SYSTEMS = 400

-- A galaxy and its wars after so many days with nobody flying in it,
-- with everything that was said on the way, by kind.
local function history(seed: number, days: number): (Galaxy.Galaxy, any, { [string]: { any } }, Galaxy.Galaxy)
  local galaxy, plain = Galaxy.Describe(seed, SYSTEMS), Galaxy.Describe(seed, SYSTEMS)
  Galaxy.Deepen(galaxy)
  local wars = Wars.New(galaxy)
  local said: { [string]: { any } } = {}
  for tick = 1, days * Wars.DAY do
    local events: { any } = {}
    Wars.Step(galaxy, wars, seed, tick, events)
    for _, event in events do
      said[event.kind] = said[event.kind] or {}
      table.insert(said[event.kind], event)
    end
  end
  return galaxy, wars, said, plain
end

suite:Case("a game begins with nobody at war and nothing claimed, and every two factions as their kinds make them", function(t)
  local galaxy = Galaxy.Describe(1, SYSTEMS)
  local wars = Wars.New(galaxy)
  local holders = Galaxy.Holders(galaxy)
  t.eq(#holders, 8)
  t.eq({ #wars.feuds, #wars.operations, next(wars.claims), next(wars.truces) } :: { any }, { 0, 0, nil, nil } :: { any })
  t.eq(Wars.Between(wars, "vessari", "talmar"), 10)
  t.eq(Wars.Between(wars, "talmar", "vessari"), 10)
  t.ok(Wars.Between(wars, "vessari", "vail") < 0 and Wars.Between(wars, "vessari", "unbound") < Wars.Between(wars, "vessari", "vail"))
  t.ok(Wars.Between(wars, "vessari", "unbound") > Wars.WAR_BELOW, "nobody begins at war")
  t.eq(Wars.AtWar(wars, "vessari", "unbound"), false)
  t.eq(next(Wars.Blocked(wars)), nil)
end)

suite:Case("only open space changes hands: homes are as they were made, claims are made next to what is held, and wars move them", function(t)
  local galaxy, wars, said, plain = history(1, 20)
  local holders = Galaxy.Holders(galaxy)
  -- Every home is whose it was, as safe as it was; no homeworld was ever anybody's target.
  local claims = 0
  for id = 1, SYSTEMS do
    local now, was = galaxy.systems[id], plain.systems[id]
    if was.owner ~= "" then
      t.eq({ now.owner, now.security, now.home } :: { any }, { was.owner, was.security, was.home } :: { any }, `system {id}`)
      t.eq(wars.claims[id], nil)
    else
      -- (open space: nobody's, or a claim: on the map as its holder's, and as lawless as it was)
      t.eq(now.owner, wars.claims[id] or "")
      t.eq(now.security, 0)
      claims += if now.owner ~= "" then 1 else 0
    end
  end
  t.ok(claims >= 60, `{claims} open systems are claimed after twenty days`)
  for _, faction in holders do
    local has = 0
    for _, owner in wars.claims do
      has += if owner == faction then 1 else 0
    end
    t.ok(has <= Wars.CLAIMS, `{faction} has {has} claims`)
    t.ok((wars.strength[faction] or 0) >= 0 and (wars.strength[faction] or 0) <= Wars.MOST)
  end
  -- Every operation was against open space: a claim of what nobody held, or a siege of somebody's claim.
  for _, event in said.OperationBegan do
    t.eq(plain.systems[event.system].owner, "", "an operation against somebody's home")
    t.ok(not plain.systems[event.system].home)
    t.eq(event.what, if event.against ~= "" then "siege" else "claim")
    t.ok(event.against ~= event.by)
  end
  -- Wars were declared and ended, sieges won and broken, and claims taken from their holders.
  t.ok(#said.WarDeclared >= 3 and #said.PeaceMade >= 1, `{#said.WarDeclared} wars and {#said.PeaceMade} truces in twenty days`)
  local won, taken = 0, 0
  for _, event in said.SystemTaken do
    taken += 1
    won += if event.from ~= "" then 1 else 0
  end
  local broken = 0
  local over: { any } = said.OperationOver or {}
  for _, event in over do
    broken += if event.how == "broken" then 1 else 0
  end
  t.ok(won >= 5 and broken >= 2, `{won} claims were taken by siege and {broken} sieges were broken`)
  for _, event in said.PeaceMade do
    t.ok(event.hours >= 24, "a war was over in less than a day")
  end
  -- (a war is between two who share a border, and is declared by one of them once a day at most)
  local last: { [string]: number } = {}
  for _, event in said.WarDeclared do
    t.ok(event.by ~= event.on and table.find(holders, event.by) ~= nil and table.find(holders, event.on) ~= nil)
    last[event.by] = (last[event.by] or 0) + 1
  end
  print(`     wars: {#said.WarDeclared} declared and {#said.PeaceMade} ended in twenty days; {taken - won} claims made, {won} taken by siege, {broken} sieges broken`)
  -- The same galaxy and seed, the same history: and another seed, another.
  local _, again = history(1, 3)
  local _, same = history(1, 3)
  local _, other = history(2, 3)
  t.eq(Codec.HashOf(again), Codec.HashOf(same))
  t.ok(Codec.HashOf(again) ~= Codec.HashOf(other))
end)

suite:Case("a blockaded system's lanes are all but shut, and open again when the blockade is over", function(t)
  local galaxy = Galaxy.Describe(1, 40)
  Galaxy.Deepen(galaxy)
  local econ = Commerce.New(galaxy)
  local edge = econ.edges[1]
  local before = edge.cost
  Commerce.Lanes(econ, galaxy, 0, { [edge.a] = true })
  t.near(edge.cost, before + Commerce.BLOCKADE_COST, 1e-9)
  t.ok(edge.loss >= Commerce.BLOCKADE_LOSS)
  Commerce.Lanes(econ, galaxy, 0, {})
  t.near(edge.cost, before, 1e-9)
  -- (an operation blockades from the end of its muster)
  local wars = Wars.New(galaxy)
  table.insert(wars.operations, { id = 1, by = "vessari", system = 7, kind = "claim", began = 0, force = 40, sent = 40, against = "",
    defence = 0, defended = 0, stage = "muster", relieved = false })
  t.eq(Wars.Blocked(wars)[7], nil)
  wars.operations[1].stage = "blockade"
  t.eq(Wars.Blocked(wars)[7], true)
end)

suite:Case("the wars are in the save, a game steps them, and a save from before begins at peace", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, systems = 40, peaceful = true, wars = true })
  local state = game.state
  local began = false
  for _ = 1, 3 * Wars.HOUR do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      began = began or event.kind == "OperationBegan"
    end
  end
  t.ok(began, "nobody claimed anything in three hours")
  t.ok(state.wars.version >= 1, "no system has changed hands")
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  for _ = 1, Wars.HOUR do
    Core.Step(game)
    Core.Step(loaded)
  end
  t.eq(Core.Hash(loaded), Core.Hash(game))
  -- (a test's galaxy is one where nobody stirs, unless it asks)
  local still = Core.New({ galaxySeed = 1, historySeed = 1, systems = 40, peaceful = true })
  for _ = 1, 2 * Wars.HOUR do
    Core.Step(still)
  end
  t.eq({ still.state.wars.on, still.state.wars.version, #still.state.wars.operations } :: { any }, { false, 0, 0 } :: { any })
  local fresh = Core.New({ galaxySeed = 1, historySeed = 1, systems = 40, peaceful = true, wars = true })
  local saved, savedLength = Core.Save(fresh)
  local file = Codec.Decode(saved, savedLength)
  file.saveVersion = 75
  file.state.wars = nil
  local old, oldLength = Codec.Encode(file)
  t.eq(Core.Hash(Core.Load(old, oldLength)), Core.Hash(fresh))
end)

return suite
