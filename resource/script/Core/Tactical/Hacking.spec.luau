--!strict
-- Hacking (Tactical/Hacking).

local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Hacking = require("@lt/Core/Tactical/Hacking")
local Items = require("@lt/Core/Assets/Items")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Sites = require("@lt/Core/Tactical/Sites")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Hacking")

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

-- A game with a derelict in the first system, the pilot's ship beside
-- one of its hulls, with or without a data analyzer fitted, and the
-- Hacking skill at a level: the game, the hull, and the site.
local function beside(fitted: boolean, level: number): (Core.Game, State.Wreck, State.Site)
  for seed = 1, 60 do
    local game = Core.New({ galaxySeed = 1, historySeed = seed, peaceful = true })
    local state = game.state
    state.skills.hacking = level
    if fitted then
      Items.Equip(state, state.player.ship, Hacking.ANALYZER, nil)
    end
    assert(submit(game, { kind = "Undock", actor = 0 }))
    assert(submit(game, { kind = "Stop", actor = 0 }))
    for _, site in Sites.In(state, 1) do
      if site.kind == "relic" then
        for _, id in state.wreckIds do
          local wreck = state.wrecks[id]
          if wreck.grid == site.id then
            local me = state.balls[state.player.ship]
            me.x, me.y, me.z = wreck.x + 1500, wreck.y, wreck.z
            me.vx, me.vy, me.vz = 0, 0, 0
            Space.AssignGrid(state, me)
            return game, wreck, site
          end
        end
      end
    end
  end
  error("no history seed up to 60 gives the first system a derelict")
end

-- Try the open node nearest the core (the test may look; a pilot goes by
-- the numbers), until the hack is over. Returns the blows it took.
local function play(game: Core.Game): number
  local state = game.state
  local turns = 0
  while state.hack and turns < 200 do
    local hack = state.hack :: State.Hack
    local best, least = 0, math.huge
    for index in hack.nodes do
      if Hacking.Open(hack, index) and Hacking.Steps(hack, index) < least then
        best, least = index, Hacking.Steps(hack, index)
      end
    end
    assert(best ~= 0, "nothing on the board can be tried")
    assert(submit(game, { kind = "HackNode", actor = 0, pin = best }))
    turns += 1
  end
  return turns
end

suite:Case("a derelict's hold is sealed, and is hacked by a ship with a data analyzer from near by", function(t)
  local bare, hull = beside(false, 1)
  t.eq(hull.locked, true)
  t.eq(refused(bare, { kind = "Loot", actor = 0, target = hull.id }), "its hold is sealed: it has to be hacked")
  t.eq(refused(bare, { kind = "StartHack", actor = 0, target = hull.id }), "needs a Data Analyzer fitted")
  t.eq(refused(bare, { kind = "StartHack", actor = 0, target = 12345 }), "not a wreck")
  t.eq(refused(bare, { kind = "HackNode", actor = 0, pin = 1 }), "no hack is under way")
  -- (the analyzer wants its skill to fit)
  local docked = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local item = Items.Add(docked.state, Hacking.ANALYZER, 1, docked.state.player.home, "hangar")
  t.eq(refused(docked, { kind = "Fit", actor = 0, item = item.id }), "needs Hacking 1")

  local game, wreck = beside(true, 1)
  local state = game.state
  local me = state.balls[state.player.ship]
  me.x += 10000
  t.eq(refused(game, { kind = "StartHack", actor = 0, target = wreck.id }), "too far away")
  me.x -= 10000
  t.ok((submit(game, { kind = "StartHack", actor = 0, target = wreck.id })))
  local hack = assert(state.hack)
  t.eq({ hack.wreck, #hack.nodes, hack.coherence, hack.most, hack.strength } :: { any }, { wreck.id, 30, 70, 70, 25 } :: { any })
  t.eq(refused(game, { kind = "StartHack", actor = 0, target = wreck.id }), "a hack is under way already")
  -- The board: the way in cleared, one core in the last column, ten firewalls, two repair nodes.
  local counts: { [string]: number } = {}
  for index, node in hack.nodes do
    counts[node.kind] = (counts[node.kind] or 0) + 1
    t.eq(node.cleared, index == hack.start)
    if node.kind == "core" then
      t.eq(index % Hacking.WIDTH, 0)
    end
  end
  t.eq({ counts.core, counts.firewall, counts.repair, counts.empty } :: { any }, { 1, 10, 2, 17 } :: { any })
  t.eq((hack.start - 1) % Hacking.WIDTH, 0)
  -- What the pilot sees of it: hidden nodes, those next to the way in open.
  local seen = assert(Core.Query.Hack(game))
  local open = 0
  for index, node in seen.nodes do
    open += if node.open then 1 else 0
    t.eq(node.kind, if index == hack.start then "empty" else "hidden")
  end
  t.eq(open, 3)
  t.ok(seen.nodes[hack.start].steps >= 5)
  t.eq(refused(game, { kind = "HackNode", actor = 0, pin = hack.start }), "that node cannot be reached yet")
  t.eq(refused(game, { kind = "HackNode", actor = 0, pin = hack.start + 3 }), "that node cannot be reached yet")
  -- The pirates' stores at a den are not sealed.
  for seed = 1, 20 do
    local other = Core.New({ galaxySeed = 1, historySeed = seed, peaceful = true })
    assert(submit(other, { kind = "Undock", actor = 0 }))
    for _, site in Sites.In(other.state, 1) do
      if site.kind == "combat" then
        for _, id in other.state.wreckIds do
          if other.state.wrecks[id].grid == site.id then
            t.eq(other.state.wrecks[id].locked, false)
          end
        end
      end
    end
  end
end)

suite:Case("a node is found, then fought: a blow takes the pilot's strength off it, and its answer its own off their coherence", function(t)
  local game, wreck = beside(true, 0)
  local state = game.state
  state.skills.hacking = 0
  t.ok((submit(game, { kind = "StartHack", actor = 0, target = wreck.id })))
  local hack = assert(state.hack)
  t.eq({ hack.coherence, hack.strength }, { 60, 20 })
  -- (the node beside the way in is made a firewall, to see one fought)
  local at = hack.start + 1
  local node = hack.nodes[at]
  node.kind, node.hp, node.strength = "firewall", 50, 15
  t.ok((submit(game, { kind = "HackNode", actor = 0, pin = at })))
  t.eq({ node.seen, node.cleared, node.hp, hack.coherence } :: { any }, { true, false, 50, 60 } :: { any })
  t.eq(assert(Core.Query.Hack(game)).nodes[at].kind, "firewall")
  -- The way past it is shut while it stands.
  t.eq(refused(game, { kind = "HackNode", actor = 0, pin = at + 1 }), "that node cannot be reached yet")
  t.ok((submit(game, { kind = "HackNode", actor = 0, pin = at })))
  t.eq({ node.hp, hack.coherence }, { 30, 45 })
  t.ok((submit(game, { kind = "HackNode", actor = 0, pin = at })))
  t.eq({ node.hp, hack.coherence }, { 10, 30 })
  -- The blow that brings it down is not answered, and the way past is open.
  t.ok((submit(game, { kind = "HackNode", actor = 0, pin = at })))
  t.eq({ node.hp, node.cleared, hack.coherence } :: { any }, { 0, true, 30 } :: { any })
  t.eq(refused(game, { kind = "HackNode", actor = 0, pin = at + 1 }), "(accepted)")
  -- A repair node gives coherence back, never above what the pilot began with; nothing clears and says how far the core is.
  local mend = hack.nodes[at + 1]
  mend.kind, mend.hp, mend.strength = "repair", 0, 0
  t.ok((submit(game, { kind = "HackNode", actor = 0, pin = at + 1 })))
  t.eq({ mend.cleared, hack.coherence } :: { any }, { true, 55 } :: { any })
  local plain = hack.nodes[at + 2]
  plain.kind, plain.hp, plain.strength = "empty", 0, 0
  t.ok((submit(game, { kind = "HackNode", actor = 0, pin = at + 2 })))
  t.eq(assert(Core.Query.Hack(game)).nodes[at + 2].steps, Hacking.Steps(hack, at + 2))
  -- Coherence gone: the hold opens, with half of everything in it burnt.
  local before: { [string]: number } = {}
  for _, item in Items.In(state, wreck.id, "cargo") do
    before[item.type] = item.quantity
  end
  local wall = hack.nodes[at + 3]
  wall.kind, wall.hp, wall.strength = "firewall", 500, 100
  t.ok((submit(game, { kind = "HackNode", actor = 0, pin = at + 3 })))
  Core.TakeEvents(game)
  t.ok((submit(game, { kind = "HackNode", actor = 0, pin = at + 3 })))
  t.eq({ state.hack, wreck.locked } :: { any }, { nil, false } :: { any })
  local told = false
  for _, event in Core.TakeEvents(game) do
    told = told or (event.kind == "HackDone" and event.success == false and event.wreck == wreck.id)
  end
  t.ok(told, "nobody said the hack had failed")
  for _, item in Items.In(state, wreck.id, "cargo") do
    t.eq(item.quantity, before[item.type] - math.ceil(before[item.type] / 2), item.type)
  end
end)

suite:Case("with the core destroyed the hold is open, and what is in it can be taken", function(t)
  local game, wreck = beside(true, 5)
  local state = game.state
  local held = 0
  for _, item in Items.In(state, wreck.id, "cargo") do
    held += item.quantity
  end
  t.ok((submit(game, { kind = "StartHack", actor = 0, target = wreck.id })))
  Core.TakeEvents(game)
  local turns = play(game)
  t.ok(turns >= 6, `the hack was over in {turns} turns`)
  local won = false
  for _, event in Core.TakeEvents(game) do
    won = won or (event.kind == "HackDone" and event.success == true)
  end
  t.ok(won, "a pilot with Hacking 5 lost to a derelict's lock")
  t.eq({ state.hack, wreck.locked } :: { any }, { nil, false } :: { any })
  local now = 0
  for _, item in Items.In(state, wreck.id, "cargo") do
    now += item.quantity
  end
  t.eq(now, held, "a hold opened by hacking should have everything in it")
  t.eq(refused(game, { kind = "StartHack", actor = 0, target = wreck.id }), "its hold is not sealed")
  t.eq(refused(game, { kind = "Loot", actor = 0, target = wreck.id }), "(accepted)")
end)

suite:Case("a hack can be given up, is dropped if the ship goes off, and meets the same board next time; and it is in the save", function(t)
  local game, wreck = beside(true, 2)
  local state = game.state
  t.ok((submit(game, { kind = "StartHack", actor = 0, target = wreck.id })))
  local first = Codec.HashOf(assert(state.hack).nodes)
  t.ok((submit(game, { kind = "HackNode", actor = 0, pin = assert(state.hack).start + 1 })))
  -- (in the save, half done)
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.ok(loaded.state.hack ~= nil)
  t.ok((submit(game, { kind = "AbandonHack", actor = 0 })))
  t.eq({ state.hack, wreck.locked } :: { any }, { nil, true } :: { any })
  t.ok((submit(game, { kind = "StartHack", actor = 0, target = wreck.id })))
  t.eq(Codec.HashOf(assert(state.hack).nodes), first)
  -- A little way off, within a kilometre of the analyzer's reach, it holds.
  local me = state.balls[state.player.ship]
  me.x += 4000
  Core.Step(game)
  t.ok(state.hack ~= nil, "the hack was dropped inside its leash")
  -- Off it goes, and the hack is dropped, the hold still sealed.
  me.x += Hacking.LEASH + 1000
  Core.TakeEvents(game)
  Core.Step(game)
  t.eq({ state.hack, wreck.locked } :: { any }, { nil, true } :: { any })
  local why = ""
  for _, event in Core.TakeEvents(game) do
    why = if event.kind == "HackDone" then event.reason :: string else why
  end
  t.eq(why, "out of reach")
  -- A save from before holds were sealed: its hulls are as open as they were.
  local file = Codec.Decode(data, length)
  file.saveVersion = 34
  file.state.hack = nil
  for _, each in file.state.wrecks do
    each.locked = nil
  end
  local old, oldLength = Codec.Encode(file)
  local opened = Core.Load(old, oldLength)
  for _, id in opened.state.wreckIds do
    t.eq(opened.state.wrecks[id].locked, false)
  end
end)

-- A careful pilot, who goes by what the board has shown and nothing
-- else: of the nodes that can be tried, the one not known yet that the
-- numbers say could be nearest the core; a firewall only when going
-- round it would be two steps the worse, or there is no way round; and
-- the core as soon as it is found.
local function careful(hack: State.Hack): number
  local function could(index: number): number
    local least = math.huge
    for _, beside in Hacking.Beside(index) do
      if hack.nodes[beside].cleared then
        least = math.min(least, Hacking.Steps(hack, beside) - 1)
      end
    end
    return least
  end
  local unknown, unknownAt, wall, wallAt = 0, math.huge, 0, math.huge
  for index, node in hack.nodes do
    if Hacking.Open(hack, index) then
      local at = could(index)
      if node.seen and node.kind == "core" then
        return index
      elseif node.seen and at < wallAt then
        wall, wallAt = index, at
      elseif not node.seen and at < unknownAt then
        unknown, unknownAt = index, at
      end
    end
  end
  return if unknown ~= 0 and (wall == 0 or unknownAt <= wallAt + 2) then unknown else wall
end

suite:Case("played carefully, a pilot new to it opens about half the holds whole, and a practised one nearly all", function(t)
  local won: { number } = {}
  for _, level in { 1, 3, 5 } do
    local game = Core.New({ galaxySeed = 1, historySeed = 3, peaceful = true })
    local state = game.state
    state.skills.hacking = level
    Items.Equip(state, state.player.ship, Hacking.ANALYZER, nil)
    assert(submit(game, { kind = "Undock", actor = 0 }))
    assert(submit(game, { kind = "Stop", actor = 0 }))
    local me = state.balls[state.player.ship]
    me.vx, me.vy, me.vz = 0, 0, 0
    local wins = 0
    for _ = 1, 300 do
      -- (a hull with a sealed hold from nowhere: each has a lock of its own)
      local scout = Pirates.Spawn(state, Pirates.SCOUT, me.system, me.x + 1000, me.y, me.z, me.grid)
      Aftermath.Destroy(state, scout.id, 0, game.events)
      local wreck = state.wrecks[state.wreckIds[#state.wreckIds]]
      wreck.locked = true
      assert(submit(game, { kind = "StartHack", actor = 0, target = wreck.id }))
      Core.TakeEvents(game)
      local turns = 0
      while state.hack and turns < 200 do
        assert(submit(game, { kind = "HackNode", actor = 0, pin = careful(state.hack :: State.Hack) }))
        turns += 1
      end
      for _, event in Core.TakeEvents(game) do
        wins += if event.kind == "HackDone" and event.success == true then 1 else 0
      end
      t.eq(wreck.locked, false, "a hack played out should leave the hold open, won or lost")
      Aftermath.RemoveWreck(state, wreck)
    end
    table.insert(won, wins)
  end
  print(string.format("     hacking: played carefully, %d, %d and %d holds of 300 opened whole at Hacking 1, 3 and 5", won[1], won[2], won[3]))
  t.ok(won[1] >= 120 and won[1] <= 225, `at Hacking 1, {won[1]} of 300`)
  t.ok(won[2] >= 270, `at Hacking 3, {won[2]} of 300`)
  t.ok(won[3] >= 294, `at Hacking 5, {won[3]} of 300`)
  t.ok(won[1] < won[2] and won[2] <= won[3], "the skill should tell")
end)

return suite
