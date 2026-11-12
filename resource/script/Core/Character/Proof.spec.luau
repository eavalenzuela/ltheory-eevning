--!strict
-- Played through: that a new pilot, in the ship a new game gives them
-- and with nothing but what the game and the lessons hand over, can fly
-- a career of the kind that can go wrong to its end (Character/Careers).
--
-- The pilot here does what the lessons say and no better: goes where
-- the pirates come, picks out the nearest, orbits it and shoots, and
-- when the shield is gone and the armour going, warps home, has the
-- ship mended and goes out again. It has no skill but what a new pilot
-- has, and trains only what a lesson tells it to.

local Careers = require("@lt/Core/Character/Careers")
local Core = require("@lt/Core/Api")
local Hacking = require("@lt/Core/Tactical/Hacking")
local Items = require("@lt/Core/Assets/Items")
local Modules = require("@lt/Core/Data/Modules")
local Sites = require("@lt/Core/Tactical/Sites")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")

local suite = Test.Suite("Proof")

-- A new pilot in a new game, and what they can do.
type Pilot = {
  game: Core.Game,
  state: State.State,
  home: number,
  lost: boolean,          -- the ship a new game gave is gone
  bounties: number,       -- pirates destroyed and paid for
  fled: number,           -- times the pilot went home to be mended
  ticks: number,
  events: { [string]: number },   -- how many of each kind of event were the pilot's
}

local function new(seed: number): Pilot
  local game = Core.New({ galaxySeed = 1, historySeed = seed })
  return { game = game, state = game.state, home = game.state.player.home, lost = false, bounties = 0, fled = 0, ticks = 0, events = {} }
end

local function step(p: Pilot, count: number?)
  for _ = 1, count or 1 do
    Core.Step(p.game)
    p.ticks += 1
    for _, event in Core.TakeEvents(p.game) do
      if event.kind == "WalletChanged" and event.reason == "bounty" then
        p.bounties += 1
      elseif event.kind == "Ejected" then
        p.lost = true
      end

      p.events[event.kind] = (p.events[event.kind] or 0) + 1
    end
  end
end

local function order(p: Pilot, command: State.Command): (boolean, string?)
  command.actor = p.state.player.ship
  local ok, why = Core.Submit(p.game, command)
  step(p)
  return ok, why
end

local function must(p: Pilot, command: State.Command)
  local ok, why = order(p, command)
  assert(ok, `{command.kind} was refused: {tostring(why)}`)
end

local function ball(p: Pilot): State.Ball?
  return p.state.balls[p.state.player.ship]
end

-- The loose stack of a type in the home hangar.
local function stock(p: Pilot, type: string): State.Item?
  for _, item in Items.In(p.state, p.home, "hangar") do
    if item.type == type and item.slot == 0 then
      return item
    end
  end
  return nil
end

-- Home, however far, and the ship mended there if it can be paid for.
local function dock(p: Pilot)
  if p.state.ships[p.state.player.ship].docked == p.home then
    return
  end
  order(p, { kind = "Dock", actor = 0, target = p.home })
  for _ = 1, 9000 do
    if p.lost or p.state.ships[p.state.player.ship].docked == p.home then
      break
    end
    step(p)
  end
  if not p.lost then
    assert(p.state.ships[p.state.player.ship].docked == p.home, "the pilot never got home")
    order(p, { kind = "Repair", actor = 0 })
  end
end

-- The belts of the home system (not the sites), nearest first.
local function belts(p: Pilot): { number }
  local found: { number } = {}
  for _, entry in Core.Query.Overview(p.game) do
    if entry.kind == "belt" then
      table.insert(found, entry.id)
    end
  end
  return found
end

-- Out of the station (if in it) and to a place, in warp.
local function to(p: Pilot, place: number)
  if p.state.ships[p.state.player.ship].docked ~= 0 then
    must(p, { kind = "Undock", actor = 0 })
  end
  local me = assert(ball(p))
  if me.grid == place then
    return
  end
  order(p, { kind = "WarpTo", actor = 0, target = place })
  -- (the warp begun, and then over: a planet is somewhere to warp to and no grid of its own)
  local begun = false
  for _ = 1, 9000 do
    local now = ball(p)
    if p.lost or now == nil then
      break
    end
    begun = begun or now.warp ~= nil
    if begun and now.warp == nil then
      break
    end
    step(p)
  end
  assert(p.lost or begun, "a warp that was ordered never began")
end

-- The nearest pirate on the pilot's grid.
local function hostile(p: Pilot, me: State.Ball): number
  local nearest, least = 0, math.huge
  for _, id in p.state.pilotIds do
    local other = p.state.balls[id]
    if other and other.system == me.system and other.grid == me.grid and Space.Distance(other :: any, me :: any) < least then
      nearest, least = id, Space.Distance(other :: any, me :: any)
    end
  end
  return nearest
end

-- Fight at the belts until so many bounties have been paid in all: the
-- nearest pirate orbited and shot at, home to be mended when the shield
-- is gone and the armour going, and on to the next belt when nobody
-- comes to this one. Returns the belt the last pirate was destroyed at.
local function fight(p: Pilot, wanted: number, orbit: number): number
  local places: { number } = {}
  local at, quiet, last = 1, 0, 0
  while p.bounties < wanted and not p.lost and p.ticks < 60000 do
    if p.state.ships[p.state.player.ship].docked ~= 0 then
      must(p, { kind = "Undock", actor = 0 })
    end
    if #places == 0 then
      places = belts(p)
      assert(#places > 0, "the home system has no belt")
    end
    local me = assert(ball(p))
    if me.grid ~= places[at] and me.warp == nil then
      to(p, places[at])
      quiet = 0
      continue
    end
    local v = me.vitals
    local enemy = hostile(p, me)
    if v.shield < 0.15 * v.shieldMax and v.armor < 0.6 * v.armorMax then
      -- ("If your shield goes, warp out.")
      p.fled += 1
      dock(p)
      continue
    elseif enemy == 0 then
      quiet += 1
      -- (and what mends the shield is not left running on nothing)
      for _, running in v.running do
        local item = p.state.items[running.item]
        if item and Modules.byId[item.type].repair and not running.stopping then
          Core.Submit(p.game, { kind = "DeactivateModule", actor = me.id, item = item.id })
        end
      end
      -- (nobody has come: they are somewhere else for now)
      if quiet > 300 then
        at = at % #places + 1
        quiet = 0
        to(p, places[at])
      else
        step(p)
      end
      continue
    end
    quiet = 0
    if not (me.mode == "orbit" and me.target == enemy) then
      Core.Submit(p.game, { kind = "Orbit", actor = me.id, target = enemy, range = orbit })
    end
    local targeted, locked = false, false
    for _, lock in v.locks do
      if lock.target == enemy then
        targeted, locked = true, lock.locked
      end
    end
    if not targeted then
      Core.Submit(p.game, { kind = "LockTarget", actor = me.id, target = enemy })
    elseif locked then
      for _, item in Items.Fitted(p.state, me.id) do
        local module = Modules.byId[item.type]
        local on = false
        for _, running in v.running do
          on = on or running.item == item.id
        end
        if not on and (module.weapon or (module.repair and v.shield < 0.7 * v.shieldMax)) then
          Core.Submit(p.game, { kind = "ActivateModule", actor = me.id, item = item.id, target = if module.weapon then enemy else nil })
        end
      end
    end
    local before = p.bounties
    step(p)
    last = if p.bounties > before then places[at] else last
  end
  return last
end

-- The wreck on the pilot's grid that is nearest (and, with 'whole', has
-- not been salvaged).
local function wreckHere(p: Pilot, whole: boolean?): State.Wreck?
  local me = assert(ball(p))
  local found: State.Wreck? = nil
  local least = math.huge
  for _, id in p.state.wreckIds do
    local wreck = p.state.wrecks[id]
    if wreck.system == me.system and wreck.grid == me.grid and not (whole and wreck.salvaged)
      and Space.Distance(wreck :: any, me :: any) < least then
      found, least = wreck, Space.Distance(wreck :: any, me :: any)
    end
  end
  return found
end

-- Up to a wreck, to within so far of it.
local function upTo(p: Pilot, wreck: State.Wreck, within: number)
  order(p, { kind = "Approach", actor = 0, target = wreck.id, range = 500 })
  for _ = 1, 2000 do
    local me = ball(p)
    if p.lost or me == nil or Space.Gap(me :: any, wreck :: any) < within then
      break
    end
    step(p)
  end
end

local function lesson(p: Pilot, kind: string, career: string)
  must(p, { kind = kind, actor = 0, what = career })
end

-- Put a module from the hangar on the ship: true if it went on.
local function fit(p: Pilot, type: string): (boolean, string?)
  local item = assert(stock(p, type), `no {type} in the hangar`)
  return order(p, { kind = "Fit", actor = 0, item = item.id })
end

suite:Case("a new pilot in the starter ship flies the enforcement career to its end, whatever pirates the belts bring", function(t)
  local said: { string } = {}
  local finished = 0
  local SEEDS = 6
  for seed = 1, SEEDS do
    local p = new(seed)
    local state = p.state
    -- Fit for it: the shield extender a new game leaves in the hangar.
    lesson(p, "AcceptLesson", "combat")
    t.ok((fit(p, "shield.extender.small")), "the extender would not fit")
    lesson(p, "CompleteLesson", "combat")
    -- (rounds in the hold: a gun reloads from there, and the lesson has just given five hundred)
    must(p, { kind = "MoveItems", actor = 0, item = assert(stock(p, "ammo.emp")).id, quantity = 800, to = "cargo" })

    -- First pirate.
    lesson(p, "AcceptLesson", "combat")
    local belt = fight(p, 1, 1500)
    if p.lost then
      table.insert(said, `{seed}: lost to the first pirate`)
      continue
    end
    dock(p)
    lesson(p, "CompleteLesson", "combat")
    -- (the shield booster it pays goes in the other mid slot)
    t.ok((fit(p, "shield.booster.small")), "the booster would not fit")

    -- What they leave: back to where the pirate was destroyed, for its wreck.
    lesson(p, "AcceptLesson", "combat")
    to(p, belt)
    local wreck = wreckHere(p)
    if wreck == nil then
      -- (somebody else has come meanwhile, or it has gone: another)
      belt = fight(p, p.bounties + 1, 1500)
      wreck = if p.lost then nil else wreckHere(p)
    end
    if p.lost or wreck == nil then
      table.insert(said, `{seed}: no wreck to loot`)
      continue
    end
    upTo(p, wreck, 2000)
    t.ok((order(p, { kind = "Loot", actor = 0, target = wreck.id })), "the wreck would not be looted")
    dock(p)
    if p.lost then
      table.insert(said, `{seed}: lost on the way home with the loot`)
      continue
    end
    lesson(p, "CompleteLesson", "combat")

    -- Nothing wasted: the book learnt and trained, the salvager fitted, a wreck worked.
    lesson(p, "AcceptLesson", "combat")
    must(p, { kind = "LearnSkill", actor = 0, item = assert(stock(p, "book.salvaging")).id })
    must(p, { kind = "TrainSkill", actor = 0, type = "salvaging" })
    for _ = 1, 600 do
      if (state.skills.salvaging or 0) >= 1 then
        break
      end
      step(p)
    end
    t.ok((state.skills.salvaging or 0) >= 1, "Salvaging was not trained in ten minutes")
    -- (it goes on beside the guns: a new pilot is not asked to take one off for it)
    local on, why = fit(p, "salvager.small")
    t.ok(on, `the salvager would not go on beside the guns: {tostring(why)}`)
    to(p, belt)
    wreck = wreckHere(p, true)
    if wreck == nil then
      belt = fight(p, p.bounties + 1, 1500)
      wreck = if p.lost then nil else wreckHere(p, true)
    end
    if p.lost or wreck == nil then
      table.insert(said, `{seed}: no wreck to salvage`)
      continue
    end
    upTo(p, wreck, 4000)
    local salvager: State.Item? = nil
    for _, item in Items.Fitted(state, state.player.ship) do
      salvager = if item.type == "salvager.small" then item else salvager
    end
    local had = p.events.Salvaged or 0
    -- (kept on: it stops when the capacitor is low, and is put on again)
    for _ = 1, 900 do
      if p.lost or (p.events.Salvaged or 0) > had then
        break
      end
      local working = false
      for _, running in assert(ball(p)).vitals.running do
        working = working or running.item == assert(salvager).id
      end
      if not working then
        Core.Submit(p.game, { kind = "ActivateModule", actor = state.player.ship, item = assert(salvager).id, target = wreck.id })
      end
      step(p)
    end
    if p.lost or (p.events.Salvaged or 0) == had then
      table.insert(said, `{seed}: the wreck was not salvaged`)
      continue
    end
    dock(p)
    if p.lost then
      table.insert(said, `{seed}: lost on the way home from salvaging`)
      continue
    end
    lesson(p, "CompleteLesson", "combat")
    -- (the plate the lesson pays, in the low slot)
    fit(p, "armor.plate.200mm")

    -- A patrol: five more.
    lesson(p, "AcceptLesson", "combat")
    fight(p, p.bounties + 5, 1500)
    if p.lost then
      table.insert(said, `{seed}: lost on patrol`)
      continue
    end
    dock(p)
    if p.lost then
      table.insert(said, `{seed}: lost on the way home from patrol`)
      continue
    end
    lesson(p, "CompleteLesson", "combat")
    t.eq(Careers.Of(state, "combat").done, #Careers.byId.combat.lessons)
    finished += 1
    table.insert(said, `{seed}: done in {math.floor(p.ticks / 60)} min, {p.bounties} pirates, home to be mended {p.fled} times`)
  end
  print(`     enforcement, new pilot: {finished} of {SEEDS} histories finished`)
  for _, line in said do
    print(`       {line}`)
  end
  t.eq(finished, SEEDS, "a new pilot in the starter ship did not finish the enforcement career")
end)

-- Scan, and wait for the scanner to come round again.
local function scan(p: Pilot)
  for _ = 1, 40 do
    if p.state.tick >= p.state.scanReady then
      break
    end
    step(p)
  end
  must(p, { kind = "Scan", actor = 0 })
  step(p, Sites.SCAN + 1)
end

-- A way through the lock under way that gets its first key in, as a
-- pilot finds one by looking: the cells to pick, in order (none, if
-- there is no way).
local function wayIn(hack: State.Hack): { number }
  local used = table.clone(hack.used)
  local buffer = table.clone(hack.buffer)
  local picks: { number } = {}
  local function go(along: string, line: number): boolean
    if Hacking.Holds(buffer, hack.keys[1].codes) then
      return true
    elseif #buffer >= hack.room then
      return false
    end
    for at = 1, hack.size do
      local index = if along == "row" then (line - 1) * hack.size + at else (at - 1) * hack.size + line
      if not used[index] then
        used[index] = true
        table.insert(buffer, hack.cells[index])
        table.insert(picks, index)
        if go(if along == "row" then "column" else "row", at) then
          return true
        end
        table.remove(picks)
        table.remove(buffer)
        used[index] = false
      end
    end
    return false
  end
  go(hack.along, hack.line)
  return picks
end

suite:Case("a new pilot in the starter ship flies the survey career to its end: a scan, a site found, a probe, a derelict hacked whole", function(t)
  local said: { string } = {}
  local finished = 0
  local SEEDS = 6
  for seed = 1, SEEDS do
    local p = new(seed)
    local state = p.state
    local function ready(): boolean
      return (Careers.Ready(state, state.ships[state.player.ship], "survey"))
    end
    -- Listen: one scan.
    lesson(p, "AcceptLesson", "survey")
    must(p, { kind = "Undock", actor = 0 })
    scan(p)
    dock(p)
    lesson(p, "CompleteLesson", "survey")

    -- A belt on no chart: scans until something is found.
    lesson(p, "AcceptLesson", "survey")
    must(p, { kind = "Undock", actor = 0 })
    for _ = 1, 8 do
      if state.careers.survey.count >= 1 then
        break
      end
      scan(p)
    end
    dock(p)
    t.ok(ready(), `{seed}: eight scans found nothing`)
    lesson(p, "CompleteLesson", "survey")

    -- Probes: the two handed over into the hold, and one put out.
    lesson(p, "AcceptLesson", "survey")
    must(p, { kind = "MoveItems", actor = 0, item = assert(stock(p, "probe.scan")).id, to = "cargo" })
    must(p, { kind = "Undock", actor = 0 })
    must(p, { kind = "LaunchProbe", actor = 0 })
    must(p, { kind = "RecallProbes", actor = 0 })
    dock(p)
    lesson(p, "CompleteLesson", "survey")

    -- The sealed hold. What it wants learnt first: CPU Management to 2, then Hacking from its book.
    lesson(p, "AcceptLesson", "survey")
    local began = p.ticks
    must(p, { kind = "TrainSkill", actor = 0, type = "electronics" })
    must(p, { kind = "TrainSkill", actor = 0, type = "electronics" })
    for _ = 1, 1200 do
      if (state.skills.electronics or 0) >= 2 then
        break
      end
      step(p)
    end
    must(p, { kind = "LearnSkill", actor = 0, item = assert(stock(p, "book.hacking")).id })
    must(p, { kind = "TrainSkill", actor = 0, type = "hacking" })
    for _ = 1, 1200 do
      if (state.skills.hacking or 0) >= 1 then
        break
      end
      step(p)
    end
    t.ok((state.skills.hacking or 0) >= 1, "Hacking was not to be had in twenty minutes")
    local learning = p.ticks - began
    t.ok((fit(p, "analyzer.data")), "the analyzer would not fit")
    must(p, { kind = "MoveItems", actor = 0, item = assert(stock(p, "probe.scan")).id, to = "cargo" })
    must(p, { kind = "Undock", actor = 0 })
    -- The derelict: scans until the scanner says where a signal it cannot
    -- pin down is, a probe taken there, and scans again.
    local derelict = 0
    for _ = 1, 30 do
      for _, row in (Core.Query.Sites(p.game)) do
        if row.found and row.kind == "relic" then
          derelict = row.id
        elseif row.faint and row.near ~= "" and derelict == 0 then
          local planet = 0
          for _, entry in Core.Query.Overview(p.game) do
            planet = if entry.name == row.near then entry.id else planet
          end
          assert(planet ~= 0, `the scanner names {row.near}, which is not on the overview`)
          to(p, planet)
          if Core.Validate(p.game, { kind = "LaunchProbe", actor = state.player.ship }) then
            must(p, { kind = "LaunchProbe", actor = 0 })
          end
          break
        end
      end
      if derelict ~= 0 then
        break
      end
      scan(p)
    end
    if derelict == 0 then
      table.insert(said, `{seed}: the derelict was not found in thirty scans`)
      continue
    end
    to(p, derelict)
    local hull: State.Wreck? = nil
    for _, id in state.wreckIds do
      local wreck = state.wrecks[id]
      hull = if wreck.grid == derelict and wreck.locked then wreck else hull
    end
    if hull == nil then
      table.insert(said, `{seed}: the derelict has no sealed hold`)
      continue
    end
    upTo(p, hull, 3500)
    must(p, { kind = "StartHack", actor = 0, target = hull.id })
    local picks = wayIn(assert(state.hack))
    t.ok(#picks > 0, `{seed}: no way through the lock gets the safeguards' key in`)
    for _, pick in picks do
      must(p, { kind = "HackNode", actor = 0, pin = pick })
    end
    -- (the first key is in: the rest is ended there, as a new pilot would be glad to)
    if state.hack then
      must(p, { kind = "AbandonHack", actor = 0 })
    end
    t.ok(not hull.locked, "the hold is still sealed")
    dock(p)
    if p.lost then
      table.insert(said, `{seed}: lost on the way home from the derelict`)
      continue
    end
    t.ok(ready(), `{seed}: the hold was opened, and the lesson is not done`)
    lesson(p, "CompleteLesson", "survey")
    t.eq(Careers.Of(state, "survey").done, #Careers.byId.survey.lessons)
    finished += 1
    table.insert(said, `{seed}: done in {math.floor(p.ticks / 60)} min, {math.floor(learning / 60)} of them learning to hack`)
  end
  print(`     survey, new pilot: {finished} of {SEEDS} histories finished`)
  for _, line in said do
    print(`       {line}`)
  end
  t.eq(finished, SEEDS, "a new pilot in the starter ship did not finish the survey career")
end)

return suite
