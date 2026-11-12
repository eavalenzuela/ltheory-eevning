--!strict
-- Places a pilot marks in space (Tactical/Space: Bookmark, ForgetBookmark).

local Codec = require("@lt/Core/Persist/Codec")
local Core = require("@lt/Core/Api")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local System = require("@lt/Core/Describe/System")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Bookmarks")

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

-- The pilot out in open space, a long way from anything.
local function adrift(systems: number?): (Core.Game, State.Ball)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true, systems = systems })
  local state = game.state
  assert(submit(game, { kind = "Undock", actor = 0 }))
  local me = state.balls[state.player.ship]
  me.x += 5e7
  me.vx, me.vy, me.vz = 0, 0, 0
  Space.AssignGrid(state, me)
  assert(submit(game, { kind = "Stop", actor = 0 }))
  return game, me
end

local function marks(game: Core.Game): { Core.Entry }
  local found: { Core.Entry } = {}
  for _, entry in Core.Query.Overview(game) do
    if entry.kind == "bookmark" then
      table.insert(found, entry)
    end
  end
  return found
end

suite:Case("a place is marked where the ship is, and is on the overview of its system from then on", function(t)
  local docked = Core.New({ galaxySeed = 1, historySeed = 1, peaceful = true })
  t.eq(refused(docked, { kind = "Bookmark", actor = 0 }), "docked")
  local game, me = adrift()
  local state = game.state
  t.eq(#marks(game), 0)
  t.ok((submit(game, { kind = "Bookmark", actor = 0 })))
  t.ok((submit(game, { kind = "Bookmark", actor = 0, what = "The good rocks" })))
  local found = Core.Query.Bookmarks(game)
  local name = state.galaxy.systems[1].name
  t.eq({ #found, found[1].name, found[2].name } :: { any }, { 2, `{name} spot 1`, "The good rocks" } :: { any })
  -- (where the ship was when it was marked: it has hardly moved since)
  t.eq(found[1].system, 1)
  t.ok(math.sqrt((found[1].x - me.x) ^ 2 + (found[1].y - me.y) ^ 2 + (found[1].z - me.z) ^ 2) < 500)
  local listed = marks(game)
  t.eq({ #listed, listed[1].onGrid } :: { any }, { 2, false } :: { any })
  t.ok(listed[1].id == found[1].id or listed[2].id == found[1].id)
  t.ok(listed[1].distance < 500)
  local body = Core.Query.Body(game, found[2].id)
  t.eq({ body and body.name, body and body.kind } :: { any }, { "The good rocks", "bookmark" } :: { any })
  -- Only so many can be kept.
  for _ = 3, Space.BOOKMARKS do
    t.ok((submit(game, { kind = "Bookmark", actor = 0 })))
  end
  t.eq(refused(game, { kind = "Bookmark", actor = 0 }), `{Space.BOOKMARKS} places are marked already: forget one first`)
  -- One is forgotten (from anywhere), and there is room again.
  t.eq(refused(game, { kind = "ForgetBookmark", actor = 0, target = 12345 }), "no such place is marked")
  t.ok((submit(game, { kind = "ForgetBookmark", actor = 0, target = found[1].id })))
  t.eq({ #Core.Query.Bookmarks(game), Core.Query.Bookmarks(game)[1].name } :: { any }, { Space.BOOKMARKS - 1, "The good rocks" } :: { any })
  t.eq(refused(game, { kind = "Bookmark", actor = 0 }), "(accepted)")
end)

suite:Case("a marked place is warped back to and aligned to, and is nothing to approach or lock", function(t)
  local game, me = adrift()
  local state = game.state
  t.ok((submit(game, { kind = "Bookmark", actor = 0 })))
  local mark = Core.Query.Bookmarks(game)[1]
  t.eq(refused(game, { kind = "WarpTo", actor = 0, target = mark.id }), "too close to warp")
  t.eq(refused(game, { kind = "Approach", actor = 0, target = mark.id }), "no such target")
  t.eq(refused(game, { kind = "LockTarget", actor = 0, target = mark.id }), "no such target")
  t.eq(refused(game, { kind = "Dock", actor = 0, target = mark.id }), "no such target")
  -- Home, and back out to it.
  t.ok((submit(game, { kind = "Dock", actor = 0, target = state.player.home })))
  for _ = 1, 600 do
    Core.Step(game)
    if state.ships[state.player.ship].docked ~= 0 then
      break
    end
  end
  t.ok(state.ships[state.player.ship].docked ~= 0)
  t.eq(#marks(game), 0)
  t.ok((submit(game, { kind = "Undock", actor = 0 })))
  me = state.balls[state.player.ship]
  t.eq(#marks(game), 1)
  t.eq(refused(game, { kind = "AlignTo", actor = 0, target = mark.id }), "(accepted)")
  t.ok((submit(game, { kind = "WarpTo", actor = 0, target = mark.id })))
  t.eq((me.warp :: State.Warp).target, mark.id)
  for _ = 1, 600 do
    Core.Step(game)
    if me.warp == nil then
      break
    end
  end
  t.eq(me.warp, nil)
  local off = math.sqrt((me.x - mark.x) ^ 2 + (me.y - mark.y) ^ 2 + (me.z - mark.z) ^ 2)
  t.ok(off < 200, `the ship came out of warp {off} m from the place it marked`)
  t.ok(me.grid ~= 0)
end)

suite:Case("a place marked in one system is not on another's overview, and marks are in the save", function(t)
  local game, me = adrift(3)
  local state = game.state
  t.ok((submit(game, { kind = "Bookmark", actor = 0 })))
  local next = state.galaxy.systems[1].neighbors[1]
  local gate = System.GateTo(Space.Describe(state, 1), next) :: System.Object
  t.ok((submit(game, { kind = "Jump", actor = 0, target = gate.id })))
  for _ = 1, 900 do
    Core.Step(game)
    if me.system == next then
      break
    end
  end
  t.eq(me.system, next)
  t.eq(#marks(game), 0)
  t.eq(refused(game, { kind = "WarpTo", actor = 0, target = Core.Query.Bookmarks(game)[1].id }), "target is in another system")
  t.ok((submit(game, { kind = "Bookmark", actor = 0 })))
  t.eq(#marks(game), 1)
  t.eq(Core.Query.Bookmarks(game)[2].name, `{state.galaxy.systems[next].name} spot 1`)
  local data, length = Core.Save(game)
  local loaded = Core.Load(data, length)
  t.eq(Core.Hash(loaded), Core.Hash(game))
  t.eq(#Core.Query.Bookmarks(loaded), 2)
  -- (a save from before there were any)
  local file = Codec.Decode(data, length)
  file.saveVersion = 25
  file.state.bookmarks, file.state.bookmarkIds = nil, nil
  local old, oldLength = Codec.Encode(file)
  t.eq(#Core.Query.Bookmarks(Core.Load(old, oldLength)), 0)
end)

suite:Case("a marked place is given a name of the pilot's own, from anywhere, and keeps it", function(t)
  local game = adrift()
  local state = game.state
  t.ok((submit(game, { kind = "Bookmark", actor = 0 })))
  local id = state.bookmarkIds[1]
  local made = state.bookmarks[id].name
  -- A name: one letter to thirty-two, of letters, figures and spaces (and a few marks), tidied.
  t.eq(Space.PlaceName("  The   quiet  belt "), "The quiet belt")
  t.eq(Space.PlaceName("7"), "7")
  t.eq({ Space.PlaceName("   ") } :: { any }, { nil, "a place has a name" } :: { any })
  t.eq(select(2, Space.PlaceName(string.rep("a", 33))), "a name has 32 letters at most")
  t.eq(select(2, Space.PlaceName("a;b")), "a name is of letters, figures and spaces")
  t.eq(refused(game, { kind = "RenameBookmark", actor = 0, target = id, what = "" }), "a place has a name")
  t.eq(refused(game, { kind = "RenameBookmark", actor = 0, target = id }), "a place has a name")
  t.eq(refused(game, { kind = "RenameBookmark", actor = 0, target = 12345, what = "Home" }), "no such place is marked")
  -- Renamed: it is that on the overview, and where it is has not changed.
  local x, y, z = state.bookmarks[id].x, state.bookmarks[id].y, state.bookmarks[id].z
  Core.TakeEvents(game)
  t.ok((submit(game, { kind = "RenameBookmark", actor = 0, target = id, what = " Ore  cache 2 " })))
  local renamed: { [string]: any }? = nil
  for _, event in Core.TakeEvents(game) do
    renamed = if event.kind == "BookmarkRenamed" then event else renamed
  end
  t.eq({ assert(renamed).bookmark, assert(renamed).name } :: { any }, { id, "Ore cache 2" } :: { any })
  local mark = state.bookmarks[id]
  t.eq({ mark.name, mark.x, mark.y, mark.z } :: { any }, { "Ore cache 2", x, y, z } :: { any })
  t.ok(made ~= mark.name)
  t.eq(marks(game)[1].name, "Ore cache 2")
  -- It is in the save by that name.
  local data, length = Core.Save(game)
  t.eq(Core.Load(data, length).state.bookmarks[id].name, "Ore cache 2")
  -- And it can be done docked: a name is not a matter of where the ship is.
  local home = state.player.home
  local ball = state.balls[state.player.ship]
  local station = assert(Space.Object(state, home))
  ball.x, ball.y, ball.z = station.x + station.radius + 500, station.y, station.z
  Space.AssignGrid(state, ball)
  t.ok((submit(game, { kind = "Dock", actor = 0, target = home })))
  for _ = 1, 600 do
    if state.ships[state.player.ship].docked == home then
      break
    end
    Core.Step(game)
  end
  t.ok((submit(game, { kind = "RenameBookmark", actor = 0, target = id, what = "Back door" })))
  t.eq(state.bookmarks[id].name, "Back door")
end)

return suite
