--!strict
-- Relations between the powers: how they drift, when they break into
-- war, who sides against an aggressor, and how a war ends.
--
-- Relations run from -100 to 100. Each pair has a level it settles at
-- (sociable pairs high, aggressive pairs low); shared borders wear it
-- down, more for the aggressive and for a power with nowhere left to
-- grow. Below WAR_BELOW the pair is at war as soon as one of them is
-- free to declare it (a power may declare one war a day, and none within
-- a day of one ending).
--
-- Coalitions. A power that starts a war against a clearly weaker one
-- frightens the rest: their relations with it fall, and rise with its
-- victim. As they fall a bystander first closes its borders to the
-- aggressor, then pays its victim a subsidy, then joins the war, unless
-- it is in no state to.
--
-- Peace is proposed and judged, never decreed. A war has a score (who
-- has taken what, who has lost what); each side grows weary with time,
-- losses, an empty treasury, and with having got what it came for.
-- Terms are a payment and systems handed over. Whoever proposes them,
-- Accepts is the one test of whether a side will sign: so an offer from
-- a player's power is weighed exactly as a computer's is.

local Powers = require("@lt/Core/Data/Powers")
local Rng = require("@lt/Core/Kernel/Rng")
local World = require("@lt/Core/Strategic/World")

local Diplomacy = {}

export type Terms = {
  loser: number,        -- who gives; 0 for a peace with no terms
  winner: number,
  pays: number,         -- credits from the loser to the winner
  cedes: { number },    -- systems from the loser to the winner
}

-- ---------------------------------------------------------------------
-- Measures

local function laidUp(faction: World.Faction): number
  local total = 0
  for class, count in faction.reserve do
    total += count * Powers.ships[class].strength
  end
  return total
end

-- A faction's fleet, serving and laid up.
function Diplomacy.Fleet(world: World.World, faction: World.Faction): number
  return World.Navy(world, faction.id) + laidUp(faction)
end

-- The population of the systems it holds.
function Diplomacy.Worth(world: World.World, faction: number): number
  local total = 0
  for id, s in world.systems do
    if s.owner == faction then
      total += world.atlas.systems[id].population
    end
  end
  return total
end

-- How much each power counts for: its fleet and its people.
function Diplomacy.Power(world: World.World): { number }
  local power: { number } = table.create(#world.factions, 0)
  for id, s in world.systems do
    if s.owner > 0 then
      power[s.owner] += world.atlas.systems[id].population
    end
  end
  for id, faction in world.factions do
    power[id] += Diplomacy.Fleet(world, faction)
  end
  return power
end

-- How much each pair of powers rub against each other, from 0 to 1.5:
-- more the more lanes join their space, a little if they only face each
-- other across a system neither owns. And which powers still have an
-- independent system next door.
local function borders(world: World.World): ({ { number } }, { boolean })
  local n = #world.factions
  local links: { { number } } = table.create(n)
  local contact: { { number } } = table.create(n)
  local room: { boolean } = table.create(n, false)
  for id = 1, n do
    links[id] = table.create(n, 0)
    contact[id] = table.create(n, 0)
  end
  for _, lane in world.atlas.lanes do
    local a, b = world.systems[lane.a].owner, world.systems[lane.b].owner
    if a > 0 and b > 0 and a ~= b then
      links[a][b] += 1
      links[b][a] += 1
    elseif a > 0 and b == 0 and not world.systems[lane.b].den then
      room[a] = true
    elseif b > 0 and a == 0 and not world.systems[lane.a].den then
      room[b] = true
    end
  end
  for id, s in world.systems do
    if s.owner == 0 then
      local first = 0
      for _, m in world.galaxy.systems[id].neighbors do
        local owner = world.systems[m].owner
        if owner > 0 and owner ~= world.pirates then
          if first == 0 then
            first = owner
          elseif owner ~= first then
            contact[first][owner] = Powers.CONTACT_NEAR
            contact[owner][first] = Powers.CONTACT_NEAR
          end
        end
      end
    end
  end
  for a = 1, n do
    for b = 1, n do
      if links[a][b] > 0 then
        contact[a][b] = 0.5 + 0.25 * math.min(4, links[a][b])
      end
    end
  end
  return contact, room
end

local function setRelation(a: World.Faction, b: World.Faction, value: number)
  local r = math.clamp(value, -100, 100)
  a.relations[b.id], b.relations[a.id] = r, r
end

-- ---------------------------------------------------------------------
-- War

-- May 'a' declare war on 'b' now? If not, why not.
function Diplomacy.CanDeclare(world: World.World, a: World.Faction, b: World.Faction): (boolean, string?)
  if a.id == b.id or a.pirate or b.pirate or not a.alive or not b.alive then
    return false, "no such war"
  end
  if World.WarBetween(world, a.id, b.id) then
    return false, "already at war"
  end
  if world.tick < a.truce[b.id] then
    return false, "a truce holds"
  end
  if world.tick - a.lastDeclared < Powers.WAR_COOLDOWN then
    return false, "it declared a war within the day"
  end
  if world.tick - a.lastWarEnded < Powers.WAR_COOLDOWN then
    return false, "one of its wars ended within the day"
  end
  return true, nil
end

function Diplomacy.Declare(world: World.World, a: World.Faction, b: World.Faction, coalition: boolean): boolean
  if not Diplomacy.CanDeclare(world, a, b) then
    return false
  end
  table.insert(world.wars, {
    a = a.id, b = b.id, since = world.tick,
    startA = math.max(1, Diplomacy.Fleet(world, a)), startB = math.max(1, Diplomacy.Fleet(world, b)),
    lostA = 0, lostB = 0, takenA = 0, takenB = 0, coalition = coalition,
  })
  a.lastDeclared = world.tick
  setRelation(a, b, math.min(a.relations[b.id], Powers.WAR_BELOW))
  a.stance[b.id], b.stance[a.id] = 0, 0
  World.Count(world, "wars declared")
  if coalition then
    World.Count(world, "coalition wars")
    World.Log(world, "war", `{a.name} joins the war against {b.name}`, 0, a.id, b.id)
  else
    World.Log(world, "war", `{a.name} declares war on {b.name}`, 0, a.id, b.id)
  end
  return true
end

-- What taking a system is measured against: half the smaller side.
local function reference(world: World.World, war: World.War): number
  return math.max(5, 0.5 * math.min(Diplomacy.Worth(world, war.a) + war.takenB, Diplomacy.Worth(world, war.b) + war.takenA))
end

-- The score of a war, from -1 to 1, from the declarer's side: what each
-- has taken, and the share of its fleet each has lost.
function Diplomacy.Score(world: World.World, war: World.War): number
  local territory = (war.takenA - war.takenB) / reference(world, war)
  local fleets = war.lostB / war.startB - war.lostA / war.startA
  return math.clamp(territory + 0.5 * fleets, -1, 1)
end

-- The score as one side sees it.
local function scoreFor(world: World.World, war: World.War, faction: number): number
  local score = Diplomacy.Score(world, war)
  return if war.a == faction then score else -score
end

-- How tired of a war a side is: 0 fresh; near 1 it will take almost any
-- peace.
function Diplomacy.Weariness(world: World.World, war: World.War, faction: World.Faction): number
  local mine = war.a == faction.id
  local time = (world.tick - war.since) / Powers.WAR_LONGEST
  local losses = if mine then war.lostA / war.startA else war.lostB / war.startB
  local money = if faction.arrears > 0 then 0.5 elseif faction.credits < 2 * faction.costs then 0.25 else 0
  -- Having what it came for, or being beaten, both make peace welcome.
  local settled = 0.5 * math.abs(scoreFor(world, war, faction.id))
  return time + 0.6 * losses + money + settled
end

-- The terms the score calls for: the side behind pays a share of its
-- treasury and hands over border systems, those under siege first, in
-- proportion to how far behind it is. Near a draw, nothing.
function Diplomacy.Terms(world: World.World, war: World.War): Terms
  local score = Diplomacy.Score(world, war)
  local size = math.abs(score)
  if size < 0.15 then
    return { loser = 0, winner = 0, pays = 0, cedes = {} }
  end
  local winner, loser = if score > 0 then war.a else war.b, if score > 0 then war.b else war.a
  local losing = world.factions[loser]
  local candidates: { number } = {}
  for id, s in world.systems do
    if s.owner == loser and id ~= losing.capital then
      for _, n in world.galaxy.systems[id].neighbors do
        if world.systems[n].owner == winner then
          table.insert(candidates, id)
          break
        end
      end
    end
  end
  local function besieged(id: number): boolean
    local siege = world.systems[id].siege
    return siege ~= nil and siege.by == winner
  end
  table.sort(candidates, function(p: number, q: number): boolean
    local bp, bq = besieged(p), besieged(q)
    if bp ~= bq then
      return bp
    end
    local cp, cq = world.systems[p].control, world.systems[q].control
    if cp ~= cq then
      return cp < cq
    end
    return p < q
  end)
  local cedes: { number } = {}
  for i = 1, math.min(#candidates, math.floor(Powers.CEDED_MOST * size + 0.5)) do
    table.insert(cedes, candidates[i])
  end
  return { loser = loser, winner = winner, pays = Powers.REPARATIONS * size * math.max(0, losing.credits), cedes = cedes }
end

-- What a set of terms is worth to one side, in the units of the score:
-- systems against half the smaller side, money against the most the
-- score could call for.
function Diplomacy.Value(world: World.World, war: World.War, faction: number, terms: Terms): number
  if terms.loser == 0 then
    return 0
  end
  local territory = 0
  for _, id in terms.cedes do
    territory += world.atlas.systems[id].population
  end
  local most = Powers.REPARATIONS * math.max(1, world.factions[terms.loser].credits)
  local value = 0.4 * math.min(1, territory / reference(world, war)) + 0.3 * math.min(1, terms.pays / most)
  return if faction == terms.winner then value elseif faction == terms.loser then -value else 0
end

-- Would this side sign these terms now? It asks for what the score says
-- it has won, less as it tires; a side that is behind gives more as it
-- tires.
function Diplomacy.Accepts(world: World.World, war: World.War, faction: World.Faction, terms: Terms): boolean
  local demand = 0.7 * scoreFor(world, war, faction.id) - (Diplomacy.Weariness(world, war, faction) - 0.4)
  return Diplomacy.Value(world, war, faction.id, terms) >= demand - 0.05
end

-- End a war on the given terms. (Both sides have agreed: check with
-- Accepts first.)
function Diplomacy.MakePeace(world: World.World, war: World.War, terms: Terms)
  local a, b = world.factions[war.a], world.factions[war.b]
  local at = table.find(world.wars, war)
  if at == nil then
    return
  end
  table.remove(world.wars, at)
  if terms.loser > 0 then
    local names: { string } = {}
    for _, id in terms.cedes do
      if world.systems[id].owner == terms.loser then
        World.Transfer(world, id, terms.winner)
        World.Sour(world, terms.winner, terms.loser, Powers.GRUDGE)
        table.insert(names, World.SystemName(world, id))
        World.Count(world, "systems ceded")
      end
    end
    local pays = math.min(terms.pays, math.max(0, world.factions[terms.loser].credits))
    World.Pay(world, terms.loser, terms.winner, pays, "reparations")
    World.Log(world, "peace", `{World.Name(world, terms.loser)} makes peace with {World.Name(world, terms.winner)}: `
      .. `{if #names > 0 then "cedes " .. table.concat(names, ", ") else "cedes nothing"}, pays {math.floor(pays)}`,
      0, terms.loser, terms.winner)
  else
    World.Log(world, "peace", `{a.name} and {b.name} make peace, with nothing changing hands`, 0, a.id, b.id)
  end
  a.lastWarEnded, b.lastWarEnded = world.tick, world.tick
  setRelation(a, b, Powers.AFTER_PEACE)
  a.truce[b.id], b.truce[a.id] = world.tick + Powers.TRUCE, world.tick + Powers.TRUCE
  if terms.loser > 0 then
    world.factions[terms.winner].truce[terms.loser] = world.tick + Powers.TRUCE_WON
  end
  -- Plans against each other are dropped. (Sieges end by themselves:
  -- Battle.Sieges lifts one whose target is no longer an enemy's.)
  for _, faction in { a, b } do
    local other = if faction == a then b.id else a.id
    local plan = faction.plan
    if plan and world.systems[plan.target].owner == other then
      faction.plan = nil
    end
  end
  World.Count(world, "peace treaties")
  World.Count(world, "war ticks", world.tick - war.since)
  World.Count(world, "strength lost in wars", war.lostA + war.lostB)
end

-- ---------------------------------------------------------------------
-- The period

-- Is this faction an aggressor now: a power well above the average, in
-- a war it declared (not to stop another aggressor) against a clearly
-- weaker one?
local function aggressor(world: World.World, power: { number }, average: number, faction: number): boolean
  if power[faction] <= Powers.AGGRESSOR_SIZE * average then
    return false
  end
  for _, war in world.wars do
    if war.a == faction and not war.coalition and power[faction] > Powers.AGGRESSOR_RATIO * power[war.b] then
      return true
    end
  end
  return false
end

-- Is a bystander in a state to join a war?
local function ready(world: World.World, faction: World.Faction): boolean
  return faction.arrears == 0 and faction.credits >= 2 * faction.costs and not World.AtWar(world, faction.id)
end

-- Does a power think it can win a war it starts? It wants a margin over
-- the other's fleet, smaller the bolder it is, and no war already.
function Diplomacy.Confident(world: World.World, faction: World.Faction, other: World.Faction): boolean
  return ready(world, faction)
    and Diplomacy.Fleet(world, faction) >= (1.3 - 0.4 * faction.traits.aggressive) * Diplomacy.Fleet(world, other)
end

-- 'wants', if given, is how a government decides whether to start a
-- war once relations allow one (Strategic/Mind's judgement, which also
-- asks whether there is anything to attack). Without it, confidence in
-- its fleet is enough.
function Diplomacy.Step(world: World.World, wants: ((World.World, World.Faction, World.Faction) -> boolean)?)
  local willing = wants or Diplomacy.Confident
  local hours = Powers.PERIOD_HOURS
  local factions = world.factions
  local power = Diplomacy.Power(world)
  local total, count = 0, 0
  for id, faction in factions do
    if faction.alive and not faction.pirate then
      total += power[id]
      count += 1
    end
  end
  local average = if count > 0 then total / count else 1

  -- Fear of aggressors, and what bystanders do about it.
  for _, war in table.clone(world.wars) do
    if not war.coalition and aggressor(world, power, average, war.a) and power[war.a] > Powers.AGGRESSOR_RATIO * power[war.b] then
      local bully, victim = factions[war.a], factions[war.b]
      local fear = Powers.FEAR * (power[war.a] / average - 1) * hours
      for _, c in factions do
        if c.alive and not c.pirate and c.id ~= bully.id and c.id ~= victim.id
          and not World.WarBetween(world, c.id, victim.id) and not World.WarBetween(world, c.id, bully.id) then
          setRelation(c, bully, c.relations[bully.id] - fear)
          setRelation(c, victim, c.relations[victim.id] + Powers.SOLIDARITY * hours)
          if c.stance[bully.id] >= 2 and c.credits > Powers.RESERVE_HOURS * c.costs then
            World.Pay(world, c.id, victim.id, Powers.SUBSIDY * c.income * hours, "subsidy")
            World.Count(world, "subsidy periods")
          end
        end
      end
    end
  end

  local contact, room = borders(world)
  for _, a in factions do
    for _, b in factions do
      if a.id < b.id and a.alive and b.alive and not a.pirate and not b.pirate then
        local war = World.WarBetween(world, a.id, b.id)
        if war then
          local terms = Diplomacy.Terms(world, war)
          if Diplomacy.Accepts(world, war, a, terms) and Diplomacy.Accepts(world, war, b, terms) then
            Diplomacy.MakePeace(world, war, terms)
          end
        else
          -- Old grudges fade.
          local baseline = a.baseline[b.id]
          baseline += Powers.GRUDGE_FADE * (Powers.Natural(a.traits, b.traits) - baseline) * hours
          a.baseline[b.id], b.baseline[a.id] = baseline, baseline
          local r = a.relations[b.id]
          local aggressive = (a.traits.aggressive + b.traits.aggressive) / 2
          local sociable = (a.traits.sociable + b.traits.sociable) / 2
          local hunger = if room[a.id] and room[b.id] then 1 else Powers.LAND_HUNGER
          local friction = contact[a.id][b.id] * Powers.FRICTION * aggressive * (1 - 0.7 * sociable) * hunger
          r += (Powers.DRIFT * (a.baseline[b.id] - r) - friction) * hours
          if contact[a.id][b.id] > 0 then
            local rng = Rng.For(world.history, world.tick, a.id, b.id, 7)
            r += Powers.INCIDENTS * math.sqrt(hours) * Rng.Float(rng, -1, 1)
          end
          setRelation(a, b, r)

          -- Stances short of war, toward an aggressor only.
          local bullyA, bullyB = aggressor(world, power, average, a.id), aggressor(world, power, average, b.id)
          local function stance(toward: boolean): number
            return if not toward then 0 elseif r < Powers.SUBSIDY_BELOW then 2 elseif r < Powers.EMBARGO_BELOW then 1 else 0
          end
          local sa, sb = stance(bullyB), stance(bullyA)
          if sa > a.stance[b.id] and a.stance[b.id] == 0 then
            World.Count(world, "embargoes")
            World.Log(world, "embargo", `{a.name} closes its borders to {b.name}`, 0, a.id, b.id)
          end
          if sb > b.stance[a.id] and b.stance[a.id] == 0 then
            World.Count(world, "embargoes")
            World.Log(world, "embargo", `{b.name} closes its borders to {a.name}`, 0, b.id, a.id)
          end
          a.stance[b.id], b.stance[a.id] = sa, sb

          if r < Powers.WAR_BELOW then
            -- Bad blood makes a war possible; somebody still has to
            -- think it worth starting. A bystander joins against an
            -- aggressor if it is in a state to. Otherwise whichever of
            -- the two is willing declares (the bolder, if both are), and
            -- if neither is they go on glaring.
            local coalition = bullyA ~= bullyB
            if coalition then
              local declarer, target = if bullyB then a else b, if bullyB then b else a
              if ready(world, declarer) then
                Diplomacy.Declare(world, declarer, target, true)
              end
            else
              local first, second = a, b
              if b.traits.aggressive > a.traits.aggressive then
                first, second = b, a
              end
              if willing(world, first, second) then
                Diplomacy.Declare(world, first, second, false)
              elseif willing(world, second, first) then
                Diplomacy.Declare(world, second, first, false)
              end
            end
          end
        end
      end
    end
  end
end

return Diplomacy
