--!strict
-- Fronts: the factions' forces as ships, where the pilot is.
--
-- What the factions do about the open space between them is worked out
-- as quantities (Strategic/Wars): a force sent to a system, a garrison,
-- a relief, fighting a round a minute with nobody to be seen. The
-- project owner's ruling (2026-11-14) is that where the pilot is, the
-- fleets are really there, to fight beside or against. So:
--
--   - An operation that is past its muster in the system the pilot is
--     in has a place there, on the overview: the blockade's lines, or
--     the siege's.
--   - When the pilot comes to that place the two forces are put there
--     as ships: the hulls of the factions they are, as many as their
--     strength comes to (a battleship is worth fifty of it, a cruiser
--     sixteen, a frigate four; eight ships a side at most, and what is
--     over is in reserve, out of sight). They fight each other as any
--     ships fight. From then on the operation's strength is what its
--     ships are worth, and not what a round a minute would have left:
--     the fight the pilot sees is the fight.
--   - The pilot can take a hand. A ship of a side that the pilot (or
--     one of theirs) fires on is their enemy from then: that side's
--     ships go for them too, and that faction thinks the worse of them.
--     Each of its ships they destroy is paid for by the other side, if
--     there is one, which thinks the better of them.
--   - A force brought down to a fifth of what it came with gives way,
--     as it does unseen: so a pilot who destroys enough of a siege
--     breaks it, and one who destroys enough of the defence takes the
--     system for the besiegers.
--   - When the pilot leaves the place the ships are taken away, and
--     what they were worth goes on fighting unseen.
--
--   - At a siege of a system of the pilot's own there are no ships of
--     theirs but the ones that are: the pilot's, those of whoever flies
--     for them, and those of the corporation's members who fight and
--     are working in the system, each in their own hull under their
--     own name (Assets/Members).
--   - What a force has beyond its ships is its reserve, and comes in:
--     every so often a side that has room for another ship and reserve
--     enough for one has one more, the biggest its reserve comes to.
--
-- (First figures. Not yet: anything a pilot can do in a blockade but
-- fight.)

local Constants = require("@lt/Core/Data/Constants")
local Factions = require("@lt/Core/Data/Factions")
local Fellows = require("@lt/Core/Tactical/Fellows")
local Items = require("@lt/Core/Assets/Items")
local Members = require("@lt/Core/Assets/Members")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Rng = require("@lt/Core/Kernel/Rng")
local Ships = require("@lt/Core/Data/Ships")
local Sites = require("@lt/Core/Tactical/Sites")
local Space = require("@lt/Core/Tactical/Space")
local Standings = require("@lt/Core/Assets/Standings")
local State = require("@lt/Core/Kernel/State")
local Traffic = require("@lt/Core/Tactical/Traffic")
local Wallet = require("@lt/Core/Assets/Wallet")
local Wars = require("@lt/Core/Strategic/Wars")

local Fronts = {}

export type Event = { [string]: any }

-- What a ship of each class is worth of a force's strength, the biggest
-- first, and how many of each a side has at most; and how many ships a
-- side has in all.
Fronts.WORTH = { { class = "battleship", worth = 50, most = 2 }, { class = "cruiser", worth = 16, most = 3 },
  { class = "frigate", worth = 4, most = 8 } } :: { { class: string, worth: number, most: number } }
Fronts.SHIPS = 8
-- Ticks between one ship of a side's reserve coming in and the next.
Fronts.REINFORCE = math.ceil(45 / Constants.TICK)
-- The variety of a front's place.
Fronts.VARIETY = "site.front"
-- How far from the middle of the place each side is put, metres.
Fronts.APART = 14000
-- Ticks after the pilot has left the place that the ships are kept.
Fronts.LINGER = math.ceil(30 / Constants.TICK)
-- What a faction thinks the worse of a pilot who fires on its ships (once
-- a fight), and for each point of strength of its ships they destroy;
-- what the other side thinks the better of them for each point; and
-- the credits it pays for each.
Fronts.OFFENCE, Fronts.GRUDGE, Fronts.THANKS, Fronts.PAY = 0.5, 0.02, 0.01, 4000

-- The ships a strength comes to: their classes, and what is left over.
function Fronts.Muster(strength: number): ({ { class: string, worth: number } }, number)
  local ships: { { class: string, worth: number } } = {}
  local left = strength
  for _, kind in Fronts.WORTH do
    local count = 0
    -- (the big hulls only out of what there is plenty of: half of it at most)
    while count < kind.most and #ships < Fronts.SHIPS and left >= kind.worth
      and (kind.class == "frigate" or left >= 2 * kind.worth) do
      local one: { class: string, worth: number } = { class = kind.class, worth = kind.worth }
      table.insert(ships, one)
      left -= kind.worth
      count += 1
    end
  end
  return ships, left
end

local function operationOf(state: State.State, id: number): State.Operation?
  for _, operation in state.wars.operations do
    if operation.id == id then
      return operation
    end
  end
  return nil
end

-- Take a ship of a front away (it is not destroyed: nobody sees it go).
local function dismiss(state: State.State, id: number, events: { Event })
  -- (a member's own ship is theirs still: they are at their work again, Tactical/Fellows)
  local member = Members.Of(state, id)
  if member then
    member.ship, member.task = 0, ""
  end
  local ball = state.balls[id]
  if ball then
    Space.RemoveBall(state, ball)
    table.insert(events, { kind = "BallRemoved", ball = id, reason = "left" })
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

-- Take all of a front's ships away.
local function withdraw(state: State.State, front: State.Front, events: { Event })
  for id in front.ships do
    dismiss(state, id, events)
  end
  front.ships = {}
  front.shown = false
end

-- Put one ship of a side at a front: of a class, so far from the
-- front's middle on the side 'sign' says, at a place along its line.
-- Whether it could be (a faction that builds no such hull, and no
-- frigate, has none).
-- ('member': for a ship that is somebody's own and fights for a side
-- that builds none, a member of the pilot's corporation: it is their
-- own hull, and goes by their name.)
local function one(state: State.State, front: State.Front, place: any, side: string, attacking: boolean, class: string, worth: number,
  sign: number, along: number, rng: Rng.Rng, events: { Event }, member: State.Member?): boolean
  local kind = if member then Fellows.Kind(member) else Traffic.Warship(side, class) or Traffic.Warship(side, "frigate")
  if kind == nil then
    return false
  end
  local ship = Space.NewShip(state, kind.hull, kind.name, if member then "member" else side, 0)
  Pirates.Equip(state, ship, kind)
  if member then
    member.ship, member.task, member.goal, member.since = ship.id, "front", front.site, state.tick
  end
  local ball = Space.Launch(state, ship, front.system, place.x + sign * Fronts.APART + Rng.Float(rng, -2500, 2500),
    place.y + Rng.Float(rng, -2000, 2000), place.z + along * 1500)
  state.pilots[ship.id] = { ship = ship.id, range = kind.range, prey = 0, home = front.site, alone = 0, bounty = 0, tags = 0,
    side = side, worth = worth }
  State.InsertId(state.pilotIds, ship.id)
  front.ships[ship.id] = { side = side, worth = worth, attacking = attacking }
  table.insert(events, { kind = "BallAdded", ball = ball.id })
  return true
end

-- Put a side's ships at a front. Returns what is left over: its reserve.
local function field(state: State.State, front: State.Front, place: any, side: string, attacking: boolean, strength: number,
  sign: number, events: { Event }): number
  local ships, reserve = Fronts.Muster(strength)
  local rng = Rng.For(state.historySeed, front.operation, if attacking then 1 else 2, 907)
  for index, wanted in ships do
    if not one(state, front, place, side, attacking, wanted.class, wanted.worth, sign, index - #ships / 2, rng, events) then
      reserve += wanted.worth
    end
  end
  return reserve
end

-- A ship of a side's reserve comes in, if the side has room for one and
-- reserve enough: the biggest its reserve comes to. Returns the reserve
-- that is left.
local function reinforce(state: State.State, front: State.Front, place: any, side: string, attacking: boolean, reserve: number,
  events: { Event }): number
  local there = 0
  for _, record in front.ships do
    there += if record.attacking == attacking then 1 else 0
  end
  if side == "" or there >= Fronts.SHIPS then
    return reserve
  end
  for _, kind in Fronts.WORTH do
    if reserve >= kind.worth then
      local rng = Rng.For(state.historySeed, front.operation, state.tick, if attacking then 3 else 4, 909)
      if one(state, front, place, side, attacking, kind.class, kind.worth, if attacking then -1 else 1, Rng.Float(rng, -4, 4), rng, events) then
        table.insert(events, { kind = "FrontReinforced", site = front.site, side = side })
        return reserve - kind.worth
      end
      return reserve
    end
  end
  return reserve
end

-- Once a tick. 'first' is where this tick's events begin in 'events'.
function Fronts.Step(state: State.State, events: { Event }, first: number)
  local me = state.balls[state.player.ship]
  -- Fronts whose operation is over, or is somewhere the pilot is not.
  for index = #state.frontIds, 1, -1 do
    local front = state.fronts[state.frontIds[index]]
    local operation = operationOf(state, front.operation)
    if operation == nil or me == nil or me.system ~= front.system then
      if operation then
        operation.shown = nil
      end
      withdraw(state, front, events)
      Sites.Release(state, front.site, events)
      state.fronts[front.operation] = nil
      table.remove(state.frontIds, index)
    end
  end
  if me == nil then
    return
  end
  -- A place for every operation here that is past its muster.
  for _, operation in state.wars.operations do
    if operation.system == me.system and operation.stage ~= "muster" and state.fronts[operation.id] == nil then
      local site = Sites.Stake(state, me.system, Rng.For(state.historySeed, operation.id, 905),
        if operation.kind == "siege" then "Siege Lines" else "Blockade")
      if site then
        -- (a place of its own kind, to whoever names places: not a camp to clear)
        local lines = Space.Object(state, site.id)
        if lines then
          lines.variety = Fronts.VARIETY
        end
        state.fronts[operation.id] = { operation = operation.id, system = me.system, site = site.id, shown = false, ships = {},
          reserve = 0, held = 0, away = 0, crossed = {} }
        table.insert(state.frontIds, operation.id)
        table.insert(events, { kind = "FrontFound", site = site.id, system = me.system, by = operation.by, against = operation.against,
          siege = operation.kind == "siege" })
      end
    end
  end
  for _, id in state.frontIds do
    local front = state.fronts[id]
    local operation = operationOf(state, id) :: State.Operation
    local here = me.grid == front.site
    if here and not front.shown then
      -- The pilot has come: the forces are there.
      local place = Space.Object(state, front.site)
      if place then
        front.shown, front.away = true, 0
        operation.shown = true
        front.reserve = field(state, front, place, operation.by, true, operation.force, -1, events)
        -- (a system of the pilot's own has no ships but the pilot's, and
        -- whoever flies for them: its defence is what it is, unseen)
        front.held = if Factions.byId[operation.against] and operation.defence > 0
          then field(state, front, place, operation.against, false, operation.defence, 1, events) else operation.defence
        -- (and of the pilot's own, those of the corporation's members
        -- who fight and are working in the system are there, each in
        -- their own ship, for what they add to its defence: Assets/Members)
        if operation.against == Wars.PILOT then
          local rng = Rng.For(state.historySeed, front.operation, 911)
          local along = 0
          for _, member in Members.List(state) do
            local hull = Ships.byId[member.hull]
            -- (not one who has lost their ship and has not another yet)
            if member.trade == "fighter" and member.system == front.system and hull and state.tick >= member.refit then
              local worth = Members.Stands(member)
              along += 1
              if worth > 0 and front.held >= worth then
                -- (from wherever in the system they were: Tactical/Fellows)
                Members.Recall(state, member, events)
                if one(state, front, place, Wars.PILOT, false, hull.class, worth, 1, along, rng, events, member) then
                  front.held -= worth
                end
              end
            end
          end
        end
      end
    elseif front.shown then
      front.away = if here then 0 else front.away + 1
      -- What the pilot's side has done this tick: fired on a side, or destroyed one of its ships.
      for at = first, #events do
        local event = events[at]
        local shooter = if event.kind == "Shot" then state.ships[event.from] elseif event.kind == "BallDestroyed" then state.ships[event.by]
          else nil
        local victim = front.ships[if event.kind == "Shot" then event.to elseif event.kind == "BallDestroyed" then event.ball else 0]
        if shooter and victim and shooter.owner == "player" then
          if not front.crossed[victim.side] then
            front.crossed[victim.side] = true
            Standings.Change(state, victim.side, -Fronts.OFFENCE, events)
            table.insert(events, { kind = "FrontCrossed", site = front.site, side = victim.side })
          end
          if event.kind == "BallDestroyed" then
            local other = if victim.attacking then operation.against else operation.by
            Standings.Change(state, victim.side, -Fronts.GRUDGE * victim.worth, events)
            -- (nobody pays the pilot for defending what is their own: Assets/Sovereignty)
            if Factions.byId[other] then
              Standings.Change(state, other, Fronts.THANKS * victim.worth, events)
              Wallet.Pay(state, Fronts.PAY * victim.worth, `war bounty, {Factions.byId[other].name}`, events)
            end
          end
        end
      end
      -- (what each side has in reserve comes in, a ship at a time)
      local place = Space.Object(state, front.site)
      if place and state.tick % Fronts.REINFORCE == 0 then
        front.reserve = reinforce(state, front, place, operation.by, true, front.reserve, events)
        if operation.defence > 0 then
          front.held = reinforce(state, front, place, operation.against, false, front.held, events)
        end
      end
      -- (the defence has given way, by the round's reckoning: what is left of it goes)
      if operation.defence <= 0 then
        front.held = 0
        for ship, record in front.ships do
          if not record.attacking then
            dismiss(state, ship, events)
            front.ships[ship] = nil
          end
        end
      end
      -- (a relief sent since the last reckoning is the defence's, behind its ships)
      if front.last and operation.defence > front.last then
        front.held += operation.defence - front.last
      end
      -- What each force is worth now: its ships that are left, and its reserve.
      local force, defence = front.reserve, front.held
      for ship, record in front.ships do
        if state.balls[ship] == nil then
          front.ships[ship] = nil
        else
          if front.crossed[record.side] then
            state.pilots[ship].foe = true
          end
          if record.attacking then
            force += record.worth
          else
            defence += record.worth
          end
        end
      end
      operation.force, operation.defence = force, defence
      front.last = defence
      if front.away > Fronts.LINGER then
        operation.shown = nil
        withdraw(state, front, events)
      end
    end
  end
end

return Fronts
