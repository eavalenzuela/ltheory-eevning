--!strict
-- Hacking (Tactical/Hacking).

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Blueprints = require("@lt/Core/Data/Blueprints")
local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Hacking = require("@lt/Core/Tactical/Hacking")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Rng = require("@lt/Core/Kernel/Rng")
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
-- one of its hulls, with or without a relic analyzer fitted, and the
-- Hacking skill at a level: the game, the hull, and the site.
local function beside(fitted: boolean, level: number): (Core.Game, State.Wreck, State.Site)
  for seed = 1, 60 do
    local game = Core.New({ galaxySeed = 1, historySeed = seed, peaceful = true })
    local state = game.state
    state.skills.hacking = level
    if fitted then
      Items.Equip(state, state.player.ship, Hacking.RELIC, nil)
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

-- A hack begun on a lock made for the test: a matrix whose rows are the
-- five codes, each row a step round from the one above, so that picking
-- (1,1), (2,1), (2,2), (3,2), (3,3) and so on down the stair puts
-- AX DO KE NU RI AX DO in the buffer; and the keys given.
local STAIR = { 1, 6, 7, 12, 13, 18, 19 }
local function crafted(level: number, keys: { { string } }): (Core.Game, State.Wreck, State.Hack)
  local game, wreck = beside(true, level)
  assert(submit(game, { kind = "StartHack", actor = 0, target = wreck.id }))
  local hack = assert(game.state.hack)
  for index = 1, 25 do
    local row, column = (index - 1) // 5, (index - 1) % 5
    hack.cells[index] = Hacking.CODES[(row + column) % 5 + 1]
  end
  for index, codes in keys do
    hack.keys[index].codes = codes
  end
  Core.TakeEvents(game)
  return game, wreck, hack
end

-- What a wreck holds, by type.
local function held(game: Core.Game, wreck: number): { [string]: number }
  local found: { [string]: number } = {}
  for _, item in Items.In(game.state, wreck, "cargo") do
    found[item.type] = (found[item.type] or 0) + item.quantity
  end
  return found
end

local function event(game: Core.Game, kind: string): { [string]: any }?
  local found: { [string]: any }? = nil
  for _, each in Core.TakeEvents(game) do
    found = if each.kind == kind then each else found
  end
  return found
end

suite:Case("a derelict's hold is sealed, and is hacked by a ship with a relic analyzer from near by", function(t)
  local bare, hull = beside(false, 1)
  t.eq(hull.locked, true)
  t.eq(refused(bare, { kind = "Loot", actor = 0, target = hull.id }), "its hold is sealed: it has to be hacked")
  t.eq(refused(bare, { kind = "StartHack", actor = 0, target = hull.id }), "needs a Relic Analyzer fitted")
  t.eq(refused(bare, { kind = "StartHack", actor = 0, target = 12345 }), "not a wreck")
  t.eq(refused(bare, { kind = "HackNode", actor = 0, pin = 1 }), "no hack is under way")
  -- (the analyzer wants its skill to fit)
  local docked = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local item = Items.Add(docked.state, Hacking.RELIC, 1, docked.state.player.home, "hangar")
  t.eq(refused(docked, { kind = "Fit", actor = 0, item = item.id }), "needs Hacking 1")

  local game, wreck = beside(true, 1)
  local state = game.state
  local me = state.balls[state.player.ship]
  me.x += 10000
  t.eq(refused(game, { kind = "StartHack", actor = 0, target = wreck.id }), "too far away")
  me.x -= 10000
  t.ok((submit(game, { kind = "StartHack", actor = 0, target = wreck.id })))
  local hack = assert(state.hack)
  t.eq(refused(game, { kind = "StartHack", actor = 0, target = wreck.id }), "a hack is under way already")
  -- The lock: a matrix of the five codes, five by five, nothing picked; a buffer of five; and the three keys.
  t.eq({ hack.wreck, hack.size, #hack.cells, #hack.used, #hack.buffer, hack.room, hack.along, hack.line } :: { any },
    { wreck.id, 5, 25, 25, 0, 5, "row", 1 } :: { any })
  local counts: { [string]: number } = {}
  for index, code in hack.cells do
    t.ok(table.find(Hacking.CODES, code) ~= nil, `a cell with the code {code}`)
    t.eq(hack.used[index], false)
    counts[code] = (counts[code] or 0) + 1
  end
  -- (as many of each code as of any other)
  for _, code in Hacking.CODES do
    t.eq(counts[code], 5, code)
  end
  t.eq(#hack.keys, 3)
  for index, key in hack.keys do
    t.eq({ key.name, #key.codes, key.done } :: { any }, { Hacking.KEYS[index].name, index + 1, false } :: { any })
    for _, code in key.codes do
      t.ok(table.find(Hacking.CODES, code) ~= nil)
    end
  end
  -- What the pilot sees of it: the top row is what can be picked.
  local seen = assert(Core.Query.Hack(game))
  for index, cell in seen.cells do
    t.eq({ cell.code, cell.used, cell.open } :: { any }, { hack.cells[index], false, index <= 5 } :: { any })
  end
  t.eq({ seen.room, #seen.buffer, #seen.keys, seen.keys[1].begun, seen.along, seen.line } :: { any }, { 5, 0, 3, 0, "row", 1 } :: { any })
  -- The buffer is five codes, and one more for each level of Hacking after the first.
  for level, room in { 5, 6, 7, 8, 9 } do
    state.skills.hacking = level
    t.eq(Hacking.Buffer(state), room, `at Hacking {level}`)
  end
  -- And two more from a hull built for exploration (the Orun's Falchion), which a plain cruiser has not.
  local seeker = Space.NewShip(state, "cruiser.falchion", "Seeker", "player", 0)
  local cruiser = Space.NewShip(state, "cruiser.gladius", "Plain", "player", 0)
  t.eq({ Hacking.Buffer(state, seeker.id), Hacking.Buffer(state, cruiser.id) } :: { any }, { 11, 9 } :: { any })
  state.skills.hacking = 1
  t.eq({ Hacking.Buffer(state, seeker.id), Hacking.Buffer(state, cruiser.id) } :: { any }, { 7, 5 } :: { any })
  -- And one more with a Cipher Buffer fitted; a second adds nothing.
  for _ = 1, 2 do
    Items.Equip(state, cruiser.id, "hack.buffer")
    t.eq(Hacking.Buffer(state, cruiser.id), 6)
  end
  t.eq(#Items.Fitted(state, cruiser.id) >= 2, true)
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

suite:Case("picks go a row and a column by turns from the top row, no cell twice, each putting its code in the buffer", function(t)
  local game, _, hack = crafted(1, { { "RI", "RI" }, { "RI", "RI", "RI" }, { "RI", "RI", "RI", "RI" } })
  -- The first pick is in the top row.
  t.eq(refused(game, { kind = "HackNode", actor = 0, pin = 7 }), "the next pick is in row 1")
  t.eq(refused(game, { kind = "HackNode", actor = 0, pin = 99 }), "the next pick is in row 1")
  t.ok((submit(game, { kind = "HackNode", actor = 0, pin = 2 })))
  t.eq({ hack.buffer, hack.used[2], hack.along, hack.line } :: { any }, { { "DO" }, true, "column", 2 } :: { any })
  -- The next is down its column: the four cells of it that are left.
  t.eq(Hacking.Open(hack), { 7, 12, 17, 22 })
  t.eq(refused(game, { kind = "HackNode", actor = 0, pin = 2 }), "that cell is picked already")
  t.eq(refused(game, { kind = "HackNode", actor = 0, pin = 3 }), "the next pick is in column 2")
  t.ok((submit(game, { kind = "HackNode", actor = 0, pin = 12 })))
  t.eq({ hack.buffer, hack.along, hack.line } :: { any }, { { "DO", "NU" }, "row", 3 } :: { any })
  -- And the one after along the row of that: the four of it that are left.
  t.eq(Hacking.Open(hack), { 11, 13, 14, 15 })
  t.eq(refused(game, { kind = "HackNode", actor = 0, pin = 17 }), "the next pick is in row 3")
  t.ok((submit(game, { kind = "HackNode", actor = 0, pin = 11 })))
  t.eq({ hack.buffer, hack.along, hack.line } :: { any }, { { "DO", "NU", "KE" }, "column", 1 } :: { any })
  local seen = assert(Core.Query.Hack(game))
  t.eq({ seen.buffer, seen.cells[11].used, seen.cells[1].open, seen.cells[6].open, seen.cells[11].open, seen.cells[2].open } :: { any },
    { { "DO", "NU", "KE" }, true, true, true, false, false } :: { any })
end)

suite:Case("a key is in when its codes stand in the buffer one after another, and the end of the buffer shows how far one is begun", function(t)
  t.eq({ Hacking.Holds({ "AX", "DO", "KE" }, { "DO", "KE" }), Hacking.Holds({ "AX", "DO", "KE" }, { "AX", "KE" }),
    Hacking.Holds({ "AX" }, { "AX", "DO" }), Hacking.Holds({}, { "AX" }), Hacking.Holds({ "DO", "DO", "KE" }, { "DO", "KE" }) },
    { true, false, false, false, true })
  t.eq({ Hacking.Begun({ "AX", "DO" }, { "DO", "KE", "NU" }), Hacking.Begun({ "AX", "DO", "KE" }, { "DO", "KE", "NU" }),
    Hacking.Begun({ "AX" }, { "DO", "KE" }), Hacking.Begun({}, { "DO" }), Hacking.Begun({ "DO", "KE", "AX" }, { "DO", "KE" }) },
    { 1, 2, 0, 0, 0 })

  -- Down the stair: the safeguards' key first, then the manifest's, with the strongbox's out of reach.
  local game, wreck, hack = crafted(1, { { "AX", "DO" }, { "DO", "KE", "NU" }, { "RI", "RI", "RI", "RI" } })
  local state = game.state
  local before = held(game, wreck.id)
  t.ok((submit(game, { kind = "HackNode", actor = 0, pin = STAIR[1] })))
  t.eq({ hack.keys[1].done, assert(Core.Query.Hack(game)).keys[1].begun } :: { any }, { false, 1 } :: { any })
  t.ok((submit(game, { kind = "HackNode", actor = 0, pin = STAIR[2] })))
  local told = assert(event(game, "HackKey"), "nobody said a key was in")
  t.eq({ told.key, told.name, hack.keys[1].done, hack.keys[2].done } :: { any }, { 1, "Safeguards", true, false } :: { any })
  t.eq({ assert(Core.Query.Hack(game)).keys[1].begun, assert(Core.Query.Hack(game)).keys[2].begun }, { 2, 1 })
  t.ok((submit(game, { kind = "HackNode", actor = 0, pin = STAIR[3] })))
  t.ok((submit(game, { kind = "HackNode", actor = 0, pin = STAIR[4] })))
  t.eq({ hack.keys[2].done, state.hack ~= nil, wreck.locked } :: { any }, { true, true, true } :: { any })
  -- The fifth pick fills the buffer: the hack is over, and the hold open with what the keys say.
  t.ok((submit(game, { kind = "HackNode", actor = 0, pin = STAIR[5] })))
  local done = assert(event(game, "HackDone"))
  t.eq({ state.hack, wreck.locked, done.success, done.keys, done.reason, done.wreck } :: { any },
    { nil, false, true, 2, "buffer full", wreck.id } :: { any })
  -- Nothing burnt, and the datacores as many again (the manifest's key); no custom module (the strongbox's was not in).
  local after = held(game, wreck.id)
  for type, quantity in before do
    t.eq(after[type], if type == "datacore" then 2 * quantity else quantity, type)
  end
  t.ok((before.datacore or 0) >= 1, "a derelict's hull should have a datacore")
  for type in after do
    t.ok(before[type] ~= nil, `the hold has {type}, which it had not`)
  end
  t.eq(refused(game, { kind = "StartHack", actor = 0, target = wreck.id }), "its hold is not sealed")
  t.eq(refused(game, { kind = "Loot", actor = 0, target = wreck.id }), "(accepted)")
end)

suite:Case("with every key in it is over at once, the strongbox giving a custom module; with the safeguards' not in, half the hold is burnt", function(t)
  -- All three on the stair, in five picks: over with the last, though a bigger buffer has room left.
  local game, wreck, hack = crafted(5, { { "AX", "DO" }, { "DO", "KE", "NU" }, { "DO", "KE", "NU", "RI" } })
  t.eq(hack.room, 9)
  local before = held(game, wreck.id)
  for index = 1, 5 do
    t.ok((submit(game, { kind = "HackNode", actor = 0, pin = STAIR[index] })))
  end
  local done = assert(event(game, "HackDone"))
  t.eq({ game.state.hack, done.success, done.keys, done.reason } :: { any }, { nil, true, 3, "every key" } :: { any })
  local after = held(game, wreck.id)
  local customs = 0
  for type, quantity in after do
    local module = Modules.byId[type]
    if module and module.meta and (before[type] or 0) < quantity then
      customs += quantity - (before[type] or 0)
    end
  end
  t.eq(customs, 1, "the strongbox should give one custom module")
  t.eq(after.datacore, 2 * before.datacore)

  -- The buffer filled with the safeguards' key not in: half of every stack is burnt, whatever else was got.
  local lost, hull, lock = crafted(1, { { "RI", "RI" }, { "DO", "KE", "NU" }, { "RI", "RI", "RI", "RI" } })
  local had = held(lost, hull.id)
  for index = 1, 5 do
    t.ok((submit(lost, { kind = "HackNode", actor = 0, pin = STAIR[index] })))
  end
  local over = assert(event(lost, "HackDone"))
  t.eq({ lost.state.hack, hull.locked, over.success, over.keys, lock.keys[2].done } :: { any }, { nil, false, false, 1, true } :: { any })
  local left = held(lost, hull.id)
  for type, quantity in had do
    local kept = quantity - math.ceil(quantity / 2)
    -- (the manifest's key was in: what datacores came through the burning are as many again, and one at least)
    t.eq(left[type] or 0, if type == "datacore" then kept + math.max(1, kept) else kept, type)
  end
end)

suite:Case("until the first pick the lock can be left and come back to, the same; after it, leaving or flying off ends the hack", function(t)
  local game, wreck = beside(true, 2)
  local state = game.state
  t.ok((submit(game, { kind = "StartHack", actor = 0, target = wreck.id })))
  local first = Codec.HashOf(assert(state.hack))
  -- Left before a pick: nothing done, the hold as sealed as it was, and the same lock next time.
  Core.TakeEvents(game)
  t.ok((submit(game, { kind = "AbandonHack", actor = 0 })))
  local left = assert(event(game, "HackDone"))
  t.eq({ state.hack, wreck.locked, left.reason, left.success } :: { any }, { nil, true, "left", false } :: { any })
  t.ok((submit(game, { kind = "StartHack", actor = 0, target = wreck.id })))
  t.eq(Codec.HashOf(assert(state.hack)), first)
  -- Flown off before a pick: dropped, the hold still sealed.
  local me = state.balls[state.player.ship]
  me.x += 4000
  Core.Step(game)
  t.ok(state.hack ~= nil, "the hack was dropped inside its leash")
  me.x += Hacking.LEASH + 1000
  Core.Step(game)
  t.eq({ state.hack, wreck.locked } :: { any }, { nil, true } :: { any })
  me.x -= Hacking.LEASH + 5000

  -- In the save, a pick made.
  t.ok((submit(game, { kind = "StartHack", actor = 0, target = wreck.id })))
  t.ok((submit(game, { kind = "HackNode", actor = 0, pin = 3 })))
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.eq(#assert(loaded.state.hack).buffer, 1)
  -- Left after a pick: it is ended, with what keys are in (none: half is burnt).
  local before = held(game, wreck.id)
  Core.TakeEvents(game)
  t.ok((submit(game, { kind = "AbandonHack", actor = 0 })))
  local ended = assert(event(game, "HackDone"))
  t.eq({ state.hack, wreck.locked, ended.reason, ended.success } :: { any }, { nil, false, "ended", false } :: { any })
  for type, quantity in before do
    t.eq((held(game, wreck.id))[type] or 0, quantity - math.ceil(quantity / 2), type)
  end
  -- And so is one begun whose ship flies out of reach.
  local other, hull, hack = crafted(1, { { "AX", "DO" }, { "RI", "RI", "RI" }, { "RI", "RI", "RI", "RI" } })
  t.ok((submit(other, { kind = "HackNode", actor = 0, pin = STAIR[1] })))
  t.ok((submit(other, { kind = "HackNode", actor = 0, pin = STAIR[2] })))
  t.eq(hack.keys[1].done, true)
  local had = held(other, hull.id)
  local ball = other.state.balls[other.state.player.ship]
  ball.x += 20000
  Core.TakeEvents(other)
  Core.Step(other)
  local gone = assert(event(other, "HackDone"))
  t.eq({ other.state.hack, hull.locked, gone.reason, gone.success } :: { any }, { nil, false, "out of reach", true } :: { any })
  t.eq(held(other, hull.id), had, "the safeguards' key was in: nothing should be burnt")

  -- A save from before locks were matrices: a hack that was under way is dropped, the hold as sealed as it was.
  local file = Codec.Decode(data, length)
  file.saveVersion = 38
  file.state.hack = { wreck = wreck.id, width = 6, height = 5, nodes = {}, coherence = 80, most = 80, strength = 20, start = 13 }
  local old, oldLength = Codec.Encode(file)
  local opened = Core.Load(old, oldLength)
  t.eq({ opened.state.hack, opened.state.wrecks[wreck.id].locked } :: { any }, { nil, true } :: { any })
end)

-- Every way through a lock of so many picks: which of the keys each can
-- be got by itself, and the most that can be got together.
local function reach(hack: State.Hack, room: number): ({ boolean }, number)
  local size = hack.size
  local used: { boolean } = {}
  local buffer: { string } = {}
  local alone = { false, false, false }
  local most = 0
  local function go(along: string, line: number)
    if #buffer >= room then
      return
    end
    for at = 1, size do
      local index = if along == "row" then (line - 1) * size + at else (at - 1) * size + line
      if not used[index] then
        used[index] = true
        table.insert(buffer, hack.cells[index])
        local keys = 0
        for which, key in hack.keys do
          if Hacking.Holds(buffer, key.codes) then
            alone[which] = true
            keys += 1
          end
        end
        most = math.max(most, keys)
        go(if along == "row" then "column" else "row", at)
        table.remove(buffer)
        used[index] = false
      end
    end
  end
  go("row", 1)
  return alone, most
end

-- A game with a listening post in the first system, the pilot's ship
-- beside one of its vaults with a data analyzer fitted and Hacking at a
-- level, and a hack begun on a lock made for the test: a matrix whose
-- rows are the six codes, each a step round from the one above, so that
-- the stair (1,1), (2,1), (2,2), (3,2), (3,3)... puts AX DO KE NU RI VE
-- in the buffer; and the keys given.
local VAULT_STAIR = { 1, 7, 8, 14, 15, 21, 22 }
local function vault(level: number, keys: { { string } }?): (Core.Game, State.Wreck, State.Hack)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  state.skills.hacking = level
  Items.Equip(state, state.player.ship, Hacking.ANALYZER, nil)
  assert(submit(game, { kind = "Undock", actor = 0 }))
  assert(submit(game, { kind = "Stop", actor = 0 }))
  local site = assert(Sites.Plant(state, 1, "data", Rng.For(7, 7), game.events))
  local found: State.Wreck? = nil
  for _, id in state.wreckIds do
    if state.wrecks[id].grid == site.id then
      found = found or state.wrecks[id]
    end
  end
  local wreck = assert(found, "a listening post with no vault")
  local me = state.balls[state.player.ship]
  me.x, me.y, me.z = wreck.x + 1500, wreck.y, wreck.z
  me.vx, me.vy, me.vz = 0, 0, 0
  Space.AssignGrid(state, me)
  assert(submit(game, { kind = "StartHack", actor = 0, target = wreck.id }))
  local hack = assert(state.hack)
  if keys then
    local codes = Hacking.LOCKS.vault.codes
    for index = 1, 36 do
      local row, column = (index - 1) // 6, (index - 1) % 6
      hack.cells[index] = codes[(row + column) % 6 + 1]
    end
    for index, run in keys do
      hack.keys[index].codes = run
    end
  end
  Core.TakeEvents(game)
  return game, wreck, hack
end

suite:Case("a vault's lock is another kind: six by six, of six codes, with longer keys, and what its keys are for is its own", function(t)
  local game, wreck, hack = vault(1)
  t.eq({ wreck.name, wreck.locked, wreck.lock, hack.size, #hack.cells, hack.room, hack.ends } :: { any },
    { Sites.VAULT, true, "vault", 6, 36, Hacking.BUFFER, 0 } :: { any })
  local counts: { [string]: number } = {}
  for _, code in hack.cells do
    counts[code] = (counts[code] or 0) + 1
  end
  for _, code in Hacking.LOCKS.vault.codes do
    t.eq(counts[code], 6, code)
  end
  for index, key in hack.keys do
    local made = Hacking.LOCKS.vault.keys[index]
    t.eq({ key.name, #key.codes, key.done } :: { any }, { made.name, made.length, false } :: { any })
  end
  t.eq({ hack.keys[1].name, hack.keys[2].name, hack.keys[3].name }, { "Safeguards", "Index", "Archive" })
  -- The pilot is told what each is for, and how long there will be.
  local seen = assert(Core.Query.Hack(game))
  t.eq({ seen.size, seen.clock, seen.left, seen.keys[1].what, seen.keys[3].what } :: { any },
    { 6, Hacking.LOCKS.vault.clock, Hacking.LOCKS.vault.clock, "or it is all wiped", "tech 2 drawings" } :: { any })
  -- (a derelict's hold is as it was)
  local other, hull = beside(true, 1)
  t.ok((submit(other, { kind = "StartHack", actor = 0, target = hull.id })))
  local plain = assert(Core.Query.Hack(other))
  t.eq({ plain.size, plain.clock, plain.left, plain.keys[1].what } :: { any }, { 5, 0, 0, "or half is burnt" } :: { any })
  -- And every vault can be opened whole with the smallest buffer: each key by itself.
  for index, key in hack.keys do
    t.ok(#key.codes <= Hacking.BUFFER, `key {index} is longer than the smallest buffer`)
  end
end)

suite:Case("a vault's index doubles its datacores and its archive has tech 2 drawings; without the safeguards it is wiped", function(t)
  local game, wreck = vault(5, { { "AX", "DO", "KE" }, { "DO", "KE", "NU" }, { "DO", "KE", "NU", "RI" } })
  local before = held(game, wreck.id)
  t.ok((before.datacore or 0) >= 3, "a vault has more datacores than a derelict's hull")
  for type in before do
    t.ok(type == "datacore" or string.sub(type, 1, 10) == "blueprint." or string.sub(type, 1, 5) == "book.",
      `a vault had a {type} in it`)
  end
  for index = 1, 5 do
    t.ok((submit(game, { kind = "HackNode", actor = 0, pin = VAULT_STAIR[index] })))
  end
  local done = assert(event(game, "HackDone"))
  t.eq({ game.state.hack, done.success, done.keys, done.reason, wreck.locked } :: { any }, { nil, true, 3, "every key", false } :: { any })
  local after = held(game, wreck.id)
  t.eq(after.datacore, 2 * before.datacore)
  local drawings = 0
  for type, quantity in after do
    if string.sub(type, -3) == ".ii" and string.sub(type, 1, 10) == "blueprint." then
      drawings += quantity - (before[type] or 0)
      t.ok(Blueprints.byId[type].invented, type)
    end
  end
  t.eq(drawings, 1, "the archive should give the drawings of one tech 2 module")

  -- The buffer filled with the safeguards' key not in: nothing is left, whatever else was got.
  local lost, box, lock = vault(1, { { "VE", "VE", "VE" }, { "DO", "KE", "NU" }, { "VE", "VE", "VE", "VE" } })
  for index = 1, 5 do
    t.ok((submit(lost, { kind = "HackNode", actor = 0, pin = VAULT_STAIR[index] })))
  end
  local over = assert(event(lost, "HackDone"))
  t.eq({ lost.state.hack, box.locked, over.success, over.keys, lock.keys[2].done, over.reason } :: { any },
    { nil, false, false, 1, true, "buffer full" } :: { any })
  t.eq(held(lost, box.id), {})
end)

suite:Case("a vault's lock is on a clock from the first pick: looking is free, and when the time is up it is over", function(t)
  local game, wreck, hack = vault(5, { { "AX", "DO", "KE" }, { "VE", "VE", "VE" }, { "VE", "VE", "VE", "VE" } })
  local clock = Hacking.LOCKS.vault.clock
  -- Looking costs nothing.
  for _ = 1, clock * 2 do
    Core.Step(game)
  end
  t.ok(game.state.hack ~= nil and hack.ends == 0)
  local before = held(game, wreck.id)
  -- The first pick starts it.
  t.ok((submit(game, { kind = "HackNode", actor = 0, pin = VAULT_STAIR[1] })))
  t.ok(hack.ends > 0)
  local left = assert(Core.Query.Hack(game)).left
  t.ok(left <= clock and left >= clock - 2, `{left} s left after the first pick`)
  t.ok((submit(game, { kind = "HackNode", actor = 0, pin = VAULT_STAIR[2] })))
  t.ok((submit(game, { kind = "HackNode", actor = 0, pin = VAULT_STAIR[3] })))
  t.ok(hack.keys[1].done)
  -- Out of time, with the safeguards' key in: what was in it is there, and no more.
  local done: { [string]: any }? = nil
  for _ = 1, clock + 2 do
    Core.Step(game)
    done = done or event(game, "HackDone")
  end
  local over = assert(done, "the clock ran out and nothing was said")
  t.eq({ game.state.hack, over.reason, over.success, over.keys, wreck.locked } :: { any }, { nil, "out of time", true, 1, false } :: { any })
  t.eq(held(game, wreck.id), before)
  -- (a save from before vaults has a hold's lock on every sealed thing, and no clock on a hack under way)
  local saved = vault(1)
  local data, length = Core.Save(saved)
  local file = Codec.Decode(data, length)
  file.saveVersion = 45
  for _, each in file.state.wrecks do
    each.lock = nil
  end
  file.state.hack.ends = nil
  file.state.boosters = nil
  local old, oldLength = Codec.Encode(file)
  local loaded = Core.Load(old, oldLength)
  t.eq(assert(loaded.state.hack).ends, 0)
  for _, each in loaded.state.wrecks do
    t.eq(each.lock, "")
  end
end)

suite:Case("every lock can be opened whole with the smallest buffer; all three keys together want a bigger one, and luck", function(t)
  local game = beside(true, 1)
  local state = game.state
  local me = state.balls[state.player.ship]
  local locks = 150
  local all5, all7, two5, tried7 = 0, 0, 0, 0
  for n = 1, locks do
    -- (a hull with a sealed hold from nowhere: each has a lock of its own)
    local scout = Pirates.Spawn(state, Pirates.SCOUT, me.system, me.x + 1000, me.y, me.z, me.grid)
    Aftermath.Destroy(state, scout.id, 0, game.events)
    local wreck = state.wrecks[state.wreckIds[#state.wreckIds]]
    wreck.locked = true
    assert(submit(game, { kind = "StartHack", actor = 0, target = wreck.id }))
    local hack = assert(state.hack)
    local alone, most = reach(hack, Hacking.BUFFER)
    t.eq(alone, { true, true, true }, `lock {n}: a key that the smallest buffer cannot get`)
    all5 += if most == 3 then 1 else 0
    two5 += if most >= 2 then 1 else 0
    -- (a buffer of seven, which is Hacking 3's, on some of them: it is a long look)
    if n <= 40 then
      tried7 += 1
      all7 += if select(2, reach(hack, Hacking.BUFFER + 2)) == 3 then 1 else 0
    end
    assert(submit(game, { kind = "AbandonHack", actor = 0 }))
    Aftermath.RemoveWreck(state, wreck)
  end
  print(string.format("     hacking: of %d locks, two keys together in %d and all three in %d with a buffer of 5; all three in %d of %d with 7",
    locks, two5, all5, all7, tried7))
  t.ok(two5 >= 0.5 * locks, `two keys together in only {two5} of {locks}`)
  t.ok(all5 <= 0.1 * locks, `all three keys with the smallest buffer in {all5} of {locks}: too easy`)
  t.ok(all7 / tried7 > all5 / locks, "a bigger buffer should get all three more often")
  t.ok(all7 >= 0.1 * tried7 and all7 <= 0.6 * tried7, `all three keys with a buffer of seven in {all7} of {tried7}`)
end)

return suite
