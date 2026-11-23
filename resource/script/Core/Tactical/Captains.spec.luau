--!strict
-- Captains: a region's named pirates, who get away and come back worth more, and are replaced when brought down.

local Captains = require("@lt/Core/Tactical/Captains")
local Core = require("@lt/Core/Api")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Captains")

suite:Case("a region has a roster of named pirates: the same one for the same reason, five of them, made as they are asked for", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  t.eq(#state.captains.ids, 0)
  local one = Captains.Pick(state, 1, 77)
  t.eq(#state.captains.ids, Captains.ROSTER)
  t.eq(Captains.Pick(state, 1, 77), one)
  t.eq(one.region, state.galaxy.systems[1].region)
  t.ok(#one.name > 0 and one.alive and one.escapes == 0)
  -- (a system of the same region asks the same roster; another region has its own)
  local other = 0
  for id = 2, #state.galaxy.systems do
    if state.galaxy.systems[id].region ~= state.galaxy.systems[1].region then
      other = id
      break
    end
  end
  t.ok(other ~= 0)
  Captains.Pick(state, other, 77)
  t.eq(#state.captains.ids, 2 * Captains.ROSTER)
  -- How they are called: a captain by rank, a veteran by kind, and either told apart by whoever draws them.
  t.eq(Pirates.Rank(Captains.Called(one, 2, "Marauder")), 2)
  t.eq(Pirates.Rank(Captains.Called(one, 1, "Raider")), 1)
end)

suite:Case("one who gets away is worth half as much again each time, up to three times; one brought down is replaced", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local events = {}
  local one = Captains.Pick(state, 1, 5)
  t.eq(Captains.Price(one), 1)
  Captains.Escaped(state, one.id, events)
  t.eq({ one.escapes, Captains.Price(one) } :: { any }, { 1, 1.5 } :: { any })
  t.eq(events[1].kind, "CaptainEscaped")
  for _ = 1, 10 do
    Captains.Escaped(state, one.id, events)
  end
  t.eq(Captains.Price(one), Captains.MOST)
  Captains.Killed(state, one.id, events)
  t.eq({ one.alive, events[#events].kind } :: { any }, { false, "CaptainKilled" } :: { any })
  -- (and nobody who is gone gets away again)
  local was = one.escapes
  Captains.Escaped(state, one.id, events)
  t.eq(one.escapes, was)
  -- The roster is full again, with somebody new in it.
  for salt = 1, 40 do
    local next = Captains.Pick(state, 1, 1000 + salt)
    t.ok(next.alive and next.id ~= one.id)
  end
  local alive = 0
  for _, id in state.captains.ids do
    local each = state.captains.list[id]
    alive += if each.region == one.region and each.alive then 1 else 0
  end
  t.eq(alive, Captains.ROSTER)
  -- (and the roster is in the save)
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(#loaded.state.captains.ids, #state.captains.ids)
end)

return suite
