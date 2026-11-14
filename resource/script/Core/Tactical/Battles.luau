--!strict
-- The fleet's log: what happened in the fights the pilot was not at.
--
-- A hired pilot who is attacked with the pilot somewhere else fights it
-- out where they are, tick by tick, as any fight is fought (Tactical/
-- Fleet, Tactical/Pirates). The pilot hears that it has begun, and
-- until now nothing more. This keeps a record of each: where and when,
-- who of the pilot's was there, who came for them, what was destroyed
-- on either side, who got away, and what it paid.
--
-- A record is opened when a hired pilot says they are attacked (Fleet's
-- alarm), for the place they are at, and is added to as things happen
-- there: whoever else of the pilot's is there or comes, every pirate
-- that is there or comes, each one destroyed (and the share of its
-- bounty that was paid) or gone, each ship of the pilot's lost. It is
-- closed when nobody is left on one side or the other. If the pilot
-- comes to the place while it goes on, the record says so and goes on.
-- The last forty are kept.
--
-- Nothing here decides anything: it is written by those who do.

local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")

local Battles = {}

export type Event = { [string]: any }

-- How many fights are remembered.
Battles.KEPT = 40

-- The fight going on at a place, if one is.
local function open(state: State.State, system: number, grid: number): State.Fight?
  for index = #state.fleetLog, 1, -1 do
    local fight = state.fleetLog[index]
    if fight.ended == 0 and fight.system == system and fight.grid == grid then
      return fight
    end
  end
  return nil
end

-- One more of a name, in a tally of names.
local function count(tally: { State.Tally }, name: string)
  for _, entry in tally do
    if entry.name == name then
      entry.count += 1
      return
    end
  end
  table.insert(tally, { name = name, count = 1 })
end

-- Who is at a fight's place now: every hired pilot of the pilot's whose
-- ship is there is put down (once), and every pirate (once). Returns
-- how many of each are there.
local function muster(state: State.State, fight: State.Fight): (number, number)
  local ours, theirs = 0, 0
  for _, id in state.fleetIds do
    local wing = state.fleet[id]
    local ball = state.balls[wing.ship]
    if ball and ball.system == fight.system and ball.grid == fight.grid then
      ours += 1
      if not table.find(fight.pilots, wing.name) then
        table.insert(fight.pilots, wing.name)
      end
    end
  end
  for _, id in state.pilotIds do
    local ball = state.balls[id]
    if ball and ball.system == fight.system and ball.grid == fight.grid then
      theirs += 1
      if not table.find(fight.seen, id) then
        table.insert(fight.seen, id)
        count(fight.attackers, state.ships[id].name)
      end
    end
  end
  return ours, theirs
end

-- A hired pilot is attacked at a place, with the pilot somewhere else:
-- a record is opened for the place, unless one is open already.
function Battles.Begin(state: State.State, system: number, grid: number)
  if grid == 0 or open(state, system, grid) then
    return
  end
  local place = Space.Object(state, grid)
  local fight: State.Fight = {
    id = State.NewId(state), system = system, grid = grid,
    where = if place then place.name else `open space in {state.galaxy.systems[system].name}`,
    began = state.tick, ended = 0, pilots = {}, seen = {}, attackers = {}, destroyed = {}, lost = {}, fled = 0, bounty = 0,
    joined = false,
  }
  table.insert(state.fleetLog, fight)
  while #state.fleetLog > Battles.KEPT do
    table.remove(state.fleetLog, 1)
  end
  muster(state, fight)
end

-- A pirate was destroyed at a place by the pilot's side, and so much of
-- its bounty was paid: put down, if there is a fight on there.
function Battles.Destroyed(state: State.State, system: number, grid: number, name: string, paid: number)
  local fight = open(state, system, grid)
  if fight then
    count(fight.destroyed, name)
    fight.bounty += paid
  end
end

-- A ship of the pilot's that a hired pilot flew was destroyed at a place.
function Battles.Lost(state: State.State, system: number, grid: number, pilot: string, ship: string)
  local fight = open(state, system, grid)
  if fight then
    table.insert(fight.lost, `{pilot}'s {ship}`)
    if not table.find(fight.pilots, pilot) then
      table.insert(fight.pilots, pilot)
    end
  end
end

-- A pirate broke off from a place and got away.
function Battles.Fled(state: State.State, system: number, grid: number)
  local fight = open(state, system, grid)
  if fight then
    fight.fled += 1
  end
end

-- Once a tick: each fight going on is brought up to date with who is
-- there, and is over when either side has nobody left there.
function Battles.Step(state: State.State, events: { Event })
  local lead = state.balls[state.player.ship]
  for _, fight in state.fleetLog do
    if fight.ended == 0 then
      local ours, theirs = muster(state, fight)
      if lead and lead.system == fight.system and lead.grid == fight.grid then
        fight.joined = true
      end
      if ours == 0 or theirs == 0 then
        -- (never 0, which is a fight going on)
        fight.ended = math.max(1, state.tick)
        local destroyed = 0
        for _, entry in fight.destroyed do
          destroyed += entry.count
        end
        table.insert(events, { kind = "FleetFightOver", fight = fight.id, where = fight.where, destroyed = destroyed,
          lost = #fight.lost, fled = fight.fled, bounty = fight.bounty, joined = fight.joined, held = ours > 0 })
      end
    end
  end
end

-- The fights on record, the latest first.
function Battles.Log(state: State.State): { State.Fight }
  local found: { State.Fight } = {}
  for index = #state.fleetLog, 1, -1 do
    table.insert(found, state.fleetLog[index])
  end
  return found
end

return Battles
