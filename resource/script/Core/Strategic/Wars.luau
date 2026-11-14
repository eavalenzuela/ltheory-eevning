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
-- Everything here is plain data, and follows from the galaxy, the
-- history seed and the tick.

local Constants = require("@lt/Core/Data/Constants")
local Factions = require("@lt/Core/Data/Factions")
local Galaxy = require("@lt/Core/Describe/Galaxy")
local Rng = require("@lt/Core/Kernel/Rng")
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
-- (No faction has more to send than so much, however long it has been
-- left in peace; a siege is sent with a share of what there is, and no
-- less than the least a siege is; and no relief is bigger than so much.)
Wars.MOST = 300
Wars.SIEGE_SHARE, Wars.RELIEF_MOST = 0.5, 120
-- A faction keeps so many claims at most, and has so many operations
-- going at once.
Wars.CLAIMS, Wars.OPERATIONS = 40, 2
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
Wars.FRICTION, Wars.FRICTION_MOST, Wars.DRIFT = 0.15, 1, 0.02
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
Wars.ENOUGH = 1.2
-- (And no war is over in less than so long.)
Wars.LEAST = math.ceil(24 * 3600 * SECOND)

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
  node.owner = to
  if to ~= "" then
    wars.claims[system] = to
  else
    wars.claims[system] = nil
  end
  wars.version += 1
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
local function think(galaxy: Galaxy.Galaxy, wars: State.Wars, faction: string, tick: number, events: { Event })
  local held, claimed = holdings(galaxy, wars)
  local hours = Wars.THINK / Wars.HOUR
  local mine = (wars.strength[faction] or 0) + (held[faction] or 0) * Wars.INCOME * hours - (claimed[faction] or 0) * Wars.UPKEEP * hours
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
    for id = 1, Galaxy.Charted(galaxy) do
      if galaxy.systems[id].owner == faction then
        for _, neighbor in galaxy.systems[id].neighbors do
          local node = galaxy.systems[neighbor]
          local theirs = wars.claims[neighbor]
          if at(wars, neighbor) == nil and not node.home then
            if theirs and theirs ~= faction and Wars.AtWar(wars, faction, theirs) then
              siege = if siege == 0 or neighbor < siege then neighbor else siege
            elseif node.owner == "" then
              claim = if claim == 0 or neighbor < claim then neighbor else claim
            end
          end
        end
      end
    end
    local target, force = 0, 0
    if siege ~= 0 and mine >= Wars.SIEGE_FORCE then
      target, force = siege, math.max(Wars.SIEGE_FORCE, mine * Wars.SIEGE_SHARE)
    elseif claim ~= 0 and mine >= Wars.CLAIM_FORCE and (claimed[faction] or 0) < Wars.CLAIMS then
      target, force = claim, Wars.CLAIM_FORCE
    end
    if target ~= 0 then
      mine -= force
      local against = wars.claims[target] or ""
      local operation: State.Operation = { id = tick * 16 + #wars.operations, by = faction, system = target,
        kind = if against ~= "" then "siege" else "claim", began = tick, force = force, sent = force, against = against,
        defence = if against ~= "" then Wars.GARRISON else 0, defended = if against ~= "" then Wars.GARRISON else 0, stage = "muster",
        relieved = false }
      table.insert(wars.operations, operation)
      table.insert(events, { kind = "OperationBegan", system = target, by = faction, against = against, what = operation.kind })
    end
  end
  wars.strength[faction] = math.min(Wars.MOST, mine)
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
      if operation.kind == "claim" and galaxy.systems[operation.system].owner ~= "" then
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
    if over == nil and operation.stage ~= "muster" and operation.defence > 0 and not operation.shown then
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

-- An hour of diplomacy: what is between every two factions is worn by
-- their borders and comes back toward where it settles; wars begin;
-- wars weary; truces are made, and run out.
local function diplomacy(galaxy: Galaxy.Galaxy, wars: State.Wars, tick: number, events: { Event })
  local holders = Galaxy.Holders(galaxy)
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
    wars.weary[feud.a] = (wars.weary[feud.a] or 0) + Wars.WEARY_HOUR
    wars.weary[feud.b] = (wars.weary[feud.b] or 0) + Wars.WEARY_HOUR
    local a, b = wars.weary[feud.a], wars.weary[feud.b]
    if tick - feud.since >= Wars.LEAST and (a + b >= Wars.ENOUGH or a >= 1 or b >= 1) then
      table.remove(wars.feuds, index)
      local key = pair(feud.a, feud.b)
      wars.truces[key] = tick + Wars.TRUCE
      wars.relations[key] = Wars.TRUCE_AT
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
        wars.strength[winner] = math.min(Wars.MOST, (wars.strength[winner] or 0) + paid)
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
function Wars.Step(galaxy: Galaxy.Galaxy, wars: State.Wars, seed: number, tick: number, events: { Event })
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
    think(galaxy, wars, holders[phase // slot + 1], tick, events)
  end
  if tick % Wars.HOUR == 0 then
    diplomacy(galaxy, wars, tick, events)
  end
end

return Wars
