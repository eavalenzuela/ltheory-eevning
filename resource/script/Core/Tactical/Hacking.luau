--!strict
-- Hacking: getting into the sealed hold of a derelict.
--
-- A derelict's hull (Tactical/Sites) has its hold sealed: it is not
-- looted until it has been hacked, by a ship with a Relic Analyzer
-- fitted, from within the analyzer's reach. (A Data Analyzer until
-- 2026-11-16; it opens a listening post's vaults now.)
--
-- The lock is a matrix of codes, five by five, and three keys: short
-- runs of codes. The pilot has a buffer, of five codes and one more for
-- each level of Hacking after the first, and fills it by picking cells of
-- the matrix. The first pick is anywhere in the top row. The next has
-- to be in the column of that one, the one after in the row of that,
-- and so on, a row and a column by turns; and no cell is picked twice.
-- A key is in when its codes stand in the buffer one after another.
--
-- The hack is over when the buffer is full, when every key is in, when
-- there is nothing left to pick, or when the pilot says it is; and then
-- the hold opens, whatever was done. What the keys decide is how:
--   - the safeguards' key (two codes): without it, half of everything
--     in the hold is burnt as it opens;
--   - the manifest's (three): the hold's datacores are as many again
--     (one, if it had none);
--   - the strongbox's (four): there is a custom make of some module in
--     the hold beside.
-- Each key can be got by itself within the smallest buffer there is.
-- Getting two, or all three, is a matter of finding a way through the
-- matrix on which they overlap, and of how big the buffer is: with five
-- codes the safeguards' key and one other go together in about four
-- locks of five and all three in none; with seven, all three in about
-- one lock in four; with eight, in about half.
--
-- Until the first pick the pilot can look as long as they like, and
-- leave with nothing done: the lock is the same next time. After it,
-- the hack is begun: leaving it, or flying out of the analyzer's reach,
-- ends it with whatever keys are in.
--
-- A vault's lock (a listening post has vaults: Tactical/Sites) is
-- another kind, and a harder one. Its matrix is six by six, of six
-- codes; its keys are longer (three codes, three and four); and it is
-- on a clock: from the first pick there are so many seconds
-- (Hacking.LOCKS.vault.clock) and then it is over, with whatever keys
-- are in. What its keys decide:
--   - the safeguards' key: without it the vault wipes itself, and
--     there is nothing in it at all;
--   - the index's: the vault's datacores are as many again;
--   - the archive's: there are the drawings of the tech 2 make of some
--     module in the vault beside, which are otherwise only invented.
-- The pilot's buffer is the same for both. So a vault is worth looking
-- at for as long as it takes before the first pick: the looking is
-- free, and the clock is not.
--
-- (A grid, a buffer and runs to find, in the manner of the hacking of
-- Cyberpunk 2077. Not yet: locks on anything that is not adrift.)

local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")

local Hacking = {}

export type Event = { [string]: any }

Hacking.SIZE = 5
-- The codes a matrix is made of.
Hacking.CODES = { "AX", "DO", "KE", "NU", "RI" }
-- The keys, the first being the one that matters most, and how long
-- each is.
Hacking.KEYS = { { name = "Safeguards", length = 2 }, { name = "Manifest", length = 3 }, { name = "Strongbox", length = 4 } }

-- The kinds of lock there are: how big the matrix, what codes it is
-- made of, its keys (and what each is for, in a few words), how long
-- there is from the first pick (ticks; 0: as long as it takes), and how
-- much of what it holds is lost without the first key.
export type Lock = {
  size: number,
  codes: { string },
  keys: { { name: string, length: number, what: string } },
  clock: number,
  burns: number,
}
Hacking.LOCKS = {
  hold = {
    size = Hacking.SIZE, codes = Hacking.CODES, clock = 0, burns = 0.5,
    keys = {
      { name = "Safeguards", length = 2, what = "or half is burnt" },
      { name = "Manifest", length = 3, what = "datacores, as many again" },
      { name = "Strongbox", length = 4, what = "a custom module" },
    },
  },
  vault = {
    size = 6, codes = { "AX", "DO", "KE", "NU", "RI", "VE" }, clock = 45, burns = 1,
    keys = {
      { name = "Safeguards", length = 3, what = "or it is all wiped" },
      { name = "Index", length = 3, what = "datacores, as many again" },
      { name = "Archive", length = 4, what = "tech 2 drawings" },
    },
  },
  -- (a Drowned habitat's core, Tactical/Sites: the hardest there is,
  -- and behind its third key the drawings of a Wormhole Bridge, found
  -- nowhere else. Mine but the drawings, the owner's 2026-11-22)
  habitat = {
    size = 6, codes = { "AX", "DO", "KE", "NU", "RI", "VE" }, clock = 40, burns = 1,
    keys = {
      { name = "Safeguards", length = 3, what = "or it is all wiped" },
      { name = "Conduits", length = 4, what = "datacores, as many again" },
      { name = "Design Store", length = 4, what = "Wormhole Bridge drawings" },
    },
  },
} :: { [string]: Lock }

-- The lock a sealed thing has: a vault's, or a hold's.
function Hacking.LockOf(wreck: State.Wreck): Lock
  return Hacking.LOCKS[wreck.lock] or Hacking.LOCKS.hold
end
-- The smallest buffer: what a pilot with Hacking 1 has.
Hacking.BUFFER = 5
Hacking.LEASH = 1000        -- m: how much farther off than the analyzer reaches before the hack is ended
Hacking.ANALYZER = "analyzer.data"
-- (since 2026-11-16 a derelict's hold is opened with a relic analyzer, and
-- a vault's with a data analyzer: module expansion)
Hacking.RELIC = "analyzer.relic"

-- The analyzer a lock is opened with: a relic analyzer for a derelict's
-- hold, a data analyzer for a vault.
function Hacking.AnalyzerFor(lock: string): string
  return if lock == "vault" or lock == "habitat" then Hacking.ANALYZER else Hacking.RELIC
end
local DATACORE = "datacore"

-- The pilot's buffer: five codes, and one more for every level of
-- Hacking after the first. (And two more in a hack begun from 'ship',
-- if its hull is built for exploration: Ships.EXPLORER; and one more
-- with a Cipher Buffer fitted, Data/Modules, however many.)
function Hacking.Buffer(state: State.State, ship: number?): number
  local level = math.max(1, state.skills.hacking or 0)
  local from = state.ships[ship or 0]
  local hull = if from then Ships.byId[from.type] else nil
  local helper = 0
  if from then
    for _, item in Items.Fitted(state, from.id) do
      local module = Modules.byId[item.type]
      helper = math.max(helper, if module then module.hackBuffer or 0 else 0)
    end
  end
  return Hacking.BUFFER + level - 1 + (if hull and hull.explorer then Ships.EXPLORER.hack else 0) + helper
end

-- The cells of a matrix that can be picked now: those not picked yet
-- of the row or the column the next pick has to be in.
function Hacking.Open(hack: State.Hack): { number }
  local found: { number } = {}
  for at = 1, hack.size do
    local index = if hack.along == "row" then (hack.line - 1) * hack.size + at else (at - 1) * hack.size + hack.line
    if not hack.used[index] then
      table.insert(found, index)
    end
  end
  return found
end

-- Whether a run of codes stands in a buffer, one after another.
function Hacking.Holds(buffer: { string }, codes: { string }): boolean
  for start = 1, #buffer - #codes + 1 do
    local all = true
    for at, code in codes do
      if buffer[start + at - 1] ~= code then
        all = false
        break
      end
    end
    if all then
      return true
    end
  end
  return false
end

-- How much of a run the end of a buffer has begun: the longest start
-- of it that the buffer ends with.
function Hacking.Begun(buffer: { string }, codes: { string }): number
  for length = math.min(#codes, #buffer), 1, -1 do
    local all = true
    for at = 1, length do
      if buffer[#buffer - length + at] ~= codes[at] then
        all = false
        break
      end
    end
    if all then
      return length
    end
  end
  return 0
end

-- The lock of a hull: the same every time it is asked for. A matrix of
-- the codes, as many of each as of any other, shuffled; and for each
-- key a run that some way through the matrix spells out, early enough
-- to be got within the smallest buffer.
local function lock(state: State.State, wreck: number, kind: Lock): ({ string }, { State.HackKey })
  local rng = Rng.For(state.historySeed, wreck, 61)
  local size = kind.size
  local cells: { string } = {}
  for index = 1, size * size do
    cells[index] = kind.codes[(index - 1) % #kind.codes + 1]
  end
  for index = #cells, 2, -1 do
    local other = Rng.Int(rng, index) + 1
    cells[index], cells[other] = cells[other], cells[index]
  end
  local keys: { State.HackKey } = {}
  for _, key in kind.keys do
    -- A way through the matrix, as a pilot would go: from the top row,
    -- a column and a row by turns, no cell twice.
    local used: { boolean } = {}
    local path: { string } = {}
    local along, line = "row", 1
    for _ = 1, Hacking.BUFFER do
      local open: { number } = {}
      for at = 1, size do
        local index = if along == "row" then (line - 1) * size + at else (at - 1) * size + line
        if not used[index] then
          table.insert(open, index)
        end
      end
      local pick = open[Rng.Int(rng, #open) + 1]
      used[pick] = true
      table.insert(path, cells[pick])
      if along == "row" then
        along, line = "column", (pick - 1) % size + 1
      else
        along, line = "row", (pick - 1) // size + 1
      end
    end
    local from = Rng.Int(rng, Hacking.BUFFER - key.length + 1)
    local codes: { string } = {}
    for at = 1, key.length do
      codes[at] = path[from + at]
    end
    table.insert(keys, { name = key.name, codes = codes, done = false })
  end
  return cells, keys
end

-- How far the ship's analyzer for a kind of lock reaches (the best
-- fitted; "" a derelict's hold, "vault" a vault); 0 with none.
function Hacking.Reach(state: State.State, ship: number, lock: string): number
  local reach = 0
  local relic = lock ~= "vault" and lock ~= "habitat"
  for _, item in Items.Fitted(state, ship) do
    local analyzer = Modules.byId[item.type].analyzer
    if analyzer and (analyzer.relic == true) == relic then
      reach = math.max(reach, analyzer.range)
    end
  end
  return reach
end

function Hacking.Validate(state: State.State, command: State.Command): (boolean, string?)
  local ship = state.ships[command.actor]
  local ball = state.balls[command.actor]
  if ship == nil or ship.id ~= state.player.ship then
    return false, "no such ship"
  elseif ball == nil then
    return false, "docked"
  elseif ball.warp and ball.warp.stage == "warp" then
    return false, "in warp"
  end
  local kind = command.kind
  if kind == "StartHack" then
    local wreck = state.wrecks[command.target or 0]
    if wreck == nil then
      return false, "not a wreck"
    elseif not wreck.locked then
      return false, "its hold is not sealed"
    elseif state.hack then
      return false, "a hack is under way already"
    end
    local reach = Hacking.Reach(state, ship.id, wreck.lock)
    if reach <= 0 then
      return false, `needs a {Modules.byId[Hacking.AnalyzerFor(wreck.lock)].name} fitted`
    elseif wreck.system ~= ball.system or Space.Gap(ball :: any, wreck :: any) > reach then
      return false, "too far away"
    end
    return true
  end
  local hack = state.hack
  if hack == nil then
    return false, "no hack is under way"
  elseif kind == "AbandonHack" then
    return true
  elseif kind == "HackNode" then
    if table.find(Hacking.Open(hack), command.pin or 0) == nil then
      return false, if hack.used[command.pin or 0] then "that cell is picked already"
        elseif hack.along == "row" then `the next pick is in row {hack.line}`
        else `the next pick is in column {hack.line}`
    end
    return true
  end
  return false, `unknown command '{kind}'`
end

-- The modules there is a custom make of, worked out once: what a
-- strongbox has one of.
local customs: { string } = {}
for _, module in Modules.list do
  if module.meta == 1 then
    table.insert(customs, module.id)
  end
end

-- The drawings there are of a tech 2 make of a module, worked out
-- once: what a vault's archive has one of.
local drawings: { string } = {}
for _, module in Modules.list do
  if module.tech == 2 and not module.internal then
    table.insert(drawings, "blueprint." .. module.id)
  end
end

-- What a Drowned habitat's core has behind its third key: the drawings
-- of the Wormhole Bridge (Data/Structures).
local BRIDGE = { "blueprint.service.bridge.wormhole" }

-- The hack is over: the hold is open, as the keys that are in say.
local function finish(state: State.State, hack: State.Hack, reason: string, events: { Event })
  local wreck = state.wrecks[hack.wreck]
  local done = 0
  for _, key in hack.keys do
    done += if key.done then 1 else 0
  end
  if wreck then
    local kind = Hacking.LockOf(wreck)
    wreck.locked = false
    if not hack.keys[1].done then
      for _, item in Items.In(state, wreck.id, "cargo") do
        Items.Take(state, item, math.ceil(item.quantity * kind.burns))
      end
    end
    -- (a vault that has wiped itself has nothing for the other keys to find)
    local wiped = not hack.keys[1].done and kind.burns >= 1
    if hack.keys[2].done and not wiped then
      local cores = 0
      for _, item in Items.In(state, wreck.id, "cargo") do
        cores += if item.type == DATACORE then item.quantity else 0
      end
      Items.Add(state, DATACORE, math.max(1, cores), wreck.id, "cargo")
    end
    -- (the third key's prize is the lock's own: a custom make of
    -- something out of a hold, drawings out of a vault)
    local prizes = if wreck.lock == "vault" then drawings elseif wreck.lock == "habitat" then BRIDGE else customs
    if hack.keys[3].done and #prizes > 0 and not wiped then
      Items.Add(state, prizes[Rng.Int(Rng.For(state.historySeed, wreck.id, 67), #prizes) + 1], 1, wreck.id, "cargo")
    end
  end
  state.hack = nil
  table.insert(events, { kind = "HackDone", wreck = hack.wreck, success = hack.keys[1].done, keys = done, reason = reason })
end

function Hacking.Apply(state: State.State, command: State.Command, events: { Event })
  local kind = command.kind
  if kind == "StartHack" then
    local sealed = Hacking.LockOf(state.wrecks[command.target :: number])
    local cells, keys = lock(state, command.target :: number, sealed)
    state.hack = { wreck = command.target :: number, size = sealed.size, cells = cells, used = table.create(#cells, false),
      buffer = {}, room = Hacking.Buffer(state, command.actor), keys = keys, along = "row", line = 1, ends = 0 }
    table.insert(events, { kind = "HackStarted", wreck = command.target })
    return
  end
  local hack = state.hack :: State.Hack
  if kind == "AbandonHack" then
    -- Before the first pick, nothing is done and nothing lost. After
    -- it, leaving is ending.
    if #hack.buffer == 0 then
      state.hack = nil
      table.insert(events, { kind = "HackDone", wreck = hack.wreck, success = false, keys = 0, reason = "left" })
    else
      finish(state, hack, "ended", events)
    end
    return
  end
  -- A pick: its code into the buffer, and the next is across it. (And
  -- with the first, a lock that is on a clock begins to count.)
  local pick = command.pin :: number
  local wreck = state.wrecks[hack.wreck]
  local clock = if wreck then Hacking.LockOf(wreck).clock else 0
  if #hack.buffer == 0 and clock > 0 then
    hack.ends = state.tick + clock
  end
  hack.used[pick] = true
  table.insert(hack.buffer, hack.cells[pick])
  if hack.along == "row" then
    hack.along, hack.line = "column", (pick - 1) % hack.size + 1
  else
    hack.along, hack.line = "row", (pick - 1) // hack.size + 1
  end
  local all = true
  for index, key in hack.keys do
    if not key.done and Hacking.Holds(hack.buffer, key.codes) then
      key.done = true
      table.insert(events, { kind = "HackKey", wreck = hack.wreck, key = index, name = key.name })
    end
    all = all and key.done
  end
  if all then
    finish(state, hack, "every key", events)
  elseif #hack.buffer >= hack.room then
    finish(state, hack, "buffer full", events)
  elseif #Hacking.Open(hack) == 0 then
    finish(state, hack, "nothing left to pick", events)
  end
end

-- Once a tick: a hack whose ship has gone out of reach, or whose hull
-- has gone, is over. One not begun is dropped, with nothing done. One
-- begun is ended, with whatever keys are in.
function Hacking.Step(state: State.State, events: { Event })
  local hack = state.hack
  if hack == nil then
    return
  end
  local wreck = state.wrecks[hack.wreck]
  local ball = state.balls[state.player.ship]
  local reach = if wreck then Hacking.Reach(state, state.player.ship, wreck.lock) else 0
  if wreck == nil or ball == nil or ball.system ~= wreck.system or reach <= 0
    or Space.Gap(ball :: any, wreck :: any) > reach + Hacking.LEASH then
    if #hack.buffer == 0 or wreck == nil then
      state.hack = nil
      table.insert(events, { kind = "HackDone", wreck = hack.wreck, success = false, keys = 0, reason = "out of reach" })
    else
      finish(state, hack, "out of reach", events)
    end
  elseif hack.ends > 0 and state.tick >= hack.ends then
    finish(state, hack, "out of time", events)
  end
end

return Hacking
