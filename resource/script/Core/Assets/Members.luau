--!strict
-- Members: pilots who join the corporation, and do as they see fit.
--
-- The project owner's (2026-11-14): "NPCs who join the player corp,
-- with their own behavior and goals, but who contribute to the org
-- defense, mining, etc." And their rulings on it:
--
--   - They come both ways: pilots apply to a corporation by themselves,
--     more of them the more it has to offer, and the pilot can invite
--     one who is open to it at a station.
--   - A member flies a ship of their own, keeps what they earn, and pays
--     a share of it to the corporation at a rate the pilot sets. Set
--     over what a member will bear, they leave. Nobody is paid a wage.
--   - The pilot's say is calls and not orders: a call is posted for a
--     system (defend it, mine there, haul there, scout it), with a
--     reward a day if the pilot likes, and each member answers the ones
--     that suit their trade and pay better than what they would be
--     doing. Nobody is commanded. (A hired pilot is another thing, and
--     is: Tactical/Fleet.)
--   - What drives a member, for now, is a trade of their own and getting
--     rich: each is a miner, a fighter, a hauler or a scout, works at
--     that where it pays best, puts what they earn into a better hull,
--     and drifts away if the pickings stay thin.
--
-- How it is worked out (first figures, all of them). A member works by
-- the hour in one of the systems the corporation has a place in: where
-- the pilot's home is, where a tower of theirs stands, and what they
-- hold. What they do is done to the galaxy wherever the pilot is; and
-- where the pilot is, they are there to be seen at it, each in their
-- own ship (Tactical/Fellows).
--
--   - A miner digs the ore that goes for most there, and sells it to the
--     system: it is in the system's stock, in the economy.
--   - A hauler buys what is cheapest there against a system a jump or
--     two off and sells it where it is dearer: the goods are moved, in
--     the economy, and what they make is the difference.
--   - A fighter hunts where it is least safe, and is paid what is on
--     the heads they bring in: pirates come less often where one is,
--     and a system of the pilot's that is besieged has each fighter
--     member there in its defence.
--   - A scout works the signals: a site in a system they are in is
--     found, one an hour, and is on the overview when the pilot comes.
--
-- Once a day each member looks at where they would do best, calls
-- counted, and goes there; buys the next hull of their trade if they
-- have the price of it and a fifth over; and thinks about leaving.
--
-- A member is a person (the owner, 2026-11-21: "right now they feel like
-- they are just numbers in the background, not actual corp members";
-- docs/design/members.md, phase 1). Each lives at a station (their home,
-- where their clone is), owns the hulls they have bought, and is as good
-- as their grade (1 to 5, rising with the hours they work at their
-- trade: it decides what they can fly and adds to what they bring in),
-- or, one of the player's own characters, their skills. Each wants
-- something (to fly the best hull of their trade, a fortune, to bring in
-- the most of anybody of it), grows attached to the corporation as days
-- go by and pay comes, and may be given a title. What a miner digs and
-- what a fighter salvages and loots is put in the corporation's hangar
-- (the owner's: "what they mine, salvage, or loot is deposited in the
-- corp hangar"), at the corporation's station where they work, and the
-- one who brought it is paid a share of what it is worth there (the
-- owner's "a share per haul", which the pilot sets), from the
-- corporation's account; a hauler's trade and a scout's are paid and
-- taxed as before, and so is a fighter's bounty. What the corporation
-- cannot pay it owes, and a member it still owes at the end of a day
-- leaves (the owner's). The player's own characters are paid nothing:
-- what they bring in, and what they earn, is all the corporation's.
-- What happens is kept in the corporation's activity log.
--
-- A ship of theirs that is destroyed is their loss, and nobody else's:
-- they are out of work for a while finding another, and what they fly
-- next is the best of their trade they have the price of, no better
-- than the one that went (the first of it, whatever they have). One
-- whose ship the pilot's own side destroys is a member no longer.

local Commerce = require("@lt/Core/Strategic/Commerce")
local Constants = require("@lt/Core/Data/Constants")
local Corporation = require("@lt/Core/Assets/Corporation")
local Economy = require("@lt/Core/Strategic/Economy")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Items = require("@lt/Core/Assets/Items")
local Names = require("@lt/Core/Describe/Names")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local Skills = require("@lt/Core/Data/Skills")
local Space = require("@lt/Core/Tactical/Space")
local State = require("@lt/Core/Kernel/State")
local Types = require("@lt/Core/Data/Types")
local Wars = require("@lt/Core/Strategic/Wars")

local Members = {}

export type Event = { [string]: any }

Members.HOUR = math.ceil(3600 / Constants.TICK)
Members.DAY = 24 * Members.HOUR
-- The trades, and the hulls of each, from the one a member comes in to
-- the best they buy: by class (a member's hull is their own people's of
-- the class, where their people build one).
Members.TRADES = { "miner", "fighter", "hauler", "scout" }
local LADDER: { [string]: { string } } = {
  miner = { "frigate", "barge" },
  fighter = { "frigate", "destroyer", "cruiser", "battlecruiser", "battleship" },
  hauler = { "industrial", "freighter" },
  scout = { "frigate", "destroyer" },
}
-- What a member earns in an hour at their trade, by the class they fly,
-- where nothing makes it more or less.
Members.EARNS = {
  miner = { frigate = 18000, barge = 60000 },
  fighter = { frigate = 14000, destroyer = 24000, cruiser = 45000, battlecruiser = 70000, battleship = 110000 },
  hauler = { industrial = 22000, freighter = 80000 },
  scout = { frigate = 16000, destroyer = 26000 },
} :: { [string]: { [string]: number } }
-- The tax the corporation takes when nothing is said, and the most it
-- can be set to; and what a member will bear, the least and the most.
Members.TAX, Members.TAX_MOST = 0.1, 0.5
Members.BEARS = { 0.08, 0.3 }
-- How many members a corporation has room for: so many, and so many
-- more for each system it holds and each tower it keeps (the owner,
-- 2026-11-21: "20 base + 20*5 = 120 max corp members" by Hospitality,
-- and held systems and towers "still add", with no cap).
Members.ROOM, Members.ROOM_SYSTEM, Members.ROOM_TOWER = 20, 3, 2
-- An NPC member's grade (the owner, 2026-11-21: "1-5"): the hours of
-- work at their trade it takes to reach each, how much more each grade
-- over the first brings in, and the least grade that flies each class.
-- (Figures mine.)
Members.GRADE_HOURS = { 0, 150, 400, 900, 2000 }
Members.GRADE_EARNS = 0.1
Members.CLASS_GRADE = { frigate = 1, destroyer = 1, industrial = 1, capsule = 1, cruiser = 2, barge = 2, attackbattlecruiser = 3,
  battlecruiser = 3, freighter = 3, battleship = 4, carrier = 5, dreadnought = 5, siegedreadnought = 5, capitalindustrial = 5,
  supercarrier = 5, ultracapital = 5 } :: { [string]: number }
-- The share of what a delivery is worth that its member is paid, when
-- nothing is said ("your rec", the owner: 60%).
Members.SHARE = 0.6
-- How much of what a fighter brings in is the heads they collect (their
-- own, taxed), the rest being salvage and loot for the hangar. (Mine.)
Members.BOUNTY = 0.5
-- What a member wants, and how often each: the best hull of their trade,
-- a fortune of so much, or to bring in the most of anybody of their
-- trade (at the least so much). (Mine.)
Members.AIMS = { hull = 0.45, fortune = 0.35, best = 0.2 }
Members.FORTUNES = { 25000000, 60000000, 150000000 }
Members.BEST_LEAST = 5000000
-- Attachment to the corporation (the owner's "loyalty"): where one who
-- joins starts, what a day of being paid in full adds and a day owed
-- takes away; and what it does at its most: so much more tax they will
-- bear, and so many more thin days before they go. (Mine.)
Members.LOYALTY_START, Members.LOYALTY_DAY, Members.LOYALTY_OWED = 0.1, 0.02, 0.15
Members.LOYALTY_BEARS, Members.LOYALTY_DAYS = 0.1, 4
-- The most lines the activity log keeps.
Members.LOG_MOST = 200
-- Applicants: the chance of one on a day (with what each system held
-- and each tower adds, and the most it comes to); how many wait at
-- once; and how many days one waits.
Members.APPLY, Members.APPLY_SYSTEM, Members.APPLY_TOWER, Members.APPLY_MOST = 0.25, 0.1, 0.05, 0.9
Members.WAITING, Members.WAITS = 4, 3
-- How many pilots at a station are open to joining, on a day.
Members.OPEN = 2
-- A member leaves after so many days running of earning under this
-- share of what their hull would earn them anywhere; and a member
-- goes to another system only for this much more than they have.
Members.LEAN_DAYS, Members.LEAN = 3, 0.5
Members.BETTER = 1.1
-- What a fighter member in a system of the pilot's adds to its defence
-- when it is besieged, for a frigate (and as much again for each class
-- over); and how many times as long pirates leave a place alone for
-- each fighter member in the system.
Members.STANDS = 15
Members.WATCH = 0.5
-- How long a member who has lost a ship is out of work, finding another.
Members.REFIT = 2 * Members.HOUR
-- A call: the kinds there are, and the trade each is for.
Members.CALLS = { defend = "fighter", mine = "miner", haul = "hauler", scout = "scout" } :: { [string]: string }
Members.CALLS_MOST = 6
-- What the pilot's skills add (the owner, 2026-11-16, of the skills for structures and the corporation I put to them: "Yes to all your recs"): room for so many more members a
-- level of Hospitality, applications so much likelier a level of
-- Renown, and one more call posted at once a level of Muster.
Members.HOSPITALITY, Members.RENOWN = 20, 0.1
function Members.Calls(state: State.State): number
  return Members.CALLS_MOST + math.max(0, state.skills.muster or 0)
end

-- A member's own people: the faction whose space the pilot's home is in
-- (they are of the corporation's neighbourhood), or nobody's.
local function people(state: State.State): string
  local home = state.galaxy.systems[Space.SystemOf(state, state.player.home)]
  return if home then home.nearest else ""
end

-- The hull of a class a people build (the plain one), or the hull of
-- that class that is nobody's.
local function hullOf(faction: string, class: string): string?
  local plain: string? = nil
  for _, hull in Ships.list do
    if hull.class == class and hull.tech ~= 2 then
      if hull.lineage == faction then
        return hull.id
      elseif hull.lineage == "" then
        plain = plain or hull.id
      end
    end
  end
  return plain
end

-- The hull of a class somebody of a trade flies: their people's. (A
-- miner's frigate was the Prospector, anybody's, until the hulls nobody's
-- yards built were taken out of the game, 2026-11-18: Data/Ships.)
local function hullFor(_trade: string, faction: string, class: string): string?
  return hullOf(faction, class)
end
Members.HullFor = hullFor

-- The systems the corporation has a place in: where the pilot's home
-- is, where a tower of theirs stands, and what they hold. In the order
-- of their ids.
function Members.Places(state: State.State): { number }
  local has: { [number]: boolean } = {}
  local home = Space.SystemOf(state, state.player.home)
  if state.galaxy.systems[home] and not state.galaxy.systems[home].uncharted then
    has[home] = true
  end
  for _, id in state.starbaseIds do
    if state.starbases[id].owner == Wars.PILOT then
      local system = Space.SystemOf(state, id)
      if state.galaxy.systems[system] and not state.galaxy.systems[system].uncharted then
        has[system] = true
      end
    end
  end
  local found: { number } = {}
  for id = 1, Galaxy.Charted(state.galaxy) do
    if has[id] or state.galaxy.systems[id].owner == Wars.PILOT then
      table.insert(found, id)
    end
  end
  return found
end

-- How many members the corporation has room for.
function Members.Room(state: State.State): number
  if not Corporation.Founded(state) then
    return 0
  end
  local held, towers = 0, 0
  for id = 1, Galaxy.Charted(state.galaxy) do
    held += if state.galaxy.systems[id].owner == Wars.PILOT then 1 else 0
  end
  for _, id in state.starbaseIds do
    towers += if state.starbases[id].owner == Wars.PILOT then 1 else 0
  end
  -- (and so many more a level of the pilot's Hospitality)
  local more = Members.HOSPITALITY * math.max(0, state.skills.hospitality or 0)
  return Members.ROOM + Members.ROOM_SYSTEM * held + Members.ROOM_TOWER * towers + more
end

-- A line in the corporation's activity log, about a member (or nobody).
function Members.Note(state: State.State, member: State.Member?, text: string)
  local log = state.membership.log
  table.insert(log, { tick = state.tick, member = if member then member.id else 0, name = if member then member.name else "", text = text })
  while #log > Members.LOG_MOST do
    table.remove(log, 1)
  end
end

-- A member of before 2026-11-21 (a save's, or one made by hand), made a
-- person: what they did not have, as one would who has been in the
-- corporation a while (a grade as good as their hull needs, at home at
-- the pilot's home, the hull they fly theirs). What they want is rolled
-- on their next day. The member, for whoever made it.
function Members.Fill(state: State.State, member: any): State.Member
  local info = Ships.byId[member.hull or ""]
  local grade = if member.alt then 0 else (if info then Members.CLASS_GRADE[info.class] or 1 else 1)
  member.home = member.home or state.player.home
  member.clone = member.clone or member.home
  member.grade = member.grade or grade
  member.practice = member.practice or (Members.GRADE_HOURS[member.grade] or 0)
  member.ships = member.ships or { member.hull }
  member.implants = member.implants or {}
  member.loyalty = member.loyalty or (if member.alt then 1 else 0.3)
  member.title = member.title or ""
  member.owed = member.owed or 0
  member.budget = member.budget or 0
  member.delivered = member.delivered or 0
  member.shares = member.shares or 0
  member.dayGoods = member.dayGoods or 0
  member.dayShare = member.dayShare or 0
  return member :: State.Member
end

-- The grade an NPC member has reached for so many hours worked.
function Members.GradeFor(hours: number): number
  local grade = 1
  for at, needs in Members.GRADE_HOURS do
    if hours >= needs then
      grade = at
    end
  end
  return grade
end

-- The station a member working in a system puts what they bring in at:
-- a station of the pilot's there (a citadel or a tower), or the pilot's
-- home.
function Members.DepositAt(state: State.State, system: number): number
  for _, id in state.starbaseIds do
    if state.starbases[id].owner == Wars.PILOT and Space.SystemOf(state, id) == system then
      return id
    end
  end
  return state.player.home
end

-- The members there are, in the order they joined.
function Members.List(state: State.State): { State.Member }
  local found: { State.Member } = {}
  for _, id in state.membership.memberIds do
    table.insert(found, state.membership.members[id])
  end
  return found
end

-- What a member who fights adds to the defence of a system of the
-- pilot's: so much for a frigate, and as much again for each class of
-- hull over. Nothing, for a member of another trade.
function Members.Stands(member: State.Member): number
  if member.trade ~= "fighter" then
    return 0
  end
  local hull = Ships.byId[member.hull]
  return Members.STANDS * (if hull then table.find(LADDER.fighter, hull.class) or 1 else 1)
end

-- How many fighter members are working in a system (for whoever asks
-- how well it is watched: Tactical/Pirates), and what they add to its
-- defence (Assets/Sovereignty).
function Members.Watching(state: State.State, system: number): (number, number)
  local count, stands = 0, 0
  for _, id in state.membership.memberIds do
    local member = state.membership.members[id]
    -- (not one who has lost their ship, and has not another yet)
    if member.trade == "fighter" and member.system == system and state.tick >= member.refit then
      count += 1
      stands += Members.Stands(member)
    end
  end
  return count, stands
end

-- The member whose ship a ship is, if it is one's.
function Members.Of(state: State.State, ship: number): State.Member?
  if ship == 0 then
    return nil
  end
  for _, id in state.membership.memberIds do
    if state.membership.members[id].ship == ship then
      return state.membership.members[id]
    end
  end
  return nil
end

-- A member's ship is taken out of space, or out of the station it is
-- in: it is not destroyed, they have gone in, or on, or the pilot is no
-- longer there to see it ('reason' and 'gate': for the view, as for a
-- ship of the traffic). What a hauler's had aboard of the economy's is
-- where it was for.
function Members.Recall(state: State.State, member: State.Member, events: { Event }, reason: string?, gate: number?)
  local id = member.ship
  member.ship = 0
  if member.carries then
    Commerce.Deliver(state.commerce, member.carries.node, member.carries.class, member.carries.amount)
    member.carries = nil
  end
  if id == 0 then
    return
  end
  local ball = state.balls[id]
  if ball then
    Space.RemoveBall(state, ball)
    table.insert(events, { kind = "BallRemoved", ball = id, reason = reason or "left", gate = gate })
  end
  for _, item in Items.In(state, id, nil) do
    Items.Take(state, item, item.quantity)
  end
  if state.ships[id] then
    state.ships[id] = nil
    State.RemoveId(state.shipIds, id)
  end
  if state.pilots[id] then
    state.pilots[id] = nil
    State.RemoveId(state.pilotIds, id)
  end
end

-- The skill each trade is the better at for: a twentieth more for each
-- level of it, for one of the player's own characters (who has skills
-- to speak of: 2026-11-17; which skill, and how much, mine).
Members.ALT_SKILL = { miner = "mining", fighter = "rapid.firing", hauler = "industrials", scout = "astrometrics" } :: { [string]: string }
Members.ALT_BY = 0.05

-- What a member's hull earns an hour at their trade, anywhere.
local function base(member: State.Member): number
  local hull = Ships.byId[member.hull]
  local earns = Members.EARNS[member.trade]
  local skills = member.skills
  local skilled = if skills then 1 + Members.ALT_BY * math.max(0, skills[Members.ALT_SKILL[member.trade] or ""] or 0)
    else 1 + Members.GRADE_EARNS * math.max(0, (member.grade or 1) - 1)
  return if hull and earns then (earns[hull.class] or 0) * skilled else 0
end

-- Whether a member can fly a hull: an NPC member of a grade high enough
-- for its class, one of the player's own characters with the skills for
-- it.
local function canFly(member: State.Member, hull: string): boolean
  local skills = member.skills
  if skills then
    return Skills.Missing(Skills.Needs(hull), skills) == nil
  end
  local info = Ships.byId[hull]
  return info ~= nil and (member.grade or 1) >= (Members.CLASS_GRADE[info.class] or 5)
end
Members.CanFly = canFly

-- The ore that goes for most in a system, of those every belt has: its
-- class in the economy, and what it goes for as a share of normal.
local ORES = { "ore.ferrite", "ore.silicate", "ore.cuprite", "ore.titanite" }
local function bestOre(state: State.State, system: number): (number, number, string)
  local best, most, type = 0, 0, ORES[1]
  for _, ore in ORES do
    local class = Commerce.Index(ore)
    local level = Commerce.Level(state.commerce, system, ore)
    if class and level > most then
      best, most, type = class, level, ore
    end
  end
  return best, most, type
end
-- What a fighter salvages from what they destroy.
local SALVAGE = { "salvage.plates", "salvage.circuits", "salvage.conduits" }

-- The best a hauler could do from a system: the goods and the system a
-- jump or two off where they go for most over what they go for here,
-- beyond what the carrying costs. The class, where to, and the gap as a
-- share of the normal price (0: nothing pays).
local function bestHaul(state: State.State, system: number): (number, number, number)
  local commerce = state.commerce
  local near: { number } = {}
  for _, neighbor in state.galaxy.systems[system].neighbors do
    if commerce.nodes[neighbor] then
      table.insert(near, neighbor)
      for _, further in state.galaxy.systems[neighbor].neighbors do
        if commerce.nodes[further] and further ~= system and not table.find(near, further) then
          table.insert(near, further)
        end
      end
    end
  end
  local best, to, most = 0, 0, 0
  if commerce.nodes[system] == nil then
    return 0, 0, 0
  end
  for class = 1, #commerce.classes do
    local here = Economy.Price(commerce, system, class) / commerce.classes[class].par
    for _, other in near do
      local gap = Economy.Price(commerce, other, class) / commerce.classes[class].par - here - 2 * Commerce.COST_JUMP
      if gap > most then
        best, to, most = class, other, gap
      end
    end
  end
  return best, to, most
end
-- (for whoever puts a hauler's ship in space: Tactical/Fellows)
Members.Haul = bestHaul

-- What a member would earn in an hour in a system, at their trade, as
-- things are there now (before any tax, and before any call's reward).
function Members.Prospect(state: State.State, member: State.Member, system: number): number
  local node = state.galaxy.systems[system]
  local plain = base(member)
  if node == nil or plain <= 0 then
    return 0
  elseif member.trade == "miner" then
    local _, level = bestOre(state, system)
    return plain * level
  elseif member.trade == "hauler" then
    local _, _, gap = bestHaul(state, system)
    -- (a hold turned over in an hour makes the gap on what it carries: against a gap of a tenth for the plain figure)
    return plain * math.min(3, gap / 0.1)
  elseif member.trade == "fighter" then
    return plain * (1.5 - node.security)
  end
  -- (a scout: more where there is more nobody has found)
  local unfound = 0
  for _, id in state.siteIds do
    local site = state.sites[id]
    unfound += if site.system == system and not site.gone and site.strength < 1 and site.kind ~= "mission" then 1 else 0
  end
  return plain * (1 + 0.15 * math.min(4, unfound))
end

-- The call a member is answering, if it still stands.
local function callOf(state: State.State, member: State.Member): State.Call?
  for _, call in state.membership.calls do
    if call.id == member.call then
      return call
    end
  end
  return nil
end

-- Where a member would do best, of the corporation's places: what they
-- would earn there in an hour, with what a call for their trade pays.
-- The system, the call answered there (0 for none), and the figure.
local function choose(state: State.State, member: State.Member, places: { number }): (number, number, number)
  local best, answered, most = 0, 0, -1
  for _, system in places do
    local worth = Members.Prospect(state, member, system) * (1 - state.membership.tax)
    local call = 0
    for _, posted in state.membership.calls do
      if posted.system == system and Members.CALLS[posted.kind] == member.trade then
        -- (a call with no reward is still a call: a member would as soon go where they are asked)
        worth = worth * 1.05 + posted.reward / 24
        call = posted.id
      end
    end
    if worth > most then
      best, answered, most = system, call, worth
    end
  end
  return best, answered, most
end

-- A member's hour: what their trade does to the galaxy, what it earns
-- them, and what of that is the corporation's.
local function work(state: State.State, member: State.Member, events: { Event })
  local system = member.system
  local commerce = state.commerce
  -- (one who has lost their ship earns nothing until they have another)
  if state.tick < member.refit then
    member.doing = "refitting"
    return
  end
  local earned = Members.Prospect(state, member, system)
  if earned <= 0 then
    member.doing = "idle"
    return
  end
  -- (an hour more at their trade, toward the next grade)
  member.practice += 1
  if member.alt == nil then
    local grade = Members.GradeFor(member.practice)
    if grade > member.grade then
      member.grade = grade
      Members.Note(state, member, `is now grade {grade}`)
      table.insert(events, { kind = "MemberGraded", member = member.id, name = member.name, grade = grade })
    end
  end
  -- What is brought in as goods goes into the corporation's hangar: so
  -- many units, at what each goes for there; and its member is paid
  -- their share of that.
  local function deposit(type: string, worth: number, level: number)
    local each = Types.Info(type).basePrice * math.max(0.05, level)
    local units = math.max(1, math.floor(worth / each + 0.5))
    Items.Add(state, type, units, Members.DepositAt(state, system), "corporate")
    local value = math.floor(units * each)
    member.delivered += value
    member.dayGoods += value
    if member.alt then
      return
    end
    local pay = math.floor(value * state.membership.share)
    if pay <= 0 then
      return
    elseif Corporation.Afford(state, pay) then
      Corporation.Spend(state, pay, "members' shares", events)
      member.wealth += pay
      member.shares += pay
      member.dayShare += pay
      member.day += pay
    else
      member.owed += pay
    end
  end
  if member.trade == "miner" then
    local _, level, ore = bestOre(state, system)
    deposit(ore, earned, level)
    member.doing = "mining"
    return
  elseif member.trade == "hauler" then
    local class, to, gap = bestHaul(state, system)
    if class ~= 0 and gap > 0 then
      local par = commerce.classes[class].par
      local units = Economy.Draw(commerce, system, class, earned / (par * gap))
      Economy.Give(commerce, to, class, units)
      earned = units * par * gap
    end
    member.doing = "hauling"
  elseif member.trade == "fighter" then
    member.doing = if callOf(state, member) then "defending" else "hunting"
    -- (half of it salvage and loot, for the hangar: one kind an hour, by the hour; the rest the heads they bring in)
    local salvage = SALVAGE[(state.tick // Members.HOUR + member.id) % #SALVAGE + 1]
    deposit(salvage, earned * (1 - Members.BOUNTY), 1)
    earned *= Members.BOUNTY
  else
    -- (one signal there, found: the lowest-numbered that is not)
    for _, id in state.siteIds do
      local site = state.sites[id]
      if site.system == system and not site.gone and site.strength < 1 and site.kind ~= "mission" then
        site.strength = 1
        table.insert(events, { kind = "MemberFound", member = member.id, name = member.name, site = id, system = system })
        break
      end
    end
    member.doing = "scouting"
  end
  -- (what is earned as money: the tax is the corporation's; and all of
  -- it, for one of the player's own characters)
  local due = if member.alt then math.floor(earned) else math.floor(earned * state.membership.tax)
  member.wealth += math.floor(earned) - due
  member.earned += math.floor(earned)
  member.paid += due
  member.day += math.floor(earned) - due
  if due > 0 then
    Corporation.Earn(state, due, if member.alt then "members' earnings" else "members' tax", events)
  end
end

-- A member is gone from the corporation.
local LEFT_WHY: { [string]: string } = { ["the tax"] = "left over the tax", ["thin pickings"] = "left: the pickings were thin",
  expelled = "was expelled", ["fired on by their own"] = "left after their own side fired on them",
  ["pay owed"] = "left: the corporation owed them pay it could not find" }
local function leave(state: State.State, member: State.Member, why: string, events: { Event })
  Members.Note(state, member, LEFT_WHY[why] or `left: {why}`)
  Members.Recall(state, member, events)
  state.membership.members[member.id] = nil
  State.RemoveId(state.membership.memberIds, member.id)
  table.insert(events, { kind = "MemberLeft", member = member.id, name = member.name, trade = member.trade, why = why })
end

-- A member's ship has been destroyed ('by': the ship that did it). It
-- is their loss: they are out of work while they find another, which is
-- the best of their trade they have the price of, no better than the
-- one that went; and the first of it, whatever they have. (What a
-- hauler's had aboard is in its wreck, or nowhere.) One whose ship the
-- pilot's own side destroyed leaves.
function Members.Lost(state: State.State, member: State.Member, by: number, events: { Event })
  local was = member.hull
  member.ship, member.task, member.carries = 0, "", nil
  member.lost += 1
  local killer = state.ships[by]
  if by == state.player.ship or (killer ~= nil and killer.owner == "player") then
    table.insert(events, { kind = "MemberLost", member = member.id, name = member.name, trade = member.trade, was = was, hull = "",
      system = member.system, lost = member.lost })
    leave(state, member, "fired on by their own", events)
    return
  end
  local ladder = LADDER[member.trade]
  local hull = Ships.byId[was]
  local rung = if hull then table.find(ladder, hull.class) or 1 else 1
  -- (the hull that went is theirs no longer)
  local at = table.find(member.ships, was)
  if at then
    table.remove(member.ships, at)
  end
  for step = rung, 1, -1 do
    local next = hullFor(member.trade, member.people, ladder[step])
    if next and (step == 1 or member.wealth >= Types.Info(next).basePrice) then
      member.wealth = math.max(0, member.wealth - Types.Info(next).basePrice)
      member.hull = next
      break
    end
  end
  if not table.find(member.ships, member.hull) then
    table.insert(member.ships, member.hull)
  end
  Members.Note(state, member, `lost their {Types.Info(was).name}` .. (if member.hull ~= was then `, and flies a {Types.Info(member.hull).name} now`
    else ", and bought another"))
  member.refit = state.tick + Members.REFIT
  member.doing = "refitting"
  table.insert(events, { kind = "MemberLost", member = member.id, name = member.name, trade = member.trade, was = was, hull = member.hull,
    system = member.system, lost = member.lost })
end

-- What a member wants, rolled: the best hull of their trade (their
-- people's of the top class of it), a fortune, or to bring in the most
-- of anybody of their trade. Nil for one of the player's own characters.
local function rollAim(state: State.State, member: State.Member, rng: Rng.Rng): State.MemberAim?
  if member.alt then
    return nil
  end
  local roll = Rng.Float(rng, 0, 1)
  local ladder = LADDER[member.trade]
  local top = hullFor(member.trade, member.people, ladder[#ladder]) or member.hull
  if roll < Members.AIMS.hull and top ~= member.hull then
    return { kind = "hull", hull = top, wealth = 0 }
  elseif roll < Members.AIMS.hull + Members.AIMS.fortune then
    local fortune = Members.FORTUNES[Rng.Int(rng, #Members.FORTUNES) + 1]
    -- (a fortune more than they have)
    while fortune <= member.wealth do
      fortune *= 2
    end
    return { kind = "fortune", hull = "", wealth = fortune }
  end
  return { kind = "best", hull = "", wealth = 0 }
end

-- How far a member is toward what they want, 0 to 1, and it said.
function Members.AimProgress(state: State.State, member: State.Member): (number, string)
  local aim = member.aim
  if aim == nil then
    return 0, ""
  elseif aim.kind == "hull" then
    local ladder = LADDER[member.trade]
    local want, have = Ships.byId[aim.hull], Ships.byId[member.hull]
    local wantAt = if want then table.find(ladder, want.class) or #ladder else #ladder
    local haveAt = if have then table.find(ladder, have.class) or 1 else 1
    return math.clamp((haveAt - 1) / math.max(1, wantAt - 1), 0, 1),
      `to fly a {if want then want.name else aim.hull}`
  elseif aim.kind == "fortune" then
    return math.clamp(member.wealth / math.max(1, aim.wealth), 0, 1), `a fortune of {aim.wealth // 1000000} million`
  end
  -- (the most brought in by anybody of their trade)
  local most = Members.BEST_LEAST
  for _, id in state.membership.memberIds do
    local other = state.membership.members[id]
    if other.id ~= member.id and other.trade == member.trade then
      most = math.max(most, other.delivered + other.earned)
    end
  end
  return math.clamp((member.delivered + member.earned) / most, 0, 1), `to be the best {member.trade} in the corporation`
end

-- A member's day: what a call pays them, whether they stay, a better
-- hull if they have the price of it, and where they will work tomorrow.
local function reckon(state: State.State, member: State.Member, places: { number }, events: { Event })
  local membership = state.membership
  -- What the corporation owes them, paid if it can be; one it still owes
  -- leaves (the owner's, 2026-11-21: "members (non-character) leave").
  if member.owed > 0 and Corporation.Afford(state, member.owed) then
    Corporation.Spend(state, member.owed, "members' shares", events)
    member.wealth += member.owed
    member.shares += member.owed
    member.dayShare += member.owed
    member.owed = 0
  end
  if member.owed > 0 and member.alt == nil then
    leave(state, member, "pay owed", events)
    return
  end
  -- (what they brought in today, in the log)
  if member.dayGoods > 0 then
    Members.Note(state, member, if member.alt then `brought in goods worth {member.dayGoods // 1000}k`
      else `brought in goods worth {member.dayGoods // 1000}k, paid {member.dayShare // 1000}k`)
  end
  member.dayGoods, member.dayShare = 0, 0
  -- (a day in the corporation, paid as they should be: a little more attached to it)
  member.loyalty = math.clamp(member.loyalty + Members.LOYALTY_DAY, 0, 1)
  local call = callOf(state, member)
  if call and call.reward > 0 then
    if Corporation.Afford(state, call.reward) then
      Corporation.Spend(state, call.reward, "call", events)
      member.wealth += call.reward
      member.day += call.reward
    else
      -- (a call the corporation cannot pay for is nobody's to answer)
      member.call = 0
    end
  end
  -- (one of the player's own characters stays, whatever the tax and the pickings)
  if membership.tax > member.bears + Members.LOYALTY_BEARS * member.loyalty + 1e-9 and member.alt == nil then
    leave(state, member, "the tax", events)
    return
  end
  member.lean = if member.day < Members.LEAN * base(member) * 24 * (1 - member.bears) then member.lean + 1 else 0
  member.day = 0
  local patience = Members.LEAN_DAYS + math.floor(Members.LOYALTY_DAYS * member.loyalty)
  if (member.lean >= patience and member.alt == nil) or #places == 0 then
    leave(state, member, "thin pickings", events)
    return
  end
  -- (the next hull of their trade, with a fifth over to fit it out)
  local hull = Ships.byId[member.hull]
  local ladder = LADDER[member.trade]
  local rung = if hull then table.find(ladder, hull.class) or #ladder else #ladder
  local next = if rung < #ladder then hullFor(member.trade, member.people, ladder[rung + 1]) else nil
  -- (one who is set on a fortune is slower to spend it on a hull)
  local spare = if member.aim ~= nil and member.aim.kind == "fortune" then 2 else 1.2
  if next and member.wealth >= spare * Types.Info(next).basePrice and canFly(member, next) then
    member.wealth -= Types.Info(next).basePrice
    member.hull = next
    if not table.find(member.ships, next) then
      table.insert(member.ships, next)
    end
    -- (the ship they were out in is gone in, for the new one)
    Members.Recall(state, member, events)
    member.task = ""
    Members.Note(state, member, `bought a {Types.Info(next).name}`)
    table.insert(events, { kind = "MemberUpgraded", member = member.id, name = member.name, hull = next })
  end
  -- (and what they want, had: said, and something else wanted; one of
  -- before who wanted nothing in particular, now something)
  if member.aim == nil and member.alt == nil then
    member.aim = rollAim(state, member, Rng.For(state.historySeed, member.id, 157))
  end
  local progress, said = Members.AimProgress(state, member)
  if member.aim and progress >= 1 then
    Members.Note(state, member, `has what they wanted: {said}`)
    table.insert(events, { kind = "MemberAimed", member = member.id, name = member.name, aim = said })
    member.aim = rollAim(state, member, Rng.For(state.historySeed, member.id, state.tick, 157))
  end
  local best, answered, worth = choose(state, member, places)
  local here = if table.find(places, member.system) then Members.Prospect(state, member, member.system) * (1 - membership.tax) else -1
  if best ~= 0 and (best ~= member.system and worth > here * Members.BETTER or answered ~= member.call) then
    if answered ~= 0 and answered ~= member.call then
      table.insert(events, { kind = "CallAnswered", member = member.id, name = member.name, call = answered, system = best })
    end
    member.system, member.call = best, answered
  end
end

-- Somebody who would join: their name, trade, hull and what tax they
-- will bear, from a roll.
local function candidate(state: State.State, rng: Rng.Rng, key: string, waits: number): State.Applicant
  local trade = Members.TRADES[Rng.Int(rng, #Members.TRADES) + 1]
  local ladder = LADDER[trade]
  -- (one in four comes in a hull a rung up: somebody who has been at it a while)
  local rung = if #ladder > 1 and Rng.Chance(rng, 0.25) then 2 else 1
  local faction = people(state)
  local hull = hullFor(trade, faction, ladder[rung]) or hullFor(trade, "", ladder[1]) or "frigate.courier"
  -- (as good as the hull they come in needs, and, one in five, a grade better)
  local info = Ships.byId[hull]
  local grade = math.min(5, (if info then Members.CLASS_GRADE[info.class] or 1 else 1) + (if Rng.Chance(rng, 0.2) then 1 else 0))
  return { key = key, name = Names.Person(rng), trade = trade, people = faction, hull = hull,
    bears = math.floor(Rng.Float(rng, Members.BEARS[1], Members.BEARS[2]) * 100 + 0.5) / 100, until_ = waits, grade = grade }
end

-- The pilots at a station who are open to joining, today. (Nobody, with
-- no corporation to join; and not one who has been asked today.)
function Members.Open(state: State.State, station: number): { State.Applicant }
  local object = Space.Object(state, station)
  local found: { State.Applicant } = {}
  if object == nil or object.kind ~= "station" or state.starbases[station] or not Corporation.Founded(state) then
    return found
  end
  local day = state.tick // Members.DAY
  for slot = 1, Members.OPEN do
    local key = `{station}:{day}:m{slot}`
    if not (state.membership.invitedDay == day and table.find(state.membership.invited, key)) then
      table.insert(found, candidate(state, Rng.For(state.historySeed, station, day, slot, 151), key, (day + 1) * Members.DAY))
    end
  end
  return found
end

local function join(state: State.State, applicant: State.Applicant, events: { Event }): State.Member
  local places = Members.Places(state)
  local grade = applicant.grade or 1
  local member: State.Member = { id = State.NewId(state), name = applicant.name, trade = applicant.trade, people = applicant.people,
    hull = applicant.hull, bears = applicant.bears, wealth = 0, earned = 0, paid = 0, joined = state.tick,
    system = places[1] or Space.SystemOf(state, state.player.home), doing = "idle", call = 0, lean = 0, day = 0,
    ship = 0, task = "", goal = 0, since = 0, wait = 0, back = 0, refit = 0, lost = 0,
    home = state.player.home, clone = state.player.home, grade = grade, practice = Members.GRADE_HOURS[grade] or 0,
    ships = { applicant.hull }, implants = {}, aim = nil, loyalty = Members.LOYALTY_START, title = "", owed = 0, budget = 0,
    delivered = 0, shares = 0, dayGoods = 0, dayShare = 0 }
  state.membership.members[member.id] = member
  table.insert(state.membership.memberIds, member.id)
  local best, answered = choose(state, member, places)
  if best ~= 0 then
    member.system, member.call = best, answered
  end
  -- (where they live: the corporation's station where they work)
  member.home = Members.DepositAt(state, member.system)
  member.clone = member.home
  member.aim = rollAim(state, member, Rng.For(state.historySeed, member.id, 157))
  Members.Note(state, member, `joined, a {member.trade} in a {Types.Info(member.hull).name}`)
  table.insert(events, { kind = "MemberJoined", member = member.id, name = member.name, trade = member.trade, system = member.system })
  return member
end

-- One of the player's own characters asked into the corporation, at a
-- trade: whether they can be, and why not. ('id' its character's id.)
function Members.CanJoinAlt(state: State.State, id: string, trade: string): (boolean, string?)
  local membership = state.membership
  if not Corporation.Founded(state) then
    return false, "there is no corporation to be a member of: found one first"
  elseif id == state.character then
    return false, "that is who you are"
  elseif LADDER[trade] == nil then
    return false, "a member is a miner, a fighter, a hauler or a scout"
  elseif #membership.memberIds >= Members.Room(state) then
    return false, `the corporation has room for {Members.Room(state)} members`
  end
  for _, memberId in membership.memberIds do
    if membership.members[memberId].alt == id then
      return false, "they are a member already"
    end
  end
  return true
end

-- Ask one of the player's own characters in: a member who works as any
-- does, at the trade asked, with the skills they have (Members.ALT_SKILL),
-- in the best hull of the first of that trade's they can fly; who stays
-- whatever the tax and the pickings. (Character/Characters; their name
-- and skills come from their character.)
function Members.JoinAlt(state: State.State, id: string, name: string, trade: string, skills: { [string]: number },
  events: { Event }): State.Member?
  if not Members.CanJoinAlt(state, id, trade) then
    return nil
  end
  local faction = people(state)
  local hull = "frigate.courier"
  for _, class in LADDER[trade] do
    local found = hullFor(trade, faction, class) or hullFor(trade, "", class)
    if found and Skills.Missing(Skills.Needs(found), skills) == nil then
      hull = found
      break
    end
  end
  local member = join(state, { key = `alt:{id}`, name = name, trade = trade, people = faction, hull = hull, bears = 1, until_ = 0 },
    events)
  member.alt, member.skills = id, table.clone(skills)
  member.grade, member.practice, member.loyalty, member.aim = 0, 0, 1, nil
  return member
end

-- The skills of one of the player's characters who is a member, brought
-- up to date (when a game is opened: their character has trained since).
function Members.AltSkills(state: State.State, id: string, skills: { [string]: number })
  for _, memberId in state.membership.memberIds do
    local member = state.membership.members[memberId]
    if member.alt == id then
      member.skills = table.clone(skills)
    end
  end
end

-- Once a tick; it does something on the hour, and more once a day.
function Members.Step(state: State.State, events: { Event })
  if state.tick % Members.HOUR ~= 0 or state.tick == 0 then
    return
  end
  local membership = state.membership
  if not Corporation.Founded(state) then
    return
  end
  for _, id in table.clone(membership.memberIds) do
    work(state, membership.members[id], events)
  end
  if state.tick % Members.DAY ~= 0 then
    return
  end
  local places = Members.Places(state)
  for _, id in table.clone(membership.memberIds) do
    reckon(state, membership.members[id], places, events)
  end
  -- Those who have waited long enough go elsewhere; and, on some days, somebody applies.
  for index = #membership.applicants, 1, -1 do
    if state.tick >= membership.applicants[index].until_ then
      table.remove(membership.applicants, index)
    end
  end
  local held, towers = 0, 0
  for id = 1, Galaxy.Charted(state.galaxy) do
    held += if state.galaxy.systems[id].owner == Wars.PILOT then 1 else 0
  end
  for _, id in state.starbaseIds do
    towers += if state.starbases[id].owner == Wars.PILOT then 1 else 0
  end
  local day = state.tick // Members.DAY
  local rng = Rng.For(state.historySeed, day, 149)
  local chance = math.min(Members.APPLY_MOST, (Members.APPLY + Members.APPLY_SYSTEM * held + Members.APPLY_TOWER * towers)
    * (1 + Members.RENOWN * math.max(0, state.skills.renown or 0)))
  if #membership.applicants < Members.WAITING and #membership.memberIds < Members.Room(state) and Rng.Chance(rng, chance) then
    local applicant = candidate(state, rng, `apply:{day}`, state.tick + Members.WAITS * Members.DAY)
    table.insert(membership.applicants, applicant)
    table.insert(events, { kind = "MemberApplied", name = applicant.name, trade = applicant.trade, key = applicant.key })
  end
end

local COMMANDS: { [string]: boolean } = { AcceptMember = true, DeclineMember = true, InviteMember = true, ExpelMember = true,
  SetTax = true, SetShare = true, PostCall = true, CancelCall = true }
Members.COMMANDS = COMMANDS

local function waiting(state: State.State, key: string): (State.Applicant?, number)
  for index, applicant in state.membership.applicants do
    if applicant.key == key then
      return applicant, index
    end
  end
  return nil, 0
end

function Members.Validate(state: State.State, command: State.Command): (boolean, string?)
  local kind = command.kind
  local membership = state.membership
  if not COMMANDS[kind] then
    return false, `unknown command '{kind}'`
  elseif not Corporation.Founded(state) then
    return false, "there is no corporation to be a member of: found one first"
  elseif kind == "AcceptMember" or kind == "DeclineMember" then
    if waiting(state, command.what or "") == nil then
      return false, "nobody of that name is waiting"
    elseif kind == "AcceptMember" and #membership.memberIds >= Members.Room(state) then
      return false, `the corporation has room for {Members.Room(state)} members`
    end
    return true
  elseif kind == "InviteMember" then
    local ship = state.ships[command.actor]
    local found: State.Applicant? = nil
    for _, open in Members.Open(state, if ship then ship.docked else 0) do
      found = if open.key == command.what then open else found
    end
    if found == nil then
      return false, "nobody here of that name is open to joining"
    elseif #membership.memberIds >= Members.Room(state) then
      return false, `the corporation has room for {Members.Room(state)} members`
    elseif membership.tax > found.bears + 1e-9 then
      return false, `they will not join at a tax of {math.floor(membership.tax * 100 + 0.5)}%: {math.floor(found.bears * 100 + 0.5)}% is what they will bear`
    end
    return true
  elseif kind == "ExpelMember" then
    return membership.members[command.target or 0] ~= nil, "no such member"
  elseif kind == "SetTax" then
    local percent = command.quantity or -1
    if percent < 0 or percent > Members.TAX_MOST * 100 or percent % 1 ~= 0 then
      return false, `a tax is a whole number of per cent, {Members.TAX_MOST * 100} at most`
    end
    return true
  elseif kind == "SetShare" then
    local percent = command.quantity or -1
    if percent < 0 or percent > 100 or percent % 1 ~= 0 then
      return false, "a share is a whole number of per cent, 100 at most"
    end
    return true
  elseif kind == "PostCall" then
    local system = state.galaxy.systems[command.target or 0]
    if Members.CALLS[command.what or ""] == nil then
      return false, "a call is to defend, mine, haul or scout"
    elseif system == nil or table.find(Members.Places(state), system.id) == nil then
      return false, "a call is for a system the corporation has a place in"
    elseif (command.quantity or 0) < 0 or (command.quantity or 0) % 1 ~= 0 then
      return false, "a reward is a whole number of credits a day"
    elseif #membership.calls >= Members.Calls(state) then
      return false, `{Members.Calls(state)} calls are posted already`
    end
    for _, call in membership.calls do
      if call.system == system.id and call.kind == command.what then
        return false, "that call is posted already"
      end
    end
    return true
  end
  -- CancelCall
  for _, call in membership.calls do
    if call.id == command.target then
      return true
    end
  end
  return false, "no such call"
end

function Members.Apply(state: State.State, command: State.Command, events: { Event })
  local kind = command.kind
  local membership = state.membership
  if kind == "AcceptMember" or kind == "DeclineMember" then
    local applicant, index = waiting(state, command.what :: string)
    table.remove(membership.applicants, index)
    if kind == "AcceptMember" and applicant then
      join(state, applicant, events)
    end
  elseif kind == "InviteMember" then
    local ship = state.ships[command.actor]
    local day = state.tick // Members.DAY
    for _, open in Members.Open(state, ship.docked) do
      if open.key == command.what then
        if membership.invitedDay ~= day then
          membership.invitedDay, membership.invited = day, {}
        end
        table.insert(membership.invited, open.key)
        join(state, open, events)
        break
      end
    end
  elseif kind == "ExpelMember" then
    leave(state, membership.members[command.target :: number], "expelled", events)
  elseif kind == "SetTax" then
    membership.tax = (command.quantity :: number) / 100
    table.insert(events, { kind = "TaxSet", tax = membership.tax })
  elseif kind == "SetShare" then
    membership.share = (command.quantity :: number) / 100
    Members.Note(state, nil, `the share of what is brought in is now {command.quantity}%`)
    table.insert(events, { kind = "ShareSet", share = membership.share })
  elseif kind == "PostCall" then
    local call: State.Call = { id = State.NewId(state), kind = command.what :: string, system = command.target :: number,
      reward = command.quantity or 0, posted = state.tick }
    table.insert(membership.calls, call)
    table.insert(events, { kind = "CallPosted", call = call.id, what = call.kind, system = call.system, reward = call.reward })
  else
    for index, call in membership.calls do
      if call.id == command.target then
        table.remove(membership.calls, index)
        break
      end
    end
    for _, id in membership.memberIds do
      if membership.members[id].call == command.target then
        membership.members[id].call = 0
      end
    end
  end
end

return Members
