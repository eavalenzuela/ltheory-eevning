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
-- (First figures. Not yet: the reserve coming in as ships are lost;
-- ships warping in when a relief is sent; anything a pilot can do in a
-- blockade but fight.)

local Constants = require("@lt/Core/Data/Constants")
local Factions = require("@lt/Core/Data/Factions")
local Items = require("@lt/Core/Assets/Items")
local Pirates = require("@lt/Core/Tactical/Pirates")
local Rng = require("@lt/Core/Kernel/Rng")
local Sites = require("@lt/Core/Tactical/Sites")
local Space = require("@lt/Core/Tactical/Space")
local Standings = require("@lt/Core/Assets/Standings")
local State = require("@lt/Core/Kernel/State")
local Traffic = require("@lt/Core/Tactical/Traffic")
local Wallet = require("@lt/Core/Assets/Wallet")

local Fronts = {}

export type Event = { [string]: any }

-- What a ship of each class is worth of a force's strength, the biggest
-- first, and how many of each a side has at most; and how many ships a
-- side has in all.
Fronts.WORTH = { { class = "battleship", worth = 50, most = 2 }, { class = "cruiser", worth = 16, most = 3 },
  { class = "frigate", worth = 4, most = 8 } } :: { { class: string, worth: number, most: number } }
Fronts.SHIPS = 8
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

-- Put a side's ships at a front: so far from its middle, on the side
-- 'sign' says.
local function field(state: State.State, front: State.Front, place: any, side: string, attacking: boolean, strength: number,
  sign: number, events: { Event }): number
  local ships, reserve = Fronts.Muster(strength)
  local rng = Rng.For(state.historySeed, front.operation, if attacking then 1 else 2, 907)
  for index, wanted in ships do
    local kind = Traffic.Warship(side, wanted.class) or Traffic.Warship(side, "frigate")
    if kind == nil then
      reserve += wanted.worth
      continue
    end
    local ship = Space.NewShip(state, kind.hull, kind.name, side, 0)
    Pirates.Equip(state, ship, kind)
    local ball = Space.Launch(state, ship, front.system, place.x + sign * Fronts.APART + Rng.Float(rng, -2500, 2500),
      place.y + Rng.Float(rng, -2000, 2000), place.z + (index - #ships / 2) * 1500)
    state.pilots[ship.id] = { ship = ship.id, range = kind.range, prey = 0, home = front.site, alone = 0, bounty = 0, tags = 0,
      side = side, worth = wanted.worth }
    State.InsertId(state.pilotIds, ship.id)
    front.ships[ship.id] = { side = side, worth = wanted.worth, attacking = attacking }
    table.insert(events, { kind = "BallAdded", ball = ball.id })
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
        front.held = if operation.against ~= "" and operation.defence > 0
          then field(state, front, place, operation.against, false, operation.defence, 1, events) else operation.defence
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
            if other ~= "" then
              Standings.Change(state, other, Fronts.THANKS * victim.worth, events)
              Wallet.Pay(state, Fronts.PAY * victim.worth, `war bounty, {Factions.byId[other].name}`, events)
            end
          end
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
      if front.away > Fronts.LINGER then
        operation.shown = nil
        withdraw(state, front, events)
      end
    end
  end
end

return Fronts
