--!strict
-- The simulation must be a pure function of its state: the same seeds give
-- the same history, and a state that is saved and loaded part-way carries
-- on exactly as if it had never left memory. Loading rebuilds every table,
-- so anything that depends on the order a table happened to be filled in
-- (iterating a map, for instance) shows up here as a different hash.

local Codec = require("@lt/Core/Persist/Codec")
local Sim = require("@lt/Sim/Sim")
local State = require("@lt/Sim/State")
local Test = require("@lt/Tool/Test")

local SYSTEMS = 80
local TICKS = 1500
local SAVE_AT = { 1, 400, 900 }

local function reload(state: State.State): State.State
  local data, length = Codec.Encode(state)
  return Codec.Decode(data, length)
end

-- Run from the two seeds; reload the state after each tick listed in
-- 'saves'. Returns the final hash.
local function run(galaxySeed: number, historySeed: number, saves: { number }): string
  local state = Sim.New(galaxySeed, SYSTEMS, historySeed)
  local nextSave = 1
  for _ = 1, TICKS do
    Sim.Tick(state)
    if saves[nextSave] == state.tick then
      state = reload(state)
      nextSave += 1
    end
  end
  return Codec.HashOf(state)
end

local suite = Test.Suite("Sim determinism")

local baseline: string? = nil
local function uninterrupted(): string
  if baseline == nil then
    baseline = run(1, 1, {})
  end
  return baseline :: string
end

suite:Case("the state is plain data that the codec accepts", function(t)
  local state = Sim.New(1, SYSTEMS, 1)
  for _ = 1, 50 do
    Sim.Tick(state)
  end
  t.eq(Codec.HashOf(reload(state)), Codec.HashOf(state))
end)

suite:Case("the same seeds replay identically", function(t)
  t.eq(run(1, 1, {}), uninterrupted())
end)

suite:Case("a different history seed gives a different history", function(t)
  t.ok(run(1, 2, {}) ~= uninterrupted(), "history seed 2 matched history seed 1")
end)

suite:Case("a state saved and loaded mid-run continues identically", function(t)
  t.eq(run(1, 1, SAVE_AT), uninterrupted())
end)

return suite
