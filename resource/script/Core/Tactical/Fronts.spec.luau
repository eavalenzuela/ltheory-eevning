--!strict
-- The factions' forces as ships where the pilot is (Tactical/Fronts).

local Aftermath = require("@lt/Core/Tactical/Aftermath")
local Core = require("@lt/Core/Api")
local Fronts = require("@lt/Core/Tactical/Fronts")
local Members = require("@lt/Core/Assets/Members")
local Missions = require("@lt/Core/Assets/Missions")
local Space = require("@lt/Core/Tactical/Space")
local Standings = require("@lt/Core/Assets/Standings")
local State = require("@lt/Core/Kernel/State")
local Test = require("@lt/Tool/Test")
local Wars = require("@lt/Core/Strategic/Wars")

local suite = Test.Suite("Fronts")

-- A game with the pilot in space in an open system that the Talmar hold
-- as a claim and the Vessari are besieging, the siege past its muster:
-- the game, the system and the operation.
local function besieged(force: number, defence: number): (Core.Game, number, State.Operation)
  local game = Core.New({ galaxySeed = 1, historySeed = 1, systems = 40, peaceful = true, wars = true })
  local state = game.state
  assert(Core.Submit(game, { kind = "Undock", actor = state.player.ship }))
  Core.Step(game)
  local open = 0
  for id = 2, 40 do
    if state.galaxy.systems[id].owner == "" and open == 0 then
      open = id
    end
  end
  assert(open ~= 0, "the galaxy has no open system")
  state.galaxy.systems[open].owner = "talmar"
  state.wars.claims[open] = "talmar"
  table.insert(state.wars.feuds, { a = "vessari", b = "talmar", since = state.tick, score = 0 })
  local operation: State.Operation = { id = 99, by = "vessari", system = open, kind = "siege", began = state.tick - Wars.STAGE - 60,
    force = force, sent = force, against = "talmar", defence = defence, defended = defence, stage = "blockade", relieved = true }
  table.insert(state.wars.operations, operation)
  local me = state.balls[state.player.ship]
  me.system = open
  me.x, me.y, me.z = 5e9, 0, 0
  me.vx, me.vy, me.vz = 0, 0, 0
  Space.AssignGrid(state, me)
  Core.Step(game)
  Core.TakeEvents(game)
  return game, open, operation
end

-- How many ships there are of the factions' forces. (A lawless system
-- may have others that think for themselves: a pirate tower's batteries.)
local function fielded(state: State.State): number
  local count = 0
  for _, id in state.pilotIds do
    count += if state.pilots[id].side then 1 else 0
  end
  return count
end

local function go(game: Core.Game, site: number, off: number?)
  local state = game.state
  local place = assert(Space.Object(state, site))
  local me = state.balls[state.player.ship]
  me.x, me.y, me.z = place.x, place.y + (off or 30000), place.z
  Space.AssignGrid(state, me)
end

suite:Case("a strength comes to ships: the big hulls out of what there is plenty of, eight at most, and the rest in reserve", function(t)
  for _, strength in { 0, 3, 4, 40, 90, 120, 200, 300 } do
    local ships, reserve = Fronts.Muster(strength)
    local worth = 0
    for _, ship in ships do
      worth += ship.worth
    end
    t.eq(worth + reserve, strength)
    t.ok(#ships <= Fronts.SHIPS, `{#ships} ships for {strength}`)
  end
  t.eq(#Fronts.Muster(3), 0)
  local some = Fronts.Muster(120)
  t.eq({ some[1].class, some[2].class, some[#some].class }, { "battleship", "cruiser", "frigate" })
  local few = Fronts.Muster(40)
  t.eq(few[1].class, "cruiser")
end)

suite:Case("a siege where the pilot is has a place; at it the two forces are ships, and fight each other and nobody else", function(t)
  local game, system, operation = besieged(120, 90)
  local state = game.state
  local front = assert(state.fronts[99], "the siege has no place")
  local place = assert(Space.Object(state, front.site))
  t.eq({ front.system, front.shown, string.sub(place.name, 1, 11), state.sites[front.site].strength } :: { any },
    { system, false, "Siege Lines", 1 } :: { any })
  t.eq(fielded(state), 0, "ships before anybody is there to see them")
  -- (and until the pilot is there, it goes on by the round)
  t.eq(operation.shown, nil)
  go(game, front.site)
  Core.Step(game)
  t.eq({ front.shown, operation.shown } :: { any }, { true, true } :: { any })
  local sides: { [string]: number } = {}
  local worth: { [string]: number } = {}
  for id, record in front.ships do
    local ship, pilot = state.ships[id], state.pilots[id]
    sides[record.side] = (sides[record.side] or 0) + 1
    worth[record.side] = (worth[record.side] or 0) + record.worth
    t.eq({ ship.owner, pilot.side, pilot.worth, pilot.home, record.attacking } :: { any },
      { record.side, record.side, record.worth, front.site, record.side == "vessari" } :: { any })
    t.ok(state.balls[id].grid == front.site, "a ship of the force is somewhere else")
  end
  t.ok((sides.vessari or 0) >= 3 and (sides.talmar or 0) >= 3, `{sides.vessari} Vessari and {sides.talmar} Talmar ships`)
  t.eq({ worth.vessari + front.reserve, worth.talmar + front.held }, { 120, 90 })
  -- They fight: shots between the two sides, none at the pilot, and each force is worth less for it.
  local shots, atMe = 0, 0
  for _ = 1, 600 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      if event.kind == "Shot" then
        shots += 1
        atMe += if event.to == state.player.ship then 1 else 0
        local from, to = state.pilots[event.from], front.ships[event.to]
        t.ok(from == nil or to == nil or from.side ~= to.side, "a ship fired on its own side")
      end
    end
  end
  t.ok(shots > 50, `{shots} shots in ten minutes`)
  t.eq(atMe, 0, "a faction's ship fired on a pilot who had done nothing")
  t.ok(operation.force < 120 or operation.defence < 90, "nobody lost anything in ten minutes")
  local force, defence = front.reserve, front.held
  for id, record in front.ships do
    t.ok(state.balls[id] ~= nil)
    force += if record.attacking then record.worth else 0
    defence += if record.attacking then 0 else record.worth
  end
  t.eq({ operation.force, operation.defence }, { force, defence })
  -- The pilot goes: the ships are taken away, and what they were worth fights on unseen.
  local before = operation.force
  go(game, front.site, 5e7)
  for _ = 1, Fronts.LINGER + 5 do
    Core.Step(game)
  end
  t.eq({ front.shown, operation.shown, next(front.ships), fielded(state) } :: { any }, { false, nil, nil, 0 } :: { any })
  t.ok(operation.force <= before and operation.force > 0)
  -- (and the save has it all)
  go(game, front.site)
  Core.Step(game)
  local data, length = Core.Save(game)
  t.eq(Core.Hash(Core.Load(data, length)), Core.Hash(game))
end)

suite:Case("a pilot who takes a hand is that side's enemy, is paid by the other, and can break a siege or a defence", function(t)
  local game, _, operation = besieged(120, 90)
  local state = game.state
  local front = state.fronts[99]
  go(game, front.site)
  Core.Step(game)
  Core.TakeEvents(game)
  local standing = { Standings.Of(state, "talmar"), Standings.Of(state, "vessari") }
  local wallet = state.wallet
  -- One of the Talmar's is destroyed by the pilot.
  local victim, worth = 0, 0
  for id, record in front.ships do
    if record.side == "talmar" and (victim == 0 or id < victim) then
      victim, worth = id, record.worth
    end
  end
  local events: { any } = {}
  Aftermath.Destroy(state, victim, state.player.ship, events)
  local defence = operation.defence
  Fronts.Step(state, events, 1)
  t.eq(front.crossed.talmar, true)
  t.eq(front.crossed.vessari, nil)
  t.near(Standings.Of(state, "talmar"), standing[1] - Fronts.OFFENCE - Fronts.GRUDGE * worth, 1e-9)
  t.near(Standings.Of(state, "vessari"), standing[2] + Fronts.THANKS * worth, 1e-9)
  t.eq(state.wallet, wallet + Fronts.PAY * worth)
  t.eq(operation.defence, defence - worth)
  local crossed = false
  for _, event in events do
    crossed = crossed or (event.kind == "FrontCrossed" and event.side == "talmar")
  end
  t.ok(crossed, "nobody said the pilot had taken a side")
  -- (every Talmar ship there is the pilot's enemy from then, and no Vessari one)
  for id, record in front.ships do
    t.eq(state.pilots[id].foe == true, record.side == "talmar")
  end
  -- The rest of the defence is destroyed: by the next round it has given way, and the siege goes on to take the system.
  for id, record in front.ships do
    if record.side == "talmar" then
      Aftermath.Destroy(state, id, state.player.ship, game.events)
    end
  end
  local taken = false
  for _ = 1, 3 * Wars.STAGE do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      taken = taken or (event.kind == "SystemTaken" and event.by == "vessari" and event.from == "talmar")
    end
    if taken then
      break
    end
  end
  t.ok(taken, "the siege did not take the system with its defence destroyed")
  Core.Step(game)
  -- (and with the operation over its place is gone, and its ships)
  t.eq({ state.fronts[99], #state.frontIds, state.sites[front.site].gone, fielded(state) } :: { any }, { nil, 0, true, 0 } :: { any })
end)

suite:Case("war work: a station of a faction with a force at a front has a strike against the other, and a run through the blockade", function(t)
  local game, system, operation = besieged(120, 90)
  local state = game.state
  local home = state.player.home
  t.eq(state.galaxy.systems[1].nearest, "vessari")
  -- (the Vessari's station, a few jumps from where they are besieging the Talmar: its first agent has work)
  local strike: State.Mission? = nil
  local run: State.Mission? = nil
  for _, offer in Missions.Offers(state, home) do
    if offer.kind == "bounty" and offer.type ~= "" then
      strike = offer
    elseif offer.kind == "courier" and offer.aim == "blockade" then
      run = offer
    end
  end
  local job = assert(strike, "no strike is offered")
  t.eq({ job.type, job.system, job.faction, job.done } :: { any }, { "talmar", system, "vessari", 0 } :: { any })
  t.ok(job.need >= 2 and job.need <= 4 and job.reward >= job.need * Missions.WAR_HEAD and job.loyalty >= 1)
  t.eq(Missions.Title(job), `Strike: {job.need} ships of the Talmar force`)
  if run then
    t.eq(Space.SystemOf(state, run.to), system)
    t.eq(Missions.Title(run), `Blockade run: {run.need} m3 of sealed cargo`)
    t.ok(run.reward > 20000)
  end
  -- (and the seventh agent an escort to the front: of the first level for a pilot nobody knows, and no higher than the second)
  local escort: State.Mission? = nil
  for _, offer in Missions.Offers(state, home) do
    escort = if Missions.Escort(offer) and string.find(offer.key, ":war:", 1, true) then offer else escort
  end
  local tender = assert(escort, "no escort to the front is offered")
  t.eq({ tender.system, tender.aim, tender.kind, tender.faction, tender.level } :: { any }, { system, "escort", "assault", "vessari", 1 } :: { any })
  t.ok(tender.reward > 0 and tender.standing >= Missions.WAR_STANDING)
  t.eq(string.sub(Missions.Title(tender), 1, 19), "Escort to the front")
  -- (a station with nobody's force near has none: with the operation over, the offers are gone)
  local kept = table.remove(state.wars.operations)
  for _, offer in Missions.Offers(state, home) do
    t.ok(not (offer.kind == "bounty" and offer.type ~= ""), "a strike with no front to strike at")
  end
  table.insert(state.wars.operations, kept :: State.Operation)
  -- Taken, it counts the Talmar ships the pilot destroys at the lines, and no pirate, and nobody else's.
  job.id = State.NewId(state)
  job.taken = state.tick
  state.missions[job.id] = job
  table.insert(state.missionIds, job.id)
  local front = state.fronts[99]
  go(game, front.site)
  Core.Step(game)
  local destroyed = 0
  for id, record in front.ships do
    if record.side == "vessari" and destroyed == 0 then
      Aftermath.Destroy(state, id, state.player.ship, game.events)
      destroyed = 1
    end
  end
  t.eq(job.done, 0, "a Vessari ship counted toward a strike against the Talmar")
  for id, record in front.ships do
    if record.side == "talmar" and job.done < job.need and state.balls[id] then
      Aftermath.Destroy(state, id, state.player.ship, game.events)
    end
  end
  t.eq(job.done, math.min(job.need, 5))
  t.eq(operation.system, system)
end)

suite:Case("what a force has beyond its ships comes in as they are lost, a ship at a time", function(t)
  local game, _, operation = besieged(300, 90)
  local state = game.state
  local front = state.fronts[99]
  go(game, front.site)
  Core.Step(game)
  local function attackers(): number
    local count = 0
    for _, record in front.ships do
      count += if record.attacking then 1 else 0
    end
    return count
  end
  t.eq(attackers(), Fronts.SHIPS)
  local reserve = front.reserve
  t.ok(reserve >= 50, `a force of 300 has {reserve} in reserve`)
  -- (with every place taken, nobody comes)
  for _ = 1, 2 * Fronts.REINFORCE do
    Core.Step(game)
  end
  t.ok(front.reserve == reserve or attackers() < Fronts.SHIPS, "a ship came in with no room for it")
  -- One of them is lost: within a minute another is there, the biggest the reserve comes to, and the reserve is less by it.
  local before = front.reserve
  for id, record in front.ships do
    if record.attacking and attackers() == Fronts.SHIPS then
      Aftermath.Destroy(state, id, 0, game.events)
      front.ships[id] = nil
    end
  end
  local came = false
  for _ = 1, 2 * Fronts.REINFORCE do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      came = came or (event.kind == "FrontReinforced" and event.side == "vessari")
    end
  end
  t.ok(came, "nobody came in for a ship that was lost")
  t.ok(front.reserve <= before - 4, `the reserve was {before} and is {front.reserve}`)
  t.ok(operation.force <= 300)
end)

suite:Case("at a siege of a system of the pilot's own, the corporation's members who fight there are in it, in their own ships", function(t)
  local game, system, operation = besieged(120, 150)
  local state = game.state
  -- (the system is the pilot's, and the Vessari are at war with them)
  state.galaxy.systems[system].owner = "player"
  state.wars.claims[system] = "player"
  operation.against = "player"
  state.wars.feuds = { { a = "vessari", b = "player", since = state.tick, score = 0 } }
  local function fighter(name: string, hull: string, where: number): State.Member
    local member: State.Member = { id = State.NewId(state), name = name, trade = "fighter", people = "talmar", hull = hull, bears = 0.3,
      wealth = 0, earned = 0, paid = 0, joined = 0, system = where, doing = "hunting", call = 0, lean = 0, day = 0 }
    state.membership.members[member.id] = member
    table.insert(state.membership.memberIds, member.id)
    return member
  end
  local here = fighter("Ada Brook", "frigate.akashi", system)
  local away = fighter("Cal Dane", "frigate.akashi", 1)
  local miner = fighter("Ivo Marr", "frigate.courier", system)
  miner.trade = "miner"
  local front = state.fronts[99]
  go(game, front.site)
  Core.Step(game)
  -- One ship on the defending side: the member who fights and is working here, under their own name, for what they add.
  local defenders: { number } = {}
  for id, record in front.ships do
    if not record.attacking then
      table.insert(defenders, id)
      t.eq({ record.side, record.worth, state.ships[id].name, state.ships[id].owner, state.pilots[id].side } :: { any },
        { "player", Members.Stands(here), "Ada Brook", "member", "player" } :: { any })
    end
  end
  t.eq(#defenders, 1)
  t.eq(front.held, 150 - Members.Stands(here))
  t.ok(away.system == 1 and Members.Stands(miner) == 0)
  -- (it is one of the pilot's own, to whoever lists what is there)
  local own = false
  for _, entry in Core.Query.Overview(game) do
    own = own or (entry.id == defenders[1] and entry.own and not entry.hostile)
  end
  t.ok(own, "a member's ship is not shown as one of the pilot's side")
  -- It fights the besiegers, and they it.
  local at, by = 0, 0
  for _ = 1, 300 do
    Core.Step(game)
    for _, event in Core.TakeEvents(game) do
      if event.kind == "Shot" then
        at += if event.to == defenders[1] then 1 else 0
        by += if event.from == defenders[1] then 1 else 0
      end
    end
  end
  t.ok(at > 0 and by > 0, `the member's ship fired {by} times and was fired on {at} times`)
end)

return suite
