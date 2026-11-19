--!strict
-- What share of a lone launcher's missiles one point defence turret
-- stops (Core/Tactical/PointDefence), each size firing at it alone for
-- 200 s from a fair distance, three times over. The owner's ruling,
-- 2026-11-19, is "mostly misses": about half of every size.
--
--   bin/ltcore Tool/pdsmeasure
local Core = require("@lt/Core/Api")
local Items = require("@lt/Core/Assets/Items")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local M = {}
local function run(hull: string, launcher: string, charge: string, distance: number, seed: number): (number, number)
  local game = Core.New({ galaxySeed = 1, historySeed = seed, peaceful = true })
  local state = game.state
  local old = state.player.ship
  for _, item in Items.In(state, old, nil) do Items.Take(state, item, item.quantity) end
  state.ships[old] = nil
  State.RemoveId(state.shipIds, old)
  local mine = Space.NewShip(state, hull, "Tester", "player", state.player.home)
  state.player.ship = mine.id
  local l = Items.Equip(state, mine.id, launcher, charge)
  Items.Add(state, charge, 5000, mine.id, "cargo")
  local station = assert(Space.Object(state, state.player.home))
  local me = Space.Launch(state, mine, 1, station.x + 50000, station.y, station.z)
  local theirs = Space.NewShip(state, "battleship.owari", "Target", "pirate", 0)
  local foe = Space.Launch(state, theirs, 1, me.x + distance + me.radius + 1000, me.y, me.z)
  foe.grid = me.grid
  local pds = Items.Equip(state, foe.id, "pds.small", "ammo.emp")
  Items.Add(state, "ammo.emp", 50000, foe.id, "cargo")
  assert(Core.Submit(game, { kind = "ActivateModule", actor = foe.id, item = pds.id }))
  Core.Submit(game, { kind = "LockTarget", actor = mine.id, target = foe.id })
  local downed, landed, on = 0, 0, false
  for _ = 1, 200 do
    Core.Step(game)
    if not on then on = Core.Submit(game, { kind = "ActivateModule", actor = mine.id, item = l.id, target = foe.id }) end
    for _, e in Core.TakeEvents(game) do
      if e.kind == "MissileDowned" then downed += 1 elseif e.kind == "MissileHit" then landed += 1 end
    end
  end
  return downed, landed
end
function M.Main(_a: { string }): number
  type Case = { hull: string, launcher: string, charge: string, distance: number }
  local cases: { Case } = {
    { hull = "frigate.carvarro", launcher = "launcher.light", charge = "missile.light.kinetic", distance = 12000 },
    { hull = "frigate.carvarro", launcher = "launcher.rocket", charge = "missile.light.kinetic", distance = 5000 },
    { hull = "cruiser.ouyou", launcher = "launcher.heavy", charge = "missile.heavy.kinetic", distance = 15000 },
    { hull = "cruiser.ouyou", launcher = "launcher.assault", charge = "missile.heavy.kinetic", distance = 7000 },
    { hull = "battleship.owari", launcher = "launcher.cruise", charge = "missile.cruise.kinetic", distance = 30000 },
    { hull = "battleship.owari", launcher = "launcher.torpedo", charge = "missile.cruise.kinetic", distance = 15000 },
  }
  for _, case in cases do
    local d, l = 0, 0
    for seed = 1, 3 do
      local a, b = run(case.hull, case.launcher, case.charge, case.distance, seed)
      d += a; l += b
    end
    print(string.format("%-18s downed %3d landed %3d  (%d%% downed)", case.launcher, d, l, math.floor(100 * d / math.max(d + l, 1))))
  end
  return 0
end
return M
