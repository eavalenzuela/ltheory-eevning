--!strict
-- The guide (Character/Guide).

local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Guide = require("@lt/Core/Character/Guide")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Guide")

local function done(game: Core.Game): { string }
  return table.clone(game.state.guide)
end

suite:Case("every step has a name of its own, a group, and a line on how it is done that fits its window", function(t)
  local seen: { [string]: boolean } = {}
  local groups: { string } = {}
  for _, step in Guide.steps do
    t.ok(not seen[step.id], `two steps are called '{step.id}'`)
    seen[step.id] = true
    t.ok(#step.title > 3 and #step.title <= 40, `'{step.title}' is too long a title`)
    t.ok(#step.how > 10 and #step.how <= 90, `how to {step.id} takes {#step.how} letters`)
    t.ok(#step.on > 3)
    if groups[#groups] ~= step.group then
      t.ok(table.find(groups, step.group) == nil, `the steps of '{step.group}' are not together`)
      table.insert(groups, step.group)
    end
    t.eq(Guide.byId[step.id], step)
  end
  t.eq(groups, { "Flying", "Making a living", "Fighting", "Getting on" })
end)

suite:Case("a step is done when the pilot does the thing, once, and nobody else's doing counts", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true, traffic = true })
  local state = game.state
  local rows, count = Core.Query.Guide(game)
  t.eq({ #rows, count, rows[1].done } :: { any }, { #Guide.steps, 0, false } :: { any })
  -- Haulers undock and warp and miners mine all about, and the pilot sits docked.
  for _ = 1, 400 do
    Core.Step(game)
  end
  t.ok(#state.trafficIds > 0)
  t.eq(done(game), {})
  Core.TakeEvents(game)
  -- The pilot undocks: that is the first step, and it is said once.
  t.ok((Core.Submit(game, { kind = "Undock", actor = state.player.ship })))
  Core.Step(game)
  t.eq(done(game), { "undock" })
  local said = 0
  for _, event in Core.TakeEvents(game) do
    if event.kind == "Guided" then
      said += 1
      t.eq({ event.step, event.title, event.done, event.of } :: { any }, { "undock", "Undock", 1, #Guide.steps } :: { any })
    end
  end
  t.eq(said, 1)
  t.ok((Core.Submit(game, { kind = "Dock", actor = state.player.ship, target = state.player.home })))
  for _ = 1, 200 do
    Core.Step(game)
  end
  t.ok((Core.Submit(game, { kind = "Undock", actor = state.player.ship })))
  Core.Step(game)
  t.eq(done(game), { "undock" })
  -- Warping, and marking a place.
  local planet = 0
  for _, object in Core.Query.Objects(game, 1) do
    if object.kind == "planet" and planet == 0 then
      planet = object.id
    end
  end
  t.ok((Core.Submit(game, { kind = "Bookmark", actor = state.player.ship })))
  t.ok((Core.Submit(game, { kind = "WarpTo", actor = state.player.ship, target = planet })))
  for _ = 1, 60 do
    Core.Step(game)
  end
  t.eq(done(game), { "undock", "bookmark", "warp" })
  rows, count = Core.Query.Guide(game)
  t.eq({ count, rows[1].done, rows[2].done, rows[3].done } :: { any }, { 3, true, true, false } :: { any })
end)

suite:Case("some steps want more of the event than its kind", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  local state = game.state
  local mine = state.player.ship
  local function after(event: Guide.Event): { string }
    Guide.Step(state, { event }, 1)
    return done(game)
  end
  -- Money that is not a bounty is no pirate destroyed. A bounty is.
  t.eq(after({ kind = "WalletChanged", reason = "insurance", amount = 5 }), {})
  t.eq(after({ kind = "WalletChanged", reason = "bounty", amount = 5 }), { "kill" })
  -- A scan that finds nothing has found no site, and nor has somebody else's.
  t.eq(after({ kind = "Scanned", ball = mine, found = 0, signals = 2 }), { "kill" })
  t.eq(after({ kind = "Scanned", ball = mine + 1, found = 1, signals = 0 }), { "kill" })
  t.eq(after({ kind = "Scanned", ball = mine, found = 1, signals = 0 }), { "kill", "site" })
  -- Somebody else's mining, looting and drones are theirs.
  t.eq(after({ kind = "Mined", ball = mine + 1, units = 10 }), { "kill", "site" })
  t.eq(after({ kind = "DroneLaunched", owner = mine + 1 }), { "kill", "site" })
  t.eq(after({ kind = "DroneLaunched", owner = mine }), { "kill", "site", "drones" })
  -- Everything done: there is no more to say.
  for _, step in Guide.steps do
    if not Guide.Done(state, step.id) then
      table.insert(state.guide, step.id)
    end
  end
  local events: { Guide.Event } = { { kind = "Undocked", ship = mine } }
  Guide.Step(state, events, 1)
  t.eq(#events, 1)
end)

suite:Case("what has been done is in the save, and an older save has done nothing", function(t)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  t.ok((Core.Submit(game, { kind = "Undock", actor = game.state.player.ship })))
  Core.Step(game)
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.eq(loaded.state.guide, { "undock" })
  local file = Codec.Decode(data, length)
  file.saveVersion = 26
  file.state.guide = nil
  local old, oldLength = Codec.Encode(file)
  t.eq(Core.Load(old, oldLength).state.guide, {})
end)

return suite
