--!strict
-- Invasions: a force comes out of wormhole space into a charted system
-- and means to stay (the owner's rulings, 2026-11-14: "Invasions", and
-- who invades: "Out of wormhole space"). One of the four kinds of thing
-- going on (Strategic/Happenings).
--
-- Who they are: the Drowned, who live at the fourth and fifth depths
-- (Data/Factions; the owner, 2026-11-16: "we already gave you The
-- Drowned, who are the wormhole depth 4 and 5 alien faction"). Pirates
-- stood in for them until then. They come through a great wormhole
-- from one of their depths.
--
-- One at a time, every several hours, within some jumps of the pilot
-- and never at a homeworld or in a system the pilot's corporation
-- holds. It lasts four hours, in three stages by the clock: a way
-- opens and their van is through; they are landed and dug in; they are
-- at the stations, and every works of every station there stops
-- (Assets/Stations, which asks the list).
--
-- Where the pilot is in the system, it is something to fight. Their
-- lines are a place on the overview, and a great wormhole stands open
-- in the system for as long as they do: the way they came. At their
-- lines a few of them are in space at a time, and as they are destroyed
-- more come up, until there are none left to come: every one destroyed
-- is one fewer of the force. With nobody there, the force is what it
-- was.
--
-- Beaten (none left), the system's keeper pays, thinks the better of
-- the pilot, and order there is a little firmer for a few days. Let be
-- until its time is up, they go as they came: order there is thinner
-- for a few days, and one station's works are out of use for a day
-- after them. Nothing changes hands.
--
-- Every figure is a first proposal, and mine.

local Constants = require("@lt/Core/Data/Constants")
local Citadels = require("@lt/Core/Assets/Citadels")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Happenings = require("@lt/Core/Strategic/Happenings")
local Names = require("@lt/Core/Describe/Names")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Rng = require("@lt/Core/Kernel/Rng")
local Sites = require("@lt/Core/Tactical/Sites")
local Space = require("@lt/Core/Tactical/Space")
local Standings = require("@lt/Core/Assets/Standings")
local State = require("@lt/Core/Kernel/State")
local Structures = require("@lt/Core/Data/Structures")
local Wallet = require("@lt/Core/Assets/Wallet")
local Wormholes = require("@lt/Core/Tactical/Wormholes")

local Invasions = {}

export type Event = { [string]: any }

local HOUR = math.floor(3600 / Constants.TICK + 0.5)

-- Hours until the first of a game, and from the end of one to the next;
-- the hours one lasts, and the hours into it that each later stage
-- begins; how many jumps from the pilot one can be, and how near it is
-- never.
Invasions.FIRST = { 3, 5 }
Invasions.EVERY = { 6, 10 }
Invasions.LASTS = 4
Invasions.STAGES = { 0, 0.75, 2 }
Invasions.REACH = 10
Invasions.NEAR = 1
-- How many ships the force is; how many of them are in space at their
-- lines at once; the seconds between one coming up and the next; and
-- what comes up, in turn.
Invasions.FORCE = 18
Invasions.WAVE = 5
Invasions.REINFORCE = 40
-- (the Drowned's own ships, smaller to bigger: mine)
Invasions.TURN = { "drowned.cairn", "drowned.gravestone", "drowned.cairn", "drowned.casket", "drowned.gravestone", "drowned.keeper" }
-- How far from the middle of their lines they come up, m.
Invasions.OUT = 12000
-- The last of them to come up is whoever leads them: an officer, by
-- name, a captain of this, and what is theirs is in the wreck
-- (Tactical/Pirates' Officer): so many modules, and so many mutators.
Invasions.LEADER = "drowned.coffin"
Invasions.THEIRS = 2
Invasions.MUTATORS = 2
-- What beating one pays, and what the system's keeper thinks of it.
Invasions.REWARD = 400000
Invasions.THANKS = 0.4
-- The hours a station's works are out of use after one that was let be.
Invasions.RUIN = 24

-- The invasion that is on, if one is.
local function current(state: State.State): State.Happening?
  for _, one in state.happenings.list do
    if one.kind == Happenings.INVASION then
      return one
    end
  end
  return nil
end

-- The stage an invasion has got to, by the clock.
function Invasions.Stage(state: State.State, one: State.Happening): number
  local hours = (state.tick - one.began) / HOUR
  return if hours >= Invasions.STAGES[3] then 3 elseif hours >= Invasions.STAGES[2] then 2 else 1
end

-- Begin one, somewhere within reach of 'here'.
local function begin(state: State.State, here: number, rng: Rng.Rng, events: { Event })
  local galaxy = state.galaxy
  local far = Happenings.Reach(state, here, Invasions.REACH)
  local where: { number } = {}
  for id = 1, Galaxy.Charted(galaxy) do
    local node = galaxy.systems[id]
    if far[id] and far[id] >= Invasions.NEAR and not node.home and node.owner ~= "player" then
      table.insert(where, id)
    end
  end
  if #where == 0 then
    return
  end
  local system = where[Rng.Int(rng, #where) + 1]
  Happenings.Begin(state, Happenings.INVASION, "deep", system, 0, Invasions.LASTS * HOUR, Invasions.FORCE, "", events,
    Happenings.Reach(state, here, Happenings.HEARD))
end

-- Whoever of the force is in space at their lines now.
local function fielded(state: State.State, place: number): number
  local alive = 0
  for _, id in state.pilotIds do
    if state.pilots[id].home == place and state.balls[id] then
      alive += 1
    end
  end
  return alive
end

-- An invasion with the pilot in its system: their lines are staked and
-- the way they came stands open, and where the pilot is at their lines
-- they come up to be fought. Returns true when none of them is left.
local function fight(state: State.State, one: State.Happening, me: State.Ball?, events: { Event }): boolean
  local rng = Rng.For(state.historySeed, one.id, state.tick, 1319)
  if one.place == 0 then
    local site = Sites.Stake(state, one.system, Rng.For(state.historySeed, one.id, 1321), "Invaders' Lines")
    if site == nil then
      return false
    end
    one.place = site.id
    -- (the way they came: a great wormhole from one of their depths, found, open as long as they are here)
    local deep: { number } = {}
    for id = Galaxy.Charted(state.galaxy) + 1, #state.galaxy.systems do
      if (state.galaxy.systems[id].depth or 0) > Galaxy.PIRATE_DEPTH then
        table.insert(deep, id)
      end
    end
    if #deep > 0 then
      local hole = Wormholes.Open(state, one.system, deep[Rng.Int(rng, #deep) + 1], rng, events, 3, true)
      if hole then
        hole.closes = one.ends
        local mouth = state.sites[hole.a]
        if mouth then
          mouth.expires = one.ends
        end
      end
    end
  end
  -- Those destroyed since the last look are so many fewer of the force.
  local alive = fielded(state, one.place)
  local lost = (one.ref or 0) - alive
  if lost > 0 then
    one.strength = math.max(0, one.strength - lost)
    one.kills += lost
  end
  one.ref = alive
  if one.strength <= 0 then
    return true
  end
  -- More come up, one at a time, while the pilot is at their lines.
  local place = Space.Object(state, one.place)
  if me and place and me.grid == one.place and alive < math.min(Invasions.WAVE, one.strength)
    and (alive == 0 or state.tick % Invasions.REINFORCE == 0) then
    local sent = Invasions.FORCE - one.strength + alive
    -- (the last of them is their leader, by name)
    local last = one.strength - alive == 1
    local kind = if last then Pirates.Graded(Pirates.kindById[Invasions.LEADER], 2)
      else Pirates.kindById[Invasions.TURN[sent % #Invasions.TURN + 1]]
    local turn = Rng.Float(rng, 0, 2 * math.pi)
    local ball = Pirates.Spawn(state, kind, one.system, place.x + Invasions.OUT * math.cos(turn), place.y + Rng.Float(rng, -1500, 1500),
      place.z + Invasions.OUT * math.sin(turn), one.place)
    if last then
      one.name = Names.Person(Rng.For(state.historySeed, one.id, 1327))
      ball.name = one.name
      state.ships[ball.id].name = one.name
    end
    table.insert(events, { kind = "BallAdded", ball = ball.id })
    one.ref = alive + 1
  end
  return false
end

-- A station of a system that has works, and which of them: for what is
-- left out of use after an invasion nobody answered.
local function ruined(state: State.State, system: number, rng: Rng.Rng): (number, string, string)
  for _, object in Space.Glance(state, system).objects do
    if object.kind == "station" and state.starbases[object.id] == nil then
      local makeup = Structures.Makeup(object.variety, object.radius, state.galaxy.systems[system].nearest, false)
      local works: { Structures.Service } = {}
      for _, service in { "refining", "industry", "research" } :: { Structures.Service } do
        for _, module in makeup.modules do
          if Structures.moduleById[module].service == service and not table.find(works, service) then
            table.insert(works, service)
          end
        end
      end
      if #works > 0 then
        local service = works[Rng.Int(rng, #works) + 1]
        return object.id, service, `The {Structures.Provider(service)} at {object.name}`
      end
    end
  end
  return 0, "", ""
end

-- Once a tick: one that is due begins; the one that is on goes from
-- stage to stage, is fought where the pilot is, and ends, beaten or in
-- its own time, leaving what it leaves. 'here' is the system the pilot
-- is in.
function Invasions.Step(state: State.State, here: number, events: { Event })
  local all = state.happenings
  local one = current(state)
  if one == nil then
    if state.tick >= all.invasionDue and not state.peaceful then
      local rng = Rng.For(state.historySeed, all.count, state.tick, 1317)
      if not state.galaxy.systems[here].uncharted then
        begin(state, here, rng, events)
      end
      if current(state) == nil then
        -- (nowhere for one: asked again in an hour)
        all.invasionDue = state.tick + HOUR
      end
    end
    return
  end
  local stage = Invasions.Stage(state, one)
  if stage ~= one.stage then
    one.stage = stage
    all.version += 1
    table.insert(events, { kind = "HappeningStage", id = one.id, happening = one.kind, system = one.system, stage = stage })
  end
  local beaten = false
  if one.system == here then
    beaten = fight(state, one, state.balls[state.player.ship], events)
  end
  if not beaten and state.tick < one.ends then
    return
  end
  local rng = Rng.For(state.historySeed, one.id, 1323)
  local node = state.galaxy.systems[one.system]
  if one.place ~= 0 and state.sites[one.place] then
    Sites.Release(state, one.place, events)
  end
  all.invasionDue = state.tick + math.floor(Rng.Float(rng, Invasions.EVERY[1], Invasions.EVERY[2]) * HOUR)
  Happenings.End(state, one, if beaten then "beaten" else "over", events)
  if beaten then
    -- (what was their leader's is in what is left of them)
    if one.name ~= "" then
      for index = #state.wreckIds, 1, -1 do
        local wreck = state.wrecks[state.wreckIds[index]]
        if wreck.system == one.system and wreck.name == one.name .. " Wreck" then
          -- (a Drowned leader's wreck has no pirate tower's drawings in it)
          Pirates.Officer(state, wreck.id, one.name, Pirates.Graded(Pirates.kindById[Invasions.LEADER], 2), rng, Invasions.THEIRS,
            Invasions.MUTATORS, "drowned")
          break
        end
      end
    end
    local keeper = if Galaxy.Keeper(node) ~= "" then Galaxy.Keeper(node) else node.nearest
    Wallet.Pay(state, Invasions.REWARD, `the thanks of {node.name}`, events)
    Standings.Change(state, keeper, Invasions.THANKS, events)
    Happenings.Mark(state, one.system, Happenings.MARKS.invasionBeaten, "an invasion beaten")
  else
    Happenings.Mark(state, one.system, Happenings.MARKS.invasion, "an invasion")
    local station, service, name = ruined(state, one.system, rng)
    if station ~= 0 then
      Happenings.Begin(state, Happenings.DISASTER, service, one.system, station, Invasions.RUIN * HOUR, 1, name, events,
        Happenings.Reach(state, here, Happenings.HEARD))
    end
    -- (and one of the factions' citadels there is brought down: its hulk
    -- is what they leave of it, Assets/Citadels. Mine.)
    Citadels.Fall(state, one.system, events, true)
  end
end

return Invasions
