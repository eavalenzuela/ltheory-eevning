--!strict
-- The factions at war: who is at odds with whom, and what they do about
-- the open space between them.
--
-- The project owner's rulings (2026-11-14): only open space changes
-- hands (what a faction was given when the galaxy was made is its home
-- and stays so: nobody is wiped out, and nobody's home is taken); who
-- fights whom is for diplomacy to decide, and is different every game.
-- The rest is first figures.
--
-- Territory. A faction holds its home, and whatever open systems it has
-- claimed. It can claim an open system next to what it holds, by
-- sending a force there: twenty minutes mustering (which can be seen),
-- twenty blockading it, twenty moving in, and it is theirs: a claim, on
-- the map in their colour. A claim has a garrison and no more: nobody
-- keeps order there, and it is as lawless as it was (what is in its
-- belts, and who comes to them, does not change with whose it is). It
-- costs something to keep, and a faction keeps only so many.
--
-- Diplomacy. Every two factions have something between them, from -100
-- to 100, which settles at what their kinds make of each other and is
-- worn down by every gate that joins what one holds to what the other
-- does. Under WAR_BELOW they are at war, as soon as one of them is free
-- to say so. A faction that goes to war with a much weaker one
-- frightens the rest, and loses with all of them: and one of them that
-- by then thinks badly enough of it, and well enough of its victim,
-- joins the war against it, border or no border (a coalition: what it
-- adds is one more war to weary the aggressor). A war wearies both: by
-- the hour, by what each loses, by each claim taken from it. When they
-- have had enough between them there is a truce, for two days at least,
-- and it has terms: the side that took more claims than it lost is paid
-- a share of what the other has to send, and, if it took a good many
-- more, is handed one more claim of the other's that lies next to what
-- it holds.
--
-- War. A faction at war lays siege to its enemy's claims that lie next
-- to what it holds: the same hour of muster, blockade and assault, but
-- against the garrison, and against whatever the holder sends to its
-- relief. While the two forces are both there they fight, a round a
-- minute, each losing by what the other has left; the one brought down
-- to a fifth of what it came with gives way. A siege that wins takes
-- the claim. A blockaded system's lanes are all but shut (Strategic/
-- Commerce): what it is short of it stays short of, and its haulers
-- stop coming.
--
-- War in goods (the owner, 2026-11-24: "wars should be an economic
-- cost even to major factions"; no treasuries; no cap on strength). With
-- the galaxy's economy given (Strategic/Commerce), what a faction has to
-- send is ships, and ships are built of what is in the stock of the
-- systems it holds: a point of strength is a quarter of a frigate of its
-- own line (a cruiser four, a battleship twelve and a half, as the fronts
-- count them: Tactical/Fronts), and is drawn as those hulls' materials.
-- A faction keeps so much for each system it holds, twice that at war,
-- and builds toward it as fast as its yards may and its stock allows:
-- what it draws is dear there, so its industry works harder and goods
-- come in along the lanes. A force in the field burns its charges and
-- its fuel, drawn from the systems it holds beside the front: what is
-- not there to burn, the force does without, and withers. And a faction
-- at war whose yards cannot build half of what it wants wearies of it
-- the faster. Without an economy (the wars by themselves: a test, or
-- Tool/wars) strength comes as it did, so much an hour a system.
--
-- Everything here is plain data, and follows from the galaxy, the
-- history seed and the tick.

local Commerce = require("@lt/Core/Strategic/Commerce")
local Constants = require("@lt/Core/Data/Constants")
local Economy = require("@lt/Core/Strategic/Economy")
local Factions = require("@lt/Core/Data/Factions")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local State = require("@lt/Core/Kernel/State")

local Wars = {}

export type Event = { [string]: any }

local SECOND = 1 / Constants.TICK
-- Ticks between the rounds of what is going on at a system, between a
-- faction's turns to think, and between the hours of diplomacy.
Wars.ROUND = math.ceil(60 * SECOND)
Wars.THINK = math.ceil(600 * SECOND)
Wars.HOUR = math.ceil(3600 * SECOND)
-- How long each stage of an operation is.
Wars.STAGE = math.ceil(1200 * SECOND)
-- What a faction has to send: so much comes to it an hour for each
-- system it holds; a claim costs so much to make and a siege so much
-- (which is the force that goes); a claim's garrison; what a holder
-- sends to the relief of one (a share of what it has); and what a claim
-- costs an hour to keep.
Wars.INCOME = 0.5
Wars.CLAIM_FORCE, Wars.SIEGE_FORCE = 40, 100
Wars.GARRISON = 50
Wars.RELIEF = 0.5
Wars.UPKEEP = 0.2
-- (A siege is sent with a share of what there is, and no less than the
-- least a siege is; and no relief is bigger than so much. Without an
-- economy, no faction has more to send than so much, however long it
-- has been left in peace.)
Wars.MOST = 300
Wars.SIEGE_SHARE, Wars.RELIEF_MOST = 0.5, 120
-- War in goods: what a faction keeps for each system it holds, in
-- peace, and how many times that at war; how much its yards can build
-- an hour for each system it holds, its stock allowing; how much of the
-- materials of its ships a point of strength is (a scale on a quarter
-- frigate's: the economy's goods are bulk aggregates); the share of a
-- force's worth burnt an hour in the field; and what a faction at war
-- wearies an hour whose yards build less than half of what it wants.
-- (First figures, and mine: Tool/galaxyrun measures what they do.)
Wars.KEEP, Wars.KEEP_WAR = 3, 2
Wars.BUILD = 0.5
Wars.SCALE = 0.5
Wars.BURN = 0.02
Wars.SHORT, Wars.SHORT_WEARY = 0.5, 0.02
-- A war wearies a faction by what it costs: an hour's spending on it
-- (its yards' at war, and its forces' in the field), as a share of what
-- its own space makes in an hour, times this. So a big faction, which
-- makes more and fields more, tires of a costly war as a small one does;
-- and a war with little fighting drags on. (The hour's weariness of any
-- war is less than it was, now that the cost carries the rest.)
Wars.WEARY_COST = 0.06
-- (and its yards take no more than this share of what a system has of a
-- material at a time: a war drains a system, and goes short where there
-- is little. Not a price past which nothing is bought: in a big galaxy
-- what comes only from lawless space is dear in a faction's settled
-- space by nature, and a price limit stopped a people's yards outright,
-- 2026-11-24.)
Wars.SPARE = 0.25
-- A faction keeps so many claims at most, and has so many operations
-- going at once.
Wars.CLAIMS, Wars.OPERATIONS = 40, 2
-- (but in a big galaxy a faction may claim its share of so much of the
-- open space, so that the factions spread until their borders meet and
-- have something to fight over: the owner, 2026-11-24, of 5,000-system
-- galaxies where nobody touched anybody and there were no wars. The
-- rest of it stays open.)
Wars.CLAIMED_SHARE = 0.5

-- How many claims a faction may keep in this galaxy: forty, or its share
-- of half the open space, whichever is more. (Worked out once for a
-- galaxy and kept beside it, as Galaxy.Holders is.)
local mostOf: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any
function Wars.Claims(galaxy: Galaxy.Galaxy): number
  local kept = mostOf[galaxy]
  if kept == nil then
    -- (open space is what was made lawless: a faction's own space is made
    -- 0.3 or more, and a system's own security never changes)
    local open = 0
    for id = 1, Galaxy.Charted(galaxy) do
      open += if galaxy.systems[id].security < 0.3 then 1 else 0
    end
    kept = math.max(Wars.CLAIMS, math.floor(open * Wars.CLAIMED_SHARE / math.max(1, #Galaxy.Holders(galaxy))))
    mostOf[galaxy] = kept
  end
  return kept
end
-- What each force loses in a round, as a share of what the other has
-- (half as much again or as little, by the luck of it), and the share
-- of what it came with at which a force gives way.
Wars.ATTRITION, Wars.BREAK = 0.05, 0.2
-- What is between two factions settles at this, by their kinds; it is
-- worn down so much an hour for each gate between them (so much at
-- most), and comes back toward where it settles by a share of the gap
-- an hour.
local SETTLES: { [string]: number } = {
  ["human human"] = 10, ["alien human"] = -15, ["alien alien"] = -5,
  ["human pirate"] = -40, ["alien pirate"] = -40, ["pirate pirate"] = -40,
}
-- (Where two settle: their kinds' figure less a fiftieth of an hour's
-- wear, so seven and a half a gate at first. Doubled 2026-11-24: in a big
-- galaxy borders are a few gates thin, and nobody came to war; now pirates
-- go to war with whoever they touch at a gate, aliens with their
-- neighbours at two or three, two human peoples at four or more.)
Wars.FRICTION, Wars.FRICTION_MOST, Wars.DRIFT = 0.3, 2, 0.02
Wars.WAR_BELOW = -50
-- A faction declares one war a day at most; a truce lasts two days; what
-- is between two who have made one; how much stronger the one who
-- declares has to be to frighten the rest, and what that costs it with
-- each of them.
Wars.DAY = math.ceil(86400 * SECOND)
Wars.TRUCE_AT = -25
Wars.TRUCE = 2 * Wars.DAY
Wars.BULLY, Wars.FRIGHT = 1.5, 10
-- A coalition: a faction joins a war against one it thinks this badly
-- of, or worse, beside one it thinks this well of, or better.
Wars.JOIN_BELOW, Wars.JOIN_BESIDE = -30, 0
-- Terms: the side ahead by so many claims is paid this share of what
-- the other has to send, and ahead by so many is handed a claim too.
Wars.TERMS, Wars.TRIBUTE, Wars.CEDE = 1, 0.25, 3
-- What wearies a faction at war: an hour of it, a point of force lost,
-- a claim taken from it. Two at war make a truce when they are this
-- weary between them, or either is quite worn out.
Wars.WEARY_HOUR, Wars.WEARY_LOSS, Wars.WEARY_CLAIM = 0.012, 0.001, 0.15
-- (an hour of war wearies so much less with an economy to pay for it)
Wars.WEARY_HOUR_PAID = 0.006
Wars.ENOUGH = 1.2
-- (And no war is over in less than so long.)
Wars.LEAST = math.ceil(24 * 3600 * SECOND)

-- The pilot's corporation, as a holder of open space (Assets/
-- Sovereignty): it is no faction, and has no home. What is between it
-- and a faction is what that faction thinks of the pilot (their
-- standings), and not kept here: a faction that is hostile to the pilot
-- and holds space next to a system of theirs declares on them, besieges
-- it as it would an enemy's claim, and makes a truce when it has had
-- enough, or thinks better of them. And a system of the pilot's has
-- order kept in it from the first, so much.
Wars.PILOT = "player"
Wars.ORDER = 0.35
-- Order follows control (the owner, 2026-11-24, undoing their ruling of
-- 2026-11-14 that a claim is "as lawless as it was": "I do want to undo
-- the divorce of control from security. Player sov systems should
-- increase in security status, even", and "Stop at the top of Low
-- security"). A system held, a faction's claim or the pilot's, has its
-- order raised so much a day it is held, to the top of low security at
-- most; one besieged or blockaded loses so much a day; one that changes
-- hands keeps half of what its last holder had made of it; and one
-- nobody holds goes back to its own, so much a day. Its own security,
-- what its belts and sites follow, never changes (Describe/Galaxy).
Wars.ORDER_RISE, Wars.ORDER_MOST, Wars.ORDER_FALL = 0.05, 0.6, 0.1
-- (And a system of the pilot's is held by a tower and its guns, where
-- a faction's claim has a garrison: it is worth so many garrisons to
-- whoever besieges it with the pilot somewhere else.)
Wars.TOWER = 3

local function pair(a: string, b: string): string
  return if a < b then `{a}|{b}` else `{b}|{a}`
end

local function settles(a: string, b: string): number
  local ka, kb = Factions.byId[a].kind, Factions.byId[b].kind
  return SETTLES[if ka < kb then `{ka} {kb}` else `{kb} {ka}`] or 0
end

-- A galaxy's wars as a game begins: nobody at war, nothing claimed,
-- every two factions as their kinds make them.
function Wars.New(galaxy: Galaxy.Galaxy, on: boolean?): State.Wars
  local holders = Galaxy.Holders(galaxy)
  local wars: State.Wars = { on = on ~= false, relations = {}, feuds = {}, truces = {}, claims = {}, operations = {}, strength = {},
    weary = {}, declared = {}, version = 0 }
  for index, a in holders do
    wars.strength[a], wars.weary[a] = 60, 0
    for other = index + 1, #holders do
      wars.relations[pair(a, holders[other])] = settles(a, holders[other])
    end
  end
  return wars
end

-- What is between two factions (0 for one that holds nothing), and
-- whether they are at war.
function Wars.Between(wars: State.Wars, a: string, b: string): number
  return wars.relations[pair(a, b)] or 0
end

-- An id for an operation begun at 'tick': of that tick, and none that a
-- running one has (two begun in the same round shared one, and what was
-- fought at one was put down to the other).
function Wars.OperationId(wars: State.Wars, tick: number): number
  local used: { [number]: boolean } = {}
  for _, operation in wars.operations do
    used[operation.id] = true
  end
  local id = tick * 64
  while used[id] do
    id += 1
  end
  return id
end

function Wars.AtWar(wars: State.Wars, a: string, b: string): boolean
  for _, feud in wars.feuds do
    if (feud.a == a and feud.b == b) or (feud.a == b and feud.b == a) then
      return true
    end
  end
  return false
end

-- The systems that are blockaded now: those an operation is at, past
-- its muster.
function Wars.Blocked(wars: State.Wars): { [number]: boolean }
  local blocked: { [number]: boolean } = {}
  for _, operation in wars.operations do
    if operation.stage ~= "muster" then
      blocked[operation.system] = true
    end
  end
  return blocked
end

-- How many systems each faction holds (home and claims), and how many
-- claims.
local function holdings(galaxy: Galaxy.Galaxy, wars: State.Wars): ({ [string]: number }, { [string]: number })
  local held: { [string]: number } = {}
  local claimed: { [string]: number } = {}
  for id = 1, Galaxy.Charted(galaxy) do
    local owner = galaxy.systems[id].owner
    if owner ~= "" then
      held[owner] = (held[owner] or 0) + 1
      if wars.claims[id] then
        claimed[owner] = (claimed[owner] or 0) + 1
      end
    end
  end
  return held, claimed
end

-- A system changes hands: to a faction, or ("") to nobody.
local function take(galaxy: Galaxy.Galaxy, wars: State.Wars, system: number, to: string)
  local node = galaxy.systems[system]
  -- (what its last holder made of its order, half of it stays; and the
  -- pilot keeps order from the first)
  local own = node.security
  local kept = own + (Galaxy.Order(node) - own) / 2
  if to == Wars.PILOT then
    kept = math.max(kept, Wars.ORDER)
  end
  node.order = if math.abs(kept - own) < 1e-9 then nil else kept
  node.owner = to
  if to ~= "" then
    wars.claims[system] = to
  else
    wars.claims[system] = nil
  end
  wars.version += 1
end

-- Whether there is a truce between two.
function Wars.Truce(wars: State.Wars, a: string, b: string): boolean
  return wars.truces[pair(a, b)] ~= nil
end

-- A war begun, and a war ended in a truce, for a reason that is
-- somebody else's (the pilot's corporation says so: Assets/Sovereignty).
function Wars.Declare(wars: State.Wars, by: string, on: string, tick: number)
  wars.declared[by] = tick
  table.insert(wars.feuds, { a = by, b = on, since = tick, score = 0 })
end

function Wars.Settle(wars: State.Wars, a: string, b: string, tick: number): State.Feud?
  for index, feud in wars.feuds do
    if (feud.a == a and feud.b == b) or (feud.a == b and feud.b == a) then
      table.remove(wars.feuds, index)
      wars.truces[pair(a, b)] = tick + Wars.TRUCE
      return feud
    end
  end
  return nil
end

-- The war between two, if they are at war.
function Wars.Feud(wars: State.Wars, a: string, b: string): State.Feud?
  for _, feud in wars.feuds do
    if (feud.a == a and feud.b == b) or (feud.a == b and feud.b == a) then
      return feud
    end
  end
  return nil
end

-- A system changes hands for a reason that is somebody else's (the
-- pilot's claim, made or let go: Assets/Sovereignty).
function Wars.Take(galaxy: Galaxy.Galaxy, wars: State.Wars, system: number, to: string)
  take(galaxy, wars, system, to)
end

-- What a point of a faction's strength is made of: a quarter of a
-- frigate of its own line, by the materials of its frigates, cruisers
-- and battleships as the fronts count them (Tactical/Fronts' worth: 4,
-- 16, 50), each class weighed alike. By class of goods, in units.
local WORTH: { [string]: number } = { frigate = 4, cruiser = 16, battleship = 50 }
local bills: { [string]: { [number]: number } } = {}
local function billOf(faction: string): { [number]: number }
  local kept = bills[faction]
  if kept == nil then
    local sums: { [string]: { [number]: number } } = {}
    local counts: { [string]: number } = {}
    local ids: { string } = {}
    for id, hull in Ships.byId do
      if hull.lineage == faction and WORTH[hull.class] and hull.tech ~= 2 and hull.role == nil then
        table.insert(ids, id)
      end
    end
    table.sort(ids)
    for _, id in ids do
      local hull = Ships.byId[id]
      local into = sums[hull.class] or {}
      sums[hull.class] = into
      counts[hull.class] = (counts[hull.class] or 0) + 1
      for _, part in Commerce.Bill(id) do
        into[part.class] = (into[part.class] or 0) + part.amount
      end
    end
    kept = {}
    local classes = 0
    for _, class in { "frigate", "cruiser", "battleship" } do
      if counts[class] then
        classes += 1
      end
    end
    for _, class in { "frigate", "cruiser", "battleship" } do
      local into = sums[class]
      if into then
        for goods, amount in into do
          kept[goods] = (kept[goods] or 0) + amount / counts[class] / WORTH[class] / classes
        end
      end
    end
    bills[faction] = kept
  end
  return kept
end

-- What a point of a faction's strength is made of (by class of goods, in
-- units), for whoever reckons with it.
function Wars.Bill(faction: string): { [number]: number }
  return billOf(faction)
end

-- For the tools (Tool/galaxyrun): the share of its space's making a
-- faction at war spends on it, summed, and over how many faction-hours.
Wars.costShare, Wars.costHours = 0, 0

-- For the tools (Tool/galaxyrun): the worth, at the normal price, of
-- what the wars have drawn from the economy since this was last read.
Wars.drawn = 0

-- Draw so many points of a faction's materials from the stock of these
-- systems, as much of it as is there; returns the share of it there was.
local function draw(econ: Economy.Economy, faction: string, points: number, from: { number }): (number, number)
  if points <= 0 or #from == 0 then
    return if points <= 0 then 1 else 0, 0
  end
  local bill = billOf(faction)
  local goods: { number } = {}
  for class in bill do
    table.insert(goods, class)
  end
  table.sort(goods)
  -- (what each system can spare of a thing: a share of what it has)
  local function spare(id: number, class: number): number
    return math.max(0, econ.nodes[id].stock[class] * Wars.SPARE)
  end
  local share = 1
  for _, class in goods do
    local need = bill[class] * points * Wars.SCALE
    local have = 0
    for _, id in from do
      have += spare(id, class)
    end
    if need > 0 then
      share = math.min(share, have / need)
    end
  end
  share = math.clamp(share, 0, 1)
  if share <= 0 then
    return 0, 0
  end
  local worth = 0
  for _, class in goods do
    local need = bill[class] * points * Wars.SCALE * share
    local have = 0
    for _, id in from do
      have += spare(id, class)
    end
    if have > 0 then
      for _, id in from do
        local took = Economy.Draw(econ, id, class, need * spare(id, class) / have)
        worth += took * econ.classes[class].par
      end
    end
  end
  Wars.drawn += worth
  return share, worth
end

-- The systems a faction holds whose stock its yards can draw on: those
-- with a market in the economy, and not blockaded.
local function sources(galaxy: Galaxy.Galaxy, econ: Economy.Economy, faction: string, blocked: { [number]: boolean }): { number }
  local found: { number } = {}
  for id = 1, math.min(Galaxy.Charted(galaxy), #econ.nodes) do
    if galaxy.systems[id].owner == faction and not blocked[id] then
      table.insert(found, id)
    end
  end
  return found
end

local function atWar(wars: State.Wars, faction: string): boolean
  for _, feud in wars.feuds do
    if feud.a == faction or feud.b == faction then
      return true
    end
  end
  return false
end

-- Whether a faction is at war with anybody.
function Wars.Fighting(wars: State.Wars, faction: string): boolean
  return atWar(wars, faction)
end

local function operationsOf(wars: State.Wars, faction: string): number
  local count = 0
  for _, operation in wars.operations do
    count += if operation.by == faction then 1 else 0
  end
  return count
end

local function at(wars: State.Wars, system: number): State.Operation?
  for _, operation in wars.operations do
    if operation.system == system then
      return operation
    end
  end
  return nil
end

-- A faction's turn: what has come to it, what its claims cost, and what
-- it sends where. To the relief of a claim of its own that is besieged;
-- against a claim of an enemy's next to what it holds; and to an open
-- system next to what it holds that nobody has. (The lowest-numbered
-- system of each kind: the map decides, not a roll.)
local function think(galaxy: Galaxy.Galaxy, wars: State.Wars, faction: string, tick: number, events: { Event }, econ: Economy.Economy?)
  local held, claimed = holdings(galaxy, wars)
  local hours = Wars.THINK / Wars.HOUR
  local mine = (wars.strength[faction] or 0) - (claimed[faction] or 0) * Wars.UPKEEP * hours
  if econ then
    -- (in goods: toward what it keeps, as fast as its yards and its stock allow)
    local supplied = wars.supplied or {}
    wars.supplied = supplied
    local keep = (held[faction] or 0) * Wars.KEEP * (if atWar(wars, faction) then Wars.KEEP_WAR else 1)
    if supplied[faction] == nil then
      -- (what it has when the galaxy first runs with an economy was built before)
      mine = math.max(mine, (held[faction] or 0) * Wars.KEEP)
      supplied[faction] = 1
    elseif mine < keep then
      local want = math.min(keep - mine, (held[faction] or 0) * Wars.BUILD * hours)
      local share, worth = draw(econ, faction, want, sources(galaxy, econ, faction, Wars.Blocked(wars)))
      mine += want * share
      supplied[faction] = share
      if atWar(wars, faction) then
        local spent = wars.spent or {}
        wars.spent = spent
        spent[faction] = (spent[faction] or 0) + worth
      end
    else
      supplied[faction] = 1
    end
  else
    mine += (held[faction] or 0) * Wars.INCOME * hours
  end
  -- (a faction that cannot keep what it has claimed lets the last of it go)
  if mine < 0 then
    local last = 0
    for id = 1, Galaxy.Charted(galaxy) do
      if wars.claims[id] == faction and at(wars, id) == nil then
        last = id
      end
    end
    if last ~= 0 then
      take(galaxy, wars, last, "")
      table.insert(events, { kind = "ClaimLapsed", system = last, by = faction })
    end
    mine = 0
  end
  -- Relief: half of what it has, once, to a claim of its own that is past its muster.
  for _, operation in wars.operations do
    if operation.against == faction and operation.stage ~= "muster" and not operation.relieved and mine >= 20 then
      local sent = math.min(Wars.RELIEF_MOST, mine * Wars.RELIEF)
      mine -= sent
      operation.defence += sent
      operation.defended += sent
      operation.relieved = true
      table.insert(events, { kind = "ReliefSent", system = operation.system, by = faction, against = operation.by, force = sent })
    end
  end
  if operationsOf(wars, faction) < Wars.OPERATIONS then
    local siege, claim = 0, 0
    -- (a claim that is on its way counts toward how many it keeps: with
    -- two on their way at once a faction one short of its most was
    -- over it when both came home)
    local claiming = 0
    for _, operation in wars.operations do
      claiming += if operation.by == faction and operation.kind == "claim" then 1 else 0
    end
    for id = 1, Galaxy.Charted(galaxy) do
      if galaxy.systems[id].owner == faction then
        for _, neighbor in galaxy.systems[id].neighbors do
          local node = galaxy.systems[neighbor]
          local theirs = wars.claims[neighbor]
          if at(wars, neighbor) == nil and not node.home then
            if theirs and theirs ~= faction and Wars.AtWar(wars, faction, theirs) then
              siege = if siege == 0 or neighbor < siege then neighbor else siege
            elseif node.owner == "" and not (wars.spoken and wars.spoken[neighbor]) then
              -- (not one the pilot's beacon stands in: it is spoken for)
              claim = if claim == 0 or neighbor < claim then neighbor else claim
            end
          end
        end
      end
    end
    local target, force = 0, 0
    -- (a faction that keeps as many claims as it may takes no more, of
    -- anybody's: Wars.Claims held for sieges as for open space. Found by
    -- Tool/galaxyrun, 2026-11-24: one faction ran to seven in ten of all
    -- the claims there were)
    local room = (claimed[faction] or 0) + claiming < Wars.Claims(galaxy)
    if siege ~= 0 and mine >= Wars.SIEGE_FORCE and room then
      target, force = siege, math.max(Wars.SIEGE_FORCE, mine * Wars.SIEGE_SHARE)
    elseif claim ~= 0 and mine >= Wars.CLAIM_FORCE and room then
      target, force = claim, Wars.CLAIM_FORCE
    end
    if target ~= 0 then
      mine -= force
      local against = wars.claims[target] or ""
      local garrison = if against == Wars.PILOT then Wars.GARRISON * Wars.TOWER elseif against ~= "" then Wars.GARRISON else 0
      local operation: State.Operation = { id = Wars.OperationId(wars, tick), by = faction, system = target,
        kind = if against ~= "" then "siege" else "claim", began = tick, force = force, sent = force, against = against,
        defence = garrison, defended = garrison, stage = "muster", relieved = false }
      table.insert(wars.operations, operation)
      table.insert(events, { kind = "OperationBegan", system = target, by = faction, against = against, what = operation.kind })
    end
  end
  wars.strength[faction] = if econ then mine else math.min(Wars.MOST, mine)
end

-- A round of everything that is going on at a system: an operation goes
-- from stage to stage with time; where two forces are both there they
-- fight; one of them gives way; and a system is taken, or kept.
local function round(galaxy: Galaxy.Galaxy, wars: State.Wars, seed: number, tick: number, events: { Event })
  for index = #wars.operations, 1, -1 do
    local operation = wars.operations[index]
    local age = tick - operation.began
    local over: string? = nil
    if operation.stage == "muster" and age >= Wars.STAGE then
      -- (somebody else has it by now: there is nothing to claim)
      -- (or the pilot's beacon stands in it, and it is spoken for)
      if operation.kind == "claim" and (galaxy.systems[operation.system].owner ~= ""
        or (wars.spoken ~= nil and wars.spoken[operation.system] == true)) then
        over = "called off"
      else
        operation.stage = "blockade"
        table.insert(events, { kind = "Blockaded", system = operation.system, by = operation.by, against = operation.against })
      end
    elseif operation.stage == "blockade" and age >= 2 * Wars.STAGE then
      operation.stage = "assault"
    end
    -- (where the pilot is the two forces are ships, and what is left of
    -- each is what they are worth: Tactical/Fronts. No round is reckoned.)
    -- (And the pilot's own siege is fought by the pilot, in person: what
    -- they have sent is themselves, and nothing is reckoned for it.)
    if over == nil and operation.stage ~= "muster" and operation.defence > 0 and not operation.shown and operation.by ~= Wars.PILOT then
      local rng = Rng.For(seed, tick, operation.id, 811)
      local toAttack = operation.defence * Wars.ATTRITION * Rng.Float(rng, 0.5, 1.5)
      local toDefence = operation.force * Wars.ATTRITION * Rng.Float(rng, 0.5, 1.5)
      toAttack, toDefence = math.min(toAttack, operation.force), math.min(toDefence, operation.defence)
      operation.force -= toAttack
      operation.defence -= toDefence
      wars.weary[operation.by] = (wars.weary[operation.by] or 0) + toAttack * Wars.WEARY_LOSS
      if operation.against ~= "" then
        wars.weary[operation.against] = (wars.weary[operation.against] or 0) + toDefence * Wars.WEARY_LOSS
      end
    end
    if over == nil and operation.stage ~= "muster" then
      if operation.force <= Wars.BREAK * operation.sent then
        over = "broken"
      elseif operation.defence > 0 and operation.defence <= Wars.BREAK * operation.defended then
        -- (what is left of the defence gets away, to fight another day)
        wars.strength[operation.against] = (wars.strength[operation.against] or 0) + operation.defence / 2
        operation.defence = 0
      end
    end
    if over == nil and operation.stage == "assault" and operation.defence <= 0 and age >= 3 * Wars.STAGE then
      over = "taken"
    end
    -- (peace was made while it was on its way)
    if over == nil and operation.kind == "siege" and not Wars.AtWar(wars, operation.by, operation.against) then
      over = "called off"
    end
    if over then
      table.remove(wars.operations, index)
      -- (what is left of the force goes home: half of it is fit for anything)
      wars.strength[operation.by] = (wars.strength[operation.by] or 0) + operation.force / 2
      if over == "taken" then
        take(galaxy, wars, operation.system, operation.by)
        if operation.against ~= "" then
          wars.weary[operation.against] = (wars.weary[operation.against] or 0) + Wars.WEARY_CLAIM
          for _, feud in wars.feuds do
            if feud.a == operation.by and feud.b == operation.against then
              feud.score += 1
            elseif feud.b == operation.by and feud.a == operation.against then
              feud.score -= 1
            end
          end
        end
        table.insert(events, { kind = "SystemTaken", system = operation.system, by = operation.by, from = operation.against })
      else
        if over == "broken" and operation.against ~= "" then
          wars.strength[operation.against] = (wars.strength[operation.against] or 0) + operation.defence / 2
        end
        table.insert(events, { kind = "OperationOver", system = operation.system, by = operation.by, against = operation.against,
          how = over })
      end
    end
  end
end

-- An hour of order: every held system's rises toward the top of low
-- security, unless it is besieged or blockaded, when it falls; and every
-- system nobody holds goes back toward its own. (Never below its own by
-- this: a surge's mark is Strategic/Happenings'.)
local function keepOrder(galaxy: Galaxy.Galaxy, wars: State.Wars)
  local blocked = Wars.Blocked(wars)
  local rise, fall = Wars.ORDER_RISE / 24, Wars.ORDER_FALL / 24
  for id = 1, Galaxy.Charted(galaxy) do
    local node = galaxy.systems[id]
    if not node.home then
      local own = node.security
      local now = Galaxy.Order(node)
      local after = now
      if node.owner ~= "" and not blocked[id] then
        after = if now < Wars.ORDER_MOST then math.min(Wars.ORDER_MOST, now + rise) else now
      elseif node.owner ~= "" then
        after = math.max(own, now - fall)
      elseif now > own then
        after = math.max(own, now - fall)
      end
      if after ~= now then
        node.order = if math.abs(after - own) < 1e-9 then nil else after
      end
    end
  end
end

-- An hour of order, for whoever runs it by itself (a test).
function Wars.KeepOrder(galaxy: Galaxy.Galaxy, wars: State.Wars)
  keepOrder(galaxy, wars)
end

-- An hour in the field, in goods: every force at an operation past its
-- muster, the besieger's and the defence, burns its charges and fuel,
-- drawn from the systems its side holds beside the front (or, with none
-- there, any it holds); what is not there it does without, and withers
-- by as much. And a faction at war whose yards built less than half of
-- what it wanted wearies the faster, and is said to be short once a day.
local function supply(galaxy: Galaxy.Galaxy, wars: State.Wars, econ: Economy.Economy, tick: number, events: { Event })
  local blocked = Wars.Blocked(wars)
  local function beside(faction: string, system: number): { number }
    local near: { number } = {}
    for _, neighbor in galaxy.systems[system].neighbors do
      if galaxy.systems[neighbor].owner == faction and not blocked[neighbor] and neighbor <= #econ.nodes then
        table.insert(near, neighbor)
      end
    end
    table.sort(near)
    return if #near > 0 then near else sources(galaxy, econ, faction, blocked)
  end
  local spent = wars.spent or {}
  wars.spent = spent
  for _, operation in wars.operations do
    if operation.stage ~= "muster" and operation.by ~= Wars.PILOT and not operation.shown then
      local burn = operation.force * Wars.BURN
      local share, worth = draw(econ, operation.by, burn, beside(operation.by, operation.system))
      operation.force -= burn * (1 - share)
      spent[operation.by] = (spent[operation.by] or 0) + worth
      if operation.against ~= "" and operation.against ~= Wars.PILOT and operation.defence > 0 then
        local held = operation.defence * Wars.BURN
        local theirs, cost = draw(econ, operation.against, held, beside(operation.against, operation.system))
        operation.defence -= held * (1 - theirs)
        spent[operation.against] = (spent[operation.against] or 0) + cost
      end
    end
  end
  -- (what each faction's space makes in an hour, in worth: its
  -- facilities' work at the normal price of what comes of it)
  local makes: { [string]: number } = {}
  for id = 1, math.min(Galaxy.Charted(galaxy), #econ.nodes) do
    local owner = galaxy.systems[id].owner
    if owner ~= "" then
      local worth = 0
      for _, facility in econ.nodes[id].facilities do
        if facility.activity > 0 then
          for _, out in econ.recipes[facility.recipe].outputs do
            worth += facility.activity * out.amount * econ.classes[out.class].par
          end
        end
      end
      makes[owner] = (makes[owner] or 0) + worth
    end
  end
  local holders = Galaxy.Holders(galaxy)
  for _, faction in holders do
    local cost = spent[faction] or 0
    if cost > 0 and (makes[faction] or 0) > 0 then
      local share = cost / makes[faction]
      wars.weary[faction] = (wars.weary[faction] or 0) + share * Wars.WEARY_COST
      Wars.costShare += share
      Wars.costHours += 1
    end
    spent[faction] = nil
  end
  local supplied = wars.supplied or {}
  local said = wars.shortDay or {}
  wars.shortDay = said
  for _, faction in holders do
    if atWar(wars, faction) and (supplied[faction] or 1) < Wars.SHORT then
      wars.weary[faction] = (wars.weary[faction] or 0) + Wars.SHORT_WEARY
      local day = tick // Wars.DAY
      if said[faction] ~= day then
        said[faction] = day
        table.insert(events, { kind = "YardsShort", faction = faction, share = supplied[faction] })
      end
    end
  end
end

-- An hour of diplomacy: what is between every two factions is worn by
-- their borders and comes back toward where it settles; wars begin;
-- wars weary; truces are made, and run out.
local function diplomacy(galaxy: Galaxy.Galaxy, wars: State.Wars, tick: number, events: { Event }, hostile: { [string]: boolean },
  costly: boolean)
  local holders = Galaxy.Holders(galaxy)
  -- The pilot's corporation: a faction that is hostile to the pilot and
  -- holds space next to a system of theirs declares on them, if there
  -- is no truce between them; and one that is at war with them and
  -- hostile no longer makes a truce.
  local beside: { [string]: boolean } = {}
  for system, owner in wars.claims do
    if owner == Wars.PILOT then
      for _, neighbor in galaxy.systems[system].neighbors do
        local other = galaxy.systems[neighbor].owner
        if other ~= "" and other ~= Wars.PILOT then
          beside[other] = true
        end
      end
    end
  end
  for _, faction in holders do
    local key = pair(faction, Wars.PILOT)
    if hostile[faction] and beside[faction] and wars.truces[key] == nil and not Wars.AtWar(wars, faction, Wars.PILOT)
      and tick - (wars.declared[faction] or -Wars.DAY) >= Wars.DAY then
      wars.declared[faction] = tick
      table.insert(wars.feuds, { a = faction, b = Wars.PILOT, since = tick, score = 0 })
      table.insert(events, { kind = "WarDeclared", by = faction, on = Wars.PILOT })
    end
  end
  for index = #wars.feuds, 1, -1 do
    local feud = wars.feuds[index]
    if feud.b == Wars.PILOT and not hostile[feud.a] then
      table.remove(wars.feuds, index)
      wars.truces[pair(feud.a, Wars.PILOT)] = tick + Wars.TRUCE
      table.insert(events, { kind = "PeaceMade", a = feud.a, b = Wars.PILOT, score = feud.score, hours = (tick - feud.since) // Wars.HOUR,
        winner = "", paid = 0, ceded = 0 })
    end
  end
  local borders: { [string]: number } = {}
  for id = 1, Galaxy.Charted(galaxy) do
    local owner = galaxy.systems[id].owner
    if owner ~= "" then
      for _, neighbor in galaxy.systems[id].neighbors do
        local other = galaxy.systems[neighbor].owner
        if neighbor > id and other ~= "" and other ~= owner then
          local key = pair(owner, other)
          borders[key] = (borders[key] or 0) + 1
        end
      end
    end
  end
  for key, ends in wars.truces do
    if tick >= ends then
      wars.truces[key] = nil
    end
  end
  for index, a in holders do
    for other = index + 1, #holders do
      local b = holders[other]
      local key = pair(a, b)
      local between = wars.relations[key] or settles(a, b)
      between += (settles(a, b) - between) * Wars.DRIFT - math.min(Wars.FRICTION_MOST, (borders[key] or 0) * Wars.FRICTION)
      wars.relations[key] = math.clamp(between, -100, 100)
    end
  end
  -- Wars that have gone on an hour more, and those that are over.
  for index = #wars.feuds, 1, -1 do
    local feud = wars.feuds[index]
    local hourly = if costly then Wars.WEARY_HOUR_PAID else Wars.WEARY_HOUR
    wars.weary[feud.a] = (wars.weary[feud.a] or 0) + hourly
    wars.weary[feud.b] = (wars.weary[feud.b] or 0) + hourly
    local a, b = wars.weary[feud.a], wars.weary[feud.b]
    if tick - feud.since >= Wars.LEAST and (a + b >= Wars.ENOUGH or a >= 1 or b >= 1) then
      table.remove(wars.feuds, index)
      local key = pair(feud.a, feud.b)
      wars.truces[key] = tick + Wars.TRUCE
      -- (what is between a faction and the pilot is the pilot's standing with it, and is not kept here)
      if feud.b ~= Wars.PILOT then
        wars.relations[key] = Wars.TRUCE_AT
      end
      wars.weary[feud.a], wars.weary[feud.b] = a / 2, b / 2
      -- The terms: to whoever took more claims than it lost.
      local winner, loser = "", ""
      if math.abs(feud.score) >= Wars.TERMS then
        winner, loser = if feud.score > 0 then feud.a else feud.b, if feud.score > 0 then feud.b else feud.a
      end
      local paid, ceded = 0, 0
      if winner ~= "" then
        paid = math.floor((wars.strength[loser] or 0) * Wars.TRIBUTE)
        wars.strength[loser] = (wars.strength[loser] or 0) - paid
        wars.strength[winner] = (wars.strength[winner] or 0) + paid
        if math.abs(feud.score) >= Wars.CEDE then
          -- (the lowest-numbered claim of the loser's next to what the winner holds, that nothing is being done to)
          for id = 1, Galaxy.Charted(galaxy) do
            if ceded == 0 and wars.claims[id] == loser and at(wars, id) == nil then
              for _, neighbor in galaxy.systems[id].neighbors do
                if galaxy.systems[neighbor].owner == winner then
                  ceded = id
                end
              end
            end
          end
          if ceded ~= 0 then
            take(galaxy, wars, ceded, winner)
          end
        end
      end
      table.insert(events, { kind = "PeaceMade", a = feud.a, b = feud.b, score = feud.score, hours = (tick - feud.since) // Wars.HOUR,
        winner = winner, paid = paid, ceded = ceded })
    end
  end
  -- (a faction at peace with everybody rests)
  for _, faction in holders do
    local fighting = false
    for _, feud in wars.feuds do
      fighting = fighting or feud.a == faction or feud.b == faction
    end
    if not fighting then
      wars.weary[faction] = math.max(0, (wars.weary[faction] or 0) - Wars.WEARY_HOUR)
    end
  end
  local held = holdings(galaxy, wars)
  for index, a in holders do
    for other = index + 1, #holders do
      local b = holders[other]
      local key = pair(a, b)
      if (wars.relations[key] or 0) < Wars.WAR_BELOW and wars.truces[key] == nil and not Wars.AtWar(wars, a, b)
        and (borders[key] or 0) > 0 then
        -- (whichever is the stronger says so, if it has not declared a war today)
        local first, second = a, b
        if (wars.strength[b] or 0) + (held[b] or 0) > (wars.strength[a] or 0) + (held[a] or 0) then
          first, second = b, a
        end
        if tick - (wars.declared[first] or -Wars.DAY) >= Wars.DAY then
          wars.declared[first] = tick
          table.insert(wars.feuds, { a = first, b = second, since = tick, score = 0 })
          table.insert(events, { kind = "WarDeclared", by = first, on = second })
          local mine, theirs = (wars.strength[first] or 0) + (held[first] or 0), (wars.strength[second] or 0) + (held[second] or 0)
          if mine > Wars.BULLY * theirs then
            for _, third in holders do
              if third ~= first and third ~= second then
                local with = pair(first, third)
                wars.relations[with] = math.max(-100, (wars.relations[with] or 0) - Wars.FRIGHT)
                -- (and one that thinks badly enough of it by now, and
                -- well enough of its victim, joins against it)
                if wars.relations[with] <= Wars.JOIN_BELOW and (wars.relations[pair(second, third)] or 0) >= Wars.JOIN_BESIDE
                  and wars.truces[with] == nil and not Wars.AtWar(wars, first, third)
                  and tick - (wars.declared[third] or -Wars.DAY) >= Wars.DAY then
                  wars.declared[third] = tick
                  table.insert(wars.feuds, { a = third, b = first, since = tick, score = 0 })
                  table.insert(events, { kind = "CoalitionJoined", by = third, against = first, beside = second })
                end
              end
            end
          end
        end
      end
    end
  end
end

-- Once a tick. (Most ticks nothing is due.)
-- ('hostile': the factions that are hostile to the pilot now, by what
-- they think of them. Nobody, if it is not said.)
-- ('econ': the galaxy's economy, Strategic/Commerce's, for war in goods;
-- nil for the wars by themselves.)
function Wars.Step(galaxy: Galaxy.Galaxy, wars: State.Wars, seed: number, tick: number, events: { Event }, hostile: { [string]: boolean }?,
  econ: Economy.Economy?)
  if tick <= 0 or not wars.on then
    return
  end
  if tick % Wars.ROUND == 0 then
    round(galaxy, wars, seed, tick, events)
  end
  -- (each faction in its turn, a turn apart)
  local holders = Galaxy.Holders(galaxy)
  local slot = math.max(1, Wars.THINK // math.max(1, #holders))
  local phase = tick % Wars.THINK
  if phase % slot == 0 and holders[phase // slot + 1] then
    think(galaxy, wars, holders[phase // slot + 1], tick, events, econ)
  end
  if tick % Wars.HOUR == 0 then
    if econ then
      supply(galaxy, wars, econ, tick, events)
    end
    keepOrder(galaxy, wars)
    diplomacy(galaxy, wars, tick, events, hostile or {}, econ ~= nil)
  end
end

return Wars
